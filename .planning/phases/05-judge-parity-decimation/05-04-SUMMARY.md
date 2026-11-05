---
phase: 05-judge-parity-decimation
plan: 04
subsystem: core-detectors
tags:
  [
    gdscript,
    godot,
    measured,
    judge-parity,
    structured-metrics,
    sequence-step-timing,
    mutation-testing,
  ]

requires:
  - phase: 05-judge-parity-decimation
    plan: 01
    provides: `GESTURE_GOLDEN` 生成器骨架 / 哨兵纪律 / 哨兵下限机械校验
  - phase: 05-judge-parity-decimation
    plan: 02
    provides: 55 条检测器语料 / 变体配置 / 变异验证口径
  - phase: 05-judge-parity-decimation
    plan: 03
    provides: 多技能 `GestureEngine` / 唯一 8 参数 `_record` / `Outcome` 队列
  - phase: 04-device-input-green-slice
    plan: 01
    provides: `Hit` / `Failure` / `TapRuntime` 与 Phase 4 的 2044 条断言

provides:
  - "`Hit.measured` / `Failure.measured` / `Outcome.measured` 的完整透传链（不复制、不裁剪、不重算）"
  - "`ArcDetector` 的 measured：起止角 / 扫掠 / 样本 / 方向 / 目标窗 + `fail{nearest,distance,tolerance}`"
  - "`SequenceDetector._step_t`：每步**完成**时刻（毫秒），纯增量、不进判定"
  - "`TapDetector` 的 measured：两下间隔 / 窗口 / 按键 / 修饰键"
  - "`mobile/tests/unit/test_measured.gd`：12 组已知轨迹断言"
  - "哨兵 `MEASURED cases=12 mismatches=0`"

affects: [05-05-decimation, 05-07-wiring, phase-6-training-loop, phase-7-feedback, phase-8-persistence]

actuals:
  tokens: 13534
  tasks: 3
  commits: 3

plan_head_before: 4d961efbbd9dd4e1ed6d57ab51c058f550440e57
plan_head_after: 06b5a21c78f70a5e682a64dbdb86bd636acbce97

tech-stack:
  added: []
  patterns:
    - "度量只在产生判定的那一刻构造：数值全部来自判定现场的局部量，禁止事后重算"
    - "文案与结构化字段同源：先算 nearest/distance 再格式化 message，测试只把 end_rel 与文案对齐"
    - "纯增量字段（`_step_t`）：只写赋值、只读 measured，绝不进任何判定条件"
    - "没有跨语言 oracle 的字段由已知轨迹独立证明：12 组断言 + shell 哨兵 + 三次变异验证"

key-files:
  created:
    - mobile/tests/unit/test_measured.gd
    - mobile/tests/unit/test_measured.gd.uid
    - .planning/phases/05-judge-parity-decimation/05-04-SUMMARY.md
  modified:
    - mobile/src/core/hit.gd
    - mobile/src/core/failure.gd
    - mobile/src/core/outcome.gd
    - mobile/src/core/gesture_engine.gd
    - mobile/src/core/tap_runtime.gd
    - mobile/src/core/detectors/arc_detector.gd
    - mobile/src/core/detectors/sequence_detector.gd
    - mobile/src/core/detectors/tap_detector.gd
    - mobile/tests/core_runner.gd
    - mobile/tools/test-core.sh

key-decisions:
  - "`measured` 随 `Hit` / `Failure` 一起产出，删除 Phase 4 遗留的 `ArcDetector.measured()` 事后快照入口 —— 一次判定只有一份度量，不提供第二个读取路径"
  - "`distance_deg` 用 `Geometry.angle_diff`（圆周距离，与 `_end_ok` 同一把尺）；测试选的 50°/90° 让 `angle_diff` 与 `abs(end_rel - nearest)` 同为 40，组 6 仍按同源等式断言"
  - "出厂马赛回旋的终点窗 0°±80° 让 200° 成功不可达（第一个同时满足 min 250ms + 区间 + 终点窗的帧在 100.8°）；组 1~5 改用同形状合成弧（终点 20°±0.5°），判定代码零分叉"
  - "`wrong_end` 必须有非零 `nearest_target` 才有牙齿：用合成弧（终点 90°±20°、顺时针 230° 全程不经过窗口），使 `abs(end_rel)=50 ≠ distance=40`"
  - "`_step_t` 存毫秒（`now * 1000.0`）：字段名对外承诺 `t_done_ms`，存秒会让每个消费者各漏乘一次 1000"
  - "`_turn_sign` 在 `swept >= 5°` 时无条件记录实际转向，`wrong_direction` 判定仍要求 `direction != 0` —— 与参考实现行为等价，但让 `direction: any` 的 shipped 动作也有真实 `direction_sign`"

