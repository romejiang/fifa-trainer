---
phase: 03-core-foundation
verified: 2026-11-04T20:16:44Z
status: passed
score: 49/49 must-haves verified
covered_files: [
  ".planning/phases/03-core-foundation/03-01-PLAN.md",
  ".planning/phases/03-core-foundation/03-01-SUMMARY.md",
  ".planning/phases/03-core-foundation/03-02-PLAN.md",
  ".planning/phases/03-core-foundation/03-02-SUMMARY.md",
  ".planning/phases/03-core-foundation/03-03-PLAN.md",
  ".planning/phases/03-core-foundation/03-03-SUMMARY.md",
  ".planning/phases/03-core-foundation/03-04-PLAN.md",
  ".planning/phases/03-core-foundation/03-04-SUMMARY.md",
  ".planning/phases/03-core-foundation/03-05-PLAN.md",
  ".planning/phases/03-core-foundation/03-05-SUMMARY.md",
  ".planning/phases/03-core-foundation/03-06-PLAN.md",
  ".planning/phases/03-core-foundation/03-06-SUMMARY.md",
  "mobile/README.md",
  "mobile/docs/CORE.md",
  "mobile/export_presets.cfg",
  "mobile/project.godot",
  "mobile/src/app/config_store.gd",
  "mobile/src/core/config/config_error.gd",
  "mobile/src/core/config/config_loader.gd",
  "mobile/src/core/config/config_result.gd",
  "mobile/src/core/config/config_validator.gd",
  "mobile/src/core/config/overlay_merge.gd",
  "mobile/src/core/config/overlay_result.gd",
  "mobile/src/core/domain/app_config.gd",
  "mobile/src/core/domain/buttons.gd",
  "mobile/src/core/domain/direction_table.gd",
  "mobile/src/core/domain/input_config.gd",
  "mobile/src/core/domain/pulse.gd",
  "mobile/src/core/domain/rumble_config.gd",
  "mobile/src/core/domain/skill.gd",
  "mobile/src/core/domain/step.gd",
  "mobile/src/core/geometry.gd",
  "mobile/tests/core_runner.gd",
  "mobile/tests/fixtures/config_corpus.json",
  "mobile/tests/fixtures/geometry_golden.json",
  "mobile/tests/unit/test_config_corpus.gd",
  "mobile/tests/unit/test_config_loader.gd",
  "mobile/tests/unit/test_config_store.gd",
  "mobile/tests/unit/test_config_validator.gd",
  "mobile/tests/unit/test_geometry.gd",
  "mobile/tests/unit/test_models.gd",
  "mobile/tests/unit/test_overlay_merge.gd",
  "mobile/tests/unit/test_vocabulary.gd",
  "mobile/tools/check_pack.gd",
  "mobile/tools/test-core-selftest.sh",
  "mobile/tools/test-core.sh",
  "tools/check_config_parity.py",
  "tools/gen_geometry_golden.py",
  "tools/lint_core_purity.py",
  "tools/test_lint_core_purity.py"
]
covered_digest: "v3:sha256:a66ba1a3aafdd7141099c20942bbf3e4e942432fb30e991385141fe2fdb45bad"
behavior_unverified: 0
overrides_applied: 0
re_verification:
  previous_status: gaps_found
  previous_score: 48/49
  gaps_closed:
    - "T4-2：非法 UTF-8 现在稳定返回 invalid_utf8。decode_bytes 改为解码后 to_utf8_buffer() 与原始字节逐字节往返比对；test_config_loader.gd 的「invalid_utf8 或 json_syntax_error 二者之一」收紧为必须 invalid_utf8。独立探针确认 7 种非法序列全部命中 invalid_utf8，BOM/空文件/语法错误三种码不变。"
  gaps_remaining: []
  regressions: []
---

# Phase 3: 纯核心地基 Verification Report

**Phase Goal:** `mobile/src/core/` 成为一个零引擎依赖、可在无场景树无手柄条件下运行并通过测试的纯 GDScript 层，角度约定与配置错误信息一次钉死。
**Verified:** 2026-11-04T20:16:44Z
**Status:** passed
**Re-verification:** Yes — 上一轮唯一 gap（T4-2 `invalid_utf8` 死分支）由提交 `f0e35d0` 修复后复验

> **口径说明（非代码缺口）：** ROADMAP 把本阶段标为 `mode: mvp`，但阶段目标不是
> `As a …, I want to …, so that …` 形式，`query user-story.validate` 返回 `valid=false`。
> 本阶段是纯基础设施层，没有用户可见流程，因此按 Roadmap 的 5 条 Success Criteria +
> 6 份 PLAN 的 must_haves 做目标回退验证；未生成 User Flow Coverage 表。若需要严格
> MVP 口径，应先运行 `/gsd-mvp-phase 3` 改写目标。

---

## Goal Achievement

