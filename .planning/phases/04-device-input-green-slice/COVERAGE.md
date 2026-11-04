---
phase: 04-device-input-green-slice
checked: 2026-11-05
verdict: no-external-api
---

# Phase 4 — API Coverage

No external API integration: 本阶段只读取安卓系统的游戏手柄 HID 事件与本地 JSON 文件，无网络、无 SDK、无服务端。

## 判据

| 问题 | 答案 |
|------|------|
| 是否有 HTTP / RPC / GraphQL 调用？ | 无 |
| 是否有第三方 SDK 或云服务？ | 无。手柄由 Android 系统 HID 栈处理，Godot 的 `Input` 单例只读系统已枚举的设备 |
| 是否有认证 / 令牌 / 账号？ | 无。纯本地单用户工具 |
| 是否有需要版本矩阵跟踪的外部接口？ | 无。唯一的版本锚是 Godot 4.7.2-stable（Phase 2 已锁死） |
| 外部输入面有哪些？ | ① 蓝牙手柄上报的事件与轴值；② `user://profiles/controllers.json`；③ `res://assets/config/skills_config.json`（只读） |

## 本阶段的输入面与对应处理

| 输入面 | 校验 / 缓解 | 落点 |
|--------|-------------|------|
| 手柄事件（轴向、按钮、device id） | device 过滤、轴值 `is_finite()` + `clampf(-1,1)`、事件与轮询双通道幂等对账 | `mobile/src/input/pad_state_buffer.gd`（04-04） |
| `user://profiles/controllers.json` | 先取长度再分配（1 MiB 上限）、`user://` 路径守卫、任一条目非法即整份丢弃 | `mobile/src/app/profile_store.gd`（04-04）、`DeviceProfile.from_dict`（04-03） |
| `res://assets/config/skills_config.json` | Phase 3 的结构化校验；本阶段只读、不改 | `ConfigStore` / `ConfigValidator`（既有） |

不虚构能力矩阵：本阶段没有任何外部 API 的 endpoint / method / auth / pagination 面可列。
