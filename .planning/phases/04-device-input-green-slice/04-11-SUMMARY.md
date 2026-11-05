---
phase: 04-device-input-green-slice
plan: 11
subsystem: mobile-input-setup-hardening
tags: [godot, gdscript, input-setup, save-gate, layout-confirm, diagnostics, apk, headless-tests]

requires:
  - phase: 04-device-input-green-slice
    plan: 10
    provides: 一页式 input_setup_screen / 输入事件日志 / APK 27,071,318 B
  - phase: 04-device-input-green-slice
    plan: 09
    provides: InputSetup（轴对 / 符号 / 量程 / 扳机静止）/ 单页首启路径
  - phase: 02-android-toolchain
    provides: gate-b.sh 导出链路、release keystore、apksigner 36.1.0

provides:
  - "InputSetup.can_save() / cycle_layout() / mark_layout_confirmed() / layout_confirmed()"
  - "build_profile() 在量程未满时返回 null —— 默认校准不再可能落盘"
  - "DeviceProfile.can_enter_practice()：rs 映射 + 校准区间 + 布局确认 + quality.range_ready 四合一门"
  - "can_reuse() 先过自洽门再比四项；04-09/04-10 的默认校准档案一律失效"
  - "设置页按键：十字键左右翻 X、上下翻 Y、Start 切布局、A 保存、B 清空、LB/RB 换轴对；X/Y 无功能"
  - "布局行 `布局：Xbox（按 Start 切换，按 A 确认）`（%Layout 节点）"
  - "ProfileStore.clear() + 诊断覆盖层 Y 清除并回设置页"
  - "mobile/build/fifa-trainer.apk 重建（27,079,510 B，证书 e1841a17…32e046 不变）"
  - "mobile/ACCEPTANCE.md §6：04-11 的 D0 11 步、按键表、证据字段（INPUT_SETUP layout=/confirmed=）"

affects: [04-07-real-device-walkthrough, phase-5-detectors, phase-9-release]

actuals:
  tokens: 17622
  tasks: 2
  commits: 2

# #3968 的实测计数（同一数字，顶层供 verify-work 的 `^commits:` 直接读取）
commits: 2
plan_head_before: 066c8a335faa91b93de2d3232427eac27c8eadef
plan_head_after: 32cc0f1f8b23bcf7577a03f0aa8f439615f4ebbf

tech-stack:
  added: []
  patterns:
    - "保存门写在数据源上，不写在界面上：`InputSetup.can_save()` 是唯一判据，`build_profile()` 拿不到就返回 null；界面只负责把 null 变成一句人话"
    - "「档案自洽门」与「四项复用门」分层：`can_enter_practice()` 回答「这份档案自己能不能用」，`can_reuse()` 再回答「它是不是这只手柄上次那一份」"
    - "按键语义是纯函数（`action_for_button`）：无头套件直接断言 X/Y 返回 ACTION_NONE，不需要实例化场景，也不需要真机"
    - "键位索引取自 Godot 的 `JoyButton` 枚举而不是手写数字；常量名（`KEY_DPAD_LEFT` 等）同时满足计划的可 grep 契约"
    - "破坏性操作只碰一个路径 + `user://` 守卫 + 幂等：`ProfileStore.clear()` 不存在时返回 OK，`res://` 返回 ERR_UNAUTHORIZED"

key-files:
  created: []
  modified:
    - mobile/src/core/input_setup.gd
    - mobile/src/core/device/device_profile.gd
    - mobile/src/core/onboarding_flow.gd
    - mobile/src/app/profile_store.gd
    - mobile/src/ui/input_setup_screen.gd
    - mobile/src/ui/input_setup_screen.tscn
    - mobile/src/ui/diagnostics_overlay.gd
    - mobile/src/ui/main.gd
    - mobile/tests/unit/test_input_setup.gd
    - mobile/tests/unit/test_device_profile.gd
    - mobile/tests/unit/test_onboarding_flow.gd
    - mobile/tests/unit/test_onboarding_ui.gd
    - mobile/tests/unit/test_profile_store.gd
    - mobile/assets/fonts/required_glyphs.txt
    - mobile/assets/fonts/NotoSansSC-Subset.ttf
    - mobile/ACCEPTANCE.md

