---
phase: 05-judge-parity-decimation
plan: 03
subsystem: core-engine
tags:
  [
    gdscript,
    godot,
    gesture-engine,
    arbitration,
    gesture-lock,
    cooldown,
    golden-fixture,
    mutation-testing,
    judge-parity,
  ]

requires:
  - phase: 05-judge-parity-decimation
    plan: 01
    provides: 生成器骨架 / `configs` 完整对象注册表 / `_CollectingEngine` / `GESTURE_GOLDEN` 哨兵
  - phase: 05-judge-parity-decimation
    plan: 02
    provides: 55 条检测器语料 / 8 份完整配置 / 双层下限与变异验证口径
  - phase: 04-device-input-green-slice
    plan: 01
    provides: `TapRuntime`（构造签名与 6 条 tap runtime 用例）、`Outcome` 队列、`Detector` 基类
  - phase: 03-core-foundation
    plan: 04
    provides: `ConfigValidator.validate` → `ConfigResult`，回放套件用它重建合成配置

provides:
  - "`mobile/src/core/gesture_engine.gd`：`engine.py:248-377` 的完整分支顺序 + 布局硬门 + 结果队列"
  - "`mobile/src/core/active_skill.gd`：逐动作 `skill/detector/last_fire/hits/attempts/failures`"
  - "`TapRuntime extends GestureEngine`：构造签名与公开契约不变，Phase 4 的 2044 条断言零改动"
  - "29 条引擎语料（九组）+ 4 份 `synthetic:*` 完整配置 + `expect.counters`"
  - "哨兵 `GESTURE_RUNTIME cases=29 mismatches=0`（套件 `>= 29` 与 shell grep 同数）"
  - "`state_of(i)` / `cooldown_remaining_ms(i, now)`（Phase 6 只读钩子）"
  - "三次变异验证的红色见证（锁 / discard / observe-reset 顺序）"

affects: [05-04-measured, 05-05-decimation, 05-07-wiring, phase-6-training-loop, phase-7-feedback]

actuals:
  tokens: 294386
  tasks: 3
  commits: 3

plan_head_before: 133cf4ac020bd256912a792415600d6e4b3dbc2b
plan_head_after: cd9126f605fb7b850554f9cc735452ca2b6f34eb

tech-stack:
  added: []
  patterns:
    - "归约式移植：TapRuntime 只做「一个技能 → 单技能 AppConfig」的参数翻译，tick/_record/status 全部继承，单技能与多技能只有一套判定真相"
    - "仲裁用例的期望全部由参考引擎 `Engine._tick` 跑出：手势锁、冷却、discard、失败归属都无法从检测器层推导"
    - "出厂配置不可达的分支用合成配置覆盖：只改一个冷却维度（global 1000 / 三个 cooldown 900），完整对象进 `configs`"
    - "同一帧多条 pending：遍历全部技能取走、只记配置顺序第一个 owner，其余丢弃（没有 break）"
    - "变异验证：cp 到仓库外临时目录 → 改一处 → 跑套件 → 记录红行原文 → cp 还原 → 再跑全绿"

key-files:
  created:
    - mobile/src/core/active_skill.gd
    - mobile/src/core/gesture_engine.gd
    - mobile/tests/unit/test_gesture_engine.gd
    - .planning/phases/05-judge-parity-decimation/05-03-SUMMARY.md
  modified:
    - mobile/src/core/tap_runtime.gd
    - mobile/tests/unit/test_tap_runtime.gd
    - mobile/tests/core_runner.gd
    - mobile/tools/test-core.sh
    - tools/gen_gesture_golden.py
    - mobile/tests/fixtures/gesture_golden.json

