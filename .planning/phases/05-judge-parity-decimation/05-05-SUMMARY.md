---
phase: 05-judge-parity-decimation
plan: 05
subsystem: judge-parity-decimation
tags:
  [
    python,
    gdscript,
    godot,
    decimation,
    golden-fixture,
    mutation-testing,
    judge-parity,
  ]

requires:
  - phase: 05-judge-parity-decimation
    plan: 01
    provides: `GESTURE_GOLDEN` 生成器骨架 / `_drive_detector` / `_drive_engine` / 哨兵纪律
  - phase: 05-judge-parity-decimation
    plan: 02
    provides: 55 条检测器语料（含 ±4ms 边界与变体配置）
  - phase: 05-judge-parity-decimation
    plan: 03
    provides: 29 条引擎运行时语料 / `GestureEngine`
  - phase: 05-judge-parity-decimation
    plan: 04
    provides: `measured{}` 全链（本计划不消费，但保持夹具与断言基线）

provides:
  - "`tools/decimate_trace.py`：最近样本 + 原始时间戳 + 按钮沿保底 + 五条自断言；复用 `gen_gesture_golden` 的参考驱动"
  - "`mobile/tests/fixtures/golden_decimated.json`：252 条（3 × 84）抽稀记录，含 `rule` / `source_id` / `vs_250`"
  - "`shared/decimation_allowlist.json`：34 条边界带漂移，双向校验，`reason` 全部非空"
  - "`mobile/tests/unit/test_decimation.gd`：L2 判定码回放 + 独立时间戳子集证明"
  - "哨兵 `DECIMATION rates=3 cases=252 mismatches=0`（下限 240）"

affects: [05-06-practice-wiring, 05-07-outcome-log, phase-6-training-loop, phase-7-feedback, phase-9-release]

actuals:
  tokens: 677678
  tasks: 3
  commits: 3

plan_head_before: 3f8845aaa8da27875219cc3a811d346d9a45a3e1
plan_head_after: 5fd872cca890ffc21e18f5f7c930fccd9b59c162

tech-stack:
  added: []
  patterns:
    - "抽样本不抽时间戳：边界只用于选样本，输出时间戳逐字来自源轨迹；网格化必须被断言 2 抓住"
    - "按钮沿保底：每个按钮变化必须保留「变化后」的样本，丢一条边沿 = 丢一整个判定"
    - "双向白名单：有漂移必须有条目，有条目必须仍漂移；`reason` 为空即红"
    - "边界带漂移按「±1 个采样周期」登记，不动任何生产阈值（D-05）"
    - "同一份夹具的期望必须由参考实现重放抽稀后的 frames 得到，绝不复制 250 Hz 期望"

key-files:
  created:
    - tools/decimate_trace.py
    - shared/decimation_allowlist.json
    - mobile/tests/fixtures/golden_decimated.json
    - mobile/tests/unit/test_decimation.gd
    - mobile/tests/unit/test_decimation.gd.uid
    - .planning/phases/05-judge-parity-decimation/05-05-SUMMARY.md
  modified:
    - mobile/tests/core_runner.gd
    - mobile/tools/test-core.sh

key-decisions:
  - "精确有理数比较边界距离（`|t_i*hz - k*1000|`），不用浮点 `k*1000/hz`：1000/60 的 450ms 会算成 450.00000000000006，把数学上的并列判成 452，违背「并列取更早」"
  - "实测 34 条边界带漂移，不是计划预期的 1 条；全部按 D-05 登记进白名单，不网格化、不加第四条选样规则、不改阈值"
  - "`det_arc_rearm_124` 的 250 Hz 实测是 `[too_short, too_short]`，不是 RESEARCH/计划写的 `[too_short, too_fast]`；白名单理由按夹具实测书写"
  - "Task 3 是纯验证任务，工作树零改动；其证据写进 SUMMARY，另以 docs 提交校正 20 条白名单的实测描述，避免制造空提交"
  - "生成器复用 `gen_gesture_golden` 的 `_drive_detector` / `_drive_engine` / `_assert_not_rounding_cliff`，不复制第二份参考驱动"

requirements-completed: [JUDGE-07]

