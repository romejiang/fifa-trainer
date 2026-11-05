---
phase: 05-judge-parity-decimation
plan: 01
subsystem: core-detectors
tags:
  [
    gdscript,
    godot,
    arc-detector,
    sequence-detector,
    detector-factory,
    golden-fixture,
    python-parity,
    direction-names,
  ]

requires:
  - phase: 04-device-input-green-slice
    plan: 01
    provides: `Frame`（now 秒 + buttons 字典）、`Hit` / `Failure`、`Detector` 基类、`TapDetector`
  - phase: 04-device-input-green-slice
    plan: 02
    provides: tap 黄金夹具的生成器形态（源哈希 / 规范字节 / `--check` 只读）与回放套件骨架
  - phase: 03-core-foundation
    plan: 03
    provides: `Skill` / `Step` / `AppConfig` / `DirectionTable.resolve`
  - phase: 03-core-foundation
    plan: 04
    provides: `ConfigValidator.validate` → `ConfigResult`，回放套件用它重建 AppConfig
  - phase: 03-core-foundation
    plan: 01
    provides: 无头 runner + `TESTS_DONE failures=0` 哨兵 + `test-core.sh` 唯一入口

provides:
  - "tools/gen_gesture_golden.py：源哈希四文件 / `configs` 注册表 / 规范字节 / 只读 `--check` / `_assert_not_rounding_cliff`"
  - "mobile/tests/fixtures/gesture_golden.json：10 条用例（5 成功 + 5 失败码），全部由 Python 参考跑出"
  - "mobile/src/core/detectors/arc_detector.gd：`ArcDetector` 完整移植（含六个 abort 分支与 measured / last_path）"
  - "mobile/src/core/detectors/sequence_detector.gd：`SequenceDetector` 完整移植（13 分支顺序）"
  - "mobile/src/core/detectors/build_detector.gd：`DetectorFactory` 按 `skill.kind` 分派"
  - "mobile/src/core/frame.gd：+rs_mag / rs_angle / ls_mag / ls_angle / facing，全部默认 0.0"
  - "mobile/src/core/domain/direction_table.gd：`direction_name()` 八向 + 22.5° 平局规则"
  - "mobile/src/core/domain/step.gd：`Step.label()` 多方向用 `/` 连接"
  - "mobile/tests/unit/test_gesture_detector.gd：回放 + 三条按 kind 的工厂点名检查 + `GESTURE_GOLDEN` 哨兵"
  - "mobile/tools/test-core.sh：生成器校验 + `GESTURE_GOLDEN cases=N mismatches=0` 正向哨兵"

affects:
  [05-02-corpus-variants, 05-03-gesture-engine, 05-04-measured, phase-6-training-loop, phase-7-feedback]

actuals:
  tokens: 71738
  tasks: 3
  commits: 3

plan_head_before: e4e13db33e48534710a4872e428e3e4bb00446a2
plan_head_after: f75d51624d160db9c04b472403d0a7d3d1d8c6fb

tech-stack:
  added: []
  patterns:
    - "期望值唯一来源：生成器 import `desktop/padskills` 跑参考实现，夹具是生成物，`--check` 逐字节比较且绝不写盘"
    - "夹具 `configs` 注册表是唯一配置来源：每个用例只认 `configs[case.config]`，套件不读 `res://assets/config/`"
    - "检测器分派按 `skill.kind`：生成器断言 `build_detector()` 的类名，套件走 `DetectorFactory.build()` 且三条点名检查覆盖三类"
    - "`_assert_not_rounding_cliff` 在 `update()` 之前预演会被 `%.0f` 格式化的 swept / end_rel，拒绝 .5 刀口"
    - "失败码只写数学可达的配置：油炸丸子不写 too_fast；overshoot / wrong_direction 留给变体配置"
    - "夹具的 `facing` 是引擎状态：生成器按引擎规则推导后逐帧断言 `abs(engine.facing - declared) < 1e-9`"

key-files:
  created:
    - tools/gen_gesture_golden.py
    - mobile/tests/fixtures/gesture_golden.json
    - mobile/src/core/detectors/arc_detector.gd
    - mobile/src/core/detectors/arc_detector.gd.uid
    - mobile/src/core/detectors/sequence_detector.gd
    - mobile/src/core/detectors/sequence_detector.gd.uid
    - mobile/src/core/detectors/build_detector.gd
    - mobile/src/core/detectors/build_detector.gd.uid
    - mobile/tests/unit/test_gesture_detector.gd
    - mobile/tests/unit/test_gesture_detector.gd.uid
  modified:
    - mobile/src/core/frame.gd
    - mobile/src/core/domain/direction_table.gd
    - mobile/src/core/domain/step.gd
    - mobile/tests/core_runner.gd
    - mobile/tests/unit/test_vocabulary.gd
    - mobile/tools/test-core.sh

