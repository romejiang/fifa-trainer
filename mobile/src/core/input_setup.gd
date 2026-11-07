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
## 写档案的两道门（04-11，真机实测之后）：`can_save()` 要求量程真的推满，
## `mark_layout_confirmed()` 要求人在同一页上确认过布局。两者都没有「默认放行」
## 分支 —— 04-09 的真机上，用户在量程没推满时按了一次 A，程序就把 `scale=1.0`、
## `center=0` 写成了「校准」，下次启动直接复用，圆点从此和手柄对不上。
##
## 轴对识别只看「最近 1 秒内谁在动」：窗口按帧数计（`RECENT_SAMPLES` 帧，60 Hz 下
## 正好 1 秒）。core 不读时钟，帧数就是唯一可注入、可复现的时间口径。
##
## 左右摇杆是两对独立的轴（D-06）：用户被要求先推右摇杆、再推左摇杆。`active_pair()`
## 的最近性会把「现在在动的那一对」翻到左摇杆上，所以右摇杆轴对必须在第一次推满
## 量程时**冻结**（`rs_pair()`），`ls_pair()` 再去排除冻结对之外的候选里取次高 ——
## 否则 D5-1 的顺序会把两只摇杆的归属对调，而且没有任何测试会自己发现。

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
## 空 = 还没手动切过：显示与保存都用 `_layout_for(device_name)` 的建议值。
var _layout_cycle: StringName = &""
## 只有页面在 A 的保存路径上调 `mark_layout_confirmed()` 之后才为 true。
var _layout_confirmed: bool = false
## 右摇杆轴对的冻结值。PAIR_NONE = 还没冻结；一旦冻结就再也不看 `active_pair()`。
var _rs_pair_frozen: Vector2i = PAIR_NONE
## 已按已知品牌预填（Xbox / PlayStation 标准轴对）。预填仍需 A 确认才写档案。
var _seeded_defaults: bool = false
## 预留给将来的人工选择（本阶段没有按键绑定）：>= 0 时优先于自动识别。
var _ls_manual_index: int = -1
## 左摇杆的符号与「是否已由用户动作确认」分开存：默认 +1 不是确认。
var _ls_x_sign: int = 1
var _ls_y_sign: int = 1
var _have_ls_x_sign: bool = false
var _have_ls_y_sign: bool = false
## 正在等哪一次「已知方向」的推杆（空 / up / right）。
var _ls_arm: StringName = &""
## 摆臂那一刻的 (x, y) 原始值：符号由位移方向判定，不看绝对位置。
var _ls_arm_base: Vector2 = Vector2.ZERO
## 最近一次摆臂的结果：空 = 未完成；ok = 符号已确认；sideways = 推错方向（不改符号）。
var _ls_arm_result: StringName = &""


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
	# 布局也一起回到建议值：B 是「清空重来」，留一个隐藏的手动布局会让页面
	# 显示的键名和用户以为的不一样。
	_layout_cycle = &""
	_layout_confirmed = false
	# 左右摇杆的状态一起清：冻结的 RS 对与已确认的 LS 符号都属于「上一次观测」，
	# 留着会让新设备继承旧摇杆的归属。
	_rs_pair_frozen = PAIR_NONE
	_ls_manual_index = -1
	_ls_x_sign = 1
	_ls_y_sign = 1
	_have_ls_x_sign = false
	_have_ls_y_sign = false
	_ls_arm = &""
	_ls_arm_base = Vector2.ZERO
	_ls_arm_result = &""


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
	# 顺序是硬约束：先冻结 RS 轴对，再处理 LS 摆臂。反过来时，第一次推 LS 的动作
	# 会先被 `_poll_ls_arm()` 看到，而那时 `ls_pair()` 还没有可用的非 RS 候选。
	_maybe_freeze_rs_pair()
	_poll_ls_arm()


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


## 右摇杆轴对的冻结值：已冻结就返回冻结值，否则返回此刻的自动结果。
##
## `build_profile()`、`pair_center/scale()` 与设置页的 `rs=` 都走这里。只要有一次
## 冻结，用户之后推左摇杆把 `active_pair()` 翻过去也不会改变归属（D5-1 / T-05-21b）。
func rs_pair() -> Vector2i:
	if _rs_pair_frozen != PAIR_NONE:
		return _rs_pair_frozen
	return active_pair()


