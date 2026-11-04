---
phase: 02-apk
verified: 2026-11-04T17:45:28Z
status: passed
score: 35/35 must-haves verified
covered_files: [".gitattributes", ".gitignore", ".planning/phases/02-apk/02-01-PLAN.md", ".planning/phases/02-apk/02-01-SUMMARY.md", ".planning/phases/02-apk/02-02-PLAN.md", ".planning/phases/02-apk/02-02-SUMMARY.md", ".planning/phases/02-apk/02-03-PLAN.md", ".planning/phases/02-apk/02-03-SUMMARY.md", ".planning/phases/02-apk/02-04-PLAN.md", ".planning/phases/02-apk/02-04-SUMMARY.md", ".planning/phases/02-apk/02-05-PLAN.md", ".planning/phases/02-apk/02-05-SUMMARY.md", ".planning/phases/02-apk/02-UAT.md", "README.md", "mobile/ACCEPTANCE.md", "mobile/BUILD.md", "mobile/README.md", "mobile/assets/fonts/AppFont.tres", "mobile/assets/fonts/NotoSansSC-Subset.ttf", "mobile/assets/fonts/NotoSansSC-Subset.ttf.import", "mobile/assets/fonts/NotoSansSymbols2-Subset.ttf", "mobile/assets/fonts/NotoSansSymbols2-Subset.ttf.import", "mobile/assets/fonts/OFL.txt", "mobile/assets/fonts/required_glyphs.txt", "mobile/export_presets.cfg", "mobile/project.godot", "mobile/src/smoke/smoke_screen.gd", "mobile/src/smoke/smoke_screen.gd.uid", "mobile/src/smoke/smoke_screen.tscn", "mobile/tools/check_pack.gd", "mobile/tools/check_pack.gd.uid", "mobile/tools/device-smoke.sh", "mobile/tools/doctor.sh", "mobile/tools/gate-a.sh", "mobile/tools/gate-b-selftest.sh", "mobile/tools/gate-b.sh", "mobile/tools/glyph_coverage.gd", "mobile/tools/glyph_coverage.gd.uid", "mobile/tools/verify_clean_export.sh", "tools/make_font_subset.py"]
covered_digest: "v3:sha256:014d1e9d950e8474d2a046526d4f1ce0f1bcd2c085931c2b674206f92bf21cb0"
behavior_unverified: 0
overrides_applied: 3
overrides:
  - must_have: "首屏完整显示最长中文字符串与 ° ± → ✓ ✗，在两台不同 OEM 手机上均无豆腐块"
    reason: "用户 2026-11-05 明确豁免第二台手机，原话：「先不用考虑第二台手机，你先把这一台手机搞定就行了」。单台 Motorola XT2175-2 上有截图逐字确认；第二台不同 OEM 未测，本 override 只代表「单台 + 用户豁免」，不代表两台已过。"
    accepted_by: "stephen"
    accepted_at: "2026-11-05T00:00:00+08:00"
  - must_have: "release keystore 已离线备份（SC5）"
    reason: "恢复演练已执行并通过：keystore 拷到临时目录、用口令经 keytool 打开、证书 SHA-256 与 E1:84:1A:…:E0:46 逐字一致、临时副本已删除。仅「两处不同址/不同设备的离线介质 + 口令入密码管理器」未做；用户 2026-11-05 明确「我自己安排，先往下走」，由用户自行完成。"
    accepted_by: "stephen"
    accepted_at: "2026-11-05T01:44:39+08:00"
  - must_have: "另一台干净机器按文档能重导出（SC5）"
    reason: "用户 2026-11-05 决定自行安排：目前没有第二台干净机器。替代证据是 verify_clean_export.sh 在临时 clone 中从零重导出并全绿（26,797,306 字节、证书指纹一致），证明仓库状态与脚本足以复现；真实「另一台电脑」未验证，本 override 不把它冒充为已验证。"
    accepted_by: "stephen"
    accepted_at: "2026-11-05T01:44:39+08:00"
re_verification:
  previous_status: human_needed
  previous_score: 33/35
  gaps_closed:
    - "签名 arm64 APK 在真机安装并启动到首屏，全程不经过 Godot 编辑器（SC1）"
    - "首屏最长中文串与 ° ± → ✓ ✗ 在真机无豆腐（单台 Motorola XT2175-2；第二台由用户豁免）"
    - "蓝牙手柄原始轴与按钮通道在真机可读（SC4）"
    - "device-smoke.sh 在真机完成安装 / 启动 / 进程存活 / 截图并输出 DEVICE_SMOKE_OK"
    - "release keystore 离线备份（SC5 前一半）—— 恢复演练已通过；异地介质由用户接受为风险"
    - "第二台干净机器重导出（SC5 后一半）—— 用户接受风险，clone 重导出作为替代证据"
  gaps_remaining: []
  regressions: []
---

# Phase 2: 安卓工具链 + 真机冒烟 APK Verification Report

