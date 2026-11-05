---
phase: 04-device-input-green-slice
plan: 03
subsystem: core-device
tags: [gdscript, godot, axis-probe, calibration, device-profile, reuse-gate, pure-core]

requires:
  - phase: 04-device-input-green-slice
    plan: 02
    provides: 无头套件注册约定、`TESTS_DONE failures=0` 哨兵、`ConfigError` 收集式校验风格
  - phase: 03-core-foundation
    plan: 03
    provides: `ConfigError`（json_path / code / message / fix_hint）与「先 typeof 后转换」的校验惯例
  - phase: 03-core-foundation
    plan: 02
    provides: `lint_core_purity.py` 的零引擎依赖边界与 `LINT_OK files=N` 正向哨兵
  - phase: 04-device-input-green-slice
    plan: 01
    provides: 无头 runner、套件完成标记、`test-core.sh` 唯一入口
  - phase: 02-android-toolchain
    provides: Godot 4.7.2-stable 与 `*.gd.uid` 提交约定

provides:
  - "mobile/src/core/device/probe_evaluator.gd：`ProbeEvaluator` —— 中位数静止基线、四步窗口评估（有符号 delta / margin / separation）、三条交叉校验、唯一的 `low_separation` warning、`mapping_from_steps`"
  - "mobile/src/core/device/axis_mapping.gd：`AxisMapping` —— 索引与符号分开存、`raw_rs` 不乘符号、`snapshot_rs` 是 raw → 归一化 → 死区的唯一入口、to_dict/from_dict"
  - "mobile/src/core/device/calibration.gd：`Calibration` —— normalize（先减中点→再除量程→最后乘符号）、死区逐字移植（长度 ≤ 1.0）、中点/量程统计与坏样本拒绝"
  - "mobile/src/core/device/device_profile.gd：`DeviceProfile` —— schema_version / profile_id / key / axes / calibration / quality / layout / layout_confirmed / button_index_ok / probed_at_iso，`can_reuse` 四项复用门，`suggest_layout`，非法即整份丢弃"
  - "mobile/tests/unit/test_device_profile.gd：10 个 `_check_*`、157 条断言，含 evaluate_step → validate_cross 直连与 raw → 0/90/180/270 接缝"
  - "mobile/tests/core_runner.gd：SUITES 增至 11（新增 device_profile）"

affects: [04-04-pad-sampler-profile-store, 04-05-onboarding-flow, 04-07-device-checklist, phase-5-detectors]

actuals:
  tokens: 16187
  tasks: 2
  commits: 3

plan_head_before: 3836641e4ad0f942e033f0252c04ea2a8005a5d9
plan_head_after: 89f56a80e3c12e501739719f0fd00b91df680dd7

tech-stack:
  added: []
  patterns:
    - "索引与符号分成两个字段：-1 既是合法符号又是未映射哨兵，合并后无法区分"
    - "校准在原始轴空间测量，符号只在归一化的最后一步施加；raw_rs 不乘符号"
    - "探针的 rs_y 只能来自「向下」步，禁止用「向上取反」隐式推导"
    - "evaluate_step 返回有符号 delta；validate_cross 只消费 axis/sign/separation，两边不各写一份键名"
    - "schema 校验先 typeof 再转换，JSON 整数解析成 float，数值字段同时接受 TYPE_INT/TYPE_FLOAT"
    - "任一字段非法 → 整份丢弃（null + ConfigError），绝不部分恢复"
    - "复用门只比四个 index+sign；校准与 rest 不参与，同名不同映射必被拒"

key-files:
  created:
    - mobile/src/core/device/probe_evaluator.gd
    - mobile/src/core/device/probe_evaluator.gd.uid
    - mobile/src/core/device/axis_mapping.gd
    - mobile/src/core/device/axis_mapping.gd.uid
    - mobile/src/core/device/calibration.gd
    - mobile/src/core/device/calibration.gd.uid
    - mobile/src/core/device/device_profile.gd
    - mobile/src/core/device/device_profile.gd.uid
    - mobile/tests/unit/test_device_profile.gd
    - mobile/tests/unit/test_device_profile.gd.uid
  modified:
    - mobile/tests/core_runner.gd