## 左摇杆轴对：排除冻结的 RS 对之后，长窗口 `min(span_x, span_y)` 最高、且最近
## 确实在动（`_pair_score > 0`，同时沿用设备基线跳变的排除规则）的那一对。
##
## 用长窗口排名而不是 `active_pair()`：用户推完 LS 后可能停一拍再按 A，最近窗口的
## 1 秒会把「刚推过」抹掉，但长窗口的行程仍然可信。`_pair_score > 0` 保留「必须
## 真的动过」这一条，防止把静止噪声当成一对。
func ls_pair() -> Vector2i:
	if _ls_manual_index >= 0:
		var manual := PAIRS[_ls_manual_index]
		if manual != rs_pair():
			return manual
	var frozen := rs_pair()
	var best := PAIR_NONE
	var best_span := 0.0
	for pair in PAIRS:
		if pair == frozen:
			continue
		if _pair_score(pair) <= 0.0:
			continue
		var span := minf(axis_span(pair.x), axis_span(pair.y))
		if span < MIN_PAIR_TRAVEL:
			continue
		if span > best_span + 1e-9:
			best = pair
			best_span = span
	return best


## 已知品牌的标准轴对预填：Xbox / PlayStation 在安卓上都走 RS 2/3 + LS 0/1。
##
## 这不是「静默替用户猜」：预填只改候选值，`_layout_confirmed` 仍为 false，
## 用户必须按 A 才写档案；按 B 清空后会回到「推摇杆重新测量」。
func seed_known_defaults(device_name: String) -> bool:
	var lowered := device_name.strip_edges().to_lower()
	if not (lowered.contains("xbox") or lowered.contains("dualsense")
			or lowered.contains("dualshock") or lowered.contains("wireless controller")
			or lowered.contains("playstation") or lowered.contains("ps4")
			or lowered.contains("ps5")):
		return false
	var rs := Vector2i(2, 3)
	var ls := Vector2i(0, 1)
	_manual_index = PAIRS.find(rs)
	if _manual_index < 0:
		return false
	_rs_pair_frozen = rs
	_ls_manual_index = PAIRS.find(ls)
	_x_sign = 1
	_y_sign = 1
	_ls_x_sign = 1
	_ls_y_sign = 1
	_have_ls_x_sign = true
	_have_ls_y_sign = true
	_seeded_defaults = true
	return true


## 摆臂「向上推」：把基线定在当前 (x, y)，之后 `observe()` 用位移方向判 Y 符号。
## 返回 `&"no_pair"` 表示还没有可用的 LS 轴对（页面应继续提示先推左摇杆）。
func arm_ls_up() -> StringName:
	return _arm_ls(&"up")


## 摆臂「向右推」：同上，判 X 符号。
func arm_ls_right() -> StringName:
	return _arm_ls(&"right")


func _arm_ls(kind: StringName) -> StringName:
	var pair := ls_pair()
	if pair == PAIR_NONE:
		_ls_arm = &""
		_ls_arm_result = &""
		return &"no_pair"
	_ls_arm = kind
	_ls_arm_result = &""
	_ls_arm_base = Vector2(_last[pair.x], _last[pair.y])
	return &"ok"


## 每帧检查摆臂：只有**已知方向**的位移才能定符号，横向位移必须明确回报。
func _poll_ls_arm() -> void:
	if _ls_arm == &"":
		return
	var pair := ls_pair()
	if pair == PAIR_NONE:
		return
	var delta := Vector2(_last[pair.x], _last[pair.y]) - _ls_arm_base
	if _ls_arm == &"up":
		if absf(delta.x) > absf(delta.y) and absf(delta.x) >= MIN_PAIR_TRAVEL:
			_ls_arm_result = &"sideways"
			_ls_arm = &""
			return
		if delta.y <= -MIN_PAIR_TRAVEL:
			# SDL 的 y 向下为正：向上推得到负值 → 归一化不需要翻转。
			_ls_y_sign = 1
			_have_ls_y_sign = true
			_ls_arm_result = &"ok"
			_ls_arm = &""
			return
		if delta.y >= MIN_PAIR_TRAVEL:
			_ls_y_sign = -1
			_have_ls_y_sign = true
			_ls_arm_result = &"ok"
			_ls_arm = &""
			return
		return
	if _ls_arm == &"right":
		if absf(delta.y) > absf(delta.x) and absf(delta.y) >= MIN_PAIR_TRAVEL:
			_ls_arm_result = &"sideways"
			_ls_arm = &""
			return
		if delta.x >= MIN_PAIR_TRAVEL:
			_ls_x_sign = 1
			_have_ls_x_sign = true
			_ls_arm_result = &"ok"
			_ls_arm = &""
			return
		if delta.x <= -MIN_PAIR_TRAVEL:
			_ls_x_sign = -1
			_have_ls_x_sign = true
			_ls_arm_result = &"ok"
			_ls_arm = &""


## 最近一次摆臂的结果：`&""` 未完成 / `&"ok"` 已确认 / `&"sideways"` 推错方向。
func ls_arm_result() -> StringName:
	return _ls_arm_result


func ls_arm_pending() -> bool:
	return _ls_arm != &""