coverage:
  - id: D1
    description: "抽稀规则唯一：每个 1000/hz 边界取最近样本、保留原始时间戳、每个按钮变化保留「变化后」样本；五条自断言缺一即红"
    requirement: JUDGE-07
    verification:
      - kind: integration
        ref: "python3 tools/decimate_trace.py --check#rates=3 cases=252 drifting=34"
        status: pass
      - kind: integration
        ref: "三次变异：网格化时间戳 / 删按钮沿保底 / 白名单造假 → 各自 stderr 变红并还原"
        status: pass
    human_judgment: false
  - id: D2
    description: "抽稀夹具 252 条 = 3 × 84，rates 恰为 {120, 90, 60}；`configs` 整份复制源夹具；`expect` 由参考实现重放抽稀 frames 得到，`facing` 在抽稀时间轴上重算"
    requirement: JUDGE-07
    verification:
      - kind: integration
        ref: "DECIMATION_FIXTURE rates=3 cases=252 (3 x 84)"
        status: pass
      - kind: integration
        ref: "tools/decimate_trace.py#_drive_engine 的 abs(engine.facing - declared_facing) < 1e-9 自断言"
        status: pass
    human_judgment: false
  - id: D3
    description: "GDScript 侧独立复核：每个抽稀时间戳都在同 source_id 的 250 Hz 源轨迹里；252 条抽稀期望逐条回放，判定码序列 mismatches=0"
    requirement: JUDGE-07
    verification:
      - kind: integration
        ref: "bash mobile/tools/test-core.sh#DECIMATION rates=3 cases=252 mismatches=0"
        status: pass
      - kind: unit
        ref: "mobile/tests/unit/test_decimation.gd#_check_source_subset（19,927 帧逐帧子集断言）"
        status: pass
    human_judgment: false
  - id: D4
    description: "白名单双向：34 条 `vs_250.codes_equal == false` 记录与 34 条 allowlist 条目集合完全相等，全部 reason 非空且写明实测码差"
    requirement: JUDGE-07
    verification:
      - kind: integration
        ref: "tools/decimate_trace.py#_assert_allowlist_bidirectional"
        status: pass
      - kind: integration
        ref: "变异 3：给 det_roulette_ok@60 加假条目 → 白名单条目已不漂移"
        status: pass
    human_judgment: false
  - id: D5
    description: "零回归：desktop 302/302、GESTURE_GOLDEN 55、GESTURE_RUNTIME 29、MEASURED 12、断言 44,792、gate-a.sh 与 lint 全绿；shared/skills_config.json 与所有生产阈值零改动"
    requirement: JUDGE-07
    verification:
      - kind: integration
        ref: "bash tools/check_desktop.sh#302 项检查全部通过"
        status: pass
      - kind: integration
        ref: "bash mobile/tools/test-core.sh#TESTS_SUITES=22 TESTS_ASSERTIONS=44792 TESTS_DONE failures=0"
        status: pass
      - kind: integration
        ref: "shasum -a 256 shared/skills_config.json#039b2d72…1f10（与计划 01 冻结值一致）"
        status: pass
    human_judgment: false

duration: 37min
completed: 2026-11-06
status: complete
---

# Phase 5 Plan 05: `DECIMATION` 抽稀矩阵 Summary

**用一条可复现的生成器把 250 Hz 语料抽稀到 120 / 90 / 60 Hz，逐字保留原始时间戳并强制按钮沿保底；252 条抽稀记录在 Python 与 GDScript 两侧各回放一次，判定码 0 差异。实测 34 条边界带漂移（不是计划预期的 1 条）逐条登记进双向白名单，`release_hold_ms` / `global_cooldown_ms` 一个字未改。**

## Performance

- **Duration:** 37 min
- **Started:** 2026-11-05T21:08:10Z
- **Completed:** 2026-11-05T21:45:26Z
- **Tasks:** 3
- **Files:** 8（含 1 个生成夹具、1 个 `.gd.uid` 边车；另加本 SUMMARY）
- **Tokens（actuals）:** 677,678 = chars/4 over `git diff 3f8845a..5fd872c`（2.71 MB，含 2.4 MB 生成夹具）；手写源码/测试/策略部分为 **13,429**。生成夹具的字节成本是估算时最容易漏掉的一项。

