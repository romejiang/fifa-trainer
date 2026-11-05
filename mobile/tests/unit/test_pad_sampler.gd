extends RefCounted

## PadStateBuffer + JoyButtonMap 的无头套件。
##
## **只测纯缓冲与映射表**：不构造 `PadSampler`、不碰 `Input`、不需要场景树。
## 薄壳与纯逻辑的边界由文件边界强制 —— 这条套件能跑完，就说明状态机不依赖引擎。
##
## 事件用普通字典描述，形状与 `PadSampler._input` 产出的完全一致：
##   motion: {"device", "t_ms", "kind": "motion", "axis", "value"}
##   button: {"device", "t_ms", "kind": "button", "index", "pressed"}
## 这样「薄壳只做形状转换」这件事不需要真机就能验证。

const DEVICE := 0


func run(r) -> void:
	_check_same_frame_reversal(r)
	_check_device_filter(r)
	_check_reconcile_idempotent(r)
	_check_event_channel_missing(r)
	_check_pressed_dict(r)
	_check_bind_device_idempotent(r)
	_check_motion_ring_cap(r)
	_check_delta_percentiles(r)
	_check_axis_range(r)
	_check_joy_button_map(r)
	r.complete()


## INPUT-05 的唯一机械证据：同一帧右 → 左 → 右，三条 motion 事件全部保留且顺序不变。
##
## 轮询只保留帧内最后一个值：同一帧的三次反转在轮询通道里只会看到最后的「右」，
## 中间那次「左」永久丢失。这里证明事件通道不丢。
func _check_same_frame_reversal(r) -> void:
	var buffer := PadStateBuffer.new(DEVICE)
	buffer.apply_event({"device": DEVICE, "t_ms": 100.0, "kind": "motion", "axis": 2, "value": 1.0})
	buffer.apply_event({"device": DEVICE, "t_ms": 100.0, "kind": "motion", "axis": 2, "value": -1.0})
	buffer.apply_event({"device": DEVICE, "t_ms": 100.0, "kind": "motion", "axis": 2, "value": 1.0})

	r.check(buffer.events_motion == 3,
		"同一帧三次反转必须计三条 motion 事件（实际 %d）" % buffer.events_motion)
	var events := buffer.motion_events()
	r.check(events.size() == 3,
		"环形缓冲必须保留三条事件（实际 %d）" % events.size())
	if events.size() == 3:
		r.eq_float(_event_value(events, 0), 1.0, 1e-6, "第 1 条 event 的值必须是「右」")
		r.eq_float(_event_value(events, 1), -1.0, 1e-6, "第 2 条 event 的值必须是「左」")
		r.eq_float(_event_value(events, 2), 1.0, 1e-6, "第 3 条 event 的值必须是「右」")
	r.eq_float(buffer.axis_value(2), 1.0, 1e-6, "轴的当前值必须是最后一条事件的「右」")


## 设备过滤与越界拒绝：别的设备的事件、畸形索引都不能碰状态。
func _check_device_filter(r) -> void:
	var buffer := PadStateBuffer.new(3)
	r.check(not buffer.apply_event(_motion(7, 10.0, 2, 1.0)),
		"绑定 3 号设备时，7 号设备的 motion 必须被拒")
	r.check(not buffer.apply_event(_button(7, 10.0, 10, true)),
		"绑定 3 号设备时，7 号设备的 button 必须被拒")
	r.check(buffer.events_motion == 0,
		"被设备过滤的 motion 不得计数（实际 %d）" % buffer.events_motion)
	r.check(buffer.events_button == 0,
		"被设备过滤的 button 不得计数（实际 %d）" % buffer.events_button)
	var any_down := false
	for index in PadStateBuffer.MAX_BUTTON:
		if buffer.button_down(index):
			any_down = true
	r.check(not any_down, "被设备过滤的 button 不得改变按键状态")

	r.check(not buffer.apply_event(_motion(3, 11.0, 99, 1.0)),
		"越界轴索引必须被拒")
	r.check(not buffer.apply_event(_button(3, 11.0, 99, true)),
		"越界按钮索引必须被拒")
	r.check(buffer.events_motion == 0 and buffer.events_button == 0 and buffer.poll_edges == 0,
		"越界事件不得改变任何计数器（%d / %d / %d）" % [
			buffer.events_motion, buffer.events_button, buffer.poll_edges])


## 事件先到、轮询看到同值时不得补边沿；轮询看到变化时才补。
func _check_reconcile_idempotent(r) -> void:
	var buffer := PadStateBuffer.new(DEVICE)
	buffer.apply_event(_button(DEVICE, 100.0, 10, true))
	r.check(buffer.events_button == 1, "一条 button 事件必须计一条（实际 %d）" % buffer.events_button)
	r.check(buffer.button_down(10), "button 10 必须是按下状态")

	r.check(buffer.reconcile(101.0, {10: true}) == 0,
		"事件先到、轮询读到同值时必须补 0 条边沿")
	r.check(buffer.poll_edges == 0,
		"两条通道一致时 poll_edges 必须保持 0（实际 %d）" % buffer.poll_edges)

	r.check(buffer.reconcile(102.0, {10: false}) == 1,
		"轮询读到释放时必须补 1 条边沿")
	r.check(buffer.poll_edges == 1, "补出的边沿必须计入 poll_edges（实际 %d）" % buffer.poll_edges)
	r.check(not buffer.button_down(10), "补出的释放边沿必须改变按钮状态")
	r.check(buffer.button_edges().size() == 2,
		"事件与轮询各产生一次真实边沿，共两条（实际 %d）" % buffer.button_edges().size())


