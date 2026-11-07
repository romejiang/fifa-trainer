extends RefCounted

## OnboardingFlow 的无头全流程证明：从「没有设备」走到「可以进入练习」，
## 全程不需要窗口、不需要手柄、不需要场景树。
##
## 每个用例都直接构造 `OnboardingFlow.new()` 推进状态机；采样窗口用合成
## `PackedFloat32Array` 代替。覆盖的不只是 happy path，还有四条「必须拒绝」的
## 边界：没采静止基线就探针、探针步骤被拒、交叉校验失配、复用门失配，以及
## 「未确认布局 / 空布局不得进练习」这条成功标准 4 的机械保证。

func run(r) -> void:
	_check_no_device_first(r)
	_check_any_button_wakes(r)
	_check_probe_requires_rest(r)
	_check_probe_happy_path(r)
	_check_probe_step_rejection(r)
	_check_probe_cross_validation(r)
	_check_soft_retry_resets_on_success(r)
	_check_soft_retry_code_filter(r)
	_check_reuse_gate_accepts(r)
	_check_reuse_gate_rejects(r)
	_check_calibration_gate(r)
	_check_layout_never_preconfirmed(r)
	_check_empty_layout_requires_choice(r)
	_check_wrong_button_index(r)
	_check_correct_button_index(r)
	_check_device_lost_resets(r)
	_check_device_swap_clears_layout(r)
	_check_build_profile(r)
	_check_suggest_layout_wired(r)
	r.complete()


## 初始状态是 no_device；空列表不会把状态推到别处（「没有设备」不是错误）。
func _check_no_device_first(r) -> void:
	var flow := OnboardingFlow.new()
	r.check(flow.state == OnboardingFlow.STATE_NO_DEVICE,
		"新流程必须从 no_device 开始（实际 %s）" % flow.state)
	flow.on_device_list_changed([], "", "")
	r.check(flow.state == OnboardingFlow.STATE_NO_DEVICE,
		"空设备列表必须留在 no_device（实际 %s）" % flow.state)


## 设备出现 → device_ready；按任意键 → probe_intro；再按不再推进。
func _check_any_button_wakes(r) -> void:
	var flow := OnboardingFlow.new()
	flow.on_device_list_changed([3], "Xbox Series X Controller", "guid-a")
	r.check(flow.state == OnboardingFlow.STATE_DEVICE_READY,
		"设备出现必须进入 device_ready（实际 %s）" % flow.state)
	r.check(flow.device_name == "Xbox Series X Controller",
		"device_ready 必须带上传入的设备名（实际 %s）" % flow.device_name)

	r.check(flow.on_any_button(), "device_ready 里按任意键必须返回 true")
	r.check(flow.state == OnboardingFlow.STATE_PROBE_INTRO,
		"按任意键必须进入 probe_intro（实际 %s）" % flow.state)
	r.check(not flow.on_any_button(), "probe_intro 里再按任意键必须返回 false")
	r.check(flow.state == OnboardingFlow.STATE_PROBE_INTRO,
		"probe_intro 里再按任意键不得改变状态（实际 %s）" % flow.state)

	flow.begin_probe()
	r.check(flow.state == OnboardingFlow.STATE_PROBE_REST,
		"begin_probe 必须先到 probe_rest，而不是 probe_up（实际 %s）" % flow.state)


## 没有静止基线时，直接提交探针步骤必须无效。
func _check_probe_requires_rest(r) -> void:
	var flow := _fresh()
	flow.on_any_button()
	flow.begin_probe()
	flow.submit_probe_step(_step(3, -1))
	r.check(flow.state == OnboardingFlow.STATE_PROBE_REST,
		"没有 rest 时提交探针步骤必须留在 probe_rest（实际 %s）" % flow.state)
	r.check(flow.rest_baseline().size() == 0,
		"没有 rest 时 rest_baseline() 必须为空（实际 %d）" % flow.rest_baseline().size())

	flow.submit_rest_baseline(_rest_samples())
	r.check(flow.state == OnboardingFlow.STATE_PROBE_UP,
		"采完 rest 必须进入 probe_up（实际 %s）" % flow.state)
	r.check(flow.rest_baseline().size() == 8,
		"rest_baseline() 必须覆盖 8 根轴（实际 %d）" % flow.rest_baseline().size())


