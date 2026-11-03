"""角度与向量工具。

本项目全局统一使用如下角度约定（单位：度，范围 [0, 360)）：

    0°   = 上    （朝对方球门，即球员的"正前方"）
    90°  = 右
    180° = 下    （正后方）
    270° = 左

所以角度增大 = 屏幕上的顺时针方向。

手柄原始坐标是 SDL / pygame 约定：x 向右为正，y **向下**为正。
所有角度换算都在 angle_of() 里一次性处理掉，其余代码只跟上面的约定打交道。
"""

from __future__ import annotations

import math

__all__ = ["norm_deg", "signed_delta", "angle_diff", "angle_of", "magnitude"]


def norm_deg(angle: float) -> float:
    """把任意角度归一化到 [0, 360)。"""
    return angle % 360.0


def signed_delta(a_from: float, a_to: float) -> float:
    """从 a_from 旋转到 a_to 的**最短带符号**旋转量，范围 (-180, 180]。

    正值 = 顺时针（对应角度增大的方向）。
    """
    return ((a_to - a_from + 180.0) % 360.0) - 180.0


def angle_diff(a: float, b: float) -> float:
    """两个角度之间的最小夹角，范围 [0, 180]。"""
    return abs(signed_delta(a, b))


def angle_of(x: float, y: float) -> float:
    """由摇杆原始坐标求角度。x 向右为正，y 向下为正。

    摇杆居中（或落在死区内）时返回 0.0 而不是让 atan2 给出无意义的值——
    注意 atan2(0.0, -0.0) 会得到 π（180°），居中时显示成"正后方"很误导人。
    """
    if x == 0.0 and y == 0.0:
        return 0.0
    return norm_deg(math.degrees(math.atan2(x, -y)))


def magnitude(x: float, y: float) -> float:
    """摇杆推杆幅度，范围 [0, ~1.41]（斜推角落时会略大于 1）。"""
    return math.hypot(x, y)
