---
phase: 02-apk
verified: 2026-11-04T16:14:00Z
status: human_needed
score: 29/35 must-haves verified
covered_files: [".gitattributes", ".gitignore", ".planning/phases/02-apk/02-01-PLAN.md", ".planning/phases/02-apk/02-01-SUMMARY.md", ".planning/phases/02-apk/02-02-PLAN.md", ".planning/phases/02-apk/02-02-SUMMARY.md", ".planning/phases/02-apk/02-03-PLAN.md", ".planning/phases/02-apk/02-03-SUMMARY.md", ".planning/phases/02-apk/02-04-PLAN.md", ".planning/phases/02-apk/02-04-SUMMARY.md", ".planning/phases/02-apk/02-05-PLAN.md", ".planning/phases/02-apk/02-05-SUMMARY.md", "README.md", "mobile/ACCEPTANCE.md", "mobile/BUILD.md", "mobile/README.md", "mobile/assets/fonts/AppFont.tres", "mobile/assets/fonts/NotoSansSC-Subset.ttf", "mobile/assets/fonts/NotoSansSC-Subset.ttf.import", "mobile/assets/fonts/NotoSansSymbols2-Subset.ttf", "mobile/assets/fonts/NotoSansSymbols2-Subset.ttf.import", "mobile/assets/fonts/OFL.txt", "mobile/assets/fonts/required_glyphs.txt", "mobile/export_presets.cfg", "mobile/project.godot", "mobile/src/smoke/smoke_screen.gd", "mobile/src/smoke/smoke_screen.gd.uid", "mobile/src/smoke/smoke_screen.tscn", "mobile/tools/check_pack.gd", "mobile/tools/check_pack.gd.uid", "mobile/tools/device-smoke.sh", "mobile/tools/doctor.sh", "mobile/tools/gate-a.sh", "mobile/tools/gate-b-selftest.sh", "mobile/tools/gate-b.sh", "mobile/tools/glyph_coverage.gd", "mobile/tools/glyph_coverage.gd.uid", "mobile/tools/verify_clean_export.sh", "tools/make_font_subset.py"]
covered_digest: "v3:sha256:c0faa6250f0e9361fce84aab70ec0e12382371f3e3b263fb5b900da9aa50745f"
behavior_unverified: 6
overrides_applied: 0
re_verification:
  previous_status: gaps_found
  previous_score: 29/35
  gaps_closed:
    - "device-smoke.sh 无法解析 Godot activity-alias 启动入口，真机上会在 adb install 之前以 DEVICE_SMOKE_FAIL 退出"
  gaps_remaining: []
  regressions: []
behavior_unverified_items:
  - truth: "签名 arm64 APK 在一台真实 Android 手机上安装并启动到首屏，全程不经过 Godot 编辑器（SC1）"
    test: "在真机上 adb install -r mobile/build/fifa-trainer.apk，点图标启动"
    expected: "安装成功；启动后停在验收首屏（Header 显示 SKILL_COUNT = 5），不停在启动屏、不闪退"
    why_human: "本机 adb devices 为空；安装与启动是设备运行时行为，grep/文件检查看不到"
  - truth: "首屏完整显示最长中文字符串与 ° ± → ✓ ✗，两台不同 OEM 手机均无豆腐（SC2）"
    test: "在两台不同厂商手机上逐字比对「起点错了：注意从左摇杆朝向的哪个方位起手。」与五个符号"
    expected: "整串完整、无方框/缺字/截断；五个符号为字形本身；-1.000 的负号是 ASCII 短横"
    why_human: "机械闸门只证明内嵌字体在关闭系统兜底后覆盖 810 个字符，不能证明具体 OEM ROM 的字体回退与排版结果"
  - truth: "连上蓝牙手柄推动右摇杆时，屏幕上的原始轴数值实时变化（SC4）"
    test: "配对 Xbox 或 DualSense，按任意键唤醒，推动右摇杆，观察 axis N = ±x.xxx 行"
    expected: "至少两个 axis 的数值随推动实时变化，不是卡住、不是全 0.000"
    why_human: "无手柄、无设备；Input.get_joy_axis 的运行时行为与蓝牙通道可达性只能在真机观察"
  - truth: "release keystore 已离线备份（SC5 前一半）"
    test: "按 mobile/ACCEPTANCE.md §4 填写两处备份位置、口令存放位置与恢复演练记录"
    expected: "两处介质不同址或不同设备，口令与密钥库分开存放；keytool -list 能从备份打开且别名/指纹一致"
    why_human: "备份介质与恢复演练不在仓库内，无法从代码或脚本取证"
  - truth: "另一台干净机器按 mobile/BUILD.md 能重导出（SC5 后一半）"
    test: "在一台未装过 Godot/模板/SDK 的机器上按 BUILD.md §1-§8 执行 bash mobile/tools/gate-b.sh"
    expected: "退出码 0，末行 ✓ 闸门 B 通过，证书 SHA-256 与 BUILD.md §6 逐字相同（e1841a17…32e046）"
    why_human: "本机 clean-clone 脚本只能证明仓库状态足够；工具链与密钥库是机器状态，『另一台机器』只有人能证明"
  - truth: "device-smoke.sh 在真机上完成安装、启动、进程存活与截图，并输出 DEVICE_SMOKE_OK"
    test: "接一台已授权的手机，bash mobile/tools/device-smoke.sh；然后打开 device-smoke-<serial>.png"
    expected: "末行 DEVICE_SMOKE_OK serial=… package=com.fifaskill.trainer pid=… screenshot=…；截图为验收首屏而非黑屏/启动屏"
    why_human: "脚本逻辑已用假 adb 走通，但 adb install / am start / pidof / screencap 的真实设备行为无法在无设备机器上证明"