**Phase Goal:** 用锁定的工具链导出一个签名 arm64 APK，证明它能装、能启动、中文不豆腐、共享配置真的进了包、手柄原始轴在真机上能读到。
**Verified:** 2026-11-04T17:45:28Z
**Status:** passed
**Re-verification:** Yes — UAT 以「用户接受风险」收口（提交 `9813632`）；自上一轮验证（`7f311b0`）以来没有任何源码 / 脚本 / 导出预设变化，本轮只刷新指纹，不重跑闸门与真机测试

**结论先行：** 35/35 must-haves 已闭合，其中 3 项是用户明确接受的 override（SC2 第二台 OEM、SC5 的两处人工项）。SC1 / SC3 / SC4 / SC6 有真机与机械双重证据；SC2 在单台 Motorola XT2175-2 上逐字通过、第二台由用户豁免；SC5 的版本记录与 keystore 生成已机械验证，恢复演练已通过，剩余「异地离线介质」与「第二台干净机器」由用户明确接受为风险并自行跟进。**0 个代码缺口，0 项待人工阻塞**；按用户决定，`status = passed`。

**本报告不把 accepted-risk 说成 verified。** 三项 override 在 frontmatter 与 `## User-Accepted Risks` 中原样保留，写清「做到了什么 / 没做什么 / 谁跟进」。

**本轮增量（提交 `9813632`）：** 仅修改 `02-UAT.md`（`status: complete-with-accepted-risk`，§5 改记 accepted-risk，§4 计入接受风险）。`mobile/export_presets.cfg` 的 `exclude_filter` 修复来自上一轮 `7f311b0`，已复核。本轮按调度要求不重跑任何闸门或设备测试；上一轮的全部实测证据保留，指纹刷新以覆盖 UAT 的最新状态。

## 证据来源（前几轮实测，本轮未重跑）

1. 逐字读 `02-UAT.md`，并把其中的真机声明拿到**当时仍连着的那台设备**上独立复验（设备 `ZY22F5FXX9` 在 `adb devices` 中在线）。
2. 重新执行 `gate-a.sh`、`gate-b.sh`、`gate-b-selftest.sh`、`tools/check_desktop.sh`、`verify_clean_export.sh`，全部现场取退出码与输出。
3. 重新执行三条假绿反例（配置篡改、字形清单多字、源文件多字），确认闸门仍会变红，然后还原并确认工作区干净。
4. 真机重新跑 `device-smoke.sh`，并直接读 `adb logcat` 里的 `SMOKE` 事件，而不只看截图。

**真机证据（实测取得，非转述）：**

- `bash mobile/tools/device-smoke.sh` → `DEVICE_SMOKE_OK serial=ZY22F5FXX9 package=com.fifaskill.trainer pid=17686 screenshot=…`，退出码 0；`dumpsys package` 显示 `firstInstallTime 2026-11-05 00:52:00`、`lastUpdateTime 2026-11-05 01:33:54`、`primaryCpuAbi=arm64-v8a`。
- 设备属性：`ro.product.manufacturer=motorola`、`ro.product.model=XT2175-2`、`ro.build.version.release=12`。
- `adb logcat -s godot:V`：`SMOKE READY skills=5`（01:33:56，新进程 17686）；日志缓冲内共 99 条 `SMOKE` 事件，覆盖 `axis 0–7` 与按钮 `0/1/2/3/9/10`；右摇杆 `axis 2` 实测从 `-0.969` 到 `+1.000`，`axis 3` 同步变化；`idx=0 down=true` 与 `idx=9 down=true` 在同一毫秒出现（A+LB 组合）。
- 截图 `mobile/build/device-smoke-ZY22F5FXX9.png`（56,740 字节，2026-11-05 01:34）：`SKILL_COUNT = 5`、`起点错了：注意从左摇杆朝向的哪个方位起手。` 完整、`° ± → ✓ ✗   0° 45° -1.000` 全部为字形；并显示 `#0 Xbox Series X Controller` 与 8 条轴读数。
- 进程在截图后被脚本 `am force-stop` 收尾（日志 `Force stopping …`），不是崩溃；无 `FATAL EXCEPTION` / ANR。

**机械证据（前几轮现跑，退出码 0）：** `gate-a.sh`（`PACK_OK skills=5`、`GLYPH_OK chars=818`）、`gate-b.sh`（v2+v3、`ALIGN_OK`、仅 arm64、APK 26,797,306 字节）、`gate-b-selftest.sh`（`SELFTEST_OK`）、`tools/check_desktop.sh`（230 项全过）、`verify_clean_export.sh`（clone 内闸门 B 全绿、工作区零漂移）。`apksigner` 证书指纹 `e1841a17…32e046`、`zipalign -c -P 16`、包内 `assets/assets/config/*` 与 sidecar、`aapt2` badging、包内 `assets/build/` 命中 0 条，均单独复核通过。

## Goal Achievement

### Observable Truths

