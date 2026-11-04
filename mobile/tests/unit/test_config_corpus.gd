extends RefCounted

## 跨语言配置语料套件：同一份 JSON 用例，GDScript 用 ConfigLoader.parse_bytes 判一次，
## Python 用 tools/check_config_parity.py 判一次；语料是唯一契约，两侧不许有第二份期望。
##
## 为什么先断言规模下限：语料被删空时，逐用例循环零次，后面的断言会全部「通过」——
## 那正是本套件要防的真空绿。四个点名 id（BOM / 字符串布尔 / null 数值 / start_angle
## 数组）同理：少了任何一条，对应的分歧就不再被机械核对。
##
## 判据全部走 reporter 的 check；最后一句必须是 r.complete()。夹具目录带 .gdignore，
## Godot 导入器会跳过它，但 FileAccess 仍然能按 res:// 路径读到原始字节。

const CORPUS_PATH := "res://tests/fixtures/config_corpus.json"
const REQUIRED_IDS: Array[String] = [
	"bom", "string_bool", "null_number", "start_angle_array",
]


func run(r) -> void:
	var corpus := _load_corpus(r)
	if corpus.is_empty():
		r.complete()
		return
	var cases: Array = corpus.get("cases", [])
	_check_scale(r, cases)
	for case in cases:
		_check_case(r, case)
	r.complete()


func _load_corpus(r) -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes(CORPUS_PATH)
	if bytes.is_empty():
		r.check(false, "读不到跨语言配置语料 %s" % CORPUS_PATH)
		return {}
	var json := JSON.new()
	if json.parse(bytes.get_string_from_utf8()) != OK:
		r.check(false, "语料不是合法 JSON（第 %d 行：%s）"
			% [json.get_error_line() + 1, json.get_error_message()])
		return {}
	if typeof(json.data) != TYPE_DICTIONARY:
		r.check(false, "语料根节点必须是对象")
		return {}
	var corpus: Dictionary = json.data
	r.check(int(corpus.get("schema_version", 0)) == 1,
		"语料 schema_version 必须是 1（实际 %s）" % str(corpus.get("schema_version")))
	return corpus


## 规模与 id 下限：删空语料、丢掉点名用例、复制 id 都必须变红。
func _check_scale(r, cases: Array) -> void:
	r.check(cases.size() >= 4, "语料规模下限：至少 4 条用例（实际 %d）" % cases.size())
	var ids: Dictionary = {}
	for case in cases:
		if typeof(case) == TYPE_DICTIONARY:
			ids[str(case.get("id", ""))] = true
	r.check(ids.size() == cases.size(),
		"每条用例都必须有唯一 id（实际 %d 个 id / %d 条用例）" % [ids.size(), cases.size()])
	for id in REQUIRED_IDS:
		r.check(ids.has(id), "语料必须包含点名用例 %s" % id)


func _check_case(r, case: Variant) -> void:
	if typeof(case) != TYPE_DICTIONARY:
		r.check(false, "语料用例必须是对象，收到 %s" % type_string(typeof(case)))
		return
	var entry: Dictionary = case
	var id := str(entry.get("id", "<缺 id>"))
	var godot_expect: Variant = entry.get("godot", {})
	if typeof(godot_expect) != TYPE_DICTIONARY:
		r.check(false, "%s: godot 期望必须是对象" % id)
		return
	var godot_dict: Dictionary = godot_expect
	var verdict := str(godot_dict.get("verdict", ""))
	var bytes := _build_bytes(entry, r, id)
	if bytes.is_empty():
		return

	var result := ConfigLoader.parse_bytes(bytes, "corpus:" + id)
	r.check(result.ok() == (verdict == "accept"),
		"%s: ok() 必须是 %s（实际 %s；%s）"
			% [id, str(verdict == "accept"), str(result.ok()), _describe(result)])
	if verdict != "reject":
		return

	var expected_codes: Array = godot_dict.get("codes", [])
	var expected_paths: Array = godot_dict.get("paths", [])
	var actual_codes := _codes(result)
	for code in expected_codes:
		r.check(actual_codes.has(str(code)),
			"%s: 缺少错误码 %s（实际 %s）" % [id, str(code), _describe(result)])
	for path in expected_paths:
		r.check(_has_path(result, str(path)),
			"%s: 缺少 json_path %s（实际 %s）" % [id, str(path), _paths(result)])
	# to_text() 是错误屏的最小机械证明：code 与 path 必须能原样渲染出来。
	var text := result.to_text()
	for code in expected_codes:
		r.check(text.contains(str(code)),
			"%s: to_text() 必须含错误码 %s（实际 %s）" % [id, str(code), text])
	for path in expected_paths:
		r.check(text.contains(str(path)),
			"%s: to_text() 必须含 json_path %s（实际 %s）" % [id, str(path), text])


## 三种入口：data（对象 → stringify）、text（原始文本）、bom（字节前拼 EF BB BF）。
## BOM 只能在字节层合成 —— 字符串 API 会把三个字节悄悄吃掉。
func _build_bytes(entry: Dictionary, r, id: String) -> PackedByteArray:
	var text := ""
	if entry.has("data"):
		text = JSON.stringify(entry["data"])
	elif entry.has("text"):
		text = str(entry["text"])
	else:
		r.check(false, "%s: 用例必须提供 data 或 text" % id)
		return PackedByteArray()
	var bytes := text.to_utf8_buffer()
	var has_bom := false
	if entry.has("bom") and typeof(entry["bom"]) == TYPE_BOOL:
		var raw_bom: bool = entry["bom"]
		has_bom = raw_bom
	if has_bom:
		var with_bom := PackedByteArray([0xEF, 0xBB, 0xBF])
		with_bom.append_array(bytes)
		return with_bom
	return bytes


func _codes(result: ConfigResult) -> PackedStringArray:
	var codes := PackedStringArray()
	for error in result.errors:
		codes.append(str(error.code))
	return codes


func _has_path(result: ConfigResult, path: String) -> bool:
	for error in result.errors:
		if error.json_path == path:
			return true
	return false


func _paths(result: ConfigResult) -> String:
	var paths := PackedStringArray()
	for error in result.errors:
		paths.append(error.json_path)
	return ", ".join(paths)


func _describe(result: ConfigResult) -> String:
	if result.errors.is_empty():
		return "无错误"
	return result.to_text()
