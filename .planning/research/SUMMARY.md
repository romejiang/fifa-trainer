# Project Research Summary

**Project:** FIFA 花式动作练习器（桌面 + 安卓）
**Domain:** Android-first 实时手柄轨迹识别 + 视觉反馈（Godot 4 移植已验证的 Python/pygame 桌面应用）
**Researched:** 2026-11-04
**Confidence:** HIGH（可行性、栈选型、移植契约）/ MEDIUM（真机手感与设备矩阵）

---

## Executive Summary

这是一个**纯本地、离线、单用户**的手柄肌肉记忆训练器：手机架在手边，接 Xbox / DualSense，用真摇杆练 5 个 FIFA 花式动作，做对了给反馈，做错了告诉你是快了、慢了还是起点不对。它要把一个已跑通、有 230 项自建检查的 3,700 行 Python/pygame 桌面应用 1:1 搬到 Godot 4.7.2 + GDScript。**这次移植异常可行，因为 Python 侧的领域核心本来就是纯的**——`geometry → config → detectors → engine` 除了通过一个输入适配器之外不依赖 pygame。把这套 DAG 原样复刻成 GDScript，约 80% 的工作是机械翻译；剩下 20% 是四件被引擎强制改变的事（采样模型、时钟、UI 通知机制、只读 `res://`）和一件原设计本身的缺陷（GUI 反向伸进引擎内部）。推荐的形态是：`src/core/` 为纯 `RefCounted`、零 Godot API、可 headless 测试；外面套一层薄平台适配器；用**双运行时轨迹回放对等性（trace-replay parity）**证明移植正确，而不是靠"看起来一样"。

**真正难的不是移植，是安卓。** Godot 的安卓手柄通道是一套自研的、非 SDL 的实现：没有映射数据库、没有 GUID、`get_joy_info()` 恒为空、`is_joy_known()` 恒 false，而且**完全没有手柄震动**。四份研究在三点上收敛，这三点必须在设计里就成立、不能事后补：(a) **事件驱动采集 + 真实时间戳**，因为 60 Hz 轮询会丢掉帧内反向，而弧线检测器的旋转累加器依赖每一个有符号增量；(b) **用户引导的逐设备轴/扳机探针**，因为轴序号与扳机静止值在安卓上没有保证；(c) **视觉反馈必须自成闭环**，不能有任何一条信息只靠震动传达。

**必须立刻纠正 PROJECT.md 的一个技术前提。** Key Decisions 与 Context 两处都写着"外接手柄与震动是引擎级 API（`Input.start_joy_vibration()`），不需要自己写 platform channel"。前半句对，后半句在安卓上**不成立**：`Input.start_joy_vibration()` 在安卓上是**静默空操作**——`has_joy_vibration()` 因为安卓平台层从不注册 joypad features 而恒为 `false`，调用只写进一张内部 HashMap 就再无出口。安卓上唯一可用的震动通道是 `Input.vibrate_handheld()`，它震的是**手机本体，不是手柄**。这条决策必须被标记为部分失效，并在 roadmap 中改写成三级震动契约（桌面手柄马达 → 手机本体 → 静默），手柄层用 `has_joy_vibration()` 门控，且**任何"已震动"的 UI 声明都必须经过真人确认**。把这件事当成"按型号差异极大的尽力而为"——FEATURES.md 与 ARCHITECTURE.md 都这么写了——正是会做出"测试全绿但用户毫无感觉"的假功能的那条路。

---

## Key Findings

### Recommended Stack

锁定 **Godot 4.7.2-stable**（2026-08-18）。注意"Godot 4.x LTS"这个选项**不存在**：官方策略是"新 major 发布后才把上一个 major 转为 LTS"，所以现在只有 3.6 是 LTS，要等 Godot 5 出现 4.x 才会变 LTS。正确做法是跟随当前 stable 分支的最新补丁。4.8 目前是 beta2，官方明确不用于生产；4.6 会在 4.8 发布后降为 partial support。渲染后端用 **Compatibility（OpenGL ES 3.0）**，把 minSdk 压回 24（Vulkan 路径强制 29），纯 2D 用不上 Mobile/Forward+。

**Core technologies:**
- **Godot 4.7.2-stable（标准版，非 .NET）** — 引擎/渲染/输入/场景 — 当前 stable 最新补丁；4.7 起 GDScript 可直接实现 Java 接口（`JavaClassWrapper`），让"不写插件也能碰 Android API"成为现实路径
- **GDScript 2.0（非 C#）** — 全部业务代码 — 纯 2D + 5 个动作 + 无热路径性能压力；C# 在 Android 上官方标注 experimental，且会引入第二个工具链、APK 体积翻倍
- **Compatibility 渲染后端** — 2D 渲染 — minSdk 24、老设备兼容性最好、启动更快更省电
- **JSON 配置 + 手写强类型校验器** — 与 Python/CI 共享 `shared/skills_config.json` — `.tres` 是 Godot 私有格式，桌面版读不了，等于制造第二真源（正是 PROJECT.md 明令禁止的债务）
- **JavaClassWrapper + AndroidRuntime（引擎内置）** — 零插件调 `android.os.*` — 补 `vibrate_handheld` 覆盖不到的场景（如申请 120 Hz 显示模式）
- **GUT 9.7.1 / gdUnit4 6.2.3** — 备选测试框架 — 见"跨文档分歧"一节：**本建议不采纳为默认**，理由在下方
- **Temurin JDK 17 + Android SDK（非 Homebrew）+ build-tools 36.1.0** — 导出工具链 — 版本取自 4.7.2 源码 `config.gradle`；官方文档页仍写 35.0.1/android-35，**已过期**
- **Python 3.11+（复用现有 uv 环境）** — `tools/sync_config.py` 同步与 hash 校验 — 不新增依赖

**关键版本约束：** 导出模板必须精确等于 `4.7.2.stable`（含 `.stable` 后缀）；`mobile/project.godot` 的 `config/features` 会是 `PackedStringArray("4.7", "GL Compatibility")`，**禁止用 4.8 打开工程**（会静默升级工程格式）；CI 加一条 `godot --headless --version` 断言。

**最小可行工具链（侧载 APK）**：JDK 17 + platform-tools + build-tools 36.1.0 + 官方 APK 模板。**不需要** `platforms;android-36`、**不需要** NDK、**不需要** Gradle build。只有要 AAB / 原生插件 / 自定义 manifest 时才升级到 Gradle build。

---

### Expected Features

产品重心不是"更多动作"，而是**让一次尝试的结果在 1 秒内被看懂，并且整场练习不需要碰屏幕**。桌面版已经解决了"判得准"，移动版要解决的是"看得懂 + 不用手"。判定一致性是底线（不是特性），**免触摸循环 + 量化反馈**才是移动版真正的产品价值。

**Must have（v1 table stakes）：**
- **判定与桌面版逐项一致（5 个动作）** — 这是产品定义本身，230 项检查是验收规格书
- **手柄连接 + "按任意键唤醒"图文引导** — 安卓蓝牙手柄在收到第一次输入前**不会出现在输入列表里**；B 站/论坛大量"连不上"其实都是没按键
- **断连检测 + 自动重连（掉线不算失败）** — 沙发场景蓝牙必掉
- **摇杆校准（中点 + 满量程）** — 弧线阈值按归一化半径算；磨损摇杆推不到 1.0 会把硬件问题判成"你转得不够"
- **待触发 / 冷却状态可见** — 配置里有 `release_hold_ms` / `cooldown_ms` / `idle_timeout_ms`，用户必须知道"现在这一下算不算"
- **免触摸自动循环（做完自动进下一次）** — 手在手柄上、手机在架子上；每做一次都要点屏幕 = 产品不可用
- **失败原因一行说清（大字号）+ 实测值 vs 目标区间时序条** — 只说"780 ms"没意义；给出 600–750 ms 绿带 + 本次落点，一眼定位偏差方向
- **一组 10 次 + 组内进度点 + 最近尝试列表**
- **暂停/恢复（必须重置检测器 + 3 秒倒计时）** — 绝对时间轴在恢复时会算出巨大 elapsed → 误判"太慢"，这是移动端最容易被忽略的判定污染源
- **屏幕常亮 + 横屏锁定 + 架子距离可读的字号（正文 ≥ 20 sp）**
- **手柄布局标识切换（Xbox / PlayStation）+ 按键确认页**
- **本地持久化（重开还在）**
- **震动（见下方纠正后的口径）+ 音效开关**