### Roadmap Success Criteria

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| SC1 | 一条 headless 命令跑完几何与配置测试并返回退出码，不需要窗口、场景树或手柄 | ✓ VERIFIED | 本轮实跑 `bash mobile/tools/test-core.sh` exit 0；`TESTS_SUITES=8 / TESTS_ASSERTIONS=576 / TESTS_DONE failures=0`；全流程无显示服务、无手柄、无导出模板 |
| SC2 | 八方向 + 中心黄金表与 Python 版逐项一致（<1e-9），0°=上、顺时针为正；`(0,0)` 返回 0 而非 π | ✓ VERIFIED | `geometry.gd:38-45` 居中守卫；`geometry_golden.json` 9 条 `angle_of`（含 center expected 0.0）；`test_geometry.gd` `TOL=1e-9` 逐向量比较；`gen_geometry_golden.py --check` exit 0 |
| SC3 | 注入 BOM / 字符串布尔 / `null` 数值 / `start_angle` 数组后得到结构化错误列表（`json_path`+`code`+修复建议），可原样渲染；无 `push_error` 或静默降级 | ✓ VERIFIED | 四条点名用例分别得到 `bom_detected` / `bool_expected` / `number_expected` / `start_angle_not_scalar`；`ConfigError.format_line()` 四要素齐全；66 处 `_fail/_warn` 全部带非空 `fix_hint`；lint `logging` 规则零命中 |
| SC4 | `src/core/` 架构 lint 出现 `Input.` / `Time.` / `Node` / `FileAccess` / `print(` 时非零退出，干净时零退出 | ✓ VERIFIED | `LINT_OK files=15`（非真空）；反例自测 54 项全绿，五条硬规则各自命中、注释/字符串不误报、退出码 0/1/2 三档均有断言 |
| SC5 | 用户修改写入 `user://` 稀疏覆盖层；base hash 变化时丢弃并提示；运行期绝不写 `res://` | ✓ VERIFIED | `config_store.gd:87-88` 对 target 与 temp 双重 `begins_with("user://")` 守卫，否则 `ERR_UNAUTHORIZED`；`overlay_merge.gd:42-46` hash 不匹配整体丢弃；`test_config_store.gd:88-97` 断言 `res://` 写入零副作用；hash 过期 notice 逐字断言 |

**Roadmap SC score:** 5/5

### Plan must-have truths

#### 03-01（RESIL-03）

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| T1-1 | `test-core.sh` 在无窗口/场景树/手柄机器上跑完并退出 0，不需要导出模板/真机 | ✓ VERIFIED | 本轮实跑 exit 0；runner `extends SceneTree` 只做纯计算；无 `display`/`joystick` 初始化 |
| T1-2 | 通过判据只有 stdout 的 `TESTS_DONE failures=0`，不能只看 `$?` | ✓ VERIFIED | `test-core.sh:134` `grep -qE '^TESTS_DONE failures=0$'`；自测 `stub_rc0_silent`（rc=0 无哨兵）本轮仍变红 |
| T1-3 | 挂死必须由看门狗判失败，不能永久阻塞 | ✓ VERIFIED | `test-core.sh:107-122` 后台进程 + TERM→2s→KILL；本轮 `SELFTEST_OK cases=5`，`stub_hang` 2s 内被杀并变红 |
| T1-4 | 黄金夹具由 Python 重新推导；手改会被 `--check` 抓住并打印差异 | ✓ VERIFIED | `gen_geometry_golden.py:170-215` 逐字节比较并打印首个差异行；本轮 `--check` exit 0；夹具 meta 含 `padskills/geometry.py` 的 sha256 |
| T1-5 | 9 条 `angle_of` 与 Python 一致（1e-9），0°=上、顺时针为正；`(0,0)` 精确 0.0 | ✓ VERIFIED | `geometry_golden.json` 9 条 + `test_geometry.gd:74-83` 精确断言；本轮黄金校验通过 |
| T1-6 | `signed_delta(0,180) == -180` 被固化为黄金向量 | ✓ VERIFIED | `geometry.gd:31` floor-mod 公式；夹具第 1 条 `expected: -180.0` |
| T1-7 | `angle_diff(0,180) == 180` | ✓ VERIFIED | `geometry.gd:34-35` 取绝对值；夹具与 `test_geometry.gd:88` |
| T1-8 | 测试脚本不进入 APK | ✓ VERIFIED | `export_presets.cfg:18` `exclude_filter="build/*,tools/*.png,tests/*"`；`check_pack.gd:39-41` 从 PCK 断言 `res://tests/core_runner.gd` 不存在；本轮 gate A `PACK_OK` |