## 基线（开工前实测）

| 命令 | 结果 |
|------|------|
| `bash mobile/tools/test-core.sh` | `TESTS_SUITES=21`、`TESTS_ASSERTIONS=2664`、`TESTS_DONE failures=0` |
| `GESTURE_GOLDEN` / `GESTURE_RUNTIME` | `cases=55` / `cases=29`，`mismatches=0` |
| `bash tools/check_desktop.sh` | 302/302 |
| `shared/skills_config.json` | SHA-256 `039b2d72…1f10`（与计划 01 冻结值一致） |

## Accomplishments

- **`tools/decimate_trace.py`（561 行）**：CLI `[--check] [--root PATH]`；复用 `gen_gesture_golden` 的 `_drive_detector` / `_drive_engine` / `_facing_column` / `_assert_not_rounding_cliff`，**没有**第二份参考驱动。
- **抽稀规则（D-04）**：每个 `1000/hz` 边界取最近样本；并列取更早；每个按钮变化追加「变化后」样本；输出时间戳是 `t_i`，不是 `boundary`。边界距离用精确有理数 `|t_i*hz - k*1000|` 比较，避免浮点把 450ms 并列判成 452。
- **252 条夹具（3 × 84）**：`detector 55 + runtime 29`，每条记录带 `id / source_id / kind / rate_hz / rule / skill / config / ls / frames / expect / vs_250`；`configs` 整份复制源夹具的 12 份完整配置（含 `variant:*` / `synthetic:*`）。
- **`facing` 重算**：LS 变化点表原样沿用，`facing` 由参考引擎在抽稀后的帧序列上重算；`_drive_engine` 的 `1e-9` 自断言逐帧通过。
- **五条自断言**：速率、时间戳严格递增且原样来自源轨迹、按钮沿保底、参考重放、白名单双向；条数断言 `252 == 3 × 84` 且 `>= 240`。
- **`test_decimation.gd`（369 行）**：252 条逐帧回放；GDScript 侧独立断言 19,927 个时间戳都在源轨迹里；只比 `(skill, ok, code)`，不碰 `message` / `detail` / `measured` / `elapsed_ms`；配置只走 `payload["configs"]`；`DetectorFactory.build(skill)` 返回 `null` 直接判失败。
- **闸门现状**：22 套件 / **44,792** 断言 / `failures=0`、`DECIMATION rates=3 cases=252 mismatches=0`、`GESTURE_GOLDEN cases=55`、`GESTURE_RUNTIME cases=29`、`MEASURED cases=12`、`LINT_OK files=33`、desktop 302/302、gate-a.sh `PACK_OK skills=5 GLYPH_OK chars=1053`。

## 抽稀规则（唯一正确实现）

```text
period_ms = 1000 / hz
boundaries = 0, period_ms, 2*period_ms, ...（到最后一个时间戳为止）
selected = { argmin_i |t_i - boundary| }（并列取更早的样本）
for i where buttons[i] != buttons[i-1]:
    selected.add(i)                        # 「变化后」的样本
frames = [ (t_i, state_i) for i in sorted(selected) ]   # 时间戳是 t_i，不是 boundary
```

四个反例的机械落点：

| 规则 | 396 ms tap | 604 ms tap | 4 ms 按钮推杆 | 结果 |
|------|-----------|-----------|---------------|------|
| 250 Hz 基线 | `too_fast`@396 | `too_slow`@604 | 第二下被看到 | 基准 |
| 最近样本 + 原始时间戳 + 沿保底 | `too_fast`@396 ✅ | `too_slow`@604 ✅ | ✅ | 采用 |
| 最近样本 + 网格时间戳 | `ok`@400 ❌ | `ok`@600 ❌ | — | 变异 1 变红 |
| 最近样本 + 无沿保底 | `too_slow`@752 ❌ | 碰巧同码 | ❌ | 变异 2 变红 |

## 实测漂移：34 条边界带，不是 1 条

`vs_250.codes_equal == false` 的记录共 **34 / 252**（13.5%），全部集中在「±1 个采样周期」的边界带：

