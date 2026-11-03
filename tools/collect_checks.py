#!/usr/bin/env python3
"""从自建 check() 的测试脚本里收集检查项名称。

把测试模块里的 ``check()`` 临时换成记录器，再调用同模块的 ``main()``，
所以 PASS/FAIL 计数与彩色输出照常发生；名称直接写进 ``--out`` 指定的 TSV。
不解析 stdout —— 那里有 ANSI 颜色码、locale 编码和运行时测量值三重不确定。
"""

from __future__ import annotations

import argparse
import importlib.util
import sys
from pathlib import Path
from typing import List, Optional


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        prog="collect_checks.py",
        description="在进程内运行测试脚本，导出每次 check() 的检查项名称",
    )
    parser.add_argument("test_script", help="要运行的测试脚本路径")
    parser.add_argument("--out", required=True,
                        help="输出 TSV 路径（每行：测试文件名 TAB 检查项名称）")
    args = parser.parse_args(argv)

    # 先绝对化：后面写文件、拼模块名都用它，不依赖调用方的 cwd。
    path = Path(args.test_script).resolve()
    spec = importlib.util.spec_from_file_location(f"_collect_{path.stem}", path)
    mod = importlib.util.module_from_spec(spec)
    # tests/ 不是包，只能按文件加载；先注册再执行，模块内部才拿得到自己。
    sys.modules[spec.name] = mod
    spec.loader.exec_module(mod)

    names: List[str] = []
    original = mod.check

    def recording_check(label: str, ok: bool, extra: str = "",
                        *rest: object, **kwargs: object) -> None:
        """记录名称后原样转交，测试自身的统计与输出一字不改。"""
        names.append(label)
        return original(label, ok, extra, *rest, **kwargs)

    mod.check = recording_check
    try:
        rc = mod.main()
    finally:
        # 即使 main() 半途抛异常也落盘，已收集到的名称可用于定位断点。
        Path(args.out).write_text(
            "".join(f"{path.name}\t{name}\n" for name in names),
            encoding="utf-8",
        )
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
