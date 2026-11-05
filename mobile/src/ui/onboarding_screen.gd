extends Control

## 引导屏 S1–S11 的渲染器：只做三件事 —— 读 `flow.state` 刷新文案、把采样窗口
## 喂给纯函数、把纯函数结果回填给 `flow`。
##
## 它**不是**第二个状态机：按键边沿由组合根唯一消费后调用 `flow` 的方法，本屏
## 不碰边沿数组、也不直接读设备轴；轴值一律走 `PadSampler.buffer.axis_value()`，
## 设备名与 guid 走 `sampler.device_name()` / `device_guid()`。
##
## `_ready()` 只缓存 `@onready` 节点，不读注入对象：子节点的 `_ready` 先于
## `main._ready` 执行，这时 `setup()` 还没发生。首次渲染由 `setup()` 负责。
##
## 采样窗口按状态切分，样本数即倒计时（不读时钟，无头与真机行为一致）：
##   * 静止基线 18 帧（约 0.3 s @60 Hz）
##   * 四步探针每步 18 帧；开始前先等「相对静止基线的位移 ≥ 0.5」
##   * 中点校准 24 帧；满量程校准四个方向各 24 帧
## 校准屏只能通过 `flow.mapping()` + `AxisMapping.raw_rs()` 把 raw 转成 Vector2，
## 绝不硬编码轴号。
##
## **D0 停止条件**：等待推杆时若本状态已累计 ≥ 60 帧、且期间没有新增任何摇杆
## 事件（`events_motion` 不增长），屏幕必须明确说「没有收到摇杆事件」并停止提交。
## 不允许用全零窗口驱动评估 —— 那只会产出一条误导性的「位移不够」。

const REST_FRAMES := 18
const STEP_FRAMES := 18
const CALIBRATE_FRAMES := 24
const CALIBRATE_RANGE_DIRS := 4
## 开始收探针窗口的位移门槛：低于它就是「还没推」。
const PUSH_THRESHOLD := 0.5
## 静止基线期间任一轴峰峰值超过它：用户没松手。
const REST_PEAK_LIMIT := 0.15
## 等待推杆的看门狗帧数（约 1 s @60 Hz）。
const MOTION_STOP_FRAMES := 60
const AXIS_COUNT := 8
## 实时读数的门槛与刷新频率。
##
## 门槛 0.2 是「这根轴确实被推动了」的最小位移：静止噪声在 ±0.02 内，0.2 已经
## 是噪声的十倍，不会把抖动念成「轴 N 的正方向」。
##
## 刷新 10 Hz 而不是每帧：`Label.text` 赋值触发文本整形，60 Hz 下是全帧最贵的
## 操作；读数只需要人眼跟得上，10 Hz 已经比人反应快。
const READOUT_MIN_DELTA := 0.2
const READOUT_REFRESH_SECONDS := 0.1


## 方向键 → 中文方位词。屏幕上的每个方向词都从这里来，测试才能逐条断言。
static func direction_word(key: StringName) -> String:
	match key:
		&"up":
			return "上"
		&"right":
			return "右"
		&"down":
			return "下"
		&"left":
			return "左"
	return "这个方向"


## 实时读数：**app 到底收到了什么**。
##
## 逐轴算 `raw - rest` 的位移，取绝对值最大的那根轴，显示它的序号、正负方向与
## **有符号**位移。用户看到「轴 2 的负方向（-0.98）」就能对上自己推的方向，
## 而不是只看到一句「位移不够」。
##
## **不得**在这里断言哪根轴是 X 还是 Y：轴序号只能由探针给出（INPUT-02）。
## 屏幕说「轴 2」是诚实的；说「右摇杆 X 轴」是猜的，猜错就会把用户带进沟里。
##
## `rest` 为空（静止基线还没采）时按 0 处理：此时读数仍然有意义 —— 它显示的是
## 原始轴值本身。
static func live_readout(raw: PackedFloat32Array, rest: PackedFloat32Array) -> String:
	var winner := -1
	var winner_delta := 0.0
	for axis in raw.size():
		var baseline := rest[axis] if axis < rest.size() else 0.0
		var delta := raw[axis] - baseline
		if absf(delta) > absf(winner_delta):
			winner = axis
			winner_delta = delta
	if winner < 0 or absf(winner_delta) < READOUT_MIN_DELTA:
		return "你推的是：没有推动（最大变化 %.2f）" % absf(winner_delta)
	var sign_word := "正方向" if winner_delta > 0.0 else "负方向"
	return "你推的是：轴 %d 的%s（%.2f）" % [winner, sign_word, winner_delta]


