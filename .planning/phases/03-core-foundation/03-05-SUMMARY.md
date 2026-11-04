---
phase: 03-core-foundation
plan: 05
subsystem: core
tags: [gdscript, python, config-validation, corpus, cross-language-parity, divergence, fixture, gate]

requires:
  - phase: 03-core-foundation
    plan: 01
    provides: 无头 runner、`TESTS_DONE failures=0` 完成哨兵、`test-core.sh` 唯一入口
  - phase: 03-core-foundation
    plan: 02
    provides: `lint_core_purity.py` 与 `CORE.md` 的零引擎依赖边界
  - phase: 03-core-foundation
    plan: 03
    provides: `DirectionTable.resolve()`、`Buttons.canonical()`、六个域对象
  - phase: 03-core-foundation
    plan: 04
    provides: `ConfigLoader.parse_bytes`（BOM 字节入口）、`ConfigResult` / `ConfigError`、全量校验与错误码表
  - phase: 02-android-toolchain
    provides: Godot 4.7.2 与 `*.gd.uid` 提交约定

provides:
  - "mobile/tests/fixtures/config_corpus.json：28 条跨语言语料，覆盖 24 个错误码 + 3 条接受路径"
  - "mobile/tests/unit/test_config_corpus.gd：逐用例断言 ok/codes/json_path 与 to_text() 可渲染性，含规模与唯一 id 下限"
  - "tools/check_config_parity.py：Python 侧判定器（load_config 的 str 路径 + parse_config + build_detector），三类分歧失败出口"
  - "mobile/tests/core_runner.gd：SUITES 扩到 6 条（新增 config_corpus）"
  - "mobile/tools/test-core.sh：对等检查成为 Godot 之前的固定一步"

affects: [03-06, phase-5-parity, phase-7-feedback]

actuals:
  tokens: 8376
  tasks: 3
  commits: 3

plan_head_before: d090ddaa2d11b58fc5beaac55316b0cedfc699a8
plan_head_after: 3302abf276fea674a10d282c0c6d14b1f6e0ff1b

tech-stack:
  added: []
  patterns:
    - "语料即契约：同一份 JSON 用例被两套实现各判一次，期望值只存在于语料里"
    - "分歧必须可检索：divergence 非空 + python.note 非空；判定一致却还留着记录也判红"
    - "Python 侧模拟真实加载路径：read_text + json.loads(str)，BOM 作为 U+FEFF 进入字符串"
    - "accept 用例再跑 build_detector：抓 parse 通过、构造检测器才崩的晚失败"

key-files:
  created:
    - mobile/tests/fixtures/config_corpus.json
    - mobile/tests/unit/test_config_corpus.gd
    - mobile/tests/unit/test_config_corpus.gd.uid
    - tools/check_config_parity.py
  modified:
    - mobile/tests/core_runner.gd
    - mobile/tools/test-core.sh

key-decisions:
  - "语料规模下限保留 `cases.size() >= 4`（四个点名用例的防真空绿锚点），另加 `>= 16`（T-03-21：只留 4 条时旧断言发现不了语料被删空）"
  - "每个用例必须有唯一 id；重复 id 会让失败定位失真，GDScript 套件直接判红"
  - "`params_not_object` 用空数组 `[]`：Python 的 `raw.get(\"params\") or {}` 把 falsy 值静默变成默认字典，是又一处「Python 接受、移动端拒绝」，按分歧记录而不是改语料迁就"
  - "`direction_unknown` 只写在 arc 的 `params.direction`：Python 仅在此处静默落 any；sequence 步方向未知时 Python 会抛 ValueError，写在那里会变成两侧都拒的假分歧"
  - "`button_mode_invalid` 必须带 `required_button`：Python 的 `_parse_required_buttons` 在 required_button 为 None 时提前返回，根本不看 button_mode"
  - "Python 判定器不重新实现规则：规则只在 `desktop/padskills/config.py`，工具只负责调用与比对"
  - "`PARITY_OK cases=N divergences=M` 把条数与分歧数打进日志：空语料或分歧记录丢失时不会静默变绿"
  - "RESIL-02 在本计划标记完成：结构化错误（03-04）+ 跨语言判定对等（本计划）两半都已闭合"

