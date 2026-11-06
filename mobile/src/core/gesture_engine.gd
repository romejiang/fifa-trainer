class_name GestureEngine
extends RefCounted

## 多动作判定引擎：`desktop/padskills/engine.py:92-452` 里与判定有关的全部逻辑。
##
## 为什么需要它：「两次独立判定」「一次挥动只出一个判定」不是检测器的性质，是引擎的
## 性质 —— `cooldown_ms`、`global_cooldown_ms`、手势锁、失败单槽、`GROUP_SIZE` 全在
## engine.py 里。单技能场景由 `TapRuntime` 证明过；五个动作同时启用后，竞争、互斥、
## 失败归属才第一次变得可达。
##
## ## 分支顺序就是语义
##
## `tick()` 与 `engine.py:248-377` 同构，一步不许换：
##   1. **未确认布局 → 直接返回**（移动端独有硬门，必须在最前）；
##   2. 左摇杆朝向：`ls_mag >= ls_facing_threshold` 时更新 `_facing`，并写回
##      `frame.facing`（引擎是唯一写入者）；
##   3. 手势锁：右摇杆回中满 `gesture_release_ms` 才解锁，锁着就 return；
##   4. `held_required`：当前按住的、属于某个动作 `required_buttons` 的键；
##   5. 引擎级 idle：右摇杆静止满 `idle_reset_ms` 时对全部动作 `on_idle()` 一次；
##   6. 逐动作三道前置（别的动作的修饰键 / 相对动作缺 LS / 自己的修饰键）→
##      `update()` → `_discard_other_claims()` → 逐动作冷却 → 全局冷却 → 命中；
##   7. 失败统一在 `_drain_failures()` 取，一次 tick 最多一条进队列。
##
## ## 与桌面参考的三处差异（且只有这三处）
##
## | 差异 | 桌面 | 这里 | 理由 |
## |------|------|------|------|
## | 布局硬门 | 无 | `layout_confirmed == false` → 第一早退 | Phase 4 SC4；无头可证「零判定」 |
## | 结果通道 | `last_outcome` 单槽 + `outcome_seq` | `Array[Outcome]` 队列 + `pop_outcomes()` | 桌面同帧两条会吞掉第一条 |
## | 清场入口 | `set_focus` / `set_paused` → `_reset_progress` | 公开 `reset_progress()` | 语义相同，只是暴露成入口 |
##
## 不移植：`focus` / `paused`（桌面 GUI 专用）、`_fire` 的震动播发、`_render_debug`、
## `_write`。**本阶段没有震动 sink**：Phase 10 之前不接震动，这里也不留空调用点。
##
## ## 刻意的移动端语义
##
## - `pop_outcomes()` 全量 drain：每个 `Outcome` 带单调 `seq`，「不丢结果」是结构而不是约定。
## - `hits` / `attempts` / `group_hits` / `groups_done` 是**全部动作的聚合值**。单技能
##   （`TapRuntime`）时与逐动作值相同；多技能时只用于调试行 —— 真正的组语义由
##   Phase 6 的练习循环定义，本阶段不假装它是产品语义。
## - `set_layout_confirmed(false)` 静默 `abandon()` 全部动作并清空未取走的结果：
##   断连不是一次尝试，不能产出判定（`tap_runtime.gd` 的既有语义，不能用 `reset()`）。
## - `state_of()` / `cooldown_remaining_ms()` 是给 Phase 6 的只读钩子，不进黄金语料。

## 每做对这么多个算一组，满了清零重新数（engine.py:93 的 `GROUP_SIZE`）。
const GROUP_SIZE := 10

## 右摇杆低于这个幅度算「没在推」，用于 idle 计时（engine.py:97）。
const IDLE_STICK := 0.20

## 右摇杆回中到这个幅度以下才开始计手势解锁时间（engine.py:98）。
const RELEASE_STICK := 0.35

## 多动作时状态行显示的名字；单动作时 `status()` 委托检测器，不用它。
var display_title: String = "自由练习"
## 轴映射是否已确认。`false` 时 `tick()` 零判定、`status()` 直说。
var layout_confirmed: bool = false
## 组容量。默认 `GROUP_SIZE`，构造可注入更小值 —— 只在无头证明里用来两发就看到归零。
var group_size: int = GROUP_SIZE
## 被全局冷却吞掉的命中次数（逐动作冷却吞掉时**不**计数，与 engine.py:350-352 一致）。
var suppressed: int = 0

