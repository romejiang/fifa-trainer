---
phase: 03-core-foundation
plan: 04
subsystem: core
tags: [gdscript, config-validation, error-model, bom, utf8, json, collect-errors, warnings, parity]

requires:
  - phase: 03-core-foundation
    plan: 01
    provides: 无头 runner、`TESTS_DONE failures=0` 完成哨兵、`test-core.sh` 唯一入口
  - phase: 03-core-foundation
    plan: 02
    provides: `lint_core_purity.py` 的 14 条架构规则与 `CORE.md` 的边界定义
  - phase: 03-core-foundation
    plan: 03
    provides: `Buttons.canonical()`（失败空串）、`DirectionTable.resolve()`（失败 null）、六个域对象
  - phase: 02-android-toolchain
    provides: Godot 4.7.2 与 `*.gd.uid` 提交约定

provides:
  - "mobile/src/core/config/config_error.gd：json_path / code / message / fix_hint / severity + format_line()"
  - "mobile/src/core/config/config_result.gd：config / errors / warnings / source_path / notice / overrides_applied + ok() / to_text() / has_code()"
  - "mobile/src/core/config/config_loader.gd：parse_bytes（BOM/空/非法 UTF-8）、parse_text（JSON 语法 + 行号）、decode_bytes（原始字典给覆盖层）"
  - "mobile/src/core/config/config_validator.gd：结构 + arc/sequence/taps 全量参数 + input/rumble + 修饰键交叉检查 + 收集式错误 + 可见 warning"
  - "mobile/tests/unit/test_config_loader.gd：真实配置 5 条动作、BOM 合成字节、空/非法 UTF-8/语法错误、decode_bytes"
  - "mobile/tests/unit/test_config_validator.gd：接受路径 + 23 条拒绝用例 + 多错误 + 子树跳过 + 6 组 warning/截断断言"
  - "mobile/tests/core_runner.gd：SUITES 扩到 5 条（config_loader / config_validator / geometry / models / vocabulary）"

affects: [03-05, 03-06, phase-4-input, phase-7-feedback]

actuals:
  tokens: 16187
  tasks: 3
  commits: 4

plan_head_before: fb8d7731e78b3ca3ba3bb18fb33688f8188e3e73
plan_head_after: 17fc357e2932ddfc7d708c9b629c08ca821b4477

tech-stack:
  added: []
  patterns:
    - "字节入口：BOM / 空 / 非法 UTF-8 在解码前判定，字符串 API 永远看不到这三个字节"
    - "错误即数据：一条 ConfigError 自带路径、码、中文消息与修复建议，UI 不二次解释"
    - "收集式校验：Array[ConfigError] 沿调用链传递，坏字段只跳过依赖它的子树"
    - "静默 clamp → 可见 warning：可截断字段进 warnings 并带实际值与截断值，不可截断的越界仍是 error"

key-files:
  created:
    - mobile/src/core/config/config_error.gd
    - mobile/src/core/config/config_error.gd.uid
    - mobile/src/core/config/config_result.gd
    - mobile/src/core/config/config_result.gd.uid
    - mobile/src/core/config/config_loader.gd
    - mobile/src/core/config/config_loader.gd.uid
    - mobile/src/core/config/config_validator.gd
    - mobile/src/core/config/config_validator.gd.uid
    - mobile/tests/unit/test_config_loader.gd
    - mobile/tests/unit/test_config_loader.gd.uid
    - mobile/tests/unit/test_config_validator.gd
    - mobile/tests/unit/test_config_validator.gd.uid
  modified:
    - mobile/tests/core_runner.gd

