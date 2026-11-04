# Phase 3: 纯核心地基 — Pattern Map

**Mapped:** 2026-11-05
**Files analyzed:** 21 个路径（编排列表 11 个 + RESEARCH 明确要求但列表遗漏的 10 个）
**Analogs found:** exact/逐字移植 4 · role-match 7 · partial 9 · 无 analog 1

> 所有 analog 路径都已用 `git ls-files -- <path>` 验证为**已跟踪源码**，没有引用任何 `.gsd/` 镜像或生成物。

---

## File Classification

| # | 新/改文件（RESEARCH 规范路径） | 编排列表里的叫法 | Role | Data Flow | Closest Analog | Match Quality |
|---|-------------------------------|------------------|------|-----------|----------------|---------------|
| 1 | `mobile/src/core/geometry.gd` | 同名 | utility（全 static） | transform | `desktop/padskills/geometry.py` | **exact**（逐函数移植） |
| 2 | `mobile/src/core/domain/{pulse,step,skill,input_config,rumble_config,app_config}.gd` | `config_model.gd`（单文件） | model | in-memory | `desktop/padskills/config.py:152-263` | role-match |
| 3 | `mobile/src/core/domain/buttons.gd` | 列表遗漏 | utility | lookup | `desktop/padskills/input_source.py:35-74` | **exact**（逐字移植） |
| 4 | `mobile/src/core/domain/direction_table.gd` | 列表遗漏 | utility | lookup | `desktop/padskills/config.py:103-141` | **exact**（逐字移植） |
| 5 | `mobile/src/core/config/config_error.gd` + `config_result.gd` | 并入 `config_validate.gd` | model | result aggregation | 无直接 analog；文案风格取 `desktop/padskills/config.py` | partial |
| 6 | `mobile/src/core/config/config_loader.gd` | 并入 `config_validate.gd` | service | bytes → model | `desktop/padskills/config.py:775-801` | role-match（BOM 语义是全新的） |
| 7 | `mobile/src/core/config/config_validator.gd` | `config_validate.gd` | service | request-response（校验并收集） | `desktop/padskills/config.py:489-772` | role-match |
| 8 | `mobile/src/core/config/overlay_merge.gd` + `overlay_result.gd` | `config_overlay.gd` | service | merge / transform | **无** | **none** |
| 9 | `mobile/src/app/config_store.gd` | 列表遗漏（只有纯语义的 overlay） | adapter | file-I/O + CRUD | `desktop/padskills/config.py:775-809`；写入形状见 RESEARCH §Code Examples 3 | partial |
| 10 | `mobile/tests/core_runner.gd` | 同名 | test harness | batch（收集后一次退出） | `mobile/tools/check_pack.gd:1-43`、`glyph_coverage.gd:1-80` | partial |
| 11 | `mobile/tests/test_reporter.gd` | 并入 `core_runner.gd` | test utility | collect | `tools/test_sync_config.py:27-39`（Python 版 check/PASS/FAIL） | role-match |
| 12 | `mobile/tests/unit/test_geometry.gd` | `test_geometry.gd` | test suite | table-driven | `tools/test_sync_config.py:55-118` + `check_pack.gd` | partial |
| 13 | `mobile/tests/unit/test_config_loader.gd`、`test_config_validator.gd` | `test_config.gd`（单文件） | test suite | fixture-driven | `tools/test_sync_config.py:55-214` + `check_pack.gd` | partial |
| 14 | `mobile/tests/unit/test_overlay_merge.gd` | `test_overlay.gd` | test suite | pure | `tools/test_sync_config.py:55-214` | partial |
| 15 | `mobile/tools/test-core.sh` | 同名 | shell gate | orchestration | `mobile/tools/gate-a.sh`、`tools/check_desktop.sh` | role-match（看门狗无 analog） |
| 16 | `tools/lint_core_purity.py` | 同名 | repo tool | text scan（batch） | `tools/sync_config.py:39-178` + RESEARCH `strip_code` 原型 | partial |
| 17 | `tools/test_lint_core_purity.py` | 同名 | test | canary / negative-first | `tools/test_sync_config.py` | **exact**（同一套自测文化） |
| 18 | `tools/gen_geometry_golden.py` | **列表遗漏** | repo tool | generate + `--check` | `tools/make_font_subset.py:206-298` | role-match |
| 19 | `tools/check_config_parity.py` | **列表遗漏** | repo tool | cross-language parity | `tools/sync_config.py:107-152` + `test_sync_config.py` | partial |
| 20 | `mobile/tests/fixtures/geometry_golden.json`（RESEARCH 推荐）或 `shared/golden/geometry_vectors.json`（编排列表） | 同名 | fixture | generated artifact | `shared/expected_checks.txt`（生成物 + 摘要闸门） | partial |
| 21 | `mobile/src/ui/error_screen.gd`（RESEARCH 层级）/ `src/app/error_screen.gd`（编排列表） | 同名 | component | render | `mobile/src/smoke/smoke_screen.gd` | partial |

---

## 布局裁决（Planner 必须先读）

### 1. `config_model.gd` / `config_validate.gd` / `config_overlay.gd` 单文件方案不可行

GDScript **一个文件只能有一个 `class_name`**。本机 4.7.2 实测：

```text
SCRIPT ERROR: Parse Error: "class_name" can only be used once.
    at: GDScript::reload (.../two_names.gd:2)
```

而本阶段的类型化容器是硬需求（`Array[Skill]`、`Array[ConfigError]`）。若把 `Skill`、`Step`、`Pulse`、`InputConfig`、`RumbleConfig`、`AppConfig` 全塞进 `config_model.gd`，只有两种结局：

- 内嵌类（`class Skill:`）→ 所有引用变成 `ConfigModel.Skill`，`Array[ConfigModel.Skill]`，且 inner class 不能有 `class_name`；
- 放弃类型化 → 与 RESEARCH §Q6 的「800+ 行全部标注容器类型」冲突。

**结论：采用 RESEARCH 的 `domain/*.gd` + `config/*.gd` 一文件一 `class_name` 布局。** 编排列表里的扁平命名视为「逻辑分组」，不是物理文件名。同理：

- `config_error.gd` / `config_result.gd` / `config_loader.gd` / `config_validator.gd` 必须是四个文件（`ConfigError`、`ConfigResult`、`ConfigLoader`、`ConfigValidator` 四个全局类名）；
- `overlay_merge.gd` 与 `overlay_result.gd` 必须是两个文件；
- `test_reporter.gd` 与 `core_runner.gd` 分开（reporter 用 `preload`，不加 `class_name`；runner 是 `extends SceneTree` 入口）。

### 2. 几何黄金夹具：`shared/golden/` 与 RESEARCH 结论冲突

RESEARCH §Validation Architecture 明确论证：Phase 3 的几何夹具**唯一消费者是 GDScript 测试**，Python 侧只是生成器；放 `shared/` 会逼出「shared → mobile/tests」的第二次同步，等于给生成物再造一份副本。因此规范路径是：

```text
mobile/tests/fixtures/geometry_golden.json
tools/gen_geometry_golden.py          # 仓库根，不在 mobile/
```

若计划阶段坚持 `shared/golden/geometry_vectors.json`，必须同时定义同步/`--check` 机制，否则就是 Phase 1 已经消灭过的「第二份手写真源」。**二选一，不能两边都写。**

### 3. 编排列表遗漏、但成功标准要求的文件

| 缺失文件 | 为什么不能省 | 对应成功标准 |
|----------|--------------|--------------|
| `mobile/src/app/config_store.gd` | DATA-03 要求「写 `user://`、base hash 变则丢弃、绝不写 `res://`」；纯 `config_overlay.gd` 没有 I/O 无法证明 | 成功标准 5 |
| `tools/gen_geometry_golden.py` | 八方向黄金表必须「由 Python 生成」，不能手写；`test-core.sh` 的 `--check` 也要它 | 成功标准 2 |
| `tools/check_config_parity.py` | 同一份 fixture 语料两侧各判一次，把 Python/GDScript 的故意分歧写进 `.expect.json` | 成功标准 3 |
| `mobile/tests/fixtures/.gdignore` + `configs/{valid,invalid}/*.json(.expect.json)` | 坏 JSON 在 `--import` 会刷 ERROR；无 fixture 就没有「注入坏配置」的机械证明 | 成功标准 3 |
| `mobile/tests/test_reporter.gd` | 运行时错误只中止当前函数，`-> int` 崩溃返回 0；没有 `complete()` 标记就无法识别崩掉的套件 | RESIL-03 |
| `mobile/tests/unit/test_config_store.gd` | 原子写 temp+rename、`user://` 前缀守卫需要真实 I/O 测试 | DATA-03 |
| `mobile/docs/CORE.md` | 「零引擎依赖」的可执行定义必须落成文档，lint 规则与文档同源 | INFRA-03 |

### 4. `error_screen` 的层级与范围

- RESEARCH 的 Architectural Responsibility Map 把错误屏定在 **L3 UI（`mobile/src/ui/error_screen.gd`）**，`src/app/` 是 I/O 层。编排列表的 `src/app/error_screen.gd` 与分层冲突。
- 范围仍未锁定（RESEARCH Open Question 3 / A8）：**必须交付** `ConfigResult.to_text()` + headless 断言（四种坏输入的 `json_path`/`code` 都在输出里）；**建议交付**最小 `src/ui/error_screen.gd/.tscn` + 场景实例化测试。完整视觉留 Phase 7。

