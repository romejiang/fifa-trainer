extends RefCounted

## 抽稀矩阵回放（JUDGE-07）：把 120 / 90 / 60 Hz 三条抽稀时间轴逐帧喂给
## GDScript 检测器与 GestureEngine，只比对判定码序列 `(skill, ok, code)`。
##
## 为什么只比到 L2：抽稀后「触发帧」与「起手帧」都可能晚一个采样周期，
## `elapsed_ms` / `message` / `detail` / `measured` 必然与 250 Hz 不同；
## 产品语义只承诺判定码，文案嵌实测值，不能当跨采样率的契约（RESEARCH §C.3）。
##
## 为什么套件还要读 250 Hz 源夹具：生成器已经断言过「时间戳是源轨迹子集」，
## 但生成器坏了套件也会跟着绿。这里用源夹具的 id 与时间戳集合独立复核一遍，
## 抽稀夹具被手改 / 被网格化时，两道证明必须同时失效才可能假绿。
##
## 为什么配置只走 payload["configs"][case["config"]]：抽稀语料里既有
## `variant:` 也有 `synthetic:` 用例；回落 res://assets/config/ 的出厂副本
## 会让它们按出厂阈值静默回放，`mismatches=0` 变成「与出厂副本一致」。
##
## 为什么必须走 DetectorFactory.build(skill)：检测器按 skill.kind 分派；
## 硬编码 ArcDetector 会让序列 / 按键动作被弧线检测器回放，期望与实测一起跑偏。
## 返回 null 直接判该用例失败。
##
## 判据全部走 reporter 的 check / eq_float，不用 assert；最后一句必须是 r.complete()。
## 哨兵 `DECIMATION rates=3 cases=N mismatches=0` 在 r.complete() **之前**打印。

const GOLDEN_PATH := "res://tests/fixtures/golden_decimated.json"
const SOURCE_PATH := "res://tests/fixtures/gesture_golden.json"
const RULE := "nearest+keep_ts+force_button_edges"
const MIN_CASES := 240
const RATES := [60, 90, 120]

var _mismatches := 0


func run(r) -> void:
	var data := _load_fixture(r, GOLDEN_PATH, "抽稀夹具")
	var source := _load_fixture(r, SOURCE_PATH, "250 Hz 源夹具")
	if data.is_empty() or source.is_empty():
		print("DECIMATION rates=0 cases=0 mismatches=%d" % _mismatches)
		r.complete()
		return

	var cases: Array = data.get("cases", [])
	var source_cases: Array = source.get("cases", [])
	_check_scale(r, data, cases, source_cases)
	_check_source_subset(r, cases, source_cases)

	var configs := _build_configs(r, data, cases)
	if configs.is_empty():
		print("DECIMATION rates=%d cases=%d mismatches=%d"
			% [_rate_count(cases), cases.size(), _mismatches])
		r.complete()
		return

	for case in cases:
		_check_case(r, case, configs)
	print("DECIMATION rates=%d cases=%d mismatches=%d"
		% [_rate_count(cases), cases.size(), _mismatches])
	r.complete()


func _load_fixture(r, path: String, label: String) -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		_fail(r, "读不到%s：%s（运行 python3 tools/decimate_trace.py 生成）" % [label, path])
		return {}
	var json := JSON.new()
	if json.parse(bytes.get_string_from_utf8()) != OK:
		_fail(r, "%s不是合法 JSON（第 %d 行：%s）"
			% [label, json.get_error_line() + 1, json.get_error_message()])
		return {}
	if typeof(json.data) != TYPE_DICTIONARY:
		_fail(r, "%s的根节点必须是对象" % label)
		return {}
	return json.data


## 规模：抽稀条数必须恰好是源用例数的三倍，且不低于 240；三档速率一个都不能少。
## 下限与 `test-core.sh` 的 grep 是**同一个数字**：两层不一致等于允许删语料仍绿。
func _check_scale(r, data: Dictionary, cases: Array, source_cases: Array) -> void:
	r.check(cases.size() >= MIN_CASES,
		"抽稀用例至少 %d 条（实际 %d）" % [MIN_CASES, cases.size()])
	if cases.size() < MIN_CASES:
		_mismatches += 1
	_eq_int(r, cases.size(), 3 * source_cases.size(),
		"抽稀条数必须恰好是 3 × 源用例数")

	var rates: Dictionary = {}
	for case in cases:
		rates[int(case.get("rate_hz", 0))] = true
	_eq_int(r, rates.size(), 3, "rate_hz 必须恰好出现 3 档")
	for rate in RATES:
		var present: bool = rates.has(rate)
		r.check(present, "rate_hz 必须包含 %d" % rate)
		if not present:
			_mismatches += 1

	var meta: Dictionary = data.get("meta", {})
	_eq_int(r, int(meta.get("hz", 0)), 250, "meta.hz 必须是 250")
	_eq_int(r, int(meta.get("step_ms", 0)), 4, "meta.step_ms 必须是 4")

	var ids: Dictionary = {}
	for case in cases:
		ids[str(case.get("id", ""))] = true
	_eq_int(r, ids.size(), cases.size(), "每条抽稀用例都必须有唯一 id")