#### 03-02（INFRA-03）

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| T2-1 | 干净树 exit 0 + `LINT_OK files=N`；命中 exit 1 + `路径:行号: 规则: 片段` | ✓ VERIFIED | 本轮实跑 `LINT_OK files=15`；`lint_core_purity.py:219-228`；脏 canary 输出真实行号与规则名 |
| T2-2 | 注释/文档字符串/错误消息里的同样 token 不算命中 | ✓ VERIFIED | `_mask()` 状态机先剥注释与字符串；自测中文样本 0 命中（本轮 54 项全过） |
| T2-3 | `InputSource` / `NodeState` / `NodePath` / 小写 `input.deadzone` 不误伤 | ✓ VERIFIED | 规则使用 `\b` 与大小写敏感；自测显式构造这些标识符并断言 0 命中 |
| T2-4 | 目标不存在或目录无 `.gd` 时 exit 2 | ✓ VERIFIED | `lint_core_purity.py:210-217`；自测对空目录/不存在路径各断言 rc=2 |
| T2-5 | lint 自身有反例：五条硬规则各自有牙齿、注释/字符串不误报、退出码 0/1/2 | ✓ VERIFIED | 本轮 `test_lint_core_purity.py` 54 项通过、0 失败 |
| T2-6 | lint 排在所有 Godot 调用之前，是 `test-core.sh` 固定步骤 | ✓ VERIFIED | `test-core.sh:44-58`：配置校验 → lint 自测 → 真 lint → 黄金 → parity → 导入 → 测试 |
| T2-7 | `CORE.md` 与规则表同源，缺一条规则 id 判红 | ✓ VERIFIED | 自测读取 `--list-rules` 并逐条断言出现在 CORE.md；14 条全部命中（本轮输出逐条 ✓） |

#### 03-03（RESIL-02）

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| T3-1 | 按键/方向别名解析与桌面版一致（L1→LB、R2→RT、TRIANGLE→Y、dpad_up→DPAD_UP、前右→45、RIGHT→90、-90→270） | ✓ VERIFIED | `buttons.gd:48-56` + `direction_table.gd:33-52`；`test_vocabulary.gd` 逐条断言，三张表条目数 17/39/42 |
| T3-2 | 未知按键返回 `""`、未知方向返回 `null`；不抛异常/不打印/不 `push_error` | ✓ VERIFIED | `buttons.gd:56`、`direction_table.gd:52`；lint `logging` 零命中；错误由 `ConfigValidator` 转成 `ConfigError` |
| T3-3 | 布尔不是方向，`true/false` 被拒绝 | ✓ VERIFIED | `direction_table.gd:36-37` 显式 `TYPE_BOOL` 拒绝；`config_validator.gd:781-785` 另报 `direction_is_bool` |
| T3-4 | 六个域对象默认值与 Python 逐字段相同；`Skill.pattern` 默认一条 Pulse | ✓ VERIFIED | 逐字段对照 `desktop/padskills/config.py:196-262`；`test_models.gd:67-105` 断言 pattern 一条且两实例独立；`rumble_summary()` 文案逐字一致 |
| T3-5 | `enabled_skills()` 返回新数组；域对象不承载校验 | ✓ VERIFIED | `app_config.gd:19-25` 显式收集；`test_models.gd:128-139` 清空返回值后内部仍有 2 条 |
| T3-6 | 一个 `class_name` 一个文件；类型化容器真能编译 | ✓ VERIFIED | 15 个 `.gd` 各一 `class_name`（`LINT_OK files=15`）；`Array[Skill]`/`Array[Pulse]`/`Array[String]` 在 `--import` 与 8 条套件中真实编译 |

#### 03-04（RESIL-02）

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| T4-1 | 坏配置得到 `ConfigResult` + `Array[ConfigError]`，四要素齐全；四个点名坏输入 `fix_hint` 非空，BOM 含 `UTF-8` | ✓ VERIFIED | `config_error.gd:19-25`；`test_config_validator.gd:442-459` 逐条断言非空；`test_config_loader.gd:74-75` 断言 BOM 提示含 `UTF-8` |
| T4-2 | BOM / 空文件 / 非法 UTF-8 / JSON 语法错误各有一种错误码；语法错误带行号 | ✓ VERIFIED（本轮修复） | `config_loader.gd:36-39` BOM→`bom_detected`；`:40-43` 空→`file_empty`；`:48-52` 解码后 `to_utf8_buffer()` 与原始字节逐字节比对，失败→`invalid_utf8`；`:62-67` 语法→`json_syntax_error` + `get_error_line()+1`。独立探针 7 种非法序列全部 `invalid_utf8`；`test_config_loader.gd:89-98` 已硬断言 `has_code(&"invalid_utf8")` |
| T4-3 | core 无 `push_error`/`printerr`/`print`；用 `JSON.new().parse()` | ✓ VERIFIED | lint `logging` 零命中；`config_loader.gd:62-63` 使用 `JSON.new().parse()` 并取行号 |
| T4-4 | 真实配置 `ok()`、5 条动作、名称与 shared 一致；缺失必须失败 | ✓ VERIFIED | 本轮套件通过；`test_config_loader.gd:34-46`；名称与 `shared/skills_config.json` 逐字一致；探针 `real-config-parse ok()=true skills=5` |
| T4-5 | 先 `typeof` 再转换；字符串布尔/`null` 数值被拒；未知 `params.direction` 报 `direction_unknown` | ✓ VERIFIED | `config_validator.gd:672-697`；direction 白名单 `:21-23, 321-330`；语料三侧一致 |
| T4-6 | `start_angle` 数组在校验期被拒为 `start_angle_not_scalar` | ✓ VERIFIED | `config_validator.gd:289-298`；语料 `start_angle_array` 期望 `reject` + 该码 |
| T4-7 | 一次给全部独立错误；仅在前提不成立时跳过依赖子树 | ✓ VERIFIED | `config_validator.gd:39-45` 收集式；`test_config_validator.gd:203-220` 三个互不相关错误恰好 3 条 |
| T4-8 | 静默 clamp 变成可见 warning（`poll_hz:5000`→1000、`cooldown_ms:-5`→0），不阻止启动 | ✓ VERIFIED | `config_validator.gd:459-468, 119-124`；`test_config_validator.gd:259-305` 断言 `ok()` 为真、warning code 与截断值 |

