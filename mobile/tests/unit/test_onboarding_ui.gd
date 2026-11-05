extends RefCounted

## 引导屏与诊断覆盖层的**无头格式套件**。
##
## 它证明的是：屏幕上的每一句新文案都来自一个可以无头调用的纯函数，而不是散落在
## `_process` 里、只能在真机上才看得到的字符串拼接。
##
## 为什么这件事必须单独成一套：04-07 的 D0 失败原文是「我都看不明白」。如果文案只
## 存在于渲染路径里，那么「说得清不清楚」和「判定对不对」就永远只能靠真机肉眼判断；
## 把文案抽成静态函数之后，方向词、次数、增量语义、诊断页的每个字段都可以逐条断言。
##
## 覆盖三组契约：
##   1. 探针屏的人话（`live_readout` / `plain_rejection` / `cross_check_plain` / `stop_message`）；
##   2. 诊断覆盖层的两页格式（`format_profiles` / `format_events`）与行宽上限；
##   3. 覆盖层不产判定的机械证明（`set_layout_confirmed(false)` → 零 Outcome）。

const ONBOARDING := preload("res://src/ui/onboarding_screen.gd")
const DIAGNOSTICS := preload("res://src/ui/diagnostics_overlay.gd")

## 8 根轴的空读数：与 onboarding_screen 的 AXIS_COUNT 同宽。
const AXIS_COUNT := 8
## 事件页最多允许的行数：720 px 高、22 px 行框约 27 行，留一行余量。
const MAX_PAGES_LINES := 26


func run(r) -> void:
	_check_live_readout(r)
	_check_plain_rejection(r)
	_check_cross_check_plain(r)
	_check_stop_message(r)
	_check_diagnostics_profiles(r)
	_check_diagnostics_events(r)
	_check_diagnostics_line_width(r)
	_check_overlay_produces_no_outcome(r)
	r.complete()


## 1. 实时读数取「位移最大的那根轴」，并且只说轴序号与正负，不猜 X/Y。
func _check_live_readout(r) -> void:
	var raw := _axes(0.0)
	var idle := ONBOARDING.live_readout(raw, PackedFloat32Array())
	r.check(idle.contains("没有推动"),
		"全零读数必须说「没有推动」（实际 %s）" % idle)

	var negative := _axes(0.0)
	negative[2] = -0.98
	var text := ONBOARDING.live_readout(negative, _axes(0.0))
	r.check(text.contains("轴 2"), "负向读数必须点名轴 2（实际 %s）" % text)
	r.check(text.contains("负方向"), "负向读数必须说「负方向」（实际 %s）" % text)
	r.check(text.contains("0.98"), "负向读数必须带出有符号位移 0.98（实际 %s）" % text)

	var positive := _axes(0.0)
	positive[3] = 0.90
	var up_text := ONBOARDING.live_readout(positive, _axes(0.0))
	r.check(up_text.contains("轴 3"), "正向读数必须点名轴 3（实际 %s）" % up_text)
	r.check(up_text.contains("正方向"), "正向读数必须说「正方向」（实际 %s）" % up_text)

	# 两轴同时偏：主轴必须是 |delta| 更大的那根（0.8 > 0.3）。
	var two := _axes(0.0)
	two[2] = 0.3
	two[3] = -0.8
	var two_text := ONBOARDING.live_readout(two, _axes(0.0))
	r.check(two_text.contains("轴 3"),
		"两轴同时动时必须取变化更大的轴 3（实际 %s）" % two_text)
	r.check(not two_text.contains("轴 2"),
		"两轴同时动时不得把较小的轴 2 当主轴（实际 %s）" % two_text)

	# 静止基线参与位移计算：raw 与 rest 相同 → 没有推动。
	var baseline := _axes(0.0)
	baseline[4] = -0.996
	var still := ONBOARDING.live_readout(baseline, baseline)
	r.check(still.contains("没有推动"),
		"raw 与 rest 相同时必须说「没有推动」（实际 %s）" % still)


## 2. 纯语言拒绝：四个码都给出动作句，技术词不许当唯一内容。
func _check_plain_rejection(r) -> void:
	var codes: Array[StringName] = [
		&"ambiguous_axes", &"not_enough_travel", &"not_enough_samples", &"displacement_too_small",
	]
	for code in codes:
		var retry := ONBOARDING.plain_rejection(code, &"right", 1)
		r.check(not retry.is_empty(), "码 %s 必须给出非空文案" % code)
		r.check(retry.contains("右"), "码 %s 的动作句必须点名方向「右」（实际 %s）" % [code, retry])
		r.check(retry.contains("1/2"), "第 1 次机会必须写「1/2」（实际 %s）" % retry)
		r.check(not retry.contains("margin"),
			"动作句里不得出现 margin 这类技术词（实际 %s）" % retry)
		var hard := ONBOARDING.plain_rejection(code, &"right", 0)
		r.check(hard.contains("已经试了 2 次"),
			"第 3 次必须说「已经试了 2 次」（实际 %s）" % hard)


