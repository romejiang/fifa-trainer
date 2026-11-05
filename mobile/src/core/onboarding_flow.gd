class_name OnboardingFlow
extends RefCounted

## 首次启动引导的纯状态机：从「没有设备」一路推到「可以进入练习」。
##
## 本状态机只回答两个问题：**下一步是哪一屏**、**能不能进练习**。它不做采样、
## 不读时钟、不写文件、不碰引擎单例 —— 整条路径可以在没有窗口、没有手柄的
## 无头环境里走完（test_onboarding_flow 就是这条证明）。界面只是渲染器：
## 采样窗口由 UI 切好，纯函数结果回填到本对象，状态切换由本对象决定。
##
## 两条硬约束写进结构里，不依赖界面自觉：
##   1. **rest 必须在四步探针之前采集。** `begin_probe()` 只到 `probe_rest`；
##      `submit_probe_step()` 在没有 rest 时直接返回。静止基线是「位移」的参照系，
##      缺了它，四步探针就退化成「猜哪根轴在动」。
##   2. **未确认布局不得进入练习。** `can_enter_practice()` 要求布局确认、中点校准、
##      满量程校准、布局非空、状态为 practice 五条同时成立；`TapRuntime` 侧另有
##      独立的早退，两层都是机械保证。
##
## 校准屏只能通过 `mapping()` 拿到轴映射，再用 `AxisMapping.raw_rs()` 把 raw 转成
## Vector2；**绝不硬编码轴号**。索引与符号完全由四步探针产出，或在复用门通过后
## 整份来自档案。
##
## 状态用 `StringName` 常量而不是枚举类型：与 `Skill.KIND_TAPS` 等既有词汇表一致，
## 也便于把状态写进排障输出。**不设 config_error 状态**：配置错误发生在 main.gd
## 构造本对象之前，状态机没有任何入口能进入它 —— 留一个永远到不了的状态等于
## 给读代码的人一条假路径。

const STATE_NO_DEVICE := &"no_device"
const STATE_DEVICE_READY := &"device_ready"
const STATE_DEVICE_LOST := &"device_lost"
const STATE_PROBE_INTRO := &"probe_intro"
const STATE_PROBE_REST := &"probe_rest"
const STATE_PROBE_UP := &"probe_up"
const STATE_PROBE_RIGHT := &"probe_right"
const STATE_PROBE_DOWN := &"probe_down"
const STATE_PROBE_LEFT := &"probe_left"
const STATE_PROBE_FAILED := &"probe_failed"
const STATE_REUSE_REST := &"reuse_rest"
const STATE_REUSE_CHECK := &"reuse_check"
const STATE_CALIBRATE_CENTER := &"calibrate_center"
const STATE_CALIBRATE_RANGE := &"calibrate_range"
const STATE_LAYOUT_CONFIRM := &"layout_confirm"
const STATE_PRACTICE := &"practice"

## 探针与复验共用的键顺序：四步探针走完四个，复用门只走 right / down 两个。
const PROBE_KEYS: Array[StringName] = [&"up", &"right", &"down", &"left"]
const REUSE_KEYS: Array[StringName] = [&"right", &"down"]
## 静止基线的最少帧数：60 Hz 下 300 ms 有 18 帧；15 是「确实按住了一会儿」的底线。
const MIN_REST_SAMPLES := 15

var state: StringName = STATE_NO_DEVICE
var device_name: String = ""
## 由设备名推导的建议布局；认不出就是空（绝不预选）。
var suggested_layout: StringName = &""
## 用户显式选择的布局；换手柄 / 断连时必须清空。
var chosen_layout: StringName = &""
var layout_confirmed: bool = false
## 确认键的实测索引是否等于标准位置（A / × = 0）。
var button_index_ok: bool = true
var probe_failure_code: StringName = &""
var probe_failure_message: String = ""
## 失败后「重来这一步」要回到的状态。
var retry_state: StringName = &""
## 探针质量：四步各自的 samples / margin / separation，随档案一起落盘。
var quality: Dictionary = {}
## INPUT-03 预留：单档案阶段固定 "primary"。
var profile_id: String = "primary"
## 探针 / 复验共用的静止基线；空数组 = 未采集。
var rest: PackedFloat32Array = PackedFloat32Array()
## 布局页的提示（例如「没认出手柄，请先用十字键左右选择布局」）。
var layout_message: String = ""
## D2 的可见证据：复用门曾经拒绝过一份档案。
var reuse_rejected: bool = false

