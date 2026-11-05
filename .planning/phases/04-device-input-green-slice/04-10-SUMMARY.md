---
phase: 04-device-input-green-slice
plan: 10
subsystem: mobile-input-event-logging
tags: [godot, gdscript, input-log, adb, logcat, rotation, apk, headless-tests]

requires:
  - phase: 04-device-input-green-slice
    plan: 09
    provides: 一页式 input_setup_screen / 组合根首启路径 / APK 27,067,065 B
  - phase: 04-device-input-green-slice
    plan: 04
    provides: PadSampler._input 的事件通道与 JoyButtonMap
  - phase: 02-android-toolchain
    provides: gate-b.sh 导出链路、release keystore、apksigner 36.1.0

provides:
  - "InputLog：start_session / button / axis / format_button / format_axis / axis_should_log / rotated_path / reset"
  - "日志文件 /storage/emulated/0/Android/data/com.fifaskill.trainer/files/input_log.txt（adb 可直接读）"
  - "logcat 镜像：每行以 INPUT_EVT 开头（Godot 的 print 统一走 godot 标签）"
  - "PadSampler 接线：按钮边沿全记，轴按 |Δ| < 0.02 且 < 16 ms 节流（按设备+轴分别记基准）"
  - "2 MB 轮转：前半段写 input_log.1.txt，主文件留后半段，只丢最旧的一半"
  - "test_input_log 第 18 个套件（35 条断言，含格式 / 会话头 / 节流边界 / 轮转 / 错误路径）"
  - "mobile/build/fifa-trainer.apk 重建（27,071,318 B，证书 e1841a17…32e046 不变）"
  - "mobile/ACCEPTANCE.md §6：输入日志读取命令、字段表、轮转 / 隐私 / 失败语义"

affects: [04-07-real-device-walkthrough, phase-5-detectors, phase-9-release]

actuals:
  tokens: 7198
  tasks: 2
  commits: 3

# #3968 的实测计数（同一数字，顶层供 verify-work 的 `^commits:` 直接读取）
commits: 3
plan_head_before: 91b6031634da4095f8393b28a94f0e408a51e2a2
plan_head_after: c664ff14a05f73493fc80ec3618884ed52b2c992

tech-stack:
  added: []
  patterns:
    - "日志格式是纯函数：`format_button` / `format_axis` 只做字符串拼装，套件逐字断言；写文件与打印是两层副作用，分别可测"
    - "单句柄追加 + 逐行 flush：安卓外部存储上每个事件 open/close 太贵，静置时每轴 16 ms 的心跳行会把 I/O 放大到影响输入的量级"
    - "失败短路：一次 I/O 失败就把本会话的后续写入整体关掉（`_failed`），只留一行 `INPUT_LOG_ERROR`；日志永远不重试、不抛"
    - "轮转按「前半段进 .1、后半段留主文件」切分：只会丢最旧的一半，而不是整份换名"
    - "隐私边界写成格式本身：只有三种行，没有字段能装下序列号 / 账号 / 配置内容"

key-files:
  created:
    - mobile/src/input/input_log.gd
    - mobile/src/input/input_log.gd.uid
    - mobile/tests/unit/test_input_log.gd
    - mobile/tests/unit/test_input_log.gd.uid
  modified:
    - mobile/src/input/pad_sampler.gd
    - mobile/src/ui/main.gd
    - mobile/src/ui/input_setup_screen.gd
    - mobile/tests/core_runner.gd
    - mobile/ACCEPTANCE.md

key-decisions:
  - "写日志用静态单句柄、逐行 flush，而不是每个事件 open/close：真机静置时 6 根轴 × 62.5 行/秒，逐事件开关文件的代价会直接吃掉输入预算"
  - "轴节流键是 `<device>:<axis>`：换手柄后同号轴不能继承上一只手柄的基准值"
  - "被节流跳过的样本不刷新基准：否则静置时永远不会再写心跳行，日志会停在最后一个动作上"
  - "失败短路而不是每次重试：路径不可用时，125 Hz 事件流里的 mkdir/open 失败本身就会变成新的输入负担"
  - "非 Android 平台默认写 `user://input_log.txt`：真机路径一字不改，但桌面 / 无头冒烟不再去 `/storage` 撞 Godot 自己打印的 ERROR"
  - "`logcat` 用 `adb logcat -s godot:I | grep INPUT_EVT`，不用计划里写的 `-s INPUT_EVT`：Godot 的 `print` 统一走 `godot` 标签，按消息前缀过滤才看得到"
  - "会话头版本号显式兜底 0.1.0：工程没有 `application/config/version` 时 `get_setting` 返回空串（实测会话头变成 `v= `）"

