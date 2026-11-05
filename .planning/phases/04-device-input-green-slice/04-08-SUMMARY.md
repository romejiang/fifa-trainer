---
phase: 04-device-input-green-slice
plan: 08
subsystem: mobile-onboarding-ux-and-device-diagnostics
tags: [godot, gdscript, onboarding, ux, soft-retry, diagnostics-overlay, adb, apk, glyph-subset]

requires:
  - phase: 04-device-input-green-slice
    plan: 06
    provides: 练习屏 / 结果横幅 / %DebugPanel / 1 Hz PAD_DIAG 日志 / 15 套件 1224 断言
  - phase: 04-device-input-green-slice
    plan: 05
    provides: OnboardingFlow / 四步探针 / 校准 / 布局确认（本计划只加软重试，不动判定链）
  - phase: 04-device-input-green-slice
    plan: 07
    provides: D0 的失败原文、`run-as: package not debuggable`、用户「看不懂」的原话 —— 本计划修的就是这三件事
  - phase: 02-android-toolchain
    provides: gate-b.sh 导出链路、release keystore、apksigner 36.1.0

provides:
  - "探针屏的可见性与容错：%Hint 第一行实时读数、两次软重试、纯语言拒绝句、增量停止屏"
  - "屏上诊断覆盖层（LB+RB 0.8 s）：D1/D2 不再依赖 run-as，只需 adb exec-out screencap"
  - "test_onboarding_ui 第 16 个套件：屏幕上每句新文案都有无头断言"
  - "mobile/build/fifa-trainer.apk 重建（27,046,027 B，证书 e1841a17…32e046 不变，v2 通过，只含 arm64）"
  - "ACCEPTANCE §6 / UI-SPEC / VALIDATION 三处契约与实现对齐"

affects: [04-07-real-device-walkthrough, phase-5-detectors, phase-9-release]

actuals:
  tokens: 18758
  tasks: 5
  commits: 5

plan_head_before: 4ed673a3fa4b2565a97ed1b69bb0ddc72f62eba3
plan_head_after: 58ee924f7d3a23a71d3d0468b1931f2f663be787

tech-stack:
  added: []
  patterns:
    - "屏幕文案先抽成静态纯函数，再由测试逐句断言；渲染只负责把函数结果塞进既有 Label"
    - "软重试只对「这一下没推好」的三类原因生效，硬上限 2 次；失败文案与计数的清空点合并到 _clear_failure()"
    - "调试面复用 22 px 字号例外 + 100 字符行宽上限；超宽行会被 autowrap_mode=0 裁掉，所以行宽是取证要求"
    - "零 Outcome 的三层机械保证：组合键不含 X → 打开时 set_layout_confirmed(false) → 可见期间 _process 早退"
    - "坏档是预期路径：诊断面读原始字节、用 JSON.new().parse() 而不是 JSON.parse_string()，不删档也不往 stderr 打 ERROR"

key-files:
  created:
    - mobile/src/ui/diagnostics_overlay.gd
    - mobile/src/ui/diagnostics_overlay.tscn
    - mobile/tests/unit/test_onboarding_ui.gd
    - mobile/build/04-08-apk-report.txt（gitignored 证据）
  modified:
    - mobile/src/core/onboarding_flow.gd
    - mobile/src/ui/onboarding_screen.gd
    - mobile/src/ui/main.gd
    - mobile/tests/unit/test_onboarding_flow.gd
    - mobile/tests/core_runner.gd
    - mobile/tools/gate-a.sh
    - tools/make_font_subset.py
    - mobile/assets/fonts/required_glyphs.txt（992 → 1045 字符）
    - mobile/ACCEPTANCE.md
    - .planning/phases/04-device-input-green-slice/04-UI-SPEC.md
    - .planning/phases/04-device-input-green-slice/04-VALIDATION.md

