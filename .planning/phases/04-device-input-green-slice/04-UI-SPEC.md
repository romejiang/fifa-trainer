---
phase: "4"
slug: "device-input-green-slice"
status: draft
shadcn_initialized: false
preset: none
created: "2026-11-05"
---

# Phase 4 — UI Design Contract（设备输入层 + 绿色搓射竖切）

> 本阶段的视觉与交互契约。由 `gsd-ui-researcher` 依据**已实现代码**推导并锁定，由 `gsd-ui-checker` 校验。

## 0. 这份契约的性质

**它描述已经存在的实现，而不是重新设计。** 波次 5 的 `main.gd` / `main.tscn` /
`onboarding_screen.gd` / `onboarding_screen.tscn` 已在 `main` 上落地并通过闸门 A；本文件把
它们的行为写成可验收的条款，并把波次 6 尚未实现的练习屏（S12–S14）锁在同一套条款下。

三条推导原则：

1. **实现即基线。** 与设计意图不一致的地方（绝对坐标 vs 锚点/容器、`待机` vs
   `等待第一下`、键名 `X` 在 PlayStation 布局下的泄漏）在 §12 逐条记为 gap，不据此要求
   重构，也不悄悄改写成"设计如此"。
2. **只写能被机械检查或真机截图检查的话。** 每个数值都来自 `.tscn`、`.gd` 常量或
   `project.godot`；每个"做了什么"都对应一个 `grep` 或一条 D 项。
3. **零触摸、无动画、无音效、无震动。** 本阶段不存在任何触屏控件、`Tween`、
   `AudioStreamPlayer` 或马达调用；这不是"暂未实现"，是范围声明。

---

## Design System

| Property | Value |
|----------|-------|
| Tool | none —— 无设计系统包。Godot `4.7.2-stable` 内置 `Control` 主题 + 一套固定 `.tscn` |
| Preset | not applicable |
| Component library | none —— 只用 `Control` / `Label` / `ProgressBar` 三种节点 |
| Icon library | none —— 图标即字形：`✓`(U+2713) / `✗`(U+2717) / `×`(U+00D7) / `□`(U+25A1) / `△`(U+25B3) / `○`(U+25CB) |
| Font | `res://assets/fonts/AppFont.tres` —— `FontVariation`，`base_font` = `NotoSansSC-Subset.ttf`（876 字形），`fallbacks` = `NotoSansSymbols2-Subset.ttf`（提供 `✗`） |
| Engine | `4.7.2-stable`（`project.godot` 的 `config/features` 写死 `"4.7"`；用 4.8 打开会静默改写，属 P-01 违规） |
| Viewport | `1280×720`，`window/stretch/mode="canvas_items"`，`aspect` 未设置（= `keep`，非 16:9 加黑边） |
| Orientation | `window/handheld/orientation=0`（`SCREEN_LANDSCAPE`，显式写出防漂移） |
| Keep screen on | `window/energy_saving/keep_screen_on=true` |

**禁止引入**：Theme 资源、`Button` / `LineEdit` / `TouchScreenButton`、shader、
`AnimationPlayer`、`Tween`、任何第三方 UI 插件。字号与颜色一律用
`theme_override_*` 就地声明。

**为什么没有 shadcn 门**：这不是 React/Next/Vite 工程，没有 `components.json`，
没有可枚举的组件包。§1 的 Node Contract 直接用 `ls` + `.tscn` 的真值建立清单。

---

## 1. Node Contract（节点词汇表）

Enumerated by `ls mobile/src/ui/*.gd mobile/src/ui/*.tscn | grep -v '\.uid$'` — **4 个文件**
（波次 6 后为 7 个：新增 `practice_screen.gd` / `practice_screen.tscn` / `result_banner.gd`）—
`godot@4.7.2-stable` — 2026-11-05.
场景内 `unique_name_in_owner` 计数：`main.tscn` = 3，`onboarding_screen.tscn` = 8，
`grep -c 'type="Button"' mobile/src/ui/*.tscn` = **0**。

| 节点 | 类型 | 字号 | 归属 | 内容来源 | 备注 |
|------|------|------|------|----------|------|
| `%ConfigError` | `Label` | 32 | `main.tscn` / `main.gd` | `ConfigResult.to_text()`，或 `"配置里没有唯一的 taps 动作：只练绿色搓射需要恰好一条启用的 taps 动作。"` | 全屏错误屏；`autowrap_mode = 2`；四边留白 32 |
| `%Onboarding` | `onboarding_screen.tscn` 实例 | — | `main.tscn` / `main.gd` | 子屏自己渲染 | 全屏锚点 `anchors_preset = 15` |
| `%Practice` | `Control` | — | `main.tscn` / `main.gd` | 练习屏的容器 | 初始 `visible = false`；**不是**练习屏本身 |
| `%Practice/Placeholder` | `Label` | 40 | `main.tscn` | 静态 `"可以开始练习了"` | 波次 6 必须 `queue_free()`；它没有任何数据源 |
| `%Title` | `Label` | 40 | `onboarding_screen.tscn` | 每状态一句标题 | 带高 80 |
| `%Step` | `Label` | 32 | `onboarding_screen.tscn` | `"第 n/4 步"` / `"方向 n/4"` | 右对齐（`horizontal_alignment = 2`） |
| `%Body` | `Label` | 28 | `onboarding_screen.tscn` | 每状态一句正文 | `autowrap_mode = 2`，带高 120 |
| `%BigHint` | `Label` | 72 | `onboarding_screen.tscn` | 每状态一句大字指令 | `autowrap_mode = 2`，带高 124 |
| `%Hint` | `Label` | 28 | `onboarding_screen.tscn` | 补充说明；**失败原因优先** | `autowrap_mode = 2`，带高 104 |
| `%Meter` | `ProgressBar` | — | `onboarding_screen.tscn` | `_update_meter(value, max)` | `show_percentage = false`；填充色不动 |
| `%Options` | `Label` | 32 | `onboarding_screen.tscn` | 布局选择提示 / 索引不符提示 | **Label，永远不是 Button** |
| `%Footer` | `Label` | 28 | `onboarding_screen.tscn` | `"设备：<device_name>"`；设备名为空时为空串 | 带高 56 |
| `%ActionName` | `Label` | 40 | `practice_screen.tscn`（待实现） | `runtime.skill_name` | 带高 80 |
| `%Hint`（练习） | `Label` | 32 | `practice_screen.tscn`（待实现） | 由注入的 `layout` 决定的三选一常量 | 带高 88，`autowrap_mode = 2` |
| `%LiveMs` | `Label` | 32 | `practice_screen.tscn`（待实现） | `runtime.status()`（idle 例外见 §12-G3） | 10 Hz 节流；带高 40 |
| `%SuccessCount` | `Label` | 28 | `practice_screen.tscn`（待实现） | `"成功 %d / %d" % [hits, attempts]` | 只在字符串变化时赋值；带高 40 |
| `%DebugPanel` | `Label` | 28 | `practice_screen.tscn`（待实现） | 纯 ASCII 诊断行（§7） | 带高 80；**不加中文** |
| `%ResultBanner` | `Control` + `result_banner.gd` | — | `practice_screen.tscn`（待实现） | 无背景、无边框，纯布局容器 | 占据屏幕中部 |
| `%Title`（横幅） | `Label` | **72** | `%ResultBanner` 下 | `"✓ 做对了"` / `"✗ 没做对"` | **必须** `parent="ResultBanner"` |
| `%Reason` | `Label` | **40** | `%ResultBanner` 下 | `outcome.detail`（成功）/ `outcome.message`（失败） | **必须** `parent="ResultBanner"`；`autowrap_mode = 2` |

