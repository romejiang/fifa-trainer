---
phase: 04-device-input-green-slice
plan: 06
subsystem: ui-practice-green-slice
tags: [gdscript, godot, practice-screen, result-banner, 60hz, integration-test, font-closed-world, acceptance-checklist]

requires:
  - phase: 04-device-input-green-slice
    plan: 05
    provides: OnboardingFlow / main.gd 组合根 / onboarding_screen / 字形闭世界断言 / gate-a 的 5 条 check_script
  - phase: 04-device-input-green-slice
    plan: 04
    provides: PadStateBuffer（events_motion / poll_edges / delta_ms_percentiles）与 PadSampler 线程 id
  - phase: 04-device-input-green-slice
    plan: 02
    provides: TapRuntime.pop_outcomes / status / 计数器 / layout_confirmed 硬门；Outcome.seq
  - phase: 04-device-input-green-slice
    plan: 01
    provides: TapDetector 的 Failure.message / Hit.detail / status 文案
  - phase: 03-core-foundation
    provides: ConfigLoader / ConfigValidator / ConfigResult；lint 与 LINT_OK
  - phase: 02-android-toolchain
    provides: Godot 4.7.2-stable、AppFont（FontVariation）、字形闸门、*.gd.uid 约定

provides:
  - "mobile/src/ui/practice_screen.gd / .tscn：S12–S14 渲染器；setup(runtime, layout, buffer) 唯一注入；每帧全量 drain pop_outcomes；10 Hz 节流块；%DebugPanel ASCII 诊断行"
  - "mobile/src/ui/result_banner.gd：static accepts(shown_seq, seq) 单调去重；show_outcome 只取 Outcome 字段；HOLD_SECONDS 1.5 s；clear() 不重置序号"
  - "mobile/src/ui/main.gd：练习屏实例化与占位 queue_free、进入练习时容器 + 节点双可见、空布局 LAYOUT_ERROR、1 Hz PAD_DIAG/PAD_AXIS/PAD_DEV"
  - "mobile/tests/unit/test_green_slice.gd：真实配置字节 → ConfigLoader/Validator → select_taps_skill → TapRuntime 的 60 Hz 七段集成套件"
  - "tools/make_font_subset.py：三个新 UI 文件 + 7 个会渲染的 core 源进 CHAR_SOURCES；新增 RENDER_SOURCES 第二条机械断言"
  - "mobile/assets/fonts/*：清单 876 → 992 字符，两个子集重生成；AppFont.tres 显式 wght=400"
  - "mobile/ACCEPTANCE.md 第 6 节：D0–D6 真机记录表（全空，含证书 SHA-256 与 %DebugPanel / PAD_* 抄录来源）"

affects: [04-07-device-checklist, phase-5-detectors, phase-7-feedback]

actuals:
  tokens: 9500
  tasks: 3
  commits: 3

plan_head_before: fd3ec12c3e10f44787b415baf44828ee79cc3075
plan_head_after: 8c1fc74e8b56e7e3531e314ace92673cab105376

tech-stack:
  added: []
  patterns:
    - "展示端唯一结果通路：TapRuntime.pop_outcomes() 全量 drain → result_banner.show_outcome；UI 不拼原因、不去重业务"
    - "单调序号去重：accepts(shown_seq, seq) = seq > shown_seq；clear() 只清显示，不回退序号"
    - "双可见性：练习屏容器的 visible 与练习屏节点自身的 visible 是两个独立开关，进入练习必须同时置真"
    - "10 Hz 单节流块：%LiveMs / %SuccessCount / %DebugPanel 共用一个 _accum < 0.1，且只在字符串变化时赋值"
    - "字形闭世界两条边：src/ui 目录自动枚举 + RENDER_SOURCES 点名会渲染的 core 文案；--check 同时跑两条"
    - "集成测试用真实配置字节与 60 Hz 网格：不在测试里复刻筛选循环，也不手写期望值"