key-decisions:
  - "入口只收 PackedByteArray，BOM 用字面量 bytes[0] == 0xEF 在解码前判定；不用 FileAccess.get_file_as_string（会剥 BOM）也不用 JSON.parse_string（失败会向 stderr 打 ERROR、拿不到行号）"
  - "每条错误必须自带 json_path + code + 中文 message + 中文 fix_hint；fix_hint 为空视为缺陷，两套套件各有一条遍历断言"
  - "required_button / required_buttons 为 null 是合法的「不需要修饰键」：真实配置 5 条动作里有 3 条这样写，绝不能报 button_unknown，也不产生 warning"
  - "params.direction 在移动端严格化：只接受 any / cw / ccw / clockwise / counterclockwise / 顺时针 / 逆时针；Python 的静默落 any 不再保留，分歧由 03-05 语料记录"
  - "start_angle 在校验期就拒绝数组/字典（start_angle_not_scalar），不留到 ArcDetector 构造才崩"
  - "可截断字段的上界逐字照 config.py：calibration_ms 0~3000、idle_reset_ms / gesture_release_ms 0~5000；不统一，否则 4000 在两端表现不同"
  - "type 非法只跳过 arc/sequence/taps 专项检查，name / enabled / relative_to_ls / required_button / button_mode / cooldown_ms / rumble 继续查；一个坏 type 不能让其余错误消失"
  - "warning 与 error 用同一个 ConfigError 类、只靠 severity 区分；warning 不阻止启动，ok() 只看 errors 与 config"
  - "额外补齐 require_neutral_between_steps 与 global_cooldown_ms 的类型/截断检查：两者都是真实配置字段，Python 会静默接受或截断"
  - "RESIL-02 不在本计划标记完成：结构化错误与 to_text() 的可渲染性已闭合，但跨语言语料对等归 03-05；沿用 03-03 的「不提前勾选」原则"

patterns-established:
  - "Pattern 1：字节层判定编码问题 —— 三个 BOM 字节在解码前可见，合成字节用例让「字符串 API 剥 BOM」的假绿不可能发生"
  - "Pattern 2：错误对象的四件套契约 —— json_path 指位置、code 给程序、message 含实际值、fix_hint 说怎么改"
  - "Pattern 3：依赖前提才跳过 —— 类型/结构坏了只跳过依赖它的子树，其余字段照查；错误列表一次给全"
  - "Pattern 4：可截断 vs 不可截断 —— 范围明确且有安全截断值的字段进 warnings，比例/枚举等越界仍是 error"

requirements-completed: []

coverage:
  - id: D1
    description: "ConfigError 四件套（json_path / code / 中文 message / 中文 fix_hint）+ severity；ConfigResult 的 ok() / to_text() / has_code() 可直接渲染"
    requirement: RESIL-02
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_config_loader.gd（BOM 的 message/fix_hint/to_text 断言）+ test_config_validator.gd 的 _check_error_text 遍历"
        status: pass
    human_judgment: false
  - id: D2
    description: "字节入口识别 UTF-8 BOM / 空文件 / 非法 UTF-8 / JSON 语法错误，语法错误带 get_error_line() + 1；core 内不出现 FileAccess / JSON.parse_string"
    requirement: RESIL-02
    verification:
      - kind: unit
        ref: "bash mobile/tools/test-core.sh（TESTS_SUITES=5, TESTS_ASSERTIONS=340）+ python3 tools/lint_core_purity.py mobile/src/core（LINT_OK files=13）"
        status: pass
    human_judgment: false
  - id: D3
    description: "真实配置 res://assets/config/skills_config.json 解析出 5 条动作，名称顺序与 shared 一致，3 处 required_button: null 不报错"
    requirement: RESIL-02
    verification:
      - kind: integration
        ref: "mobile/tests/unit/test_config_loader.gd + test_config_validator.gd 的 _check_real_config"
        status: pass
    human_judgment: false
  - id: D4
    description: "三个点名坏输入早失败：\"enabled\": \"false\" → bool_expected、min_duration_ms: null → number_expected、start_angle: [90,180] → start_angle_not_scalar；params.direction: \"clockwisee\" → direction_unknown，真实配置的 \"any\" 被接受"
    requirement: RESIL-02
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_config_validator.gd#_check_rejections"
        status: pass
    human_judgment: false
  - id: D5
    description: "三类动作的全部参数规则 + input/rumble 类型严格化 + 修饰键交叉检查；23 个不同错误码各有一条拒绝用例"
    requirement: RESIL-02
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_config_validator.gd（24 个 &\"code\" 常量，311+ 条断言）"
        status: pass
    human_judgment: false
  - id: D6
    description: "一次校验给全所有独立错误：三个互不相关错误得到 3 条 ConfigError、to_text() 3 行；type 非法时 cooldown_ms 的检查仍然执行"
    requirement: RESIL-02
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_config_validator.gd#_check_multi_error / _check_subtree_skip"
        status: pass
    human_judgment: false
  - id: D7
    description: "静默 clamp 降级为可见 warning：poll_hz 5000 → 1000、calibration_ms 4000 → 3000、idle_reset_ms 6000 → 5000、startup_test_ms 0 → 10、duration_ms 0 → 1、gap_ms -5 → 0；deadzone 1.5 仍是 error"
    requirement: RESIL-02
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_config_validator.gd#_check_warnings"
        status: pass
    human_judgment: false
  - id: D8
    description: "core 零 I/O、零日志：新增 4 个 config 文件后 lint 仍 LINT_OK，扫描文件数从 9 增到 13"
    requirement: INFRA-03
    verification:
      - kind: unit
        ref: "python3 tools/lint_core_purity.py mobile/src/core（LINT_OK files=13）"
        status: pass
    human_judgment: false

