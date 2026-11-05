---
phase: 04-device-input-green-slice
plan: 09
subsystem: mobile-onboarding-single-page-input-setup
tags: [godot, gdscript, onboarding, single-page, axis-pair, calibration, trigger-rest, profile, apk, glyph-subset]

requires:
  - phase: 04-device-input-green-slice
    plan: 08
    provides: 引导 UX 修复 / 诊断覆盖层 / 16 套件 1335 断言 / APK 27,046,027 B
  - phase: 04-device-input-green-slice
    plan: 07
    provides: 两次真机失败的原文（扳机轴 0.000 → -1.000、57 行 ambiguous_axes）与用户「不要进步式测试」的原话
  - phase: 04-device-input-green-slice
    plan: 04
    provides: PadStateBuffer / PadSampler / ProfileStore / AxisMapping / Calibration / DeviceProfile
  - phase: 04-device-input-green-slice
    plan: 06
    provides: 练习屏 / ResultBanner / %DebugPanel / 1 Hz PAD_DIAG 日志
  - phase: 02-android-toolchain
    provides: gate-b.sh 导出链路、release keystore、apksigner 36.1.0

provides:
  - "InputSetup 纯逻辑：observe / active_pair / cycle_pair / toggle_x_sign / toggle_y_sign / range_ready / center / scale / trigger_rest / build_profile / reset（零引擎依赖，零判定）"
  - "一页式 input_setup_screen（10 个唯一节点）：8 行轴表 + 圆点 + 轴对/符号/量程/中点/扳机静止 + 手柄操作行"
  - "组合根换首启路径：无档案 → 设置页；有可用档案 → 直接进练习；TapRuntime 只在练习屏可见时 tick"
  - "test_input_setup 第 17 个套件（87 条断言，含扳机跳变与并列轴对两个真机缺陷）"
  - "mobile/build/fifa-trainer.apk 重建（27,067,065 B，证书 e1841a17…32e046 不变，v2 通过，只含 arm64）"
  - "mobile/ACCEPTANCE.md §6：D0 改成 8 步单页操作说明 + 本次待填证据表；两次尝试的历史原文保留"

affects: [04-07-real-device-walkthrough, phase-5-detectors, phase-9-release]

actuals:
  tokens: 14515
  tasks: 3
  commits: 3

plan_head_before: 4c4dbe7b4663e3e0aa7d5a1876635576639c5d51
plan_head_after: 9cff0085a815a2fc3398e081efe184126368cd07

tech-stack:
  added: []
  patterns:
    - "一页式识别的三条机械保证：没有状态变量（只有「当前看到什么」）→ 没有分支能判失败 → 没有定时器能超时"
    - "轴对并列时按「两轴都更晚变化」决胜：1 秒窗口里旧的一对还没退出，只比峰峰值会永远判给候选表里靠前的那一对"
    - "扳机静止值 = 观测到的最小值；设备基线的一次性跳变（0.000 → -1.000）按「两轴同值且停住」识别，不给分"
    - "archive 可行性先于落盘：`build_profile` 的 scale 为 0 时按 1.0 存，并用 `DeviceProfile.from_dict` 往返断言证明这份档案不会被 `load_all()` 丢弃"
    - "无头集成验证：临时 SceneTree 脚本注入合成 motion 事件驱动真实设置屏，A 保存 → 文件 → 读回逐字段核对（临时脚本不提交）"

key-files:
  created:
    - mobile/src/core/input_setup.gd
    - mobile/src/ui/input_setup_screen.gd
    - mobile/src/ui/input_setup_screen.tscn
    - mobile/tests/unit/test_input_setup.gd
    - mobile/build/04-09-apk-report.txt（gitignored 证据）
  modified:
    - mobile/src/ui/main.gd
    - mobile/tests/core_runner.gd
    - mobile/tools/gate-a.sh
    - tools/make_font_subset.py
    - mobile/assets/fonts/required_glyphs.txt（1045 → 1048 字符）
    - mobile/assets/fonts/NotoSansSC-Subset.ttf
    - mobile/ACCEPTANCE.md

