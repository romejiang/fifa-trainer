#!/usr/bin/env python3
"""tools/sync_config.py 的自测：正常路径 + 五个反例。

每个用例都在 ``tempfile.mkdtemp()`` 里搭一个最小仓库（只有真源），
跑完立刻删除，绝不碰真实仓库里的 ``shared/`` 与两份副本。

反例优先：手改副本、删 ``.sha256``、多塞一份副本、删真源，
四种破坏都必须被 ``--check`` 抓到并指名道姓。
"""

from __future__ import annotations

import hashlib
import io
import shutil
import sys
import tempfile
from pathlib import Path
from typing import Dict, Tuple

sys.path.insert(0, str(Path(__file__).resolve().parent))

from sync_config import (
    SOURCE, TARGETS, check as check_config, find_stray_copies, sidecar, sync,
)

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


# 带中文的固定字节，顺带验证编码路径；脚本本身不解析 JSON，只看字节。
SOURCE_BYTES = '{\n  "note": "同步脚本自测用真源",\n  "skills": []\n}\n'.encode("utf-8")
DIGEST = hashlib.sha256(SOURCE_BYTES).hexdigest()


def make_root(tmp: str) -> Path:
    """搭一个只有真源的最小仓库根。"""
    root = Path(tmp)
    src = root / SOURCE
    src.parent.mkdir(parents=True, exist_ok=True)
    src.write_bytes(SOURCE_BYTES)
    return root


