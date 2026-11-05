extends Control

## D1/D2 的**证据出口**：一页零交互、零判定、只读的诊断文本，靠
## `adb exec-out screencap -p` 拍照取证。
##
## 为什么需要它：release APK 不可调试（`run-as: package not debuggable`），
## `controllers.json` 的读取与改写通道在真机上根本不存在。D1「轴探测落盘」和
## D2「换手柄必须重探」不能靠源码静态检查冒充 —— 证据必须来自这台手机。屏上覆盖层
## 是唯一一条既不需要 debuggable 构建、也不需要第二只手柄的出口。
##
## 三条硬约束：
##   1. **只读，不删档。** 读的是 `ProfileStore.PROFILES_PATH` 的**原始字节**，
##      绝不调用 `ProfileStore.load_all()` —— 那个函数对损坏文件会删档，而损坏的
##      文件正是要拍下来的证据。解析失败就显示「解析失败」，不补默认值冒充真档案。
##   2. **零 Outcome。** 覆盖层自身不推进任何判定：组合根在打开时把运行时的布局
##      确认置为 false（静默 `abandon()` 并清空未取走的结果），覆盖层可见期间
##      `_process` 早退、不 tick 运行时。屏幕上出现的判定只能来自真实尝试。
##   3. **字段逐字来自源头。** 档案页的每个字段都来自 JSON 原文，事件页的每个
##      计数器都来自 `PadStateBuffer`；本文件不做任何「翻译成好看的词」。
##
## 排版：22 px（调试面字号，正式屏不得引用），每行不超过 `MAX_LINE_CHARS` 个字符。
## `autowrap_mode = 0` 意味着超宽的行会被**直接裁掉**，截图证据就少一半 —— 「每行
## 不超宽」不是审美要求，是取证要求，`test_onboarding_ui` 逐行断言它。

const PAGE_PROFILES := 0
const PAGE_EVENTS := 1
const PAGE_COUNT := 2
## 1280 px 宽、22 px 字号下大约能放 100 个字符；超了就被裁，不是换行。
const MAX_LINE_CHARS := 100
## 1 Hz：诊断面看的是「稳定下来之后的数」，不是逐帧动画；顺带把多一次 JSON
## 解析的代价摊到每秒一次。
const REFRESH_SECONDS := 1.0
## 解析失败时附带的原始字节长度。分成两行写，保证每行不超宽。
const RAW_PREVIEW_CHARS := 160
const RAW_PREVIEW_SPLIT := 80

@onready var _panel: Label = %Panel

var _page: int = 0
var _accum: float = 0.0
var _buffer: PadStateBuffer = null
var _sampler: PadSampler = null
var _cached_raw: String = ""
var _cached_trigger: Dictionary = {}


func _ready() -> void:
	pass


## 依赖唯一入口。组合根在 `add_child()` 之后调用 —— 此时 `@onready` 已经解析。
func setup(p_buffer: PadStateBuffer, p_sampler: PadSampler) -> void:
	_buffer = p_buffer
	_sampler = p_sampler
	_page = PAGE_PROFILES
	refresh()


func page() -> int:
	return _page


func next_page() -> void:
	_page = posmod(_page + 1, PAGE_COUNT)
	refresh()


func prev_page() -> void:
	_page = posmod(_page - 1, PAGE_COUNT)
	refresh()


## 重新读一次原始档案并重画当前页。
##
## 读文件用 `FileAccess.get_file_as_string()`：文件不存在时返回空串，不建目录、
## 不删档。这条路径与 `ProfileStore` 的读路径刻意不同，理由见类文档第 1 条。
func refresh() -> void:
	_cached_raw = FileAccess.get_file_as_string(ProfileStore.PROFILES_PATH)
	_cached_trigger = _trigger_from_raw(_cached_raw)
	var in_tid := _sampler.input_thread_id if _sampler != null else 0
	var proc_tid := _sampler.process_thread_id if _sampler != null else 0
	_panel.text = page_text(_page, _cached_raw, _buffer, in_tid, proc_tid, _cached_trigger)


## 由组合根每帧调用；可见时 1 Hz 刷新，不可见时什么都不做。
func tick(delta: float) -> void:
	if not visible:
		return
	_accum += delta
	if _accum < REFRESH_SECONDS:
		return
	_accum = 0.0
	refresh()


