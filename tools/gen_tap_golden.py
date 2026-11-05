#!/usr/bin/env python3
"""从桌面版 Python 参考实现重新推导 tap 检测器黄金夹具。

    python3 tools/gen_tap_golden.py            # 生成 / 刷新夹具
    python3 tools/gen_tap_golden.py --check    # 只比对，不写盘

夹具是 GDScript tap 回放套件的唯一期望来源，所以它必须是**生成物**：手改一份
JSON 让测试变绿，等于把「与 Python 对等」偷换成「与手改后的自己一致」。
``--check`` 重新推导后逐字节比较，不一致就打印首个差异行并返回 1，且绝不写盘。

为什么期望值必须跑参考实现：``desktop/padskills/detectors.py`` 的 ``TapDetector``
是唯一规格书；生成器只负责把 250 Hz 时间轴喂给它，记录每一次 ``Hit`` 与每一次
``pop_failure()``。任何「我以为是 450ms」的手写期望都可能与实现的取整、边界、
分支顺序不符。

为什么引擎分支也要照抄：修饰键不满足时，引擎调用 ``observe()`` **然后**
``reset()``（desktop/padskills/engine.py:273-279）；顺序反了 ``reset()`` 就会用
上一帧的按键状态算 elapsed，``hold_short`` 的实测值会与移动端分叉。

为什么可以安全 import ``padskills.detectors``：``input_source.py`` 的 pygame 是
函数内导入，模块级只依赖标准库；``sys.path`` 以脚本位置为锚注入 ``desktop/``，
不依赖调用方的 cwd。
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import sys
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_REPO_ROOT / "desktop"))

from padskills.config import parse_config  # noqa: E402
from padskills.detectors import Frame, TapDetector  # noqa: E402
from padskills.engine import Engine  # noqa: E402
from padskills.input_source import GamepadSource, PadState, canonical_button  # noqa: E402
from padskills.rumble import RumbleEngine  # noqa: E402

STEP_MS = 4
HZ = 250
SKILL_NAME = "绿色搓射 Green Finesse"

CONFIG_REL = Path("shared") / "skills_config.json"
FIXTURE_REL = Path("mobile") / "tests" / "fixtures" / "tap_golden.json"

# 四个摘要一起进夹具：detectors 是本文件的规格书，engine 是 04-02 运行时期望的来源，
# config 决定 Skill 字段，skills_config 是真源。任何一份变了都必须重新生成夹具。
SOURCE_RELS = {
    "detectors": Path("desktop") / "padskills" / "detectors.py",
    "engine": Path("desktop") / "padskills" / "engine.py",
    "config": Path("desktop") / "padskills" / "config.py",
    "skills_config": CONFIG_REL,
}

# 时间轴用「变化点 + 结束时刻」描述：每个变化点都落在 4ms 网格上，其余帧由
# _build_frames 全量展开。按键集合在这里写清楚，拼字符串时统一 sorted()。
#
# 窗口边界（min/max 两端包含）必须各有一条用例；超时是严格大于，所以
# det_too_slow_boundary_750 的尾巴停在 interval=748 —— 4ms 网格上取不到 750，
# 而 752 那条由 det_too_slow_no_second 证明「超过才报」。
#
# 同理，4ms 网格上的间隔只能是 4 的整数倍，取不到计划里写的 450：
# det_success_mid_450 / det_set_modifier_rt_success 用网格内最近的 448（t0=100,
# 第二下 548）。id 保留计划里的名字以便追溯，语义仍是「窗口内部的成功」。
CASES = (
    # 1. 窗口下端包含：第二下正好 400ms。
    {
        "id": "det_success_min_400",
        "modifier": "RB",
        "button": "X",
        "end_ms": 508,
        "changes": (
            (0, ()),
            (4, ("RB",)),
            (100, ("RB", "X")),
            (104, ("RB",)),
            (500, ("RB", "X")),
            (504, ("RB",)),
        ),
    },
    # 2. 窗口内部的成功（计划写 450，网格上取 448）。
    {
        "id": "det_success_mid_450",
        "modifier": "RB",
        "button": "X",
        "end_ms": 560,
        "changes": (
            (0, ()),
            (4, ("RB",)),
            (100, ("RB", "X")),
            (104, ("RB",)),
            (548, ("RB", "X")),
            (552, ("RB",)),
        ),
    },
    # 3. 窗口上端包含：第二下正好 600ms。
    {
        "id": "det_success_max_600",
        "modifier": "RB",
        "button": "X",
        "end_ms": 708,
        "changes": (
            (0, ()),
            (4, ("RB",)),
            (100, ("RB", "X")),
            (104, ("RB",)),
            (700, ("RB", "X")),
            (704, ("RB",)),
        ),
    },
    # 4. 比窗口下限快：too_fast。
    {
        "id": "det_too_fast_300",
        "modifier": "RB",
        "button": "X",
        "end_ms": 408,
        "changes": (
            (0, ()),
            (4, ("RB",)),
            (100, ("RB", "X")),
            (104, ("RB",)),
            (400, ("RB", "X")),
            (404, ("RB",)),
        ),
    },
    # 5. 第二下存在但太慢：走 rising 的 too_slow 分支，不是超时分支。
    {
        "id": "det_too_slow_second_700",
        "modifier": "RB",
        "button": "X",
        "end_ms": 808,
        "changes": (
            (0, ()),
            (4, ("RB",)),
            (100, ("RB", "X")),
            (104, ("RB",)),
            (800, ("RB", "X")),
            (804, ("RB",)),
        ),
    },
    # 6. 一直没有第二下：首个 interval > 750 的帧是 852（752ms）。
    {
        "id": "det_too_slow_no_second",
        "modifier": "RB",
        "button": "X",
        "end_ms": 900,
        "changes": (
            (0, ()),
            (4, ("RB",)),
            (100, ("RB", "X")),
            (104, ("RB",)),
        ),
    },
    # 7. 超时边界：尾巴停在 interval=748（网格上取不到 750），不报任何失败。
    {
        "id": "det_too_slow_boundary_750",
        "modifier": "RB",
        "button": "X",
        "end_ms": 848,
        "changes": (
            (0, ()),
            (4, ("RB",)),
            (100, ("RB", "X")),
            (104, ("RB",)),
        ),
    },
    # 8. 修饰键中途松开：hold_short 由 reset() 产出，elapsed 用上一帧的 _now。
    {
        "id": "det_hold_short_modifier_released",
        "modifier": "RB",
        "button": "X",
        "end_ms": 308,
        "changes": (
            (0, ()),
            (4, ("RB",)),
            (100, ("RB", "X")),
            (300, ("X",)),
        ),
    },
    # 9. 第一下按 RB，随后换 RT 再按第二下：RB 撤离触发 hold_short，不产 Hit。
    {
        "id": "det_modifier_switch_rb_to_rt",
        "modifier": "RB",
        "button": "X",
        "end_ms": 608,
        "changes": (
            (0, ()),
            (4, ("RB",)),
            (100, ("RB", "X")),
            (300, ("X",)),
            (304, ("RT", "X")),
            (500, ("RT",)),
            (604, ("RT", "X")),
        ),
    },
    # 10. set_modifier("RT") 在首帧之前调用：证明换修饰键后判定跟着换。
    {
        "id": "det_set_modifier_rt_success",
        "set_modifier": "RT",
        "modifier": "RB",
        "button": "X",
        "end_ms": 560,
        "changes": (
            (0, ()),
            (4, ("RT",)),
            (100, ("RT", "X")),
            (104, ("RT",)),
            (548, ("RT", "X")),
            (552, ("RT",)),
        ),
    },
    # 11. 首帧 X 已按住，之后才按 RB：observe 守卫让「一直按着」不算 rising。
    {
        "id": "det_first_frame_held_x",
        "modifier": "RB",
        "button": "X",
        "end_ms": 200,
        "changes": (
            (0, ("X",)),
            (100, ("RB", "X")),
        ),
    },
    # 12. 命中后 40ms 再按被 _armed 挡住；松开满 120ms 后重新起手，第二段再 Hit。
    {
        "id": "det_release_hold_gate",
        "modifier": "RB",
        "button": "X",
        "end_ms": 1104,
        "changes": (
            (0, ()),
            (4, ("RB",)),
            (100, ("RB", "X")),
            (104, ("RB",)),
            (500, ("RB", "X")),
            (504, ("RB",)),
            (540, ("RB", "X")),
            (544, ("RB",)),
            (700, ("RB", "X")),
            (704, ("RB",)),
            (1100, ("RB", "X")),
            (1104, ("RB",)),
        ),
    },
)


# 运行时用例：驱动 `Engine._tick`（不是 `Engine.run()` —— 那是 250 Hz 墙钟循环）。
#
# 右摇杆恒回中是本阶段移动端的范围收缩，正好让 Python 引擎的手势锁在
# `gesture_release_ms`（150 ms）后自动解锁；rt_gesture_lock / rt_release_hold_rearm
# 依赖这一条。所有变化点与结束时刻都必须落在 4 ms 网格上（552 / 556 / 680 / 700 /
# 900 / 1352 都能被 4 整除），不允许出现 550 / 554 / 698 / 1350 这类偏离网格的写法。
#
# rt_gesture_lock 的时间线推导（用它说明「锁被写漏必然偏离 2 条」）：
#   552 命中 → 556 松 X，锁从这一帧起算 → 708 是 556+150=706 之后的首个网格帧，解锁；
#   680 / 700 那段「第一下 + 20ms 后第二下」因为在锁定期内，检测器完全没看到；
#   解锁后检测器才第一次看到 X 已松开，重新武装要 120 ms（828）；
#   合法一发在 900 / 1352（间隔 452），恰好 2 条 ok。
#   若锁被写漏：556 起算的松开到 676 就重新武装，680 的按下会建立 _t0，
#   700 的第二下间隔 20ms 必然多出一条 too_fast。
RUNTIME_CASES = (
    # 1. 两发，每发内两下 X 间隔 500 ms，发与发之间留 700 ms 空档。
    {
        "id": "rt_two_shots_500",
        "end_ms": 1820,
        "changes": (
            (0, ()),
            (4, ("RB",)),
            (100, ("RB", "X")),
            (104, ("RB",)),
            (600, ("RB", "X")),
            (604, ("RB",)),
            (1304, ("RB", "X")),
            (1308, ("RB",)),
            (1804, ("RB", "X")),
            (1808, ("RB",)),
        ),
    },
    # 2. 发与发之间留 1000 ms 空档：成功标准 5 的「快速连做两次」上界。
    {
        "id": "rt_two_shots_1000",
        "end_ms": 2120,
        "changes": (
            (0, ()),
            (4, ("RB",)),
            (100, ("RB", "X")),
            (104, ("RB",)),
            (600, ("RB", "X")),
            (604, ("RB",)),
            (1604, ("RB", "X")),
            (1608, ("RB",)),
            (2104, ("RB", "X")),
            (2108, ("RB",)),
        ),
    },
    # 3. 手势锁：锁定期内一段「本来会报 too_fast」的按压不许产出第三条判定。
    {
        "id": "rt_gesture_lock",
        "end_ms": 1372,
        "changes": (
            (0, ()),
            (4, ("RB",)),
            (100, ("RB", "X")),
            (104, ("RB",)),
            (552, ("RB", "X")),
            (556, ("RB",)),
            (680, ("RB", "X")),
            (684, ("RB",)),
            (700, ("RB", "X")),
            (704, ("RB",)),
            (900, ("RB", "X")),
            (904, ("RB",)),
            (1352, ("RB", "X")),
            (1356, ("RB",)),
        ),
    },
    # 4. 重新武装：「锁满前」与「锁满后但未武装」各一次 rising 按压都被挡住，
    #    之后再做一发合法 400–600。这条只证明重新武装，手势锁由第 3 条单独证明。
    {
        "id": "rt_release_hold_rearm",
        "end_ms": 1520,
        "changes": (
            (0, ()),
            (4, ("RB",)),
            (100, ("RB", "X")),
            (104, ("RB",)),
            (552, ("RB", "X")),
            (556, ("RB",)),
            (680, ("RB", "X")),
            (684, ("RB",)),
            (800, ("RB", "X")),
            (804, ("RB",)),
            (1000, ("RB", "X")),
            (1004, ("RB",)),
            (1500, ("RB", "X")),
            (1504, ("RB",)),
        ),
    },
    # 5. 一次尝试只一条判定：第一下之后松开 RB → 恰好一条 hold_short，
    #    其后的 20 帧（300→380）不许再冒出第二条。
    {
        "id": "rt_one_verdict_per_attempt",
        "end_ms": 380,
        "changes": (
            (0, ()),
            (4, ("RB",)),
            (100, ("RB", "X")),
            (104, ("RB",)),
            (300, ("X",)),
        ),
    },
    # 6. 布局硬门：移动端独有结构，期望**直接写空**（Python 引擎没有这个概念，
    #    它的时间线本来会命中一次 448ms，伪称来自参考实现就是造假）。
    {
        "id": "rt_layout_gate_blocks",
        "layout_confirmed": False,
        "end_ms": 560,
        "changes": (
            (0, ()),
            (4, ("RB",)),
            (100, ("RB", "X")),
            (104, ("RB",)),
            (548, ("RB", "X")),
            (552, ("RB",)),
        ),
    },
)

# 两个分支各有一条 reachable 的合成时序在 GDScript 侧（不占夹具）：
# 真实配置的 450 ms 下，手势锁 150 + 重新武装 120 + 最短间隔 400 = 670 ms，
# 所以「第二发命中在第一发后 670~870 ms」必然先越过逐动作冷却 450，却还没到
# global_cooldown_ms = 1000。同一段时间线换 cooldown_ms = 900 就落到逐动作分支。


class _NullSource(GamepadSource):
    """只用于构造引擎；生成器直接手工喂 `_tick`，`poll()` 永不被调用。"""

    name = "空手柄"
    layout_source = "测试"

    def poll(self) -> PadState:
        return PadState()


class _CollectingEngine(Engine):
    """把**全部** Outcome 收集起来；只看 `last_outcome` 会漏掉中间结果。"""

    collected: list

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.collected = []

    def _record(self, active, ok, code, message, elapsed_ms, now, detail=""):
        super()._record(active, ok, code, message, elapsed_ms, now, detail)
        self.collected.append(self.last_outcome)


def repo_root() -> Path:
    """仓库根目录：以脚本位置（tools/ 的上一级）为锚，不依赖调用方的 cwd。"""
    return _REPO_ROOT


def fixture_path(root: Path) -> Path:
    return root / FIXTURE_REL


def _sha256(root: Path, rel: Path) -> str:
    return hashlib.sha256((root / rel).read_bytes()).hexdigest()


def _load_config(root: Path):
    """从唯一真源加载整份配置：不写第二份配置副本。

    runtime 用例要用到 `global_cooldown_ms` 与 `input.gesture_release_ms`，
    所以这里返回 AppConfig，而不是只挑出 Skill。
    """
    data = json.loads((root / CONFIG_REL).read_text(encoding="utf-8"))
    return parse_config(data, root / CONFIG_REL)


def _pick_skill(cfg):
    for skill in cfg.skills:
        if skill.name == SKILL_NAME:
            return skill
    raise SystemExit(f"✗ 配置里找不到动作 {SKILL_NAME!r}：{CONFIG_REL.as_posix()}")


def _build_frames(case: dict) -> list:
    """把变化点展开成逐帧全量时间轴（步长 4ms，t_ms 用 int）。"""
    case_id = case["id"]
    end_ms = int(case["end_ms"])
    if end_ms % STEP_MS:
        raise SystemExit(f"✗ {case_id}: end_ms 必须是 {STEP_MS}ms 的整数倍")
    changes = list(case["changes"])
    for t_ms, _ in changes:
        if int(t_ms) % STEP_MS:
            raise SystemExit(f"✗ {case_id}: 变化点 {t_ms} 不在 {STEP_MS}ms 网格上")

    frames = []
    state: tuple = ()
    index = 0
    for t_ms in range(0, end_ms + 1, STEP_MS):
        while index < len(changes) and int(changes[index][0]) == t_ms:
            state = tuple(sorted(changes[index][1]))
            index += 1
        frames.append([t_ms, "+".join(state)])
    if index != len(changes):
        raise SystemExit(f"✗ {case_id}: 有变化点晚于 end_ms")
    return frames


def _normalize_elapsed_ms(value: float, case_id: str, what: str) -> float:
    """把浮点噪声归一成毫秒整数，并拒绝真正的非整数。

    250 Hz 网格上所有时长都应是 4ms 的整数倍，但 ``(t2/1000 - t1/1000) * 1000``
    会带 1e-13 量级的二进制误差（450 会算成 450.00000000000006）。判据必须是
    「与最近整数相差不超过 1e-6」而不是 ``float.is_integer()``，否则生成器会
    因浮点噪声拒绝掉本来完全合法的用例。落盘统一取 round()，GDScript 侧用
    1e-6 容差比较，文案里的 ``%.0f`` 两端仍然逐字相同。
    """
    rounded = float(round(float(value)))
    if abs(float(value) - rounded) > 1e-6:
        raise SystemExit(f"✗ {case_id}: {what} 的 elapsed_ms={value!r} 不是毫秒整数")
    return rounded


def _drive(det: TapDetector, frames: list, case_id: str, set_modifier=None) -> tuple:
    """按引擎分支驱动参考实现，记录 Hit / Failure / 首下后的 status。"""
    if set_modifier is not None:
        value = set_modifier
        try:
            normalized = canonical_button(value)
        except ValueError as exc:
            raise SystemExit(f"✗ {case_id}: set_modifier 不是规范按键名：{exc}") from None
        if normalized != value:
            raise SystemExit(
                f"✗ {case_id}: set_modifier 必须是规范名 {normalized!r}，收到 {value!r}"
            )
        # 必须在喂首帧之前调用：回放套件走同一入口、同一顺序，否则
        # det_set_modifier_rt_success 会变成「Python 0 条、GDScript 1 条」的假分歧。
        det.set_modifier(normalized)

    hits = []
    failures = []
    status_after_first_press = None
    for t_ms, label in frames:
        buttons = frozenset(part for part in label.split("+") if part)
        frame = Frame(
            now=t_ms / 1000.0,
            state=PadState(),
            ls_mag=0.0,
            ls_angle=0.0,
            rs_mag=0.0,
            rs_angle=0.0,
            facing=0.0,
            buttons=buttons,
        )
        if all(name in buttons for name in det.required):
            hit = det.update(frame)
            if hit is not None:
                hits.append({
                    "elapsed_ms": _normalize_elapsed_ms(hit.elapsed_ms, case_id, "Hit"),
                    "summary": hit.summary,
                    "detail": hit.detail,
                })
        else:
            # 顺序不能反：先 observe 才能让 reset 用上本帧的按键状态。
            det.observe(frame)
            det.reset()
        if status_after_first_press is None and det._t0 is not None:
            status_after_first_press = det.status()
        failure = det.pop_failure()
        if failure is not None:
            failures.append({
                "code": failure.code,
                "message": failure.message,
                "elapsed_ms": _normalize_elapsed_ms(
                    failure.elapsed_ms, case_id, f"Failure {failure.code}"
                ),
            })
    return hits, failures, status_after_first_press


def _case_payload(case: dict, skill) -> dict:
    case_id = case["id"]
    det = TapDetector(skill)
    frames = _build_frames(case)
    hits, failures, status_after_first_press = _drive(
        det, frames, case_id, case.get("set_modifier")
    )
    expect = {"hits": hits, "failures": failures}
    if status_after_first_press is not None:
        expect["status_after_first_press"] = status_after_first_press

    payload = {
        "id": case_id,
        "kind": "detector",
        "modifier": case["modifier"],
        "button": case["button"],
        "frames": frames,
        "expect": expect,
    }
    if "set_modifier" in case:
        payload["set_modifier"] = case["set_modifier"]
    return payload


def _drive_runtime(cfg, frames: list, case_id: str):
    """用 `Engine._tick` 逐帧驱动参考引擎，收集**全部** Outcome 与 taps 计数。

    不跑 `Engine.run()`：那是 250 Hz 墙钟循环，夹具需要的是确定性的注入时间轴。
    """
    # out 指向 StringIO：Engine 每次命中都会 _write 一行「✓ 绿色搓射…」，
    # 生成器只需要夹具字节，不要在 --check 的输出里刷屏。
    engine = _CollectingEngine(
        cfg, _NullSource(), RumbleEngine(None, enabled=False), out=io.StringIO()
    )
    # counters 只从**唯一**的 taps 动作读。真实配置把绿色搓射排在 skills 最后
    # （index 4），`engine.skills[0]` 是马赛回旋（arc）；按下标取会让
    # rt_two_shots_500 期望 hits=2 而实际读到 0。
    tap_actives = [a for a in engine.skills if a.skill.kind == "taps"]
    if len(tap_actives) != 1:
        raise SystemExit(
            f"✗ {case_id}: 运行时夹具需要唯一的 taps 动作，实际 {len(tap_actives)} 个"
        )
    active = tap_actives[0]

    for t_ms, label in frames:
        buttons = frozenset(part for part in label.split("+") if part)
        # rs_x / rs_y 恒为 0：右摇杆恒回中是移动端本阶段的收缩，正好让 Python 的
        # 手势锁在 gesture_release_ms 后自动解锁。
        engine._tick(t_ms / 1000.0, PadState(buttons=buttons))

    outcomes = [
        {
            "ok": outcome.ok,
            "code": outcome.code,
            "elapsed_ms": _normalize_elapsed_ms(outcome.elapsed_ms, case_id, "Outcome"),
            "message": outcome.message,
            "detail": outcome.detail,
        }
        for outcome in engine.collected
    ]
    counters = {
        "hits": active.hits,
        "attempts": active.attempts,
        "group_hits": active.group_hits,
        "groups_done": active.groups_done,
        "suppressed": engine.suppressed,
    }
    return outcomes, counters


def _runtime_case_payload(case: dict, cfg) -> dict:
    case_id = case["id"]
    frames = _build_frames(case)
    payload = {"id": case_id, "kind": "runtime", "frames": frames}
    confirmed = bool(case.get("layout_confirmed", True))
    if confirmed:
        outcomes, counters = _drive_runtime(cfg, frames, case_id)
    else:
        # 布局硬门是移动端独有的结构：Python 引擎没有这个分支，它的时间线本来
        # 会命中一次 448ms。期望直接写空，不伪称来自参考实现。
        payload["layout_confirmed"] = False
        outcomes = []
        counters = {
            "hits": 0,
            "attempts": 0,
            "group_hits": 0,
            "groups_done": 0,
            "suppressed": 0,
        }
    payload["expect"] = {"outcomes": outcomes, "counters": counters}
    return payload


def build_payload(root: Path) -> dict:
    """按 Python 参考实现逐用例推导夹具内容（纯计算，不写盘）。"""
    cfg = _load_config(root)
    skill = _pick_skill(cfg)
    detector_cases = [_case_payload(case, skill) for case in CASES]
    runtime_cases = [_runtime_case_payload(case, cfg) for case in RUNTIME_CASES]
    seen: set[str] = set()
    for payload in detector_cases + runtime_cases:
        if payload["id"] in seen:
            raise SystemExit(f"✗ 夹具 id 重复：{payload['id']}")
        seen.add(payload["id"])
    return {
        "schema_version": 1,
        "source": {
            **{name: rel.as_posix() for name, rel in SOURCE_RELS.items()},
            "sha256": {name: _sha256(root, rel) for name, rel in SOURCE_RELS.items()},
        },
        "meta": {"hz": HZ, "step_ms": STEP_MS, "skill": skill.name},
        "cases": detector_cases + runtime_cases,
    }


def render(root: Path) -> bytes:
    """夹具的规范字节形态：UTF-8、两空格缩进、键排序、结尾一个换行。

    ``sort_keys`` + 固定 indent 保证「同一份实现 → 同一串字节」，``--check``
    才能做逐字节比较而不是语义比较（语义比较会漏掉键顺序与格式漂移）。
    """
    payload = build_payload(root)
    text = json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    return text.encode("utf-8")


def write_if_changed(path: Path, data: bytes) -> bool:
    """内容相同就不落盘：重复运行不产生 diff，也不白改 mtime。"""
    if path.is_file() and path.read_bytes() == data:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return True


def _first_difference(expected: bytes, actual: bytes) -> str:
    """首个差异的行号与上下文：定位用，不把整份夹具刷到终端。"""
    expected_lines = expected.decode("utf-8").splitlines()
    actual_lines = actual.decode("utf-8", errors="replace").splitlines()
    total = max(len(expected_lines), len(actual_lines))
    for index in range(total):
        want = expected_lines[index] if index < len(expected_lines) else "<文件结束>"
        got = actual_lines[index] if index < len(actual_lines) else "<文件结束>"
        if want != got:
            return (
                f"第 {index + 1} 行开始不一致：\n"
                f"  期望（重新推导）: {want}\n"
                f"  实际（磁盘上的夹具）: {got}"
            )
    return "字节不同但逐行内容一致（行尾或编码差异）"


def check(root: Path) -> int:
    """只读校验：重新推导后与磁盘夹具逐字节比较，绝不写盘。"""
    target = fixture_path(root)
    if not target.is_file():
        print(
            f"✗ 缺少 tap 黄金夹具：{FIXTURE_REL.as_posix()}\n"
            "  运行 python3 tools/gen_tap_golden.py 生成。",
            file=sys.stderr,
        )
        return 1
    expected = render(root)
    actual = target.read_bytes()
    if expected != actual:
        print(
            f"✗ 夹具与 Python 参考不一致：{FIXTURE_REL.as_posix()}\n"
            f"  {_first_difference(expected, actual)}\n"
            "  夹具是生成物，不能手改；运行 python3 tools/gen_tap_golden.py "
            "重新生成黄金夹具。",
            file=sys.stderr,
        )
        return 1
    payload = build_payload(root)
    detector_count = sum(1 for case in payload["cases"] if case["kind"] == "detector")
    runtime_count = sum(1 for case in payload["cases"] if case["kind"] == "runtime")
    print(
        "✓ tap 黄金夹具与 Python 参考一致"
        f"（detector {detector_count} 条、runtime {runtime_count} 条）"
    )
    return 0


def sync(root: Path) -> int:
    """生成夹具；内容没变就只报告「未变」。"""
    target = fixture_path(root)
    changed = write_if_changed(target, render(root))
    marker = "✓" if changed else "·"
    state = "已更新" if changed else "未变"
    print(f"{marker} {FIXTURE_REL.as_posix()} {state}")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="gen_tap_golden.py",
        description="从 desktop/padskills/detectors.py 推导 tap 检测器黄金夹具",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "示例:\n"
            "  python3 tools/gen_tap_golden.py           生成 / 刷新夹具\n"
            "  python3 tools/gen_tap_golden.py --check   只校验，不写盘\n"
        ),
    )
    parser.add_argument(
        "--check", action="store_true", help="只校验夹具是否等于重新推导的结果，不写任何文件"
    )
    parser.add_argument(
        "--root", default=None, help="仓库根目录（默认按脚本位置推导，仅供自测注入）"
    )
    args = parser.parse_args(argv)

    root = Path(args.root).resolve() if args.root else repo_root()
    if not root.is_dir():
        raise SystemExit(f"仓库根目录不存在: {root}")
    missing = [rel.as_posix() for rel in SOURCE_RELS.values() if not (root / rel).is_file()]
    if missing:
        raise SystemExit(f"✗ 参考实现不存在：{', '.join(missing)}")
    if args.check:
        return check(root)
    return sync(root)


if __name__ == "__main__":
    raise SystemExit(main())
