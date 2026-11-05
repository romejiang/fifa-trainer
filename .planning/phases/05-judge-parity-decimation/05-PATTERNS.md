# Phase 5: 全动作判定对等性 — Pattern Map

**Mapped:** 2026-11-06
**Files analyzed:** 34（新建 16 / 修改 18，含生成物）
**Analogs found:** 31 / 34（3 个无真实前例，见 §No Analog Found）

> 所有引用的 analog 均已用 `git ls-files -- <path>` 验证为 **git 跟踪源码**；本文件不引用任何 gitignore 的安装镜像（如 `mobile/.godot/`）。
> `design/` 是用户未跟踪的工作区，本阶段**零引用、零改动**。

---

## 0. 计划者必须先钉住的五条硬闸门（RESEARCH §Recommendations）

每条都要在 PLAN 的验收段里逐字出现，且都要有可执行命令：

| # | 闸门 | 命令 | 判据 |
|---|------|------|------|
| G1 | 桌面零回归 | `bash tools/check_desktop.sh` | 「302 项检查全部通过」；本阶段**禁止**改 `desktop/padskills/*.py`（`check_desktop.sh:2` 与 `:15` 的基线 SHA 会同时抓住改测试与改基线） |
| G2 | 移动端套件只增不减 | `bash mobile/tools/test-core.sh` | `TESTS_DONE failures=0` 且 `TESTS_ASSERTIONS` **严格 > 1533** |
| G3 | 四条新哨兵 | 见 §Shared Patterns / 哨兵 | `GESTURE_GOLDEN` / `GESTURE_RUNTIME` / `MEASURED` / `DECIMATION` 全部 `mismatches=0` 且 `cases` 达下限（84 / 29 / N / 252） |
| G4 | core 纯度 | `python3 tools/lint_core_purity.py mobile/src/core` | `LINT_OK files=N`；14 条禁用 token 见 `tools/lint_core_purity.py:47-64` |
| G5 | 真机证据 | D5-2 / D5-3 的 `OUTCOME` 日志行 + `adb exec-out screencap` | D5-8 未执行时**不得**声称 INPUT-01 完整 |

补充口径：
- JUDGE-03 的「230 项」是 Phase 1 的历史数字；当前基线是 **302**（205 + 97，RESEARCH E3）。计划里写「以 205 项检测器/引擎断言表达的 127 条可移植行为为移植口径」。
- **夹具位置冲突裁决**：RESEARCH §B.3 写 `shared/golden_detector.json` / `shared/golden_engine.json`，05-VALIDATION 写 `mobile/tests/fixtures/gesture_golden.json`。采用 VALIDATION 的位置 + `shared/golden_decimated.json`，理由是有既有先例与书面理由：`tools/gen_geometry_golden.py:11-14` 明确写过「夹具不放 shared/，唯一消费者是 mobile/tests，放 shared 会逼出第二次同步」。检测器与引擎用例合成**一份** `gesture_golden.json`、用 `kind` 区分，正是 `tap_golden.json` 的现状（`tools/gen_tap_golden.py:602`、`mobile/tests/unit/test_tap_detector.gd:84-89`、`test_tap_runtime.gd:121-126`）。
- 抽稀夹具留在 `shared/`：它是 `decimate_trace.py` 的输出、且被 Python 重放消费，两边都是消费者。

---

## File Classification

| # | New/Modified File | Wave | Role | Data Flow | Closest Analog | Match Quality |
|---|-------------------|:----:|------|-----------|----------------|---------------|
| 1 | `tools/gen_gesture_golden.py` | 1 | tool / generator | batch / transform | `tools/gen_tap_golden.py` | exact |
| 2 | `mobile/tests/fixtures/gesture_golden.json` | 1-3 | fixture（生成物） | batch | `mobile/tests/fixtures/tap_golden.json` | exact |
| 3 | `mobile/src/core/frame.gd`（改：+5 字段） | 2 | model | streaming（逐帧） | 自身 + `desktop/padskills/detectors.py:27-37` | exact |
| 4 | `mobile/src/core/hit.gd`（改：+`measured`） | 2 | model | event-driven | 自身 | exact |
| 5 | `mobile/src/core/failure.gd`（改：+`measured`） | 2 | model | event-driven | 自身 | exact |
| 6 | `mobile/src/core/domain/step.gd`（改：+`label()`） | 2 | model | transform | `desktop/padskills/config.py:162-163` | role-match |
| 7 | `mobile/src/core/domain/direction_table.gd`（改：+`direction_name()`） | 2 | utility | transform | `desktop/padskills/config.py:116-149` | role-match |
| 8 | `mobile/src/core/detectors/arc_detector.gd` | 2 | detector（状态机） | streaming | 风格：`mobile/src/core/detectors/tap_detector.gd`；语义：`desktop/padskills/detectors.py:125-446` | role-match + 语义 exact |
| 9 | `mobile/src/core/detectors/sequence_detector.gd` | 2 | detector（状态机） | streaming | 同上 + `detectors.py:453-853` | role-match + 语义 exact |
| 10 | `mobile/src/core/detectors/build_detector.gd` | 2 | factory | request-response | `detectors.py:1039-1046` | partial（无 GDScript 前例） |
| 11 | `mobile/src/core/active_skill.gd` | 3 | model / runtime | event-driven | `desktop/padskills/engine.py:78-89` | role-match |
| 12 | `mobile/src/core/gesture_engine.gd` | 3 | service（引擎） | streaming | `mobile/src/core/tap_runtime.gd` + `engine.py:92-452` | role-match（唯一可用前例） |
| 13 | `mobile/src/core/tap_runtime.gd`（改：改为子类） | 3 | service | streaming | 自身 | exact |
| 14 | `mobile/src/core/outcome.gd`（改：+`measured`） | 3 | model | event-driven | 自身 + `engine.py:62-76` | exact |
| 15 | `tools/decimate_trace.py` | 4 | tool | batch / transform | `tools/gen_geometry_golden.py` + `tools/check_config_parity.py` | exact（骨架） |
| 16 | `shared/golden_decimated.json` | 4 | fixture（生成物） | batch | `mobile/tests/fixtures/geometry_golden.json` | role-match |
| 17 | `shared/decimation_allowlist.json` | 4 | config | batch | 无（首个白名单）；格式参考 `config_corpus.json` 的 `divergence` 双向规则 | partial |
| 18 | `mobile/src/core/device/calibration.gd`（改：+LS 四字段） | 5 | model | transform | 自身 | exact |
| 19 | `mobile/src/core/device/axis_mapping.gd`（改：+`snapshot_ls()`） | 5 | model | transform | 自身 `snapshot_rs()` | exact |
| 20 | `mobile/src/core/input_setup.gd`（改：LS 对/符号/量程） | 5 | domain service | streaming | 自身 | exact |
| 21 | `mobile/src/core/device/device_profile.gd`（改：schema v2 + `ls_ready`） | 5 | model | request-response | 自身 `_range_ready_marker()` | exact |
| 22 | `mobile/src/ui/input_setup_screen.gd`（改：LS 两行 + 向上推提示） | 5 | UI | request-response | 自身 | exact |
| 23 | `mobile/src/ui/main.gd`（改：Frame 组装 + 引擎 + drain 语义） | 6 | composition root | event-driven | 自身 | exact |
| 24 | `mobile/src/ui/practice_screen.gd`（改：OUTCOME 日志 + 横幅动作名） | 6 | UI | event-driven | 自身 | exact |
| 25 | `mobile/src/ui/result_banner.gd`（改：显示 `skill_name`） | 6 | UI | event-driven | 自身 | exact |
| 26 | `mobile/src/input/input_log.gd`（改：+`outcome()` 行） | 6 | utility | file-I/O | 自身 | exact |
| 27 | `tools/analyze_input_log.py` | 6 | tool | transform | `tools/check_config_parity.py` | role-match |
| 28 | `mobile/tests/unit/test_gesture_detector.gd` | 2 | test | batch replay | `mobile/tests/unit/test_tap_detector.gd` | exact |
| 29 | `mobile/tests/unit/test_gesture_engine.gd` | 3 | test | batch replay | `mobile/tests/unit/test_tap_runtime.gd` | exact |
| 30 | `mobile/tests/unit/test_measured.gd` | 3 | test | batch / assertions | `test_tap_runtime.gd` 的结构断言段 | role-match |
| 31 | `mobile/tests/unit/test_decimation.gd` | 4 | test | batch replay | `test_tap_detector.gd` + `test_geometry.gd` | exact |
| 32 | `mobile/tests/unit/test_practice_wiring.gd` | 6 | test | integration（无头） | `mobile/tests/unit/test_green_slice.gd` | role-match |
| 33 | `mobile/tests/unit/test_input_setup.gd` / `test_device_profile.gd`（改） | 5 | test | batch / assertions | 自身 | exact |
| 34 | `mobile/tools/test-core.sh`（改：+4 grep） / `mobile/tests/core_runner.gd`（改：+SUITES） | 2-6 | CI gate / config | — | 自身 | exact |

---

## Pattern Assignments

### 1. `tools/gen_gesture_golden.py`（tool / batch，Wave 1）

**Analog:** `tools/gen_tap_golden.py`（结构逐字照抄，用例表换成语料）

**文件头与路径锚**（`gen_tap_golden.py:25-57`）——`sys.path` 以脚本位置为锚，绝不依赖调用方 cwd：

```python
from __future__ import annotations

import argparse
import hashlib
import io
import json
import sys
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_REPO_ROOT / "desktop"))

from padskills.config import parse_config  # noqa: E402
from padskills.detectors import Frame, TapDetector  # noqa: E402
from padskills.engine import Engine  # noqa: E402
from padskills.input_source import GamepadSource, PadState, canonical_button  # noqa: E402
from padskills.rumble import RumbleEngine  # noqa: E402

STEP_MS = 4
HZ = 250
SKILL_NAME = "绿色搓射 Green Finesse"

CONFIG_REL = Path("shared") / "skills_config.json"
FIXTURE_REL = Path("mobile") / "tests" / "fixtures" / "tap_golden.json"
```

