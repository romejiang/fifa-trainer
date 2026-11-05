class_name Frame
extends RefCounted

## 检测器输入的最小单位：一帧采样。
##
## 只有两个字段，因为 TapDetector 只读 `now` 与 `buttons`
## （desktop/padskills/detectors.py:917-918、950-952、959）。左/右摇杆与 facing 在
## Phase 5 移植 arc / sequence 时再加，不要提前造 —— 多出来的字段没人读，只会让
## 「core 只承载判定真正需要的数据」这条边界先烂掉。
##
## `now` 的单位是**秒**（float）：与参考实现一致，`elapsed_ms` 由
## `(now - t0) * 1000.0` 现场换算。core 不读时钟，时间轴一律由调用方注入。
##
## `buttons` 是 canonical 名 → true 的字典，例如 `{"RB": true}`。用字典而不是
## `Array[String]`：参考实现是 frozenset，逐帧 `button in buttons` 必须是 O(1)；
## 全仓只能有一种表示（见 mobile/docs/CORE.md）。

var now: float = 0.0
var buttons: Dictionary = {}
