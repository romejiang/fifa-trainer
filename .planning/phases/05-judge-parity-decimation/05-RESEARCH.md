# Phase 5 Research: 全动作判定对等性

**Researched:** 2026-11-06
**Domain:** Python 参考实现 → 纯 GDScript 检测器/引擎移植 / 250 Hz 黄金向量 / 250→120/90/60 Hz 抽稀
**Confidence:** 检测器与引擎语义 **HIGH（逐行读 + 实跑）**；抽稀规则 **HIGH（本次实测，含反例）**；左摇杆映射与真机项 **MEDIUM（无第二只手柄、无活动窗口实测）**

---

## Executive Summary

按「计划者最需要先知道什么」排序：

1. **三类检测器的语义自仓库诞生起从未改过，引擎只被加过两个正交开关。** `git log --follow desktop/padskills/detectors.py` 只有 `5e489a1 Initial commit` 与 `02b03db` 搬迁两次提交；`4825afa` 的合并只往 `engine.py` 加了 `focus` / `paused` / `_reset_progress`，并把循环里的 `self.skills` 换成 `active_skills()`。**Arc/Sequence 的阈值、分支顺序、失败码与 Phase 3 时期完全一致**；真正变了的是**检查数量**（182 → 205，总共 302），因为合并新增了专项练习与按键校准的断言。所以「230 项基线」这个说法已经过期，当前基线是 **302**（`test_detectors.py` 205 + `test_gui_smoke.py` 97）[VERIFIED: `bash tools/check_desktop.sh` 输出「302 项检查全部通过」；`cut -f1 shared/expected_checks.txt | sort | uniq -c` → 205 / 97]。

2. **检测器只读 `Frame` 的五个字段，`state` / `ls_mag` / `ls_angle` 对它们全是死字段。** `grep -n "frame\." desktop/padskills/detectors.py` 的全部命中只有 `now`、`rs_mag`、`rs_angle`、`facing`、`buttons` —— 没有任何一行读 `frame.state`、`frame.ls_mag`、`frame.ls_angle`。因此移动端 `Frame` 的**检测器可见**字段只需五个；左摇杆只以 `ls_mag` / `ls_angle` 两个「引擎专用」字段存在，`facing` 由引擎每帧写入后再交给检测器（与桌面「引擎构造 Frame」完全同构）。

3. **抽稀规则的决定性变量不是「取哪个样本」，而是「保留哪个时间戳」。** 本次实测（`/tmp/p5probe/probe5.py`）：在 250 Hz 网格上把 tap 的第二下间隔做成 396 / 400 / 404 / 596 / 600 / 604 ms，**只把时间戳对齐到抽稀后的网格**（120 Hz 也一样），396→`ok`、604→`ok`，即边界判定被凭空翻转；而「取最近样本 + 保留该样本的原始时间戳」在 120/90/60 Hz 下把全部六种间隔的 `code` 与 `elapsed_ms` 都原样保住。结论：**抽稀只能抽样本，不能抽时间戳**。

4. **「永不丢按钮沿」是硬需求，不是保险。** 同一次实测（`probe4.py`）：4 ms 的一次 X 按下在 60 Hz 下只占 1/4 帧；一旦不做按钮沿保底，396 ms 的 `too_fast` 会变成 752 ms 的 `too_slow`（第二下根本没被看见），404 ms 的 `ok` 同样变成 `too_slow`。**丢一条边沿 = 丢掉一整个判定。**

5. **`global_cooldown_ms = 60` 在出厂配置下是不可达分支 —— 这是对路线图假设的实测修正。** 实测两段马赛回旋（各 252 ms，相隔约 680 ms）：真实配置下两条都记 `ok`、`suppressed=0`；把 `global_cooldown_ms` 改成 1000 后第二条被吞、`suppressed=1`（`probe2.py`）。而代码上任何命中都会置手势锁，解锁要求「右摇杆回中持续 `gesture_release_ms=150`」（`engine.py:275-289, 368-370`），所以第二发最早也在 150 ms 之后 —— 恒大于 60 ms。**真正会被抽稀撬动的阈值是 `release_hold_ms = 120`**：实测在弧线失败后回中 **124 ms** 再起手，250 Hz 得到 `[too_short, too_fast]` 两条，120/90/60 Hz 只剩 `[too_short]` —— 少了一条判定（`probe6.py`）。这是本次唯一实测到的「整条判定消失」类漂移。

6. **`message` / `detail` / `summary` 在抽稀后一定不同，只有 `code` 可跨采样率比较。** `wrong_end` 的文案里嵌着实测角度（`停在相对 264°`），60 Hz 下同一轨迹会写出别的数字；Arc 的 `detail` 还嵌着 `采样 N 点`。所以对等契约必须分三层：250 Hz 全字段逐字；抽稀后只比 `(skill, code)` + `measured` 容差；`message` 永不在抽稀层比较。

7. **`measured{}` 今天有一半拿不到：Sequence 没有「每步耗时」。** Arc 有 `start_angle` / `start_rel` / `end_rel` / `acc` / `samples` / `_path`（`detectors.py:191-209`）；Sequence 有每步的 `_step_lo/_hi/_sum/_n` 与 `_best_hold_ms`（`:512-518`），但**没有记录每一步完成时刻**。要满足 JUDGE-05 与 Phase 7 的时序条，Phase 5 必须在移动端检测器里加 `_step_t`（纯增量字段，不影响判定），并把它装进 `Hit.measured` / `Failure.measured`。桌面参考保持冻结，`measured` 是移动端视图，由移动端断言证明。

8. **左摇杆现在是 `-1`，而 5 个动作里 4 个是 `relative_to_ls`。** `InputSetup.build_profile()` 明写 `mapping.ls_x_index = -1` / `ls_y_index = -1`（`mobile/src/core/input_setup.gd:338-340`）。`AxisMapping.from_dict` 允许 `ls` 的**索引**为 -1（`axis_mapping.gd:123-129, 163`），所以旧档案**能加载但不能用**：`relative_to_ls` 的技能会因为 `ls_ok == false` 永远走 `reset()` 分支。必须补「左摇杆轴对 + 符号 + 校准」，并给档案加一道可机械识别的迁移门（照 04-11 的 `quality.range_ready` 先例）。

9. **真机 5 个动作不能靠「专项练习」式单选，因为没有 UI 选择器。** 现在 `main.gd` 用 `TapRuntime.select_taps_skill()` 取唯一 taps 动作（`main.gd:90-97`），练习屏只显示 `_runtime.skill_name`。Phase 5 最小可行路径是**自由练习（全部启用技能）+ 横幅显示 `Outcome.skill_name`**；动作选择器属于 Phase 6（LOOP-05）。

**Primary recommendation:** 把「三类检测器 + `GestureEngine`」当成**一个不可分割的移植单元**，以 `Engine._tick` 为唯一参考入口；黄金语料按「250 Hz 全字段逐字 / 抽稀只比 code / measured 单独断言」三层设计；抽稀工具只抽样本、保留时间戳、强制保留按钮沿；左摇杆按「新 schema + `ls_ready` 标记」整份重建档案。

---

## Evidence and Confidence

> `[VERIFIED: path:line]` = 本次 `Read` 该文件并逐字引用；`[VERIFIED: 命令行输出]` = 本次实跑；`[CITED: url]` = 外部一手来源；`[ASSUMED]` = 未验证，必须转成测量项。

| # | 结论 | 证据 | 置信度 |
|---|------|------|--------|
| E1 | `detectors.py` 自 Initial commit 起未改语义 | `[VERIFIED: git log --follow -- desktop/padskills/detectors.py 仅 5e489a1、02b03db]` | HIGH |
| E2 | `engine.py` 在 `4825afa` 只新增 `focus`/`paused`/`_reset_progress`，循环改用 `active_skills()` | `[VERIFIED: git diff c350258 4825afa -- desktop/padskills/engine.py]`（diff 只含这四类改动） | HIGH |
| E3 | 当前桌面基线 = 302 项（205 + 97） | `[VERIFIED: bash tools/check_desktop.sh → 「✓ 302 项检查全部通过，名称与基线逐项一致」]` | HIGH |
| E4 | 检测器只读 `now/rs_mag/rs_angle/facing/buttons` | `[VERIFIED: desktop/padskills/detectors.py:241-242, 285-294, 627-631, 696-698, 809-813, 917-918, 950-959]`，无一处 `frame.state` / `frame.ls_*` | HIGH |
| E5 | `Frame` 有 8 个字段，但 `ls_mag/ls_angle/state` 无消费者 | `[VERIFIED: desktop/padskills/detectors.py:27-37]` | HIGH |
| E6 | `Engine.GROUP_SIZE=10` / `IDLE_STICK=0.20` / `RELEASE_STICK=0.35` | `[VERIFIED: desktop/padskills/engine.py:93-98]` | HIGH |
| E7 | `_tick` 分支顺序：朝向 → paused → Frame → 手势锁 → held_required → idle → 逐技能（held/relative/buttons/update）→ 命中丢弃他人 → 冷却 → 记录 → 锁 → break → drain → rumble | `[VERIFIED: desktop/padskills/engine.py:248-377]` | HIGH |
| E8 | 命中后先 `_discard_other_claims` **再**判冷却；被冷却吞掉时静默 `continue` | `[VERIFIED: desktop/padskills/engine.py:340-352]` | HIGH |
| E9 | 失败也只有**一条**：按 `active_skills()` 配置顺序取第一个有 pending 的；取到后 `_discard_other_claims(owner)`（失败也清别人进度） | `[VERIFIED: desktop/padskills/engine.py:391-412]` | HIGH |
| E10 | 「按住别的技能的修饰键 → 该技能 observe+abandon」由 `held_required` 集合驱动 | `[VERIFIED: desktop/padskills/engine.py:296-330]` | HIGH |
| E11 | 相对技能在左摇杆回中时走 `observe()` + `reset()`（不是 abandon） | `[VERIFIED: desktop/padskills/engine.py:326-330]` | HIGH |
| E12 | 引擎级 idle：`rs_mag < 0.20` 持续 `idle_reset_ms` 后对每个技能 `on_idle()` 一次 | `[VERIFIED: desktop/padskills/engine.py:303-314]` | HIGH |
| E13 | `_reset_progress()` = 全部 `abandon()` 再 `on_idle()`，并清锁/清 idle 计时 | `[VERIFIED: desktop/padskills/engine.py:185-198]` | HIGH |
| E14 | 桌面**没有** `on_time_discontinuity` / `on_device_lost` | `[VERIFIED: grep 全仓：只出现在 .planning/research/ 与 onboarding_flow.gd，engine.py 零命中]` | HIGH |
| E15 | 5 个动作的阈值（逐字） | `[VERIFIED: shared/skills_config.json:93-235]` | HIGH |
| E16 | `_deadzone` 输出长度恒 = `scaled ≤ 1.0`，角度不变 | `[VERIFIED: desktop/padskills/input_source.py:364-370]` | HIGH |
| E17 | `PadState` 的 `ls_mag/rs_mag/ls_angle/rs_angle` 是 property，从 x/y 现算 | `[VERIFIED: desktop/padskills/input_source.py:84-112]` | HIGH |
| E18 | 抽稀「对齐网格时间戳」会翻转 396/604 ms 边界 | `[VERIFIED: /tmp/p5probe/probe5.py 输出：396→ok、604→ok（120/90/60 全同）]` | HIGH |
| E19 | 抽稀「保留原始时间戳」在 120/90/60 下六种间隔全同码同 elapsed | `[VERIFIED: /tmp/p5probe/probe5.py 输出]` | HIGH |
| E20 | 不保留按钮沿 → 4 ms 按压在 60 Hz 被整条丢掉，`too_fast`/`ok` 变 `too_slow` | `[VERIFIED: /tmp/p5probe/probe4.py 输出]` | HIGH |
| E21 | `global_cooldown_ms=60` 在出厂配置下不可达（手势锁 ≥150 ms）；改成 1000 才可达 | `[VERIFIED: /tmp/p5probe/probe2.py 输出 suppressed=0 / suppressed=1；engine.py:275-289, 368-370]` | HIGH |
| E22 | 弧线失败后回中 124 ms：250 Hz 两条判定，120/90/60 只剩一条 | `[VERIFIED: /tmp/p5probe/probe6.py 输出 gap=124]` | HIGH |
| E23 | `wrong_end` 的 `message` 在抽稀后数字不同、`code` 相同 | `[VERIFIED: /tmp/p5probe/probe2.py 输出 msg_same=False]` | HIGH |
| E24 | 踩单车 `wrong_start` 可达（起点 60°） | `[VERIFIED: /tmp/p5probe/probe8.py → 'wrong_start'，文案「从相对 60° 起手」]` | HIGH |
| E25 | 马赛回旋 `overshoot` 在出厂配置下不可达（终点窗口覆盖 max_angle 区间） | `[VERIFIED: /tmp/p5probe/probe8.py：240° 扫掠先得到 too_fast；结合 detectors.py:353-361 与 383-404 的分支顺序]` | HIGH（实测 + 代码） |
| E26 | `InputSetup.build_profile()` 写 `ls = -1` | `[VERIFIED: mobile/src/core/input_setup.gd:338-340]` | HIGH |
| E27 | `AxisMapping` 已有 `ls_x/ls_y` 字段与 `has_ls()`；`from_dict` 允许 ls=-1 | `[VERIFIED: mobile/src/core/device/axis_mapping.gd:20-23, 34-35, 123-129, 163]` | HIGH |
| E28 | `Calibration` 只有一组 `center_x/center_y/scale_x/scale_y`（右摇杆） | `[VERIFIED: mobile/src/core/device/calibration.gd:27-31]` | HIGH |
| E29 | `DeviceProfile.can_enter_practice()` 是复用唯一门；旧档案靠 `quality.range_ready` 识别 | `[VERIFIED: mobile/src/core/device/device_profile.gd:65-106]` | HIGH |
| E30 | 移动端套件 18 / 1533，哨兵是 `TESTS_DONE failures=0` + 拦截 `TESTS_ASSERTIONS=0` | `[VERIFIED: bash mobile/tools/test-core.sh 输出；mobile/tools/test-core.sh:150-172]` | HIGH |
| E31 | tap 夹具 `--check` 通过（detector 12 / runtime 6） | `[VERIFIED: python3 tools/gen_tap_golden.py --check → 「✓ …（detector 12 条、runtime 6 条）」]` | HIGH |
| E32 | 真机活动窗口 `dt95` 未单独测量（234.7 含 idle） | `[VERIFIED: .planning/phases/04-device-input-green-slice/04-VERIFICATION.md:53-54]` | HIGH（作为缺口） |
| E33 | 第二只手柄的复用拒绝面未测 | `[VERIFIED: 04-VERIFICATION.md:20, 48-50]` | HIGH（作为缺口） |
| E34 | `JoyButtonMap` 明写 LT/RT 是轴、不合成 | `[VERIFIED: mobile/src/input/joy_button_map.gd:17-22]` | HIGH |
| E35 | Godot `--script` 的解析失败会返回 0，只能用哨兵判 | `[VERIFIED: mobile/tests/core_runner.gd:4-12, 74-85]` | HIGH |