**源哈希表**（`gen_tap_golden.py:50-57`）——四个文件缺一不可；改一行注释也会触发重生成，这是设计意图：

```python
SOURCE_RELS = {
    "detectors": Path("desktop") / "padskills" / "detectors.py",
    "engine": Path("desktop") / "padskills" / "engine.py",
    "config": Path("desktop") / "padskills" / "config.py",
    "skills_config": CONFIG_REL,
}
```

**参考引擎的两块脚手架**（`gen_tap_golden.py:379-400`）——Phase 5 直接复用，改成收集全部 Outcome：

```python
class _NullSource(GamepadSource):
    """只用于构造引擎；生成器直接手工喂 `_tick`，`poll()` 永不被调用。"""

    name = "空手柄"
    layout_source = "测试"

    def poll(self) -> PadState:
        return PadState()


class _CollectingEngine(Engine):
    """把**全部** Outcome 收集起来；只看 `last_outcome` 会漏掉中间结果。"""

    collected: list

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.collected = []

    def _record(self, active, ok, code, message, elapsed_ms, now, detail=""):
        super()._record(active, ok, code, message, elapsed_ms, now, detail)
        self.collected.append(self.last_outcome)
```

**单帧驱动入口**（`gen_tap_golden.py:553-562`）——`Engine.run()` 是墙钟循环，**绝不能**用于夹具：

```python
def _drive_runtime(cfg, frames: list, case_id: str):
    """用 `Engine._tick` 逐帧驱动参考引擎，收集**全部** Outcome 与 taps 计数。

    不跑 `Engine.run()`：那是 250 Hz 墙钟循环，夹具需要的是确定性的注入时间轴。
    """
    engine = _CollectingEngine(
        cfg, _NullSource(), RumbleEngine(None, enabled=False), out=io.StringIO()
    )
```

**payload / 规范字节 / 只读校验 / main**（`gen_tap_golden.py:622-652`、`:681-709`、`:722-749`）：

```python
return {
    "schema_version": 1,
    "source": {
        **{name: rel.as_posix() for name, rel in SOURCE_RELS.items()},
        "sha256": {name: _sha256(root, rel) for name, rel in SOURCE_RELS.items()},
    },
    "meta": {"hz": HZ, "step_ms": STEP_MS, "skill": skill.name},
    "cases": detector_cases + runtime_cases,
}
```

```python
def render(root: Path) -> bytes:
    payload = build_payload(root)
    text = json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    return text.encode("utf-8")
```

```python
def check(root: Path) -> int:
    """只读校验：重新推导后与磁盘夹具逐字节比较，绝不写盘。"""
```

**必须扩展的六条（RESEARCH §B.6，缺一条 0 差异就是假的）：**

1. 每条用例带 `config: "shipped" | "variant:<name>"`，`variant()` 只改一个技能的 params（与桌面 `test_arc_direction` 同构）。
2. `frames` 形状 `[t_ms, rs_angle, rs_mag, [buttons...], facing]`；`facing` 是**期望值**，生成器必须断言 `abs(engine.facing - facing) < 1e-9`（B.4 规则 4）。
3. 每个会被 `%.0f` 格式化的实测值（`swept` / `end_rel` / `elapsed_ms` / `held_ms` / `interval_ms`）距最近的 `.5` ≥ 1e-6，否则 `SystemExit`。
4. id 唯一（`gen_tap_golden.py:628-632` 已有先例）。
5. 数量下限常量写死（检测器 ≥ 50、引擎 ≥ 26），GDScript 侧先断言 `size()` 再回放。
6. 每组至少一条反向对照（absolute 模式不触发 / LS 回中零判定）。

**不要照抄的部分：** `_drive`（`gen_tap_golden.py:472-526`）是 tap 专用；arc/sequence 一律走 `_tick`。

---

### 2. `mobile/src/core/frame.gd`（改，model，Wave 2）

**Analog:** 自身 + `desktop/padskills/detectors.py:27-37`

**现状**（`frame.gd:1-19`）——两个字段、类文档已经把扩展条件写死：

```gdscript
class_name Frame
extends RefCounted

var now: float = 0.0
var buttons: Dictionary = {}
```

**目标形状**（`detectors.py:27-37` 的八字段去掉 `state`）：`now` / `buttons` / `rs_mag` / `rs_angle` / `ls_mag` / `ls_angle` / `facing`。新增五个全部默认 `0.0`，Phase 4 的 `Frame.new()` + 只赋 `now`/`buttons` 的写法因此零改动（`tap_runtime` 的 1533 条断言靠这一条继续通过）。

**必须写进类文档的两条纪律：**
- 检测器**只准**读 `now / buttons / rs_mag / rs_angle / facing`（`detectors.py` 里 `frame.` 的全部命中，RESEARCH E4）。
- `facing` **由引擎每帧写入**，调用方传进来的值会被覆盖；`ls_mag/ls_angle` 只给引擎算 `facing`。
- 保留「`buttons` 是 canonical 名 → true 的字典」这条唯一表示（`frame.gd:14-16`），不要换 `Array[String]`。

---

### 3. `mobile/src/core/hit.gd` / `failure.gd`（改，model，Wave 2）

**Analog:** 自身。两者都是「位置参数 + 无访问器」的纯数据，新增字段只能加在**末尾**并给默认值（`hit.gd:18`、`failure.gd:17`）：

```gdscript
func _init(p_elapsed_ms := 0.0, p_detail := "", p_summary := "") -> void:
```

```gdscript
func _init(p_code: StringName = &"", p_message := "", p_elapsed_ms := 0.0) -> void:
```

改为 `(..., p_measured: Dictionary = {})`。**不要**改成命名参数或字典构造——`tap_detector.gd` 里有 6 处位置调用，Phase 4 的断言全靠它们不动。

`measured` 的纪律（RESEARCH §D.5）：**只能由检测器在产生 `Hit`/`Failure` 的那一刻填**，UI 与日志不得从 `message` 正则抠数字。

---

### 4. `mobile/src/core/detectors/arc_detector.gd`（detector / streaming，Wave 2）

**Analog（风格）：** `mobile/src/core/detectors/tap_detector.gd`
**Analog（语义）：** `desktop/padskills/detectors.py:125-446`

**风格骨架**（`tap_detector.gd:1-16`）——一个 `class_name`、`extends Detector`、类文档先写「逐行移植 + 时间口径 + 状态表示」：

```gdscript
class_name TapDetector
extends Detector

## 按键双击类：按住修饰键，在时间窗口内按两下同一个键。
##
## 逐行移植 desktop/padskills/detectors.py:858-1034。...
##
## 时间口径：`Frame.now` 是秒；`min_ms` / `max_ms` / `grace_ms` / `release_hold_ms`
## 是毫秒。窗口两端**都包含**（`min <= interval <= max`），超时是**严格大于**
## （`interval > max + grace`）。
```

Arc 对应改成：`Frame.now` 秒、`*_ms` 毫秒、`signed_delta` 用 `Geometry`、`exit` 迟滞必须成立。

**构造期**（`detectors.py:134-152`）——比例与默认值逐字照抄：

```python
self.enter = float(p.get("enter_threshold", 0.80))
self.exit = float(p.get("exit_threshold", min(0.60, self.enter)))
if self.exit >= self.enter:
    # 迟滞必须成立，否则会在阈值附近疯狂抖动
    self.exit = max(0.0, self.enter - 0.05)

self.min_angle = float(p.get("min_angle", 150.0))
self.max_angle = float(p.get("max_angle", 220.0))
self.min_ms = float(p.get("min_duration_ms", 300.0))
self.max_ms = float(p.get("max_duration_ms", 700.0))
self.idle_ms = float(p.get("idle_timeout_ms", 180.0))
self.motion_delta = float(p.get("motion_min_delta_deg", 2.0))
```

`max_ms <= min_ms` 在 Python 抛 `ValueError`（`:148-152`）。**GDScript 侧不抛**：`ConfigValidator` 已在校验期拦下同一条件（`config_validator.gd:187-193` 的 arc 分支、`:278-284` 的 sequence 分支都是 `max_not_greater_than_min`），检测器构造只 `maxf` 兜底，不在 core 里把异常当控制流（`detector.gd:5-7` 的既定契约）。

**运行期字段**（`detectors.py:187-209`）：

```python
self.report_min_angle = max(20.0, self.min_angle * 0.35)
...
self.armed = True
self.active = False
self.t0 = 0.0
self.acc = 0.0
self.last_angle = 0.0
self.start_angle = 0.0      # 显示用：起点的绝对角度
self.start_rel = 0.0        # 判定用：起点换算到判定基准后的角度
self.end_rel = 0.0
self.base = 0.0             # 本次动作使用的方向基准，中途不随左摇杆改变
self.samples = 0
self._last_motion = 0.0
self._last_mag = 0.0
self._motion_ref_angle = 0.0
self._release_since: Optional[float] = None
self._path: List[Tuple[float, float, float]] = []
self._last_path_t = -1e9
self._pending: Optional[Failure] = None
self._claimed = False
self._turn_sign = 0
```

GDScript 侧：`_release_since` 必须用**成对表示**（`_have_release_since` + `_release_since`），不能拿 `-1.0` 当哨兵——`tap_detector.gd:15-16` 已把这条写成仓库纪律。`_path` 用 `Array`，元素 `Vector3(t_ms, angle, mag)` 或 `Array[float]` 三连，**上限 64、间隔 ≥ 8 ms**。