## 拒绝原因 → 人话动作句（第一行）。技术数值（margin / 轴号 / 符号）只作为
## 第二行或 logcat 出现，绝不当成唯一内容。
##
## `attempt` 是「这是第几次机会」：大于 0 时句尾写「（第 n/2 次机会）」；等于 0
## 表示两次软重试已经用完、这次是真失败，写「（已经试了 2 次仍不对）」。
static func plain_rejection(code: StringName, key: StringName, attempt: int) -> String:
	var word := direction_word(key)
	var sentence := ""
	match code:
		&"ambiguous_axes":
			sentence = "只推「%s」这一个方向：别的方向先松开" % word
		&"not_enough_travel":
			sentence = "推得不够远：把右摇杆推到「%s」到底再按住" % word
		&"not_enough_samples":
			sentence = "松得太快：推到「%s」后保持不动约 0.3 秒" % word
		_:
			sentence = "这一步没测出来：把右摇杆推到「%s」到底再按住" % word
	if attempt > 0:
		return sentence + "（第 %d/2 次机会）" % attempt
	return sentence + "（已经试了 2 次仍不对）"


## 交叉校验失败 → 先告诉用户「你刚才推的方向不像「右」」，再说清为什么。
##
## 三个交叉码是四个方向之间的**一致性**问题，不是单手推歪：用户很可能每一步都
## 自己觉得推对了。所以第一句先否定方向判断，第二句才说轴的关系，最后给下一步。
static func cross_check_plain(code: StringName, key: StringName) -> String:
	match code:
		&"same_axis_up_right":
			return "你刚才推的方向不像「右」：上和右落在了同一根轴上，这把手的右摇杆可能没有独立的左右轴。先松开，再只把右摇杆推到「右」到底按住。"
		&"vertical_not_opposed":
			return "你刚才推的方向不像「下」：上和下的符号没有相反，推下时轴变化的方向和推上一样。先松开，再只把右摇杆推到「下」到底按住。"
		&"horizontal_not_opposed":
			return "你刚才推的方向不像「左」：左和右的符号没有相反，推左时轴变化的方向和推右一样。先松开，再只把右摇杆推到「左」到底按住。"
	var word := direction_word(key)
	return "你刚才推的方向不像「%s」：先松开，再只把右摇杆推到「%s」到底按住。" % [word, word]


## 停止屏：报的是**本步增量**，不是累计总数。
##
## D0 的旧文案把「本状态 1 秒内没有新事件」念成「本机从没送上任何摇杆事件」，
## 与同一时段的 `PAD_DIAG ev_m=2633` 自相矛盾，用户当然看不明白。增量语义不会
## 撒谎：它只说这一步开始之后有没有新事件。
static func stop_message(delta: int, total: int) -> String:
	return "本步开始后新增 %d 个摇杆事件（累计 %d）。本机可能不发送轴事件，请记录并停止（D0 判失败）" % [
		delta, total]


@onready var _title: Label = %Title
@onready var _step: Label = %Step
@onready var _body: Label = %Body
@onready var _big_hint: Label = %BigHint
@onready var _hint: Label = %Hint
@onready var _meter: ProgressBar = %Meter
@onready var _options: Label = %Options
@onready var _footer: Label = %Footer

var _flow: OnboardingFlow = null
var _sampler: PadSampler = null
var _last_state: StringName = &""
## 探针/复验的合成窗口：每帧 8 根轴的 raw 值。
var _window: Array[PackedFloat32Array] = []
## 校准的 raw 二元组；中点与量程分开存。
var _center_samples: Array[Vector2] = []
var _range_samples: Array[Vector2] = []
var _range_dir: int = 0
var _range_dir_frames: int = 0
var _center: Vector2 = Vector2.ZERO
var _frames_in_state: int = 0
var _motion_at_state_start: int = 0
var _motion_stop: bool = false
## 最近一次算好的实时读数；10 Hz 节流更新，渲染只读它。
var _readout: String = ""
var _readout_accum: float = 0.0
## 已经打进 logcat 的拒绝码：同一个码只打一行，换码就打新的一行。
var _logged_reject_code: StringName = &""



