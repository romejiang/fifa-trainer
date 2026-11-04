# Phase 4: 设备输入层 + 绿色搓射竖切 — Pattern Map

**Mapped:** 2026-11-05
**Files analyzed:** 36 个新建 / 修改路径
**Analogs found:** 34 / 36（2 个无直接 analog，见文末）

> 所有 analog 路径都已用 `git ls-files -- <path>` 验证为**已跟踪源码**；没有引用 `.gsd/` 镜像、`design/` 或任何生成物。`design/` 未被读取或修改。

---

## File Classification

| # | 新建 / 修改文件 | Role | Data Flow | Closest Analog | Match Quality |
|---|-----------------|------|-----------|----------------|---------------|
| 1 | `mobile/src/core/frame.gd` | model | in-memory value | `mobile/src/core/domain/step.gd` | role-match |
| 2 | `mobile/src/core/hit.gd` | model | in-memory value | `mobile/src/core/domain/pulse.gd` + `domain/skill.gd:39-43` | role-match |
| 3 | `mobile/src/core/failure.gd` | model | in-memory value | `mobile/src/core/config/config_error.gd` | role-match |
| 4 | `mobile/src/core/outcome.gd` | model | in-memory value | `desktop/padskills/engine.py:62-76` | **exact**（字段对等） |
| 5 | `mobile/src/core/detectors/detector.gd` | service（基类） | request-response | `desktop/padskills/detectors.py:61-118` | **exact 语义** / partial 风格 |
| 6 | `mobile/src/core/detectors/tap_detector.gd` | service | state machine | `desktop/padskills/detectors.py:858-1034` | **exact**（逐行移植） |
| 7 | `mobile/src/core/tap_runtime.gd` | service | orchestration / batch | `desktop/padskills/engine.py:198-363` | role-match（引擎子集） |
| 8 | `mobile/src/core/device/axis_mapping.gd` | utility | mapping | `desktop/padskills/input_source.py:116-132, 313-325` | role-match |
| 9 | `mobile/src/core/device/calibration.gd` | utility | transform | `desktop/padskills/input_source.py:328-334, 539-547` | **exact**（死区逐字） |
| 10 | `mobile/src/core/device/device_profile.gd` | model | serialize / validate | `mobile/src/core/domain/skill.gd` + `config/config_validator.gd:865-878` | partial |
| 11 | `mobile/src/core/device/probe_evaluator.gd` | service | sampled-window transform | `desktop/padskills/input_source.py:258-292` | partial |
| 12 | `mobile/src/input/pad_sampler.gd` | adapter（Node） | event-driven + 每帧对账 | `mobile/src/smoke/smoke_screen.gd:26-98` + `desktop/padskills/input_source.py:484-537` | partial |
| 13 | `mobile/src/input/joy_button_map.gd` | utility | lookup | `mobile/src/core/domain/buttons.gd:17-56` | role-match |
| 14 | `mobile/src/app/profile_store.gd` | adapter | file-I/O + CRUD | `mobile/src/app/config_store.gd:83-103, 147-161` | **exact 模式** |
| 15 | `mobile/src/ui/main.gd` | composition root | state switch | `mobile/src/smoke/smoke_screen.gd:26-43` | partial |
| 16 | `mobile/src/ui/main.tscn` | scene | static layout | `mobile/src/smoke/smoke_screen.tscn:1-26` | role-match |
| 17 | `mobile/src/ui/onboarding_screen.gd` | component | state machine + render | `mobile/src/smoke/smoke_screen.gd:67-98` | partial |
| 18 | `mobile/src/ui/onboarding_screen.tscn` | scene | static layout | `mobile/src/smoke/smoke_screen.tscn:1-26` | role-match |
| 19 | `mobile/src/ui/practice_screen.gd` | component | render loop | `desktop/padskills/gui.py:593-620` + `smoke_screen.gd:71-98` | partial |
| 20 | `mobile/src/ui/practice_screen.tscn` | scene | static layout | `mobile/src/smoke/smoke_screen.tscn:1-26` | role-match |
| 21 | `mobile/src/ui/result_banner.gd` | component | render | 无直接 analog（取 `gui.py:600-614` 的「只显示一次」语义） | none |
| 22 | `mobile/tests/unit/test_tap_detector.gd` | test | fixture replay | `mobile/tests/unit/test_geometry.gd:21-46` | role-match |
| 23 | `mobile/tests/unit/test_tap_runtime.gd` | test | fixture replay | `mobile/tests/unit/test_geometry.gd:21-46` | role-match |
| 24 | `mobile/tests/unit/test_device_profile.gd` | test | table-driven | `mobile/tests/unit/test_models.gd:27-38` + `test_config_corpus.gd:50-62` | role-match |
| 25 | `mobile/tests/unit/test_pad_sampler.gd` | test | synthetic events | `mobile/tests/unit/test_config_store.gd:23-37` | partial |
| 26 | `mobile/tests/fixtures/tap_golden.json` | fixture | generated artifact | `mobile/tests/fixtures/geometry_golden.json`（生成物） | role-match |
| 27 | `tools/gen_tap_golden.py` | repo tool | generate + `--check` | `tools/gen_geometry_golden.py` | **exact**（结构照抄） |
| 28 | `mobile/tools/test-core.sh` | gate | orchestration | 自身 `:60-64, 133-143` + `gate-a.sh:126-136` | role-match |
| 29 | `mobile/tools/test-core-selftest.sh` | gate selftest | counterexample | 自身 `:30-70, 98` | **exact**（追加第 5 条） |
| 30 | `tools/make_font_subset.py` | repo tool | char derivation | 自身 `:38-44, 100-108` | **exact**（改 `CHAR_SOURCES`） |
| 31 | `tools/lint_core_purity.py` | repo tool | text scan | 自身 `:47-67` | **exact**（扩 `outer_layer_dep`） |
| 32 | `tools/test_lint_core_purity.py` | test | canary | 自身 `:154-189` | **exact**（追加反例） |
| 33 | `mobile/tests/core_runner.gd` | test harness | batch | 自身 `:45-54` | **exact**（加 4 个套件） |
| 34 | `mobile/project.godot` | config | static | 自身 `:6-15` | **exact**（改 `run/main_scene`） |
| 35 | `mobile/docs/CORE.md` | doc | contract | 自身 `:41-58, 113-129` | **exact** |
| 36 | `mobile/ACCEPTANCE.md` | doc | acceptance table | 自身 `:50-61, 88-98` | **exact** |

---

## Pattern Assignments

### 1. `mobile/src/core/frame.gd`（model, in-memory）

**Analog:** `mobile/src/core/domain/step.gd`

**文件骨架 / 注释习惯**（`step.gd:1-22`）：

```gdscript
class_name Step
extends RefCounted

## 方向序列里的一步：与 desktop/padskills/config.py:152-163 的 `Step` 对齐。
##
## angles  允许的角度集合。长度 > 1 表示「任一方向都算」，例如 [90, 270] 是左右都行。
## hold_ms 需要把这个方向保持多久才算完成这一步；0 表示点拨一下即可。
##
## angles 在构造时复制一份：GDScript 的数组是引用类型，直接持有入参会把调用方后续的
## append / clear 穿透进对象内部。这条语义由 test_models.gd 断言，不要为了省一次复制
## 把它改回去。
##
## 本类只承载已校验的数据：方向名解析在 DirectionTable，步骤合法性在 ConfigValidator。

var angles: Array[float] = []
var hold_ms: float = 0.0


func _init(p_angles: Array[float] = [], p_hold_ms := 0.0) -> void:
	# 浅拷贝足够：Array[float] 的元素是值类型。
	angles = p_angles.duplicate()
	hold_ms = p_hold_ms
```

照此写 `Frame`：`class_name Frame` / `extends RefCounted` / 中文 `##` 说明「为什么只有两个字段」/ 字段带类型与默认值。RESEARCH 已给出字段本体（`04-RESEARCH.md:575-583`）：

```gdscript
var now: float = 0.0            # 秒；时间轴由调用方注入（core 不读时钟）
var buttons: Dictionary = {}    # canonical_name -> true；用字典而不是数组，查询 O(1)
```

**必须钉死的口径（RESEARCH 内部有一处措辞冲突）：**
- `Frame.now` 的单位是**秒**。依据是 `04-RESEARCH.md:581` 的字段注释、`:702` 的 `Frame{now = t_ms / 1000.0}` 回放代码，以及 Python 参考实现 `detectors.py:925, 985` 的 `(now - _t0) * 1000.0` 换算。
- `04-RESEARCH.md:38` 的 C9 表格写作「检测器入参 `now_ms`」，与上述三处冲突；**以秒为准**，只在 `_ms` 后缀的时长字段上使用毫秒。
- `buttons` 用 `Dictionary` 而不是 `Array[String]`，理由写在 `04-RESEARCH.md:585`；选定后必须写进 `mobile/docs/CORE.md`（见第 35 项）。

---

### 2. `mobile/src/core/hit.gd`（model, in-memory）

**Analog:** `mobile/src/core/domain/pulse.gd`（构造器带默认值）+ `domain/skill.gd:39-43`（同一对象上的格式化函数）

**带默认值的位置参数构造器**（`pulse.gd:15-25`）：

```gdscript
var low: float = 0.8
var high: float = 0.0
var duration_ms: int = 120
var gap_ms: int = 0


func _init(p_low := 0.8, p_high := 0.0, p_duration_ms := 120, p_gap_ms := 0) -> void:
	low = p_low
	high = p_high
	duration_ms = p_duration_ms
	gap_ms = p_gap_ms
```

**派生文案放在对象自己的方法里**（`skill.gd:37-43`）：

```gdscript
## 复刻 Python 的 rumble_summary()（config.py:219-223）：两个分支，两种文案。
## 这是用户在设置界面看到的那一行，措辞与小数位数必须与桌面版逐字相同。
func rumble_summary() -> String:
	if pattern.size() == 1:
		var pulse: Pulse = pattern[0]
		return "单震 low=%.2f high=%.2f %dms" % [pulse.low, pulse.high, pulse.duration_ms]
	return "%d 连震" % pattern.size()
```

`Hit` 的字段与文案由 Python 现场生成，见 `detectors.py:990-995`：

```python
                summary = f"两下 {self.button} 间隔 {interval_ms:.0f}ms"
                detail = (f"{summary}（{self._required_label()} 全程按住）")
                self._clear(armed=False)
                self._prev_pressed = pressed
                return Hit(elapsed_ms=interval_ms, detail=detail,
                           summary=summary)
```

> 黄金夹具会**逐字比对** `summary` / `detail`（`04-RESEARCH.md:705`），所以这两个字符串必须由 `Hit` 的构造现场产生，不能在 UI 层重新拼。

---

### 3. `mobile/src/core/failure.gd`（model, in-memory）

**Analog:** `mobile/src/core/config/config_error.gd`

**「机器码 + 中文消息」的对象形状**（`config_error.gd:19-39`）：

```gdscript
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
```

`Failure` 对等字段来自 `detectors.py:49-58`：

```python
@dataclass
class Failure:
    """一次"认出了这次手势、但没做对"的裁定。

    code 是给程序看的（统计用），message 是给用户看的一行中文。
    失败只做文字反馈，绝不触发震动——震动只代表"做对了"。
    """
    code: str
    message: str
    elapsed_ms: float = 0.0
```

写法：`code: StringName`（与 `ConfigError.code` 一致，便于统计键比较）、`message: String`（中文完整句）、`elapsed_ms: float = 0.0`。不照抄 `json_path` / `fix_hint` / `severity`——那三项是配置错误特有的。

---

### 4. `mobile/src/core/outcome.gd`（model, in-memory）

**Analog:** `desktop/padskills/engine.py:62-76`（字段的唯一规格书）

