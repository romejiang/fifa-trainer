---
phase: 04-device-input-green-slice
plan: 04
subsystem: input-device
tags: [gdscript, godot, joystick, event-capture, atomic-write, profile-store, architecture-lint]
requires:
  - phase: 04-device-input-green-slice
    plan: 03
    provides: AxisMapping / Calibration / DeviceProfile / ProbeEvaluator（档案 schema 与复用门）
  - phase: 04-device-input-green-slice
    plan: 02
    provides: TapRuntime、无头 runner、TESTS_DONE 哨兵
  - phase: 04-device-input-green-slice
    plan: 01
    provides: tap 检测器与黄金夹具
  - phase: 03-core-foundation
    plan: 02
    provides: lint_core_purity.py 的 outer_layer_dep 规则与 LINT_OK 哨兵
  - phase: 02-android-toolchain
    provides: Godot 4.7.2-stable 与 *.gd.uid 提交约定
provides:
  - "mobile/src/input/joy_button_map.gd：JoyButtonMap —— 索引 0..20 ↔ 17 个规范名，反向表由 INDEX_TO_NAME 构建"
  - "mobile/src/input/pad_state_buffer.gd：PadStateBuffer —— 唯一状态写入点，apply_event 与 reconcile 共用 _set_button；轴值只来自事件；D5/D6 诊断出口"
  - "mobile/src/input/pad_sampler.gd：PadSampler —— 唯一碰 Input. / Time. 的薄壳，事件优先 + 每帧按钮对账，input_thread_id / process_thread_id"
  - "mobile/src/app/profile_store.gd：ProfileStore —— user:// 原子写、先取长度再分配、任一条目非法整份丢弃"
  - "mobile/tests/unit/test_pad_sampler.gd：10 个 _check_*，含同帧右→左→右三条事件顺序断言"
  - "mobile/tests/unit/test_profile_store.gd：8 个 _check_*，含 res:// 守卫、1 MiB+1 字节、坏条目整份丢弃"
  - "tools/lint_core_purity.py：outer_layer_dep 枚举加 input（规则 id / 顺序 / 返回码不变）"
  - "mobile/tools/test-core.sh：导入之前的轴枚举常量零出现断言（INPUT-02）"
  - "mobile/tools/test-core-selftest.sh：joy_axis_canary（第 6 条反例 / 第 7 个用例）→ SELFTEST_OK cases=7"
affects: [04-05-onboarding-flow, 04-06-practice-screen, 04-07-device-checklist, phase-5-detectors]

actuals:
  tokens: 11572
  tasks: 3
  commits: 3

plan_head_before: bd8689e873744b9bfa4428e2d135812007ffe006
plan_head_after: 2e176f8

tech-stack:
  added: []
  patterns:
    - "事件通道 + 每帧轮询对账写同一份状态：状态一致时不产生边沿，天然幂等，不维护两套代码路径"
    - "轴值只来自 InputEventJoypadMotion；轮询只对账按钮，没有『轮询轴』回退路径"
    - "纯缓冲（RefCounted，零引擎单例）与薄壳（Node，唯一碰 Input./Time.）按文件边界切分"
    - "bind_device(same) 返回 false 且不碰状态：组合根初始 emit + 主动播种两次不会把一次按下变成两次边沿"
    - "ProfileStore 复用 ConfigStore 的原子写与先取长度范式，但采用『任一条目非法→整份丢弃』"
    - "lint 规则扩展只加枚举分支，不动规则 id / 顺序 / 返回码；反例与文档互锁同步更新"
    - "闸门断言先于 Godot 导入：纯文本、毫秒级；反例用 GODOT_BIN=/bin/false 证明没有调用引擎"

