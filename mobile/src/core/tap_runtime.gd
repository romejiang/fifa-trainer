class_name TapRuntime
extends RefCounted

## 单动作 tap 运行时：`desktop/padskills/engine.py:198-363` 里 tap 动作真正用到的那部分引擎。
##
## 为什么需要它：「两次独立判定」不是检测器的性质，是引擎的性质 —— `cooldown_ms`、
## `global_cooldown_ms`、手势锁、失败单槽、`GROUP_SIZE` 全在 engine.py 里。只移植
## `TapDetector` 无法解释「快速连做两次」，所以判定链的另一半必须一起搬过来。
##
## 分支顺序就是语义，与参考实现逐条对应，一步不许换：
##   1. 未启用（`relative_to_ls` 的技能）→ 直接返回；
##   2. **未确认布局 → 直接返回**（移动端独有硬门，见下）；
##   3. 手势锁：锁定期内**不调用检测器、不 drain**；锁满时调一次 `on_idle()` 再解锁，
##      解锁那一帧继续走判定（与 engine.py:219-233 相同）；
##   4. 修饰键不满足：先 `observe()` 再 `reset()`（顺序不能反，reset 用 `_prev_pressed`
##      决定 `_armed`），然后 drain；
##   5. `update()` → Hit 后先逐动作冷却、再全局冷却；两者吞掉命中时都不记 Outcome；
##   6. 真正命中：计数、分组、记 Outcome、置手势锁；
##   7. drain 失败单槽（一次 tick 最多取一条）。
##
## ## 布局硬门（不是 Python 行为）
##
## `layout_confirmed == false` 是本类 `tick()` 的**第一早退**，位于手势锁判断之前。
## 理由：成功标准 4「未确认轴映射不得前进」如果只由界面状态机实现，任何绕过界面的
## 路径都能产出判定。界面另有状态机，但这里才是唯一的机械保证 —— 无头断言可以在
## 没有窗口、没有手柄的环境里证明「零判定」。
##
## ## 刻意的移动端改良（不是分歧）
##
## Python 的引擎用 `last_outcome` + `outcome_seq`，同一帧若产生两条，第一条会被静默
## 吞掉。移动端改为 `Array[Outcome]` 队列 + `pop_outcomes()` 全量 drain，每个
## `Outcome` 带单调 `seq`。「不丢结果」从约定变成结构，判定集合与 Python 完全一致。
##
## ## 本阶段刻意的范围收缩（Phase 5 必须还原）
##
## - 手势锁按「右摇杆恒回中」的最保守路径实现：命中后固定锁满 `gesture_release_ms`
##   （150 ms），锁满时调一次 `on_idle()`。Phase 5 的 `Frame` 有了 `rs_mag` 之后，
##   要还原成「右摇杆真正回中才计时，推着就不解锁」（engine.py:219-233）。
## - `idle_reset_ms` 计时器**未移植**。论证：引擎的 idle 路径只调用 `on_idle()`，而
##   `TapDetector.on_idle()` 是空实现，所以对 tap 场景零行为差异。Phase 5 移植
##   arc / sequence 时必须补上，否则「摇杆静置后清空半截进度」会缺失。
## - `_discard_other_claims`、`held_required`（别的技能的修饰键）在单技能场景下不可达，
##   不移植。`relative_to_ls` 则在构造时留了一道硬护栏：没有左摇杆基准就整个禁用，
##   绝不在缺基准的情况下判相对动作。

## 每做对这么多个算一组，满了清零重新数（engine.py:93 的 `GROUP_SIZE`）。
const GROUP_SIZE := 10

## 供 UI 只读的状态。计数与参考实现的 `ActiveSkill` 同名字段一一对应。
var skill_name: String = ""
var layout_confirmed: bool = false
var hits: int = 0
var attempts: int = 0
var group_hits: int = 0
var groups_done: int = 0
## 被全局冷却吞掉的命中次数（逐动作冷却吞掉时**不**计数，与 engine.py:289-293 一致）。
var suppressed: int = 0
## 组容量。默认 `GROUP_SIZE`，构造可注入更小值 —— 只在无头证明里用来两发就看到归零。
var group_size: int = GROUP_SIZE

var _skill: Skill = null
var _detector: TapDetector = null
## `relative_to_ls` 的技能在本阶段没有左摇杆基准，整个运行时禁用（见类文档）。
var _enabled: bool = true
var _global_cooldown_ms: int = 0
var _gesture_release_ms: int = 0
var _last_fire: float = -1e9
var _last_any_fire: float = -1e9
var _gesture_locked: bool = false
## 成对表示，不用 -1.0 当哨兵：0.0 是合法时间戳。
var _have_lock_release_since: bool = false
var _lock_release_since: float = 0.0
var _outcomes: Array[Outcome] = []
var _seq: int = 0


## `p_layout_confirmed` 默认 false：宁可什么都不判，也不要在轴映射未确认时给结论。
## `p_group_size` 只为了在没有设备的环境里用两次命中证明分组归零；默认值必须等于
## 常量 `GROUP_SIZE`，真实运行时不传这个参数。
func _init(p_skill: Skill, p_global_cooldown_ms: int, p_gesture_release_ms: int,
		p_layout_confirmed := false, p_group_size: int = GROUP_SIZE) -> void:
	_skill = p_skill
	skill_name = p_skill.name
	_global_cooldown_ms = p_global_cooldown_ms
	_gesture_release_ms = p_gesture_release_ms
	layout_confirmed = p_layout_confirmed
	group_size = p_group_size
	_detector = TapDetector.new(p_skill)
	_enabled = not p_skill.relative_to_ls


