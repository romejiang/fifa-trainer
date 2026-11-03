# Phase 2: 安卓工具链 + 真机冒烟 APK - Pattern Map

**Mapped:** 2026-11-04
**Files analyzed:** 23 entries（18 条新建、5 条修改；另有 4 条「禁止触碰」路径单列）
**Analogs found:** 13 / 23（10 条完全无先例，见「No Analog Found」——其中 8 条是 Godot 专有格式）

> 所有被引用的 analog 均已用 `git ls-files --error-unmatch <path>` 逐项确认是 **git 跟踪的源文件**（14/14 TRACKED）。本文件中没有任何 `.gsd/capabilities/`、`.godot/`、`build/` 或其它 gitignored 镜像路径。

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `mobile/tools/doctor.sh` | shell gate（环境断言） | batch / assertion | `tools/check_desktop.sh` + `tools/verify_clean_clone.sh` | role-match（同角色，异主题） |
| `mobile/tools/gate-a.sh` | shell gate（无模板/无设备） | batch / process orchestration | `tools/check_desktop.sh` + `tools/verify_clean_clone.sh` | exact-role |
| `mobile/tools/gate-b.sh` | shell gate（打 APK + 静态校验） | batch / process orchestration | `tools/check_desktop.sh` + `desktop/build/build_macos.sh` | role-match |
| `tools/make_font_subset.py` | tool（Python CLI，一次性） | batch / transform（抽字符 → 子集） | `tools/sync_config.py` | exact-role |
| `mobile/tools/check_pack.gd` | test/gate（GDScript） | file-I/O read（从 PCK 读配置） | **无 GDScript 先例**；契约取自 `tools/sync_config.py:check()` | none（仅契约可抄） |
| `mobile/tools/glyph_coverage.gd` | test/gate（GDScript） | batch / assertion | 同上 | none（仅契约可抄） |
| `mobile/project.godot` | config（工程定义） | config read | **无** | none |
| `mobile/export_presets.cfg` | config（导出预设） | config read（导出期） | **无**；`package/unique_name` 与 `desktop/build/build_macos.sh:22` 同源 | none（单字段可对齐） |
| `mobile/assets/fonts/AppFont.tres` | config（字体资源） | config read | **无** | none |
| `mobile/src/smoke/smoke_screen.gd` | UI script | event-driven（`_process` 每帧）+ file-I/O read | **无 GDScript 先例**；文案来源 `desktop/padskills/gui.py:54-65` | none |
| `mobile/src/smoke/smoke_screen.tscn` | scene（UI 布局） | event-driven | **无** | none |
| `mobile/assets/fonts/{NotoSansSC-Subset,NotoSansSymbols2-Subset}.ttf` | asset（二进制） | — | **无**（仓库无二进制资产） | none |
| `mobile/assets/fonts/required_glyphs.txt` | data（生成物） | transform | `shared/expected_checks.txt`（同为「生成后提交、禁止手改」的基线数据） | partial |
| `mobile/assets/fonts/OFL.txt` | doc（许可证全文） | — | **无**（仓库无第三方许可证文件） | none |
| `mobile/BUILD.md` | doc（构建手册） | — | `desktop/README.md` §七 打包 + §十一 故障排查；`README.md` 地图风格 | role-match |
| `mobile/ACCEPTANCE.md`（真机验收表） | doc（人工验收清单） | — | `desktop/README.md` §十一 的「症状 → 原因 → 怎么办」体例 | partial |
| `.gitignore`（根，追加） | config | — | 自身（分组注释 + `!` 白名单） | exact |
| `.gitattributes`（根，追加） | config | — | 自身 | exact |
| `mobile/README.md`（改写现状段） | doc | — | 自身 + `README.md` 目录地图 | exact |
| `README.md`（根，改 3 处） | doc | — | 自身 | exact |
| `.github/workflows/desktop-checks.yml`（**可选**，加闸门 A） | CI config | event-driven | 自身 | exact |
| `mobile/icon.svg`（可选） | asset | — | **无** | none |

**明确禁止触碰（不是「新建/修改」，列在这里防止 planner 误排任务）**

| Path | 为什么 |
|------|--------|
| `mobile/assets/config/skills_config.json` + `.sha256` | Phase 1 生成物，唯一真源是 `shared/skills_config.json`（P-04）。本阶段**只能读**，任何「为了让闸门过而手改副本」都是破坏单一真源。 |
| `shared/skills_config.json` | 本阶段不需要改 5 个动作的任何字段。 |
| `desktop/pyproject.toml` | `fonttools` 是 SUS 且只做一次性子集工具，**不得**进入任何依赖清单（RESEARCH §Package Legitimacy Audit）。 |
| `desktop/**` | 本阶段零改动；230 项检查必须保持全绿（回归红线）。 |

---

## Pattern Assignments

### `mobile/tools/doctor.sh` (shell gate, batch/assertion)

**Analog:** `tools/check_desktop.sh`（主）+ `tools/verify_clean_clone.sh`（参数校验与退出码 2）

**文件头：shebang + 中文块注释 + 缩进三格的用法行**（`tools/check_desktop.sh:1-11`）：

```bash
#!/usr/bin/env bash
# 桌面版回归闸门：230 项检查必须全绿，且检查项名称与搬迁前基线逐项一致。
#
#   bash tools/check_desktop.sh
#
# 一条命令同时证明四件事：配置副本与唯一真源一致、检查项基线未被重新生成、
# 锁文件未漂移、桌面两套件 182 + 48 项全部通过。
#
# 基线 shared/expected_checks.txt 在搬迁前生成，本阶段禁止重新生成；若未来
# 合法新增检查，必须同时显式修改下面的常量并在提交信息中说明理由。
# 这条常量是「基线不可重写」的机械化落点：改基线而不改常量，闸门必红。
```

必须复刻的四点：① 第一行是 `# 一句话职责：<判据>。`；② 空一行后缩进三格写调用方式；③ 空一行后写「这条命令同时证明哪几件事」的编号式说明；④ 最后一段写「为什么这个常量/这个顺序不能动」。`doctor.sh` 的第 ④ 段应写 RESEARCH P7（`JAVA_HOME` 必须先设再首次 `--import`）。

**`set -euo pipefail` + 钉死常量用 `readonly UPPER_SNAKE`**（`tools/check_desktop.sh:13-16`）：

```bash
set -euo pipefail

BASELINE_SHA256=724b40a3904ddd37be432967f96ff99b8427e6b2e2e6369ef4b7b9f41a0a596a
readonly BASELINE_SHA256
```

`doctor.sh` 对应五个钉死值，全部 `readonly`：`GODOT_VERSION_PREFIX="4.7.2.stable."`（注意带尾点，且**必须前缀匹配**，RESEARCH P8）、`TEMPLATE_VERSION="4.7.2.stable"`、`JDK_MAJOR="17"`、`BUILD_TOOLS="36.1.0"`、`PACKAGE_NAME="com.fifaskill.trainer"`。

**路径锚定：`BASH_SOURCE` + 按深度数 `..`**（`tools/check_desktop.sh:18`、`tools/verify_clean_clone.sh:24`）：

```bash
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
```

