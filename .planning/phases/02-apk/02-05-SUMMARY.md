---
phase: 02-apk
plan: 05
subsystem: docs

tags: [android, build-manual, clean-clone, acceptance-form, adb, device-smoke, keystore-backup, gate-b]

# Dependency graph
requires:
  - phase: 02-apk
    plan: 01
    provides: "mobile/tools/doctor.sh 五项构建断言；引擎 / 模板 / JDK / SDK / 密钥库的唯一定义处"
  - phase: 02-apk
    plan: 02
    provides: "mobile/tools/gate-a.sh 七步闸门与可导出工程（.godot/ 冷启动导入路径）"
  - phase: 02-apk
    plan: 03
    provides: "810 字形清单 + 双字体子集；字形闸门的 GLYPH_OK 分支"
  - phase: 02-apk
    plan: 04
    provides: "mobile/tools/gate-b.sh、证书 SHA-256 指纹、26,793,210 B 的签名 APK 与全部实测数据"
provides:
  - "mobile/BUILD.md（328 行）：八节重建手册 —— 版本表 / 顺序陷阱 / 双 SHA-512 / 密钥库 / 一条命令 / 指纹 / 九条排错 / 干净机器步骤"
  - "mobile/tools/verify_clean_export.sh：干净 clone 内重跑闸门 B + 五边车已跟踪预检 + 零漂移断言，脏树 exit 2"
  - "mobile/ACCEPTANCE.md：第 0 节前置条件 + 两台不同 OEM × 四项观察 + 记录字段 + 密钥库备份（§4）+ 第二台机器重导出（§5）"
  - "mobile/tools/device-smoke.sh：adb 装机 / 启动 / 存活 / 截图，DEVICE_SMOKE_OK|FAIL，支持 --dry-run"
  - "mobile/README.md 与根 README.md：目录现状不再描述一个已经不存在的仓库"
affects: ["09"]

# Actuals (#2632) — 与计划的 estimate 同尺度（chars/4 over realized diff）
actuals:
  tokens: 7632
  tasks: 3
  commits: 4
  plan_head_before: bdf63af0b261474b8f84a1caea06a62ebffff0ce
  plan_head_after: ae1ff50c85bc8b2a68e3d7d29cea7355876883e2

tech-stack:
  added:
    - "零新增依赖：本计划只写文档与 bash 脚本，调用已存在的 adb / aapt2 / gate-b"
  patterns:
    - "文档不定义第二份断言：版本前缀、SHA-512、密钥库默认值全在 doctor.sh；校验全在 gate-b.sh，BUILD.md 只给入口"
    - "入口守卫与内部断言的范围可以不同，但必须写清为什么：脏树守卫只判已跟踪文件（clone 复制的是提交），clone 内零漂移断言判全量（抓 .gitignore 漏项与未提交边车）"
    - "失败信息直指修法所属层：边车未跟踪在跑闸门之前就点名，否则只会以 `?? …/*.import` 出现，诱人去改 .gitignore 而不是补提交"
    - "`set -euo pipefail` 下每个可能失败的赋值都必须落在 if/&& 或紧跟显式 token 分支；最典型的坑是裸 `pid=$(pidof …)` 在进程已崩时当场终止脚本"
    - "工具路径按 SDK 根目录拼绝对路径，不吃 PATH：aapt2 只在 build-tools/36.1.0/ 里，裸名字会让脚本跑到一半才 127"

key-files:
  created:
    - mobile/BUILD.md
    - mobile/ACCEPTANCE.md
    - mobile/tools/verify_clean_export.sh
    - mobile/tools/device-smoke.sh
  modified:
    - mobile/README.md
    - README.md

