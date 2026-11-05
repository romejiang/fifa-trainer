extends RefCounted

## `InputSetup` 的无头证明：推哪对轴就选哪对、扳机跳变不干扰、人工可覆盖、档案字段正确。
##
## 为什么这些必须是纯函数：04-07 的两次真机失败都发生在「采样窗口 + 判定」这一段。
## 如果选轴对、算量程只能靠真机肉眼，同一类缺陷下一次还会在真机上才发现 —— 而真机
## 一轮要卸载、装包、连蓝牙、推摇杆。这里每一帧都是合成数据，整套跑完不到一秒。
##
## 覆盖的四条用户要求（2026-11-05）：
##   1. 一页、无状态机 —— 本套件没有「第几步」可断言，只有「现在选中哪一对」；
##   2. 想测多久就测多久 —— 没有帧数上限，喂 200 帧与喂 20 帧的结论只取决于数据；
##   3. 识别错了当场能改 —— 人工切换与符号翻转立刻生效，且不被后续自动识别覆盖；
##   4. 扳机跳变不能污染识别 —— `rest = min` 与「设备基线跳变不给分」各有一条断言。

const AXIS_COUNT := 8
const TOL := 1e-6


func run(r) -> void:
	_check_idle_has_no_pair(r)
	_check_push_selects_pair(r)
	_check_trigger_jump_does_not_win(r)
	_check_manual_cycle(r)
	_check_signs(r)
	_check_range_ready(r)
	_check_center_scale(r)
	_check_trigger_rest_is_min(r)
	_check_save_gate(r)
	_check_layout_confirm(r)
	_check_legacy_profile(r)
	_check_profile(r)
	_check_reset(r)
	_check_rs_pair_frozen_before_ls(r)
	_check_ls_pair_excludes_rs(r)
	_check_ls_up_sign(r)
	_check_ls_right_sign(r)
	_check_ls_ready_gate(r)
	_check_build_profile_writes_ls(r)
	_check_reset_clears_ls(r)
	var total: int = r.assertions
	r.check(total >= 100, "本套件至少 100 条断言（实际 %d）" % total)
	r.complete()


## 1. 静止时没有活动轴对：噪声不能凑出一对。
func _check_idle_has_no_pair(r) -> void:
	var setup := InputSetup.new()
	for _frame_index in 30:
		setup.observe(_frame({0: 0.01, 1: -0.01, 2: 0.02, 3: -0.02, 4: -1.0, 5: -1.0}))
	r.check(setup.active_pair() == InputSetup.PAIR_NONE,
		"静止噪声不得选出轴对（实际 %s）" % str(setup.active_pair()))
	r.check(setup.recent_range(2) < InputSetup.MIN_PAIR_TRAVEL,
		"静止噪声的峰峰值低于门槛（实际 %.3f）" % setup.recent_range(2))
	r.check(not setup.range_ready(), "没有轴对时量程未就绪")


## 2. 推哪一对就选哪一对：另一对的大位移不能抢走。
func _check_push_selects_pair(r) -> void:
	var setup := InputSetup.new()
	# 先让 (0,1) 轻微晃动：它不该因为「先动」而被记住。
	_sweep(setup, 0, 0.0, 0.2, 6)
	_sweep(setup, 1, 0.0, 0.2, 6)
	r.check(setup.active_pair() == InputSetup.PAIR_NONE,
		"0.2 的行程低于门槛，仍不算一对（实际 %s）" % str(setup.active_pair()))

	var pushed := InputSetup.new()
	_sweep(pushed, 2, -1.0, 1.0, 12)
	_sweep(pushed, 3, 1.0, -1.0, 12)
	r.check(pushed.active_pair() == Vector2i(2, 3),
		"推 2/3 必须选中 (2,3)（实际 %s）" % str(pushed.active_pair()))
	r.check(pushed.recent_range(2) >= 1.9,
		"2 轴最近峰峰值接近 2.0（实际 %.3f）" % pushed.recent_range(2))

	# 换一对继续推：最近在动的那一对必须换过去，旧的一对留在窗口里也不影响。
	_sweep(pushed, 6, -1.0, 1.0, 12)
	_sweep(pushed, 7, -1.0, 1.0, 12)
	r.check(pushed.active_pair() == Vector2i(6, 7),
		"改推 6/7 后轴对必须切到 (6,7)（实际 %s）" % str(pushed.active_pair()))


## 3. 扳机从 0.000 一步跳到 -1.000 不得被当成「在动」。
##
## 这是 04-07 尝试二的真实序列：所有轴先读 0.000，扳机首次上报后变 -1.000 并停在那里。
func _check_trigger_jump_does_not_win(r) -> void:
	var setup := InputSetup.new()
	_feed(setup, {}, 20)
	_feed(setup, {4: -1.0, 5: -1.0}, 1)
	_feed(setup, {4: -1.0, 5: -1.0}, 30)
	r.check(setup.recent_range(4) >= 0.9,
		"扳机确实跳了 1.0（实际 %.3f）" % setup.recent_range(4))
	r.check(setup.recent_range(5) >= 0.9,
		"第二根扳机同样跳了 1.0（实际 %.3f）" % setup.recent_range(5))
	r.check(setup.active_pair() == InputSetup.PAIR_NONE,
		"设备基线跳变不得选出 (4,5)（实际 %s）" % str(setup.active_pair()))

	# 用户随后推右摇杆：轴对必须切过去。
	_sweep(setup, 2, -1.0, 1.0, 12)
	_sweep(setup, 3, -1.0, 1.0, 12)
	r.check(setup.active_pair() == Vector2i(2, 3),
		"推右摇杆后轴对切到 (2,3)（实际 %s）" % str(setup.active_pair()))
	r.eq_float(setup.trigger_rest(4), -1.0, TOL, "扳机静止值仍是最小值 -1.0")


