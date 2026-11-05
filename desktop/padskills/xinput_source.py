"""Windows 原生 XInput 读取源。

为什么需要它：部分手柄 / 接收器（例如飞智的 2.4G 接收器）在 XInput 模式下
只往 XInput 接口送数据，同时暴露出来的 HID 接口是静默的。SDL 可能枚举到
那个 HID 接口，读到的轴和键全是静止值；但 `XInputGetState()` 能看到真实
输入。表现就是"系统测试页/游戏都正常，这个程序按什么都没反应"。

这里不经过 SDL，直接调用微软的 XInput API，槽位 0~3 与
`input.joystick_index` 对应。按键编号沿用 SDL 对 Xbox 360 的标准顺序
（A=0, B=1, X=2, Y=3, LB=4, RB=5, BACK=6, START=7, LS=8, RS=9, GUIDE=10），
所以以前在 SDL 下做过的按键校准也能继续用。
"""

from __future__ import annotations

import ctypes
import sys
from typing import Any, Dict, List, Optional, Tuple

from .input_source import (
    AxisLayout,
    GamepadSource,
    PadState,
    _deadzone,
    _hat_matches,
    apply_axis_inverts,
    apply_button_names,
    canonical_button,
)

__all__ = ["XINPUT_AVAILABLE", "XInputSource", "connected_slots"]

_ERROR_SUCCESS = 0

# XInput 标准按键位
_GAMEPAD_DPAD_UP = 0x0001
_GAMEPAD_DPAD_DOWN = 0x0002
_GAMEPAD_DPAD_LEFT = 0x0004
_GAMEPAD_DPAD_RIGHT = 0x0008
_GAMEPAD_START = 0x0010
_GAMEPAD_BACK = 0x0020
_GAMEPAD_LEFT_THUMB = 0x0040
_GAMEPAD_RIGHT_THUMB = 0x0080
_GAMEPAD_LEFT_SHOULDER = 0x0100
_GAMEPAD_RIGHT_SHOULDER = 0x0200
_GAMEPAD_GUIDE = 0x0400
_GAMEPAD_A = 0x1000
_GAMEPAD_B = 0x2000
_GAMEPAD_X = 0x4000
_GAMEPAD_Y = 0x8000

# 位 -> 原始键编号。编号刻意与 SDL 的 Xbox 360 映射保持一致。
_BIT_TO_INDEX: Tuple[Tuple[int, int], ...] = (
    (_GAMEPAD_A, 0),
    (_GAMEPAD_B, 1),
    (_GAMEPAD_X, 2),
    (_GAMEPAD_Y, 3),
    (_GAMEPAD_LEFT_SHOULDER, 4),
    (_GAMEPAD_RIGHT_SHOULDER, 5),
    (_GAMEPAD_BACK, 6),
    (_GAMEPAD_START, 7),
    (_GAMEPAD_LEFT_THUMB, 8),
    (_GAMEPAD_RIGHT_THUMB, 9),
    (_GAMEPAD_GUIDE, 10),
)

_DEFAULT_BUTTONS: Dict[str, int] = {
    "A": 0, "B": 1, "X": 2, "Y": 3,
    "LB": 4, "RB": 5, "BACK": 6, "START": 7,
    "LS": 8, "RS": 9, "GUIDE": 10,
}


class XINPUT_GAMEPAD(ctypes.Structure):
    _fields_ = [
        ("wButtons", ctypes.c_ushort),
        ("bLeftTrigger", ctypes.c_ubyte),
        ("bRightTrigger", ctypes.c_ubyte),
        ("sThumbLX", ctypes.c_short),
        ("sThumbLY", ctypes.c_short),
        ("sThumbRX", ctypes.c_short),
        ("sThumbRY", ctypes.c_short),
    ]


class XINPUT_STATE(ctypes.Structure):
    _fields_ = [
        ("dwPacketNumber", ctypes.c_ulong),
        ("Gamepad", XINPUT_GAMEPAD),
    ]


class XINPUT_VIBRATION(ctypes.Structure):
    _fields_ = [
        ("wLeftMotorSpeed", ctypes.c_ushort),
        ("wRightMotorSpeed", ctypes.c_ushort),
    ]


