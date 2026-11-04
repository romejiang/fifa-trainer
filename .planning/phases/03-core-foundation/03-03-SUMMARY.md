---
phase: 03-core-foundation
plan: 03
subsystem: core
tags: [gdscript, vocabulary, domain-model, parity, alias-table, typed-containers]

requires:
  - phase: 03-core-foundation
    plan: 01
    provides: 无头 runner、`test-core.sh` 唯一入口与完成哨兵、`Array[T]` 可用性已实测
  - phase: 03-core-foundation
    plan: 02
    provides: 架构 lint（14 条规则）与 CORE.md 的可执行边界定义
  - phase: 02-android-toolchain
    provides: Godot 4.7.2 安装与 `*.gd.uid` 提交约定

provides:
  - "mobile/src/core/domain/buttons.gd：17 个规范名 + 39 条别名 + canonical()（失败返回空串）"
  - "mobile/src/core/domain/direction_table.gd：42 条方向别名 + resolve()（失败返回 null）"
  - "mobile/src/core/domain/{pulse,step,skill}.gd：动作规则三件套，默认值与 Python dataclass 逐字段一致"
  - "mobile/src/core/domain/{input_config,rumble_config,app_config}.gd：配置容器，12 + 5 + 4 字段"
  - "mobile/tests/unit/test_vocabulary.gd：三张表条目数（17/39/42）+ 别名/大小写/分隔符/布尔拒绝"
  - "mobile/tests/unit/test_models.gd：六个域对象默认值逐字段 + 复制语义 + rumble_summary 文案"
  - "mobile/tests/core_runner.gd：SUITES 扩到 3 条（geometry / models / vocabulary）"

affects: [03-04, 03-05, 03-06, phase-4-detectors, phase-5-detectors]

actuals:
  tokens: 4745
  tasks: 3
  commits: 3

plan_head_before: 2f4be8cc717186dea379fba0e51b520521ddcb61
plan_head_after: be18bef92779618407d30515fea433761981a6d3

tech-stack:
  added: []
  patterns:
    - "一个 class_name 一个文件：类型化容器（Array[Skill] / Array[Pulse]）才编译得过"
    - "词汇表失败值是空串 / null，错误文本由校验层拼 json_path；core 零异常零日志"
    - "条目数与默认值都当契约断言：改表或改默认值必须先改测试"

key-files:
  created:
    - mobile/src/core/domain/buttons.gd
    - mobile/src/core/domain/buttons.gd.uid
    - mobile/src/core/domain/direction_table.gd
    - mobile/src/core/domain/direction_table.gd.uid
    - mobile/src/core/domain/pulse.gd
    - mobile/src/core/domain/pulse.gd.uid
    - mobile/src/core/domain/step.gd
    - mobile/src/core/domain/step.gd.uid
    - mobile/src/core/domain/skill.gd
    - mobile/src/core/domain/skill.gd.uid
    - mobile/src/core/domain/input_config.gd
    - mobile/src/core/domain/input_config.gd.uid
    - mobile/src/core/domain/rumble_config.gd
    - mobile/src/core/domain/rumble_config.gd.uid
    - mobile/src/core/domain/app_config.gd
    - mobile/src/core/domain/app_config.gd.uid
    - mobile/tests/unit/test_vocabulary.gd
    - mobile/tests/unit/test_vocabulary.gd.uid
    - mobile/tests/unit/test_models.gd
    - mobile/tests/unit/test_models.gd.uid
  modified:
    - mobile/tests/core_runner.gd