**`update()` 的分支顺序**（`detectors.py:246-273`）——顺序即语义，先写「回中收尾」再写起手：

```python
if mag < self.exit:
    was_active = self.active
    if was_active and self._claimed:
        elapsed_ms = (now - self.t0) * 1000.0
        end_rel = norm_deg(self.last_angle - self.base)
        ...
        if swept >= self.report_min_angle:
            failure = self._release_failure(swept, elapsed_ms, end_rel, end_ok)
            if failure is not None:
                self._emit(failure)
    self.active = False
    self.acc = 0.0
    self._turn_sign = 0
    if was_active:
        self.armed = False
    if self._release_since is None:
        self._release_since = now
    if (not self.armed
            and (now - self._release_since) * 1000.0 >= self.release_hold_ms):
        self.armed = True
    return None
```

**起手**（`:279-301`）——`base` 在这里冻结，`_claimed` 由 `start_target ± (start_tolerance + claim_margin)` 决定：

```python
self.start_angle = frame.rs_angle
self.base = frame.facing if self.relative else 0.0
self.start_rel = norm_deg(frame.rs_angle - self.base)
...
self._claimed = (
    self.start_target is None
    or angle_diff(self.start_rel, self.start_target)
    <= self.start_tolerance + self.claim_margin
)
```

**累计与「在动」判据**（`:303-321`）——比的是**冻结参考角**，不是相邻帧；这是 RESEARCH §C.2 判定「`motion_delta` 不需要按采样率重写」的依据：

```python
delta = signed_delta(self.last_angle, frame.rs_angle)
self.acc += delta
self.last_angle = frame.rs_angle
self.samples += 1
# 慢速但持续的旋转也要算"在动"：用累计角度而不是单帧角度判断，
# 否则 250Hz 下每帧只转 1° 左右的慢弧会被误判成停住。
if (angle_diff(self._motion_ref_angle, frame.rs_angle) >= self.motion_delta
        or abs(mag - self._last_mag) >= 0.05):
    self._last_motion = now
    self._motion_ref_angle = frame.rs_angle
self._last_mag = mag
```

**六个 abort 分支的固定顺序**（`:323-404`）——`wrong_start → wrong_direction → overshoot → stalled → too_slow → too_fast → in_range/end_ok → 成功`。源码里已经写明理由：

```python
# 检查顺序按"最能说明问题"排：起点 -> 方向 -> 转多了 -> 停住 -> 太慢 -> 太快。
# 这些分支都会 abort，所以顺序只影响报告哪条原因，不影响是否触发。
```

**`_release_failure()`**（`:220-238`）——只可能两种码；`swept < report_min_angle` 时调用方整条静默（`:258`）：

```python
if swept < self.min_angle:
    return Failure("too_short", ...)
if self.end_targets and not end_ok:
    target = "/".join(f"{t:.0f}°" for t in self.end_targets)
    return Failure("wrong_end", ...)
return None
```

**三套清理语义必须分开**（`:212-218`、`:430-440`）：

```python
def _abort(self) -> None:
    """作废本次画弧，必须等摇杆回落才允许下一次。"""
    self.active = False
    self.armed = False
    self.acc = 0.0
    self._release_since = None
    self._turn_sign = 0

def reset(self) -> None:
    self.active = False
    self.armed = True          # ← 与 _abort 相反
    ...

def abandon(self) -> None:
    self._pending = None
    self._abort()              # ← 不能继承基类的 abandon()（基类会调 reset()）
```

> **移植陷阱：** `detector.gd:52-54` 的基类 `abandon()` 是 `_pending = null; reset()`。Arc/Sequence 在桌面**各自覆盖** `abandon()`（`detectors.py:438-440`、`:804-806`）走 `_abort()`。照抄基类会把「这段轨迹被别的动作认领」变成「可以立刻重试」，`wrong_end`/`hold_short` 会互相冒充。

**`measured`（JUDGE-05）**：直接用现成局部量拼字典，**不重算**——`start_angle_deg` / `start_rel_deg` / `end_angle_deg`（= `last_angle`）/ `end_rel_deg` / `swept_deg`（= `abs(acc)`）/ `elapsed_ms` / `samples` / `direction_sign`（`_turn_sign`）/ `target{...}`；失败再加 `fail{code,end_rel_deg,nearest_target_deg,distance_deg,tolerance_deg}`，其中 `distance_deg` 必须与 `message` 里那个数字同源。
**额外新增** `last_path() -> Array`（暴露 `_path` 给 Phase 7 高亮），对应 `path_detail()`（`:426-428`）。

---

### 5. `mobile/src/core/detectors/sequence_detector.gd`（detector / streaming，Wave 2）

**Analog（风格）：** `tap_detector.gd`；**语义：** `desktop/padskills/detectors.py:453-853`

**构造期**（`detectors.py:465-494`）——`release >= enter` 时退到 `enter - 0.15`（与 arc 的 `-0.05` 不同，别抄错）：

```python
self.steps: List[Step] = [parse_step(s) for s in raw_steps]

self.tolerance = float(p.get("tolerance_deg", 35.0))
self.enter = float(p.get("enter_threshold", 0.65))
self.release = float(p.get("release_threshold", 0.35))
if self.release >= self.enter:
    self.release = max(0.0, self.enter - 0.15)
self.max_ms = float(p.get("max_duration_ms", 700.0))
self.min_ms = float(p.get("min_duration_ms", 300.0))
self.idle_ms = float(p.get("idle_timeout_ms", 250.0))
self.motion_delta = float(p.get("motion_min_delta_deg", 2.0))
```

**运行期字段**（`:496-522`）——`t0 = None` 表示「没有进行中的序列」；GDScript 用 `_have_t0` 成对表示：

```python
self.index = 0
self.t0: Optional[float] = None    # None = 当前没有进行中的序列
self.neutral = True
self._armed = True                 # False = 已触发过，等一次"真正的松手"
self._release_since: Optional[float] = None
self.last_base = 0.0
self._hold_since: Optional[float] = None
self._now = 0.0
self._last_motion = 0.0
self._last_angle = 0.0
self._last_mag = 0.0
self._have_last = False
self._motion_ref_angle = 0.0
self._pending: Optional[Failure] = None
self._best_hold_ms = 0.0
# 每一步匹配期间的相对角度统计：最低 / 最高 / 总和 / 样本数
n = len(self.steps)
self._step_lo: List[Optional[float]] = [None] * n
self._step_hi: List[Optional[float]] = [None] * n
self._step_sum: List[float] = [0.0] * n
self._step_n: List[int] = [0] * n
self._facing = 0.0
self._buttons: FrozenSet[str] = frozenset()
self._required = tuple(skill.required_buttons)
self._button_mode = skill.button_mode
```

> GDScript 没有 `Optional[float]` 列表：`_step_lo/_step_hi` 用**无类型 `Array`**（元素 `null` 或 `float`），`_step_sum`/`_step_n` 用 `Array[float]` / `Array[int]`。不要用 `NAN` 当哨兵——`hi - lo` 会静默变 NaN。

**`_abandon_failure()` 优先级**（`:585-612`）——`timed_out → too_slow`；否则 `hold_ms>0 且 _best_hold_ms>0 → hold_short`；否则 `index>0 → incomplete`；否则 `None`：

```python
if self.t0 is None:
    return None
elapsed_ms = (now - self.t0) * 1000.0
step = self.steps[min(self.index, len(self.steps) - 1)]
if timed_out:
    return Failure("too_slow", ...)
if step.hold_ms > 0 and self._best_hold_ms > 0:
    return Failure("hold_short", ...)
if self.index > 0:
    done = " → ".join(s.label() for s in self.steps[:self.index])
    return Failure("incomplete", ...)
return None
```

**`on_idle()`**（`:614-624`）——先产失败再清场，`neutral=True, _armed=True`：

```python
def on_idle(self) -> None:
    """真正静置一段时间后：把没做完的尝试记一笔，再清空并允许起手。"""
    failure = self._abandon_failure(self._now)
    if failure is not None:
        self._emit(failure)
    self._clear_progress()
    self.neutral = True
    self._armed = True
    self._release_since = None
    self._last_motion = 0.0
    self._have_last = False
```

**`update()` 的十三个分支**（`:626-768`）。三处最易写错：

① 「在动」用 `>= motion_delta` **或** `>= 0.06`（与 arc 的 `0.05` 不同）：

```python
moved = (
    not self._have_last
    or angle_diff(self._motion_ref_angle, frame.rs_angle) >= self.motion_delta
    or abs(self._last_mag - mag) >= 0.06
)
```

② 序列中途超时/停顿后，**还推着就先不继续判**：

```python
if timed_out or stalled:
    failure = self._abandon_failure(now, timed_out=timed_out)
    if failure is not None:
        self._emit(failure)
    self._abort()
    # 还推着摇杆就先不继续判，必须回中之后重新起手
    if mag >= self.release:
        return None
```

③ 保持时长必须在清零前取出，否则 `summary` 永远 0 ms：

```python
self.index += 1
self.neutral = False
# 保持时长要在清零前取出来，否则成功摘要里永远是 0ms
fired_hold_ms = self._best_hold_ms if step.hold_ms > 0 else 0.0
self._hold_since = None
self._best_hold_ms = 0.0
self._last_motion = now
```

**`reset()` 绝不能动 `neutral`**（`:782-802`）——这段 docstring 是本阶段最重要的移植注释：

```python
def reset(self) -> None:
    """修饰键松开时作废进度。

    这里**不能**动 neutral：它描述的是"摇杆位置"，跟按键无关。
    如果把 neutral 置回 True，摇杆明明还推着、只是 L1 抖了一帧，
    就会被当成"已经回中"，于是按住不放就反复触发。
    ...
    """
    if self.t0 is not None and self._hold_since is not None:
        failure = self._abandon_failure(self._now)
        if failure is not None:
            self._emit(failure)
    self.index = 0
    self.t0 = None
    self._hold_since = None
    self._best_hold_ms = 0.0
    self._armed = True
```

