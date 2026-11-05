extends Control

## 练习屏 S12–S14 的渲染器：只读运行时，不推进判定。
##
## 三条边界，违反任何一条都会让「一次尝试一条判定」变成假绿：
##   1. **判定推进点唯一**：`GestureEngine` 只在组合根（`main.gd`）里被推进；本屏只消费
##      引擎的结果队列。这里既不读设备、也不读按钮边沿数组 —— 同一次按下不能有
##      第二个解释者。**日志与横幅在本屏同一个 drain 循环里**：先写 `OUTCOME` 行、
##      再交给横幅，两个消费者共用同一次取走的结果，`main.gd` 里没有第二个 drain。
##   2. **结果全量 drain**：每帧把队列取空、逐条交给横幅。假设「最多一条」会在
##      同帧两条时静默丢掉一条；队列是结构，不是约定。
##   3. **文案来自判定**：成功显示 `Outcome.detail`、失败显示 `Outcome.message`，
##      本屏不重组原因字符串。`%Hint` 是唯一由布局决定的静态文案，三支：Xbox /
##      PlayStation / 空布局错误态 —— 空布局绝不回退到 Xbox 键名。
##
## 注入顺序：`_ready()` 只缓存 `@onready` 节点；依赖一律从 `setup(runtime, layout,
## buffer)` 进入。先 `add_child` 再 `setup` 是常态，子节点的 `_ready` 早于组合根。
##
## 可见性：`_process` 的第一句是 `if not visible: return`。组合根进入练习时必须把
## **容器与练习屏自身都**置为可见；只显示容器会让 drain、横幅与 `%DebugPanel`
## 全部停在屏幕外。
##
## 刷新节流：`Label.text` 赋值触发文本整形，60 Hz 下是全帧最贵的操作；`%LiveMs`、
## `%SuccessCount`、`%DebugPanel` 全部收在同一个 10 Hz 节流块内，并在值未变化时跳过。

## 10 Hz：够读清实时毫秒，也不会让文本整形占满一帧。
const LIVE_REFRESH_SECONDS := 0.1
const HINT_PLAYSTATION := "按住 R1，连按两下 □\n按住 B 1 秒返回设置"
const HINT_XBOX := "按住 RB，连按两下 X\n按住 B 1 秒返回设置"
const HINT_NO_LAYOUT := "布局未确认，请返回引导重选\n按住 B 1 秒返回设置"
## 检测器在未起手时返回这个字面量；屏上不显示设备面板黑话，显示「等待第一下」。
const IDLE_STATUS := "待机"
const IDLE_DISPLAY := "等待第一下"

@onready var _action_name: Label = %ActionName
@onready var _hint: Label = %Hint
@onready var _live_ms: Label = %LiveMs
@onready var _success_count: Label = %SuccessCount
@onready var _debug_panel: Label = %DebugPanel
## 不标 `Control`：`result_banner.gd` 没有 `class_name`，静态类型会在编译期拒绝
## `show_outcome`。无类型引用是正确的写法，不是遗漏。
@onready var _banner = %ResultBanner

var _runtime: GestureEngine = null
var _buffer: PadStateBuffer = null
var _accum: float = 0.0
## 上一次写入 `%SuccessCount` 的整串文本；相同就跳过赋值。
var _last_count_text: String = ""


func _ready() -> void:
	pass


## 依赖唯一入口。`main.gd` 在 `flow.can_enter_practice()` 首次为真时调用，
## 那时 `effective_layout()` 必非空；本屏只按传入值选文案，不猜。
func setup(p_runtime: GestureEngine, p_layout: StringName, p_buffer: PadStateBuffer) -> void:
	_runtime = p_runtime
	_buffer = p_buffer
	# 多动作自由练习没有「唯一动作名」：标题来自引擎的通用串。
	_action_name.text = _runtime.display_title
	_hint.text = _hint_text(p_layout)
	# 清掉上一场会话的显示与计数缓存；横幅的 `_shown_seq` 不随之重置（序号单调）。
	_banner.clear()
	_last_count_text = ""
	# 让第一次 `_process` 立刻刷新，而不是先空等 0.1 秒。
	_accum = LIVE_REFRESH_SECONDS


## 隐藏时连 drain 都不做：组合根只显示容器而漏掉本节点时，下面这条早退就是
## 「判定全被静默吞掉」的唯一入口，所以进入练习必须把本节点也置为可见。
func _process(delta: float) -> void:
	if not visible:
		return
	if _runtime == null:
		return
	# 全量 drain：本帧有几条就显示几条，不假设最多一条。
	# 日志必须写在 `show_outcome` **之前**：横幅只显示最后一条，日志要留下每一条
	# （D5-2/D5-3 的「每次恰好一条」靠它核对）。本循环是唯一的 drain 点。
	var outcomes: Array[Outcome] = _runtime.pop_outcomes()
	for outcome in outcomes:
		InputLog.outcome(Time.get_ticks_msec(), outcome.skill_name, outcome.ok,
			outcome.code, outcome.elapsed_ms, outcome.seq, outcome.measured)
		_banner.show_outcome(outcome)
	_accum += delta
	if _accum < 0.1:
		return
	_accum = 0.0
	_refresh_readouts()


## 10 Hz 节流块内的全部高频标签。`_live_ms` 每拍都写（文本确实在变），
## 计数与诊断行只在字符串变化时赋值。
func _refresh_readouts() -> void:
	var status := _runtime.status()
	if status == IDLE_STATUS:
		_live_ms.text = IDLE_DISPLAY
	else:
		_live_ms.text = status

	var count_text := "成功 %d / %d" % [_runtime.hits, _runtime.attempts]
	if count_text != _last_count_text:
		_last_count_text = count_text
		_success_count.text = count_text

	var debug_text := _debug_text()
	if _debug_panel.text != debug_text:
		_debug_panel.text = debug_text


## 诊断面板契约（UI-SPEC §5）：纯 ASCII、单行、不出现设备名。
## 字段来源只有 `PadStateBuffer` 的计数/分位数与运行时的组计数。
func _debug_text() -> String:
	var p95 := 0.0
	if _buffer != null:
		p95 = float(_buffer.delta_ms_percentiles().get("p95", 0.0))
	var events_motion := _buffer.events_motion if _buffer != null else 0
	var events_button := _buffer.events_button if _buffer != null else 0
	var poll_edges := _buffer.poll_edges if _buffer != null else 0
	return "ev_m=%d ev_b=%d poll=%d dt95=%.1f g=%d/%d" % [
		events_motion, events_button, poll_edges, p95,
		_runtime.group_hits, _runtime.group_size,
	]


## 布局 → 键名文案。三支之外的一律视为「布局未确认」：宁可显示错误态，
## 也不让用户按着 Xbox 键名去按 DualSense。
func _hint_text(p_layout: StringName) -> String:
	match p_layout:
		&"playstation":
			return HINT_PLAYSTATION
		&"xbox":
			return HINT_XBOX
	return HINT_NO_LAYOUT
