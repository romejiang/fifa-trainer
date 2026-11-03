"""震动引擎：多后端自动回退 + 完全非阻塞。

后端优先级（auto 模式）实测依据：
    1. pygame-ce `Joystick.rumble()`   —— 飞智八爪鱼 4 实测返回 True，可用
    2. SDL2 `Controller.rumble()`      —— 同一台设备实测返回 False（SDL 的
                                          GameController 层认为该设备不支持）
    3. XInput ctypes (Xinput1_4.dll)   —— 直接走微软 XInput，绕开 SDL
    4. XInput-Python（可选安装）

主采样循环绝不能因为震动而卡住，所以震动是非阻塞的：下发一次、记下截止时间，
每帧比较时间戳，不做 sleep。所有 SDL 调用都在主循环线程里完成。
"""

from __future__ import annotations

import ctypes
import sys
import time
from typing import Callable, List, Optional, Sequence

from .config import Pulse

__all__ = ["RumbleBackend", "RumbleEngine", "build_backends", "pick_backend"]


# ---------------------------------------------------------------------------
# 后端
# ---------------------------------------------------------------------------

class RumbleBackend:
    """一个震动后端。start() 必须立刻返回，不能阻塞。"""

    label = "未知后端"

    def start(self, low: float, high: float, duration_ms: int) -> bool:
        raise NotImplementedError

    def stop(self) -> None:
        pass

    def close(self) -> None:
        try:
            self.stop()
        except Exception:
            pass


class PygameJoystickRumble(RumbleBackend):
    """pygame-ce 的原始摇杆震动接口（实测最可靠）。"""

    def __init__(self, joystick):
        # 旧版 pygame / 某些精简构建没有 rumble()；在这里就说清楚，
        # 比等到第一次触发时抛 AttributeError 好排查得多。
        if not hasattr(joystick, "rumble"):
            raise RuntimeError(
                "当前 pygame 构建没有 Joystick.rumble()，请升级到 pygame-ce >= 2.4")
        self._joy = joystick
        name = joystick.get_name() if hasattr(joystick, "get_name") else "?"
        self.label = f"pygame-ce Joystick.rumble() [{name}]"

    def start(self, low: float, high: float, duration_ms: int) -> bool:
        return bool(self._joy.rumble(float(low), float(high), int(duration_ms)))

    def stop(self) -> None:
        self._joy.stop_rumble()


class SDL2ControllerRumble(RumbleBackend):
    """SDL2 GameController 层的震动接口。"""

    def __init__(self, index: int = 0):
        from pygame._sdl2 import controller as sdl2c
        if not sdl2c.get_init():
            sdl2c.init()
        self._dev = sdl2c.Controller(index)
        self.label = f"SDL2 GameController.rumble() [{self._dev.name}]"

    def start(self, low: float, high: float, duration_ms: int) -> bool:
        return bool(self._dev.rumble(float(low), float(high), int(duration_ms)))

    def stop(self) -> None:
        self._dev.stop_rumble()


class XInputRumble(RumbleBackend):
    """直接 ctypes 调用 Xinput1_4.dll（回退 1_3 / 9_1_0）。

    XInput 的震动是"持续"的：设了值就一直震，必须自己清零。
    本后端的 start() 只负责设值并立刻返回，清零交给 RumbleEngine 的后台线程。
    """

    class _VIBRATION(ctypes.Structure):
        _fields_ = [
            ("wLeftMotorSpeed", ctypes.c_ushort),    # 低频大马达
            ("wRightMotorSpeed", ctypes.c_ushort),   # 高频小马达
        ]

    def __init__(self, user_index: int = 0):
        if sys.platform != "win32":
            raise RuntimeError("XInput 只在 Windows 上可用")
        self._user = user_index
        last_error: Optional[Exception] = None
        dll_name = ""
        for dll_name in ("Xinput1_4.dll", "Xinput1_3.dll", "Xinput9_1_0.dll"):
            try:
                self._lib = ctypes.WinDLL(dll_name)
                break
            except OSError as exc:
                last_error = exc
        else:
            raise RuntimeError(f"加载 XInput 动态库失败: {last_error}")

        self._set_state = self._lib.XInputSetState
        self._set_state.argtypes = [ctypes.c_uint, ctypes.POINTER(self._VIBRATION)]
        self._set_state.restype = ctypes.c_uint
        try:
            self._get_state = self._lib.XInputGetState
            self._get_state.argtypes = [ctypes.c_uint, ctypes.c_void_p]
            self._get_state.restype = ctypes.c_uint
        except AttributeError:
            self._get_state = None
        self.label = f"XInput ctypes [{dll_name}]"

    def is_connected(self) -> bool:
        if self._get_state is None:
            return True
        buffer = ctypes.create_string_buffer(16)
        return self._get_state(self._user, buffer) == 0

    def start(self, low: float, high: float, duration_ms: int) -> bool:
        vibration = self._VIBRATION(
            int(min(1.0, max(0.0, low)) * 65535),
            int(min(1.0, max(0.0, high)) * 65535),
        )
        return self._set_state(self._user, ctypes.byref(vibration)) == 0

    def stop(self) -> None:
        try:
            self.start(0.0, 0.0, 0)
        except Exception:
            pass


