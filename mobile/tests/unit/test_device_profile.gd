extends RefCounted

## 设备档案套件：探针 → 映射 → 校准 → 档案 → 复用门 → 角度接缝。
##
## 为什么全部用合成 raw：探针、校准、复用门必须能在没有手柄、没有时钟、没有文件
## 系统的机器上逐条证明；真机只负责确认「合成数据之外没有意外」（04-07）。
##
## 每个判据都走 reporter 的 check / eq_float，不用 assert；run(r) 的倒数第二句是
## 规模断言（≥ 32 条），最后一句是 r.complete()。

const TOL := 1e-6
const AXIS_COUNT := 6


func run(r) -> void:
	_check_probe_four_steps(r)
	_check_probe_rejections(r)
	_check_evaluate_feeds_cross(r)
	_check_calibration(r)
	_check_normalize_order(r)
	_check_deadzone(r)
	_check_profile_schema(r)
	_check_reuse_gate(r)
	_check_angle_seam(r)
	_check_suggest_layout(r)
	var total: int = r.assertions
	r.check(total >= 32, "本套件至少 32 条断言（实际 %d）" % total)
	r.complete()


func _check_probe_four_steps(r) -> void:
	var rest := ProbeEvaluator.rest_from_samples(_quiet_samples())
	r.check(rest.size() == AXIS_COUNT, "rest 轴数取第一帧长度（实际 %d）" % rest.size())
	r.eq_float(rest[0], 0.02, 1e-9, "rest 取中位数：单帧尖峰没有拉偏基线")
	r.eq_float(rest[1], 0.0, 1e-12, "rest 未动的轴为 0")

	var up := ProbeEvaluator.evaluate_step(_ramp(3, -1.0), rest)
	var right := ProbeEvaluator.evaluate_step(_ramp(2, 1.0), rest)
	var down := ProbeEvaluator.evaluate_step(_ramp(3, 1.0), rest)
	var left := ProbeEvaluator.evaluate_step(_ramp(2, -1.0), rest)
	r.check(up["ok"] == true, "上：可判定（%s）" % str(up["message"]))
	r.check(right["ok"] == true, "右：可判定（%s）" % str(right["message"]))
	r.check(down["ok"] == true, "下：可判定（%s）" % str(down["message"]))
	r.check(left["ok"] == true, "左：可判定（%s）" % str(left["message"]))
	r.check(int(up["axis"]) == 3, "上落在轴 3（实际 %d）" % int(up["axis"]))
	r.check(int(right["axis"]) == 2, "右落在轴 2（实际 %d）" % int(right["axis"]))
	r.check(int(up["axis"]) != int(right["axis"]), "上/右不同轴")
	r.check(int(down["axis"]) == int(up["axis"]), "下与上同轴")
	r.check(int(down["sign"]) == -int(up["sign"]), "下与上反号")
	r.check(int(left["axis"]) == int(right["axis"]), "左与右同轴")
	r.check(int(left["sign"]) == -int(right["sign"]), "左与右反号")
	r.check(float(up["delta"]) < 0.0, "delta 是有符号值（上为负，实际 %.6f）" % float(up["delta"]))
	r.check(int(up["samples"]) == 12, "samples 返回窗口长度（实际 %d）" % int(up["samples"]))
	r.check(float(up["margin"]) > 0.0, "margin 已计算（实际 %.6f）" % float(up["margin"]))
	r.check(float(up["separation"]) >= 3.0, "单轴分离度足够（实际 %.3f）" % float(up["separation"]))

	var mapping := ProbeEvaluator.mapping_from_steps(up, right, down, left)
	r.check(mapping.rs_x_index == int(right["axis"]), "rs_x_index 由 right 给出")
	r.check(mapping.rs_x_sign == int(right["sign"]), "rs_x_sign 由 right 给出")
	r.check(mapping.rs_y_index == int(down["axis"]), "rs_y_index 由 down 给出")
	r.check(mapping.rs_y_sign == int(down["sign"]), "rs_y_sign 由 down 给出")


