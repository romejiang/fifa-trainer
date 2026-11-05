class_name Outcome
extends RefCounted

## 一次尝试的最终判定（成功或失败），对齐 desktop/padskills/engine.py:62-76 的 `Outcome`。
##
## 与 Python 的差别只有一处：多一个 `seq`。移动端的结果入口是
## `TapRuntime.pop_outcomes()` 的**队列**，不是 `last_outcome` 单槽；`seq` 让 UI 能在
## 同帧多条的情况下稳定排序，也让测试能断言「没有结果被覆盖」。
##
## `at` 与 `seq` 都由 `TapRuntime` 写入：`at` 是引擎时间轴上的秒（与 `Frame.now` 同一
## 口径），`seq` 从 1 开始单调递增。`Outcome` 自身不读时钟、不校验、不提供 getter ——
## 它是纯数据，和 `ConfigResult` 一样「公开字段 + 无访问器」。
##
## `detail` 在成功时是检测器给的 `Hit.summary`（Python 的 `_record(... detail=hit.summary)`），
## 失败时为空串。UI 只显示，不重新拼装。

var skill_name: String = ""
var ok: bool = false
var code: StringName = &""
var message: String = ""
var elapsed_ms: float = 0.0
var at: float = 0.0
var detail: String = ""
var seq: int = 0