key-decisions:
  - "首启路径彻底离开 OnboardingFlow：`%Onboarding` 节点与脚本保留但永不 setup、永不可见；这不是删功能，是把它降级为复用门的后续工作"
  - "复用判据从「四项 index+sign 逐项比较」改为「同 key + 结构可用」：没有探针就没有本次观测值，拿档案自己比自己等于假绿；四项比较仍留在 DeviceProfile.can_reuse，等将来重新引入「探一次」的界面"
  - "A 的两个前置（无设备 / 无轴对）只给提示、不切屏、不记失败：这是「没有可保存的映射」，不是判定失败"
  - "布局在设置页一次写定：`suggest_layout` 认出品牌就用，认不出按 Xbox；空布局会让练习屏进入「请返回引导重选」的死角，而引导屏已经不在首启路径上"
  - "圆点与轴表用两套刷新节奏：圆点每帧（手感），文本 10 Hz（Label 赋值的文本整形是整帧最贵的操作）"
  - "`INPUT_SETUP` 每秒一行 logcat：没有 run-as 时，这一行就是「页面认了哪一对、符号是什么、量程到没到」的可核对原文"
  - "APK 必须重建：04-07 若拿 27,046,027 B 的旧包重走 D0，装上去的仍是四步探针"

patterns-established:
  - "用户的流程否决要落到结构上：不是把「四步」文案改软，而是让页面里不存在可以表达「第几步」的变量"
  - "无头集成检查可以覆盖「屏幕 + 保存 + 读回」整条链：合成 motion 事件喂真实场景，比只测纯函数更接近真机失败点"
  - "已知设备缺陷（扳机基线跳变）写成一条带证据的规则，并在测试里用真机的真实序列（0.000 × 20 帧 → -1.000 × 30 帧）钉住"

requirements-completed: []
# INPUT-01 / INPUT-02 / INPUT-03 / INPUT-04 / ONBOARD-01 / ONBOARD-02 在本计划**全部不宣布完成**：
# 单页流程的代码、断言与 APK 都已交付，但「真机上能不能走完 D0」「屏幕 1 m 外看不看得清」
# 仍只能由 04-07 的屏幕原文回答。断言绿不等于真机通过。

coverage:
  - id: D1
    description: "首启只有一页：8 行轴表 + 圆点 + 轴对/符号/量程/中点/扳机静止，没有步骤计数、没有倒计时、没有自动失败、没有『重来』屏"
    requirement: ONBOARD-01
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_input_setup.gd#全套 10 段（无 pair / 选对 / 扳机跳变 / 人工切换 / 符号 / 量程门槛 / 中点量程 / rest=min / 档案 / reset）"
        status: pass
      - kind: other
        ref: "无头：临时 SceneTree 脚本实例化 input_setup_screen.tscn，10 个唯一节点全部存在；主场景 180 帧无错，首屏为『没有检测到手柄』"
        status: pass
    human_judgment: true
    rationale: "『不想再看到重来』『想测多久就测多久』只能由真机上的连续操作感受判断；无头只能证明没有状态机与定时器"
  - id: D2
    description: "轴对识别：推哪一对就选哪一对；扳机从 0.000 跳到 -1.000 不抢轴对；LB/RB 可人工覆盖且不被自动识别打断"
    requirement: INPUT-02
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_input_setup.gd#_check_push_selects_pair / _check_trigger_jump_does_not_win / _check_manual_cycle"
        status: pass
    human_judgment: false
  - id: D3
    description: "按 A 保存 per-device profile 并进入练习；档案可往返序列化（不会被 load_all 整份丢弃）；同一设备再次启动直接进练习"
    requirement: INPUT-03
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_input_setup.gd#_check_profile（含 DeviceProfile.from_dict 往返）"
        status: pass
      - kind: other
        ref: "临时 SceneTree 集成检查：合成 motion → A → controllers.json → load_all 得到 1 条档案，pair=2/3 sign=-1/1 rest=-1/-1"
        status: pass
    human_judgment: true
    rationale: "真机上 `Input.get_joy_name()` / guid 是否非空、档案是否真的落到 user://，只有 04-07 的覆盖层档案页能证明"
  - id: D4
    description: "重建签名 APK：与旧包同一把钥匙、只含 arm64、v2 验签通过、16 KB 对齐"
    requirement: ONBOARD-02
    verification:
      - kind: other
        ref: "bash mobile/tools/gate-b.sh（末行 ✓ 闸门 B 通过）+ apksigner verify --print-certs"
        status: pass
    human_judgment: false

