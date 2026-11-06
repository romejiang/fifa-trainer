---
phase: 05-judge-parity-decimation
plan: 08
subsystem: ui
tags: [godot, portrait, home-screen, gamepad, auto-profile, font-subset, apk]

requires:
  - phase: 05-judge-parity-decimation
    provides: GestureEngine 多动作判定、FrameBuilder、OUTCOME 日志与唯一 drain 契约（05-07）
  - phase: 05-judge-parity-decimation
    provides: InputSetup 标准映射自动建档（RS 2/3、LS 0/1、扳机 4/5）与 schema v2 档案（05-06 / 前置提交）

provides:
  - 720×1280 竖屏 HomeScreen（顶部区 / 英雄卡 / 5 行动作熟练度 / 8 条最近尝试 / 手柄状态卡）
  - 首启直达主界面：无档案时按标准映射自动建档，输入设置页仅 B 按住 1 秒进入
  - 十字键上下切换聚焦动作（只影响显示，不影响判定）
  - test_home_screen 无头套件（24 套件 / 44,994 断言全绿）
  - 重建的签名 APK（27,150,559 字节，证书 e1841a17…32e046）

affects: [06-practice-loop, 07-feedback-loop, 09-device-acceptance]

actuals:
  tokens: 16141
  tasks: 3
  commits: 6

tech-stack:
  added: []
  patterns:
    - "HomeScreen 静态格式化函数 + AttemptLog 内部类：文案、去重、8 条上限都可在无头套件里断言"
    - "全项目唯一 drain：主界面每帧全量消费结果队列，先写 InputLog.outcome 再刷新显示"
    - "首屏即主界面：输入设置页默认隐藏，只作为 B 按住 1 秒的手动入口"

key-files:
  created:
    - mobile/src/ui/home_screen.gd
    - mobile/src/ui/home_screen.tscn
    - mobile/tests/unit/test_home_screen.gd
  modified:
    - mobile/src/ui/main.gd
    - mobile/tests/core_runner.gd
    - tools/make_font_subset.py
    - mobile/assets/fonts/required_glyphs.txt
    - mobile/assets/fonts/NotoSansSC-Subset.ttf
    - mobile/tools/gate-a.sh
    - mobile/ACCEPTANCE.md

key-decisions:
  - "首启不再显示输入设置页：无档案时按 InputSetup.seed_known_defaults() 自动建档并直接进练习"
  - "主界面取 ActiveSkill.last_outcome 显示聚焦动作；AttemptLog 以单调 seq 去重并只留最近 8 条"
  - "十字键边沿转给 HomeScreen.handle_button；tap 手势仍走 pressed_dict，不产生第二次解释"
  - "Y 清除档案后自动按标准映射重建并回主界面，不把用户丢回设置页（设置页只由 B 按住 1 秒进入）"
  - "设备行用 layout + 连接状态生成（setup 签名保持 runtime/layout/buffer 三参，不额外注入设备名）"

patterns-established:
  - "列表 UI 固定节点一次建成，10 Hz 刷新只改文本/样式，不在热路径增删节点"
  - "UI 文案全部走静态函数（clock_text / hero_* / split_name / progress_value），真机前即可断言"
  - "竖屏基准 720×1280 + canvas_items；所有尺寸按设计 token 直接落成 px"

requirements-completed: [JUDGE-02, JUDGE-05]  # JUDGE-04 的真机五码归因仍 Pending（ACCEPTANCE H5/H6）

