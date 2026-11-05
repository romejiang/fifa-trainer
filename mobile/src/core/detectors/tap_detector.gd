class_name TapDetector
extends Detector

## 按键双击类：按住修饰键，在时间窗口内按两下同一个键。
##
## 逐行移植 desktop/padskills/detectors.py:858-1034。典型用法是绿色搓射：按住 RB
## （或 RT），第一下 X 之后 400~600ms 再按第二下 X，整个过程修饰键不能松开。
## 按钮判定和右摇杆完全无关，所以 `on_idle()` 不能清进度 —— 引擎在右摇杆静止时
## 会定期调用它，而做这个动作时右摇杆通常一直回中。
##
## 时间口径：`Frame.now` 是秒；`min_ms` / `max_ms` / `grace_ms` / `release_hold_ms`
## 是毫秒。窗口两端**都包含**（`min <= interval <= max`），超时是**严格大于**
## （`interval > max + grace`）。
##
## 状态成对表示，不用 `-1.0` 当哨兵：`_have_t0` + `_t0`、`_have_release_since` +
## `_release_since`。`-1.0` 是合法时间戳，用哨兵会在某些时间轴上变成「真的已建立」。

## 要连按的键（规范名）。
var button: String = "X"
## 全程必须按住的修饰键；空数组表示不要求。
var required: Array[String] = []
## 窗口两端，毫秒，都包含。
var min_ms: float = 400.0
var max_ms: float = 600.0
## 一直没有第二下时的宽限。
var grace_ms: float = 150.0
## 成功/失败后必须真正松开多久才允许下一次。
var release_hold_ms: float = 120.0

var _now: float = 0.0
var _have_t0: bool = false
var _t0: float = 0.0
## false = 等按键真正松开再允许重试。
var _armed: bool = true
var _prev_pressed: bool = false
var _have_prev: bool = false
var _have_release_since: bool = false
var _release_since: float = 0.0


## 构造参数来自已校验的 Skill：button / required / 窗口 / 宽限 / 松开时长。
## 修饰键与窗口的合法性由 ConfigValidator 保证，这里不重复抛错；但
## `timeout_grace_ms` **没有**被校验器检查，所以仍要 `maxf(0.0, ...)`。
func _init(skill: Skill) -> void:
	var params: Dictionary = skill.params
	button = Buttons.canonical(str(params.get("button", "X")))
	required = skill.required_buttons.duplicate()
	min_ms = float(params.get("min_interval_ms", 400.0))
	max_ms = float(params.get("max_interval_ms", 600.0))
	grace_ms = maxf(0.0, float(params.get("timeout_grace_ms", 150.0)))
	release_hold_ms = maxf(0.0, float(params.get("release_hold_ms", 120.0)))


## 切换要按住的修饰键（绿色搓射的 RB / RT）。
##
## 配置里 `required_button` 是默认值，用户在界面上切换后立即生效；正在等待第二下
## 的进度会被作废，避免用旧键的起手去配新键的第二次按下。`_armed` 必须按
## `_prev_pressed` 重算，否则「按住修饰键时切换」会让重新武装的时机与桌面版不一致。
func set_modifier(button_name: String) -> void:
	var normalized := Buttons.canonical(button_name)
	required = [normalized]
	_pending = null
	_have_t0 = false
	_t0 = 0.0
	_have_release_since = false
	_release_since = 0.0
	_armed = not _prev_pressed


func _required_label() -> String:
	if required.is_empty():
		return "修饰键"
	return "/".join(PackedStringArray(required))


func _clear(armed: bool) -> void:
	_have_t0 = false
	_t0 = 0.0
	_have_release_since = false
	_release_since = 0.0
	_armed = armed


## 按住别的修饰键 / 没按 RB 时引擎只调 observe + reset。这里仍然要记录按键状态，
## 否则重新按住 RB 的那一帧会把「一直按着 X」误判成一次新的按下。
func observe(frame: Frame) -> void:
	_now = frame.now
	_prev_pressed = frame.buttons.has(button)
	_have_prev = true


