---
phase: 05-judge-parity-decimation
plan: 06
subsystem: input-setup-and-profile-migration
tags:
  [
    gdscript,
    godot,
    left-stick,
    axis-mapping,
    calibration,
    schema-migration,
    mutation-testing,
    judge-parity,
  ]

requires:
  - phase: 05-judge-parity-decimation
    plan: 05
    provides: 252 条抽稀语料 / 基线哨兵 / 断言 44,792 与 22 套件
  - phase: 04
    provides: 单页输入设置 / RS 校准 / range_ready 保存门 / DeviceProfile schema v1

provides:
  - "`Calibration` 的四个 LS 字段（ls_center_x/y、ls_scale_x/y），缺失即 ConfigError"
  - "`AxisMapping._snapshot()` + `snapshot_ls()`：左右摇杆共用同一套归一化与死区"
  - "`InputSetup` 的 RS 轴对冻结（`rs_pair()` / `_rs_pair_frozen`）与 LS 轴对（`ls_pair()`）"
  - "`arm_ls_up()` / `arm_ls_right()` / `ls_ready()`：已知方向的符号确认 + 三条件就绪门"
  - "`build_profile()` 写入真实 LS 索引/符号/校准与 `quality.ls_ready`；RS 取冻结值"
  - "`DeviceProfile.SCHEMA_VERSION = 2` + `_ls_ready_marker()` + `has_ls()` 三道迁移门"
  - "`OnboardingFlow.build_profile()` 的档案自洽门（无 LS 探针 → 返回 null）"
  - "同一页的设置项：`Ls` 标签 + 三句 LS 提示 + `debug_line()` 的 rs=/ls=/ls_ready="

affects:
  [05-07-practice-wiring, phase-6-training-loop, phase-7-feedback, phase-9-release]

actuals:
  tokens: 14278
  tasks: 3
  commits: 3

plan_head_before: 88a9b7612d1c1f583aa2eb0f40d6142ef143db8c
plan_head_after: 47fbbaa

tech-stack:
  added: []
  patterns:
    - "左右摇杆同构：`_snapshot()` 是唯一变换实现，`snapshot_rs()` / `snapshot_ls()` 只做索引分派"
    - "RS 轴对先冻结、LS 再排除冻结对：归属不依赖推杆顺序（D5-1）"
    - "符号只由已知方向的位移确认；横向位移返回 sideways，绝不猜"
    - "保存时事实标记成对：`range_ready` 与 `ls_ready` 同层，缺一不可"
    - "schema 升版整份淘汰旧档案：解析层允许 ls=-1，使用层用 has_ls() 拒绝（分层各守一边）"

key-files:
  created:
    - .planning/phases/05-judge-parity-decimation/05-06-SUMMARY.md
  modified:
    - mobile/src/core/device/calibration.gd
    - mobile/src/core/device/axis_mapping.gd
    - mobile/src/core/device/device_profile.gd
    - mobile/src/core/input_setup.gd
    - mobile/src/core/onboarding_flow.gd
    - mobile/src/ui/input_setup_screen.gd
    - mobile/src/ui/input_setup_screen.tscn
    - mobile/tests/unit/test_device_profile.gd
    - mobile/tests/unit/test_input_setup.gd
    - mobile/tests/unit/test_onboarding_flow.gd
    - mobile/assets/fonts/required_glyphs.txt
    - mobile/assets/fonts/NotoSansSC-Subset.ttf