## 独立复核：每个抽稀时间戳都能在**同 source_id 的 250 Hz 源轨迹**里原样找到，
## 且严格递增。这条断言不依赖生成器自己的断言 2。
func _check_source_subset(r, cases: Array, source_cases: Array) -> void:
	var source_times: Dictionary = {}
	for case in source_cases:
		var times: Dictionary = {}
		for entry in case.get("frames", []):
			times[int(entry[0])] = true
		source_times[str(case.get("id", ""))] = times

	for case in cases:
		var case_id := str(case.get("id", "<缺 id>"))
		var source_id := str(case.get("source_id", ""))
		r.check(not source_id.is_empty(), "%s: 必须带 source_id" % case_id)
		r.check(str(case.get("rule", "")) == RULE,
			"%s: rule 必须是 %s" % [case_id, RULE])
		r.check(case.has("vs_250"), "%s: 必须带 vs_250" % case_id)
		if not source_times.has(source_id):
			_fail(r, "%s: source_id %s 不在 250 Hz 源夹具里" % [case_id, source_id])
			continue
		var times: Dictionary = source_times[source_id]
		var frames: Array = case.get("frames", [])
		r.check(not frames.is_empty(), "%s: frames 不能为空" % case_id)
		if frames.is_empty():
			_mismatches += 1
		var previous := -1
		for entry in frames:
			var t_ms := int(entry[0])
			var in_source: bool = times.has(t_ms)
			r.check(in_source,
				"%s: 时间戳 %d 不在源轨迹里（抽稀只许抽样本，不许网格化）"
				% [case_id, t_ms])
			if not in_source:
				_mismatches += 1
			var increasing := t_ms > previous
			r.check(increasing, "%s: 时间戳必须严格递增（%d 之后出现 %d）"
				% [case_id, previous, t_ms])
			if not increasing:
				_mismatches += 1
			previous = t_ms

		var vs: Dictionary = case.get("vs_250", {})
		var drift: Array = vs.get("drift", [])
		r.check(bool(vs.get("codes_equal", false)) == drift.is_empty(),
			"%s: vs_250.codes_equal 必须与 drift 是否为空一致" % case_id)
		if bool(vs.get("codes_equal", false)) != drift.is_empty():
			_mismatches += 1


## 每个用到的 config 键只解析一次：252 条用例共用少数几份完整配置。
func _build_configs(r, data: Dictionary, cases: Array) -> Dictionary:
	var configs := {}
	var registry: Dictionary = data.get("configs", {})
	for case in cases:
		var key := str(case.get("config", "shipped"))
		if configs.has(key):
			continue
		if not registry.has(key):
			_fail(r, "%s: config 键 %s 不在 configs 注册表里"
				% [str(case.get("id", "")), key])
			continue
		var result := ConfigValidator.validate(registry[key], "<golden_decimated:%s>" % key)
		if not result.ok():
			_fail(r, "%s: configs[%s] 无法通过 ConfigValidator：%s"
				% [str(case.get("id", "")), key, result.to_text()])
			continue
		configs[key] = result.config
	return configs


func _check_case(r, case: Dictionary, configs: Dictionary) -> void:
	var case_id := str(case.get("id", "<缺 id>"))
	var config_key := str(case.get("config", "shipped"))
	if not configs.has(config_key):
		return
	var config: AppConfig = configs[config_key]
	var skill := _find_skill(config, str(case.get("skill", "")))
	if skill == null:
		_fail(r, "%s: 配置里找不到动作 %s" % [case_id, str(case.get("skill", ""))])
		return

	var expected: Array = case.get("expect", {}).get("outcomes", [])
	var kind := str(case.get("kind", ""))
	var actual: Array = []
	if kind == "detector":
		actual = _replay_detector(r, case_id, skill, case.get("frames", []))
	elif kind == "runtime":
		actual = _replay_engine(config, case)
	else:
		_fail(r, "%s: 未知的用例类型 %s" % [case_id, kind])
		return
	_check_codes(r, case_id, actual, expected)


