#!/usr/bin/env python3
"""识别算法自测（不依赖 pytest，直接 `uv run tests/test_detectors.py`）。

用合成轨迹喂给识别器，验证三个内置动作能正确触发、且不该触发的情况不误触发。
改完 skills_config.json 之后跑一遍，能快速确认没把规则改坏。
"""

from __future__ import annotations

import math
import sys
import time
from pathlib import Path
from typing import Iterable, List, Optional, Sequence, Tuple

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from padskills.config import (
    DEFAULT_CONFIG, Pulse, Skill, load_config, parse_config,
)
from padskills.detectors import ArcDetector, Frame, SequenceDetector, TapDetector
from padskills.engine import Engine
from padskills.input_source import (
    AxisLayout, GamepadSource, PadState, apply_axis_inverts,
)
from padskills.rumble import RumbleBackend, RumbleEngine

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


# ---------------------------------------------------------------------------
# 合成轨迹工具
# ---------------------------------------------------------------------------

def stick(angle: float, mag: float) -> Tuple[float, float]:
    """角度 + 幅度 -> 摇杆原始坐标（与 geometry.angle_of 互逆）。"""
    rad = math.radians(angle)
    return mag * math.sin(rad), -mag * math.cos(rad)


def make_frame(t: float, rs_angle: float = 0.0, rs_mag: float = 0.0,
               ls_angle: float = 0.0, ls_mag: float = 0.0,
               facing: float = 0.0, buttons: Iterable[str] = ()) -> Frame:
    rs_x, rs_y = stick(rs_angle, rs_mag) if rs_mag > 0 else (0.0, 0.0)
    ls_x, ls_y = stick(ls_angle, ls_mag) if ls_mag > 0 else (0.0, 0.0)
    state = PadState(ls_x=ls_x, ls_y=ls_y, rs_x=rs_x, rs_y=rs_y,
                     buttons=frozenset(buttons))
    return Frame(now=t, state=state,
                 ls_mag=state.ls_mag, ls_angle=state.ls_angle,
                 rs_mag=state.rs_mag, rs_angle=state.rs_angle,
                 facing=facing, buttons=state.buttons)


def rotate(t0: float, start_angle: float, sweep: float, duration_ms: float,
           hz: int = 250, mag: float = 0.92, facing: float = 0.0,
           buttons: Iterable[str] = ()) -> List[Frame]:
    """生成一段匀速旋转的轨迹。"""
    step_ms = 1000.0 / hz
    n = max(1, int(duration_ms / step_ms))
    frames = []
    for i in range(n + 1):
        frac = i / n
        frames.append(make_frame(
            t0 + (i * step_ms) / 1000.0,
            rs_angle=start_angle + sweep * frac,
            rs_mag=mag, facing=facing, buttons=buttons,
        ))
    return frames


def flick(t0: float, angle: float, mag: float = 0.9, hold_ms: float = 60.0,
          hz: int = 250, facing: float = 0.0,
          buttons: Iterable[str] = ()) -> List[Frame]:
    """生成一次"点拨"：推到角度 -> 保持 -> 回中。"""
    step_ms = 1000.0 / hz
    frames = []
    t = t0
    for _ in range(int(hold_ms / step_ms)):
        frames.append(make_frame(t, rs_angle=angle, rs_mag=mag, facing=facing, buttons=buttons))
        t += step_ms / 1000.0
    for _ in range(int(80 / step_ms)):
        frames.append(make_frame(t, rs_mag=0.0, facing=facing, buttons=buttons))
        t += step_ms / 1000.0
    return frames


def centered(t0: float, duration_ms: float, hz: int = 250) -> List[Frame]:
    """摇杆回中并保持一段时间。"""
    step_ms = 1000.0 / hz
    n = max(1, int(duration_ms / step_ms))
    return [make_frame(t0 + i * step_ms / 1000.0, rs_mag=0.0) for i in range(n)]


def held(t0: float, angle: float, duration_ms: float, mag: float = 0.92,
         hz: int = 250) -> List[Frame]:
    """推着摇杆不动。"""
    step_ms = 1000.0 / hz
    n = max(1, int(duration_ms / step_ms))
    return [make_frame(t0 + i * step_ms / 1000.0, rs_angle=angle, rs_mag=mag)
            for i in range(n)]


def variant(base_name: str, **params) -> Skill:
    """基于内置动作派生一个改了参数的测试变体。"""
    raw = dict(DEFAULT_CONFIG)
    base = default_skill_raw(base_name)
    raw["skills"] = [dict(base, name="测试变体",
                          params=dict(base["params"], **params))]
    return parse_config(raw).skills[0]


def tap_frames(t0: float, interval_ms: float, hold_ms: float = 60.0,
               second: bool = True, rb: bool = True,
               rb_release_at: Optional[float] = None,
               modifier: str = "RB", hz: int = 250) -> List[Frame]:
    """按住修饰键，按两下 X；两下按下的时间间隔为 interval_ms。"""
    step_ms = 1000.0 / hz
    frames: List[Frame] = []
    # 先按住修饰键 100ms，保证第一下 X 是真正的"按下沿"
    for i in range(int(100 / step_ms)):
        frames.append(make_frame(t0 + i * step_ms / 1000.0,
                                 buttons=(modifier,) if rb else ()))
    first_t = t0 + 100 / 1000.0
    # 尾巴要盖过"没有第二下"的超时（max 600 + grace 150）
    total_ms = interval_ms + hold_ms + 400
    for i in range(int(total_ms / step_ms) + 1):
        ms = i * step_ms
        buttons = set()
        held_mod = rb and (rb_release_at is None or ms < rb_release_at)
        if held_mod:
            buttons.add(modifier)
        pressed = ms < hold_ms or (
            second and interval_ms <= ms < interval_ms + hold_ms)
        if pressed:
            buttons.add("X")
        frames.append(make_frame(first_t + ms / 1000.0, buttons=buttons))
    return frames


def run_taps(cfg, interval_ms: float, **kwargs) -> Engine:
    engine = Engine(cfg, NullSource(), RumbleEngine(None, enabled=False),
                    debug=False)
    for f in tap_frames(0.0, interval_ms, **kwargs):
        tick(engine, f.now, buttons=f.buttons, ls_mag=0.0)
    return engine


def run_detector(detector, frames: Sequence[Frame]) -> Optional[object]:
    hit = None
    for f in frames:
        result = detector.update(f)
        if result is not None and hit is None:
            hit = result
    return hit


def skill_of(cfg, name_fragment: str) -> Skill:
    for s in cfg.skills:
        if name_fragment in s.name:
            return s
    raise AssertionError(f"配置里找不到动作 {name_fragment!r}")


def default_skill_raw(name_fragment: str) -> dict:
    """按名字片段从内置默认配置里取动作，避免用下标（加新动作后下标会错位）。"""
    for s in DEFAULT_CONFIG["skills"]:
        if name_fragment in s["name"]:
            return s
    raise AssertionError(f"默认配置里找不到动作 {name_fragment!r}")


def skill_index(data: dict, name_fragment: str) -> int:
    for i, s in enumerate(data["skills"]):
        if name_fragment in s["name"]:
            return i
    raise AssertionError(f"配置里找不到动作 {name_fragment!r}")


# ---------------------------------------------------------------------------
# 用例
# ---------------------------------------------------------------------------

def test_geometry() -> None:
    from padskills.geometry import angle_diff, angle_of, signed_delta

    print("\n[0] 角度换算")
    check("居中 (0,0) -> 0.0°，不是 atan2(0,-0) 的 180°",
          angle_of(0.0, 0.0) == 0.0, f"实际 {angle_of(0.0, 0.0)}")
    check("正上方 -> 0°", angle_of(0.0, -1.0) == 0.0)
    check("正右方 -> 90°", angle_of(1.0, 0.0) == 90.0)
    check("正下方 -> 180°", angle_of(0.0, 1.0) == 180.0)
    check("正左方 -> 270°", angle_of(-1.0, 0.0) == 270.0)
    check("最短弧 350° -> 10° 为 +20°（顺时针）",
          abs(signed_delta(350.0, 10.0) - 20.0) < 1e-9,
          f"实际 {signed_delta(350.0, 10.0)}")
    check("最短弧 10° -> 350° 为 -20°（逆时针）",
          abs(signed_delta(10.0, 350.0) + 20.0) < 1e-9)
    check("夹角 0° 与 350° 为 10°", angle_diff(0.0, 350.0) == 10.0)