requirements-completed: [JUDGE-05]

coverage:
  - id: D1
    description: "每次判定（成功与失败）都带结构化 `measured`，并经 `Hit` / `Failure` → `GestureEngine._record` → `Outcome` 原样透传"
    requirement: JUDGE-05
    verification:
      - kind: integration
        ref: "mobile/tests/unit/test_measured.gd#tap_success + tap_too_fast（经 TapRuntime 走完整链）"
        status: pass
      - kind: integration
        ref: "bash mobile/tools/test-core.sh#MEASURED cases=12 mismatches=0"
        status: pass
    human_judgment: false
  - id: D2
    description: "三类检测器的字段表与 RESEARCH §D.5 逐键一致：Arc 起止角/扫掠/样本/方向/目标窗 + fail；Sequence 每步角度统计/保持/完成时刻；Tap 间隔/窗口/按键/修饰键"
    requirement: JUDGE-05
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_measured.gd#组 1~12"
        status: pass
    human_judgment: false
  - id: D3
    description: "`SequenceDetector._step_t`：每步完成时刻严格递增，且不出现在任何判定条件里"
    requirement: JUDGE-05
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_measured.gd#sequence_two_steps（t_done 4ms → 256ms）"
        status: pass
      - kind: integration
        ref: "bash mobile/tools/test-core.sh（GESTURE_GOLDEN/RUNTIME 仍 0 差异）"
        status: pass
    human_judgment: false
  - id: D4
    description: "`MEASURED` 哨兵与套件下限同为 12；三次变异（swept*0.999 / distance 漏 nearest / 删 _step_t 写入）各自让具名断言变红"
    requirement: JUDGE-05
    verification:
      - kind: integration
        ref: "bash mobile/tools/test-core.sh（三次变异 + 三次还原）"
        status: pass
      - kind: integration
        ref: "git diff --exit-code -- mobile/src/core/detectors/arc_detector.gd mobile/src/core/detectors/sequence_detector.gd"
        status: pass
    human_judgment: false
  - id: D5
    description: "零回归：desktop 302/302、GESTURE_GOLDEN 55、GESTURE_RUNTIME 29、断言 2587 → 2664、gate-a.sh 与 lint 全绿；`desktop/` 与 `shared/` 零改动"
    requirement: JUDGE-05
    verification:
      - kind: integration
        ref: "bash tools/check_desktop.sh#302 项检查全部通过"
        status: pass
      - kind: integration
        ref: "bash mobile/tools/gate-a.sh#PACK_OK skills=5 GLYPH_OK chars=1053"
        status: pass
      - kind: integration
        ref: "bash mobile/tools/test-core.sh#TESTS_SUITES=21 TESTS_ASSERTIONS=2664 TESTS_DONE failures=0"
        status: pass
    human_judgment: false

duration: 39min
completed: 2026-11-06
status: complete
---

# Phase 5 Plan 04: `measured{}` 结构化度量 Summary

**每次判定都携带一份与文案同源的结构化度量：弧线的起止角/扫掠/样本/方向/目标窗与失败落点、序列每一步的保持时长与完成时刻、tap 的两下间隔与窗口 —— 经 `Hit`/`Failure` → `_record` → `Outcome` 原样透传，并由 12 组已知轨迹断言与三次「改坏就红」实证钉死。**

## Performance

- **Duration:** 39 min
- **Started:** 2026-11-05T19:42:26Z
- **Completed:** 2026-11-05T20:21:47Z
- **Tasks:** 3
- **Files modified:** 12（含 1 个新建 `.gd.uid` 边车文件）

## 基线（开工前实测）

| 命令 | 结果 |
|------|------|
| `bash mobile/tools/test-core.sh` | `TESTS_SUITES=20`、`TESTS_ASSERTIONS=2587`、`TESTS_DONE failures=0` |
| `GESTURE_GOLDEN` / `GESTURE_RUNTIME` | `cases=55` / `cases=29`，`mismatches=0` |
| `bash tools/check_desktop.sh` | 302/302 |
| `shared/skills_config.json` | 零改动（`git status` 空） |

## Accomplishments