key-decisions:
  - "字符串 \"-90\" 的负号按分隔符剥掉（与 Python 的 strip 顺序逐字一致），得到 90.0 而不是 270.0；要 270° 必须写数字 -90。这条「看起来像 bug 的既有行为」被显式钉死并注释：改成保留负号会让同一份配置在两端相差 180°"
  - "39 条按键别名与 42 条方向别名逐条照抄并直接用「条目数 == 契约」断言；未来增删必须先改 test_vocabulary.gd，不可能悄悄漂移"
  - "6 个测试文件之外不加任何抽象层：不做基类、不做 enum 双向表、不做 direction_name()（RESEARCH 裁定 Phase 5/7 需要时再加）"
  - "Skill.pattern 用成员初始化器 `[Pulse.new()]`，并额外断言「两个 Skill 的默认 Pulse 不是同一个实例」—— 成员初始化器每实例独立是默认值的可观测语义"
  - "InputConfig.axis_layout / button_names 保持 Variant = null：null（自动推断）与 {}（手动但为空）语义不同，用空字典代替会让「自动」变成「什么都没覆盖」"
  - "AppConfig 不移植 `path` 字段：Godot 无 pathlib，来源路径归 ConfigResult.source_path（03-04），域对象不记录 I/O 痕迹"

patterns-established:
  - "Pattern 1：词汇表条目数即契约 —— size() 断言先于行为断言，多一条是自创词汇，少一条是某写法不认"
  - "Pattern 2：域对象与校验彻底分离 —— 类里只有字段与 _init，非法值一律由 ConfigValidator 转成 ConfigError"
  - "Pattern 3：引用类型泄漏用「改调用方 / 清返回值」两种反向操作证明，而不是靠读代码相信 duplicate()"

requirements-completed: []

coverage:
  - id: D1
    description: "配置里的按键与方向写法解析成与桌面版相同的规范值：L1→LB、R2→RT、TRIANGLE→Y、dpad_up→DPAD_UP、前右→45、RIGHT→90、-90→270"
    requirement: RESIL-02
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_vocabulary.gd（经 bash mobile/tools/test-core.sh，TESTS_SUITES=3）"
        status: pass
    human_judgment: false
  - id: D2
    description: "无法识别的按键返回空字符串、方向返回 null；core 不抛异常、不打印、不 push_error"
    requirement: RESIL-02
    verification:
      - kind: unit
        ref: "test_vocabulary.gd 的 _expect_button(\"nope\", \"\") / _expect_null(...) + python3 tools/lint_core_purity.py mobile/src/core（LINT_OK files=9）"
        status: pass
    human_judgment: false
  - id: D3
    description: "布尔值不是方向：true / false 都在 typeof 守卫处返回 null，不靠 float(true)=1.0 兜底"
    requirement: RESIL-02
    verification:
      - kind: unit
        ref: "test_vocabulary.gd 两条布尔断言 + direction_table.gd 的 TYPE_BOOL 分支"
        status: pass
    human_judgment: false
  - id: D4
    description: "六个域对象默认值与 desktop/padskills/config.py 的 dataclass 逐字段相同，Skill.pattern 默认一条 Pulse（low 0.8 / high 0.0 / 120ms / gap 0）"
    requirement: RESIL-02
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_models.gd（12 + 5 + 4 + 4 + 4 + 10 个字段逐一断言）"
        status: pass
    human_judgment: false
  - id: D5
    description: "AppConfig.enabled_skills() 返回新数组：过滤 disabled、保持顺序，清空返回值后内部 skills 仍是 3 条"
    requirement: RESIL-02
    verification:
      - kind: unit
        ref: "test_models.gd 的 _check_app_config（result.clear() 后断言内部长度不变）"
        status: pass
    human_judgment: false
  - id: D6
    description: "每个 class_name 独占一个文件，Array[Skill] / Array[Pulse] / Array[String] 类型化容器真的能编译"
    requirement: RESIL-03
    verification:
      - kind: integration
        ref: "bash mobile/tools/test-core.sh（preload 全部成功、TESTS_DONE failures=0）"
        status: pass
    human_judgment: false
  - id: D7
    description: "词汇表与容器零引擎依赖：新增 8 个 core 文件后 lint 仍 LINT_OK，扫描文件数从 1 增到 9"
    requirement: INFRA-03
    verification:
      - kind: unit
        ref: "python3 tools/lint_core_purity.py mobile/src/core（LINT_OK files=9）"
        status: pass
    human_judgment: false

duration: 5min
completed: 2026-11-05
status: complete
---