**节点命名冲突说明**：引导屏与练习屏各有一个 `%Title`。它们分属两个场景，
`unique_name_in_owner` 的作用域是各自场景，互不影响；`result_banner.gd` 里的
`%Title` 解析到 `practice_screen.tscn` 的 `ResultBanner/Title`，会遮蔽练习屏根下的
同名节点——因此练习屏根节点**不得**再叫 `Title`（它叫 `ActionName`）。

**`%SuccessCount` 的格式**：取 `"成功 %d / %d"`，不是计划字面里的裸 `"%d / %d"`。
1 m 外一个没有标签的 `3 / 5` 没有语义；加了「成功」两个字才读得懂。数据来源不变
（`runtime.hits` / `runtime.attempts`），变化检测规则不变，也不触发任何闸门 grep。

---

## 2. Layout Contract（1280×720 条带网格）

实现基线是**设计视口内的绝对偏移**（`layout_mode = 0`，`anchors_preset = 15` 的根
`Control` 之下），不是容器布局。这是已验收的写法：`canvas_items` + 基准视口
`1280×720` + 默认 `aspect = keep` 让像素语义在 16:9 上稳定，非 16:9 由引擎加黑边。
本契约接受该基线（gap 见 §12-G2），但**新节点必须落在下列条带内**，不得自创新的边距。

### 2.1 横向

| 边 | 值 | 说明 |
|----|----|------|
| 左安全边 | `x = 48` | 全部文本节点左边界 |
| 右安全边 | `x = 1232` | 右侧 = `1280 − 48` |
| 可用宽度 | `1184` | 所有 `autowrap` 断行按此宽度 |
| 例外 | `%Step` 占 `1040…1232`（右对齐）；`%ConfigError` 用 `32…1248`（错误屏四边 32） | — |

### 2.2 纵向条带 —— 引导屏（`onboarding_screen.tscn`，已实现）

| 节点 | y 起 | y 止 | 带高 |
|------|------|------|------|
| `%Title` / `%Step` | 24 | 104 | 80 |
| `%Body` | 112 | 232 | 120 |
| `%BigHint` | 236 | 360 | 124 |
| `%Hint` | 368 | 472 | 104 |
| `%Meter` | 480 | 520 | 40 |
| `%Options` | 532 | 640 | 108 |
| `%Footer` | 648 | 704 | 56 |

### 2.3 纵向条带 —— 练习屏（`practice_screen.tscn`，波次 6 必须遵守）

沿用同一套节奏（24 顶边距、48 左右边、8 的带间隙、16 底边距）：

| 节点 | y 起 | y 止 | 带高 | 依据 |
|------|------|------|------|------|
| `%ActionName` | 24 | 104 | 80 | 与 `%Title` 同带 |
| `%Hint` | 112 | 200 | 88 | 32 px × 2 行 = 76.8 |
| `%LiveMs` | 208 | 248 | 40 | 32 px × 1 行 = 38.4 |
| `%SuccessCount` | 256 | 296 | 40 | 28 px × 1 行 = 33.6 |
| `%ResultBanner` | 304 | 584 | 280 | 容器；无背景 |
| └ `%Title`（相对容器） | 0 | 128 | 128 | 72 px，含 `✓/✗` 时行框 ≈122.3 |
| └ `%Reason`（相对容器） | 136 | 280 | 144 | 40 px × 3 行 = 144 |
| `%DebugPanel` | 600 | 680 | 80 | 28 px × 2 行 = 67.2 |

**禁则**：`%DebugPanel` 与横幅不得重叠（584 < 600）；横幅清空后**不得**改变任何带高
（固定条带 → 无布局跳动）；不得为横幅加 `Panel` / `NinePatchRect` 背景。

---

## 3. Screen State Contract（S0–S15 + S99）

`OnboardingFlow` 只有 16 个状态常量（无 `config_error`：配置错误发生在状态机构造之前，
`main.gd` 用自己的 `%ConfigError` 屏，理由见 §11）。S12/S13/S14 不是三个状态机状态——
运行时只有 `STATE_PRACTICE`，三者是**练习屏的显示子态**，由 `runtime.status()` 与
横幅的 `_remaining` 派生，不新增第二套状态机。