**`observe()`**（`:808-814`）必须记录 `_now/_facing/_buttons/_last_angle/_last_mag/_have_last`——`status()`（`:828-853`）依赖这些字段做「方向对了，要按住 L1」「先松开右摇杆回中」提示。

**新增 `_step_t`（JUDGE-05 的唯一增量字段）**：在 `index += 1` 那一行记录 `_step_t[index] = now`（**完成**该步的时刻），并在 `_reset_metrics()` 里一并清空（`-1.0` 或单独的 `_have_step_t`）。它**不进任何判定分支**，只在构造 `measured.steps[].t_done_ms` 时读取。

**`measured` 结构**：`{kind:"sequence", elapsed_ms, base_deg, tolerance_deg, steps:[{label, required_hold_ms, actual_hold_ms, t_done_ms, angle_lo_deg, angle_hi_deg, angle_avg_deg}]}`。`label` 来自 `Step.label()`（见 §Shared Patterns / 方向文案）。

---

### 6. `mobile/src/core/detectors/build_detector.gd`（factory，Wave 2）

**Analog（语义）：** `desktop/padskills/detectors.py:1039-1046`

```python
def build_detector(skill: Skill) -> Detector:
    if skill.kind == "arc":
        return ArcDetector(skill)
    if skill.kind == "sequence":
        return SequenceDetector(skill)
    if skill.kind == "taps":
        return TapDetector(skill)
    raise ValueError(f"动作 {skill.name!r} 的 type 未知: {skill.kind!r}")
```

GDScript：`class_name DetectorFactory extends RefCounted` + `static func build(skill: Skill) -> Detector`，`match skill.kind`，未知 kind 返回 `null`（core 不抛；`ConfigValidator` 已保证 kind 合法）。文件必须独立（一个文件一个 `class_name`，`skill.gd:6-7` 的既定约束）。

---

### 7. `mobile/src/core/active_skill.gd`（model/runtime，Wave 3）

**Analog:** `desktop/padskills/engine.py:78-89`（无 GDScript 前例）

```python
@dataclass
class ActiveSkill:
    skill: Skill
    detector: Detector
    last_fire: float = -1e9
    hits: int = 0
    attempts: int = 0
    # 练习进度：每做对 GROUP_SIZE 个算一组，满了清零重新数
    group_hits: int = 0
    groups_done: int = 0
    failures: Dict[str, int] = field(default_factory=dict)
    last_outcome: Optional[Outcome] = None
```

GDScript：`RefCounted` + 公开字段 + `_init(p_skill, p_detector)`。`last_fire` 默认 `-1e9` 照抄——它让「第一发永远不受冷却限制」。`failures` 用 `Dictionary`（code → count）。

**不要**把 `TapRuntime` 的 `skill_name/hits/attempts/...` 复制成第二套：`GestureEngine` 的公开只读字段应由 `active_skills[i]` 派生（Phase 4 的 `_runtime.hits` 等都是单技能场景，`TapRuntime` 转发第 0 个 ActiveSkill 即可）。

---

### 8. `mobile/src/core/gesture_engine.gd`（service，Wave 3）

**Analog（唯一前例，风格 + 移动端差异）：** `mobile/src/core/tap_runtime.gd`
**Analog（语义）：** `desktop/padskills/engine.py:92-452`

**Phase 4 已经写下的范围收缩清单**（`tap_runtime.gd:34-44`）——Phase 5 要逐条「还原」，这段注释本身就是施工单：

```gdscript
## ## 本阶段刻意的范围收缩（Phase 5 必须还原）
##
## - 手势锁按「右摇杆恒回中」的最保守路径实现：命中后固定锁满 `gesture_release_ms`
##   （150 ms），锁满时调一次 `on_idle()`。Phase 5 的 `Frame` 有了 `rs_mag` 之后，
##   要还原成「右摇杆真正回中才计时，推着就不解锁」（engine.py:219-233）。
## - `idle_reset_ms` 计时器**未移植**。论证：引擎的 idle 路径只调用 `on_idle()`，而
##   `TapDetector.on_idle()` 是空实现，所以对 tap 场景零行为差异。Phase 5 移植
##   arc / sequence 时必须补上，否则「摇杆静置后清空半截进度」会缺失。
## - `_discard_other_claims`、`held_required`（别的技能的修饰键）在单技能场景下不可达，
##   不移植。`relative_to_ls` 则在构造时留了一道硬护栏：没有左摇杆基准就整个禁用，
##   绝不在缺基准的情况下判相对动作。
```

**现有的顺序骨架**（`tap_runtime.gd:110-168`）——Phase 5 保留 1/2 步、重写 3-7 步：

```gdscript
func tick(frame: Frame) -> void:
	# 1. 相对左摇杆的动作：本阶段没有左摇杆基准，绝不判。
	if not _enabled:
		return

	# 2. 未确认布局：第一早退，必须在手势锁之前。这条是成功标准 4 的机械保证。
	if not layout_confirmed:
		return

	# 3. 手势锁：锁定期间检测器看不到任何帧，失败也不 drain。
	if _gesture_locked:
		if not _have_lock_release_since:
			_have_lock_release_since = true
			_lock_release_since = frame.now
		if (frame.now - _lock_release_since) * 1000.0 >= float(_gesture_release_ms):
			_detector.on_idle()
			_gesture_locked = false
			...
```

**目标 `tick()` 顺序**（`engine.py:248-377`，逐段引用）：

① 朝向在 paused 之前算，Frame 在朝向之后建（`:248-271`）：

```python
ls_ok = state.ls_mag >= self.cfg.input.ls_facing_threshold
self.facing_valid = ls_ok
if ls_ok:
    self.facing = state.ls_angle
...
frame = Frame(now=now, state=state, ls_mag=state.ls_mag, ls_angle=state.ls_angle,
              rs_mag=state.rs_mag, rs_angle=state.rs_angle,
              facing=self.facing, buttons=state.buttons)
```

② 手势锁必须看 `rs_mag`，锁满时对**全部** skills 调 `on_idle()`（`:275-289`）：

```python
if self._gesture_locked:
    if state.rs_mag < self.RELEASE_STICK:
        if self._lock_release_since is None:
            self._lock_release_since = now
        if (now - self._lock_release_since) * 1000.0 >= self.cfg.input.gesture_release_ms:
            for active in self.skills:
                active.detector.on_idle()
            self._gesture_locked = False
            self._lock_release_since = None
    else:
        self._lock_release_since = None
```

③ 引擎级 idle 计时器（`:303-314`）：

```python
if state.rs_mag < self.IDLE_STICK:
    if self._idle_since is None:
        self._idle_since = now
    if (not self._idle_cleared
            and (now - self._idle_since) * 1000.0 >= self.cfg.input.idle_reset_ms):
        for active in active_skills:
            active.detector.on_idle()
        self._idle_cleared = True
else:
    self._idle_since = None
    self._idle_cleared = False
```

④ 每技能的三道前置过滤 + 命中后的仲裁（`:316-370`）：

```python
if (held_required
        and not any(b in active.skill.required_buttons for b in held_required)):
    active.detector.observe(frame)
    active.detector.abandon()
    continue
if active.skill.relative_to_ls and not ls_ok:
    active.detector.observe(frame)
    active.detector.reset()
    continue
if not self._buttons_ok(active.skill, state.buttons):
    active.detector.observe(frame)
    active.detector.reset()
    continue

hit = active.detector.update(frame)
if hit is None:
    continue

self._discard_other_claims(active)           # ← 在冷却判断之前
if (now - active.last_fire) * 1000.0 < active.skill.cooldown_ms:
    continue
if (now - self._last_any_fire) * 1000.0 < self.cfg.global_cooldown_ms:
    self.suppressed += 1
    continue
```

⑤ 计数 / 分组 / 记录 / 置锁（`:354-370`）——照抄，`break` 不能在锁之前。

⑥ 失败归属（`:391-412`）——**只有一条**，取配置顺序第一个有 pending 的；取到后再清别人：

```python
def _drain_failures(self, now: float) -> None:
    owner: Optional[ActiveSkill] = None
    for active in self.active_skills():
        failure = active.detector.pop_failure()
        if failure is None:
            continue
        if owner is not None:
            continue
        owner = active
        active.attempts += 1
        ...
    if owner is not None:
        self._discard_other_claims(owner)
```

**`_buttons_ok`**（`:446-452`）——`any` / `all` 两模式，Phase 5 的油炸丸子用 `any`（`button_mode` 来自 `Skill`，`mobile/src/core/domain/skill.gd:18-19`）。

**清场入口**（`:185-198`）——Phase 5 只公开这一个，不移植 `focus`/`paused`：

```python
def _reset_progress(self) -> None:
    """丢掉所有未完成的进度，并让动作可以立刻重新起手。

    先 ``abandon()`` 静默清空（不会像 ``reset()`` 那样报"中途松手"），
    再 ``on_idle()`` 把 armed 拉回 True。少了后半步，画弧/序列动作要等
    摇杆回中 120~150ms 才重新武装，点完专项开关马上出手的第一下会被吃掉。
    """
    for item in self.skills:
        item.detector.abandon()
        item.detector.on_idle()
    self._gesture_locked = False
    self._lock_release_since = None
    self._idle_since = None
    self._idle_cleared = False
```

**结果通道**（移动端差异，必须写进类文档）：沿用 `tap_runtime.gd:189-193` 的 `Array[Outcome]` 全量 drain：