---

## Project Constraints (from AGENTS.md)

从仓库根 `AGENTS.md` 提取、本阶段必须遵守的硬约束（与 04-RESEARCH 的 C1–C11 同源，补两条本阶段新增）：

| # | 约束 | 对本阶段的含义 |
|---|------|----------------|
| C1 | 安卓优先，iOS 延后 | 只做 Android；不写 iOS 分支 |
| C2 | 必须有外接手柄，不做虚拟摇杆 | 判定输入只能来自 `PadSampler` 的事件通道 |
| C3 | 安卓上 Godot **没有**手柄震动；唯一通道 `vibrate_handheld()` | 本阶段不接任何震动；`RumbleSequencer` 只保留注入式 no-op |
| C4 | 采样 60–125 Hz；阈值按毫秒保留；`Input.set_use_accumulated_input(false)` | 抽稀矩阵的验收目标是 60/90/120 Hz，不是 250 Hz |
| C5 | 真机真手柄验证；模拟器不算 | SC2/SC3 的「真机」部分不得无头代签 |
| C6 | 桌面检查是回归红线 | `bash tools/check_desktop.sh` 必须保持 302 全绿；本阶段**不得**改 `desktop/padskills/*.py` |
| C7 | `shared/skills_config.json` 唯一真源 | 语料生成器只能读它；**不得**为对齐而改阈值（除证据流程批准） |
| C8 | 标识符英文 ASCII；注释/文案中文；JSON 键 snake_case | 新文件、夹具键、错误码全部遵守 |
| C9 | 时长 `_ms`、频率 `_hz`、时间戳显式传入 | `Frame.now` 秒、检测器内部 `* 1000.0` |
| C10 | 一文件一 `class_name`、Tab 缩进、无第三方测试框架 | 新套件挂进 `core_runner.gd` 的 `SUITES` |
| C11 | `design/` 不许碰；禁止 `git add -A` | 只写 `.planning/` 与计划内文件 |
| C12 | `src/core/**` 禁 `Input.` / `Time.` / `Node` / `FileAccess` / `print(` 等 14 条 | 新检测器/引擎全部在 `src/core/`，由 `tools/lint_core_purity.py` 机械强制 |
| C13 | 移动端测试不加 `class_name`，避免污染全局命名空间 | 新套件文件同样不加 |

---

## Phase Requirements

| ID | 描述（REQUIREMENTS.md） | 本研究的支撑 |
|----|------------------------|--------------|
| JUDGE-01 | 三类检测器以纯 GDScript 状态机重实现，不依赖场景树 | §Current Desktop Reference A.2–A.4（逐字段/逐分支）+ §Mobile Runtime Shape |
| JUDGE-02 | 5 个动作全部可识别 | §Five-Skill Parity Corpus B.1（逐字阈值）+ B.3（每个动作的成功轨迹） |
| JUDGE-03 | 判定序列与 Python 桌面版逐条一致（230 项为基线） | §A.7（302 项的移植口径）+ §B.4（`_tick` harness）+ §Verification（三层契约） |
| JUDGE-04 | 五类失败原因正确 | §B.2（可达性矩阵：哪些码在出厂配置下真能出现） |
| JUDGE-05 | 每次判定返回 `measured{}` | §Mobile Runtime Shape D.5（字段表 + 今天缺什么） |
| JUDGE-06 | 手势锁/失败归属/冷却/修饰键互斥与桌面一致 | §A.5（`_tick` 分支顺序）+ §B.3（仲裁夹具） |
| JUDGE-07 | 250 Hz 抽稀到 60/90/120 不漂移 | §Decimation（规则 + 实测 + 工具形态 + 调整流程） |

> 注：JUDGE-03 写的是「230 项」，但 04-VERIFICATION 与本次实测都是 **302 项**。计划里应写「以当前 205 项检测器/引擎检查为移植口径」，并在文档里注明 230 是 Phase 1 的历史数字。

---

## Current Desktop Reference

### A.1 文件溯源：哪些东西真的变了

| 文件 | 4825afa 之前 → 之后 | 对 Phase 5 的意义 |
|------|--------------------|-------------------|
| `desktop/padskills/detectors.py` | 无变化（自 Initial commit 起只有两次提交：初版 + 搬目录） | **三类检测器 = 冻结的规格书**，照抄即可 |
| `desktop/padskills/engine.py` | 新增 `focus`（专项）/`paused`（暂停）/`_reset_progress`；循环目标从 `self.skills` 改为 `active_skills()` | 仲裁语义未变；移动端**不移植 focus/paused**，只移植 `_reset_progress` 的语义（见 D.2） |
| `desktop/padskills/config.py` | 新增 `shared_config_path` / `write_config_target` | 与判定无关 |
| `desktop/tests/test_detectors.py` | +154 行：专项练习隔离、切换后立即起手、暂停判定、按键表覆盖 | 这 154 行里**只有「暂停」与「专项」是桌面特有**，其余是对既有语义的补充断言 |
| `shared/expected_checks.txt` | 230 → 302（182+48 → 205+97） | 移植口径按 302 算 |
| tap 夹具 | 因 `config.py` / `engine.py` / `skills_config.json` 的哈希变化重生成（`detectors.py` 哈希 `9fca63…` 两边相同），18 条期望字节不变 | 证明「源哈希进夹具」机制有效；也说明**改一行注释都会触发重生成**（见下） |

`shared/skills_config.json` 在 4825afa 里**只改了 `_readme` 文案**（新增 `button_names` 说明），5 个动作的阈值与 `input` / `global_cooldown_ms` 逐字未变 `[VERIFIED: git diff c350258 4825afa -- shared/skills_config.json]`。这条很重要：文件哈希会因注释而变，**不能**把「哈希变了」当成「语义变了」的证据。

`[VERIFIED: git log --follow；git diff c350258 4825afa；4825afa 提交信息；git show 58f9e9d]`

### A.2 `ArcDetector`（`detectors.py:125-446`）

**构造期字段（逐字）**

| 字段 | 来源/默认 | 出厂值（马赛回旋 / 踩单车） |
|------|-----------|------------------------------|
| `enter` | `enter_threshold`，默认 0.80 | 0.72 / 0.72 |
| `exit` | `exit_threshold`，默认 `min(0.60, enter)`；若 `exit >= enter` 则 `max(0.0, enter-0.05)` | 0.52 / 0.52 |
| `min_angle` / `max_angle` | 默认 150 / 220 | 70/230 、70/135 |
| `min_ms` / `max_ms` | `min_duration_ms` / `max_duration_ms`，默认 300/700；`max<=min` 抛错 | 250/600 |
| `idle_ms` | `idle_timeout_ms`，默认 180 | 250 |
| `motion_delta` | `motion_min_delta_deg`，默认 2.0 | 2.0（未写出） |
| `direction` | `"cw"→1`、`"ccw"→-1`、其它→0 | 0（`"any"`） |
| `start_target` | `start_angle`，`null` → None | 180 / 0 |
| `start_tolerance` | 默认 60 | 65 / 55 |
| `end_targets` | `end_angles` 或 `end_angle`，标量→单元素元组 | (0,) / (90,270) |
| `end_tolerance` | 默认 60 | 80 / 55 |
| `release_hold_ms` | 默认 120 | 120 |
| `claim_margin` | `claim_margin_deg`，默认 20 | 20（未写出） |
| `report_min_angle` | `max(20.0, min_angle * 0.35)` | 派生：24.5 / 24.5 |
| `relative` | `skill.relative_to_ls` | true |

**运行期字段**（`detectors.py:191-209`）：`armed`、`active`、`t0`、`acc`、`last_angle`、`start_angle`、`start_rel`、`end_rel`、`base`、`samples`、`_last_motion`、`_last_mag`、`_motion_ref_angle`、`_release_since`、`_path`（`(t,angle,mag)` 最多 64 点、间隔 ≥8 ms）、`_last_path_t`、`_pending`、`_claimed`、`_turn_sign`。

**`update()` 的分支顺序（顺序即语义，一步都不许换）**

```
1  mag < exit                     → 结束本段：若 was_active 且 _claimed 则算终点/扫掠 → _release_failure
                                    → active=False, acc=0, turn_sign=0；was_active 时 armed=False
                                    → 记 _release_since；若 !armed 且松手 ≥ release_hold_ms → armed=True
                                    → return None            (detectors.py:246-273)
2  !armed                         → return None              (:276-277)
3  !active 且 mag >= enter         → 起手：t0/acc/samples/start_angle/base/start_rel/end_rel/
                                    last_angle/_last_motion/_last_mag/_motion_ref_angle/_path/
                                    _claimed = start_target 为 None 或 angle_diff(start_rel,target)
                                               <= start_tolerance + claim_margin   (:279-301)
4  active                          → delta=signed_delta(last_angle, rs_angle); acc+=delta;
                                    samples+=1; 若 (angle_diff(_motion_ref_angle,rs_angle) >= motion_delta
                                    or |mag-_last_mag| >= 0.05) → _last_motion=now, ref=rs_angle;
                                    _last_mag=mag; elapsed_ms=(now-t0)*1000  (:303-316)
5  起点不对（仅 start_target 非空且超 start_tolerance）→ _claimed 时 emit wrong_start → _abort → None  (:325-336)
6  方向（仅 direction!=0 且 swept>=5）→ 首次锁定 turn_sign；与 direction 不符 → _claimed 时 emit
                                    wrong_direction → _abort → None                       (:340-351)
7  swept > max_angle               → _claimed 时 emit overshoot → _abort → None            (:353-361)
8  (now-_last_motion)*1000 > idle_ms → _claimed 且 swept>=5 时 emit stalled → _abort → None (:363-371)
9  elapsed_ms > max_ms             → _claimed 时 emit too_slow → _abort → None             (:373-381)
10 更新 end_rel / end_ok / in_range                                                        (:383-387)
11 elapsed_ms < min_ms             → 若 in_range 且 end_ok：_claimed 时 emit too_fast → _abort；否则 None
                                                                                            (:391-401)
12 !in_range 或 !end_ok            → None（继续累计，不报错）                              (:403-404)
13 成功：active=False, armed=False, turn_sign=0 → Hit(elapsed_ms, _describe(), summary)     (:406-412)
```

`_release_failure()`（`:220-238`）只可能产出两种码，且**扫掠小于 `report_min_angle` 时整条静默**（`:258`）：

```python
if swept < self.min_angle:
    return Failure("too_short", f"转得不够：只转了 {swept:.0f}°（需要 {self.min_angle:.0f}°~{self.max_angle:.0f}°）", elapsed_ms)
if self.end_targets and not end_ok:
    return Failure("wrong_end", f"终点不对：停在相对 {end_rel:.0f}°（应该回到 {target}±{self.end_tolerance:.0f}°）", elapsed_ms)
return None
```

`[VERIFIED: desktop/padskills/detectors.py:220-238]`

`_abort()`（`:212-218`）置 `active=False, armed=False, acc=0, _release_since=None, _turn_sign=0`；`reset()`（`:430-436`）置 `active=False, armed=True, acc=0, _release_since=None, _last_motion=0.0, _turn_sign=0`；`abandon()`（`:438-440`）= `_pending=None` + `_abort()`。

