#!/usr/bin/env python3
"""从仓库里真实出现的文案抽字符，生成字形清单 + 两个字体子集 + OFL 许可证。

成功标准 2 要求界面上能显示 ``° ± → ✓ ✗`` 与全部中文文案，而 Noto Sans SC
恰好没有 ``✗``（02-RESEARCH §P6）—— 一个字体做不到，必须有符号 fallback。
本脚本把「界面里到底用到哪些字」这件事从人工维护变成机械推导：清单与两个
子集出自同一份字符集、同一次运行，任何一处单独漂移都会被 ``--check`` 或
``mobile/tools/glyph_coverage.gd`` 抓住。

    python3 tools/make_font_subset.py           # 生成 / 刷新三份产物
    python3 tools/make_font_subset.py --check   # 只比对，不写盘

为什么字体工具只作为子进程出现：``fonttools`` 被 Package Legitimacy Audit 判为
SUS，只允许一次性使用（Task 1 已人工放行 4.60.2）。脚本本体保持纯标准库，
``desktop/pyproject.toml`` 与 ``desktop/uv.lock`` 一个字不改；产物提交进仓库后，
构建链路不再需要这个工具。

路径一律以脚本自身位置为锚，所以在任何 cwd 下运行都指向同一个仓库。源字体
默认缓存在 ``$HOME/.cache/fifa-trainer/fonts``，不进仓库；只有裁剪产物入库。
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import urllib.request
from pathlib import Path
from typing import Dict, List, Optional

# 字符来源：整文件扫描所有非 ASCII 字符，不挑行。这样以后往首屏加一句中文，
# 清单与子集自动跟上，不需要有人记得回来改常量。
#   shared/skills_config.json      —— 动作名与 _readme（会直接渲染到练习界面）
#   desktop/padskills/gui.py       —— _ADVICE 里的失败建议文案
#   desktop/padskills/detectors.py —— FAILURE_LABELS 的失败短标签
#   mobile/src/smoke/*             —— 首屏验收面板本身（最长中文串 / 符号 / 轴读数）
#   mobile/src/ui/*                —— 组合根、引导屏、练习屏（由下面的断言自动枚举）
#   mobile/src/core/*              —— S8 / S99 等**会渲染到屏幕**的失败原因（见
#                                     RENDER_SOURCES：这些没有目录级边界，必须点名）
#
# 为什么不登记 config_store.gd / profile_store.gd：它们的 `notice` 与档案提示在
# Phase 4 从未被渲染（`main.gd` 只渲染 `ConfigResult.to_text()` 的 errors/warnings，
# 档案失败只打印错误码）；把不点屏的文件收进来只会让清单无谓膨胀。
CHAR_SOURCES = (
    Path("shared") / "skills_config.json",
    Path("desktop") / "padskills" / "gui.py",
    Path("desktop") / "padskills" / "detectors.py",
    Path("mobile") / "src" / "smoke" / "smoke_screen.gd",
    Path("mobile") / "src" / "smoke" / "smoke_screen.tscn",
    Path("mobile") / "src" / "ui" / "main.gd",
    Path("mobile") / "src" / "ui" / "main.tscn",
    Path("mobile") / "src" / "ui" / "input_setup_screen.gd",
    Path("mobile") / "src" / "ui" / "input_setup_screen.tscn",
    Path("mobile") / "src" / "ui" / "onboarding_screen.gd",
    Path("mobile") / "src" / "ui" / "onboarding_screen.tscn",
    Path("mobile") / "src" / "ui" / "diagnostics_overlay.gd",
    Path("mobile") / "src" / "ui" / "diagnostics_overlay.tscn",
    Path("mobile") / "src" / "ui" / "home_screen.gd",
    Path("mobile") / "src" / "ui" / "home_screen.tscn",
    Path("mobile") / "src" / "ui" / "practice_screen.gd",
    Path("mobile") / "src" / "ui" / "practice_screen.tscn",
    Path("mobile") / "src" / "ui" / "result_banner.gd",
    Path("mobile") / "src" / "core" / "config" / "config_loader.gd",
    Path("mobile") / "src" / "core" / "config" / "config_validator.gd",
    Path("mobile") / "src" / "core" / "config" / "overlay_merge.gd",
    Path("mobile") / "src" / "core" / "device" / "probe_evaluator.gd",
    Path("mobile") / "src" / "core" / "device" / "calibration.gd",
    Path("mobile") / "src" / "core" / "device" / "device_profile.gd",
    Path("mobile") / "src" / "core" / "onboarding_flow.gd",
)

# 渲染源：这些文件的字符串**会直接出现在屏幕上** —— S99 配置错误正文
# （config_loader / config_validator / overlay_merge）、S8 与校准失败原因
# （probe_evaluator / calibration）、复用门与布局建议（device_profile /
# onboarding_flow）。`mobile/src/ui/**` 有目录级的自动枚举，`src/core` 没有
# （里面大量纯逻辑文件永远不渲染），所以这条边只能点名。
#
# 为什么 `--check` 也要查：只查「UI 目录有没有漏登记」时，core 里新加一句会渲染的
# 文案仍然能悄悄漏进子集 —— 屏幕豆腐而闸门全绿。RENDER_SOURCES 让这条边也有牙齿，
# 且只看「是否在 CHAR_SOURCES 里」，不重复扫描字符。
RENDER_SOURCES = (
    Path("mobile") / "src" / "core" / "config" / "config_loader.gd",
    Path("mobile") / "src" / "core" / "config" / "config_validator.gd",
    Path("mobile") / "src" / "core" / "config" / "overlay_merge.gd",
    Path("mobile") / "src" / "core" / "device" / "probe_evaluator.gd",
    Path("mobile") / "src" / "core" / "device" / "calibration.gd",
    Path("mobile") / "src" / "core" / "device" / "device_profile.gd",
    Path("mobile") / "src" / "core" / "onboarding_flow.gd",
)

# 成功标准 2 写死的五个符号。它们不必出现在源文件里，但必须进子集。
EXTRA_SYMBOLS = "°±→✓✗"

# %%+.3f 这类格式产出的 + - . 0-9 必须在子集里；否则轴读数会缺字形。
ASCII_PRINTABLE = "".join(chr(c) for c in range(0x20, 0x7F))

# 换行与空格不是字形：清单是一行一个字符，写进去会被 glyph_coverage.gd
# 当成待检查字符（它跳过这些，但清单本身也不该有）。
_DISCARD = frozenset("\n\r\t ")

FONTS_DIR = Path("mobile") / "assets" / "fonts"
GLYPHS_PATH = FONTS_DIR / "required_glyphs.txt"
SC_SUBSET_PATH = FONTS_DIR / "NotoSansSC-Subset.ttf"
SYM_SUBSET_PATH = FONTS_DIR / "NotoSansSymbols2-Subset.ttf"
OFL_PATH = FONTS_DIR / "OFL.txt"

# 源文件（不进仓库）→ 官方下载地址。三个地址在本次规划中已确认返回 200。
SC_SOURCE_NAME = "NotoSansSC-VF.ttf"
SYM_SOURCE_NAME = "NotoSansSymbols2-Regular.ttf"
OFL_SOURCE_NAME = "OFL.txt"
SOURCE_URLS: Dict[str, str] = {
    SC_SOURCE_NAME: (
        "https://raw.githubusercontent.com/notofonts/noto-cjk/main/"
        "Sans/Variable/TTF/Subset/NotoSansSC-VF.ttf"
    ),
    SYM_SOURCE_NAME: (
        "https://raw.githubusercontent.com/google/fonts/main/"
        "ofl/notosanssymbols2/NotoSansSymbols2-Regular.ttf"
    ),
    OFL_SOURCE_NAME: "https://raw.githubusercontent.com/notofonts/noto-cjk/main/Sans/LICENSE",
}

SOURCE_DIR_DEFAULT = Path.home() / ".cache" / "fifa-trainer" / "fonts"

# 只允许这一个一次性工具版本；不带版本约束的 --with 会让产物随上游漂移。
FONTTOOLS_SPEC = "fonttools==4.60.2"

# --check 打印差异时每段最多列多少个字符：够定位，不会把终端刷满。
_MAX_LISTED = 40


def repo_root() -> Path:
    """仓库根目录：以脚本位置（tools/ 的上一级）为锚，不依赖调用方的 cwd。"""
    return Path(__file__).resolve().parent.parent


def assert_ui_sources_registered(root: Path) -> None:
    """``mobile/src/ui`` 下的每个 ``.gd`` / ``.tscn`` 都必须登记在 CHAR_SOURCES 里。

    为什么需要这条断言：CHAR_SOURCES 是闭世界的硬编码元组。新 UI 文件忘了登记时，
    清单与子集彼此自洽、``glyph_coverage.gd`` 照旧 ``GLYPH_OK``，真机上却是豆腐 ——
    这正是本阶段唯一一处「闸门假绿」。把「忘了登记」变成一条会失败的断言，
    才谈得上闭世界。

    本函数由 ``collect_chars()`` 的第一句调用，所以 ``sync()`` 与 ``--check`` 两条
    路径都必然执行；只挂在 ``sync()`` 里会让 ``--check`` 继续假绿。
    """
    ui_dir = root / "mobile" / "src" / "ui"
    if not ui_dir.is_dir():
        return
    registered = {rel.as_posix() for rel in CHAR_SOURCES}
    missing: List[str] = []
    for path in sorted(ui_dir.rglob("*")):
        if not path.is_file() or path.suffix not in (".gd", ".tscn"):
            continue
        rel = path.relative_to(root).as_posix()
        if rel not in registered:
            missing.append(rel)
    if not missing:
        return
    lines = "\n".join(f"  ✗ {rel}" for rel in missing)
    raise SystemExit(
        "✗ mobile/src/ui 下有未登记进 CHAR_SOURCES 的文件：\n"
        f"{lines}\n"
        "新 UI 文件必须先登记进 CHAR_SOURCES，再运行本脚本重生成清单与子集；"
        "否则字形闸门会在真机豆腐时保持绿色。"
    )


def assert_render_sources_registered(root: Path) -> None:
    """``RENDER_SOURCES`` 里的每个 core 文件都必须在 ``CHAR_SOURCES`` 里。

    为什么需要第二条断言：``assert_ui_sources_registered()`` 只能枚举
    ``mobile/src/ui``；``src/core`` 里没有可枚举的边界（大多数文件永不渲染），
    于是「新增一条会渲染的失败原因却忘了登记」会继续假绿。两条断言一起构成
    闭世界的两条边：目录自动枚举 + 渲染源点名。

    与 UI 断言一样挂在 ``collect_chars()`` 的第一句，所以 ``sync`` 与 ``--check``
    两条路径都必然执行。
    """
    registered = {rel.as_posix() for rel in CHAR_SOURCES}
    missing = [rel.as_posix() for rel in RENDER_SOURCES if rel.as_posix() not in registered]
    if not missing:
        return
    lines = "\n".join(f"  ✗ {rel}" for rel in missing)
    raise SystemExit(
        "✗ 有会渲染到屏幕的 core 文件未登记进 CHAR_SOURCES：\n"
        f"{lines}\n"
        "把这些文件追加进 CHAR_SOURCES（并加入 RENDER_SOURCES），再运行本脚本重生成；"
        "否则屏幕上的失败原因会在真机上缺字，而字形闸门仍然报绿。"
    )


def collect_chars(root: Path) -> List[str]:
    """从全部字符来源里推导必需字符集（按码点排序、去重）。

    缺任何一个来源都直接报错：悄悄少扫一个文件，清单就会少字，而闸门对着
    少字的清单照样报绿 —— 那正是本脚本存在的原因。
    """
    # 先证明闭世界没有缺口，再谈扫描：未登记的 UI 文件或渲染源会让清单少字。
    assert_ui_sources_registered(root)
    assert_render_sources_registered(root)
    chars = set(EXTRA_SYMBOLS)
    chars.update(ASCII_PRINTABLE)
    for rel in CHAR_SOURCES:
        path = root / rel
        if not path.is_file():
            raise SystemExit(f"✗ 字符来源不存在：{rel.as_posix()}")
        for ch in path.read_text(encoding="utf-8"):
            if ord(ch) >= 0x80:
                chars.add(ch)
    chars.difference_update(_DISCARD)
    return sorted(chars)


def render_glyphs(chars: List[str]) -> bytes:
    """清单的字节形态：一行一个字符、LF 行尾、无表头。"""
    return "".join(ch + "\n" for ch in chars).encode("utf-8")


def write_if_changed(path: Path, data: bytes) -> bool:
    """内容相同就不落盘：重复运行不产生 diff，也不白改 mtime。"""
    if path.is_file() and path.read_bytes() == data:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return True


def download(url: str, dest: Path) -> None:
    """把官方源文件下载到缓存目录，打印字节数（源字体不进仓库）。"""
    dest.parent.mkdir(parents=True, exist_ok=True)
    print(f"▸ 下载 {url}")
    request = urllib.request.Request(url, headers={"User-Agent": "fifa-trainer-font-subset"})
    with urllib.request.urlopen(request, timeout=300) as response:
        data = response.read()
    dest.write_bytes(data)
    print(f"  已保存 {dest}（{len(data)} 字节）")


def ensure_source(dest: Path) -> None:
    """源文件缺失时才下载；已缓存则直接复用。"""
    if not dest.is_file() or dest.stat().st_size == 0:
        download(SOURCE_URLS[dest.name], dest)


def run_pyftsubset(root: Path, source: Path, glyphs: Path, target: Path) -> bool:
    """用一次性 fonttools 子进程裁一个子集；字节相同则不落盘。

    先写到 ``<target>.tmp`` 再比较：pyftsubset 只会写文件，不给我们「先在内存
    里看一眼」的机会。临时文件放在目标目录里，避免跨文件系统 rename。
    """
    tmp = target.with_name(target.name + ".tmp")
    command = [
        "uv", "run", "--with", FONTTOOLS_SPEC, "pyftsubset",
        str(source),
        f"--text-file={glyphs}",
        f"--output-file={tmp}",
        "--layout-features=*",
        "--drop-tables+=DSIG",
    ]
    try:
        subprocess.run(command, check=True, cwd=str(root))
        data = tmp.read_bytes()
        if target.is_file() and target.read_bytes() == data:
            return False
        target.parent.mkdir(parents=True, exist_ok=True)
        os.replace(tmp, target)
        return True
    except FileNotFoundError as exc:
        raise SystemExit("✗ 找不到 uv：字体裁剪依赖 uv run --with " + FONTTOOLS_SPEC) from exc
    except subprocess.CalledProcessError as exc:
        raise SystemExit(f"✗ 字体裁剪失败（退出码 {exc.returncode}）：{' '.join(command)}") from exc
    finally:
        if tmp.exists():
            tmp.unlink()


def sync_license(root: Path, source_dir: Path) -> bool:
    """把 OFL 许可证原样写进仓库；内容是空壳就报错，不静默写空文件。"""
    source = source_dir / OFL_SOURCE_NAME
    ensure_source(source)
    text = source.read_text(encoding="utf-8", errors="replace")
    if "SIL OPEN FONT LICENSE" not in text:
        raise SystemExit(f"✗ {source} 不含 'SIL OPEN FONT LICENSE'，拒绝写入空壳许可证")
    return write_if_changed(root / OFL_PATH, source.read_bytes())


def sync(root: Path, source_dir: Path) -> int:
    """生成三份产物：字符清单、两个子集、许可证。"""
    chars = collect_chars(root)
    changed = write_if_changed(root / GLYPHS_PATH, render_glyphs(chars))
    print(f"{'✓' if changed else '·'} {GLYPHS_PATH.as_posix()}（{len(chars)} 个字符）")

    for name in (SC_SOURCE_NAME, SYM_SOURCE_NAME):
        ensure_source(source_dir / name)

    glyphs_file = root / GLYPHS_PATH
    for source_name, target_rel in (
        (SC_SOURCE_NAME, SC_SUBSET_PATH),
        (SYM_SOURCE_NAME, SYM_SUBSET_PATH),
    ):
        changed = run_pyftsubset(root, source_dir / source_name, glyphs_file, root / target_rel)
        print(f"{'✓' if changed else '·'} {target_rel.as_posix()}")

    changed = sync_license(root, source_dir)
    print(f"{'✓' if changed else '·'} {OFL_PATH.as_posix()}")
    return 0


def check(root: Path) -> int:
    """只读校验：清单必须等于从源文件重新推导的结果，两个子集必须存在。

    为什么清单与子集必须同源：清单被手改而子集没重裁时，字形闸门会对着
    「自己生成的清单」报绿，而屏幕上依然豆腐 —— 这是本仓库第二次出现同构的
    假绿风险（第一次在 ``tools/check_desktop.sh`` 的配置校验）。另外，源文件里
    新加一个汉字而清单没重生成时，清单与子集仍然彼此自洽，只有这里能抓住。

    ``--check`` 绝不调用子进程、绝不写盘：它要能在闸门里毫秒级反复跑。
    """
    problems: List[str] = []

    derived = set(collect_chars(root))
    glyphs_file = root / GLYPHS_PATH
    if not glyphs_file.is_file():
        problems.append(
            f"✗ 缺少 {GLYPHS_PATH.as_posix()}（运行 python3 tools/make_font_subset.py 生成）"
        )
    else:
        actual_text = glyphs_file.read_text(encoding="utf-8")
        actual = {ch for ch in actual_text if ch not in _DISCARD}
        not_in_manifest = sorted(derived - actual)
        not_in_sources = sorted(actual - derived)
        if not_in_manifest:
            problems.append(
                "✗ 清单少了 %d 个源文件里出现的字符（运行 python3 tools/make_font_subset.py "
                "重新生成）：%s" % (len(not_in_manifest), _preview(not_in_manifest))
            )
        if not_in_sources:
            problems.append(
                "✗ 清单多了 %d 个源文件里没有的字符（清单是生成物，不能手改）：%s"
                % (len(not_in_sources), _preview(not_in_sources))
            )
        if not not_in_manifest and not not_in_sources and actual_text != render_glyphs(
            sorted(derived)
        ).decode("utf-8"):
            problems.append("✗ 清单的字符集合正确，但行序或格式与生成结果不一致（不能手改）")

    for rel in (SC_SUBSET_PATH, SYM_SUBSET_PATH):
        path = root / rel
        if not path.is_file():
            problems.append(f"✗ 缺少 {rel.as_posix()}（运行 python3 tools/make_font_subset.py 生成）")
        elif path.stat().st_size == 0:
            problems.append(f"✗ {rel.as_posix()} 是空文件")

    if problems:
        for line in problems:
            print(line, file=sys.stderr)
        return 1
    print(f"✓ 字形清单与源文件一致（{len(derived)} 个字符），两个子集均已生成")
    return 0


def _preview(chars: List[str]) -> str:
    """差异字符的可读预览：最多列 _MAX_LISTED 个，余下折算成「还有 N 个」。"""
    shown = "".join(chars[:_MAX_LISTED])
    if len(chars) <= _MAX_LISTED:
        return shown
    return f"{shown} …（还有 {len(chars) - _MAX_LISTED} 个）"


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        prog="make_font_subset.py",
        description="从仓库源文件抽字符 → 生成字形清单 + 两个字体子集 + OFL 许可证",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "示例:\n"
            "  python3 tools/make_font_subset.py           生成 / 刷新三份产物\n"
            "  python3 tools/make_font_subset.py --check   只校验，不写盘\n"
        ),
    )
    parser.add_argument("--check", action="store_true",
                        help="只校验清单与子集是否一致，不写任何文件")
    parser.add_argument("--source-dir", default=None,
                        help=f"源字体缓存目录（默认 {SOURCE_DIR_DEFAULT}）")
    parser.add_argument("--root", default=None,
                        help="仓库根目录（默认按脚本位置推导，仅供自测注入）")
    args = parser.parse_args(argv)

    root = Path(args.root).resolve() if args.root else repo_root()
    if not root.is_dir():
        raise SystemExit(f"仓库根目录不存在: {root}")
    if args.check:
        return check(root)
    source_dir = (
        Path(args.source_dir).expanduser() if args.source_dir else SOURCE_DIR_DEFAULT
    )
    return sync(root, source_dir)


if __name__ == "__main__":
    raise SystemExit(main())