def test_arc(cfg) -> None:
    print("\n[1] 连续旋转类 —— 马赛回旋（从后往前转）")
    skill = skill_of(cfg, "马赛回旋")

    det = ArcDetector(skill)
    hit = run_detector(det, rotate(0.0, 180.0, 200.0, 500.0))
    check("从后(180°)顺时针转 200°/500ms -> 触发", hit is not None,
          f"耗时 {hit.elapsed_ms:.0f}ms" if hit else "未触发")
    check("成功摘要：带命中瞬间的累计旋转角度和经过的角度范围",
          hit is not None and "旋转" in hit.summary and "°→" in hit.summary,
          hit.summary if hit else "未触发")

    det = ArcDetector(skill)
    hit = run_detector(det, rotate(0.0, 180.0, -200.0, 500.0))
    check("从后逆时针转 200° 同样触发（direction=any）", hit is not None)

    det = ArcDetector(skill)
    hit = run_detector(det, rotate(0.0, 180.0, 90.0, 500.0))
    check("从后只转 90° 停在侧面 -> 不触发（终点不在身前）", hit is None)

    det = ArcDetector(skill)
    hit = run_detector(det, rotate(0.0, 180.0, 200.0, 1400.0))
    check("转 200° 但用了 1400ms -> 不触发（超出时间窗口）", hit is None)

    det = ArcDetector(skill)
    hit = run_detector(det, rotate(0.0, 180.0, 200.0, 60.0))
    check("60ms 内甩完 200° -> 不触发（太快，不算搓招）", hit is None)

    det = ArcDetector(skill)
    hit = run_detector(det, rotate(0.0, 230.0, 100.0, 400.0))
    check("起点 230°（在 180±65 容差内）-> 触发", hit is not None)

    det = ArcDetector(skill)
    hit = run_detector(det, rotate(0.0, 250.0, 200.0, 200.0))
    check("起点 250°（超出 180±65 容差）-> 不触发", hit is None)

    det = ArcDetector(skill)
    hit = run_detector(det, rotate(0.0, 180.0, 200.0, 200.0, mag=0.5))
    check("幅度只有 0.5（没推到外圈）-> 不触发", hit is None)

    det = ArcDetector(skill)
    hit = run_detector(det, rotate(0.0, 180.0, 200.0, 200.0, mag=0.65))
    check("幅度 0.65（够不到 enter_threshold=0.72）-> 不触发", hit is None)

    # 从后(180)转到 360，会越过 0°/360° 边界，累计角度必须连续
    det = ArcDetector(skill)
    hit = run_detector(det, rotate(0.0, 180.0, 180.0, 500.0))
    check("从后 180° 转到 360°（越过 0° 边界）-> 正常触发",
          hit is not None, f"累计 {abs(det.acc):.0f}°" if hit else "未触发")

    # 判定语义是"累计角度一进入区间、终点也对得上就成功"，转一整圈必然在路过时触发一次
    det = ArcDetector(skill)
    frames = rotate(0.0, 180.0, 230.0, 600.0)
    hits = [h for h in (det.update(f) for f in frames) if h is not None]
    check("从后连续转满 230° -> 只触发一次", len(hits) == 1, f"实际 {len(hits)} 次")

    # 终点方向对不上就不算：从后往前转，但停在侧面（累计够了、终点错了）
    det = ArcDetector(skill)
    hit = run_detector(det, rotate(0.0, 180.0, 150.0, 500.0))
    check("从后转 150° 停在 330°(≈-30°，在终点 0°±75 内) -> 触发", hit is not None)

    det = ArcDetector(skill)
    hit = run_detector(det, rotate(0.0, 90.0, 200.0, 200.0))
    check("从侧面起手 -> 不触发（起点就不是马赛回旋）", hit is None)

    # 持续推着外圈不松手，不能反复触发
    det = ArcDetector(skill)
    frames = rotate(0.0, 180.0, 200.0, 500.0) + rotate(0.50, 200.0, 200.0, 500.0)
    hits = [h for h in (det.update(f) for f in frames) if h is not None]
    check("持续推着外圈连转两圈 -> 只触发一次", len(hits) == 1, f"实际 {len(hits)} 次")


def test_stepover(cfg) -> None:
    print("\n[2] 连续旋转类 —— 踩单车（从前往侧转）")
    skill = skill_of(cfg, "踩单车")

    det = ArcDetector(skill)
    hit = run_detector(det, rotate(0.0, 0.0, 90.0, 500.0))
    check("从前(0°)顺时针转 90° -> 触发", hit is not None,
          f"耗时 {hit.elapsed_ms:.0f}ms" if hit else "未触发")

    det = ArcDetector(skill)
    check("从前(0°)逆时针转 90° -> 触发",
          run_detector(det, rotate(0.0, 0.0, -90.0, 500.0)) is not None)

    det = ArcDetector(skill)
    check("从前只转 40° -> 不触发（转得不够）",
          run_detector(det, rotate(0.0, 0.0, 40.0, 100.0)) is None)


def test_arc_discrimination(cfg) -> None:
    """用户报的核心问题：不能把"从前往侧转"误判成马赛回旋。"""
    print("\n[3] 马赛回旋 与 踩单车 互不误判")
    roulette = skill_of(cfg, "马赛回旋")
    stepover = skill_of(cfg, "踩单车")

    cases = [
        (180.0, 180.0, "从后往前转 180°", "马赛回旋"),
        (180.0, -180.0, "从后往前反向转 180°", "马赛回旋"),
        (0.0, 90.0, "从前往侧转 90°", "踩单车"),
        (0.0, -90.0, "从前往另一侧转 90°", "踩单车"),
        (90.0, 90.0, "从侧往转 90°（不完整动作）", "都不触发"),
    ]
    for start, sweep, label, expect in cases:
        r = run_detector(ArcDetector(roulette), rotate(0.0, start, sweep, 500.0))
        s = run_detector(ArcDetector(stepover), rotate(0.0, start, sweep, 500.0))
        fired = ("马赛回旋" if r else "") + ("踩单车" if s else "")
        fired = fired or "都不触发"
        check(f"{label} -> {expect}", fired == expect, f"实际: {fired}")


def test_arc_direction(cfg) -> None:
    print("\n[4] 旋转方向约束")
    base = default_skill_raw("马赛回旋")
    raw = dict(DEFAULT_CONFIG)
    raw["skills"] = [dict(base, name="只认顺时针",
                          params=dict(base["params"], direction="cw"))]
    skill = parse_config(raw).skills[0]

    det = ArcDetector(skill)
    check("direction=cw 时顺时针 -> 触发",
          run_detector(det, rotate(0.0, 180.0, 200.0, 500.0)) is not None)

    det = ArcDetector(skill)
    check("direction=cw 时逆时针 -> 不触发",
          run_detector(det, rotate(0.0, 180.0, -200.0, 500.0)) is None)


def test_sequence_heel_to_heel(cfg) -> None:
    print("\n[5] 方向点拨序列 —— 磕球过人 Heel-to-Heel")
    skill = skill_of(cfg, "磕球")

    # 球员面朝右（左摇杆推到 90°），前 = 屏幕右，后 = 屏幕左
    facing = 90.0
    det = SequenceDetector(skill)
    frames = flick(0.0, 90.0, hold_ms=250, facing=facing) + flick(0.35, 270.0, facing=facing)
    hit = run_detector(det, frames)
    check("面朝右时：RS 向屏幕右再向屏幕左 -> 触发（相对左摇杆模式）",
          hit is not None, f"耗时 {hit.elapsed_ms:.0f}ms" if hit else "未触发")

    # 绝对方向模式下，同一串操作不该触发（因为"前"变成了屏幕上方）
    raw = dict(DEFAULT_CONFIG)
    raw["skills"] = [dict(default_skill_raw("磕球"), relative_to_ls=False)]
    abs_skill = parse_config(raw).skills[0]
    det = SequenceDetector(abs_skill)
    check("同样的操作在 absolute 模式下 -> 不触发（方向基准不同）",
          run_detector(det, frames) is None)

    # 中间不回中的"推过去再拉回来"不算点拨
    det = SequenceDetector(skill)
    step_ms = 4.0
    frames = ([make_frame(i * step_ms / 1000.0, rs_angle=90.0, rs_mag=0.9, facing=facing)
               for i in range(15)] +
              [make_frame((15 + i) * step_ms / 1000.0, rs_angle=270.0, rs_mag=0.9, facing=facing)
               for i in range(15)])
    check("前->后 中间摇杆不回中 -> 不触发（不是真正的点拨）",
          run_detector(det, frames) is None)

    det = SequenceDetector(skill)
    frames = flick(0.0, 90.0, facing=facing) + flick(0.20, 90.0, facing=facing)
    check("前->前（方向错了）-> 不触发",
          run_detector(det, frames) is None)

    det = SequenceDetector(skill)
    frames = flick(0.0, 90.0, facing=facing) + flick(1.20, 270.0, facing=facing)
    check("两步间隔 1.2s -> 不触发（超出 max_duration_ms=600）",
          run_detector(det, frames) is None)


