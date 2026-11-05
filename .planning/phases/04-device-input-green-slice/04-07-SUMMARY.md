---
phase: 04-device-input-green-slice
plan: 07
subsystem: android-release-artifact-and-device-acceptance
tags: [android, apk, apksigner, adb, real-device, acceptance, blocked, ux, single-screen-diagnostic]

requires:
  - phase: 04-device-input-green-slice
    plan: 06
    provides: 练习屏 / 结果横幅 / %DebugPanel / PAD_DIAG·PAD_AXIS·PAD_DEV 1 Hz 日志；ACCEPTANCE §6 空表
  - phase: 04-device-input-green-slice
    plan: 05
    provides: OnboardingFlow / 引导屏 / 四步探针 / 校准 / 布局确认的 S1–S11 流程
  - phase: 02-android-toolchain
    provides: gate-b.sh 导出链路、release keystore、apksigner 36.1.0、adb 36.0.2

provides:
  - "mobile/build/fifa-trainer.apk：Phase 2 同一把钥匙签名的 arm64 release APK（27,012,856 B；v2+v3；证书 e1841a17…32e046）"
  - "mobile/ACCEPTANCE.md §6：D0 失败的可核对原文（探针三次拒绝 + 停止屏 events_motion=1931）、D1–D6 未执行原因、用户要求单屏输入检测的记录"
  - "阻塞事实：release APK 不可调试，adb run-as 被拒，D1/D2 的 controllers.json 读取/改写通道不可用"

affects: [phase-5-detectors, phase-9-release, next-plan-single-screen-input-diagnostic]

actuals:
  tokens: 6300
  tasks: 1
  commits: 3

plan_head_before: 71a968fdc575a2d69246ec71ca1e4eba87d139fa
plan_head_after: c350258bec1a544da5e4dee9345eceaa4b077965

tech-stack:
  added: []
  patterns:
    - "真机验收先出包再开表：被验收的包与被提交的代码必须是同一个；本计划零源码改动"
    - "D0 的停止条件按屏幕原文判定，不按「设备看起来正常」推断；停止屏出现即 D0 失败并停止 D1–D6"
    - "验收表只写可核对原文：屏幕整句、adb 整行输出、logcat 整行；未执行的格子写「未执行 + 原因」，不预打勾"
    - "用户口头反馈也是真机证据：把「看不懂 / 一直显示重来」原话记进表，而不是转述成「体验一般」"

key-files:
  created: []
  modified:
    - mobile/ACCEPTANCE.md
    - .planning/STATE.md

key-decisions:
  - "D0 判失败：探针在 20:15:38–20:18:22 连续拒绝（两轴同时动了 margin 0.001；上与右落在同一根轴 2/2；上下没有互为反号 上轴2符号-1/下轴3符号1），且 20:15:50 出现停止屏「没有收到摇杆事件（events_motion = 1931）」；按 ACCEPTANCE §6 的停止条件立即停止，不继续填 D1–D6"
  - "停止屏的文案与日志自相矛盾：同一时段 PAD_DIAG ev_m=2633 ev_b=70，轴事件实际到达；「本机在当前阶段没有送上任何摇杆事件」是待修缺陷，不是本机缺轴事件。本计划只记录，不改代码"
  - "release APK 不可调试：adb shell run-as com.fifaskill.trainer ... 返回 run-as: package not debuggable；D1 的档案原文与 D2 的外层 key 改写都无法执行。计划把 run-as 当成可用通道，这是计划缺陷，需要可调试构建或别的档案出口"
  - "用户（2026-11-05 20:38）否决多步引导，要求改成单屏输入检测：一屏显示所有按键与摇杆，无状态机、无第一步/第二步顺序依赖，按/推哪个就亮哪个，识别错了由用户指出。该要求是 Rule 4 架构变更，未在 04-07 实施（本计划明令零源码改动），交回 orchestrator 重新规划"
  - "D2 的拒绝面需要两只轴映射不同的真手柄；现场只有 Xbox Series X Controller（getevent -pl 仅列出 Xbox Wireless Controller），没有 DualSense，拒绝面未执行"
  - "杆量记录：本次只捕获到第 2/4 步与第 3/4 步的截图；第 1/4 步以「20:15:42 已显示第 2/4 步」间接证明，不伪造第 1 步截图"

