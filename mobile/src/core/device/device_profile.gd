class_name DeviceProfile
extends RefCounted

## 一台手柄的完整设备档案：轴映射 + 校准 + 探针质量 + 布局建议。
##
## **不存设备序号。** 官方文档明确 `get_connected_joypads()` 的顺序在重启后不保证
## 一致，存下来迟早会错位到另一台手柄。身份只用 `key`（guid 优先、否则规范化设备名）。
##
## 复用门是纯函数：`can_reuse()` 先要求「这份档案本身可用」（`can_enter_practice()`），
## 再比较本次实测的四个 index+sign。四项逐项相等才采用整份档案（含它的校准）；
## 只要有一项不同 —— 哪怕只是符号 —— 就必须整份丢弃、重跑四步探针。
## **绝不部分应用**：「同名手柄 + 错误映射」在这里必须返回 false。
##
## 为什么还要一条「档案自洽门」：04-09 的真机上，量程没推满时按 A 会把
## `scale=1.0 / center=0` 写成一份看起来完全合法的档案；四项比较对着它自己是真，
## 但那份「校准」等于没校准。`quality.range_ready == true` 是 04-11 之后新档案的
## 标记，旧档案（缺这个键、或它是 false）一律不可复用，用户会重新看到设置页。
##
## `profile_id` 是 INPUT-03 的预留字段：本阶段固定 "primary"（单档案），但字段与
## 序列化必须存在，将来多档案（例如一人一手柄）不需要改 schema。
##
## `probed_at_iso` 只承载字符串：墙钟由外层填（core 不读 Time.），排障用，不参与判定。
##
## **schema v2（D-06）**：本阶段补上左摇杆的轴对、符号与校准。`ProfileStore.load_all()`
## 对非法条目是整份丢弃，所以升版会删掉全部 v1 档案 —— 用户需要重走一次设置页
## （约 20 秒）。这是一次性代价，比「进练习后四个 `relative_to_ls` 动作全无反应」
## 便宜得多。版本号不能悄悄回退：回退会让已写入的 v2 档案被旧版拒绝。

const SCHEMA_VERSION := 2
const LAYOUT_XBOX := &"xbox"
const LAYOUT_PLAYSTATION := &"playstation"
## 校准半量程的下限直接复用 `Calibration.MIN_SCALE`（0.5）：低于它是「只推到一半
## 就保存了」，归一化之后摇杆永远说不出「推到底」。上限 1.0 由 `Calibration` 自己夹住。
## 中点的绝对值上限：超过 0.5 的「中点」不是中点，是一只被按住的摇杆。
const MAX_CALIBRATION_CENTER := 0.5

var schema_version: int = SCHEMA_VERSION
## `guid:...` 或 `name:...`；由 make_key() 生成，始终与下面两个字段并存便于人工核对。
var key: String = ""
## INPUT-03 预留：单档案阶段固定 "primary"。
var profile_id: String = "primary"
var device_name: String = ""
var device_guid: String = ""
var axes: AxisMapping = null
var calibration: Calibration = null
## 探针质量：四步各自的 samples / margin / separation。内容不做 schema 校验，
## 避免把「探针指标」写死成档案格式的一部分。
var quality: Dictionary = {}
## 空 StringName = 没有建议；调用方必须让用户二选一，绝不预选。
var layout: StringName = &""
var layout_confirmed: bool = false
var button_index_ok: bool = true
var probed_at_iso: String = ""


## guid 非空就用 guid（大小写不敏感），否则退回规范化设备名。
static func make_key(device_guid: String, device_name: String) -> String:
	var guid := device_guid.strip_edges().to_lower()
	if not guid.is_empty():
		return "guid:" + guid
	return "name:" + device_name.strip_edges().to_lower()