**Should have（v1.x，验证后再加）：**
- **本次轨迹回放（0.5×，失败点高亮）** — 移动端最缺的正是"我看不见自己做了什么"；只需一次尝试的采样环形缓冲，不需要录像
- **示范一次（参考轨迹按需播放，播完隐藏）** — Frame Dojo 的 "Show me"
- **序列动作逐步拆解** — 总时长 620 ms 达标但第 2 步慢了 90 ms，只看总时长永远修不好
- **每动作准确率趋势 + 弱项加权 + 混合练习（交错）** — 交错练习证据较稳，但**练的时候感觉更差**，所以两种模式都要给
- **组末/会话小结、干净连击、手柄当遥控器、节奏音**

**Defer（v2+）：**
- 掌握等级（铜/银/金）— 需要样本量与防刷设计
- 多手柄档案对比 — 需要可靠设备标识，安卓上成本高
- 统计导出/导入、竖屏/平板排版、动作库扩充（>5）、难度档

**明确拒绝（anti-features，roadmap 阶段直接拒绝）：** 账号/云同步、排行榜、社交 feed、广告、强制教程、**虚拟摇杆/触屏搓招**、自动收紧判定阈值（历史数据立刻不可比）、单一总分、**常驻参考轨迹 ghost**（Guidance hypothesis：持续视觉引导让练习表现变好、留存变差）、失败时自动慢放教学弹窗、**自动识别手柄型号并静默改映射**、XP/金币/皮肤/每日签到、严格每日连续打卡（断一天清零）、悬浮窗覆盖游戏。

**关键设计约束（隐藏的关键路径）：** **检测器必须输出结构化度量，而不只是错误码。** "实测 vs 目标区间""逐步拆解""失败点高亮"全都要求检测器额外输出 `measured{}`（起止角、扫过角、每步耗时、保持时长）。这一层要在**移植检测器时**就留出接口，否则后面所有反馈特性都要返工。

---

### Architecture Approach

这套架构能干净移植的根本原因：**Python 的领域核心已经是纯的**，`geometry → config → detectors → engine` 只通过 `PadState` 接触 pygame。在 GDScript 里复刻同样的 DAG 即可。但**五件事必须改**——四件是引擎强制的，一件是原设计的缺陷：

1. **固定 250 Hz sleep 循环 → 每帧一次采样**，Δt 可变。固定周期循环死亡。
2. **绝对时间轴追帧 + `overruns` 计数器 → 帧间隔检测器**（Δt 超阈值就放弃进行中的手势）。无事可追。
3. **`time.perf_counter()` → `Time.get_ticks_usec() / 1000.0` 全链路毫秒**。**永远不要用 `delta`**：它被钳制在 `max_physics_steps_per_frame / physics_ticks_per_second`（默认 ≈133 ms）且可能被 delta smoothing 后处理——300 ms 的安卓卡顿会被报成 133 ms，400 ms 的手势可能被判进 250–600 ms 窗口。
4. **GUI 读 `engine.skills[i].detector` 并就地改 `Skill` → 信号 + 不可变快照 + 命令方法 + `user://` 覆盖层**。`res://` 导出后只读；`assert()` 在 release 被剥离。
5. **（要修的那件）** **`src/core/` 里零 `Input` / `Time` / `Node` / `print` / `FileAccess`**，用 lint 测试强制。引擎不再持有 `TextIO`，GUI 不再在采样回调里跑渲染。

**Major components:**
1. **L0 `Main`（组合根）** — 加载配置、构造对象图、连信号 — 唯一同时知道 core 与 UI 的地方。**零 autoload**：autoload 就是"更好的语法写同一个 Python 缺陷"（全局可达的可变单例）。
2. **L1 平台适配器（Node）** — `GestureRuntime`（时钟 + tick + 信号，`process_priority = -100`）、`GodotInputSource`、`GodotRumbleSink`、`ReplayerSource`（dev/test）。**只有这几个能碰 `Input` / `Time` / `OS`。**
3. **L2 Core（纯 GDScript，`RefCounted`，可 headless）** — `GestureEngine`（朝向、手势锁、修饰键过滤、冷却、统计、失败排空、震动序列）、三类 `Detector`、`AppConfig`/`Skill`/`Step`/`Pulse`、`ConfigLoader`/`ConfigValidator`、`SessionSnapshot`。
4. **L3 表现层（Control）** — `SticksPlot`（`draw_polyline` 环形缓冲）、`StatsPanel`（**10 Hz 文本节流**）、`OutcomeFeed`、`ErrorScreen`。只读 `SessionSnapshot`。
5. **L4 数据** — `res://assets/config/skills_config.json`（同步、hash 钉死）+ `user://config/overrides.json`（稀疏覆盖）。

**关键模式：** 信号出、快照入、命令改；`PadSample` 与 `Frame` 分离（前者给适配器，后者给检测器）；`RefCounted` 而非 `Resource`（Resource 按路径缓存，`load()` 两次返回**同一实例**，可变状态会跨场景静默泄漏）；`assert()` 绝不用于用户可见校验（release 被剥离，且安卓没有 console）；`res://` 下 `.json` 是**非资源文件**，导出预设必须填 `*.json`。

**采样率的真实数字（来自本项目配置）：** 所有 5 个动作 `min_duration_ms = 250`、`max_duration_ms = 600`、`idle_timeout_ms = 250–350`、`release_hold_ms = 120–150`、`global_cooldown_ms = 60`、tap `min_interval_ms = 400`。结论：**没有阈值需要预先修改**（每个窗口 ≥ 3.6 个样本，时长都由时间戳算所以测量值精确，只有*判定瞬间*被量化）。最紧的是 `global_cooldown_ms = 60`（60 Hz 下只有 3.6 个样本，一帧抖动 = ±28%），但它也是最无害的（只影响双击抑制，而那里已经有两道闸）。**不要预防性放宽——先用夹具证明漂移，再带着证据放宽。**

---

### Critical Pitfalls