func _ready() -> void:
	pass


## 注入依赖。主场景在 `add_child(_sampler)` 之后调用；此前本屏不读任何状态。
func setup(p_flow: OnboardingFlow, p_sampler: PadSampler) -> void:
	_flow = p_flow
	_sampler = p_sampler
	_enter_state(_flow.state)
	_refresh()


func _process(delta: float) -> void:
	if _flow == null or not visible:
		return
	if _flow.state != _last_state:
		_enter_state(_flow.state)
	_refresh_readout(delta)
	_advance()
	_refresh()


## 实时读数的节流块。**必须在 `_advance()` 之前**：本帧采样完再算读数，
## 屏幕上显示的就是这一帧刚采到的值；放到后面会永远慢一帧。
func _refresh_readout(delta: float) -> void:
	_readout_accum += delta
	if _readout_accum < READOUT_REFRESH_SECONDS:
		return
	_readout_accum = 0.0
	if _sampler == null:
		return
	_readout = live_readout(_current_axis_frame(), _flow.rest_baseline())


## 状态切换时清空所有窗口与计数。采样进度不能跨状态复用。
func _enter_state(next: StringName) -> void:
	_last_state = next
	_window.clear()
	_center_samples.clear()
	_range_samples.clear()
	_range_dir = 0
	_range_dir_frames = 0
	_center = Vector2.ZERO
	_frames_in_state = 0
	_motion_stop = false
	_motion_at_state_start = _sampler.buffer.events_motion if _sampler != null else 0
	# 进屏第一帧就要有读数：等满 0.1 秒才出现会让用户以为屏幕没在听。
	_readout_accum = 0.0
	if _sampler != null and _flow != null:
		_readout = live_readout(_current_axis_frame(), _flow.rest_baseline())


func _advance() -> void:
	if not _is_sampling_state():
		return
	_frames_in_state += 1
	if _check_motion_stop():
		return
	match _flow.state:
		OnboardingFlow.STATE_PROBE_REST:
			_sample_rest(true)
		OnboardingFlow.STATE_PROBE_UP, OnboardingFlow.STATE_PROBE_RIGHT, \
		OnboardingFlow.STATE_PROBE_DOWN, OnboardingFlow.STATE_PROBE_LEFT:
			_sample_probe_step()
		OnboardingFlow.STATE_REUSE_REST:
			_sample_rest(false)
		OnboardingFlow.STATE_REUSE_CHECK:
			_sample_reuse_step()
		OnboardingFlow.STATE_CALIBRATE_CENTER:
			_sample_center()
		OnboardingFlow.STATE_CALIBRATE_RANGE:
			_sample_range()


func _is_sampling_state() -> bool:
	match _flow.state:
		OnboardingFlow.STATE_PROBE_REST, OnboardingFlow.STATE_PROBE_UP, \
		OnboardingFlow.STATE_PROBE_RIGHT, OnboardingFlow.STATE_PROBE_DOWN, \
		OnboardingFlow.STATE_PROBE_LEFT, OnboardingFlow.STATE_REUSE_REST, \
		OnboardingFlow.STATE_REUSE_CHECK, OnboardingFlow.STATE_CALIBRATE_CENTER, \
		OnboardingFlow.STATE_CALIBRATE_RANGE:
			return true
	return false


## D0：等推杆时 60 帧没有任何新摇杆事件 → 显式停止，不静默挂住。
##
## 只在窗口还空着（确实在等输入）时触发：静止基线与校准会按帧数自动提交，
## 不存在「等到天荒地老」的路径，也就不该把「设备静止时不发事件」误判成 D0。
func _check_motion_stop() -> bool:
	if _frames_in_state < MOTION_STOP_FRAMES:
		return false
	if not _window.is_empty():
		return false
	if _sampler.buffer.events_motion != _motion_at_state_start:
		return false
	_motion_stop = true
	return true