### A.3 `SequenceDetector`（`detectors.py:453-853`）

**构造期字段**

| 字段 | 默认 | 磕球过人 | 油炸丸子 |
|------|------|----------|----------|
| `steps` | `parse_step` 列表 | `["forward","back"]` | `[{direction:[右,左], hold_ms:350}]` |
| `tolerance` | 35 | 35 | 10 |
| `enter` | 0.65 | 0.65 | 0.60 |
| `release` | 0.35（若 ≥enter 则 `enter-0.15`） | 0.35 | 0.30 |
| `max_ms` / `min_ms` | 700 / 300 | 600 / 250 | 600 / 250 |
| `idle_ms` | 250 | 250 | 350 |
| `motion_delta` | 2.0 | 2.0 | 2.0 |
| `require_neutral` | True | true | true |
| `release_hold_ms` | 150 | 150 | 150 |
| `relative` | `skill.relative_to_ls` | true | true |

**运行期字段**（`:496-522`）：`index`、`t0`（None = 无进行中序列）、`neutral`、`_armed`、`_release_since`、`last_base`、`_hold_since`、`_now`、`_last_motion`、`_last_angle`、`_last_mag`、`_have_last`、`_motion_ref_angle`、`_pending`、`_best_hold_ms`、`_step_lo`/`_step_hi`/`_step_sum`/`_step_n`、`_facing`、`_buttons`、`_required`、`_button_mode`。

**`update()` 的分支顺序**

```
1  moved = !_have_last or angle_diff(_motion_ref_angle, rs_angle) >= motion_delta
          or |_last_mag - mag| >= 0.06；moved → ref=rs_angle；更新 _last_angle/_last_mag/_have_last  (:635-644)
2  t0 非空：base = last_base（relative）或 0；rel = norm(rs_angle-base)；step=steps[min(index,last)]
   holding = step.hold_ms>0 且 mag>=enter 且 match(rel)
   mag>=enter 且 match → _note_angle(index, rel)
   holding 且 _hold_since → _best_hold_ms = max(..., now-_hold_since)
   holding 或 moved → _last_motion = now
   timed_out (>max_ms) 或 stalled (>idle_ms) → _abandon_failure(...) → _abort()
        → 若 mag >= release 则 return None（还推着就先不继续判）                       (:646-672)
3  mag < release：记 _release_since；neutral=True；_hold_since=None；
   !_armed 且松手 ≥ release_hold_ms → _armed=True；return None                          (:674-685)
4  mag < enter → None            (:687-688)
5  !_armed → None                 (:689-690)
6  require_neutral 且 !neutral → None                                                   (:691-692)
7  facing_now = facing（relative）或 0；base = last_base（t0 非空）或 facing_now
   rel = norm(rs_angle - base)；step = steps[index]
8  !match(rel, step)：_hold_since=None；若 index>0 且命中 steps[0] → 从第一步重来
   （index=1, t0=now, last_base=facing_now, neutral=False, _last_motion=now,
    ref=rs_angle, _hold_since=None, _best_hold_ms=0）；return None                        (:701-716)
9  t0 为空 → t0=now, last_base=base, _last_motion=now, ref=rs_angle, _best_hold_ms=0,
   _reset_metrics(), _note_angle(index, rel)                                             (:719-726)
10 step.hold_ms>0 → 首次 _hold_since=now；held=(now-_hold_since)*1000；_best_hold_ms=max；
   held < hold_ms → None                                                                 (:729-736)
11 index == 末步 且 elapsed < min_ms → emit too_fast → _abort → None                     (:739-749)
12 index+=1；neutral=False；fired_hold_ms 取出；_hold_since=None；_best_hold_ms=0；
   _last_motion=now                                                                      (:751-757)
13 index >= len(steps) → elapsed；detail=_describe()；summary=_summary(fired_hold_ms)；
   index=0, t0=None, _armed=False, _release_since=None, _reset_metrics() → Hit           (:759-768)
```

`_abandon_failure()`（`:585-612`）的优先级：**`timed_out` → `too_slow`；否则 `step.hold_ms>0 and _best_hold_ms>0` → `hold_short`；否则 `index>0` → `incomplete`；否则 None**。

`reset()`（`:782-802`）只在 `t0 is not None and _hold_since is not None` 时 `_abandon_failure(self._now)`（即 `hold_short`），然后 `index=0, t0=None, _hold_since=None, _best_hold_ms=0, _armed=True`，**不动 `neutral`**。`on_idle()`（`:614-624`）先 `_abandon_failure(self._now)`（`timed_out=False`），再清进度、`neutral=True, _armed=True, _release_since=None, _last_motion=0, _have_last=False`。

### A.4 `TapDetector`（`detectors.py:858-1034`）

Phase 4 已逐行移植（`mobile/src/core/detectors/tap_detector.gd`），本研究只登记与 Phase 5 相关的两点：

- 构造期把 `grace_ms = max(0.0, timeout_grace_ms|150)`、`release_hold_ms = max(0.0, ...|120)`；`ConfigValidator` **不校验** `timeout_grace_ms`（`[VERIFIED: mobile/src/core/config/config_validator.gd 中无此键]`）。
- `on_idle()` 是**空实现**（`detectors.py:937-939`），所以引擎级 idle 对 tap 零影响 —— 这也是 Phase 4 能暂时不移植 idle 计时器的依据，但 Phase 5 必须补上（arc/sequence 依赖它）。

### A.5 `Engine._tick` 的当前分支顺序（`engine.py:248-377`）

```
0  ls_ok = state.ls_mag >= cfg.input.ls_facing_threshold；facing_valid = ls_ok；ls_ok 时 facing = state.ls_angle   (:251-254)
1  if self.paused: rumble.update(now); return                                                                     (:256-260)
2  frame = Frame(now, state, ls_mag, ls_angle, rs_mag, rs_angle, facing, buttons)                                  (:262-271)
3  if _gesture_locked:
     rs_mag < RELEASE_STICK(0.35) → 记 _lock_release_since；满 gesture_release_ms → 对**所有** skills on_idle()、
       解锁；否则保持
     rs_mag >= RELEASE_STICK → _lock_release_since = None
     仍锁着 → rumble.update(now); return                                                                          (:275-289)
4  active_skills = [focus] 或 skills；held_required = {当前按住的、属于某技能 required_buttons 的键}              (:295-301)
5  rs_mag < IDLE_STICK(0.20)：_idle_since 起算；未清过且 ≥ idle_reset_ms → 对 active_skills 逐个 on_idle()；
   _idle_cleared=True；否则 rs_mag ≥ IDLE_STICK 时清 _idle_since/_idle_cleared                                    (:303-314)
6  for active in active_skills:
     a) held_required 非空且该技能不需要其中任何一个 → observe(frame) + abandon(); continue                        (:319-324)
     b) skill.relative_to_ls 且 !ls_ok → observe(frame) + reset(); continue                                        (:326-330)
     c) !_buttons_ok(skill, buttons) → observe(frame) + reset(); continue                                          (:332-338)
     d) hit = detector.update(frame)；None → continue                                                              (:340-342)
     e) _discard_other_claims(active)                                                                              (:346)
     f) (now-last_fire)*1000 < skill.cooldown_ms → continue（静默）                                                  (:348-349)
     g) (now-_last_any_fire)*1000 < global_cooldown_ms → suppressed += 1; continue                                  (:350-352)
     h) last_fire=now; hits+=1; attempts+=1; group_hits+=1; 满 GROUP_SIZE 归零且 groups_done+=1;
        _last_any_fire=now; _record(ok=True,...); _fire(...)                                                       (:354-365)
     i) _gesture_locked=True; _lock_release_since=None; break                                                       (:368-370)
7  _drain_failures(now)                                                                                            (:374)
8  rumble.update(now)                                                                                              (:377)
```

`_buttons_ok`：无要求键 → True；`button_mode == "any"` → any；否则 all（`engine.py:446-452`）。

`[VERIFIED: desktop/padskills/engine.py:248-377, 446-452]`

### A.6 桌面参考里**不存在**的东西（不要凭空造）

- 没有 `on_time_discontinuity` / `on_device_lost`（它们在 `.planning/research/ARCHITECTURE.md` 与 `OnboardingFlow` 里，不在 `Engine`）。
  **Phase 5 的对等契约里不能出现它们**；移动端需要一个「静默清场」入口时，用 `_reset_progress()` 的语义（`abandon()` + `on_idle()` + 清锁/清 idle），并把它标成移动端扩展，不进黄金语料。Phase 8 的 RESIL-01/INPUT-06 再在此基础上加时间不连续与掉线语义。
- 没有 `measured`。`Outcome` 只有 `skill_name/ok/code/message/elapsed_ms/at/detail`（`engine.py:62-76`）。
- 没有「按技能暂停」「按技能启用」以外的开关；`focus`/`paused` 是桌面 GUI 专用。

### A.7 302 项检查的移植口径

本次用「包一层 `check()` 并按测试函数归因」实测出各函数的**运行时断言条数**（合 205）：

| 测试函数 | 条数 | 可移植性 | 说明 |
|---------|-----:|----------|------|
| `test_arc` | 15 | ✅ 检测器 | 弧线成功/失败/边界/幅度/起手 |
| `test_stepover` | 3 | ✅ 检测器 | |
| `test_arc_discrimination` | 5 | ✅ 检测器 | 马赛 vs 踩单车互不误判 |
| `test_arc_direction` | 2 | ✅ 检测器（需变体配置） | `direction=cw` 不在出厂配置里 |
| `test_sequence_heel_to_heel` | 5 | ✅ 检测器 | 含 absolute 模式不该触发 |
| `test_sequence_croqueta` | 30 | ✅ 检测器 | 保持/容差/status/引擎 `_buttons_ok` |
| `test_no_retrigger_while_held` | 4 | ✅ 检测器 | 按住不复触发 |
| `test_idle_reset` | 5 | ✅ 检测器 | 停顿作废 |
| `test_min_duration` | 3 | ✅ 检测器 | |
| `test_failure_diagnostics` | 22 | ✅ 检测器 + 引擎 | 各失败码的归属与「一次尝试只一条」 |
| `test_button_taps` | 18 | ✅ 检测器 + 引擎 | Phase 4 已覆盖大半 |
| `test_engine_gesture_lock` | 8 | ✅ 引擎（`_tick`） | 锁 + idle 计数 |
| `test_engine_facing_and_group` | 7 | ✅ 引擎 | 左摇杆朝向 + 分组 + LB 互斥 |
| `test_geometry` | 8 | ❌ 已有 | 移动端 `test_geometry` + `geometry_golden.json` 覆盖 |
| `test_button_names` | 10 | ❌ 不适用 | SDL `input.button_names`；移动端用 `JoyButtonMap` |
| `test_engine_end_to_end` | 4 | ❌ 不移植 | 250 Hz **墙钟**循环；`abs(frames/0.9-250)<25` 天然 flaky |
| `test_rumble_state_machine` | 12 | ❌ 不移植 | 安卓无手柄马达 |
| `test_config_validation` | 31 | ❌ 已有 | 移动端 `config_corpus` + `config_validator` |
| `test_focus_mode` | 13 | ❌ 桌面特有 | 专项/暂停；只移植 `_reset_progress` 的语义 |
| **合计** | **205** | **可移植 ≈ 127** | 其余 78 条已由其他层覆盖或物理不适用 |

`test_gui_smoke.py` 的 97 条**全部不移植**（GUI / 日志 / 剪贴板 / 鼠标）。

**真正的对等契约 = 上表 ✅ 的 127 条所表达的 14 类行为**，而不是逐条复刻断言。计划应把它转成语料用例，而不是在 GDScript 里抄 127 个 `check()`。

---

## Five-Skill Parity Corpus

### B.1 五个动作（逐字，`shared/skills_config.json`）

| # | 名称 | type | relative_to_ls | required_button | cooldown_ms | 关键阈值 |
|---|------|------|----------------|-----------------|------------:|----------|
| 1 | 马赛回旋 Roulette | arc | true | null | 400 | start 180±65、end 0±80、enter .72/exit .52、angle 70~230、dur 250~600、idle 250、release 120、direction any |
| 2 | 踩单车 Stepover | arc | true | null | 350 | start 0±55、end [90,270]±55、enter .72/exit .52、angle 70~135、dur 250~600、idle 250、release 120 |
| 3 | 磕球过人 Heel-to-Heel | sequence | true | null | 350 | steps [forward, back]、tol 35、enter .65/rel .35、dur 250~600、idle 250、release 150、neutral true |
| 4 | 油炸丸子 La Croqueta | sequence | true | **"L1"→LB** | 450 | steps [{direction:[右,左], hold_ms:350}]、tol **10**、enter .6/rel .3、dur 250~600、idle **350**、release 150 |
| 5 | 绿色搓射 Green Finesse | taps | false | **"RB"** | 450 | button X、400~600、grace 150、release 120、modifier_options [RB,RT] |

全局：`global_cooldown_ms = 60`（`:93`）、`input.ls_facing_threshold = 0.35`（`:76`）、`input.idle_reset_ms = 250`（`:83`）、`input.gesture_release_ms = 150`（`:84`）、`input.poll_hz = 250`（`:74`）。

`[VERIFIED: shared/skills_config.json:74-235]`