func _check_probe_rejections(r) -> void:
	var rest := _flat_rest()

	var too_few := ProbeEvaluator.evaluate_step(_flat(3, -1.0, 2), rest)
	r.check(too_few["ok"] == false, "2 帧必须被拒")
	r.check(too_few["code"] == &"not_enough_samples", "2 帧 → not_enough_samples")

	var short_travel := ProbeEvaluator.evaluate_step(_flat(3, -0.3, 12), rest)
	r.check(short_travel["ok"] == false, "位移 0.3 必须被拒")
	r.check(short_travel["code"] == &"not_enough_travel", "位移 0.3 → not_enough_travel")

	var ambiguous := ProbeEvaluator.evaluate_step(_two_axes(3, -0.8, 2, 0.75), rest)
	r.check(ambiguous["ok"] == false, "两轴同时动必须被拒")
	r.check(ambiguous["code"] == &"ambiguous_axes", "两轴 0.8/0.75 → ambiguous_axes")
	r.check(float(ambiguous["margin"]) < ProbeEvaluator.MIN_MARGIN,
		"ambiguous 的 margin 确实低于阈值（实际 %.3f）" % float(ambiguous["margin"]))

	var good_up := {"axis": 3, "sign": -1, "separation": 5.0}
	var good_right := {"axis": 2, "sign": 1, "separation": 5.0}
	var good_down := {"axis": 3, "sign": 1, "separation": 5.0}
	var good_left := {"axis": 2, "sign": -1, "separation": 5.0}
	r.check(ProbeEvaluator.validate_cross(good_up, good_right, good_down, good_left)["ok"] == true,
		"四步正确时交叉校验通过")

	var same_axis_right := {"axis": 3, "sign": 1, "separation": 5.0}
	var same_axis := ProbeEvaluator.validate_cross(good_up, same_axis_right, good_down, good_left)
	r.check(same_axis["code"] == &"same_axis_up_right", "上/右同轴 → same_axis_up_right")

	var non_opposed_down := {"axis": 3, "sign": -1, "separation": 5.0}
	var vertical := ProbeEvaluator.validate_cross(good_up, good_right, non_opposed_down, good_left)
	r.check(vertical["code"] == &"vertical_not_opposed", "上下同号 → vertical_not_opposed")

	var non_opposed_left := {"axis": 2, "sign": 1, "separation": 5.0}
	var horizontal := ProbeEvaluator.validate_cross(good_up, good_right, good_down, non_opposed_left)
	r.check(horizontal["code"] == &"horizontal_not_opposed", "左右同号 → horizontal_not_opposed")

	# 可达的 warning：赢家轴 1.0、第二名轴 0.4 → margin 0.6 能过 evaluate_step，
	# 但 separation 2.5 < 3.0。这条断言证明 warning 不是不可达的装饰。
	var low_sep_step := ProbeEvaluator.evaluate_step(_two_axes(3, -1.0, 2, 0.4), rest)
	r.check(low_sep_step["ok"] == true, "1.0/0.4 仍能通过 evaluate_step（margin 0.6）")
	r.eq_float(float(low_sep_step["separation"]), 2.5, 1e-6, "separation = 1.0 / 0.4")
	r.check(float(low_sep_step["margin"]) >= ProbeEvaluator.MIN_MARGIN,
		"margin 0.6 不低于阈值")
	var with_warning := ProbeEvaluator.validate_cross(low_sep_step, good_right, good_down, good_left)
	r.check(with_warning["ok"] == true, "warning 不阻止继续")
	r.check((with_warning["warnings"] as Array).has(&"low_separation"),
		"分离度 2.5 → low_separation warning")


func _check_evaluate_feeds_cross(r) -> void:
	var rest := _flat_rest()
	# 实参必须直接来自 evaluate_step 的返回字典：两边各写一份键名就会在这里分叉。
	var up := ProbeEvaluator.evaluate_step(_ramp(3, -1.0), rest)
	var right := ProbeEvaluator.evaluate_step(_ramp(2, 1.0), rest)
	var down := ProbeEvaluator.evaluate_step(_ramp(3, 1.0), rest)
	var left := ProbeEvaluator.evaluate_step(_ramp(2, -1.0), rest)
	var cross := ProbeEvaluator.validate_cross(up, right, down, left)
	r.check(cross["ok"] == true, "evaluate_step 的输出直接喂 validate_cross 可通过")
	r.check(cross["code"] == &"", "通过时 code 为空")
	var warnings: Array = cross["warnings"]
	r.check(warnings.is_empty(), "干净的斜坡不应产生 warning（实际 %d 条）" % warnings.size())

	var bad := ProbeEvaluator.validate_cross(up, right, up, left)
	r.check(bad["ok"] == false, "把 down 换成 up 的结果必须被拒")
	r.check(bad["code"] == &"vertical_not_opposed", "同一根轴同一符号 → vertical_not_opposed")


