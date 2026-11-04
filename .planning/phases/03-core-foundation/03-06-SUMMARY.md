---
phase: 03-core-foundation
plan: 06
subsystem: core
tags: [gdscript, user-data, overlay, config-store, atomic-write, sha256, sparse-merge, data-03]

requires:
  - phase: 03-core-foundation
    plan: 01
    provides: 无头 runner、`TESTS_DONE failures=0` 完成哨兵、`test-core.sh` 唯一入口
  - phase: 03-core-foundation
    plan: 02
    provides: `lint_core_purity.py` 的 14 条架构规则与 `CORE.md` 的零 I/O 边界
  - phase: 03-core-foundation
    plan: 04
    provides: `ConfigLoader.decode_bytes`（原始字典）、`ConfigValidator.validate`、`ConfigResult` / `ConfigError`
  - phase: 03-core-foundation
    plan: 05
    provides: 28 条跨语言语料与两端判定对等；本计划不新增错误码
  - phase: 02-android-toolchain
    provides: Godot 4.7.2 与 `*.gd.uid` 提交约定

provides:
  - "mobile/src/core/config/overlay_result.gd：data / warnings / applied / discarded_reason / notice + `_discard()`"
  - "mobile/src/core/config/overlay_merge.gd：schema_version / base_sha256 / 三个白名单键的纯合并与整体丢弃语义"
  - "mobile/src/app/config_store.gd：唯一允许 FileAccess/DirAccess 的配置入口；bytes 读、base sha256、覆盖层合并、temp+flush+close+rename 原子写"
  - "mobile/tests/unit/test_overlay_merge.gd：七条语义逐条断言 + base 前后快照 + 用户可见 notice 原文"
  - "mobile/tests/unit/test_config_store.gd：真实 I/O 矩阵（写→读→合并、首启安静、res:// 守卫、原子写、坏/超大/过期/结构错覆盖层、base 失败、warning 抵达 ConfigResult）"
  - "mobile/project.godot：`config/use_custom_user_dir=true` + `config/custom_user_dir_name=\"FifaSkillTrainer\"`"
  - "mobile/tests/core_runner.gd：SUITES 扩到 8 条（新增 config_store / overlay_merge）"

affects: [phase-4-input, phase-7-feedback, phase-8-stats, phase-9-upgrade]

actuals:
  tokens: 9102
  tasks: 3
  commits: 3

plan_head_before: 04c00313650a1903ad4ee19c1ac55175074e699f
plan_head_after: 45a164685c173a78808fd7f4329e234a93712f17

tech-stack:
  added: []
  patterns:
    - "稀疏覆盖层：只允许 enabled / required_button / button_mode，以 skill name 为键，params 阈值永远不进覆盖层"
    - "整体丢弃：schema 缺失/过新、base 摘要变化、skills 非对象一律回退 base + 一句 notice，不做部分保留"
    - "原子写：临时文件 → flush → close → 改名；失败清理临时文件，成功后 `.tmp` 必须消失"
    - "I/O 与纯语义分界：core 只吃 Dictionary / PackedByteArray，FileAccess/DirAccess 只出现在 src/app/config_store.gd"
    - "warning 必须转交：`ConfigResult.warnings.append_array(merged.warnings)`，纯合并绿不等于生产路径看得到"

key-files:
  created:
    - mobile/src/core/config/overlay_result.gd
    - mobile/src/core/config/overlay_result.gd.uid
    - mobile/src/core/config/overlay_merge.gd
    - mobile/src/core/config/overlay_merge.gd.uid
    - mobile/src/app/config_store.gd
    - mobile/src/app/config_store.gd.uid
    - mobile/tests/unit/test_overlay_merge.gd
    - mobile/tests/unit/test_overlay_merge.gd.uid
    - mobile/tests/unit/test_config_store.gd
    - mobile/tests/unit/test_config_store.gd.uid
  modified:
    - mobile/project.godot
    - mobile/tests/core_runner.gd