## 四步都成功 → calibrate_center；四步质量全部记录。
func _check_probe_happy_path(r) -> void:
	var flow := _to_probe(_fresh())
	_submit_four_steps(flow)
	r.check(flow.state == OnboardingFlow.STATE_CALIBRATE_CENTER,
		"四步探针成功必须进入 calibrate_center（实际 %s）" % flow.state)
	for key in ["up", "right", "down", "left"]:
		r.check(flow.quality.has(key), "quality 必须记录 %s 步" % key)
		if flow.quality.has(key):
			var entry: Dictionary = flow.quality[key]
			r.check(entry.has("samples") and entry.has("margin") and entry.has("separation"),
				"quality[%s] 必须带 samples / margin / separation" % key)


## 第二步被拒：前两次留在本步（软重试），第 3 次才停在 probe_failed；
## 按 B 重来只回退到该步、计数归零，第一步结果仍在。
func _check_probe_step_rejection(r) -> void:
	var flow := _to_probe(_fresh())
	flow.submit_probe_step(_step(3, -1))

	flow.submit_probe_step(_reject(&"ambiguous_axes", "两轴同时动了：请只推一个方向"))
	r.check(flow.state == OnboardingFlow.STATE_PROBE_RIGHT,
		"第 1 次 ambiguous_axes 必须留在本步（期望 probe_right，实际 %s）" % flow.state)
	r.check(flow.soft_retry_count == 1,
		"第 1 次软重试后计数必须是 1（实际 %d）" % flow.soft_retry_count)
	r.check(flow.probe_failure_code == &"",
		"软重试期间 probe_failure_code 必须保持空（实际 %s）" % flow.probe_failure_code)

	flow.submit_probe_step(_reject(&"ambiguous_axes", "两轴同时动了：请只推一个方向"))
	r.check(flow.state == OnboardingFlow.STATE_PROBE_RIGHT,
		"第 2 次 ambiguous_axes 仍必须留在本步（期望 probe_right，实际 %s）" % flow.state)
	r.check(flow.soft_retry_count == 2,
		"第 2 次软重试后计数必须是 2（实际 %d）" % flow.soft_retry_count)

	flow.submit_probe_step(_reject(&"ambiguous_axes", "两轴同时动了：请只推一个方向"))
	r.check(flow.state == OnboardingFlow.STATE_PROBE_FAILED,
		"第 3 次 ambiguous_axes 必须判失败（期望 probe_failed，实际 %s）" % flow.state)
	r.check(flow.probe_failure_code == &"ambiguous_axes",
		"硬失败必须保留具体 code（实际 %s）" % flow.probe_failure_code)
	r.check(flow.retry_state == OnboardingFlow.STATE_PROBE_RIGHT,
		"重试必须指向出错的那一步（实际 %s）" % flow.retry_state)

	flow.retry_probe_step()
	r.check(flow.state == OnboardingFlow.STATE_PROBE_RIGHT,
		"重试必须回到 probe_right（实际 %s）" % flow.state)
	r.check(flow.soft_retry_count == 0,
		"按 B 重来必须把软重试计数归零（实际 %d）" % flow.soft_retry_count)
	# 只补 right / down / left 就能到 calibrate_center，说明 up 的结果没有被清掉。
	flow.submit_probe_step(_step(2, -1))
	flow.submit_probe_step(_step(3, 1))
	flow.submit_probe_step(_step(2, 1))
	r.check(flow.state == OnboardingFlow.STATE_CALIBRATE_CENTER,
		"重试后补完剩余步骤必须能继续（实际 %s）" % flow.state)