key-decisions:
  - "TapRuntime 只做参数翻译：构造签名 5 个参数逐字不变，Phase 4 的 19 套件 / 2044 条断言零改动全绿 —— 机制替换不改变行为的机械证明"
  - "手势锁的 ±4ms 在 4ms 网格 + 「解锁帧必须回中」下不可直接表示：实测边界是 148ms（推着会清零计时，永不解锁）对 156ms（解锁帧之后再推）"
  - "`rt_lock_hold_no_recenter` 在拆掉 `_gesture_locked` 后仍绿：右摇杆一直推着时 ArcDetector 自己的 `armed=false` 已挡住第二段弧；真正有牙齿的锁见证是 `rt_lock_release_150_minus_4`"
  - "`rt_failure_owner_config_order` 用同帧的「马赛 wrong_start + 磕球 too_slow」：LB 按住时 `held_required` 会把不需要 LB 的技能 abandon，双 idle 方案不可达"
  - "`rt_heel_too_slow` 必须在 90°/110° 之间逐帧摆动：静置会先触发 sequence 的 stalled（incomplete），等不到 max_duration 的 too_slow"

requirements-completed: [JUDGE-03, JUDGE-06]

coverage:
  - id: D1
    description: "GestureEngine.tick() 与 engine.py:248-377 同构：布局硬门最前、facing 引擎写、手势锁、held_required 互斥、idle 重置、discard 在冷却前、逐动作/全局冷却、遍历全部技能的失败归属、唯一 8 参数 _record、结果队列"
    requirement: JUDGE-06
    verification:
      - kind: integration
        ref: "bash mobile/tools/test-core.sh#TESTS_SUITES=20 TESTS_ASSERTIONS=2587 TESTS_DONE failures=0"
        status: pass
      - kind: integration
        ref: "mobile/tests/unit/test_gesture_engine.gd#GESTURE_RUNTIME cases=29 mismatches=0"
        status: pass
    human_judgment: false
  - id: D2
    description: "TapRuntime 降为 GestureEngine 子类：构造签名不变、status() 保留布局门、Phase 4 的 18 套件一条不改仍全绿"
    requirement: JUDGE-03
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_tap_runtime.gd#TAP_GOLDEN_RUNTIME cases=6 mismatches=0"
        status: pass
      - kind: unit
        ref: "mobile/tests/unit/test_green_slice.gd#19 套件 / 2044 断言基线 → 20 套件 / 2587"
        status: pass
    human_judgment: false
  - id: D3
    description: "29 条引擎语料覆盖九组仲裁：单动作端到端 10、双动作竞争 2、手势锁 3、逐动作冷却 3、全局冷却 2、idle 重置 2、facing 2、修饰键互斥 2、失败归属 2、分组 1；期望与 counters 由参考引擎逐字段跑出"
    requirement: JUDGE-06
    verification:
      - kind: integration
        ref: "python3 tools/gen_gesture_golden.py --check（detector 55 条、runtime 29 条）"
        status: pass
      - kind: integration
        ref: "mobile/tests/unit/test_gesture_engine.gd#REQUIRED_RUNTIME_IDS 29 条 + 逐字段回放"
        status: pass
    human_judgment: false
  - id: D4
    description: "三次变异验证：拆手势锁 / 拆命中路径 _discard_other_claims / 对调 observe-reset，各自让具名用例变红；还原后 git diff --exit-code 为 0"
    requirement: JUDGE-06
    verification:
      - kind: integration
        ref: "bash mobile/tools/test-core.sh（三次变异 + 三次还原）"
        status: pass
    human_judgment: false
  - id: D5
    description: "合成配置只改一个冷却维度且是完整对象：`synthetic:global_1000`、`synthetic:{stepover,roulette,green}_cd_900`；`shared/skills_config.json` 的 SHA-256 保持 039b2d72…1f10"
    requirement: JUDGE-03
    verification:
      - kind: integration
        ref: "python3 -c \"…assert 'synthetic:global_1000' in d['configs']\"#RUNTIME cases=29 configs=12"
        status: pass
      - kind: integration
        ref: "shasum -a 256 shared/skills_config.json"
        status: pass
    human_judgment: false

duration: 43min
completed: 2026-11-06
status: complete
---

# Phase 5 Plan 03: 多技能 GestureEngine 与 29 条仲裁语料 Summary