## 3. 交叉校验文案：先说「你刚才推的方向不像「X」」，再解释轴的关系。
func _check_cross_check_plain(r) -> void:
	var up_right := ONBOARDING.cross_check_plain(&"same_axis_up_right", &"right")
	r.check(up_right.contains("你刚才推的方向不像「右」"),
		"上/右同轴必须先否定方向「右」（实际 %s）" % up_right)
	var vertical := ONBOARDING.cross_check_plain(&"vertical_not_opposed", &"down")
	r.check(vertical.contains("你刚才推的方向不像「下」"),
		"上下不反号必须先否定方向「下」（实际 %s）" % vertical)
	var horizontal := ONBOARDING.cross_check_plain(&"horizontal_not_opposed", &"left")
	r.check(horizontal.contains("你刚才推的方向不像「左」"),
		"左右不反号必须先否定方向「左」（实际 %s）" % horizontal)


## 4. 停止语报的是**增量**，且保留 D0 判失败的标记。
func _check_stop_message(r) -> void:
	var zero := ONBOARDING.stop_message(0, 1931)
	r.check(zero.contains("本步开始后新增 0 个摇杆事件"),
		"增量 0 必须写成「本步开始后新增 0 个摇杆事件」（实际 %s）" % zero)
	r.check(zero.contains("累计 1931"),
		"停止语必须同时给出累计值 1931（实际 %s）" % zero)
	r.check(zero.contains("D0 判失败"),
		"停止语必须保留 D0 判失败的标记（实际 %s）" % zero)
	var some := ONBOARDING.stop_message(5, 2000)
	r.check(some.contains("新增 5"),
		"增量 5 必须写在第一句里（实际 %s）" % some)


## 5. 档案页：每个字段都有落点；空档 / 坏档 / 空表都不许抛错或白屏。
func _check_diagnostics_profiles(r) -> void:
	var good := DIAGNOSTICS.format_profiles(_profile_json())
	r.check(good.contains("档案页（第 1/2 页）"),
		"合法档案必须显示档案页抬头（实际 %s）" % good)
	for fragment in [
		"rs_x=(2,-1)", "rs_y=(3,1)", "center=", "scale=",
		"profile_id=primary", "layout=xbox", "probed=", "q up=",
		"layout_confirmed", "button_index_ok", "probed_at_iso",
	]:
		# `layout_confirmed` / `button_index_ok` / `probed_at_iso` 三个字段名在屏上
		# 用的是短名（confirmed / btn_idx_ok / probed），这里断言的是「有对应输出」，
		# 所以用各自的短名再查一遍。
		var needle: String = str(fragment)
		if needle == "layout_confirmed":
			needle = "confirmed=true"
		elif needle == "button_index_ok":
			needle = "btn_idx_ok=true"
		elif needle == "probed_at_iso":
			needle = "probed="
		r.check(good.contains(needle),
			"档案页必须包含 %s（实际输出 %s）" % [needle, good])

	var empty := DIAGNOSTICS.format_profiles("")
	r.check(empty.contains("尚未生成"), "文件不存在时必须说「尚未生成」（实际 %s）" % empty)

	var corrupt := DIAGNOSTICS.format_profiles("{\"schema_version\": 1, \"profiles\": {")
	r.check(corrupt.contains("解析失败"), "坏 JSON 必须说「解析失败」（实际 %s）" % corrupt)
	r.check(not corrupt.is_empty(), "坏 JSON 也必须返回可显示的文本，不得抛错")

	var empty_map := DIAGNOSTICS.format_profiles("{\"schema_version\": 1, \"profiles\": {}}")
	r.check(empty_map.contains("没有条目"), "空 profiles 必须说「没有条目」（实际 %s）" % empty_map)


## 6. 事件页：计数器、分位数、线程号、每轴 min/max、扳机静止值全部来自缓冲。
func _check_diagnostics_events(r) -> void:
	var buffer := PadStateBuffer.new(0)
	buffer.apply_event({"device": 0, "t_ms": 0.0, "kind": "motion", "axis": 2, "value": -0.5})
	buffer.apply_event({"device": 0, "t_ms": 8.0, "kind": "motion", "axis": 3, "value": 0.5})
	buffer.apply_event({"device": 0, "t_ms": 16.0, "kind": "motion", "axis": 2, "value": -0.6})
	buffer.apply_event({"device": 0, "t_ms": 24.0, "kind": "button", "index": 0, "pressed": true})

	var text := DIAGNOSTICS.format_events(buffer, 1, 1, {})
	for fragment in [
		"事件页（第 2/2 页）", "ev_m=3", "ev_b=1", "poll=0", "dt95=",
		"in_tid=1", "proc_tid=1", "轴 2", "min=", "max=", "扳机：未记录",
	]:
		r.check(text.contains(fragment), "事件页必须包含 %s（实际 %s）" % [fragment, text])

	var with_trigger := DIAGNOSTICS.format_events(
		buffer, 1, 1, {"lt_index": 4, "lt_rest": -0.996, "rt_index": 5, "rt_rest": -1.0})
	r.check(with_trigger.contains("LT 轴 4"),
		"有扳机条目时必须点名 LT 的轴号（实际 %s）" % with_trigger)
	r.check(with_trigger.contains("rest=-0.996"),
		"扳机静止值必须逐字来自档案 -0.996（实际 %s）" % with_trigger)

	var null_buffer := DIAGNOSTICS.format_events(null, 0, 0, {})
	r.check(not null_buffer.is_empty(), "buffer 为 null 时必须返回文本而不是抛错")