func _check_calibration(r) -> void:
	# 中位数 vs 均值：单帧尖峰把均值拉偏，中位数不动。
	var steady: Array[Vector2] = []
	for i in 15:
		steady.append(Vector2(0.10, 0.0))
	steady[7] = Vector2(0.14, 0.0)
	var steady_result := Calibration.center_from_samples(steady)
	r.check(steady_result["ok"] == true, "中点采样通过（%s）" % str(steady_result["message"]))
	var steady_center: Vector2 = steady_result["center"]
	r.eq_float(steady_center.x, 0.10, TOL, "中点是中位数，不被尖峰拉偏")
	var mean := 0.0
	for sample in steady:
		mean += sample.x
	mean /= 15.0
	r.check(absf(mean - 0.10) > 1e-4,
		"均值确实被尖峰拉偏（%.6f），证明上一条不是恒真" % mean)
	r.eq_float(float(steady_result["peak_to_peak"]), 0.04, TOL, "峰峰值 0.04")

	var few: Array[Vector2] = []
	for i in 14:
		few.append(Vector2.ZERO)
	var few_result := Calibration.center_from_samples(few)
	r.check(few_result["code"] == &"not_enough_samples", "14 帧中点 → not_enough_samples")

	var moving: Array[Vector2] = []
	for i in 15:
		moving.append(Vector2(0.0 if i % 2 == 0 else 0.30, 0.0))
	var moving_result := Calibration.center_from_samples(moving)
	r.check(moving_result["ok"] == false, "峰峰值 0.30 必须被拒")
	r.check(moving_result["code"] == &"hand_on_stick", "峰峰值 0.30 → hand_on_stick")

	var drifted: Array[Vector2] = []
	for i in 15:
		drifted.append(Vector2(0.40, 0.0))
	var drift_result := Calibration.center_from_samples(drifted)
	r.check(drift_result["ok"] == true, "中点漂移只警告，不拒绝启动")
	var drift_warnings: Array = drift_result["warnings"]
	r.check(drift_warnings.size() > 0, "中点漂移必须留下 warning")
	r.check(str(drift_warnings).contains("0.400"), "warning 里带实际值 0.400")

	# 某一轴量程 0.4：峰值 0.9 已过 range_short，但 Y 轴不可用 → scale_too_small。
	var lopsided: Array[Vector2] = [
		Vector2(0.9, 0.0), Vector2(-0.9, 0.0),
		Vector2(0.0, 0.4), Vector2(0.0, -0.4),
	]
	for i in 11:
		lopsided.append(Vector2.ZERO)
	var small_result := Calibration.scale_from_samples(lopsided, Vector2.ZERO)
	r.check(small_result["ok"] == false, "某一轴量程 0.4 必须被拒")
	r.check(small_result["code"] == &"scale_too_small", "某一轴 0.4 → scale_too_small")
	var small_scale: Vector2 = small_result["scale"]
	r.eq_float(small_scale.x, 0.9, TOL, "X 量程 0.9")
	r.eq_float(small_scale.y, 0.4, TOL, "Y 量程 0.4")

	var shallow: Array[Vector2] = []
	for i in 15:
		shallow.append(Vector2(0.4 if i % 2 == 0 else -0.4, 0.3 if i % 2 == 0 else -0.3))
	var short_result := Calibration.scale_from_samples(shallow, Vector2.ZERO)
	r.check(short_result["ok"] == false, "四方向最大位移 0.4 必须被拒")
	r.check(short_result["code"] == &"range_short", "最大位移 0.4 → range_short")

	var wild: Array[Vector2] = [
		Vector2(1.2, 0.0), Vector2(-1.2, 0.0),
		Vector2(0.0, 1.2), Vector2(0.0, -1.2),
	]
	for i in 11:
		wild.append(Vector2.ZERO)
	var wild_result := Calibration.scale_from_samples(wild, Vector2.ZERO)
	r.check(wild_result["ok"] == true, "量程 > 1.0 只夹到 1.0，不拒绝")
	var wild_scale: Vector2 = wild_result["scale"]
	r.eq_float(wild_scale.x, 1.0, 1e-9, "X 量程夹到 1.0")
	r.eq_float(wild_scale.y, 1.0, 1e-9, "Y 量程夹到 1.0")
	var wild_warnings: Array = wild_result["warnings"]
	r.eq_float(float(wild_warnings.size()), 2.0, 1e-12, "两个轴各一条 clamp warning")