key-decisions:
  - "保留四步探针（用户 2026-11-05 最终决定）：本计划只改引导的可见性与容错，tap_detector / tap_runtime / probe_evaluator / calibration 一行未动"
  - "软重试上限 2 次、只认 ambiguous_axes / not_enough_samples / not_enough_travel；其它码立刻硬失败，不让坏手柄看起来「只是没推好」"
  - "交叉校验失败的软重试不调用 _clear_failure()：重测那一步单独是成功的，清掉计数会让交叉失败变成无限重来"
  - "实时读数只说轴序号与正负（「轴 2 的负方向（-0.98）」），绝不说「右摇杆 X 轴」—— 轴序号只能由探针给出（INPUT-02）"
  - "停止屏只报本步增量（「本步开始后新增 N 个摇杆事件（累计 M）」），三个停止判据一字未改；旧文案与 PAD_DIAG ev_m=2633 矛盾，替换原因写进 ACCEPTANCE"
  - "诊断覆盖层读原始字节而不调 ProfileStore.load_all()：后者对损坏文件会删档，而坏档正是 D1 要拍的证据"
  - "覆盖层 22 px 是 UI-SPEC 的显式例外，正式屏不得引用；每行 ≤100 字符、每页 ≤26 行由测试逐行断言"
  - "APK 必须重建：04-07 若拿旧包重走 D0，装上去的仍是没修的版本"

patterns-established:
  - "D0 类失败的正确修法：先让用户看得见 app 收到了什么，再谈判定阈值；屏幕不是证据的替代品，但它是用户唯一的输入"
  - "真机证据通道要把「不可调试」当成事实设计，而不是当成可以绕过的问题：只读覆盖层 + screencap 比 debuggable 构建更接近验收条件"
  - "验收表里的「未执行」必须写清原因与前提（第二只手柄不可用 / 需要 debuggable 构建），不得留空也不得预打勾"

requirements-completed: []
# ONBOARD-01 / ONBOARD-02 / INPUT-04 / INPUT-05 在本计划**全部不宣布完成**：
# - ONBOARD-01 / ONBOARD-02（首启零触摸走完扩导）与 INPUT-04（布局建议 + 按键确认）
#   需要真机 D0/D3 的屏幕原文；本计划是代码计划，真机走查留给 04-07。
# - INPUT-05（一次尝试一条判定）的设备侧证据是 D4/D5；覆盖层的「零 Outcome」只是
#   机械保证，不能替代真机记录。
# 代码侧的修复已经交付并有 1335 条断言兜底，但「断言绿」不等于「真机通过」。

coverage:
  - id: D1
    description: "探针屏看得见也可改：%Hint 第一行显示「你推的是：轴 N 的正/负方向（±x.xx）」，第二行给动作句；同一步最多软重试 2 次；交叉校验失败先回到出错那一步"
    requirement: ONBOARD-01
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_onboarding_ui.gd#_check_live_readout / _check_plain_rejection / _check_cross_check_plain"
        status: pass
      - kind: unit
        ref: "mobile/tests/unit/test_onboarding_flow.gd#_check_probe_step_rejection / _check_probe_cross_validation / _check_soft_retry_resets_on_success / _check_soft_retry_code_filter"
        status: pass
    human_judgment: true
    rationale: "无头断言只能证明文案与状态机；真机上「1 m 外读得懂」与「连推三次能过」只能由 D0 的屏幕原文判读"
  - id: D2
    description: "停止屏报本步增量而不是累计总数，三个停止判据不变"
    requirement: ONBOARD-01
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_onboarding_ui.gd#_check_stop_message"
        status: pass
    human_judgment: true
    rationale: "增量的语义已断言；真机上是否再次出现停止屏只能等 04-07 重走 D0"
  - id: D3
    description: "诊断覆盖层：LB+RB 0.8 s 打开的两页只读文本，逐字段给出 controllers.json 与 PadStateBuffer 计数器，零 Outcome"
    requirement: INPUT-05
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_onboarding_ui.gd#_check_diagnostics_profiles / _check_diagnostics_events / _check_diagnostics_line_width / _check_overlay_produces_no_outcome"
        status: pass
    human_judgment: true
    rationale: "格式与零 Outcome 已无头证明；组合键在目标机型上是否可同时按下、22 px 是否可真机读清，只能由 04-07 的 screencap 判读"
  - id: D4
    description: "重建签名 APK：与旧包同一把钥匙、只含 arm64、v2 验签通过"
    requirement: ONBOARD-02
    verification:
      - kind: other
        ref: "bash mobile/tools/gate-b.sh（末行 ✓ 闸门 B 通过）+ apksigner verify --print-certs"
        status: pass
    human_judgment: false