key-files:
  created:
    - mobile/src/ui/practice_screen.gd
    - mobile/src/ui/practice_screen.gd.uid
    - mobile/src/ui/practice_screen.tscn
    - mobile/src/ui/result_banner.gd
    - mobile/src/ui/result_banner.gd.uid
    - mobile/tests/unit/test_green_slice.gd
    - mobile/tests/unit/test_green_slice.gd.uid
  modified:
    - mobile/src/ui/main.gd
    - tools/make_font_subset.py
    - mobile/assets/fonts/required_glyphs.txt
    - mobile/assets/fonts/NotoSansSC-Subset.ttf
    - mobile/assets/fonts/NotoSansSymbols2-Subset.ttf
    - mobile/assets/fonts/AppFont.tres
    - mobile/tools/gate-a.sh
    - mobile/tests/core_runner.gd
    - mobile/ACCEPTANCE.md

key-decisions:
  - "横幅去重做成静态纯函数 accepts(shown_seq, seq)：行为测试可直接 preload 脚本调用，不需要实例化 Node；clear() 不重置 _shown_seq（序号单调，重置会重播旧结果）"
  - "练习屏 _process 第一句是 if not visible: return；组合根进入练习时必须同时置 %Practice 容器与练习屏节点可见 —— 只显示容器会让 drain / 横幅 / %DebugPanel 静默停在屏幕外"
  - "setup() 是唯一注入点：_ready() 只 pass；动作名与 hint 只在 setup 里赋值，先 add_child 后 setup 是常态"
  - "布局三支文案由注入值决定：playstation / xbox / 其余一律「布局未确认，请返回引导重选」，绝不回退到 Xbox 键名"
  - "%SuccessCount 取「成功 %d / %d」而不是裸「%d / %d」；%LiveMs 只把字面量「待机」映射成「等待第一下」，其余逐字显示 runtime.status()"
  - "%DebugPanel 纯 ASCII 单行 ev_m/ev_b/poll/dt95/g，与 %LiveMs、%SuccessCount 共用 10 Hz 节流；只在文本变化时赋值"
  - "不登记 config_store.gd / profile_store.gd：它们的 notice 在 Phase 4 从未渲染（main.gd 只渲染 ConfigResult.to_text() 的 errors/warnings）；S99 正文来自 config_loader / config_validator / overlay_merge"
  - "RENDER_SOURCES 是字形闭世界的第二条边：src/core 没有目录级边界，只能点名 7 个会渲染的文件，缺一个 --check 即红"
  - "AppFont.tres 显式 variation_opentype wght=400：UI-SPEC G11 的 1 m 可读性修复，不改 cmap、不影响 GLYPH_OK"
  - "test_green_slice 七段各自新建 TapRuntime：手势锁 / 重新武装 / 冷却都存活在实例里，复用会让上一段污染下一段"
  - "ACCEPTANCE 第 6 节只写判据与空格子：无设备时留空即未闭合，verify 断言不存在任何 - [x]"

patterns-established:
  - "结果呈现的信任边界：屏幕上每条结论只来自 Outcome（ok / message / detail / elapsed_ms），UI 不重拼"
  - "诊断出口双通道：屏上 %DebugPanel + logcat 1 Hz PAD_DIAG/PAD_AXIS/PAD_DEV，D5/D6 都有可抄录原文"
  - "集成套件的采样率就是手机采样率：60 Hz 网格证明毫秒阈值在抽稀后仍成立"
  - "新 UI 文件 = 字形闭世界的一条边：先登记、再重生成、再上屏；core 渲染源另有一条点名断言"

requirements-completed: []
# INPUT-01 / INPUT-04 / INPUT-05 在本计划**不宣布完成**：
# - INPUT-01：Xbox / PlayStation 两套键名文案与布局来源已就位；两只真手柄各做一次由 04-07 的 D3/D4 证明。
# - INPUT-04：布局决定文案的呈现端已就位；确认页与实测索引由 04-05 状态机 + 04-07 的 D3 记录。
# - INPUT-05：结果只来自运行时队列的呈现证据已由 test_green_slice 证明；真机事件计数与 Δt 分布由 04-07 的 D5/D6 记录。
# 依据 plan 的 Flagged Assumptions：探针结果仍是 unclassified，不得据此勾选。

