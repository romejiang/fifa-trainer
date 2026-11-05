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
    DemoSource, TrainerApp, W, H, _CAL_BUTTONS, find_cjk_font,
)
from padskills.input_source import AxisLayout, PadState, apply_button_names
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
    # 演示模式没有真实布局，设备那几行用假手柄单独验证（见 test_session_log）

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

    # 按了一颗映射表里没有的键：这是"按了没反应"最直接的证据
    app._open_log(path)
    odd = PadState(ls_x=0.0, ls_y=-0.9, raw_buttons=(11,))
    app._diagnose(t0 + 3.0, odd)
    app._close_log()
    text3 = path.read_text(encoding="utf-8")
    check("诊断日志：未映射的原始键会被标出来",
          "原始按键=[11]" in text3 and "无对应按键名" in text3)

    # 绿射第一下按下：状态变化要落进日志（打包版看不到卡片提示）
    app._open_log(path)
    for i in range(30):
        buttons = frozenset({"RB", "X"}) if i >= 10 else frozenset({"RB"})
        st = PadState(ls_x=0.0, ls_y=-0.9, buttons=buttons)
        app.engine._tick(t0 + 4.0 + i * 0.004, st)
        app._diagnose(t0 + 4.0 + i * 0.004, st)
    app._close_log()
    text4 = path.read_text(encoding="utf-8")
    check("诊断日志：绿射按下第一下时状态落进日志",
          "状态 绿色搓射 Green Finesse: 已按第一下 X" in text4)

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


def test_focus_switch() -> None:
    """卡片左边的开关：打开后只判定这一个动作，其余卡片置灰。"""
    screen = pygame.display.set_mode((W, H))
    app = TrainerApp(pygame, str(_cfg_path), None, demo=True)
    app.screen = screen
    assert app._open_device() and app.engine is not None
    app.state = DemoSource().poll()
    app._draw(0.0)

    green = next(a for a in app.engine.skills if "绿色" in a.skill.name)
    switches = [(rect, active) for rect, active in app._focus_hits]
    green_switch = next(rect for rect, active in switches if active is green)
    check("GUI：每个动作卡片都有专项练习开关",
          len(switches) == len(app.engine.skills), f"{len(switches)} 个")

    pygame.event.post(pygame.event.Event(
        pygame.MOUSEBUTTONDOWN, button=1, pos=green_switch.center))
    app._handle_events("play")
    check("GUI：点开关 -> 进入该动作的专项练习",
          app.engine.focus is green, str(app.engine.focus))
    check("GUI：其它动作不再参与判定",
          app.engine.active_skills() == [green],
          str([a.skill.name for a in app.engine.active_skills()]))
    check("GUI：给出一句提示", "专项" in app.notice, app.notice)
    check("GUI：切换专项后清掉上一条结果", app.engine.last_outcome is None)

    ok = True
    try:
        app._draw(0.2)          # 置灰的卡片 + 高亮的卡片都要能画
    except Exception as exc:
        ok = False
        print(f"    绘制异常: {type(exc).__name__}: {exc}")
    check("GUI：专项练习界面能正常绘制", ok)

    pygame.event.post(pygame.event.Event(
        pygame.MOUSEBUTTONDOWN, button=1, pos=green_switch.center))
    app._handle_events("play")
    check("GUI：再点一次回到自由练习",
          app.engine.focus is None
          and len(app.engine.active_skills()) == len(app.engine.skills))

    # 键盘也要能开专项：数字键 1 = 第一张卡片
    pygame.event.post(pygame.event.Event(
        pygame.KEYDOWN, key=pygame.K_1, mod=0, unicode="1", scancode=0))
    app._handle_events("play")
    check("GUI：数字键 1 等于点第一个开关",
          app.engine.focus is app.engine.skills[0],
          app.engine.focus.skill.name if app.engine.focus else "无")
    pygame.event.post(pygame.event.Event(
        pygame.KEYDOWN, key=pygame.K_1, mod=0, unicode="1", scancode=0))
    app._handle_events("play")
    check("GUI：再按数字键 1 关掉专项", app.engine.focus is None)

    # T = 点绿色搓射卡片上的 RB / RT 徽章
    before = green.skill.required_buttons
    pygame.event.post(pygame.event.Event(
        pygame.KEYDOWN, key=pygame.K_t, mod=0, unicode="t", scancode=0))
    app._handle_events("play")
    check("GUI：T 切换修饰键（RB <-> RT）",
          green.skill.required_buttons != before
          and green.detector.required == green.skill.required_buttons,
          f"{before} -> {green.skill.required_buttons}")
    pygame.event.post(pygame.event.Event(
        pygame.KEYDOWN, key=pygame.K_t, mod=0, unicode="t", scancode=0))
    app._handle_events("play")
    check("GUI：再按 T 切回来", green.skill.required_buttons == before,
          str(green.skill.required_buttons))