key-decisions:
  - "`_rs_pair_frozen` 在第一次推满 RANGE_READY 时冻结；手动 LB/RB 选择直接采信，自动识别才要求它是此刻 `_pair_score` 最高的一对 —— 否则人工路径可能永远冻不上"
  - "`ls_pair()` 用长窗口 span 排名、用最近窗口 `_pair_score > 0` 只做「真的动过」的过滤：两者混用会让用户停一拍就丢掉 LS"
  - "`_sweep_ls` 的所有调用点都排在两条 RS `_sweep` 之后；测试助手自身也先 RS 后 LS，把 D5-1 的顺序写进夹具而不是注释"
  - "`ls_ready` 只在轴对 + 两个符号 + 两轴量程三条同时成立时为 true；`can_save()` 与 `build_profile()` 双重拒绝"
  - "`OnboardingFlow` 没有 LS 探针，因此不再产出档案（返回 null），而不是产出「能加载但永远进不去练习」的档案"
  - "设置页仍是同一个 `.tscn`：15 → 16 个节点只多一个 `Ls`，静态断言 `SINGLE_PAGE nodes=16 added=Ls` 把它钉死"
  - "字形清单整文件扫描（含注释）导致 10 个新汉字（八冻升及宜末歧活涉臂）进入清单；按计划重新生成 1063 字符子集，不为过闸门改文案"

requirements-completed: [JUDGE-02, JUDGE-03]

coverage:
  - id: D1
    description: "Calibration 四个 LS 字段与 snapshot_ls：与 snapshot_rs 同输入同向量同角度（<1e-9），缺任一 LS 字段整份拒绝"
    requirement: JUDGE-02
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_device_profile.gd#_check_calibration_ls"
        status: pass
      - kind: integration
        ref: "bash mobile/tools/test-core.sh#TESTS_DONE failures=0"
        status: pass
    human_judgment: false
  - id: D2
    description: "InputSetup 的 RS 冻结 + LS 轴对/符号/量程/就绪门，D5-1 顺序下 rs=(2,3)、ls=(0,1)、档案 ls_ready=true"
    requirement: JUDGE-02
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_input_setup.gd#_check_rs_pair_frozen_before_ls"
        status: pass
      - kind: unit
        ref: "mobile/tests/unit/test_input_setup.gd#_check_ls_up_sign / _check_ls_right_sign / _check_ls_ready_gate"
        status: pass
      - kind: unit
        ref: "mobile/tests/unit/test_input_setup.gd#_check_build_profile_writes_ls / _check_reset_clears_ls"
        status: pass
    human_judgment: false
  - id: D3
    description: "schema v2 + ls_ready 迁移门：v1 档案 unsupported_schema 整份拒绝；缺 ls_ready 与 ls=-1 自相矛盾各一条拒绝面；OnboardingFlow 不再产出进不去练习的档案"
    requirement: JUDGE-02
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_device_profile.gd#_check_ls_migration / _check_reuse_gate"
        status: pass
      - kind: unit
        ref: "mobile/tests/unit/test_onboarding_flow.gd#_check_build_profile"
        status: pass
    human_judgment: false
  - id: D4
    description: "设置页仍是同一页：节点集合原 15 个 + Ls；三句 LS 提示存在；debug_line() 含 rs= / ls= / ls_sign= / ls_ready="
    requirement: JUDGE-02
    verification:
      - kind: integration
        ref: "python3 -c ... assert len(n)==16 ... → SINGLE_PAGE nodes=16 added=Ls"
        status: pass
      - kind: integration
        ref: "bash mobile/tools/gate-a.sh#GLYPH_OK chars=1063"
        status: pass
    human_judgment: false
  - id: D5
    description: "零回归：desktop 302/302、22 套件 / 44,867 断言 / failures=0、四条哨兵 55/29/12/252 全部 mismatches=0、LINT_OK"
    requirement: JUDGE-03
    verification:
      - kind: integration
        ref: "bash tools/check_desktop.sh#302 项检查全部通过"
        status: pass
      - kind: integration
        ref: "bash mobile/tools/test-core.sh#GESTURE_GOLDEN 55 / GESTURE_RUNTIME 29 / MEASURED 12 / DECIMATION 252"
        status: pass
      - kind: integration
        ref: "python3 tools/lint_core_purity.py mobile/src/core#LINT_OK files=33"
        status: pass
    human_judgment: false

duration: 26min
completed: 2026-11-06
status: complete
---

# Phase 5 Plan 06: 左摇杆三件套 + schema v2 迁移门 Summary