duration: 7min
completed: 2026-11-05
status: complete
---

# Phase 3 Plan 04: bytes → 结构化错误 → 全量校验 Summary

**配置错误变成可直接渲染的 `ConfigResult` + `Array[ConfigError]`：BOM 在字节层被抓住，三类动作的全部规则与 input/rumble 逐字段 typeof 守卫，一次校验给全所有独立错误，静默 clamp 降级为带实际值与截断值的可见 warning**

## Performance

- **Duration:** 7 min
- **Started:** 2026-11-04T19:41:32Z（plan 基线提交 `fb8d773` 时刻）
- **Completed:** 2026-11-04T19:48Z
- **Tasks:** 3
- **Files modified:** 13（12 新建、1 修改）

## Accomplishments

- `config_error.gd` / `config_result.gd` 落地错误对象契约：`json_path`（根 `$`、数组 `skills[3]`、字段 `.params.button`）、`code`（小写 snake_case StringName）、中文 `message`（含实际值）、中文 `fix_hint`（说清楚改哪里）、`severity`。`format_line()` 输出 `[code] path: message（fix_hint）`，`to_text()` 先 errors 后 warnings 逐行拼接，`has_code()` 同时查两类。
- `config_loader.gd` 把入口钉成 `PackedByteArray`：BOM 用 `bytes[0] == 0xEF` 在解码前判定，空文件、非法 UTF-8、JSON 语法错误各有独立错误码；`JSON.new().parse()` + `get_error_line() + 1` 拿到行号；`decode_bytes()` 单独暴露原始字典给 03-06 的覆盖层合并。loader 代码里没有 `FileAccess` / `JSON.parse_string`。
- `config_validator.gd` 885 行完成全部规则：sequence（steps 三种写法、hold 之和、时长窗口、公共时间参数）、arc（角度/时长窗口、`start_angle` 标量、七种旋转方向写法）、taps（button、间隔窗口、`modifier_options` 归一与交叉检查）、input（比例字段、axis_layout / invert / button_names、五个可截断整数）、rumble 根与技能级 pattern。
- 三个点名坏输入都在校验期早失败：`"enabled": "false"` → `bool_expected`（不是 `bool("false") == true`）、`min_duration_ms: null` → `number_expected`（不触发运行时错误）、`start_angle: [90, 180]` → `start_angle_not_scalar`（不留到检测器构造才崩）。`params.direction: "clockwisee"` → `direction_unknown`，真实配置两处 `"direction": "any"` 原样接受。
- 收集式校验：三个互不相关错误得到 3 条 error、`to_text()` 3 行；`type` 非法只跳过专项子树，`cooldown_ms` 的负数仍被检查并给出 warning。
- 六个静默 clamp 全部降级为可见 warning 并应用截断值：`poll_hz` 30~1000、`calibration_ms` 0~3000、`idle_reset_ms` / `gesture_release_ms` 0~5000、`joystick_index >= 0`、`startup_test_ms >= 10`、`duration_ms >= 1`、`gap_ms >= 0`、`cooldown_ms >= 0`、`global_cooldown_ms >= 0`。不可截断的越界（`deadzone: 1.5`）仍是 error。
- 真实配置在无头环境里被真正解析过一次：`ok()` 为真、5 条动作、名称顺序与 `shared/skills_config.json` 一致、3 处 `"required_button": null` 不产生 `button_unknown`。
- 闸门保持绿：`bash mobile/tools/test-core.sh` → `TESTS_SUITES=5` / `TESTS_ASSERTIONS=340` / `TESTS_DONE failures=0`；`python3 tools/lint_core_purity.py mobile/src/core` → `LINT_OK files=13`；`bash tools/check_desktop.sh` 230 项全绿；`bash mobile/tools/gate-a.sh` → `PACK_OK skills=5` / `GLYPH_OK chars=818`。

