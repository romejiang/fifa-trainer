---
phase: 02-apk
plan: 02
subsystem: infra

tags: [godot, pck, export-presets, shell-gate, gdscript, sidecar-uid, gitattributes]

# Dependency graph
requires:
  - phase: 02-apk
    provides: "mobile/tools/doctor.sh（godot 断言 + 命名子集入口）；仓库外 Godot 4.7.2-stable"
  - phase: 01-repo-split-config-single-source
    provides: "shared/skills_config.json 唯一真源 + mobile/assets/config/ 生成副本与 .sha256"
provides:
  - "mobile/project.godot：config_version=5、GL Compatibility、import_etc2_astc（可 headless 导入与打包）"
  - "mobile/export_presets.cfg：Android 预设，只出 arm64-v8a、零凭据键、include_filter 覆盖 .json 与 .sha256"
  - "mobile/src/smoke/{smoke_screen.gd,.tscn}：SKILL_COUNT / 最长中文串 / ° ± → ✓ ✗ / 八条轴实时读数的验收面板"
  - "mobile/tools/check_pack.gd：--main-pack 从 PCK 内读配置与 sidecar，EXPECTED_SKILLS 硬编码为 5"
  - "mobile/tools/gate-a.sh：闸门 A 唯一入口（配置校验 → 版本断言 → 导入 → 语法 → 打包 → 读包）"
  - "两个 *.gd.uid 导入边车已提交：脚本 UID 跨机器稳定，干净 clone 重新导入不产生未跟踪文件"
affects: [02-03, 02-04, 02-05]

# Actuals (#2632) — 与计划的 estimate 同尺度（chars/4 over realized diff）
actuals:
  tokens: 3645
  tasks: 2
  commits: 2
  plan_head_before: 912481b4fd60764165ae2e5068765ee5e397658f
  plan_head_after: 9d5da81dd516d123d71bf73bf5ade205bf497d65

tech-stack:
  added:
    - "Godot PCK 往返（--import → --export-pack → --main-pack），全程 headless，不需要导出模板 / JDK / 真机"
  patterns:
    - "从包里读、不从工程目录读：--main-pack 且不带 --path，res:// 才指向导出物（T-02-06）"
    - "硬编码期望值 + 注释说明为什么可以硬编码：EXPECTED_SKILLS = 5 与 BASELINE_SHA256 同构"
    - "配置校验必须是闸门第一步：副本被手改时下游断言全部假绿（T-02-04）"
    - "导入边车（*.gd.uid）是提交物而非缓存：提交后干净 clone 的 --import 零未跟踪文件"
    - "sha256sum 兼容 sidecar 取第一个空白字段，不裸比字符串（RESEARCH P15）"

key-files:
  created:
    - mobile/project.godot
    - mobile/export_presets.cfg
    - mobile/src/smoke/smoke_screen.gd
    - mobile/src/smoke/smoke_screen.gd.uid
    - mobile/src/smoke/smoke_screen.tscn
    - mobile/tools/check_pack.gd
    - mobile/tools/check_pack.gd.uid
    - mobile/tools/gate-a.sh
  modified:
    - .gitattributes

key-decisions:
  - "EXPECTED_SKILLS := 5 硬编码并带「禁止改成读到几条算几条」注释：动态读取会让这条断言永远绿（与 check_desktop.sh 的 BASELINE_SHA256 同构）"
  - "首屏 SYMBOLS 用 ASCII 连字符 U+002D，不用数学减号 U+2212：后者不在 required_glyphs.txt 里，会造成「字体闸门绿、屏幕豆腐」的假绿"
  - "读包一律 --main-pack 且不带 --path；带 --path 时 res:// 指回工程目录，读到的是源码而不是导出物"
  - "导出产品路径一律 \"$repo_root/mobile/build/...\" 绝对路径：--path 之后相对路径的锚点是工程目录（P2）"
  - "project.godot 本计划不写 [gui] theme/custom_font：字体资产 02-03 才生成，先写会指向不存在的资源"
  - "gate-a.sh 里不出现版本号字面量，版本断言只调 doctor.sh godot；安装路径 Godot-4.7.2.app 不算断言"
  - "*.gd.uid 边车随本计划提交，不进 .gitignore：它们是导入产物中的提交物，其余只有 mobile/.godot/ 与 mobile/build/ 是忽略物"
  - "INFRA-04 不在本计划标记完成：闸门 A 只证明「工程能打包、配置在包里」，签名 APK 与真机冒烟由 02-04/02-05 收口"