def test_sequence_croqueta(cfg) -> None:
    print("\n[6] 修饰键 + 保持 —— La Croqueta（相对左摇杆 ±90°）")
    skill = skill_of(cfg, "Croqueta")
    facing = 0.0     # 面朝上：相对朝向 +90° 是右侧，-90°（270°）是左侧
    tol = float(skill.params.get("tolerance_deg", 10.0))
    hold_ms = float(skill.params["steps"][0]["hold_ms"])
    step_ms = 4.0
    for angle, label in ((90.0, "右侧 90°"), (270.0, "左侧 90°")):
        det = SequenceDetector(skill)
        frames = flick(0.0, angle, hold_ms=600, facing=facing, buttons=("LB",))
        hit = run_detector(det, frames)
        check(f"按住 L1 + RS 相对朝向偏{label}并保持 600ms -> 触发",
              hit is not None, f"耗时 {hit.elapsed_ms:.0f}ms" if hit else "未触发")
        check(f"成功摘要：{label} 记录实际角度和保持时长",
              hit is not None and "°" in hit.summary
              and "保持" in hit.summary and "保持 0ms" not in hit.summary,
              hit.summary if hit else "未触发")
    # 容错窗口：目标是 ±90°，容差从配置读（当前 10° 即 80°~100°）
    right = 90.0
    for delta, expect in ((-tol, True), (tol, True),
                          (-tol - 5, False), (tol + 5, False)):
        det = SequenceDetector(skill)
        frames = flick(0.0, right + delta, hold_ms=600,
                       facing=facing, buttons=("LB",))
        hit = run_detector(det, frames)
        check(f"相对角度 {right + delta:.0f}° -> {'触发' if expect else '不触发'}"
              f"（窗口 {right - tol:.0f}~{right + tol:.0f}°）",
              (hit is not None) == expect)
    # 保持门槛从配置里读。250Hz 下每帧 4ms，多给两帧才真正越过门槛
    det = SequenceDetector(skill)
    frames = flick(0.0, right, hold_ms=hold_ms + 8, facing=facing, buttons=("LB",))
    check(f"保持到 {hold_ms:.0f}ms 门槛整 -> 触发（边界值）",
          run_detector(det, frames) is not None, f"hold_ms={hold_ms:.0f}")
    det = SequenceDetector(skill)
    frames = flick(0.0, right, hold_ms=150, facing=facing, buttons=("LB",))
    check("只推 150ms 就松手 -> 不触发（必须保持住）",
          run_detector(det, frames) is None)
    det = SequenceDetector(skill)
    frames = flick(0.0, right, hold_ms=hold_ms - 50, facing=facing, buttons=("LB",))
    check(f"推 {hold_ms - 50:.0f}ms 还差一点 -> 不触发",
          run_detector(det, frames) is None)
    # 真实手柄推杆有几十毫秒行程（幅度从 0 爬到 enter_threshold），
    # 保持计时从"推过门槛"才开始，所以用户嘴里的"推住半秒"实际只记到 ~450ms。
    ramp_frames = []
    t = 0.0
    for i in range(10):                      # 40ms 推杆行程
        ramp_frames.append(make_frame(t, rs_angle=right,
                                      rs_mag=0.90 * (i + 1) / 10.0,
                                      facing=facing, buttons=("LB",)))
        t += step_ms / 1000.0
    for _ in range(125):                     # 500ms 保持
        ramp_frames.append(make_frame(t, rs_angle=right, rs_mag=0.90,
                                      facing=facing, buttons=("LB",)))
        t += step_ms / 1000.0
    det = SequenceDetector(skill)
    check("真实手感：40ms 推杆行程 + 推住 500ms -> 触发",
          run_detector(det, ramp_frames) is not None)
    # 跑动中做油炸丸子：不管往哪跑，右摇杆都要相对左摇杆朝向偏 ±90°。
    for ls_angle, facing_now, label in ((90.0, 90.0, "向右跑动"),
                                        (270.0, 270.0, "向左跑动"),
                                        (45.0, 45.0, "向右前方跑动")):
        for offset, side in ((90.0, "右侧"), (-90.0, "左侧")):
            rs_angle = facing_now + offset
            det = SequenceDetector(skill)
            frames = [make_frame(i * step_ms / 1000.0, rs_angle=rs_angle,
                                 rs_mag=0.9, facing=facing_now,
                                 buttons=("LB",),
                                 ls_angle=ls_angle, ls_mag=0.8)
                      for i in range(150)]
            check(f"{label}时 RS 相对朝向偏{side} 90° -> 触发",
                  run_detector(det, frames) is not None,
                  f"LS={facing_now:.0f}° RS={rs_angle:.0f}°")
    # 相对判定必须是真的拿 LS 当基准：同一根绝对方向的杆位不可能同时算两侧
    det = SequenceDetector(skill)
    frames = [make_frame(i * step_ms / 1000.0, rs_angle=facing_now + 135.0,
                         rs_mag=0.9, facing=facing_now, buttons=("LB",),
                         ls_angle=facing_now, ls_mag=0.8)
              for i in range(150)]
    check("向右跑动时 RS 偏 135°（相对）-> 不触发（不是 90°）",
          run_detector(det, frames) is None)
    # 没起手时推错方向，status() 要直接把当前相对角度说出来，方便排查
    det = SequenceDetector(skill)
    for f in flick(0.0, 0.0, hold_ms=200, facing=facing, buttons=("LB",)):
        det.update(f)
        if det._last_mag >= det.enter:
            text = det.status()
            break
    else:
        text = det.status()
    check("推正前方时 status 提示\"方向不对\"并给出角度",
          "方向不对" in text and "当前相对 0°" in text, text)
    det = SequenceDetector(skill)
    det.observe(make_frame(0.0, rs_angle=90.0, rs_mag=0.9, buttons=()))
    det.reset()
    check("没按 L1 但 90° 方向对 -> status 提示按住 L1",
          det.status() == "方向对了，要按住 L1", det.status())
    det = SequenceDetector(skill_of(cfg, "磕球"))
    det.update(make_frame(0.0, rs_angle=90.0, rs_mag=0.9))
    check("无修饰键的动作空闲时不显示方向提示（避免刷屏）",
          det.status() == "待机", det.status())
    # 一直按着不放不该反复震
    det = SequenceDetector(skill)
    frames = flick(0.0, right, hold_ms=2000, facing=facing, buttons=("LB",))
    hits = [h for h in (det.update(f) for f in frames) if h is not None]
    check("按住不放 2 秒 -> 只触发一次", len(hits) == 1, f"实际 {len(hits)} 次")
    # 修饰键过滤是引擎层的职责（识别器本身不认识按键），所以这里直接测引擎的判定
    check("引擎层：不按 L1 -> 该动作被过滤",
          not Engine._buttons_ok(skill, frozenset()))
    check("引擎层：按住 L1 -> 该动作放行",
          Engine._buttons_ok(skill, frozenset({"LB"})))
    check("引擎层：按住 L1+R1 仍然放行（all 模式下多按不影响）",
          Engine._buttons_ok(skill, frozenset({"LB", "RB"})))
    det = SequenceDetector(skill)
    frames = flick(0.0, 0.0, hold_ms=600, facing=facing, buttons=("LB",))   # 正前方
    check("按住 L1 但 RS 推正前方 -> 不触发（不是侧向 90°）",
          run_detector(det, frames) is None)
    # 保持过程中方向跑偏 -> 保持计时重新开始
    det = SequenceDetector(skill)
    frames = (flick(0.0, right, hold_ms=120, facing=facing, buttons=("LB",)) +
              flick(0.22, right, hold_ms=600, facing=facing, buttons=("LB",)))
    check("保持 120ms 后松手、再保持 600ms -> 触发（重新计时后攒够，总时长仍在上限内）",
          run_detector(det, frames) is not None)
    # 引擎层验证修饰键松开时进度会被清空
    det = SequenceDetector(skill)
    frames = flick(0.0, right, hold_ms=600, facing=facing, buttons=("LB",))[:20]
    for f in frames:
        det.update(f)
    check("保持到一半时进度确实在进行中", det.index == 0 and det.t0 is not None)
    det.reset()
    check("修饰键中途松开 -> 识别进度被重置",
          det.index == 0 and det.t0 is None and det._hold_since is None)