key-decisions:
  - "`build_profile()` 在量程未满时返回 null，而不是写一份「降级档案」：默认校准不是校准，写进去之后复用门会把它当真"
  - "布局确认与布局建议分开：`layout_cycle()` 只给显示/保存用的当前值，`mark_layout_confirmed()` 只由 A 的保存路径调用；`build_profile()` 自己永远不会写 true"
  - "`can_enter_practice()` 放在 `DeviceProfile` 而不是 `main.gd`：组合根与 `can_reuse()` 共用同一扇门，避免两处判定分叉"
  - "`quality.range_ready == true` 是识别新档案的唯一标记：默认 scale=1.0/center=0 与「真的推到 ±1.0」在数值上无法区分，只能靠写入时的事实"
  - "`Calibration.MIN_SCALE`（0.5）直接复用为半量程下限，不另写一个 0.5：同一语义只有一个常量"
  - "X/Y 在设置页彻底无功能，而不是「只在某些状态下有效」：它们与按住 RB 连按两下 X 的手势共用同一颗键，任何分支都会再次撞车"
  - "诊断覆盖层的键位语义收进覆盖层自己的 `action_for_button` / `handle_button`：组合根不再维护第二份 match，Y 的加入不需要改两处"
  - "`ProfileStore.clear()` 只删目标文件、不删 `.tmp`、不删目录：T-04-23 的边界用代码写死，不靠调用方自觉"
  - "布局行放在独立的 `%Layout` 节点（全宽 y=436..476），量程/中点/扳机整体下移 36 px：不挤压 Help 与 Footer 的两行空间"

patterns-established:
  - "「不可静默确认」的状态必须是显式方法：`layout_confirmed` 只有一个置真入口（A），套件还能断言「只切换布局不算确认」"
  - "旧数据失效靠写入时的事实标记，而不是靠数值启发式：改判定条件时先问「这份档案是哪一版写的、能不能机械识别」"

requirements-completed: []
# INPUT-03 / INPUT-04 / ONBOARD-02 在本计划**不宣布完成**：
# 代码侧的三道门与按键重排都有无头断言，但真机上的「只用手柄走完」「DualSense 确认」
# 与「覆盖层按 Y 后回到设置页」仍只能由 04-07 的 D0 回答。断言绿不等于真机通过。

coverage:
  - id: D1
    description: "量程未满时不可能写出可复用档案：can_save false + build_profile null + can_enter_practice 拒绝旧档案"
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_input_setup.gd#_check_save_gate / _check_layout_confirm / _check_legacy_profile"
        status: pass
      - kind: unit
        ref: "mobile/tests/unit/test_device_profile.gd#_check_reuse_gate（缺标记 / range_ready=false / 窄量程 / 越界中点 / 未确认布局）"
        status: pass
    human_judgment: false
  - id: D2
    description: "X/Y 在设置页无功能；符号归十字键、布局归 Start；Y 清除档案的键位语义"
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_onboarding_ui.gd#_check_setup_key_map / _check_setup_texts / _check_overlay_key_map"
        status: pass
    human_judgment: false
  - id: D3
    description: "ProfileStore.clear() 只删目标文件、幂等、res:// 守卫；新 APK 同证书"
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_profile_store.gd#_check_clear"
        status: pass
      - kind: other
        ref: "bash mobile/tools/gate-b.sh（末行 ✓ 闸门 B 通过）；apksigner 证书 e1841a17…32e046"
        status: pass
    human_judgment: false
  - id: D4
    description: "真机：按 X/Y 不再改符号、量程未满按 A 不写档案、布局行显示且 Start 可切、覆盖层按 Y 回到设置页"
    verification: []
    human_judgment: true
    rationale: "按键是否真的到达、页面是否真的停在设置页、覆盖层清除后是否真的回到设置页，都只能由 04-07 的真机 D0 回答；无头环境没有手柄也没有真实用户目录。"

duration: 18min
completed: 2026-11-05
status: complete
---

# Phase 4 Plan 11: 设置页保存门 + 按键重排 + 诊断页清除 Summary

**三个真机缺陷在同一页上修掉：X/Y 不再碰符号（改十字键），A 只在量程推满时保存，布局必须由 Start 切换并由 A 确认；诊断覆盖层按 Y 可删档重来 —— 同一个 APK 证书，代码里没有新增任何步骤**

## Performance

- **Duration:** 18 min
- **Started:** 2026-11-05T15:31:32Z
- **Completed:** 2026-11-05T15:49:30Z
- **Tasks:** 2 / 2
- **Files modified:** 16 个受版本控制的文件（全部为修改，无新建）