duration: 32min
completed: 2026-11-05
status: complete
---

# Phase 4 Plan 08: 引导 UX 修复 + 屏上诊断覆盖层 Summary

**探针屏变得「看得见、可改、说人话」（实时轴读数 / 两次软重试 / 纯语言拒绝 / 增量停止屏），并新增一个不依赖 `run-as` 的屏上诊断覆盖层作为 D1/D2 的证据出口；签名 APK 已用同一把钥匙重建，交给 04-07 重走真机 D0–D6**

## Performance

- **Duration:** 32 min
- **Started:** 2026-11-05T20:44Z（约）
- **Completed:** 2026-11-05T21:16Z
- **Tasks:** 5 / 5（Task 5 的产物与报告都在 gitignored 的 `mobile/build/`，因此没有第 5 个提交）
- **Files modified:** 15 个受版本控制的文件（含 2 个字体子集二进制）+ 1 个 gitignored 报告

## Accomplishments

- **探针屏把「app 到底收到了什么」放到第一行**：`%Hint` 第 1 行 = 实时读数（轴序号 + 正/负方向 + 有符号位移，10 Hz 节流），第 2 行 = 下一步动作；进屏第一帧就有读数，不用等 0.1 秒。`onboarding_screen.tscn` **零改动**（复用 `%Hint` 的 104 px 三行带）。
- **一次推不对不再整屏判死**：`SOFT_RETRY_LIMIT = 2` + `SOFT_RETRY_CODES`（`ambiguous_axes` / `not_enough_samples` / `not_enough_travel`）前两次留在本步，第 3 次才进 `probe_failed`；交叉校验失败（上右同轴 / 上下不反号 / 左右不反号）先回到出错的那一步，并在屏幕上直说「你刚才推的方向不像「右」…」。
- **技术数值退到第二行与 logcat**：`plain_rejection()` 的第一句永远是动作句（「只推「右」这一个方向：别的方向先松开」），`margin` / `轴 2` / `符号 -1` 这些只出现在硬失败面的第三行与 `PROBE_REJECT` 日志里。
- **停止屏不再自相矛盾**：文案改成「本步开始后新增 N 个摇杆事件（累计 M）」，N 是相对本状态起点的增量；三个停止判据（窗口为空 + 本状态 ≥60 帧 + 期间零新增事件）一字未改。
- **D1/D2 有了新的证据出口**：按住 LB+RB 0.8 秒打开诊断覆盖层，第 1 页逐字段展开 `controllers.json`（外层 key / schema / profile_id / name / guid / 六根轴 / center+scale / layout+confirmed+btn_idx_ok / probed / 四步 quality），第 2 页给出四个计数器、三个分位数、两个线程 id、每轴 v/min/max 与扳机静止值；十字键左右翻页，1 Hz 刷新，全程零触摸、零 Outcome，取证只要 `adb exec-out screencap -p`。
- **屏幕上的每句新文案都有断言兜着**：新增 `test_onboarding_ui`（8 段），套件从 15 → 16、断言从 1224 → 1335。
- **三道闸门全绿**：`test-core`（16 套件 / 1335 断言 / `TESTS_DONE failures=0`）、`gate-a`（`GLYPH_OK chars=1045` + 新脚本 `✓`）、`check_desktop`（302/302）、`test-core-selftest`（`SELFTEST_OK cases=7`）。
- **新 APK**：27,046,027 字节（旧 27,012,856，+33,171），证书 `e1841a17bda43307cdfc8e9e757c672a6a91b7fd60ea86e715afd461ba32e046` 逐字不变，`Verified using v2 scheme: true`，只含 `arm64-v8a`。

## Task Commits

Each task was committed atomically:

