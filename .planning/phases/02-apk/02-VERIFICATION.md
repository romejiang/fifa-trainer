---
phase: 02-apk
verified: 2026-11-04T17:36:38Z
status: human_needed
score: 33/35 must-haves verified
covered_files: [".gitattributes", ".gitignore", ".planning/phases/02-apk/02-01-PLAN.md", ".planning/phases/02-apk/02-01-SUMMARY.md", ".planning/phases/02-apk/02-02-PLAN.md", ".planning/phases/02-apk/02-02-SUMMARY.md", ".planning/phases/02-apk/02-03-PLAN.md", ".planning/phases/02-apk/02-03-SUMMARY.md", ".planning/phases/02-apk/02-04-PLAN.md", ".planning/phases/02-apk/02-04-SUMMARY.md", ".planning/phases/02-apk/02-05-PLAN.md", ".planning/phases/02-apk/02-05-SUMMARY.md", ".planning/phases/02-apk/02-UAT.md", "README.md", "mobile/ACCEPTANCE.md", "mobile/BUILD.md", "mobile/README.md", "mobile/assets/fonts/AppFont.tres", "mobile/assets/fonts/NotoSansSC-Subset.ttf", "mobile/assets/fonts/NotoSansSC-Subset.ttf.import", "mobile/assets/fonts/NotoSansSymbols2-Subset.ttf", "mobile/assets/fonts/NotoSansSymbols2-Subset.ttf.import", "mobile/assets/fonts/OFL.txt", "mobile/assets/fonts/required_glyphs.txt", "mobile/export_presets.cfg", "mobile/project.godot", "mobile/src/smoke/smoke_screen.gd", "mobile/src/smoke/smoke_screen.gd.uid", "mobile/src/smoke/smoke_screen.tscn", "mobile/tools/check_pack.gd", "mobile/tools/check_pack.gd.uid", "mobile/tools/device-smoke.sh", "mobile/tools/doctor.sh", "mobile/tools/gate-a.sh", "mobile/tools/gate-b-selftest.sh", "mobile/tools/gate-b.sh", "mobile/tools/glyph_coverage.gd", "mobile/tools/glyph_coverage.gd.uid", "mobile/tools/verify_clean_export.sh", "tools/make_font_subset.py"]
covered_digest: "v3:sha256:a1014d0ec4d534409969d8603d7f84cd5981701b628976ece77e59f07af2feb0"
behavior_unverified: 0
overrides_applied: 1
overrides:
  - must_have: "首屏完整显示最长中文字符串与 ° ± → ✓ ✗，在两台不同 OEM 手机上均无豆腐块"
    reason: "用户 2026-11-05 明确豁免第二台手机（原话：「先不用考虑第二台手机，你先把这一台手机搞定就行了」）。单台 Motorola XT2175-2 上有截图逐字确认，第二台不同 OEM 未测 —— 状态只代表「单台 + 豁免」，不代表两台已过。"
    accepted_by: "stephen (user)"
    accepted_at: "2026-11-05T00:00:00+08:00"
re_verification:
  previous_status: human_needed
  previous_score: 29/35
  gaps_closed:
    - "签名 arm64 APK 在真机安装并启动到首屏，全程不经过 Godot 编辑器（SC1）"
    - "首屏最长中文串与 ° ± → ✓ ✗ 在真机无豆腐（单台 Motorola XT2175-2；第二台由用户豁免）"
    - "蓝牙手柄原始轴与按钮通道在真机可读（SC4）"
    - "device-smoke.sh 在真机完成安装 / 启动 / 进程存活 / 截图并输出 DEVICE_SMOKE_OK"
  gaps_remaining: []
  regressions: []