1. **把 `Input.start_joy_vibration()` 当成安卓上可用的手柄震动** — 不报错、不抛异常、`get_joy_vibration_strength()` 还会返回你设的值，但手柄永远不震。**避免：** 把震动建模成三态能力（`CONTROLLER` / `DEVICE` / `NONE`），安卓默认 `DEVICE` 或 `NONE`，**永远不默认 `CONTROLLER`**；绝不用返回值 / `has_joy_vibration()` / `get_joy_vibration_strength()` 作为"用户感觉到了"的证据——唯一有效证据是真人确认。`vibrate_handheld()` 在 UI 上必须标注为"手机震动"。
2. **假设安卓手柄映射等于桌面 SDL 映射** — 右摇杆轴序/符号不同、扳机对调、DualSense 某些三星机上扳机报"永久按下"。检测器照样跑、照样出结果——只是全错。**避免：** 首次运行做引导式"手柄检查"屏（推右摇杆上/右/下/左，按 L1，扣右扳机），记录哪个轴变化、符号、静止值、哪个按钮索引触发，按 `get_joy_name()` + 用户标签持久化成 per-device profile；**永不硬编码轴序号**。
3. **在 `_process` 里轮询 `Input.get_joy_axis()` 而丢掉帧内反向** — 60 Hz 只看到每帧最后一个值；快速假动作（右→左→右 30 ms 内）塌缩成一次净位移，弧线检测器的 `acc` 被污染。设备负载下降帧到 30–45 Hz 时更严重。**避免：** 在 `_input(event)` 里捕获 `InputEventJoypadMotion`，按到达顺序逐条推给检测器；渲染用最新快照，判定用事件流。
4. **移植了 `detectors.py` 却没移植 `engine.py` 的仲裁** — 一次手势被两个动作同时认领、同一次动作既报成功又报失败、失败归错动作、冷却吞掉连击、"10 个一组"计数错。**避免：** 把 `engine.py` 当**一个单元**移植，保持同样的方法边界（`_tick` / `_discard_other_claims` / `_drain_failures` / `_buttons_ok` / `_fire`）；**"引擎对等"是与"检测器对等"并列的独立交付物**，两者都过才能进 UI。
5. **角度约定搞错（0° = 上，顺时针为正）** — Python 的 `angle_of(x, y)` 是 `atan2(x, -y)`；Godot 的 `Vector2.angle()` 从 +X 起、屏幕 Y 向下，天真的 `atan2(y, x)` 给出 0° = 右、90° = 下。搞反后每个 `start_angle` 都旋转 90° 且镜像，"马赛回旋"（`start_angle: 180`，向后）会在用户前推时触发。**避免：** 逐行翻译 `geometry.py`，**保留 `x == 0.0 and y == 0.0 → return 0.0` 的守卫**（`atan2(0.0, -0.0)` 是 π，中心会显示"向后"）；在手势代码里禁用 `Vector2.angle()` / `Vector2.rotated()` / `atan2(y, x)`；八方向 + 中心单测。
6. **用 `Input.get_vector()` / action 死区替换项目自己的径向死区重缩放** — Python 的 `_deadzone` 径向重缩放到 `min(1.0, (m-dz)/(1-dz))`、保角度、对角线 `magnitude` 可 > 1.0（最多 ~1.41）；Godot 的 `Input.get_vector()` 是圆形死区并把结果钳到 1.0。同一个物理位置会在不同点越过 `enter_threshold: 0.72`。**避免：** 逐字移植 `_deadzone`，喂裸 `get_joy_axis` 值；`InputMap` 只留给 UI 导航；用 8 方向 × 5 量级夹具断言与 Python 差 < 1e-4。
7. **把逐样本魔数原样搬过来** — `swept >= 5.0`、`angle_diff(ref, angle) >= 2°`、`_last_path_t >= 0.008` 在 250 Hz 与 60–125 Hz 下含义不同。`>= 2°` 在 60 Hz 下几乎每个运动样本都成立 → "中途停住"实际停止触发。**避免：** 盘点每个逐样本常量，分成"率无关"（度/毫秒阈值）与"率依赖"（逐样本增量）；把率依赖的重写成**角速度**或**距上次变化的时间**；桌面对等夹具必须同时跑 60 / 120 / 突发不规则 三条同手势轨迹。
8. **中文 UI 依赖安卓系统字体回退** — Godot 默认字体 Open Sans 无 CJK 字形。官方文档警告安卓上加载系统字体不可靠（没有官方 API，Godot 解析厂商可改的配置文件）。开发者 Pixel 上完美，朋友的小米/华为上是豆腐块——而**这个项目的整个 UI 都是中文**，这是产品级失败不是外观 bug。**避免：** 在 P3 就定字体（内嵌 Noto Sans SC 子集，或 `SystemFont` 显式回退列表 **+ 内嵌兜底**）；把最长的中文字符串（动作名 + 失败原因 + 度数文字）放首屏，**在两台不同 OEM 手机上截图**；字形测试必须含 `° ± → ✓ ✗` 和数字。
9. **用安卓模拟器验证这个产品** — 模拟器没有蓝牙手柄、没有真震动、输入派发不同、帧节奏不同、没有 OEM 字体栈。本项目的每一个真实风险（配对、映射、延迟、断连、息屏）都不会被触发。**避免：** 把"真手机 + 真手柄"设为**阶段退出条件**，不是 P9 的锦上添花；模拟器只用于布局截图与非输入回归。

**其他高危项（不可漏）：** `delta` 或墙钟时间进入判定路径（C4）；无暂停/恢复/息屏/重连的不连续处理（C5，恢复后首帧会算出巨大 elapsed → 误判"太慢"）；XP 手柄老款（型号 1537/1697）**没有蓝牙**根本连不上手机；`*.json` 没加导出非资源过滤 → "编辑器能跑、APK 报错"；两块 `skills_config.json` 漂移 + 试图往 `res://` 写配置；keystore 泄露或换 key 导致每次更新都要卸载（会清空 `user://` 统计）。

---

## Cross-Document Disagreements — Resolved

四份研究在三处实质性冲突。**不取平均，逐条裁决。**

### D1. 输入采集：轮询 vs 事件驱动（STACK + PITFALLS vs ARCHITECTURE）

- **STACK.md**：用 `_input()` 收 `InputEventJoypadMotion`，**收到即** `Time.get_ticks_usec()` 打时间戳；明确禁止 `_process` 里轮询，理由"会丢中间值"；并建议 `Input.set_use_accumulated_input(false)`。
- **PITFALLS.md C3**：同结论，并补充"默认缓冲下 `InputEventJoypadMotion` 不实现 `accumulate()`，所以运动事件不会被合并，全部到达，只是时间戳都在帧末"。
- **ARCHITECTURE.md**：主张**轮询** `Input.get_joy_axis()` 每帧一次，理由是它给出"某个瞬间所有轴与按钮的一致快照"，而 `_input` 是逐轴交错到达、需要自己携带其他轴。

**裁决：采纳事件驱动，但保留轮询快照作为 UI 通道。** 理由不是"谁更新"，而是**事件捕获是轮询的严格超集**：它永远不会丢掉轮询能保留的信息，且可能额外保留亚帧时序；反过来不成立。ARCHITECTURE 的反对意见（逐轴到达需要携带其他轴）是**真实的实现成本，但只是约 30 行**：维护一个 `PadSample` 携带缓冲，每个事件更新对应轴、用 `Time.get_ticks_usec()` 打戳、发出一条完整样本。而它的核心论点"轮询给一致快照"在负载下降帧到 30–45 Hz 时恰恰失效——那正是最需要分辨率的时候（ARCHITECTURE 自己的设备矩阵就写了这一行）。

**保留 ARCHITECTURE 的正确部分：** UI 每帧读一次 `snapshot()` 做渲染；`Input.get_joy_axis()` 仍用于死区可视化与"当前值"展示。`InputSource` 端口从 `poll(t_ms) -> PadSample` 改成 `drain() -> Array[PadSample]`（或 `poll` 仍存在但仅供 UI）。

**未决且必须实测：** `set_use_accumulated_input(false)` 在安卓上是否真的产生亚帧时间戳。STACK 从源码推断"收到即派发"，但 Godot 安卓的 JNI 回调发生在 Android UI 线程，而主循环在另一线程——这一点两份文档都没有实证。**因此：** 先按事件驱动实现（无论时间戳粒度如何，它都保序且不丢反转），然后在 Phase 5 用真机记录 `t_ms` 差值的 p50/p95/max 直方图，再决定是否需要 `agile_event_flushing` 或原生时间戳。这是一个**设备 spike 项，不是设计阻塞项**。

### D2. 震动：三级降级 vs 视觉优先 vs 按型号尽力而为（四份文档三种说法）

- **STACK.md**：明确"安卓上 `start_joy_vibration()` 是静默 no-op（源码 + 官方文档双重确认）"；主张把 `vibrate_handheld()` 当作**主路径而非兜底**（标注为 MEDIUM — 产品判断）。
- **PITFALLS.md C1**：同意机制（"不是尽力而为，是**不存在**"），但产品结论更保守：**按纯视觉设计，震动只是加分项**；`vibrate_handheld` 必须标注为"手机震动"，不得呈现为手柄反馈。
- **ARCHITECTURE.md**：`GodotRumbleSink` 直接用 `start_joy_vibration` / `has_joy_vibration`，并写"Android reliability is device-dependent → must degrade silently"。
- **FEATURES.md**：写"Godot 安卓端手柄震动**按型号差异极大**（Xbox 有线常可用，DualSense 常不可用）；先让用户按一下测试"。

**裁决：STACK 在机制上权威，PITFALLS 在产品结论上正确，ARCHITECTURE 与 FEATURES 的"按型号差异"模型是错的。**

- 机制：**安卓上 Godot 没有任何手柄震动实现**，与型号、固件、有线/蓝牙全部无关。`has_joy_vibration()` 在安卓上恒为 `false`（`set_joy_features()` 全仓库只有 SDL 驱动调用，安卓走自研 `InputDevice` 路径）。FEATURES/ARCHITECTURE 的"按型号"说法来自对 Godot issue #73446 与 PR #109645 的误读——那些是 SDL 摇杆支持，不是震动。
- 产品：**不要**像 STACK 那样把手机震动抬成"主路径"。它震的是手机不是手柄，语义不同（用户会以为手柄在反馈）；而且手机多半架在支架上、甚至放在腿上，可感知度不稳定。正确口径是 **PITFALLS 的：视觉自成闭环，手机震动是一个明确标注、可关、默认可试的附加通道**。
- 接口：保留 ARCHITECTURE 的 `Haptics` 三层抽象（这是好的设计），但**必须把 `has_joy_vibration()` 门控放在 L1**，且安卓上 L1 永远是死的。

