class_name Failure
extends RefCounted

## 一次「认出了手势、但没做对」的裁定：与 desktop/padskills/detectors.py:49-58 对齐。
##
## `code` 是给程序看的（统计用），`message` 是给用户看的一行中文，`elapsed_ms`
## 是这次尝试的实测时长。不搬 Python 侧的 `json_path` / `fix_hint` / `severity`：
## 那些属于配置错误（ConfigError），不是判定失败。
##
## 失败只做文字反馈，绝不触发震动 —— 震动只代表「做对了」。

var code: StringName = &""
var message: String = ""
var elapsed_ms: float = 0.0


func _init(p_code: StringName = &"", p_message := "", p_elapsed_ms := 0.0) -> void:
	code = p_code
	message = p_message
	elapsed_ms = p_elapsed_ms