human_verification:
  - test: "按 mobile/ACCEPTANCE.md §4 完成密钥库离线备份与恢复演练：两处不同址/不同设备的介质、口令与密钥库分开存放、从备份拷回后用 keytool -list 验证别名与证书 SHA-256，并把四行字段填满"
    expected: "§4 四行均有可核对字符串；两次备份互不同址或不同设备；口令存放在密码管理器；恢复演练记录日期且 keytool -list 能打开备份、别名 fifa-trainer 与指纹 e1841a17…32e046 一致"
    why_human: "备份介质、存放地点与恢复演练全部发生在仓库之外，代码与脚本无法取证；ACCEPTANCE.md §4 当前四行空白，按该文档自己的规则「留空即未闭合」"
  - test: "在一台从未装过 Godot / 导出模板 / JDK / Android SDK / 密钥库的机器上按 mobile/BUILD.md §1–§8 执行，末步 bash mobile/tools/gate-b.sh，并填 mobile/ACCEPTANCE.md §5"
    expected: "gate-b.sh 退出码 0、末行「✓ 闸门 B 通过」；apksigner --print-certs 的证书 SHA-256 与 BUILD.md §6 逐字相同（e1841a17…32e046）；§5 至少填一行"
    why_human: "工具链与密钥库是机器状态，不随仓库走；verify_clean_export.sh 只证明仓库状态足够，且跑在同一个宿主上"
---

# Phase 2: 安卓工具链 + 真机冒烟 APK Verification Report

**Phase Goal:** 用锁定的工具链导出一个签名 arm64 APK，证明它能装、能启动、中文不豆腐、共享配置真的进了包、手柄原始轴在真机上能读到。
**Verified:** 2026-11-04T17:36:38Z
**Status:** human_needed
**Re-verification:** Yes — 冒烟屏新增输入日志 + 字体重生成（818 字符）后，真机验证已完成并记录于 `02-UAT.md`

**结论先行：** 上一轮 6 项「present, behavior-unverified」中 3 项已被本轮真机证据完全闭合（SC1 安装启动、SC4 手柄轴与按钮、device-smoke 真机执行），SC2 以「单台真机 + 用户豁免」闭合（不冒充两台），剩余 2 项是成功标准 5 的人工两半（密钥库离线备份、第二台干净机器重导出）。本轮还独立复跑了全部机械闸门与一次真机装机。**0 个代码缺口**；因为有 must-have 未被证明，状态必须是 `human_needed`，而不是 `passed`。

## 本轮复核方式（不采信 SUMMARY 自述）

1. 逐字读 `02-UAT.md`，并把其中的真机声明拿到**当前仍连着的那台设备**上独立复验（设备 `ZY22F5FXX9` 在 `adb devices` 中在线）。
2. 重新执行 `gate-a.sh`、`gate-b.sh`、`gate-b-selftest.sh`、`tools/check_desktop.sh`、`verify_clean_export.sh`，全部现场取退出码与输出。
3. 重新执行三条假绿反例（配置篡改、字形清单多字、源文件多字），确认闸门仍会变红，然后还原并确认工作区干净。
4. 真机重新跑 `device-smoke.sh`，并直接读 `adb logcat` 里的 `SMOKE` 事件，而不只看截图。

**真机复验新证据（本轮亲自取得，非转述）：**

- `bash mobile/tools/device-smoke.sh` → `DEVICE_SMOKE_OK serial=ZY22F5FXX9 package=com.fifaskill.trainer pid=17686 screenshot=…`，退出码 0；`dumpsys package` 显示 `firstInstallTime 2026-11-05 00:52:00`、`lastUpdateTime 2026-11-05 01:33:54`、`primaryCpuAbi=arm64-v8a`。
- 设备属性：`ro.product.manufacturer=motorola`、`ro.product.model=XT2175-2`、`ro.build.version.release=12`。
- `adb logcat -s godot:V`：`SMOKE READY skills=5`（01:33:56，新进程 17686）；日志缓冲内共 99 条 `SMOKE` 事件，覆盖 `axis 0–7` 与按钮 `0/1/2/3/9/10`；右摇杆 `axis 2` 实测从 `-0.969` 到 `+1.000`，`axis 3` 同步变化；`idx=0 down=true` 与 `idx=9 down=true` 在同一毫秒出现（A+LB 组合）。
- 截图 `mobile/build/device-smoke-ZY22F5FXX9.png`：`SKILL_COUNT = 5`、`起点错了：注意从左摇杆朝向的哪个方位起手。` 完整、`° ± → ✓ ✗   0° 45° -1.000` 全部为字形；并显示 `#0 Xbox Series X Controller` 与 8 条轴读数。
- 进程在截图后被脚本 `am force-stop` 收尾（日志 `Force stopping … from pid 17773 uid 2000`），不是崩溃；无 `FATAL EXCEPTION` / ANR。

