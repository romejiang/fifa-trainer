---
phase: 04-device-input-green-slice
plan: 01
subsystem: core-detectors
tags: [gdscript, godot, tap-detector, golden-fixture, python-parity, no-engine-lint]

requires:
  - phase: 03-core-foundation
    plan: 01
    provides: 无头 runner、`TESTS_DONE failures=0` 完成哨兵、`test-core.sh` 唯一入口
  - phase: 03-core-foundation
    plan: 02
    provides: `lint_core_purity.py` 的 14 条架构规则与 `CORE.md` 的零引擎依赖边界
  - phase: 03-core-foundation
    plan: 03
    provides: `Skill` / `Buttons` 域对象与 17 个规范按键名
  - phase: 03-core-foundation
    plan: 04
    provides: `ConfigLoader.parse_bytes` / `ConfigResult`（回放套件用它读真实配置副本）
  - phase: 02-android-toolchain
    provides: Godot 4.7.2-stable 与 `*.gd.uid` 提交约定

provides:
  - "mobile/src/core/frame.gd：`now`（秒）+ `buttons`（canonical 名 → true 的 Dictionary）"
  - "mobile/src/core/hit.gd / failure.gd：检测器与引擎共用的判定值对象"
  - "mobile/src/core/detectors/detector.gd：7 方法基类 + 10 条 FAILURE_LABELS + 单槽 `_pending`"
  - "mobile/src/core/detectors/tap_detector.gd：TapDetector 逐行移植（九步判定顺序、reset vs abandon、set_modifier）"
  - "tools/gen_tap_golden.py：直接跑 desktop 参考实现生成夹具，`--check` 逐字节比对"
  - "mobile/tests/fixtures/tap_golden.json：12 条 detector 用例、逐帧全量 250 Hz 时间轴"
  - "mobile/tests/unit/test_tap_detector.gd：引擎分支回放 + 规模/id/网格/abandon 结构断言"
  - "mobile/tools/test-core.sh：tap 夹具未漂移检查 + `TAP_GOLDEN_DETECTOR` 正向哨兵"

affects: [04-02-tap-runtime, phase-5-detectors, phase-6-training-loop, phase-7-feedback]

actuals:
  tokens: 40215
  tasks: 2
  commits: 2

plan_head_before: c02f4d0e45e5b539cd76a91060c5271d1114d9c9
plan_head_after: 26e565606711e38c42aae3acc3a600842e285150

tech-stack:
  added: []
  patterns:
    - "Python 生成夹具 → GDScript 回放：期望值只能来自跑参考实现，禁止手写"
    - "按引擎分支回放：修饰键不满足时 observe() 然后 reset()，顺序不能反"
    - "状态成对表示：`_have_t0` + `_t0`、`_have_release_since` + `_release_since`，禁止 -1.0 哨兵"
    - "单槽覆盖写失败：`_emit()` 覆盖 `_pending`，`pop_failure()` 取出并清空"
    - "闸门只加强：既有 TESTS_DONE / TESTS_ASSERTIONS 判据一字未放宽，新增正向哨兵"

key-files:
  created:
    - mobile/src/core/frame.gd
    - mobile/src/core/frame.gd.uid
    - mobile/src/core/hit.gd
    - mobile/src/core/hit.gd.uid
    - mobile/src/core/failure.gd
    - mobile/src/core/failure.gd.uid
    - mobile/src/core/detectors/detector.gd
    - mobile/src/core/detectors/detector.gd.uid
    - mobile/src/core/detectors/tap_detector.gd
    - mobile/src/core/detectors/tap_detector.gd.uid
    - tools/gen_tap_golden.py
    - mobile/tests/fixtures/tap_golden.json
    - mobile/tests/unit/test_tap_detector.gd
    - mobile/tests/unit/test_tap_detector.gd.uid
  modified:
    - mobile/tests/core_runner.gd
    - mobile/tools/test-core.sh

