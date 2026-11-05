class_name SequenceDetector
extends Detector

## 方向点拨序列识别：逐行移植 desktop/padskills/detectors.py:453-853。
##
## 每一步可以是：
##     "forward"                                      单一方向（点拨一下）
##     ["left", "right"]                              任一方向
##     {"direction": [...], "hold_ms": 500}           方向对了还要保持住
##
## hold_ms 用来区分「点拨」和「按住」—— 比如 La Croqueta 需要按住侧向约半秒
## 才算数，光推一下不算。
##
## 时间口径：`Frame.now` 是**秒**；`*_ms` 全部是毫秒。序列从「首次命中第一步」
## 开始计时（这样耗时里包含保持时间）。
##
## 状态成对表示，不用负时间戳当哨兵：`_have_t0` / `_have_release_since` /
## `_have_hold_since`。`t0 = 0.0` 是合法时间戳，用 -1 当哨兵会在某些时间轴上
## 变成「真的已建立」。`_step_lo` / `_step_hi` 用无类型 Array，元素是 null 或
## float —— 不用 NAN 当哨兵（NAN 参与比较永远是 false，会把统计静默吞掉）。
##
## 方向基准：序列一旦开始，`last_base` 就固定为起手时的左摇杆朝向；中途左摇杆
## 怎么动都不再改变判定基准，避免动作中途「换了参照系」。
##
## `measured` 只由本类在产生 `Hit` / `Failure` 的那一刻构造（`_measured()`）：每一步的
## 实际保持时长与**完成时刻**都来自判定现场的累积量（`_step_t` 是纯增量字段，不进
## 任何判定分支）。UI 不得二次计算，也不得从文案里抠数字。


## 已校验的方向步骤。
var steps: Array[Step] = []
var tolerance: float = 35.0
var enter: float = 0.65
var release: float = 0.35
var max_ms: float = 700.0
var min_ms: float = 300.0
var idle_ms: float = 250.0
## 「还在动」判据：与冻结的参考角比，不是相邻两帧。
var motion_delta: float = 2.0
var require_neutral: bool = true
var relative: bool = false

## 触发之后必须「真正松手」一段时间才允许再次触发。
## 只判 mag < release 不够：摇杆在阈值附近抖一下（甚至只有一帧）就会重新武装，
## 表现出来就是「按住不放却一直震」。
var release_hold_ms: float = 150.0

var _name: String = ""

var index: int = 0
var _have_t0: bool = false
var t0: float = 0.0
var neutral: bool = true
## false = 已触发过，等一次「真正的松手」。
var _armed: bool = true
var _have_release_since: bool = false
var _release_since: float = 0.0
var last_base: float = 0.0
var _have_hold_since: bool = false
var _hold_since: float = 0.0
var _now: float = 0.0
var _last_motion: float = 0.0
var _last_angle: float = 0.0
var _last_mag: float = 0.0
var _have_last: bool = false
var _motion_ref_angle: float = 0.0
var _best_hold_ms: float = 0.0
## 每一步匹配期间的相对角度统计：最低 / 最高 / 总和 / 样本数。
var _step_lo: Array = []
var _step_hi: Array = []
var _step_sum: Array[float] = []
var _step_n: Array[int] = []
## 每一步**完成**的时刻（毫秒口径的时间轴值）；元素是 `null` 或 `float`。
## 纯增量字段：只在 `index += 1` 的同一处写入、只在构造 `measured` 时读取，
## **不得出现在任何判定条件里**（T-05-15）。`_have_step_t` 与它成对表示
## 「有没有写过」，与仓库的 `_have_*` 纪律一致。
var _step_t: Array = []
var _have_step_t: bool = false
var _facing: float = 0.0
var _buttons: Dictionary = {}
var _required: Array[String] = []
var _button_mode: StringName = Skill.MODE_ALL