---

## Pattern Assignments

### 1. `mobile/src/core/geometry.gd`（utility，transform）

**Analog:** `desktop/padskills/geometry.py`（逐字规格书，54 行，全文已读）

**模块头 / 文档字符串**（`geometry.py:1-20`）——中文契约说明 + 英文标识符：

```python
"""角度与向量工具。

本项目全局统一使用如下角度约定（单位：度，范围 [0, 360)）：

    0°   = 上    （朝对方球门，即球员的"正前方"）
    90°  = 右
    180° = 下    （正后方）
    270° = 左

所以角度增大 = 屏幕上的顺时针方向。

手柄原始坐标是 SDL / pygame 约定：x 向右为正，y **向下**为正。
所有角度换算都在 angle_of() 里一次性处理掉，其余代码只跟上面的约定打交道。
"""

__all__ = ["norm_deg", "signed_delta", "angle_diff", "angle_of", "magnitude"]
```

**逐函数移植表**（`geometry.py:23-54`）：

| Python | GDScript | 关键差异 |
|--------|----------|----------|
| `angle % 360.0` | `fposmod(angle, 360.0)` | GDScript 对两个 float 用 `%` 是**解析错误**；`fmod` 保留负号 |
| `((a_to - a_from + 180.0) % 360.0) - 180.0` | `fposmod(a_to - a_from + 180.0, 360.0) - 180.0` | 实际区间是 `[-180, 180)`，`sd(0,180) == -180`；不要「修正」端点 |
| `abs(signed_delta(a, b))` | `absf(signed_delta(a, b))` | `absf` 对 float |
| `math.degrees(math.atan2(x, -y))` | `rad_to_deg(atan2(x, -y))` | **参数顺序仍是 `atan2(y, x)`**，公式文本恰好是 `atan2(x, -y)`；不要写成 `atan2(-y, x)` |
| `math.hypot(x, y)` | `sqrt(x * x + y * y)` | 斜向结果差 1 ulp，比较必须带 `1e-9` 容差 |

**不可省略的居中守卫**（`geometry.py:47-49`）：

```python
if x == 0.0 and y == 0.0:
    return 0.0
return norm_deg(math.degrees(math.atan2(x, -y)))
```

GDScript 目标（RESEARCH §Q3 已实测）：

```gdscript
class_name Geometry
extends RefCounted

## 本项目全局角度约定：0° = 上，90° = 右，180° = 下，270° = 左；范围 [0, 360)。
## 手柄原始坐标是 SDL / Godot 约定：x 向右为正，y 向下为正；只在 angle_of() 里换算一次。


static func norm_deg(angle: float) -> float:
	# 不能用 %：GDScript 对两个 float 使用 % 是解析错误；fmod 会保留负号。
	return fposmod(angle, 360.0)


static func signed_delta(a_from: float, a_to: float) -> float:
	# 与 Python 的实现逐字对应。注意实际区间是 [-180, 180)：
	# 正好 180° 时返回 -180（Python 的 % 是 floor-mod，不是 C 的 fmod）。
	return fposmod(a_to - a_from + 180.0, 360.0) - 180.0


static func angle_diff(a: float, b: float) -> float:
	return absf(signed_delta(a, b))


static func angle_of(x: float, y: float) -> float:
	# 居中守卫：x == 0.0 也覆盖 -0.0；没有它 atan2(0.0, -0.0) 会返回 180°。
	if x == 0.0 and y == 0.0:
		return 0.0
	return norm_deg(rad_to_deg(atan2(x, -y)))


static func magnitude(x: float, y: float) -> float:
	return sqrt(x * x + y * y)
```

**禁止：** `Vector2.angle()` / `Vector2.rotated()`（从 +X 起、y-down；`up` 得 `-π/2`，再 norm 成 270°，整张表逆时针转 90°）。可选的 lint 扩展规则见 §Shared Patterns。

---

### 2. `mobile/src/core/domain/*.gd`（model，in-memory）

**Analog:** `desktop/padskills/config.py:152-263`（`Step` / `Pulse` / `Skill` / `InputConfig` / `RumbleConfig` / `AppConfig`）

**dataclass 形状**（`config.py:152-263`，节选）：

```python
@dataclass(frozen=True)
class Pulse:
    """一次震动。low = 低频大马达(左)，high = 高频小马达(右)，取值 0.0~1.0。"""
    low: float = 0.8
    high: float = 0.0
    duration_ms: int = 120
    gap_ms: int = 0


@dataclass
class Skill:
    """一个花式动作规则。"""
    name: str
    kind: str                                  # "arc" | "sequence" | "taps"
    enabled: bool = True
    relative_to_ls: bool = False
    required_buttons: Tuple[str, ...] = ()
    button_mode: str = "all"                   # "all" | "any"
    params: Dict[str, Any] = field(default_factory=dict)
    pattern: Tuple[Pulse, ...] = (Pulse(),)
    cooldown_ms: int = 400
    raw: Dict[str, Any] = field(default_factory=dict)
```

**GDScript 目标形状**（RESEARCH §Q6「类型化数组/字典」+ Pattern 1）：

```gdscript
class_name Skill
extends RefCounted

# 配置词汇用 StringName 常量，不要为 JSON 字符串造 enum + 双向表。
const KIND_ARC := &"arc"
const KIND_SEQUENCE := &"sequence"
const KIND_TAPS := &"taps"
const MODE_ALL := &"all"
const MODE_ANY := &"any"

var name: String = ""
var kind: StringName = &""
var enabled: bool = true
var relative_to_ls: bool = false
var required_buttons: Array[String] = []
var button_mode: StringName = MODE_ALL
var params: Dictionary = {}
var pattern: Array[Pulse] = []
var cooldown_ms: int = 400
var raw: Dictionary = {}
```

**必须重新设计的 Python 语义：**

| Python | GDScript 现实 | 计划动作 |
|--------|---------------|----------|
| `@dataclass` 自动生成 `__init__` | 必须手写 `_init(...)` 或逐字段赋值 | 给 `Pulse`/`Step` 写带参数 `_init`；`Skill` 由 validator 构造 |
| `field(default_factory=dict/list)` | 类字段默认值在 GDScript 里是**每个实例独立**的（`var a: Array = []` 可用） | 直接写 `var params: Dictionary = {}` |
| `frozen=True` | 无强制不可变 | 约定 + 边界处 `duplicate(true)`；不要宣称「不可变」 |
| `Tuple[str, ...]` | 无 tuple | `Array[String]`；数组是引用类型，对外返回前 `.duplicate()` |
| `Optional[Path]` | 无 pathlib；`String` 路径 | 用 `""` 表示「无」，或 `Variant` + `typeof` 判定 |
| `Optional[float]`（如 `start_target`） | `float` 不能为 null | 用 `Variant`（`null` 或 float）或 `has_start_target: bool` + float |
| `AppConfig.enabled_skills()` | 普通方法即可 | 返回**新数组**，不要泄漏内部引用 |

**不要**在 model 里做校验（`__post_init__` 在 Python 里也没用；本项目约定校验集中在 `_parse_*`）。所有非法值由 `ConfigValidator` 拦截，model 只承载已校验数据。

---

### 3. `mobile/src/core/domain/buttons.gd`（utility，lookup）

**Analog:** `desktop/padskills/input_source.py:35-74`（逐字移植）

```python
CANONICAL_BUTTONS: Tuple[str, ...] = (
    "A", "B", "X", "Y",
    "LB", "RB", "LT", "RT",
    "LS", "RS", "BACK", "START", "GUIDE",
    "DPAD_UP", "DPAD_DOWN", "DPAD_LEFT", "DPAD_RIGHT",
)

BUTTON_ALIASES: Dict[str, str] = {
    # PlayStation 叫法
    "L1": "LB", "L2": "LT", "L3": "LS",
    "R1": "RB", "R2": "RT", "R3": "RS",
    # ... 共 52 条，逐条抄，不要只抄「常用键」
}


def canonical_button(value: Any) -> str:
    key = str(value).strip().upper()
    for ch in (" ", "-", "_"):
        key = key.replace(ch, "")
    key = BUTTON_ALIASES.get(key, key)
    if key not in CANONICAL_BUTTONS:
        raise ValueError(
            f"无法识别的按键名 {value!r}。可用规范名: {', '.join(CANONICAL_BUTTONS)}；"
            f"也接受别名如 L1/R1/L2/R2/L3/R3、SHARE/OPTIONS。"
        )
    return key
```

**GDScript 形状：**

```gdscript
class_name Buttons
extends RefCounted

const CANONICAL: Array[String] = [
	"A", "B", "X", "Y",
	"LB", "RB", "LT", "RT",
	"LS", "RS", "BACK", "START", "GUIDE",
	"DPAD_UP", "DPAD_DOWN", "DPAD_LEFT", "DPAD_RIGHT",
]

const ALIASES := {
	"L1": "LB", "L2": "LT", "L3": "LS",
	# ...
}


## 返回规范名；无法识别时返回空串，由调用方生成 ConfigError（core 不抛异常）。
static func canonical(value: Variant) -> String:
	var key := str(value).strip_edges().to_upper()
	for ch in [" ", "-", "_"]:
		key = key.replace(ch, "")
	key = ALIASES.get(key, key)
	return key if key in CANONICAL else ""
```

