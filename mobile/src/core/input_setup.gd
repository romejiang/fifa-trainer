class_name InputSetup
extends RefCounted

## 单页输入设置的全部纯逻辑：把每帧采样变成「轴对 / 符号 / 中点 / 量程 / 扳机静止」。
##
## 为什么没有「第几步 / 还有几秒 / 重来」：用户 2026-11-05 两次真机失败的原话是
## 「一直显示重来重来重来」「检测方式就有问题，没有任何容错」，随后明确要求
## 「不要有状态改变，我可以反复地测」。只要识别带时间窗口，用户就必须在窗口内做对
## 动作；而窗口一出现，扳机轴的静止基线跳变就足以让每一条窗口都判错（04-07 尝试二：
## `i=4` / `i=5` 先报 0.000、22 秒后跳到 -1.000，57 行 `ambiguous_axes`）。
## 所以本类只回答「现在看到了什么」，不回答「你对不对」：没有任何方法产出
## ok / failed / retry，量程没推够只由 `range_ready()` 说「还没」。
##
## 三条硬约束：
##   1. **零引擎依赖**：不读 Input / Time / 场景树 / 文件系统，采样由调用方每帧喂入；
##   2. **不判失败**：用户按 A 之前页面一直采样，本类不设上限、不计次数；
##   3. **扳机静止值 = 观测到的最小值**：设备先报 0.000、后跳到 -1.000 时，min 自己
##      收敛到 -1.000，不需要「等所有轴都上报过一次」这类时序假设。
##
## 轴对识别只看「最近 1 秒内谁在动」：窗口按帧数计（`RECENT_SAMPLES` 帧，60 Hz 下
## 正好 1 秒）。core 不读时钟，帧数就是唯一可注入、可复现的时间口径。

const AXIS_COUNT := 8

## 候选轴对：Godot / SDL 的标准布局里右摇杆通常是 (2,3)、扳机是 (4,5)。
## 但这只是候选，不是断言 —— 哪一对真的是右摇杆由用户的动作决定（INPUT-02）。
const PAIRS: Array[Vector2i] = [
	Vector2i(0, 1),
	Vector2i(2, 3),
	Vector2i(4, 5),
	Vector2i(6, 7),
]
## 「一对都没认出来」：屏幕据此显示「推一下右摇杆」，绝不替用户猜一对。
const PAIR_NONE := Vector2i(-1, -1)

## 扳机轴的标准索引（SDL 的 TRIGGERLEFT / TRIGGERRIGHT）。本阶段不读扳机判定，
## 但档案要记下它们的静止值，Phase 5 的扳机归一直接用。
const TRIGGER_AXES: Array[int] = [4, 5]

## 最近窗口的帧数：60 Hz 下约 1 秒。真机事件率 125 Hz，但 `observe()` 每帧一次，
## 所以窗口的语义是「最近一秒里屏幕看到的那些帧」，不是「最近 60 个事件」。
const RECENT_SAMPLES := 60

## 一对轴要被认定为「在动」的最小峰峰值：静止噪声在 ±0.02 内，0.35 是它的十倍以上。
const MIN_PAIR_TRAVEL := 0.35

## 量程就绪门槛：两轴的峰峰值都要 ≥ 1.2（各自从 0 推到 ±0.6 以上）。
## 没到只是「还没推到底」，不是失败。
const RANGE_READY := 1.2

## 判「停在同一个值上没动」要看多少帧（60 Hz 下约 0.2 秒）。
const SETTLE_SAMPLES := 12

## 档案 `profile_id`：本阶段单档案，但字段必须写，将来多档案不改 schema。
const PROFILE_ID := "input_setup"

var _min := PackedFloat32Array()
var _max := PackedFloat32Array()
var _last := PackedFloat32Array()
## 最近 RECENT_SAMPLES 帧的完整快照：轴对识别只用它，长窗口 min/max 另存。
var _recent: Array[PackedFloat32Array] = []
## 每根轴最后一次「值真的变了」的帧号：并列时用它决定谁更「最近在动」。
var _last_change := PackedInt32Array()
var _frame_index: int = 0
## -1 = 自动识别；>= 0 = 用户用 LB/RB 亲手选的那一对（下标指向 PAIRS）。
var _manual_index: int = -1
var _x_sign: int = 1
var _y_sign: int = 1