key-files:
  created:
    - mobile/src/input/joy_button_map.gd
    - mobile/src/input/joy_button_map.gd.uid
    - mobile/src/input/pad_state_buffer.gd
    - mobile/src/input/pad_state_buffer.gd.uid
    - mobile/src/input/pad_sampler.gd
    - mobile/src/input/pad_sampler.gd.uid
    - mobile/src/app/profile_store.gd
    - mobile/src/app/profile_store.gd.uid
    - mobile/tests/unit/test_pad_sampler.gd
    - mobile/tests/unit/test_pad_sampler.gd.uid
    - mobile/tests/unit/test_profile_store.gd
    - mobile/tests/unit/test_profile_store.gd.uid
  modified:
    - mobile/tests/core_runner.gd
    - tools/lint_core_purity.py
    - tools/test_lint_core_purity.py
    - mobile/docs/CORE.md
    - mobile/tools/test-core.sh
    - mobile/tools/test-core-selftest.sh

key-decisions:
  - "PadStateBuffer 是唯一状态写入点：apply_event / reconcile 都走 _set_button，只有真实变化才记边沿"
  - "同一设备重复绑定返回 false 且不碰状态/计数器；换设备才清场 —— 组合根两次播种必须幂等"
  - "轴值只来自事件：events_motion == 0 是显式的 D0 停止条件，不允许设备层偷偷轮询轴"
  - "pressed_dict() 只由按钮索引产生：LT/RT 是轴，本阶段只有 RB 修饰键；RT 分支留给 Phase 5"
  - "JoyButtonMap 的 NAME_TO_INDEX 用 static var + _static_init() 反向构建（GDScript const 不能求值循环），避免第二份手写字面量"
  - "ProfileStore 超限返回 ERR_INVALID_DATA，坏 JSON / schema 返回 ERR_FILE_CORRUPT；恢复动作都只有『重新探测』"
  - "upsert 拒绝空 key：否则写出的文件下次启动必然被 DeviceProfile.from_dict 整份丢弃"
  - "apply_event 在写入点拒绝 NaN/Inf：坏样本不进入判定路径"
  - "lint 只加 input 分支，不动规则 id、顺序、_STRING_AWARE 与返回码三档"
  - "轴枚举常量断言放在导入之前：纯文本检查没有理由等引擎装好，反例也能在几秒内变红"

patterns-established:
  - "同一物理事件的两条通道共享一个状态机：对账是幂等的，真机只负责记录哪条通道在供数"
  - "诊断量（events_* / poll_edges / delta_ms_percentiles / axis_range / thread ids）全部由被观测对象自己暴露，日志层不另算一份"
  - "设备档案的恢复策略只有一种：任一条目非法即整份丢弃并删除，绝不部分恢复"
  - "新增闸门断言必须同时交出一条反例，并用『引擎不可用』证明它在导入之前命中"

requirements-completed: []
# INPUT-01 / INPUT-02 / INPUT-05 在本计划**不宣布完成**：
# - INPUT-01：索引↔规范名表与 device 过滤已在无头环境证明；真实蓝牙配对与 Xbox/DualSense 各连一次在 04-07（D0/D3）。
# - INPUT-02：零轴枚举常量的 grep 与『轴号由探针给出』的纯逻辑都已就位；换一只手柄仍能探出在 04-07（D2）。
# - INPUT-05：同帧反转与幂等对账已有无头证据；真机 events_* 能解释谁在供数、Δt p95 ≤ 20ms 在 04-07（D5/D6）。
# 依据 plan 的 Flagged Assumptions：探针结果仍是 unclassified，不得据此勾选。