key-decisions:
  - "BUILD.md 的第六节抄两种写法（连续小写 64 hex + 冒号大写 32 组）：apksigner 与 keytool 各打一种，只写一种会让另一半人以为对不上"
  - "verify_clean_export.sh 的入口守卫只判 `--untracked-files=no`：clone 只复制提交，未跟踪文件不可能让 clone 假绿（只会让它失败）；真正让绿失效的是已跟踪文件与 HEAD 不一致"
  - "clone 内零漂移断言保持全量（含未跟踪），与入口守卫范围不同且把理由写进注释：两处都写 --untracked-files=no 就再也抓不到漏提交的边车"
  - "五个 Godot 边车在跑闸门之前逐个 `ls-files --error-unmatch` 点名：跑完再发现只会得到一条 `??`，读者的第一反应是改 .gitignore"
  - "device-smoke.sh 先断言 adb/aapt2 可执行再进 --dry-run：工具缺失也走同一条 fail-closed 出口，不允许「脚本自己崩了但没打印 token」"
  - "启动 activity 从 `aapt2 dump badging` 解析而不硬编码：硬编码一份会与 export_presets.cfg 脱钩，症状是「装上了但起不来」"
  - "ACCEPTANCE.md 明确写出动作名是**机械覆盖**（make_font_subset.py → required_glyphs.txt → glyph_coverage.gd）：首屏只显示 SKILL_COUNT = 5 不逐条列五个名字，不写清会被当成成功标准 2 少测一半"
  - "INFRA-04 仍不标记完成：本计划交付判据与可执行部分，成功标准 1/2/4 必须在两台不同 OEM + 真手柄上由人打勾，无设备时不得声称通过"

patterns-established:
  - "「文档给入口、脚本给断言」的分工：BUILD.md 第五节只说 gate-b.sh 依次做五段，不复制其中任何一条校验命令"
  - "验收表格式：每格写「看什么 + 合格的判据 + 勾选框」，失败必须记「哪一项 / 看到什么 / 截图文件名」三件事，不接受「有点问题」"
  - "记录字段必须是可核对字符串（介质类型 + 地点 + 日期、64 位摘要），不接受「已备份」「导出来了」"

requirements-completed: []

# Coverage metadata (#1602)
coverage:
  - id: D1
    description: "一个没参与过项目的人只读 BUILD.md 就能在新机器上装齐工具链、生成/恢复密钥库、跑出一条命令并核对指纹"
    requirement: INFRA-04
    verification:
      - kind: other
        ref: "bash 断言 20 条：八节标题各一次、两个 SHA-512 字面量、`shasum -a 512 -c` 3 处、包名/模板/build-tools/密钥库变量/-storepass:env/JAVA_HOME/gate-b.sh 全在，wc -l = 328 ≥ 120"
        status: pass
      - kind: other
        ref: "负向断言：`GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=` 0 处、`-storepass <字面>` 0 处（T-02-15）"
        status: pass
    human_judgment: false
  - id: D2
    description: "干净 clone 上真的重跑一次闸门 B，并断言 clone 零漂移（成功标准 5 的机械旁证）"
    requirement: INFRA-04
    verification:
      - kind: integration
        ref: "bash mobile/tools/verify_clean_export.sh → rc=0，末行 `✓ 干净 clone 重导出成功：闸门 B 全绿，工作区无漂移`；clone 内产出 26,793,210 B 的同尺寸 APK"
        status: pass
    human_judgment: false
  - id: D3
    description: "脏工作区以退出码 2 拒绝，且守卫只看已跟踪文件（用户未跟踪的 design/ 不该挡住闸门）"
    requirement: INFRA-04
    verification:
      - kind: other
        ref: "反例：给已跟踪的 mobile/README.md 追加一个换行 → rc=2，输出 `M mobile/README.md`；还原后 git diff --quiet 通过"
        status: pass
      - kind: other
        ref: "正向那一跑发生在 design/ 与 .planning/milestone.lock 仍在未跟踪状态时 → 仍 rc=0，证明守卫范围可机械核对"
        status: pass
    human_judgment: false
  - id: D4
    description: "五个 Godot 边车在 clone 里是已跟踪文件（漏提交要被报成上游缺陷，而不是神秘漂移）"
    requirement: INFRA-04
    verification:
      - kind: integration
        ref: "verify_clean_export.sh 输出 `✓ 五个导入边车在 clone 里都是已跟踪文件`，逐个 ls-files --error-unmatch 点名"
        status: pass
    human_judgment: false
  - id: D5
    description: "缺设备时 device-smoke.sh fail-closed，不静默通过；--dry-run 不需要设备"
    requirement: INFRA-04
    verification:
      - kind: integration
        ref: "bash mobile/tools/device-smoke.sh → rc=1，stderr `DEVICE_SMOKE_FAIL 未检测到设备（adb devices 为空）`，stdout 为空"
        status: pass
      - kind: integration
        ref: "ANDROID_SDK_ROOT=/nonexistent → rc=1，stderr `DEVICE_SMOKE_FAIL 找不到 adb: /nonexistent/platform-tools/adb`"
        status: pass
      - kind: other
        ref: "bash mobile/tools/device-smoke.sh --dry-run → rc=0，输出含 aapt2 绝对路径 …/build-tools/36.1.0/aapt2 与期望 token"
        status: pass
    human_judgment: false
  - id: D6
    description: "验收表把成功标准 5 的两半变成可填的落点，而不是散文"
    requirement: INFRA-04
    verification:
      - kind: other
        ref: "grep 15 条关键串全中：不同 OEM / 模拟器 / SKILL_COUNT = 5 / ° ± → ✓ ✗ / ro.product.manufacturer / 第 4 节密钥库离线备份 / 第 5 节第二台干净机器重导出 / 备份 1 位置 / 备份 2 位置 / 口令存放位置 / 恢复演练 / 证书 SHA-256 / 机械覆盖 / required_glyphs.txt；wc -l = 149 ≥ 50"
        status: pass
    human_judgment: false
  - id: D7
    description: "回归红线未动：桌面 230 项、闸门 A、闸门 B 全部仍绿"
    verification:
      - kind: integration
        ref: "bash tools/check_desktop.sh → `✓ 230 项检查全部通过，名称与基线逐项一致`；gate-a → GLYPH_OK chars=810；gate-b → `✓ 闸门 B 通过`"
        status: pass
    human_judgment: false

