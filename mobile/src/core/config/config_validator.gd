class_name ConfigValidator
extends RefCounted

## 配置校验：把「坏配置」变成一份可直接渲染的 ConfigError 列表。
##
## 契约：
## - 永远不因输入而崩溃：每个字段先 typeof 再转换，绝不做无守卫的类型强转。
## - 永远给出可操作的中文错误：路径 + 实际值 + 修复建议；一条 ConfigError 自带全部
##   渲染信息，错误屏不需要二次解释。
## - 收集式：同一个 Array[ConfigError] 沿调用链传下去（GDScript 数组是引用类型），
##   一个坏字段不会让其余检查消失。
##
## 本类只做纯计算：不读文件、不打印、不 push_error、不 assert。错误只走返回值。

const ROOT_PATH := "$"
const KINDS: Array[String] = ["arc", "sequence", "taps"]
const BUTTON_MODES: Array[String] = ["all", "any"]
const INVERT_KEYS: Array[String] = ["ls_x", "ls_y", "rs_x", "rs_y"]
const RUMBLE_BACKENDS: Array[String] = ["auto", "pygame", "sdl2", "xinput", "none"]
## 与 desktop/padskills/detectors.py:154-160 的接受面逐字一致：多一个写法就是多一套词汇表。
const ARC_DIRECTIONS: Array[String] = [
	"any", "cw", "clockwise", "ccw", "counterclockwise", "顺时针", "逆时针",
]


## 把已解析的 JSON 数据变成 AppConfig；只要有任何 error，config 保持 null。
static func validate(data: Variant, source_path := "") -> ConfigResult:
	var result := ConfigResult.new()
	result.source_path = source_path
	if typeof(data) != TYPE_DICTIONARY:
		_fail(result.errors, ROOT_PATH, &"root_not_object",
			"配置文件根节点必须是 JSON 对象，收到 %s" % type_string(typeof(data)),
			"用 { } 把整份配置包住；最外层不能是数组、字符串或 null。")
		return result

	var root: Dictionary = data
	var app := AppConfig.new()
	app.skills = _validate_skills(root.get("skills"), result.errors)
	app.input = _validate_input(root.get("input"), ROOT_PATH + ".input", result.errors)
	app.rumble = _validate_rumble(root.get("rumble"), ROOT_PATH + ".rumble", result.errors)
	if result.errors.is_empty():
		result.config = app
	return result


# ---------------------------------------------------------------------------
# 结构
# ---------------------------------------------------------------------------

static func _validate_skills(raw: Variant, out: Array[ConfigError]) -> Array[Skill]:
	var skills: Array[Skill] = []
	if typeof(raw) != TYPE_ARRAY:
		_fail(out, ROOT_PATH + ".skills", &"skills_not_array",
			"skills 必须是数组，收到 %s" % type_string(typeof(raw)),
			"把每个动作写进 skills 数组：[ { ... }, { ... } ]。")
		return skills
	var items: Array = raw
	if items.is_empty():
		_fail(out, ROOT_PATH + ".skills", &"skills_empty",
			"skills 数组是空的，至少要有 1 个动作",
			"把要练的动作写进 skills 数组，或从默认配置里复制一段。")
		return skills
	for index in items.size():
		var skill := _validate_skill(items[index], index, out)
		if skill != null:
			skills.append(skill)
	_report_duplicate_names(skills, out)
	return skills


