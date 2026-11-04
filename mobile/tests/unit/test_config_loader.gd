extends RefCounted

## 加载器套件：字节入口是唯一入口，BOM 必须在字节层被发现。
##
## 为什么 BOM 用例必须合成字节：`FileAccess.get_file_as_string()` 会在解码时静默剥掉
## 文件头的 EF BB BF，用它读出来的「干净」文本永远测不到 BOM。这里直接拼三个字节，
## 走 `ConfigLoader.parse_bytes`，所以这条断言不可能假绿。
##
## 为什么真实配置必须直接读：只测合成夹具时，「配置能加载」的绿灯可能对着空气。
## 读不到文件要判失败而不是跳过 —— 那说明同步脚本没跑，闸门本来就该红。
##
## 判据全部走 reporter 的 check；最后一句必须是 r.complete()。

const CONFIG_PATH := "res://assets/config/skills_config.json"
const EXPECTED_NAMES: Array[String] = [
	"马赛回旋 Roulette",
	"踩单车 Stepover",
	"磕球过人 Heel-to-Heel",
	"油炸丸子 La Croqueta",
	"绿色搓射 Green Finesse",
]


func run(r) -> void:
	_check_real_config(r)
	_check_bom(r)
	_check_empty(r)
	_check_invalid_utf8(r)
	_check_syntax_error(r)
	_check_decode_bytes(r)
	r.complete()


func _check_real_config(r) -> void:
	var bytes := FileAccess.get_file_as_bytes(CONFIG_PATH)
	if bytes.is_empty():
		r.check(false, "读不到真实配置 %s（先运行 python3 tools/sync_config.py）" % CONFIG_PATH)
		return
	var result := ConfigLoader.parse_bytes(bytes, CONFIG_PATH)
	r.check(result.ok(), "真实配置必须通过加载与校验（实际 %s）" % _describe(result))
	r.check(result.errors.is_empty(), "真实配置不应产生任何 error（实际 %s）" % _paths(result.errors))
	r.check(result.config != null, "真实配置必须产出 AppConfig")
	if result.config == null:
		return
	r.check(result.config.skills.size() == 5,
		"真实配置必须正好 5 条动作（实际 %d）" % result.config.skills.size())
	var names: Array[String] = []
	for skill in result.config.skills:
		names.append(skill.name)
	r.check(names == EXPECTED_NAMES,
		"5 条动作名与 shared/skills_config.json 完全一致（实际 %s）" % str(names))
	# 真实配置有 3 处 "required_button": null；它必须是「不需要修饰键」，不是错误。
	r.check(not result.has_code(&"button_unknown"),
		"required_button: null 不得产生 button_unknown")
	r.check(result.source_path == CONFIG_PATH, "source_path 必须原样记录来源")


func _check_bom(r) -> void:
	var clean := FileAccess.get_file_as_bytes(CONFIG_PATH)
	if clean.is_empty():
		r.check(false, "BOM 用例需要真实配置作为干净字节来源")
		return
	var with_bom := PackedByteArray([0xEF, 0xBB, 0xBF])
	with_bom.append_array(clean)
	var result := ConfigLoader.parse_bytes(with_bom, "<bom>")
	r.check(not result.ok(), "带 UTF-8 BOM 的配置必须失败，不能被静默接受")
	r.check(result.errors.size() == 1, "BOM 只应产生 1 条错误（实际 %d）" % result.errors.size())
	if result.errors.is_empty():
		return
	var error: ConfigError = result.errors[0]
	r.check(error.code == &"bom_detected", "BOM 的错误码必须是 bom_detected（实际 %s）" % error.code)
	r.check(error.json_path == "$", "BOM 的 json_path 必须是 $（实际 %s）" % error.json_path)
	r.check(not error.message.is_empty(), "BOM 的 message 必须非空")
	r.check(not error.fix_hint.is_empty(), "BOM 的 fix_hint 必须非空")
	r.check(error.fix_hint.contains("UTF-8"), "BOM 的修复建议必须写明另存为 UTF-8（实际 %s）" % error.fix_hint)
	var text := result.to_text()
	r.check(text.contains("bom_detected"), "to_text() 必须含错误码（实际 %s）" % text)
	r.check(text.contains("$"), "to_text() 必须含 json_path（实际 %s）" % text)
	r.check(text.contains("UTF-8"), "to_text() 必须含修复建议（实际 %s）" % text)


