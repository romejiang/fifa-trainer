class_name ArcDetector
extends Detector

## 右摇杆画弧 / 转圈识别：逐行移植 desktop/padskills/detectors.py:125-446。
##
## 状态机：
##     armed   —— 可以开始一段新的画弧（必须等摇杆回落才重新武装，
##                避免同一个动作被反复触发）
##     active  —— 正在累计旋转角度
##
## 时间口径：`Frame.now` 是**秒**；`*_ms` 全部是毫秒。`swept` / `end_rel` /
## `elapsed_ms` 会进 `%.0f` 文案，黄金生成器负责拒绝这些值落在取整刀口上。
##
## 角度：一律走 `Geometry.signed_delta` / `norm_deg` / `angle_diff`，不手写取模 ——
## 0°/360° 环绕与最短弧是判定正确性的一部分。
##
## 状态成对表示，不用 `-1.0` 当哨兵：`_have_release_since` + `_release_since`。
## 参考实现的 `Optional[float]` 在这里对应「有没有」的布尔 + 值，语义完全一致。
##
## 起点约束是区分动作的关键：从前往侧转 90° 是踩单车，从后往前转 180° 才是
## 马赛回旋，所以 `start_target` 为 null 以外的情况都要把起点纳入判定。
##
## 六个 abort 分支的顺序是语义的一部分（detectors.py:323-404）：
## `wrong_start → wrong_direction → overshoot → stalled → too_slow → too_fast`。
## 它们都会 abort，所以顺序只影响报告哪条原因，不影响是否触发 —— 但「报哪条」
## 正是用户看到的反馈，不能重排。

## 推过这个幅度才算起手。
var enter: float = 0.80
## 掉到这个幅度以下算松手结束（必须比 enter 小，做迟滞）。
var exit: float = 0.60

var min_angle: float = 150.0
var max_angle: float = 220.0
var min_ms: float = 300.0
var max_ms: float = 700.0
## 停在原地不转超过这么久就作废。
var idle_ms: float = 180.0
## 「还在动」判据：与冻结的参考角比，不是相邻两帧。
var motion_delta: float = 2.0

## 0 = 任意，1 = 顺时针，-1 = 逆时针。
var direction: int = 0
var direction_label: String = "任意"

## 起点目标；`_have_start_target == false` 表示配置里是 null（不限制起点）。
var start_target: float = 0.0
var _have_start_target: bool = false
var start_tolerance: float = 60.0

## 终点目标集合；空数组 = 不限制终点。
var end_targets: Array[float] = []
var end_tolerance: float = 60.0

## 触发/作废后要连续回中这么久才允许下一段。
var release_hold_ms: float = 120.0
## 起点落在 start_tolerance + claim_margin 之内，才算「这次手势是冲我来的」。
var claim_margin: float = 20.0
## 太小的抖动不值得报「转得不够」。
var report_min_angle: float = 20.0
var relative: bool = false

var _name: String = ""

var armed: bool = true
var active: bool = false
var t0: float = 0.0
var acc: float = 0.0
var last_angle: float = 0.0
## 显示用：起点的绝对角度。
var start_angle: float = 0.0
## 判定用：起点换算到判定基准后的角度。
var start_rel: float = 0.0
var end_rel: float = 0.0
## 本次动作使用的方向基准，中途不随左摇杆改变。
var base: float = 0.0
var samples: int = 0

var _last_motion: float = 0.0
var _last_mag: float = 0.0
var _motion_ref_angle: float = 0.0
var _have_release_since: bool = false
var _release_since: float = 0.0
## 轨迹粗采样：(t_ms, angle, mag)，上限 64 点、间隔 ≥ 8 ms。
var _path: Array = []
var _last_path_t: float = -1e9
var _claimed: bool = false
var _turn_sign: int = 0

## `measured()` 的快照：在终结路径上由 `_capture_measured()` 写入，不重算。
var _measured_elapsed_ms: float = 0.0
var _measured_swept_deg: float = 0.0
var _measured_end_angle: float = 0.0
var _measured_end_rel: float = 0.0
var _measured_samples: int = 0
var _measured_direction_sign: int = 0


