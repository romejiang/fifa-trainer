extends Control

## 竖屏主界面（`design/mobile.html` 的落地版）：只读运行时，不推进判定。
##
## 三条边界与练习屏同源，违反任何一条都会让「一次尝试一条判定」变成假绿：
##   1. **判定推进点唯一**：`GestureEngine` 只在组合根（`main.gd`）里被推进；
##      本屏只消费运行时的结果队列，并且是**唯一**的 drain 点。
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
## 摇杆低于这个幅度算「回中」；与引擎的 IDLE_STICK 同值，便于人读。
const STICK_CENTERED := 0.20
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
const COLOR_ROW_FOCUS := Color("#F3F8FF")

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
## 当前聚焦的动作下标（只影响显示，不影响判定）。
var _focused: int = 0
## 最近的尝试环形缓冲：同一 `seq` 只进一次，超过 8 条丢最旧。
var _log := AttemptLog.new()

# 逐行动作的节点引用：只建一次，之后只改文本与样式，避免 10 Hz 反复增删节点。
var _skill_rows: Array[PanelContainer] = []
var _skill_names: Array[Label] = []
var _skill_ratios: Array[Label] = []
var _skill_recents: Array[Label] = []
var _skill_bars: Array[ProgressBar] = []
var _skill_styles: Array[StyleBoxFlat] = []
var _skill_focus_styles: Array[StyleBoxFlat] = []

# 最近尝试的固定 8 行。空列表时显示一行占位文案。
var _attempt_rows: Array[PanelContainer] = []
var _attempt_times: Array[Label] = []
var _attempt_names: Array[Label] = []
var _attempt_ms: Array[Label] = []
var _attempt_empty: Label = null


## 最近尝试的环形缓冲。独立成内部类是为了让「8 条上限 + 同 seq 去重」可以在
## 无头套件里直接构造断言，不需要实例化整个 Control。
class AttemptLog:
	extends RefCounted

	const LIMIT := 8

	var rows: Array[Dictionary] = []
	var shown_seq: int = 0

	## 新结果插到最前；`seq` 不大于已显示的最大值就整条丢弃。
	func push(outcome: Outcome, stamp: String) -> bool:
		if outcome == null or outcome.seq <= shown_seq:
			return false
		shown_seq = outcome.seq
		rows.push_front({
			"time": stamp,
			"skill": outcome.skill_name,
			"ms": outcome.elapsed_ms,
			"ok": outcome.ok,
			"code": outcome.code,
		})
		while rows.size() > LIMIT:
			rows.pop_back()
		return true

	func clear() -> void:
		rows.clear()
		shown_seq = 0


func _ready() -> void:
	_build_attempt_rows()
	# 未连接（或还没进入练习、`setup()` 尚未调用）时也要显示正确的默认状态：
	# 场景里的静态文案不能停在「训练中」，否则首启无手柄会自相矛盾。
	_refresh_header()
	_refresh_pad()
	_refresh_attempts()
	# 标题与分节标题再重一档：子集字体的 700 在 2x 屏上还不够粗，800 才接近设计稿。
	var bold: Font = load("res://assets/fonts/AppFontBold.tres")
	if bold != null:
		_title.add_theme_font_override("font", bold)
		_hero_name.add_theme_font_override("font", bold)
		%SkillsTitle.add_theme_font_override("font", bold)
		%AttemptsTitle.add_theme_font_override("font", bold)


## 依赖唯一入口。组合根进入练习时调用；本屏不读设备、不推进判定。
func setup(p_runtime: GestureEngine, p_layout: StringName, p_buffer: PadStateBuffer) -> void:
	_runtime = p_runtime
	_layout = p_layout
	_buffer = p_buffer
	_elapsed = 0.0
	_focused = 0
	_last_timer_text = ""
	# 让第一次 `_process` 立刻刷新，而不是先空等 0.1 秒。
	_accum = REFRESH_SECONDS
	_title.text = "花式练习"
	_status_text.text = "训练中"
	_build_skill_rows()
	_refresh_header()
	_refresh_timer()
	_refresh_hero()
	_refresh_skills()
	_refresh_attempts()
	_refresh_pad()


