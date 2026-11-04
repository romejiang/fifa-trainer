# 移动端（Godot，安卓优先）

这里是 FIFA 花式动作练习器的移动版。目标形态：手机或平板架在手边，连 Xbox / DualSense 手柄，用真摇杆练花式动作。

**`project.godot` 已由锁定工具链（Godot 4.7.2-stable）创建。** 不要用其它版本的 Godot 打开这个工程：新版本会把工程格式静默改写一遍，改写之后的差异既不属于任何人的改动，也没人知道它为什么出现。要用就用 `mobile/BUILD.md` 第一节钉死的那一份。

## 目录现状

```text
mobile/
├── project.godot              # Godot 工程入口；版本由 BUILD.md 钉死，不要用别的版本打开
├── export_presets.cfg         # Android 导出预设（包名 / versionCode / 架构 / 纹理格式）
├── assets/config/             # 配置只读副本 + .sha256，由 tools/sync_config.py 生成
├── assets/fonts/              # CJK 子集 + 符号 fallback 子集 + OFL 许可 + 字形清单
├── src/core/                  # 零引擎依赖的纯 GDScript 层；边界由 tools/lint_core_purity.py 强制
├── src/smoke/                 # 验收面板；一次性证明配置进包、中文不豆腐、轴在动
├── tests/                     # 无头套件与夹具（不进 APK）
├── docs/CORE.md               # 「零引擎依赖」的可执行定义与 lint 规则表
├── tools/                     # 闸门与反例：doctor.sh / gate-a.sh / gate-b.sh / test-core.sh
└── build/                     # 导出产物（gitignored）；不是源码，不要手改
```

`assets/fonts/*.import` 与 `**/*.gd.uid` 是 Godot 的**导入边车**，属于提交物：`.import` 钉住导入参数与目标路径，`.uid` 钉住脚本 UID。它们不是缓存，**不要**加进 `.gitignore` —— 忽略它们的代价是每台机器重新抽签导入参数与资源 UID，产物随之漂移。

## 四条入口命令

```bash
bash mobile/tools/test-core.sh  # 纯核心闸门：lint + 黄金 + 无头测试（无需模板、无需设备）
bash mobile/tools/gate-a.sh     # 闸门 A：配置真源 + 语法 + PCK 往返 + 字形覆盖（无需模板、无需设备）
bash mobile/tools/gate-b.sh     # 闸门 B：闸门 A + release 导出 + 验签 / 对齐 / 包内容 / badging
```

前两条都是「不需要设备」的自动闸门，区别在验证对象：`test-core.sh` 验的是
`src/core/` 这个零引擎依赖层（含架构边界 lint），`gate-a.sh` 验的是整个工程与打包往返。

第四条是**人的动作**，脚本只能做前半段：

```bash
bash mobile/tools/device-smoke.sh   # 装机 + 启动 + 进程存活 + 截图；视觉结论归人
```

然后按 [`ACCEPTANCE.md`](ACCEPTANCE.md) 在真机上逐项打勾 —— 两台不同 OEM 手机 + 一只真手柄，缺一个都不许声称通过。构建环境的安装、版本与排错见 [`BUILD.md`](BUILD.md)。

## 配置副本不可手改

`mobile/assets/config/skills_config.json` 及其 `.sha256` 是 `tools/sync_config.py` 生成的只读副本，供 Godot 从 `res://assets/config/` 读取。

- 唯一可手写的真源：`shared/skills_config.json`
- 同步：`python3 tools/sync_config.py`
- 校验：`python3 tools/sync_config.py --check`

闸门 A 的第一步就是这条校验：副本被手改时 PCK 闸门照样能解析出 5 条动作并报绿，所以顺序不能换。