## 四步都「成功」但上/右同轴：前两次回到出错的 probe_right，第 3 次才判失败。
func _check_probe_cross_validation(r) -> void:
	var flow := _to_probe(_fresh())
	_submit_four_steps_ambiguous(flow)
	r.check(flow.state == OnboardingFlow.STATE_PROBE_RIGHT,
		"第 1 次上/右同轴必须回到 probe_right（期望 probe_right，实际 %s）" % flow.state)
	r.check(flow.soft_retry_count == 1,
		"第 1 次交叉失败后计数必须是 1（实际 %d）" % flow.soft_retry_count)
	r.check(flow.last_reject_code == &"same_axis_up_right",
		"交叉失败必须把码写进 last_reject_code（实际 %s）" % flow.last_reject_code)

	# 状态已经回到 probe_right，重测同一个键就会覆盖它并重新触发交叉校验。
	flow.submit_probe_step(_step(3, -1))
	r.check(flow.state == OnboardingFlow.STATE_PROBE_RIGHT,
		"第 2 次上/右同轴仍必须回到 probe_right（期望 probe_right，实际 %s）" % flow.state)
	r.check(flow.soft_retry_count == 2,
		"第 2 次交叉失败后计数必须是 2（实际 %d）" % flow.soft_retry_count)

	flow.submit_probe_step(_step(3, -1))
	r.check(flow.state == OnboardingFlow.STATE_PROBE_FAILED,
		"第 3 次上/右同轴必须判失败（期望 probe_failed，实际 %s）" % flow.state)
	r.check(flow.probe_failure_code == &"same_axis_up_right",
		"硬失败必须给出 same_axis_up_right（实际 %s）" % flow.probe_failure_code)
	r.check(flow.retry_state == OnboardingFlow.STATE_PROBE_RIGHT,
		"same_axis_up_right 的重试必须指向 probe_right（实际 %s）" % flow.retry_state)


## 软重试之后推对了：计数与拒绝码立刻归零，状态正常推进。
func _check_soft_retry_resets_on_success(r) -> void:
	var flow := _to_probe(_fresh())
	flow.submit_probe_step(_step(3, -1))
	flow.submit_probe_step(_reject(&"ambiguous_axes", "两轴同时动了：请只推一个方向"))
	r.check(flow.soft_retry_count == 1,
		"前置：一次软重试之后计数必须是 1（实际 %d）" % flow.soft_retry_count)

	flow.submit_probe_step(_step(2, -1))
	r.check(flow.soft_retry_count == 0,
		"推对之后软重试计数必须归零（实际 %d）" % flow.soft_retry_count)
	r.check(flow.last_reject_code == &"",
		"推对之后 last_reject_code 必须清空（实际 %s）" % flow.last_reject_code)
	r.check(flow.state == OnboardingFlow.STATE_PROBE_DOWN,
		"推对之后必须推进到 probe_down（实际 %s）" % flow.state)


## 不在软重试表里的码（例如 displacement_too_small）必须立刻硬失败：
## 重推一次也没用的问题，不该给用户「再试两次」的错觉。
func _check_soft_retry_code_filter(r) -> void:
	var flow := _to_probe(_fresh())
	flow.submit_probe_step(_reject(&"displacement_too_small", "位移不够：最大只有 0.100"))
	r.check(flow.state == OnboardingFlow.STATE_PROBE_FAILED,
		"非软重试码必须立刻判失败（期望 probe_failed，实际 %s）" % flow.state)
	r.check(flow.soft_retry_count == 0,
		"非软重试码不得消耗软重试次数（实际 %d）" % flow.soft_retry_count)
	r.check(flow.probe_failure_code == &"displacement_too_small",
		"硬失败必须保留具体 code（实际 %s）" % flow.probe_failure_code)


## 复用门命中：只验 right + down，整份采用档案；但布局仍需重新确认。
func _check_reuse_gate_accepts(r) -> void:
	var flow := _fresh()
	var profile := _profile()
	r.check(flow.offer_profile(profile), "完整档案必须被 offer_profile 接受")
	r.check(flow.state == OnboardingFlow.STATE_REUSE_REST,
		"offer_profile 命中必须进入 reuse_rest（实际 %s）" % flow.state)

	flow.submit_reuse_rest(_rest_samples())
	r.check(flow.state == OnboardingFlow.STATE_REUSE_CHECK,
		"复用静止基线采集后必须进入 reuse_check（实际 %s）" % flow.state)

	flow.submit_reuse_step(_step(2, -1))
	flow.submit_reuse_step(_step(3, -1))
	r.check(flow.state == OnboardingFlow.STATE_LAYOUT_CONFIRM,
		"两步复验一致必须进入 layout_confirm（实际 %s）" % flow.state)
	r.check(flow.mapping() != null, "复用成功后 mapping() 必须非 null")
	r.check(flow.mapping() == profile.axes, "复用必须整份采用档案里的轴映射")
	r.check(not flow.reuse_rejected, "复用成功时 reuse_rejected 必须为 false")
	r.check(flow.chosen_layout == &"",
		"复用不得带过来上次的布局选择（实际 %s）" % flow.chosen_layout)
	r.check(not flow.can_enter_practice(),
		"复用成功后仍需按键确认布局，can_enter_practice() 必须为 false")

	flow.confirm_layout(0, 0)
	r.check(flow.state == OnboardingFlow.STATE_PRACTICE,
		"布局确认后必须能进入练习（实际 %s）" % flow.state)
	r.check(flow.can_enter_practice(), "档案复用 + 按键确认后 can_enter_practice() 必须为 true")