# Phase 3 Plan 03: 配置词汇表 + 域模型 Summary

**把「配置里能写什么」落成两张查表与六个纯数据对象：39 条按键别名、42 条方向别名、12 个 InputConfig 字段全部与桌面版逐字段对齐，失败是空串 / null 而不是异常**

## Performance

- **Duration:** 5 min
- **Started:** 2026-11-04T19:33:58Z（plan 基线提交 `2f4be8c` 时刻）
- **Completed:** 2026-11-04T19:39Z
- **Tasks:** 3
- **Files modified:** 21（20 新建、1 修改）

## Accomplishments

- `buttons.gd` 落地 17 个规范按键名与 39 条别名：PlayStation（`L1` → `LB`、`R2` → `RT`、`TRIANGLE` → `Y`）、Xbox / 通用、以及去分隔符形态（`LEFTSHOULDERBUTTON` → `LB`）。`canonical()` 依次做 strip / upper / 三种分隔符剥除 / 查表 / 命中规范表判定，失败返回空串。
- `direction_table.gd` 落地 42 条方向别名（英文 22 + 中文 20，含四个斜向）与 `resolve()`：布尔先挡掉、数值走 `fposmod`、字符串去分隔符后查表再试数字。`true` / `false` / `"clockwisee"` / `""` / `null` / 字典 / 数组全部返回 `null`。
- `pulse.gd` / `step.gd` / `skill.gd` 落地动作规则三件套，三个 `class_name` 各占一个文件，`Array[Pulse]` 与 `Array[String]` 类型化容器编译通过。`Skill.pattern` 默认一条 `Pulse`（对应 Python 的 `(Pulse(),)`），`rumble_summary()` 复刻「单震 low=0.80 high=0.00 120ms」与「N 连震」两个分支。
- `input_config.gd` / `rumble_config.gd` / `app_config.gd` 落地配置容器：12 + 5 + 4 个字段逐字段对齐 `config.py`，`axis_layout` / `button_names` 保留 `Variant = null` 以区分「自动推断」与「手动但为空」，`enabled_skills()` 逐项 `append` 到新数组。
- `test_vocabulary.gd`（77 条断言中的 37 条）与 `test_models.gd`（24 条）把三张表条目数、每个字段默认值、两种引用泄漏都变成断言。`core_runner.gd` 的 `SUITES` 从 1 条扩到 3 条。
- 闸门保持绿：`bash mobile/tools/test-core.sh` → `TESTS_SUITES=3` / `TESTS_ASSERTIONS=131` / `TESTS_DONE failures=0`；`python3 tools/lint_core_purity.py mobile/src/core` → `LINT_OK files=9`；`bash tools/check_desktop.sh` 230 项全绿；`bash mobile/tools/gate-a.sh` → `PACK_OK` / `GLYPH_OK chars=818`。

## Task Commits

1. **Task 1: 词汇表端到端——配置里怎么写，移动端就怎么认** — `9e14ace` (feat)
2. **Task 2: 动作规则三件套——Pulse / Step / Skill** — `f881f93` (feat)
3. **Task 3: 配置容器——InputConfig / RumbleConfig / AppConfig 与缺省对等** — `be18bef` (feat)

**Plan metadata:** 见本次最终 docs 提交（SUMMARY / STATE / ROADMAP）

## Files Created/Modified