**左摇杆第一次拥有与右摇杆完全同构的校准、映射与识别：D5-1 顺序下 RS 轴对冻结在 (2,3)、LS 识别为 (0,1)、档案 `ls_ready=true`；schema 升到 v2 后旧档案被机械拒绝，四个 `relative_to_ls` 技能不再是「推了完全没反应」的静默失败。**

## Performance

- **Duration:** 26 min
- **Started:** 2026-11-05T22:20:59Z
- **Completed:** 2026-11-05T22:46:55Z
- **Tasks:** 3
- **Files:** 12 个唯一文件（3 任务提交，另加本 SUMMARY；含 1 个生成的字体子集）
- **Tokens（actuals）:** 14,278 = chars/4 over `git diff 88a9b76..47fbbaa`（57,113 字符）

## 基线（开工前实测）

| 命令 | 结果 |
|------|------|
| `bash mobile/tools/test-core.sh` | `TESTS_SUITES=22`、`TESTS_ASSERTIONS=44792`、`TESTS_DONE failures=0` |
| 四条哨兵 | `GESTURE_GOLDEN 55` / `GESTURE_RUNTIME 29` / `MEASURED 12` / `DECIMATION 252`，全部 `mismatches=0` |
| `bash tools/check_desktop.sh` | 302/302 |
| `shared/skills_config.json` | SHA-256 `039b2d72…1f10`（与 05-01 冻结值一致，本计划零改动） |

## Accomplishments

- **`Calibration` 的 LS 四字段**：`ls_center_x/y`、`ls_scale_x/y` 与 RS 同构；`to_dict` / `from_dict` 各八项，缺任一 LS 字段即 `ConfigError` + null —— 不给「默认校准」兜底。
- **`AxisMapping._snapshot()`**：把「两次 normalize → deadzone」抽成唯一实现；`snapshot_rs()` 与 `snapshot_ls()` 只做索引分派。同输入下向量距离与角度差 < 1e-9，符号不同也保持同构。
- **RS 轴对冻结**：`rs_pair()` 在第一次推满 `RANGE_READY` 时冻结；`ls_pair()` 在排除冻结对之后取长窗口 `min(span_x, span_y)` 最高且最近真的动过的一对。`active_pair()` 的最近性反转再也无法对调两只摇杆。
- **LS 符号只由已知方向确认**：`arm_ls_up()` / `arm_ls_right()` 记录基线，按位移方向定符号；向上推成左右时返回 `&"sideways"` 并明确提示，绝不静默把 X 的位移当成 Y。
- **`ls_ready()` / `can_save()` / `build_profile()`**：三个门同一套事实；档案写入真实 LS 索引/符号/`ls_center_*`/`ls_scale_*` 与 `quality.ls_ready`，RS 一律取冻结值。
- **schema v2**：`DeviceProfile.SCHEMA_VERSION = 2`；`can_enter_practice()` 追加 `has_ls()` 与 `_ls_ready_marker()`；v1 档案由 `from_dict` 报 `unsupported_schema` 整份拒绝。
- **`OnboardingFlow` 诚实化**：`build_profile()` 末尾用档案自己的 `can_enter_practice()` 自检；本流程无 LS 探针，因此返回 null，而不是发一份「能加载但永远进不去练习」的档案。
- **设置页仍是同一页**：节点 15 → 16 只多 `Ls`；`_process` 自动摆臂确认符号，位移回落 0.1 以下持续 0.25 s 重取基线（松手再推即可）；`debug_line()` 增加 `rs=` / `ls=` / `ls_sign=` / `ls_ready=`。
- **闸门现状**：22 套件 / **44,867** 断言 / `failures=0`、`GESTURE_GOLDEN 55`、`GESTURE_RUNTIME 29`、`MEASURED 12`、`DECIMATION 252/0`、`LINT_OK files=33`、desktop 302/302、`GLYPH_OK chars=1063`、`SINGLE_PAGE nodes=16 added=Ls`。

## 保存门与档案字段（D-06 的机械落点）