## 复用门失配：整份丢弃、转完整探针；rest 已采过，重试直接回 probe_up。
func _check_reuse_gate_rejects(r) -> void:
	var flow := _fresh()
	var profile := _profile()
	flow.offer_profile(profile)
	flow.submit_reuse_rest(_rest_samples())
	flow.submit_reuse_step(_step(2, -1))
	# 档案记录的 rs_y_sign 是 -1；这次推下是 +1，四项里有一项不等。
	flow.submit_reuse_step(_step(3, 1))
	r.check(flow.state == OnboardingFlow.STATE_PROBE_FAILED,
		"复用失配必须停在 probe_failed（实际 %s）" % flow.state)
	r.check(flow.probe_failure_code == &"reuse_mismatch",
		"复用失配必须给出 reuse_mismatch（实际 %s）" % flow.probe_failure_code)
	r.check(flow.reuse_rejected, "复用失配必须留下 reuse_rejected = true")
	r.check(flow.mapping() == null, "复用失配后不得返回任何轴映射")

	flow.retry_probe_step()
	r.check(flow.state == OnboardingFlow.STATE_PROBE_UP,
		"复用失配后 rest 已存在，重试必须直接回 probe_up（实际 %s）" % flow.state)


## 校准两道门：被拒时留在本屏且原因非空；成功时必须清掉旧原因。
func _check_calibration_gate(r) -> void:
	var flow := _to_calibrate(_fresh())
	r.check(flow.state == OnboardingFlow.STATE_CALIBRATE_CENTER,
		"前置：必须已到 calibrate_center（实际 %s）" % flow.state)

	flow.submit_calibration_center(_reject(&"hand_on_stick", "采样期间摇杆在动：请双手离开摇杆"))
	r.check(flow.state == OnboardingFlow.STATE_CALIBRATE_CENTER,
		"中点校准被拒必须留在 calibrate_center（实际 %s）" % flow.state)
	r.check(not flow.probe_failure_message.is_empty(),
		"中点校准被拒必须给出可渲染的原因")

	flow.submit_calibration_center({"ok": true, "center": Vector2(0.01, -0.02)})
	r.check(flow.state == OnboardingFlow.STATE_CALIBRATE_RANGE,
		"中点校准成功必须进入 calibrate_range（实际 %s）" % flow.state)
	r.check(flow.probe_failure_message == "",
		"中点校准成功后必须清掉上一条失败文案（实际 %s）" % flow.probe_failure_message)

	flow.submit_calibration_range(_reject(&"range_short", "四方向最大位移只有 0.400：请推到最外圈"))
	r.check(flow.state == OnboardingFlow.STATE_CALIBRATE_RANGE,
		"满量程校准被拒必须留在 calibrate_range（实际 %s）" % flow.state)
	r.check(not flow.probe_failure_message.is_empty(),
		"满量程校准被拒必须给出可渲染的原因")

	flow.submit_calibration_range({"ok": true, "scale": Vector2(0.98, 0.97)})
	r.check(flow.state == OnboardingFlow.STATE_LAYOUT_CONFIRM,
		"满量程校准成功必须进入 layout_confirm（实际 %s）" % flow.state)
	r.check(flow.probe_failure_message == "",
		"满量程校准成功后必须清掉上一条失败文案（实际 %s）" % flow.probe_failure_message)


## 布局确认是「能不能进练习」的唯一授权：到这一屏时还没确认。
func _check_layout_never_preconfirmed(r) -> void:
	var flow := _to_layout(_fresh())
	r.check(flow.state == OnboardingFlow.STATE_LAYOUT_CONFIRM,
		"前置：必须已到 layout_confirm（实际 %s）" % flow.state)
	r.check(not flow.layout_confirmed, "到达 layout_confirm 时 layout_confirmed 必须仍为 false")
	r.check(not flow.can_enter_practice(), "未按键确认时 can_enter_practice() 必须为 false")