func _process(delta: float) -> void:
	if not visible:
		return
	_elapsed += delta
	_refresh_timer()
	if _runtime == null:
		return
	# 全量 drain：本帧有几条就处理几条。日志必须写在刷新显示**之前** ——
	# 列表只显示最近 8 条，日志要留下每一条。本循环是全项目唯一的 drain 点。
	var outcomes: Array[Outcome] = _runtime.pop_outcomes()
	for outcome in outcomes:
		InputLog.outcome(Time.get_ticks_msec(), outcome.skill_name, outcome.ok,
			outcome.code, outcome.elapsed_ms, outcome.seq, outcome.measured)
		_log.push(outcome, Time.get_time_string_from_system())
	if not outcomes.is_empty():
		_refresh_hero()
		_refresh_attempts()
	_accum += delta
	if _accum < REFRESH_SECONDS:
		return
	_accum = 0.0
	_refresh_header()
	_refresh_skills()
	_refresh_attempts()
	_refresh_pad()


## 十字键上下切换聚焦动作。返回 true 表示本键被本屏消费（组合根不再转发）。
## 只影响显示：切换聚焦不会 reset / abandon 任何检测器。
func handle_button(index: int) -> bool:
	if _runtime == null:
		return false
	var count := _runtime.active_skills().size()
	if count <= 0:
		return false
	if index == KEY_DPAD_UP:
		_set_focus(next_focus(_focused, count, -1))
		return true
	if index == KEY_DPAD_DOWN:
		_set_focus(next_focus(_focused, count, 1))
		return true
	return false


func _set_focus(value: int) -> void:
	if value == _focused:
		return
	_focused = value
	_apply_skill_focus()
	_refresh_hero()


## 顶部设备行与状态 pill：布局 + 连接状态决定，不读设备名。
func _refresh_header() -> void:
	var connected := _buffer != null and _buffer.device >= 0
	_status_text.text = "训练中" if connected else "等待手柄"
	_status_text.add_theme_color_override("font_color",
		COLOR_GREEN_DEEP if connected else COLOR_TEXT_2)
	_device.text = device_line(_layout, connected)


func _refresh_timer() -> void:
	var text := clock_text(_elapsed)
	if text == _last_timer_text:
		return
	_last_timer_text = text
	_timer.text = text


## 英雄卡显示**当前聚焦动作**最近一次判定；同一 `seq` 不会重复进入列表。
func _refresh_hero() -> void:
	var active := _runtime.active_skills() if _runtime != null else []
	if active.is_empty():
		_hero_name.text = "等待动作"
		_hero_en.text = ""
		_hero_state.text = "还没有成功"
		_hero_state.add_theme_color_override("font_color", COLOR_TEXT_2)
		_hero_ms.text = "—"
		_hero_tip.text = "配置里没有启用的动作。"
		_hero_hint.text = "十字键上下切换动作"
		return
	_focused = clampi(_focused, 0, active.size() - 1)
	var skill: Skill = active[_focused].skill
	var outcome: Outcome = active[_focused].last_outcome
	var parts := split_name(skill.name)
	_hero_name.text = parts[0]
	_hero_en.text = parts[1]
	_hero_state.text = hero_state_text(outcome)
	_hero_state.add_theme_color_override("font_color", _hero_state_color(outcome))
	_hero_ms.text = hero_ms_text(outcome)
	_hero_tip.text = hero_tip_text(outcome)
	_hero_hint.text = hint_for(skill, _layout)


## 5 行动作熟练度：名称、成功/尝试、进度条 hits/10、最近一次 ms。
func _refresh_skills() -> void:
	if _runtime == null:
		return
	var active := _runtime.active_skills()
	_build_skill_rows()
	for index in active.size():
		var item: ActiveSkill = active[index]
		var parts := split_name(item.skill.name)
		_skill_names[index].text = parts[0]
		_skill_ratios[index].text = skill_ratio_text(item.hits, item.attempts)
		_skill_bars[index].value = float(progress_value(item.hits))
		var outcome: Outcome = item.last_outcome
		if outcome == null:
			_skill_recents[index].text = "—"
			_skill_recents[index].add_theme_color_override("font_color", COLOR_TEXT_3)
		else:
			_skill_recents[index].text = "%d ms" % int(round(outcome.elapsed_ms))
			_skill_recents[index].add_theme_color_override("font_color",
				COLOR_GREEN_DEEP if outcome.ok else COLOR_TEXT_3)
	_apply_skill_focus()


## 最近 8 条尝试：时间、动作名、ms。不足 8 条时隐藏多余行并显示占位文案。
func _refresh_attempts() -> void:
	var count := mini(_log.rows.size(), _attempt_rows.size())
	for index in _attempt_rows.size():
		_attempt_rows[index].visible = index < count
	for index in count:
		var entry: Dictionary = _log.rows[index]
		_attempt_times[index].text = String(entry.get("time", ""))
		_attempt_names[index].text = split_name(String(entry.get("skill", "")))[0]
		_attempt_ms[index].text = "%d ms" % int(round(float(entry.get("ms", 0.0))))
	_attempt_empty.visible = count == 0