1. **前置修复: 重生成 tap 黄金夹具** — `58f9e9d` (fix) — 见 Deviations 第 1 条
2. **Task 1: 探针屏看得见、可重来** — `53e546c` (feat)
3. **Task 2: 诊断覆盖层 + 组合根接线 + 字形登记** — `71262a8` (feat)
4. **Task 3: onboarding_ui 无头套件** — `fd3db0d` (test)
5. **Task 4: 文档契约（ACCEPTANCE / UI-SPEC / VALIDATION）** — `58ee924` (docs)
6. **Task 5: 重建签名 APK** — 无提交（`mobile/build/fifa-trainer.apk` 与 `mobile/build/04-08-apk-report.txt` 都在 gitignored 的 `mobile/build/` 下）

**Plan metadata:** 见本次最终 docs 提交（SUMMARY / STATE / ROADMAP）

## Files Created/Modified

- `mobile/src/core/onboarding_flow.gd`（+~70 / −~15）— `SOFT_RETRY_LIMIT` / `SOFT_RETRY_CODES` / `soft_retry_count` / `last_reject_code` / `last_reject_message`；`submit_probe_step` 的软重试与交叉软重试；`_retry_entry_state()`；`_clear_failure()` 成为唯一的清空点
- `mobile/src/ui/onboarding_screen.gd`（+~200）— 四个静态纯函数（`direction_word` / `live_readout` / `plain_rejection` / `cross_check_plain` / `stop_message`）、`_refresh_readout()` 10 Hz 节流、`%Hint` 两行/三行排版、`PROBE_REJECT` 日志、增量停止屏
- `mobile/src/ui/diagnostics_overlay.gd`（新，~330 行）— 两页只读诊断文本；`format_profiles` / `format_events` / `page_text` 三个静态入口 + `_profile_block` 单一字段落点
- `mobile/src/ui/diagnostics_overlay.tscn`（新）— 根 `Control` + `%Panel`（22 px，`autowrap_mode = 0`），只 1 个 `unique_name_in_owner`
- `mobile/src/ui/main.gd`（+~110）— `DIAGNOSTICS_SCENE` / `DIAGNOSTICS_CHORD_SECONDS` / `DIAGNOSTICS_CHORD_BUTTONS = [9, 10]`；`_build_diagnostics` / `_tick_diagnostics_chord` / `_open_diagnostics` / `_close_diagnostics` / `_flush_diagnostics_edges`；`_process` 早退；`_flush_button_edges` 跳过组合键
- `mobile/tests/unit/test_onboarding_flow.gd` — 两条旧断言改写 + 两条新用例
- `mobile/tests/unit/test_onboarding_ui.gd`（新，~300 行）— 八段格式/语义断言
- `mobile/tests/core_runner.gd` — 注册 `onboarding_ui`（15 → 16）
- `mobile/tools/gate-a.sh` — `check_script` 追加 `diagnostics_overlay.gd`
- `tools/make_font_subset.py` — `CHAR_SOURCES` 追加两个新 UI 文件
- `mobile/assets/fonts/required_glyphs.txt` + 两个 `.ttf` — 992 → 1045 字符
- `mobile/ACCEPTANCE.md` — §6 的停止判据、D1 证据通道、D2 的「未执行」措辞
- `04-UI-SPEC.md` — §1 节点计数与 `%Panel` 行、Typography 22 px 例外、§5.1 覆盖层契约、§12 G12、§13 八条新检查
- `04-VALIDATION.md` — D0 / D1 / D2 三处引用
- `mobile/build/04-08-apk-report.txt`（gitignored）— size / 证书整行 / 包内容结论 / 构建时间

## Decisions Made

