"""手柄状态读取。

设计要点（针对"不确定手柄处于 XInput / DInput / 蓝牙哪种模式"）：

1. 读取本身用 `pygame.joystick.Joystick`——它拿到的是最原始的轴/键索引，
   速度快，而且实测 `Joystick.rumble()` 在飞智八爪鱼 4 上是可用的
   （`pygame._sdl2.controller.Controller.rumble()` 在同一个设备上返回 False）。

2. 索引到语义的映射（哪个轴是右摇杆、哪个键是 L1）**不写死**，而是优先向
   SDL 的 GameController 映射表查询（`Controller.get_mapping()`）。SDL 内部维护了
   一份庞大的设备数据库，XInput / DInput / 蓝牙设备都能正确解析，
   所以同一份代码不需要为协议改任何东西。

3. 万一 SDL 不认识这个设备，退化为"静止值分类法"：启动时静采 250ms，
   静止在中位附近的轴是摇杆，静止在极值的是扳机，再按标准顺序配对。
   实测你这台设备静止值是 [0, 0, 0, 0, -1, -1]，正好能被正确分类。

4. 再不行还有 `skills_config.json` 里的 `input.axis_layout` 手动覆盖。
"""

from __future__ import annotations

import math
import time
from dataclasses import dataclass, field
from typing import Any, Dict, FrozenSet, List, Optional, Sequence, Tuple

from .geometry import angle_of, magnitude

__all__ = [
    "PadState", "AxisLayout", "GamepadSource", "PygameJoystickSource",
    "canonical_button", "list_devices", "CANONICAL_BUTTONS", "open_source",
]

CANONICAL_BUTTONS: Tuple[str, ...] = (
    "A", "B", "X", "Y",
    "LB", "RB", "LT", "RT",
    "LS", "RS", "BACK", "START", "GUIDE",
    "DPAD_UP", "DPAD_DOWN", "DPAD_LEFT", "DPAD_RIGHT",
)

BUTTON_ALIASES: Dict[str, str] = {
    # PlayStation 叫法
    "L1": "LB", "L2": "LT", "L3": "LS",
    "R1": "RB", "R2": "RT", "R3": "RS",
    "CROSS": "A", "CIRCLE": "B", "SQUARE": "X", "TRIANGLE": "Y",
    "SHARE": "BACK", "OPTIONS": "START", "TOUCHPAD": "BACK",
    "LSTICK": "LS", "RSTICK": "RS", "LTHUMB": "LS", "RTHUMB": "RS",
    # Xbox / 通用叫法
    "VIEW": "BACK", "SELECT": "BACK", "CREATE": "BACK",
    "MENU": "START", "PAUSE": "START",
    "HOME": "GUIDE", "PS": "GUIDE", "XBOX": "GUIDE",
    "DUP": "DPAD_UP", "DDOWN": "DPAD_DOWN", "DLEFT": "DPAD_LEFT", "DRIGHT": "DPAD_RIGHT",
    # 去掉下划线/横线之后的形态
    "DPADUP": "DPAD_UP", "DPADDOWN": "DPAD_DOWN",
    "DPADLEFT": "DPAD_LEFT", "DPADRIGHT": "DPAD_RIGHT",
    "LEFTSHOULDER": "LB", "RIGHTSHOULDER": "RB",
    "LEFTTRIGGER": "LT", "RIGHTTRIGGER": "RT",
    "LEFTSHOULDERBUTTON": "LB", "RIGHTSHOULDERBUTTON": "RB",
}


def canonical_button(value: Any) -> str:
    """把各种叫法统一成规范名（L1 -> LB，三角 -> Y ...）。"""
    key = str(value).strip().upper()
    for ch in (" ", "-", "_"):
        key = key.replace(ch, "")
    key = BUTTON_ALIASES.get(key, key)
    if key not in CANONICAL_BUTTONS:
        raise ValueError(
            f"无法识别的按键名 {value!r}。可用规范名: {', '.join(CANONICAL_BUTTONS)}；"
            f"也接受别名如 L1/R1/L2/R2/L3/R3、SHARE/OPTIONS。"
        )
    return key