## 这份档案能不能直接进练习（不比较本次观测值）。
##
## 「看起来有档案、其实不能用」的情况都在这里被拦下：没有 rs 映射、没有**左摇杆**
## 映射（`ls = -1` 的 04 阶段档案会让四个 `relative_to_ls` 技能静默失效）、没有校准、
## 没有确认过布局、校准是默认值（半量程 < 0.5 或中点越界）、量程从未推满
## （`quality.range_ready` 缺失或不为 true）、左摇杆从未确认
## （`quality.ls_ready` 缺失或不为 true）。组合根与 `can_reuse()` 共用这一扇门，
## 避免两处各写一份判定后分叉。
func can_enter_practice() -> bool:
	if axes == null or not axes.has_rs():
		return false
	if not axes.has_ls():
		return false
	if calibration == null:
		return false
	if layout == &"" or not layout_confirmed:
		return false
	if calibration.scale_x < Calibration.MIN_SCALE:
		return false
	if calibration.scale_y < Calibration.MIN_SCALE:
		return false
	if absf(calibration.center_x) > MAX_CALIBRATION_CENTER:
		return false
	if absf(calibration.center_y) > MAX_CALIBRATION_CENTER:
		return false
	if not _range_ready_marker():
		return false
	return _ls_ready_marker()


## 复用门：先过 `can_enter_practice()`，再要求四个 index+sign 逐项相等。
##
## **不比较校准的具体数值**：复用时整份采用档案里的校准，`center/scale` 只要落在
## 合理区间（见上）就够；拿档案自己的校准去比自己是假绿。`rest` 也不参与 ——
## 它只是探针阶段的临时基线。
func can_reuse(observed_rs_x_index: int, observed_rs_x_sign: int,
		observed_rs_y_index: int, observed_rs_y_sign: int) -> bool:
	if not can_enter_practice():
		return false
	return (
		axes.rs_x_index == observed_rs_x_index
		and axes.rs_x_sign == observed_rs_x_sign
		and axes.rs_y_index == observed_rs_y_index
		and axes.rs_y_sign == observed_rs_y_sign
	)


## 新档案的标记：`quality.range_ready` 必须是布尔 true。
##
## 旧档案（04-09 / 04-10 在量程未满时保存的那一份）要么没有这个键，要么是 false；
## 两者都必须拒绝 —— 那是「默认校准」唯一的可机械识别的痕迹。
func _range_ready_marker() -> bool:
	var marker: Variant = quality.get("range_ready")
	return typeof(marker) == TYPE_BOOL and bool(marker)


## 左摇杆的保存时事实标记：`quality.ls_ready` 必须是布尔 true。
##
## 与 `_range_ready_marker()` 同构，对应 T-05-19 / T-05-20：04 阶段的档案要么没有
## 这个键（`ls = -1`），要么它不是布尔；两者都必须拒绝。`has_ls()` 另守一条边 ——
## 有人手工把 `ls_ready` 写成 true 但 ls 索引仍是 -1 时，自相矛盾的档案不能放行。
func _ls_ready_marker() -> bool:
	var marker: Variant = quality.get("ls_ready")
	return typeof(marker) == TYPE_BOOL and bool(marker)


## 只按小写设备名匹配；认不出就返回空（无建议，绝不静默落默认值）。
##
## 「Xbox Wireless Controller」同时含 xbox 与 wireless controller，xbox 先判。
static func suggest_layout(device_name: String) -> StringName:
	var lowered := device_name.strip_edges().to_lower()
	if lowered.contains("xbox"):
		return LAYOUT_XBOX
	for token in ["dualsense", "dualshock", "wireless controller", "playstation", "ps4", "ps5"]:
		if lowered.contains(token):
			return LAYOUT_PLAYSTATION
	return &""


func to_dict() -> Dictionary:
	return {
		"schema_version": schema_version,
		"key": key,
		"profile_id": profile_id,
		"device_name": device_name,
		"device_guid": device_guid,
		"axes": axes.to_dict() if axes != null else {},
		"calibration": calibration.to_dict() if calibration != null else {},
		"quality": quality,
		"layout": String(layout),
		"layout_confirmed": layout_confirmed,
		"button_index_ok": button_index_ok,
		"probed_at_iso": probed_at_iso,
	}


