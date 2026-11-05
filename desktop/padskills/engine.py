"""250Hz 无阻塞采样主循环。

节奏控制用"绝对时间轴 + 追帧重对齐"，而不是简单的 sleep(1/250)：
这样即使某一轮因为 GC 或系统调度慢了，后续也会自动补上，
并且不会出现越积越多的"追帧雪崩"。
"""

from __future__ import annotations

import shutil
import sys
import time
from dataclasses import dataclass, field
from typing import Callable, Dict, List, Optional, TextIO

__all__ = ["Engine", "ActiveSkill", "Outcome", "enable_windows_ansi"]


class _NullWriter:
    """windowed 打包时 sys.stdout 是 None，写日志要有个安全的落点。"""

    def write(self, _text: str) -> int:
        return 0

    def flush(self) -> None:
        pass


def enable_windows_ansi() -> bool:
    """在 Windows 控制台上打开 ANSI 转义序列支持。

    --trace 需要"光标上移一行"来原地刷新两行，`\\r` 做不到这件事。
    Windows 10+ 的 cmd / PowerShell 支持 ANSI，但默认没开，得自己打开。
    """
    if sys.platform != "win32":
        return True
    try:
        import ctypes

        ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x0004
        STD_OUTPUT_HANDLE = -11
        kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
        handle = kernel32.GetStdHandle(STD_OUTPUT_HANDLE)
        mode = ctypes.c_uint32()
        if not kernel32.GetConsoleMode(handle, ctypes.byref(mode)):
            return False
        if mode.value & ENABLE_VIRTUAL_TERMINAL_PROCESSING:
            return True
        return bool(kernel32.SetConsoleMode(
            handle, mode.value | ENABLE_VIRTUAL_TERMINAL_PROCESSING))
    except Exception:
        return False

from .config import AppConfig, Skill
from .detectors import Detector, Failure, Frame, Hit, build_detector
from .input_source import GamepadSource, PadState
from .rumble import RumbleEngine

__all__ = ["Engine", "ActiveSkill", "Outcome"]


@dataclass
class Outcome:
    """一次尝试的结果（成功或失败），CLI 和 GUI 共用。

    ok=True 时 code 为 "ok"、message 为空；失败时 message 是给用户看的一行原因。
    """
    skill_name: str
    ok: bool
    code: str
    message: str
    elapsed_ms: float
    at: float
    # 成功时的参数摘要（旋转角度 / 保持时长 / 角度范围），失败时为空
    detail: str = ""


@dataclass
class ActiveSkill:
    skill: Skill
    detector: Detector
    last_fire: float = -1e9
    hits: int = 0
    attempts: int = 0
    # 练习进度：每做对 GROUP_SIZE 个算一组，满了清零重新数
    group_hits: int = 0
    groups_done: int = 0
    failures: Dict[str, int] = field(default_factory=dict)
    last_outcome: Optional[Outcome] = None