**把三类检测器接进完整引擎：多技能 `GestureEngine` 逐段移植 `engine.py:248-377`，`TapRuntime` 降为只做参数翻译的子类（Phase 4 的 2044 条断言零改动全绿），并用 29 条由参考引擎跑出的语料把「一次挥动最多一个判定」的锁、竞争、冷却、idle、互斥、归属与分组逐条钉死。**

## Performance

- **Duration:** 43 min
- **Started:** 2026-11-05T18:38:45Z（以上一计划最后一次提交为锚）
- **Completed:** 2026-11-05T19:21:18Z
- **Tasks:** 3
- **Files modified:** 12（含 3 个 `*.gd.uid` 边车文件与 1 个生成物夹具）

## 基线（开工前实测）

| 命令 | 结果 |
|------|------|
| `bash mobile/tools/test-core.sh` | `TESTS_SUITES=19`、`TESTS_ASSERTIONS=2044`、`TESTS_DONE failures=0` |
| `GESTURE_GOLDEN` | `cases=55 mismatches=0` |
| `TAP_GOLDEN_RUNTIME` | `cases=6 mismatches=0` |
| `python3 tools/make_font_subset.py --check` | 1053 字符一致 |
| `bash tools/check_desktop.sh` | 302/302 |
| `shasum -a 256 shared/skills_config.json` | `039b2d72…1f10` |

## Accomplishments

- **多技能引擎落地**：`GestureEngine.tick()` 逐段对应 `engine.py:248-377`。三处移动端差异（布局硬门最前、结果队列、公开 `reset_progress()`）写进类文档；`focus`/`paused`/震动/调试渲染明确不移植。
- **Phase 4 零回归**：`TapRuntime` 的 5 参数构造签名一字未改，只把技能翻译成单技能 `AppConfig`；19 套件 / 2044 条断言全部原样通过，`GESTURE_GOLDEN cases=55` 不变。
- **29 条引擎语料**：九组全部有夹具，`expect.outcomes` 与 `expect.counters` 都由参考引擎 `_tick` 跑出；`GESTURE_RUNTIME cases=29 mismatches=0` 由套件与 `test-core.sh` 双层 29 下限机械校验。
- **出厂不可达分支被合成配置覆盖**：`global_cooldown_ms=1000` 让全局冷却真的吞掉第二发（`suppressed=1`）；三个 `cooldown_ms=900` 让逐动作冷却**静默**吞掉（`suppressed` 不变）。
- **失败归属与清场**：`rt_failure_owner_config_order` 在同帧放两条 pending（马赛 `wrong_start` + 磕球 `too_slow`），只留配置顺序第一个；`rt_failure_clears_others` 证明失败会作废另一动作的半截保持进度。
- **三次变异验证**：拆锁、拆 discard、对调 observe/reset 各自让具名用例变红；三次都按临时目录备份原样还原，`git diff --exit-code` 为 0。
- **闸门现状**：20 套件 / **2587** 断言 / `failures=0`、`LINT_OK files=33`、`GLYPH_OK chars=1053`、desktop 302/302、两个夹具 `--check` 一致。

## 引擎语料矩阵（29 条）

