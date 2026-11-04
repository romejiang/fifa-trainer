extends RefCounted

## ConfigStore 的真实 I/O 矩阵：写入 → 读回 → 合并生效，以及四条失败路径。
##
## 为什么用注入路径 user://config/test_overrides.json：默认路径是真实用户数据，
## 测试既不能读也不能写它；默认路径的 user:// 前缀另有单独断言。
##
## 为什么 base 摘要取真实文件：只有摘要真正匹配，才能测到「应用成功」这一半；
## 伪造摘要只能证明丢弃路径。base 变更时这个套件会跟着变红 —— 那正是提醒
## 「覆盖层该作废了」的同一件事。
##
## 每个用例前后都清理测试文件：坏覆盖层用例会留下文件，下一条用例若读到它，
## 失败会指向错误的场景。

const BASE_PATH := "res://assets/config/skills_config.json"
const TEST_OVERRIDES := "user://config/test_overrides.json"
const TEST_BASE_MISSING := "user://config/test_base_missing.json"
const TEST_BASE_LARGE := "user://config/test_base_large.json"
const GREEN := "绿色搓射 Green Finesse"
const FORBIDDEN_PATH := "res://config/should_not_exist.json"


func run(r) -> void:
	_clean()
	_check_default_path(r)
	_check_write_read_merge(r)
	_check_first_run_is_quiet(r)
	_check_res_guard(r)
	_check_atomic_write(r)
	_check_broken_overlay(r)
	_check_too_large_overlay(r)
	_check_overlay_schema_invalid(r)
	_check_base_failures(r)
	_check_stale_hash(r)
	_check_warnings_reach_result(r)
	_clean()
	r.complete()


## 默认路径必须落在 user://：这是「绝不写 res://」的第一道机械证据。
func _check_default_path(r) -> void:
	var store := ConfigStore.new()
	r.check(store.overrides_path().begins_with("user://"),
		"默认覆盖层路径必须在 user:// 下（实际 %s）" % store.overrides_path())
	r.check(store.overrides_path() == "user://config/overrides.json",
		"默认覆盖层路径必须是常量 user://config/overrides.json（实际 %s）" % store.overrides_path())


## 写一次 → 读回来 → 合并生效。这是 DATA-03 的主路径。
func _check_write_read_merge(r) -> void:
	_clean()
	var store := _store()
	var saved := store.save_overrides(_overlay({GREEN: {"enabled": false}}))
	r.check(saved == OK, "合法覆盖层必须保存成功（实际错误码 %d）" % saved)

	var result := store.load_config()
	r.check(result.ok(), "读回覆盖层后配置必须仍然可用：%s" % _describe(result))
	if not result.ok():
		return
	r.check(result.overrides_applied, "覆盖层必须被标记为已应用")
	r.check(result.notice.is_empty(), "成功应用覆盖层时不应有 notice（实际 %s）" % result.notice)

	var green := _find_skill(result.config, GREEN)
	r.check(green != null, "合并后必须还能找到 %s" % GREEN)
	if green == null:
		return
	r.check(not green.enabled, "覆盖层里的 enabled=false 必须生效")

	var others_enabled := true
	for skill in result.config.skills:
		if skill.name != GREEN and not skill.enabled:
			others_enabled = false
	r.check(others_enabled, "未被覆盖的四条动作必须保持 enabled=true")
	r.check(result.config.skills.size() == 5,
		"合并不得增删动作（实际 %d 条）" % result.config.skills.size())


## 首启没有覆盖层是正常状态：安静地只用 base，不创建空文件。
func _check_first_run_is_quiet(r) -> void:
	_clean()
	var result := _store().load_config()
	r.check(result.ok(), "首启没有覆盖层必须能加载 base：%s" % _describe(result))
	r.check(not result.overrides_applied, "首启没有覆盖层时 overrides_applied 必须为 false")
	r.check(result.notice.is_empty(), "首启没有覆盖层时 notice 必须为空（实际 %s）" % result.notice)
	r.check(not FileAccess.file_exists(TEST_OVERRIDES), "首启不得创建空覆盖层文件")