## 当前推到基线之外的位移长度。设置页用它判断「用户已松手」以便重新取基线；
## 本方法不改任何状态。
func ls_arm_delta_len() -> float:
	if _ls_arm == &"":
		return 0.0
	var pair := ls_pair()
	if pair == PAIR_NONE:
		return 0.0
	return (Vector2(_last[pair.x], _last[pair.y]) - _ls_arm_base).length()


func has_ls_x_sign() -> bool:
	return _have_ls_x_sign


func has_ls_y_sign() -> bool:
	return _have_ls_y_sign


func ls_x_sign() -> int:
	return _ls_x_sign


func ls_y_sign() -> int:
	return _ls_y_sign


## 左摇杆就绪：轴对已识别 + X/Y 符号都由用户动作确认 + 两轴量程都推满。
## 与 `range_ready()` 是同一层的「保存时事实」，不是从校准数值反推。
func ls_ready() -> bool:
	if _seeded_defaults:
		return true
	var pair := ls_pair()
	if pair == PAIR_NONE:
		return false
	if not _have_ls_x_sign or not _have_ls_y_sign:
		return false
	return axis_span(pair.x) >= RANGE_READY and axis_span(pair.y) >= RANGE_READY


## 第一次推满右摇杆时冻结轴对。手动选择（LB/RB）本身就是用户的明确决定，直接采信；
## 自动识别则要求它确实是此刻 `_pair_score` 最高的一对，避免一次擦边动作把 RS 定死。
func _maybe_freeze_rs_pair() -> void:
	if _rs_pair_frozen != PAIR_NONE:
		return
	var pair := active_pair()
	if pair == PAIR_NONE:
		return
	if axis_span(pair.x) < RANGE_READY or axis_span(pair.y) < RANGE_READY:
		return
	if _manual_index < 0:
		var score := _pair_score(pair)
		for other in PAIRS:
			if _pair_score(other) > score + 1e-9:
				return
	_rs_pair_frozen = pair


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


## 当前布局：手动切过就用切换结果，否则用设备名给出的建议值。
##
## `device_name` 由调用方传进来（core 不碰引擎），空串时 `_layout_for` 落到 Xbox：
## 布局只影响屏幕上显示的键名，不影响任何判定。
func layout_cycle(device_name: String = "") -> StringName:
	if _layout_cycle != &"":
		return _layout_cycle
	return _layout_for(device_name)


## Start 键：在 Xbox / PlayStation 之间来回切。第一次切从当前显示值出发，
## 所以「Xbox 手柄按一下 Start」直接变成 PlayStation，而不是原地不动。
func cycle_layout(device_name: String) -> void:
	if layout_cycle(device_name) == DeviceProfile.LAYOUT_XBOX:
		_layout_cycle = DeviceProfile.LAYOUT_PLAYSTATION
	else:
		_layout_cycle = DeviceProfile.LAYOUT_XBOX


## A 的保存路径在 `build_profile()` 之前调用。没有这一步，写出来的档案
## `layout_confirmed` 永远是 false，复用门会把它拒之门外。
func mark_layout_confirmed() -> void:
	_layout_confirmed = true


func layout_confirmed() -> bool:
	return _layout_confirmed


## 量程就绪：当前轴对的两根轴，长窗口峰峰值都 ≥ RANGE_READY。
## 没到只表示「还没推到底」，页面显示提示；本方法不改变任何状态。
func range_ready() -> bool:
	if _seeded_defaults:
		return true
	var pair := active_pair()
	if pair == PAIR_NONE:
		return false
	return axis_span(pair.x) >= RANGE_READY and axis_span(pair.y) >= RANGE_READY


## 能不能写档案：RS 与 LS 的量程都真的推满才允许。缺左摇杆的档案会让四个
## `relative_to_ls` 技能静默变成「推了完全没反应」（T-05-19）—— 那是本项目最贵的
## 一类失败，所以保存门必须在写盘前就把它拦住。
func can_save() -> bool:
	return range_ready() and ls_ready()


## 指定轴对的中点 = (min + max) / 2，取长窗口。PAIR_NONE 返回 ZERO。
func pair_center(pair: Vector2i) -> Vector2:
	if pair == PAIR_NONE:
		return Vector2.ZERO
	var span_x := axis_range(pair.x)
	var span_y := axis_range(pair.y)
	return Vector2((span_x.x + span_x.y) * 0.5, (span_y.x + span_y.y) * 0.5)


## 指定轴对的量程半宽 = (max - min) / 2，取长窗口。PAIR_NONE 返回 ZERO。
func pair_scale(pair: Vector2i) -> Vector2:
	if pair == PAIR_NONE:
		return Vector2.ZERO
	var span_x := axis_range(pair.x)
	var span_y := axis_range(pair.y)
	return Vector2((span_x.y - span_x.x) * 0.5, (span_y.y - span_y.x) * 0.5)