- **保留四步探针，只修 UX**：用户 2026-11-05 否决了单屏输入检测；本计划的 `files_modified` 因此不含任何判定链文件（`tap_detector` / `tap_runtime` / `probe_evaluator` / `calibration` 零 diff，`git status` 可核）。
- **软重试只认三类「这一下没推好」的原因**：`displacement_too_small` 这类码重推也没用，立刻硬失败；`test_onboarding_flow._check_soft_retry_code_filter` 把这条钉住。
- **读数只说轴序号**：屏幕写「轴 2 的负方向（-0.98）」。写「右摇杆 X 轴」等于替探针猜结论，猜错就把用户带进沟里（INPUT-02）。
- **诊断面读原始字节**：`ProfileStore.load_all()` 对损坏文件会删档，而坏档正是 D1 要拍的证据；因此覆盖层用 `FileAccess.get_file_as_string(ProfileStore.PROFILES_PATH)` + 自己的解析，坏档显示「解析失败」并把前 160 字符分两行附上。
- **组合键不含 X**：tap 手势是「按住 RB 连按两下 X」，组合键只用 9/10，永远凑不出 `Hit` 或 `Failure`；打开时再叠一层 `set_layout_confirmed(false)`，可见期间 `_process` 早退 —— 三层保证覆盖层自身 0 条 Outcome。
- **APK 必须重建**：04-07 若拿旧包重走 D0，装上去的仍是没修的版本；新包已进 `mobile/build/`，报告里 size 与证书都可核对。

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `tap_golden.json` 在桌面合并后已经过期，基线 `test-core.sh` 一开始就是红的**
- **Found during:** 开工前的基线核对（第一个 task 之前）
- **Issue:** 合并提交 `4825afa`（桌面版专项练习 / 按键校准）改了 `desktop/padskills/config.py`、`engine.py` 与 `shared/skills_config.json`，但没有重生成 `mobile/tests/fixtures/tap_golden.json`。夹具里的 `sha256.config` 是 `b9fb9f39…`，实际文件是 `244be196…`，`gen_tap_golden.py --check` 直接失败 —— 于是**任何** task 的 `<verify>` 都不可能通过。
- **Fix:** 跑 `python3 tools/gen_tap_golden.py` 重新生成。逐字节比对确认**只有 sha256 块变了**：12 条 detector 用例与 6 条 runtime 用例的期望值一字未动，桌面侧改的是专项练习 / 暂停等 UI 层逻辑，不影响 tap 判定。
- **Files modified:** `mobile/tests/fixtures/tap_golden.json`（3 行）
- **Verification:** `bash mobile/tools/test-core.sh` → `TAP_GOLDEN_DETECTOR cases=12 mismatches=0`、`TAP_GOLDEN_RUNTIME cases=6 mismatches=0`、`TESTS_DONE failures=0`
- **Committed in:** `58f9e9d`（独立提交，不塞进 Task 1）
- **说明:** 该文件不在本计划的 `files_modified` 里。它是生成物、修复方式是工具自己打印的，且不修就无法完成任何 task —— 按 Rule 3 处理，并在此记录。

**2. [Rule 1 - Bug] 交叉校验的软重试计数会被「这一步单独测成功了」抹掉**
- **Found during:** Task 1 第一次跑 `test_onboarding_flow`（`第 2 次交叉失败后计数必须是 2（实际 1）`）
- **Issue:** 计划写「成功分支：`soft_retry_count = 0`」。但交叉失败发生在**四步都提交成功之后**：如果每次成功的 step 提交都调 `_clear_failure()`（它同时清计数），交叉失败就永远只有「第 1 次」，重试变成无限 —— 与计划自己的用例（「累计第 3 次交叉失败才判失败」）冲突。
- **Fix:** 把 `_clear_failure()` 移到两个真正的成功出口（`_steps.size() < 4` 与 `cross.ok`）；交叉失败分支不调它，只写 `last_reject_*`。注释里写明原因。
- **Files modified:** `mobile/src/core/onboarding_flow.gd`
- **Verification:** `_check_probe_cross_validation` 三次交叉失败分别得到 1 / 2 / 硬失败；`_check_soft_retry_resets_on_success` 证明推对之后计数归零
- **Committed in:** `53e546c`（Task 1）

**3. [Rule 2 - Missing Critical] 坏档是预期路径，`JSON.parse_string` 会往 stderr 打 `ERR_PRINT`**
- **Found during:** Task 3 第一次跑套件（日志里出现 `ERROR: Parse JSON failed`）
- **Issue:** `JSON.parse_string()` 解析失败时自己 `ERR_PRINT`。诊断覆盖层的坏档分支**必须**解析失败（那正是 D1 要拍的证据），生产路径上每次刷新都会打一行看起来像崩溃的错误。
- **Fix:** 改用 `JSON.new().parse()`（返回 Error、不打印），封装成 `_parse()` 单一入口。
- **Files modified:** `mobile/src/ui/diagnostics_overlay.gd`
- **Verification:** 套件输出不再有 `ERROR: Parse JSON failed`；`_check_diagnostics_profiles` 仍拿到「解析失败」文本
- **Committed in:** `fd3db0d`（Task 3，与被它逼出来的原因写在一起）

