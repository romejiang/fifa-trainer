extends Control

## 组合根：加载配置 → 建对象图 → 把设备事件交给「单页输入设置」或「练习屏」。
##
## 2026-11-05 的两次真机失败（04-07）之后，首启路径从「四步探针 + 中点/满量程校准 +
## 布局确认」换成一页式输入设置（04-09）。用户的硬要求原文是「不要用这种一步，这种
## 进步式的测试。你要不你就做成一个页面。就不要有状态改变，我可以反复地测。」
## 因此本文件里**没有** `OnboardingFlow` 的分派：`%Onboarding` 节点仍留在场景里
## （`onboarding_screen.gd` 与 `OnboardingFlow` 一并保留，供复用门的后续工作），
## 但它永远不可见、也永远不 `setup()` —— 它的 `_process` 在 `_flow == null` 时早退。
##
## 这里仍然是**唯一**的接线处（零 autoload）：
##   * `PadSampler` 是唯一碰引擎输入单例的节点；
##   * 按钮边沿只有一个消费者（`_flush_button_edges`），按当前可见的屏分派；
##   * `GestureEngine.tick()` 只在练习屏可见时推进 —— 输入设置页零 Outcome 的机械保证
##     （运行时另有 `layout_confirmed` 硬门，两层都在）；
##   * raw 轴 → `Frame` 的唯一换算入口是 `FrameBuilder`：本文件**不准**出现第二份
##     「减中点除量程」，也不准绕过它直接做校准归一化（T-05-23）。
##
## 复用：启动时若本设备（guid 优先）已有档案、且 `DeviceProfile.can_enter_practice()`
## 为真（rs 映射齐全 + 校准合理 + 布局已确认 + `quality.range_ready` 标记）→ 直接进练习；
## 否则显示输入设置页。04-09 / 04-10 在量程没推满时保存的「默认校准」档案没有这个标记，
## 因此会被丢弃、设置页重新出现 —— 这是 04-11 的第二个真机缺陷修法。
##
## 时间单位：`Frame.now` 是**秒**（`Time.get_ticks_usec()` 除以一百万），与
## 检测器的 `* 1000.0` 换算一致。`PadSampler` 的
## `_now_ms()` 是**事件时间戳**，单位毫秒；两者不能混用，也不要在本文件里换算。

const PRACTICE_SCENE := preload("res://src/ui/practice_screen.tscn")
const INPUT_SETUP_SCENE := preload("res://src/ui/input_setup_screen.tscn")
const DIAGNOSTICS_SCENE := preload("res://src/ui/diagnostics_overlay.tscn")
## 诊断覆盖层的组合键：LB + RB 同时按住 0.8 秒。
##
## 为什么是 9 / 10：Phase 2 的真机实测已经确认这把手上 LB / RB = 9 / 10（A/B/X/Y = 0/1/2/3），
## D3 的布局页也在用这两个索引。
##
## 为什么永远不会和 tap 手势撞车：tap 是「按住 RB 连按两下 X」，本组合键只用到 9 / 10、
## 从不按 X（索引 2），所以既凑不出 `Hit` 也凑不出 `Failure`。
##
## 已知且可接受的副作用：在输入设置页按组合键时，先按下的那只键会被页面当成
## 换轴对（输入设置屏对「两键同时按住」另有一道守卫，见 `handle_button`）。
const DIAGNOSTICS_CHORD_SECONDS := 0.8
const DIAGNOSTICS_CHORD_BUTTONS: Array[int] = [9, 10]
## 练习屏按住 B 这么久就回设置页。B 不参与绿色搓射，不会和判定冲突。
const BACK_HOLD_SECONDS := 1.0


@onready var _config_error: Label = %ConfigError
## 04-09 之前的首启屏。保留节点与脚本，但不参与任何路径；`_ready` 里第一件事就是隐藏。
@onready var _onboarding: Control = %Onboarding
@onready var _practice_container: Control = %Practice