# Metrics
duration: 8min
completed: 2026-11-04
status: complete
---

# Phase 02 Plan 05: 构建手册 + 干净 clone 重导出 + 真机验收表 Summary

**把「我这台机器能导出」换成可重放的证据：328 行的重建手册、clone 里真跑一次的闸门 B、以及一张缺设备就必然留白的验收表**

## Performance

- **Duration:** 8 min
- **Started:** 2026-11-04T15:07:19Z
- **Completed:** 2026-11-04T15:15:00Z
- **Tasks:** 3
- **Files modified:** 6（4 新建 / 2 修改）
- **Commits:** 4（3 个任务 + 1 个运行态时间戳）

## Accomplishments

- `mobile/BUILD.md`（328 行，八节）：版本表逐字取自 RESEARCH，`--version` 明写前缀匹配；
  第二节把「先设 `JAVA_HOME` 再第一次 `--import`」写成顺序陷阱并给出检查与修法；第三节两条
  SHA-512 以**字面量**落在可直接执行的 `shasum -a 512 -c -` 行里；第四节密钥库只出现变量名
  与 `-storepass:env`；第六节抄入两种写法的证书 SHA-256 并标注 Phase 9 核对义务；第七节九条
  排错（P1/P2/P3/P7/P8/P10/P11/P13 + 边车漏提交）
- `mobile/tools/verify_clean_export.sh`：入口只判已跟踪文件并以 `exit 2` 拒绝脏树；clone 后先
  逐个点名断言五个 Godot 边车是已跟踪文件，再跑 `gate-b.sh`，最后判全量零漂移。实跑 rc=0，clone
  内重新导出 26,793,210 B 的同尺寸签名 APK
- 脏树反例实测：给已跟踪的 `mobile/README.md` 追加换行 → `rc=2` 并打印 `M mobile/README.md`；
  还原后 `git diff --quiet` 通过。正向那一跑发生在 `design/` 仍未跟踪时，证明守卫没把用户的
  在制品当成脏树
- `mobile/tools/device-smoke.sh`：adb / aapt2 按 `${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}`
  拼绝对路径；工具缺失、无设备、装不上、起不来、5 秒内退出、截图空文件全部走同一条
  `DEVICE_SMOKE_FAIL` 出口。无设备实跑 rc=1、stdout 为空；`ANDROID_SDK_ROOT=/nonexistent` 也能
  打印 `DEVICE_SMOKE_FAIL 找不到 adb: …` 而不是 127
