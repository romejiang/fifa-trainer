class_name ConfigStore
extends RefCounted

## 配置的唯一 I/O 入口：读 base 字节、读覆盖层字节、算 base 摘要、原子写覆盖层。
##
## 为什么只有这里能用 FileAccess / DirAccess：src/core 必须能在没有文件系统的
## 环境里跑回放测试；I/O 混进去就不可复现。core 只认 PackedByteArray，
## 解码与合并全部是纯函数。
##
## 为什么写入目标是 user:// 而不是 res://：导出后的 APK 里 res:// 只读；编辑器
## 里能写会把「写错地方」掩盖到真机才暴露。save_overrides() 的第一句就是机械守卫。
##
## 为什么先写临时文件再改名：写到一半被杀会留下半损坏的 JSON；改名在 POSIX
## 文件系统上是原子的（macOS 实测通过，Android 真机确认留给 Phase 4）。
##
## 覆盖层被整体丢弃时立刻删除文件：否则每次启动都会重复丢弃、重复提示，
## 用户会被同一条横幅反复打扰。删除失败不视为致命 —— base 仍然可用。

const BASE_PATH := "res://assets/config/skills_config.json"
const OVERRIDES_DIR := "user://config"
## 生产路径是常量：任何注入路径都必须以 user:// 开头，否则 save_overrides 拒绝。
const OVERRIDES_PATH := "user://config/overrides.json"
const TEMP_SUFFIX := ".tmp"
## 1 MiB：base 约 9 KB、覆盖层正常不到 2 KB；超限直接拒绝解析，廉价挡掉畸形输入。
const MAX_BYTES := 1_048_576

var _base_path: String
var _overrides_path: String


## 路径可注入是为了测试用独立文件，不污染真实用户目录。
func _init(base_path: String = BASE_PATH, overrides_path: String = OVERRIDES_PATH) -> void:
	_base_path = base_path
	_overrides_path = overrides_path


func overrides_path() -> String:
	return _overrides_path


## 读 base（必经）与覆盖层（可选）→ 合并 → 整体校验。
## 任何失败都返回带 ConfigError 的 ConfigResult，绝不抛错、绝不写日志。
func load_config() -> ConfigResult:
	if not (_base_path.begins_with("res://") or _base_path.begins_with("user://")):
		return _result_with(&"file_read_error",
			"配置路径必须以 res:// 或 user:// 开头，收到 %s" % _base_path,
			"检查 ConfigStore 的 base_path；导出后的 APK 只能读 res://。")
	if not FileAccess.file_exists(_base_path):
		return _result_with(&"file_missing",
			"找不到配置文件 %s" % _base_path,
			"确认配置已导出，或运行 python3 tools/sync_config.py 重新生成副本。")

	var base_read := _read_bytes(_base_path)
	if base_read["error"] != null:
		return _result_from_error(base_read["error"])
	var decoded := ConfigLoader.decode_bytes(base_read["bytes"], _base_path)
	if decoded["error"] != null:
		return _result_from_error(decoded["error"])

	var base_data: Variant = decoded["data"]
	# 只有 base 是对象时才谈得上合并；不是对象时交给 validate 报 root_not_object。
	var merged := OverlayResult.new()
	if typeof(base_data) == TYPE_DICTIONARY:
		if FileAccess.file_exists(_overrides_path):
			merged = _merge_overlay(base_data)
		else:
			merged.data = base_data
	else:
		merged.data = {}

	var validated: Variant = base_data if typeof(base_data) != TYPE_DICTIONARY else merged.data
	var result := ConfigValidator.validate(validated, _base_path)
	# 这次转交是生产路径的关键：OverlayMerge 只把 warning 放进自己的返回值，
	# 不在 load_config 里转交，纯合并测试全绿而真实调用方永远看不到它们。
	result.warnings.append_array(merged.warnings)
	result.notice = merged.notice
	result.overrides_applied = merged.applied
	return result


## 原子写覆盖层：临时文件 → flush → close → 改名。
## 失败路径要么返回错误码，要么删除临时文件后返回错误码，绝不留半损坏的目标文件。
func save_overrides(data: Dictionary) -> Error:
	var target := _overrides_path
	var temp := target + TEMP_SUFFIX
	# 导出后的 APK 里 res:// 只读；编辑器里能写，所以这一条必须由代码强制。
	if not target.begins_with("user://") or not temp.begins_with("user://"):
		return ERR_UNAUTHORIZED
	var dir_err := DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	if dir_err != OK:
		return dir_err
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t", true))
	# 顺序不能换：先刷到内核再关闭，关闭之后才允许改名。
	file.flush()
	file.close()
	var err := DirAccess.rename_absolute(temp, target)
	if err != OK:
		# 改名前失败时清掉临时文件，否则下次启动会看到一个孤立的 .tmp。
		DirAccess.remove_absolute(temp)
	return err


## 覆盖层字节 → 合并结果。所有「坏覆盖层」路径都收敛到这里：
## 删除文件 + 一句 notice，base 仍然可用。
func _merge_overlay(base_data: Dictionary) -> OverlayResult:
	var merged := OverlayResult.new()
	merged.data = base_data

	var read := _read_bytes(_overrides_path)
	if read["error"] != null:
		_remove_overrides()
		var read_error: ConfigError = read["error"]
		if read_error.code == &"file_too_large":
			merged.notice = "自定义设置文件过大，已忽略。"
		else:
			merged.notice = "自定义设置已损坏，已恢复默认。"
		return merged

	var decoded := ConfigLoader.decode_bytes(read["bytes"], _overrides_path)
	if decoded["error"] != null or typeof(decoded["data"]) != TYPE_DICTIONARY:
		_remove_overrides()
		merged.notice = "自定义设置已损坏，已恢复默认。"
		return merged

	var overlay: Dictionary = decoded["data"]
	merged = OverlayMerge.merge(base_data, overlay, _base_sha256())
	if merged.discarded_reason != &"":
		_remove_overrides()
	return merged


## base 的摘要取当前文件字节，不读可能过期或被手改的 .sha256 边车文件。
func _base_sha256() -> String:
	return FileAccess.get_sha256(_base_path)


## 丢弃覆盖层后立刻删除，保证同一条提示最多打扰一次。
func _remove_overrides() -> void:
	DirAccess.remove_absolute(_overrides_path)


## bytes 读是 BOM 检测的前提：字符串 API 会在解码时静默剥掉文件头的 EF BB BF。
## 先取长度再读：超限文件在分配内存之前就被拒绝，上限才真的挡得住畸形输入。
static func _read_bytes(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"bytes": PackedByteArray(), "error": ConfigError.new("$", &"file_read_error",
			"无法读取文件 %s（错误码 %d）" % [path, FileAccess.get_open_error()],
			"确认文件存在且当前用户可读。")}
	var length := file.get_length()
	if length > MAX_BYTES:
		file.close()
		return {"bytes": PackedByteArray(), "error": ConfigError.new("$", &"file_too_large",
			"文件 %s 有 %d 字节，超过 %d 字节上限" % [path, length, MAX_BYTES],
			"确认这是配置文件；覆盖层正常大小不到 2 KB。")}
	var bytes := file.get_buffer(length)
	file.close()
	return {"bytes": bytes, "error": null}


func _result_with(code: StringName, message: String, fix_hint: String) -> ConfigResult:
	return _result_from_error(ConfigError.new("$", code, message, fix_hint))


func _result_from_error(error: ConfigError) -> ConfigResult:
	var result := ConfigResult.new()
	result.source_path = _base_path
	result.errors.append(error)
	return result