coverage:
  - id: INPUT-05-A
    description: "同一帧右→左→右三条 motion 事件全部保留且顺序不变，最后一条轴值为「右」"
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_pad_sampler.gd#_check_same_frame_reversal"
        status: pass
    human_judgment: false
  - id: INPUT-05-B
    description: "事件通道在场时 poll_edges == 0；缺席时轮询补边沿且 events_button == 0，两条通道写同一份状态"
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_pad_sampler.gd#_check_reconcile_idempotent / _check_event_channel_missing"
        status: pass
    human_judgment: false
  - id: T-04-13
    description: "绑定 3 号设备时收到 7 号设备的 motion/button：状态与三个计数器完全不变；越界索引同样被拒"
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_pad_sampler.gd#_check_device_filter"
        status: pass
    human_judgment: false
  - id: INPUT-01-A
    description: "索引 0..20 覆盖完整；非空规范名全部在 Buttons.CANONICAL 里；LT/RT 不出现在 pressed_dict()"
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_pad_sampler.gd#_check_joy_button_map / _check_pressed_dict"
        status: pass
    human_judgment: false
  - id: INPUT-02-A
    description: "mobile/src 下零轴枚举常量前缀；制造反例后闸门在导入之前以 INPUT-02 变红"
    verification:
      - kind: integration
        ref: "bash mobile/tools/test-core.sh / bash mobile/tools/test-core-selftest.sh#joy_axis_canary"
        status: pass
    human_judgment: false
  - id: T-04-05
    description: "ProfileStore 写 res:// 返回 ERR_UNAUTHORIZED，且不创建目录或文件"
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_profile_store.gd#_check_res_guard"
        status: pass
    human_judgment: false
  - id: T-04-12
    description: "MAX_BYTES + 1 字节的档案在解析前被拒绝并删除；合法档案原子写后不留 .tmp"
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_profile_store.gd#_check_too_large / _check_atomic_write"
        status: pass
    human_judgment: false
  - id: PROFILE-DISCARD
    description: "两个条目中第二条轴序号 99：整份丢弃，合法的第一条也不保留；坏 JSON 与缺失文件首启安静态各有断言"
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_profile_store.gd#_check_one_bad_entry_discards_all / _check_broken_json / _check_missing_file_is_quiet"
        status: pass
    human_judgment: false
  - id: LINT-INPUT
    description: "core 不得 preload res://src/input/；注释里的写法与 res://src/core/ 不误报；规则表仍 14 行"
    verification:
      - kind: unit
        ref: "python3 tools/test_lint_core_purity.py"
        status: pass
    human_judgment: false
  - id: BASELINE
    description: "test-core 13 套件 / 1074 断言 / failures=0；selftest cases=7；LINT_OK files=26；gate-a 与桌面 230 项保持绿"
    verification:
      - kind: integration
        ref: "bash mobile/tools/test-core.sh；bash mobile/tools/test-core-selftest.sh；bash mobile/tools/gate-a.sh；bash tools/check_desktop.sh"
        status: pass
    human_judgment: false

duration: 13min
completed: 2026-11-05
status: complete
---

# Phase 4 Plan 04: PadStateBuffer + PadSampler + ProfileStore + lint 扩到 input Summary

**同一帧右→左→右三条 motion 事件在纯缓冲里全部保留且顺序不变；事件通道缺席时轮询补边沿、在场时 `poll_edges` 为 0；`ProfileStore` 把 04-03 的纯档案落到 `user://` 并在任一条目非法时整份丢弃；`core` 反向依赖 `src/input/` 从此是一条会失败的 lint 规则，「不硬编码轴号」变成导入之前的 grep**

## Performance

- **Duration:** 13 min
- **Started:** 2026-11-05T10:10:42Z
- **Completed:** 2026-11-05T10:23:27Z
- **Tasks:** 3
- **Files modified:** 18（12 新建、6 修改；含 6 个 `.gd.uid` 边车）

## Accomplishments

