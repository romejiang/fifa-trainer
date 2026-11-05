extends RefCounted

## 词汇表套件：按键别名与方向别名必须和桌面版逐条一致。
##
## 三张表的条目数（17 / 39 / 42）是契约本身，不是实现细节：多一条是自创词汇表，
## 少一条就是某个配置写法在移动端不认。因此第一个断言就是 size()，而不是先测行为。
##
## 失败值的类型必须用 typeof 判定：null 与 0.0 是两种完全不同的结论，用
## `== 0.0` 判 null 会在 null 被强转时静默通过。
##
## 判据全部走 reporter 的 check / eq_float，不用 assert；最后一句必须是 r.complete()。

const TOL := 1e-12


func run(r) -> void:
	_check_table_sizes(r)
	_check_buttons(r)
	_check_directions(r)
	_check_direction_names(r)
	r.complete()


func _check_table_sizes(r) -> void:
	r.check(Buttons.CANONICAL.size() == 17,
		"Buttons.CANONICAL 必须恰好 17 条（实际 %d）" % Buttons.CANONICAL.size())
	r.check(Buttons.ALIASES.size() == 39,
		"Buttons.ALIASES 必须恰好 39 条（实际 %d）" % Buttons.ALIASES.size())
	r.check(DirectionTable.ALIASES.size() == 42,
		"DirectionTable.ALIASES 必须恰好 42 条（实际 %d）" % DirectionTable.ALIASES.size())


func _check_buttons(r) -> void:
	# 四类写法各挑代表：PlayStation 叫法、去分隔符形态、本来就叫规范名、拼错。
	_expect_button(r, "L1", "LB", "PlayStation L1 归一到 LB")
	_expect_button(r, "R2", "RT", "PlayStation R2 归一到 RT")
	_expect_button(r, "TRIANGLE", "Y", "PlayStation 三角归一到 Y")
	_expect_button(r, "CROSS", "A", "PlayStation 叉归一到 A")
	_expect_button(r, "dpad_up", "DPAD_UP", "下划线形态归一到 DPAD_UP")
	_expect_button(r, "LEFTSHOULDERBUTTON", "LB", "SDL 长名归一到 LB")
	_expect_button(r, "A", "A", "规范名原样返回")
	_expect_button(r, "  l1  ", "LB", "前后空白与大小写都要吃掉")
	_expect_button(r, "dpad-up", "DPAD_UP", "横线形态也要归一")
	_expect_button(r, "nope", "", "无法识别的按键返回空串（不是异常、不是原样返回）")
	_expect_button(r, "", "", "空串不是合法按键")

	# 真实配置 shared/skills_config.json 里出现的四种写法：任何一个归一失败，
	# 移动端就有四个动作直接不可用。
	_expect_button(r, "L1", "LB", "真实配置：L1")
	_expect_button(r, "X", "X", "真实配置：X")
	_expect_button(r, "RB", "RB", "真实配置：RB")
	_expect_button(r, "RT", "RT", "真实配置：RT")


func _check_directions(r) -> void:
	# 中英文名称：每个方向至少两种写法，覆盖 42 条表的三类键（英文 / 中文 / 斜向）。
	_expect_angle(r, "前右", 45.0, "中文斜向 前右 = 45°")
	_expect_angle(r, "forward", 0.0, "英文 forward = 0°")
	_expect_angle(r, "RIGHT", 90.0, "大写 RIGHT = 90°（大小写不敏感）")
	_expect_angle(r, "upleft", 315.0, "斜向 upleft = 315°")
	_expect_angle(r, "左", 270.0, "中文 左 = 270°")
	_expect_angle(r, "back-right", 135.0, "带横线形态 back-right = 135°")
	_expect_angle(r, "  forward  ", 0.0, "前后空白要吃掉")

	# 数字写法：整数、负数、超过一圈的浮点都必须落到 [0, 360)。
	_expect_angle(r, 90, 90.0, "整数 90 = 90°")
	_expect_angle(r, -90, 270.0, "负角 -90 归一为 270°")
	_expect_angle(r, 720.5, 0.5, "超过一圈的 720.5 归一为 0.5°")
	_expect_angle(r, "180", 180.0, "字符串数字 \"180\" 也要认")
	# 负号是**分隔符**，不是符号位 —— 这与 Python 的 strip 顺序逐字一致（config.py:129-130）。
	# 想要 270° 就必须写数字 -90（上面那条），写成字符串 "-90" 两端都会得到 90°。
	# 这里刻意把「看起来像 bug 的既有行为」钉死：改成保留负号会让移动端与桌面端对同一份
	# 配置给出 180° 相反的判定，那比这个写法本身更难查。
	_expect_angle(r, "-90", 90.0, "字符串 \"-90\" 的负号按分隔符剥掉（与桌面版一致）")

	# 失败值必须是 null 而不是 0.0：布尔不是方向，拼错的方向名也不是方向。
	_expect_null(r, true, "布尔 true 不是方向")
	_expect_null(r, false, "布尔 false 不是方向")
	_expect_null(r, "clockwisee", "拼错的方向名返回 null")
	_expect_null(r, "", "空串不是方向")
	_expect_null(r, null, "null 不是方向")
	_expect_null(r, {"angle": 90.0}, "字典不是方向")
	_expect_null(r, [90.0], "数组不是方向")