coverage:
  - id: D1
    description: "练习屏 S12–S14：进入练习后可见；横幅成功显示「✓ 做对了」+ detail，失败显示「✗ 没做对」+ message"
    verification:
      - kind: integration
        ref: "mobile/src/ui/practice_screen.tscn 实例化冒烟（headless：TITLE=✓ 做对了 / REASON / SEQ2_TITLE=✗ 没做对）"
        status: pass
      - kind: unit
        ref: "mobile/tests/unit/test_green_slice.gd#_check_result_banner_dedupe"
        status: pass
    human_judgment: false
  - id: D2
    description: "一次尝试恰好一条判定；同 seq 重放被忽略；两次尝试两条判定"
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_green_slice.gd#_check_single_shot_success / _check_two_shots / _check_result_banner_dedupe"
        status: pass
    human_judgment: false
  - id: D3
    description: "未确认布局时 60 Hz 合成搓射零判定、hits/attempts 为 0、status 直说「未确认布局」"
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_green_slice.gd#_check_layout_gate"
        status: pass
    human_judgment: false
  - id: D4
    description: "五种结果各自归因：ok / too_fast / too_slow / hold_short，毫秒落在量化区间"
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_green_slice.gd#_check_single_shot_success / _check_too_fast / _check_too_slow / _check_hold_short"
        status: pass
    human_judgment: false
  - id: D5
    description: "布局决定键名文案；空布局显示「布局未确认，请返回引导重选」；%LiveMs 把「待机」映射成「等待第一下」"
    verification:
      - kind: integration
        ref: "grep 三支逐字文案 + practice_screen.tscn 字号/节点归属断言 + 段落实例化冒烟"
        status: pass
    human_judgment: false
  - id: D6
    description: "全量 drain：每帧 pop_outcomes() 逐条显示，不假设最多一条，不取 [0]"
    verification:
      - kind: integration
        ref: "grep 'pop_outcomes()\\[0\\]' = 0 + test_green_slice 两发两条"
        status: pass
    human_judgment: false
  - id: D7
    description: "字形闭世界扩到会渲染的 core 文案；新 UI 文件未登记即 --check 失败；GLYPH_OK chars=992"
    verification:
      - kind: integration
        ref: "python3 tools/make_font_subset.py --check + bash mobile/tools/gate-a.sh → GLYPH_OK chars=992"
        status: pass
    human_judgment: false
  - id: D8
    description: "真机 D0–D6：首次启动零触摸、轴落盘、换手柄重探与复用门两面、布局确认、一次/两次判定、M1–M6 输入体检"
    verification: []
    human_judgment: true
    rationale: "蓝牙配对、安卓 OEM 输入栈、真实轴映射与按键索引、事件到达间隔分布只能在真机 + 真手柄上测量；ACCEPTANCE 第 6 节全部留白，由 04-07 录制。"

duration: 9min
completed: 2026-11-05
status: complete
---

# Phase 4 Plan 06: 练习屏 + 结果横幅 + 60 Hz 集成竖切 + 真机记录表 Summary

**「做一次绿色搓射 → 屏幕出现且只出现一条判定」的呈现端闭合：真实配置字节在 60 Hz 合成时间轴上产出 success / too_fast / too_slow / hold_short / 两发两条五种结果，横幅以 `Outcome.seq` 单调去重且只显示运行时给的字段；同时字形闭世界补上 7 个会渲染的 core 源（876 → 992 字符），真机验收有了唯一的、无法预填的落点**

## Performance

