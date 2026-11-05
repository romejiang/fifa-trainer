#!/usr/bin/env python3
"""从桌面版 Python 参考实现重新推导 tap 检测器黄金夹具。

    python3 tools/gen_tap_golden.py            # 生成 / 刷新夹具
    python3 tools/gen_tap_golden.py --check    # 只比对，不写盘

夹具是 GDScript tap 回放套件的唯一期望来源，所以它必须是**生成物**：手改一份
JSON 让测试变绿，等于把「与 Python 对等」偷换成「与手改后的自己一致」。
``--check`` 重新推导后逐字节比较，不一致就打印首个差异行并返回 1，且绝不写盘。

为什么期望值必须跑参考实现：``desktop/padskills/detectors.py`` 的 ``TapDetector``
是唯一规格书；生成器只负责把 250 Hz 时间轴喂给它，记录每一次 ``Hit`` 与每一次
``pop_failure()``。任何「我以为是 450ms」的手写期望都可能与实现的取整、边界、
分支顺序不符。

为什么引擎分支也要照抄：修饰键不满足时，引擎调用 ``observe()`` **然后**
``reset()``（desktop/padskills/engine.py:273-279）；顺序反了 ``reset()`` 就会用
上一帧的按键状态算 elapsed，``hold_short`` 的实测值会与移动端分叉。

为什么可以安全 import ``padskills.detectors``：``input_source.py`` 的 pygame 是
函数内导入，模块级只依赖标准库；``sys.path`` 以脚本位置为锚注入 ``desktop/``，
不依赖调用方的 cwd。
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_REPO_ROOT / "desktop"))

from padskills.config import parse_config  # noqa: E402
from padskills.detectors import Frame, TapDetector  # noqa: E402
from padskills.input_source import PadState, canonical_button  # noqa: E402

STEP_MS = 4
HZ = 250
SKILL_NAME = "绿色搓射 Green Finesse"

CONFIG_REL = Path("shared") / "skills_config.json"
FIXTURE_REL = Path("mobile") / "tests" / "fixtures" / "tap_golden.json"

# 四个摘要一起进夹具：detectors 是本文件的规格书，engine 是 04-02 运行时期望的来源，
# config 决定 Skill 字段，skills_config 是真源。任何一份变了都必须重新生成夹具。
SOURCE_RELS = {
    "detectors": Path("desktop") / "padskills" / "detectors.py",
    "engine": Path("desktop") / "padskills" / "engine.py",
    "config": Path("desktop") / "padskills" / "config.py",
    "skills_config": CONFIG_REL,
}

# 时间轴用「变化点 + 结束时刻」描述：每个变化点都落在 4ms 网格上，其余帧由
# _build_frames 全量展开。按键集合在这里写清楚，拼字符串时统一 sorted()。
#
# 窗口边界（min/max 两端包含）必须各有一条用例；超时是严格大于，所以
# det_too_slow_boundary_750 的尾巴停在 interval=748 —— 4ms 网格上取不到 750，
# 而 752 那条由 det_too_slow_no_second 证明「超过才报」。
#
# 同理，4ms 网格上的间隔只能是 4 的整数倍，取不到计划里写的 450：
# det_success_mid_450 / det_set_modifier_rt_success 用网格内最近的 448（t0=100,
# 第二下 548）。id 保留计划里的名字以便追溯，语义仍是「窗口内部的成功」。
CASES = (
    # 1. 窗口下端包含：第二下正好 400ms。
    {
        "id": "det_success_min_400",
        "modifier": "RB",
        "button": "X",
        "end_ms": 508,
        "changes": (
            (0, ()),
            (4, ("RB",)),
            (100, ("RB", "X")),
            (104, ("RB",)),
            (500, ("RB", "X")),
            (504, ("RB",)),
        ),
    },
    # 2. 窗口内部的成功（计划写 450，网格上取 448）。
    {
        "id": "det_success_mid_450",
        "modifier": "RB",
        "button": "X",
        "end_ms": 560,
        "changes": (
            (0, ()),
            (4, ("RB",)),
            (100, ("RB", "X")),
            (104, ("RB",)),
            (548, ("RB", "X")),
            (552, ("RB",)),
        ),
    },
    # 3. 窗口上端包含：第二下正好 600ms。
    {
        "id": "det_success_max_600",
        "modifier": "RB",
        "button": "X",
        "end_ms": 708,
        "changes": (
            (0, ()),
            (4, ("RB",)),
            (100, ("RB", "X")),
            (104, ("RB",)),
            (700, ("RB", "X")),
            (704, ("RB",)),
        ),
    },
    # 4. 比窗口下限快：too_fast。
    {
        "id": "det_too_fast_300",
        "modifier": "RB",
        "button": "X",
        "end_ms": 408,
        "changes": (
            (0, ()),
            (4, ("RB",)),
            (100, ("RB", "X")),
            (104, ("RB",)),
            (400, ("RB", "X")),
            (404, ("RB",)),
        ),
    },
    # 5. 第二下存在但太慢：走 rising 的 too_slow 分支，不是超时分支。
    {
        "id": "det_too_slow_second_700",
        "modifier": "RB",
        "button": "X",
        "end_ms": 808,
        "changes": (
            (0, ()),
            (4, ("RB",)),
            (100, ("RB", "X")),
            (104, ("RB",)),
            (800, ("RB", "X")),
            (804, ("RB",)),
        ),
    },
    # 6. 一直没有第二下：首个 interval > 750 的帧是 852（752ms）。
    {
        "id": "det_too_slow_no_second",
        "modifier": "RB",
        "button": "X",
        "end_ms": 900,
        "changes": (
            (0, ()),
            (4, ("RB",)),
            (100, ("RB", "X")),
            (104, ("RB",)),
        ),
    },
    # 7. 超时边界：尾巴停在 interval=748（网格上取不到 750），不报任何失败。
    {
        "id": "det_too_slow_boundary_750",
        "modifier": "RB",
        "button": "X",
        "end_ms": 848,
        "changes": (
            (0, ()),
            (4, ("RB",)),
            (100, ("RB", "X")),
            (104, ("RB",)),
        ),
    },
    # 8. 修饰键中途松开：hold_short 由 reset() 产出，elapsed 用上一帧的 _now。
    {
        "id": "det_hold_short_modifier_released",
        "modifier": "RB",
        "button": "X",
        "end_ms": 308,
        "changes": (
            (0, ()),
            (4, ("RB",)),
            (100, ("RB", "X")),
            (300, ("X",)),
        ),
    },
    # 9. 第一下按 RB，随后换 RT 再按第二下：RB 撤离触发 hold_short，不产 Hit。
    {
        "id": "det_modifier_switch_rb_to_rt",
        "modifier": "RB",
        "button": "X",
        "end_ms": 608,
        "changes": (
            (0, ()),
            (4, ("RB",)),
            (100, ("RB", "X")),
            (300, ("X",)),
            (304, ("RT", "X")),
            (500, ("RT",)),
            (604, ("RT", "X")),
        ),
    },
    # 10. set_modifier("RT") 在首帧之前调用：证明换修饰键后判定跟着换。
    {
        "id": "det_set_modifier_rt_success",
        "set_modifier": "RT",
        "modifier": "RB",
        "button": "X",
        "end_ms": 560,
        "changes": (
            (0, ()),
            (4, ("RT",)),
            (100, ("RT", "X")),
            (104, ("RT",)),
            (548, ("RT", "X")),
            (552, ("RT",)),
        ),
    },
    # 11. 首帧 X 已按住，之后才按 RB：observe 守卫让「一直按着」不算 rising。
    {
        "id": "det_first_frame_held_x",
        "modifier": "RB",
        "button": "X",
        "end_ms": 200,
        "changes": (
            (0, ("X",)),
            (100, ("RB", "X")),
        ),
    },
    # 12. 命中后 40ms 再按被 _armed 挡住；松开满 120ms 后重新起手，第二段再 Hit。
    {
        "id": "det_release_hold_gate",
        "modifier": "RB",
        "button": "X",
        "end_ms": 1104,
        "changes": (
            (0, ()),
            (4, ("RB",)),
            (100, ("RB", "X")),
            (104, ("RB",)),
            (500, ("RB", "X")),
            (504, ("RB",)),
            (540, ("RB", "X")),
            (544, ("RB",)),
            (700, ("RB", "X")),
            (704, ("RB",)),
            (1100, ("RB", "X")),
            (1104, ("RB",)),
        ),
    },
)


def repo_root() -> Path:
    """仓库根目录：以脚本位置（tools/ 的上一级）为锚，不依赖调用方的 cwd。"""
    return _REPO_ROOT


def fixture_path(root: Path) -> Path:
    return root / FIXTURE_REL


def _sha256(root: Path, rel: Path) -> str:
    return hashlib.sha256((root / rel).read_bytes()).hexdigest()


def _load_skill(root: Path):
    """从唯一真源加载绿色搓射：不写第二份配置副本。"""
    data = json.loads((root / CONFIG_REL).read_text(encoding="utf-8"))
    cfg = parse_config(data, root / CONFIG_REL)
    for skill in cfg.skills:
        if skill.name == SKILL_NAME:
            return skill
    raise SystemExit(f"✗ 配置里找不到动作 {SKILL_NAME!r}：{CONFIG_REL.as_posix()}")


def _build_frames(case: dict) -> list:
    """把变化点展开成逐帧全量时间轴（步长 4ms，t_ms 用 int）。"""
    case_id = case["id"]
    end_ms = int(case["end_ms"])
    if end_ms % STEP_MS:
        raise SystemExit(f"✗ {case_id}: end_ms 必须是 {STEP_MS}ms 的整数倍")
    changes = list(case["changes"])
    for t_ms, _ in changes:
        if int(t_ms) % STEP_MS:
            raise SystemExit(f"✗ {case_id}: 变化点 {t_ms} 不在 {STEP_MS}ms 网格上")

    frames = []
    state: tuple = ()
    index = 0
    for t_ms in range(0, end_ms + 1, STEP_MS):
        while index < len(changes) and int(changes[index][0]) == t_ms:
            state = tuple(sorted(changes[index][1]))
            index += 1
        frames.append([t_ms, "+".join(state)])
    if index != len(changes):
        raise SystemExit(f"✗ {case_id}: 有变化点晚于 end_ms")
    return frames


def _normalize_elapsed_ms(value: float, case_id: str, what: str) -> float:
    """把浮点噪声归一成毫秒整数，并拒绝真正的非整数。

    250 Hz 网格上所有时长都应是 4ms 的整数倍，但 ``(t2/1000 - t1/1000) * 1000``
    会带 1e-13 量级的二进制误差（450 会算成 450.00000000000006）。判据必须是
    「与最近整数相差不超过 1e-6」而不是 ``float.is_integer()``，否则生成器会
    因浮点噪声拒绝掉本来完全合法的用例。落盘统一取 round()，GDScript 侧用
    1e-6 容差比较，文案里的 ``%.0f`` 两端仍然逐字相同。
    """
    rounded = float(round(float(value)))
    if abs(float(value) - rounded) > 1e-6:
        raise SystemExit(f"✗ {case_id}: {what} 的 elapsed_ms={value!r} 不是毫秒整数")
    return rounded


def _drive(det: TapDetector, frames: list, case_id: str, set_modifier=None) -> tuple:
    """按引擎分支驱动参考实现，记录 Hit / Failure / 首下后的 status。"""
    if set_modifier is not None:
        value = set_modifier
        try:
            normalized = canonical_button(value)
        except ValueError as exc:
            raise SystemExit(f"✗ {case_id}: set_modifier 不是规范按键名：{exc}") from None
        if normalized != value:
            raise SystemExit(
                f"✗ {case_id}: set_modifier 必须是规范名 {normalized!r}，收到 {value!r}"
            )
        # 必须在喂首帧之前调用：回放套件走同一入口、同一顺序，否则
        # det_set_modifier_rt_success 会变成「Python 0 条、GDScript 1 条」的假分歧。
        det.set_modifier(normalized)

    hits = []
    failures = []
    status_after_first_press = None
    for t_ms, label in frames:
        buttons = frozenset(part for part in label.split("+") if part)
        frame = Frame(
            now=t_ms / 1000.0,
            state=PadState(),
            ls_mag=0.0,
            ls_angle=0.0,
            rs_mag=0.0,
            rs_angle=0.0,
            facing=0.0,
            buttons=buttons,
        )
        if all(name in buttons for name in det.required):
            hit = det.update(frame)
            if hit is not None:
                hits.append({
                    "elapsed_ms": _normalize_elapsed_ms(hit.elapsed_ms, case_id, "Hit"),
                    "summary": hit.summary,
                    "detail": hit.detail,
                })
        else:
            # 顺序不能反：先 observe 才能让 reset 用上本帧的按键状态。
            det.observe(frame)
            det.reset()
        if status_after_first_press is None and det._t0 is not None:
            status_after_first_press = det.status()
        failure = det.pop_failure()
        if failure is not None:
            failures.append({
                "code": failure.code,
                "message": failure.message,
                "elapsed_ms": _normalize_elapsed_ms(
                    failure.elapsed_ms, case_id, f"Failure {failure.code}"
                ),
            })
    return hits, failures, status_after_first_press


def _case_payload(case: dict, skill) -> dict:
    case_id = case["id"]
    det = TapDetector(skill)
    frames = _build_frames(case)
    hits, failures, status_after_first_press = _drive(
        det, frames, case_id, case.get("set_modifier")
    )
    expect = {"hits": hits, "failures": failures}
    if status_after_first_press is not None:
        expect["status_after_first_press"] = status_after_first_press

    payload = {
        "id": case_id,
        "kind": "detector",
        "modifier": case["modifier"],
        "button": case["button"],
        "frames": frames,
        "expect": expect,
    }
    if "set_modifier" in case:
        payload["set_modifier"] = case["set_modifier"]
    return payload


def build_payload(root: Path) -> dict:
    """按 Python 参考实现逐用例推导夹具内容（纯计算，不写盘）。"""
    skill = _load_skill(root)
    return {
        "schema_version": 1,
        "source": {
            **{name: rel.as_posix() for name, rel in SOURCE_RELS.items()},
            "sha256": {name: _sha256(root, rel) for name, rel in SOURCE_RELS.items()},
        },
        "meta": {"hz": HZ, "step_ms": STEP_MS, "skill": skill.name},
        "cases": [_case_payload(case, skill) for case in CASES],
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
            f"✗ 缺少 tap 黄金夹具：{FIXTURE_REL.as_posix()}\n"
            "  运行 python3 tools/gen_tap_golden.py 生成。",
            file=sys.stderr,
        )
        return 1
    expected = render(root)
    actual = target.read_bytes()
    if expected != actual:
        print(
            f"✗ 夹具与 Python 参考不一致：{FIXTURE_REL.as_posix()}\n"
            f"  {_first_difference(expected, actual)}\n"
            "  夹具是生成物，不能手改；运行 python3 tools/gen_tap_golden.py "
            "重新生成黄金夹具。",
            file=sys.stderr,
        )
        return 1
    payload = build_payload(root)
    print(
        "✓ tap 黄金夹具与 Python 参考一致"
        f"（detector {len(payload['cases'])} 条）"
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
        prog="gen_tap_golden.py",
        description="从 desktop/padskills/detectors.py 推导 tap 检测器黄金夹具",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "示例:\n"
            "  python3 tools/gen_tap_golden.py           生成 / 刷新夹具\n"
            "  python3 tools/gen_tap_golden.py --check   只校验，不写盘\n"
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
    missing = [rel.as_posix() for rel in SOURCE_RELS.values() if not (root / rel).is_file()]
    if missing:
        raise SystemExit(f"✗ 参考实现不存在：{', '.join(missing)}")
    if args.check:
        return check(root)
    return sync(root)


if __name__ == "__main__":
    raise SystemExit(main())
