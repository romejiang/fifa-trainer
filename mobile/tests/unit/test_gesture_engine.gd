extends RefCounted

## 引擎层黄金回放：把 Python 参考引擎（`Engine._tick`）跑出的 29 条期望逐帧
## 喂给移动端 `GestureEngine`，逐字段比对 `outcomes` 与 `counters`。
##
## 为什么必须单独一套：检测器套件（`test_gesture_detector.gd`）证明的是「一个识别器
## 看一条轨迹」；手势锁、逐动作冷却、全局冷却、`_discard_other_claims`、
## held_required 互斥、失败归属与分组都只存在于引擎层，检测器套件永远看不到它们。
##
## 为什么每个用例都新建 `GestureEngine`：冷却、`_last_any_fire`、分组、手势锁全在
## 实例里；复用会让上一条的锁污染下一条。
##
## 为什么每帧全量 `pop_outcomes()`：这正是 UI 的用法（`practice_screen.gd` 每帧
## drain）。顺带证明「同帧多条结果不会被覆盖」。
##
## 为什么不读 `res://assets/config/`：每个用例的 `config` 键都能在夹具 `configs`
## 注册表里找到**完整**配置对象（含 `synthetic:*`）。读出厂副本会让合成用例按
## 出厂阈值静默回放，`mismatches=0` 就变成「与出厂副本一致」。
##
## 判据全部走 reporter 的 check / eq_float，不用 assert；最后一句必须是 r.complete()。
## 哨兵 `GESTURE_RUNTIME cases=N mismatches=0` 在 r.complete() **之前**打印。
##
## ## 变异验证（D-10，2026-11-06 实测）
##
## 语料「有牙齿」不是靠断言条数，而是靠「拆掉实现就红」证明。三次变异各自
## 还原后重跑全绿（`git diff --exit-code -- mobile/src/core` 为空）：
##
## | 变异 | 红色见证 |
## |------|----------|
## | 命中分支不置 `_gesture_locked` | `rt_lock_release_150_minus_4`（多出第 2 条）+ Phase 4 的 `rt_gesture_lock` / `rt_release_hold_rearm` |
## | 命中路径不调 `_discard_other_claims` | `rt_competition_stepover_wins`（多出磕球的迟到裁定） |
## | 三道前置把 `observe` 与 `reset` 对调 | `rt_croqueta_hold_short`（elapsed 196 vs 200）+ `rt_one_verdict_per_attempt` |
##
## 计划原本点名 `rt_lock_hold_no_recenter` 作变异 1 的见证；实测它保持全绿 ——
## 右摇杆一直推着时，ArcDetector 自己的 `armed=false` 已经挡住第二段弧，手势锁
## 不是唯一闸门。真正能区分「有锁 / 无锁」的是 `rt_lock_release_150_minus_4`：
## 摘掉锁后它在 744ms 推的第二段弧会被检测器接受（已重新武装），多出第 2 条判定。


const GOLDEN_PATH := "res://tests/fixtures/gesture_golden.json"
const TOL := 1e-6

## 逐条点名的 runtime 用例：少一条就红。删掉大半夹具时，逐用例循环会零次
## 「通过」，所以规模与 id 下限必须先于任何回放执行。
const REQUIRED_RUNTIME_IDS: Array[String] = [
	# 单动作端到端 10
	"rt_roulette_ok",
	"rt_roulette_too_fast",
	"rt_stepover_ok",
	"rt_stepover_wrong_start",
	"rt_heel_ok",
	"rt_heel_too_slow",
	"rt_croqueta_ok",
	"rt_croqueta_hold_short",
	"rt_green_ok",
	"rt_green_too_fast",
	# 双动作竞争 2
	"rt_competition_stepover_wins",
	"rt_competition_roulette_wins",
	# 手势锁 3
	"rt_lock_hold_no_recenter",
	"rt_lock_release_150_plus_4",
	"rt_lock_release_150_minus_4",
	# 逐动作冷却 3
	"rt_cooldown_stepover",
	"rt_cooldown_roulette",
	"rt_cooldown_green",
	# 全局冷却 2
	"rt_global_cooldown_synthetic",
	"rt_global_cooldown_shipped_unreachable",
	# idle 重置 2
	"rt_idle_reset_250",
	"rt_idle_hold_no_reset",
	# facing 2
	"rt_facing_centered_zero_verdict",
	"rt_facing_held_hit",
	# 修饰键互斥 2
	"rt_modifier_lb_abandons_arcs",
	"rt_modifier_lb_keeps_croqueta",
	# 失败归属 2
	"rt_failure_owner_config_order",
	"rt_failure_clears_others",
	# 分组 1
	"rt_group_ten_hits",
]

var _mismatches := 0