human_verification:
  - test: "两台不同 OEM 手机各跑一次装机（bash mobile/tools/device-smoke.sh 或手工 adb install -r mobile/build/fifa-trainer.apk）并启动到首屏"
    expected: "安装成功、启动到验收屏；Header 第一行显示 SKILL_COUNT = 5（不是 0 / -1 / 配置缺失）"
    why_human: "无设备；且 SC1 的『能装、能启动』只有真机运行时能证明"
  - test: "逐字比对首屏第二行中文与第三行符号"
    expected: "「起点错了：注意从左摇杆朝向的哪个方位起手。」完整无豆腐；° ± → ✓ ✗ 全部为字形；负号为短横"
    why_human: "OEM 字体回退行为不可在开发机复现"
  - test: "蓝牙手柄配对 + 唤醒 + 推右摇杆"
    expected: "至少两个 axis 数值实时变化"
    why_human: "需要真实蓝牙手柄与手机"
  - test: "按 ACCEPTANCE.md §4 完成密钥库离线备份与恢复演练"
    expected: "四行字段全部有可核对内容；两处备份不同址/不同设备；口令与钥匙分开存放"
    why_human: "仓库外的人工操作"
  - test: "按 BUILD.md §8 在第二台干净机器重导出"
    expected: "gate-b.sh 退出 0，证书指纹与 §6 逐字相同"
    why_human: "机器状态无法由本机脚本替代"
  - test: "在真机上跑修复后的 device-smoke.sh 并检查截图"
    expected: "末行 DEVICE_SMOKE_OK serial=… package=com.fifaskill.trainer pid=… screenshot=…；截图非空且确为验收屏"
    why_human: "解析与脚本控制流已机械证明；真实 adb 的安装/启动/截图只能由设备证明"
---

# Phase 2: 安卓工具链 + 真机冒烟 APK Verification Report

**Phase Goal:** 用锁定的工具链导出一个签名 arm64 APK，证明它能装、能启动、中文不豆腐、共享配置真的进了包、手柄原始轴在真机上能读到。
**Verified:** 2026-11-04T16:14:00Z
**Status:** human_needed
**Re-verification:** Yes — after gap closure（commit `d0108b6`）

**结论先行：** 上轮唯一 BLOCKER 已修复并在真实 APK 上复验通过 —— `device-smoke.sh` 现在能从 `aapt2 dump xmltree` 解析出 activity-alias 启动入口，且用隔离的假 `adb` 驱动真实脚本走通到 `DEVICE_SMOKE_OK`。机械证明全部复绿（闸门 A/B、反例自测、干净 clone 重导出、桌面 230 项）。**当前 0 个未闭合缺口**；剩余 6 项必须由人在真机 / 另一台机器上闭合，故状态为 `human_needed`，不是 `passed`。

## Gap Closure Verification

**上轮唯一缺口：** `device-smoke.sh` 从 `aapt2 dump badging` 的 `launchable-activity` 取启动入口，而本包入口是 activity-alias；badging 不输出该行，脚本会在 `adb install` 之前以 `DEVICE_SMOKE_FAIL` 退出，并误报「这个包没有可启动的入口」。

**修复（commit `d0108b6`）：** badging 为空时回退解析 `aapt2 dump xmltree <apk> --file AndroidManifest.xml`，找带 `android.intent.category.LAUNCHER` 的 `activity` / `activity-alias` 名字；失败文案改为不再断言「包不可启动」。

**本轮逐项复验：**