```gdscript
func pop_outcomes() -> Array[Outcome]:
	var drained: Array[Outcome] = []
	drained.assign(_outcomes)
	_outcomes.clear()
	return drained
```

**布局门 + 静默清场**沿用 `tap_runtime.gd:207-215`（`set_layout_confirmed(false)` 时 `abandon()` + 清队列，**不能** `reset()`）。

**Phase 6 钩子**（RESEARCH §D.6，本阶段只留接口）：`state_of(i) -> StringName`（`idle`/`tracking`/`locked`/`cooldown`）、`cooldown_remaining_ms(i, now) -> float`。二者都是只读派生，不进夹具。

---

### 9. `mobile/src/core/tap_runtime.gd`（改：变为 `GestureEngine` 子类，Wave 3）

**Analog:** 自身。构造签名**一个字都不能变**（`tap_runtime.gd:80-89`）：

```gdscript
func _init(p_skill: Skill, p_global_cooldown_ms: int, p_gesture_release_ms: int,
		p_layout_confirmed := false, p_group_size: int = GROUP_SIZE) -> void:
```

RESEARCH §D.3 规定的目标形态：

```gdscript
class_name GestureEngine extends RefCounted
    const GROUP_SIZE := 10
    func _init(p_config: AppConfig, p_layout_confirmed := false, p_group_size := GROUP_SIZE)

class_name TapRuntime extends GestureEngine
    func _init(p_skill, p_global_cooldown_ms, p_gesture_release_ms,
               p_layout_confirmed := false, p_group_size := GROUP_SIZE)
        # 造一个只含该 skill 的 AppConfig，注入 global_cooldown / gesture_release，
        # idle_reset_ms 与 ls_facing_threshold 用出厂默认（250 / 0.35）
        super._init(synthetic_config, p_layout_confirmed, p_group_size)
    static func select_taps_skill(config) -> Skill   # 原样保留
```

**必须同步改注释的两处**（断言本身一条不动，RESEARCH §D.3-4 / R.4-6）：
- `tap_runtime.gd:63` 的 `var _enabled: bool = true` 与 `:89` 的 `_enabled = not p_skill.relative_to_ls`：护栏从**构造期禁用**变成**运行期 `!ls_ok`**。
- `test_tap_runtime.gd:332-333` 的注释「这条护栏必须是**构造期**决定的」必须改成「运行期由 `ls_ok` 决定；旧用例的帧不带 LS，行为不变」。

**为什么旧断言仍绿**（逐条论证见 RESEARCH §D.3，计划里要原文引用）：`rs_mag` 默认 0 → 锁恒按 150 ms 解锁；`on_idle()` 满 250 ms 调一次且 tap 是空实现；单技能无 `held_required` / `_discard_other_claims` 对象；`suppressed` 语义不变。

---

### 10. `mobile/src/core/outcome.gd`（改，model，Wave 3）

**Analog:** 自身 + `engine.py:62-76`

现有字段与「`seq` 是移动端唯一差别」的说明（`outcome.gd:4-8`、`:17-24`）保持。新增 `measured: Dictionary = {}`，由 `GestureEngine._record(...)` 从 `Hit.measured` / `Failure.measured` 透传。

> 这是 RESEARCH §D.1 表里没列、但 V.5 的 `OUTCOME ... measured=...` 日志行与 JUDGE-05 的「每次判定返回」都需要的字段。计划里显式写一条，避免执行者到写日志时才发现没地方取。

**记录函数**（`tap_runtime.gd:172-184`）就是模板：逐字段赋值 + `_seq += 1`，不做校验、不做格式化。

---

### 11. `tools/decimate_trace.py`（tool / batch，Wave 4）

**Analog（骨架）：** `tools/gen_geometry_golden.py`（`render` / `write_if_changed` / `_first_difference` / `check` / `sync` / `main`，`:116-220`）
**Analog（判定器骨架）：** `tools/check_config_parity.py`（`check(root, stream=None)` 收集全部问题再返回，`:113-191`）

**CLI 形态**（RESEARCH §C.5）：`python3 tools/decimate_trace.py --check` 只比对；无参数时重新生成。

**必须照抄的 main 形状**（`gen_geometry_golden.py:194-220`）——`argv` 可注入、`repo_root()` 锚定脚本位置、`--check` 分支返回 `int`：

```python
def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="gen_geometry_golden.py", ...)
    parser.add_argument("--check", action="store_true", ...)
    parser.add_argument("--root", default=None, ...)
    args = parser.parse_args(argv)
    root = Path(args.root).resolve() if args.root else repo_root()
    if not root.is_dir():
        raise SystemExit(f"仓库根目录不存在: {root}")
    if args.check:
        return check(root)
    return sync(root)
```

**抽稀规则（唯一正确实现，RESEARCH §C.1）**：

```
period_ms = 1000 / hz
boundaries = 0, period_ms, 2*period_ms, ...
selected = { argmin_i |t_i - boundary| , 对每个 boundary（并列取更早的样本） }
for each i where buttons[i] != buttons[i-1]:
    selected.add( first j with t_j >= t_i )        # 按钮沿保底
frames = [ (t_i, state_i) for i in sorted(selected) ]   # 时间戳是 t_i，不是 boundary
```

**工具自身五条断言（缺一即假绿）**：
1. `rate_hz ∈ {120, 90, 60}`，`1000/rate` 非整数时用 float 边界，禁止取整。
2. `frames` 时间戳严格递增，且**每个时间戳都能在源轨迹里原样找到**（证明没网格化）。
3. 每个按钮变化都有对应的「变化后」样本。
4. `expect` 必须由参考引擎重放 `frames` 得到（复用 §1 的 `_NullSource` / `_CollectingEngine` harness）。
5. `vs_250.drift` 非空 ⇔ `shared/decimation_allowlist.json` 有同 id、同 rate 且 `reason` 非空的条目；白名单里已不漂移的条目也判红（双向，照 `check_config_parity.py:180-184` 的「记录过时也要删」）。

---

### 12. 左摇杆三件套（Wave 5）

#### 12.1 `mobile/src/core/device/calibration.gd`（改）

**Analog:** 自身。`normalize` 的三步顺序是硬约束（`calibration.gd:34-43`）：

```gdscript
static func normalize(raw: float, center: float, scale: float, sign: int) -> float:
	if not is_finite(raw) or not is_finite(center) or not is_finite(scale):
		return 0.0
	var centered := raw - center
	var normalized := clampf(centered / scale, -1.0, 1.0)
	return float(sign) * normalized
```

新增 `ls_center_x/ls_center_y/ls_scale_x/ls_scale_y`（`calibration.gd:27-31` 的 RS 四字段同构），复用同一个 `normalize`。`to_dict` / `from_dict` 用同一套 `_read_finite` / `_read_positive`（`:212-251`）——**不要**给 LS 做「可选、缺失落默认」：那正是 04-11 修掉的「默认校准看起来像真校准」。

> `from_dict` 增加 LS 四字段后，`test_device_profile.gd` 的 `_legal_profile()`（`:422-445` 附近）也要补，否则 schema 往返会先红。

#### 12.2 `mobile/src/core/device/axis_mapping.gd`（改：`snapshot_ls()`）

**Analog:** 自身 `snapshot_rs()`（`axis_mapping.gd:71-86`）——顺序固定，注释已经写死理由：

```gdscript
static func snapshot_rs(raw: PackedFloat32Array, mapping: AxisMapping,
		calibration: Calibration, deadzone: float) -> Vector2:
	if mapping == null or calibration == null or not mapping.has_rs():
		return Vector2.ZERO
	if mapping.rs_x_index >= raw.size() or mapping.rs_y_index >= raw.size():
		return Vector2.ZERO
	var x := Calibration.normalize(raw[mapping.rs_x_index], calibration.center_x,
		calibration.scale_x, mapping.rs_x_sign)
	var y := Calibration.normalize(raw[mapping.rs_y_index], calibration.center_y,
		calibration.scale_y, mapping.rs_y_sign)
	return Calibration.deadzone(x, y, deadzone)
```

RESEARCH §D.4 给了两条等价路径：新增 `snapshot_ls()`（同构复制），**或**抽成私有 `_snapshot(raw, x_idx, y_idx, cx, cy, sx, sy, sign_x, sign_y, dz)`。推荐后者——**禁止**让 `main.gd` 自己写一份「减中点除量程」（那是两套校准语义的开始）。

`has_ls()` 已存在（`:34-35`）；`from_dict` 对 ls 的 `allow_unmapped=true`（`:123-129`、`:159-182`）保持不变——旧档案仍能**加载**，但由 `DeviceProfile` 的门拒绝（见 12.4）。

#### 12.3 `mobile/src/core/input_setup.gd`（改：LS 对 / 符号 / 量程）

**Analog:** 自身。三处直接扩展：

① 候选轴对表与「不在动」的门槛（`input_setup.gd:32-57`）：

```gdscript
const PAIRS: Array[Vector2i] = [
	Vector2i(0, 1),
	Vector2i(2, 3),
	Vector2i(4, 5),
	Vector2i(6, 7),
]
const PAIR_NONE := Vector2i(-1, -1)
const MIN_PAIR_TRAVEL := 0.35
```

② `active_pair()`（`:146-164`）的评分与并列裁决逻辑，`ls_pair()` 逐条照抄，**再加一条**「不得与 RS 对相同」：

```gdscript
	var best := PAIR_NONE
	var best_score := 0.0
	var best_recency := -1
	for pair in PAIRS:
		var score := _pair_score(pair)
		if score <= 0.0:
			continue
		var recency := mini(_last_change[pair.x], _last_change[pair.y])
		if score > best_score + 1e-9:
			...
```

③ `build_profile()` 里必须替换的三行（`input_setup.gd:338-340`）：

