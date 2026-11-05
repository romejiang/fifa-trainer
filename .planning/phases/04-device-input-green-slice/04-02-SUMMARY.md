---
phase: 04-device-input-green-slice
plan: 02
subsystem: core-runtime
tags: [gdscript, godot, tap-runtime, outcome-queue, golden-fixture, python-parity, layout-gate]

requires:
  - phase: 04-device-input-green-slice
    plan: 01
    provides: `Frame`（now 秒 + buttons 字典）、`Hit` / `Failure`、`Detector` 基类、`TapDetector`、`tap_golden.json` 的 schema 与 12 条 detector 用例
  - phase: 03-core-foundation
    plan: 03
    provides: `Skill` / `AppConfig` / `InputConfig` 域对象与 `Skill.KIND_TAPS` / `MODE_ANY`
  - phase: 03-core-foundation
    plan: 04
    provides: `ConfigLoader.parse_bytes` → `ConfigResult`，回放套件用它读真实配置副本
  - phase: 03-core-foundation
    plan: 01
    provides: 无头 runner + `TESTS_DONE failures=0` 哨兵 + `test-core.sh` 唯一入口

provides:
  - "mobile/src/core/outcome.gd：`Outcome`（skill_name / ok / code / message / elapsed_ms / at / detail / seq）"
  - "mobile/src/core/tap_runtime.gd：`TapRuntime` —— 手势锁、冷却、单槽失败、分组、`layout_confirmed` 硬门、`pop_outcomes()` 队列、`select_taps_skill()`"
  - "mobile/tests/fixtures/tap_golden.json：18 条用例（12 detector + 6 runtime），runtime 期望由 Python `Engine._tick` 逐帧驱动生成"
  - "mobile/tests/unit/test_tap_runtime.gd：runtime 回放 + 五条结构断言 + `TAP_GOLDEN_RUNTIME` 哨兵"
  - "mobile/tools/test-core.sh：`TAP_GOLDEN_RUNTIME cases=N mismatches=0` 正向哨兵"
  - "mobile/tools/test-core-selftest.sh：第 5 条反例 fixture_missing → `SELFTEST_OK cases=6`"
  - "mobile/docs/CORE.md 第 6 节：数据与判定契约 + 三处范围收缩"

affects: [04-05-onboarding-flow, 04-06-practice-screen, phase-5-detectors, phase-6-training-loop]

actuals:
  tokens: 41258
  tasks: 3
  commits: 4

plan_head_before: b00fedc8fbc2d69756125dc6691e71dc1b6831ad
plan_head_after: ea99cadd18b9379d515239c4274dcd6846f4ba06

tech-stack:
  added: []
  patterns:
    - "运行时夹具：用 Python `Engine._tick` 逐帧驱动（不是 `run()` 墙钟循环），把 `_record` 包一层收集**全部** Outcome"
    - "counters 只从唯一的 `kind == \"taps\"` ActiveSkill 读；按 `kind` 选，绝不按名字或下标"
    - "结构断言必须展开到逐帧 4ms 网格：稀疏变化点会让手势锁 / 重新武装的计时器永远等不到阈值"
    - "断言非真空的自证：反向变异（删锁 / 删门 / 改 suppressed）必须让**对应那一条**变红"
    - "同一份夹具按 `kind` 分工两个套件，哨兵各带实际条数与差异数"
    - "闸门只加强：新增正向哨兵 + 第 5 条反例，既有 TESTS_DONE / TESTS_ASSERTIONS 判据一字未改"

key-files:
  created:
    - mobile/src/core/outcome.gd
    - mobile/src/core/outcome.gd.uid
    - mobile/src/core/tap_runtime.gd
    - mobile/src/core/tap_runtime.gd.uid
    - mobile/tests/unit/test_tap_runtime.gd
    - mobile/tests/unit/test_tap_runtime.gd.uid
  modified:
    - tools/gen_tap_golden.py
    - mobile/tests/fixtures/tap_golden.json
    - mobile/tests/core_runner.gd
    - mobile/tools/test-core.sh
    - mobile/tools/test-core-selftest.sh
    - mobile/docs/CORE.md

