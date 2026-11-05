extends RefCounted

## 无设备竖切集成套件：真实配置字节 → ConfigLoader / ConfigValidator → Skill →
## TapRuntime → Outcome，中间没有夹具、没有手写期望值。
##
## 为什么必须读真实字节：窗口 / 宽限 / 松开 / 冷却全写在 `skills_config.json` 里；
## 手抄一份常量等于允许两份数字各自漂移。`test-core.sh` 的第一步已经证明配置副本
## 与唯一真源一致，这里读同一份副本。
##
## 为什么是 60 Hz 而不是 250 Hz：手机上就是 60–125 Hz。用 60 Hz 走通，证明毫秒
## 阈值在抽稀后仍然成立，而不是只在桌面版的 4 ms 网格上成立。误差来源只有一帧
## 的量化（±16.7 ms），所以断言给的是区间而不是点值。
##
## 为什么每段都新建运行时：手势锁、重新武装计时与逐动作冷却都活在上一个实例里；
## 复用会让上一段的锁污染下一段，失败定位会变成「看起来哪里都不对」。
##
## 最后一段是**行为测试**而不是源码字符串检查：`result_banner.accepts()` 是
## 「同一 seq 只显示一次」的唯一实现，直接调静态函数就能证明它有牙齿。

const CONFIG_PATH := "res://assets/config/skills_config.json"
const BANNER := preload("res://src/ui/result_banner.gd")

## 60 Hz：与手机端的实际轮询率同量级。
const FRAME_SECONDS := 1.0 / 60.0
## 时间轴末端余量：保证最后一次按键变化之后还有帧可走（锁 / 超时都按帧推进）。
const TAIL_MS := 200.0

## 一条成功的绿色搓射：按住 RB，100 ms 第一下 X，580 ms 第二下 X（间隔约 480 ms）。
## 用「变化点」而不是逐帧描述，由 `_frames()` 展开成 60 Hz 时间轴。
const SHOT_480 := [
	[0, []],
	[40, ["RB"]],
	[100, ["RB", "X"]],
	[140, ["RB"]],
	[580, ["RB", "X"]],
	[620, ["RB"]],
]

## 两下间隔约 300 ms：低于 400 ms 下限。
const TOO_FAST := [
	[0, []],
	[40, ["RB"]],
	[100, ["RB", "X"]],
	[140, ["RB"]],
	[400, ["RB", "X"]],
	[440, ["RB"]],
]

## 两下间隔约 700 ms：高于 600 ms 上限，但仍在 max + grace（750 ms）之前起手，
## 所以走的是「第二下太慢」分支，而不是超时分支。
const TOO_SLOW := [
	[0, []],
	[40, ["RB"]],
	[100, ["RB", "X"]],
	[140, ["RB"]],
	[800, ["RB", "X"]],
	[840, ["RB"]],
]

## 第一下之后 200 ms 撤掉 RB：检测器必须报「保持不够」。
const HOLD_SHORT := [
	[0, []],
	[40, ["RB"]],
	[100, ["RB", "X"]],
	[140, ["RB"]],
	[300, ["X"]],
]

## 两发成功、发间留 1.2 s 空档：第一发命中在约 583 ms，第二发起手在 1780 ms。
const TWO_SHOTS := [
	[0, []],
	[40, ["RB"]],
	[100, ["RB", "X"]],
	[140, ["RB"]],
	[580, ["RB", "X"]],
	[620, ["RB"]],
	[1780, ["RB", "X"]],
	[1820, ["RB"]],
	[2260, ["RB", "X"]],
	[2300, ["RB"]],
]


func run(r) -> void:
	_check_layout_gate(r)
	_check_single_shot_success(r)
	_check_too_fast(r)
	_check_too_slow(r)
	_check_hold_short(r)
	_check_two_shots(r)
	_check_result_banner_dedupe(r)
	r.complete()


## 1. 未确认布局：喂一条本来会命中的时间轴，必须零 Outcome、零 hits。
## 这是成功标准 4 在组合根之外的机械落点，也是「轴映射未确认不判」的证据。
func _check_layout_gate(r) -> void:
	var data := _load_runtime(r, false)
	if data.is_empty():
		return
	var runtime: TapRuntime = data["runtime"]
	var outcomes := _drive(runtime, SHOT_480)
	_eq_int(r, outcomes.size(), 0, "未确认布局时 480ms 搓射必须零 Outcome")
	_eq_int(r, runtime.hits, 0, "未确认布局时 hits 必须为 0")
	_eq_int(r, runtime.attempts, 0, "未确认布局时 attempts 必须为 0")
	_eq_str(r, runtime.status(), "未确认布局", "未确认布局时 status 必须直说")


