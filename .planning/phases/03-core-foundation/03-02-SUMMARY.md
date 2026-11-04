---
phase: 03-core-foundation
plan: 02
subsystem: infra
tags: [gdscript, lint, architecture-boundary, python-stdlib, shell-gate, canary-test]

requires:
  - phase: 03-core-foundation
    plan: 01
    provides: 无头 runner、几何黄金链、test-core.sh 唯一入口与哨兵文化
  - phase: 02-android-toolchain
    provides: Godot 4.7.2 安装与版本断言、闸门脚本的哨兵/有界重试风格

provides:
  - "tools/lint_core_purity.py：注释/字符串剥离状态机 + 14 条规则 + 0/1/2 三档退出码"
  - "tools/test_lint_core_purity.py：54 项反例自测（五条硬规则 + 九条扩展规则 + 三档退出码 + 文档互锁）"
  - "mobile/docs/CORE.md：「零引擎依赖」的可执行定义、允许/禁止清单与规则表"
  - "mobile/tools/test-core.sh：反例自测 → 真 lint → Godot 的固定顺序"
  - "mobile/README.md：四条入口命令与目录现状（src/core/、tests/、docs/CORE.md）"

affects: [03-03, 03-04, 03-05, 03-06, phase-4-detectors, phase-9-ci]

actuals:
  tokens: 6879
  tasks: 2
  commits: 2

plan_head_before: f727c03ceb0a51d6d8f4552c0e7c9b633652b254
plan_head_after: fa18e24b4097bc02e71c72d710b052dd08126720

tech-stack:
  added: []
  patterns:
    - "两档剥离：strip_code（注释 + 字符串）与 strip_comments（仅注释），后者只服务依赖路径字面量的规则"
    - "正向哨兵 LINT_OK files=N + 三档退出码 0 / 1 / 2（扫不到 ≠ 干净）"
    - "lint 自带反例自测，且自测先于真扫描；规则表与文档由 --list-rules 互锁"

key-files:
  created:
    - tools/lint_core_purity.py
    - tools/test_lint_core_purity.py
    - mobile/docs/CORE.md
  modified:
    - mobile/tools/test-core.sh
    - mobile/README.md

key-decisions:
  - "strip_code 逐字保留 RESEARCH 原型；另加 strip_comments 只剥注释，仅 outer_layer_dep 使用 —— 该规则必须看到 res:// 字面量，否则永远不可能命中"
  - "扫描目标不存在或零个 .gd 一律 rc=2 并打印 LINT_INVALID：路径写错等于自动通过的假绿比漏报更危险"
  - "规则大小写敏感且用词边界，InputSource / NodeState / NodePath 与小写 input.deadzone 都不误伤"
  - "反例自测必须先于真 lint：一条被写坏的规则会以「干净通过」的形式保护一切"
  - "步骤横幅带脚本名（tools/test_lint_core_purity.py / tools/lint_core_purity.py），让「先于 Godot」可被 grep 机械验证"
  - "lint 只扫 mobile/src/core；tests/ 允许 print/printerr，不把测试代码的日志需求当边界违规"

patterns-established:
  - "Pattern 1：架构边界用纯文本扫描器（零依赖、毫秒级）而不是 --check-only（对解析错误也返回 0）"
  - "Pattern 2：每条硬规则一条独立 canary，外加一份「五个 token 全写在注释/字符串里」的干净 canary"
  - "Pattern 3：文档与规则表用 --list-rules 互相钉住，规则增删必须同步改文档与自测"

requirements-completed: [INFRA-03]

