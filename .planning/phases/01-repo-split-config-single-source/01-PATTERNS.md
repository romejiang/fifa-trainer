# Phase 1: 仓库拆分 + 配置单一真源 + 桌面回归闸门 - Pattern Map

**Mapped:** 2026-11-04
**Files analyzed:** 21 entries（覆盖约 60 条路径：12 条新建、4 条改写、8 条纯移动、5 条移动+改内容）
**Analogs found:** 18 / 21（3 条无同角色先例，见「No Analog Found」）

> 所有被引用的 analog 均已用 `git ls-files --error-unmatch <path>` 逐项确认是 **git 跟踪的源文件**（不是 `.venv/`、`dist/` 或任何镜像副本）。

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `tools/collect_checks.py` | tool (CLI) | batch / transform（执行测试并提取名称） | `main.py`（argparse + `main(argv)->int`） | role-match |
| `tools/sync_config.py` | tool (CLI) | file-I/O + hash（单源 → 双副本） | `main.py` + `padskills/config.py`（路径推导 / 写盘 / `SystemExit` 报错） | role-match |
| `tools/test_sync_config.py` | test | batch（临时目录构造场景） | `tests/test_detectors.py`（自建 `check()` harness） | exact（同角色同 harness） |
| `tools/check_desktop.sh` | shell gate | batch / process orchestration | `build/build_macos.sh` | role-match |
| `.github/workflows/desktop-checks.yml` | CI config | event-driven（push/PR） | **无** | none |
| `shared/expected_checks.txt` | data（baseline） | transform（排序后的名称集合） | **无** | none |
| `shared/skills_config.json` | data（唯一真源） | config read（只读） | 现有根 `skills_config.json`（原地迁移，内容不变） | exact |
| `desktop/skills_config.json` + `.sha256` | data（生成副本） | file-I/O | 现有根 `skills_config.json`（作为被复制的内容） | partial |
| `mobile/assets/config/skills_config.json` + `.sha256` | data（生成副本） | file-I/O | 同上 | partial |
| `README.md`（根，改写为仓库地图） | doc | — | 现有 `README.md` 的章节风格 + `padskills/__init__.py` 的模块地图 | role-match |
| `desktop/README.md`（原手册整体迁移） | doc | — | 现有 `README.md`（一字不改） | exact |
| `mobile/README.md` | doc | — | `padskills/__init__.py`（简短「这里放什么」说明） | partial |
| `.gitignore`（根，重写） | config | — | 现有 `.gitignore`（分组注释 + `!` 白名单） | exact |
| `.gitattributes`（根，追加 `*.sha256` / `*.txt`） | config | — | 现有 `.gitattributes` | exact |
| `desktop/pyproject.toml`（移动 + `[[tool.uv.index]]`） | config | — | 现有 `pyproject.toml` | exact |
| `desktop/uv.lock`（纯移动） | config | — | 现有 `uv.lock`（零改动，**手不要碰**） | exact |
| `desktop/FIFA-Skill-Trainer.spec`（纯移动） | config | — | 现有 `FIFA-Skill-Trainer.spec`（零改动） | exact |
| `desktop/build/build_macos.sh`、`build_windows.ps1`（纯移动） | build script | batch | 自身（已按脚本位置解析根目录） | exact |
| `desktop/padskills/config.py`（改 `__all__` + 新增 `shared_config_path()`） | config module | config read（path derive） | 自身 `app_dir()` / `default_config_path()` | exact |
| `desktop/main.py`（改 `-c` 默认值 + `--write-config` 路由） | CLI entry | request-response（分支派发） | 自身（`main.py:212-213`、`:236-239`） | exact |
| `desktop/app.py`、`desktop/padskills/**`、`desktop/tests/**`（纯 `git mv`） | 全部 | — | 自身（**内容零改动**） | exact |

---

## Pattern Assignments

### `tools/collect_checks.py` (tool, batch/transform)

**Analog:** `main.py`

**模块头 + 中文 docstring + `from __future__ import annotations`**（`main.py:1-16`、`padskills/config.py:1-7`）——本项目 11/11 个模块都是这个开头，新增工具脚本必须一致：

