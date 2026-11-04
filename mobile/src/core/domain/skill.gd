class_name Skill
extends RefCounted

## 一个花式动作规则：与 desktop/padskills/config.py:205-223 的 `Skill` 逐字段同默认值。
##
## 一个文件只能有一个 `class_name`，所以 `Pulse` / `Step` / `Skill` 各自独占文件 ——
## 塞进同一个文件就只能退化成内嵌类，而 `Array[Pulse]` 这类类型化容器是硬需求。
##
## 种类与按钮模式用 StringName 常量，不是 enum：这些值直接来自 JSON、也要出现在错误
## 消息里。造 enum + from_string() 双向表等于维护第二份会漂移的词汇表。
##
## 本类只承载已校验的数据：非法值由 ConfigValidator 拦截并转成 ConfigError，
## 这里不做构造期拒绝、不打印、不做 I/O。

const KIND_ARC := &"arc"
const KIND_SEQUENCE := &"sequence"
const KIND_TAPS := &"taps"
const MODE_ALL := &"all"
const MODE_ANY := &"any"

var name: String = ""
var kind: StringName = &""
var enabled: bool = true
var relative_to_ls: bool = false
var required_buttons: Array[String] = []
var button_mode: StringName = MODE_ALL
var params: Dictionary = {}
## 默认**一条** Pulse，对应 Python 的 `(Pulse(),)`（config.py:215）——不是空数组。
## 空数组会让「没写 rumble 的动作」在移动端完全不震，桌面端却震一下。
var pattern: Array[Pulse] = [Pulse.new()]
var cooldown_ms: int = 400
## 开放 schema：原始配置里未识别的 params 键原样留在这里，不报警告、不丢弃。
## 桌面版的 `Skill.raw` 也是这个语义，改动前先看 config.py:217。
var raw: Dictionary = {}


## 复刻 Python 的 rumble_summary()（config.py:219-223）：两个分支，两种文案。
## 这是用户在设置界面看到的那一行，措辞与小数位数必须与桌面版逐字相同。
func rumble_summary() -> String:
	if pattern.size() == 1:
		var pulse: Pulse = pattern[0]
		return "单震 low=%.2f high=%.2f %dms" % [pulse.low, pulse.high, pulse.duration_ms]
	return "%d 连震" % pattern.size()