- **350ms 保持阈值 ±2ms**：`det_croqueta_ok` / `det_croqueta_hold_352` / `det_croqueta_tol_minus_1` 及它们的 runtime 副本；
- **弧线时长 ±4ms 邻点**：`det_roulette_max_minus_4` / `max_plus_4` / `min_minus_4` / `min_plus_4`；
- **4ms 摇杆推杆（无按钮沿）**：`det_heel_to_heel_ok@90`、`rt_heel_ok@90`、`rt_failure_owner_config_order@*`；
- **重新武装 120ms**：`det_arc_rearm_124@120/90/60`；
- **报告下限 24.5°**：`det_roulette_short_at_report_min@60`。

| 用例@速率 | 250 Hz | 抽稀后 |
|---|---|---|
| `det_heel_to_heel_ok@90` | ok@348 | incomplete@356 |
| `det_croqueta_ok@120` | ok@352 | （无） |
| `det_croqueta_ok@90` | ok@352 | （无） |
| `det_croqueta_ok@60` | ok@352 | （无） |
| `det_roulette_max_minus_4@120` | ok@596 | wrong_end@600 |
| `det_roulette_max_minus_4@90` | ok@596 | wrong_end@600 |
| `det_roulette_max_minus_4@60` | ok@596 | wrong_end@600 |
| `det_roulette_max_plus_4@120` | too_slow@604 | （无） |
| `det_roulette_max_plus_4@90` | too_slow@604 | （无） |
| `det_roulette_max_plus_4@60` | too_slow@604 | （无） |
| `det_roulette_min_minus_4@90` | too_fast@248 | wrong_end@256 |
| `det_roulette_min_plus_4@120` | ok@252 | wrong_end@260 |
| `det_roulette_min_plus_4@90` | ok@252 | wrong_end@256 |
| `det_roulette_min_plus_4@60` | ok@252 | wrong_end@268 |
| `det_roulette_short_at_report_min@60` | too_short@200 | （无） |
| `det_arc_rearm_124@120` | too_short@204, too_short@208 | too_short@208 |
| `det_arc_rearm_124@90` | too_short@204, too_short@208 | too_short@212 |
| `det_arc_rearm_124@60` | too_short@204, too_short@208 | too_short@216 |
| `det_croqueta_hold_352@120` | ok@352 | hold_short@356, ok@356 |
| `det_croqueta_hold_352@90` | ok@352 | hold_short@356, ok@352 |
| `det_croqueta_hold_352@60` | ok@352 | hold_short@356, ok@356 |
| `det_croqueta_tol_minus_1@120` | ok@352 | hold_short@356 |
| `det_croqueta_tol_minus_1@90` | ok@352 | hold_short@356 |
| `det_croqueta_tol_minus_1@60` | ok@352 | hold_short@356 |
| `rt_heel_ok@90` | ok@348 | incomplete@344 |
| `rt_croqueta_ok@120` | ok@352 | （无） |
| `rt_croqueta_ok@90` | ok@352 | （无） |
| `rt_croqueta_ok@60` | ok@352 | （无） |
| `rt_modifier_lb_keeps_croqueta@120` | ok@352 | （无） |
| `rt_modifier_lb_keeps_croqueta@90` | ok@352 | （无） |
| `rt_modifier_lb_keeps_croqueta@60` | ok@352 | （无） |
| `rt_failure_owner_config_order@120` | wrong_start@4 | too_slow@608 |
| `rt_failure_owner_config_order@90` | wrong_start@4 | too_slow@612 |
| `rt_failure_owner_config_order@60` | wrong_start@4 | too_slow@616 |

> 结论：**非边界带 218 条完全一致**；34 条差异全部能用「采样点没落在 4ms 级决定性帧上」解释，没有一条是检测器/引擎实现分叉。按 RESEARCH §C.4 的 A/B 类处置顺序，这属于第 2 步「轨迹落在阈值 ±1 帧内 → 标成边界带并记录」，不是第 3 步「远离阈值仍漂移 → 才动阈值」。**本阶段零阈值改动。**

## 三次变异验证（D-10，红色行原文）

每次 `cp` 到仓库外临时目录 → 改一处 → 跑生成器（不是 `--check`）→ 记录 stderr + 退出码 → 还原 → `--check` 全绿 → `git diff --exit-code` 为空。