### B.2 失败码可达性矩阵（出厂配置）

> 这张表决定语料**能写什么**。不可达的码要么用「变体配置」单独测，要么不写 —— 写一条永远不可能触发的期望，等于给「假绿」留门。

| 码 | 马赛回旋 | 踩单车 | 磕球 | 油炸丸子 | 绿射 | 依据 |
|----|---------|--------|------|----------|------|------|
| `ok` | ✅ | ✅ | ✅ | ✅ | ✅ | 实测 `probe.py` / Phase 4 夹具 |
| `too_fast` | ✅ | ✅ | ✅ | ❌ | ✅ | 油炸丸子要满足 hold 350 才轮到 `elapsed<min(250)` 判定 → 恒不成立（`detectors.py:729-749`） |
| `too_slow` | ✅ | ✅ | ✅（需「持续动但不对」的摆动轨迹） | ✅ | ✅ | 磕球 1.2 s 直停会先撞 idle 250 → `incomplete`（实测 `probe.py`）；必须摆动 |
| `too_short` | ✅ | ✅ | — | — | — | 实测 `probe.py` |
| `wrong_start` | ✅（起点 100°） | ✅（起点 60°，实测 `probe8`） | — | — | — | 起点须在 `tol + claim_margin` 内、`tol` 外 |
| `wrong_end` | ✅（扫掠 70~100° 的窄窗） | ❌ | — | — | — | 实测 `probe2`（扫掠 85° → `停在相对 264°`） |
| `overshoot` | ❌（端点窗口覆盖 70~230） | ❌ | — | — | — | 实测 `probe8`：240° 先撞 `too_fast`；端点窗口 [280,360]∪[0,80] 覆盖扫掠 100~280 |
| `wrong_direction` | ❌（`direction: any`） | ❌ | — | — | — | 需变体配置 |
| `stalled` | ✅ | ✅ | — | — | — | 实测 `probe.py`（转 60° 后推住 400 ms） |
| `incomplete` | — | — | ✅ | — | — | 实测 `probe.py` / `probe8` |
| `hold_short` | — | — | ❌（无 hold 步） | ✅ | ✅（松 RB） | 桌面 `test_failure_diagnostics` 已证 |

**结论（写进计划的硬约束）：**

- 成功标准 2 的五个码（太快/太慢/起点不对/终点不对/保持时间不足）在出厂配置下**全部可达**：太快→马赛/踩单车/绿射；太慢→马赛（1400 ms）；起点不对→马赛/踩单车；终点不对→**只有马赛**且窗口很窄；保持不够→油炸丸子/绿射。
- `overshoot` / `wrong_direction` 必须走**变体配置**（与桌面 `variant()` 同构：只改一个技能，其余不动），并且只放在「检测器层」语料里，不进引擎层语料（变体配置会改变引擎构造）。
- **`too_fast` 对油炸丸子在数学上不可达**，语料里不许出现；否则生成器会永远拿不到期望，最后必然有人去改阈值来「修好」它。

### B.3 语料规模与用例清单

建议三本夹具（全部由 Python 生成，全部 `--check` 逐字节）：

**夹具 1：`shared/golden_detector.json`（检测器层，250 Hz，逐字段全等）**
每例：`{id, skill, config: "shipped"|"variant:<name>", frames: [[t_ms, rs_angle, rs_mag, ["RB"], facing], ...], expect: {hits:[...], failures:[...]}}`

| 组 | 用例 | 条数 |
|----|------|-----:|
| 成功 | 马赛正/反、踩单车正/反、磕球、油炸丸子、绿射（400/600 边界各一） | 8 |
| 失败码 | 上表全部可达码，每码 1~2 条 | 14 |
| 边界 | `min_angle±1°`、`max_angle±1°`、`min_duration±4ms`、`max_duration±4ms`、`tolerance±1°`、`hold_ms±4ms`、tap `400/600±4ms`、`max+grace±4ms` | 16 |
| 起手/认领 | 起点在 `tol` 内/外但在 `claim` 内/外（三个区间各一条）、`start_angle:null` 变体 | 6 |
| 重武装 | `release_hold_ms±4ms` 后再次起手（arc ×1、sequence ×1、tap ×1） | 6 |
| 修饰键 | LB 按下/中途松开（油炸丸子 `hold_short`）、tap RB→RT 切换、首帧已按住 X | 5 |
| **小计** | | **55** |

**夹具 2：`shared/golden_engine.json`（引擎层，250 Hz，`Engine._tick`）**
每例：`{id, config:"shipped"|"synthetic:<name>", ls: [angle,mag], frames, expect:{outcomes:[{skill,ok,code,message,elapsed_ms,at,detail}], counters:{...}}}`

| 组 | 用例 | 条数 |
|----|------|-----:|
| 单动作端到端 | 5 个动作各 1 条成功 + 1 条失败 | 10 |
| 双动作竞争 | 0°→90°（踩单车赢、磕球第一步被丢弃）；180°→380°（马赛赢、其他全清） | 2 |
| 手势锁 | 不回中连做两段弧；回中 150ms±4ms 后解锁 | 3 |
| 逐动作冷却 | 真实 350/400/450 各一条（第二发在冷却内） | 3 |
| 全局冷却 | **合成运行时**（`global_cooldown_ms=1000`）一条；真实 60 一条（证明不可达/静默） | 2 |
| idle 重置 | 归中 250±4ms 清进度；推住不清 | 2 |
| facing 无效 | LS 回中做相对动作 → 零判定；同一轨迹 LS 推住 → 命中 | 2 |
| 修饰键互斥 | 按住 LB 时马赛/踩单车/磕球全被 abandon；油炸丸子照常 | 2 |
| 失败归属 | 同帧两个技能都产失败 → 只留配置里靠前的；失败后别人的进度被清 | 2 |
| 分组 | 10 次命中 → `group_hits=0, groups_done=1` | 1 |
| **小计** | | **29** |

**夹具 3：`shared/golden_decimated.json`（抽稀矩阵）**
对夹具 1+2 的每一条轨迹，生成 120/90/60 Hz 三个变体 + 各自的 `expect`（**由参考引擎重放该变体得到，不是复制 250 Hz 的期望**），并把「与 250 Hz 的差异」显式列出。

- 变体数 = (55 + 29) × 3 = **252** 条回放；
- 每条变体记录：`{rate, frames, expect, vs_250: {codes_equal: bool, drift: [{index, from, to, reason}]}}`；
- 未解释的 drift 一律判红；已登记的 drift 若不再出现也判红（照 Phase 3「记录过时也要删」的规则）。

**总计：84 条 250 Hz 用例 + 252 条抽稀变体。**

> 数量下限要机械钉住（照 Phase 3 的「双层下限」）：检测器 ≥ 50、引擎 ≥ 26、抽稀 ≥ 240。删掉大半语料仍能通过是最常见的假绿。

### B.4 生成器如何驱动参考引擎（可直接照抄的最小 harness）

`Engine.run()` 是 250 Hz **墙钟**循环，不能用于夹具；`Engine._tick(now, state)` 是确定性的单帧入口，Phase 4 的 tap 生成器已经这么做了（`tools/gen_tap_golden.py:553-596`）。本次实测证明它对 arc/sequence 同样成立（`/tmp/p5probe/probe.py`、`probe2.py` 用同一入口复现了桌面 `test_arc` / `test_sequence_*` 的全部结论）。

```python
import io, json, math, sys
from pathlib import Path
sys.path.insert(0, "desktop")
from padskills.config import parse_config
from padskills.engine import Engine
from padskills.input_source import GamepadSource, PadState
from padskills.rumble import RumbleEngine

class _NullSource(GamepadSource):          # 只用于构造，poll() 永不被调用
    name = "空手柄"; layout_source = "夹具"
    def poll(self): return PadState()

class _CollectingEngine(Engine):           # last_outcome 会漏掉同帧中间结果
    def __init__(self, *a, **k):
        super().__init__(*a, **k); self.collected = []
    def _record(self, active, ok, code, message, elapsed_ms, now, detail=""):
        super()._record(active, ok, code, message, elapsed_ms, now, detail)
        self.collected.append(self.last_outcome)

def replay(cfg, frames, ls_angle=0.0, ls_mag=0.9) -> _CollectingEngine:
    """frames: [(t_ms, rs_angle, rs_mag, buttons_tuple, facing)]，4ms 网格。"""
    engine = _CollectingEngine(cfg, _NullSource(),
                               RumbleEngine(None, enabled=False), out=io.StringIO())
    lx, ly = ls_mag * math.sin(math.radians(ls_angle)), -ls_mag * math.cos(math.radians(ls_angle))
    for t_ms, rs_angle, rs_mag, buttons, facing in frames:
        rx = rs_mag * math.sin(math.radians(rs_angle))
        ry = -rs_mag * math.cos(math.radians(rs_angle))
        engine._tick(t_ms / 1000.0,
                     PadState(ls_x=lx, ls_y=ly, rs_x=rx, rs_y=ry, buttons=frozenset(buttons)))
        # facing 是夹具声明、引擎计算；不一致就是夹具写错了，不是引擎错
        assert abs(engine.facing - facing) < 1e-9, (t_ms, engine.facing, facing)
    return engine
```

四条硬规则：

1. **一条轨迹一个 `Engine` 实例**。冷却、`_last_any_fire`、分组、手势锁全在实例里；复用实例会让上一条的锁污染下一条。
2. **`out=io.StringIO()`**：每次命中 `_fire` 都会写一行，不接住会污染 `--check` 输出。
3. **`RumbleEngine(None, enabled=False)`**：`play()` 返回 False 只影响写日志的后缀，不影响 `Outcome`。
4. **`facing` 由夹具显式给出**，不要试图从 `ls_angle` 反推：`Engine` 内部只在 `ls_ok` 时更新 `self.facing`，而夹具要能构造「LS 推住但 facing 已冻结」的边界。夹具里的 `facing` 是**期望的引擎状态**，生成器必须断言它与引擎实际 `facing` 一致（不一致就是夹具写错了）。

### B.5 轨迹从哪来：合成是**必须**，不是偷懒

- 250 Hz 的「录制」只存在于桌面版。手机是事件驱动（125 Hz 量级），**不存在**一条 250 Hz 的真实手机轨迹。
- 边界用例（`min_angle ± 1°`、`max_duration ± 4 ms`）无法用真人手搓出来；只有合成轨迹能精确落在边界上。
- 路线图的「由 Python 侧生成，绝不手写」约束的是**期望值**：任何一条 `expect` 必须由参考实现跑出来，不能人手写「我觉得这里是 too_fast」。

**建议的两层来源：**

> 先纠正一个计划里容易照抄的细节：路线图写的「边界 ±1 ms」在 250 Hz 的 4 ms 网格上**不可表示** —— 任何时长都只能是 4 的整数倍。语料用 **±4 ms（一帧）**，并在计划里注明这是网格分辨率的下限；`±1°` 可以精确做到（角度是连续量，采样点的角度按扫掠速度确定）。

1. **主语料 = 合成**（4 ms 网格、可参数化），覆盖成功 / 失败 / 边界 / 仲裁；
2. **补充 = 真机录制回放**（3~5 条，每动作一条），从 Phase 4 的 `input_log.txt` 里裁出活动窗口，转成 `PadState` 空间后作为「真实抖动 + 不规则时间戳」的冒烟用例。它不进 ±1° 边界组，只证明「真实时间戳也能跑通且码一致」。

> 实机日志的时间戳是不规则的（`t=12345` 这类整数毫秒），`Frame.now` 直接用它即可 —— 引擎从不假设均匀网格，`motion_min_delta_deg` 也是按角度而不是按帧数判定的（`detectors.py:308-314`）。

### B.6 生成器的六条不变量（否则 0 差异是假的）

1. **源哈希进夹具**：`detectors.py` / `engine.py` / `config.py` / `skills_config.json` 的 SHA-256 写进 `source.sha256`（照 `gen_tap_golden.py:52-57, 635-638`）。任一变化 → `--check` 立即红，强制重新推导。
2. **id 唯一**（`gen_tap_golden.py:628-632` 已有先例）。
3. **规范字节**：`json.dumps(..., ensure_ascii=False, indent=2, sort_keys=True) + "\n"`，`--check` 逐字节比较且**绝不写盘**。
4. **禁止取整刀口**：生成器必须断言每个会被 `%.0f` 格式化的实测值（`swept`、`end_rel`、`elapsed_ms`、`held_ms`、`interval_ms`）距离最近的 `.5` 边界 ≥ 1e-6。否则 Python 与 GDScript 的 1-ulp 差异会在 `%.0f` 上翻一位，产生「看起来像移植 bug」的假分歧。
5. **数量下限**：三类夹具各自的 `cases` 条数必须 ≥ 计划里写死的常量（检测器 50 / 引擎 26 / 抽稀 240），并在 GDScript 侧先断言 `size()` 再回放。
6. **每组至少一条「反向对照」**：例如「同一轨迹在 absolute 模式下不触发」「LS 回中时同一轨迹零判定」。只有正向用例的语料无法区分「判定正确」与「什么都没判」。

---

## Decimation 250 → 120 / 90 / 60 Hz