class _FakePad:
    """带 layout 的假手柄源：验证校准面板的绑定与写盘，不需要真手柄。"""

    name = "测试手柄"
    layout_source = "测试"
    guid = "03000000deadbeef0000000000000000"
    num_axes = 10
    num_buttons = 12
    num_hats = 1

    def __init__(self) -> None:
        self.auto = {"A": 0, "B": 1, "X": 2, "Y": 3, "LB": 4, "RB": 5,
                     "BACK": 6, "START": 7, "LS": 8, "RS": 9, "GUIDE": 10}
        self.layout = AxisLayout()
        self.layout.buttons = dict(self.auto)
        self.button_names = {}
        self.button_notes = []
        self._rest = [{"mean": 0.0}, {"mean": 0.0}, {"mean": 0.0},
                      {"mean": 0.0}, {"mean": -1.0}, {"mean": -1.0}]
        self.applied = {}

    def set_button_names(self, names):
        self.applied = dict(names)
        self.layout.buttons = dict(self.auto)
        return apply_button_names(self.layout, names)

    def button_overrides(self):
        return {name: index for name, index in self.layout.buttons.items()
                if self.auto.get(name) != index}

    def poll(self):
        return PadState()

    def close(self) -> None:
        pass


def test_calibration_panel() -> None:
    """B 打开按键校准：按一下真键 -> 绑定 -> 写回 input.button_names。"""
    tmp = Path(tempfile.mkdtemp(prefix="fifa-cal-"))
    path = dump_default_config(tmp / "skills_config.json")
    screen = pygame.display.set_mode((W, H))
    app = TrainerApp(pygame, str(path), None, demo=True)
    app.screen = screen
    assert app._open_device() and app.engine is not None
    app.state = PadState()

    app._open_calibration()
    check("GUI：演示模式（没有真实手柄）打不开按键校准",
          not app._cal_open and app.engine.paused is False)

    pad = _FakePad()
    app.engine.source = pad
    app._open_calibration()
    check("GUI：B 打开按键校准面板", app._cal_open)
    check("GUI：校准期间暂停判定（按的键不会被当成动作）",
          app.engine.paused is True)
    check("GUI：面板读出当前的自动键表", app._cal_map.get("X") == 2,
          str(app._cal_map))

    app._cal_sel = _CAL_BUTTONS.index("X")
    app._cal_capture(1.0, PadState(raw_buttons=(9,)))
    check("GUI：按一下原始键 #9 -> 绑定到 X", app._cal_map.get("X") == 9,
          str(app._cal_map))
    check("GUI：原本占着 #9 的 RS 被摘掉",
          app._cal_map.get("RS") is None, str(app._cal_map))
    check("GUI：绑定立即生效到手柄源", pad.applied.get("X") == 9,
          str(pad.applied))

    ok = True
    try:
        app._draw(1.0)
    except Exception as exc:
        ok = False
        print(f"    绘制异常: {type(exc).__name__}: {exc}")
    check("GUI：按键校准面板能正常绘制", ok)

    buttons = {action: rect for rect, action in app._cal_btn_hits}
    check("GUI：面板底部画出保存/清除/关闭三个按钮",
          set(buttons) == {"save", "clear", "close"}, str(sorted(buttons)))

    # 鼠标点『保存』（和按 S 等效）
    pygame.event.post(pygame.event.Event(
        pygame.MOUSEBUTTONDOWN, button=1, pos=buttons["save"].center))
    app._handle_events("play")
    saved = json.loads(path.read_bytes().decode("utf-8"))
    check("GUI：点『保存』写进 input.button_names",
          saved["input"]["button_names"].get("X") == 9,
          str(saved["input"]["button_names"]))
    check("GUI：只写改过的项，不把整张自动表钉进配置",
          set(saved["input"]["button_names"]) == {"X"},
          str(saved["input"]["button_names"]))
    check("GUI：保存后配置文件还能正常解析",
          load_config(path).input.button_names.get("X") == 9)

    # 鼠标点一行选中它
    row = next(rect for rect, index in app._cal_hits
               if _CAL_BUTTONS[index] == "X")
    pygame.event.post(pygame.event.Event(
        pygame.MOUSEBUTTONDOWN, button=1, pos=row.center))
    app._handle_events("play")
    check("GUI：点一行就能选中它", _CAL_BUTTONS[app._cal_sel] == "X",
          _CAL_BUTTONS[app._cal_sel])

    # 鼠标点『清除』
    pygame.event.post(pygame.event.Event(
        pygame.MOUSEBUTTONDOWN, button=1, pos=buttons["clear"].center))
    app._handle_events("play")
    check("GUI：点『清除』后这一项退回自动识别", app._cal_map.get("X") == 2,
          str(app._cal_map))

    # 面板打开时要吞掉其它快捷键，免得在背后误触 R 清统计
    app.history.append(("12:00:00", _fake_outcome()))
    pygame.event.post(pygame.event.Event(
        pygame.KEYDOWN, key=pygame.K_r, mod=0, unicode="r", scancode=0))
    app._handle_events("play")
    check("GUI：校准面板打开时吞掉其它快捷键", bool(app.history))

    pygame.event.post(pygame.event.Event(
        pygame.KEYDOWN, key=pygame.K_ESCAPE, mod=0, unicode="", scancode=0))
    app._handle_events("play")
    check("GUI：Esc 关闭面板、恢复判定且不退出程序",
          not app._cal_open and app._running and app.engine.paused is False)

    # 用鼠标把面板关掉（不用键盘）
    app._open_calibration()
    app._draw(2.0)
    buttons = {action: rect for rect, action in app._cal_btn_hits}
    pygame.event.post(pygame.event.Event(
        pygame.MOUSEBUTTONDOWN, button=1, pos=buttons["close"].center))
    app._handle_events("play")
    check("GUI：点『关闭』就能退出校准面板（不需要键盘）",
          not app._cal_open and app.engine.paused is False)

    # 点面板外面的灰色区域也能关掉
    app._open_calibration()
    app._draw(2.1)
    pygame.event.post(pygame.event.Event(
        pygame.MOUSEBUTTONDOWN, button=1, pos=(10, 10)))
    app._handle_events("play")
    check("GUI：点面板外的灰色区域也能关闭", not app._cal_open)

    # 把 RB 绑到 #4（原本是 LB）：油炸丸子要用的 LB 会被摘掉，必须当场提醒
    app._open_calibration()
    app._cal_sel = _CAL_BUTTONS.index("RB")
    app._cal_capture(3.0, PadState(raw_buttons=(4,)))
    check("GUI：抢走别的动作要用的键时给出警告",
          "LB" in app._cal_warning and "失效" in app._cal_warning,
          app._cal_warning)