coverage:
  - id: D1
    description: "干净 core 上 lint 退出 0 并打印 LINT_OK files=N（N >= 1）"
    requirement: INFRA-03
    verification:
      - kind: unit
        ref: "python3 tools/lint_core_purity.py mobile/src/core"
        status: pass
    human_judgment: false
  - id: D2
    description: "五条硬规则各自有牙齿：Input. / Time. / Node / FileAccess / print( / push_error( 命中对应规则 id"
    requirement: INFRA-03
    verification:
      - kind: unit
        ref: "python3 tools/test_lint_core_purity.py（test_hard_rules_have_teeth）"
        status: pass
    human_judgment: false
  - id: D3
    description: "注释、文档字符串、双/单/三引号、raw string 里的同样 token 零误报，合法标识符不误伤"
    requirement: INFRA-03
    verification:
      - kind: unit
        ref: "python3 tools/test_lint_core_purity.py（test_clean_canary）"
        status: pass
    human_judgment: false
  - id: D4
    description: "空目录与不存在的路径都返回 2 并打印 LINT_INVALID，「什么都没扫到」不冒充干净"
    requirement: INFRA-03
    verification:
      - kind: unit
        ref: "python3 tools/test_lint_core_purity.py（test_exit_codes）"
        status: pass
    human_judgment: false
  - id: D5
    description: "九条扩展规则各自有牙齿，且 preload(res://src/core/...) 与注释里的反向依赖不误报"
    requirement: INFRA-03
    verification:
      - kind: unit
        ref: "python3 tools/test_lint_core_purity.py（test_extended_rules_have_teeth）"
        status: pass
    human_judgment: false
  - id: D6
    description: "CORE.md 与 --list-rules 同源：14 条规则 id 全部出现，且保留 LINT_OK 与退出码 2 的契约"
    requirement: INFRA-03
    verification:
      - kind: unit
        ref: "python3 tools/test_lint_core_purity.py（test_doc_and_rules_are_locked）"
        status: pass
    human_judgment: false
  - id: D7
    description: "test-core.sh 中反例自测 → 真 lint → Godot 导入的固定顺序，且真实越界会让闸门指名变红"
    requirement: INFRA-03
    verification:
      - kind: integration
        ref: "bash mobile/tools/test-core.sh（步骤行号 2 < 64 < 68；追加 Time.get_ticks_usec 后 rc=1 并指名 time_singleton）"
        status: pass
    human_judgment: false

duration: 4min
completed: 2026-11-05
status: complete
---

# Phase 3 Plan 02: 架构 lint + 「零引擎依赖」的可执行定义 Summary

**把「零引擎依赖」变成一台机器：14 条规则的纯文本扫描器（干净 0 / 命中 1 / 扫不到 2）、54 项反例自测，以及与规则表互锁的 CORE.md**

## Performance

- **Duration:** 4 min
- **Started:** 2026-11-04T19:27:56Z
- **Completed:** 2026-11-04T19:31:53Z
- **Tasks:** 2
- **Files modified:** 5（3 新建、2 修改）

## Accomplishments

- `tools/lint_core_purity.py` 上线：逐字符状态机先剥注释与字符串（保留换行与列位置），再按行匹配 14 条规则。干净树 `LINT_OK files=1` 退出 0；脏 canary 输出 `mobile/src/core/geometry.gd:53: time_singleton: Time.` 并退出 1；空目录与不存在的路径退出 2 且打印 `LINT_INVALID`。
- `tools/test_lint_core_purity.py` 用 54 项断言证明 lint 有牙齿：五条硬规则各一条 canary、九条扩展规则各一条 canary、`push_error(` / `printerr(` 归 `logging`、干净 canary（五个 token 全写在 `##` / `#` / 双引号 / 单引号 / 三引号 / raw string 里）零误报、退出码 0/1/2 三档、`--list-rules` 14 行且前五顺序固定。
- `mobile/docs/CORE.md` 把边界写成五节可执行定义：这一层是什么、允许/禁止清单（14 条规则逐条）、`JSON`/`RegEx` 例外与 `FileAccess` 非例外、退出码契约、怎么加套件与夹具。自测机械断言文档列出全部规则 id。
- `mobile/tools/test-core.sh` 的固定顺序变成：配置副本校验 → lint 反例自测 → 真 lint → 几何黄金校验 → 无头导入 → 套件。两个 lint 步骤都排在 `--import` 之前；给 `geometry.gd` 追加一行 `Time.get_ticks_usec()` 后整条闸门 rc=1 并指名 `time_singleton`，还原后重新全绿。
- `mobile/README.md` 的「三条入口命令」改成四条，补上 `src/core/`、`tests/`、`docs/CORE.md` 三个目录说明。
- 回归红线保持：`bash tools/check_desktop.sh` 230 项全绿、`bash mobile/tools/gate-a.sh` `PACK_OK skills=5` 且 `GLYPH_OK chars=818`。