class XInputPyRumble(RumbleBackend):
    """可选的 XInput-Python 包（`uv add xinput-python` 之后才会被启用）。"""

    def __init__(self, user_index: int = 0):
        import XInput  # type: ignore
        self._xinput = XInput
        self._user = user_index
        self.label = "XInput-Python [XInput.set_vibration()]"

    def start(self, low: float, high: float, duration_ms: int) -> bool:
        connected = self._xinput.get_connected()
        if not connected or self._user >= len(connected) or not connected[self._user]:
            return False
        self._xinput.set_vibration(
            self._user,
            int(min(1.0, max(0.0, low)) * 255),
            int(min(1.0, max(0.0, high)) * 255),
        )
        return True

    def stop(self) -> None:
        try:
            self._xinput.set_vibration(self._user, 0, 0)
        except Exception:
            pass


# ---------------------------------------------------------------------------
# 后端选择
# ---------------------------------------------------------------------------

def build_backends(which: str, joystick=None, joystick_index: int = 0,
                   verbose: bool = False) -> List[RumbleBackend]:
    """按配置构造候选后端列表（顺序即优先级）。"""
    which = (which or "auto").strip().lower()
    if which == "none":
        return []

    candidates: List[RumbleBackend] = []

    def add(description: str, factory: Callable[[], RumbleBackend]) -> None:
        try:
            candidates.append(factory())
        except Exception as exc:
            if verbose:
                print(f"  · 跳过 {description}: {exc}")

    if which in ("auto", "pygame") and joystick is not None:
        add("pygame-ce Joystick.rumble()", lambda: PygameJoystickRumble(joystick))
    if which in ("auto", "sdl2"):
        add("SDL2 GameController.rumble()", lambda: SDL2ControllerRumble(joystick_index))

    # XInput 是微软 Windows 专属的；macOS / Linux 上直接跳过，
    # 不要靠"import 失败"这种间接路径，否则 verbose 下来源不明。
    if which in ("auto", "xinput"):
        if sys.platform == "win32":
            add("XInput-Python（可选依赖，未安装则跳过）", lambda: XInputPyRumble(joystick_index))
            add("XInput ctypes (Xinput1_4.dll)", lambda: XInputRumble(joystick_index))
        elif which == "xinput":
            if verbose:
                print("  · 跳过 XInput: 该后端只在 Windows 上可用")
        elif verbose:
            print(f"  · 跳过 XInput: 当前平台 {sys.platform} 不支持")
    return candidates


def pick_backend(candidates: Sequence[RumbleBackend], logger: Callable[[str], None] = print,
                 strength: float = 0.55, duration_ms: int = 160,
                 verbose: bool = False) -> Optional[RumbleBackend]:
    """逐个试震，返回第一个真正返回成功的后端。

    verbose=False 时全程安静（试震本身照做），由调用方打印最终结果。
    """
    for backend in candidates:
        try:
            ok = backend.start(strength, strength, duration_ms)
        except Exception as exc:
            if verbose:
                logger(f"  ✗ {backend.label} —— 调用失败: {exc}")
            continue
        time.sleep(duration_ms / 1000.0)
        try:
            backend.stop()
        except Exception:
            pass
        if ok:
            if verbose:
                logger(f"  ✓ {backend.label} —— 自检成功")
            return backend
        if verbose:
            logger(f"  ✗ {backend.label} —— 接口返回失败（该设备不支持这个后端）")
    return None


