extends RefCounted

## tap 运行时黄金回放 + 五条不依赖夹具的结构断言。
##
## 与 `test_tap_detector.gd` 同构、共读同一份 `tap_golden.json`，只消费
## `kind == "runtime"` 的用例。分开成两个套件只为失败定位：检测器分叉与引擎分叉
## 是两类完全不同的 bug。
##
## 为什么构造运行时用的 Skill 必须来自真实配置：窗口 / 宽限 / 松开时长 / 冷却
## 全都写在 `skills_config.json` 里，手抄一份常量就等于允许两份数字各自漂移。
## `test-core.sh` 已经在第一步证明配置副本与唯一真源一致，这里再读同一份副本。
##
## 为什么还要五条结构断言：夹具只能证明「这 6 条时间线一致」，证明不了「布局硬门在
## 任意输入下都成立」，也证明不了「逐动作冷却分支可达」（真实配置 450 ms 下它不可达：
## 手势锁 150 + 重新武装 120 + 最短间隔 400 = 最短第二发命中在 670 ms 之后）。

const GOLDEN_PATH := "res://tests/fixtures/tap_golden.json"
const CONFIG_PATH := "res://assets/config/skills_config.json"
const TOL := 1e-6

## 逐条点名的 runtime 用例：少一条就红。删掉 runtime 用例不能靠 12 条 detector
## 用例蒙混过关 —— 本套件自己先断言条数与 id。
const REQUIRED_RUNTIME_IDS: Array[String] = [
	"rt_two_shots_500",
	"rt_two_shots_1000",
	"rt_gesture_lock",
	"rt_release_hold_rearm",
	"rt_one_verdict_per_attempt",
	"rt_layout_gate_blocks",
]

## 两发成功搓射（每发间隔 500ms，发间 700ms 空档）：分组归零与相对动作护栏共用。
## 用「变化点 + 结束时刻」描述，由 `_drive()` 展开成逐帧 4ms 时间轴 —— 与生成器同一
## 形状。不能只喂变化点：手势锁 / 重新武装都是按帧推进的计时器，稀疏帧会让它们
## 永远等不到阈值，第二发会被吞掉。
const TWO_SHOTS_500_CHANGES := [
	[0, ""],
	[4, "RB"],
	[100, "RB+X"],
	[104, "RB"],
	[600, "RB+X"],
	[604, "RB"],
	[1304, "RB+X"],
	[1308, "RB"],
	[1804, "RB+X"],
	[1808, "RB"],
]
const TWO_SHOTS_500_END_MS := 1820

## 两次命中相隔 800ms 的时间线：第一次命中在 600ms，第二次在 1400ms。
## 800 已越过真实配置的逐动作冷却 450、也越过重新武装所需的最早 670ms，
## 所以换 cooldown_ms = 900 时走逐动作分支，换 global_cooldown_ms = 1000 时走全局分支。
const COOLDOWN_CHANGES := [
	[0, ""],
	[4, "RB"],
	[100, "RB+X"],
	[104, "RB"],
	[600, "RB+X"],
	[604, "RB"],
	[880, "RB+X"],
	[884, "RB"],
	[1400, "RB+X"],
	[1404, "RB"],
]
const COOLDOWN_END_MS := 1420

var _mismatches := 0


func run(r) -> void:
	var data := _load_fixture(r)
	if data.is_empty():
		r.complete()
		return
	var cases := _runtime_cases(data)
	_check_scale(r, cases)

	var result := _load_config(r)
	if result == null:
		r.complete()
		return
	var skill := TapRuntime.select_taps_skill(result.config)
	if skill == null:
		r.check(false, "真实配置里必须有唯一的 taps 动作（select_taps_skill 返回 null）")
		_mismatches += 1
		r.complete()
		return
	_eq_str(r, skill.name, str(data.get("meta", {}).get("skill", "")),
		"select_taps_skill 选出的动作必须是夹具点名的动作")

	for case in cases:
		_check_case(r, case, skill, result.config)
	_check_layout_gate_blocks(r, skill, result.config)
	_check_global_cooldown_counts(r)
	_check_skill_cooldown_silent(r)
	_check_group_rollover(r, skill, result.config)
	_check_relative_skill_disabled(r, skill, result.config)

	print("TAP_GOLDEN_RUNTIME cases=%d mismatches=%d" % [cases.size(), _mismatches])
	r.complete()


func _load_fixture(r) -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes(GOLDEN_PATH)
	if bytes.is_empty():
		r.check(false, "读不到 tap 黄金夹具：%s（运行 python3 tools/gen_tap_golden.py 生成）" % GOLDEN_PATH)
		return {}
	var json := JSON.new()
	if json.parse(bytes.get_string_from_utf8()) != OK:
		r.check(false, "tap 黄金夹具不是合法 JSON（第 %d 行：%s）"
			% [json.get_error_line() + 1, json.get_error_message()])
		return {}
	if typeof(json.data) != TYPE_DICTIONARY:
		r.check(false, "tap 黄金夹具的根节点必须是对象")
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