## Accomplishments

- **量程未满不再可能保存默认校准**：`InputSetup.can_save()` 是唯一判据，`build_profile()` 拿不到就返回 `null`；设置页在 A 分支只把 `%Help` 换成「量程还没推满：把右摇杆往四个方向各推到底几次」，不写档案、不切屏。
- **旧档案自动失效**：`DeviceProfile.can_enter_practice()` 把「rs 映射齐全 + 校准半量程 ≥ `Calibration.MIN_SCALE` + 中点 ±0.5 + 布局已确认 + `quality.range_ready == true`」合成一扇门；`can_reuse()` 先过这扇门再比四项。04-09/04-10 在量程未满时写出的档案没有标记，因此被丢弃、设置页重新出现。
- **布局必须人确认**：新增 `layout_cycle()` / `cycle_layout()` / `mark_layout_confirmed()`；`build_profile()` 只写 `_layout_confirmed` 的值，自己永远不会把 `layout_confirmed` 置真。A 是唯一的置真路径。
- **X / Y 在设置页彻底无功能**：符号翻转到十字键（左右翻 X、上下翻 Y），布局切换到 Start；`action_for_button()` 是纯函数，套件直接断言 `X/Y → ACTION_NONE`。
- **诊断页可一键重来**：`ProfileStore.clear()` 只删 `user://profiles/controllers.json`，不存在视为成功，`res://` 返回 `ERR_UNAUTHORIZED`；覆盖层按 Y 调它并发 `profile_cleared`，组合根关闭覆盖层、退出练习、回到设置页。
- **布局行上屏**：新增 `%Layout` 节点，逐字显示 `布局：Xbox（按 Start 切换，按 A 确认）`；`INPUT_SETUP` 的每秒日志多两个 ASCII 字段 `layout=` / `confirmed=`。
- **套件从 1457 涨到 1533 条断言**（18 套件不变）：保存门 / 布局确认 / 旧档案失效 / 按键语义 / 文案 / 清除档案共 76 条新断言。
- **新 APK 27,079,510 字节**（上一包 27,071,318，+8,192）：`gate-b.sh` 全绿，证书 `e1841a17…32e046` 逐字不变，`GLYPH_OK chars=1053`。
- **ACCEPTANCE §6 可照抄**：04-11 的 D0 11 步、按键表（含「X / Y 无功能」）、量程未满按 A 的预期提示、覆盖层 Y 清除、证据字段全部写进新小节；04-09 的 8 步保留为历史对照。

## Task Commits

Each task was committed atomically:

1. **Task 1: InputSetup 保存门 + 布局确认 + 旧档案失效** — `09f29a5` (feat)
2. **Task 2: 设置页按键重排 + 诊断页清除 + 重建 APK** — `32cc0f1` (feat)

**Plan metadata:** 见本次最终 docs 提交（SUMMARY / STATE / ROADMAP / PLAN）

## Files Created/Modified