var _config: AppConfig = null
var _skills: Array[ActiveSkill] = []
var _last_any_fire: float = -1e9
## 最近一帧的时间戳（秒）。`state_of()` 的冷却判断用它，避免再要求调用方传 now。
var _now: float = 0.0
## 球员朝向：只有左摇杆推过阈值时才更新；回中时冻结在上次方向。
var _facing: float = 0.0
var _gesture_locked: bool = false
## 成对表示，不用 -1.0 当哨兵：0.0 是合法时间戳。
var _have_lock_release_since: bool = false
var _lock_release_since: float = 0.0
var _have_idle_since: bool = false
var _idle_since: float = 0.0
var _idle_cleared: bool = false
var _outcomes: Array[Outcome] = []
var _seq: int = 0
## 单练模式：非空时只推进这一条动作，其余只做 observe/abandon。
var focused_skill: StringName = &""


## `p_layout_confirmed` 默认 false：宁可什么都不判，也不要在轴映射未确认时给结论。
## `p_group_size` 只为了在没有设备的环境里用两次命中证明分组归零；默认值必须等于
## 常量 `GROUP_SIZE`，真实运行时不传这个参数。
func _init(p_config: AppConfig, p_layout_confirmed := false,
		p_group_size: int = GROUP_SIZE) -> void:
	_config = p_config
	layout_confirmed = p_layout_confirmed
	group_size = p_group_size
	_facing = p_config.input.initial_facing_deg
	for skill in p_config.enabled_skills():
		var detector := DetectorFactory.build(skill)
		# 配置校验已把 kind 限制在三值内；这里只防御，不抛错（core 不把错误当控制流）。
		if detector == null:
			continue
		_skills.append(ActiveSkill.new(skill, detector))


## 当前参与判定的动作（副本）。Phase 6 的只读钩子与调试行用它。
func active_skills() -> Array[ActiveSkill]:
	var copy: Array[ActiveSkill] = []
	copy.assign(_skills)
	return copy


## 全部动作的成功次数之和。单技能时就是该动作的 `hits`。
var hits: int:
	get:
		var total := 0
		for active in _skills:
			total += active.hits
		return total


## 全部动作的尝试次数之和（成功 + 有主的失败）。
var attempts: int:
	get:
		var total := 0
		for active in _skills:
			total += active.attempts
		return total


## 全部动作的组内命中数之和 —— 仅调试行用，真正的组语义在 Phase 6。
var group_hits: int:
	get:
		var total := 0
		for active in _skills:
			total += active.group_hits
		return total


## 全部动作的已完成组数之和 —— 仅调试行用，真正的组语义在 Phase 6。
var groups_done: int:
	get:
		var total := 0
		for active in _skills:
			total += active.groups_done
		return total


## 唯一动作的名字；零个或多个动作时为空串（多动作的状态行由 Phase 6 定义）。
var skill_name: String:
	get:
		if focused_skill != &"":
			return String(focused_skill)
		if _skills.size() == 1:
			return _skills[0].skill.name
		return ""


## 单练：只推进这一条动作。空串 = 全部启用（测试与旧行为）。
func set_focused_skill(name: StringName) -> void:
	if focused_skill == name:
		return
	focused_skill = name
	# 切换单练目标时静默清掉其余动作的半截进度，避免旧手势在新目标上误判。
	for active in _skills:
		if not _is_focused(active):
			active.detector.abandon()


func _is_focused(active: ActiveSkill) -> bool:
	return focused_skill == &"" or active.skill.name == String(focused_skill)