key-decisions:
  - "`user://` 目录名在本计划一次定死（`FifaSkillTrainer`）：必须早于任何用户数据存在，发布后再改等于丢数据，Phase 9 覆盖安装依赖它不变"
  - "覆盖层用 skill name 而不是数组下标作键：base 重排不会把覆盖改到另一个动作上；params 阈值永不允许覆盖（历史数据可比性）"
  - "base 摘要取当前 base 文件字节（`FileAccess.get_sha256`），不读可能过期或被手改的 `.sha256` 边车"
  - "整体丢弃不部分保留：schema/hash 问题一律回退 base + notice + 删除覆盖层，只打扰一次"
  - "未知动作名与未知键只记 warning 并忽略该条，其余合法条目照常生效"
  - "读文件先取长度再分配缓冲（`get_buffer(length)`）：超限文件在内存分配之前被拒绝；仍然是 bytes 读，BOM 不会被剥掉"
  - "测试使用注入路径 `user://config/test_overrides.json`，默认路径只断言前缀、绝不读写真实用户数据"
  - "base 目标名写死为 `res://assets/config/skills_config.json`；`OVERRIDES_DIR` 常量保留为目录语义说明，实际写入用常量路径 + `.tmp` 后缀"

patterns-established:
  - "Pattern 1：两文件分工 —— `overlay_merge.gd` 是纯语义（可回放驱动），`config_store.gd` 是唯一 I/O 适配器"
  - "Pattern 2：丢弃即删除 —— 覆盖层被整体作废后立刻 `remove_absolute`，用户只被同一条提示打扰一次"
  - "Pattern 3：失败必须可恢复 —— 坏 JSON / 超大 / 结构错 / 过期 hash 都回退到可用 base，`ok()` 仍为真"
  - "Pattern 4：守卫做在入口 —— `save_overrides` 首句检查目标与临时路径都以 `user://` 开头，res:// 与绝对路径都返回 `ERR_UNAUTHORIZED` 且零文件副作用"

requirements-completed: [DATA-03]

coverage:
  - id: D1
    description: "用户改的动作开关写入 `user://` 覆盖层，重启后读回并合并生效；未被覆盖的四条动作保持原值，动作总数不变"
    requirement: DATA-03
    verification:
      - kind: integration
        ref: "mobile/tests/unit/test_config_store.gd#_check_write_read_merge（save_overrides → load_config → overrides_applied / enabled=false / skills.size()==5）"
        status: pass
    human_judgment: false
  - id: D2
    description: "覆盖层稀疏语义七条：合法稀疏、缺 schema、schema 过新、base hash 不匹配、摘要大小写、未知动作、未知键；base 入参前后逐字不变"
    requirement: DATA-03
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_overlay_merge.gd（TESTS_ASSERTIONS 内 39 条断言；JSON.stringify 前后快照）"
        status: pass
    human_judgment: false
  - id: D3
    description: "运行期绝不写 `res://`：`save_overrides` 对 res:// 目标返回 `ERR_UNAUTHORIZED` 且不建文件/目录；默认覆盖层路径以 `user://` 开头"
    requirement: DATA-03
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_config_store.gd#_check_res_guard + _check_default_path（FileAccess.file_exists / DirAccess.dir_exists_absolute 均为假）"
        status: pass
    human_judgment: false
  - id: D4
    description: "写盘原子且失败可恢复：成功后无 `.tmp` 残留、预置 `.tmp` 被改名覆盖；坏 JSON / 超大 / skills 非对象 / 过期 hash 都回退 base + 中文 notice 并删除覆盖层；base 缺失/超限返回结构化错误"
    requirement: DATA-03
    verification:
      - kind: integration
        ref: "mobile/tests/unit/test_config_store.gd#_check_atomic_write / _check_broken_overlay / _check_too_large_overlay / _check_overlay_schema_invalid / _check_stale_hash / _check_base_failures"
        status: pass
    human_judgment: false
  - id: D5
    description: "未知动作 / 未知键的 warning 经 `load_config()` 抵达 `ConfigResult.warnings`，且未知键 params 未写入合并后的配置"
    requirement: DATA-03
    verification:
      - kind: integration
        ref: "mobile/tests/unit/test_config_store.gd#_check_warnings_reach_result（warnings.size()==2，两个 code，params 无 min_angle）"
        status: pass
    human_judgment: false
  - id: D6
    description: "`user://` 目录名在任何用户数据产生之前定死为 `FifaSkillTrainer`；core 仍然零 I/O（lint 15 个文件干净）"
    requirement: DATA-03
    verification:
      - kind: integration
        ref: "mobile/project.godot（use_custom_user_dir=true / custom_user_dir_name=\"FifaSkillTrainer\"）+ bash mobile/tools/test-core.sh（LINT_OK files=15）"
        status: pass
    human_judgment: false