func _check_normalize_order(r) -> void:
	r.eq_float(Calibration.normalize(0.02, 0.02, 1.0, 1), 0.0, 0.0,
		"中点样本归一化后必须精确为 0")
	r.eq_float(Calibration.normalize(0.02, 0.02, 1.0, -1), 0.0, 0.0,
		"符号为 -1 时中点仍是 0（-0.0 == 0）")
	r.eq_float(Calibration.normalize(0.52, 0.02, 1.0, 1), 0.5, 1e-12,
		"先减中点再除量程 → 0.5")
	# 若先把符号乘进中点，结果会是 -(0.02) - 0.02 = -0.04。这条把顺序写反钉死。
	r.check(absf(Calibration.normalize(0.02, 0.02, 1.0, -1) + 0.04) > 1e-6,
		"顺序写反会得到 -0.04，当前实现不是那个值")
	r.eq_float(Calibration.normalize(2.0, 0.0, 1.0, 1), 1.0, 0.0, "越界钳到 1.0")
	r.eq_float(Calibration.normalize(-2.0, 0.0, 1.0, 1), -1.0, 0.0, "越界钳到 -1.0")
	r.eq_float(Calibration.normalize(NAN, 0.0, 1.0, 1), 0.0, 0.0, "NaN 回到 0.0")
	r.eq_float(Calibration.normalize(0.5, 0.0, 1.0, -1), -0.5, 1e-12, "符号最后乘")


func _check_deadzone(r) -> void:
	r.check(Calibration.deadzone(0.05, 0.0, 0.08) == Vector2.ZERO,
		"幅度 0.05 < 死区 0.08 → 归零")
	r.check(Calibration.deadzone(0.0, 0.0, 0.08) == Vector2.ZERO,
		"居中 → 归零")

	var diagonal := Calibration.deadzone(1.0, 1.0, 0.08)
	r.check(absf(diagonal.x - diagonal.y) <= TOL, "斜向 (1,1) 方向保持 45°")
	r.eq_float(diagonal.x, 0.7071067811865476, TOL, "斜向输出 x = 0.7071")
	r.check(diagonal.length() <= 1.0 + TOL,
		"输出长度不得超过 1.0（实际 %.12f）" % diagonal.length())
	r.check(diagonal.length() >= 1.0 - TOL,
		"斜向推到底输出长度为 1.0（实际 %.12f）" % diagonal.length())

	var directional := Calibration.deadzone(0.6, 0.8, 0.08)
	r.eq_float(Geometry.angle_diff(Geometry.angle_of(0.6, 0.8),
		Geometry.angle_of(directional.x, directional.y)), 0.0, TOL,
		"死区不改变角度")
	r.eq_float(directional.length(), 1.0, TOL, "满量程方向长度为 1.0")

	var partial := Calibration.deadzone(0.3, 0.4, 0.08)
	r.eq_float(partial.length(), 0.42 / 0.92, TOL, "输出长度 = (m - dz) / (1 - dz)")