**对 FEATURES 的连带修正：** "震动自检（先让用户按一下测试，再决定是否指望它）"这条 P1 特性**保留但改语义**——它测的是**手机本体震动**，并在 UI 上写清楚。不要做一个"测试手柄震动"的按钮，那会 100% 失败并让用户以为手柄坏了。

### D3. 测试框架：GUT vs 手写 `SceneTree` runner（STACK vs ARCHITECTURE）

- **STACK.md**：默认 **GUT 9.7.1**（9.7.0 专门适配 4.7 更严格的返回值类型检查），gdUnit4 6.2.3 备选；给了完整的 `gut_cmdln.gd` 命令与 JUnit XML 用法。
- **ARCHITECTURE.md**：推荐 **40 行手写 `extends SceneTree` runner**，明确说"GUT / GdUnit4 是备选——都成熟且 CI 友好，但它们引入 addon、配置文件、和第二套断言方式。对 ~200 条纯 `RefCounted` 断言，手写 runner 是更好的权衡"。

**裁决：默认手写 `SceneTree` runner，GUT 9.7.1 作为已论证的逃生口。** 理由：(a) 本项目今天没有 CI、没有 pytest，测试是自建 `check()` 脚本——手写 runner 与既有文化零迁移成本；(b) 断言主体是"遍历 JSONL 轨迹 → 喂纯函数 → 比对 `Outcome.code`"，这是**循环**而不是框架特性；(c) addon 目录会被 Godot 导入并需要排除出导出包，而本项目在做侧载 APK 体积控制；(d) STACK 自己记录的 9.6→9.7 breaking change 恰好说明"第三方框架与引擎版本耦合"是一个真实成本。

**触发切换的条件（写进 phase 计划）：** 需要 mock、需要场景级输入回放、或 CI 需要 JUnit XML 报告时，切 GUT 9.7.1（**必须 ≥ 9.7.0**，9.6.x 在 4.7 上会报错）。这是低风险可逆决策，不要在这上面纠缠。

### D4. 扳机轴范围（STACK 精确 vs ARCHITECTURE 待验 vs PITFALLS 逐设备变化）

- **STACK.md（源码级，HIGH）**：安卓上扳机**已经是 `0.0..1.0`**（`input.cpp` 里有 `#ifndef ANDROID_ENABLED` 专门分支），桌面才是 `-1.0..1.0`。
- **ARCHITECTURE.md**：`JOY_AXIS_TRIGGER_*` 实践上报 0..1 — **MEDIUM，需真机验证**。
- **PITFALLS.md C9**：安卓上静止值与极性**按手柄变化**，要校准 `-1` vs `0`。

**裁决：以 STACK 的 0..1 为预期实现，但按 PITFALLS 保留逐设备静止值校准作为启动探针。** 两者不矛盾：STACK 说"引擎层做了 0..1 归一"，PITFALLS 说"别信任何单一假设，探一下"。代价是 20 行；收益是朋友寄来一台杂牌手柄时不用改代码。**不要**把 `-1..1` 当默认分支——那会引入 STACK 已排除的桌面行为。

### D5. 轴映射：固定 JoyAxis vs 逐设备探针（ARCHITECTURE vs STACK + PITFALLS）

- **ARCHITECTURE.md**："**彻底删掉 `AxisLayout` 推断**"，依赖固定的逻辑 `JOY_AXIS_LEFT_X=0 … RIGHT_Y=3`（SDL GameController DB）。这条对**桌面**成立。
- **STACK.md**：安卓上 `fallback_mapping == -1` → 原始轴序号直通；典型蓝牙手柄排序后下标恰好 0..5 **能用但脆**；同时上报 RX/RY 与 Z/RZ 的杂牌手柄会错位。
- **PITFALLS.md C2**：必须做逐设备探针 + profile，永不硬编码。

**裁决：ARCHITECTURE 的"删掉推断"对桌面正确、对安卓错误。采纳 STACK + PITFALLS 的混合方案。** 关键区别：Python 那 250 行是**运行时自动推断**（该删）；我们要的是**用户引导的探针 + 持久化 profile**（约 40 行 + 一个屏）。既不是一个数量级的复杂度，也不依赖不可靠的自动识别。`Input.get_joy_name()` 作主标识（能拿到 `"Xbox Wireless Controller"` / `"DualSense Wireless Controller"` / `"Wireless Controller"`），`get_joy_guid()` 只当不透明字符串当稳定 key 用——它返回的是**设备名的十六进制串**，不是 `03000000...` 形式的 SDL GUID。

### D6. 手柄布局标签：手动选择 vs 自动识别（FEATURES vs PITFALLS）

- **FEATURES.md**：**手动选布局 + 按键确认页**，理由"Android 上拿不到 raw name / vendor id，DualSense 还会被系统改写按钮布局，猜错比不猜更糟"。
- **PITFALLS.md（UX 表）**：按检测到的手柄显示品牌对应标签，未知时两者都显示。

**裁决：两者合一——自动**建议**、手动**确认**、永不静默。** FEATURES 说"拿不到 raw name"略过头：`get_joy_name()` 是可用的（STACK 明确说它是主标识）。所以可以从名字字符串匹配 `Xbox` / `DualSense` / `Wireless Controller` 得到**建议值**，但必须让用户在按键确认页覆盖它，并且**永远不要**因为猜对了一次就静默应用映射。这既保住了 FEATURES 对"猜错更糟"的警惕，又去掉了不必要的手动负担。

### D7. 阶段顺序：先安卓管线 vs 先纯核心（PITFALLS vs ARCHITECTURE）

- **PITFALLS.md**：P3 就是"安卓构建管线 + 真机冒烟"，理由是"签约 APK 装不上真机之前不要开始检测器工作"；且 C15 说模拟器验证是致命的。
- **ARCHITECTURE.md**：安卓设备层放到 Phase 8（UI 之后），理由是"设备工作是唯一不能单测的部分，必须落在稳定核心上，失败才不含糊"。

**裁决：两者都对，因为它们说的不是同一件事。** 拆成两次"碰安卓"：
1. **尽早（Phase 2）：工具链 + hello-world 冒烟 APK。** 目标是证明 JDK17/SDK/模板版本对得上、16 KB 页对齐能装、侧载能过、中文字体不豆腐、`*.json` 真的进了 PCK。这是 1–2 天，不是设备层。
2. **靠后（Phase 5）：完整设备输入层**（轴探针、扳机校准、热插拔、设备身份）。此时核心已被轨迹回放证明，输入 bug 与检测 bug 不会互相冒充。

这个拆分同时满足 PITFALLS 的"别在没装过真机前写检测器"和 ARCHITECTURE 的"别在核心不稳时做设备工作"。

### D8. 无争议的强共识（三份以上一致，直接采纳）

这些**没有**分歧，roadmap 可以当作已定事实：`Time.get_ticks_usec()` 是唯一时钟、`delta` 禁止进判定；死区必须自己实现且保留 >1.0 的 magnitude；`get_joy_info()` 在安卓恒空；`get_connected_joypads()` 顺序跨重启不稳定 → 永不持久化数字 device id；`res://` 只读 → 稀疏 `user://overrides.json`；`*.json` 需要导出非资源过滤；`assert()` 在 release 被剥离；`poll_hz` 在移动端只作为"上报值"不是调度指令；Godot 4.7.x + 真机 + 真手柄验证不可替代。

---

## Invalidated Assumptions in PROJECT.md

**这是本次研究对项目文档的唯一硬性修正，必须在 roadmap 之前落到 PROJECT.md。**