## 键（String）→ 该步结果字典。String 而不是 StringName：与 quality 的键、
## 测试里的 `_steps["up"]` 字面量保持同一种表示。
var _steps: Dictionary = {}
var _center: Vector2 = Vector2.ZERO
var _scale: Vector2 = Vector2.ONE
var _has_center: bool = false
var _has_scale: bool = false
var _has_rest: bool = false
var _device_guid: String = ""
var _cached_profile: DeviceProfile = null
var _reused_mapping: AxisMapping = null


## 设备列表的唯一入口。空列表 = 没有设备；非空只从「没有设备 / 刚断开」进入，
## 重复列表必须幂等 —— 组合根会在 add_child 的初始 emit 之后主动播种一次。
func on_device_list_changed(devices: Array, first_device_name: String,
		first_device_guid: String) -> void:
	if devices.is_empty():
		if state != STATE_NO_DEVICE:
			on_device_lost()
		return
	if state != STATE_NO_DEVICE and state != STATE_DEVICE_LOST:
		return
	device_name = first_device_name
	_device_guid = first_device_guid
	suggested_layout = DeviceProfile.suggest_layout(device_name)
	# 换手柄后上一只手的布局绝不复用：用户必须重新按键确认。
	chosen_layout = &""
	layout_confirmed = false
	_clear_probe()
	_clear_reuse()
	state = STATE_DEVICE_READY


## 「按任意键唤醒」的全部语义：只在 device_ready 有效。它不是确认键。
func on_any_button() -> bool:
	if state != STATE_DEVICE_READY:
		return false
	state = STATE_PROBE_INTRO
	return true


## 开始四步探针（或放弃复验）。**不允许从 device_ready 直接跳 probe_up**：
## 静止基线必须先采，`submit_probe_step()` 在没有 rest 时会拒绝推进。
func begin_probe() -> void:
	if state != STATE_PROBE_INTRO and state != STATE_REUSE_CHECK:
		return
	_steps.clear()
	_cached_profile = null
	_reused_mapping = null
	reuse_rejected = false
	_clear_failure()
	state = STATE_PROBE_REST


## 当前探针步骤对应的状态常量；非探针状态返回空。
func current_probe_state() -> StringName:
	match current_probe_key():
		&"up":
			return STATE_PROBE_UP
		&"right":
			return STATE_PROBE_RIGHT if state != STATE_REUSE_CHECK else STATE_REUSE_CHECK
		&"down":
			return STATE_PROBE_DOWN if state != STATE_REUSE_CHECK else STATE_REUSE_CHECK
		&"left":
			return STATE_PROBE_LEFT
	return &""


## 当前步骤的键；复用门只走 right / down，两处共用同一套键枚举。
func current_probe_key() -> StringName:
	match state:
		STATE_PROBE_UP:
			return &"up"
		STATE_PROBE_RIGHT:
			return &"right"
		STATE_PROBE_DOWN:
			return &"down"
		STATE_PROBE_LEFT:
			return &"left"
		STATE_REUSE_CHECK:
			# 复用门按 right → down 的顺序实测；已存 right 就轮到 down。
			return &"down" if _steps.has("right") else &"right"
	return &""


## 采集静止基线。样本不够时留在原地并把原因写进 probe_failure_message；
## 这是四步探针唯一的 rest 来源。
func submit_rest_baseline(samples: Array[PackedFloat32Array]) -> void:
	if state != STATE_PROBE_REST:
		return
	if samples.size() < MIN_REST_SAMPLES:
		probe_failure_code = &"not_enough_samples"
		probe_failure_message = "静止样本不够，请保持不动"
		return
	rest = ProbeEvaluator.rest_from_samples(samples)
	_has_rest = true
	_clear_failure()
	state = STATE_PROBE_UP