- `mobile/ACCEPTANCE.md`（149 行）：第 0 节四项前置条件（doctor device / 两台不同 OEM / 真手柄 /
  模拟器与单台手机的禁令）；第 1 节两台手机 × 四项观察，「看什么 + 判据 + 勾选框」逐格写；
  第 2 节记录字段 + 证书 SHA-256 + 动作名机械覆盖说明；第 4 节密钥库离线备份四行；
  第 5 节第二台干净机器重导出
- 回归红线未动：`bash tools/check_desktop.sh` 230 项全绿，`gate-a.sh` `GLYPH_OK chars=810`，
  `gate-b.sh` `✓ 闸门 B 通过`
- 两份 README 同步：`mobile/README.md` 删掉「Phase 1 只有配置副本」，扩成真实目录树并写明
  导入边车属于提交物；根 `README.md` 要点加 `BUILD.md` 链接、目录地图改成「Godot 工程 +
  工具链闸门 + 构建手册」、`tools/` 补 `make_font_subset.py`

## Task Commits

Each task was committed atomically:

1. **Task 1: 换个人照这份手册就能重导出** - `4ff17e9` (feat) — `mobile/BUILD.md`
2. **Task 2: 干净 clone 上重跑闸门 B，并同步两份 README** - `bcbd2c1` (feat) —
   `verify_clean_export.sh` + 两份 README
3. **Task 3: 真机验收表 + 可执行的装机冒烟** - `ae1ff50` (feat) — `device-smoke.sh` + `ACCEPTANCE.md`

穿插一个运行态提交（见偏差 1）：

- `c8e7c60` (chore) — `.planning/state.json` 的 `updated_at` 一行

**Plan metadata:** _(docs commit follows this file)_

## Files Created/Modified

- `mobile/BUILD.md`（新建，328 行）— 唯一的重建依据；四段下载/校验/解压/安装与八节结构
- `mobile/tools/verify_clean_export.sh`（新建，92 行）— 调度 + 边车预检 + 零漂移；`apksigner`
  出现 0 次（不复制校验逻辑）
- `mobile/ACCEPTANCE.md`（新建，149 行）— 闸门 C 的唯一合法落点
- `mobile/tools/device-smoke.sh`（新建，176 行）— 装机 / 启动 / 存活 / 截图；`if ! pid=` 恰好一处
- `mobile/README.md`（改写，+23/-9）— 真实目录树、边车属于提交物、三条入口命令
- `README.md`（修改，+4/-4）— 要点、目录地图两行、进一步阅读一行

产物（gitignored）：`mobile/build/fifa-trainer.apk` 26,793,210 B、
`mobile/build/device-smoke-<serial>.png`（本计划**未产生** —— 没有设备）。

## Decisions Made

- **BUILD.md 的第六节抄两种指纹写法**：`apksigner` 打连续小写 64 hex，`keytool -list -v` 打冒号
  大写 32 组。只写一种，另一半人会以为对不上，然后去「修」其中一边。
- **入口守卫只判已跟踪文件，clone 内断言判全量**：两个范围不同是刻意的 —— 前者防止「clone 里跑
  旧代码」，后者抓 `.gitignore` 漏项与未提交边车。注释里把这条差异写出来，否则下一个人会以为
  守卫漏了未跟踪文件。
- **边车预检放在跑闸门之前**：跑完再发现只会得到一条 `?? …/*.import`，读者的第一反应是去改
  `.gitignore`；提前点名则直接说「上游漏提交」。
- **`device-smoke.sh` 先断工具再进 `--dry-run`**：工具缺失也走同一条 fail-closed 出口，
  `DEVICE_SMOKE_FAIL 找不到 aapt2: <绝对路径>` 比 `command not found` 有用得多。
- **activity 从 badging 解析**：硬编码会与 `export_presets.cfg` 脱钩，症状是「装上了但起不来」。
- **ACCEPTANCE.md 写清动作名是机械覆盖**：首屏只显示 `SKILL_COUNT = 5` 与最长中文串，不逐条列
  五个动作名。这是刻意的（一次性验收面板不是 UI），但不写下来会被当成成功标准 2 少测一半。
- **INFRA-04 不标记完成**：本计划交付判据与可执行部分。成功标准 1/2/4 必须在两台不同 OEM +
  真手柄上由人打勾；没有设备时声称通过，就是这一阶段唯一无法自动化的信任点被伪造。

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `gsd_run` / `gsd-tools query` 在本机不存在，STATE/ROADMAP 手工更新**