## 写偏：目标在 res:// 时必须拒绝，且零文件副作用（目录也不能建）。
func _check_res_guard(r) -> void:
	DirAccess.remove_absolute(FORBIDDEN_PATH)
	var store := ConfigStore.new(BASE_PATH, FORBIDDEN_PATH)
	var err := store.save_overrides({"schema_version": 1})
	r.check(err == ERR_UNAUTHORIZED,
		"写入 res:// 必须返回 ERR_UNAUTHORIZED（实际 %d）" % err)
	r.check(not FileAccess.file_exists(FORBIDDEN_PATH), "写入 res:// 失败后不得留下文件")
	r.check(not DirAccess.dir_exists_absolute("res://config"),
		"写入 res:// 失败后不得创建目录")


## 写一半：成功后不留 .tmp；预置的 .tmp 必须被改名覆盖，而不是留下两份。
func _check_atomic_write(r) -> void:
	_clean()
	var store := _store()
	var first := store.save_overrides(_overlay({GREEN: {"enabled": false}}))
	r.check(first == OK, "首次原子写必须成功（实际 %d）" % first)
	r.check(not FileAccess.file_exists(TEST_OVERRIDES + ConfigStore.TEMP_SUFFIX),
		"成功后不得残留 .tmp")

	_write_raw(TEST_OVERRIDES + ConfigStore.TEMP_SUFFIX, "stale")
	var second := store.save_overrides(_overlay({GREEN: {"enabled": true}}))
	r.check(second == OK, "目标已存在时原子覆盖必须成功（实际 %d）" % second)
	r.check(not FileAccess.file_exists(TEST_OVERRIDES + ConfigStore.TEMP_SUFFIX),
		"改名成功后 .tmp 必须消失")

	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TEST_OVERRIDES))
	r.check(typeof(parsed) == TYPE_DICTIONARY and parsed.get("skills", {}).has(GREEN),
		"覆盖后的文件必须是新内容，不是旧文件残留")


## 写坏：坏 JSON 必须回退到 base + notice，并删除坏文件。
func _check_broken_overlay(r) -> void:
	_clean()
	_write_raw(TEST_OVERRIDES, "not json at all")
	var result := _store().load_config()
	r.check(result.ok(), "坏覆盖层必须回退到可用 base：%s" % _describe(result))
	r.check(result.notice.contains("已恢复默认"),
		"坏覆盖层必须给出中文 notice（实际 %s）" % result.notice)
	r.check(not result.overrides_applied, "坏覆盖层不得被标记为已应用")
	r.check(not FileAccess.file_exists(TEST_OVERRIDES),
		"坏覆盖层必须被删除，避免每次启动重复提示")


## 超大：超过 MAX_BYTES 的覆盖层不解析，删除并提示「已忽略」。
func _check_too_large_overlay(r) -> void:
	_clean()
	_write_raw(TEST_OVERRIDES, "x".repeat(ConfigStore.MAX_BYTES + 1))
	var result := _store().load_config()
	r.check(result.ok(), "超大覆盖层必须回退到可用 base：%s" % _describe(result))
	r.check(result.notice.contains("已忽略"),
		"超大覆盖层必须给出「已忽略」notice（实际 %s）" % result.notice)
	r.check(not FileAccess.file_exists(TEST_OVERRIDES), "超大覆盖层必须被删除")


## 覆盖层结构不对（skills 不是对象）：整体丢弃，base 仍然可用。
func _check_overlay_schema_invalid(r) -> void:
	_clean()
	var overlay := _overlay({})
	overlay["skills"] = []
	_write_raw(TEST_OVERRIDES, JSON.stringify(overlay))
	var result := _store().load_config()
	r.check(result.ok(), "skills 非对象时 base 仍必须可用：%s" % _describe(result))
	r.check(result.notice.contains("已恢复默认"),
		"skills 非对象必须给出「已恢复默认」notice（实际 %s）" % result.notice)
	r.check(not result.overrides_applied, "skills 非对象时不得应用任何覆盖")
	r.check(not FileAccess.file_exists(TEST_OVERRIDES), "结构坏掉的覆盖层必须被删除")