**机械复核（本轮全部现跑，退出码 0）：** `gate-a.sh`（`PACK_OK skills=5`、`GLYPH_OK chars=818`）、`gate-b.sh`（v2+v3、`ALIGN_OK`、仅 arm64）、`gate-b-selftest.sh`（`SELFTEST_OK`）、`tools/check_desktop.sh`（230 项全过）、`verify_clean_export.sh`（clone 内闸门 B 全绿、工作区零漂移）。

## Goal Achievement

### Observable Truths

| #   | Truth   | Status     | Evidence       |
| --- | ------- | ---------- | -------------- |
| 1 | 签名 arm64 APK 在一台真实 Android 手机上安装并启动到首屏，全程不经过 Godot 编辑器（SC1） | ✓ VERIFIED | 本轮真机重跑 `device-smoke.sh` rc=0：`am start -W -n com.fifaskill.trainer/com.godot.game.GodotAppLauncher` 成功、pid=17686 存活、截图即验收首屏；安装来自 `gate-b.sh` 的 headless 导出（`apksigner` v2+v3 true、`e1841a17…32e046`、仅 `arm64-v8a`） |
| 2 | 首屏完整显示最长中文字符串与 `° ± → ✓ ✗`，在两台不同 OEM 手机上均无豆腐块（SC2） | PASSED (override — 单台豁免) | 单台 Motorola XT2175-2 截图逐字确认：中文整串完整、五个符号为字形、`-1.000` 负号为 ASCII。第二台不同 OEM **未测**；用户 2026-11-05 明确豁免（见 frontmatter override） |
| 3 | 启动读到 `res://assets/config/` 并显示 `SKILL_COUNT = 5`，证明 `*.json` 进了 PCK（SC3） | ✓ VERIFIED | 真机 logcat `SMOKE READY skills=5`（01:33:56，pid 17686）；截图 `SKILL_COUNT = 5`；APK 内 `assets/assets/config/skills_config.json` 的 sha256 与 `shared/skills_config.json` 同为 `bccf123a…eee9`，sidecar 也逐字一致 |
| 4 | 连蓝牙手柄推右摇杆时，屏幕上的原始轴数值实时变化（SC4） | ✓ VERIFIED | logcat 99 条 `SMOKE` 事件：`axis 0–7` 全部出现；`axis 2` 从 `-0.969` 到 `+1.000`、`axis 3` 同步变化；按钮 `0/1/2/3/9/10` 均被观测，含 A+LB 同帧；截图显示 `#0 Xbox Series X Controller` + 八条轴 |
| 5 | BUILD.md 记录精确版本；release keystore 已生成（SC5 前半） | ✓ VERIFIED | `BUILD.md §1`：Godot 4.7.2-stable / 模板 4.7.2.stable / JDK 17 / build-tools 36.1.0；`gate-b.sh` 实测五项 doctor 全绿（含 `keystore … alias=fifa-trainer 可读`）；keystore 权限 `600`；`apksigner` 证书 DN `CN=FIFA Skill Trainer…` |
| 6 | release keystore 已离线备份（SC5） | ? UNCERTAIN（需人工） | `ACCEPTANCE.md §4` 四行仍为空；仓库内无任何备份位置/演练记录。不是代码缺陷，是未执行的人工动作 |
| 7 | 另一台干净机器按文档能重导出（SC5） | ? UNCERTAIN（需人工） | `ACCEPTANCE.md §5` 仍为空；本轮 `verify_clean_export.sh` rc=0，但跑在**同一台**宿主机上，只证明仓库状态足够 |
| 8 | doctor 一条命令判定缺项：非零退出 + 实际值/期望值/修法 | ✓ VERIFIED | 口令在环境时五项全绿 rc=0；不提供口令时 `✗ keystore 口令未在环境变量 …` rc=1，只打印变量名与修法 |
| 9 | 引擎版本前缀匹配：4.7.2.* 通过，4.7.3 / 4.8 失败 | ✓ VERIFIED | 本轮假 `GODOT_BIN` 实测：`4.7.3.stable.official.abc` rc=1；`4.7.2.stable.official.ed1daf0bf` rc=0 |
| 10 | 版本字符串只在 doctor.sh 一处定义，其它脚本调 doctor 断言 | ✓ VERIFIED | `GODOT_VERSION_PREFIX` / `TEMPLATE_VERSION` 仍只出现在 `doctor.sh`；`gate-a.sh:38` 只调 `doctor.sh godot` |
| 11 | 断言可按名单独运行：闸门 A 只跑引擎断言，不需模板/JDK/真机 | ✓ VERIFIED | `doctor.sh godot` 单独 rc=0；`gate-a.sh` 全程未触碰模板/JDK/设备 |
| 12 | keystore 断言缺文件/缺口令 fail-closed，且从不打印口令值 | ✓ VERIFIED | 本轮未导出口令执行 doctor → rc=1 且只显示变量名；全仓无口令字面值（仅规划文档里的占位符） |
| 13 | 设备断言从第一天存在，0 台时明确报出 0 台 | ✓ VERIFIED | 本轮设备在线时 `doctor.sh device` → `✓ device 1 台` rc=0；0 台路径上轮已实测为 `✗ device 0 台` rc=1（代码未改） |
| 14 | 闸门 A 一条命令，无模板/JDK/设备，约 10 秒 | ✓ VERIFIED | 本轮 `gate-a.sh` rc=0，七段全绿 |
| 15 | 配置与 `.sha256` 真在 PCK，`--main-pack` 读出 5 条动作 | ✓ VERIFIED | `PACK_OK skills=5`；`check_pack.gd` 不带 `--path` |
| 16 | 手改 `mobile/assets/config/` 副本后闸门 A 必红 | ✓ VERIFIED | 本轮反例：追加一个换行 → rc=1，首条即「副本与真源不一致」；已还原（`git status` 干净） |
| 17 | 首屏源码无 U+2212，轴读数由 `%+.3f` 生成 ASCII 符号 | ✓ VERIFIED | `grep U+2212`：`.gd` / `.tscn` / 字形清单均 0 次；`smoke_screen.gd:87` 使用 `%+.3f` |
| 18 | SKILL_COUNT 硬编码 5 并带「为什么可以硬编码」注释 | ✓ VERIFIED | `check_pack.gd:12-13` 常量 + 「禁止改成读到几条算几条」注释 |
| 19 | Godot 边车是提交物；干净 clone 重导入零漂移 | ✓ VERIFIED | 5 个边车（3×`*.gd.uid` + 2×`*.ttf.import`）在 `git ls-files`；本轮 `verify_clean_export.sh` rc=0、工作区无漂移 |
| 20 | 关闭系统兜底后 `° ± → ✓ ✗` 与全部中文仍可渲染 | ✓ VERIFIED | 本轮 `GLYPH_OK chars=818`（字体重生成后从 810 → 818），`allow_system_fallback=false` |
| 21 | 清单/两子集/AppFont 同源；清单多出子集没有的字时闸门红 | ✓ VERIFIED | 本轮反例：清单追加 `龘` → `GLYPH_MISSING 1: 龘` rc=1；已还原 |
| 22 | 源文件新增字符而清单未重生成时闸门 A 红 | ✓ VERIFIED | 本轮反例：`smoke_screen.gd` 追加 `龘` 注释 → `make_font_subset.py --check` rc=1 并指名缺字；已还原 |
| 23 | `✗` 由 fallback 提供，主字体不含它（双字体是硬条件） | ✓ VERIFIED | `GLYPH_BASE_HAS_X=false`；`AppFont.tres` 有 `fallbacks = Array[Font]([…Symbols2])` |
| 24 | 子集入库后构建链路不再需要字体工具 | ✓ VERIFIED | `make_font_subset.py --check` 纯标准库、`check()` 路径不调子进程（`subprocess` 只在生成路径 `:158`）；闸门 A 的 `--check` 在无 fonttools 下通过 |
| 25 | 闸门 B 一条命令产出并自证 v2 签名、16 KB 对齐、仅 arm64 | ✓ VERIFIED | 本轮 rc=0；`apksigner`：v2 true、v3 true；`zipalign -c -P 16` rc=0；badging `native-code: 'arm64-v8a'` |
| 26 | 缺 keystore/口令错时非零退出，磁盘残留过不了 apksigner | ✓ VERIFIED | 本轮 `gate-b-selftest.sh` rc=0：错口令残留被 apksigner 拒绝；缺口令 rc≠0 |
| 27 | 口令不进 stdout/stderr/仓库；导出日志的密钥库参数脱敏 | ✓ VERIFIED | 本轮自测：`✓ 导出日志不含口令 canary`、`✓ 签名命令行里的密钥库参数是脱敏的`；全仓扫描无口令字面值 |
| 28 | 闸门 B 只有一个必填输入（口令），不设 FIFA_KEYSTORE/ALIAS 也能跑 | ✓ VERIFIED | 本轮仅从 `credentials.sh` 取口令、未设两个覆盖变量，`gate-b.sh` rc=0 且使用默认密钥库路径 |
| 29 | 包名 / versionCode / versionName / 架构定死 | ✓ VERIFIED | badging：`com.fifaskill.trainer`、`versionCode='1'`、`versionName='0.1.0'`、`arm64-v8a`、`minSdkVersion:'24'` |
| 30 | APK 内配置路径是 `assets/assets/config/...` | ✓ VERIFIED | `unzip -l` 与 `gate-b` 包内容校验均命中该路径 + `.sha256` |
| 31 | 干净 clone 上重跑脚本即产出同一份 APK，零漂移 | ✓ VERIFIED | 本轮 `verify_clean_export.sh` rc=0：clone 内产物 26,797,306 字节、工作区无漂移。注：本机 APK 26,809,821 字节，差值是 `mobile/build/` 残留截图被当资源打包（见 Anti-Patterns） |
| 32 | 验收表要求两台不同 OEM + 真手柄；模拟器/单台手机不允许打勾 | ✓ VERIFIED | `ACCEPTANCE.md §0` 四条前置 + 明确禁令仍在；本阶段第二台由用户豁免，文档未改写（豁免只在 UAT/本报告记录） |
| 33 | 验收表记录可核对事实；SC5 两半各有可填字段 | ✓ VERIFIED | §2 厂商/型号/Android/截图名/时间/验收人 + 证书 SHA-256 字段、§4 备份四行、§5 第二台机器三行均在。⚠️ §2 仍空白，真机结论暂只落在 `02-UAT.md`（见 Anti-Patterns） |
| 34 | 构建文档里没有任何口令值 | ✓ VERIFIED | `BUILD.md` 只有变量名与占位；仓库扫描仅规划文档中的示例占位，无真实口令 |
| 35 | `device-smoke.sh` 装机 + 启动 + 存活 + 截图，输出 DEVICE_SMOKE_OK/FAIL | ✓ VERIFIED | 本轮真机 rc=0，末行 `DEVICE_SMOKE_OK serial=ZY22F5FXX9 package=com.fifaskill.trainer pid=17686 screenshot=…`；安装/启动/截图均为真实 adb 行为 |

