extends RefCounted

## 结构化度量（JUDGE-05）的独立证明：12 条断言组，**不读任何黄金夹具**。
##
## 为什么必须有这一套：桌面参考**不产出** `measured`，所以它没有跨语言 oracle，
## 不可能进 250 Hz 语料的逐字比较。没有这套断言，`measured` 就是「有字段、没人验」
## 的装饰 —— 改坏它，所有黄金回放仍然全绿。
##
## 做法：用已知参数的合成轨迹直接驱动检测器 / 单技能运行时，断言
##   1. 弧线：扫掠角、起点、活动帧数、目标窗口、实际转向；
##   2. 弧线失败：`fail.distance_deg` 与 `message` 里的 `end_rel` **同源**
##      （`distance == abs(end_rel - nearest)`）、`too_short` / `too_fast` 自洽；
##   3. 序列：每一步的完成时刻严格递增、保持时长与设定值差 < 1 帧、`hold_short`；
##   4. tap：两下间隔 448 成功 / 396 太快，且 `Outcome.measured` 非空 ——
##      这一段同时证明「检测器 → Failure/Hit → 引擎 `_record` → Outcome」的透传。
##
## 第 6 组是**唯一允许解析 `message` 的地方**：它证明「文案里的数字与结构化字段是同
## 一次计算」。UI 与日志不得照做（RESEARCH §D.5 / T-05-12）。
##
## 哨兵 `MEASURED cases=%d mismatches=%d` 在 `r.complete()` **之前**打印；
## `_cases` 就是实际执行并比较的断言组数，`test-core.sh` 的 grep 下限与它同数（12）。

const CONFIG_PATH := "res://assets/config/skills_config.json"

## 一帧的宽度（毫秒）：与参考实现的 250 Hz 标称采样一致。
const FRAME_MS := 4

var _cases := 0
var _mismatches := 0
var _group_failed := false


func run(r) -> void:
	var result := _load_config(r)
	if result == null:
		print("MEASURED cases=%d mismatches=%d" % [_cases, _mismatches])
		r.complete()
		return
	var config: AppConfig = result.config
	var roulette := _find_skill(config, "马赛回旋")
	var heel := _find_skill(config, "磕球过人")
	var croqueta := _find_skill(config, "油炸丸子")
	var green := _find_skill(config, "绿色搓射")
	if not _require_skills(r, [roulette, heel, croqueta, green]):
		print("MEASURED cases=%d mismatches=%d" % [_cases, _mismatches])
		r.complete()
		return

	var arc_success := _arc_success_measured()
	_group_arc_swept(r, arc_success)
	_group_arc_start(r, arc_success)
	_group_arc_samples(r, arc_success)
	_group_arc_target(r, arc_success)
	_group_arc_direction(r, arc_success)

	_group_arc_wrong_end(r)
	_group_arc_too_short(r, roulette)
	_group_arc_too_fast(r, roulette)

	_group_sequence_two_steps(r, heel)
	_group_sequence_hold(r, croqueta)
	_group_sequence_hold_short(r, croqueta)

	_group_tap(r, green, config)

	print("MEASURED cases=%d mismatches=%d" % [_cases, _mismatches])
	r.complete()


# ---------------------------------------------------------------------------
# 12 条断言组
# ---------------------------------------------------------------------------


## 组 1：匀速 200° 的弧，`swept_deg` 与设定值差 < 0.05°。
##
## 容差取得比「1°」更紧是有意的：变异验证把构造改成 `swept * 0.999` 时，
## 200° 只差 0.2° —— 1° 的容差会放过它，闸门就没有牙齿（D-10）。
##
## 为什么用合成弧而不是 shipped 马赛回旋：出厂终点窗是 0°±80°（160° 宽），
## 从 180° 顺时针扫时，第一次「同时满足 min 250ms + 区间 + 终点窗」在
## swept≈100.8° —— 200° 成功在出厂阈值下不可达。合成弧把终点窗收窄到 20°±0.5°，
## 让 200° 成为真正的成功点；判定代码与文案都没有任何分叉。
func _group_arc_swept(r, m: Dictionary) -> void:
	_begin()
	if _require_measured(r, m, "arc_success"):
		_eq_float(r, _number(m.get("swept_deg")), 200.0, 0.05, "arc_success: swept_deg")
	_end()