```python
@dataclass
class Outcome:
    """一次尝试的结果（成功或失败），CLI 和 GUI 共用。

    ok=True 时 code 为 "ok"、message 为空；失败时 message 是给用户看的一行原因。
    """
    skill_name: str
    ok: bool
    code: str
    message: str
    elapsed_ms: float
    at: float
    # 成功时的参数摘要（旋转角度 / 保持时长 / 角度范围），失败时为空
    detail: str = ""
```

GDScript 侧只加一个 `seq: int`（移动端「不丢结果」的结构保证，见 `04-RESEARCH.md:603`），字段顺序与默认值照上面。数据对象的写法沿用 `config_result.gd:18-23` 的「公开字段 + 无 getter」风格：

```gdscript
var config: AppConfig = null
var errors: Array[ConfigError] = []
var warnings: Array[ConfigError] = []
var source_path: String = ""
var notice: String = ""
var overrides_applied: bool = false
```

> `at` 是引擎时间轴（秒），`seq` 是单调递增整数；两者都由 `TapRuntime` 写入，`Outcome` 自身不读时钟（core 纯度）。

---

### 5. `mobile/src/core/detectors/detector.gd`（service 基类, request-response）

**Analog:** `desktop/padskills/detectors.py:61-118`

**失败码 → 中文短标签表**（`detectors.py:65-76`，必须整表移植，即使 Phase 4 只用到 3 个）：

```python
    # 给失败统计用的中文短标签
    FAILURE_LABELS = {
        "too_fast": "太快",
        "too_slow": "太慢",
        "too_short": "转得不够",
        "overshoot": "转多了",
        "wrong_start": "起点不对",
        "wrong_end": "终点不对",
        "wrong_direction": "方向反了",
        "stalled": "中途停住",
        "incomplete": "没做完",
        "hold_short": "保持不够",
    }
```

**七个方法的契约**（`detectors.py:78-118`，逐条对照移植）：

```python
    def update(self, frame: Frame) -> Optional[Hit]:
        raise NotImplementedError

    def reset(self) -> None:
        """修饰键松开等情况下强制归零。"""

    def on_idle(self) -> None:
        """右摇杆已安静足够久，作废所有未完成的进度。"""
        self.reset()

    def abandon(self) -> None:
        """这次手势其实属于别的动作：丢掉进度，并且等摇杆回中再重新武装。"""
        self._pending = None
        self.reset()

    def pop_failure(self) -> Optional[Failure]:
        """取出并清空一次失败裁定（一次尝试最多一条）。"""
        failure = getattr(self, "_pending", None)
        self._pending = None
        return failure

    def _emit(self, failure: Failure) -> None:
        # 每个终结路径都会立刻 return，所以一次 update() 里最多走到这里一次。
        # 万一上一条还没被引擎取走，直接覆盖：新的这次更相关。
        self._pending = failure

    def status(self) -> str:
        """给 --trace / GUI 用的实时状态摘要。"""
        return ""

    def observe(self, frame: Frame) -> None:
        """只记下这一帧的摇杆位置，供 status() 提示用；不推进任何判定。"""
```

**GDScript 写法（必须写进类文档）：**
- `class_name Detector` / `extends RefCounted`。
- GDScript 没有 `NotImplementedError` 可捕获语义，也没有 `abstract`；基类方法返回 `null`，子类覆盖。契约写在 `##` 文档里，不靠运行时抛错。
- `var _pending: Failure = null`；`pop_failure() -> Failure` 返回 `null` 表示无。
- `FAILURE_LABELS` 用 `const FAILURE_LABELS := { &"too_fast": "太快", ... }`；`const` 字典在 Godot 4 中是只读的，正好符合查找表用途（参考 `buttons.gd:26` 的 `const ALIASES := {...}`）。
- `on_idle()` 在基类里是 `reset()`，而 `TapDetector` 必须覆盖成**空实现**（见第 6 项）——这是最容易「顺手优化」掉的一条。

---

### 6. `mobile/src/core/detectors/tap_detector.gd`（service, state machine）

**Analog:** `desktop/padskills/detectors.py:858-1034`（唯一规格书，逐行移植）

**状态字段与默认值**（`detectors.py:867-889`）：

```python
    def __init__(self, skill: Skill):
        p = skill.params
        self.button = canonical_button(p.get("button", "X"))
        self.required = tuple(skill.required_buttons)
        self.min_ms = float(p.get("min_interval_ms", 400.0))
        self.max_ms = float(p.get("max_interval_ms", 600.0))
        if self.min_ms < 0:
            raise ValueError(f"动作 {skill.name!r}: min_interval_ms 不能是负数")
        if self.max_ms <= self.min_ms:
            raise ValueError(
                f"动作 {skill.name!r}: max_interval_ms ({self.max_ms:.0f}) "
                f"必须大于 min_interval_ms ({self.min_ms:.0f})"
            )
        self.grace_ms = max(0.0, float(p.get("timeout_grace_ms", 150.0)))
        self.release_hold_ms = max(0.0, float(p.get("release_hold_ms", 120.0)))

        self._now = 0.0
        self._t0: Optional[float] = None       # 第一下按下的时刻
        self._armed = True                     # False = 等按键真正松开再允许重试
        self._prev_pressed = False
        self._have_prev = False
        self._release_since: Optional[float] = None
        self._pending: Optional[Failure] = None
```

**GDScript 对应注意：**
- `Optional[float]` → `var _t0: float = NAN` 或 `var _have_t0 := false`。**不要用 `-1.0` 当哨兵**：`-1.0` 是合法时间戳（AGENTS 的「never return sentinel magic numbers」）。推荐 `_have_t0: bool` + `_t0: float`，并在测试里钉住。
- `canonical_button()` 由 `Buttons.canonical()` 提供，返回空串表示不认（`buttons.gd:47-56`）；core 不抛异常，`TapDetector` 收到的 `Skill` 已经过 `ConfigValidator`，`params.button` 必定合法。
- `min/max` 的合法性已由 `ConfigValidator` 保证（`04-RESEARCH.md:70`）；检测器里**不要**重复抛错，但保留 `max(0.0, ...)` 处理 `timeout_grace_ms`，因为校验器**没有**这条规则（E21 / G13）。

**判定顺序（`detectors.py:949-984`，顺序本身就是语义）：**

```python
    def update(self, frame: Frame) -> Optional[Hit]:
        now = frame.now
        self._now = now
        pressed = self.button in frame.buttons
        if not self._have_prev:
            self._prev_pressed = pressed
            self._have_prev = True
            return None

        rising = pressed and not self._prev_pressed
        mods_ok = all(b in frame.buttons for b in self.required)
        if not mods_ok:
            # 正常情况下引擎不会在这里调用 update()；防御性处理。
            self._prev_pressed = pressed
            return None

        # 成功/失败之后，必须真正松开按键并保持一小段时间，才允许下一次。
        if not self._armed:
            if not pressed:
                if self._release_since is None:
                    self._release_since = now
                elif (now - self._release_since) * 1000.0 >= self.release_hold_ms:
                    self._armed = True
                    self._release_since = None
            else:
                self._release_since = None
            self._prev_pressed = pressed
            return None

        if self._t0 is None:
            if rising:
                self._t0 = now
                self._release_since = None
            self._prev_pressed = pressed
            return None
```

**三条终结路径（`detectors.py:985-1026`，窗口两端都包含、超时严格大于）：**

```python
        interval_ms = (now - self._t0) * 1000.0

        if rising:
            # 第二下：只看两下按下的时间间隔
            if self.min_ms <= interval_ms <= self.max_ms:
                summary = f"两下 {self.button} 间隔 {interval_ms:.0f}ms"
                detail = (f"{summary}（{self._required_label()} 全程按住）")
                self._clear(armed=False)
                self._prev_pressed = pressed
                return Hit(elapsed_ms=interval_ms, detail=detail,
                           summary=summary)

            if interval_ms < self.min_ms:
                self._emit(Failure(
                    "too_fast",
                    f"太快了：两下 {self.button} 只隔了 {interval_ms:.0f}ms"
                    f"（需要 {self.min_ms:.0f}~{self.max_ms:.0f}ms）",
                    interval_ms,
                ))
            else:
                self._emit(Failure(
                    "too_slow",
                    f"太慢了：两下 {self.button} 隔了 {interval_ms:.0f}ms"
                    f"（需要 {self.min_ms:.0f}~{self.max_ms:.0f}ms）",
                    interval_ms,
                ))
            self._clear(armed=False)
            self._prev_pressed = pressed
            return None

        # 一直没有第二下：超过上限再给一点宽限就报"太慢"，不能一直挂着
        if interval_ms > self.max_ms + self.grace_ms:
            self._emit(Failure(
                "too_slow",
                f"太慢了：等了 {interval_ms:.0f}ms 还没有第二下 {self.button}"
                f"（需要在 {self.min_ms:.0f}~{self.max_ms:.0f}ms 内）",
                interval_ms,
            ))
            self._clear(armed=False)

        self._prev_pressed = pressed
        return None
```

**`_clear()` / `observe()` / `reset()` / `on_idle()` / `abandon()` / `status()`（`detectors.py:908-946, 1029-1034`）：**

```python
    def _clear(self, armed: bool) -> None:
        self._t0 = None
        self._release_since = None
        self._armed = armed

    def observe(self, frame: Frame) -> None:
        self._now = frame.now
        self._prev_pressed = self.button in frame.buttons
        self._have_prev = True

    def reset(self) -> None:
        if self._t0 is not None:
            elapsed = max(0.0, (self._now - self._t0) * 1000.0)
            self._emit(Failure(
                "hold_short",
                f"保持不够：中途松开了 {self._required_label()}"
                f"（两下 {self.button} 之间要一直按住）",
                elapsed,
            ))
        self._t0 = None
        self._release_since = None
        # 只有按键已经松开，才允许下一次起手
        self._armed = not self._prev_pressed

    def on_idle(self) -> None:
        # 右摇杆静止与按键动作无关，不能在这里作废进度。
        pass

    def abandon(self) -> None:
        self._pending = None
        self._t0 = None
        self._release_since = None
        self._armed = not self._prev_pressed
```

```python
    def status(self) -> str:
        if self._t0 is None:
            return "待机"
        elapsed = max(0.0, (self._now - self._t0) * 1000.0)
        return (f"已按第一下 {self.button}，等第二下 "
                f"{elapsed:.0f}ms（目标 {self.min_ms:.0f}~{self.max_ms:.0f}）")
```

**移植红线（每条都要有夹具，编号与 `04-RESEARCH.md:552-569` 的 G1–G14 对应）：**
- G1 首帧只记状态，永不产 rising。
- G2 `observe()` 必须更新 `_prev_pressed`（`detectors.py:913-919`）。
- G3 `reset()` 产 `hold_short`，`abandon()` 静默；不能合并。
- G4 `reset()` 用 `_now`（上一帧时间），不是「当前时间」。
- G5 `on_idle()` 必须 no-op。
- G7 四条终结路径都要 `_clear(armed=False)`。
- G8 超时是 `>`，不是 `>=`。
- G9 窗口是 `min <= interval <= max`，两端包含。
- G10 `mods_ok` 为假时**不清 `_t0`**。
- G11 `set_modifier()` 要清 `_t0` / `_release_since` / `_pending` 并按 `_prev_pressed` 重算 `_armed`（`detectors.py:892-903`）。
- G12 `%.0f` 的对等依赖 250 Hz / 4 ms 步长；生成器要为每个 `elapsed_ms` 断言整数。
- G14 `reset()` 只读 `_prev_pressed`，不写。

---

### 7. `mobile/src/core/tap_runtime.gd`（service, orchestration / batch）

**Analog:** `desktop/padskills/engine.py:198-363`（引擎子集；只移植 tap 需要的分支）

**门控顺序**（`engine.py:257-281`）——先 `observe` 再 `reset`，顺序不能反：

```python
        for active in self.skills:
            # 按住了别的动作的修饰键 -> 这个动作今天不参与判定；
            # 静默丢弃半截进度，不能让它过一会儿报"没做完"。
            if (held_required
                    and not any(b in active.skill.required_buttons
                                for b in held_required)):
                active.detector.observe(frame)
                active.detector.abandon()
                continue

            # 相对左摇杆朝向的动作：左摇杆回中时没有方向基准，整段作废。
            if active.skill.relative_to_ls and not ls_ok:
                active.detector.observe(frame)
                active.detector.reset()
                continue

            if not self._buttons_ok(active.skill, state.buttons):
                # 修饰键没按住 -> 该动作的进度作废（例如 L1 松开了就不是 La Croqueta）。
                # 但先把这一帧的摇杆位置记下来：GUI 靠它提示
                # "方向对了，要按住 L1"，比什么都不显示强得多。
                active.detector.observe(frame)
                active.detector.reset()
                continue

            hit = active.detector.update(frame)
```

**命中后的冷却与分组**（`engine.py:285-311`）——冷却吞掉时**静默 `continue`**，不记 Outcome：

```python
            # 这一次手势已经成功了，别的识别器攒下的进度和失败裁定全部作废：
            # 同一次手势不能既报成功又报失败，也不能过一会儿再报"没做完"。
            self._discard_other_claims(active)

            if (now - active.last_fire) * 1000.0 < active.skill.cooldown_ms:
                continue
            if (now - self._last_any_fire) * 1000.0 < self.cfg.global_cooldown_ms:
                self.suppressed += 1
                continue

            active.last_fire = now
            active.hits += 1
            active.attempts += 1
            active.group_hits += 1
            if active.group_hits >= self.GROUP_SIZE:
                active.group_hits = 0
                active.groups_done += 1
            self._last_any_fire = now
            self._record(active, ok=True, code="ok", message="",
                         elapsed_ms=hit.elapsed_ms, now=now,
                         detail=hit.summary)
            self._fire(active, hit, state, now)

            # 一次物理动作只认一个技能；其余识别器等回中后重新开始
            self._gesture_locked = True
            self._lock_release_since = None
            break
```

**失败单槽 drain + 统计**（`engine.py:332-363`）：

```python
    def _drain_failures(self, now: float) -> None:
        owner: Optional[ActiveSkill] = None
        for active in self.skills:
            failure = active.detector.pop_failure()
            if failure is None:
                continue
            # 同一次手势最多一条裁定；先到的（配置里靠前的）留下
            if owner is not None:
                continue
            owner = active
            active.attempts += 1
            active.failures[failure.code] = active.failures.get(failure.code, 0) + 1
            self._record(active, ok=False, code=failure.code,
                         message=failure.message,
                         elapsed_ms=failure.elapsed_ms, now=now)
            if self.feedback or self.verbose:
                self._report_failure(active, failure)

        # 失败也意味着"这次手势结束了"：别的识别器从这段轨迹里攒的进度
        # 同样不能用（例如画弧失败时顺手扫过的"前"，不该再报磕球没做完）。
        if owner is not None:
            self._discard_other_claims(owner)

    def _record(self, active: ActiveSkill, ok: bool, code: str, message: str,
                elapsed_ms: float, now: float, detail: str = "") -> None:
        outcome = Outcome(
            skill_name=active.skill.name, ok=ok, code=code,
            message=message, elapsed_ms=elapsed_ms, at=now, detail=detail,
        )
        active.last_outcome = outcome
        self.last_outcome = outcome
        self.outcome_seq += 1
```

**修饰键判定**（`engine.py:387-393`，all / any 两种模式都要移植）：

```python
    @staticmethod
    def _buttons_ok(skill: Skill, buttons) -> bool:
        if not skill.required_buttons:
            return True
        if skill.button_mode == "any":
            return any(b in buttons for b in skill.required_buttons)
        return all(b in buttons for b in skill.required_buttons)
```

**手势锁**（`engine.py:219-233`）——tap 场景 `rs_mag ≈ 0`，所以命中后固定锁 150 ms；锁定期间**不调用 detector、不 drain**：

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

            if self._gesture_locked:
                self.rumble.update(now)
                return
```

**移动端唯一刻意的改良（必须写进 PLAN 并说明理由）：**
- Python 用 `last_outcome` + `outcome_seq`（`engine.py:355-363`），同一帧两条会静默吞掉第一条。
- 移动端改为 `Array[Outcome]` 队列 + `pop_outcomes() -> Array[Outcome]`：记录时 push，UI 每帧全量 drain。判定集合与 Python 完全一致，只是「不丢」从约定变成结构（`04-RESEARCH.md:603`）。
- **新增硬门**：`layout_confirmed == false` 时 `tick()` 必须直接返回、不产生任何 Outcome。这不是 Python 行为，是成功标准 4 的无头断言（`04-RESEARCH.md:1026`）。它应作为 `TapRuntime` 的第一个早退分支，并由 `test_tap_runtime.gd` 钉死。

---

### 8. `mobile/src/core/device/axis_mapping.gd`（utility, mapping）

**Analog:** `desktop/padskills/input_source.py:116-132`（轴布局形状）+ `:313-325`（只翻转符号、不动索引）

```python
@dataclass
class AxisLayout:
    ls_x: int = 0
    ls_y: int = 1
    rs_x: Optional[int] = 2
    rs_y: Optional[int] = 3
    lt_axis: Optional[int] = 4
    rt_axis: Optional[int] = 5
    lt_button: Optional[int] = None
    rt_button: Optional[int] = None
    invert_ls_y: bool = False
    invert_rs_y: bool = False
    invert_ls_x: bool = False
    invert_rs_x: bool = False
    buttons: Dict[str, int] = field(default_factory=dict)   # 规范名 -> 按键索引
    dpad: Dict[str, Tuple[int, int]] = field(default_factory=dict)  # 名 -> (hat索引, 掩码)
    trigger_rest: float = -1.0    # 扳机轴的静止值：-1.0 表示 -1~1 双极，0.0 表示 0~1 单极
```

```python
def apply_axis_inverts(layout: AxisLayout,
                       invert: Optional[Dict[str, Any]]) -> AxisLayout:
    """把配置里的 {"rs_y": true} 应用到自动推断出的布局上。

    只翻转方向、不动轴索引，所以用户不需要知道轴号就能纠正
    "右摇杆上下反了"这种情况。值写成 false 表示强制不反转，
    可以覆盖 SDL 映射表里的 `~` 号。
    """
    for key, value in (invert or {}).items():
        attr = _INVERT_KEYS.get(str(key).strip().lower())
        if attr is not None:
            setattr(layout, attr, bool(value))
    return layout
```

**GDScript 写法：**
- `class_name AxisMapping` / `extends RefCounted`；字段用 `rs_x_index: int = -1` + `rs_x_sign: int = 1`（`-1` 表示未映射，但 `-1` 也是合法符号，所以**索引用 `-1` 哨兵、符号用 ±1 独立字段**，不要合并成一个「带符号索引」）。
- 派生量按 `04-RESEARCH.md:307-310`：`rs_x` 由「右」步给出，`rs_y` 由「下」步给出（SDL y-down，与 `geometry.gd:38-45` 一致）；**不要**用「上取反」隐式推导 `rs_y`。
- `mapped_axis(raw: PackedFloat32Array, key: StringName) -> float` 这类查询函数返回 `0.0` 表示未映射，且不抛错。

---

### 9. `mobile/src/core/device/calibration.gd`（utility, transform）

**Analog:** `desktop/padskills/input_source.py:328-334`（死区**逐字**移植）

```python
def _deadzone(x: float, y: float, dz: float) -> Tuple[float, float]:
    """带重新缩放的死区处理：角度不变，可用行程被拉满。"""
    m = math.hypot(x, y)
    if m <= dz or m == 0.0:
        return 0.0, 0.0
    scaled = min(1.0, (m - dz) / (1.0 - dz))
    return x / m * scaled, y / m * scaled
```

**扳机归一**（`input_source.py:539-547`）：

```python
    def _trigger_value(self, value: float, button_index: Optional[int], joy: Any) -> float:
        if button_index is not None:
            if 0 <= button_index < self.num_buttons:
                return 1.0 if joy.get_button(button_index) else 0.0
            return 0.0
        rest = self.layout.trigger_rest
        if rest < -0.05:
            return min(1.0, max(0.0, (value - rest) / (1.0 - rest)))
        return min(1.0, max(0.0, value))
```

**归一化顺序（`04-RESEARCH.md:407-418`，顺序不能换）：**

```gdscript
# Calibration.normalize(raw, center, scale, sign) -> float
var centered := raw - center
var normalized := clampf(centered / scale, -1.0, 1.0)
return sign * normalized
```

**红线：**
- **禁止** `Input.get_vector()` / `InputMap` 替代死区（`04-RESEARCH.md:448`）：`get_vector` 会把 magnitude 钳到 1.0 并用圆形死区，斜向推到底时不同位置会越过 `enter_threshold`。
- 死区输出长度 = `scaled` ≤ 1.0：斜向 `(1,1)` 返回 `(0.7071, 0.7071)`、长度 1.0（`x/m` 是单位向量，乘 `scaled` 后长度就是 `scaled`）。
- `scale <= 0` 由上游（探针）拒绝，core 不写除零兜底（`04-RESEARCH.md:417`）。
- 符号最后乘；`sign = +1` = 推右/推下得正（与 `geometry.gd` 的 SDL 约定一致）。
- 调用顺序固定：`raw → 符号/中点/量程 → deadzone → Geometry.angle_of / Geometry.magnitude`（`04-RESEARCH.md:462`）。`geometry.gd` **一行都不改**。

---

### 10. `mobile/src/core/device/device_profile.gd`（model, serialize / validate）

**Analog:** `mobile/src/core/domain/skill.gd:21-34`（已校验数据 + 开放 schema）+ `config/config_validator.gd:865-878`（校验不在构造函数里）

```gdscript
var name: String = ""
var kind: StringName = &""
var enabled: bool = true
var relative_to_ls: bool = false
var required_buttons: Array[String] = []
var button_mode: StringName = MODE_ALL
var params: Dictionary = {}
## 默认**一条** Pulse，对应 Python 的 `(Pulse(),)`（config.py:215）——不是空数组。
## 空数组会让「没写 rumble 的动作」在移动端完全不震，桌面端却震一下。
var pattern: Array[Pulse] = [Pulse.new()]
var cooldown_ms: int = 400
## 开放 schema：原始配置里未识别的 params 键原样留在这里，不报警告、不丢弃。
## 桌面版的 `Skill.raw` 也是这个语义，改动前先看 config.py:217。
var raw: Dictionary = {}
```

```gdscript
static func _fail(out: Array[ConfigError], path: String, code: StringName,
		message: String, fix_hint: String) -> void:
	out.append(ConfigError.new(path, code, message, fix_hint))


## warning 与 error 走同一个对象，只是 severity 不同：它不阻止启动，但必须可见。
static func _warn(warnings: Array[ConfigError], path: String, code: StringName,
		message: String, fix_hint: String) -> void:
	warnings.append(ConfigError.new(path, code, message, fix_hint, ConfigError.SEVERITY_WARNING))


## 把任意 JSON 值变成可读短串（含实际值），错误消息里必须让用户看到收到的是什么。
static func _preview(value: Variant) -> String:
	return JSON.stringify(value)
```

**写法：**
- `DeviceProfile` 只承载**已校验**数据；`from_dict()` 返回一个结果对象（`ProfileResult` 或复用 `ConfigResult` + `ConfigError`），任何字段非法 → **整份丢弃**，不做部分恢复（`04-RESEARCH.md:955`）。
- 数值范围、轴序号上限（`< 8`）、`schema_version`、`key` 非空、`layout` 枚举、`layout_confirmed` 必须是 bool —— 全部在静态 `from_dict()` 里用 `typeof` 先判再转，绝不做无守卫强转（仿 `config_validator.gd:6-13` 的契约）。
- **不存 device index**（E34）；`probed_at_iso` 只作为字符串字段接收，core 不读时钟；墙钟由 `profile_store.gd` 填（`04-RESEARCH.md:390`）。
- `to_dict()` 的键顺序无所谓（JSON 对象语义），但 `ProfileStore` 写入时用 `JSON.stringify(data, "\t", true)`（`config_store.gd:95`）保持与现有文件一致的格式。
- 复用门（`04-RESEARCH.md:334-338`）是一个纯函数：`can_reuse(observed_right_axis: int, observed_right_sign: int) -> bool`；**只有逐项相等才返回 true**，否则整份丢弃。

---

### 11. `mobile/src/core/device/probe_evaluator.gd`（service, sampled-window transform）

**Analog:** `desktop/padskills/input_source.py:258-292`（用统计量分类轴，而不是硬编码索引）

```python
def _layout_from_rest(joy: Any, rest: Sequence[Dict[str, float]]) -> AxisLayout:
    """静止值分类法：中位附近的轴是摇杆，停在极值的是扳机。"""
    lay = AxisLayout()
    lay.buttons = dict(_DEFAULT_XINPUT_BUTTONS)
    lay.dpad = dict(_DEFAULT_DPAD)

    centered: List[int] = []
    extreme: List[int] = []
    for i, stat in enumerate(rest):
        if abs(stat["mean"]) <= 0.25 and (stat["max"] - stat["min"]) < 0.4:
            centered.append(i)
        else:
            extreme.append(i)

    if len(centered) >= 4:
        lay.ls_x, lay.ls_y = centered[0], centered[1]
        lay.rs_x, lay.rs_y = centered[2], centered[3]
    elif len(centered) == 2:
        lay.ls_x, lay.ls_y = centered[0], centered[1]
        lay.rs_x = lay.rs_y = None
    else:
        lay.ls_x, lay.ls_y, lay.rs_x, lay.rs_y = 0, 1, 2, 3

    if len(extreme) >= 2:
        lay.lt_axis, lay.rt_axis = extreme[0], extreme[1]
    elif len(extreme) == 1:
        lay.lt_axis, lay.rt_axis = extreme[0], None
    else:
        lay.lt_axis = lay.rt_axis = None

    if lay.lt_axis is not None and rest[lay.lt_axis]["mean"] < -0.4:
        lay.trigger_rest = -1.0
    else:
        lay.trigger_rest = 0.0
    return lay
```

**这是个 partial analog**：桌面版用「静止值分类」，本阶段用「四步主动推 + argmax」。可复用的是**判定形状**，不是算法本身：
- 所有统计都从 `Array[PackedFloat32Array]` 采样窗口算，函数纯、无时钟（Windows 由调用方切片后传入）；
- 赢家与拒绝理由一起返回（`w`、`sign`、`samples`、`margin`、`separation`）；
- 拒绝是「返回带原因的结果」，不是抛错 —— 与 `ConfigValidator` 的收集式风格一致（`config_validator.gd:6-13`）。
- 交叉校验（`04-RESEARCH.md:294-303`）必须实现为 `ProbeEvaluator.validate_cross(up, right, down, left)` 的纯静态函数；失败时**不清空已有结果**，只返回具体原因。
- `probe_evaluator` 不得读 `Input.` / `Time.`；采样由 `PadSampler` 收集后传入。

---

### 12. `mobile/src/input/pad_sampler.gd`（adapter, event-driven + 每帧对账）

**Analog A（生命周期与 `Input.` 用法）:** `mobile/src/smoke/smoke_screen.gd`

```gdscript
func _ready() -> void:
	# 默认每帧 flush 一次累积输入；关掉它只是为了在轴上「看得见」。
	# 真正的采样契约（事件时间戳、亚帧精度）归 Phase 4，这里不建立任何输入契约。
	Input.use_accumulated_input = false
	Input.joy_connection_changed.connect(_on_joy_changed)
	_load_config()
	_refresh_axes()
```

```gdscript
func _on_joy_changed(_device: int, _connected: bool) -> void:
	_device_ids = Input.get_connected_joypads()
	_refresh_axes()

func _process(_delta: float) -> void:
	# 每帧重读是故意的：成功标准 4 只要求「看得见在动」，事件驱动的采样归 Phase 4。
	_refresh_axes()
```

**Analog B（轮询到语义状态的映射）:** `desktop/padskills/input_source.py:484-537`

```python
    def poll(self) -> PadState:
        pg = self._pygame
        pg.event.pump()          # pygame 靠事件泵刷新手柄状态，必须每轮调用

        joy = self._joy
        lay = self.layout
        raw = [joy.get_axis(i) for i in range(self.num_axes)]

        def axis(idx: Optional[int]) -> float:
            if idx is None or idx < 0 or idx >= len(raw):
                return 0.0
            return raw[idx]

        ls_x = -axis(lay.ls_x) if lay.invert_ls_x else axis(lay.ls_x)
        ...
        pressed: set = set()
        raw_buttons: List[int] = []
        for i in range(self.num_buttons):
            if joy.get_button(i):
                raw_buttons.append(i)
```

**写法约束（RESEARCH 已给设计，`04-RESEARCH.md:175-223`）：**
- `class_name PadSampler` / `extends Node`；放在 `src/input/`，**不**放 `src/app/`（理由见 `04-RESEARCH.md:814-820`）。
- `_input(event)` 只接受 `event.device == _device` 的事件；`InputEventJoypadMotion` → 追加 `MotionSample` 队列；`InputEventJoypadButton` → `_set_button`。
- `_process` 每帧对账 21 个 `JoyButton`，用 `poll_edges` 只统计「轮询补出来的边沿」。
- 两条通道写同一份状态，因此幂等；**不维护两套代码路径**（`04-RESEARCH.md:173`）。
- 不在 `_input` 里调用 `set_input_as_handled()`；节点必须在场景树里；`_input` 是否主线程由 M3 实测，必要时在 `src/input/` 加 `Mutex`（一行）。
- `_input` 里只打时间戳，不做判定；轴的消费者是 core 的 `MotionSample` 队列。
- `PadSampler` 允许 `Input.` / `Time.` / `OS.`；`src/core` 不得 `preload` 它（lint 扩展后强制）。

---

### 13. `mobile/src/input/joy_button_map.gd`（utility, lookup）

**Analog:** `mobile/src/core/domain/buttons.gd:17-56`

```gdscript
const CANONICAL: Array[String] = [
	"A", "B", "X", "Y",
	"LB", "RB", "LT", "RT",
	"LS", "RS", "BACK", "START", "GUIDE",
	"DPAD_UP", "DPAD_DOWN", "DPAD_LEFT", "DPAD_RIGHT",
]

## 别名 → 规范名。键是「已去空格 / 横线 / 下划线并转大写」之后的形态，
## 所以查表前必须先走 canonical() 的归一步骤，否则带分隔符的写法永远查不到。
const ALIASES := {
	# PlayStation 叫法
	"L1": "LB", "L2": "LT", "L3": "LS",
	...
}


## 返回规范名；无法识别时返回空串（core 的约定失败值，由调用方转成 ConfigError）。
static func canonical(value: Variant) -> String:
	var key := str(value).strip_edges().to_upper()
	# 三种分隔符一律剥掉：dpad_up / dpad-up / "dpad up" 都是同一种写法。
	key = key.replace(" ", "")
	key = key.replace("-", "")
	key = key.replace("_", "")
	key = ALIASES.get(key, key)
	# 不在规范表里就是「不认」：返回空串而不是原样返回，避免上层把拼错的串当合法值用。
	return key if key in CANONICAL else ""
```

**写法：**
- 两张 `const` 表：`INDEX_TO_NAME`（`JoyButton` → 17 个规范名）与 `NAME_TO_INDEX`（反向）。索引上界是 `JoyButton.JOY_BUTTON_TOUCHPAD = 20`（`04-RESEARCH.md:186`），所以表只覆盖 0..20。
- 纯静态、无状态、无 `Input.`；因此可以放 `src/input/` 也可以放 core —— 放 `src/input/` 是因为它依赖 `JoyButton` 枚举（`04-RESEARCH.md:801`）。
- 查不到返回空串（与 `Buttons.canonical()` 同一约定），不 `push_error`。
- 与 `desktop/padskills/input_source.py:296-304` 的 `_DEFAULT_XINPUT_BUTTONS` 对照：**只用于「索引 ↔ 规范名」，不用于轴映射**；轴映射完全由探针决定。

---

### 14. `mobile/src/app/profile_store.gd`（adapter, file-I/O + CRUD）

**Analog:** `mobile/src/app/config_store.gd`

**原子写（逐字复用的形状，`config_store.gd:83-103`）：**

```gdscript
## 原子写覆盖层：临时文件 → flush → close → 改名。
## 失败路径要么返回错误码，要么删除临时文件后返回错误码，绝不留半损坏的目标文件。
func save_overrides(data: Dictionary) -> Error:
	var target := _overrides_path
	var temp := target + TEMP_SUFFIX
	# 导出后的 APK 里 res:// 只读；编辑器里能写，所以这一条必须由代码强制。
	if not target.begins_with("user://") or not temp.begins_with("user://"):
		return ERR_UNAUTHORIZED
	var dir_err := DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	if dir_err != OK:
		return dir_err
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t", true))
	# 顺序不能换：先刷到内核再关闭，关闭之后才允许改名。
	file.flush()
	file.close()
	var err := DirAccess.rename_absolute(temp, target)
	if err != OK:
		# 改名前失败时清掉临时文件，否则下次启动会看到一个孤立的 .tmp。
		DirAccess.remove_absolute(temp)
	return err
```

**先取长度再分配（`config_store.gd:147-161`）：**

```gdscript
## bytes 读是 BOM 检测的前提：字符串 API 会在解码时静默剥掉文件头的 EF BB BF。
## 先取长度再读：超限文件在分配内存之前就被拒绝，上限才真的挡得住畸形输入。
static func _read_bytes(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"bytes": PackedByteArray(), "error": ConfigError.new("$", &"file_read_error",
			"无法读取文件 %s（错误码 %d）" % [path, FileAccess.get_open_error()],
			"确认文件存在且当前用户可读。")}
	var length := file.get_length()
	if length > MAX_BYTES:
		file.close()
		return {"bytes": PackedByteArray(), "error": ConfigError.new("$", &"file_too_large",
			"文件 %s 有 %d 字节，超过 %d 字节上限" % [path, length, MAX_BYTES],
			"确认这是配置文件；覆盖层正常大小不到 2 KB。")}
	var bytes := file.get_buffer(length)
	file.close()
	return {"bytes": bytes, "error": null}
```

**`ProfileStore` 的具体差异（不要照抄成 ConfigStore）：**
- 路径常量：`const PROFILES_PATH := "user://profiles/controllers.json"`；`TEMP_SUFFIX := ".tmp"`；`MAX_BYTES := 1_048_576`（沿用 `config_store.gd:25`）。
- 第一句守卫：目标与临时路径都必须以 `user://` 开头，否则 `ERR_UNAUTHORIZED`。
- 读：`FileAccess.get_file_as_bytes` / 先取长度；解析失败或任一条目 schema 非法 → **整份丢弃并返回空档案**（不是逐条恢复），调用方重新探针（`04-RESEARCH.md:955`）。
- 写：整个 `profiles` 字典重写；`JSON.stringify(data, "\t", true)`。
- 不存 device index；`probed_at_iso` 在这里用 `Time.get_datetime_string_from_system()` 填（`04-RESEARCH.md:390`）。
- 测试用注入路径（`ConfigStore.new(base, overrides)` 的做法，`config_store.gd:31-34`），不污染真实用户目录。

---

### 15. `mobile/src/ui/main.gd`（composition root, state switch）

**Analog:** `mobile/src/smoke/smoke_screen.gd:1-43`