## 从原始字节里挑出「这台手柄」的扳机条目。
##
## 优先取 `device_name` 与当前绑定设备相同的那一条，否则取排序后的第一条：
## 现场只有一只手柄时这就是同一份；将来两只手柄同时连着时，至少有一条确定规则，
## 而不是「随便挑一个」。解析失败或没有条目一律返回空字典，由 `format_events`
## 显示「未记录」—— 绝不拿 0.0 冒充真实静止值。
##
## 1 Hz 下多解析一次 JSON 是可接受的代价，换来 `format_events` 保持纯函数、
## 可以在无头环境里逐字段断言。
func _trigger_from_raw(raw: String) -> Dictionary:
	if raw.is_empty() or _sampler == null:
		return {}
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var root: Dictionary = parsed
	var entries: Dictionary = _dict(root.get("profiles"))
	if entries.is_empty():
		return {}
	var keys: Array = entries.keys()
	keys.sort()
	var wanted := _sampler.device_name()
	var chosen: Dictionary = {}
	for key in keys:
		var candidate: Dictionary = _dict(entries[key])
		if candidate.is_empty():
			continue
		if _text(candidate, "device_name", "") == wanted:
			chosen = candidate
			break
	if chosen.is_empty():
		for key in keys:
			var candidate: Dictionary = _dict(entries[key])
			if not candidate.is_empty():
				chosen = candidate
				break
	if chosen.is_empty():
		return {}
	var axes: Dictionary = _dict(chosen.get("axes"))
	var lt: Dictionary = _dict(axes.get("lt"))
	var rt: Dictionary = _dict(axes.get("rt"))
	return {
		"lt_index": _int(lt.get("index"), -1),
		"lt_rest": _number(lt.get("rest"), 0.0),
		"rt_index": _int(rt.get("index"), -1),
		"rt_rest": _number(rt.get("rest"), 0.0),
	}


## 当前页的全文。两个静态函数之外的唯一分派点。
static func page_text(page: int, raw: String, buffer: PadStateBuffer, in_tid: int,
		proc_tid: int, trigger: Dictionary) -> String:
	if page == PAGE_EVENTS:
		return format_events(buffer, in_tid, proc_tid, trigger)
	return format_profiles(raw)


## 档案页：`controllers.json` 的每个字段都给出落点。
##
## 输出顺序按 `profiles` 字典的**排序后** key：同一份文件永远得到同一段文本，
## 截图与无头断言才能逐字比对。
static func format_profiles(raw: String) -> String:
	if raw.is_empty():
		return "档案：controllers.json 尚未生成（走完引导并进入练习后才会写入）"
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		return _corrupt_text(raw)
	var root: Dictionary = parsed
	var entries: Variant = root.get("profiles")
	if typeof(entries) != TYPE_DICTIONARY:
		return _corrupt_text(raw)
	var map: Dictionary = entries
	if map.is_empty():
		return "档案：文件存在但没有条目"
	var keys: Array = map.keys()
	keys.sort()
	var lines: Array[String] = ["档案页（第 1/2 页）  user://profiles/controllers.json"]
	var index := 0
	for key in keys:
		var entry: Dictionary = _dict(map[key])
		if entry.is_empty():
			continue
		index += 1
		lines.append(_profile_block(index, str(key), entry))
	return "\n".join(lines)


## 事件页：四个计数器 + 三个分位数 + 两个线程号 + 每轴 min/max + 扳机静止值。
##
## `buffer == null` 时不抛错，用全 0 的安全分支 —— 诊断屏白屏比数字难看更糟。
static func format_events(buffer: PadStateBuffer, in_tid: int, proc_tid: int,
		trigger: Dictionary) -> String:
	var ev_m := 0
	var ev_b := 0
	var poll := 0
	var dt50 := 0.0
	var dt95 := 0.0
	var dtmax := 0.0
	var samples := 0
	if buffer != null:
		ev_m = buffer.events_motion
		ev_b = buffer.events_button
		poll = buffer.poll_edges
		var stats := buffer.delta_ms_percentiles()
		dt50 = _number(stats.get("p50"), 0.0)
		dt95 = _number(stats.get("p95"), 0.0)
		dtmax = _number(stats.get("max"), 0.0)
		samples = _int(stats.get("count"), 0)

	var lines: Array[String] = ["事件页（第 2/2 页）"]
	lines.append("计数器 ev_m=%d ev_b=%d poll=%d" % [ev_m, ev_b, poll])
	lines.append("间隔ms dt50=%.2f dt95=%.2f dtmax=%.2f（样本 %d）" % [dt50, dt95, dtmax, samples])
	lines.append("线程 in_tid=%d proc_tid=%d" % [in_tid, proc_tid])
	if trigger.is_empty():
		lines.append("扳机：未记录（档案尚未生成）")
	else:
		var lt_index := _int(trigger.get("lt_index"), -1)
		var rt_index := _int(trigger.get("rt_index"), -1)
		var lt_value := buffer.axis_value(lt_index) if buffer != null else 0.0
		var rt_value := buffer.axis_value(rt_index) if buffer != null else 0.0
		lines.append("扳机 LT 轴 %d v=%.3f rest=%.3f | RT 轴 %d v=%.3f rest=%.3f" % [
			lt_index, lt_value, _number(trigger.get("lt_rest"), 0.0),
			rt_index, rt_value, _number(trigger.get("rt_rest"), 0.0),
		])
	for axis in PadStateBuffer.MAX_AXIS:
		var value := 0.0
		var span := Vector2.ZERO
		if buffer != null:
			value = buffer.axis_value(axis)
			span = buffer.axis_range(axis)
		lines.append("轴 %d v=%.3f min=%.3f max=%.3f" % [axis, value, span.x, span.y])
	return "\n".join(lines)