duration: 3min
completed: 2026-11-05
status: complete
---

# Phase 3 Plan 06: `user://` 稀疏覆盖层 + ConfigStore Summary

**用户改的开关写进 `user://config/overrides.json` 并读回生效，base 摘要一变就整体丢弃且只提示一次；写盘走临时文件 + flush + close + 改名，坏/超大/结构错/过期四种覆盖层都回退到可用 base，core 里没有一行文件 I/O**

## Performance

- **Duration:** 3 min
- **Started:** 2026-11-04T20:00:43Z
- **Completed:** 2026-11-04T20:03:20Z
- **Tasks:** 3
- **Files modified:** 12（10 新建、2 修改）

## Accomplishments

- `project.godot` 在任何用户数据产生之前把 `user://` 目录名定死为 `FifaSkillTrainer`（`config/use_custom_user_dir=true`）。注释写明发布后再改等于丢数据、Phase 9 覆盖安装依赖它不变；中文 `config/name` 保持为应用显示名。
- `OverlayMerge` 是纯语义：深拷贝 base，按 `schema_version` → `base_sha256` → `skills` 顺序判定，整体丢弃时返回 base + notice，不合并不猜；只应用 `enabled` / `required_button` / `button_mode`，以 skill name 索引，`params` 阈值永远进不来。
- `ConfigStore` 是唯一 I/O 入口：base 与覆盖层都按字节读，base 摘要取当前文件（不读 `.sha256` 边车），覆盖层丢弃时立刻 `remove_absolute` 删除；写入走 `temp → flush → close → rename_absolute`，rename 失败清理临时文件。
- 首启没有覆盖层是安静的：不创建空文件、不报错、`notice` 为空；只有用户第一次改设置才有写盘动作。
- 生产路径的 warning 不再丢失：`load_config` 把 `merged.warnings` 追加到 `ConfigResult.warnings`，未知动作 / 未知键经真实入口抵达调用方；`test_config_store` 的专用用例用 `load_config()` 而不是直接调 `OverlayMerge.merge` 来证明这一点。
- 全套门槛保持绿：`test-core.sh` → `TESTS_SUITES=8` / `TESTS_ASSERTIONS=575` / `TESTS_DONE failures=0`；`LINT_OK files=15`；`PARITY_OK cases=28 divergences=4`；`check_desktop.sh` → 230 项全绿。

## Task Commits

1. **Task 1: 写一次 → 读回来 → 合并生效；`user://` 目录名同时定死** — `d6af97e` (feat)
2. **Task 2: 覆盖层七条合并语义逐条钉死** — `8d8e4d6` (test)
3. **Task 3: 写坏、写偏、写一半、写旧四条路径都可恢复** — `45a1646` (fix)

**Plan metadata:** 见本次最终 docs 提交（SUMMARY / STATE / ROADMAP / REQUIREMENTS）

## Files Created/Modified

- `mobile/src/core/config/overlay_result.gd` — `data` / `warnings` / `applied` / `discarded_reason` / `notice` + `_discard()` 链式早退
- `mobile/src/core/config/overlay_merge.gd` — `SCHEMA_VERSION=1`、三个白名单键、base 深拷贝、按 name 索引、未知项 warning
- `mobile/src/app/config_store.gd` — bytes 读（先取长度）、`get_sha256`、覆盖层合并与删除、`ERR_UNAUTHORIZED` 守卫、原子写
- `mobile/tests/unit/test_overlay_merge.gd` — 七条语义 + base 快照 + notice 原文 + 白名单单键循环
- `mobile/tests/unit/test_config_store.gd` — 写读合并、首启安静、res:// 守卫、原子写、坏/超大/结构错/过期、base 失败、warning 转交
- `mobile/tests/core_runner.gd` — `SUITES` 增至 8 条（`config_store`、`overlay_merge`）
- `mobile/project.godot` — `use_custom_user_dir` / `custom_user_dir_name` 两行与不可再改注释
- 对应 `.gd.uid` — Godot 4.7.2 导入生成的边车，按既有约定提交