## Task Commits

1. **Task 1: 一段字节进，一份可渲染的错误或一份 5 条动作的配置出** — `e465011` (feat)
2. **Task 2: 三类动作的参数规则 + input/rumble 类型严格化** — `028c2c8` (feat)
3. **Task 3: 一次给全所有独立错误，并把静默 clamp 降级成可见 warning** — `151e24e` (feat)
4. **收尾清理：删除加载器里未使用的 BOM 常量** — `17fc357` (refactor)

**Plan metadata:** 见本次最终 docs 提交（SUMMARY / STATE / ROADMAP）

## Files Created/Modified

- `mobile/src/core/config/config_error.gd` — 四件套错误对象 + severity + `format_line()`
- `mobile/src/core/config/config_result.gd` — config / errors / warnings / source_path / notice / overrides_applied + `ok()` / `to_text()` / `has_code()`
- `mobile/src/core/config/config_loader.gd` — `parse_bytes` / `parse_text` / `decode_bytes`；BOM 在字节层、JSON 行号 +1
- `mobile/src/core/config/config_validator.gd` — 结构 + 三类动作参数 + input/rumble + 修饰键交叉检查 + 收集式错误 + 可见 warning
- `mobile/tests/unit/test_config_loader.gd` — 真实配置 5 条动作、BOM 合成字节、空/非法 UTF-8/语法错误、`decode_bytes`
- `mobile/tests/unit/test_config_validator.gd` — 接受路径、23 条拒绝用例、多错误、子树跳过、6 组 warning/截断
- `mobile/tests/core_runner.gd` — `SUITES` 增 `config_loader` 与 `config_validator`（共 5 条）
- 上述 4 个 core 文件与 2 个测试文件的 `.gd.uid` — `--import` 生成的导入边车（提交物）

## Decisions Made

- **入口只收字节，BOM 判定用字面量 `bytes[0] == 0xEF`**：`FileAccess.get_file_as_string()` 会静默剥 BOM，字符串入口永远测不到；`JSON.parse_string()` 失败时向 stderr 打 ERROR 且不给行号。
- **`required_button: null` 是合法值**：真实配置 5 条动作里有 3 条（马赛回旋 / 踩单车 / 磕球过人）这样写；把它报错会让真实配置过不了验收。只有「存在且是字符串或数组、归一后得到空串」才是 `button_unknown`。
- **`params.direction` 故意比 Python 严格**：Python 把未知值静默当 `any`（`detectors.py:154-160`），移动端只接受七种写法；未知值在启动前报 `direction_unknown`，而不是「看起来能练、永远不触发」。分歧由 03-05 的语料记录。
- **`start_angle` 数组在校验期拒绝**：Python 的 `parse_config` 接受 `[90, 180]`，到构造 `ArcDetector` 才抛 `TypeError`；移动端把晚失败提前到配置加载。
- **clamp 上界不统一**：`calibration_ms` 0~3000、`idle_reset_ms` / `gesture_release_ms` 0~5000，逐字照 `config.py:699-702`。统一成 5000 会让 4000 在移动端被接受、桌面版被截到 3000，而这个差异会因为语料只比 verdict 永远隐身。
- **type 非法不提前返回**：只跳过 arc/sequence/taps 专项检查，技能级字段继续查；否则一个坏 type 会把 `cooldown_ms: -5` 之类的错误一起吞掉。
- **warning 与 error 同构**：都用 `ConfigError`，只靠 `severity` 区分；`ok()` 只看 errors 与 config，warning 不阻止启动。
- **额外补齐 `require_neutral_between_steps` 与 `global_cooldown_ms`**：两者都是真实配置字段，Python 分别用 `bool()` 与 `max(0, ...)` 静默处理；移动端给出 `bool_expected` / `negative_value`，与 T-03-15 / T-03-17 的威胁缓解一致。
- **RESIL-02 不提前勾选**：本计划闭合「结构化错误 + 可原样渲染」一半，跨语言判定对等归 03-05；沿用 03-03 的原则，不用部分交付冒充完成。

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - 计划测试期望与自身规则矛盾] `calibration_ms: 4000` + `idle_reset_ms: 4000` 不可能产生两条 warning**

- **Found during:** Task 3 首次跑 `test_config_validator`
- **Issue:** 计划 Task 3 用例 ⑤ 要求这两个值同时产生两条 warning，但同一条 action 明确规定 `idle_reset_ms` 的上界是 5000——4000 在界内，按规格不应有 warning。断言与规则不可能同时成立。
- **Fix:** 拆成两个夹具：① `calibration_ms: 4000` + `idle_reset_ms: 4000` → 1 条 warning，断言 `calibration_ms == 3000` 且 `idle_reset_ms == 4000`（证明 idle 的上界大于 3000）；② `idle_reset_ms: 6000` → 1 条 warning、截断到 5000（证明 idle 的硬上界是 5000）。两个断言合起来比原来的「两条 warning」更强地证明两个上界没有被统一。
- **Files modified:** mobile/tests/unit/test_config_validator.gd
- **Verification:** `bash mobile/tools/test-core.sh` → `TESTS_DONE failures=0`；`calibration_ms == 3000`、`idle_reset_ms == 4000`、`idle_reset_ms == 5000` 三条断言均通过。
- **Committed in:** `151e24e`（Task 3 提交）

**2. [Rule 2 - 缺失的布尔/根字段检查] `require_neutral_between_steps` 与 `global_cooldown_ms` 未被校验**

- **Found during:** Task 2/3 对照 `config.py` 字段表
- **Issue:** `require_neutral_between_steps` 是真实配置字段（两个 sequence 动作都写 `true`），Python 用 `bool()` 接受任意值；`global_cooldown_ms` 用 `max(0, int(...))` 静默截断。计划的 Task 2 字段清单没有点名这两个，但它们是「类型混淆 / 静默降级」威胁面的一部分。
- **Fix:** `require_neutral_between_steps` 加 `TYPE_BOOL` 守卫，非布尔报 `bool_expected`；`global_cooldown_ms` 加数字类型检查与负数 warning（应用 0）。
- **Files modified:** mobile/src/core/config/config_validator.gd、mobile/tests/unit/test_config_validator.gd（前者实现，后者通过既有断言路径覆盖）
- **Verification:** 真实配置仍 `ok()`；`TESTS_DONE failures=0`；`LINT_OK files=13`。
- **Committed in:** `028c2c8` / `151e24e`

**3. [Rule 1 - 机械验收形状] `_read_bool` 的方法名包含 `bool(`，触发「禁止 `bool(` 强转」的字面检查**

- **Found during:** Task 2 验收
- **Issue:** 验收脚本用 `'bool(' in code` 拦截 `bool(...)` 强转，而共享守卫函数名 `_read_bool(` 本身包含这个子串；实现里没有任何布尔强转，但检查会误报。
- **Fix:** 把守卫函数改名为 `_read_boolean`，语义不变；同时为 `rumble.enabled` / `rumble.startup_test` 各写独立的 `TYPE_BOOL` 守卫，满足「每个布尔字段各自守卫」的机械判据。
- **Files modified:** mobile/src/core/config/config_validator.gd
- **Verification:** 字面检查 `forbidden: []`；`grep -c 'TYPE_BOOL'` = 6；`TESTS_DONE failures=0`。
- **Committed in:** `028c2c8`

**4. [Rule 3 - 编译阻塞] Godot 4.7.2 把「从 Variant 推断变量类型」当成错误**