## 认不出设备名：两个选项并列且不预选；确认与「仍然使用」都不得放行。
func _check_empty_layout_requires_choice(r) -> void:
	var flow := _fresh("8BitDo Pro 2", "guid-8bitdo")
	r.check(flow.suggested_layout == &"",
		"8BitDo Pro 2 不得被建议成任何布局（实际 %s）" % flow.suggested_layout)
	_to_layout(flow)
	r.check(flow.effective_layout() == &"",
		"空建议下 effective_layout() 必须为空（实际 %s）" % flow.effective_layout())

	flow.confirm_layout(0, 0)
	r.check(flow.state == OnboardingFlow.STATE_LAYOUT_CONFIRM,
		"空布局时确认键不得放行（实际 %s）" % flow.state)
	r.check(not flow.layout_confirmed, "空布局时 layout_confirmed 必须为 false")
	r.check(not flow.layout_message.is_empty(), "空布局时必须给出「请选择布局」的提示")

	flow.accept_layout_anyway()
	r.check(flow.state == OnboardingFlow.STATE_LAYOUT_CONFIRM,
		"空布局时 accept_layout_anyway 也不得放行（实际 %s）" % flow.state)
	r.check(not flow.layout_confirmed, "空布局时 accept_layout_anyway 不得置 layout_confirmed")

	flow.choose_layout(&"playstation")
	r.check(flow.effective_layout() == &"playstation",
		"显式选择后 effective_layout() 必须是 playstation（实际 %s）" % flow.effective_layout())
	flow.confirm_layout(0, 0)
	r.check(flow.state == OnboardingFlow.STATE_PRACTICE,
		"选择布局后确认必须进入练习（实际 %s）" % flow.state)


## 按错键：button_index_ok 变 false 并留在布局页；B 是显式出口。
func _check_wrong_button_index(r) -> void:
	var flow := _to_layout(_fresh())
	flow.confirm_layout(1, 0)
	r.check(flow.state == OnboardingFlow.STATE_LAYOUT_CONFIRM,
		"按到索引 1 必须留在 layout_confirm（实际 %s）" % flow.state)
	r.check(not flow.button_index_ok, "按到索引 1 时 button_index_ok 必须为 false")
	r.check(not flow.layout_confirmed, "按错键时 layout_confirmed 必须为 false")
	r.check(not flow.can_enter_practice(), "按错键时 can_enter_practice() 必须为 false")

	flow.accept_layout_anyway()
	r.check(flow.state == OnboardingFlow.STATE_PRACTICE,
		"accept_layout_anyway 必须给出显式出口（实际 %s）" % flow.state)
	r.check(flow.can_enter_practice(), "显式接受布局后 can_enter_practice() 必须为 true")
	r.check(not flow.button_index_ok, "显式接受布局不得篡改实测的 button_index_ok")


## 按对键（A / × = 0）：进入练习，button_index_ok 为 true。
func _check_correct_button_index(r) -> void:
	var flow := _to_layout(_fresh())
	flow.confirm_layout(0, 0)
	r.check(flow.state == OnboardingFlow.STATE_PRACTICE,
		"按对索引必须进入练习（实际 %s）" % flow.state)
	r.check(flow.button_index_ok, "按对索引时 button_index_ok 必须为 true")


## 断连：一切作废；重连只回到 device_ready，必须重走探针。
func _check_device_lost_resets(r) -> void:
	var flow := _to_practice(_fresh())
	flow.on_device_lost()
	r.check(flow.state == OnboardingFlow.STATE_DEVICE_LOST,
		"断连必须进入 device_lost（实际 %s）" % flow.state)
	r.check(not flow.can_enter_practice(), "断连后 can_enter_practice() 必须为 false")
	r.check(flow.chosen_layout == &"", "断连必须清掉 chosen_layout")
	r.check(flow.suggested_layout == &"", "断连必须清掉 suggested_layout")
	r.check(flow.rest_baseline().size() == 0, "断连必须清掉静止基线")

	flow.on_device_list_changed([0], "Xbox Series X Controller", "guid")
	r.check(flow.state == OnboardingFlow.STATE_DEVICE_READY,
		"重连必须只回到 device_ready（实际 %s）" % flow.state)
	r.check(flow.state != OnboardingFlow.STATE_PRACTICE, "重连绝不直通 practice")
	r.check(flow.chosen_layout == &"", "重连后 chosen_layout 必须为空")
	r.check(flow.suggested_layout == &"xbox",
		"重连后建议布局必须按新设备名重算（实际 %s）" % flow.suggested_layout)