# ---------------------------------------------------------------------------
# 状态快照
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class PadState:
    """某一时刻的手柄状态快照（角度遵循 geometry.py 的约定）。"""

    ls_x: float = 0.0
    ls_y: float = 0.0
    rs_x: float = 0.0
    rs_y: float = 0.0
    lt: float = 0.0
    rt: float = 0.0
    buttons: FrozenSet[str] = frozenset()
    raw_axes: Tuple[float, ...] = ()
    raw_buttons: Tuple[int, ...] = ()

    @property
    def ls_mag(self) -> float:
        return magnitude(self.ls_x, self.ls_y)

    @property
    def rs_mag(self) -> float:
        return magnitude(self.rs_x, self.rs_y)

    @property
    def ls_angle(self) -> float:
        return angle_of(self.ls_x, self.ls_y)

    @property
    def rs_angle(self) -> float:
        return angle_of(self.rs_x, self.rs_y)


# ---------------------------------------------------------------------------
# 轴布局
# ---------------------------------------------------------------------------

@dataclass
class AxisLayout:
    ls_x: int = 0
    ls_y: int = 1
    rs_x: Optional[int] = 2
    rs_y: Optional[int] = 3
    lt_axis: Optional[int] = 4
    rt_axis: Optional[int] = 5
    lt_button: Optional[int] = None
    rt_button: Optional[int] = None
    invert_ls_y: bool = False
    invert_rs_y: bool = False
    invert_ls_x: bool = False
    invert_rs_x: bool = False
    buttons: Dict[str, int] = field(default_factory=dict)   # 规范名 -> 按键索引
    dpad: Dict[str, Tuple[int, int]] = field(default_factory=dict)  # 名 -> (hat索引, 掩码)
    trigger_rest: float = -1.0    # 扳机轴的静止值：-1.0 表示 -1~1 双极，0.0 表示 0~1 单极

    def to_dict(self) -> Dict[str, Any]:
        """导出成可以直接粘进 skills_config.json 的 input.axis_layout。"""
        return {
            "ls_x": self.ls_x, "ls_y": self.ls_y,
            "rs_x": self.rs_x, "rs_y": self.rs_y,
            "lt_axis": self.lt_axis, "rt_axis": self.rt_axis,
            "lt_button": self.lt_button, "rt_button": self.rt_button,
            "invert_ls_x": self.invert_ls_x, "invert_ls_y": self.invert_ls_y,
            "invert_rs_x": self.invert_rs_x, "invert_rs_y": self.invert_rs_y,
            "trigger_rest": self.trigger_rest,
            "buttons": dict(self.buttons),
        }

    @classmethod
    def from_dict(cls, raw: Dict[str, Any]) -> "AxisLayout":
        lay = cls()
        for key in ("ls_x", "ls_y", "rs_x", "rs_y", "lt_axis", "rt_axis",
                    "lt_button", "rt_button"):
            if key in raw:
                value = raw[key]
                setattr(lay, key, None if value is None else int(value))
        for key in ("invert_ls_x", "invert_ls_y", "invert_rs_x", "invert_rs_y"):
            if key in raw:
                setattr(lay, key, bool(raw[key]))
        if raw.get("trigger_rest") is not None:
            lay.trigger_rest = float(raw["trigger_rest"])
        if isinstance(raw.get("buttons"), dict):
            lay.buttons = {canonical_button(k): int(v) for k, v in raw["buttons"].items()}
        return lay


# 注意：pygame-ce 2.5.8 并没有把 SDL 的 CONTROLLER_AXIS_* / CONTROLLER_BUTTON_*
# 常量暴露到 `pygame._sdl2.controller` 模块上（实测 dir() 里一个都没有）。
# 好在 `Controller.get_mapping()` 返回的映射表用的是 'a2' / 'b4' / 'h0.1' 这种
# 自描述的字符串，里面已经带了轴号/键号，所以下面全部从映射表推导，不需要那些常量。
_SDL_BUTTON_CANON = {
    "a": "A", "b": "B", "x": "X", "y": "Y",
    "back": "BACK", "start": "START", "guide": "GUIDE",
    "leftstick": "LS", "rightstick": "RS",
    "leftshoulder": "LB", "rightshoulder": "RB",
}
_SDL_DPAD_CANON = {
    "dpup": "DPAD_UP", "dpdown": "DPAD_DOWN",
    "dpleft": "DPAD_LEFT", "dpright": "DPAD_RIGHT",
}


@dataclass(frozen=True)
class _Binding:
    kind: str        # "axis" | "button" | "hat"
    index: int
    invert: bool = False
    mask: int = 0