```gdscript
extends Control

## 验收面板。这一屏要一次性证明三件事：
##   1) 最长中文串与 ° ± → ✓ ✗ 都能显示（成功标准 2，不是豆腐块）
##   2) res://assets/config/ 的配置真的在包里，且 SKILL_COUNT = 5（成功标准 3）
##   3) 蓝牙手柄的原始轴读数在动（成功标准 4）
##
## Phase 3 之后这一屏会被真正的首屏替换。在此之前它是唯一的验收面板，
## 因此刻意不做样式、不接业务逻辑 —— 可以整体删除，不要把 UI 逻辑长在这里。

@onready var _header: Label = %Header
@onready var _axes: Label = %Axes

var _skill_count := -1
var _device_ids: Array[int] = []

func _ready() -> void:
	Input.use_accumulated_input = false
	Input.joy_connection_changed.connect(_on_joy_changed)
	_load_config()
	_refresh_axes()
```

**写法：**
- `extends Control`，无 `class_name`（UI 文件不污染全局命名空间，参考 `core_runner.gd:14` 的同一理由）。
- 组合根职责：`_ready()` 里 `Input.set_use_accumulated_input(false)`（注意 `smoke_screen.gd:29` 用的是属性写法 `Input.use_accumulated_input = false`，两者等价；RESEARCH 写的是方法名，计划里钉死一种）、`ConfigStore.load_config()`、构建 `PadSampler` / `TapRuntime` / `ProfileStore` 对象图、按状态切屏。
- **零 autoload**（`04-RESEARCH.md:832`）；所有依赖从 `main.gd` 显式注入子屏。
- 状态用 `const STATE_* := &"..."` 而不是 enum（项目既有词汇表做法：`skill.gd:15-19` 的 `KIND_ARC` / `MODE_ALL`）。
- 配置失败 → 复用 `ConfigResult.to_text()` 渲染错误屏（`config_result.gd:31-38`），不在 UI 里解析错误。
- `run/main_scene` 改为 `res://src/ui/main.tscn`；smoke 屏保留为输入体检调试入口（`04-RESEARCH.md:767`）。

---

### 16. `mobile/src/ui/main.tscn`（scene, static layout）

**Analog:** `mobile/src/smoke/smoke_screen.tscn:1-26`

```gdscript
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://src/smoke/smoke_screen.gd" id="1"]

[node name="Smoke" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
script = ExtResource("1")

[node name="Header" type="Label" parent="."]
unique_name_in_owner = true
offset_left = 32.0
offset_top = 32.0
offset_right = 1200.0
offset_bottom = 260.0
theme_override_font_sizes/font_size = 28
```

**写法：**
- 根 `Control` 全屏锚点（`anchors_preset = 15`），子节点用 `unique_name_in_owner = true` 供 `%Name` 访问。
- 字号用 `theme_override_font_sizes/font_size`；本阶段建议 72–96（判定大字）/ 40–48（失败原因）/ 28–32（正文）/ 32（实时数字），依据 `04-RESEARCH.md:769`。
- 不写 `input_devices/buffering/agile_event_flushing`（必须保持 false，`04-RESEARCH.md:766`）。
- 不新增任何触屏控件（C2）。

---

### 17. `mobile/src/ui/onboarding_screen.gd`（component, state machine + render）

**Analog:** `mobile/src/smoke/smoke_screen.gd:67-98`（设备列表 + 状态驱动标签）

```gdscript
func _refresh_axes() -> void:
	_device_ids = Input.get_connected_joypads()
	if _device_ids.is_empty():
		# 安卓蓝牙手柄可能要先按一下键才出现在设备列表里（RESEARCH P14，标 ASSUMED）。
		# 这句话无论真假都该有，成本为零。
		_axes.text = "没有检测到手柄：先按手柄上任意键唤醒"
		return
	var out: PackedStringArray = []
	for d in _device_ids:
		_log_changes(d)
		out.append("#%d  %s" % [d, Input.get_joy_name(d)])
		for axis in range(8):
			out.append("  axis %d = %+.3f" % [axis, Input.get_joy_axis(d, axis as JoyAxis)])
		# 按钮通道也要证明：Phase 4 的修饰键（A/B/X/Y、LB/RB）全部依赖它。
		# 只列「当前按下的索引」而不是全部 32 个，屏幕才不会被按钮刷屏。
		# 这里刻意用 ASCII 文案，避免给字体子集新增字形、把字形闸门弄红。
		var pressed: PackedStringArray = []
		for btn in range(21):
			if Input.is_joy_button_pressed(d, btn as JoyButton):
				pressed.append(str(btn))
		out.append("  buttons: " + (", ".join(pressed) if pressed.size() > 0 else "-"))
	out.append("")
	out.append("  stick/trigger -> axis; A/B/X/Y/LB/RB -> buttons")
	_axes.text = "\n".join(out)
```

**写法（partial：无现成多屏状态机 analog）：**
- S1–S11 的状态用 `const STATE_* := &"..."`；`_process` 只读 `PadSampler` 的快照与探针阶段的结果，**不直接读 `Input.get_joy_axis`**（那会绕开事件通道）。
- 「按任意键」只在设备出现在 `get_connected_joypads()` 后判定；空列表时每帧重读 + `joy_connection_changed`（`04-RESEARCH.md:260`）。
- 探针/校准的子状态、拒绝原因、进度条都由 core 的结果对象驱动；UI 只负责把 `suggestion` / `reject_reason` 显示出来，不重算。
- 文案必须与字形清单同步：新增中文先登记再上屏（`04-RESEARCH.md:502`）。
- **不实现** S11 之外的自动推进 / 组进度 / 音效（Phase 6+）。

---

### 18. `mobile/src/ui/onboarding_screen.tscn`（scene, static layout）

同第 16 项的 scene 形状。每屏一个 `Control` 根 + 若干 `Label` / `ProgressBar` / `Button`（按钮仅作为「已连接设备选择」的兜底，不作为搓招输入）。所有可读文本节点的字号必须 ≥ 28（1 m 支架距离判据，`04-RESEARCH.md:769`）。

---

### 19. `mobile/src/ui/practice_screen.gd`（component, render loop）

**Analog A（结果只消费一次）:** `desktop/padskills/gui.py:600-614`

```python
        if self.engine is not None and self.engine.outcome_seq != self._seen_seq:
            self._seen_seq = self.engine.outcome_seq
            outcome = self.engine.last_outcome
            if outcome is not None:
                self.history.insert(0, (time.strftime("%H:%M:%S"), outcome))
                del self.history[50:]
                max_off = max(0, len(self.history) - self._HISTORY_ROWS)
                self.history_scroll = min(self.history_scroll, max_off)
                mark = "✓" if outcome.ok else "✗"
                if outcome.ok:
                    detail = f" | {outcome.detail}" if outcome.detail else ""
                else:
                    detail = f" — {outcome.message}"
                self._write_log(
                    f"结果 {mark} {outcome.skill_name} {outcome.elapsed_ms:.0f}ms{detail}")
```

**Analog B（重绘节流）:** `desktop/padskills/gui.py:618-620`

```python
        if now - self._last_draw < 1.0 / FPS:
            return
        self._last_draw = now
        self._draw(now)
```

**写法：**
- 每帧 `runtime.pop_outcomes()` **全量 drain**，逐条交给 `result_banner`；不再用 `last_outcome` + `seq` 比较（移动端的队列结构保证不丢，`04-RESEARCH.md:754-756`）。
- S13 的实时毫秒数标签更新**节流到 10 Hz**（`Label.text` 赋值是全帧最贵操作，`04-RESEARCH.md:750`）；节流形状照 `gui.py:618-620`。
- 判定大字 / 失败原因 / 实测间隔全部来自 `Outcome.message` / `elapsed_ms`，UI 不重拼原因。
- 练习屏不直接读 `PadSampler` 内部状态；只读 `TapRuntime.status()` 与 `pop_outcomes()`（保持 core/UI 边界）。
- `layout_confirmed == false` 时不得进入本屏（由 `main.gd` 状态机保证；`TapRuntime` 还有第二道硬门）。

---

### 20. `mobile/src/ui/practice_screen.tscn`（scene, static layout）

同第 16 项。建议节点：`%ActionName`、`%Hint`（「按住 RB，连按两下 X」）、`%LiveMs`（10 Hz）、`%ResultBanner`、`%SuccessCount`。字号按第 16 项。

---

### 21. `mobile/src/ui/result_banner.gd`（component, render）

**无直接 analog。** 语义参考 `gui.py:600-614`：一次 Outcome 只显示一次，靠单调序列号去重。移动端的 `Outcome.seq` 由 `TapRuntime` 分配；banner 维护 `_shown_seq`，只显示比它大的。

**写法：**
- `extends Control`（或 `PanelContainer`），无 `class_name`。
- `show_outcome(outcome: Outcome) -> void`：设置文本与颜色（成功/失败），启动一个停留计时器；**不**自己判断成功/失败的业务含义，只读 `outcome.ok`。
- 不使用 `Tween` 之外的动画；停留时长是本地常量（Phase 6 才做自动推进）。
- 文案模板已在 `Outcome.message` / `detail` 里，banner 不做字符串拼接。

---

### 22. `mobile/tests/unit/test_tap_detector.gd`（test, fixture replay）

**Analog:** `mobile/tests/unit/test_geometry.gd:21-46`

```gdscript
func run(r) -> void:
	var bytes := FileAccess.get_file_as_bytes(GOLDEN_PATH)
	if bytes.is_empty():
		r.check(false, "读不到几何黄金夹具：%s（运行 python3 tools/gen_geometry_golden.py 生成）" % GOLDEN_PATH)
		r.complete()
		return

	var json := JSON.new()
	if json.parse(bytes.get_string_from_utf8()) != OK:
		r.check(false, "几何黄金夹具不是合法 JSON（第 %d 行：%s）"
			% [json.get_error_line() + 1, json.get_error_message()])
		r.complete()
		return

	var data = json.data
	if not (data is Dictionary):
		r.check(false, "几何黄金夹具的根节点必须是对象")
		r.complete()
		return
```

**必须照抄的判据纪律：**
- 用 `FileAccess.get_file_as_bytes` + `JSON.new().parse()`；**不用** `JSON.parse_string`（失败时向 stderr 打 ERROR、不给行号）。
- 读不到 / 解析失败也要走到 `r.complete()`（否则 runner 记成崩溃，掩盖真正原因）。
- 每条用例：`frames` 逐帧构造 `Frame{now = t_ms / 1000.0, buttons = parse("RB+X")}`；`detector.update(frame)` 收 `Hit`；每帧后 `pop_failure()`；`reset()` 之后**也要** `pop_failure()`（`hold_short` 可能来自 reset）。
- `elapsed_ms` 用 `r.eq_float(..., 1e-6, ...)`；`summary` / `detail` / `code` 用精确字符串相等；数组长度精确。
- 规模下限与 id 唯一性照 `test_config_corpus.gd:50-62`：

```gdscript
## 规模与 id 下限：删空语料、丢掉点名用例、复制 id 都必须变红。
func _check_scale(r, cases: Array) -> void:
	r.check(cases.size() >= 4, "语料规模下限：至少 4 条用例（实际 %d）" % cases.size())
	# 03-05 Task 2 把总规模抬到 16：只留 4 条也能通过前一条，删掉大半语料不会被发现。
	r.check(cases.size() >= 16, "语料规模下限：至少 16 条用例（实际 %d）" % cases.size())
	var ids: Dictionary = {}
	for case in cases:
		if typeof(case) == TYPE_DICTIONARY:
			ids[str(case.get("id", ""))] = true
	r.check(ids.size() == cases.size(),
		"每条用例都必须有唯一 id（实际 %d 个 id / %d 条用例）" % [ids.size(), cases.size()])
	for id in REQUIRED_IDS:
		r.check(ids.has(id), "语料必须包含点名用例 %s" % id)
```

本套件的下限按 `04-RESEARCH.md:690`：`cases >= 14`、id 唯一、`kind == "detector"` 至少 5 条。哨兵行 `TAP_GOLDEN_DETECTOR cases=N mismatches=0` 必须在 `r.complete()` **之前**打印；`mismatches` 只统计实际比较过的差异数。

---