| 组 | 条数 | id | 关键期望 |
|---|---:|---|---|
| 单动作端到端 | 10 | `rt_roulette_ok` / `rt_roulette_too_fast` / `rt_stepover_ok` / `rt_stepover_wrong_start` / `rt_heel_ok` / `rt_heel_too_slow` / `rt_croqueta_ok` / `rt_croqueta_hold_short` / `rt_green_ok` / `rt_green_too_fast` | 5 个动作各 1 成功 + 1 失败 |
| 双动作竞争 | 2 | `rt_competition_stepover_wins` / `rt_competition_roulette_wins` | 0°→90° 只出踩单车；180°→380° 只出马赛 |
| 手势锁 | 3 | `rt_lock_hold_no_recenter` / `rt_lock_release_150_plus_4` / `rt_lock_release_150_minus_4` | 不回中 1 条；解锁后 2 条；148ms 推着永不解锁 |
| 逐动作冷却 | 3 | `rt_cooldown_stepover` / `rt_cooldown_roulette` / `rt_cooldown_green` | 第二发 780/784/888ms 被静默吞，`suppressed=0` |
| 全局冷却 | 2 | `rt_global_cooldown_synthetic` / `rt_global_cooldown_shipped_unreachable` | 合成 `suppressed=1`；出厂 60ms `suppressed=0` |
| idle 重置 | 2 | `rt_idle_reset_250` / `rt_idle_hold_no_reset` | 静置 → 磕球 `incomplete@452`；持续移动 → `ok@404` |
| facing | 2 | `rt_facing_centered_zero_verdict` / `rt_facing_held_hit` | LS 回中零判定；同一轨迹 LS 推住命中 |
| 修饰键互斥 | 2 | `rt_modifier_lb_abandons_arcs` / `rt_modifier_lb_keeps_croqueta` | LB 按住时 0°→70° 弧零判定；油炸丸子照常 |
| 失败归属 | 2 | `rt_failure_owner_config_order` / `rt_failure_clears_others` | 同帧只留马赛；绿色失败后油炸丸子不再补 `ok` |
| 分组 | 1 | `rt_group_ten_hits` | 10 发：`group_hits=0`、`groups_done=1` |

`configs` 注册表 12 份：`shipped` + 7 个 detector 变体 + 4 个引擎合成配置。

### 由参考引擎跑出的关键期望（逐条核对）

| 用例 | 期望 |
|---|---|
| `rt_lock_release_150_plus_4` | 2 条 `ok`：492ms + 1272ms（解锁帧 756 后再武装，880 起第二段） |
| `rt_lock_release_150_minus_4` | 1 条 `ok`：744ms 就推第二段，回中计时被清零，锁永不解开 |
| `rt_global_cooldown_synthetic` | 1 条 `ok`、`suppressed=1`（第二发 784ms < 1000） |
| `rt_cooldown_green` | 1 条 `ok`、`suppressed=0`（第二发 888ms < 900） |
| `rt_failure_owner_config_order` | 1 条 `wrong_start`（马赛，elapsed 4ms）；同帧磕球 `too_slow` 被丢弃 |
| `rt_failure_clears_others` | 1 条绿色 `too_slow@1352`；油炸丸子 152ms 的保持进度被作废 |
| `rt_idle_hold_no_reset` | `ok@404`（第 1 步 t0=100，elapsed 304 ≥ 250） |
| `rt_group_ten_hits` | 10 条 `ok`（548…9548ms），`group_hits=0`、`groups_done=1` |

## Task Commits

每个任务原子提交：

1. **Task 1: ActiveSkill + GestureEngine 全量 tick 移植，TapRuntime 降为子类** - `2c1705c` (feat)
2. **Task 2: 29 条引擎语料 + GESTURE_RUNTIME 哨兵** - `89cd0fc` (feat)
3. **Task 3: 记录三次变异验证的红色见证** - `cd9126f` (test)

**Plan metadata:** 本次 SUMMARY 提交（docs: complete plan）

## Files Created/Modified

- `mobile/src/core/active_skill.gd`（新）— `engine.py:78-89` 的逐动作容器；`last_fire = -1e9` 让第一发不受冷却限制
- `mobile/src/core/gesture_engine.gd`（新，412 行）— 完整分支顺序、唯一 8 参数 `_record`、结果队列、Phase 6 只读钩子
- `mobile/src/core/tap_runtime.gd`（重写）— 保留 `select_taps_skill` 与 5 参数构造，只做合成配置与 `super._init`
- `mobile/tests/unit/test_gesture_engine.gd`（新，317 行）— 29 条逐帧回放 + counters + 三条反向对照契约 + 变异见证注释
- `mobile/tests/unit/test_tap_runtime.gd`（注释）— 「构造期禁用」→「运行期由 `ls_ok` 决定」；断言一条未动
- `mobile/tests/core_runner.gd` — `gesture_engine` preload；19 → 20 套件
- `mobile/tools/test-core.sh` — `GESTURE_RUNTIME cases=(29|…) mismatches=0` grep
- `tools/gen_gesture_golden.py` — `RUNTIME_CASES` 29 条、`_osc()`、`_runtime_from()`、`synthetic_global()`、`synthetic_skill_cooldown()`、`_runtime_counters()`
- `mobile/tests/fixtures/gesture_golden.json` — 生成物：55 detector + 29 runtime，12 份配置（1.07 MB → 2.0 MB）

