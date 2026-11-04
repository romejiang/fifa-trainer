class_name OverlayMerge
extends RefCounted

## 用户覆盖层的纯合并语义：两个字典进，OverlayResult 出。
##
## 这里没有文件系统、没有引擎状态、没有日志 —— 同一个输入永远得到同一份输出，
## 所以它可以被无场景树的回放测试直接驱动。读文件、算 base 摘要、删除坏文件
## 全部在 src/app/config_store.gd；core 只认 Dictionary。
##
## 覆盖层是稀疏的，只允许三个白名单键：enabled / required_button / button_mode。
## params 里的阈值永远不进覆盖层 —— 改了阈值，历史统计立刻不可比，那是
## PROJECT.md 的明确反目标。以 skill name（不是数组下标）为键，是因为 base
## 重排不该让覆盖层改到另一个动作上。
##
## 整体丢弃（缺 schema / schema 过新 / base hash 变了 / skills 不是对象）一律
## 不部分保留：半套语义比没有语义更难查，用户看到一句 notice 就能理解「回去
## 重新设置一次」。
##
## 未知动作名与未知键只记 warning，其余合法条目照常生效 —— 一条手写的多余条目
## 不该让整份自定义设置失效。

const SCHEMA_VERSION := 1
const ALLOWED_KEYS := [&"enabled", &"required_button", &"button_mode"]


## 把 overlay 合并进 base 的深拷贝；绝不修改调用者传入的 base。
static func merge(base: Dictionary, overlay: Dictionary,
		current_base_sha256: String) -> OverlayResult:
	var result := OverlayResult.new()
	# 回放测试会复用同一份 base：深拷贝是「输入相同、输出相同」的前提。
	result.data = base.duplicate(true)

	var schema: Variant = overlay.get("schema_version")
	if typeof(schema) != TYPE_INT and typeof(schema) != TYPE_FLOAT:
		return result._discard(&"overlay_schema_invalid",
			"自定义设置缺少有效的 schema_version，已恢复默认。")
	# 未来版本写的文件，当前版本不猜它的语义。
	if int(schema) > SCHEMA_VERSION:
		return result._discard(&"overlay_schema_too_new",
			"自定义设置来自更新的版本，已恢复默认。")

	var hash_value: Variant = overlay.get("base_sha256")
	if typeof(hash_value) != TYPE_STRING or \
			String(hash_value).to_lower() != current_base_sha256.to_lower():
		return result._discard(&"overlay_base_changed",
			"配置已更新，已丢弃自定义按键设置。")

	var skills_value: Variant = overlay.get("skills")
	if typeof(skills_value) != TYPE_DICTIONARY:
		return result._discard(&"overlay_schema_invalid",
			"自定义设置缺少有效的 skills 对象，已恢复默认。")

	var by_name := _index_skills(result.data)
	var entries: Dictionary = skills_value
	for raw_name in entries:
		var name := String(raw_name)
		if not by_name.has(name):
			result.warnings.append(ConfigError.new(
				"$overlay.skills.%s" % name,
				&"overlay_skill_unknown",
				"自定义设置里的动作 %s 在当前配置中不存在，已忽略" % name,
				"删除该动作的自定义设置，或从配置里恢复同名动作。",
				ConfigError.SEVERITY_WARNING))
			continue
		var raw_values: Variant = entries[raw_name]
		if typeof(raw_values) != TYPE_DICTIONARY:
			continue
		var values: Dictionary = raw_values
		var target: Dictionary = by_name[name]
		for raw_key in values:
			var key := StringName(raw_key)
			if key not in ALLOWED_KEYS:
				result.warnings.append(ConfigError.new(
					"$overlay.skills.%s.%s" % [name, String(raw_key)],
					&"overlay_key_unknown",
					"自定义设置里的键 %s 不允许修改（只允许 enabled / required_button / button_mode），已忽略" % String(raw_key),
					"把该键改成三个白名单键之一；params 里的阈值不属于自定义设置。",
					ConfigError.SEVERITY_WARNING))
				continue
			# 键沿用 JSON 里的字符串形态，与 base 的键类型一致。
			target[raw_key] = values[raw_key]
			result.applied = true
	return result


## 建 name → skill 字典 的索引；非字典项与没有字符串 name 的项直接跳过，
## 让它们留给校验器报错，而不是在这里制造第二条错误来源。
static func _index_skills(data: Dictionary) -> Dictionary:
	var by_name := {}
	var raw: Variant = data.get("skills")
	if typeof(raw) != TYPE_ARRAY:
		return by_name
	for item in raw:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var skill: Dictionary = item
		var name_value: Variant = skill.get("name")
		if typeof(name_value) != TYPE_STRING:
			continue
		by_name[String(name_value)] = skill
	return by_name
