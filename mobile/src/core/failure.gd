class_name Failure
extends RefCounted

## 一次「认出了手势、但没做对」的裁定：与 desktop/padskills/detectors.py:49-58 对齐。
##
## `code` 是给程序看的（统计用），`message` 是给用户看的一行中文，`elapsed_ms`
## 是这次尝试的实测时长。不搬 Python 侧的 `json_path` / `fix_hint` / `severity`：
## 那些属于配置错误（ConfigError），不是判定失败。
##
## 失败只做文字反馈，绝不触发震动 —— 震动只代表「做对了」。
##
## `measured` 是 JUDGE-05 的结构化度量（RESEARCH §D.5 的字段表）：与 `Hit.measured`
## 同构，失败时额外带 `fail{code, end_rel_deg, nearest_target_deg, distance_deg,
## tolerance_deg}`（弧线）或与失败相关的现场量。它**只在检测器产生 Failure 的那一刻**
## 由检测器构造；UI 与日志只读，不得从 `message` 里正则抠数字重建。
##
## 位置参数顺序不变：`measured` 只能加在末尾并给默认值，Phase 4 的全部位置调用
## （`Failure.new(code, message, elapsed)`）必须一字不改地继续编译。

var code: StringName = &""
var message: String = ""
var elapsed_ms: float = 0.0
var measured: Dictionary = {}


func _init(p_code: StringName = &"", p_message := "", p_elapsed_ms := 0.0,
		p_measured: Dictionary = {}) -> void:
	code = p_code
	message = p_message
	elapsed_ms = p_elapsed_ms
	measured = p_measured
