# FIFA / EA FC 花式动作练习器

连上手柄练花式动作：做对了手柄震一下；没做对也会当场告诉你**是快了、慢了，还是起点 / 终点 / 保持时间不对**。

- **桌面版已可用**：Python + pygame-ce，250Hz 实时识别右摇杆轨迹
- **移动版建设中**：Godot，安卓优先；Phase 2 才创建 Godot 工程
- **一份配置**：`shared/skills_config.json` 是唯一可手写的真源，其余副本由脚本生成

本文件只是仓库地图。桌面版的安装、操作、打包与排错，请看 [`desktop/README.md`](desktop/README.md)。

---

## 一、这是什么

用真手柄练 FIFA / EA FC 花式动作的本地工具。桌面版（Windows / macOS）已经能用；移动版（Godot，安卓优先）正在建设，目标是手机或平板架在手边、连 Xbox / DualSense 手柄，躺着或坐着都能练。

两版共用同一份动作规则，判定结果必须一致。

## 二、目录地图

- `desktop/` —— 桌面版全部代码、测试、构建脚本与使用手册（Python + pygame-ce）
- `mobile/` —— 移动版（Godot，安卓优先）；Phase 2 起才创建 Godot 工程，当前只有配置副本与说明
- `shared/` —— 唯一手写的动作配置 `skills_config.json` 与 230 项检查基线 `expected_checks.txt`
- `tools/` —— 仓库级工具：配置同步、桌面回归闸门、检查项采集

`.planning/` 放项目规划与代码地图，不参与运行时。

## 三、跑桌面版

桌面版是一个独立的 uv 项目，所有命令都在 `desktop/` 里执行：

```bash
cd desktop
uv sync          # 首次运行会自动下载 Python 与 pygame-ce
uv run app.py    # 打开练习窗口
```

命令行模式示例：

```bash
cd desktop && uv run main.py --list
```

不想 `cd` 也可以写成 `uv --directory desktop run app.py`。**不要**用 `--project` 指向 `desktop/` 再传相对测试路径（如 `tests/test_detectors.py`）—— 子进程的 cwd 仍是仓库根，会 `Failed to spawn`。

## 四、跑回归检查

```bash
bash tools/check_desktop.sh
```

一条命令同时做三件事：

1. 校验 `desktop/` 与 `mobile/assets/config/` 下的配置副本与 `shared/` 真源逐字节一致、`.sha256` 对得上；
2. 确认 230 项检查的基线 `shared/expected_checks.txt` 没有被重新生成；
3. 跑完桌面的 182 + 48 = 230 项检查，并与基线逐项比对名称。

任何一步不符都会非零退出并指出具体文件。

想在干净副本上复现整条链路（含配置反例）可运行 `bash tools/verify_clean_clone.sh`：它会 clone 已提交状态、重放上面这条闸门，再断言跑完工作区零漂移；加 `--tamper` 会额外验证手改副本必被抓住。

## 五、改配置

- **唯一可手写的真源**：`shared/skills_config.json`
- **生成副本**：`desktop/skills_config.json` 与 `mobile/assets/config/skills_config.json`（各带 `.sha256`）—— 不要手改，同步会覆盖，闸门也会报错
- 改完真源后同步：`python3 tools/sync_config.py`
- 只校验不写盘：`python3 tools/sync_config.py --check`

## 六、进一步阅读

- [`desktop/README.md`](desktop/README.md) —— 桌面版完整手册（安装、操作、打包、排障）。其中「九、项目结构」一节描述的是搬迁前的扁平布局，以本文件的目录地图为准。
- [`mobile/README.md`](mobile/README.md) —— 移动端目录说明与 Phase 2 的边界。
- [`.planning/codebase/`](.planning/codebase/) —— 架构、技术栈、测试与代码约定的代码地图。