## 组 2：起点相对角就是轨迹的起点（shipped 马赛回旋从 180° 起手）。
func _group_arc_start(r, m: Dictionary) -> void:
	_begin()
	if _require_measured(r, m, "arc_success"):
		_eq_float(r, _number(m.get("start_rel_deg")), 180.0, 1.0,
			"arc_success: start_rel_deg")
	_end()


## 组 3：`samples` == **活动帧数**，不是驱动的总帧数。
##
## ArcDetector 在起手那一帧就把 `samples` 置 1（detectors.py:293），之后每活动帧 +1。
## 这条轨迹从 t=4ms 推起、到 t=504ms 命中，共 126 个活动帧；t=0 那一帧是「回中」
## 起手前的准备帧，不算 —— 断言 126 而不是 127。
func _group_arc_samples(r, m: Dictionary) -> void:
	_begin()
	if _require_measured(r, m, "arc_success"):
		var samples: Variant = m.get("samples")
		_check(r, samples != null, "arc_success: samples 不能为 null")
		if samples != null:
			_eq_int(r, int(samples), 126, "arc_success: samples 必须是活动帧数（起手帧计 1）")
	_end()


## 组 4：目标窗口来自配置，不是常量。
func _group_arc_target(r, m: Dictionary) -> void:
	_begin()
	if _require_measured(r, m, "arc_success"):
		var target: Dictionary = m.get("target", {})
		_eq_float(r, _number(target.get("min_ms")), 250.0, 1e-6, "arc_success: target.min_ms")
		_eq_float(r, _number(target.get("max_ms")), 600.0, 1e-6, "arc_success: target.max_ms")
		_eq_float(r, _number(target.get("min_angle")), 70.0, 1e-6,
			"arc_success: target.min_angle")
	_end()


## 组 5：实际转向。shipped 配置是 `direction: any`，但 measured 仍然必须记下
## 真实转向（顺时针 = 1）—— 否则 Phase 7 拿到的永远是 0。
func _group_arc_direction(r, m: Dictionary) -> void:
	_begin()
	if _require_measured(r, m, "arc_success"):
		var sign_value: Variant = m.get("direction_sign")
		_check(r, sign_value != null, "arc_success: direction_sign 不能为 null")
		if sign_value != null:
			_eq_int(r, int(sign_value), 1, "arc_success: direction_sign 必须是 1（顺时针）")
	_end()


## 组 6：`wrong_end` 的**同源**证明。
##
## 断言 `distance_deg == abs(end_rel_deg - nearest_target_deg)`，并且 `message` 里
## 第一个整数就是 `end_rel_deg` 的四舍五入。注意 `message` 里**没有** `distance_deg`
## （detectors.py:232-235 只报「停在相对 N°」与目标区间），所以不能拿距离去比文案。
## 这是全仓唯一允许解析 `message` 的地方；UI 不得照做。
func _group_arc_wrong_end(r) -> void:
	_begin()
	# 顺时针 230°：180° → 360° → 50°，全程不经过终点窗 70°~110°。
	var changes := _sweep_changes(4, 180.0, 230.0, 460)
	changes.append([468, 0.1, 50.0])
	var run := _run_detector(ArcDetector.new(_synthetic_arc_skill()), changes, 476)
	var failures: Array = run.get("failures", [])
	_eq_int(r, failures.size(), 1, "arc_wrong_end: 必须产生 1 条 Failure")
	if failures.size() == 1:
		var failure: Failure = failures[0]
		_eq_str(r, str(failure.code), "wrong_end", "arc_wrong_end: code")
		var m: Dictionary = failure.measured
		if _require_measured(r, m, "arc_wrong_end"):
			var fail: Dictionary = m.get("fail", {})
			var end_rel := _number(m.get("end_rel_deg"))
			var nearest := _number(fail.get("nearest_target_deg"))
			var distance := _number(fail.get("distance_deg"))
			_eq_float(r, end_rel, 50.0, 1.0, "arc_wrong_end: end_rel_deg")
			_eq_float(r, nearest, 90.0, 1e-6, "arc_wrong_end: nearest_target_deg")
			_eq_float(r, distance, absf(end_rel - nearest), 1e-6,
				"arc_wrong_end: distance_deg 必须等于 abs(end_rel - nearest)")
			var from_message := _first_integer(failure.message)
			_check(r, not is_nan(from_message), "arc_wrong_end: message 里必须有一个整数")
			if not is_nan(from_message):
				_eq_float(r, from_message, roundf(end_rel), 1e-6,
					"arc_wrong_end: message 的第一个整数必须就是 end_rel_deg")
	_end()


