class_name ProfileStore
extends RefCounted

## 手柄档案的唯一 I/O 入口：`user://profiles/controllers.json` 的整份读写。
##
## 为什么在 `src/app/` 而不是 core：文件系统是环境状态，core 必须能在没有文件系统的
## 无头环境里跑。本类只负责字节与 `DeviceProfile` 之间的边界，schema 校验仍由
## `DeviceProfile.from_dict()` 完成 —— 不在这里写第二份字段名。
##
## 三条硬约束：
##   1. **只写 `user://`**：导出后的 APK 里 `res://` 只读；第一句守卫目标与临时路径，
##      否则返回 `ERR_UNAUTHORIZED`，且不创建目录或文件。
##   2. **原子写**：temp → flush → close → rename；rename 失败清理临时文件。
##   3. **整份丢弃**：任一条目 schema 非法，就丢弃整份文件并删除它，绝不逐条恢复。
##      一份坏档案最坏的结果必须是「要求重新探测」，而不是「带着错误轴映射进入练习」。
##
## 读文件先取长度再分配：超过 `MAX_BYTES` 在分配内存之前拒绝（T-04-12）。
## `probed_at_iso` 的墙钟只在 `upsert()` 里填 —— core 的 `DeviceProfile` 不读时钟。

const PROFILES_PATH := "user://profiles/controllers.json"
const TEMP_SUFFIX := ".tmp"
## 1 MiB：正常档案不到 4 KB；超限直接拒绝解析，廉价挡掉畸形输入。
const MAX_BYTES := 1_048_576
const SCHEMA_VERSION := 1

var _path: String


## 路径可注入是为了测试用独立文件，不污染真实用户目录。
func _init(p_path: String = PROFILES_PATH) -> void:
	_path = p_path


func path() -> String:
	return _path


## 读全部档案。返回 `{profiles: Dictionary, notice: String, error: Error}`。
##
## 文件不存在是首次使用的正常状态：`notice` 为空、`error == OK`、空档案。
## 任何损坏路径（打不开、过大、JSON 坏、版本不对、条目非法）都归到「删除 + 一句
## notice + 空档案」；`error` 保留具体错误码便于诊断，但调用方的恢复动作只有一种：
## 重新探测。
func load_all() -> Dictionary:
	if not FileAccess.file_exists(_path):
		return {"profiles": {}, "notice": "", "error": OK}
	var file := FileAccess.open(_path, FileAccess.READ)
	if file == null:
		return {
			"profiles": {},
			"notice": "手柄档案读取失败，已忽略。",
			"error": FileAccess.get_open_error(),
		}
	# 先取长度再分配：超限文件在 get_as_text() 之前就被拒绝。
	var length := file.get_length()
	if length > MAX_BYTES:
		file.close()
		_discard()
		return {
			"profiles": {},
			"notice": "手柄档案过大，已丢弃。",
			"error": ERR_INVALID_DATA,
		}
	var text := file.get_as_text()
	file.close()

	var parsed := JSON.new()
	if parsed.parse(text) != OK:
		return _discard_corrupt()
	var root: Variant = parsed.data
	if typeof(root) != TYPE_DICTIONARY:
		return _discard_corrupt()
	var data: Dictionary = root

	var version: Variant = data.get("schema_version")
	if not _is_number(version) or int(float(version)) != SCHEMA_VERSION:
		return _discard_corrupt()
	var raw_profiles: Variant = data.get("profiles")
	if typeof(raw_profiles) != TYPE_DICTIONARY:
		return _discard_corrupt()
	var raw_map: Dictionary = raw_profiles

	var profiles := {}
	var errors: Array[ConfigError] = []
	for key in raw_map:
		var profile := DeviceProfile.from_dict(raw_map[key], errors)
		# 任一条目非法 → 整份丢弃：合法条目也不保留，避免「半个档案」进入运行时。
		if profile == null or not errors.is_empty():
			return _discard_corrupt()
		profiles[key] = profile
	return {"profiles": profiles, "notice": "", "error": OK}


## 整份重写。目标与临时路径都必须以 `user://` 开头，否则 `ERR_UNAUTHORIZED`
## 且零副作用 —— 导出后的 APK 里 `res://` 只读，这条必须由代码强制，不能靠调用方自觉。
func save_all(profiles: Dictionary) -> Error:
	var target := _path
	var temp := target + TEMP_SUFFIX
	if not target.begins_with("user://") or not temp.begins_with("user://"):
		return ERR_UNAUTHORIZED
	var dir_err := DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	if dir_err != OK:
		return dir_err
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var serialized := {}
	for key in profiles:
		var value: Variant = profiles[key]
		if value is DeviceProfile:
			serialized[key] = (value as DeviceProfile).to_dict()
	# 顺序不能换：先刷到内核再关闭，关闭之后才允许改名。
	file.store_string(JSON.stringify({
		"schema_version": SCHEMA_VERSION,
		"profiles": serialized,
	}, "\t", true))
	file.flush()
	file.close()
	var err := DirAccess.rename_absolute(temp, target)
	if err != OK:
		# 改名前失败时清掉临时文件，否则下次启动会看到一个孤立的 .tmp。
		DirAccess.remove_absolute(temp)
	return err


## 写入 / 更新一份档案。墙钟时间只在这里填（秒级，排障用，不参与判定）。
## 空 key 直接拒绝：`DeviceProfile.from_dict` 不接受空 key，写进去的文件下次启动
## 必然整份丢弃 —— 与其制造一个自毁档案，不如在写入点就报错。
func upsert(profile: DeviceProfile) -> Error:
	if profile == null or profile.key.strip_edges().is_empty():
		return ERR_INVALID_PARAMETER
	var loaded := load_all()
	var profiles: Dictionary = loaded["profiles"]
	profile.probed_at_iso = Time.get_datetime_string_from_system()
	profiles[profile.key] = profile
	return save_all(profiles)


## 按 key 查一份档案；不存在返回 null（首次使用是正常状态，不是错误）。
func find(key: String) -> DeviceProfile:
	var loaded := load_all()
	var profiles: Dictionary = loaded["profiles"]
	var value: Variant = profiles.get(key)
	if value is DeviceProfile:
		return value
	return null


## 丢弃后立刻删除：否则每次启动都会重复丢弃、重复提示。
func _discard_corrupt() -> Dictionary:
	_discard()
	return {
		"profiles": {},
		"notice": "手柄档案已损坏，已丢弃并等待重新探测。",
		"error": ERR_FILE_CORRUPT,
	}


func _discard() -> void:
	DirAccess.remove_absolute(_path)


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT
