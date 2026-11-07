---
phase: 05-judge-parity-decimation
plan: 02
subsystem: core-detectors
tags:
  [
    gdscript,
    godot,
    golden-fixture,
    boundary-cases,
    variant-config,
    mutation-testing,
    judge-parity,
  ]

requires:
  - phase: 05-judge-parity-decimation
    plan: 01
    provides: 生成器骨架 / `configs` 完整对象注册表 / 10 条已知用例 / `GESTURE_GOLDEN` 哨兵 / `_assert_not_rounding_cliff`
  - phase: 04-device-input-green-slice
    plan: 01
    provides: `Frame`（now 秒 + buttons 字典 + rs/ls/facing）、`Hit` / `Failure`、`Detector` 基类、`TapDetector`
  - phase: 03-core-foundation
    plan: 04
    provides: `ConfigValidator.validate` → `ConfigResult`，回放套件用它重建变体配置

provides:
  - "tools/gen_gesture_golden.py：`BOUNDARY_CASES`(18) / `VARIANT_CASES`(7) / `EXTRA_CASES`(20) 三张用例表"
  - "mobile/tests/fixtures/gesture_golden.json：55 条 detector 用例 + 8 份完整配置（shipped + 7 个变体）"
  - "反向对照：`det_roulette_relative_ls90_zero` / `det_roulette_absolute_ls90_ok` 共用同一 frames 与同一 LS，只差 relative_to_ls"
  - "双层下限：套件 `_check_scale >= 52` 与 `test-core.sh` grep `cases=(5[2-9]|…)` 是同一个数字（实际 55）"
  - "15 条 `REQUIRED_DETECTOR_IDS` 点名清单"
  - "四次变异验证的红色行原文（D-10）"

affects:
  [05-03-gesture-engine, 05-04-measured, 05-05-decimation, phase-6-training-loop, phase-7-feedback]

actuals:
  tokens: 235988
  tasks: 3
  commits: 3

plan_head_before: b90c2bc9d86cfae9eb5a3a34e7f560053e776240
plan_head_after: ec7f35e

tech-stack:
  added: []
  patterns:
    - "边界用例把刀口放在最后一帧：参考实现「到区间就成功」，中途满足会提前命中，测不到边界"
    - "时长边界从检测器 `t0`（推过 enter 的那一帧）起算，不是夹具第一帧；596 指 sweep 段时长"
    - "变体只改深拷贝副本的一个维度：顶层 `relative_to_ls` 或 `params` 的单个键；完整对象进 `configs`"
    - "反向对照两条用例引用同一个 `segments` 常量与同一份 `ls`，只差一个布尔"
    - "落不下来的轨迹用同族替换（同族、同码、参考实现跑得出），绝不删条、绝不改阈值"
    - "每条「有牙齿」的实现都做一次变异：改源码 → 红行原文 → 临时目录 cp 还原 → 重新全绿"

key-files:
  created:
    - .planning/phases/05-judge-parity-decimation/05-02-SUMMARY.md
  modified:
    - tools/gen_gesture_golden.py
    - mobile/tests/fixtures/gesture_golden.json
    - mobile/tests/unit/test_gesture_detector.gd
    - mobile/tools/test-core.sh

key-decisions:
  - "边界用例的 sweep 起点必须按 `t0` 计算：`det_roulette_max_minus_4` 的 596 是 sweep 段时长，末帧在 696ms（t0=100）"
  - "逆时针轨迹必须写成负的 `angle_to`：`_timeline()` 是线性插值，写 325 会变成顺时针 271°"
  - "变体用例 6 条 + 1 条 shipped 反向对照 = 7；`variant()` 因此要支持顶层 `relative_to_ls`，不能只改 params"
  - "`det_croqueta_hold_352` 追加「成功后 LB 松一帧再按回、摇杆仍推着」：croqueta 单步序列的 neutral 只有在步进后才变 false，否则 D-10 的第 4 次变异不可达"
  - "变异 3 的计划文字指向 `reset()` 的 `armed = true`，但 arc 套件从不调用 reset（无 required_button）；实际变异打在回中分支的 rearm 赋值上，并把「按字面变异仍全绿」一并记录"
  - "夹具 55 条、8 份配置；`shared/skills_config.json` 的 SHA-256 保持 039b2d72…1f10 不变"