| #   | Truth   | Status     | Evidence       |
| --- | ------- | ---------- | -------------- |
| 1 | 签名 arm64 APK 在一台真实 Android 手机上安装并启动到首屏，全程不经过 Godot 编辑器（SC1） | ✓ VERIFIED | 真机重跑 `device-smoke.sh` rc=0：`am start -W -n com.fifaskill.trainer/com.godot.game.GodotAppLauncher` 成功、pid=17686 存活、截图即验收首屏；安装来自 `gate-b.sh` 的 headless 导出（`apksigner` v2+v3 true、`e1841a17…32e046`、仅 `arm64-v8a`） |
| 2 | 首屏完整显示最长中文字符串与 `° ± → ✓ ✗`，在两台不同 OEM 手机上均无豆腐块（SC2） | PASSED (override) | 单台 Motorola XT2175-2 截图逐字确认：中文整串完整、五个符号为字形、`-1.000` 负号为 ASCII。第二台不同 OEM **未测**；用户 2026-11-05 明确豁免（见 frontmatter override 与 `## User-Accepted Risks`） |
| 3 | 启动读到 `res://assets/config/` 并显示 `SKILL_COUNT = 5`，证明 `*.json` 进了 PCK（SC3） | ✓ VERIFIED | 真机 logcat `SMOKE READY skills=5`（01:33:56，pid 17686）；截图 `SKILL_COUNT = 5`；APK 内 `assets/assets/config/skills_config.json` 的 sha256 与 `shared/skills_config.json` 同为 `bccf123a…eee9`，sidecar 也逐字一致 |
| 4 | 连蓝牙手柄推右摇杆时，屏幕上的原始轴数值实时变化（SC4） | ✓ VERIFIED | logcat 99 条 `SMOKE` 事件：`axis 0–7` 全部出现；`axis 2` 从 `-0.969` 到 `+1.000`、`axis 3` 同步变化；按钮 `0/1/2/3/9/10` 均被观测，含 A+LB 同帧；截图显示 `#0 Xbox Series X Controller` + 八条轴 |
| 5 | BUILD.md 记录精确版本；release keystore 已生成（SC5 前半） | ✓ VERIFIED | `BUILD.md §1`：Godot 4.7.2-stable / 模板 4.7.2.stable / JDK 17 / build-tools 36.1.0；`gate-b.sh` 实测五项 doctor 全绿（含 `keystore … alias=fifa-trainer 可读`）；keystore 权限 `600`；`apksigner` 证书 DN `CN=FIFA Skill Trainer…` |
| 6 | release keystore 已离线备份（SC5） | PASSED (override) | **恢复演练已通过：** keystore 拷到临时目录 → `keytool -list -alias fifa-trainer` 用口令打开 → 证书 SHA-256 与 `E1:84:1A:…:E0:46` 一致 → 删除临时副本。**未做：** 两处不同址/异设备的离线介质、口令入密码管理器、`ACCEPTANCE.md §4` 回填。用户 2026-11-05 明确「我自己安排，先往下走」，作为用户接受风险（见 `## User-Accepted Risks`） |
| 7 | 另一台干净机器按文档能重导出（SC5） | PASSED (override) | 用户 2026-11-05 决定自行安排（目前无第二台干净机器）。替代证据：`verify_clean_export.sh` 在临时 clone 中从零重导出并全绿（26,797,306 字节、证书指纹一致），证明仓库状态与脚本足以复现；真实「另一台电脑」**未验证** —— 用户接受风险，不冒充已验证 |
| 8 | doctor 一条命令判定缺项：非零退出 + 实际值/期望值/修法 | ✓ VERIFIED | 口令在环境时五项全绿 rc=0；不提供口令时 `✗ keystore 口令未在环境变量 …` rc=1，只打印变量名与修法 |
| 9 | 引擎版本前缀匹配：4.7.2.* 通过，4.7.3 / 4.8 失败 | ✓ VERIFIED | 假 `GODOT_BIN` 实测：`4.7.3.stable.official.abc` rc=1；`4.7.2.stable.official.ed1daf0bf` rc=0 |
| 10 | 版本字符串只在 doctor.sh 一处定义，其它脚本调 doctor 断言 | ✓ VERIFIED | `GODOT_VERSION_PREFIX` / `TEMPLATE_VERSION` 只出现在 `doctor.sh`；`gate-a.sh` 只调 `doctor.sh godot` |
| 11 | 断言可按名单独运行：闸门 A 只跑引擎断言，不需模板/JDK/真机 | ✓ VERIFIED | `doctor.sh godot` 单独 rc=0；`gate-a.sh` 全程未触碰模板/JDK/设备 |
| 12 | keystore 断言缺文件/缺口令 fail-closed，且从不打印口令值 | ✓ VERIFIED | 未导出口令执行 doctor → rc=1 且只显示变量名；全仓无口令字面值（仅规划文档里的占位符） |
| 13 | 设备断言从第一天存在，0 台时明确报出 0 台 | ✓ VERIFIED | 设备在线时 `doctor.sh device` → `✓ device 1 台` rc=0；0 台路径实测为 `✗ device 0 台` rc=1 |
| 14 | 闸门 A 一条命令，无模板/JDK/设备，约 10 秒 | ✓ VERIFIED | `gate-a.sh` rc=0，七段全绿 |
| 15 | 配置与 `.sha256` 真在 PCK，`--main-pack` 读出 5 条动作 | ✓ VERIFIED | `PACK_OK skills=5`；`check_pack.gd` 不带 `--path` |
| 16 | 手改 `mobile/assets/config/` 副本后闸门 A 必红 | ✓ VERIFIED | 反例：追加一个换行 → rc=1，首条即「副本与真源不一致」；已还原（`git status` 干净） |
| 17 | 首屏源码无 U+2212，轴读数由 `%+.3f` 生成 ASCII 符号 | ✓ VERIFIED | `grep U+2212`：`.gd` / `.tscn` / 字形清单均 0 次；`smoke_screen.gd:87` 使用 `%+.3f` |
| 18 | SKILL_COUNT 硬编码 5 并带「为什么可以硬编码」注释 | ✓ VERIFIED | `check_pack.gd:12-13` 常量 + 「禁止改成读到几条算几条」注释 |
| 19 | Godot 边车是提交物；干净 clone 重导入零漂移 | ✓ VERIFIED | 5 个边车（3×`*.gd.uid` + 2×`*.ttf.import`）在 `git ls-files`；`verify_clean_export.sh` rc=0、工作区无漂移 |
| 20 | 关闭系统兜底后 `° ± → ✓ ✗` 与全部中文仍可渲染 | ✓ VERIFIED | `GLYPH_OK chars=818`；`allow_system_fallback=false` |
| 21 | 清单/两子集/AppFont 同源；清单多出子集没有的字时闸门红 | ✓ VERIFIED | 反例：清单追加 `龘` → `GLYPH_MISSING 1: 龘` rc=1；已还原 |
| 22 | 源文件新增字符而清单未重生成时闸门 A 红 | ✓ VERIFIED | 反例：`smoke_screen.gd` 追加 `龘` 注释 → `make_font_subset.py --check` rc=1 并指名缺字；已还原 |
| 23 | `✗` 由 fallback 提供，主字体不含它（双字体是硬条件） | ✓ VERIFIED | `GLYPH_BASE_HAS_X=false`；`AppFont.tres` 有 `fallbacks = Array[Font]([…Symbols2])` |
| 24 | 子集入库后构建链路不再需要字体工具 | ✓ VERIFIED | `make_font_subset.py --check` 纯标准库、`check()` 路径不调子进程；闸门 A 的 `--check` 在无 fonttools 下通过 |
| 25 | 闸门 B 一条命令产出并自证 v2 签名、16 KB 对齐、仅 arm64 | ✓ VERIFIED | `gate-b.sh` rc=0；`apksigner`：v2 true、v3 true；`zipalign -c -P 16` rc=0；badging `native-code: 'arm64-v8a'` |
| 26 | 缺 keystore/口令错时非零退出，磁盘残留过不了 apksigner | ✓ VERIFIED | `gate-b-selftest.sh` rc=0：错口令残留被 apksigner 拒绝；缺口令 rc≠0 |
| 27 | 口令不进 stdout/stderr/仓库；导出日志的密钥库参数脱敏 | ✓ VERIFIED | 自测：`✓ 导出日志不含口令 canary`、`✓ 签名命令行里的密钥库参数是脱敏的`；全仓扫描无口令字面值 |
| 28 | 闸门 B 只有一个必填输入（口令），不设 FIFA_KEYSTORE/ALIAS 也能跑 | ✓ VERIFIED | 仅从 `credentials.sh` 取口令、未设两个覆盖变量，`gate-b.sh` rc=0 且使用默认密钥库路径 |
| 29 | 包名 / versionCode / versionName / 架构定死 | ✓ VERIFIED | badging：`com.fifaskill.trainer`、`versionCode='1'`、`versionName='0.1.0'`、`arm64-v8a`、`minSdkVersion:'24'` |
| 30 | APK 内配置路径是 `assets/assets/config/...` | ✓ VERIFIED | `unzip -l` 命中该路径 + `.sha256`；`gate-b` 包内容校验通过 |
| 31 | 干净 clone 上重跑脚本即产出同一份 APK，零漂移 | ✓ VERIFIED | `verify_clean_export.sh` rc=0：clone 内产物 26,797,306 字节、工作区无漂移；`exclude_filter` 加 `build/*` 后本机产物同为 26,797,306 字节 |
| 32 | 验收表要求两台不同 OEM + 真手柄；模拟器/单台手机不允许打勾 | ✓ VERIFIED | `ACCEPTANCE.md §0` 四条前置 + 明确禁令仍在；本阶段第二台由用户豁免，文档未改写（豁免只在 UAT/本报告记录） |
| 33 | 验收表记录可核对事实；SC5 两半各有可填字段 | ✓ VERIFIED | §2 厂商/型号/Android/截图名/时间/验收人 + 证书 SHA-256 字段、§4 备份四行、§5 第二台机器三行均在。⚠️ §2/§4/§5 未回填，真机结论以 `02-UAT.md` 为权威记录（见 Anti-Patterns） |
| 34 | 构建文档里没有任何口令值 | ✓ VERIFIED | `BUILD.md` 只有变量名与占位；仓库扫描仅规划文档中的示例占位，无真实口令 |
| 35 | `device-smoke.sh` 装机 + 启动 + 存活 + 截图，输出 DEVICE_SMOKE_OK/FAIL | ✓ VERIFIED | 真机 rc=0，末行 `DEVICE_SMOKE_OK serial=ZY22F5FXX9 package=com.fifaskill.trainer pid=17686 screenshot=…`；安装/启动/截图均为真实 adb 行为 |