- **Found during:** 开工第一步（`command -v gsd_run` 为空；`gsd --help` 是本交互式 CLI v1.15.0，
  没有 `query` 子命令）
- **Issue:** 执行器协议要求用 `gsd_run query state.advance-plan` / `roadmap.update-plan-progress`
  等句柄更新状态。这些句柄不可用，直接照抄会得到一串 127。
- **Fix:** 按 `.planning/STATE.md` 与 `.planning/ROADMAP.md` 的现有格式手工编辑：推进
  `completed_plans` 到 10 / `total_plans` 10、补 02-05 的 Per-Plan Metrics 行、追加本轮决策、
  更新 Session Continuity；ROADMAP 把 02-05 标 `[x]` 但**保留 Phase 2 的 `- [ ]`**（见下条）。
- **Files modified:** `.planning/STATE.md`、`.planning/ROADMAP.md`
- **Verification:** 两份文件的结构与 `bdf63af` 那次提交同形；没有出现占位符或 TODO。
- **Committed in:** 本 SUMMARY 同批的 docs 提交

**2. [Rule 1 - Bug] `verify_clean_export.sh` 的脏树提示会把 `\n` 原样打出来**

- **Found during:** Task 2 写作时（未运行即发现）
- **Issue:** `echo "…再运行：\n"` 在 bash 内建 `echo` 下不解释转义，输出会带一个字面 `\n`。
- **Fix:** 去掉 `\n`，改成两行 `echo`。
- **Files modified:** `mobile/tools/verify_clean_export.sh`
- **Verification:** 反例实跑输出干净（`先提交（或还原）下面这些路径再运行：` 下一行就是路径）。
- **Committed in:** `bcbd2c1`

**3. [Rule 3 - Blocking] `.planning/state.json` 是已跟踪文件且被运行态改脏，挡住入口守卫**

- **Found during:** Task 2 提交后首次运行 `verify_clean_export.sh`
- **Issue:** 该文件只有 `updated_at` 一行差异（orchestrator 启动时写的），但它是**已跟踪**文件，
  会让 `--untracked-files=no` 守卫 `exit 2`。守卫不能为它放宽 —— 放宽一次，这条守卫就再也挡
  不住真代码的旧状态。
- **Fix:** 单独一个 `chore(02-05)` 提交收录这一行时间戳，让工作区对**已跟踪**文件干净，守卫的语义
  保持不变。
- **Files modified:** `.planning/state.json`
- **Verification:** 提交后 `git status --porcelain --untracked-files=no` 为空；正向那一跑 rc=0。
- **Committed in:** `c8e7c60`

**4. [Rule 2 - Missing Critical] 根 `README.md` 第 72 行仍写着「Phase 2 的边界」**

- **Found during:** Task 2 改写根 README 时
- **Issue:** 计划只点了三处（`:6` / `:22` / `:24`），但「进一步阅读」里对 `mobile/README.md` 的
  描述还停在「Phase 2 的边界」—— 本计划完成后这句话就是错的，而它正好指向被改写的那份文件。
- **Fix:** 同一文件内补一句，改成指向三条入口命令，并加上 `BUILD.md` / `ACCEPTANCE.md` 的链接。
  只改这一句，不扩写。
- **Files modified:** `README.md`
- **Verification:** `grep -c 'mobile/BUILD.md' README.md` = 2；`grep -c 'Phase 2 的边界' README.md` = 0。
- **Committed in:** `bcbd2c1`

---

**Total deviations:** 4（2 个阻塞绕行 / 1 个自捉 bug / 1 处文档事实修正）
**Impact on plan:** 没有放宽任何一条校验。两处阻塞绕行都是环境事实（缺 CLI 句柄、运行态文件被写脏），
修法都是「在既有语义下绕过去」，不是「把挡路的东西删掉」。

## Issues Encountered

**干净 clone 的首次 `--import` 出现过一次段错误（1/5）**

- **现象：** 第一次跑 `verify_clean_export.sh` 时，clone 内 `gate-a.sh` 的无头导入在
  `reimport | NotoSansSC-Subset.ttf` 处 `Segmentation fault: 11`，闸门 A 因此判红。