## 多动作引擎：全部启用技能由**一个**实例驱动（D-11）。本文件不区分「当前练哪个动作」，
## 自由练习的标题与动作名由引擎 / 判定结果提供。
var _runtime: GestureEngine = null
## 已校验的配置。`_process` 每帧要用 `input.deadzone`，不能在热路径里重复加载。
var _config: AppConfig = null
## 当前设备的档案。`null` = 无档案：`FrameBuilder` 把四个角度/幅度字段写 0，
## 相对左摇杆的技能保持 inert。生命周期见 `_try_reuse_profile` / `_on_profile_saved` /
## `_on_device_list_changed` —— 设与清都必须显式。
var _profile: DeviceProfile = null
var _sampler: PadSampler = null
var _profile_store: ProfileStore = null
## 输入设置屏脚本没有 `class_name`，必须保持无类型引用才能在运行时调 `setup` /
## `handle_button`。练习屏与诊断覆盖层同理。
var _setup = null
var _practice = null
var _diagnostics = null
## 组合键已经按住多久、本轮是否已经触发过（按住不放只开一次，不会来回抖）。
var _chord_hold: float = 0.0
var _chord_latched: bool = false
## 练习屏按住 B 的累计秒数。
var _back_hold: float = 0.0
## 打开覆盖层前的布局确认值；关闭时原样恢复。
var _layout_was_confirmed: bool = false

## 已消费到第几条按钮边沿。边沿数组只追加，游标只前进。
var _seen_edges: int = 0
## 是否已经进入练习屏。进入之前 `GestureEngine` 一帧都不推进。
var _in_practice: bool = false
## 复用检查只做一次（每次换设备重置）：同一只手柄不会在练习中途被拽回设置页。
var _reuse_checked: bool = false
## 1 Hz 诊断日志的累加器（D5/D6 的抄录来源）。
var _diag_accum: float = 0.0


func _ready() -> void:
	# 默认每帧 flush 一次累积输入；必须关掉，事件时间戳才有亚帧意义。
	Input.set_use_accumulated_input(false)
	# 输入事件日志的会话头：每次启动一行，日志按进程分段。写入失败不影响任何判定。
	InputLog.start_session(_app_version())
	_config_error.visible = false
	_onboarding.visible = false
	_practice_container.visible = false

	var result := ConfigStore.new().load_config()
	if not result.ok():
		_show_config_error(result.to_text())
		return
	# 全技能自由练习：不再要求「恰好一条 taps 动作」。动作选择器属于 Phase 6。
	_config = result.config
	_runtime = GestureEngine.new(_config, false)
	_profile_store = ProfileStore.new()
	_sampler = PadSampler.new()
	# 顺序即正确性：先建三块屏，再 connect，最后 add_child。
	#   * `add_child(_sampler)` 会让 `PadSampler._ready()` 立刻 emit 设备列表；
	#     回调里可能直接进入练习（复用档案），所以练习屏必须先存在。
	#   * 设置屏必须在 `add_child(_sampler)` 之前建好，回调里要能安全地隐藏它。
	#   * 诊断覆盖层最后建，画在最上面。
	_build_input_setup()
	_build_practice_screen()
	_build_diagnostics()
	_sampler.device_list_changed.connect(_on_device_list_changed)
	add_child(_sampler)
	_on_device_list_changed(_sampler.connected_devices())


## 工程里没有 `application/config/version` 时 `get_setting` 返回空串而不是默认值；
## 空版本号会让会话头变成 `v= `。用导出配置里的 versionName 兜底。
func _app_version() -> String:
	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	return version if not version.is_empty() else "0.1.0"


func _process(delta: float) -> void:
	# 配置错误屏上没有判定：不推进、不分派。
	if _runtime == null:
		return
	# 组合键计时必须在 `_flush_button_edges()` 之前：本帧按住的 9 / 10 要先把
	# 「组合键进行中」置位，边沿分派才会跳过它们。
	_tick_diagnostics_chord(delta)
	if _diagnostics != null and _diagnostics.visible:
		# 覆盖层可见期间：只处理它自己的按键（十字键翻页 / Y 清除档案），
		# 不 tick 运行时、不把边沿转发给设置页、不推进判定。
		_flush_diagnostics_edges()
		_diagnostics.call("tick", delta)
		return
	_flush_button_edges()
	# 练习屏返回：按住 B 一秒。读的是当前按住状态，不是边沿 —— 松开即清零。
	if _in_practice:
		if bool(_sampler.buffer.pressed_dict().has("B")):
			_back_hold += delta
			if _back_hold >= BACK_HOLD_SECONDS:
				_back_hold = 0.0
				_leave_practice()
				return
		else:
			_back_hold = 0.0
	_log_diagnostics(delta)
	if not _in_practice:
		# 输入设置页零 Outcome：连 `tick()` 都不调用。运行时的 `layout_confirmed`
		# 硬门是第二层保证，但这一层是结构上的 —— 没有调用就没有产出。
		return
	var frame := Frame.new()
	frame.now = Time.get_ticks_usec() / 1_000_000.0
	frame.buttons = _sampler.buffer.pressed_dict()
	# 无档案时传 null：`FrameBuilder` 把四个字段写 0，相对技能 inert，不崩。
	var mapping: AxisMapping = _profile.axes if _profile != null else null
	var calibration: Calibration = _profile.calibration if _profile != null else null
	FrameBuilder.fill(frame, _raw_axes(), mapping, calibration, _config.input.deadzone)
	_runtime.tick(frame)