patterns-established:
  - "Pattern 1：双向语料 —— 每条用例同时写 godot 与 python 期望，任何一侧单独改动都会让对等检查变红"
  - "Pattern 2：分歧三态 —— 判定不同必须记录；记录存在但 note 为空也不行；分歧修复后旧记录必须删除"
  - "Pattern 3：三条失败出口 —— 渲染失败、基线路径失败（BOM 被 utf-8-sig 接受）、晚失败漏检（build_detector）各有独立检查"

requirements-completed: [RESIL-02]

coverage:
  - id: D1
    description: "BOM / 字符串布尔 / null 数值 / start_angle 数组四个点名坏输入各有一条语料用例，GDScript 侧断言 code 与 json_path 同时出现在 to_text() 里"
    requirement: RESIL-02
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_config_corpus.gd + mobile/tests/fixtures/config_corpus.json#bom,string_bool,null_number,start_angle_array"
        status: pass
    human_judgment: false
  - id: D2
    description: "语料覆盖结构 / 三类动作参数 / 修饰键 / input·rumble / 语义 / 多错误六个族，28 条用例、24 个不同错误码、3 条接受路径"
    requirement: RESIL-02
    verification:
      - kind: unit
        ref: "bash mobile/tools/test-core.sh（TESTS_SUITES=6, TESTS_ASSERTIONS=484, TESTS_DONE failures=0）"
        status: pass
    human_judgment: false
  - id: D3
    description: "Python 侧判定器模拟 load_config 的真实字符串路径；BOM 不被 utf-8-sig 悄悄接受；accept 用例再跑 build_detector 抓晚失败"
    requirement: RESIL-02
    verification:
      - kind: integration
        ref: "python3 tools/check_config_parity.py（PARITY_OK cases=28 divergences=4）"
        status: pass
    human_judgment: false
  - id: D4
    description: "未记录的分歧会把闸门打红：清空 string_bool 的 divergence 后判定器退出 1 并打印 PARITY_FAIL string_bool；还原后恢复绿"
    requirement: RESIL-02
    verification:
      - kind: integration
        ref: "反例：清空 divergence → rc=1 + PARITY_FAIL string_bool；还原 → PARITY_OK cases=28 divergences=4"
        status: pass
    human_judgment: false
  - id: D5
    description: "对等检查接进 test-core.sh 且排在 import / Godot 测试之前；桌面 230 项与闸门 A 保持全绿"
    requirement: RESIL-02
    verification:
      - kind: integration
        ref: "bash mobile/tools/test-core.sh（check_config_parity 在第 71 行，--import 在第 84 行）+ bash tools/check_desktop.sh（230 项）+ bash mobile/tools/gate-a.sh（PACK_OK / GLYPH_OK）"
        status: pass
    human_judgment: false

duration: 4min
completed: 2026-11-05
status: complete
---

# Phase 3 Plan 05: 坏配置语料 + 跨语言判定对等 Summary

**同一份 28 条坏配置语料被 GDScript 与 Python 各判一次：24 个错误码全部命中，4 处故意分歧（字符串布尔、未知旋转方向、start_angle 晚失败、空 params 被 Python 当默认）每条都带可检索的 divergence 与说明，未记录的分歧会把闸门打成红色**

## Performance

- **Duration:** 4 min
- **Started:** 2026-11-04T19:52:52Z
- **Completed:** 2026-11-04T19:56:30Z
- **Tasks:** 3
- **Files modified:** 6（4 新建、2 修改）

## Accomplishments