### C.1 正确规则（本次实测确定）

> **抽取样本，不抽取时间戳；每个按钮变化必须至少保留一个「变化后」的样本。**

```
period_ms = 1000 / hz
boundaries = 0, period_ms, 2*period_ms, ...
selected = { argmin_i |t_i - boundary| , 对每个 boundary（并列取更早的样本） }
for each i where buttons[i] != buttons[i-1]:
    selected.add( first j with t_j >= t_i )        # 按钮沿保底
frames = [ (t_i, state_i) for i in sorted(selected) ]   # 时间戳是 t_i，不是 boundary
```

实测证据（同一批轨迹，250 Hz 基线 vs 三种抽稀）：

| 规则 | 396 ms tap | 604 ms tap | `wrong_end` 文案 | 弧线 gap=124 ms 重起手 |
|------|-----------|-----------|------------------|------------------------|
| 250 Hz 基线 | `too_fast`@396 | `too_slow`@604 | `停在相对 264°` | `[too_short, too_fast]` |
| 最近样本 + **原始时间戳** + 沿保底 | `too_fast`@396 ✅ | `too_slow`@604 ✅ | 数字不同、码相同 ✅ | `[too_short]`（少一条）⚠️ |
| 最近样本 + 原始时间戳 + **无**沿保底 | `too_slow`@752 ❌ | `too_slow`@752（碰巧同码） | — | — |
| 最近样本 + **网格时间戳** | `ok`@400 ❌ | `ok`@600 ❌ | — | — |

`[VERIFIED: /tmp/p5probe/probe4.py, probe5.py, probe6.py]`

**为什么网格时间戳必错：** tap 的窗口是 `min <= interval <= max`（两端包含），400/600 是**包含端点**的；把 396 量化到 400 就把它从「太快」搬进了「成功」。120 Hz（8.33 ms）同样会翻，因为 396/8.33 = 47.5 → 最近的边界是 48×8.33 = 400。**任何 ≥60 Hz 的网格化都会翻转 ±1 帧以内的边界值。**

**为什么沿保底必错不可接受：** 4 ms 按压在 60 Hz 下只覆盖 1/4 个帧周期；最近样本法可能一次都选不中它。丢了按下沿 = 检测器根本不知道有第二下 = 整个判定从 `too_fast` 变成超时 `too_slow`。

### C.2 哪些阈值真的有风险（量化清单）

| 阈值 | 60 Hz 下的帧数 | 量化误差 | 风险等级 | 实测/推理 |
|------|---------------:|---------|---------|-----------|
| `release_hold_ms = 120`（arc/sequence/tap） | 7.2 | ≤16.7 ms 延迟重新武装 | **高** | 实测：124 ms 重起手在 60 Hz 少一条判定（`probe6`） |
| `gesture_release_ms = 150` | 9.0 | ≤16.7 ms 延迟解锁 | 中 | 解锁只影响「下一发最早何时开始」，回中通常远长于 150 ms |
| tap `min_interval=400` / `max=600` | 24 / 36 | ≤16.7 ms | **高（边界包含）** | 实测：仅当保留原始时间戳时不漂 |
| tap `timeout_grace=150`（600+150=750） | 45 | ≤16.7 ms | 中 | 超时是严格大于；750 附近 ±1 帧可能翻 `too_slow` 的**分支**（文案不同、码相同） |
| `min_duration_ms = 250` / `max_duration_ms = 600` | 15 / 36 | ≤16.7 ms | 中 | 实测 gap=136 时 90 Hz 出 `ok`、250 Hz 出 `too_fast`（`probe6`） |
| 步 `hold_ms = 350` | 21 | ≤16.7 ms | 中 | 350±17 仍远大于 `min_duration` 250，不会翻转成败 |
| `idle_timeout_ms = 250 / 350` | 15 / 21 | ≤16.7 ms | 低 | 是「静置」判据，手势中的间隔远小于它 |
| `idle_reset_ms = 250`（引擎） | 15 | ≤16.7 ms | 低 | 同上 |
| `global_cooldown_ms = 60` | 3.6 | ≤16.7 ms | **零（不可达）** | 实测：手势锁 150 ms 恒先拦住（`probe2`） |
| `enter/exit/release_threshold`（幅度） | — | 采样点值本身 | 低 | 幅度不随时间量化；唯一影响是「越过阈值的那一帧」晚 ≤1 帧 |

**逐样本常量审计**（项目级 CONCERNS #7 点名的那批，本次逐条核对）：

| 常量 | 位置 | 是否率依赖 | 结论 |
|------|------|-----------|------|
| `motion_delta = 2.0°` | `detectors.py:310, 637` | 否（比较的是**参考角**，不是相邻帧） | 参考角只在差值 ≥2° 时刷新，刷新间隔 = 2°/角速度；60 Hz 下最多晚一帧（16.7 ms），对 `idle 250~350 ms` 无实质影响。**不需要重写成角速度。** |
| `abs(mag - _last_mag) >= 0.05` | `:311, 638` | 弱 | 60 Hz 下每帧幅度变化更大 → 更容易判「在动」→ 只会让 `stalled` 更保守，不会误报 |
| `swept >= 5.0` | `:340, 364` | 否（度） | 率无关 |
| `_last_path_t >= 0.008` | `:317` | 是 | **只影响 `path_detail()` 显示**，不进判定；60 Hz 下每帧都追加，64 点上限 |
| `_step_lo/_hi` 的 `hi-lo < 3.0` | `:553` | 是 | 只影响 `summary` 文案，不进判定 |
| `report_min_angle = max(20, 0.35*min_angle)` | `:187` | 否（度） | 率无关 |

> 结论：项目级研究里「`>= 2°` 在 60 Hz 下几乎每个样本都成立 → 中途停住不再触发」的担忧，**在参考实现的具体写法下不成立**（它比的是冻结参考角，不是相邻帧）。真正需要证据的是 `release_hold_ms`，不是 `motion_delta`。这一条应写进计划的「已知分歧的裁决记录」，避免执行者去改一个不需要改的常量。

### C.3 「不漂移」到底指什么（三层契约）

| 层 | 比较内容 | 容差 | 理由 |
|----|---------|------|------|
| L1 250 Hz 黄金 | `(skill, ok, code, message, elapsed_ms, at, detail)` 全字段 | 0（逐字） | 4 ms 网格上所有**时长**都是整数毫秒；角度类实测值由 B.6 #4 的「禁止取整刀口」保证不在 `.5` 上分叉 |
| L2 抽稀 | `(skill, code)` 序列 | 0（必须完全一致） | 判定码是产品语义；不同码 = 用户看到不同结论 |
| L3 抽稀 | `measured`（swept/end_rel/hold/interval/elapsed） | ≤ 1 帧周期（60 Hz 16.7 ms / 1°） | 触发帧与起手帧都可能晚一帧；实测 `maxΔelapsed = 8 ms` |
| L4 抽稀 | `message` / `detail` / `summary` | **不比较** | 文案嵌实测值（`停在相对 264°`、`采样 N 点`），必然不同 |

**「同码」不是「同文案」**：`too_slow` 有两个产出分支（第二下太慢 vs 一直没第二下），文案不同但码相同。在 L2 上它们不可区分 —— 这是可接受的，因为产品只承诺「太慢」；但 L1 必须区分，所以 250 Hz 语料要各写一条。

### C.4 出现漂移时的调整流程（证据优先）

1. **先判定漂移类别**：
   - **A 类：整条判定消失/多出**（如 gap=124 的 `[too_short]` vs `[too_short, too_fast]`）→ 属于时序契约破裂，必须处理。
   - **B 类：码不同但条数相同**（如 `too_fast` → `ok`）→ 边界契约破裂，必须处理。
   - **C 类：码相同、`measured` 差 ≤1 帧** → 可接受，登记为容差。
   - **D 类：文案不同** → 不比较，不处理。
2. **A/B 类的处置顺序**（不许跳步）：
   1. 先确认抽稀实现符合 C.1（时间戳是否被网格化？按钮沿是否保底？）。本次实测里 90% 的「漂移」都是这两条写错。
   2. 再确认轨迹本身是否落在阈值 ±1 帧内。若在，**把该用例标成「边界带」，允许 ±1 帧的差异并记录**（这是采样定理的必然结果，不是缺陷）。
   3. 只有在「远离阈值仍漂移」时，才允许动阈值；动之前必须同时给出：原始 250 Hz 期望、漂移率、受影响的动作、以及**桌面端 302 项仍全绿**的证明。
3. **哪些阈值 1:1 冻结、哪些可以带证据调整**：

| 阈值 | 能否改 | 理由 |
|------|--------|------|
| `min_angle` / `max_angle` / `start_tolerance` / `end_tolerance` / `tolerance_deg` | **冻结** | 是产品手感定义，与采样率无关（度） |
| `enter_threshold` / `exit_threshold` / `release_threshold` | **冻结** | 幅度阈值，与采样率无关 |
| `min_duration_ms` / `max_duration_ms` / `hold_ms` | 冻结（除证据流程） | 毫秒定义；改动会同时改桌面手感 |
| `release_hold_ms` | **可带证据微调**（唯一候选） | 它是「重新武装」的内部延迟，不是用户可感知的动作定义；124 ms 的实测缺口可用 +1 帧（120→136）覆盖，但**必须先证明桌面 302 项不受影响**（桌面测试用 120，改常量会改默认行为） |
| `global_cooldown_ms` | **不需要动** | 出厂配置下不可达 |
| `idle_timeout_ms` / `idle_reset_ms` / `gesture_release_ms` | 冻结 | 250/150 远大于一帧，量化影响 <7% |

> **强烈建议：本阶段不改任何阈值。** 把 gap=124 这类用例登记为「边界带已知差异」，并在计划里写明「Phase 6 的真机循环若在 60 Hz 下感到『第二发被吞』，再带真机数据回来改 `release_hold_ms`」。这符合路线图「先用夹具证明漂移，再带着证据放宽」。

### C.5 `tools/decimate_trace.py` 的形态

```
python3 tools/decimate_trace.py --check        # 只比对
python3 tools/decimate_trace.py                # 重新生成夹具
```

输入：`shared/golden_detector.json` + `shared/golden_engine.json`
输出：`shared/golden_decimated.json`

每条输出记录：

```json
{
  "id": "det_roulette_ok@60",
  "source_id": "det_roulette_ok",
  "rate_hz": 60,
  "rule": "nearest+keep_ts+force_button_edges",
  "frames": [[0, 0.0, 0.0, [], 0.0], [4, 180.0, 0.92, ["RB"], 0.0], ["..."]],
  "expect": {"hits": [], "failures": []},
  "vs_250": {"codes_equal": true, "max_abs_elapsed_delta_ms": 8.0, "drift": []}
}
```

工具自身的断言（缺一不可）：

1. `rate_hz ∈ {120, 90, 60}`，且 `1000/rate` 不是整数时用 float 边界，禁止取整；
2. `frames` 的时间戳必须严格递增，且**每个时间戳都能在源轨迹里原样找到**（证明没有网格化）；
3. 每个按钮变化在 `frames` 里都有对应的「变化后」样本；
4. `expect` 必须由参考引擎重放 `frames` 得到（工具内部 import 参考实现，与 B.4 同一个 harness）；
5. `vs_250.drift` 非空时，必须能在 `shared/decimation_allowlist.json` 找到同 id、同 rate 的条目且带非空 `reason`；反之 allowlist 里有的条目若不再漂移，也判红。

---

## Mobile Runtime Shape

### D.1 类布局（全部在 `mobile/src/core/`，零引擎依赖）

| 文件 | 类 | 职责 | 与桌面参考的对应 |
|------|-----|------|------------------|
| `core/frame.gd` | `Frame`（扩展） | `now: float`(秒)、`buttons: Dictionary`、`rs_mag`、`rs_angle`、`ls_mag`、`ls_angle`、`facing` | `detectors.py:27-37`。检测器只读其中 5 个（`now/buttons/rs_mag/rs_angle/facing`，E4）；`ls_mag/ls_angle` 只被引擎读；`facing` **由引擎每帧写入**，调用方传进来的值会被覆盖 |
| `core/detectors/arc_detector.gd` | `ArcDetector` | `detectors.py:125-446` 逐行 | 新增：`measured` 构造 + `last_path()` |
| `core/detectors/sequence_detector.gd` | `SequenceDetector` | `detectors.py:453-853` 逐行 | 新增：`_step_t`（每步完成时刻）+ `measured` |
| `core/detectors/build_detector.gd` | `DetectorFactory` | `skill.kind` → 具体类 | `detectors.py:1039-1046` |
| `core/active_skill.gd` | `ActiveSkill` | `skill` + `detector` + `last_fire/hits/attempts/group_hits/groups_done/failures/last_outcome` | `engine.py:78-89` |
| `core/gesture_engine.gd` | `GestureEngine` | `_tick` 的完整移植 + `pop_outcomes()` + `set_layout_confirmed()` + `reset_progress()` + `status_for(i)` + `cooldown_remaining_ms(i)` | `engine.py:92-452` |
| `core/tap_runtime.gd` | `TapRuntime extends GestureEngine` | 单技能门面，构造签名不变 | Phase 4 兼容层 |
| `core/hit.gd` / `core/failure.gd` | `Hit` / `Failure` | 新增第 4 个可选参数 `measured: Dictionary = {}` | 位置参数向后兼容 |