## 构造参数来自已校验的 Skill：默认值与迟滞关系逐字照抄参考实现。
## `max_ms <= min_ms` 在 Python 抛 ValueError；GDScript 侧不抛 ——
## ConfigValidator 已在校验期拦下同一条件，core 不把异常当控制流（detector.gd:5-7）。
func _init(skill: Skill) -> void:
	var params: Dictionary = skill.params
	enter = float(params.get("enter_threshold", 0.80))
	exit = float(params.get("exit_threshold", minf(0.60, enter)))
	if exit >= enter:
		# 迟滞必须成立，否则会在阈值附近疯狂抖动。
		exit = maxf(0.0, enter - 0.05)

	min_angle = float(params.get("min_angle", 150.0))
	max_angle = float(params.get("max_angle", 220.0))
	min_ms = float(params.get("min_duration_ms", 300.0))
	max_ms = float(params.get("max_duration_ms", 700.0))
	idle_ms = float(params.get("idle_timeout_ms", 180.0))
	motion_delta = float(params.get("motion_min_delta_deg", 2.0))

	var raw_direction := str(params.get("direction", "any")).strip_edges().to_lower()
	if raw_direction in ["cw", "clockwise", "顺时针"]:
		direction = 1
	elif raw_direction in ["ccw", "counterclockwise", "逆时针"]:
		direction = -1
	else:
		direction = 0
	match direction:
		1:
			direction_label = "顺时针"
		-1:
			direction_label = "逆时针"
		_:
			direction_label = "任意"

	# start_angle 为 null 表示不限制起点。ConfigValidator 已保证能 resolve。
	var raw_start: Variant = params.get("start_angle", null)
	if raw_start != null:
		var resolved_start: Variant = DirectionTable.resolve(raw_start)
		if typeof(resolved_start) == TYPE_FLOAT:
			start_target = float(resolved_start)
			_have_start_target = true
	start_tolerance = float(params.get("start_tolerance", 60.0))

	var raw_end: Variant = params.get("end_angles", params.get("end_angle", null))
	end_targets = []
	if raw_end != null:
		var raw_values: Array = raw_end if typeof(raw_end) == TYPE_ARRAY else [raw_end]
		for value in raw_values:
			var resolved_end: Variant = DirectionTable.resolve(value)
			if typeof(resolved_end) == TYPE_FLOAT:
				end_targets.append(float(resolved_end))
	end_tolerance = float(params.get("end_tolerance", 60.0))
	release_hold_ms = float(params.get("release_hold_ms", 120.0))
	claim_margin = float(params.get("claim_margin_deg", 20.0))
	report_min_angle = maxf(20.0, min_angle * 0.35)
	relative = skill.relative_to_ls
	_name = skill.name.split(" (")[0]


## 作废本次画弧，必须等摇杆回落才允许下一次。
func _abort() -> void:
	active = false
	armed = false
	acc = 0.0
	_have_release_since = false
	_release_since = 0.0
	_turn_sign = 0


## 松手了但没成功：说清楚差在哪儿（detectors.py:220-238）。
##
## 只可能产出两种码，且**扫掠小于 `report_min_angle` 时调用方整条静默**
## （detectors.py:258）—— 太小的抖动不值得报「转得不够」。
func _release_failure(
		swept: float, elapsed_ms: float, end_rel_value: float, end_ok: bool) -> Failure:
	if swept < min_angle:
		return Failure.new(
			&"too_short",
			"转得不够：只转了 %.0f°（需要 %.0f°~%.0f°）" % [swept, min_angle, max_angle],
			elapsed_ms,
		)
	if not end_targets.is_empty() and not end_ok:
		var parts := PackedStringArray()
		for target in end_targets:
			parts.append("%.0f°" % target)
		return Failure.new(
			&"wrong_end",
			"终点不对：停在相对 %.0f°（应该回到 %s±%.0f°）"
				% [end_rel_value, "/".join(parts), end_tolerance],
			elapsed_ms,
		)
	return null


## 终点是否落在任一目标 ± 容差内；没有目标即恒真（detectors.py:254-256、:384-386）。
func _end_ok(angle: float) -> bool:
	if end_targets.is_empty():
		return true
	for target in end_targets:
		if Geometry.angle_diff(angle, target) <= end_tolerance:
			return true
	return false


## 终结时把 `%.0f` 会用到的实测值原样记下，供 `measured()` 读取。
func _capture_measured(swept: float, elapsed_ms: float, end_rel_value: float) -> void:
	_measured_elapsed_ms = elapsed_ms
	_measured_swept_deg = swept
	_measured_end_angle = last_angle
	_measured_end_rel = end_rel_value
	_measured_samples = samples
	_measured_direction_sign = _turn_sign