| S# | Flow 状态 | 进入触发 | 屏幕（逐字文案 / 节点） | 离开条件（唯一推进者） | 失败面 |
|----|-----------|----------|--------------------------|------------------------|--------|
| S0 | `BOOT`（无 flow 状态） | 应用启动 → `main._ready()` | `%ConfigError` 与 `%Practice` 初始 `visible = false`，`%Onboarding` 默认可见；`_ready()` 在**同一帧**决定最终显示哪一屏 | 配置 ok → S1；失败 → S99 | `ConfigStore` 读不到/解析失败；`select_taps_skill` 返回 null |
| S1 | `NO_DEVICE` | 启动后 `get_connected_joypads()` 为空 | Title 40「没有检测到手柄：先按任意键唤醒」；Body 28「打开手柄电源 → 长按配对键 → 在系统蓝牙里选择它 → 按手柄任意键唤醒」；BigHint 72「等待手柄」；Hint 28「安卓蓝牙手柄在收到第一次输入前不会出现在设备列表里。」；Meter 归零；Footer 空 | 设备列表非空 → S2（`_on_device_list_changed`） | 手柄始终不出现（配对失败/蓝牙关闭）。本屏**不采样**，D0 停止条件不适用；屏幕上没有第二步可点——这是零触摸设计的有意结果 |
| S2 | `DEVICE_READY` | 设备列表从空变非空，或换设备 | Title 40「已连接：<device_name>」；Body 28「按任意键继续」；BigHint 72「手柄已就绪」；Footer「设备：<device_name>」 | **任意**按钮边沿 → `on_any_button()` → S3 | 同一设备的重复列表若被误判为"换设备"会清进度；由 `buffer.device != devices[0]` 守卫 |
| S2a | `REUSE_REST` | `ProfileStore.find(key)` 命中且 `offer_profile()` 返回 true | Title 40「先松手，验证上次档案」；Body 28「双手离开摇杆」；BigHint 72「保持不动」；Hint 28「正在验证上次档案的静止基线」 | 18 帧静止样本（每轴峰峰值 < 0.15）→ `submit_reuse_rest` → S2b | 用户手没离开：窗口清空、Hint 改「双手离开摇杆」、不提交；`events_motion` 不增长 ≥60 帧且窗口仍空 → D0 停止屏 |
| S2b | `REUSE_CHECK` | S2a 提交成功 | Title 40「验证上次档案」；Body 28「按 B 跳过验证，重新探测」；BigHint 72 = 方向大字（「把右摇杆推到最右，按住」/「…最下…」）；Hint 28「只验右与下两步；不一致会自动丢弃档案并重探四步。」 | 只验 `right` + `down` 两步；两步与档案四项 index+sign 全等 → S11；不等 → S8（`reuse_mismatch`） | 实测与档案不符 → 整份丢弃（`reuse_rejected = true`）、文案「这次实测与上次记录的轴不一致，已丢弃旧档案，需要重新探测四步。」；任一步位移不足/两轴同动 → S8 |
| S3 | `PROBE_INTRO` | S2 按任意键；或复用成功后重探 | Title 40「轴探测」；Body 28「接下来测四步，只推右摇杆；左摇杆不要动」；BigHint 72「按 A 开始」；Hint 28「四步记录每根轴的序号与符号；校准随后修正量程。」 | 索引 **0** 按下 → `begin_probe()` → S3a（**不能**直达 S4） | 按到非 0 键：忽略，不前进（屏幕无反馈，属已知交互空档） |
| S3a | `PROBE_REST` | `begin_probe()` | Title 40「静止基线」；Body 28「双手离开摇杆」；BigHint 72「保持不动」；Hint 28「正在采集静止基线（约 0.3 秒）」；Meter 0→18 | 18 帧静止样本通过峰峰值门 → `submit_rest_baseline` → S4 | 手在动 → 清窗口、Hint 改「双手离开摇杆」、不提交；样本 < 15 帧 → `probe_failure_message = "静止样本不够，请保持不动"` |
| S4 | `PROBE_UP` | S3a 提交成功 | Title 40「轴探测」；Step 32「第 1/4 步」；Body 28「把右摇杆推到最上，按住」；BigHint 72「推到底并保持不动」；Meter 0→18 | 先等任一轴位移 ≥ 0.5，再收 18 帧 → `ProbeEvaluator.evaluate_step` → `submit_probe_step` → S5（ok）或 S8 | `not_enough_samples` / `displacement_too_small` / `ambiguous_axes`；位移门槛 0.5 |
| S5 | `PROBE_RIGHT` | S4 ok | Step 32「第 2/4 步」；Body 28「把右摇杆推到最右，按住」；其余同 S4 | 同 S4 → S6 或 S8 | 同上 |
| S6 | `PROBE_DOWN` | S5 ok | Step 32「第 3/4 步」；Body 28「把右摇杆推到最下，按住」 | 同 S4 → S7 或 S8 | 同上 |
| S7 | `PROBE_LEFT` | S6 ok | Step 32「第 4/4 步」；Body 28「把右摇杆推到最左，按住」 | 同 S4；四步齐后 `validate_cross` → S9（通过）或 S8 | 交叉校验：`same_axis_up_right` / `vertical_not_opposed` / `horizontal_not_opposed`；失败保留已完成四步中未被否定的数据 |
| S8 | `PROBE_FAILED` | 任一步被拒、交叉校验失败、复用被拒 | Title 40「这一步没通过」；Body 28「按 B 重来这一步」；BigHint 72「重来」；Hint 28 = `flow.probe_failure_message`（非空时**逐字**） | 索引 **1** 按下 → `retry_probe_step()` → `retry_state` 指向的那一步（`probe_up` 时回 S3a 或 S4） | 消息为空时回退「按 B 重来这一步」；**不得**清空已完成步骤（只有 `retry_state == probe_up` 才整轮重探） |
| S9 | `CALIBRATE_CENTER` | S7 交叉校验通过 | Title 40「中点校准」；Body 28「双手离开摇杆，保持不动」；BigHint 72「保持 0.4 秒」；Hint 28 = 失败原因（非空）或「正在采集中点…」；Meter 0→24 | 24 帧静止样本 → `center_from_samples` → `submit_calibration_center` → S10 | 手放上去/漂移 → `ok == false`，**留在本屏**且原因渲染在 `%Hint`；`flow.mapping() == null` → Hint「轴映射缺失，无法校准：请按 B 重新探测」并停住 |
| S10 | `CALIBRATE_RANGE` | S9 提交成功 | Title 40「满量程校准」；Step 32「方向 n/4」；Body 28 = 方向轮换（「推到最右并保持」→「…最上…」→「…最下…」→「…最左…」）；BigHint 72「推到最外圈并保持」；Hint 28 = 失败原因（非空）或「每个方向保持 0.4 秒」；Meter 每方向 0→24 | 四方向各 24 帧 → `scale_from_samples(all, center)` → `submit_calibration_range` → S11 | 量程不足 → `ok == false`，留在本屏 + 原因；成功提交时 flow 清空 `probe_failure_message`，屏幕自然回到提示文案 |
| S11 | `LAYOUT_CONFIRM` | S10 通过；或复用门通过 | **Xbox**：Title 40「检测到 Xbox 布局」+ BigHint 72「按 A 继续」；**PlayStation**：Title 40「检测到 PlayStation 布局」+ BigHint 72「按 × 继续」；**认不出**：Title 40「没认出手柄，请选择布局」+ BigHint 72「请选择布局」；Body 28 = `flow.layout_message`（非空）否则「十字键或 LB/RB：左选 Xbox，右选 PlayStation」；Options 32 = 索引正常时同上句，索引不符时「按到的是索引与标准不同：按 B 仍然使用此布局，或换布局」；Hint 28「按 B 仍然使用此布局」 | 索引 13/9 → `choose_layout(xbox)`；14/10 → `choose_layout(playstation)`；索引 1 → `accept_layout_anyway()`；**其余任何索引** → `confirm_layout(实际索引, 0)`；成功后 S12 | 布局为空：`layout_message = "没认出手柄，请先用十字键左右选择布局"`，`confirm_layout` 与 `accept_layout_anyway` 都留在原地；索引 ≠ 0：`button_index_ok = false`、留在本屏（文案写明「按到的是索引…」） |
| S12 | `PRACTICE` / idle | `can_enter_practice()` 首次为真 → `main.gd` 调 `practice_screen.setup(runtime, effective_layout, buffer)` | `%ActionName` 40「绿色搓射 Green Finesse」；`%Hint` 32「按住 RB，连按两下 X」/「按住 R1，连按两下 □」；`%LiveMs` 32「等待第一下」；`%SuccessCount` 28「成功 0 / 0」；横幅空；`%DebugPanel` 28 一行 ASCII | 第一下按下 → 检测器起手，`status()` 返回「已按第一下…」→ S13 | 布局为空：`main.gd` 打 `LAYOUT_ERROR` 留在引导；练习屏收到 `&""` 时显示「布局未确认，请返回引导重选」；`layout_confirmed == false` 时运行时零输出（永不离开 S12） |
| S13 | `PRACTICE` / armed | `runtime.status()` 的文本从 idle 变为「已按第一下 X，等第二下 Nms（目标 400~600）」 | 同一套节点；**唯一差异**是 `%LiveMs` 的文本（10 Hz 刷新） | 第二次按下 / 超时 → 运行时产出 1 条 `Outcome` → S14 | 中途松开 RB → `hold_short`；间隔超窗 → `too_fast` / `too_slow`（原因来自检测器，不由 UI 拼） |
| S14 | `PRACTICE` / result | `pop_outcomes()` 非空 | 横幅 `%Title` 72「✓ 做对了」或「✗ 没做对」；`%Reason` 40 = `detail`（成功）/ `message`（失败）；停留 `1.5 s` | 1.5 s 后清空 → S12；期间若来第二条 `Outcome` 且 `seq` 更大 → 直接覆盖（仍在 S14） | 同一 `seq` 重放必须被忽略；`layout_confirmed` 变 false（断连）→ S15，横幅静默清空 |
| S15 | `DEVICE_LOST` | 设备列表变空且已绑定；或绑定的设备换了一台 | Title 40「手柄断开，等待重连」；Body 28「重新连接后会重新走探针与校准。」；BigHint 72「等待重连」 | 设备重新出现 → S2（**必须重走探针**，`chosen_layout`/`suggested_layout`/`layout_confirmed` 已清空） | 断开瞬间的未完成手势必须 `abandon()`（静默，不产 `hold_short`/`too_slow`）；练习屏隐藏、`_practice_entered = false` |
| S99 | 无 flow 状态（`main.gd` 错误屏） | 配置加载/校验失败；或 taps 动作不是恰好一条 | `%ConfigError` Label 32 = `ConfigResult.to_text()`（路径 + 行列 + 原因 + 提示），或「配置里没有唯一的 taps 动作：只练绿色搓射需要恰好一条启用的 taps 动作。」 | **没有手柄推进路径**：修文件 + 重启 | `_flow = null` → `_process` 早退；三屏互斥；不会进入 S1 |

**全局规则**（跨 S3a–S10）：