## 7. 行宽与行数：`autowrap_mode = 0` 下超宽的行会被直接裁掉，截图证据就少一半。
func _check_diagnostics_line_width(r) -> void:
	var buffer := PadStateBuffer.new(0)
	buffer.apply_event({"device": 0, "t_ms": 0.0, "kind": "motion", "axis": 2, "value": -0.5})
	buffer.apply_event({"device": 0, "t_ms": 8.0, "kind": "motion", "axis": 3, "value": 0.5})
	var pages := {
		"profiles": DIAGNOSTICS.format_profiles(_profile_json()),
		"events": DIAGNOSTICS.format_events(
			buffer, 1, 1, {"lt_index": 4, "lt_rest": -0.996, "rt_index": 5, "rt_rest": -1.0}),
	}
	for name in pages:
		var lines: PackedStringArray = str(pages[name]).split("\n")
		r.check(lines.size() <= MAX_PAGES_LINES,
			"%s 页行数必须 ≤ %d（实际 %d）" % [name, MAX_PAGES_LINES, lines.size()])
		for line in lines:
			r.check(line.length() <= DIAGNOSTICS.MAX_LINE_CHARS,
				"%s 页有一行超宽：%d > %d（%s）" % [
					name, line.length(), DIAGNOSTICS.MAX_LINE_CHARS, line])


## 8. 覆盖层打开时「静默放弃手势」的机械证明：不留下任何一条 hold_short。
func _check_overlay_produces_no_outcome(r) -> void:
	var runtime := TapRuntime.new(_skill(), 450, 150, true)
	runtime.tick(_frame(0.04, ["RB"]))
	runtime.tick(_frame(0.10, ["RB", "X"]))
	r.check(runtime.status() != "待机", "前置：第二帧必须让检测器起手（实际 %s）" % runtime.status())

	# 这一句就是覆盖层打开时做的事。
	runtime.set_layout_confirmed(false)
	runtime.tick(_frame(0.20, []))
	var outcomes := runtime.pop_outcomes()
	r.check(outcomes.is_empty(),
		"覆盖层打开后不得留下任何 Outcome（实际 %d 条）" % outcomes.size())

	runtime.set_layout_confirmed(true)
	r.check(runtime.layout_confirmed, "关闭覆盖层后必须恢复布局确认")


## 一条合成的绿色搓射：参数与真实配置一致，只为这一段服务。
func _skill() -> Skill:
	var skill := Skill.new()
	skill.name = "合成的绿色搓射"
	skill.kind = Skill.KIND_TAPS
	var required: Array[String] = ["RB"]
	skill.required_buttons = required
	skill.params = {
		"button": "X",
		"min_interval_ms": 400,
		"max_interval_ms": 600,
		"timeout_grace_ms": 150,
		"release_hold_ms": 120,
	}
	skill.cooldown_ms = 450
	return skill


func _frame(now: float, buttons: Array) -> Frame:
	var frame := Frame.new()
	frame.now = now
	for name in buttons:
		frame.buttons[str(name)] = true
	return frame


static func _axes(value: float) -> PackedFloat32Array:
	var raw := PackedFloat32Array()
	raw.resize(AXIS_COUNT)
	for axis in AXIS_COUNT:
		raw[axis] = value
	return raw


## 一份结构完整的 `controllers.json` 原文：字段照 `DeviceProfile.to_dict()`。
static func _profile_json() -> String:
	return JSON.stringify({
		"schema_version": 1,
		"profiles": {
			"guid:abc": {
				"schema_version": 1,
				"key": "guid:abc",
				"profile_id": "primary",
				"device_name": "Xbox Series X Controller",
				"device_guid": "abc",
				"axes": {
					"rs_x": {"index": 2, "sign": -1},
					"rs_y": {"index": 3, "sign": 1},
					"ls_x": {"index": -1, "sign": 1},
					"ls_y": {"index": -1, "sign": 1},
					"lt": {"index": 4, "rest": -0.996},
					"rt": {"index": 5, "rest": -1.0},
				},
				"calibration": {
					"center_x": 0.01,
					"center_y": -0.02,
					"scale_x": 0.98,
					"scale_y": 0.97,
				},
				"quality": {
					"up": {"samples": 30, "margin": 0.7, "separation": 6.0},
					"right": {"samples": 28, "margin": 0.68, "separation": 5.4},
				},
				"layout": "xbox",
				"layout_confirmed": true,
				"button_index_ok": true,
				"probed_at_iso": "2026-11-05 20:00:00",
			},
		},
	}, "\t", true)