- `config_corpus.json` 成为两端唯一契约：每条用例含 `id` / `data` 或 `text` / `bom` / `godot{verdict,codes,paths}` / `python{verdict,note}` / `divergence`。28 条用例覆盖结构、arc/sequence/taps 参数、修饰键交叉、input/rumble、语义与多错误六个族；24 个不同错误码各至少出现一次。
- 四个点名坏输入都在两侧可执行：BOM 用字节前拼 `EF BB BF`、字符串布尔断言 `bool_expected`、`null` 数值断言 `number_expected`、`start_angle` 数组断言 `start_angle_not_scalar`；每条都校验 `code` 与 `json_path` 同时出现在 `to_text()` 里，证明错误屏可以原样渲染。
- `test_config_corpus.gd` 先断言规模（≥ 4 与 ≥ 16）和唯一 id，再逐用例调用真实的 `ConfigLoader.parse_bytes`。语料删空、丢点名用例、复制 id 都会变红，不存在「零次循环、全部通过」的真空绿。
- `tools/check_config_parity.py` 走 `load_config` 的真实字符串路径：`json.loads(text)`，BOM 以 `\ufeff` 进入字符串（绝不走会按 `utf-8-sig` 接受 BOM 的字节路径）；`parse_config` 抓 `ValueError` 与 `TypeError`；对 accept 用例再跑 `build_detector`，抓住 `start_angle` 数组这种「parse 通过、构造检测器才崩」的晚失败。
- 分歧记录有完整三态：判定不同却无 `divergence` → 红；有 `divergence` 但 `python.note` 为空 → 红；判定一致却还留着 `divergence` → 红（记录已过时）。反例实测：清空 `string_bool` 的 `divergence` 后退出 1 并打印 `PARITY_FAIL string_bool`，还原后 `PARITY_OK cases=28 divergences=4`。
- `test-core.sh` 在几何黄金校验之后、任何 Godot 调用之前插入对等检查；顺序理由是纯 Python 越早失败越省时间，且「两端语义分叉」比「某一端自己红了」更需要先知道。
- 全部门槛保持绿：`test-core.sh` → `TESTS_SUITES=6` / `TESTS_ASSERTIONS=484` / `TESTS_DONE failures=0`；`check_config_parity.py` → `PARITY_OK cases=28 divergences=4`；`check_desktop.sh` → 230 项；`gate-a.sh` → `PACK_OK skills=5` / `GLYPH_OK chars=818`；`lint_core_purity.py` → `LINT_OK files=13`。

## Task Commits

1. **Task 1: 四个点名坏输入成为两端可执行的配置语料** — `f3530df` (feat)
2. **Task 2: 语料扩到 28 条，覆盖 24 个错误码与三条接受路径** — `cc437be` (feat)
3. **Task 3: Python 侧判定器上线，分歧未记录即判红** — `3302abf` (feat)

**Plan metadata:** 见本次最终 docs 提交（SUMMARY / STATE / ROADMAP / REQUIREMENTS）

## Files Created/Modified

- `mobile/tests/fixtures/config_corpus.json` — 28 条跨语言语料（711 行），三条入口形态 `data` / `text` / `bom`
- `mobile/tests/unit/test_config_corpus.gd` — 规模与唯一 id 下限、逐用例 ok/codes/json_path、`to_text()` 可渲染性
- `mobile/tests/unit/test_config_corpus.gd.uid` — Godot 导入生成的边车（提交物）
- `tools/check_config_parity.py` — Python 侧判定器（216 行），三类 `PARITY_FAIL` 出口与 `PARITY_OK` 哨兵
- `mobile/tests/core_runner.gd` — `SUITES` 增 `config_corpus`（共 6 条）
- `mobile/tools/test-core.sh` — 新增「校验配置判定在两端一致」一步，排在 Godot 导入之前

## Decisions Made