## 一帧。分支顺序见类文档，不许重排。
func tick(frame: Frame) -> void:
	# 1. 未确认布局：第一早退，必须在朝向与手势锁之前。成功标准 4 的机械保证。
	if not layout_confirmed:
		return

	_now = frame.now

	# 2. 左摇杆推动时更新「球员面朝方向」；回中则冻结。frame.facing 由引擎写。
	var ls_ok := frame.ls_mag >= _config.input.ls_facing_threshold
	if ls_ok:
		_facing = frame.ls_angle
	frame.facing = _facing

	# 3. 手势锁：锁定期间检测器看不到任何帧，失败也不 drain。
	if _gesture_locked:
		if frame.rs_mag < RELEASE_STICK:
			if not _have_lock_release_since:
				_have_lock_release_since = true
				_lock_release_since = frame.now
			if (frame.now - _lock_release_since) * 1000.0 >= float(_config.input.gesture_release_ms):
				for active in _skills:
					active.detector.on_idle()
				_gesture_locked = false
				_have_lock_release_since = false
				_lock_release_since = 0.0
		else:
			# 还推着就不算回中：连续动作不会被拆成两段。
			_have_lock_release_since = false
			_lock_release_since = 0.0
		if _gesture_locked:
			return

	# 4. 按住某个动作的修饰键时，只判定需要这个键的动作（engine.py:291-301）。
	var held_required: Array[String] = []
	for active in _skills:
		if not _is_focused(active):
			continue
		for button_name in active.skill.required_buttons:
			if frame.buttons.has(button_name) and not held_required.has(button_name):
				held_required.append(button_name)

	# 5. 长时间没有推右摇杆：清空全部未完成动作（engine.py:303-314）。
	if frame.rs_mag < IDLE_STICK:
		if not _have_idle_since:
			_have_idle_since = true
			_idle_since = frame.now
		if not _idle_cleared and (frame.now - _idle_since) * 1000.0 >= float(_config.input.idle_reset_ms):
			for active in _skills:
				active.detector.on_idle()
			_idle_cleared = true
	else:
		_have_idle_since = false
		_idle_cleared = false

	for active in _skills:
		# 单练模式：非聚焦动作只更新外部按键状态并静默清空进度。
		if not _is_focused(active):
			active.detector.observe(frame)
			active.detector.abandon()
			continue
		# a) 按住了别的动作的修饰键 -> 静默丢弃半截进度，不能过一会儿报「没做完」。
		if not held_required.is_empty() and not _requires_any(active.skill, held_required):
			active.detector.observe(frame)
			active.detector.abandon()
			continue

		# b) 相对左摇杆的动作：左摇杆回中时没有方向基准，整段作废（reset 会报 hold_short）。
		if active.skill.relative_to_ls and not ls_ok:
			active.detector.observe(frame)
			active.detector.reset()
			continue

		# c) 自己的修饰键没按住 -> 进度作废，但先记下这一帧供 status() 提示。
		if not _buttons_ok(active.skill, frame.buttons):
			active.detector.observe(frame)
			active.detector.reset()
			continue

		var hit := active.detector.update(frame)
		if hit == null:
			continue

		# e) 这次手势已经成功，别的检测器攒下的进度与失败裁定全部作废。
		#    必须在冷却判断**之前**（engine.py:346 在 :348 之前）。
		_discard_other_claims(active)

		# f) 逐动作冷却：**静默**丢弃，不记 Outcome、不加 suppressed。
		if (frame.now - active.last_fire) * 1000.0 < float(active.skill.cooldown_ms):
			continue
		# g) 全局冷却：吞掉时 suppressed += 1。
		if (frame.now - _last_any_fire) * 1000.0 < float(_config.global_cooldown_ms):
			suppressed += 1
			continue

		# h) 真正命中。
		active.last_fire = frame.now
		active.hits += 1
		active.attempts += 1
		active.group_hits += 1
		if active.group_hits >= group_size:
			active.group_hits = 0
			active.groups_done += 1
		_last_any_fire = frame.now
		_record(active, true, &"ok", "", hit.elapsed_ms, frame.now, hit.summary,
			hit.measured)

		# i) 一次物理动作只认一个动作；`break` 必须在置锁之后。
		_gesture_locked = true
		_have_lock_release_since = false
		_lock_release_since = 0.0
		break

	# 7. 失败统一在这里取：一次 tick 最多一条进队列。
	_drain_failures(frame.now)


## 一次物理手势只归一个动作：别的检测器攒下的进度全部静默作废。
func _discard_other_claims(owner: ActiveSkill) -> void:
	for active in _skills:
		# `==` 对 Object 比的是引用身份（Python 的 `is`）；`is` 是类型判断，不能用。
		if active == owner:
			continue
		active.detector.abandon()


## 另一个动作的修饰键被按住时，本动作今天不参与判定。
func _requires_any(skill: Skill, held: Array[String]) -> bool:
	for button_name in held:
		if skill.required_buttons.has(button_name):
			return true
	return false


## 失败单槽：**遍历全部动作**把待取槽清空，只给配置顺序里第一个有 pending 的
## owner 记账。任何 `break` 都会把后面的 pending 留到下一帧，产出「延迟一帧的
## 失败」（engine.py:391-412 没有 break）。
func _drain_failures(now: float) -> void:
	var owner: ActiveSkill = null
	for active in _skills:
		var failure := active.detector.pop_failure()
		if failure == null:
			continue
		if not _is_focused(active):
			continue
		if owner != null:
			continue
		owner = active
		active.attempts += 1
		var code := str(failure.code)
		active.failures[code] = int(active.failures.get(code, 0)) + 1
		_record(active, false, failure.code, failure.message, failure.elapsed_ms,
			now, "", failure.measured)
	if owner != null:
		_discard_other_claims(owner)


