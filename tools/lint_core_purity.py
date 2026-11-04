#!/usr/bin/env python3
"""扫描 ``mobile/src/core``，把「零引擎依赖」变成一台可执行的机器。

``src/core/**`` 不得读取任何环境状态（时钟、输入、OS、配置单例）、不得做 I/O、
不得持有或构造场景树类型、不得写日志或错误通道。所有输入以参数传入，所有输出
以返回值传出。``JSON`` 与 ``RegEx`` 是唯一允许的引擎类：它们是纯解析器，没有
I/O，也没有环境状态。完整定义见 ``mobile/docs/CORE.md``。

    python3 tools/lint_core_purity.py                  # 扫描 mobile/src/core
    python3 tools/lint_core_purity.py <目录>            # 扫描指定目录
    python3 tools/lint_core_purity.py --list-rules     # 只列规则 id（供文档互锁）

退出码：

    0  没有命中，打印 ``LINT_OK files=N``（正向哨兵，与 ``PACK_OK`` / ``GLYPH_OK`` 同文化）
    1  有命中，逐条打印 ``相对路径:行号: 规则: 片段`` 到 stdout
    2  目标不存在，或目录里一个 ``.gd`` 都没有，打印 ``LINT_INVALID ...`` 到 stderr

为什么「扫不到」必须与「干净」分开：目标路径写错时扫到 0 个文件，若返回 0
就等于自动通过 —— 那是最容易被后门化的一档，所以单独用 2 表示「这不是一次
有效运行」。

实现分两级：先用状态机把注释与字符串替换成空格（保留换行与列位置），再对剥离
后的文本按行匹配规则。中文文档字符串里解释「为什么不能用 ``FileAccess``」、
错误消息里写着 ``Node``，都不会误报；报错行号也仍指向真实行。

已知漏报（记录，不追求完美）：用行继续符把 token 拆开、``ClassDB.instantiate("Node")``、
``call("print")``、``preload`` 路径用变量拼接。本工具的目标是挡住无意识引入，
不是对抗恶意代码。``outer_layer_dep`` 需要看到字符串字面量，因此该规则对
「只剥注释、保留字符串」的文本匹配；代价是错误消息里逐字写出
``preload("res://src/app/...")`` 会被误报 —— 本仓库没有这种写法，若出现请改写
消息措辞，而不是删规则。
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from typing import List, Optional, Tuple

DEFAULT_TARGET = Path("mobile") / "src" / "core"

# 顺序即契约：前五条是 INFRA-03 的硬集合，不可删、不可重排。``--list-rules``
# 的前五行由自测断言，文档与历史的对应关系都按这个顺序。
RULES: List[Tuple[str, re.Pattern[str]]] = [
    ("input_singleton", re.compile(r"\bInput\s*\.")),
    ("time_singleton", re.compile(r"\bTime\s*\.")),
    ("node_type", re.compile(r"\bNode\b")),
    ("fileaccess_io", re.compile(r"\bFileAccess\b")),
    ("logging", re.compile(
        r"\b(?:print|prints|printt|printerr|print_rich|print_debug|push_error|push_warning)\s*\(")),
    ("os_singleton", re.compile(r"\bOS\s*\.")),
    ("engine_singleton", re.compile(r"\bEngine\s*\.")),
    ("display_server", re.compile(r"\bDisplayServer\b")),
    ("tree_access", re.compile(r"\bget_tree\s*\(")),
    ("scene_tree_type", re.compile(r"\bSceneTree\b")),
    ("resource_loader", re.compile(r"\bResourceLoader\b")),
    ("resource_type", re.compile(r"\bResource\b")),
    ("tool_annotation", re.compile(r"^\s*@tool\b")),
    ("outer_layer_dep", re.compile(
        r"(?:preload|load)\s*\(\s*\"res://src/(?:platform|ui|app)/")),
]

# 这些规则必须看到字符串字面量的内容，所以对 strip_comments() 的结果匹配。
_STRING_AWARE = frozenset({"outer_layer_dep"})

# 扫描时整体跳过的目录名：Godot 导入缓存与导出产物都不是源码。
_SKIP_DIRS = frozenset({".godot", "build"})


def repo_root() -> Path:
    """仓库根目录：以脚本位置（tools/ 的上一级）为锚，不依赖调用方的 cwd。"""
    return Path(__file__).resolve().parent.parent


def _mask(text: str, drop_strings: bool) -> str:
    """逐字符状态机：注释永远剥掉；字符串按 drop_strings 决定剥掉还是保留内容。

    换行原样输出，其它被剥掉的字符输出等宽空格，因此行号与列号仍指向真实位置。
    三引号形式用 ``text.startswith(delim * 3, i)`` 判定；``\\`` 转义连转义字符
    一起吃掉两个字符。
    """
    out: List[str] = []
    i = 0
    n = len(text)
    while i < n:
        ch = text[i]
        if ch == "#":                                  # 行注释
            while i < n and text[i] != "\n":
                out.append(" ")
                i += 1
            continue
        if ch in ('"', "'"):                           # 普通 / 三引号 / raw / StringName / NodePath
            delim = ch
            triple = text.startswith(delim * 3, i)
            width = 3 if triple else 1
            opener = delim * width
            out.append(" " * width if drop_strings else opener)
            i += width
            while i < n:
                if text.startswith(delim * width, i):
                    out.append(" " * width if drop_strings else opener)
                    i += width
                    break
                if text[i] == "\\" and i + 1 < n:
                    if drop_strings:
                        out.append("  ")
                    else:
                        out.append(text[i:i + 2])
                    i += 2
                    continue
                if drop_strings:
                    out.append("\n" if text[i] == "\n" else " ")
                else:
                    out.append(text[i])
                i += 1
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def strip_code(text: str) -> str:
    """把注释与字符串替换成空格，保留换行与列位置。"""
    return _mask(text, drop_strings=True)


def strip_comments(text: str) -> str:
    """只把注释替换成空格，保留字符串内容（供依赖路径字面量的规则使用）。"""
    return _mask(text, drop_strings=False)


def scan_text(text: str) -> List[Tuple[int, str, str]]:
    """返回 ``(行号, 规则 id, 命中片段)``；行号从 1 开始，按行优先稳定排序。"""
    code_lines = strip_code(text).split("\n")
    raw_lines = strip_comments(text).split("\n")
    hits: List[Tuple[int, str, str]] = []
    for index, code_line in enumerate(code_lines):
        for rule, pattern in RULES:
            line = raw_lines[index] if rule in _STRING_AWARE else code_line
            match = pattern.search(line)
            if match is None:
                continue
            hits.append((index + 1, rule, match.group(0).strip()))
    return hits


def iter_gd_files(target: Path) -> List[Path]:
    """收集目标下所有 ``.gd``，跳过 ``.godot/`` 与 ``build/``，按相对路径稳定排序。"""
    files: List[Path] = []
    for path in target.rglob("*.gd"):
        try:
            rel = path.relative_to(target)
        except ValueError:  # 理论上不会发生，保险起见跳过
            continue
        if any(part in _SKIP_DIRS for part in rel.parts):
            continue
        files.append(path)
    return sorted(files, key=lambda p: p.relative_to(target).as_posix())


def display_path(path: Path, root: Path) -> str:
    """仓库内文件打印仓库相对路径；仓库外的临时 canary 打印绝对路径。"""
    try:
        return path.relative_to(root).as_posix()
    except ValueError:
        return path.as_posix()


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        prog="lint_core_purity.py",
        description="扫描 GDScript：先剥离注释与字符串，再匹配零引擎依赖规则",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "示例:\n"
            "  python3 tools/lint_core_purity.py                  扫描 mobile/src/core\n"
            "  python3 tools/lint_core_purity.py mobile/src/core   显式指定目标\n"
            "  python3 tools/lint_core_purity.py --list-rules      只列规则 id\n"
        ),
    )
    parser.add_argument(
        "target", nargs="?", default=None,
        help="要扫描的目录（默认 mobile/src/core；相对路径按仓库根解析）")
    parser.add_argument(
        "--list-rules", action="store_true",
        help="逐行打印规则 id 后退出 0，供文档与自测互锁")
    parser.add_argument(
        "--repo-root", default=None,
        help="仓库根目录（默认按脚本位置推导，仅供自测注入）")
    args = parser.parse_args(argv)

    if args.list_rules:
        for rule, _ in RULES:
            print(rule)
        return 0

    root = Path(args.repo_root).resolve() if args.repo_root else repo_root()
    if not root.is_dir():
        print(f"LINT_INVALID 仓库根目录不存在: {root}", file=sys.stderr)
        return 2

    target = Path(args.target) if args.target is not None else DEFAULT_TARGET
    if not target.is_absolute():
        target = root / target
    target = target.resolve()

    if not target.is_dir():
        print(f"LINT_INVALID 目标目录不存在: {target}", file=sys.stderr)
        return 2

    files = iter_gd_files(target)
    if not files:
        print(f"LINT_INVALID 目录里没有任何 .gd 文件: {target}", file=sys.stderr)
        return 2

    found = 0
    for path in files:
        text = path.read_text(encoding="utf-8", errors="replace")
        for line_no, rule, token in scan_text(text):
            print(f"{display_path(path, root)}:{line_no}: {rule}: {token}")
            found += 1
    if found:
        return 1
    print(f"LINT_OK files={len(files)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