**Score:** 33/35 truths verified（含 1 项 override；2 项待人工，0 failed）

### Deferred Items

无。密钥库离线备份与第二台机器重导出都不在任何后续阶段的成功标准里（Phase 9 只覆盖「干净 clone 脚本化导出」与覆盖安装），必须在本阶段由人闭合。

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
| `mobile/export_presets.cfg` | 仅 arm64、零凭据键、include_filter 覆盖 json+sha256 | ✓ VERIFIED | `arm64-v8a=true`，其余架构 false；无签名凭据键；`include_filter` 含 json 与 sha256 |
| `mobile/src/smoke/smoke_screen.gd` | 验收面板 + 输入日志（SKILL_COUNT/最长串/五符号/8 轴/按钮） | ✓ VERIFIED | 98 行；`_log_changes()` 打印 `SMOKE BTN/AXIS`，`_load_config()` 打印 `SMOKE READY`；真机 logcat 已验证 |
| `mobile/src/smoke/smoke_screen.tscn` | Header/Axes 两个 Label | ✓ VERIFIED | 26 行，`%Header` / `%Axes` |
| `mobile/tools/check_pack.gd` | 从 PCK 读配置+sidecar，`EXPECTED_SKILLS=5` | ✓ VERIFIED | 43 行；`PACK_OK skills=5` |
| `mobile/tools/gate-a.sh` | 配置→引擎→导入→语法→打包→读包→字形 | ✓ VERIFIED | 155 行；本轮 rc=0 |
| `mobile/assets/fonts/required_glyphs.txt` | 唯一字形清单 | ✓ VERIFIED | 818 行/818 字符（本次重生成新增 8 字：印/析/缀/询 + 前一轮 4 字） |
| `mobile/assets/fonts/NotoSansSC-Subset.ttf` + `.import` | CJK 子集 + 导入契约 | ✓ VERIFIED | 455,128 字节；已跟踪；APK 内有 `.fontdata` |
| `mobile/assets/fonts/NotoSansSymbols2-Subset.ttf` + `.import` | 符号 fallback（提供 ✗） | ✓ VERIFIED | 已跟踪；`GLYPH_BASE_HAS_X=false` |
| `mobile/assets/fonts/AppFont.tres` | FontVariation + fallbacks | ✓ VERIFIED | `base_font` + `fallbacks` |
| `mobile/assets/fonts/OFL.txt` | SIL OFL 1.1 | ✓ VERIFIED | 存在（版权行缺失仍为已分类 open 的 MED-05） |
| `mobile/tools/glyph_coverage.gd` | 关闭兜底逐字符断言 | ✓ VERIFIED | 80 行；本轮 `GLYPH_OK chars=818`，反例变红 |
| `mobile/tools/gate-b.sh` | doctor→gate-a→清旧→导出→四段校验 | ✓ VERIFIED | 203 行；本轮 rc=0 |
| `mobile/tools/gate-b-selftest.sh` | 未签名拒绝 + 口令不进日志 + 缺口令非零 | ✓ VERIFIED | 本轮 `SELFTEST_OK` rc=0 |
| `mobile/tools/device-smoke.sh` | 装机/启动/存活/截图，OK/FAIL token | ✓ VERIFIED（真机） | 196 行；本轮真机 rc=0，`DEVICE_SMOKE_OK`；收尾 `am force-stop` 是脚本行为 |
| `.gitignore` | `*.keystore` / `*.jks` / `*.idsig` / `*.apk` | ✓ VERIFIED | 全部在列 |
| `mobile/BUILD.md` | 版本表 + 顺序 + 密钥库 + 指纹 + 排查 + 干净机器 | ✓ VERIFIED | 340 行；§1 四行版本与实测一致 |
| `mobile/ACCEPTANCE.md` | 2 OEM × 4 观察 + 记录字段 + SC5 两半 | ✓ VERIFIED（字段在，待填） | 149 行；§0 前置与禁令完整；§2/§4/§5 仍空白（见 Warning） |
| `mobile/tools/verify_clean_export.sh` | clone 重跑闸门 B + 零漂移 | ✓ VERIFIED | 本轮 rc=0，clone 产物 26,797,306 字节 |
| `mobile/README.md` / `README.md` | 三条入口命令 + 仓库地图 | ✓ VERIFIED | 含 `gate-a.sh` / `gate-b.sh` / `device-smoke.sh` / `BUILD.md` |
| `tools/make_font_subset.py` | 抽字符 + 两子集 + OFL + `--check` | ✓ VERIFIED | 298 行；`--check` 不调子进程、不写盘 |