coverage:
  - id: D1
    description: "首次启动直接进入竖屏主界面（无输入设置页；无档案时按标准映射自动建档）"
    requirement: JUDGE-02
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_home_screen.gd#_check_source_structure（_setup.visible = false / seed_known_defaults / 唯一 drain）"
        status: pass
    human_judgment: true
    rationale: "真机首次启动、蓝牙手柄配对与自动建档只能由人观察；无头套件只证明源码路径与文案逻辑"
  - id: D2
    description: "顶部状态 pill / 标题 / 计时 / 设备行，以及英雄卡的成功、失败、无判定三种显示"
    requirement: JUDGE-04
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_home_screen.gd#_check_hero_texts + _check_header_and_pad"
        status: pass
    human_judgment: true
    rationale: "竖屏排版、1 m 可读性与设计稿一致性必须真机目视"
  - id: D3
    description: "动作熟练度 5 行：名称、成功/尝试、hits/10 进度条、最近一次 ms"
    requirement: JUDGE-02
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_home_screen.gd#_check_skill_rows"
        status: pass
    human_judgment: false
  - id: D4
    description: "最近尝试最多 8 条、新结果在前、同一 seq 只显示一次"
    requirement: JUDGE-05
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_home_screen.gd#_check_attempts"
        status: pass
    human_judgment: false
  - id: D5
    description: "十字键上下切换聚焦动作，到头不回绕；B 按住 1 秒进入输入设置"
    requirement: JUDGE-02
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_home_screen.gd#_check_focus + _check_source_structure"
        status: pass
    human_judgment: true
    rationale: "真实手柄的十字键边沿与按住 B 1 秒的时序只能在真机验收"
  - id: D6
    description: "字形闭世界：home_screen.gd/tscn 登记 + 1074 字符子集 + GLYPH_OK"
    verification:
      - kind: integration
        ref: "bash mobile/tools/gate-a.sh（GLYPH_OK chars=1074）"
        status: pass
    human_judgment: false
  - id: D7
    description: "新签名 APK：27,150,559 字节，证书 e1841a17…32e046，16 KB 对齐、仅 arm64"
    verification:
      - kind: integration
        ref: "bash mobile/tools/gate-b.sh（证书指纹一致 / 16 KB 对齐 / badging）"
        status: pass
    human_judgment: false

duration: 24min
completed: 2026-11-06
status: complete
---

# Phase 5 Plan 8: 竖屏主界面与首启直达 Summary

**720×1280 竖屏主界面替换横屏练习屏：首启按标准映射自动建档直接练习，顶部区/英雄卡/5 行熟练度/8 条最近尝试/手柄状态卡全部按 design/mobile.html 落地，并重建证书一致的 APK。**

## Performance

- **Duration:** 24 min
- **Started:** 2026-11-06T10:15:02Z
- **Completed:** 2026-11-06T10:30:07Z
- **Tasks:** 3
- **Files modified:** 12

## Accomplishments

- 新增 `home_screen.tscn/gd`：竖屏 720×1280，14 个契约 unique 节点齐全（顶部状态 pill、标题、计时、设备行、英雄卡、5 行动作熟练度、8 条最近尝试、手柄状态卡）。
- 首启路径改为「标准映射自动建档 → 直接进练习」：输入设置页默认不可见，只从主界面按住 B 1 秒进入；Y 清档案后也自动重建，不把用户丢回设置页。
- 英雄卡读取当前聚焦动作的 `last_outcome`；成功显示 `Outcome.detail`、失败显示 `Outcome.message`；最近尝试以单调 `seq` 去重、只保留 8 条；十字键上下切换聚焦（不回绕，不影响判定）。
- 主界面保持全项目唯一的结果 drain 点：每帧全量消费队列、先写 `InputLog.outcome(...)` 再刷新显示，`main.gd` 零 drain。
- 字形闭世界扩展到 `home_screen.gd/tscn` 并重生成子集（1074 字符），`gate-a.sh` 增加 `home_screen.gd` 语法检查并通过 `GLYPH_OK`。
- 重建 APK：27,150,559 字节，证书 `e1841a17…32e046`，16 KB 对齐、仅 arm64；`ACCEPTANCE.md` 新增第 7 节 H1–H13 真机验收项。

## Task Commits