## 构造参数来自已校验的 Skill：`max_ms <= min_ms` 与 steps 非空都已由
## ConfigValidator 拦下，这里只做转换与默认值。
func _init(skill: Skill) -> void:
	var params: Dictionary = skill.params
	var raw_steps: Variant = params.get("steps", [])
	steps = []
	if typeof(raw_steps) == TYPE_ARRAY:
		for item in raw_steps:
			var parsed := _parse_step(item)
			if parsed != null:
				steps.append(parsed)

	tolerance = float(params.get("tolerance_deg", 35.0))
	enter = float(params.get("enter_threshold", 0.65))
	release = float(params.get("release_threshold", 0.35))
	if release >= enter:
		# 与弧线的 -0.05 不同：序列的迟滞带更宽，别抄错。
		release = maxf(0.0, enter - 0.15)
	max_ms = float(params.get("max_duration_ms", 700.0))
	min_ms = float(params.get("min_duration_ms", 300.0))
	idle_ms = float(params.get("idle_timeout_ms", 250.0))
	motion_delta = float(params.get("motion_min_delta_deg", 2.0))
	require_neutral = bool(params.get("require_neutral_between_steps", true))
	relative = skill.relative_to_ls
	_name = skill.name.split(" (")[0]
	release_hold_ms = float(params.get("release_hold_ms", 150.0))

	_required = skill.required_buttons.duplicate()
	_button_mode = skill.button_mode
	_reset_metrics()


## 把已校验的步骤写法转成 domain 对象（config.py:166-189 的最小对等版本）。
## 合法性（空数组、非法方向、负数 hold）已在 ConfigValidator 里变成中文错误，
## 这里不再重复校验或抛错 —— 拿到 null 表示该步在原始配置里就是坏的。
func _parse_step(value: Variant) -> Step:
	if typeof(value) == TYPE_DICTIONARY:
		var dict: Dictionary = value
		var direction: Variant = dict.get("direction", dict.get("dir", null))
		var hold_ms := float(dict.get("hold_ms", 0.0))
		var inner := _parse_step(direction)
		if inner == null:
			return null
		return Step.new(inner.angles, hold_ms)
	var group: Array = value if typeof(value) == TYPE_ARRAY else [value]
	if group.is_empty():
		return null
	var angles: Array[float] = []
	for item in group:
		var resolved: Variant = DirectionTable.resolve(item)
		if typeof(resolved) != TYPE_FLOAT:
			return null
		angles.append(float(resolved))
	return Step.new(angles, 0.0)


## 与 config.py:525-527 的 `_match` 一致：任一步方向命中即可。
func _match(rel_angle: float, step: Step) -> bool:
	for target in step.angles:
		if Geometry.angle_diff(rel_angle, target) <= tolerance:
			return true
	return false


func _reset_metrics() -> void:
	var count := steps.size()
	_step_lo = []
	_step_hi = []
	_step_sum = []
	_step_n = []
	_step_t = []
	for _i in range(count):
		_step_lo.append(null)
		_step_hi.append(null)
		_step_sum.append(0.0)
		_step_n.append(0)
		_step_t.append(null)
	_have_step_t = false


func _note_angle(step_index: int, angle: float) -> void:
	if step_index < 0 or step_index >= steps.size():
		return
	var lo: Variant = _step_lo[step_index]
	var hi: Variant = _step_hi[step_index]
	_step_lo[step_index] = angle if lo == null else minf(float(lo), angle)
	_step_hi[step_index] = angle if hi == null else maxf(float(hi), angle)
	_step_sum[step_index] += angle
	_step_n[step_index] += 1


## 角度文案：区间小于 3° 时只显示平均角，否则显示区间与平均（detectors.py:546-555）。
func _step_angle_text(step_index: int) -> String:
	var count := int(_step_n[step_index])
	if count == 0:
		return ""
	var lo := float(_step_lo[step_index])
	var hi := float(_step_hi[step_index])
	var avg := float(_step_sum[step_index]) / float(count)
	if hi - lo < 3.0:
		return "%.0f°" % avg
	return "%.0f°~%.0f°（平均 %.0f°）" % [lo, hi, avg]


func _summary(hold_ms: float) -> String:
	var parts := PackedStringArray()
	for step_index in range(steps.size()):
		var step: Step = steps[step_index]
		var angle := _step_angle_text(step_index)
		if angle.is_empty():
			continue
		var text := "%s %s" % [step.label(), angle]
		if step.hold_ms > 0.0 and step_index == steps.size() - 1:
			text += " 保持 %.0fms" % hold_ms
		parts.append(text)
	var joined := " · ".join(parts)
	if joined.is_empty():
		return ""
	return "相对朝向 %s" % joined


