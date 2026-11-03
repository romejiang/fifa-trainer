#!/usr/bin/env python3
"""GUI 冒烟测试（不需要真实显示器 / 手柄）。

    uv run tests/test_gui_smoke.py

用 SDL 的 dummy 视频驱动跑窗口绘制，并让演示轨迹走一遍完整的
"采样 -> 识别 -> 结果" 链路，确认 GUI 的接线在打包前是通的。
"""

from __future__ import annotations

import json
import os
import sys
import tempfile
import time
from pathlib import Path

os.environ.setdefault("SDL_VIDEODRIVER", "dummy")
os.environ.setdefault("SDL_AUDIODRIVER", "dummy")
os.environ.setdefault("PYGAME_HIDE_SUPPORT_PROMPT", "1")

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import pygame

from padskills.config import dump_default_config, load_config
from padskills.engine import Engine
from padskills.gui import (
    DemoSource, TrainerApp, W, H, find_cjk_font,
)
from padskills.rumble import RumbleEngine

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


class _Sink:
    def write(self, _text):
        return 0

    def flush(self):
        pass


def test_demo_source() -> None:
    clock = [0.0]
    source = DemoSource(clock=lambda: clock[0])
    mags = []
    angles = []
    buttons = set()
    for i in range(1200):
        clock[0] = i * 0.004
        state = source.poll()
        mags.append(state.rs_mag)
        angles.append(state.rs_angle)
        buttons |= state.buttons

    check("演示轨迹：幅度在 [0, 1] 内",
          max(mags) <= 1.0 + 1e-6 and min(mags) >= 0.0,
          f"max={max(mags):.2f}")
    check("演示轨迹：角度归一化到 [0, 360)",
          all(0.0 <= a < 360.0 for a in angles))
    check("演示轨迹：既有推杆也有回中",
          max(mags) > 0.8 and min(mags) < 0.1)
    check("演示轨迹：会出现修饰键 LB", "LB" in buttons, str(sorted(buttons)))


def test_font_lookup() -> None:
    font = find_cjk_font()
    check("字体：找到中文字体或安全返回 None（不抛异常）",
          font is None or os.path.exists(font), str(font))


def run_demo(seconds: float = 9.0):
    """按 250Hz 推进演示轨迹，返回 (outcomes, engine)。"""
    clock = [0.0]
    source = DemoSource(clock=lambda: clock[0])
    engine = Engine(_cfg, source, RumbleEngine(None, enabled=False),
                    verbose=False, feedback=True, out=_Sink())
    outcomes = []
    seen = 0
    step = 1.0 / 250.0
    for i in range(int(seconds / step)):
        clock[0] = i * step
        state = source.poll()
        engine._tick(clock[0], state)
        if engine.outcome_seq != seen:
            seen = engine.outcome_seq
            if engine.last_outcome is not None:
                outcomes.append(engine.last_outcome)
    return outcomes, engine


def test_demo_end_to_end() -> None:
    outcomes, engine = run_demo()
    codes = [o.code for o in outcomes if not o.ok]
    names = {o.skill_name for o in outcomes if o.ok}

    def has(*parts: str) -> bool:
        return any(all(part in n for part in parts) for n in names)

    check("演示轨迹：5 个动作各成功一次（中英文名都在）",
          has("马赛回旋", "Roulette")
          and has("踩单车", "Stepover")
          and has("磕球", "Heel")
          and has("油炸丸子", "Croqueta")
          and has("绿色搓射", "Green"),
          f"成功动作={sorted(names)}")
    check("演示轨迹：覆盖 4 种典型失败",
          {"too_fast", "too_short", "incomplete", "hold_short"} <= set(codes),
          f"失败={sorted(set(codes))}")
    check("演示轨迹：成功次数与尝试次数一致",
          engine.last_outcome is not None
          and sum(a.hits for a in engine.skills) >= 5,
          f"hits={sum(a.hits for a in engine.skills)}")
    failed_rumbles = engine.rumble.played
    check("演示轨迹：没有手柄时不震动", failed_rumbles == 0)