key-decisions:
  - "`layout_confirmed == false` 是 `tick()` 的第一早退，位于手势锁判断**之前**：界面被绕过时运行时仍然零输出"
  - "`set_layout_confirmed(false)` 调 `abandon()` 而不是 `reset()`：断连不是一次尝试，不得产 `too_slow` / `hold_short`，同时清空未取走的 Outcome"
  - "结果用 `Array[Outcome]` 队列 + `pop_outcomes()` 全量 drain + 单调 `seq`：Python 的 `last_outcome` 会在同帧两条时静默吞掉第一条"
  - "逐动作冷却吞掉时**静默**（不加 suppressed），全局冷却吞掉时 `suppressed += 1`；两个分支各有一条可达的合成时序，不互相冒充"
  - "真实配置 450ms 下逐动作冷却分支不可达（手势锁 150 + 重新武装 120 + 最短间隔 400 = 670），只能用 `cooldown_ms = 900` 的合成运行时证明"
  - "`select_taps_skill()` 按 `kind == \"taps\"` 选唯一动作：真实配置把绿色搓射排在最后，`skills[0]` 是马赛回旋"
  - "`relative_to_ls` 的技能构造即 `_enabled = false`：本阶段没有左摇杆基准，绝不在缺基准时判相对动作"
  - "结构断言用「变化点 + 结束时刻」+ 逐帧展开，与生成器同一形状：夹具与套件用同一种时间分辨率"
  - "200 帧布局门断言叠加一条干净的 500ms 两下：纯确定性噪声凑不成合法搓射，否则删掉布局门也照样绿"

patterns-established:
  - "Pattern 1：运行时行为的期望值也只能来自参考实现；移动端独有结构（布局门）直接写空期望，不伪称来自 Python"
  - "Pattern 2：每个「吞掉」分支都要有独立的可达时序，混成一个断言时改坏任一边都看不出来"
  - "Pattern 3：新增反向断言时同时做一次变异验证，证明它真的会因为缺陷变红（本次三个变异各自只红对应一条）"
  - "Pattern 4：闸门反例的还原证明用内容摘要（sha256），不用 `git status` —— 工作区可能本来就有未提交改动"

requirements-completed: []

# INPUT-04 在本计划**不宣布完成**：本计划只承接「未确认布局零判定」这一半（运行时硬门）。
# 布局建议表、按键确认页与「不静默猜测」在 04-03 与 04-05（见本计划 Flagged Assumptions）。
# INPUT-05 同理只闭合结构半边（一次一条 / 两次两条），帧内反转的事件捕获在 04-04。

coverage:
  - id: D1
    description: "TapRuntime 移植 tap 场景真正用到的引擎分支：手势锁、修饰键门、命中后逐动作/全局冷却、分组、失败单槽 drain，顺序与 engine.py:198-363 逐条对应"
    verification:
      - kind: unit
        ref: "bash mobile/tools/test-core.sh#TAP_GOLDEN_RUNTIME cases=6 mismatches=0"
        status: pass
    human_judgment: false
  - id: D2
    description: "未确认布局零判定：`layout_confirmed` 是第一早退；200 帧噪声+合法两下与 `rt_layout_gate_blocks` 双覆盖；撤销确认静默 abandon，断连不产判定"
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_tap_runtime.gd#_check_layout_gate_blocks + rt_layout_gate_blocks；反向变异删门 → 7 处差异"
        status: pass
    human_judgment: false
  - id: D3
    description: "一次尝试一条判定、两次尝试两条独立判定：`rt_one_verdict_per_attempt` 1 条 hold_short、`rt_two_shots_500/1000` 各 2 条 ok，Outcome.seq 从 1 单调递增"
    verification:
      - kind: unit
        ref: "bash mobile/tools/test-core.sh#TAP_GOLDEN_RUNTIME cases=6 mismatches=0"
        status: pass
    human_judgment: false
  - id: D4
    description: "冷却两分支各自可达：逐动作 900ms 静默（1 条 Outcome / suppressed 0）、全局 1000ms 计数（1 条 Outcome / suppressed 1）"
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_tap_runtime.gd#_check_skill_cooldown_silent / _check_global_cooldown_counts；反向变异各红 1 条"
        status: pass
    human_judgment: false
  - id: D5
    description: "分组与选择器：group_size=2 时第 2 次命中归零并 groups_done+1，默认仍是 GROUP_SIZE=10；select_taps_skill 按 kind 选唯一动作；relative_to_ls 禁用"
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_tap_runtime.gd#_check_group_rollover / _check_relative_skill_disabled + meta.skill 断言"
        status: pass
    human_judgment: false
  - id: D6
    description: "闸门只加强：`TAP_GOLDEN_RUNTIME cases=6 mismatches=0` 正向哨兵 + 第 5 条反例 fixture_missing；夹具缺失时生成器自己的提示让闸门变红并原样还原"
    verification:
      - kind: integration
        ref: "bash mobile/tools/test-core-selftest.sh#SELFTEST_OK cases=6"
        status: pass
    human_judgment: false
  - id: D7
    description: "CORE.md 第 6 节记录 Frame 两字段口径、三个判定值对象、TapRuntime 三条契约与三处范围收缩；不新增 lint 规则 id"
    verification:
      - kind: unit
        ref: "python3 tools/test_lint_core_purity.py + grep 四个契约片段"
        status: pass
    human_judgment: false