key-decisions:
  - "死区逐字移植 desktop 的 `_deadzone`：`scaled = minf(1.0, …)` 把长度封顶在 1.0，斜向 (1,1) 返回 (0.7071, 0.7071)，不是 1.41"
  - "归一化顺序写死为「先减中点 → 再除量程 → 最后乘符号」；中点 0.02 的样本必须精确归零，顺序写反会得到 ±0.04"
  - "probe 的 delta 返回有符号值，sign 由它导出；validate_cross 只读 axis/sign/separation，不重算"
  - "`low_separation` 是唯一 warning 且必须可达：赢家 1.0 / 第二名 0.4 → margin 0.6 通过评估、separation 2.5 命中 warning"
  - "rs_y 只来自 down 步：接线反了要在探针阶段被交叉校验抓住，而不是在判定里表现成 180° 偏差"
  - "复用门只比较四个 index+sign；校准 center/scale 与探针 rest 不参与，复用时整份采用档案校准"
  - "`from_dict` 任一字段非法即返回 null + ConfigError；不做部分恢复、不静默补默认值"
  - "`profile_id` 固定 \"primary\" 但字段与序列化必须存在（INPUT-03 预留）"
  - "`suggest_layout` 认不出返回空：调用方必须让用户二选一，绝不预选"
  - "不存设备序号：`get_connected_joypads()` 顺序重启后不保证一致"

patterns-established:
  - "探针 → 映射 → 校准 → 档案是一条纯计算链，四步全部可在无头环境用合成 raw 驱动"
  - "负例断言必须带具体 code（not_enough_samples / not_enough_travel / ambiguous_axes / same_axis_up_right / vertical_not_opposed / horizontal_not_opposed），含糊的「重试」不可接受"
  - "schema 负例逐项破坏并断言 null + code/fix_hint 非空；整份丢弃是唯一恢复策略"
  - "端到端接缝断言：合成 raw 上/右/下/左经 snapshot_rs 得到 0/90/180/270，geometry.gd 一行不改"

requirements-completed: []

# INPUT-02 / INPUT-03 / INPUT-04 在本计划**不宣布完成**：
# - INPUT-02：本计划证明「轴序号完全由探针决定」在纯逻辑层成立；`mobile/src/` 无轴枚举常量的
#   机械 grep 与真实设备枚举在 04-04 / 04-07。
# - INPUT-03：本计划证明中点/满量程数学、坏样本拒绝、profile_id 预留与整份丢弃策略；
#   「首次使用能走完校准」的真机确认在 04-07。
# - INPUT-04：本计划只交出布局建议纯函数与「匹配不到就返回空」；按键确认页与状态机在 04-05。