static func _validate_skill(raw: Variant, index: int, out: Array[ConfigError]) -> Skill:
	var path := "skills[%d]" % index
	if typeof(raw) != TYPE_DICTIONARY:
		_fail(out, path, &"skill_not_object",
			"每个动作必须是 JSON 对象，收到 %s" % type_string(typeof(raw)),
			"用 { } 包住一个动作；动作之间用逗号分隔。")
		return null
	var dict: Dictionary = raw

	var kind := ""
	var raw_kind: Variant = dict.get("type", null)
	if typeof(raw_kind) == TYPE_STRING:
		kind = str(raw_kind).strip_edges().to_lower()
	if not KINDS.has(kind):
		_fail(out, path + ".type", &"skill_type_invalid",
			"type 必须是 'arc'、'sequence' 或 'taps'，收到 %s" % _preview(raw_kind),
			"改成三种之一；拼写和大小写都要对。")
		# 只跳过依赖 type 的子树：外层继续下一个动作。
		return null

	var skill := Skill.new()
	skill.kind = StringName(kind)
	skill.raw = dict

	var skill_name := "未命名动作 #%d" % (index + 1)
	if dict.has("name"):
		var raw_name: Variant = dict["name"]
		if typeof(raw_name) != TYPE_STRING:
			_fail(out, path + ".name", &"string_expected",
				"name 必须是字符串，收到 %s" % _preview(raw_name),
				"给动作起一个名字，例如 \"马赛回旋 Roulette\"。")
		else:
			skill_name = str(raw_name)
	skill.name = skill_name

	skill.enabled = _read_boolean(dict, "enabled", true, path, out)
	skill.relative_to_ls = _read_boolean(dict, "relative_to_ls", false, path, out)
	skill.cooldown_ms = int(_read_number(dict, "cooldown_ms", 400.0, path, out))
	skill.required_buttons = _read_required_buttons(dict, path, out)
	skill.button_mode = _read_button_mode(dict, path, out)

	# params 缺省或显式为 null 都视为 {}（与 Python 的 `raw.get("params") or {}` 一致）。
	# params 不是对象时只跳过 params.* 检查，技能级字段照查。
	var params: Dictionary = {}
	var params_ok := true
	if dict.has("params"):
		var raw_params: Variant = dict["params"]
		if typeof(raw_params) == TYPE_NIL:
			params = {}
		elif typeof(raw_params) != TYPE_DICTIONARY:
			params_ok = false
			_fail(out, path + ".params", &"params_not_object",
				"params 必须是对象，收到 %s" % _preview(raw_params),
				"把该动作的参数写进 { }；没有参数就写 {}。")
		else:
			# 深拷贝：校验过程会规范化 modifier_options，不能改到调用方的输入字典。
			var params_dict: Dictionary = raw_params
			params = params_dict.duplicate(true)
	skill.params = params

	if params_ok:
		if kind == "sequence":
			_validate_sequence(skill, path, out)
		elif kind == "arc":
			_validate_arc(skill, path, out)
		elif kind == "taps":
			_validate_taps(skill, path, out)
		_check_modifier_cross(skill, path, out)

	skill.pattern = _read_pattern(dict.get("rumble"), path, out)
	return skill


# ---------------------------------------------------------------------------
# sequence / arc / taps
# ---------------------------------------------------------------------------

static func _validate_sequence(skill: Skill, path: String, out: Array[ConfigError]) -> void:
	var params_path := path + ".params"
	var raw_steps: Variant = skill.params.get("steps", null)
	var parsed: Array[Step] = []
	var steps_ok := typeof(raw_steps) == TYPE_ARRAY
	if not steps_ok:
		_fail(out, params_path + ".steps", &"steps_empty",
			"sequence 类型的 params.steps 必须是非空数组，收到 %s" % _preview(raw_steps),
			"写方向列表，例如 [\"forward\", \"back\"]。")
	else:
		var steps: Array = raw_steps
		if steps.is_empty():
			steps_ok = false
			_fail(out, params_path + ".steps", &"steps_empty",
				"sequence 类型的 params.steps 必须是非空数组",
				"写方向列表，例如 [\"forward\", \"back\"]。")
		else:
			for index in steps.size():
				var step := _parse_step(steps[index], "%s.steps[%d]" % [params_path, index], out)
				if step != null:
					parsed.append(step)

	var min_dur := _read_number(skill.params, "min_duration_ms", 300.0, params_path, out)
	var max_dur := _read_number(skill.params, "max_duration_ms", 700.0, params_path, out)
	if max_dur <= min_dur:
		_fail(out, params_path + ".max_duration_ms", &"max_not_greater_than_min",
			"max_duration_ms (%s ms) 必须大于 min_duration_ms (%s ms)"
				% [_fmt(max_dur), _fmt(min_dur)],
			"把 max_duration_ms 调大，或把 min_duration_ms 调小。")
	# 各步保持时间之和必须小于总时长窗口，否则这个动作永远不可能触发。
	# 只有全部步骤都解析成功时，这个和不完整才不成立，跳过以免报出假错误。
	if steps_ok and parsed.size() == (raw_steps as Array).size():
		var total_hold := 0.0
		for step in parsed:
			total_hold += step.hold_ms
		if total_hold >= max_dur:
			_fail(out, params_path + ".max_duration_ms", &"hold_sum_exceeds_max",
				"各步骤 hold_ms 合计 %s ms 已经不小于 max_duration_ms (%s ms)，这个动作永远无法触发"
					% [_fmt(total_hold), _fmt(max_dur)],
				"把 max_duration_ms 调大，或缩短某一步的 hold_ms。")
	if skill.params.has("require_neutral_between_steps"):
		var raw_neutral: Variant = skill.params["require_neutral_between_steps"]
		if typeof(raw_neutral) != TYPE_BOOL:
			_fail(out, params_path + ".require_neutral_between_steps", &"bool_expected",
				"require_neutral_between_steps 必须是 true 或 false，收到 %s"
					% _preview(raw_neutral),
				"写 true 或 false（不要加引号）。")
	_validate_common_timing(skill.params, params_path, out)