## 构造本次判定的结构化度量（JUDGE-05，RESEARCH §D.5 的 Sequence 字段表）。
##
## 只在产生 `Hit` / `Failure` 的那一刻调用；数值全部来自 `_step_lo/_hi/_sum/_n`、
## `_step_t` 与调用方给出的保持时长，这里不重算判定。
##
## `hold_ms` 只对 `hold_index` 那一步有意义：成功路径传已经取出的 `fired_hold_ms`，
## 失败路径传 `_best_hold_ms`；其余步骤写 0 —— 与参考实现 `_summary()` 只保留最后
## 一步保持时长的口径一致（detectors.py:559-568）。
func _measured(elapsed_ms: float, hold_ms: float, hold_index: int) -> Dictionary:
	var base := last_base if relative else 0.0
	var steps_data: Array = []
	for step_index in range(steps.size()):
		var count: int = _step_n[step_index]
		var average: Variant = null
		if count > 0:
			average = float(_step_sum[step_index]) / float(count)
		steps_data.append({
			"label": steps[step_index].label(),
			"required_hold_ms": steps[step_index].hold_ms,
			"actual_hold_ms": hold_ms if step_index == hold_index else 0.0,
			"t_done_ms": _step_t[step_index],
			"angle_lo_deg": _step_lo[step_index],
			"angle_hi_deg": _step_hi[step_index],
			"angle_avg_deg": average,
		})
	return {
		"kind": "sequence",
		"elapsed_ms": elapsed_ms,
		"base_deg": base,
		"tolerance_deg": tolerance,
		"steps": steps_data,
	}


func _clear_progress() -> void:
	index = 0
	_have_t0 = false
	t0 = 0.0
	_have_hold_since = false
	_hold_since = 0.0
	_best_hold_ms = 0.0
	_reset_metrics()


## 作废当前序列，必须回中够久才允许重新开始。
func _abort() -> void:
	_clear_progress()
	neutral = false
	_armed = false
	_have_release_since = false
	_release_since = 0.0
	_last_motion = 0.0


## 序列还没做完就被放弃：给出原因（调用前 t0 / index 必须还在）。
## 优先级逐字保持（detectors.py:585-612）：
##   timed_out → too_slow；否则 hold 步已攒过时间 → hold_short；
##   否则 index > 0 → incomplete；否则 null。
func _abandon_failure(now: float, timed_out := false) -> Failure:
	if not _have_t0:
		return null
	var elapsed_ms := (now - t0) * 1000.0
	var current := mini(index, steps.size() - 1)
	var step: Step = steps[current]
	# 失败路径的保持时长就是 `_best_hold_ms`；它只可能属于当前这一步。
	var measured := _measured(elapsed_ms, _best_hold_ms, current)
	if timed_out:
		return Failure.new(
			&"too_slow",
			"太慢了：用了 %.0fms（上限 %.0fms）" % [elapsed_ms, max_ms],
			elapsed_ms,
			measured,
		)
	if step.hold_ms > 0.0 and _best_hold_ms > 0.0:
		return Failure.new(
			&"hold_short",
			"保持不够：只保持了 %.0fms（需要 %.0fms）" % [_best_hold_ms, step.hold_ms],
			elapsed_ms,
			measured,
		)
	if index > 0:
		var done := PackedStringArray()
		for step_index in range(index):
			done.append(steps[step_index].label())
		return Failure.new(
			&"incomplete",
			"没做完：只做到第 %d/%d 步（%s → 还差 %s）"
				% [index, steps.size(), " → ".join(done), step.label()],
			elapsed_ms,
			measured,
		)
	return null


## 真正静置一段时间后：把没做完的尝试记一笔，再清空并允许起手。
func on_idle() -> void:
	var failure := _abandon_failure(_now)
	if failure != null:
		_emit(failure)
	_clear_progress()
	neutral = true
	_armed = true
	_have_release_since = false
	_release_since = 0.0
	_last_motion = 0.0
	_have_last = false