## 组 7：转得不够。`fail` 里没有真实目标可报：`distance` / `nearest` / `tolerance`
## 必须是 null，而不是硬造的 0。
func _group_arc_too_short(r, roulette: Skill) -> void:
	_begin()
	var changes := _sweep_changes(4, 180.0, 40.0, 100)
	changes.append([108, 0.1, 220.0])
	var run := _run_detector(ArcDetector.new(roulette), changes, 116)
	var failures: Array = run.get("failures", [])
	_eq_int(r, failures.size(), 1, "arc_too_short: 必须产生 1 条 Failure")
	if failures.size() == 1:
		var failure: Failure = failures[0]
		_eq_str(r, str(failure.code), "too_short", "arc_too_short: code")
		var m: Dictionary = failure.measured
		if _require_measured(r, m, "arc_too_short"):
			var fail: Dictionary = m.get("fail", {})
			var swept := _number(m.get("swept_deg"))
			var min_angle := _number((m.get("target", {}) as Dictionary).get("min_angle"))
			_check(r, swept < min_angle, "arc_too_short: swept_deg 必须小于 min_angle")
			_check(r, fail.get("distance_deg") == null, "arc_too_short: distance_deg 必须是 null")
			_check(r, fail.get("nearest_target_deg") == null,
				"arc_too_short: nearest_target_deg 必须是 null")
	_end()


## 组 8：太快。`target.min_ms` / `max_ms` 与 `elapsed_ms` 必须与 `code` 自洽：
## 报 `too_fast` 时耗时一定小于 `min_ms`，且上限仍是配置值。
func _group_arc_too_fast(r, roulette: Skill) -> void:
	_begin()
	var changes := _sweep_changes(4, 180.0, 120.0, 100)
	changes.append([108, 0.1, 300.0])
	var run := _run_detector(ArcDetector.new(roulette), changes, 116)
	var failures: Array = run.get("failures", [])
	_eq_int(r, failures.size(), 1, "arc_too_fast: 必须产生 1 条 Failure")
	if failures.size() == 1:
		var failure: Failure = failures[0]
		_eq_str(r, str(failure.code), "too_fast", "arc_too_fast: code")
		var m: Dictionary = failure.measured
		if _require_measured(r, m, "arc_too_fast"):
			var target: Dictionary = m.get("target", {})
			var elapsed := _number(m.get("elapsed_ms"))
			_eq_float(r, _number(target.get("min_ms")), 250.0, 1e-6, "arc_too_fast: target.min_ms")
			_eq_float(r, _number(target.get("max_ms")), 600.0, 1e-6, "arc_too_fast: target.max_ms")
			_check(r, elapsed < _number(target.get("min_ms")),
				"arc_too_fast: elapsed_ms 必须小于 target.min_ms")
			_check(r, elapsed <= _number(target.get("max_ms")),
				"arc_too_fast: elapsed_ms 不能超过 target.max_ms")
	_end()