## 解析一个序列步骤：字符串 / 数组 / 字典三种写法。
## 错误路径统一停在步骤本身（与 Python 的 `steps[i]: ...` 一致），便于定位。
static func _parse_step(value: Variant, path: String, out: Array[ConfigError]) -> Step:
	if typeof(value) == TYPE_DICTIONARY:
		var dict: Dictionary = value
		var direction: Variant = null
		if dict.has("direction"):
			direction = dict["direction"]
		elif dict.has("dir"):
			direction = dict["dir"]
		else:
			_fail(out, path, &"step_direction_missing",
				"步骤缺少 direction 字段，收到 %s" % _preview(value),
				"写成 {\"direction\": \"forward\"} 或 {\"direction\": [\"left\", \"right\"], \"hold_ms\": 350}。")
			return null
		var hold_ms := 0.0
		if dict.has("hold_ms"):
			var raw_hold: Variant = dict["hold_ms"]
			if not _is_number(raw_hold):
				_fail(out, path + ".hold_ms", &"step_hold_not_number",
					"步骤的 hold_ms 必须是数字，收到 %s" % _preview(raw_hold),
					"写成毫秒数，例如 350；不要写字符串或 null。")
			else:
				hold_ms = float(raw_hold)
				if hold_ms < 0.0:
					_fail(out, path + ".hold_ms", &"step_hold_negative",
						"步骤的 hold_ms 不能是负数，收到 %s" % _preview(raw_hold),
						"改成 0 或更大的毫秒数。")
					hold_ms = 0.0
		var inner := _parse_step(direction, path, out)
		if inner == null:
			return null
		return Step.new(inner.angles, hold_ms)

	var group: Array = []
	if typeof(value) == TYPE_ARRAY:
		group = value
	else:
		group = [value]
	if group.is_empty():
		_fail(out, path, &"step_group_empty",
			"步骤不能是空数组", "写至少一个方向，例如 \"forward\" 或 [\"left\", \"right\"]。")
		return null

	var angles: Array[float] = []
	for item in group:
		var angle: Variant = _read_direction(item, path, out)
		if angle != null:
			angles.append(float(angle))
	if angles.size() != group.size():
		return null
	return Step.new(angles, 0.0)


static func _validate_arc(skill: Skill, path: String, out: Array[ConfigError]) -> void:
	var params_path := path + ".params"
	var lo := _read_number(skill.params, "min_angle", 150.0, params_path, out)
	var hi := _read_number(skill.params, "max_angle", 220.0, params_path, out)
	if hi <= lo:
		_fail(out, params_path + ".max_angle", &"max_not_greater_than_min",
			"max_angle (%s°) 必须大于 min_angle (%s°)" % [_fmt(hi), _fmt(lo)],
			"把 max_angle 调大，或把 min_angle 调小。")

	var min_dur := _read_number(skill.params, "min_duration_ms", 300.0, params_path, out)
	var max_dur := _read_number(skill.params, "max_duration_ms", 700.0, params_path, out)
	if max_dur <= min_dur:
		_fail(out, params_path + ".max_duration_ms", &"max_not_greater_than_min",
			"max_duration_ms (%s ms) 必须大于 min_duration_ms (%s ms)"
				% [_fmt(max_dur), _fmt(min_dur)],
			"把 max_duration_ms 调大，或把 min_duration_ms 调小。")
	_validate_common_timing(skill.params, params_path, out)

	# start_angle 必须是标量：数组写法在 Python 里会通过 parse_config、到构造
	# ArcDetector 才崩（resolve_direction(list) 的 TypeError），移动端在校验期就拒绝。
	if skill.params.has("start_angle"):
		var raw_start: Variant = skill.params["start_angle"]
		if typeof(raw_start) == TYPE_NIL:
			pass  # null = 不限制起点
		elif typeof(raw_start) == TYPE_ARRAY or typeof(raw_start) == TYPE_DICTIONARY:
			_fail(out, params_path + ".start_angle", &"start_angle_not_scalar",
				"start_angle 只能写一个方向，收到 %s" % _preview(raw_start),
				"改成单个方向名或角度数字，例如 180 或 \"back\"；这里不接受数组。")
		else:
			_read_direction(raw_start, params_path + ".start_angle", out)

	for key in ["end_angle", "end_angles"]:
		if not skill.params.has(key):
			continue
		var raw_end: Variant = skill.params[key]
		if typeof(raw_end) == TYPE_NIL:
			continue  # null = 不限制终点
		var values: Array = []
		if typeof(raw_end) == TYPE_ARRAY:
			values = raw_end
		else:
			values = [raw_end]
		if values.is_empty():
			_fail(out, params_path + "." + key, &"step_group_empty",
				"%s 不能是空数组" % key,
				"写至少一个终点方向，或写 null 表示不限制。")
			continue
		for value in values:
			_read_direction(value, params_path + "." + key, out)

	# 旋转方向是 Python 唯一静默落到 any 的位置（detectors.py:154-160）；移动端故意
	# 严格化：未知值必须在启动前报出来，而不是「看起来能练、永远不触发」。
	if skill.params.has("direction"):
		var raw_direction: Variant = skill.params["direction"]
		var direction := ""
		if typeof(raw_direction) == TYPE_STRING:
			direction = str(raw_direction).strip_edges().to_lower()
		if not ARC_DIRECTIONS.has(direction):
			_fail(out, params_path + ".direction", &"direction_unknown",
				"params.direction 只接受 any / cw / ccw / clockwise / counterclockwise / 顺时针 / 逆时针，收到 %s"
					% _preview(raw_direction),
				"改成上面七种写法之一；写 \"any\" 表示不限制旋转方向。")