key-decisions:
  - "`Frame.now` 用秒：与参考实现 `(now - t0) * 1000.0` 逐字一致；毫秒只用于 `_ms` 后缀的时长字段"
  - "`Frame.buttons` 用 Dictionary：参考实现是 frozenset，逐帧 `has()` 必须 O(1)，全仓只此一种表示"
  - "`on_idle()` 在 TapDetector 是 no-op：右摇杆静止与按键动作无关，基类默认 reset 必须覆盖掉"
  - "`reset()` 产 hold_short、`abandon()` 静默：两者不可合并；abandon 最后一行同样按 `_prev_pressed` 重算 `_armed`"
  - "用例结束不 reset：否则 det_too_slow_boundary_750 会凭空多出一条 hold_short"
  - "`set_modifier()` 在生成器与回放两侧都在首帧之前调用，验证的是真实分支而不是改 required 的旁路"
  - "回放套件从真实配置副本读窗口/宽限/松开时长，不写第二份常量；夹具与配置漂移时比对必红"

patterns-established:
  - "Pattern 1：生成物夹具 —— `--check` 重新推导后逐字节比较，手改即红，且绝不写盘"
  - "Pattern 2：跨语言回放必须复刻引擎调用顺序（observe→reset / update），否则验证的不是同一条分支"
  - "Pattern 3：正向哨兵带实际条数与差异数（`cases=N mismatches=0`），零用例无法真空绿"
  - "Pattern 4：结构断言不依赖夹具（`_check_abandon_silent`），防止「夹具与实现一起错」"

requirements-completed: []

# INPUT-05 在本计划**不宣布完成**：本计划只交付消费者端的输入契约
# （Frame.now 秒 + buttons 字典）与 tap 判定对等；「事件捕获不丢帧内反转」的
# 机械证明在 04-04（见本计划 Flagged Assumptions 与 ROADMAP 成功标准 5）。

coverage:
  - id: D1
    description: "TapDetector 逐行移植：九步判定顺序、窗口两端包含、超时严格大于、reset/abandon 不可合并、set_modifier 生效"
    verification:
      - kind: unit
        ref: "bash mobile/tools/test-core.sh#TAP_GOLDEN_DETECTOR cases=12 mismatches=0"
        status: pass
    human_judgment: false
  - id: D2
    description: "夹具由 Python 参考实现生成，缺失或手改时 `--check` 非零退出且绝不写盘"
    verification:
      - kind: unit
        ref: "python3 tools/gen_tap_golden.py --check"
        status: pass
    human_judgment: false
  - id: D3
    description: "12 条 detector 用例覆盖 400/600 边界、too_fast、第二下 too_slow、超时 752、边界 748 沉默、hold_short、换修饰键、首帧守卫、重新武装"
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_tap_detector.gd（REQUIRED_DETECTOR_IDS 12 条 + 唯一 id + 4ms 网格断言）"
        status: pass
    human_judgment: false
  - id: D4
    description: "五个新 class_name 全部在 mobile/src/core/ 且零引擎依赖；`.gd.uid` 边车已提交"
    verification:
      - kind: unit
        ref: "python3 tools/lint_core_purity.py mobile/src/core → LINT_OK files=20"
        status: pass
    human_judgment: false
  - id: D5
    description: "闸门加强：tap 夹具未漂移检查排在 Godot 导入之前，`TAP_GOLDEN_DETECTOR cases=N mismatches=0` 作为正向哨兵；既有判据未放宽"
    verification:
      - kind: integration
        ref: "bash mobile/tools/test-core.sh（TESTS_SUITES=9 / TESTS_ASSERTIONS=680 / TESTS_DONE failures=0）"
        status: pass
    human_judgment: false

duration: 5min
completed: 2026-11-05
status: complete
---

# Phase 4 Plan 01: Tap 检测器逐行移植 + Python 生成黄金夹具 Summary

**绿色搓射的 tap 判定从 Python 参考实现一路走到 GDScript：12 条 250 Hz 时间轴由生成器直接跑 `desktop/padskills/detectors.py` 得出，无头回放 `cases=12 mismatches=0`，`--check` 让手改夹具当场变红**

## Performance

- **Duration:** 5 min
- **Started:** 2026-11-05T09:18:58Z
- **Completed:** 2026-11-05T09:24:50Z
- **Tasks:** 2
- **Files modified:** 16（14 新建、2 修改）

