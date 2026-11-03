# 移动端（Godot，安卓优先）

这里是 FIFA 花式动作练习器的移动版。目标形态：手机或平板架在手边，连 Xbox / DualSense 手柄，用真摇杆练花式动作。

**Phase 1 只有配置副本，没有 Godot 工程。** `project.godot` 由 Phase 2 创建 —— 若先用未锁定版本的 Godot 生成，Phase 2 用正确版本打开时会被静默重写，所以创建权交给锁定工具链的那一阶段。

## 目录现状

```text
mobile/
└── assets/config/
    ├── skills_config.json
    └── skills_config.json.sha256
```

## 配置副本不可手改

`mobile/assets/config/skills_config.json` 及其 `.sha256` 是 `tools/sync_config.py` 生成的只读副本，未来供 Godot 从 `res://assets/config/` 读取。

- 唯一可手写的真源：`shared/skills_config.json`
- 同步：`python3 tools/sync_config.py`
- 校验：`python3 tools/sync_config.py --check`