`Frame` 的字段划分是本次实测结论，不是猜测：`grep -n "frame\." desktop/padskills/detectors.py` 的全部命中只有 `now`、`rs_angle`、`rs_mag`、`facing`、`buttons`（E4）。所以**检测器可见字段 = 5**；`ls_mag`/`ls_angle` 只给引擎用，`facing` 也由引擎每帧写。Phase 4 的 `Frame` 只有 `now`/`buttons`，新增的 5 个字段全部有默认值（`0.0`），旧测试的构造方式因此不需要改。

### D.2 `GestureEngine.tick()` 的分支顺序（必须与 `engine.py:248-377` 同构）

```
1  if not layout_confirmed: return                     ← 移动端独有硬门，保持在最前（Phase 4 已定）
2  ls_ok = frame.ls_mag >= config.input.ls_facing_threshold
   facing_valid = ls_ok; ls_ok 时 facing = frame.ls_angle
   frame.facing = facing                              ← 引擎写入，检测器只读（对应 engine.py:262-271）
3  if _gesture_locked:
       frame.rs_mag < RELEASE_STICK(0.35) → 记 _lock_release_since；满 gesture_release_ms →
           对**全部** skills on_idle()、解锁；否则 return
       else → _lock_release_since = null
4  held_required = {b : b ∈ 某技能 required_buttons 且 b ∈ frame.buttons}
5  if frame.rs_mag < IDLE_STICK(0.20):
       _idle_since 起算；未清过且 ≥ idle_reset_ms → 对全部 skills on_idle()；_idle_cleared = true
   else: _idle_since = null; _idle_cleared = false
6  for active in skills:
       a) held_required 非空且该技能不需要其中任何一个 → observe + abandon; continue
       b) skill.relative_to_ls 且 !ls_ok              → observe + reset;    continue
       c) !buttons_ok(skill)                          → observe + reset;    continue
       d) hit = detector.update(frame); null → continue
       e) _discard_other_claims(active)               ← 在冷却之前
       f) (now-last_fire)*1000 < skill.cooldown_ms    → continue（静默）
       g) (now-_last_any_fire)*1000 < global_cooldown → suppressed += 1; continue
       h) 计数 + 分组 + _record(ok) + (可选) rumble sink
       i) _gesture_locked = true; _lock_release_since = null; break
7  _drain_failures(now)   ← 配置顺序第一条；取到后 _discard_other_claims(owner)
8  (可选) rumble sink.update(now) —— 本阶段注入 no-op
```

**移动端差异只允许三处，且必须写进类文档与测试：**

| 差异 | 桌面 | 移动端 | 理由 |
|------|------|--------|------|
| 布局硬门 | 无 | `layout_confirmed == false` → 第一早退 | Phase 4 SC4；无头可证「零判定」 |
| 结果通道 | `last_outcome` 单槽 + `outcome_seq` | `Array[Outcome]` 队列 + `pop_outcomes()` + 单调 `seq` | 桌面同帧两条会吞掉第一条；移动端结构上不丢 |
| 清场入口 | `set_focus` / `set_paused` → `_reset_progress` | 公开 `reset_progress()`（同语义），供 Phase 8 的断连/时间不连续使用 | 桌面没有 `on_device_lost`；不发明新语义，只暴露既有清场 |

**不要移植**：`focus`、`paused`、`_fire` 的震动播发、`_render_debug`、`_write`。震动在 Phase 10 之前只有 no-op sink。

### D.3 与 Phase 4 的 1533 条断言的兼容性（硬要求）

Phase 4 的套件大量使用 `TapRuntime.new(skill, global_cooldown_ms, gesture_release_ms, layout_confirmed[, group_size])` 与 `TapRuntime.GROUP_SIZE` / `select_taps_skill`。推荐路径：

```
class_name GestureEngine extends RefCounted
    const GROUP_SIZE := 10
    func _init(p_config: AppConfig, p_layout_confirmed := false, p_group_size := GROUP_SIZE)

class_name TapRuntime extends GestureEngine
    func _init(p_skill, p_global_cooldown_ms, p_gesture_release_ms,
               p_layout_confirmed := false, p_group_size := GROUP_SIZE)
        # 造一个只含该 skill 的 AppConfig，注入 global_cooldown / gesture_release，
        # idle_reset_ms 与 ls_facing_threshold 用出厂默认（250 / 0.35）
        super._init(synthetic_config, p_layout_confirmed, p_group_size)
    static func select_taps_skill(config) -> Skill   # 原样保留
```

**为什么旧断言会继续通过（逐条论证，不是希望）：**

1. `Frame` 的 `rs_mag` 默认 `0.0` → 手势锁的 `rs_mag < RELEASE_STICK` 恒真 → 退化成 Phase 4 的「固定 150 ms 解锁」，`rt_gesture_lock` / `rt_release_hold_rearm` 不变。
2. `rs_mag = 0` → 引擎 idle 计时器在第一次满 `idle_reset_ms`（250 ms）时调一次 `on_idle()`，之后 `_idle_cleared` 保持，直到摇杆被推动才会再次触发；`TapDetector.on_idle()` 是空实现 → `rt_*` 全部不变。
3. 单技能 → `held_required` 只可能含该技能自己的 require 键；`_discard_other_claims` 无对象。
4. `_check_relative_skill_disabled` 断言「relative tap 技能零判定」：旧实现是**构造期禁用**，新实现是**运行期 `!ls_ok`**。旧测试的帧不带 LS（`ls_mag` 默认 0）→ `ls_ok=false` → 仍然零判定。**行为保持，机制改变**：该测试的注释必须同步改写（断言本身一条不动）。
5. `suppressed` 语义不变（逐动作静默 / 全局 +1）。

**若某条旧断言因此变红**：先怀疑新引擎（锁/idle/discard 的顺序），不要改断言。Phase 4 的规则「新增反例必须做变异验证」在这里同样适用：删掉锁、删掉 discard、改一个分支顺序，都必须让新套件变红。

### D.4 纯核心与组合根

- 新文件全部落在 `mobile/src/core/`，受 `tools/lint_core_purity.py` 的 14 条规则约束（`Input.` / `Time.` / `Node` / `FileAccess` / `print(` / `OS.` / `Engine.` / `DisplayServer` / `get_tree(` / `SceneTree` / `ResourceLoader` / `Resource` / `@tool` / `outer_layer_dep`）。
- **唯一**的引擎绑定处仍是 `mobile/src/ui/main.gd` 与 `mobile/src/input/pad_sampler.gd`。Phase 5 在 `main.gd` 里新增的只有：把 `PadStateBuffer` 的 raw 轴 + `AxisMapping` + `Calibration` 变成 `Frame.rs_mag/rs_angle/ls_mag/ls_angle`（`facing` 由引擎写）。
- `AxisMapping` 目前只有 `snapshot_rs()`（`axis_mapping.gd:76-86`）；需要新增 `snapshot_ls()`（同一顺序：normalize → normalize → deadzone），或把两者抽成 `_snapshot(raw, x_idx, y_idx, center_x, center_y, scale_x, scale_y, sign_x, sign_y, dz)`。**禁止**让 `main.gd` 自己写一份「减中点除量程」——那是两套校准语义的开始。
- 采样侧：`PadStateBuffer` 已有 `axis_value(i)`，`main.gd` 用它组 raw 数组即可；不要新增轮询通道（INPUT-05）。

### D.5 `measured{}` 的字段表（JUDGE-05，Phase 7 的隐藏关键路径）

**Arc 成功**

```json
{"kind":"arc","start_angle_deg":180.0,"start_rel_deg":180.0,"end_angle_deg":20.0,
 "end_rel_deg":20.0,"swept_deg":200.0,"elapsed_ms":500.0,"samples":126,
 "direction_sign":1,"target":{"min_angle":70,"max_angle":230,"start_target":180,
 "start_tolerance":65,"end_targets":[0],"end_tolerance":80,"min_ms":250,"max_ms":600}}
```

**Arc 失败**：同上 + `"fail":{"code":"wrong_end","end_rel_deg":264.0,"nearest_target_deg":0.0,"distance_deg":96.0,"tolerance_deg":80}`（距离与容差必须与 `message` 里的数字同源，**不得二次计算**）。

**Sequence 成功/失败**

```json
{"kind":"sequence","elapsed_ms":332.0,"base_deg":90.0,"tolerance_deg":35.0,
 "steps":[{"label":"前","required_hold_ms":0,"actual_hold_ms":0,"t_done_ms":250,
           "angle_lo_deg":0.4,"angle_hi_deg":0.4,"angle_avg_deg":0.4},
          {"label":"后","required_hold_ms":0,"actual_hold_ms":0,"t_done_ms":332,
           "angle_lo_deg":180.0,"angle_hi_deg":180.0,"angle_avg_deg":180.0}]}
```

**Tap**：`{"kind":"taps","interval_ms":448.0,"window":{"min_ms":400,"max_ms":600},"button":"X","modifier":"RB"}`。

**今天缺什么（必须在移动端补，桌面端不动）**

| 字段 | Arc | Sequence | Tap | 补法 |
|------|-----|----------|-----|------|
| 起止角 / 扫掠 | ✅ `start_angle/start_rel/end_rel/acc` | ✅ `_step_lo/_hi` | n/a | 直接读 |
| 每步耗时 | n/a | ❌ **无** | n/a | 在 `index += 1` 时记 `_step_t[index] = now`（纯增量，判定不变） |
| 保持时长 | n/a | ✅ `_best_hold_ms`（但被清零） | n/a | 在成功/失败构造 `measured` 时先取 `fired_hold_ms`（`detectors.py:754` 已经这么做） |
| 失败落点 | ✅ 文案里有，字段没有 | ✅ 文案里有 | ✅ | 从同一批局部变量填 `measured.fail`，**不许重新算** |
| 轨迹 | ✅ `_path`（64 点 @8ms） | ❌ | n/a | 可选：暴露 `last_path()` 给 Phase 7 的高亮 |

**关键纪律：`measured` 只能由检测器在产生 `Hit`/`Failure` 的那一刻填。** 让 UI 从 `message` 里正则抠数字，是最容易在改文案时静默坏掉的做法。

**`measured` 没有跨语言 oracle**：桌面参考不产出它，因此它不进 250 Hz 黄金语料的逐字比较。它的正确性由移动端**独立断言**证明：用已知参数的合成轨迹，断言 `swept` 与设定值差 <1°、`t_done_ms` 与轨迹变化点差 <1 帧、`actual_hold_ms` 与设定 hold 差 <1 帧。计划里必须为此单独列一条任务，否则 `measured` 会成为「有字段、没人验」的装饰。

### D.6 给 Phase 6 留的两个钩子

Phase 6 的「待触发/冷却可见」（LOOP-03）需要引擎暴露：

- `state_of(i) -> StringName`：`idle`（armed 且无进度）/ `tracking`（active 或 index>0）/ `locked`（`_gesture_locked`）/ `cooldown`（`now - last_fire < skill.cooldown_ms`）；
- `cooldown_remaining_ms(i, now) -> float`。

这两个是**只读派生**，不进判定、不进黄金语料；现在留出接口，Phase 6 不需要改引擎内部。

---

## Left Stick Mapping and Profile Migration

### E.1 现状（缺口证据）

```gdscript
	# 本页不区分左右摇杆：用户只被要求推右摇杆，左摇杆保持未映射。
	mapping.ls_x_index = -1
	mapping.ls_y_index = -1
```

`[VERIFIED: mobile/src/core/input_setup.gd:338-340]`

后果链（逐条已核实）：

1. `AxisMapping.from_dict` 对 `ls` 传 `allow_unmapped=true`（`axis_mapping.gd:123-129, 163`），所以旧档案**能加载**；
2. `has_ls()` 为假（`axis_mapping.gd:34-35`）；
3. 引擎里 `ls_ok = frame.ls_mag >= 0.35` 恒假 → 4 个 `relative_to_ls` 技能永远走 `observe + reset` 分支（`engine.py:326-330`）；
4. 用户看到的是「推右摇杆完全没反应」，且没有任何错误提示 —— 正是本项目最贵的一类静默失败。

### E.2 必须新增的四件事

| # | 内容 | 落点 |
|---|------|------|
| 1 | **LS 轴对识别**：候选仍是 `PAIRS`（`input_setup.gd:32-37`）；RS 对确定后，LS 对 = 最近窗口内 `min(span_x, span_y)` 次高且 ≥ `MIN_PAIR_TRAVEL` 的那一对，且**不得与 RS 对相同** | `InputSetup.active_pair()` 旁新增 `ls_pair()` |
| 2 | **LS 符号**：`Calibration.normalize` 最后乘 sign，且 `angle_of` 用 `atan2(x, -y)` → 「推上」必须得到**负的 y**、「推右」必须得到**正的 x**。所以：向上推时该 Y 轴读数为负 → `ls_y_sign=+1`，为正 → `-1`；向右推时 X 轴读数为正 → `ls_x_sign=+1`，为负 → `-1`。必须由用户「向上推」这个已知方向确认，不能猜 | `InputSetup` 新增 `ls_x_sign/ls_y_sign` + `confirm_ls_up()` |
| 3 | **LS 校准**：`Calibration` 增加 `ls_center_x/y`、`ls_scale_x/y`（与 RS 同构，先减中点 → 再除量程 → 最后乘符号） | `calibration.gd` + `InputSetup.build_profile()` |
| 4 | **`snapshot_ls()`**：与 `snapshot_rs()` 完全同构 | `axis_mapping.gd` |

