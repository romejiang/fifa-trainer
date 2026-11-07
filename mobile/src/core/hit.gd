class_name Hit
extends RefCounted

## 一次成功识别：与 desktop/padskills/detectors.py:40-46 的 `Hit` 逐字段对齐。
##
## `summary` / `detail` 由检测器在构造现场产生（detectors.py:990-991），黄金夹具
## 逐字比对这两个字符串。UI 只能显示它们，不得重新拼装 —— 否则「与桌面版一致」
## 就悄悄变成了「与 UI 作者的理解一致」。
##
## `elapsed_ms` 是这次尝试的实测时长；`summary` 是简短参数摘要（日志/GUI 用一行），
## `detail` 是完整文案（含修饰键说明）。
##
## `measured` 是 JUDGE-05 的结构化度量（RESEARCH §D.5 的字段表）：起止角、扫掠角、
## 耗时、样本数、目标区间。它**只在检测器产生 Hit 的那一刻**由检测器构造，数值全部
## 来自判定现场的局部量；UI 与日志只读，不得从 `summary` / `detail` 里正则抠数字
## 重建（那会在改文案时静默失效，形成两套判定真相）。
##
## 位置参数顺序不变：`measured` 只能加在末尾并给默认值，Phase 4 的全部位置调用
## （`Hit.new(elapsed, detail, summary)`）必须一字不改地继续编译。

var elapsed_ms: float = 0.0
var detail: String = ""
var summary: String = ""
var measured: Dictionary = {}


func _init(p_elapsed_ms := 0.0, p_detail := "", p_summary := "",
		p_measured: Dictionary = {}) -> void:
	elapsed_ms = p_elapsed_ms
	detail = p_detail
	summary = p_summary
	measured = p_measured