1. **解析块对真实 APK 实跑**（`serial=dummy` 回显正常）：`aapt2 dump badging` 的 `launchable-activity` 仍为空 → 进入回退分支 → xmltree 105 行 → `activity=com.godot.game.GodotAppLauncher`；连续两次结果一致。
2. **Manifest 结构核验：** `E: activity-alias` 的 `android:name=com.godot.game.GodotAppLauncher`、`exported=true`、`targetActivity=com.godot.game.GodotApp`，intent-filter 同时含 `android.intent.action.MAIN` 与 `android.intent.category.LAUNCHER`；awk 取到的是 alias，不是 `com.godot.game.GodotApp`。
3. **真实脚本端到端（假 adb 隔离）：** 把 `ANDROID_SDK_ROOT` 指向临时目录，`aapt2` 符号链接到真 bin，假 `adb` 记录 argv。真实 `device-smoke.sh` rc=0，打印 `▸ 设备 dummy；包 com.fifaskill.trainer；入口 com.godot.game.GodotAppLauncher`，假 adb 实际收到 `shell am start -W -n com.fifaskill.trainer/com.godot.game.GodotAppLauncher`，末行 `DEVICE_SMOKE_OK serial=dummy package=com.fifaskill.trainer pid=4242 screenshot=…`。
4. **无设备仍 fail-closed：** `bash mobile/tools/device-smoke.sh` → `DEVICE_SMOKE_FAIL 未检测到设备（adb devices 为空）`，rc=1；`--dry-run` rc=0；`bash -n` rc=0。
5. **修复文案核验：** 失败分支现在明确写「这不是「包不可启动」的证明」，不再与真实 Manifest 相反。