- `PadStateBuffer`：唯一状态写入点。`apply_event()` 与 `reconcile()` 共用 `_set_button()`，只有真实变化才记边沿，所以两条通道写同一份状态、天然幂等。轴值只来自 `kind == "motion"` 的事件，没有任何轮询轴入口；`events_motion` / `events_button` / `poll_edges` / `delta_ms_percentiles()` / `axis_range(i)` 是 D5/D6 的唯一数据源。`bind_device(same)` 返回 false 且不碰状态/计数器，组合根的初始 emit + 主动播种不会把一次按下变成两次边沿。
- `PadSampler`：唯一碰引擎单例的薄壳。`_input` 只做 `InputEvent → 字典` 的形状转换并记录 `input_thread_id`；`_process` 只对账 21 个按钮并记录 `process_thread_id`。类文档把「轴值只来自事件；`events_motion == 0` 是 D0 停止条件」写成硬约束，明确禁止轮询轴回退。
- `JoyButtonMap`：索引 0..20 ↔ 17 个规范名；反向表由 `INDEX_TO_NAME` 反向构建，不写第二份字面量。类文档写明本阶段只支持 `required_button = "RB"`，`LT`/`RT` 是轴、`pressed_dict()` 不合成，RT 分支留给 Phase 5。
- `ProfileStore`：`user://profiles/controllers.json` 的原子写（temp → flush → close → rename），先取长度再分配（1 MiB 上限），任一条目 `DeviceProfile.from_dict` 返回 null 即整份丢弃并删除文件。`res://` 目标返回 `ERR_UNAUTHORIZED` 且零副作用；`probed_at_iso` 只在 `upsert()` 里由墙钟填入。
- 无头证据：`test_pad_sampler` 10 个 `_check_*`（同帧反转、设备过滤、对账幂等、事件缺席、pressed_dict、绑定幂等、环形上限、Δt 百分位、每轴 min/max、映射表）；`test_profile_store` 8 个 `_check_*`（往返、原子写、res 守卫、坏 JSON、超大、坏条目整份丢弃、upsert 时间戳、首启安静）。
- 闸门加强：`outer_layer_dep` 枚举加 `input`，规则 id / 顺序 / 返回码不变；`test-core.sh` 在导入之前 grep 轴枚举常量（INPUT-02）；`test-core-selftest.sh` 新增 `joy_axis_canary`，用 `GODOT_BIN=/bin/false` 证明断言先于引擎。
- 全套基线保持绿：`TESTS_SUITES=13` / `TESTS_ASSERTIONS=1074` / `TESTS_DONE failures=0`；`SELFTEST_OK cases=7`；`LINT_OK files=26`；lint 自测 56 项；`gate-a.sh` 通过；`check_desktop.sh` 230/230；`grep -R JOY_AXIS_ mobile/src` 无输出。

## Task Commits

Each task was committed atomically:

1. **Task 1: PadStateBuffer + PadSampler 薄壳 + JoyButtonMap + 同帧反转套件** — `0b648a4` (feat)
2. **Task 2: ProfileStore user:// 原子写 + 整份丢弃 + 档案套件** — `9a7b7e4` (feat)
3. **Task 3: lint 扩到 src/input + 轴枚举常量闸门断言 + 第 6 条反例** — `2e176f8` (feat)

**Plan metadata:** 见本次最终 docs 提交（SUMMARY / STATE / ROADMAP）

## Files Created/Modified

- `mobile/src/input/joy_button_map.gd`（66 行）— 0..20 索引表、反向表、RB 范围声明
- `mobile/src/input/pad_state_buffer.gd`（251 行）— 唯一状态写入点、事件/轮询共用边沿、D5/D6 诊断
- `mobile/src/input/pad_sampler.gd`（115 行）— 事件优先 + 每帧按钮对账、线程取证、D0 停止条件文档
- `mobile/src/app/profile_store.gd`（164 行）— 原子写、1 MiB 上限、整份丢弃、upsert 墙钟
- `mobile/tests/unit/test_pad_sampler.gd`（247 行）— 10 个 `_check_*`
- `mobile/tests/unit/test_profile_store.gd`（216 行）— 8 个 `_check_*`
- `mobile/tests/core_runner.gd` — `SUITES` 增至 13（pad_sampler / profile_store）
- `tools/lint_core_purity.py` — `outer_layer_dep` 加 `input`
- `tools/test_lint_core_purity.py` — input 命中与注释不误报两条新断言，总数 56
- `mobile/docs/CORE.md` — 规则表、单向依赖方向、Phase 4 修饰键范围
- `mobile/tools/test-core.sh` — 导入之前的轴枚举常量零出现断言
- `mobile/tools/test-core-selftest.sh` — `joy_axis_canary`、EXIT 清理、`cases=7`
- 六个 `.gd.uid` 边车（4 个源文件 + 2 个测试文件）— Godot 4.7.2 `--import` 生成，按既有约定提交