| 位置 | 原文 | 判定 | 应改成 |
|---|---|---|---|
| Context → 为什么选 Godot 4 | "外接手柄与震动是引擎级 API（`Input.start_joy_vibration()`），**不需要自己写 platform channel**" | **前半句成立，后半句在安卓上失效** | "外接手柄是引擎级 API；**震动在安卓上不是**——引擎的安卓平台层没有 rumble 实现，`start_joy_vibration()` 是静默空操作。安卓唯一通道是 `vibrate_handheld()`（震手机本体）。要真手柄马达必须写 Android v2 插件，已明确推迟。" |
| Key Decisions → 移动端用 Godot 4 + GDScript | "外接手柄与震动是引擎级能力；2D 与实时绘制轻量；免费且 Mac 可导出安卓" | **"震动"三字须删/改** | 选型结论不变（Godot 仍是最优），但理由改成"外接手柄是引擎级能力；**震动是视觉反馈的附加项，安卓上只有手机本体震动**" |
| Constraints → 反馈 | "安卓上外接手柄的震动支持**不可靠**（Xbox 蓝牙常完全失效，DualSense 亦不如 PC），因此震动必须可静默降级" | **方向对，事实弱化** | 不是"不可靠"而是"**不存在**"。改成："安卓上 Godot **没有**手柄震动实现。唯一可用通道是 `vibrate_handheld()`，震的是手机本体，必须明确标注且可关。视觉反馈必须自成闭环。" |
| Constraints → 采样率 | "移动端约 60–125 Hz……需要实测确认时序抖动可接受" | **成立，但补充机制** | 加一句："默认输入是每帧 flush 一次，同一帧内所有事件共享时间戳；须在 `_ready()` 调 `Input.set_use_accumulated_input(false)` 并在真机量化实际到达间隔分布。" |

**为什么这条不能只当成"一个功能的细节"：** PROJECT.md 的 Core Value 写着"震动是加分项，视觉反馈是主路径"——这个**优先级判断是对的**，但它建立在一个错误的**机制**前提上。如果 roadmap 按"按型号尽力而为"来规划，就会做出一个带 `has_joy_vibration()` 分支、带"震动已发送"日志、带自检按钮的功能，而这三样在安卓上**全部无效**。修机制、保优先级，是唯一正确的改法。

---

## Implications for Roadmap

基于四份研究的合并结论，建议 **9 个阶段**。顺序不是偏好，是依赖关系：**纯核心必须先于设备层，设备层必须先于 UI，UI 必须先于生命周期，震动永远不阻塞任何阶段。**

### Phase 1: 仓库拆分 + 配置单一真源 + 桌面回归闸门
**Rationale:** 阻塞一切。目录重构是机械改动但影响面广（PROJECT.md 已定"先搬目录再写移动端"），且 230 项检查是唯一的回归红线——搬完不绿就不许继续。配置真源与 hash 守卫必须此刻建立，否则后面每个阶段都在制造第二真源。
**Delivers:** `desktop/` + `shared/skills_config.json` + `mobile/`（空 Godot 工程骨架）；`tools/sync_config.py`（生成 `mobile/assets/config/skills_config.json` + `.sha256` + `config_stamp.gd`，支持 `--check` 退出码）；桌面 230 项检查全绿；`errors` / 已知 bug 的修正清单（BOM、string boolean、null numeric、`start_angle` 数组）落到共享夹具。
**Addresses:** 配置单一真源（PROJECT.md Active #2）
**Avoids:** C14（双份配置漂移）、m2/m3/m4（JSON 边界）
**Research:** 不需要——纯机械 + 已有代码。

### Phase 2: 安卓工具链 + 真机冒烟 APK
**Rationale:** 与 Phase 1 尾部可并行，**且越早越好**：手柄与第二台手机的采购/借用有前置时间；工具链版本错配是最高频的"卡三天"问题；16 KB 页对齐、侧载权限、中文字体、`*.json` 入包这四件事只能在真机上证明。这是 1–2 天的 spike，不是设备层。
**Delivers:** 签名 arm64 APK 能装能启动；首屏显示一段最长中文（动作名 + 失败原因 + `° ± → ✓ ✗`）**并在两台不同 OEM 手机上截图**；启动时读 `res://assets/config/skills_config.json` 并显示 `SKILL_COUNT`（同时证明 `include_filter="*.json"` 生效）；`Permission.VIBRATE` 勾选；`mobile/BUILD.md` 记录精确版本（Godot 4.7.2-stable / 模板 4.7.2.stable / JDK 17 / build-tools 36.1.0）；**release keystore 当天生成并离线备份**；`scripts/export_android.sh` + `doctor` 检查。
**Uses:** Godot 4.7.2 + Compatibility + Temurin JDK 17 + 官方 APK 模板（不装 Gradle build）
**Addresses:** "可侧载的安卓 APK"的第一个证据；CJK 字体决策
**Avoids:** C11（陈旧工具链）、C12（16KB 页）、C13（keystore）、M7（ABI/体积）、M11（macOS 路径）、C10（字体，决策 + 首次验证）、C15（模拟器验证）
**Research:** 不需要研究——需要的是**动手**。但必须在真机上做，模拟器不算。

### Phase 3: 纯核心 — 几何 + 领域模型 + 配置校验（对等性证明）
**Rationale:** `src/core/` 是唯一能 headless 证明的部分，也是整个移植的对等性契约。几何与配置校验先行，因为它们零依赖、失败信号最清晰、且后面所有东西都建在它们上面。
**Delivers:** `geometry.gd`（`norm_deg` / `signed_delta` / `angle_diff` / `angle_of`，含 `x==0 and y==0 → 0.0` 守卫；八方向 + 中心黄金表 与 Python 差 < 1e-9）；`PadSample` / `Frame` / `Hit` / `Failure` / `Outcome` / `AppConfig` / `Skill` / `Step` / `Pulse`（全 `RefCounted`，加载后不可变）；`ConfigLoader` + `ConfigValidator` + `ConfigError{json_path, code, message, fix_hint}`；`user://overrides.json` 稀疏合并 schema（`schema_version` + `base_sha256`，base 变了就丢弃覆盖）；**accept/reject 对等性语料在 Python 与 GDScript 双跑**。
**Uses:** JSON + 手写校验器；`Time` 不进 core（时间由参数传入）
**Implements:** L2 core 的 domain + config 层
**Avoids:** C7（角度约定，在此钉死）、m1–m4、C14 的写入路径、Anti-pattern 4（`Resource` 缓存）
**Research:** 不需要——Python 源码就是规格书。

### Phase 4: 检测器 + `GestureEngine` + 轨迹回放对等性 ★ 最高风险
**Rationale:** 这是产品定义本身，也是唯一"是否与桌面一致"是真问题的地方。**先做 UI 会让每个检测器 bug 看起来像 UI bug**，而 182 项检查会被对着一个移动靶移植。
**Delivers:** 三类检测器（arc / sequence / taps）1:1 移植，保留 7 方法生命周期（`update` / `reset` / `on_idle` / `abandon` / `observe` / `pop_failure` / `status`）与失败优先级顺序；**检测器必须输出 `measured{}` 结构化度量**（起止角、扫过角、每步耗时、保持时长）——这是"实测 vs 区间""逐步拆解""失败点高亮"的隐藏关键路径；`GestureEngine` 作为一个单元移植（手势锁、`held_required` 互斥、`_discard_other_claims`、单失败排空、逐动作 + 全局冷却、idle 重置、分组计数、`on_time_discontinuity`、`on_device_lost`）；`RumbleSequencer`（注入 no-op sink）；**trace-replay parity harness**：~40 条轨迹（每动作成功 1 条 + 每个失败码 1 条 + 阈值 ±1ms/±1° 边界 + CONCERNS 已知 bug #6/#7 + 双动作竞争 + 修饰键中途切换 + facing 无效）；`.expected.json` **由 Python 生成，绝不手写**；`tools/decimate_trace.py` 做 250→120/60 Hz 抽取（**抽取规则：取每个 `1000/hz` 边界最近的样本，但永不丢弃按钮沿**）；architecture lint 测试（`src/core/**` 禁 `Input.` / `Time.` / `OS.` / `FileAccess` / `DisplayServer` / `print(` / `get_tree(` / `preload("res://src/platform…")`）。
**Addresses:** 判定一致性（5 个动作，230 项检查中的 182 项）、检测器结构化度量
**Avoids:** C3（丢帧内反向——靠事件流契约）、C4（`delta` 进判定）、C6（只移检测器不移引擎）、M10（率依赖常量）、m1（精确浮点断言）
**Research:** **需要 `--research-phase`。** 唯一必须先量出来的问题：60 Hz 抽取是否保住 `release_hold_ms=120` 与 `global_cooldown_ms=60` 的判定。这是经验问题，用抽取矩阵回答，**不要靠推理**。