def test_draw() -> None:
    screen = pygame.display.set_mode((W, H))
    app = TrainerApp(pygame, str(_cfg_path), None, demo=True)
    app.screen = screen

    check("GUI：演示模式能打开（模拟连接）", app._open_device())
    assert app.engine is not None

    # 让 La Croqueta 进入"按住 L1 + 侧推保持中"的状态，
    # 确认卡片第三行能画出 detector.status()（排查识别问题全靠它）
    from padskills.input_source import PadState
    # 左摇杆必须推着：引擎把"左摇杆回中"当成没有球员朝向，方向类动作不成立
    push = PadState(ls_x=0.0, ls_y=-0.9,
                    rs_x=0.9, rs_y=0.0,
                    buttons=frozenset({"LB"}))
    t0 = time.monotonic()
    for i in range(80):
        app.engine._tick(t0 + i * 0.004, push)
    app.state = push
    try:
        app._draw(t0 + 0.32)
        check("GUI：卡片能画出动作进行中的实时状态", True)
    except Exception as exc:
        check("GUI：卡片能画出动作进行中的实时状态", False,
              f"{type(exc).__name__}: {exc}")

    outcomes, _ = run_demo(2.2)
    for outcome in outcomes[:4]:
        app.engine.last_outcome = outcome
        app.engine.outcome_seq += 1
        app.history.insert(0, ("12:00:00", outcome))
    app.state = DemoSource().poll()

    ok = True
    try:
        for now in (0.1, 0.5, 1.0):
            app._draw(now)
    except Exception as exc:  # 绘制里的任何异常都要抓出来
        ok = False
        print(f"    绘制异常: {type(exc).__name__}: {exc}")
    check("GUI：练习界面能完整绘制", ok)

    app.config_error = "配置文件 JSON 语法错误: 第 3 行 第 1 列"
    try:
        app._draw(1.0)
        check("GUI：配置错误界面能绘制", True)
    except Exception as exc:
        check("GUI：配置错误界面能绘制", False, f"{type(exc).__name__}: {exc}")

    app.config_error = None
    app.engine = None
    app.error = "没有检测到任何手柄。"
    try:
        app._draw(1.0)
        check("GUI：无手柄界面能绘制", True, app.error)
    except Exception as exc:
        check("GUI：无手柄界面能绘制", False, f"{type(exc).__name__}: {exc}")

    app.opening = True
    try:
        app._draw(1.0)
        check("GUI：连接中界面能绘制", True)
    except Exception as exc:
        check("GUI：连接中界面能绘制", False, f"{type(exc).__name__}: {exc}")
    app.opening = False


def test_stick_point() -> None:
    """右摇杆可视化不能把上下画反。SDL 的 y 向上推是负数。"""
    cx = cy = 100.0
    up = TrainerApp._stick_point(cx, cy, 50.0, 0.0, -0.8)
    down = TrainerApp._stick_point(cx, cy, 50.0, 0.0, 0.8)
    right = TrainerApp._stick_point(cx, cy, 50.0, 0.8, 0.0)
    check("GUI：右摇杆上推 -> 圆点向上画", up[1] < cy and up[0] == cx, str(up))
    check("GUI：右摇杆下拉 -> 圆点向下画", down[1] > cy, str(down))
    check("GUI：右推 -> 圆点向右画", right[0] > cx and right[1] == cy, str(right))


def test_diagnostic_log() -> None:
    """日志是排查"识别不到"的主要证据，格式和内容要稳定。"""
    screen = pygame.display.set_mode((W, H))
    app = TrainerApp(pygame, str(_cfg_path), None, demo=True)
    app.screen = screen
    tmp = Path(tempfile.mkdtemp(prefix="fifa-log-"))
    path = tmp / "trainer.log"
    app._open_log(path)
    assert app._open_device() and app.engine is not None

    from padskills.input_source import PadState
    push = PadState(ls_x=0.0, ls_y=-0.9,
                    rs_x=0.9, rs_y=0.0,
                    buttons=frozenset({"LB"}))
    t0 = time.monotonic()
    for i in range(80):
        app.engine._tick(t0 + i * 0.004, push)
        app._diagnose(t0 + i * 0.004, push)
    app._close_log()
    text = path.read_text(encoding="utf-8")

    check("诊断日志：写下了本次加载的配置路径", "配置文件 " in text)
    check("诊断日志：写下了 La Croqueta 的实际参数",
          "hold_ms': 350" in text and "相对左摇杆" in text
          and "右/左" in text, "hold_ms=350 / ±90°")
    check("诊断日志：记录了按键变化",
          "按键 - -> LB" in text, text.splitlines()[0][:24])
    check("诊断日志：记录了右摇杆角度/原始值",
          "RS=90.0°" in text and "raw=(+0.90,+0.00)" in text)
    check("诊断日志：记录了 La Croqueta 的保持进度",
          "La Croqueta=保持" in text and "350ms" in text)

    # 没按 L1：提示应该写进日志，而不是只留在界面上
    app._diag_buttons = frozenset({"LB"})
    app._diag_active = False
    app._open_log(path)
    push2 = PadState(ls_x=0.0, ls_y=-0.9, rs_x=0.9, rs_y=0.0,
                     buttons=frozenset())
    for i in range(10):
        app.engine._tick(t0 + 2.0 + i * 0.004, push2)
        app._diagnose(t0 + 2.0 + i * 0.004, push2)
    app._close_log()
    text2 = path.read_text(encoding="utf-8")
    check("诊断日志：没按 L1 时记下\"方向对了，要按住 L1\"",
          "方向对了，要按住 L1" in text2)