## 规模与 id 下限：删空、丢掉点名用例、复制 id 都必须变红。
## `TAP_GOLDEN_RUNTIME cases=N` 里的 N 就是这里的条数 —— 12 条 detector 用例帮不上忙。
func _check_scale(r, cases: Array) -> void:
	_eq_int(r, cases.size(), 6, "runtime 用例必须正好 6 条")
	var ids: Dictionary = {}
	for case in cases:
		ids[str(case.get("id", ""))] = true
	_eq_int(r, ids.size(), cases.size(), "每条用例都必须有唯一 id")
	for required_id in REQUIRED_RUNTIME_IDS:
		var present: bool = ids.has(required_id)
		r.check(present, "runtime 用例必须包含点名 id %s" % required_id)
		if not present:
			_mismatches += 1
	_check_frame_grid(r, cases)


## 时间轴必须在 250 Hz / 4ms 网格上：换成别的采样率后 %.0f 才可能分叉。
func _check_frame_grid(r, cases: Array) -> void:
	for case in cases:
		var case_id := str(case.get("id", ""))
		var frames: Array = case.get("frames", [])
		r.check(not frames.is_empty(), "%s: frames 不能为空" % case_id)
		if frames.is_empty():
			_mismatches += 1
		for entry in frames:
			if typeof(entry) != TYPE_ARRAY or entry.size() != 2:
				r.check(false, "%s: frames 的每一项必须是 [t_ms, 按键]" % case_id)
				_mismatches += 1
				continue
			var t_ms := int(entry[0])
			if t_ms % 4 != 0:
				r.check(false, "%s: 帧时间 %d 必须是 4 的整数倍" % [case_id, t_ms])
				_mismatches += 1


## `parse_bytes` 就是 `decode_bytes` + `ConfigValidator.validate`（见 config_loader.gd），
## 与 04-01 的回放套件走同一条入口。
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


func _check_case(r, case: Dictionary, skill: Skill, config: AppConfig) -> void:
	var case_id := str(case.get("id", "<缺 id>"))
	var confirmed := bool(case.get("layout_confirmed", true))
	var runtime := TapRuntime.new(skill, config.global_cooldown_ms,
		config.input.gesture_release_ms, confirmed)
	var actual: Array[Outcome] = []
	for entry in case.get("frames", []):
		var frame := _make_frame(int(entry[0]), str(entry[1]))
		runtime.tick(frame)
		# 每帧全量 drain 再累积：这正是 UI 的用法，也证明队列不会被覆盖。
		actual.append_array(runtime.pop_outcomes())
	var expect: Dictionary = case.get("expect", {})
	_check_outcomes(r, case_id, actual, expect.get("outcomes", []))
	_check_counters(r, case_id, runtime, expect.get("counters", {}))


func _check_outcomes(r, case_id: String, actual: Array[Outcome], expected: Array) -> void:
	_eq_int(r, actual.size(), expected.size(), "%s: Outcome 条数" % case_id)
	for index in range(mini(actual.size(), expected.size())):
		var outcome: Outcome = actual[index]
		var want: Dictionary = expected[index]
		_eq_bool(r, outcome.ok, bool(want.get("ok", false)),
			"%s: outcomes[%d].ok" % [case_id, index])
		_eq_str(r, str(outcome.code), str(want.get("code", "")),
			"%s: outcomes[%d].code" % [case_id, index])
		_eq_float(r, outcome.elapsed_ms, float(want.get("elapsed_ms", 0.0)),
			"%s: outcomes[%d].elapsed_ms" % [case_id, index])
		_eq_str(r, outcome.message, str(want.get("message", "")),
			"%s: outcomes[%d].message" % [case_id, index])
		_eq_str(r, outcome.detail, str(want.get("detail", "")),
			"%s: outcomes[%d].detail" % [case_id, index])
		_eq_int(r, outcome.seq, index + 1,
			"%s: outcomes[%d].seq 必须从 1 单调递增" % [case_id, index])


func _check_counters(r, case_id: String, runtime: TapRuntime, expected: Dictionary) -> void:
	_eq_int(r, runtime.hits, int(expected.get("hits", 0)), "%s: counters.hits" % case_id)
	_eq_int(r, runtime.attempts, int(expected.get("attempts", 0)),
		"%s: counters.attempts" % case_id)
	_eq_int(r, runtime.group_hits, int(expected.get("group_hits", 0)),
		"%s: counters.group_hits" % case_id)
	_eq_int(r, runtime.groups_done, int(expected.get("groups_done", 0)),
		"%s: counters.groups_done" % case_id)
	_eq_int(r, runtime.suppressed, int(expected.get("suppressed", 0)),
		"%s: counters.suppressed" % case_id)