## Decisions Made

- **`user://` 目录名一次定死**：`FifaSkillTrainer` 是 ASCII、无空格；这是 Phase 9 覆盖安装不丢数据的前提，必须早于任何用户数据存在。Android 沙箱路径是否受该设置影响未真机验证（与 RESEARCH A1 一致，留给 Phase 4）。
- **覆盖层按 skill name 索引而不是数组下标**：base 重排不会让自定义设置改到另一个动作；skill name 已被校验为唯一。
- **`params` 阈值永不允许覆盖**：改阈值会让历史统计不可比，直接违反 PROJECT.md 的反目标；未知键变 warning 并忽略，不尝试「聪明地」合并。
- **整体丢弃不做部分保留**：schema 缺失/过新、摘要变化、`skills` 非对象都回退完整 base；半套语义比没有语义更难查。
- **摘要比较忽略大小写**：JSON 里手写大写 hex 不应被误判为「配置已更新」。
- **读文件先取长度再分配**：超过 1 MiB 的文件在内存分配之前被拒绝；仍然按字节读，BOM 不会像 `get_file_as_string()` 那样被静默剥掉。
- **测试只碰注入路径**：`user://config/test_overrides.json` 与 `user://config/test_base_*.json`；默认路径只断言前缀，避免污染真实用户数据。

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - 防御性读] `_read_bytes` 改为先取长度再读，而非 `get_file_as_bytes` 后判大小**

- **Found during:** Task 3 补失败路径
- **Issue:** 计划的 `<action>` 写「`FileAccess.get_file_as_bytes` 读，超过 `MAX_BYTES` → `file_too_large`」。这个顺序会先把整个超大文件读进内存再拒绝，1 MiB 上限对畸形/恶意输入并不构成真正的防线（T-03-24 相邻风险）。
- **Fix:** 用 `FileAccess.open` + `get_length()` 先判上限，再 `get_buffer(length)`；空文件仍走 `decode_bytes` 的 `file_empty`，读失败与空文件不再混淆。仍然坚持 bytes 读（BOM 检测前提不变）。
- **Files modified:** mobile/src/app/config_store.gd
- **Verification:** `TESTS_DONE failures=0`；新增 base 超限用例断言 `file_too_large` 且不产出半个配置。
- **Committed in:** `45a1646`（Task 3 提交）

**2. [Rule 1 - 计划内数字过期] 最终 `TESTS_SUITES=7` 与实际 8 条套件不一致**

- **Found during:** Task 2 注册 `overlay_merge`
- **Issue:** Task 1 新增 `config_store` 后是 7 条（Task 1 acceptance 要求 `TESTS_SUITES=7`）；Task 2 再注册 `overlay_merge` 后必然是 8 条。计划末尾 `<verification>` 仍写 7，是 Task 2 之前的快照。
- **Fix:** 保留 Task 1 的 7 条断言不动；最终门槛按实际 8 条验收，未删减任何套件来凑数字。
- **Files modified:** mobile/tests/core_runner.gd
- **Verification:** `TESTS_SUITES=8` / `TESTS_ASSERTIONS=575` / `TESTS_DONE failures=0`。
- **Committed in:** `8d8e4d6`（Task 2 提交）

**3. [Rule 2 - 任务边界] Task 1 提前实现了 Task 3 的防御与失败用例**

- **Found during:** Task 1 编写 `ConfigStore`
- **Issue:** Task 1 的 `<action>` 已要求完整 `save_overrides`（含 `ERR_UNAUTHORIZED`、flush/close/rename）与 `load_config` 的三条 notice；把它们拆成「先写不防御版本、Task 3 再补」会故意留下已知不安全实现，且 Task 1 acceptance 的 `flush()`/`remove_absolute`/`merged.warnings` 断言本来就检查这些行。
- **Fix:** Task 1 一次性实现完整安全属性与主要失败用例；Task 3 追加 base 缺失/超限、`skills` 非对象两条结构失败用例，并完成「先取长度再读」的加固。提交仍按任务拆分，Task 3 的 diff 是真实的增量。
- **Files modified:** mobile/src/app/config_store.gd、mobile/tests/unit/test_config_store.gd
- **Verification:** 三个提交分别独立通过 `test-core.sh`；最终 `TESTS_DONE failures=0`。
- **Committed in:** `d6af97e` + `45a1646`