patterns-established:
  - "真机验收的失败也是交付物：D0 的失败原文 + 停止屏 + 用户原话，比一张「全部通过」的表更能说明下一版要改什么"
  - "凡是清单依赖但 artifact 不提供的通道（run-as / 档案读取），在第一次尝试时就记成计划缺陷，不在后续步骤里反复撞同一堵墙"
  - "用户拒绝流程设计时，执行器不在验收计划里改代码；记录需求、返回阻塞、让下一轮计划承担设计与重建"

requirements-completed: []
# INPUT-01 / INPUT-03 / INPUT-04 / ONBOARD-01 / ONBOARD-02 在本计划**全部不宣布完成**：
# - D0 失败，首次启动零触摸走完未证明（ONBOARD-01 / ONBOARD-02）。
# - D1 未执行，轴落盘与「无 device index」未在真机证明（INPUT-03）。
# - D2 未执行，换手柄重探与复用门两面未证明（成功标准 3 后半）。
# - D3–D6 未执行，布局确认 / 一次判定 / 两发独立 / 输入体检均未证明（INPUT-01 / INPUT-04 / INPUT-05）。
# 依据 plan 的 Flagged Assumptions 与「无真机记录不得勾选」禁令。

coverage:
  - id: D0
    description: "全新手机首次启动：卸载 → 安装 → 只用手柄走完配对唤醒 / 四步探针 / 中点+满量程校准 / 布局确认"
    verification:
      - kind: manual
        ref: "mobile/ACCEPTANCE.md §6 D0（2026-11-05 20:14–20:38）"
        status: fail
    human_judgment: true
    failure: "探针三次拒绝；停止屏「没有收到摇杆事件（events_motion = 1931）」出现，按停止条件 D0 判失败；用户明确表示流程看不懂"
  - id: D1
    description: "轴探测落盘：controllers.json 的 axes.rs_x / axes.rs_y index+sign，无 device index 字段"
    verification:
      - kind: manual
        ref: "mobile/ACCEPTANCE.md §6 D1"
        status: fail
    human_judgment: true
    failure: "未执行：run-as: package not debuggable（release APK 不可调试），且 D0 未走完、档案未生成"
  - id: D2
    description: "换手柄必须重探 + 复用门接受/拒绝两面"
    verification:
      - kind: manual
        ref: "mobile/ACCEPTANCE.md §6 D2"
        status: fail
    human_judgment: true
    failure: "未执行：D1 通道不可用；现场只有一只 Xbox 手柄，没有 DualSense 做拒绝面"
  - id: D3–D6
    description: "布局建议 + 按键确认 / 一次绿色搓射 / 两发独立 / 输入体检"
    verification:
      - kind: manual
        ref: "mobile/ACCEPTANCE.md §6 D3–D6"
        status: fail
    human_judgment: true
    failure: "未执行：D0 失败，从未到达布局确认屏与练习屏"

duration: 28min（本次 continuation；Task 1 于前一会话完成，APK 构建 19:22）
completed: 2026-11-05
status: blocked
---

# Phase 4 Plan 07: 签名 APK + 真机 D0–D6 走查 Summary

**签名 APK 与证书指纹核对完成；真机 D0 在探针重试循环与「没有收到摇杆事件（events_motion = 1931）」停止屏处失败，D1–D6 未执行；用户否决多步状态机，要求改成单屏输入检测 —— 本计划没有改一行源码，把失败原文与需求一起交回规划**

## Performance

- **Duration:** 本次 continuation 20:14–20:42（约 28 min）；Task 1 于前一会话完成（APK 构建时间 2026-11-05 19:22:57 CST）
- **Tasks:** 1 / 2 完成（Task 1 完成；Task 2 是 `checkpoint:human-verify`，D0 失败后按停止条件终止）
- **Files modified:** 1（`mobile/ACCEPTANCE.md`）；STATE / ROADMAP 在收尾 docs 提交中更新
- **Commits:** 3（`a2617a4` Task 1、`0b97276` 等待设备的阻塞记录、`c350258` D0 失败记录）

## Accomplishments

