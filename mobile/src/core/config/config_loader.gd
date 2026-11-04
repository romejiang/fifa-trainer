class_name ConfigLoader
extends RefCounted

## 配置加载的唯一入口：字节进，ConfigResult 出。
##
## 三条铁律：
## 1. 入口只收 PackedByteArray。读文件归 src/app/config_store.gd；core 不碰文件系统。
##    用字符串 API 读文件会在解码时静默剥掉 UTF-8 BOM（EF BB BF），BOM 用例会永远假绿。
## 2. 不用 JSON.parse_string：失败时它会向 stderr 打 ERROR，纯层不该写日志，也拿不到行号。
## 3. JSON.new().parse() 的错误行号是 0 基，报给用户时 +1。
##
## parse_bytes = decode_bytes + ConfigValidator.validate。decode_bytes 单独暴露原始
## Dictionary，是因为 03-06 的 ConfigStore 需要先在原始字典上合并覆盖层再整体校验，
## 不能直接用「已经校验过」的结果。

const ROOT_PATH := "$"


## 字节 → 已校验的 ConfigResult。
static func parse_bytes(bytes: PackedByteArray, source_path := "") -> ConfigResult:
	var decoded := decode_bytes(bytes, source_path)
	return _result_from_decoded(decoded, source_path)


## 文本 → 已校验的 ConfigResult。防御直接调用者传进来的 BOM 字符。
static func parse_text(text: String, source_path := "") -> ConfigResult:
	var decoded := decode_text(text, source_path)
	return _result_from_decoded(decoded, source_path)


## 字节 → 原始 JSON 数据，**不做语义校验**。返回 {"data": Variant, "error": ConfigError}。
##
## BOM 只在这一层能被发现：三个字节在解码前是可见的，解码成字符串之后就可能被
## 上游 API 悄悄吃掉。这是本计划把入口定为字节的唯一原因。
static func decode_bytes(bytes: PackedByteArray, source_path := "") -> Dictionary:
	if bytes.size() >= 3 and bytes[0] == 0xEF and bytes[1] == 0xBB and bytes[2] == 0xBF:
		return _failure(ConfigError.new(ROOT_PATH, &"bom_detected",
			"配置文件开头有 UTF-8 BOM（EF BB BF），JSON 解析器会把它当成非法字符",
			"用编辑器另存为 UTF-8（无 BOM）；BOM 是文件头的三个隐藏字节，肉眼看不到。"))
	if bytes.is_empty():
		return _failure(ConfigError.new(ROOT_PATH, &"file_empty",
			"配置文件的字节数为 0，没有任何内容",
			"确认文件没有被清空；也可以运行同步脚本重新生成副本。"))
	var text := bytes.get_string_from_utf8()
	if text.is_empty():
		# get_string_from_utf8 在遇到非法序列时返回空串；字节非空却解不出文本，
		# 说明文件不是 UTF-8，而不是「内容为空」。
		return _failure(ConfigError.new(ROOT_PATH, &"invalid_utf8",
			"配置文件的字节不是合法的 UTF-8，无法解码成文本",
			"用支持 UTF-8 的编辑器另存为 UTF-8；不要用 GBK / Latin-1 保存。"))
	return decode_text(text, source_path)


## 文本 → 原始 JSON 数据，**不做语义校验**。返回 {"data": Variant, "error": ConfigError}。
static func decode_text(text: String, source_path := "") -> Dictionary:
	if text.begins_with(String.chr(0xFEFF)):
		return _failure(ConfigError.new(ROOT_PATH, &"bom_detected",
			"配置文件开头有 UTF-8 BOM，JSON 解析器会把它当成非法字符",
			"用编辑器另存为 UTF-8（无 BOM）；BOM 是文件头的隐藏字符，肉眼看不到。"))
	var json := JSON.new()
	if json.parse(text) != OK:
		var line := json.get_error_line() + 1
		return _failure(ConfigError.new(ROOT_PATH, &"json_syntax_error",
			"配置文件 JSON 语法错误（第 %d 行）：%s" % [line, json.get_error_message()],
			"JSON 不支持 // 注释，也不允许最后一个元素后面多写逗号。"))
	return {"data": json.data, "error": null}


static func _result_from_decoded(decoded: Dictionary, source_path: String) -> ConfigResult:
	if decoded["error"] != null:
		var result := ConfigResult.new()
		result.source_path = source_path
		var error: ConfigError = decoded["error"]
		result.errors.append(error)
		return result
	return ConfigValidator.validate(decoded["data"], source_path)


static func _failure(error: ConfigError) -> Dictionary:
	return {"data": null, "error": error}