key-decisions:
  - "夹具路径裁决：ROADMAP 成功标准 1 写 `shared/golden_vectors.json`，实际用 `mobile/tests/fixtures/gesture_golden.json` —— 唯一消费者是 Godot，`shared/` 在 `res://` 之外读不到"
  - "`configs` 注册表存**完整**配置对象（不是 diff），用例用 `config` 键引用；生成器用 `is` 身份比较确认回放的就是产出 expect 的那一份"
  - "六个 abort 分支顺序（wrong_start → wrong_direction → overshoot → stalled → too_slow → too_fast）逐字照抄：顺序只影响报哪条原因，但那就是用户看到的反馈"
  - "`_release_failure()` 只在 `swept >= report_min_angle` 时被调用；太小的抖动整条静默"
  - "`Frame` 的五个新字段全部默认 0.0，Phase 4 的 1533 条断言零改动（最终 1669 = 1533 + 136）"
  - "`direction_name()` 的数字回落分支在参考实现里不可达（八向间隔 45°，最近卡点恒 ≤ 22.5°），保留为死分支以维持逐行对等"
  - "踩单车成功用例的扫掠时长从 400ms 改成 500ms：0.9°/帧会让 swept 在 4.5° 处撞上 `%.0f` 刀口"
  - "磕球过人的 250ms `idle_timeout` 与 250ms `min_duration` 只留一帧窗口（446~450ms）；448ms 是两个判据各留 2ms 余量的唯一选择"

requirements-completed: [JUDGE-01, JUDGE-02, JUDGE-03, JUDGE-04]

coverage:
  - id: D1
    description: "Python 参考 → 生成夹具 → GDScript 回放 → 哨兵 → 闸门的端到端链路"
    requirement: JUDGE-03
    verification:
      - kind: integration
        ref: "bash mobile/tools/test-core.sh#GESTURE_GOLDEN cases=10 mismatches=0"
        status: pass
      - kind: automated_ui
        ref: "python3 tools/gen_gesture_golden.py --check"
        status: pass
    human_judgment: false
  - id: D2
    description: "5 个 shipped 动作各一条 250 Hz 成功用例，逐字段与 Python 参考一致"
    requirement: JUDGE-01
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_gesture_detector.gd#det_roulette_ok..det_green_finesse_ok"
        status: pass
    human_judgment: false
  - id: D3
    description: "五个失败码各一条正确归因：too_fast / too_slow / wrong_start / wrong_end / hold_short"
    requirement: JUDGE-04
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_gesture_detector.gd#det_roulette_too_fast..det_croqueta_hold_short"
        status: pass
    human_judgment: false
  - id: D4
    description: "检测器按 skill.kind 分派：arc / sequence / taps 三类各被点名检查覆盖"
    requirement: JUDGE-01
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_gesture_detector.gd#_check_factory_arc/_check_factory_sequence/_check_factory_taps"
        status: pass
    human_judgment: false
  - id: D5
    description: "方向文案与参考实现逐字一致：DirectionTable.direction_name + Step.label"
    requirement: JUDGE-02
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_vocabulary.gd#_check_direction_names"
        status: pass
    human_judgment: false
  - id: D6
    description: "桌面参考零改动，302 项检查全绿"
    requirement: JUDGE-01
    verification:
      - kind: integration
        ref: "bash tools/check_desktop.sh && git status --porcelain -- desktop"
        status: pass
    human_judgment: false

duration: 14min
completed: 2026-11-06
status: complete
---

# Phase 5 Plan 01: 全动作判定对等性 — 弧线/序列切片与黄金回放 Summary

**一条由 Python 参考实现驱动的生成夹具，把 5 个动作的成功路径与 5 个失败码的归因逐字段证死在 GDScript 侧，并接进 `test-core.sh` 的机械闸门。**

## Performance

- **Duration:** 14 min
- **Started:** 2026-11-05T18:04:21Z
- **Completed:** 2026-11-05T18:18:11Z
- **Tasks:** 3
- **Files modified:** 16（10 新建 / 6 修改）