## 底部手柄状态卡：左/右摇杆当前原始值与连接状态。
func _refresh_pad() -> void:
	var connected := _buffer != null and _buffer.device >= 0
	var ls := Vector2.ZERO
	var rs := Vector2.ZERO
	if _buffer != null:
		ls = Vector2(_buffer.axis_value(0), _buffer.axis_value(1))
		rs = Vector2(_buffer.axis_value(2), _buffer.axis_value(3))
	_pad_text.text = pad_text(connected, ls, rs)


## 建一次 5 行（按运行时实际动作数）；少建多补，不重复清空重排。
func _build_skill_rows() -> void:
	var count := _runtime.active_skills().size() if _runtime != null else 0
	if _skill_rows.size() == count:
		return
	for row in _skill_rows:
		row.queue_free()
	_skill_rows.clear()
	_skill_names.clear()
	_skill_ratios.clear()
	_skill_recents.clear()
	_skill_bars.clear()
	_skill_styles.clear()
	_skill_focus_styles.clear()
	for index in count:
		var panel := PanelContainer.new()
		var normal := _row_style(false, index == 0, index == count - 1)
		var focus := _row_style(true, index == 0, index == count - 1)
		panel.add_theme_stylebox_override("panel", normal)
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 10)
		var main := VBoxContainer.new()
		main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		main.add_theme_constant_override("separation", 5)
		var name_label := Label.new()
		name_label.add_theme_font_size_override("font_size", 15)
		name_label.add_theme_color_override("font_color", COLOR_TEXT)
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(0, 6)
		bar.max_value = float(SKILL_TARGET)
		bar.show_percentage = false
		bar.add_theme_stylebox_override("background", _bar_style(Color("#E7ECE9")))
		bar.add_theme_stylebox_override("fill", _bar_style(Color("#00B84D")))
		var side := VBoxContainer.new()
		side.custom_minimum_size = Vector2(64, 0)
		side.add_theme_constant_override("separation", 1)
		var ratio := Label.new()
		ratio.add_theme_font_size_override("font_size", 15)
		ratio.add_theme_color_override("font_color", COLOR_TEXT)
		ratio.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var recent := Label.new()
		recent.add_theme_font_size_override("font_size", 13)
		recent.add_theme_color_override("font_color", COLOR_TEXT_3)
		recent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		main.add_child(name_label)
		main.add_child(bar)
		side.add_child(ratio)
		side.add_child(recent)
		box.add_child(main)
		box.add_child(side)
		panel.add_child(box)
		_skills.add_child(panel)
		_skill_rows.append(panel)
		_skill_names.append(name_label)
		_skill_ratios.append(ratio)
		_skill_recents.append(recent)
		_skill_bars.append(bar)
		_skill_styles.append(normal)
		_skill_focus_styles.append(focus)


func _apply_skill_focus() -> void:
	for index in _skill_rows.size():
		var style := _skill_focus_styles[index] if index == _focused else _skill_styles[index]
		_skill_rows[index].add_theme_stylebox_override("panel", style)


## 最近尝试的 8 行固定节点；空列表的占位文案也在这里建。
func _build_attempt_rows() -> void:
	if not _attempt_rows.is_empty():
		return
	_attempt_empty = Label.new()
	_attempt_empty.add_theme_font_size_override("font_size", 15)
	_attempt_empty.add_theme_color_override("font_color", COLOR_TEXT_3)
	_attempt_empty.text = "暂无尝试记录，做对一个动作后会出现在这里。"
	_attempt_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_attempt_empty.custom_minimum_size = Vector2(0, 56)
	_attempt_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_attempts.add_child(_attempt_empty)
	for index in ATTEMPT_LIMIT:
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", _attempt_style(index == ATTEMPT_LIMIT - 1))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var stamp := Label.new()
		stamp.add_theme_font_size_override("font_size", 13)
		stamp.add_theme_color_override("font_color", COLOR_TEXT_3)
		stamp.custom_minimum_size = Vector2(84, 0)
		var name_label := Label.new()
		name_label.add_theme_font_size_override("font_size", 15)
		name_label.add_theme_color_override("font_color", COLOR_TEXT)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var ms := Label.new()
		ms.add_theme_font_size_override("font_size", 15)
		ms.add_theme_color_override("font_color", COLOR_TEXT)
		ms.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(stamp)
		row.add_child(name_label)
		row.add_child(ms)
		panel.add_child(row)
		_attempts.add_child(panel)
		_attempt_rows.append(panel)
		_attempt_times.append(stamp)
		_attempt_names.append(name_label)
		_attempt_ms.append(ms)