1. **Task 1: 竖屏 HomeScreen 骨架 + 自动建档首启** - `31b31d1` (feat)
2. **Task 2: 英雄卡 / 熟练度 / 最近尝试 / 手柄状态** - `55d573d` (feat)
3. **Task 3: 无头格式套件 + 字体登记 + 重建 APK** - `f78d77b` (test)
4. **Follow-up fix: 未建档手柄的连接状态** - `4ac92f7` (fix)

**Plan metadata:** `4e61375` + 本次更新（docs: complete 竖屏主界面 plan）

## Files Created/Modified

- `mobile/src/ui/home_screen.gd` — 竖屏主界面：唯一 drain、英雄卡、5 行熟练度、8 条尝试、十字键聚焦、静态格式化函数
- `mobile/src/ui/home_screen.tscn` — 720×1280 场景，14 个契约 unique 节点 + 设计 token 样式
- `mobile/src/ui/main.gd` — 首屏改 HomeScreen；设置页默认隐藏；B 按住 1 秒入口；边沿转发；Y 清档案后自动重建
- `mobile/tests/unit/test_home_screen.gd` — 主界面无头套件（文案 / 上限 / 去重 / 焦点 / 节点 / 源码结构 / 竖屏）
- `mobile/tests/core_runner.gd` — 注册 `home_screen` 套件（24 套件）
- `tools/make_font_subset.py` — 登记 `home_screen.gd/tscn`
- `mobile/assets/fonts/required_glyphs.txt` + `NotoSansSC-Subset.ttf` — 重新生成的字形清单与子集（1074 字符）
- `mobile/tools/gate-a.sh` — 语法检查增加 `res://src/ui/home_screen.gd`
- `mobile/ACCEPTANCE.md` — 第 7 节 H1–H13 真机验收表与本次 APK 事实

## Decisions Made

- **首屏即主界面**：`_build_input_setup()` 默认 `visible = false`；`_leave_practice(show_setup)` 区分「回主界面」与「打开设置页」。断连回主界面（显示「手柄未连接」），不再回设置页。
- **Y 清档案后自动重建**：保持「设置页只由 B 按住 1 秒进入」的约束；清档案等价于回到标准映射，而不是把用户丢进引导流程。
- **设备行不注入设备名**：保持 `HomeScreen.setup(runtime, layout, buffer)` 三参接口不变，设备行用 `layout` + 连接状态生成（`Xbox 手柄 · 手柄已连接` / `手柄已连接 · 标准映射` / `手柄未连接`）。
- **摇杆卡显示原始轴值**：`setup` 不接收 `AxisMapping`，主界面不新增第二份归一化；LS/RS 取轴 0/1、2/3 的原始值，回中时显示「回中」。
- **固定行节点 + 10 Hz 改文本**：5 行熟练度与 8 行尝试一次建成，刷新只改 `text` / `value` / 样式，避免每帧增删节点。

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] drain 计数被注释里的字面量污染**
- **Found during:** Task 3（运行 test_home_screen）
- **Issue:** 源码结构断言 `_count(home, "pop_outcomes(") == 1` 数到 2 次 —— 一次是真实调用，一次是文件头注释里的 `pop_outcomes()`。
- **Fix:** 注释改为「运行时的结果队列」，保留「唯一 drain」的语义，不放宽断言。
- **Files modified:** `mobile/src/ui/home_screen.gd`
- **Verification:** `test_home_screen` 的 `_check_source_structure` 通过，24 套件全绿。
- **Committed in:** `f78d77b`（Task 3 提交）