coverage:
  - id: D1
    description: "四步探针：合成 raw 的 (index, sign) 与手推方向一致；上/右不同轴、上下反号、左右反号；rs_x 来自 right、rs_y 来自 down"
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_device_profile.gd#_check_probe_four_steps"
        status: pass
    human_judgment: false
  - id: D2
    description: "拒绝原因具体可达：samples<3 → not_enough_samples、|delta|=0.3 → not_enough_travel、两轴 0.8/0.75 → ambiguous_axes；三种交叉失配各有 code；low_separation warning 可达且不阻止继续"
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_device_profile.gd#_check_probe_rejections"
        status: pass
    human_judgment: false
  - id: D3
    description: "evaluate_step 的真实返回直接喂 validate_cross 可通过；把 down 换成 up 得 vertical_not_opposed —— 证明两侧消费同一套键名"
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_device_profile.gd#_check_evaluate_feeds_cross"
        status: pass
    human_judgment: false
  - id: D4
    description: "校准：中位数抗尖峰（均值被拉偏）、14 帧拒绝、峰峰值 0.30 → hand_on_stick、中心 0.40 只警告、某轴量程 0.4 → scale_too_small、最大位移 0.4 → range_short、量程 1.2 夹到 1.0 并警告"
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_device_profile.gd#_check_calibration"
        status: pass
    human_judgment: false
  - id: D5
    description: "归一化顺序与死区：中点 0.02 精确归零；0.52/0.02/1.0 → 0.5；死区保持角度、输出长度 = scaled ≤ 1.0，斜向 (1,1) 长度恰为 1.0"
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_device_profile.gd#_check_normalize_order / _check_deadzone"
        status: pass
    human_judgment: false
  - id: D6
    description: "档案 schema：合法档案往返逐字段相等（含 profile_id）；缺 schema_version / 版本 2 / key 空 / profile_id 空 / rs index 8 / sign 0 / scale 0 / layout_confirmed 字符串 / 根是数组 全部 null + ConfigError（含 code 与 fix_hint）"
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_device_profile.gd#_check_profile_schema"
        status: pass
    human_judgment: false
  - id: D7
    description: "复用门：四值相等才 true；rs_x_sign / rs_x_index / rs_y_index / rs_y_sign 各一条反例；axes=null → false；校准完全不同仍 true"
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_device_profile.gd#_check_reuse_gate"
        status: pass
    human_judgment: false
  - id: D8
    description: "端到端接缝：合成 raw 上/右/下/左经 snapshot_rs 得到 0/90/180/270（±1e-6）；raw_rs 不乘符号"
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_device_profile.gd#_check_angle_seam"
        status: pass
    human_judgment: false
  - id: D9
    description: "布局建议只按小写设备名：Xbox* → xbox；DualSense/DualShock/Wireless Controller/PS4/PS5 → playstation；空与未知 → 空（不预选）"
    verification:
      - kind: unit
        ref: "mobile/tests/unit/test_device_profile.gd#_check_suggest_layout"
        status: pass
    human_judgment: false
  - id: D10
    description: "零引擎依赖：新增四个 core 文件全部通过 lint；测试套件 11 / 断言 965 / failures=0；gate-a 与桌面 230 项保持绿"
    verification:
      - kind: integration
        ref: "python3 tools/lint_core_purity.py mobile/src/core → LINT_OK files=26；bash mobile/tools/test-core.sh → TESTS_SUITES=11 / TESTS_ASSERTIONS=965 / TESTS_DONE failures=0"
        status: pass
    human_judgment: false

duration: 22min
completed: 2026-11-05
status: complete
---

# Phase 4 Plan 03: 轴探针 + 校准 + DeviceProfile + 复用门 Summary

**「不硬编码轴序号」从约定变成结构：合成 raw 经探针得到 (index, sign)，经 snapshot_rs 精确落到 0/90/180/270；档案任何一项非法即整份丢弃，同名不同映射的复用门返回 false，而这一切都在没有手柄、没有时钟、没有文件系统的无头环境里被 157 条断言钉死**

## Performance

- **Duration:** 22 min
- **Started:** 2026-11-05T09:42:15Z
- **Completed:** 2026-11-05T10:04:34Z
- **Tasks:** 2
- **Files modified:** 11（10 新建、1 修改）

## Accomplishments