### Key Link Verification

| From | To  | Via | Status | Details |
| ---- | --- | --- | ------ | ------- |
| `gate-a.sh` | `tools/sync_config.py` | 第一条命令 `--check` | WIRED | 本轮反例证实会红 |
| `gate-a.sh` | `check_pack.gd` | `--main-pack` 且不带 `--path` | WIRED | `PACK_OK skills=5` |
| `gate-a.sh` | `make_font_subset.py --check` | 字形闸门之前 | WIRED | 本轮反例 rc=1 并指名缺字 |
| `gate-a.sh` | `glyph_coverage.gd` | 关闭兜底逐字符 | WIRED | `GLYPH_OK chars=818` |
| `project.godot` | `AppFont.tres` | `theme/custom_font` | WIRED | `glyph_coverage.gd` 反向断言 |
| `AppFont.tres` | 两个子集 | `base_font` + `fallbacks` | WIRED | 两者缺一即 `GLYPH_FAIL` |
| `gate-b.sh` | `doctor.sh` | 五项构建断言 | WIRED | 本轮实跑五项绿 |
| `gate-b.sh` | release 导出 | 口令环境变量 + 默认路径/别名 | WIRED | 本轮产出 26,809,821 字节签名包 |
| `gate-b.sh` | build-tools 36.1.0 | `apksigner`/`zipalign`/`aapt2` 绝对路径 | WIRED | v2/v3、ALIGN_OK、badging 全过 |
| `verify_clean_export.sh` | `gate-b.sh` | clone 内调用 | WIRED | rc=0 + 零漂移 |
| `device-smoke.sh` | `com.godot.game.GodotAppLauncher` | badging 为空时回退 `dump xmltree` | WIRED（真机确认） | 本轮真实设备安装并 `am start -W -n …/GodotAppLauncher` 成功 |
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
| 闸门 B 全链路 | `bash mobile/tools/gate-b.sh` | v2+v3、`ALIGN_OK`、arm64、rc=0 | ✓ PASS |
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
**Circular patterns detected:** 0 → `verify_clean_export.sh` 明确声明不能替代「第二台机器」人工项，已按文档口径记录
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
| `mobile/build/device-smoke-*.png` | — | 工程目录内的验收截图被 Godot 导入并打进本机 APK（`assets/build/…png.import` + `.godot/imported/…ctex`） | ⚠️ Warning | 本机 APK 26,809,821 vs 干净 clone 26,797,306 字节；不影响功能与验收。建议 `exclude_filter` 排除 `build/` 或把截图移出工程目录 |
| `mobile/ACCEPTANCE.md` | 34-68 | §2 六行记录字段仍空白，而该文档自称「唯一允许宣布真机通过的地方」；真机结论只落在 `02-UAT.md` | ⚠️ Warning | 文档与证据不同步。建议把 UAT 的厂商/型号/Android 版本/截图名/时间/验收人与证书指纹回填 §2 —— 不改变本轮判定 |
| `mobile/tools/device-smoke.sh` | 73-74 | `--dry-run` 仍只列 `aapt2 dump badging`，未提 xmltree 兜底 | ℹ️ Info | 仅说明不完整，真跑路径正确 |
| `.gitattributes` | 1-18 | 缺 `*.uid` / `*.import` 行尾规则 | ℹ️ Info（LOW-09，open） | Windows 上边车可能被改写行尾；不改变本阶段机械保证 |
| 源码债务标记 | — | `TBD`/`FIXME`/`XXX` | 无 | 本阶段改动文件扫描为零 |