patterns-established:
  - "gate-a.sh 的文件头四段体例：一句话职责 / 缩进三格调用方式 / 这条命令证明什么 / 为什么这个顺序不能换"
  - "闸门脚本只用 ▸/✓/✗ + 中文人话，失败一律 >&2 且 exit 1；GDScript 探针显式 quit(0)/quit(1)"
  - "新增 Godot 文本类型统一进 .gitattributes 的 eol=lf 清单，*.ttf 声明 binary"

requirements-completed: []

coverage:
  - id: D1
    description: "一条命令在无模板 / 无 JDK / 无真机的机器上判定工程与配置是否就绪（约 3 秒，两次导入后）"
    requirement: INFRA-04
    verification:
      - kind: other
        ref: "bash mobile/tools/gate-a.sh（退出 0，stdout 含 PACK_OK skills=5 与 ✓ 闸门 A 通过）"
        status: pass
    human_judgment: false
  - id: D2
    description: "配置与 .sha256 真的在导出的 PCK 里：用 --main-pack 且不带 --path 读出 5 条动作并校验摘要"
    requirement: INFRA-04
    verification:
      - kind: integration
        ref: "godot --headless --main-pack mobile/build/verify.pck --script res://tools/check_pack.gd（PACK_OK skills=5）"
        status: pass
    human_judgment: false
  - id: D3
    description: "手改 mobile/assets/config/ 下的副本后闸门 A 必红，且 stderr 指名该文件"
    requirement: INFRA-04
    verification:
      - kind: other
        ref: "printf ' ' >> mobile/assets/config/skills_config.json && bash mobile/tools/gate-a.sh（退出 1，stderr 含该路径），随后 git checkout 还原恢复绿"
        status: pass
    human_judgment: false
  - id: D4
    description: "导出预设零凭据键、只有 arm64-v8a、include_filter 同时覆盖 .json 与 .sha256"
    requirement: INFRA-04
    verification:
      - kind: other
        ref: "grep -c keystore = 0；arm64-v8a=true = 1；x86_64/armeabi-v7a/x86 =true = 0；include_filter 含 *.json 与 *.sha256"
        status: pass
    human_judgment: false
  - id: D5
    description: "首屏源码无数学减号、关闭累积输入、含 SKILL_COUNT 格式化与无手柄提示"
    requirement: INFRA-04
    verification:
      - kind: other
        ref: "grep -c $'\\xe2\\x88\\x92' = 0；use_accumulated_input = false = 1；SKILL_COUNT = %d = 1"
        status: pass
    human_judgment: false
  - id: D6
    description: "两个脚本 UID 边车已入库且不被忽略（干净 clone 重新导入零未跟踪文件的前提）"
    requirement: INFRA-04
    verification:
      - kind: other
        ref: "git ls-files --error-unmatch mobile/src/smoke/smoke_screen.gd.uid mobile/tools/check_pack.gd.uid（退出 0）；git check-ignore 各自非零"
        status: pass
    human_judgment: false
  - id: D7
    description: "桌面版回归红线未被本计划污染"
    requirement: INFRA-04
    verification:
      - kind: other
        ref: "bash tools/check_desktop.sh（退出 0，✓ 230 项检查全部通过）"
        status: pass
    human_judgment: false

duration: 3min
completed: 2026-11-04
status: complete
---

# Phase 2 Plan 2: 最小工程 + PCK 往返 + 闸门 A Summary

**一个最小但非玩具的 Godot 工程，能在无导出模板的机器上用一条命令证明「工程可导入、脚本语法通过、5 条动作与匹配的 sha256 真的在 PCK 里」**

## Performance

- **Duration:** 3 min
- **Started:** 2026-11-04T10:14:44Z
- **Completed:** 2026-11-04T10:18:03Z
- **Tasks:** 2
- **Files modified:** 9（8 新建 + 1 修改）

## Accomplishments

- `--import → --export-pack → --main-pack` 三步在本机（有模板但**未使用**）跑通，
  `check_pack.gd` 从包里读出 `PACK_OK skills=5`，证明成功标准 3 的机械链路成立。
- `mobile/tools/gate-a.sh` 把这条链路收成一条命令：配置真源校验（第一步）→
  `doctor.sh godot` → 导入 → 两个脚本 `--check-only` → 打包 → 读包；失败一律
  `✗ + >&2 + exit 1`，成功最后一行写明「证明了什么」。