### 23. `mobile/tests/unit/test_tap_runtime.gd`（test, fixture replay）

**Analog:** 同第 22 项的 fixture 读取 + `test_config_corpus.gd:50-62` 的规模断言。

**差异：**
- 只消费 `kind == "runtime"` 的用例；`runtime.tick(frame)` → `pop_outcomes()` 累积；最后比对 `outcomes` 与 `counters`。
- `counters` 至少含 `hits` / `attempts` / `group_hits` / `groups_done` / `suppressed`（`04-RESEARCH.md:667`）。
- 必须包含 `rt_two_shots_500`（两发独立）与 `rt_gesture_lock`（锁定期内 0 条额外 Outcome）；逐动作冷却用 `cooldown_ms = 900` 的合成运行时断言（真实 450 ms 下分支不可达）。这两条是防止后人「顺手修好」冷却/锁的钉子。
- 额外硬断言：`layout_confirmed == false` 时 `tick()` 不产任何 Outcome（成功标准 4）。
- 哨兵 `TAP_GOLDEN_RUNTIME cases=N mismatches=0`。

---

### 24. `mobile/tests/unit/test_device_profile.gd`（test, table-driven）

**Analog A（逐字段断言默认值）:** `mobile/tests/unit/test_models.gd:27-38`

```gdscript
func _check_pulse(r) -> void:
	var pulse := Pulse.new()
	r.eq_float(pulse.low, 0.8, TOL, "Pulse.low 默认 0.8")
	r.eq_float(pulse.high, 0.0, TOL, "Pulse.high 默认 0.0")
	r.check(pulse.duration_ms == 120, "Pulse.duration_ms 默认 120（实际 %d）" % pulse.duration_ms)
	r.check(pulse.gap_ms == 0, "Pulse.gap_ms 默认 0（实际 %d）" % pulse.gap_ms)
```

**Analog B（规模 / id 下限）:** `test_config_corpus.gd:50-62`（同上）。

**必须覆盖的矩阵（`04-RESEARCH.md:997` + VALIDATION INPUT-03/04）：**
- `AxisMapping`：给定四组合成 raw 序列，`ProbeEvaluator` 输出 `(index, sign)` 与手推方向一致；上/右同轴、上下不反号、左右不反号、`|delta| < 0.6`、`margin < 0.25`、`samples < 3` 各自被拒绝且原因具体。
- `Calibration`：中点中位数、峰峰值 > 0.15 拒绝、`abs(center) > 0.35` 拒绝、`scale < 0.5` 拒绝、正常样本归一化后的角度依次为 0 / 90 / 180 / 270（±1e-6）。
- `DeviceProfile`：`from_dict` 合法 → `to_dict` 往返逐字段相等；缺 `schema_version`、键类型错、轴序号 ≥ 8、`layout_confirmed` 非 bool → **整份丢弃**。
- 复用门：key 命中但实测 `(axis, sign)` 不符 → 必须 `can_reuse() == false`；相符 → true；**不允许**「部分应用」。
- 无 `JOY_AXIS_` 常量参与映射（另有一条 grep 断言，见第 28 项）。

---

### 25. `mobile/tests/unit/test_pad_sampler.gd`（test, synthetic events）

**Analog:** `mobile/tests/unit/test_config_store.gd:23-37`（有状态 adapter 的套件组织 + 前后清理）

```gdscript
func run(r) -> void:
	_clean()
	_check_default_path(r)
	_check_write_read_merge(r)
	_check_first_run_is_quiet(r)
	_check_res_guard(r)
	_check_atomic_write(r)
	_check_broken_overlay(r)
	_check_too_large_overlay(r)
	_check_overlay_schema_invalid(r)
	_check_base_failures(r)
	_check_stale_hash(r)
	_check_warnings_reach_result(r)
	_clean()
	r.complete()
```

**写法：**
- 直接构造 `PadSampler.new()`，手工喂合成的 `InputEventJoypadMotion` / `InputEventJoypadButton`；不依赖真机。
- 关键用例：同一帧内右→左→右三条 motion 事件，`motion_samples.size()` 必须增加 3 **且顺序不变**（INPUT-05 的唯一机械证据）。
- 事件通道正常时 `poll_edges == 0`；事件通道缺失时轮询补边沿，`poll_edges > 0` 且状态最终一致。
- 设备过滤：`event.device != _device` 的事件必须被丢弃。
- 不测 `_input` 的线程行为（那是 M3 真机项）。
- 测试结束不留下全局状态（`Input.use_accumulated_input` 若被改，需恢复——参考 `test_config_store.gd` 的 `_clean()` 纪律）。

---

### 26. `mobile/tests/fixtures/tap_golden.json`（fixture, generated artifact）

**Analog:** `mobile/tests/fixtures/geometry_golden.json` 的生成物地位（生产者 `tools/gen_geometry_golden.py`，消费者 `mobile/tests/unit/test_geometry.gd`）。

**写法：**
- 目录已有 `.gdignore`（`mobile/tests/fixtures/.gdignore`），不进 PCK、不参与导入。
- 文件**只能**由 `python3 tools/gen_tap_golden.py` 生成；手改即被 `--check` 判红。
- schema 按 `04-RESEARCH.md:633-668`：`schema_version` / `source`（含 `sha256`）/ `meta`（`hz` / `step_ms` / `skill`）/ `cases`。
- `frames` 是全量逐帧 `[t_ms:int, "RB+X"]`，按键按字母序拼；`kind` 只有 `"detector"` / `"runtime"`。
- 规模约 100–140 KB，不压缩（`04-RESEARCH.md:629`）。

---

### 27. `tools/gen_tap_golden.py`（repo tool, generate + `--check`）

**Analog:** `tools/gen_geometry_golden.py`（结构**照抄**）

**路径锚定 + `sys.path` 注入**（`gen_geometry_golden.py:30-40`）：

```python
_REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_REPO_ROOT / "desktop"))

# 只导入几何模块：它零引擎依赖，是几何行为的唯一规格书。
from padskills.geometry import (  # noqa: E402
    angle_diff,
    angle_of,
    magnitude,
    norm_deg,
    signed_delta,
)
```

**规范字节形态**（`gen_geometry_golden.py:116-133`）：

```python
def render(root: Path) -> bytes:
    """夹具的规范字节形态：UTF-8、两空格缩进、键排序、结尾一个换行。

    ``sort_keys`` + 固定 indent 保证「同一份实现 → 同一串字节」，``--check``
    才能做逐字节比较而不是语义比较（语义比较会漏掉键顺序与格式漂移）。
    """
    payload = build_payload(root)
    text = json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    return text.encode("utf-8")


def write_if_changed(path: Path, data: bytes) -> bool:
    """内容相同就不落盘：重复运行不产生 diff，也不白改 mtime。"""
    if path.is_file() and path.read_bytes() == data:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return True
```

**`--check` 逐字节比较**（`gen_geometry_golden.py:153-181`）：

```python
def check(root: Path) -> int:
    """只读校验：重新推导后与磁盘夹具逐字节比较，绝不写盘。"""
    target = fixture_path(root)
    if not target.is_file():
        print(
            f"✗ 缺少几何黄金夹具：{FIXTURE_REL.as_posix()}\n"
            "  运行 python3 tools/gen_geometry_golden.py 生成。",
            file=sys.stderr,
        )
        return 1
    expected = render(root)
    actual = target.read_bytes()
    if expected != actual:
        print(
            f"✗ 夹具与 Python 参考不一致：{FIXTURE_REL.as_posix()}\n"
            f"  {_first_difference(expected, actual)}\n"
            "  夹具是生成物，不能手改；运行 python3 tools/gen_geometry_golden.py "
            "重新生成黄金夹具。",
            file=sys.stderr,
        )
        return 1
    payload = build_payload(root)
    print(
        "✓ 几何黄金夹具与 Python 参考一致"
        f"（angle_of {len(payload['angle_of'])} 条、norm_deg {len(payload['norm_deg'])} 条、"
        f"signed_delta {len(payload['signed_delta'])} 条、angle_diff "
        f"{len(payload['angle_diff'])} 条、magnitude {len(payload['magnitude'])} 条）"
    )
    return 0
```

**`main(argv)` 与 `--root`**（`gen_geometry_golden.py:194-220`）：

```python
def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="gen_geometry_golden.py",
        description="从 desktop/padskills/geometry.py 推导几何黄金夹具",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "示例:\n"
            "  python3 tools/gen_geometry_golden.py           生成 / 刷新夹具\n"
            "  python3 tools/gen_geometry_golden.py --check   只校验，不写盘\n"
        ),
    )
    parser.add_argument(
        "--check", action="store_true", help="只校验夹具是否等于重新推导的结果，不写任何文件"
    )
    parser.add_argument(
        "--root", default=None, help="仓库根目录（默认按脚本位置推导，仅供自测注入）"
    )
    args = parser.parse_args(argv)

    root = Path(args.root).resolve() if args.root else repo_root()
    if not root.is_dir():
        raise SystemExit(f"仓库根目录不存在: {root}")
    if not (root / SOURCE_REL).is_file():
        raise SystemExit(f"✗ 参考实现不存在：{(root / SOURCE_REL).as_posix()}")
    if args.check:
        return check(root)
    return sync(root)
```

**本脚本特有的实现要点：**
- 导入：`from padskills.config import parse_config`、`from padskills.detectors import TapDetector`、`from padskills.engine import Engine`；`input_source.py` 的 pygame 是函数内导入，所以模块级安全（`desktop/padskills/input_source.py:26-32`）。
- 生成器内部定义一个最小的 `_NullSource(GamepadSource)`，照 `desktop/tests/test_detectors.py:646-653`：

```python
class NullSource(GamepadSource):
    """只用于构造引擎；测试里直接手工喂 _tick。"""

    name = "空手柄"
    layout_source = "测试"

    def poll(self) -> PadState:
        return PadState()
```

- 时间轴固定 250 Hz / 4 ms；`frames` 用 `int` 毫秒；每条 `elapsed_ms` 必须是整数（`elapsed_ms.is_integer()`），否则 `raise SystemExit`。
- 期望直接跑参考实现：detector 用例记录每次 `Hit` 与每次 `pop_failure()`；runtime 用例用 `Engine(cfg, _NullSource(), RumbleEngine(None, enabled=False))` 包一层 `_record` 收集**全部** Outcome（只看 `last_outcome` 会漏中间结果）。
- `source.sha256` 覆盖 `detectors.py` / `engine.py` / `shared/skills_config.json`；摘要变化即代表夹具必须重生成。
- 配置用真源：`json.loads((root / "shared/skills_config.json").read_text(encoding="utf-8"))` → `parse_config(...)`，不写第二份配置。

---

### 28. `mobile/tools/test-core.sh`（gate, orchestration）

**Analog:** 自身与 `mobile/tools/gate-a.sh:126-136`（「清单 vs 源文件」必须排在「清单 vs 子集」之前）

**黄金校验位置（`test-core.sh:60-64`）：**

```bash
echo "▸ 校验几何黄金夹具未漂移…"
if ! python3 "$repo_root/tools/gen_geometry_golden.py" --check; then
    echo "  运行 python3 tools/gen_geometry_golden.py 重新生成黄金夹具后再试。" >&2
    exit 1
fi
```

**哨兵位置（`test-core.sh:133-143`，新增哨兵必须在其后）：**

```bash
# 判据是哨兵，不是 $?。没有这一行，解析失败 / class_name 未解析都会一路绿灯。
if ! grep -qE '^TESTS_DONE failures=0$' "$tmp/tests.log"; then
    echo "✗ 没有 TESTS_DONE failures=0（解析 / 编译 / 运行时错误都可能 rc=0）" >&2
    exit 1
fi

# 零断言是另一种假绿：套件全被跳过时同样打印 failures=0。
if grep -qE '^TESTS_ASSERTIONS=0$' "$tmp/tests.log"; then
    echo "✗ TESTS_ASSERTIONS=0：零断言是另一种假绿（套件全被跳过时也会打印 failures=0）" >&2
    exit 1
fi
```