```python
#!/usr/bin/env python3
"""FIFA / EA FC 花式动作搓招实时监测与震动反馈工具。
...
"""

from __future__ import annotations

import os
import sys
```

**CLI 形状 + 退出码约定**（`main.py:198-234`）：`prog` 显式命名、`description` 中文、`formatter_class=argparse.RawDescriptionHelpFormatter`（本项目帮助文本用 `epilog` 写示例）、`parse_args(argv)` 收 `argv` 形参以便测试注入。

```python
def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        prog="main.py",
        description="FIFA / EA FC 花式动作搓招实时监测与震动反馈",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "示例:\n"
            "  uv run main.py --gui              打开练习窗口\n"
            ...
        ),
    )
    parser.add_argument("--version", action="version", version=f"%(prog)s {__version__}")
    args = parser.parse_args(argv)
```

**入口守卫**（`main.py:323-324`，`tests/test_detectors.py:1479-1480` 同样写法）：

```python
if __name__ == "__main__":
    raise SystemExit(main())
```

**用 `argparse` 的强制参数而不是位置参数猜测**——`--out` 必须 `required=True`，与 RESEARCH §Code Examples 一致。

> ⚠️ 风格冲突提醒：RESEARCH 的骨架用了 PEP 585 的 `list[str]`，但本项目 CONVENTIONS 明确要求 `typing.List` / `Dict` / `Optional`（`main.py:41` 写的是 `Optional[List[str]]`）。**以代码库为准**，新脚本一律 `from typing import List, Optional`。

---

### `tools/sync_config.py` (tool, file-I/O + hash)

**Analog:** `padskills/config.py`（路径与写盘）+ `main.py`（CLI 骨架）

**路径推导：开发态以 `__file__` 为锚，不读 cwd**（`padskills/config.py:39-43`）：

```python
def app_dir() -> Path:
    """开发态 = 项目根目录；打包态 = 可执行文件所在目录。"""
    if is_frozen():
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parent.parent
```

`tools/` 脚本应等价地写成 `Path(__file__).resolve().parent.parent`，而不是 `Path("shared/...")`（后者在 `cd desktop` 后就会指错）。

**写盘：显式 UTF-8 + 结尾换行 + 返回 Path**（`padskills/config.py:785-790`）—— `.sha256` 与副本都应沿用这一形态，保证字节稳定（hash 才能稳定）：

```python
def dump_default_config(path: Path) -> Path:
    """把内置默认配置写到磁盘（skills_config.json 就是这么生成的）。"""
    path = Path(path)
    text = json.dumps(DEFAULT_CONFIG, ensure_ascii=False, indent=2)
    path.write_text(text + "\n", encoding="utf-8")
    return path
```

**用户可见错误：中文 + 指向具体文件 + `SystemExit`**（`padskills/config.py:765-782`）。CLI 工具的 `--check` 失败请照此形态打印 `✗ <相对路径> …`，然后 `return 1`（而不是抛异常），让 `check_desktop.sh` 能拿到退出码：

```python
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        raise SystemExit(f"读取配置文件失败: {path}\n  {exc}") from None

    try:
        data = json.loads(text)
    except json.JSONDecodeError as exc:
        raise SystemExit(
            f"配置文件 JSON 语法错误: {path}\n"
            f"  第 {exc.lineno} 行 第 {exc.colno} 列: {exc.msg}\n"
            f"  提示：JSON 不支持 // 注释，也不允许最后一个元素后面多写逗号。"
        ) from None

    try:
        return parse_config(data, path)
    except ValueError as exc:
        raise SystemExit(f"配置文件内容有误: {path}\n  {exc}") from None
```

**「发现问题继续报完再退出」的分支形态**——`cmd_list()` 一次列全部设备后统一判定（`main.py:86-101`）；`--check` 应遍历所有副本收集全部差异，再一次性 `return 1`，而不是遇到第一个错就 `raise`：

```python
def cmd_list() -> int:
    banner("手柄设备列表")
    devices = list_devices()
    if not devices:
        print("  没有检测到任何手柄。")
        print("  · 确认手柄已开机并连接（USB 线或接收器）")
        print_controller_hints()
        return 1
    for d in devices:
        ...
    return 0
```