patterns-established:
  - "「事后可读」优先于「实时可看」：先让事实落成带时间戳的文本，界面随后再消费；截图只保留给视觉结论"
  - "每一个会写盘的诊断通道都要有一条无头格式套件：格式漂移必须在闸门里变红，而不是等真机读日志的人发现"

requirements-completed: []
# INPUT-01 / INPUT-02 / INPUT-05 在本计划**不宣布完成**：
# 日志只证明「事件到达时能被记录」，不证明真机上的手柄配对 / 轴映射 / 目录可写。
# 这些仍只能由 04-07 的真机 D0–D6 回答；断言绿不等于真机通过。

coverage:
  - id: D1
    description: "InputLog 的三种行格式、2 MB 轮转、错误路径；格式是纯函数，套件逐字断言"
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_input_log.gd#_check_format / _check_append_and_session / _check_constants / _check_rotation / _check_error_path"
        status: pass
    human_judgment: false
  - id: D2
    description: "PadSampler 在 apply_event 之后接线：按钮边沿永不节流，轴按 0.02 / 16 ms 节流"
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_input_log.gd#_check_throttle_boundaries（纯函数边界）"
        status: pass
      - kind: other
        ref: "grep：mobile/src/input/pad_sampler.gd 的 _input 两个分支分别调用 InputLog.button / _log_axis"
        status: pass
    human_judgment: false
  - id: D3
    description: "会话头 + 设置页日志提示 + 新 APK 同证书 + ACCEPTANCE 读取命令"
    verification:
      - kind: other
        ref: "bash mobile/tools/gate-b.sh（末行 ✓ 闸门 B 通过）；apksigner 证书 e1841a17…32e046"
        status: pass
      - kind: other
        ref: "grep 'adb exec-out cat /sdcard/Android/data/com.fifaskill.trainer/files/input_log.txt' mobile/ACCEPTANCE.md"
        status: pass
    human_judgment: false
  - id: D4
    description: "真机上按任意键后，adb 能直接读出完整事件序列（含时间戳 / 设备号 / 按钮或轴索引）"
    verification: []
    human_judgment: true
    rationale: "目录是否可写、手柄事件是否真的以 InputEventJoypadButton / Motion 到达、轮转在真机存储上的行为，都只能由 04-07 的真机操作回答；无头环境连 /storage 路径都不存在。"

duration: 13min
completed: 2026-11-05
status: complete
---

# Phase 4 Plan 10: 输入事件日志 Summary

**每一次按键边沿与每根轴的有效变化都写成带毫秒时间戳的一行，落到 `/sdcard/Android/data/com.fifaskill.trainer/files/input_log.txt` 并镜像 logcat `INPUT_EVT`；测试者按完，`adb exec-out cat` 就能回放整段操作，不再依赖实时截图**

## Performance

- **Duration:** 13 min
- **Started:** 2026-11-05T14:46Z（约）
- **Completed:** 2026-11-05T14:59Z
- **Tasks:** 2 / 2
- **Files modified:** 9 个受版本控制的文件（4 个新建含 2 个 `.uid`，5 个修改）

## Accomplishments