## 基线冻结（开工前实测，D-02）

| 命令 | 结果 |
|------|------|
| `bash tools/check_desktop.sh` | `✓ 302 项检查全部通过，名称与基线逐项一致`（通过 97 / 失败 0） |
| `bash mobile/tools/test-core.sh` | `TESTS_SUITES=18`、`TESTS_ASSERTIONS=1533`、`TESTS_DONE failures=0` |
| `python3 tools/gen_tap_golden.py --check` | `✓ tap 黄金夹具与 Python 参考一致（detector 12 条、runtime 6 条）` |
| `python3 tools/lint_core_purity.py mobile/src/core` | `LINT_OK files=28` |

三个数字与阶段开工前完全一致，未出现「基线本身已经漂移」的情况。

## 路径裁决

ROADMAP 的成功标准 1 写的是 `shared/golden_vectors.json`；本计划实际使用
`mobile/tests/fixtures/gesture_golden.json`。

理由：夹具的**唯一消费者**是 Godot 回放套件，而 `shared/` 在 `res://` 之外，运行期
读不到；若放 `shared/`，要么给 Godot 再造一份同步副本（第二份会漂移的真源），要么在
`test-core.sh` 里复制文件。沿用 `tools/gen_geometry_golden.py:11-14` 与
`gen_tap_golden.py` 已写过的裁定：**夹具放唯一消费者旁边，生成器以脚本位置为锚读
仓库根**。ROADMAP 的路径是排序阶段的占位名，实质要求是「由 Python 侧生成、0 差异」，
这一点未变。

## Accomplishments

- **期望值的唯一来源变成机械事实**：`tools/gen_gesture_golden.py` import `desktop/padskills`
  跑参考实现，把 `detectors.py` / `engine.py` / `config.py` / `shared/skills_config.json`
  四个 SHA-256 写进夹具；`--check` 逐字节比较且绝不写盘，`test-core.sh` 在 Godot 之前跑它。
- **5 个动作的成功路径全部逐字段对齐**：马赛回旋、踩单车、磕球过人、油炸丸子、绿色搓射；
  每条用例的 `skill` / `ok` / `code` / `message` / `elapsed_ms` / `at` / `detail` 都由参考实现跑出。
- **五个失败码各一条正确归因**：`too_fast`（马赛 128ms 转到位）、`too_slow`（马赛 604ms 超上限）、
  `wrong_start`（踩单车从相对 60° 起手）、`wrong_end`（马赛停在 264°）、`hold_short`（油炸丸子
  保持 196ms 后松 LB）。
- **检测器分派按 `skill.kind`，不是按名字**：生成器断言 `build_detector()` 返回的类名，
  GDScript 侧 `DetectorFactory.build()` + 三条点名检查（2 arc / 2 sequence / 1 taps）覆盖三类。
- **夹具 `configs` 注册表**让后续变体 / 合成用例可回放：每个用例只认
  `configs[case.config]`，回放套件不读 `res://assets/config/` 的出厂副本；生成器用 `is`
  身份比较确认回放的就是产出 expect 的那一份。
- **桌面参考零改动**：`git status --porcelain -- desktop` 为空，302 项检查保持全绿。

## Task Commits

每个任务原子提交：

1. **Task 1: 端到端一条弧线 —— Python 参考 → 生成夹具 → GDScript 回放 → 哨兵** - `2d0a9b3` (feat)
2. **Task 2: SequenceDetector + 方向文案 + 工厂补全，5 个动作各一条成功用例** - `02043e8` (feat)
3. **Task 3: 弧线六个 abort 分支 + 五个失败码各一条用例（累计 10 条）** - `f75d516` (feat)

**Plan metadata:** 本次 SUMMARY 提交（docs: complete plan）

## Files Created/Modified

