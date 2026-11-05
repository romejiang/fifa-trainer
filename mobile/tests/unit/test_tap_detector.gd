extends RefCounted

## tap 检测器黄金回放：把 Python 生成的时间轴逐帧喂给 GDScript TapDetector，
## 逐字比对 Hit / Failure。
##
## 为什么用 FileAccess.get_file_as_bytes + JSON.new().parse()：与 test_geometry.gd
## 同一理由 —— 读字节不做字符串层面的意外转换；parse_string() 失败时会向 stderr
## 打 ERROR 且不给行号。
##
## 为什么按「引擎分支」驱动而不是无脑 update()：参考实现的引擎在修饰键不满足时
## 调用 observe() **然后** reset()（desktop/padskills/engine.py:273-279），顺序不能
## 反。只调 update() 的话，hold_short 这类由 reset() 产生的失败会一条都不出现。
##
## 为什么用例结束不 reset()：det_too_slow_boundary_750 的尾巴停在 interval=748
## （4ms 网格上取不到 750），到这里本来就该沉默；无条件 reset 会凭空多出一条
## hold_short。reset() 只出现在「修饰键不满足」这条引擎分支里。
##
## 判据全部走 reporter 的 check / eq_float，不用 assert；最后一句必须是 r.complete()。

const GOLDEN_PATH := "res://tests/fixtures/tap_golden.json"
const CONFIG_PATH := "res://assets/config/skills_config.json"
const TOL := 1e-6

## 逐条点名的 detector 用例：少一条就红。删掉大半夹具时，逐用例循环会零次
## 「通过」，所以规模与 id 下限必须先于任何回放执行。
const REQUIRED_DETECTOR_IDS: Array[String] = [
	"det_success_min_400",
	"det_success_mid_450",
	"det_success_max_600",
	"det_too_fast_300",
	"det_too_slow_second_700",
	"det_too_slow_no_second",
	"det_too_slow_boundary_750",
	"det_hold_short_modifier_released",
	"det_modifier_switch_rb_to_rt",
	"det_set_modifier_rt_success",
	"det_first_frame_held_x",
	"det_release_hold_gate",
]

var _mismatches := 0


func run(r) -> void:
	var data := _load_fixture(r)
	if data.is_empty():
		r.complete()
		return
	var cases := _detector_cases(data)
	_check_meta(r, data)
	_check_scale(r, cases, data)

	var meta: Dictionary = data.get("meta", {})
	var base_skill := _load_skill(r, str(meta.get("skill", "")))
	if base_skill == null:
		r.complete()
		return
	for case in cases:
		_check_case(r, case, base_skill)
	_check_abandon_silent(r, base_skill)
	print("TAP_GOLDEN_DETECTOR cases=%d mismatches=%d" % [cases.size(), _mismatches])
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


## 04-02 会往同一份夹具加入 runtime 用例；过滤器从第一天就在，回放只看 detector。
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


## 规模与 id 下限：删空夹具、丢掉点名用例、复制 id 都必须变红。
##
## 只断言 kind == "detector" 的条数，不对总 cases.size() 下断言：04-02 会往同一份
## 夹具加入 runtime 用例，总数会变成 18；两个计划合起来才能防「删掉一大半」。
func _check_scale(r, cases: Array, data: Dictionary) -> void:
	_eq_int(r, cases.size(), 12, "detector 用例必须正好 12 条")
	var ids: Dictionary = {}
	for case in cases:
		ids[str(case.get("id", ""))] = true
	_eq_int(r, ids.size(), cases.size(), "每条用例都必须有唯一 id")
	for required_id in REQUIRED_DETECTOR_IDS:
		var present: bool = ids.has(required_id)
		r.check(present, "detector 用例必须包含点名 id %s" % required_id)
		if not present:
			_mismatches += 1
	_check_frame_grid(r, data)


## 所有帧必须落在 250 Hz / 4ms 网格上：时间轴换成别处采样率后，%.0f 才可能分叉；
## 这条断言让「偷偷换采样率」当场变红，而不是等文案对不上才发现。
func _check_frame_grid(r, data: Dictionary) -> void:
	for case in data.get("cases", []):
		if typeof(case) != TYPE_DICTIONARY or str(case.get("kind", "")) != "detector":
			continue
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


## 检测器的窗口 / 宽限 / 松开时长来自真实配置副本（test-core.sh 先证明它与唯一
## 真源一致），不在这里写第二份常量。夹具由同一份配置生成，两边若漂移，比对必红。
func _load_skill(r, skill_name: String) -> Skill:
	var bytes := FileAccess.get_file_as_bytes(CONFIG_PATH)
	if bytes.is_empty():
		r.check(false, "读不到配置副本：%s" % CONFIG_PATH)
		return null
	var result := ConfigLoader.parse_bytes(bytes, CONFIG_PATH)
	if not result.ok():
		r.check(false, "配置副本无法加载：%s" % result.to_text())
		return null
	for skill in result.config.skills:
		if skill.name == skill_name:
			return skill
	r.check(false, "配置里找不到夹具点名的动作 %s" % skill_name)
	return null


## 每个用例的初始修饰键来自 case.modifier；params 复制真实配置，只覆盖 button。
func _build_skill(base: Skill, case: Dictionary) -> Skill:
	var skill := Skill.new()
	skill.name = base.name
	skill.kind = Skill.KIND_TAPS
	var required: Array[String] = []
	required.append(str(case.get("modifier", "")))
	skill.required_buttons = required
	var params: Dictionary = base.params.duplicate()
	params["button"] = str(case.get("button", "X"))
	skill.params = params
	return skill


