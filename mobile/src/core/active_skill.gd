class_name ActiveSkill
extends RefCounted

## 一个参与判定的动作：技能规则 + 活着的检测器 + 逐动作运行期计数。
##
## 与 desktop/padskills/engine.py:78-89 的 `ActiveSkill` 逐字段对齐。为什么必须
## 单独成类：`hits` / `attempts` / `failures` / `last_fire` 都是**按动作分别累计**
## 的，塞进引擎的三个平行字典会让「取第 i 个动作的进度」变成三处下标同步。
##
## `last_fire` 的 `-1e9` 是刻意的（照抄 engine.py:82）：它让第一发永远不受逐动作
## 冷却限制。换成 `0.0` 会让 `now - 0` 在启动后的头 400ms 里把第一发吞掉。
##
## `failures` 用 `Dictionary`（失败码 → 次数），失败码是 `StringName` 的字符串形态：
## 只给统计用，不参与判定。
##
## `last_outcome` 是「这个动作最近一次结果」的只读快照；结果队列的真源在
## `GestureEngine._outcomes`。两者不是二选一：GUI 的逐动作卡片读前者，结果横幅读
## 后者。

var skill: Skill = null
var detector: Detector = null
## 第一发永远不受冷却限制（见类文档）。
var last_fire: float = -1e9
var hits: int = 0
var attempts: int = 0
var group_hits: int = 0
var groups_done: int = 0
var failures: Dictionary = {}
var last_outcome: Outcome = null


func _init(p_skill: Skill, p_detector: Detector) -> void:
	skill = p_skill
	detector = p_detector
