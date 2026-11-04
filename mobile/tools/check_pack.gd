extends SceneTree

## 从导出的 PCK 里把配置与 sidecar 读回来，证明它们真的在包里 ——
## 而不是从工程目录里读到（那就是闸门 A 的假绿）。
## 用法：godot --headless --main-pack <pck> --script res://tools/check_pack.gd
## 必须**不带** --path：带 --path 时 res:// 指向工程目录，读到的不是导出物。

const CONFIG_PATH := "res://assets/config/skills_config.json"
const SIDECAR_PATH := "res://assets/config/skills_config.json.sha256"

## 这条常量对应 shared/skills_config.json 的 5 条动作：新增动作时必须同步改这里并在
## 提交信息里写明理由。禁止改成读到几条算几条 —— 那样这条断言永远绿，等于没有断言。
const EXPECTED_SKILLS := 5

func _initialize() -> void:
	var failures: Array[String] = []
	if not FileAccess.file_exists(CONFIG_PATH):
		failures.append("配置不在包里: " + CONFIG_PATH)
	if not FileAccess.file_exists(SIDECAR_PATH):
		failures.append("sha256 不在包里: " + SIDECAR_PATH)
	if failures.is_empty():
		var text := FileAccess.get_file_as_string(CONFIG_PATH)
		var parsed = JSON.parse_string(text)
		if not (parsed is Dictionary):
			failures.append("配置不是合法 JSON")
		else:
			var skills = parsed.get("skills", [])
			if not (skills is Array) or skills.size() != EXPECTED_SKILLS:
				failures.append("SKILL_COUNT != %d" % EXPECTED_SKILLS)
			# 注意：.sha256 是 sha256sum 兼容格式「摘要 + 两个空格 + 文件名 + LF」，
			# 不是裸摘要（见 tools/sync_config.py:98-99）。必须取第一个空白分隔字段，
			# 照「字符串相等」写会永远不相等 —— 那时最危险的修法是把校验删掉。
			var sidecar := FileAccess.get_file_as_string(SIDECAR_PATH).strip_edges().split(" ", false)[0]
			var digest := FileAccess.get_sha256(CONFIG_PATH)
			if sidecar != digest:
				failures.append("sha256 不匹配: %s != %s" % [sidecar, digest])
	if failures.is_empty():
		print("PACK_OK skills=%d" % EXPECTED_SKILLS)
		quit(0)
	else:
		for f in failures:
			printerr("PACK_FAIL " + f)
		quit(1)
