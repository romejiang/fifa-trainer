extends RefCounted

## 手势检测器黄金回放：把 Python 生成的时间轴逐帧喂给 GDScript 检测器，
## 逐字段比对 `skill` / `ok` / `code` / `message` / `elapsed_ms` / `at` / `detail`。
##
## 为什么用 FileAccess.get_file_as_bytes + JSON.new().parse()：与 test_tap_detector.gd
## 同一理由 —— 读字节不做字符串层面的意外转换；parse_string() 失败时会向 stderr
## 打 ERROR 且不给行号。
##
## 为什么必须从夹具的 `configs` 构造 AppConfig：变体 / 合成用例不能被静默按出厂阈值
## 回放，否则 `mismatches=0` 只是「与出厂副本一致」，不是「与 Python 参考一致」。
## 本套件**不读** `res://assets/config/` 的出厂副本。
##
## 为什么必须走 DetectorFactory.build(skill)：检测器按 `skill.kind` 分派。硬编码
## `ArcDetector.new(skill)` 会让非弧线技能被弧线检测器回放，期望值与回放结果一起跑偏。
##
## 判据全部走 reporter 的 check / eq_float，不用 assert；最后一句必须是 r.complete()。
## 哨兵 `GESTURE_GOLDEN cases=N mismatches=0` 在 r.complete() **之前**打印。

const GOLDEN_PATH := "res://tests/fixtures/gesture_golden.json"
const TOL := 1e-6

## 逐条点名的 detector 用例：少一条就红。删掉大半夹具时，逐用例循环会零次
## 「通过」，所以规模与 id 下限必须先于任何回放执行。
const REQUIRED_DETECTOR_IDS: Array[String] = [
	"det_roulette_ok",
	"det_stepover_ok",
	"det_heel_to_heel_ok",
	"det_croqueta_ok",
	"det_green_finesse_ok",
	"det_roulette_too_fast",
	"det_roulette_too_slow",
	"det_stepover_wrong_start",
	"det_roulette_wrong_end",
	"det_croqueta_hold_short",
]

var _mismatches := 0


func run(r) -> void:
	var data := _load_fixture(r)
	if data.is_empty():
		r.complete()
		return
	var cases := _detector_cases(data)
	_check_meta(r, data)
	_check_scale(r, cases)
	_check_frame_grid(r, cases)

	var shipped := _config_for(r, data, "shipped")
	if shipped == null:
		print("GESTURE_GOLDEN cases=%d mismatches=%d" % [cases.size(), _mismatches])
		r.complete()
		return
	# 三条按 kind 分派的点名检查：硬编码 ArcDetector 或「按 id 选检测器」都会红。
	_check_factory_arc(r, shipped)
	_check_factory_sequence(r, shipped)
	_check_factory_taps(r, shipped)

	for case in cases:
		_check_case(r, data, case)
	print("GESTURE_GOLDEN cases=%d mismatches=%d" % [cases.size(), _mismatches])
	r.complete()


func _load_fixture(r) -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes(GOLDEN_PATH)
	if bytes.is_empty():
		r.check(false, "读不到手势黄金夹具：%s（运行 python3 tools/gen_gesture_golden.py 生成）" % GOLDEN_PATH)
		return {}
	var json := JSON.new()
	if json.parse(bytes.get_string_from_utf8()) != OK:
		r.check(false, "手势黄金夹具不是合法 JSON（第 %d 行：%s）"
			% [json.get_error_line() + 1, json.get_error_message()])
		return {}
	if typeof(json.data) != TYPE_DICTIONARY:
		r.check(false, "手势黄金夹具的根节点必须是对象")
		return {}
	var data: Dictionary = json.data
	_eq_int(r, int(data.get("schema_version", 0)), 1, "夹具 schema_version 必须是 1")
	for key in ["schema_version", "source", "meta", "configs", "cases"]:
		r.check(data.has(key), "夹具必须包含顶层键 %s" % key)
	return data


func _detector_cases(data: Dictionary) -> Array:
	var filtered: Array = []
	for case in data.get("cases", []):
		if typeof(case) == TYPE_DICTIONARY and str(case.get("kind", "")) == "detector":
			filtered.append(case)
	return filtered


func _check_meta(r, data: Dictionary) -> void:
	var meta: Dictionary = data.get("meta", {})
	_eq_int(r, int(meta.get("hz", 0)), 250, "meta.hz 必须是 250")
	_eq_int(r, int(meta.get("step_ms", 0)), 4, "meta.step_ms 必须是 4")
	var source: Dictionary = data.get("source", {})
	var digests: Dictionary = source.get("sha256", {})
	for key in ["detectors", "engine", "config", "skills_config"]:
		r.check(digests.has(key), "source.sha256 必须包含 %s" % key)