func _sample_rest(probe: bool) -> void:
	_push_frame()
	if _window.size() < REST_FRAMES:
		_update_meter(_window.size(), REST_FRAMES)
		return
	if not _rest_is_still(_window):
		_window.clear()
		_update_meter(0, REST_FRAMES)
		_set_text(_hint, "双手离开摇杆")
		return
	if probe:
		_flow.submit_rest_baseline(_window)
	else:
		_flow.submit_reuse_rest(_window)
	_window.clear()
	_update_meter(0, REST_FRAMES)


func _sample_probe_step() -> void:
	var rest := _flow.rest_baseline()
	if _window.is_empty():
		if not _push_started(rest):
			_update_meter(0, STEP_FRAMES)
			return
		_push_frame()
		_update_meter(_window.size(), STEP_FRAMES)
		return
	_push_frame()
	if _window.size() < STEP_FRAMES:
		_update_meter(_window.size(), STEP_FRAMES)
		return
	var result := ProbeEvaluator.evaluate_step(_window, rest)
	_window.clear()
	_update_meter(0, STEP_FRAMES)
	_flow.submit_probe_step(result)


func _sample_reuse_step() -> void:
	var rest := _flow.rest_baseline()
	if _window.is_empty():
		if not _push_started(rest):
			_update_meter(0, STEP_FRAMES)
			return
		_push_frame()
		_update_meter(_window.size(), STEP_FRAMES)
		return
	_push_frame()
	if _window.size() < STEP_FRAMES:
		_update_meter(_window.size(), STEP_FRAMES)
		return
	var result := ProbeEvaluator.evaluate_step(_window, rest)
	_window.clear()
	_update_meter(0, STEP_FRAMES)
	_flow.submit_reuse_step(result)


func _sample_center() -> void:
	var mapping := _flow.mapping()
	if mapping == null:
		_set_text(_hint, "轴映射缺失，无法校准：请按 B 重新探测")
		return
	_center_samples.append(mapping.raw_rs(_current_axis_frame()))
	_update_meter(_center_samples.size(), CALIBRATE_FRAMES)
	if _center_samples.size() < CALIBRATE_FRAMES:
		return
	var samples: Array[Vector2] = []
	samples.assign(_center_samples)
	_center_samples.clear()
	var result := Calibration.center_from_samples(samples)
	if bool(result.get("ok", false)):
		_center = result.get("center", Vector2.ZERO)
	_flow.submit_calibration_center(result)


func _sample_range() -> void:
	var mapping := _flow.mapping()
	if mapping == null:
		_set_text(_hint, "轴映射缺失，无法校准：请按 B 重新探测")
		return
	if _range_dir >= CALIBRATE_RANGE_DIRS:
		var range_samples: Array[Vector2] = []
		range_samples.assign(_range_samples)
		var result := Calibration.scale_from_samples(range_samples, _center)
		_range_samples.clear()
		_range_dir = 0
		_range_dir_frames = 0
		_update_meter(0, CALIBRATE_FRAMES)
		_flow.submit_calibration_range(result)
		return
	_range_samples.append(mapping.raw_rs(_current_axis_frame()))
	_range_dir_frames += 1
	_update_meter(_range_dir_frames, CALIBRATE_FRAMES)
	if _range_dir_frames >= CALIBRATE_FRAMES:
		_range_dir += 1
		_range_dir_frames = 0


func _current_axis_frame() -> PackedFloat32Array:
	var frame := PackedFloat32Array()
	frame.resize(AXIS_COUNT)
	for axis in AXIS_COUNT:
		frame[axis] = _sampler.buffer.axis_value(axis)
	return frame


func _push_frame() -> void:
	_window.append(_current_axis_frame())


## 用户开始推了吗：任一轴相对静止基线的位移达到门槛。
func _push_started(rest: PackedFloat32Array) -> bool:
	if rest.size() == 0:
		# 没有基线就无法比较；交给 evaluate_step 报 not_enough_samples，不在这里挂死。
		return true
	for axis in AXIS_COUNT:
		if axis >= rest.size():
			break
		if absf(_sampler.buffer.axis_value(axis) - rest[axis]) >= PUSH_THRESHOLD:
			return true
	return false