- **三处 `measured` 构造**：`ArcDetector`（成功 + 8 条失败路径）、`SequenceDetector`（成功 + 4 条失败路径）、`TapDetector`（成功 + 4 条失败路径）。每个 `Hit.new` / `Failure.new` 都带 measured，旧位置参数调用（`Hit.new(elapsed, detail, summary)`）零改动继续编译。
- **`measured.fail` 与文案同源**：`wrong_end` 先算 `nearest = min(end_targets, angle_diff)` 与 `distance = angle_diff(end_rel, nearest)`，再格式化文案；组 6 断言 `distance == abs(end_rel - nearest)` 且 `message` 的第一个整数就是 `end_rel`。文案一个字未改。
- **`SequenceDetector._step_t`**：在 `index += 1` 的同一处写入完成时刻（毫秒），`_reset_metrics()` 一并清空。它只出现在赋值与 `measured` 构造里，不进任何 `if` / `match`。
- **`Outcome.measured` 透传**：`_record` 仍是全仓唯一 8 参数定义，签名未改；命中传 `hit.measured`、失败传 `failure.measured`，同一个对象，不 `duplicate()`。
- **12 组独立证明**：`test_measured.gd` 不读任何黄金夹具，用已知轨迹断言扫掠角（±0.05°）、起点、活动帧数 126、目标窗口、实际转向、`wrong_end` 同源、`too_short`/`too_fast` 自洽、两步完成时刻严格递增、保持 350ms、`hold_short` 200ms、tap 448/396 经 `TapRuntime` 走完整透传链。
- **闸门现状**：21 套件 / **2664** 断言 / `failures=0`、`MEASURED cases=12 mismatches=0`、`LINT_OK files=33`、desktop 302/302、gate-a.sh 全绿、两个黄金夹具 `--check` 一致。

## `measured{}` 字段表（与 RESEARCH §D.5 逐键一致）

| 类别 | 字段 |
|---|---|
| Arc 成功 | `kind, start_angle_deg, start_rel_deg, end_angle_deg, end_rel_deg, swept_deg, elapsed_ms, samples, direction_sign, target{min_angle,max_angle,start_target,start_tolerance,end_targets,end_tolerance,min_ms,max_ms}` |
| Arc 失败 | 同上 + `fail{code,end_rel_deg,nearest_target_deg,distance_deg,tolerance_deg}`（`too_short` 的 target/distance/tolerance 为 null；六个 abort 分支只有 `code` + `elapsed_ms`/`swept_deg`） |
| Sequence | `kind, elapsed_ms, base_deg, tolerance_deg, steps[{label, required_hold_ms, actual_hold_ms, t_done_ms, angle_lo_deg, angle_hi_deg, angle_avg_deg}]` |
| Tap | `kind, interval_ms, window{min_ms,max_ms}, button, modifier` |

## 12 组断言清单

| # | 轨迹 | 断言 |
|---:|---|---|
| 1 | 合成弧 180°→200°，500ms | `swept_deg == 200`（±0.05） |
| 2 | 同上 | `start_rel_deg == 180` |
| 3 | 同上 | `samples == 126`（活动帧数，起手帧计 1） |
| 4 | 同上 | `target.min_ms/max_ms/min_angle` 来自配置 |
| 5 | 同上 | `direction_sign == 1`（shipped 是 `any`，仍要记真实转向） |
| 6 | 合成弧顺时针 230°→50° | `distance == abs(end_rel - nearest)`；`message` 第一个整数 == `round(end_rel)` |
| 7 | shipped 马赛 180°→40° 松手 | `too_short`、`swept < min_angle`、`distance/nearest/tolerance == null` |
| 8 | shipped 马赛快速扫 | `too_fast`、`elapsed < target.min_ms`、上限仍是 600 |
| 9 | 磕球 [前, 后] | 两步 `t_done_ms` 严格递增（4ms → 256ms） |
| 10 | 油炸丸子按住 350ms | `actual_hold_ms` 与 350 差 2ms（< 1 帧） |
| 11 | 油炸丸子按 200ms 松手 | `hold_short`、`actual_hold_ms == 200`、`t_done_ms == null` |
| 12 | 绿射 448ms / 396ms（经 `TapRuntime`） | `interval_ms` 448/396、窗口 400/600、`button=X`、`modifier=RB` |

## Task Commits

每个任务原子提交：

1. **Task 1: Hit/Failure.measured + 三类检测器的结构化度量** - `c06e234` (feat)
2. **Task 2: Outcome.measured 与引擎/运行时的原样透传** - `e79b8f8` (feat)
3. **Task 3: test_measured 12 组断言 + MEASURED 哨兵 + 变异验证** - `06b5a21` (test)