**中文步骤标记 `▸` / 结论标记 `✓` `✗`**——本项目 CLI 输出的既有词汇（`main.py:65` `step()`、`test_detectors.py:36-39`），新工具沿用，不要另造符号。

---

### `tools/test_sync_config.py` (test, batch)

**Analog:** `tests/test_detectors.py`（harness）、`tests/test_gui_smoke.py`（临时目录）

**harness 必须逐字照抄**（`tests/test_detectors.py:28-39` / `test_gui_smoke.py:34-45`，两份完全一致）。**不要引入 pytest**（RESEARCH §"无 pytest"、CONTEXT code_context）：

```python
PASS = 0
FAIL = 0


def check(label: str, ok: bool, extra: str = "") -> None:
    global PASS, FAIL
    if ok:
        PASS += 1
        print(f"  \033[32m✓\033[0m {label}" + (f"  ({extra})" if extra else ""))
    else:
        FAIL += 1
        print(f"  \033[31m✗\033[0m {label}" + (f"  ({extra})" if extra else ""))
```

**`main()` 结构**（`tests/test_detectors.py:1449-1476`）：横幅 → 顺序调用各 `test_*()` → 汇总 → `return 1 if FAIL else 0`。

```python
def main() -> int:
    print("═" * 62)
    print("  FIFA 花式动作识别 —— 算法自测")
    print("═" * 62)

    cfg = load_config(Path(__file__).resolve().parent.parent / "skills_config.json")
    test_geometry()
    ...
    print("\n" + "═" * 62)
    print(f"  通过 {PASS} 项，失败 {FAIL} 项")
    print("═" * 62)
    return 1 if FAIL else 0
```

**临时目录 + 自注入 sys.path**（`tests/test_detectors.py:16`、`test_gui_smoke.py:23,442-444`）：新测试放 `tools/`，不在 `padskills` 包内，必须自己把仓库根塞进 `sys.path` 才能 `import` 被测脚本，或用 `importlib.util.spec_from_file_location` 加载（RESEARCH §Pattern 2 的做法）：

```python
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
...
tmp = Path(tempfile.mkdtemp(prefix="fifa-gui-"))
_cfg_path = dump_default_config(tmp / "skills_config.json")
_cfg = load_config(_cfg_path)
```

> 建议 `tools/sync_config.py` 暴露 `--root` 参数，让本测试能在 `tempfile.mkdtemp()` 里构造完整场景（RESEARCH §Code Examples 注释明确要求补这一项），且 `--root` resolve 后必须仍在允许范围内（Security Domain §"路径穿越"）。

---

### `tools/check_desktop.sh` (shell gate, batch)

**Analog:** `build/build_macos.sh` —— 全仓库唯一的 shell 脚本，也是唯一需要照抄的 shell 形态。

**shebang + 中文用途注释 + `set -euo pipefail`**（`build/build_macos.sh:1-9`）：

```bash
#!/usr/bin/env bash
# 在 macOS 上打包成可双击的 .app。
#
#   bash build/build_macos.sh
#
# 产物：dist/FIFA Skill Trainer.app
# PyInstaller 不能交叉编译：Windows 的 exe 必须在 Windows 上打包。

set -euo pipefail
```

**根目录解析：以 `BASH_SOURCE` 为锚，不依赖调用者的 cwd**（`build/build_macos.sh:11-12`）——闸门脚本会被本地（任意 cwd）与 CI（仓库根）两处调用，这是唯一正确写法：

```bash
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
```

**步骤输出用 `▸`，失败信息进 stderr 并 `exit 1`**（`build/build_macos.sh:14-31`）：

```bash
echo "▸ 安装打包依赖…"
uv sync --extra build

echo "▸ 开始打包…"
uv run pyinstaller \
    --noconfirm --clean \
    ...

app="dist/FIFA Skill Trainer.app"
if [[ ! -d "$app" ]]; then
    echo "没有找到产物：$app" >&2
    exit 1
fi
```