- **Task 1（前一会话，已完成）**：`gate-b.sh` 产出 `mobile/build/fifa-trainer.apk`；独立 `apksigner verify --verbose --print-certs` 通过，证书 SHA-256 `e1841a17bda43307cdfc8e9e757c672a6a91b7fd60ea86e715afd461ba32e046` 与 `BUILD.md` 第六节逐字一致；`unzip -l` 无 x86_64 / .DS_Store / keystore；包名 `com.fifaskill.trainer`、versionCode 1、versionName 0.1.0、arm64-v8a、minSdk 24、27,012,856 字节。
- **D0 的「真首次」落点**：`adb uninstall com.fifaskill.trainer` 返回 `Success`，`pm list packages` 无该包，`run-as` 返回 `unknown package`；`adb install -r` 返回 `Success` / `Install command complete in 720 ms`。
- **D0 的实际观察**：20:14:24 首屏「已连接：Xbox Series X Controller / 按任意键继续 / 手柄已就绪 / 设备：Xbox Series X Controller」；20:15:42 已到「轴探测 / 第 2/4 步」；20:15:50 到「第 3/4 步」后同一秒出现停止屏；20:15:38 / 20:15:46 / 20:18:22 三次探针拒绝原文已逐字抄进表。
- **停止条件执行**：屏幕出现「输入事件缺失 / 本机在当前阶段没有送上任何摇杆事件。 / 停止 / 没有收到摇杆事件（events_motion = 1931）：本机可能不发送轴事件，请记录并停止（D0 判失败）」，按 `ACCEPTANCE.md` §6 的停止条件立即停止，没有继续把 D1–D6 写成「通过」。
- **日志旁证**：同一时段 `PAD_DIAG ev_m=2633 ev_b=70 poll=0 dt50=7.87 dt95=94.54 dtmax=3173.86 in_tid=1 proc_tid=1`，`PAD_DEV name=Xbox Series X Controller guid=58626f7820576972656c65737320436f`；轴事件确实到达，停止屏的「没有送上任何摇杆事件」与计数自相矛盾。
- **D1/D2 的硬阻塞**：`adb shell run-as com.fifaskill.trainer ls -l files/profiles` 返回 `run-as: package not debuggable: com.fifaskill.trainer`；release APK 不可调试，`controllers.json` 的读取与改写通道不存在。
- **用户需求入库**：用户（Stephen）在真机操作后明确表示「一直显示重来重来重来」「我都看不明白」，要求把多步引导改成单屏输入检测；原话与要求已写进 `ACCEPTANCE.md` §6 与 `STATE.md` Blockers。

## Task Commits

Each task was committed atomically:

1. **Task 1: 导出签名 APK 并核对证书指纹（不碰源码）** — `a2617a4` (docs)
2. **Task 2 阻塞记录: 记录真机清单阻塞（Task 2 等待设备）** — `0b97276` (docs)
3. **Task 2: 真机 D0 走查并记录失败与未执行项** — `c350258` (docs)

**Plan metadata:** 见本次最终 docs 提交（SUMMARY / STATE / ROADMAP）

## Files Created/Modified

- `mobile/ACCEPTANCE.md`（+76 / −64）— §6 D0–D6：本次结论、用户要求、D0 的 12 行实测原文、D1–D6 的逐行「未执行 + 原因」
- `.planning/STATE.md`（收尾提交）— 当前计划状态改为 blocked、Blockers 增加 D0 失败 / run-as 不可用 / 用户要求单屏检测、Session Continuity 更新
- `.planning/ROADMAP.md`（收尾提交）— 04-07 保持未勾选，追加本次真机结果与待重新规划的说明

## Decisions Made

- **D0 判失败，且不继续填 D1–D6**：停止屏原文已经出现，继续填只会把「没跑到」写成「通过」；这是计划明确要求的停止条件。
- **停止屏是待修缺陷，不是本机缺轴事件**：`events_motion = 1931` 与 `PAD_DIAG ev_m=2633` 同时存在；`_check_motion_stop()` 把「本状态 60 帧内没有新事件」误报成「本机没有送上任何摇杆事件」。本计划不改代码，留给下一个代码计划。
- **release APK 不可调试是计划缺陷**：D1/D2 的 `run-as` 命令把 release 包当成可调试包；后续计划要么出 debuggable 构建，要么换一个不改源码的档案出口（例如导出前把档案通过 `user://` 以外的路径暴露），不能拿源码静态检查冒充真机证据。
- **D2 拒绝面没有第二只手柄**：现场只有 Xbox Series X Controller；`getevent -pl` 只列出 `Xbox Wireless Controller`。按 orchestrator 约束 8，拒绝面明确标为「未执行」，不声称成功标准 3 完整。
- **用户要求单屏输入检测是 Rule 4 架构变更**：多步状态机（rest → 四步探针 → 中点/满量程校准 → 布局确认）被用户否决；新形态是一屏显示所有按键与摇杆、无状态切换、按/推哪个亮哪个。04-07 的 `files_modified` 只有 `ACCEPTANCE.md`，且计划明令零源码改动，因此未实施；需要新计划、新测试、重新构建与重新验收。

