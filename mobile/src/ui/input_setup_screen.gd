extends Control

## 一页式输入设置：一屏看完 8 根轴、一个右摇杆圆点、量程与中点，全部操作都在手柄上。
##
## 为什么是「一页」而不是「四步」：用户 2026-11-05 两次真机失败的原话是
## 「一直显示重来重来重来」「检测方式就有问题，没有任何容错」，随后明确要求
## 「不要用这种一步，这种进步式的测试。你要不你就做成一个页面。就不要有状态改变，
## 我可以反复地测。」。因此本文件里**没有**步骤计数、没有倒计时、没有时间窗口、
## 没有自动失败、没有「重来」屏：页面从可见到按 A 之间一直在采样。
##
## 职责边界：
##   * 采样与识别全部在 `InputSetup`（纯逻辑，零引擎依赖）；本屏只做格式化与按键分派；
##   * 按键边沿由组合根（`main.gd`）唯一消费后调用 `handle_button()` —— 同一次按下
##     不能有两个解释者；
##   * 本屏**不碰** `TapRuntime`、不产生任何 `Outcome`，只写 `ProfileStore`（按 A 时）。
##
## 轴对、符号、量程都是「用户看着屏幕确认」的：轴对由推摇杆得出（也可 LB/RB 手选），
## 符号由圆点方向决定（X/Y 翻转），量程没推够只显示「还没推到底」。自动识别结果
## 绝不静默落盘 —— 唯一的写档案入口是 A。

## 按 A 保存成功后通知组合根进入练习。参数是档案里的布局，空值时由组合根兜底。
signal profile_saved(layout: StringName)

const AXIS_COUNT := 8
const DOT_SIZE := 240.0
const MARKER_SIZE := 14.0
## 圆点可走的最大半径：留 20 px 边距，推到最外圈时点不会压到边框上。
const DOT_MARGIN := 20.0
## 文本刷新 10 Hz：Label 赋值会触发文本整形，60 Hz 下是全帧最贵的操作。
const REFRESH_SECONDS := 0.1
## 轴表里标「正在动」的最近峰峰值门槛：静止噪声在 ±0.02 内。
const MOVING_SPAN := 0.05

const TITLE_TEXT := "输入设置"
const HELP_TEXT := "A 保存并开始    B 清空重来    X 反转 X    Y 反转 Y    LB/RB 换轴对"
const NO_DEVICE_HELP := "打开手柄电源 → 长按配对键 → 在系统蓝牙里选择它 → 按手柄任意键唤醒"

@onready var _title: Label = %Title
@onready var _axes: Label = %Axes
@onready var _dot: Panel = %Dot
## 圆点不是 `unique_name_in_owner`：一页里只有这 10 个唯一节点（UI 契约），
## 圆点是 `%Dot` 的内部构件，用路径取。
@onready var _marker: Panel = $Dot/Marker
@onready var _pair: Label = %Pair
@onready var _signs: Label = %Signs
@onready var _range: Label = %Range
@onready var _center: Label = %Center
@onready var _trigger: Label = %Trigger
@onready var _help: Label = %Help
@onready var _footer: Label = %Footer

var _sampler: PadSampler = null
var _store: ProfileStore = null
var _setup := InputSetup.new()
var _accum: float = 0.0
## 上一次刷新时算好的文本；相同就不赋值（隐式节流，与练习屏同一条约定）。
var _last_axes_text: String = ""
## 一次性提示（保存失败 / 已清空）。下一次按键就清掉，不会盖住操作行。
var _notice: String = ""
var _had_device: bool = false


func _ready() -> void:
	pass


## 依赖唯一入口。组合根在 `add_child(_sampler)` 之后、任何采样之前调用。
func setup(p_sampler: PadSampler, p_store: ProfileStore) -> void:
	_sampler = p_sampler
	_store = p_store
	reset_stats()


## 换设备 / 断连时清空统计。两种情况下旧数据都属于另一只手柄，
## 留着只会让下一条轴对看起来像是这一只手柄的。
func reset_stats() -> void:
	_setup.reset()
	_notice = ""
	_last_axes_text = ""
	_accum = REFRESH_SECONDS
	if _marker != null:
		_marker.visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	if _sampler == null:
		return
	if _sampler.buffer.device < 0:
		_render_no_device()
		return
	_had_device = true
	var values := _axis_values()
	# 每帧都要 observe：轴对识别用的是「最近 1 秒的帧」，不是「最近一次刷新」。
	_setup.observe(values)
	_move_marker(values)
	_accum += delta
	if _accum < REFRESH_SECONDS:
		return
	_accum = 0.0
	_refresh()


