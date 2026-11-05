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

var elapsed_ms: float = 0.0
var detail: String = ""
var summary: String = ""


func _init(p_elapsed_ms := 0.0, p_detail := "", p_summary := "") -> void:
	elapsed_ms = p_elapsed_ms
	detail = p_detail
	summary = p_summary