## Decisions Made

- **TapRuntime 只做参数翻译**：任何逻辑分叉都会让「单技能」与「多技能」成为两套判定真相。Phase 4 的 2044 条断言原样通过，是这次机制替换最强的证据。
- **统一 `_record` 8 参数**：`TapRuntime` 不再声明自己的 6 参数版本；计划 04 只填 `measured`，不再动签名。
- **合成冷却只改一个维度**：出厂 350/400/450ms 与全局 60ms 在「锁 150 + 重新武装 + 最短动作」之后不可达；合成值只证明分支可达，不改真源。
- **`status()` 先过布局门**：单动作委托检测器、多动作返回「自由练习」，不在状态行里拼技能名（Phase 6 才定义）。
- **`state_of()` 的 tracking 用 `detector.status() != "待机"`**：三个检测器共用同一空闲标记，不新增第二个判定真源。

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - 计划文字 vs 参考实现] 变异 1 的计划见证 `rt_lock_hold_no_recenter` 实测保持绿色；真正有牙齿的是 `rt_lock_release_150_minus_4`**

- **Found during:** Task 3（变异验证 1）
- **Issue:** 计划写「把命中分支的 `_gesture_locked = true` 注释掉 → `rt_lock_hold_no_recenter` 必须变红（多出第 2 条）」。但该用例右摇杆一直推着（`rs_mag=0.9`），ArcDetector 自己在首段命中后 `armed=false`、且只在下穿 `exit` 时重新武装 —— 摘掉手势锁后它仍然看不到第二段弧，套件保持全绿。
- **Fix:** 按计划「没有变红就补一条有牙齿的用例」的要求先验证现有语料：`rt_lock_release_150_minus_4` 在摘掉锁后从 1 条变 2 条（744ms 推的第二段弧被已重新武装的检测器接受）。用它作变异 1 的具名见证，并把「hold_no_recenter 为何仍绿」写进套件注释与 SUMMARY。
- **Files modified:** 无临时改动（变异已还原）；`mobile/tests/unit/test_gesture_engine.gd` 增加变异见证注释
- **Verification:** 变异后 `GESTURE_RUNTIME cases=29 mismatches=4`；还原后 `mismatches=0`
- **Committed in:** `cd9126f`（Task 3 提交）

**2. [Rule 3 - 可达性] 150ms ±4ms 在 4ms 网格 + 「解锁帧必须回中」下不可直接表示**

- **Found during:** Task 2（设计 `rt_lock_release_150_*`）
- **Issue:** 锁的计时从命中后第一个回中帧开始；解锁要求「该帧回中且已满 150ms」。右摇杆 ≥ `RELEASE_STICK` 会把计时清零（`engine.py:284-285`），所以「150±4ms 后推第二段」在 4ms 网格上不可能只差 4ms：148ms 推会清零计时、永不解锁；156ms 推才落在解锁帧之后。
- **Fix:** 两个用例按真实可达语义落：`minus_4` 在 140ms（744）就推并保持 → 永不解锁（1 条）；`plus_4` 在解锁帧 756 之后继续回中到 876 再武装、880 起第二段 → 2 条。差异写进用例注释与 SUMMARY。
- **Files modified:** `tools/gen_gesture_golden.py`
- **Verification:** 两个用例的期望由参考引擎跑出，逐字段一致
- **Committed in:** `89cd0fc`（Task 2 提交）

**3. [Rule 3 - 可达性] 磕球 `too_slow` 不能用静止保持得到：sequence 的 stalled 会先报 `incomplete`**