func _init() -> void:
	reset()


## B 键：清空全部统计与人工选择。之后页面回到「推一下右摇杆」的初始状态。
##
## 符号也一起清：屏幕永远显示当前符号，所以清掉不会让人误以为 X 还是反向的；
## 反过来「清空」却留下一个隐藏的符号，才是真正的意外。
func reset() -> void:
	_min = PackedFloat32Array()
	_max = PackedFloat32Array()
	_last = PackedFloat32Array()
	_min.resize(AXIS_COUNT)
	_max.resize(AXIS_COUNT)
	_last.resize(AXIS_COUNT)
	_last_change.resize(AXIS_COUNT)
	for axis in AXIS_COUNT:
		# INF / -INF 让「从未收到样本」与「样本恰好是 0」可以区分（同 PadStateBuffer）。
		_min[axis] = INF
		_max[axis] = -INF
		_last[axis] = 0.0
		_last_change[axis] = -1
	_frame_index = 0
	_recent.clear()
	_manual_index = -1
	_x_sign = 1
	_y_sign = 1


## 喂一帧。`values` 少于 8 根时，缺的轴保持上一帧的值（不制造一次假的「回中」）。
## NaN / Inf 一律沿用上一帧：坏样本不能进统计，也不能把 min/max 污染成 NaN。
func observe(values: PackedFloat32Array) -> void:
	var frame := PackedFloat32Array()
	frame.resize(AXIS_COUNT)
	for axis in AXIS_COUNT:
		var previous := _last[axis]
		var value := previous
		if axis < values.size():
			var raw := values[axis]
			if is_finite(raw):
				value = raw
		frame[axis] = value
		_last[axis] = value
		if absf(value - previous) > 1e-6:
			_last_change[axis] = _frame_index
		if value < _min[axis]:
			_min[axis] = value
		if value > _max[axis]:
			_max[axis] = value
	_recent.append(frame)
	if _recent.size() > RECENT_SAMPLES:
		_recent.pop_front()
	_frame_index += 1


## 当前活动轴对：人工选择优先；否则取「最近 1 秒内两轴峰峰值的最小值」最大的一对。
##
## 用 `min(span_x, span_y)` 而不是两轴之和：只有「两根都在动」才说明这是摇杆的一对轴。
## 单根轴的大位移（扳机、噪声、别的摇杆）凑不出一对。
##
## 得分并列时取「两轴都更晚变化」的那一对：窗口是 1 秒，用户刚换推另一对时旧的一对
## 还在窗口里，只比峰峰值会永远判给候选表里靠前的那一对 —— 屏幕上就是「推了没反应」。
func active_pair() -> Vector2i:
	if _manual_index >= 0:
		return PAIRS[_manual_index]
	var best := PAIR_NONE
	var best_score := 0.0
	var best_recency := -1
	for pair in PAIRS:
		var score := _pair_score(pair)
		if score <= 0.0:
			continue
		var recency := mini(_last_change[pair.x], _last_change[pair.y])
		if score > best_score + 1e-9:
			best = pair
			best_score = score
			best_recency = recency
		elif absf(score - best_score) <= 1e-9 and recency > best_recency:
			best = pair
			best_recency = recency
	return best


## LB / RB：在候选对之间人工切换。`direction > 0` 为下一对，`< 0` 为上一对，0 不动。
##
## 第一次按键从当前自动结果出发（自动是 (2,3) 时 RB 直接到 (4,5)）；还没有自动结果时
## RB 落到第一对、LB 落到最后一对 —— 第一次按就该「选出一对」，不是「跳过一对」。
func cycle_pair(direction: int) -> void:
	if direction == 0:
		return
	var step := 1 if direction > 0 else -1
	if _manual_index < 0:
		var current := active_pair()
		if current == PAIR_NONE:
			_manual_index = 0 if step > 0 else PAIRS.size() - 1
			return
		_manual_index = PAIRS.find(current)
	_manual_index = wrapi(_manual_index + step, 0, PAIRS.size())


func toggle_x_sign() -> void:
	_x_sign = -_x_sign