def test_no_retrigger_while_held(cfg) -> None:
    """回归用例：用户报"往左扳着不动就一直震"。

    两条触发路径都要堵上：
      · L1 有一帧读数抖动 -> 引擎调 reset() -> 不该把摇杆当成"已回中"
      · 摇杆幅度在阈值附近抖一下 -> 不该被当成"已经松手"
    """
    print("\n[7] 回归：按住不放不能反复触发")
    skill = skill_of(cfg, "Croqueta")
    facing = 0.0

    def hold(t0: float, seconds: float, angle: float = 270.0, mag: float = 0.9):
        """持续按住，不回中。返回 (帧列表, 结束时刻)。"""
        out = []
        t = t0
        for _ in range(int(seconds * 250)):
            out.append(make_frame(t, rs_angle=angle, rs_mag=mag,
                                  facing=facing, buttons=("LB",)))
            t += 0.004
        return out, t

    # 1) 单纯按住 5 秒
    frames, _ = hold(0.0, 5.0)
    det = SequenceDetector(skill)
    check("按住 5 秒不动 -> 只触发一次",
          sum(1 for f in frames if det.update(f) is not None) == 1)

    # 2) 按住不动，但 L1 每 0.6 秒闪断一帧（引擎会在松键时调 reset()）
    det = SequenceDetector(skill)
    hits, t = 0, 0.0
    for _ in range(5):
        frames, t = hold(t, 0.6)
        for f in frames:
            hits += det.update(f) is not None
        det.reset()                      # 模拟引擎在按键读数丢失时的行为
    check("按住不动 + L1 每 0.6s 闪断一帧 -> 只触发一次", hits == 1, f"实际 {hits} 次")

    # 3) 按住不动，幅度短暂抖到 0.3（低于 release_threshold）
    det = SequenceDetector(skill)
    hits, t = 0, 0.0
    for _ in range(5):
        frames, t = hold(t, 0.6)
        for f in frames:
            hits += det.update(f) is not None
        frames, t = hold(t, 0.05, mag=0.3)
        for f in frames:
            hits += det.update(f) is not None
    check("按住不动 + 幅度抖到 0.3 共 50ms -> 只触发一次", hits == 1, f"实际 {hits} 次")

    # 4) 反向对照：真的松手够久，再做第二次，应该能触发第二次
    det = SequenceDetector(skill)
    first, t = hold(0.0, 1.0)
    release = [make_frame(t + i * 0.004, rs_mag=0.0, facing=facing) for i in range(75)]
    second, _ = hold(t + 0.3, 1.0)
    hits = sum(1 for f in (first + release + second) if det.update(f) is not None)
    check("松手 300ms 后再做一次 -> 应该触发两次（不能因防重复而失灵）",
          hits == 2, f"实际 {hits} 次")


def test_idle_reset(cfg) -> None:
    """用户报的问题：中间停了 1~2 秒，上一个动作的结尾被当成下一个动作的开头。"""
    print("\n[7b] 停顿超时 -> 未完成的进度作废")

    roulette = skill_of(cfg, "马赛回旋")
    # 从后往前转到一半（累计 110°，还没进 150~220 区间），停住不动 800ms，再转完剩下的
    frames = rotate(0.0, 180.0, 110.0, 150.0)
    frames += [make_frame(0.15 + i * 0.004, rs_angle=290.0, rs_mag=0.92) for i in range(200)]
    frames += rotate(0.95, 290.0, 90.0, 120.0)
    det = ArcDetector(roulette)
    hits = [h for h in (det.update(f) for f in frames) if h is not None]
    check("画弧画到一半停 800ms 再转完 -> 不触发（中间断掉了）",
          len(hits) == 0, f"实际 {len(hits)} 次")
    check("画弧中途停顿 -> 识别器被作废、等回中才重新武装",
          det.armed is False and det.active is False)

    # 对照：一口气转完就该触发
    det = ArcDetector(roulette)
    hits = [h for h in (det.update(f) for f in rotate(0.0, 180.0, 200.0, 500.0))
            if h is not None]
    check("对照：一口气转完 200°/500ms -> 触发", len(hits) == 1, f"实际 {len(hits)} 次")

    # 序列类：这是"上一个动作的结尾接成下一个动作的开头"最容易出问题的地方——
    # 回中之后 index 会一直留着，停多久都还记得"已经点过第一下了"。
    heel = skill_of(cfg, "磕球")
    facing = 90.0

    def two_flicks(gap_ms: float):
        first = flick(0.0, 90.0, hold_ms=250, facing=facing)  # 前（0~330ms）
        t = 0.33
        gap = [make_frame(t + i * 0.004, rs_mag=0.0, facing=facing)
               for i in range(int(gap_ms / 4))]           # 回中不动
        t += gap_ms / 1000.0
        return first + gap + flick(t, 270.0, facing=facing)   # 后

    det = SequenceDetector(heel)
    hits = [h for h in (det.update(f) for f in two_flicks(150)) if h is not None]
    check("磕球：两步之间停 150ms -> 触发（总时长过 300ms 下限）",
          len(hits) == 1, f"实际 {len(hits)} 次")

    det = SequenceDetector(heel)
    hits = [h for h in (det.update(f) for f in two_flicks(1500)) if h is not None]
    check("磕球：两步之间停了 1.5 秒 -> 不触发（进度已清空，不能接起来）",
          len(hits) == 0, f"实际 {len(hits)} 次")


def test_min_duration(cfg) -> None:
    print("\n[7c] 最小时长 —— 太快不算搓招")
    roulette = skill_of(cfg, "马赛回旋")

    det = ArcDetector(roulette)
    check("马赛回旋：80ms 内甩完 200° -> 不触发",
          run_detector(det, rotate(0.0, 180.0, 200.0, 80.0)) is None)

    det = ArcDetector(roulette)
    check("马赛回旋：500ms 转完 200° -> 触发",
          run_detector(det, rotate(0.0, 180.0, 200.0, 500.0)) is not None)

    heel = skill_of(cfg, "磕球")
    facing = 90.0
    det = SequenceDetector(heel)
    # 30ms 内点两下：整体太快
    fast = ([make_frame(i * 0.004, rs_angle=90.0, rs_mag=0.9, facing=facing) for i in range(4)]
            + [make_frame((4 + i) * 0.004, rs_mag=0.0, facing=facing) for i in range(4)]
            + [make_frame((8 + i) * 0.004, rs_angle=270.0, rs_mag=0.9, facing=facing)
               for i in range(4)])
    check("磕球：30ms 内点完前后两下 -> 不触发（太快）",
          run_detector(det, fast) is None)


# ---------------------------------------------------------------------------
# 引擎层：真实时间轴 + 冷却 + 震动派发
# ---------------------------------------------------------------------------

class NullSource(GamepadSource):
    """只用于构造引擎；测试里直接手工喂 _tick。"""

    name = "空手柄"
    layout_source = "测试"

    def poll(self) -> PadState:
        return PadState()


def tick(engine, t: float, rs_angle: float = 0.0, rs_mag: float = 0.0,
         buttons: Iterable[str] = (), ls_angle: float = 0.0,
         ls_mag: float = 0.9) -> None:
    """按给定的绝对时间手工驱动一帧引擎。

    默认左摇杆推正前方：引擎现在要求"有朝向"才判定方向类动作。
    """
    x, y = stick(rs_angle, rs_mag) if rs_mag > 0 else (0.0, 0.0)
    lx, ly = stick(ls_angle, ls_mag) if ls_mag > 0 else (0.0, 0.0)
    state = PadState(ls_x=lx, ls_y=ly, rs_x=x, rs_y=y,
                     buttons=frozenset(buttons))
    engine._tick(t, state)


class SpyDetector:
    """包一层识别器，数一数引擎到底调了几次 on_idle()。"""

    def __init__(self, inner):
        self.inner = inner
        self.idle_calls = 0

    def update(self, frame):
        return self.inner.update(frame)

    def reset(self):
        self.inner.reset()

    def on_idle(self):
        self.idle_calls += 1
        self.inner.on_idle()

    def pop_failure(self):
        return self.inner.pop_failure()

    def abandon(self):
        self.inner.abandon()
    def observe(self, frame):
        self.inner.observe(frame)

    def status(self):
        return self.inner.status()