- 反例验证：给 `mobile/assets/config/skills_config.json` 追加一个空格后，
  闸门在第 1 步即退出 1 并在 stderr 指名该文件；还原后恢复绿。假绿路径被堵死。
- 导出预设置零凭据键、只出 `arm64-v8a`、`include_filter` 同时覆盖 `.json` 与
  `.sha256`（后者不是 Godot 资源，不加过滤就丢）。
- 首屏验收面板落地：`SKILL_COUNT / 最长中文串 / ° ± → ✓ ✗ / 八条轴实时读数 /
  「先按手柄上任意键唤醒」`；减号用 ASCII 连字符，避免「字体闸门绿、屏幕豆腐」。
- `--import` 生成的两个 `*.gd.uid` 边车随 Task 1 提交：脚本 UID 跨机器稳定，
  干净 clone 重新导入不会冒出未跟踪文件（02-05 的零漂移断言的前提）。
- 桌面回归红线未受影响：`bash tools/check_desktop.sh` 仍 230 项全绿。

## Task Commits

每个任务单独提交：

1. **Task 1: 一个最小工程，从包里把 5 条动作读回来** - `ba2193c` (feat)
2. **Task 2: 闸门 A 收成一条命令，并把新文件类型钉进行尾规则** - `9d5da81` (feat)

**Plan metadata:** 本 SUMMARY 与 STATE/ROADMAP 的提交见最终 `docs(02-02)` 提交。

## Files Created/Modified

- `mobile/project.godot`（新建，19 行）— `config_version=5`、`main_scene`、GL Compatibility、
  `import_etc2_astc=true`（缺则 Android 导出直接失败，P1）。`[gui] theme/custom_font` 留给 02-03。
- `mobile/export_presets.cfg`（新建，45 行）— Android 预设；arm64-v8a 唯一为真；
  `include_filter="assets/config/*.json,assets/config/*.sha256"`；零凭据键。
- `mobile/src/smoke/smoke_screen.gd`（新建，64 行）— 验收面板：`Input.use_accumulated_input = false`、
  `joy_connection_changed`、`SKILL_COUNT = %d`、`axis %d = %+.3f`、无手柄提示。
- `mobile/src/smoke/smoke_screen.tscn`（新建，26 行）— 手写场景，两个 `Label` 均
  `unique_name_in_owner = true`，字号 28 / 22。
- `mobile/tools/check_pack.gd`（新建，43 行）— 从 PCK 读配置与 sidecar，`EXPECTED_SKILLS := 5`
  带「禁止改成读到几条算几条」注释；`split(" ", false)[0]` 解析 sha256sum 格式。
- `mobile/src/smoke/smoke_screen.gd.uid` / `mobile/tools/check_pack.gd.uid`（新建，各 1 行）—
  `--import` 生成的 UID 边车，作为导入产物中的提交物入库。
- `mobile/tools/gate-a.sh`（新建，92 行）— 闸门 A 唯一入口；六步固定顺序，绝对路径产物，
  读包不带 `--path`，`trap` 清理临时日志，结束时把 PCK 留在 `mobile/build/` 供人工检查。
- `.gitattributes`（修改，+6 行）— `*.gd / *.tscn / *.tres / *.cfg / *.godot` 为 `eol=lf`，
  `*.ttf` 声明 `binary`；已有行序未动。

## Decisions Made

- **`EXPECTED_SKILLS := 5` 保留硬编码**：动态读「读到几条算几条」会让断言永远绿。
  注释按 `tools/check_desktop.sh` 的 `BASELINE_SHA256` 体例写明「新增动作必须同步改这里」。
- **首屏减号用 U+002D**：`−1.000` 的数学减号不在 139 字字形清单里，会造成字体闸门假绿。
- **读包不带 `--path`**：`--main-pack` 只挂载包；带 `--path` 会让 `res://` 指回工程目录。
- **`project.godot` 不写 `theme/custom_font`**：字体资产 02-03 才生成，先写会指向不存在的资源。
- **闸门 A 不接 GitHub Actions**：ROADMAP 把「CI 打发布包」留给 Phase 9；提前接需要在 runner
  上再下一份 Godot，属于另一件事（本计划 `<objective>` 的范围裁定）。