⚠️ **本阶段最容易抄错的一行**：analog 位于 `tools/`（一层深），所以是 `/..`。`mobile/tools/*.sh` 是**两层深**，要写成 `/../..`；而 `mobile/tools/*.gd` 必须用 `res://tools/...` 引用（Godot 的 `res://` 锚点就是 `mobile/`）。三个坐标系不要在同一个文件里混用。

**失败信息三段式：谁错 + 实际值 + 期望值 + 怎么修**（`tools/check_desktop.sh:50-56`）：

```bash
if [ "$baseline_digest" != "$BASELINE_SHA256" ]; then
    echo "✗ 基线被修改：$baseline" >&2
    echo "  实际 SHA-256: $baseline_digest" >&2
    echo "  期望 SHA-256: $BASELINE_SHA256" >&2
    echo "  本阶段禁止重新生成基线；合法新增检查必须同步更新脚本里的 BASELINE_SHA256。" >&2
    exit 1
fi
```

`doctor.sh` 的每个断言都必须长这样（例如 JDK 那条要打出「解析出的 java_sdk_path」「`java -version` 第一行」「期望 17」，再给一行「改哪一行 / 跑哪条命令」）。RESEARCH 对 doctor 的要求原文是「失败必须指名『改哪一行』」，这段就是它的机械化模板。

**参数分支 + 退出码 2**（`tools/verify_clean_clone.sh:26-33`）：

```bash
mode="${1:-}"
case "$mode" in
    "" | --tamper) ;;
    *)
        echo "✗ 未知参数：${mode}（只接受留空或 --tamper）" >&2
        exit 2
        ;;
esac
```

`doctor.sh` 应采用同样的 `case` 形状支持**按断言名单独运行**（`doctor.sh godot` / `doctor.sh jdk`），默认无参跑全部五项。理由见下方「设计冲突 1」——闸门 A 不能依赖模板，但又必须复用版本断言。

**前置条件不满足时用 `exit 2` 而不是 1**（`tools/verify_clean_clone.sh:35-40`）：

```bash
if [[ -n "$(git -C "$repo_root" status --porcelain)" ]]; then
    echo "✗ 工作区有未提交改动，干净 clone 只能验证已提交状态" >&2
    git -C "$repo_root" status --porcelain >&2
    exit 2
fi
```

照此推导 `doctor.sh` 的语义：**被断言的环境缺项 → `exit 1`**（那不是「脚本用错了」，正是 doctor 要报告的对象）；**调用方式错（未知断言名）→ `exit 2`**。

**禁止 `set -x`**：RESEARCH §Security Domain 明确要求，导出日志里 Godot 自己会把 `--ks` 脱敏，但 `set -x` 会把 `GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD` 原样打到 stdout。`check_desktop.sh` / `verify_clean_clone.sh` 都没用过 `set -x`，保持一致。

**环境变量覆盖（无仓库先例，按 RESEARCH 写）**：本仓库**没有**任何 `${VAR:-default}` 用法（已 grep 确认 0 处；只有 `check_desktop.sh:22-25` 的裸 `export`）。因此 `GODOT_BIN` / `ANDROID_SDK_ROOT` 的默认值写法只能照 RESEARCH §Code Examples 7，不要假装有先例。

---

### `mobile/tools/gate-a.sh` (shell gate, batch/orchestration)

**Analog:** `tools/check_desktop.sh`（步骤编排 + trap）+ `tools/verify_clean_clone.sh`（「不复制检查逻辑，只做调度与断言」）

**「第一步必须是配置校验」——这条注释是整个 Phase 2 的闸门灵魂**（`tools/check_desktop.sh:30-36`）：

```bash
# 第一步必须是配置校验：副本缺失时 load_config() 会静默回退到内置
# DEFAULT_CONFIG，测试照样全绿，但测的已经不是真源了（假绿）。
echo "▸ 校验配置副本…"
if ! python3 "$repo_root/tools/sync_config.py" --check; then
    echo "  运行 python3 tools/sync_config.py 重新生成副本后再试。" >&2
    exit 1
fi
```

**gate-a.sh 必须原样复刻这个顺序**，理由更强：PCK 闸门读的就是 `mobile/assets/config/skills_config.json`；如果那份副本被手改过，PCK 里的内容照样能解析、`SKILL_COUNT` 照样是 5，闸门 A 会给出一个「配置真的进包了」的**假绿**。顺序 = `sync_config.py --check` → `--import` → `--check-only` → `--export-pack` → `--main-pack check_pack.gd` → `glyph_coverage.gd`。

**tmp + trap 清理**（`tools/check_desktop.sh:27-28`）：

```bash
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
```

**「本脚本不复制任何检查逻辑」**（`tools/verify_clean_clone.sh:19-20`）：

```bash
# 本脚本不复制任何检查逻辑：命令、数量、阈值全在 check_desktop.sh 与
# sync_config.py 里，这里只负责调度与断言。
```

照此推导：gate-a 里**不要**再写一遍 `4.7.2.stable` 的前缀判断，调 `bash "$repo_root/mobile/tools/doctor.sh" godot` 即可。同理 gate-b 调 gate-a，而不是把五条 A 层命令再抄一遍——两份定义必然漂移。

**失败判定必须包进 `if !`，绝不 `|| true`**（`tools/verify_clean_clone.sh:74-79`，《Phase 1 PATTERNS 已把它列为全仓库级约束》）：

```bash
# 期望失败必须用 if 包起来，绝不能用 || true 吞掉退出码后照样打印成功 ——
# 一个永远绿的反例比没有反例更危险。
if out="$(python3 tools/sync_config.py --check 2>&1)"; then
    echo "✗ 手改副本后 --check 仍然通过" >&2
    exit 1
fi
```

**绝对路径**：RESEARCH P2 —— `--path mobile` 之后，`--export-pack` / `--export-release` 的相对路径锚点是**工程目录**，不是 cwd。analog 里所有传给外部程序的路径都是 `"$repo_root/..."` 形式（`check_desktop.sh:33,68`），gate 脚本必须保持这个习惯，产物路径统一 `"$repo_root/mobile/build/..."`。

**结束行**（`tools/check_desktop.sh:90`）：

```bash
echo "✓ 230 项检查全部通过，名称与基线逐项一致"
```

gate-a 的对应行应写成 `✓ 闸门 A 通过：配置一致、脚本语法通过、PCK 内含 5 条动作、139 个字形可渲染`——把「证明了什么」写进最后一行，而不是只写 `OK`。

---

### `mobile/tools/gate-b.sh` (shell gate, batch/orchestration)

**Analog:** `tools/check_desktop.sh` + `desktop/build/build_macos.sh`

**打包脚本的骨架**（`desktop/build/build_macos.sh:9-31`）：

```bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

echo "▸ 安装打包依赖…"
uv sync --extra build

echo "▸ 开始打包…"
uv run pyinstaller \
    --noconfirm --clean \
    --windowed --noupx \
    --name "FIFA Skill Trainer" \
    --osx-bundle-identifier com.fifaskill.trainer \
    --hidden-import pygame._sdl2.controller \
    --exclude-module XInput \
    app.py

app="dist/FIFA Skill Trainer.app"
if [[ ! -d "$app" ]]; then
    echo "没有找到产物：$app" >&2
    exit 1
fi
```

注意两个细节：① 长命令用**反斜杠续行 + 每行一个参数**，不用一行超长；② 产物断言单独一段，且**不用 `✗` 前缀**（这是 Phase 1 之前就存在的脚本，它用裸中文 + `>&2`）。新建脚本统一用 `✗`（见输出标记词汇），但不要把 `build_macos.sh` 的风格当成新脚本的模板。

