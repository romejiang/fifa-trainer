extends RefCounted

## 竖屏主界面的**无头格式套件**（Phase 5 计划 08 的 Task 3）。
##
## 它回答四类没有设备也能回答的问题：
##   1. 英雄卡文案：成功 / 失败 / 无判定三种状态下，状态词、毫秒位与提示行是否
##      只取 `Outcome` 的字段，而不是在本屏重拼原因；
##   2. 动作熟练度：`成功 / 尝试` 与 `hits / 10` 进度条的值是否正确（含上限）；
##   3. 最近尝试：最多 50 条、新结果在前、同一 `seq` 只进一次；
##   4. 交互与接线的源码结构：十字键焦点不回绕、`pop_outcomes()` 只有一个 drain
##      点、日志写在刷新显示之前、`main.gd` 不再 drain、首启不再显示输入设置页。
##
## 场景节点用源码结构断言（`unique_name_in_owner = true`）而不是实例化：无头
## `--script` 下根视口尺寸为 0，`get_node("%X")` 能过但尺寸断言没有意义；节点
## 是否真的存在由 `.tscn` 的 node 块逐条证明即可。
##
## 本套件不加 `class_name`（项目约定：测试脚不污染全局命名空间，也不进导出包）。

const HOME_SCRIPT := preload("res://src/ui/home_screen.gd")
const HOME_PATH := "res://src/ui/home_screen.gd"
const MAIN_PATH := "res://src/ui/main.gd"
const SCENE_PATH := "res://src/ui/home_screen.tscn"
const PROJECT_PATH := "res://project.godot"

## 需求写死的 14 个 unique 节点（另有 StatusText / SkillsTitle / AttemptsTitle 等
## 辅助节点；这里只断言契约里点名的那些）。
const UNIQUE_NODES := [
	"Status", "Title", "Timer", "Device", "Hero", "HeroName", "HeroEn",
	"HeroState", "HeroMs", "HeroTip", "Skills", "Attempts", "Pad", "PadText",
]


func run(r) -> void:
	_check_name_split(r)
	_check_hero_texts(r)
	_check_skill_rows(r)
	_check_attempts(r)
	_check_focus(r)
	_check_header_and_pad(r)
	_check_scene_nodes(r)
	_check_source_structure(r)
	_check_portrait(r)
	r.complete()


## 1. 配置里的「中文 English」必须拆成两段；没有英文时第二段为空。
func _check_name_split(r) -> void:
	var green := HOME_SCRIPT.split_name("绿色搓射 Green Finesse")
	r.check(green.size() == 2 and green[0] == "绿色搓射" and green[1] == "Green Finesse",
		"split_name 必须把「绿色搓射 Green Finesse」拆成中文与英文（实际 %s）" % str(green))
	var only := HOME_SCRIPT.split_name("马赛回旋")
	r.check(only.size() == 2 and only[0] == "马赛回旋" and only[1] == "",
		"没有空格的名称必须整串留在中文位、英文位为空（实际 %s）" % str(only))


## 2. 英雄卡三种状态：无判定 / 成功 / 失败。成功取 detail，失败取 message。
func _check_hero_texts(r) -> void:
	r.check(HOME_SCRIPT.hero_state_text(null) == "还没有成功",
		"无判定时状态必须是「还没有成功」")
	r.check(HOME_SCRIPT.hero_ms_text(null) == "—",
		"无判定时毫秒位必须是破折号，不能是 0 ms")
	r.check(HOME_SCRIPT.hero_tip_text(null) == "这个动作还没有成功记录。",
		"无判定时提示必须是「这个动作还没有成功记录。」")

	var ok := _outcome(1, true, "绿色搓射 Green Finesse", 556.4, "两下 X 间隔 556ms", "")
	r.check(HOME_SCRIPT.hero_state_text(ok) == "做对了", "成功状态必须是「做对了」")
	r.check(HOME_SCRIPT.hero_ms_text(ok) == "556 ms", "成功毫秒位必须四舍五入到 556 ms")
	r.check(HOME_SCRIPT.hero_tip_text(ok) == "两下 X 间隔 556ms",
		"成功提示必须原样取 Outcome.detail")

	var fail := _outcome(2, false, "绿色搓射 Green Finesse", 209.2, "",
		"太快了：两下间隔 209ms（需要 400ms~600ms）")
	r.check(HOME_SCRIPT.hero_state_text(fail) == "没做对", "失败状态必须是「没做对」")
	r.check(HOME_SCRIPT.hero_ms_text(fail) == "209 ms", "失败毫秒位必须是 209 ms")
	r.check(HOME_SCRIPT.hero_tip_text(fail).contains("太快了"),
		"失败提示必须原样取 Outcome.message（实际 %s）" % HOME_SCRIPT.hero_tip_text(fail))

	var empty_ok := _outcome(3, true, "踩单车 Stepover", 300.0, "", "")
	r.check(HOME_SCRIPT.hero_tip_text(empty_ok) == "动作识别成功。",
		"成功但 detail 为空时必须有兜底文案")