#### 03-05（RESIL-02）

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| T5-1 | 一份语料被 GDScript 与 Python 两侧读取，语料是唯一契约 | ✓ VERIFIED | `config_corpus.json` 28 条；`test_config_corpus.gd` 调真实 `ConfigLoader.parse_bytes`；`check_config_parity.py` 调真实 `parse_config` + `build_detector` |
| T5-2 | 四个点名坏输入各有语料用例，`code` 与 `json_path` 同时出现在 `to_text()` | ✓ VERIFIED | 语料 id `bom` / `string_bool` / `null_number` / `start_angle_array`；`test_config_corpus.gd:82-103` 同时断言 code/path/`to_text()` |
| T5-3 | 两侧判定不一致必须带非空 `divergence` 与 `python.note`，否则判红 | ✓ VERIFIED | `check_config_parity.py:168-184` 三类失败出口；本轮实跑 `PARITY_OK cases=28 divergences=4` |
| T5-4 | `start_angle` 数组 Python 记 `accept_then_detector_reject`，GDScript 记 `reject` + `start_angle_not_scalar` | ✓ VERIFIED | 语料对应条目；`check_config_parity.py:82-88` 对 accept 用例再跑 `build_detector` |
| T5-5 | 语料规模有下限，防真空绿 | ✓ VERIFIED | `test_config_corpus.gd:52-62` 断言 ≥4 与 ≥16；实际 28 |
| T5-6 | Python 侧模拟 `read_text` + `json.loads(str)`，不用 `json.loads(bytes)` | ✓ VERIFIED | `check_config_parity.py:56-67`；BOM 用 `"\ufeff" + text` 走字符路径 |
| T5-7 | `python: accept` 用例还要跑 `build_detector()` | ✓ VERIFIED | `check_config_parity.py:82-88`；`start_angle_array` 因此得到 `accept_then_detector_reject` |

#### 03-06（DATA-03）

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| T6-1 | 写 `user://config/overrides.json`，运行期绝不写 `res://`；`save_overrides()` 前缀不匹配返回 `ERR_UNAUTHORIZED` | ✓ VERIFIED | `config_store.gd:19-22, 83-88`；`test_config_store.gd:88-97` 断言无文件、无目录副作用 |
| T6-2 | 覆盖层稀疏：只允许 `enabled`/`required_button`/`button_mode`，以 skill name 为键，`params` 永不进入 | ✓ VERIFIED | `overlay_merge.gd:23, 70-82`；`test_overlay_merge.gd:107-120` 断言 `params` 阈值不变、未知键不写入 |
| T6-3 | base sha256 变化整体丢弃 + 中文 notice + 删除文件 | ✓ VERIFIED | `overlay_merge.gd:42-46`；`config_store.gd:129-132`；`test_config_store.gd:172-185` 逐字断言 notice |
| T6-4 | 原子写 temp + `flush()` + `close()` + rename；成功后无 `.tmp` | ✓ VERIFIED | `config_store.gd:92-103`；`test_config_store.gd:101-113` 真实 I/O 断言 `.tmp` 消失且可覆盖改名 |
| T6-5 | 首启无覆盖层是正常状态：不建空文件、不报错、不提示 | ✓ VERIFIED | `config_store.gd:64-67`；`test_config_store.gd:60-85` 断言 notice 为空 |
| T6-6 | `user://` 目录名一次定死为 `FifaSkillTrainer` | ✓ VERIFIED | `mobile/project.godot:14-15` `use_custom_user_dir=true` + `custom_user_dir_name="FifaSkillTrainer"` |
| T6-7 | 坏覆盖层丢弃并删除，`load_config()` 返回 base + notice；未知 skill/键只 warning 且经 `ConfigResult.warnings` 抵达调用方 | ✓ VERIFIED | `config_store.gd:108-132`；转交在 `:75`；`test_config_store.gd:120-206` 断言 2 条 warning 真到调用方 |
| T6-8 | 合并是纯逻辑（不改入参、深拷贝 base），文件 I/O 只在 `config_store.gd` | ✓ VERIFIED | `overlay_merge.gd:27-31` `base.duplicate(true)`；`test_overlay_merge.gd` 断言 base 逐字不变；lint 对 `src/core` 的 `FileAccess` 零命中 |

**Plan truth score:** 44/44

### Combined score

**49/49 must-haves verified**（5/5 Roadmap SC + 44/44 plan truths），0 项 present-but-behavior-unverified。

### Deferred Items