duration: 10min
completed: 2026-11-05
status: complete
---

# Phase 4 Plan 02: TapRuntime 引擎子集 + 布局硬门 + 运行时黄金回放 Summary

**「一次一条、两次两条、未确认布局零条」从约定变成结构：18 条黄金用例（12 detector + 6 runtime）由 Python `Engine._tick` 逐帧生成，无头回放 `TAP_GOLDEN_RUNTIME cases=6 mismatches=0`，且删锁 / 删门 / 改冷却的变异各自只红对应那一条断言**

## Performance

- **Duration:** 10 min
- **Started:** 2026-11-05T09:26:00Z
- **Completed:** 2026-11-05T09:37:20Z
- **Tasks:** 3（+1 个加强提交）
- **Files modified:** 12（6 新建、6 修改）

## Accomplishments

- `TapRuntime` 落地：手势锁（150 ms 固定锁满 + 锁满调一次 `on_idle()`）、修饰键门（`all` / `any` 两种模式）、命中后逐动作冷却 → 全局冷却、分组、失败单槽 drain，分支顺序与 `engine.py:198-363` 逐条对应。`_discard_other_claims` / `held_required` / `idle_reset_ms` 三处单技能不可达或对 tap 等价，按计划收缩并在代码里标注 Phase 5 必须还原。
- `layout_confirmed == false` 成为 `tick()` 的**第一早退**，位于手势锁之前；`set_layout_confirmed(false)` 用 `abandon()` 静默清场并清空未取走的 Outcome。成功标准 4 从「界面自觉」变成运行时结构，200 帧噪声断言与 `rt_layout_gate_blocks` 双覆盖。
- 结果表示从 Python 的 `last_outcome` 单槽改为 `Array[Outcome]` 队列 + `pop_outcomes()` 全量 drain + 单调 `seq`；每个夹具用例都断言 `seq == index + 1`，所以「同帧两条被吞掉」会立刻变红。
- 生成器加 runtime 分支：`Engine._tick` 逐帧驱动、`_record` 包一层收集全部 Outcome；counters 只从唯一的 `kind == "taps"` ActiveSkill 读（负向 grep `skills\[0\]` = 0），`rt_layout_gate_blocks` 的期望直接写空、不伪称来自 Python。
- 6 条 runtime 用例钉死六种行为：两发独立（500 / 1000 ms 空档）、手势锁（锁定期内的 20 ms 两下不产 `too_fast`）、重新武装、一次一条（`hold_short` 后 20 帧无第二条）、布局硬门、相对动作禁用。
- 闸门只加强：`TAP_GOLDEN_RUNTIME` 正向哨兵与 `TAP_GOLDEN_DETECTOR` 并列，自测追加第 5 条反例 `fixture_missing`（生成器自己的「缺少 tap 黄金夹具」让闸门变红），`SELFTEST_OK cases=6`。
- 全套基线保持绿：`TESTS_SUITES=10` / `TESTS_ASSERTIONS=808` / `TESTS_DONE failures=0`；`LINT_OK files=22`；`PARITY_OK cases=28 divergences=4`；`check_desktop.sh` 230/230；闸门 A 通过。