## 一份档案的 8 行。**字段名的唯一落点**：`format_profiles` 只负责遍历与拼接，
## 不要再在那里抄一遍字段名。
##
## 每个字段都用 `Dictionary.get()` 读并给默认值：档案半坏时诊断屏也不能白屏。
static func _profile_block(index: int, outer_key: String, entry: Dictionary) -> String:
	var prefix := "P%d " % index
	var axes: Dictionary = _dict(entry.get("axes"))
	var calibration: Dictionary = _dict(entry.get("calibration"))
	var quality: Dictionary = _dict(entry.get("quality"))
	var rs_x: Dictionary = _dict(axes.get("rs_x"))
	var rs_y: Dictionary = _dict(axes.get("rs_y"))
	var ls_x: Dictionary = _dict(axes.get("ls_x"))
	var ls_y: Dictionary = _dict(axes.get("ls_y"))
	var lt: Dictionary = _dict(axes.get("lt"))
	var rt: Dictionary = _dict(axes.get("rt"))
	var rows: Array[String] = [
		prefix + "外层key=" + outer_key + "  schema=" + str(_int(entry.get("schema_version"), 0))
			+ "  profile_id=" + _text(entry, "profile_id", ""),
		prefix + "name=" + _text(entry, "device_name", "") + "  guid=" + _text(entry, "device_guid", ""),
		prefix + "axes rs_x=(%d,%d) rs_y=(%d,%d) ls_x=(%d,%d) ls_y=(%d,%d)" % [
			_int(rs_x.get("index"), -1), _int(rs_x.get("sign"), 1),
			_int(rs_y.get("index"), -1), _int(rs_y.get("sign"), 1),
			_int(ls_x.get("index"), -1), _int(ls_x.get("sign"), 1),
			_int(ls_y.get("index"), -1), _int(ls_y.get("sign"), 1),
		],
		prefix + "axes lt=(%d,rest=%.3f) rt=(%d,rest=%.3f)" % [
			_int(lt.get("index"), -1), _number(lt.get("rest"), 0.0),
			_int(rt.get("index"), -1), _number(rt.get("rest"), 0.0),
		],
		prefix + "cal center=(%.3f,%.3f) scale=(%.3f,%.3f)" % [
			_number(calibration.get("center_x"), 0.0),
			_number(calibration.get("center_y"), 0.0),
			_number(calibration.get("scale_x"), 1.0),
			_number(calibration.get("scale_y"), 1.0),
		],
		prefix + "layout=" + _text(entry, "layout", "") + " confirmed="
			+ _bool_word(entry.get("layout_confirmed"))
			+ " btn_idx_ok=" + _bool_word(entry.get("button_index_ok")),
		prefix + "probed=" + _text(entry, "probed_at_iso", ""),
		prefix + _quality_row(quality),
	]
	return "\n".join(rows)


## 「q up=(samples,margin,separation) right=… down=… left=…」，缺项打印 `-`。
static func _quality_row(quality: Dictionary) -> String:
	var parts: Array[String] = []
	for key in ["up", "right", "down", "left"]:
		parts.append("%s=%s" % [key, _quality_entry(_dict(quality.get(key)))])
	return "q " + " ".join(parts)


static func _quality_entry(entry: Dictionary) -> String:
	if entry.is_empty():
		return "-"
	return "(%d,%.2f,%.2f)" % [
		_int(entry.get("samples"), 0),
		_number(entry.get("margin"), 0.0),
		_number(entry.get("separation"), 0.0),
	]


## 解析失败时的证据文本：第一行说结论，后面两行是原始字节的前 160 个字符。
## 分成 80 + 80 两行是因为 `autowrap_mode = 0`：一行超过 100 个字符会被直接裁掉。
static func _corrupt_text(raw: String) -> String:
	var preview := raw.substr(0, RAW_PREVIEW_CHARS)
	var head := preview.substr(0, RAW_PREVIEW_SPLIT)
	var tail := preview.substr(RAW_PREVIEW_SPLIT)
	if tail.is_empty():
		return "档案解析失败：%s" % head
	return "档案解析失败：%s\n%s" % [head, tail]


static func _dict(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


static func _text(entry: Dictionary, key: String, fallback: String) -> String:
	var value: Variant = entry.get(key, fallback)
	if typeof(value) == TYPE_STRING:
		return value
	return fallback


static func _int(value: Variant, fallback: int) -> int:
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return int(float(value))
	return fallback


static func _number(value: Variant, fallback: float) -> float:
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return float(value)
	return fallback


static func _bool_word(value: Variant) -> String:
	return "true" if typeof(value) == TYPE_BOOL and bool(value) else "false"