static func _validate_taps(skill: Skill, path: String, out: Array[ConfigError]) -> void:
	var params_path := path + ".params"
	var raw_button: Variant = skill.params.get("button", "X")
	if Buttons.canonical(raw_button).is_empty():
		_fail(out, params_path + ".button", &"button_unknown",
			"无法识别的按键名 %s。可用规范名: %s"
				% [_preview(raw_button), ", ".join(PackedStringArray(Buttons.CANONICAL))],
			"改成规范名或别名（A/B/X/Y、LB/RB、L1/R2 等）。")

	var min_i := _read_number(skill.params, "min_interval_ms", 400.0, params_path, out)
	var max_i := _read_number(skill.params, "max_interval_ms", 600.0, params_path, out)
	if min_i < 0.0:
		_fail(out, params_path + ".min_interval_ms", &"negative_value",
			"min_interval_ms 不能是负数，收到 %s" % _fmt(min_i),
			"改成 0 或更大的毫秒数。")
	if max_i <= min_i:
		_fail(out, params_path + ".max_interval_ms", &"max_not_greater_than_min",
			"max_interval_ms (%s ms) 必须大于 min_interval_ms (%s ms)"
				% [_fmt(max_i), _fmt(min_i)],
			"把 max_interval_ms 调大，或把 min_interval_ms 调小。")

	if skill.params.has("modifier_options"):
		var raw_options: Variant = skill.params["modifier_options"]
		if typeof(raw_options) != TYPE_ARRAY or (raw_options as Array).is_empty():
			_fail(out, params_path + ".modifier_options", &"modifier_options_invalid",
				"params.modifier_options 必须是非空数组，收到 %s" % _preview(raw_options),
				"写可切换的修饰键，例如 [\"RB\", \"RT\"]；不用这个功能就删掉该字段。")
		else:
			var options: Array[String] = []
			var seen: Dictionary = {}
			var options_ok := true
			for value in (raw_options as Array):
				var canonical := Buttons.canonical(value)
				if canonical.is_empty():
					options_ok = false
					_fail(out, params_path + ".modifier_options", &"button_unknown",
						"modifier_options 里有无法识别的按键 %s" % _preview(value),
						"改成规范名或别名，例如 \"RB\" / \"RT\"。")
					continue
				if seen.has(canonical):
					_fail(out, params_path + ".modifier_options", &"modifier_duplicate",
						"modifier_options 里 %s 重复出现；规范化之后必须是唯一按键" % canonical,
						"删掉重复项；RB 与 rb 会被归一成同一个键。")
					continue
				seen[canonical] = true
				options.append(canonical)
			if options_ok and not options.is_empty():
				skill.params["modifier_options"] = options

	_validate_common_timing(skill.params, params_path, out)