func rest_baseline() -> PackedFloat32Array:
	return rest


func has_rest() -> bool:
	return _has_rest


## 四步探针的一步。没有 rest 时直接返回（防御，正常时序不可能到这里）。
##
## 成功时保留该步结果，四步齐了做交叉校验；失败时停在 probe_failed 并保留
## **其它已完成步骤** —— 重试只回退出错的那一步，不做整轮清空。
func submit_probe_step(result: Dictionary) -> void:
	if not _has_rest:
		return
	var key := current_probe_key()
	if key == &"":
		return
	var step_key := String(key)
	# 先记下当前步骤的状态再改 state：current_probe_state() 是按 state 反查的，
	# 置成 probe_failed 之后就查不到「出错的是哪一步」了。
	var step_state := current_probe_state()
	if not bool(result.get("ok", false)):
		state = STATE_PROBE_FAILED
		probe_failure_code = StringName(result.get("code", &""))
		probe_failure_message = String(result.get("message", ""))
		retry_state = step_state
		return
	_steps[step_key] = result
	quality[step_key] = {
		"samples": result.get("samples", 0),
		"margin": result.get("margin", 0.0),
		"separation": result.get("separation", 0.0),
	}
	_clear_failure()
	if _steps.size() < PROBE_KEYS.size():
		state = _next_probe_state(step_key)
		return
	var cross := ProbeEvaluator.validate_cross(
		_steps["up"], _steps["right"], _steps["down"], _steps["left"])
	if bool(cross["ok"]):
		state = STATE_CALIBRATE_CENTER
		return
	state = STATE_PROBE_FAILED
	probe_failure_code = StringName(cross["code"])
	probe_failure_message = String(cross["message"])
	retry_state = _cross_retry_state(probe_failure_code)


## 重来这一步。retry_state 是 UP 时整轮重探（rest 已存在就直接回到 probe_up，
## 不重复要求用户松手）；其余步骤只回退到该步，保留其它已完成结果。
func retry_probe_step() -> void:
	if state != STATE_PROBE_FAILED:
		return
	var target := retry_state
	_clear_failure()
	retry_state = &""
	match target:
		STATE_PROBE_UP:
			_steps.clear()
			_reused_mapping = null
			state = STATE_PROBE_UP if _has_rest else STATE_PROBE_REST
		STATE_PROBE_RIGHT, STATE_PROBE_DOWN, STATE_PROBE_LEFT:
			state = target
		_:
			state = STATE_PROBE_UP if _has_rest else STATE_PROBE_REST


## ProfileStore.find(key) 命中后的唯一入口。档案不完整（缺 axes / calibration）
## 返回 false，调用方走完整四步探针。
func offer_profile(profile: DeviceProfile) -> bool:
	if state != STATE_DEVICE_READY:
		return false
	if profile == null or profile.axes == null or profile.calibration == null:
		return false
	_cached_profile = profile
	_steps.clear()
	state = STATE_REUSE_REST
	return true


## 复用门的静止基线：与四步探针相同的样本下限与中位数计算。
func submit_reuse_rest(samples: Array[PackedFloat32Array]) -> void:
	if state != STATE_REUSE_REST:
		return
	if samples.size() < MIN_REST_SAMPLES:
		probe_failure_code = &"not_enough_samples"
		probe_failure_message = "静止样本不够，请保持不动"
		return
	rest = ProbeEvaluator.rest_from_samples(samples)
	_has_rest = true
	_clear_failure()
	state = STATE_REUSE_CHECK