def test_session_log() -> None:
    """启动时的设备/键位信息要够事后远程排查用。"""
    screen = pygame.display.set_mode((W, H))
    app = TrainerApp(pygame, str(_cfg_path), None, demo=True)
    app.screen = screen
    assert app._open_device() and app.engine is not None

    pad = _FakePad()
    app.engine.source = pad
    tmp = Path(tempfile.mkdtemp(prefix="fifa-session-"))
    path = tmp / "trainer.log"
    app._open_log(path)
    app._log_session(pad)
    app._close_log()
    text = path.read_text(encoding="utf-8")

    check("诊断日志：写下手柄型号/GUID/轴键帽数量",
          "GUID=03000000deadbeef" in text and "轴=10" in text
          and "键=12" in text and "帽=1" in text)
    check("诊断日志：写下轴布局与扳机来源",
          "LT=轴4" in text and "RT=轴5" in text and "扳机静止值=" in text)
    check("诊断日志：写下轴静止值",
          "轴静止值 +0.00 +0.00 +0.00 +0.00 -1.00 -1.00" in text)
    check("诊断日志：写下每个动作实际在等哪颗键",
          "动作按键 绿色搓射 Green Finesse: 按住 RB=#5 + 连按 X=#2" in text,
          "按住 RB + 连按 X")
    check("诊断日志：taps 动作的日志不再是画弧字段",
          "button=X" in text and "间隔=400~600ms" in text
          and "start=None" not in text.split("绿色搓射")[1].splitlines()[0])