## 八根原始轴。数据源只有 `PadStateBuffer.axis_value()` —— 本文件**不新增轮询通道**
## （INPUT-05），也不在这里做任何归一化。
func _raw_axes() -> PackedFloat32Array:
	var raw := PackedFloat32Array()
	raw.resize(PadStateBuffer.MAX_AXIS)
	for axis in PadStateBuffer.MAX_AXIS:
		raw[axis] = _sampler.buffer.axis_value(axis)
	return raw


## 实例化一页式输入设置。**必须排在 `add_child(_sampler)` 之前**：采样节点 `_ready`
## 会 emit 设备列表，回调里会碰设置屏。
func _build_input_setup() -> void:
	_setup = INPUT_SETUP_SCENE.instantiate()
	add_child(_setup)
	# 首启就是这一页：默认可见。只有「复用档案 / 保存成功」才会隐藏它。
	_setup.visible = true
	_setup.connect("profile_saved", _on_profile_saved)
	_setup.call("setup", _sampler, _profile_store)


## 实例化练习屏进 `%Practice` 容器。**这里不调 `setup`**：进入练习的第一步才注入。
## 04-05 的占位 Label 必须真正 `queue_free()`：它没有任何数据源。
func _build_practice_screen() -> void:
	_practice = PRACTICE_SCENE.instantiate()
	_practice_container.add_child(_practice)
	_practice.visible = false
	var placeholder := _practice_container.get_node_or_null("Placeholder")
	if placeholder != null:
		placeholder.queue_free()


## 实例化诊断覆盖层。**必须排在最后**：同一个父节点下后加的子节点画在上面，
## 否则诊断文本会被别的屏盖住，screencap 取证就白拍了。
##
## 档案 store 一起注入：覆盖层按 Y 时调 `ProfileStore.clear()`，只删那一份文件。
func _build_diagnostics() -> void:
	_diagnostics = DIAGNOSTICS_SCENE.instantiate()
	add_child(_diagnostics)
	_diagnostics.visible = false
	_diagnostics.connect("profile_cleared", _on_profile_cleared)
	_diagnostics.call("setup", _sampler.buffer, _sampler, _profile_store)


## 组合键计时。读的是**当前按住状态**，不是边沿数组。
## 任一个松开就立刻清零并解除 latch —— 下一次组合键必须重新按满 0.8 秒。
func _tick_diagnostics_chord(delta: float) -> void:
	if _sampler == null or _diagnostics == null:
		return
	var both_down := _sampler.buffer.button_down(DIAGNOSTICS_CHORD_BUTTONS[0]) \
		and _sampler.buffer.button_down(DIAGNOSTICS_CHORD_BUTTONS[1])
	if not both_down:
		_chord_hold = 0.0
		_chord_latched = false
		return
	_chord_hold += delta
	if _chord_hold < DIAGNOSTICS_CHORD_SECONDS or _chord_latched:
		return
	_chord_latched = true
	if _diagnostics.visible:
		_close_diagnostics()
	else:
		_open_diagnostics()


## 打开覆盖层 = **静默放弃当前这一下**。
## `set_layout_confirmed(false)` 会在运行时里 `abandon()` 未完成的手势并清空尚未取走
## 的 Outcome：覆盖层打开期间屏幕上绝不会冒出一条判定。
func _open_diagnostics() -> void:
	_layout_was_confirmed = _runtime.layout_confirmed
	_runtime.set_layout_confirmed(false)
	_seen_edges = _sampler.buffer.button_edges().size()
	_diagnostics.visible = true
	_diagnostics.call("refresh")


