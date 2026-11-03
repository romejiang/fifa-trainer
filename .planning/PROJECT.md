# FIFA 花式动作练习器（桌面 + 安卓）

## What This Is

一个本地运行的花式动作练习工具：接上手柄，实时识别右摇杆轨迹，做对了给出反馈，做错了告诉你是快了、慢了，还是起点 / 终点 / 保持时间不对。

目前只有桌面版（Python + pygame-ce），已验证可在飞智八爪鱼 4 上使用。本项目要在保留桌面版的同时，新增一个**安卓优先的移动版**：手机或平板架在手边，连 Xbox / DualSense 手柄，躺在床上或沙发上用真摇杆练习。

## Core Value

**用真手柄、在任何地方都能练，判定准、反馈看得懂。**

如果一件事只能保住一件，那就是：判定结果必须和桌面版一致，且用户一眼能看出这次错在哪。震动是加分项，视觉反馈是主路径。

## Requirements

### Validated

<!-- 已由现有桌面版代码与 230 项自建检查证明可用。 -->

- ✓ 250 Hz 无阻塞采样主循环，绝对时间轴追帧重对齐 — existing（`desktop/padskills/engine.py`）
- ✓ 三类检测器：弧形（arc）、方向序列（sequence）、点按（taps） — existing（`desktop/padskills/detectors.py`）
- ✓ 5 个动作的识别规则：马赛回旋、踩单车、磕球过人、油炸丸子、绿色搓射 — existing（`shared/skills_config.json`）
- ✓ 失败原因诊断：太快 / 太慢 / 起点不对 / 终点不对 / 保持时间不足 — existing
- ✓ 桌面 GUI：累计成功数、10 个一组进度、最近结果、双摇杆同图可视化 — existing（`desktop/padskills/gui.py`）
- ✓ CLI 模式：后台只报动作名，不打扰游戏 — existing（`desktop/main.py`）
- ✓ 手柄震动反馈 + 多后端回退（SDL / XInput / 其他） — existing（`desktop/padskills/rumble.py`）
- ✓ 数据驱动的动作配置，含解析期校验 — existing（`desktop/padskills/config.py`）
- ✓ 可打包为 Windows `.exe` / macOS `.app` — existing（`desktop/FIFA-Skill-Trainer.spec`）
- ✓ 230 项自建检查（182 检测器/引擎 + 48 GUI 冒烟） — existing（`desktop/tests/`）

### Active

- [ ] 仓库重构为 `desktop/` + `mobile/` + `shared/`，桌面版 230 项检查全部通过
- [ ] `shared/skills_config.json` 作为唯一真源，并有同步到 `mobile/` 的一致性校验
- [ ] Godot 4 安卓项目骨架：主循环、手柄输入、场景结构
- [ ] GDScript 版三类检测器，行为与桌面版逐项对齐
- [ ] 5 个动作 1:1 平移，判定结果与桌面版一致
- [ ] 手柄支持：Xbox 系与 PlayStation（DualSense / DualShock）蓝牙连接
- [ ] 视觉反馈：实时轨迹绘制 + 成功/失败原因展示
- [ ] 触觉反馈：优先 `vibrate_handheld()` 手机震动，可全局关闭；手柄马达不在首版范围
- [ ] 手柄断连检测与自动恢复
- [ ] 可侧载的安卓 APK，朋友能装上就用

### Out of Scope

- 与 FC / FC Mobile 或任何真实游戏联动 — 手机无法合法地向游戏注入手柄输入，且这不是本项目要解决的问题
- iOS / iPadOS 首个版本 — 需要 Apple Developer 账号（$99/年）与 App Store 审核，等安卓验证后再评估
- 扩充动作库 — 首版只平移现有 5 个动作，先证明管线可用
- 账号、云同步、排行榜 — 纯本地工具，无服务端
- 应用商店上架（Google Play / App Store）— 首版走 APK 侧载给朋友
- 桌面版新增功能 — 桌面版只做重构与回归，不叠加新特性

## Context

**现有代码库状态**（详见 `.planning/codebase/`）：

- Python 3.11+，依赖仅 `pygame-ce`，可选 `XInput-Python`（仅 Windows）与 `pyinstaller`（打包）
- 约 3,700 行 Python：`padskills/gui.py`（1308）、`detectors.py`（1046）、`config.py`（790）、`input_source.py`（642）、`engine.py`（508）、`rumble.py`（344）、`main.py`（324）
- 严格单线程、SDL 亲和；无网络、无数据库、无认证
- 无 CI、无 pytest、无 lint / 类型检查；测试是自建 `check()` 脚本，用 `uv run tests/test_*.py` 运行
- 已知 12 个 bug 与技术债记录在 `.planning/codebase/CONCERNS.md`

