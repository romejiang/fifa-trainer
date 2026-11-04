class_name AppConfig
extends RefCounted

## 一份完整配置：与 desktop/padskills/config.py:253-262 的 `AppConfig` 对齐（除 `path`）。
##
## 没有 `path` 字段：Godot 里没有 pathlib，来源路径属于「这次加载从哪来」的运行期元数据，
## 由 ConfigResult.source_path 承载（03-04）。域对象只描述配置本身，不记录 I/O 痕迹。
##
## 本类只承载已校验的数据：校验由 ConfigValidator 做完，调用方拿到的 AppConfig 一定合法。

var input := InputConfig.new()
var rumble := RumbleConfig.new()
var skills: Array[Skill] = []
var global_cooldown_ms: int = 60


## 返回**新数组**：调用方改它（append / clear）不能改到 AppConfig 内部。
## 与 Python 的列表推导 `[s for s in self.skills if s.enabled]` 语义相同，只是 GDScript
## 的数组是引用类型，必须显式收集而不能直接返回 skills。
func enabled_skills() -> Array[Skill]:
	var out: Array[Skill] = []
	for skill in skills:
		if skill.enabled:
			out.append(skill)
	return out