- `mobile/src/core/input_setup.gd`（+61/−8）— `can_save()`、`layout_cycle()` / `cycle_layout()` / `mark_layout_confirmed()` / `layout_confirmed()`；`build_profile()` 未就绪返回 `null`，布局取 `layout_cycle()`、`layout_confirmed` 取用户确认值；`reset()` 一并清布局
- `mobile/src/core/device/device_profile.gd`（+51/−8）— `can_enter_practice()`、`_range_ready_marker()`、`MAX_CALIBRATION_CENTER`；`can_reuse()` 先过自洽门；文档说明为什么数值无法区分默认校准
- `mobile/src/core/onboarding_flow.gd`（+4）— 复用流程产出的档案补 `quality["range_ready"] = true`，否则会被自己的复用门拒绝
- `mobile/src/app/profile_store.gd`（+14）— `clear()`：只删目标文件、幂等、`user://` 守卫
- `mobile/src/ui/input_setup_screen.gd`（+112/−21）— `ACTION_*` / `KEY_*` 常量、`action_for_button()`、保存门与提示、Start 切布局、`layout_text()`、`debug_line()` 增 `layout=/confirmed=`
- `mobile/src/ui/input_setup_screen.tscn`（+19/−10）— 新增 `%Layout` 全宽行；量程/中点/扳机/帮助/页脚整体下移 36 px
- `mobile/src/ui/diagnostics_overlay.gd`（+63/−3）— `profile_cleared` 信号、store 注入、`action_for_button()` / `handle_button()`、`clear_profile()`；文档从「只读」改为「正常渲染只读，唯一例外是 Y 清除」
- `mobile/src/ui/main.gd`（+37/−18）— 覆盖层注入 store 与信号接线、边沿统一交给覆盖层、`_on_profile_cleared()`、`_profile_usable()` 改为 `can_enter_practice()`
- `mobile/tests/unit/test_input_setup.gd`（+160/−8）— 保存门 / 布局确认 / 旧档案失效三组用例；`_stored_profile()` 夹具
- `mobile/tests/unit/test_device_profile.gd`（+33/−3）— 自洽门六条反例 + 合法档案补标记
- `mobile/tests/unit/test_onboarding_flow.gd`（+1）— 复用夹具补 `range_ready`
- `mobile/tests/unit/test_onboarding_ui.gd`（+80）— 设置页与覆盖层的按键语义、布局行与符号文案
- `mobile/tests/unit/test_profile_store.gd`（+20）— `clear()` 的成功 / 幂等 / `res://` 守卫
- `mobile/assets/fonts/required_glyphs.txt` + `NotoSansSC-Subset.ttf` — 1048 → 1053 字符（+7 新增注释用字，−2 因改写文档移除「东西」）
- `mobile/ACCEPTANCE.md`（+77/−6）— §6 新增 04-11 的 D0 操作说明与证据表；尝试表加「五」；04-10 日志小节改为「之后的包都包含」

## Decisions Made

- **保存门写在数据源上**：界面只调用 `can_save()`，`build_profile()` 自己再拒绝一次；这样即使将来出现第二个保存入口也不会绕过。
- **布局建议 ≠ 布局确认**：`layout_cycle()` 只是当前显示值，`mark_layout_confirmed()` 是唯一置真入口；套件断言「只切换不算确认」「不调 mark 时档案写 false」。
- **`can_enter_practice()` 与 `can_reuse()` 分层**：前者回答「档案自己能不能用」，后者回答「是不是这只手柄上次那一份」。组合根只调前者，避免两处各写一份判定。
- **`quality.range_ready` 作为新档案标记**：`scale=1.0 / center=0` 与真实推到 ±1.0 在数值上不可区分，只能靠「保存时量程是否真的满」这一事实。
- **X/Y 彻底无功能**：不做「长按/组合键」之类的例外 —— 练习手势是「按住 RB 连按两下 X」，任何用到 X 的分支都会再次撞车。
- **键位索引用 `JoyButton` 枚举**：同时保留 `KEY_DPAD_*` / `JOY_BUTTON_START` 常量名，满足计划的可 grep 契约且不手写数字。
- **诊断覆盖层的按键语义收进覆盖层**：组合根只负责把边沿转交，新增 Y 时不需要改两处，也不会出现两份 match 分叉。
- **`ProfileStore.clear()` 不删 `.tmp`**：约束是「只删那一份文件」；孤立 `.tmp` 会在下次 `save_all()` 被覆盖，删它反而扩大边界。

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `device_profile.gd` 不在 `files_modified` 里，但 Task 1 的 action 明确要求改它的复用门**
- **Found during:** Task 1 设计阶段（`can_reuse()` 是 `DeviceProfile` 的方法）
- **Issue:** 计划的 `files_modified` 只列了 `input_setup.gd` 与 `test_input_setup.gd`；不改 `DeviceProfile` 就无法实现「旧档案不可复用」。
- **Fix:** 在 `device_profile.gd` 新增 `can_enter_practice()` / `_range_ready_marker()`，`can_reuse()` 先过自洽门；`main.gd` 的 `_profile_usable()` 改为直接委托。
- **Files modified:** `mobile/src/core/device/device_profile.gd`、`mobile/src/ui/main.gd`
- **Verification:** `test_device_profile#_check_reuse_gate` 六条反例 + `test_input_setup#_check_legacy_profile`
- **Committed in:** `09f29a5`（Task 1）