```text
can_save() = range_ready() and ls_ready()
ls_ready() = ls_pair() != NONE
           and has_ls_x_sign() and has_ls_y_sign()
           and span(ls.x) >= 1.2 and span(ls.y) >= 1.2
```

| 档案字段 | 来源 | 旧档案 |
|---|---|---|
| `axes.rs_x/rs_y` | `rs_pair()`（冻结值） | 同名，但 v1 被 schema 门拒绝 |
| `axes.ls_x/ls_y` | `ls_pair()` | 04 阶段写 -1；v1 整份拒绝 |
| `calibration.ls_*` | `pair_center/scale(ls_pair())` | v1 无此四字段 → `from_dict` 也会拒绝 |
| `quality.range_ready` | 保存时事实 | 04-11 已有 |
| `quality.ls_ready` | 保存时事实 | 缺失 → `can_enter_practice()` 拒绝 |

## 任务提交

1. **Task 1: Calibration 四个 LS 字段 + snapshot_ls 同构** — `69d9dd7` (feat)
2. **Task 2: InputSetup RS 冻结 + LS 轴对/符号/量程 + build_profile** — `ed52f55` (feat)
3. **Task 3: schema v2 + ls_ready 迁移门 + 设置页 LS 行 + 字体子集** — `47fbbaa` (feat)

**Plan metadata:** 本次 SUMMARY / STATE / ROADMAP 提交（docs: complete plan）

## Files Created/Modified

- `mobile/src/core/device/calibration.gd` — 四个 LS 字段；`to_dict`/`from_dict` 各八项，缺字段即拒绝
- `mobile/src/core/device/axis_mapping.gd` — 私有 `_snapshot()`；`snapshot_ls()` 与 `snapshot_rs()` 同构；注释明确解析层允许 ls=-1、使用层拒绝
- `mobile/src/core/device/device_profile.gd` — `SCHEMA_VERSION = 2`、`has_ls()`、`_ls_ready_marker()`、迁移代价文档
- `mobile/src/core/input_setup.gd` — RS 冻结、LS 轴对/符号/量程/就绪门、`pair_center/pair_scale`、`build_profile` 双摇杆写出
- `mobile/src/core/onboarding_flow.gd` — `build_profile()` 末尾的档案自洽门
- `mobile/src/ui/input_setup_screen.gd` — `Ls` 标签、三句提示、自动摆臂 + 松手重臂、`debug_line()` 扩展
- `mobile/src/ui/input_setup_screen.tscn` — 新增 `Ls`（15 → 16 节点），下方行距压缩到 720 高度内
- `mobile/tests/unit/test_device_profile.gd` — LS 校准/同构/缺字段、v1 拒绝、四条 v2 拒绝面、schema 常量往返、反例补齐
- `mobile/tests/unit/test_input_setup.gd` — D5-1 顺序、LS 排除 RS、向上/向右（含 sideways）、就绪门、档案写入、reset；五处旧夹具修好
- `mobile/tests/unit/test_onboarding_flow.gd` — `_profile()` 补 LS + ls_ready；`build_profile()` 改为断言 null
- `mobile/assets/fonts/required_glyphs.txt` — 992 → 1063 字符（新注释引入 10 个汉字）
- `mobile/assets/fonts/NotoSansSC-Subset.ttf` — 重新生成的子集

## Decisions Made