**关键差异：** Python 用 `raise ValueError` 让上层拼路径；GDScript 不能抛异常（运行时错误不可捕获且会中止当前函数），所以要么返回空串、要么返回 `{value, error}`。推荐返回空串，校验器负责生成带 `json_path` 的 `ConfigError`。

**测试要求：** 至少覆盖 `L1→LB`、`R2→RT`、`TRIANGLE→Y`、`dpad_up→DPAD_UP`（下划线剥除）、`"A"→"A"`、`"nope"→""`。`shared/skills_config.json` 里实际出现 `L1`/`RB`/`X`/`RT`。

---

### 4. `mobile/src/core/domain/direction_table.gd`（utility，lookup）

**Analog:** `desktop/padskills/config.py:103-141`

```python
DIRECTION_ALIASES: Dict[str, float] = {
    "up": 0.0, "forward": 0.0, "fwd": 0.0, "front": 0.0, "north": 0.0,
    "前": 0.0, "上": 0.0, "正前": 0.0, "前方": 0.0,
    "upright": 45.0, "forwardright": 45.0, "前右": 45.0, "右上": 45.0,
    # ... 共 47 条，逐条抄
}


def resolve_direction(value: Any) -> float:
    if isinstance(value, bool):  # bool 是 int 的子类，先挡掉
        raise ValueError(f"方向不能是布尔值: {value!r}")
    if isinstance(value, (int, float)):
        return norm_deg(float(value))
    key = str(value).strip().lower()
    for ch in ("_", "-", " ", "\t"):
        key = key.replace(ch, "")
    if key in DIRECTION_ALIASES:
        return DIRECTION_ALIASES[key]
    try:
        return norm_deg(float(key))
    except ValueError:
        raise ValueError(f"无法识别的方向 {value!r}。可用名称: ...") from None
```

**GDScript 目标：** `static func resolve(value: Variant) -> Variant`，成功返回 `float`，失败返回 `null`（或 `{angle, code}`）。必须：

1. 先 `typeof(value) == TYPE_BOOL` → 拒绝（`bool` 在 GDScript 里不是 int，但仍要单独挡，避免 `float(true)=1.0`）；
2. 数值接受 `TYPE_INT | TYPE_FLOAT`；
3. 字符串流程：`strip_edges().to_lower()` → 去掉 `_ - space tab` → 查表 → 尝试 `float()`；
4. 失败返回 `null`，**不要** `push_error`。

`direction_name()` **不移植**（RESEARCH Open Question 5）；Phase 3 的错误消息只需要 `direction_unknown`。

---

### 5. `mobile/src/core/config/config_error.gd` + `config_result.gd`（model，result aggregation）

**Analog:** 无 GDScript 先例。字段与文案契约来自 `desktop/padskills/config.py` 的中文错误消息（`config.py:554-745`），聚合思路来自 `tools/sync_config.py:107-152` 的 collect-then-report。

**目标形状**（RESEARCH §Q4 已给，逐字引用）：

```gdscript
class_name ConfigError
extends RefCounted

const SEVERITY_ERROR := &"error"
const SEVERITY_WARNING := &"warning"

var json_path: String      # "skills[3].params.max_duration_ms"；根用 "$"
var code: StringName       # &"number_expected" / &"bom_detected" / ...
var message: String        # 中文，人能看懂，含实际值
var fix_hint: String       # 中文，告诉用户改哪里、改成什么
var severity: StringName   # &"error" | &"warning"

func _init(p_path: String, p_code: StringName, p_message: String,
		p_fix_hint: String, p_severity: StringName = SEVERITY_ERROR) -> void:
	json_path = p_path
	code = p_code
	message = p_message
	fix_hint = p_fix_hint
	severity = p_severity

func format_line() -> String:
	return "[%s] %s: %s（%s）" % [code, json_path, message, fix_hint]
```

```gdscript
class_name ConfigResult
extends RefCounted

var config: AppConfig                 # 有 error 时为 null
var errors: Array[ConfigError] = []
var warnings: Array[ConfigError] = []
var source_path := ""
var notice := ""
var overrides_applied := false

func ok() -> bool:
	return errors.is_empty() and config != null

func to_text() -> String:
	var lines: PackedStringArray = []
	for e in errors:
		lines.append(e.format_line())
	for w in warnings:
		lines.append(w.format_line())
	return "\n".join(lines)
```

**文案风格必须照抄 Python 的「字段路径 + 实际值 + 下一步」：**

```python
raise ValueError(
    f"动作 {name!r} 的 type 必须是 'arc'、'sequence' 或 'taps'，"
    f"收到 {raw.get('type')!r}"
)
```

GDScript 改写（RESEARCH §Pattern 2 已给）：

```gdscript
out.append(ConfigError.new(path + ".type", &"skill_type_invalid",
	"type 必须是 'arc'、'sequence' 或 'taps'，收到 %s" % JSON.stringify(dict.get("type")),
	"改成三种之一；拼写和大小写都要对。"))
```

**`to_text()` 是 RESIL-02 的最小机械证明**：四种坏输入的 `json_path` + `code` 必须出现在输出里，测试直接断言字符串包含关系即可，不需要 UI。

---

### 6. `mobile/src/core/config/config_loader.gd`（service，bytes → model）

**Analog:** `desktop/padskills/config.py:775-801`（`load_config` 的结构：读 → JSON 语法错误 → 语义错误），但**必须去掉 `SystemExit`**。

Python 现状（反面教材，`config.py:775-801`）：

```python
def load_config(path: Optional[Path] = None) -> AppConfig:
    ...
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        raise SystemExit(f"读取配置文件失败: {path}\n  {exc}") from None

    try:
        data = json.loads(text)
    except json.JSONDecodeError as exc:
        raise SystemExit(
            f"配置文件 JSON 语法错误: {path}\n"
            f"  第 {exc.lineno} 行 第 {exc.colno} 列: {exc.msg}\n"
            f"  提示：JSON 不支持 // 注释，也不允许最后一个元素后面多写逗号。"
        ) from None
```

**GDScript 目标**（RESEARCH §Code Examples 1，已实测）：

```gdscript
class_name ConfigLoader
extends RefCounted

## 配置加载的唯一入口。core 不读文件：调用者（ConfigStore / 测试）传 bytes。
## 使用 JSON.new().parse() 而不是 JSON.parse_string()：后者失败时会向 stderr 打 ERROR。

static func parse_bytes(bytes: PackedByteArray, source_path := "") -> ConfigResult:
	if bytes.size() >= 3 and bytes[0] == 0xEF and bytes[1] == 0xBB and bytes[2] == 0xBF:
		# bom_detected
	...
	var text := bytes.get_string_from_utf8()
	if text.is_empty():
		# invalid_utf8
	...
	return parse_text(text, source_path)
```

**铁律：**

- 入口是 `PackedByteArray`，**绝不**用 `FileAccess.get_file_as_string()`（会静默剥 BOM，P4）；
- `JSON.new().parse(text)`，**绝不**用 `JSON.parse_string()`（失败时向 stderr 打 ERROR，P5）；
- 错误行 `json.get_error_line() + 1`（0 基）；
- `decode_bytes()` 返回 `{data, error}`，供 `ConfigStore` 在合并 overlay 前拿原始字典；`parse_bytes()` = decode + validate。

---

### 7. `mobile/src/core/config/config_validator.gd`（service，validate/collect）

**Analog:** `desktop/padskills/config.py:489-772`（规则与文案的规格书）

**必须逐条移植的规则（路径 → 规则）：**

| Python 位置 | 规则 | GDScript 目标 code |
|-------------|------|--------------------|
| `config.py:489-496` | 0..1 范围 | `out_of_range` |
| `config.py:499-525` | rumble 单对象/数组/`pattern`；item 是对象；low/high 0..1 | `rumble_invalid` / `rumble_pattern_empty` / `rumble_item_not_object` |
| `config.py:528-538` | `required_button` 规范化；`button_mode` 只能是 all/any | `button_unknown` / `button_mode_invalid` |
| `config.py:541-551` | `idle_timeout_ms`、`release_hold_ms` 非负；`idle_timeout_ms > 0`；`motion_min_delta_deg > 0` | `negative_value` / `must_be_positive` |
| `config.py:554-568` | skill 是对象；type ∈ {arc,sequence,taps}；params 是对象 | `skill_not_object` / `skill_type_invalid` / `params_not_object` |
| `config.py:570-596` | sequence：steps 非空；逐步 parse；`max_duration > min_duration`；`sum(hold) < max_duration` | `steps_empty` / `max_not_greater_than_min` / `hold_sum_exceeds_max` |
| `config.py:598-622` | arc：`max_angle > min_angle`；时长窗口；`start_angle`/`end_angle`/`end_angles` 非空且可解析 | `max_not_greater_than_min` / `direction_unknown` / `start_angle_not_scalar` |
| `config.py:624-653` | taps：`button` 规范化；`min_interval >= 0`；`max > min`；`modifier_options` 非空/规范/不重复 | `button_unknown` / `max_not_greater_than_min` / `modifier_*` |
| `config.py:655-670` | modifier_options 必须同时有 required_button；required_button 必须在 options 里 | `modifier_requires_required_button` / `required_button_not_in_options` |
| `config.py:686-726` | input：对象；deadzone/ls_facing/trigger 0..1；axis_layout 对象或 null；invert 键白名单 + bool 值；button_names 对象或 null | `input_not_object` / `invert_*` / `axis_layout_not_object` |
| `config.py:729-745` | rumble 配置：backend 五选一；startup_test_strength 0..1 | `rumble_backend_invalid` / `out_of_range` |
| `config.py:748-772` | 根是对象；skills 非空数组；重复 name | `root_not_object` / `skills_empty` / `duplicate_skill_name` |