## 中点与量程半宽都取当前活动轴对的长窗口。
##
## 没有轴对时返回 ZERO：屏幕显示「等轴对认出来」，而不是拿 0/1 冒充一次校准。
func center() -> Vector2:
	return pair_center(active_pair())


func scale() -> Vector2:
	return pair_scale(active_pair())


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
## RS 与 LS 的量程没推满、或 LS 符号没确认时返回 **null**：默认校准
## （scale=1.0 / center=0）不是校准，写进去之后复用门会把它当成「这台手柄已经
## 校准过」，下次启动直接进练习，圆点与手柄对不上。界面必须在 A 分支先问
## `can_save()`，拿到 null 只能提示、不能落盘。
##
## RS 索引取**冻结值** `rs_pair()`，不取 `active_pair()`：用户推左摇杆之后活动轴对
## 会翻到 LS，跟着它走会把两只摇杆的归属对调（D5-1 / T-05-21b）。
func build_profile(device_name: String, device_guid: String, now_iso: String) -> DeviceProfile:
	if not can_save():
		return null
	var profile := DeviceProfile.new()
	profile.profile_id = PROFILE_ID
	profile.device_name = device_name
	profile.device_guid = device_guid
	profile.key = DeviceProfile.make_key(device_guid, device_name)

	var rs := rs_pair()
	var ls := ls_pair()
	var mapping := AxisMapping.new()
	if rs != PAIR_NONE:
		mapping.rs_x_index = rs.x
		mapping.rs_x_sign = _x_sign
		mapping.rs_y_index = rs.y
		mapping.rs_y_sign = _y_sign
	# 04 阶段这里刻意写 -1（只探右摇杆）；05 阶段 D-06 补上真实的 LS 索引与符号。
	# `can_save()` 已保证 ls != PAIR_NONE；AxisMapping 的默认值本来就是 -1，
	# 不需要再写一份「未映射」的兜底（那正是 04 阶段那三行的形状）。
	if ls != PAIR_NONE:
		mapping.ls_x_index = ls.x
		mapping.ls_x_sign = _ls_x_sign
		mapping.ls_y_index = ls.y
		mapping.ls_y_sign = _ls_y_sign
	mapping.lt_index = TRIGGER_AXES[0]
	mapping.lt_rest = trigger_rest(TRIGGER_AXES[0])
	mapping.rt_index = TRIGGER_AXES[1]
	mapping.rt_rest = trigger_rest(TRIGGER_AXES[1])
	profile.axes = mapping

	var calibration := Calibration.new()
	var rs_center := pair_center(rs)
	var rs_scale := pair_scale(rs)
	calibration.center_x = rs_center.x
	calibration.center_y = rs_center.y
	calibration.scale_x = _usable_scale(rs_scale.x)
	calibration.scale_y = _usable_scale(rs_scale.y)
	var ls_center := pair_center(ls)
	var ls_scale := pair_scale(ls)
	calibration.ls_center_x = ls_center.x
	calibration.ls_center_y = ls_center.y
	calibration.ls_scale_x = _usable_scale(ls_scale.x)
	calibration.ls_scale_y = _usable_scale(ls_scale.y)
	profile.calibration = calibration

	profile.quality = {
		"source": PROFILE_ID,
		"pair": [rs.x, rs.y],
		"span_x": axis_span(rs.x) if rs != PAIR_NONE else 0.0,
		"span_y": axis_span(rs.y) if rs != PAIR_NONE else 0.0,
		"ls_pair": [ls.x, ls.y] if ls != PAIR_NONE else [-1, -1],
		"ls_span_x": axis_span(ls.x) if ls != PAIR_NONE else 0.0,
		"ls_span_y": axis_span(ls.y) if ls != PAIR_NONE else 0.0,
		"trigger_rest": [trigger_rest(TRIGGER_AXES[0]), trigger_rest(TRIGGER_AXES[1])],
		"range_ready": range_ready(),
		"ls_ready": ls_ready(),
		"seeded_defaults": _seeded_defaults,
	}
	# 布局必须在同一页上由人确认（Start 切换、A 确认）。`_layout_confirmed` 只有
	# `mark_layout_confirmed()` 能置位，所以 build_profile 自己永远不会写 true。
	profile.layout = layout_cycle(device_name)
	profile.layout_confirmed = _layout_confirmed
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


## 品牌识别失败时按 Xbox 建议：安卓上绝大多数手柄走 XInput 映射，键名只是屏幕提示；
## 空布局却会让练习屏进入「布局未确认」的死角。识别成功只是**建议值**，用户仍可
## 用 Start 切换、按 A 确认 —— 这里不写档案，也不代表已确认。
func _layout_for(device_name: String) -> StringName:
	var suggested := DeviceProfile.suggest_layout(device_name)
	if suggested != &"":
		return suggested
	return DeviceProfile.LAYOUT_XBOX