## 分支顺序即语义（detectors.py:626-768），十三步不能重排。
func update(frame: Frame) -> Hit:
	var now := frame.now
	_now = now
	_facing = frame.facing
	_buttons = frame.buttons
	var mag := frame.rs_mag

	# 记录右摇杆是否发生了有意义的变化。动作之间停顿太久时，这个计时器会把
	# 没做完的序列清掉，防止「上一个动作的尾巴」接成下一个动作。
	# 注意幅度阈值是 0.06，弧线是 0.05 —— 两处不同，别统一。
	var moved := (not _have_last
		or Geometry.angle_diff(_motion_ref_angle, frame.rs_angle) >= motion_delta
		or absf(_last_mag - mag) >= 0.06)
	if moved:
		_motion_ref_angle = frame.rs_angle
	_last_angle = frame.rs_angle
	_last_mag = mag
	_have_last = true

	if _have_t0:
		var base := last_base if relative else 0.0
		var rel_angle := Geometry.norm_deg(frame.rs_angle - base)
		var step: Step = steps[mini(index, steps.size() - 1)]
		var holding := (
			step.hold_ms > 0.0
			and mag >= enter
			and _match(rel_angle, step)
		)
		if mag >= enter and _match(rel_angle, step):
			_note_angle(index, rel_angle)
		if holding and _have_hold_since:
			_best_hold_ms = maxf(_best_hold_ms, (now - _hold_since) * 1000.0)
		if holding or moved:
			_last_motion = now

		var timed_out := (now - t0) * 1000.0 > max_ms
		var stalled := (now - _last_motion) * 1000.0 > idle_ms
		if timed_out or stalled:
			var failure := _abandon_failure(now, timed_out)
			if failure != null:
				_emit(failure)
			_abort()
			# 还推着摇杆就先不继续判，必须回中之后重新起手。
			if mag >= release:
				return null

	if mag < release:
		if not _have_release_since:
			_have_release_since = true
			_release_since = now
		# 回中：允许下一步。
		neutral = true
		_have_hold_since = false
		_hold_since = 0.0
		# 已经触发过的动作，要连续松开够久才重新武装。
		if not _armed and (now - _release_since) * 1000.0 >= release_hold_ms:
			_armed = true
		return null
	_have_release_since = false

	if mag < enter:
		return null
	if not _armed:
		return null
	if require_neutral and not neutral:
		return null

	# 序列一旦开始，方向基准就固定为起手时的左摇杆朝向。
	var facing_now := frame.facing if relative else 0.0
	var base := last_base if _have_t0 else facing_now
	var rel_angle := Geometry.norm_deg(frame.rs_angle - base)
	var step: Step = steps[index]

	if not _match(rel_angle, step):
		_have_hold_since = false
		# 没匹配上当前这一步，但如果命中了第一步，说明是一次新的起手
		# （例如想搓「前-后」却先搓成了「前-前-后」），允许从头重来。
		if index > 0:
			var rel_first := Geometry.norm_deg(frame.rs_angle - facing_now)
			if _match(rel_first, steps[0]):
				index = 1
				_have_t0 = true
				t0 = now
				last_base = facing_now
				neutral = false
				_last_motion = now
				_motion_ref_angle = frame.rs_angle
				_have_hold_since = false
				_hold_since = 0.0
				_best_hold_ms = 0.0
		return null

	# 方向对了，序列从这一刻开始计时（这样耗时里会包含保持时间）。
	if not _have_t0:
		_have_t0 = true
		t0 = now
		last_base = base
		_last_motion = now
		_motion_ref_angle = frame.rs_angle
		_best_hold_ms = 0.0
		_reset_metrics()
		_note_angle(index, rel_angle)

	# 如果这一步要求保持，先攒够时间再说。
	if step.hold_ms > 0.0:
		if not _have_hold_since:
			_have_hold_since = true
			_hold_since = now
			_best_hold_ms = 0.0
		var held_ms := (now - _hold_since) * 1000.0
		_best_hold_ms = maxf(_best_hold_ms, held_ms)
		if held_ms < step.hold_ms:
			return null

	# 最后一步如果整体太快，直接作废，不能等时长到了再补触发。
	if index == steps.size() - 1:
		var elapsed_ms := (now - t0) * 1000.0
		if elapsed_ms < min_ms:
			_emit(Failure.new(
				&"too_fast",
				"太快了：整个动作只用了 %.0fms（至少 %.0fms）" % [elapsed_ms, min_ms],
				elapsed_ms,
				_measured(elapsed_ms, _best_hold_ms, index),
			))
			_abort()
			return null

	index += 1
	neutral = false
	# 记录**完成**这一步的时刻。纯增量：只有 measured.steps[].t_done_ms 读它，
	# 任何判定分支都不读（T-05-15）。写在 `index += 1` 的同一处，语义是「刚完成
	# 的是上一索引那一步」。
	_step_t[index - 1] = now
	_have_step_t = true
	# 保持时长要在清零前取出来，否则成功摘要里永远是 0ms。
	var fired_hold_ms := _best_hold_ms if step.hold_ms > 0.0 else 0.0
	_have_hold_since = false
	_hold_since = 0.0
	_best_hold_ms = 0.0
	_last_motion = now

	if index >= steps.size():
		var elapsed_ms := (now - t0) * 1000.0
		var detail := _describe()
		var summary := _summary(fired_hold_ms)
		# 必须赶在 `_reset_metrics()` 之前构造：保持时长与完成时刻都在那里被清空。
		var measured := _measured(elapsed_ms, fired_hold_ms, steps.size() - 1)
		index = 0
		_have_t0 = false
		t0 = 0.0
		# 必须等一次「真正的松手」才能再触发。
		_armed = false
		_have_release_since = false
		_release_since = 0.0
		_reset_metrics()
		return Hit.new(elapsed_ms, detail, summary, measured)
	return null