**成品的收尾说明用 heredoc**（`desktop/build/build_macos.sh:33-47`）：

```bash
cat <<EOF

完成：$app

未签名的 App 第一次打开会被 Gatekeeper 拦下，任选一种方式放行：
  1. 右键点 App → 打开 → 再点"打开"
  2. xattr -dr com.apple.quarantine "$app"
EOF
```

gate-b 结尾同样应给「产物在哪、怎么装、下一步是什么」三行，而不是只打印路径。

**gate-b 独有的三条硬约束（全部来自 RESEARCH 实测，不是风格问题）：**

1. **不许用 `cmd | grep -q` 当判据**（RESEARCH §Code Examples 7 注 (b)）。`apksigner verify` 通过管道接 `grep` 时 `$?` 是 `grep` 的。写成 `if ! "$bt/apksigner" verify --print-certs "$out" >/dev/null; then ... fi`。
2. **退出码 0 不够**（RESEARCH P3）：缺 keystore 时导出打印 WARNING、退出码 1，但 `nokey.apk` 26.5 MB 照样躺在 `build/`。所以顺序必须是 `rm -f "$out"` → 导出 → `apksigner verify` → `zipalign -c -P 16 -v 4` → `unzip -l` 断言 → `aapt2 dump badging`。任何一条都不能省。
3. **密钥只走环境变量，且要 fail-fast**（RESEARCH §Code Examples 7）：

```bash
# 只有口令是必填输入；路径与别名由脚本解析出与 doctor.sh 逐字相同的默认值。
KEYSTORE_PATH="${FIFA_KEYSTORE:-$HOME/.fifa-trainer/release.keystore}"
KEYSTORE_ALIAS="${FIFA_KEYSTORE_ALIAS:-fifa-trainer}"
: "${GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD:?缺密码：见 mobile/BUILD.md 第四节}"
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD
GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$KEYSTORE_PATH" \
GODOT_ANDROID_KEYSTORE_RELEASE_USER="$KEYSTORE_ALIAS" \
  "$godot" --headless --path "$repo_root/mobile" --export-release "Android" "$out"
```

`: "${VAR:?中文消息}"` 是 bash 原生 fail-fast：变量为空就非零退出并打印中文。这是仓库里**第一次**出现该写法（grep 确认 0 处先例），planner 应把它标成「新引入的惯例」，并在 BUILD.md 里写出变量名。**注意 `:?` 的消息会进 stderr，不要把它写成密码或路径值。** 只有口令用 `:?`：路径与别名在仓库里各只有一个正确答案，要求调用者再导出两个恒定变量，只会制造一种与「包打成没打成」无关的红。

**`unzip -l` 的路径是 `assets/assets/...`**（RESEARCH §Code Examples 7 注 (a)）：PCK 整体挂在 APK 的 `assets/` 下，所以 `res://assets/config/x.json` 在 zip 里是 `assets/assets/config/x.json`。这个双 `assets` 是最容易被「修」成假的断言——如果写错成单 `assets/`，`grep -q` 永远失败；如果为了让它过而删掉断言，成功标准 3 就失去机械证明。

---

### `tools/make_font_subset.py` (Python CLI, batch/transform)

**Analog:** `tools/sync_config.py`（同角色、同「生成物 + 校验」模式）

**模块头三件套**（`tools/sync_config.py:1-22`）：

```python
#!/usr/bin/env python3
"""把 shared/skills_config.json 同步成两份只读副本，并校验三者一致。

真源只有一份：``shared/skills_config.json``。桌面版开发态读
``desktop/skills_config.json``，未来的 Godot 工程读
``mobile/assets/config/skills_config.json`` —— 两份都是本脚本生成的副本，
不允许手改。手改副本、少写一个 ``.sha256``、多抄一份配置文件，都会被
``--check`` 抓出来并指名道姓。

    python3 tools/sync_config.py           # 生成 / 刷新两份副本
    python3 tools/sync_config.py --check   # 只校验，不写盘

路径一律以脚本自身位置为锚，所以在任何 cwd 下运行都指向同一个仓库。
"""

from __future__ import annotations

import argparse
import hashlib
import sys
from pathlib import Path
from typing import List, Optional, TextIO
```

必须复刻：`#!/usr/bin/env python3`、中文 docstring（职责 + 为什么 + 缩进四格的用法示例 + 路径锚定说明）、`from __future__ import annotations`、`typing.List/Optional`（**不用** `list[str]`）、只用 stdlib。

**常量集中 + 白名单注释**（`tools/sync_config.py:24-36`）：

```python
SOURCE = Path("shared") / "skills_config.json"
TARGETS = (
    Path("desktop") / "skills_config.json",
    Path("mobile") / "assets" / "config" / "skills_config.json",
)
SIDECAR_SUFFIX = ".sha256"

# 扫描"多余副本"时整体跳过的目录名：生成物、工具缓存、历史遗留路径。
# 跳过不等于放过 —— 白名单里的三个路径仍然逐个校验。
_SKIP_DIRS = frozenset({
    ".git", ".venv", ".planning", "__pycache__", "node_modules",
    ".godot", "build", "dist", "export",
})
```

`make_font_subset.py` 对应写出**字符来源清单**（哪些文件抽字符）作为模块级常量，并在注释里写清「为什么是这几个文件」：`shared/skills_config.json`（动作名 / `_readme`）、`desktop/padskills/gui.py`（`_ADVICE`）+ `desktop/padskills/detectors.py`（`FAILURE_LABELS`）、`mobile/src/smoke/smoke_screen.gd`（首屏文字）。

**`repo_root()` 以 `__file__` 为锚**（`tools/sync_config.py:39-41`）：

```python
def repo_root() -> Path:
    """仓库根目录：以脚本位置（tools/ 的上一级）为锚，不依赖调用方的 cwd。"""
    return Path(__file__).resolve().parent.parent
```

**幂等写盘：内容相同就不落盘**（`tools/sync_config.py:80-104`）：

```python
data = src.read_bytes()
digest = sha256(data)
for rel in TARGETS:
    target = root / rel
    target.parent.mkdir(parents=True, exist_ok=True)
    if not target.is_file() or target.read_bytes() != data:
        target.write_bytes(data)
```

`make_font_subset.py` 对两个 `.ttf` 与 `required_glyphs.txt` 也要先比较再写——否则每跑一次 gate-a 都会把仓库弄脏，而这正是 `verify_clean_clone.sh:57-61` 那条「跑完 clone 仍是干净的」断言要防的事。

⚠️ **`pyftsubset` 的产物不保证跨 fonttools 版本字节一致**。因此「相同才不写」只能省掉无谓的 mtime 变更，不能用来断言「重跑必然零 diff」。BUILD.md 必须写明：**子集产物提交进仓库后，构建链路不再需要 fonttools**。

**入口契约**（`tools/sync_config.py:155-182`）：

```python
def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        prog="sync_config.py",
        description="把 shared/skills_config.json 同步成两份只读副本，并校验 hash",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "示例:\n"
            "  python3 tools/sync_config.py           生成 / 刷新两份副本\n"
            "  python3 tools/sync_config.py --check   只校验，不写盘\n"
        ),
    )
    ...
    return check(root) if args.check else sync(root)


if __name__ == "__main__":
    raise SystemExit(main())
```