## Task Commits

Each task was committed atomically:

1. **Task 1: Outcome 数据结构 + TapRuntime 引擎子集（含 layout_confirmed 硬门）** — `0b1db24` (feat)
2. **Task 2: 6 条 runtime 用例 + TAP_GOLDEN_RUNTIME 哨兵 + 闸门第 5 条反例** — `14f4680` (feat)
3. **Task 3: 把 core 的数据与判定契约写进 CORE.md** — `91f560b` (docs)
4. **加强：让「未确认布局 200 帧」断言不再是真空** — `ea99cad` (test)

**Plan metadata:** 见本次最终 docs 提交（SUMMARY / STATE / ROADMAP）

## Files Created/Modified

- `mobile/src/core/outcome.gd` — 对齐 `engine.py:62-76` 的判定值对象，另加单调 `seq`；公开字段、无 getter、不读时钟
- `mobile/src/core/tap_runtime.gd` — 引擎子集（240 行）：四类分支顺序、`GROUP_SIZE`、`pop_outcomes()`、`status()`、`set_layout_confirmed()`、`select_taps_skill()`
- `mobile/tests/unit/test_tap_runtime.gd` — runtime 回放 + 五条结构断言 + `TAP_GOLDEN_RUNTIME` 哨兵（397 行）
- `tools/gen_tap_golden.py` — 新增 `RUNTIME_CASES`、`_NullSource` / `_CollectingEngine`、`_drive_runtime()`、`_runtime_case_payload()`；`--check` 分别报两类的条数
- `mobile/tests/fixtures/tap_golden.json` — 12 → 18 条用例（+7961 行），runtime 期望全部由参考引擎生成
- `mobile/tests/core_runner.gd` — `SUITES` 增至 10 条（新增 `tap_runtime`）
- `mobile/tools/test-core.sh` — 新增 `TAP_GOLDEN_RUNTIME` 正向哨兵与通过行
- `mobile/tools/test-core-selftest.sh` — 第 5 条反例 `fixture_missing`、`trap` 扩成 rm+restore、`SELFTEST_OK cases=6`
- `mobile/docs/CORE.md` — 第 6 节「数据与判定契约」+ 三处范围收缩；第 5 节补夹具分工
- 三个 `.gd.uid` 边车（`outcome.gd.uid` / `tap_runtime.gd.uid` / `test_tap_runtime.gd.uid`）—— Godot 4.7.2 导入生成，按既有约定提交

## Decisions Made

- **布局门必须是第一早退**：放在手势锁之后就会出现「锁定期跨过撤销确认」的窗口，界面被绕过时仍可能出判定。
- **撤销确认用 `abandon()` 而非 `reset()`**：手柄中途断开时 `now` 会跳走几分钟，继续用旧 `_t0` 必然报 `too_slow`；断连不是尝试，必须一声不吭。
- **两个冷却分支各用一条合成时序**：真实 450ms 下逐动作分支不可达（最早第二发命中在 670ms 后），拿真实时序「证明」它等于没测。
- **counters 按 `kind` 选动作**：真实配置把绿色搓射排在 `skills` 最后，按下标读会永远得到 0，而且名字可被翻译改掉。
- **结构断言的判定阈值必须可达**：`_check_layout_gate_blocks` 叠一条干净两下，否则「删掉布局门也照样零 Outcome」——真空绿。
- **`select_taps_skill` 是唯一筛选点**：组合根与测试调同一个函数，不许各自复刻筛选循环。

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] 结构断言最初只喂变化点，计时器永远推不动**
- **Found during:** Task 2（首次跑 `TESTS_DONE failures=4`）
- **Issue:** `_check_global_cooldown_counts` / `_check_skill_cooldown_silent` / `_check_group_rollover` 只按变化点喂帧（0 / 4 / 100 / 104 / 600 / 604 / 1304 / 1308 / 1804 / 1808）。手势锁与重新武装都是**按帧推进的计时器**：稀疏帧下 `604 → 1304` 一步跨过 700ms，解锁帧上检测器第一次看到「X 仍按着」，1304 的按下被未武装分支吞掉，第二发永远不发生。
- **Fix:** 新增 `_drive(runtime, changes, end_ms)`，把「变化点 + 结束时刻」展开成逐帧 4ms 时间轴（与生成器 `_build_frames` 同形状）；三条断言改用 `_drive()`。
- **Files modified:** mobile/tests/unit/test_tap_runtime.gd
- **Verification:** 修复后 `TAP_GOLDEN_RUNTIME cases=6 mismatches=0`、`TESTS_DONE failures=0`；`_check_skill_cooldown_silent` 也从「真空通过」变为真实可达（变异后只红它一条）。
- **Committed in:** `14f4680`