- **Found during:** Task 2（设计 `rt_heel_too_slow`）
- **Issue:** 只完成第 1 步后把右摇杆停在 90°，`_last_motion` 超过 `idle_timeout_ms=250` 会先触发 `stalled`，得到 `incomplete@552`，等不到 `max_duration` 的 `too_slow@704`。
- **Fix:** 在 90°/110° 之间逐帧摆动（`_osc()`），既刷新「在动」计时器又不匹配任何一步；704ms 时 elapsed 604 > 600 → `too_slow`。
- **Files modified:** `tools/gen_gesture_golden.py`
- **Verification:** 生成器输出 `too_slow 604.0 at 704.0`
- **Committed in:** `89cd0fc`

**4. [Rule 1 - 计划设计的轨迹不可达] 双 idle 的失败归属不可行：LB 按住时 `held_required` 会 abandon 磕球**

- **Found during:** Task 2（设计 `rt_failure_owner_config_order`）
- **Issue:** 原设计用「磕球 + 油炸丸子同时 idle」制造同帧两条 pending；但油炸丸子需要 LB，LB 一按住，`held_required` 就把不需要 LB 的磕球 `abandon()`，磕球进度消失，只剩油炸丸子一条。
- **Fix:** 改成同帧两条**不同来源**的失败：300–696ms 用 `rs_mag=0.3` 摆动（低于 arc 的 `enter=0.72` 让它保持武装、高于 `IDLE_STICK=0.20` 且持续在动），704ms 推 100° 让马赛报 `wrong_start`，同一帧磕球 elapsed 604 → `too_slow`。配置顺序决定马赛胜出。
- **Files modified:** `tools/gen_gesture_golden.py`
- **Verification:** 期望只有 1 条 `wrong_start`，`attempts=1`
- **Committed in:** `89cd0fc`

**5. [Rule 3 - 计划 04 的前置占位] `_record` 的 8 参数签名先定稿，`Outcome.measured` 留给计划 04**

- **Found during:** Task 1
- **Issue:** 计划要求 `_record(..., measured := {})` 在本计划定稿，但 `Outcome.measured` 由计划 04 添加；本计划不能用这个参数，否则会产生「传了但没写」的静默丢弃。
- **Fix:** 参数保留并加 `@warning_ignore("unused_parameter")`，注释写明「计划 04 才透传」；计划 04 填 `measured` 时可移除该注解。
- **Files modified:** `mobile/src/core/gesture_engine.gd`
- **Verification:** `GESTURE_RUNTIME` 全绿；全仓 `func _record` 只有 1 处定义
- **Committed in:** `2c1705c`（Task 1 提交）

---

**Total deviations:** 5 auto-fixed（2 Rule 1、3 Rule 3）
**Impact on plan:** 全部是「让用例落在参考实现真正可达的边界上」与「计划文字与实际机制冲突」的修正；没有删条、没有放宽断言、没有改真源阈值。Phase 4 的 1533/2044 条断言一条未动。

## 变异验证（D-10，红色行原文）

每一步都先 `cp` 到仓库外临时目录，改源码 → `bash mobile/tools/test-core.sh` → 记录红色行 → `cp` 拷回 → 重新跑绿。没有使用 `git checkout --`，避免误还原其他人未提交的改动。

### 变异 1：命中分支不置 `_gesture_locked = true`

`GESTURE_RUNTIME cases=29 mismatches=4`

```
TESTS_FAIL gesture_engine: rt_lock_release_150_minus_4: Outcome 条数（实际 2，期望 1）
TESTS_FAIL tap_runtime: rt_gesture_lock: Outcome 条数（实际 3，期望 2）
```

（另两条为 `rt_lock_release_150_minus_4` 的 `counters.hits` / `counters.attempts`，以及 `rt_release_hold_rearm` 的同名断言。）

还原后：`GESTURE_RUNTIME cases=29 mismatches=0`、`TESTS_DONE failures=0`。

### 变异 2：命中路径不调 `_discard_other_claims(active)`

`GESTURE_RUNTIME cases=29 mismatches=24`

```
TESTS_FAIL gesture_engine: rt_competition_stepover_wins: Outcome 条数（实际 2，期望 1）
```

