# Requirements: FIFA 花式动作练习器（移动版）

**Defined:** 2026-11-04
**Core Value:** 用真手柄、在任何地方都能练，判定准、反馈看得懂。

## v1 Requirements

首个可用版本的范围。每条映射到一个路线图阶段。

### 判定核心

- [ ] **JUDGE-01**: 三类检测器（arc / sequence / tap）以纯 GDScript 状态机重实现，不依赖场景树即可运行
- [ ] **JUDGE-02**: 现有 5 个动作全部可识别：马赛回旋、踩单车、磕球过人、油炸丸子、绿色搓射
- [ ] **JUDGE-03**: 重放同一轨迹时，判定序列与 Python 桌面版逐条一致（以现有 230 项检查为验收基线）
- [ ] **JUDGE-04**: 失败原因分类正确：太快 / 太慢 / 起点不对 / 终点不对 / 保持时间不足
- [ ] **JUDGE-05**: 每次判定返回结构化度量 `measured{}`（起止角、扫过角、每步耗时、保持时长），供反馈层直接消费
- [ ] **JUDGE-06**: 用手势锁、失败归属、冷却、修饰键互斥的仲裁语义与桌面版一致，一次动作最多产出一个判定
- [ ] **JUDGE-07**: 用 250 Hz 录制轨迹抽稀到 60 / 90 / 120 Hz 的夹具，证明判定不漂移；若漂移，以证据调整阈值并记录理由

### 输入与设备

- [ ] **INPUT-01**: 支持 Xbox 系与 PlayStation（DualSense / DualShock）手柄经蓝牙连接
- [ ] **INPUT-02**: 启动时探测实际轴序号，不硬编码 `JOY_AXIS_*` 常量
- [ ] **INPUT-03**: 摇杆校准：中点与满量程，单档案，数据结构预留 `profile_id`
- [ ] **INPUT-04**: 提供 Xbox / PlayStation 布局选择与按键确认页；无法自动识别设备时由用户确认，绝不静默猜测
- [ ] **INPUT-05**: 检测器输入来自事件捕获（`InputEventJoypadMotion`），不轮询 `get_joy_axis`，避免丢失帧内反转
- [ ] **INPUT-06**: 手柄断连被检测并自动重连；掉线期间不计入尝试、不产生失败判定

### 会话循环

- [ ] **LOOP-01**: 10 次一组，组内进度点可见
- [ ] **LOOP-02**: 结果停留后自动进入下一次尝试，全程无需触碰屏幕（免触摸循环）
- [ ] **LOOP-03**: 待触发与冷却状态可见，用户知道什么时候可以开始下一次
- [ ] **LOOP-04**: 暂停 / 恢复；恢复时重置检测器并 3 秒倒计时，避免跨暂停误判
- [ ] **LOOP-05**: 冷启动直达上次练习的动作

### 反馈呈现

- [ ] **FEEDBACK-01**: 失败原因一行，采用架子距离可读的大字号
- [ ] **FEEDBACK-02**: 实测 vs 目标区间时序条，让用户看出差了多少而不是只知道失败
- [ ] **FEEDBACK-03**: 实时双摇杆轨迹绘制
- [ ] **FEEDBACK-04**: 成功 / 失败提示音，全局可开关
- [ ] **FEEDBACK-05**: 触觉反馈走 `vibrate_handheld()`，可全局关闭；界面明确标注震的是手机而非手柄
- [ ] **FEEDBACK-06**: 屏幕常亮 + 横屏锁定 + 适配支架观看距离的字号

### 数据留存

- [ ] **DATA-01**: 每动作累计尝试数与成功数
- [ ] **DATA-02**: 每动作最近 N 次结果记录
- [ ] **DATA-03**: 用户数据写入 `user://` 的稀疏覆盖层，绝不尝试修改 `res://` 内配置

### 上手引导

- [ ] **ONBOARD-01**: 手柄配对图文引导，支持按任意键唤醒
- [ ] **ONBOARD-02**: 校准引导（中点 + 满量程），首次使用可完成

### 韧性

- [ ] **RESIL-01**: 切后台 / 回前台不产生误判（前台时间与墙钟时间分离）
- [ ] **RESIL-02**: 配置校验失败显示错误屏并给出可操作信息，而非 `push_error` 或静默降级
- [ ] **RESIL-03**: 核心代码可在无场景树、无手柄的环境下无头运行，由回放源驱动

### 仓库与构建

- [ ] **INFRA-01**: 仓库拆分为 `desktop/` + `mobile/` + `shared/`，桌面版 230 项检查全部通过
- [ ] **INFRA-02**: `shared/skills_config.json` 为唯一真源；同步脚本 + hash 校验；应用启动时校验
- [ ] **INFRA-03**: `mobile/src/core/` 架构 lint：禁止出现 `Input.` / `Time.` / `Node` / `FileAccess` / `print(`
- [ ] **INFRA-04**: 真机冒烟 APK：能安装、能启动、能读到原始轴值
- [ ] **INFRA-05**: 可侧载 APK 分发给朋友；包名 / keystore / versionCode 稳定，v1 → v2 升级不丢数据

## v2 Requirements

延后到后续版本。已记录但不在当前路线图内。

### 反馈加深

- **REVW-01**: 本次轨迹回放（0.5×，失败点高亮）
- **REVW-02**: 示范一次（按需播放参考轨迹，而非常驻显示）
- **REVW-03**: 序列动作逐步拆解

### 统计