## 组合根分派的按键边沿。索引同 `JoyButton`：A=0 B=1 X=2 Y=3 LB=9 RB=10。
func handle_button(index: int) -> void:
	if not visible:
		return
	# LB+RB 是诊断覆盖层的组合键（按住 0.8 秒）。同时按住时不当成换轴对，
	# 否则「打开诊断」会顺手改掉用户刚选好的那一对。
	if _sampler != null and _sampler.buffer.button_down(9) and _sampler.buffer.button_down(10):
		return
	_notice = ""
	match index:
		0:
			_save_and_enter()
		1:
			reset_stats()
			_notice = "已清空：重新推右摇杆，页面会重新认轴对"
		2:
			_setup.toggle_x_sign()
		3:
			_setup.toggle_y_sign()
		9:
			_setup.cycle_pair(-1)
		10:
			_setup.cycle_pair(1)
	_accum = REFRESH_SECONDS
	_refresh()


## A：写档案并进练习。**唯一的写盘入口**，而且只在用户亲手按下时发生。
##
## 两个前置条件都只给提示、不改变页面状态：没有手柄、还没有认出轴对。
## 后者不是「判定失败」，而是「没有可保存的映射」—— 存一份 rs 索引为 -1 的档案，
## 下次启动会被 `ProfileStore.load_all()` 整份丢弃。
func _save_and_enter() -> void:
	if _sampler == null or _sampler.buffer.device < 0:
		_notice = "没有检测到手柄：按手柄任意键唤醒后再按 A"
		return
	if _setup.active_pair() == InputSetup.PAIR_NONE:
		_notice = "先推一下右摇杆：认出一对轴之后才能保存"
		return
	var device_name := _sampler.device_name()
	if device_name.strip_edges().is_empty():
		# `DeviceProfile` 要求 device_name 非空；空名字写进去，下次启动会被
		# `from_dict` 判非法并整份丢弃 —— 用户会莫名其妙回到这一页。
		device_name = "未知手柄"
	var profile := _setup.build_profile(device_name, _sampler.device_guid(),
		Time.get_datetime_string_from_system())
	var err := _store.upsert(profile)
	if err != OK:
		_notice = "档案写入失败（错误码 %d）：按 A 再试一次" % err
		return
	_notice = ""
	profile_saved.emit(profile.layout)


## 1 Hz 的 logcat 取样行（纯 ASCII）：真机上没有 run-as 时，这一行就是「页面认了哪一对、
## 符号是什么、量程到没到」的可核对原文。
func debug_line() -> String:
	var pair := _setup.active_pair()
	var span_x := _setup.axis_span(pair.x) if pair != InputSetup.PAIR_NONE else 0.0
	var span_y := _setup.axis_span(pair.y) if pair != InputSetup.PAIR_NONE else 0.0
	return "pair=%d/%d sign=%d/%d ready=%d span=%.2f/%.2f rest4=%.2f rest5=%.2f" % [
		pair.x, pair.y, _setup.x_sign(), _setup.y_sign(),
		1 if _setup.range_ready() else 0, span_x, span_y,
		_setup.trigger_rest(4), _setup.trigger_rest(5),
	]


func _axis_values() -> PackedFloat32Array:
	var values := PackedFloat32Array()
	values.resize(AXIS_COUNT)
	for axis in AXIS_COUNT:
		values[axis] = _sampler.buffer.axis_value(axis)
	return values


## 圆点：当前轴对的原始值 × 用户确认的符号。Y 不翻转 —— SDL 的 y 本来就是下正，
## 屏幕坐标也是下正，两边同向才谈得上「圆点方向和手柄一致」。
func _move_marker(values: PackedFloat32Array) -> void:
	var pair := _setup.active_pair()
	if pair == InputSetup.PAIR_NONE:
		_marker.visible = false
		return
	_marker.visible = true
	var x := clampf(values[pair.x] * float(_setup.x_sign()), -1.0, 1.0)
	var y := clampf(values[pair.y] * float(_setup.y_sign()), -1.0, 1.0)
	var area := Vector2(DOT_SIZE, DOT_SIZE)
	if _dot != null and _dot.size.x > 0.0 and _dot.size.y > 0.0:
		area = _dot.size
	var radius_x := maxf(0.0, area.x * 0.5 - DOT_MARGIN)
	var radius_y := maxf(0.0, area.y * 0.5 - DOT_MARGIN)
	_marker.position = Vector2(
		area.x * 0.5 + x * radius_x - MARKER_SIZE * 0.5,
		area.y * 0.5 + y * radius_y - MARKER_SIZE * 0.5)