- **D0 停止条件**：等待推杆时，若本状态已累计 ≥ 60 帧、`_window` 仍为空、且
  `buffer.events_motion` 未增长 → 整屏改为：Title「输入事件缺失」/ Body「本机在当前阶段
  没有送上任何摇杆事件。」/ BigHint「停止」/ Hint「没有收到摇杆事件（events_motion = N）：
  本机可能不发送轴事件，请记录并停止（D0 判失败）」/ Options「记录此屏并停止（D0 判失败）」。
  **不得**用全零窗口驱动评估（那只会产出一条误导性的"位移不够"）。
- **采样以样本数计时，不读时钟**：18 / 24 帧；60 Hz 下分别约 0.3 s / 0.4 s。
- **失败原因一律走 `flow.probe_failure_message`**；成功提交时 flow 清空它，屏幕自动回到
  本步提示，不会挂着上一条旧原因。

---

## 4. Interaction Contract（零触摸输入）

### 4.1 按键分派矩阵（唯一消费者：`main.gd::_handle_button_edge`）

| `flow.state` | 索引 0（A / ×） | 索引 1（B / ○） | 13 或 9（十字上 / LB） | 14 或 10（十字下 / RB） | 其它索引 |
|---|---|---|---|---|---|
| `DEVICE_READY` | `on_any_button()` | `on_any_button()` | `on_any_button()` | `on_any_button()` | `on_any_button()` |
| `PROBE_INTRO` | `begin_probe()` | 忽略 | 忽略 | 忽略 | 忽略 |
| `PROBE_FAILED` | 忽略 | `retry_probe_step()` | 忽略 | 忽略 | 忽略 |
| `REUSE_CHECK` | 忽略 | `begin_probe()`（放弃复验） | 忽略 | 忽略 | 忽略 |
| `LAYOUT_CONFIRM` | `confirm_layout(实际索引, 0)` | `accept_layout_anyway()` | `choose_layout(xbox)` | `choose_layout(playstation)` | `confirm_layout(实际索引, 0)` |
| `PRACTICE` | 忽略 | 忽略 | 忽略 | 忽略 | 忽略 |

**写死 `confirm_layout(0, 0)` 是禁止的**：必须把边沿字典里的真实 `index` 传进去，否则
`button_index_ok` 永远为真、真机自检形同虚设。

### 4.2 不变量

1. **零触屏**：`mobile/src/ui/**` 内 `type="Button"` 计数为 0；不处理
   `InputEventScreenTouch` / `InputEventScreenDrag`；不做虚拟摇杆。
2. **边沿唯一消费者**：只有 `main.gd` 读 `buffer.button_edges()`；`onboarding_screen.gd`
   与 `practice_screen.gd` 都不得读它（同一次按下不能被解释两次）。
3. **判定推进点唯一**：只有 `main.gd` 调 `runtime.tick(frame)`；两个屏都只读。
4. **`Frame.now` 是秒**（`Time.get_ticks_usec() / 1_000_000.0`）；毫秒只出现在
   `PadSampler` 的事件时间戳里。
5. **注入顺序**：两屏的 `_ready()` 只缓存 `@onready` 节点（`pass`），依赖一律从
   `setup(...)` 进入；`setup` 负责首次 `_refresh()`。**先 `add_child` 再 `setup` 是常态**，
   所以 `_ready` 里读注入对象会 null 崩。
6. **可见性双保险**：进入练习时 `%Practice` 容器与练习屏节点**都**要 `visible = true`；
   只显示容器时，`practice_screen._process` 开头的 `if not visible: return` 会把
   `pop_outcomes()`、横幅与 `%DebugPanel` 全部挡在屏幕外。
7. **一次结果一次展示**：横幅去重谓词是
   `static func accepts(shown_seq: int, seq: int) -> bool: return seq > shown_seq`；
   `clear()` **不重置** `_shown_seq`（序号单调，重置会让旧结果重播）。
8. **无自动推进**：横幅 1.5 s 后清空即停；不进入下一题、不切屏、不弹新窗口。
9. **不动画**：无 `Tween`、无 `AnimationPlayer`、无补间；横幅的出现/消失是**瞬时**
   文本变化（Godot 默认无淡入淡出）。
10. **不震动、不发声**：不调用 `Input.vibrate_handheld`；不加 `AudioStreamPlayer`；
    文案里不出现「震动」二字（安卓上 Godot 没有手柄马达实现）。

### 4.3 刷新节流

| 标签 | 刷新频率 | 规则 |
|------|----------|------|
| `%LiveMs` | 10 Hz | `_accum += delta; if _accum < 0.1: return;` 之后统一赋值 |
| `%SuccessCount` | 10 Hz + 变化检测 | 缓存上一次 `"成功 %d / %d"` 字符串，相同则跳过 |
| `%DebugPanel` | 10 Hz | 与上面同一个节流块 |
| 横幅 `%Title` / `%Reason` | 事件驱动 | 只在 `show_outcome` / 清空时赋值 |
| 引导屏全部标签 | 变化检测 | 统一走 `_set_text(label, text)`：`label.text == text` 直接 return |

`Label.text` 赋值触发文本整形，60 Hz 下是全帧最贵的操作；**禁止**在 `_process` 里
无节流地写文字标签。

> 接下来五节是模板要求的视觉令牌章节（Spacing / Typography / Color / Copywriting /
> UI Considerations）；编号章节自 §5 续。

---

## Spacing Scale

只用 4 的倍数。下表是**实际在用**的值（来自 `.tscn` 偏移差），未使用的档位明确标注。

| Token | Value | Usage |
|-------|-------|-------|
| xs | 4px | 相邻文本带的最小间隙（Body 232 → BigHint 236） |
| sm | 8px | 文本带之间的默认间隙（104→112、360→368、472→480、640→648） |
| md | 16px | 屏幕底边留白（704→720）；`%Footer` 与屏幕底部之间 |
| lg | 24px | 屏幕上边距（`%Title` 的 y=24） |
| xl | 32px | `%ConfigError` 四边留白（32 / 1248 / 32 / 688） |
| 2xl | 48px | 左右安全边（`x=48` / `x=1232`） |
| 3xl | 64px | **本阶段未使用**（预留；最长消息在 40 px 下 2 行内，不需要更大留白） |

Exceptions:

- **12px**（`%Meter` 520 → `%Options` 532）是 4 的倍数但不是 8 的倍数。允许：条带高度
  由字号行框决定，不是排版间距。
- **触控目标尺寸不适用**：零触摸，不存在 44 px 最小可点区域。
- 字号不是间距：行框高度由字体度量给出（§Typography），不得为了让文字塞进条带而改字号。

---

## Typography

`mobile/src/ui/**` 内的字号**恰好 4 档**，全部来自 `.tscn` 的
`theme_override_font_sizes/font_size`。（`src/smoke/` 里另有 22 px，那是输入体检调试屏，
不属本契约，也不得被任何正式屏引用。）

| Role | Size | Weight | Line Height |
|------|------|--------|-------------|
| Body | 28px | **100 Thin（当前渲染值，实测）** | 1.2（字体固有：Noto Sans SC 子集 `hhea` = 1000 / −200 / 0，行框 ≈33.6px） |
| Label / Readout | 32px | 100 Thin | 1.2（≈38.4px） |
| Heading | 40px | 100 Thin | 1.2（≈48px） |
| Display | 72px | 100 Thin | 1.2（≈86.4px）；**含 `✓`/`✗` 时行框 ≈1.699em ≈122.3px**（Symbols 2 的 `hhea` = 1069 / −630 / 0） |

**两个字重槽位，只有一个在实际渲染**：

- **槽位 1：`wght = 100`（Thin）—— 当前生效。** 实测依据：子集
  `NotoSansSC-Subset.ttf` 的 `fvar` 轴为 `wght 100…900，default = 100`，
  `OS/2.usWeightClass = 100`；`AppFont.tres` 只声明 `base_font` + `fallbacks`，
  **没有** `variation_opentype`，因此引擎取默认实例 = Thin。28 px 的正文在 1 m 外
  笔画偏细——这是 gap（§12-G11），不是设计选择。