## 4. 人工切换：LB/RB 之后固定，不被自动识别覆盖；B 之外没有解除方式。
func _check_manual_cycle(r) -> void:
	var setup := InputSetup.new()
	_sweep(setup, 2, -1.0, 1.0, 10)
	_sweep(setup, 3, -1.0, 1.0, 10)
	r.check(setup.active_pair() == Vector2i(2, 3), "前置：自动选中 (2,3)")
	setup.cycle_pair(1)
	r.check(setup.active_pair() == Vector2i(4, 5), "RB 从 (2,3) 走到 (4,5)")
	_sweep(setup, 0, -1.0, 1.0, 20)
	r.check(setup.active_pair() == Vector2i(4, 5),
		"人工选择不被自动识别覆盖（实际 %s）" % str(setup.active_pair()))
	setup.cycle_pair(1)
	r.check(setup.active_pair() == Vector2i(6, 7), "RB 再走一步到 (6,7)")
	setup.cycle_pair(1)
	r.check(setup.active_pair() == Vector2i(0, 1), "RB 到末尾回卷到 (0,1)")
	setup.cycle_pair(-1)
	r.check(setup.active_pair() == Vector2i(6, 7), "LB 回卷到 (6,7)")
	setup.cycle_pair(0)
	r.check(setup.active_pair() == Vector2i(6, 7), "direction 0 不改变选择")

	var fresh := InputSetup.new()
	fresh.cycle_pair(1)
	r.check(fresh.active_pair() == Vector2i(0, 1), "没有自动结果时 RB 落到第一对")
	var back := InputSetup.new()
	back.cycle_pair(-1)
	r.check(back.active_pair() == Vector2i(6, 7), "没有自动结果时 LB 落到最后一对")


## 5. 符号翻转：两根轴独立，翻两次回到原值。
func _check_signs(r) -> void:
	var setup := InputSetup.new()
	r.check(setup.x_sign() == 1 and setup.y_sign() == 1, "默认符号都是 +1")
	setup.toggle_x_sign()
	r.check(setup.x_sign() == -1, "X 翻转后是 -1")
	r.check(setup.y_sign() == 1, "翻转 X 不得动 Y")
	setup.toggle_y_sign()
	r.check(setup.y_sign() == -1, "Y 翻转后是 -1")
	setup.toggle_x_sign()
	r.check(setup.x_sign() == 1, "再翻一次回到 +1")
	r.check(setup.y_sign() == -1, "Y 仍保持 -1")


## 6. 量程门槛：两轴峰峰值都到 1.2 才就绪；只推一个方向不算。
func _check_range_ready(r) -> void:
	r.eq_float(float(InputSetup.RANGE_READY), 1.2, TOL, "门槛常量是 1.2")

	var one_way := InputSetup.new()
	_sweep(one_way, 2, 0.0, 1.0, 10)
	_sweep(one_way, 3, 0.0, 1.0, 10)
	r.check(one_way.active_pair() == Vector2i(2, 3), "前置：选中 (2,3)")
	r.eq_float(one_way.axis_span(2), 1.0, 1e-5, "只往正方向推到底：峰峰值 1.0")
	r.check(not one_way.range_ready(), "峰峰值 1.0 未到门槛，只显示「还没推到底」")

	var short := InputSetup.new()
	_sweep(short, 2, -0.6, 0.59, 10)
	_sweep(short, 3, -0.6, 0.59, 10)
	r.check(short.axis_span(2) < InputSetup.RANGE_READY,
		"峰峰值 1.19 低于门槛（实际 %.4f）" % short.axis_span(2))
	r.check(not short.range_ready(), "峰峰值 1.19 仍未就绪")

	var ready := InputSetup.new()
	_sweep(ready, 2, -0.6, 0.61, 10)
	_sweep(ready, 3, -0.6, 0.61, 10)
	r.check(ready.axis_span(2) >= InputSetup.RANGE_READY,
		"峰峰值 1.21 达到门槛（实际 %.4f）" % ready.axis_span(2))
	r.check(ready.range_ready(), "两轴都过门槛 → 就绪")


## 7. 中点与量程半宽都从长窗口 min/max 推导。
func _check_center_scale(r) -> void:
	var setup := InputSetup.new()
	_sweep(setup, 2, -1.0, 1.0, 10)
	_sweep(setup, 3, -0.5, 0.5, 10)
	r.check(setup.active_pair() == Vector2i(2, 3), "前置：选中 (2,3)")
	r.eq_float(setup.center().x, 0.0, TOL, "X 中点 = (min+max)/2 = 0")
	r.eq_float(setup.center().y, 0.0, TOL, "Y 中点 = 0")
	r.eq_float(setup.scale().x, 1.0, TOL, "X 量程半宽 = 1.0")
	r.eq_float(setup.scale().y, 0.5, TOL, "Y 量程半宽 = 0.5")

	var skewed := InputSetup.new()
	_sweep(skewed, 2, -0.8, 0.6, 10)
	r.check(skewed.active_pair() == InputSetup.PAIR_NONE,
		"单轴行程凑不出一对（实际 %s）" % str(skewed.active_pair()))
	_hold(skewed, 2, -0.8, 2)
	_hold(skewed, 2, 0.6, 2)
	_hold(skewed, 3, 0.5, 4)
	skewed.cycle_pair(1)
	r.check(skewed.active_pair() == Vector2i(4, 5), "人工选到 (4,5) 以验证 center/scale 的取轴")
	_hold(skewed, 4, -0.6, 3)
	_hold(skewed, 4, 0.4, 3)
	_hold(skewed, 5, -0.2, 3)
	_hold(skewed, 5, 0.2, 3)
	r.eq_float(skewed.center().x, -0.1, 1e-5, "非对称 X：中点 = (-0.6+0.4)/2 = -0.1")
	r.eq_float(skewed.scale().x, 0.5, 1e-5, "非对称 X：半宽 = 0.5")
	r.eq_float(skewed.center().y, 0.0, 1e-5, "Y 中点 = 0")
	r.eq_float(skewed.scale().y, 0.2, 1e-5, "Y 半宽 = 0.2")


## 8. 扳机静止值 = 观测到的最小值（04-07 尝试二的修复点）。
func _check_trigger_rest_is_min(r) -> void:
	var setup := InputSetup.new()
	_feed(setup, {4: 0.0, 5: 0.0}, 3)
	r.eq_float(setup.trigger_rest(4), 0.0, TOL, "首次上报 0.000 时 rest 就是 0")
	_feed(setup, {4: -1.0, 5: -1.0}, 3)
	r.eq_float(setup.trigger_rest(4), -1.0, TOL, "跳到 -1.000 后 rest 自动收敛到 -1")
	_feed(setup, {4: 1.0, 5: 1.0}, 2)
	r.eq_float(setup.trigger_rest(4), -1.0, TOL, "扳机按到底也不改变 rest = min")
	r.eq_float(setup.trigger_rest(9), 0.0, TOL, "越界轴返回 0")
	r.eq_float(setup.trigger_rest(-1), 0.0, TOL, "负数轴返回 0")


## 9. 保存门：量程没推满时 `can_save()` 为 false 且 `build_profile()` 返回 null。
##
## 这是 04-11 的真机缺陷：用户在量程没推满时按 A，程序写出 `scale=1.0 / center=0`
## 的「默认校准」，下次启动直接复用。null 是唯一可接受的结果 —— 不是「写一份降级档案」。
func _check_save_gate(r) -> void:
	var idle := InputSetup.new()
	for _frame_index in 30:
		idle.observe(_frame({0: 0.01, 1: -0.01, 2: 0.02, 3: -0.02}))
	r.check(not idle.can_save(), "没有轴对时 can_save 为 false")
	r.check(idle.build_profile("Pad", "", "2026-11-05T22:00:00") == null,
		"没有轴对时 build_profile 必须返回 null")

	var one_way := InputSetup.new()
	_sweep(one_way, 2, 0.0, 1.0, 12)
	_sweep(one_way, 3, 0.0, 1.0, 12)
	r.check(one_way.active_pair() == Vector2i(2, 3), "前置：只推一个方向也能认出轴对")
	r.check(not one_way.can_save(), "峰峰值 1.0 未到 1.2：can_save 为 false")
	r.check(one_way.build_profile("Pad", "", "") == null,
		"量程未满时 build_profile 必须返回 null（不写默认校准）")

	var ready := InputSetup.new()
	_sweep(ready, 2, -1.0, 1.0, 12)
	_sweep(ready, 3, -1.0, 1.0, 12)
	# 05 阶段 D-06：保存门同时要求 LS 就绪。RS 推满只是必要条件 —— 缺左摇杆
	# 映射的档案会让四个 relative_to_ls 技能静默变成「推了完全没反应」。
	r.check(not ready.can_save(), "RS 推满但 LS 未就绪：can_save 仍为 false")
	r.check(ready.build_profile("Pad", "", "") == null,
		"LS 未就绪时 build_profile 必须返回 null")
	_sweep_ls(ready)
	r.check(ready.can_save(), "RS 与 LS 量程都推满：can_save 为 true")
	r.check(ready.build_profile("Pad", "", "") != null, "量程满了才允许返回档案")


## 10. 布局：建议值只用于显示；Start 切换；A 的保存路径才把 `layout_confirmed` 置真。
func _check_layout_confirm(r) -> void:
	var setup := InputSetup.new()
	r.check(setup.layout_cycle("Xbox Series X Controller") == DeviceProfile.LAYOUT_XBOX,
		"Xbox 设备名 → 默认建议 xbox（实际 %s）" % String(setup.layout_cycle("Xbox Series X Controller")))
	r.check(setup.layout_cycle("DualSense Wireless Controller") == DeviceProfile.LAYOUT_PLAYSTATION,
		"DualSense → 默认建议 playstation")
	r.check(setup.layout_cycle("8BitDo Pro 2") == DeviceProfile.LAYOUT_XBOX,
		"认不出的设备名 → 建议 xbox（空布局会让练习屏进死角）")
	r.check(not setup.layout_confirmed(), "默认布局未确认")

	setup.cycle_layout("Xbox Series X Controller")
	r.check(setup.layout_cycle("Xbox Series X Controller") == DeviceProfile.LAYOUT_PLAYSTATION,
		"Start 切一次：xbox → playstation")
	setup.cycle_layout("Xbox Series X Controller")
	r.check(setup.layout_cycle("Xbox Series X Controller") == DeviceProfile.LAYOUT_XBOX,
		"再切一次：playstation → xbox")
	r.check(not setup.layout_confirmed(), "只切换布局不算确认")

	_sweep(setup, 2, -1.0, 1.0, 12)
	_sweep(setup, 3, -1.0, 1.0, 12)
	# `_sweep_ls` 必须排在两条 RS `_sweep` 之后：它先推轴 0/1，若在 RS 冻结之前
	# 调用，`_maybe_freeze_rs_pair()` 会把 (0,1) 当成 RS，LS 就没有候选轴对了。
	_sweep_ls(setup)
	var unconfirmed := setup.build_profile("Xbox Series X Controller", "GUID-1", "")
	r.check(unconfirmed != null, "前置：量程满了才能构造档案")
	r.check(unconfirmed != null and not unconfirmed.layout_confirmed,
		"没调 mark_layout_confirmed 时档案不得写 layout_confirmed=true")

	setup.mark_layout_confirmed()
	r.check(setup.layout_confirmed(), "A 的保存路径调用之后 layout_confirmed 为 true")
	var confirmed := setup.build_profile("Xbox Series X Controller", "GUID-1", "")
	r.check(confirmed != null and confirmed.layout_confirmed,
		"确认之后的档案 layout_confirmed 为 true")
	r.check(confirmed != null and confirmed.layout == DeviceProfile.LAYOUT_XBOX,
		"档案布局取用户确认后的当前值（实际 %s）" % (String(confirmed.layout) if confirmed != null else "null"))


## 11. 旧档案必须失效：缺 `quality.range_ready` 或校准是默认值 → `can_reuse` 为 false。
##
## 这是「设置页重新出现」的机械保证：`main.gd` 的复用路径不再自己写一份结构判定，
## 而是直接调 `can_enter_practice()`。
func _check_legacy_profile(r) -> void:
	var legacy := _stored_profile()
	legacy.quality = {"up": {"samples": 30, "margin": 0.7, "separation": 6.0}}
	r.check(not legacy.can_enter_practice(), "旧档案无 range_ready 标记 → 不能进练习")
	r.check(not legacy.can_reuse(2, 1, 3, 1), "旧档案无标记时 can_reuse 必须为 false")

	var failed_flag := _stored_profile()
	failed_flag.quality = {"range_ready": false, "span_x": 1.0, "span_y": 1.0}
	r.check(not failed_flag.can_reuse(2, 1, 3, 1),
		"04-09 在量程未满时保存的档案（range_ready=false）不得复用")

	var string_flag := _stored_profile()
	string_flag.quality = {"range_ready": "true"}
	r.check(not string_flag.can_reuse(2, 1, 3, 1),
		"range_ready 是字符串时不算标记（JSON 里 true 不带引号）")

	var default_calibration := _stored_profile()
	default_calibration.calibration = Calibration.new()
	default_calibration.quality = {}
	r.check(not default_calibration.can_enter_practice(),
		"04-09 的旧档案（scale=1.0 / center=0 + 无标记）→ 不能进练习")

	var narrow := _stored_profile()
	narrow.calibration.scale_x = 0.2
	r.check(not narrow.can_enter_practice(), "半量程 0.2 < 0.5 → 不能进练习")

	var off_center := _stored_profile()
	off_center.calibration.center_x = 0.8
	r.check(not off_center.can_enter_practice(), "中点 0.8 越界 → 不能进练习")

	var unconfirmed := _stored_profile()
	unconfirmed.layout_confirmed = false
	r.check(not unconfirmed.can_enter_practice(), "布局未确认 → 不能进练习")

	var fresh := _stored_profile()
	r.check(fresh.can_enter_practice(), "新档案（标记 + 合理校准 + 已确认布局）→ 可进练习")
	r.check(fresh.can_reuse(2, 1, 3, 1), "新档案四项相等 → 可复用")
	r.check(not fresh.can_reuse(3, 1, 2, 1), "新档案索引互换 → 拒绝")


## 12. 档案字段 + 复用门四项 + 可往返序列化。
func _check_profile(r) -> void:
	var setup := InputSetup.new()
	_sweep(setup, 2, -1.0, 1.0, 10)
	_sweep(setup, 3, -0.8, 0.6, 10)
	# RS 冻结之后再推 LS（顺序不可倒，见 `_sweep_ls` 的注释）。
	_sweep_ls(setup)
	_feed(setup, {4: -1.0, 5: -1.0}, 3)
	setup.toggle_y_sign()
	setup.mark_layout_confirmed()

	var profile := setup.build_profile("Xbox Series X Controller", "ABC-123", "2026-11-05T22:00:00")
	r.check(profile != null, "build_profile 必须返回档案")
	r.check(profile.key == "guid:abc-123", "key 用 guid 小写（实际 %s）" % profile.key)
	r.check(profile.profile_id == "input_setup", "profile_id 固定 input_setup")
	r.check(profile.device_name == "Xbox Series X Controller", "设备名逐字保留")
	r.check(profile.device_guid == "ABC-123", "设备 guid 逐字保留")
	r.check(profile.axes.rs_x_index == 2, "rs_x_index 来自轴对 X（实际 %d）" % profile.axes.rs_x_index)
	r.check(profile.axes.rs_y_index == 3, "rs_y_index 来自轴对 Y（实际 %d）" % profile.axes.rs_y_index)
	r.check(profile.axes.rs_x_sign == 1, "X 符号默认 +1")
	r.check(profile.axes.rs_y_sign == -1, "Y 符号被翻转成 -1")
	# 04 阶段这一页刻意不映射左摇杆（ls = -1）；05 阶段 D-06 补上：四个
	# relative_to_ls 技能需要真实的 LS 索引、符号与校准。索引必须非负，且不得与
	# RS 共用同一对轴。
	r.check(profile.axes.ls_x_index >= 0 and profile.axes.ls_y_index >= 0,
		"05 阶段 D-06：LS 索引必须非负（实际 %d/%d）" % [
			profile.axes.ls_x_index, profile.axes.ls_y_index])
	r.check(Vector2i(profile.axes.ls_x_index, profile.axes.ls_y_index)
		!= Vector2i(profile.axes.rs_x_index, profile.axes.rs_y_index),
		"LS 轴对不得与 RS 轴对相同")
	r.check(bool(profile.quality.get("ls_ready", false)),
		"05 阶段：档案必须记下 quality.ls_ready = true")
	r.check(profile.axes.lt_index == 4 and profile.axes.rt_index == 5,
		"扳机轴按标准布局记 4/5")
	r.eq_float(profile.axes.rt_rest, -1.0, TOL, "扳机静止值是观测到的最小值")
	r.eq_float(profile.calibration.center_x, 0.0, 1e-5, "X 中点写进档案")
	r.eq_float(profile.calibration.scale_x, 1.0, 1e-5, "X 量程半宽写进档案")
	r.eq_float(profile.calibration.center_y, -0.1, 1e-5, "Y 中点 = (-0.8+0.6)/2")
	r.eq_float(profile.calibration.scale_y, 0.7, 1e-5, "Y 量程半宽 = 0.7")
	r.check(profile.layout == DeviceProfile.LAYOUT_XBOX, "Xbox 名字 → xbox 布局")
	r.check(profile.layout_confirmed, "本页保存即确认布局")
	r.check(profile.probed_at_iso == "2026-11-05T22:00:00", "墙钟由调用方传入")
	r.check(bool(profile.quality.get("range_ready", false)), "quality 记下量程是否就绪")

	r.check(profile.can_reuse(2, 1, 3, -1), "复用门：四项逐项相等 → true")
	r.check(not profile.can_reuse(3, 1, 2, -1), "复用门：索引互换 → false")
	r.check(not profile.can_reuse(2, -1, 3, -1), "复用门：符号不同 → false")
	r.check(not profile.can_reuse(2, 1, 3, 1), "复用门：Y 符号不同 → false")

	var errors: Array[ConfigError] = []
	var reloaded := DeviceProfile.from_dict(profile.to_dict(), errors)
	r.check(reloaded != null and errors.is_empty(),
		"档案可以往返序列化，不会被 load_all 整份丢弃（errors=%d）" % errors.size())

	# 从未推过：build_profile 直接拒绝（保存门），不再写「未校准但看起来合法」的档案。
	var untouched := InputSetup.new()
	untouched.observe(_frame({2: 0.0, 3: 0.0}))
	r.check(untouched.build_profile("Pad", "", "") == null,
		"没推过量程时 build_profile 返回 null（保存门）")

	# 没有 guid 时 key 用规范化设备名：用一份量程已满的档案验证。
	var named := InputSetup.new()
	_sweep(named, 2, -1.0, 1.0, 10)
	_sweep(named, 3, -1.0, 1.0, 10)
	_sweep_ls(named)
	named.mark_layout_confirmed()
	var pad := named.build_profile("Pad", "", "")
	r.check(pad != null and pad.key == "name:pad",
		"没有 guid 时 key 用规范化设备名（实际 %s）" % (pad.key if pad != null else "null"))


## 12. reset：统计、人工选择、符号、布局全部清空。
func _check_reset(r) -> void:
	var setup := InputSetup.new()
	_sweep(setup, 2, -1.0, 1.0, 10)
	_feed(setup, {4: -1.0, 5: -1.0}, 3)
	setup.toggle_x_sign()
	setup.toggle_y_sign()
	setup.cycle_pair(1)
	setup.cycle_layout("Xbox Series X Controller")
	setup.mark_layout_confirmed()
	r.check(setup.active_pair() != InputSetup.PAIR_NONE, "重置前有轴对")
	setup.reset()
	r.check(setup.active_pair() == InputSetup.PAIR_NONE, "reset 之后没有轴对")
	r.check(setup.x_sign() == 1 and setup.y_sign() == 1, "reset 清掉人工符号")
	r.check(setup.layout_cycle("Xbox Series X Controller") == DeviceProfile.LAYOUT_XBOX,
		"reset 把布局退回设备名建议值")
	r.check(not setup.layout_confirmed(), "reset 清掉布局确认")
	r.eq_float(setup.trigger_rest(4), 0.0, TOL, "reset 清掉扳机 min")
	r.eq_float(setup.axis_span(2), 0.0, TOL, "reset 清掉长窗口 min/max")
	r.eq_float(setup.center().x, 0.0, TOL, "reset 后中点为 0")
	r.check(setup.axis_range(2) == Vector2.ZERO, "从未采样时 axis_range 返回 ZERO")


## 13. D5-1 的机械证明：先推 RS 四方向、再推 LS，RS 轴对必须在 LS 检测开始之前
## 就被冻结。`active_pair()` 的最近性会把「现在在动的那一对」翻到 LS；如果
## `rs_pair()` 跟着它走，档案里的 RS 就会变成 (0,1)，两只摇杆对调。
func _check_rs_pair_frozen_before_ls(r) -> void:
	var setup := _ls_ready_setup()
	r.check(setup.active_pair() == Vector2i(0, 1),
		"前置：此刻最近在动的是 LS（实际 %s）" % str(setup.active_pair()))
	r.check(setup.rs_pair() == Vector2i(2, 3),
		"D5-1：先推 RS 再推 LS，rs_pair 必须冻结在 (2,3)（实际 %s）" % str(setup.rs_pair()))
	r.check(setup.ls_pair() == Vector2i(0, 1),
		"D5-1：ls_pair 必须是排除冻结 RS 之后的 (0,1)（实际 %s）" % str(setup.ls_pair()))
	r.check(setup.ls_ready(), "D5-1：轴对 + 两个符号 + 两轴量程齐备 → ls_ready")

	setup.mark_layout_confirmed()
	var profile := setup.build_profile("Xbox Series X Controller", "GUID-D51", "")
	r.check(profile != null, "D5-1：保存门通过时必须能构造档案")
	if profile == null:
		return
	r.check(profile.axes.rs_x_index == 2 and profile.axes.rs_y_index == 3,
		"档案 RS 必须是冻结的 2/3（实际 %d/%d）" % [
			profile.axes.rs_x_index, profile.axes.rs_y_index])
	r.check(profile.axes.ls_x_index == 0 and profile.axes.ls_y_index == 1,
		"档案 LS 必须是 0/1（实际 %d/%d）" % [
			profile.axes.ls_x_index, profile.axes.ls_y_index])
	r.check(bool(profile.quality.get("ls_ready", false)),
		"档案 quality.ls_ready 必须为 true")
	r.check(profile.quality.get("ls_pair") == [0, 1],
		"档案 quality.ls_pair 必须记录 LS 索引（实际 %s）" % str(profile.quality.get("ls_pair")))
	r.eq_float(profile.calibration.ls_scale_x, 1.0, 1e-5, "LS X 量程半宽写进档案")
	r.eq_float(profile.calibration.ls_scale_y, 1.0, 1e-5, "LS Y 量程半宽写进档案")


## 14. `ls_pair()` 永远不返回冻结的 RS 对：RS 与 LS 必须是两对不同的轴。
func _check_ls_pair_excludes_rs(r) -> void:
	var setup := _ls_ready_setup()
	# 先让 LS 的最近窗口自然过期（长窗口行程不受影响），再轻轻推一下 LS、用力推 RS：
	# active_pair 会翻回 (2,3)，但 ls_pair 仍必须排除冻结的 RS 对。
	_feed(setup, {}, 61)
	_feed(setup, {0: 0.4, 1: -0.4}, 3)
	_feed(setup, {2: 1.0, 3: -1.0}, 3)
	r.check(setup.active_pair() == Vector2i(2, 3),
		"前置：再推 RS 后 active_pair 回到 (2,3)（实际 %s）" % str(setup.active_pair()))
	r.check(setup.ls_pair() != Vector2i(2, 3),
		"ls_pair 永远不得等于冻结的 rs_pair（实际 %s）" % str(setup.ls_pair()))
	r.check(setup.ls_pair() == Vector2i(0, 1),
		"LS 仍是最近推满的 (0,1)（实际 %s）" % str(setup.ls_pair()))


## 15. 向左摇杆「向上推」的三种结果：Y 读数为负 → +1、为正 → -1、推成左右 → sideways。
##
## 符号不能从极值推断 —— 用户为了量程把四个方向都推满了，min/max 里没有方向信息。
## 必须有一次**已知方向**的观测，推错时明确回报，绝不静默把 X 的位移当成 Y。
func _check_ls_up_sign(r) -> void:
	var negative := _ls_unconfirmed_setup()
	negative.arm_ls_up()
	_feed(negative, {0: 0.0, 1: -1.0}, 3)
	r.check(negative.has_ls_y_sign() and negative.ls_y_sign() == 1,
		"向上推且 Y 轴读数为负 → ls_y_sign = +1（实际 %d）" % negative.ls_y_sign())
	r.check(negative.ls_arm_result() == &"ok", "成功时 ls_arm_result = ok")

	var positive := _ls_unconfirmed_setup()
	_feed(positive, {0: 0.0, 1: -0.5}, 2)
	positive.arm_ls_up()
	_feed(positive, {0: 0.0, 1: 0.5}, 3)
	r.check(positive.has_ls_y_sign() and positive.ls_y_sign() == -1,
		"向上推但 Y 轴读数为正（反接）→ ls_y_sign = -1（实际 %d）" % positive.ls_y_sign())

	var sideways := _ls_unconfirmed_setup()
	sideways.arm_ls_up()
	_feed(sideways, {0: -1.0, 1: 1.0}, 3)
	r.check(sideways.ls_arm_result() == &"sideways",
		"向上推却推成左右 → ls_arm_result = sideways（实际 %s）" % String(sideways.ls_arm_result()))
	r.check(not sideways.has_ls_y_sign() and sideways.ls_y_sign() == 1,
		"sideways 不得改动 Y 符号")
	r.check(not sideways.ls_arm_pending(), "sideways 之后不再 pending")


## 16. 向左摇杆「向右推」：X 读数为正 → +1、为负 → -1。
func _check_ls_right_sign(r) -> void:
	var positive := _ls_unconfirmed_setup()
	positive.arm_ls_right()
	_feed(positive, {0: 1.0, 1: 0.0}, 3)
	r.check(positive.has_ls_x_sign() and positive.ls_x_sign() == 1,
		"向右推且 X 轴读数为正 → ls_x_sign = +1（实际 %d）" % positive.ls_x_sign())

	var negative := _ls_unconfirmed_setup()
	_feed(negative, {0: 0.5, 1: 0.0}, 2)
	negative.arm_ls_right()
	_feed(negative, {0: -1.0, 1: 0.0}, 3)
	r.check(negative.has_ls_x_sign() and negative.ls_x_sign() == -1,
		"向右推但 X 轴读数为负（反接）→ ls_x_sign = -1（实际 %d）" % negative.ls_x_sign())


## 17. `ls_ready()` 的三个必要条件：轴对、两个符号、两轴量程。缺一不可。
func _check_ls_ready_gate(r) -> void:
	var idle := InputSetup.new()
	r.check(not idle.ls_ready(), "没有 LS 轴对 → ls_ready 为 false")
	r.check(idle.ls_pair() == InputSetup.PAIR_NONE, "没有轴对时 ls_pair 返回 PAIR_NONE")

	var short := InputSetup.new()
	_sweep(short, 2, -1.0, 1.0, 12)
	_sweep(short, 3, -1.0, 1.0, 12)
	_sweep(short, 0, -0.2, 0.2, 8)
	_sweep(short, 1, -0.2, 0.2, 8)
	r.check(short.ls_pair() == Vector2i(0, 1),
		"0.4 的行程足够认出 LS 轴对（实际 %s）" % str(short.ls_pair()))
	r.check(not short.ls_ready(), "符号未确认 → ls_ready 为 false")
	short.arm_ls_up()
	_feed(short, {0: 0.0, 1: -0.4}, 3)
	short.arm_ls_right()
	_feed(short, {0: 0.4, 1: 0.0}, 3)
	r.check(short.has_ls_x_sign() and short.has_ls_y_sign(), "两个符号都已确认")
	r.check(not short.ls_ready(), "量程只有 0.4 < 1.2 → ls_ready 仍为 false")
	_sweep(short, 0, -1.0, 1.0, 12)
	_sweep(short, 1, -1.0, 1.0, 12)
	r.check(short.ls_ready(), "量程推满 → ls_ready 为 true")


## 18. `build_profile()` 写真实的 LS 索引 / 符号 / 校准，不是占位 -1。
func _check_build_profile_writes_ls(r) -> void:
	var setup := _ls_ready_setup()
	setup.toggle_y_sign()
	setup.mark_layout_confirmed()
	var profile := setup.build_profile("Pad", "", "")
	r.check(profile != null, "前置：LS 就绪后 build_profile 非 null")
	if profile == null:
		return
	r.check(profile.axes.rs_x_index == 2 and profile.axes.rs_y_index == 3,
		"RS 索引来自冻结对")
	r.check(profile.axes.rs_y_sign == -1, "RS Y 符号仍来自十字键翻转")
	r.check(profile.axes.ls_x_index == 0 and profile.axes.ls_y_index == 1,
		"LS 索引来自 ls_pair（实际 %d/%d）" % [
			profile.axes.ls_x_index, profile.axes.ls_y_index])
	r.check(profile.axes.ls_x_sign == 1 and profile.axes.ls_y_sign == 1,
		"LS 符号来自自动确认（实际 %d/%d）" % [
			profile.axes.ls_x_sign, profile.axes.ls_y_sign])
	r.eq_float(profile.calibration.ls_center_x, 0.0, 1e-5, "LS X 中点写进档案")
	r.eq_float(profile.calibration.ls_center_y, 0.0, 1e-5, "LS Y 中点写进档案")
	r.eq_float(profile.calibration.ls_scale_x, 1.0, 1e-5, "LS X 量程半宽写进档案")
	r.eq_float(profile.calibration.ls_scale_y, 1.0, 1e-5, "LS Y 量程半宽写进档案")
	r.check(profile.quality.get("ls_pair") == [0, 1], "quality.ls_pair 记录 LS 索引")
	r.check(bool(profile.quality.get("ls_ready", false)), "quality.ls_ready = true")


## 19. reset：RS 冻结、LS 轴对、两个符号、未完成的摆臂全部清空。
func _check_reset_clears_ls(r) -> void:
	var setup := _ls_ready_setup()
	r.check(setup.ls_ready(), "前置：LS 已就绪")
	setup.reset()
	r.check(setup.rs_pair() == InputSetup.PAIR_NONE, "reset 清掉 RS 冻结")
	r.check(setup.ls_pair() == InputSetup.PAIR_NONE, "reset 之后 ls_pair 回到 PAIR_NONE")
	r.check(not setup.ls_ready(), "reset 之后 ls_ready 为 false")
	r.check(not setup.has_ls_x_sign() and not setup.has_ls_y_sign(),
		"reset 清掉 LS 符号确认")
	r.check(setup.ls_x_sign() == 1 and setup.ls_y_sign() == 1,
		"reset 把 LS 符号退回 +1")
	r.check(not setup.ls_arm_pending(), "reset 清掉未完成的 LS 摆臂")


## 8 根轴的一帧。字典里没写的轴填 `fallback`（默认 0.0）。
func _frame(values: Dictionary, fallback: float = 0.0) -> PackedFloat32Array:
	var frame := PackedFloat32Array()
	frame.resize(AXIS_COUNT)
	for axis in AXIS_COUNT:
		frame[axis] = float(values.get(axis, fallback))
	return frame


func _feed(setup: InputSetup, values: Dictionary, frames: int) -> void:
	for _index in frames:
		setup.observe(_frame(values))


func _hold(setup: InputSetup, axis: int, value: float, frames: int) -> void:
	for _index in frames:
		setup.observe(_frame({axis: value}))


## 单轴从 from 扫到 to：一对手动推杆的完整行程。
func _sweep(setup: InputSetup, axis: int, from_value: float, to_value: float, frames: int) -> void:
	for step in frames + 1:
		var ratio := float(step) / float(frames)
		setup.observe(_frame({axis: lerpf(from_value, to_value, ratio)}))


## 完整的左摇杆夹具：先把轴 0 / 1 各推满 -1..1，再确认两个符号。
##
## 顺序不能倒：`arm_ls_up()` 的基线取当前值，所以必须先推满量程、再推「向上」那一下。
## 所有调用点都必须排在两条 RS `_sweep` 之后 —— `_sweep_ls` 先推轴 0/1，若在 RS
## 冻结之前调用，`_maybe_freeze_rs_pair()` 会把 (0,1) 冻结成 RS，`ls_pair()` 再无
## 非 RS 候选，两个 LS 符号都确认不了，`ls_ready()` 恒假。
func _sweep_ls(setup: InputSetup) -> void:
	_sweep(setup, 0, -1.0, 1.0, 12)
	_sweep(setup, 1, -1.0, 1.0, 12)
	setup.arm_ls_up()
	_feed(setup, {1: -1.0}, 3)
	setup.arm_ls_right()
	_feed(setup, {0: 1.0}, 3)


## LS 轴对已认出、量程已推满，但两个符号都还没确认：用于单独证明符号判定。
func _ls_unconfirmed_setup() -> InputSetup:
	var setup := InputSetup.new()
	_sweep(setup, 2, -1.0, 1.0, 12)
	_sweep(setup, 3, -1.0, 1.0, 12)
	_sweep(setup, 0, -1.0, 1.0, 12)
	_sweep(setup, 1, -1.0, 1.0, 12)
	return setup


## 完整的 D5-1 形态：先 RS 后 LS，两个符号都已确认。
func _ls_ready_setup() -> InputSetup:
	var setup := _ls_unconfirmed_setup()
	_sweep_ls(setup)
	return setup


## 一份「已保存且可用」的档案：四项映射 + 合理校准 + 布局已确认 + range_ready 标记。
##
## 04-11 时期的档案是 `ls = -1`；05 阶段 D-06 之后这样的档案会被 schema v2 与
## `has_ls()` 双重拒绝。这里显式写真实的 LS 轴对与四个 LS 校准字段，代表「新的、
## 可进入练习的档案」，与 `_check_legacy_profile` 里各个旧档案反例形成对照。
static func _stored_profile() -> DeviceProfile:
	var profile := DeviceProfile.new()
	profile.key = "guid:stored"
	profile.device_name = "Stored Pad"
	profile.device_guid = "stored"
	profile.axes = AxisMapping.new()
	profile.axes.rs_x_index = 2
	profile.axes.rs_x_sign = 1
	profile.axes.rs_y_index = 3
	profile.axes.rs_y_sign = 1
	profile.axes.ls_x_index = 0
	profile.axes.ls_y_index = 1
	profile.axes.lt_index = 4
	profile.axes.rt_index = 5
	profile.calibration = Calibration.new()
	profile.calibration.center_x = 0.01
	profile.calibration.center_y = -0.02
	profile.calibration.scale_x = 0.98
	profile.calibration.scale_y = 0.96
	profile.calibration.ls_center_x = 0.0
	profile.calibration.ls_center_y = 0.0
	profile.calibration.ls_scale_x = 0.97
	profile.calibration.ls_scale_y = 0.95
	profile.quality = {
		"range_ready": true, "ls_ready": true, "span_x": 2.0, "span_y": 2.0,
	}
	profile.layout = DeviceProfile.LAYOUT_XBOX
	profile.layout_confirmed = true
	profile.probed_at_iso = "2026-11-05T22:00:00"
	return profile