- `tools/gen_gesture_golden.py` - 手势黄金夹具生成器：源哈希 / `configs` 注册表 / 规范字节 / 只读 `--check` / 取整刀口守卫
- `mobile/tests/fixtures/gesture_golden.json` - 生成物，10 条用例 + 完整 `shipped` 配置
- `mobile/src/core/frame.gd` - +5 字段（`rs_mag` / `rs_angle` / `ls_mag` / `ls_angle` / `facing`），全部默认 0.0
- `mobile/src/core/detectors/arc_detector.gd` - `ArcDetector`：起手、累计、六个 abort、松手两种失败、成功；`measured()` / `last_path()`
- `mobile/src/core/detectors/sequence_detector.gd` - `SequenceDetector`：13 分支顺序、hold 累计、`_abandon_failure` 优先级、`reset()` 不动 `neutral`
- `mobile/src/core/detectors/build_detector.gd` - `DetectorFactory`：`match skill.kind` 三类分派，未知返回 null
- `mobile/src/core/domain/direction_table.gd` - `CARDINAL_NAMES` + `direction_name()`（八向、22.5° 平局、数字回落）
- `mobile/src/core/domain/step.gd` - `label()`：多方向步用 `/` 连接
- `mobile/tests/unit/test_gesture_detector.gd` - 回放套件 + 三条工厂点名检查 + `GESTURE_GOLDEN` 哨兵
- `mobile/tests/unit/test_vocabulary.gd` - `direction_name` 八向 / 22.5° / 22.6° / 30° / `label()` 断言
- `mobile/tests/core_runner.gd` - 注册 `gesture_detector` 套件（显式 preload）
- `mobile/tools/test-core.sh` - `gen_gesture_golden.py --check` + `GESTURE_GOLDEN cases=N mismatches=0` grep
- 四个 `.gd.uid` 边车 - `--import` 生成，随对应 `.gd` 一并提交

## Decisions Made

- **夹具放 `mobile/tests/fixtures/`**：见「路径裁决」。
- **`configs` 注册表存完整配置对象**：变体 / 合成用例不能被静默按出厂阈值回放，否则
  `mismatches=0` 只是「与出厂副本一致」。生成器用 `is` 而非 `==` 比较 AppConfig 身份。
- **生成器驱动检测器走 `build_detector(skill)` 并断言类名**：四个非弧线成功用例若被
  `ArcDetector` 回放，期望会变成空或错值，而「一条弧线用例」完全看不出这个错误。
- **`_assert_not_rounding_cliff` 在 `update()` 之前预演**：release 路径会在格式化后把
  `acc` 清零，事后读不到被格式化的 `swept`，所以按参考实现的两条分支预演。
- **失败码只写数学可达的配置**：油炸丸子的 `too_fast` 恒不成立（要满足 hold 350 才轮到
  `elapsed < min 250`），语料里不出现；`overshoot` / `wrong_direction` 出厂配置不可达，
  留给计划 02 的变体用例。
- **`Frame` 五字段默认 0.0**：Phase 4 的 `Frame.new()` + 只赋 `now` / `buttons` 的写法零改动。

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - 计划文字与参考实现冲突] `direction_name(30)` 不是 `30°`，而是 `前右`**

- **Found during:** Task 2（方向文案）
- **Issue:** 计划的 `<behavior>` 写「`30` → `30°`（超出 22.5 回落为数字）」。参考实现
  `config.py:144-149` 先取**最近的**卡点再判距离：八个正/斜向间隔 45°，任何角度到最近
  卡点的距离都 ≤ 22.5°，所以 `diff <= 22.5` 恒成立，数字回落分支**数学上不可达**。
  30° 距 45° 只有 15°，参考实现返回「前右」。
- **Fix:** 按参考实现（唯一规格书）钉死 `30 → 前右`，并在 `test_vocabulary.gd` 与
  `direction_table.gd` 的注释里写明「数字回落是死分支，保留纯粹为了逐行对等」。
  没有为了让计划文字成立而放宽阈值或改写 `direction_name`。
- **Files modified:** `mobile/src/core/domain/direction_table.gd`,
  `mobile/tests/unit/test_vocabulary.gd`
- **Verification:** `test_vocabulary` 全绿；`direction_name` 与 Python 的八向 + 平局规则逐条一致。
- **Committed in:** `02043e8`（Task 2 提交）

**2. [Rule 1 - Bug] 踩单车成功用例的扫掠时长 400ms → 500ms，避开 `%.0f` 取整刀口**

- **Found during:** Task 2（新增 `det_stepover_ok`）
- **Issue:** 90° / 400ms = 0.9°/帧，`swept` 在第 5 帧正好是 4.5°；生成器的
  `_assert_not_rounding_cliff` 拒绝该值（Python 与 GDScript 的 1 ulp 差异会让
  `%.0f` 翻一位）。该值虽然不在终结路径上，但守卫刻意在每一帧预演，属于语料约束。