```gdscript
	# 本页不区分左右摇杆：用户只被要求推右摇杆，左摇杆保持未映射。
	mapping.ls_x_index = -1
	mapping.ls_y_index = -1
```

新增：
- `ls_pair()`：`min(span_x, span_y)` 次高且 `>= MIN_PAIR_TRAVEL`，且 `!= active_pair()`。
- `confirm_ls_up()` + `_ls_up_armed`：用户「向上推」时取该对 Y 轴的位移符号——**不能**从极值方向推断（RESEARCH §E.2 已论证）。若检测到的位移在 X 轴，返回明确错误码供页面显示「推的是左右，请向上推」。
- `ls_ready() -> bool`：LS 对已识别 + 符号已确认 + LS 量程 `>= RANGE_READY`。
- `can_save()`（`:240-241`）改为 `range_ready() and ls_ready()`。
- `quality` 里追加 `"ls_ready": ls_ready()`（与 `:356-363` 的 `"range_ready": range_ready()` 同层）。
- `reset()`（`:88-110`）把 LS 状态一起清（与 `_x_sign/_y_sign` 的行为一致）。

#### 12.4 `mobile/src/core/device/device_profile.gd`（改：schema v2 + `ls_ready`）

**Analog:** 自身。

① 常量（`device_profile.gd:24`）：`const SCHEMA_VERSION := 1` → `2`。

② 复用门（`:65-80`）追加一条：`if not _ls_ready_marker(): return false`。

③ 标记函数照抄 `_range_ready_marker()`（`:100-106`）：

```gdscript
func _range_ready_marker() -> bool:
	var marker: Variant = quality.get("range_ready")
	return typeof(marker) == TYPE_BOOL and bool(marker)
```

④ 版本门已经有现成实现（`:154-160`），**只改常量**：

```gdscript
	var version: Variant = root.get("schema_version")
	if not _is_number(version) or float(version) != float(SCHEMA_VERSION):
		_error(out_errors, "$.schema_version", &"unsupported_schema",
			"schema_version 必须是 %d，收到 %s" % [SCHEMA_VERSION, JSON.stringify(version)],
			"改成 %d；未知版本必须整份丢弃，不做猜测迁移。" % SCHEMA_VERSION)
```

⑤ `can_enter_practice()` 追加 `has_ls()`：`ls=-1` 但 `ls_ready=true` 的自相矛盾档案必须拒绝（RESEARCH §E.3 第 4 条）。

> **必须同步的既有断言：** `test_device_profile.gd:255-257` 现在把 `schema_version = 2` 当作非法输入。升版后这条要改成 `3`，否则套件先红。这是本阶段唯一「改断言」的地方，且必须在计划里写明理由（改的是被升版淘汰的旧期望，不是放宽）。

---

### 13. `mobile/src/ui/input_setup_screen.gd`（改，Wave 5）

**Analog:** 自身。

**文案常量区**（`input_setup_screen.gd:61-67`）是唯一加文案的地方：

```gdscript
const TITLE_TEXT := "输入设置"
const HELP_TEXT := "A 保存并开始    B 清空重来    十字键左右翻 X / 上下翻 Y    LB/RB 换轴对    Start 换布局"
const NO_DEVICE_HELP := "打开手柄电源 → 长按配对键 → 在系统蓝牙里选择它 → 按手柄任意键唤醒"
## 量程没推满时按 A 的唯一回应：只说这一句、只改 `%Help`，不写档案、不切屏。
const RANGE_NOT_READY_HELP := "量程还没推满：把右摇杆往四个方向各推到底几次"
```

新增：`LS_NOT_READY_HELP` / `LS_PUSH_UP_HELP`（「左摇杆向上推一下」）。

**保存门**（`:198-226`）——新增 `if not _setup.can_save(): _notice = ...; return` 之前的两条 LS 提示，保持「只提示、不改页面状态、不写盘」：

```gdscript
func _save_and_enter() -> void:
	if _sampler == null or _sampler.buffer.device < 0:
		_notice = "没有检测到手柄：按手柄任意键唤醒后再按 A"
		return
	if _setup.active_pair() == InputSetup.PAIR_NONE:
		_notice = "先推一下右摇杆：认出一对轴之后才能保存"
		return
	if not _setup.can_save():
		_notice = RANGE_NOT_READY_HELP
		return
```

**渲染**：`_refresh()`（`:279-293`）追加两行（`_set_text` 的隐式节流照用，`:394-398`）；`debug_line()`（`:231-241`）追加 `ls=` / `ls_ready=` / `ls_sign=`，D5-1 的判据就是这一行。

**纯函数风格**（`pair_text` / `range_text` / `center_text` / `trigger_text`，`:345-377`）——新文案同样写成 static，套件可直接断言，不必实例化场景。

---

### 14. 组合根与日志（Wave 6）

#### 14.1 `mobile/src/ui/main.gd`（改）

**Analog:** 自身。要改的三处：

① 引擎构造（`main.gd:90-97`）——从「唯一 taps 技能」换成整份配置：

```gdscript
	var skill := TapRuntime.select_taps_skill(result.config)
	if skill == null:
		_show_config_error("配置里没有唯一的 taps 动作：只练绿色搓射需要恰好一条启用的 taps 动作。")
		return

	_runtime = TapRuntime.new(skill, result.config.global_cooldown_ms,
		result.config.input.gesture_release_ms, false)
```

② 每帧 Frame（`main.gd:149-152`）——这是唯一新增的接线点：

```gdscript
	var frame := Frame.new()
	frame.now = Time.get_ticks_usec() / 1_000_000.0
	frame.buttons = _sampler.buffer.pressed_dict()
	_runtime.tick(frame)
```

新增字段来自 `PadStateBuffer.axis_value(i)`（`pad_state_buffer.gd:108-111`）+ `AxisMapping.snapshot_rs/snapshot_ls` + 档案里的 `Calibration`。**`facing` 不赋值**——由引擎每帧写。raw 数组用 `axis_value` 组，不要新增轮询通道（RESEARCH §D.4 / INPUT-05）。

③ 时间单位注释（`main.gd:23-25`）保留：`Frame.now` 是秒，`PadSampler._now_ms()` 是毫秒，不要在 `main.gd` 换算。

④ 「输入设置页零 Outcome」的两层保证（`main.gd:145-148`）不能动——结构层（不调 `tick`）+ 运行时层（`layout_confirmed`）。

#### 14.2 `mobile/src/ui/practice_screen.gd`（改）

**Analog:** 自身。drain 是唯一结果入口（`practice_screen.gd:70-83`）：

```gdscript
func _process(delta: float) -> void:
	if not visible:
		return
	if _runtime == null:
		return
	# 全量 drain：本帧有几条就显示几条，不假设最多一条。
	var outcomes: Array[Outcome] = _runtime.pop_outcomes()
	for outcome in outcomes:
		_banner.show_outcome(outcome)
```

`InputLog.outcome(...)` 必须在这个循环里、`show_outcome` **之前**调用（RESEARCH §V.5）。**不得**在 `main.gd` 再 drain 一次——第二个消费者会把队列取空。

`setup()`（`:56-65`）的 `_runtime.skill_name` 改成「自由练习」类的标题；动作名交给横幅（`Outcome.skill_name`）。

#### 14.3 `mobile/src/ui/result_banner.gd`（改）

**Analog:** 自身。`show_outcome`（`result_banner.gd:41-53`）只做去重 + 取字段：

```gdscript
func show_outcome(outcome: Outcome) -> void:
	if not accepts(_shown_seq, outcome.seq):
		return
	_shown_seq = outcome.seq
	if outcome.ok:
		_title.text = "✓ 做对了"
		_reason.text = outcome.detail
		...
	else:
		_title.text = "✗ 没做对"
		_reason.text = outcome.message
```

改动只有一处：`_title.text` 前加 `outcome.skill_name`（例如 `"✓ 做对了 · %s" % outcome.skill_name`）。**不要**在这里重排原因文案。

#### 14.4 `mobile/src/input/input_log.gd`（改：`outcome()`）

**Analog:** 自身。格式真源是纯函数（`input_log.gd:60-66`），新行同理：

```gdscript
static func format_button(t_ms: int, device: int, index: int, name: String, down: bool) -> String:
	return "t=%d dev=%d btn=%d name=%s down=%d" % [t_ms, device, index, name, 1 if down else 0]


static func format_axis(t_ms: int, device: int, index: int, value: float) -> String:
	return "t=%d dev=%d axis=%d v=%.3f" % [t_ms, device, index, value]
```

新增 `format_outcome(t_ms, skill, ok, code, elapsed, seq, measured) -> String`，输出：

```
t=<ms> OUTCOME skill=<name> ok=<0|1> code=<code> elapsed=<ms> seq=<n> measured=<k=v;k=v;...>
```

`measured` 值 `%.1f`、分号串（给人和脚本看，不要求可逆解析）。写入走同一个 `_emit()`（`:108-110`），因此自动获得 logcat 镜像 + 2 MB 轮转 + 失败短路（`:114-125`、`:184-190`）。

#### 14.5 `tools/analyze_input_log.py`（tool，Wave 6）

**Analog:** `tools/check_config_parity.py`——只读、收集全部问题、`check(root, stream=None) -> int`、`main(argv) -> int`（`:113-120`、`:194-212`）。

三件事（RESEARCH §V.5）：
1. 以 `OUTCOME` 行为窗口右界，向前找最近一次「连续轴变化」的起点（间隔 > 100 ms 视为断开）；
2. 只统计窗口内 `axis=` 行的时间差 → `p50/p95/max`；
3. 输出窗口内每根轴的 `min/max`（判断扳机跳变污染）。

输入路径用 `--log <path>` 注入（方便把 `adb exec-out cat` 的转储喂进来），默认 `input_log.txt`。判据行建议 `INPUT_LOG_STATS window_ms=... n=... p50=... p95=... max=...`，与其它工具的 `*_OK` 正向哨兵同文化（`check_config_parity.py:190`）。

