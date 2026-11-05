extends RefCounted

## 组合根接线的无头套件（Phase 5 计划 07 的 Task 1 / Task 2）。
##
## 它回答三个没有设备也能回答的问题：
##   1. `FrameBuilder` 的四个字段与 `AxisMapping.snapshot_*` + `Geometry` 是否同一份
##      语义（角度 90° / 0°、回中为零、幅度 1.0）；
##   2. 无档案（`mapping == null` / `calibration == null`）时是否「四字段写 0」而不是
##      崩溃或降级校准；
##   3. 组合根是否真的只剩一条换算入口 —— 用**源码结构断言**钉死，因为这类分叉
##      在运行期看起来完全正常（`main.gd` 自写一份归一化，屏幕上的角度只是悄悄偏了）。
##
## 第三种断言故意读源码：它是唯一能区分「调用 `FrameBuilder`」与「另写一份减中点
## 除量程」的证据。变异验证（D-10）会删掉被保护的那一行，证明断言确实有牙齿。
##
## 本套件不加 `class_name`（项目约定：测试脚不污染全局命名空间，也不进导出包）。

const MAIN_PATH := "res://src/ui/main.gd"
const PRACTICE_PATH := "res://src/ui/practice_screen.gd"
const CONFIG_PATH := "res://assets/config/skills_config.json"
## 与真实配置的输入死区同值（`input.deadzone`）；四舍五入不影响 90° / 0° 的判定。
const DEADZONE := 0.08
## 浮点比较的唯一容差：角度与幅度都在归一化空间里，1e-9 足以区分 1 ulp。
const EPSILON := 1e-9


func run(r) -> void:
	_check_frame_fields(r)
	_check_centered(r)
	_check_facing_frozen(r)
	_check_null_contract(r)
	_check_main_source(r)
	_check_drain_source(r)
	r.complete()