**收集而非抛出**（RESEARCH §Pattern 2）：

```gdscript
static func _validate_skill(raw: Variant, index: int, out: Array[ConfigError]) -> Skill:
	var path := "skills[%d]" % index
	if typeof(raw) != TYPE_DICTIONARY:
		out.append(ConfigError.new(path, &"skill_not_object",
			"每个动作必须是 JSON 对象", "用 { } 包住一个动作"))
		return null
	var dict: Dictionary = raw
	var kind := str(dict.get("type", "")).strip_edges().to_lower()
	if kind not in ["arc", "sequence", "taps"]:
		out.append(ConfigError.new(path + ".type", &"skill_type_invalid",
			"type 必须是 'arc'、'sequence' 或 'taps'，收到 %s" % JSON.stringify(dict.get("type")),
			"改成三种之一；拼写和大小写都要对。"))
		return null                       # 只跳过依赖 type 的子树，外层继续下一个 skill
	# ...
	return null
```

**类型严格化（与 Python 的故意分歧，必须写进 `.expect.json`）：**

| 输入 | Python 行为 | GDScript 目标 | code |
|------|-------------|---------------|------|
| `"enabled": "false"` | `bool("false") == True`，静默接受 | **拒绝** | `bool_expected` |
| `"min_duration_ms": null` | `float(None)` → TypeError（未捕获） | **拒绝** | `number_expected` |
| `"min_duration_ms": "250"` | `float("250")` 接受 | **拒绝**（A2） | `number_expected` |
| `"start_angle": [90, 180]` | `parse_config` 接受，构造 `ArcDetector` 才崩 | **拒绝** | `start_angle_not_scalar` |
| `"direction": "clockwisee"` | 静默落到 `any` | **拒绝**（A3） | `direction_unknown` |
| `poll_hz: 5000` | 静默 clamp 到 1000 | **warning** + 应用截断值 | `out_of_range` |
| `cooldown_ms: -5` | 静默 clamp 到 0 | **warning** + 应用 0 | `negative_value` |

**每个字段先 `typeof`，再转换：** `float(true)=1.0`、`float("3.5")=3.5`、`bool("false")=true`、`float(null)` 运行错误（只中止当前函数，调用者继续，P10）。数值接受 `TYPE_INT | TYPE_FLOAT`（JSON 整数解析成 float，P11）。

**重复 name 的路径：** 给每一处重复都报一条 `duplicate_skill_name`，消息里点名第一次出现的位置（`config.py:759-764` 只报一次，GDScript 应更利于修复）。

---

### 8. `mobile/src/core/config/overlay_merge.gd` + `overlay_result.gd`（service，merge）

**Analog:** **无。** 这是整个 Phase 3 唯一没有先例的纯语义模块。不要从 `desktop/padskills/config.py` 类推「覆盖层」——桌面版没有 overlay。直接采用 RESEARCH §Code Examples 2 的实现：

```gdscript
class_name OverlayMerge
extends RefCounted

const SCHEMA_VERSION := 1
const ALLOWED_KEYS := [&"enabled", &"required_button", &"button_mode"]


static func merge(base: Dictionary, overlay: Dictionary,
		current_base_sha256: String) -> OverlayResult:
	var result := OverlayResult.new()
	result.data = base.duplicate(true)       # 绝不修改调用者的 base

	var schema = overlay.get("schema_version")
	if typeof(schema) != TYPE_INT and typeof(schema) != TYPE_FLOAT:
		return result._discard(&"overlay_schema_invalid",
			"自定义设置缺少有效的 schema_version，已恢复默认。")
	if int(schema) > SCHEMA_VERSION:
		return result._discard(&"overlay_schema_too_new",
			"自定义设置来自更新的版本，已恢复默认。")

	var hash_value = overlay.get("base_sha256")
	if typeof(hash_value) != TYPE_STRING or \
			String(hash_value).to_lower() != current_base_sha256.to_lower():
		return result._discard(&"overlay_base_changed",
			"配置已更新，已丢弃自定义按键设置。")
	# ... skills 必须是对象；按 skill name 查 by_name；白名单键；未知键 warning
```

**必须固化的语义（测试逐条对应）：**

1. 缺 `schema_version` / 非数字 → 整体丢弃 `overlay_schema_invalid`；
2. `int(schema) > 1` → 整体丢弃 `overlay_schema_too_new`（未来版本不猜）；
3. `base_sha256` 不是字符串或不匹配（忽略大小写）→ 整体丢弃 `overlay_base_changed` + `notice = "配置已更新，已丢弃自定义按键设置。"`；
4. `skills` 不是对象 → 整体丢弃；每个 key 必须是 base 里存在的 skill name，否则 **warning** `overlay_skill_unknown` 并忽略该条；
5. 每个 skill 值必须是对象；只应用 `enabled` / `required_button` / `button_mode`；未知键 **warning** `overlay_key_unknown`；
6. **深拷贝** base（`duplicate(true)`），绝不修改入参；
7. 丢弃后由 `ConfigStore` 删除 `user://config/overrides.json`，只提示一次。

**`OverlayResult` 形状：**

```gdscript
class_name OverlayResult
extends RefCounted

var data: Dictionary = {}
var warnings: Array[ConfigError] = []
var applied := false
var discarded_reason: StringName = &""
var notice := ""

func _discard(reason: StringName, p_notice: String) -> OverlayResult:
	discarded_reason = reason
	notice = p_notice
	applied = false
	return self
```

**注意：** `overlay` 的键来自 JSON，是 `String`；`ALLOWED_KEYS` 是 `StringName`。本机实测 `String` / `StringName` 作为字典键可互换，`StringName(key) not in ALLOWED_KEYS` 可以正常工作。

---

### 9. `mobile/src/app/config_store.gd`（adapter，file-I/O）

**Analog:** `desktop/padskills/config.py:775-809`（读配置 / 写默认配置的职责划分）+ RESEARCH §Code Examples 3（GDScript I/O 形状）。

Python 侧可借鉴的只有「读写分离 + 写失败可降级」：

```python
def ensure_user_config(path: Optional[Path] = None) -> Path:
    ...
    if not path.exists():
        try:
            path.parent.mkdir(parents=True, exist_ok=True)
            dump_default_config(path)
        except OSError:
            # 写不进去就退回内置默认配置，至少还能跑
            pass
    return path
```

**GDScript 目标（RESEARCH §Code Examples 3，已实测）：**

```gdscript
class_name ConfigStore
extends RefCounted

const BASE_PATH := "res://assets/config/skills_config.json"
const OVERRIDES_DIR := "user://config"
const OVERRIDES_PATH := "user://config/overrides.json"
const TEMP_PATH := "user://config/overrides.json.tmp"
const MAX_BYTES := 1_048_576

func load_config() -> ConfigResult:
	# 1) bytes 读 base；2) FileAccess.get_sha256(base)；3) decode_bytes 拿原始 Dictionary
	# 4) 可选 overlay：bytes 读 → decode → OverlayMerge.merge → 丢弃则 remove_absolute
	# 5) ConfigValidator.validate(合并后的 dict)；result.notice = notice
	...
```

**写入形状（temp + flush + close + rename）：**

```gdscript
func save_overrides(data: Dictionary) -> Error:
	var target := _overrides_path
	var temp := target + ".tmp"
	if not target.begins_with("user://") or not temp.begins_with("user://"):
		return ERR_UNAUTHORIZED           # 生产路径必须是 user://；绝不尝试写 res://
	var dir_err := DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	if dir_err != OK:
		return dir_err
	var f := FileAccess.open(temp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(data, "\t", true))
	f.flush()
	f.close()
	return DirAccess.rename_absolute(temp, target)
```

**必须保留的安全属性：**

- 写入路径是常量 `user://config/overrides.json`，入口 `begins_with("user://")` 守卫返回 `ERR_UNAUTHORIZED`；
- 读取一律 `get_file_as_bytes()`（BOM 检测的前提）；
- `MAX_BYTES = 1_048_576`，超限直接 `file_too_large`，不解析；
- base hash 用 `FileAccess.get_sha256(base_path)`，**不要**用 `.sha256` sidecar（可能过期/被手改）；
- 首启没有 overlay 文件是正常状态：不创建空文件、不报错；
- 丢弃 overlay 后 `DirAccess.remove_absolute()`，只提示一次。

---

### 10. `mobile/tests/core_runner.gd`（test harness，batch）

**Analog（部分）：** `mobile/tools/check_pack.gd:1-43` 与 `mobile/tools/glyph_coverage.gd:1-80`

两者都给出了仓库里的 `extends SceneTree` 入口形状：