- `ProbeEvaluator`：静止基线逐轴取中位数（单帧尖峰不拉偏）；`evaluate_step` 返回有符号 `delta`、`margin`、`separation`，按「帧数 → 位移 → 歧义」顺序给出具体拒绝码；`validate_cross` 只消费 `axis/sign/separation`，三条失配各有 code，唯一 warning `low_separation` 由「赢家 1.0 / 第二名 0.4」这一可达时序证明；`mapping_from_steps` 把 `rs_x` 绑到 right、`rs_y` 绑到 down。
- `AxisMapping`：索引与符号分成独立字段（`-1` 既是合法符号又是未映射哨兵，合并就无法区分）；`raw_rs()` 返回未乘符号的原始值供校准采样；`snapshot_rs()` 依次 normalize ×2 再 deadzone，是 raw → 角度的唯一接缝。
- `Calibration`：`normalize` 把「先减中点 → 再除量程 → 最后乘符号」写死并注释理由；`deadzone` 逐字移植桌面 `_deadzone`，`minf(1.0, …)` 把输出长度封顶在 1.0（斜向 (1,1) → (0.7071, 0.7071)、长度恰为 1.0）；中点/量程统计用中位数与峰峰值，坏样本按 `not_enough_samples` / `hand_on_stick` / `range_short` / `scale_too_small` 分类。
- `DeviceProfile`：schema 必含 `profile_id`（固定 "primary"，INPUT-03 预留）；`can_reuse()` 只比较实测的四个 index+sign，`axes == null` 返回 false；`suggest_layout()` 只按小写名匹配，认不出返回空；`from_dict()` 逐字段 `typeof` 守卫，任一非法 → null + ConfigError（整份丢弃）。
- `test_device_profile`：10 个 `_check_*` 函数、157 条断言。除逐条正负例外，还有两条结构性断言：`evaluate_step` 的真实返回直接喂 `validate_cross`（防止两侧各写一份键名），以及合成 raw 经 `snapshot_rs` → `Geometry.angle_of` 依次得到 0/90/180/270。
- 全套基线保持绿：`TESTS_SUITES=11` / `TESTS_ASSERTIONS=965` / `TESTS_DONE failures=0`；`LINT_OK files=26`；`gate-a.sh` 通过；`check_desktop.sh` 230/230；`git diff --stat mobile/src/core/geometry.gd` 为空。

## Task Commits

Each task was committed atomically:

1. **Task 1: ProbeEvaluator + AxisMapping + Calibration（纯计算，零时钟零 I/O）** — `c873a8a` (feat)
2. **Task 2: DeviceProfile + 复用门 + 布局建议 + 设备档案套件** — `c051880` (feat)
3. **复核修正: 子对象 from_dict 出错必须整份返回 null（+2 条直连断言）** — `89f56a8` (fix)

**Plan metadata:** 见本次最终 docs 提交（SUMMARY / STATE / ROADMAP）

## Files Created/Modified

- `mobile/src/core/device/probe_evaluator.gd` — 中位数基线、四步窗口评估、交叉校验、`mapping_from_steps`（184 行）
- `mobile/src/core/device/axis_mapping.gd` — 索引/符号分离、`mapped`、`raw_rs`、`snapshot_rs`、to_dict/from_dict（259 行）
- `mobile/src/core/device/calibration.gd` — normalize/deadzone、center/scale 采样统计、to_dict/from_dict（263 行）
- `mobile/src/core/device/device_profile.gd` — 档案字段、make_key、can_reuse、suggest_layout、严格 from_dict（202 行）
- `mobile/tests/unit/test_device_profile.gd` — 10 个 `_check_*`、157 条断言（502 行）
- `mobile/tests/core_runner.gd` — `SUITES` 增至 11（新增 `device_profile`）
- 四个 core `.gd.uid` 与 `test_device_profile.gd.uid` — Godot 4.7.2 `--import` 生成，按既有约定提交

## Decisions Made

- **死区逐字移植，不换 `Input` 的向量合成**：桌面公式的角度不变性与「长度 = scaled ≤ 1.0」是判定对等的前提；换一套圆形死区会让同一物理位置在不同点越阈值。
- **归一化顺序写死**：先减中点、再除量程、最后乘符号；middle 0.02 的样本必须精确归零。
- **`delta` 有符号**：`sign` 由它导出，质量记录与排障也读它；`validate_cross` 不重算。
- **`low_separation` 是唯一且可达的 warning**：用 1.0/0.4 的合成窗口证明；不写不可达的 `weak_step`。
- **`rs_y` 只来自 down 步**：上下接线反了必须在探针阶段暴露，而不是在判定里表现成 180°。
- **复用门只比四项**：校准与 rest 不参与，复用时整份采用档案校准；同名不同映射必被拒。
- **整份丢弃**：`from_dict` 不做部分恢复，任何字段非法都只返回 null + ConfigError。
- **不存设备序号**：官方明说重启后顺序不保证一致。

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `validate_cross` 的上/右同轴判断写反**
- **Found during:** Task 2 首次跑套件（`TESTS_FAIL` 9 条）
- **Issue:** 实现写成 `if up.axis != right.axis: return fail`。上（y 轴）与右（x 轴）本来就该不同轴，正确条件应是「相等才失败」；结果所有正常四步都被判成 `same_axis_up_right`。
- **Fix:** 改为 `if up["axis"] == right["axis"]`。上下、左右两条判断本来就是对的（`!=(同轴) or !=(反号)` 即失败）。
- **Files modified:** mobile/src/core/device/probe_evaluator.gd
- **Verification:** `_check_probe_rejections` 的四步正确交叉校验与三种失配各返回预期 code；`TESTS_DONE failures=0`。
- **Committed in:** `c051880`