## 修饰键交叉检查（desktop/padskills/config.py:655-670）：
## 有 modifier_options 就必须有 required_button，且 required_button 必须在选项里。
static func _check_modifier_cross(skill: Skill, path: String, out: Array[ConfigError]) -> void:
	if not skill.params.has("modifier_options"):
		return
	var raw_options: Variant = skill.params["modifier_options"]
	if typeof(raw_options) != TYPE_ARRAY:
		return
	var options: Array = raw_options
	if options.is_empty():
		return
	if skill.required_buttons.is_empty():
		_fail(out, path + ".params.modifier_options", &"modifier_requires_required_button",
			"配了 modifier_options 就必须同时写 required_button，否则不知道默认按住哪个键",
			"在动作顶层写 \"required_button\": \"RB\"，或删掉 modifier_options。")
		return
	for required in skill.required_buttons:
		if not options.has(required):
			_fail(out, path + ".required_button", &"required_button_not_in_options",
				"required_button %s 不在 modifier_options %s 里"
					% [_preview(required), _preview(options)],
				"把 %s 加进 modifier_options，或把 required_button 改成选项里的键。" % required)
			break


static func _validate_common_timing(params: Dictionary, params_path: String,
		out: Array[ConfigError]) -> void:
	for key in ["idle_timeout_ms", "release_hold_ms"]:
		if not params.has(key) or not _is_number(params[key]):
			continue
		var value := float(params[key])
		if key == "idle_timeout_ms" and value == 0.0:
			_fail(out, params_path + ".idle_timeout_ms", &"must_be_positive",
				"idle_timeout_ms 必须大于 0", "改成大于 0 的毫秒数，例如 250。")
		elif value < 0.0:
			_fail(out, params_path + "." + key, &"negative_value",
				"%s 不能是负数，收到 %s" % [key, _fmt(value)],
				"改成 0 或更大的毫秒数。")
	if params.has("motion_min_delta_deg") and _is_number(params["motion_min_delta_deg"]):
		var delta := float(params["motion_min_delta_deg"])
		if delta <= 0.0:
			_fail(out, params_path + ".motion_min_delta_deg", &"must_be_positive",
				"motion_min_delta_deg 必须大于 0，收到 %s" % _fmt(delta),
				"改成大于 0 的角度，例如 2。")
	# 其余字段（tolerance_deg / enter_threshold 等）由具体检测器按自己的语义消费，
	# 本阶段不在这里重复定义阈值 —— 配置校验只拦住「不可能工作」的值。


# ---------------------------------------------------------------------------
# input / rumble
# ---------------------------------------------------------------------------

static func _validate_input(raw: Variant, path: String, out: Array[ConfigError]) -> InputConfig:
	var cfg := InputConfig.new()
	if typeof(raw) == TYPE_NIL:
		return cfg
	if typeof(raw) != TYPE_DICTIONARY:
		_fail(out, path, &"input_not_object",
			"input 必须是对象，收到 %s" % _preview(raw),
			"把输入参数写进 { }；全部用默认值就写 {} 或直接删掉。")
		return cfg
	var dict: Dictionary = raw

	cfg.deadzone = _clamp01_field(dict, "deadzone", cfg.deadzone, path, out)
	cfg.ls_facing_threshold = _clamp01_field(
		dict, "ls_facing_threshold", cfg.ls_facing_threshold, path, out)
	cfg.trigger_threshold = _clamp01_field(
		dict, "trigger_threshold", cfg.trigger_threshold, path, out)
	cfg.initial_facing_deg = _read_number(
		dict, "initial_facing_deg", cfg.initial_facing_deg, path, out)
	cfg.poll_hz = int(_read_number(dict, "poll_hz", float(cfg.poll_hz), path, out))
	cfg.joystick_index = int(_read_number(
		dict, "joystick_index", float(cfg.joystick_index), path, out))
	cfg.calibration_ms = int(_read_number(
		dict, "calibration_ms", float(cfg.calibration_ms), path, out))
	cfg.idle_reset_ms = int(_read_number(
		dict, "idle_reset_ms", float(cfg.idle_reset_ms), path, out))
	cfg.gesture_release_ms = int(_read_number(
		dict, "gesture_release_ms", float(cfg.gesture_release_ms), path, out))

	if dict.has("axis_layout"):
		var layout: Variant = dict["axis_layout"]
		if typeof(layout) != TYPE_NIL and typeof(layout) != TYPE_DICTIONARY:
			_fail(out, path + ".axis_layout", &"axis_layout_not_object",
				"input.axis_layout 必须是对象或 null，收到 %s" % _preview(layout),
				"写 {\"ls_x\": 0, \"ls_y\": 1} 这样的映射，或写 null 表示自动推断。")
		else:
			cfg.axis_layout = layout

	if dict.has("invert"):
		var raw_invert: Variant = dict["invert"]
		if typeof(raw_invert) == TYPE_NIL:
			pass
		elif typeof(raw_invert) != TYPE_DICTIONARY:
			_fail(out, path + ".invert", &"invert_not_object",
				"input.invert 必须是对象或 null，收到 %s" % _preview(raw_invert),
				"写 {\"rs_y\": true} 这样的对象，或写 null。")
		else:
			var invert: Dictionary = raw_invert
			var normalized: Dictionary = {}
			for key in invert.keys():
				var name := str(key).strip_edges().to_lower()
				if not INVERT_KEYS.has(name):
					_fail(out, path + ".invert", &"invert_key_invalid",
						"input.invert 的键只能是 ls_x / ls_y / rs_x / rs_y，收到 %s"
							% _preview(key),
						"把键改成四个轴名之一。")
					continue
				var value: Variant = invert[key]
				if typeof(value) != TYPE_BOOL:
					_fail(out, path + ".invert." + name, &"invert_value_not_bool",
						"input.invert.%s 必须是 true / false，收到 %s"
							% [name, _preview(value)],
						"写 true 或 false（不要加引号）。")
					continue
				var flag: bool = value
				normalized[name] = flag
			cfg.invert = normalized

	if dict.has("button_names"):
		var names: Variant = dict["button_names"]
		if typeof(names) != TYPE_NIL and typeof(names) != TYPE_DICTIONARY:
			_fail(out, path + ".button_names", &"button_names_not_object",
				"input.button_names 必须是对象或 null，收到 %s" % _preview(names),
				"写 {\"A\": 0, \"B\": 1} 这样的映射，或写 null 表示自动推断。")
		else:
			cfg.button_names = names

	return cfg