## 分支顺序即语义（detectors.py:240-412）：回中收尾 → 未武装 → 起手 → 累计 →
## （abort 分支）→ 终点与区间 → 太快 → 未就绪 → 成功。
func update(frame: Frame) -> Hit:
	var mag := frame.rs_mag
	var now := frame.now

	# 摇杆回落 -> 结束本次画弧；连续回中够久才重新武装。
	# 不能一低于 exit 就立刻 armed=True，否则动作结尾轻轻一抖就会被当成下一次起手。
	if mag < exit:
		var was_active := active
		if was_active and _claimed:
			var elapsed_ms := (now - t0) * 1000.0
			# 松手时摇杆已经回中，这一帧的角度没有意义；用最后一次有效角度判断终点。
			var release_end_rel := Geometry.norm_deg(last_angle - base)
			end_rel = release_end_rel
			var end_ok := _end_ok(release_end_rel)
			var swept := absf(acc)
			_capture_measured(swept, elapsed_ms, release_end_rel)
			if swept >= report_min_angle:
				var failure := _release_failure(swept, elapsed_ms, release_end_rel, end_ok)
				if failure != null:
					_emit(failure)
		active = false
		acc = 0.0
		_turn_sign = 0
		if was_active:
			armed = false
		if not _have_release_since:
			_have_release_since = true
			_release_since = now
		if not armed and (now - _release_since) * 1000.0 >= release_hold_ms:
			armed = true
		return null
	_have_release_since = false

	if not armed:
		return null

	if not active:
		if mag >= enter:
			active = true
			t0 = now
			acc = 0.0
			samples = 1
			start_angle = frame.rs_angle
			base = frame.facing if relative else 0.0
			start_rel = Geometry.norm_deg(frame.rs_angle - base)
			end_rel = start_rel
			last_angle = frame.rs_angle
			_last_motion = now
			_last_mag = mag
			_motion_ref_angle = frame.rs_angle
			_turn_sign = 0
			_path = [[0.0, frame.rs_angle, mag]]
			_last_path_t = now
			_claimed = (not _have_start_target
				or Geometry.angle_diff(start_rel, start_target)
					<= start_tolerance + claim_margin)
		return null

	# 累计旋转（走最短弧，天然处理 0°/360° 环绕）。
	var delta := Geometry.signed_delta(last_angle, frame.rs_angle)
	acc += delta
	last_angle = frame.rs_angle
	samples += 1
	# 慢速但持续的旋转也要算「在动」：用累计角度而不是单帧角度判断，
	# 否则 250Hz 下每帧只转 1° 左右的慢弧会被误判成停住。
	if (Geometry.angle_diff(_motion_ref_angle, frame.rs_angle) >= motion_delta
			or absf(mag - _last_mag) >= 0.05):
		_last_motion = now
		_motion_ref_angle = frame.rs_angle
	_last_mag = mag

	var elapsed_ms := (now - t0) * 1000.0
	if now - _last_path_t >= 0.008 and _path.size() < 64:
		_path.append([elapsed_ms, frame.rs_angle, mag])
		_last_path_t = now

	var swept := absf(acc)

	# 检查顺序按「最能说明问题」排：起点 -> 方向 -> 转多了 -> 停住 -> 太慢 -> 太快。
	# 这些分支都会 abort，所以顺序只影响报告哪条原因，不影响是否触发
	# （detectors.py:323-404）。顺序是语义的一部分，不许重排。
	if _have_start_target and Geometry.angle_diff(start_rel, start_target) > start_tolerance:
		if _claimed:
			_emit(Failure.new(
				&"wrong_start",
				"起点不对：从相对 %.0f° 起手（%s要求 %.0f°±%.0f°）"
					% [start_rel, _name, start_target, start_tolerance],
				elapsed_ms,
			))
		_capture_measured(swept, elapsed_ms, Geometry.norm_deg(frame.rs_angle - base))
		_abort()
		return null

	# 转向符号要等真的转起来再锁定：刚推出去那一帧 acc 还是 0，
	# 直接比较会把它误判成「转向反了」。
	if direction != 0 and swept >= 5.0:
		if _turn_sign == 0:
			_turn_sign = 1 if acc > 0.0 else -1
		if _turn_sign != direction:
			if _claimed:
				_emit(Failure.new(
					&"wrong_direction",
					"转向反了：应该%s" % direction_label,
					elapsed_ms,
				))
			_capture_measured(swept, elapsed_ms, Geometry.norm_deg(frame.rs_angle - base))
			_abort()
			return null

	if swept > max_angle:
		if _claimed:
			_emit(Failure.new(
				&"overshoot",
				"转多了：累计 %.0f°（上限 %.0f°）" % [swept, max_angle],
				elapsed_ms,
			))
		_capture_measured(swept, elapsed_ms, Geometry.norm_deg(frame.rs_angle - base))
		_abort()
		return null

	if (now - _last_motion) * 1000.0 > idle_ms:
		if _claimed and swept >= 5.0:
			_emit(Failure.new(
				&"stalled",
				"中途停住了：超过 %.0fms 没转动" % idle_ms,
				elapsed_ms,
			))
		_capture_measured(swept, elapsed_ms, Geometry.norm_deg(frame.rs_angle - base))
		_abort()
		return null

	if elapsed_ms > max_ms:
		if _claimed:
			_emit(Failure.new(
				&"too_slow",
				"太慢了：用了 %.0fms（上限 %.0fms）" % [elapsed_ms, max_ms],
				elapsed_ms,
			))
		_capture_measured(swept, elapsed_ms, Geometry.norm_deg(frame.rs_angle - base))
		_abort()
		return null

	end_rel = Geometry.norm_deg(frame.rs_angle - base)
	var end_ok := _end_ok(end_rel)
	var in_range := min_angle <= swept and swept <= max_angle

	# 动作还没到最短时长，就已经转到位了 -> 太快，直接作废。
	# 不能只 return null 继续等：否则用户快速转完再停住，会在 min_duration 到点时误触发。
	if elapsed_ms < min_ms:
		if in_range and end_ok:
			if _claimed:
				_emit(Failure.new(
					&"too_fast",
					"太快了：%.0fms 就转到位了（至少 %.0fms）" % [elapsed_ms, min_ms],
					elapsed_ms,
				))
			_capture_measured(swept, elapsed_ms, end_rel)
			_abort()
		return null

	if not in_range or not end_ok:
		_capture_measured(swept, elapsed_ms, end_rel)
		return null

	active = false
	armed = false
	_turn_sign = 0
	_capture_measured(swept, elapsed_ms, end_rel)
	var summary := "旋转 %.0f°（相对 %.0f°→%.0f°）" % [absf(acc), start_rel, end_rel]
	return Hit.new(elapsed_ms, _describe(), summary)