- **`>= 4` 与 `>= 16` 两条规模断言并存**：前者是四个点名用例的原始锚点（Task 1 acceptance 要求字面存在），后者是 T-03-21 的缓解（只留 4 条时，删掉大半语料不会被发现）。两条都留，机械检查与威胁缓解各取所需。
- **`params_not_object` 保留空数组写法**：Python 的 `raw.get("params") or {}` 把 `[]` 静默变成 `{}`，于是 Python 接受、移动端拒绝。这是真实的宽松面，按分歧记录（`params_empty_list_python_coerced_to_default`），不改成非空数组去「消灭」分歧。
- **`direction_unknown` 固定在 arc**：这是 Python 唯一静默落到 `any` 的位置（`detectors.py:154-160`）；sequence 的未知方向会抛 `ValueError`，写在那里会得到一条没有信息量的「两侧都拒」。
- **`button_mode_invalid` 必须带 `required_button`**：Python 的 `_parse_required_buttons` 在 `required_button is None` 时提前返回，根本不读 `button_mode`；不带 `required_button` 的用例在 Python 侧是 accept，无法测到模式白名单。
- **判定器不复制校验规则**：错误码、接受面、异常类型全部来自 `desktop/padskills`；工具只负责把语料喂给真实实现再比对，避免出现第二份「期望行为」的实现。
- **RESIL-02 在本计划勾选**：03-04 闭合了结构化错误与 `to_text()`，本计划闭合了「同一批坏配置在两端判定一致且分歧有记录」，需求的两半都已可机械核对。

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - 语料期望与 Python 实际行为不符] `button_mode_invalid` 在 Python 侧被静默接受**

- **Found during:** Task 3 首次运行 `check_config_parity.py`
- **Issue:** 计划写「`button_mode_invalid`（`button_mode: "some"`）」，但 Python 的 `_parse_required_buttons` 在 `required_button` 为 `None` 时提前 `return (), "all"`，完全不看 `button_mode`；该用例在 Python 侧是 accept，与语料记录的 reject 冲突。
- **Fix:** 给该用例补 `required_button: "RB"`，让 Python 真正走到 mode 白名单检查；GDScript 侧仍报 `button_mode_invalid`，两侧都拒、`divergence` 为空。`python.note` 写明这个提前返回的边界，避免下一个人再踩。
- **Files modified:** mobile/tests/fixtures/config_corpus.json
- **Verification:** `python3 tools/check_config_parity.py` → `PARITY_OK cases=28 divergences=4`；`bash mobile/tools/test-core.sh` → `TESTS_DONE failures=0`。
- **Committed in:** `3302abf`（Task 3 提交）

**2. [Rule 2 - 防真空绿] Task 2 同时把 GDScript 规模下限抬到 16**

- **Found during:** Task 2 扩充语料
- **Issue:** Task 1 的下限是 `cases.size() >= 4`；语料扩到 28 条后，若有人删掉 20 条，剩余 4 条仍能让旧断言通过。计划威胁模型 T-03-21 明确要求「Task 2 把下限抬到 16」，但 Task 2 的 `<files>` 只列了语料。
- **Fix:** 在 `test_config_corpus.gd` 保留原 `>= 4` 断言（Task 1 acceptance 的字面要求），并新增 `>= 16` 断言。
- **Files modified:** mobile/tests/unit/test_config_corpus.gd
- **Verification:** `grep -c 'cases.size() >= 4'` = 1；语料 28 条时两条断言均通过；`TESTS_DONE failures=0`。
- **Committed in:** `cc437be`（Task 2 提交）

**3. [Rule 2 - 契约自检] 新增唯一 id 断言**

- **Found during:** Task 1 编写套件
- **Issue:** 计划只要求四个点名 id 存在；重复 id 会让「哪条用例失败」的日志失去定位能力，且 Task 2 acceptance 只在 Python 侧检查唯一性。
- **Fix:** GDScript 侧新增 `ids.size() == cases.size()` 断言，重复或缺失 id 直接判红。
- **Files modified:** mobile/tests/unit/test_config_corpus.gd
- **Verification:** 28 条用例 28 个 id，套件全绿。
- **Committed in:** `f3530df`

**4. [Rule 1 - 文档与事实同步] `test-core.sh` 头部由「六件事」改为「七件事」**