无。上一轮唯一缺口 T4-2 已在本轮关闭。

### Advisory (New Scope, Unevidenced)

None。本轮复验未发现新的、无确定性证据的越界项。

---

## Required Artifacts

`gsd-tools query verify.artifacts` 对 6 份 PLAN 的机械结果：03-01 8/8、03-02 5/5、03-03 9/11、03-04 6/7、03-05 5/5、03-06 7/7（共 40/43）。未通过项全部是 `min_lines` 估算偏差，逐文件阅读确认功能完整、无 stub：

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `mobile/src/core/geometry.gd` | 角度工具 5 函数 | ✓ VERIFIED | 50 行；`fposmod` floor-mod；居中守卫 |
| `tools/gen_geometry_golden.py` | 生成器 + `--check` | ✓ VERIFIED | 224 行；逐字节比较 |
| `mobile/tests/fixtures/geometry_golden.json` | 36 条黄金向量 | ✓ VERIFIED | 9+5+7+6+9 条，生成物 |
| `mobile/tests/core_runner.gd` | 无头多套件 runner | ✓ VERIFIED | 8 套件、`complete()` 缺失检测、哨兵 |
| `mobile/tests/unit/test_geometry.gd` | 几何套件 | ✓ VERIFIED | 89 行；1e-9 容差 + 精确端点 |
| `mobile/tools/test-core.sh` | 唯一闸门 | ✓ VERIFIED | 145 行；顺序固定 + 看门狗 + 哨兵 |
| `mobile/tools/test-core-selftest.sh` | 四种假绿反例 | ✓ VERIFIED | 本轮 `SELFTEST_OK cases=5` |
| `mobile/tests/fixtures/.gdignore` | 夹具不进导入/PCK | ✓ VERIFIED | 存在且生效（`PACK_OK`） |
| `tools/lint_core_purity.py` | 扫描器 14 规则/三档退出 | ✓ VERIFIED | 232 行；注释/字符串剥离状态机 |
| `tools/test_lint_core_purity.py` | lint 反例自测 | ✓ VERIFIED | 275 行、54 项断言全过 |
| `mobile/docs/CORE.md` | 边界契约 | ✓ VERIFIED | 129 行；14 条规则 id 全覆盖 |
| `mobile/src/core/domain/buttons.gd` | 17 规范名 + 39 别名 | ✓ VERIFIED | 56 行；条目数由测试硬断言 |
| `mobile/src/core/domain/direction_table.gd` | 42 条方向别名 | ✓ VERIFIED（低于估算 3 行） | 52 行；42 条逐条照抄；行数偏差非 stub |
| `mobile/src/core/domain/pulse.gd` | Pulse | ✓ VERIFIED | 25 行；默认值对等 |
| `mobile/src/core/domain/step.gd` | Step | ✓ VERIFIED | 22 行；angles 构造时复制 |
| `mobile/src/core/domain/skill.gd` | Skill | ✓ VERIFIED | 43 行；pattern 默认一条 Pulse |
| `mobile/src/core/domain/input_config.gd` | InputConfig 12 字段 | ✓ VERIFIED | 34 行；逐字段对等 |
| `mobile/src/core/domain/rumble_config.gd` | RumbleConfig | ✓ VERIFIED（低于估算 2 行） | 16 行；5 字段完整；行数偏差 |
| `mobile/src/core/domain/app_config.gd` | AppConfig | ✓ VERIFIED | 25 行；`enabled_skills()` 新数组 |
| `mobile/src/core/config/config_error.gd` | ConfigError 四要素 | ✓ VERIFIED | 39 行 |
| `mobile/src/core/config/config_result.gd` | ConfigResult | ✓ VERIFIED | 49 行；`to_text()` 可渲染 |
| `mobile/src/core/config/config_loader.gd` | bytes/text/JSON 入口 | ✓ VERIFIED（低于估算 8 行；本轮 +1 行注释） | 82 行；三入口齐全；`invalid_utf8` 分支本轮已可达（探针验证） |
| `mobile/src/core/config/config_validator.gd` | 收集式校验 + warning | ✓ VERIFIED | 885 行；59 处 `_fail` + 7 处 `_warn` 全带 fix_hint |
| `mobile/src/core/config/overlay_result.gd` | OverlayResult | ✓ VERIFIED | 29 行 |
| `mobile/src/core/config/overlay_merge.gd` | 纯合并语义 | ✓ VERIFIED | 101 行；深拷贝 + 白名单 |
| `mobile/src/app/config_store.gd` | 唯一 I/O 入口 | ✓ VERIFIED | 172 行；`user://` 守卫 + 原子写 |
| `mobile/tests/unit/test_vocabulary.gd` | 词汇表套件 | ✓ VERIFIED | 108 行 |
| `mobile/tests/unit/test_models.gd` | 域对象套件 | ✓ VERIFIED | 147 行 |
| `mobile/tests/unit/test_config_loader.gd` | 加载器套件 | ✓ VERIFIED | 146 行；四种错误码逐个硬断言（本轮收紧 invalid_utf8） |
| `mobile/tests/unit/test_config_validator.gd` | 校验器套件 | ✓ VERIFIED | 500 行 |
| `mobile/tests/fixtures/config_corpus.json` | 跨语言语料 ≥16 | ✓ VERIFIED | 711 行 / 28 条 |
| `mobile/tests/unit/test_config_corpus.gd` | 语料套件 | ✓ VERIFIED | 154 行；规模下限 + 逐用例 |
| `tools/check_config_parity.py` | Python 侧判定器 | ✓ VERIFIED | 216 行 |
| `mobile/tests/unit/test_overlay_merge.gd` | 合并矩阵 | ✓ VERIFIED | 177 行；七条语义 |
| `mobile/tests/unit/test_config_store.gd` | 真实 I/O 矩阵 | ✓ VERIFIED | 260 行；坏/偏/半/旧四路 |
| `mobile/project.godot` | 自定义 user 目录 | ✓ VERIFIED | 14-15 行 |
| `mobile/tools/check_pack.gd` | PCK 内断言 | ✓ VERIFIED | 含 tests 排除检查 |