func _check_profile_schema(r) -> void:
	_assert_profile_round_trip(r)

	var base: Dictionary = _legal_profile().to_dict()
	var missing_version: Dictionary = base.duplicate(true)
	missing_version.erase("schema_version")
	_expect_invalid(r, missing_version, "缺 schema_version")

	var wrong_version: Dictionary = base.duplicate(true)
	wrong_version["schema_version"] = 2
	_expect_invalid(r, wrong_version, "schema_version = 2")

	var empty_key: Dictionary = base.duplicate(true)
	empty_key["key"] = ""
	_expect_invalid(r, empty_key, "key 为空")

	var empty_profile: Dictionary = base.duplicate(true)
	empty_profile["profile_id"] = ""
	_expect_invalid(r, empty_profile, "profile_id 为空")

	var bad_x_index: Dictionary = base.duplicate(true)
	bad_x_index["axes"]["rs_x"]["index"] = 8
	_expect_invalid(r, bad_x_index, "axes.rs_x.index = 8")

	var bad_x_sign: Dictionary = base.duplicate(true)
	bad_x_sign["axes"]["rs_x"]["sign"] = 0
	_expect_invalid(r, bad_x_sign, "axes.rs_x.sign = 0")

	var bad_y_index: Dictionary = base.duplicate(true)
	bad_y_index["axes"]["rs_y"]["index"] = 8
	_expect_invalid(r, bad_y_index, "axes.rs_y.index = 8")

	var bad_y_sign: Dictionary = base.duplicate(true)
	bad_y_sign["axes"]["rs_y"]["sign"] = 0
	_expect_invalid(r, bad_y_sign, "axes.rs_y.sign = 0")

	var zero_scale_x: Dictionary = base.duplicate(true)
	zero_scale_x["calibration"]["scale_x"] = 0.0
	_expect_invalid(r, zero_scale_x, "calibration.scale_x = 0.0")

	var zero_scale_y: Dictionary = base.duplicate(true)
	zero_scale_y["calibration"]["scale_y"] = 0.0
	_expect_invalid(r, zero_scale_y, "calibration.scale_y = 0.0")

	var string_bool: Dictionary = base.duplicate(true)
	string_bool["layout_confirmed"] = "true"
	_expect_invalid(r, string_bool, "layout_confirmed 是字符串")

	_expect_invalid(r, [base], "根是数组")

	# 直接调用子对象的 from_dict 也必须整份返回 null，而不是「部分可用 + 错误」。
	var axes_errors: Array[ConfigError] = []
	var bad_axes := AxisMapping.from_dict({"rs_x": {"index": 8, "sign": 1}}, axes_errors)
	r.check(bad_axes == null, "AxisMapping.from_dict 直接调用也返回 null")
	var calibration_errors: Array[ConfigError] = []
	var bad_calibration := Calibration.from_dict(
		{"center_x": 0.0, "center_y": 0.0, "scale_x": 0.0, "scale_y": 1.0},
		calibration_errors)
	r.check(bad_calibration == null, "Calibration.from_dict 直接调用也返回 null")


func _check_reuse_gate(r) -> void:
	var profile := _legal_profile()
	r.check(profile.can_reuse(2, -1, 3, -1), "四值逐项相等 → 可复用")
	r.check(not profile.can_reuse(2, 1, 3, -1),
		"同名手柄 + rs_x_sign 反了 → 拒绝（绝不部分应用）")
	r.check(not profile.can_reuse(1, -1, 3, -1), "rs_x_index 换了 → 拒绝")
	r.check(not profile.can_reuse(2, -1, 2, -1), "rs_y_index 换了 → 拒绝")
	r.check(not profile.can_reuse(2, -1, 3, 1),
		"rs_y_sign 反了 → 拒绝（不能只比较 x 分量）")

	var bare := DeviceProfile.new()
	r.check(not bare.can_reuse(2, -1, 3, -1), "axes 为 null → 拒绝")

	# 复用门的范围：只比四项 index+sign。校准完全不同仍然可复用（整份采用档案里的校准）。
	var recalibrated := _legal_profile()
	recalibrated.calibration = Calibration.new()
	recalibrated.calibration.center_x = 0.30
	recalibrated.calibration.center_y = -0.30
	recalibrated.calibration.scale_x = 0.55
	recalibrated.calibration.scale_y = 0.60
	r.check(recalibrated.can_reuse(2, -1, 3, -1),
		"同轴同符号但校准完全不同 → 仍可复用（复用门只比四项）")