# ---------------------------------------------------------------------------
# 引擎
# ---------------------------------------------------------------------------

class RumbleEngine:
    """单脉冲震动状态机，由主循环每帧驱动（不开后台线程）。

    为什么不用后台线程：SDL 的 joystick 子系统要求所有调用都发生在初始化它的
    那个线程上。主循环每秒 250 次 pygame.event.pump()，后台线程再去调
    SDL_JoystickRumble 会跟它撞车，表现就是"有时候震、有时候不震"。
    改由主循环驱动后，所有 SDL 调用都在同一线程里，问题消失。

    **只播一个脉冲，不排队。** 早先的版本会把多次触发排成队列背靠背播放，
    结果就是"有时候震得特别长、甚至一直在震"——因为几次触发被串成了一串。
    现在一次触发 = 一次固定时长的震动，到点一定停；上一次还没结束就来的
    新触发直接丢掉（识别端的手势锁 + 冷却已经保证正常搓招不会撞上）。

    依然是非阻塞的：play() 只是下发一次并记下截止时间，update() 每帧比较
    一下时间戳，不做任何 sleep。250Hz 意味着 4ms 的开关分辨率。
    """

    def __init__(self, backend: Optional[RumbleBackend], enabled: bool = True):
        self.backend = backend
        self.enabled = enabled and backend is not None
        self._active = False
        self._deadline = 0.0

        self.played = 0
        self.dropped = 0
        self.failures = 0
        self._last_error = ""

    # ------------------------------------------------------------------
    def start(self) -> None:
        """保留这个接口以便调用方不用改（现在不需要启动线程了）。"""

    def play(self, pattern: Sequence[Pulse], now: float) -> bool:
        """请求震一下。立即返回，不阻塞主循环。

        只取 pattern 的第一个脉冲——所有内置动作都是单震，多脉冲已不再使用。
        `now` 由调用方传入（主循环的 time.perf_counter() 时间戳），
        跟 update() 用同一个时间轴，避免两套时钟对不上导致震动停不下来。
        返回 True 表示震动真的下发成功了。
        """
        if not self.enabled or self.backend is None or not pattern:
            return False

        if self._active and now < self._deadline:
            # 上一次还没震完：丢掉这一次，绝不排队连播
            self.dropped += 1
            return False

        pulse = pattern[0]
        self.played += 1
        ok = self._safe_start(pulse)
        self._active = ok
        if ok:
            self._deadline = now + max(1, int(pulse.duration_ms)) / 1000.0
        return ok

    def update(self, now: float) -> None:
        """由主循环每帧调用：到点就停。"""
        if not self.enabled or self.backend is None:
            return
        if self._active and now >= self._deadline:
            self._safe_stop()
            self._active = False

    def _safe_start(self, pulse: Pulse) -> bool:
        try:
            ok = bool(self.backend.start(pulse.low, pulse.high, pulse.duration_ms))
        except Exception as exc:
            self.failures += 1
            self._last_error = f"{type(exc).__name__}: {exc}"
            return False
        if not ok:
            # 接口明确返回失败——多半是设备不支持这个后端，值得让用户知道
            self.failures += 1
            self._last_error = "后端返回失败（设备可能不支持该震动方式）"
        return ok

    def _safe_stop(self) -> None:
        try:
            self.backend.stop()
        except Exception:
            pass

    # ------------------------------------------------------------------
    def close(self) -> None:
        if self.backend is not None:
            self._safe_stop()
            try:
                self.backend.close()
            except Exception:
                pass
        self._active = False

    def health(self) -> str:
        """给运行结束时的统计用。"""
        if not self.enabled:
            return "震动已关闭"
        text = f"震动 {self.played} 次"
        if self.dropped:
            text += f"，因排队丢弃 {self.dropped} 次"
        if self.failures:
            text += f"，⚠ 后端报错 {self.failures} 次（{self._last_error}）"
        return text
