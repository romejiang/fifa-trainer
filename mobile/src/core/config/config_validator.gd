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
	# 本任务只搭骨架：input / rumble 的字段级规则在后续任务补齐，此处先取默认值。
	if result.errors.is_empty():
		result.config = app
	return result


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

	skill.enabled = _read_bool(dict, "enabled", true, path, out)
	skill.relative_to_ls = _read_bool(dict, "relative_to_ls", false, path, out)
	skill.cooldown_ms = int(_read_number(dict, "cooldown_ms", 400.0, path, out))
	skill.required_buttons = _read_required_buttons(dict, path, out)
	skill.button_mode = _read_button_mode(dict, path, out)
	skill.pattern = _read_pattern(dict.get("rumble"), path, out)
	skill.params = _read_params(dict, path, out)
	return skill


## params 缺省或显式为 null 都视为 {}（与 Python 的 `raw.get("params") or {}` 一致）。
static func _read_params(dict: Dictionary, path: String, out: Array[ConfigError]) -> Dictionary:
	if not dict.has("params"):
		return {}
	var raw: Variant = dict["params"]
	if typeof(raw) == TYPE_NIL:
		return {}
	if typeof(raw) != TYPE_DICTIONARY:
		_fail(out, path + ".params", &"params_not_object",
			"params 必须是对象，收到 %s" % _preview(raw),
			"把该动作的参数写进 { }；没有参数就写 {}。")
		return {}
	var params: Dictionary = raw
	# 深拷贝：校验过程会规范化 modifier_options 等字段，不能改到调用方的输入字典。
	return params.duplicate(true)


static func _read_bool(dict: Dictionary, key: String, fallback: bool,
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
	if typeof(raw) != TYPE_INT and typeof(raw) != TYPE_FLOAT:
		_fail(out, path + "." + key, &"number_expected",
			"%s 必须是数字，收到 %s" % [key, _preview(raw)],
			"写成不带引号的数字，例如 250；不要写 null、字符串或 true/false。")
		return fallback
	return float(raw)


## required_button / required_buttons：null 或缺失是合法的「不需要修饰键」。
## 真实配置 5 个动作里有 3 个写 "required_button": null —— 这里绝不能报 button_unknown。
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


## 技能级 rumble：null → 一条默认 Pulse；单对象 / 数组 / {pattern: [...]} 三种形状归一。
## 本任务只填默认值；low/high/duration_ms/gap_ms 的类型与范围在后续任务补齐。
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
		if typeof(item) != TYPE_DICTIONARY:
			_fail(out, "%s.rumble.pattern[%d]" % [path, index], &"rumble_item_not_object",
				"震动项必须是对象，收到 %s" % _preview(item),
				"写成 {\"low\": 0.8, \"high\": 0.0, \"duration_ms\": 120}。")
			continue
		pulses.append(Pulse.new())
	if pulses.is_empty():
		pulses.append(Pulse.new())
	return pulses


## 重复 name 在收集完所有 skill 之后统一统计：每一处重复各报一条，
## 消息里点名第一次出现的位置，用户不需要自己数。
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


static func _fail(out: Array[ConfigError], path: String, code: StringName,
		message: String, fix_hint: String) -> void:
	out.append(ConfigError.new(path, code, message, fix_hint))


## 把任意 JSON 值变成可读短串（含实际值），错误消息里必须让用户看到收到的是什么。
static func _preview(value: Variant) -> String:
	return JSON.stringify(value)