requirements-completed: [JUDGE-01, JUDGE-03, JUDGE-04]

coverage:
  - id: D1
    description: "六类边界各 ≥2 条、全部由 Python 参考跑出：时长 ±4ms、角度 ±1°、起手 54/56/74/76、重新武装 116/124、保持 348/352、容差 9/11"
    requirement: JUDGE-03
    verification:
      - kind: integration
        ref: "bash mobile/tools/test-core.sh#GESTURE_GOLDEN cases=55 mismatches=0"
        status: pass
      - kind: integration
        ref: "python3 tools/gen_gesture_golden.py --check"
        status: pass
    human_judgment: false
  - id: D2
    description: "出厂配置不可达的 4 个分支由变体覆盖：wrong_direction、start_angle:null、absolute、负 grace"
    requirement: JUDGE-04
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_gesture_detector.gd#det_roulette_direction_ccw_wrong..det_croqueta_absolute_no_match"
        status: pass
    human_judgment: false
  - id: D3
    description: "反向对照只改 relative_to_ls：同一 frames + 同一 LS 下相对模式零判定、绝对模式 ok"
    requirement: JUDGE-03
    verification:
      - kind: integration
        ref: "python3 -c \"…assert a[0]['frames']==a[1]['frames'] and a[0]['ls']==a[1]['ls']\""
        status: pass
    human_judgment: false
  - id: D4
    description: "语料下限双层同数：套件 >=52 与 shell grep >=52，实际 55"
    requirement: JUDGE-03
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_gesture_detector.gd#_check_scale"
        status: pass
      - kind: integration
        ref: "mobile/tools/test-core.sh#GESTURE_GOLDEN grep"
        status: pass
    human_judgment: false
  - id: D5
    description: "四次变异验证：分支对调、去掉静默门、去掉重新武装、reset 动 neutral，均按预期变红并还原全绿"
    requirement: JUDGE-03
    verification:
      - kind: integration
        ref: "bash mobile/tools/test-core.sh（四次变异 + 四次还原）"
        status: pass
    human_judgment: false
  - id: D6
    description: "真源零改动：shared/ 与 desktop/ 的 git status 为空，桌面 302 项保持全绿"
    requirement: JUDGE-01
    verification:
      - kind: integration
        ref: "bash tools/check_desktop.sh && git status --porcelain -- shared desktop"
        status: pass
    human_judgment: false

duration: 13min
completed: 2026-11-06
status: complete
---

# Phase 5 Plan 02: 检测器语料扩到 55 条 — 六类边界、变体配置、反向对照与变异验证 Summary

**把检测器黄金语料从 10 条「已知结论」扩到 55 条，覆盖六类真正会分叉的边界；出厂配置不可达的四个分支由带完整配置的变体覆盖；并用四次变异证明每一条关键断言都会在实现被拆掉时变红。**

## Performance

- **Duration:** 13 min
- **Started:** 2026-11-05T18:24:03Z（以上一计划最后一次提交为锚；本计划自己的起始计时未单独落盘）
- **Completed:** 2026-11-05T18:36:33Z
- **Tasks:** 3
- **Files modified:** 4（生成器 / 夹具 / 回放套件 / 闸门脚本）；`arc_detector.gd` 与 `sequence_detector.gd` **零改动** —— 边界轨迹没有暴露新的移植偏差

## 基线（开工前实测，沿用计划 01 冻结值）