## 事件通道完全缺席时，轮询能补出边沿，且这些边沿不冒充事件计数。
func _check_event_channel_missing(r) -> void:
	var buffer := PadStateBuffer.new(DEVICE)
	r.check(buffer.reconcile(100.0, {10: true}) == 1, "第一次对账必须补出按下边沿")
	r.check(buffer.poll_edges == 1, "poll_edges 必须为 1（实际 %d）" % buffer.poll_edges)
	r.check(buffer.events_button == 0,
		"轮询补出的边沿不得计入 events_button（实际 %d）" % buffer.events_button)
	r.check(buffer.button_down(10), "轮询必须能改变最终按钮状态")

	r.check(buffer.reconcile(200.0, {10: false}) == 1, "第二次对账必须补出释放边沿")
	r.check(buffer.poll_edges == 2, "poll_edges 必须为 2（实际 %d）" % buffer.poll_edges)
	r.check(not buffer.button_down(10), "最终按钮状态必须与 polled 一致")


## pressed_dict() 只由按钮索引产生；LT/RT 是轴，本阶段不得合成。
func _check_pressed_dict(r) -> void:
	var buffer := PadStateBuffer.new(DEVICE)
	for index in [0, 9, 10]:
		buffer.apply_event(_button(DEVICE, 100.0, index, true))
	var pressed := buffer.pressed_dict()
	r.check(pressed.size() == 3,
		"按下 A/LB/RB 后 pressed_dict 必须正好三个键（实际 %s）" % str(pressed.keys()))
	r.check(pressed.has("A") and pressed.has("LB") and pressed.has("RB"),
		"索引 0 / 9 / 10 必须映射为 A / LB / RB（实际 %s）" % str(pressed.keys()))
	r.check(not pressed.has(""), "pressed_dict 不得含空字符串键")

	for index in PadStateBuffer.MAX_BUTTON:
		buffer.apply_event(_button(DEVICE, 101.0, index, true))
	pressed = buffer.pressed_dict()
	r.check(not pressed.has("LT"),
		"LT 是轴不是按钮：pressed_dict 不得合成它（实际 %s）" % str(pressed.keys()))
	r.check(not pressed.has("RT"),
		"RT 是轴不是按钮：pressed_dict 不得合成它（实际 %s）" % str(pressed.keys()))
	r.check(not pressed.has(""), "全部按下时也不得出现空字符串键")


## 同一台设备的重复列表信号不得重置采样状态；换设备才清场。
func _check_bind_device_idempotent(r) -> void:
	var buffer := PadStateBuffer.new()
	r.check(buffer.bind_device(3), "首次绑定必须返回 true")
	buffer.apply_event(_button(3, 100.0, 10, true))
	r.check(buffer.button_down(10), "3 号设备的 button 10 必须是按下状态")
	r.check(buffer.events_button == 1, "事件计数必须为 1（实际 %d）" % buffer.events_button)

	var events_button_before := buffer.events_button
	var events_motion_before := buffer.events_motion
	var poll_edges_before := buffer.poll_edges
	var motion_size_before := buffer.motion_events().size()

	r.check(not buffer.bind_device(3),
		"同一设备重复绑定必须返回 false（无变化）")
	r.check(buffer.button_down(10),
		"同一设备重复绑定不得清掉按键状态")
	r.check(buffer.events_button == events_button_before
			and buffer.events_motion == events_motion_before
			and buffer.poll_edges == poll_edges_before,
		"同一设备重复绑定不得改变任何计数器")
	r.check(buffer.motion_events().size() == motion_size_before,
		"同一设备重复绑定不得改变 motion 缓冲")

	r.check(buffer.bind_device(7), "换设备必须返回 true")
	r.check(not buffer.button_down(10), "换设备必须清空按键状态")
	r.check(buffer.events_button == 0 and buffer.events_motion == 0 and buffer.poll_edges == 0,
		"换设备必须清空全部计数器")


## 环形缓冲有界：超出上限丢最旧，计数不丢。
func _check_motion_ring_cap(r) -> void:
	var buffer := PadStateBuffer.new(DEVICE)
	var total := PadStateBuffer.MAX_MOTION_EVENTS + 5
	for index in total:
		buffer.apply_event(_motion(DEVICE, float(index), 2, 0.5))
	r.check(buffer.motion_events().size() == PadStateBuffer.MAX_MOTION_EVENTS,
		"环形缓冲必须恰好保留 %d 条（实际 %d）" % [
			PadStateBuffer.MAX_MOTION_EVENTS, buffer.motion_events().size()])
	r.check(buffer.dropped_motion() == 5,
		"超出上限的 5 条必须计入 dropped_motion（实际 %d）" % buffer.dropped_motion())
	r.check(buffer.motion_event_count() == total,
		"总计数必须包含已淘汰的事件（实际 %d）" % buffer.motion_event_count())