## 布局硬门：未确认时**任意**输入零判定，且中途撤销确认必须静默清场。
##
## 第一个序列是「噪声 + 一条本来会命中的 500ms 两下」：纯确定性噪声凑不成一次合法
## 搓射（X 每 4~16ms 反转一次，`_armed` 永远等不到 120ms 的松开），那样这条断言会
## 变成真空 —— 布局门被删掉也照样绿。叠一条干净的两下以后，没有布局门就必然产出判定。
##
## 第二个序列是断连的模型：`_t0` 已建立（半截搓射）→ 撤销确认 → 恢复 → 喂一帧
## 无按键。若 `set_layout_confirmed(false)` 没有 `abandon()`，`reset()` 会立刻产
## hold_short —— 断连被当成一次「保持不够」的尝试，这是明确不允许的。
func _check_layout_gate_blocks(r, skill: Skill, config: AppConfig) -> void:
	var blocked := TapRuntime.new(skill, config.global_cooldown_ms,
		config.input.gesture_release_ms, false)
	var leaked := 0
	for index in range(200):
		var frame := Frame.new()
		frame.now = float(index * 4) / 1000.0
		# 确定性伪随机：不用 randi()，否则失败无法复现。
		var mask := (index * 37 + 11) % 8
		if mask & 1:
			frame.buttons["RB"] = true
		if mask & 2:
			frame.buttons["X"] = true
		if mask & 4:
			frame.buttons["RT"] = true
		# 4~104ms 按住 RB；100ms 第一下 X；600ms 第二下 X（间隔 500ms，本来会命中）。
		if index >= 1 and index <= 26:
			frame.buttons["RB"] = true
			frame.buttons.erase("X")
		if index == 25:
			frame.buttons["X"] = true
		if index >= 27 and index <= 149:
			frame.buttons["RB"] = true
			frame.buttons.erase("X")
		if index == 150:
			frame.buttons["RB"] = true
			frame.buttons["X"] = true
		if index == 151:
			frame.buttons["RB"] = true
			frame.buttons.erase("X")
		blocked.tick(frame)
		leaked += blocked.pop_outcomes().size()
	_eq_int(r, leaked, 0, "未确认布局时 200 帧任意输入必须零 Outcome")
	_eq_int(r, blocked.hits, 0, "未确认布局时 hits 必须为 0")
	_eq_int(r, blocked.attempts, 0, "未确认布局时 attempts 必须为 0")
	_eq_str(r, blocked.status(), "未确认布局", "未确认布局时 status 必须直说")

	var runtime := TapRuntime.new(skill, config.global_cooldown_ms,
		config.input.gesture_release_ms, true)
	runtime.tick(_make_frame(0, ""))
	runtime.tick(_make_frame(100, "RB+X"))
	var mid_status := runtime.status()
	r.check(mid_status != "待机", "半截搓射时 status 必须显示已按第一下（实际 %s）" % mid_status)
	if mid_status == "待机":
		_mismatches += 1

	runtime.set_layout_confirmed(false)
	_eq_bool(r, runtime.layout_confirmed, false, "set_layout_confirmed(false) 必须立刻生效")
	runtime.set_layout_confirmed(true)
	runtime.tick(_make_frame(104, ""))
	_eq_int(r, runtime.pop_outcomes().size(), 0,
		"断连后恢复不得产出 hold_short / too_slow（断连不是一次尝试）")
	_eq_int(r, runtime.attempts, 0, "断连不是一次尝试，attempts 必须保持 0")


## 全局冷却分支的可达证据：global_cooldown_ms = 1000，第二发命中在第一发后 800ms。
## 800 > 逐动作冷却 450（先通过），800 < 1000（被全局吞掉并 suppressed += 1）。
## 这条与下一条必须分开：把两个分支混成一个断言，改坏任意一边都看不出来。
func _check_global_cooldown_counts(r) -> void:
	var runtime := TapRuntime.new(_synthetic_skill(450), 1000, 150, true)
	_drive(runtime, COOLDOWN_CHANGES, COOLDOWN_END_MS)
	var outcomes := runtime.pop_outcomes()
	_eq_int(r, outcomes.size(), 1, "全局冷却：第二条命中必须被吞掉（只有 1 条 Outcome）")
	_eq_int(r, runtime.suppressed, 1, "全局冷却吞掉时必须 suppressed += 1")
	_eq_int(r, runtime.hits, 1, "全局冷却吞掉时 hits 不增加")