- **输入层多了一条事实通道**：`InputLog` 把按键边沿写成 `t=<ms> dev=<d> btn=<i> name=<canonical> down=<0|1>`、轴值写成 `t=<ms> dev=<d> axis=<i> v=<x.xxx>`；格式由 `format_button` / `format_axis` 两个纯函数唯一决定，套件逐字断言。
- **两条读取通道**：主通道是应用外部目录里的 `input_log.txt`（release 包不需要 `run-as`）；第二条是 logcat 的 `INPUT_EVT` 前缀，文件写不进去时仍然可读。
- **日志不会拖慢输入**：静态单句柄逐行 flush；轴按「同设备同轴 `|Δ| < 0.02` 且距上次写入 `< 16 ms` 才跳过」节流，按钮边沿永不节流；一次 I/O 失败只打印一行 `INPUT_LOG_ERROR` 并短路本会话后续写入。
- **2 MB 自动轮转**：超过阈值时前半段写入 `input_log.1.txt`、后半段留在主文件，只丢最旧的一半；测试中途不需要手动清空。
- **第 18 个套件**：`test_input_log` 35 条断言（17 套件 / 1422 → 18 套件 / 1457），覆盖格式、会话头、时间戳单调、节流边界、轮转切分、错误路径不抛且只记一次。
- **会话头与页面提示**：`main.gd` 启动写 `# session v=0.1.0 t=<ms> mono`；输入设置页底部固定显示日志路径，并说明 B 只清空本页、不删日志。
- **新 APK**：27,071,318 字节（上一包 27,067,065，+4,253），证书 `e1841a17…32e046` 逐字不变，`gate-b.sh` 全绿（v2 验签、16 KB 对齐、仅 arm64）。
- **ACCEPTANCE 可照抄**：§6 新增读取命令、字段表、节流 / 轮转 / 隐私 / 失败语义；`adb logcat -s INPUT_EVT` 被纠正为 `adb logcat -s godot:I | grep INPUT_EVT`。

## Task Commits

Each task was committed atomically:

1. **Task 1: InputLog + PadSampler 接线 + 无头格式套件** — `adcfd4b` (feat)
2. **Task 2: 会话头 + 页面提示 + ACCEPTANCE + 重建 APK** — `3252b4c` (feat)
3. **修正：会话头版本号兜底 + 桌面日志路径回退** — `c664ff1` (fix)

**Plan metadata:** 见本次最终 docs 提交（SUMMARY / STATE / ROADMAP）

## Files Created/Modified

- `mobile/src/input/input_log.gd`（新，198 行）— `start_session` / `button` / `axis` / `format_button` / `format_axis` / `axis_should_log` / `now_ms` / `rotated_path` / `error_count` / `reset`；内部 `_emit` / `_append` / `_ensure_open` / `_rotate` / `_fail` / `_close_file`
- `mobile/tests/unit/test_input_log.gd`（新，191 行）— 格式 / 会话头 / 时间戳 / 节流边界 / 常量 / 轮转 / 错误路径
- `mobile/src/input/pad_sampler.gd`（+33）— `_input` 两个分支接线；`_log_axes` 按 `<device>:<axis>` 保存最后写入的 `{v, t}`；`_log_axis` 用纯函数判节流
- `mobile/src/ui/main.gd`（+10）— `_ready()` 调 `InputLog.start_session(_app_version())`；`_app_version()` 空值兜底 0.1.0
- `mobile/src/ui/input_setup_screen.gd`（+7/−1）— `LOG_HINT` 常量；`_footer_text()` 两行（设备 + 日志路径）
- `mobile/tests/core_runner.gd`（+1）— 注册 `input_log`（17 → 18 套件）
- `mobile/ACCEPTANCE.md`（+46/−5）— 尝试表加「四」；04-09 的「本次待验收」改名为「D0 操作说明」；新增「输入事件日志」小节
- `mobile/src/input/input_log.gd.uid` / `mobile/tests/unit/test_input_log.gd.uid`（新）— Godot 4.7.2 的脚本 UID 边车文件

## Decisions Made