| 命令 | 结果 |
|------|------|
| `bash tools/check_desktop.sh` | `✓ 302 项检查全部通过` |
| `bash mobile/tools/test-core.sh` | `TESTS_SUITES=19`、`TESTS_ASSERTIONS=1669`、`TESTS_DONE failures=0` |
| `python3 tools/gen_tap_golden.py --check` | detector 12 / runtime 6，一致 |
| `python3 tools/lint_core_purity.py mobile/src/core` | `LINT_OK files=31` |
| `shasum -a 256 shared/skills_config.json` | `039b2d72…1f10`（收尾复核未变） |

## Accomplishments

- **六类边界 18 条全部落地，且每条都真的测到边界**：时长 596/604/248/252、终点容差 79/81、扫掠 23（静默）/26（too_short）、起手 54/56/74/76、重新武装 116/124、保持 348/352、容差 9/11。
- **变体配置 7 条**：`wrong_direction`（cw/ccw）、`start_angle:null`、`relative_to_ls:false`（arc + sequence）、`timeout_grace_ms:-50`、`max_angle:120`（overshoot）。每份变体都是**完整配置对象**进 `configs` 注册表。
- **反向对照成立**：`det_roulette_relative_ls90_zero` 与 `det_roulette_absolute_ls90_ok` 的 `frames` 与 `ls` 逐字节相同，只差 `relative_to_ls`；相对模式零判定、绝对模式 `ok`。
- **补充 20 条**：`stalled` / `incomplete` / `too_slow`、tap 396/596/604/404/600/752、`release_hold`、踩单车终点 78/76/89 三支、马赛回旋 `wrong_start` / claim 外 / `too_short_near_min`、`overshoot`、`direction:any` 逆时针。
- **双层下限同数**：套件 `_check_scale >= 52`，`test-core.sh` grep `cases=(5[2-9]|…)`，实际 **55**。
- **四次变异验证**：每次都能让对应断言变红，还原后重新打印 `GESTURE_GOLDEN cases=55 mismatches=0`。
- **零回归**：桌面 302/302、移动端 19 套件 / **2044** 断言（1669 → 2044）、`gate-a.sh`、tap 夹具、lint 全绿；`shared/` 与 `desktop/` 零改动。

## 语料矩阵（55 条 = 10 已知 + 18 边界 + 7 变体/对照 + 20 补充）

| 组 | 条数 | id |
|---|---:|---|
| 已知成功 / 失败码（计划 01） | 10 | `det_roulette_ok` … `det_croqueta_hold_short` |
| 时长 ±4ms | 4 | `det_roulette_max_minus_4`(596 ok) / `max_plus_4`(604 too_slow) / `min_minus_4`(248 too_fast) / `min_plus_4`(252 ok) |
| 角度 / 容差 | 4 | `end_tol_minus_1`(79 ok) / `end_tol_plus_1`(81 wrong_end) / `short_below_report_min`(23 零) / `short_at_report_min`(26 too_short) |
| 起手 | 4 | `start_in_tol`(54 ok) / `start_out_tol`(56 wrong_start) / `start_at_claim_edge`(74 wrong_start) / `start_outside_claim`(76 零) |
| 重新武装 | 2 | `det_arc_rearm_116`(1 条) / `det_arc_rearm_124`(2 条) |
| 保持 | 2 | `hold_348`(hold_short 348ms) / `hold_352`(ok 352ms) |
| 油炸丸子容差 | 2 | `tol_minus_1`(9° ok) / `tol_plus_1`(11° 零) |
| 变体 + 反向对照 | 7 | `direction_cw_ok` / `direction_ccw_wrong` / `start_null_any_start` / `relative_ls90_zero` / `absolute_ls90_ok` / `green_negative_grace` / `croqueta_absolute_no_match` |
| 补充 20 条 | 20 | `stalled`×2、`incomplete`、`too_slow`、tap×8、`release_hold`、stepover 终点×3、roulette×5、`overshoot`、`direction_any_ccw` |

`configs` 注册表 8 份：`shipped` + `variant:roulette_cw` / `_ccw` / `_start_null` / `_absolute` / `_max_angle_120`、`variant:green_negative_grace`、`variant:croqueta_absolute`。