func _close_diagnostics() -> void:
	_diagnostics.visible = false
	_runtime.set_layout_confirmed(_layout_was_confirmed)
	_seen_edges = _sampler.buffer.button_edges().size()


## 覆盖层可见期间的边沿消费者：所有按下的边沿都交给覆盖层自己的 `handle_button`。
## 键位语义只有一处定义（覆盖层的 `action_for_button`）：十字键左右翻页、Y 清除档案，
## 其余无动作 —— 组合根不再维护第二份 match。
func _flush_diagnostics_edges() -> void:
	var edges: Array = _sampler.buffer.button_edges()
	var total := edges.size()
	if total <= _seen_edges:
		return
	for position in range(_seen_edges, total):
		var edge: Dictionary = edges[position]
		if not bool(edge.get("pressed", false)):
			continue
		_diagnostics.call("handle_button", int(edge["index"]))
	_seen_edges = total


## 覆盖层按 Y 清除档案之后的唯一后续动作：关覆盖层、退出练习、回到设置页。
##
## 不清 `_profile_store` 实例（它只是路径句柄），但把 `_reuse_checked` 置为真：
## 文件已经删了，即使下次设备列表变化也不需要再试一次复用 —— 用户此刻应该在
## 设置页上重新推摇杆，而不是被自动带回练习。
func _on_profile_cleared() -> void:
	_diagnostics.visible = false
	_layout_was_confirmed = false
	_leave_practice()
	if _setup != null:
		_setup.visible = true
		_setup.call("reset_stats")
	_reuse_checked = true
	_seen_edges = _sampler.buffer.button_edges().size()


## 1 Hz 诊断日志：D5 / D6 的抄录来源（adb logcat -s godot:I）。
## 只在已绑定设备时打印 —— 无设备时 `buffer` 的 min/max 是哨兵值（INF / -INF）。
func _log_diagnostics(delta: float) -> void:
	_diag_accum += delta
	if _diag_accum < 1.0:
		return
	_diag_accum = 0.0
	if _sampler == null or _sampler.buffer.device < 0:
		return
	var buffer := _sampler.buffer
	var stats := buffer.delta_ms_percentiles()
	print("PAD_DIAG ev_m=%d ev_b=%d poll=%d dt50=%.2f dt95=%.2f dtmax=%.2f in_tid=%d proc_tid=%d" % [
		buffer.events_motion, buffer.events_button, buffer.poll_edges,
		float(stats.get("p50", 0.0)), float(stats.get("p95", 0.0)),
		float(stats.get("max", 0.0)),
		_sampler.input_thread_id, _sampler.process_thread_id,
	])
	for axis in PadStateBuffer.MAX_AXIS:
		var span := buffer.axis_range(axis)
		print("PAD_AXIS i=%d v=%.3f min=%.3f max=%.3f" % [
			axis, buffer.axis_value(axis), span.x, span.y,
		])
	print("PAD_DEV name=%s guid=%s" % [_sampler.device_name(), _sampler.device_guid()])
	if not _in_practice and _setup != null:
		# 输入设置页的「认了哪一对、符号是什么、量程到没到」——没有 run-as 时
		# 这一行就是可核对的原文（04-07 的 D1 通道）。
		print("INPUT_SETUP %s" % String(_setup.call("debug_line")))


## 唯一的按钮边沿消费者。练习中不消费任何边沿：tap 手势走 `pressed_dict()`，
## 两次解释同一次按下会让「按住 RB 连按两下 X」多出一条边沿。
func _flush_button_edges() -> void:
	var edges: Array = _sampler.buffer.button_edges()
	var total := edges.size()
	if total <= _seen_edges:
		return
	for position in range(_seen_edges, total):
		var edge: Dictionary = edges[position]
		if not bool(edge.get("pressed", false)):
			continue
		if _chord_hold > 0.0 and DIAGNOSTICS_CHORD_BUTTONS.has(int(edge["index"])):
			continue
		if _in_practice or _setup == null:
			continue
		_setup.call("handle_button", int(edge["index"]))
	_seen_edges = total