- **单句柄 + 逐行 flush**：计划原文建议每次 `FileAccess.open(READ_WRITE)`；真机上静置心跳是 6 根轴 × 62.5 行/秒，逐事件开关外部存储会把 I/O 变成输入负担。句柄只在换路径 / 触发轮转 / 上次失败时重开。
- **轮转按前后半段切分**：`head → input_log.1.txt`，`tail` 留在主文件；只丢最旧的一半。不是整份改名（那样每次轮转都会丢掉整段历史）。
- **节流基准只记「真的写进日志」的样本**：跳过时既不写行也不更新 `{v, t}`，所以静置时每 16 ms 仍有一行心跳，日志不会停在最后一个动作上。
- **失败短路**：`_failed` 一旦置位，本会话后续 `_append` 直接返回 false，不再 mkdir/open；`start_session()` 会 `reset()`，即每次启动重新尝试一次。
- **非 Android 回退 `user://input_log.txt`**：真机路径与 adb 命令一字不改；桌面 / 无头冒烟不再触发 `DirAccess` 自己打印的 `ERROR: Could not create directory: '/storage'` + 调用栈。
- **`adb logcat -s INPUT_EVT` 纠正为 `-s godot:I | grep INPUT_EVT`**：Godot 的 `print` 统一走 `godot` 标签，`INPUT_EVT` 是消息前缀而不是 tag；照抄原命令会一行也看不到。
- **不宣布 INPUT-01 / INPUT-02 / INPUT-05 完成**：日志只证明事件到达时能被记录，真机目录可写、手柄事件真的到达仍归 04-07。

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `FileAccess.open(READ_WRITE)` 不会创建不存在的文件**
- **Found during:** Task 1 第一次跑 `test-core.sh`（`INPUT_LOG_ERROR stage=open code=7`，断言「三行」实际 0 行）
- **Issue:** Godot 的 `READ_WRITE` 等价于 `r+b`，文件不存在时返回 `ERR_FILE_NOT_FOUND`（7），不是创建。计划原文的 `_append` 只写了 `open(READ_WRITE)`，首次写入必然失败。
- **Fix:** `_ensure_open` 在打开前先 `FileAccess.file_exists`；不存在时用 `WRITE` 建空文件、关闭，再开 `READ_WRITE`。
- **Files modified:** `mobile/src/input/input_log.gd`
- **Verification:** `test_input_log` 的会话头 / 三行断言通过；`TESTS_DONE failures=0`
- **Committed in:** `adcfd4b`（Task 1）

**2. [Rule 1 - Bug] 会话头版本号是空串（`v=`）**
- **Found during:** Task 2 的无头冒烟（`INPUT_EVT # session v= t=498 mono`）
- **Issue:** 工程没有 `application/config/version`；`ProjectSettings.get_setting(key, "0.1.0")` 在该键存在但为空时返回空串，默认值不生效。会话头少了版本就无法定位是哪次构建产生的日志。
- **Fix:** `main.gd` 新增 `_app_version()`：读不到非空值时兜底 `0.1.0`（与导出配置的 versionName 一致）。
- **Files modified:** `mobile/src/ui/main.gd`
- **Verification:** 冒烟输出 `INPUT_EVT # session v=0.1.0 t=286 mono`，无 SCRIPT ERROR
- **Committed in:** `c664ff1`

**3. [Rule 2 - Missing Critical] 非 Android 环境去 `/storage` 建目录会打印与输入无关的 ERROR + 调用栈**
- **Found during:** Task 2 的无头冒烟
- **Issue:** `DirAccess.make_dir_recursive_absolute` 失败时 Godot 自己往 stderr 打 `ERROR: Could not create directory: '/storage'` 和 GDScript backtrace；桌面上每次启动都有，容易被误读成日志功能坏了。
- **Fix:** 新增 `default_path()`：Android 用 `LOG_PATH`，其他平台用 `user://input_log.txt`。真机路径与验收命令不变。
- **Files modified:** `mobile/src/input/input_log.gd`、`mobile/tests/unit/test_input_log.gd`
- **Verification:** 冒烟只剩一行 `INPUT_EVT # session ...`，无 ERROR；套件新增 1 条平台路径断言
- **Committed in:** `c664ff1`

### 计划文本修正（不是代码分歧）

**4. [文档修正] `adb logcat -s INPUT_EVT` 看不到任何行**
- Godot 的 `print` 走 logcat 标签 `godot`，`INPUT_EVT` 只是消息前缀。验收表改成 `adb logcat -s godot:I | grep INPUT_EVT`，并在正文解释原因。计划 Task 2 的自动判据只要求 `ACCEPTANCE.md` 含 `input_log.txt`，不受影响。

### 计数修正