## 静止基线的质量门：每轴峰峰值都必须低于 REST_PEAK_LIMIT。
func _rest_is_still(samples: Array[PackedFloat32Array]) -> bool:
	for axis in AXIS_COUNT:
		var lowest := INF
		var highest := -INF
		for sample in samples:
			if axis >= sample.size():
				continue
			lowest = minf(lowest, sample[axis])
			highest = maxf(highest, sample[axis])
		if is_finite(lowest) and highest - lowest > REST_PEAK_LIMIT:
			return false
	return true


func _refresh() -> void:
	if _flow == null:
		return
	_log_rejection()
	if _motion_stop:
		_render_motion_stop()
		return
	match _flow.state:
		OnboardingFlow.STATE_NO_DEVICE:
			_set_text(_title, "没有检测到手柄：先按任意键唤醒")
			_set_text(_step, "")
			_set_text(_body, "打开手柄电源 → 长按配对键 → 在系统蓝牙里选择它 → 按手柄任意键唤醒")
			_set_text(_big_hint, "等待手柄")
			_set_text(_hint, "安卓蓝牙手柄在收到第一次输入前不会出现在设备列表里。")
			_set_text(_options, "")
			_reset_meter()
		OnboardingFlow.STATE_DEVICE_READY:
			_set_text(_title, "已连接：%s" % _flow.device_name)
			_set_text(_step, "")
			_set_text(_body, "按任意键继续")
			_set_text(_big_hint, "手柄已就绪")
			_set_text(_hint, "")
			_set_text(_options, "")
			_reset_meter()
		OnboardingFlow.STATE_DEVICE_LOST:
			_set_text(_title, "手柄断开，等待重连")
			_set_text(_step, "")
			_set_text(_body, "重新连接后会重新走探针与校准。")
			_set_text(_big_hint, "等待重连")
			_set_text(_hint, "")
			_set_text(_options, "")
			_reset_meter()
		OnboardingFlow.STATE_PROBE_INTRO:
			_set_text(_title, "轴探测")
			_set_text(_step, "")
			_set_text(_body, "接下来测四步，只推右摇杆；左摇杆不要动")
			_set_text(_big_hint, "按 A 开始")
			_set_text(_hint, "四步记录每根轴的序号与符号；校准随后修正量程。")
			_set_text(_options, "")
			_reset_meter()
		OnboardingFlow.STATE_PROBE_REST:
			_set_text(_title, "静止基线")
			_set_text(_step, "")
			_set_text(_body, "双手离开摇杆")
			_set_text(_big_hint, "保持不动")
			_set_text(_hint, "正在采集静止基线（约 0.3 秒）")
			_set_text(_options, "")
		OnboardingFlow.STATE_PROBE_UP, OnboardingFlow.STATE_PROBE_RIGHT, \
		OnboardingFlow.STATE_PROBE_DOWN, OnboardingFlow.STATE_PROBE_LEFT:
			_render_probe_step()
		OnboardingFlow.STATE_PROBE_FAILED:
			_render_probe_failed()
		OnboardingFlow.STATE_REUSE_REST:
			_set_text(_title, "先松手，验证上次档案")
			_set_text(_step, "")
			_set_text(_body, "双手离开摇杆")
			_set_text(_big_hint, "保持不动")
			_set_text(_hint, "正在验证上次档案的静止基线")
			_set_text(_options, "")
		OnboardingFlow.STATE_REUSE_CHECK:
			_render_reuse_check()
		OnboardingFlow.STATE_CALIBRATE_CENTER:
			_set_text(_title, "中点校准")
			_set_text(_step, "")
			_set_text(_body, "双手离开摇杆，保持不动")
			_set_text(_big_hint, "保持 0.4 秒")
			_set_text(_hint, _flow.probe_failure_message if not _flow.probe_failure_message.is_empty()
				else "正在采集中点…")
			_set_text(_options, "")
		OnboardingFlow.STATE_CALIBRATE_RANGE:
			_set_text(_title, "满量程校准")
			_set_text(_step, "方向 %d/%d" % [mini(_range_dir + 1, CALIBRATE_RANGE_DIRS), CALIBRATE_RANGE_DIRS])
			_set_text(_body, _range_direction_text())
			_set_text(_big_hint, "推到最外圈并保持")
			_set_text(_hint, _flow.probe_failure_message if not _flow.probe_failure_message.is_empty()
				else "每个方向保持 0.4 秒")
			_set_text(_options, "")
		OnboardingFlow.STATE_LAYOUT_CONFIRM:
			_render_layout()
		OnboardingFlow.STATE_PRACTICE:
			_set_text(_title, "可以开始练习了")
			_set_text(_step, "")
			_set_text(_body, "只练绿色搓射：按住 RB，连按两下 X")
			_set_text(_big_hint, "进入练习")
			_set_text(_hint, "")
			_set_text(_options, "")
			_reset_meter()
	_set_text(_footer, _footer_text())


