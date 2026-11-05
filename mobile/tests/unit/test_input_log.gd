extends RefCounted

## `InputLog` 的无头套件：格式、会话头、时间戳单调、轴节流边界、轮转、错误路径。
##
## 只碰纯函数与 `_append()` 的注入路径（`path` / `max_bytes`），不构造 `PadSampler`、
## 不碰 `Input`、不写真实的安卓路径。日志格式是 UI 与验收表的共同契约，必须逐字断言。
##
## 用例顺序有约束：错误路径会把 `_failed` 置位并短路后续写入，所以**必须最后跑**；
## 它自己也以 `InputLog.reset()` 收尾，不给后面的套件留状态。

const TEST_DIR := "user://test_input_log"
const TEST_PATH := TEST_DIR + "/input_log.txt"


func run(r) -> void:
	_check_format(r)
	_check_append_and_session(r)
	_check_throttle_boundaries(r)
	_check_constants(r)
	_check_rotation(r)
	_check_error_path(r)
	r.complete()


## 两种行的格式是契约：`t=<ms> dev=<d> btn=<i> name=<n> down=<0|1>` /
## `t=<ms> dev=<d> axis=<i> v=<x.xxx>`。任何字段顺序或小数位变化都会让
## `adb exec-out cat` 的读者对不上号。
func _check_format(r) -> void:
	r.check(InputLog.format_button(1234, 0, 0, "A", true)
			== "t=1234 dev=0 btn=0 name=A down=1",
		"按下 A 的行必须逐字是 t=1234 dev=0 btn=0 name=A down=1")
	r.check(InputLog.format_button(1235, 1, 1, "B", false)
			== "t=1235 dev=1 btn=1 name=B down=0",
		"松开 B 的行必须逐字是 t=1235 dev=1 btn=1 name=B down=0")
	r.check(InputLog.format_axis(1234, 0, 2, 0.5)
			== "t=1234 dev=0 axis=2 v=0.500",
		"轴行必须有三位小数：v=0.500")
	r.check(InputLog.format_axis(1235, 0, 2, -1.0)
			== "t=1235 dev=0 axis=2 v=-1.000",
		"负值必须保留短横且三位小数：v=-1.000")
	r.check(InputLog.format_axis(1236, 0, 7, 0.0)
			== "t=1236 dev=0 axis=7 v=0.000",
		"零值必须写成 0.000，不能省略小数位")


## 端到端：会话头 + 两种事件真的落进文件、以换行分隔、时间戳递增。
func _check_append_and_session(r) -> void:
	_clean()
	InputLog.start_session("0.1.0", 1000, TEST_PATH)
	InputLog._append(InputLog.format_button(1001, 0, 0, "A", true), TEST_PATH)
	InputLog._append(InputLog.format_axis(1002, 0, 2, -0.25), TEST_PATH)
	var lines := _read_lines(TEST_PATH)
	r.check(lines.size() == 3,
		"会话头 + 两条事件必须正好三行（实际 %d 行：%s）" % [lines.size(), str(lines)])
	if lines.size() == 3:
		r.check(lines[0] == "# session v=0.1.0 t=1000 mono",
			"第一行必须是会话头（实际 %s）" % lines[0])
		r.check(lines[1] == "t=1001 dev=0 btn=0 name=A down=1",
			"第二行必须是 A 的按下边沿（实际 %s）" % lines[1])
		r.check(lines[2] == "t=1002 dev=0 axis=2 v=-0.250",
			"第三行必须是轴 2 的值（实际 %s）" % lines[2])
		r.check(_line_t(lines[0]) < _line_t(lines[1])
				and _line_t(lines[1]) < _line_t(lines[2]),
			"文件里的时间戳必须单调递增（%d / %d / %d）" % [
				_line_t(lines[0]), _line_t(lines[1]), _line_t(lines[2])])
	r.check(InputLog.now_ms() <= InputLog.now_ms(),
		"now_ms() 必须非递减（单调时钟）")
	InputLog.reset()


## 节流边界：|Δ| < 0.02 且 < 16 ms 才跳过；任一条件达到就写。
func _check_throttle_boundaries(r) -> void:
	r.check(not InputLog.axis_should_log(0.0, 100, 0.0, 108),
		"同值且间隔 8 ms 必须跳过")
	r.check(not InputLog.axis_should_log(0.0, 100, 0.01, 108),
		"Δ=0.01 且间隔 8 ms 必须跳过")
	r.check(not InputLog.axis_should_log(0.0, 100, -0.019, 115),
		"Δ=0.019 且间隔 15 ms 必须跳过")
	r.check(InputLog.axis_should_log(0.0, 100, 0.01, 116),
		"间隔正好 16 ms 必须写")
	r.check(InputLog.axis_should_log(0.0, 100, 0.02, 101),
		"Δ 正好 0.02 必须写")
	r.check(InputLog.axis_should_log(0.0, 100, -0.02, 101),
		"Δ 正好 -0.02 必须写")
	r.check(InputLog.axis_should_log(0.0, 100, 0.5, 101),
		"大变化在 1 ms 内也必须写")
	r.check(InputLog.axis_should_log(0.0, 100, 0.0, 500),
		"静置超过 16 ms 也必须写心跳行")