**Plan metadata:** 本次 SUMMARY 提交（docs: complete plan）

## Files Created/Modified

- `mobile/src/core/hit.gd` — `measured: Dictionary = {}` 加在参数末尾，旧位置调用不变
- `mobile/src/core/failure.gd` — 同上
- `mobile/src/core/outcome.gd` — `measured` 字段 + 「引擎原样透传、下游只读」的文档
- `mobile/src/core/detectors/arc_detector.gd` — `_measured()` / `_nearest_end_target()` / `_abort_fail()`；删除 Phase 4 的事后快照入口；修 `_turn_sign` 两个静默洞
- `mobile/src/core/detectors/sequence_detector.gd` — `_step_t` / `_have_step_t` / `_measured()`；成功与四条失败路径都带度量
- `mobile/src/core/detectors/tap_detector.gd` — `_measured()`；成功 + 四条失败路径
- `mobile/src/core/gesture_engine.gd` — `_record` 填入 `outcome.measured`；两条路径各传一份（签名未改）
- `mobile/src/core/tap_runtime.gd` — 文档：单技能门面不再另开度量访问器
- `mobile/tests/unit/test_measured.gd`（新，595 行）— 12 组已知轨迹 + 驱动/断言工具
- `mobile/tests/unit/test_measured.gd.uid`（新）— `--import` 生成的边车文件
- `mobile/tests/core_runner.gd` — 20 → 21 套件
- `mobile/tools/test-core.sh` — `MEASURED cases>=12 mismatches=0` 哨兵

## Decisions Made

- **一次判定只有一份度量**：删除 `ArcDetector.measured()` 这个「事后从检测器再读一次」的入口。它返回的 `target{end_deg,start_deg}` 与 RESEARCH §D.5 的键表不一致，且无人调用 —— 留着就是第二套度量真相。
- **`distance_deg` 用圆周距离**：`Geometry.angle_diff(end_rel, nearest)` 与 `_end_ok` 同一把尺。RESEARCH §D.5 的示例（264°/0°→96）只有圆周距离能成立；组 6 选的 50°/90° 让两种定义同为 40，因此仍可按计划要求的 `abs(end_rel - nearest)` 断言。
- **合成弧而不是 shipped 弧**：出厂两个弧线的终点窗都覆盖了「扫掠中段」，200° 成功与 `wrong_end` 在出厂阈值下不可达。合成只改终点目标/容差/上限，检测器代码与文案零分叉。
- **`_step_t` 存毫秒**：字段名承诺 `t_done_ms`；存秒会让每个消费者各漏乘一次 1000，而这类错误不会在黄金语料里暴露（桌面参考没有该字段）。

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - 计划假设的轨迹不可达] shipped 马赛回旋的 200° 成功与 `wrong_end` 都不可达**

- **Found during:** Task 3（设计组 1~6 的轨迹）
- **Issue:** 出厂马赛回旋 `end_tolerance=80`，从 180° 顺时针扫时，第一次同时满足「min 250ms + 扫掠区间 + 终点窗」的帧在 `swept≈100.8°`（实测），200° 成功根本不可达；`wrong_end` 也要求终点落在窗外的同时不经过窗口，出厂窗口 160° 宽，扫掠必然穿过。
- **Fix:** 组 1~5 改用同形状合成弧（起点 180°、终点 20°±0.5°、扫掠 70°~230°、时长 250~600ms）；组 6 用合成弧（终点 90°±20°、上限 240°、顺时针 230° 不经过 70°~110°）。检测器代码、阈值语义与文案零改动。
- **Files modified:** `mobile/tests/unit/test_measured.gd`
- **Verification:** `MEASURED cases=12 mismatches=0`；黄金 55/29 仍 0 差异
- **Committed in:** `06b5a21`

**2. [Rule 1 - 隐藏 bug] `direction_sign` 在成功路径永远是 0，且 `direction: any` 时永不记录**