func toggle_y_sign() -> void:
	_y_sign = -_y_sign


func x_sign() -> int:
	return _x_sign


func y_sign() -> int:
	return _y_sign


## 量程就绪：当前轴对的两根轴，长窗口峰峰值都 ≥ RANGE_READY。
## 没到只表示「还没推到底」，页面显示提示；本方法不改变任何状态。
func range_ready() -> bool:
	var pair := active_pair()
	if pair == PAIR_NONE:
		return false
	return axis_span(pair.x) >= RANGE_READY and axis_span(pair.y) >= RANGE_READY


## 中点 = (min + max) / 2，量程半宽 = (max - min) / 2，都取当前轴对的长窗口。
##
## 没有轴对时返回 ZERO：屏幕显示「等轴对认出来」，而不是拿 0/1 冒充一次校准。
func center() -> Vector2:
	var pair := active_pair()
	if pair == PAIR_NONE:
		return Vector2.ZERO
	var span_x := axis_range(pair.x)
	var span_y := axis_range(pair.y)
	return Vector2((span_x.x + span_x.y) * 0.5, (span_y.x + span_y.y) * 0.5)


func scale() -> Vector2:
	var pair := active_pair()
	if pair == PAIR_NONE:
		return Vector2.ZERO
	var span_x := axis_range(pair.x)
	var span_y := axis_range(pair.y)
	return Vector2((span_x.y - span_x.x) * 0.5, (span_y.y - span_y.x) * 0.5)


## 某根轴的扳机静止值 = 观测到的最小值。从未收到样本时返回 0.0。
##
## 这是 04-07 尝试二的修复点：旧实现「先采一段时间当静止基线」，而扳机轴在首次上报前
## 一直返回 0.000，基线就被记成 0；之后真实静止值 -1.000 到达，每个窗口都看到两根轴
## 各移动 1.0。min 没有这个时序假设 —— 它在一帧之内就会收敛到 -1.000。
func trigger_rest(axis: int) -> float:
	if axis < 0 or axis >= AXIS_COUNT:
		return 0.0
	if not is_finite(_min[axis]):
		return 0.0
	return _min[axis]


## 长窗口的 min/max。从未收到样本时返回 `Vector2.ZERO`
## （用 `is_finite()` 判 `_min`，因为初值是 INF）。
func axis_range(axis: int) -> Vector2:
	if axis < 0 or axis >= AXIS_COUNT:
		return Vector2.ZERO
	if not is_finite(_min[axis]) or not is_finite(_max[axis]):
		return Vector2.ZERO
	return Vector2(_min[axis], _max[axis])


func axis_span(axis: int) -> float:
	var span := axis_range(axis)
	return span.y - span.x


func axis_last(axis: int) -> float:
	if axis < 0 or axis >= AXIS_COUNT:
		return 0.0
	return _last[axis]


## 最近窗口内的峰峰值：轴表用它标出「这一行正在动」。
func recent_range(axis: int) -> float:
	if axis < 0 or axis >= AXIS_COUNT or _recent.is_empty():
		return 0.0
	var lowest := INF
	var highest := -INF
	for frame in _recent:
		var value := frame[axis]
		if value < lowest:
			lowest = value
		if value > highest:
			highest = value
	return highest - lowest


