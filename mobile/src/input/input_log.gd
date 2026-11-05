class_name InputLog
extends RefCounted

## 输入事件日志：把「测试者到底按了什么」变成 adb 可直接读取的事实。
##
## 为什么需要它：前三次真机测试都卡在「代理看不到用户按了什么」—— 实时截图只能
## 看到某一帧，按完再问「按成功了吗」不可靠。这里把每一次按键边沿与每根轴的可见
## 变化写成一行带毫秒时间戳的文本：
##   t=<ms> dev=<d> btn=<i> name=<canonical> down=<0|1>
##   t=<ms> dev=<d> axis=<i> v=<x.xxx>
## 测试者按完任意组合后，`adb exec-out cat <LOG_PATH>` 就能回放整段事件序列。
##
## 为什么是绝对路径 /storage/emulated/0/Android/data/<包名>/files：release 包不可
## 调试（`run-as` 直接拒绝），而 Android/data/<包名>/files 是应用自己的外部目录，
## adb shell 可以读。logcat 通道（`INPUT_EVT` 前缀）作为第二条无需权限的通道同时写。
##
## 为什么写日志不能影响输入（T-04-21）：所有 I/O 都在 `_append()` 里被守卫，任何
## 失败只打印一次 `INPUT_LOG_ERROR` 并把本会话的后续写入整体短路；不弹窗、不重试、
## 不抛异常。2 MB 轮转保证长时间测试不需要手动清理，只丢最旧的一半。
##
## 日志只包含：按钮索引 / canonical 名 / 轴索引 / 轴值 / 设备号 / 毫秒时间戳。
## 不含设备序列号、账号、配置文件内容或任何用户数据（T-04-20）。

const LOG_DIR := "/storage/emulated/0/Android/data/com.fifaskill.trainer/files"
const LOG_PATH := LOG_DIR + "/input_log.txt"
## 2 MiB：静置时每根轴每 16 ms 一行心跳，约两分钟写满；轮转后仍保留最近的一段。
const MAX_BYTES := 2_097_152
## 轴节流：同一轴 |Δ| < 0.02 且距上次写入 < 16 ms 时跳过。按钮边沿永不节流。
const AXIS_MIN_DELTA := 0.02
const AXIS_MIN_INTERVAL_MS := 16

## 打开一次、逐行 flush：安卓外部存储上每个事件都 open/close 太贵，而静置时
## 每根轴 16 ms 仍会写一行心跳，开放句柄是「日志不影响输入」的一部分。
static var _file: FileAccess = null
static var _file_path: String = ""
static var _file_max_bytes: int = 0
static var _error_count: int = 0
## 一旦失败就短路本会话的全部后续写入：故障路径上不再反复 mkdir / open。
static var _failed: bool = false


## 会话头：每次启动一行，把日志按进程分段。`t_ms` 与 `path` 只为套件注入，
## 生产调用只传版本号。
static func start_session(version: String, t_ms: int = -1, path: String = "") -> void:
	reset()
	var stamp := t_ms if t_ms >= 0 else now_ms()
	_emit("# session v=%s t=%d mono" % [version, stamp], path)


## 按键边沿（按下 / 松开各一条）。`name` 是 canonical 名（A/B/X/Y/LB/RB/DPAD_*）。
static func button(t_ms: int, device: int, index: int, name: String, down: bool) -> void:
	_emit(format_button(t_ms, device, index, name, down))


## 轴值。调用方负责节流判据（`axis_should_log`）；本函数不做任何跳过。
static func axis(t_ms: int, device: int, index: int, value: float) -> void:
	_emit(format_axis(t_ms, device, index, value))


## 纯函数：日志行的唯一格式真源，套件逐字断言。
static func format_button(t_ms: int, device: int, index: int, name: String, down: bool) -> String:
	return "t=%d dev=%d btn=%d name=%s down=%d" % [t_ms, device, index, name, 1 if down else 0]


static func format_axis(t_ms: int, device: int, index: int, value: float) -> String:
	return "t=%d dev=%d axis=%d v=%.3f" % [t_ms, device, index, value]


## 轴节流判据（纯函数）：|Δ| < 0.02 且距上次写入 < 16 ms 时跳过。
## 「距上次写入」指上一次真的写进日志的时间；被跳过的样本不刷新基准，否则静置
## 时永远不会再写心跳行，日志会停在最后一个动作上。
static func axis_should_log(previous_value: float, previous_t_ms: int, value: float,
		t_ms: int) -> bool:
	return absf(value - previous_value) >= AXIS_MIN_DELTA \
		or (t_ms - previous_t_ms) >= AXIS_MIN_INTERVAL_MS


