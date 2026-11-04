class_name Buttons
extends RefCounted

## 按键名归一：配置里能写的按键叫法，全部收敛到 17 个规范名。
##
## 逐条照抄 desktop/padskills/input_source.py:35-60（`CANONICAL_BUTTONS` 17 条 +
## `BUTTON_ALIASES` 39 条）。少一条就是某个手柄的某个按键不认，多一条就是自创词汇表；
## 两个条目数都由 mobile/tests/unit/test_vocabulary.gd 硬断言，不是「大概齐」。
##
## 铁律：PlayStation 叫法（L1 归一到 LB、R2 归一到 RT）必须**立刻**归一。禁止把配置里
## 的原始字符串直接和运行时按键比较 —— 那等于维护两套词汇表，两端迟早各说各话。
##
## 失败值是空串，不是异常：GDScript 的运行时错误不可捕获且只中止当前函数，core 层不把
## 错误当控制流。调用方（ConfigValidator）把空串变成带 `json_path` 的 ConfigError，
## 消息里列出可用规范名。core 不打印、不 push_error。

const CANONICAL: Array[String] = [
	"A", "B", "X", "Y",
	"LB", "RB", "LT", "RT",
	"LS", "RS", "BACK", "START", "GUIDE",
	"DPAD_UP", "DPAD_DOWN", "DPAD_LEFT", "DPAD_RIGHT",
]

## 别名 → 规范名。键是「已去空格 / 横线 / 下划线并转大写」之后的形态，
## 所以查表前必须先走 canonical() 的归一步骤，否则带分隔符的写法永远查不到。
const ALIASES := {
	# PlayStation 叫法
	"L1": "LB", "L2": "LT", "L3": "LS",
	"R1": "RB", "R2": "RT", "R3": "RS",
	"CROSS": "A", "CIRCLE": "B", "SQUARE": "X", "TRIANGLE": "Y",
	"SHARE": "BACK", "OPTIONS": "START", "TOUCHPAD": "BACK",
	"LSTICK": "LS", "RSTICK": "RS", "LTHUMB": "LS", "RTHUMB": "RS",
	# Xbox / 通用叫法
	"VIEW": "BACK", "SELECT": "BACK", "CREATE": "BACK",
	"MENU": "START", "PAUSE": "START",
	"HOME": "GUIDE", "PS": "GUIDE", "XBOX": "GUIDE",
	"DUP": "DPAD_UP", "DDOWN": "DPAD_DOWN", "DLEFT": "DPAD_LEFT", "DRIGHT": "DPAD_RIGHT",
	# 去掉下划线 / 横线之后的形态
	"DPADUP": "DPAD_UP", "DPADDOWN": "DPAD_DOWN",
	"DPADLEFT": "DPAD_LEFT", "DPADRIGHT": "DPAD_RIGHT",
	"LEFTSHOULDER": "LB", "RIGHTSHOULDER": "RB",
	"LEFTTRIGGER": "LT", "RIGHTTRIGGER": "RT",
	"LEFTSHOULDERBUTTON": "LB", "RIGHTSHOULDERBUTTON": "RB",
}


## 返回规范名；无法识别时返回空串（core 的约定失败值，由调用方转成 ConfigError）。
static func canonical(value: Variant) -> String:
	var key := str(value).strip_edges().to_upper()
	# 三种分隔符一律剥掉：dpad_up / dpad-up / "dpad up" 都是同一种写法。
	key = key.replace(" ", "")
	key = key.replace("-", "")
	key = key.replace("_", "")
	key = ALIASES.get(key, key)
	# 不在规范表里就是「不认」：返回空串而不是原样返回，避免上层把拼错的串当合法值用。
	return key if key in CANONICAL else ""