```gdscript
extends SceneTree

## 从导出的 PCK 里把配置与 sidecar 读回来，证明它们真的在包里 ——
## 而不是从工程目录里读到（那就是闸门 A 的假绿）。
## 用法：godot --headless --main-pack <pck> --script res://tools/check_pack.gd
## 必须**不带** --path：带 --path 时 res:// 指向工程目录，读到的不是导出物。

const CONFIG_PATH := "res://assets/config/skills_config.json"

func _initialize() -> void:
	var failures: Array[String] = []
	# ... 逐条 append
	if failures.is_empty():
		print("PACK_OK skills=%d" % EXPECTED_SKILLS)
		quit(0)
	else:
		for f in failures:
			printerr("PACK_FAIL " + f)
		quit(1)
```

`glyph_coverage.gd:61-80` 的 `_fail()` 也值得抄：

```gdscript
	if missing.is_empty():
		print("GLYPH_OK chars=%d" % checked)
		quit(0)
	else:
		printerr("GLYPH_MISSING %d: %s" % [missing.size(), "".join(missing)])
		quit(1)

func _fail(message: String) -> void:
	printerr(message)
	quit(1)
```

**本阶段必须新增、仓库里没有的部分：**

- `TestReporter`（`tests/test_reporter.gd`，`extends RefCounted`，**不加 `class_name`**）：

```gdscript
extends RefCounted

var assertions := 0
var failures: Array[String] = []
var completed: Array[String] = []
var _suite := ""

func begin(suite: String) -> void:
	_suite = suite

func check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok:
		failures.append("%s: %s" % [_suite, label])

func eq_float(actual: float, expected: float, tol: float, label: String) -> void:
	check(absf(actual - expected) <= tol,
		"%s（实际 %.17f，期望 %.17f，容差 %s）" % [label, actual, expected, str(tol)])

func complete() -> void:
	completed.append(_suite)
```

- runner 的 `complete()` 缺失检测与哨兵：

```gdscript
func _initialize() -> void:
	var r := Reporter.new()
	for suite_name in SUITES:
		r.begin(suite_name)
		SUITES[suite_name].new().run(r)
		if not r.completed.has(suite_name):
			# 运行时错误只中止套件函数，调用者会继续；把「没走完」变成失败
			r.check(false, "套件提前中止（运行时错误 / assert 失败），断言未全部执行")
	for f in r.failures:
		printerr("TESTS_FAIL " + f)
	print("TESTS_ASSERTIONS=%d" % r.assertions)
	print("TESTS_DONE failures=%d" % r.failures.size())
	quit(0 if r.failures.is_empty() else 1)
```

**测试目录规则：**

- 测试脚本与 reporter **不加 `class_name`**（避免污染全局命名空间、避免被打进导出包），用 `preload("res://tests/...")`；
- 套件必须 `r.complete()`；没有完成标记即失败；
- `printerr` / `print` 在 `tests/` 里允许（lint 只扫 `src/core/`）；
- `--path "$repo_root/mobile"` 必须显式传入（否则 `user://` 落到 `[unnamed project]`）。

---

### 11. `mobile/tests/test_reporter.gd`（test utility，collect）

**Analog:** `tools/test_sync_config.py:27-39`（Python 的 `PASS`/`FAIL` + `check()`），以及 `desktop/tests/test_detectors.py` 的手写 `check()` 文化。

```python
PASS = 0
FAIL = 0


def check(label: str, ok: bool, extra: str = "") -> None:
    global PASS, FAIL
    if ok:
        PASS += 1
        print(f"  \033[32m✓\033[0m {label}" + (f"  ({extra})" if extra else ""))
    else:
        FAIL += 1
        print(f"  \033[31m✗\033[0m {label}" + (f"  ({extra})" if extra else ""))
```

GDScript 版把「立即打印」换成「累积到 failures + 由 runner 统一打印」，因为 `print` 在 headless 输出里必须可被 `grep`。`eq_float` 的 `%.17f` 格式和「实际/期望/容差」中文消息要保留 —— 失败时能直接定位。

---

### 12-14. `mobile/tests/unit/test_geometry.gd` / `test_config_loader.gd` / `test_config_validator.gd` / `test_overlay_merge.gd`（test suites）

**Analog:** `tools/test_sync_config.py:55-214`（反例优先、临时目录隔离、收集全部问题）+ `check_pack.gd`（`extends SceneTree` 入口）。

**可照抄的测试结构：**

```python
def test_check_detects_tampered_copy() -> None:
    """⑤ 手改移动端副本后 check 返回 1，并指出该文件。"""
    tmp = tempfile.mkdtemp(prefix="fifa-sync-")
    try:
        root = make_root(tmp)
        sync(root, io.StringIO())
        victim = root / TARGETS[1]
        victim.write_bytes(SOURCE_BYTES + b"\n")

        err = io.StringIO()
        rc = check_config(root, err)
        check("手改副本后 check 返回 1", rc == 1, f"实际 {rc}")
        check("手改副本的报错里含该文件路径",
              TARGETS[1].as_posix() in err.getvalue(), err.getvalue().strip())
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
```

GDScript 对应：

```gdscript
func run(r) -> void:
	# geometry：表驱动，逐向量 eq_float
	for case in _load_golden()["angle_of"]:
		r.eq_float(Geometry.angle_of(case["x"], case["y"]), case["expected"], 1e-9, case["name"])
	# 中心用例额外精确断言（守卫是精确分支）
	r.check(Geometry.angle_of(0.0, 0.0) == 0.0, "angle_of(0,0) 必须精确为 0.0")
	r.complete()
```

**fixture 规则（test_config 特有）：**

- 用 `FileAccess.get_file_as_bytes()` 读 fixture（BOM 用例必须保留原始字节；也可以在测试里直接合成 `PackedByteArray([0xEF,0xBB,0xBF]) + clean_bytes`）；
- 目录列 `DirAccess.get_files_at()`，**过滤 `*.expect.json` 与 `.gdignore`**，按文件名排序；
- 断言 `ok()`、`codes`（按集合比较，顺序无关）、`paths`；
- `valid/*` 必须通过；`invalid/*` 必须拒绝；
- 真实配置 `res://assets/config/skills_config.json` 必须直接测：`ok()` 且 `skills.size() == 5`、名称顺序与 `shared/` 一致；缺失必须**失败而不是 skip**。

**test_overlay 的矩阵（RESEARCH §Q5）：** 合法稀疏合并、schema 缺失、schema 过新、base hash 不匹配、未知 skill、未知键、白名单键逐个应用、base 不被修改、丢弃后 `applied == false`、notice 文案。

---

### 15. `mobile/tools/test-core.sh`（shell gate，orchestration）

**Analog:** `mobile/tools/gate-a.sh` + `tools/check_desktop.sh`

**必须照抄的 shell house style：**

`gate-a.sh:20-26`：

```bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
godot="${GODOT_BIN:-$HOME/Applications/Godot-4.7.2.app/Contents/MacOS/Godot}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
```

`gate-a.sh:43-69`（有界重试，只对信号终止重试）：

```bash
import_rc=1
for attempt in 1 2 3; do
    set +e
    "$godot" --headless --path "$repo_root/mobile" --import >"$tmp/import.log" 2>&1
    import_rc=$?
    set -e
    if [ "$import_rc" -eq 0 ]; then
        [ "$attempt" -gt 1 ] && echo "  · 导入第 ${attempt} 次成功（前一次被信号终止，Godot 已知偶发）"
        break
    fi
    if [ "$import_rc" -lt 128 ]; then
        echo "✗ 工程导入失败（Godot --import 退出码 ${import_rc}，不是信号终止，不重试），日志尾部：" >&2
        tail -n 20 "$tmp/import.log" >&2
        exit 1
    fi
    echo "  · 导入被信号终止（退出码 ${import_rc}），第 ${attempt}/3 次，重试…" >&2
done
```

`gate-a.sh:117-124`（哨兵判定，不看退出码）：

```bash
case "$pack_out" in
    *PACK_OK*)
        ;;
    *)
        echo "✗ 包内校验没有给出 PACK_OK 标记：${pack_out}" >&2
        exit 1
        ;;
esac
```

`check_desktop.sh:32-36`（`▸` 进度行 + 可操作提示）：

```bash
echo "▸ 校验配置副本…"
if ! python3 "$repo_root/tools/sync_config.py" --check; then
    echo "  运行 python3 tools/sync_config.py 重新生成副本后再试。" >&2
    exit 1
fi
```

**本阶段必须新增、仓库里没有的两件事：**

1. **看门狗**：仓库现有任何 `.sh` 都没有 `timeout` / `run_with_timeout`（已 grep 验证）。直接采用 RESEARCH §Q1 的 bash 3.2 兼容实现：

```bash
run_with_timeout() {
	local secs="$1"; shift
	local out="$1"; shift
	"$@" >"$out" 2>&1 &
	local pid=$!
	( sleep "$secs"; kill -TERM "$pid" 2>/dev/null; sleep 2; kill -KILL "$pid" 2>/dev/null ) &
	local watcher=$!
	local rc=0
	wait "$pid" || rc=$?
	kill "$watcher" 2>/dev/null || true
	wait "$watcher" 2>/dev/null || true
	return "$rc"
}
```

2. **完成哨兵**：仓库现有哨兵是 `PACK_OK` / `GLYPH_OK`；本阶段是 `TESTS_DONE failures=0`，并且必须 `grep -q`：