- `mobile/src/core/domain/buttons.gd` — 17 规范名 + 39 别名 + `canonical()`，失败返回空串
- `mobile/src/core/domain/direction_table.gd` — 42 条方向别名 + `resolve()`，失败返回 null
- `mobile/src/core/domain/pulse.gd` — 四字段震动，默认 0.8 / 0.0 / 120 / 0
- `mobile/src/core/domain/step.gd` — `angles: Array[float]`（构造时复制）+ `hold_ms`
- `mobile/src/core/domain/skill.gd` — KIND_* / MODE_* 常量、10 字段、`pattern` 默认一条 Pulse、`rumble_summary()`
- `mobile/src/core/domain/input_config.gd` — 12 字段，含 `axis_layout` / `button_names` 的 null 语义
- `mobile/src/core/domain/rumble_config.gd` — 5 字段，`backend` 默认 `&"auto"`
- `mobile/src/core/domain/app_config.gd` — input / rumble / skills / global_cooldown_ms 60 + `enabled_skills()`
- 上述 8 个文件的 `.gd.uid` — `--import` 生成的导入边车（提交物）
- `mobile/tests/unit/test_vocabulary.gd` — 三张表条目数、别名、大小写、分隔符、布尔拒绝、真实配置四写法
- `mobile/tests/unit/test_models.gd` — 六个域对象默认值逐字段、Step 复制语义、默认 Pulse 实例独立、三处 rumble_summary
- `mobile/tests/unit/test_vocabulary.gd.uid`、`mobile/tests/unit/test_models.gd.uid` — 导入边车
- `mobile/tests/core_runner.gd` — `SUITES` 增 `models` 与 `vocabulary`，按字母序

## Decisions Made

- **字符串 `"-90"` 的负号按分隔符剥掉**，解析成 90.0，与 Python `config.py:129-130` 的 strip 顺序逐字一致；要 270° 必须写数字 `-90`。这条既有行为被显式断言 + 注释钉死：改成保留负号会让同一份配置在两端相差 180°，那比这个写法本身更难查。
- **条目数就是契约**：`CANONICAL.size() == 17` / `ALIASES.size() == 39` / `ALIASES.size() == 42` 是 `test_vocabulary.gd` 的第一组断言。增删别名必须先改测试，词汇表不可能悄悄漂移。
- **不做 enum 双向表、不做基类、不做 `direction_name()`**：种类与模式用 `StringName` 常量（值来自 JSON、要出现在错误消息里）；`direction_name()` 按 RESEARCH Open Question 5 不移植。
- **`Skill.pattern` 用成员初始化器** `[Pulse.new()]`（4.7.2 接受跨 `class_name` 引用），并额外断言两个 `Skill` 的默认 `Pulse` 不是同一实例 —— 「每实例各建一条」是可观测语义，不是实现细节。
- **`axis_layout` / `button_names` 保持 `Variant = null`**：`null`（自动推断）与 `{}`（手动覆盖但为空）是两种配置意图，用空字典替代会让「自动」静默变成「一条都没覆盖」。
- **`AppConfig` 不移植 `path`**：Godot 无 pathlib；来源路径属于「这次从哪加载」的运行期元数据，归 `ConfigResult.source_path`（03-04），域对象不记录 I/O 痕迹。
- **RESIL-02 不在本计划标记完成**：本计划只交付需求的前半截（词汇与数据形状），错误对象 + 校验器 + 错误屏在 03-04 / 03-06。现在勾选等于用「类型定义好了」冒充「坏配置能给出可操作信息」。

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - 测试期望错误] 字符串 `"-90"` 的方向期望值写成了 270.0**

- **Found during:** Task 1 首次跑闸门（`TESTS_FAIL vocabulary: 字符串负角 "-90" 归一为 270°（实际 90.0…）`）
- **Issue:** 计划只要求数字 `-90 → 270.0`，我在测试里额外加了一条「字符串 `-90` → 270°」。但实现（与计划规格、与 Python `config.py:129-130`）在数值解析**之前**就把 `-` 当分隔符剥掉，字符串 `"-90"` 得到 `"90"` → 90.0。测试期望与规格相反。
- **Fix:** 保留测试用例但改正期望为 90.0，并加三行注释说明「负号是分隔符、这是与桌面版一致的既有语义、改成保留负号会让两端相差 180°」。实现一个字未改。
- **Files modified:** mobile/tests/unit/test_vocabulary.gd
- **Verification:** `bash mobile/tools/test-core.sh` → `TESTS_SUITES=2` / `TESTS_DONE failures=0`；数字 `-90` 的 270.0 断言仍在且通过。
- **Committed in:** `9e14ace`（Task 1 提交）

**2. [Rule 1 - 机械验收] `duplicate()` 在注释里多出现一次，`grep -c == 1` 会红**