## 组 9：磕球两步的完成时刻严格递增。
##
## 第 1 步在 t=4ms 完成（起手帧就匹配「前」），第 2 步在 t=256ms 完成（「后」）。
## `t_done_ms` 必须来自 `_step_t` 的现场记录 —— 用总耗时「平均分摊」会得到两个
## 相同的数，这条断言就会红。删掉 `_step_t[index - 1] = ...` 时本组也必红（D-10）。
func _group_sequence_two_steps(r, heel: Skill) -> void:
	_begin()
	var run := _run_detector(SequenceDetector.new(heel), _heel_changes(), 264)
	var hits: Array = run.get("hits", [])
	_eq_int(r, hits.size(), 1, "sequence_two_steps: 必须产生 1 条 Hit")
	if hits.size() == 1:
		var m: Dictionary = hits[0].measured
		if _require_measured(r, m, "sequence_two_steps"):
			_eq_str(r, str(m.get("kind")), "sequence", "sequence_two_steps: kind")
			var steps: Array = m.get("steps", [])
			_eq_int(r, steps.size(), 2, "sequence_two_steps: 必须有两步")
			if steps.size() == 2:
				var first: Dictionary = steps[0]
				var second: Dictionary = steps[1]
				_eq_str(r, str(first.get("label")), "前", "sequence_two_steps: steps[0].label")
				_eq_str(r, str(second.get("label")), "后", "sequence_two_steps: steps[1].label")
				var t_first: Variant = first.get("t_done_ms")
				var t_second: Variant = second.get("t_done_ms")
				_check(r, t_first != null, "sequence_two_steps: steps[0].t_done_ms 不能为 null")
				_check(r, t_second != null, "sequence_two_steps: steps[1].t_done_ms 不能为 null")
				if t_first != null and t_second != null:
					_check(r, float(t_second) > float(t_first),
						"sequence_two_steps: steps[1].t_done_ms 必须严格大于 steps[0]")
					_eq_float(r, float(t_first), 4.0, 4.0,
						"sequence_two_steps: steps[0].t_done_ms")
					_eq_float(r, float(t_second), 256.0, 4.0,
						"sequence_two_steps: steps[1].t_done_ms")
				_eq_float(r, _number(m.get("elapsed_ms")), 252.0, 4.0,
					"sequence_two_steps: elapsed_ms")
	_end()


## 组 10：油炸丸子按住 350ms 的成功路径：`actual_hold_ms` 与设定值差 < 1 帧。
func _group_sequence_hold(r, croqueta: Skill) -> void:
	_begin()
	var changes: Array = [[0, 0.1, 0.0], [4, 0.9, 90.0]]
	var run := _run_detector(SequenceDetector.new(croqueta), changes, 400)
	var hits: Array = run.get("hits", [])
	_eq_int(r, hits.size(), 1, "sequence_hold: 必须产生 1 条 Hit")
	if hits.size() == 1:
		var m: Dictionary = hits[0].measured
		if _require_measured(r, m, "sequence_hold"):
			var steps: Array = m.get("steps", [])
			_eq_int(r, steps.size(), 1, "sequence_hold: 必须只有一步")
			if steps.size() == 1:
				var step: Dictionary = steps[0]
				_eq_float(r, _number(step.get("required_hold_ms")), 350.0, 1e-6,
					"sequence_hold: required_hold_ms")
				var actual: Variant = step.get("actual_hold_ms")
				_check(r, actual != null, "sequence_hold: actual_hold_ms 不能为 null")
				if actual != null:
					_check(r, absf(float(actual) - 350.0) < 4.0,
						"sequence_hold: actual_hold_ms 与设定 350ms 差必须 < 1 帧（实际 %s）"
							% str(actual))
				var done: Variant = step.get("t_done_ms")
				_check(r, done != null, "sequence_hold: t_done_ms 不能为 null")
				if done != null:
					_eq_float(r, float(done), 356.0, 4.0, "sequence_hold: t_done_ms")
	_end()