```bash
if ! run_with_timeout 180 "$tmp/tests.log" \
		"$godot" --headless --path "$repo_root/mobile" --script res://tests/core_runner.gd; then
	cat "$tmp/tests.log"; echo "✗ 核心测试进程失败/超时" >&2; exit 1
fi
cat "$tmp/tests.log"
grep -q "TESTS_DONE failures=0" "$tmp/tests.log" || {
	echo "✗ 没有 TESTS_DONE failures=0（解析/编译/运行时错误都可能 rc=0）" >&2
	exit 1
}
```

**固定顺序（顺序即安全属性，RESEARCH §Validation Architecture）：**

```
1. python3 tools/sync_config.py --check        # 防止对着被手改的副本自洽地绿
2. python3 tools/test_lint_core_purity.py      # lint 反例自测
3. python3 tools/lint_core_purity.py mobile/src/core
4. python3 tools/gen_geometry_golden.py --check
5. python3 tools/check_config_parity.py
6. godot --headless --path mobile --import     # 有界重试
7. run_with_timeout 180 ... --script res://tests/core_runner.gd
   → 必须看到 TESTS_DONE failures=0
```

---

### 16. `tools/lint_core_purity.py`（repo tool，text scan）

**Analog:** `tools/sync_config.py:39-178`（CLI 工具结构）+ RESEARCH §Code Examples 5（`strip_code` 原型，已实测 clean=0 / dirty=6）

**必须照抄的工具结构：**

