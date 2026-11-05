class_name PadStateBuffer
extends RefCounted

## 手柄状态的**唯一写入点**：零引擎单例、零时钟，只接受已经打好时间戳的事件字典。
##
## 两条通道写同一份状态，因此天然幂等：
##   * 事件通道：`apply_event()` —— 每一条 InputEvent 到达即写状态；
##   * 轮询通道：`reconcile()` —— 每帧把按钮快照与当前状态对账，只补事件通道没送来的边沿。
## 状态已经一致时 `reconcile()` 不产生任何变化；两条通道各写一套状态会让「同一次按下」
## 变成两条边沿，所以这里只有 `_set_button()` 一个内部写入函数。
##
## **轴值只来自事件通道。** 轮询轴只保留帧内最后一个值，同帧
## 右 → 左 → 右会把中间那次「左」永久吞掉；本类因此不提供任何「轮询轴」入口，
## `_axes` 的每一次写入都对应一条 `kind == "motion"` 的事件。
##
## 诊断计数是 D5/D6 的唯一数据源，不在别处另算一份：
##   * `events_motion` / `events_button` —— 事件通道收到多少条；
##   * `poll_edges` —— 轮询补出多少条边沿；
##   * `delta_ms_percentiles()` / `axis_range(i)` —— 到达间隔分布与每轴 min/max。
##
## 本阶段的修饰键只有 `RB`：`LT` / `RT` 是轴，`pressed_dict()` 只由按钮索引产生，
## 不会合成它们。Phase 5 有了扳机轴归一（`AxisMapping.lt_index` / `rt_index`）再启用 RT。

const MAX_AXIS := 8
## 覆盖引擎按钮枚举 0..20（20 是触摸板，索引上界）。
const MAX_BUTTON := 21
## 轴事件环形缓冲上限：真机 125 Hz 下 512 条约 4 秒，足够算 p50/p95 又不至于无界增长。
const MAX_MOTION_EVENTS := 512

var device: int = -1
var events_motion: int = 0
var events_button: int = 0
## 只统计「轮询补出来的边沿」，事件通道正常时它保持 0。
var poll_edges: int = 0

## int(button_index) → bool。只用 int 键，避免 "10" 与 10 两套键。
var _down: Dictionary = {}
var _axes := PackedFloat32Array()
var _motion_events: Array = []
var _button_edges: Array = []
var _dropped_motion: int = 0
## min 填 INF、max 填 -INF：这样「从未收到样本」与「样本恰好全 0」可以区分。
var _axis_min := PackedFloat32Array()
var _axis_max := PackedFloat32Array()


func _init(p_device: int = -1) -> void:
	device = p_device
	_reset_state()


func accepts(p_device: int) -> bool:
	return p_device == device


## 幂等绑定。**同一个设备重复绑定不碰任何状态、返回 false**：
## 组合根在 `add_child()` 前 connect、之后又主动播种一次，两次都会走到这里；
## 若第二次清空状态，同一次按下就会被当成新边沿再分派一次。
## 换设备才清空状态与计数器，返回 true。
func bind_device(p_device: int) -> bool:
	if p_device == device:
		return false
	device = p_device
	_reset_state()
	return true


## 断开：语义上等于「没有设备」。与 `bind_device()` 分开，是因为断连必须无条件清场。
func unbind() -> void:
	device = -1
	_reset_state()


## 单一状态写入入口。device 不匹配、`kind` 未知、字段类型不对、索引越界时
## 一律返回 false **且状态一字不动** —— 畸形事件不能把数组写越界，也不能污染计数。
func apply_event(event: Dictionary) -> bool:
	var raw_device: Variant = event.get("device", null)
	if not _is_number(raw_device):
		return false
	if device < 0 or int(float(raw_device)) != device:
		return false
	var raw_kind: Variant = event.get("kind", "")
	if typeof(raw_kind) != TYPE_STRING and typeof(raw_kind) != TYPE_STRING_NAME:
		return false
	var t_ms := float(event.get("t_ms", 0.0))
	match String(raw_kind):
		"motion":
			return _apply_motion(t_ms, event)
		"button":
			return _apply_button(t_ms, event)
	return false


## 每帧对账：只把「轮询读数与当前状态不同」的索引补成边沿，返回本次补出的条数。
## 幂等性的全部机制就在这里 —— 状态一致时什么也不做，不维护第二套代码路径。
func reconcile(t_ms: float, polled_down: Dictionary) -> int:
	var edges := 0
	for index in MAX_BUTTON:
		var down := bool(polled_down.get(index, false))
		if bool(_down.get(index, false)) == down:
			continue
		poll_edges += 1
		_set_button(t_ms, index, down)
		edges += 1
	return edges


func axis_value(axis: int) -> float:
	if axis < 0 or axis >= _axes.size():
		return 0.0
	return _axes[axis]