**Score:** 35/35 truths verified（含 3 项用户 override；0 failed，0 uncertain，0 behavior-unverified）

> **MVP 模式说明：** ROADMAP 给本阶段标了 `Mode: mvp`，但阶段目标不是 `As a …, I want …, so that …` 形式的用户故事，而是可机械/真机验收的技术结果。因此本报告沿用前三轮的标准 goal-backward 口径，不套用 User Flow Coverage 表；这是对既有验收方式的延续，不是本轮新引入的豁免。

### Deferred Items

无。成功标准 5 的两处人工项不在任何后续阶段的成功标准里（Phase 9 只覆盖「干净 clone 脚本化导出」与覆盖安装）。它们不是延期到后续阶段，而是由用户明确接受为风险并自行跟进（见 `## User-Accepted Risks`）。

### Advisory (New Scope, Unevidenced)

本轮未发现「无证据支撑的新范围阻塞项」。

| # | Finding | Category | Why Advisory |
|---|---------|----------|--------------|
| — | None | — | — |

### Required Artifacts

| Artifact | Expected    | Status | Details |
| -------- | ----------- | ------ | ------- |
| `mobile/tools/doctor.sh` | 六项断言 + 命名入口 + 0/1/2 契约 | ✓ VERIFIED | 328 行；五项绿、缺口令 rc=1、未知名 rc=2、`device` 单独可用 |
| `mobile/project.godot` | config_version=5、主场景、GL Compatibility、ETC2/ASTC | ✓ VERIFIED | `theme/custom_font` 指 `AppFont.tres`；字形闸门反向断言 fallback |
| `mobile/export_presets.cfg` | 仅 arm64、零凭据键、include_filter 覆盖 json+sha256、exclude_filter 排除 build | ✓ VERIFIED | `arm64-v8a=true`，其余架构 false；无签名凭据键；`include_filter="assets/config/*.json,assets/config/*.sha256"`；`exclude_filter="build/*,tools/*.png"`（`7f311b0`） |
| `mobile/src/smoke/smoke_screen.gd` | 验收面板 + 输入日志（SKILL_COUNT/最长串/五符号/8 轴/按钮） | ✓ VERIFIED | 98 行；`_log_changes()` 打印 `SMOKE BTN/AXIS`，`_load_config()` 打印 `SMOKE READY`；真机 logcat 已验证 |
| `mobile/src/smoke/smoke_screen.tscn` | Header/Axes 两个 Label | ✓ VERIFIED | 26 行，`%Header` / `%Axes` |
| `mobile/tools/check_pack.gd` | 从 PCK 读配置+sidecar，`EXPECTED_SKILLS=5` | ✓ VERIFIED | 43 行；`PACK_OK skills=5` |
| `mobile/tools/gate-a.sh` | 配置→引擎→导入→语法→打包→读包→字形 | ✓ VERIFIED | 155 行；`gate-b` 内联执行 rc=0 |
| `mobile/assets/fonts/required_glyphs.txt` | 唯一字形清单 | ✓ VERIFIED | 818 行/818 字符 |
| `mobile/assets/fonts/NotoSansSC-Subset.ttf` + `.import` | CJK 子集 + 导入契约 | ✓ VERIFIED | 455,128 字节；已跟踪；APK 内有 `.fontdata` |
| `mobile/assets/fonts/NotoSansSymbols2-Subset.ttf` + `.import` | 符号 fallback（提供 ✗） | ✓ VERIFIED | 已跟踪；`GLYPH_BASE_HAS_X=false` |
| `mobile/assets/fonts/AppFont.tres` | FontVariation + fallbacks | ✓ VERIFIED | `base_font` + `fallbacks` |
| `mobile/assets/fonts/OFL.txt` | SIL OFL 1.1 | ✓ VERIFIED | 存在（版权行缺失仍为已分类 open 的 MED-05） |
| `mobile/tools/glyph_coverage.gd` | 关闭兜底逐字符断言 | ✓ VERIFIED | 80 行；`GLYPH_OK chars=818`，反例变红 |
| `mobile/tools/gate-b.sh` | doctor→gate-a→清旧→导出→四段校验 | ✓ VERIFIED | 203 行；rc=0，APK 26,797,306 字节 |
| `mobile/tools/gate-b-selftest.sh` | 未签名拒绝 + 口令不进日志 + 缺口令非零 | ✓ VERIFIED | `SELFTEST_OK` rc=0 |
| `mobile/tools/device-smoke.sh` | 装机/启动/存活/截图，OK/FAIL token | ✓ VERIFIED（真机） | 196 行；真机 rc=0，`DEVICE_SMOKE_OK`；收尾 `am force-stop` 是脚本行为 |
| `.gitignore` | `*.keystore` / `*.jks` / `*.idsig` / `*.apk` | ✓ VERIFIED | 全部在列 |
| `mobile/BUILD.md` | 版本表 + 顺序 + 密钥库 + 指纹 + 排查 + 干净机器 | ✓ VERIFIED | 340 行；§1 四行版本与实测一致 |
| `mobile/ACCEPTANCE.md` | 2 OEM × 4 观察 + 记录字段 + SC5 两半 | ✓ VERIFIED（字段在；§2/§4/§5 由用户接受留白） | 149 行；§0 前置与禁令完整；真机证据以 `02-UAT.md` 为权威记录（见 Warning） |
| `mobile/tools/verify_clean_export.sh` | clone 重跑闸门 B + 零漂移 | ✓ VERIFIED | rc=0，clone 产物 26,797,306 字节 |
| `mobile/README.md` / `README.md` | 三条入口命令 + 仓库地图 | ✓ VERIFIED | 含 `gate-a.sh` / `gate-b.sh` / `device-smoke.sh` / `BUILD.md` |
| `tools/make_font_subset.py` | 抽字符 + 两子集 + OFL + `--check` | ✓ VERIFIED | 298 行；`--check` 不调子进程、不写盘 |