- **Found during:** Task 3 接入对等检查
- **Issue:** 新增一步后，头部注释仍写「六件事」，最终哨兵也只列了几何套件；注释与实际检查项不一致会误导后来者。
- **Fix:** 更新头部枚举与最终 `✓` 行，加入「配置判定在两端一致 / 两端判定对等」。
- **Files modified:** mobile/tools/test-core.sh
- **Verification:** 闸门输出 `✓ 核心闸门通过：配置一致、边界干净、黄金未漂移、两端判定对等、核心套件全绿`。
- **Committed in:** `3302abf`

---

**Total deviations:** 4 auto-fixed（1 处语料期望错误、2 处防真空绿/契约补齐、1 处文档同步）
**Impact on plan:** 无功能削弱。`button_mode_invalid` 的修正让该规则真正被两端检查；新增的 `>= 16` 与唯一 id 断言只加强下限，没有放宽任何既有门槛。

## Issues Encountered

- 本机没有 `gsd_run` 命令（`command -v gsd_run` 为空），`state.json` / `STATE.md` / `ROADMAP.md` / `REQUIREMENTS.md` 按 `state advance-plan` / `update-progress` / `record-metric` / `requirements mark-complete` 的语义手工更新。
- Godot 输出里的 `Unicode parsing error ... (ff/fe)` 是 `test_config_loader.gd` 故意注入的非法 UTF-8 字节触发的预期噪声，不是本计划的失败。
- `button_mode_invalid` 的首次失败说明「语料先定、代码跟随」需要反过来一次：当语料对 Python 行为的假设本身错了，应修语料并记录，而不是给 Python 加特例。

## User Setup Required

None - 无外部服务或环境变量；Godot 4.7.2 已在 Phase 2 安装并校验。

## Next Phase Readiness

- `03-06` 可以直接复用本计划的语料结构做 `ConfigStore` / 覆盖层测试：`data` / `text` / `bom` 三种入口与 `to_text()` 可渲染性断言都已跑通。
- Phase 5 的轨迹回放对等（`shared/golden_vectors.json`）可以照抄本计划的三件套：语料（期望值唯一来源）+ 两侧判定器 + 分歧记录三态；不要另造一套「看起来一样」的断言。
- 新增错误码时的硬约定：先在 `config_validator.gd` 与 `config.py` 里确定行为，再把用例写进语料；语料不发明实现里不存在的码。若两侧判定不同，`divergence` 与 `python.note` 必须同时非空。
- `test-core.sh` 现在的固定顺序：配置副本 → lint 反例 → 架构边界 → 几何黄金 → 两端判定对等 → 导入 → 核心套件。新增纯 Python 检查应插在导入之前。

## Known Stubs

None.

## Threat Flags

None — 本计划未引入威胁模型之外的新表面。T-03-19（分歧未记录）由三类 `PARITY_FAIL` 出口缓解；T-03-20（Python 基线用错）由 `json.loads(text)` 单一路径与 `bom` 反例缓解；T-03-21（语料删空）由 ≥ 4 / ≥ 16 / 唯一 id / `PARITY_OK cases=` 四重锚点缓解；T-03-22（晚失败）由 accept 用例再跑 `build_detector` 缓解；T-03-SC 无包管理器安装。

## Self-Check: PASSED

- 6 个交付文件全部存在（语料 + 测试 + `.uid` + Python 工具 + runner + 闸门）。
- 3 个提交 `f3530df` / `cc437be` / `3302abf` 均为 HEAD 祖先；`plan_head_before..HEAD` 实测 3 个提交，与 `actuals.commits` 一致。
- `bash mobile/tools/test-core.sh`（`TESTS_SUITES=6` / `TESTS_ASSERTIONS=484` / `TESTS_DONE failures=0`）、`python3 tools/check_config_parity.py`（`PARITY_OK cases=28 divergences=4`）、`bash tools/check_desktop.sh`（230 项）、`bash mobile/tools/gate-a.sh`（`PACK_OK skills=5` / `GLYPH_OK chars=818`）在本次执行中全部通过。
- 反例实测：清空 `string_bool` 的 `divergence` → 退出 1 并打印 `PARITY_FAIL string_bool`；还原后恢复绿。