**2. [Rule 2 - 加强] 200 帧布局门断言原本是真空的**
- **Found during:** 变异验证（临时删掉 `layout_confirmed` 早退）
- **Issue:** 确定性噪声的 X 每 4~16ms 反转一次，`_armed` 永远等不到 120ms 的松开，所以整段凑不成一次合法搓射 —— 即使删掉布局门，200 帧断言仍然是 0 条 Outcome。这条断言当时只能被 `rt_layout_gate_blocks` 兜住。
- **Fix:** 在噪声上叠加一条干净的 500ms 两下（100ms 第一下、600ms 第二下，中间强制只按 RB）。
- **Files modified:** mobile/tests/unit/test_tap_runtime.gd
- **Verification:** 删除早退后 200 帧断言与 `rt_layout_gate_blocks` 同时变红（7 处差异）；恢复后 `mismatches=0`。
- **Committed in:** `ea99cad`

**3. [Rule 2 - 加强] 闸门反例的还原证明改用 sha256**
- **Found during:** Task 2 编写第 5 条反例
- **Issue:** 计划要求反例后 `git status --porcelain mobile/tests/fixtures/` 为空。但该反例必须能在「夹具刚改过、还没提交」的工作区里正确判定；那时 `git status` 本来就有 ` M`，无法区分「没还原」与「已修改」。
- **Fix:** 脚本内改为比较移动前后的 `shasum -a 256`（更强：逐字节相同），并保留 `restore_fixture` 在 `trap ... EXIT` 上。验收要求的 `git status` 判据在提交后另行验证为空。
- **Files modified:** mobile/tools/test-core-selftest.sh
- **Verification:** `SELFTEST_OK cases=6`；提交后 `git status --porcelain mobile/tests/fixtures/` 为空。
- **Committed in:** `14f4680`

**4. [Rule 2 - 边界] 额外提交 `test_tap_runtime.gd.uid`**
- **Found during:** Task 2 首次 `--import`
- **Issue:** `files_modified` 未列测试脚本的边车，但 Phase 2 的既有约定是 `*.gd.uid` 是提交物、不进 `.gitignore`；漏提交会让工作区长期带一个未跟踪文件。
- **Fix:** 随 Task 2 一并提交。
- **Files modified:** mobile/tests/unit/test_tap_runtime.gd.uid
- **Verification:** `git ls-files --error-unmatch mobile/tests/unit/test_tap_runtime.gd.uid` 成立。
- **Committed in:** `14f4680`

**5. [Rule 3 - 计划字面] 套件用 `ConfigLoader.parse_bytes` 而非分别调 `decode_bytes` + `ConfigValidator.validate`**
- **Found during:** Task 2 编写 `_load_config`
- **Issue:** 计划写的是 `FileAccess.get_file_as_bytes` → `ConfigLoader.decode_bytes` → `ConfigValidator.validate`；而 `parse_bytes` 的函数体就是这两步的组合（`config_loader.gd:20-23`），04-01 的回放套件也走这条入口。
- **Fix:** 用 `parse_bytes`，并在套件注释里写明它等价于计划写的两步，避免下一个读者以为是两条不同的路径。
- **Files modified:** mobile/tests/unit/test_tap_runtime.gd
- **Verification:** `TAP_GOLDEN_RUNTIME cases=6 mismatches=0`。
- **Committed in:** `14f4680`