## 组 11：油炸丸子只按住约 200ms 就松手 —— 引擎静置后给 `hold_short`，
## 且 measured 里的实际保持时长就是那 200ms。
func _group_sequence_hold_short(r, croqueta: Skill) -> void:
	_begin()
	var changes: Array = [
		[0, 0.1, 0.0],
		[4, 0.9, 90.0],
		[208, 0.1, 90.0],
		[212, 0.1, 90.0],
	]
	var detector := SequenceDetector.new(croqueta)
	_run_detector(detector, changes, 216)
	# 引擎在右摇杆静置满 idle_reset_ms 时调 on_idle()（engine.py:303-314）。
	detector.on_idle()
	var failure := detector.pop_failure()
	_check(r, failure != null, "sequence_hold_short: on_idle 必须产出 hold_short")
	if failure != null:
		_eq_str(r, str(failure.code), "hold_short", "sequence_hold_short: code")
		var m: Dictionary = failure.measured
		if _require_measured(r, m, "sequence_hold_short"):
			var steps: Array = m.get("steps", [])
			_eq_int(r, steps.size(), 1, "sequence_hold_short: 必须只有一步")
			if steps.size() == 1:
				var step: Dictionary = steps[0]
				_eq_float(r, _number(step.get("required_hold_ms")), 350.0, 1e-6,
					"sequence_hold_short: required_hold_ms")
				var actual: Variant = step.get("actual_hold_ms")
				_check(r, actual != null, "sequence_hold_short: actual_hold_ms 不能为 null")
				if actual != null:
					_eq_float(r, float(actual), 200.0, 4.0,
						"sequence_hold_short: actual_hold_ms")
				_check(r, step.get("t_done_ms") == null,
					"sequence_hold_short: 没完成的步骤 t_done_ms 必须是 null")
	_end()


## 组 12：tap 的两下间隔，**经 `TapRuntime` 走完整透传链**（检测器 → Failure/Hit →
## 引擎 `_record` → `Outcome.measured`）。448ms 成功、396ms 太快。
func _group_tap(r, green: Skill, config: AppConfig) -> void:
	_begin()
	var success_changes: Array = [
		[0, ""],
		[4, "RB"],
		[100, "RB+X"],
		[104, "RB"],
		[548, "RB+X"],
		[552, "RB"],
	]
	var success_runtime := TapRuntime.new(green, config.global_cooldown_ms,
		config.input.gesture_release_ms, true)
	var success := _run_tap(success_runtime, success_changes, 560)
	_eq_int(r, success.size(), 1, "tap_success: 必须产生 1 条 Outcome")
	if success.size() == 1:
		var outcome: Outcome = success[0]
		_check(r, outcome.ok, "tap_success: ok 必须为 true")
		var m: Dictionary = outcome.measured
		if _require_measured(r, m, "tap_success"):
			_eq_str(r, str(m.get("kind")), "taps", "tap_success: kind")
			_eq_float(r, _number(m.get("interval_ms")), 448.0, 1e-6, "tap_success: interval_ms")
			var window: Dictionary = m.get("window", {})
			_eq_float(r, _number(window.get("min_ms")), 400.0, 1e-6, "tap_success: window.min_ms")
			_eq_float(r, _number(window.get("max_ms")), 600.0, 1e-6, "tap_success: window.max_ms")
			_eq_str(r, str(m.get("button")), "X", "tap_success: button")
			_eq_str(r, str(m.get("modifier")), "RB", "tap_success: modifier")

	var too_fast_changes: Array = [
		[0, ""],
		[4, "RB"],
		[100, "RB+X"],
		[104, "RB"],
		[496, "RB+X"],
		[500, "RB"],
	]
	var too_fast_runtime := TapRuntime.new(green, config.global_cooldown_ms,
		config.input.gesture_release_ms, true)
	var too_fast := _run_tap(too_fast_runtime, too_fast_changes, 508)
	_eq_int(r, too_fast.size(), 1, "tap_too_fast: 必须产生 1 条 Outcome")
	if too_fast.size() == 1:
		var outcome: Outcome = too_fast[0]
		_check(r, not outcome.ok, "tap_too_fast: ok 必须为 false")
		_eq_str(r, str(outcome.code), "too_fast", "tap_too_fast: code")
		var m: Dictionary = outcome.measured
		if _require_measured(r, m, "tap_too_fast"):
			_eq_float(r, _number(m.get("interval_ms")), 396.0, 1e-6,
				"tap_too_fast: interval_ms")
	_end()


# ---------------------------------------------------------------------------
# 轨迹
# ---------------------------------------------------------------------------