**2. [Rule 1 - Bug] `Calibration` 漏写四个字段声明，整条依赖链编译失败**
- **Found during:** Task 2 首次跑套件（`Parse Error: Identifier "center_x" not declared`）
- **Issue:** 类文档、常量、方法都写了，但 `center_x/center_y/scale_x/scale_y` 四个 `var` 忘写；`AxisMapping`、`DeviceProfile` 依次编译失败，套件里出现一串 `Nonexistent function`。
- **Fix:** 补上四个带默认值的字段声明（0.0 / 0.0 / 1.0 / 1.0）。
- **Files modified:** mobile/src/core/device/calibration.gd
- **Verification:** `TESTS_DONE failures=0`；`_check_profile_schema` 往返通过。
- **Committed in:** `c051880`

**3. [Rule 1 - Bug] 扳机条目被误要求 `sign`，合法档案无法往返**
- **Found during:** Task 2 往返断言（`合法档案必须能往返` + 2 条 ConfigError）
- **Issue:** `_axis()` 对所有轴无条件读 `sign`，而 `lt` / `rt` 的 schema 只有 `index` + `rest`；`to_dict()` 自己产出的档案被 `from_dict()` 拒绝。
- **Fix:** 只对摇杆轴（非 lt/rt）读 `sign`；扳机条目的 `rest` 保持可选。
- **Files modified:** mobile/src/core/device/axis_mapping.gd
- **Verification:** `合法档案不应产生 ConfigError（实际 0 条）`；往返逐字段断言全绿。
- **Committed in:** `c051880`

### 计划字面与验收的冲突（按验收执行并记录）

**4. [Rule 3 - 计划字面] `calibration.gd` 不允许出现 `get_vector` 字面量，但 action 要求写出该 API 名**
- **Found during:** Task 1 验收自检
- **Issue:** action 要求「明确写出禁止用 `Input.get_vector()`」，而 acceptance 要求「`calibration.gd` 不含 `get_vector`」。两句不能同时满足。
- **Fix:** 按 acceptance 执行 —— 注释改为「禁止用 Input 的向量合成（那套圆形死区与 enter_threshold）或 InputMap 替代」，保留同一条理由，但不出现该标识符。prohibition 的语义未减弱。
- **Files modified:** mobile/src/core/device/calibration.gd
- **Verification:** `grep -c get_vector calibration.gd` = 0；lint 与套件全绿。
- **Committed in:** `c873a8a`

**5. [Rule 3 - 计划字面] 计划说「八个 `_check_*`」，实际枚举了十个**
- **Found during:** Task 2 组织套件
- **Issue:** action 的清单有 10 条：four_steps / rejections / evaluate_feeds_cross / calibration / normalize_order / deadzone / profile_schema / reuse_gate / angle_seam / suggest_layout。
- **Fix:** 实现全部 10 个（每个都对应一条 must-have，合并会丢覆盖）；SUMMARY 记录更正后的数量。未删除任何断言。
- **Files modified:** mobile/tests/unit/test_device_profile.gd
- **Verification:** `grep -c '^func _check_'` = 10，`run(r)` 十个全部调用。
- **Committed in:** `c051880`