**2. [Rule 3 - Blocking] 既有夹具 / 复用流程产出的档案缺 `range_ready`，会被新门判死**
- **Found during:** Task 1 第一次 `test-core.sh`（6 条 `onboarding_flow` 失败）
- **Issue:** `test_device_profile._legal_profile()`、`test_onboarding_flow._profile()` 与 `OnboardingFlow.build_profile()` 都不写 `quality.range_ready`。前两者是夹具问题；后者是真缺陷 —— 流程自己产出的档案会被自己的复用门拒绝。
- **Fix:** 两个夹具补标记；`OnboardingFlow.build_profile()` 在 `quality` 里写 `range_ready = true`（它的量程是按满行程采的，标记是事实）。
- **Files modified:** `mobile/src/core/onboarding_flow.gd`、`mobile/tests/unit/test_device_profile.gd`、`mobile/tests/unit/test_onboarding_flow.gd`
- **Verification:** `TESTS_DONE failures=0`（18 套件 / 1496 断言，Task 1 结束时）
- **Committed in:** `09f29a5`（Task 1）

**3. [Rule 3 - Blocking] 「屏幕新增一行」需要新节点，而 `.tscn` 不在 `files_modified` 里**
- **Found during:** Task 2 实现布局行
- **Issue:** 现有 10 个唯一节点没有地方放 `布局：…`：右列 Pair/Signs 已排到 y=432，三行全宽从 y=444 开始，Help/Footer 已贴底。
- **Fix:** 新增 `%Layout` 全宽节点（y=436..476），量程/中点/扳机/Help/Footer 整体下移 36 px；脚本的「10 个唯一节点」注释同步改成 11。
- **Files modified:** `mobile/src/ui/input_setup_screen.tscn`、`mobile/src/ui/input_setup_screen.gd`
- **Verification:** `gate-a.sh` 的 `✓ res://src/ui/input_setup_screen.gd` + `check_pack` 全绿；`GLYPH_OK chars=1053`
- **Committed in:** `32cc0f1`（Task 2）

**4. [Rule 2 - Missing Critical] 新增的破坏性方法 `ProfileStore.clear()` 没有测试**
- **Found during:** Task 2 自查
- **Issue:** 计划没有要求测试 `clear()`，但它是唯一会删用户档案的入口（T-04-23）；没有断言时「只删那一份文件 / 幂等 / `res://` 守卫」全靠读代码。
- **Fix:** `test_profile_store.gd` 新增 `_check_clear`（8 条断言）：成功后文件不存在、重复调用仍 OK、不留 `.tmp`、`res://` 返回 `ERR_UNAUTHORIZED`。
- **Files modified:** `mobile/tests/unit/test_profile_store.gd`（不在计划清单内）
- **Verification:** `TESTS_ASSERTIONS=1533` / `TESTS_DONE failures=0`
- **Committed in:** `32cc0f1`（Task 2）

### 计划文本修正（不是代码分歧）

**5. [清单修正] `tools/make_font_subset.py`、`NotoSansSymbols2-Subset.ttf`、`mobile/tests/core_runner.gd` 列在 `files_modified` 但无需改动**
- 生成器本身没有逻辑变化；符号子集不含新字符（四个产物里它输出 `·`）；套件数量仍是 18，`core_runner.gd` 不需要注册新套件。字体清单与 SC 子集确实变了：**1048 → 1053**（+7 个新注释用字 `扇护撤洽痕销陷`，−2 个因改写 `can_reuse` 文档而消失的 `东西`）。

**6. [结构修正] 诊断覆盖层的边沿分派从 `main.gd` 移进覆盖层**
- 计划只要求「按 Y 调 `ProfileStore.clear()` 并发信号」。为避免 `main.gd` 与覆盖层各写一份键位 match，分派整体收进覆盖层的 `action_for_button()` / `handle_button()`；`main.gd` 只把按下的边沿转交。行为等价，新增 Y 不需要改两处。

### 环境事实

**7. [执行环境] 顺序执行在 `main` 上（`branching_strategy: "none"`）**
- 编排器以 `SEQUENTIAL=true` 在主工作树派发；仓库配置 `git.branching_strategy = "none"`，此前 04-01…04-10 的提交也都在 `main`。未新建分支、未改 `git.allow_default_branch_commits`，以保持仓库既有工作流。
- **影响：** 无 —— 提交仍是原子的，`git log` 可逐条核对。

---

**Total deviations:** 4 auto-fixed（3 个 Rule 3、1 个 Rule 2）+ 2 个计划文本修正 + 1 条环境事实
**Impact on plan:** 三处 Rule 3 都是「不改就无法实现计划要求的同一行为」；Rule 2 补的是唯一会删用户数据的入口。没有放宽任何断言，也没有为凑数改测试。