- **Duration:** 9 min
- **Started:** 2026-11-05T11:09:08Z
- **Completed:** 2026-11-05T11:18:26Z
- **Tasks:** 3
- **Files modified:** 16（7 新建、9 修改；含 3 个 `.gd.uid` 边车与 2 个字体子集）

## Accomplishments

- `practice_screen.gd`：`setup(runtime, layout, buffer)` 唯一注入；`_process` 第一句 `if not visible: return`；每帧全量 drain `pop_outcomes()` 并逐条 `show_outcome`；`%LiveMs` / `%SuccessCount` / `%DebugPanel` 收在同一个 10 Hz 节流块，计数与诊断行只在字符串变化时赋值；`待机` 显式映射为「等待第一下」。
- `practice_screen.tscn`：8 个 `unique_name_in_owner` 节点落在 UI-SPEC §2.3 的条带内（24/112/208/256/304–584/600–680）；根节点与 `%ResultBanner` 各绑一个 `script = ExtResource`；`%Title` / `%Reason` 真实挂在 `parent="ResultBanner"` 下，字号 72 / 40。
- `result_banner.gd`：`static accepts(shown_seq, seq) -> bool` 是去重语义的唯一实现；`show_outcome` 只取 `Outcome.ok/detail/message/seq`，不做业务判断；成功绿 `#66BB6A`、失败红 `#EF5350`；`clear()` 不重置序号。
- `main.gd`：实例化练习屏进 `%Practice`、`queue_free()` 占位 Label；`can_enter_practice()` 首次为真时用 `effective_layout()` 调 `setup`，容器与练习屏节点**都**置可见；空布局打 `LAYOUT_ERROR` 并留在引导；断连分支保留 `_practice_entered = false` 让下次重新 setup。
- 1 Hz 诊断日志：`PAD_DIAG`（events / poll / p50 / p95 / max / 两个线程 id）+ 每轴一行 `PAD_AXIS`（v / min / max）+ `PAD_DEV`（name / guid）；`buffer.device < 0` 时不打印。
- `test_green_slice`：真实配置字节 → `ConfigLoader.decode_bytes` → `ConfigValidator.validate` → `TapRuntime.select_taps_skill` → 60 Hz 合成轴；七段 `_check_*` 覆盖布局硬门、成功、太快、太慢、保持不够、两发独立与 `accepts` 行为去重。二次 drain 为空证明队列语义。
- 字形闭世界：`CHAR_SOURCES` 增加 3 个 UI 文件 + 7 个会渲染的 core 源；新增 `RENDER_SOURCES` 第二条断言并在 `--check` 中执行；清单 876 → **992**，`GLYPH_OK chars=992`；`AppFont.tres` 显式 `wght=400`。
- `ACCEPTANCE.md` 第 6 节：D0–D6 七组表格全部留白；D0 写死 `events_motion = 0` 停止条件与证书 SHA-256 落点；D2 写死「外层 key」拒绝面与「只改 device_name 不会命中」；D6 写死 `%DebugPanel` + `PAD_DIAG/PAD_AXIS/PAD_DEV` 来源，缺 `PAD_DIAG` 即判失败。
- 基线全绿：`TESTS_SUITES=15` / `TESTS_ASSERTIONS=1224` / `TESTS_DONE failures=0`；`gate-a.sh` 五个脚本全部真编译并 `GLYPH_OK chars=992`；`test-core-selftest.sh` → `SELFTEST_OK cases=7`；`check_desktop.sh` 230/230；`LINT_OK files=27`。

## Task Commits

Each task was committed atomically:

1. **Task 1: 练习屏 + 结果横幅 + 组合根接线 + 字形登记与重生成** — `0c0ffbd` (feat)
2. **Task 2: 无设备竖切集成套件（真实配置 60 Hz 到结果序列）** — `f0eb11b` (test)
3. **Task 3: ACCEPTANCE 第 6 节 Phase 4 真机记录表** — `8c1fc74` (docs)

**Plan metadata:** 见本次最终 docs 提交（SUMMARY / STATE / ROADMAP）