- **槽位 2：`wght = 400`（Regular）—— 未启用。** 命名实例存在于 `fvar`，但没有任何
  代码或资源选中它。若要启用，只需在 `AppFont.tres` 加一行
  `variation_opentype = { &"wght": 400 }`：不改字体文件、不重生成子集、不影响
  `glyph_coverage.gd` 的逐字符断言（它按码点查 `has_char`，与坐标无关）。
- **没有第三档**：子集没有独立的 Bold 面。合成粗体（`variation_embolden`）**禁止**：
  它会改变字宽与行框，让"1 m 可读"的实测失去意义，也不在字形闸门覆盖内。

**行高不写 `line_spacing`**：保持字体原生的 1.2，条带高度按上表预留。若将来必须改，
只能是整数像素的 `theme_override_constants/line_spacing`，且不得让任何条带溢出。

**1 m 观看距离判据**（唯一可验收的一句话）：坐在 1 m 外、不眯眼，能读出 `%Reason` 那
一行。读不清时**先确认字重**（Thin 100 → 400，见 §12-G11），再调字号常量；两者都不动
布局结构。

**字形闭世界**：

- `mobile/src/ui/**` 下每个 `.gd` / `.tscn` 都必须登记进 `tools/make_font_subset.py` 的
  `CHAR_SOURCES`；`assert_ui_sources_registered()` 在 `collect_chars()` 第一句执行，
  `sync` 与 `--check` 两条路径都会失败。
- 闸门顺序不可反：`make_font_subset.py --check`（清单 vs 源文件）→ `glyph_coverage.gd`
  （清单 vs 子集，关闭系统兜底逐字符断言）→ `GLYPH_OK chars=876`。
- 新增中文必须先写进源文件、再重生成产物；**不得**在运行时拼出源文件里没有的字符。
- 已知缺口见 §12-G5：`src/core` 里会送到屏幕上的字符串不在闭世界内。

---

## Color

本阶段**只有两处显式颜色**（横幅标题的成功/失败），其余全部继承 Godot 4.7 默认
深色主题——场景里没有任何 `theme_override_colors`，也没有 Theme 资源。前两行（背景与
默认文本色）是**继承值**，不是本阶段声明的新令牌：D0 截图取色是唯一确认方式；若要改，
改的是 `project.godot` 的 `default_clear_color` 与 Theme，不是逐节点覆写。

| Role | Value | Usage |
|------|-------|-------|
| Dominant (60%) | `#1D1D1D` | 全屏 `Control` 背景（Godot 默认 clear color，未覆写） |
| Secondary (30%) | **无** | 单层全屏文本布局：没有卡片、没有导航、没有 Panel。不得为"好看的层次"引入底色块 |
| Accent (10%) | `#66BB6A`（成功）/ `#EF5350`（失败） | **仅** `%ResultBanner/%Title` 的 `theme_override_colors/font_color` |
| Destructive | **无** | 本阶段没有删除/重置/退出等破坏性操作 |
| Foreground（默认文本） | `#DFDFDF` | 全部 `Label` 的默认字体色（未覆写） |
| 进度条 | 默认主题填充色（不覆写） | `%Meter`；**中性进度指示，不算 accent** |

**Accent 保留清单（只有这两项）**：

1. 横幅标题「✓ 做对了」的绿；
2. 横幅标题「✗ 没做对」的红。

**禁止**：把 accent 用到 `%Meter`、`%Options`、`%Hint`、`%Footer`、任何背景或边框上；
把 `%Meter` 改成绿/红（会与判定颜色语义冲突）；用颜色作为**唯一**信号（成功/失败同时
有 `✓`/`✗` 字形与「做对了 / 没做对」文字，色盲与灰度截图下仍可判读）。

**对比度**（对 `#1D1D1D`，按 WCAG 相对亮度计算）：

| 前景 | 对比度 | 判定 |
|------|--------|------|
| `#DFDFDF` 正文 | ≈12.7:1 | AAA（正文） |
| `#66BB6A` 成功 | ≈7.1:1 | AAA（大字号） |
| `#EF5350` 失败 | ≈4.8:1 | AA（正文）/ AAA（大字号） |

实现常量（`result_banner.gd`，波次 6）：

```gdscript
const SUCCESS_COLOR := Color("#66BB6A")
const FAILURE_COLOR := Color("#EF5350")
const HOLD_SECONDS := 1.5
```

---

## Copywriting Contract

| Element | Copy |
|---------|------|
| Primary CTA | 「按 A 开始」（S3）。PlayStation 布局下的确认是「按 × 继续」（S11）。**零触摸：CTA 是手柄键名，不是按钮** |
| Empty state heading | 「没有检测到手柄：先按任意键唤醒」 |
| Empty state body | 「打开手柄电源 → 长按配对键 → 在系统蓝牙里选择它 → 按手柄任意键唤醒」，下一行「安卓蓝牙手柄在收到第一次输入前不会出现在设备列表里。」 |
| Error state | 「这一步没通过」+ **具体原因一行**（`ProbeEvaluator` / `Calibration` / `OnboardingFlow` 的原文，逐字）+「按 B 重来这一步」 |
| Destructive confirmation | 无 —— 本阶段没有破坏性操作（B 键的"接受当前布局"不是破坏性动作） |
| 练习屏 idle | 「等待第一下」 |
| 练习屏成功 | 「✓ 做对了」+ `Outcome.detail`（例：「两下 X 间隔 480ms（RB 全程按住）」） |
| 练习屏失败 | 「✗ 没做对」+ `Outcome.message`（例：「太快了：两下 X 只隔了 300ms（需要 400~600ms）」） |
| 练习屏布局缺失 | 「布局未确认，请返回引导重选」 |
| 练习屏键名提示 | Xbox：「按住 RB，连按两下 X」；PlayStation：「按住 R1，连按两下 □」 |

**文案来源纪律**：

- 判定文本（`Hit.summary/detail`、`Failure.message`、`Outcome.message/detail`）**只显示，
  不拼装**。UI 不得把"太快/太慢/保持不够"重新组织成自己的句子——否则"与桌面版一致"
  会悄悄变成"与作者的理解一致"。
- 静态指令（`%Hint`、`%BigHint`、`%Body`）由 `layout` 注入值决定，只有三支：`xbox` /
  `playstation` / 空串。空串**绝不**回退到 Xbox 文案。
- 符号用 `×`(U+00D7) / `□`(U+25A1) / `△`(U+25B3) / `○`(U+25CB)；**禁止** U+2A2F
  （字体里没有字形）。要写"叉"就直接用汉字。
- 逐字常量（波次 6 必须在源文件里出现）：`"按住 RB，连按两下 X"`、`"按住 R1，连按两下 □"`、
  `"等待第一下"`、`"✓ 做对了"`、`"✗ 没做对"`、`"布局未确认，请返回引导重选"`。

**禁止措辞清单**（出现即违规）：

| 禁止 | 原因 |
|------|------|
| 「手柄震动」「震动测试」「震一下」 | 安卓上 Godot 没有手柄马达实现；本阶段不接任何震动，视觉反馈自成闭环 |
| 「点击」「轻触」「滑动」「点这里」 | 零触摸；用户的手在 1 m 外握着手柄 |
| 「重试」单独成句 | 每一步失败都必须给出**具体原因**与具体出口（「按 B 重来这一步」） |
| 「演示」「示例判定」「模拟结果」 | 屏幕上的每条结论必须由该次尝试真正驱动检测器与运行时 |
| 「加载中」「请稍候」 | 本阶段没有网络或异步等待；采样进度用 `%Meter` + 样本数表达 |

---

## UI Considerations

