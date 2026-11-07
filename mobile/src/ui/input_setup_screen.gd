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
## 按键分工（04-11 真机实测之后重排）：**X / Y 在本页没有任何功能** —— 它们与练习
## 手势里的「按住 RB 连按两下 X」撞车，真机上还误把 X 的符号翻成了反向。符号翻转
## 改到十字键（左右翻 X、上下翻 Y），布局切换在 Start，A 只负责保存。
##
## 轴对、符号、量程、布局都是「用户看着屏幕确认」的：轴对由推摇杆得出（也可 LB/RB
## 手选），符号由圆点方向决定（十字键翻转），量程没推够只显示「还没推到底」，布局
## 由 Start 切换、A 确认。自动识别结果绝不静默落盘 —— 唯一的写档案入口是 A，
## 而且只在 `InputSetup.can_save()` 为真时。

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

## 按键索引取自 Godot 的 `JoyButton` 枚举，不手写数字：真机牙刷手法与不同手柄的
## 索引差异只能靠枚举名对齐，写死 13/14 迟早会在另一把手上错位。
const KEY_A := JoyButton.JOY_BUTTON_A
const KEY_B := JoyButton.JOY_BUTTON_B
const KEY_LB := JoyButton.JOY_BUTTON_LEFT_SHOULDER
const KEY_RB := JoyButton.JOY_BUTTON_RIGHT_SHOULDER
const KEY_DPAD_UP := JoyButton.JOY_BUTTON_DPAD_UP
const KEY_DPAD_DOWN := JoyButton.JOY_BUTTON_DPAD_DOWN
const KEY_DPAD_LEFT := JoyButton.JOY_BUTTON_DPAD_LEFT
const KEY_DPAD_RIGHT := JoyButton.JOY_BUTTON_DPAD_RIGHT
const JOY_BUTTON_START := JoyButton.JOY_BUTTON_START

## 按键语义的唯一名字表。X / Y（2 / 3）**刻意没有**对应动作 —— 它们属于练习手势。
const ACTION_SAVE := &"save"
const ACTION_CLEAR := &"clear"
const ACTION_X_SIGN := &"x_sign"
const ACTION_Y_SIGN := &"y_sign"
const ACTION_PAIR_PREV := &"pair_prev"
const ACTION_PAIR_NEXT := &"pair_next"
const ACTION_LAYOUT := &"layout"
const ACTION_NONE := &""

const TITLE_TEXT := "输入设置"
const HELP_TEXT := "A 保存并开始    B 清空重来    十字键左右翻 X / 上下翻 Y    LB/RB 换轴对    Start 换布局"
const NO_DEVICE_HELP := "打开手柄电源 → 长按配对键 → 在系统蓝牙里选择它 → 按手柄任意键唤醒"
## 量程没推满时按 A 的唯一回应：只说这一句、只改 `%Help`，不写档案、不切屏。
const RANGE_NOT_READY_HELP := "量程还没推满：把右摇杆往四个方向各推到底几次"
## 左摇杆（D-06）的三句提示。全部只改 `%Help`，不新增页面 / 步骤 / 按键。
const LS_NOT_READY_HELP := "左摇杆还没推满：把左摇杆往四个方向各推到底几次"
const LS_ARM_UP_HELP := "推一下左摇杆：向上（确认方向没接反）"
const LS_ARM_RIGHT_HELP := "推一下左摇杆：向右"
## 向上推却推成左右：明确说清楚，绝不静默把 X 的位移当成 Y 的符号。
const LS_SIDEWAYS_HELP := "推的是左右，请向上推"
## 松手重臂的阈值：位移回到 0.1 以下并持续 0.25 s，就重新取基线。
const LS_ARM_IDLE_DELTA := 0.1
const LS_ARM_IDLE_SECONDS := 0.25
## 底部固定提示：日志不随 B 清空，测试者按完可以直接用 adb 取。
const LOG_HINT := "日志：files/input_log.txt（按 B 清空本页，不删日志）"