### Human Verification Required

以下 2 项尚未执行，完成前不得勾选，也不得声称 Phase 2 完成。它们是成功标准 5 的人工两半，不是代码缺口。

#### 1. 密钥库离线备份与恢复演练（SC5 前一半）

**Test:** 按 `mobile/ACCEPTANCE.md` §4 操作：把 `~/.fifa-trainer/release.keystore` 备份到两处**不同址或不同设备**的介质；口令单独存进密码管理器；从其中一份备份拷回临时目录，执行 `keytool -list -alias fifa-trainer` 验证，然后删除临时副本；把四行字段（备份 1、备份 2、口令位置、演练日期与结果）填满。
**Expected:** 四行均为可核对字符串；两处备份互不同址/不同设备；口令与密钥库分开存放；`keytool -list` 能打开备份，别名 `fifa-trainer` 与证书 SHA-256 `e1841a17…32e046` 一致。
**Why human:** 介质、地点与演练都在仓库外，脚本无法取证；`ACCEPTANCE.md §4` 当前空白，按文档规则「任何一行留空即视为成功标准 5 未闭合」。

#### 2. 第二台干净机器重导出（SC5 后一半）

**Test:** 在一台从未装过 Godot / 导出模板 / JDK / Android SDK / 密钥库的机器上按 `mobile/BUILD.md` §1–§8 执行；末步 `bash mobile/tools/gate-b.sh`；填 `mobile/ACCEPTANCE.md` §5 至少一行。
**Expected:** 退出码 0，末行「✓ 闸门 B 通过」；`apksigner verify --print-certs` 的证书 SHA-256 与 `BUILD.md §6` 逐字相同（`e1841a17…32e046`）。
**Why human:** 工具链与密钥库是机器状态，不随仓库走；本机 `verify_clean_export.sh` 只证明仓库状态足够，无法证明「换一台机器也行」。