Applicable state considerations resolved: **10 covered, 2 backstop, 3 unresolved**

| Category | Element(s) | Status | Resolution / Reason |
|----------|------------|--------|---------------------|
| empty | S1 无设备 | ✅ covered | 屏幕给出三步配对图文 + 「安卓蓝牙手柄在收到第一次输入前不会出现在设备列表里。」；不是空白等待屏，也不给"重试"按钮 |
| empty | S12 无判定 | ✅ covered | `%LiveMs` 显示「等待第一下」，横幅为空且**不占位**（固定条带，清空不引起布局跳动） |
| empty | 复用门无档案 | ✅ covered | `ProfileStore.find` 未命中 → 直接走完整四步探针；没有额外空态屏、没有"跳过"按钮 |
| loading | 采样窗口（静止基线 / 探针 / 校准） | ✅ covered | `%Meter` 以**样本数**为倒计时（18/18、24/24），无 spinner、无 skeleton；倒计时不读时钟，无头与真机一致 |
| error | 探针 / 校准被拒 | ✅ covered | `flow.probe_failure_message` 优先渲染到 `%Hint`；成功提交时 flow 清空 → 文案自动消失，不残留旧原因 |
| error | D0 轴事件缺失 | ✅ covered | 整屏切到"输入事件缺失"并要求记录后停止；不用全零窗口驱动评估 |
| error | S99 配置错误 | ✅ covered | `%ConfigError` 显示 `ConfigResult.to_text()`（路径 + 行列 + 原因 + 提示），32 px 可读；无手柄推进路径，改文件后重启 |
| error | 布局为空 / 组合根被绕过 | ✅ covered | `main.gd` 打 `LAYOUT_ERROR` 并留在引导；练习屏 `&""` 分支显示「布局未确认，请返回引导重选」，绝不回退 Xbox 键名 |
| partial | 探针部分完成 | ✅ covered | S8 保留已完成步骤；`retry_probe_step()` 只回退出错的那一步（`retry_state` 由未改状态前的 `current_probe_state()` 写入） |
| zero-one-many | 0 / 1 / 2+ 条判定 | ✅ covered | 队列侧全量 drain（数据不丢）；横幅按 `Outcome.seq` 单调去重。同帧多条时**视觉上只留最后一条**——这是刻意的：屏幕一次只讲一条结论 |
| long-text | 失败原因（`%Reason` 40px） | 🧪 backstop | 1184 px 宽、最多 2 行（96 px），Reason 带留 144 px。最长已知消息「太慢了：等了 9999ms 还没有第二下 X（需要在 400~600ms 内）」必须在 D4 截图里完整可读且不压到 `%DebugPanel` |
| overflow | 横幅标题含 `✓`/`✗` 的行框 | 🧪 backstop | Symbols 2 的 1.699em 行高把 72 px 行框抬到 ≈122 px；标题带留 128 px。D4 截图确认不裁字、不与 Reason 重叠 |
| overflow | 超长蓝牙设备名（`%Title` 40px） | ⚠ unresolved | 标题带 80 px 只放得下 1 行（48 px）；`.tscn` 未设 `text_overrun_behavior`，超长名会**硬裁**。假设：D0 用真机设备名截图确认；若裁切，加 `text_overrun_behavior`（省略号）而**不是**缩小字号 |
| overflow | `%DebugPanel` 单行 ASCII | ⚠ unresolved | 约 45 字符 ≈ 630 px，在 1280 宽内单行可容；但 `canvas_items` 放大或未来换基准视口时可能换行。假设：本阶段只保证 1280×720 基准，不做自适应 |
| long-text | `%ConfigError` 多行 | ⚠ unresolved | 错误文本可长达 4–6 行（含路径与提示），32 px 行框 38.4 → 6 行 = 230 px，在 656 px 高度内可容；但存在极端长路径（>100 字符）时的换行行数未实测。假设：D0 只验证正常错误文案，不构造超长路径 |

**给 planner 的抬升说明**：`✅ covered` 的 10 条可直接作为 `must_haves.truths` 的候选；
`🧪 backstop` 的 2 条带 `verification: backstop`（D4 截图）；`⚠ unresolved` 的 3 条必须作为
**显式假设**进入计划，不得静默丢弃。

---

## 5. 诊断面板契约（`%DebugPanel`）

D5/D6 的唯一屏上来源。纯 ASCII，不引入中文，避免字形依赖。

格式（单行，`%.1f` 保留一位小数）：

```
ev_m=%d ev_b=%d poll=%d dt95=%.1f g=%d/%d
```

| 字段 | 来源 | 说明 |
|------|------|------|
| `ev_m` | `buffer.events_motion` | 轴事件计数；D5 要求一次快甩增量 ≥ 3 |
| `ev_b` | `buffer.events_button` | 按钮事件计数 |
| `poll` | `buffer.poll_edges` | 轮询对账补出的边沿数 |
| `dt95` | `buffer.delta_ms_percentiles()["p95"]` | 到达间隔 p95；D5 要求 ≤ 20 ms |
| `g` | `runtime.group_hits` / `runtime.group_size` | 组内命中 / 组容量（默认 10） |

示例：`ev_m=1240 ev_b=37 poll=2 dt95=16.7 g=2/10`

**禁则**：`%DebugPanel` 不得显示中文、不得显示设备名（设备名走 `%Footer` 与
`PAD_DEV` 日志）、不得因 `device < 0` 而抛错（无设备时不进入练习屏）。

---

## 6. 字体与字形闸门（Font Contract）

| 项 | 契约 |
|----|------|
| 资源 | `res://assets/fonts/AppFont.tres`；`project.godot` 的 `[gui] theme/custom_font` 必须指向它 |
| 组成 | `FontVariation(base_font = NotoSansSC-Subset.ttf, fallbacks = [NotoSansSymbols2-Subset.ttf])` |
| 为什么必须有 fallback | 成功标准 2 写死 `✓ ✗`，而 Noto Sans SC 恰好没有 `✗` |
| 断言 | `glyph_coverage.gd` 逐层设 `allow_system_fallback = false`，对清单逐字符 `has_char()`；通过才打印 `GLYPH_OK chars=N` |
| 源清单 | `CHAR_SOURCES` 闭世界：`shared/skills_config.json`、`desktop/padskills/gui.py`、`desktop/padskills/detectors.py`、`mobile/src/smoke/*`、`mobile/src/ui/*` |
| 新 UI 文件 | 必须先登记进 `CHAR_SOURCES`，再 `python3 tools/make_font_subset.py` 重生成字体产物（`required_glyphs.txt` + 两个 `.ttf`；`OFL.txt` 随源字体落盘） |
| 未登记 | `assert_ui_sources_registered()` 直接 `SystemExit`，`--check` 与 `sync` 两条路径都红 |
| 额外符号 | `EXTRA_SYMBOLS = "°±→✓✗"` + ASCII 可打印区（轴读数与 `%DebugPanel` 需要） |
| 当前基数 | `GLYPH_OK chars=876`（波次 5 实测） |

新增 UI 文案的**唯一**正确顺序：写进 `.gd` / `.tscn` → 登记 → 重生成 → `--check` 0 →
`gate-a.sh` 出现 `GLYPH_OK`。反过来（先上屏再补登记）会让闸门在真机豆腐时保持绿色。

---

## 7. 可见性、生命周期与注入契约