## 逐动作冷却分支的可达证据：cooldown_ms = 900，第二发命中仍在 800ms。
## 真实配置的 450ms 下这条分支不可达（最早第二发命中在 670ms 之后），
## 所以必须用合成运行时；真实时序不能冒充这个分支。
## 吞掉时**静默**：不记 Outcome，也不加 suppressed。
func _check_skill_cooldown_silent(r) -> void:
	var runtime := TapRuntime.new(_synthetic_skill(900), 60, 150, true)
	_drive(runtime, COOLDOWN_CHANGES, COOLDOWN_END_MS)
	var outcomes := runtime.pop_outcomes()
	_eq_int(r, outcomes.size(), 1, "逐动作冷却：第二条命中必须静默丢弃（只有 1 条 Outcome）")
	_eq_int(r, runtime.suppressed, 0, "逐动作冷却吞掉时 suppressed 必须不变")
	_eq_int(r, runtime.hits, 1, "逐动作冷却吞掉时 hits 不增加")


## 分组：group_size = 2 时第 2 次命中把 group_hits 归零、groups_done 加一。
## 另断言默认值仍是常量 10 —— 注入用的更小容量不能被顺手改成新默认。
func _check_group_rollover(r, skill: Skill, config: AppConfig) -> void:
	var runtime := TapRuntime.new(skill, config.global_cooldown_ms,
		config.input.gesture_release_ms, true, 2)
	_eq_int(r, runtime.group_size, 2, "构造注入的组容量必须生效")
	_drive(runtime, TWO_SHOTS_500_CHANGES, TWO_SHOTS_500_END_MS)
	_eq_int(r, runtime.hits, 2, "两发都必须命中")
	_eq_int(r, runtime.group_hits, 0, "第 2 次命中必须把 group_hits 归零")
	_eq_int(r, runtime.groups_done, 1, "第 2 次命中必须 groups_done += 1")

	_eq_int(r, TapRuntime.GROUP_SIZE, 10, "GROUP_SIZE 常量必须是 10")
	var default_runtime := TapRuntime.new(skill, config.global_cooldown_ms,
		config.input.gesture_release_ms, true)
	_eq_int(r, default_runtime.group_size, TapRuntime.GROUP_SIZE,
		"默认组容量必须等于 GROUP_SIZE")


## `relative_to_ls` 的技能在本阶段没有左摇杆基准：运行时整个禁用，任意输入零判定。
## 这条护栏必须是**构造期**决定的，不能靠调用方记得不喂帧。
func _check_relative_skill_disabled(r, skill: Skill, config: AppConfig) -> void:
	var relative := Skill.new()
	relative.name = skill.name
	relative.kind = Skill.KIND_TAPS
	relative.relative_to_ls = true
	var required: Array[String] = []
	required.assign(skill.required_buttons)
	relative.required_buttons = required
	relative.params = skill.params.duplicate()
	relative.cooldown_ms = skill.cooldown_ms

	var runtime := TapRuntime.new(relative, config.global_cooldown_ms,
		config.input.gesture_release_ms, true)
	_drive(runtime, TWO_SHOTS_500_CHANGES, TWO_SHOTS_500_END_MS)
	_eq_int(r, runtime.pop_outcomes().size(), 0,
		"relative_to_ls 的技能在本阶段必须整个禁用（零 Outcome）")
	_eq_int(r, runtime.hits, 0, "被禁用的运行时 hits 必须为 0")


## 合成 Skill：参数与真实绿色搓射一致，只有 cooldown_ms 由调用方指定。
## 存在的唯一理由是「真实 450ms 下逐动作冷却分支不可达」。
func _synthetic_skill(cooldown_ms: int) -> Skill:
	var skill := Skill.new()
	skill.name = "合成的绿色搓射"
	skill.kind = Skill.KIND_TAPS
	var required: Array[String] = []
	required.append("RB")
	skill.required_buttons = required
	skill.params = {
		"button": "X",
		"min_interval_ms": 400,
		"max_interval_ms": 600,
		"timeout_grace_ms": 150,
		"release_hold_ms": 120,
	}
	skill.cooldown_ms = cooldown_ms
	return skill


## 把「变化点 + 结束时刻」展开成逐帧 4ms 时间轴再喂给运行时。
## 生成器的 `_build_frames` 是同一形状：夹具与套件用同一种时间分辨率，稀疏帧不会
## 悄悄改变语义。
func _drive(runtime: TapRuntime, changes: Array, end_ms: int) -> void:
	var label := ""
	var index := 0
	for t_ms in range(0, end_ms + 1, 4):
		while index < changes.size() and int(changes[index][0]) == t_ms:
			label = str(changes[index][1])
			index += 1
		runtime.tick(_make_frame(t_ms, label))


func _make_frame(t_ms: int, label: String) -> Frame:
	var frame := Frame.new()
	frame.now = float(t_ms) / 1000.0
	if label != "":
		for part in label.split("+", false):
			frame.buttons[part] = true
	return frame


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