## 角度 -> 中文方向名的边界：八向、22.5° 等距平局、22.6° 落向斜向、
## 超出 22.5° 回落成数字，以及 Step.label() 的多方向连接。
## 这些都是 SequenceDetector 的 `_summary` / `status` 文案的来源，失真会直接
## 表现为「手机上说的方向和电脑不一样」。
func _check_direction_names(r) -> void:
	_expect_name(r, 0.0, "前", "0° = 前")
	_expect_name(r, 45.0, "前右", "45° = 前右")
	_expect_name(r, 90.0, "右", "90° = 右")
	_expect_name(r, 135.0, "后右", "135° = 后右")
	_expect_name(r, 180.0, "后", "180° = 后")
	_expect_name(r, 225.0, "后左", "225° = 后左")
	_expect_name(r, 270.0, "左", "270° = 左")
	_expect_name(r, 315.0, "前左", "315° = 前左")
	_expect_name(r, 360.0, "前", "360 归一为 0°")
	_expect_name(r, -45.0, "前左", "-45 归一为 315°")
	_expect_name(r, 22.5, "前", "22.5° 与 前/前右 等距，取先遇到的「前」（与 Python min 一致）")
	_expect_name(r, 22.6, "前右", "22.6° 更靠近 前右")
	_expect_name(r, 337.5, "前", "337.5° 与 前/前左 等距，取「前」")
	# 计划里写的「30 -> 30°」在参考实现里**不可达**：八个正/斜向间隔 45°，任何角度
	# 到最近卡点的距离都 <= 22.5°，所以 `diff <= 22.5` 恒成立，数字回落是死分支。
	# 这里按 Python 的真实行为钉死 30° = 前右（45° 方向，差 15°）；数字回落分支
	# 仍保留，纯粹为了与 config.py:144-149 逐行对齐。
	_expect_name(r, 30.0, "前右", "30° 距 前右 15°，仍落在 22.5° 内")
	_expect_name(r, 67.5, "前右", "67.5° 与 前右/右 等距，取先遇到的「前右」")

	var two: Array[float] = [90.0, 270.0]
	_expect_label(r, Step.new(two), "右/左", "多方向步用 / 连接")
	var one: Array[float] = [0.0]
	_expect_label(r, Step.new(one), "前", "单方向步直接返回名字")


func _expect_name(r, angle: float, expected: String, label: String) -> void:
	var actual := DirectionTable.direction_name(angle)
	r.check(actual == expected, "%s（实际 %s，期望 %s）" % [label, actual, expected])


func _expect_label(r, step: Step, expected: String, label: String) -> void:
	var actual := step.label()
	r.check(actual == expected, "%s（实际 %s，期望 %s）" % [label, actual, expected])


func _expect_button(r, value: Variant, expected: String, label: String) -> void:
	var actual := Buttons.canonical(value)
	r.check(actual == expected,
		"%s（实际 %s，期望 %s）" % [label, _show(actual), _show(expected)])


func _expect_angle(r, value: Variant, expected: float, label: String) -> void:
	# 先判类型再取浮点：null 一旦被 float() 强转就是运行时错误，会中止整个函数，
	# 后面的断言全部消失，看起来却像「套件跑完了」。
	var actual: Variant = DirectionTable.resolve(value)
	if typeof(actual) != TYPE_FLOAT:
		r.check(false, "%s：期望 %.17f，实际返回 %s（不是 float）"
			% [label, expected, _show(actual)])
		return
	r.eq_float(float(actual), expected, TOL, label)


func _expect_null(r, value: Variant, label: String) -> void:
	var actual: Variant = DirectionTable.resolve(value)
	r.check(typeof(actual) == TYPE_NIL, "%s（实际返回 %s）" % [label, _show(actual)])


func _show(value: Variant) -> String:
	return "<null>" if typeof(value) == TYPE_NIL else str(value)
