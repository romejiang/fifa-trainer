extends RefCounted

## 校验器套件：三类动作的接受路径 + 每条规则的拒绝路径。
##
## 反例优先：真实配置通过只证明「没误杀」，每条规则还必须有一条已知坏输入证明
## 「真的会拒」。三个点名坏输入（字符串布尔 / null 数值 / start_angle 数组）都是
## Python 静默接受或晚失败、移动端必须早失败的分歧点。
##
## 每条拒绝用例统一再断言 message 与 fix_hint 非空 —— 成功标准 3 的「修复建议」
## 必须机械可证，空串不能通过。
##
## 判据全部走 reporter 的 check；最后一句必须是 r.complete()。

const CONFIG_PATH := "res://assets/config/skills_config.json"


func run(r) -> void:
	_check_real_config(r)
	_check_minimal_valid(r)
	_check_rejections(r)
	r.complete()


# ---------------------------------------------------------------------------
# 接受路径
# ---------------------------------------------------------------------------

func _check_real_config(r) -> void:
	var bytes := FileAccess.get_file_as_bytes(CONFIG_PATH)
	if bytes.is_empty():
		r.check(false, "读不到真实配置 %s（先运行 python3 tools/sync_config.py）" % CONFIG_PATH)
		return
	var result := ConfigLoader.parse_bytes(bytes, CONFIG_PATH)
	r.check(result.ok(), "真实配置必须通过校验（实际 %s）" % _text(result))
	r.check(result.errors.is_empty(),
		"真实配置不应产生任何 error（实际 %s）" % _paths(result.errors))
	if result.config == null:
		return
	r.check(result.config.skills.size() == 5,
		"真实配置必须正好 5 条动作（实际 %d）" % result.config.skills.size())
	# 两处 arc 的 "direction": "any" 与 3 处 "required_button": null 不能被误杀。
	r.check(not result.has_code(&"direction_unknown"), "真实配置的 direction: any 必须被接受")
	r.check(not result.has_code(&"button_unknown"), "真实配置的 required_button: null 必须被接受")
	if result.config.skills.size() >= 5:
		var arc: Skill = result.config.skills[0]
		r.check(arc.kind == Skill.KIND_ARC, "第一条真实动作必须是 arc")
		var taps: Skill = result.config.skills[4]
		r.check(taps.kind == Skill.KIND_TAPS, "第五条真实动作必须是 taps")
		r.check(taps.params.has("modifier_options"), "taps 的 modifier_options 必须保留")
		var options: Array = taps.params["modifier_options"]
		r.check(options.size() == 2 and options[0] == "RB" and options[1] == "RT",
			"modifier_options 必须被归一成规范名（实际 %s）" % str(options))


func _check_minimal_valid(r) -> void:
	_expect_ok(r, "最小 arc 配置", _base_arc())
	_expect_ok(r, "最小 sequence 配置", _base_sequence())
	_expect_ok(r, "最小 taps 配置", _base_taps())

	# 解析后的字段真的落在 AppConfig 上，不是「校验通过但没赋值」。
	var result := ConfigValidator.validate(_base_arc(), "<minimal>")
	if result.config == null:
		r.check(false, "最小 arc 配置没有产出 AppConfig")
		return
	r.check(result.config.skills[0].kind == Skill.KIND_ARC, "arc 的 kind 必须落到 Skill")
	r.check(typeof(result.config.skills[0].pattern) == TYPE_ARRAY and not result.config.skills[0].pattern.is_empty(),
		"arc 必须产出至少一条 Pulse")
	r.check(result.config.input.deadzone > 0.0, "input.deadzone 必须被赋值")
	r.check(result.config.rumble.backend == &"auto", "rumble.backend 必须被赋值")


# ---------------------------------------------------------------------------
# 拒绝路径
# ---------------------------------------------------------------------------