## 设置屏按 A 保存成功之后的唯一后续动作。
##
## `_profile` 的生命周期在这里设：保存成功后重新按 key 查一次档案，取不到就保持
## `null`（画面仍进练习，但相对技能 inert）。不在回调里直接拼一份内存档案 ——
## 文件里的那一份才是 `ProfileStore` 与 `can_enter_practice()` 共同承认的事实。
func _on_profile_saved(layout: StringName) -> void:
	_profile = _profile_store.find(
		DeviceProfile.make_key(_sampler.device_guid(), _sampler.device_name()))
	_enter_practice(layout)


## 进入练习。布局为空时按 Xbox 兜底：设置页总会写一个非空布局，走到这里说明
## 档案来自更早的版本 —— 空布局会让练习屏进入「请返回引导重选」的死角。
func _enter_practice(layout: StringName) -> void:
	if _practice == null or _setup == null:
		return
	var effective := layout
	if effective == &"":
		effective = DeviceProfile.LAYOUT_XBOX
	_in_practice = true
	# 成功标准 4 的机械落点：只有走到这里（设置页按 A / 复用已存在档案）才置为已确认。
	_runtime.set_layout_confirmed(true)
	_practice.setup(_runtime, effective, _sampler.buffer)
	_practice.visible = true
	_practice_container.visible = true
	if _setup != null:
		_setup.visible = false
	# 吞掉进入练习这一下自己的边沿，返回设置页时不会重放。
	_seen_edges = _sampler.buffer.button_edges().size()


## 回到设置页（断连 / 换手柄）。运行时静默清场：断连不是一次尝试。
func _leave_practice() -> void:
	if _setup == null or _practice == null:
		return
	_in_practice = false
	_back_hold = 0.0
	_runtime.set_layout_confirmed(false)
	_practice.visible = false
	_practice_container.visible = false
	_setup.visible = true
	_seen_edges = _sampler.buffer.button_edges().size()


## 复用：本设备已有档案且**档案自洽** → 直接进练习。
##
## 只判档案自身能否用（`DeviceProfile.can_enter_practice()`），不在启动时逐项比较
## 四项 index+sign：没有探针就没有「本次观测值」，拿档案自己的值去比自己是假绿。
## 四项比较仍在 `can_reuse()` 里，留给将来重新引入「探一次」的界面。
func _try_reuse_profile() -> void:
	if _reuse_checked or _in_practice or _sampler.buffer.device < 0:
		return
	_reuse_checked = true
	var key := DeviceProfile.make_key(_sampler.device_guid(), _sampler.device_name())
	var profile := _profile_store.find(key)
	if not _profile_usable(profile):
		# 不可用就保持 null：无档案 = 无输入，不降级、不猜。
		return
	_profile = profile
	_enter_practice(profile.layout)


func _profile_usable(profile: DeviceProfile) -> bool:
	if profile == null:
		return false
	return profile.can_enter_practice()


## 设备列表信号与主动播种共用的唯一回调体。
func _on_device_list_changed(devices: Array) -> void:
	if _runtime == null:
		return
	if devices.is_empty():
		if _sampler.buffer.device >= 0:
			_sampler.unbind()
			_seen_edges = 0
			_reuse_checked = false
			# 设备没了：旧档案的轴对绝不能留在内存里。
			_profile = null
			_leave_practice()
			_setup.call("reset_stats")
		return

	var first := int(devices[0])
	if _sampler.buffer.device >= 0 and _sampler.buffer.device != first:
		# 换了一只手柄：上一只的轴对、符号、量程全部作废。
		_profile = null
		_leave_practice()
		_reuse_checked = false
		_setup.call("reset_stats")
	# 只在设备真的换了时才重绑：同一设备的重复列表不得清掉按键状态、
	# 也不得把 _seen_edges 归零后重放已经分派过的边沿。
	if _sampler.buffer.device != first:
		_profile = null
		_sampler.bind(first)
		_seen_edges = 0
		_reuse_checked = false
		_setup.call("reset_stats")
	_try_reuse_profile()


func _show_config_error(text: String) -> void:
	_config_error.text = text
	_config_error.visible = true
	_onboarding.visible = false
	_practice_container.visible = false
	if _setup != null:
		_setup.visible = false