## 换手柄：A 的布局选择不得泄漏到 B。
func _check_device_swap_clears_layout(r) -> void:
	var flow := _fresh("DualSense Wireless Controller", "guid-a")
	flow.on_any_button()
	flow.begin_probe()
	flow.submit_rest_baseline(_rest_samples())
	_submit_four_steps_from_probe(flow)
	flow.submit_calibration_center({"ok": true, "center": Vector2(0.01, -0.02)})
	flow.submit_calibration_range({"ok": true, "scale": Vector2(0.98, 0.97)})
	flow.choose_layout(&"playstation")
	flow.confirm_layout(0, 0)
	r.check(flow.state == OnboardingFlow.STATE_PRACTICE,
		"前置：DualSense 流程必须能进练习（实际 %s）" % flow.state)

	flow.on_device_lost()
	flow.on_device_list_changed([1], "Xbox Series X Controller", "guid-b")
	r.check(flow.chosen_layout == &"",
		"换手柄后 chosen_layout 必须为空（实际 %s）" % flow.chosen_layout)
	r.check(flow.suggested_layout == &"xbox",
		"换手柄后建议布局必须按 B 重新计算（实际 %s）" % flow.suggested_layout)
	r.check(flow.state == OnboardingFlow.STATE_DEVICE_READY,
		"换手柄必须回到 device_ready（实际 %s）" % flow.state)


## build_profile：只有走完流程才进入构造；但本流程没有 LS 探针，自洽门会让它返回 null。
##
## 档案字段本身的断言已迁到 `test_device_profile` 的 v2 往返用例 —— 这里只证明
## 「流程能进练习」与「它不再产出进不去练习的档案」是两层独立的事实。
func _check_build_profile(r) -> void:
	var unfinished := _fresh()
	r.check(unfinished.build_profile() == null, "未完成流程时 build_profile() 必须为 null")

	var flow := _to_practice(_fresh())
	r.check(flow.build_profile() == null,
		"本流程无 LS 探针：自洽门拒绝，build_profile() 必须为 null")
	r.check(flow.can_enter_practice(),
		"流程门与档案门是两层：流程本身仍可进入练习")
	r.check(flow.mapping() != null, "流程仍有可用的右摇杆映射")
	r.check(flow.quality.has("up"), "探针质量仍记录在流程里")

	var empty := _fresh("8BitDo Pro 2", "guid-8bitdo")
	_to_layout(empty)
	r.check(empty.build_profile() == null, "布局为空时 build_profile() 必须为 null")


## 布局建议只来自 DeviceProfile.suggest_layout：认不出就是空，不预选。
func _check_suggest_layout_wired(r) -> void:
	var dualsense := _fresh("DualSense Wireless Controller", "guid-ps")
	r.check(dualsense.suggested_layout == &"playstation",
		"DualSense 必须建议 playstation（实际 %s）" % dualsense.suggested_layout)
	var unknown := _fresh("8BitDo Pro 2", "guid-8bitdo")
	r.check(unknown.suggested_layout == &"",
		"8BitDo Pro 2 必须无建议（实际 %s）" % unknown.suggested_layout)


func _fresh(device_name := "Xbox Series X Controller", guid := "guid-a") -> OnboardingFlow:
	var flow := OnboardingFlow.new()
	flow.on_device_list_changed([0], device_name, guid)
	return flow


func _to_probe(flow: OnboardingFlow) -> OnboardingFlow:
	flow.on_any_button()
	flow.begin_probe()
	flow.submit_rest_baseline(_rest_samples())
	return flow


func _to_calibrate(flow: OnboardingFlow) -> OnboardingFlow:
	_to_probe(flow)
	_submit_four_steps_from_probe(flow)
	return flow


