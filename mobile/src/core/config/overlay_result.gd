class_name OverlayResult
extends RefCounted

## 覆盖层合并结果：一份可直接校验的配置字典 + 用户需要知道的中文提示。
##
## data 永远是完整字典：整体丢弃时它就是 base 的深拷贝，调用方不需要判断
## 「失败时该拿什么」。把「丢弃」做成返回值而不是异常，是因为配置层不抛错 ——
## 上层用 ok() / notice 决定显示，不需要 try/catch。
##
## warnings 只放「值得告诉用户但不阻止启动」的条目（未知动作名、未知键）。
## 白名单之外的键永远不写进 data：warning 与忽略是同一次操作的两面。
##
## notice 是给用户看的单句中文，Phase 7 的错误屏直接渲染，不在这里拼接上下文；
## discarded_reason 给程序判断（测试与日志用），不面向用户。

var data: Dictionary = {}
var warnings: Array[ConfigError] = []
var applied: bool = false
var discarded_reason: StringName = &""
var notice: String = ""


## 整体丢弃：base 保持原样，只留下原因与一句可直接显示的中文提示。
## 返回 self 是为了让 merge() 里每条早退都能写成一行 return。
func _discard(reason: StringName, p_notice: String) -> OverlayResult:
	discarded_reason = reason
	notice = p_notice
	applied = false
	return self