闸门脚本另外需要 RESEARCH §Code Examples 里已验证的三件套：`mktemp -d` + `trap 'rm -rf "$tmp"' EXIT`、`export SDL_VIDEODRIVER=dummy / SDL_AUDIODRIVER=dummy / PYGAME_HIDE_SUPPORT_PROMPT=1 / PYTHONIOENCODING=utf-8`、以及 `LC_ALL=C sort`（**禁止裸 `sort`**，Pitfall 6）。

---

### `.github/workflows/desktop-checks.yml` (CI, event-driven)

**Analog:** **无。** 仓库当前零 YAML、零 `.github/`（`git ls-files | grep -Ei 'ya?ml|github|ci'` 返回空）。

**唯一可复用的既有约定**是"一条命令 + 中文步骤名 + 失败即红"（`build/build_macos.sh` 的 `echo "▸ …"` 形态）。内容直接采用 RESEARCH §Code Examples 的 workflow，但必须遵守研究里两条硬约束：

- action 按 **commit SHA** 固定并附 `# vX.Y.Z` 注释（`actions/checkout@3d3c42e5…  # v7.0.1`、`astral-sh/setup-uv@68559e99…  # v10.3.3`）
- **只用 `uv sync --locked` / `--frozen`**，绝不裸 `uv sync`（Pitfall 1）

---

### `shared/expected_checks.txt` (baseline data)

**Analog:** **无**（仓库里没有任何基线/快照数据文件）。

格式与生成方式见 RESEARCH §Pattern 2 与 §Code Examples：`<测试文件名>\t<label>`，按 `sorted()`（UTF-8 码点序）落盘，230 行。

> 生成时机是**流程约束**而非代码约束：必须在 `git mv` 之前用 `tools/collect_checks.py` 从现存 `tests/` 生成并单独提交（D-08）。本文件无 analog 不是缺陷——它的价值恰恰在于它是全新、不可推导的。

---

### `shared/skills_config.json` (唯一真源)

**Analog:** 现有根 `skills_config.json`（`git mv skills_config.json shared/skills_config.json`，**内容零改动**）。

现有文件是 `DEFAULT_CONFIG` 的一次导出（`padskills/config.py:250-463`），但**不完全相同**（缺 `input.invert`、`_readme` 少 4 行）。RESEARCH Open Question 2 的决定是：**不要趁机对齐**，原样搬迁。

---

### `desktop/skills_config.json` + `.sha256`、`mobile/assets/config/skills_config.json` + `.sha256` (生成副本)

**Analog:** 现有 `skills_config.json`（作为被复制的内容源）；生成行为由 `tools/sync_config.py` 定义（见上）。

两条不可违反的约束（都来自 RESEARCH 实测）：

1. **必须提交进 git**。`load_config()` 在文件缺失时静默回退（`padskills/config.py:762-763`）：
   ```python
   if not path.exists():
       return parse_config(json.loads(json.dumps(DEFAULT_CONFIG)), None)
   ```
   不提交 = 干净 clone 上 182 项照样全绿，但测的是 `DEFAULT_CONFIG`（Pitfall 4）。
2. **绝不能被 `.gitignore` 命中**。写 `.gitignore` 后必须 `git check-ignore -v desktop/skills_config.json` 返回空。

`.sha256` 采用 `sha256sum` 兼容格式 `<hex>  <basename>`（RESEARCH A4），脚本内部用 `hashlib.sha256`，**不要**调 `shasum`（Windows 没有）。

---

### `README.md`（根，改写为仓库地图）

**Analog:** 现有 `README.md`（章节编号风格）+ `padskills/__init__.py:1-10`（模块地图）

现有 README 的组织方式：一级标题 + 一句价值描述 + 要点 bullet + `---` + `## 一、…` 中文数字章节（`README.md:1-15`）。新根 README 沿用这个"标题 → 一句话 → bullet → 分隔线 → 中文编号章节"的骨架，但章节只保留：三棵子树在哪、共享配置在哪、怎么跑桌面测试、指向 `desktop/README.md`。

模块地图写法直接抄 `padskills/__init__.py`——对齐的 `名称 —— 职责` 列表，这是仓库里已有的"目录说明"范式：