**6. [Rule 3 - 计划字面] `scale 0.4 → scale_too_small` 与 `最多位移 < 0.6 → range_short` 的判定顺序冲突**
- **Found during:** Task 2 设计校准用例
- **Issue:** 若整份样本的最大位移是 0.4，`range_short`（< 0.6）会先命中，`scale_too_small` 永不可达，与计划要求的「scale 0.4 → scale_too_small」矛盾。
- **Fix:** 明确两个分支的判据：`range_short` 看 `max(scale.x, scale.y) < 0.6`；`scale_too_small` 看 `min(scale.x, scale.y) < 0.5`。用例用「X 0.9 / Y 0.4」的偏斜样本命中后者，「X/Y 都 0.4」命中前者；两个分支各一条可达断言。语义（推不到外圈 / 某轴不可用）与计划一致。
- **Files modified:** mobile/src/core/device/calibration.gd、mobile/tests/unit/test_device_profile.gd
- **Verification:** `_check_calibration` 两条 code 断言各自命中。
- **Committed in:** `c051880`

### 边界与加强

**7. [Rule 2 - 边界] `ls_*` 索引允许 -1（未映射），`rs_*` 仍强制 0..7**
- **Found during:** Task 1 设计 `from_dict`
- **Issue:** 计划写「axes 四项索引是 0..7」，但 RESEARCH 允许「跳过左摇杆探针」，而 `AxisMapping` 的 ls 默认值就是 -1。若严格只收 0..7，`to_dict()` 自己产出的「无左摇杆」档案无法被 `from_dict()` 读回，往返断言必红。
- **Fix:** `rs_x/rs_y` 必须 0..7（没有右摇杆的档案不可用）；`ls_x/ls_y` 额外接受 -1；`lt/rt` 允许省略或 -1。负例 `rs index = 8` 仍被拒。
- **Files modified:** mobile/src/core/device/axis_mapping.gd
- **Verification:** schema 负例 `rs_x.index = 8` / `rs_y.index = 8` 均返回 null；合法档案往返通过。
- **Committed in:** `c873a8a` / `c051880`

**8. [Rule 2 - 强化] 死区增加 NaN / Inf 守卫**
- **Found during:** Task 1 写死区
- **Issue:** 威胁模型 T-04-10 要求坏样本不能流进判定；`normalize` 已挡住 NaN，但 `deadzone` 是公开函数，调用方可能直接喂 raw。
- **Fix:** 公式主体逐字保留，函数开头加 `is_finite` 三连守卫，非有限值返回 `Vector2.ZERO`。
- **Files modified:** mobile/src/core/device/calibration.gd
- **Verification:** 公式与长度断言不变；lint 与套件全绿。
- **Committed in:** `c873a8a`

**9. [Rule 2 - 任务边界] 额外提交 `test_device_profile.gd.uid`**
- **Found during:** Task 2 `--import`
- **Issue:** `files_modified` 未列测试脚本边车，但 Phase 2 的既有约定是 `*.gd.uid` 是提交物。
- **Fix:** 随 Task 2 一并提交。
- **Verification:** `git ls-files --error-unmatch mobile/tests/unit/test_device_profile.gd.uid` 成立。
- **Committed in:** `c051880`

**10. [Rule 1 - Bug] 子对象 `from_dict` 出错时返回了「部分可用 + 错误」**
- **Found during:** SUMMARY 复核（对照计划里「任一不合法 → 记一条 ConfigError 并返回 null」）
- **Issue:** `AxisMapping.from_dict` / `Calibration.from_dict` 在字段非法时把错误追加进 `out_errors` 后仍返回对象。`DeviceProfile` 的整份丢弃不受影响（它自己检查错误数），但直接调用子对象的路径会拿到部分映射 —— 与计划契约不符，也给 04-04 的 `ProfileStore` 留了一个危险入口。
- **Fix:** 两个 `from_dict` 各加 `before := out_errors.size()` 守卫，出错即返回 null；补两条直连断言证明「直接调用也不返回部分对象」。
- **Files modified:** mobile/src/core/device/axis_mapping.gd、mobile/src/core/device/calibration.gd、mobile/tests/unit/test_device_profile.gd
- **Verification:** `TESTS_ASSERTIONS=965` / `TESTS_DONE failures=0`；lint 与闸门 A 全绿。
- **Committed in:** `89f56a8`

### 机械计数更正