## 规模与 id 下限：删空夹具、丢掉点名用例、复制 id 都必须变红。
## 下限与 `test-core.sh` 的 grep 是**同一个数字**：两层不一致等于允许删语料仍绿。
func _check_scale(r, cases: Array) -> void:
	r.check(cases.size() >= 28, "detector 用例至少 28 条（实际 %d）" % cases.size())
	if cases.size() < 28:
		_mismatches += 1
	var ids: Dictionary = {}
	for case in cases:
		ids[str(case.get("id", ""))] = true
	_eq_int(r, ids.size(), cases.size(), "每条用例都必须有唯一 id")
	for required_id in REQUIRED_DETECTOR_IDS:
		var present: bool = ids.has(required_id)
		r.check(present, "detector 用例必须包含点名 id %s" % required_id)
		if not present:
			_mismatches += 1


## 从夹具的 `configs` 注册表构造 AppConfig：不读 res://assets/config/ 的出厂副本。
func _config_for(r, data: Dictionary, key: String) -> AppConfig:
	var configs: Dictionary = data.get("configs", {})
	if not configs.has(key):
		_fail(r, "config 键 %s 不在 configs 注册表里" % key)
		return null
	var result := ConfigValidator.validate(configs[key], "<gesture_golden:%s>" % key)
	if not result.ok():
		_fail(r, "configs[%s] 无法通过 ConfigValidator：%s" % [key, result.to_text()])
		return null
	return result.config


## 2 个弧线动作：分派表若把 arc 指向 sequence/taps，这两条立刻红。
func _check_factory_arc(r, config: AppConfig) -> void:
	_expect_detector_class(r, config, "马赛回旋 Roulette", Skill.KIND_ARC, "ArcDetector")
	_expect_detector_class(r, config, "踩单车 Stepover", Skill.KIND_ARC, "ArcDetector")


## 2 个序列动作：这是「按 kind 而不是按名字」的核心证明。
func _check_factory_sequence(r, config: AppConfig) -> void:
	_expect_detector_class(r, config, "磕球过人 Heel-to-Heel", Skill.KIND_SEQUENCE, "SequenceDetector")
	_expect_detector_class(r, config, "油炸丸子 La Croqueta", Skill.KIND_SEQUENCE, "SequenceDetector")


## 1 个按键动作：三类各覆盖，缺一类就不是完整分派表。
func _check_factory_taps(r, config: AppConfig) -> void:
	_expect_detector_class(r, config, "绿色搓射 Green Finesse", Skill.KIND_TAPS, "TapDetector")


func _expect_detector_class(r, config: AppConfig, skill_name: String,
		expected_kind: StringName, expected_class: String) -> void:
	var skill := _find_skill(config, skill_name)
	if skill == null:
		_fail(r, "工厂检查：配置里找不到 %s" % skill_name)
		return
	if skill.kind != expected_kind:
		_fail(r, "工厂检查：%s 的 kind 是 %s，期望 %s"
			% [skill_name, str(skill.kind), str(expected_kind)])
		return
	var detector := DetectorFactory.build(skill)
	if detector == null:
		_fail(r, "工厂检查：DetectorFactory.build(%s) 返回 null" % skill_name)
		return
	var actual := ""
	if detector is ArcDetector:
		actual = "ArcDetector"
	elif detector is SequenceDetector:
		actual = "SequenceDetector"
	elif detector is TapDetector:
		actual = "TapDetector"
	r.check(actual == expected_class, "工厂检查：%s -> %s（期望 %s）"
		% [skill_name, actual, expected_class])
	if actual != expected_class:
		_mismatches += 1


## 所有帧必须落在 250 Hz / 4ms 网格上，且五元组形状正确。
func _check_frame_grid(r, cases: Array) -> void:
	for case in cases:
		var case_id := str(case.get("id", ""))
		var frames: Array = case.get("frames", [])
		r.check(not frames.is_empty(), "%s: frames 不能为空" % case_id)
		if frames.is_empty():
			_mismatches += 1
		for entry in frames:
			if typeof(entry) != TYPE_ARRAY or entry.size() != 5:
				r.check(false, "%s: frames 的每一项必须是 [t_ms, rs_angle, rs_mag, [按键], facing]" % case_id)
				_mismatches += 1
				continue
			var t_ms := int(entry[0])
			if t_ms % 4 != 0:
				r.check(false, "%s: 帧时间 %d 必须是 4 的整数倍" % [case_id, t_ms])
				_mismatches += 1