（其余红行是磕球的迟到 `incomplete` 污染了多个二次动作用例；`counters.attempts` 同步变红。）

还原后：`GESTURE_RUNTIME cases=29 mismatches=0`、`TESTS_DONE failures=0`。

### 变异 3：三道前置分支把 `observe(frame)` 与 `reset()` 对调

`GESTURE_RUNTIME cases=29 mismatches=1`

```
TESTS_FAIL gesture_engine: rt_croqueta_hold_short: outcomes[0].elapsed_ms（实际 195.99999999999997158，期望 200.00000000000000000，容差 0.000001）
TESTS_FAIL tap_runtime: rt_one_verdict_per_attempt: outcomes[0].elapsed_ms（实际 195.99999999999997158，期望 200.00000000000000000，容差 0.000001）
```

还原后：`GESTURE_RUNTIME cases=29 mismatches=0`、`TESTS_DONE failures=0`；`git diff --exit-code -- mobile/src/core/gesture_engine.gd mobile/src/core/tap_runtime.gd` 退出 0。

## Issues Encountered

- **本次提交在 `main` 上**：工程配置 `branching_strategy: none`，且编排器以顺序执行器指令派发（`SEQUENTIAL=true`）。与 05-01 / 05-02 的提交线一致；通用提交守卫里的「保护分支」检查在此配置下不适用。
- **Godot `--import` 本轮未撞上 SIGSEGV**：6 次完整套件（3 变异 + 3 还原）全部一次导入成功。
- **夹具从 1.07 MB 涨到 2.0 MB**：29 条 runtime 用例中 `rt_group_ten_hits` 单条 2501 帧，占增量的大头；`--check` 仍逐字节一致。

## Known Stubs

无。`GestureEngine` 的公开面覆盖了 `practice_screen.gd` 逐一调用的每个方法；`state_of()` / `cooldown_remaining_ms()` 是给 Phase 6 的只读钩子，本阶段不进夹具但已实现并有明确文档，不构成「有字段没人验」的占位。

## Threat Flags

无新增信任面：本计划只读 `desktop/padskills/*.py` 与 `shared/skills_config.json`（SHA-256 保持 `039b2d72…1f10`），写入全部在 `mobile/src/core/`、`mobile/tests/` 与 `tools/`。变异验证只临时改 `mobile/src/core/gesture_engine.gd`，已按字节还原。

## User Setup Required

None - 无外部服务或环境变量。

## Next Phase Readiness

- **计划 04 可直接消费**：`_record` 的 8 参数签名已定稿，计划 04 只需把 `Hit.measured` / `Failure.measured` 透传进第 8 个参数，并给 `Outcome` 加 `measured` 字段。
- **计划 05 的抽稀矩阵有夹具基础**：55 + 29 = 84 条 250 Hz 用例全部由 Python 参考跑出，抽稀变体可以逐条重放而不是手写期望。
- **计划 06/07 的只读钩子已就位**：`state_of(i)` / `cooldown_remaining_ms(i, now)`；`display_title` 默认「自由练习」。
- **闸门现状**：`TESTS_SUITES=20`、`TESTS_ASSERTIONS=2587`、`TESTS_DONE failures=0`、`GESTURE_GOLDEN cases=55`、`GESTURE_RUNTIME cases=29`、`LINT_OK files=33`、`GLYPH_OK chars=1053`、desktop 302/302。
- **无阻塞项**：`desktop/` 与 `shared/` 零改动；Phase 4 的检测器与 tap 运行时全部原样通过。

## Self-Check: PASSED

- 计划内 12 个文件全部存在于工作树；夹具 55 + 29 条、12 份配置。
- 三个任务提交均可在 `git log` 中定位：`2c1705c` / `89cd0fc` / `cd9126f`。
- 测得提交数：`git rev-list --count 133cf4a..HEAD` = 3；`git status --porcelain -- shared desktop` 为空。
- 最终闸门：`python3 tools/gen_gesture_golden.py --check` 退出 0；`bash mobile/tools/test-core.sh` 全绿；`bash tools/check_desktop.sh` 302/302。