- **复现尝试：** 手工在 `/tmp` 冷 clone 后导入 3 次、脚本重跑 1 次，共 4 次全部 rc=0。
- **处置：** 不加重试、不放宽闸门 —— 给导入加重试会把「真崩」也吞掉，而这条闸门存在的理由正是
  「不许用重跑换绿」。**记录在这里**：如果后续在别的机器上高频率复现，应先查 Godot 4.7.2 的
  字体导入线程崩溃，而不是改脚本。
- **对结论的影响：** 本计划的最终验证是在同一台机器上**连续两次** rc=0（Task 2 之后一次、
  Task 3 之后一次），两次的 clone 都是全新 `mktemp` 目录。

**`mobile/build/` 里的 APK 被闸门 B 重写了三次**，每次都是 26,793,210 B —— 导出在这台机器上可复现。

## User Setup Required

- `GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD` 必须由人在当前 shell 里 export（从密码管理器取）。
  本机通过 `$HOME/.fifa-trainer/credentials.sh` 加载，该脚本在仓库外。
- **成功标准 5 的两半仍未闭合，且只能由人闭合**：
  1. 密钥库的离线备份（两处不同址介质 + 口令分开存放 + 一次恢复演练）→ `ACCEPTANCE.md` 第 4 节；
  2. 第二台干净机器按 `BUILD.md` 重导出并核对指纹 → `ACCEPTANCE.md` 第 5 节。
- **成功标准 1/2/4 仍未闭合**：需要两台不同 OEM 手机 + 一只真手柄。`adb devices` 当前为空，
  `device-smoke.sh` 因此以 `DEVICE_SMOKE_FAIL` 退出 —— 这是**正确**的结果，不是缺陷。

## Known Stubs

None. 四个新文件都是完整实现：`verify_clean_export.sh` 与 `device-smoke.sh` 的每条失败路径都有
token 与退出码；两份文档没有占位符或「待补」段落。

唯一的「空」是**刻意的空**：`ACCEPTANCE.md` 的记录字段留白，等真人填。

## Threat Flags

None — 本计划新增的是文档与构建期/验收期脚本，没有引入运行期网络、认证或数据访问面。

威胁登记的缓解措施落地情况：

- **T-02-14（Repudiation，真机验收结论）**：`ACCEPTANCE.md` 要求记录厂商 / 型号 / 系统版本 /
  截图文件名 / 证书指纹；两台不同 OEM 才允许打勾；模拟器与单台手机被明令排除。
- **T-02-15（Information disclosure，密钥库章节）**：`BUILD.md` 只写变量名与「口令在密码管理器」；
  负向断言 `GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=` 0 处、`-storepass <字面>` 0 处。
- **T-02-16（Tampering，「另一台机器能重导出」只靠声明）**：`verify_clean_export.sh` 在
  `git clone` 出来的目录里真跑闸门 B 并断言零漂移；文件头写明它只证明仓库状态足够。
- **T-02-SC（供应链）**：零安装。只调用已存在的 `adb` / `aapt2` / `gate-b.sh`。

## Next Phase Readiness

- **Phase 2 的自动化部分到此收口**：闸门 A / B、反例自测、干净 clone 重导出全绿，
  桌面 230 项未动。
- **Phase 2 的人工部分全部落在 `mobile/ACCEPTANCE.md`**：第 0 节四项前置条件、第 1 节两台 × 四项、
  第 4 节密钥库备份、第 5 节第二台机器重导出。这四块都留白，所以：
  - ROADMAP 的 Phase 2 复选框**保持未勾**；
  - `INFRA-04` **不标记完成**。
- Phase 3 可以开工：它只依赖 Phase 1，不依赖真机结论。但 Phase 4 的真机输入层会继承
  `device-smoke.sh` 的装机/启动骨架 —— 届时把「读轴」从人工观察推进到可断言，是这个脚本的下一步。
- `BUILD.md` 第七节第 9 条（边车漏提交）是这一轮唯一的「文档先于故障」条目：它描述的失败模式在
  `verify_clean_export.sh` 里已经被提前拦住，两边指的是同一件事。

---

*Phase: 02-apk*
*Completed: 2026-11-04*

## Self-Check: PASSED