static func now_ms() -> int:
	return Time.get_ticks_msec()


## 轮转目标：`input_log.txt` → `input_log.1.txt`（与主文件同目录、同扩展名）。
static func rotated_path(path: String = "") -> String:
	var target := path if not path.is_empty() else default_path()
	return target.get_basename() + ".1." + target.get_extension()


## 生产路径是 adb 可读的绝对路径；桌面 / 无头开发环境退回 user://，
## 免得每次启动都去 /storage 撞一个与输入无关的 ERROR（安卓分支不受影响）。
static func default_path() -> String:
	return LOG_PATH if OS.get_name() == "Android" else "user://input_log.txt"


## 失败次数（每个会话最多增长一次）。套件用它证明「只记一次」。
static func error_count() -> int:
	return _error_count


## 关闭缓存句柄并清掉失败状态，下一次写入会重新打开。`start_session()` 每次
## 启动调用一次；套件用它隔离用例（删文件前必须先关句柄）。
static func reset() -> void:
	_close_file()
	_error_count = 0
	_failed = false


## 唯一的写日志出口：先镜像到 logcat（文件坏了也还能读），再写文件。
static func _emit(line: String, path: String = "") -> void:
	print("INPUT_EVT " + line)
	_append(line, path)


## 追加一行。`path` / `max_bytes` 只为套件注入，生产路径用常量。
static func _append(line: String, path: String = "", max_bytes: int = MAX_BYTES) -> bool:
	if _failed:
		return false
	var target := path if not path.is_empty() else default_path()
	if not _ensure_open(target, max_bytes):
		return false
	if _file == null:
		return _fail("write", ERR_CANT_OPEN, target)
	_file.seek_end()
	_file.store_string(line + "\n")
	_file.flush()
	return true


## 句柄失效（换路径 / 换阈值 / 上次失败）时重新打开；仍有效时只检查轮转阈值。
static func _ensure_open(target: String, max_bytes: int) -> bool:
	if _file != null and _file_path == target and _file_max_bytes == max_bytes:
		if _file.get_length() > max_bytes:
			return _rotate(target, max_bytes)
		return true
	_close_file()
	var dir_err := DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	if dir_err != OK:
		return _fail("mkdir", dir_err, target)
	# READ_WRITE 在 Godot 里等价于 "r+b"：文件不存在时不会创建（ERR_FILE_NOT_FOUND）。
	# 首次写入必须先用 WRITE 建一个空文件，再换成读写句柄。
	if not FileAccess.file_exists(target):
		var created := FileAccess.open(target, FileAccess.WRITE)
		if created == null:
			return _fail("create", FileAccess.get_open_error(), target)
		created.close()
	var opened := FileAccess.open(target, FileAccess.READ_WRITE)
	if opened == null:
		return _fail("open", FileAccess.get_open_error(), target)
	_file = opened
	_file_path = target
	_file_max_bytes = max_bytes
	if _file.get_length() > max_bytes:
		return _rotate(target, max_bytes)
	return true


## 超过阈值时把前半段写进 `.1`、后半段留在主文件，再继续追加。
## 只会丢最旧的一段；用户不需要在测试中途清空日志。
static func _rotate(target: String, max_bytes: int) -> bool:
	var length := _file.get_length()
	var cut := length / 2
	_file.seek(0)
	var head := _file.get_buffer(cut)
	_file.seek(cut)
	var tail := _file.get_buffer(length - cut)
	_close_file()
	var rotated := FileAccess.open(rotated_path(target), FileAccess.WRITE)
	if rotated == null:
		return _fail("rotate", FileAccess.get_open_error(), target)
	rotated.store_buffer(head)
	rotated.flush()
	rotated.close()
	var current := FileAccess.open(target, FileAccess.WRITE)
	if current == null:
		return _fail("truncate", FileAccess.get_open_error(), target)
	current.store_buffer(tail)
	current.flush()
	current.seek_end()
	_file = current
	_file_path = target
	_file_max_bytes = max_bytes
	return true


## 失败只打印一次；`_failed` 让后续事件零 I/O 直接返回。
static func _fail(stage: String, code: int, target: String) -> bool:
	_error_count += 1
	_failed = true
	if _error_count == 1:
		print("INPUT_LOG_ERROR stage=%s code=%d path=%s" % [stage, code, target])
	return false


static func _close_file() -> void:
	if _file != null:
		_file.close()
	_file = null
	_file_path = ""
	_file_max_bytes = 0