## 构造 per-device 档案。**只在用户按 A 时由界面调用** —— 自动识别结果必须先显示在
## 屏幕上（轴对、符号、量程），由人确认之后才落盘（INPUT-04 / T-04-18）。
##
## 没有轴对时 rs 索引写 -1：这份档案不可用，界面也不该走到这里（A 分支会先拦下）。
## 量程为 0（一次都没推）时按 1.0 使用：宁可写「未校准的原始值」，
## 也不写一份 `Calibration.from_dict` 必然拒绝、进而让 `load_all()` 丢掉整个文件的档案。
func build_profile(device_name: String, device_guid: String, now_iso: String) -> DeviceProfile:
	var profile := DeviceProfile.new()
	profile.profile_id = PROFILE_ID
	profile.device_name = device_name
	profile.device_guid = device_guid
	profile.key = DeviceProfile.make_key(device_guid, device_name)

	var pair := active_pair()
	var mapping := AxisMapping.new()
	if pair != PAIR_NONE:
		mapping.rs_x_index = pair.x
		mapping.rs_x_sign = _x_sign
		mapping.rs_y_index = pair.y
		mapping.rs_y_sign = _y_sign
	# 本页不区分左右摇杆：用户只被要求推右摇杆，左摇杆保持未映射。
	mapping.ls_x_index = -1
	mapping.ls_y_index = -1
	mapping.lt_index = TRIGGER_AXES[0]
	mapping.lt_rest = trigger_rest(TRIGGER_AXES[0])
	mapping.rt_index = TRIGGER_AXES[1]
	mapping.rt_rest = trigger_rest(TRIGGER_AXES[1])
	profile.axes = mapping

	var calibration := Calibration.new()
	var measured_center := center()
	var measured_scale := scale()
	calibration.center_x = measured_center.x
	calibration.center_y = measured_center.y
	calibration.scale_x = _usable_scale(measured_scale.x)
	calibration.scale_y = _usable_scale(measured_scale.y)
	profile.calibration = calibration

	profile.quality = {
		"source": PROFILE_ID,
		"pair": [pair.x, pair.y],
		"span_x": axis_span(pair.x) if pair != PAIR_NONE else 0.0,
		"span_y": axis_span(pair.y) if pair != PAIR_NONE else 0.0,
		"trigger_rest": [trigger_rest(TRIGGER_AXES[0]), trigger_rest(TRIGGER_AXES[1])],
		"range_ready": range_ready(),
	}
	profile.layout = _layout_for(device_name)
	# 本页没有布局选择步骤：认得出品牌就按品牌存，认不出按 Xbox 存。
	# 空布局会让练习屏直接显示「布局未确认，请返回引导重选」，而引导屏已经不是首启路径。
	profile.layout_confirmed = true
	profile.button_index_ok = true
	profile.probed_at_iso = now_iso
	return profile


## 一对轴在最近窗口里的得分。见类文档：只有两轴同时动才算一对。
func _pair_score(pair: Vector2i) -> float:
	var score := minf(recent_range(pair.x), recent_range(pair.y))
	if score < MIN_PAIR_TRAVEL:
		return 0.0
	if _is_device_rest_jump(pair):
		return 0.0
	return score


## 扳机静止基线的「一步跳变」不是用户动作。
##
## 04-07 尝试二的实测：手柄刚连上时 `i=4` / `i=5` 都读 0.000，22 秒后首次上报真实
## 静止值 -1.000 并永远停在那里。两根轴同时、同值、一步跳完，然后完全不动 ——
## 人手做不到这一点（两根独立的模拟轴不会停在同一个值上还保持不动），所以它不给分。
##
## 只对扳机对生效：右摇杆推到 45° 时两根轴也可能同值，但那是真实手势，不能被压掉；
## 真把摇杆映射到 4/5 的手柄仍可用 LB/RB 手选这一对。
func _is_device_rest_jump(pair: Vector2i) -> bool:
	if pair != PAIRS[2]:
		return false
	if _recent.size() < SETTLE_SAMPLES:
		return false
	var value := _last[pair.x]
	if absf(value - _last[pair.y]) > 1e-4:
		return false
	for index in range(_recent.size() - SETTLE_SAMPLES, _recent.size()):
		var frame: PackedFloat32Array = _recent[index]
		if absf(frame[pair.x] - value) > 1e-4:
			return false
		if absf(frame[pair.y] - value) > 1e-4:
			return false
	return true


## 量程半宽：0 或非有限 → 1.0（未校准直通）；上限 1.0（原始轴本来就在 ±1 内）。
func _usable_scale(value: float) -> float:
	if not is_finite(value) or value <= 0.0:
		return 1.0
	return minf(value, 1.0)


## 品牌识别失败时按 Xbox 存：安卓上绝大多数手柄走 XInput 映射，键名只是屏幕提示；
## 存空布局却会让练习屏进入「布局未确认」的死角，而这一版没有布局选择步骤。
func _layout_for(device_name: String) -> StringName:
	var suggested := DeviceProfile.suggest_layout(device_name)
	if suggested != &"":
		return suggested
	return DeviceProfile.LAYOUT_XBOX
