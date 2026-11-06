extends Control

## 竖屏主界面（`design/mobile.html` 的落地版）：只读运行时，不推进判定。
##
## 三条边界与练习屏同源，违反任何一条都会让「一次尝试一条判定」变成假绿：
##   1. **判定推进点唯一**：`GestureEngine` 只在组合根（`main.gd`）里被推进；
##      本屏只消费 `pop_outcomes()` 的结果队列，并且是**唯一**的 drain 点。
##   2. **结果全量 drain**：每帧把队列取空、逐条写 `InputLog.outcome(...)`，再更新
##      英雄卡与最近尝试列表。日志必须写在显示之前（D5-2/D5-3 的核对顺序）。
##   3. **文案来自判定**：成功显示 `Outcome.detail`、失败显示 `Outcome.message`，
##      本屏不重组原因字符串。只有静态标签（标题、分组名）由布局决定。
##
## 注入顺序：`_ready()` 只缓存 `@onready` 节点；依赖一律从 `setup(runtime, layout,
## buffer)` 进入。先 `add_child` 再 `setup` 是常态，子节点的 `_ready` 早于组合根。
##
## 交互仍然是手柄：十字键上下切换聚焦动作（只影响显示，不影响判定），B 按住 1 秒
## 回输入设置页由组合根处理。本屏没有任何触摸控件。
##
## 刷新节流：`Label.text` 赋值触发文本整形，60 Hz 下是全帧最贵的操作；定时器每秒
## 只写一次，列表与摇杆读数收在同一个 10 Hz 节流块内。

## 10 Hz：够读清摇杆与计数，也不会让文本整形占满一帧。
const REFRESH_SECONDS := 0.1
## 最近的尝试只保留最近 8 条（设计稿的「保留 8 / 50 条」）。
const ATTEMPT_LIMIT := 8
## 熟练度进度条的目标次数（设计稿的 10 次目标）。
const SKILL_TARGET := 10
## 十字键上下的 canonical 名称与 Godot 按钮枚举一一对应。
const KEY_DPAD_UP := JoyButton.JOY_BUTTON_DPAD_UP
const KEY_DPAD_DOWN := JoyButton.JOY_BUTTON_DPAD_DOWN

## 设计 token（design/mobile.html 的 :root 变量）。
const COLOR_TEXT := Color("#1D1D1F")
const COLOR_TEXT_2 := Color("#6E6E73")
const COLOR_TEXT_3 := Color("#8E8E93")
const COLOR_SUCCESS := Color("#34C759")
const COLOR_FAILURE := Color("#FF3B30")
const COLOR_ACCENT := Color("#007AFF")
const COLOR_GREEN_DEEP := Color("#068A36")
const COLOR_ORANGE := Color("#C2410C")

@onready var _status_text: Label = %StatusText
@onready var _title: Label = %Title
@onready var _timer: Label = %Timer
@onready var _device: Label = %Device
@onready var _hero: PanelContainer = %Hero
@onready var _hero_name: Label = %HeroName
@onready var _hero_en: Label = %HeroEn
@onready var _hero_state: Label = %HeroState
@onready var _hero_ms: Label = %HeroMs
@onready var _hero_tip: Label = %HeroTip
@onready var _hero_hint: Label = %HeroHint
@onready var _skills: VBoxContainer = %Skills
@onready var _attempts: VBoxContainer = %Attempts
@onready var _pad: PanelContainer = %Pad
@onready var _pad_text: Label = %PadText

var _runtime: GestureEngine = null
var _buffer: PadStateBuffer = null
var _layout: StringName = &""
## 本次练习时长（秒）。从 `setup()` 起算，只用于顶部计时。
var _elapsed: float = 0.0
## 10 Hz 刷新累加器。
var _accum: float = 0.0
## 上一次写进 `%Timer` 的整串文本；相同就跳过赋值。
var _last_timer_text: String = ""


func _ready() -> void:
	pass


## 依赖唯一入口。组合根进入练习时调用；本屏不读设备、不推进判定。
func setup(p_runtime: GestureEngine, p_layout: StringName, p_buffer: PadStateBuffer) -> void:
	_runtime = p_runtime
	_layout = p_layout
	_buffer = p_buffer
	_elapsed = 0.0
	# 让第一次 `_process` 立刻刷新，而不是先空等 0.1 秒。
	_accum = REFRESH_SECONDS
	_title.text = "花式练习"
	_status_text.text = "训练中"
	_refresh_header()
	_refresh_pad()
	_refresh_timer()


func _process(delta: float) -> void:
	if not visible:
		return
	_elapsed += delta
	_refresh_timer()
	_accum += delta
	if _accum < REFRESH_SECONDS:
		return
	_accum = 0.0
	_refresh_header()
	_refresh_pad()


## 顶部设备行与状态 pill：布局 + 连接状态决定，不读设备名。
func _refresh_header() -> void:
	var connected := _buffer != null and _buffer.device >= 0
	_status_text.text = "训练中" if connected else "等待手柄"
	_device.text = device_line(_layout, connected)


func _refresh_timer() -> void:
	var text := clock_text(_elapsed)
	if text == _last_timer_text:
		return
	_last_timer_text = text
	_timer.text = text


## 底部手柄状态卡：左/右摇杆当前原始值与连接状态。
func _refresh_pad() -> void:
	var connected := _buffer != null and _buffer.device >= 0
	var ls := Vector2.ZERO
	var rs := Vector2.ZERO
	if _buffer != null:
		ls = Vector2(_buffer.axis_value(0), _buffer.axis_value(1))
		rs = Vector2(_buffer.axis_value(2), _buffer.axis_value(3))
	_pad_text.text = pad_text(connected, ls, rs)


## 秒数 → `MM:SS`。超过 99 分钟只保留分钟位（练习不会那么久）。
static func clock_text(seconds: float) -> String:
	var whole := int(maxf(0.0, seconds))
	return "%02d:%02d" % [whole / 60, whole % 60]


## 顶部设备行：布局名 + 连接状态。空布局不回退到 Xbox 字样。
static func device_line(layout: StringName, connected: bool) -> String:
	var brand := ""
	match layout:
		&"xbox":
			brand = "Xbox 手柄"
		&"playstation":
			brand = "PlayStation 手柄"
	if not connected:
		return "手柄未连接 · 打开电源后自动连接"
	if brand.is_empty():
		return "手柄已连接 · 标准映射"
	return brand + " · 手柄已连接"


## 底部摇杆行：连接状态 + 左/右摇杆原始值 + 是否回中。
static func pad_text(connected: bool, ls: Vector2, rs: Vector2) -> String:
	if not connected:
		return "手柄未连接"
	var ls_state := "回中" if ls.length() < 0.2 else "%.2f / %.2f" % [ls.x, ls.y]
	var rs_state := "回中" if rs.length() < 0.2 else "%.2f / %.2f" % [rs.x, rs.y]
	return "手柄已连接　左摇杆 %s　右摇杆 %s" % [ls_state, rs_state]