**未落地的建议（非缺口）：** 上轮建议的「不需要设备的回归」没有作为持久化测试提交；本轮用临时假 adb 完成同样证明。建议后续把假 adb 固化进脚本，防止解析逻辑再次退化 —— 这不是任何 must-have，不影响本阶段判定。

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | 签名 arm64 APK 在真机安装并启动到首屏，不经过 Godot 编辑器（SC1） | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | 签名/架构已证：`apksigner` v2+v3 true、证书 `e1841a17…32e046`、`zipalign -c -P 16` 通过、`native-code: 'arm64-v8a'`；导出全程 CLI headless。安装/启动无设备可测（`adb devices` 空） |
| 2 | 首屏最长中文串 + `° ± → ✓ ✗`，两台不同 OEM 无豆腐（SC2） | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | 机械侧已证：`GLYPH_OK chars=810`（关闭系统兜底）、`GLYPH_BASE_HAS_X=false`、清单含全部动作名与五个符号；OEM 真机未测 |
| 3 | 启动读到 `res://assets/config/` 并显示 `SKILL_COUNT = 5`，证明 `*.json` 进 PCK（SC3） | ✓ VERIFIED | `--main-pack` 读回：`PACK_OK skills=5`；APK 内 `assets/assets/config/skills_config.json` 与 `shared/skills_config.json` 哈希逐字相同（`bccf123a…eee9`），sidecar 也匹配；`smoke_screen.gd:34-42` 读同一路径并写入 Header。屏上显示由人工项 ① 复核 |
| 4 | 连蓝牙手柄推右摇杆，屏幕原始轴数值实时变化（SC4） | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | `smoke_screen.gd:52-64` 每帧 `Input.get_joy_axis(d, 0..7)` 格式化 8 条轴；无手柄/无设备，运行时未证 |
| 5 | BUILD.md 记录精确版本；release keystore 已生成（SC5 前半） | ✓ VERIFIED | BUILD.md §1 四行版本（Godot 4.7.2-stable / 模板 4.7.2.stable / JDK 17 / build-tools 36.1.0）；keystore 600 权限存在、`keytool -list` 可开、能签出通过验签的包 |
| 6 | release keystore 已离线备份（SC5） | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | ACCEPTANCE.md §4 四行全空（未填），仓库内无备份证据 |
| 7 | 另一台干净机器按文档能重导出（SC5） | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | 本机 clean-clone 重导出通过（仓库状态足够）；「另一台机器」未做，ACCEPTANCE §5 空 |
| 8 | doctor 一条命令判定缺项：非零退出 + 实际值/期望值/修法 | ✓ VERIFIED | `bash mobile/tools/doctor.sh` 五项全绿 rc=0；缺口令时 keystore 项 rc=1 并打印期望/修法；未知断言名 rc=2 |
| 9 | 引擎版本前缀匹配：4.7.2.* 通过，4.7.3 / 4.8 失败 | ✓ VERIFIED | 假二进制实测：`4.7.2.stable.official.ed1daf0bf` rc=0；`4.7.3.stable.official.abc` rc=1；`4.8.stable.official.abc` rc=1 |
| 10 | 版本字符串只在 doctor.sh 一处定义，其它脚本调 doctor 断言 | ✓ VERIFIED | `GODOT_VERSION_PREFIX` / `TEMPLATE_VERSION` 仅 doctor.sh:25,31；gate-a/gate-b 只保留安装路径默认值并调 `doctor.sh godot` / `doctor.sh`，无第二份断言 |
| 11 | 断言可按名单独运行：闸门 A 只跑引擎断言，不需模板/JDK/真机 | ✓ VERIFIED | `bash mobile/tools/doctor.sh godot` 单独 rc=0；gate-a.sh:38 只调 `doctor.sh godot`；gate-a 全程 rc=0 且未触碰模板/JDK |
| 12 | keystore 断言缺文件/缺口令 fail-closed，且从不打印口令值 | ✓ VERIFIED | `env -u GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD bash mobile/tools/doctor.sh keystore` → rc=1，只打印变量名；全仓 `git grep` 无口令字面值 |
| 13 | 设备断言从第一天存在，0 台时明确报出 0 台 | ✓ VERIFIED | `bash mobile/tools/doctor.sh device` → `✗ device 0 台`，rc=1（未静默跳过） |
| 14 | 闸门 A 一条命令，无模板/JDK/设备，约 10 秒 | ✓ VERIFIED | 本轮复跑 `bash mobile/tools/gate-a.sh` rc=0：配置校验 → 引擎断言 → import → 语法 → PCK → 读包 → 字形 |
| 15 | 配置与 `.sha256` 真在 PCK，`--main-pack` 读出 5 条动作 | ✓ VERIFIED | `PACK_OK skills=5`；`check_pack.gd` 不带 `--path`；`EXPECTED_SKILLS = 5` 硬编码 |
| 16 | 手改 `mobile/assets/config/` 副本后闸门 A 必红 | ✓ VERIFIED | 负向控制：追加一个换行后 `gate-a rc=1`，首条即报「副本与真源不一致」；已还原（git status 干净） |
| 17 | 首屏源码无 U+2212，轴读数由 `%+.3f` 生成 ASCII 符号 | ✓ VERIFIED | `smoke_screen.gd/.tscn` U+2212 出现 0 次；`"%+.3f"` 在 :63 |
| 18 | SKILL_COUNT 硬编码 5 并带「为什么可以硬编码」注释 | ✓ VERIFIED | `check_pack.gd:11-13` 常量 + 注释「禁止改成读到几条算几条」 |
| 19 | Godot 边车是提交物；干净 clone 重导入零漂移 | ✓ VERIFIED | 5 个边车（3×`*.gd.uid` + 2×`*.ttf.import`）在 `git ls-files`；`verify_clean_export.sh` 在 clone 内断言已跟踪且跑完闸门 B 后 `git status` 为空 |
| 20 | 关闭系统兜底后 `° ± → ✓ ✗` 与全部中文仍可渲染 | ✓ VERIFIED | `GLYPH_OK chars=810`；`_font_files()` 对 base 与 fallbacks 逐层 `allow_system_fallback=false` |
| 21 | 清单/两子集/AppFont 同源；清单多出子集没有的字时闸门红 | ✓ VERIFIED | 负向控制：清单追加 `龘` 后 `glyph_coverage rc=1`，`GLYPH_MISSING 1: 龘`；已还原 |
| 22 | 源文件新增字符而清单未重生成时闸门 A 红 | ✓ VERIFIED | 负向控制：`smoke_screen.gd` 注释加 `龘` 后 `make_font_subset.py --check rc=1` 并指名缺字；已还原 |
| 23 | `✗` 由 fallback 提供，主字体不含它（双字体是硬条件） | ✓ VERIFIED | `GLYPH_BASE_HAS_X=false`；`AppFont.tres` 有 `fallbacks = Array[Font]([...Symbols2])` |
| 24 | 子集入库后构建链路不再需要字体工具 | ✓ VERIFIED | `make_font_subset.py --check` 纯标准库、不调子进程（`subprocess` 仅生成路径 :158）；闸门 A 的 `--check` 在无 fonttools 下通过 |
| 25 | 闸门 B 一条命令产出并自证 v2 签名、16 KB 对齐、仅 arm64 | ✓ VERIFIED | 本轮复跑 `bash mobile/tools/gate-b.sh` rc=0；apksigner v2/v3 true、`ALIGN_OK`、badging `native-code: 'arm64-v8a'` |
| 26 | 缺 keystore/口令错时非零退出，磁盘残留过不了 apksigner | ✓ VERIFIED | `gate-b-selftest.sh` 场景 A：错口令导出失败，残留 26,777,137 字节被 apksigner 拒绝；场景 C：缺口令 rc≠0 |
| 27 | 口令不进 stdout/stderr/仓库；导出日志的密钥库参数脱敏 | ✓ VERIFIED | 本轮复跑 selftest：`✓ 导出日志不含口令 canary`、`✓ 签名命令行里的密钥库参数是脱敏的`；`git grep` 无口令字面值 |
| 28 | 闸门 B 只有一个必填输入（口令），不设 FIFA_KEYSTORE/ALIAS 也能跑 | ✓ VERIFIED | 本轮 gate-b 未设两个覆盖变量仍 rc=0 |
| 29 | 包名 / versionCode / versionName / 架构定死 | ✓ VERIFIED | 本轮 badging：`com.fifaskill.trainer`、`versionCode='1'`、`versionName='0.1.0'`、`arm64-v8a`、`minSdkVersion:'24'` |
| 30 | APK 内配置路径是 `assets/assets/config/...` | ✓ VERIFIED | gate-b 包内容校验通过；`assets/assets/config/skills_config.json` + `.sha256` |
| 31 | 干净 clone 上重跑脚本即产出同一份 APK，零漂移 | ✓ VERIFIED | 本轮复跑 `verify_clean_export.sh` rc=0；clone 内闸门 B 全绿，产物 26,793,210 字节，工作区无漂移 |
| 32 | 验收表要求两台不同 OEM + 真手柄；模拟器/单台手机不允许打勾 | ✓ VERIFIED | ACCEPTANCE.md §0 四条前置 + 明确禁令；§1 2×4 表格 |
| 33 | 验收表记录可核对事实；SC5 两半各有可填字段 | ✓ VERIFIED | §2 厂商/型号/Android 版本/截图名/时间/验收人 + 证书 SHA-256；§4 备份四行；§5 第二台机器三行 |
| 34 | 构建文档里没有任何口令值 | ✓ VERIFIED | BUILD.md 只出现变量名与 `<从密码管理器复制>` 占位；全仓口令字面值扫描为空 |
| 35 | `device-smoke.sh` 装机 + 启动 + 存活 + 截图，输出 DEVICE_SMOKE_OK/FAIL | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | 上轮 BLOCKER 已修复：badging 为空时回退 xmltree，对当前 APK 解析出 `com.godot.game.GodotAppLauncher`（alias、exported=true、targetActivity=GodotApp）；假 adb 驱动真实脚本 rc=0，实际发出 `am start -W -n com.fifaskill.trainer/com.godot.game.GodotAppLauncher`，末行 `DEVICE_SMOKE_OK`。真实设备上的 install/start/pidof/screencap 仍待人工 |