### 由参考实现跑出的关键期望（逐条核对）

| 用例 | 期望 |
|------|------|
| `det_roulette_max_minus_4` | `ok` @ 596ms（末帧终点 280°，恰在 0±80 的下边界） |
| `det_roulette_max_plus_4` | `too_slow` @ 604ms（第 600ms 帧终点 279.3° 仍在窗口外） |
| `det_roulette_min_minus_4` / `min_plus_4` | `too_fast` @ 248ms / `ok` @ 252ms |
| `det_arc_rearm_124` | **2 条** `too_short`（204ms + 208ms）——与 RESEARCH §C.2 的记录一致 |
| `det_croqueta_hold_348` | `hold_short` @ 352ms，文案「只保持了 348ms」 |
| `det_green_finesse_grace_too_slow` | `too_slow` @ 752ms（600+150 是严格大于，4ms 网格首点 752） |
| `det_stepover_end_target_270` | `ok` @ 500ms（325° = 270+55 的容差边界） |
| `det_roulette_overshoot` | `overshoot` @ 404ms（max_angle:120 变体） |

## Task Commits

每个任务原子提交：

1. **Task 1: 六类边界语料 18 条，语料下限提到 28** - `3286a86` (feat)
2. **Task 2: 6 条变体配置与 relative/absolute 反向对照** - `f5a16d3` (feat)
3. **Task 3: 语料补到 55，双层下限收紧到 52 并完成四次变异验证** - `ec7f35e` (feat)

**Plan metadata:** 本次 SUMMARY 提交（docs: complete plan）

## Files Created/Modified

- `tools/gen_gesture_golden.py` — 新增三张用例表与 7 个变体注册；`variant()` 支持顶层 `relative_to_ls`；`meta.variants` 记人类可读 diff
- `mobile/tests/fixtures/gesture_golden.json` — 生成物：55 条用例 + 8 份完整配置（1.07 MB）
- `mobile/tests/unit/test_gesture_detector.gd` — `_check_scale` 从 10 提到 52；`REQUIRED_DETECTOR_IDS` 固化为 15 条
- `mobile/tools/test-core.sh` — `GESTURE_GOLDEN` grep 下限同步收紧到 52
- `mobile/src/core/detectors/arc_detector.gd` / `sequence_detector.gd` — **零改动**（仅变异验证期间临时改过，全部按临时目录备份原样还原，`git diff` 为空）

## Decisions Made

- **边界刀口放在最后一帧**：参考实现是「swept 与终点同时满足就成功」。若轨迹中途就进入终点窗口，用例会在 300ms 前命中，`max_duration` / `end_tolerance` 的边界根本没被测到。所有时长与容差边界都让最后一帧才满足条件。
- **时长从 `t0` 起算**：`elapsed_ms` 是「推过 enter 之后」的时长。夹具 `end_ms` 比 sweep 段时长多 100ms，计划里的 596 / 604 / 248 / 252 全部指 sweep 段本身。
- **逆时针必须写负的 `angle_to`**：`_timeline()` 对 `sweep` 做线性插值再 `norm_deg`。写 `325` 会得到 54→325 的顺时针 271°，写 `-35` 才是逆时针 89°。这条错误在第一次生成时直接表现为 `too_fast@132ms`。
- **变体只改一个维度**：`variant()` 的契约收紧成「顶层 `relative_to_ls` 或 `params` 的单个键」。`det_roulette_relative_ls90_zero` / `absolute_ls90_ok` 引用同一个 `_ROULETTE_CW_SEGMENTS` 常量，生成器层面的 `frames` / `ls` 逐字节相同。
- **夹具条数取 55 而不是刚好 52**：20 条补充用例全部可达，没有触发「同族替换」；下限仍按 52 钉死，多出的 3 条是保险。
- **`det_croqueta_hold_352` 承担 neutral 纪律的变异证据**：croqueta 是单步 hold 序列，`neutral` 只有在步进成功后才变 false。成功后再让 LB 抖一帧、摇杆保持推着，才能证明 `reset()` 不能把 `neutral` 置回 true。

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] 逆时针轨迹被线性插值成顺时针，`det_stepover_end_target_270` 先报 `too_fast`**

