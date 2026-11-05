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

W, H = 960, 660
FPS = 60

# ---- 几何（与设计稿 desktop.html 对齐，全部程序化绘制） ----
MARGIN_X, MARGIN_Y = 20, 16
HEADER_H = 104
GAP = 14
FOOTER_H = 78
LEFT_W = 316
BODY_Y = 134            # MARGIN_Y + HEADER_H + GAP
FOOTER_Y = 566          # H - MARGIN_Y - FOOTER_H
GRID_H = 418            # FOOTER_Y - GAP - BODY_Y
RIGHT_X = 350           # MARGIN_X + LEFT_W + GAP
RIGHT_W = 590
DETAIL_H = 212
ATTEMPTS_Y = 360        # BODY_Y + DETAIL_H + GAP
ATTEMPTS_H = 192
FULL_H = 510            # H - MARGIN_Y - BODY_Y，无底栏页面的整块正文卡

# ---- 配色（亮色，卡片白 + 高对比结果色） ----
BG = (245, 245, 247)
CARD = (255, 255, 255)
CARD_SOFT = (250, 250, 252)
LINE = (236, 236, 240)
LINE_STRONG = (224, 224, 229)
TEXT = (29, 29, 31)
MUTED = (110, 110, 115)
FAINT = (114, 114, 119)
TEXT_SOFT = (58, 58, 60)
GREEN = (6, 138, 54)
GREEN_DEEP = (4, 107, 42)
GREEN_FILL = (0, 200, 83)
GREEN_SOFT = (226, 251, 236)
GREEN_LINE = (232, 250, 240)
RED = (215, 0, 21)
RED_SOFT = (255, 233, 234)
RED_LINE = (255, 226, 208)
ACCENT = (0, 113, 227)
ACCENT_SOFT = (233, 242, 255)
BLUE_LINE = (168, 202, 240)
AMBER = (194, 65, 12)
AMBER_SOFT = (255, 240, 227)
ORANGE = (255, 138, 31)
CYAN = (14, 159, 212)
CYAN_DEEP = (11, 110, 146)
CYAN_SOFT = (231, 247, 253)
HOVER = (247, 247, 249)
ICON_IDLE = (166, 166, 172)
DIM_TEXT = (166, 166, 172)
DIM_SOFT = (190, 190, 196)
DIALOG_MASK = (28, 28, 32)

# "马赛回旋 Roulette" -> ("马赛回旋", "Roulette")；没有 ASCII 后缀时整串都是中文名
_SPLIT_NAME = re.compile(r"^(.*?)\s+([A-Za-z][A-Za-z0-9 '\-/.]*)$")

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

def _pingfang_paths() -> List[str]:
    """macOS 的苹方可能以 MobileAsset 形式安装；不要在运行时用私有 UI 变体。"""
    root = Path("/System/Library/AssetsV2")
    if not root.exists():
        return []
    try:
        return sorted(str(path) for path in root.glob(
            "com_apple_MobileAsset_Font*/**/PingFang.ttc"))
    except OSError:
        return []


def _font_files() -> List[str]:
    if sys.platform == "win32":
        return [
            r"C:\Windows\Fonts\msyh.ttc",          # 微软雅黑
            r"C:\Windows\Fonts\msyhbd.ttc",
            r"C:\Windows\Fonts\simhei.ttf",        # 黑体
            r"C:\Windows\Fonts\simsun.ttc",
        ]
    if sys.platform == "darwin":
        return _pingfang_paths() + [
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


def _asset_path(name: str) -> Optional[Path]:
    """定位随包发布的图片：源码运行、PyInstaller onefile/onedir 都能找。"""
    roots = [Path(__file__).resolve().parent / "assets"]
    meipass = getattr(sys, "_MEIPASS", None)
    if meipass:
        roots.append(Path(meipass) / "padskills" / "assets")
    exe_dir = Path(sys.executable).resolve().parent
    roots.append(exe_dir / "padskills" / "assets")
    # macOS .app：PyInstaller 的 datas 默认落在 Contents/Resources
    roots.append(exe_dir.parent / "Resources" / "padskills" / "assets")
    for root in roots:
        path = root / name
        if path.exists():
            return path
    return None


def _first_existing(paths: List[str]) -> Optional[str]:
    for path in paths:
        if os.path.exists(path):
            return path
    return None


def _ui_font_paths() -> Tuple[Optional[str], Optional[str], Optional[str]]:
    """(常规主字体, 粗体主字体, 中文回退字体)。

    macOS 用苹果默认的 SF Pro Text + 苹方；Windows 用微软雅黑；
    Linux 用 Noto Sans CJK。主字体负责 ASCII，中文走回退字体。
    """
    if sys.platform == "darwin":
        regular = _first_existing([
            "/Library/Fonts/SF-Pro-Text-Regular.otf",
            "/Library/Fonts/SF-Pro-Display-Regular.otf",
            "/System/Library/Fonts/SFNS.ttf",
            "/System/Library/Fonts/HelveticaNeue.ttc",
        ])
        bold = _first_existing([
            "/Library/Fonts/SF-Pro-Text-Semibold.otf",
            "/Library/Fonts/SF-Pro-Text-Bold.otf",
            "/Library/Fonts/SF-Pro-Display-Semibold.otf",
            "/System/Library/Fonts/SFNS.ttf",
            "/System/Library/Fonts/HelveticaNeue.ttc",
        ])
        cjk = _first_existing(_pingfang_paths() + [
            "/System/Library/Fonts/Hiragino Sans GB.ttc",
            "/System/Library/Fonts/STHeiti Medium.ttc",
            "/Library/Fonts/Arial Unicode.ttf",
        ])
        return regular, bold, cjk

    if sys.platform == "win32":
        regular = _first_existing([
            r"C:\Windows\Fonts\msyh.ttc",
            r"C:\Windows\Fonts\msyhbd.ttc",
            r"C:\Windows\Fonts\simhei.ttf",
            r"C:\Windows\Fonts\simsun.ttc",
        ])
        bold = _first_existing([
            r"C:\Windows\Fonts\msyhbd.ttc",
            r"C:\Windows\Fonts\msyh.ttc",
            r"C:\Windows\Fonts\simhei.ttf",
        ])
        return regular, bold, regular

    regular = _first_existing([
        "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
        "/usr/share/fonts/noto-cjk/NotoSansCJK-Regular.ttc",
        "/usr/share/fonts/truetype/wqy/wqy-microhei.ttc",
        "/usr/share/fonts/truetype/arphic/uming.ttc",
    ])
    return regular, regular, regular


class _UiFont:
    """ASCII 走主字体（SF Pro / 微软雅黑），中文走回退字体（苹方）。"""

    def __init__(self, primary, fallback) -> None:
        self.primary = primary
        self.fallback = fallback
        self.height = max(primary.get_height(), fallback.get_height()) + 2
        self.ascent = max(primary.get_ascent(), fallback.get_ascent())

    @staticmethod
    def _is_ascii(ch: str) -> bool:
        return ord(ch) < 128

    def _runs(self, text: str) -> List[Tuple[bool, str]]:
        runs: List[Tuple[bool, str]] = []
        chars: List[str] = []
        kind: Optional[bool] = None
        for ch in text:
            flag = self._is_ascii(ch)
            if kind is not None and flag != kind:
                runs.append((kind, "".join(chars)))
                chars = []
            kind = flag
            chars.append(ch)
        if chars and kind is not None:
            runs.append((kind, "".join(chars)))
        return runs

    def _font(self, ascii_run: bool):
        return self.primary if ascii_run else self.fallback

    def size(self, text: str) -> Tuple[int, int]:
        width = 0
        for flag, run in self._runs(text):
            width += self._font(flag).size(run)[0]
        return width, self.height

    def get_height(self) -> int:
        return self.height

    def get_ascent(self) -> int:
        return self.ascent

    def render(self, text: str, antialias: bool, color):
        import pygame

        if not text:
            return pygame.Surface((1, 1), pygame.SRCALPHA)
        parts = []
        total = 0
        for flag, run in self._runs(text):
            font = self._font(flag)
            part = font.render(run, antialias, color)
            parts.append((part, font.get_ascent()))
            total += part.get_width()
        surf = pygame.Surface((max(1, total), max(1, self.height)),
                              pygame.SRCALPHA)
        x = 0
        for part, ascent in parts:
            surf.blit(part, (x, max(0, self.ascent - ascent)))
            x += part.get_width()
        return surf


class FontBook:
    """按字号缓存字体对象；ASCII 与中文分别用对应平台的系统字体。"""

    def __init__(self) -> None:
        self.regular_path, self.bold_path, self.cjk_path = _ui_font_paths()
        self.path = self.cjk_path or self.regular_path
        self.cjk_ok = self.cjk_path is not None
        self._cache = {}

    @staticmethod
    def _load(path: Optional[str], px: int, synthetic_bold: bool):
        import pygame

        if path:
            font = pygame.font.Font(path, px)
        else:
            font = pygame.font.SysFont(None, px)
        if synthetic_bold:
            font.set_bold(True)
        return font

    def get(self, size: float, bold: bool = False):
        """按字号取字体；设计稿里的 .5 号字在这里四舍五入成像素。"""
        px = max(6, int(size + 0.5))
        key = (px, bold)
        font = self._cache.get(key)
        if font is None:
            if bold:
                primary_path = self.bold_path or self.regular_path
                synthetic = not self.bold_path
            else:
                primary_path = self.regular_path
                synthetic = False
            primary = self._load(primary_path, px, synthetic)
            fallback_path = self.cjk_path or primary_path
            fallback_synthetic = bold
            if (bold and sys.platform == "win32" and self.bold_path
                    and self.cjk_path == self.regular_path):
                fallback_path = self.bold_path
                fallback_synthetic = False
            fallback = self._load(fallback_path, px, fallback_synthetic)
            font = _UiFont(primary, fallback)
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
        joystick_index=getattr(source, "xinput_slot", cfg.input.joystick_index),
        verbose=False)
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
# 高 DPI 绘制代理
#
# UI 代码全部按 960x660 的逻辑坐标写。Retina / 高 DPI 窗口拿到的真实绘制
# 表面是 1920x1320；如果直接把 1x 画面交给系统放大，字和线就是一块一块的。
# 这层代理只把「画到 self.screen 上」的坐标放大，命中区和布局仍保持 1x，
# 所以鼠标点击、_focus_hits 等逻辑一行都不用改。
# ---------------------------------------------------------------------------