func _check_case(r, case: Dictionary, base_skill: Skill) -> void:
	var case_id := str(case.get("id", "<缺 id>"))
	var detector := TapDetector.new(_build_skill(base_skill, case))
	if case.has("set_modifier"):
		# 与生成器同一入口、同一顺序：必须在喂首帧之前调用。
		detector.set_modifier(str(case["set_modifier"]))
	var actual := _replay(detector, case.get("frames", []))
	var expect: Dictionary = case.get("expect", {})
	_check_hits(r, case_id, actual["hits"], expect.get("hits", []))
	_check_failures(r, case_id, actual["failures"], expect.get("failures", []))
	if expect.has("status_after_first_press"):
		_eq_str(r, str(actual["status_after_first_press"]),
			str(expect["status_after_first_press"]), "%s: 首次按下后的 status" % case_id)


## 不依赖夹具的结构断言：abandon() 必须静默、清槽，并按 _prev_pressed 重算 _armed。
##
## 如果 abandon() 被「顺手合并」成 reset()，第一条 pop_failure() 就会拿到 hold_short；
## 如果只清了 _t0/_release_since 而漏掉最后一行 `_armed = not _prev_pressed`，两个方向
## 的 _armed 断言会分别变红。仓库既有纪律：测试可以直接读带下划线的私有字段。
func _check_abandon_silent(r, base_skill: Skill) -> void:
	var synthetic := {"modifier": "RB", "button": "X"}
	var detector := TapDetector.new(_build_skill(base_skill, synthetic))
	detector.update(_make_frame(0, "RB"))
	detector.update(_make_frame(100, "RB+X"))
	_eq_bool(r, detector._have_t0, true, "abandon 前：_t0 已建立")

	detector.observe(_make_frame(200, "RB+X"))
	detector.abandon()
	var silent: bool = detector.pop_failure() == null
	r.check(silent, "abandon() 必须静默（不产 hold_short）")
	if not silent:
		_mismatches += 1
	_eq_str(r, detector.status(), "待机", "abandon() 后 status 回到待机")
	_eq_bool(r, detector._armed, false, "X 仍按住时 abandon() 后 _armed 必须是 false")

	detector.observe(_make_frame(300, "RB"))
	detector.abandon()
	_eq_bool(r, detector._armed, true, "X 松开后 abandon() 必须重新武装（_armed == true）")

	# 失败单槽也要被静默清掉：先造成一次 too_fast（不 pop），再 abandon。
	var slot := TapDetector.new(_build_skill(base_skill, synthetic))
	slot.update(_make_frame(0, "RB"))
	slot.update(_make_frame(100, "RB+X"))
	slot.update(_make_frame(200, "RB"))
	slot.update(_make_frame(300, "RB+X"))
	var pending_present: bool = slot._pending != null
	r.check(pending_present, "构造 too_fast 后失败单槽必须非空")
	if not pending_present:
		_mismatches += 1
	slot.abandon()
	var cleared: bool = slot.pop_failure() == null
	r.check(cleared, "abandon() 必须清掉尚未取走的失败单槽")
	if not cleared:
		_mismatches += 1


## 逐帧回放：修饰键满足才 update，否则 observe + reset（顺序不能反）；
## 每帧后 pop_failure。用例结束不 reset。
func _replay(detector: TapDetector, frames: Array) -> Dictionary:
	var hits: Array = []
	var failures: Array = []
	var status_after_first_press := ""
	var recorded_status := false
	for entry in frames:
		var t_ms := int(entry[0])
		var label := str(entry[1])
		var frame := _make_frame(t_ms, label)
		var mods_ok := true
		for required_button in detector.required:
			if not frame.buttons.has(required_button):
				mods_ok = false
				break
		if mods_ok:
			var hit := detector.update(frame)
			if hit != null:
				hits.append(hit)
		else:
			detector.observe(frame)
			detector.reset()
		if not recorded_status and detector._have_t0:
			status_after_first_press = detector.status()
			recorded_status = true
		var failure := detector.pop_failure()
		if failure != null:
			failures.append(failure)
	return {
		"hits": hits,
		"failures": failures,
		"status_after_first_press": status_after_first_press,
	}


func _make_frame(t_ms: int, label: String) -> Frame:
	var frame := Frame.new()
	frame.now = float(t_ms) / 1000.0
	if label != "":
		for part in label.split("+", false):
			frame.buttons[part] = true
	return frame


func _check_hits(r, case_id: String, actual: Array, expected: Array) -> void:
	_eq_int(r, actual.size(), expected.size(), "%s: Hit 条数" % case_id)
	for index in range(mini(actual.size(), expected.size())):
		var hit: Hit = actual[index]
		var want: Dictionary = expected[index]
		_eq_float(r, hit.elapsed_ms, float(want.get("elapsed_ms", 0.0)),
			"%s: hits[%d].elapsed_ms" % [case_id, index])
		_eq_str(r, hit.summary, str(want.get("summary", "")),
			"%s: hits[%d].summary" % [case_id, index])
		_eq_str(r, hit.detail, str(want.get("detail", "")),
			"%s: hits[%d].detail" % [case_id, index])


func _check_failures(r, case_id: String, actual: Array, expected: Array) -> void:
	_eq_int(r, actual.size(), expected.size(), "%s: Failure 条数" % case_id)
	for index in range(mini(actual.size(), expected.size())):
		var failure: Failure = actual[index]
		var want: Dictionary = expected[index]
		_eq_str(r, str(failure.code), str(want.get("code", "")),
			"%s: failures[%d].code" % [case_id, index])
		_eq_str(r, failure.message, str(want.get("message", "")),
			"%s: failures[%d].message" % [case_id, index])
		_eq_float(r, failure.elapsed_ms, float(want.get("elapsed_ms", 0.0)),
			"%s: failures[%d].elapsed_ms" % [case_id, index])


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