## 2. 一次成功：恰好 1 条，成功码 / 摘要 / 毫秒区间都对；二次 drain 必须为空。
func _check_single_shot_success(r) -> void:
	var data := _load_runtime(r, true)
	if data.is_empty():
		return
	var runtime: TapRuntime = data["runtime"]
	var outcomes := _drive(runtime, SHOT_480)
	_eq_int(r, outcomes.size(), 1, "一次成功搓射必须恰好 1 条 Outcome")
	if outcomes.size() == 1:
		var outcome: Outcome = outcomes[0]
		r.check(outcome.ok, "成功判定的 ok 必须为 true")
		_eq_str(r, str(outcome.code), "ok", "成功判定的 code 必须是 ok")
		_eq_str(r, outcome.message, "", "成功判定的 message 必须为空串")
		r.check(not outcome.detail.is_empty(), "成功判定的 detail 必须是检测器现场生成的摘要")
		r.check(outcome.elapsed_ms >= 400.0 and outcome.elapsed_ms <= 600.0,
			"成功判定的 elapsed_ms 必须落在 [400, 600]（实际 %.3f）" % outcome.elapsed_ms)
	_eq_int(r, runtime.pop_outcomes().size(), 0, "第二次 drain 必须为空（队列而不是单槽）")
	_eq_int(r, runtime.hits, 1, "成功一次后 hits 必须是 1")


## 3. 太快：两下间隔约 300 ms。
func _check_too_fast(r) -> void:
	var data := _load_runtime(r, true)
	if data.is_empty():
		return
	var runtime: TapRuntime = data["runtime"]
	var outcomes := _drive(runtime, TOO_FAST)
	_eq_int(r, outcomes.size(), 1, "太快的时间轴必须恰好 1 条 Outcome")
	if outcomes.size() == 1:
		var outcome: Outcome = outcomes[0]
		_eq_str(r, str(outcome.code), "too_fast", "太快时 code 必须是 too_fast")
		r.check(not outcome.ok, "失败判定的 ok 必须为 false")
		r.check(outcome.elapsed_ms >= 280.0 and outcome.elapsed_ms <= 320.0,
			"太快判定的 elapsed_ms 必须落在 [280, 320]（实际 %.3f）" % outcome.elapsed_ms)
		r.check(not outcome.message.is_empty(), "失败判定必须带可渲染的原因")
	_eq_int(r, runtime.hits, 0, "太快不增加 hits")


## 4. 太慢：两下间隔约 700 ms。
func _check_too_slow(r) -> void:
	var data := _load_runtime(r, true)
	if data.is_empty():
		return
	var runtime: TapRuntime = data["runtime"]
	var outcomes := _drive(runtime, TOO_SLOW)
	_eq_int(r, outcomes.size(), 1, "太慢的时间轴必须恰好 1 条 Outcome")
	if outcomes.size() == 1:
		var outcome: Outcome = outcomes[0]
		_eq_str(r, str(outcome.code), "too_slow", "太慢时 code 必须是 too_slow")
		r.check(outcome.elapsed_ms >= 680.0 and outcome.elapsed_ms <= 720.0,
			"太慢判定的 elapsed_ms 必须落在 [680, 720]（实际 %.3f）" % outcome.elapsed_ms)
	_eq_int(r, runtime.hits, 0, "太慢不增加 hits")


## 5. 中途松开修饰键：hold_short，原因文本必须含「保持不够」。
func _check_hold_short(r) -> void:
	var data := _load_runtime(r, true)
	if data.is_empty():
		return
	var runtime: TapRuntime = data["runtime"]
	var outcomes := _drive(runtime, HOLD_SHORT)
	_eq_int(r, outcomes.size(), 1, "中途松开 RB 必须恰好 1 条 Outcome")
	if outcomes.size() == 1:
		var outcome: Outcome = outcomes[0]
		_eq_str(r, str(outcome.code), "hold_short", "松开修饰键时 code 必须是 hold_short")
		r.check(outcome.message.contains("保持不够"),
			"hold_short 的 message 必须含「保持不够」（实际 %s）" % outcome.message)
	_eq_int(r, runtime.attempts, 1, "hold_short 是一次尝试，attempts 必须为 1")