**Score:** 29/35 truths verified（6 present, behavior-unverified；0 failed）

### Deferred Items

无。设备相关项不是「留给后续阶段」，而是本阶段成功标准本身，必须在 Phase 2 内由人闭合。

### Required Artifacts

| Artifact | Expected | Status | Details |
| -------- | -------- | ------ | ------- |
| `mobile/tools/doctor.sh` | 六项断言 + 命名入口 + 0/1/2 契约 | ✓ VERIFIED | 328 行；实测五项绿、keystore 缺口令红、未知名 rc=2、0 台 device 明确报出 |
| `mobile/project.godot` | config_version=5、主场景、GL Compatibility、ETC2/ASTC | ✓ VERIFIED | 全部存在；`theme/custom_font` 指 AppFont |
| `mobile/export_presets.cfg` | 仅 arm64、零凭据键、include_filter 覆盖 json+sha256 | ✓ VERIFIED | badging 只 arm64；无签名凭据键；`include_filter="assets/config/*.json,assets/config/*.sha256"` |
| `mobile/src/smoke/smoke_screen.gd` | 验收面板（SKILL_COUNT/最长串/五符号/8 轴/唤醒提示） | ✓ VERIFIED | 64 行；读包内配置 + 每帧 8 轴 |
| `mobile/src/smoke/smoke_screen.tscn` | Header/Axes 两个 Label，unique_name_in_owner | ✓ VERIFIED | 25 行，两个 `%Header`/`%Axes` |
| `mobile/tools/check_pack.gd` | 从 PCK 读配置+sidecar，`EXPECTED_SKILLS=5`，显式 quit | ✓ VERIFIED | 43 行；实测 `PACK_OK skills=5` |
| `mobile/tools/gate-a.sh` | 配置→引擎→导入→语法→打包→读包→字形 | ✓ VERIFIED | 155 行；本轮 rc=0 |
| `mobile/assets/fonts/required_glyphs.txt` | 唯一字形清单 | ✓ VERIFIED | 810 行/810 字符，含全部动作名与五个符号 |
| `mobile/assets/fonts/NotoSansSC-Subset.ttf` + `.import` | CJK 子集 + 导入契约 | ✓ VERIFIED | 已跟踪；APK 内有 `.fontdata` |
| `mobile/assets/fonts/NotoSansSymbols2-Subset.ttf` + `.import` | 符号 fallback（提供 ✗） | ✓ VERIFIED | 已跟踪；`GLYPH_BASE_HAS_X=false` 证明必要性 |
| `mobile/assets/fonts/AppFont.tres` | FontVariation + fallbacks | ✓ VERIFIED | `base_font` + `fallbacks` |
| `mobile/assets/fonts/OFL.txt` | SIL OFL 1.1 | ✓ VERIFIED | 存在（版权行缺失为 MED-05，已分类 open） |
| `mobile/tools/glyph_coverage.gd` | 关闭兜底逐字符断言 | ✓ VERIFIED | 80 行；负向控制变红 |
| `mobile/tools/gate-b.sh` | doctor→gate-a→清旧→导出→四段校验 | ✓ VERIFIED | 203 行；本轮 rc=0，产物 26,793,210 字节 |
| `mobile/tools/gate-b-selftest.sh` | 未签名拒绝 + 口令不进日志 + 缺口令非零 | ✓ VERIFIED | 本轮 `SELFTEST_OK`，rc=0 |
| `.gitignore` | `*.keystore` / `*.jks` / `*.idsig` / `*.apk` | ✓ VERIFIED | 全部在列 |
| `mobile/BUILD.md` | 版本表 + 顺序 + 密钥库 + 指纹 + 排查 + 干净机器 | ✓ VERIFIED | 340 行；§1-§8 齐全；SHA-512 两处均 128 位 |
| `mobile/ACCEPTANCE.md` | 2 OEM × 4 观察 + 记录字段 + SC5 两半 | ✓ VERIFIED | 149 行；全部空白待填（正确） |
| `mobile/tools/verify_clean_export.sh` | clone 重跑闸门 B + 零漂移 | ✓ VERIFIED | 92 行；本轮 rc=0 |
| `mobile/tools/device-smoke.sh` | 装机/启动/存活/截图，OK/FAIL token | ✓ VERIFIED（机械）/ ⚠️ 真机待测 | 修复后 176 行：badging → xmltree 回退解析出 alias；假 adb 端到端 rc=0；无设备 rc=1 且带 token。真实设备运行归入人工项 ⑥ |
| `mobile/README.md` | 三条入口命令 | ✓ VERIFIED | 含 `gate-a.sh` / `gate-b.sh` / `device-smoke.sh` |
| `README.md` | 仓库地图同步 | ✓ VERIFIED | 含 `BUILD.md` / `make_font_subset.py` |
| `tools/make_font_subset.py` | 抽字符 + 两子集 + OFL + `--check` | ✓ VERIFIED | 298 行；`--check` 不调子进程、不写盘 |