- **手动 LB/RB 选择直接冻结**：计划写「active_pair() 必须是 `_pair_score` 最高的一对」；若手动选中一对而另一对最近更热，按字面实现会永远冻不上、人工路径死锁。实现为「手动选择直接采信，自动识别才比最高分」，语义仍是「RS 是先被冻结的那一对」。
- **`ls_pair()` 混用两个窗口**：排名用长窗口 span（用户停一拍仍可信），过滤用最近窗口 `_pair_score > 0`（必须真的动过）。与 `ls_ready()` 的量程门配合，避免静止噪声凑成一对。
- **`_sweep_ls` 的顺序写进夹具**：助手先推满 0/1、再向上、再向右；所有调用点排在两条 RS `_sweep` 之后。计划里「若在 RS 冻结前调用会把 (0,1) 冻成 RS」不是理论风险 —— 变异 3 实测 `rs_pair()` 变成 `(0,1)`。
- **`_save_and_enter` 先判 `range_ready()` 再判 LS**：计划只要求在 `can_save()` 前加两个 LS 分支；若照字面把 LS 分支放在 RS 量程判断之前，RS 只推到一半的用户会看到「左摇杆还没推满」的错误提示。实现为 RS 量程 → LS 轴对 → LS 符号/量程的顺序。
- **字体清单按整文件扫描重新生成**：新增的三句提示本身只用既有字形，但新中文注释引入了「八冻升及宜末歧活涉臂」10 个字符。按计划重生成 1063 字符子集，不改文案规避闸门。

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - 假绿] `ConfigError` 的字段名写成 `path`，运行时错误吞掉半个 schema 套件**

- **Found during:** Task 3 第一次跑 `test-core.sh`
- **Issue:** 新增的反例断言遍历 `ConfigError` 并访问 `entry.path`；真实字段是 `json_path`。GDScript 的运行时错误只中止 `_check_profile_schema` 这一个函数，`run()` 继续走到 `r.complete()`，于是 `TESTS_DONE failures=0` 而后面十几条 schema 断言根本没执行 —— 这是一个「零失败」的假绿。
- **Fix:** 改为 `entry.json_path`，并在断言里同时检查 `invalid_scale` 与 `$.calibration.scale_x`，确保反例确实由 `scale_x = 0` 触发。
- **Files modified:** `mobile/tests/unit/test_device_profile.gd`
- **Verification:** 重跑后 `SCRIPT ERROR` 消失，断言数 44,866 → 44,867（被跳过的断言恢复执行）；`bad_calibration` 的 `scale_x=0` 路径有独立断言。
- **Committed in:** `47fbbaa`

**2. [Rule 2 - 关键路径] 手动选轴对时「最高分」条件会让冻结永不发生**

- **Found during:** Task 2 实现 `_maybe_freeze_rs_pair()`
- **Issue:** 计划要求 `active_pair()` 是此刻 `_pair_score` 最高的一对才冻结。LB/RB 手动选择会让 `active_pair()` 固定为用户选的那对；若另一对最近动得更多，冻结条件永远不成立，`rs_pair()` 一直跟着 `active_pair()`，后续 `build_profile()` 的 RS 归属重新变得依赖推杆顺序。
- **Fix:** `_manual_index >= 0` 时直接采信手动选择；自动识别仍要求最高分。冻结后的行为与计划完全一致。
- **Files modified:** `mobile/src/core/input_setup.gd`
- **Verification:** `_check_manual_cycle` 与 `_check_rs_pair_frozen_before_ls` 同时通过；变异 3 证明删除冻结会让 D5-1 用例变红。
- **Committed in:** `ed52f55`

**3. [Rule 1 - 夹具时序] `_check_ls_pair_excludes_rs` 的 3 帧 RS 推杆无法压过仍在窗口内的 LS 行程**

- **Found during:** Task 2 第一次跑套件
- **Issue:** 计划设想「再推一下 RS 让 active_pair 回到 (2,3)」，但 LS 的完整扫掠仍在最近 60 帧窗口里，`_pair_score` 是 2.0；3 帧 RS 推杆只有 1.0，`active_pair()` 仍是 LS。
- **Fix:** 先喂 61 帧静止让 LS 离开最近窗口（长窗口行程保留），再轻推 LS（0.4）与 RS（1.0），使 active_pair 合理翻回 RS，而 `ls_pair()` 仍能凭长窗口认出 (0,1)。
- **Files modified:** `mobile/tests/unit/test_input_setup.gd`
- **Verification:** 该用例通过；`ls_pair() != rs_pair()` 与 `== (0,1)` 两条断言同时成立。
- **Committed in:** `ed52f55`

**4. [Rule 2 - 提示正确性] A 的前置提示顺序必须 RS 量程优先于 LS**