## 6. 两发独立：恰好 2 条成功、seq 严格递增、计数器各自加一。
func _check_two_shots(r) -> void:
	var data := _load_runtime(r, true)
	if data.is_empty():
		return
	var runtime: TapRuntime = data["runtime"]
	var outcomes := _drive(runtime, TWO_SHOTS)
	_eq_int(r, outcomes.size(), 2, "两发成功必须恰好 2 条 Outcome")
	if outcomes.size() == 2:
		r.check(outcomes[0].ok and outcomes[1].ok, "两条都必须是成功")
		_eq_str(r, str(outcomes[0].code), "ok", "第一发 code 必须是 ok")
		_eq_str(r, str(outcomes[1].code), "ok", "第二发 code 必须是 ok")
		r.check(outcomes[1].seq > outcomes[0].seq, "第二条的 seq 必须严格大于第一条")
	_eq_int(r, runtime.hits, 2, "两发成功后 hits 必须是 2")
	_eq_int(r, runtime.attempts, 2, "两发成功后 attempts 必须是 2")
	_eq_int(r, runtime.group_hits, 2, "两发成功后 group_hits 必须是 2")


## 7. 横幅去重谓词的行为断言（不是源码字符串检查）。
## 同一 seq 第二次必须被忽略；更大的 seq 必须被接受。`clear()` 不重置序号是
## 本谓词的下游约定，由 `result_banner.gd` 的注释与实现共同保证。
func _check_result_banner_dedupe(r) -> void:
	r.check(BANNER.accepts(0, 1), "首个结果（shown=0, seq=1）必须被接受")
	r.check(not BANNER.accepts(1, 1), "同一 seq 重复到达必须被忽略")
	r.check(BANNER.accepts(1, 2), "更大的 seq 必须被接受")


## 读真实配置字节 → 解码 → 校验 → 用组合根同一个筛选函数选动作 → 新运行时。
## 失败时只记失败并返回空字典；`run()` 末尾仍会 `complete()`，不会挂死。
func _load_runtime(r, layout_confirmed: bool) -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes(CONFIG_PATH)
	if bytes.is_empty():
		r.check(false, "读不到真实配置 %s（先运行 python3 tools/sync_config.py）" % CONFIG_PATH)
		return {}
	var decoded := ConfigLoader.decode_bytes(bytes, CONFIG_PATH)
	if decoded["error"] != null:
		var error: ConfigError = decoded["error"]
		r.check(false, "真实配置字节解码失败：%s" % error.message)
		return {}
	var result := ConfigValidator.validate(decoded["data"], CONFIG_PATH)
	if not result.ok():
		r.check(false, "真实配置未通过校验：%s" % result.to_text())
		return {}
	# 与组合根走同一条实现：不在测试里复刻「遍历 skills 找 taps」的循环。
	var skill := TapRuntime.select_taps_skill(result.config)
	if skill == null:
		r.check(false, "真实配置里必须恰好一条启用的 taps 动作（select_taps_skill 返回 null）")
		return {}
	r.check(skill.name.contains("绿色搓射"),
		"select_taps_skill 必须选出绿色搓射（实际 %s）" % skill.name)
	var taps_count := 0
	for candidate in result.config.enabled_skills():
		if candidate.kind == Skill.KIND_TAPS:
			taps_count += 1
	r.check(taps_count == 1, "真实配置必须恰好一条启用的 taps 动作（实际 %d）" % taps_count)
	return {
		"runtime": TapRuntime.new(skill, result.config.global_cooldown_ms,
			result.config.input.gesture_release_ms, layout_confirmed),
		"skill": skill,
	}


## 把「变化点 + 按键集合」展开成 60 Hz 逐帧时间轴，逐帧 tick 并全量 drain。
func _drive(runtime: TapRuntime, changes: Array) -> Array[Outcome]:
	var outcomes: Array[Outcome] = []
	for frame in _frames(changes):
		runtime.tick(frame)
		outcomes.append_array(runtime.pop_outcomes())
	return outcomes


## 把「变化点 + 按键集合」展开成 60 Hz 逐帧时间轴。
func _frames(changes: Array) -> Array[Frame]:
	var frames: Array[Frame] = []
	if changes.is_empty():
		return frames
	var end_ms := float(changes[changes.size() - 1][0]) + TAIL_MS
	var change_index := 0
	var frame_index := 0
	while true:
		var t_ms := float(frame_index) * FRAME_SECONDS * 1000.0
		if t_ms > end_ms:
			break
		while change_index < changes.size() and float(changes[change_index][0]) <= t_ms:
			change_index += 1
		var labels: Array = []
		if change_index > 0:
			labels = changes[change_index - 1][1]
		var frame := Frame.new()
		frame.now = t_ms / 1000.0
		for label in labels:
			frame.buttons[str(label)] = true
		frames.append(frame)
		frame_index += 1
	return frames


func _eq_int(r, actual: int, expected: int, label: String) -> void:
	r.check(actual == expected, "%s（实际 %d，期望 %d）" % [label, actual, expected])


func _eq_str(r, actual: String, expected: String, label: String) -> void:
	r.check(actual == expected, "%s（实际 %s，期望 %s）" % [label, actual, expected])