### Key Link Verification

| From | To  | Via | Status | Details |
| ---- | --- | --- | ------ | ------- |
| `gate-a.sh` | `tools/sync_config.py` | 第一条命令 `--check` | WIRED | 反例证实会红 |
| `gate-a.sh` | `check_pack.gd` | `--main-pack` 且不带 `--path` | WIRED | `PACK_OK skills=5` |
| `gate-a.sh` | `make_font_subset.py --check` | 字形闸门之前 | WIRED | 反例 rc=1 并指名缺字 |
| `gate-a.sh` | `glyph_coverage.gd` | 关闭兜底逐字符 | WIRED | `GLYPH_OK chars=818` |
| `project.godot` | `AppFont.tres` | `theme/custom_font` | WIRED | `glyph_coverage.gd` 反向断言 |
| `AppFont.tres` | 两个子集 | `base_font` + `fallbacks` | WIRED | 两者缺一即 `GLYPH_FAIL` |
| `gate-b.sh` | `doctor.sh` | 五项构建断言 | WIRED | 五项绿 |
| `gate-b.sh` | release 导出 | 口令环境变量 + 默认路径/别名 | WIRED | 产出 26,797,306 字节签名包 |
| `gate-b.sh` | build-tools 36.1.0 | `apksigner`/`zipalign`/`aapt2` 绝对路径 | WIRED | v2/v3、ALIGN_OK、badging 全过 |
| `verify_clean_export.sh` | `gate-b.sh` | clone 内调用 | WIRED | rc=0 + 零漂移 |
| `device-smoke.sh` | `com.godot.game.GodotAppLauncher` | badging 为空时回退 `dump xmltree` | WIRED（真机确认） | 真实设备安装并 `am start -W -n …/GodotAppLauncher` 成功 |
| `smoke_screen.gd` | `res://assets/config/skills_config.json` | `FileAccess` + `JSON.parse_string` | WIRED | 真机 `SMOKE READY skills=5` |
| `smoke_screen.gd` | `adb logcat` | `print("SMOKE …")` | WIRED | 99 条事件，含 `READY/AXIS/BTN` |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
| -------- | ------------- | ------ | ------------------ | ------ |
| `smoke_screen.gd` Header | `_skill_count` | 包内 `res://assets/config/skills_config.json`（哈希与真源一致） | 是（5，真机 logcat + 截图） | ✓ FLOWING |
| `smoke_screen.gd` Axes | `Input.get_joy_axis(d, 0..7)` | Godot 引擎运行时手柄驱动 | 是（axis 0–7 事件，2/3 实时变化） | ✓ FLOWING |
| `smoke_screen.gd` Buttons | `Input.is_joy_button_pressed` | Godot 引擎运行时 | 是（0/1/2/3/9/10） | ✓ FLOWING |
| `device-smoke.sh` 启动入口 | `activity` | badging → xmltree → Manifest 的 LAUNCHER alias | 是（真实安装与启动成功） | ✓ FLOWING |
| `check_pack.gd` | `EXPECTED_SKILLS` + `.sha256` | PCK 内文件 | 是 | ✓ FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
| -------- | ------- | ------ | ------ |
| 闸门 A 全链路 | `bash mobile/tools/gate-a.sh` | `PACK_OK skills=5`、`GLYPH_OK chars=818`、rc=0 | ✓ PASS |
| 闸门 B 全链路 | `bash mobile/tools/gate-b.sh` | v2+v3、`ALIGN_OK`、arm64、rc=0；APK 26,797,306 字节、包内无 `assets/build/` | ✓ PASS |
| 闸门 B 反例 | `bash mobile/tools/gate-b-selftest.sh` | `SELFTEST_OK`、canary 不入日志、缺口令 rc≠0 | ✓ PASS |
| 桌面回归 | `bash tools/check_desktop.sh` | 「230 项检查全部通过，名称与基线逐项一致」rc=0 | ✓ PASS |
| 干净 clone 重导出 | `bash mobile/tools/verify_clean_export.sh` | rc=0、零漂移、clone 产物 26,797,306 字节 | ✓ PASS |
| 真机装机 + 启动 + 截图 | `bash mobile/tools/device-smoke.sh` | rc=0、`DEVICE_SMOKE_OK … pid=17686`、截图非黑屏 | ✓ PASS |
| 真机配置读取 | `adb logcat -s godot:V \| grep "SMOKE READY"` | `SMOKE READY skills=5` | ✓ PASS |
| 真机手柄轴 | `adb logcat … \| grep "SMOKE AXIS"` | axis 0–7 均出现；axis 2 `-0.969…+1.000`、axis 3 同步变化 | ✓ PASS |
| 真机按钮通道 | `adb logcat … \| grep "SMOKE BTN"` | idx 0/1/2/3/9/10；A+LB 同毫秒 true | ✓ PASS |
| 设备断言 | `bash mobile/tools/doctor.sh device` | `✓ device 1 台` rc=0 | ✓ PASS |
| 版本前缀负向控制 | 假 `GODOT_BIN` 4.7.3 / 4.7.2 | rc=1 / rc=0 | ✓ PASS |
| 配置漂移负向控制 | 副本追加换行 → `gate-a.sh` | rc=1，首条即红；已还原 | ✓ PASS |
| 字形清单负向控制 | 清单追加 `龘` → `glyph_coverage.gd` | rc=1，`GLYPH_MISSING 1: 龘`；已还原 | ✓ PASS |
| 源文件字形漂移负向控制 | 源码追加 `龘` → `make_font_subset.py --check` | rc=1，指名缺字；已还原 | ✓ PASS |