func _describe() -> String:
	var turn := "顺时针" if acc > 0.0 else "逆时针"
	var text := "右摇杆%s %.0f° (起始 %.0f° → 结束 %.0f°) 采样 %d 点" % [
		turn, absf(acc), start_angle, last_angle, samples,
	]
	if _have_start_target:
		text += " 起点%.0f°(要求%.0f°±%.0f°)" % [start_rel, start_target, start_tolerance]
	return text


## 把轨迹粗采样成一行文本，便于回看搓招路径（detectors.py:426-428）。
func path_detail() -> String:
	var parts := PackedStringArray()
	for entry in _path.slice(0, 24):
		parts.append("%.0f°@%.0fms" % [float(entry[1]), float(entry[0])])
	return " ".join(parts)


## 暴露轨迹给 Phase 7 的高亮面板；返回副本，调用方无法改内部状态。
func last_path() -> Array:
	return _path.duplicate(true)


## 最近一次尝试的实测参数：Phase 5 只负责构造，JUDGE-05 的展示在后续计划。
## 数值全部来自 `_capture_measured()` 记下的局部量，与 `message` / `summary`
## 里那个数字同源 —— 不在这里二次计算。
func measured() -> Dictionary:
	var target: Dictionary = {
		"end_deg": end_targets.duplicate(),
		"end_tolerance_deg": end_tolerance,
	}
	if _have_start_target:
		target["start_deg"] = start_target
		target["start_tolerance_deg"] = start_tolerance
	return {
		"kind": "arc",
		"start_angle_deg": start_angle,
		"start_rel_deg": start_rel,
		"end_angle_deg": _measured_end_angle,
		"end_rel_deg": _measured_end_rel,
		"swept_deg": _measured_swept_deg,
		"elapsed_ms": _measured_elapsed_ms,
		"samples": _measured_samples,
		"direction_sign": _measured_direction_sign,
		"target": target,
	}


func reset() -> void:
	active = false
	armed = true
	acc = 0.0
	_have_release_since = false
	_release_since = 0.0
	_last_motion = 0.0
	_turn_sign = 0


## 不能继承基类的 abandon()：基类会调 reset()，把「已被别人认领」变成
## 「可以立刻重试」，`wrong_end` / `hold_short` 会互相冒充（detectors.py:438-440）。
func abandon() -> void:
	_pending = null
	_abort()


func status() -> String:
	# 只推杆不转圈时 acc 是 0，别显示「旋转中 0°」误导人。
	if not active or absf(acc) < 5.0:
		return "待机"
	return "旋转中 %.0f° (目标 %.0f~%.0f°)" % [absf(acc), min_angle, max_angle]
