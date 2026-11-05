"""桌面练习窗口（pygame 版 GUI）。

设计约束：

* **单线程**——joystick / rumble / display 全部在主循环线程里调用。
  SDL 对 joystick 子系统有线程亲和性，跨线程调用会表现成"有时震、有时不震"。
* **不阻塞识别**——渲染挂在 ``Engine.run(on_tick=...)`` 上，自己按时间戳
  节流到 60fps；识别仍然跑满 250Hz。
* **不用 pygame.init()**——它连音频子系统一起初始化，打包后经常是故障源。
"""

from __future__ import annotations

import json
import math
import os
import re
import subprocess
import sys
import time
from pathlib import Path
from typing import Callable, Dict, FrozenSet, List, Optional, Tuple

from .config import (
    AppConfig, direction_name, default_config_path, ensure_user_config,
    is_frozen, load_config, user_config_dir,
)
from .detectors import Detector, TapDetector
from .geometry import angle_diff
from .engine import Engine, Outcome
from .input_source import (
    GamepadSource, PadState, canonical_button, open_source,
)
from .rumble import RumbleEngine, build_backends, pick_backend

__all__ = ["main_gui", "DemoSource", "find_cjk_font", "TrainerApp"]

APP_TITLE = "FIFA 花式动作练习"

W, H = 900, 620
FPS = 60

# ---- 配色（深色，低对比背景 + 高对比结果色） ----
BG = (18, 20, 26)
PANEL = (28, 31, 40)
CARD = (36, 40, 52)
LINE = (54, 59, 74)
TEXT = (232, 236, 244)
MUTED = (140, 148, 165)
FAINT = (96, 103, 119)
GREEN = (74, 222, 128)
RED = (248, 113, 113)
ACCENT = (96, 165, 250)
AMBER = (251, 191, 36)

# 按键校准面板里的行：一列面键/肩键，一列扳机/摇杆/菜单键，
# 顺序就是手柄上的常见布局，方便对着实物按。
_CAL_COLUMNS: Tuple[Tuple[str, ...], ...] = (
    ("A", "B", "X", "Y", "LB", "RB"),
    ("LT", "RT", "LS", "RS", "BACK", "START", "GUIDE"),
)
_CAL_BUTTONS: Tuple[str, ...] = tuple(b for col in _CAL_COLUMNS for b in col)

# 识别器状态里带数字（"等第二下 123ms"、"保持 210/350ms"），
# 判断"阶段有没有变"时要先抹掉，否则每帧都会被当成新状态。
_STATUS_DIGITS = re.compile(r"\d+(?:\.\d+)?")

# 底部的快捷键按钮：键位、动作、文案
_HOTKEYS: Tuple[Tuple[str, str, str], ...] = (
    ("reset", "R", "重置统计"),
    ("calibrate", "B", "按键校准"),
    ("snapshot", "D", "诊断快照"),
    ("folder", "C", "配置文件夹"),
    ("quit", "Esc", "退出"),
)

# 失败原因 -> 一句可执行的建议（原因本身已经说清哪里不对，这里只说怎么改）
_ADVICE = {
    "too_fast": "放慢一点：把整条弧走完，别一甩而过。",
    "too_slow": "加快一点：一口气转完，中间不要犹豫。",
    "too_short": "把弧画满：起手到收尾要转过规定的角度。",
    "overshoot": "转多了：到点就收手，不要多带。",
    "wrong_start": "起点错了：注意从左摇杆朝向的哪个方位起手。",
    "wrong_end": "终点没落到要求的方向上，最后要停住。",
    "wrong_direction": "方向反了：换一个旋转方向再试。",
    "stalled": "中途别停：摇杆保持推着，连续转过去。",
    "incomplete": "后面的方向也要做出来，动作要连贯。",
    "hold_short": "保持再久一点，别提前松手。",
}


# ---------------------------------------------------------------------------
# 中文字体
# ---------------------------------------------------------------------------

def _font_files() -> List[str]:
    if sys.platform == "win32":
        return [
            r"C:\Windows\Fonts\msyh.ttc",          # 微软雅黑
            r"C:\Windows\Fonts\msyhbd.ttc",
            r"C:\Windows\Fonts\simhei.ttf",        # 黑体
            r"C:\Windows\Fonts\simsun.ttc",
        ]
    if sys.platform == "darwin":
        return [
            "/System/Library/Fonts/PingFang.ttc",
            "/System/Library/Fonts/Hiragino Sans GB.ttc",
            "/System/Library/Fonts/STHeiti Medium.ttc",
            "/Library/Fonts/Arial Unicode.ttf",
        ]
    return [
        "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
        "/usr/share/fonts/noto-cjk/NotoSansCJK-Regular.ttc",
        "/usr/share/fonts/truetype/wqy/wqy-microhei.ttc",
        "/usr/share/fonts/truetype/arphic/uming.ttc",
    ]


_FONT_NAMES = [
    "microsoftyahei", "pingfangsc", "pingfang", "hiraginosansgb", "stheiti",
    "notosanscjksc", "notosanscjk", "sourcehansanssc", "wenquanyimicrohei",
    "simhei", "arialunicodems",
]


def find_cjk_font() -> Optional[str]:
    """找一个能显示中文的字体文件；全都没有时返回 None（界面会退化成方块）。"""
    import pygame

    for path in _font_files():
        if os.path.exists(path):
            return path
    for name in _FONT_NAMES:
        try:
            path = pygame.font.match_font(name)
        except Exception:
            path = None
        if path:
            return path
    return None


class FontBook:
    """按字号缓存字体对象。"""

    def __init__(self) -> None:
        self.path = find_cjk_font()
        self.cjk_ok = self.path is not None
        self._cache = {}

    def get(self, size: int, bold: bool = False):
        import pygame

        key = (size, bold)
        font = self._cache.get(key)
        if font is None:
            if self.path:
                font = pygame.font.Font(self.path, size)
            else:
                font = pygame.font.SysFont(None, size)
            font.set_bold(bold)
            self._cache[key] = font
        return font


# ---------------------------------------------------------------------------
# 演示模式：没有手柄也能看界面 / 试打包
# ---------------------------------------------------------------------------

_F = frozenset


class _Segment:
    __slots__ = ("ms", "fn")

    def __init__(self, ms: float,
                 fn: Callable[[float], Tuple[float, float, FrozenSet[str]]]):
        self.ms = float(ms)
        self.fn = fn


def _neutral(ms: float) -> _Segment:
    return _Segment(ms, lambda t: (0.0, 0.0, _F()))


def _wait(ms: float, buttons: FrozenSet[str] = _F()) -> _Segment:
    return _Segment(ms, lambda t: (0.0, 0.0, buttons))


def _push(ms: float, angle: float, buttons: FrozenSet[str] = _F(),
          mag: float = 0.92) -> _Segment:
    return _Segment(ms, lambda t: (angle, mag, buttons))


def _tap(ms: float, hold_ms: float = 60.0,
         buttons: FrozenSet[str] = _F(), tap: str = "X") -> _Segment:
    """按一下键：段首按下，hold_ms 后松开，其余时间保持 buttons。"""
    def fn(t: float) -> Tuple[float, float, FrozenSet[str]]:
        active = set(buttons)
        if t < hold_ms:
            active.add(tap)
        return 0.0, 0.0, _F(active)
    return _Segment(ms, fn)


def _arc(ms: float, start: float, sweep: float,
         buttons: FrozenSet[str] = _F(), mag: float = 0.92) -> _Segment:
    def fn(t: float) -> Tuple[float, float, FrozenSet[str]]:
        p = 0.0 if ms <= 0 else min(1.0, max(0.0, t / ms))
        return start + sweep * p, mag, buttons
    return _Segment(ms, fn)


def _demo_script() -> List[_Segment]:
    """一段循环轨迹：5 个成功 + 4 个典型失败。

    角度沿用项目的约定（0° 前、90° 右、180° 后、270° 左），
    和默认的 skills_config.json 完全对应。
    """
    # 配置里的 L1 会被规范成 Xbox 的 LB（见 config.canonical_button），
    # 演示轨迹必须用规范名，否则引擎的修饰键过滤会把这个动作整个跳过。
    l1 = _F({"LB"})
    rb = _F({"RB"})
    return [
        _neutral(360),
        _arc(500, 180, 180),            # 马赛回旋 ✓（250~600ms 窗口）
        _neutral(440),
        _arc(500, 0, 90),               # 踩单车 ✓
        _neutral(440),
        _push(170, 0),                  # 磕球过人：前
        _neutral(180),
        _push(170, 180),                #                后 → ✓（总时长 350ms）
        _neutral(440),
        _wait(90, l1),                  # La Croqueta：按住 L1
        # 方向是相对左摇杆 +90°（演示里左摇杆一直推正前方，朝向固定为 0°，所以就是 90°）
        _push(560, 90, l1),             # 侧向保持 ~550ms → ✓
        _neutral(440),
        # 绿色搓射：按住 RB，第一下 X 在段首，450ms 后第二下 X → ✓
        _wait(100, rb),
        _tap(450, buttons=rb),
        _tap(120, buttons=rb),
        _wait(260, rb),
        _neutral(440),
        _arc(70, 180, 180),             # ✗ 太快
        _neutral(440),
        _arc(230, 180, 50),             # ✗ 转得不够（累计 < 70°）
        _neutral(440),
        _push(170, 0),                  # ✗ 磕球只做了一半
        _neutral(560),
        _wait(90, l1),
        _push(300, 270, l1),            # ✗ La Croqueta 保持不够（方向对，时间不够）
        _neutral(560),
    ]


