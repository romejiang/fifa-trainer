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


def repo_root() -> Path:
    """仓库根目录：以脚本位置（tools/ 的上一级）为锚，不依赖调用方的 cwd。"""
    return Path(__file__).resolve().parent.parent


def sha256(data: bytes) -> str:
    """字节内容的 SHA-256 十六进制摘要。"""
    return hashlib.sha256(data).hexdigest()


def sidecar(path: Path) -> Path:
    """副本旁边的 ``.sha256`` 校验文件路径。"""
    return path.with_name(path.name + SIDECAR_SUFFIX)


def _skipped(rel: Path) -> bool:
    """相对路径里只要有一段命中 _SKIP_DIRS，就整体跳过。"""
    return any(part in _SKIP_DIRS for part in rel.parts)


def find_stray_copies(root: Path) -> List[Path]:
    """找出白名单之外的所有 ``skills_config*.json``（相对路径，已排序）。

    白名单只有三个：真源加两份副本。任何第四份（例如有人手抄一份
    ``mobile/skills_config.json``）都会让"唯一真源"重新变成多真源，
    必须报错而不是默默容忍。
    """
    allowed = {SOURCE}
    allowed.update(TARGETS)
    stray: List[Path] = []
    for path in root.rglob("skills_config*.json"):
        try:
            rel = path.relative_to(root)
        except ValueError:  # 理论上不会发生，保险起见跳过
            continue
        if _skipped(rel) or rel in allowed:
            continue
        stray.append(rel)
    return sorted(stray)


def sync(root: Path, stream: Optional[TextIO] = None) -> int:
    """把真源逐字节写到两份副本，并刷新 ``.sha256``。

    内容相同就不落盘，保证重复运行不产生 diff（也不会白改 mtime）。
    """
    out = stream if stream is not None else sys.stdout
    src = root / SOURCE
    if not src.is_file():
        print(f"✗ 缺少真源 {SOURCE.as_posix()}", file=out)
        return 1

    data = src.read_bytes()
    digest = sha256(data)
    for rel in TARGETS:
        target = root / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        if not target.is_file() or target.read_bytes() != data:
            target.write_bytes(data)
        # 固定写成 sha256sum 兼容格式：「摘要 + 两个空格 + 文件名」，行尾 LF。
        line = f"{digest}  {target.name}\n"
        side = sidecar(target)
        if not side.is_file() or side.read_text(encoding="utf-8") != line:
            side.write_bytes(line.encode("utf-8"))
        print(f"✓ {rel.as_posix()}", file=out)
    return 0


def check(root: Path, stream: Optional[TextIO] = None) -> int:
    """校验副本与真源一致，并确认没有第四份副本。

    先把全部问题收集完再一次性报告，不在第一个错误处中断 —— 出问题时
    开发者想看到的是"一共错了几处"，不是"第一处是什么"。
    """
    err = stream if stream is not None else sys.stderr
    problems: List[str] = []

    src = root / SOURCE
    data: Optional[bytes] = None
    if not src.is_file():
        problems.append(f"✗ 缺少真源 {SOURCE.as_posix()}（唯一可手写的配置源不见了）")
    else:
        data = src.read_bytes()
    digest = sha256(data) if data is not None else ""

    for rel in TARGETS:
        target = root / rel
        if not target.is_file():
            problems.append(
                f"✗ {rel.as_posix()} 不存在（运行 python3 tools/sync_config.py 生成）"
            )
            continue
        if data is not None and target.read_bytes() != data:
            problems.append(
                f"✗ {rel.as_posix()} 与真源不一致（副本只能由脚本生成，不能手改）"
            )
        side = sidecar(target)
        if not side.is_file():
            problems.append(f"✗ {rel.as_posix()}{SIDECAR_SUFFIX} 不存在")
            continue
        fields = side.read_text(encoding="utf-8").split()
        if not fields:
            problems.append(f"✗ {rel.as_posix()}{SIDECAR_SUFFIX} 内容为空")
        elif digest and fields[0] != digest:
            problems.append(f"✗ {rel.as_posix()}{SIDECAR_SUFFIX} 与真源摘要不符")

    for rel in find_stray_copies(root):
        problems.append(
            f"✗ 多余的副本 {rel.as_posix()}（唯一真源是 {SOURCE.as_posix()}）"
        )

    for line in problems:
        print(line, file=err)
    return 1 if problems else 0


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
    parser.add_argument("--check", action="store_true",
                        help="只校验副本与真源是否一致，不写任何文件")
    parser.add_argument("--root", default=None,
                        help="仓库根目录（默认按脚本位置推导，仅供自测注入）")
    args = parser.parse_args(argv)

    root = Path(args.root).resolve() if args.root else repo_root()
    if not root.is_dir():
        raise SystemExit(f"仓库根目录不存在: {root}")

    if args.check:
        return check(root)
    return sync(root)


if __name__ == "__main__":
    raise SystemExit(main())