def test_button_taps(cfg) -> None:
    print()
    print("[6b] 按键双击 —— 绿色搓射（修饰键 + 两下 X，间隔 400~600ms）")
    skill = skill_of(cfg, "绿色")
    check("绿色搓射：类型 taps、默认修饰键 RB、连按 X",
          skill.kind == "taps" and skill.required_buttons == ("RB",)
          and skill.params.get("button") == "X",
          f"{skill.kind} {skill.required_buttons} {skill.params.get('button')}")
    check("绿色搓射：相对朝向关闭（跟左摇杆无关）",
          skill.relative_to_ls is False)
    check("绿色搓射：界面可选 RB / RT",
          tuple(skill.params.get("modifier_options") or ()) == ("RB", "RT"),
          str(skill.params.get("modifier_options")))

    active_name = "绿色"

    def green(engine):
        return next(a for a in engine.skills if active_name in a.skill.name)

    def use(engine, button: str):
        act = green(engine)
        act.skill.required_buttons = (button,)
        act.detector.set_modifier(button)

    engine = run_taps(cfg, 450)
    act = green(engine)
    outcome = engine.last_outcome
    check("按住 RB，两下 X 间隔 450ms -> 触发",
          act.hits == 1 and outcome is not None and outcome.ok,
          f"hits={act.hits}")
    check("成功摘要记录两下间隔",
          outcome is not None and "两下 X 间隔" in outcome.detail,
          outcome.detail if outcome else "无结果")
    check("触发时其他动作没有被误判",
          sum(a.hits for a in engine.skills if a is not act) == 0)
    check("绿色搓射成功也计入 10 个一组的进度",
          act.group_hits == 1)

    engine = run_taps(cfg, 400)
    outcome = engine.last_outcome
    check("两下正好隔 400ms（下限）-> 触发",
          green(engine).hits == 1 and outcome is not None and outcome.ok,
          outcome.detail if outcome else "无结果")

    engine = run_taps(cfg, 600)
    outcome = engine.last_outcome
    check("两下正好隔 600ms（上限）-> 触发",
          green(engine).hits == 1 and outcome is not None and outcome.ok,
          outcome.detail if outcome else "无结果")

    engine = run_taps(cfg, 300)
    outcome = engine.last_outcome
    check("两下只隔 300ms -> too_fast",
          green(engine).hits == 0 and outcome is not None
          and outcome.code == "too_fast",
          outcome.message if outcome else "无结果")

    engine = run_taps(cfg, 700)
    outcome = engine.last_outcome
    check("两下隔 700ms -> too_slow",
          green(engine).hits == 0 and outcome is not None
          and outcome.code == "too_slow",
          outcome.message if outcome else "无结果")

    engine = run_taps(cfg, 400, second=False)
    outcome = engine.last_outcome
    check("等了超过 600+150ms 还没有第二下 -> too_slow",
          green(engine).hits == 0 and outcome is not None
          and outcome.code == "too_slow",
          outcome.message if outcome else "无结果")

    engine = run_taps(cfg, 450, rb_release_at=200)
    outcome = engine.last_outcome
    check("两下之间松开 RB -> hold_short",
          green(engine).hits == 0 and outcome is not None
          and outcome.code == "hold_short",
          outcome.message if outcome else "无结果")

    engine = run_taps(cfg, 450, rb=False)
    check("全程不按 RB -> 不触发", green(engine).hits == 0,
          f"hits={green(engine).hits}")

    # 选择 RT 之后，判定必须改用 RT：按 RT 成功，按 RB 不算
    engine = Engine(cfg, NullSource(), RumbleEngine(None, enabled=False),
                    debug=False)
    use(engine, "RT")
    for f in tap_frames(0.0, 450, modifier="RT"):
        tick(engine, f.now, buttons=f.buttons, ls_mag=0.0)
    act = green(engine)
    check("切换到 RT：按住 RT + 两下 X 450ms -> 触发",
          act.hits == 1, f"hits={act.hits}")

    engine = Engine(cfg, NullSource(), RumbleEngine(None, enabled=False),
                    debug=False)
    use(engine, "RT")
    for f in tap_frames(0.0, 450, modifier="RB"):
        tick(engine, f.now, buttons=f.buttons, ls_mag=0.0)
    check("切换到 RT 后只按 RB -> 不触发",
          green(engine).hits == 0, f"hits={green(engine).hits}")

    # Skill 对象被所有 Engine 共享，后续用例恢复默认的 RB
    skill.required_buttons = ("RB",)

    # 先按着 X 再按 RB：不能把"一直按着的 X"当成第一下
    engine = Engine(cfg, NullSource(), RumbleEngine(None, enabled=False),
                    debug=False)
    t = 0.0
    for btns in (("X",), ("X", "RB"), ("RB",)):
        for _ in range(25):
            tick(engine, t, buttons=btns, ls_mag=0.0)
            t += 0.004
    for f in tap_frames(t, 450):
        tick(engine, f.now, buttons=f.buttons, ls_mag=0.0)
    act = green(engine)
    check("先按住 X 再按 RB -> 不会误把旧按键当第一下",
          act.hits == 1, f"hits={act.hits}")

    # 第一下之后卡片状态要告诉用户还差第二下
    engine = Engine(cfg, NullSource(), RumbleEngine(None, enabled=False),
                    debug=False)
    frames = tap_frames(0.0, 450)
    for f in frames[:90]:                  # 100ms 前奏 + 约 240ms 等待（还没到第二下）
        tick(engine, f.now, buttons=f.buttons, ls_mag=0.0)
    status = green(engine).detector.status()
    check("第一下之后实时状态显示『等第二下』和目标窗口",
          "等第二下" in status and "400~600" in status, status)


def test_engine_gesture_lock(cfg) -> None:
    """一次动作触发后要回中才允许下一个；长时间不动则清空进度。"""
    print("\n[8b] 引擎层：手势锁 + 全局空闲清零")
    backend = RecordingBackend()
    rumble = RumbleEngine(backend, enabled=True)
    engine = Engine(cfg, NullSource(), rumble, debug=False)

    # 一段从后往前的弧（500ms）触发马赛回旋
    for f in rotate(0.0, 180.0, 200.0, 500.0):
        tick(engine, f.now, f.rs_angle, f.rs_mag)
    hits = {a.skill.name: a.hits for a in engine.skills}
    check("画完一段弧 -> 马赛回旋触发一次",
          hits[skill_of(cfg, "马赛回旋").name] == 1, f"实际 {hits}")

    # 不回中，紧接着再画一段完全相同的弧：手势锁应该挡住
    for f in rotate(0.50, 180.0, 200.0, 500.0):
        tick(engine, f.now, f.rs_angle, f.rs_mag)
    hits = {a.skill.name: a.hits for a in engine.skills}
    check("不回中接着再画一段 -> 不重复触发",
          hits[skill_of(cfg, "马赛回旋").name] == 1, f"实际 {hits}")

    # 回中并保持 200ms（> gesture_release_ms=150）解锁
    for i in range(60):
        tick(engine, 1.00 + i * 0.004, rs_mag=0.0)
    check("回中保持 200ms 后解锁", engine._gesture_locked is False)

    # 解锁后再画一次，应该能正常触发
    for f in rotate(1.30, 180.0, 200.0, 500.0):
        tick(engine, f.now, f.rs_angle, f.rs_mag)
    hits = {a.skill.name: a.hits for a in engine.skills}
    check("解锁后再画一次 -> 正常触发第二次",
          hits[skill_of(cfg, "马赛回旋").name] == 2, f"实际 {hits}")

    # 全局空闲清零：摇杆归中超过 idle_reset_ms 后，所有识别器进度作废（且只作废一次）
    engine2 = Engine(cfg, NullSource(), RumbleEngine(None, enabled=False), debug=False)
    spies = []
    for active in engine2.skills:
        spy = SpyDetector(active.detector)
        active.detector = spy
        spies.append(spy)

    for i in range(25):                             # 归中 100ms < idle_reset_ms=250
        tick(engine2, i * 0.004, rs_mag=0.0)
    check("归中 100ms 还不算空闲 -> 没有触发清零",
          all(s.idle_calls == 0 for s in spies),
          f"实际 {[s.idle_calls for s in spies]}")

    for i in range(25, 100):                        # 累计归中 400ms > 250
        tick(engine2, i * 0.004, rs_mag=0.0)
    check("归中累计超过 idle_reset_ms -> 每个识别器各清零一次",
          all(s.idle_calls == 1 for s in spies),
          f"实际 {[s.idle_calls for s in spies]}")

    for i in range(100, 200):                       # 继续归中，不该反复清零
        tick(engine2, i * 0.004, rs_mag=0.0)
    check("继续归中 -> 不重复清零",
          all(s.idle_calls == 1 for s in spies),
          f"实际 {[s.idle_calls for s in spies]}")

    for f in rotate(1.0, 0.0, 0.0, 4.0):            # 重新推摇杆
        tick(engine2, f.now, f.rs_angle, f.rs_mag)
    for i in range(25):                             # 再归中 100ms
        tick(engine2, 1.01 + i * 0.004, rs_mag=0.0)
    check("重新推过摇杆后，空闲计时重新开始",
          all(s.idle_calls == 1 for s in spies),
          f"实际 {[s.idle_calls for s in spies]}")