> 以上为前几轮现场实测结果；本轮按要求未重跑。自 `7f311b0` 起源码 / 脚本 / 导出预设无变化，`9813632` 仅改 UAT 文本。

### Probe Execution

N/A — 本阶段未声明任何 `probe-*.sh`，成功标准也不涉及探针。

### Test Quality Audit

| Test / Gate | Linked Req | Active | Skipped | Circular | Assertion Level | Verdict |
| ----------- | ---------- | ------ | ------- | -------- | --------------- | ------- |
| `mobile/tools/gate-a.sh` | INFRA-04 | 7 段 | 0 | 否（配置 hash 来自真源；SKILL_COUNT 为字面常量 5） | Behavioral（读包、逐字符渲染） | ✓ |
| `mobile/tools/gate-b.sh` | INFRA-04 | 4 段静态校验 | 0 | 否（apksigner/zipalign/aapt2 独立工具） | Behavioral（验签/对齐/badging） | ✓ |
| `mobile/tools/gate-b-selftest.sh` | INFRA-04 | 3 场景 | 0 | 否（反例独立构造） | Behavioral（残留必被拒） | ✓ |
| `mobile/tools/device-smoke.sh` | INFRA-04 | 真机 1 次 | 0 | 否（真实 adb） | Behavioral（安装/启动/截图） | ✓ |
| `tools/check_desktop.sh` | 项目回归红线 | 230 项 | 0 | 否 | Behavioral（名称与基线逐项一致） | ✓ |