duration: 21min
completed: 2026-11-05
status: complete
---

# Phase 4 Plan 09: 单页输入设置 Summary

**把「四步探针 + 校准 + 布局确认」整块换成一页：8 根轴的实时表 + 一个跟着右摇杆动的圆点，推、按、翻符号、换轴对、清空、保存全部当场生效；扳机静止值改成观测到的最小值，两次真机失败的根因（0.000 → -1.000 的基线跳变污染每个窗口）在数据层消失**

## Performance

- **Duration:** 21 min
- **Started:** 2026-11-05T13:34Z（约）
- **Completed:** 2026-11-05T13:56Z
- **Tasks:** 3 / 3
- **Files modified:** 14 个受版本控制的文件（含 1 个字体子集二进制）+ 1 个 gitignored 报告

## Accomplishments

- **页面里不再有「第几步」这种东西**：`InputSetup` 没有状态机，`input_setup_screen.gd` 没有步骤计数、没有倒计时、没有重试计数、没有失败分支（`grep` 四条零命中）。页面从可见到按 A 之间一直在采样，用户想测多久就测多久。
- **一屏看全**：左边 8 行轴表（值 + 10 格条形 + 长窗口 min/max，扳机行多一个 `rest`），右边 240×240 圆点 + 十字准星；`%Pair` / `%Signs` / `%Range` / `%Center` / `%Trigger` / `%Help` / `%Footer` 七块状态全部逐字来自纯函数。
- **轴对识别改用「最近 1 秒谁在动」**：候选 `(0,1) (2,3) (4,5) (6,7)`，得分 `min(span_x, span_y)`，并列时取两轴都更晚变化的那一对；LB/RB 可人工覆盖，B 清空后回到自动。
- **扳机缺陷在数据层修掉**：`trigger_rest(axis) = 观测到的最小值`。真机序列（0.000 × 20 帧 → -1.000 × 30 帧）在套件里逐帧复现，结果是「扳机对不给分、轴对仍是未识别」；用户推右摇杆后立刻切到 `(2,3)`。
- **保存即进练习**：A 写 `user://profiles/controllers.json` → 发 `profile_saved(layout)` → 组合根进练习；启动时同 key 已有可用档案就直接进练习，不再走任何探针。
- **组合根瘦身**：`main.gd` 从「分派 OnboardingFlow」变成「设置页 / 练习屏二选一」，`TapRuntime.tick()` 只在练习屏可见时调用；按钮边沿仍然只有一个消费者。
- **第 17 个套件**：`test_input_setup` 87 条断言（16 套件 / 1335 → 17 套件 / 1422）。
- **三道闸门全绿**：`test-core`（`TESTS_DONE failures=0`）、`gate-a`（`GLYPH_OK chars=1048` + `✓ res://src/ui/input_setup_screen.gd`）、`check_desktop`（302/302）、lint（`LINT_OK files=28`）、lint 自测（56/56）。
- **新 APK**：27,067,065 字节（旧 27,046,027，+21,038），证书 `e1841a17…32e046` 逐字不变，`Verified using v2 scheme: true`，只含 `arm64-v8a`。

## Task Commits

Each task was committed atomically:

1. **Task 1: InputSetup 纯逻辑 + 无头套件** — `1966ca4` (feat)
2. **Task 2: 一页式 input_setup_screen + 组合根切换** — `1dd7248` (feat)
3. **Task 3: 重建 APK + ACCEPTANCE 的 D0 操作说明** — `9cff008` (docs)

**Plan metadata:** 见本次最终 docs 提交（SUMMARY / STATE / ROADMAP）

## Files Created/Modified