## 从 JSON 还原档案。**任何一项不合法 → 整份丢弃**（返回 null + 至少一条 ConfigError）。
##
## 绝不部分恢复、绝不静默用默认值补：一份坏档案最坏的结果必须是「要求重探」，
## 而不是「带着错误轴映射进入练习」。所有取值先用 typeof() 判断再转换；JSON 的
## 整数会被解析成 float，所以数值字段同时接受 TYPE_INT 与 TYPE_FLOAT。
static func from_dict(data: Variant, out_errors: Array[ConfigError]) -> DeviceProfile:
	var before := out_errors.size()
	if typeof(data) != TYPE_DICTIONARY:
		_error(out_errors, "$", &"profile_not_object",
			"设备档案必须是 JSON 对象，收到 %s" % JSON.stringify(data),
			"检查文件是否被截断；顶层必须是 { ... }。")
		return null
	var root: Dictionary = data
	var profile := DeviceProfile.new()

	var version: Variant = root.get("schema_version")
	if not _is_number(version) or float(version) != float(SCHEMA_VERSION):
		_error(out_errors, "$.schema_version", &"unsupported_schema",
			"schema_version 必须是 %d，收到 %s" % [SCHEMA_VERSION, JSON.stringify(version)],
			"改成 %d；未知版本必须整份丢弃，不做猜测迁移。" % SCHEMA_VERSION)
	else:
		profile.schema_version = SCHEMA_VERSION

	profile.key = _read_text(root, "key", "$.key", false, out_errors)
	profile.profile_id = _read_text(root, "profile_id", "$.profile_id", false, out_errors)
	profile.device_name = _read_text(root, "device_name", "$.device_name", false, out_errors)
	profile.device_guid = _read_text(root, "device_guid", "$.device_guid", true, out_errors)

	profile.axes = AxisMapping.from_dict(root.get("axes"), out_errors)
	profile.calibration = Calibration.from_dict(root.get("calibration"), out_errors)

	var quality: Variant = root.get("quality")
	if typeof(quality) != TYPE_DICTIONARY:
		_error(out_errors, "$.quality", &"quality_not_object",
			"quality 必须是对象，收到 %s" % JSON.stringify(quality),
			"补上 {} 或探针质量对象；内容不做校验。")
	else:
		profile.quality = quality

	var layout: Variant = root.get("layout")
	if typeof(layout) != TYPE_STRING:
		_error(out_errors, "$.layout", &"layout_not_string",
			"layout 必须是字符串，收到 %s" % JSON.stringify(layout),
			"写成 \"xbox\"、\"playstation\" 或 \"\"（无建议）。")
	elif layout == "":
		profile.layout = &""
	elif layout == "xbox":
		profile.layout = LAYOUT_XBOX
	elif layout == "playstation":
		profile.layout = LAYOUT_PLAYSTATION
	else:
		_error(out_errors, "$.layout", &"layout_unknown",
			"layout 只能是 \"xbox\" / \"playstation\" / \"\"，收到 %s" % JSON.stringify(layout),
			"改成三个合法值之一；布局只影响屏幕上显示的键名。")

	profile.layout_confirmed = _read_bool(root, "layout_confirmed", out_errors)
	profile.button_index_ok = _read_bool(root, "button_index_ok", out_errors)
	profile.probed_at_iso = _read_text(root, "probed_at_iso", "$.probed_at_iso", true, out_errors)

	if out_errors.size() > before:
		return null
	return profile


## 非空文本字段。allow_empty = true 时允许空串（device_guid / probed_at_iso）。
static func _read_text(root: Dictionary, field: String, path: String, allow_empty: bool,
		out: Array[ConfigError]) -> String:
	if not root.has(field):
		_error(out, path, &"missing_field",
			"缺少 %s 字段" % field, "补上 %s。" % field)
		return ""
	var raw: Variant = root[field]
	if typeof(raw) != TYPE_STRING:
		_error(out, path, &"string_expected",
			"%s 必须是字符串，收到 %s" % [field, JSON.stringify(raw)],
			"写成不带引号以外的形式，例如 \"Xbox Series X Controller\"。")
		return ""
	var value: String = raw
	if not allow_empty and value.strip_edges().is_empty():
		_error(out, path, &"empty_field",
			"%s 不能为空" % field, "补上非空值；空值无法定位设备档案。")
		return ""
	return value


static func _read_bool(root: Dictionary, field: String, out: Array[ConfigError]) -> bool:
	var path := "$." + field
	if not root.has(field):
		_error(out, path, &"missing_field",
			"缺少 %s 字段" % field, "补上 true 或 false。")
		return false
	var raw: Variant = root[field]
	if typeof(raw) != TYPE_BOOL:
		_error(out, path, &"bool_expected",
			"%s 必须是布尔值，收到 %s" % [field, JSON.stringify(raw)],
			"写 true 或 false（不要加引号）；字符串 \"true\" 不是布尔值。")
		return false
	return raw


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


static func _error(out: Array[ConfigError], path: String, code: StringName,
		message: String, fix_hint: String) -> void:
	out.append(ConfigError.new(path, code, message, fix_hint))