func _describe() -> String:
	var parts := PackedStringArray()
	for step in steps:
		var text := step.label()
		if step.hold_ms > 0.0:
			text += "(保持%.0fms)" % step.hold_ms
		parts.append(text)
	var scope := ("相对左摇杆朝向(基准 %.0f°)" % last_base) if relative else "屏幕绝对方向"
	return "序列 [%s] %s 容错 ±%.0f°" % [" → ".join(parts), scope, tolerance]


## 修饰键松开时作废进度。
##
## 这里**不能**动 neutral：它描述的是「摇杆位置」，跟按键无关。如果把 neutral
## 置回 true，摇杆明明还推着、只是 L1 抖了一帧，就会被当成「已经回中」，
## 于是按住不放就反复触发。
##
## 但 _armed 要置回 true。修饰键已经松开了，说明上一次动作结束，用户完全可能
## 「先松 L1、再回中摇杆」—— 如果这里不解除武装，下一次按住 L1 推杆会被当成
## 上一次动作的余波，永远触发不了。neutral 仍然是 false，所以摇杆还推着时
## 不会立刻重复触发。
func reset() -> void:
	if _have_t0 and _have_hold_since:
		var failure := _abandon_failure(_now)
		if failure != null:
			_emit(failure)
	index = 0
	_have_t0 = false
	t0 = 0.0
	_have_hold_since = false
	_hold_since = 0.0
	_best_hold_ms = 0.0
	_armed = true


## 不能继承基类的 abandon()：基类会调 reset()，把「已被别人认领」变成
## 「可以立刻重试」（detectors.py:804-806）。
func abandon() -> void:
	_pending = null
	_abort()


func observe(frame: Frame) -> void:
	_now = frame.now
	_facing = frame.facing
	_buttons = frame.buttons
	_last_angle = frame.rs_angle
	_last_mag = frame.rs_mag
	_have_last = true


func _modifier_held() -> bool:
	if _required.is_empty():
		return true
	if _button_mode == Skill.MODE_ANY:
		for required_button in _required:
			if _buttons.has(required_button):
				return true
		return false
	for required_button in _required:
		if not _buttons.has(required_button):
			return false
	return true


## 配置里写的是 L1/R1，规范化后是 LB/RB；提示里说回用户熟悉的叫法。
func _modifier_label() -> String:
	var alias := {"LB": "L1", "RB": "R1", "LT": "L2", "RT": "R2"}
	var parts := PackedStringArray()
	for required_button in _required:
		parts.append(alias.get(required_button, required_button))
	return "/".join(parts)


func status() -> String:
	if index == 0 and not _have_t0:
		# 还没起手：把「卡在哪一步」直接显示出来，识别不到时好排查。
		# 只对带修饰键的动作做提示 —— 否则随便推杆时每张卡片都在喊「方向不对」。
		if not (not _required.is_empty() and _armed and _last_mag >= enter):
			return "待机"
		var base := _facing if relative else 0.0
		var rel := Geometry.norm_deg(_last_angle - base)
		var first: Step = steps[0]
		var matched := _match(rel, first)
		if not _modifier_held():
			if matched:
				return "方向对了，要按住 %s" % _modifier_label()
			return "待机"
		if require_neutral and not neutral:
			return "先松开右摇杆回中"
		if not matched:
			return "方向不对：当前相对 %.0f°，要 %s" % [rel, first.label()]
		return "待机"
	var step: Step = steps[mini(index, steps.size() - 1)]
	if step.hold_ms > 0.0 and _have_hold_since:
		var held := (_now - _hold_since) * 1000.0
		return "保持 %s %.0f/%.0fms" % [step.label(), held, step.hold_ms]
	return "已匹配 %d/%d，等 %s" % [index, steps.size(), step.label()]