## Deviations from Plan

### Auto-fixed Issues

**None** — 本计划没有任何源码改动；`git status --porcelain mobile/src mobile/tools tools` 为空，`shared/skills_config.json` 零 diff。

### 计划级阻塞（不是自动修复）

**1. [Rule 4 - 架构变更] 用户否决多步引导，要求单屏输入检测**
- **Found during:** Task 2 的 D0 真机走查
- **Issue:** 用户在探针重试循环中明确表示流程看不懂（「一直显示重来重来重来」「我都看不明白」），要求把多步状态机改成单屏按键/摇杆检测：无状态切换、无第一步/第二步顺序依赖，按/推哪个就亮哪个，识别错了由用户指出。
- **Action:** STOP。不在 04-07 改源码（违反本计划硬约束），把原话与要求写进 `mobile/ACCEPTANCE.md` §6 与 `STATE.md` Blockers，交回 orchestrator 重新规划。
- **Impact:** 成功标准 2/3/4/5 均未闭合；04-07 不能宣布完成。

**2. [Rule 3 - 计划缺陷] release APK 不可调试，D1/D2 的 run-as 通道不可用**
- **Found during:** D1 第一次尝试（2026-11-05 20:38）
- **Issue:** `adb shell run-as com.fifaskill.trainer ls -l files/profiles` 返回 `run-as: package not debuggable: com.fifaskill.trainer`。D1 的档案原文、D2 的外层 key 改写与档案恢复都依赖这个通道。
- **Action:** 记录为计划缺陷；D1/D2 全部标「未执行」，不伪造档案内容。
- **Impact:** 成功标准 3 后半无法在本 artifact 上验收。

**3. [Rule 1 - 候选缺陷] D0 停止屏把「1 秒内没有新事件」误报成「本机没有送上任何摇杆事件」**
- **Found during:** D0 第 3/4 步（2026-11-05 20:15:50）
- **Issue:** 屏幕原文「没有收到摇杆事件（events_motion = 1931）」与同一时段 `PAD_DIAG ev_m=2633` 矛盾；`_check_motion_stop()` 只比较本状态起点与当前累计值，用户停下来读屏幕超过 60 帧就会触发。
- **Action:** 只记录，不改代码（本计划零源码改动）；留给下一个代码计划修。
- **Impact:** 这是用户「莫名其妙」体验的直接来源之一；下一版单屏检测不应再依赖这种「无事件即失败」的看门狗。

**4. [计划缺口] D2 拒绝面需要两只轴映射不同的真手柄，现场只有 Xbox**
- **Found during:** D2 准备
- **Issue:** `adb shell getevent -pl` 只列出 `Xbox Wireless Controller`（event13），没有 DualSense。
- **Action:** 按 orchestrator 约束 8，D2 的接受面与拒绝面都标「未执行」，不声称成功标准 3 完整。
- **Impact:** 复用门的两面仍未在真机证明。

**5. [验证证据] 第 1/4 步没有单独截图**
- **Found during:** D0 记录整理
- **Issue:** 连续截图从 20:15:35 开始，20:15:42 已经是第 2/4 步；第 1/4 步的屏幕没有被捕获。
- **Action:** 表中写「未捕获到第 1/4 步的单独截图；第 2/4 步的显示证明第 1 步已通过」，不伪造截图。
- **Impact:** 第 1 步的证据是间接的；不影响 D0 的失败结论。

### 环境差异（不是计划分歧）

- 本环境没有 `gsd_run` 命令：Step 0 的 protected-branch 查询、`state.*`、`roadmap.update-plan-progress`、`windows append` 均无法执行。按 orchestrator 的 `<sequential_execution>`（在 main 工作树上顺序执行）与 `.planning/config.json` 的 `git.branching_strategy: none`，在 `main` 上用普通提交（带 hooks，未用 `--no-verify`）。STATE / ROADMAP 用手工编辑更新；未做任何 `git update-ref` 之类的自愈操作。
- 手机在 20:18–20:29 之间断连过一次（屏幕「手柄断开，等待重连」）；重连后 `PAD_DIAG` 计数从 `ev_m=2633` 归零到 `ev_m=59`，`dt95` 一度到 4511 ms。这是蓝牙/省电行为，不是应用崩溃；记录在 D6 的扳机静止值一行里。

