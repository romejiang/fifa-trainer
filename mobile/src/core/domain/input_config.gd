class_name InputConfig
extends RefCounted

## 手柄读取参数：与 desktop/padskills/config.py:226-241 的 `InputConfig` 逐字段同默认值。
##
## 共 12 个字段，一个不多一个不少 —— 缺一个字段就等于有一个默认值没人钉住，而「桌面能跑、
## 移动端报错」正是这类缺省不一致造成的。数量与逐字段默认值都由 test_models.gd 断言。
##
## axis_layout / button_names 用 Variant 而不是空字典：Python 那边是 `Optional[Dict]`，
## `null` 表示「自动推断」，`{}` 表示「手动覆盖但一条都没写」—— 两者语义不同，不能合并。
##
## invert 的四个合法键是 ls_x / ls_y / rs_x / rs_y。SDL 的映射表偶尔和实物对不上，
## 这是「不写死整套 axis_layout 就能纠正上下反了」的开关。键白名单与布尔值检查在
## ConfigValidator，本类只承载已校验的数据。

var poll_hz: int = 250
var deadzone: float = 0.08
## 超过这个幅度才更新「球员面朝方向」；低于它等于没有面朝，相对方向的动作用不了。
var ls_facing_threshold: float = 0.35
var initial_facing_deg: float = 0.0
## 扳机按到多深算「按下」。
var trigger_threshold: float = 0.35
var joystick_index: int = 0
## null = 自动推断轴布局；`{}` = 手动覆盖但为空。不要用空字典代替 null。
var axis_layout: Variant = null
var invert: Dictionary = {}
## null = 自动推断按键索引；语义同 axis_layout。
var button_names: Variant = null
## 启动时扳机静止值的采样时长。
var calibration_ms: int = 250
## 右摇杆静止这么久之后，清空未完成的动作。
var idle_reset_ms: int = 250
## 一次触发后，回中这么久才允许下一个动作。
var gesture_release_ms: int = 150