- **Found during:** Task 2 首次跑 `test-core.sh`（`config_validator.gd:237/661`）
- **Issue:** `var angle := _read_direction(...)` 与 `var angle := DirectionTable.resolve(...)` 的返回值是 `Variant`，Godot 4.7.2 把它当 warning 并 error 掉，导致 `ConfigValidator` 编译失败、全局类名解析不到。
- **Fix:** 两处改成显式 `var angle: Variant = ...`。
- **Files modified:** mobile/src/core/config/config_validator.gd
- **Verification:** `bash mobile/tools/test-core.sh` → 5 套件、340 条断言、0 失败。
- **Committed in:** `028c2c8`

---

**Total deviations:** 4 auto-fixed（2 处规则/检查形状、1 处缺失校验、1 处编译阻塞）
**Impact on plan:** 无功能削弱；测试 ⑤ 的改法比原断言更强地证明了 clamp 上界差异；新增的两个字段检查属于威胁模型内的正确性补齐，没有扩大范围。

## Issues Encountered

- 非法 UTF-8 的测试字节 `[0xFF, 0xFE, 0x7B]` 在 `get_string_from_utf8()` 里被替换成 U+FFFD，最终以 `json_syntax_error` 被拒绝，而不是 `invalid_utf8`。计划明确允许二者之一，套件按「被拒绝且有可读错误」断言，不锁实现细节。
- Godot 对 `Variant` 推断的警告在本项目的编译配置下是 error（见 deviation 4）；后续在 core 里接 `Variant` 返回值时必须显式标注类型。
- 本机没有 `gsd_run` 命令（`command -v gsd_run` 为空），STATE.md / ROADMAP.md 按 `state advance-plan` / `update-progress` / `record-metric` 的语义手工更新。

## User Setup Required

None - 无外部服务或环境变量；Godot 4.7.2 已在 Phase 2 安装并校验。

## Next Phase Readiness

- `03-05` 可以直接拿 `ConfigResult` / `ConfigError` 做跨语言语料：`codes` 与 `json_path` 已是稳定契约，BOM 必须走字节入口（`path.read_text()` + `json.loads`），不能用 `json.loads(bytes)`（后者按 `utf-8-sig` 接受 BOM）。
- `03-06` 可以直接用 `ConfigLoader.decode_bytes()` 拿原始字典做覆盖层合并，再用 `ConfigValidator.validate(merged)` 整体校验；`ConfigResult.notice` / `overrides_applied` 已预留。
- 新增配置字段时的两条硬约定：先 `typeof` 再转换（数值收 INT/FLOAT、布尔只收 BOOL、字符串只收 STRING）；可截断字段进 `warnings` 并带实际值与截断值。
- `bash mobile/tools/test-core.sh` 现在覆盖 13 个 core 文件 + 5 条套件；新增套件只需在 `core_runner.gd` 的 `SUITES` 里显式 `preload`。

## Known Stubs

None.

## Threat Flags

None — 本计划未引入威胁模型之外的新表面。T-03-14（BOM）由字节层判定 + 合成字节用例缓解；T-03-15（类型混淆）由逐字段 `typeof` + 三个点名坏输入早失败缓解；T-03-16（运行期崩溃/中途返回）由收集式校验 + 零 `assert` + 零日志缓解；T-03-17（静默降级）由 `SEVERITY_WARNING` + 实际值/截断值缓解；T-03-18（真实配置假绿）由真实文件读取 + 缺失即失败缓解；T-03-SC 无包管理器安装。

## Self-Check: PASSED

- 13 个交付文件全部存在（4 个 core + 4 个 `.uid` + 2 个测试 + 2 个测试 `.uid` + `core_runner.gd`）。
- 4 个提交 `e465011` / `028c2c8` / `151e24e` / `17fc357` 均为 HEAD 祖先；`plan_head_before..HEAD` 实测 4 个提交，与 `actuals.commits` 一致。
- `bash mobile/tools/test-core.sh`（`TESTS_SUITES=5` / `TESTS_ASSERTIONS=340` / `TESTS_DONE failures=0`）、`python3 tools/lint_core_purity.py mobile/src/core`（`LINT_OK files=13`）、`bash tools/check_desktop.sh`（230 项）、`bash mobile/tools/gate-a.sh`（`PACK_OK skills=5` / `GLYPH_OK chars=818`）在本次执行中全部通过。