def _load_xinput() -> Any:
    if sys.platform != "win32":
        return None
    # xinput1_4 在 Win8+ 上才有；老系统退到 1_3 / 9_1_0。
    for name in ("xinput1_4.dll", "xinput1_3.dll", "xinput9_1_0.dll"):
        try:
            return ctypes.WinDLL(name)
        except OSError:
            continue
    return None


_XINPUT = _load_xinput()
XINPUT_AVAILABLE = _XINPUT is not None

if _XINPUT is not None:
    _get_state = _XINPUT.XInputGetState
    _get_state.argtypes = [ctypes.c_uint, ctypes.POINTER(XINPUT_STATE)]
    _get_state.restype = ctypes.c_uint

    _set_state = _XINPUT.XInputSetState
    _set_state.argtypes = [ctypes.c_uint, ctypes.POINTER(XINPUT_VIBRATION)]
    _set_state.restype = ctypes.c_uint
else:
    _get_state = None
    _set_state = None


def connected_slots() -> List[int]:
    """返回当前有手柄的 XInput 槽位（0~3）。非 Windows 上返回空列表。"""
    if _get_state is None:
        return []
    slots: List[int] = []
    for slot in range(4):
        state = XINPUT_STATE()
        try:
            if _get_state(slot, ctypes.byref(state)) == _ERROR_SUCCESS:
                slots.append(slot)
        except Exception:
            pass
    return slots


def _norm_thumb(value: int) -> float:
    """XInput 摇杆 -32768~32767 -> -1.0~1.0。"""
    return max(-1.0, min(1.0, value / 32767.0))


def _default_layout() -> AxisLayout:
    lay = AxisLayout()
    lay.ls_x, lay.ls_y = 0, 1
    lay.rs_x, lay.rs_y = 2, 3
    lay.lt_axis, lay.rt_axis = 4, 5
    lay.trigger_rest = 0.0
    lay.buttons = dict(_DEFAULT_BUTTONS)
    lay.dpad = {
        "DPAD_UP": (0, 1), "DPAD_RIGHT": (0, 2),
        "DPAD_DOWN": (0, 4), "DPAD_LEFT": (0, 8),
    }
    return lay