class _ScreenProxy:
    """逻辑坐标（1x）到真实绘制表面的桥；scale 通常是 2。"""

    __slots__ = ("real", "scale")

    def __init__(self, surface, scale: float) -> None:
        self.real = surface
        self.scale = max(1.0, float(scale))

    def blit(self, source, dest, *args, **kwargs):
        s = self.scale
        if hasattr(dest, "x"):
            point = (int(dest.x * s), int(dest.y * s))
        else:
            point = (int(dest[0] * s), int(dest[1] * s))
        return self.real.blit(source, point, *args, **kwargs)

    def fill(self, color, rect=None, special_flags=0):
        if rect is not None:
            s = self.scale
            if hasattr(rect, "x"):
                rect = (int(rect.x * s), int(rect.y * s),
                        int(rect.w * s), int(rect.h * s))
            else:
                rect = tuple(int(value * s) for value in rect)
        return self.real.fill(color, rect, special_flags)

    def get_size(self):
        return (int(self.real.get_width() / self.scale),
                int(self.real.get_height() / self.scale))

    def get_width(self) -> int:
        return self.get_size()[0]

    def get_height(self) -> int:
        return self.get_size()[1]

    def get_rect(self, **kwargs):
        rect = self.real.get_rect()
        rect.width = self.get_width()
        rect.height = self.get_height()
        rect.x = 0
        rect.y = 0
        for key, value in kwargs.items():
            setattr(rect, key, value)
        return rect

    def __getattr__(self, name):
        return getattr(self.real, name)


class _DrawProxy:
    """把画在 _ScreenProxy 上的坐标/线宽放大；本地缓存表面保持原样。"""

    __slots__ = ("owner", "real")

    def __init__(self, owner, real_draw) -> None:
        self.owner = owner
        self.real = real_draw

    def _scale(self, surface) -> float:
        return surface.scale if isinstance(surface, _ScreenProxy) else 1.0

    @staticmethod
    def _surface(surface):
        return surface.real if isinstance(surface, _ScreenProxy) else surface

    @staticmethod
    def _rect(rect, s: float):
        if hasattr(rect, "x"):
            return (int(rect.x * s), int(rect.y * s),
                    int(rect.w * s), int(rect.h * s))
        return (int(rect[0] * s), int(rect[1] * s),
                int(rect[2] * s), int(rect[3] * s))

    @staticmethod
    def _pt(point, s: float):
        return (int(point[0] * s), int(point[1] * s))

    @staticmethod
    def _pts(points, s: float):
        return [(int(point[0] * s), int(point[1] * s)) for point in points]

    @staticmethod
    def _width(width, s: float) -> int:
        return 0 if not width else max(1, int(round(width * s)))

    def rect(self, surface, color, rect, width=0, border_radius=0, **kwargs):
        s = self._scale(surface)
        for key in list(kwargs):
            if (key.startswith("border_") and key.endswith("_radius")
                    and kwargs[key] not in (-1, 0)):
                kwargs[key] = int(round(kwargs[key] * s))
        return self.real.rect(
            self._surface(surface), color, self._rect(rect, s),
            width=self._width(width, s),
            border_radius=int(round(border_radius * s)) if border_radius else 0,
            **kwargs)

    def circle(self, surface, color, center, radius, width=0, **kwargs):
        s = self._scale(surface)
        return self.real.circle(
            self._surface(surface), color, self._pt(center, s),
            max(1, int(round(radius * s))), width=self._width(width, s),
            **kwargs)

    def line(self, surface, color, start_pos, end_pos, width=1):
        s = self._scale(surface)
        return self.real.line(
            self._surface(surface), color, self._pt(start_pos, s),
            self._pt(end_pos, s), self._width(width, s))

    def lines(self, surface, color, closed, points, width=1):
        s = self._scale(surface)
        return self.real.lines(
            self._surface(surface), color, closed, self._pts(points, s),
            self._width(width, s))

    def polygon(self, surface, color, points, width=0):
        s = self._scale(surface)
        return self.real.polygon(
            self._surface(surface), color, self._pts(points, s),
            self._width(width, s))


class _PygameProxy:
    """除 draw 外全部转给真实 pygame 模块。"""

    __slots__ = ("owner", "draw")

    def __init__(self, owner) -> None:
        self.owner = owner
        self.draw = _DrawProxy(owner, owner._real_pg.draw)

    def __getattr__(self, name):
        return getattr(self.owner._real_pg, name)


# ---------------------------------------------------------------------------
# 主窗口
# ---------------------------------------------------------------------------

_TOKEN = re.compile(r"[A-Za-z0-9_\-./:%+]+|\s+|.", re.S)