@onready var _title: Label = %Title
@onready var _axes: Label = %Axes
@onready var _dot: Panel = %Dot
## 圆点不是 `unique_name_in_owner`：一页里只有这 11 个唯一节点（UI 契约），
## 圆点是 `%Dot` 的内部构件，用路径取。
@onready var _marker: Panel = $Dot/Marker
@onready var _pair: Label = %Pair
@onready var _signs: Label = %Signs
@onready var _layout: Label = %Layout
@onready var _range: Label = %Range
@onready var _center: Label = %Center
@onready var _trigger: Label = %Trigger
@onready var _ls: Label = %Ls
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
## 松手重臂的累计时间：位移回到阈值以下多久（秒）。
var _ls_arm_idle: float = 0.0


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
	_ls_arm_idle = 0.0
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
	# 左摇杆的符号确认也在每帧推进：它依赖位移基线，不能等到 10 Hz 的文本刷新。
	_auto_confirm_ls(delta)
	_move_marker(values)
	_accum += delta
	if _accum < REFRESH_SECONDS:
		return
	_accum = 0.0
	_refresh()


## 同一页、零新按键地确认左摇杆符号：轴对认出来之后自动摆臂，用户只要按提示推。
##
## 两次摆臂的顺序固定为「先向上、再向右」：Y 先确认（向上推不涉及左右歧义），
## X 后确认（向右推）。符号只在成功时改；推成左右时 `ls_arm_result()` 为 sideways，
## 页面把提示换成 `LS_SIDEWAYS_HELP`，下一帧继续重新摆臂，用户再推一次即可。
##
## 松手重臂：用户「推住不放看提示」时，基线一直停在按下那一刻，永远采不到完整位移。
## 这里只在位移回到 0.1 以下时累计时间，满 0.25 s 重新取基线 —— 松手再推一次即可。
func _auto_confirm_ls(delta: float) -> void:
	if _setup.ls_pair() == InputSetup.PAIR_NONE:
		_ls_arm_idle = 0.0
		return
	if not _setup.ls_arm_pending():
		_ls_arm_idle = 0.0
		if not _setup.has_ls_y_sign():
			_setup.arm_ls_up()
		elif not _setup.has_ls_x_sign():
			_setup.arm_ls_right()
		return
	if _setup.ls_arm_delta_len() < LS_ARM_IDLE_DELTA:
		_ls_arm_idle += delta
		if _ls_arm_idle >= LS_ARM_IDLE_SECONDS:
			_ls_arm_idle = 0.0
			if not _setup.has_ls_y_sign():
				_setup.arm_ls_up()
			elif not _setup.has_ls_x_sign():
				_setup.arm_ls_right()
	else:
		_ls_arm_idle = 0.0


## 组合根分派的按键边沿。索引同 `JoyButton`：A=0 B=1 X=2 Y=3 LB=9 RB=10
## DPAD 上/下/左/右=11/12/13/14 Start=6。
##
## X / Y（2 / 3）**没有分支**：它们与「按住 RB 连按两下 X」的练习手势撞车，
## 真机上还误翻了 X 的符号。符号改由十字键翻转，布局由 Start 切换。
func handle_button(index: int) -> void:
	if not visible:
		return
	# LB+RB 是诊断覆盖层的组合键（按住 0.8 秒）。同时按住时不当成换轴对，
	# 否则「打开诊断」会顺手改掉用户刚选好的那一对。
	if _sampler != null and _sampler.buffer.button_down(KEY_LB) \
			and _sampler.buffer.button_down(KEY_RB):
		return
	_notice = ""
	match action_for_button(index):
		ACTION_SAVE:
			_save_and_enter()
		ACTION_CLEAR:
			reset_stats()
			_notice = "已清空：重新推右摇杆，页面会重新认轴对"
		ACTION_X_SIGN:
			_setup.toggle_x_sign()
		ACTION_Y_SIGN:
			_setup.toggle_y_sign()
		ACTION_PAIR_PREV:
			_setup.cycle_pair(-1)
		ACTION_PAIR_NEXT:
			_setup.cycle_pair(1)
		ACTION_LAYOUT:
			_setup.cycle_layout(_device_name())
	_accum = REFRESH_SECONDS
	_refresh()