- **Found during:** Task 2 验收准备
- **Issue:** 验收要求 `grep -c 'duplicate()' mobile/src/core/domain/step.gd` 等于 1，但实现行与说明它为什么存在的注释行各含一次，`grep -c` 数的是行数 → 2。
- **Fix:** 注释改成「浅拷贝足够：Array[float] 的元素是值类型。」，不写 `duplicate()` 字面量；`duplicate()` 调用本身与语义不变。
- **Files modified:** mobile/src/core/domain/step.gd
- **Verification:** `grep -c 'duplicate()'` = 1；`bash mobile/tools/test-core.sh` 仍 `TESTS_SUITES=3` / `failures=0`，复制语义断言仍通过。
- **Committed in:** `f881f93`（Task 2 提交）

---

**Total deviations:** 2 auto-fixed（1 处我自己的测试期望写错 + 1 处机械验收形状）
**Impact on plan:** 无功能/安全影响；判据强度未变，没有删除或放宽任何断言。

## Issues Encountered

- 计划对 `const CANONICAL: Array[String]` 预留了「4.7.2 可能拒绝类型化 const 数组」的退路 —— 实测**接受**，无需退化成 `const CANONICAL := [...]`。
- 计划对 `var pattern: Array[Pulse] = [Pulse.new()]` 预留了「成员初始化器可能拒绝跨 `class_name` 引用」的退路 —— 实测**接受**，默认值留在成员初始化器，可观测默认值不变（未退回空数组）。
- 本机没有 `gsd_run` 命令（`command -v gsd_run` 为空），STATE.md / ROADMAP.md 按 `state advance-plan` / `roadmap update-plan-progress` 的语义手工更新。

## User Setup Required

None - 无外部服务或环境变量；Godot 4.7.2 已在 Phase 2 安装并校验。

## Next Phase Readiness

- `03-04` 可以直接在 `mobile/src/core/domain/` 的类型上建 `ConfigError` / `ConfigResult` / `ConfigValidator`：`Buttons.canonical()` 的空串与 `DirectionTable.resolve()` 的 `null` 就是它要转成 `button_unknown` / `direction_unknown` 的两个入口。
- `Array[Skill]` / `Array[Pulse]` / `Array[String]` 已在真实编译路径上验证（`SUITES` 三条套件 + `--import` 全过），Phase 5 的检测器可以直接持有它们。
- 新增域对象时两条硬约定：一个文件一个 `class_name`；默认值必须同时写进 `test_models.gd`，否则「缺省对等」没有机械证据。
- `bash mobile/tools/test-core.sh` 现在覆盖 9 个 core 文件 + 3 条套件；后续加文件不需要改闸门脚本，只需要在 `SUITES` 里显式 `preload`。

## Known Stubs

None.

## Threat Flags

None — 本计划未引入威胁模型之外的新表面。T-03-10…T-03-13 全部按计划落地：布尔在 `typeof` 处被拒绝（硬断言两条）、两张表逐条照抄并在文件头标注来源行号、`Step.angles` 复制与 `enabled_skills()` 新数组各有一条反向断言、域对象里零校验零日志（lint 全量扫描 `src/core/`）。T-03-SC 无包管理器安装。

## Self-Check: PASSED

- 21 个交付文件全部存在（8 个域对象 + 8 个 `.uid` + 2 个测试 + 2 个测试 `.uid` + `core_runner.gd`）。
- 三个提交 `9e14ace` / `f881f93` / `be18bef` 均为 HEAD 祖先；`plan_head_before..HEAD` 实测 3 个提交，与 `actuals.commits` 一致。
- `bash mobile/tools/test-core.sh`（`TESTS_SUITES=3` / `TESTS_ASSERTIONS=131` / `TESTS_DONE failures=0`）、`python3 tools/lint_core_purity.py mobile/src/core`（`LINT_OK files=9`）、`bash tools/check_desktop.sh`（230 项）、`bash mobile/tools/gate-a.sh`（`PACK_OK` / `GLYPH_OK`）在本次执行中全部通过。