## Task Commits

1. **Task 1: 扫描器上线，并在真实 core 与脏 canary 上各判一次** — `c807e87` (feat)
2. **Task 2: 反例自测 + 「零引擎依赖」的可执行定义，让文档与规则表互锁** — `fa18e24` (feat)

**Plan metadata:** 见本次最终 docs 提交（SUMMARY / STATE / ROADMAP / REQUIREMENTS）

## Files Created/Modified

- `tools/lint_core_purity.py` — 架构边界扫描器：两档剥离状态机 + 14 条规则 + 0/1/2 退出码 + `--list-rules`
- `tools/test_lint_core_purity.py` — 反例自测：54 项断言，覆盖 clean canary、硬规则、扩展规则、退出码、行号、文档互锁、规则表稳定性
- `mobile/docs/CORE.md` — 「零引擎依赖」的五节可执行定义，含 14 条规则表与退出码契约
- `mobile/tools/test-core.sh` — 新增「反例自测」与「真 lint」两步，均排在 Godot 之前
- `mobile/README.md` — 四条入口命令；目录现状补 `src/core/`、`tests/`、`docs/CORE.md`

## Decisions Made

- `strip_code` 逐字保留 RESEARCH 原型；另加 `strip_comments` 只剥注释、保留字符串内容，仅 `outer_layer_dep` 使用 —— 该规则要匹配 `"res://src/app/` 字面量，字符串一旦被空格化就永远不可能命中（见 Deviations 1）。
- 扫描目标不存在或目录里零个 `.gd` 一律 rc=2：路径写错时返回 0 等于自动通过，比漏报更危险。
- 规则大小写敏感并带词边界：`InputSource` / `NodeState` / `NodePath` / `_input.deadzone` 都不误伤；这是「边界与解释可以共存」的前提。
- 自测必须先于真 lint：一条被写坏的规则会以「干净通过」的形式保护一切。
- lint 只扫 `mobile/src/core`，不扫 `tests/`：测试代码需要 `print` / `printerr`，把日志需求当边界违规会逼人删规则。
- 步骤横幅带上脚本名，让「lint 先于 Godot」可以被 `grep -n` 机械验证，而不是靠读脚本相信顺序。

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `outer_layer_dep` 在剥离字符串后永远无法命中**

- **Found during:** Task 1（编写规则表与剥离器时）
- **Issue:** RESEARCH 原型把注释与字符串一律替换成空格，但 `outer_layer_dep` 的正则要求匹配 `(?:preload|load)\s*\(\s*"res://src/(?:platform|ui|app)/`。字符串被空格化后，这条规则**永远不会响** —— 一条没有牙齿的规则比没有规则更糟，它会让人以为反向依赖被挡住了。
- **Fix:** 把状态机抽成 `_mask(text, drop_strings)` 两档：`strip_code` 保持原型行为（注释 + 字符串全部空格化），`strip_comments` 只剥注释、保留字符串内容；只有 `outer_layer_dep` 对后者匹配。代价（错误消息里逐字写出 `preload("res://src/app/...")` 会误报）写进工具 docstring 与 `CORE.md` 的已知漏报节。
- **Files modified:** `tools/lint_core_purity.py`
- **Verification:** 自测中 `preload("res://src/app/config_store.gd")` 命中 `outer_layer_dep`；`preload("res://src/core/geometry.gd")` 与注释里的同样文本均 0 命中。
- **Committed in:** `c807e87`（Task 1 提交）