**Wiring status:** 全部 WIRED。`src/core` 15 个模块均被 `ConfigStore` / `ConfigValidator` / runner 套件实际引用；无 ORPHANED。

---

## Key Link Verification

`gsd-tools query verify.key-links` 对 6 份 PLAN：19/19 全部 `verified=true`，0 pending。

| From | To | Via | Status | Details |
|------|----|----|--------|---------|
| `mobile/tools/test-core.sh` | `tools/sync_config.py` | `--check` | WIRED | `test-core.sh:39`，第一步 |
| `mobile/tools/test-core.sh` | `mobile/tests/core_runner.gd` | 看门狗 + 哨兵 | WIRED | `:125-137` |
| `mobile/tests/unit/test_geometry.gd` | `geometry_golden.json` | bytes + `JSON.new()` | WIRED | `test_geometry.gd:22-28` |
| `tools/gen_geometry_golden.py` | `desktop/padskills/geometry.py` | `import padskills.geometry` | WIRED | 生成器第 29-40 行 |
| `mobile/tools/test-core.sh` | `tools/lint_core_purity.py` | 固定第二步 | WIRED | `:44-58`，先于任何 Godot 调用 |
| `tools/test_lint_core_purity.py` | `mobile/docs/CORE.md` | `--list-rules` 互锁 | WIRED | 14 条 id 全断言 |
| `mobile/src/core/config/config_loader.gd` | `config_validator.gd` | `ConfigValidator.validate` | WIRED | `config_loader.gd:78`（本轮下移 2 行） |
| `mobile/tests/unit/test_config_loader.gd` | `mobile/assets/config/skills_config.json` | `FileAccess.get_file_as_bytes` | WIRED | 文件缺失即 `check(false)`，不 skip |
| `mobile/src/core/config/config_validator.gd` | `buttons.gd` | `Buttons.canonical` | WIRED | `config_validator.gd:336, 829` |
| `mobile/tests/unit/test_config_corpus.gd` | `config_corpus.json` | bytes 读取 | WIRED | `.gdignore` 下仍可读 |
| `tools/check_config_parity.py` | `desktop/padskills/config.py` | `parse_config` | WIRED | `:52` |
| `tools/check_config_parity.py` | `desktop/padskills/detectors.py` | `build_detector` | WIRED | `:53, 82-88` |
| `mobile/src/app/config_store.gd` | `decode_bytes` / `OverlayMerge.merge` / `ConfigValidator.validate` | 三步链 | WIRED | `config_store.gd:56, 129, 72` |
| `mobile/src/app/config_store.gd` | `user://config/overrides.json` | 常量 + 前缀守卫 | WIRED | `:22, 87-88` |
| `mobile/tests/unit/test_config_store.gd` | `res://assets/config/skills_config.json` | `FileAccess.get_sha256` | WIRED | `:223` |
| `mobile/src/core/domain/direction_table.gd` | `desktop/padskills/config.py` | `DIRECTION_ALIASES` 42 条 | WIRED | 测试硬断言条目数 |
| `mobile/src/core/domain/buttons.gd` | `desktop/padskills/input_source.py` | 17 规范 + 39 别名 | WIRED | 测试硬断言条目数 |
| `mobile/tests/core_runner.gd` | `test_vocabulary.gd` | 显式 `preload` | WIRED | `core_runner.gd:53` |

---

## Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| `ConfigStore.load_config()` | `AppConfig` | `res://assets/config/skills_config.json` 真实字节 → `decode_bytes` → overlay → `validate` | 是（5 条动作，测试逐名断言） | ✓ FLOWING |
| `ConfigResult.errors` | `Array[ConfigError]` | 校验器/加载器现场构造 | 是（28 条语料 + 多错误用例 + 7 种非法 UTF-8） | ✓ FLOWING |
| `ConfigResult.warnings` | `Array[ConfigError]` | `OverlayMerge` → `load_config` 转交 | 是（2 条 warning 抵达调用方） | ✓ FLOWING |
| `Skill.pattern` | `Array[Pulse]` | 配置缺省/显式 rumble | 是（默认一条 Pulse） | ✓ FLOWING |