## Decisions Made

- **同一份状态、两条通道**：对账的全部机制是「状态一致时什么也不做」。事件先到 → 轮询不补边沿；事件缺席 → 轮询补边沿。真机只记录哪条通道在供数。
- **轴值只来自事件**：`_process` 不读轴。轮询轴只保留帧内最后一个值，同帧反转会永久丢失（INPUT-05）。某设备不派发 motion 事件时，`events_motion == 0` 是显式 D0 停止条件，不是加回退路径的理由。
- **绑定幂等**：同一设备重复 `bind_device` 返回 false 且不碰任何状态；否则组合根的初始 emit + 主动播种会把一次按下分派两次。
- **`NAME_TO_INDEX` 反向构建**：GDScript 的 `const` 不能求值循环，改用 `static var` + `_static_init()`；两张表不可能漂移。
- **修饰键范围写死**：本阶段只有 `required_button = "RB"`；`LT`/`RT` 是轴，`pressed_dict()` 不合成；`AxisMapping` 的 lt/rt 字段留给 Phase 5。
- **档案恢复只有一种动作**：任一条目非法 → 整份丢弃并删除文件。不做部分恢复、不静默补默认值。
- **空 key 在写入点拒绝**：`DeviceProfile.from_dict` 不接受空 key，写进去只会制造一个下次启动必然自毁的档案。
- **闸门断言先于导入**：轴枚举常量的 grep 是纯文本、毫秒级、零 Godot 依赖；放在导入之前，反例才能在几秒内变红。

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `ERR_FILE_TOO_BIG` 在 Godot 4.7.2 里不存在**
- **Found during:** Task 2 首次导入（脚本编译前用临时脚本探常量）
- **Issue:** 超限档案原本打算返回 `ERR_FILE_TOO_BIG`，但该常量在 Godot 4 的 `Error` 枚举里没有声明；直接写会让 `profile_store.gd` 解析失败。
- **Fix:** 超限返回 `ERR_INVALID_DATA`（30），坏 JSON / schema 仍返回 `ERR_FILE_CORRUPT`（16）。两者都是合法错误码；调用方的恢复动作不变（删除 + 重新探测）。
- **Files modified:** mobile/src/app/profile_store.gd
- **Verification:** `test-core.sh` 13 套件全绿；`_check_too_large` 命中空档案 + notice + 文件已删除。
- **Committed in:** `9a7b7e4`

### 计划字面与验收的冲突（按验收执行并记录）

**2. [Rule 3 - 计划字面] `pad_state_buffer.gd` 类文档不能出现 `Input.` / `Time.` 字面量**
- **Found during:** Task 1 验收自检
- **Issue:** action 要求类文档写「零 `Input.` / `Time.`」并解释轮询 `Input.get_joy_axis` 的丢值问题；acceptance 要求该文件 `grep -c` 两者都为 0。两句不能同时满足。
- **Fix:** 按 acceptance 执行 —— 改成「零引擎单例、零时钟」与「轮询轴只保留帧内最后一个值」，保留同一条理由，不出现标识符。prohibition 的语义未减弱。
- **Files modified:** mobile/src/input/pad_state_buffer.gd
- **Verification:** `grep -c 'Input\.'` = 0、`grep -c 'Time\.'` = 0；同帧反转套件全绿。
- **Committed in:** `0b648a4`