| 时机 | 必须发生 | 禁止 |
|------|----------|------|
| `main._ready()` | 先 `Input.set_use_accumulated_input(false)`；`ConfigStore.load_config()`；配置失败 → `%ConfigError` + `_flow = null` + return | 失败后继续建对象图（会让 S99 与 S1 同时可见） |
| `main._ready()` 建 `PadSampler` | **先** `device_list_changed.connect(...)`，**再** `add_child(_sampler)`，随后用 `connected_devices()` 主动播种一次 | 先 `add_child` 后 connect（错过初始 emit） |
| `main._ready()` 建练习屏 | `PRACTICE_SCENE.instantiate()` → `add_child` → `visible = false`；**不调 `setup`** | 在 `add_child` 后立刻 `setup`（此时 `flow` 可能还没到 `layout_confirm`） |
| 首次 `can_enter_practice()` 为真 | `_runtime.set_layout_confirmed(true)`；`_practice.setup(_runtime, _flow.effective_layout(), _sampler.buffer)`；`_onboarding.visible = false`；`%Practice.visible = true`；`_practice.visible = true`；`build_profile()` 非 null 才 `upsert` | 只显示容器；在空布局时调 `setup`；`profile == null` 时弹窗/阻塞 |
| 退出练习（断连/换手柄） | `_runtime.set_layout_confirmed(false)`（静默 `abandon()`）；`_flow.on_device_lost()`；`_practice_entered = false`；下次进入重新 `setup`（清横幅与计数缓存） | 带着旧进度继续判；用 `reset()` 代替 `abandon()`（会产 `hold_short`） |
| 练习屏 `_process` | `if not visible: return`；每帧 `pop_outcomes()` **全量 drain**，逐条 `show_outcome` | 假设"最多一条"；只取 `[0]` |
| 横幅 `_process` | `_remaining > 0` 时递减；到 0 清空 `%Title` / `%Reason` | 到 0 后自动前进/切屏 |
| 引导屏 `_process` | `if _flow == null or not visible: return`；状态变化时清空所有采样窗口 | 跨状态复用窗口（进度会串台） |

---

## 8. 键盘/手柄以外的输入面

| 输入面 | 本阶段状态 |
|--------|------------|
| 触摸 | **不使用**。不响应触摸、不做虚拟摇杆（触屏搓招的肌肉记忆无法迁移到真手柄） |
| 鼠标 | 不使用（安卓上没有鼠标；桌面版仍用 Python + pygame，不受影响） |
| 系统返回键 | 未处理。安卓返回键不映射到任何 flow 方法；本阶段不提供退出路径（Phase 8 再谈） |
| 键盘 | 不使用 |

---

## 9. 状态与文案的"单一真源"

| 内容 | 唯一来源 | UI 的角色 |
|------|----------|-----------|
| 哪一屏可见 | `OnboardingFlow.state` + `can_enter_practice()` | 只读，切 `visible` |
| 能不能进练习 | `can_enter_practice()`（五条同时成立） | 只读；`TapRuntime.layout_confirmed` 是第二道独立闸 |
| 失败原因（引导期） | `flow.probe_failure_message` | 逐字渲染到 `%Hint` |
| 判定结论 | `Outcome`（`ok` / `code` / `message` / `detail` / `elapsed_ms` / `seq`） | 逐字渲染，**不拼装** |
| 实时状态 | `runtime.status()` | 逐字渲染（唯一例外见 §12-G3） |
| 键名文案 | 注入的 `layout`（`xbox` / `playstation` / 空） | 三选一常量 |
| 动作名 | `runtime.skill_name` | 逐字渲染 |
| 设备名 | `sampler.device_name()` | 逐字渲染（`%Title` / `%Footer`） |
| 采样进度 | 样本计数 | `%Meter.value / max_value` |

---

## 10. 与桌面版的一致性边界

| 项 | 移动端 | 桌面版（参照） | 本契约的立场 |
|----|--------|----------------|--------------|
| 状态文案 | `TapDetector.status()` 返回「待机」/「已按第一下 X，等第二下 Nms（目标 400~600）」 | `gui.py:497-498` 与 `1002-1003` **抑制**「待机」，不显示 | 练习屏同样不显示「待机」，idle 时显示「等待第一下」（§12-G3） |
| 失败建议 | `Failure.message` 已含具体原因与数值 | `gui.py:54-65` 的 `_ADVICE` 追加一条建议 | 本阶段**不移植** `_ADVICE`；`message` 自带数值与出口，够用 |
| 结果通路 | `pop_outcomes()` 队列 + `seq` | `last_outcome` + `outcome_seq` 单槽 | 移动端是结构改良（同帧两条不丢），不是分歧 |
| 进度分组 | `group_hits` / `groups_done`（10/组） | 同 | 一致；屏上只在 `%DebugPanel` 露出 `g=hits/size` |

---

## 11. 偏离与加强（非 gap，记录以免被当成 bug）

| 项 | 契约 |
|----|------|
| 布局选择用 Label 而非两个按钮 | 零触摸的必然结果；`%Options` 是 `Label`，选择由十字键/LB/RB 完成 |
| 静止基线是独立一屏（S3a） | 研究表里没有，实现补上了：没有参照系的"位移"只是噪声 |
| 无 `STATE_CONFIG_ERROR` | 配置错误发生在状态机构造之前；`main.gd` 用自己的错误屏，避免留一条永远到不了的假路径 |
| `confirm_layout(实际索引, 0)` | 第二个参数 `0` 是"标准确认键的位置"，第一个参数必须实测；写死两个 0 会让自检失效 |
| 帧内不读时钟 | 采样以帧数计时（18/24），倒计时用样本数；无头与真机行为一致 |

---

## 12. Gaps：实现 vs 设计意图（显式记录）