## 复用门的实测步：只验 right / down 两步。
##
## 四项（rs_x index/sign、rs_y index/sign）逐项相等才整份采用档案；只要有一项
## 不同，就整份丢弃并转完整探针 —— **绝不部分应用**，也不静默覆盖校准。
## 复用成功后 `chosen_layout` 仍清空：成功标准 4 要求用户按键确认布局。
func submit_reuse_step(result: Dictionary) -> void:
	if state != STATE_REUSE_CHECK:
		return
	if not bool(result.get("ok", false)) or _cached_profile == null:
		_reject_reuse()
		return
	var key := current_probe_key()
	if key == &"":
		return
	_steps[String(key)] = result
	quality[String(key)] = {
		"samples": result.get("samples", 0),
		"margin": result.get("margin", 0.0),
		"separation": result.get("separation", 0.0),
	}
	if _steps.size() < REUSE_KEYS.size():
		return
	var right: Dictionary = _steps["right"]
	var down: Dictionary = _steps["down"]
	if not _cached_profile.can_reuse(
			int(right["axis"]), int(right["sign"]), int(down["axis"]), int(down["sign"])):
		_reject_reuse()
		return
	_reused_mapping = _cached_profile.axes
	_center = Vector2(_cached_profile.calibration.center_x,
		_cached_profile.calibration.center_y)
	_scale = Vector2(_cached_profile.calibration.scale_x,
		_cached_profile.calibration.scale_y)
	_has_center = true
	_has_scale = true
	quality = _cached_profile.quality.duplicate(true)
	_steps.clear()
	_cached_profile = null
	reuse_rejected = false
	# 布局仍按本次设备名重算；上一只手的选择绝不带过来。
	suggested_layout = DeviceProfile.suggest_layout(device_name)
	chosen_layout = &""
	state = STATE_LAYOUT_CONFIRM


## 校准屏访问轴映射的唯一入口。复用成功时返回档案里的映射；否则要求四步齐了
## 才能从探针结果推导。缺步返回 null。
func mapping() -> AxisMapping:
	if _reused_mapping != null:
		return _reused_mapping
	if _steps.size() < PROBE_KEYS.size():
		return null
	return ProbeEvaluator.mapping_from_steps(
		_steps["up"], _steps["right"], _steps["down"], _steps["left"])


## 中点校准。被拒时留在本屏并把具体原因写进 probe_failure_message（界面负责
## 把它渲染出来）；成功必须清掉上一条失败文案，否则屏幕会一直挂着旧原因。
func submit_calibration_center(result: Dictionary) -> void:
	if state != STATE_CALIBRATE_CENTER:
		return
	if not bool(result.get("ok", false)):
		probe_failure_code = StringName(result.get("code", &""))
		probe_failure_message = String(result.get("message", ""))
		return
	_center = result.get("center", Vector2.ZERO)
	_has_center = true
	_clear_failure()
	state = STATE_CALIBRATE_RANGE


## 满量程校准。拒绝路径与中点校准完全相同：留在本屏 + 可渲染的原因。
func submit_calibration_range(result: Dictionary) -> void:
	if state != STATE_CALIBRATE_RANGE:
		return
	if not bool(result.get("ok", false)):
		probe_failure_code = StringName(result.get("code", &""))
		probe_failure_message = String(result.get("message", ""))
		return
	_scale = result.get("scale", Vector2.ONE)
	_has_scale = true
	_clear_failure()
	state = STATE_LAYOUT_CONFIRM


## 显式选择布局。只接受两个合法值；其它值忽略（不猜、不落默认）。
func choose_layout(layout: StringName) -> void:
	if state != STATE_LAYOUT_CONFIRM:
		return
	if layout != DeviceProfile.LAYOUT_XBOX and layout != DeviceProfile.LAYOUT_PLAYSTATION:
		return
	chosen_layout = layout
	layout_message = ""


## 用户选择优先，其次设备名建议；两者都空返回空。
func effective_layout() -> StringName:
	if chosen_layout != &"":
		return chosen_layout
	return suggested_layout


## 按键确认。调用方**必须**把本次实际按下的索引传进来（`confirm_layout(实际索引, 0)`）；
## 写死 0 会让 button_index_ok 永远为真，这条检查就形同虚设。
##
## 布局为空时先要求用户选择：绝不静默按 Xbox 进练习。
func confirm_layout(button_index: int, expected_index := 0) -> void:
	if state != STATE_LAYOUT_CONFIRM:
		return
	if effective_layout() == &"":
		layout_message = "没认出手柄，请先用十字键左右选择布局"
		layout_confirmed = false
		return
	if button_index == expected_index:
		button_index_ok = true
		layout_confirmed = true
		layout_message = ""
		state = STATE_PRACTICE
		return
	button_index_ok = false
	layout_confirmed = false
	layout_message = "按到的是索引 %d，说明这把手的键位与标准不同" % button_index