### Phase 5: 平台适配层 — 真手柄输入 + 可桌面运行的 demo
**Rationale:** 设备工作是唯一不能单测的部分，必须落在已被轨迹证明的核心上——否则输入延迟的产物和检测器 bug 无法区分。同时，`ReplayerSource` 驱动的 macOS demo 让你在**零手柄**的情况下开发 UI（对应桌面版的 `--demo`）。
**Delivers:** `GestureRuntime`（`process_priority = -100`；`now_ms = Time.get_ticks_usec()/1000.0`；`dt_ms > 50` 记 warn、`> 120` 调 `on_time_discontinuity()` 并 **return，不把不连续喂成样本**）；`GodotInputSource`：**`_input()` 捕获 `InputEventJoypadMotion`/`Button` + 携带缓冲 + 每事件时间戳**，`_ready()` 里 `Input.set_use_accumulated_input(false)`（单点决策 + 注释原因）；径向死区重缩放逐字移植（magnitude 不钳制）；扳机读 `JOY_AXIS_TRIGGER_*`、按设备校准静止值、归一到 0..1、超 `trigger_threshold` 合成 `LT`/`RT` 按钮；`joy_button_map.gd`（`A→JOY_BUTTON_A` … `DPAD_*`）；`event.device` 过滤 + 永不持久化数字 device id；**引导式轴探针屏**（推右摇杆上/右/下/左、按 L1、扣右扳机）写 per-device profile；`joy_connection_changed` → `engine.on_device_lost()` + 重连浮层；`ReplayerSource`；**真机实测并记录**：`t_ms` 差值 p50/p95/max、摇杆轴序号、扳机静止值、`get_joy_name()` 返回值、空闲 vs 活动事件率。
**Uses:** `Input.*`、`Time.get_ticks_usec()`；JavaClassWrapper（若需申请高刷）
**Implements:** L1 适配器 + `core/ports/input_source.gd`
**Avoids:** C2（安卓映射≠桌面）、C8（错死区模型）、C9（扳机当按钮）、M1/M2（device id / 多设备）、M3（空闲帧率塌陷）、m6、m8（`poll_hz` 当指令）、D1/D4/D5 裁决落地
**Research:** **需要 `--research-phase`（且必须含真机 spike）。** 目标矩阵：**2 台手机（尽量不同 OEM）× 2 个手柄（Xbox + DualSense）**。要回答的具体问题：右摇杆是否真的落在 `JOY_AXIS_RIGHT_X/Y = 2/3`；扳机是否 0..1；`set_use_accumulated_input(false)` 是否真的改变时间戳粒度；Xbox 蓝牙 LT/RT 是否对调；DualSense 在某机型上扳机是否报"永久按下"。

### Phase 6: 视觉反馈 UI + 纯手柄操作
**Rationale:** 对着 `ReplayerSource` 开发，不依赖手柄；但"结果必须在命中同一帧产生"这个时序契约由 Phase 4/5 提供，所以不能更早。
**Delivers:** `SticksPlot`（`draw_polyline` + 固定 256 点环形缓冲，**不要 `Line2D` + `antialiased=true`**——官方注记它不参与批处理，长轨迹会掉帧）；`OutcomeBanner`（**命中同一帧**产生，**最短停留 1.5 s**，即使下次手势开始也不立刻覆盖；成功/失败用 **颜色 + 图标 + 一个短词** 三重编码，1 m 外可读）；**实测 vs 目标区间时序条**（600–750 ms 绿带 + 本次落点）；一行大字号原因（"太快了"）+ 小字数值（"180 ms，需要 ≥ 250 ms"）；组内进度点 + 最近 5–50 条列表；`StatsPanel` **10 Hz 文本节流**（`Label.text` 赋值触发文本整形，120 Hz 下是整帧最贵的东西）；`ErrorScreen`（列出**每一条** `ConfigError`，含 `json_path`、复制按钮、恢复默认）；**纯手柄导航**（A 开始、Start 暂停、十字键换动作、B 返回；显式 `focus_neighbor_*` + `grab_focus()`；**无任何需要点击的模态**）；横屏 + `keep_screen_on` + 深色低亮主题；布局用 `Control` 锚点/容器，不是绝对坐标。
**Addresses:** 失败原因一行、实测 vs 区间、组内进度、最近列表、布局切换 + 按键确认、屏幕常亮、横屏、音效开关
**Avoids:** M4（反馈太快/太隐晦）、M5（必须要触摸）、M9（平板/安全区）、C10（字体，此处完成验证）、Anti-pattern 9（逐帧 `Label.text`）、Anti-pattern 10（`print` 当日志）
**Research:** 不需要——`Control` / `draw_polyline` / focus 导航都是成熟文档。需要的是**真人测试**：auto-advance 停留时长在 1.2 / 1.8 / 2.5 s 三档上试。

### Phase 7: 生命周期 / 断连 / 持久化韧性
**Rationale:** 桌面版拥有进程直到退出，没有应用生命周期——这是移植里最容易被整段删掉的一块。必须在 UI 建好之后、发布之前补上，且检测器在 Phase 4 就要暴露 `reset_hard()` / `abandon()` 钩子（否则此处要返工）。
**Delivers:** `NOTIFICATION_APPLICATION_PAUSED` / `_RESUMED` / `WM_WINDOW_FOCUS_OUT/IN`（**幂等**——安卓可能连发两次 PAUSED，#85265）；暂停时停采样、`stop_joy_vibration` 所有设备、记录暂停时刻；恢复时硬重置所有检测器、清 `_prev_pressed`、设 `ignore_until_ms = now + 150`、要求右摇杆在 `RELEASE_STICK` 以下持续 `gesture_release_ms` 才重新武装；**`has_axis_sample` 逐设备**（新连上的手柄在第一帧真实事件前所有轴报 0.0，不能当"摇杆居中"）；`user://progress.json` 原子写（temp + rename，容错缺失/损坏，含 `schema_version`），**每次结果就写或几秒 debounce，不是退出时写**；断连"丢弃不计失败" + 重连后回待触发；诊断屏（设备型号、Android 版本、手柄名、原始轴快照、实测事件率、最近 20 条结果、导出日志走系统分享）+ `user://logs/` 轮转。
**Addresses:** 暂停/恢复、断连自动恢复、本地持久化、诊断
**Avoids:** C5（无生命周期处理）、M6（进程被杀丢进度）、M8（朋友手机零诊断）、C13 的数据丢失后果
**Research:** 不需要——`NOTIFICATION_*` 与 `FileAccess` 都有文档。**但必须做真机验收**：后台 2 分钟中途返回、锁屏解锁、拔手柄再插（拿到新 device index）。

### Phase 8: 震动 — 仅手机本体，能力门控
**Rationale:** 明确"尽力而为"，**永不阻塞任何阶段**。放在这里是因为它依赖 Phase 5 的设备能力探测与 Phase 6 的反馈骨架；但即使整个阶段被砍掉，产品也完整。
**Delivers:** `Haptics` / `RumbleSink` 三层：**L1** `has_joy_vibration(d)` 门控 → `start_joy_vibration(d, weak, strong, duration_s)`（**永远传显式秒数，如 0.08**——`duration=0` 意味着"尽可能长（约 65 s）"，不是"瞬时"）——**安卓上这一层永远走不到**；**L2** `Input.vibrate_handheld(duration_ms, amplitude)`（API 26+ 真正使用 amplitude），UI 标注 **"手机震动"**；**L3** `pass`。`Permission.VIBRATE` 已在预设勾选；用户可关；自检按钮测的是**手机震动**并写清文案。**成功震、失败不震**（桌面版策略，正确：失败震动既惩罚又语义模糊）。**明确不做**：Android v2 插件、`VibratorManager`、手柄马达——除非三条件同时满足（真机验证 L2 手感不够 + JavaClassWrapper 走不通 + 用户明确要求），届时单独立项。
**Addresses:** "震动反馈尽力而为"（改写成"手机震动 + 静默降级"）
**Avoids:** C1（把 no-op 当功能）、"测试全绿但用户没感觉"的假功能
**Research:** 不需要研究——STACK 已经把机制钉死。需要的是**纪律**，加一次真人 A/B（30/50/80/120 ms 主观阈值）。