## 每次「新的拒绝码」打一行 logcat：技术值（margin、轴号、符号）必须能从日志
## 抄回来，屏幕不是唯一证据。同一个码连续显示时只打一次，避免 60 Hz 刷屏。
func _log_rejection() -> void:
	if _flow.last_reject_code == _logged_reject_code:
		return
	_logged_reject_code = _flow.last_reject_code
	if _logged_reject_code == &"":
		return
	print("PROBE_REJECT code=%s key=%s soft=%d msg=%s" % [
		String(_logged_reject_code), String(_flow.current_probe_key()),
		_flow.soft_retry_count, _flow.last_reject_message,
	])


func _render_probe_step() -> void:
	var key := _flow.current_probe_key()
	_set_text(_title, "轴探测")
	_set_text(_step, "第 %d/4 步" % _probe_step_number(key))
	_set_text(_body, _probe_direction_text(key))
	_set_text(_big_hint, "推到底并保持不动")
	# 第一行永远是「app 收到了什么」，第二行才是下一步该做什么。两行 = 67.2 px，
	# 落在 %Hint 的 104 px 带里（28 px × 3 行 = 100.8 px 是上限）。
	_set_text(_hint, "%s\n%s" % [_readout, _probe_second_line(key)])
	_set_text(_options, "")


func _render_reuse_check() -> void:
	var key := _flow.current_probe_key()
	_set_text(_title, "验证上次档案")
	_set_text(_step, "")
	_set_text(_body, "按 B 跳过验证，重新探测")
	_set_text(_big_hint, _probe_direction_text(key))
	_set_text(_hint, "%s\n%s" % [_readout, _reuse_second_line(key)])
	_set_text(_options, "")


## 探针第二行：正在软重试就把「为什么被拒 + 还剩几次机会」说清，否则只说这一步要什么。
func _probe_second_line(key: StringName) -> String:
	if _flow.soft_retry_count > 0 and _flow.last_reject_code != &"":
		return _soft_retry_sentence(key)
	return "本步要的是「%s」：推到底并保持" % direction_word(key)


## 复用门第二行：软重试句优先；没有重试时补一句「只验右与下两步」的既有说明。
func _reuse_second_line(key: StringName) -> String:
	if _flow.soft_retry_count > 0 and _flow.last_reject_code != &"":
		return _soft_retry_sentence(key)
	return "本步要的是「%s」：推到底并保持（只验右与下两步）" % direction_word(key)


## 软重试句的唯一实现：交叉码走「不像「右」」的长句并补次数，其余走纯语言映射。
func _soft_retry_sentence(key: StringName) -> String:
	var code := _flow.last_reject_code
	match code:
		&"same_axis_up_right", &"vertical_not_opposed", &"horizontal_not_opposed":
			return "%s（第 %d/2 次机会）" % [cross_check_plain(code, key), _flow.soft_retry_count]
	return plain_rejection(code, key, _flow.soft_retry_count)