**改动（只加强，不削弱）：**
1. 在 `gen_geometry_golden.py --check` **旁边**（导入之前）加 `python3 tools/gen_tap_golden.py --check`。
2. 在 `TESTS_DONE` / `TESTS_ASSERTIONS` 之后加两条：
   `grep -qE '^TAP_GOLDEN_DETECTOR cases=[1-9][0-9]* mismatches=0$'` 与 runtime 同名。
3. 加 `grep -R "JOY_AXIS_" mobile/src` 为空（INPUT-02 的机械断言）；空结果时 grep 返回 1，注意用 `if grep -R ... ; then exit 1; fi` 或 `! grep -q`。
4. 不改既有判据、不加 `--check-only` 当语法判据（`test-core.sh:21-23` 已说明它 rc=0）。

---

### 29. `mobile/tools/test-core-selftest.sh`（gate selftest, counterexample）

**Analog:** 自身 `:30-70` 的 `make_stub` / `check_red`

```bash
make_stub() {  # $1=名字 $2=--script 分支的正文；返回可执行路径
    local name="$1" body="$2" path="$tmp/$1"
    {
        printf '#!/bin/sh\n'
        printf 'case "$*" in\n'
        printf '  *--script*)\n'
        printf '%s\n' "$body"
        printf '    ;;\n'
        printf '  *)\n'
        printf '    exit 0\n'
        printf '    ;;\n'
        printf 'esac\n'
    } >"$path"
    chmod +x "$path"
    printf '%s' "$path"
}
```

```bash
check_red() {  # $1=用例名 $2=stub 路径 $3=日志里必须出现的失败原因
    local name="$1" stub="$2" reason="$3" log="$tmp/$1.log"
    if GODOT_BIN="$stub" CORE_TEST_TIMEOUT=2 bash "$gate" >"$log" 2>&1; then
        sed 's/^/    /' "$log" >&2
        fail "$name" "闸门返回 0，假绿没有被抓住"
    fi
    if ! grep -qF "$reason" "$log"; then
        sed 's/^/    /' "$log" >&2
        fail "$name" "闸门变红了，但不是因为预期原因（日志缺「${reason}」）"
    fi
    echo "✓ 反例 ${name} 已变红"
}
```

**必须追加的第 5 条反例：** 把 `mobile/tests/fixtures/tap_golden.json` 挪走 → `gen_tap_golden.py --check` 必须非零 → 闸门必须红，且日志含「缺少 … 黄金夹具」。实现上不能直接用 `make_stub`（它替换的是 Godot 可执行文件，而夹具检查在 Godot 之前）；正确做法是：
- 在临时副本里运行闸门，或用 `TAP_GOLDEN_PATH` 可注入路径（若生成器支持 `--root`，可用一个缺少 `tests/fixtures/tap_golden.json` 的临时根）；
- 断言日志含生成器自己的缺失提示，而不是 Godot 的失败。
- 末尾 `SELFTEST_OK cases=6`（`:98` 当前是 `cases=5`）。

---

### 30. `tools/make_font_subset.py`（repo tool, char derivation）

**Analog:** 自身

```python
# 字符来源：整文件扫描所有非 ASCII 字符，不挑行。这样以后往首屏加一句中文，
# 清单与子集自动跟上，不需要有人记得回来改常量。
#   shared/skills_config.json      —— 动作名与 _readme（会直接渲染到练习界面）
#   desktop/padskills/gui.py       —— _ADVICE 里的失败建议文案
#   desktop/padskills/detectors.py —— FAILURE_LABELS 的失败短标签
#   mobile/src/smoke/*             —— 首屏验收面板本身（最长中文串 / 符号 / 轴读数）
CHAR_SOURCES = (
    Path("shared") / "skills_config.json",
    Path("desktop") / "padskills" / "gui.py",
    Path("desktop") / "padskills" / "detectors.py",
    Path("mobile") / "src" / "smoke" / "smoke_screen.gd",
    Path("mobile") / "src" / "smoke" / "smoke_screen.tscn",
)
```

**缺失来源必须报错（`make_font_subset.py:100-108`）：**

```python
    for rel in CHAR_SOURCES:
        path = root / rel
        if not path.is_file():
            raise SystemExit(f"✗ 字符来源不存在：{rel.as_posix()}")
        for ch in path.read_text(encoding="utf-8"):
            if ord(ch) >= 0x80:
                chars.add(ch)
```

**改动：**
- 把 `mobile/src/ui/` 下每个 `.gd` 与 `.tscn` 加入 `CHAR_SOURCES`（新增 8 个文件，见第 15–21 项）。
- 加一条机械断言：`mobile/src/ui/` 下每个 `.gd` 都必须出现在 `CHAR_SOURCES` 里。实现放在 `collect_chars()` 之前（或 `--check` 分支）：
  - `for path in (root / "mobile" / "src" / "ui").rglob("*.gd")`，若 `path.relative_to(root)` 不在 `CHAR_SOURCES` → `SystemExit`，消息列出缺失文件。
  - 该断言必须也在 `--check` 路径执行（否则「清单自洽、源文件漏扫」仍会假绿）。
- PlayStation 文案若出现 `□ △ ○ ⨯`，字形必须来自 `EXTRA_SYMBOLS` 或某个被扫描源文件；`⨯` 用 U+00D7，**不要** U+2A2F（`04-RESEARCH.md:502`）。
- 改完运行 `python3 tools/make_font_subset.py` 并提交三份产物；闸门 A 的 `--check` 会逐字节比对。

---

### 31. `tools/lint_core_purity.py`（repo tool, text scan）

**Analog:** 自身 `:47-67`

```python
RULES: List[Tuple[str, re.Pattern[str]]] = [
    ("input_singleton", re.compile(r"\bInput\s*\.")),
    ("time_singleton", re.compile(r"\bTime\s*\.")),
    ("node_type", re.compile(r"\bNode\b")),
    ("fileaccess_io", re.compile(r"\bFileAccess\b")),
    ("logging", re.compile(
        r"\b(?:print|prints|printt|printerr|print_rich|print_debug|push_error|push_warning)\s*\(")),
    ("os_singleton", re.compile(r"\bOS\s*\.")),
    ("engine_singleton", re.compile(r"\bEngine\s*\.")),
    ("display_server", re.compile(r"\bDisplayServer\b")),
    ("tree_access", re.compile(r"\bget_tree\s*\(")),
    ("scene_tree_type", re.compile(r"\bSceneTree\b")),
    ("resource_loader", re.compile(r"\bResourceLoader\b")),
    ("resource_type", re.compile(r"\bResource\b")),
    ("tool_annotation", re.compile(r"^\s*@tool\b")),
    ("outer_layer_dep", re.compile(
        r"(?:preload|load)\s*\(\s*\"res://src/(?:platform|ui|app)/")),
]

# 这些规则必须看到字符串字面量的内容，所以对 strip_comments() 的结果匹配。
_STRING_AWARE = frozenset({"outer_layer_dep"})
```

**改动：** 把 `outer_layer_dep` 的枚举从 `(?:platform|ui|app)` 扩成 `(?:platform|ui|app|input)`，规则 id 和顺序不变（`04-RESEARCH.md:819`）。这样 `src/core` 不得 `preload("res://src/input/...")` 也由 lint 强制。

---

### 32. `tools/test_lint_core_purity.py`（test, canary）

**Analog:** 自身 `:154-189`

```python
def test_extended_rules_have_teeth() -> None:
    """③ 九条扩展规则各自变红。"""
    cases = {
        ...
        "outer_layer_dep": "const X := preload(\"res://src/app/config_store.gd\")\n",
    }
    ...
    check("preload(res://src/app → outer_layer_dep",
          _rules(cases["outer_layer_dep"]) == ["outer_layer_dep"],
          str(_rules(cases["outer_layer_dep"])))
    check("preload(res://src/core) 不算反向依赖",
          _rules("const X := preload(\"res://src/core/geometry.gd\")\n") == [])
    check("注释里的 preload(res://src/app 不算命中",
          _rules("# 不要写 preload(\"res://src/app/config_store.gd\")\n") == [])
```

**必须追加：**
- `preload("res://src/input/pad_sampler.gd")` → `outer_layer_dep`（新分支有牙齿）。
- `preload("res://src/core/geometry.gd")` 仍 0 命中（不误报）。
- 若改动了规则数量，`test_list_rules_is_stable` 的 `len(lines) == 14` 需要同步；**不要**为了让测试过而放宽前五行顺序断言。

---

### 33. `mobile/tests/core_runner.gd`（test harness, batch）

**Analog:** 自身 `:45-54`

```gdscript
const SUITES := {
	"config_corpus": preload("res://tests/unit/test_config_corpus.gd"),
	"config_loader": preload("res://tests/unit/test_config_loader.gd"),
	"config_store": preload("res://tests/unit/test_config_store.gd"),
	"config_validator": preload("res://tests/unit/test_config_validator.gd"),
	"geometry": preload("res://tests/unit/test_geometry.gd"),
	"models": preload("res://tests/unit/test_models.gd"),
	"overlay_merge": preload("res://tests/unit/test_overlay_merge.gd"),
	"vocabulary": preload("res://tests/unit/test_vocabulary.gd"),
}
```

**改动：** 追加四个显式 `preload`：`tap_detector` / `tap_runtime` / `device_profile` / `pad_sampler`。键按字母序不影响 runner（它自己 `sort()`）；**不要**改成运行时扫描目录（`core_runner.gd:15-17` 已说明扫描目录会在目录消失时「零套件、零失败」地绿）。

---

### 34. `mobile/project.godot`（config, static）

**Analog:** 自身 `:6-15`

```gdscript
[application]

config/name="FIFA 花式动作练习器"
run/main_scene="res://src/smoke/smoke_screen.tscn"
config/features=PackedStringArray("4.7", "GL Compatibility")
; user:// 的目录名必须在产生任何用户数据之前定死。发布之后再改等于把老用户的
; user:// 换成一个空目录（覆盖安装会丢配置）；Phase 9 的覆盖安装依赖它保持不变。
; 显示名仍是上面的中文 config/name —— 那是应用名，不是目录名。
config/use_custom_user_dir=true
config/custom_user_dir_name="FifaSkillTrainer"
```

**改动：**
- `run/main_scene` → `res://src/ui/main.tscn`；smoke 屏保留为调试入口，不删。
- 显式写 `display/window/handheld/orientation=0`（SCREEN_LANDSCAPE）与 `display/window/energy_saving/keep_screen_on=true`（`04-RESEARCH.md:763-764`）。
- `display/window/stretch/mode="canvas_items"` + 基准视口 1280×720（`[ASSUMED]`，真机确认）。
- **不要**写 `input_devices/buffering/agile_event_flushing`（保持 false，`04-RESEARCH.md:766`）。

---

### 35. `mobile/docs/CORE.md`（doc, contract）

**Analog:** 自身 `:41-58`（规则表）与 `:113-129`（加套件 / 加夹具）

```markdown
| 规则 id | 禁止的形状 | 为什么 |
|---------|------------|--------|
| `input_singleton` | `Input.` | 手柄状态是环境输入，必须由调用方采样后作为参数传入 |
| `time_singleton` | `Time.` | 时钟必须显式传入 `now`，否则回放测试不可能确定 |
| `node_type` | `Node` | 场景树类型；core 用 `RefCounted` 承载数据 |
| `fileaccess_io` | `FileAccess` | 读真实文件系统属于 `src/app/config_store.gd` |
...
| `outer_layer_dep` | `preload` / `load` 指向 `res://src/platform|ui|app/` | 依赖方向：`core` 不得反向依赖外层 |
```

```markdown
**加测试套件：**

1. 新文件放 `mobile/tests/unit/test_<主题>.gd`，不加 `class_name`；
2. `run(r)` 的最后一句必须是 `r.complete()` —— runner 靠它识别「套件中途崩了」；
3. 断言用 `r.check(...)` / `r.eq_float(...)`，不要用 `assert`（运行时错误只中止当前函数，
   调用者会继续，assert 失败会让套件静默缺断言）；