## 成功弧的已知轨迹：180° 起手，匀速顺时针 200°，500ms 命中；t=508 回中收尾。
## 五组断言共用这一次回放的结果，避免同一轨迹重复驱动五次。
func _arc_success_measured() -> Dictionary:
	var changes := _sweep_changes(4, 180.0, 200.0, 500)
	changes.append([508, 0.1, 380.0])
	var run := _run_detector(ArcDetector.new(_synthetic_success_arc_skill()), changes, 512)
	var hits: Array = run.get("hits", [])
	if hits.size() != 1:
		return {}
	return (hits[0] as Hit).measured


## 匀速扫掠的逐帧轨迹：起手帧 + 每 4ms 一帧的等角度增量。
## 返回「变化点」数组 `[t_ms, rs_mag, rs_angle]`，由 `_run_detector()` 展开成逐帧。
func _sweep_changes(start_ms: int, start_angle: float, sweep_deg: float,
		duration_ms: int) -> Array:
	var changes: Array = [[0, 0.1, 0.0]]
	var frames := int(round(float(duration_ms) / float(FRAME_MS)))
	var per_frame := sweep_deg / float(frames)
	changes.append([start_ms, 0.9, start_angle])
	for k in range(1, frames + 1):
		changes.append([start_ms + FRAME_MS * k, 0.9, start_angle + per_frame * float(k)])
	return changes


## 磕球：t=4 起手匹配「前」（第 1 步完成）；t=12 回中（`require_neutral_between_steps`
## 要求两步之间真的松手）；t=256 推到「后」—— elapsed=252ms ≥ min 250ms。
##
## 不能更晚推「后」：松手期间不满足「在动」，`_last_motion` 停在 t=12，
## t≥264ms 会先触发 250ms 的 stalled（报 `incomplete`）。
## 也不能更早推「后」：elapsed < 250ms 会先触发 `too_fast`。
func _heel_changes() -> Array:
	return [
		[0, 0.1, 0.0],
		[4, 0.9, 0.0],
		[12, 0.1, 0.0],
		[256, 0.9, 180.0],
	]


## 合成的成功弧：起点 180°、终点 20°±0.5°、扫掠 70°~230°、时长 250~600ms。
## 窄终点窗让 200° 成为真正的成功点（出厂 0°±80° 会在 100.8° 就命中）。
func _synthetic_success_arc_skill() -> Skill:
	return _arc_skill(20.0, 0.5, 70.0, 230.0, 250.0, 600.0)


## 合成的终点测试弧：起点 180°、唯一终点 90°±20°、扫掠上限放到 240°。
## 从 180° 顺时针扫 230° 到 50°：全程不经过 70°~110° 的终点窗，所以只会在松手时
## 报 `wrong_end`；同时 `nearest_target=90` 让「漏掉 `- nearest_target`」的变异变红
## （`abs(end_rel)=50` 与 `distance=40` 不相等）。
func _synthetic_arc_skill() -> Skill:
	return _arc_skill(90.0, 20.0, 40.0, 240.0, 100.0, 1000.0)


func _arc_skill(end_angle: float, end_tolerance: float, min_angle: float,
		max_angle: float, min_ms: float, max_ms: float) -> Skill:
	var skill := Skill.new()
	skill.name = "合成的弧"
	skill.kind = Skill.KIND_ARC
	skill.params = {
		"start_angle": 180,
		"start_tolerance": 65,
		"end_angle": end_angle,
		"end_tolerance": end_tolerance,
		"enter_threshold": 0.8,
		"exit_threshold": 0.6,
		"min_angle": min_angle,
		"max_angle": max_angle,
		"min_duration_ms": min_ms,
		"max_duration_ms": max_ms,
		"idle_timeout_ms": 500,
		"release_hold_ms": 120,
		"direction": "any",
	}
	return skill


# ---------------------------------------------------------------------------
# 驱动与断言工具
# ---------------------------------------------------------------------------