## 硬失败面：三行 = 100.8 px，正好落在 %Hint 的 104 px 带里。
##   1. 实时读数（app 收到了什么）
##   2. 人话动作句（下一步做什么）
##   3. 检测器的技术原文（margin 与门槛的比较、轴号与符号）—— 逐字来自 core，UI 不重拼
func _render_probe_failed() -> void:
	var key := _key_from_state(_flow.retry_state)
	_set_text(_title, "这一步没通过")
	_set_text(_step, "")
	_set_text(_body, "按 B 重来这一步")
	_set_text(_big_hint, "重来")
	var third := _flow.probe_failure_message if not _flow.probe_failure_message.is_empty() \
		else "按 B 重来这一步"
	_set_text(_hint, "%s\n%s\n%s" % [_readout, plain_rejection(_flow.probe_failure_code, key, 0), third])
	_set_text(_options, "")
	_reset_meter()


## 失败面的方向词只能从 retry_state 反查：probe_failed 状态下 current_probe_key() 是空的。
func _key_from_state(target: StringName) -> StringName:
	match target:
		OnboardingFlow.STATE_PROBE_UP:
			return &"up"
		OnboardingFlow.STATE_PROBE_RIGHT:
			return &"right"
		OnboardingFlow.STATE_PROBE_DOWN:
			return &"down"
		OnboardingFlow.STATE_PROBE_LEFT:
			return &"left"
	return &""


func _render_layout() -> void:
	var layout := _flow.effective_layout()
	if layout == DeviceProfile.LAYOUT_XBOX:
		_set_text(_title, "检测到 Xbox 布局")
		_set_text(_big_hint, "按 A 继续")
	elif layout == DeviceProfile.LAYOUT_PLAYSTATION:
		_set_text(_title, "检测到 PlayStation 布局")
		_set_text(_big_hint, "按 × 继续")
	else:
		_set_text(_title, "没认出手柄，请选择布局")
		_set_text(_big_hint, "请选择布局")
	_set_text(_step, "")
	if not _flow.layout_message.is_empty():
		_set_text(_body, _flow.layout_message)
	else:
		_set_text(_body, "十字键或 LB/RB：左选 Xbox，右选 PlayStation")
	if _flow.button_index_ok:
		_set_text(_options, "十字键或 LB/RB：左选 Xbox，右选 PlayStation")
	else:
		_set_text(_options, "按到的是索引与标准不同：按 B 仍然使用此布局，或换布局")
	_set_text(_hint, "按 B 仍然使用此布局")
	_reset_meter()


func _render_motion_stop() -> void:
	_set_text(_title, "输入事件缺失")
	_set_text(_step, "")
	_set_text(_body, "这一步开始后没有再收到新的摇杆事件。")
	_set_text(_big_hint, "停止")
	# 停的是**本步增量**：绝对总数在长会话里永远大于 0，拿它当判据只会自相矛盾。
	var delta := _sampler.buffer.events_motion - _motion_at_state_start
	_set_text(_hint, stop_message(delta, _sampler.buffer.events_motion))
	_set_text(_options, "记录此屏并停止（D0 判失败）")
	_set_text(_footer, _footer_text())
	_reset_meter()


func _probe_step_number(key: StringName) -> int:
	match key:
		&"up":
			return 1
		&"right":
			return 2
		&"down":
			return 3
		&"left":
			return 4
	return 0


func _probe_direction_text(key: StringName) -> String:
	match key:
		&"up":
			return "把右摇杆推到最上，按住"
		&"right":
			return "把右摇杆推到最右，按住"
		&"down":
			return "把右摇杆推到最下，按住"
		&"left":
			return "把右摇杆推到最左，按住"
	return "推动右摇杆"


func _range_direction_text() -> String:
	match _range_dir:
		0:
			return "推到最右并保持"
		1:
			return "推到最上并保持"
		2:
			return "推到最下并保持"
	return "推到最左并保持"


func _footer_text() -> String:
	if _flow == null or _flow.device_name.is_empty():
		return ""
	return "设备：%s" % _flow.device_name


## 只在文本真的变化时赋值：Label.text 会触发文本整形，等同一次隐式节流。
func _set_text(label: Label, text: String) -> void:
	if label.text == text:
		return
	label.text = text


func _update_meter(value: int, maximum: int) -> void:
	_meter.max_value = float(maximum)
	_meter.value = float(value)


func _reset_meter() -> void:
	_meter.max_value = float(REST_FRAMES)
	_meter.value = 0.0