**3. [Rule 3 - 语言约束] `NAME_TO_INDEX` 用 `static var` + `_static_init()` 而不是 `const`**
- **Found during:** Task 1 设计映射表
- **Issue:** plan 写「`const NAME_TO_INDEX` 由 `INDEX_TO_NAME` 反向构建」，但 GDScript 的常量初始化器不能执行循环；写成字面量就是第二份会漂移的表。
- **Fix:** `static var NAME_TO_INDEX: Dictionary = {}`，在 `_static_init()` 里从 `INDEX_TO_NAME` 反向填充。语义是「类加载时构建一次的只读索引」，且测试断言 `NAME_TO_INDEX["RB"] == 10`、每个非空值都在 `Buttons.CANONICAL` 里。
- **Files modified:** mobile/src/input/joy_button_map.gd
- **Verification:** `_check_joy_button_map` 全绿；`TESTS_DONE failures=0`。
- **Committed in:** `0b648a4`

**4. [Rule 3 - 机械计数] `test_profile_store.gd` 保持恰好八个 `_check_*`**
- **Found during:** Task 2 组织套件
- **Issue:** 额外写了一个 `_check_default_path`，会让 `_check_*` 变成九个；acceptance 要求「含八个 `_check_` 函数名且全部在 `run(r)` 里被调用」。
- **Fix:** 把默认路径断言并进 `_check_missing_file_is_quiet`（只调 `path()`，不碰真实用户档案），保持八个 `_check_*` 全部被调用。断言未删除。
- **Files modified:** mobile/tests/unit/test_profile_store.gd
- **Verification:** `grep -c '^func _check_'` = 8，`grep -c '^	_check_'` = 8；套件全绿。
- **Committed in:** `9a7b7e4`

**5. [Rule 3 - 计划字面] lint 反例「追加三条断言」中有一条已经存在**
- **Found during:** Task 3 编辑 `test_extended_rules_have_teeth`
- **Issue:** 三条里的「`preload("res://src/core/geometry.gd")` → 0 命中」在 03-02 就已存在；再写一遍就是重复断言。
- **Fix:** 保留已有那条，新增「input 分支有牙齿」与「注释里的 input 不命中」两条；该区段仍是三条并列断言，自测总数 54 → 56。没有删除或弱化旧断言。
- **Files modified:** tools/test_lint_core_purity.py
- **Verification:** `python3 tools/test_lint_core_purity.py` → 56 项全绿；`--list-rules` 仍 14 行。
- **Committed in:** `2e176f8`

### 边界与加强

**6. [Rule 2 - 边界] `upsert()` 拒绝 null / 空 key**
- **Found during:** Task 2 写 `upsert`
- **Issue:** 空 key 会被写成 `profiles[""]`；下次启动 `DeviceProfile.from_dict` 对空 `key` 返回 null，整份档案被丢弃 —— 写入点制造了一个必然自毁的文件。
- **Fix:** `upsert()` 第一句检查 `profile == null or profile.key.strip_edges().is_empty()`，返回 `ERR_INVALID_PARAMETER`。
- **Files modified:** mobile/src/app/profile_store.gd
- **Verification:** 既有八条断言不受影响；`TESTS_DONE failures=0`。
- **Committed in:** `9a7b7e4`

**7. [Rule 2 - 安全] `apply_event()` 在写入点拒绝 NaN / Inf 轴值**
- **Found during:** Task 1 写 motion 分支
- **Issue:** RESEARCH 的 Security Domain 要求「手柄上报异常轴值（NaN/Inf/超出 ±1）不得进入判定」；`PadStateBuffer` 是唯一写入点，下游无法区分坏样本。
- **Fix:** `_apply_motion()` 对 `value` 做 `is_finite()` 守卫，非有限值返回 false 且不计数、不写缓冲。
- **Files modified:** mobile/src/input/pad_state_buffer.gd
- **Verification:** 所有 motion 用例（有限值）保持绿；`TESTS_DONE failures=0`。
- **Committed in:** `0b648a4`

**8. [Rule 3 - 任务边界] 额外提交两个测试脚本的 `.gd.uid` 边车**
- **Found during:** Task 1 / Task 2 的 `--import`
- **Issue:** `files_modified` 只列了源文件与部分测试，未列 `test_pad_sampler.gd.uid` / `test_profile_store.gd.uid`；Phase 2 的既有约定是 `*.gd.uid` 是提交物。
- **Fix:** 随各自任务一并提交。
- **Verification:** `git ls-files --error-unmatch` 两个边车均成立。
- **Committed in:** `0b648a4` / `9a7b7e4`