- **Fix:** 改成 90° / 500ms = 0.72°/帧。0.72k 的取整余数只可能是
  `.00/.72/.44/.16/.88/.60/.32/.04`，永远不会落在 `.5` 上；语义仍是「起手 0°、扫向 90°」。
- **Files modified:** `tools/gen_gesture_golden.py`, `mobile/tests/fixtures/gesture_golden.json`
- **Verification:** `gen_gesture_golden.py --check` 通过；`det_stepover_ok` 在 392ms 命中，逐字段一致。
- **Committed in:** `02043e8`（Task 2 提交）

**3. [Rule 3 - Blocking] `variant()` 返回配置字典而不是 AppConfig**

- **Found during:** Task 1（生成器骨架）
- **Issue:** 计划写「`variant(...)`：深拷贝 ... 再 `parse_config`」。但 `configs` 注册表
  存的是**原始配置对象**（回放套件要把它交给 `ConfigValidator.validate`），返回
  AppConfig 会让注册表里出现两种形态。
- **Fix:** `variant()` 返回深拷贝后的字典，并在返回前用 `parse_config` 自检一次
  （失败即 `SystemExit`）。解析后的 AppConfig 由 `build_payload()` 统一构建并缓存。
- **Files modified:** `tools/gen_gesture_golden.py`
- **Verification:** `_assert_configs_replayable` 逐键重解析 + `is` 身份比较通过。
- **Committed in:** `2d0a9b3`（Task 1 提交）

---

**Total deviations:** 3 auto-fixed（2 Rule 1、1 Rule 3）
**Impact on plan:** 全部是「让实现与参考实现/生成器不变量一致」的修正，无范围扩张；
`desktop/` 与 `shared/` 零改动。

## Issues Encountered

- **马赛回旋的成功在 252ms 就发生，而不是 500ms 扫完**：参考实现的成功条件是
  「swept 在区间内 **且** 当前终点在目标 ± 容差内」，而终点目标 `0±80°` 的窗口在
  相对 280° 就开始。180°→20° 的轨迹转到 280.8° 时两者同时成立，于是提前命中。
  这是参考实现的真实行为，期望值由它跑出；用例注释里写明了这一点，没有为了让
  「看起来更像完整一圈」而改轨迹。
- **磕球过人的窗口只有一帧**：`idle_timeout_ms` 与 `min_duration_ms` 都是 250，
  第二步必须落在「自 t0 起 ≥250ms」且「自松手起 ≤250ms」的交集里。第一步按住
  100ms、第二步在 448ms，两个判据各留 2ms 余量。这是配置本身的约束，不是移植偏差。
- Godot `--import` 两次都一次成功（未撞上 macOS arm64 的 NotoSansSC 偶发 SIGSEGV）。

## Known Stubs

无。`measured()` 已在 `ArcDetector` 内部构造（`kind` / 起终点角度 / swept / elapsed /
samples / direction_sign / target），但按计划边界**不**挂到 `Hit` / `Failure` ——
字段扩展由计划 04 与 `Outcome.measured` 一起完成，不属于本计划的缺口。

## Threat Flags

无新增信任面：本计划只读 `desktop/padskills/*.py` 与 `shared/skills_config.json`，
新增代码全部在 `mobile/src/core/`（零 I/O、零时钟）与 `tools/`（只读参考实现）。

## User Setup Required

None - 无外部服务或环境变量。

## Next Phase Readiness

- 生成器骨架、`configs` 注册表与哨兵已就位：后续语料扩展只需往 `CASES` 加条目、
  往 `config_dicts` 注册变体，不需要改骨架。
- `DetectorFactory` 已是唯一构造入口，计划 03 的 `GestureEngine` 直接复用。
- `Frame` 的五字段契约（`now` / `buttons` / `rs_mag` / `rs_angle` / `facing`）已冻结，
  `ls_mag` / `ls_angle` 只给引擎算 `facing`。
- 闸门现状：`TESTS_SUITES=19`、`TESTS_ASSERTIONS=1669`、`TESTS_DONE failures=0`、
  `GESTURE_GOLDEN cases=10 mismatches=0`、`LINT_OK files=31`、desktop 302/302。

## Self-Check: PASSED

- 16 个文件全部存在于工作树，10 个新建文件已入库。
- 三个任务提交均可在 `git log` 中定位：`2d0a9b3` / `02043e8` / `f75d516`。
- 测得提交数：`git rev-list --count e4e13db..HEAD` = 3。
