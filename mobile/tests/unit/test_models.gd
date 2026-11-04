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