## Δt 百分位：等间隔样本的 p50 / p95 / max 都是同一个值；索引不插值。
func _check_delta_percentiles(r) -> void:
	var buffer := PadStateBuffer.new(DEVICE)
	for index in 5:
		buffer.apply_event(_motion(DEVICE, 100.0 + 8.0 * index, 2, 0.0))
	var stats := buffer.delta_ms_percentiles()
	r.check(int(stats["count"]) == 4,
		"5 条事件必须给出 4 个间隔（实际 %d）" % int(stats["count"]))
	r.eq_float(float(stats["p50"]), 8.0, 1e-6, "等间隔 8ms 的 p50")
	r.eq_float(float(stats["p95"]), 8.0, 1e-6, "等间隔 8ms 的 p95")
	r.eq_float(float(stats["max"]), 8.0, 1e-6, "等间隔 8ms 的 max")

	var fresh := PadStateBuffer.new(DEVICE)
	var empty_stats := fresh.delta_ms_percentiles()
	r.check(int(empty_stats["count"]) == 0, "没有间隔时 count 必须为 0（D6 的真空态）")
	r.eq_float(float(empty_stats["p50"]), 0.0, 1e-6, "没有间隔时 p50 必须为 0")
	r.eq_float(float(empty_stats["p95"]), 0.0, 1e-6, "没有间隔时 p95 必须为 0")
	r.eq_float(float(empty_stats["max"]), 0.0, 1e-6, "没有间隔时 max 必须为 0")


## 每轴 min/max 是 D6 的唯一数据源；「从未收到样本」必须与「样本全 0」可区分。
func _check_axis_range(r) -> void:
	var buffer := PadStateBuffer.new(DEVICE)
	r.check(buffer.axis_range(2) == Vector2.ZERO,
		"从未收到样本时 axis_range 必须是 Vector2.ZERO")
	buffer.apply_event(_motion(DEVICE, 100.0, 2, -1.0))
	buffer.apply_event(_motion(DEVICE, 101.0, 2, 0.5))
	buffer.apply_event(_motion(DEVICE, 102.0, 2, 1.0))
	var found := buffer.axis_range(2)
	r.eq_float(found.x, -1.0, 1e-6, "轴 2 的最小值必须是 -1.0")
	r.eq_float(found.y, 1.0, 1e-6, "轴 2 的最大值必须是 1.0")
	buffer.reset()
	r.check(buffer.axis_range(2) == Vector2.ZERO,
		"reset() 之后必须回到 Vector2.ZERO（不能保留旧样本）")


## 索引 ↔ 规范名：覆盖 0..20，且与 Buttons.CANONICAL 同源不漂移。
func _check_joy_button_map(r) -> void:
	r.check(JoyButtonMap.INDEX_TO_NAME.size() == 21,
		"索引表必须覆盖 0..20（实际 %d 条）" % JoyButtonMap.INDEX_TO_NAME.size())
	r.check(JoyButtonMap.name_of(0) == "A", "索引 0 必须是 A")
	r.check(JoyButtonMap.name_of(9) == "LB", "索引 9 必须是 LB")
	r.check(JoyButtonMap.name_of(10) == "RB", "索引 10 必须是 RB")
	r.check(JoyButtonMap.name_of(20) == "", "索引 20（触摸板）本阶段没有规范名")
	r.check(JoyButtonMap.name_of(99) == "", "越界索引必须返回空串")
	r.check(int(JoyButtonMap.NAME_TO_INDEX.get("RB", -1)) == 10,
		"反向表里 RB 必须是 10（实际 %s）" % str(JoyButtonMap.NAME_TO_INDEX.get("RB", -1)))

	var drift: Array[String] = []
	for index in JoyButtonMap.INDEX_TO_NAME:
		var canonical: String = JoyButtonMap.INDEX_TO_NAME[index]
		if canonical.is_empty():
			continue
		if not Buttons.CANONICAL.has(canonical):
			drift.append(canonical)
	r.check(drift.is_empty(),
		"INDEX_TO_NAME 的非空值必须全部在 Buttons.CANONICAL 里（漂移：%s）" % str(drift))


static func _motion(device: int, t_ms: float, axis: int, value: float) -> Dictionary:
	return {"device": device, "t_ms": t_ms, "kind": "motion", "axis": axis, "value": value}


static func _event_value(events: Array, index: int) -> float:
	return float(events[index]["value"])


static func _button(device: int, t_ms: float, index: int, pressed: bool) -> Dictionary:
	return {"device": device, "t_ms": t_ms, "kind": "button", "index": index, "pressed": pressed}