func _check_rejections(r) -> void:
	# 根与 skills 结构
	_expect_reject_variant(r, "根不是对象", [], &"root_not_object", "$")
	_expect_reject(r, "skills 不是数组", {"skills": {}}, &"skills_not_array", "$.skills")
	_expect_reject(r, "skills 是空数组", {"skills": []}, &"skills_empty", "$.skills")
	_expect_reject(r, "动作不是对象", {"skills": [42]}, &"skill_not_object", "skills[0]")

	var bad_type := _base_arc()
	_first_skill(bad_type)["type"] = "nope"
	_expect_reject(r, "type 拼写错误", bad_type, &"skill_type_invalid", "skills[0].type")

	var bad_params := _base_arc()
	_first_skill(bad_params)["params"] = 7
	_expect_reject(r, "params 不是对象", bad_params, &"params_not_object", "skills[0].params")

	# 点名坏输入 1：字符串布尔必须早失败，不能 bool("false") == true。
	var string_bool := _base_arc()
	_first_skill(string_bool)["enabled"] = "false"
	_expect_reject(r, "字符串布尔", string_bool, &"bool_expected", "skills[0].enabled")
	var string_bool_result := ConfigValidator.validate(string_bool, "<test>")
	r.check(not string_bool_result.ok(), "字符串 \"false\" 必须被判拒，而不是当成 true")

	# 点名坏输入 2：null 数值不能崩，也不能被静默吞掉。
	var null_number := _base_arc()
	_first_params(_first_skill(null_number))["min_duration_ms"] = null
	_expect_reject(r, "null 数值", null_number, &"number_expected",
		"skills[0].params.min_duration_ms")

	# 点名坏输入 3：start_angle 数组在校验期就拒绝。
	var array_start := _base_arc()
	_first_params(_first_skill(array_start))["start_angle"] = [90, 180]
	_expect_reject(r, "start_angle 数组", array_start, &"start_angle_not_scalar",
		"skills[0].params.start_angle")

	# sequence 规则
	var empty_steps := _base_sequence()
	_first_params(_first_skill(empty_steps))["steps"] = []
	_expect_reject(r, "steps 空数组", empty_steps, &"steps_empty", "skills[0].params.steps")

	var missing_direction := _base_sequence()
	_first_params(_first_skill(missing_direction))["steps"] = [{"hold_ms": 100}]
	_expect_reject(r, "步骤缺 direction", missing_direction, &"step_direction_missing",
		"skills[0].params.steps[0]")

	var unknown_step_direction := _base_sequence()
	_first_params(_first_skill(unknown_step_direction))["steps"] = [{"direction": "clockwisee"}]
	_expect_reject(r, "步骤方向未知", unknown_step_direction, &"direction_unknown",
		"skills[0].params.steps[0]")

	var hold_too_long := _base_sequence()
	_first_params(_first_skill(hold_too_long))["steps"] = [{"direction": "forward", "hold_ms": 700}]
	_expect_reject(r, "hold 之和超窗口", hold_too_long, &"hold_sum_exceeds_max",
		"skills[0].params.max_duration_ms")
	r.check(_has_code(hold_too_long, &"hold_sum_exceeds_max"), "hold_sum_exceeds_max 必须真的产生")

	var max_le_min := _base_arc()
	_first_params(_first_skill(max_le_min))["max_duration_ms"] = 200
	_expect_reject(r, "max <= min", max_le_min, &"max_not_greater_than_min",
		"skills[0].params.max_duration_ms")

	# arc 的旋转方向：Python 静默当 any，移动端必须报出来。
	var unknown_rotation := _base_arc()
	_first_params(_first_skill(unknown_rotation))["direction"] = "clockwisee"
	_expect_reject(r, "弧线旋转方向未知", unknown_rotation, &"direction_unknown",
		"skills[0].params.direction")

	# taps 规则
	var unknown_button := _base_taps()
	_first_params(_first_skill(unknown_button))["button"] = "NOPE"
	_expect_reject(r, "taps 按键未知", unknown_button, &"button_unknown",
		"skills[0].params.button")

	var bad_mode := _base_arc()
	_first_skill(bad_mode)["button_mode"] = "some"
	_expect_reject(r, "button_mode 非法", bad_mode, &"button_mode_invalid",
		"skills[0].button_mode")

	var modifier_without_button := _base_taps()
	_first_skill(modifier_without_button)["required_button"] = null
	_expect_reject(r, "有选项没 required_button", modifier_without_button,
		&"modifier_requires_required_button", "skills[0].params.modifier_options")

	var button_not_in_options := _base_taps()
	_first_skill(button_not_in_options)["required_button"] = "LB"
	_expect_reject(r, "required_button 不在选项里", button_not_in_options,
		&"required_button_not_in_options", "skills[0].required_button")

	var duplicate_modifier := _base_taps()
	_first_params(_first_skill(duplicate_modifier))["modifier_options"] = ["RB", "rb"]
	_expect_reject(r, "modifier_options 重复", duplicate_modifier, &"modifier_duplicate",
		"skills[0].params.modifier_options")

	# input / rumble 根字段
	var bad_backend := _base_arc()
	var root_rumble: Dictionary = bad_backend["rumble"]
	root_rumble["backend"] = "bogus"
	_expect_reject(r, "rumble.backend 非法", bad_backend, &"rumble_backend_invalid",
		"$.rumble.backend")

	var bad_invert_key := _base_arc()
	bad_invert_key["input"] = {"invert": {"up_y": true}}
	_expect_reject(r, "invert 键非法", bad_invert_key, &"invert_key_invalid", "$.input.invert")

	var bad_invert_value := _base_arc()
	bad_invert_value["input"] = {"invert": {"rs_y": "true"}}
	_expect_reject(r, "invert 值不是布尔", bad_invert_value, &"invert_value_not_bool",
		"$.input.invert.rs_y")

	# 重复名字：每一处重复各一条，消息点名第一次出现的位置。
	var duplicate_name := _base_arc()
	var second: Dictionary = (_first_skill(duplicate_name) as Dictionary).duplicate(true)
	(duplicate_name["skills"] as Array).append(second)
	_expect_reject(r, "动作名重复", duplicate_name, &"duplicate_skill_name", "skills[1].name")
	var duplicate_result := ConfigValidator.validate(duplicate_name, "<test>")
	r.check(_count_code(duplicate_result.errors, &"duplicate_skill_name") == 1,
		"两个同名动作应报 1 条 duplicate_skill_name（实际 %d）"
			% _count_code(duplicate_result.errors, &"duplicate_skill_name"))