- `mobile/src/core/input_setup.gd`（新，369 行）— `observe` / `active_pair` / `cycle_pair` / `toggle_x_sign` / `toggle_y_sign` / `range_ready` / `center` / `scale` / `trigger_rest` / `build_profile` / `reset`；`_pair_score` / `_is_device_rest_jump` / `_usable_scale` / `_layout_for`
- `mobile/src/ui/input_setup_screen.gd`（新，305 行）— 每帧采样 + 圆点、10 Hz 文本、`handle_button` 六个分支、`_save_and_enter`、`debug_line`，以及 6 个静态格式化纯函数
- `mobile/src/ui/input_setup_screen.tscn`（新，144 行）— 10 个 `unique_name_in_owner` 节点 + `%Dot` 内的十字准星与圆点
- `mobile/src/ui/main.gd`（+142 / −162）— 首启路径换成设置页 / 练习屏；`_build_input_setup` / `_enter_practice` / `_leave_practice` / `_try_reuse_profile` / `_profile_usable`；1 Hz `INPUT_SETUP` 日志
- `mobile/tests/unit/test_input_setup.gd`（新，297 行）— 10 段、87 条断言
- `mobile/tests/core_runner.gd` — 注册 `input_setup`（16 → 17）
- `mobile/tools/gate-a.sh` — `check_script` 追加 `res://src/ui/input_setup_screen.gd`
- `tools/make_font_subset.py` — `CHAR_SOURCES` 追加 `.gd` / `.tscn`
- `mobile/assets/fonts/required_glyphs.txt` + `NotoSansSC-Subset.ttf` — 1045 → 1048 字符（新增 6、移除 5：main.gd 重写后不再出现的注释用字）
- `mobile/ACCEPTANCE.md` — §6 新增「本次待验收：27,067,065 B」+ 8 步单页 D0 + 空证据表；尝试一/二原文保留并标注「不得当作本版操作说明」
- `mobile/build/04-09-apk-report.txt`（gitignored）— size / 证书整行 / 包内容 / badging / 闸门结论

## Decisions Made

- **不在设置页驱动 `OnboardingFlow`**：保留节点与脚本（复用门将来要用），但 `_ready` 第一件事就是隐藏它，且永不 `setup()`；`onboarding_screen._process` 在 `_flow == null` 时早退，所以它连字都不会渲染。
- **复用判据降级为「同 key + 结构可用」**：没有探针就没有「本次观测到的四项 index+sign」，拿档案自己的值去比自己是假绿。`DeviceProfile.can_reuse` 仍是四项比较的唯一实现，`test_device_profile` 继续钉它；导入界面时再接回来（本计划的 `_try_reuse_profile` 注释写明了这条）。
- **扳机基线跳变按「两轴同值且停住 0.2 秒」识别**：只对 `(4,5)` 生效。理由：两根独立模拟轴不会停在同一个非零值上还保持不动；右摇杆推 45° 时两轴也可能同值，但那是真实手势，不能被压掉。
- **`scale = 0` 时按 1.0 存**：宁可写「未校准直通」，也不写一份 `Calibration.from_dict` 必然拒绝、进而让 `load_all()` 丢掉整份 `controllers.json` 的档案；`_check_profile` 用 `DeviceProfile.from_dict` 往返证明这一点。
- **无设备名的兜底是「未知手柄」**：`DeviceProfile` 要求 `device_name` 非空；空名字写进去下次启动会被整份丢弃，用户会莫名其妙回到设置页（无头集成检查先撞到了这条）。
- **布局在设置页一次写定**：`suggest_layout` 认得出品牌就用品牌，认不出按 Xbox。空布局会让练习屏进入「布局未确认，请返回引导重选」的死角，而引导屏已经不在首启路径上。
- **A 的两个前置只给提示**：没有手柄、还没有轴对时，`%Help` 多一行说明，不切屏、不记失败、不清空已采数据。

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] 两组轴对峰峰值并列时，候选表靠前的一对会永远赢**
- **Found during:** Task 1 第一次跑 `test_input_setup`（`改推 6/7 后轴对必须切到 (6,7)` 失败）
- **Issue:** 窗口是 1 秒（60 帧）。用户从 `(2,3)` 换推到 `(6,7)` 时，旧的一对还整段留在窗口里，两对得分都是 2.0；`score > best + 1e-9` 严格大于 → 永远保留候选表里更靠前的 `(2,3)`。屏幕上就是「推了没反应」——正是用户最反感的那类体验。
- **Fix:** 每轴记 `_last_change`（值真的变了的那一帧的帧号），并列时取 `min(last_change_x, last_change_y)` 更大的一对（「最近在动」的字面含义）。只在 `absf(score - best_score) <= 1e-9` 时启用，不改变得分本身的排序。
- **Files modified:** `mobile/src/core/input_setup.gd`
- **Verification:** `_check_push_selects_pair` 的「改推 6/7」断言通过；`_check_manual_cycle` 的人工覆盖不受影响
- **Committed in:** `1966ca4`（Task 1）

