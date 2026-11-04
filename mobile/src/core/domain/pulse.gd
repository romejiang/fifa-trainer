class_name Pulse
extends RefCounted

## 一次震动：与 desktop/padskills/config.py:196-202 的 `Pulse` 逐字段同默认值。
##
## low  = 低频大马达（手柄左侧），high = 高频小马达（右侧），取值 0.0 ~ 1.0。
## duration_ms 是这一次震动持续多久，gap_ms 是它之后到下一次震动之间的停顿。
##
## 为什么保留桌面语义：Phase 10 在安卓上只有 vibrate_handheld()（震手机本体），
## 「震哪一侧」无从表达，但配置里写的 low / high 必须原样保存 —— 否则桌面版与移动端
## 的 rumble_summary() 文案会对不上，而那段文案是用户在设置界面看到的东西。
##
## 本类只承载已校验的数据：范围检查在 ConfigValidator，不在这里。

var low: float = 0.8
var high: float = 0.0
var duration_ms: int = 120
var gap_ms: int = 0


func _init(p_low := 0.8, p_high := 0.0, p_duration_ms := 120, p_gap_ms := 0) -> void:
	low = p_low
	high = p_high
	duration_ms = p_duration_ms
	gap_ms = p_gap_ms