# ---------------------------------------------------------------------------
# 夹具
# ---------------------------------------------------------------------------

func _base_arc() -> Dictionary:
	return {
		"skills": [{
			"name": "测试弧线",
			"enabled": true,
			"type": "arc",
			"relative_to_ls": false,
			"required_button": null,
			"params": {
				"start_angle": 180,
				"end_angle": 0,
				"min_angle": 70,
				"max_angle": 230,
				"min_duration_ms": 250,
				"max_duration_ms": 600,
				"idle_timeout_ms": 250,
				"release_hold_ms": 120,
				"direction": "any",
			},
			"rumble": {"low": 0.8, "high": 0.0, "duration_ms": 120},
			"cooldown_ms": 400,
		}],
		"input": {},
		"rumble": {
			"enabled": true,
			"backend": "auto",
			"startup_test": true,
			"startup_test_strength": 0.55,
			"startup_test_ms": 160,
		},
		"global_cooldown_ms": 60,
	}


func _base_sequence() -> Dictionary:
	return {
		"skills": [{
			"name": "测试序列",
			"enabled": true,
			"type": "sequence",
			"relative_to_ls": true,
			"required_button": null,
			"params": {
				"steps": ["forward", "back"],
				"min_duration_ms": 250,
				"max_duration_ms": 600,
				"idle_timeout_ms": 250,
				"release_hold_ms": 150,
			},
			"rumble": {"low": 0.8, "high": 0.0, "duration_ms": 120},
			"cooldown_ms": 350,
		}],
		"input": {},
		"rumble": {"enabled": true, "backend": "auto"},
		"global_cooldown_ms": 60,
	}