def test_engine_facing_and_group(cfg) -> None:
    """左摇杆回中 = 没有朝向；每 10 个正确动作一组。"""
    print("\n[8c] 引擎层：左摇杆朝向 + 每 10 个一组")

    # 左摇杆回中：右摇杆画得再标准也不算，因为没有方向基准
    engine = Engine(cfg, NullSource(), RumbleEngine(None, enabled=False),
                    debug=False)
    for f in rotate(0.0, 180.0, 200.0, 500.0):
        tick(engine, f.now, f.rs_angle, f.rs_mag, ls_mag=0.0)
    check("左摇杆回中 -> 方向类动作不触发",
          sum(a.hits for a in engine.skills) == 0)
    check("左摇杆回中 -> 朝向标记为无效", engine.facing_valid is False)

    # 同一段轨迹，推着左摇杆就应该触发
    for f in rotate(1.0, 180.0, 200.0, 500.0):
        tick(engine, f.now, f.rs_angle, f.rs_mag)
    check("推着左摇杆 -> 同一段弧正常触发",
          sum(a.hits for a in engine.skills) == 1,
          f"实际 {sum(a.hits for a in engine.skills)} 次")

    # 每做对 10 个，本组进度清零，并记一组完成
    engine = Engine(cfg, NullSource(), RumbleEngine(None, enabled=False),
                    debug=False)
    active = next(a for a in engine.skills if "马赛" in a.skill.name)
    t = 0.0
    for _ in range(Engine.GROUP_SIZE):
        for f in rotate(t, 180.0, 200.0, 500.0):
            tick(engine, f.now, f.rs_angle, f.rs_mag)
        t += 0.5
        for i in range(100):                     # 回中 400ms，解锁手势
            tick(engine, t + i * 0.004, rs_mag=0.0)
        t += 0.4
    check("做对 10 个 -> 本组清零、记完成一组",
          active.hits == Engine.GROUP_SIZE
          and active.group_hits == 0 and active.groups_done == 1,
          f"hits={active.hits} group={active.group_hits} "
          f"groups={active.groups_done}")

    engine.reset_stats()
    check("R 重置 -> 组进度和完成组数一起清零",
          active.group_hits == 0 and active.groups_done == 0)

    # 按住 L1 时只判定油炸丸子：同样一段马赛回旋轨迹不能再被认成马赛回旋
    engine = Engine(cfg, NullSource(), RumbleEngine(None, enabled=False),
                    debug=False)
    for f in rotate(0.0, 180.0, 200.0, 500.0):
        tick(engine, f.now, f.rs_angle, f.rs_mag, buttons=("LB",))
    roulette = next(a for a in engine.skills if "马赛" in a.skill.name)
    check("按住 L1 时不判定其他动作（马赛回旋不触发）",
          roulette.hits == 0, f"实际 {roulette.hits} 次")

    # 松开 L1、右摇杆回中后，同一段轨迹恢复正常判定
    for i in range(150):
        tick(engine, 0.5 + i * 0.004, rs_mag=0.0)
    for f in rotate(1.10, 180.0, 200.0, 500.0):
        tick(engine, f.now, f.rs_angle, f.rs_mag)
    check("松开 L1 后马赛回旋恢复判定", roulette.hits == 1,
          f"实际 {roulette.hits} 次")


class RecordingBackend(RumbleBackend):
    label = "测试用记录后端"

    def __init__(self):
        self.pulses: List[Tuple[float, float, int]] = []

    def start(self, low, high, duration_ms):
        self.pulses.append((low, high, duration_ms))
        return True


class ScriptedSource(GamepadSource):
    """按真实时间播放一段脚本化轨迹。"""

    name = "脚本化测试手柄"
    layout_source = "测试"

    def __init__(self, segments, total: float):
        # segments: [(t_start, t_end, rs_angle, rs_mag, buttons)]
        self.segments = segments
        self.total = total
        self.t0 = time.perf_counter()
        self.polls = 0

    def poll(self) -> PadState:
        self.polls += 1
        t = time.perf_counter() - self.t0
        for start, end, angle, mag, buttons in self.segments:
            if start <= t < end:
                x, y = stick(angle, mag)
                return PadState(rs_x=x, rs_y=y, buttons=frozenset(buttons))
        return PadState()


def test_engine_end_to_end(cfg) -> None:
    print("\n[8] 引擎端到端（真实时间轴 + 冷却 + 震动派发）")
    backend = RecordingBackend()
    rumble = RumbleEngine(backend, enabled=True)
    rumble.start()

    # 0.10s~0.60s 之间从"后(180°)"匀速画一个 200° 的弧，其余时间摇杆归中
    start, end, sweep = 0.10, 0.60, 200.0

    class RotatingSource(ScriptedSource):
        def poll(self):
            self.polls += 1
            t = time.perf_counter() - self.t0
            if start <= t <= end:
                angle = 180.0 + sweep * (t - start) / (end - start)
                x, y = stick(angle, 0.92)
                return PadState(ls_y=-0.9, rs_x=x, rs_y=y)
            return PadState()

    source = RotatingSource(segments=[], total=1.0)
    engine = Engine(cfg, source, rumble, debug=False)
    engine.run(duration=0.9)
    rumble.close()

    hits = {a.skill.name: a.hits for a in engine.skills}
    roulette = hits[skill_of(cfg, "马赛回旋").name]
    check("真实时间轴下画弧 -> 马赛回旋触发一次", roulette == 1, f"实际 {roulette} 次")
    outcome = engine.last_outcome
    check("成功结果带上旋转摘要（供界面/日志调参）",
          outcome is not None and outcome.ok and "旋转" in outcome.detail,
          outcome.detail if outcome is not None else "无结果")
    check("震动后端收到 1 次震动", len(backend.pulses) == 1,
          f"实际 {len(backend.pulses)} 次 {backend.pulses}")
    check("采样频率接近 250Hz", abs(engine.frames / 0.9 - 250) < 25,
          f"实际 {engine.frames / 0.9:.0f}Hz")


class TimelineBackend(RumbleBackend):
    """记录"什么时候开、什么时候关"，用来验证震动状态机的时序。"""

    label = "时间线后端"

    def __init__(self):
        self.events: List[tuple] = []

    def start(self, low, high, duration_ms):
        self.events.append(("start", round(low, 2), round(high, 2), duration_ms))
        return True

    def stop(self):
        self.events.append(("stop",))


def drive(engine, seconds: float, t0: float = 0.0, step: float = 0.004) -> float:
    """以 4ms 步进模拟主循环驱动震动状态机。"""
    t = t0
    end = t0 + seconds
    while t < end:
        engine.update(t)
        t += step
    return t


def test_rumble_state_machine() -> None:
    print("\n[9] 震动状态机（单脉冲，主循环驱动，非阻塞）")

    backend = TimelineBackend()
    engine = RumbleEngine(backend, enabled=True)
    engine.play((Pulse(0.5, 0.9, 100),), 0.0)
    drive(engine, 0.3)
    check("单震：只开一次、关一次",
          [e[0] for e in backend.events] == ["start", "stop"], f"实际 {backend.events}")
    check("震动参数正确传递",
          backend.events[0][1:] == (0.5, 0.9, 100), f"{backend.events[0]}")

    # 统一动作时长：120ms 的震动必须在 120ms 前后停，不能拖长
    backend = TimelineBackend()
    engine = RumbleEngine(backend, enabled=True)
    engine.play((Pulse(0.8, 0.0, 120),), 0.0)
    drive(engine, 0.1)                       # 只走 100ms，应该还在震
    still_on = engine._active
    drive(engine, 0.1, t0=0.1)               # 再走 100ms，应该已经停了
    check("统一 120ms 单震：100ms 时还在震、200ms 时已经停",
          still_on and not engine._active and backend.events[-1][0] == "stop",
          f"100ms时={still_on} 200ms时={engine._active}")

    # 只取第一个脉冲：多脉冲写法不再连播
    backend = TimelineBackend()
    engine = RumbleEngine(backend, enabled=True)
    engine.play((Pulse(0.4, 0.9, 60, gap_ms=50), Pulse(0.4, 0.9, 60)), 0.0)
    drive(engine, 0.5)
    check("多脉冲只播第一个（不再排队连震）",
          [e[0] for e in backend.events] == ["start", "stop"],
          f"实际 {[e[0] for e in backend.events]}")

    # 上一次还没震完就来的新触发：直接丢掉，不排队
    backend = TimelineBackend()
    engine = RumbleEngine(backend, enabled=True)
    engine.play((Pulse(0.5, 0.0, 200),), 0.0)
    again = engine.play((Pulse(0.5, 0.0, 200),), 0.05)
    drive(engine, 0.5)
    check("上一次震动未完时的触发被丢弃，不排队",
          again is False and engine.dropped == 1
          and [e[0] for e in backend.events] == ["start", "stop"],
          f"dropped={engine.dropped} events={[e[0] for e in backend.events]}")

    # 震完之后可以正常再震一次
    backend = TimelineBackend()
    engine = RumbleEngine(backend, enabled=True)
    engine.play((Pulse(0.5, 0.0, 120),), 0.0)
    drive(engine, 0.2, t0=0.0)
    engine.play((Pulse(0.5, 0.0, 120),), 0.2)
    drive(engine, 0.3, t0=0.2)
    check("上一次震完之后再触发 -> 正常再震一次",
          [e[0] for e in backend.events] == ["start", "stop", "start", "stop"],
          f"实际 {[e[0] for e in backend.events]}")

    backend = TimelineBackend()
    engine = RumbleEngine(backend, enabled=False)
    check("禁用时 play() 返回 False", engine.play((Pulse(),), 0.0) is False)
    drive(engine, 0.2)
    check("禁用时不产生任何震动事件", backend.events == [])

    class FailingBackend(RumbleBackend):
        label = "失败后端"

        def start(self, low, high, duration_ms):
            return False

        def stop(self):
            pass

    engine = RumbleEngine(FailingBackend(), enabled=True)
    check("后端返回失败 -> play() 返回 False", engine.play((Pulse(0.5, 0.9, 60),), 0.0) is False)
    drive(engine, 0.2)
    check("后端返回失败 -> 计数并记录原因，不再假装成功",
          engine.failures == 1 and "报错" in engine.health(),
          engine.health())

    class ExplodingBackend(RumbleBackend):
        label = "抛异常后端"

        def start(self, low, high, duration_ms):
            raise RuntimeError("模拟硬件错误")

        def stop(self):
            pass

    engine = RumbleEngine(ExplodingBackend(), enabled=True)
    try:
        engine.play((Pulse(0.5, 0.9, 60),), 0.0)
        drive(engine, 0.2)
        check("后端抛异常 -> 不冒泡到主循环，计入 failures", engine.failures >= 1)
    except Exception as exc:
        check("后端抛异常 -> 不冒泡到主循环，计入 failures", False, f"异常冒泡: {exc}")

    backend = TimelineBackend()
    engine = RumbleEngine(backend, enabled=True)
    engine.play((Pulse(0.5, 0.9, 5000),), 0.0)
    t0 = time.perf_counter()
    engine.update(0.0)
    dt = time.perf_counter() - t0
    check("5 秒长的震动，update() 也立即返回（非阻塞）",
          dt < 0.01, f"耗时 {dt * 1000:.2f}ms")


