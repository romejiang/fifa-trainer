#!/usr/bin/env python3
"""从桌面版 Python 参考实现重新推导几何黄金夹具。

    python3 tools/gen_geometry_golden.py            # 生成 / 刷新夹具
    python3 tools/gen_geometry_golden.py --check    # 只比对，不写盘

夹具是 GDScript 几何测试的唯一期望来源，所以它必须是**生成物**：手改一份
JSON 让测试变绿，等于把「与 Python 对等」偷换成「与手改后的自己一致」。
``--check`` 重新推导后逐字节比较，不一致就打印首个差异行并返回 1，且绝不写盘。

为什么夹具不放 ``shared/``：它唯一的消费者是 ``mobile/tests/`` 里的 GDScript
套件，Python 侧只是生成器，没有任何运行期读者。放进 ``shared/`` 会逼出第二次
同步（一份给生成器、一份给 Godot），等于给生成物再造一份副本 —— 那正是
Phase 1 用 ``shared/skills_config.json`` 消灭掉的坏模式。

为什么可以安全 import ``padskills.geometry``：该模块只 ``import math``，不碰
pygame，也不需要显示设备；``sys.path`` 以脚本位置为锚注入 ``desktop/``，不依赖
调用方的 cwd。
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_REPO_ROOT / "desktop"))

# 只导入几何模块：它零引擎依赖，是几何行为的唯一规格书。
from padskills.geometry import (  # noqa: E402
    angle_diff,
    angle_of,
    magnitude,
    norm_deg,
    signed_delta,
)

SOURCE_REL = Path("desktop") / "padskills" / "geometry.py"
FIXTURE_REL = Path("mobile") / "tests" / "fixtures" / "geometry_golden.json"

# 九条方向向量：八方向 + 中心。S 是 45° 单位向量，用同一份 math.sqrt 推导，
# 两边都不写字面量 0.7071…，否则夹具会随手抄精度漂移。
_S = 1.0 / math.sqrt(2.0)
ANGLE_CASES = (
    ("center", 0.0, 0.0),
    ("up", 0.0, -1.0),
    ("upright", _S, -_S),
    ("right", 1.0, 0.0),
    ("downright", _S, _S),
    ("down", 0.0, 1.0),
    ("downleft", -_S, _S),
    ("left", -1.0, 0.0),
    ("upleft", -_S, -_S),
)

NORM_DEG_INPUTS = (-90.0, 360.0, -0.0, -1e-12, 720.5)
SIGNED_DELTA_CASES = (
    (0.0, 180.0),
    (0.0, 181.0),
    (350.0, 10.0),
    (10.0, 350.0),
    (270.0, 0.0),
    (0.0, 270.0),
    (45.0, 45.0),
)
ANGLE_DIFF_CASES = (
    (0.0, 180.0),
    (0.0, 90.0),
    (350.0, 10.0),
    (270.0, 0.0),
    (10.0, 350.0),
    (45.0, 45.0),
)


def repo_root() -> Path:
    """仓库根目录：以脚本位置（tools/ 的上一级）为锚，不依赖调用方的 cwd。"""
    return _REPO_ROOT


def fixture_path(root: Path) -> Path:
    return root / FIXTURE_REL


def build_payload(root: Path) -> dict:
    """按 Python 参考实现逐项推导夹具内容（纯计算，不写盘）。"""
    geometry_bytes = (root / SOURCE_REL).read_bytes()
    return {
        "schema_version": 1,
        "source": SOURCE_REL.as_posix(),
        "meta": {"python_geometry_sha256": hashlib.sha256(geometry_bytes).hexdigest()},
        "angle_of": [
            {"name": name, "x": x, "y": y, "expected": angle_of(x, y)}
            for name, x, y in ANGLE_CASES
        ],
        "norm_deg": [
            {"input": value, "expected": norm_deg(value)} for value in NORM_DEG_INPUTS
        ],
        "signed_delta": [
            {"from": a_from, "to": a_to, "expected": signed_delta(a_from, a_to)}
            for a_from, a_to in SIGNED_DELTA_CASES
        ],
        "angle_diff": [
            {"from": a, "to": b, "expected": angle_diff(a, b)} for a, b in ANGLE_DIFF_CASES
        ],
        "magnitude": [
            {"x": x, "y": y, "expected": magnitude(x, y)} for _, x, y in ANGLE_CASES
        ],
    }


def render(root: Path) -> bytes:
    """夹具的规范字节形态：UTF-8、两空格缩进、键排序、结尾一个换行。

    ``sort_keys`` + 固定 indent 保证「同一份实现 → 同一串字节」，``--check``
    才能做逐字节比较而不是语义比较（语义比较会漏掉键顺序与格式漂移）。
    """
    payload = build_payload(root)
    text = json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    return text.encode("utf-8")


def write_if_changed(path: Path, data: bytes) -> bool:
    """内容相同就不落盘：重复运行不产生 diff，也不白改 mtime。"""
    if path.is_file() and path.read_bytes() == data:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return True


def _first_difference(expected: bytes, actual: bytes) -> str:
    """首个差异的行号与上下文：定位用，不把整份夹具刷到终端。"""
    expected_lines = expected.decode("utf-8").splitlines()
    actual_lines = actual.decode("utf-8", errors="replace").splitlines()
    total = max(len(expected_lines), len(actual_lines))
    for index in range(total):
        want = expected_lines[index] if index < len(expected_lines) else "<文件结束>"
        got = actual_lines[index] if index < len(actual_lines) else "<文件结束>"
        if want != got:
            return (
                f"第 {index + 1} 行开始不一致：\n"
                f"  期望（重新推导）: {want}\n"
                f"  实际（磁盘上的夹具）: {got}"
            )
    return "字节不同但逐行内容一致（行尾或编码差异）"


def check(root: Path) -> int:
    """只读校验：重新推导后与磁盘夹具逐字节比较，绝不写盘。"""
    target = fixture_path(root)
    if not target.is_file():
        print(
            f"✗ 缺少几何黄金夹具：{FIXTURE_REL.as_posix()}\n"
            "  运行 python3 tools/gen_geometry_golden.py 生成。",
            file=sys.stderr,
        )
        return 1
    expected = render(root)
    actual = target.read_bytes()
    if expected != actual:
        print(
            f"✗ 夹具与 Python 参考不一致：{FIXTURE_REL.as_posix()}\n"
            f"  {_first_difference(expected, actual)}\n"
            "  夹具是生成物，不能手改；运行 python3 tools/gen_geometry_golden.py "
            "重新生成黄金夹具。",
            file=sys.stderr,
        )
        return 1
    payload = build_payload(root)
    print(
        "✓ 几何黄金夹具与 Python 参考一致"
        f"（angle_of {len(payload['angle_of'])} 条、norm_deg {len(payload['norm_deg'])} 条、"
        f"signed_delta {len(payload['signed_delta'])} 条、angle_diff "
        f"{len(payload['angle_diff'])} 条、magnitude {len(payload['magnitude'])} 条）"
    )
    return 0


def sync(root: Path) -> int:
    """生成夹具；内容没变就只报告「未变」。"""
    target = fixture_path(root)
    changed = write_if_changed(target, render(root))
    marker = "✓" if changed else "·"
    state = "已更新" if changed else "未变"
    print(f"{marker} {FIXTURE_REL.as_posix()} {state}")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="gen_geometry_golden.py",
        description="从 desktop/padskills/geometry.py 推导几何黄金夹具",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "示例:\n"
            "  python3 tools/gen_geometry_golden.py           生成 / 刷新夹具\n"
            "  python3 tools/gen_geometry_golden.py --check   只校验，不写盘\n"
        ),
    )
    parser.add_argument(
        "--check", action="store_true", help="只校验夹具是否等于重新推导的结果，不写任何文件"
    )
    parser.add_argument(
        "--root", default=None, help="仓库根目录（默认按脚本位置推导，仅供自测注入）"
    )
    args = parser.parse_args(argv)

    root = Path(args.root).resolve() if args.root else repo_root()
    if not root.is_dir():
        raise SystemExit(f"仓库根目录不存在: {root}")
    if not (root / SOURCE_REL).is_file():
        raise SystemExit(f"✗ 参考实现不存在：{(root / SOURCE_REL).as_posix()}")
    if args.check:
        return check(root)
    return sync(root)


if __name__ == "__main__":
    raise SystemExit(main())