## Files Created/Modified

- `mobile/src/ui/practice_screen.gd`（122 行）— S12–S14 渲染器、10 Hz 节流、全量 drain、三支布局文案
- `mobile/src/ui/practice_screen.tscn`（82 行）— 8 个唯一节点；根与 `%ResultBanner` 双脚本绑定；Title 72 / Reason 40
- `mobile/src/ui/result_banner.gd`（72 行）— `accepts` 静态谓词、`show_outcome`、1.5 s 停留、`clear`
- `mobile/src/ui/main.gd`（+61 行）— 练习屏实例化 / 占位释放 / 双可见 / `LAYOUT_ERROR` / 1 Hz 诊断
- `mobile/tests/unit/test_green_slice.gd`（281 行）— 七段集成断言 + 60 Hz 时间轴生成
- `mobile/tests/core_runner.gd` — `SUITES` 增至 15
- `tools/make_font_subset.py` — 10 个新 `CHAR_SOURCES` 条目 + `RENDER_SOURCES` + `assert_render_sources_registered()`
- `mobile/tools/gate-a.sh` — 字形步骤明写覆盖「目录枚举 + RENDER_SOURCES 点名」两条边
- `mobile/assets/fonts/required_glyphs.txt` — 992 个字符（+116）
- `mobile/assets/fonts/NotoSansSC-Subset.ttf` / `NotoSansSymbols2-Subset.ttf` — 重生成
- `mobile/assets/fonts/AppFont.tres` — `variation_opentype = { &"wght": 400 }`
- `mobile/ACCEPTANCE.md` — 第 6 节（+141 行，D0–D6 全空）
- 三个 `.gd.uid` 边车 — `--import` 生成，按 Phase 2 约定提交

## Decisions Made

- **去重是纯函数而不是实例状态机的一部分**：`accepts(shown_seq, seq)` 可以被测试直接调用，证明「同一 seq 只显示一次」有牙齿；`clear()` 不重置 `_shown_seq`，避免旧结果重播。
- **练习屏 `_process` 的第一句必须是可见性早退**：这不是性能优化，而是「只显示容器」这一接线错误唯一会静默吞掉判定的位置；组合根因此同时翻两个 visible。
- **`setup` 是唯一注入点**：`_ready()` 只 `pass`；先 `add_child` 再 `setup` 是常态，任何在 `_ready` 里读注入对象的写法都会 null 崩。
- **空布局是错误态，不是默认值**：`_hint_text()` 的三支之外一律「布局未确认，请返回引导重选」，组合根在空布局时根本不调 `setup`。
- **`%SuccessCount` 用「成功 %d / %d」**：1 m 外裸 `3 / 5` 没有语义；数据来源与变化检测规则不变。
- **不登记 `config_store.gd` / `profile_store.gd`**：它们的 `notice` 在 Phase 4 从未渲染；S99 的 errors/warnings 由 `config_loader` / `config_validator` / `overlay_merge` 现场产生。把不点屏的文件收进清单只会无谓膨胀。
- **`RENDER_SOURCES` 是第二条边**：`src/ui` 可以目录枚举，`src/core` 不行；点名 7 个会渲染的文件，缺一个就让 `--check` 与 `gate-a.sh` 同时红。
- **`AppFont.tres` 选 400 而不是 Thin**：UI-SPEC G11 指出子集默认实例是 100；改一行 `variation_opentype` 不影响码点覆盖，也不要求重生成子集。
- **每段测试新建运行时**：手势锁、重新武装与冷却都活在实例里；复用会让失败定位退化成「看起来哪里都不对」。
- **`ACCEPTANCE` 只写判据与空格子**：`- [x]` 的存在本身就是伪造证据的入口，verify 直接断言它不存在。

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - 机械计数] D 行粗体使 `\*\*D[0-6]` 计数变成 8**
- **Found during:** Task 3 验收自检
- **Issue:** 停止条件那行写成 `**D0 停止条件**`，与七组标题一起被 `grep -cE '\*\*D[0-6]'` 计入，输出 8 而不是 7。
- **Fix:** 改为 `**停止条件**`，语义不变，机械计数回到 7。
- **Files modified:** mobile/ACCEPTANCE.md
- **Verification:** `grep -cE '\*\*D[0-6]' mobile/ACCEPTANCE.md` → `7`。
- **Committed in:** `8c1fc74`

