extends RefCounted

## 域对象套件：六个纯数据对象的默认值必须与 desktop/padskills/config.py 逐字段相同。
##
## 为什么默认值也要断言：缺字段的配置在桌面端能用、在移动端报错（或反之）是最难查的
## 一类「对等」问题 —— 它不会崩，只会让同一个动作在两端表现不同。所以每个字段一个断言，
## 不写「大概对」的聚合判断。
##
## 为什么数组复制语义也要断言：GDScript 的数组是引用类型，`Step.angles` 或
## `AppConfig.enabled_skills()` 一旦泄漏内部引用，下游一次 append 就能改到配置本身。
##
## 判据全部走 reporter 的 check / eq_float，不用 assert；最后一句必须是 r.complete()。

const TOL := 1e-12


func run(r) -> void:
	_check_pulse(r)
	_check_step(r)
	_check_skill(r)
	_check_input_config(r)
	_check_rumble_config(r)
	_check_app_config(r)
	r.complete()


func _check_pulse(r) -> void:
	var pulse := Pulse.new()
	r.eq_float(pulse.low, 0.8, TOL, "Pulse.low 默认 0.8")
	r.eq_float(pulse.high, 0.0, TOL, "Pulse.high 默认 0.0")
	r.check(pulse.duration_ms == 120, "Pulse.duration_ms 默认 120（实际 %d）" % pulse.duration_ms)
	r.check(pulse.gap_ms == 0, "Pulse.gap_ms 默认 0（实际 %d）" % pulse.gap_ms)

	var custom := Pulse.new(0.3, 0.6, 40, 10)
	r.eq_float(custom.low, 0.3, TOL, "Pulse(low) 显式赋值")
	r.eq_float(custom.high, 0.6, TOL, "Pulse(high) 显式赋值")
	r.check(custom.duration_ms == 40, "Pulse(duration_ms) 显式赋值（实际 %d）" % custom.duration_ms)
	r.check(custom.gap_ms == 10, "Pulse(gap_ms) 显式赋值（实际 %d）" % custom.gap_ms)


func _check_step(r) -> void:
	var step := Step.new([0.0, 180.0], 350.0)
	r.check(step.angles.size() == 2, "Step.angles 长度 2（实际 %d）" % step.angles.size())
	r.eq_float(step.hold_ms, 350.0, TOL, "Step.hold_ms 显式赋值")

	# 复制语义：构造之后改调用方的数组，不能穿透进 Step 内部。
	var source: Array[float] = [90.0]
	var copied := Step.new(source)
	source.append(270.0)
	r.check(copied.angles.size() == 1,
		"Step 必须复制入参数组（调用方 append 后实际长度 %d）" % copied.angles.size())
	r.eq_float(copied.angles[0], 90.0, TOL, "Step 复制后保留原值")


func _check_skill(r) -> void:
	var skill := Skill.new()
	r.check(skill.name == "", "Skill.name 默认空串（实际 %s）" % skill.name)
	r.check(skill.kind == &"", "Skill.kind 默认空 StringName（实际 %s）" % str(skill.kind))
	r.check(skill.enabled == true, "Skill.enabled 默认 true")
	r.check(skill.relative_to_ls == false, "Skill.relative_to_ls 默认 false")
	r.check(skill.required_buttons.is_empty(), "Skill.required_buttons 默认空数组")
	r.check(skill.button_mode == Skill.MODE_ALL, "Skill.button_mode 默认 MODE_ALL")
	r.check(skill.params.is_empty(), "Skill.params 默认空字典")
	r.check(skill.cooldown_ms == 400, "Skill.cooldown_ms 默认 400（实际 %d）" % skill.cooldown_ms)
	r.check(skill.raw.is_empty(), "Skill.raw 默认空字典")

	# pattern 默认是一条 Pulse，不是空数组 —— 对应 Python 的 (Pulse(),)（config.py:215）。
	r.check(skill.pattern.size() == 1, "Skill.pattern 默认一条 Pulse（实际 %d 条）" % skill.pattern.size())
	var default_pulse: Pulse = skill.pattern[0]
	r.eq_float(default_pulse.low, 0.8, TOL, "默认 Pulse.low")
	r.eq_float(default_pulse.high, 0.0, TOL, "默认 Pulse.high")
	r.check(default_pulse.duration_ms == 120, "默认 Pulse.duration_ms")
	r.check(default_pulse.gap_ms == 0, "默认 Pulse.gap_ms")
	# 成员初始化器每个实例各建一条：两个 Skill 的默认 pattern 不能是同一个对象。
	var other := Skill.new()
	r.check(other.pattern[0] != skill.pattern[0], "两个 Skill 的默认 Pulse 必须是各自独立的实例")

	# rumble_summary()：默认即单震、显式单条同文案、两条走「连震」分支。
	r.check(skill.rumble_summary() == "单震 low=0.80 high=0.00 120ms",
		"默认 pattern 的 rumble_summary（实际 %s）" % skill.rumble_summary())
	var single := Skill.new()
	single.pattern = [Pulse.new(0.8, 0.0, 120)]
	r.check(single.rumble_summary() == "单震 low=0.80 high=0.00 120ms",
		"显式单条 Pulse 的 rumble_summary（实际 %s）" % single.rumble_summary())
	var double := Skill.new()
	double.pattern = [Pulse.new(0.5, 0.0, 60), Pulse.new(0.5, 0.0, 60)]
	r.check(double.rumble_summary() == "2 连震",
		"两条 Pulse 的 rumble_summary（实际 %s）" % double.rumble_summary())