**4. [计数修正] 诊断覆盖层计数器 grep 按「行」计是 3，不是 ≥8**
- **Found during:** Task 2 验收
- **Issue:** 计划写 `grep -c 'ev_m=\|ev_b=\|…\|proc_tid=' mobile/src/ui/diagnostics_overlay.gd` ≥ 8，但计划自己的格式要求是「`计数器 ev_m=%d ev_b=%d poll=%d`」一行、「`间隔ms dt50=… dt95=… dtmax=…`」一行、「`线程 in_tid=… proc_tid=…`」一行 —— `grep -c` 数的是**行**，三个字段组只占 3 行。
- **Action:** 保持计划写的屏幕格式（8 个字段全在，逐字来自 `PadStateBuffer`），不做「为凑 8 行把句子拆碎」的改动。按 orchestrator 约束 16 记录修正值：**行数 3（字段数 8）**。语义层面的证据由 Task 3 的 `_check_diagnostics_events` 逐字段断言（`ev_m=3` / `ev_b=1` / `poll=0` / `dt50=` / `dt95=` / `dtmax=` / `in_tid=1` / `proc_tid=1`）。
- **没有放宽任何断言**：新套件对 8 个字段各有独立断言。

**5. [计数修正] `check_desktop.sh` 的基线是 302 项，不是 230**
- **Found during:** 收尾验证
- **Issue:** 计划与 STATE 里沿用的「230 项」是 Phase 1 搬迁时的数字；桌面版后续新增了专项练习 / 按键校准 / 诊断日志三批检查，实际基线已是 302。
- **Action:** 记录实际值：`bash tools/check_desktop.sh` → `✓ 302 项检查全部通过，名称与基线逐项一致`。**没有改脚本里的 `BASELINE_SHA256`，也没有放宽任何断言** —— 302 是脚本自己算出来的，不是本计划改的。

### 计划未覆盖但我没有做的事（显式记录）

- **没有跑 D0–D6**：计划明写真机走查归 04-07（Wave 8）。本次只出包与可核对报告。
- **没有改 `shared/skills_config.json`**：`git status --porcelain shared` 为空。
- **没有碰 `desktop/` 与 `design/`**：`design/` 一直是用户的未跟踪工作，全程未 `git add`。
- **没有把四步探针改成单屏检测**：用户已最终决定保留四步。

### 环境差异（不是计划分歧）

- 本环境没有 `gsd_run`：Step 0 的 protected-branch 查询、`state.*`、`roadmap.update-plan-progress`、`windows append` 均无法执行。按 orchestrator 的 `<sequential_execution>`（主工作树顺序执行）与 `.planning/config.json` 的 `git.branching_strategy: none`，在 `main` 上用普通提交（带 hooks，未用 `--no-verify`）。STATE / ROADMAP 用手工编辑更新。
- **Task 5 的口令来源**：`GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD` 开工时不在环境里。按 `mobile/BUILD.md` 第四节记录的本机做法（`set -a; . "$HOME/.fifa-trainer/credentials.sh"; set +a`，仓库外的 600 文件）在同一 shell 内注入后跑 `gate-b.sh`；口令**没有**出现在任何文件、日志或命令行参数里，事后随 shell 退出消失。

---

**Total deviations:** 5（3 auto-fixed：1 个 Rule 3 阻塞、1 个 Rule 1 bug、1 个 Rule 2 缺项；2 个计数修正：grep 行数、桌面对照数）
**Impact on plan:** 没有放宽任何断言。Rule 3 的夹具重生成是「不修就一步都走不动」的前置；Rule 1/Rule 2 两条都写在被它们影响的文件旁边。两处计数修正都按实际树重算并在此记录。

## Issues Encountered