```python
"""FIFA / EA FC 花式动作搓招实时监测与震动反馈引擎。

模块划分：
    geometry      —— 角度 / 向量工具
    config        —— skills_config.json 的解析与默认配置
    input_source  —— 手柄状态读取（SDL 映射表驱动的协议无关布局）
    rumble        —— 多后端震动引擎（非阻塞）
    detectors     —— arc / sequence 两类动作识别器
    engine        —— 250Hz 采样主循环
"""
```

**命令写法必须用 `cd desktop` 或 `uv --directory desktop`**，禁止 `uv run --project desktop tests/…`（实测 `Failed to spawn`，Pitfall 3）。这是 README 里最容易写错的一句话。

---

### `desktop/README.md`（原手册整体迁移）

**Analog:** 现有 `README.md`，**776 行一字不改**（`wc -l` 实测 776；`## 一、安装` … `## 十一、故障排查` 共 11 个章节）。

> 唯一需要人工判断的是：第 602 行 `## 九、项目结构` 会描述搬迁前的布局。CONTEXT D-03 明确"内容不改"，因此**保留原样**；如有读者误导风险，只能在根 README 里说明"`desktop/README.md` 中「项目结构」一节描述的是搬迁前的扁平布局"。不要改子目录文档。

---

### `.gitignore`（根，重写）

**Analog:** 现有 `.gitignore`（全文 23 行）——分组注释 + `!` 白名单的结构逐字保留，只把路径加上 `desktop/` / `mobile/` 前缀。

现有关键三行（`.gitignore:9-13`），搬迁后**等价改写为** `desktop/build/*` + 两条 `!desktop/build/…`：

```gitignore
# PyInstaller / local build artifacts
dist/
build/*
!build/build_windows.ps1
!build/build_macos.sh
```

**必须写成 `desktop/build/*` 而不是 `desktop/build/`** —— 目录整体排除后 `!` 无法再包含内部文件（Pitfall 7）。

RESEARCH 已用 `git check-ignore` 验证过的目标矩阵，写成断言更稳：

| 路径 | 期望 |
|------|------|
| `desktop/build/build_windows.ps1` | tracked |
| `desktop/build/build_macos.sh` | tracked |
| `desktop/build/thing.txt` | IGNORED |
| `desktop/dist/x` | IGNORED |
| `desktop/.venv/py` | IGNORED |
| `mobile/.godot/y` | IGNORED |
| `mobile/export/a.apk` | IGNORED |
| `shared/skills_config.json` | tracked |
| `desktop/skills_config.json` | tracked **（关键：不能忽略）** |

---

### `.gitattributes`（根，追加规则）

**Analog:** 现有 `.gitattributes`（全文 9 行）——每条 `glob text eol=…`，无注释，保持这一形态逐行追加：

```gitattributes
* text=auto
*.sh text eol=lf
*.py text eol=lf
*.json text eol=lf
*.md text eol=lf
*.toml text eol=lf
*.lock text eol=lf
*.ps1 text eol=crlf
*.spec text eol=lf
```

新增两行（RESEARCH §Target Repository Structure 提到"追加 `*.sha256` / `*.txt` 规则"）：`*.sha256 text eol=lf`、`*.txt text eol=lf`。**不要**加 `*.yml`/`*.yaml` —— 会让 CI 文件在 Windows 检出时变成 CRLF，虽然无害但增加 diff 噪音；若加，必须是 `eol=lf`。

---

### `desktop/pyproject.toml`（移动 + 固定索引）

**Analog:** 现有 `pyproject.toml`（全文 19 行），`git mv` 后**只在末尾追加**：

```toml
[project]
name = "fifa-skill-rumble"
version = "1.0.0"
description = "FIFA / EA FC 花式动作搓招实时监测与手柄震动反馈（飞智八爪鱼 4 实测通过）"
requires-python = ">=3.11"
dependencies = [
    "pygame-ce>=2.5.8",
]

[project.optional-dependencies]
xinput = [
    "XInput-Python>=0.4.0; sys_platform == 'win32'",
]
build = [
    "pyinstaller>=6.0",
]
```