- 计划写 `TESTS_ASSERTIONS ≥ 608`（Phase 3 基线 576 + 32）。04-02 结束时基线已是 **808**；本套件新增 **157** 条，实测 **965**。阈值未放宽，按实际树更正记录（约束 17）。
- 计划写「八个 `_check_*`」，实际清单十条，实现十条（见 Deviation 5）。

### 环境差异（不是计划分歧）

- 本环境没有 `gsd_run` 命令，Step 0 的 protected-branch 查询无法执行。按 orchestrator 的 `<sequential_execution>`「在 main 工作树上顺序执行」与 `.planning/config.json` 的 `git.branching_strategy: none`，在 `main` 上用普通提交（带 hooks，未用 `--no-verify`）。未做任何 `git update-ref` 之类的自愈操作。

---

**Total deviations:** 10（4 个真实 bug、1 处验收冲突、2 处计划字面调整、3 个边界/加强）+ 1 条环境说明
**Impact on plan:** 无断言被削弱。三个 bug 都是实现与自身契约不一致（不是行为取舍），修复后套件从 9 条失败降到 0；两处计划字面调整都保留了两侧覆盖（10 个 `_check_*` 全实现；`range_short` 与 `scale_too_small` 各有一条可达样本）。`get_vector` 的处理只改注释，不改变任何行为。

## Issues Encountered

- 首次跑套件时 `r.assertions` 因 `r` 无类型而无法推断 `:=`，改为显式 `var total: int = r.assertions`。这是 GDScript 的类型推断限制，不是逻辑问题。
- `Vector2` 分量是 32 位浮点（`0.1` 存成 `0.10000000149`），三处 `1e-9` 容差过紧；按实际精度改成 `1e-6`，判据（中位数 / 量程数值）未削弱。
- 死区角度断言原用 (0.3, 0.4)，输出经 32 位转换后角度差约 1.5e-6，超过 1e-6 容差；按计划原文改用 (0.6, 0.8) 比较角度（满量程，转换误差更小），(0.3, 0.4) 保留长度断言。
- Godot 仍偶发打印 `Unicode parsing error ... Invalid UTF-8 leading byte (ff/fe)`；既有导入噪声，`--import` 本次一次成功，测试不受影响。

## User Setup Required

None - no external service configuration required. 本计划未安装任何依赖，未修改 `shared/skills_config.json`，未改 `mobile/src/core/geometry.gd`。

## Next Phase Readiness

- `ProbeEvaluator` / `AxisMapping` / `Calibration` / `DeviceProfile` 四个纯对象已就位，04-04 的 `PadSampler` 只需把 `PackedFloat32Array` 采样切好传进来；`ProfileStore` 直接复用 `to_dict()` / `from_dict()`，不写第二份字段名。
- 复用门的消费者契约已固定：04-05 的 `STATE_REUSE_REST` / `STATE_REUSE_CHECK` 只实测右 + 下两步，调 `can_reuse(rs_x_index, rs_x_sign, rs_y_index, rs_y_sign)`；相等才跳过四步探针，否则整份丢弃重探。
- 成功标准 3 的可无头证明部分闭合（探针记录 index+sign、复用门拒绝同名不同映射、档案非法即整份丢弃）；真机枚举与首次校准在 04-04 / 04-07。
- INPUT-04 的布局建议纯函数与「匹配不到不预选」已固定；按键确认页与状态机在 04-05。
- 真机相关风险不变：安卓 60–125 Hz 的到达间隔分布、`set_use_accumulated_input(false)` 的亚帧时间戳仍未实测（见 STATE.md Blockers）。

---

*Phase: 04-device-input-green-slice*
*Completed: 2026-11-05*

## Self-Check: PASSED

- 10 个新建文件全部存在（含 5 个 `.gd.uid` 边车）
- 三个任务提交 `c873a8a` / `c051880` / `89f56a8` 均为 HEAD 祖先
- `TESTS_SUITES=11` / `TESTS_ASSERTIONS=965` / `TESTS_DONE failures=0` / `LINT_OK files=26` / `gate-a.sh` 通过 / `check_desktop.sh` 230/230 均为本次运行实测