- **`infer the type of "needle"` 编译错误**（Task 3 第一次）：`for fragment in [...]` 的循环变量是 Variant,`var needle := fragment` 无法推断类型。改成 `var needle: String = str(fragment)`。
- **套件日志里的 `Unicode parsing error … (ff/fe)`**：基线里本来就有（`--import` 扫到非 UTF-8 字节时会打），与本计划无关，未处理；闸门判据不看这两行。
- **`_render_layout` 一度被我误删函数头**：一次 Edit 用新函数块替换了 `func _render_layout() -> void:` 那一行。`--check-only` 之前就发现并补回，最终 `gate-a.sh` 的六个 `✓` 都在。

## Known Stubs

None — 新增的两个文件都不含占位数据：诊断覆盖层的数据源是真实档案字节与 `PadStateBuffer`；引导屏的读数来自 `axis_value()`，不是常量。

## Threat Flags

None — 本计划新增的唯一外部面是「屏幕 → 截图」，不引入网络、文件写入或权限变更。威胁登记里的 T-04-22 / T-04-23 / T-04-24 / T-04-26 四条 mitigate 都有对应断言（软重试上限、逐字段断言、零 Outcome、字形闭世界）。

## User Setup Required

- **`GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD`**：只有重建 APK 需要。本次按 `mobile/BUILD.md` §4 的本机做法从仓库外的 `~/.fifa-trainer/credentials.sh` 注入，未写进任何文件或命令行参数。下次重出包仍需在 shell 里 export。
- 真机走查（04-07）需要：一台已连 adb 的手机 + 一只 Xbox 手柄；D2 的拒绝面还需要第二只轴映射不同的手柄（本次不具备）。

## Next Phase Readiness

- **04-07（Wave 8）可以开工**，但**必须先卸载重装新包**：`adb uninstall com.fifaskill.trainer` → `adb install -r mobile/build/fifa-trainer.apk`（27,046,027 B，证书 `e1841a17…32e046`）。装旧包等于重跑一次没修的版本。
- **D0 这次应该看得到读数**：每一步 `%Hint` 第一行会显示「你推的是：轴 N 的正/负方向（±x.xx）」。若屏幕再次出现停止屏，抄录整句「本步开始后新增 N 个摇杆事件（累计 M）」。
- **D1 不再需要 `run-as`**：LB+RB 0.8 秒打开档案页 → `adb exec-out screencap -p > mobile/build/phase4-D1-diagnostics-profiles.png`。
- **D2 只能部分执行**：接受面（同一只手柄重连只验右 + 下）可验；拒绝面缺第二只手柄，且覆盖层只读、改不了外层 key。成功标准 3 不得声称完整。
- **成功标准 2/3/4/5 仍未闭合**：`REQUIREMENTS.md` 与 `ROADMAP.md` 均未勾选；Phase 4 不得宣布完成。

---

*Phase: 04-device-input-green-slice*
*Completed: 2026-11-05*
*Status: complete（代码侧）— 真机清单在 04-07*

## Self-Check: PASSED

- `test -f mobile/src/ui/diagnostics_overlay.gd` / `.tscn` / `.gd.uid` / `mobile/tests/unit/test_onboarding_ui.gd` / `.gd.uid` 全部成立
- `test -f mobile/build/fifa-trainer.apk` 成立；`stat -f %z` = 27046027，与报告里的 `size=` 一致
- 五个提交都是 HEAD 的祖先：`58f9e9d` / `53e546c` / `71262a8` / `fd3db0d` / `58ee924`
- `git diff --stat mobile/src/ui/onboarding_screen.tscn` 为空（零新节点）
- `bash mobile/tools/test-core.sh` → `TESTS_SUITES=16` / `TESTS_ASSERTIONS=1335` / `TESTS_DONE failures=0`
- `bash mobile/tools/gate-a.sh` → `GLYPH_OK chars=1045` + `✓ res://src/ui/diagnostics_overlay.gd` + `✓ 闸门 A 通过`
- `bash mobile/tools/gate-b.sh` → `✓ 闸门 B 通过`；证书 SHA-256 与 `BUILD.md` 第六节逐字相同
- `bash tools/check_desktop.sh` → 302/302；`python3 tools/lint_core_purity.py mobile/src/core` → `LINT_OK files=27`；`python3 tools/make_font_subset.py --check` → 0
- `grep -c '^- \[x\]' mobile/ACCEPTANCE.md` → 0（本计划不宣布任何 D 项通过）
- `git status --porcelain shared desktop` 为空
