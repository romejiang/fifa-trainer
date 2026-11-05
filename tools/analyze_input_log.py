#!/usr/bin/env python3
"""从 ``input_log.txt`` 里切出判定前的活动窗口，统计到达间隔与每轴行程。

用法::

    python3 tools/analyze_input_log.py --log <本地副本> [--gap-ms 100]

为什么需要它：``PadStateBuffer.delta_ms_percentiles()`` 统计的是**整段会话**，静置
空档会把 ``dt95`` 拉到几百毫秒（04-VERIFICATION 的 ``dt95=234.7`` 就是这么来的）。
一次搓招真正要看的只是「判定前的连续轴变化」这一段。本脚本以每条 ``OUTCOME`` 行
为窗口右界，向前找最近一次连续轴变化：相邻 ``axis=`` 行的间隔大于 ``--gap-ms``
（默认 100）即视为断开。

输出：

* 每个窗口一行摘要（``samples`` / 去重后的时间戳数 / ``p50`` / ``p95`` / ``max``）；
* 窗口内每根轴的 ``min`` / ``max``（判断是否有扳机轴跳变污染）；
* 最后一行哨兵 ``INPUT_LOG_STATS windows=N outcome=K p50=… p95=… max=…``，
  供脚本 grep。没有 ``OUTCOME`` 时以非零退出并打印 ``INPUT_LOG_EMPTY``。

输入形态：生产日志是裸行 ``t=…``；``adb logcat`` 拷贝带 ``INPUT_EVT `` 前缀。
两种都接受。

只读、零第三方依赖。分位数口径与 ``PadStateBuffer`` 一致：取排序后的
``floor(0.5*(n-1))`` / ``ceil(0.95*(n-1))``，不做插值。
"""

from __future__ import annotations

import argparse
import math
import re
import sys
from pathlib import Path
from typing import Dict, List, Tuple

BARE_AXIS = re.compile(
    r"^t=(\d+)\s+(?:dev=-?\d+\s+)?axis=(\d+)\s+v=(-?\d+(?:\.\d+)?)\s*$")
BARE_OUTCOME = re.compile(r"^t=(\d+)\s+OUTCOME\b")
LOGCAT_MARKER = "INPUT_EVT "

DEFAULT_LOG = "input_log.txt"
DEFAULT_GAP_MS = 100

AxisSample = Tuple[int, int, float]
Window = Tuple[int, List[AxisSample]]


def payload(line: str) -> str:
    """剥掉 logcat 前缀，返回 ``t=…`` 开始的正文。"""
    marker = line.rfind(LOGCAT_MARKER)
    if marker >= 0:
        return line[marker + len(LOGCAT_MARKER):].strip()
    return line.strip()


def parse(path: Path) -> Tuple[List[AxisSample], List[int]]:
    """返回 ``(axis 样本, outcome 时间戳)``。无法识别的行（会话头 / 按钮 / 噪声）跳过。"""
    text = path.read_text(encoding="utf-8-sig", errors="replace")
    axes: List[AxisSample] = []
    outcomes: List[int] = []
    for raw in text.splitlines():
        line = payload(raw)
        if not line:
            continue
        axis_match = BARE_AXIS.match(line)
        if axis_match:
            axes.append((int(axis_match.group(1)), int(axis_match.group(2)),
                         float(axis_match.group(3))))
            continue
        outcome_match = BARE_OUTCOME.match(line)
        if outcome_match:
            outcomes.append(int(outcome_match.group(1)))
    return axes, outcomes


def build_windows(axes: List[AxisSample], outcomes: List[int],
                  gap_ms: int) -> List[Window]:
    """每条 ``OUTCOME`` 一个窗口：向前走连续的 ``axis=`` 行，遇大间隔或上一条判定即停。

    时间戳不保证严格递增的输入（例如把两段日志拼在一起）也不会让窗口跨越上一条
    判定 —— 下界取 ``outcomes[i-1]``，上界取 ``outcomes[i]``。
    """
    windows: List[Window] = []
    for index, outcome_t in enumerate(outcomes):
        floor_t = outcomes[index - 1] if index > 0 else -1
        cursor = len(axes) - 1
        while cursor >= 0 and axes[cursor][0] > outcome_t:
            cursor -= 1
        run: List[AxisSample] = []
        later_t = None
        while cursor >= 0 and axes[cursor][0] >= floor_t:
            sample_t = axes[cursor][0]
            if later_t is not None and later_t - sample_t > gap_ms:
                break
            run.append(axes[cursor])
            later_t = sample_t
            cursor -= 1
        run.reverse()
        windows.append((outcome_t, run))
    return windows


def percentiles(values: List[int]) -> Tuple[float, float, float]:
    """与 ``PadStateBuffer`` 同口径：排序后取下标，不插值。"""
    if not values:
        return (0.0, 0.0, 0.0)
    ordered = sorted(values)
    last = len(ordered) - 1
    return (float(ordered[int(math.floor(0.5 * last))]),
            float(ordered[int(math.ceil(0.95 * last))]),
            float(ordered[last]))


def window_deltas(samples: List[AxisSample]) -> List[int]:
    """同一时间戳的多根轴算一帧，避免 0 ms 间隔把分位数拉低。"""
    stamps = sorted({sample[0] for sample in samples})
    return [stamps[i] - stamps[i - 1] for i in range(1, len(stamps))]


def axis_ranges(samples: List[AxisSample]) -> Dict[int, Tuple[float, float]]:
    ranges: Dict[int, Tuple[float, float]] = {}
    for _, axis, value in samples:
        low, high = ranges.get(axis, (value, value))
        ranges[axis] = (min(low, value), max(high, value))
    return ranges


def main(argv: List[str]) -> int:
    parser = argparse.ArgumentParser(description="统计 input_log 判定窗口的采样间隔")
    parser.add_argument("--log", default=DEFAULT_LOG, help="日志路径（默认 input_log.txt）")
    parser.add_argument("--gap-ms", type=int, default=DEFAULT_GAP_MS,
                        help="相邻轴行间隔超过它即视为断开（默认 100 ms）")
    args = parser.parse_args(argv)

    if args.gap_ms <= 0:
        print("INPUT_LOG_INVALID gap_ms 必须大于 0", file=sys.stderr)
        return 2
    path = Path(args.log)
    if not path.is_file():
        print(f"INPUT_LOG_EMPTY reason=no_file path={path}", file=sys.stderr)
        return 1
    axes, outcomes = parse(path)
    if not outcomes:
        print(f"INPUT_LOG_EMPTY outcomes=0 path={path}", file=sys.stderr)
        return 1

    windows = build_windows(axes, outcomes, args.gap_ms)
    all_deltas: List[int] = []
    counted = 0
    for index, (outcome_t, samples) in enumerate(windows, start=1):
        deltas = window_deltas(samples)
        all_deltas.extend(deltas)
        p50, p95, maximum = percentiles(deltas)
        if samples:
            counted += 1
        print(f"window={index} outcome_t={outcome_t} samples={len(samples)} "
              f"intervals={len(deltas)} p50={p50:.1f} p95={p95:.1f} max={maximum:.1f}")
        for axis, (low, high) in sorted(axis_ranges(samples).items()):
            print(f"  axis={axis} min={low:.3f} max={high:.3f}")

    p50, p95, maximum = percentiles(all_deltas)
    print(f"INPUT_LOG_STATS windows={counted} outcome={len(outcomes)} "
          f"p50={p50:.1f} p95={p95:.1f} max={maximum:.1f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