**符号为什么不能用「极值方向」推断**：用户被要求「四个方向都推到底」以测满量程时，min 与 max 都会出现，极值本身不含方向信息。必须有一个**已知方向**的单次观测。三种可选做法（按推荐度排序）：

| 方案 | 做法 | 代价 | 风险 |
|------|------|------|------|
| A（推荐） | 页面加一行「左摇杆向上推一下」，取那一刻该对 Y 轴的位移符号；若检测到的位移在 X 轴，显示「推的是左右，请向上推」 | 一行文案 + 一个 `_ls_up_armed` 标志 | 用户推错方向 → 明确提示，不静默 |
| B | 复用现有的十字键左右/上下翻符号，但**分成两组**（RS 一组、LS 一组） | 四个按键语义、UI 变复杂 | 用户不知道自己在翻哪根杆 |
| C | 与 RS 共用符号 | 零成本 | **错**：两只摇杆的 Y 轴接反可以独立发生（Phase 2 实测 RS 的 `axis 2 = -1.000` 就是右手柄独有的） |

### E.3 迁移规则（旧档案必须整份失效，不许部分恢复）

沿用 04-11 已验证的机制：

1. `InputSetup.build_profile()` 写入 `quality.ls_ready = true`（与 `range_ready` 同一层）；
2. `DeviceProfile.can_enter_practice()` 追加 `if not _ls_ready_marker(): return false`；
3. `DeviceProfile.SCHEMA_VERSION` 从 `1` 升到 `2`（`device_profile.gd:24`），`from_dict` 对 `schema_version != 2` 直接报 `unsupported_schema` 并返回 null（`device_profile.gd:154-160` 已有这条逻辑，只改常量）。

**为什么两件事都要做：**

- 只升版本：`Calibration.from_dict` 若把 `ls_*` 做成可选，缺失时会落默认 `scale=1.0 / center=0` —— 这正是 04-11 修掉的「默认校准看起来像真校准」；
- 只加标记：`from_dict` 仍会把 `ls=-1` 的旧档案恢复成「合法对象」，任何绕过 `can_enter_practice` 的路径（测试、诊断页、将来的多档案）都能拿到一份不可用的映射。

**代价（必须写进计划）**：`ProfileStore.load_all()` 对非法条目是**整份丢弃并删文件**（Phase 4 决定），所以升级后用户会丢掉 RS 校准，需要重走一次设置页（约 20 秒）。这是一次性的、可接受的，且比「进练习后四个动作全无反应」便宜得多。

**迁移的机械证明（无头）**：
- 用 04-11 时期的真实档案字节（`ls=-1`、`schema_version=1`）喂 `DeviceProfile.from_dict` → 必须返回 null 且错误码 `unsupported_schema`；
- 新档案（`ls` 齐全 + `ls_ready=true`）→ `can_enter_practice() == true`；
- 新档案但 `ls_ready` 缺失 → false；
- `ls=-1` 但 `ls_ready=true`（自相矛盾）→ false（`has_ls()` 检查）。

### E.4 真机上的设置页流程（最小改动）

现有单页（`A 保存 / B 清空 / 十字键翻 X·Y / LB·RB 换轴对 / Start 换布局`，`input_setup_screen.gd:62`）只需增加两行显示 + 一个提示：

```
右摇杆：轴 2/3  符号 +/+  量程 2.00/2.00   ✓
左摇杆：轴 0/1  符号 +/+  向上推一下确认方向
```

- 左摇杆未识别前，`%Help` 显示「推一下左摇杆（向上）」；识别后显示量程；
- `can_save()` 变为 `range_ready() and ls_ready()`；
- B 清空时 LS 状态一起清（与现有 X/Y 符号的行为一致）。

> 这是 Phase 5 唯一必要的 UI 改动。动作选择器、轨迹绘制、时序条都属于 Phase 6/7。

---

## Verification Architecture

### V.1 测试基础设施

| 层 | 框架 | 配置文件 | 快跑 | 全跑 |
|----|------|----------|------|------|
| 桌面参考（只读） | 自建 `check()` 脚本 | 无 | `bash tools/check_desktop.sh`（约 1.6 s） | 同左（302 项） |
| 移动端核心 | Godot 4.7.2 headless + 自建 Reporter | `mobile/tests/core_runner.gd` 的 `SUITES` 字典 | `bash mobile/tools/test-core.sh`（18 套件 / 1533 断言） | 同左 + 看门狗 180 s |
| 黄金夹具 | Python 生成器 `--check` | `tools/gen_*_golden.py` | `python3 tools/gen_tap_golden.py --check`（现有）/ `gen_gesture_golden.py --check`（新增） | 同上 |
| 架构边界 | `tools/lint_core_purity.py` | `mobile/docs/CORE.md` 互锁 | `python3 tools/lint_core_purity.py mobile/src/core` | `python3 tools/test_lint_core_purity.py`（56 项自测） |

本次实测基线（Phase 5 开工前必须仍是这些数）：

```
bash tools/check_desktop.sh          → 302 项检查全部通过，名称与基线逐项一致
bash mobile/tools/test-core.sh       → TESTS_SUITES=18 / TESTS_ASSERTIONS=1533 / TESTS_DONE failures=0
python3 tools/gen_tap_golden.py --check → detector 12 条、runtime 6 条
```

### V.2 需求 → 测试矩阵（自动 vs 人工）

| Req | 行为 | 类型 | 自动命令 | 现有文件？ |
|-----|------|------|----------|-----------|
| JUDGE-01 | 三类检测器纯状态机、无场景树 | 架构 + 单元 | `python3 tools/lint_core_purity.py mobile/src/core` + `test_arc/sequence/tap_detector` 套件 | ❌ Wave 0 |
| JUDGE-02 | 5 个动作可识别 | 单元（夹具回放） | `test_gesture_golden` 套件 + `gen_gesture_golden.py --check` | ❌ Wave 0 |
| JUDGE-03 | 判定序列与桌面一致 | 单元（夹具回放） | 同上，哨兵 `GESTURE_GOLDEN cases=N mismatches=0` | ❌ Wave 0 |
| JUDGE-04 | 五类失败原因 | 单元 + 真机 | 夹具（每码 ≥1 条）+ D5-3 人工 | ❌ / 人工 |
| JUDGE-05 | `measured{}` | 单元 | `test_measured` 套件（按已知轨迹断言） | ❌ Wave 0 |
| JUDGE-06 | 仲裁语义 | 单元（引擎夹具） | `GESTURE_RUNTIME cases=N mismatches=0` | ❌ Wave 0 |
| JUDGE-07 | 抽稀不漂移 | 单元（夹具矩阵） | `DECIMATION rates=3 cases=N mismatches=0` | ❌ Wave 0 |
| — | 左摇杆映射 + 迁移 | 单元 | `test_input_setup` 扩展 + `test_device_profile` 扩展 | ✅ 扩展 |
| — | 组合根接线（raw → Frame） | 集成（无头） | `test_practice_wiring`（新） | ❌ |
| — | 真机 5 动作 / 5 失败码 / 延迟 | 人工 | D5-2 / D5-3 / D5-7 | 人工 |

### V.3 0 差异的机械化（缺一条就是假绿）

1. **`--check` 只读**：`gen_gesture_golden.py --check` 重新推导后逐字节比较，绝不写盘（照 `gen_tap_golden.py:681-709`）。
2. **源哈希**：夹具内嵌 `detectors.py` / `engine.py` / `config.py` / `skills_config.json` 的 SHA-256；任一变化 → 红。
3. **正向哨兵**（打印在 `r.complete()` 之前，照 Phase 4 决定）：
   - `GESTURE_GOLDEN cases=84 mismatches=0`
   - `GESTURE_RUNTIME cases=29 mismatches=0`
   - `MEASURED cases=N mismatches=0`
   - `DECIMATION rates=3 cases=252 mismatches=0`
   - 每个哨兵的 `cases` 必须 ≥ 计划写死的常量，`mismatches` 只统计真实差异。
4. **`test-core.sh` 新增四条 grep**（照 `TAP_GOLDEN_*` 的写法，`cases=[1-9][0-9]*` 不可省）。
5. **数量下限双层**：GDScript 侧先断言 `fixture["cases"].size() >= N`，再回放。
6. **变异验证**（每条新反例都要做一次）：删手势锁 → `GESTURE_RUNTIME` 必红；删 `_discard_other_claims` → 竞争用例必红；把 `observe`/`reset` 顺序颠倒 → `hold_short` 用例必红；把抽稀的时间戳改成网格 → `DECIMATION` 必红；去掉按钮沿保底 → tap 边界必红。
7. **漂移白名单双向**：未登记的漂移判红；白名单里已不漂移的条目也判红。

### V.4 真机清单（Phase 5 最小集）

| ID | 步骤 | 判据（可抄进 ACCEPTANCE） |
|----|------|--------------------------|
| D5-0 | 卸载旧包 → 安装新包 → 首启 | 设置页出现「左摇杆：轴 N/M 向上推一下确认方向」 |
| D5-1 | 推右摇杆四方向 → 推左摇杆**向上** → 推左摇杆四方向 → A | `INPUT_SETUP` 行同时出现 `rs=` 与 `ls=`，`ls_ready=1`；进练习 |
| D5-2 | 依次做 5 个动作各 3 次 | 每次恰好 1 条 `OUTCOME`，`skill=` 与动作匹配，`ok=1` |
| D5-3 | 针对每个码做一次错误动作：太快（马赛 60 ms）/ 太慢（马赛 1400 ms）/ 起点不对（从 100° 起手）/ 终点不对（从 180° 只扫 85°）/ 保持不够（油炸丸子推 200 ms 就松） | 5 条 `code` 分别为 `too_fast/too_slow/wrong_start/wrong_end/hold_short`，**不需要看日志就能在屏幕上读到中文原因** |
| D5-4 | 一次「从正前扫到右侧 90°」 | 恰好 1 条 `OUTCOME`（踩单车），没有伴随的 `incomplete` |
| D5-5 | 连续两次同一动作，中间回中 200 ms / 100 ms | 200 ms → 2 条；100 ms → 1 条（锁未解锁） |
| D5-6 | 从 `input_log.txt` 里裁出 D5-2 的活动窗口，跑 `tools/analyze_input_log.py` | 输出活动窗口 `p50/p95/max`（回答 04-VERIFICATION 的 `dt95=234.7` 缺口） |
| D5-7 | 感知延迟 | 挥完到横幅出现 ≤ 1 个用户可感知瞬间（不量化；Phase 7 才做秒表级验收） |
| D5-8（承接） | 第二只手柄（DualSense 或另一只 Xbox）连上 | 复用门拒绝、回到设置页重探（Phase 4 的 SC3 拒绝面） |

> D5-2/3/4 的证据全部来自 **`OUTCOME` 日志行 + `adb exec-out screencap`**，不需要实时截图；这与 04-10/04-11 已建立的证据通道一致。

### V.5 输入日志要补什么

现状（`mobile/src/input/input_log.gd`）只有两种行：

```
t=<ms> dev=<d> btn=<i> name=<canonical> down=<0|1>
t=<ms> dev=<d> axis=<i> v=<x.xxx>
```

`[VERIFIED: mobile/src/input/input_log.gd:9-11, 61-66]`

Phase 5 追加**一种**行（写在组合根 drain 到 `Outcome` 时，不进 core）：

```
t=<ms> OUTCOME skill=<name> ok=<0|1> code=<code> elapsed=<ms> seq=<n> measured=<k=v;k=v;...>
```

- 写点：**唯一**的 `pop_outcomes()` 调用在 `practice_screen._process`（`mobile/src/ui/practice_screen.gd:76`）。因此 `InputLog.outcome(...)` 必须在那个循环里、`show_outcome` 之前调用一次（`ui → input` 的依赖方向合法）。**不要**为了写日志在 `main.gd` 里再 drain 一次：第二个消费者会把队列取空，屏幕就什么都看不到了。
- `measured` 用 `k=v` 分号串，值 `%.1f`；这是给人和脚本看的，不要求可逆解析（要可逆就走 Phase 8 的持久化格式）。
- 失败时同时记 `code` 与 `measured.fail`，这样 D5-3 的「五个码各一次」可以在一条 `adb exec-out cat` 里逐行核对。

**活动窗口 `dt95` 的解法**：不改运行时，新增离线脚本 `tools/analyze_input_log.py`：

1. 以 `OUTCOME` 行为窗口右界，向前找最近一次「连续轴变化」的起点（间隔 > 100 ms 视为断开）；
2. 只统计窗口内的 `axis=` 行时间差 → `p50/p95/max`；
3. 同时输出该窗口内每根轴的 `min/max`（判断是否有扳机轴跳变污染）。