static func _validate_rumble(raw: Variant, path: String, out: Array[ConfigError]) -> RumbleConfig:
	var cfg := RumbleConfig.new()
	if typeof(raw) == TYPE_NIL:
		return cfg
	if typeof(raw) != TYPE_DICTIONARY:
		_fail(out, path, &"rumble_invalid",
			"rumble 必须是对象，收到 %s" % _preview(raw),
			"把震动参数写进 { }；或直接删掉该字段使用默认值。")
		return cfg
	var dict: Dictionary = raw

	if dict.has("enabled"):
		var raw_enabled: Variant = dict["enabled"]
		if typeof(raw_enabled) != TYPE_BOOL:
			_fail(out, path + ".enabled", &"bool_expected",
				"enabled 必须是 true 或 false，收到 %s" % _preview(raw_enabled),
				"写 true 或 false（不要加引号）。")
		else:
			var enabled_value: bool = raw_enabled
			cfg.enabled = enabled_value
	if dict.has("startup_test"):
		var raw_startup: Variant = dict["startup_test"]
		if typeof(raw_startup) != TYPE_BOOL:
			_fail(out, path + ".startup_test", &"bool_expected",
				"startup_test 必须是 true 或 false，收到 %s" % _preview(raw_startup),
				"写 true 或 false（不要加引号）。")
		else:
			var startup_value: bool = raw_startup
			cfg.startup_test = startup_value

	if dict.has("backend"):
		var raw_backend: Variant = dict["backend"]
		var backend := ""
		if typeof(raw_backend) == TYPE_STRING:
			backend = str(raw_backend).strip_edges().to_lower()
		if not RUMBLE_BACKENDS.has(backend):
			_fail(out, path + ".backend", &"rumble_backend_invalid",
				"rumble.backend 只能是 auto / pygame / sdl2 / xinput / none，收到 %s"
					% _preview(raw_backend),
				"改成五种之一；移动端没有 pygame/xinput 后端，但配置仍要能原样读入。")
		else:
			cfg.backend = StringName(backend)

	cfg.startup_test_strength = _clamp01_field(
		dict, "startup_test_strength", cfg.startup_test_strength, path, out)
	cfg.startup_test_ms = int(_read_number(
		dict, "startup_test_ms", float(cfg.startup_test_ms), path, out))

	return cfg


# ---------------------------------------------------------------------------
# 技能级 rumble
# ---------------------------------------------------------------------------