### Key Link Verification

| From | To | Via | Status | Details |
| ---- | -- | --- | ------ | ------- |
| `gate-a.sh` | `tools/sync_config.py` | 第一条命令 `--check` | WIRED | 负向控制证实会红 |
| `gate-a.sh` | `check_pack.gd` | `--main-pack` 且不带 `--path` | WIRED | `PACK_OK skills=5` |
| `gate-a.sh` | `make_font_subset.py --check` | 字形闸门之前 | WIRED | 负向控制 rc=1 |
| `gate-a.sh` | `glyph_coverage.gd` | 关闭兜底逐字符 | WIRED | `GLYPH_OK chars=810` |
| `project.godot` | `AppFont.tres` | `theme/custom_font` | WIRED | `glyph_coverage.gd` 反向断言 `ThemeDB.fallback_font.resource_path` |
| `AppFont.tres` | 两个子集 | `base_font` + `fallbacks` | WIRED | 两者缺一即 `GLYPH_FAIL` |
| `gate-b.sh` | `doctor.sh` | 五项构建断言 | WIRED | 实跑五项绿 |
| `gate-b.sh` | release 导出 | 口令环境变量 + 默认路径/别名 | WIRED | 本轮产出 26,793,210 字节签名包 |
| `gate-b.sh` | build-tools 36.1.0 | `apksigner`/`zipalign`/`aapt2` 绝对路径 | WIRED | 三段全部通过 |
| `verify_clean_export.sh` | `gate-b.sh` | clone 内调用 | WIRED | rc=0 + 零漂移 |
| `device-smoke.sh` | `com.godot.game.GodotAppLauncher` | `aapt2 dump badging` 为空时回退 `dump xmltree`，按 LAUNCHER 取 name | **WIRED（本轮修复）** | 真实 APK 解析出 alias；假 adb 记录到 `am start -W -n com.fifaskill.trainer/com.godot.game.GodotAppLauncher` |
| `ACCEPTANCE.md` | `device-smoke.sh` | 「装机与启动由脚本完成」 | WIRED | 解析阻断已消除；真机执行由人工项 ⑥ 复核 |
| `smoke_screen.gd` | `res://assets/config/skills_config.json` | `FileAccess` + `JSON.parse_string` | WIRED | 路径与包内一致；运行时显示待人工 |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
| -------- | ------------- | ------ | ------------------ | ------ |
| `smoke_screen.gd` Header | `_skill_count` | `res://assets/config/skills_config.json`（包内，哈希与真源一致） | 是（5） | ✓ FLOWING（机械侧）；屏上显示待人工 |
| `smoke_screen.gd` Axes | `Input.get_joy_axis(d, axis)` | 引擎运行时手柄驱动 | 运行时才有 | ⚠️ STATIC（无手柄，未观测） |
| `check_pack.gd` | `EXPECTED_SKILLS` + `.sha256` | PCK 内文件 | 是 | ✓ FLOWING |
| `device-smoke.sh` 启动入口 | `activity` | badging → xmltree 回退 → Manifest 的 LAUNCHER alias | 是（`com.godot.game.GodotAppLauncher`） | ✓ FLOWING（真实 APK + 假 adb 双重） |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
| -------- | ------- | ------ | ------ |
| 闸门 A 全链路 | `bash mobile/tools/gate-a.sh` | `PACK_OK skills=5`、`GLYPH_OK chars=810`、rc=0 | ✓ PASS |
| 闸门 B 全链路 | `bash mobile/tools/gate-b.sh` | v2+v3、指纹一致、`ALIGN_OK`、arm64、26,793,210 字节、rc=0 | ✓ PASS |
| 闸门 B 反例 | `bash mobile/tools/gate-b-selftest.sh` | `SELFTEST_OK`，未签名残留被拒、canary 不入日志、缺口令 rc≠0 | ✓ PASS |
| 桌面回归 | `bash tools/check_desktop.sh` | 「230 项检查全部通过，名称与基线逐项一致」 | ✓ PASS |
| 干净 clone 重导出 | `bash mobile/tools/verify_clean_export.sh` | rc=0，零漂移，产物同尺寸 | ✓ PASS |
| 解析块对真实 APK（`serial=dummy`） | 逐字执行修复块 | badging 空 → xmltree 105 行 → `activity=com.godot.game.GodotAppLauncher`；二次运行一致 | ✓ PASS |
| 无设备真跑 | `bash mobile/tools/device-smoke.sh` | `DEVICE_SMOKE_FAIL 未检测到设备（adb devices 为空）`，rc=1 | ✓ PASS（按预期失败） |
| dry-run | `bash mobile/tools/device-smoke.sh --dry-run` | rc=0，打印工具绝对路径与期望 token | ✓ PASS |
| 假 adb 端到端 | 临时 `ANDROID_SDK_ROOT` + 假 adb 驱动真实脚本 | rc=0；`入口 com.godot.game.GodotAppLauncher`；收到 `am start -W -n com.fifaskill.trainer/com.godot.game.GodotAppLauncher`；末行 `DEVICE_SMOKE_OK` | ✓ PASS |
| 语法 | `bash -n mobile/tools/device-smoke.sh` | rc=0 | ✓ PASS |
| 配置漂移负向控制 | 手改副本 → `gate-a.sh` | rc=1，首条即红 | ✓ PASS |
| 源文件字形漂移负向控制 | 加 `龘` → `make_font_subset.py --check` | rc=1，指名缺字 | ✓ PASS |
| 子集缺字负向控制 | 清单加 `龘` → `glyph_coverage.gd` | rc=1，`GLYPH_MISSING 1: 龘` | ✓ PASS |
| 版本前缀负向控制 | 假 `GODOT_BIN` 4.7.3 / 4.8 | rc=1 / rc=1（4.7.2 rc=0） | ✓ PASS |
| APK 内配置逐字比对 | `unzip -p … \| shasum -a 256` | 与 `shared/skills_config.json` 同为 `bccf123a…eee9` | ✓ PASS |