**为什么有把握移植：**

1. **所有检测器阈值都是毫秒制，不是帧数制。** `min_duration_ms`、`max_duration_ms`、`release_hold_ms`、`hold_ms` 等均可原样保留，采样率从 250 Hz 降到 60–125 Hz 不影响判定参数。
2. **动作库只有 5 个**，三种检测器各覆盖 1–2 个，首版无需做内容取舍。
3. **230 项自建检查等价于一份行为规格书**，可作为 GDScript 重写的验收标准。
4. **`skills_config.json` 是纯数据**，Godot 可直接 `JSON.parse_string` 读取，无需转换。

**为什么选 Godot 4：**

- 外接手柄是引擎级 API；**震动在安卓上不是** —— 引擎的安卓平台层没有 rumble 实现，`start_joy_vibration()` 是静默空操作。安卓唯一通道是 `vibrate_handheld()`（震手机本体）。要真正驱动手柄马达必须写 Android v2 插件，已明确推迟。
- 2D 优先、包体小、免费无授权费；锁定 `4.7.2-stable`（Godot 4 没有 LTS，只有当前 stable 分支的补丁）
- macOS 上可直接导出 Android（及日后的 iOS）
- 相比 Flutter（iOS 手柄插件缺失）和 Unity（工程更重），在「真手柄 + 实时 2D」这个场景下最省事

## Constraints

- **平台**：安卓优先。iOS 延后，且需 Apple Developer 账号与 Xcode 构建。
- **输入**：必须有外接手柄。不做虚拟摇杆 —— 触屏搓招的肌肉记忆无法迁移到真手柄。
- **反馈**：视觉为主。安卓上 Godot **没有**手柄震动实现 —— 不是「不可靠」，是「不存在」。唯一可用通道是 `vibrate_handheld()`，震的是手机本体，必须明确标注且可关闭。**视觉反馈必须自成闭环**，删掉震动不影响任何核心功能。
- **采样率**：移动端约 60–125 Hz，低于桌面 250 Hz。判定阈值按毫秒保留，但需要实测确认时序抖动可接受。默认输入是每帧 flush 一次，同一帧内所有事件共享时间戳；须在启动时调用 `Input.set_use_accumulated_input(false)`，并在真机上量化实际到达间隔分布。
- **设备覆盖**：必须以真机真手柄验证（Xbox + DualSense），模拟器与单元测试不能证明配对、轴映射或触觉可用性。
- **回归红线**：桌面版搬目录后，230 项检查必须全部通过，否则不得继续移动端开发。
- **分发**：APK 侧载给朋友，不追求商店合规（隐私政策、签名托管等）。
- **配置真源**：`shared/skills_config.json` 是唯一真源。Godot 只能读 `res://`，因此必须有同步步骤与一致性检查，禁止出现两份手工维护的副本。

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| 移动端用 Godot 4 + GDScript | 外接手柄是引擎级能力；震动只是视觉反馈的附加项，安卓上仅有手机本体震动；2D 与实时绘制轻量；免费且 Mac 可导出安卓 | — Pending |
| 首版不做手柄马达的原生插件 | 安卓上要驱动手柄马达必须写 Android v2 插件，且 `JavaClassWrapper` 调 `InputDevice.getVibrator()` 可行性未验证；震动不阻塞任何阶段，推迟到验证产品价值之后 | — Pending |
| 安卓优先，iOS 延后 | 安卓侧载零成本零审核；iOS 需 $99/年与审核，先用低成本端验证产品 | — Pending |
| 视觉反馈为主、触觉为辅 | 安卓上 Godot 根本没有手柄震动实现，不能把核心体验押在一个不存在的能力上 | — Pending |
| 首版只平移现有 5 个动作 | 先证明管线可用，避免同时承担「移植」与「设计新检测规则」两类风险 | — Pending |
| 仓库拆成 `desktop/` + `mobile/` + `shared/` | 两端边界清晰，Godot 缓存不污染 Python 项目，共享配置显式化 | — Pending |
| `skills_config.json` 单一真源 + 同步 | 避免重演桌面版已记录的「配置多真源」债务 | — Pending |
| 先搬目录再写移动端 | 目录重构是机械改动但影响面广，先做且用 230 项检查验证，避免边写边改导致返工 | — Pending |
| 不做游戏联动 | iOS/Android 均无法合法向真实游戏注入手柄输入；定位为纯肌肉记忆训练器 | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-11-04 after initialization*