## 3. 熟练度：成功 / 尝试，以及封顶 10 的进度值。
func _check_skill_rows(r) -> void:
	r.check(HOME_SCRIPT.skill_ratio_text(9, 12) == "9 / 12",
		"熟练度右侧必须是「成功 / 尝试」")
	r.check(HOME_SCRIPT.skill_ratio_text(0, 0) == "0 / 0",
		"零尝试时必须是 0 / 0")
	r.check(HOME_SCRIPT.progress_value(0) == 0, "零成功时进度必须是 0")
	r.check(HOME_SCRIPT.progress_value(9) == 9, "9 次成功时进度必须是 9")
	r.check(HOME_SCRIPT.progress_value(14) == 10,
		"超过目标时必须封顶在 10（进度条 max_value 是 10）")
	r.check(HOME_SCRIPT.progress_value(-3) == 0, "负值必须夹到 0")

	var taps := _skill("绿色搓射 Green Finesse", Skill.KIND_TAPS, ["RB"])
	var xbox_hint := HOME_SCRIPT.hint_for(taps, &"xbox")
	r.check(xbox_hint.contains("按住 RB") and xbox_hint.contains("X"),
		"Xbox 布局的 taps 提示必须出现 RB 与 X（实际 %s）" % xbox_hint)
	var ps_taps := _skill("绿色搓射 Green Finesse", Skill.KIND_TAPS, ["RB"])
	var ps_hint := HOME_SCRIPT.hint_for(ps_taps, &"playstation")
	r.check(ps_hint.contains("按住 R1"),
		"PlayStation 布局必须把 RB 写成 R1（实际 %s）" % ps_hint)
	r.check(HOME_SCRIPT.button_label("L1", &"xbox") == "LB",
		"L1 在 Xbox 布局必须写成 LB")
	r.check(HOME_SCRIPT.button_label("LB", &"playstation") == "L1",
		"LB 在 PlayStation 布局必须写成 L1")


## 4. 最近尝试：50 条上限、新结果在前、同 seq 去重、clear 归零。
func _check_attempts(r) -> void:
	var log = HOME_SCRIPT.AttemptLog.new()
	var pushed := 0
	for index in 60:
		if log.push(_outcome(index + 1, true, "动作%d" % (index + 1), float(100 + index), "", ""), "02:20:%02d" % index):
			pushed += 1
	r.check(pushed == 60, "60 条全新结果必须全部被接收（实际 %d）" % pushed)
	r.check(log.rows.size() == 50,
		"最近尝试必须只保留 50 条（实际 %d）" % log.rows.size())
	r.check(String(log.rows[0]["skill"]) == "动作60",
		"最新一条必须在最前（实际 %s）" % String(log.rows[0]["skill"]))
	r.check(String(log.rows[49]["skill"]) == "动作11",
		"第 50 条必须是最旧保留的那条（实际 %s）" % String(log.rows[49]["skill"]))
	r.check(not log.push(_outcome(60, true, "重复", 1.0, "", ""), "02:20:59"),
		"同一 seq 必须被拒绝")
	r.check(log.rows.size() == 50, "同 seq 被拒后条数不得变化")
	r.check(not log.push(_outcome(5, true, "更旧", 1.0, "", ""), "02:21:00"),
		"更小的 seq 必须被拒绝（序号单调）")
	log.clear()
	r.check(log.rows.is_empty() and log.shown_seq == 0,
		"clear 必须同时清空行与已显示序号")


## 5. 十字键焦点：上下各一格，到头不回绕。
func _check_focus(r) -> void:
	r.check(HOME_SCRIPT.next_focus(0, 5, -1) == 0, "第一行再按上必须停在 0")
	r.check(HOME_SCRIPT.next_focus(0, 5, 1) == 1, "从 0 按下必须到 1")
	r.check(HOME_SCRIPT.next_focus(4, 5, 1) == 4, "最后一行再按下必须停在 4")
	r.check(HOME_SCRIPT.next_focus(2, 0, 1) == 0, "零动作时必须返回 0")


## 6. 顶部设备行与底部摇杆行。
func _check_header_and_pad(r) -> void:
	var xbox := HOME_SCRIPT.device_line(&"xbox", true)
	r.check(xbox.contains("Xbox") and xbox.contains("手柄已连接"),
		"Xbox 已连接必须同时出现品牌与「手柄已连接」（实际 %s）" % xbox)
	var no_brand := HOME_SCRIPT.device_line(&"", true)
	r.check(no_brand.contains("标准映射"),
		"空布局不得回退到 Xbox 字样（实际 %s）" % no_brand)
	var off := HOME_SCRIPT.device_line(&"xbox", false)
	r.check(off.contains("未连接"), "未连接必须说「手柄未连接」（实际 %s）" % off)
	r.check(HOME_SCRIPT.pad_text(false, Vector2.ZERO, Vector2.ZERO) == "手柄未连接",
		"未连接时摇杆卡只说未连接")
	var pad := HOME_SCRIPT.pad_text(true, Vector2.ZERO, Vector2(0.5, -0.25))
	r.check(pad.contains("回中"), "左摇杆回中必须写出来（实际 %s）" % pad)
	r.check(pad.contains("0.50 / -0.25"), "右摇杆必须带出当前值（实际 %s）" % pad)