def _parse_binding(value: Any) -> Optional[_Binding]:
    """解析 SDL 映射表里的一个绑定串，例如 'b4' / '-a1' / 'h0.1'。"""
    if not value:
        return None
    text = str(value).strip()
    invert = False
    if text[:1] in ("+", "-"):
        invert = text[0] == "-"
        text = text[1:]
    if not text:
        return None
    kind_char, rest = text[0], text[1:]
    try:
        if kind_char == "a":
            return _Binding("axis", int(rest), invert)
        if kind_char == "b":
            return _Binding("button", int(rest), invert)
        if kind_char == "h":
            hat, _, mask = rest.partition(".")
            return _Binding("hat", int(hat), invert, int(mask or 0))
    except ValueError:
        return None
    return None       # 'f044' 之类我们不需要的绑定


def _layout_from_mapping(mapping: Dict[str, Any]) -> AxisLayout:
    """由 SDL GameController 映射表推导出轴/键索引。"""
    lay = AxisLayout()
    lay.buttons = {}
    lay.dpad = {}

    # 摇杆轴：索引 + 符号（SDL 映射串里的 + / -）
    for sdl_key, attr, inv_attr in (
        ("leftx", "ls_x", "invert_ls_x"), ("lefty", "ls_y", "invert_ls_y"),
        ("rightx", "rs_x", "invert_rs_x"), ("righty", "rs_y", "invert_rs_y"),
    ):
        binding = _parse_binding(mapping.get(sdl_key))
        if binding is not None and binding.kind == "axis":
            setattr(lay, attr, binding.index)
            setattr(lay, inv_attr, binding.invert)

    # 扳机：可能是轴，也可能是按键
    for sdl_key, axis_attr, btn_attr in (
        ("lefttrigger", "lt_axis", "lt_button"),
        ("righttrigger", "rt_axis", "rt_button"),
    ):
        binding = _parse_binding(mapping.get(sdl_key))
        if binding is None:
            continue
        if binding.kind == "axis":
            setattr(lay, axis_attr, binding.index)
            setattr(lay, btn_attr, None)
        elif binding.kind == "button":
            setattr(lay, axis_attr, None)
            setattr(lay, btn_attr, binding.index)

    for sdl_key, canon in _SDL_BUTTON_CANON.items():
        binding = _parse_binding(mapping.get(sdl_key))
        if binding is not None and binding.kind == "button":
            lay.buttons[canon] = binding.index

    for sdl_key, canon in _SDL_DPAD_CANON.items():
        binding = _parse_binding(mapping.get(sdl_key))
        if binding is not None and binding.kind == "hat":
            lay.dpad[canon] = (binding.index, binding.mask)

    return lay


def _layout_from_rest(joy: Any, rest: Sequence[Dict[str, float]]) -> AxisLayout:
    """静止值分类法：中位附近的轴是摇杆，停在极值的是扳机。"""
    lay = AxisLayout()
    lay.buttons = dict(_DEFAULT_XINPUT_BUTTONS)
    lay.dpad = dict(_DEFAULT_DPAD)

    centered: List[int] = []
    extreme: List[int] = []
    for i, stat in enumerate(rest):
        if abs(stat["mean"]) <= 0.25 and (stat["max"] - stat["min"]) < 0.4:
            centered.append(i)
        else:
            extreme.append(i)

    if len(centered) >= 4:
        lay.ls_x, lay.ls_y = centered[0], centered[1]
        lay.rs_x, lay.rs_y = centered[2], centered[3]
    elif len(centered) == 2:
        lay.ls_x, lay.ls_y = centered[0], centered[1]
        lay.rs_x = lay.rs_y = None
    else:
        lay.ls_x, lay.ls_y, lay.rs_x, lay.rs_y = 0, 1, 2, 3

    if len(extreme) >= 2:
        lay.lt_axis, lay.rt_axis = extreme[0], extreme[1]
    elif len(extreme) == 1:
        lay.lt_axis, lay.rt_axis = extreme[0], None
    else:
        lay.lt_axis = lay.rt_axis = None

    if lay.lt_axis is not None and rest[lay.lt_axis]["mean"] < -0.4:
        lay.trigger_rest = -1.0
    else:
        lay.trigger_rest = 0.0
    return lay