### Gaps Summary

**未闭合代码缺口：0 个。**

上一轮 6 项行为未验证中：**3 项完全闭合**（SC1 安装启动、SC4 手柄轴与按钮、device-smoke 真机执行）；**SC2 的豆腐展示已在单台真机上闭合，但「两台不同 OEM」的字面要求由用户豁免并以 override 记录，不冒充两台通过**；SC3 上轮已是 VERIFIED，本轮用真机 logcat `SMOKE READY skills=5` 再次加固。剩余 2 项未闭合。

剩余 2 项（§4 密钥库离线备份、§5 第二台干净机器重导出）是成功标准 5 中只能由人执行、且在仓库外留证的部分。它们使 `status` 保持 `human_needed`：不是 `passed`（有 must-have 未被证明），也不是 `gaps_found`（没有代码缺陷，无需 `--gaps` 计划）。

**交给 Phase 4 的真机事实（不是本阶段缺口，但不得丢失）：**

1. 安卓上右摇杆推右得到 `axis 2 = -1.000`，与桌面 SDL「右为正」相反 —— 输入层必须做符号归一。
2. 扳机静止值不稳定（首次 `-1.000`、交互后 `0.000`），行程范围也不规整 —— 必须做静止值校准。
3. Godot 4.7.2 安卓上 `_input` 收不到 `InputEventJoypadButton`，只有轮询 `Input.is_joy_button_pressed` 有效 —— 输入层必须走轮询或事件+轮询混合。

---

_Verified: 2026-11-04T17:36:38Z_
_Verifier: the agent (gsd-verifier)_
