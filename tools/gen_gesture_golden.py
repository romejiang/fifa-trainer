#!/usr/bin/env python3
"""从桌面版 Python 参考实现重新推导手势检测器黄金夹具。

    python3 tools/gen_gesture_golden.py            # 生成 / 刷新夹具
    python3 tools/gen_gesture_golden.py --check    # 只比对，不写盘

夹具是 GDScript 手势回放套件的唯一期望来源，所以它必须是**生成物**：手改一份
JSON 让测试变绿，等于把「与 Python 对等」偷换成「与手改后的自己一致」。
``--check`` 重新推导后逐字节比较，不一致就打印首个差异行并返回 1，且绝不写盘。

为什么期望值必须跑参考实现：``desktop/padskills/detectors.py`` 的 ``ArcDetector``
/ ``SequenceDetector`` / ``TapDetector`` 是唯一规格书；生成器只负责把 250 Hz 时间轴
喂进去，记录每一次 ``Hit`` 与每一次 ``pop_failure()``。任何「我以为是 400ms」的
手写期望都可能与实现的取整、边界、分支顺序不符。

为什么检测器要按 ``skill.kind`` 分派：``det_stepover_ok`` / ``det_heel_to_heel_ok`` /
``det_croqueta_ok`` / ``det_green_finesse_ok`` 都不是弧线动作。硬编码 ``ArcDetector``
会让它们的期望变成空或错值 —— 而这个错误在「一条弧线用例」里完全看不出来。

为什么夹具带 ``configs`` 注册表：变体 / 合成用例不能回落到 ``res://assets/config/``
的出厂副本，否则会被按出厂阈值静默回放，``mismatches=0`` 变成假绿。每个用例的
``config`` 键都能在 ``configs`` 里找到**完整**配置对象。

为什么引擎也要跑一遍：``facing`` 是引擎状态而不是夹具自由量。生成器先按引擎规则
推导每帧的 ``facing``，再逐帧断言 ``abs(engine.facing - declared) < 1e-9`` ——
不一致就是夹具写错了，不是引擎错。
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import io
import json
import math
import sys
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_REPO_ROOT / "desktop"))

from padskills.config import parse_config  # noqa: E402
from padskills.detectors import Frame, build_detector  # noqa: E402
from padskills.engine import Engine  # noqa: E402
from padskills.geometry import norm_deg, signed_delta  # noqa: E402
from padskills.input_source import GamepadSource, PadState  # noqa: E402
from padskills.rumble import RumbleEngine  # noqa: E402

STEP_MS = 4
HZ = 250

CONFIG_REL = Path("shared") / "skills_config.json"
FIXTURE_REL = Path("mobile") / "tests" / "fixtures" / "gesture_golden.json"

# 四个摘要一起进夹具：detectors 是本文件的规格书，engine 决定 facing / 手势锁 /
# 冷却，config 决定 Skill 字段，skills_config 是真源。任何一份变了都必须重新生成。
SOURCE_RELS = {
    "detectors": Path("desktop") / "padskills" / "detectors.py",
    "engine": Path("desktop") / "padskills" / "engine.py",
    "config": Path("desktop") / "padskills" / "config.py",
    "skills_config": CONFIG_REL,
}

# 左摇杆默认「朝前推满」：relative_to_ls 的动作因此有稳定基准 facing = 0°。
DEFAULT_LS = ((0, 0.0, 0.9),)

# 时间轴用「线段」描述，再由 `_timeline()` 展开到 4ms 网格：
#   ("hold",  t0, t1, angle, mag)           —— 逐帧恒定
#   ("sweep", t0, duration_ms, a0, a1, mag) —— 匀速扫掠，a1 可以超过 360（表示多转）
#
# 所有数字都必须落在 4ms 网格上；角度按 4ms 步长归一化到 [0, 360)，与真机
# `PadState.rs_angle` 的值域一致。期望值由参考实现跑出来，这里只写轨迹。
CASES = (
    # 1. 马赛回旋成功：左摇杆朝前为基准，右摇杆从相对 180° 顺时针扫到 20°
    #    （扫过 200°），耗时 500 ms，回中后不改判。
    #
    #    为什么 500ms 不会先撞 too_fast：end_ok 在 swept >= 100° 时成立，
    #    而 200°/500ms 的轨迹要到 252ms 才转满 100° —— min_duration 250ms
    #    已经过了。两个边界相差 2ms（半帧），这条用例同时钉住了这个顺序。
    {
        "id": "det_roulette_ok",
        "kind": "detector",
        "skill": "马赛回旋 Roulette",
        "config": "shipped",
        "end_ms": 700,
        "segments": (
            ("hold", 0, 96, 0.0, 0.0),
            ("sweep", 100, 500, 180.0, 380.0, 0.9),
            ("hold", 604, 700, 0.0, 0.0),
        ),
    },
    # 2. 踩单车成功：起手 0°（起点容错 55° 内），顺时针扫到 90°（终点
    #    [90, 270] ± 55 内），500 ms。swept 70° 时同时满足「最短 70°」与
    #    「终点够近」，于是 392 ms 命中 —— 早于 500 ms 的满扫，这是参考实现
    #    「到区间就成功」的真实行为，期望值由它跑出来。
    #    每帧 0.72°：0.72k 的取整余数只可能是 .00/.72/.44/.16/.88/.60/.32/.04，
    #    永远不会落在 %.0f 的 .5 刀口上。
    {
        "id": "det_stepover_ok",
        "kind": "detector",
        "skill": "踩单车 Stepover",
        "config": "shipped",
        "end_ms": 700,
        "segments": (
            ("hold", 0, 96, 0.0, 0.0),
            ("sweep", 100, 500, 0.0, 90.0, 0.9),
            ("hold", 604, 700, 0.0, 0.0),
        ),
    },
    # 3. 磕球过人成功：前点拨 → 回中 → 后点拨。
    #    第一步按住 100ms 再松手，所以 t0 冻结在 196ms；第二步必须同时满足
    #    「自 t0 起 >= 250ms」与「自松手起 <= idle 250ms」，窗口只有一帧
    #    （446~450ms）。448ms 是窗口正中那一帧，两个判据都留 2ms 余量。
    {
        "id": "det_heel_to_heel_ok",
        "kind": "detector",
        "skill": "磕球过人 Heel-to-Heel",
        "config": "shipped",
        "end_ms": 560,
        "segments": (
            ("hold", 0, 96, 0.0, 0.0),
            ("hold", 100, 196, 0.0, 0.9),
            ("hold", 200, 444, 0.0, 0.0),
            ("hold", 448, 452, 180.0, 0.9),
            ("hold", 456, 560, 0.0, 0.0),
        ),
    },
    # 4. 油炸丸子成功：全程按住 LB，向右推满并保持。hold_ms 350 在 4ms 网格上
    #    取不到，首个达标帧是 352ms；elapsed 也是 352ms（>= min 250）。
    {
        "id": "det_croqueta_ok",
        "kind": "detector",
        "skill": "油炸丸子 La Croqueta",
        "config": "shipped",
        "end_ms": 560,
        "buttons": ((0, ()), (4, ("LB",))),
        "segments": (
            ("hold", 0, 96, 0.0, 0.0),
            ("hold", 100, 452, 90.0, 0.9),
            ("hold", 456, 560, 0.0, 0.0),
        ),
    },
    # 5. 绿色搓射成功：按住 RB，两下 X 间隔 448ms（4ms 网格上取不到 450）。
    #    与 tap 黄金夹具的 det_success_mid_450 同一时间线，跨套件口径一致。
    {
        "id": "det_green_finesse_ok",
        "kind": "detector",
        "skill": "绿色搓射 Green Finesse",
        "config": "shipped",
        "end_ms": 560,
        "buttons": (
            (0, ()),
            (4, ("RB",)),
            (100, ("RB", "X")),
            (104, ("RB",)),
            (548, ("RB", "X")),
            (552, ("RB",)),
        ),
        "segments": (
            ("hold", 0, 560, 0.0, 0.0),
        ),
    },
    # 6. 马赛回旋太快：3.2°/帧（248ms 扫 198.4°）。end_ok 在 end_rel >= 280 时成立，
    #    即 swept >= 100；3.2°/帧的 100° 落在第 32 帧（swept 102.4，距终点边界
    #    还有 2.4° 余量），elapsed 128ms < 250 → too_fast。
    #    刻意不用「每帧整 1°」：那会让第一个达标帧正好压在 ±80° 的边界上，
    #    Python/GDScript 的 1 ulp 差异就可能把 abort 推后一帧。
    {
        "id": "det_roulette_too_fast",
        "kind": "detector",
        "skill": "马赛回旋 Roulette",
        "config": "shipped",
        "end_ms": 500,
        "segments": (
            ("hold", 0, 96, 0.0, 0.0),
            ("sweep", 100, 248, 180.0, 378.4, 0.9),
            ("hold", 348, 500, 0.0, 0.0),
        ),
    },
    # 7. 马赛回旋太慢：0.6°/帧持续旋转 1400ms。每 4 帧走 2.4° > motion_delta 2.0，
    #    所以「在动」计时器一直刷新，不会先撞 idle 250ms；第 151 帧（604ms）刚
    #    超过上限 600ms 就报 too_slow。
    {
        "id": "det_roulette_too_slow",
        "kind": "detector",
        "skill": "马赛回旋 Roulette",
        "config": "shipped",
        "end_ms": 1600,
        "segments": (
            ("hold", 0, 96, 0.0, 0.0),
            ("sweep", 100, 1400, 180.0, 390.0, 0.9),
            ("hold", 1504, 1600, 0.0, 0.0),
        ),
    },
    # 8. 踩单车起点不对：从相对 60° 起手。start_tolerance 55 已经超出，但仍在
    #    55 + claim_margin 20 = 75 之内，所以这次手势「是冲我来的」——会报错，
    #    而不是静默。起手帧本身不判，下一帧（4ms）立刻报 wrong_start。
    {
        "id": "det_stepover_wrong_start",
        "kind": "detector",
        "skill": "踩单车 Stepover",
        "config": "shipped",
        "end_ms": 700,
        "segments": (
            ("hold", 0, 96, 0.0, 0.0),
            ("sweep", 100, 500, 60.0, 150.0, 0.9),
            ("hold", 604, 700, 0.0, 0.0),
        ),
    },
    # 9. 马赛回旋终点不对：扫掠 84° 后回中。swept 84 >= min_angle 70，所以不是
    #    too_short；终点 180 + 84 = 264°，距 0° 目标 96° > 80°，松手时报 wrong_end。
    #    整段都没进过终点窗口（end_rel 最大 264 < 280），不会先命中成功。
    {
        "id": "det_roulette_wrong_end",
        "kind": "detector",
        "skill": "马赛回旋 Roulette",
        "config": "shipped",
        "end_ms": 700,
        "segments": (
            ("hold", 0, 96, 0.0, 0.0),
            ("sweep", 100, 500, 180.0, 264.0, 0.9),
            ("hold", 604, 700, 0.0, 0.0),
        ),
    },
    # 10. 油炸丸子保持不够：按住 LB 向右推 196ms 后松开 LB、但摇杆仍推着。
    #     引擎前置分支走 observe() + reset()，reset 里的 _abandon_failure 报
    #     hold_short（已保持 196ms，需要 350ms）。elapsed 用上一帧的 _now（200ms）。
    {
        "id": "det_croqueta_hold_short",
        "kind": "detector",
        "skill": "油炸丸子 La Croqueta",
        "config": "shipped",
        "end_ms": 500,
        "buttons": ((0, ()), (4, ("LB",)), (300, ())),
        "segments": (
            ("hold", 0, 96, 0.0, 0.0),
            ("hold", 100, 396, 90.0, 0.9),
            ("hold", 400, 500, 0.0, 0.0),
        ),
    },
)

# 六类边界（RESEARCH §B.3）：时长 / 角度 / 起手 / 重新武装 / 保持 / 容差。
# 每一条都刻意把「刀口」放在最后一帧：参考实现是「到区间就成功」，
# 若边界值在轨迹中途就被满足，用例会提前命中，测不到那个边界。
#
# 为什么时长边界从 t0=100ms 起算：`elapsed_ms` 从检测器 `t0`（摇杆推过
# enter 的那一帧）起算，不是从夹具第一帧起算。所以 `596` 指的是 sweep 段
# 自己的时长，不是 `end_ms`。
BOUNDARY_CASES = (
    # 1. 马赛回旋上限 - 4ms：596ms 走完 100°，终点正好落在 280°（0±80 的
    #    下边界），elapsed 596 <= 600 → ok。若上限判定早一帧，会先报 too_slow。
    {
        "id": "det_roulette_max_minus_4",
        "kind": "detector",
        "skill": "马赛回旋 Roulette",
        "config": "shipped",
        "end_ms": 700,
        "segments": (
            ("hold", 0, 96, 0.0, 0.0),
            ("sweep", 100, 596, 180.0, 280.0, 0.9),
            ("hold", 700, 700, 0.0, 0.0),
        ),
    },
    # 2. 马赛回旋上限 + 4ms：604ms 才走到 280°。第 600ms 那一帧终点仍是
    #    279.3°（窗口外），下一帧 elapsed 604 > 600 → too_slow。
    {
        "id": "det_roulette_max_plus_4",
        "kind": "detector",
        "skill": "马赛回旋 Roulette",
        "config": "shipped",
        "end_ms": 708,
        "segments": (
            ("hold", 0, 96, 0.0, 0.0),
            ("sweep", 100, 604, 180.0, 280.0, 0.9),
            ("hold", 708, 708, 0.0, 0.0),
        ),
    },
    # 3. 马赛回旋下限 - 4ms：248ms 就转满 100° 且终点到位 → too_fast。
    #    必须让终点窗口只在最后一帧才满足，否则会提前触发。
    {
        "id": "det_roulette_min_minus_4",
        "kind": "detector",
        "skill": "马赛回旋 Roulette",
        "config": "shipped",
        "end_ms": 400,
        "segments": (
            ("hold", 0, 96, 0.0, 0.0),
            ("sweep", 100, 248, 180.0, 280.0, 0.9),
            ("hold", 352, 400, 0.0, 0.0),
        ),
    },
    # 4. 马赛回旋下限 + 4ms：252ms 转满 100° 且终点到位 → ok。
    {
        "id": "det_roulette_min_plus_4",
        "kind": "detector",
        "skill": "马赛回旋 Roulette",
        "config": "shipped",
        "end_ms": 400,
        "segments": (
            ("hold", 0, 96, 0.0, 0.0),
            ("sweep", 100, 252, 180.0, 280.0, 0.9),
            ("hold", 356, 400, 0.0, 0.0),
        ),
    },
    # 5. 终点容差 - 1°：终点相对 79°（目标 0±80）。前 99° 停在 81°（窗口外
    #    1°），最后一帧跳到 79° → ok。若容差少 1°，这一帧会是 wrong_end。
    {
        "id": "det_roulette_end_tol_minus_1",
        "kind": "detector",
        "skill": "马赛回旋 Roulette",
        "config": "shipped",
        "end_ms": 560,
        "segments": (
            ("hold", 0, 96, 0.0, 0.0),
            ("sweep", 100, 396, 180.0, 81.0, 0.9),
            ("hold", 500, 504, 79.0, 0.9),
            ("hold", 508, 560, 0.0, 0.0),
        ),
    },
    # 6. 终点容差 + 1°：终点 81° 在窗口外 1°，全程没有成功，松手报 wrong_end。
    {
        "id": "det_roulette_end_tol_plus_1",
        "kind": "detector",
        "skill": "马赛回旋 Roulette",
        "config": "shipped",
        "end_ms": 600,
        "segments": (
            ("hold", 0, 96, 0.0, 0.0),
            ("sweep", 100, 396, 180.0, 81.0, 0.9),
            ("hold", 500, 600, 0.0, 0.0),
        ),
    },
    # 7. 扫掠 23° < report_min_angle 24.5：整条静默（连 too_short 都不报）。
    #    49 步（196ms）而不是 50 步：偶数步会在中点产生 11.5° 的取整刀口。
    {
        "id": "det_roulette_short_below_report_min",
        "kind": "detector",
        "skill": "马赛回旋 Roulette",
        "config": "shipped",
        "end_ms": 400,
        "segments": (
            ("hold", 0, 96, 0.0, 0.0),
            ("sweep", 100, 196, 180.0, 157.0, 0.9),
            ("hold", 300, 400, 0.0, 0.0),
        ),
    },
    # 8. 扫掠 26° >= report_min_angle 24.5 且 < min_angle 70 → too_short。
    {
        "id": "det_roulette_short_at_report_min",
        "kind": "detector",
        "skill": "马赛回旋 Roulette",
        "config": "shipped",
        "end_ms": 400,
        "segments": (
            ("hold", 0, 96, 0.0, 0.0),
            ("sweep", 100, 196, 180.0, 154.0, 0.9),
            ("hold", 300, 400, 0.0, 0.0),
        ),
    },
    # 9. 踩单车起手 54°（start_tolerance 55 内）：正常判定。90° 是合法终点，
    #    swept 到 70 时终点 124 已落在 [90,270]±55 的窗口里 → 392ms 命中。
    {
        "id": "det_stepover_start_in_tol",
        "kind": "detector",
        "skill": "踩单车 Stepover",
        "config": "shipped",
        "end_ms": 700,
        "segments": (
            ("hold", 0, 96, 0.0, 0.0),
            ("sweep", 100, 500, 54.0, 144.0, 0.9),
            ("hold", 604, 700, 0.0, 0.0),
        ),
    },
    # 10. 起手 56°：超出 55° 容差、仍在 55+20=75 的 claim 内 → wrong_start。
    {
        "id": "det_stepover_start_out_tol",
        "kind": "detector",
        "skill": "踩单车 Stepover",
        "config": "shipped",
        "end_ms": 600,
        "segments": (
            ("hold", 0, 96, 0.0, 0.0),
            ("sweep", 100, 500, 56.0, 146.0, 0.9),
            ("hold", 604, 600, 0.0, 0.0),
        ),
    },
    # 11. 起手 74°：容差外、claim 边界内（74 <= 75）→ wrong_start。
    {
        "id": "det_stepover_start_at_claim_edge",
        "kind": "detector",
        "skill": "踩单车 Stepover",
        "config": "shipped",
        "end_ms": 600,
        "segments": (
            ("hold", 0, 96, 0.0, 0.0),
            ("sweep", 100, 500, 74.0, 164.0, 0.9),
            ("hold", 604, 600, 0.0, 0.0),
        ),
    },
    # 12. 起手 76°：既超出容差也超出 claim（76 > 75）→ 静默 abort，零判定。
    {
        "id": "det_stepover_start_outside_claim",
        "kind": "detector",
        "skill": "踩单车 Stepover",
        "config": "shipped",
        "end_ms": 600,
        "segments": (
            ("hold", 0, 96, 0.0, 0.0),
            ("sweep", 100, 500, 76.0, 166.0, 0.9),
            ("hold", 604, 600, 0.0, 0.0),
        ),
    },
    # 13. 重新武装 116ms：第一段 too_short 后回中 116ms 就推第二段。
    #     release_hold_ms=120，116 < 120 → 第二段起不来，只有第一条判定。
    {
        "id": "det_arc_rearm_116",
        "kind": "detector",
        "skill": "马赛回旋 Roulette",
        "config": "shipped",
        "end_ms": 700,
        "segments": (
            ("hold", 0, 96, 0.0, 0.0),
            ("sweep", 100, 200, 180.0, 150.0, 0.9),
            ("hold", 304, 416, 0.0, 0.0),
            ("hold", 420, 600, 180.0, 0.9),
            ("hold", 604, 700, 0.0, 0.0),
        ),
    },
    # 14. 重新武装 124ms：回中满 120ms 后第二段正常起手，两条 too_short。
    {
        "id": "det_arc_rearm_124",
        "kind": "detector",
        "skill": "马赛回旋 Roulette",
        "config": "shipped",
        "end_ms": 800,
        "segments": (
            ("hold", 0, 96, 0.0, 0.0),
            ("sweep", 100, 200, 180.0, 150.0, 0.9),
            ("hold", 304, 424, 0.0, 0.0),
            ("hold", 428, 428, 180.0, 0.9),
            ("sweep", 432, 200, 180.0, 150.0, 0.9),
            ("hold", 636, 800, 0.0, 0.0),
        ),
    },
    # 15. 保持 348ms（hold_ms 350 在 4ms 网格上的下邻点）→ hold_short。
    #     第 448ms 那一帧 held=348 < 350；452ms 松开 LB 时 reset 报 348ms。
    {
        "id": "det_croqueta_hold_348",
        "kind": "detector",
        "skill": "油炸丸子 La Croqueta",
        "config": "shipped",
        "end_ms": 560,
        "buttons": ((0, ()), (4, ("LB",)), (452, ())),
        "segments": (
            ("hold", 0, 96, 0.0, 0.0),
            ("hold", 100, 448, 90.0, 0.9),
            ("hold", 452, 560, 0.0, 0.0),
        ),
    },
    # 16. 保持 352ms（上邻点）→ ok。第 452ms 那一帧 held=352 >= 350。
    {
        "id": "det_croqueta_hold_352",
        "kind": "detector",
        "skill": "油炸丸子 La Croqueta",
        "config": "shipped",
        "end_ms": 560,
        "buttons": ((0, ()), (4, ("LB",)), (456, ())),
        "segments": (
            ("hold", 0, 96, 0.0, 0.0),
            ("hold", 100, 452, 90.0, 0.9),
            ("hold", 456, 560, 0.0, 0.0),
        ),
    },
    # 17. 容差 - 1°：目标偏 9°（<= tolerance_deg 10）→ 匹配 → ok。
    {
        "id": "det_croqueta_tol_minus_1",
        "kind": "detector",
        "skill": "油炸丸子 La Croqueta",
        "config": "shipped",
        "end_ms": 560,
        "buttons": ((0, ()), (4, ("LB",)), (456, ())),
        "segments": (
            ("hold", 0, 96, 0.0, 0.0),
            ("hold", 100, 452, 99.0, 0.9),
            ("hold", 456, 560, 0.0, 0.0),
        ),
    },
    # 18. 容差 + 1°：目标偏 11°（> 10）→ 从不匹配，_best_hold_ms 恒 0，
    #     超时分支也不会产 hold_short → 零判定。
    {
        "id": "det_croqueta_tol_plus_1",
        "kind": "detector",
        "skill": "油炸丸子 La Croqueta",
        "config": "shipped",
        "end_ms": 560,
        "buttons": ((0, ()), (4, ("LB",)), (456, ())),
        "segments": (
            ("hold", 0, 96, 0.0, 0.0),
            ("hold", 100, 452, 101.0, 0.9),
            ("hold", 456, 560, 0.0, 0.0),
        ),
    },
)


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


# ---------------------------------------------------------------------------
# 轨迹展开
# ---------------------------------------------------------------------------


def _timeline(segments) -> dict[int, tuple[float, float]]:
    """把线段描述展开成「4ms 网格 -> (角度, 幅度)」的查表。"""
    values: dict[int, tuple[float, float]] = {}
    for segment in segments:
        kind = segment[0]
        if kind == "hold":
            _, t0, t1, angle, mag = segment
            if int(t0) % STEP_MS or int(t1) % STEP_MS:
                raise SystemExit(f"✗ hold 段 {t0}..{t1} 不在 {STEP_MS}ms 网格上")
            for t_ms in range(int(t0), int(t1) + 1, STEP_MS):
                values[t_ms] = (float(angle), float(mag))
        elif kind == "sweep":
            _, t0, duration_ms, angle_from, angle_to, mag = segment
            if int(t0) % STEP_MS or int(duration_ms) % STEP_MS:
                raise SystemExit(f"✗ sweep 段 {t0}+{duration_ms}ms 不在 {STEP_MS}ms 网格上")
            steps = int(duration_ms) // STEP_MS
            if steps <= 0:
                raise SystemExit("✗ sweep 段的 duration_ms 必须至少一帧")
            for index in range(steps + 1):
                angle = angle_from + (angle_to - angle_from) * index / steps
                values[int(t0) + index * STEP_MS] = (norm_deg(angle), float(mag))
        else:
            raise SystemExit(f"✗ 未知的轨迹段类型 {kind!r}")
    return values


def _button_timeline(changes, end_ms: int, case_id: str) -> dict[int, tuple[str, ...]]:
    """按键变化点 -> 逐帧按键集合（保持不变到下一个变化点）。"""
    ordered = list(changes)
    for t_ms, _ in ordered:
        if int(t_ms) % STEP_MS:
            raise SystemExit(f"✗ {case_id}: 按键变化点 {t_ms} 不在 {STEP_MS}ms 网格上")
    result: dict[int, tuple[str, ...]] = {}
    state: tuple[str, ...] = ()
    index = 0
    for t_ms in range(0, end_ms + 1, STEP_MS):
        while index < len(ordered) and int(ordered[index][0]) == t_ms:
            state = tuple(sorted(ordered[index][1]))
            index += 1
        result[t_ms] = state
    if index != len(ordered):
        raise SystemExit(f"✗ {case_id}: 有按键变化点晚于 end_ms")
    return result


def _ls_at(points, t_ms: int) -> tuple[float, float]:
    """左摇杆变化点 -> 该帧的 (角度, 幅度)。"""
    angle, mag = 0.0, 0.9
    for point in points:
        if int(point[0]) <= t_ms:
            angle, mag = float(point[1]), float(point[2])
        else:
            break
    return angle, mag


def _facing_column(cfg, points, times) -> list[float]:
    """按引擎规则（engine.py:251-254）推导每帧 facing：ls_mag 过阈值才更新。"""
    facing = float(cfg.input.initial_facing_deg)
    column: list[float] = []
    for t_ms in times:
        angle, mag = _ls_at(points, t_ms)
        if mag >= cfg.input.ls_facing_threshold:
            facing = angle
        column.append(facing)
    return column


def _build_frames(case: dict, cfg) -> list:
    """展开成逐帧全量时间轴：`[t_ms, rs_angle, rs_mag, [buttons], facing]`。"""
    case_id = case["id"]
    end_ms = int(case["end_ms"])
    if end_ms % STEP_MS:
        raise SystemExit(f"✗ {case_id}: end_ms 必须是 {STEP_MS}ms 的整数倍")
    values = _timeline(case["segments"])
    if values and max(values) > end_ms:
        raise SystemExit(f"✗ {case_id}: 轨迹点 {max(values)} 晚于 end_ms {end_ms}")
    buttons = _button_timeline(case.get("buttons", ()), end_ms, case_id)
    times = list(range(0, end_ms + 1, STEP_MS))
    facing = _facing_column(cfg, case.get("ls", DEFAULT_LS), times)

    frames = []
    angle, mag = 0.0, 0.0
    for index, t_ms in enumerate(times):
        if t_ms in values:
            angle, mag = values[t_ms]
        frames.append([t_ms, angle, mag, list(buttons[t_ms]), facing[index]])
    return frames


# ---------------------------------------------------------------------------
# 参考实现驱动
# ---------------------------------------------------------------------------


def _stick(angle: float, mag: float) -> tuple[float, float]:
    """角度 + 幅度 -> SDL 轴坐标（x 右正、y 下正），与 geometry.py 的约定互逆。"""
    return mag * math.sin(math.radians(angle)), -mag * math.cos(math.radians(angle))


def _drive_engine(cfg, frames: list, ls_points, case_id: str) -> _CollectingEngine:
    """用 `Engine._tick` 逐帧驱动参考引擎，并断言夹具的 facing 就是引擎状态。

    不跑 `Engine.run()`：那是 250 Hz 墙钟循环，夹具需要的是确定性的注入时间轴。
    `out` 指向 StringIO：每次命中都会写一行，不能让它污染 `--check` 输出。
    """
    engine = _CollectingEngine(
        cfg, _NullSource(), RumbleEngine(None, enabled=False), out=io.StringIO()
    )
    for t_ms, rs_angle, rs_mag, buttons, facing in frames:
        ls_angle, ls_mag = _ls_at(ls_points, t_ms)
        ls_x, ls_y = _stick(ls_angle, ls_mag)
        rs_x, rs_y = _stick(rs_angle, rs_mag)
        engine._tick(
            t_ms / 1000.0,
            PadState(ls_x=ls_x, ls_y=ls_y, rs_x=rs_x, rs_y=rs_y,
                     buttons=frozenset(buttons)),
        )
        if abs(engine.facing - facing) > 1e-9:
            raise SystemExit(
                f"✗ {case_id}: 第 {t_ms}ms 的 facing 夹具写错了："
                f"引擎 {engine.facing!r}，夹具 {facing!r}"
            )
    return engine


def _normalize_elapsed_ms(value: float, case_id: str, what: str) -> float:
    """把浮点噪声归一成毫秒整数，并拒绝真正的非整数（照 gen_tap_golden.py:457-469）。"""
    rounded = float(round(float(value)))
    if abs(float(value) - rounded) > 1e-6:
        raise SystemExit(f"✗ {case_id}: {what} 的 elapsed_ms={value!r} 不是毫秒整数")
    return rounded


def _assert_not_rounding_cliff(value: float, case_id: str, what: str) -> None:
    """拒绝会被 `%.0f` 格式化的实测值落在 .5 刀口上。

    Python 的 `format` 与 GDScript 的 `%` 都按 IEEE-754 取整，1 ulp 的差异足以让
    「1234.5」在两个语言里报成不同的整数。语料里不允许出现这种值 —— 它看起来像
    移植 bug，实际上只是取整。
    """
    fraction = abs(float(value) - math.floor(float(value)))
    if abs(fraction - 0.5) < 1e-6:
        raise SystemExit(
            f"✗ {case_id}: {what}={value!r} 落在 %.0f 的取整刀口上（距 .5 太近）"
        )


def _check_arc_cliffs(detector, rs_angle: float, rs_mag: float, case_id: str) -> None:
    """在 update() 之前算出这一帧会被格式化的 swept / end_rel，并拒绝刀口值。"""
    if rs_mag < detector.exit:
        swept = abs(detector.acc)
        end_rel = norm_deg(detector.last_angle - detector.base)
    else:
        swept = abs(detector.acc + signed_delta(detector.last_angle, rs_angle))
        end_rel = norm_deg(rs_angle - detector.base)
    _assert_not_rounding_cliff(swept, case_id, "swept")
    _assert_not_rounding_cliff(end_rel, case_id, "end_rel")


def _find_skill(cfg, name: str):
    for skill in cfg.skills:
        if skill.name == name:
            return skill
    raise SystemExit(f"✗ 配置里找不到动作 {name!r}：{CONFIG_REL.as_posix()}")


def _outcome(case_id: str, skill_name: str, ok: bool, code: str, message: str,
             elapsed_ms: float, at: float, detail: str) -> dict:
    return {
        "skill": skill_name,
        "ok": bool(ok),
        "code": str(code),
        "message": str(message),
        "elapsed_ms": _normalize_elapsed_ms(elapsed_ms, case_id, "elapsed_ms"),
        "at": float(at),
        "detail": str(detail),
    }


def _drive_detector(cfg, case: dict, frames: list) -> list:
    """按引擎分支驱动**按 kind 选出**的检测器，记录每一条 Hit / Failure。

    与 engine.py:316-350 的两道前置分支对应：修饰键不满足时先 `observe()` 再
    `reset()`（顺序不能反），否则 `reset()` 会用上一帧的按键状态算 elapsed。
    `relative_to_ls` 的第二道分支在检测器层不需要：``facing`` 已经由夹具给出。
    """
    case_id = case["id"]
    skill = _find_skill(cfg, case["skill"])
    detector = build_detector(skill)
    expected = {
        "arc": "ArcDetector",
        "sequence": "SequenceDetector",
        "taps": "TapDetector",
    }[skill.kind]
    if type(detector).__name__ != expected:
        raise SystemExit(
            f"✗ {case_id}: build_detector 按 kind={skill.kind!r} 返回了 "
            f"{type(detector).__name__}，期望 {expected}"
        )

    outcomes = []
    for t_ms, rs_angle, rs_mag, buttons, facing in frames:
        frame = Frame(
            now=t_ms / 1000.0,
            state=PadState(),
            ls_mag=0.0,
            ls_angle=0.0,
            rs_mag=rs_mag,
            rs_angle=rs_angle,
            facing=facing,
            buttons=frozenset(buttons),
        )
        if skill.kind == "arc" and detector.active:
            _check_arc_cliffs(detector, rs_angle, rs_mag, case_id)
        if not Engine._buttons_ok(skill, frame.buttons):
            detector.observe(frame)
            detector.reset()
        else:
            hit = detector.update(frame)
            if hit is not None:
                outcomes.append(_outcome(
                    case_id, skill.name, True, "ok", "", hit.elapsed_ms,
                    frame.now, hit.summary,
                ))
        failure = detector.pop_failure()
        if failure is not None:
            outcomes.append(_outcome(
                case_id, skill.name, False, failure.code, failure.message,
                failure.elapsed_ms, frame.now, "",
            ))
    return outcomes


def _runtime_outcomes(case_id: str, engine: _CollectingEngine) -> list:
    return [
        _outcome(
            case_id, outcome.skill_name, outcome.ok, outcome.code,
            outcome.message, outcome.elapsed_ms, outcome.at, outcome.detail,
        )
        for outcome in engine.collected
    ]


# ---------------------------------------------------------------------------
# 配置注册表
# ---------------------------------------------------------------------------


def variant(base: dict, skill_name: str, **params) -> dict:
    """深拷贝整份配置，只改点名技能的 params，再用 `parse_config` 自检一次。

    与桌面 `test_arc_direction` 的 `variant()` 同构：变体只改一个技能，其余不动。
    返回值是**完整**配置对象（不是 diff），直接进夹具的 `configs` 注册表。
    """
    data = copy.deepcopy(base)
    for item in data.get("skills", []):
        if item.get("name") == skill_name:
            item.setdefault("params", {}).update(params)
            break
    else:
        raise SystemExit(f"✗ variant: 配置里找不到动作 {skill_name!r}")
    parse_config(data, CONFIG_REL)
    return data


def _input_snapshot(cfg) -> dict:
    item = cfg.input
    return {
        "poll_hz": item.poll_hz,
        "deadzone": item.deadzone,
        "ls_facing_threshold": item.ls_facing_threshold,
        "initial_facing_deg": item.initial_facing_deg,
        "trigger_threshold": item.trigger_threshold,
        "joystick_index": item.joystick_index,
        "axis_layout": item.axis_layout,
        "invert": item.invert,
        "button_names": item.button_names,
        "calibration_ms": item.calibration_ms,
        "idle_reset_ms": item.idle_reset_ms,
        "gesture_release_ms": item.gesture_release_ms,
    }


def _skill_snapshot(skill) -> dict:
    return {
        "name": skill.name,
        "kind": skill.kind,
        "relative_to_ls": skill.relative_to_ls,
        "required_buttons": tuple(skill.required_buttons),
        "button_mode": skill.button_mode,
        "params": skill.params,
        "cooldown_ms": skill.cooldown_ms,
    }


def _assert_same_config(actual, expected, label: str) -> None:
    if actual.global_cooldown_ms != expected.global_cooldown_ms:
        raise SystemExit(f"✗ {label}: global_cooldown_ms 与真源不一致")
    if _input_snapshot(actual) != _input_snapshot(expected):
        raise SystemExit(f"✗ {label}: input 与真源不一致")
    a_skills = [_skill_snapshot(s) for s in actual.skills]
    b_skills = [_skill_snapshot(s) for s in expected.skills]
    if a_skills != b_skills:
        raise SystemExit(f"✗ {label}: skills 与真源不一致")


def _assert_configs_replayable(payload: dict, root: Path, parsed: dict, used: dict) -> None:
    """逐个重解析 `configs` 的每个值，并确认用例用的就是注册表里那一份。"""
    configs = payload["configs"]
    for key in configs:
        if key not in parsed:
            raise SystemExit(f"✗ configs[{key!r}] 没有被重新解析过")
    reference = parse_config(
        json.loads((root / CONFIG_REL).read_text(encoding="utf-8")),
        root / CONFIG_REL,
    )
    _assert_same_config(parsed["shipped"], reference, 'configs["shipped"]')

    for case in payload["cases"]:
        key = case["config"]
        if key not in configs:
            raise SystemExit(f"✗ {case['id']}: config 键 {key!r} 不在 configs 注册表里")
        # 身份比较而不是相等比较：相等但换了对象，说明回放时可能悄悄用了另一份配置。
        if parsed[key] is not used[case["id"]]:
            raise SystemExit(
                f"✗ {case['id']}: 产出 expect 的 AppConfig 与 configs[{key!r}] 不是同一个对象"
            )


# ---------------------------------------------------------------------------
# payload / 规范字节 / 只读校验
# ---------------------------------------------------------------------------


def _case_payload(case: dict, cfg) -> dict:
    case_id = case["id"]
    ls_points = tuple(case.get("ls", DEFAULT_LS))
    frames = _build_frames(case, cfg)
    engine = _drive_engine(cfg, frames, ls_points, case_id)
    kind = case.get("kind", "detector")
    if kind == "detector":
        outcomes = _drive_detector(cfg, case, frames)
    elif kind == "runtime":
        outcomes = _runtime_outcomes(case_id, engine)
    else:
        raise SystemExit(f"✗ {case_id}: 未知的用例类型 {kind!r}")
    return {
        "id": case_id,
        "kind": kind,
        "skill": case["skill"],
        "config": case.get("config", "shipped"),
        "ls": [[int(t), float(a), float(m)] for t, a, m in ls_points],
        "frames": frames,
        "expect": {"outcomes": outcomes},
    }


def build_payload(root: Path) -> dict:
    """按 Python 参考实现逐用例推导夹具内容（纯计算，不写盘）。"""
    base_dict = json.loads((root / CONFIG_REL).read_text(encoding="utf-8"))
    config_dicts: dict[str, dict] = {"shipped": base_dict}
    # 后续变体 / 合成配置注册到这里，例如：
    #   config_dicts["variant:roulette_cw"] = variant(
    #       base_dict, "马赛回旋 Roulette", direction="cw")

    parsed = {
        key: parse_config(copy.deepcopy(value), root / CONFIG_REL)
        for key, value in config_dicts.items()
    }

    used: dict[str, object] = {}
    cases = []
    seen: set[str] = set()
    for case in CASES + BOUNDARY_CASES:
        case_id = case["id"]
        if case_id in seen:
            raise SystemExit(f"✗ 夹具 id 重复：{case_id}")
        seen.add(case_id)
        key = case.get("config", "shipped")
        if key not in parsed:
            raise SystemExit(f"✗ {case_id}: config 键 {key!r} 不在 configs 注册表里")
        cases.append(_case_payload(case, parsed[key]))
        used[case_id] = parsed[key]

    payload = {
        "schema_version": 1,
        "source": {
            **{name: rel.as_posix() for name, rel in SOURCE_RELS.items()},
            "sha256": {name: _sha256(root, rel) for name, rel in SOURCE_RELS.items()},
        },
        "meta": {"hz": HZ, "step_ms": STEP_MS},
        "configs": config_dicts,
        "cases": cases,
    }
    _assert_configs_replayable(payload, root, parsed, used)
    return payload


def render(root: Path) -> bytes:
    """夹具的规范字节形态：UTF-8、两空格缩进、键排序、结尾一个换行。"""
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


def _counts(payload: dict) -> tuple[int, int]:
    detector_count = sum(1 for case in payload["cases"] if case["kind"] == "detector")
    runtime_count = sum(1 for case in payload["cases"] if case["kind"] == "runtime")
    return detector_count, runtime_count


def check(root: Path) -> int:
    """只读校验：重新推导后与磁盘夹具逐字节比较，绝不写盘。"""
    target = fixture_path(root)
    if not target.is_file():
        print(
            f"✗ 缺少手势黄金夹具：{FIXTURE_REL.as_posix()}\n"
            "  运行 python3 tools/gen_gesture_golden.py 生成。",
            file=sys.stderr,
        )
        return 1
    expected = render(root)
    actual = target.read_bytes()
    if expected != actual:
        print(
            f"✗ 夹具与 Python 参考不一致：{FIXTURE_REL.as_posix()}\n"
            f"  {_first_difference(expected, actual)}\n"
            "  夹具是生成物，不能手改；运行 python3 tools/gen_gesture_golden.py "
            "重新生成黄金夹具。",
            file=sys.stderr,
        )
        return 1
    detector_count, runtime_count = _counts(build_payload(root))
    print(
        "✓ 手势黄金夹具与 Python 参考一致"
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
        prog="gen_gesture_golden.py",
        description="从 desktop/padskills 推导手势检测器黄金夹具",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "示例:\n"
            "  python3 tools/gen_gesture_golden.py           生成 / 刷新夹具\n"
            "  python3 tools/gen_gesture_golden.py --check   只校验，不写盘\n"
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