**2. [Rule 1 - Bug] `%Marker` 不是唯一节点，运行时 `Node not found`**
- **Found during:** Task 2 的无头冒烟（`godot --headless --path mobile --quit-after 180`）
- **Issue:** 圆点标记写在 `%Dot` 内部，但只有 10 个契约节点标了 `unique_name_in_owner`；脚本里 `@onready var _marker: Panel = %Marker` 找不到节点，`_ready` 直接报错。
- **Fix:** 改用路径 `$Dot/Marker`，保持「一页只有 10 个唯一节点」这条契约不被稀释。
- **Files modified:** `mobile/src/ui/input_setup_screen.gd`
- **Verification:** 无头冒烟不再有 `Node not found`；临时 SceneTree 检查打印 `SCENE_NODES=10 MISSING=[]`
- **Committed in:** `1dd7248`（Task 2）

**3. [Rule 1 - Bug] 首启时设置页默认不可见，屏幕会全白**
- **Found during:** Task 2 复查 `_build_input_setup`（写的时候先设了 `visible = false`）
- **Issue:** 只有「复用档案 / 保存成功」才会改可见性；新装的手柄既没有档案、也没有按过 A，于是没有任何路径把设置页显示出来。
- **Fix:** 建屏时默认可见（`visible = true`），由 `_enter_practice` 负责隐藏。
- **Files modified:** `mobile/src/ui/main.gd`
- **Verification:** 临时 SceneTree 脚本跑主场景：`SETUP_VISIBLE=true`、`TITLE=没有检测到手柄`、`PRACTICE_VISIBLE=false`
- **Committed in:** `1dd7248`（Task 2）

**4. [Rule 2 - Missing Critical] 设备名为空时会写出一份下次启动必被丢弃的档案**
- **Found during:** Task 2 的无头集成检查（`PROFILES=0 NOTICE=手柄档案已损坏，已丢弃`）
- **Issue:** `DeviceProfile.from_dict` 要求 `device_name` 非空；`Input.get_joy_name()` 返回空串时（无头环境、以及极少数设备刚连上的一瞬），`build_profile` 会写出 `device_name: ""`，下次启动 `ProfileStore.load_all()` 把整份文件当坏档删掉。
- **Fix:** 屏幕在保存前把空设备名替换成「未知手柄」；key 仍优先用 guid，所以同一只手柄的 key 不受影响。
- **Files modified:** `mobile/src/ui/input_setup_screen.gd`
- **Verification:** 同一集成检查复跑：`PROFILES=1`、`PROFILE key=name:未知手柄 pair=2/3 sign=-1/1 scale=0.950/0.950 rest=-1.000/-1.000 layout=xbox`
- **Committed in:** `1dd7248`（Task 2）

**5. [Rule 3 - Blocking] 组合根建屏顺序：练习屏必须先于 `add_child(_sampler)` 存在**
- **Found during:** Task 2 写 `_ready` 时的静态推演（`PadSampler._ready()` 会立刻 emit 设备列表）
- **Issue:** 回调里可能直接 `_try_reuse_profile()` → `_enter_practice()`；若练习屏还没建，`_practice.setup(...)` 在 null 上调用，第一次带档案启动就崩。
- **Fix:** 顺序固定为「建设置屏 → 建练习屏 → 建诊断覆盖层 → connect → add_child(_sampler) → 主动播种」；`_enter_practice` / `_leave_practice` 另加 null 守卫。
- **Files modified:** `mobile/src/ui/main.gd`
- **Verification:** 主场景无头 180 帧无错；`gate-a` 逐个脚本语法通过
- **Committed in:** `1dd7248`（Task 2）