### 环境差异（不是计划分歧）

- 本环境没有 `gsd_run` 命令，Step 0 的 protected-branch 查询无法执行。按 orchestrator 的 `<sequential_execution>`「在 main 工作树上顺序执行」与 `.planning/config.json` 的 `git.branching_strategy: none`，在 `main` 上用普通提交（带 hooks，未用 `--no-verify`）。未做任何 `git update-ref` 之类的自愈操作（与 04-03 同一处理）。
- 计划没有指定 `TESTS_ASSERTIONS` 的目标值；实测从 04-03 的 965 增至 **1074**（Task 1 +68、Task 2 +41）。阈值未放宽。

---

**Total deviations:** 8（1 个真实编译 bug、3 处计划字面/机械计数、2 个边界/安全加强、2 个边车补充）+ 1 条环境说明
**Impact on plan:** 无断言被削弱。`ERR_FILE_TOO_BIG` 的替换只影响错误码的可诊断性，恢复动作不变；两处计划字面调整都保留了原意（`Input.`/`Time.` 的语义、`NAME_TO_INDEX` 的反向构建）；lint 只新增两条不重复的断言。全部基线（test-core / selftest / lint / gate-a / 桌面 230）保持绿。

## Issues Encountered

- `PackedFloat32Array` 的 32 位精度不影响本轮断言：轴样本只用了 -1.0 / 0.5 / 1.0 等可精确表示的值；`delta_ms_percentiles` 的 `t_ms` 保存在普通 `Array` 字典里，仍是 64 位浮点。
- `ProfileStore.load_all()` 的 `raw_profiles` 先 `typeof` 判 `Dictionary` 再赋给带类型局部变量；直接索引 `Variant` 虽然运行期可行，但显式收窄后解析更早、错误更明确。
- Godot 仍偶发打印 `Unicode parsing error ... Invalid UTF-8 leading byte`；本次两次 `--import` 一次成功，测试不受影响（既有导入噪声）。

## User Setup Required

None - no external service configuration required. 本计划未安装任何依赖，未修改 `shared/skills_config.json`，未触碰 `design/`（用户未跟踪工作）。

## Next Phase Readiness

- 04-05 composition root 可直接使用：`PadSampler` 在 `add_child()` 之前 connect `device_list_changed`，之后用 `connected_devices()` 主动播种；两次 `bind()` 幂等，不会重复边沿。
- 04-06 的 `PAD_DIAG` 日志只需读 `PadStateBuffer.events_motion` / `events_button` / `poll_edges` / `delta_ms_percentiles()` / `axis_range(i)` 与 `PadSampler.input_thread_id` / `process_thread_id`，不另算副本。
- `ProfileStore` 已能在无头环境证明原子写与整份丢弃；04-05 的 `STATE_REUSE_REST` / `STATE_REUSE_CHECK` 只需把实测的四元组喂给 `DeviceProfile.can_reuse()`。
- 真机项不变，仍待 04-07：`events_motion` 是否非零（D0）、`events_button > 0` 还是轮询供数（D5）、`input_thread_id == process_thread_id`（D6）、Δt p95 ≤ 20 ms（D6）。04-04 只交无头证据，不宣布 INPUT-01/02/05 完成。

---

*Phase: 04-device-input-green-slice*
*Completed: 2026-11-05*

## Self-Check: PASSED

- 12 个新建文件（含 6 个 `.gd.uid` 边车）全部存在
- 三个任务提交 `0b648a4` / `9a7b7e4` / `2e176f8` 均为 HEAD 祖先
- `TESTS_SUITES=13` / `TESTS_ASSERTIONS=1074` / `TESTS_DONE failures=0` / `SELFTEST_OK cases=7` / `LINT_OK files=26` / `gate-a.sh` 通过 / `check_desktop.sh` 230/230 均为本次运行实测