### Probe Execution

N/A — 本阶段未声明任何 `probe-*.sh`，成功标准也不涉及探针。

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
| ----------- | ---------- | ----------- | ------ | -------- |
| INFRA-04 | 02-01…02-05（全部声明 `requirements: [INFRA-04]`） | 真机冒烟 APK：能安装、能启动、能读到原始轴值 | **PARTIAL（阻塞已消除）** | 包结构/签名/配置进包/字形覆盖/工具链/文档均有机械证据；上轮 device-smoke 的启动入口阻断已修复并双重复验。剩余「安装、启动、读原始轴」三项需真机。REQUIREMENTS.md 仍标 `Pending`，与现状一致 |

**Orphaned requirements:** 无。REQUIREMENTS.md 的 Phase 映射只有 `| 2 | INFRA-04 (1) |`，5 份 PLAN 全部声明 INFRA-04，无遗漏、无多报。

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| ---- | ---- | ------- | -------- | ------ |
| `mobile/tools/device-smoke.sh` | 73-74 | `--dry-run` 仍只列 `aapt2 dump badging`，未提 xmltree 兜底 | ℹ️ Info | 仅 dry-run 说明不完整，真跑路径正确 |
| `mobile/tools/device-smoke.sh` | 127-139 | 无持久化的无设备回归；本轮用临时假 adb 验证 | ℹ️ Info | 未来改解析逻辑时无自动化守门；建议固化假 adb 回归 |
| `.gitattributes` | 1-17 | 缺 `*.uid` / `*.import` 行尾规则 | ℹ️ Info（LOW-09，已分类 open） | Windows 上边车可能被改写行尾；不改变本阶段机械保证 |
| `mobile/export_presets.cfg` | 11, 45 | `all_resources` 把两个闸门脚本打进包；`permissions/vibrate=true` 无对应代码 | ℹ️ Info（INFO-01，已分类 open） | 包体略大与多余权限；不影响正确性 |
| `mobile/.godot` / `mobile/build` | — | 本机存在导出产物与缓存 | ℹ️ Info | 均被 `.gitignore` 覆盖；`git ls-files` 无 `.apk/.keystore/.jks/.idsig` |
| 源码债务标记 | — | `TBD`/`FIXME`/`XXX` | 无 | `device-smoke.sh` 与全仓源码均为零 |