**2. [Rule 3 - 计划字面] `_process` 首行必须是可见性早退**
- **Found during:** Task 1 写练习屏
- **Issue:** 初版把解释性注释放在 `func _process` 之后、`if not visible: return` 之前；验收与 UI-SPEC §7 都要求早退是第一句可执行语句。
- **Fix:** 注释移到函数签名上方，函数体第一句就是 `if not visible: return`。
- **Files modified:** mobile/src/ui/practice_screen.gd
- **Verification:** `sed -n '/func _process/,+2p'` 第一行即早退；`grep -c '_accum < 0.1'` 仍为 1。
- **Committed in:** `0c0ffbd`

### 计划外但由 orchestrator 约束要求的文件

**3. [Rule 2 - UI 契约] `mobile/assets/fonts/AppFont.tres` 加 `wght=400`**
- **Found during:** Task 1（UI-SPEC §12-G11）
- **Issue:** 文件不在本计划的 `files_modified` 里，但子集字体的默认实例是 100 Thin，28 px 正文在 1 m 外笔画偏细。
- **Fix:** 加 `variation_opentype = { &"wght": 400 }`；不改字体文件、不重生成子集、不影响 `GLYPH_OK`。
- **Files modified:** mobile/assets/fonts/AppFont.tres
- **Verification:** `gate-a.sh` 仍 `GLYPH_OK chars=992`；`--check` 退出 0。
- **Committed in:** `0c0ffbd`

**4. [Rule 2 - 闭世界] `mobile/tools/gate-a.sh` 的字形步骤明写覆盖 `RENDER_SOURCES`**
- **Found during:** Task 1（orchestrator 约束 13）
- **Issue:** 文件不在 `files_modified` 里；只靠 `--check` 隐式覆盖时，读闸门输出的人看不出 core 渲染源也被断言。
- **Fix:** 步骤标题改为「src/ui 自动枚举 + RENDER_SOURCES 点名」，命令本身不变（同一份 `--check` 同时跑两条断言）。
- **Files modified:** mobile/tools/gate-a.sh
- **Verification:** `gate-a.sh` 输出含该行且通过。
- **Committed in:** `0c0ffbd`

**5. [Rule 2 - 边车约定] 额外提交 `test_green_slice.gd.uid`**
- **Found during:** Task 2 的 `--import`
- **Issue:** `files_modified` 未列测试脚本的 `.gd.uid`；Phase 2 的既有约定是所有 `*.gd.uid` 都是提交物。
- **Fix:** 边车随 Task 2 提交。
- **Files modified:** mobile/tests/unit/test_green_slice.gd.uid
- **Verification:** `git ls-files` 命中；`--import` 后无未跟踪残留。
- **Committed in:** `f0eb11b`

### 机械计数更正

- 字形清单从 04-05 的 876 增至 **992**（+116）。计划 G5 的估算 943 只基于 4 个 core 文件；本次按 orchestrator 约束登记 7 个 core 源 + 3 个 UI 文件，实测 992。阈值未放宽，`GLYPH_OK chars=992` 为本次实测。
- `TESTS_SUITES` 14 → **15**，`TESTS_ASSERTIONS` 1175 → **1224**（+49），`TESTS_DONE failures=0`。
- `gate-a.sh` 的 5 条 `check_script` 本次**全部**真正执行（04-05 缺 `practice_screen.gd`，被存在性守卫跳过）；输出含 `✓ res://src/ui/practice_screen.gd`。
- `LINT_OK files=27`、`check_desktop.sh` 230/230、`test-core-selftest.sh` `SELFTEST_OK cases=7` 均为本次实测。