`make_font_subset.py` 应提供 `--check`（只比对、不写盘）与默认（生成）两种模式，与 `sync_config.py` 完全同构；这样 gate-a 可以只调 `--check`，不会在 CI 里意外重写二进制资产。

**不要 import fontTools**。RESEARCH §Package Legitimacy Audit 已把它标成 SUS 并要求「不进入构建链路」。正确做法是 `subprocess.run(["uv", "run", "--with", "fonttools", "pyftsubset", ...])`——脚本本体保持纯 stdlib，依赖只在那条子进程里出现，`desktop/pyproject.toml` 一个字不改。

---

### `mobile/tools/check_pack.gd` / `mobile/tools/glyph_coverage.gd` (GDScript gates)

**Analog: 无。** 仓库里 0 个 `.gd` 文件（已确认 `git ls-files | grep -E '\.(gd|tscn|tres|godot|cfg)$'` → NONE）。**planner 不要给这两个文件编造 analog。**

可抄的**只有契约层**，来自 Python/Shell 的退出码与报错惯例：

**「收集全部问题，最后一次性报告」**（`tools/sync_config.py:107-152`）：

```python
def check(root: Path, stream: Optional[TextIO] = None) -> int:
    """校验副本与真源一致，并确认没有第四份副本。

    先把全部问题收集完再一次性报告，不在第一个错误处中断 —— 出问题时
    开发者想看到的是"一共错了几处"，不是"第一处是什么"。
    """
    ...
    problems: List[str] = []
    ...
    for line in problems:
        print(line, file=err)
    return 1 if problems else 0
```

`check_pack.gd` 已经天然是这个形状（`failures: Array[String]` → 循环 `printerr` → `quit(1)`），`glyph_coverage.gd` 的 `missing` 数组同理。**不要在 GDScript 里改成「第一个缺失就 return」**——两台 OEM 上真正想知道的是缺了几个、分别是哪些。

**退出码必须显式传参（RESEARCH P9）**：`quit(0)` / `quit(1)`，绝不裸 `quit()`。实测同一个 `_initialize()` 里裸 `quit()` 曾返回 1。

**输出语汇：英文机器 token + 中文人话**，与项目既有的「失败码是英文 snake_case、标签是中文」同构（`AGENTS.md` §Failure codes / `desktop/padskills/detectors.py:65-76`）：

```gdscript
print("PACK_OK skills=%d" % EXPECTED_SKILLS)
printerr("PACK_FAIL " + f)
```

成功用 `print` → stdout，失败用 `printerr` → stderr。`PACK_OK` / `PACK_FAIL` / `GLYPH_OK` / `GLYPH_MISSING` 是给 CI `grep` 用的，后面的中文是给人看的。shell 侧捕获时 `2>&1` 再看 token，与 `verify_clean_clone.sh:80-87` 的做法一致。

**`.sha256` 解析：取第一个空白分隔字段**（RESEARCH P15）。两边必须完全对齐——

生成侧（`tools/sync_config.py:98-99`）：

```python
# 固定写成 sha256sum 兼容格式：「摘要 + 两个空格 + 文件名」，行尾 LF。
line = f"{digest}  {target.name}\n"
```

校验侧（`tools/sync_config.py:139-143`）：

```python
fields = side.read_text(encoding="utf-8").split()
if not fields:
    problems.append(f"✗ {rel.as_posix()}{SIDECAR_SUFFIX} 内容为空")
elif digest and fields[0] != digest:
    problems.append(f"✗ {rel.as_posix()}{SIDECAR_SUFFIX} 与真源摘要不符")
```

GDScript 对应：`FileAccess.get_file_as_string(PATH).strip_edges().split(" ", false)[0]`。实测 sidecar 的字节是 `bccf…eee9` + **两个空格** + `skills_config.json` + `\n`（`xxd` 已确认）。**照「字符串相等」写必然永远失败**，而第一次失败之后最危险的「修法」是把校验删掉——所以这一条要写进 gate 脚本的注释。

**`expected_skills = 5` 是硬编码常量，必须带「为什么可以硬编码」的注释**。analog 是 `tools/check_desktop.sh:15` 的 `BASELINE_SHA256` + 第 9-11 行的说明：「若未来合法新增检查，必须同时显式修改下面的常量并在提交信息中说明理由」。`check_pack.gd` 的对应注释应写成「`EXPECTED_SKILLS = 5` 对应 `shared/skills_config.json` 的 5 条动作；新增动作时必须同步改这里，不许改成『读到几条算几条』——那样这条断言就永远绿」。

---

### `mobile/project.godot` (config, config read)

**Analog: 无。** 仓库里没有任何 Godot 工程文件；Phase 1 的 D-10 明确把创建权留给本阶段（`mobile/README.md:5`）。

**唯一真源：RESEARCH §Code Examples 1**，逐字使用：

```ini
config_version=5

[application]

config/name="FIFA 花式动作练习器"
run/main_scene="res://src/smoke/smoke_screen.tscn"
config/features=PackedStringArray("4.7", "GL Compatibility")

[rendering]

renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
textures/vram_compression/import_etc2_astc=true

[gui]

theme/custom_font="res://assets/fonts/AppFont.tres"
```

四个不能改的键，每个都对应一条实测失败：`config_version=5`（4.7.2 的当前值）、`"4.7"` 不是 `"4.7.2"`（引擎按 major.minor 匹配，且它是「4.8 打开会改写本文件」的哨兵）、`import_etc2_astc=true`（P1：不加则导出直接失败）、`gl_compatibility`（P-03：把 minSdk 压回 24）。

**`.ini` 的注释前缀不适用**：`project.godot` 用 `;` 注释，而 `export_presets.cfg` 也是 `;`。两者都不是标准 INI 库，不要用 `#`。仓库里唯一可参考的「配置即源码」体例是 `.gitignore:10` 那种「为什么必须这么写」的行内注释——把同样的说明放进 `;` 注释里，写在对应键的上方。

---

### `mobile/export_presets.cfg` (config, export-time read)

**Analog: 无**（`.cfg` 在仓库里 0 个）。**唯一真源：RESEARCH §Code Examples 2。**

```ini
[preset.0]

name="Android"
platform="Android"
runnable=true
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter="assets/config/*.json,assets/config/*.sha256"
exclude_filter=""
export_path="build/fifa-trainer.apk"
...
[preset.0.options]

custom_template/debug=""
custom_template/release=""
gradle_build/use_gradle_build=false
architectures/armeabi-v7a=false
architectures/arm64-v8a=true
architectures/x86=false
architectures/x86_64=false
package/unique_name="com.fifaskill.trainer"
package/name="FIFA 花式动作练习器"
package/signed=true
version/code=1
version/name="0.1.0"
permissions/vibrate=true
```

**五个必须写死的点：**

