#!/usr/bin/env python3
"""Python 侧的坏配置语料判定器：同一份语料，与 GDScript 各判一次。

真源是 ``mobile/tests/fixtures/config_corpus.json``：每条用例带 ``godot`` 与
``python`` 两侧的期望判定，以及一个可选的 ``divergence``（故意分歧的检索名）。
本脚本只负责 Python 侧；GDScript 侧由 ``mobile/tests/unit/test_config_corpus.gd``
在无头闸门里逐条断言。

    职责边界（重要）：

    - 它**不**校验 GDScript 侧，也不重新实现校验规则；规则在
      ``desktop/padskills/config.py`` 里。
    - 它保证 Python 侧的判定与语料记录一致，并且每一处「两侧判定不同」都带
      非空的 ``divergence`` 与 ``python.note``；分歧被修复后记录必须删除，
      否则会误导后来者。
    - ``python: accept`` 的用例还要跑 ``build_detector()``：``start_angle``
      数组这类「parse_config 通过、构造检测器才崩」的晚失败只有这里抓得到。

BOM 必须按 ``load_config`` 的真实路径模拟：``read_text`` 再 ``json.loads(str)``。
**不要**先把文本编码回字节再交给 json.loads —— 那样会按 ``utf-8-sig`` 接受 BOM，
把 Python 侧的基线本身弄错。

本脚本只用标准库加仓库内的 ``desktop/padskills``；导入时不会拉起 pygame
（``padskills.config`` 只依赖 geometry，``padskills.detectors`` 依赖
config/geometry/input_source，而 input_source 的 pygame 导入在函数内部），
所以不需要安装桌面依赖就能跑。

    python3 tools/check_config_parity.py
    python3 tools/check_config_parity.py --root <仓库根>
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

CORPUS_PATH = Path("mobile") / "tests" / "fixtures" / "config_corpus.json"
VERDICTS = ("accept", "reject", "accept_then_detector_reject")


def repo_root() -> Path:
    """仓库根目录：以脚本位置（tools/ 的上一级）为锚，不依赖调用方的 cwd。"""
    return Path(__file__).resolve().parent.parent


_REPO = repo_root()
sys.path.insert(0, str(_REPO / "desktop"))

from padskills.config import parse_config  # noqa: E402
from padskills.detectors import build_detector  # noqa: E402


def _text_for(case: Dict[str, Any]) -> str:
    """把一条用例变成 Python 侧实际会读到的文本。"""
    if "data" in case:
        text = json.dumps(case["data"], ensure_ascii=False)
    elif "text" in case:
        text = str(case["text"])
    else:
        raise ValueError("用例必须提供 data 或 text")
    if case.get("bom"):
        # load_config 用 read_text 读文件，BOM 作为 U+FEFF 留在字符串开头。
        text = "\ufeff" + text
    return text


def python_verdict(case: Dict[str, Any]) -> str:
    """模拟 load_config 的字符路径，再对 accept 用例跑 build_detector。"""
    text = _text_for(case)
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        return "reject"
    try:
        config = parse_config(data)
    except (ValueError, TypeError):
        # TypeError 也要抓：null 数值在 Python 侧抛的是它，不是 ValueError。
        return "reject"
    try:
        for skill in config.skills:
            build_detector(skill)
    except Exception:
        # parse 通过、构造检测器才失败（例如 start_angle 数组）。
        return "accept_then_detector_reject"
    return "accept"


def _load_corpus(root: Path) -> Tuple[Optional[List[Dict[str, Any]]], List[str]]:
    """读语料并做最小结构检查；返回 (cases, problems)。"""
    path = root / CORPUS_PATH
    if not path.is_file():
        return None, [f"PARITY_FAIL 语料不存在: {CORPUS_PATH.as_posix()}"]
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        return None, [
            f"PARITY_FAIL 语料不是合法 JSON: {CORPUS_PATH.as_posix()} "
            f"第 {exc.lineno} 行第 {exc.colno} 列: {exc.msg}"
        ]
    if not isinstance(payload, dict):
        return None, ["PARITY_FAIL 语料根节点必须是对象"]
    if payload.get("schema_version") != 1:
        return None, ["PARITY_FAIL 语料 schema_version 必须是 1"]
    cases = payload.get("cases")
    if not isinstance(cases, list) or not cases:
        return None, ["PARITY_FAIL 语料 cases 必须是非空数组"]
    return cases, []


def check(root: Path, stream=None) -> int:
    """逐用例判定并收集全部问题；不在第一处失败处中断。"""
    err = stream if stream is not None else sys.stderr
    cases, problems = _load_corpus(root)
    if cases is None:
        for line in problems:
            print(line, file=err)
        return 1

    seen_ids: Dict[str, int] = {}
    divergences = 0
    for index, case in enumerate(cases):
        if not isinstance(case, dict):
            problems.append(f"PARITY_FAIL cases[{index}] 必须是对象")
            continue
        case_id = str(case.get("id", ""))
        if not case_id:
            problems.append(f"PARITY_FAIL cases[{index}] 缺少 id")
            continue
        if case_id in seen_ids:
            problems.append(
                f"PARITY_FAIL {case_id}: id 与 cases[{seen_ids[case_id]}] 重复"
            )
            continue
        seen_ids[case_id] = index

        godot = case.get("godot")
        expected = case.get("python")
        if not isinstance(godot, dict) or godot.get("verdict") not in ("accept", "reject"):
            problems.append(f"PARITY_FAIL {case_id}: godot.verdict 必须是 accept / reject")
            continue
        if not isinstance(expected, dict) or expected.get("verdict") not in VERDICTS:
            problems.append(f"PARITY_FAIL {case_id}: python.verdict 必须是 {VERDICTS}")
            continue

        divergence = case.get("divergence", "")
        note = expected.get("note", "")
        if divergence:
            divergences += 1

        try:
            actual = python_verdict(case)
        except Exception as exc:  # 未预期异常属于判定器缺陷，不能算 reject
            problems.append(
                f"PARITY_FAIL {case_id}: 判定时抛出未预期异常 "
                f"{type(exc).__name__}: {exc}"
            )
            continue

        if actual != expected["verdict"]:
            problems.append(
                f"PARITY_FAIL {case_id}: python 实测 {actual}，"
                f"语料记的是 {expected['verdict']}"
            )

        godot_verdict = godot["verdict"]
        if actual != godot_verdict:
            if not divergence:
                problems.append(
                    f"PARITY_FAIL {case_id}: 两侧判定不同却没有 divergence 记录"
                    f"（python={actual}, godot={godot_verdict}）"
                )
            elif not note:
                problems.append(
                    f"PARITY_FAIL {case_id}: divergence 存在但 python.note 为空，"
                    f"读不出为什么"
                )
        elif divergence:
            problems.append(
                f"PARITY_FAIL {case_id}: 两侧判定一致，divergence 记录已过时应删除"
                f"（{divergence}）"
            )

    for line in problems:
        print(line, file=err)
    if problems:
        return 1
    print(f"PARITY_OK cases={len(seen_ids)} divergences={divergences}")
    return 0


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        prog="check_config_parity.py",
        description="校验坏配置语料的 Python 侧判定，以及两侧分歧是否已记录",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "示例:\n"
            "  python3 tools/check_config_parity.py           校验 Python 侧判定\n"
            "  python3 tools/check_config_parity.py --root .  指定仓库根（仅供自测）\n"
        ),
    )
    parser.add_argument("--root", default=None,
                        help="仓库根目录（默认按脚本位置推导，仅供自测注入）")
    args = parser.parse_args(argv)

    root = Path(args.root).resolve() if args.root else repo_root()
    if not root.is_dir():
        raise SystemExit(f"仓库根目录不存在: {root}")
    return check(root)


if __name__ == "__main__":
    raise SystemExit(main())