- **STAT-01**: 每动作准确率趋势
- **STAT-02**: 弱项高亮与弱项加权练习
- **STAT-03**: 组末 / 会话小结
- **STAT-04**: 干净连击与最佳连击

### 体验

- **UX-01**: 手柄当遥控器（Start 暂停、十字键换动作、Y 回放）
- **UX-02**: 节奏音（仅序列类动作）
- **UX-03**: 会话长度选择（5 / 10 / 20 分钟自动组课）
- **UX-04**: 竖屏与平板排版

### 平台

- **PLAT-01**: iOS / iPadOS 版本
- **PLAT-02**: 手柄马达原生插件（需先验证 `JavaClassWrapper` 调 `InputDevice.getVibrator()` 的可行性）

### 内容与难度

- **CONT-01**: 动作库扩充到 5 个以上
- **DIFF-01**: 难度档（宽 / 标准 / 严），必须把档位写入历史记录以保证可比性

## Out of Scope

明确排除，记录在此以防范围蔓延。

| Feature | Reason |
|---------|--------|
| 与 FC / FC Mobile 或任何真实游戏联动 | iOS 与 Android 均无法合法向真实游戏注入手柄输入；定位为纯肌肉记忆训练器 |
| 虚拟摇杆 / 触屏搓招 | 触屏搓招的肌肉记忆无法迁移到真手柄，与产品目的冲突 |
| 账号 / 云同步 / 排行榜 | 纯本地工具，无服务端；引入后需要隐私与运维成本 |
| 应用商店上架（Google Play / App Store） | 首版走 APK 侧载给朋友，不承担商店合规成本 |
| 常驻参考轨迹 | 会造成 guidance 依赖，撤掉后用户就不会做动作了 |
| 自动收紧阈值 | 会让历史数据立刻不可比，破坏进步感知 |
| 严格每日 streak | 断一天就彻底放弃，与「随时练几分钟」的场景冲突 |
| 旧 Xbox One 无蓝牙型号 | 硬件本身不支持蓝牙连接，无法通过软件解决 |
| DualSense 自适应扳机特效 | 与摇杆轨迹训练目标无关，且 Android 支持不稳定 |
| 手柄电量显示 / 后台常驻 | 非核心，收益低 |
| 社交 / 广告 / 强制教程 | 与工具属性冲突 |

## Traceability

哪些阶段覆盖哪些需求。路线图创建时填入。

| Requirement | Phase | Status |
|-------------|-------|--------|
| JUDGE-01 | Phase 5 | Pending |
| JUDGE-02 | Phase 5 | Pending |
| JUDGE-03 | Phase 5 | Pending |
| JUDGE-04 | Phase 5 | Pending |
| JUDGE-05 | Phase 5 | Pending |
| JUDGE-06 | Phase 5 | Pending |
| JUDGE-07 | Phase 5 | Pending |
| INPUT-01 | Phase 4 | Pending |
| INPUT-02 | Phase 4 | Pending |
| INPUT-03 | Phase 4 | Pending |
| INPUT-04 | Phase 4 | Pending |
| INPUT-05 | Phase 4 | Pending |
| INPUT-06 | Phase 8 | Pending |
| LOOP-01 | Phase 6 | Pending |
| LOOP-02 | Phase 6 | Pending |
| LOOP-03 | Phase 6 | Pending |
| LOOP-04 | Phase 6 | Pending |
| LOOP-05 | Phase 6 | Pending |
| FEEDBACK-01 | Phase 6 | Pending |
| FEEDBACK-02 | Phase 7 | Pending |
| FEEDBACK-03 | Phase 7 | Pending |
| FEEDBACK-04 | Phase 7 | Pending |
| FEEDBACK-05 | Phase 10 | Pending |
| FEEDBACK-06 | Phase 7 | Pending |
| DATA-01 | Phase 8 | Pending |
| DATA-02 | Phase 8 | Pending |
| DATA-03 | Phase 3 | Pending |
| ONBOARD-01 | Phase 4 | Pending |
| ONBOARD-02 | Phase 4 | Pending |
| RESIL-01 | Phase 8 | Pending |
| RESIL-02 | Phase 3 | Pending |
| RESIL-03 | Phase 3 | Pending |
| INFRA-01 | Phase 1 | Pending |
| INFRA-02 | Phase 1 | Pending |
| INFRA-03 | Phase 3 | Pending |
| INFRA-04 | Phase 2 | Pending |
| INFRA-05 | Phase 9 | Pending |

**Coverage:**
- v1 requirements: 37 total
- Mapped to phases: 37
- Unmapped: 0 ✓

**Per-phase counts:**

| Phase | Requirements |
|-------|--------------|
| 1 | INFRA-01, INFRA-02 (2) |
| 2 | INFRA-04 (1) |
| 3 | RESIL-02, RESIL-03, INFRA-03, DATA-03 (4) |
| 4 | INPUT-01, INPUT-02, INPUT-03, INPUT-04, INPUT-05, ONBOARD-01, ONBOARD-02 (7) |
| 5 | JUDGE-01 … JUDGE-07 (7) |
| 6 | LOOP-01 … LOOP-05, FEEDBACK-01 (6) |
| 7 | FEEDBACK-02, FEEDBACK-03, FEEDBACK-04, FEEDBACK-06 (4) |
| 8 | RESIL-01, INPUT-06, DATA-01, DATA-02 (4) |
| 9 | INFRA-05 (1) |
| 10 | FEEDBACK-05 (1) |

---
*Requirements defined: 2026-11-04*
*Last updated: 2026-11-04 after roadmap creation (10 phases)*