## 组 1：右摇杆推到 90°、左摇杆推到 0° 时，四个字段与 `snapshot_*` + `Geometry`
## 逐项一致，且落在两条已知轨迹的精确值上。
func _check_frame_fields(r) -> void:
	var profile := _profile()
	r.check(profile.can_enter_practice(),
		"前置：测试档案必须自洽（can_enter_practice 为真），否则 null 对照没有意义")
	# 90° = 右。RS 的 X 符号是 -1，所以原始轴要写 -1 才归一化成 +1。
	var raw_right := _raw([0.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var frame_right := FrameBuilder.make(raw_right, profile.axes, profile.calibration,
		DEADZONE, 0.0, {})
	_assert_matches_snapshots(r, frame_right, raw_right, profile, "右摇杆 90°")
	r.eq_float(frame_right.rs_angle, 90.0, EPSILON, "右摇杆推到右边必须得到 90°")
	r.eq_float(frame_right.rs_mag, 1.0, EPSILON, "右摇杆推到底的幅度必须是 1.0")
	r.eq_float(frame_right.ls_mag, 0.0, EPSILON, "左摇杆未推时幅度必须为 0")

	# 0° = 上。LS 的 Y 符号是 +1，推上在 Godot 坐标里是负的 y。
	var raw_up := _raw([0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var frame_up := FrameBuilder.make(raw_up, profile.axes, profile.calibration,
		DEADZONE, 0.0, {})
	_assert_matches_snapshots(r, frame_up, raw_up, profile, "左摇杆 0°")
	r.eq_float(frame_up.ls_angle, 0.0, EPSILON, "左摇杆推上必须得到 0°")
	r.eq_float(frame_up.ls_mag, 1.0, EPSILON, "左摇杆推到底的幅度必须是 1.0")
	r.eq_float(frame_up.rs_mag, 0.0, EPSILON, "右摇杆未推时幅度必须为 0")


## 组 2：两杆都回中时四个字段全为 0（死区把小噪声吃掉，而不是留下残角）。
func _check_centered(r) -> void:
	var profile := _profile()
	var raw := _raw([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var frame := FrameBuilder.make(raw, profile.axes, profile.calibration, DEADZONE, 0.0, {})
	r.eq_float(frame.rs_mag, 0.0, EPSILON, "两杆回中时右摇杆幅度必须为 0")
	r.eq_float(frame.ls_mag, 0.0, EPSILON, "两杆回中时左摇杆幅度必须为 0")
	r.eq_float(frame.rs_angle, 0.0, EPSILON, "两杆回中时右摇杆角度必须为 0")
	r.eq_float(frame.ls_angle, 0.0, EPSILON, "两杆回中时左摇杆角度必须为 0")


## 组 3：左摇杆回中后 `facing` 冻结在上一次方向，相对技能不会在无基准时重新定基准。
## 第一帧用 `FrameBuilder` 组出来（LS 推到 90°），第二帧回中：`facing` 必须仍是 90°。
func _check_facing_frozen(r) -> void:
	var config := _load_config(r)
	if config == null:
		return
	var engine := GestureEngine.new(config, true)
	var profile := _profile()
	var raw_right := _raw([1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var pushed := FrameBuilder.make(raw_right, profile.axes, profile.calibration,
		DEADZONE, 1.0, {})
	engine.tick(pushed)
	r.check(pushed.ls_mag >= 0.35,
		"前置：左摇杆推到底的幅度必须 ≥ ls_facing_threshold（实际 %f）" % pushed.ls_mag)
	r.eq_float(pushed.facing, 90.0, EPSILON, "LS 推到 90° 时 facing 必须更新为 90°")

	var centered := FrameBuilder.make(_raw([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]),
		profile.axes, profile.calibration, DEADZONE, 1.1, {})
	engine.tick(centered)
	r.eq_float(centered.ls_mag, 0.0, EPSILON, "回中帧的 ls_mag 必须是 0")
	r.eq_float(centered.facing, 90.0, EPSILON, "LS 回中后 facing 必须冻结在 90°")


## 组 4：null 契约。无档案不是「崩溃」也不是「用默认校准」，而是四个字段写 0。
##
## 行为断言之外还要一条源码断言：`AxisMapping.snapshot_*` 自己也对 null 返回 ZERO，
## 所以「删掉早退直接调 snapshot_*」在行为上**看不出区别**。显式早退的价值是让这条
## 语义不依赖被调方的实现细节（被调方将来若改成抛错就晚了）—— 只有结构断言能钉住它，
## 变异验证 3 正是删这一行。
func _check_null_contract(r) -> void:
	var raw := _raw([1.0, -1.0, 1.0, -1.0, 0.5, 0.5, 0.0, 0.0])
	var frame := FrameBuilder.make(raw, null, null, DEADZONE, 0.0, {})
	r.eq_float(frame.rs_angle, 0.0, EPSILON, "无档案时 rs_angle 必须是 0")
	r.eq_float(frame.rs_mag, 0.0, EPSILON, "无档案时 rs_mag 必须是 0")
	r.eq_float(frame.ls_angle, 0.0, EPSILON, "无档案时 ls_angle 必须是 0")
	r.eq_float(frame.ls_mag, 0.0, EPSILON, "无档案时 ls_mag 必须是 0")
	# 有映射但无校准同样必须早退：缺任何一半都不能「降级校准」。
	var profile := _profile()
	var half := FrameBuilder.make(raw, profile.axes, null, DEADZONE, 0.0, {})
	r.eq_float(half.rs_mag, 0.0, EPSILON, "只有映射没有校准时 rs_mag 必须是 0")
	r.eq_float(half.ls_mag, 0.0, EPSILON, "只有映射没有校准时 ls_mag 必须是 0")
	var builder := _read_source("res://src/core/frame_builder.gd")
	r.check(builder.contains("if mapping == null or calibration == null"),
		"FrameBuilder.fill 必须有显式的无档案早退（不依赖 snapshot_* 的 null 判断）")


## 组 5：组合根的源码结构。`FrameBuilder` 必须存在、不能有第二份归一化、类型必须是
## `GestureEngine`，且 `_profile` 的调用点是 null 安全的。
func _check_main_source(r) -> void:
	var source := _read_source(MAIN_PATH)
	r.check(not source.is_empty(), "必须能读到 %s" % MAIN_PATH)
	if source.is_empty():
		return
	r.check(source.contains("FrameBuilder"),
		"main.gd 必须调用 FrameBuilder（raw → Frame 的唯一入口）")
	r.check(not source.contains("Calibration.normalize"),
		"main.gd 不得出现第二份归一化（Calibration.normalize 必须为零次）")
	r.check(source.contains("var _runtime: GestureEngine"),
		"main.gd 的 _runtime 声明类型必须是 GestureEngine")
	r.check(not source.contains("select_taps_skill"),
		"组合根不再只练单一 taps 动作（select_taps_skill 必须为零次）")
	r.check(source.contains("var _profile: DeviceProfile = null"),
		"main.gd 必须有显式的 _profile 字段（null = 无档案）")
	r.check(source.contains("_profile.axes if _profile != null"),
		"FrameBuilder 调用点必须对 _profile 做 null 安全处理")
	r.check(source.contains("_profile = null"),
		"设备列表变化 / 解绑时必须显式清掉 _profile")


## 组 6：唯一 drain 点与「日志先写」。这两条在运行期都看不出来 —— 第二个 drain
## 只会让屏幕上少一条结果，日志写在横幅之后只会让日志少一条 —— 只能用源码结构钉死。
func _check_drain_source(r) -> void:
	var practice := _read_source(PRACTICE_PATH)
	var main := _read_source(MAIN_PATH)
	r.check(not practice.is_empty(), "必须能读到 %s" % PRACTICE_PATH)
	if practice.is_empty():
		return
	var log_index := practice.find("InputLog.outcome(")
	var banner_index := practice.find("show_outcome(")
	r.check(log_index >= 0, "practice_screen 必须写 OUTCOME 日志行")
	r.check(banner_index >= 0, "practice_screen 必须把结果交给横幅")
	r.check(log_index >= 0 and banner_index >= 0 and log_index < banner_index,
		"日志必须在 show_outcome 之前写（日志 %d，横幅 %d）" % [log_index, banner_index])
	var drains := _count(practice, "pop_outcomes(")
	r.check(drains == 1, "practice_screen 必须恰好一个 drain 点（实际 %d）" % drains)
	var main_drains := _count(main, "pop_outcomes(")
	r.check(main_drains == 0, "main.gd 不得再 drain 一次（实际 %d）" % main_drains)
	r.check(practice.contains("var _runtime: GestureEngine"),
		"practice_screen._runtime 的类型必须是 GestureEngine")
	r.check(practice.contains("setup(p_runtime: GestureEngine"),
		"practice_screen.setup 的参数类型必须是 GestureEngine")


## 用同一组 raw 对照 `snapshot_*` + `Geometry`：四个字段逐项一致。
func _assert_matches_snapshots(r, frame: Frame, raw: PackedFloat32Array,
		profile: DeviceProfile, label: String) -> void:
	var rs := AxisMapping.snapshot_rs(raw, profile.axes, profile.calibration, DEADZONE)
	var ls := AxisMapping.snapshot_ls(raw, profile.axes, profile.calibration, DEADZONE)
	r.eq_float(frame.rs_angle, Geometry.angle_of(rs.x, rs.y), EPSILON,
		"%s：rs_angle 必须与 snapshot_rs + Geometry.angle_of 一致" % label)
	r.eq_float(frame.rs_mag, Geometry.magnitude(rs.x, rs.y), EPSILON,
		"%s：rs_mag 必须与 snapshot_rs + Geometry.magnitude 一致" % label)
	r.eq_float(frame.ls_angle, Geometry.angle_of(ls.x, ls.y), EPSILON,
		"%s：ls_angle 必须与 snapshot_ls + Geometry.angle_of 一致" % label)
	r.eq_float(frame.ls_mag, Geometry.magnitude(ls.x, ls.y), EPSILON,
		"%s：ls_mag 必须与 snapshot_ls + Geometry.magnitude 一致" % label)


## 一份自洽的 v2 档案：RS=(2,3) sign=(-1,1)、LS=(0,1) sign=(1,1)，两套校准齐备，
## `quality` 同时带 `range_ready` 与 `ls_ready`。`can_enter_practice()` 必须为真 ——
## 否则后面的「无档案」对照就没有意义（档案本身不合格，null 与坏档案无法区分）。
func _profile() -> DeviceProfile:
	var axes := AxisMapping.new()
	axes.rs_x_index = 2
	axes.rs_y_index = 3
	axes.rs_x_sign = -1
	axes.rs_y_sign = 1
	axes.ls_x_index = 0
	axes.ls_y_index = 1
	axes.ls_x_sign = 1
	axes.ls_y_sign = 1

	var calibration := Calibration.new()
	calibration.center_x = 0.0
	calibration.center_y = 0.0
	calibration.scale_x = 1.0
	calibration.scale_y = 1.0
	calibration.ls_center_x = 0.0
	calibration.ls_center_y = 0.0
	calibration.ls_scale_x = 1.0
	calibration.ls_scale_y = 1.0

	var profile := DeviceProfile.new()
	profile.key = "guid:test-practice-wiring"
	profile.device_name = "测试手柄"
	profile.axes = axes
	profile.calibration = calibration
	profile.quality = {"range_ready": true, "ls_ready": true}
	profile.layout = DeviceProfile.LAYOUT_XBOX
	profile.layout_confirmed = true
	return profile


## 八元素 raw 数组；缺省补 0。
func _raw(values: Array) -> PackedFloat32Array:
	var raw := PackedFloat32Array()
	raw.resize(PadStateBuffer.MAX_AXIS)
	for index in PadStateBuffer.MAX_AXIS:
		raw[index] = float(values[index]) if index < values.size() else 0.0
	return raw


## 真实配置字节 → 解码 → 校验。`facing` 的冻结只看 `input.ls_facing_threshold`，
## 但用它而不是手搓 AppConfig，能同时证明「组合根拿到的就是这一份配置」。
func _load_config(r) -> AppConfig:
	var bytes := FileAccess.get_file_as_bytes(CONFIG_PATH)
	if bytes.is_empty():
		r.check(false, "读不到真实配置 %s（先运行 python3 tools/sync_config.py）" % CONFIG_PATH)
		return null
	var decoded := ConfigLoader.decode_bytes(bytes, CONFIG_PATH)
	if decoded["error"] != null:
		var error: ConfigError = decoded["error"]
		r.check(false, "真实配置字节解码失败：%s" % error.message)
		return null
	var result := ConfigValidator.validate(decoded["data"], CONFIG_PATH)
	if not result.ok():
		r.check(false, "真实配置未通过校验：%s" % result.to_text())
		return null
	return result.config


static func _read_source(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


## 非重叠计数：源码结构断言用它证明「恰好一次 / 零次」。
static func _count(text: String, needle: String) -> int:
	var total := 0
	var start := 0
	while true:
		var found := text.find(needle, start)
		if found < 0:
			break
		total += 1
		start = found + needle.length()
	return total