### 变异 1：把输出时间戳从原始 `t_i` 改成网格化的 `boundary`

```text
✗ det_roulette_ok@120: 时间戳 17ms 不在源轨迹里（抽稀只许抽样本，不许网格化时间戳）
```

退出码 `1`。还原后 `--check` 通过、`git diff` 干净。

### 变异 2：删掉按钮沿保底

```text
✗ det_croqueta_ok@120: 缺少按钮沿样本（4ms 无 -> LB）
```

退出码 `1`。还原后 `--check` 通过、`git diff` 干净。

### 变异 3：给一个实际不漂移的 id 加白名单条目

```text
✗ 白名单条目已不漂移：det_roulette_ok@60 现在与 250 Hz 完全一致，请从 shared/decimation_allowlist.json 删除该条
```

退出码 `1`。还原后 `--check` 通过、`git diff` 干净。

## Task Commits

每个任务原子提交（`branching_strategy: none` + `SEQUENTIAL=true`，与 05-01/02/03/04 的提交线一致）：

1. **Task 1: decimate_trace 生成器 + 双向白名单 + 252 条夹具** — `12fab0c` (feat)
2. **Task 2: test_decimation 套件 + DECIMATION 哨兵** — `442fba2` (test)
3. **Task 3: 白名单实测描述校正（变异验证证据）** — `5fd872c` (docs)

**Plan metadata:** 本次 SUMMARY 提交（docs: complete plan）

## Files Created/Modified

- `tools/decimate_trace.py`（新，561 行）— 抽稀 + 五条自断言 + 双向白名单 + `--check`
- `shared/decimation_allowlist.json`（新，34 条）— 每条带非空 `reason` 与实测码差
- `mobile/tests/fixtures/golden_decimated.json`（新，生成物，2.4 MB）— 252 条 / 19,927 帧
- `mobile/tests/unit/test_decimation.gd`（新，369 行）— L2 回放 + 独立子集证明
- `mobile/tests/unit/test_decimation.gd.uid`（新）— `--import` 生成的边车文件
- `mobile/tests/core_runner.gd` — 21 → 22 套件（按字母序插入 `decimation`）
- `mobile/tools/test-core.sh` — Godot 前加 `decimate_trace.py --check`；`MEASURED` 后加 `DECIMATION rates=3 cases>=240 mismatches=0` 哨兵

## Decisions Made

- **精确有理数边界**：`k*1000/hz` 的浮点写法会把 60Hz 的 450ms 算成 450.00000000000006，使数学上的并列（448 与 452）倒向 452，违背「并列取更早」。比较 `|t_i*hz - k*1000|` 既不把边界取整到毫秒，也让并列判定与精确值一致。
- **34 条漂移全部登记，不发明第四条选样规则**：给摇杆沿也加保底会改变 D-04 的唯一规则，并让本计划的「已知例外」变成「零例外」；按 RESEARCH §C.4 把边界带记录进白名单才是可审计的做法。
- **`det_arc_rearm_124` 的实测理由按夹具书写**：250 Hz 实际是 `[too_short, too_short]`（204/208ms），不是计划文字里的 `[too_short, too_fast]`；白名单理由不能抄一个已被夹具否定的结论。
- **Task 3 不制造空提交**：变异验证只读改临时副本，工作树零改动；证据进 SUMMARY。随后发现 20 条白名单原因把 `elapsed_ms` 当成了绝对帧时间，修正这些描述并重生成夹具，作为 Task 3 的 `docs` 提交。

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - 计划假设过期] 实测漂移 34 条，不是「唯一例外 det_arc_rearm_124」**