class DemoSource(GamepadSource):
    """不用手柄，循环播放一段预设轨迹（成功 + 失败）。"""

    name = "演示模式（无手柄）"
    layout_source = "内置轨迹"

    def __init__(self, clock: Optional[Callable[[], float]] = None) -> None:
        # clock 可注入：测试里可以按固定步长推进，不必真的等 9 秒
        self._clock = clock or time.perf_counter
        self._t0 = self._clock()
        self._segs = _demo_script()
        self._starts: List[float] = []
        total = 0.0
        for seg in self._segs:
            self._starts.append(total)
            total += seg.ms
        self._total = max(1.0, total)

    def poll(self) -> PadState:
        t = ((self._clock() - self._t0) * 1000.0) % self._total
        idx = len(self._segs) - 1
        for i, seg in enumerate(self._segs):
            if t < self._starts[i] + seg.ms:
                idx = i
                break
        angle, mag, buttons = self._segs[idx].fn(t - self._starts[idx])
        rad = math.radians(angle)
        x = mag * math.sin(rad)
        y = -mag * math.cos(rad)
        # 新规则：左摇杆回中就没有"球员朝向"，所有相对方向的动作都不成立。
        # 演示轨迹因此一直把左摇杆推正前方（朝向 0°）。
        return PadState(ls_x=0.0, ls_y=-0.9,
                        rs_x=x, rs_y=y, buttons=buttons,
                        raw_axes=(0.0, -0.9, x, y))


class _Sink:
    """GUI 里不需要把引擎日志打到控制台。"""

    def write(self, _text: str) -> int:
        return 0

    def flush(self) -> None:
        pass


def _build_rumble(cfg: AppConfig, source: GamepadSource) -> Tuple[RumbleEngine, str]:
    """和 main.py 同样的后端选择逻辑，但全程安静。"""
    if not cfg.rumble.enabled:
        return RumbleEngine(None, enabled=False), "已关闭"

    joy = getattr(source, "_joy", None)
    candidates = build_backends(
        cfg.rumble.backend, joystick=joy,
        joystick_index=cfg.input.joystick_index, verbose=False)
    if not candidates:
        return RumbleEngine(None, enabled=False), "不可用"

    backend = candidates[0]
    if cfg.rumble.startup_test:
        backend = pick_backend(
            candidates,
            strength=cfg.rumble.startup_test_strength,
            duration_ms=cfg.rumble.startup_test_ms,
            verbose=False,
        )
    if backend is None:
        return RumbleEngine(None, enabled=False), "不可用"

    engine = RumbleEngine(backend, enabled=True)
    engine.start()
    return engine, backend.label.split(" [")[0]


# ---------------------------------------------------------------------------
# 主窗口
# ---------------------------------------------------------------------------

_TOKEN = re.compile(r"[A-Za-z0-9_\-./:%+]+|\s+|.", re.S)