## 逐帧 4ms 推进一个检测器：每帧喂完立刻取走 Hit / Failure。
## 与 250 Hz 黄金语料同一时间分辨率；稀疏帧会让计时器永远等不到阈值。
func _run_detector(detector: Detector, changes: Array, end_ms: int) -> Dictionary:
	var hits: Array = []
	var failures: Array = []
	var mag := 0.0
	var angle := 0.0
	var index := 0
	for t_ms in range(0, end_ms + 1, FRAME_MS):
		while index < changes.size() and int(changes[index][0]) == t_ms:
			mag = float(changes[index][1])
			angle = float(changes[index][2])
			index += 1
		var frame := Frame.new()
		frame.now = float(t_ms) / 1000.0
		frame.rs_mag = mag
		frame.rs_angle = angle
		var hit := detector.update(frame)
		if hit != null:
			hits.append(hit)
		var failure := detector.pop_failure()
		if failure != null:
			failures.append(failure)
	return {"hits": hits, "failures": failures}


## 逐帧推进单技能运行时：每帧全量 drain，与 UI 用法一致。
func _run_tap(runtime: TapRuntime, changes: Array, end_ms: int) -> Array:
	var outcomes: Array = []
	var label := ""
	var index := 0
	for t_ms in range(0, end_ms + 1, FRAME_MS):
		while index < changes.size() and int(changes[index][0]) == t_ms:
			label = str(changes[index][1])
			index += 1
		var frame := Frame.new()
		frame.now = float(t_ms) / 1000.0
		if label != "":
			for part in label.split("+", false):
				frame.buttons[part] = true
		runtime.tick(frame)
		outcomes.append_array(runtime.pop_outcomes())
	return outcomes


## `parse_bytes` 与出厂副本走同一条入口（decode + validate），不手抄阈值。
func _load_config(r) -> ConfigResult:
	var bytes := FileAccess.get_file_as_bytes(CONFIG_PATH)
	if bytes.is_empty():
		r.check(false, "读不到配置副本：%s" % CONFIG_PATH)
		return null
	var result := ConfigLoader.parse_bytes(bytes, CONFIG_PATH)
	if not result.ok():
		r.check(false, "配置副本无法加载：%s" % result.to_text())
		return null
	return result


func _find_skill(config: AppConfig, prefix: String) -> Skill:
	for skill in config.enabled_skills():
		if skill.name.begins_with(prefix):
			return skill
	return null


func _require_skills(r, skills: Array) -> bool:
	var names := ["马赛回旋", "磕球过人", "油炸丸子", "绿色搓射"]
	var ok := true
	for index in range(skills.size()):
		if skills[index] == null:
			r.check(false, "配置里必须有「%s」动作（找不到就无法证明 measured）" % names[index])
			ok = false
	if not ok:
		_mismatches += 1
	return ok


## 所有组共用的前置：没有 measured 的判定等于这条特性不存在，直接记一次失败。
func _require_measured(r, m: Dictionary, label: String) -> bool:
	var ok := not m.is_empty()
	_check(r, ok, "%s: measured 不能是空字典" % label)
	return ok


## Variant -> float。null / 非数值会让 `float()` 报运行时错误，这里先兜底成 NAN。
func _number(value: Variant) -> float:
	if value == null or not (typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT):
		return NAN
	return float(value)


## 抽第一个整数（含负号）。只用于第 6 组的同源断言。
func _first_integer(text: String) -> float:
	var regex := RegEx.new()
	if regex.compile("-?\\d+") != OK:
		return NAN
	var found := regex.search(text)
	if found == null:
		return NAN
	return float(found.get_string())


func _begin() -> void:
	_group_failed = false


func _end() -> void:
	_cases += 1
	if _group_failed:
		_mismatches += 1


func _check(r, ok: bool, label: String) -> void:
	if not ok:
		_group_failed = true
	r.check(ok, label)


func _eq_int(r, actual: int, expected: int, label: String) -> void:
	_check(r, actual == expected, "%s（实际 %d，期望 %d）" % [label, actual, expected])


func _eq_float(r, actual: float, expected: float, tol: float, label: String) -> void:
	if is_nan(actual):
		_check(r, false, "%s（实际值不是数值，期望 %.17f）" % [label, expected])
		return
	_check(r, absf(actual - expected) <= tol,
		"%s（实际 %.17f，期望 %.17f，容差 %s）" % [label, actual, expected, str(tol)])


func _eq_str(r, actual: String, expected: String, label: String) -> void:
	_check(r, actual == expected, "%s（实际 %s，期望 %s）" % [label, actual, expected])