| 键 | 值 | 理由 | 来源 |
|----|----|------|------|
| `include_filter` | `assets/config/*.json,assets/config/*.sha256` | `.json` 在 4.7.2 已自动入包，但 **`.sha256` 不是资源**，不加过滤就丢 | P5 |
| `package/unique_name` | `com.fifaskill.trainer` | 与桌面版 macOS bundle id **完全同一个身份** | `desktop/build/build_macos.sh:22` |
| `architectures/*` | 只有 `arm64-v8a=true` | 成功标准 1 写死 arm64；x86_64 混入是 gate-b 的失败条件 | RESEARCH |
| keystore 六个键 | **一个都不能出现** | 4.7.2 里全是 `PROPERTY_USAGE_SECRET`，编辑器一保存就搬进 `.godot/export_credentials.cfg` | RESEARCH §Code Examples 2 |
| `version/code` / `version/name` | `1` / `"0.1.0"` | Phase 9 的 v1→v2 覆盖安装依赖它们单调递增；现在定死接口 | P-08 |

**唯一可跨文件对齐的 analog：bundle id。** 桌面版 `desktop/build/build_macos.sh:22`：

```bash
--osx-bundle-identifier com.fifaskill.trainer \
```

移动端写 `package/unique_name="com.fifaskill.trainer"`。**这个值一旦发给朋友就不能改**（改了 = 另一个 app + 数据全丢），BUILD.md 必须把它写成「不可变事实」而不是「当前值」。

`export_path` 只是编辑器里的默认值；脚本调用 `--export-release "Android" <绝对路径>` 时以命令行参数为准（RESEARCH P2 的坑就在这）。

---

### `mobile/assets/fonts/AppFont.tres` + 两个子集 `.ttf` + `required_glyphs.txt` + `OFL.txt`

**Analog: 无**（`.tres` 与二进制资产在仓库里都是 0 个）。

`AppFont.tres` 逐字用 RESEARCH §Code Examples 3：

```ini
[gd_resource type="FontVariation" format=3]

[ext_resource type="FontFile" path="res://assets/fonts/NotoSansSC-Subset.ttf" id="1_sc"]
[ext_resource type="FontFile" path="res://assets/fonts/NotoSansSymbols2-Subset.ttf" id="2_sym"]

[resource]
base_font = ExtResource("1_sc")
fallbacks = Array[Font]([ExtResource("2_sym")])
```

**必须有两条链路**，因为没有任何一个字体单独覆盖 `° ± → ✓ ✗`：Noto Sans SC 缺 `✗`（U+2717），Noto Sans Symbols 2 缺 `° ± →`。这不是优化，是成功标准 2 的硬条件（RESEARCH P6）。

`required_glyphs.txt` 与两个 `.ttf` 是**同一次运行的三份产物**，必须由 `tools/make_font_subset.py` 以**同一份字符清单**生成。RESEARCH 原文：「清单与子集必须同源，否则字形闸门会假绿」。这个「生成物不得手改」的体例在仓库里有先例——`shared/expected_checks.txt` 由 `tools/collect_checks.py` 生成、且用 `BASELINE_SHA256` 钉死（`tools/check_desktop.sh:15,40-56`）。`required_glyphs.txt` 不需要钉 hash，但需要 `glyph_coverage.gd` 直接读它，**不许在 `.gd` 里再抄一份字符表**。

`OFL.txt` 是 SIL OFL 1.1 全文，随字体一起进仓库与 APK。仓库无许可证文件先例，直接放官方文本，不改写、不翻译。

---

### `mobile/src/smoke/smoke_screen.gd` / `.tscn` (UI script + scene)

**Analog: 无 GDScript 先例。** 但**文案不能自己编**——`const LONGEST` 必须是仓库里真实存在的最长中文串。

RESEARCH §Code Examples 6 用的就是这一条，出处是 `desktop/padskills/gui.py:59`：

```python
"wrong_start": "起点错了：注意从左摇杆朝向的哪个方位起手。",
```

`_ADVICE` 全表在 `desktop/padskills/gui.py:54-65`，是「失败原因 → 一句可执行的建议」的唯一真源。首屏要证明「中文不豆腐」，用真实 UI 文案比编一句更长的假字符串有意义：**它同时验证了字符集和真实排版长度**。

三个必须保留的细节（都来自 RESEARCH §Code Examples 6）：

```gdscript
func _ready() -> void:
	Input.use_accumulated_input = false          # 采样时钟归 Phase 4，这里先关掉便于观察
	Input.joy_connection_changed.connect(_on_joy_changed)
	_load_config()
	_refresh_axes()
```

```gdscript
	if _device_ids.is_empty():
		_axes.text = "没有检测到手柄：先按手柄上任意键唤醒"
		return
```

```gdscript
		for axis in range(8):
			out.append("  axis %d = %+.3f" % [axis, Input.get_joy_axis(d, axis as JoyAxis)])
```

- `Input.use_accumulated_input = false` 必须在 `_ready()` 里（P-06/Constraints：默认每帧 flush 一次）。**但要在注释里写清「本阶段只为了看得见，采样契约归 Phase 4」**，否则 Phase 4 会以为这里已经建立了输入契约。
- 「先按任意键唤醒」的提示**无条件显示**（RESEARCH P14，标 ASSUMED）。真假都该有这句话，成本为零。
- 轴读数用 `Input.get_joy_axis()`（每帧快照），**故意不用事件**。成功标准 4 只要求「看得见在动」。

**命名分工**（`AGENTS.md` §Language Split + `CONVENTIONS`）：节点名 `Header` / `Axes` 用英文 PascalCase；`unique_name_in_owner = true` + `%Header` / `%Axes` 取引用；所有 `.text` 赋值是中文；`_skill_count`、`_device_ids`、`_refresh_axes()` 这类内部成员按 GDScript 惯例用下划线前缀——**这与 Python 侧的 `_pending` / `_tick` 单下划线私有约定方向一致，但 GDScript 的下划线只是约定，不影响可访问性**。

**`smoke_screen.tscn` 手写即可**（RESEARCH §Code Examples 6 给了完整 18 行）。`load_steps=2`（1 个 ext_resource + 场景本身）、`format=3`、`layout_mode = 3` + `anchors_preset = 15` 全屏铺满。**不需要打开编辑器**——这正是「全程不经过 Godot 编辑器」的一部分。

---

### `mobile/BUILD.md` (doc)

**Analog:** `desktop/README.md` §七 打包 + §十一 故障排查；`README.md` 的仓库地图风格。

**章节编号用中文数字，每节一个动词短语**（`desktop/README.md:548`、`:668`）：

```markdown
## 七、打包成双击就能用的应用
## 十一、故障排查
```

**前置条件写成「顺序 + 为什么顺序不能反」**（`desktop/README.md:574-575`）：

```markdown
> **Input Monitoring 权限和 App 的路径绑定**：把 `.app` 挪了位置之后，
> 需要到「系统设置 → 隐私与安全性 → 输入监控」里重新勾一次，否则读不到摇杆。
```

`BUILD.md` 的头号警告要用同样的 `> **加粗短语**：` 体例写 RESEARCH P7 / Pattern 2：

> **先设 `JAVA_HOME`，再跑第一次 `--import`。** 顺序反了，`java_sdk_path` 会被永久写成当时那个 JDK（本机首次就被写成了 JDK 25）。

**版本表**直接照搬 README 的表格体例，五列：组件 / 精确版本 / 期望输出（可断言的前缀）/ 安装位置 / 校验命令。RESEARCH §Standard Stack 与 §Version verification 已经把内容备齐，**不要重写版本号，逐字复制**（尤其 `4.7.2.stable.official.<hash>` 与 `--version` 前缀匹配那条）。