- **Found during:** Task 1（读 Phase 4 的 `_capture_measured`）
- **Issue:** 成功分支先 `_turn_sign = 0` 再快照，`direction_sign` 必为 0；而 `_turn_sign` 只在 `direction != 0` 时写入，出厂两个弧线都是 `any`，即使修好清零顺序也仍是 0 —— 对 Phase 7 是死字段。
- **Fix:** 把记录与判定拆开：`swept >= 5°` 时无条件记录实际转向；`wrong_direction` 仍然只在 `direction != 0` 时比较（行为等价）；成功分支先构造 `measured` 再清 `_turn_sign`。
- **Files modified:** `mobile/src/core/detectors/arc_detector.gd`
- **Verification:** 组 5 `direction_sign == 1`；`GESTURE_GOLDEN cases=55 mismatches=0`（判定未变）
- **Committed in:** `c06e234`

**3. [Rule 1 - 单位] `_step_t` 写入的是秒，与 `t_done_ms` 的承诺冲突**

- **Found during:** Task 3（组 9 期望 4ms/256ms）
- **Issue:** 计划文字写 `_step_t[index - 1] = now`，但 `Frame.now` 是秒；直接读进 `t_done_ms` 会得到 0.004/0.256，下游每个消费者都可能漏乘 1000。
- **Fix:** 写入改为 `now * 1000.0`，换算只做一次；注释写明原因。
- **Files modified:** `mobile/src/core/detectors/sequence_detector.gd`
- **Verification:** 组 9 断言 4ms/256ms；变异 3 证明它有牙齿
- **Committed in:** `06b5a21`

**4. [Rule 1 - 重复入口] 删除 Phase 4 遗留的 `ArcDetector.measured()` 快照**

- **Found during:** Task 1
- **Issue:** 该方法的 `target` 键（`end_deg` / `end_tolerance_deg` / `start_deg`）与 RESEARCH §D.5 不一致，且全仓无人调用；保留会形成「随判定产出的 measured」与「事后快照」两个真相。
- **Fix:** 删除方法与 6 个 `_measured_*` 快照字段，改为随 `Hit` / `Failure` 构造。
- **Files modified:** `mobile/src/core/detectors/arc_detector.gd`
- **Verification:** lint 通过；全仓 `measured()` 无调用点
- **Committed in:** `c06e234`

**5. [Rule 1 - 计划文字 vs 参考语义] `distance_deg` 的等式按测试轨迹成立，实现按圆周距离**

- **Found during:** Task 1（对照 RESEARCH §D.5 的 264°/0°→96 示例）
- **Issue:** 计划的 `<behavior>` 写 `distance = abs(end_rel - nearest)`，但 RESEARCH 示例中 264° 与 0° 的距离是 96（圆周距离）。二者只在「不跨 0°」的样本上一致。
- **Fix:** 实现按 `Geometry.angle_diff`（与 `_end_ok` 同源）；组 6 特意选 50°/90°（两种定义同为 40），因此仍按计划要求的 `abs(end_rel - nearest)` 断言，同时在注释里说明选择理由。
- **Files modified:** `mobile/src/core/detectors/arc_detector.gd`、`mobile/tests/unit/test_measured.gd`
- **Verification:** 组 6 通过；变异 2 变红
- **Committed in:** `c06e234` / `06b5a21`

---

**Total deviations:** 5 auto-fixed（5 Rule 1）
**Impact on plan:** 全部是「让轨迹落在参考实现真正可达的边界上」或「消除同一事实的两套表示」。没有删断言、没有放宽阈值、没有改 `message` 文案；`desktop/` 与 `shared/` 零改动。

## 变异验证（D-10，红色行原文）

每一步都先 `cp` 到仓库外临时目录，改源码 → `bash mobile/tools/test-core.sh` → 记录红行 → `cp` 拷回 → 重新跑绿；没有使用 `git checkout --`。

### 变异 1：`swept_deg` 构造成 `swept * 0.999`

```
MEASURED cases=12 mismatches=1
TESTS_FAIL measured: arc_success: swept_deg（实际 199.80000000000001137，期望 200.00000000000000000，容差 0.05）
TESTS_DONE failures=1
```

还原后：`MEASURED cases=12 mismatches=0`、`TESTS_DONE failures=0`、`git diff --exit-code -- mobile/src/core/detectors/arc_detector.gd` 退出 0。

### 变异 2：`fail.distance_deg` 改成 `abs(end_rel)`（漏掉 `- nearest_target`）

```
MEASURED cases=12 mismatches=1
TESTS_FAIL measured: arc_wrong_end: distance_deg 必须等于 abs(end_rel - nearest)（实际 50.00000000000000000，期望 40.00000000000000000，容差 0.000001）
TESTS_DONE failures=1
```

还原后：`MEASURED cases=12 mismatches=0`、`TESTS_DONE failures=0`、`git diff --exit-code` 退出 0。