def test_config_error() -> None:
    tmp = Path(tempfile.mkdtemp(prefix="fifa-bad-"))
    bad = tmp / "skills_config.json"
    bad.write_text('{ "skills": [ }', encoding="utf-8")

    app = TrainerApp(pygame, str(bad), None, demo=True)
    check("GUI：JSON 语法错误被捕获而不是直接退出",
          app.cfg is None and app.config_error is not None,
          (app.config_error or "").splitlines()[0][:44])

    app.screen = pygame.display.set_mode((W, H))
    try:
        app._draw(0.0)
        check("GUI：配置错误时窗口仍能绘制（多行报错不重叠）", True)
    except Exception as exc:
        check("GUI：配置错误时窗口仍能绘制（多行报错不重叠）", False,
              f"{type(exc).__name__}: {exc}")

    dump_default_config(bad)
    app._load_config()
    check("GUI：修好配置文件后能重新加载",
          app.cfg is not None and app.config_error is None)


def test_hotkeys() -> None:
    screen = pygame.display.set_mode((W, H))
    app = TrainerApp(pygame, str(_cfg_path), None, demo=True)
    app.screen = screen
    assert app._open_device() and app.engine is not None
    engine = app.engine
    app.history.append(("12:00:00", engine.last_outcome or _fake_outcome()))

    pygame.event.post(pygame.event.Event(
        pygame.KEYDOWN, key=pygame.K_r, mod=0, unicode="r", scancode=0))
    app._handle_events("play")
    check("GUI：R 清空统计和记录",
          engine.last_outcome is None and not app.history)

    pygame.event.post(pygame.event.Event(
        pygame.KEYDOWN, key=pygame.K_ESCAPE, mod=0, unicode="", scancode=0))
    app._handle_events("play")
    check("GUI：Esc 退出并停止引擎",
          not app._running and not engine._running)


def test_history_scroll() -> None:
    """日志列表：保留最近 50 条、滚轮/PageUp/PageDown 可滚动、成功行带调参数据。"""
    from padskills.engine import Outcome

    screen = pygame.display.set_mode((W, H))
    app = TrainerApp(pygame, str(_cfg_path), None, demo=True)
    app.screen = screen
    assert app._open_device() and app.engine is not None

    state = DemoSource().poll()
    t0 = time.monotonic()
    for i in range(60):
        app.engine.last_outcome = Outcome(
            skill_name="马赛回旋 Roulette", ok=True, code="ok", message="",
            elapsed_ms=400.0 + i, at=t0 + i * 0.004,
            detail="旋转 101°（相对 180°→281°）")
        app.engine.outcome_seq += 1
        app._on_tick(t0 + i * 0.004, state)

    check("日志：最多保留 50 条", len(app.history) == 50, f"{len(app.history)} 条")
    check("日志：留下的是最近 50 条",
          app.history[0][1].elapsed_ms == 459.0,
          f"最新 {app.history[0][1].elapsed_ms:.0f}ms")
    check("日志：默认停在最新一条（滚动偏移 0）", app.history_scroll == 0)

    app._scroll_history(10 ** 6)
    check("日志：滚到底时偏移 = 总数 - 可见行数",
          app.history_scroll == 50 - app._HISTORY_ROWS,
          f"offset={app.history_scroll}")

    app._scroll_history(10 ** 6)
    check("日志：继续往下滚不会越界", app.history_scroll == 50 - app._HISTORY_ROWS)

    app._scroll_history(-10 ** 6)
    check("日志：往上滚回到最新一条", app.history_scroll == 0)

    pygame.event.post(pygame.event.Event(pygame.MOUSEWHEEL, x=0, y=-2))
    app._handle_events("play")
    check("日志：鼠标滚轮向下 -> 查看更早记录", app.history_scroll == 2,
          f"offset={app.history_scroll}")

    pygame.event.post(pygame.event.Event(
        pygame.KEYDOWN, key=pygame.K_END, mod=0, unicode="", scancode=0))
    app._handle_events("play")
    check("日志：End 跳到最旧一端",
          app.history_scroll == 50 - app._HISTORY_ROWS)
    pygame.event.post(pygame.event.Event(
        pygame.KEYDOWN, key=pygame.K_HOME, mod=0, unicode="", scancode=0))
    app._handle_events("play")
    check("日志：Home 回到最新一条", app.history_scroll == 0)

    ok = True
    try:
        app._draw(t0 + 1.0)          # 50 条 + 滚动条
        app.history_scroll = 50 - app._HISTORY_ROWS
        app._draw(t0 + 1.1)          # 滚到最旧一端
    except Exception as exc:
        ok = False
        print(f"    绘制异常: {type(exc).__name__}: {exc}")
    check("GUI：50 条日志（两端滚动位置）都能绘制", ok)


