extends Control

## 组合根：加载配置 → 建对象图 → 把设备事件交给 OnboardingFlow → 按状态切屏。
##
## 这里是**唯一**的接线处（零 autoload）：
##   * `ConfigStore` 读配置，`TapRuntime.select_taps_skill` 只挑 `kind == taps` 的
##     那条动作。「只练绿色搓射」由这条筛选实现，`shared/skills_config.json` 是
##     唯一真源，一个字节都不改。
##   * `PadSampler` 是唯一碰引擎输入单例的节点；本文件只消费它快照下来的
##     `button_edges()` 与 `pressed_dict()`，不自己读设备。
##   * `OnboardingFlow` 是纯状态机；本文件把「哪一屏可见」与「按键分派」翻译成
##     对状态机的调用，不在这里长第二套判定逻辑。
##   * `TapRuntime` 的 `tick()` 只在组合根这一处推进；引导屏与练习屏都不调。
##
## 时间单位：`Frame.now` 是**秒**（`Time.get_ticks_usec()` 除以一百万），与
## `TapDetector` / `TapRuntime` 的 `* 1000.0` 换算一致。`PadSampler` 的
## `_now_ms()` 是**事件时间戳**，单位毫秒；两者不能混用，也不要在本文件里换算。

@onready var _config_error: Label = %ConfigError
@onready var _onboarding: Control = %Onboarding
@onready var _practice_container: Control = %Practice

var _flow: OnboardingFlow = null
var _runtime: TapRuntime = null
var _sampler: PadSampler = null
var _profile_store: ProfileStore = null
## 已消费到第几条按钮边沿。边沿数组只追加，游标只前进。
var _seen_edges: int = 0
var _practice_entered: bool = false


func _ready() -> void:
	# 默认每帧 flush 一次累积输入；必须关掉，事件时间戳才有亚帧意义。
	Input.set_use_accumulated_input(false)
	_config_error.visible = false
	_onboarding.visible = true
	_practice_container.visible = false

	var result := ConfigStore.new().load_config()
	if not result.ok():
		_show_config_error(result.to_text())
		_flow = null
		return
	var skill := TapRuntime.select_taps_skill(result.config)
	if skill == null:
		# 零个或多个 taps 动作都不可用：不回退到别的动作，也不猜。
		_show_config_error("配置里没有唯一的 taps 动作：只练绿色搓射需要恰好一条启用的 taps 动作。")
		_flow = null
		return

	_runtime = TapRuntime.new(skill, result.config.global_cooldown_ms,
		result.config.input.gesture_release_ms, false)
	_profile_store = ProfileStore.new()
	_flow = OnboardingFlow.new()
	_sampler = PadSampler.new()
	# 顺序即正确性：先 connect 再 add_child。PadSampler._ready() 会 emit 一次
	# 当前设备列表；晚接一行就错过这次初始 emit。之后再用 connected_devices()
	# 主动播种一次，两次都走 bind() 的幂等分支。
	_sampler.device_list_changed.connect(_on_device_list_changed)
	add_child(_sampler)
	_on_device_list_changed(_sampler.connected_devices())
	_onboarding.call("setup", _flow, _sampler)
	_refresh_screens()


func _process(_delta: float) -> void:
	# 配置错误屏上没有判定：不推进、不分派。
	if _flow == null:
		return
	_flush_button_edges()
	var frame := Frame.new()
	frame.now = Time.get_ticks_usec() / 1_000_000.0
	frame.buttons = _sampler.buffer.pressed_dict()
	_runtime.tick(frame)
	_refresh_screens()


## 唯一的按钮边沿消费者。引导屏不读边沿数组，避免同一次按下被解释两次。
func _flush_button_edges() -> void:
	var edges: Array = _sampler.buffer.button_edges()
	var total := edges.size()
	if total <= _seen_edges:
		return
	for position in range(_seen_edges, total):
		var edge: Dictionary = edges[position]
		if bool(edge.get("pressed", false)):
			_handle_button_edge(edge)
	_seen_edges = total