class TrainerApp:
    _HISTORY_ROWS = 5          # 最近的尝试一屏显示几条
    """窗口 + 状态机。事件/渲染都在主线程，识别在 Engine 的 250Hz 循环里。"""

    def __init__(self, pygame_module, config_path: Optional[str],
                 index: Optional[int], demo: bool):
        self._real_pg = pygame_module
        self.pg = _PygameProxy(self)
        self.screen = None
        self.window = None
        self._window_focused = False
        self._scale = 1.0
        self._clock = pygame_module.time.Clock()
        self._fonts = FontBook()
        # 绘制缓存：渐变卡、阴影、圆角遮罩都按尺寸/颜色缓存，60fps 下不重复生成
        self._cache: Dict[Tuple, object] = {}
        self._mouse: Tuple[int, int] = (-1, -1)

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
            if self.window is not None:
                self.window.destroy()
        except Exception:
            pass
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
            elif event.type == getattr(pg, "WINDOWCLOSE", -1):
                # 高 DPI 窗口走 SDL Window API，关闭事件不是 QUIT
                self._running = False
                if self.engine is not None:
                    self.engine.stop()
            elif event.type == pg.MOUSEMOTION:
                self._mouse = (event.pos[0], event.pos[1])
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
        elif pg.K_1 <= key <= pg.K_9 or pg.K_KP1 <= key <= pg.K_KP9:
            # 数字键（主键盘或小键盘）= 点对应卡片的专项开关
            if mode == "play" and self.engine is not None:
                base = pg.K_1 if key <= pg.K_9 else pg.K_KP1
                index = key - base
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
        real = (self.screen.real if isinstance(self.screen, _ScreenProxy)
                else self.screen)
        scale = max(1.0, real.get_width() / W)
        if abs(scale - self._scale) > 0.01:
            self._scale = scale
            self._cache.clear()
        self.screen = _ScreenProxy(real, scale)
        # 高 DPI 窗口下 pygame.mouse.get_pos() 绑定不到这个 SDL 窗口，
        # 由 _handle_events 里的 MOUSEMOTION 事件维护 self._mouse。
        if self.window is None:
            try:
                self._mouse = self.pg.mouse.get_pos()
            except Exception:
                self._mouse = (-1, -1)
        self.screen.blit(self._bg_surface(), (0, 0))
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
            if self.window is not None:
                self.window.flip()
                if not self._window_focused:
                    self.window.focus()
                    self._window_focused = True
            else:
                self.pg.display.flip()
        except Exception:
            pass

    # -- 基础绘制工具 --------------------------------------------------

    def _cached(self, key: Tuple, factory):
        """取缓存或生成后存入；同尺寸同颜色的表面只生成一次。"""
        surf = self._cache.get(key)
        if surf is None:
            surf = factory()
            self._cache[key] = surf
        return surf

    def _round_mask(self, w: int, h: int, radius: int):
        """圆角遮罩：用 BLEND_RGBA_MULT 把任意表面切成圆角（按 DPI 放大）。"""
        s = self._scale
        sw = max(1, int(round(w * s)))
        sh = max(1, int(round(h * s)))
        sr = max(0, int(round(radius * s)))
        key = ("mask", sw, sh, sr)

        def make():
            surf = self.pg.Surface((sw, sh), self.pg.SRCALPHA)
            self.pg.draw.rect(surf, (255, 255, 255, 255), surf.get_rect(),
                              border_radius=sr)
            return surf
        return self._cached(key, make)

    @staticmethod
    def _lerp_color(a, b, t: float):
        """两个 RGB 之间线性插值，t 超出 [0, 1] 时夹住。"""
        t = 0.0 if t < 0.0 else 1.0 if t > 1.0 else t
        return (int(a[0] + (b[0] - a[0]) * t + 0.5),
                int(a[1] + (b[1] - a[1]) * t + 0.5),
                int(a[2] + (b[2] - a[2]) * t + 0.5))

    def _vgrad_surface(self, w: int, h: int, top, bottom, radius: int):
        """竖直线性渐变，最后切圆角（按 DPI 放大）。"""
        s = self._scale
        sw = max(1, int(round(w * s)))
        sh = max(1, int(round(h * s)))
        key = ("vg", sw, sh, top, bottom, radius)

        def make():
            surf = self.pg.Surface((sw, sh), self.pg.SRCALPHA)
            for y in range(sh):
                color = self._lerp_color(top, bottom, y / max(1, sh - 1))
                self.pg.draw.line(surf, color, (0, y), (sw, y))
            surf.blit(self._round_mask(w, h, radius), (0, 0),
                      special_flags=self.pg.BLEND_RGBA_MULT)
            return surf
        return self._cached(key, make)

    def _hgrad_surface(self, w: int, h: int, left, right, radius: int):
        """水平线性渐变（进度条用），最后切圆角（按 DPI 放大）。"""
        s = self._scale
        sw = max(1, int(round(w * s)))
        sh = max(1, int(round(h * s)))
        key = ("hg", sw, sh, left, right, radius)

        def make():
            surf = self.pg.Surface((sw, sh), self.pg.SRCALPHA)
            for x in range(sw):
                color = self._lerp_color(left, right, x / max(1, sw - 1))
                self.pg.draw.line(surf, color, (x, 0), (x, sh))
            surf.blit(self._round_mask(w, h, radius), (0, 0),
                      special_flags=self.pg.BLEND_RGBA_MULT)
            return surf
        return self._cached(key, make)

    def _shadow_surface(self, w: int, h: int, radius: int):
        """浅色阴影：小尺寸上叠几层低 alpha 圆角矩形，再放大得到柔和边缘。"""
        s = self._scale
        sw = max(1, int(round(w * s)))
        sh = max(1, int(round(h * s)))
        sr = max(1, int(round(radius * s)))
        key = ("shadow", sw, sh, sr)

        def make():
            small_w, small_h = max(8, sw // 4), max(8, sh // 4)
            small = self.pg.Surface((small_w, small_h), self.pg.SRCALPHA)
            step = max(1, small_w // 26)
            for i in range(6):
                inset = i * step
                rect = self.pg.Rect(inset, inset,
                                    max(1, small_w - 2 * inset),
                                    max(1, small_h - 2 * inset))
                self.pg.draw.rect(small, (20, 20, 30, 7 + i * 5), rect,
                                  border_radius=max(1, sr // 4))
            return self.pg.transform.smoothscale(small, (sw, sh))
        return self._cached(key, make)

    def _card(self, rect, fill=CARD, radius: int = 14, border=LINE,
              shadow: bool = True) -> None:
        """白卡：柔和阴影 + 圆角底 + 1px 描边。"""
        if shadow:
            self.screen.blit(self._shadow_surface(rect.width, rect.height,
                                                  radius),
                             (rect.x, rect.y + 2))
        self.pg.draw.rect(self.screen, fill, rect, border_radius=radius)
        if border is not None:
            self.pg.draw.rect(self.screen, border, rect, border_radius=radius,
                              width=1)

    def _gradient_card(self, rect, top, bottom, radius: int, border) -> None:
        """竖向渐变卡片：成功 / 失败结果卡用。"""
        self.screen.blit(self._shadow_surface(rect.width, rect.height, radius),
                         (rect.x, rect.y + 2))
        surf = self._vgrad_surface(rect.width, rect.height, top, bottom, radius)
        self.screen.blit(surf, rect.topleft)
        if border is not None:
            self.pg.draw.rect(self.screen, border, rect, border_radius=radius,
                              width=1)

    def _kbd(self, x: int, y: int, label: str, active: bool = False,
             w: int = 22, h: int = 19):
        """键帽。active 时蓝底蓝边，否则浅灰底；返回整个键帽的矩形。"""
        font = self._fonts.get(10, True)
        width = max(w, font.size(label)[0] + 10)
        rect = self.pg.Rect(x, y, width, h)
        if active:
            bg, border, fg = ACCENT_SOFT, BLUE_LINE, ACCENT
        else:
            bg, border, fg = (242, 242, 245), LINE_STRONG, (72, 72, 74)
        self.pg.draw.rect(self.screen, bg, rect, border_radius=5)
        self.pg.draw.rect(self.screen, border, rect, border_radius=5, width=1)
        self.pg.draw.line(self.screen, border, (rect.x + 1, rect.bottom - 1),
                          (rect.right - 2, rect.bottom - 1), 1)
        self._text(label, rect.centerx, rect.centery - 1, 10, fg, bold=True,
                   anchor="center")
        return rect

    def _chip(self, x: int, y: int, text: str, fg, bg,
              size: float = 10.5, pad: int = 7, h: int = 18,
              bold: bool = True):
        """圆角小标签，返回矩形（方便需要时登记命中区）。"""
        font = self._fonts.get(size, bold)
        rect = self.pg.Rect(x, y, font.size(text)[0] + pad * 2, h)
        self.pg.draw.rect(self.screen, bg, rect, border_radius=8)
        self._text(text, rect.centerx, rect.centery, size, fg, bold=bold,
                   anchor="center")
        return rect

    def _icon_gamepad(self, cx: float, cy: float, size: float, color) -> None:
        """手柄线框图标：椭圆机身 + 左侧十字键 + 右侧两颗按键。"""
        r = size / 2.0
        body = self.pg.Rect(int(cx - r), int(cy - r * 0.62),
                            max(1, int(size)), max(1, int(size * 0.78)))
        self.pg.draw.rect(self.screen, color, body, width=1,
                          border_radius=max(2, int(size * 0.22)))
        arm = max(1.5, size * 0.10)
        gx = cx - r * 0.32
        self.pg.draw.line(self.screen, color, (gx - arm, cy), (gx + arm, cy), 1)
        self.pg.draw.line(self.screen, color, (gx, cy - arm), (gx, cy + arm), 1)
        dot = max(1, int(size * 0.055))
        self.pg.draw.circle(self.screen, color,
                            (int(cx + r * 0.28), int(cy - arm * 0.4)), dot)
        self.pg.draw.circle(self.screen, color,
                            (int(cx + r * 0.50), int(cy + arm * 0.6)), dot)

    def _icon_folder(self, x: float, y: float, size: float, color) -> None:
        """文件夹线框图标。"""
        s = size
        body = self.pg.Rect(int(x), int(y + s * 0.24),
                            max(1, int(s)), max(1, int(s * 0.60)))
        self.pg.draw.rect(self.screen, color, body, width=1,
                          border_radius=max(1, int(s * 0.12)))
        self.pg.draw.line(self.screen, color, (x, y + s * 0.24),
                          (x + s * 0.36, y + s * 0.24), 1)
        self.pg.draw.line(self.screen, color, (x + s * 0.36, y + s * 0.24),
                          (x + s * 0.44, y + s * 0.10), 1)
        self.pg.draw.line(self.screen, color, (x + s * 0.44, y + s * 0.10),
                          (x + s * 0.72, y + s * 0.10), 1)

    def _icon_clock(self, cx: float, cy: float, size: float, color) -> None:
        """时钟线框图标：圆 + 时针 + 分针。"""
        r = size / 2.0
        self.pg.draw.circle(self.screen, color, (int(cx), int(cy)),
                            max(2, int(round(r))), 1)
        self.pg.draw.line(self.screen, color, (cx, cy), (cx, cy - r * 0.60), 1)
        self.pg.draw.line(self.screen, color, (cx, cy),
                          (cx + r * 0.42, cy + r * 0.30), 1)

    def _icon_warning(self, cx: float, cy: float, size: float, color) -> None:
        """警告三角线框图标：三角 + 感叹号。"""
        r = size / 2.0
        points = [(cx, cy - r), (cx + r * 0.95, cy + r * 0.78),
                  (cx - r * 0.95, cy + r * 0.78)]
        self.pg.draw.polygon(self.screen, color, points,
                             max(2, int(size * 0.08)))
        self.pg.draw.line(self.screen, color, (cx, cy - r * 0.30),
                          (cx, cy + r * 0.26), max(2, int(size * 0.09)))
        self.pg.draw.circle(self.screen, color,
                            (int(cx), int(cy + r * 0.52)),
                            max(1, int(size * 0.05)))

    def _check_circle(self, cx: float, cy: float, r: float, kind: str) -> None:
        """结果圆：ok 绿色渐变对勾 / fail 橙红渐变叉 / idle 浅灰对勾。"""
        radius = max(4, int(round(r)))
        if kind == "ok":
            self.pg.draw.circle(self.screen, GREEN_DEEP, (int(cx), int(cy)),
                                radius)
            self.pg.draw.circle(self.screen, (0, 184, 70), (int(cx), int(cy)),
                                max(1, radius - 3))
            self.pg.draw.circle(self.screen, GREEN_FILL, (int(cx), int(cy)),
                                max(1, radius - 6))
            self._mark(cx - r * 0.52, cy - r * 0.54, r * 1.05, True,
                       (255, 255, 255), max(2, int(r * 0.16)))
        elif kind == "fail":
            self.pg.draw.circle(self.screen, (168, 26, 22), (int(cx), int(cy)),
                                radius)
            self.pg.draw.circle(self.screen, RED, (int(cx), int(cy)),
                                max(1, radius - 3))
            self.pg.draw.circle(self.screen, (233, 84, 32), (int(cx), int(cy)),
                                max(1, radius - 6))
            self._mark(cx - r * 0.46, cy - r * 0.46, r * 0.92, False,
                       (255, 255, 255), max(2, int(r * 0.16)))
        else:
            self.pg.draw.circle(self.screen, (242, 242, 245), (int(cx), int(cy)),
                                radius)
            self._mark(cx - r * 0.46, cy - r * 0.46, r * 0.92, True,
                       ICON_IDLE, max(2, int(r * 0.14)))

    def _text(self, text: str, x: int, y: int, size: float, color,
              bold: bool = False, anchor: str = "topleft"):
        if not text:
            return None
        s = self._scale
        font = self._fonts.get(size * s, bold)
        surf = font.render(text, True, color)
        rect = surf.get_rect(**{anchor: (x * s, y * s)})
        target = (self.screen.real if isinstance(self.screen, _ScreenProxy)
                  else self.screen)
        target.blit(surf, rect)
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

    def _fit(self, text: str, size: float, width: int,
             bold: bool = False) -> str:
        s = self._scale
        limit = width * s
        font = self._fonts.get(size * s, bold)
        if font.size(text)[0] <= limit:
            return text
        lo, hi = 0, len(text)
        while lo < hi:
            mid = (lo + hi + 1) // 2
            if font.size(text[:mid] + "…")[0] <= limit:
                lo = mid
            else:
                hi = mid - 1
        return text[:lo] + "…"

    def _wrap(self, text: str, size: float, width: int,
              bold: bool = False) -> List[str]:
        s = self._scale
        limit = width * s
        font = self._fonts.get(size * s, bold)
        lines: List[str] = []
        cur = ""
        for token in _TOKEN.findall(text):
            trial = cur + token
            if not cur or font.size(trial)[0] <= limit:
                cur = trial
            else:
                lines.append(cur.rstrip())
                cur = "" if token.isspace() else token
        if cur.strip():
            lines.append(cur.rstrip())
        return lines

    def _wrap_lines(self, text: str, size: float, width: int,
                    bold: bool = False) -> List[str]:
        """保留原文的换行再逐行折行——配置报错是多行的。"""
        out: List[str] = []
        for raw in text.splitlines() or [""]:
            out.extend(self._wrap(raw, size, width, bold) or [""])
        return out

    @staticmethod
    def _short_name(name: str) -> str:
        return name.split(" (")[0].strip()

    @staticmethod
    def _split_name(name: str) -> Tuple[str, str]:
        """把 "马赛回旋 Roulette" 拆成中文名和英文名，只用于显示。"""
        match = _SPLIT_NAME.match(name.strip())
        if match is None:
            return name.strip(), ""
        return match.group(1).strip(), match.group(2).strip()

    # -- 背景 / 顶栏底稿 ------------------------------------------------

    def _bg_surface(self):
        """窗口底色 + 两团极淡的绿 / 青晕染，只生成一次（按 DPI 放大）。"""
        s = self._scale
        bw, bh = max(1, int(W * s)), max(1, int(H * s))
        key = ("bg", bw, bh)

        def make():
            small = self.pg.Surface((120, 82), self.pg.SRCALPHA)
            for cx, cy, color, radius, peak in (
                    (104, 8, (0, 200, 83), 62, 34),
                    (14, 74, (14, 159, 212), 60, 30)):
                steps = 22
                for i in range(steps, 0, -1):
                    t = i / steps
                    alpha = int(peak * (1.0 - t))
                    if alpha <= 0:
                        continue
                    self.pg.draw.circle(small, color + (alpha,), (cx, cy),
                                        max(1, int(radius * t)))
            big = self.pg.transform.smoothscale(small, (bw, bh))
            surf = self.pg.Surface((bw, bh))
            surf.fill(BG)
            surf.blit(big, (0, 0))
            return surf
        return self._cached(key, make)

    def _hero_photo(self):
        """顶栏右侧的球场照片；文件缺失或解码失败时返回 None。"""
        key = ("hero-photo",)

        def make():
            path = _asset_path("hero_pitch.jpg")
            if path is None:
                return False
            try:
                img = self.pg.image.load(str(path))
                try:
                    img = img.convert()
                except Exception:
                    pass
                return img
            except Exception:
                return False
        return self._cached(key, make) or None

    def _header_surface(self):
        """顶栏底稿：白→浅青渐变 + 右侧球场照片（顶到最右边）+ 强调线。

        照片按高 DPI 比例绘制；左边 2%–18% 淡入，标题仍压在白色区上。
        照片缺失时退回程序化青色光带，不在顶栏留白块。
        """
        s = self._scale
        lw, lh = W - 2 * MARGIN_X, HEADER_H
        w = max(1, int(round(lw * s)))
        h = max(1, int(round(lh * s)))
        key = ("header", w, h)

        def make():
            surf = self.pg.Surface((w, h), self.pg.SRCALPHA)
            for x in range(w):
                color = self._lerp_color((255, 255, 255), (241, 250, 254),
                                         x / max(1, w - 1))
                self.pg.draw.line(surf, color, (x, 0), (x, h))

            hero_w = max(1, int(round(lw * 0.66 * s)))
            hero = self.pg.Surface((hero_w, h), self.pg.SRCALPHA)
            photo = self._hero_photo()
            if photo is not None:
                iw, ih = photo.get_size()
                scale = max(hero_w / iw, h / ih)
                sw = max(1, int(iw * scale + 0.5))
                sh = max(1, int(ih * scale + 0.5))
                scaled = self.pg.transform.smoothscale(photo, (sw, sh))
                hero.blit(scaled, (-max(0, (sw - hero_w) // 2),
                                   -max(0, (sh - h) // 2)))
            else:
                # 兜底：程序化青色渐变 + 柔和斜向光带（不画球）
                for y in range(h):
                    color = self._lerp_color((44, 181, 232), CYAN,
                                             y / max(1, h - 1))
                    self.pg.draw.line(hero, color, (0, y), (hero_w, y))
                glow = self.pg.Surface((hero_w, h), self.pg.SRCALPHA)
                for fx, peak, band_w in ((0.26, 26, 84), (0.48, 20, 120),
                                         (0.72, 24, 68)):
                    bw = max(1, int(round(band_w * s)))
                    band = self.pg.Surface((bw, h * 2), self.pg.SRCALPHA)
                    for x in range(bw):
                        center = bw / 2.0
                        t = 1.0 - abs(x - center) / max(1.0, center)
                        alpha = int(peak * max(0.0, t) ** 1.4)
                        if alpha > 0:
                            self.pg.draw.line(
                                band, (255, 255, 255, alpha),
                                (x, 0), (x, band.get_height()))
                    band = self.pg.transform.rotate(band, -22)
                    glow.blit(band,
                              (int(hero_w * fx) - band.get_width() // 2,
                               -band.get_height() // 3))
                hero.blit(glow, (0, 0))

            # 左侧柔和淡入：照片从 2% 处开始出现，18% 处完全实心
            fade = self.pg.Surface((hero_w, h), self.pg.SRCALPHA)
            for x in range(hero_w):
                t = (x / max(1, hero_w) - 0.02) / 0.18
                alpha = int(255 * (0.0 if t < 0.0 else 1.0 if t > 1.0 else t))
                self.pg.draw.line(fade, (255, 255, 255, alpha), (x, 0),
                                  (x, h))
            hero.blit(fade, (0, 0), special_flags=self.pg.BLEND_RGBA_MULT)
            surf.blit(hero, (w - hero_w, 0))

            # 先画卡片描边，底部强调线再压上去
            self.pg.draw.rect(
                surf, LINE, (0, 0, w, h),
                max(1, int(round(s))),
                border_radius=max(1, int(round(14 * s))))

            # 底部 2px（逻辑）的绿→青强调线：画在 overlay 上正常混合
            line_h = max(1, int(round(2 * s)))
            line = self.pg.Surface((w, line_h), self.pg.SRCALPHA)
            for x in range(w):
                t = x / max(1, w - 1)
                if t <= 0.24:
                    color, alpha = (0, 200, 83), int(160 * t / 0.24)
                elif t <= 0.64:
                    color = self._lerp_color((0, 200, 83), CYAN,
                                             (t - 0.24) / 0.40)
                    alpha = int(160 + (145 - 160) * (t - 0.24) / 0.40)
                else:
                    color, alpha = CYAN, int(145 * (1.0 - (t - 0.64) / 0.36))
                if alpha > 0:
                    self.pg.draw.line(line, color + (alpha,),
                                      (x, 0), (x, line_h - 1))
            surf.blit(line, (0, h - line_h))

            surf.blit(self._round_mask(lw, lh, 14), (0, 0),
                      special_flags=self.pg.BLEND_RGBA_MULT)
            return surf
        return self._cached(key, make)

    # -- 顶部 ----------------------------------------------------------

    @staticmethod
    def _stick_point(cx: float, cy: float, radius: float,
                     x: float, y: float) -> Tuple[float, float]:
        """摇杆原始坐标 -> 屏幕坐标。

        SDL 的 y 轴**向下为正**，屏幕坐标也是向下为正，所以这里直接相加。
        取负会把"上推"画成"下拉"——看起来就像手柄的上下反了。
        """
        return cx + x * radius, cy + y * radius

    def _header_pill(self, rect, title: str, sub: str, title_color) -> None:
        """顶栏右侧状态胶囊：和计时胶囊同形，避免小 chip 飘在 Hero 上。"""
        self._card(rect, CARD, 13, LINE_STRONG, True)
        self._text(title, rect.centerx, rect.y + 11, 13, title_color,
                   bold=True, anchor="midtop")
        self._text(sub, rect.centerx, rect.y + 37, 9.5, MUTED,
                   anchor="midtop")

    def _draw_header(self, now: float) -> None:
        rect = self.pg.Rect(MARGIN_X, MARGIN_Y, W - 2 * MARGIN_X, HEADER_H)
        self.screen.blit(
            self._shadow_surface(rect.width, rect.height, 14),
            (rect.x, rect.y + 2))
        self.screen.blit(self._header_surface(), rect.topleft)

        x = rect.x + 22
        self._text(APP_TITLE, x, rect.y + 14, 24, TEXT, bold=True)
        self._text("震一下 = 做对了；没震就是还没到位", x + 1, rect.y + 50,
                   12, MUTED)

        # 设备行：手柄图标 + 设备名 + · + 震动后端 chip
        icon_cy = rect.y + 78
        self._icon_gamepad(x + 9, icon_cy, 17, MUTED)
        if self.config_error is not None:
            device = "配置未加载"
            backend = ""
        elif self.engine is not None:
            device = self.device_label
            backend = self.rumble_label
        else:
            device = "未连接"
            backend = ""
        dev_x = x + 26
        # 设备名最多占白色区的 260px；再长就会压到右侧 Hero 上
        device = self._fit(device, 11.5,
                           min(260, rect.right - 150 - dev_x))
        self._text(device, dev_x, icon_cy, 11.5, MUTED, anchor="midleft")
        if backend:
            name_w = self._fonts.get(11.5).size(device)[0]
            sep_x = dev_x + name_w + 7
            self._text("·", sep_x, icon_cy, 11.5, (195, 195, 200),
                       anchor="midleft")
            self._chip(sep_x + 11, icon_cy - 9, backend, CYAN_DEEP,
                       CYAN_SOFT, size=10, h=18, bold=False)

        right = rect.right - 18
        if self.config_error is not None:
            cap = self.pg.Rect(right - 104, rect.centery - 30, 104, 60)
            self._header_pill(cap, "配置有错误", "R 重新加载", RED)
            return

        if self.engine is None:
            cap = self.pg.Rect(right - 104, rect.centery - 30, 104, 60)
            self._header_pill(cap, "未连接手柄", "等待连接", MUTED)
            return

        # 计时胶囊：白色卡片 + 轻阴影，压在青色 Hero 上
        cap = self.pg.Rect(right - 96, rect.centery - 30, 96, 60)
        self._card(cap, CARD, 13, LINE_STRONG, True)
        elapsed = max(0.0, now - self.engine.started_at) if now else 0.0
        clock = f"{int(elapsed) // 60:02d}:{int(elapsed) % 60:02d}"
        self._text(clock, cap.centerx, cap.y + 8, 22, TEXT, bold=True,
                   anchor="midtop")
        self._text("练习时长", cap.centerx, cap.y + 40, 9, MUTED,
                   anchor="midtop")

    # -- 左栏：动作熟练度 ----------------------------------------------

    def _draw_skills(self) -> None:
        assert self.engine is not None
        pg = self.pg
        panel = pg.Rect(MARGIN_X, BODY_Y, LEFT_W, GRID_H)
        self._card(panel)
        self._text("动作熟练度", panel.x + 16, panel.y + 14, 11.5, MUTED,
                   bold=True)

        skills = self.engine.skills
        focus = self.engine.focus
        focus_name = (self._split_name(self._short_name(focus.skill.name))[0]
                      if focus is not None else "")
        show_strip = 0 < len(skills) <= 9

        if not skills:
            hint = "没有启用的动作"
        elif focus is not None:
            hint = ("点开关关闭" if show_strip
                    else self._fit(f"专项：{focus_name}", 10.5, 180, True))
        else:
            hint = "开关＝专项"
        self._text(hint, panel.right - 16, panel.y + 15, 10.5,
                   ACCENT if focus is not None else FAINT,
                   bold=focus is not None and not show_strip,
                   anchor="topright")

        self._modifier_hits = []
        self._focus_hits = []
        if not skills:
            self._text("没有启用的动作，检查配置里的 enabled",
                       panel.centerx, panel.centery, 12, FAINT,
                       anchor="center")
            return

        # 模式条：把「自由练习 / 专项训练：某某」说清楚；动作太多时省略
        top = panel.y + 40
        if show_strip:
            strip = pg.Rect(panel.x + 8, panel.y + 38,
                            panel.width - 16, 26)
            if focus is not None:
                pg.draw.rect(self.screen, ACCENT_SOFT, strip,
                             border_radius=8)
                pg.draw.rect(self.screen, BLUE_LINE, strip,
                             border_radius=8, width=1)
                pg.draw.circle(self.screen, ACCENT,
                               (strip.x + 11, strip.centery), 3)
                label = f"专项训练：{focus_name}"
                self._text(self._fit(label, 10.5, strip.width - 100, True),
                           strip.x + 20, strip.centery, 10.5, ACCENT,
                           bold=True, anchor="midleft")
                self._text("其他动作已置灰", strip.right - 10, strip.centery,
                           9.5, MUTED, anchor="midright")
            else:
                pg.draw.rect(self.screen, CARD_SOFT, strip,
                             border_radius=8)
                pg.draw.rect(self.screen, LINE, strip, border_radius=8,
                             width=1)
                self._text("自由练习 · 所有动作都参与判定",
                           strip.x + 10, strip.centery, 10.5, MUTED,
                           anchor="midleft")
                self._text(f"数字键 1–{min(9, len(skills))} 也能切",
                           strip.right - 10, strip.centery, 9.5, FAINT,
                           anchor="midright")
            top = strip.bottom + 6

        n = max(1, len(skills))
        gap = 6 if n <= 8 else 4
        avail = panel.bottom - 10 - top
        row_h = int((avail - gap * (n - 1)) / n)
        # 用户往配置里加动作时行会变矮；低于 58px 走单行紧凑布局，
        # 否则 7 个以上动作会顶出面板、压到下面的卡片上。
        row_h = max(26, min(90, row_h))

        for i, active in enumerate(skills):
            rect = pg.Rect(panel.x + 8, top + i * (row_h + gap),
                           panel.width - 16, row_h)
            self._draw_skill_row(active, rect, i)

    def _focus_switch(self, rect, on: bool, dimmed: bool) -> None:
        """动作行左侧的专项开关：开=蓝，关=灰，置灰行更浅。"""
        pg = self.pg
        if on:
            track, knob = ACCENT, CARD
        elif dimmed:
            track, knob = (232, 232, 237), (250, 250, 252)
        else:
            track, knob = (219, 219, 225), CARD
        pg.draw.rect(self.screen, track, rect, border_radius=rect.height // 2)
        r = max(3, rect.height // 2 - 1)
        cx = (rect.right - rect.height // 2 if on
              else rect.x + rect.height // 2)
        pg.draw.circle(self.screen, knob, (cx, rect.centery), r)

    def _draw_skill_row(self, active, rect, index: int) -> None:
        """一个动作占一行：专项开关 / 名字 / 成功数 / 进度条 / 最近一次。"""
        pg = self.pg
        focus = self.engine.focus if self.engine is not None else None
        selected = focus is active
        dimmed = focus is not None and not selected
        hover = rect.collidepoint(self._mouse)
        compact = rect.height < 58

        # 选中行：3px 蓝色外发光 + 白卡 + 蓝色描边；其余行不参与时整行变灰
        if selected:
            pg.draw.rect(self.screen, ACCENT_SOFT, rect.inflate(6, 6),
                         border_radius=13)
        row_bg = HOVER if dimmed else (
            HOVER if hover and not selected else CARD)
        pg.draw.rect(self.screen, row_bg, rect, border_radius=10)
        if selected:
            pg.draw.rect(self.screen, BLUE_LINE, rect, border_radius=10,
                         width=1)

        switch = (pg.Rect(rect.x + 8, rect.centery - 7, 24, 14) if compact
                  else pg.Rect(rect.x + 10, rect.y + 9, 30, 16))
        self._focus_switch(switch, selected, dimmed)
        name_x = switch.right + (6 if compact else 8)

        # 顶行：中文名 + 英文名 / 成功次数 + 本组进度
        cn, en = self._split_name(self._short_name(active.skill.name))
        group = min(active.group_hits, Engine.GROUP_SIZE)
        ratio = f"{group}/{Engine.GROUP_SIZE}"
        ratio_color = (DIM_TEXT if dimmed
                       else GREEN if group > 0 else FAINT)
        name_color = DIM_TEXT if dimmed else TEXT
        soft_color = DIM_SOFT if dimmed else FAINT

        # 动作多到行高不足时只留一行：开关 + 名字 + 进度
        if compact:
            self._text(self._fit(cn, 12, rect.width - 110, bold=True),
                       name_x, rect.centery, 12, name_color, bold=True,
                       anchor="midleft")
            self._text(ratio, rect.right - 10, rect.centery, 12.5,
                       ratio_color, bold=True, anchor="midright")
            self._focus_hits.append((rect, active))
            return

        name = self._fit(cn, 13.5, rect.width - 150, bold=True)
        self._text(name, name_x, rect.y + 8, 13.5, name_color, bold=True)
        if en:
            # 中文名被截断时不再画英文名，否则会把 "…" 画到行外
            cn_w = self._fonts.get(13.5, True).size(name)[0]
            en_room = rect.width - 150 - cn_w
            if en_room >= 24:
                en = self._fit(en, 10.5, en_room)
                if en != "…":
                    self._text(en, name_x + cn_w + 5, rect.y + 11,
                               10.5, soft_color)

        ratio_w = self._fonts.get(13.5, True).size(ratio)[0]
        self._text(ratio, rect.right - 10, rect.y + 6, 13.5, ratio_color,
                   bold=True, anchor="topright")
        self._text(f"成功 {active.hits}", rect.right - 22 - ratio_w,
                   rect.y + 9, 10.5, DIM_SOFT if dimmed else MUTED,
                   anchor="topright")

        # 进度条：本组做满 10 个由引擎清零。行太矮时省略，避免压住底行文字
        if rect.height >= 62:
            bar = pg.Rect(rect.x + 10, rect.y + 30, rect.width - 20, 4)
            pg.draw.rect(self.screen, (242, 242, 245) if dimmed else LINE,
                         bar, border_radius=2)
            if group > 0:
                fill_w = max(2, int(bar.width * group / Engine.GROUP_SIZE))
                left = (214, 214, 220) if dimmed else GREEN_FILL
                right = (214, 214, 220) if dimmed else (59, 226, 124)
                self.screen.blit(
                    self._hgrad_surface(fill_w, 4, left, right, 2),
                    (bar.x, bar.y))

        # 右侧键帽：数字键（专项）+ 可点的修饰键；行高太矮时不画
        keys_w = 0
        options = tuple(active.skill.params.get("modifier_options") or ())
        if rect.height >= 60:
            key_y = rect.bottom - 27
            num_x = rect.right - 10 - 22
            self._kbd(num_x, key_y, str(index + 1), active=selected)
            keys_w = 22 + 4
            if len(options) > 1:
                widths = [max(22, self._fonts.get(10, True).size(opt)[0] + 10)
                          for opt in options]
                total = sum(widths) + 4 * (len(options) - 1)
                x = num_x - 4 - total
                for opt, width in zip(options, widths):
                    on = (not dimmed
                          and bool(active.skill.required_buttons)
                          and active.skill.required_buttons[0] == opt)
                    key_rect = self._kbd(x, key_y, opt, active=on, w=width)
                    self._modifier_hits.append((key_rect, active, opt))
                    x += width + 4
                keys_w += 4 + total

        # 底行：实时状态 > 最近一次结果 > 还没有成功记录
        text_w = rect.width - 20 - keys_w
        base_y = rect.bottom - 26
        status = active.detector.status()
        if status and status != "待机":
            self._text(self._fit(status, 10.5, text_w), rect.x + 10, base_y,
                       10.5, DIM_SOFT if dimmed else ACCENT)
        elif active.last_outcome is not None:
            last = active.last_outcome
            color = (DIM_SOFT if dimmed
                     else GREEN if last.ok else RED)
            self._mark(rect.x + 10, base_y + 1, 10, last.ok, color, 2)
            if last.ok:
                detail = f"最近 {last.elapsed_ms:.0f}ms"
            else:
                label = Detector.FAILURE_LABELS.get(last.code, last.code)
                detail = f"最近 · {label}"
            self._text(self._fit(detail, 10.5, text_w - 14), rect.x + 23,
                       base_y, 10.5, color)
        else:
            self._text("还没有成功记录", rect.x + 10, base_y, 10.5,
                       DIM_SOFT if dimmed else FAINT)

        self._focus_hits.append((rect, active))

    # -- 中央：最近一次结果 --------------------------------------------

    def _draw_result(self) -> None:
        pg = self.pg
        assert self.engine is not None
        panel = pg.Rect(RIGHT_X, BODY_Y, RIGHT_W, DETAIL_H)
        outcome = self.engine.last_outcome

        if outcome is None:
            self._card(panel)
            self._check_circle(panel.x + 48, panel.y + 44, 26, "idle")
            self._text("等待第一次尝试", panel.x + 90, panel.y + 18, 24, TEXT,
                       bold=True)
            self._chip(panel.x + 90, panel.y + 54, "等待尝试", FAINT,
                       (242, 242, 245), size=11.5)
            pg.draw.line(self.screen, LINE, (panel.x + 22, panel.y + 84),
                         (panel.right - 22, panel.y + 84), 1)
            self._text("推右摇杆做出动作；做对了会震一下。",
                       panel.x + 22, panel.y + 96, 14, TEXT_SOFT)
            self._text("失败不会震，只会在这里告诉你差在哪儿。",
                       panel.x + 22, panel.y + 150, 12.5, MUTED,
                       bold=True)
            return

        ok = outcome.ok
        if ok:
            self._gradient_card(panel, (243, 254, 248), CARD, 14, GREEN_LINE)
        else:
            self._gradient_card(panel, (255, 247, 241), CARD, 14, RED_LINE)
        self._check_circle(panel.x + 48, panel.y + 44, 26,
                           "ok" if ok else "fail")

        cn, en = self._split_name(self._short_name(outcome.skill_name))
        title_x = panel.x + 90
        # 给右侧毫秒数留 116px；长动作名截断，不能压到时间上
        title_max = panel.right - 22 - 116 - title_x
        cn = self._fit(cn, 24, max(40, title_max), bold=True)
        self._text(cn, title_x, panel.y + 18, 24, TEXT, bold=True)
        if en:
            cn_w = self._fonts.get(24, True).size(cn)[0]
            en_room = panel.right - 22 - 116 - (title_x + cn_w + 8)
            if en_room >= 24:
                en = self._fit(en, 12, en_room)
                if en != "…":
                    self._text(en, title_x + cn_w + 8, panel.y + 34,
                               12, FAINT)
        if ok:
            self._chip(title_x, panel.y + 54, "做对了", GREEN_DEEP, GREEN_SOFT,
                       size=11.5)
        else:
            self._chip(title_x, panel.y + 54, "没做对", RED, RED_SOFT,
                       size=11.5)

        # 右侧毫秒数 + 单位
        unit_x = panel.right - 22
        self._text("ms", unit_x, panel.y + 36, 11, MUTED, anchor="topright")
        unit_w = self._fonts.get(11).size("ms")[0]
        self._text(f"{outcome.elapsed_ms:.0f}", unit_x - unit_w - 3,
                   panel.y + 22, 22, TEXT, bold=True, anchor="topright")

        pg.draw.line(self.screen, LINE, (panel.x + 22, panel.y + 84),
                     (panel.right - 22, panel.y + 84), 1)

        if ok:
            body = "动作识别成功，手柄已经震动过了。"
            advice = "保持这个节奏，继续练下一个。"
            advice_color = GREEN
        else:
            body = outcome.message or Detector.FAILURE_LABELS.get(
                outcome.code, "没有做到位")
            advice = _ADVICE.get(outcome.code, "再试一次，注意动作的起手和收尾。")
            advice_color = AMBER

        y = panel.y + 96
        for line in self._wrap(body, 14, panel.width - 44)[:2]:
            self._text(line, panel.x + 22, y, 14, TEXT_SOFT)
            y += 21
        if advice:
            self._text(self._fit(advice, 12.5, panel.width - 44, bold=True),
                       panel.x + 22, panel.y + 150, 12.5, advice_color,
                       bold=True)

    # -- 中央：最近几次 -------------------------------------------------

    def _draw_history(self) -> None:
        pg = self.pg
        panel = pg.Rect(RIGHT_X, ATTEMPTS_Y, RIGHT_W, ATTEMPTS_H)
        self._card(panel)
        self._text("最近的尝试", panel.x + 16, panel.y + 12, 11.5, MUTED,
                   bold=True)
        if self.history:
            meta = f"滚轮滚动 · 保留最近 {len(self.history)}/50 条"
            self._text(meta, panel.right - 16, panel.y + 13, 10.5, FAINT,
                       anchor="topright")

        if not self.history:
            self._icon_clock(panel.centerx, panel.y + 70, 24, (194, 194, 200))
            self._text("暂无尝试记录，做对一个动作后会出现在这里。",
                       panel.centerx, panel.y + 92, 11.5, FAINT,
                       anchor="midtop")
            return

        max_off = max(0, len(self.history) - self._HISTORY_ROWS)
        self.history_scroll = max(0, min(max_off, self.history_scroll))

        # 一行一条：时间 / 对勾叉 / 动作名 / 毫秒 + 说明，成功灰、失败红
        row_h = 27
        top = panel.y + 44
        for i in range(self._HISTORY_ROWS):
            idx = self.history_scroll + i
            if idx >= len(self.history):
                break
            stamp, outcome = self.history[idx]
            y = top + i * row_h
            row = pg.Rect(panel.x + 8, y, panel.width - 22, row_h)
            if row.collidepoint(self._mouse):
                pg.draw.rect(self.screen, HOVER, row, border_radius=8)
            color = GREEN if outcome.ok else RED
            self._text(stamp, panel.x + 16, y + 8, 10.5, FAINT)
            self._mark(panel.x + 80, y + 9, 11, outcome.ok, color, 2)

            ms = f"{outcome.elapsed_ms:.0f} ms"
            if outcome.ok:
                cue = outcome.detail
                cue_color = MUTED
            else:
                cue = outcome.message or Detector.FAILURE_LABELS.get(
                    outcome.code, outcome.code)
                cue_color = RED
            cue = self._fit(cue, 10, 230) if cue else ""
            cue_w = self._fonts.get(10).size(cue)[0] if cue else 0
            ms_w = self._fonts.get(11.5, True).size(ms)[0]
            right_w = (cue_w + 9 if cue else 0) + ms_w

            # 先算右侧说明+毫秒占多宽，再把剩余宽度给动作名，长名字不会压住时间
            name_room = panel.right - 16 - right_w - 10 - (panel.x + 100)
            name = self._fit(
                self._split_name(self._short_name(outcome.skill_name))[0],
                12, max(40, name_room))
            self._text(name, panel.x + 100, y + 7, 12, TEXT)

            cue_x = panel.right - 16
            if cue:
                self._text(cue, cue_x, y + 8, 10, cue_color,
                           anchor="topright")
                cue_x -= cue_w + 9
            self._text(ms, cue_x, y + 6, 11.5, TEXT, bold=True,
                       anchor="topright")

        if len(self.history) > self._HISTORY_ROWS:
            track_x = panel.right - 7
            track_top = top
            track_h = self._HISTORY_ROWS * row_h - 4
            thumb_h = max(16, int(track_h * self._HISTORY_ROWS / len(self.history)))
            span = max(1, max_off)
            thumb_y = track_top + int((track_h - thumb_h) * self.history_scroll / span)
            pg.draw.rect(self.screen, LINE_STRONG,
                         pg.Rect(track_x, track_top, 3, track_h),
                         border_radius=2)
            pg.draw.rect(self.screen, (210, 210, 216),
                         pg.Rect(track_x, thumb_y, 3, thumb_h), border_radius=2)

    # -- 底部：摇杆可视化 + 快捷键 --------------------------------------

    def _draw_footer(self, now: float) -> None:
        pg = self.pg
        rect = pg.Rect(MARGIN_X, FOOTER_Y, W - 2 * MARGIN_X, FOOTER_H)
        self._card(rect)

        state = self.state or PadState()
        engine = self.engine
        facing = engine.facing if engine is not None else 0.0
        facing_ok = engine.facing_valid if engine is not None else False
        rs_on = state.rs_mag >= 0.02

        # 浅色摇杆图：外圈浅灰环 + 内圈准线 + 中心蓝环
        cx, cy = rect.x + 42, rect.centery
        r_out, r_in = 30, 20
        pg.draw.circle(self.screen, (250, 250, 252), (cx, cy), r_out)
        pg.draw.circle(self.screen, (217, 217, 223), (cx, cy), r_out, 1)
        pg.draw.circle(self.screen, (228, 228, 233), (cx, cy), r_in, 1)
        pg.draw.line(self.screen, (228, 228, 233),
                     (cx - r_out, cy), (cx + r_out, cy), 1)
        pg.draw.line(self.screen, (228, 228, 233),
                     (cx, cy - r_out), (cx, cy + r_out), 1)
        pg.draw.circle(self.screen, (195, 220, 247), (cx, cy), 10, 1)
        pg.draw.circle(self.screen, (129, 129, 132), (cx, cy), 4)

        def hand(angle: float, color, on: bool,
                 width: int, ball: int) -> None:
            if not on:
                return
            rad = math.radians(angle)
            # 指针伸到内圈边缘：球心 = r_in - 球半径，外缘正好贴住内圈
            tip = self._stick_point(cx, cy, r_in - ball,
                                    math.sin(rad), -math.cos(rad))
            pg.draw.line(self.screen, color, (cx, cy), tip, width)
            pg.draw.circle(self.screen, color,
                           (int(round(tip[0])), int(round(tip[1]))), ball)

        # 朝向先画（深色），右摇杆后画（蓝色压在深色上也分得清）
        hand(facing, TEXT, facing_ok, 3, 3)
        hand(state.rs_angle, ACCENT, rs_on, 2, 3)

        tx = cx + r_out + 14
        if facing_ok:
            self._text(f"球员朝向 {direction_name(facing)}", tx, rect.y + 9,
                       13, TEXT, bold=True)
        else:
            self._text("左摇杆回中", tx, rect.y + 9, 13, TEXT, bold=True)
        if rs_on:
            if facing_ok:
                rel = angle_diff(state.rs_angle, facing)
                sub = f"右摇杆 · 相对 {rel:.0f}°"
            else:
                sub = "右摇杆 · 已推（无朝向基准）"
        else:
            sub = "右摇杆 · 居中"
        self._text(sub, tx, rect.y + 31, 11, FAINT)
        if not facing_ok:
            warn = "方向类动作暂不可用"
            w = self._fonts.get(10.5, True).size(warn)[0] + 26
            box = pg.Rect(tx, rect.y + 47, w, 19)
            pg.draw.rect(self.screen, AMBER_SOFT, box, border_radius=7)
            pg.draw.circle(self.screen, ORANGE, (box.x + 9, box.centery), 2)
            self._text(warn, box.x + 17, box.centery, 10.5, AMBER, bold=True,
                       anchor="midleft")

        # 右侧一列：快捷键 / 提示行 / 配置文件路径
        right = rect.right - 18
        self._draw_hotkeys(right, rect.y + 9)
        hint = self.notice or ("开关＝专项 · 数字键也能切 · T 切修饰键 · "
                               "修饰键动作先按键再推杆")
        self._text(self._fit(hint, 10.5, 520), right, rect.y + 35, 10.5,
                   ACCENT if self.notice else FAINT, anchor="topright")
        if not self._fonts.cjk_ok:
            self._text("未找到中文字体，部分文字可能显示为方块", right,
                       rect.y + 54, 10, AMBER, anchor="topright")
        else:
            label = self._fit(f"配置文件：{self.config_path}", 10, 480)
            label_w = self._fonts.get(10).size(label)[0]
            self._icon_folder(right - label_w - 16, rect.y + 55, 12, FAINT)
            self._text(label, right, rect.y + 54, 10, FAINT,
                       anchor="topright")

    def _draw_hotkeys(self, right: int, y: int) -> None:
        """底栏快捷键：键帽 + 文字整项可点，和键盘按走同一套动作。"""
        self._hotkey_hits = []
        label_font = self._fonts.get(11.5)
        key_font = self._fonts.get(10, True)
        x = right
        for action, key, label in reversed(_HOTKEYS):
            key_w = max(22, key_font.size(key)[0] + 10)
            width = key_w + 6 + label_font.size(label)[0]
            rect = self.pg.Rect(x - width, y, width, 20)
            hover = rect.collidepoint(self._mouse)
            self._kbd(rect.x, rect.y, key, active=hover, w=key_w, h=20)
            self._text(label, rect.x + key_w + 6, rect.centery, 11.5,
                       ACCENT if hover else MUTED, anchor="midleft")
            self._hotkey_hits.append((rect, action))
            x -= width + 16

    # -- 按键校准面板 ---------------------------------------------------

    def _dialog_mask(self):
        """校准弹窗的半透明遮罩：rgba(28, 28, 32, .28)，只生成一次。"""
        s = self._scale
        bw, bh = max(1, int(W * s)), max(1, int(H * s))
        key = ("dialog-mask", bw, bh)

        def make():
            surf = self.pg.Surface((bw, bh), self.pg.SRCALPHA)
            surf.fill(DIALOG_MASK + (72,))
            return surf
        return self._cached(key, make)

    def _draw_calibration(self) -> None:
        pg = self.pg
        self.screen.blit(self._dialog_mask(), (0, 0))

        panel = pg.Rect(48, 52, W - 96, H - 104)
        self._cal_panel_rect = panel
        self._card(panel, CARD, 16, LINE_STRONG, True)

        icon = pg.Rect(panel.x + 26, panel.y + 20, 40, 40)
        pg.draw.rect(self.screen, ACCENT_SOFT, icon, border_radius=10)
        self._icon_gamepad(icon.centerx, icon.centery, 24, ACCENT)
        self._text("按键校准", icon.right + 14, icon.y + 2, 17, TEXT,
                   bold=True)
        tip = ("按下手柄上的键，就绑到高亮的那一项。绿色搓射只要对准 "
               "X（要连按的键）和 RB（要按住的键）。")
        self._text(self._fit(tip, 13, panel.width - 52),
                   panel.x + 26, panel.y + 68, 13, MUTED)
        tip2 = "LT / RT 一般由扳机轴自动识别，不用绑；如果扳机是数字键，按一下它就能绑上。"
        self._text(self._fit(tip2, 11.5, panel.width - 52),
                   panel.x + 26, panel.y + 90, 11.5, FAINT)

        col_w = (panel.width - 52 - 16) // 2
        row_h = 42
        top = panel.y + 116
        self._cal_hits = []
        index = 0
        for col, names in enumerate(_CAL_COLUMNS):
            for row, name in enumerate(names):
                box = pg.Rect(panel.x + 26 + col * (col_w + 16),
                              top + row * row_h, col_w, 36)
                selected = (index == self._cal_sel)
                if selected:
                    pg.draw.rect(self.screen, ACCENT_SOFT, box,
                                 border_radius=8)
                    pg.draw.rect(self.screen, ACCENT, box,
                                 border_radius=8, width=1)
                else:
                    pg.draw.rect(self.screen, CARD, box, border_radius=8)
                    pg.draw.rect(self.screen, LINE, box,
                                 border_radius=8, width=1)
                self._text(name, box.x + 12, box.centery, 14, TEXT,
                           bold=selected, anchor="midleft")
                value = self._cal_map.get(name)
                label = "未绑定" if value is None else f"#{value}"
                self._text(label, box.right - 12, box.centery, 13,
                           FAINT if value is None else ACCENT,
                           bold=value is not None, anchor="midright")
                if selected:
                    label_w = self._fonts.get(13, value is not None).size(label)[0]
                    self._text("按手柄键…", box.right - 28 - label_w,
                               box.centery, 11, AMBER, anchor="midright")
                self._cal_hits.append((box, index))
                index += 1

        raw = ",".join(str(i) for i in sorted(self._cal_prev_raw)) or "无"
        y = panel.bottom - 142
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
                   panel.x + 26, panel.bottom - 58, 10, MUTED)

    def _draw_cal_buttons(self, panel, y: int) -> int:
        """校准面板底部的保存/清除/关闭按钮。返回最左边的 x。"""
        pg = self.pg
        self._cal_btn_hits = []
        font = self._fonts.get(12.5, True)
        specs = (("save", "S 保存", True),
                 ("clear", "Del 清除", False),
                 ("close", "Esc 关闭", False))
        x = panel.right - 26
        for action, text, primary in reversed(specs):
            width = font.size(text)[0] + 24
            rect = pg.Rect(x - width, y, width, 32)
            hover = rect.collidepoint(self._mouse)
            if primary:
                bg = (0, 102, 204) if hover else ACCENT
                border, fg = bg, CARD
            else:
                bg = HOVER if hover else CARD
                border = LINE_STRONG
                fg = TEXT
            pg.draw.rect(self.screen, bg, rect, border_radius=8)
            pg.draw.rect(self.screen, border, rect, border_radius=8, width=1)
            self._text(text, rect.centerx, rect.centery, 12.5, fg,
                       anchor="center")
            self._cal_btn_hits.append((rect, action))
            x -= width + 8
        return x

    # -- 无手柄 / 连接中 / 配置错误 -------------------------------------

    def _keycap_row(self, cx: int, y: int, items) -> None:
        """一排纯视觉键帽 + 文字（不登记命中区），整体水平居中。"""
        label_font = self._fonts.get(11.5)
        key_font = self._fonts.get(10, True)
        parts = []
        for key, label in items:
            key_w = max(22, key_font.size(key)[0] + 10)
            parts.append((key_w, label_font.size(label)[0], key, label))
        total = sum(kw + 6 + lw for kw, lw, _, _ in parts) \
            + 18 * (len(parts) - 1)
        x = cx - total // 2
        for key_w, label_w, key, label in parts:
            self._kbd(x, y, key, w=key_w, h=20)
            self._text(label, x + key_w + 6, y + 10, 11.5, MUTED,
                       anchor="midleft")
            x += key_w + 6 + label_w + 18

    def _draw_opening(self) -> None:
        panel = self.pg.Rect(MARGIN_X, BODY_Y, W - 2 * MARGIN_X, FULL_H)
        self._card(panel)
        box = self.pg.Rect(panel.centerx - 28, panel.centery - 96, 56, 56)
        self.pg.draw.rect(self.screen, ACCENT_SOFT, box, border_radius=14)
        self._icon_gamepad(box.centerx, box.centery, 30, ACCENT)
        self._text("正在连接手柄…", panel.centerx, panel.centery - 22, 22,
                   TEXT, bold=True, anchor="midtop")
        self._text("首次连接会花 0.25 秒校准扳机静止值", panel.centerx,
                   panel.centery + 14, 12.5, MUTED, anchor="midtop")

    def _draw_no_device(self) -> None:
        pg = self.pg
        panel = pg.Rect(MARGIN_X, BODY_Y, W - 2 * MARGIN_X, FULL_H)
        self._card(panel)

        # 右侧淡色手柄水印：大卡片下半部不空，也不抢正文
        self._icon_gamepad(panel.right - 150, panel.y + 360, 150,
                           (231, 239, 249))

        icon = pg.Rect(panel.x + 48, panel.y + 56, 52, 52)
        pg.draw.rect(self.screen, ACCENT_SOFT, icon, border_radius=12)
        self._icon_gamepad(icon.centerx, icon.centery, 28, ACCENT)
        self._text("未检测到手柄", icon.right + 16, icon.y + 10, 22, TEXT,
                   bold=True)

        y = panel.y + 140
        message = self.error or "请确认手柄已连接并开机。"
        for line in self._wrap_lines(message, 14, panel.width - 210)[:4]:
            self._text(line, panel.x + 48, y, 14, MUTED)
            y += 22

        y = max(y + 28, panel.y + 230)
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
            pg.draw.circle(self.screen, (170, 170, 176),
                           (panel.x + 52, y + 8), 2)
            self._text(tip, panel.x + 64, y, 13, FAINT)
            y += 24

        self._text("插上手柄后会自动重试，也可以按 R 立即重试。",
                   panel.centerx, panel.bottom - 84, 12.5, ACCENT,
                   anchor="midtop")
        self._keycap_row(panel.centerx, panel.bottom - 52,
                         (("R", "重试"), ("C", "配置文件夹"), ("Esc", "退出")))

    def _draw_config_error(self) -> None:
        pg = self.pg
        panel = pg.Rect(MARGIN_X, BODY_Y, W - 2 * MARGIN_X, FULL_H)
        self._card(panel)

        # 右侧淡色警告水印：短报错时卡片下半部不空
        self._icon_warning(panel.right - 140, panel.y + 340, 150,
                           (252, 235, 236))

        icon = pg.Rect(panel.x + 52, panel.y + 52, 52, 52)
        pg.draw.rect(self.screen, RED_SOFT, icon, border_radius=12)
        self._icon_warning(icon.centerx, icon.centery, 28, RED)
        self._text("配置文件有错误", icon.right + 16, icon.y + 10, 22, RED,
                   bold=True)

        lines = self._wrap_lines(self.config_error or "", 13.5,
                                 panel.width - 140)[:10]
        box_h = max(76, 20 + 22 * len(lines))
        box = pg.Rect(panel.x + 52, panel.y + 128, panel.width - 104,
                      min(box_h, panel.height - 270))
        pg.draw.rect(self.screen, CARD_SOFT, box, border_radius=10)
        pg.draw.rect(self.screen, LINE, box, border_radius=10, width=1)
        y = box.y + 12
        for line in lines:
            self._text(line, box.x + 18, y, 13.5, TEXT)
            y += 22

        tip_y = box.bottom + 18
        self._text("常见原因：少了逗号或引号、括号没闭合、动作参数超出范围。",
                   panel.x + 52, tip_y, 11.5, FAINT)
        self._text(self._fit(f"配置文件：{self.config_path}", 10,
                             panel.width - 104),
                   panel.x + 52, tip_y + 24, 10, FAINT)

        self._text("改好保存后按 R 重新加载。", panel.centerx,
                   panel.bottom - 84, 12.5, ACCENT, anchor="midtop")
        self._keycap_row(panel.centerx, panel.bottom - 52,
                         (("R", "重新加载"), ("C", "配置文件夹"),
                          ("Esc", "退出")))


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

    # Retina / 高 DPI：用 SDL Window 拿到真实的 2x 绘制面。直接 set_mode
    # 只有 960x660 像素，系统放大后文字和线条会有明显锯齿。
    window = None
    try:
        from pygame._sdl2 import video
        window = video.Window(APP_TITLE, size=(W, H),
                              position=video.WINDOWPOS_CENTERED,
                              allow_high_dpi=True)
        window.focus()
        screen = window.get_surface()
    except Exception:
        window = None
        try:
            screen = pygame.display.set_mode(
                (W, H), pygame.SCALED | pygame.RESIZABLE)
        except pygame.error:
            screen = pygame.display.set_mode((W, H))

    app = TrainerApp(pygame, config_path, index, demo)
    app.window = window
    app.screen = screen
    try:
        return app.run()
    finally:
        app._shutdown()