## null → 一条默认 Pulse；单对象 / 数组 / {pattern: [...]} 三种形状归一。
static func _read_pattern(raw: Variant, path: String, out: Array[ConfigError]) -> Array[Pulse]:
	var pulses: Array[Pulse] = []
	if typeof(raw) == TYPE_NIL:
		pulses.append(Pulse.new())
		return pulses

	var items: Variant = null
	if typeof(raw) == TYPE_DICTIONARY:
		var dict: Dictionary = raw
		if dict.has("pattern"):
			items = dict["pattern"]
		else:
			items = [raw]
	elif typeof(raw) == TYPE_ARRAY:
		items = raw
	else:
		_fail(out, path + ".rumble", &"rumble_invalid",
			"动作的 rumble 必须是对象、数组或 {pattern: [...]}，收到 %s" % _preview(raw),
			"写 {low, high, duration_ms}，或把这些对象放进数组。")
		pulses.append(Pulse.new())
		return pulses

	var list: Array = []
	if typeof(items) == TYPE_ARRAY:
		list = items
	if list.is_empty():
		_fail(out, path + ".rumble.pattern", &"rumble_pattern_empty",
			"rumble.pattern 必须是非空数组",
			"至少写一条震动，例如 [{\"low\": 0.8, \"duration_ms\": 120}]。")
		pulses.append(Pulse.new())
		return pulses

	for index in list.size():
		var item: Variant = list[index]
		var item_path := "%s.rumble.pattern[%d]" % [path, index]
		if typeof(item) != TYPE_DICTIONARY:
			_fail(out, item_path, &"rumble_item_not_object",
				"震动项必须是对象，收到 %s" % _preview(item),
				"写成 {\"low\": 0.8, \"high\": 0.0, \"duration_ms\": 120}。")
			continue
		var item_dict: Dictionary = item
		var low := _clamp01_field(item_dict, "low", 0.8, item_path, out)
		var high := _clamp01_field(item_dict, "high", 0.0, item_path, out)
		var duration := int(_read_number(item_dict, "duration_ms", 120.0, item_path, out))
		var gap := int(_read_number(item_dict, "gap_ms", 0.0, item_path, out))
		pulses.append(Pulse.new(low, high, duration, gap))
	if pulses.is_empty():
		pulses.append(Pulse.new())
	return pulses


# ---------------------------------------------------------------------------
# 重复名字
# ---------------------------------------------------------------------------

static func _report_duplicate_names(skills: Array[Skill], out: Array[ConfigError]) -> void:
	var first_index: Dictionary = {}
	for index in skills.size():
		var skill_name: String = skills[index].name
		if not first_index.has(skill_name):
			first_index[skill_name] = index
			continue
		var first: int = first_index[skill_name]
		_fail(out, "skills[%d].name" % index, &"duplicate_skill_name",
			"动作名称 %s 与 skills[%d] 重复；名称用于日志区分，必须唯一"
				% [_preview(skill_name), first],
			"改成唯一的名称，例如加上左右脚或版本后缀。")


# ---------------------------------------------------------------------------
# 基础读写
# ---------------------------------------------------------------------------

static func _read_boolean(dict: Dictionary, key: String, fallback: bool,
		path: String, out: Array[ConfigError]) -> bool:
	if not dict.has(key):
		return fallback
	var raw: Variant = dict[key]
	if typeof(raw) != TYPE_BOOL:
		_fail(out, path + "." + key, &"bool_expected",
			"%s 必须是 true 或 false，收到 %s" % [key, _preview(raw)],
			"写 true 或 false（不要加引号）；字符串 \"false\" 不是布尔值。")
		return fallback
	var value: bool = raw
	return value


## 数值字段：JSON 的 1 解析成 float，所以 TYPE_INT 与 TYPE_FLOAT 都接受。
static func _read_number(dict: Dictionary, key: String, fallback: float,
		path: String, out: Array[ConfigError]) -> float:
	if not dict.has(key):
		return fallback
	var raw: Variant = dict[key]
	if not _is_number(raw):
		_fail(out, path + "." + key, &"number_expected",
			"%s 必须是数字，收到 %s" % [key, _preview(raw)],
			"写成不带引号的数字，例如 250；不要写 null、字符串或 true/false。")
		return fallback
	return float(raw)


## 0.0 ~ 1.0 的比例字段：类型错是 number_expected，越界是 out_of_range（不可截断）。
static func _clamp01_field(dict: Dictionary, key: String, fallback: float,
		path: String, out: Array[ConfigError]) -> float:
	if not dict.has(key):
		return fallback
	var raw: Variant = dict[key]
	if not _is_number(raw):
		_fail(out, path + "." + key, &"number_expected",
			"%s 必须是数字，收到 %s" % [key, _preview(raw)],
			"写成不带引号的数字，例如 0.35。")
		return fallback
	var value := float(raw)
	if value < 0.0 or value > 1.0:
		_fail(out, path + "." + key, &"out_of_range",
			"%s 必须在 0.0~1.0 之间，收到 %s" % [key, _fmt(value)],
			"改成 0.0 到 1.0 之间的数；这是比例，不是百分比。")
		return fallback
	return value


