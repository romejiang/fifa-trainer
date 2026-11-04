class_name ConfigError
extends RefCounted

## 一条可原样渲染的配置问题。
##
## 为什么不是「一个字符串」：错误屏（Phase 7）不应该再解析文本或猜字段含义。
## json_path 告诉用户改哪一行，code 给程序判断，message 说清楚哪里不对，fix_hint
## 说清楚怎么改。四项信息由校验器在产生错误的现场填好，UI 不再解释任何东西。
##
## json_path 的写法：根用 `$`，数组元素用 `skills[3]`，对象字段用 `.params.button`
## （拼起来就是 `skills[3].params.button`）。
##
## severity 只有 error 与 warning 两种：error 阻止启动；warning 表示值已被安全截断、
## 配置仍然可用 —— 它对应桌面版里的静默 clamp，移动端把它变成用户看得见的提示。

const SEVERITY_ERROR := &"error"
const SEVERITY_WARNING := &"warning"

var json_path: String = ""
var code: StringName = &""
## 中文，人能看懂；必须含实际收到的值，否则用户不知道该改什么。
var message: String = ""
## 中文，告诉用户改哪里、改成什么；不允许为空串。
var fix_hint: String = ""
var severity: StringName = SEVERITY_ERROR


func _init(p_path: String, p_code: StringName, p_message: String,
		p_fix_hint: String, p_severity: StringName = SEVERITY_ERROR) -> void:
	json_path = p_path
	code = p_code
	message = p_message
	fix_hint = p_fix_hint
	severity = p_severity


## 错误屏 / `to_text()` 的单行形态：`[code] json_path: message（fix_hint）`。
func format_line() -> String:
	return "[%s] %s: %s（%s）" % [code, json_path, message, fix_hint]