def test_sync_writes_copies() -> None:
    """① 两份副本与真源逐字节相等；② .sha256 是 sha256sum 兼容格式。"""
    tmp = tempfile.mkdtemp(prefix="fifa-sync-")
    try:
        root = make_root(tmp)
        out = io.StringIO()
        rc = sync(root, out)

        check("sync 首次运行返回 0", rc == 0, f"实际 {rc}")
        for rel in TARGETS:
            target = root / rel
            check(f"{rel.as_posix()} 与真源逐字节相等",
                  target.is_file() and target.read_bytes() == SOURCE_BYTES)
            expected = f"{DIGEST}  {target.name}\n"
            side = sidecar(target)
            check(f"{rel.as_posix()}.sha256 内容为「摘要 + 两个空格 + 文件名」",
                  side.is_file() and side.read_text(encoding="utf-8") == expected)
        check("sync 把两份副本的路径都打印出来",
              all(rel.as_posix() in out.getvalue() for rel in TARGETS))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_sync_is_idempotent() -> None:
    """③ 连续 sync 两次，副本与 .sha256 的字节都不变。"""
    tmp = tempfile.mkdtemp(prefix="fifa-sync-")
    try:
        root = make_root(tmp)
        sync(root, io.StringIO())

        snapshot: Dict[str, Tuple[bytes, bytes]] = {}
        for rel in TARGETS:
            target = root / rel
            snapshot[rel.as_posix()] = (
                target.read_bytes(), sidecar(target).read_bytes(),
            )

        out = io.StringIO()
        rc = sync(root, out)
        unchanged = all(
            (root / Path(name)).read_bytes() == pair[0]
            and sidecar(root / Path(name)).read_bytes() == pair[1]
            for name, pair in snapshot.items()
        )
        check("sync 重复运行仍返回 0", rc == 0, f"实际 {rc}")
        check("sync 重复运行不改变副本与 .sha256 的字节", unchanged)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_check_clean() -> None:
    """④ 干净 root 上 check 返回 0 且不打印任何问题。"""
    tmp = tempfile.mkdtemp(prefix="fifa-sync-")
    try:
        root = make_root(tmp)
        sync(root, io.StringIO())
        err = io.StringIO()
        rc = check_config(root, err)
        check("干净 root 上 check 返回 0", rc == 0, f"实际 {rc}")
        check("干净 root 上 check 不打印任何问题", err.getvalue() == "",
              err.getvalue().strip())
        check("干净 root 上没有多余副本", find_stray_copies(root) == [])
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_check_detects_tampered_copy() -> None:
    """⑤ 手改移动端副本后 check 返回 1，并指出该文件。"""
    tmp = tempfile.mkdtemp(prefix="fifa-sync-")
    try:
        root = make_root(tmp)
        sync(root, io.StringIO())
        victim = root / TARGETS[1]
        victim.write_bytes(SOURCE_BYTES + b"\n")

        err = io.StringIO()
        rc = check_config(root, err)
        check("手改副本后 check 返回 1", rc == 1, f"实际 {rc}")
        check("手改副本的报错里含该文件路径",
              TARGETS[1].as_posix() in err.getvalue(), err.getvalue().strip())
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_check_detects_missing_sidecar() -> None:
    """⑥ 删掉 .sha256 后 check 返回 1，并指出 .sha256。"""
    tmp = tempfile.mkdtemp(prefix="fifa-sync-")
    try:
        root = make_root(tmp)
        sync(root, io.StringIO())
        sidecar(root / TARGETS[0]).unlink()

        err = io.StringIO()
        rc = check_config(root, err)
        check("缺 .sha256 后 check 返回 1", rc == 1, f"实际 {rc}")
        check("缺 .sha256 的报错里含 .sha256",
              ".sha256" in err.getvalue(), err.getvalue().strip())
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_check_detects_stray_copy() -> None:
    """⑦ 多塞一份 mobile/skills_config.json 后 check 返回 1 且能被扫描到。"""
    tmp = tempfile.mkdtemp(prefix="fifa-sync-")
    try:
        root = make_root(tmp)
        sync(root, io.StringIO())
        stray = Path("mobile") / "skills_config.json"
        (root / stray).write_bytes(SOURCE_BYTES)

        err = io.StringIO()
        rc = check_config(root, err)
        found = find_stray_copies(root)
        check("多塞副本后 check 返回 1", rc == 1, f"实际 {rc}")
        check("find_stray_copies 找到多余副本", found == [stray], str(found))
        check("多余副本的报错里含该路径",
              stray.as_posix() in err.getvalue(), err.getvalue().strip())
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_check_detects_missing_source() -> None:
    """⑧ 删掉真源后 check 与 sync 都返回 1，报错含「缺少真源」。"""
    tmp = tempfile.mkdtemp(prefix="fifa-sync-")
    try:
        root = make_root(tmp)
        sync(root, io.StringIO())
        (root / SOURCE).unlink()

        err = io.StringIO()
        rc = check_config(root, err)
        check("缺真源后 check 返回 1", rc == 1, f"实际 {rc}")
        check("缺真源的报错里含「缺少真源」",
              "缺少真源" in err.getvalue(), err.getvalue().strip())

        out = io.StringIO()
        rc_sync = sync(root, out)
        check("缺真源后 sync 返回 1", rc_sync == 1, f"实际 {rc_sync}")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_check_reports_all_problems() -> None:
    """⑨ 同时存在两个问题时一次性报告两条，不在第一处中断。"""
    tmp = tempfile.mkdtemp(prefix="fifa-sync-")
    try:
        root = make_root(tmp)
        sync(root, io.StringIO())
        (root / TARGETS[0]).write_bytes(SOURCE_BYTES + b"\n")
        sidecar(root / TARGETS[1]).unlink()

        err = io.StringIO()
        rc = check_config(root, err)
        text = err.getvalue()
        check("同时两处问题时 check 返回 1", rc == 1, f"实际 {rc}")
        check("两处问题的报错都被打印（不中途退出）",
              TARGETS[0].as_posix() in text and ".sha256" in text,
              text.strip().replace("\n", " | "))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main() -> int:
    print("═" * 62)
    print("  配置单一真源 —— 同步脚本自测")
    print("═" * 62)

    test_sync_writes_copies()
    test_sync_is_idempotent()
    test_check_clean()
    test_check_detects_tampered_copy()
    test_check_detects_missing_sidecar()
    test_check_detects_stray_copy()
    test_check_detects_missing_source()
    test_check_reports_all_problems()

    print("\n" + "═" * 62)
    print(f"  通过 {PASS} 项，失败 {FAIL} 项")
    print("═" * 62)
    return 1 if FAIL else 0


if __name__ == "__main__":
    raise SystemExit(main())