本阶段无 UI 渲染路径；错误屏消费在 Phase 7。

---

## Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| 核心闸门 | `bash mobile/tools/test-core.sh` | exit 0；`TESTS_SUITES=8`、`TESTS_ASSERTIONS=576`、`TESTS_DONE failures=0` | ✓ PASS |
| 四种假绿反例 | `bash mobile/tools/test-core-selftest.sh` | `SELFTEST_OK cases=5`；`stub_rc0_silent`/`stub_fail`/`stub_zero_assertions`/`stub_hang` 全红；正例绿 | ✓ PASS |
| 架构 lint | `python3 tools/lint_core_purity.py mobile/src/core` | `LINT_OK files=15`，exit 0 | ✓ PASS |
| lint 反例 | `python3 tools/test_lint_core_purity.py` | 54 项通过、0 失败 | ✓ PASS |
| 跨语言判定 | `python3 tools/check_config_parity.py` | `PARITY_OK cases=28 divergences=4`，exit 0 | ✓ PASS |
| 黄金未漂移 | `python3 tools/gen_geometry_golden.py --check` | 36 条向量一致，exit 0 | ✓ PASS |
| 闸门 A（PCK/字形） | `bash mobile/tools/gate-a.sh` | `PACK_OK skills=5`、`GLYPH_OK chars=818`，exit 0 | ✓ PASS |
| 桌面回归 | `bash tools/check_desktop.sh` | exit 0；230 项全通过，名称与基线逐项一致 | ✓ PASS |
| 非法 UTF-8 错误码（7 种序列） | Godot headless 探针调 `ConfigLoader.parse_bytes` | `ff-fe-7b` / `ff-alone` / `c3-truncated` / `lone-continuation` / `overlong-slash` / `surrogate-pair` / `latin1-gbk` 全部 `invalid_utf8` | ✓ PASS |
| 合法 UTF-8 不误判 | 同上探针（真实配置 / 中文+4 字节 emoji / CRLF / combining / tabs） | 真实配置 `decode error=null` 且 `ok()=true skills=5`；其余合法样本均未被判 `invalid_utf8` | ✓ PASS |
| BOM 不被往返校验抢走 | 同上探针（`EF BB BF` + 真实配置） | `bom_detected`，且 errors 恰好 1 条 | ✓ PASS |
| 空文件 / 语法错误码不变 | 同上探针 | 空 → `file_empty`；语法 → `json_syntax_error` 且消息含「第 1 行」 | ✓ PASS |

---

## Probe Execution

PLAN/SUMMARY 未声明 `scripts/*/tests/probe-*.sh`，仓库内也无该约定路径；改为直接执行闸门与本报告自建的只读探针。

| Probe | Command | Result | Status |
|-------|---------|--------|--------|
| `test-core.sh` | `bash mobile/tools/test-core.sh` | 哨兵 `TESTS_DONE failures=0`、`TESTS_ASSERTIONS=576`、exit 0 | PASS |
| `test-core-selftest.sh` | `bash mobile/tools/test-core-selftest.sh` | `SELFTEST_OK cases=5` | PASS |
| loader 错误码探针 | `godot --headless --path mobile --script <tmp>/loaderprobe.gd` | `PROBE_OK`；7 种非法 UTF-8 → `invalid_utf8`；BOM → `bom_detected`；空 → `file_empty`；语法 → `json_syntax_error`（含行号） | PASS |
| 假阳性探针 | `godot --headless --path mobile --script <tmp>/falsepositive.gd` | `NO_FALSE_POSITIVE`（CRLF / U+10FFFF / combining / tabs 均正常解码；真实配置解码与 `ok()` 均通过） | PASS |

> ℹ️ 探针附注（不影响判定）：原始 NUL 字节（`[0x7B,0x00,0x7D]`）会被 Godot 的
> `get_string_from_utf8()` 在首个 NUL 处截断（实测 `decoded_len=1`），因此往返比对判为
> `invalid_utf8`。JSON 规范（RFC 8259 §7）禁止 JSON 文本中出现未转义的 NUL，所以
> 不存在「合法配置文件被误拒」；转义写法 `\u0000` 的 ASCII 字节正常解码（探针
> `escaped-nul error=null`）。这是错误码分类的边角，不是假阳性。

---

## Test Quality Audit