追加（Pitfall 1 的唯一正解）：

```toml
[[tool.uv.index]]
url = "https://pypi.org/simple"
default = true
```

> ⚠️ 追加后 `uv.lock` 的**字节内容不应变化**（实测 `uv lock --check` 退出 0）。如果 `uv sync` 后 `git diff uv.lock` 非空，说明本机镜像又把 lockfile 改写了 —— 回滚 lockfile，不要提交被改写的版本。

---

### `desktop/uv.lock`（纯移动，零改动）

**Analog:** 现有 `uv.lock`。**用 `git mv`，不要任何其他操作触碰它**。`uv.lock` 里 10 处 `pypi.org` 是提交态的真相；任何 `uv sync` 不带 `--locked` 都可能把它改写成 aliyun（Pitfall 1）。

---

### `desktop/FIFA-Skill-Trainer.spec`（纯移动，零改动）

**Analog:** 现有 `FIFA-Skill-Trainer.spec`。**不要改 `Analysis(['app.py'])`**（`FIFA-Skill-Trainer.spec:4-5`）：

```python
a = Analysis(
    ['app.py'],
```

实测（PyInstaller 6.22.3）spec 内的相对路径按 **SPECPATH（spec 所在目录）** 解析，与 cwd 无关（Pitfall 8）。改成 `desktop/app.py` 反而会在 `cd desktop && pyinstaller FIFA-Skill-Trainer.spec` 时失败。

---

### `desktop/build/build_macos.sh`、`desktop/build/build_windows.ps1`（纯移动，零改动）

**Analog:** 自身。两个脚本**已经**做了"以脚本所在目录为根"的解析，所以搬进 `desktop/build/` 后自动指向 `desktop/`，无需改一个字符：

```bash
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
```
（`build/build_macos.sh:11-12`）

```powershell
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
```
（`build/build_windows.ps1:8-10`）

> 只改脚本顶部的用法注释（`bash build/build_macos.sh` → `bash desktop/build/build_macos.sh`）算"内容改动"，按 Pattern 1 必须放到第 3 个提交，**不能**混进纯移动提交。

---

### `desktop/padskills/config.py`（移动 + 新增 `shared_config_path()`）

**Analog:** 自身。**不动 `default_config_path()`**（`padskills/config.py:60-64`）——它是冻结态语义的锚点：

```python
def default_config_path() -> Path:
    """默认配置文件路径。开发态保持在项目根目录，保持现有习惯。"""
    if is_frozen():
        return user_config_dir() / DEFAULT_CONFIG_FILENAME
    return app_dir() / DEFAULT_CONFIG_FILENAME
```

按 `app_dir()` / `user_config_dir()` 的形态新增一个同级函数（中文 docstring + `-> Path` + 一行说明"为什么"）：

```python
def shared_config_path() -> Path:
    """开发态唯一手写配置：<repo>/shared/skills_config.json。"""
    return app_dir().parent / "shared" / DEFAULT_CONFIG_FILENAME
```

并把它加进 `__all__`（`padskills/config.py:18-24`，按现有分组顺序，路径类函数聚在一起）：

```python
__all__ = [
    "Pulse", "Step", "Skill", "InputConfig", "RumbleConfig", "AppConfig",
    "DEFAULT_CONFIG", "load_config", "dump_default_config",
    "resolve_direction", "direction_name", "parse_step", "DEFAULT_CONFIG_FILENAME",
    "APP_NAME", "is_frozen", "app_dir", "user_config_dir",
    "default_config_path", "ensure_user_config",
]
```

---

### `desktop/main.py`（移动 + `--write-config` 路由）

**Analog:** 自身。当前两处必须改的代码：

```python
    parser.add_argument("-c", "--config", default=str(default_config_path()),
                        help="配置文件路径（默认在项目根目录 / 用户配置目录）")
```
（`main.py:212-213`）

```python
    if args.write_config:
        path = dump_default_config(Path(args.config))
        print(f"已生成默认配置: {path.resolve()}")
        return 0
```
（`main.py:236-239`）