func _refresh() -> void:
	var pair := _setup.active_pair()
	_set_text(_title, TITLE_TEXT)
	var axes_text := _axes_text()
	if axes_text != _last_axes_text:
		_last_axes_text = axes_text
		_set_text(_axes, axes_text)
	_set_text(_pair, pair_text(pair))
	_set_text(_signs, signs_text(_setup.x_sign(), _setup.y_sign()))
	_set_text(_range, range_text(pair, _setup.axis_range(pair.x), _setup.axis_range(pair.y)))
	_set_text(_center, center_text(pair, _setup.center()))
	_set_text(_trigger, trigger_text(_setup.trigger_rest(4), _setup.trigger_rest(5)))
	_set_text(_help, HELP_TEXT if _notice.is_empty() else "%s\n%s" % [HELP_TEXT, _notice])
	_set_text(_footer, _footer_text())


func _axes_text() -> String:
	var lines := PackedStringArray()
	for axis in AXIS_COUNT:
		lines.append(axis_line(axis, _setup.axis_last(axis), _setup.axis_range(axis),
			_setup.recent_range(axis) >= MOVING_SPAN))
	return "\n".join(lines)


func _render_no_device() -> void:
	if _had_device:
		_had_device = false
		reset_stats()
	_set_text(_title, "没有检测到手柄")
	_set_text(_axes, "")
	_set_text(_pair, "先按手柄任意键唤醒")
	_set_text(_signs, "")
	_set_text(_range, "")
	_set_text(_center, "")
	_set_text(_trigger, "")
	_set_text(_help, NO_DEVICE_HELP)
	_set_text(_footer, "设备：未连接")
	_marker.visible = false


func _footer_text() -> String:
	if _sampler == null or _sampler.buffer.device < 0:
		return "设备：未连接"
	return "设备：%s" % _sampler.device_name()


static func axis_line(axis: int, value: float, span: Vector2, moving: bool) -> String:
	var mark := ">" if moving else " "
	var name := "轴 %d" % axis
	if InputSetup.TRIGGER_AXES.has(axis):
		name = "轴 %d（扳机）" % axis
	var text := "%s %s %s %6.2f   min %6.2f  max %6.2f" % [
		mark, name, bar(value), value, span.x, span.y]
	if InputSetup.TRIGGER_AXES.has(axis):
		text += "  rest %6.2f" % span.x
	return text


## 一维条形图：-1..+1 映射到 10 格，中点在第 5 格。
static func bar(value: float) -> String:
	var filled := clampi(int(roundf((clampf(value, -1.0, 1.0) + 1.0) * 5.0)), 0, 10)
	return "[" + "=".repeat(filled) + "-".repeat(10 - filled) + "]"


static func pair_text(pair: Vector2i) -> String:
	if pair == InputSetup.PAIR_NONE:
		return "轴对：还没认出（推一下右摇杆）"
	return "轴对：%d / %d（按 LB/RB 换）" % [pair.x, pair.y]


static func signs_text(x_sign: int, y_sign: int) -> String:
	return "X：%s（按 X 切换）    Y：%s（按 Y 切换）" % [
		_sign_word(x_sign), _sign_word(y_sign)]


static func range_text(pair: Vector2i, span_x: Vector2, span_y: Vector2) -> String:
	if pair == InputSetup.PAIR_NONE:
		return "量程：等轴对认出来"
	return "量程：X %+.2f..%+.2f %s    Y %+.2f..%+.2f %s" % [
		span_x.x, span_x.y, _ready_word(span_x.y - span_x.x),
		span_y.x, span_y.y, _ready_word(span_y.y - span_y.x)]


static func center_text(pair: Vector2i, center: Vector2) -> String:
	if pair == InputSetup.PAIR_NONE:
		return "中点：等轴对认出来"
	return "中点：%.2f / %.2f" % [center.x, center.y]


static func trigger_text(rest_lt: float, rest_rt: float) -> String:
	return "扳机静止：%.2f / %.2f（取观测到的最小值）" % [rest_lt, rest_rt]


static func _sign_word(sign: int) -> String:
	return "反向" if sign < 0 else "正常"


static func _ready_word(span: float) -> String:
	return "✓" if span >= InputSetup.RANGE_READY else "还没推到底"


## 只在文本真的变化时赋值：Label.text 会触发文本整形，等同一次隐式节流。
func _set_text(label: Label, text: String) -> void:
	if label.text == text:
		return
	label.text = text