## 成功 / 失败都从这里进队列；`seq` 从 1 开始单调递增。
##
## **全项目唯一的 `_record` 定义**，8 个参数。`measured` 由命中路径从
## `Hit.measured`、失败路径从 `Failure.measured` **原样**透传（同一个对象，
## 不 `duplicate()`、不裁剪、不重算）—— Phase 7 只认这一份度量。
func _record(active: ActiveSkill, ok: bool, code: StringName, message: String,
		elapsed_ms: float, at: float, detail: String, measured: Dictionary = {}) -> void:
	var outcome := Outcome.new()
	outcome.skill_name = active.skill.name
	outcome.ok = ok
	outcome.code = code
	outcome.message = message
	outcome.elapsed_ms = elapsed_ms
	outcome.at = at
	outcome.detail = detail
	outcome.measured = measured
	_seq += 1
	outcome.seq = _seq
	active.last_outcome = outcome
	_outcomes.append(outcome)


## UI 唯一的结果入口：返回当前队列的副本并清空内部队列（全量 drain，绝不覆盖）。
func pop_outcomes() -> Array[Outcome]:
	var drained: Array[Outcome] = []
	drained.assign(_outcomes)
	_outcomes.clear()
	return drained


## 未确认布局时明确说出来；单动作委托检测器；多动作显示通用标题。
##
## 布局门必须在最前：`TapRuntime` 子类化后如果丢了这一条，Phase 4 的
## `test_tap_runtime.gd:269` 会在「未确认布局」时读到检测器的「待机」。
func status() -> String:
	if not layout_confirmed:
		return "未确认布局"
	if focused_skill != &"":
		for active in _skills:
			if active.skill.name == String(focused_skill):
				return active.detector.status()
	if _skills.size() == 1:
		return _skills[0].detector.status()
	return display_title


## 布局确认状态由界面/设备层设置。从「已确认」变回「未确认」时**静默清场**：
## 手柄在动作中途断开时 `now` 会跳走几分钟，恢复后继续用旧的 `_t0` 必然报
## `too_slow`。断连不是一次尝试 —— 用 `abandon()`（静默）而不是 `reset()`。
func set_layout_confirmed(value: bool) -> void:
	var was := layout_confirmed
	layout_confirmed = value
	if was and not value:
		for active in _skills:
			active.detector.abandon()
		_gesture_locked = false
		_have_lock_release_since = false
		_lock_release_since = 0.0
		_have_idle_since = false
		_idle_since = 0.0
		_idle_cleared = false
		_outcomes.clear()


## 丢掉所有未完成的进度，并让动作可以立刻重新起手。
##
## 与桌面 `_reset_progress()`（engine.py:185-198）同语义：先 `abandon()` 静默清空，
## 再 `on_idle()` 把 armed 拉回 True。少了后半步，画弧 / 序列动作要等摇杆回中
## 120~150ms 才重新武装，切回练习的第一下会被吃掉。
func reset_progress() -> void:
	for active in _skills:
		active.detector.abandon()
		active.detector.on_idle()
	_gesture_locked = false
	_have_lock_release_since = false
	_lock_release_since = 0.0
	_have_idle_since = false
	_idle_since = 0.0
	_idle_cleared = false


## 修饰键判定，两种模式都要（Sequence 的 `any` 与默认的 `all`）。
func _buttons_ok(skill: Skill, buttons: Dictionary) -> bool:
	var required := skill.required_buttons
	if required.is_empty():
		return true
	if skill.button_mode == Skill.MODE_ANY:
		for button_name in required:
			if buttons.has(button_name):
				return true
		return false
	for button_name in required:
		if not buttons.has(button_name):
			return false
	return true


## Phase 6 只读钩子：第 i 个动作现在处于什么阶段（不进本阶段夹具）。
##
## `tracking` 用 `detector.status()` 是否等于「待机」判断：三个检测器共用这个
## 空闲标记，且都只在类文档承诺的同一语义下使用它。`cooldown` 用最近一帧的
## 时间戳计算，避免再要求调用方传 now。
func state_of(i: int) -> StringName:
	if i < 0 or i >= _skills.size():
		return &"idle"
	var active := _skills[i]
	if _gesture_locked:
		return &"locked"
	if (_now - active.last_fire) * 1000.0 < float(active.skill.cooldown_ms):
		return &"cooldown"
	var text := active.detector.status()
	if text != "" and text != "待机":
		return &"tracking"
	return &"idle"


## Phase 6 只读钩子：第 i 个动作的逐动作冷却还剩多少毫秒（0 表示已就绪）。
func cooldown_remaining_ms(i: int, now: float) -> float:
	if i < 0 or i >= _skills.size():
		return 0.0
	var active := _skills[i]
	return maxf(0.0, float(active.skill.cooldown_ms) - (now - active.last_fire) * 1000.0)
