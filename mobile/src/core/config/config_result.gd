class_name ConfigResult
extends RefCounted

## 一次配置加载的完整结果：要么拿到 config，要么拿到一份 errors。
##
## config 只在「没有任何 error」时才非 null —— 半个配置比明确的失败更难查。
## warnings 不阻止启动：它们记录的是「值被安全截断」这类用户应当知道、但不必中断
## 练习的情况（对应桌面版的静默 clamp）。
##
## source_path 记录这次加载的来源（`res://...` / `user://...` / 测试里的 `<test>`），
## 是运行期元数据，不属于 AppConfig。
##
## notice / overrides_applied 留给 03-06 的覆盖层合并：被丢弃时给一次性中文提示。
##
## `to_text()` 是 RESIL-02 的最小机械证明：错误对象自带全部渲染信息，错误屏（Phase 7）
## 拿到的就是这份可以直接逐行显示的数据。

var config: AppConfig = null
var errors: Array[ConfigError] = []
var warnings: Array[ConfigError] = []
var source_path: String = ""
var notice: String = ""
var overrides_applied: bool = false


## 只有「没有 error 且真的产出了配置」才算成功；warning 不影响。
func ok() -> bool:
	return errors.is_empty() and config != null


## 先 errors 后 warnings，每条一行；行数等于问题条数，不额外加标题或空行。
func to_text() -> String:
	var lines := PackedStringArray()
	for error in errors:
		lines.append(error.format_line())
	for warning in warnings:
		lines.append(warning.format_line())
	return "\n".join(lines)


## errors 与 warnings 一起查：测试与调用方不必各自写两遍循环。
func has_code(p_code: StringName) -> bool:
	for error in errors:
		if error.code == p_code:
			return true
	for warning in warnings:
		if warning.code == p_code:
			return true
	return false