## Issues Encountered

- **ACCEPTANCE 记录了两轮构建**：第一次 `gate-b.sh` 产出 27,079,510 B 之后又调整了 `%Layout` 的宽度与字号；重跑后字节数恰好不变（tscn 里替换的字符串长度相同），但为了避免「文档描述的是上一轮产物」，最终记录以第二次构建时间 23:46 CST 为准。
- **`test_profile_store.gd` 的一次中间编辑误删了空行**（把 `return ProfileStore.new(...)` 和下一段注释拼到一行），在同一任务内立刻修正，最终 diff 里只有新增的 `_check_clear`。
- **`--import` 一次通过**，没有遇到已知的 1/5 字体导入 SIGSEGV。

## Known Stubs

None — 本计划没有占位数据：布局行的两个值（Xbox / PlayStation）都来自 `InputSetup` 的真实状态，覆盖层的清除结果要么删成功要么返回错误码，没有「稍后接入」的分支。

## Threat Flags

None — 新增的唯一写操作（删除档案）已在计划 `<threat_model>` 内：T-04-23 要求「只删 `user://profiles/controllers.json`，不碰其他数据」，实现里有 `user://` 守卫、只调一次 `DirAccess.remove_absolute(_path)`，并由 `test_profile_store#_check_clear` 断言。T-04-22 的三重门（`can_save` + `range_ready` + 布局确认）各有对应断言；无新增依赖（T-04-SC）。

## User Setup Required

- **重建 APK 需要 `GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD`**：本次按 `mobile/BUILD.md` §4 从仓库外的 `~/.fifa-trainer/credentials.sh` 在同一 shell 注入，口令没有出现在任何文件、日志或命令行参数里。
- **真机验收只需 adb**：`adb uninstall com.fifaskill.trainer` → `adb install -r mobile/build/fifa-trainer.apk`；按 ACCEPTANCE §6 的 11 步走 D0。

## Next Phase Readiness

- **04-07 下一次走查请装 27,079,510 B 的新包**：装旧包会看到旧按键（X/Y 翻符号、A 随时保存、布局静默确认），三个缺陷都还在。
- **D0 判据已经机械可读**：`INPUT_SETUP` 行现在带 `layout=` 与 `confirmed=`；`ready=0` 时按 A 不应出现任何写入，`confirmed=0` 表示还没人按过 A。
- **诊断页不再只读**：按 Y 会删档案并回设置页；要拍档案证据请**先截图、再按 Y**。
- **成功标准 2/3/4/5 仍未闭合**：`REQUIREMENTS.md` 与 `ROADMAP.md` 都不勾；本计划只把三个已知缺陷的代码侧修好，真机结论仍归 04-07。

---

*Phase: 04-device-input-green-slice*
*Completed: 2026-11-05*
*Status: complete（代码侧）— 真机清单仍在 04-07*

## Self-Check: PASSED

- `test -f` 全部成立：`mobile/src/core/input_setup.gd`、`mobile/src/core/device/device_profile.gd`、`mobile/src/app/profile_store.gd`、`mobile/src/ui/input_setup_screen.tscn`、`mobile/src/ui/input_setup_screen.gd`、`mobile/src/ui/diagnostics_overlay.gd`、`mobile/src/ui/main.gd`
- 两个任务提交都是 HEAD 的祖先：`09f29a5` / `32cc0f1`
- `bash mobile/tools/test-core.sh` → `TESTS_SUITES=18` / `TESTS_ASSERTIONS=1533` / `TESTS_DONE failures=0`
- `bash mobile/tools/gate-a.sh` → `GLYPH_OK chars=1053` + `✓ res://src/ui/input_setup_screen.gd` + `✓ 闸门 A 通过`
- `bash mobile/tools/gate-b.sh` → `✓ 闸门 B 通过`；`stat -f %z` = 27079510；证书 SHA-256 `e1841a17…32e046`
- `bash tools/check_desktop.sh` → 302/302；`python3 tools/lint_core_purity.py mobile/src/core` → `LINT_OK files=28`；`python3 tools/make_font_subset.py --check` → 0
- `grep 'layout=.*confirmed=' mobile/src/ui/input_setup_screen.gd` 命中；`grep 'KEY_DPAD_LEFT' mobile/src/ui/input_setup_screen.gd` 命中
- `git status --porcelain shared desktop` 为空；`design/` 未被 `git add`