class XInputSource(GamepadSource):
    """直接调用 XInputGetState 的读取源（仅 Windows）。"""

    def __init__(self, slot: Optional[int] = None, deadzone: float = 0.08,
                 trigger_threshold: float = 0.35, verbose: bool = False,
                 invert: Optional[Dict[str, Any]] = None,
                 button_names: Optional[Dict[str, Any]] = None):
        if _get_state is None:
            raise RuntimeError("XInput 当前不可用（仅 Windows 支持）")

        slots = connected_slots()
        if not slots:
            raise RuntimeError(
                "没有检测到任何 XInput 手柄。请确认手柄已连接、已开机，"
                "并切到 XInput 模式（有线或 2.4G 接收器）。"
            )
        if slot is None or slot not in slots:
            slot = slots[0]

        self.xinput_slot = slot
        self.name = f"XInput 手柄 #{slot}"
        self.guid = f"XInput:{slot}"
        self.num_axes = 6
        self.num_buttons = len(_BIT_TO_INDEX)
        self.num_hats = 1
        self.layout_source = "XInput 原生（微软 XInputGetState）"
        self.layout = _default_layout()
        self._deadzone = deadzone
        self._trigger_threshold = trigger_threshold

        self.axis_invert = {str(k).strip().lower(): bool(v)
                            for k, v in (invert or {}).items()}
        if self.axis_invert:
            apply_axis_inverts(self.layout, self.axis_invert)

        # 保留自动识别的按键表，GUI 里"清除校准"时能退回这里。
        self._auto_buttons: Dict[str, int] = dict(self.layout.buttons)
        self.button_names: Dict[str, int] = {}
        self.button_notes: List[str] = []
        self.set_button_names(button_names or {})

        # 日志里沿用手柄源的"轴静止值"字段；XInput 的静止值是固定的。
        self._rest = [{"min": 0.0, "max": 0.0, "mean": 0.0}
                      for _ in range(self.num_axes)]

        if verbose:
            self._print_layout_report()

    # -- 按键校准（与 PygameJoystickSource 同接口） ---------------------

    def set_button_names(self, names: Dict[str, Any]) -> List[str]:
        self.layout.buttons = dict(self._auto_buttons)
        self.button_names = {}
        for key, value in (names or {}).items():
            try:
                self.button_names[canonical_button(key)] = int(value)
            except (TypeError, ValueError):
                continue
        self.button_notes = apply_button_names(self.layout, names)
        return self.button_notes

    def button_overrides(self) -> Dict[str, int]:
        return {name: index for name, index in self.layout.buttons.items()
                if self._auto_buttons.get(name) != index}

    def _print_layout_report(self) -> None:
        lay = self.layout
        print(f"  设备名称   : {self.name}")
        print(f"  布局来源   : {self.layout_source}")
        print(f"  轴/键/帽   : {self.num_axes} 轴 / {self.num_buttons} 键 / {self.num_hats} 方向帽")
        print(f"  左摇杆     : 轴 {lay.ls_x}, {lay.ls_y}"
              f"    右摇杆: 轴 {lay.rs_x}, {lay.rs_y}")
        print(f"  扳机       : LT=轴{lay.lt_axis}, RT=轴{lay.rt_axis}"
              f"（静止值 {lay.trigger_rest:+.0f}）")
        print("  按键映射   : " + ", ".join(
            f"{k}=#{v}" for k, v in sorted(lay.buttons.items())))

    # -- 轮询 ------------------------------------------------------------

    def poll(self) -> PadState:
        state = XINPUT_STATE()
        if _get_state(self.xinput_slot, ctypes.byref(state)) != _ERROR_SUCCESS:
            raise RuntimeError(f"XInput 手柄 #{self.xinput_slot} 已断开")
        g = state.Gamepad
        lay = self.layout

        # XInput 的 Y 轴向上为正；项目内部（与 SDL 一致）向下为正，所以取反。
        raw: Tuple[float, ...] = (
            _norm_thumb(g.sThumbLX),
            -_norm_thumb(g.sThumbLY),
            _norm_thumb(g.sThumbRX),
            -_norm_thumb(g.sThumbRY),
            g.bLeftTrigger / 255.0,
            g.bRightTrigger / 255.0,
        )

        def axis(index: Optional[int]) -> float:
            if index is None or index < 0 or index >= len(raw):
                return 0.0
            return raw[index]

        ls_x = -axis(lay.ls_x) if lay.invert_ls_x else axis(lay.ls_x)
        ls_y = -axis(lay.ls_y) if lay.invert_ls_y else axis(lay.ls_y)
        rs_x = -axis(lay.rs_x) if lay.invert_rs_x else axis(lay.rs_x)
        rs_y = -axis(lay.rs_y) if lay.invert_rs_y else axis(lay.rs_y)

        ls_x, ls_y = _deadzone(ls_x, ls_y, self._deadzone)
        rs_x, rs_y = _deadzone(rs_x, rs_y, self._deadzone)

        lt = min(1.0, max(0.0, axis(lay.lt_axis)))
        rt = min(1.0, max(0.0, axis(lay.rt_axis)))

        raw_buttons = [index for bit, index in _BIT_TO_INDEX
                       if g.wButtons & bit]
        reverse = {value: name for name, value in lay.buttons.items()}
        pressed = {reverse[index] for index in raw_buttons
                   if index in reverse}

        # 方向键在 XInput 里是位，不是 SDL 的 hat；合成 hat 值复用同一套掩码。
        hx = (1 if g.wButtons & _GAMEPAD_DPAD_RIGHT else 0) \
            - (1 if g.wButtons & _GAMEPAD_DPAD_LEFT else 0)
        hy = (1 if g.wButtons & _GAMEPAD_DPAD_UP else 0) \
            - (1 if g.wButtons & _GAMEPAD_DPAD_DOWN else 0)
        for name, (_, mask) in lay.dpad.items():
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
            raw_axes=raw,
            raw_buttons=tuple(raw_buttons),
        )

    def close(self) -> None:
        if _set_state is not None:
            try:
                _set_state(self.xinput_slot,
                           ctypes.byref(XINPUT_VIBRATION(0, 0)))
            except Exception:
                pass