**Disabled tests on requirements:** 0 → 无 BLOCKER
**Circular patterns detected:** 0 → `verify_clean_export.sh` 明确声明不能替代「第二台机器」人工项，本轮按用户接受风险记录，不把它冒充为已验证
**Insufficient assertions:** 0

### Decision Coverage

N/A — 本阶段目录无 `*-CONTEXT.md`，不存在 `<decisions>` 块。

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
| ----------- | ---------- | ----------- | ------ | -------- |
| INFRA-04 | 02-01…02-05（全部声明 `requirements: [INFRA-04]`） | 真机冒烟 APK：能安装、能启动、能读到原始轴值 | **SATISFIED** | 真机安装 + 启动 + `SKILL_COUNT=5` + 轴/按钮 logcat 均已实测；签名/对齐/架构/配置进包/字形覆盖/工具链文档均有机械证据。REQUIREMENTS.md 仍标 `Pending`，那是里程碑级记账，建议由编排器在收口时更新 |

**Orphaned requirements:** 无。REQUIREMENTS.md 的 Phase 映射只有 `| 2 | INFRA-04 (1) |`，5 份 PLAN 全部声明 INFRA-04。

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| ---- | ---- | ------- | -------- | ------ |
| `mobile/build/device-smoke-*.png` | — | 工程目录内的验收截图曾被 Godot 导入并打进本机 APK（`assets/build/…png.import` + `.godot/imported/…ctex`） | ℹ️ Info（已修复） | 已由 `7f311b0` 修复：`export_presets.cfg` 的 `exclude_filter` 现含 `build/*`；APK 26,797,306 字节，与干净 clone 同大小，包内 `assets/build/` 命中 0 条 |
| `mobile/ACCEPTANCE.md` | 34-68 | §2/§4/§5 记录字段仍空白，而该文档自称「唯一允许宣布真机通过的地方」；真机结论与用户接受风险只落在 `02-UAT.md` 与本报告 | ⚠️ Warning（文档同步，非 must-have） | 建议后续把 UAT 的厂商/型号/Android 版本/截图名/时间/验收人回填 §2，并把用户接受风险的跟进写进 §4/§5。不改变本轮判定，但文档与证据不同步 |
| `02-UAT.md` | 46 | §4 的 `result:` 仍写 `[pending]`，而 `Summary` 已把 §4 计入 `accepted_risk: 2` | ℹ️ Info | 记录内部不一致。按本轮调度给出的会话记录，恢复演练已通过、仅异地备份未做；UAT 的 result 行未同步更新。以 `Summary` + 本报告为准，建议下次编辑 UAT 时补一行 |
| `mobile/tools/device-smoke.sh` | 73-74 | `--dry-run` 仍只列 `aapt2 dump badging`，未提 xmltree 兜底 | ℹ️ Info | 仅说明不完整，真跑路径正确 |
| `.gitattributes` | 1-18 | 缺 `*.uid` / `*.import` 行尾规则 | ℹ️ Info（LOW-09，open） | Windows 上边车可能被改写行尾；不改变本阶段机械保证 |
| 源码债务标记 | — | `TBD`/`FIXME`/`XXX` | 无 | 本阶段改动文件扫描为零 |