func run(r) -> void:
	var data := _load_fixture(r)
	if data.is_empty():
		r.complete()
		return
	var cases := _runtime_cases(data)
	_check_scale(r, cases)
	_check_frame_grid(r, cases)

	var configs := _build_configs(r, data, cases)
	if configs.is_empty():
		print("GESTURE_RUNTIME cases=%d mismatches=%d" % [cases.size(), _mismatches])
		r.complete()
		return
	_check_counter_contracts(r, cases)
	_check_focus_mode(r, cases, configs)
	for case in cases:
		_check_case(r, case, configs)
	print("GESTURE_RUNTIME cases=%d mismatches=%d" % [cases.size(), _mismatches])
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
	return data


func _runtime_cases(data: Dictionary) -> Array:
	var filtered: Array = []
	for case in data.get("cases", []):
		if typeof(case) == TYPE_DICTIONARY and str(case.get("kind", "")) == "runtime":
			filtered.append(case)
	return filtered


## 规模与 id 下限：删空夹具、丢掉点名用例、复制 id 都必须变红。
## 下限与 `test-core.sh` 的 grep 是**同一个数字**：两层不一致等于允许删语料仍绿。
func _check_scale(r, cases: Array) -> void:
	r.check(cases.size() >= 29, "runtime 用例至少 29 条（实际 %d）" % cases.size())
	if cases.size() < 29:
		_mismatches += 1
	var ids: Dictionary = {}
	for case in cases:
		ids[str(case.get("id", ""))] = true
	_eq_int(r, ids.size(), cases.size(), "每条用例都必须有唯一 id")
	for required_id in REQUIRED_RUNTIME_IDS:
		var present: bool = ids.has(required_id)
		r.check(present, "runtime 用例必须包含点名 id %s" % required_id)
		if not present:
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
				r.check(false,
					"%s: frames 的每一项必须是 [t_ms, rs_angle, rs_mag, [按键], facing]" % case_id)
				_mismatches += 1
				continue
			var t_ms := int(entry[0])
			if t_ms % 4 != 0:
				r.check(false, "%s: 帧时间 %d 必须是 4 的整数倍" % [case_id, t_ms])
				_mismatches += 1


## 每个用到的 config 键只解析一次：29 条用例共 5 份配置，重复解析只是白跑。
func _build_configs(r, data: Dictionary, cases: Array) -> Dictionary:
	var configs := {}
	var registry: Dictionary = data.get("configs", {})
	for case in cases:
		var key := str(case.get("config", "shipped"))
		if configs.has(key):
			continue
		if not registry.has(key):
			_fail(r, "%s: config 键 %s 不在 configs 注册表里" % [str(case.get("id", "")), key])
			continue
		var result := ConfigValidator.validate(registry[key], "<gesture_golden:%s>" % key)
		if not result.ok():
			_fail(r, "%s: configs[%s] 无法通过 ConfigValidator：%s"
				% [str(case.get("id", "")), key, result.to_text()])
			continue
		configs[key] = result.config
	return configs


## 三条「反向对照」的机械落点：合成全局冷却必须吞掉命中，出厂冷却必须吞不掉；
## 10 连击必须正好完成一组。它们比较的是**期望值**，防止生成器把三条写成同一种形状。
## 单练模式：非聚焦动作只 observe/abandon，不能产出判定。
##
## 用黄金夹具里的 `rt_green_ok` 轨迹做双向对照：聚焦绿色搓射必须仍有判定，
## 聚焦别的动作时同一条轨迹必须一条判定都没有 —— 后者防止「置灰只是 UI 效果」。
func _check_focus_mode(r, cases: Array, configs: Dictionary) -> void:
	var green_case := {}
	for case in cases:
		if str(case.get("id", "")) == "rt_green_ok":
			green_case = case
			break
	if green_case.is_empty():
		_fail(r, "缺少 rt_green_ok，无法验证单练模式")
		return
	var config_key := str(green_case.get("config", "shipped"))
	if not configs.has(config_key):
		return
	var config: AppConfig = configs[config_key]
	var green_name := ""
	var other_name := ""
	for active in GestureEngine.new(config, true).active_skills():
		if active.skill.kind == &"taps" and green_name.is_empty():
			green_name = active.skill.name
		elif active.skill.name != green_name and other_name.is_empty():
			other_name = active.skill.name
	r.check(not green_name.is_empty(), "出厂配置必须有一个 taps 动作供单练验证")
	if green_name.is_empty():
		return
	var focused := GestureEngine.new(config, true)
	focused.set_focused_skill(StringName(green_name))
	var focused_outcomes := _replay(focused, green_case)
	r.check(not focused_outcomes.is_empty(), "单练绿色搓射时同一轨迹必须仍有判定")
	for outcome in focused_outcomes:
		_eq_str(r, outcome.skill_name, green_name, "单练模式下 Outcome 只能来自聚焦动作")
	var other := GestureEngine.new(config, true)
	other.set_focused_skill(StringName(other_name))
	var other_outcomes := _replay(other, green_case)
	r.check(other_outcomes.is_empty(),
		"单练 %s 时绿色搓射轨迹不得产生判定（实际 %d 条）"
		% [other_name, other_outcomes.size()])
	if not other_outcomes.is_empty():
		_mismatches += 1