---

**Total deviations:** 3 auto-fixed（1 处防御顺序修正、1 处计划数字过期、1 处任务边界前移）
**Impact on plan:** 无功能削弱。读顺序改为「先量后读」只加强上限；套件从 7 增到 8 是 Task 2 的正常增量；Task 1 提前实现的安全属性全部有行为断言，Task 3 仍交付独立增量。

## Issues Encountered

- 本机没有 `gsd_run` 命令，STATE.md / ROADMAP.md / REQUIREMENTS.md 按 `state advance-plan` / `update-progress` / `record-metric` / `requirements mark-complete` 的语义手工更新（与 03-04、03-05 相同）。
- Godot 输出里的 `Unicode parsing error ... (ff/fe)` 是 `test_config_loader.gd` 故意注入非法 UTF-8 字节的预期噪声，不是本计划失败。
- 本计划只在 macOS 实测 `rename_absolute` 覆盖与 `user://` 路径；Android 真机的原子改名与沙箱路径确认留给 Phase 4（RESEARCH A1/A4，与本计划探针结论一致）。

## User Setup Required

None — 无外部服务或环境变量；Godot 4.7.2 已在 Phase 2 安装并校验。`user://` 目录由引擎自动创建，首次写覆盖层时才会真正出现文件。

## Next Phase Readiness

- Phase 4 可以直接构造 `ConfigStore.new()` 并调用 `load_config()` 拿 `AppConfig`；覆盖层写入接口是 `save_overrides(Dictionary)`，返回 `Error`。
- Phase 7 的错误屏可以原样渲染 `ConfigResult.notice` 与 `to_text()`；被丢弃的覆盖层已经删除，不需要额外的「恢复默认」清理。
- Phase 8 的统计持久化可以复用本计划的 `user://` 路径约定与 temp + flush + close + rename 形状；不要另造写盘方式。
- Phase 9 覆盖安装不得更改 `config/custom_user_dir_name`；`project.godot` 里的注释就是给那一次升级的提醒。
- 新增覆盖层可写键时必须同时改三处：`OverlayMerge.ALLOWED_KEYS`、未知键 warning 文案、`test_overlay_merge` 的白名单循环；只改一处会让「未知键被挡住」变成一句空话。

## Known Stubs

None.

## Threat Flags

None — 本计划未引入威胁模型之外的新表面。T-03-23（写 `res://`）由 `ERR_UNAUTHORIZED` 与零副作用断言缓解；T-03-24（任意键篡改）由三键白名单 + 合并后完整校验缓解；T-03-25（非原子写）由 temp + flush + close + rename 与 `.tmp` 断言缓解；T-03-26（旧覆盖层继续生效）由 `get_sha256` 当前字节 + 整体丢弃 + 删除文件缓解；T-03-27（目录名变更丢数据）由 `project.godot` 注释与 Phase 9 复核约定缓解；T-03-SC 无包管理器安装。

## Self-Check: PASSED

- 12 个交付文件全部存在（3 个实现 + 3 个 `.uid` + 2 套件 + 2 个套件 `.uid` + `project.godot` + `core_runner.gd`）。
- 3 个提交 `d6af97e` / `8d8e4d6` / `45a1646` 均为 HEAD 祖先；`plan_head_before..HEAD` 实测 3 个提交，与 `actuals.commits` 一致。
- `bash mobile/tools/test-core.sh`（`TESTS_SUITES=8` / `TESTS_ASSERTIONS=575` / `TESTS_DONE failures=0`、`LINT_OK files=15`、`PARITY_OK cases=28 divergences=4`）与 `bash tools/check_desktop.sh`（230 项）在本次执行中通过。
- `grep -c 'use_custom_user_dir=true'` = 1；`grep -c 'custom_user_dir_name="FifaSkillTrainer"'` = 1；`flush()` 行号 97 < `close()` 98 < `rename_absolute` 99；`remove_absolute` 2 处；`merged.warnings` 1 处。
- `res://` 目标写入实测返回 `ERR_UNAUTHORIZED`，`res://config` 目录未被创建。