### 计数修正（按实际树重算，没有放宽任何断言）

**6. [计数修正] 新 D0 段落里旧词是 0 条，但整份 ACCEPTANCE 仍有 15 条历史原文**
- 计划要求「D0 段落不再出现『第 N/4 步』『按 B 重来这一步』」，同时要求「保留尝试一/尝试二的历史记录」。两者只能在范围上区分：新的「本次待验收」段落实测 `第 [0-9]/4 步` = 0、`按 B 重来这一步` = 0；整份文件仍有 15 条，全部位于尝试一/尝试二的原文引用里（那是需要保留的证据）。历史段落前已加一句「不得当作本版操作说明」。
- 「倒计时」在新段落出现 3 次，全部是否定句（「没有倒计时」「无倒计时」「没有出现任何步骤提示、倒计时或失败屏」），不是残留描述。

**7. [计数修正] 字形的实际变化是 +6 / −5，不是「只增不减」**
- `required_glyphs.txt` 1045 → 1048。新增 6 个（`拽框维职观谈`）来自新 UI 文案与注释；移除 5 个（`弹摸晚普筛`）是因为 `main.gd` 被重写，那些只出现在旧注释里的字不再存在于任何字符来源。扫描器整文件扫描（含注释）是 Phase 2 定下的机制，清单是生成物，这一变化是它的正常行为，不是手工删字。
- `NotoSansSymbols2-Subset.ttf` 未变（没有新增符号字形；圆点标记刻意用 ASCII `>` 而不是 `▶`）。

### 计划未覆盖但我没有做的事（显式记录）

- **没有跑 D0–D6**：计划明写真机走查归 04-07；本次只出包与可核对报告。
- **没有改 `shared/skills_config.json`**：`git status --porcelain shared` 为空。
- **没有碰 `desktop/` 与 `design/`**：`design/` 一直是用户的未跟踪工作，全程未 `git add`。
- **没有删 `onboarding_screen.gd` / `onboarding_flow.gd` / `%Onboarding` 节点**：计划要求「保留但不再作为首启路径」。

### 环境差异（不是计划分歧）

- 本环境没有 `gsd_run`：Step 0 的 protected-branch 查询、`state.*`、`roadmap.update-plan-progress`、`windows append` 均无法执行。按 orchestrator 的 `<sequential_execution>`（主工作树顺序执行）与 `.planning/config.json` 的 `git.branching_strategy: none`，在 `main` 上用普通提交（带 hooks，未用 `--no-verify`）。STATE / ROADMAP 用手工编辑更新。
- **APK 口令来源**：`GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD` 不在环境里。按 `mobile/BUILD.md` §4 的本机做法（`set -a; . "$HOME/.fifa-trainer/credentials.sh"; set +a`）在同一 shell 内注入后跑 `gate-b.sh`；口令**没有**出现在任何文件、日志或命令行参数里，事后随 shell 退出消失。

---

**Total deviations:** 5 auto-fixed（4 个 Rule 1 bug、1 个 Rule 2 缺项、1 个 Rule 3 阻塞）+ 2 个计数修正
**Impact on plan:** 没有放宽任何断言。三条 Rule 1 都是「用户会直接撞上」的体验缺陷（推了不切换、首屏空白、运行时报错），Rule 2 防止一份档案把整份 `controllers.json` 拖下水。两处计数修正都按实际树重算并在此记录。

## Issues Encountered

- **`_sweep` 只扫一根轴时选不出轴对**：`min(span_x, span_y)` 要求两轴都在动，测试里先只扫了轴 2，`active_pair()` 返回 NONE，`_check_manual_cycle` 的前置断言先红。这是规则本身正确（单根轴的位移不能凑成一对），修的是测试的输入序列。
- **临时集成脚本的类型推断**：`var script_res := screen.get_script()` 报 `Cannot infer the type`，改 `var script_res: Variant`。与 04-08 的 `needle` 同类，只在临时脚本里出现，未进仓库。
- **`ObjectDB instances leaked` / `resources still in use` 退出告警**：只在临时 SceneTree 检查里出现（脚本自己 `PadSampler.new()` 不挂树 + lambda 连接），生产路径 180 帧冒烟无此告警。