### 环境差异（不是计划分歧）

- 本环境没有 `gsd_run` 命令，Step 0 的 protected-branch 查询与 `windows append` 台账均无法执行。按 orchestrator 的 `<sequential_execution>`「在 main 工作树上顺序执行」与 `.planning/config.json` 的 `git.branching_strategy: none`，在 `main` 上用普通提交（带 hooks，未用 `--no-verify`）。未做任何 `git update-ref` 之类的自愈操作。
- 字体重新生成后的首次 `--import` **一次成功**（04-05 曾遇到已知 SIGSEGV）；重试逻辑未改动，判据未放宽。

---

**Total deviations:** 5（2 个计划字面、2 个 orchestrator 约束要求的计划外文件、1 个边车约定）+ 1 条环境说明
**Impact on plan:** 无断言被削弱。`RENDER_SOURCES` 让字形闭世界第二条边有了机械牙齿；`wght=400` 是 UI-SPEC 的既定修复；两处计划字面调整都保留原意；边车与既有约定一致。

## Known Stubs

None — 占位 Label 已 `queue_free()`；练习屏、横幅、诊断面板全部接真实数据源（`TapRuntime` / `PadStateBuffer`），没有硬编码空值或演示判定。

## Issues Encountered

- 首版 headless 冒烟在 `_initialize()` 里 `add_child` 后立刻调 `show_outcome`，此时子节点尚未进入 `_ready` 阶段，`@onready` 的 `%Title` 还是 null —— 这不是产品 bug，而是测试时序错误。改为等一帧后调用，横幅三类断言（成功文案 / 同 seq 去重 / 更大 seq 覆盖）全部通过。
- GDScript 静态类型：`result_banner.gd` 没有 `class_name`，练习屏里 `@onready var _banner = %ResultBanner` 必须无类型，否则编译期拒绝 `show_outcome`。已按计划写成无类型引用。
- Godot 仍偶发打印 `Unicode parsing error ... Invalid UTF-8 leading byte`；既有导入噪声，与本次产物无关。

## User Setup Required

None - no external service configuration required. 本计划未安装任何依赖，未修改 `shared/skills_config.json`，未触碰 `design/`（用户未跟踪工作）。

## Next Phase Readiness

- 04-07 可以直接使用 `%DebugPanel`（屏上）与 `PAD_DIAG` / `PAD_AXIS` / `PAD_DEV`（1 Hz logcat）抄录 D5/D6；D0–D6 的表格与判据已经落在 `mobile/ACCEPTANCE.md` 第 6 节，且全部留白。
- 成功标准 5 的呈现半边已闭合：一次尝试一条判定、两次尝试两条、原因逐字来自 `Outcome`。真机上的「只出现一条」仍由 D4 记录。
- `gate-a.sh` 的五条 `check_script` 全部真编译；后续新增 UI 脚本时只需追加路径，判据不用改。
- INPUT-01 / INPUT-04 / INPUT-05 不因本计划勾选：真机证据在 04-07 的 D0–D6。

---

*Phase: 04-device-input-green-slice*
*Completed: 2026-11-05*

## Self-Check: PASSED

- 7 个新建文件（含 3 个 `.gd.uid` 边车）全部存在
- 三个任务提交 `0c0ffbd` / `f0eb11b` / `8c1fc74` 均为 HEAD 祖先；`git rev-list --count fd3ec12..8c1fc74` = 3
- `TESTS_SUITES=15` / `TESTS_ASSERTIONS=1224` / `TESTS_DONE failures=0` / `LINT_OK files=27` / `GLYPH_OK chars=992` / `gate-a.sh` 通过 / `check_desktop.sh` 230/230 / `SELFTEST_OK cases=7` 均为本次运行实测
- `shared/skills_config.json` 零 diff；`mobile/src/ui/main.tscn` 零 diff