**故障排查用「症状加粗 + 分点原因 + 一条可执行命令」**（`desktop/README.md:670-676`）：

```markdown
**手柄识别不到**
用 `--list` 看。

- Windows：FIFA 本身需要 XInput，所以手柄最好切到 XInput 模式；换一个 USB 口试试。
- macOS：「系统设置 → 隐私与安全性 → 输入监控」里允许终端 / App；
  先用系统的「游戏控制器」面板确认系统本身能看到手柄。
```

`BUILD.md` 的排查表至少覆盖 RESEARCH P1–P15 里会在「另一台机器」上复现的 8 条：P1（`import_etc2_astc`）、P2（相对路径）、P3（未签名 APK）、P7（JDK 顺序）、P8（`--version` 前缀）、P10（adb 噪声）、P11（`.idsig`）、P13（`.godot/` 不存在）。

**必须含一节「同一把钥匙的指纹」**：把 `apksigner verify --print-certs` 的证书 SHA-256 抄进文档（RESEARCH §Security Domain）。这是 Phase 9 覆盖安装的唯一可核对凭据。

**keystore 备份**照 RESEARCH §Open Questions 5 写：「离线介质 + 至少两处 + 密码与文件分开存放」。**文档里不出现密码**，只出现「密码在 X 处」的指引。

---

### `.gitignore` / `.gitattributes`（根，追加）

**Analog: 自身。**

`.gitignore` 的分组注释是中文、每组之间空一行（`.gitignore:1-30`）：

```gitignore
# PyInstaller / local build artifacts
# 必须写 desktop/build/* 而不是 desktop/build/：目录被整体排除后 ! 无法再把脚本捞回来
desktop/dist/
desktop/build/*
!desktop/build/build_windows.ps1
!desktop/build/build_macos.sh

# 移动端产物（Phase 2 起才会有内容，先占位，避免第一次导出就把缓存提交进来）
mobile/.godot/
mobile/build/
mobile/export/
*.apk
```

已有 `mobile/.godot/`、`mobile/build/`、`mobile/export/`、`*.apk` 四条覆盖了 RESEARCH P11/P13 的大部分。**本阶段需要补的只有三类**（放在「移动端产物」组内，不要新开一组）：

```gitignore
*.idsig                 # apksigner 的 v4 旁文件（P11），分发时只拷 .apk
*.keystore              # release / debug 密钥永远不进仓库
*.jks                   # keytool 的另一种扩展名
```

⚠️ **不要**把 `mobile/assets/fonts/*.ttf` 加进去——子集产物必须提交（RESEARCH：产物提交后构建不再需要 fonttools）。