# 没有映射表可查时的兜底键位（XInput / HID 手柄的通用顺序）
_DEFAULT_XINPUT_BUTTONS: Dict[str, int] = {
    "A": 0, "B": 1, "X": 2, "Y": 3,
    "LB": 4, "RB": 5, "BACK": 6, "START": 7,
    "LS": 8, "RS": 9, "GUIDE": 10,
}
_DEFAULT_DPAD: Dict[str, Tuple[int, int]] = {
    "DPAD_UP": (0, 1), "DPAD_RIGHT": (0, 2),
    "DPAD_DOWN": (0, 4), "DPAD_LEFT": (0, 8),
}


_INVERT_KEYS = {
    "ls_x": "invert_ls_x", "ls_y": "invert_ls_y",
    "rs_x": "invert_rs_x", "rs_y": "invert_rs_y",
}


def apply_axis_inverts(layout: AxisLayout,
                       invert: Optional[Dict[str, Any]]) -> AxisLayout:
    """把配置里的 {"rs_y": true} 应用到自动推断出的布局上。

    只翻转方向、不动轴索引，所以用户不需要知道轴号就能纠正
    "右摇杆上下反了"这种情况。值写成 false 表示强制不反转，
    可以覆盖 SDL 映射表里的 `~` 号。
    """
    for key, value in (invert or {}).items():
        attr = _INVERT_KEYS.get(str(key).strip().lower())
        if attr is not None:
            setattr(layout, attr, bool(value))
    return layout


def _deadzone(x: float, y: float, dz: float) -> Tuple[float, float]:
    """带重新缩放的死区处理：角度不变，可用行程被拉满。"""
    m = math.hypot(x, y)
    if m <= dz or m == 0.0:
        return 0.0, 0.0
    scaled = min(1.0, (m - dz) / (1.0 - dz))
    return x / m * scaled, y / m * scaled


# ---------------------------------------------------------------------------
# 读取源
# ---------------------------------------------------------------------------

class GamepadSource:
    """手柄读取源的公共接口。"""

    name: str = "未知设备"
    layout_source: str = "未知"

    def poll(self) -> PadState:
        raise NotImplementedError

    def close(self) -> None:
        pass

    def describe(self) -> str:
        return f"{self.name}（布局来源：{self.layout_source}）"