def test_hotkey_buttons() -> None:
    """底部快捷键做成按钮：鼠标点一下和按键盘等效。"""
    screen = pygame.display.set_mode((W, H))
    app = TrainerApp(pygame, str(_cfg_path), None, demo=True)
    app.screen = screen
    assert app._open_device() and app.engine is not None
    app.state = DemoSource().poll()
    app._draw(0.0)

    keys = {action: rect for rect, action in app._hotkey_hits}
    check("GUI：底部画出 5 个快捷键按钮",
          set(keys) == {"reset", "calibrate", "snapshot", "folder", "quit"},
          str(sorted(keys)))

    app.history.append(("12:00:00", _fake_outcome()))
    pygame.event.post(pygame.event.Event(
        pygame.MOUSEBUTTONDOWN, button=1, pos=keys["reset"].center))
    app._handle_events("play")
    check("GUI：点『重置统计』等于按 R",
          not app.history and "清零" in app.notice, app.notice)

    pad = _FakePad()
    app.engine.source = pad
    tmp = Path(tempfile.mkdtemp(prefix="fifa-hotkey-"))
    log = tmp / "trainer.log"
    app._open_log(log)
    pygame.event.post(pygame.event.Event(
        pygame.MOUSEBUTTONDOWN, button=1, pos=keys["snapshot"].center))
    app._handle_events("play")
    app._close_log()
    text = log.read_text(encoding="utf-8")
    check("GUI：点『诊断快照』把完整状态写进日志",
          "诊断快照" in text and "生效键表" in text and "原始轴" in text
          and "动作按键 绿色搓射" in text,
          text.split("诊断快照")[-1].splitlines()[0][:40] if "诊断快照" in text else "无")

    pygame.event.post(pygame.event.Event(
        pygame.MOUSEBUTTONDOWN, button=1, pos=keys["calibrate"].center))
    app._handle_events("play")
    check("GUI：点『按键校准』等于按 B", app._cal_open)
    app._close_calibration()

    pygame.event.post(pygame.event.Event(
        pygame.MOUSEBUTTONDOWN, button=1, pos=keys["quit"].center))
    app._handle_events("play")
    check("GUI：点『退出』和按 Esc 等效", not app._running)


def test_persist_button_names() -> None:
    """写盘只动 input.button_names：空对象、null、BOM 都不能把配置写坏。"""
    screen = pygame.display.set_mode((W, H))
    cases = {
        "空 input 对象": '{"input": {}, "skills": []}',
        "只带空白的 input": '{"input": {\n  }, "skills": []}',
        "input 为 null": '{"input": null, "skills": []}',
        "已有 button_names": '{"input": {"button_names": null}, "skills": []}',
        "readme 里提到 input": '{"_readme": ["input 段说明"], "input": {"poll_hz": 250}, "skills": []}',
        "带 BOM": '\ufeff{"input": {"poll_hz": 250}, "skills": []}',
    }
    for label, text in cases.items():
        root = Path(tempfile.mkdtemp(prefix="fifa-persist-"))
        path = root / "skills_config.json"
        path.write_text(text, encoding="utf-8")
        app = TrainerApp(pygame, str(path), None, demo=True)
        app.screen = screen
        ok, message = app._persist_button_names({"X": 9})
        try:
            parsed = json.loads(path.read_bytes().decode("utf-8").lstrip("\ufeff"))
            got = (parsed.get("input") or {}).get("button_names")
        except Exception as exc:
            parsed, got = {}, f"JSON 坏了: {exc}"
        check(f"写盘：{label}", ok and got == {"X": 9},
              f"ok={ok} got={got} {message}")

    # 没有 input 段时应该安全地失败，而不是写坏文件
    root = Path(tempfile.mkdtemp(prefix="fifa-persist-"))
    path = root / "skills_config.json"
    path.write_text('{"skills": []}', encoding="utf-8")
    app = TrainerApp(pygame, str(path), None, demo=True)
    app.screen = screen
    ok, message = app._persist_button_names({"X": 9})
    check("写盘：没有 input 段 -> 报错且不动文件",
          not ok and path.read_text(encoding="utf-8") == '{"skills": []}',
          message)


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
    test_session_log()
    test_config_error()
    test_hotkeys()
    test_history_scroll()
    test_modifier_switch()
    test_focus_switch()
    test_calibration_panel()
    test_hotkey_buttons()
    test_persist_button_names()

    pygame.quit()

    print("\n" + "═" * 62)
    print(f"  通过 {PASS} 项，失败 {FAIL} 项")
    print("═" * 62)
    return 1 if FAIL else 0


if __name__ == "__main__":
    raise SystemExit(main())
