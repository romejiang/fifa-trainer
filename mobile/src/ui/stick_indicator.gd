## 手柄摇杆指示器：一个圆 + 十字准星 + 跟手的小点。
##
## 只负责画，不读设备；`set_value()` 由 HomeScreen 每帧调用。坐标是已归一化的
## SDL 约定（x 右正、y 下正），所以小点位置可以直接映射到圆心 + value * 半径。
class_name StickIndicator
extends Control

## 当前摇杆值，范围 [-1, 1]。零 = 回中。
var _value := Vector2.ZERO
## 小点半径（像素）。
const DOT_RADIUS := 5.0


func set_value(value: Vector2) -> void:
	var clamped := Vector2(clampf(value.x, -1.0, 1.0), clampf(value.y, -1.0, 1.0))
	if clamped.is_equal_approx(_value):
		return
	_value = clamped
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - 2.0
	if radius <= 0.0:
		return
	draw_circle(center, radius, Color("#FAFAFC"))
	draw_arc(center, radius, 0.0, TAU, 64, Color("#DCDCE2"), 1.2, true)
	draw_arc(center, radius * 0.68, 0.0, TAU, 48, Color("#E6E6EB"), 1.0, true)
	draw_line(center + Vector2(-radius, 0), center + Vector2(radius, 0), Color("#D3D3DA"), 1.2, true)
	draw_line(center + Vector2(0, -radius), center + Vector2(0, radius), Color("#D3D3DA"), 1.2, true)
	draw_line(center + Vector2(0, -radius * 0.72), center + Vector2(0, -radius * 0.28),
		Color("#B9B9C1"), 1.8, true)
	var dot := center + Vector2(_value.x, _value.y) * (radius * 0.62)
	draw_circle(dot, DOT_RADIUS, Color("#FFFFFF"))
	draw_arc(dot, DOT_RADIUS, 0.0, TAU, 24, Color("#1D1D1F"), 1.2, true)
	draw_circle(dot, 2.0, Color(0.11, 0.11, 0.12, 0.55))