- **Found during:** Task 1 第一次运行 `python3 tools/decimate_trace.py`
- **Issue:** 计划按 `52 + 29 = 81`、`3 × 81 = 243` 的下限与 RESEARCH §C.1 的四个探针，预期只有 `det_arc_rearm_124` 一条边界带差异。实际语料在计划 02 已扩到 **55 + 29 = 84**，且包含大量 ±4ms 边界与 4ms 摇杆推杆；首次实测 24 条，改用精确并列比较后 34 条。
- **Fix:** 按生成器的双向校验，把 34 条全部登记进 `shared/decimation_allowlist.json`，每条写明阈值、量化机制与 250 Hz → 抽稀的实测码差。没有网格化时间戳、没有删按钮沿、没有增加第四条选样规则、没有改任何阈值。
- **Files modified:** `shared/decimation_allowlist.json`、`mobile/tests/fixtures/golden_decimated.json`
- **Verification:** `python3 tools/decimate_trace.py --check` 绿；`DECIMATION rates=3 cases=252 mismatches=0`；desktop 302/302
- **Committed in:** `12fab0c` / `5fd872c`

**2. [Rule 1 - 浮点并列] `k*1000/hz` 的浮点边界破坏了「并列取更早」**

- **Found during:** Task 1 对照 `det_croqueta_ok@60` 的样本点
- **Issue:** `1000/60 = 16.666…`，`27 * period = 450.00000000000006`；448 与 452 到该边界的距离本应相等，浮点让 452 略近，选中了 452（保持 352ms → ok）。这违反 D-04 的「并列取更早」，也让同一实现在不同速率下行为不可解释。
- **Fix:** 用整数分子比较 `|t_i * hz - k * 1000|`，边界值本身仍不取整到毫秒；并列时按 `times[i]` 取更早。
- **Files modified:** `tools/decimate_trace.py`
- **Verification:** 60Hz 的 450ms 边界稳定选 448；`--check` 与全套件绿；变异 1/2/3 仍变红
- **Committed in:** `12fab0c`

**3. [Rule 1 - 计划文字与夹具不符] `det_arc_rearm_124` 的 250 Hz 期望是两条 `too_short`**

- **Found during:** Task 1 写白名单理由
- **Issue:** 计划/RESEARCH 写 250 Hz 为 `[too_short, too_fast]`；夹具实测是 `[too_short@204, too_short@208]`。照抄计划文字会让白名单理由与夹具自相矛盾。
- **Fix:** 理由按夹具实测书写；`too_fast` 的说法删除。
- **Files modified:** `shared/decimation_allowlist.json`
- **Verification:** 夹具 `expect.outcomes` 与白名单理由一致；`test_decimation` 回放 0 差异
- **Committed in:** `12fab0c` / `5fd872c`

**4. [Rule 1 - 白名单理由精度] 20 条原因把 `elapsed_ms` 当成绝对帧时间**

- **Found during:** Task 3 复核漂移表
- **Issue:** `wrong_end@260` 是 `elapsed_ms`，不是「260ms 的那一帧」；`max_minus_4` 的「600ms 样本只看到 278°」也把释放时刻与采样时刻混在一起。照这种文字去 Phase 6 复查会找不到帧。
- **Fix:** 改为「决定性帧不被采样 / 最后一个活跃样本 279.3° / 回中时 elapsed=…」的表述；重生成夹具（`drift.reason` 内嵌白名单文本）。
- **Files modified:** `shared/decimation_allowlist.json`、`mobile/tests/fixtures/golden_decimated.json`
- **Verification:** `--check` 绿；`test-core.sh` 22/44,792/0
- **Committed in:** `5fd872c`

---

**Total deviations:** 4 auto-fixed（4 Rule 1）
**Impact on plan:** 第 1 条是计划最实质的偏差：**34 条边界带漂移不是 1 条**。所有差异都能用「决定性帧落在两个采样点之间」解释，没有实现分叉；按 RESEARCH §C.4 与用户约束「不改阈值」，登记而不是放宽。`desktop/`、`shared/skills_config.json` 与全部生产阈值零改动。

## 变异验证的边界说明

- 变异 1 的网格化实现会先对边界去重（否则时间戳重复会先触发「严格递增」）；去重后仍能命中「17ms 不在源轨迹里」，证明断言 2 的成员判定本身有牙齿，不依赖重复时间戳。
- 变异 2 的第一条按钮沿是 `det_croqueta_ok` 的 `4ms 无 -> LB`；90/60Hz 的 `det_roulette_ok` 没有按钮，所以优先命中这条。
- 变异 3 的白名单条目带非空 `reason`，仍被「条目已不漂移」抓住 —— 证明校验的是**漂移事实**，不是「有没有写理由」。