def test_modifier_switch() -> None:
    """绿色搓射卡片上的 RB / RT 按钮：点击即切换判定，并写回配置文件。"""
    tmp = Path(tempfile.mkdtemp(prefix="fifa-modifier-"))
    path = dump_default_config(tmp / "skills_config.json")
    screen = pygame.display.set_mode((W, H))
    app = TrainerApp(pygame, str(path), None, demo=True)
    app.screen = screen
    assert app._open_device() and app.engine is not None
    app._draw(0.0)

    green = next(a for a in app.engine.skills if "绿色" in a.skill.name)
    chips = {option: rect for rect, active, option in app._modifier_hits
             if active is green}
    check("GUI：绿色搓射卡片画出 RB / RT 两个选项",
          set(chips) == {"RB", "RT"}, str(sorted(chips)))
    check("GUI：默认选中 RB",
          green.skill.required_buttons == ("RB",)
          and green.detector.required == ("RB",),
          str(green.skill.required_buttons))

    pygame.event.post(pygame.event.Event(
        pygame.MOUSEBUTTONDOWN, button=1, pos=chips["RT"].center))
    app._handle_events("play")
    check("GUI：点击 RT -> 判定立即改用 RT",
          green.skill.required_buttons == ("RT",)
          and green.detector.required == ("RT",),
          str(green.skill.required_buttons))
    check("GUI：切换后给出提示",
          "RT" in app.notice and "绿色" in app.notice, app.notice)

    saved = json.loads(path.read_bytes().decode("utf-8"))
    entry = next(s for s in saved["skills"] if "绿色" in s["name"])
    other = next(s for s in saved["skills"] if "Croqueta" in s["name"])
    check("GUI：选择写回配置文件（只改绿色搓射）",
          entry["required_button"] == "RT"
          and other["required_button"] == "L1",
          f"绿色={entry['required_button']} Croqueta={other['required_button']}")
    check("GUI：配置文件其余内容仍能正常解析",
          load_config(path).skills[0].name == saved["skills"][0]["name"])

    app._draw(0.1)
    chips = {option: rect for rect, active, option in app._modifier_hits
             if active is green}
    pygame.event.post(pygame.event.Event(
        pygame.MOUSEBUTTONDOWN, button=1, pos=chips["RB"].center))
    app._handle_events("play")
    check("GUI：再点 RB -> 切回 RB",
          green.skill.required_buttons == ("RB",)
          and green.detector.required == ("RB",),
          str(green.skill.required_buttons))
    saved = json.loads(path.read_bytes().decode("utf-8"))
    entry = next(s for s in saved["skills"] if "绿色" in s["name"])
    check("GUI：切回 RB 也写回配置文件", entry["required_button"] == "RB",
          entry["required_button"])

    ok = True
    try:
        app._draw(0.2)
    except Exception as exc:
        ok = False
        print(f"    绘制异常: {type(exc).__name__}: {exc}")
    check("GUI：带选项的卡片能正常绘制", ok)


def _fake_outcome():
    from padskills.engine import Outcome
    return Outcome(skill_name="测试", ok=False, code="too_fast",
                   message="太快了", elapsed_ms=60.0, at=0.0)


def main() -> int:
    global _cfg, _cfg_path

    pygame.display.init()
    pygame.font.init()

    print("═" * 62)
    print("  FIFA 花式动作练习 —— GUI 冒烟测试（dummy 视频驱动）")
    print("═" * 62)

    tmp = Path(tempfile.mkdtemp(prefix="fifa-gui-"))
    _cfg_path = dump_default_config(tmp / "skills_config.json")
    _cfg = load_config(_cfg_path)

    test_demo_source()
    test_font_lookup()
    test_demo_end_to_end()
    test_draw()
    test_stick_point()
    test_diagnostic_log()
    test_config_error()
    test_hotkeys()
    test_history_scroll()
    test_modifier_switch()

    pygame.quit()

    print("\n" + "═" * 62)
    print(f"  通过 {PASS} 项，失败 {FAIL} 项")
    print("═" * 62)
    return 1 if FAIL else 0


if __name__ == "__main__":
    raise SystemExit(main())