## Accomplishments

- 五个纯 core 类落地：`Frame`（只有 `now` 秒与 `buttons` 字典）、`Hit`、`Failure`、`Detector` 基类、`TapDetector`。`TapDetector` 按 `detectors.py:949-1026` 的九步顺序实现，`on_idle()` 是空实现，`reset()` 产 `hold_short`，`abandon()` 静默且按 `_prev_pressed` 重算 `_armed`。
- `tools/gen_tap_golden.py` 结构照抄 `gen_geometry_golden.py`：路径以脚本位置锚定、`sys.path` 注入 `desktop/`、从 `shared/skills_config.json` 真源解析 Skill、逐帧按引擎分支驱动参考实现、`json.dumps(..., sort_keys=True)` 逐字节可比、`--check` 缺失或不同都返回 1 且绝不写盘。
- 夹具 `tap_golden.json` 含 12 条 detector 用例（逐帧全量 250 Hz），`source.sha256` 覆盖 `detectors.py` / `engine.py` / `config.py` / `skills_config.json` 四份摘要，为 04-02 的 runtime 用例预留同一 schema。
- 回放套件 `test_tap_detector.gd` 只消费 `kind == "detector"`，按同一引擎分支驱动，逐字比对 `elapsed_ms` / `summary` / `detail` / `code` / `message`，并打印正向哨兵；另有规模、唯一 id、12 个点名 id、4ms 网格与 `_check_abandon_silent` 结构断言。
- `test-core.sh` 只加强：几何黄金检查之后新增 tap 夹具检查（Godot 导入之前），`TESTS_DONE` / `TESTS_ASSERTIONS` 之后新增 `TAP_GOLDEN_DETECTOR` 哨兵 grep，既有判据一字未放宽。
- 全套基线保持绿：`TESTS_SUITES=9` / `TESTS_ASSERTIONS=680` / `TESTS_DONE failures=0`；`LINT_OK files=20`；`PARITY_OK cases=28 divergences=4`；`check_desktop.sh` 230/230；闸门 A 通过。

## Task Commits

1. **Task 1: 端到端「一条 250 Hz tap 时间轴：Python 生成 → GDScript 回放 → 闸门哨兵」** — `4103614` (feat)
2. **Task 2: 把 detector 用例扩到 12 条（边界、改写、守卫各一条）** — `26e5656` (feat)

**Plan metadata:** 见本次最终 docs 提交（SUMMARY / STATE / ROADMAP）

## Files Created/Modified

- `mobile/src/core/frame.gd` — `now: float`（秒）+ `buttons: Dictionary`；注释写明 Phase 5 才加摇杆字段
- `mobile/src/core/hit.gd` — `elapsed_ms` / `detail` / `summary` + 位置参数构造器
- `mobile/src/core/failure.gd` — `code: StringName` / `message` / `elapsed_ms`
- `mobile/src/core/detectors/detector.gd` — 7 方法基类、10 条 `FAILURE_LABELS`、单槽 `_pending`、`_emit` 覆盖写
- `mobile/src/core/detectors/tap_detector.gd` — 九步 `update`、`observe` 的 `_prev_pressed` 守卫、`reset` / `on_idle` / `abandon`、`set_modifier`、`status`
- `tools/gen_tap_golden.py` — 生成器 + `--check` + `--root`；时间轴用「变化点 + 结束时刻」展开
- `mobile/tests/fixtures/tap_golden.json` — 12 条用例的逐帧时间轴与 Python 期望（约 7.8k 行）
- `mobile/tests/unit/test_tap_detector.gd` — 回放 + 比对 + 规模/id/网格/abandon 断言 + 哨兵
- `mobile/tests/core_runner.gd` — `SUITES` 增至 9 条（新增 `tap_detector`）
- `mobile/tools/test-core.sh` — tap 夹具未漂移检查 + 正向哨兵 grep + 收尾文案
- 五个 core `.gd.uid` 与 `test_tap_detector.gd.uid` — Godot 4.7.2 导入生成的边车，按既有约定提交

## Decisions Made

