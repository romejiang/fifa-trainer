class_name Frame
extends RefCounted

## 检测器输入的最小单位：一帧采样。
##
## 检测器**只准读**这五项：`now` / `buttons` / `rs_mag` / `rs_angle` / `facing`
## （对应 desktop/padskills/detectors.py:27-37 的 `Frame` 去掉 `state`）。多出来的
## `ls_mag` / `ls_angle` 只给引擎算 `facing` 用，检测器直接读它们会让「相对朝向」
## 的基准来源出现第二个真源。
##
## `facing` 是**引擎每帧写入**的状态：左摇杆推过 `ls_facing_threshold` 时更新为
## `ls_angle`。调用方自己填进 `Frame.facing` 的值会被引擎覆盖，检测器只消费结果。
##
## `now` 的单位是**秒**（float）：与参考实现一致，`elapsed_ms` 由
## `(now - t0) * 1000.0` 现场换算。core 不读时钟，时间轴一律由调用方注入。
##
## `buttons` 是 canonical 名 → true 的字典，例如 `{"RB": true}`。用字典而不是
## `Array[String]`：参考实现是 frozenset，逐帧 `button in buttons` 必须是 O(1)；
## 全仓只能有一种表示（见 mobile/docs/CORE.md）。
##
## 五个新增字段全部带默认值，所以 Phase 4 的 `Frame.new()` + 只赋 `now`/`buttons`
## 的写法继续编译、继续通过 —— 不写 `state` / `ls_*` 给检测器，是这一层的边界。

var now: float = 0.0
var buttons: Dictionary = {}
var rs_mag: float = 0.0
var rs_angle: float = 0.0
var ls_mag: float = 0.0
var ls_angle: float = 0.0
var facing: float = 0.0