**2. [Rule 1 - Bug] 未建档手柄被误报为「手柄未连接」**
- **Found during:** 收尾复核（首启无档案 / 未识别品牌路径）
- **Issue:** `HomeScreen` 的 `_buffer` 只在 `setup()` 里注入；认不出的手柄不会自动建档，`setup()` 永远不调用，顶部设备行与底部摇杆卡停在场景静态文案「未连接」；无手柄首启时状态 pill 还会停在「训练中」。
- **Fix:** `_ready()` 先刷新设备行/状态 pill；`main.gd` 在设备已绑定但未进入练习时用空布局调用 `setup()`（`layout_confirmed` 仍为假，零判定），让主界面拿到真实 `buffer`。
- **Files modified:** `mobile/src/ui/home_screen.gd`, `mobile/src/ui/main.gd`
- **Verification:** `test-core.sh` 24 套件 / 44,994 断言全绿；`make_font_subset.py --check` 仍为 1074 字符（无新增字形）。
- **Committed in:** `4ac92f7`

### Plan/环境差异（非代码缺陷）

**3. project.godot 竖屏与自动建档已在计划执行前落地**
- 计划 Task 1 列出的 `orientation=1` / 720×1280 与 `seed_known_defaults()` 自动建档已由前置提交 `06b2cdf` 完成；本计划只补主界面并保持这两条路径，未重复改动 `project.godot` 的竖屏段。验收命令中的两条 grep 均通过。

**4. practice_screen.gd/tscn 保留但不再实例化**
- 计划允许「可保留但不再实例化」。为避免无意义改动，这两个文件保持原样；`gate-a.sh` 仍对 `practice_screen.gd` 做语法检查，旧的 `practice_wiring` 套件继续通过。

**5. 设备名未进主界面（设计稿示例为具体型号）**
- 受 `HomeScreen.setup(runtime, layout, buffer)` 三参接口约束，主界面拿不到 `PadSampler.device_name()`；设备行改用布局 + 连接状态。功能不受影响，真机验收表按实际显示判定。

---

**Total deviations:** 2 auto-fixed（Rule 1）+ 3 计划/环境差异
**Impact on plan:** 无范围蔓延；两次修复都是连接状态/源码结构断言的正确性问题，判定与统计路径未变。

## Issues Encountered

- Godot 4.7.2 的 `--import` 偶发 SIGSEGV 未触发（本次一次成功）；`gate-a.sh` / `test-core.sh` 自带的有界重试保持原样。
- 无头 `--script` 下根视口尺寸为 0，因此场景验收用 `.tscn` 源码结构断言（节点块 + `unique_name_in_owner`），不依赖实例化后的尺寸。

## User Setup Required

None - 无外部服务配置。真机验收（ACCEPTANCE 第 7 节 H1–H13）需要人手与手柄，属于闸门 C 的常规流程。

## Next Phase Readiness

- 主界面与自动建档已就绪，Phase 6 可以直接消费 `HomeScreen` 的聚焦动作与 `ActiveSkill` 统计。
- 待真机确认：竖屏排版、Xbox / DualSense 的十字键边沿、B 按住 1 秒入口、蓝牙断连后的「手柄未连接」状态。
- **JUDGE-04 的真机五码归因仍保持 Pending**：本计划只保证失败原因原样来自 `Outcome.message`，五码在真机上的逐条归因按 `ACCEPTANCE.md` 第 7 节 H5/H6 验收，不在本计划勾选。
- 已知遗留：无（Phase 5 金标 55/29、MEASURED 12、DECIMATION 252、桌面 302 项均未变化）。

---

## Self-Check: PASSED

- 文件存在：`mobile/src/ui/home_screen.gd` / `home_screen.tscn` / `mobile/tests/unit/test_home_screen.gd`
- 提交存在：`31b31d1`、`55d573d`、`f78d77b`、`4ac92f7`、`4e61375` 均在 HEAD 祖先链上
- 闸门：`test-core.sh` 24 套件 / 44,994 断言 / `TESTS_DONE failures=0`；`gate-a.sh` `GLYPH_OK chars=1074`；`gate-b.sh` 证书 `e1841a17…32e046`；`check_desktop.sh` 302/302

---

*Phase: 05-judge-parity-decimation*
*Completed: 2026-11-06*