## Issues Encountered

- **首次 `decimate_trace.py` 报 24 条未登记漂移**：不是工具坏了，是计划对语料的漂移面估计过窄。逐条核对后确认全部落在阈值 ±1 帧内；登记而非改阈值。
- **`det_croqueta_ok@60` 在浮点并列下曾「通过」**：这是最危险的一种假绿 —— 同一份实现因为 `450.00000000000006` 选了 452。改成精确比较后它变红并进入白名单，说明「并列取更早」不是一句口号。
- **`test_decimation.gd` 第一版只在失败时计数**：19,927 帧的子集证明没有正向断言，零循环也会绿。补成逐帧 `r.check` 后断言从 4,686 涨到 44,792，正向证据与失败证据同时存在。
- **Godot `--import` 本轮未撞上 SIGSEGV**：多次完整套件（Task 2 两次 + 最终两次）全部一次导入成功。
- **任务提交仍在 `main` 上**：`branching_strategy: none` + 顺序执行器（`SEQUENTIAL=true`），与 05-01/02/03/04 的提交线一致；通用提交守卫的「保护分支」检查在此配置下不适用（沿用 05-03/04 的记录）。

## Known Stubs

无。34 条白名单条目不是 stub：它们是**已实测、已具名、双向校验**的边界带差异，`reason` 非空且附 250 Hz → 抽稀的码差；任何新增漂移仍会让生成器红。

## Threat Flags

无新增信任面。T-05-17 的双向白名单已落地（有漂移必须有条目、有条目必须仍漂移、`reason` 非空）；T-05-18 由 `shared/skills_config.json` SHA-256 未变（`039b2d72…1f10`）与 `git status --porcelain -- shared/skills_config.json` 为空证明；T-05-18b 由 `configs` 整份复制 + 身份比较兜住。抽稀夹具只含角度、毫秒、按钮名与配置对象，不含设备名/GUID/账号。

## User Setup Required

None - 无外部服务、环境变量或真机步骤。

## Next Phase Readiness

- **Phase 6 有一份诚实已知边界带清单**：60/90/120Hz 下 34 条（全部在 ±1 个采样周期内）。真机若出现「第二发没反应」，优先对照 `det_arc_rearm_124` 与 `rt_failure_owner_config_order` 两条，再带实测数据回来评估 `release_hold_ms`；本阶段未改该阈值。
- **`DECIMATION` 哨兵可直接接进 Phase 6 的回归**：`rates=3 cases=252 mismatches=0`，下限 240；夹具是生成物，`--check` 在 Godot 之前判红。
- **`tools/decimate_trace.py` 的复用点已固定**：任何新的 250 Hz 语料只要进 `gesture_golden.json`，抽稀夹具与 3× 条数断言会自动扩展；不要复制第二份参考驱动。
- **闸门现状**：22 套件 / 44,792 断言 / `failures=0`、`DECIMATION 252/0`、`GESTURE 55/29`、`MEASURED 12`、`LINT_OK 33`、`PARITY_OK 28 divergences=4`、desktop 302/302、gate-a.sh 全绿。
- **无阻塞项**：`desktop/padskills/*.py` 与 `shared/skills_config.json` 零改动；Phase 4/5 的既有夹具全部原样通过。

## Self-Check: PASSED

- 计划内新建/修改的 8 个文件全部存在于工作树；`test_decimation.gd.uid` 已提交。
- 三个任务提交均可在 `git log` 中定位：`12fab0c` / `442fba2` / `5fd872c`。
- 测得提交数：`git rev-list --count 3f8845a..5fd872c` = 3（Task 1~3）。
- `git status --porcelain -- desktop shared/skills_config.json` 为空；`git diff --exit-code -- tools/decimate_trace.py shared/decimation_allowlist.json` 退出 0。
- 最终闸门：`bash mobile/tools/test-core.sh` 全绿（22 套件 / 44,792 断言 / `DECIMATION rates=3 cases=252 mismatches=0`）；`bash tools/check_desktop.sh` 302/302；`bash mobile/tools/gate-a.sh` 通过；`python3 tools/decimate_trace.py --check` 通过。