def test_config_validation() -> None:
    print("\n[10] 配置校验")
    import copy
    base = copy.deepcopy(DEFAULT_CONFIG)

    def expect_error(label, mutate):
        data = copy.deepcopy(base)
        mutate(data)
        try:
            parse_config(data)
            check(label, False, "居然没报错")
        except ValueError as exc:
            check(label, True, str(exc)[:60])

    expect_error("type 写错 -> 报错",
                 lambda d: d["skills"][0].__setitem__("type", "circle"))
    expect_error("sequence 缺 steps -> 报错",
                 lambda d: d["skills"][skill_index(d, "磕球")]["params"].pop("steps"))
    expect_error("方向名写错 -> 报错",
                 lambda d: d["skills"][skill_index(d, "磕球")]["params"].__setitem__(
                     "steps", ["forward", "backwards!"]))
    expect_error("动作重名 -> 报错",
                 lambda d: d["skills"][1].__setitem__("name", d["skills"][0]["name"]))
    expect_error("min_angle >= max_angle -> 报错",
                 lambda d: d["skills"][0]["params"].update(min_angle=300, max_angle=200))
    expect_error("震动强度超出 0~1 -> 报错",
                 lambda d: d["skills"][0]["rumble"].__setitem__("low", 1.5))
    expect_error("按键名不认识 -> 报错",
                 lambda d: d["skills"][skill_index(d, "Croqueta")].__setitem__("required_button", "L9"))
    expect_error("hold_ms 之和 >= max_duration_ms（永远触发不了）-> 报错",
                 lambda d: d["skills"][skill_index(d, "Croqueta")]["params"].__setitem__(
                     "steps", [{"direction": ["left", "right"], "hold_ms": 2000}]))
    expect_error("hold_ms 为负数 -> 报错",
                 lambda d: d["skills"][skill_index(d, "Croqueta")]["params"].__setitem__(
                     "steps", [{"direction": "left", "hold_ms": -100}]))
    expect_error("步骤对象缺少 direction -> 报错",
                 lambda d: d["skills"][skill_index(d, "Croqueta")]["params"].__setitem__(
                     "steps", [{"hold_ms": 300}]))
    expect_error("start_angle 写成不存在的方向名 -> 报错",
                 lambda d: d["skills"][0]["params"].__setitem__("start_angle", "sideways"))
    expect_error("end_angle 写成不存在的方向名 -> 报错",
                 lambda d: d["skills"][0]["params"].__setitem__("end_angle", "sideways"))
    expect_error("end_angle 写成空数组 -> 报错",
                 lambda d: d["skills"][0]["params"].__setitem__("end_angle", []))
    expect_error("idle_timeout_ms 为 0 -> 报错",
                 lambda d: d["skills"][0]["params"].__setitem__("idle_timeout_ms", 0))
    expect_error("release_hold_ms 为负数 -> 报错",
                 lambda d: d["skills"][0]["params"].__setitem__("release_hold_ms", -50))
    expect_error("max_duration_ms <= min_duration_ms -> 报错",
                 lambda d: d["skills"][0]["params"].update(
                     min_duration_ms=600, max_duration_ms=500))
    expect_error("taps 间隔上限 <= 下限 -> 报错",
                 lambda d: d["skills"][skill_index(d, "绿色")]["params"].update(
                     min_interval_ms=500, max_interval_ms=400))
    expect_error("taps 按键名写错 -> 报错",
                 lambda d: d["skills"][skill_index(d, "绿色")]["params"].__setitem__(
                     "button", "L9"))
    expect_error("modifier_options 不是数组 -> 报错",
                 lambda d: d["skills"][skill_index(d, "绿色")]["params"].__setitem__(
                     "modifier_options", "RB"))
    expect_error("modifier_options 为空 -> 报错",
                 lambda d: d["skills"][skill_index(d, "绿色")]["params"].__setitem__(
                     "modifier_options", []))
    expect_error("modifier_options 有重复按键 -> 报错",
                 lambda d: d["skills"][skill_index(d, "绿色")]["params"].__setitem__(
                     "modifier_options", ["RB", "RB"]))
    expect_error("required_button 不在 modifier_options 里 -> 报错",
                 lambda d: d["skills"][skill_index(d, "绿色")]["params"].__setitem__(
                     "modifier_options", ["RT", "LB"]))
    expect_error("input.invert 键名写错 -> 报错",
                 lambda d: d["input"].__setitem__("invert", {"right_y": True}))
    expect_error("input.invert 的值不是布尔 -> 报错",
                 lambda d: d["input"].__setitem__("invert", {"rs_y": 1}))

    data = copy.deepcopy(base)
    i = skill_index(data, "绿色")
    tap_skill = parse_config(data).skills[i]
    check("taps 类型能正常解析（RB + X，400~600ms，可选 RT）",
          tap_skill.kind == "taps"
          and tap_skill.required_buttons == ("RB",)
          and tap_skill.params["min_interval_ms"] == 400
          and tap_skill.params["max_interval_ms"] == 600
          and tap_skill.params["modifier_options"] == ["RB", "RT"],
          f"{tap_skill.kind} {tap_skill.required_buttons} "
          f"{tap_skill.params.get('modifier_options')}")

    data = copy.deepcopy(base)
    i = skill_index(data, "Croqueta")
    data["skills"][i]["params"]["steps"] = [{"direction": ["left", "right"], "hold_ms": 500}]
    cfg3 = parse_config(data)
    steps = cfg3.skills[i].params["steps"]
    check("dict 形式的步骤能正常解析（含 hold_ms）",
          isinstance(steps[0], dict) and steps[0]["hold_ms"] == 500)

    data = copy.deepcopy(base)
    data["input"]["idle_reset_ms"] = 400
    data["input"]["gesture_release_ms"] = 200
    cfg_in = parse_config(data)
    check("input.idle_reset_ms / gesture_release_ms 能正常解析并生效",
          cfg_in.input.idle_reset_ms == 400 and cfg_in.input.gesture_release_ms == 200,
          f"实际 {cfg_in.input.idle_reset_ms} / {cfg_in.input.gesture_release_ms}")

    data = copy.deepcopy(base)
    data["input"]["idle_reset_ms"] = 99999
    check("input.idle_reset_ms 超出上限 -> 被夹到 5000",
          parse_config(data).input.idle_reset_ms == 5000)

    data = copy.deepcopy(base)
    data["input"]["invert"] = {"rs_y": True}
    cfg_inv = parse_config(data)
    check("input.invert 能解析（用于纠正'右摇杆上下反了'）",
          cfg_inv.input.invert == {"rs_y": True}, str(cfg_inv.input.invert))

    lay = apply_axis_inverts(AxisLayout(), {"rs_y": True, "ls_x": False})
    check("apply_axis_inverts 只翻方向、不动轴索引",
          lay.invert_rs_y and not lay.invert_ls_x and lay.rs_y == 3,
          f"invert_rs_y={lay.invert_rs_y} rs_y={lay.rs_y}")

    data = copy.deepcopy(base)
    data["skills"][0]["required_button"] = "L1"       # 别名应被接受
    try:
        cfg2 = parse_config(data)
        check("required_button 用别名 'L1' -> 规范化为 LB",
              cfg2.skills[0].required_buttons == ("LB",))
    except ValueError as exc:
        check("required_button 用别名 'L1' -> 规范化为 LB", False, str(exc))