## 引擎在 required_button 松开时调用 reset()。如果正做到一半，说明 RB 中途松了，
## 给一次明确提示；已经结束的尝试不再重复报。
##
## elapsed 用的是上一帧的 `_now`（略微过期），不是当前时刻 —— core 不读时钟，
## 这里必须照抄参考实现的时间口径。
func reset() -> void:
	if _have_t0:
		var elapsed_ms: float = maxf(0.0, (_now - _t0) * 1000.0)
		_emit(Failure.new(
			&"hold_short",
			"保持不够：中途松开了 %s（两下 %s 之间要一直按住）" % [_required_label(), button],
			elapsed_ms,
		))
	_have_t0 = false
	_t0 = 0.0
	_have_release_since = false
	_release_since = 0.0
	# 只有按键已经松开，才允许下一次起手。
	_armed = not _prev_pressed


## 右摇杆静止与按键动作无关，不能在这里作废进度。
func on_idle() -> void:
	pass


## 这段轨迹属于别的动作（或按住了别的修饰键）：静默丢弃，不报错。
##
## 不调用 reset()：reset 会产 hold_short，而这里必须一声不吭。最后一行同样要按
## `_prev_pressed` 重算 `_armed` —— 参考实现 detectors.py:946 就是这么写的。
func abandon() -> void:
	_pending = null
	_have_t0 = false
	_t0 = 0.0
	_have_release_since = false
	_release_since = 0.0
	_armed = not _prev_pressed


## 判定顺序就是语义，九步不能重排（detectors.py:949-1026）：
## 首帧守卫 → rising → 修饰键防御分支 → 未武装时松开计时 → 只记起手 →
## interval → rising 三分支 → 超时分支。
func update(frame: Frame) -> Hit:
	var now := frame.now
	_now = now
	var pressed := frame.buttons.has(button)
	if not _have_prev:
		_prev_pressed = pressed
		_have_prev = true
		return null

	var rising := pressed and not _prev_pressed
	var mods_ok := true
	for required_button in required:
		if not frame.buttons.has(required_button):
			mods_ok = false
			break
	if not mods_ok:
		# 正常情况下引擎不会在这里调用 update()；防御性处理：不产失败、不清 _t0。
		_prev_pressed = pressed
		return null

	# 成功/失败之后，必须真正松开按键并保持一小段时间，才允许下一次。
	if not _armed:
		if not pressed:
			if not _have_release_since:
				_have_release_since = true
				_release_since = now
			elif (now - _release_since) * 1000.0 >= release_hold_ms:
				_armed = true
				_have_release_since = false
				_release_since = 0.0
		else:
			_have_release_since = false
			_release_since = 0.0
		_prev_pressed = pressed
		return null

	if not _have_t0:
		if rising:
			_have_t0 = true
			_t0 = now
			_have_release_since = false
			_release_since = 0.0
		_prev_pressed = pressed
		return null

	var interval_ms := (now - _t0) * 1000.0

	if rising:
		# 第二下：只看两下按下的时间间隔。
		if min_ms <= interval_ms and interval_ms <= max_ms:
			var summary := "两下 %s 间隔 %.0fms" % [button, interval_ms]
			var detail := "%s（%s 全程按住）" % [summary, _required_label()]
			_clear(false)
			_prev_pressed = pressed
			return Hit.new(interval_ms, detail, summary)

		if interval_ms < min_ms:
			_emit(Failure.new(
				&"too_fast",
				"太快了：两下 %s 只隔了 %.0fms（需要 %.0f~%.0fms）"
					% [button, interval_ms, min_ms, max_ms],
				interval_ms,
			))
		else:
			_emit(Failure.new(
				&"too_slow",
				"太慢了：两下 %s 隔了 %.0fms（需要 %.0f~%.0fms）"
					% [button, interval_ms, min_ms, max_ms],
				interval_ms,
			))
		_clear(false)
		_prev_pressed = pressed
		return null

	# 一直没有第二下：超过上限再给一点宽限就报「太慢」，不能一直挂着。
	if interval_ms > max_ms + grace_ms:
		_emit(Failure.new(
			&"too_slow",
			"太慢了：等了 %.0fms 还没有第二下 %s（需要在 %.0f~%.0fms 内）"
				% [interval_ms, button, min_ms, max_ms],
			interval_ms,
		))
		_clear(false)

	_prev_pressed = pressed
	return null


func status() -> String:
	if not _have_t0:
		return "待机"
	var elapsed_ms: float = maxf(0.0, (_now - _t0) * 1000.0)
	return ("已按第一下 %s，等第二下 %.0fms（目标 %.0f~%.0f）"
		% [button, elapsed_ms, min_ms, max_ms])