## 「只练绿色搓射」的唯一实现点：按 `kind` 选，绝不按名字或下标。
##
## 真实配置里 `skills` 的顺序是 Roulette / Stepover / Heel-to-Heel / La Croqueta /
## Green Finesse —— 绿色搓射是**最后一个**。任何 `skills[0]` 的写法都会读到马赛回旋
## （arc），于是「命中次数」永远是 0。名字可以被翻译改掉，`kind` 不会。
## 零个或多个 taps 动作都返回 null：运行时的语义是「唯一一个」。
static func select_taps_skill(config: AppConfig) -> Skill:
	var found: Skill = null
	for skill in config.enabled_skills():
		if skill.kind != Skill.KIND_TAPS:
			continue
		if found != null:
			return null
		found = skill
	return found


## 一帧。分支顺序见类文档，不许重排。
func tick(frame: Frame) -> void:
	# 1. 相对左摇杆的动作：本阶段没有左摇杆基准，绝不判。
	if not _enabled:
		return

	# 2. 未确认布局：第一早退，必须在手势锁之前。这条是成功标准 4 的机械保证。
	if not layout_confirmed:
		return

	# 3. 手势锁：锁定期间检测器看不到任何帧，失败也不 drain。
	if _gesture_locked:
		if not _have_lock_release_since:
			_have_lock_release_since = true
			_lock_release_since = frame.now
		if (frame.now - _lock_release_since) * 1000.0 >= float(_gesture_release_ms):
			_detector.on_idle()
			_gesture_locked = false
			_have_lock_release_since = false
			_lock_release_since = 0.0
		else:
			return

	# 4. 修饰键不满足：先 observe 再 reset，顺序不能反。
	if not _buttons_ok(frame.buttons):
		_detector.observe(frame)
		_detector.reset()
		_drain(frame.now)
		return

	# 5. 推进判定。
	var hit := _detector.update(frame)
	if hit != null:
		# 逐动作冷却：**静默**丢弃，不记 Outcome、不加 suppressed（engine.py:289-290）。
		if (frame.now - _last_fire) * 1000.0 < float(_skill.cooldown_ms):
			_drain(frame.now)
			return
		# 全局冷却：吞掉时 suppressed 加一（engine.py:291-293）。
		if (frame.now - _last_any_fire) * 1000.0 < float(_global_cooldown_ms):
			suppressed += 1
			_drain(frame.now)
			return

		# 6. 真正命中。
		_last_fire = frame.now
		hits += 1
		attempts += 1
		group_hits += 1
		if group_hits >= group_size:
			group_hits = 0
			groups_done += 1
		_last_any_fire = frame.now
		_record(true, &"ok", "", hit.elapsed_ms, frame.now, hit.summary)
		# 一次物理动作只认一次；下一个动作要等手势锁走完。
		_gesture_locked = true
		_have_lock_release_since = false
		_lock_release_since = 0.0

	# 7. 失败单槽：不管它是在 update() 还是 reset() 里产生的，只在这一点进队列。
	_drain(frame.now)


## 成功 / 失败都从这里进队列；`seq` 从 1 开始单调递增。
func _record(ok: bool, code: StringName, message: String, elapsed_ms: float,
		at: float, detail: String) -> void:
	var outcome := Outcome.new()
	outcome.skill_name = skill_name
	outcome.ok = ok
	outcome.code = code
	outcome.message = message
	outcome.elapsed_ms = elapsed_ms
	outcome.at = at
	outcome.detail = detail
	_seq += 1
	outcome.seq = _seq
	_outcomes.append(outcome)


## UI 唯一的结果入口：返回当前队列的副本并清空内部队列（全量 drain，绝不覆盖）。
## 用 `assign` 而不是直接返回内部数组：调用方拿到的是副本，改它不会影响运行时。
func pop_outcomes() -> Array[Outcome]:
	var drained: Array[Outcome] = []
	drained.assign(_outcomes)
	_outcomes.clear()
	return drained


## 未确认布局时明确说出来；否则委托检测器（它知道第一下按到了没有）。
func status() -> String:
	if not layout_confirmed:
		return "未确认布局"
	return _detector.status()


## 布局确认状态由界面/设备层设置。从「已确认」变回「未确认」时必须**静默清场**：
## 手柄在搓射中途断开时 `now` 会跳走几分钟，恢复后继续用旧的 `_t0` 必然报 `too_slow`。
## 断连不是一次尝试，不能产出判定 —— 所以用 `abandon()`（静默）而不是 `reset()`
## （后者会产 `hold_short`），并清空尚未取走的 Outcome。
func set_layout_confirmed(value: bool) -> void:
	var was := layout_confirmed
	layout_confirmed = value
	if was and not value:
		_detector.abandon()
		_gesture_locked = false
		_have_lock_release_since = false
		_lock_release_since = 0.0
		_outcomes.clear()


## 修饰键判定，两种模式都要（Phase 5 的 sequence 动作会用 `any`）。
func _buttons_ok(buttons: Dictionary) -> bool:
	var required := _skill.required_buttons
	if required.is_empty():
		return true
	if _skill.button_mode == Skill.MODE_ANY:
		for button_name in required:
			if buttons.has(button_name):
				return true
		return false
	for button_name in required:
		if not buttons.has(button_name):
			return false
	return true


## 一次 tick 最多取一条失败：检测器是单槽覆盖写，这里全量取走即清空。
func _drain(now: float) -> void:
	var failure := _detector.pop_failure()
	if failure == null:
		return
	attempts += 1
	_record(false, failure.code, failure.message, failure.elapsed_ms, now, "")