- **Found during:** Task 3 实现 `_save_and_enter()`
- **Issue:** 计划字面要求在 `can_save()` 前插入两个 LS 分支；`can_save()` 同时覆盖 RS 与 LS，若直接插入，RS 量程只推到一半的用户会收到「左摇杆还没推满」的误导提示。
- **Fix:** 明确按「RS 轴对 → RS 量程 → LS 轴对 → LS 符号/量程」逐条提示，最后保留 `can_save()` 作为防御门。
- **Files modified:** `mobile/src/ui/input_setup_screen.gd`
- **Verification:** 设置页脚本语法经 `gate-a.sh` 逐文件检查通过；文案常量与 `test_onboarding_ui` 的既有断言不冲突。
- **Committed in:** `47fbbaa`

---

**Total deviations:** 4 auto-fixed（2 Rule 1、2 Rule 2）
**Impact on plan:** 第 1 条是最有价值的一次发现：它证明「零失败」并不等于「断言都跑了」，也解释了为什么 Task 3 的断言数只涨了 9 条。第 2、4 条是计划的字面实现会在真实路径上死锁或误导用户；第 3 条是夹具时序修正，不改生产行为。`desktop/`、`shared/skills_config.json` 与全部判定阈值零改动。

## 变异验证（D-10，红色行原文）

每次用 `/tmp` 备份 → 改一处 → 跑 `core_runner.gd` → 记录 `TESTS_FAIL` 原文 → 还原 → `grep -c MUTATION` 为 0 → 全量套件重新全绿。

### 变异 1：拿掉 `_ls_ready_marker()` 门（`return _ls_ready_marker()` → `return true`）

```text
TESTS_FAIL device_profile: v2 缺 quality.ls_ready → 不能进练习
TESTS_FAIL device_profile: 缺 quality.ls_ready → 拒绝
TESTS_DONE failures=2
```

还原后 `failures=0`。

### 变异 2：注释掉 `can_enter_practice()` 里的 `axes.has_ls()`

```text
TESTS_FAIL device_profile: ls = -1 但 ls_ready = true（自相矛盾）→ has_ls() 必须拦截
TESTS_FAIL device_profile: ls = -1 但 ls_ready = true（自相矛盾）→ 拒绝
TESTS_DONE failures=2
```

还原后 `failures=0`。

### 变异 3：注释掉 `observe()` 里的 `_maybe_freeze_rs_pair()`

```text
TESTS_FAIL input_setup: D5-1：先推 RS 再推 LS，rs_pair 必须冻结在 (2,3)（实际 (0, 1)）
TESTS_FAIL input_setup: D5-1：ls_pair 必须是排除冻结 RS 之后的 (0,1)（实际 (-1, -1)）
TESTS_FAIL input_setup: D5-1：轴对 + 两个符号 + 两轴量程齐备 → ls_ready
TESTS_FAIL input_setup: D5-1：保存门通过时必须能构造档案
TESTS_FAIL input_setup: RS 与 LS 量程都推满：can_save 为 true
TESTS_FAIL input_setup: 量程满了才允许返回档案
TESTS_FAIL input_setup: 前置：量程满了才能构造档案
TESTS_FAIL input_setup: 没调 mark_layout_confirmed 时档案不得写 layout_confirmed=true
TESTS_FAIL input_setup: 确认之后的档案 layout_confirmed 为 true
TESTS_FAIL input_setup: 档案布局取用户确认后的当前值（实际 null）
TESTS_FAIL input_setup: build_profile 必须返回档案
TESTS_FAIL input_setup: 向上推且 Y 轴读数为负 → ls_y_sign = +1（实际 1）
TESTS_DONE failures=12
```

关键行是第一条：没有冻结时 `rs_pair()` 实际返回 `(0, 1)` —— 正是 D5-1 会发生的 RS/LS 对调。还原后 `failures=0`。

## Issues Encountered