## 某根轴的历史 min/max。一个样本都没有时返回 `Vector2.ZERO`
## （用 `is_finite()` 判 `_axis_min`，因为初值是 INF）。
func axis_range(axis: int) -> Vector2:
	if axis < 0 or axis >= _axis_min.size():
		return Vector2.ZERO
	if not is_finite(_axis_min[axis]) or not is_finite(_axis_max[axis]):
		return Vector2.ZERO
	return Vector2(_axis_min[axis], _axis_max[axis])


func button_down(index: int) -> bool:
	return bool(_down.get(index, false))


## canonical 名 → true，直接就是 `Frame.buttons` 的形状。
## 空名（MISC1 / PADDLE / TOUCHPAD）跳过：它们在本阶段没有词汇。
func pressed_dict() -> Dictionary:
	var pressed := {}
	for index in MAX_BUTTON:
		if not bool(_down.get(index, false)):
			continue
		var canonical := JoyButtonMap.name_of(index)
		if canonical.is_empty():
			continue
		pressed[canonical] = true
	return pressed


## 事件通道收到过的 motion 总条数（含已从环形缓冲淘汰的）。
func motion_event_count() -> int:
	return events_motion


## 返回副本：调用方排序或改动不会污染内部环形缓冲。
func motion_events() -> Array:
	return _motion_events.duplicate(true)


func button_edges() -> Array:
	return _button_edges.duplicate(true)


func dropped_motion() -> int:
	return _dropped_motion


## 清状态与计数、重置 min/max，**保留 device**（这是「同一个设备重新开始」的语义）。
func reset() -> void:
	_reset_state()


## 相邻 motion 事件时间差的 p50 / p95 / max。索引按排序后
## `floor(0.5*(n-1))` / `ceil(0.95*(n-1))` 取，不做插值 —— 真机读数只要量级。
## 样本少于 2 条时 `count = 0`，三个统计值都是 0.0。
func delta_ms_percentiles() -> Dictionary:
	if _motion_events.size() < 2:
		return {"p50": 0.0, "p95": 0.0, "max": 0.0, "count": 0}
	var deltas: Array[float] = []
	for index in range(1, _motion_events.size()):
		var previous := float(_motion_events[index - 1]["t_ms"])
		var current := float(_motion_events[index]["t_ms"])
		deltas.append(current - previous)
	deltas.sort()
	var last := deltas.size() - 1
	return {
		"p50": deltas[int(floor(0.5 * last))],
		"p95": deltas[int(ceil(0.95 * last))],
		"max": deltas[last],
		"count": deltas.size(),
	}


func _apply_motion(t_ms: float, event: Dictionary) -> bool:
	var raw_axis: Variant = event.get("axis", null)
	if not _is_number(raw_axis):
		return false
	var axis := int(float(raw_axis))
	if axis < 0 or axis >= MAX_AXIS:
		return false
	var value := float(event.get("value", 0.0))
	# NaN / Inf 不能进判定路径：坏样本在写入点挡住，下游不需要再判一次。
	if not is_finite(value):
		return false
	events_motion += 1
	_axes[axis] = value
	_axis_min[axis] = minf(_axis_min[axis], value)
	_axis_max[axis] = maxf(_axis_max[axis], value)
	_motion_events.append({"t_ms": t_ms, "axis": axis, "value": value})
	if _motion_events.size() > MAX_MOTION_EVENTS:
		_motion_events.pop_front()
		_dropped_motion += 1
	return true


func _apply_button(t_ms: float, event: Dictionary) -> bool:
	var raw_index: Variant = event.get("index", null)
	if not _is_number(raw_index):
		return false
	var index := int(float(raw_index))
	if index < 0 or index >= MAX_BUTTON:
		return false
	events_button += 1
	_set_button(t_ms, index, bool(event.get("pressed", false)))
	return true


## 唯一的按钮写入点：只有真实变化才记边沿。事件通道与轮询通道都经过这里，
## 所以两条通道对「同一次按下」只会留下一条边沿。
func _set_button(t_ms: float, index: int, pressed: bool) -> void:
	if bool(_down.get(index, false)) == pressed:
		return
	_down[index] = pressed
	_button_edges.append({"t_ms": t_ms, "index": index, "pressed": pressed})


func _reset_state() -> void:
	_down.clear()
	_axes = PackedFloat32Array()
	_axes.resize(MAX_AXIS)
	for axis in MAX_AXIS:
		_axes[axis] = 0.0
	_motion_events.clear()
	_button_edges.clear()
	_dropped_motion = 0
	events_motion = 0
	events_button = 0
	poll_edges = 0
	_axis_min = PackedFloat32Array()
	_axis_max = PackedFloat32Array()
	_axis_min.resize(MAX_AXIS)
	_axis_max.resize(MAX_AXIS)
	for axis in MAX_AXIS:
		_axis_min[axis] = INF
		_axis_max[axis] = -INF


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT
