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
	var total: int = r.assertions
	r.check(total >= 50, "本套件至少 50 条断言（实际 %d）" % total)
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
	r.check(ready.can_save(), "两轴峰峰值都到 2.0：can_save 为 true")
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
	r.check(profile.axes.ls_x_index == -1 and profile.axes.ls_y_index == -1,
		"本页不映射左摇杆")
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


## 一份「已保存且可用」的档案：四项映射 + 合理校准 + 布局已确认 + range_ready 标记。
##
## 不从 `build_profile()` 构造：保存门要求量程真的推满，而这里要单独证明「档案侧」
## 的复用门 —— 两份数据源分开，任何一个门坏了都会被另一边的用例抓住。
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
	profile.axes.ls_x_index = -1
	profile.axes.ls_y_index = -1
	profile.axes.lt_index = 4
	profile.axes.rt_index = 5
	profile.calibration = Calibration.new()
	profile.calibration.center_x = 0.01
	profile.calibration.center_y = -0.02
	profile.calibration.scale_x = 0.98
	profile.calibration.scale_y = 0.96
	profile.quality = {"range_ready": true, "span_x": 2.0, "span_y": 2.0}
	profile.layout = DeviceProfile.LAYOUT_XBOX
	profile.layout_confirmed = true
	profile.probed_at_iso = "2026-11-05T22:00:00"
	return profile
