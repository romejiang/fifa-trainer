## 手柄摇杆指示器：一个圆 + 十字准星 + 蓝红两根指针。
##
## 只负责画，不读设备；`set_values()` 由 HomeScreen 每帧调用。坐标是已归一化的
## SDL 约定（x 右正、y 下正），所以指针位置可以直接映射到圆心 + value * 半径。
## 左摇杆用蓝色指针、右摇杆用红色指针，共用一个圆圈，像时钟一样。
class_name StickIndicator
extends Control

## 左摇杆值，范围 [-1, 1]。零 = 回中。
var _ls := Vector2.ZERO
## 右摇杆值，范围 [-1, 1]。零 = 回中。
var _rs := Vector2.ZERO

## 指针圆点半径（像素）。
const DOT_RADIUS := 5.0
const COLOR_LS := Color("#0A84FF")
const COLOR_RS := Color("#FF3B30")


func set_values(ls: Vector2, rs: Vector2) -> void:
	var next_ls := Vector2(clampf(ls.x, -1.0, 1.0), clampf(ls.y, -1.0, 1.0))
	var next_rs := Vector2(clampf(rs.x, -1.0, 1.0), clampf(rs.y, -1.0, 1.0))
	if next_ls.is_equal_approx(_ls) and next_rs.is_equal_approx(_rs):
		return
	_ls = next_ls
	_rs = next_rs
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - 3.0
	if radius <= 0.0:
		return
	draw_circle(center, radius, Color("#FAFAFC"))
	draw_arc(center, radius, 0.0, TAU, 64, Color("#DCDCE2"), 1.2, true)
	draw_arc(center, radius * 0.68, 0.0, TAU, 48, Color("#E6E6EB"), 1.0, true)
	draw_line(center + Vector2(-radius, 0), center + Vector2(radius, 0),
		Color("#D3D3DA"), 1.2, true)
	draw_line(center + Vector2(0, -radius), center + Vector2(0, radius),
		Color("#D3D3DA"), 1.2, true)
	# 12 点刻度，确定「上」的方向。
	draw_line(center + Vector2(0, -radius * 0.80), center + Vector2(0, -radius * 0.62),
		Color("#B9B9C1"), 2.0, true)
	_draw_needle(center, radius, _ls, COLOR_LS, true)
	_draw_needle(center, radius, _rs, COLOR_RS, false)
	draw_circle(center, 3.0, Color("#B9B9C1"))


## 一根指针：从圆心到摇杆位置，末端一个圆点。
##
## 左摇杆画实心点、右摇杆画描边点：两根回中重叠时仍能看出是一蓝一红两个指针，
## 而不是被后画的那个完全盖住。
func _draw_needle(center: Vector2, radius: float, value: Vector2, color: Color,
		filled: bool) -> void:
	var reach := radius * 0.62
	var tip := center + Vector2(value.x, value.y) * reach
	draw_line(center, tip, Color(color, 0.5), 2.0, true)
	if filled:
		draw_circle(tip, DOT_RADIUS + 2.0, color)
		return
	draw_circle(tip, DOT_RADIUS, Color.WHITE)
	draw_arc(tip, DOT_RADIUS, 0.0, TAU, 24, color, 2.4, true)
	draw_circle(tip, 1.8, color)