## 「仍然使用此布局」：布局必须已确定；button_index_ok 保持实测值。
func accept_layout_anyway() -> void:
	if state != STATE_LAYOUT_CONFIRM:
		return
	if effective_layout() == &"":
		layout_message = "没认出手柄，请先用十字键左右选择布局"
		return
	layout_confirmed = true
	state = STATE_PRACTICE


## 断连：一切进度作废。重连必须重走探针，上一只手的布局不得残留。
func on_device_lost() -> void:
	state = STATE_DEVICE_LOST
	layout_confirmed = false
	chosen_layout = &""
	suggested_layout = &""
	_clear_probe()
	_clear_reuse()
	button_index_ok = true


## 成功标准 4 在纯层的落点：五条同时成立才算。
func can_enter_practice() -> bool:
	return (
		layout_confirmed
		and _has_center
		and _has_scale
		and effective_layout() != &""
		and state == STATE_PRACTICE
	)


## 进入练习时构建档案。未完成流程 / 没有映射 / 布局为空时返回 null。
## `probed_at_iso` 留空：墙钟由 ProfileStore.upsert 填，core 不读时钟。
func build_profile() -> DeviceProfile:
	if not can_enter_practice():
		return null
	var axes := mapping()
	if axes == null:
		return null
	var layout := effective_layout()
	if layout == &"":
		return null
	var profile := DeviceProfile.new()
	profile.key = DeviceProfile.make_key(_device_guid, device_name)
	profile.device_name = device_name
	profile.device_guid = _device_guid
	profile.profile_id = profile_id
	profile.axes = axes
	profile.calibration = Calibration.new()
	profile.calibration.center_x = _center.x
	profile.calibration.center_y = _center.y
	profile.calibration.scale_x = _scale.x
	profile.calibration.scale_y = _scale.y
	profile.quality = quality.duplicate(true)
	profile.layout = layout
	profile.layout_confirmed = true
	profile.button_index_ok = button_index_ok
	profile.probed_at_iso = ""
	return profile


func _reject_reuse() -> void:
	reuse_rejected = true
	_reused_mapping = null
	_cached_profile = null
	_steps.clear()
	# 复验阶段的质量指标不能和随后完整探针的混在一起：整份丢弃就是整份丢弃。
	quality.clear()
	probe_failure_code = &"reuse_mismatch"
	probe_failure_message = "这次实测与上次记录的轴不一致，已丢弃旧档案，需要重新探测四步。"
	retry_state = STATE_PROBE_UP
	state = STATE_PROBE_FAILED


func _next_probe_state(step_key: String) -> StringName:
	match step_key:
		"up":
			return STATE_PROBE_RIGHT
		"right":
			return STATE_PROBE_DOWN
		"down":
			return STATE_PROBE_LEFT
	return STATE_PROBE_UP


## 交叉校验失败时回到哪一步：上/右同轴 → 重测右；上下不反号 → 重测下；
## 左右不反号 → 重测左；其它 → 整轮重探。
func _cross_retry_state(code: StringName) -> StringName:
	match code:
		&"same_axis_up_right":
			return STATE_PROBE_RIGHT
		&"vertical_not_opposed":
			return STATE_PROBE_DOWN
		&"horizontal_not_opposed":
			return STATE_PROBE_LEFT
	return STATE_PROBE_UP


func _clear_probe() -> void:
	_steps.clear()
	quality.clear()
	rest = PackedFloat32Array()
	_has_rest = false
	_has_center = false
	_has_scale = false
	_center = Vector2.ZERO
	_scale = Vector2.ONE
	retry_state = &""
	_clear_failure()
	layout_message = ""


func _clear_reuse() -> void:
	_cached_profile = null
	_reused_mapping = null
	reuse_rejected = false


func _clear_failure() -> void:
	probe_failure_code = &""
	probe_failure_message = ""