## Known Stubs

None — 新页面没有占位数据：轴值来自 `PadStateBuffer.axis_value()`，轴对来自最近 1 秒的真实采样，档案来自用户当场的推杆；没有任何「coming soon」或空数组流到渲染。

## Threat Flags

None — 本计划不新增网络、文件写入或权限面。威胁登记里的两条 mitigate 有对应实现与断言：
T-04-18（自动识别不得静默落盘）→ 唯一写入点是 `_save_and_enter`，轴对/符号/量程全部先显示在屏幕上；T-04-19（设置页不得产生 Outcome）→ 组合根在 `_in_practice == false` 时连 `TapRuntime.tick()` 都不调用。

## User Setup Required

- **`GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD`**：只有重建 APK 需要。本次按 `mobile/BUILD.md` §4 从仓库外的 `~/.fifa-trainer/credentials.sh` 注入，未写进任何文件或命令行参数。下次重出包仍需在 shell 里 export（或 source 该文件）。
- 真机走查（04-07）需要：一台已连 adb 的手机 + 一只 Xbox 手柄；D2 的拒绝面还需要第二只轴映射不同的手柄（仍不具备）。

## Next Phase Readiness

- **04-07 可以重走 D0，但必须先卸载重装新包**：`adb uninstall com.fifaskill.trainer` → `adb install -r mobile/build/fifa-trainer.apk`（27,067,065 B，证书 `e1841a17…32e046`）。装 27,046,027 B 的旧包等于重跑一次四步探针。
- **这次的 D0 只有 8 步**（ACCEPTANCE §6「本次待验收」）：看轴表 → 推圆点 → 方向不对按 X/Y → 推到底几次 → A 保存 → 练习屏。页面里没有任何「第几步」，也没有倒计时；想测多久都行，B 清空后留在原页。
- **证据通道多了一条**：`adb logcat -s godot:I | grep INPUT_SETUP` 每秒一行，逐字给出 `pair=/sign=/ready=/span=/rest4=/rest5=`，不需要 `run-as`。
- **成功标准 2/3/4/5 仍未闭合**：`REQUIREMENTS.md` 与 `ROADMAP.md` 均未勾选；Phase 4 不得宣布完成。本计划只把「首启路径」从结构上修好，真机结论仍归 04-07。

---

*Phase: 04-device-input-green-slice*
*Completed: 2026-11-05*
*Status: complete（代码侧）— 真机清单仍在 04-07*

## Self-Check: PASSED

- `test -f mobile/src/core/input_setup.gd` / `.gd.uid` / `mobile/src/ui/input_setup_screen.gd` / `.gd.uid` / `.tscn` / `mobile/tests/unit/test_input_setup.gd` / `.gd.uid` 全部成立
- `test -f mobile/build/fifa-trainer.apk` 成立；`stat -f %z` = 27067065，与报告里的 `size=` 一致
- 三个提交都是 HEAD 的祖先：`1966ca4` / `1dd7248` / `9cff008`
- `grep -c 'unique_name_in_owner = true' mobile/src/ui/input_setup_screen.tscn` = 10；临时脚本打印 `SCENE_NODES=10 MISSING=[]`
- `bash mobile/tools/test-core.sh` → `TESTS_SUITES=17` / `TESTS_ASSERTIONS=1422` / `TESTS_DONE failures=0`
- `bash mobile/tools/gate-a.sh` → `GLYPH_OK chars=1048` + `✓ res://src/ui/input_setup_screen.gd` + `✓ 闸门 A 通过`
- `bash mobile/tools/gate-b.sh` → `✓ 闸门 B 通过`；证书 SHA-256 `e1841a17…32e046` 逐字不变
- `bash tools/check_desktop.sh` → 302/302；`python3 tools/lint_core_purity.py mobile/src/core` → `LINT_OK files=28`；`python3 tools/test_lint_core_purity.py` → 56/56；`python3 tools/make_font_subset.py --check` → 0
- `grep -c '^- \[x\]' mobile/ACCEPTANCE.md` → 0（本计划不宣布任何 D 项通过）
- `git status --porcelain shared desktop` 为空；`design/` 未被 `git add`