func _check_case(r, data: Dictionary, case: Dictionary) -> void:
	var case_id := str(case.get("id", "<缺 id>"))
	var config_key := str(case.get("config", "shipped"))
	var config := _config_for(r, data, config_key)
	if config == null:
		return
	var skill := _find_skill(config, str(case.get("skill", "")))
	if skill == null:
		_fail(r, "%s: 配置里找不到动作 %s" % [case_id, str(case.get("skill", ""))])
		return
	var detector := DetectorFactory.build(skill)
	if detector == null:
		_fail(r, "%s: DetectorFactory.build(%s) 返回 null（kind=%s）"
			% [case_id, skill.name, str(skill.kind)])
		return

	var actual := _replay(detector, skill, case.get("frames", []))
	var expect: Dictionary = case.get("expect", {})
	_check_outcomes(r, case_id, actual, expect.get("outcomes", []))


func _find_skill(config: AppConfig, name: String) -> Skill:
	if config == null or name == "":
		return null
	for skill in config.skills:
		if skill.name == name:
			return skill
	return null


## 逐帧回放：修饰键满足才 update，否则 observe + reset（顺序不能反）；
## 每帧后 pop_failure。用例结束不 reset（会凭空多出一条 hold_short）。
func _replay(detector: Detector, skill: Skill, frames: Array) -> Array:
	var outcomes: Array = []
	for entry in frames:
		var frame := _make_frame(entry)
		if _buttons_ok(skill, frame.buttons):
			var hit := detector.update(frame)
			if hit != null:
				outcomes.append({
					"skill": skill.name,
					"ok": true,
					"code": "ok",
					"message": "",
					"elapsed_ms": hit.elapsed_ms,
					"at": frame.now,
					"detail": hit.summary,
				})
		else:
			detector.observe(frame)
			detector.reset()
		var failure := detector.pop_failure()
		if failure != null:
			outcomes.append({
				"skill": skill.name,
				"ok": false,
				"code": str(failure.code),
				"message": failure.message,
				"elapsed_ms": failure.elapsed_ms,
				"at": frame.now,
				"detail": "",
			})
	return outcomes


## 与参考引擎的 `_buttons_ok`（engine.py:446-452）逐行一致。
func _buttons_ok(skill: Skill, buttons: Dictionary) -> bool:
	if skill.required_buttons.is_empty():
		return true
	if skill.button_mode == Skill.MODE_ANY:
		for required_button in skill.required_buttons:
			if buttons.has(required_button):
				return true
		return false
	for required_button in skill.required_buttons:
		if not buttons.has(required_button):
			return false
	return true


func _make_frame(entry: Array) -> Frame:
	var frame := Frame.new()
	frame.now = float(entry[0]) / 1000.0
	frame.rs_angle = float(entry[1])
	frame.rs_mag = float(entry[2])
	for part in entry[3]:
		frame.buttons[str(part)] = true
	frame.facing = float(entry[4])
	return frame


func _check_outcomes(r, case_id: String, actual: Array, expected: Array) -> void:
	_eq_int(r, actual.size(), expected.size(), "%s: 判定条数" % case_id)
	for index in range(mini(actual.size(), expected.size())):
		var got: Dictionary = actual[index]
		var want: Dictionary = expected[index]
		var label := "%s: outcomes[%d]" % [case_id, index]
		_eq_str(r, str(got["skill"]), str(want.get("skill", "")), label + ".skill")
		_eq_bool(r, bool(got["ok"]), bool(want.get("ok", false)), label + ".ok")
		_eq_str(r, str(got["code"]), str(want.get("code", "")), label + ".code")
		_eq_str(r, str(got["message"]), str(want.get("message", "")), label + ".message")
		_eq_float(r, float(got["elapsed_ms"]), float(want.get("elapsed_ms", 0.0)), label + ".elapsed_ms")
		_eq_float(r, float(got["at"]), float(want.get("at", 0.0)), label + ".at")
		_eq_str(r, str(got["detail"]), str(want.get("detail", "")), label + ".detail")


func _fail(r, label: String) -> void:
	r.check(false, label)
	_mismatches += 1


func _eq_str(r, actual: String, expected: String, label: String) -> void:
	r.check(actual == expected, "%s（实际 %s，期望 %s）" % [label, actual, expected])
	if actual != expected:
		_mismatches += 1


func _eq_float(r, actual: float, expected: float, label: String) -> void:
	r.eq_float(actual, expected, TOL, label)
	if absf(actual - expected) > TOL:
		_mismatches += 1


func _eq_int(r, actual: int, expected: int, label: String) -> void:
	r.check(actual == expected, "%s（实际 %d，期望 %d）" % [label, actual, expected])
	if actual != expected:
		_mismatches += 1


func _eq_bool(r, actual: bool, expected: bool, label: String) -> void:
	r.check(actual == expected, "%s（实际 %s，期望 %s）" % [label, str(actual), str(expected)])
	if actual != expected:
		_mismatches += 1