4. 在 `mobile/tests/core_runner.gd` 的 `SUITES` 字典里显式 `preload` 注册。
```

**改动：**
- 规则 `outer_layer_dep` 的形状说明加入 `input`（与第 31 项同步；`tools/test_lint_core_purity.py:236-242` 会断言文档列出每个 id）。
- 在「这一层是什么」或新增小节写明：`Frame.buttons` 用 `Dictionary`（canonical_name → true），全仓唯一表示；`Frame.now` 单位是秒；`TapRuntime` 的 `pop_outcomes()` 队列是 UI 唯一的结果入口。
- 在「怎么加套件」补一句：黄金夹具是生成物，先跑生成器再跑套件。

---

### 36. `mobile/ACCEPTANCE.md`（doc, acceptance table）

**Analog:** 自身 `:50-61`（记录字段表）与 `:88-98`（失败怎么记）

```markdown
## 第 2 节 记录字段

每台手机填一份。留空的字段等同于该项未验收。

| 字段 | 手机 A | 手机 B |
|------|--------|--------|
| 厂商（`ro.product.manufacturer`） | | |
| 型号（`ro.product.model`） | | |
| Android 版本（`ro.build.version.release`） | | |
| 截图文件名（`device-smoke-<serial>.png`） | | |
| 验收时间（年月日 时:分） | | |
| 验收人 | | |
```

```markdown
## 第 3 节 失败怎么记

不要写「有点问题」「基本正常」。每一处失败记三件事：

1. **哪一项**（①②③④ 或第 0 节的某条前置条件）；
2. **看到什么**（屏幕上的原文，或「显示为 3 个方框」，逐字抄，不要转述）；
3. **截图文件名**（该手机对应的 `device-smoke-<serial>.png`；必要时补拍一张屏幕照片，
   文件名写进同一格）。
```

**改动：** 新增「第 6 节 Phase 4 真机记录」，字段按 D0–D6：
- 设备身份：`get_joy_name()` / `get_joy_guid()`（逐字）；
- 输入健康：`events_motion` / `events_button` / `poll_edges`、`Δt` p50/p95/max、`_input` 与 `_process` 的 `OS.get_thread_caller_id()`；
- 探针：四步 `(index, sign)`、每步 `samples` / `margin` / `separation`；
- 校准：`center_x/y`、`scale_x/y`、拒绝次数；
- 判定：D4 三条反例各自的原因与实测 ms；D5 两发独立 + 快速右→左→右的 motion 计数；
- 结论只能由人盯着手机屏幕填写，留空 = 未验收（沿用第 2 节纪律）。

---

## Shared Patterns

### 1. core 纯度（适用于第 1–11 项的全部文件）

**来源：** `mobile/docs/CORE.md:11-28` + `tools/lint_core_purity.py:47-64`

- `src/core/**` 不得出现 `Input.` / `Time.` / `Node` / `FileAccess` / `print(` / `OS.` / `Engine.` / `DisplayServer` / `get_tree(` / `SceneTree` / `ResourceLoader` / `Resource` / `@tool`。
- 数据对象一律 `extends RefCounted`；不用 `Resource`（按路径缓存，可变状态跨测试泄漏）。
- 错误/失败只走返回值；不打印、不 `push_error`。
- 时间、设备状态、文件字节全部由参数传入。
- 加完文件后立刻跑 `python3 tools/lint_core_purity.py mobile/src/core`（毫秒级）。

### 2. GDScript 文件与注释惯例（适用于全部新建 `.gd`）

**来源：** `mobile/src/core/domain/skill.gd:1-13`、`mobile/src/core/domain/buttons.gd:1-16`

- 一个文件一个 `class_name`；Tab 缩进；文件头 `##` 中文说明「这是什么、为什么这样、边界在哪」。
- 标识符英文 ASCII、JSON 键 snake_case、用户可见文案中文。
- **不用 enum**：状态/种类用 `const X := &"..."`（`skill.gd:15-19`），因为值来自 JSON、也要出现在错误消息里。
- 私有 helper 单个下划线前缀；纯函数用 `static func`。
- 时长字段 `_ms`、频率 `_hz`；时间戳由调用方注入。

### 3. 结果对象代替异常（适用于 `DeviceProfile.from_dict`、`ProfileStore`、`TapRuntime`）

**来源：** `mobile/src/core/config/config_result.gd:26-38` + `config_error.gd:28-39`

```gdscript
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
```

新结果类型沿用同一形状：`ok()` + `errors: Array[ConfigError]` + `to_text()`；错误对象必须在产生现场填好 `code` / `message` / `fix_hint`，UI 不二次解释。

### 4. 生成物 + `--check` + 正向哨兵（适用于夹具、闸门、字形）

**来源：** `tools/gen_geometry_golden.py:116-133, 153-181`、`mobile/tools/test-core.sh:133-143`、`gate-a.sh:126-136`

- 能由 Python 推导的夹具一律写成生成器 + `--check`；手改即红。
- `--check` 绝不写盘；缺失与不同都返回 1。
- 闸门判据是**正向哨兵**（`TESTS_DONE failures=0` / `GLYPH_OK` / `LINT_OK` / `TAP_GOLDEN_* mismatches=0`），不是「没看到失败」。
- 零断言 / 零用例是另一种假绿，必须单独拦截。

### 5. 原子写与 `user://` 守卫（适用于 `ProfileStore`）

**来源：** `mobile/src/app/config_store.gd:83-103, 147-161`

- temp → `flush()` → `close()` → `rename`；失败清理 temp。
- 第一句守卫目标与 temp 都以 `user://` 开头。
- 先 `get_length()` 再 `get_buffer(length)`，上限 `MAX_BYTES = 1_048_576`。
- 读失败 / 解析失败 / schema 非法 → 整份丢弃，删除文件或返回空档案，不做部分恢复。

### 6. 测试套件纪律（适用于第 22–25 项）

**来源：** `mobile/docs/CORE.md:113-129`、`mobile/tests/unit/test_geometry.gd:1-13`

- 不加 `class_name`；`extends RefCounted`；`run(r)` 最后一句 `r.complete()`。
- 只用 `r.check` / `r.eq_float`，不用 `assert`。
- 读不到夹具也要 `complete()`。
- 套件显式注册进 `core_runner.gd` 的 `SUITES`。
- 每个套件打印自己的正向哨兵，且哨兵在 `complete()` 之前。

### 7. 输入层边界（适用于 `src/input/**`）

- `src/input/` 允许 `Input.` / `Time.` / `OS.` / `Node`；`src/core` 不得 `preload` 它（lint 扩展后强制）。
- `src/input/` 不 import `src/ui`；依赖方向严格单向：`core ← input ← ui`，`app` 只做 I/O。
- `PadSampler` 是唯一碰 `Input.` 的采样器；UI 与 core 都只消费它产出的值 / 事件队列。
- 不硬编码轴序号（INPUT-02）：`mobile/src/` 内 `JOY_AXIS_` 出现次数必须为 0；所有轴由 `AxisMapping` / `DeviceProfile` 提供。

---

## No Analog Found

| 文件 | Role | Data Flow | 原因 / 计划应依据 |
|------|------|-----------|-------------------|
| `mobile/src/core/device/probe_evaluator.gd` | service | sampled-window transform | 仓库里没有「主动四步探针 + argmax + 交叉校验」的实现；只能借 `input_source.py:258-292` 的统计分类形状。算法规格以 `04-RESEARCH.md:280-324` 为准。 |
| `mobile/src/ui/result_banner.gd` | component | render | 没有独立横幅组件；`gui.py:600-614` 只有「结果只消费一次」的语义。组件结构按第 21 项新写。 |

**准无 analog（有结构参考、无同构实现）：**

| 文件 | 可借的部分 | 不能借的部分 |
|------|------------|--------------|
| `mobile/src/input/pad_sampler.gd` | `smoke_screen.gd` 的生命周期与 `Input.` 用法；`input_source.py` 的轮询映射 | 事件优先 + 每帧对账 + `events_*` 计数器是全新的；规格见 `04-RESEARCH.md:171-230` |
| `mobile/src/ui/onboarding_screen.gd` | `smoke_screen.gd` 的状态驱动标签刷新 | S1–S11 的多屏状态机、探针进度、倒计时是全新的；规格见 `04-RESEARCH.md:728-779` |
| `mobile/src/ui/practice_screen.gd` | `gui.py:600-620` 的结果去重与重绘节流 | `pop_outcomes()` 队列、10 Hz 数字节流、`layout_confirmed` 门是移动端新增 |
| `mobile/tests/unit/test_pad_sampler.gd` | `test_config_store.gd` 的有状态 adapter 套件组织 | 合成 `InputEvent` 流、同帧反转保序没有现成测试 |

---

## Planner 必须原样带上的裁决

1. **时间单位**：`Frame.now` 用秒；`elapsed_ms` / `interval_ms` 用毫秒。依据 `04-RESEARCH.md:575-583, 702` 与 `detectors.py:925, 985`。不要按 C9 表格的 `now_ms` 改字段名。
2. **`Frame.buttons` 用 `Dictionary`**（canonical_name → true），并写进 `CORE.md`；不要两套表示并存。
3. **`on_idle()` 在 `TapDetector` 是 no-op**；基类默认 `reset()`，子类必须覆盖成空。
4. **失败单槽是覆盖写**，不是队列；`TapRuntime` 每次 tick 最多 drain 一条（配置顺序第一个 owner）。
5. **冷却吞掉命中时静默 `continue`**，不记 Outcome；`_check_skill_cooldown_silent`（`cooldown_ms = 900` 的合成运行时）就是防止后人「修好」它 —— 真实配置 450 ms 下重新武装 + 最短间隔 = 520 ms，逐动作冷却分支不可达。
6. **`layout_confirmed == false` 不产任何 Outcome**，是 `TapRuntime` 的第一道早退，不是 UI 自觉。
7. **`reset()` 产 `hold_short`，`abandon()` 静默**；两者不可合并。
8. **窗口包含端点、超时严格大于**；`timeout_grace_ms` 不被配置校验器检查，必须 `max(0.0, ...)`。
9. **死区不用 `Input.get_vector()`；角度不变、输出长度 = `scaled` ≤ 1.0**。
10. **profile 复用门只看实测 `(axis, sign)` 逐项相等**；key 命中不足以复用，绝不部分应用。
11. **不存 device index**（官方明确顺序不稳定）；只存 `device_name` / `device_guid` / `axes` / `calibration` / `quality` / `layout` / `layout_confirmed` / `probed_at_iso`。
12. **字体是闭世界**：`src/ui/**` 每个 `.gd` / `.tscn` 都必须登记进 `CHAR_SOURCES`，并由机械断言钉住；先登记再上屏。
13. **`class_name` 撞名风险**：`Frame` / `Hit` / `Failure` / `Outcome` / `Detector` / `Calibration` / `AxisMapping` / `DeviceProfile` / `ProbeEvaluator` 在第一个 Wave 必须先跑 `--import`；撞名改 `DetectFrame` 等，只改 core 内。
14. **不修改 `design/`**；不 `git add -A`；本阶段只写计划内文件。

---

## Metadata

**Analog search scope:** `mobile/src/`、`mobile/tests/`、`mobile/tools/`、`desktop/padskills/`、`desktop/tests/`、`tools/`、`.planning/phases/04-device-input-green-slice/`

**Files scanned:** 30+（core 15 个 `class_name` + 8 个现有套件 + 6 个 mobile 工具 + 6 个 Python 工具 + 3 个 desktop 参考模块）

**Pattern extraction date:** 2026-11-05

**Tracked-source gate:** 所有引用的 analog 均已 `git ls-files` 验证为 tracked source；未引用 `.gsd/` 镜像、`design/` 或任何生成物。

## PATTERN MAPPING COMPLETE