## 按键语义的纯函数：无头套件直接断言「X / Y 返回 ACTION_NONE」，
## 不需要实例化场景，也不需要真机。
static func action_for_button(index: int) -> StringName:
	match index:
		KEY_A:
			return ACTION_SAVE
		KEY_B:
			return ACTION_CLEAR
		KEY_DPAD_LEFT, KEY_DPAD_RIGHT:
			return ACTION_X_SIGN
		KEY_DPAD_UP, KEY_DPAD_DOWN:
			return ACTION_Y_SIGN
		KEY_LB:
			return ACTION_PAIR_PREV
		KEY_RB:
			return ACTION_PAIR_NEXT
		JOY_BUTTON_START:
			return ACTION_LAYOUT
	return ACTION_NONE


## A：写档案并进练习。**唯一的写盘入口**，而且只在用户亲手按下时发生。
##
## 前置条件按「先 RS 后 LS」的顺序逐条提示、不改变页面状态：没有手柄、还没有认出
## RS 轴对、RS 量程没推满、LS 轴对没认出、LS 符号/量程没就绪。最后两条是 D-06 的
## 新门：缺 LS 的档案会让四个 relative_to_ls 技能静默失效。`can_save()` 为假时
## **不调用 `build_profile`、不调用 `upsert`** —— 那是这道门唯一的实现位置。
func _save_and_enter() -> void:
	if _sampler == null or _sampler.buffer.device < 0:
		_notice = "没有检测到手柄：按手柄任意键唤醒后再按 A"
		return
	if _setup.active_pair() == InputSetup.PAIR_NONE:
		_notice = "先推一下右摇杆：认出一对轴之后才能保存"
		return
	if not _setup.range_ready():
		_notice = RANGE_NOT_READY_HELP
		return
	if _setup.ls_pair() == InputSetup.PAIR_NONE:
		_notice = LS_NOT_READY_HELP
		return
	if not _setup.ls_ready():
		if _setup.ls_arm_result() == &"sideways":
			_notice = LS_SIDEWAYS_HELP
		elif _setup.has_ls_y_sign():
			_notice = LS_ARM_RIGHT_HELP
		else:
			_notice = LS_ARM_UP_HELP
		return
	if not _setup.can_save():
		_notice = RANGE_NOT_READY_HELP
		return
	var device_name := _device_name()
	if device_name.strip_edges().is_empty():
		# `DeviceProfile` 要求 device_name 非空；空名字写进去，下次启动会被
		# `from_dict` 判非法并整份丢弃 —— 用户会莫名其妙回到这一页。
		device_name = "未知手柄"
	# A 确认布局：这是 `layout_confirmed` 唯一的置真路径。
	_setup.mark_layout_confirmed()
	var profile := _setup.build_profile(device_name, _sampler.device_guid(),
		Time.get_datetime_string_from_system())
	if profile == null:
		# can_save() 已为真时不可达；真到了这里也只提示，绝不落盘一份默认校准。
		_notice = RANGE_NOT_READY_HELP
		return
	var err := _store.upsert(profile)
	if err != OK:
		_notice = "档案写入失败（错误码 %d）：按 A 再试一次" % err
		return
	_notice = ""
	profile_saved.emit(profile.layout)


## 1 Hz 的 logcat 取样行（纯 ASCII）：真机上没有 run-as 时，这一行就是「页面认了哪一对、
## 符号是什么、量程到没到、左摇杆是否就绪、布局是什么」的可核对原文。
##
## `rs=` 是**冻结值**，`pair=` 是当前活动轴对：D5-1 的判据就是「rs=2/3、ls=0/1、
## ls_ready=1」三处同时出现，而 `pair=` 允许已经翻到 0/1。
func debug_line() -> String:
	var pair := _setup.active_pair()
	var rs := _setup.rs_pair()
	var ls := _setup.ls_pair()
	var span_x := _setup.axis_span(pair.x) if pair != InputSetup.PAIR_NONE else 0.0
	var span_y := _setup.axis_span(pair.y) if pair != InputSetup.PAIR_NONE else 0.0
	return ("rs=%d/%d pair=%d/%d sign=%d/%d ready=%d span=%.2f/%.2f rest4=%.2f rest5=%.2f"
		+ " ls=%d/%d ls_sign=%d/%d ls_ready=%d layout=%s confirmed=%d") % [
		rs.x, rs.y, pair.x, pair.y, _setup.x_sign(), _setup.y_sign(),
		1 if _setup.range_ready() else 0, span_x, span_y,
		_setup.trigger_rest(4), _setup.trigger_rest(5),
		ls.x, ls.y, _setup.ls_x_sign(), _setup.ls_y_sign(),
		1 if _setup.ls_ready() else 0,
		String(_setup.layout_cycle(_device_name())), 1 if _setup.layout_confirmed() else 0,
	]