---

### 15. 测试套件（Wave 2-6）

#### 15.1 `test_gesture_detector.gd` / `test_gesture_engine.gd`

**Analog:** `mobile/tests/unit/test_tap_detector.gd` + `test_tap_runtime.gd`（两者同构、共读一份夹具、只按 `kind` 过滤）。

**套件骨架**（`test_tap_detector.gd:44-62`）——先读夹具、再查 meta、再查规模、最后逐例回放：

```gdscript
func run(r) -> void:
	var data := _load_fixture(r)
	if data.is_empty():
		r.complete()
		return
	var cases := _detector_cases(data)
	_check_meta(r, data)
	_check_scale(r, cases, data)

	var meta: Dictionary = data.get("meta", {})
	var base_skill := _load_skill(r, str(meta.get("skill", "")))
	if base_skill == null:
		r.complete()
		return
	for case in cases:
		_check_case(r, case, base_skill)
	_check_abandon_silent(r, base_skill)
	print("TAP_GOLDEN_DETECTOR cases=%d mismatches=%d" % [cases.size(), _mismatches])
	r.complete()
```

Phase 5 的 `print` 换成四条新哨兵（见 §Shared Patterns）。

**读取夹具的方式**（`test_tap_detector.gd:65-80`）——`get_file_as_bytes` + `JSON.new().parse()`，不用 `parse_string`：

```gdscript
	var bytes := FileAccess.get_file_as_bytes(GOLDEN_PATH)
	if bytes.is_empty():
		r.check(false, "读不到 tap 黄金夹具：%s（运行 python3 tools/gen_tap_golden.py 生成）" % GOLDEN_PATH)
		return {}
	var json := JSON.new()
	if json.parse(bytes.get_string_from_utf8()) != OK:
		r.check(false, "tap 黄金夹具不是合法 JSON（第 %d 行：%s）"
			% [json.get_error_line() + 1, json.get_error_message()])
		return {}
```

**规模与 id 下限**（`test_tap_detector.gd:102-113`）——逐条点名 id，防「删掉大半仍绿」：

```gdscript
func _check_scale(r, cases: Array, data: Dictionary) -> void:
	_eq_int(r, cases.size(), 12, "detector 用例必须正好 12 条")
	var ids: Dictionary = {}
	for case in cases:
		ids[str(case.get("id", ""))] = true
	_eq_int(r, ids.size(), cases.size(), "每条用例都必须有唯一 id")
	for required_id in REQUIRED_DETECTOR_IDS:
		var present: bool = ids.has(required_id)
		r.check(present, "detector 用例必须包含点名 id %s" % required_id)
		if not present:
			_mismatches += 1
```

Phase 5 把「正好 N 条」换成「`>= 50` / `>= 26`」（RESEARCH 允许语料增长），但**必须同时保留逐条点名 id**。

**逐帧回放**（`test_tap_detector.gd:229-260`）——修饰键不满足时 `observe` + `reset`，顺序不能反；每帧后 `pop_failure()`；用例结束不 `reset()`。

Phase 5 的 `frames` 变成 5 元组，`_make_frame` 要扩成：

```gdscript
func _make_frame(t_ms: int, label: String) -> Frame:
	var frame := Frame.new()
	frame.now = float(t_ms) / 1000.0
	if label != "":
		for part in label.split("+", false):
			frame.buttons[part] = true
	return frame
```

新增 `rs_angle/rs_mag/ls_angle/ls_mag/facing` 赋值；`facing` 用夹具值（引擎层），检测器层直接用夹具的 `facing` 字段。

**引擎套件**（`test_tap_runtime.gd:178-191`）——每帧 `tick` 后全量 drain 累积，这正是 UI 的用法：

```gdscript
	var runtime := TapRuntime.new(skill, config.global_cooldown_ms,
		config.input.gesture_release_ms, confirmed)
	var actual: Array[Outcome] = []
	for entry in case.get("frames", []):
		var frame := _make_frame(int(entry[0]), str(entry[1]))
		runtime.tick(frame)
		# 每帧全量 drain 再累积：这正是 UI 的用法，也证明队列不会被覆盖。
		actual.append_array(runtime.pop_outcomes())
```

**结构断言段**（`test_tap_runtime.gd:234-350`）是 Phase 5 引擎夹具的补充模板：布局门、逐动作冷却、全局冷却、分组、相对动作护栏各一条——它们证明「真实配置下不可达的分支仍然可达（用合成配置）」。

#### 15.2 `test_measured.gd`（JUDGE-05 的唯一证明）

**Analog:** `test_tap_runtime.gd` 的结构断言段（不经夹具，直接构轨迹断言字段）。

写法：用已知参数的合成轨迹（例如匀速 200°/500 ms 的弧），断言：
- `swept_deg` 与设定值差 < 1°；
- `t_done_ms` 与轨迹变化点差 < 1 帧（4 ms）；
- `actual_hold_ms` 与设定 hold 差 < 1 帧；
- **同一条失败**里 `measured.fail.distance_deg` 与 `message` 里的数字同源（例如把 `message` 里的 `%d` 抠出来比较——这是唯一允许在测试里解析文案的地方，用来证明「同源」而不是鼓励 UI 解析）。

哨兵：`MEASURED cases=N mismatches=0`。

#### 15.3 `test_decimation.gd`

**Analog:** `test_tap_detector.gd`（回放）+ `test_geometry.gd`（黄金夹具读取）。

断言：`rate_hz ∈ {120,90,60}`、`frames` 时间戳在源轨迹里原样存在（子集）、`codes_equal`、`drift` 双向白名单。哨兵：`DECIMATION rates=3 cases=252 mismatches=0`。

#### 15.4 `test_practice_wiring.gd`

**Analog:** `mobile/tests/unit/test_green_slice.gd`（无头组合根风格；本阶段新增）。

断言：给定 raw 轴数组 + 档案，`main.gd` 同款组装函数产出的 `Frame` 字段与 `AxisMapping.snapshot_rs/snapshot_ls` 一致；`facing` 在 `ls_mag` 回中后保持上值、`ls_ok=false`。若 `main.gd` 的组装逻辑无法在无头环境调用，则把它抽成 `mobile/src/core/frame_builder.gd`（纯函数）——**推荐**，这样不需要实例化场景。

#### 15.5 扩展 `test_input_setup.gd` / `test_device_profile.gd`

**Analog:** 自身。`test_input_setup.gd:19-35` 的写法值得照抄——每个 `_check_*` 一个行为，最后一条断言是数量下限：

```gdscript
	var total: int = r.assertions
	r.check(total >= 50, "本套件至少 50 条断言（实际 %d）" % total)
	r.complete()
```

**保存门**（`test_input_setup.gd:208-232`）是 LS 版本的模板：

```gdscript
	r.check(not idle.can_save(), "没有轴对时 can_save 为 false")
	r.check(idle.build_profile("Pad", "", "2026-11-05T22:00:00") == null,
		"没有轴对时 build_profile 必须返回 null")
```

新增四条（RESEARCH §E.3 的机械证明）：v1 档案（`ls=-1`）→ `from_dict` 返回 null + `unsupported_schema`；v2 齐全 + `ls_ready=true` → `can_enter_practice()==true`；v2 但缺 `ls_ready` → false；`ls=-1` 但 `ls_ready=true` → false。

#### 15.6 `mobile/tests/core_runner.gd`（改）

**Analog:** 自身。只加 `SUITES` 条目（`core_runner.gd:45-64`），保持「显式 preload 的字典」：

```gdscript
const SUITES := {
	"config_corpus": preload("res://tests/unit/test_config_corpus.gd"),
	...
	"tap_detector": preload("res://tests/unit/test_tap_detector.gd"),
	"tap_runtime": preload("res://tests/unit/test_tap_runtime.gd"),
	"vocabulary": preload("res://tests/unit/test_vocabulary.gd"),
}
```

新增键（建议按字母序插入，runner 自己会 `sort()`，`core_runner.gd:69-70`）：`decimation`、`gesture_detector`、`gesture_engine`、`measured`、`practice_wiring`。

**不要**给测试文件加 `class_name`（`core_runner.gd:14`）。

---

## Shared Patterns

### S1. 失败单槽 + `_emit`（所有检测器）

**Source:** `mobile/src/core/detectors/detector.gd:9-11, 30, 62-71`

```gdscript
## 失败是**单槽覆盖写**（`_pending`），不是队列：每个终结路径都会立刻 return，
## 一次 update() 最多走到 `_emit` 一次；万一上一条还没被取走，新的直接覆盖，
## 因为新的这次更相关。
var _pending: Failure = null
...
func pop_failure() -> Failure:
	var failure: Failure = _pending
	_pending = null
	return failure

func _emit(failure: Failure) -> void:
	_pending = failure
```

**Apply to:** `arc_detector.gd`、`sequence_detector.gd`（tap 已实现）。规则：**每条终结路径 `_emit` 后立刻 `return`**；`_abort`/`_clear_progress` 不碰 `_pending`；只有 `abandon()` 和 `reset()` 可以清槽。

### S2. 三套清理语义（`reset` / `abandon` / `on_idle`）

| 语义 | 触发者 | 副作用 | 会产失败？ |
|------|--------|--------|-----------|
| `reset()` | 修饰键松开、LS 回中、`!buttons_ok` | 清进度；Arc `armed=True`；Sequence **不动 `neutral`**；Tap 产 `hold_short` | Sequence/Tap 会，Arc 不会 |
| `abandon()` | `_discard_other_claims`、修饰键互斥 | `_pending=null` + `_abort()`（Arc/Sequence 各自覆盖） | **绝不** |
| `on_idle()` | 引擎 idle 计时器、手势锁满 | Sequence 先 `_abandon_failure(timed_out=false)` 再清场并重新武装；Tap 空实现 | Sequence 会（`incomplete`/`hold_short`） |