func _check_angle_seam(r) -> void:
	var rest := _flat_rest()
	var mapping := ProbeEvaluator.mapping_from_steps(
		ProbeEvaluator.evaluate_step(_ramp(3, -1.0), rest),
		ProbeEvaluator.evaluate_step(_ramp(2, 1.0), rest),
		ProbeEvaluator.evaluate_step(_ramp(3, 1.0), rest),
		ProbeEvaluator.evaluate_step(_ramp(2, -1.0), rest))
	var calibration := Calibration.new()
	var up_raw := _frame(3, -1.0)
	var right_raw := _frame(2, 1.0)
	var down_raw := _frame(3, 1.0)
	var left_raw := _frame(2, -1.0)

	# raw_rs 不乘符号：校准屏在原始轴空间采 center/scale。这里 rs_y_sign = -1，
	# 若 raw_rs 乘了符号，「向上」的 -1.0 会变成 +1.0。
	var raw_pair := mapping.raw_rs(up_raw)
	r.eq_float(raw_pair.x, 0.0, 1e-12, "raw_rs 取 rs_x_index")
	r.eq_float(raw_pair.y, -1.0, 1e-12, "raw_rs 不乘符号（向上仍是原始 -1.0）")

	# 注意 raw 的符号：rs_x_sign = right.sign = +1、rs_y_sign = down.sign = +1，
	# 所以「向右」的 raw 在 rs_x_index 上是 +满量程，「向上」的 raw 在 rs_y_index 上
	# 是 -满量程（SDL y 向下为正）。断言不是写反了。
	var up_v := AxisMapping.snapshot_rs(up_raw, mapping, calibration, 0.08)
	var right_v := AxisMapping.snapshot_rs(right_raw, mapping, calibration, 0.08)
	var down_v := AxisMapping.snapshot_rs(down_raw, mapping, calibration, 0.08)
	var left_v := AxisMapping.snapshot_rs(left_raw, mapping, calibration, 0.08)
	r.eq_float(Geometry.angle_of(up_v.x, up_v.y), 0.0, TOL, "上 = 0°")
	r.eq_float(Geometry.angle_of(right_v.x, right_v.y), 90.0, TOL, "右 = 90°")
	r.eq_float(Geometry.angle_of(down_v.x, down_v.y), 180.0, TOL, "下 = 180°")
	r.eq_float(Geometry.angle_of(left_v.x, left_v.y), 270.0, TOL, "左 = 270°")
	r.check(right_v.length() >= 1.0 - TOL, "满量程经死区后长度仍为 1.0")


func _check_suggest_layout(r) -> void:
	r.check(DeviceProfile.suggest_layout("Xbox Series X Controller") == &"xbox",
		"Xbox Series X Controller → xbox")
	r.check(DeviceProfile.suggest_layout("Xbox Wireless Controller") == &"xbox",
		"Xbox Wireless Controller → xbox（xbox 先于 wireless controller 判定）")
	r.check(DeviceProfile.suggest_layout("DualSense Wireless Controller") == &"playstation",
		"DualSense → playstation")
	r.check(DeviceProfile.suggest_layout("Wireless Controller") == &"playstation",
		"Wireless Controller → playstation")
	r.check(DeviceProfile.suggest_layout("PS5 Controller") == &"playstation",
		"PS5 → playstation")
	r.check(DeviceProfile.suggest_layout("DualShock 4") == &"playstation",
		"DualShock → playstation")
	r.check(DeviceProfile.suggest_layout("") == &"", "空设备名 → 无建议（绝不预选）")
	r.check(DeviceProfile.suggest_layout("8BitDo Pro 2") == &"", "未知名 → 无建议（绝不预选）")


# --- 辅助 -------------------------------------------------------------------

func _flat_rest() -> PackedFloat32Array:
	var rest := PackedFloat32Array()
	rest.resize(AXIS_COUNT)
	return rest


## 静止样本：轴 0 稳定在 0.02，第 6 帧插入一个 0.90 的尖峰（中位数必须不受影响）。
func _quiet_samples() -> Array[PackedFloat32Array]:
	var samples: Array[PackedFloat32Array] = []
	for i in 11:
		var frame := PackedFloat32Array()
		frame.resize(AXIS_COUNT)
		frame[0] = 0.02
		samples.append(frame)
	var spike: PackedFloat32Array = samples[5]
	spike[0] = 0.90
	samples[5] = spike
	return samples


func _frame(axis: int, value: float, axis_count: int = AXIS_COUNT) -> PackedFloat32Array:
	var frame := PackedFloat32Array()
	frame.resize(axis_count)
	frame[axis] = value
	return frame


## 斜坡 + 平台：模拟「推到位」的 300 ms 窗口（0.2 → 1.0，再保持 3 帧）。
func _ramp(axis: int, sign: float, axis_count: int = AXIS_COUNT) -> Array[PackedFloat32Array]:
	var samples: Array[PackedFloat32Array] = []
	for step in 9:
		samples.append(_frame(axis, sign * (0.2 + 0.1 * step), axis_count))
	for _i in 3:
		samples.append(_frame(axis, sign, axis_count))
	return samples


## 恒定窗口：用于需要精确 |delta| 的边界（0.5 / 0.4 这类）。
func _flat(axis: int, value: float, frames: int,
		axis_count: int = AXIS_COUNT) -> Array[PackedFloat32Array]:
	var samples: Array[PackedFloat32Array] = []
	for _i in frames:
		samples.append(_frame(axis, value, axis_count))
	return samples