class Engine:
    GROUP_SIZE = 10

    # 右摇杆低于这个幅度算"没在推"；一次动作触发后要回中并保持一小段，
    # 才允许开始下一个动作，避免一个连续动作被拆成两个、或上一个动作的尾巴接成下一个。
    IDLE_STICK = 0.20
    RELEASE_STICK = 0.35

    def __init__(self, cfg: AppConfig, source: GamepadSource, rumble: RumbleEngine,
                 debug: bool = False, trace: bool = False, verbose: bool = False,
                 feedback: bool = False, out: TextIO = None):
        self.cfg = cfg
        self.source = source
        self.rumble = rumble
        self.debug = debug
        self.trace = trace
        self.verbose = verbose
        # 默认只在成功时打印；失败诊断是练习模式的重点，CLI 里用 --feedback 打开
        self.feedback = feedback
        self.out = out if out is not None else (sys.stdout or _NullWriter())

        self.skills: List[ActiveSkill] = [
            ActiveSkill(skill=s, detector=build_detector(s))
            for s in cfg.enabled_skills()
        ]
        # 专项练习：只让指定动作参与判定，其余动作完全不喂数据。
        # 自由练习时几个动作会同时给出"方向对了/保持中"的提示，互相干扰；
        # 专项模式下只有一个识别器在跑，提示和成败都只属于它。
        self.focus: Optional[ActiveSkill] = None
        # 暂停判定（按键校准面板打开时用），不影响采样和 GUI 刷新
        self.paused = False
        self.facing = cfg.input.initial_facing_deg
        # 左摇杆回中时没有"球员朝向"，所有相对朝向判定的动作都不成立
        self.facing_valid = False
        self._last_state: Optional[PadState] = None
        self._last_any_fire = -1e9
        self._running = True

        # 动作分段：一次触发后先锁住，等右摇杆真正回中；长时间没有输入则清空未完成进度
        self._gesture_locked = False
        self._lock_release_since: Optional[float] = None
        self._idle_since: Optional[float] = None
        self._idle_cleared = False
        self._debug_width = max(60, shutil.get_terminal_size((120, 30)).columns - 1)
        self._debug_line_len = 0

        # --trace 要原地刷新两行，必须能控制光标；控制台不支持 ANSI 时自动降级
        self._ansi = enable_windows_ansi() if trace else False
        if trace and not self._ansi:
            print("[提示] 当前终端不支持 ANSI 转义序列，--trace 的两行刷新已关闭"
                  "（--debug 的单行刷新不受影响）。"
                  "建议用支持 ANSI 的终端（Windows Terminal / VS Code / macOS Terminal）。")
            self.trace = False

        # 统计
        self.frames = 0
        self.overruns = 0
        self.suppressed = 0
        self.started_at = 0.0

        # 最近一次尝试的结果；GUI 靠 outcome_seq 判断有没有新结果
        self.last_outcome: Optional[Outcome] = None
        self.outcome_seq = 0

    # ------------------------------------------------------------------
    # 专项练习
    # ------------------------------------------------------------------

    def active_skills(self) -> List[ActiveSkill]:
        """当前参与判定的动作。专项练习时只有那一个。"""
        return [self.focus] if self.focus is not None else self.skills

    def set_focus(self, active: Optional[ActiveSkill]) -> None:
        """开关专项练习。传 None 回到自由练习。

        切换时把所有识别器的半截进度清掉：否则从"练绿射"切回自由练习，
        上一段摇杆轨迹还挂在别的动作里，会立刻报一条莫名其妙的失败。
        """
        if active is not None and active not in self.skills:
            return
        self.focus = active
        self._reset_progress()
        self.last_outcome = None

    def set_paused(self, paused: bool) -> None:
        """暂停/恢复判定。恢复时清掉暂停期间攒下的半截进度。"""
        paused = bool(paused)
        if paused == self.paused:
            return
        self.paused = paused
        if not paused:
            self._reset_progress()

    def _reset_progress(self) -> None:
        """丢掉所有未完成的进度，并让动作可以立刻重新起手。

        先 ``abandon()`` 静默清空（不会像 ``reset()`` 那样报"中途松手"），
        再 ``on_idle()`` 把 armed 拉回 True。少了后半步，画弧/序列动作要等
        摇杆回中 120~150ms 才重新武装，点完专项开关马上出手的第一下会被吃掉。
        """
        for item in self.skills:
            item.detector.abandon()
            item.detector.on_idle()
        self._gesture_locked = False
        self._lock_release_since = None
        self._idle_since = None
        self._idle_cleared = False

    # ------------------------------------------------------------------
    # 主循环
    # ------------------------------------------------------------------

    def run(self, duration: Optional[float] = None,
            on_tick: Optional[Callable[[float, PadState], None]] = None) -> None:
        """主循环。`on_tick(now, state)` 每帧调用一次，必须立即返回、不能 sleep；
        GUI 自己按时间戳节流到 60fps。"""
        period = 1.0 / max(1, self.cfg.input.poll_hz)
        next_tick = time.perf_counter()
        deadline = None if duration is None else next_tick + duration
        self.started_at = next_tick

        try:
            while self._running:
                now = time.perf_counter()
                if deadline is not None and now >= deadline:
                    break

                state = self.source.poll()
                self._last_state = state
                self._tick(now, state)
                self.frames += 1

                if self.debug:
                    self._render_debug(now, state)
                if on_tick is not None:
                    on_tick(now, state)

                next_tick += period
                slack = next_tick - time.perf_counter()
                if slack > 0:
                    time.sleep(slack)
                else:
                    # 落后了：重新对齐时间轴，并记录一次 overrun
                    self.overruns += 1
                    next_tick = time.perf_counter()
        except KeyboardInterrupt:
            self._write("\n收到 Ctrl+C，正在退出…\n")
        finally:
            self._clear_debug_line()
            self.rumble.close()
            self.source.close()

    # ------------------------------------------------------------------
    # 单帧处理
    # ------------------------------------------------------------------

    def _tick(self, now: float, state: PadState) -> None:
        # 左摇杆推动时更新"球员面朝方向"；回中则标记为"没有朝向"。
        # 回中时哪怕记住最后一次方向也不作数——没有方向，方向类动作就不成立。
        ls_ok = state.ls_mag >= self.cfg.input.ls_facing_threshold
        self.facing_valid = ls_ok
        if ls_ok:
            self.facing = state.ls_angle

        if self.paused:
            # 暂停判定（校准面板打开时）：照样采样，但不识别、不记结果、不震动，
            # 否则校准用的按键会被当成真实动作，边校准边震。
            self.rumble.update(now)   # 让已经开始的那一下自然震完
            return

        frame = Frame(
            now=now,
            state=state,
            ls_mag=state.ls_mag,
            ls_angle=state.ls_angle,
            rs_mag=state.rs_mag,
            rs_angle=state.rs_angle,
            facing=self.facing,
            buttons=state.buttons,
        )

        # 一次动作触发后先锁住识别，直到右摇杆真正回中。
        # 这样同一个连续轨迹不会被两个识别器先后认成两个动作。
        if self._gesture_locked:
            if state.rs_mag < self.RELEASE_STICK:
                if self._lock_release_since is None:
                    self._lock_release_since = now
                if (now - self._lock_release_since) * 1000.0 >= self.cfg.input.gesture_release_ms:
                    for active in self.skills:
                        active.detector.on_idle()
                    self._gesture_locked = False
                    self._lock_release_since = None
            else:
                self._lock_release_since = None

            if self._gesture_locked:
                self.rumble.update(now)
                return

        # 按住某个动作的修饰键（例如 L1）时，只判定需要这个键的动作：
        # 现在按着 L1 就只可能是油炸丸子，其他动作整个跳过，不参与竞争。
        # 专项练习时只看得到当前动作：别的动作的修饰键被按住也不该影响判定
        # （否则"练绿射时顺手按了 L1"会把绿射整个跳过）。
        active_skills = self.active_skills()
        held_required = {
            b
            for active in active_skills
            for b in active.skill.required_buttons
            if b in state.buttons
        }

        # 长时间没有推右摇杆：清空所有未完成动作，防止上一段的尾巴被当成下一段的起手
        if state.rs_mag < self.IDLE_STICK:
            if self._idle_since is None:
                self._idle_since = now
            if (not self._idle_cleared
                    and (now - self._idle_since) * 1000.0 >= self.cfg.input.idle_reset_ms):
                for active in active_skills:
                    active.detector.on_idle()
                self._idle_cleared = True
        else:
            self._idle_since = None
            self._idle_cleared = False

        for active in active_skills:
            # 按住了别的动作的修饰键 -> 这个动作今天不参与判定；
            # 静默丢弃半截进度，不能让它过一会儿报"没做完"。
            if (held_required
                    and not any(b in active.skill.required_buttons
                                for b in held_required)):
                active.detector.observe(frame)
                active.detector.abandon()
                continue

            # 相对左摇杆朝向的动作：左摇杆回中时没有方向基准，整段作废。
            if active.skill.relative_to_ls and not ls_ok:
                active.detector.observe(frame)
                active.detector.reset()
                continue

            if not self._buttons_ok(active.skill, state.buttons):
                # 修饰键没按住 -> 该动作的进度作废（例如 L1 松开了就不是 La Croqueta）。
                # 但先把这一帧的摇杆位置记下来：GUI 靠它提示
                # "方向对了，要按住 L1"，比什么都不显示强得多。
                active.detector.observe(frame)
                active.detector.reset()
                continue

            hit = active.detector.update(frame)
            if hit is None:
                continue

            # 这一次手势已经成功了，别的识别器攒下的进度和失败裁定全部作废：
            # 同一次手势不能既报成功又报失败，也不能过一会儿再报"没做完"。
            self._discard_other_claims(active)

            if (now - active.last_fire) * 1000.0 < active.skill.cooldown_ms:
                continue
            if (now - self._last_any_fire) * 1000.0 < self.cfg.global_cooldown_ms:
                self.suppressed += 1
                continue

            active.last_fire = now
            active.hits += 1
            active.attempts += 1
            active.group_hits += 1
            if active.group_hits >= self.GROUP_SIZE:
                active.group_hits = 0
                active.groups_done += 1
            self._last_any_fire = now
            self._record(active, ok=True, code="ok", message="",
                         elapsed_ms=hit.elapsed_ms, now=now,
                         detail=hit.summary)
            self._fire(active, hit, state, now)

            # 一次物理动作只认一个技能；其余识别器等回中后重新开始
            self._gesture_locked = True
            self._lock_release_since = None
            break

        # 失败裁定统一在这里取：不管它是在 update()、reset() 还是 on_idle() 里
        # 产出的，都只在这一个点进日志/统计，保证一次尝试最多一条。
        self._drain_failures(now)

        # 震动状态机由主循环驱动，所有 SDL 调用都在同一个线程里
        self.rumble.update(now)

    def _discard_other_claims(self, winner: ActiveSkill) -> None:
        """一次物理手势只归一个动作。

        触发成功的动作之外的识别器，攒下的失败裁定和半截进度都要清掉。
        不清进度的话，一次"从正前起手的踩单车"会顺手把磕球过人的第一步
        匹配上，等摇杆回中后又被报成"磕球没做完"——明明是同一个动作。
        """
        for active in self.active_skills():
            if active is winner:
                continue
            active.detector.abandon()

    def _drain_failures(self, now: float) -> None:
        owner: Optional[ActiveSkill] = None
        for active in self.active_skills():
            failure = active.detector.pop_failure()
            if failure is None:
                continue
            # 同一次手势最多一条裁定；先到的（配置里靠前的）留下
            if owner is not None:
                continue
            owner = active
            active.attempts += 1
            active.failures[failure.code] = active.failures.get(failure.code, 0) + 1
            self._record(active, ok=False, code=failure.code,
                         message=failure.message,
                         elapsed_ms=failure.elapsed_ms, now=now)
            if self.feedback or self.verbose:
                self._report_failure(active, failure)

        # 失败也意味着"这次手势结束了"：别的识别器从这段轨迹里攒的进度
        # 同样不能用（例如画弧失败时顺手扫过的"前"，不该再报磕球没做完）。
        if owner is not None:
            self._discard_other_claims(owner)

    def _record(self, active: ActiveSkill, ok: bool, code: str, message: str,
                elapsed_ms: float, now: float, detail: str = "") -> None:
        outcome = Outcome(
            skill_name=active.skill.name, ok=ok, code=code,
            message=message, elapsed_ms=elapsed_ms, at=now, detail=detail,
        )
        active.last_outcome = outcome
        self.last_outcome = outcome
        self.outcome_seq += 1

    def _report_failure(self, active: ActiveSkill, failure: Failure) -> None:
        self._clear_debug_line()
        self._write(
            f"[{time.strftime('%H:%M:%S')}] ✗ {active.skill.name} — {failure.message}\n")

    def reset_stats(self) -> None:
        """GUI 的 R 键 / 重新开始练习。"""
        for active in self.skills:
            active.hits = 0
            active.attempts = 0
            active.group_hits = 0
            active.groups_done = 0
            active.failures.clear()
            active.last_fire = -1e9
            active.last_outcome = None
        self.last_outcome = None
        self.outcome_seq += 1
        self.frames = 0
        self.overruns = 0
        self.suppressed = 0
        self.started_at = time.perf_counter()

    @staticmethod
    def _buttons_ok(skill: Skill, buttons) -> bool:
        if not skill.required_buttons:
            return True
        if skill.button_mode == "any":
            return any(b in buttons for b in skill.required_buttons)
        return all(b in buttons for b in skill.required_buttons)

    def _fire(self, active: ActiveSkill, hit: Hit, state: PadState, now: float) -> None:
        fired = self.rumble.play(active.skill.pattern, now)
        self._clear_debug_line()

        if self.verbose:
            # --verbose 才打详细轨迹，平时只报动作名
            held = ",".join(sorted(state.buttons)) or "无"
            self._write(
                f"[{time.strftime('%H:%M:%S')}] {active.skill.name} | "
                f"{hit.elapsed_ms:.0f}ms | {hit.detail} | 按键[{held}] | "
                f"{'已震动' if fired else '未震动'}\n"
            )
            return

        # 默认：一行，只说明"识别到了哪个动作"。
        # 震动没发出去才追加一个标记——正常情况不加任何后缀，保持安静。
        suffix = "" if fired else "   (识别到了但震动未发出)"
        self._write(f"[{time.strftime('%H:%M:%S')}] ✓ {active.skill.name}{suffix}\n")

    # ------------------------------------------------------------------
    # 调试输出
    # ------------------------------------------------------------------

    @staticmethod
    def _angle_cell(angle: float, mag: float) -> str:
        """摇杆没推动时不显示角度——居中时角度是无意义的。

        两种返回值都是 6 个字符，保证后面的幅度列对齐。
        """
        return " --.-°" if mag < 0.02 else f"{angle:5.1f}°"

    def _render_debug(self, now: float, state: PadState) -> None:
        if self.out is None:
            return
        raw_axes = " ".join(f"{v:+.2f}" for v in state.raw_axes)
        buttons = ",".join(sorted(state.buttons)) or "-"
        raw_btn = ",".join(str(i) for i in state.raw_buttons) or "-"
        line = (
            f"LS {self._angle_cell(state.ls_angle, state.ls_mag)} {state.ls_mag:4.2f} | "
            f"RS {self._angle_cell(state.rs_angle, state.rs_mag)} {state.rs_mag:4.2f} | "
            f"面朝 {self.facing:5.1f}° | "
            f"LT {state.lt:4.2f} RT {state.rt:4.2f} | "
            f"键[{buttons}] #{raw_btn} | "
            f"轴[{raw_axes}]"
        )

        if self.trace:
            parts = [f"{a.skill.name.split(' ')[0]}:{a.detector.status()}" for a in self.skills]
            trace_line = "  " + " | ".join(parts)
            # 写完两行后用 \x1b[1A 把光标挪回第一行，下一帧才能原地覆盖
            self.out.write(
                "\r" + line[: self._debug_width] + "\x1b[K\n"
                + trace_line[: self._debug_width] + "\x1b[K\x1b[1A"
            )
        else:
            self.out.write("\r" + line[: self._debug_width].ljust(self._debug_width))
            self._debug_line_len = self._debug_width
        self.out.flush()

    def _clear_debug_line(self) -> None:
        if not self.debug:
            return
        if self.trace:
            # 清两行，然后把光标放回第一行行首
            self.out.write("\r\x1b[K\n\x1b[K\x1b[1A\r")
        else:
            self.out.write("\r" + " " * max(self._debug_line_len, 1) + "\r")
        self.out.flush()

    def _write(self, text: str) -> None:
        if self.out is None:
            return
        self.out.write(text)
        self.out.flush()

    def stop(self) -> None:
        self._running = False

    # ------------------------------------------------------------------
    # 汇总
    # ------------------------------------------------------------------

    def summary(self) -> str:
        """退出时的简短统计。正常情况下只报各动作触发次数，
        只有在时序或震动出问题时才额外提一句（异常才值得占用你的注意力）。"""
        elapsed = max(1e-6, time.perf_counter() - self.started_at) if self.started_at else 0.0
        total = sum(a.hits for a in self.skills)
        lines = [
            "",
            "─" * 46,
            f"运行 {elapsed:.0f}s | {self.frames / elapsed:.0f}Hz | 共触发 {total} 次"
            if elapsed else "",
        ]
        short = lambda name: name.split(" (")[0]
        for active in self.skills:
            if not active.attempts:
                continue
            pct = 100.0 * active.hits / active.attempts
            line = (f"  {active.hits:4d}/{active.attempts:<4d} "
                    f"{short(active.skill.name):<22s} {pct:3.0f}%")
            if active.failures:
                code, count = max(active.failures.items(), key=lambda kv: kv[1])
                label = Detector.FAILURE_LABELS.get(code, code)
                line += f"   最多: {label} ×{count}"
            lines.append(line)
        idle = [short(a.skill.name) for a in self.skills if not a.attempts]
        if idle:
            lines.append(f"  未尝试: {', '.join(idle)}")
        if self.overruns:
            lines.append(f"  ⚠ 采样调度落后 {self.overruns} 次")
        if self.rumble.failures:
            lines.append(f"  ⚠ {self.rumble.health()}")
        lines.append("─" * 46)
        return "\n".join(line for line in lines if line != "")