| ID | 缺口 | 现状（基线） | 影响 | 处理 |
|----|------|--------------|------|------|
| G1 | 练习屏尚未实现 | `%Practice` 里只有一个 `Placeholder` Label「可以开始练习了」 | S12–S14 无真屏；S15 回引导正常 | 波次 6 交付；本契约 §2.3 / §3 / §4 已锁死其形状。**不得**把占位 Label 留在真屏下面 |
| G2 | 绝对坐标 vs "锚点/容器"约束 | 现有 2 个 `.tscn` 的文本节点全部用 `layout_mode = 0` + 绝对偏移；只有根节点用 `anchors_preset = 15` | 16:9 上稳定（`canvas_items` + `aspect=keep`）；非 16:9 由引擎加黑边 | **接受为基线**：不要求重写成 `VBoxContainer`（会打乱已验收的 8 节点布局与闸门 grep）。新节点必须落在 §2 的条带内 |
| G3 | idle 文案：`待机` vs `等待第一下` | `TapDetector.status()` 在未起手时返回「待机」；04-06 要求屏上出现「等待第一下」 | 直接显示「待机」是设备面板黑话，1 m 外读不懂 | **契约取映射**：`%LiveMs` 逐字显示 `runtime.status()`，仅当它等于字面量 `待机` 时显示「等待第一下」。与桌面版抑制「待机」的口径一致；不改 core |
| G4 | PlayStation 布局下运行时文本仍写 `X` / `RB` | `Failure.message` 与 `status()` 由检测器生成，键名是 canonical 名（`X`），与配置 `params.button` 一致 | DualSense 上 `%Hint` 说「连按两下 □」，而横幅原因/实时行说「X」——同一屏两种键名（P4-UI-1） | **不修**：判定文本必须逐字来自 `Outcome`（桌面一致性优先）；记录为已知文案不一致。D3/D4 真机若确认刺眼，Phase 5 在**展示层**做键名映射（只换 token，不动数值与措辞），不改 core |
| G5 | 字形闭世界漏掉 core 的屏上字符串 | `CHAR_SOURCES` 只含 `src/ui/**` + `shared` + 两个 desktop 文件；`src/core/config/*.gd`（S99 错误正文）、`device/probe_evaluator.gd`（S8「互为反号」）、`device/calibration.gd`、`device/device_profile.gd`、`onboarding_flow.gd` 的字符串**不在**清单里 | 已实测：这些文件的字符串字面量里有 **23 个字符**不在子集内（如 `互`、`七`、`拼`、`藏`、`肉`、`语`、`逗`、`骤`、`非`、`脚`、`层`、`另`、`副`）；其中 S99（配置错误正文）与 S8（`互为反号`）两条路径已确认可达，其余随消息分支可达。系统兜底会在多数安卓机上补上，但**违背"不靠系统字体"的闸门前提**（P4-UI-2） | **未解决**。建议加法修复：把 `config_loader.gd` / `config_validator.gd` / `probe_evaluator.gd` / `onboarding_flow.gd` 登记进 `CHAR_SOURCES` 并重生成（实测 876 → **943** 字形，+67）。这是纯加法，不会让任何闸门变红，但需要一次 `fonttools` 重生成与 `--import` |
| G6 | `%Practice/Placeholder` 必须删除 | `main.tscn` 里仍在 | 占位文案会压在真练习屏下 | 波次 6 在 `add_child(_practice)` 后 `queue_free()`；契约不接受"隐藏了事" |
| G7 | 长设备名无溢出策略 | `%Title` 无 `text_overrun_behavior`、无 `autowrap` | 超长蓝牙名硬裁（不带省略号） | 见 §UI Considerations 的 ⚠ 行；D0 截图确认后再决定是否加省略号 |
| G8 | S11 同句重复显示 | `_render_layout()` 在"布局已识别"时把「十字键或 LB/RB：左选 Xbox，右选 PlayStation」同时写进 `%Body` 与 `%Options` | 32 px 与 28 px 各出现一次，屏幕啰嗦但不算错误 | 已实现基线；**不要求本阶段改**。新文案不得再复制同一句；若后续触碰该函数，只改一处 |
| G9 | 练习屏 `%LiveMs` 的 10 Hz 与状态检测 | 计划要求 `%LiveMs.text = runtime.status()`；S12/S13 的区分也依赖同一字符串 | 若改成"每帧读状态再分支"，会把节流块复杂度抬高 | 契约：**S12/S13 不新增节点、不新增状态机**，只由 `%LiveMs` 的文本体现；所有高频赋值收在同一个 `_accum < 0.1` 块内 |
| G10 | 无返回/退出路径 | 安卓返回键不处理；练习屏没有"退出练习" | 本阶段可接受（单动作竖切） | Phase 8 的热插拔 UX 再补；现在不新增按钮（零触摸） |
| G11 | 实际渲染字重是 100（Thin），不是 400 | `AppFont.tres` 只有 `base_font` + `fallbacks`，无 `variation_opentype`；`NotoSansSC-Subset.ttf` 的 `fvar` 默认实例 `wght = 100`、`OS/2.usWeightClass = 100` | 28 px 正文在 1 m 外笔画偏细，契约的"不眯眼读出 `%Reason`"可能不达标；32/40 px 同样受影响 | **未解决**。一行修复：`AppFont.tres` 加 `variation_opentype = { &"wght": 400 }`——不动字体文件、不重生成子集、不影响 `GLYPH_OK`（按码点断言）、不影响任何 `.gd` grep。D0 判读通过则可维持 Thin 基线；判读失败先改这一行，**不要**先加字号 |

---

## 13. Verification Hooks（契约 → 检查）

| 契约条款 | 检查方式 |
|----------|----------|
| 零触摸：无 Button | `grep -c 'type="Button"' mobile/src/ui/*.tscn` → `0` |
| 每个场景根绑脚本 | `grep -c 'script = ExtResource' mobile/src/ui/*.tscn`：`main` 1、`onboarding` 1、`practice` **2**（根 + `ResultBanner`） |
| 练习屏 8 个唯一节点 | `grep -c 'unique_name_in_owner = true' mobile/src/ui/practice_screen.tscn` → `8`；节点名逐一存在（`ActionName`/`Hint`/`LiveMs`/`SuccessCount`/`DebugPanel`/`ResultBanner`/`Title`/`Reason`） |
| 横幅子节点归属与字号 | `grep -cE '^\[node name="(Title|Reason)" type="Label" parent="ResultBanner"\]'` → `2`；72 / 40 各一处 |
| 双可见性 | `grep -c '_practice.visible = true' mobile/src/ui/main.gd` → `1`，且行号大于 `_practice.visible = false` |
| 10 Hz 节流 | `grep -c '_accum < 0.1' mobile/src/ui/practice_screen.gd` ≥ `1` |
| 全量 drain | `grep -c 'runtime.pop_outcomes()' mobile/src/ui/practice_screen.gd` ≥ `1`；`grep -c 'pop_outcomes()\[0\]'` → `0` |
| 横幅去重谓词 | `grep -c 'static func accepts(' mobile/src/ui/result_banner.gd` → `1`；`test_green_slice` 调 `BANNER.accepts(...)` 三条断言 |
| idle 映射 | `grep -c '等待第一下' mobile/src/ui/practice_screen.gd` ≥ `1`；`grep -c '待机'` ≥ `1`（比较用的字面量） |
| 三支布局文案 | `grep -c '按住 R1，连按两下 □'` ≥ 1、`grep -c '按住 RB，连按两下 X'` ≥ 1、`grep -c '布局未确认，请返回引导重选'` ≥ 1 |
| 颜色常量 | `grep -c 'Color("#66BB6A")'` → 1、`grep -c 'Color("#EF5350")'` → 1（十六进制按本契约的常量**逐字大写**；语义是"全项目只有这两处颜色覆写"） |
| 无动画/音效/震动 | `grep -rE 'create_tween|AnimationPlayer|AudioStreamPlayer|vibrate_handheld' mobile/src/ui mobile/src/input` → 0 命中 |
| 判定推进点唯一 | `grep -rn 'runtime.tick(' mobile/src/ui` → 只在 `main.gd` 命中 |
| 边沿唯一消费者 | `grep -rn 'button_edges' mobile/src/ui/onboarding_screen.gd mobile/src/ui/practice_screen.gd` → 无命中 |
| 字形闭世界 | `python3 tools/make_font_subset.py --check` 退出 0；`bash mobile/tools/gate-a.sh` 含 `GLYPH_OK` 与 `✓ 闸门 A 通过` |
| 1 m 可读性 | D0 / D4 真机截图：不眯眼读出 `%Reason`；失败原因不压 `%DebugPanel` |
| 判定只出现一次 | `test_green_slice`：`_check_single_shot_success` 恰好 1 条 + 二次 drain 为空；`_check_two_shots` 恰好 2 条且 `seq` 严格递增 |
| 未确认布局零判定 | `test_green_slice._check_layout_gate`（`pop_outcomes()` 为空、`hits == 0`）+ `test_onboarding_flow._check_layout_never_preconfirmed` |
| D0 停止条件可达 | `grep -c '没有收到摇杆事件' mobile/src/ui/onboarding_screen.gd` ≥ 1，同文件含 `events_motion`；真机 D0 复现时抄录原句即判失败 |

---

## Registry Safety

| Registry | Blocks Used | Safety Gate |
|----------|-------------|-------------|
| shadcn official | none | not required（无设计系统包；不存在 registry 拉取） |
| third-party | none | not applicable |

本阶段不安装任何前端依赖；唯一的一次性工具是既有的 `fonttools==4.60.2`（经 `uv run --with`
子进程调用，版本已人工放行，不新增依赖、不改 `FONTTOOLS_SPEC`）。

---

## Checker Sign-Off

- [ ] Dimension 1 Copywriting: PASS
- [ ] Dimension 2 Visuals: PASS
- [ ] Dimension 3 Color: PASS
- [ ] Dimension 4 Typography: PASS
- [ ] Dimension 5 Spacing: PASS
- [ ] Dimension 6 Registry Safety: PASS
- [ ] Dimension 7 Inventory Provenance: PASS

**Approval:** pending

## UI-SPEC COMPLETE