**5. [计数修正] 字体清单与两个子集没有变化（仍是 1048 字符）**
- 计划 `files_modified` 列了 `tools/make_font_subset.py`、`required_glyphs.txt` 与两个 `.ttf`；实际新增文案里的字（志 / 删等）此前已被其他源文件的注释覆盖，`python3 tools/make_font_subset.py` 四个产物全部输出 `·`（未变），`--check` 通过。故没有提交字体改动。

---

**Total deviations:** 3 auto-fixed（2 个 Rule 1、1 个 Rule 2）+ 1 个文档修正 + 1 个计数修正
**Impact on plan:** 三处自动修复都直接关系到「日志能不能写成、写完能不能定位、失败会不会干扰输入」；没有放宽任何断言。字体无变化是按生成器的实际输出记录，不是漏做。

## Issues Encountered

- **`test-core` 里的 `Unicode parsing error ... 0xff` 是既有噪声**：来自 `test_config_loader` 故意喂的非法 UTF-8 字节 `[0xFF, 0xFE, 0x7B]`，与本计划无关；套件仍全绿。
- **首次导入没有遇到已知的 1/5 字体导入 SIGSEGV**：本次 `--import` 一次通过，没有触发重试。

## Known Stubs

None — 日志没有占位数据：每一行都由真实的按键 / 轴事件产生，格式函数没有默认分支或「待接」字段。

## Threat Flags

None — 本计划新增的文件写入面已在计划 `<threat_model>` 内：T-04-20（只写输入事件与时间戳，不含序列号 / 账号 / 配置）与 T-04-21（2 MB 轮转、失败只记一次、不阻塞输入）都有对应实现与套件断言。

## User Setup Required

- **重建 APK 需要 `GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD`**：本次按 `mobile/BUILD.md` §4 从仓库外的 `~/.fifa-trainer/credentials.sh` 在同一 shell 注入，口令没有出现在任何文件、日志或命令行参数里。
- **真机读取日志只需要 adb**：`adb exec-out cat /sdcard/Android/data/com.fifaskill.trainer/files/input_log.txt`；不需要 `run-as`，也不需要额外权限。

## Next Phase Readiness

- **04-07 下一次走查请装 27,071,318 B 的新包**：`adb uninstall com.fifaskill.trainer` → `adb install -r mobile/build/fifa-trainer.apk`。D0 操作与 04-09 相同（8 步）；装旧包会看不到本次的事件日志。
- **证据通道现在是两条**：文件 `input_log.txt`（完整、可回放）与 logcat `adb logcat -s godot:I | grep INPUT_EVT`（无需读外部存储）。`INPUT_SETUP` 每秒一行仍然保留。
- **成功标准 2/3/4/5 仍未闭合**：`REQUIREMENTS.md` 与 `ROADMAP.md` 均未勾选；Phase 4 不得宣布完成。本计划只增加「用户按了什么」的可核对事实，真机结论仍归 04-07。

---

*Phase: 04-device-input-green-slice*
*Completed: 2026-11-05*
*Status: complete（代码侧）— 真机清单仍在 04-07*

## Self-Check: PASSED

- `test -f` 全部成立：`mobile/src/input/input_log.gd` / `.gd.uid`、`mobile/tests/unit/test_input_log.gd` / `.gd.uid`
- 三个提交都是 HEAD 的祖先：`adcfd4b` / `3252b4c` / `c664ff1`
- `bash mobile/tools/test-core.sh` → `TESTS_SUITES=18` / `TESTS_ASSERTIONS=1457` / `TESTS_DONE failures=0`
- `bash mobile/tools/gate-a.sh` → `GLYPH_OK chars=1048` + `✓ res://src/ui/input_setup_screen.gd` + `✓ 闸门 A 通过`
- `bash mobile/tools/gate-b.sh` → `✓ 闸门 B 通过`；`stat -f %z` = 27071318；证书 SHA-256 `e1841a17…32e046`
- `bash tools/check_desktop.sh` → 302/302；`python3 tools/lint_core_purity.py mobile/src/core` → `LINT_OK files=28`；`python3 tools/make_font_subset.py --check` → 0
- `grep 'adb exec-out cat /sdcard/Android/data/com.fifaskill.trainer/files/input_log.txt' mobile/ACCEPTANCE.md` 命中
- `git status --porcelain shared desktop` 为空；`design/` 未被 `git add`