`.gitattributes` 是逐扩展名枚举的（`.gitattributes:1-11`）：

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
*.sha256 text eol=lf
*.txt text eol=lf
```

追加 Godot 侧五种文本格式 + 明确二进制（保持字母序/语义分组，不要打乱现有行）：

```gitattributes
*.gd text eol=lf
*.tscn text eol=lf
*.tres text eol=lf
*.cfg text eol=lf
*.godot text eol=lf
*.ttf binary
```

`*.godot` 匹配 `project.godot`；`*.cfg` 匹配 `export_presets.cfg`。`.sh` 已有规则，`mobile/tools/*.sh` 自动覆盖。

---

### `mobile/README.md`（改写）+ `README.md`（根，改 3 处）

**Analog: 自身。**

`mobile/README.md:5` 现在写着：

```markdown
**Phase 1 只有配置副本，没有 Godot 工程。** `project.godot` 由 Phase 2 创建 —— 若先用未锁定版本的 Godot 生成，Phase 2 用正确版本打开时会被静默重写，所以创建权交给锁定工具链的那一阶段。
```

这句在 Phase 2 完成后**就是错的**，必须改写。同时 `:7-14` 的「目录现状」只有两行，要扩成 `mobile/` 的真实树（`project.godot` / `export_presets.cfg` / `assets/` / `src/smoke/` / `tools/` / `build/`）。仓库里「目录树 + 每行一句职责」的体例见 `README.md:19-26` 与 `desktop/README.md:602-623`。

根 `README.md` 要改三处：`:6`（「Phase 2 才创建 Godot 工程」→ 已完成）、`:22`（`mobile/` 一行描述）、`:24`（`tools/` 一行加上 `make_font_subset.py`）。**改法照 `README.md` 现有的「一条命令 + 它同时证明什么」风格，不要写成变更日志。**

---

## Shared Patterns

### 1. 中英分工（对所有新建文件生效，含 `.gd` / `.cfg` / `.md`）

| 层 | 语言 | 例子 |
|----|------|------|
| 文件名、目录名、标识符、配置键、机器 token | **英文 ASCII** | `gate-a.sh`、`check_pack.gd`、`EXPECTED_SKILLS`、`package/unique_name`、`PACK_OK` |
| 模块 docstring、行内注释、用户可见文案、错误信息 | **中文** | `# 先按任意键唤醒`、`✗ 缺 keystore 路径`、`SKILL_COUNT = 5`（数值英文，标签英文） |
| 例外 | 语法关键字无法中文 | INI 的 `[preset.0]`、GDScript 的 `extends SceneTree`、`.sha256` 的 hex 与文件名 |

来源：`.planning/codebase/CONVENTIONS.md` §Language Split；`AGENTS.md` P-07；实例 `tools/sync_config.py:1-14`、`tools/check_desktop.sh:1-11`。

### 2. 输出标记词汇（全仓库统一）

| 标记 | 用途 | 去向 |
|------|------|------|
| `▸` | 开始一个步骤 | stdout |
| `✓` | 单项通过 | stdout |
| `✗` | 单项失败 | **stderr**（`>&2`） |
| `·` | 补充提示 / 排查建议 | stdout |
| `  ✓`（两空格缩进） | 子步骤通过 | stdout |

来源：`tools/check_desktop.sh:32,40,51,60,70,75,86,90`、`tools/verify_clean_clone.sh:30,37,45,49,52,58,63,71,77,81,85,90,94,98,102,106,111`。GDScript 侧对应 `print()`（成功）/ `printerr()`（失败），token 用 `PACK_OK` / `PACK_FAIL` / `GLYPH_OK` / `GLYPH_MISSING`。

### 3. 退出码契约

| 场景 | 码 | 来源 |
|------|----|------|
| 成功 | `0` | 全部脚本 |
| 断言失败 / 缺依赖 / 缺设备 / 配置不一致 | `1` | `check_desktop.sh:35,55,71,76,87`；`sync_config.py:152` |
| 调用方式错误 / 前置条件不成立（脏工作区、未知参数） | `2` | `verify_clean_clone.sh:31,39` |
| GDScript 探针 | 显式 `quit(0)` / `quit(1)`，**禁止裸 `quit()`** | RESEARCH P9 |
| Python 入口 | `def main(argv: Optional[List[str]] = None) -> int` + `raise SystemExit(main())` | `sync_config.py:155,181-182` |

### 4. 路径解析：三个坐标系，别混

| 场景 | 锚点 | 写法 |
|------|------|------|
| Shell 脚本 | 脚本自身位置 | `repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"` — **`mobile/tools/` 要写 `/../..`** |
| Python 工具 | `__file__` | `Path(__file__).resolve().parent.parent`（`sync_config.py:39-41`） |
| Godot 资源 | 工程根 `res://` = `mobile/` | `res://tools/check_pack.gd`、`res://assets/config/...` |
| **传给 Godot 的产物路径** | **必须绝对路径** | `"$repo_root/mobile/build/verify.pck"`（RESEARCH P2：`--path` 之后相对路径锚点是工程目录，不是 cwd） |
| APK 内部路径 | PCK 挂在 `assets/` 下 | `unzip -l` 里是 `assets/assets/config/skills_config.json`（双 `assets`） |

来源：`check_desktop.sh:18`、`verify_clean_clone.sh:24`、`sync_config.py:39-41`、`desktop/build/build_macos.sh:11-12`。

### 5. 失败信息三段式

任何断言失败都要给出：**① 谁 / 哪个文件 ② 实际值 ③ 期望值 ④ 怎么修（一条可执行命令或「改哪一行」）**。

`tools/check_desktop.sh:50-56` 是逐字模板（见上文 doctor.sh 段）。`sync_config.py:124-148` 是「收集全部再一次性打印」的批量版本。`tools/verify_clean_clone.sh:30` 是「一句话说清为什么不接受这个参数」的极简版本。

### 6. 「先校验生成物，再跑依赖它的测试」

`tools/check_desktop.sh:30-36` 的注释已经把原理写死：「副本缺失时 `load_config()` 会静默回退到内置 `DEFAULT_CONFIG`，测试照样全绿，但测的已经不是真源了（假绿）」。

**Phase 2 的两处同构风险：**

1. `gate-a.sh` 若不先跑 `sync_config.py --check`，PCK 闸门会对着手改过的副本报 `PACK_OK`。
2. `make_font_subset.py` 生成的 `required_glyphs.txt` 与 `.ttf` 若不是同源，`glyph_coverage.gd` 会对着「自己生成的清单」报 `GLYPH_OK`，而屏幕上依然豆腐。

两处都必须在脚本注释里写明「为什么这个顺序不能换」，而不是靠 reviewer 记得。

### 7. 幂等与「跑完不弄脏仓库」

`tools/sync_config.py:96-102` 的「内容相同就不落盘」+ `tools/verify_clean_clone.sh:57-61` 的零漂移断言是同一个原则的两面。Phase 2 的 `make_font_subset.py` 与 `gate-a.sh`（会生成 `mobile/build/verify.pck`）都要满足：**跑完之后 `git status --porcelain` 只允许出现被 `.gitignore` 覆盖的路径**。

### 8. 密钥只在环境变量里

仓库零密钥先例（`.gitignore` 里目前连 `*.keystore` 都没有）。本阶段新引入的惯例：

- `export_presets.cfg` 里**零** `keystore/*` 键（4.7.2 的 SECRET 机制会把它们搬走，写进去也会被静默移走）。
- 三个环境变量名固定为 `GODOT_ANDROID_KEYSTORE_RELEASE_PATH` / `_USER` / `_PASSWORD`（Godot 官方命名）。
- 用 `${VAR:?中文消息}` fail-fast，**禁止 `set -x`**。只有 `_PASSWORD` 需要 `:?` 守卫（它是唯一必须由人提供、且已写进 `user_setup` 的输入）；`_PATH` / `_USER` 在 `gate-b.sh` 内由 `FIFA_KEYSTORE` / `FIFA_KEYSTORE_ALIAS` 解析出与 `doctor.sh` **逐字相同**的默认值后再前置注入。要求调用者额外导出这两个恒定变量，只会制造一种与构建结果无关的红——而那种红最后一定会被注释掉。
- 提交前自查：`grep -rn "storepass\|keystore_password\|GODOT_ANDROID_KEYSTORE" mobile/` 只允许命中 gate-b.sh 的变量名本身，不允许命中任何值。

来源：RESEARCH §Code Examples 2 注、§Security Domain。

### 9. 「不复制检查逻辑」

`tools/verify_clean_clone.sh:19-20` 定下的原则：一个脚本只做调度与断言，判据只有一处定义。Phase 2 的调用图应当是**单向、无重复**：

```
gate-b.sh  →  gate-a.sh  →  doctor.sh godot
                          →  sync_config.py --check
                          →  godot --import / --check-only / --export-pack
                          →  check_pack.gd / glyph_coverage.gd
gate-b.sh  →  doctor.sh（全五项）→ godot --export-release → apksigner/zipalign/unzip/aapt2
```

`4.7.2.stable` 这个字符串只能出现在 `doctor.sh` 的常量里；gate-a/gate-b 一律通过调用 doctor 来断言。

---

## 设计冲突与假绿风险（planner 必须显式裁决，不要默认）

### 冲突 1：闸门脚本放 `mobile/tools/` 还是仓库 `tools/`？

- `02-VALIDATION.md:22-23,56-58` 明确写 `bash mobile/tools/gate-a.sh`、`mobile/tools/doctor.sh`、`mobile/tools/gate-b.sh`。
- `02-RESEARCH.md:249-251` 的 Recommended Project Structure 写的是仓库根 `tools/android_doctor.sh`、`tools/export_android.sh`。
- 仓库既有惯例（`README.md:24`）把 `tools/` 定义为「仓库级工具」（`sync_config.py` 跨 `shared/`→`mobile/`，正是跨域工具）。

**建议裁决（本文件按此分类）：**

| 文件 | 位置 | 理由 |
|------|------|------|
| `*.gd` 探针 | **必须** `mobile/tools/` | `--script res://tools/...` 要求它在 `res://` 内 |
| `doctor.sh` / `gate-a.sh` / `gate-b.sh` | `mobile/tools/` | VALIDATION 是验证契约，verifier 会按这些路径执行；改路径等于改契约 |
| `make_font_subset.py` | `tools/` | 跨 `shared/` + `desktop/` + `mobile/` 三个子树，与 `sync_config.py` 同构 |

**无论选哪个，都不许两处各放一份。** 如果 planner 决定改路径，必须同步改 `02-VALIDATION.md` 的 Quick run / Full suite command，否则 `/gsd-verify-work` 会照旧路径跑命令然后报「文件不存在」。

### 冲突 2：闸门 A 不能调用 doctor 的全部五项

`doctor.sh` 的五项断言含「导出模板存在」（1.9 GB）与「keystore 可 `keytool -list` 打开」——这两项在**无模板/无设备**的闸门 A 里根本不该要求。若不拆开，闸门 A 就失去了「7 秒、零外部依赖」的全部价值。

**建议裁决：** `doctor.sh` 接受可选的断言名（`godot` / `template` / `jdk` / `sdk` / `keystore`），无参跑全部五项。gate-a 只调 `doctor.sh godot`；gate-b 先跑 `doctor.sh`（全五项）再导出。参数解析用 `verify_clean_clone.sh:26-33` 的 `case` 形状。

### 冲突 3：`−1.000` 里的 `−` 是 U+2212，不在 `required_glyphs.txt` 里 → 假绿

RESEARCH §Code Examples 6 的 `const SYMBOLS := "° ± → ✓ ✗   0°  45°  −1.000"` 里，`−` 是**数学减号 U+2212**，而 `required_glyphs.txt` 的 139 字清单只钉了 `° ± → ✓ ✗` 与中文。

后果：`glyph_coverage.gd` 报 `GLYPH_OK`（清单里没有 `−`），但屏幕上那个位置是豆腐。这正是「清单与使用不同源」的第二种假绿。

**建议裁决（两条都要做）：**

1. 把首屏里的 `−1.000` 改成 ASCII `-1.000`（轴读数的 `%+.3f` 本来就产出 ASCII `+`/`-`，硬编码那行没理由用 U+2212）。
2. `make_font_subset.py` 的字符来源清单里**加入 `mobile/src/smoke/smoke_screen.gd` 本身**（扫所有非 ASCII 字符），让「首屏用到的字」天然进入子集与清单。这样以后有人往场景里加一句中文，字体闸门仍然有效。

### 冲突 4：`check_pack.gd` 的 `EXPECTED_SKILLS = 5` 是重复事实

`shared/skills_config.json` 里已有 5 条动作，`.gd` 里再写一个 5 就是第二份真源。但这**不是**要改成动态读取——动态读取会让断言永远绿。

**建议裁决：** 保留硬编码，但按 `tools/check_desktop.sh:9-11,15` 的体例写注释：「新增动作时必须同步改这个常量并在提交信息里说明；禁止改成『读到几条算几条』」。这与 `BASELINE_SHA256` 的处置完全同构。

### 风险 5：`export_path` 与「相对路径陷阱」

`export_presets.cfg` 里 `export_path="build/fifa-trainer.apk"` 是编辑器用的默认值；脚本一律传绝对路径。**不要为了「统一」把脚本改成相对路径**——RESEARCH P2 是实测失败过的。

---

## No Analog Found

| File | Role | Data Flow | Reason & 替代依据 |
|------|------|-----------|-------------------|
| `mobile/project.godot` | config | config read | 仓库零 Godot 工程文件（Phase 1 D-10 刻意不做）。逐字用 RESEARCH §Code Examples 1。 |
| `mobile/export_presets.cfg` | config | export-time read | 仓库零 `.cfg`。逐字用 RESEARCH §Code Examples 2，keystore 键**一个都不写**。 |
| `mobile/assets/fonts/AppFont.tres` | config (资源) | config read | 仓库零 `.tres`。逐字用 RESEARCH §Code Examples 3。 |
| `mobile/src/smoke/smoke_screen.tscn` | scene | event-driven | 仓库零场景文件。手写 18 行，用 RESEARCH §Code Examples 6 的第二段。 |
| `mobile/src/smoke/smoke_screen.gd` | UI script | event-driven + file-I/O | 仓库零 GDScript。只有**文案**有先例：`desktop/padskills/gui.py:59`。 |
| `mobile/tools/check_pack.gd` | test/gate | file-I/O read | 仓库零 GDScript。契约（收集全部问题 → 逐条 printerr → `quit(1)`）抄 `sync_config.py:107-152`。 |
| `mobile/tools/glyph_coverage.gd` | test/gate | batch/assertion | 同上。`allow_system_fallback = false` 是硬要求（RESEARCH Pattern 3）。 |
| `mobile/assets/fonts/*.ttf`（两份子集） | asset | — | 仓库零二进制资产。产物由 `tools/make_font_subset.py` 生成，**提交进仓库**。 |
| `mobile/assets/fonts/OFL.txt` | doc | — | 仓库零第三方许可证文件。直接用官方 OFL 1.1 全文。 |
| `mobile/icon.svg`（可选） | asset | — | 仓库零 SVG。不提供只打印一条无害 ERROR（RESEARCH §Code Examples 1 要点），**建议本阶段不提供**。 |

> 这 10 条**不是**「可以自由发挥」的意思。RESEARCH 已经给出逐字可用的代码/配置片段（§Code Examples 1–7），planner 应让执行者**直接引用 RESEARCH 的段落号**，而不是让执行者「参考一下自己写」。真正的自由度只在三个地方：节点名、注释措辞、以及冲突 1–4 的裁决。

---

## Metadata

**Analog search scope:** 仓库根（`README.md`、`.gitignore`、`.gitattributes`）、`tools/`（`check_desktop.sh`、`verify_clean_clone.sh`、`sync_config.py`、`collect_checks.py`）、`desktop/build/`（`build_macos.sh`、`build_windows.ps1`）、`desktop/padskills/gui.py`、`desktop/README.md`、`mobile/README.md`、`shared/`、`.github/workflows/`。`.planning/` 与 `.venv/` 未作为 analog 来源（但 `.planning/codebase/CONVENTIONS.md` 被作为**约定**引用）。

**Files scanned:** 17 个源文件（含 `check_desktop.sh` 90 行、`verify_clean_clone.sh` 111 行、`sync_config.py` 182 行、`build_macos.sh` 47 行全量读；`desktop/README.md` 776 行用 grep 定位后定向读 548-607、668-707 两段；`gui.py` 只读 50-79 行 `_ADVICE`；`detectors.py` 只读 63-78 行 `FAILURE_LABELS`；`collect_checks.py` 只读 1-40 行）。

**Tracked-source gate:** 14/14 analog 通过 `git ls-files --error-unmatch` 确认为跟踪文件。本文件不含任何 gitignored 镜像路径。

**Files created/modified in this phase:** 18 新建 + 5 修改 = 23 条；另有 4 条「禁止触碰」路径（`mobile/assets/config/*`、`shared/skills_config.json`、`desktop/pyproject.toml`、`desktop/**`）。

**Pattern extraction date:** 2026-11-04

**Downstream notes for planner:**

1. **闸门顺序不是风格问题**。`gate-a.sh` 的第一条命令必须是 `python3 tools/sync_config.py --check`；`gate-b.sh` 的第一条必须是 `bash mobile/tools/doctor.sh`。把这两条挪到后面，闸门就会变成「对着手改过的副本/对着没装模板的机器」报绿。
2. **`-` 不要写成 `−`**。首屏硬编码的 `−1.000` 用了 U+2212，不在 139 字清单里，会造成「字体闸门绿、屏幕豆腐」的假绿（冲突 3）。
3. **`4.7.2.stable` 只允许出现在 `doctor.sh` 的 `readonly` 常量里**，其它脚本一律调 doctor 断言（Shared Pattern 9）。`--version` 是前缀匹配，不是等号（P8）。
4. **`/=../..` 而不是 `/..`**：`mobile/tools/*.sh` 比 `tools/*.sh` 深一级（Shared Pattern 4）。
5. **`fonttools` 不进 `pyproject.toml`**。`make_font_subset.py` 通过 `uv run --with fonttools pyftsubset` 子进程调用，本体纯 stdlib。
6. **`unzip -l` 的路径是 `assets/assets/...`**（双 `assets`）。把这条写进 gate-b 的注释，否则下一个人会「修」掉它。
7. **三个 Godot 文件（`project.godot` / `export_presets.cfg` / `AppFont.tres`）不要用 `#` 注释**，它们用 `;`。
8. **`.gitignore` 只加三类**（`*.idsig` / `*.keystore` / `*.jks`），**不要**忽略 `*.ttf`——字体子集是提交物。
9. **`mobile/README.md:5` 现在是错的**（「Phase 1 只有配置副本，没有 Godot 工程」），本阶段必须一起改，否则文档与实际相反。
10. **`02-VALIDATION.md` 与 `02-RESEARCH.md` 的脚本路径不一致**（`mobile/tools/*` vs 根 `tools/*`）。选定后同步改 VALIDATION，不能两处各放一份（冲突 1）。
