"""花式动作识别器。

内置两类识别算法，配置里的 `type` 字段决定用哪一个：

    arc       连续旋转类 —— 马赛回旋、麦吉迪转身……
              右摇杆推外圈后累计旋转角度，在时间窗口内落到目标区间即判定成功。

    sequence  方向点拨序列类 —— 磕球变向、La Croqueta、踩单车……
              按顺序匹配若干个方向点拨，支持"绝对方向"与"相对左摇杆朝向"两种基准。

两类识别器都支持 required_button 修饰键（由引擎在调用前过滤）。
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import FrozenSet, List, Optional, Sequence, Tuple

from .config import Skill, Step, parse_step, resolve_direction
from .geometry import angle_diff, norm_deg, signed_delta
from .input_source import PadState, canonical_button

__all__ = ["Frame", "Hit", "Detector", "ArcDetector", "SequenceDetector",
           "TapDetector", "build_detector"]


@dataclass
class Frame:
    """一帧采样数据，交给识别器判定。"""
    now: float            # time.perf_counter()
    state: PadState
    ls_mag: float
    ls_angle: float
    rs_mag: float
    rs_angle: float
    facing: float         # 球员面朝方向（左摇杆最后一次有效推动的角度）
    buttons: FrozenSet[str]


@dataclass
class Hit:
    """一次成功识别。"""
    elapsed_ms: float
    detail: str
    # 给 GUI / 日志用的简短参数摘要（转了多少度、保持多久、角度范围）
    summary: str = ""


@dataclass
class Failure:
    """一次"认出了这次手势、但没做对"的裁定。

    code 是给程序看的（统计用），message 是给用户看的一行中文。
    失败只做文字反馈，绝不触发震动——震动只代表"做对了"。
    """
    code: str
    message: str
    elapsed_ms: float = 0.0


class Detector:
    """识别器基类。"""

    # 给失败统计用的中文短标签
    FAILURE_LABELS = {
        "too_fast": "太快",
        "too_slow": "太慢",
        "too_short": "转得不够",
        "overshoot": "转多了",
        "wrong_start": "起点不对",
        "wrong_end": "终点不对",
        "wrong_direction": "方向反了",
        "stalled": "中途停住",
        "incomplete": "没做完",
        "hold_short": "保持不够",
    }

    def update(self, frame: Frame) -> Optional[Hit]:
        raise NotImplementedError

    def reset(self) -> None:
        """修饰键松开等情况下强制归零。"""

    def on_idle(self) -> None:
        """右摇杆已安静足够久，作废所有未完成的进度。"""
        self.reset()

    def abandon(self) -> None:
        """这次手势其实属于别的动作：丢掉进度，并且等摇杆回中再重新武装。

        和 ``reset()`` 的区别：``reset()`` 是"修饰键松了"这种可立刻重试的情况，
        ``abandon()`` 是"这一段轨迹已经被别的动作认领了"，绝不能半路重新起手。
        """
        self._pending = None
        self.reset()

    def pop_failure(self) -> Optional[Failure]:
        """取出并清空一次失败裁定（一次尝试最多一条）。"""
        failure = getattr(self, "_pending", None)
        self._pending = None
        return failure

    def _emit(self, failure: Failure) -> None:
        # 每个终结路径都会立刻 return，所以一次 update() 里最多走到这里一次。
        # 万一上一条还没被引擎取走，直接覆盖：新的这次更相关。
        self._pending = failure

    def status(self) -> str:
        """给 --trace / GUI 用的实时状态摘要。"""
        return ""

    def observe(self, frame: Frame) -> None:
        """只记下这一帧的摇杆位置，供 status() 提示用；不推进任何判定。

        修饰键没按住时引擎不会调 update()（会调 reset() 作废进度），
        但如果完全不看一眼摇杆，GUI 就永远只能显示"待机"，
        用户根本不知道是没按 L1 还是方向推错了。
        """


# ---------------------------------------------------------------------------
# 连续旋转类
# ---------------------------------------------------------------------------

class ArcDetector(Detector):
    """右摇杆画弧 / 转圈识别。

    状态机：
        armed   —— 可以开始一段新的画弧（必须等摇杆回落才重新武装，
                   避免同一个动作被反复触发）
        active  —— 正在累计旋转角度
    """

    def __init__(self, skill: Skill):
        p = skill.params
        self.enter = float(p.get("enter_threshold", 0.80))
        self.exit = float(p.get("exit_threshold", min(0.60, self.enter)))
        if self.exit >= self.enter:
            # 迟滞必须成立，否则会在阈值附近疯狂抖动
            self.exit = max(0.0, self.enter - 0.05)

        self.min_angle = float(p.get("min_angle", 150.0))
        self.max_angle = float(p.get("max_angle", 220.0))
        self.min_ms = float(p.get("min_duration_ms", 300.0))
        self.max_ms = float(p.get("max_duration_ms", 700.0))
        self.idle_ms = float(p.get("idle_timeout_ms", 180.0))
        self.motion_delta = float(p.get("motion_min_delta_deg", 2.0))
        if self.max_ms <= self.min_ms:
            raise ValueError(
                f"动作 {skill.name!r}: max_duration_ms ({self.max_ms}) 必须大于 "
                f"min_duration_ms ({self.min_ms})"
            )

        direction = str(p.get("direction", "any")).strip().lower()
        if direction in ("cw", "clockwise", "顺时针"):
            self.direction = 1
        elif direction in ("ccw", "counterclockwise", "逆时针"):
            self.direction = -1
        else:
            self.direction = 0
        self.direction_label = {0: "任意", 1: "顺时针", -1: "逆时针"}[self.direction]

        # 起点约束：光有"转了多少度"是不够的。
        # 从前往侧转 90° 是踩单车，从后往前转 180° 是马赛回旋——
        # 两者的差别就在"从哪儿开始转"，所以必须把起点也纳入判定。
        # start_angle 为 null 表示不限制起点。
        raw_start = p.get("start_angle")
        self.start_target: Optional[float] = (
            None if raw_start is None else resolve_direction(raw_start)
        )
        self.start_tolerance = float(p.get("start_tolerance", 60.0))

        raw_end = p.get("end_angles", p.get("end_angle"))
        if raw_end is None:
            end_values = []
        else:
            end_values = raw_end if isinstance(raw_end, (list, tuple)) else [raw_end]
        self.end_targets: Tuple[float, ...] = tuple(
            resolve_direction(value) for value in end_values
        )
        self.end_tolerance = float(p.get("end_tolerance", 60.0))
        self.release_hold_ms = float(p.get("release_hold_ms", 120.0))
        # 起点落在 start_tolerance + claim_margin 之内，才算"这次手势是冲我来的"。
        # 更远的推杆保持安静，避免一次随意推杆被好几个动作同时报失败。
        self.claim_margin = float(p.get("claim_margin_deg", 20.0))
        # 太小的抖动不值得报"转得不够"
        self.report_min_angle = max(20.0, self.min_angle * 0.35)
        self.relative = skill.relative_to_ls
        self._name = skill.name.split(" (")[0]

        self.armed = True
        self.active = False
        self.t0 = 0.0
        self.acc = 0.0
        self.last_angle = 0.0
        self.start_angle = 0.0      # 显示用：起点的绝对角度
        self.start_rel = 0.0        # 判定用：起点换算到判定基准后的角度
        self.end_rel = 0.0
        self.base = 0.0             # 本次动作使用的方向基准，中途不随左摇杆改变
        self.samples = 0
        self._last_motion = 0.0
        self._last_mag = 0.0
        self._motion_ref_angle = 0.0
        self._release_since: Optional[float] = None
        self._path: List[Tuple[float, float, float]] = []
        self._last_path_t = -1e9
        self._pending: Optional[Failure] = None
        self._claimed = False
        self._turn_sign = 0

    # ------------------------------------------------------------------
    def _abort(self) -> None:
        """作废本次画弧，必须等摇杆回落才允许下一次。"""
        self.active = False
        self.armed = False
        self.acc = 0.0
        self._release_since = None
        self._turn_sign = 0

    def _release_failure(self, swept: float, elapsed_ms: float,
                         end_rel: float, end_ok: bool) -> Optional[Failure]:
        """松手了但没成功：说清楚差在哪儿。"""
        if swept < self.min_angle:
            return Failure(
                "too_short",
                f"转得不够：只转了 {swept:.0f}°"
                f"（需要 {self.min_angle:.0f}°~{self.max_angle:.0f}°）",
                elapsed_ms,
            )
        if self.end_targets and not end_ok:
            target = "/".join(f"{t:.0f}°" for t in self.end_targets)
            return Failure(
                "wrong_end",
                f"终点不对：停在相对 {end_rel:.0f}°"
                f"（应该回到 {target}±{self.end_tolerance:.0f}°）",
                elapsed_ms,
            )
        return None

    def update(self, frame: Frame) -> Optional[Hit]:
        mag = frame.rs_mag
        now = frame.now

        # 摇杆回落 -> 结束本次画弧；连续回中够久才重新武装。
        # 不能一低于 exit 就立刻 armed=True，否则动作结尾轻轻一抖就会被当成下一次起手。
        if mag < self.exit:
            was_active = self.active
            if was_active and self._claimed:
                elapsed_ms = (now - self.t0) * 1000.0
                # 松手时摇杆已经回中，这一帧的角度没有意义；
                # 用最后一次有效角度判断终点。
                end_rel = norm_deg(self.last_angle - self.base)
                self.end_rel = end_rel
                end_ok = (not self.end_targets
                          or any(angle_diff(end_rel, target) <= self.end_tolerance
                                 for target in self.end_targets))
                swept = abs(self.acc)
                if swept >= self.report_min_angle:
                    failure = self._release_failure(
                        swept, elapsed_ms, end_rel, end_ok)
                    if failure is not None:
                        self._emit(failure)
            self.active = False
            self.acc = 0.0
            self._turn_sign = 0
            if was_active:
                self.armed = False
            if self._release_since is None:
                self._release_since = now
            if (not self.armed
                    and (now - self._release_since) * 1000.0 >= self.release_hold_ms):
                self.armed = True
            return None
        self._release_since = None

        if not self.armed:
            return None

        if not self.active:
            if mag >= self.enter:
                self.active = True
                self.t0 = now
                self.acc = 0.0
                self.samples = 1
                self.start_angle = frame.rs_angle
                self.base = frame.facing if self.relative else 0.0
                self.start_rel = norm_deg(frame.rs_angle - self.base)
                self.end_rel = self.start_rel
                self.last_angle = frame.rs_angle
                self._last_motion = now
                self._last_mag = mag
                self._motion_ref_angle = frame.rs_angle
                self._turn_sign = 0
                self._path = [(0.0, frame.rs_angle, mag)]
                self._last_path_t = now
                self._claimed = (
                    self.start_target is None
                    or angle_diff(self.start_rel, self.start_target)
                    <= self.start_tolerance + self.claim_margin
                )
            return None

        # 累计旋转（走最短弧，天然处理 0°/360° 环绕）
        delta = signed_delta(self.last_angle, frame.rs_angle)
        self.acc += delta
        self.last_angle = frame.rs_angle
        self.samples += 1
        # 慢速但持续的旋转也要算"在动"：用累计角度而不是单帧角度判断，
        # 否则 250Hz 下每帧只转 1° 左右的慢弧会被误判成停住。
        if (angle_diff(self._motion_ref_angle, frame.rs_angle) >= self.motion_delta
                or abs(mag - self._last_mag) >= 0.05):
            self._last_motion = now
            self._motion_ref_angle = frame.rs_angle
        self._last_mag = mag

        elapsed_ms = (now - self.t0) * 1000.0
        if now - self._last_path_t >= 0.008 and len(self._path) < 64:
            self._path.append((elapsed_ms, frame.rs_angle, mag))
            self._last_path_t = now

        swept = abs(self.acc)

        # 检查顺序按"最能说明问题"排：起点 -> 方向 -> 转多了 -> 停住 -> 太慢 -> 太快。
        # 这些分支都会 abort，所以顺序只影响报告哪条原因，不影响是否触发。
        if (self.start_target is not None
                and angle_diff(self.start_rel, self.start_target) > self.start_tolerance):
            if self._claimed:
                self._emit(Failure(
                    "wrong_start",
                    f"起点不对：从相对 {self.start_rel:.0f}° 起手"
                    f"（{self._name}要求 {self.start_target:.0f}°"
                    f"±{self.start_tolerance:.0f}°）",
                    elapsed_ms,
                ))
            self._abort()
            return None

        # 转向符号要等真的转起来再锁定：刚推出去那一帧 acc 还是 0，
        # 直接比较会把它误判成"转向反了"。
        if self.direction and swept >= 5.0:
            if self._turn_sign == 0:
                self._turn_sign = 1 if self.acc > 0 else -1
            if self._turn_sign != self.direction:
                if self._claimed:
                    self._emit(Failure(
                        "wrong_direction",
                        f"转向反了：应该{self.direction_label}",
                        elapsed_ms,
                    ))
                self._abort()
                return None

        if swept > self.max_angle:
            if self._claimed:
                self._emit(Failure(
                    "overshoot",
                    f"转多了：累计 {swept:.0f}°（上限 {self.max_angle:.0f}°）",
                    elapsed_ms,
                ))
            self._abort()
            return None

        if (now - self._last_motion) * 1000.0 > self.idle_ms:
            if self._claimed and swept >= 5.0:
                self._emit(Failure(
                    "stalled",
                    f"中途停住了：超过 {self.idle_ms:.0f}ms 没转动",
                    elapsed_ms,
                ))
            self._abort()
            return None

        if elapsed_ms > self.max_ms:
            if self._claimed:
                self._emit(Failure(
                    "too_slow",
                    f"太慢了：用了 {elapsed_ms:.0f}ms（上限 {self.max_ms:.0f}ms）",
                    elapsed_ms,
                ))
            self._abort()
            return None

        self.end_rel = norm_deg(frame.rs_angle - self.base)
        end_ok = (not self.end_targets
                  or any(angle_diff(self.end_rel, target) <= self.end_tolerance
                         for target in self.end_targets))
        in_range = self.min_angle <= swept <= self.max_angle

        # 动作还没到最短时长，就已经转到位了 -> 太快，直接作废。
        # 不能只 return None 继续等：否则用户快速转完再停住，会在 min_duration 到点时误触发。
        if elapsed_ms < self.min_ms:
            if in_range and end_ok:
                if self._claimed:
                    self._emit(Failure(
                        "too_fast",
                        f"太快了：{elapsed_ms:.0f}ms 就转到位了"
                        f"（至少 {self.min_ms:.0f}ms）",
                        elapsed_ms,
                    ))
                self._abort()
            return None

        if not in_range or not end_ok:
            return None

        self.active = False
        self.armed = False
        self._turn_sign = 0
        summary = (f"旋转 {abs(self.acc):.0f}°"
                   f"（相对 {self.start_rel:.0f}°→{self.end_rel:.0f}°）")
        return Hit(elapsed_ms=elapsed_ms, detail=self._describe(),
                   summary=summary)

    # ------------------------------------------------------------------
    def _describe(self) -> str:
        turn = "顺时针" if self.acc > 0 else "逆时针"
        text = (
            f"右摇杆{turn} {abs(self.acc):.0f}° "
            f"(起始 {self.start_angle:.0f}° → 结束 {self.last_angle:.0f}°) "
            f"采样 {self.samples} 点"
        )
        if self.start_target is not None:
            text += f" 起点{self.start_rel:.0f}°(要求{self.start_target:.0f}°±{self.start_tolerance:.0f}°)"
        return text

    def path_detail(self) -> str:
        """把轨迹粗采样成一行文本，便于回看搓招路径。"""
        return " ".join(f"{a:.0f}°@{t:.0f}ms" for t, a, _ in self._path[:24])

    def reset(self) -> None:
        self.active = False
        self.armed = True
        self.acc = 0.0
        self._release_since = None
        self._last_motion = 0.0
        self._turn_sign = 0

    def abandon(self) -> None:
        self._pending = None
        self._abort()

    def status(self) -> str:
        # 只推杆不转圈时 acc 是 0，别显示"旋转中 0°"误导人
        if not self.active or abs(self.acc) < 5.0:
            return "待机"
        return f"旋转中 {abs(self.acc):.0f}° (目标 {self.min_angle:.0f}~{self.max_angle:.0f}°)"


# ---------------------------------------------------------------------------
# 方向点拨序列类
# ---------------------------------------------------------------------------

class SequenceDetector(Detector):
    """方向点拨序列识别。

    每一步可以是：
        "forward"                                      单一方向（点拨一下）
        ["left", "right"]                              任一方向
        {"direction": [...], "hold_ms": 500}           方向对了还要保持住

    hold_ms 用来区分"点拨"和"按住"——比如 FIFA 的 La Croqueta 需要按住侧向
    约半秒才算数，光推一下不算。
    """

    def __init__(self, skill: Skill):
        p = skill.params
        raw_steps = p.get("steps") or []
        if not raw_steps:
            raise ValueError(f"动作 {skill.name!r} 是 sequence 类型，params.steps 不能为空")

        self.steps: List[Step] = [parse_step(s) for s in raw_steps]

        self.tolerance = float(p.get("tolerance_deg", 35.0))
        self.enter = float(p.get("enter_threshold", 0.65))
        self.release = float(p.get("release_threshold", 0.35))
        if self.release >= self.enter:
            self.release = max(0.0, self.enter - 0.15)
        self.max_ms = float(p.get("max_duration_ms", 700.0))
        self.min_ms = float(p.get("min_duration_ms", 300.0))
        self.idle_ms = float(p.get("idle_timeout_ms", 250.0))
        self.motion_delta = float(p.get("motion_min_delta_deg", 2.0))
        if self.max_ms <= self.min_ms:
            raise ValueError(
                f"动作 {skill.name!r}: max_duration_ms ({self.max_ms}) 必须大于 "
                f"min_duration_ms ({self.min_ms})"
            )
        self.require_neutral = bool(p.get("require_neutral_between_steps", True))
        self.relative = skill.relative_to_ls
        self._name = skill.name.split(" (")[0]

        # 触发之后必须"真正松手"一段时间才允许再次触发。
        # 只判 mag < release 不够：摇杆在阈值附近抖一下（甚至只有一帧）就会重新武装，
        # 表现出来就是"按住不放却一直震"。
        self.release_hold_ms = float(p.get("release_hold_ms", 150.0))

        self.index = 0
        self.t0: Optional[float] = None    # None = 当前没有进行中的序列
        self.neutral = True
        self._armed = True                 # False = 已触发过，等一次"真正的松手"
        self._release_since: Optional[float] = None
        self.last_base = 0.0
        self._hold_since: Optional[float] = None
        self._now = 0.0
        self._last_motion = 0.0
        self._last_angle = 0.0
        self._last_mag = 0.0
        self._have_last = False
        # 判断"还在动"要和几帧前的参考角度比：250Hz 下慢速画弧每帧只走
        # 0.7°，拿相邻两帧比会一直小于 motion_delta，被误判成停住。
        self._motion_ref_angle = 0.0
        self._pending: Optional[Failure] = None
        self._best_hold_ms = 0.0
        # 每一步匹配期间的相对角度统计：最低 / 最高 / 总和 / 样本数
        n = len(self.steps)
        self._step_lo: List[Optional[float]] = [None] * n
        self._step_hi: List[Optional[float]] = [None] * n
        self._step_sum: List[float] = [0.0] * n
        self._step_n: List[int] = [0] * n
        self._facing = 0.0
        self._buttons: FrozenSet[str] = frozenset()
        self._required = tuple(skill.required_buttons)
        self._button_mode = skill.button_mode

    # ------------------------------------------------------------------
    def _match(self, rel_angle: float, step: Step) -> bool:
        return any(angle_diff(rel_angle, target) <= self.tolerance
                   for target in step.angles)

    def _reset_metrics(self) -> None:
        n = len(self.steps)
        self._step_lo = [None] * n
        self._step_hi = [None] * n
        self._step_sum = [0.0] * n
        self._step_n = [0] * n

    def _note_angle(self, index: int, angle: float) -> None:
        if not (0 <= index < len(self.steps)):
            return
        lo = self._step_lo[index]
        hi = self._step_hi[index]
        self._step_lo[index] = angle if lo is None else min(lo, angle)
        self._step_hi[index] = angle if hi is None else max(hi, angle)
        self._step_sum[index] += angle
        self._step_n[index] += 1

    def _step_angle_text(self, index: int) -> Optional[str]:
        n = self._step_n[index]
        if not n:
            return None
        lo = float(self._step_lo[index])
        hi = float(self._step_hi[index])
        avg = self._step_sum[index] / n
        if hi - lo < 3.0:
            return f"{avg:.0f}°"
        return f"{lo:.0f}°~{hi:.0f}°（平均 {avg:.0f}°）"

    def _summary(self, hold_ms: float) -> str:
        parts: List[str] = []
        for i, step in enumerate(self.steps):
            angle = self._step_angle_text(i)
            if angle is None:
                continue
            text = f"{step.label()} {angle}"
            if step.hold_ms > 0 and i == len(self.steps) - 1:
                text += f" 保持 {hold_ms:.0f}ms"
            parts.append(text)
        text = " · ".join(parts)
        return f"相对朝向 {text}" if text else ""

    def _clear_progress(self) -> None:
        self.index = 0
        self.t0 = None
        self._hold_since = None
        self._best_hold_ms = 0.0
        self._reset_metrics()

    def _abort(self) -> None:
        """作废当前序列，必须回中够久才允许重新开始。"""
        self._clear_progress()
        self.neutral = False
        self._armed = False
        self._release_since = None
        self._last_motion = 0.0

    def _abandon_failure(self, now: float, timed_out: bool = False) -> Optional[Failure]:
        """序列还没做完就被放弃：给出原因（调用前 t0 / index 必须还在）。"""
        if self.t0 is None:
            return None
        elapsed_ms = (now - self.t0) * 1000.0
        step = self.steps[min(self.index, len(self.steps) - 1)]
        if timed_out:
            return Failure(
                "too_slow",
                f"太慢了：用了 {elapsed_ms:.0f}ms（上限 {self.max_ms:.0f}ms）",
                elapsed_ms,
            )
        if step.hold_ms > 0 and self._best_hold_ms > 0:
            return Failure(
                "hold_short",
                f"保持不够：只保持了 {self._best_hold_ms:.0f}ms"
                f"（需要 {step.hold_ms:.0f}ms）",
                elapsed_ms,
            )
        if self.index > 0:
            done = " → ".join(s.label() for s in self.steps[:self.index])
            return Failure(
                "incomplete",
                f"没做完：只做到第 {self.index}/{len(self.steps)} 步"
                f"（{done} → 还差 {step.label()}）",
                elapsed_ms,
            )
        return None

    def on_idle(self) -> None:
        """真正静置一段时间后：把没做完的尝试记一笔，再清空并允许起手。"""
        failure = self._abandon_failure(self._now)
        if failure is not None:
            self._emit(failure)
        self._clear_progress()
        self.neutral = True
        self._armed = True
        self._release_since = None
        self._last_motion = 0.0
        self._have_last = False

    def update(self, frame: Frame) -> Optional[Hit]:
        now = frame.now
        self._now = now
        self._facing = frame.facing
        self._buttons = frame.buttons
        mag = frame.rs_mag

        # 记录右摇杆是否发生了有意义的变化。动作之间停顿太久时，
        # 这个计时器会把没做完的序列清掉，防止"上一个动作的尾巴"接成下一个动作。
        moved = (
            not self._have_last
            or angle_diff(self._motion_ref_angle, frame.rs_angle) >= self.motion_delta
            or abs(self._last_mag - mag) >= 0.06
        )
        if moved:
            self._motion_ref_angle = frame.rs_angle
        self._last_angle = frame.rs_angle
        self._last_mag = mag
        self._have_last = True

        if self.t0 is not None:
            base = self.last_base if self.relative else 0.0
            rel_angle = norm_deg(frame.rs_angle - base)
            step = self.steps[min(self.index, len(self.steps) - 1)]
            holding = (
                step.hold_ms > 0
                and mag >= self.enter
                and self._match(rel_angle, step)
            )
            if mag >= self.enter and self._match(rel_angle, step):
                self._note_angle(self.index, rel_angle)
            if holding and self._hold_since is not None:
                self._best_hold_ms = max(
                    self._best_hold_ms, (now - self._hold_since) * 1000.0)
            if holding or moved:
                self._last_motion = now

            timed_out = (now - self.t0) * 1000.0 > self.max_ms
            stalled = (now - self._last_motion) * 1000.0 > self.idle_ms
            if timed_out or stalled:
                failure = self._abandon_failure(now, timed_out=timed_out)
                if failure is not None:
                    self._emit(failure)
                self._abort()
                # 还推着摇杆就先不继续判，必须回中之后重新起手
                if mag >= self.release:
                    return None

        if mag < self.release:
            if self._release_since is None:
                self._release_since = now
            # 回中：允许下一步
            self.neutral = True
            self._hold_since = None
            # 已经触发过的动作，要连续松开够久才重新武装
            if (not self._armed
                    and (now - self._release_since) * 1000.0 >= self.release_hold_ms):
                self._armed = True
            return None
        self._release_since = None

        if mag < self.enter:
            return None
        if not self._armed:
            return None
        if self.require_neutral and not self.neutral:
            return None

        # 序列一旦开始，方向基准就固定为起手时的左摇杆朝向；
        # 中途左摇杆怎么动都不再改变判定基准，避免动作中途"换了参照系"。
        facing_now = frame.facing if self.relative else 0.0
        base = self.last_base if self.t0 is not None else facing_now
        rel_angle = norm_deg(frame.rs_angle - base)
        step = self.steps[self.index]

        if not self._match(rel_angle, step):
            self._hold_since = None
            # 没匹配上当前这一步，但如果命中了第一步，说明是一次新的起手
            # （例如想搓"前-后"却先搓成了"前-前-后"），允许从头重来
            if self.index > 0:
                rel_first = norm_deg(frame.rs_angle - facing_now)
                if self._match(rel_first, self.steps[0]):
                    self.index = 1
                    self.t0 = now
                    self.last_base = facing_now
                    self.neutral = False
                    self._last_motion = now
                    self._motion_ref_angle = frame.rs_angle
                    self._hold_since = None
                    self._best_hold_ms = 0.0
            return None

        # 方向对了，序列从这一刻开始计时（这样耗时里会包含保持时间）
        if self.t0 is None:
            self.t0 = now
            self.last_base = base
            self._last_motion = now
            self._motion_ref_angle = frame.rs_angle
            self._best_hold_ms = 0.0
            self._reset_metrics()
            self._note_angle(self.index, rel_angle)

        # 如果这一步要求保持，先攒够时间再说
        if step.hold_ms > 0:
            if self._hold_since is None:
                self._hold_since = now
                self._best_hold_ms = 0.0
            held_ms = (now - self._hold_since) * 1000.0
            self._best_hold_ms = max(self._best_hold_ms, held_ms)
            if held_ms < step.hold_ms:
                return None

        # 最后一步如果整体太快，直接作废，不能等时长到了再补触发
        if self.index == len(self.steps) - 1:
            elapsed_ms = (now - self.t0) * 1000.0
            if elapsed_ms < self.min_ms:
                self._emit(Failure(
                    "too_fast",
                    f"太快了：整个动作只用了 {elapsed_ms:.0f}ms"
                    f"（至少 {self.min_ms:.0f}ms）",
                    elapsed_ms,
                ))
                self._abort()
                return None

        self.index += 1
        self.neutral = False
        # 保持时长要在清零前取出来，否则成功摘要里永远是 0ms
        fired_hold_ms = self._best_hold_ms if step.hold_ms > 0 else 0.0
        self._hold_since = None
        self._best_hold_ms = 0.0
        self._last_motion = now

        if self.index >= len(self.steps):
            elapsed_ms = (now - self.t0) * 1000.0
            detail = self._describe()
            summary = self._summary(fired_hold_ms)
            self.index = 0
            self.t0 = None
            self._armed = False          # 必须等一次"真正的松手"才能再触发
            self._release_since = None
            self._reset_metrics()
            return Hit(elapsed_ms=elapsed_ms, detail=detail, summary=summary)
        return None

    # ------------------------------------------------------------------
    def _describe(self) -> str:
        parts = []
        for step in self.steps:
            text = step.label()
            if step.hold_ms > 0:
                text += f"(保持{step.hold_ms:.0f}ms)"
            parts.append(text)
        scope = f"相对左摇杆朝向(基准 {self.last_base:.0f}°)" if self.relative else "屏幕绝对方向"
        return f"序列 [{' → '.join(parts)}] {scope} 容错 ±{self.tolerance:.0f}°"

    def reset(self) -> None:
        """修饰键松开时作废进度。

        这里**不能**动 neutral：它描述的是"摇杆位置"，跟按键无关。
        如果把 neutral 置回 True，摇杆明明还推着、只是 L1 抖了一帧，
        就会被当成"已经回中"，于是按住不放就反复触发。

        但 _armed 要置回 True。修饰键已经松开了，说明上一次动作结束，
        用户完全可能"先松 L1、再回中摇杆"——如果这里不解除武装，
        下一次按住 L1 推杆会被当成上一次动作的余波，永远触发不了。
        neutral 仍然是 False，所以摇杆还推着时不会立刻重复触发。
        """
        if self.t0 is not None and self._hold_since is not None:
            failure = self._abandon_failure(self._now)
            if failure is not None:
                self._emit(failure)
        self.index = 0
        self.t0 = None
        self._hold_since = None
        self._best_hold_ms = 0.0
        self._armed = True

    def abandon(self) -> None:
        self._pending = None
        self._abort()

    def observe(self, frame: Frame) -> None:
        self._now = frame.now
        self._facing = frame.facing
        self._buttons = frame.buttons
        self._last_angle = frame.rs_angle
        self._last_mag = frame.rs_mag
        self._have_last = True

    def _modifier_held(self) -> bool:
        if not self._required:
            return True
        if self._button_mode == "any":
            return any(b in self._buttons for b in self._required)
        return all(b in self._buttons for b in self._required)

    def _modifier_label(self) -> str:
        # 配置里写的是 L1/R1，规范化后是 LB/RB；提示里说回用户熟悉的叫法
        alias = {"LB": "L1", "RB": "R1", "LT": "L2", "RT": "R2"}
        return "/".join(alias.get(b, b) for b in self._required)

    def status(self) -> str:
        if self.index == 0 and self.t0 is None:
            # 还没起手：把"卡在哪一步"直接显示出来，识别不到时好排查。
            # 只对带修饰键的动作做提示——否则随便推杆时每张卡片都在喊"方向不对"。
            # _armed=False 说明刚做完一个，等松手，不要提示。
            if not (self._required and self._armed and self._last_mag >= self.enter):
                return "待机"
            base = self._facing if self.relative else 0.0
            rel = norm_deg(self._last_angle - base)
            first = self.steps[0]
            matched = self._match(rel, first)
            if not self._modifier_held():
                if matched:
                    return f"方向对了，要按住 {self._modifier_label()}"
                return "待机"
            if self.require_neutral and not self.neutral:
                return "先松开右摇杆回中"
            if not matched:
                return (f"方向不对：当前相对 {rel:.0f}°，"
                        f"要 {first.label()}")
            return "待机"
        step = self.steps[min(self.index, len(self.steps) - 1)]
        if step.hold_ms > 0 and self._hold_since is not None:
            held = (self._now - self._hold_since) * 1000.0
            return (f"保持 {step.label()} {held:.0f}/{step.hold_ms:.0f}ms")
        return f"已匹配 {self.index}/{len(self.steps)}，等 {step.label()}"


# ---------------------------------------------------------------------------

class TapDetector(Detector):
    """按键双击类：按住修饰键，在时间窗口内按两下同一个键。

    典型用法是绿色搓射：按住 RB（或 RT），第一下 X 之后 400~600ms 再按
    第二下 X。整个过程修饰键不能松开。按钮判定和右摇杆完全无关，所以 on_idle() 不能
    清进度——引擎在右摇杆静止时会定期调用 on_idle()，而做这个动作时右摇杆
    通常一直回中。
    """

    def __init__(self, skill: Skill):
        p = skill.params
        self.button = canonical_button(p.get("button", "X"))
        self.required = tuple(skill.required_buttons)
        self.min_ms = float(p.get("min_interval_ms", 400.0))
        self.max_ms = float(p.get("max_interval_ms", 600.0))
        if self.min_ms < 0:
            raise ValueError(f"动作 {skill.name!r}: min_interval_ms 不能是负数")
        if self.max_ms <= self.min_ms:
            raise ValueError(
                f"动作 {skill.name!r}: max_interval_ms ({self.max_ms:.0f}) "
                f"必须大于 min_interval_ms ({self.min_ms:.0f})"
            )
        self.grace_ms = max(0.0, float(p.get("timeout_grace_ms", 150.0)))
        self.release_hold_ms = max(0.0, float(p.get("release_hold_ms", 120.0)))

        self._now = 0.0
        self._t0: Optional[float] = None       # 第一下按下的时刻
        self._armed = True                     # False = 等按键真正松开再允许重试
        self._prev_pressed = False
        self._have_prev = False
        self._release_since: Optional[float] = None
        self._pending: Optional[Failure] = None

    # ------------------------------------------------------------------
    def set_modifier(self, button: str) -> None:
        """切换要按住的修饰键（绿色搓射的 RB / RT）。

        配置里 ``required_button`` 是默认值，用户在界面上切换后立即生效；
        正在等待第二下的进度会被作废，避免用旧键的起手去配新键的第二次按下。
        """
        button = canonical_button(button)
        self.required = (button,)
        self._pending = None
        self._t0 = None
        self._release_since = None
        self._armed = not self._prev_pressed

    def _required_label(self) -> str:
        return "/".join(self.required) if self.required else "修饰键"

    def _clear(self, armed: bool) -> None:
        self._t0 = None
        self._release_since = None
        self._armed = armed

    def observe(self, frame: Frame) -> None:
        # 按住别的修饰键 / 没按 RB 时引擎只调 observe + reset，
        # 这里仍然要记录按键状态，否则重新按住 RB 的那一帧会把"一直按着 X"
        # 误判成一次新的按下。
        self._now = frame.now
        self._prev_pressed = self.button in frame.buttons
        self._have_prev = True

    def reset(self) -> None:
        # 引擎在 required_button 松开时调用 reset()。如果正做到一半，
        # 说明 RB 中途松了，给一次明确提示；已经结束的尝试不再重复报。
        if self._t0 is not None:
            elapsed = max(0.0, (self._now - self._t0) * 1000.0)
            self._emit(Failure(
                "hold_short",
                f"保持不够：中途松开了 {self._required_label()}"
                f"（两下 {self.button} 之间要一直按住）",
                elapsed,
            ))
        self._t0 = None
        self._release_since = None
        # 只有按键已经松开，才允许下一次起手
        self._armed = not self._prev_pressed

    def on_idle(self) -> None:
        # 右摇杆静止与按键动作无关，不能在这里作废进度。
        pass

    def abandon(self) -> None:
        # 这段轨迹属于别的动作（或按住了别的修饰键）：静默丢弃，不报错。
        self._pending = None
        self._t0 = None
        self._release_since = None
        self._armed = not self._prev_pressed

    # ------------------------------------------------------------------
    def update(self, frame: Frame) -> Optional[Hit]:
        now = frame.now
        self._now = now
        pressed = self.button in frame.buttons
        if not self._have_prev:
            self._prev_pressed = pressed
            self._have_prev = True
            return None

        rising = pressed and not self._prev_pressed
        mods_ok = all(b in frame.buttons for b in self.required)
        if not mods_ok:
            # 正常情况下引擎不会在这里调用 update()；防御性处理。
            self._prev_pressed = pressed
            return None

        # 成功/失败之后，必须真正松开按键并保持一小段时间，才允许下一次。
        if not self._armed:
            if not pressed:
                if self._release_since is None:
                    self._release_since = now
                elif (now - self._release_since) * 1000.0 >= self.release_hold_ms:
                    self._armed = True
                    self._release_since = None
            else:
                self._release_since = None
            self._prev_pressed = pressed
            return None

        if self._t0 is None:
            if rising:
                self._t0 = now
                self._release_since = None
            self._prev_pressed = pressed
            return None

        interval_ms = (now - self._t0) * 1000.0

        if rising:
            # 第二下：只看两下按下的时间间隔
            if self.min_ms <= interval_ms <= self.max_ms:
                summary = f"两下 {self.button} 间隔 {interval_ms:.0f}ms"
                detail = (f"{summary}（{self._required_label()} 全程按住）")
                self._clear(armed=False)
                self._prev_pressed = pressed
                return Hit(elapsed_ms=interval_ms, detail=detail,
                           summary=summary)

            if interval_ms < self.min_ms:
                self._emit(Failure(
                    "too_fast",
                    f"太快了：两下 {self.button} 只隔了 {interval_ms:.0f}ms"
                    f"（需要 {self.min_ms:.0f}~{self.max_ms:.0f}ms）",
                    interval_ms,
                ))
            else:
                self._emit(Failure(
                    "too_slow",
                    f"太慢了：两下 {self.button} 隔了 {interval_ms:.0f}ms"
                    f"（需要 {self.min_ms:.0f}~{self.max_ms:.0f}ms）",
                    interval_ms,
                ))
            self._clear(armed=False)
            self._prev_pressed = pressed
            return None

        # 一直没有第二下：超过上限再给一点宽限就报"太慢"，不能一直挂着
        if interval_ms > self.max_ms + self.grace_ms:
            self._emit(Failure(
                "too_slow",
                f"太慢了：等了 {interval_ms:.0f}ms 还没有第二下 {self.button}"
                f"（需要在 {self.min_ms:.0f}~{self.max_ms:.0f}ms 内）",
                interval_ms,
            ))
            self._clear(armed=False)

        self._prev_pressed = pressed
        return None

    # ------------------------------------------------------------------
    def status(self) -> str:
        if self._t0 is None:
            return "待机"
        elapsed = max(0.0, (self._now - self._t0) * 1000.0)
        return (f"已按第一下 {self.button}，等第二下 "
                f"{elapsed:.0f}ms（目标 {self.min_ms:.0f}~{self.max_ms:.0f}）")


# ---------------------------------------------------------------------------

def build_detector(skill: Skill) -> Detector:
    if skill.kind == "arc":
        return ArcDetector(skill)
    if skill.kind == "sequence":
        return SequenceDetector(skill)
    if skill.kind == "taps":
        return TapDetector(skill)
    raise ValueError(f"动作 {skill.name!r} 的 type 未知: {skill.kind!r}")