func _replay(engine: GestureEngine, case: Dictionary) -> Array[Outcome]:
	var collected: Array[Outcome] = []
	var ls_points: Array = case.get("ls", [[0, 0.0, 0.9]])
	for entry in case.get("frames", []):
		var t_ms := int(entry[0])
		engine.tick(_make_frame(entry, ls_points, t_ms))
		collected.append_array(engine.pop_outcomes())
	return collected


func _check_counter_contracts(r, cases: Array) -> void:
	for case in cases:
		var case_id := str(case.get("id", ""))
		var counters: Dictionary = case.get("expect", {}).get("counters", {})
		if case_id == "rt_global_cooldown_synthetic":
			r.check(int(counters.get("suppressed", 0)) >= 1,
				"rt_global_cooldown_synthetic: suppressed 必须 >= 1")
			if int(counters.get("suppressed", 0)) < 1:
				_mismatches += 1
		elif case_id == "rt_global_cooldown_shipped_unreachable":
			_eq_int(r, int(counters.get("suppressed", -1)), 0,
				"rt_global_cooldown_shipped_unreachable: 出厂 60ms 冷却不可吞命中")
		elif case_id == "rt_group_ten_hits":
			_eq_int(r, int(counters.get("group_hits", -1)), 0,
				"rt_group_ten_hits: 第 10 发必须把 group_hits 归零")
			_eq_int(r, int(counters.get("groups_done", 0)), 1,
				"rt_group_ten_hits: 10 发必须正好完成一组")


func _check_case(r, case: Dictionary, configs: Dictionary) -> void:
	var case_id := str(case.get("id", "<缺 id>"))
	var config_key := str(case.get("config", "shipped"))
	if not configs.has(config_key):
		return
	var config: AppConfig = configs[config_key]
	var engine := GestureEngine.new(config, true)
	var ls_points: Array = case.get("ls", [[0, 0.0, 0.9]])
	var actual: Array[Outcome] = []
	for entry in case.get("frames", []):
		var t_ms := int(entry[0])
		engine.tick(_make_frame(entry, ls_points, t_ms))
		# 每帧全量 drain 再累积：这正是 UI 的用法，也证明队列不会被覆盖。
		actual.append_array(engine.pop_outcomes())
	var expect: Dictionary = case.get("expect", {})
	_check_outcomes(r, case_id, actual, expect.get("outcomes", []))
	_check_counters(r, case_id, engine, expect.get("counters", {}))


func _check_outcomes(r, case_id: String, actual: Array[Outcome], expected: Array) -> void:
	_eq_int(r, actual.size(), expected.size(), "%s: Outcome 条数" % case_id)
	for index in range(mini(actual.size(), expected.size())):
		var outcome: Outcome = actual[index]
		var want: Dictionary = expected[index]
		var label := "%s: outcomes[%d]" % [case_id, index]
		_eq_str(r, outcome.skill_name, str(want.get("skill", "")), label + ".skill")
		_eq_bool(r, outcome.ok, bool(want.get("ok", false)), label + ".ok")
		_eq_str(r, str(outcome.code), str(want.get("code", "")), label + ".code")
		_eq_str(r, outcome.message, str(want.get("message", "")), label + ".message")
		_eq_float(r, outcome.elapsed_ms, float(want.get("elapsed_ms", 0.0)), label + ".elapsed_ms")
		_eq_float(r, outcome.at, float(want.get("at", 0.0)), label + ".at")
		_eq_str(r, outcome.detail, str(want.get("detail", "")), label + ".detail")
		_eq_int(r, outcome.seq, index + 1, label + ".seq 必须从 1 单调递增")


func _check_counters(r, case_id: String, engine: GestureEngine, expected: Dictionary) -> void:
	_eq_int(r, engine.hits, int(expected.get("hits", 0)), "%s: counters.hits" % case_id)
	_eq_int(r, engine.attempts, int(expected.get("attempts", 0)),
		"%s: counters.attempts" % case_id)
	_eq_int(r, engine.group_hits, int(expected.get("group_hits", 0)),
		"%s: counters.group_hits" % case_id)
	_eq_int(r, engine.groups_done, int(expected.get("groups_done", 0)),
		"%s: counters.groups_done" % case_id)
	_eq_int(r, engine.suppressed, int(expected.get("suppressed", 0)),
		"%s: counters.suppressed" % case_id)


func _make_frame(entry: Array, ls_points: Array, t_ms: int) -> Frame:
	var frame := Frame.new()
	frame.now = float(t_ms) / 1000.0
	frame.rs_angle = float(entry[1])
	frame.rs_mag = float(entry[2])
	for part in entry[3]:
		frame.buttons[str(part)] = true
	var ls := _ls_at(ls_points, t_ms)
	frame.ls_angle = ls.x
	frame.ls_mag = ls.y
	return frame


## 左摇杆变化点 → 该帧的 (angle, mag)；默认与生成器一致（0°、0.9）。
## 返回 Vector2 而不是小数组：x=角度、y=幅度，调用处不必再解包。
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