func _row_style(focused: bool, first: bool, last: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_ROW_FOCUS if focused else Color(0, 0, 0, 0)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 5.0
	style.content_margin_bottom = 5.0
	if not first:
		style.border_width_top = 1
		style.border_color = Color("#ECECF0")
	return style


func _attempt_style(last: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 3.0
	style.content_margin_bottom = 3.0
	if not last:
		style.border_width_bottom = 1
		style.border_color = Color("#ECECF0")
	return style


func _bar_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(4)
	return style


func _hero_state_color(outcome: Outcome) -> Color:
	if outcome == null:
		return COLOR_TEXT_2
	return COLOR_SUCCESS if outcome.ok else COLOR_FAILURE


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
	var ls_state := "回中" if ls.length() < STICK_CENTERED else "%.2f / %.2f" % [ls.x, ls.y]
	var rs_state := "回中" if rs.length() < STICK_CENTERED else "%.2f / %.2f" % [rs.x, rs.y]
	return "手柄已连接　左摇杆 %s　右摇杆 %s" % [ls_state, rs_state]


## 配置里的动作名是「中文 English」一个字符串；英雄卡与列表要分开显示。
## 没有空格时第二段为空串，绝不把整串塞进英文位。
static func split_name(full: String) -> Array[String]:
	var trimmed := full.strip_edges()
	var cut := trimmed.find(" ")
	if cut < 0:
		var only: Array[String] = [trimmed, ""]
		return only
	var parts: Array[String] = [trimmed.substr(0, cut), trimmed.substr(cut + 1).strip_edges()]
	return parts


## 英雄卡状态文案。null = 这个动作还没有任何判定。
static func hero_state_text(outcome: Outcome) -> String:
	if outcome == null:
		return "还没有成功"
	return "做对了" if outcome.ok else "没做对"


## 英雄卡毫秒位。null 显示破折号，不显示 0 ms。
static func hero_ms_text(outcome: Outcome) -> String:
	if outcome == null:
		return "—"
	return "%d ms" % int(round(outcome.elapsed_ms))


## 英雄卡提示行：成功用检测器给的 detail，失败用检测器的 message，本屏不重拼。
static func hero_tip_text(outcome: Outcome) -> String:
	if outcome == null:
		return "这个动作还没有成功记录。"
	if outcome.ok:
		return outcome.detail if not outcome.detail.is_empty() else "动作识别成功。"
	return outcome.message if not outcome.message.is_empty() else "没做对，再来一次。"


## 熟练度右侧：成功 / 尝试。
static func skill_ratio_text(hits: int, attempts: int) -> String:
	return "%d / %d" % [maxi(0, hits), maxi(0, attempts)]


## 进度条的值：成功次数，封顶 10。
static func progress_value(hits: int) -> int:
	return clampi(hits, 0, SKILL_TARGET)


## 十字键焦点移动：上下各一格，到头停住（不回绕）。
static func next_focus(current: int, count: int, step: int) -> int:
	if count <= 0:
		return 0
	return clampi(current + step, 0, count - 1)


## 动作提示行：种类决定一句话，修饰键按当前布局换键名。
static func hint_for(skill: Skill, layout: StringName) -> String:
	if skill == null:
		return "十字键上下切换动作"
	var modifier := ""
	if not skill.required_buttons.is_empty():
		modifier = "按住 %s，" % button_label(skill.required_buttons[0], layout)
	match skill.kind:
		&"taps":
			return modifier + "连按两下 X；十字键切换动作"
		&"arc":
			return "推右摇杆画弧；左摇杆定朝向"
		&"sequence":
			return modifier + "按顺序推右摇杆；左摇杆定朝向"
	return "十字键上下切换动作"


## 配置里的按钮 canonical 名在两种布局下的用户文案。
static func button_label(name: String, layout: StringName) -> String:
	if layout == &"playstation":
		match name:
			"LB":
				return "L1"
			"RB":
				return "R1"
			"LT":
				return "L2"
			"RT":
				return "R2"
		return name
	match name:
		"L1":
			return "LB"
		"R1":
			return "RB"
	return name