## 方向值 → 角度（float）；失败返回 null。布尔单独给 direction_is_bool。
static func _read_direction(value: Variant, path: String,
		out: Array[ConfigError]) -> Variant:
	if typeof(value) == TYPE_BOOL:
		_fail(out, path, &"direction_is_bool",
			"方向不能是 true / false，收到 %s" % _preview(value),
			"写方向名或角度数字，例如 \"forward\" / 0 / 90。")
		return null
	var angle: Variant = DirectionTable.resolve(value)
	if angle == null:
		_fail(out, path, &"direction_unknown",
			"无法识别的方向 %s。可用名称：up/forward、right、down/back、left、四个斜向，也可以直接写角度数字"
				% _preview(value),
			"改成方向名或角度数字（0 / 90 / 180 / 270），或参考配置文件里的 _readme。")
		return null
	return angle


static func _read_required_buttons(dict: Dictionary, path: String,
		out: Array[ConfigError]) -> Array[String]:
	var names: Array[String] = []
	var field := ""
	var raw: Variant = null
	if dict.has("required_button"):
		field = "required_button"
		raw = dict["required_button"]
	elif dict.has("required_buttons"):
		field = "required_buttons"
		raw = dict["required_buttons"]
	else:
		return names
	# null 或缺失是合法的「不需要修饰键」：真实配置 5 个动作里有 3 个这样写，
	# 绝不能在这里报 button_unknown。
	if typeof(raw) == TYPE_NIL:
		return names

	var values: Array = []
	if typeof(raw) == TYPE_ARRAY:
		values = raw
	elif typeof(raw) == TYPE_STRING:
		values = [raw]
	else:
		_fail(out, path + "." + field, &"button_unknown",
			"%s 必须是按键名字符串或字符串数组，收到 %s" % [field, _preview(raw)],
			"写 \"LB\" 这样的规范名，或写 null 表示不需要修饰键。")
		return names

	for value in values:
		if typeof(value) == TYPE_STRING and str(value).strip_edges().is_empty():
			# 与 Python `_parse_required_buttons` 的 `if str(v).strip()` 一致：空串视为没写。
			continue
		var canonical := Buttons.canonical(value)
		if canonical.is_empty():
			_fail(out, path + "." + field, &"button_unknown",
				"无法识别的按键名 %s。可用规范名: %s"
					% [_preview(value), ", ".join(PackedStringArray(Buttons.CANONICAL))],
				"改成规范名或别名（L1/R1/R2/TRIANGLE 等），或写 null 表示不需要修饰键。")
			continue
		names.append(canonical)
	return names


static func _read_button_mode(dict: Dictionary, path: String,
		out: Array[ConfigError]) -> StringName:
	if not dict.has("button_mode"):
		return Skill.MODE_ALL
	var raw: Variant = dict["button_mode"]
	if typeof(raw) == TYPE_NIL:
		return Skill.MODE_ALL
	if typeof(raw) != TYPE_STRING:
		_fail(out, path + ".button_mode", &"button_mode_invalid",
			"button_mode 只能是 'all' 或 'any'，收到 %s" % _preview(raw),
			"写 \"all\"（全部按住）或 \"any\"（任一按住）。")
		return Skill.MODE_ALL
	var mode := str(raw).strip_edges().to_lower()
	if not BUTTON_MODES.has(mode):
		_fail(out, path + ".button_mode", &"button_mode_invalid",
			"button_mode 只能是 'all' 或 'any'，收到 %s" % _preview(raw),
			"写 \"all\"（全部按住）或 \"any\"（任一按住）。")
		return Skill.MODE_ALL
	return StringName(mode)


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


static func _fail(out: Array[ConfigError], path: String, code: StringName,
		message: String, fix_hint: String) -> void:
	out.append(ConfigError.new(path, code, message, fix_hint))


## 把任意 JSON 值变成可读短串（含实际值），错误消息里必须让用户看到收到的是什么。
static func _preview(value: Variant) -> String:
	return JSON.stringify(value)


## 数值消息里的整数不带 .0：用户写 600，错误里就不该显示 600.0。
static func _fmt(value: float) -> String:
	if value == floorf(value):
		return str(int(value))
	return "%.2f" % value