class PygameJoystickSource(GamepadSource):
    """基于 pygame.joystick 的读取源。"""

    def __init__(self, index: int = 0, layout: Optional[Dict[str, Any]] = None,
                 deadzone: float = 0.08, trigger_threshold: float = 0.35,
                 calibration_ms: int = 250, verbose: bool = True,
                 invert: Optional[Dict[str, Any]] = None):
        import pygame

        self._pygame = pygame
        count = pygame.joystick.get_count()
        if count == 0:
            raise RuntimeError(
                "没有检测到任何手柄。请确认手柄已连接、已开机，"
                "并且 FIFA 能识别到它。可以用 --list 查看设备列表。"
            )
        if index >= count:
            raise RuntimeError(
                f"joystick_index={index} 超出范围，当前只检测到 {count} 个设备。"
            )

        self._joy = pygame.joystick.Joystick(index)
        self.index = index
        self.name = self._joy.get_name() or f"手柄 #{index}"
        self.guid = self._joy.get_guid()
        self.num_axes = self._joy.get_numaxes()
        self.num_buttons = self._joy.get_numbuttons()
        self.num_hats = self._joy.get_numhats()
        self._deadzone = deadzone
        self._trigger_threshold = trigger_threshold

        # 静采：既用来标定扳机静止值，也是布局自动推断的兜底依据
        self._rest = self._sample_rest(calibration_ms)

        if layout is not None:
            self.layout = AxisLayout.from_dict(layout)
            self.layout_source = "skills_config.json 手动指定"
        else:
            self.layout, self.layout_source = self._auto_layout()

        # 配置里的手动反转最后应用：优先级最高，能盖过映射表
        self.axis_invert = {str(k).strip().lower(): bool(v)
                            for k, v in (invert or {}).items()}
        if self.axis_invert:
            apply_axis_inverts(self.layout, self.axis_invert)

        if verbose:
            self._print_layout_report()

    # -- 初始化辅助 --------------------------------------------------------

    def _sample_rest(self, ms: int) -> List[Dict[str, float]]:
        n = max(1, self.num_axes)
        stats = [{"min": 1e9, "max": -1e9, "mean": 0.0} for _ in range(n)]
        if ms <= 0:
            for s in stats:
                s.update(min=0.0, max=0.0, mean=0.0)
            return stats

        total = 0
        deadline = time.perf_counter() + ms / 1000.0
        while time.perf_counter() < deadline:
            self._pygame.event.pump()
            for i in range(n):
                v = self._joy.get_axis(i)
                if v < stats[i]["min"]:
                    stats[i]["min"] = v
                if v > stats[i]["max"]:
                    stats[i]["max"] = v
                stats[i]["mean"] += v
            total += 1
            time.sleep(0.004)
        for s in stats:
            s["mean"] = s["mean"] / max(1, total)
            if s["min"] > s["max"]:
                s["min"] = s["max"] = 0.0
        return stats

    def _auto_layout(self) -> Tuple[AxisLayout, str]:
        """优先用 SDL 映射表；查不到再按静止值分类。"""
        mapping = _query_sdl_mapping(self._joy)
        if mapping:
            lay = _layout_from_mapping(mapping)
            if lay.rs_x is not None and lay.buttons:
                lay.trigger_rest = self._detect_trigger_rest(lay)
                return lay, "SDL GameController 映射表（协议无关）"
        lay = _layout_from_rest(self._joy, self._rest)
        return lay, "静止值自动分类（SDL 无此设备映射表）"

    def _detect_trigger_rest(self, lay: AxisLayout) -> float:
        for axis in (lay.lt_axis, lay.rt_axis):
            if axis is not None and 0 <= axis < len(self._rest):
                if self._rest[axis]["mean"] < -0.4:
                    return -1.0
        return 0.0

    def _print_layout_report(self) -> None:
        lay = self.layout
        print(f"  设备名称   : {self.name}")
        print(f"  设备 GUID  : {self.guid}")
        print(f"  轴/键/帽   : {self.num_axes} 轴 / {self.num_buttons} 键 / {self.num_hats} 方向帽")
        print(f"  布局来源   : {self.layout_source}")
        print(f"  左摇杆     : 轴 {lay.ls_x}, {lay.ls_y}"
              f"    右摇杆: 轴 {lay.rs_x}, {lay.rs_y}")
        trig = []
        if lay.lt_axis is not None:
            trig.append(f"LT=轴{lay.lt_axis}")
        elif lay.lt_button is not None:
            trig.append(f"LT=键{lay.lt_button}")
        if lay.rt_axis is not None:
            trig.append(f"RT=轴{lay.rt_axis}")
        elif lay.rt_button is not None:
            trig.append(f"RT=键{lay.rt_button}")
        print(f"  扳机       : {', '.join(trig) if trig else '未识别'}"
              f"（静止值 {lay.trigger_rest:+.0f}）")
        named = ", ".join(f"{k}=键{v}" for k, v in sorted(lay.buttons.items(), key=lambda kv: kv[1]))
        print(f"  按键映射   : {named or '未识别'}")
        flipped = [k for k, v in (
            ("ls_x", lay.invert_ls_x), ("ls_y", lay.invert_ls_y),
            ("rs_x", lay.invert_rs_x), ("rs_y", lay.invert_rs_y)) if v]
        if flipped:
            print(f"  轴方向反转 : {', '.join(flipped)}")
        if lay.rs_x is None:
            print("  [警告] 没有识别到右摇杆，花式动作将无法触发。请用 --debug 核对。")

    # -- 轮询 --------------------------------------------------------------

    def poll(self) -> PadState:
        pg = self._pygame
        pg.event.pump()          # pygame 靠事件泵刷新手柄状态，必须每轮调用

        joy = self._joy
        lay = self.layout
        raw = [joy.get_axis(i) for i in range(self.num_axes)]

        def axis(idx: Optional[int]) -> float:
            if idx is None or idx < 0 or idx >= len(raw):
                return 0.0
            return raw[idx]

        ls_x = -axis(lay.ls_x) if lay.invert_ls_x else axis(lay.ls_x)
        ls_y = -axis(lay.ls_y) if lay.invert_ls_y else axis(lay.ls_y)
        rs_x = -axis(lay.rs_x) if lay.invert_rs_x else axis(lay.rs_x)
        rs_y = -axis(lay.rs_y) if lay.invert_rs_y else axis(lay.rs_y)

        ls_x, ls_y = _deadzone(ls_x, ls_y, self._deadzone)
        rs_x, rs_y = _deadzone(rs_x, rs_y, self._deadzone)

        lt = self._trigger_value(axis(lay.lt_axis), lay.lt_button, joy)
        rt = self._trigger_value(axis(lay.rt_axis), lay.rt_button, joy)

        pressed: set = set()
        raw_buttons: List[int] = []
        for i in range(self.num_buttons):
            if joy.get_button(i):
                raw_buttons.append(i)
        reverse = {v: k for k, v in lay.buttons.items()}
        for idx in raw_buttons:
            name = reverse.get(idx)
            if name:
                pressed.add(name)

        for name, (hat_index, mask) in lay.dpad.items():
            if hat_index >= self.num_hats:
                continue
            hx, hy = joy.get_hat(hat_index)
            if _hat_matches(hx, hy, mask):
                pressed.add(name)

        if lt >= self._trigger_threshold:
            pressed.add("LT")
        if rt >= self._trigger_threshold:
            pressed.add("RT")

        return PadState(
            ls_x=ls_x, ls_y=ls_y, rs_x=rs_x, rs_y=rs_y,
            lt=lt, rt=rt,
            buttons=frozenset(pressed),
            raw_axes=tuple(raw),
            raw_buttons=tuple(raw_buttons),
        )

    def _trigger_value(self, value: float, button_index: Optional[int], joy: Any) -> float:
        if button_index is not None:
            if 0 <= button_index < self.num_buttons:
                return 1.0 if joy.get_button(button_index) else 0.0
            return 0.0
        rest = self.layout.trigger_rest
        if rest < -0.05:
            return min(1.0, max(0.0, (value - rest) / (1.0 - rest)))
        return min(1.0, max(0.0, value))

    def close(self) -> None:
        try:
            self._joy.stop_rumble()
        except Exception:
            pass