改法（RESEARCH §Code Examples，D-05）：`-c` 默认值改 `None`，在 `parse_args` 之后统一派生 `config_path`；`--write-config` 按「显式 `-c` > 冻结态用户目录 > 开发态 `shared/`」三级路由，并在开发态多打一行中文提示。其余所有 `Path(args.config)` 分支（`:250`、`:252`、`:246`）统一换成 `config_path`，**确保未传 `-c` 时读取路径仍是 `desktop/skills_config.json`**（Pitfall 9 的唯一失败模式）。

---

### `desktop/app.py`、`desktop/padskills/**`、`desktop/tests/**`（纯 `git mv`）

**Analog:** 自身，**内容零改动**。

证据：`tests/test_detectors.py:1454` 用 `Path(__file__).resolve().parent.parent / "skills_config.json"` 定位配置 —— 搬迁后自动解析为 `desktop/skills_config.json`，正是 D-04 要求的副本位置，**无需改测试**。`app.py:27-29` 用 `__file__` 推导 `sys.path`，同理自洽。

唯一例外：`tests/test_detectors.py:1-6` 的 docstring 写着 `uv run tests/test_detectors.py`，搬迁后语义仍成立（因为命令在 `desktop/` 内执行）。**不要改它** —— 改动会污染纯移动提交。

---

## Shared Patterns

### 中英分工（对所有新建文件生效）

- 标识符 / 配置键 / 文件名：**英文 ASCII**（`sync_config.py`、`expected_checks.txt`、`SOURCE`、`TARGETS`）
- 模块 docstring / 行内注释 / 用户可见输出 / 错误信息：**中文**
- 例外：`.sha256` 的 hex 与文件名片段、YAML 的 `name:` / `on:` 等语法关键字（英文，无法中文）

来源：`.planning/codebase/CONVENTIONS.md` §Language Split；示例见 `padskills/config.py:1-5`、`main.py:53-55`。

### 模块头三件套

**来源：** `padskills/config.py:1-24`、`main.py:16-50`、`tests/test_detectors.py:8-26`
**适用：** `tools/collect_checks.py`、`tools/sync_config.py`、`tools/test_sync_config.py`

```python
#!/usr/bin/env python3        # 仅可执行脚本（tools/*、tests/*）
"""中文一句话职责。

补充说明：为什么这样做、不这样会怎样。
"""

from __future__ import annotations   # 11/11 模块都有，强制

import argparse
import sys
from pathlib import Path
from typing import Dict, List, Optional   # 用 typing，不用 PEP 585
```

`__all__` 只对"被 import 的库模块"要求（`padskills/*`），`tools/` 与 `tests/` 的脚本不需要。

### 退出码契约

**来源：** `main.py:198,236-239,323-324`、`tests/test_detectors.py:1476-1480`
**适用：** 所有 `tools/*.py`、`tools/*.sh`

| 场景 | 约定 |
|------|------|
| `main(argv: Optional[List[str]] = None) -> int` | 每个 Python 入口都长这样 |
| 成功 | `return 0` |
| 校验失败 / 缺依赖 / 缺设备 | `return 1`（**不抛异常**，让 shell 与 CI 拿退出码） |
| 无法继续（配置语法错误、路径不可读） | `raise SystemExit(f"中文说明: {path}\n  {exc}")` |
| 脚本末尾 | `if __name__ == "__main__": raise SystemExit(main())` |
| shell | `set -euo pipefail` + 显式 `exit 1` |

### 输出标记词汇（全仓库统一）

**来源：** `main.py:57-65`、`tests/test_detectors.py:36-39`、`build/build_macos.sh:14,17,29`
**适用：** 所有新脚本的中文输出

| 标记 | 用途 |
|------|------|
| `▸` | 开始一个步骤（`step()` / `echo "▸ …"`） |
| `✓` | 单项通过（`check()` 绿） |
| `✗` | 单项失败（`check()` 红） |
| `·` | 补充提示 / 排查建议 |
| `═` × 62 | 横幅（`banner()`，`tests/*.py` 的 `main()`） |
| stderr `>&2` | 失败原因（shell） |

### 路径解析

