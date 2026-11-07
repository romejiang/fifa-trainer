#!/usr/bin/env python3
"""把 250 Hz 手势黄金语料抽稀到 120 / 90 / 60 Hz，并证明判定码不漂移。

    python3 tools/decimate_trace.py            # 生成 / 刷新抽稀夹具
    python3 tools/decimate_trace.py --check    # 只比对，不写盘

抽稀规则只有一条（RESEARCH §C.1，D-04）：

  抽取样本，不抽取时间戳；每个按钮变化必须至少保留一个「变化后」的样本。

    period_ms = 1000 / hz
    boundaries = 0, period_ms, 2*period_ms, ...（到最后一个时间戳为止）
    selected = { argmin_i |t_i - boundary| }（并列取更早的样本）
    for i where buttons[i] != buttons[i-1]:
        selected.add(i)                        # 变化后的那个样本
    frames = [ (t_i, state_i) for i in sorted(selected) ]
    # 时间戳是 t_i，不是 boundary —— 网格化会把 396ms 搬成 400ms，
    # 也就是把 tap 的 too_fast 凭空翻成 ok。

为什么期望值必须由参考实现重放抽稀后的 frames：250 Hz 的期望是另一条时间轴上的
结果，复制过来只能证明「写了两个一样的数字」。重放同时让 `facing` 必须按抽稀后
的帧序列重算 —— 复制 250 Hz 的 facing 列会被 `_drive_engine` 的 1e-9 自断言当场
抓住。

为什么复用 `gen_gesture_golden` 的驱动：`_drive_detector` / `_drive_engine` 是
参考实现与夹具之间的唯一桥。复制一份「差不多的驱动」会与生成器分叉，而分叉不会
在夹具里露出来 —— 两边都绿，判定不同。

为什么白名单必须双向：只校验「有漂移必须有记录」会让白名单随语料腐烂；只校验
「有记录必须有漂移」会让未登记的漂移静默通过。两边都查，删掉一条旧记录与漏登
一条新漂移都会变红。
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import sys
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parent.parent
# 复用同一目录里的生成器 harness：驱动、变体配置、取整刀口断言全部照抄，
# 不在这里写第二份参考驱动。
sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(_REPO_ROOT / "desktop"))

import gen_gesture_golden as golden  # noqa: E402
from padskills.config import parse_config  # noqa: E402

SOURCE_FIXTURE_REL = Path("mobile") / "tests" / "fixtures" / "gesture_golden.json"
FIXTURE_REL = Path("mobile") / "tests" / "fixtures" / "golden_decimated.json"
ALLOWLIST_REL = Path("shared") / "decimation_allowlist.json"
CONFIG_REL = Path("shared") / "skills_config.json"

RATES = (120, 90, 60)
MIN_CASES = 240
RULE = "nearest+keep_ts+force_button_edges"
NO_CODE = "<none>"


def repo_root() -> Path:
    """仓库根目录：以脚本位置（tools/ 的上一级）为锚，不依赖调用方的 cwd。"""
    return _REPO_ROOT


def fixture_path(root: Path) -> Path:
    return root / FIXTURE_REL


def allowlist_path(root: Path) -> Path:
    return root / ALLOWLIST_REL


def _sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


# ---------------------------------------------------------------------------
# 抽稀（唯一正确实现）
# ---------------------------------------------------------------------------


def decimate(frames: list, rate_hz: int) -> list:
    """按 D-04 抽稀：取最近样本、保留原始时间戳、按钮沿保底。

    返回的每一项仍是源夹具的五元组形状 `[t_ms, rs_angle, rs_mag, [按键], facing]`，
    其中 `t_ms` 逐字来自源轨迹。`facing` 此时还是 250 Hz 的旧值，由调用方在
    抽稀后的时间轴上重算。
    """
    if rate_hz not in RATES:
        raise SystemExit(f"✗ 抽稀速率必须是 {RATES} 之一，收到 {rate_hz!r}")
    if not frames:
        raise SystemExit("✗ 抽稀的源轨迹不能为空")

    times = [int(entry[0]) for entry in frames]
    last = times[-1]

    selected: set[int] = set()
    index = 0
    while True:
        # 边界是 k * 1000 / hz，**不做整毫秒取整**。比较距离时用精确有理数
        # （`|t_i * hz - k * 1000|`）而不是浮点 boundary：1000/60 的 450ms
        # 边界会算成 450.00000000000006，把数学上的并列（448 与 452）判成
        # 452，违背「并列取更早」。分子是整数，比较结果与精确边界一致。
        boundary_num = index * 1000
        if boundary_num > last * rate_hz:
            break
        # 并列时取更早的样本：min 的 key 是 (距离分子, 时间戳)。
        best = min(
            range(len(times)),
            key=lambda i: (abs(times[i] * rate_hz - boundary_num), times[i]),
        )
        selected.add(best)
        index += 1

    # 每个按钮变化保留「变化后」的样本。源帧是逐帧全量序列，变化点 i 本身
    # 就是第一个 t_j >= t_i 的样本，所以直接选 i。
    for i in range(1, len(frames)):
        if tuple(frames[i][3]) != tuple(frames[i - 1][3]):
            selected.add(i)

    return [list(frames[i]) for i in sorted(selected)]


def rebuild_facing(frames: list, ls_points, cfg) -> list:
    """在抽稀后的时间轴上重算 `facing`，不复制 250 Hz 的那一列。

    LS 变化点表是时间轴（用户什么时候推左摇杆），不是采样点；原样沿用。
    但 `facing` 是引擎在**实际收到的帧序列**上算出来的状态，抽稀后 LS 的
    推杆时刻可能落到别的时间戳，同一条用例的 facing 因此可能与 250 Hz 不同。
    """
    times = [int(entry[0]) for entry in frames]
    column = golden._facing_column(cfg, ls_points, times)
    rebuilt: list = []
    for entry, facing in zip(frames, column):
        rebuilt.append([
            int(entry[0]),
            float(entry[1]),
            float(entry[2]),
            list(entry[3]),
            float(facing),
        ])
    return rebuilt


# ---------------------------------------------------------------------------
# 工具自身的五条断言
# ---------------------------------------------------------------------------


def _assert_rate(rate_hz: int) -> None:
    """断言 1：速率只能是 120 / 90 / 60。"""
    if rate_hz not in RATES:
        raise SystemExit(f"✗ 未支持的抽稀速率 {rate_hz!r}：只允许 {RATES}")


def _assert_timestamps_from_source(case_id: str, rate_hz: int,
                                   frames: list, source_frames: list) -> None:
    """断言 2：时间戳严格递增，且每个都能在源轨迹里原样找到。

    `set` 成员判定就是「没有网格化」的机械证明：网格化后的 400ms 不在
    源轨迹的 {0,4,8,...,396,...} 里，必然命中这里。
    """
    source_times = {int(entry[0]) for entry in source_frames}
    previous = None
    for entry in frames:
        t_ms = int(entry[0])
        if t_ms not in source_times:
            raise SystemExit(
                f"✗ {case_id}@{rate_hz}: 时间戳 {t_ms}ms 不在源轨迹里"
                f"（抽稀只许抽样本，不许网格化时间戳）"
            )
        if previous is not None and t_ms <= previous:
            raise SystemExit(
                f"✗ {case_id}@{rate_hz}: 时间戳必须严格递增，"
                f"{previous}ms 之后出现了 {t_ms}ms"
            )
        previous = t_ms


def _assert_button_edges(case_id: str, rate_hz: int,
                         frames: list, source_frames: list) -> None:
    """断言 3：每个按钮变化在输出里都有对应的「变化后」样本。"""
    by_time = {int(entry[0]): tuple(entry[3]) for entry in frames}
    for i in range(1, len(source_frames)):
        before = tuple(source_frames[i - 1][3])
        after = tuple(source_frames[i][3])
        if before == after:
            continue
        t_ms = int(source_frames[i][0])
        if by_time.get(t_ms) != after:
            raise SystemExit(
                f"✗ {case_id}@{rate_hz}: 缺少按钮沿样本（{t_ms}ms "
                f"{'/'.join(before) or '无'} -> {'/'.join(after) or '无'}）"
            )


# ---------------------------------------------------------------------------
# 白名单
# ---------------------------------------------------------------------------


def load_allowlist(root: Path) -> dict[tuple[str, int], str]:
    """读白名单：`(id, rate_hz) -> reason`，reason 必须非空。"""
    path = allowlist_path(root)
    if not path.is_file():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SystemExit(
            f"✗ 白名单不是合法 JSON：{ALLOWLIST_REL.as_posix()} 第 {exc.lineno} 行：{exc.msg}"
        ) from exc
    if not isinstance(data, dict):
        raise SystemExit("✗ 白名单根节点必须是对象")
    entries: dict[tuple[str, int], str] = {}
    for item in data.get("allow", []):
        if not isinstance(item, dict):
            raise SystemExit("✗ 白名单 allow[] 的每一项必须是对象")
        key = (str(item.get("id", "")), int(item.get("rate_hz", 0)))
        reason = str(item.get("reason", "")).strip()
        if not key[0]:
            raise SystemExit("✗ 白名单条目缺少 id")
        if key[1] not in RATES:
            raise SystemExit(f"✗ 白名单条目 {key} 的 rate_hz 不在 {RATES}")
        if not reason:
            raise SystemExit(f"✗ 白名单条目 {key} 的 reason 为空：漂移必须写明理由")
        if key in entries:
            raise SystemExit(f"✗ 白名单条目重复：{key}")
        entries[key] = reason
    return entries


def _assert_allowlist_bidirectional(cases: list, allow: dict[tuple[str, int], str]) -> None:
    """断言 5：漂移 ⇔ 白名单，两个方向都查。"""
    drifting = {
        (str(case["source_id"]), int(case["rate_hz"]))
        for case in cases
        if case["vs_250"]["drift"]
    }
    missing = sorted(drifting - set(allow))
    stale = sorted(set(allow) - drifting)
    problems: list[str] = []
    for case_id, rate_hz in missing:
        problems.append(
            f"未登记的漂移：{case_id}@{rate_hz} 的判定码与 250 Hz 不同，"
            "但 shared/decimation_allowlist.json 里没有同 id、同 rate 的条目"
        )
    for case_id, rate_hz in stale:
        problems.append(
            f"白名单条目已不漂移：{case_id}@{rate_hz} 现在与 250 Hz 完全一致，"
            "请从 shared/decimation_allowlist.json 删除该条"
        )
    if problems:
        for line in problems:
            print(f"✗ {line}", file=sys.stderr)
        raise SystemExit(1)


# ---------------------------------------------------------------------------
# 期望值 / vs_250
# ---------------------------------------------------------------------------


def _codes(outcomes: list) -> list[tuple[str, str]]:
    """L2 比较口径：只到 `(skill, code)`；`ok` 由 `code == "ok"` 表达。"""
    return [(str(item["skill"]), str(item["code"])) for item in outcomes]


def _label(code: tuple[str, str] | None) -> str:
    if code is None:
        return NO_CODE
    return f"{code[0]}:{code[1]}"


def _max_elapsed_delta(source_outcomes: list, outcomes: list, case_id: str) -> float:
    """配对比较 elapsed_ms，返回最大绝对差（毫秒）。

    条数不同时只比较能配对的前缀；条数差异本身已经由 drift 记录表达。
    所有时间戳都是 4ms 的整数倍，差值也是 4 的倍数，因此这里同时复用
    `_assert_not_rounding_cliff` 拒绝 .5 刀口 —— 该断言本来就是为「数字会不会
    被格式化到另一个整数」而存在。
    """
    deltas = []
    for want, got in zip(source_outcomes, outcomes):
        deltas.append(abs(float(got["elapsed_ms"]) - float(want["elapsed_ms"])))
    value = max(deltas) if deltas else 0.0
    golden._assert_not_rounding_cliff(value, case_id, "max_abs_elapsed_delta_ms")
    return value


def _vs_250(source_case: dict, outcomes: list, rate_hz: int,
            reason: str | None) -> dict:
    source_outcomes = source_case.get("expect", {}).get("outcomes", [])
    source_codes = _codes(source_outcomes)
    decimated_codes = _codes(outcomes)
    drift: list[dict] = []
    for index in range(max(len(source_codes), len(decimated_codes))):
        want = source_codes[index] if index < len(source_codes) else None
        got = decimated_codes[index] if index < len(decimated_codes) else None
        if want == got:
            continue
        if reason is None:
            # 未登记时给出可读的差异，最终由双向校验判红并阻止写盘。
            reason = (
                f"250 Hz 判定码 {_label(want)}，{rate_hz} Hz 判定码 {_label(got)}"
            )
        drift.append({
            "index": index,
            "from": _label(want),
            "to": _label(got),
            "reason": reason,
        })
    return {
        "codes_equal": source_codes == decimated_codes,
        "max_abs_elapsed_delta_ms": _max_elapsed_delta(
            source_outcomes, outcomes, str(source_case["id"])),
        "drift": drift,
    }


# ---------------------------------------------------------------------------
# payload / 规范字节 / 只读校验
# ---------------------------------------------------------------------------


def _build_case(source_case: dict, cfg, rate_hz: int,
                allow: dict[tuple[str, int], str]) -> dict:
    case_id = str(source_case["id"])
    kind = str(source_case["kind"])
    ls_points = source_case.get("ls", [[0, 0.0, 0.9]])
    source_frames = source_case["frames"]
    rate = int(rate_hz)

    _assert_rate(rate)
    frames = decimate(source_frames, rate)
    frames = rebuild_facing(frames, ls_points, cfg)
    _assert_timestamps_from_source(case_id, rate, frames, source_frames)
    _assert_button_edges(case_id, rate, frames, source_frames)

    if kind == "detector":
        outcomes = golden._drive_detector(cfg, source_case, frames)
        expect = {"outcomes": outcomes}
    elif kind == "runtime":
        engine = golden._drive_engine(cfg, frames, ls_points, case_id)
        outcomes = golden._runtime_outcomes(case_id, engine)
        expect = {
            "outcomes": outcomes,
            "counters": golden._runtime_counters(engine),
        }
    else:
        raise SystemExit(f"✗ {case_id}: 未知的用例类型 {kind!r}")

    reason = allow.get((case_id, rate))
    return {
        "id": f"{case_id}@{rate}",
        "source_id": case_id,
        "kind": kind,
        "rate_hz": rate,
        "rule": RULE,
        "skill": str(source_case["skill"]),
        "config": str(source_case.get("config", "shipped")),
        "ls": [[int(t), float(a), float(m)] for t, a, m in ls_points],
        "frames": frames,
        "expect": expect,
        "vs_250": _vs_250(source_case, outcomes, rate, reason),
    }


def build_payload(root: Path) -> dict:
    """按 D-04 逐用例推导抽稀夹具内容（纯计算，不写盘）。"""
    source_path = root / SOURCE_FIXTURE_REL
    if not source_path.is_file():
        raise SystemExit(
            f"✗ 缺少源夹具：{SOURCE_FIXTURE_REL.as_posix()}\n"
            "  先运行 python3 tools/gen_gesture_golden.py 生成。"
        )
    source_bytes = source_path.read_bytes()
    source = json.loads(source_bytes.decode("utf-8"))
    if int(source.get("schema_version", 0)) != 1:
        raise SystemExit("✗ 源夹具 schema_version 不是 1")

    configs = source.get("configs", {})
    parsed = {
        key: parse_config(copy.deepcopy(value), root / CONFIG_REL)
        for key, value in configs.items()
    }
    allow = load_allowlist(root)

    source_cases = source.get("cases", [])
    detector_count = sum(1 for case in source_cases if case.get("kind") == "detector")
    runtime_count = sum(1 for case in source_cases if case.get("kind") == "runtime")
    expected_cases = len(RATES) * (detector_count + runtime_count)

    cases: list[dict] = []
    for source_case in source_cases:
        key = str(source_case.get("config", "shipped"))
        if key not in parsed:
            raise SystemExit(
                f"✗ {source_case.get('id')}: config 键 {key!r} 不在源夹具 configs 注册表里"
            )
        for rate_hz in RATES:
            cases.append(_build_case(source_case, parsed[key], rate_hz, allow))

    if len(cases) != expected_cases:
        raise SystemExit(
            f"✗ 条数不等于 3 倍源用例数：实际 {len(cases)}，"
            f"期望 {expected_cases}（3 × ({detector_count} + {runtime_count})）"
        )
    if len(cases) < MIN_CASES:
        raise SystemExit(
            f"✗ 抽稀用例只有 {len(cases)} 条，低于下限 {MIN_CASES}"
        )

    seen: set[str] = set()
    for case in cases:
        if case["id"] in seen:
            raise SystemExit(f"✗ 抽稀用例 id 重复：{case['id']}")
        seen.add(case["id"])

    _assert_allowlist_bidirectional(cases, allow)

    payload = {
        "schema_version": 1,
        "source": {
            "fixture": SOURCE_FIXTURE_REL.as_posix(),
            "sha256": {
                "gesture_golden": _sha256_bytes(source_bytes),
                "skills_config": _sha256_bytes((root / CONFIG_REL).read_bytes()),
            },
        },
        "meta": {
            "hz": int(source.get("meta", {}).get("hz", 250)),
            "step_ms": int(source.get("meta", {}).get("step_ms", 4)),
            "rates": list(RATES),
            "rule": RULE,
            "min_cases": MIN_CASES,
        },
        # 注册表整份复制：变体 / 合成用例不能回落到出厂副本，否则会被按
        # 出厂阈值静默回放，`mismatches=0` 变成假绿。
        "configs": configs,
        "cases": cases,
    }
    if payload["configs"] != configs:
        raise SystemExit("✗ configs 注册表没有整份复制源夹具")
    if set(payload["configs"]) != set(source.get("configs", {})):
        raise SystemExit("✗ configs 注册表的键集合与源夹具不同")
    return payload


def render(root: Path) -> bytes:
    """夹具的规范字节形态：UTF-8、两空格缩进、键排序、结尾一个换行。"""
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


def _counts(payload: dict) -> tuple[int, int, int]:
    rates = sorted({int(case["rate_hz"]) for case in payload["cases"]})
    drifting = sum(1 for case in payload["cases"] if case["vs_250"]["drift"])
    return len(rates), len(payload["cases"]), drifting


def check(root: Path) -> int:
    """只读校验：重新推导后与磁盘夹具逐字节比较，绝不写盘。"""
    target = fixture_path(root)
    if not target.is_file():
        print(
            f"✗ 缺少抽稀夹具：{FIXTURE_REL.as_posix()}\n"
            "  运行 python3 tools/decimate_trace.py 生成。",
            file=sys.stderr,
        )
        return 1
    expected = render(root)
    actual = target.read_bytes()
    if expected != actual:
        print(
            f"✗ 抽稀夹具与生成器不一致：{FIXTURE_REL.as_posix()}\n"
            f"  {_first_difference(expected, actual)}\n"
            "  夹具是生成物，不能手改；运行 python3 tools/decimate_trace.py "
            "重新生成。",
            file=sys.stderr,
        )
        return 1
    rates, cases, drifting = _counts(build_payload(root))
    print(
        "✓ 抽稀夹具与生成器一致"
        f"（rates={rates} cases={cases} drifting={drifting}）"
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
        prog="decimate_trace.py",
        description="把 250 Hz 手势黄金语料抽稀到 120 / 90 / 60 Hz",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "示例:\n"
            "  python3 tools/decimate_trace.py           生成 / 刷新夹具\n"
            "  python3 tools/decimate_trace.py --check   只校验，不写盘\n"
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
    if not (root / SOURCE_FIXTURE_REL).is_file():
        raise SystemExit(f"✗ 源夹具不存在：{SOURCE_FIXTURE_REL.as_posix()}")
    if args.check:
        return check(root)
    return sync(root)


if __name__ == "__main__":
    raise SystemExit(main())