## 两轴同时动的窗口：赢家轴先写，第二名轴后写。
func _two_axes(winner: int, winner_value: float, second: int, second_value: float,
		frames: int = 12) -> Array[PackedFloat32Array]:
	var samples: Array[PackedFloat32Array] = []
	for _i in frames:
		var frame := PackedFloat32Array()
		frame.resize(AXIS_COUNT)
		frame[winner] = winner_value
		frame[second] = second_value
		samples.append(frame)
	return samples


func _legal_profile() -> DeviceProfile:
	var profile := DeviceProfile.new()
	profile.key = "guid:03000000abc"
	profile.device_name = "Xbox Series X Controller"
	profile.device_guid = "03000000ABC"
	profile.axes = AxisMapping.new()
	profile.axes.rs_x_index = 2
	profile.axes.rs_x_sign = -1
	profile.axes.rs_y_index = 3
	profile.axes.rs_y_sign = -1
	profile.axes.ls_x_index = 0
	profile.axes.ls_x_sign = 1
	profile.axes.ls_y_index = 1
	profile.axes.ls_y_sign = 1
	profile.axes.lt_index = 4
	profile.axes.lt_rest = -1.0
	profile.axes.rt_index = 5
	profile.axes.rt_rest = -1.0
	profile.calibration = Calibration.new()
	profile.calibration.center_x = 0.001
	profile.calibration.center_y = -0.003
	profile.calibration.scale_x = 0.98
	profile.calibration.scale_y = 0.97
	profile.quality = {"up": {"samples": 31, "margin": 0.72, "separation": 6.1}}
	profile.layout = DeviceProfile.LAYOUT_XBOX
	profile.layout_confirmed = true
	profile.button_index_ok = true
	profile.probed_at_iso = "2026-11-05T10:22:31"
	return profile


func _assert_profile_round_trip(r) -> void:
	var source := _legal_profile()
	var errors: Array[ConfigError] = []
	var loaded := DeviceProfile.from_dict(source.to_dict(), errors)
	r.check(loaded != null, "合法档案必须能往返")
	r.check(errors.is_empty(), "合法档案不应产生 ConfigError（实际 %d 条）" % errors.size())
	if loaded == null:
		return
	r.check(loaded.schema_version == 1, "schema_version 往返为 1")
	r.check(loaded.key == source.key, "key 往返一致（实际 %s）" % loaded.key)
	r.check(loaded.profile_id == "primary", "profile_id 默认 primary 且被序列化")
	r.check(loaded.device_name == source.device_name, "device_name 往返一致")
	r.check(loaded.device_guid == source.device_guid, "device_guid 往返一致")
	r.check(loaded.axes != null and loaded.axes.rs_x_index == 2
		and loaded.axes.rs_x_sign == -1, "axes.rs_x 往返一致")
	r.check(loaded.axes != null and loaded.axes.rs_y_index == 3
		and loaded.axes.rs_y_sign == -1, "axes.rs_y 往返一致")
	r.check(loaded.axes != null and loaded.axes.ls_x_index == 0
		and loaded.axes.ls_y_index == 1, "axes.ls_* 往返一致")
	r.check(loaded.calibration != null and loaded.calibration.scale_y > 0.96,
		"calibration 往返一致")
	r.check(loaded.quality.has("up"), "quality 原样保留（内容不做 schema 校验）")
	r.check(loaded.layout == DeviceProfile.LAYOUT_XBOX, "layout 往返一致")
	r.check(loaded.layout_confirmed == true, "layout_confirmed 往返一致")
	r.check(loaded.button_index_ok == true, "button_index_ok 往返一致")
	r.check(loaded.probed_at_iso == source.probed_at_iso, "probed_at_iso 往返一致")


## 非法档案的唯一合法结果：返回 null + 至少一条带 code/fix_hint 的 ConfigError。
func _expect_invalid(r, data: Variant, label: String) -> void:
	var errors: Array[ConfigError] = []
	var loaded := DeviceProfile.from_dict(data, errors)
	r.check(loaded == null, "%s：整份丢弃（返回 null）" % label)
	r.check(errors.size() > 0, "%s：必须给出 ConfigError（实际 %d 条）" % [label, errors.size()])
	var fields_ok := true
	for entry in errors:
		if str(entry.code).is_empty() or entry.fix_hint.is_empty():
			fields_ok = false
	r.check(fields_ok, "%s：每条错误都有 code 与 fix_hint" % label)