def _hat_matches(hx: int, hy: int, mask: int) -> bool:
    """SDL 方向帽掩码：1=上 2=右 4=下 8=左。"""
    if mask == 1:
        return hy > 0
    if mask == 2:
        return hx > 0
    if mask == 4:
        return hy < 0
    if mask == 8:
        return hx < 0
    return False


def _query_sdl_mapping(joy: Any) -> Optional[Dict[str, Any]]:
    """向 SDL 的 GameController 数据库查询这台设备的映射表。"""
    try:
        from pygame._sdl2 import controller as sdl2c
        if not sdl2c.get_init():
            sdl2c.init()
        if sdl2c.get_count() == 0:
            return None
        try:
            instance_id = joy.get_instance_id()
        except Exception:
            instance_id = None
        for i in range(sdl2c.get_count()):
            try:
                dev = sdl2c.Controller(i)
            except Exception:
                continue
            matched = False
            if instance_id is not None:
                try:
                    matched = dev.id == instance_id
                except Exception:
                    matched = False
            if not matched:
                try:
                    matched = dev.name == joy.get_name()
                except Exception:
                    matched = False
            if matched:
                mapping = dev.get_mapping()
                return mapping if isinstance(mapping, dict) and mapping else None
    except Exception:
        return None
    return None


# ---------------------------------------------------------------------------
# 设备枚举
# ---------------------------------------------------------------------------

def list_devices() -> List[Dict[str, Any]]:
    """列出所有手柄，供 --list 使用。"""
    import pygame

    pygame.init()
    pygame.event.pump()
    out: List[Dict[str, Any]] = []
    for i in range(pygame.joystick.get_count()):
        joy = pygame.joystick.Joystick(i)
        info: Dict[str, Any] = {
            "index": i,
            "name": joy.get_name(),
            "guid": joy.get_guid(),
            "axes": joy.get_numaxes(),
            "buttons": joy.get_numbuttons(),
            "hats": joy.get_numhats(),
            "sdl_mapping": _query_sdl_mapping(joy) is not None,
            "rumble": hasattr(joy, "rumble"),
        }
        out.append(info)
    return out


def open_source(cfg: Any, verbose: bool = False) -> PygameJoystickSource:
    """按配置打开手柄。verbose=True 时打印完整的布局/键位报告。"""
    return PygameJoystickSource(
        index=cfg.joystick_index,
        layout=cfg.axis_layout,
        invert=getattr(cfg, "invert", None),
        deadzone=cfg.deadzone,
        trigger_threshold=cfg.trigger_threshold,
        calibration_ms=cfg.calibration_ms,
        verbose=verbose,
    )