def test_failure_diagnostics(cfg) -> None:
    """失败也要说清楚原因，而且一次尝试只能报一条。"""
    print("\n[11] 失败诊断")
    roulette = skill_of(cfg, "马赛回旋")
    stepover = skill_of(cfg, "踩单车")
    heel = skill_of(cfg, "磕球")
    croqueta = skill_of(cfg, "Croqueta")

    def verdict(det, frames):
        run_detector(det, frames)
        return det.pop_failure()

    # --- 转得不够 ---
    det = ArcDetector(roulette)
    f = verdict(det, rotate(0.0, 180.0, 60.0, 150.0) + centered(0.15, 200))
    check("转得不够 -> too_short",
          f is not None and f.code == "too_short", f.message if f else "没有裁定")

    # --- 起点不对（在认领范围内，但超出 start_tolerance）---
    det = ArcDetector(roulette)
    f = verdict(det, rotate(0.0, 100.0, 200.0, 200.0) + centered(0.20, 200))
    check("起点偏了但看得出是这招 -> wrong_start",
          f is not None and f.code == "wrong_start", f.message if f else "没有裁定")

    # --- 起点离得太远 -> 保持安静，不要把锅算到马赛回旋头上 ---
    det = ArcDetector(roulette)
    f = verdict(det, rotate(0.0, 90.0, 90.0, 150.0) + centered(0.15, 200))
    check("起点离得太远 -> 不报这个动作的失败",
          f is None, f.message if f else "")

    det = ArcDetector(stepover)
    f = verdict(det, rotate(0.0, 90.0, 90.0, 150.0) + centered(0.15, 200))
    check("同一个起手点 -> 踩单车也不误报", f is None, f.message if f else "")

    # --- 太快 / 太慢 ---
    det = ArcDetector(roulette)
    f = verdict(det, rotate(0.0, 180.0, 200.0, 60.0) + centered(0.06, 200))
    check("60ms 甩完 200° -> too_fast",
          f is not None and f.code == "too_fast", f.message if f else "没有裁定")

    det = ArcDetector(roulette)
    f = verdict(det, rotate(0.0, 180.0, 200.0, 1400.0) + centered(0.90, 200))
    check("1400ms 才转完 200° -> too_slow",
          f is not None and f.code == "too_slow", f.message if f else "没有裁定")

    # --- 转多了（把终点容差收窄，让"进区间"和"终点对"不再重叠）---
    over = variant("马赛回旋", end_angle=90, end_tolerance=10)
    det = ArcDetector(over)
    f = verdict(det, rotate(0.0, 180.0, 300.0, 300.0) + centered(0.30, 200))
    check("累计超过 max_angle -> overshoot",
          f is not None and f.code == "overshoot", f.message if f else "没有裁定")

    # --- 终点不对 ---
    wrong_end = variant("马赛回旋", end_angle=0, end_tolerance=10)
    det = ArcDetector(wrong_end)
    f = verdict(det, rotate(0.0, 180.0, 160.0, 500.0) + centered(0.20, 200))
    check("角度够了但停在错的方向 -> wrong_end",
          f is not None and f.code == "wrong_end", f.message if f else "没有裁定")

    # --- 中途停住 ---
    det = ArcDetector(roulette)
    f = verdict(det, rotate(0.0, 180.0, 60.0, 60.0) + held(0.06, 240.0, 400.0))
    check("转一半停住不动 -> stalled",
          f is not None and f.code == "stalled", f.message if f else "没有裁定")

    # --- 方向反了 ---
    cw_only = variant("马赛回旋", direction="cw")
    det = ArcDetector(cw_only)
    f = verdict(det, rotate(0.0, 180.0, -200.0, 220.0) + centered(0.22, 200))
    check("direction=cw 却逆时针转 -> wrong_direction",
          f is not None and f.code == "wrong_direction", f.message if f else "没有裁定")

    # 回归：刚开始那一帧 acc=0，不能误判成"转向反了"
    det = ArcDetector(cw_only)
    hit = run_detector(det, held(0.0, 180.0, 8.0) + rotate(0.01, 180.0, 200.0, 500.0))
    check("direction=cw：起点静止两帧后再转 -> 正常触发、不误报方向",
          hit is not None and det.pop_failure() is None)

    # --- 序列：没做完 ---
    det = SequenceDetector(heel)
    f = verdict(det, flick(0.0, 90.0, facing=90.0) + centered(0.14, 400.0))
    check("磕球只点了第一下就停 -> incomplete",
          f is not None and f.code == "incomplete", f.message if f else "没有裁定")

    # --- 序列：正常步间回中不报错 ---
    det = SequenceDetector(heel)
    frames = flick(0.0, 90.0, hold_ms=250, facing=90.0) + flick(0.35, 270.0, facing=90.0)
    hit = run_detector(det, frames)
    check("磕球正常完成 -> 成功且没有任何失败裁定",
          hit is not None and det.pop_failure() is None)

    # --- 序列：太快 ---
    det = SequenceDetector(heel)
    fast = ([make_frame(i * 0.004, rs_angle=90.0, rs_mag=0.9, facing=90.0)
             for i in range(4)]
            + [make_frame((4 + i) * 0.004, rs_mag=0.0, facing=90.0) for i in range(4)]
            + [make_frame((8 + i) * 0.004, rs_angle=270.0, rs_mag=0.9, facing=90.0)
               for i in range(4)])
    f = verdict(det, fast)
    check("30ms 内点完前后两下 -> too_fast",
          f is not None and f.code == "too_fast", f.message if f else "没有裁定")

    # --- 保持不够：松手后放弃 ---
    det = SequenceDetector(croqueta)
    f = verdict(det, flick(0.0, 90.0, hold_ms=200, facing=0.0, buttons=("LB",))
                + centered(0.40, 400.0))
    check("Croqueta 只保持 200ms -> hold_short",
          f is not None and f.code == "hold_short", f.message if f else "没有裁定")

    # --- 保持不够：中途松开 L1（引擎每帧都会调 reset）---
    det = SequenceDetector(croqueta)
    for frame in flick(0.0, 90.0, hold_ms=300, facing=0.0, buttons=("LB",))[:75]:
        det.update(frame)
    det.reset()
    f = det.pop_failure()
    check("保持中途松开 L1 -> hold_short",
          f is not None and f.code == "hold_short", f.message if f else "没有裁定")

    # --- 成功不产生裁定；失败只报一次 ---
    det = ArcDetector(roulette)
    hit = run_detector(det, rotate(0.0, 180.0, 200.0, 500.0))
    check("成功之后没有遗留的失败裁定",
          hit is not None and det.pop_failure() is None)

    det = ArcDetector(roulette)
    run_detector(det, rotate(0.0, 180.0, 60.0, 150.0) + centered(0.15, 400))
    first = det.pop_failure()
    second = det.pop_failure()
    check("一次失败只产出一条裁定",
          first is not None and second is None,
          f"first={first.code if first else None} second={second}")

    # --- 引擎层：失败不震、成功震一次、统计正确 ---
    backend = RecordingBackend()
    rumble = RumbleEngine(backend, enabled=True)
    engine = Engine(cfg, NullSource(), rumble, debug=False)

    for frame in rotate(0.0, 180.0, 60.0, 150.0):
        tick(engine, frame.now, frame.rs_angle, frame.rs_mag)
    for i in range(75):
        tick(engine, 0.15 + i * 0.004, rs_mag=0.0)

    active = next(a for a in engine.skills if "马赛" in a.skill.name)
    out = engine.last_outcome
    check("引擎：失败的尝试记录为失败，而且不震动",
          out is not None and not out.ok and out.code == "too_short"
          and len(backend.pulses) == 0,
          f"{out.code if out else None} pulses={len(backend.pulses)}")
    check("引擎：失败计入 attempts / failures",
          active.attempts == 1 and active.failures.get("too_short") == 1,
          f"attempts={active.attempts} failures={active.failures}")

    for frame in rotate(0.5, 180.0, 200.0, 500.0):
        tick(engine, frame.now, frame.rs_angle, frame.rs_mag)
    check("引擎：成功震一次，并计入 attempts",
          len(backend.pulses) == 1 and active.attempts == 2 and active.hits == 1
          and engine.last_outcome is not None and engine.last_outcome.ok,
          f"pulses={len(backend.pulses)} attempts={active.attempts}")

    engine.reset_stats()
    active = next(a for a in engine.skills if "马赛" in a.skill.name)
    check("引擎：reset_stats 清空统计",
          active.attempts == 0 and active.hits == 0 and not active.failures
          and engine.last_outcome is None)


def main() -> int:
    print("═" * 62)
    print("  FIFA 花式动作识别 —— 算法自测")
    print("═" * 62)

    cfg = load_config(Path(__file__).resolve().parent.parent / "skills_config.json")
    test_geometry()
    test_arc(cfg)
    test_stepover(cfg)
    test_arc_discrimination(cfg)
    test_arc_direction(cfg)
    test_sequence_heel_to_heel(cfg)
    test_sequence_croqueta(cfg)
    test_no_retrigger_while_held(cfg)
    test_idle_reset(cfg)
    test_min_duration(cfg)
    test_engine_end_to_end(cfg)
    test_engine_gesture_lock(cfg)
    test_engine_facing_and_group(cfg)
    test_button_taps(cfg)
    test_failure_diagnostics(cfg)
    test_rumble_state_machine()
    test_config_validation()

    print("\n" + "═" * 62)
    print(f"  通过 {PASS} 项，失败 {FAIL} 项")
    print("═" * 62)
    return 1 if FAIL else 0


if __name__ == "__main__":
    raise SystemExit(main())