- **Found during:** Task 3（首次生成 20 条补充用例）
- **Issue:** 计划写「起手相对 54°、逆时针 89° 收在相对 325°」，我最初把 `angle_to` 写成 `325`。`_timeline()` 是 54→325 的线性插值（顺时针 271°），参考实现在 132ms 就以 `too_fast` 命中，目标结论 `ok` 根本到不了。
- **Fix:** 改成 `-35`（54 + (-89) = -35，`norm_deg` 后 325）。末帧才是 325°，扫掠 89° ∈ [70,135]，`ok@500ms`。
- **Files modified:** `tools/gen_gesture_golden.py`
- **Verification:** `gen_gesture_golden.py` 重新生成后该条为 `[('ok', 500.0)]`。
- **Committed in:** `ec7f35e`（Task 3 提交）

**2. [Rule 1 - Bug] `det_roulette_direction_any_ccw` 的 340 同样是顺时针 160°**

- **Found during:** Task 3
- **Issue:** 同上：180→340 的线性插值只转了 160° 顺时针，与「200° 逆时针」的用例意图不符（虽然 `direction: any` 下仍然 `ok`，但测的不是想测的东西）。
- **Fix:** `angle_to` 改成 `-20`（180 - 200 = -20 = 340），参考实现给出 `ok@252ms`。
- **Files modified:** `tools/gen_gesture_golden.py`
- **Verification:** 生成后为 `[('ok', 252.0)]`。
- **Committed in:** `ec7f35e`（Task 3 提交）

**3. [Rule 3 - Blocking] `det_green_finesse_release_hold` 的按键变化点 590/594 不在 4ms 网格**

- **Found during:** Task 3（生成器拒绝 `按键变化点 590 不在 4ms 网格上`）
- **Issue:** 第二对 X 的按下 / 松开时刻写成 590/594，两者都不是 4 的整数倍。
- **Fix:** 改成 588/592；语义不变（距上一次松开 24ms，仍 < `release_hold_ms` 120）。
- **Files modified:** `tools/gen_gesture_golden.py`
- **Verification:** 生成通过，该条仍只有 1 条 `too_fast@396ms`。
- **Committed in:** `ec7f35e`（Task 3 提交）

**4. [Rule 3 - Blocking] `variant()` 需要支持顶层 `relative_to_ls`，计划只写了 `params`**

- **Found during:** Task 2
- **Issue:** 计划要求变体覆盖「absolute」分支，而 `relative_to_ls` 是技能顶层字段，不在 `params` 里；原 `variant()` 只能改 `params`。
- **Fix:** 扩展签名为 `variant(base, skill_name, *, relative_to_ls=None, **params)`，仍保持「一次只改一个维度」；`det_roulette_absolute_ls90_ok` / `det_croqueta_absolute_no_match` 用它。
- **Files modified:** `tools/gen_gesture_golden.py`
- **Verification:** 两份变体配置都通过 `parse_config` 自检并进入 `configs` 注册表。
- **Committed in:** `f5a16d3`（Task 2 提交）

**5. [Rule 1 - Plan text vs 参考实现] 变异 3 的 `reset()` 指向不可达代码；实际变异打在回中分支的 rearm 赋值**