func _base_taps() -> Dictionary:
	return {
		"skills": [{
			"name": "测试连按",
			"enabled": true,
			"type": "taps",
			"relative_to_ls": false,
			"required_button": "RB",
			"params": {
				"button": "X",
				"min_interval_ms": 400,
				"max_interval_ms": 600,
				"release_hold_ms": 120,
				"modifier_options": ["RB", "RT"],
			},
			"rumble": {"low": 0.8, "high": 0.0, "duration_ms": 120},
			"cooldown_ms": 450,
		}],
		"input": {},
		"rumble": {"enabled": true, "backend": "auto"},
		"global_cooldown_ms": 60,
	}


func _first_skill(data: Dictionary) -> Dictionary:
	var skills: Array = data["skills"]
	var skill: Dictionary = skills[0]
	return skill


func _first_params(skill: Dictionary) -> Dictionary:
	var params: Dictionary = skill["params"]
	return params


# ---------------------------------------------------------------------------
# 断言辅助
# ---------------------------------------------------------------------------

func _expect_ok(r, label: String, data: Dictionary) -> void:
	var result := ConfigValidator.validate(data, "<test>")
	r.check(result.ok(), "%s：必须通过（实际 %s）" % [label, _text(result)])
	r.check(result.errors.is_empty(), "%s：不应有 error（实际 %s）" % [label, _paths(result.errors)])
	r.check(result.config != null, "%s：必须产出 AppConfig" % label)


func _expect_reject(r, label: String, data: Dictionary, code: StringName,
		path: String) -> void:
	_expect_reject_variant(r, label, data, code, path)


func _expect_reject_variant(r, label: String, data: Variant, code: StringName,
		path: String) -> void:
	var result := ConfigValidator.validate(data, "<test>")
	r.check(not result.ok(), "%s：必须被拒绝，但 ok() 为 true" % label)
	r.check(result.has_code(code), "%s：应报 %s（实际 %s）" % [label, code, _codes(result)])
	r.check(_has_path(result.errors, path),
		"%s：应有一条 json_path=%s（实际 %s）" % [label, path, _paths(result.errors)])
	_check_error_text(r, label, result)


func _check_error_text(r, label: String, result: ConfigResult) -> void:
	for error in result.errors:
		r.check(not error.message.is_empty(),
			"%s：%s 的 message 不能为空" % [label, error.code])
		r.check(not error.fix_hint.is_empty(),
			"%s：%s 的 fix_hint 不能为空" % [label, error.code])
	for warning in result.warnings:
		r.check(not warning.message.is_empty(),
			"%s：warning %s 的 message 不能为空" % [label, warning.code])
		r.check(not warning.fix_hint.is_empty(),
			"%s：warning %s 的 fix_hint 不能为空" % [label, warning.code])


func _has_path(errors: Array[ConfigError], path: String) -> bool:
	for error in errors:
		if error.json_path == path:
			return true
	return false


func _count_code(errors: Array[ConfigError], code: StringName) -> int:
	var count := 0
	for error in errors:
		if error.code == code:
			count += 1
	return count


func _codes(result: ConfigResult) -> String:
	var codes := PackedStringArray()
	for error in result.errors:
		codes.append(str(error.code))
	for warning in result.warnings:
		codes.append(str(warning.code))
	return ", ".join(codes)


func _paths(errors: Array[ConfigError]) -> String:
	var paths := PackedStringArray()
	for error in errors:
		paths.append(error.json_path)
	return ", ".join(paths)


func _text(result: ConfigResult) -> String:
	if result.errors.is_empty() and result.warnings.is_empty():
		return "无问题"
	return result.to_text()


func _has_code(data: Dictionary, code: StringName) -> bool:
	return ConfigValidator.validate(data, "<test>").has_code(code)