这比在 `PadStateBuffer` 里加环形缓冲更简单，也回答了 04-VERIFICATION 的 accepted gap #3。

---

## Risks and Open Questions

### R.1 移植最可能分叉的十个点（按风险排序）

| # | 风险 | 为什么危险 | 防线 |
|---|------|-----------|------|
| 1 | **分支顺序**（尤其 arc 的 `wrong_start → direction → overshoot → stalled → too_slow → too_fast`） | 顺序只影响「报哪条原因」，不影响「是否触发」；写反了失败码会互相冒充，黄金语料能抓到但很难定位 | 每个失败码单独一条夹具；`status()` 也进夹具 |
| 2 | **`_discard_other_claims` 的两处调用**（命中后、失败 drain 后） | 只做一处会让「同一手势两个判定」在真机上偶发 | 竞争用例 + 失败归属用例各一条；变异验证 |
| 3 | **`facing` 冻结时机**（arc 在 `active` 变真那一刻；sequence 在 `t0` 建立那一刻；中途 LS 改变不改基准） | 写活成「每帧读 LS」会让跑动中的动作全部错位 | 夹具里让 LS 中途换向，断言仍以起手基准判定 |
| 4 | **`reset()` vs `abandon()` vs `on_idle()` 的三套语义** | `reset` 产 `hold_short`、`abandon` 静默、`on_idle` 产 `incomplete`/`hold_short` 并重新武装 | 三套各一条断言；LS 回中用 `reset`（会产 hold_short），修饰键松开也用 `reset` |
| 5 | **Sequence `reset()` 不动 `neutral`** | 改成 `neutral=True` 会让「按住 L1 抖动一帧」变成反复触发（桌面 `test_no_retrigger_while_held` 的原始 bug） | 该用例移植成夹具 |
| 6 | **`_best_hold_ms` 的清零时机**（成功前取出、`_abort` 清、`reset` 清） | 清早了 `summary` 永远 0 ms；清晚了失败文案报错值 | `hold_short` 与成功摘要各一条 |
| 7 | **浮点比较**：`%.0f` 的取整刀口、`fposmod` 端点 | 1-ulp 差异在 `.5` 上翻一位，看起来像移植 bug | 生成器断言「距 .5 边界 ≥1e-6」；`Geometry` 已有黄金表 |
| 8 | **`timeout_grace_ms` 的 `max(0.0, ...)`**（校验器不查它） | 负值会让超时提前 | 一条负值合成用例 |
| 9 | **`relative_to_ls` 与 `ls_ok` 的先后**（在 `_buttons_ok` 之前） | 顺序反了会让「LS 回中 + 按住 L1」的语义不同（是否产 `hold_short`） | 一条「LS 回中时按住 L1」的夹具 |
| 10 | **抽稀实现把时间戳网格化** | 边界码整体翻转，且看起来「很合理」 | `decimate_trace.py` 断言时间戳原样来自源轨迹 |

### R.2 时序敏感的桌面检查（CI 可能 flaky）

- `test_engine_end_to_end`（4 条）：用 `time.perf_counter()` 跑 0.9 s 墙钟，断言 `abs(frames/0.9 - 250) < 25` 与「震动后端收到 1 次」。Phase 1 已记录它敏感（`.planning/STATE.md`：`时序敏感的 test_engine_end_to_end 不在 01-04 修复`）。
- `test_rumble_state_machine` 的 `dt < 0.01`（非阻塞断言，12 条里 1 条）。
- 两者都**不在**移植范围（A.7），所以 Phase 5 不会放大这个风险；但每次改完都要跑 `check_desktop.sh`，偶发红时先重跑再判断。

### R.3 如果现在不设计 `measured{}`，Phase 6/7/8 的返工面

| 下游 | 依赖的字段 | 没有它的后果 |
|------|-----------|-------------|
| Phase 6 LOOP-03「待触发/冷却可见」 | `state_of(i)` / `cooldown_remaining_ms(i)` | 要么改引擎内部，要么在 UI 里重算冷却（两套真相） |
| Phase 7 FEEDBACK-02 时序条 | `elapsed_ms` + `target.min/max` | UI 只能显示「太快」，说不出「快了 180 ms」 |
| Phase 7 失败点高亮 / 逐步拆解 | `measured.fail` + `steps[].t_done_ms` | 只能重放原始轨迹再算一遍（两套判定逻辑） |
| Phase 8 DATA-02 最近 N 次 | `measured` 的稳定 JSON schema | 已存的历史没有度量，之后补等于历史不可比 |
| Phase 7 FEEDBACK-03 实时轨迹 | `ArcDetector._path`（或 UI 自采样） | 可行但会与检测器看到的角度有偏差（校准/死区不同源） |

### R.4 开放问题

1. **实机 `dt95` 的活动窗口值到底是多少？**
   - 已知：全窗口 `dt95=234.7` 含 idle 空档（04-VERIFICATION）。
   - 未知：一次典型搓招（300–600 ms）内的真实间隔分布。
   - 处理：D5-6 + `tools/analyze_input_log.py`；若活动窗口 `p95 > 25 ms`（<40 Hz），抽稀矩阵要多跑一档 40 Hz 并重新评估 `release_hold_ms`。`[ASSUMED: 需要测量]`

2. **第二只手柄（DualSense）的左摇杆轴对与符号是否与 Xbox 相同？**
   - 已知：Phase 2 只实测了 Xbox（`axis 2 = -1.000` 是右手柄的符号）。
   - 未知：DualSense 的 LS 轴序号/符号。
   - 处理：D5-8；在此之前 `INPUT-01` 保持 partial。`[ASSUMED]`

3. **`release_hold_ms=120` 在真机 60 Hz 下的实际缺口有多大？**
   - 已知：合成轨迹上 124 ms 会丢一条判定（E22）。
   - 未知：真人重试间隔的分布（几乎不可能精准落在 120–136 ms）。
   - 处理：先不改；把它登记为「边界带已知差异」，Phase 6 真机循环若报「第二发没反应」再带数据回来。`[ASSUMED: 真人重试间隔]`

4. **`global_cooldown_ms` 是否要保留在移动端？**
   - 已知：出厂配置下不可达（E21）。
   - 处理：**保留并移植**（它是 `skills_config.json` 的一部分，且换成合成配置时可达），但不为它写「真实配置」的期望；计划里注明「不可达，仅合成运行时可达」。

5. **`Frame` 的 `ls_mag/ls_angle` 会不会诱使后来的人让检测器直接读 LS？**
   - 已知：检测器只需要 `facing`（E4）；`ls_*` 是给引擎算 `facing` 的。
   - 处理：类文档写明「检测器**只准**读 `facing`，不准读 `ls_*`」；夹具里放一条「LS 中途换向仍以起手基准判定」的用例，让违规实现立刻变红。

6. **`TapRuntime` 的 `relative_to_ls` 护栏**：从「构造期禁用」改成「运行期 `!ls_ok`」是否算弱化断言？
   - 结论：不算。旧测试的帧不带 LS，行为完全一致；但**测试注释必须改**，否则下一个人会以为护栏还在构造期。计划里要显式列这条「注释同步」。

### R.5 假设清单（`[ASSUMED]`，需用户确认或真机测量）

| # | 假设 | 在哪一节 | 错了会怎样 |
|---|------|---------|-----------|
| A1 | 手机活动窗口的输入间隔 p95 不会差到 <40 Hz | §R.4-1 / V.5 | 抽稀矩阵要补 40 Hz 档，`release_hold_ms` 的边界带会变宽 |
| A2 | DualSense 的左摇杆轴对可由同一个「向上推」流程识别 | §E.2 | 需要 OEM 专用的轴对候选或人工手选 |
| A3 | 真人重试间隔不会密集落在 120–136 ms | §R.4-3 / C.4 | 60 Hz 下会偶发「第二发无反应」，需要带证据调 `release_hold_ms` |
| A4 | 出厂配置的 5 个动作就是 v1 的全部动作集（不新增技能） | §B.1 / B.3 | 语料规模与可达性矩阵要重算 |
| A5 | `shared/skills_config.json` 在本阶段不会被改阈值 | §C.4 / C7 | 所有黄金夹具必须重新生成，桌面 302 项也要重跑 |

---

## Recommendations for the Planner

### 建议的 Wave 划分（每个 Wave 结束都能独立验收）

**Wave 1 — 参考冻结与语料骨架（无 UI、无设备）**
- 冻结基线：跑 `check_desktop.sh`（302）、`test-core.sh`（18/1533）、`gen_tap_golden.py --check`，把三个数字写进计划。
- `tools/gen_gesture_golden.py` 骨架：读 `shared/skills_config.json`、`_tick` harness（B.4）、源哈希、`--check` 只读、规范字节。
- 先落 10 条「已知结论」用例（5 成功 + 5 失败码），证明 harness 能复现桌面语义。
- 验收：`python3 tools/gen_gesture_golden.py --check` 通过；10 条期望与桌面套件里对应断言的结论逐条一致（不是「看着像」）。

**Wave 2 — 三类检测器（纯 core）**
- `Frame` 扩 5 字段；`ArcDetector` / `SequenceDetector` 逐行移植；`build_detector`。
- 语料补到 §B.3 的 55 条（含边界、起手区间、重武装、修饰键）。
- `test_gesture_detector` 套件回放 + `GESTURE_GOLDEN` 哨兵；`test-core.sh` 加 grep。
- 验收：哨兵 `cases≥50 mismatches=0`；变异验证（把 `_release_failure` 的两个分支顺序对调 → 必红）。

**Wave 3 — `GestureEngine`（仲裁）**
- `ActiveSkill` + `GestureEngine`（D.2 顺序）；`TapRuntime` 改为子类；`measured` 初版（arc/tap）。
- 引擎语料 29 条 + `GESTURE_RUNTIME` 哨兵；`test-core.sh` 加 grep。
- 验收：`GESTURE_RUNTIME cases≥26 mismatches=0`；Phase 4 的 1533 条一条不少仍全绿。

**Wave 4 — 抽稀矩阵**
- `tools/decimate_trace.py` + `shared/golden_decimated.json` + `shared/decimation_allowlist.json`（初始为空）。
- `DECIMATION rates=3 cases≥240 mismatches=0`；把 C.4 的「边界带」用例登记进 allowlist（若实测有）。
- 验收：三种速率全部满足 L2（码序列相同）；每个未登记差异都会让闸门红。

**Wave 5 — 左摇杆与档案迁移**
- `Calibration` 增 LS 四字段；`AxisMapping.snapshot_ls()`；`InputSetup` 的 LS 对/符号/量程；`quality.ls_ready` + `SCHEMA_VERSION=2`；设置页两行 + 「向上推」提示。
- 单测：旧档案（v1 / ls=-1）必须被拒；新档案必须可用；`snapshot_ls` 与 `snapshot_rs` 同构（同一组 raw 输入下角度一致）。
- 验收：`test_input_setup` / `test_device_profile` 扩展全绿；lint 仍 `LINT_OK`。

**Wave 6 — 组合根接线 + 真机**
- `main.gd`：建 `GestureEngine`（全部启用技能）、组 `Frame`（`now` / `buttons` / `rs_mag` / `rs_angle` / `ls_mag` / `ls_angle`；`facing` 由引擎写）、drain 后写 `OUTCOME` 日志、横幅显示 `Outcome.skill_name`。
- `InputLog.outcome()` + `tools/analyze_input_log.py`。
- 构建 APK，走 D5-0…D5-8。
- 验收：D5-2/3/4/5 有日志证据；D5-6 产出活动窗口分位数；D5-8 明确记录「已测/未测」。

### 计划边界（避免一个 PLAN 同时改三层）

| 边界 | 允许改 | 禁止 |
|------|--------|------|
| 检测器计划 | `mobile/src/core/detectors/**`、`frame.gd`、`hit.gd`、`failure.gd`、夹具、生成器 | 碰 `engine`/UI/设备层 |
| 引擎计划 | `core/gesture_engine.gd`、`core/active_skill.gd`、`tap_runtime.gd`、引擎语料 | 碰检测器内部（除 `measured` 钩子） |
| 抽稀计划 | `tools/decimate_trace.py`、`golden_decimated.json`、`allowlist` | 改任何阈值 |
| 左摇杆计划 | `calibration.gd`、`axis_mapping.gd`、`input_setup.gd`、`device_profile.gd`、设置页 | 碰判定链 |
| 接线计划 | `main.gd`、`practice_screen.gd`、`input_log.gd`、`analyze_input_log.py` | 碰 core 语义 |

### 五条不可协商的验收

1. `bash tools/check_desktop.sh` → 302 全绿（本阶段**零**改动 `desktop/padskills/*.py`）。
2. `bash mobile/tools/test-core.sh` → `TESTS_DONE failures=0`，且 `TESTS_ASSERTIONS` 严格大于 1533。
3. 四条新哨兵全部出现且 `mismatches=0`，`cases` 达到下限。
4. `python3 tools/lint_core_purity.py mobile/src/core` → `LINT_OK`（新文件不得引入任何禁用 token）。
5. 真机 D5-2/3 有 `OUTCOME` 日志证据；D5-8 未执行时**不得**声称 INPUT-01 完整。

---

## RESEARCH COMPLETE