- **`Frame.now` 用秒、时长字段用毫秒**：唯一判据是参考实现 `(now - _t0) * 1000.0` 的换算位置；`now_ms` 只出现在被否决的 RESEARCH C9 表格里。
- **`buttons` 用 Dictionary**：与 Python 的 frozenset 语义最近，逐帧 `has()` 为 O(1)；全仓只允许这一种表示。
- **状态成对表示**：`_have_t0` / `_t0` 与 `_have_release_since` / `_release_since`；`-1.0` 是合法时间戳，不能当哨兵。
- **`reset()` 与 `abandon()` 不可合并**：前者是「修饰键松了」可立刻重试、产 `hold_short`；后者是「轨迹被别的动作认领」、必须静默。`abandon()` 最后一行同样按 `_prev_pressed` 重算 `_armed`（`detectors.py:946`）。
- **`on_idle()` 空实现**：引擎在右摇杆静止时周期调用它，而绿色搓射时右摇杆通常回中；照抄基类 `reset()` 会不断作废进度。
- **用例结束不 reset**：`det_too_slow_boundary_750` 的尾巴停在 interval=748，到这里本来就该沉默；无条件 reset 会多出一条 `hold_short`。
- **`set_modifier` 走真实入口**：生成器与回放都在首帧之前调用 `set_modifier("RT")`，不用「改 required」或「改 case.button」旁路；否则 `det_set_modifier_rt_success` 会变成假分歧。
- **回放套件从真实配置副本读参数**：窗口/宽限/松开时长来自 `res://assets/config/skills_config.json`（`test-core.sh` 先证明它与唯一真源一致），不写第二份常量。

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - 阻塞] `elapsed_ms.is_integer()` 会因 IEEE-754 噪声拒绝合法用例，改为 1e-6 容差 + 归一**

- **Found during:** Task 1 生成首条夹具
- **Issue:** 计划要求「每个 `elapsed_ms` 必须 `float.is_integer()`，否则 `raise SystemExit`」。但 `(548/1000 - 100/1000) * 1000` 在 Python 得到 `447.99999999999994`，`450` 会得到 `450.00000000000006`；逐字调用 `is_integer()` 会把完全合法的 4ms 网格用例判死。GDScript 侧是同样的 64 位 double，浮点噪声方向也一致。
- **Fix:** `_normalize_elapsed_ms()` 改为「与最近整数相差 ≤ 1e-6」，落盘统一取 `round()`；GDScript 侧用 `eq_float(..., 1e-6, ...)` 比较，文案里的 `%.0f` 两端仍逐字相同。断言意图（必须是毫秒整数）未削弱，只是不再把二进制表示误差当成分歧。
- **Files modified:** tools/gen_tap_golden.py、mobile/tests/unit/test_tap_detector.gd
- **Verification:** `python3 tools/gen_tap_golden.py --check` 退出 0；`TAP_GOLDEN_DETECTOR cases=12 mismatches=0`。
- **Committed in:** `4103614`（生成器骨架）+ `26e5656`（12 条用例）

**2. [Rule 3 - 计划内数字不可达] 4ms 网格上取不到 450ms 与 750ms：改用 448 / 748 并保留原 id**

- **Found during:** Task 1 / Task 2 设计时间轴
- **Issue:** 计划要求 `det_success_mid_450` 与 `det_set_modifier_rt_success` 的间隔为 450ms、`det_too_slow_boundary_750` 覆盖到 interval=750。但 250 Hz / 4ms 网格上两帧时间差只能是 4 的整数倍，450 与 750 都取不到；Task 2 的验收又要求每个 `frames[i][0]` 都能被 4 整除。若强行插入 550/850 帧，会破坏「逐帧全量 250 Hz」这一前提。
- **Fix:** 保留计划里的 id（便于追溯），把 mid 用例的间隔改为网格内最近的 448（t0=100、第二下 548），把 boundary 用例的尾巴停在 748（t0=100、结束 848）。超时边界仍由 `det_too_slow_no_second` 的 752.0 证明「严格大于才报」；生成器注释写明原因。
- **Files modified:** tools/gen_tap_golden.py、mobile/tests/fixtures/tap_golden.json
- **Verification:** 夹具 `det_too_slow_boundary_750.expect.failures == []`；`det_too_slow_no_second` 唯一失败为 `too_slow` / `752.0`；mid 与 set_modifier 用例各 1 条 Hit。
- **Committed in:** `4103614`（mid 448）+ `26e5656`（boundary 748）