### 变异 3：删掉 `_step_t[index - 1] = now * 1000.0`

```
MEASURED cases=12 mismatches=2
TESTS_FAIL measured: sequence_two_steps: steps[0].t_done_ms 不能为 null
TESTS_FAIL measured: sequence_two_steps: steps[1].t_done_ms 不能为 null
TESTS_FAIL measured: sequence_hold: t_done_ms 不能为 null
TESTS_DONE failures=3
```

（`mismatches` 计的是「整组红」2 组，`TESTS_DONE failures` 计的是失败断言 3 条。）

还原后：`MEASURED cases=12 mismatches=0`、`TESTS_DONE failures=0`、`git diff --exit-code` 退出 0。

## Issues Encountered

- **首次跑 `MEASURED` 时 4 组红**：两组是「轨迹在出厂阈值下会提前成功」（见 Deviation 1），一组是磕球忘了 `require_neutral_between_steps`（两步之间必须真的回中），还有一次是自己写的 `_arc_success_measured()` 漏了定义（编译期就红，说明套件不是假绿）。全部按参考实现的真实语义修正，没有改断言口径。
- **`_step_t` 的毫秒换算是在 Task 1 提交后补的**：Task 3 写期望值时才发现单位冲突；作为 Deviation 3 记入 Task 3 提交，未改写历史。
- **Godot `--import` 本轮未撞上 SIGSEGV**：6 次完整套件（3 变异 + 3 还原）全部一次导入成功。
- **任务提交仍在 `main` 上**：`branching_strategy: none` + 顺序执行器（`SEQUENTIAL=true`），与 05-01/02/03 的提交线一致；通用提交守卫的「保护分支」检查在此配置下不适用（沿用 05-03 的记录）。

## Known Stubs

无。`measured` 的每个字段都有消费者或明确的下游计划（Phase 7 / 8），且都有断言覆盖；`SequenceDetector._step_t` 与 `_have_step_t` 是纯增量簿记，不是「有字段没人验」的占位。

## Threat Flags

无新增信任面：`measured` 只含角度、毫秒、步标签与目标区间；不含设备名、GUID、账号（T-05-13 的 `accept` 结论成立）。本计划写入全部在 `mobile/src/core/`、`mobile/tests/` 与 `mobile/tools/`；`desktop/padskills/*.py` 与 `shared/skills_config.json` 零改动（SHA-256 保持 `039b2d72…1f10`）。

## User Setup Required

None - 无外部服务、环境变量或真机步骤。

## Next Phase Readiness

- **计划 05（抽稀）可直接消费**：`measured` 已随每次判定产出，抽稀矩阵不需要另算期望；55 + 29 条黄金语料不变。
- **计划 07 的 `OUTCOME` 日志**：`Outcome.measured` 已就位，日志只需结构化输出该字段，不必解析文案。
- **Phase 7 的三条反馈特性有唯一数据源**：时序条（`t_done_ms` / `elapsed_ms`）、失败点高亮（`measured.fail` + `last_path()`）、逐步拆解（`steps[]`）。
- **闸门现状**：`TESTS_SUITES=21`、`TESTS_ASSERTIONS=2664`、`TESTS_DONE failures=0`、`MEASURED cases=12 mismatches=0`、`GESTURE_GOLDEN cases=55`、`GESTURE_RUNTIME cases=29`、`LINT_OK files=33`、`GLYPH_OK chars=1053`、desktop 302/302、gate-a.sh 全绿。
- **无阻塞项**：`desktop/` 与 `shared/` 零改动；Phase 4 的检测器与 tap 运行时全部原样通过。

## Self-Check: PASSED

- 计划内新建/修改的 12 个文件全部存在于工作树；`test_measured.gd` 与 `.gd.uid` 均已提交。
- 三个任务提交均可在 `git log` 中定位：`c06e234` / `e79b8f8` / `06b5a21`。
- 测得提交数：`git rev-list --count 4d961ef..HEAD` = 3（Task 1~3）。
- `git status --porcelain -- desktop shared` 为空；`git diff --exit-code -- mobile/src/core/detectors/arc_detector.gd mobile/src/core/detectors/sequence_detector.gd` 退出 0。
- 最终闸门：`bash mobile/tools/test-core.sh` 全绿（21 套件 / 2664 断言 / `MEASURED cases=12 mismatches=0`）；`bash tools/check_desktop.sh` 302/302；`bash mobile/tools/gate-a.sh` 通过。