func _to_layout(flow: OnboardingFlow) -> OnboardingFlow:
	_to_calibrate(flow)
	flow.submit_calibration_center({"ok": true, "center": Vector2(0.01, -0.02)})
	flow.submit_calibration_range({"ok": true, "scale": Vector2(0.98, 0.97)})
	return flow


func _to_practice(flow: OnboardingFlow) -> OnboardingFlow:
	_to_layout(flow)
	flow.confirm_layout(0, 0)
	return flow


## 已经在 probe_rest 的流程：直接走四步。
func _submit_four_steps(flow: OnboardingFlow) -> void:
	flow.submit_probe_step(_step(3, -1))
	flow.submit_probe_step(_step(2, -1))
	flow.submit_probe_step(_step(3, 1))
	flow.submit_probe_step(_step(2, 1))


## 从 probe_up 开始的四步（rest 已采）：覆盖 to_calibrate 的调用路径。
func _submit_four_steps_from_probe(flow: OnboardingFlow) -> void:
	flow.submit_probe_step(_step(3, -1))
	flow.submit_probe_step(_step(2, -1))
	flow.submit_probe_step(_step(3, 1))
	flow.submit_probe_step(_step(2, 1))


## 四步各自「成功」但上/右落在同一根轴：专门用来触发交叉校验。
func _submit_four_steps_ambiguous(flow: OnboardingFlow) -> void:
	flow.submit_probe_step(_step(3, -1))
	flow.submit_probe_step(_step(3, -1))
	flow.submit_probe_step(_step(3, 1))
	flow.submit_probe_step(_step(2, 1))


static func _rest_samples() -> Array[PackedFloat32Array]:
	var samples: Array[PackedFloat32Array] = []
	for _index in 18:
		var frame := PackedFloat32Array()
		frame.resize(8)
		frame[0] = 0.01
		frame[1] = -0.01
		samples.append(frame)
	return samples


static func _step(axis: int, sign: int) -> Dictionary:
	return {
		"ok": true,
		"axis": axis,
		"sign": sign,
		"delta": 0.9 * float(sign),
		"samples": 18,
		"margin": 0.7,
		"separation": 6.0,
		"code": &"",
		"message": "",
	}


static func _reject(code: StringName, message: String) -> Dictionary:
	return {
		"ok": false,
		"axis": -1,
		"sign": 0,
		"delta": 0.0,
		"samples": 2,
		"margin": 0.0,
		"separation": 0.0,
		"code": code,
		"message": message,
	}


## 一份完整档案：rs_x = (2, -1)、rs_y = (3, -1)，校准与质量都填满。
##
## 05 阶段 D-06 起，缺 LS 的档案会被 `can_enter_practice()` 拒绝；`offer_profile`
## 会直接判「不是可复用档案」，本套件里那些依赖复用门命中的用例就会全红。所以这里
## 显式补上真实的 LS 索引、符号、校准与 `ls_ready`（与输入设置页的新档案同形）。
static func _profile() -> DeviceProfile:
	var profile := DeviceProfile.new()
	profile.key = "guid:guid-a"
	profile.device_name = "Xbox Series X Controller"
	profile.device_guid = "guid-a"
	profile.profile_id = "primary"
	profile.axes = AxisMapping.new()
	profile.axes.rs_x_index = 2
	profile.axes.rs_x_sign = -1
	profile.axes.rs_y_index = 3
	profile.axes.rs_y_sign = -1
	profile.axes.ls_x_index = 0
	profile.axes.ls_x_sign = 1
	profile.axes.ls_y_index = 1
	profile.axes.ls_y_sign = 1
	profile.calibration = Calibration.new()
	profile.calibration.center_x = 0.01
	profile.calibration.center_y = -0.02
	profile.calibration.scale_x = 0.98
	profile.calibration.scale_y = 0.97
	profile.calibration.ls_center_x = 0.0
	profile.calibration.ls_center_y = 0.0
	profile.calibration.ls_scale_x = 0.99
	profile.calibration.ls_scale_y = 0.96
	profile.quality = {
		"range_ready": true,
		"ls_ready": true,
		"up": {"samples": 30, "margin": 0.7, "separation": 6.0},
		"right": {"samples": 28, "margin": 0.68, "separation": 5.4},
	}
	profile.layout = DeviceProfile.LAYOUT_XBOX
	profile.layout_confirmed = true
	return profile