## 检测器回放：与 test_gesture_detector.gd 同一套规则 —— 修饰键满足才 update，
## 否则先 observe 再 reset（顺序不能反）；每帧后 pop_failure。
func _replay_detector(r, case_id: String, skill: Skill, frames: Array) -> Array:
	var detector := DetectorFactory.build(skill)
	if detector == null:
		_fail(r, "%s: DetectorFactory.build(%s) 返回 null（kind=%s）"
			% [case_id, skill.name, str(skill.kind)])
		return []
	var actual: Array = []
	for entry in frames:
		var frame := _make_frame(entry)
		if _buttons_ok(skill, frame.buttons):
			var hit := detector.update(frame)
			if hit != null:
				actual.append({"skill": skill.name, "ok": true, "code": "ok"})
		else:
			detector.observe(frame)
			detector.reset()
		var failure := detector.pop_failure()
		if failure != null:
			actual.append({
				"skill": skill.name,
				"ok": false,
				"code": str(failure.code),
			})
	return actual


## 引擎回放：每帧全量 pop_outcomes()，这正是 UI 的用法，也证明队列不会被覆盖。
func _replay_engine(config: AppConfig, case: Dictionary) -> Array:
	var engine := GestureEngine.new(config, true)
	var ls_points: Array = case.get("ls", [[0, 0.0, 0.9]])
	var actual: Array = []
	for entry in case.get("frames", []):
		engine.tick(_make_engine_frame(entry, ls_points))
		for outcome in engine.pop_outcomes():
			actual.append({
				"skill": outcome.skill_name,
				"ok": outcome.ok,
				"code": str(outcome.code),
			})
	return actual


## L2 口径：只比 (skill, ok, code)。message / detail / measured / elapsed_ms
## 一概不比较 —— 文案与实测值必然随采样率变化，不是产品契约。
func _check_codes(r, case_id: String, actual: Array, expected: Array) -> void:
	_eq_int(r, actual.size(), expected.size(), "%s: 判定条数" % case_id)
	for index in range(mini(actual.size(), expected.size())):
		var got: Dictionary = actual[index]
		var want: Dictionary = expected[index]
		var label := "%s: outcomes[%d]" % [case_id, index]
		_eq_str(r, str(got["skill"]), str(want.get("skill", "")), label + ".skill")
		_eq_bool(r, bool(got["ok"]), bool(want.get("ok", false)), label + ".ok")
		_eq_str(r, str(got["code"]), str(want.get("code", "")), label + ".code")


func _find_skill(config: AppConfig, name: String) -> Skill:
	if config == null or name == "":
		return null
	for skill in config.skills:
		if skill.name == name:
			return skill
	return null


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


func _make_engine_frame(entry: Array, ls_points: Array) -> Frame:
	var frame := Frame.new()
	frame.now = float(entry[0]) / 1000.0
	frame.rs_angle = float(entry[1])
	frame.rs_mag = float(entry[2])
	for part in entry[3]:
		frame.buttons[str(part)] = true
	var ls := _ls_at(ls_points, int(entry[0]))
	frame.ls_angle = ls.x
	frame.ls_mag = ls.y
	return frame


## 左摇杆变化点 → 该帧的 (angle, mag)；默认与生成器一致（0°、0.9）。
func _ls_at(points: Array, t_ms: int) -> Vector2:
	var angle := 0.0
	var mag := 0.9
	for point in points:
		if typeof(point) != TYPE_ARRAY or point.size() < 3:
			continue
		if int(point[0]) <= t_ms:
			angle = float(point[1])
			mag = float(point[2])
		else:
			break
	return Vector2(angle, mag)


func _rate_count(cases: Array) -> int:
	var rates: Dictionary = {}
	for case in cases:
		rates[int(case.get("rate_hz", 0))] = true
	return rates.size()


func _fail(r, label: String) -> void:
	r.check(false, label)
	_mismatches += 1


func _eq_str(r, actual: String, expected: String, label: String) -> void:
	r.check(actual == expected, "%s（实际 %s，期望 %s）" % [label, actual, expected])
	if actual != expected:
		_mismatches += 1


func _eq_int(r, actual: int, expected: int, label: String) -> void:
	r.check(actual == expected, "%s（实际 %d，期望 %d）" % [label, actual, expected])
	if actual != expected:
		_mismatches += 1


func _eq_bool(r, actual: bool, expected: bool, label: String) -> void:
	r.check(actual == expected, "%s（实际 %s，期望 %s）" % [label, str(actual), str(expected)])
	if actual != expected:
		_mismatches += 1