**Source:** `detectors.py:212-218, 220-238, 430-440, 578-624, 782-806, 937-939`；GDScript 契约 `detector.gd:38-54`。
**Apply to:** 全部三个检测器 + `GestureEngine` 的三处调用点（`:322-338`、`:346`、`:411-412`）。

### S3. 引擎分支顺序（不可重排）

**Source:** `desktop/padskills/engine.py:248-377`（完整 8 步）+ `tap_runtime.gd:10-19`（Phase 4 的等价骨架）

```
layout 门 → 朝向 → 手势锁 → held_required → idle → 逐技能(held/relative/buttons/update)
→ discard → 冷却 → 记录 → 锁 → break → drain → (rumble no-op)
```

**Apply to:** `gesture_engine.gd`。三处移动端差异只能有三处（RESEARCH §D.2）：布局硬门（最前）、`pop_outcomes()` 队列、公开 `reset_progress()`。

### S4. 方向文案（`Step.label()` + `direction_name()`）——移植缺口

**Source:** `desktop/padskills/config.py:116-149`

```python
_CARDINAL_NAMES = {
    0.0: "前", 45.0: "前右", 90.0: "右", 135.0: "后右",
    180.0: "后", 225.0: "后左", 270.0: "左", 315.0: "前左",
}

def direction_name(angle: float) -> str:
    """角度 -> 便于阅读的中文方向名。"""
    a = norm_deg(angle)
    best = min(_CARDINAL_NAMES, key=lambda k: abs(((a - k + 180) % 360) - 180))
    diff = abs(((a - best + 180) % 360) - 180)
    return _CARDINAL_NAMES[best] if diff <= 22.5 else f"{a:.0f}°"
```

**为什么本阶段必须补：** `SequenceDetector._describe()`（`detectors.py:772-780`）、`_summary()`（`:557-568`）、`_abandon_failure()`（`:605`）、`status()`（`:841-853`）全部调用 `Step.label()`，而 `Step.label()` 就是 `"/".join(direction_name(a) ...)`（`config.py:162-163`）。这些字符串进 250 Hz 黄金语料的**逐字比较**，所以 `direction_name` 的 `<= 22.5` 与 `%.0f` 必须逐字移植。

**落点：** `mobile/src/core/domain/direction_table.gd`（现在刻意没移植，见其类文档 `:15-16`）+ `mobile/src/core/domain/step.gd` 加 `func label() -> String`。方向名的黄金用例应进 `mobile/tests/fixtures/geometry_golden.json` 或 `test_vocabulary.gd`（后者已有 42 条别名硬断言，`direction_table.gd:6-8`）。

### S5. 夹具生成纪律（唯一期望来源）

**Source:** `tools/gen_tap_golden.py:1-9`、`gen_geometry_golden.py:7-9`

> 夹具是**生成物**：手改一份 JSON 让测试变绿，等于把「与 Python 对等」偷换成「与手改后的自己一致」。

**Apply to:** `gen_gesture_golden.py`、`decimate_trace.py`。三条铁律：`--check` 逐字节比较且**绝不写盘**；规范字节 `json.dumps(ensure_ascii=False, indent=2, sort_keys=True) + "\n"`；源哈希进夹具。

### S6. 哨兵与断言下限（假绿的四个入口）

**Source:** `mobile/tools/test-core.sh:149-178`

```bash
# 判据是哨兵，不是 $?。没有这一行，解析失败 / class_name 未解析都会一路绿灯。
if ! grep -qE '^TESTS_DONE failures=0$' "$tmp/tests.log"; then
...
# 零断言是另一种假绿：套件全被跳过时同样打印 failures=0。
if grep -qE '^TESTS_ASSERTIONS=0$' "$tmp/tests.log"; then
...
if ! grep -qE '^TAP_GOLDEN_DETECTOR cases=[1-9][0-9]* mismatches=0$' "$tmp/tests.log"; then
```

新增四条必须**同一形状**（`cases=[1-9][0-9]*` 不可省；`mismatches` 只统计真实差异）：

```
GESTURE_GOLDEN cases=84 mismatches=0
GESTURE_RUNTIME cases=29 mismatches=0
MEASURED cases=N mismatches=0
DECIMATION rates=3 cases=252 mismatches=0
```

**生成器 vs 套件双下限**：套件先断言 `cases.size() >= 常量`，外壳再 grep 哨兵；两层都要。

### S7. 中文文案 / 英文标识符 / 单文件单 `class_name`

**Source:** `AGENTS.md` 的 Language Split；`skill.gd:6-7`；`core_runner.gd:14`

- 新文件：`class_name ArcDetector extends Detector`、变量 `rs_mag`、参数 `p_skill`；注释与 docstring 全中文。
- 失败码是 lowercase snake_case 的 `StringName`：`&"too_short"`、`&"wrong_end"`。新码必须同时加进 `detector.gd:17-28` 的 `FAILURE_LABELS`（整表已移植，10 条）。
- 时长字段 `*_ms`、频率 `*_hz`、时间戳显式传 `now`（秒）。
- 每个 core 文件一个 `class_name`；测试文件**不加** `class_name`。

### S8. core 纯度（机械闸门）

**Source:** `tools/lint_core_purity.py:47-64`

```python
RULES: List[Tuple[str, re.Pattern[str]]] = [
    ("input_singleton", re.compile(r"\bInput\s*\.")),
    ("time_singleton", re.compile(r"\bTime\s*\.")),
    ("node_type", re.compile(r"\bNode\b")),
    ("fileaccess_io", re.compile(r"\bFileAccess\b")),
    ("logging", re.compile(
        r"\b(?:print|prints|printt|printerr|print_rich|print_debug|push_error|push_warning)\s*\(")),
    ...
    ("outer_layer_dep", re.compile(
        r"(?:preload|load)\s*\(\s*\"res://src/(?:platform|ui|app|input)/")),
]
```

**Apply to:** 全部新 `core/**` 文件。两个已知误报陷阱：注释里逐字写 `FileAccess` / `Node` 会被状态机剥掉（安全），但**字符串字面量**里写 `preload("res://src/ui/…")` 会被 `outer_layer_dep` 抓住（它是 string-aware）。

### S9. 数字与文案对等（取整刀口）

**Source:** `gen_tap_golden.py:457-469`

```python
def _normalize_elapsed_ms(value: float, case_id: str, what: str) -> float:
    """把浮点噪声归一成毫秒整数，并拒绝真正的非整数。
    ...
    判据必须是「与最近整数相差不超过 1e-6」而不是 float.is_integer()
    """
    rounded = float(round(float(value)))
    if abs(float(value) - rounded) > 1e-6:
        raise SystemExit(f"✗ {case_id}: {what} 的 elapsed_ms={value!r} 不是毫秒整数")
    return rounded
```

**Apply to:** `gen_gesture_golden.py` 的每个 `%.0f` 字段（RESEARCH §B.6 #4）；GDScript 侧统一 `TOL := 1e-6`（`test_tap_detector.gd:22`）。

---

## No Analog Found

| File | Role | Data Flow | Reason / 计划应怎么处理 |
|------|------|-----------|--------------------------|
| `mobile/src/core/gesture_engine.gd` | service（引擎） | streaming | 没有 GDScript 多技能引擎前例。`tap_runtime.gd` 是**单技能**门面，其类文档（`:34-44`）已把「本阶段刻意收缩、Phase 5 必须还原」的三项逐条列出——按它当施工单 + `engine.py:248-377` 当规格书。 |
| `mobile/src/core/active_skill.gd` | model | event-driven | 无 GDScript 前例；`engine.py:78-89` 的 dataclass 直接翻成 `RefCounted` 公开字段。 |
| `shared/decimation_allowlist.json` | config | batch | 首个漂移白名单。语义可照 `config_corpus.json` 的 `divergence` 双向规则（`check_config_parity.py:148-184`）：有记录必须真漂移，真漂移必须有记录。 |

其余 31 个文件均有 exact 或 role-match 前例。

---

## Metadata

**Analog search scope:** `mobile/src/core/**`、`mobile/src/ui/**`、`mobile/src/input/**`、`mobile/tests/**`、`mobile/tools/**`、`tools/**`、`desktop/padskills/detectors.py`、`desktop/padskills/engine.py`、`desktop/padskills/config.py`、`shared/skills_config.json`

**Files scanned:** 34 个 analog 目标 + 4 份上游文档（05-RESEARCH / 05-VALIDATION / REQUIREMENTS / AGENTS）
**Pattern extraction date:** 2026-11-06

**已核实的约束：**
- 所有引用的 analog 均为 `git ls-files` 跟踪源码（无 `.godot/` 镜像路径）。
- `design/` 零引用。
- 本阶段不修改 `desktop/padskills/*.py`（G1 红线）；桌面文件只作**语义**参考，不作为执行目标。
- `shared/skills_config.json` 是唯一真源；本阶段不改任何阈值（RESEARCH §C.4 的「强烈建议」）。语料生成器只读它。

**给计划者的三个提醒（来自 RESEARCH，容易在拆任务时丢掉）：**
1. `release_hold_ms = 120` 的 124 ms 缺口是**已登记的边界带差异**，不是 bug；不要在 Wave 4 顺手改阈值。
2. `global_cooldown_ms = 60` 在出厂配置下**不可达**；只为它写合成运行时的期望，不要写「真实配置」的期望。
3. `too_fast` 对油炸丸子**数学上不可达**；语料里出现它，生成器就永远拿不到期望，最后一定有人去改阈值「修好」它。

## PATTERN MAPPING COMPLETE