### Phase 9: 发布产物 + 侧载 + 升级路径
**Rationale:** 侧载不是"发个 APK"，它有自己的支持负担；且签名/包名/versionCode 的错误会造成**不可逆的数据丢失**，必须在第一次发给朋友之前验证。
**Delivers:** arm64-v8a Only、不勾 "Export With Debug"、`version/code` 递增、应用内可见版本号、文件名带版本（`fifa-trainer-0.3.2-7.apk`）；`zipalign -c -P 16 -v 4` 通过；`unzip -l` 确认无 `lib/x86_64/`、无 `.DS_Store`；发布 SHA-256 + 一页带截图的安装指南（"允许安装未知应用" / Play Protect → 仍要安装 / 各型号配对组合）；**v1→v2 同 key 升级测试，确认 `user://` 统计不丢、无需卸载**；`export_presets.cfg` 提交时**去除密钥**（用 `GODOT_ANDROID_KEYSTORE_RELEASE_PATH/USER/PASSWORD` 注入），pre-commit grep `storepass|keystore/.*password`。
**Addresses:** "可侧载的安卓 APK，朋友能装上就用"
**Avoids:** C13（keystore/包名/versionCode）、M7（ABI/体积/debug）、M8（侧载摩擦）、M12（密钥泄露）、M13（minSdk/targetSdk 与 Gradle 路径）、m5（预设名漂移）
**Research:** 不需要——但**必须在干净 clone 上跑一次脚本化导出**，并在一台 Android 15+ 设备上装一次。

### Phase Ordering Rationale

- **纯核心（3–4）先于设备层（5）先于 UI（6）。** 这是唯一不返工的顺序：检测器是唯一"是否与桌面一致"是真问题的地方；设备层是唯一不能单测的地方，必须落在稳定核心上；UI 是对着 `ReplayerSource` 开发的，建在会动的靶子上等于把检测 bug 化妆成 UI bug。
- **安卓只碰两次，不是一次也不是三次。** Phase 2 的 hello-world 冒烟（工具链 / 16KB / 字体 / JSON 入包）与 Phase 5 的完整设备输入层（轴探针 / 扳机 / 热插拔）是**两个不同的风险**，合并会让 1–2 天的 spike 变成 2 周的不确定性；拆成三次（再加发布）又会让工具链问题在最后才暴露。
- **生命周期（7）在 UI 之后、发布之前。** 它需要检测器的硬重置钩子（Phase 4 就要留），也需要 UI 的通知面（重连浮层、诊断屏）。放在发布前是因为"后台回来必失败一次""切个应用统计就没了"会直接毁掉产品感。
- **震动（8）与发布（9）可并行，且 8 可整体砍掉。** 这是唯一一个"删掉它产品依然完整"的阶段——正是 Core Value 说的"震动是加分项"的结构性体现。
- **`measured{}` 是隐藏关键路径。** Phase 4 不留接口，Phase 6 的三大反馈特性（实测条、逐步拆解、失败点高亮）全部返工。这是四份研究里最容易被忽略、代价最高的一条。

### Research Flags

**Phases likely needing `--research-phase` during planning:**
- **Phase 4（检测器 + 引擎对等性）：** 60 Hz 抽取是否保住 `release_hold_ms=120` / `global_cooldown_ms=60` 的判定；逐样本率依赖常量的重写方式（M10）。**这是经验问题，必须跑抽取矩阵，不能推理。**
- **Phase 5（平台适配层）：** 真机轴序号、扳机范围/静止值、`set_use_accumulated_input(false)` 的真实时间戳粒度、Xbox 蓝牙 LT/RT 是否对调、DualSense 在特定 OEM 上的扳机异常。**必须含 2 手机 × 2 手柄的实机 spike，产出实测表格再冻结容差。**
- **Phase 9（发布）：** `*.json` 在 4.7.2 上是否真的进 PCK——如果 Phase 2 的冒烟 APK 已加载配置并显示技能数，此项提前关闭；否则需一次真实导出而非读文档。

**Phases with standard patterns（跳过 research-phase）：**
- **Phase 1：** 目录重构 + hash 脚本 + 回归闸门——纯机械。
- **Phase 3：** 几何 + JSON 校验——Python 源码即规格书。
- **Phase 6：** `Control` 布局、`draw_polyline`、focus 导航——官方文档充分。需要的是**真人测试**（auto-advance 1.2/1.8/2.5 s），不是资料研究。
- **Phase 7：** `NOTIFICATION_*`、`FileAccess`、原子写——文档充分，需要真机验收清单。
- **Phase 8：** 震动机制已被 STACK 源码级钉死——不需要研究，需要纪律。

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| **Stack** | **HIGH** | 版本号与 API 事实来自 4.7.2-stable **源码实际下载阅读** + 官方文档 + GitHub Releases API 的一手验证。震动结论是源码（`input.cpp` / `platform/android/`）+ 官方文档（"controller features 仅支持 Windows/macOS/iOS/Linux"）**双重确认**。剩余 MEDIUM：真机时序与震动主观手感——那本来就不能靠研究回答。 |
| **Features** | **MEDIUM** | 8 类相邻产品的实际功能 + 运动学习文献交叉验证。**有一处事实错误已在本 SUMMARY 修正**：把安卓震动描述成"按型号差异极大"是错的，实际是"不存在"。会话形态与反馈设计的结论是跨产品推断，未经本项目用户测试。 |
| **Architecture** | **HIGH** | Godot 语义全部来自官方文档逐字引用（`_process` delta 钳制、`use_accumulated_input` 默认值、`agile_event_flushing` 仅安卓、`Engine.max_fps` 与 vsync 关系、`get_joy_info()` 安卓恒空）。移植契约来自实际 Python 源码。MEDIUM：扳机轴范围（已被 STACK 用源码补强为 HIGH）、`.json` 入 PCK 的版本差异、安卓震动可靠性（被 STACK 推翻）。**有一处对安卓的错误外推已修正**：`AxisLayout` 的"彻底删除"只对桌面成立。 |
| **Pitfalls** | **HIGH / MEDIUM** | 仓库/工具链/API 事实 HIGH（一手源码 + 官方文档）；Xbox 蓝牙 LT/RT 对调、DualSense 特定 OEM 扳机异常属于小样本社区报告，标 MEDIUM 且必须逐设备验证。**有一处与 STACK 冲突已裁决**：`has_joy_vibration()` 在安卓上是恒 false（STACK 源码），不是"可能返回 true"（PITFALLS 泛化表述）。 |

**Overall confidence:** **HIGH** 对"能不能做、按什么形状做"；**MEDIUM** 对"在朋友那台手机上手感对不对"。这两件事的置信度本来就不同，不要合并成一个数字。

### Gaps to Address

以下问题**四份研究都没能解决**，必须在 roadmap 执行期用真机或真人回答。建议在 Phase 5 之前集中做一次 **device spike**，产出一张实测表再冻结判定容差。