## 设备名是布局建议的唯一输入；没有设备时给空串（`_layout_for` 会落到 Xbox）。
func _device_name() -> String:
	if _sampler == null or _sampler.buffer.device < 0:
		return ""
	return _sampler.device_name()


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
	_set_text(_layout, layout_text(_setup.layout_cycle(_device_name())))
	_set_text(_range, range_text(pair, _setup.axis_range(pair.x), _setup.axis_range(pair.y)))
	_set_text(_center, center_text(pair, _setup.center()))
	_set_text(_trigger, trigger_text(_setup.trigger_rest(4), _setup.trigger_rest(5)))
	var ls := _setup.ls_pair()
	_set_text(_ls, ls_text(ls, _setup.ls_x_sign(), _setup.ls_y_sign(),
		_setup.axis_range(ls.x) if ls != InputSetup.PAIR_NONE else Vector2.ZERO,
		_setup.axis_range(ls.y) if ls != InputSetup.PAIR_NONE else Vector2.ZERO,
		_setup.ls_ready()))
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
	_set_text(_layout, "")
	_set_text(_range, "")
	_set_text(_center, "")
	_set_text(_trigger, "")
	_set_text(_ls, "")
	_set_text(_help, NO_DEVICE_HELP)
	_set_text(_footer, "设备：未连接")
	_marker.visible = false


func _footer_text() -> String:
	if _sampler == null or _sampler.buffer.device < 0:
		return "设备：未连接\n%s" % LOG_HINT
	return "设备：%s\n%s" % [_sampler.device_name(), LOG_HINT]


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
	return "X：%s（十字键左右翻）    Y：%s（十字键上下翻）" % [
		_sign_word(x_sign), _sign_word(y_sign)]


## 布局行：只显示当前值 + 两个操作入口。确认是 A 的副作用 —— 屏幕上不再出现
## 「布局已确认」这种无法撤销的状态，用户永远知道现在是什么、按什么能改。
static func layout_text(layout: StringName) -> String:
	return "布局：%s（按 Start 切换，按 A 确认）" % _layout_word(layout)


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


## 左摇杆行：与右摇杆的「轴对 / 符号 / 量程」同构，另加一个保存时事实 ✓。
##
## 未识别时不显示 0/0 这种猜出来的值，而是明说「推一下」—— 与 `pair_text()` 同一纪律。
static func ls_text(pair: Vector2i, x_sign: int, y_sign: int,
		span_x: Vector2, span_y: Vector2, ready: bool) -> String:
	if pair == InputSetup.PAIR_NONE:
		return "左摇杆：还没认出（推一下）"
	var ready_mark := "✓" if ready else "还没推到底"
	return "左摇杆：轴 %d/%d  符号 %s/%s  量程 %.2f/%.2f %s" % [
		pair.x, pair.y, _sign_letter(x_sign), _sign_letter(y_sign),
		span_x.y - span_x.x, span_y.y - span_y.x, ready_mark]


static func _sign_letter(sign: int) -> String:
	return "+" if sign > 0 else "-"


static func _sign_word(sign: int) -> String:
	return "反向" if sign < 0 else "正常"


## 布局的显示名。只有两个合法值：xbox / playstation（空值由 `_layout_for` 兜底成
## Xbox），所以这里不需要第三个分支，也不显示内部枚举名。
static func _layout_word(layout: StringName) -> String:
	return "PlayStation" if layout == DeviceProfile.LAYOUT_PLAYSTATION else "Xbox"


static func _ready_word(span: float) -> String:
	return "✓" if span >= InputSetup.RANGE_READY else "还没推到底"


## 只在文本真的变化时赋值：Label.text 会触发文本整形，等同一次隐式节流。
func _set_text(label: Label, text: String) -> void:
	if label.text == text:
		return
	label.text = text