### Human Verification Required

以下 6 项必须在真机/另一台机器上完成；完成前不得勾选，也不得声称 Phase 2 完成。

#### 1. 两台不同 OEM 手机：安装 + 启动到首屏（SC1）

**Test:** 先用 `bash mobile/tools/device-smoke.sh`（或手工 `adb install -r mobile/build/fifa-trainer.apk`）在手机 A、手机 B 上各装一次，然后点图标启动。
**Expected:** 安装成功；启动后停在验收首屏（不是启动屏、不闪退）；`Header` 第一行为 `SKILL_COUNT = 5`。
**Why human:** `adb devices` 为空；安装与启动是设备运行时行为。

#### 2. 两台不同 OEM 手机：中文与符号不豆腐（SC2）

**Test:** 逐字比对第二行 `起点错了：注意从左摇杆朝向的哪个方位起手。`（21 字，全角冒号与句号）与第三行 `° ± → ✓ ✗   0°  45°  -1.000`。
**Expected:** 中文整串完整、无方框/缺字/截断；五个符号为字形本身；`-1.000` 的负号是 ASCII 短横。
**Why human:** 机械闸门只证明内嵌字体覆盖 810 字符（且已关闭系统兜底），不能证明具体 OEM ROM 的字体回退与排版。

#### 3. 蓝牙手柄：原始轴在动（SC4）

**Test:** 在手机系统蓝牙里配对 Xbox 或 DualSense；打开应用后按手柄任意键唤醒；推动右摇杆。
**Expected:** 至少两个 `axis N = ±x.xxx` 数值随推动实时变化；不是卡住、不是全 0.000。
**Why human:** 需要真实蓝牙手柄与手机。

#### 4. 密钥库离线备份（SC5 前一半）

**Test:** 按 `mobile/ACCEPTANCE.md` §4 填写：两处备份位置（不同址或不同设备）、口令存放位置、恢复演练日期与结果。
**Expected:** 四行全部有可核对内容；`keytool -list` 能从备份打开，别名 `fifa-trainer` 与证书 SHA-256 `e1841a17…32e046` 对得上。
**Why human:** 介质与演练在仓库外。

#### 5. 第二台干净机器重导出（SC5 后一半）

**Test:** 在未装过 Godot/模板/SDK 的机器上按 `mobile/BUILD.md` §1-§8 执行；末步 `bash mobile/tools/gate-b.sh`。
**Expected:** 退出码 0、末行 `✓ 闸门 B 通过`；`apksigner --print-certs` 的证书 SHA-256 与 BUILD.md §6 逐字相同。
**Why human:** 工具链与密钥库是机器状态；本机 clean-clone 只证明仓库状态足够。

#### 6. 真机跑修复后的 device-smoke.sh

**Test:** 接一台已授权手机（`adb devices` 显示 `device`），执行 `bash mobile/tools/device-smoke.sh`，再打开 `mobile/build/device-smoke-<serial>.png`。
**Expected:** 末行 `DEVICE_SMOKE_OK serial=<serial> package=com.fifaskill.trainer pid=<pid> screenshot=<path>`；截图非空且确为验收首屏。
**Why human:** 入口解析与控制流已机械证明；真实 `adb install` / `am start` / `pidof` / `screencap` 的行为只能由设备证明。

### Gaps Summary

**未闭合缺口：0 个。** 上轮唯一 BLOCKER（`device-smoke.sh` 无法解析 activity-alias 启动入口）已由 commit `d0108b6` 修复，并在真实 APK 上逐字复验、再用假 adb 驱动真实脚本走通到 `DEVICE_SMOKE_OK`。

剩余 6 条 ⚠️ 不是缺口，而是本阶段成功标准中**只能由人完成**的部分（两台不同 OEM 手机、蓝牙手柄、离线备份、第二台机器、真机脚本执行），已逐条列入 Human Verification Required。故状态为 `human_needed`。

---

_Verified: 2026-11-04T16:14:00Z_
_Verifier: the agent (gsd-verifier)_