class TrainerApp:
    _HISTORY_ROWS = 5          # 最近的尝试一屏显示几条
    """窗口 + 状态机。事件/渲染都在主线程，识别在 Engine 的 250Hz 循环里。"""

    def __init__(self, pygame_module, config_path: Optional[str],
                 index: Optional[int], demo: bool):
        self.pg = pygame_module
        self.screen = None
        self._clock = pygame_module.time.Clock()
        self._fonts = FontBook()

        self.config_path = Path(config_path) if config_path else default_config_path()
        self.index_override = index
        self.demo = demo

        self.cfg: Optional[AppConfig] = None
        self.config_error: Optional[str] = None
        self.engine: Optional[Engine] = None
        self.opening = False
        self.error = ""
        self.notice = ""

        self.device_label = "未连接"
        self.rumble_label = ""
        self.state: Optional[PadState] = None
        self.history: List[Tuple[str, Outcome]] = []
        self.history_scroll = 0
        # 动作卡片上可点击的修饰键按钮（绿色搓射的 RB / RT）
        self._modifier_hits: List[Tuple[object, object, str]] = []
        # 动作卡片左边的"专项练习"开关
        self._focus_hits: List[Tuple[object, object]] = []
        # 底部快捷键按钮（R / B / D / C / Esc），鼠标点也行
        self._hotkey_hits: List[Tuple[object, str]] = []

        # ---- 按键校准面板 ---------------------------------------------
        # B 打开：按一下手柄上的键，就把它绑定到高亮的那一行，并写回配置。
        # 设备不被 SDL 认识时按键名是猜的，这块面板就是用来纠正它的。
        self._cal_open = False
        self._cal_map: Dict[str, Optional[int]] = {}
        self._cal_extra: Dict[str, int] = {}
        self._cal_sel = 0
        self._cal_hits: List[Tuple[object, int]] = []
        self._cal_btn_hits: List[Tuple[object, str]] = []
        self._cal_panel_rect = None
        self._cal_prev_raw: FrozenSet[int] = frozenset()
        self._cal_ignore_until = 0.0
        self._cal_message = ""
        self._cal_warning = ""
        self._cal_dirty = False
        self._seen_seq = 0
        self._last_draw = 0.0
        self._running = True
        self._retry = False

        # ---- 诊断日志 -------------------------------------------------
        # 打包后没有控制台，识别不了时要能留下证据：
        # 记录配置、按键映射、每一次右摇杆推动的角度/幅度和各识别器的实时状态。
        self._log_path: Optional[Path] = None
        self._log_file = None
        self._diag_buttons: FrozenSet[str] = frozenset()
        self._diag_raw: Tuple[int, ...] = ()
        self._diag_status: Dict[str, str] = {}
        self._diag_active = False
        self._diag_started = 0.0
        self._diag_last = 0.0
        self._diag_max = 0.0

        self._load_config()

    # ------------------------------------------------------------------
    # 配置
    # ------------------------------------------------------------------

    def _load_config(self) -> bool:
        self.config_error = None
        try:
            if is_frozen():
                ensure_user_config(self.config_path)
            cfg = load_config(self.config_path)
        except SystemExit as exc:
            self.config_error = str(exc)
            return False
        except Exception as exc:  # 打包后看不到控制台，必须显示到窗口里
            self.config_error = f"{type(exc).__name__}: {exc}"
            return False

        if self.index_override is not None:
            cfg.input.joystick_index = self.index_override
        self.cfg = cfg
        return True

    # ------------------------------------------------------------------
    # 生命周期
    # ------------------------------------------------------------------

    def run(self) -> int:
        self._open_log()
        try:
            if self.cfg is None and not self._wait_config():
                return 0

            while self._running:
                if self.engine is None and not self._open_device():
                    if not self._wait_device():
                        break
                    continue
                if not self._play():
                    # 手柄掉线等异常：回到等待界面，插回去还能继续，而不是直接崩掉
                    if not self._wait_device():
                        break
                    continue
                break

            self.engine = None
            return 0
        finally:
            self._close_log()

    # ------------------------------------------------------------------
    # 诊断日志（%APPDATA%\FifaSkillTrainer\trainer.log）
    # ------------------------------------------------------------------

    LOG_MAX_BYTES = 2_000_000

    def _open_log(self, path: Optional[Path] = None) -> None:
        try:
            path = Path(path) if path is not None else user_config_dir() / "trainer.log"
            path.parent.mkdir(parents=True, exist_ok=True)
            if path.exists() and path.stat().st_size > self.LOG_MAX_BYTES:
                path.write_bytes(b"\xef\xbb\xbf")
            # 带 BOM 的 UTF-8：Windows 记事本 / PowerShell 5.1 才能正确显示中文。
            # 追加时不会再写 BOM（那会把 BOM 塞到文件中间），所以只在开头补一次。
            if path.exists() and path.stat().st_size > 3:
                if path.read_bytes()[:3] != b"\xef\xbb\xbf":
                    path.write_bytes(b"\xef\xbb\xbf" + path.read_bytes())
            self._log_path = path
            self._log_file = open(path, "a", encoding="utf-8")
            if not path.exists() or path.stat().st_size == 0:
                self._log_file.write("\ufeff")
        except Exception:
            self._log_path = None
            self._log_file = None

    def _close_log(self) -> None:
        if self._log_file is not None:
            try:
                self._log_file.close()
            except Exception:
                pass
            self._log_file = None

    def _write_log(self, text: str) -> None:
        if self._log_file is None:
            return
        try:
            ms = int(time.time() * 1000) % 1000
            self._log_file.write(f"[{time.strftime('%H:%M:%S')}.{ms:03d}] {text}\n")
            self._log_file.flush()
        except Exception:
            pass

    def _log_session(self, source: GamepadSource) -> None:
        if self._log_file is None:
            return
        self._write_log("=" * 60)
        self._write_log(f"启动 {time.strftime('%Y-%m-%d %H:%M:%S')} | "
                        f"{'打包版' if is_frozen() else '源码运行'}")
        try:
            mtime = time.strftime("%Y-%m-%d %H:%M:%S",
                                  time.localtime(self.config_path.stat().st_mtime))
        except OSError:
            mtime = "?"
        self._write_log(f"配置文件 {self.config_path}（修改于 {mtime}）")

        # 设备信息尽量写全：映射猜错时，全靠这几行判断手柄到底是什么形态
        info = [f"手柄 {source.name}"]
        guid = getattr(source, "guid", None)
        if guid:
            info.append(f"GUID={guid}")
        for label, attr in (("轴", "num_axes"), ("键", "num_buttons"),
                            ("帽", "num_hats")):
            value = getattr(source, attr, None)
            if value is not None:
                info.append(f"{label}={value}")
        self._write_log(" ".join(info))
        self._write_log("映射来源 " + str(getattr(source, "layout_source", "?")))

        layout = getattr(source, "layout", None)
        if layout is not None:
            self._write_log("按键映射 " + (", ".join(
                f"{k}=#{v}" for k, v in sorted(layout.buttons.items())) or "无"))
            self._write_log(
                f"轴映射 ls_x={layout.ls_x} ls_y={layout.ls_y} "
                f"rs_x={layout.rs_x} rs_y={layout.rs_y} "
                f"LT={self._button_label(layout, 'LT')} "
                f"RT={self._button_label(layout, 'RT')} "
                f"扳机静止值={layout.trigger_rest} "
                f"反转_rs_y={layout.invert_rs_y} 反转_ls_y={layout.invert_ls_y}")
            rest = getattr(source, "_rest", None)
            if rest:
                self._write_log("轴静止值 " + " ".join(
                    f"{item['mean']:+.2f}" for item in rest))
            names = getattr(source, "button_names", None)
            self._write_log("按键校准 " + (
                ", ".join(f"{k}=#{v}" for k, v in sorted(names.items()))
                if names else "无（全部按自动识别）"))
            notes = getattr(source, "button_notes", None)
            if notes:
                self._write_log("按键校准说明 " + "；".join(notes))

        if self.cfg is not None:
            for skill in self.cfg.skills:
                if not skill.enabled:
                    continue
                p = skill.params
                if skill.kind == "sequence":
                    extra = (f"steps={p.get('steps')} tol={p.get('tolerance_deg')} "
                             f"enter={p.get('enter_threshold')} "
                             f"max={p.get('max_duration_ms')} "
                             f"idle={p.get('idle_timeout_ms')}")
                elif skill.kind == "taps":
                    extra = (f"button={p.get('button')} "
                             f"间隔={p.get('min_interval_ms')}~{p.get('max_interval_ms')}ms "
                             f"可选修饰键={p.get('modifier_options')}")
                else:
                    extra = (f"start={p.get('start_angle')} end={p.get('end_angle')} "
                             f"angle={p.get('min_angle')}~{p.get('max_angle')} "
                             f"max={p.get('max_duration_ms')}")
                self._write_log(
                    f"动作 {skill.name} | {skill.kind} | "
                    f"{'相对左摇杆' if skill.relative_to_ls else '屏幕绝对'} | "
                    f"修饰键={list(skill.required_buttons) or '无'} | {extra}")
            self._log_skill_buttons(source)

    @staticmethod
    def _button_label(layout, name: str) -> str:
        """规范名 -> 手柄上实际靠什么触发（原始编号 / 轴号 / 方向帽）。"""
        buttons = getattr(layout, "buttons", {}) or {}
        if name in buttons:
            return f"#{buttons[name]}"
        if name in (getattr(layout, "dpad", {}) or {}):
            return "方向帽"
        if name in ("LT", "RT"):
            axis = getattr(layout, f"{name.lower()}_axis", None)
            button = getattr(layout, f"{name.lower()}_button", None)
            if axis is not None:
                return f"轴{axis}"
            if button is not None:
                return f"键{button}"
        return "未绑定"

    def _log_skill_buttons(self, source: GamepadSource) -> None:
        """每个动作实际在等哪颗键、对应手柄的哪个原始编号。

        "按键类的动作按不出来"最常见的原因就是这行对不上：应用在等 #2，
        而手柄的射门键报的是 #9。有一行日志就能直接看出来。
        """
        layout = getattr(source, "layout", None)
        if layout is None or self.cfg is None:
            return
        for skill in self.cfg.skills:
            if not skill.enabled:
                continue
            parts = [f"按住 {name}={self._button_label(layout, name)}"
                     for name in skill.required_buttons]
            button = skill.params.get("button")
            if skill.kind == "taps" and button:
                try:
                    canon = canonical_button(button)
                except (TypeError, ValueError):
                    canon = str(button)
                p = skill.params
                parts.append(f"连按 {canon}={self._button_label(layout, canon)}")
                parts.append(f"{p.get('min_interval_ms')}~{p.get('max_interval_ms')}ms")
            self._write_log(
                f"动作按键 {skill.name}: " + (" + ".join(parts) if parts else "无需按键"))

    def _rs_line(self, state: PadState, tag: str) -> str:
        assert self.engine is not None
        parts = []
        for active in self.engine.active_skills():
            text = active.detector.status()
            if text and text != "待机":
                parts.append(f"{active.skill.name.split(' (')[0]}={text}")
        line = (f"{tag} RS={state.rs_angle:.1f}° mag={state.rs_mag:.2f} "
                f"raw=({state.rs_x:+.2f},{state.rs_y:+.2f}) "
                f"LS={state.ls_angle:.0f}°/{state.ls_mag:.2f} "
                f"facing={self.engine.facing:.0f} "
                f"键={','.join(sorted(state.buttons)) or '-'}")
        if parts:
            line += " | " + " | ".join(parts)
        return line

    def _diagnose(self, now: float, state: PadState) -> None:
        """每帧调用（250Hz）：按键变化、识别器状态变化、右摇杆推动过程。"""
        if self._log_file is None:
            return
        try:
            raw_now = tuple(state.raw_buttons)
            if state.buttons != self._diag_buttons or raw_now != self._diag_raw:
                before = ",".join(sorted(self._diag_buttons)) or "-"
                after = ",".join(sorted(state.buttons)) or "-"
                line = (f"按键 {before} -> {after} "
                        f"原始按键={list(raw_now)}")
                fresh = sorted(set(raw_now) - set(self._diag_raw))
                if fresh and state.buttons == self._diag_buttons:
                    # 新按下的编号没有产生任何按键名：这颗键不在映射表里，
                    # 正是"按了没反应"最典型的样子
                    line += (f"  ⚠ 编号 {fresh} 无对应按键名  "
                             f"扳机 LT={state.lt:.2f} RT={state.rt:.2f}")
                self._write_log(line)
                self._diag_buttons = state.buttons
                self._diag_raw = raw_now

            # 识别器状态的变化（"已按第一下 X，等第二下…"只画在卡片上，
            # 打包版事后看不到，这里在变化时落一行）
            if self.engine is not None:
                for active in self.engine.active_skills():
                    status = active.detector.status() or "待机"
                    key = _STATUS_DIGITS.sub("#", status)
                    if self._diag_status.get(active.skill.name) != key:
                        self._diag_status[active.skill.name] = key
                        self._write_log(f"状态 {active.skill.name}: {status}")

            if state.rs_mag >= 0.5:
                if not self._diag_active:
                    self._diag_active = True
                    self._diag_started = now
                    self._diag_last = 0.0
                    self._diag_max = 0.0
                    self._write_log(self._rs_line(state, "RS推下"))
                self._diag_max = max(self._diag_max, state.rs_mag)
                if now - self._diag_last >= 0.045:
                    self._diag_last = now
                    self._write_log(self._rs_line(state, "RS"))
            elif self._diag_active and state.rs_mag < 0.3:
                self._write_log(
                    f"RS松手 按住 {(now - self._diag_started) * 1000:.0f}ms "
                    f"最大幅度 {self._diag_max:.2f}")
                self._diag_active = False
        except Exception:
            pass

    def _dump_diagnostic(self) -> None:
        """按 D / 点"诊断快照"：把这一瞬间的完整状态写进日志。

        远程排查时让对方在"按不出来"的那一刻点一下，比事后猜有用得多。
        """
        if self._log_file is None:
            self.notice = "日志没打开，快照写不了"
            return
        state = self.state or PadState()
        engine = self.engine
        layout = self._layout()
        self._write_log("=" * 60)
        self._write_log(f"诊断快照 {time.strftime('%Y-%m-%d %H:%M:%S')} | "
                        f"{self.device_label}")
        if layout is not None:
            self._write_log("生效键表 " + (", ".join(
                f"{k}=#{v}" for k, v in sorted(layout.buttons.items())) or "空"))
            self._write_log(
                f"方向帽 {', '.join(sorted(getattr(layout, 'dpad', {}) or {})) or '无'}"
                f" | LT={self._button_label(layout, 'LT')}"
                f" RT={self._button_label(layout, 'RT')}"
                f" | 扳机静止值={layout.trigger_rest}")
        self._write_log(
            f"当前按键 [{','.join(sorted(state.buttons)) or '无'}] "
            f"原始编号 {list(state.raw_buttons)} "
            f"LT={state.lt:.2f} RT={state.rt:.2f}")
        self._write_log("原始轴 [" + " ".join(
            f"{v:+.2f}" for v in state.raw_axes) + "]")
        facing = engine.facing if engine is not None else 0.0
        facing_ok = engine.facing_valid if engine is not None else False
        self._write_log(
            f"左摇杆 {state.ls_angle:.0f}°/{state.ls_mag:.2f} "
            f"右摇杆 {state.rs_angle:.0f}°/{state.rs_mag:.2f} "
            f"球员朝向 {facing:.0f}°"
            f"{'' if facing_ok else '（左摇杆回中，方向类动作不成立）'}")
        focus = engine.focus if engine is not None else None
        mode = f"专项：{focus.skill.name}" if focus is not None else "自由练习"
        if engine is not None and engine.paused:
            mode += "　已暂停（校准中）"
        self._write_log("模式 " + mode)
        if engine is not None:
            self._write_log("识别器 " + (" | ".join(
                f"{a.skill.name.split(' (')[0]}={a.detector.status() or '待机'}"
                for a in engine.active_skills()) or "无"))
            self._log_skill_buttons(engine.source)
        self._write_log("=" * 60)
        self.notice = "诊断快照已写进 trainer.log"

    def _open_device(self) -> bool:
        assert self.cfg is not None
        self.opening = True
        self.error = ""
        self.notice = ""
        # 先画一帧"正在连接"，否则打开手柄的校准会阻塞 250ms 以上，窗口一片空白
        self._draw(0.0)
        try:
            if self.demo:
                source: GamepadSource = DemoSource()
                rumble = RumbleEngine(None, enabled=False)
                rumble_label = "演示（不震动）"
            else:
                source = open_source(self.cfg.input, verbose=False)
                rumble, rumble_label = _build_rumble(self.cfg, source)

            engine = Engine(self.cfg, source, rumble, verbose=False,
                            feedback=True, out=_Sink())
        except Exception as exc:
            self.error = str(exc)
            self.notice = ""
            self.opening = False
            self._write_log(f"打开手柄失败：{type(exc).__name__}: {exc}")
            return False
        finally:
            self.opening = False

        self._log_session(source)
        self.engine = engine
        self.device_label = source.name
        self.rumble_label = rumble_label
        self.history.clear()
        self.history_scroll = 0
        self._seen_seq = engine.outcome_seq
        self._last_draw = 0.0
        self._diag_buttons = frozenset()
        self._diag_raw = ()
        self._diag_status.clear()
        return True

    def _play(self) -> bool:
        """跑识别主循环。返回 False 表示是异常中断（手柄掉线等）。"""
        engine = self.engine
        if engine is None:
            return True
        crashed = False
        try:
            engine.run(on_tick=self._on_tick)
        except Exception as exc:  # 打包后没有控制台，至少要在窗口里说一声
            self.error = f"手柄连接中断：{type(exc).__name__}: {exc}"
            self.notice = ""
            crashed = True
        finally:
            self.engine = None
        return not crashed

    def _on_tick(self, now: float, state: PadState) -> None:
        if not self._running:
            if self.engine is not None:
                self.engine.stop()
            return

        # 先收结果再处理事件：点"专项"开关会清空 last_outcome，
        # 同一帧刚产生的那条记录不能因此漏进历史。
        if self.engine is not None and self.engine.outcome_seq != self._seen_seq:
            self._seen_seq = self.engine.outcome_seq
            outcome = self.engine.last_outcome
            if outcome is not None:
                self.history.insert(0, (time.strftime("%H:%M:%S"), outcome))
                del self.history[50:]
                max_off = max(0, len(self.history) - self._HISTORY_ROWS)
                self.history_scroll = min(self.history_scroll, max_off)
                mark = "✓" if outcome.ok else "✗"
                if outcome.ok:
                    detail = f" | {outcome.detail}" if outcome.detail else ""
                else:
                    detail = f" — {outcome.message}"
                self._write_log(
                    f"结果 {mark} {outcome.skill_name} {outcome.elapsed_ms:.0f}ms{detail}")

        self._handle_events("play")
        self._diagnose(now, state)
        if self._cal_open:
            self._cal_capture(now, state)
        self.state = state
        if now - self._last_draw < 1.0 / FPS:
            return
        self._last_draw = now
        self._draw(now)

    def _wait_config(self) -> bool:
        while self._running and self.cfg is None:
            self._handle_events("config")
            self._draw(0.0)
            self._clock.tick(FPS)
        return self.cfg is not None

    def _wait_device(self) -> bool:
        while self._running and self.engine is None:
            self._handle_events("device")
            if self._retry:
                self._retry = False
                # 重新枚举设备：热插拔时 SDL 需要重新 init 才能看到新手柄
                try:
                    self.pg.joystick.quit()
                    self.pg.joystick.init()
                except Exception:
                    pass
                if self._open_device():
                    return True
            self._draw(0.0)
            self._clock.tick(FPS)
        return self.engine is not None

    def _shutdown(self) -> None:
        try:
            self.pg.quit()
        except Exception:
            pass

    # ------------------------------------------------------------------
    # 事件
    # ------------------------------------------------------------------

    def _handle_events(self, mode: str) -> None:
        pg = self.pg
        if self.engine is None and self._cal_open:
            # 手柄掉了：面板没有意义，别让它继续吞键盘
            self._cal_open = False
            self._cal_hits = []
        for event in pg.event.get():
            if event.type == pg.QUIT:
                self._running = False
                if self.engine is not None:
                    self.engine.stop()
            elif event.type == getattr(pg, "JOYDEVICEADDED", -1):
                if mode == "device":
                    self._retry = True
            elif event.type == pg.KEYDOWN:
                self._on_key(event.key, mode)
            elif (event.type == pg.MOUSEWHEEL and mode == "play"
                  and not self._cal_open):
                # pygame 的 y>0 是向上滚；向下滚看更早的记录
                self._scroll_history(-event.y)
            elif (event.type == pg.MOUSEBUTTONDOWN
                  and getattr(event, "button", 0) == 1 and mode == "play"):
                self._on_click(event.pos)

    def _on_key(self, key: int, mode: str) -> None:
        pg = self.pg
        if self._cal_open:
            # 校准面板占着键盘：吞掉所有按键，免得 R / C 在背后的界面里误触
            self._on_calibration_key(key)
            return
        if key in (pg.K_ESCAPE, pg.K_q):
            self._running = False
            if self.engine is not None:
                self.engine.stop()
        elif key == pg.K_b:
            if mode == "play" and self.engine is not None:
                self._open_calibration()
        elif key == pg.K_d:
            if mode == "play" and self.engine is not None:
                self._dump_diagnostic()
        elif key == pg.K_r:
            if mode == "play" and self.engine is not None:
                self._reset_stats()
            elif mode == "device":
                self._retry = True
            elif mode == "config":
                self._load_config()
        elif key == pg.K_c:
            self._open_config_folder()
        elif key == pg.K_t:
            if mode == "play" and self.engine is not None:
                self._cycle_modifier()
        elif pg.K_1 <= key <= pg.K_9:
            # 数字键 = 点对应卡片的专项开关（从上往下 1、2、3…）
            if mode == "play" and self.engine is not None:
                index = key - pg.K_1
                if 0 <= index < len(self.engine.skills):
                    self._toggle_focus(self.engine.skills[index])
        elif key == pg.K_PAGEUP:
            self._scroll_history(-self._HISTORY_ROWS)
        elif key == pg.K_PAGEDOWN:
            self._scroll_history(self._HISTORY_ROWS)
        elif key == pg.K_HOME:
            self.history_scroll = 0
        elif key == pg.K_END:
            self._scroll_history(10 ** 6)

    def _on_click(self, pos) -> None:
        if self._cal_open:
            # 面板在最上层：点不到下面的卡片，只能点按钮 / 选行
            for rect, action in self._cal_btn_hits:
                if rect.collidepoint(pos):
                    self._cal_button(action)
                    return
            for rect, index in self._cal_hits:
                if rect.collidepoint(pos):
                    self._cal_sel = index
                    return
            # 点面板外面的灰色区域 = 关闭（改动本次运行内已经生效，不会丢）
            panel = getattr(self, "_cal_panel_rect", None)
            if panel is not None and not panel.collidepoint(pos):
                self._close_calibration()
            return
        for rect, action in self._hotkey_hits:
            if rect.collidepoint(pos):
                self._run_hotkey(action)
                return
        for rect, active, option in self._modifier_hits:
            if rect.collidepoint(pos):
                self._choose_modifier(active, option)
                return
        for rect, active in self._focus_hits:
            if rect.collidepoint(pos):
                self._toggle_focus(active)
                return

    def _run_hotkey(self, action: str) -> None:
        """底部按钮和键盘快捷键共用这一套动作。"""
        if action == "reset":
            self._reset_stats()
        elif action == "calibrate":
            self._open_calibration()
        elif action == "snapshot":
            self._dump_diagnostic()
        elif action == "folder":
            self._open_config_folder()
        elif action == "quit":
            self._running = False
            if self.engine is not None:
                self.engine.stop()

    def _cycle_modifier(self) -> None:
        """键盘切换修饰键，等价于点卡片右下角的 RB / RT 徽章。"""
        if self.engine is None:
            return
        for active in self.engine.active_skills():
            options = tuple(active.skill.params.get("modifier_options") or ())
            if len(options) < 2:
                continue
            current = (active.skill.required_buttons[0]
                       if active.skill.required_buttons else options[0])
            nxt = (options[(options.index(current) + 1) % len(options)]
                   if current in options else options[0])
            self._choose_modifier(active, nxt)
            return
        self.notice = "当前没有可切换的修饰键"

    def _reset_stats(self) -> None:
        if self.engine is None:
            return
        self.engine.reset_stats()
        self.history.clear()
        self.history_scroll = 0
        self._seen_seq = self.engine.outcome_seq
        self.notice = "统计已清零"

    def _choose_modifier(self, active, option: str) -> None:
        """切换某个动作要按住的修饰键，并写回当前使用的配置文件。"""
        skill = active.skill
        options = tuple(skill.params.get("modifier_options") or ())
        if option not in options:
            return
        if skill.required_buttons == (option,):
            return

        skill.required_buttons = (option,)
        skill.raw["required_button"] = option
        if isinstance(active.detector, TapDetector):
            active.detector.set_modifier(option)

        name = self._short_name(skill.name)
        self.notice = f"{name}：改为按住 {option} 连按 {skill.params.get('button', 'X')}"
        self._write_log(f"切换修饰键 {skill.name} -> {option}")
        ok, message = self._persist_required_button(skill.name, option)
        if not ok:
            self.notice += f"（写入配置失败：{message}）"
            self._write_log(f"写入配置失败：{message}")

    def _persist_required_button(self, skill_name: str, button: str) -> Tuple[bool, str]:
        """只替换这个动作段落里的 required_button，不重写整份手改过的配置。"""
        try:
            text = self.config_path.read_bytes().decode("utf-8")
            spans = list(re.finditer(
                r'"name"\s*:\s*"([^"]*)"', text))
            for idx, match in enumerate(spans):
                name = match.group(1)
                if name != skill_name:
                    continue
                end = spans[idx + 1].start() if idx + 1 < len(spans) else len(text)
                segment = text[match.start():end]
                pattern = re.compile(r'("required_button"\s*:\s*")([^"]*)(")')
                if pattern.search(segment) is None:
                    return False, "这个动作没有 required_button"
                segment = pattern.sub(
                    lambda m: m.group(1) + button + m.group(3), segment, count=1)
                text = text[:match.start()] + segment + text[end:]
                self.config_path.write_bytes(text.encode("utf-8"))
                return True, ""
            return False, "配置里找不到这个动作"
        except Exception as exc:
            return False, f"{type(exc).__name__}: {exc}"

    # ------------------------------------------------------------------
    # 专项练习：卡片左边的开关
    # ------------------------------------------------------------------

    def _toggle_focus(self, active) -> None:
        """开/关某个动作的专项练习。同一时间只能开一个。"""
        engine = self.engine
        if engine is None or active is None:
            return
        name = self._short_name(active.skill.name)
        if engine.focus is active:
            engine.set_focus(None)
            self.notice = "已回到自由练习：所有动作都参与判定"
            self._write_log("专项练习 -> 关闭（自由练习）")
        else:
            engine.set_focus(active)
            self.notice = f"专项练习：{name}（其他动作已置灰，不再判定）"
            self._write_log(f"专项练习 -> {active.skill.name}")
        self.history_scroll = 0

    # ------------------------------------------------------------------
    # 按键校准：把猜错的按键名改成真实的原始编号
    # ------------------------------------------------------------------

    def _layout(self):
        source = getattr(self.engine, "source", None) \
            if self.engine is not None else None
        return getattr(source, "layout", None)

    def _layout_buttons(self) -> Dict[str, int]:
        layout = self._layout()
        return dict(getattr(layout, "buttons", {}) or {})

    def _available_buttons(self) -> set:
        """当前布局里"能产生名字"的全部按键。

        除了 buttons，还有方向帽（DPAD_*）和轴驱动的 LT/RT；
        只看 buttons 会把它们误报成"没有绑定"。
        """
        layout = self._layout()
        names = set(self._layout_buttons())
        names.update(getattr(layout, "dpad", {}) or {})
        if (getattr(layout, "lt_axis", None) is not None
                or getattr(layout, "lt_button", None) is not None):
            names.add("LT")
        if (getattr(layout, "rt_axis", None) is not None
                or getattr(layout, "rt_button", None) is not None):
            names.add("RT")
        return names

    def _open_calibration(self) -> None:
        if self._layout() is None:
            self.notice = "当前没有真实手柄（演示模式），校准用不了"
            return
        table = self._layout_buttons()
        self._cal_map = {name: table.get(name) for name in _CAL_BUTTONS}
        # 配置里手写的、面板没有展示的名字（如 DPAD_*）要原样保留，
        # 保存时不能因为"没在面板上"就被抹掉。
        saved = dict(self.cfg.input.button_names or {}) if self.cfg else {}
        self._cal_extra = {k: v for k, v in saved.items() if k not in _CAL_BUTTONS}
        self._cal_sel = _CAL_BUTTONS.index("X") if "X" in _CAL_BUTTONS else 0
        self._cal_hits = []
        self._cal_btn_hits = []
        # 打开这一刻已经按着的键不算一次"按下"，否则会立刻误绑
        self._cal_prev_raw = frozenset(self.state.raw_buttons) if self.state else frozenset()
        self._cal_ignore_until = 0.0
        self._cal_dirty = False
        self._cal_message = ""
        self._cal_warning = ""
        self._cal_open = True
        # 校准期间暂停判定：否则按的键会被当成真实动作、还会震动
        if self.engine is not None:
            self.engine.set_paused(True)
        self._write_log("打开按键校准")

    def _close_calibration(self) -> None:
        self._cal_open = False
        self._cal_hits = []
        self._cal_btn_hits = []
        if self.engine is not None:
            self.engine.set_paused(False)
        if self._cal_dirty:
            self.notice = "按键校准已生效（本次运行）；要写进配置文件请按 S"
        self._write_log("关闭按键校准")

    def _cal_button(self, action: str) -> None:
        """校准面板底部按钮，和 S / Del / Esc 走同一套逻辑。"""
        if action == "save":
            self._cal_save()
        elif action == "clear":
            self._cal_clear()
        elif action == "close":
            self._close_calibration()

    def _on_calibration_key(self, key: int) -> None:
        pg = self.pg
        if key in (pg.K_ESCAPE, pg.K_b):
            self._close_calibration()
        elif key in (pg.K_UP, pg.K_LEFT):
            self._cal_sel = (self._cal_sel - 1) % len(_CAL_BUTTONS)
        elif key in (pg.K_DOWN, pg.K_RIGHT, pg.K_TAB):
            self._cal_sel = (self._cal_sel + 1) % len(_CAL_BUTTONS)
        elif key in (pg.K_DELETE, pg.K_BACKSPACE):
            self._cal_clear()
        elif key in (pg.K_s, pg.K_RETURN, pg.K_KP_ENTER):
            self._cal_save()

    def _cal_capture(self, now: float, state: PadState) -> None:
        """把"这一帧新按下的原始键"绑到高亮的那一行。"""
        raw = frozenset(state.raw_buttons)
        if now < self._cal_ignore_until:
            self._cal_prev_raw = raw
            return
        fresh = raw - self._cal_prev_raw
        self._cal_prev_raw = raw
        if not fresh:
            return

        index = min(fresh)          # 一次只认一个，组合键取编号最小的
        name = _CAL_BUTTONS[self._cal_sel]
        old = self._cal_map.get(name)
        for other, value in list(self._cal_map.items()):
            if other != name and value == index:
                self._cal_map[other] = None
        self._cal_map[name] = index
        self._cal_dirty = True

        self._cal_message = f"{name} ← 原始键 #{index}（要换下一项按 ↑↓ 或直接点它）"
        self._cal_warning = ""
        if old is not None and old != index:
            self._cal_message += f"，原本是 #{old}"
        self._apply_button_map()
        self._write_log(f"按键校准 {name} -> #{index}")
        # 不自动跳到下一行：用户常常连按好几颗键核对，跳行会把它们绑到错的名字上
        # 同一次按键可能连续几帧都算"新按下"，给个短暂的空窗
        self._cal_ignore_until = now + 0.18

    def _cal_clear(self) -> None:
        name = _CAL_BUTTONS[self._cal_sel]
        self._cal_map[name] = None
        self._cal_dirty = True
        self._cal_message = f"{name} 已清除（这一项退回自动识别）"
        self._apply_button_map()
        self._write_log(f"按键校准 清除 {name}")

    def _apply_button_map(self) -> None:
        """把校准表立刻套到正在跑的手柄源上，不用重开窗口。"""
        source = getattr(self.engine, "source", None) \
            if self.engine is not None else None
        setter = getattr(source, "set_button_names", None)
        if setter is None:
            return
        table = dict(self._cal_extra)
        table.update({k: v for k, v in self._cal_map.items() if v is not None})
        try:
            notes = setter(table)
        except Exception as exc:
            self._cal_message = f"应用失败：{type(exc).__name__}: {exc}"
            return
        # 清掉某一项后自动识别会把它补回来，界面上要如实显示
        live = self._layout_buttons()
        self._cal_map = {name: live.get(name) for name in _CAL_BUTTONS}
        if notes:
            self._cal_message += "；" + "；".join(notes)
        if self.cfg is not None:
            self.cfg.input.button_names = dict(table)

        # 改绑会把同编号的旧名字摘掉：如果摘掉的正好是某个动作要用的键，
        # 那个动作会直接失效，必须当场说出来（否则又是一轮"为什么识别不到"）。
        available = self._available_buttons()
        needed = set()
        for active in (self.engine.skills if self.engine is not None else []):
            needed.update(b for b in active.skill.required_buttons if b)
            button = active.skill.params.get("button")
            if button:
                try:
                    needed.add(canonical_button(button))
                except (TypeError, ValueError):
                    pass
        missing = sorted(b for b in needed if b not in available)
        self._cal_warning = (
            f"注意：{'、'.join(missing)} 现在没有绑定，用到它的动作会失效"
            if missing else "")

    def _cal_save(self) -> None:
        # 只把"和自动识别不一样"的那些写进配置：整张表写进去会把当前设备的
        # 编号钉死，换手柄就全错。拿不到基线时退回整张表。
        source = getattr(self.engine, "source", None) \
            if self.engine is not None else None
        getter = getattr(source, "button_overrides", None)
        if getter is not None:
            table = dict(getter())
        else:
            table = dict(self._cal_extra)
            table.update({k: v for k, v in self._cal_map.items() if v is not None})
        ok, message = self._persist_button_names(table)
        if ok:
            self._cal_dirty = False
            if table:
                self._cal_message = f"已保存 {len(table)} 处改动，下次启动直接生效"
            else:
                self._cal_message = "当前和自动识别一致，没有需要保存的改动"
            self.notice = "按键映射已保存到配置文件"
            self._write_log(f"按键校准保存 {table}")
            if self.cfg is not None:
                self.cfg.input.button_names = dict(table)
        else:
            self._cal_message = f"保存失败：{message}"
            self._write_log(f"按键校准保存失败：{message}")

    def _persist_button_names(self, table: Dict[str, int]) -> Tuple[bool, str]:
        """只改 input.button_names 这一项，不重写整份手改过的配置。"""
        try:
            text = self.config_path.read_bytes().decode("utf-8")
        except Exception as exc:
            return False, f"{type(exc).__name__}: {exc}"

        payload = json.dumps(table, ensure_ascii=False)
        match = re.search(r'"input"\s*:\s*', text)
        if match is None:
            return False, "配置里找不到 input 段"
        rest = text[match.end():]
        stripped = rest.lstrip()
        obj_start = match.end() + (len(rest) - len(stripped))
        if stripped.startswith("null"):
            # input 被手改成了 null：整段换成一个只含校准表的对象
            obj_end = obj_start + 4
            new_text = (text[:obj_start] + "{ \"button_names\": " + payload + " }"
                        + text[obj_end:])
        elif stripped.startswith("{"):
            try:
                _, length = json.JSONDecoder().raw_decode(text[obj_start:])
            except ValueError as exc:
                return False, f"input 段不是合法 JSON：{exc}"
            obj_end = obj_start + length

            # 只在 input 这一段里动刀：_readme 里也提到 button_names，
            # 全文替换会把说明文字写坏。
            segment = text[obj_start:obj_end]
            pattern = re.compile(r'("button_names"\s*:\s*)(null|\{[^{}]*\})')
            if pattern.search(segment):
                segment = pattern.sub(lambda m: m.group(1) + payload,
                                      segment, count=1)
            elif re.fullmatch(r"\{\s*\}", segment):
                # 空的 input 段（可能带换行/空格）：不能留逗号，否则 JSON 无效
                segment = "{\n    " + f'"button_names": {payload}' + "\n  }"
            else:
                segment = "{" + f'\n    "button_names": {payload},' + segment[1:]
            new_text = text[:obj_start] + segment + text[obj_end:]
        else:
            return False, "配置里的 input 既不是对象也不是 null"

        try:
            data = json.loads(new_text.lstrip("\ufeff"))
        except Exception as exc:
            return False, f"写入后 JSON 无效：{exc}"
        if (data.get("input") or {}).get("button_names") != table:
            return False, "写入校验失败"

        tmp = self.config_path.with_suffix(self.config_path.suffix + ".tmp")
        try:
            tmp.write_bytes(new_text.encode("utf-8"))
            os.replace(tmp, self.config_path)
        except Exception as exc:
            try:
                tmp.unlink()
            except OSError:
                pass
            return False, f"{type(exc).__name__}: {exc}"
        return True, ""

    def _scroll_history(self, delta: int) -> None:
        max_off = max(0, len(self.history) - self._HISTORY_ROWS)
        self.history_scroll = max(0, min(max_off,
                                         self.history_scroll + int(delta)))

    def _open_config_folder(self) -> None:
        folder = self.config_path.parent
        try:
            folder.mkdir(parents=True, exist_ok=True)
            if sys.platform == "win32":
                os.startfile(str(folder))  # type: ignore[attr-defined]
                self.notice = f"已打开 {folder}"
            elif sys.platform == "darwin":
                subprocess.Popen(["open", str(folder)])
                self.notice = f"已打开 {folder}"
            else:
                subprocess.Popen(["xdg-open", str(folder)])
                self.notice = f"已打开 {folder}"
        except Exception as exc:
            self.notice = f"打不开文件夹：{exc}"

    # ------------------------------------------------------------------
    # 绘制
    # ------------------------------------------------------------------

    def _draw(self, now: float) -> None:
        if self.screen is None:
            return
        self.screen.fill(BG)
        self._draw_header(now)
        if self.config_error is not None:
            self._draw_config_error()
        elif self.opening:
            self._draw_opening()
        elif self.engine is None:
            self._draw_no_device()
        else:
            self._draw_skills()
            self._draw_result()
            self._draw_history()
            self._draw_footer(now)
            if self._cal_open:
                self._draw_calibration()
        try:
            self.pg.display.flip()
        except Exception:
            pass

    # -- 基础绘制工具 --------------------------------------------------

    def _panel(self, rect, color=PANEL, radius: int = 14) -> None:
        self.pg.draw.rect(self.screen, color, rect, border_radius=radius)

    def _text(self, text: str, x: int, y: int, size: int, color,
              bold: bool = False, anchor: str = "topleft"):
        if not text:
            return None
        font = self._fonts.get(size, bold)
        surf = font.render(text, True, color)
        rect = surf.get_rect(**{anchor: (x, y)})
        self.screen.blit(surf, rect)
        return rect

    def _mark(self, x: float, y: float, size: float, ok: bool, color,
              width: int = 0) -> None:
        """画 ✓ / ✗。

        不依赖字体：微软雅黑 / 苹方里都没有 U+2713（会渲染成方块），
        用线段画既能保证显示，又比字符锐利。
        """
        w = width or max(3, int(size * 0.13))
        if ok:
            pts = [(x + size * 0.10, y + size * 0.52),
                   (x + size * 0.38, y + size * 0.80),
                   (x + size * 0.90, y + size * 0.16)]
            self.pg.draw.lines(self.screen, color, False, pts, w)
        else:
            self.pg.draw.line(self.screen, color,
                              (x + size * 0.16, y + size * 0.16),
                              (x + size * 0.84, y + size * 0.84), w)
            self.pg.draw.line(self.screen, color,
                              (x + size * 0.84, y + size * 0.16),
                              (x + size * 0.16, y + size * 0.84), w)

    def _fit(self, text: str, size: int, width: int, bold: bool = False) -> str:
        font = self._fonts.get(size, bold)
        if font.size(text)[0] <= width:
            return text
        lo, hi = 0, len(text)
        while lo < hi:
            mid = (lo + hi + 1) // 2
            if font.size(text[:mid] + "…")[0] <= width:
                lo = mid
            else:
                hi = mid - 1
        return text[:lo] + "…"

    def _wrap(self, text: str, size: int, width: int,
              bold: bool = False) -> List[str]:
        font = self._fonts.get(size, bold)
        lines: List[str] = []
        cur = ""
        for token in _TOKEN.findall(text):
            trial = cur + token
            if not cur or font.size(trial)[0] <= width:
                cur = trial
            else:
                lines.append(cur.rstrip())
                cur = "" if token.isspace() else token
        if cur.strip():
            lines.append(cur.rstrip())
        return lines

    def _wrap_lines(self, text: str, size: int, width: int,
                    bold: bool = False) -> List[str]:
        """保留原文的换行再逐行折行——配置报错是多行的。"""
        out: List[str] = []
        for raw in text.splitlines() or [""]:
            out.extend(self._wrap(raw, size, width, bold) or [""])
        return out

    @staticmethod
    def _short_name(name: str) -> str:
        return name.split(" (")[0].strip()

    # -- 顶部 ----------------------------------------------------------

    @staticmethod
    def _stick_point(cx: float, cy: float, radius: float,
                     x: float, y: float) -> Tuple[float, float]:
        """摇杆原始坐标 -> 屏幕坐标。

        SDL 的 y 轴**向下为正**，屏幕坐标也是向下为正，所以这里直接相加。
        取负会把"上推"画成"下拉"——看起来就像手柄的上下反了。
        """
        return cx + x * radius, cy + y * radius

    def _draw_header(self, now: float) -> None:
        self._text(APP_TITLE, 24, 14, 22, TEXT, bold=True)
        self._text("震一下 = 做对了；没震就是还没到位", 26, 44, 12, MUTED)

        right = W - 24
        if self.config_error is not None:
            self._text("配置有错误", right, 16, 15, RED, anchor="topright")
            self._text("R 重新加载", right, 42, 12, MUTED, anchor="topright")
            return

        if self.engine is not None:
            label = self._fit(
                f"{self.device_label}   ·   {self.rumble_label}", 14, 560)
            self._text(label, right, 16, 14, TEXT, anchor="topright")
            elapsed = max(0.0, now - self.engine.started_at) if now else 0.0
            clock = f"{int(elapsed) // 60:02d}:{int(elapsed) % 60:02d}"
            self._text(clock, right, 40, 16, MUTED, bold=True, anchor="topright")
        else:
            self._text("未连接手柄", right, 16, 14, MUTED, anchor="topright")

    # -- 左栏：动作熟练度 ----------------------------------------------

    def _draw_skills(self) -> None:
        assert self.engine is not None
        panel = self.pg.Rect(20, 74, 300, 428)
        self._panel(panel)
        self._text("动作熟练度", panel.x + 16, panel.y + 12, 12, MUTED)
        if self.engine.focus is not None:
            label = f"专项：{self._short_name(self.engine.focus.skill.name)}"
            self._text(self._fit(label, 11, 170), panel.right - 16,
                       panel.y + 13, 11, ACCENT, anchor="topright")
        else:
            self._text("开关＝专项", panel.right - 16, panel.y + 14, 10,
                       FAINT, anchor="topright")

        skills = self.engine.skills
        n = max(1, len(skills))
        top = panel.y + 38
        avail = panel.height - 38 - 14
        gap = 8 if n <= 4 else 4
        card_h = int((avail - gap * (n - 1)) / n)
        card_h = max(30, min(92, card_h))

        self._modifier_hits = []
        self._focus_hits = []
        for i, active in enumerate(skills):
            rect = self.pg.Rect(panel.x + 12, top + i * (card_h + gap),
                                panel.width - 24, card_h)
            self._skill_card(active, rect)

    def _skill_card(self, active, rect) -> None:
        pg = self.pg
        last = active.last_outcome
        focus = self.engine.focus if self.engine is not None else None
        focused = focus is active
        dimmed = focus is not None and not focused

        accent = FAINT
        if last is not None and not dimmed:
            accent = GREEN if last.ok else RED
        if focused:
            accent = ACCENT

        # 置灰用更暗的底色，专项练习的那一张描一圈高亮边
        pg.draw.rect(self.screen, PANEL if dimmed else CARD, rect,
                     border_radius=10)
        pg.draw.rect(self.screen, accent,
                     pg.Rect(rect.x, rect.y + 10, 4, rect.height - 20),
                     border_radius=2)
        if focused:
            pg.draw.rect(self.screen, ACCENT, rect, border_radius=10, width=2)

        # 每 10 个正确动作一组：进度条只反映本组进度，做满 10 个由引擎清零。
        group = min(active.group_hits, Engine.GROUP_SIZE)
        rate = 100.0 * group / Engine.GROUP_SIZE
        rate_color = GREEN if group > 0 and not dimmed else FAINT

        # 动作多了（用户自己往配置里加）卡片会变矮，按剩余高度决定显示几行
        small = rect.height < 56
        name_size = 12 if small else 14

        # 卡片最左边是"专项练习"开关：打开后其它动作全部置灰、不再参与判定
        switch = pg.Rect(rect.x + 12, rect.y + (6 if small else 8), 36, 18)
        self._draw_switch(switch, focused, dimmed)
        self._focus_hits.append((switch, active))

        name = self._fit(self._short_name(active.skill.name), name_size,
                         rect.width - 160)
        self._text(name, switch.right + 8, rect.y + (5 if small else 8),
                   name_size, FAINT if dimmed else TEXT)
        # 进度条上方：本次运行累计成功次数 + 大号"本组第几次/10"
        hits_color = MUTED if dimmed and active.hits > 0 else (
            TEXT if active.hits > 0 else FAINT)
        self._text(f"成功 {active.hits}", rect.right - 66,
                   rect.y + (6 if small else 10), 10, hits_color,
                   anchor="topright")
        self._text(f"{group}/{Engine.GROUP_SIZE}",
                   rect.right - 12, rect.y + (4 if small else 7),
                   15 if small else 16, rate_color, bold=True, anchor="topright")

        # 可选修饰键（绿色搓射：RB / RT）。画在卡片右下角，点一下就切换；
        # 选中的键用填充色高亮。状态文字要为它让出宽度，避免叠在一起。
        options = tuple(active.skill.params.get("modifier_options") or ())
        selected = (active.skill.required_buttons[0]
                    if active.skill.required_buttons else None)
        reserve = 0
        if len(options) > 1 and rect.height >= 50:
            chip_font = self._fonts.get(10, True)
            widths = [max(28, chip_font.size(opt)[0] + 14) for opt in options]
            total = sum(widths) + 4 * (len(options) - 1)
            x = rect.right - 12 - total
            y = rect.bottom - 23
            reserve = total + 10
            for opt, width in zip(options, widths):
                on = opt == selected
                chip = pg.Rect(x, y, width, 18)
                pg.draw.rect(self.screen, ACCENT if on else LINE,
                             chip, border_radius=9)
                self._text(opt, chip.centerx, chip.y + 2, 10,
                           BG if on else MUTED, bold=on, anchor="midtop")
                self._modifier_hits.append((chip, active, opt))
                x += width + 4

        if not small:
            bar_x, bar_y = rect.x + 14, rect.y + 34
            bar_w = rect.width - 28
            pg.draw.rect(self.screen, LINE, pg.Rect(bar_x, bar_y, bar_w, 5),
                         border_radius=3)
            if rate > 0:
                pg.draw.rect(self.screen, rate_color,
                             pg.Rect(bar_x, bar_y, int(bar_w * rate / 100.0), 5),
                             border_radius=3)

        if rect.height >= 68 and not dimmed:
            # 正在做这个动作时优先显示实时进度（"保持 210/350ms"、"方向不对…"），
            # 这是排查"为什么识别不到"最直接的线索；否则显示最近一次结果。
            status = active.detector.status()
            if status and status != "待机":
                self._text(self._fit(status, 11, rect.width - 28 - reserve),
                           rect.x + 14, rect.y + 50, 11, ACCENT)
            elif last is not None:
                if last.ok:
                    # √ / × 用的是中文标点区里的字符，雅黑/苹方都有，
                    # 不会像 ✓ / ✗ 那样显示成方块
                    detail, color = f"最近 √ {last.elapsed_ms:.0f}ms", GREEN
                else:
                    label = Detector.FAILURE_LABELS.get(last.code, last.code)
                    detail, color = f"最近 × {label}", RED
                self._text(self._fit(detail, 11, rect.width - 28 - reserve),
                           rect.x + 14, rect.y + 50, 11, color)

    def _draw_switch(self, rect, on: bool, dimmed: bool) -> None:
        """卡片左边的专项练习开关。命中区由 _skill_card 记录。"""
        pg = self.pg
        if on:
            track, knob = ACCENT, BG
        elif dimmed:
            track, knob = (44, 48, 60), (86, 92, 108)
        else:
            track, knob = (66, 72, 90), (190, 196, 210)
        pg.draw.rect(self.screen, track, rect, border_radius=rect.height // 2)
        knob_r = rect.height // 2 - 2
        cx = (rect.right - rect.height // 2) if on else (rect.x + rect.height // 2)
        pg.draw.circle(self.screen, knob, (cx, rect.centery), knob_r)

    # -- 中央：最近一次结果 --------------------------------------------

    def _draw_result(self) -> None:
        pg = self.pg
        assert self.engine is not None
        panel = pg.Rect(336, 74, 544, 252)
        self._panel(panel)

        outcome = self.engine.last_outcome
        self._text("最近一次", panel.x + 24, panel.y + 14, 12, MUTED)

        if outcome is None:
            self._text("等待第一次尝试", panel.x + 24, panel.y + 64,
                       26, TEXT, bold=True)
            self._text("推右摇杆做出动作；做对了会震一下。",
                       panel.x + 26, panel.y + 108, 15, MUTED)
            self._text("失败不会震，只会在这里告诉你差在哪儿。",
                       panel.x + 26, panel.y + 134, 13, FAINT)
            return

        ok = outcome.ok
        color = GREEN if ok else RED
        title = "做对了" if ok else "没做对"

        self._mark(panel.x + 22, panel.y + 36, 56, ok, color)
        self._text(self._short_name(outcome.skill_name),
                   panel.x + 96, panel.y + 40, 25, TEXT, bold=True)
        self._text(title, panel.x + 97, panel.y + 76, 15, color)
        self._text(f"{outcome.elapsed_ms:.0f} ms",
                   panel.right - 24, panel.y + 40, 18, MUTED,
                   anchor="topright")

        if ok:
            body = "动作识别成功，手柄已经震动过了。"
            advice = "保持这个节奏，继续练下一个。"
            advice_color = GREEN
        else:
            body = outcome.message or Detector.FAILURE_LABELS.get(
                outcome.code, "没有做到位")
            advice = _ADVICE.get(outcome.code, "再试一次，注意动作的起手和收尾。")
            advice_color = AMBER

        y = panel.y + 122
        for line in self._wrap(body, 17, panel.width - 48)[:2]:
            self._text(line, panel.x + 24, y, 17, TEXT)
            y += 26

        if advice:
            self._text(self._fit(advice, 13, panel.width - 48),
                       panel.x + 24, panel.y + 186, 13, advice_color)

    # -- 中央：最近几次 -------------------------------------------------

    def _draw_history(self) -> None:
        pg = self.pg
        panel = pg.Rect(336, 336, 544, 166)
        self._panel(panel)
        self._text("最近的尝试", panel.x + 20, panel.y + 10, 12, MUTED)
        if self.history:
            hint = f"滚轮滚动 · 保留最近 {len(self.history)}/50 条"
            self._text(hint, panel.right - 20, panel.y + 10, 10, FAINT,
                       anchor="topright")

        if not self.history:
            self._text("还没有记录。", panel.x + 20, panel.y + 46, 13, FAINT)
            return

        max_off = max(0, len(self.history) - self._HISTORY_ROWS)
        self.history_scroll = max(0, min(max_off, self.history_scroll))

        # 一行一条：左边是动作（时间 / ✓✗ / 名称），右边是详情
        # （毫秒 + 旋转角度或失败原因），成功灰色、失败红色。
        row_h = 26
        top = panel.y + 32
        for i in range(self._HISTORY_ROWS):
            idx = self.history_scroll + i
            if idx >= len(self.history):
                break
            stamp, outcome = self.history[idx]
            y = top + i * row_h
            color = GREEN if outcome.ok else RED
            self._text(stamp, panel.x + 20, y + 4, 10, FAINT)
            self._mark(panel.x + 74, y + 2, 12, outcome.ok, color, 2)
            name = self._fit(self._short_name(outcome.skill_name), 12, 150)
            self._text(name, panel.x + 92, y + 2, 12, TEXT)

            # 详情从动作名右边开始排，右对齐到面板边缘；空间够就不截断
            name_w = self._fonts.get(12, False).size(name)[0]
            detail_x = panel.x + 92 + name_w + 14
            detail_w = max(120, panel.right - 20 - detail_x)
            detail = f"{outcome.elapsed_ms:.0f} ms"
            if outcome.ok:
                if outcome.detail:
                    detail += f" · {outcome.detail}"
                detail_color = MUTED
            else:
                message = outcome.message or Detector.FAILURE_LABELS.get(
                    outcome.code, outcome.code)
                detail += f" · {message}"
                detail_color = RED
            self._text(self._fit(detail, 10, detail_w),
                       panel.right - 20, y + 4, 10, detail_color,
                       anchor="topright")

        if len(self.history) > self._HISTORY_ROWS:
            track_x = panel.right - 8
            track_top = top
            track_h = self._HISTORY_ROWS * row_h - 4
            thumb_h = max(16, int(track_h * self._HISTORY_ROWS / len(self.history)))
            span = max(1, max_off)
            thumb_y = track_top + int((track_h - thumb_h) * self.history_scroll / span)
            pg.draw.rect(self.screen, LINE,
                         pg.Rect(track_x, track_top, 3, track_h), border_radius=2)
            pg.draw.rect(self.screen, ACCENT,
                         pg.Rect(track_x, thumb_y, 3, thumb_h), border_radius=2)

    # -- 底部：摇杆可视化 + 快捷键 --------------------------------------

    def _draw_footer(self, now: float) -> None:
        pg = self.pg
        panel = pg.Rect(20, 512, 860, 88)
        self._panel(panel)

        # 一个圆环同时显示两个方向：红 = 左摇杆（球员朝向），蓝 = 右摇杆。
        # 两条指针都从圆心指向当前方向，顶端带圆球，像手表指针一样便于目测夹角。
        state = self.state or PadState()
        engine = self.engine
        facing = engine.facing if engine is not None else 0.0
        facing_ok = engine.facing_valid if engine is not None else False
        rs_on = state.rs_mag >= 0.02

        cx, cy, r = 64, panel.y + 46, 36
        pg.draw.circle(self.screen, LINE, (cx, cy), r, 2)
        pg.draw.line(self.screen, LINE, (cx - r, cy), (cx + r, cy), 1)
        pg.draw.line(self.screen, LINE, (cx, cy - r), (cx, cy + r), 1)
        pg.draw.circle(self.screen, FAINT, (cx, cy), 3)

        def hand(angle: float, color, on: bool,
                 width: int, ball: int) -> None:
            if not on:
                return
            rad = math.radians(angle)
            # 两条指针都伸到圆环内缘：球心 = r - 球半径，所以两个球的
            # 外缘都正好贴住圆环。红球/红线比蓝的粗 2px。
            reach = r - ball
            tip = (cx + int(math.sin(rad) * reach),
                   cy - int(math.cos(rad) * reach))
            pg.draw.line(self.screen, color, (cx, cy), tip, width)
            pg.draw.circle(self.screen, color, tip, ball)

        # 红色先画、且线条/球都比蓝色大 2px；方向重合时蓝色压在红色上，
        # 仍能看见红色露出的边缘。两条指针长度完全一样。
        hand(facing, RED, facing_ok, 5, 7)
        hand(state.rs_angle, ACCENT, rs_on, 3, 5)

        # 文字区只显示“右摇杆相对球员朝向”的角度。
        # 绝对角度需要自己在脑子里减去朝向，没有意义，所以一律不显示。
        tx = 112
        if facing_ok and rs_on:
            rel = angle_diff(state.rs_angle, facing)
            self._text("右摇杆 相对", tx, panel.y + 12, 10, ACCENT)
            self._text(f"{rel:.0f}°", tx + 64, panel.y + 6, 19, TEXT, bold=True)
        elif not facing_ok:
            self._text("左摇杆回中", tx, panel.y + 8, 13, AMBER, bold=True)
        else:
            self._text("推右摇杆做动作", tx, panel.y + 8, 12, FAINT)

        if facing_ok:
            self._text(f"球员朝向 {direction_name(facing)}",
                       tx, panel.y + 34, 11, RED)
        elif rs_on:
            self._text("右摇杆 已推（无朝向基准）",
                       tx, panel.y + 34, 10, ACCENT)
        else:
            self._text("右摇杆 居中", tx, panel.y + 34, 10, FAINT)
        if not facing_ok:
            self._text("方向类动作暂不可用", tx, panel.y + 52, 10, AMBER)

        # 快捷键按钮：鼠标点一下和按键等效
        right = W - 40
        self._draw_hotkeys(right, panel.y + 10)
        hint = self.notice or ("卡片开关＝专项（数字键）· T 切修饰键 · "
                               "L1 的动作要先按键再推杆")
        self._text(self._fit(hint, 10, 480), right, panel.y + 40,
                   10, ACCENT if self.notice else FAINT, anchor="topright")
        if not self._fonts.cjk_ok:
            self._text("未找到中文字体，部分文字可能显示为方块", right,
                       panel.y + 60, 10, AMBER, anchor="topright")
        else:
            self._text(self._fit(f"配置文件：{self.config_path}", 10, 480),
                       right, panel.y + 60, 10, FAINT, anchor="topright")

    def _draw_hotkeys(self, right: int, y: int) -> None:
        """底部的快捷键按钮。键盘按和鼠标点走同一套动作。"""
        pg = self.pg
        self._hotkey_hits = []
        font = self._fonts.get(11, True)
        try:
            mouse = pg.mouse.get_pos()
        except Exception:
            mouse = (-1, -1)
        x = right
        for action, key, label in reversed(_HOTKEYS):
            text = f"{key} {label}"
            width = font.size(text)[0] + 18
            rect = pg.Rect(x - width, y, width, 22)
            hover = rect.collidepoint(mouse)
            pg.draw.rect(self.screen, (48, 54, 70) if hover else CARD,
                         rect, border_radius=11)
            pg.draw.rect(self.screen, ACCENT if hover else LINE,
                         rect, border_radius=11, width=1)
            self._text(text, rect.centerx, rect.centery, 11,
                       TEXT if hover else MUTED, bold=True, anchor="center")
            self._hotkey_hits.append((rect, action))
            x -= width + 6

    # -- 按键校准面板 ---------------------------------------------------

    def _draw_calibration(self) -> None:
        pg = self.pg
        mask = pg.Surface((W, H), pg.SRCALPHA)
        mask.fill((8, 9, 13, 205))
        self.screen.blit(mask, (0, 0))

        panel = pg.Rect(48, 52, W - 96, H - 104)
        self._cal_panel_rect = panel
        self._panel(panel, CARD, 16)
        self._text("按键校准", panel.x + 26, panel.y + 16, 22, TEXT, bold=True)
        tip = ("按下手柄上的键，就绑到高亮的那一项。绿色搓射只要对准 "
               "X（要连按的键）和 RB（要按住的键）。")
        self._text(self._fit(tip, 12, panel.width - 52),
                   panel.x + 26, panel.y + 46, 12, MUTED)
        tip2 = "LT / RT 一般由扳机轴自动识别，不用绑；如果扳机是数字键，按一下它就能绑上。"
        self._text(self._fit(tip2, 11, panel.width - 52),
                   panel.x + 26, panel.y + 68, 11, FAINT)

        col_w = (panel.width - 52 - 16) // 2
        row_h = 40
        top = panel.y + 96
        self._cal_hits = []
        index = 0
        for col, names in enumerate(_CAL_COLUMNS):
            for row, name in enumerate(names):
                box = pg.Rect(panel.x + 26 + col * (col_w + 16),
                              top + row * row_h, col_w, row_h - 6)
                selected = (index == self._cal_sel)
                pg.draw.rect(self.screen, (44, 56, 84) if selected else PANEL,
                             box, border_radius=8)
                if selected:
                    pg.draw.rect(self.screen, ACCENT, box,
                                 border_radius=8, width=2)
                self._text(name, box.x + 12, box.centery, 14, TEXT,
                           bold=selected, anchor="midleft")
                value = self._cal_map.get(name)
                label = "未绑定" if value is None else f"#{value}"
                self._text(label, box.right - 12, box.centery, 13,
                           FAINT if value is None else ACCENT,
                           bold=value is not None, anchor="midright")
                if selected:
                    self._text("按手柄键…", box.right - 74, box.centery, 11,
                               AMBER, anchor="midright")
                self._cal_hits.append((box, index))
                index += 1

        raw = ",".join(str(i) for i in sorted(self._cal_prev_raw)) or "无"
        y = panel.bottom - 120
        if self._cal_message:
            self._text(self._fit(self._cal_message, 12, panel.width - 52),
                       panel.x + 26, y, 12, GREEN)
        if self._cal_warning:
            for i, line in enumerate(
                    self._wrap(self._cal_warning, 11, panel.width - 52)[:2]):
                self._text(line, panel.x + 26, y + 18 + i * 17, 11, AMBER)
        self._text(f"当前按下的原始键：{raw}", panel.x + 26, y + 58, 11, FAINT)

        # 底部一排按钮：鼠标点即可，键盘 S / Del / Esc 同效
        left = self._draw_cal_buttons(panel, panel.bottom - 38)
        hint = "点一行选中它 · 选中后按手柄上的键就能绑定 · ↑↓ 也能换行"
        self._text(self._fit(hint, 10, max(120, left - panel.x - 38)),
                   panel.x + 26, panel.bottom - 32, 10, MUTED)

    def _draw_cal_buttons(self, panel, y: int) -> int:
        """校准面板底部的保存/清除/关闭按钮。返回最左边的 x。"""
        pg = self.pg
        self._cal_btn_hits = []
        font = self._fonts.get(11, True)
        try:
            mouse = pg.mouse.get_pos()
        except Exception:
            mouse = (-1, -1)
        specs = (("save", "S 保存", True),
                 ("clear", "Del 清除", False),
                 ("close", "Esc 关闭", False))
        x = panel.right - 26
        for action, text, primary in reversed(specs):
            width = font.size(text)[0] + 20
            rect = pg.Rect(x - width, y, width, 26)
            hover = rect.collidepoint(mouse)
            if primary:
                bg = (32, 92, 160) if hover else (28, 72, 120)
                border, fg = ACCENT, TEXT
            else:
                bg = (48, 54, 70) if hover else CARD
                border = ACCENT if hover else LINE
                fg = TEXT if hover else MUTED
            pg.draw.rect(self.screen, bg, rect, border_radius=13)
            pg.draw.rect(self.screen, border, rect, border_radius=13, width=1)
            self._text(text, rect.centerx, rect.centery, 11, fg,
                       bold=True, anchor="center")
            self._cal_btn_hits.append((rect, action))
            x -= width + 8
        return x

    # -- 无手柄 / 连接中 / 配置错误 -------------------------------------

    def _draw_opening(self) -> None:
        panel = self.pg.Rect(20, 74, 860, 428)
        self._panel(panel)
        self._text("正在连接手柄…", W // 2, panel.centery - 12, 26, TEXT,
                   bold=True, anchor="center")
        self._text("首次连接会花 0.25 秒校准扳机静止值", W // 2,
                   panel.centery + 28, 13, MUTED, anchor="center")

    def _draw_no_device(self) -> None:
        pg = self.pg
        panel = pg.Rect(20, 74, 860, 428)
        self._panel(panel)

        self._text("未检测到手柄", W // 2, panel.y + 54, 30, TEXT,
                   bold=True, anchor="midtop")

        y = panel.y + 108
        message = self.error or "请确认手柄已连接并开机。"
        for line in self._wrap_lines(message, 14, panel.width - 160)[:4]:
            self._text(line, panel.x + 80, y, 14, MUTED)
            y += 22

        y = max(y + 18, panel.y + 200)
        tips = []
        if sys.platform == "darwin":
            tips = [
                "macOS：系统设置 → 隐私与安全性 → 输入监控，把本应用勾上。",
                "有线连接通常比蓝牙更容易驱动震动。",
            ]
        elif sys.platform == "win32":
            tips = [
                "换一个 USB 口，或把手柄切到 XInput 模式。",
                "有线连接通常比蓝牙更容易驱动震动。",
            ]
        else:
            tips = ["确认手柄已连接，并且有 /dev/input 的访问权限。"]
        for tip in tips:
            self._text("· " + tip, panel.x + 80, y, 13, FAINT)
            y += 24

        self._text("插上手柄后会自动重试，也可以按 R 立即重试。",
                   W // 2, panel.bottom - 74, 13, ACCENT, anchor="midtop")
        self._text("C 打开配置文件夹      Esc 退出",
                   W // 2, panel.bottom - 44, 11, FAINT, anchor="midtop")

    def _draw_config_error(self) -> None:
        pg = self.pg
        panel = pg.Rect(20, 74, 860, 428)
        self._panel(panel)
        self._text("配置文件有错误", W // 2, panel.y + 46, 28, RED,
                   bold=True, anchor="midtop")

        y = panel.y + 100
        for line in self._wrap_lines(self.config_error or "", 14,
                                     panel.width - 160)[:10]:
            self._text(line, panel.x + 80, y, 14, TEXT)
            y += 24

        self._text("改好保存后按 R 重新加载。", W // 2, panel.bottom - 74,
                   13, ACCENT, anchor="midtop")
        self._text("C 打开配置文件夹      Esc 退出",
                   W // 2, panel.bottom - 44, 11, FAINT, anchor="midtop")


# ---------------------------------------------------------------------------
# 入口
# ---------------------------------------------------------------------------

def main_gui(config_path: Optional[str] = None, index: Optional[int] = None,
             demo: bool = False) -> int:
    """打开练习窗口。返回进程退出码。"""
    import pygame

    # 让 SDL 把窗口摆到屏幕中央：否则 Windows 会从左上角往下排，
    # 在小屏幕上底部那行快捷键会被任务栏/屏幕边缘挡住。
    os.environ.setdefault("SDL_VIDEO_CENTERED", "1")

    pygame.display.init()
    pygame.font.init()
    pygame.joystick.init()

    try:
        pygame.display.set_caption(APP_TITLE)
    except Exception:
        pass

    try:
        screen = pygame.display.set_mode(
            (W, H), pygame.SCALED | pygame.RESIZABLE)
    except pygame.error:
        screen = pygame.display.set_mode((W, H))

    app = TrainerApp(pygame, config_path, index, demo)
    app.screen = screen
    try:
        return app.run()
    finally:
        app._shutdown()