## 常量与轮转路径：2 MiB 是验收表写明的阈值，路径必须与 adb 命令逐字一致。
func _check_constants(r) -> void:
	r.check(InputLog.LOG_PATH
			== "/storage/emulated/0/Android/data/com.fifaskill.trainer/files/input_log.txt",
		"LOG_PATH 必须是 adb 可读的绝对路径（实际 %s）" % InputLog.LOG_PATH)
	r.check(InputLog.MAX_BYTES == 2_097_152,
		"MAX_BYTES 必须是 2 MiB（实际 %d）" % InputLog.MAX_BYTES)
	r.check(InputLog.rotated_path(InputLog.LOG_PATH)
			== "/storage/emulated/0/Android/data/com.fifaskill.trainer/files/input_log.1.txt",
		"轮转目标必须是 input_log.1.txt（实际 %s）" % InputLog.rotated_path(InputLog.LOG_PATH))
	r.check(InputLog.AXIS_MIN_DELTA == 0.02,
		"轴节流最小变化必须是 0.02（实际 %s）" % str(InputLog.AXIS_MIN_DELTA))
	r.check(InputLog.AXIS_MIN_INTERVAL_MS == 16,
		"轴节流最小间隔必须是 16 ms（实际 %d）" % InputLog.AXIS_MIN_INTERVAL_MS)


## 轮转：> 阈值时前半段进 `.1`、后半段留在主文件；只丢最旧的一半。
## 用 40 字节阈值而不是真的写 2 MB：判的是同一段代码，不是磁盘速度。
func _check_rotation(r) -> void:
	_clean()
	_ensure_dir()
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	r.check(file != null, "必须先能创建轮转用例的临时文件")
	if file == null:
		return
	file.store_string("AAAAAAAAAA")
	file.store_string("BBBBBBBBBB")
	file.store_string("CCCCCCCCCC")
	file.store_string("DDDDDDDDDD")
	file.store_string("EEEEEEEEEE")
	file.close()
	r.check(FileAccess.file_exists(TEST_PATH), "轮转前主文件必须存在")

	r.check(InputLog._append("tail", TEST_PATH, 40),
		"超过阈值后的追加必须成功（并触发轮转）")
	var rotated := InputLog.rotated_path(TEST_PATH)
	r.check(FileAccess.file_exists(rotated),
		"轮转必须生成 %s" % rotated)
	r.check(_read_text(rotated) == "AAAAAAAAAABBBBBBBBBBCCCCC",
		"轮转文件必须是原文件的前半段（实际 %s）" % _read_text(rotated))
	r.check(_read_text(TEST_PATH) == "CCCCCDDDDDDDDDDEEEEEEEEEEtail\n",
		"主文件必须保留后半段并追加新行（实际 %s）" % _read_text(TEST_PATH))
	InputLog.reset()


## 错误路径：不可写目录必须返回 false、不抛、只记一次；后续写入被整体短路。
func _check_error_path(r) -> void:
	_clean()
	var bad := "/dev/null/input_log.txt"
	r.check(not InputLog._append("x", bad),
		"不可写路径的第一次写入必须返回 false（不抛异常）")
	r.check(not InputLog._append("y", bad),
		"不可写路径的第二次写入也必须返回 false（不重试）")
	r.check(InputLog.error_count() == 1,
		"失败只能记一次（实际 %d）" % InputLog.error_count())
	InputLog.reset()
	r.check(InputLog.error_count() == 0, "reset() 必须清掉失败计数")
	_clean()


static func _line_t(line: String) -> int:
	# 会话头与事件行都以 `t=<数字>` 结尾或出现在中段，这里只取第一处。
	var start := line.find("t=")
	if start < 0:
		return -1
	var rest := line.substr(start + 2)
	var end := 0
	while end < rest.length() and rest[end] >= "0" and rest[end] <= "9":
		end += 1
	if end == 0:
		return -1
	return int(rest.substr(0, end))


static func _read_lines(path: String) -> PackedStringArray:
	return _read_text(path).split("\n", false)


static func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


static func _ensure_dir() -> void:
	DirAccess.make_dir_recursive_absolute(TEST_DIR)


static func _clean() -> void:
	InputLog.reset()
	for path in [TEST_PATH, InputLog.rotated_path(TEST_PATH)]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