**2. [Rule 1 - 机械验收] 步骤横幅加上脚本名，否则「先于 Godot」无法机械比较**

- **Found during:** Task 2 验收准备
- **Issue:** 验收要求「输出里 `test_lint_core_purity.py` 的步骤行号早于 `lint_core_purity.py` 的步骤行号」，但计划给的横幅文案只有「校验 lint 自身的反例…」，输出里 grep 不到脚本名，判据无法执行。
- **Fix:** 两条 `▸` 横幅改为 `…（tools/test_lint_core_purity.py）` 与 `…（tools/lint_core_purity.py）`；执行逻辑与判定完全不变。
- **Files modified:** `mobile/tools/test-core.sh`
- **Verification:** `grep -n` 实测行号 2（自测）< 64（真 lint）< 68（导入）。
- **Committed in:** `fa18e24`（Task 2 提交）

**3. [Rule 1 - 文案一致性] test-core.sh 头部「证明四件事」与实际步骤数不符**

- **Found during:** Task 1
- **Issue:** 插入 lint 步骤后，头部注释仍写着「同时证明四件事」，读者会低估闸门覆盖面。
- **Fix:** 改为六件事并补上「lint 的反例仍会变红」「src/core 没有越出零引擎依赖边界」两条；最终成功消息同步加上「边界干净」。
- **Files modified:** `mobile/tools/test-core.sh`
- **Verification:** 头注释与实际 6 个判定步骤逐条对应；闸门输出与文案一致。
- **Committed in:** `c807e87`（Task 1）与 `fa18e24`（Task 2）

---

**Total deviations:** 3 auto-fixed（1 处规则失效 bug + 1 处机械验收形状 + 1 处文案同步）
**Impact on plan:** 无功能/安全影响；三处都保留了原判据的强度，未删除、放宽或注释掉任何一条硬规则。

## Issues Encountered

- 本机没有 `gsd_run` 命令（`command -v gsd_run` 为空），GSD 状态更新改为手工编辑 `STATE.md` / `ROADMAP.md` / `REQUIREMENTS.md`；内容与 `state advance-plan` / `roadmap update-plan-progress` / `requirements mark-complete` 的语义一致。
- 扫描器用 `path.read_text(encoding="utf-8", errors="replace")` 读取源码：GDScript 源码理应是合法 UTF-8，但一个坏字节不应该让 lint 自己崩掉（崩溃会被误读成「没有命中」）。

## User Setup Required

None - 无外部服务或环境变量配置；lint 与自测只用 Python 标准库。

## Next Phase Readiness

- `03-03`（按键/方向词汇表 + 六个域对象）可以直接往 `mobile/src/core/domain/` 里加文件：每次 `bash mobile/tools/test-core.sh` 都会先跑边界 lint，越界立刻指名。
- 新增规则时三处必须同步：`tools/lint_core_purity.py` 的 `RULES`、`mobile/docs/CORE.md` 的规则表、`tools/test_lint_core_purity.py` 的 canary；自测会拦住只改一处的情况。
- 后续计划若要给 `test-core.sh` 加步骤，保持「纯 Python 检查在 Godot 之前」这条顺序；现有步骤行号已可作为插入点参照。

## Known Stubs

None.

## Threat Flags

None — 本计划未引入威胁模型之外的新表面。T-03-06…T-03-09 全部按计划落地：五条硬规则 + 九条扩展规则、脏 canary 逐条证明、`LINT_INVALID` 覆盖路径写错、文档与规则表互锁；零包管理器安装，只用 Python 标准库。

## Self-Check: PASSED

- 5 个交付文件全部存在。
- 两个提交 `c807e87` / `fa18e24` 均为 HEAD 祖先；`plan_head_before..HEAD` 实测 2 个代码提交，与 `actuals.commits` 一致。
- `python3 tools/test_lint_core_purity.py`（54 项，失败 0）、`bash mobile/tools/test-core.sh`、`bash mobile/tools/gate-a.sh`、`bash tools/check_desktop.sh`（230 项）在本次执行中全部通过。