| Test File | Linked Req | Active | Skipped | Circular | Assertion Level | Verdict |
|-----------|-----------|--------|---------|----------|-----------------|---------|
| `mobile/tests/unit/test_geometry.gd` | RESIL-03 | 12 | 0 | 否 | Value（1e-9 逐向量） | PASS |
| `mobile/tests/unit/test_config_loader.gd` | RESIL-02 | 35 | 0 | 否 | Value/Behavioral（四种错误码逐个硬断言 + 真实配置 5 条） | PASS |
| `mobile/tests/unit/test_config_validator.gd` | RESIL-02 | 55 | 0 | 否 | Behavioral（每条规则的接受/拒绝/多错/warning） | PASS |
| `mobile/tests/unit/test_config_corpus.gd` | RESIL-02 | 16 | 0 | 否 | Behavioral（28 条语料逐条 + 规模下限） | PASS |
| `mobile/tests/unit/test_models.gd` | RESIL-02 | 41 | 0 | 否 | Value（逐字段默认值） | PASS |
| `mobile/tests/unit/test_vocabulary.gd` | RESIL-02 | 6 | 0 | 否 | Value（逐条别名/条目数） | PASS |
| `mobile/tests/unit/test_overlay_merge.gd` | DATA-03 | 33 | 0 | 否 | Behavioral（七条合并语义） | PASS |
| `mobile/tests/unit/test_config_store.gd` | DATA-03 | 52 | 0 | 否 | Behavioral（真实 I/O 坏/偏/半/旧） | PASS |

**Disabled tests on requirements:** 0（全局扫描 `skip/pending/todo` 零命中）
**Circular patterns detected:** 0（loader/corpus/parity 均不写夹具；黄金夹具由 Python 参考生成，provenance=VALID）
**Insufficient assertions:** 0（关键契约均为 value/behavioral 级）

---

## Decision Coverage

N/A — 本阶段没有 `*-CONTEXT.md`，无 `<decisions>` 块可校验。

---

## Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| RESIL-02 | 03-03 / 03-04 / 03-05 | 配置校验失败显示错误屏并给出可操作信息，而非 `push_error` 或静默降级 | ✓ SATISFIED | `ConfigError` 四要素 + `to_text()` 可渲染；66 处错误/warning 全带非空 `fix_hint`；lint 无日志；四种错误码（含本轮修复的 `invalid_utf8`）各有独立 code；语料两侧对等 |
| RESIL-03 | 03-01 | 核心代码可在无场景树、无手柄环境无头运行，由回放源驱动 | ✓ SATISFIED | `test-core.sh` exit 0 + 哨兵 576 断言；runner `extends SceneTree` |
| INFRA-03 | 03-02 | `mobile/src/core/` 架构 lint 禁止五类 token | ✓ SATISFIED | `LINT_OK files=15`；反例自测 54 项证明规则有牙齿 |
| DATA-03 | 03-06 | 用户数据写 `user://` 稀疏覆盖层，绝不修改 `res://` | ✓ SATISFIED | `user://` 双重守卫 + 原子写 + hash 过期丢弃 + 真实 I/O 测试 |

**Orphaned requirements:** 无。REQUIREMENTS.md 映射到 Phase 3 的 4 个 ID 全部出现在 PLAN frontmatter。

---

## Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `mobile/src/core/config/config_loader.gd` | 44-52 | 原 `invalid_utf8` 死分支 | ✅ 已修复 | 改为解码后字节往返比对（`text.to_utf8_buffer() != bytes`）；探针证实可达 |
| `mobile/tests/unit/test_config_loader.gd` | 89-98 | 原「二者之一」宽松断言 | ✅ 已修复 | 收紧为 `result.has_code(&"invalid_utf8")` 硬断言 |
| 多个 PLAN artifact 声明 | — | 3 个文件低于计划 `min_lines`（`direction_table.gd` 52/55、`rumble_config.gd` 16/18、`config_loader.gd` 82/90） | ℹ️ Info | 估算值与实现密度不符；逐文件阅读确认功能完整，不是 stub |
| 本阶段改动文件 | — | 无 `TBD` / `FIXME` / `XXX`；无 placeholder / TODO | ℹ️ Info | 债务标记门通过 |

---

## Human Verification

N/A — Infrastructure/foundation phase with no user-facing elements. 所有验收标准均由可执行测试、只读探针与 lint 覆盖；无 ⚠️ PRESENT_BEHAVIOR_UNVERIFIED truth，也没有 Plan 中延后的 `<human-check>` 项。

---

## Gaps Summary

无剩余缺口。

上一轮唯一 gap（T4-2）由提交 `f0e35d0` 关闭：

- `config_loader.gd` 不再依赖 `get_string_from_utf8()` 返回空串来判断编码错误，而是把解码结果 `to_utf8_buffer()` 与原始字节逐字节比较；任何非法序列 → `invalid_utf8`。
- `test_config_loader.gd` 把「`invalid_utf8` 或 `json_syntax_error` 二者之一」收紧为必须 `invalid_utf8`，并在注释里写明两者对用户的意义不同（编码问题 vs 括号问题）。
- 独立探针覆盖 7 种非法序列（含上一轮用过的 `[0xFF,0xFE,0x7B]`）全部命中 `invalid_utf8`；BOM / 空文件 / JSON 语法错误三种码与行号行为未回归；真实配置、中文、4 字节 emoji、CRLF、combining 字符、tabs 等合法 UTF-8 均未被误判。

回归证据：核心闸门 576 断言 0 失败、lint 反例 54 项、parity 28 例 4 分歧有记录、黄金 36 条一致、闸门 A `PACK_OK`+`GLYPH_OK`、桌面 230 项全通过。

---

_Verified: 2026-11-04T20:16:44Z_
_Verifier: gsd-verifier_