## 7. `.tscn` 里 14 个契约节点必须存在且带 unique_name_in_owner。
func _check_scene_nodes(r) -> void:
	var text := _read_source(SCENE_PATH)
	r.check(not text.is_empty(), "必须能读到 %s" % SCENE_PATH)
	if text.is_empty():
		return
	for name in UNIQUE_NODES:
		r.check(_has_unique_node(text, name),
			"home_screen.tscn 必须有 unique 节点 %s" % name)
	r.check(text.contains('type="Control"'),
		"根节点必须是 Control")
	r.check(not text.contains('type="Button"'),
		"主界面不得有触摸按钮（Button 节点为零）")


## 8. 源码结构：唯一 drain、日志先写、组合根不再 drain；首启不再强制设置页。
func _check_source_structure(r) -> void:
	var home := _read_source(HOME_PATH)
	var main := _read_source(MAIN_PATH)
	r.check(not home.is_empty(), "必须能读到 %s" % HOME_PATH)
	r.check(not main.is_empty(), "必须能读到 %s" % MAIN_PATH)
	if home.is_empty() or main.is_empty():
		return
	r.check(_count(home, "pop_outcomes(") == 1,
		"HomeScreen 必须恰好一个 drain 点（实际 %d）" % _count(home, "pop_outcomes("))
	r.check(_count(main, "pop_outcomes(") == 0,
		"main.gd 不得再 drain 一次（实际 %d）" % _count(main, "pop_outcomes("))
	var log_index := home.find("InputLog.outcome(")
	var refresh_index := home.find("_refresh_hero()")
	r.check(log_index >= 0, "HomeScreen 必须写 OUTCOME 日志行")
	r.check(refresh_index >= 0, "HomeScreen 必须刷新英雄卡")
	r.check(log_index >= 0 and refresh_index >= 0 and log_index < refresh_index,
		"日志必须在刷新显示之前写（日志 %d，刷新 %d）" % [log_index, refresh_index])
	r.check(home.contains("setup(p_runtime: GestureEngine"),
		"HomeScreen.setup 的第一个参数必须是 GestureEngine")
	r.check(not home.contains("Button.new("),
		"HomeScreen 不得创建触摸按钮")
	r.check(main.contains("HomeScreen"),
		"main.gd 必须接 HomeScreen")
	r.check(main.contains("seed_known_defaults"),
		"main.gd 必须保留标准映射自动建档路径")
	r.check(main.contains("_setup.visible = false"),
		"输入设置页默认必须不可见（首启直达主界面）")
	r.check(main.contains("handle_button"),
		"main.gd 必须把十字键边沿转给 HomeScreen")


## 9. 竖屏基准：orientation=1、393x852（与 design/mobile.html 的逻辑尺寸一致）。
func _check_portrait(r) -> void:
	var text := _read_source(PROJECT_PATH)
	r.check(text.contains("window/handheld/orientation=1"),
		"project.godot 必须是竖屏（orientation=1）")
	r.check(text.contains("window/size/viewport_width=393"),
		"project.godot 基准宽度必须是 393")
	r.check(text.contains("window/size/viewport_height=852"),
		"project.godot 基准高度必须是 852")


## 构造一个 Outcome：套件只关心 UI 读取的字段。
func _outcome(seq: int, ok: bool, skill: String, elapsed_ms: float,
		detail: String, message: String) -> Outcome:
	var outcome := Outcome.new()
	outcome.seq = seq
	outcome.ok = ok
	outcome.skill_name = skill
	outcome.elapsed_ms = elapsed_ms
	outcome.detail = detail
	outcome.message = message
	outcome.code = &"ok" if ok else &"too_fast"
	return outcome


func _skill(name: String, kind: StringName, buttons: Array) -> Skill:
	var skill := Skill.new()
	skill.name = name
	skill.kind = kind
	for button_name in buttons:
		skill.required_buttons.append(String(button_name))
	return skill


## `.tscn` 的 node 块里是否带 `unique_name_in_owner = true`。
static func _has_unique_node(text: String, name: String) -> bool:
	var start := text.find('[node name="%s"' % name)
	if start < 0:
		return false
	var next := text.find("[node ", start + 1)
	var block := text.substr(start, (next - start) if next >= 0 else text.length() - start)
	return block.contains("unique_name_in_owner = true")


static func _read_source(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


## 非重叠计数：源码结构断言用它证明「恰好一次 / 零次」。
static func _count(text: String, needle: String) -> int:
	var total := 0
	var start := 0
	while true:
		var found := text.find(needle, start)
		if found < 0:
			break
		total += 1
		start = found + needle.length()
	return total
