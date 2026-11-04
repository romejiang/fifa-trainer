extends SceneTree

## 无头多套件 runner：本阶段唯一入口 `godot --headless --path mobile --script res://tests/core_runner.gd`。
##
## 为什么需要它，而不是直接看退出码：Godot 4.7.2 的 --script 有三种失败模式会让
## 退出码骗人 ——
##   1) 解析失败 / class_name 未解析 / 依赖编译失败：打印 SCRIPT ERROR，退出码仍是 0；
##   2) 入口函数运行时错误或 assert 失败：quit() 永远执行不到，进程挂死；
##   3) 套件函数内部运行时错误：只中止当前函数，调用者会继续，返回的「0 失败」
##      看起来完全正常。
## 对策：套件必须打完成标记（complete()），runner 只在看到 `TESTS_DONE failures=0`
## 哨兵时才判过；外壳 test-core.sh 另有看门狗处理第 2 种。三者缺一都是假绿。
##
## 测试脚本不加 class_name：避免污染全局命名空间，也避免被打进导出包。
## SUITES 必须是显式 preload 的字典，不要改成运行时扫描目录 —— preload 失败会让
## runner 自己编译失败（于是没有哨兵，闸门必红）；扫描目录在目录消失时会
## 「零套件、零失败」地绿，那正是本阶段要防的假绿。


## 断言收集器。为什么把失败累积起来而不是 fail-fast：一次跑完才能看到全部问题。
class Reporter extends RefCounted:
	var assertions := 0
	var failures: Array[String] = []
	var completed: Array[String] = []
	var _suite := ""

	func begin(suite: String) -> void:
		_suite = suite

	func check(ok: bool, label: String) -> void:
		assertions += 1
		if not ok:
			failures.append("%s: %s" % [_suite, label])

	## 浮点比较的唯一入口：失败消息同时打印实际值、期望值与容差，避免二次调试。
	func eq_float(actual: float, expected: float, tol: float, label: String) -> void:
		check(absf(actual - expected) <= tol,
			"%s（实际 %.17f，期望 %.17f，容差 %s）" % [label, actual, expected, str(tol)])

	## 每个套件 run() 的最后一句必须是它；缺失即视为崩溃。
	func complete() -> void:
		completed.append(_suite)


const SUITES := {
	"config_corpus": preload("res://tests/unit/test_config_corpus.gd"),
	"config_loader": preload("res://tests/unit/test_config_loader.gd"),
	"config_store": preload("res://tests/unit/test_config_store.gd"),
	"config_validator": preload("res://tests/unit/test_config_validator.gd"),
	"geometry": preload("res://tests/unit/test_geometry.gd"),
	"models": preload("res://tests/unit/test_models.gd"),
	"overlay_merge": preload("res://tests/unit/test_overlay_merge.gd"),
	"vocabulary": preload("res://tests/unit/test_vocabulary.gd"),
}


func _initialize() -> void:
	var r := Reporter.new()
	var suite_names: Array = SUITES.keys()
	suite_names.sort()
	for suite_name in suite_names:
		r.begin(suite_name)
		SUITES[suite_name].new().run(r)
		if not r.completed.has(suite_name):
			# 运行时错误只中止套件函数，调用者会继续；「没走完」是唯一可靠的崩溃信号。
			r.check(false, "套件提前中止（运行时错误 / assert 失败），断言未全部执行")
	for failure in r.failures:
		printerr("TESTS_FAIL " + failure)
	print("TESTS_SUITES=%d" % SUITES.size())
	print("TESTS_ASSERTIONS=%d" % r.assertions)
	print("TESTS_DONE failures=%d" % r.failures.size())
	if r.failures.is_empty():
		quit(0)
	else:
		quit(1)
