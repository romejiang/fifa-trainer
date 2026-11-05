class_name FrameBuilder
extends RefCounted

## raw 轴 → `Frame` 的**唯一**换算入口：减中点、除量程、死区、角度。
##
## 为什么必须只有这一处：`AxisMapping.snapshot_rs()` / `snapshot_ls()` 已经把
## 「两次 normalize → deadzone」抽成唯一实现；如果组合根再手写一份「减中点除量程」，
## App 与黄金夹具就会看到不同的角度，而且那种分叉不会让任何现有测试变红
## （T-05-23）。`main.gd` 只准调用本类，不准直接碰 `Calibration.normalize`。
##
## 分工写死：
##   * 本类**只写四个字段**：`rs_angle` / `rs_mag` / `ls_angle` / `ls_mag`；
##   * `facing` 由引擎每帧写入（`GestureEngine.tick()`），本类一字不碰；
##   * 按钮由调用方填 `frame.buttons`，本类不读按钮、不读时钟、不做 I/O。
##
## **null 契约**：`mapping == null` 或 `calibration == null`（无档案 / 档案残缺）时，
## 四个字段全部写 0，绝不抛错、绝不降级校准。「无档案 = 无输入」与「有档案但没推到」
## 在检测器眼里是同一件事：四个字段都是 0，相对左摇杆的技能保持 inert（T-05-27b）。
## 显式早退而不是依赖 `snapshot_*` 已有的 null 判断，是为了让这条语义不随被调方
## 的实现细节漂移。
##
## 时间单位与 `Frame` 一致：`now` 是秒，由调用方注入（core 不读时钟）。


## 把 raw 轴灌进一帧。调用方负责 `frame.now` / `frame.buttons` 与 `facing` 的最终归属。
static func fill(frame: Frame, raw: PackedFloat32Array, mapping: AxisMapping,
		calibration: Calibration, deadzone: float) -> void:
	# 无档案：四个字段一律 0。不抛错、不猜、不用默认校准补。
	if mapping == null or calibration == null:
		frame.rs_angle = 0.0
		frame.rs_mag = 0.0
		frame.ls_angle = 0.0
		frame.ls_mag = 0.0
		return
	var rs := AxisMapping.snapshot_rs(raw, mapping, calibration, deadzone)
	var ls := AxisMapping.snapshot_ls(raw, mapping, calibration, deadzone)
	# 角度约定只有 `Geometry` 一处：0° 上、90° 右、顺时针为正。
	frame.rs_angle = Geometry.angle_of(rs.x, rs.y)
	frame.rs_mag = Geometry.magnitude(rs.x, rs.y)
	frame.ls_angle = Geometry.angle_of(ls.x, ls.y)
	frame.ls_mag = Geometry.magnitude(ls.x, ls.y)


## 无头测试与工具箱用的构造函数：`fill()` 加时间与按钮，等价于组合根每帧做的事。
## `now` 显式传入而不是在这里读时钟 —— core 的时钟一律由调用方注入。
static func make(raw: PackedFloat32Array, mapping: AxisMapping,
		calibration: Calibration, deadzone: float, now: float,
		buttons: Dictionary = {}) -> Frame:
	var frame := Frame.new()
	frame.now = now
	frame.buttons = buttons
	fill(frame, raw, mapping, calibration, deadzone)
	return frame