- **Found during:** Task 3（变异验证 3）
- **Issue:** 计划写「把 `reset()` 里的 `_armed = true` 改成 `false` → `det_arc_rearm_124` 必须变红」。但 arc 技能没有 `required_button`，回放套件从不调用 `reset()`（只走 `update` / `observe`）；按字面改完仍 `GESTURE_GOLDEN cases=55 mismatches=0`、`TESTS_DONE failures=0`。真正让第二段起手的是回中分支里的 `armed = true`。
- **Fix:** 先按字面变异并记录「仍全绿」（证据：`GESTURE_GOLDEN cases=55 mismatches=0`），再改回中分支的 `armed = true → false`，得到 `TESTS_FAIL gesture_detector: det_arc_rearm_124: 判定条数（实际 1，期望 2）`。两次都还原并重新全绿。
- **Files modified:** 无（仅临时变异，已还原）
- **Verification:** 还原后 `GESTURE_GOLDEN cases=55 mismatches=0` / `TESTS_DONE failures=0`；`git diff -- mobile/src/core/detectors/` 为空。
- **Committed in:** `ec7f35e`（Task 3 提交）

**6. [Rule 1 - 用例可达性] `det_croqueta_hold_352` 追加「LB 抖一帧」轨迹，否则第 4 次变异不可达**

- **Found during:** Task 3（准备变异 4）
- **Issue:** croqueta 是单步 hold 序列，`neutral` 只在 `index += 1`（成功/步进）时变 false。原 `hold_352` 在成功前从未步进，`reset()` 改不改 `neutral` 都观察不到差异；第 4 次变异会假绿。
- **Fix:** 成功（452ms）之后追加 `456ms 松 LB → 460ms 重按`，摇杆保持推到 896ms。正确实现下 `require_neutral` 拦住第二次起手（仍 1 条 `ok`）；把 `neutral = true` 加回 `reset()` 后多出 1 条，变异 4 变红。
- **Files modified:** `tools/gen_gesture_golden.py`、`mobile/tests/fixtures/gesture_golden.json`
- **Verification:** 未变异时 1 条 `ok@352`；变异后 `判定条数（实际 2，期望 1）`；还原后全绿。
- **Committed in:** `ec7f35e`（Task 3 提交）

**7. [Rule 1 - 取整刀口] `det_roulette_short_*` 从 50 步改成 49 步**

- **Found during:** Task 1（生成器 `_assert_not_rounding_cliff` 拒绝 168.5°）
- **Issue:** 23°/50 步的中点正好是 11.5°，`end_rel` 落在 `%.0f` 的刀口上；26°/50 步同理。
- **Fix:** sweep 时长从 200ms 改成 196ms（49 步）。`23k/49` 与 `26k/49` 的 `.5` 解要求偶数=奇数，数学上不可能。
- **Files modified:** `tools/gen_gesture_golden.py`
- **Verification:** 生成器通过；两条分别得到「零判定」与 `too_short@200ms`。
- **Committed in:** `3286a86`（Task 1 提交）

---

**Total deviations:** 7 auto-fixed（5 Rule 1、1 Rule 3、1 计划文字与实现冲突）
**Impact on plan:** 全部是「让轨迹落在参考实现真正可达的边界上」的修正与变异验证的可达性补强；无语料删除、无阈值改动、无范围扩张。`desktop/` 与 `shared/` 零改动。

## 变异验证（D-10，红色行原文）

每一步都先 `cp` 到临时目录，改源码 → `bash mobile/tools/test-core.sh` → 记录红色行 → `cp` 拷回 → 重新跑绿。没有使用 `git checkout --`，避免误还原其他人未提交的改动。

### 变异 1：`_release_failure()` 的 `too_short` / `wrong_end` 两个分支对调

`GESTURE_GOLDEN cases=55 mismatches=16`

```
TESTS_FAIL gesture_detector: det_roulette_wrong_end: outcomes[0].code（实际 too_short，期望 wrong_end）
TESTS_FAIL gesture_detector: det_roulette_short_at_report_min: outcomes[0].code（实际 wrong_end，期望 too_short）
```

还原后：`GESTURE_GOLDEN cases=55 mismatches=0`、`TESTS_DONE failures=0`。

### 变异 2：去掉 `swept >= report_min_angle` 静默门（改成无条件调用）

`GESTURE_GOLDEN cases=55 mismatches=1`

```
TESTS_FAIL gesture_detector: det_roulette_short_below_report_min: 判定条数（实际 1，期望 0）
```

