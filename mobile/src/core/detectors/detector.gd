class_name Detector
extends RefCounted

## 识别器基类：与 desktop/padskills/detectors.py:61-118 的契约逐条对齐。
##
## GDScript 没有可捕获的 NotImplementedError，也没有 abstract：基类方法返回 null /
## 空串，子类覆盖。契约写在文档里，不靠运行时抛错 —— core 层不把错误当控制流。
##
## 失败是**单槽覆盖写**（`_pending`），不是队列：每个终结路径都会立刻 return，
## 一次 update() 最多走到 `_emit` 一次；万一上一条还没被取走，新的直接覆盖，
## 因为新的这次更相关。
##
## `on_idle()` 在基类里调 `reset()`；TapDetector 必须覆盖成**空实现**——引擎在
## 右摇杆静止时会周期性调用它，而按键动作与右摇杆无关。

## 给失败统计用的中文短标签：整表移植（detectors.py:65-76），即使本阶段只用到 3 个。
const FAILURE_LABELS := {
	&"too_fast": "太快",
	&"too_slow": "太慢",
	&"too_short": "转得不够",
	&"overshoot": "转多了",
	&"wrong_start": "起点不对",
	&"wrong_end": "终点不对",
	&"wrong_direction": "方向反了",
	&"stalled": "中途停住",
	&"incomplete": "没做完",
	&"hold_short": "保持不够",
}

var _pending: Failure = null


## 唯一推进判定的入口：返回 Hit 或 null；失败进 `_pending`。
func update(_frame: Frame) -> Hit:
	return null


## 修饰键松开等情况下强制归零。
func reset() -> void:
	pass


## 右摇杆已安静足够久，作废所有未完成的进度。
func on_idle() -> void:
	reset()


## 这次手势其实属于别的动作：丢掉进度，并且等摇杆回中再重新武装。
##
## 与 reset() 的区别：reset() 是「修饰键松了」这种可立刻重试的情况；
## abandon() 是「这一段轨迹已经被别的动作认领了」，绝不能半路重新起手。
func abandon() -> void:
	_pending = null
	reset()


## 只记下这一帧的状态，供 status() 提示用；不推进任何判定。
func observe(_frame: Frame) -> void:
	pass


## 取出并清空一次失败裁定（一次尝试最多一条）。
func pop_failure() -> Failure:
	var failure: Failure = _pending
	_pending = null
	return failure


## 每个终结路径都会立刻 return，所以一次 update() 里最多 emit 一次。
func _emit(failure: Failure) -> void:
	_pending = failure


## 给 --trace / GUI 用的实时状态摘要。
func status() -> String:
	return ""