## base 自己读不到或超过上限：必须返回错误结果，而不是半个配置。
func _check_base_failures(r) -> void:
	var missing := ConfigStore.new(TEST_BASE_MISSING, TEST_OVERRIDES).load_config()
	r.check(not missing.ok(), "base 不存在时必须返回失败")
	r.check(missing.has_code(&"file_missing"), "base 不存在时错误码必须是 file_missing")
	r.check(missing.config == null, "base 不存在时不得产出半个配置")

	_write_raw(TEST_BASE_LARGE, "x".repeat(ConfigStore.MAX_BYTES + 1))
	var large := ConfigStore.new(TEST_BASE_LARGE, TEST_OVERRIDES).load_config()
	r.check(not large.ok(), "base 超过上限时必须返回失败")
	r.check(large.has_code(&"file_too_large"), "base 超限时错误码必须是 file_too_large")
	r.check(large.config == null, "base 超限时不得产出半个配置")


## 写旧：base 摘要变了必须整体丢弃，notice 逐字等于约定原文。
func _check_stale_hash(r) -> void:
	_clean()
	var stale := {
		"schema_version": 1,
		"base_sha256": "0".repeat(64),
		"skills": {GREEN: {"enabled": false}},
	}
	r.check(_store().save_overrides(stale) == OK, "过期 hash 的覆盖层也必须能写入")

	var result := _store().load_config()
	r.check(result.ok(), "hash 过期必须回退到可用 base：%s" % _describe(result))
	r.check(result.notice == "配置已更新，已丢弃自定义按键设置。",
		"hash 过期的 notice 必须是约定原文（实际 %s）" % result.notice)
	r.check(not result.overrides_applied, "hash 过期时不得应用任何覆盖")
	r.check(not FileAccess.file_exists(TEST_OVERRIDES),
		"hash 过期后必须删除覆盖层，只打扰一次")


## 生产路径的 warning 转交：未知动作 / 未知键必须经 load_config() 抵达调用方，
## 而不是只躺在 OverlayMerge 的返回值里。
func _check_warnings_reach_result(r) -> void:
	_clean()
	var overlay := _overlay({
		"不存在的动作": {"enabled": false},
		GREEN: {"enabled": true, "params": {"min_angle": 10}},
	})
	r.check(_store().save_overrides(overlay) == OK, "含未知项的覆盖层必须能写入")

	var result := _store().load_config()
	r.check(result.ok(), "未知项不得阻止启动：%s" % _describe(result))
	r.check(result.config != null, "未知项存在时 config 仍必须非 null")
	r.check(result.overrides_applied, "同一个覆盖层里的合法白名单键必须生效")
	r.check(result.warnings.size() == 2,
		"load_config 必须转交两条 warning（实际 %d 条）" % result.warnings.size())
	r.check(result.has_code(&"overlay_skill_unknown"), "必须含未知动作 warning")
	r.check(result.has_code(&"overlay_key_unknown"), "必须含未知键 warning")

	var green := _find_skill(result.config, GREEN) if result.config != null else null
	r.check(green != null and not green.params.has("min_angle"),
		"未知键 params 不得写进合并后的配置")


func _store() -> ConfigStore:
	return ConfigStore.new(BASE_PATH, TEST_OVERRIDES)


## 覆盖层的固定外壳；摘要取真实 base 文件的当前摘要。
static func _overlay(skills: Dictionary) -> Dictionary:
	return {
		"schema_version": 1,
		"base_sha256": FileAccess.get_sha256(BASE_PATH),
		"skills": skills,
	}


static func _find_skill(config: AppConfig, name: String) -> Skill:
	if config == null:
		return null
	for skill in config.skills:
		if skill.name == name:
			return skill
	return null


static func _describe(result: ConfigResult) -> String:
	if result == null:
		return "null"
	if result.ok():
		return "ok"
	return result.to_text()


static func _write_raw(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(text)
	file.flush()
	file.close()


func _clean() -> void:
	DirAccess.remove_absolute(TEST_OVERRIDES)
	DirAccess.remove_absolute(TEST_OVERRIDES + ConfigStore.TEMP_SUFFIX)
	DirAccess.remove_absolute(TEST_BASE_MISSING)
	DirAccess.remove_absolute(TEST_BASE_LARGE)
	DirAccess.remove_absolute(FORBIDDEN_PATH)