```python
def repo_root() -> Path:
    """仓库根目录：以脚本位置（tools/ 的上一级）为锚，不依赖调用方的 cwd。"""
    return Path(__file__).resolve().parent.parent


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(...)
    parser.add_argument("--root", default=None,
                        help="仓库根目录（默认按脚本位置推导，仅供自测注入）")
    args = parser.parse_args(argv)
    root = Path(args.root).resolve() if args.root else repo_root()
    if not root.is_dir():
        raise SystemExit(f"仓库根目录不存在: {root}")
    ...
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

> 注意：`tools/sync_config.py` 与 `tools/test_sync_config.py` **没有 `__all__`**（已 grep 验证）。`__all__` 是 `desktop/padskills/*.py` 的模块约定（`geometry.py:20`、`config.py:18`）。给 lint 工具加 `__all__` 不是现有工具的先例，别声称「照 tools 的风格」。

**剥离器状态机**（RESEARCH §Code Examples 5，逐字）：

```python
def strip_code(text: str) -> str:
    """把注释与字符串替换成空格，保留换行与列位置。"""
    out, i, n = [], 0, len(text)
    while i < n:
        ch = text[i]
        if ch == "#":                                  # 行注释
            while i < n and text[i] != "\n":
                out.append(" "); i += 1
            continue
        if ch in ('"', "'"):                           # 普通/三引号/raw/StringName/NodePath
            delim = ch
            triple = text.startswith(delim * 3, i)
            width = 3 if triple else 1
            out.extend(" " * width); i += width
            while i < n:
                if text.startswith(delim * width, i):
                    out.extend(" " * width); i += width; break
                if text[i] == "\\" and i + 1 < n:
                    out.extend("  "); i += 2; continue
                out.append("\n" if text[i] == "\n" else " "); i += 1
            continue
        out.append(ch); i += 1
    return "".join(out)
```

**规则表（前 5 条是 INFRA-03 硬集合，不可删）：**

```python
FORBIDDEN = [
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
```

**退出码约定（与 Phase 1 一致）：**

- 命中 → `1`，输出 `relative_path:line: rule: token`；
- 干净 → `0`；
- `--root` 不存在或零个 `.gd` → `2`（「这不是一次有效运行」，不要和「干净」混淆）。

**已知漏报要写进工具 docstring：** 行继续符拆 token、`ClassDB.instantiate("Node")`、`call("print")`、`preload` 路径变量拼接。lint 的目标是挡住无意识引入，不是对抗恶意代码。

---

### 17. `tools/test_lint_core_purity.py`（test，canary）

**Analog:** `tools/test_sync_config.py`（同一套自测文化）

照抄的结构：

- `tempfile.mkdtemp(prefix=...)` 搭临时 core 目录；
- `check(label, ok, extra)` 累计 `PASS` / `FAIL`；
- 每个用例 `try/finally: shutil.rmtree(tmp, ignore_errors=True)`；
- `main() -> int` 打印 `通过 N 项，失败 M 项`，`return 1 if FAIL else 0`；
- **反例优先**：clean canary 0 命中；五条硬规则各一条 canary 命中对应 rule；注释/字符串/三引号/raw string canary 0 命中；嵌套 `tests/*` + `outer_layer_dep` 命中；`--root` 不存在 → rc=2；空目录 → rc=2。

```python
def main() -> int:
    print("═" * 62)
    print("  配置单一真源 —— 同步脚本自测")
    print("═" * 62)

    test_sync_writes_copies()
    # ...

    print("\n" + "═" * 62)
    print(f"  通过 {PASS} 项，失败 {FAIL} 项")
    print("═" * 62)
    return 1 if FAIL else 0


if __name__ == "__main__":
    raise SystemExit(main())
```

---

### 18. `tools/gen_geometry_golden.py`（repo tool，generate + `--check`）

**Analog:** `tools/make_font_subset.py:206-298`

这是仓库里「生成物 + `--check` 只读校验」的成熟先例：

```python
def check(root: Path) -> int:
    """只读校验：清单必须等于从源文件重新推导的结果，两个子集必须存在。

    ``--check`` 绝不调用子进程、绝不写盘：它要能在闸门里毫秒级反复跑。
    """
    problems: List[str] = []
    ...
    if problems:
        for line in problems:
            print(line, file=sys.stderr)
        return 1
    print(f"✓ 字形清单与源文件一致（{len(derived)} 个字符），两个子集均已生成")
    return 0


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        prog="make_font_subset.py",
        description="...",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "示例:\n"
            "  python3 tools/make_font_subset.py           生成 / 刷新三份产物\n"
            "  python3 tools/make_font_subset.py --check   只校验，不写盘\n"
        ),
    )
    parser.add_argument("--check", action="store_true",
                        help="只校验清单与子集是否一致，不写任何文件")
    parser.add_argument("--root", default=None,
                        help="仓库根目录（默认按脚本位置推导，仅供自测注入）")
    ...
    if args.check:
        return check(root)
    return sync(root, source_dir)


if __name__ == "__main__":
    raise SystemExit(main())
```

**几何生成器的核心**（RESEARCH §Code Examples 6）：

```python
repo = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(repo / "desktop"))
from padskills.geometry import norm_deg, signed_delta, angle_diff, angle_of, magnitude  # noqa: E402

S = 1.0 / math.sqrt(2.0)
CASES = [
    ("center", 0.0, 0.0), ("up", 0.0, -1.0), ("upright", S, -S),
    ("right", 1.0, 0.0), ("downright", S, S), ("down", 0.0, 1.0),
    ("downleft", -S, S), ("left", -1.0, 0.0), ("upleft", -S, -S),
]
payload = {
    "schema_version": 1,
    "source": "desktop/padskills/geometry.py",
    "meta": {"python_geometry_sha256": hashlib.sha256(
        (repo / "desktop/padskills/geometry.py").read_bytes()).hexdigest()},
    "angle_of": [{"name": n, "x": x, "y": y, "expected": angle_of(x, y)} for n, x, y in CASES],
    "norm_deg": [{"input": v, "expected": norm_deg(v)} for v in (-90.0, 360.0, -0.0, -1e-12, 720.5)],
    "signed_delta": [{"from": a, "to": b, "expected": signed_delta(a, b)}
                     for a, b in ((0, 180), (0, 181), (350, 10), (10, 350), (270, 0), (0, 270), (45, 45))],
    "magnitude": [{"x": x, "y": y, "expected": magnitude(x, y)} for _, x, y in CASES],
}
text = json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
```

**`--check` 语义：** 重新生成 → 与夹具逐字节比较；不一致即失败并打印差异。**不写盘。**

---

### 19. `tools/check_config_parity.py`（repo tool，cross-language parity）

**Analog:** `tools/sync_config.py:107-152`（collect-then-report）+ `tools/test_sync_config.py`（同一批 fixture 的断言风格）

**职责：** 读 `mobile/tests/fixtures/configs/{valid,invalid}/*.json` + 同名 `.expect.json`，在 Python 侧调用 `parse_config`（并对 `python: accept` 的条目再跑 `build_detector()`，抓 `start_angle` 数组这种晚失败），断言：

- `valid/*` 必须成功；
- `invalid/*` 必须按 `expect.python` 拒绝（`TypeError` / `ValueError` / `JSONDecodeError` 都算拒绝）；
- 带 `divergence` 的条目单独断言「Python 接受但 GDScript 拒绝」是已知且已记录的；
- BOM 必须模拟 `path.read_text(encoding="utf-8")` + `json.loads(str)`，**不能**用 `json.loads(bytes)`（后者按 `utf-8-sig` 接受 BOM）。

**`.expect.json` 契约**（RESEARCH §Validation Architecture）：

```json
{
  "python": "accept",
  "python_note": "bool('false') 为 True，属已知缺陷；GDScript 故意拒绝",
  "godot": "reject",
  "codes": ["bool_expected"],
  "paths": ["skills[0].enabled"],
  "divergence": "string_bool_python_silently_true"
}
```

`start_angle_array` 这条用 `"python": "accept_then_detector_reject"`，证明 GDScript 把错误提前到校验期。

---

### 20. `mobile/tests/fixtures/geometry_golden.json`（fixture，generated）

**Analog（部分）：** `shared/expected_checks.txt` —— 仓库里唯一「生成物被闸门钉死」的先例（`tools/check_desktop.sh:15` 固定 `BASELINE_SHA256`，改基线不改常量必红）。

**精确形状**（RESEARCH §Code Examples 6）：

```json
{
  "schema_version": 1,
  "source": "desktop/padskills/geometry.py",
  "meta": {
    "python_geometry_sha256": "<64 位小写 hex>"
  },
  "angle_of": [
    {"name": "center", "x": 0.0, "y": 0.0, "expected": 0.0},
    {"name": "up", "x": 0.0, "y": -1.0, "expected": 0.0},
    {"name": "upright", "x": 0.7071067811865476, "y": -0.7071067811865476, "expected": 45.0},
    {"name": "right", "x": 1.0, "y": 0.0, "expected": 90.0},
    {"name": "downright", "x": 0.7071067811865476, "y": 0.7071067811865476, "expected": 135.0},
    {"name": "down", "x": 0.0, "y": 1.0, "expected": 180.0},
    {"name": "downleft", "x": -0.7071067811865476, "y": 0.7071067811865476, "expected": 225.0},
    {"name": "left", "x": -1.0, "y": 0.0, "expected": 270.0},
    {"name": "upleft", "x": -0.7071067811865476, "y": -0.7071067811865476, "expected": 315.0}
  ],
  "norm_deg": [
    {"input": -90.0, "expected": 270.0},
    {"input": 360.0, "expected": 0.0},
    {"input": -0.0, "expected": 0.0},
    {"input": -1e-12, "expected": 359.999999999999},
    {"input": 720.5, "expected": 0.5}
  ],
  "signed_delta": [
    {"from": 0.0, "to": 180.0, "expected": -180.0},
    {"from": 0.0, "to": 181.0, "expected": -179.0},
    {"from": 350.0, "to": 10.0, "expected": 20.0},
    {"from": 10.0, "to": 350.0, "expected": -20.0},
    {"from": 270.0, "to": 0.0, "expected": 90.0},
    {"from": 0.0, "to": 270.0, "expected": -90.0},
    {"from": 45.0, "to": 45.0, "expected": 0.0}
  ],
  "magnitude": [
    {"x": 1.0, "y": 0.0, "expected": 1.0},
    {"x": 0.7071067811865476, "y": 0.7071067811865476, "expected": 1.0}
  ]
}
```

**生成器：** `tools/gen_geometry_golden.py`（仓库根，`sys.path.insert(0, repo/"desktop")`，只 import `padskills.geometry`，不碰 pygame）。

**测试判据：**

- `angle_of` 9 个方向用 `eq_float(..., 1e-9)`；`center` 额外 `== 0.0` 精确断言；
- `signed_delta(0,180) == -180` 必须固化，防止后人「修正」成 +180；
- `magnitude(s,s)` 用 1e-9 容差（`sqrt` 与 `hypot` 差 1 ulp）；
- 夹具 `meta.python_geometry_sha256` 与 generator `--check` 共同证明夹具没漂移。

---

### 21. `mobile/src/ui/error_screen.gd`（可选，component，render）

**Analog:** `mobile/src/smoke/smoke_screen.gd`（`extends Control` + `@onready` + 动态 Label）

```gdscript
extends Control

## 验收面板。这一屏要一次性证明三件事：
##   1) 最长中文串与 ° ± → ✓ ✗ 都能显示（成功标准 2，不是豆腐块）
##   ...

@onready var _header: Label = %Header
@onready var _axes: Label = %Axes
```

错误屏只需要消费 `ConfigResult`，不做解释：

- 顶部：`source_path` + 「发现 N 个问题」；
- 每条 `ConfigError`：`json_path`（等宽小字）、`message`（大字）、`fix_hint`（`→` 前缀）；
- 底部：「复制」（`DisplayServer.clipboard_set(result.to_text())`）、「恢复默认」（删除 `user://config/overrides.json` 并重载）；
- `notice` 单独一条横幅。

**范围：** 若计划阶段决定不引入 UI，**至少保留 `ConfigResult.to_text()` + headless 断言**；否则 RESIL-02 只闭合一半（RESEARCH A8）。

---

## Shared Patterns

### A. 错误对象契约（所有校验路径）

**Source:** RESEARCH §Q4 + `desktop/padskills/config.py` 的错误消息风格

**Apply to:** `config_loader.gd`、`config_validator.gd`、`overlay_merge.gd`、`config_store.gd`、测试

每条错误必须有四个字段：`json_path` + `code` + `message` + `fix_hint`。`severity` 用来承载「静默 clamp → 可见 warning」：

```gdscript
ConfigError.new(
	"skills[%d].params.max_duration_ms" % i,
	&"max_not_greater_than_min",
	"max_duration_ms (250ms) 必须大于 min_duration_ms (600ms)",
	"把 max_duration_ms 调大，或把 min_duration_ms 调小。")
```

- `json_path` 根用 `$`；数组用 `skills[3]`；字段用 `.params.button`；
- `code` 用 `StringName` + lowercase snake_case（稳定后不改名）；
- `message` 中文、含实际值；`fix_hint` 中文、可执行；
- core 内**绝不** `push_error` / `printerr` / `print`（lint 强制）。

### B. 收集而不是抛出（collect-then-report）

**Source:** `tools/sync_config.py:107-152`

```python
problems: List[str] = []
...
for line in problems:
    print(line, file=err)
return 1 if problems else 0
```

**Apply to:** `ConfigValidator.validate()`、`OverlayMerge.merge()`、`lint_core_purity.py`、`test-core.sh` 的失败汇总。

校验器把同一个 `Array[ConfigError]` 传下去（GDScript 数组是引用类型）；只有「依赖前提不成立」时才跳过子树（例如 `type` 非法就不做 arc/sequence/taps 专项检查，但 `enabled`/`required_button`/`cooldown_ms`/`rumble` 仍然检查）。

### C. GDScript 文件头与注释约定

**Source:** `mobile/src/smoke/smoke_screen.gd:1-18`、`mobile/tools/check_pack.gd:1-13`、`mobile/tools/glyph_coverage.gd:1-16`

- `extends` 在第一行（core 用 `class_name X` 后接 `extends RefCounted`，顺序按官方 style guide）；
- 空一行，`##` 开头的中文 docstring：说明「这一屏/这个模块证明什么」「为什么顺序不能换」「不要照抄 research 的哪一句」；
- 常量 `UPPER_SNAKE` + `:=`；
- 函数之间两个空行；缩进用 **Tab**（现有 `.gd` 全部如此）；
- 标识符英文 ASCII；注释、错误消息中文。

### D. Shell 闸门风格

**Source:** `mobile/tools/gate-a.sh:20-26`、`tools/check_desktop.sh:13-90`

- `set -euo pipefail`；
- `repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/... " && pwd)"`，不依赖 cwd；
- `tmp="$(mktemp -d)"` + `trap 'rm -rf "$tmp"' EXIT`；
- 进度行 `▸ ...`，成功 `✓ ...`，失败 `✗ ...` 到 stderr；
- 错误消息必须给下一步（「运行 python3 tools/sync_config.py 重新生成副本后再试」）；
- 顺序即安全属性：配置同步校验永远第一步；
- 有界重试只对信号终止（`rc >= 128`），且打印重试次数；
- 哨兵用 `case ... in *SENTINEL*)` / `grep -q`，**绝不只看 `$?`**。

### E. 生成物 + `--check`

**Source:** `tools/sync_config.py:80-152`（字节副本 + `.sha256`）、`tools/make_font_subset.py:206-256`（生成物 + 只读校验）、`tools/check_desktop.sh:15`（基线摘要常量）

**Apply to:** `tools/gen_geometry_golden.py`、`mobile/tests/fixtures/geometry_golden.json`、`mobile/assets/config/*.json`

- 生成器默认写盘；`--check` 只读、毫秒级、不调用子进程；
- `--check` 重新生成并逐字节比较；不一致打印差异并返回 1；
- 生成物不能手改；手改由 `--check` 抓住。

---

## No Analog Found

| 文件/能力 | Role | Data Flow | 为什么没有 analog | Planner 应采用的来源 |
|-----------|------|-----------|-------------------|----------------------|
| `mobile/src/core/config/overlay_merge.gd` | service | merge | 桌面版没有用户覆盖层；仓库里没有任何「合并 + 丢弃 + base hash」语义 | RESEARCH §Q5 + §Code Examples 2，逐条实现 |
| Godot 多套件 headless runner + `complete()` 哨兵 | harness | batch | `check_pack.gd` / `glyph_coverage.gd` 只是单脚本 `quit(0/1)`，没有「套件崩溃识别」 | RESEARCH §Q1；只把 `extends SceneTree` + `_initialize` + `quit` 骨架当 analog |
| Shell 看门狗 / 超时 | infra | process control | 仓库所有 `.sh` 都没有 `timeout` / `run_with_timeout`（已 grep 验证） | RESEARCH §Q1 的 bash 3.2 兼容实现；不要假设 macOS 有 GNU `timeout` |
| BOM 安全的配置加载器 | service | bytes → model | 仓库现有 GDScript 全部用 `JSON.parse_string(FileAccess.get_file_as_string(...))`，**正好是会剥 BOM 的反面教材** | RESEARCH §Code Examples 1；入口必须是 `PackedByteArray` |
| `class_name` + `extends RefCounted` 的 core 数据对象 | model | in-memory | `src/` 只有 `smoke_screen.gd`（`extends Control` + `@onready`），没有纯数据类先例 | RESEARCH §Pattern 1 + §Q6；一文件一 `class_name` |
| `mobile/tests/fixtures/.gdignore` + 坏 JSON 语料 | fixture | file-set | 仓库无 `tests/` 目录、无 fixture 先例 | RESEARCH §Q6「`--import` 与 `.uid` 边车」；实测 `.gdignore` 下 `FileAccess` 仍可读 |
| `tools/check_config_parity.py` | tool | cross-language | Phase 1 的 `sync_config.py` 只比字节，不比语义 | RESEARCH §Validation Architecture 的 `.expect.json` 契约 |

---

## Anti-Analogs（看起来像 analog，但绝不能照抄）

| 位置 | 看似可抄 | 为什么不能 | 正确做法 |
|------|----------|------------|----------|
| `mobile/src/smoke/smoke_screen.gd:39` | `JSON.parse_string(FileAccess.get_file_as_string(path))` | `get_file_as_string()` **静默剥 BOM**；`parse_string()` 失败时向 stderr 打 ERROR | `ConfigLoader.parse_bytes(FileAccess.get_file_as_bytes(path))` |
| `mobile/tools/check_pack.gd:22-23` | 同上 | 同一组假绿风险；`check_pack` 是导出包校验，不是配置校验 | 只在非配置场景使用；配置一律走 bytes |
| `mobile/tools/gate-a.sh:78-92` | `--check-only` 语法检查 | 对解析错误返回 0，只能看输出；不能当 core 架构闸门 | 架构边界用 `lint_core_purity.py`；语法闸门靠 runner 的 preload/编译失败 + 哨兵 |
| `tools/check_desktop.sh:64-79` | `run_suite()` | 没有超时；Godot 入口错误会挂死 | 用 `run_with_timeout` 包住 Godot 进程 |
| `desktop/padskills/config.py:775-801` | `raise SystemExit(...)` / `raise ValueError(...)` | GDScript 无异常；运行时错误不可捕获且只中止当前函数 | 返回 `ConfigResult` + `Array[ConfigError]` |
| `desktop/padskills/config.py:675-676` | `bool(raw.get(...))` | `bool("false") == true`，静默错误语义 | 先 `typeof(v) == TYPE_BOOL`；字符串布尔拒绝 |
| `desktop/padskills/config.py:691` | `int(raw.get("poll_hz", ...))` + clamp | 静默降级；用户看不见 | warning + 应用截断值（`out_of_range`） |
| `desktop/padskills/config.py:152` | `@dataclass(frozen=True)` | GDScript 无 frozen、无自动 `__init__`、无 `__all__` | `class_name` + typed `var` + `_init`；不可变性靠约定 + `duplicate(true)` |
| `mobile/tests/*` 里加 `class_name` | 测试类全局名 | 污染全局命名空间、可能被打进导出包 | 用 `preload("res://tests/...")` |

---

## Python → GDScript 无对应构造表

| Python 构造 | GDScript 现实 | 本阶段的重设计 |
|-------------|---------------|----------------|
| `raise ValueError(...)` / `raise SystemExit(...)` | 无受检异常；运行时错误**只中止当前函数**，调用者继续；`assert` 在 release 被剥离 | 全部改成返回值：`ConfigResult` / `Array[ConfigError]` / `null` / `String` 空串 |
| `@dataclass` | 无自动 `__init__` / `__repr__` / `__eq__`；`frozen` 不存在 | `class_name` + typed `var` + 手写 `_init`；需要摘要时手写 `summary()` / `format_line()` |
| `field(default_factory=dict)` | 类字段默认值每个实例独立 | 直接 `var params: Dictionary = {}` |
| `Optional[T]` | 对象类型可为 `null`；`float` / `int` / `bool` **不能**为 null | 对象用 `T = null`；数值用 `Variant`（`null` 或 float）或 `has_x: bool` + `x: float` |
| `Tuple[str, ...]` | 无 tuple | `Array[String]`；数组是引用类型，对外返回 `.duplicate()` |
| `Dict[str, Any]` | `Dictionary` / `Dictionary[String, Variant]`；**嵌套类型化集合不允许** | 用普通 `Dictionary`，或 `Dictionary[String, Variant]` |
| `__all__` | 不存在 | 公开性由 `class_name`（全局类）与 `_` 前缀（私有）表达；工具脚本不写 `__all__` |
| `isinstance(value, bool)` 先挡 bool | `typeof(true) == TYPE_BOOL`，bool 不是 int；但 `float(true) == 1.0` 仍成立 | 每个字段先 `typeof`；数值接受 `TYPE_INT | TYPE_FLOAT`；bool 只接受 `TYPE_BOOL` |
| `float(None)` → TypeError | `float(null)` 是**运行时错误**，只中止当前函数 | 转换前 `typeof` 守卫；`null` 单独报 `number_expected` |
| `bool("false")` | `bool("false") == true` | 字符串布尔拒绝 `bool_expected` |
| `value % 360.0` | 两个 float 用 `%` 是**解析错误** | `fposmod(value, 360.0)` |
| `math.degrees` / `math.atan2` / `math.hypot` | `rad_to_deg` / `atan2(y,x)` / `sqrt(x*x+y*y)` | 见 geometry.gd 映射表 |
| `f"{value!r}"` | 无 `!r` | `JSON.stringify(value)`（诊断用）或 `str(value)`；`str(1.0/3.0)` 只有 14 位有效数字，**不要用于浮点比较** |
| `pathlib.Path` / `read_text` | 无 pathlib；路径是 `res://` / `user://` 字符串 | `ConfigLoader` 只收 bytes；`ConfigStore` 负责 `FileAccess` |
| `json.loads(str)` | `JSON.new().parse(text)` 返回 `Error` + `get_error_line()` / `get_error_message()`；JSON 整数解析成 float | 用 `JSON.new().parse()`；错误行 `+1`；数值同时接受 INT/FLOAT |
| `try/except` 包住 JSON 解析 | GDScript 无 try/catch | 检查 `Error` 返回值；解析失败 → `ConfigError` |
| `@dataclass` 的 `raw: Dict[str, Any]` | 同上 | 保留 `raw: Dictionary`（开放 schema）；未知 params 键不警告 |
| `systemexit` 退出码 | 只有 `SceneTree.quit(code)` 能设退出码 | 测试 runner 用 `quit(0/1)`；工具脚本用 `raise SystemExit(main())` |

---

## 几何对等性夹具：精确契约

**生成器位置：** `tools/gen_geometry_golden.py`（仓库根，**不在** `mobile/`；Godot 会扫描工程内所有文件，Python 脚本放 `mobile/` 会变成 PCK 里的非资源 blob）。

**夹具位置（二选一，按 RESEARCH 推荐）：** `mobile/tests/fixtures/geometry_golden.json`。

**生成方式：**

```python
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "desktop"))
from padskills.geometry import norm_deg, signed_delta, angle_diff, angle_of, magnitude
```

**为什么可以安全 import：** `geometry.py` 只 `import math`，不碰 pygame。

**形状：** 见 §20 的完整 JSON。四个顶层键必须都有：`angle_of`（9 个方向）、`norm_deg`（5 个边界）、`signed_delta`（7 个端点/跨零）、`magnitude`（至少两个）。

**容差：** `1e-9`（roadmap 要求）；`angle_of(0,0)` 额外精确 `== 0.0`；`norm_deg(-1e-12)` 的期望值是 `359.999999999999`（这是 Python 实测值，不是 `360.0`）。

**必须进表的边界（RESEARCH 明列）：**

```
norm_deg(-90)              = 270.0
norm_deg(360)              = 0.0
norm_deg(-1e-12)           = 359.999999999999
angle_of(-0.0, -0.0)       = 0.0
signed_delta(0, 180)       = -180.0   ← 固化端点，防止被「修正」成 +180
signed_delta(350, 10)      = 20.0
signed_delta(10, 350)      = -20.0
magnitude(1, 0)            = 1.0
magnitude(s, s)            ≈ 1.0      ← 容差 1e-9
```

**这些向量能抓住的静默失败：** `atan2(y,x)` / `Vector2.angle()`（整表逆时针 90°）、`fmod` 代替 `fposmod`（`left` 得 -90）、去掉居中守卫（`angle_of(0,0)` 得 180）、把 `signed_delta` 端点改成 +180。

---

## Metadata

**Analog search scope:** `desktop/padskills/`、`tools/`、`mobile/src/`、`mobile/tools/`

**Files scanned:** 13 个 analog（`geometry.py`、`config.py`、`input_source.py`、`__init__.py`、`check_desktop.sh`、`sync_config.py`、`test_sync_config.py`、`make_font_subset.py`、`gate-a.sh`、`check_pack.gd`、`glyph_coverage.gd`、`smoke_screen.gd`、`project.godot`/`export_presets.cfg`）

**Tracked-source gate:** 所有引用的 analog 均已 `git ls-files -- <path>` 验证为已跟踪（非空输出）；未引用 `.godot/`、`build/`、`assets/config/` 生成物或任何 `.gsd/` 镜像。

**Pattern extraction date:** 2026-11-05