1. **`set_use_accumulated_input(false)` 在安卓上是否真的产生亚帧时间戳。**（D1 的未决部分）→ Phase 5 记录 `t_ms` 差值直方图；若 p95 > 20 ms，判定容差整体放宽 ≥ 1 帧，或上 `agile_event_flushing` / 原生 `MotionEvent.getEventTime()`。
2. **目标手柄上右摇杆是否真的落在 `JOY_AXIS_RIGHT_X/Y = 2/3`。** STACK 说典型蓝牙手柄排序后恰好对齐，但"能用但脆"。→ 若错位，逐设备 profile 的轴映射表升级为必选功能（本来就要做，只是从"兜底"变"主路径"）。
3. **安卓上扳机的真实静止值与极性。** STACK 源码说 0..1，PITFALLS 说逐设备变化。→ 保留启动探针，代价 20 行。
4. **60 Hz 抽取是否保住 `release_hold_ms=120` / `global_cooldown_ms=60` 的判定。** → Phase 4 的抽取矩阵直接回答；**在此之前不要动任何阈值**。
5. **实质性的逐样本率依赖常量清单。** `motion_delta = 2.0°` / `abs(mag-last_mag) >= 0.05` / `swept >= 5.0` / `_last_path_t >= 0.008` 在 60 Hz 下含义变了，但**没有清单**。→ Phase 4 开工前先做一次 `detectors.py` 的"采样假设审计"，把每个常量分类并重写率依赖项。
6. **DualSense 在安卓上的按钮映射偏移是否严重到需要"重映射"而不只是"确认"。** → 若严重，Phase 5 的按键确认页升级为重映射页。
7. **手机本体震动的可感知阈值。** 30 / 50 / 80 / 120 ms 哪一档在"手机架在支架上、人在 1 m 外"能被感知。→ Phase 8 真人 A/B。
8. **auto-advance 的结果停留时长。** 1.2 / 1.8 / 2.5 s 三档，太短看不清、太长破坏节奏。→ Phase 6 真人测试。
9. **`left-stick-relative` 在移动端的必要性。** `relative_to_ls=true` 以左摇杆朝向为 0°，但移动端没有"球员朝向"这个语境。→ 建议 v1 两种都保留、默认 LS 相对 + 屏幕上画出左摇杆方向 + 一句"推住左摇杆定朝向"，等真实反馈再定。
10. **230 项检查的映射口径。** 182 项检测器/引擎可直接移植成轨迹夹具；48 项 GUI 冒烟**不应**移植（Python 侧直接调 `Engine._tick()` 私有方法是 bug 不是模式，GDScript 里应通过公开的 `tick()` / `snapshot()` 测）；1 项 250 Hz 时序测试**删除**（在可变帧率主循环上无意义），替换为 `assert(p95_dt_ms < 2 × nominal_dt)`。

---

## Sources

### Primary（HIGH confidence — 一手源码与官方文档）
- **Godot 4.7-stable / 4.7.2-stable 源码**（GitHub tarball，实际下载阅读）— `core/input/input.cpp`、`platform/android/android_input_handler.cpp`、`java_godot_lib_jni.cpp`、`GodotInputHandler.java`、`GodotNativeBridge.kt`、`display_server_android.cpp`、`input_enums.h`、`java/app/config.gradle`。**这是本项目震动结论与轴序结论的最高权威**——它直接证明了安卓从不注册 `JoypadFeatures`、`start_joy_vibration` 只写 HashMap、`fallback_mapping == -1` 时原始轴序号直通。
- **Godot 官方文档 4.7**（Context7 `/websites/godotengine_en/4.7`）— `Input` / `FileAccess` / `JSON` / `Line2D` / `CanvasItem` / `Engine` / `DisplayServer` / `OS` / Node `_process` / ProjectSettings / Android 导出 / Gradle build / Android plugin v2 / JavaClassWrapper / 控制器。
- **docs.godotengine.org/en/4.7/tutorials/inputs/controllers_gamepads_joysticks.html** — "Android 仍用 custom implementation 而非 SDL"、"SDL-based mobile support planned"、死区语义、省电/焦点设置。
- **docs.godotengine.org/en/4.7/tutorials/inputs/controller_features.html** — "controller features 仅支持 Windows/macOS/iOS/Linux"（排除安卓的官方依据）。
- **docs.godotengine.org/en/4.7/about/release_policy.html** — "新 major 才产生 LTS"的原文（推翻"4.x LTS"这个选项）。
- **docs.godotengine.org/en/4.7/tutorials/export/{exporting_for_android, android_gradle_build, exporting_projects, troubleshooting}.html** — JDK 17、SDK 包清单、Editor Settings 两处路径、`.so` 预编译免 C++ 工具链、下划线目录不入包、**`*.json` 非资源文件过滤**（"编辑器能跑、导出报错"的根因）。
- **docs.godotengine.org/en/4.7/tutorials/platform/android/{android_plugin, javaclasswrapper_and_androidruntimeplugin}.html** — v2 插件架构、AAR + `EditorExportPlugin`、`@UsedByGodot`、`AndroidRuntime` + `JavaClassWrapper` 官方示例。
- **仓库源码（一手）** — `desktop/padskills/{geometry,engine,detectors,input_source,config,rumble}.py`、`shared/skills_config.json`、`.planning/codebase/CONCERNS.md`。角度约定、死区公式、扳机合成、引擎仲裁、配置别名、12 个已知 bug 与技术债。
- **Godot issue #106313 / PR #106358** — 16 KB 页对齐在 4.5 通过 NDK r28b 修复。
- **Android Developers — Support 16 KB page sizes；App orientation（Android 16）** — 16 KB 要求；targetSdk 36 在 sw600dp 上忽略方向/可调整大小限制。

### Secondary（MEDIUM confidence — 交叉验证或社区共识）
- **8 类相邻产品的一手页面** — MotionInputs、Ironfist Insights Trainer、Fighting Game Combo Trainer、Button Masher、Frame Dojo、escwasd、keybr（帮助 + 算法仓库）、Yousician、Simply Piano streak、Aim Lab、练习计时器类（Timglas / Dugout Edge / Fretlist）、手柄检测类（OG Gamepad Tester / DriftGuard / Gamepad Tester Pro）、Android 手柄配对与测试站。会话形态、反馈分层、逐步 frame delta、弱项加权、反特性。
- **运动学习文献** — 间隔练习对动作序列学习无显著学习优势（*Scientific Reports*, 2026）；交错/随机练习优于分块练习（含反馈频率 meta 分析）；带宽反馈优于同频反馈；自我控制反馈对迁移有优势；跨天分配优于同日集中（*Human Movement Science*, 2000）。**用途是"拒绝做 Anki 式 SR 排程"，不是"证明弱项加权科学"**——后者是工程启发式，文案上不得宣称"科学算法"。
- **Godot issue #73446** — 安卓手柄震动不可用，2023 年至今未实现。**注意：FEATURES.md 把它与 PR #109645（为安卓引入 SDL 摇杆）混读，得出了"按型号差异"的错误结论；本 SUMMARY 已按 STACK 的源码结论纠正。**
- **Godot issue #39380** — `.json` 是否入 PCK 在版本间有双向报告 → 因此必须设 `include_filter` **且**做导出冒烟测试。
- **Godot issue #85265** — Android 可能连发两次 `NOTIFICATION_APPLICATION_PAUSED` → 处理器必须幂等。
- **Godot forum（2025-05）+ PR #106021** — Xbox 蓝牙 LT/RT 对调报告。
- **Godot forum（2025-10）** — DualSense 在特定三星/诺基亚机型上的扳机/映射异常。
- **gut.readthedocs.io Command-Line** — `gut_cmdln.gd` 参数、`-gexit`、退出码。文档可能滞后于 9.7.1，但命令形式自 GUT 7 未变。
- **GUT 9.7.1 / 9.7.0 release notes；gdUnit4 6.2.3 release notes** — 4.7 适配状态（9.6.x 在 4.7 上会报返回值类型相关错误）。

### Tertiary（LOW confidence — 单源或训练数据，需验证）
- **调试 keystore 自动生成**（Godot 首次导出在 `~/.android/debug.keystore`）— 未在 4.7 文档明确写出。若导出报 keystore 错误，直接用 `keytool` 手生成。
- **`JAVA_HOME` 与 Godot 的 JDK 选择关系** — Godot 用 Editor Settings 的 `Java SDK Path`，但 `keytool`/`apksigner` 子进程可能仍受 `JAVA_HOME` 影响（多 JDK 机器上出现过 "apksigner not found"）。建议宿主机只留一个 JDK 17。
- **Apple Silicon 上的导出路径** — 官方文档未单列；SDK/JDK 架构无关或原生 arm64，导出模板按 ABI 分。
- **`arm64-v8a` vs `armeabi-v7a`** — 建议只勾 `arm64-v8a`（APK 更小，32 位设备已极少），但**朋友的设备未验证**。

---

*Research synthesized: 2026-11-04*
*Sources: `.planning/research/{STACK,FEATURES,ARCHITECTURE,PITFALLS}.md`*
*Ready for roadmap: yes — 但 PROJECT.md 的震动前提必须先按 "Invalidated Assumptions" 一节修正*