还原后：`GESTURE_GOLDEN cases=55 mismatches=0`、`TESTS_DONE failures=0`。

### 变异 3：重新武装（计划字面 vs 实际机制）

**3a（计划字面：`reset()` 的 `armed = true → false`）**：仍全绿，证明该行在 arc 回放路径不可达。

```
GESTURE_GOLDEN cases=55 mismatches=0
TESTS_DONE failures=0
```

**3b（实际机制：回中分支的 rearm 赋值 `armed = true → false`）**：`GESTURE_GOLDEN cases=55 mismatches=1`

```
TESTS_FAIL gesture_detector: det_arc_rearm_124: 判定条数（实际 1，期望 2）
```

还原后：`GESTURE_GOLDEN cases=55 mismatches=0`、`TESTS_DONE failures=0`。

### 变异 4：`SequenceDetector.reset()` 把 `neutral = true` 加回去

`GESTURE_GOLDEN cases=55 mismatches=1`

```
TESTS_FAIL gesture_detector: det_croqueta_hold_352: 判定条数（实际 2，期望 1）
```

还原后：`GESTURE_GOLDEN cases=55 mismatches=0`、`TESTS_DONE failures=0`；`git diff -- mobile/src/core/detectors/` 为空。

## Issues Encountered

- **`sweep` 的线性插值不认 0/360 环绕**：写 `325` 不是「逆时针到 325」，而是「顺时针从 54 到 325」。两次踩中（`det_stepover_end_target_270`、`det_roulette_direction_any_ccw`），都改成负角度后修复；注释里写明了这条坑。
- **边界用例会提前命中**：参考实现的成功条件是「swept 在区间 且 终点在容差」，任何单调轨迹在进入终点窗口的第一帧就可能成功。所以所有时长 / 容差边界都必须让最后一帧才满足终点窗口，否则测到的是窗口入口而不是边界。
- Godot `--import` 本轮未撞上信号终止，一次成功；四次变异 + 两次还原共跑了 7 次完整套件，全部一次通过。

## Known Stubs

无。55 条用例的期望全部由 Python 参考实现跑出；`shared/skills_config.json` 的 SHA-256 保持 `039b2d72…1f10`，未为对齐而改任何阈值。

## Threat Flags

无新增信任面：本计划只读 `desktop/padskills/*.py` 与 `shared/skills_config.json`，写入全部在 `tools/`（只读参考实现）与 `mobile/tests/`（生成物 + 回放）。变异验证只临时改 `mobile/src/core/detectors/`，已按字节还原。

## User Setup Required

None - 无外部服务或环境变量。

## Next Phase Readiness

- **计划 03 可直接消费**：55 条 detector 用例 + 8 份完整配置已在夹具里，引擎层语料可以复用 `_drive_engine` 的 harness 与 `configs` 注册表。
- **计划 05 的抽稀白名单有依据**：`det_arc_rearm_124` 的「124ms 重起手在 60 Hz 少一条判定」是已实测的漂移点，白名单可以引用这条 id。
- **闸门现状**：`TESTS_SUITES=19`、`TESTS_ASSERTIONS=2044`、`TESTS_DONE failures=0`、`GESTURE_GOLDEN cases=55 mismatches=0`、`LINT_OK files=31`、desktop 302/302、`gate-a.sh` 通过。
- **无阻塞项**：`arc_detector.gd` / `sequence_detector.gd` 在本次语料下零改动；计划 03 的引擎移植不需要先修检测器。

## Self-Check: PASSED

- 4 个计划内文件全部存在于工作树；夹具 55 条、配置 8 份。
- 三个任务提交均可在 `git log` 中定位：`3286a86` / `f5a16d3` / `ec7f35e`。
- 测得提交数：`git rev-list --count b90c2bc..HEAD` = 3；`git status --porcelain -- shared desktop` 为空。
- 最终闸门：`python3 tools/gen_gesture_golden.py --check` 退出 0；`bash mobile/tools/test-core.sh` 全绿。