**6. [Rule 2 - 文档] `gen_tap_golden.py --check` 的汇总行分列两类条数**
- **Found during:** Task 2 加 runtime 用例后
- **Issue:** 原汇总行写「detector {len(cases)} 条」，夹具涨到 18 条后会变成「detector 18 条」这种错话。
- **Fix:** 分别统计并打印 `detector 12 条、runtime 6 条`。
- **Files modified:** tools/gen_tap_golden.py
- **Verification:** `python3 tools/gen_tap_golden.py --check` 打印 `（detector 12 条、runtime 6 条）`。
- **Committed in:** `14f4680`

### 环境差异（不是计划分歧）

- 本环境没有 `gsd_run` 命令，Step 0 的 protected-branch 查询无法执行。按 orchestrator 的 `<sequential_execution>`「在 main 工作树上顺序执行」与 `.planning/config.json` 的 `git.branching_strategy: none`，在 `main` 上用普通提交（带 hooks，未用 `--no-verify`）。未做任何 `git update-ref` 之类的自愈操作。

---

**Total deviations:** 6（1 个真实 bug、4 个加强/边界、1 处计划字面等价替换）+ 1 条环境说明
**Impact on plan:** 无断言被削弱。两处加强都是变异验证发现的真空绿，修好后反向变异各只红对应那一条（删锁 → `rt_gesture_lock` / `rt_release_hold_rearm`；删门 → 200 帧断言 + `rt_layout_gate_blocks`；逐动作冷却加 suppressed → 只红 `_check_skill_cooldown_silent`；全局冷却去 suppressed → 只红 `_check_global_cooldown_counts`）。

## Issues Encountered

- 第一次跑套件时 4 条失败都指向「第二发没命中」；根因是稀疏帧（见 Deviation 1），不是运行时逻辑。修复后夹具回放一次通过。
- Godot 仍偶发打印 `Unicode parsing error ... Invalid UTF-8 leading byte (ff/fe)`；既有导入噪声，`--import` 本次一次成功，测试不受影响。
- `rt_gesture_lock` 的「锁被写漏」推导在实现里得到验证：删锁后 700ms 确实多出一条 `too_fast`（间隔 20ms），与计划预测一致。

## User Setup Required

None - no external service configuration required. 本计划未安装任何依赖，`shared/skills_config.json` 未改动（`git diff --stat` 为空）。

## Next Phase Readiness

- `TapRuntime.pop_outcomes()` / `layout_confirmed` / `set_layout_confirmed()` 已就位，04-05 的引导状态机与 04-06 的练习屏可以直接消费；UI 只需每帧 drain 一次队列。
- `select_taps_skill()` 是「只练绿色搓射」的唯一实现点，04-06 的组合根必须复用它，不得另写筛选循环。
- 成功标准 5 的结构半边闭合（一次一条、两次两条、冷却吞掉、重新武装）；剩余半边（帧内反转的事件捕获与真机时间戳直方图）在 04-04 与 04-07。
- 成功标准 4 的运行时半边闭合（未确认布局零判定）；布局建议表与按键确认页在 04-03 / 04-05，INPUT-04 届时才可宣布完成。
- Phase 5 必须还原 `TapRuntime` 类文档里记录的三处范围收缩（手势锁按 `rs_mag` 计时、`idle_reset_ms` 计时器、`relative_to_ls` 的 `facing` 基准）。
- 真机相关风险不变：安卓 60–125 Hz 的到达间隔分布、`set_use_accumulated_input(false)` 的亚帧时间戳仍未实测（见 STATE.md Blockers）。

---

*Phase: 04-device-input-green-slice*
*Completed: 2026-11-05*

## Self-Check: PASSED

- 6 个新建文件全部存在（含 3 个 `.gd.uid` 边车）
- 4 个提交 `0b1db24` / `14f4680` / `91f560b` / `ea99cad` 均为 HEAD 祖先
- `TAP_GOLDEN_RUNTIME cases=6 mismatches=0` / `TAP_GOLDEN_DETECTOR cases=12 mismatches=0` / `TESTS_DONE failures=0` / `SELFTEST_OK cases=6` 均为本次运行实测