- **`*.gd.uid` 提交但不进 `.gitignore`**：只有 `mobile/.godot/` 与 `mobile/build/` 是忽略物；
  边车缺失会让干净 clone 的第一次 `--import` 冒出两个未跟踪文件。
- **INFRA-04 不在本计划标记完成**：闸门 A 只覆盖「工程能打包、配置在包里」，
  签名 APK 与真机冒烟由 02-04 / 02-05 收口。

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - 验收可机械化] `gate-a.sh` 里与 `export-pack` 同行的旁白改成不带该字面量的措辞**
- **Found during:** Task 2（自检验收条款时）
- **Issue:** 验收要求「`grep -n 'export-pack' mobile/tools/gate-a.sh` 所在行的产物路径以
  `"$repo_root/mobile/build/` 开头」。原稿里 `echo "▸ 导出 PCK（--export-pack 不需要导出模板）…"`
  与失败提示也含该字面量，却不带产物路径 —— 机械核对时会被判成「有行不带绝对路径」。
- **Fix:** 两处旁白改成不含 `export-pack` 字面量的措辞（「打包不需要 1.9 GB 导出模板」/
  「Godot 打包命令」），只留真正那条命令含该字面量且与绝对产物路径同行。
- **Files modified:** mobile/tools/gate-a.sh
- **Verification:** `grep -n 'export-pack' mobile/tools/gate-a.sh` 只剩 1 行且含
  `"$repo_root/mobile/build/verify.pck"`；`bash mobile/tools/gate-a.sh` 仍退出 0。
- **Committed in:** `9d5da81`（Task 2 提交）

---

**Total deviations:** 1 auto-fixed（1 验收可机械化）
**Impact on plan:** 只改旁白措辞，没有放宽任何判据；闸门行为与退出码不变。

## Issues Encountered

- 本机的 `gsd_run` / `gsd-tools` 运行时不可用（`gsd` 是另一套 CLI，`command -v gsd_run` 为空），
  因此 STATE.md / ROADMAP.md 用直接文件编辑更新，没有走 SDK 的 state 命令。
- `git.branching_strategy = "none"`，本项目历史所有计划提交都在 `main`；本次是编排器指定的
  sequential-on-main 执行，故按既有工作流在 `main` 提交（与 02-01 一致）。
- 全部 `.sh` 在 git 里都是 `100644`（含 `tools/check_desktop.sh`、`mobile/tools/doctor.sh`），
  因此 `gate-a.sh` 也保持 644、一律用 `bash <path>` 调用，不引入可执行位差异。
- 导出日志尾部固定出现 `cannot connect to daemon at tcp:5037`（P10 的 adb 噪声），不影响退出码。

## User Setup Required

None — 闸门 A 不需要导出模板、JDK、keystore 或真机。release keystore 的口令仍由
02-04 的 `checkpoint:human-action` 从密码管理器注入。

## Next Phase Readiness

- 02-03 可以直接往 `mobile/assets/fonts/` 放字体与 `AppFont.tres`，并在 `project.godot`
  补上 `[gui] theme/custom_font` 一行；闸门 A 的末尾会由它追加字形一项。
- 02-04 的闸门 B 应调 `doctor.sh`（全五项）后再 `--export-release`，不要复制闸门 A 的命令。
- `mobile/build/verify.pck` 留在原地供人工检查，已被 `.gitignore` 覆盖，仓库仍干净。
- 真机阻塞仍在：`adb devices` 为 0 台，成功标准 1/2/4 需要 2 台不同 OEM 手机 + 手柄。

## Self-Check: PASSED

- `mobile/project.godot`、`mobile/export_presets.cfg`、`mobile/src/smoke/smoke_screen.{gd,tscn}`、
  `mobile/tools/check_pack.gd`、`mobile/tools/gate-a.sh`、两个 `*.gd.uid` 均存在。
- `ba2193c`、`9d5da81` 均在 HEAD 祖先链上。
- `bash mobile/tools/gate-a.sh` 退出 0，输出含 `PACK_OK skills=5` 与 `✓ 闸门 A 通过`。
- 反例（追加空格）退出 1 且 stderr 指名 `mobile/assets/config/skills_config.json`，还原后恢复绿。
- `bash tools/check_desktop.sh` 退出 0，230 项全绿。
- `git status --porcelain -- mobile/` 在两次任务提交后为空（`mobile/.godot/` 与
  `mobile/build/` 被忽略规则覆盖，不弄脏仓库）。

---
*Phase: 02-apk*
*Completed: 2026-11-04*