func _check_input_config(r) -> void:
	# 12 个字段逐个断言 —— 漏一个就等于有一个默认值没人钉住。
	var cfg := InputConfig.new()
	r.check(cfg.poll_hz == 250, "InputConfig.poll_hz 默认 250（实际 %d）" % cfg.poll_hz)
	r.eq_float(cfg.deadzone, 0.08, TOL, "InputConfig.deadzone 默认 0.08")
	r.eq_float(cfg.ls_facing_threshold, 0.35, TOL, "InputConfig.ls_facing_threshold 默认 0.35")
	r.eq_float(cfg.initial_facing_deg, 0.0, TOL, "InputConfig.initial_facing_deg 默认 0.0")
	r.eq_float(cfg.trigger_threshold, 0.35, TOL, "InputConfig.trigger_threshold 默认 0.35")
	r.check(cfg.joystick_index == 0, "InputConfig.joystick_index 默认 0（实际 %d）" % cfg.joystick_index)
	r.check(typeof(cfg.axis_layout) == TYPE_NIL,
		"InputConfig.axis_layout 默认 null（不是空字典；实际 %s）" % str(cfg.axis_layout))
	r.check(cfg.invert.is_empty(), "InputConfig.invert 默认空字典")
	r.check(typeof(cfg.button_names) == TYPE_NIL,
		"InputConfig.button_names 默认 null（不是空字典；实际 %s）" % str(cfg.button_names))
	r.check(cfg.calibration_ms == 250, "InputConfig.calibration_ms 默认 250（实际 %d）" % cfg.calibration_ms)
	r.check(cfg.idle_reset_ms == 250, "InputConfig.idle_reset_ms 默认 250（实际 %d）" % cfg.idle_reset_ms)
	r.check(cfg.gesture_release_ms == 150,
		"InputConfig.gesture_release_ms 默认 150（实际 %d）" % cfg.gesture_release_ms)


func _check_rumble_config(r) -> void:
	var cfg := RumbleConfig.new()
	r.check(cfg.enabled == true, "RumbleConfig.enabled 默认 true")
	r.check(cfg.backend == &"auto", "RumbleConfig.backend 默认 auto（实际 %s）" % str(cfg.backend))
	r.check(cfg.startup_test == true, "RumbleConfig.startup_test 默认 true")
	r.eq_float(cfg.startup_test_strength, 0.55, TOL, "RumbleConfig.startup_test_strength 默认 0.55")
	r.check(cfg.startup_test_ms == 160, "RumbleConfig.startup_test_ms 默认 160（实际 %d）" % cfg.startup_test_ms)


func _check_app_config(r) -> void:
	var app := AppConfig.new()
	r.check(app.global_cooldown_ms == 60,
		"AppConfig.global_cooldown_ms 默认 60（实际 %d）" % app.global_cooldown_ms)
	r.check(app.skills.is_empty(), "AppConfig.skills 默认空数组")
	r.check(app.input != null, "AppConfig.input 必须是 InputConfig 实例")
	r.check(app.rumble != null, "AppConfig.rumble 必须是 RumbleConfig 实例")

	# enabled_skills()：过滤掉 disabled，且返回的必须是副本。
	app.skills.append(_named_skill("第一个", true))
	app.skills.append(_named_skill("第二个", true))
	app.skills.append(_named_skill("第三个", false))
	var enabled := app.enabled_skills()
	r.check(enabled.size() == 2, "enabled_skills() 只保留 enabled 的两条（实际 %d）" % enabled.size())
	r.check(enabled[0].name == "第一个" and enabled[1].name == "第二个",
		"enabled_skills() 保持原有顺序并跳过 disabled")
	# 清空返回值不能影响 AppConfig 内部的 skills —— 泄漏引用的典型症状。
	enabled.clear()
	r.check(app.skills.size() == 3,
		"enabled_skills() 必须返回新数组（清空返回值后内部仍有 %d 条）" % app.skills.size())


func _named_skill(skill_name: String, is_enabled: bool) -> Skill:
	var skill := Skill.new()
	skill.name = skill_name
	skill.enabled = is_enabled
	return skill