func _handle_button_edge(edge: Dictionary) -> void:
	if _flow == null:
		return
	var index := int(edge["index"])
	match _flow.state:
		OnboardingFlow.STATE_DEVICE_READY:
			_flow.on_any_button()
		OnboardingFlow.STATE_PROBE_INTRO:
			if index == 0:
				_flow.begin_probe()
		OnboardingFlow.STATE_PROBE_FAILED:
			if index == 1:
				_flow.retry_probe_step()
		OnboardingFlow.STATE_REUSE_CHECK:
			if index == 1:
				# B：放弃复验，走完整四步探针。
				_flow.begin_probe()
		OnboardingFlow.STATE_LAYOUT_CONFIRM:
			_handle_layout_edge(edge)
		_:
			pass


## 布局页分派：保留键优先，其余每一次按下都把**实际索引**交给状态机。
##
## 索引 1 = B（显式接受当前布局）；13 / 14 = 十字键上/下，9 / 10 = LB / RB ——
## 两套都认，因为某些手柄把十字键报成 hat 而不是 button。写死确认索引会让
## `button_index_ok` 永远为真，那条真实设备自检就形同虚设。
func _handle_layout_edge(edge: Dictionary) -> void:
	var index := int(edge["index"])
	match index:
		13, 9:
			_flow.choose_layout(DeviceProfile.LAYOUT_XBOX)
			return
		14, 10:
			_flow.choose_layout(DeviceProfile.LAYOUT_PLAYSTATION)
			return
		1:
			_flow.accept_layout_anyway()
			return
	_flow.confirm_layout(int(edge["index"]), 0)


## 设备列表信号与主动播种共用的唯一回调体。
func _on_device_list_changed(devices: Array) -> void:
	if _flow == null:
		return
	if devices.is_empty():
		if _sampler.buffer.device >= 0:
			_sampler.unbind()
			_seen_edges = 0
			_runtime.set_layout_confirmed(false)
			_flow.on_device_lost()
			_practice_entered = false
		else:
			_flow.on_device_list_changed([], "", "")
		return

	var first := int(devices[0])
	if _sampler.buffer.device >= 0 and _sampler.buffer.device != first:
		# 换了一只手柄：上一只手的布局、校准与进度全部作废。
		_runtime.set_layout_confirmed(false)
		_flow.on_device_lost()
		_practice_entered = false
	# 只在设备真的换了时才重绑：同一设备的重复列表不得清掉按键状态、
	# 也不得把 _seen_edges 归零后重放已经分派过的边沿。
	if _sampler.buffer.device != devices[0]:
		_sampler.bind(first)
		_seen_edges = 0
	_flow.on_device_list_changed(devices, _sampler.device_name(), _sampler.device_guid())

	# 复用门：只在 device_ready 尝试一次，避免练习中重复进入 REUSE_REST。
	if _flow.state == OnboardingFlow.STATE_DEVICE_READY:
		var key := DeviceProfile.make_key(_sampler.device_guid(), _sampler.device_name())
		var profile := _profile_store.find(key)
		if profile != null:
			_flow.offer_profile(profile)


func _refresh_screens() -> void:
	if _flow == null:
		return
	if _flow.can_enter_practice():
		if not _practice_entered:
			_practice_entered = true
			# 成功标准 4 的机械落点：只有五条同时成立时才把运行时置为已确认。
			_runtime.set_layout_confirmed(true)
			_onboarding.visible = false
			_practice_container.visible = true
			_commit_profile()
		return
	_practice_container.visible = false
	_onboarding.visible = true
	if _practice_entered:
		# 回到引导（例如刚刚断连）：运行时必须静默清场，不能带着旧进度继续判。
		_practice_entered = false
		_runtime.set_layout_confirmed(false)


## 进入练习的第一刻落盘档案。失败只记录，不阻塞判定、不弹窗。
func _commit_profile() -> void:
	var profile := _flow.build_profile()
	if profile == null:
		print("PROFILE_ERROR 构建失败，判定继续但不落盘")
		return
	var err := _profile_store.upsert(profile)
	if err != OK:
		print("PROFILE_ERROR 档案落盘失败（错误码 %d），判定继续" % err)


func _show_config_error(text: String) -> void:
	_config_error.text = text
	_config_error.visible = true
	_onboarding.visible = false
	_practice_container.visible = false