- **`ConfigError.path` 假绿**：见偏差 1。教训：GDScript 的运行时错误只中止当前函数，`r.complete()` 仍会执行；凡是新增「遍历错误对象」的断言，必须在修正后核对断言总数确实增长了。
- **退出码与假绿的其余防线正常**：`test-core.sh` 的 `TESTS_DONE` 哨兵在变异 1/2/3 中都报红；`TESTS_ASSERTIONS` 从 44,792 涨到 44,867，证明新增断言被执行。
- **Godot `--import` 本轮未撞 SIGSEGV**：Task 3 期间多次完整导入全部一次成功。
- **任务提交仍在 `main` 上**：`branching_strategy: none` + 顺序执行器（`SEQUENTIAL=true`），与 05-01~05 的提交线一致。

## Known Stubs

无。`_ls_manual_index` 是为将来人工选择 LS 轴对预留的字段（本阶段没有按键绑定、没有 UI 入口）；它不参与任何判定，也不产生「看起来有功能其实没有」的路径 —— 唯一的自动路径 `ls_pair()` 在没有手动值时必须凭观测数据成立。

## Threat Flags

无新增信任面。T-05-19 由 schema v2 + `has_ls()` + `_ls_ready_marker()` 三重门与变异 1/2 兜住；T-05-20 由 `ls_ready()` 的三条件与 `can_save()`/`build_profile()` 双重拒绝兜住；T-05-21 由 X/Y 独立确认 + `sideways` 明确回报兜住；T-05-21b 由 RS 冻结 + `ls_pair()` 排除冻结对 + `_check_rs_pair_frozen_before_ls` + 变异 3 兜住；T-05-22b 由 `OnboardingFlow.build_profile()` 的自洽门与测试断言兜住。`debug_line()` 只含轴号、符号、量程，不含设备名或 GUID。

## User Setup Required

None - 无外部服务、环境变量或真机步骤。真机 D5-0 / D5-1 走查仍按 `ACCEPTANCE.md`，本计划只交付无头证明。

## Next Phase Readiness

- **计划 07（练习接线）现在有可消费的 LS 入口**：`AxisMapping.snapshot_ls(raw, mapping, calibration, deadzone)` 是唯一接缝；`main.gd` 禁止再写一份「减中点除量程」。
- **档案升级是一次性代价**：`ProfileStore.load_all()` 对 v1 条目整份丢弃，用户需重走一次约 20 秒的设置页；这是刻意的，不能靠「猜测迁移」把旧档案恢复成 ls=-1 的半可用状态。
- **设置页的真机判据**：`INPUT_SETUP` 行出现 `rs=2/3`、`ls=0/1`、`ls_ready=1`；用户先推 RS 四方向、再向上推 LS、再向右推 LS、再推满 LS 四方向，A 才能保存。若 `ls_ready=0`，页面会明确说明缺哪一步。
- **闸门现状**：22 套件 / 44,867 断言 / `failures=0`、`GESTURE 55/29`、`MEASURED 12`、`DECIMATION 252/0`、`LINT_OK 33`、desktop 302/302、`GLYPH_OK 1063`、`SINGLE_PAGE nodes=16`。
- **无阻塞项**：`desktop/padskills/*.py` 与 `shared/skills_config.json` 零改动；`test_profile_store` 的外层文件 schema 是独立常量（1），不受 `DeviceProfile` 升版影响。

## Self-Check

- 计划内修改的 10 个源码/测试文件全部存在于工作树；Task 3 生成的字形清单与子集已提交。
- 三个任务提交均可在 `git log` 中定位：`69d9dd7` / `ed52f55` / `47fbbaa`。
- 测得提交数：`git rev-list --count 88a9b76..47fbbaa` = 3。
- `git status --porcelain -- desktop shared/skills_config.json` 为空；`shared/skills_config.json` SHA-256 仍为 `039b2d72…1f10`。
- 最终闸门：`bash mobile/tools/test-core.sh` 22 套件 / 44,867 断言 / `failures=0`；`bash tools/check_desktop.sh` 302/302；`bash mobile/tools/gate-a.sh` `GLYPH_OK chars=1063`；`python3 tools/lint_core_purity.py mobile/src/core` `LINT_OK files=33`。

## Self-Check: PASSED