**来源：** `padskills/config.py:39-43`、`build/build_macos.sh:11-12`、`build/build_windows.ps1:9-10`
**适用：** `tools/*.py`、`tools/check_desktop.sh`、所有被移动的构建脚本

一律以**脚本自身位置**为锚，绝不依赖 cwd：Python 用 `Path(__file__).resolve().parent…`，Bash 用 `BASH_SOURCE[0]`，PowerShell 用 `$PSScriptRoot`。

### 搬迁操作模式（流程约束，非代码）

**来源：** RESEARCH §Pattern 1（实测）
**适用：** 全部 8 条纯移动路径

1. 基线提交（`tools/collect_checks.py` + `shared/expected_checks.txt`）**必须早于**任何 `git mv`
2. 纯移动提交里**只允许 `git mv`**，禁止任何内容改动（包括 `.gitignore`、注释、docstring）
3. 内容适配（`.gitignore`、README、`pyproject.toml` 索引、`--write-config`）放第 3 个提交
4. 验证：`git log --follow --oneline -- desktop/padskills/config.py` 必须能看到搬迁前的提交

### 校验脚本的「反例优先」测试

**来源：** `tests/test_detectors.py` 的失败路径测试（如 `test_config_validation()`、`test_failure_diagnostics()`）
**适用：** `tools/test_sync_config.py`

每个"通过"断言都要配一个"篡改后必须失败"的断言（RESEARCH §Phase Requirements → Test Map 的负例行）：手改副本 → `--check` 必须 rc=1 且 stderr 含该文件名；多塞一份 `mobile/skills_config.json` → 必须 rc=1。只测 happy path 的闸门等于没有闸门。

---

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `.github/workflows/desktop-checks.yml` | CI config | event-driven | 仓库零 YAML、零 `.github/`，无任何 CI 先例。只能用 RESEARCH §Code Examples 的 workflow，并强制 SHA 钉死 action。 |
| `shared/expected_checks.txt` | data（baseline） | transform | 仓库无任何基线/快照数据文件。格式由 `tools/collect_checks.py` 定义（RESEARCH §Pattern 2 / A3）。 |
| `.sha256` sidecar 文件（两份） | data（校验） | file-I/O | 仓库无 hash 校验先例。格式由 `sha256sum` 兼容性决定（RESEARCH A4），由 `tools/sync_config.py` 生成。 |

> 注意：这三项**不是**"可以随便写"的意思。它们的形态在 RESEARCH 中已逐条实测并给出逐字可用的示例，planner 应直接引用 RESEARCH，而不是让执行者自由发挥。

---

## Metadata

**Analog search scope:** 仓库根（`main.py`、`app.py`、`pyproject.toml`、`FIFA-Skill-Trainer.spec`、`README.md`、`.gitignore`、`.gitattributes`、`skills_config.json`）、`padskills/`（8 模块）、`tests/`（2 脚本）、`build/`（2 构建脚本）。`.planning/` 与 `.venv/` 未作为 analog 来源。

**Files scanned:** 17 个源文件（其中 `padskills/config.py` 790 行、`tests/test_detectors.py` 1480 行采用「先 grep 定位再定向读」）；`git ls-files` 全量列表核对一次。

**Tracked-source gate:** 全部 17 个 analog 均通过 `git ls-files --error-unmatch` 验证为跟踪文件；本文件中无任何 `.gsd/capabilities/` 或其它 gitignored 镜像路径。

**Pattern extraction date:** 2026-11-04

**Downstream notes for planner:**
1. `tools/sync_config.py` 的 `--root` 参数与「多余副本扫描」是 RESEARCH 明确要求实现时补上的两项，别只抄骨架。
2. RESEARCH 的骨架用 `list[str]`，与项目 `typing.List` 约定冲突 —— 以代码库为准。
3. 纯移动提交的边界是本阶段最容易违反的流程约束（Pitfall 2），PLAN 的 action 里应显式写「本任务只允许 `git mv`」。
4. `desktop/skills_config.json` 必须被提交且**不被** `.gitignore` 命中，否则 230 项检查会假绿（Pitfall 4）。