---

**Total deviations:** 5 个计划级阻塞（1 个用户架构变更、1 个 run-as 计划缺陷、1 个候选缺陷、1 个手柄缺口、1 个截图缺口）+ 1 条环境说明。
**Impact on plan:** 没有任何断言被放宽；D0 的失败原文、停止屏、用户原话与 `run-as` 错误都进了验收表。成功标准 2/3/4/5 全部保持未勾选。

## Known Stubs

None — 本计划没有新增源码；被验收的 APK 是 Task 1 的产物，未在验收过程中重建或修改。

## Issues Encountered

- **探针连续拒绝**：`两轴同时动了：margin 0.001 < 0.25，请只推一个方向`（20:15:38）；`上与右落在同一根轴（2/2），请只推右摇杆`（20:15:46）；`上下没有互为反号：上 (轴 2, 符号 -1)、下 (轴 3, 符号 1)，请检查手柄接线`（20:18:22）。
- **停止屏**：`输入事件缺失 / 本机在当前阶段没有送上任何摇杆事件。 / 停止 / 没有收到摇杆事件（events_motion = 1931）…`（20:15:50）。
- **手柄断连**：20:18–20:29 之间出现 `手柄断开，等待重连 / 重新连接后会重新走探针与校准。`；重连后用户再次尝试，仍被 `两轴同时动了：margin 0.004 < 0.25` 拒绝（20:38:20）。
- **用户反馈原话**：「一直显示重来重来重来」「我都看不明白」「不要弄成这种状态机的模式，就在一个屏里边把所有按键检测事解决了」。

## User Setup Required

None — 本计划未安装任何依赖；手机与手柄由用户提供，`adb` 使用本机 `$HOME/Library/Android/sdk/platform-tools/adb`。`mobile/build/` 为 gitignored 证据目录。

## Next Phase Readiness

- **必须重新规划**：把多步引导改成单屏输入检测（按钮 + 摇杆实时显示，无状态机、无顺序依赖）。这需要新的计划、新的 UI 测试、重新构建 APK，并重新走真机验收。
- **D1/D2 的通道要先解决**：release APK 不可调试；新计划要么产出 debuggable 构建（仅用于验收），要么设计一个不依赖 `run-as` 的档案证据出口，并在计划里写清「源码静态检查不算真机证据」。
- **D2 需要第二只手柄**：Xbox + DualSense（或任意两只轴映射不同的手柄）；只有一只时不得声称成功标准 3 完整。
- **成功标准 2/3/4/5 仍未闭合**：`REQUIREMENTS.md` 与 `ROADMAP.md` 不得勾选；Phase 4 不得宣布完成。
- **已可复用的证据**：`mobile/build/phase4-d0-seq/d0-logcat.txt`（1 Hz `PAD_DIAG` / `PAD_AXIS` / `PAD_DEV` 整行）、`mobile/build/phase4-D0-*.png`（首屏、第 2/4 步、第 3/4 步、三次拒绝、停止屏、断连屏）、`mobile/build/phase4-D0-install-and-runas.txt`（uninstall / install / run-as 原文）。

---

*Phase: 04-device-input-green-slice*
*Status: blocked — D0 失败，D1–D6 未执行*
*Completed: 2026-11-05*

## Self-Check: PASSED

- `mobile/ACCEPTANCE.md` §6 D0–D6 无空单元格（空单元格计数 0；未执行项写的是「未执行 + 原因」）
- `c350258` 是 HEAD 祖先；`git diff 71a968f..c350258` 只含 `mobile/ACCEPTANCE.md` 与 `.planning/STATE.md`
- `git status --porcelain mobile/src mobile/tools tools shared` 为空（0 行）
- §6 内没有 `- [x]`（计数 0）；`ROADMAP.md` 的 `04-07-PLAN.md` 仍为 `- [ ]`
- 4 张关键截图与 install/run-as 文本、d0-logcat.txt 均存在于 `mobile/build/`（gitignored）并在表中点名
- 成功标准 2/3/4/5 未被勾选：`REQUIREMENTS.md` 与 `ROADMAP.md` 未做任何完成标记