### User-Accepted Risks

以下三项**不是已证实的 must-have**，而是用户明确接受的偏差。它们被计为 override 才使分数达到 35/35；写在这里是为了不把风险藏进「passed」。

#### 1. SC2 第二台不同 OEM 手机（override）

- **已做：** 单台 Motorola XT2175-2（Android 12）安装、启动、截图逐字确认：`起点错了：注意从左摇杆朝向的哪个方位起手。` 完整，`° ± → ✓ ✗` 全部为字形，`-1.000` 负号为 ASCII。
- **未做：** 第二台不同 OEM 手机。
- **用户决定：** 2026-11-05 明确「先不用考虑第二台手机，你先把这一台手机搞定就行了」。
- **跟进人：** stephen。拿到第二台手机后，按 `ACCEPTANCE.md §0–§2` 补跑 `device-smoke.sh` 并填表。
- **关闭条件：** 第二台不同 OEM 的截图与记录进入 `ACCEPTANCE.md §2`。

#### 2. SC5 密钥库离线备份（override）

- **已做：** 恢复演练通过 —— keystore 拷到临时目录、用口令经 `keytool -list -alias fifa-trainer` 打开、证书 SHA-256 与 `E1:84:1A:…:E0:46` 逐字一致、临时副本已删除。`release.keystore` 在仓库外且权限 `600`。
- **未做：** 两处不同址/不同设备的离线介质、口令存入密码管理器、`ACCEPTANCE.md §4` 四行回填。
- **用户决定：** 2026-11-05 明确「我自己安排，先往下走」。
- **跟进人：** stephen。
- **关闭条件：** `mobile/ACCEPTANCE.md §4` 四行全部填满可核对字符串，且两处介质不同址/不同设备、口令与密钥库分开存放。

#### 3. SC5 第二台干净机器重导出（override）

- **已做（替代证据）：** `verify_clean_export.sh` 在 `git clone` 出来的临时目录里从零重跑闸门 B，rc=0；APK 26,797,306 字节，证书指纹 `e1841a17…32e046` 与 `BUILD.md §6` 一致。它证明仓库状态与脚本足以复现。
- **未做：** 在另一台从未装过 Godot / 模板 / JDK / SDK / 密钥库的机器上执行 `BUILD.md §1–§8`。
- **用户决定：** 2026-11-05 决定自行安排（当前没有第二台干净机器）。
- **跟进人：** stephen。
- **关闭条件：** 在第二台机器上 `bash mobile/tools/gate-b.sh` 退出 0、末行「✓ 闸门 B 通过」，且 `apksigner --print-certs` 指纹与 `BUILD.md §6` 逐字相同，并填 `ACCEPTANCE.md §5`。

### Gaps Summary

**未闭合代码缺口：0 个。**

35 项 must-have 里，32 项是直接证据（机械闸门 + 真机），3 项是用户明确接受的 override。没有任何一项仍是「未证实且未被接受」—— 这正是本轮 `status` 从 `human_needed` 变为 `passed` 的唯一原因。SC2 的「两台 OEM」字面要求、SC5 的「异地离线备份」与「第二台机器」没有被我冒充为已验证；它们在 `## User-Accepted Risks` 中原样保留，跟进人是 stephen。

**交给 Phase 4 的真机事实（不是本阶段缺口，但不得丢失）：**

1. 安卓上右摇杆推右得到 `axis 2 = -1.000`，与桌面 SDL「右为正」相反 —— 输入层必须做符号归一。
2. 扳机静止值不稳定（首次 `-1.000`、交互后 `0.000`），行程范围也不规整 —— 必须做静止值校准。
3. Godot 4.7.2 安卓上 `_input` 收不到 `InputEventJoypadButton`，只有轮询 `Input.is_joy_button_pressed` 有效 —— 输入层必须走轮询或事件+轮询混合。

---

_Verified: 2026-11-04T17:45:28Z_
_Verifier: the agent (gsd-verifier)_