func _check_empty(r) -> void:
	var result := ConfigLoader.parse_bytes(PackedByteArray(), "<empty>")
	r.check(not result.ok(), "空文件必须失败")
	r.check(result.has_code(&"file_empty"), "空文件必须是 file_empty（实际 %s）" % _describe(result))
	_check_all_error_text(r, "空文件", result)


func _check_invalid_utf8(r) -> void:
	var result := ConfigLoader.parse_bytes(PackedByteArray([0xFF, 0xFE, 0x7B]), "<invalid-utf8>")
	r.check(not result.ok(), "非法 UTF-8 必须失败")
	# 必须是 invalid_utf8，不能退化成 json_syntax_error：后者会让用户去查括号，
	# 而真正的问题是文件编码。get_string_from_utf8 会把坏字节替换成 U+FFFD 并照常
	# 返回，所以加载器必须先做字节往返校验（见 config_loader.gd 的注释）。
	r.check(result.has_code(&"invalid_utf8"),
		"非法 UTF-8 必须是 invalid_utf8（实际 %s）" % _describe(result))
	r.check(not result.errors.is_empty(), "非法 UTF-8 至少要报告一条错误")
	_check_all_error_text(r, "非法 UTF-8", result)


func _check_syntax_error(r) -> void:
	var result := ConfigLoader.parse_text("{\"skills\": [}\n", "<syntax>")
	r.check(not result.ok(), "JSON 语法错误必须失败")
	r.check(result.has_code(&"json_syntax_error"),
		"JSON 语法错误必须是 json_syntax_error（实际 %s）" % _describe(result))
	if not result.errors.is_empty():
		var message: String = result.errors[0].message
		r.check(message.contains("行"), "语法错误消息必须含行号（实际 %s）" % message)
	_check_all_error_text(r, "JSON 语法错误", result)


func _check_decode_bytes(r) -> void:
	var clean := FileAccess.get_file_as_bytes(CONFIG_PATH)
	if clean.is_empty():
		r.check(false, "decode_bytes 用例需要真实配置")
		return
	var decoded := ConfigLoader.decode_bytes(clean, CONFIG_PATH)
	r.check(decoded["error"] == null, "decode_bytes 对干净配置必须返回 error == null")
	r.check(decoded["data"] != null, "decode_bytes 必须返回原始数据")
	r.check(typeof(decoded["data"]) == TYPE_DICTIONARY, "decode_bytes 的 data 必须还是字典")
	if typeof(decoded["data"]) == TYPE_DICTIONARY:
		var data: Dictionary = decoded["data"]
		r.check(data.has("skills"), "decode_bytes 的原始字典必须保留 skills 字段")
		r.check(typeof(data["skills"]) == TYPE_ARRAY and data["skills"].size() == 5,
			"decode_bytes 必须原样给出 5 条动作（不做校验、不改形状）")


func _check_all_error_text(r, label: String, result: ConfigResult) -> void:
	for error in result.errors:
		r.check(not error.message.is_empty(),
			"%s：每条错误的 message 都不能为空（code=%s）" % [label, error.code])
		r.check(not error.fix_hint.is_empty(),
			"%s：每条错误的 fix_hint 都不能为空（code=%s）" % [label, error.code])


func _describe(result: ConfigResult) -> String:
	if result.errors.is_empty():
		return "无错误"
	return result.to_text()


func _paths(errors: Array[ConfigError]) -> String:
	var paths := PackedStringArray()
	for error in errors:
		paths.append(error.json_path)
	return ", ".join(paths)