**3. [Rule 2 - 加强] `_check_abandon_silent` 额外证明「失败单槽被静默清掉」**

- **Found during:** Task 2 编写结构断言
- **Issue:** 计划要求的 abandon 用例从 `_t0` 已建立但 `_pending` 为空的状态出发，能证明「不产 hold_short」，但没有真正验证「已存在的失败单槽被清空」。
- **Fix:** 在同一函数里追加一段：先制造一次 `too_fast`（不 pop），再 `abandon()`，断言 `pop_failure()` 为 null；两个方向的 `_armed` 断言保持不变。
- **Files modified:** mobile/tests/unit/test_tap_detector.gd
- **Verification:** `grep -c '_armed'` ≥ 2；`TESTS_DONE failures=0`。
- **Committed in:** `26e5656`（Task 2 提交）

**4. [Rule 2 - 任务边界] 额外提交 `test_tap_detector.gd.uid`**

- **Found during:** Task 1 导入
- **Issue:** `files_modified` 只列了 5 个 core 边车，但 Godot 对测试脚本同样生成 `.uid`；Phase 2 的既有约定是「`*.gd.uid` 是提交物，不进 `.gitignore`」，漏提交会让 `--import` 后工作区长期带一个未跟踪文件。
- **Fix:** 随 Task 1 一并提交 `mobile/tests/unit/test_tap_detector.gd.uid`。
- **Files modified:** mobile/tests/unit/test_tap_detector.gd.uid
- **Verification:** `git check-ignore` 对六个边车均返回非零；`git ls-files --error-unmatch` 全部成立。
- **Committed in:** `4103614`

---

**Total deviations:** 4（2 个阻塞修正、2 个加强/边界）
**Impact on plan:** 两处数字修正都源于「4ms 网格」这一硬约束，未删减任何断言或边界覆盖；mid 用例仍覆盖窗口内部，超时边界仍由 752 的用例证明严格大于。加强项与边车提交不扩大产品范围。

## Issues Encountered

- 首次写时间轴时把结束时刻写成 558、变化点写成 550，生成器立即以 `end_ms 必须是 4ms 的整数倍` / `变化点不在 4ms 网格上` 拒绝。这正是生成器早失败设计的价值：错误在夹具落盘之前暴露，而不是等 GDScript 回放出现差异。修正后所有 12 条用例一次性通过。
- Godot 导入仍偶发打印 `Unicode parsing error ... Invalid UTF-8 leading byte (ff/fe)`；这是既有导入噪声，与本次新增文件无关，`--import` 退出码 0，测试不受影响。

## User Setup Required

None - no external service configuration required. 本计划未安装任何依赖，未修改 `shared/skills_config.json`。

## Next Phase Readiness

- `Frame` / `Hit` / `Failure` / `Detector` 四个契约对象已就位，04-02 的 `TapRuntime` 可直接复用；`TapDetector` 的 `set_modifier` / `abandon` / `pop_failure` 语义已由 12 条夹具与结构断言钉死。
- `tap_golden.json` 的 schema 已包含 `engine.py` 摘要与 `kind` 过滤器，04-02 只需追加 `kind == "runtime"` 用例，不必二次改 schema。
- 成功标准 1 的 detector 半边闭合；剩余半边（真机 250 Hz 时间轴录制、INPUT-05 的帧内反转）由 04-04 与 04-07 收口。
- 真机相关风险不变：安卓上 60–125 Hz 的到达间隔分布、`Input.set_use_accumulated_input(false)` 的亚帧时间戳仍未实测（见 STATE.md Blockers）。

---
*Phase: 04-device-input-green-slice*
*Completed: 2026-11-05*

## Self-Check: PASSED

- 8 个交付文件全部存在
- 两个任务提交 `4103614` / `26e5656` 均为 HEAD 祖先
- 6 个 `*.gd.uid` 边车全部在索引中（`git ls-files --error-unmatch` 成立）
