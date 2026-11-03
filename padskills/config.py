"""skills_config.json 的解析、校验与默认配置。

这里是"引擎"与"配置"的分界线：本文件只负责把 JSON 变成引擎直接消费的数据结构，
所有"花式动作规则"都写在 skills_config.json 里，不需要改 Python 代码。
"""

from __future__ import annotations

import json
import os
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from .geometry import norm_deg

__all__ = [
    "Pulse", "Step", "Skill", "InputConfig", "RumbleConfig", "AppConfig",
    "DEFAULT_CONFIG", "load_config", "dump_default_config",
    "resolve_direction", "direction_name", "parse_step", "DEFAULT_CONFIG_FILENAME",
    "APP_NAME", "is_frozen", "app_dir", "user_config_dir",
    "default_config_path", "ensure_user_config",
]

DEFAULT_CONFIG_FILENAME = "skills_config.json"
APP_NAME = "FifaSkillTrainer"


# ---------------------------------------------------------------------------
# 配置放在哪里
# ---------------------------------------------------------------------------

def is_frozen() -> bool:
    """是不是 PyInstaller / 打包后的可执行文件。"""
    return bool(getattr(sys, "frozen", False))


def app_dir() -> Path:
    """开发态 = 项目根目录；打包态 = 可执行文件所在目录。"""
    if is_frozen():
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parent.parent


def user_config_dir() -> Path:
    """打包后配置要写到用户目录——.app / Program Files 里通常没有写权限，
    而且写进去会破坏 macOS 的签名。"""
    if sys.platform == "win32":
        base = os.environ.get("APPDATA")
        if base:
            return Path(base) / APP_NAME
        return Path.home() / "AppData" / "Roaming" / APP_NAME
    if sys.platform == "darwin":
        return Path.home() / "Library" / "Application Support" / APP_NAME
    base = os.environ.get("XDG_CONFIG_HOME")
    return (Path(base) if base else Path.home() / ".config") / APP_NAME


def default_config_path() -> Path:
    """默认配置文件路径。开发态保持在项目根目录，保持现有习惯。"""
    if is_frozen():
        return user_config_dir() / DEFAULT_CONFIG_FILENAME
    return app_dir() / DEFAULT_CONFIG_FILENAME


def ensure_user_config(path: Optional[Path] = None) -> Path:
    """打包运行：首次启动时把默认配置写到用户目录，之后用户可以直接编辑。"""
    path = Path(path) if path is not None else default_config_path()
    if not path.exists():
        try:
            path.parent.mkdir(parents=True, exist_ok=True)
            dump_default_config(path)
        except OSError:
            # 写不进去就退回内置默认配置，至少还能跑
            pass
    return path


# ---------------------------------------------------------------------------
# 方向名称 -> 角度
# ---------------------------------------------------------------------------

DIRECTION_ALIASES: Dict[str, float] = {
    "up": 0.0, "forward": 0.0, "fwd": 0.0, "front": 0.0, "north": 0.0,
    "前": 0.0, "上": 0.0, "正前": 0.0, "前方": 0.0,
    "upright": 45.0, "forwardright": 45.0, "前右": 45.0, "右上": 45.0,
    "right": 90.0, "east": 90.0, "右": 90.0, "正右": 90.0,
    "downright": 135.0, "backright": 135.0, "后右": 135.0, "右下": 135.0,
    "down": 180.0, "back": 180.0, "backward": 180.0, "south": 180.0,
    "rear": 180.0, "后": 180.0, "下": 180.0, "正后": 180.0, "后方": 180.0,
    "downleft": 225.0, "backleft": 225.0, "后左": 225.0, "左下": 225.0,
    "left": 270.0, "west": 270.0, "左": 270.0, "正左": 270.0,
    "upleft": 315.0, "forwardleft": 315.0, "前左": 315.0, "左上": 315.0,
}

# 反向查表用（用于打印轨迹详情）
_CARDINAL_NAMES = {
    0.0: "前", 45.0: "前右", 90.0: "右", 135.0: "后右",
    180.0: "后", 225.0: "后左", 270.0: "左", 315.0: "前左",
}


def resolve_direction(value: Any) -> float:
    """把配置里的方向写法（名称 / 数字 / 中文）解析成角度。"""
    if isinstance(value, bool):  # bool 是 int 的子类，先挡掉
        raise ValueError(f"方向不能是布尔值: {value!r}")
    if isinstance(value, (int, float)):
        return norm_deg(float(value))
    key = str(value).strip().lower()
    for ch in ("_", "-", " ", "\t"):
        key = key.replace(ch, "")
    if key in DIRECTION_ALIASES:
        return DIRECTION_ALIASES[key]
    try:
        return norm_deg(float(key))
    except ValueError:
        raise ValueError(
            f"无法识别的方向 {value!r}。可用名称: "
            f"up/forward, right, down/back, left, 以及四个斜向 (upright/…)，"
            f"也可以直接写角度数字，例如 0 / 90 / 180 / 270。"
        ) from None


def direction_name(angle: float) -> str:
    """角度 -> 便于阅读的中文方向名。"""
    a = norm_deg(angle)
    best = min(_CARDINAL_NAMES, key=lambda k: abs(((a - k + 180) % 360) - 180))
    diff = abs(((a - best + 180) % 360) - 180)
    return _CARDINAL_NAMES[best] if diff <= 22.5 else f"{a:.0f}°"


@dataclass(frozen=True)
class Step:
    """方向序列里的一步。

    angles   允许的角度集合（长度 > 1 表示"任一"）
    hold_ms  需要把这个方向保持多久才算完成这一步（0 = 点拨一下即可）
    """
    angles: Tuple[float, ...]
    hold_ms: float = 0.0

    def label(self) -> str:
        return "/".join(direction_name(a) for a in self.angles)


def parse_step(value: Any) -> Step:
    """解析一个序列步骤。支持三种写法：

        "forward"                                        单一方向
        ["left", "right"]                                任一方向
        {"direction": ["left","right"], "hold_ms": 500}  需要保持一段时间
    """
    if isinstance(value, dict):
        direction = value.get("direction", value.get("dir"))
        if direction is None:
            raise ValueError(f"步骤 {value!r} 缺少 direction 字段")
        try:
            hold_ms = float(value.get("hold_ms", 0))
        except (TypeError, ValueError):
            raise ValueError(f"步骤的 hold_ms 必须是数字，收到 {value.get('hold_ms')!r}") from None
        if hold_ms < 0:
            raise ValueError(f"步骤的 hold_ms 不能是负数，收到 {hold_ms}")
        inner = parse_step(direction)
        return Step(inner.angles, hold_ms)

    group = value if isinstance(value, (list, tuple)) else [value]
    if not group:
        raise ValueError("步骤不能是空数组")
    return Step(tuple(resolve_direction(g) for g in group), 0.0)


# ---------------------------------------------------------------------------
# 数据结构
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class Pulse:
    """一次震动。low = 低频大马达(左)，high = 高频小马达(右)，取值 0.0~1.0。"""
    low: float = 0.8
    high: float = 0.0
    duration_ms: int = 120
    gap_ms: int = 0


@dataclass
class Skill:
    """一个花式动作规则。"""
    name: str
    kind: str                                  # "arc" | "sequence" | "taps"
    enabled: bool = True
    relative_to_ls: bool = False
    required_buttons: Tuple[str, ...] = ()
    button_mode: str = "all"                   # "all" | "any"
    params: Dict[str, Any] = field(default_factory=dict)
    pattern: Tuple[Pulse, ...] = (Pulse(),)
    cooldown_ms: int = 400
    raw: Dict[str, Any] = field(default_factory=dict)

    def rumble_summary(self) -> str:
        if len(self.pattern) == 1:
            p = self.pattern[0]
            return f"单震 low={p.low:.2f} high={p.high:.2f} {p.duration_ms}ms"
        return f"{len(self.pattern)} 连震"


@dataclass
class InputConfig:
    poll_hz: int = 250
    deadzone: float = 0.08
    ls_facing_threshold: float = 0.35           # 超过此幅度才更新"球员面朝方向"
    initial_facing_deg: float = 0.0
    trigger_threshold: float = 0.35             # 扳机按到多深算"按下"
    joystick_index: int = 0
    axis_layout: Optional[Dict[str, Any]] = None   # 手动覆盖，null = 自动
    invert: Dict[str, bool] = field(default_factory=dict)
    # 手动反转轴方向，例如 {"rs_y": true}。映射表偶尔和实物对不上，
    # 这是不写死整套 axis_layout 就能纠正"上下反了"的开关。
    button_names: Optional[Dict[str, Any]] = None  # 手动覆盖 {名字: 索引}
    calibration_ms: int = 250                   # 启动时扳机静止值采样时长
    idle_reset_ms: int = 250                    # 右摇杆静止这么久后清空未完成动作
    gesture_release_ms: int = 150               # 一次触发后，回中这么久才允许下一个动作


@dataclass
class RumbleConfig:
    enabled: bool = True
    backend: str = "auto"        # auto | pygame | sdl2 | xinput | none
    startup_test: bool = True
    startup_test_strength: float = 0.55
    startup_test_ms: int = 160


@dataclass
class AppConfig:
    input: InputConfig = field(default_factory=InputConfig)
    rumble: RumbleConfig = field(default_factory=RumbleConfig)
    skills: List[Skill] = field(default_factory=list)
    global_cooldown_ms: int = 60
    path: Optional[Path] = None

    def enabled_skills(self) -> List[Skill]:
        return [s for s in self.skills if s.enabled]


# ---------------------------------------------------------------------------
# 默认配置（单一事实来源：skills_config.json 由 --write-config 从这里生成）
# ---------------------------------------------------------------------------

DEFAULT_CONFIG: Dict[str, Any] = {
    "_readme": [
        "FIFA / EA FC 花式动作搓招监测 —— 配置文件。",
        "改完直接存盘，重新运行程序即可生效，无需改 Python 代码。",
        "",
        "每个动作的字段：",
        "  name            动作名称，随便起",
        "  enabled         true / false，是否启用",
        "  type            'arc'（摇杆画弧）、'sequence'（方向点拨序列）或 'taps'（按键双击）",
        "  relative_to_ls  true = 方向以左摇杆朝向为基准(0°=球员正前方)；false = 屏幕绝对方向",
        "  required_button 可选修饰键，如 'L1'；不需要就写 null。也可写数组如 ['L1','R1']",
        "  button_mode     required_button 是数组时：'all' 全部按住 / 'any' 任一按住",
        "  params          各类型自己的参数，见下面两个示例",
        "  rumble          震动参数，目前统一是低频 120ms 单震",
        "  cooldown_ms     触发后冷却，防止同一次搓招连震",
        "",
        "arc（画弧）params：",
        "  start_angle      画弧的**起点**必须是哪个方向（可写方向名或角度），null = 不限制。",
        "                   这是区分动作的关键：从前往侧转是踩单车，从后往前转才是马赛回旋。",
        "  start_tolerance  起点的容错夹角，默认 60",
        "  end_angle        画弧的**终点**方向，可写一个方向或数组（如 [90, 270]），null = 不限制。",
        "  end_tolerance    终点的容错夹角，默认 60",
        "  enter_threshold  右摇杆推到多大幅度算'开始画弧'（0~1）",
        "  exit_threshold   掉到多低算'松手结束'（要比 enter 小，做迟滞）",
        "  min_angle/max_angle      累计旋转角度的合格区间（度）",
        "  min_duration_ms/max_duration_ms  完成时间窗口（毫秒）。低于 min 视为太快，作废。",
        "  idle_timeout_ms  停在原地不转超过这么久就作废（默认 180），避免停顿后接着算同一个动作。",
        "  release_hold_ms  触发/作废后要连续回中这么久才允许下一段（默认 120）。",
        "  direction        'any' 任意方向 / 'cw' 只认顺时针 / 'ccw' 只认逆时针",
        "",
        "sequence（方向序列）params：",
        "  steps            方向列表，如 ['forward','back']。每个元素有三种写法：",
        "                     'forward'                                  单一方向",
        "                     ['left','right']                           任一方向",
        "                     {'direction':['left','right'],'hold_ms':500}  需要保持一段时间",
        "                   hold_ms 从右摇杆推过 enter_threshold 那一刻起算。真手推杆有几十毫秒行程，",
        "                   '推住半秒'实际只记到 450ms 左右，所以阈值要留 50~100ms 余量。",
        "                   可用名称：forward/up 前, back/down 后, left 左, right 右,",
        "                              upright/downright/downleft/upleft 四个斜向，",
        "                             也可以直接写角度数字 0/90/180/270。",
        "  tolerance_deg    每个方向的容错夹角，默认 35",
        "  enter_threshold  推过这个幅度才算一次有效点拨，默认 0.65",
        "  release_threshold 回落到这个幅度以下才算'松手'，默认 0.35",
        "  min_duration_ms  整个序列至少要花这么久（默认 250），太快游戏里根本搓不出来。",
        "  max_duration_ms  整个序列必须在多久内完成（要大于各步 hold_ms 之和）",
        "  idle_timeout_ms  两步之间停顿超过这么久就清空进度（默认 250）。",
        "  require_neutral_between_steps  两步之间是否要求摇杆回中（默认 true，即真正的'点拨'）",
        "  release_hold_ms  已触发过的动作，要连续松开多久才允许再触发（默认 150）。",
        "                   防止摇杆在阈值附近抖一下就重新武装，出现'按住不放却一直震'。",
        "",
        "taps（按键双击/连按）params：",
        "  button           要连按的键，如 'X'；也可用 A/B/Y、方向键名等规范名。",
        "  min_interval_ms  两下按键之间的最短间隔（默认 400）。",
        "  max_interval_ms  两下按键之间的最长间隔（默认 600）。",
        "  timeout_grace_ms 超过上限后再等这么久仍没有第二下，就报'太慢'（默认 150）。",
        "  release_hold_ms  成功/失败后要松开按键这么久才允许下一次（默认 120）。",
        "  配合 required_button 使用：例如 required_button='RB' + button='X'",
        "  = 按住 RB，在 400~600ms 内按两下 X。这类动作与右摇杆、球员朝向无关。",
        "  modifier_options 可选：给用户切换按住哪个键，如 ['RB','RT']；",
        "                   默认选中的键仍写在 required_button 里。",
        "",
        "rumble：目前所有动作统一用低频 120ms 单震，改这几个数就行：",
        "  {\"low\": 0.8, \"high\": 0.0, \"duration_ms\": 120}",
        "  low  = 低频大马达（沉闷、有力），high = 高频小马达（清脆、偏弱），都是 0.0~1.0",
        "  嫌弱就调大 low（最大 1.0），嫌长就调小 duration_ms。",
        "  引擎一次只播一个脉冲，不会排队连震。",
        "",
        "input.invert：如果某个摇杆方向和实物相反（比如右摇杆上推却显示成后），",
        "  在这里单独翻转，不用重写整套 axis_layout。例：{\"rs_y\": true}",
        "  可用键：ls_x / ls_y / rs_x / rs_y。先跑 --debug 看角度再改。",
    ],

    "input": {
        "poll_hz": 250,
        "deadzone": 0.08,
        "ls_facing_threshold": 0.35,
        "initial_facing_deg": 0,
        "trigger_threshold": 0.35,
        "joystick_index": 0,
        "axis_layout": None,
        "invert": {},
        "button_names": None,
        "calibration_ms": 250,
        "idle_reset_ms": 250,
        "gesture_release_ms": 150,
    },

    "rumble": {
        "enabled": True,
        "backend": "auto",
        "startup_test": True,
        "startup_test_strength": 0.55,
        "startup_test_ms": 160,
    },

    "global_cooldown_ms": 60,

    "skills": [
        {
            "name": "马赛回旋 Roulette",
            "enabled": True,
            "type": "arc",
            "relative_to_ls": True,
            "required_button": None,
            "params": {
                "start_angle": 180,
                "start_tolerance": 65,
                "end_angle": 0,
                "end_tolerance": 80,
                "enter_threshold": 0.72,
                "exit_threshold": 0.52,
                "min_angle": 70,
                "max_angle": 230,
                "min_duration_ms": 250,
                "max_duration_ms": 600,
                "idle_timeout_ms": 250,
                "release_hold_ms": 120,
                "direction": "any",
            },
            "rumble": {"low": 0.8, "high": 0.0, "duration_ms": 120},
            "cooldown_ms": 400,
        },
        {
            "name": "踩单车 Stepover",
            "enabled": True,
            "type": "arc",
            "relative_to_ls": True,
            "required_button": None,
            "params": {
                "start_angle": 0,
                "start_tolerance": 55,
                "end_angle": [90, 270],
                "end_tolerance": 55,
                "enter_threshold": 0.72,
                "exit_threshold": 0.52,
                "min_angle": 70,
                "max_angle": 135,
                "min_duration_ms": 250,
                "max_duration_ms": 600,
                "idle_timeout_ms": 250,
                "release_hold_ms": 120,
                "direction": "any",
            },
            "rumble": {"low": 0.8, "high": 0.0, "duration_ms": 120},
            "cooldown_ms": 350,
        },
        {
            "name": "磕球过人 Heel-to-Heel",
            "enabled": True,
            "type": "sequence",
            "relative_to_ls": True,
            "required_button": None,
            "params": {
                "steps": ["forward", "back"],
                "tolerance_deg": 35,
                "enter_threshold": 0.65,
                "release_threshold": 0.35,
                "min_duration_ms": 250,
                "max_duration_ms": 600,
                "idle_timeout_ms": 250,
                "release_hold_ms": 150,
                "require_neutral_between_steps": True,
            },
            "rumble": {"low": 0.8, "high": 0.0, "duration_ms": 120},
            "cooldown_ms": 350,
        },
        {
            "name": "油炸丸子 La Croqueta",
            "enabled": True,
            "type": "sequence",
            # 油炸丸子：右摇杆以左摇杆朝向为基准，偏左/偏右各 90°（即面朝方向的左右两侧）。
            # 所以必须相对左摇杆判定——跑动方向变了，输入方向也跟着转。
            "relative_to_ls": True,
            "required_button": "L1",
            "params": {
                "steps": [
                    # "右"/"左" = 相对左摇杆 +90° / -90°（即 90° / 270°，正侧向）。
                    # 计时从推过 enter_threshold 起算，推杆本身还有几十毫秒行程，
                    # 所以 350ms 阈值对应"推住约半秒"的真实手感。
                    {"direction": ["右", "左"], "hold_ms": 350}
                ],
                "tolerance_deg": 10,
                "enter_threshold": 0.6,
                "release_threshold": 0.3,
                "min_duration_ms": 250,
                "max_duration_ms": 600,
                "idle_timeout_ms": 350,
                "release_hold_ms": 150,
                "require_neutral_between_steps": True,
            },
            "rumble": {"low": 0.8, "high": 0.0, "duration_ms": 120},
            "cooldown_ms": 450,
        },
        {
            "name": "绿色搓射 Green Finesse",
            "enabled": True,
            "type": "taps",
            # 绿色搓射：按住 RB，按两下 X，两下之间间隔 400~500ms。
            # 整个过程 RB 不能松开；和右摇杆/球员朝向无关。
            "relative_to_ls": False,
            "required_button": "RB",
            "params": {
                "button": "X",
                "min_interval_ms": 400,
                "max_interval_ms": 600,
                "timeout_grace_ms": 150,
                "release_hold_ms": 120,
                "modifier_options": ["RB", "RT"],
            },
            "rumble": {"low": 0.8, "high": 0.0, "duration_ms": 120},
            "cooldown_ms": 450,
        },
    ],
}


# ---------------------------------------------------------------------------
# 解析
# ---------------------------------------------------------------------------

def _clamp01(value: Any, field_name: str) -> float:
    try:
        v = float(value)
    except (TypeError, ValueError):
        raise ValueError(f"{field_name} 必须是数字，收到 {value!r}") from None
    if not 0.0 <= v <= 1.0:
        raise ValueError(f"{field_name} 必须在 0.0~1.0 之间，收到 {v}")
    return v


def _parse_pulses(raw: Any, skill_name: str) -> Tuple[Pulse, ...]:
    if raw is None:
        return (Pulse(),)

    if isinstance(raw, dict) and "pattern" in raw:
        items = raw["pattern"]
    elif isinstance(raw, list):
        items = raw
    elif isinstance(raw, dict):
        items = [raw]
    else:
        raise ValueError(f"动作 {skill_name!r} 的 rumble 字段无法解析: {raw!r}")

    if not isinstance(items, list) or not items:
        raise ValueError(f"动作 {skill_name!r} 的 rumble.pattern 必须是非空数组")

    pulses: List[Pulse] = []
    for i, item in enumerate(items):
        if not isinstance(item, dict):
            raise ValueError(f"动作 {skill_name!r} 的 rumble.pattern[{i}] 必须是对象")
        pulses.append(Pulse(
            low=_clamp01(item.get("low", 0.8), f"{skill_name}.rumble.low"),
            high=_clamp01(item.get("high", 0.0), f"{skill_name}.rumble.high"),
            duration_ms=max(1, int(item.get("duration_ms", 120))),
            gap_ms=max(0, int(item.get("gap_ms", 0))),
        ))
    return tuple(pulses)


def _parse_required_buttons(raw: Any, mode_raw: Any, skill_name: str) -> Tuple[Tuple[str, ...], str]:
    from .input_source import canonical_button  # 延迟导入避免循环依赖

    if raw is None:
        return (), "all"
    values = raw if isinstance(raw, (list, tuple)) else [raw]
    names = tuple(canonical_button(v) for v in values if str(v).strip())
    mode = str(mode_raw or "all").strip().lower()
    if mode not in ("all", "any"):
        raise ValueError(f"动作 {skill_name!r} 的 button_mode 只能是 'all' 或 'any'，收到 {mode!r}")
    return names, mode


def _validate_common_timing(params: Dict[str, Any], name: str) -> None:
    """校验两类识别器共用的时间参数。"""
    for key in ("idle_timeout_ms", "release_hold_ms"):
        if key in params:
            value = float(params[key])
            if value < 0:
                raise ValueError(f"动作 {name!r} 的 {key} 不能是负数，收到 {value}")
    if "idle_timeout_ms" in params and float(params["idle_timeout_ms"]) <= 0:
        raise ValueError(f"动作 {name!r} 的 idle_timeout_ms 必须大于 0")
    if "motion_min_delta_deg" in params and float(params["motion_min_delta_deg"]) <= 0:
        raise ValueError(f"动作 {name!r} 的 motion_min_delta_deg 必须大于 0")


def _parse_skill(raw: Any, index: int) -> Skill:
    if not isinstance(raw, dict):
        raise ValueError(f"skills[{index}] 必须是对象")

    name = str(raw.get("name") or f"未命名动作 #{index + 1}")
    kind = str(raw.get("type", "")).strip().lower()
    if kind not in ("arc", "sequence", "taps"):
        raise ValueError(
            f"动作 {name!r} 的 type 必须是 'arc'、'sequence' 或 'taps'，"
            f"收到 {raw.get('type')!r}"
        )

    params = raw.get("params") or {}
    if not isinstance(params, dict):
        raise ValueError(f"动作 {name!r} 的 params 必须是对象")

    if kind == "sequence":
        steps = params.get("steps")
        if not isinstance(steps, list) or not steps:
            raise ValueError(f"动作 {name!r} 是 sequence 类型，params.steps 必须是非空数组")
        # 提前校验方向写法，配置写错时立刻报错而不是运行中才发现
        parsed: List[Step] = []
        for i, step in enumerate(steps):
            try:
                parsed.append(parse_step(step))
            except ValueError as exc:
                raise ValueError(f"动作 {name!r} 的 steps[{i}]: {exc}") from None
        # 各步保持时间之和必须小于总时长窗口，否则这个动作永远不可能触发
        total_hold = sum(s.hold_ms for s in parsed)
        max_dur = float(params.get("max_duration_ms", 700))
        min_dur = float(params.get("min_duration_ms", 300))
        if max_dur <= min_dur:
            raise ValueError(
                f"动作 {name!r}: max_duration_ms ({max_dur:.0f}ms) 必须大于 "
                f"min_duration_ms ({min_dur:.0f}ms)"
            )
        if total_hold >= max_dur:
            raise ValueError(
                f"动作 {name!r}: 各步骤 hold_ms 合计 {total_hold:.0f}ms 已经不小于 "
                f"max_duration_ms ({max_dur:.0f}ms)，这个动作永远无法触发，"
                f"请把 max_duration_ms 调大。"
            )
        _validate_common_timing(params, name)

    if kind == "arc":
        lo = float(params.get("min_angle", 150))
        hi = float(params.get("max_angle", 220))
        if hi <= lo:
            raise ValueError(f"动作 {name!r} 的 max_angle ({hi}) 必须大于 min_angle ({lo})")
        min_dur = float(params.get("min_duration_ms", 300))
        max_dur = float(params.get("max_duration_ms", 700))
        if max_dur <= min_dur:
            raise ValueError(
                f"动作 {name!r}: max_duration_ms ({max_dur:.0f}ms) 必须大于 "
                f"min_duration_ms ({min_dur:.0f}ms)"
            )
        _validate_common_timing(params, name)
        for key in ("start_angle", "end_angle", "end_angles"):
            raw_dir = params.get(key)
            if raw_dir is None:
                continue
            values = raw_dir if isinstance(raw_dir, (list, tuple)) else [raw_dir]
            if not values:
                raise ValueError(f"动作 {name!r} 的 {key} 不能是空数组")
            for value in values:
                try:
                    resolve_direction(value)
                except ValueError as exc:
                    raise ValueError(f"动作 {name!r} 的 {key}: {exc}") from None

    if kind == "taps":
        from .input_source import canonical_button
        try:
            canonical_button(params.get("button", "X"))
        except ValueError as exc:
            raise ValueError(f"动作 {name!r} 的 params.button: {exc}") from None
        min_i = float(params.get("min_interval_ms", 400))
        max_i = float(params.get("max_interval_ms", 600))
        if min_i < 0:
            raise ValueError(f"动作 {name!r}: min_interval_ms 不能是负数")
        if max_i <= min_i:
            raise ValueError(
                f"动作 {name!r}: max_interval_ms ({max_i:.0f}) 必须大于 "
                f"min_interval_ms ({min_i:.0f})"
            )
        options = params.get("modifier_options")
        if options is not None:
            if not isinstance(options, (list, tuple)) or not options:
                raise ValueError(
                    f"动作 {name!r} 的 params.modifier_options 必须是非空数组")
            try:
                opts = [canonical_button(v) for v in options]
            except ValueError as exc:
                raise ValueError(
                    f"动作 {name!r} 的 params.modifier_options: {exc}") from None
            if len(set(opts)) != len(opts):
                raise ValueError(
                    f"动作 {name!r} 的 params.modifier_options 不能有重复按键")
            params["modifier_options"] = opts
        _validate_common_timing(params, name)

    buttons, mode = _parse_required_buttons(
        raw.get("required_button", raw.get("required_buttons")),
        raw.get("button_mode"),
        name,
    )

    options = params.get("modifier_options")
    if options:
        if not buttons:
            raise ValueError(
                f"动作 {name!r}: 配了 modifier_options 就必须同时写 required_button")
        missing = [b for b in buttons if b not in options]
        if missing:
            raise ValueError(
                f"动作 {name!r}: required_button {missing[0]!r} 不在 "
                f"modifier_options {options!r} 里")

    return Skill(
        name=name,
        kind=kind,
        enabled=bool(raw.get("enabled", True)),
        relative_to_ls=bool(raw.get("relative_to_ls", False)),
        required_buttons=buttons,
        button_mode=mode,
        params=params,
        pattern=_parse_pulses(raw.get("rumble"), name),
        cooldown_ms=max(0, int(raw.get("cooldown_ms", 400))),
        raw=raw,
    )


def _parse_input(raw: Any) -> InputConfig:
    raw = raw or {}
    if not isinstance(raw, dict):
        raise ValueError("input 字段必须是对象")
    cfg = InputConfig()
    cfg.poll_hz = max(30, min(1000, int(raw.get("poll_hz", cfg.poll_hz))))
    cfg.deadzone = _clamp01(raw.get("deadzone", cfg.deadzone), "input.deadzone")
    cfg.ls_facing_threshold = _clamp01(
        raw.get("ls_facing_threshold", cfg.ls_facing_threshold), "input.ls_facing_threshold")
    cfg.initial_facing_deg = float(raw.get("initial_facing_deg", cfg.initial_facing_deg))
    cfg.trigger_threshold = _clamp01(
        raw.get("trigger_threshold", cfg.trigger_threshold), "input.trigger_threshold")
    cfg.joystick_index = max(0, int(raw.get("joystick_index", cfg.joystick_index)))
    cfg.calibration_ms = max(0, min(3000, int(raw.get("calibration_ms", cfg.calibration_ms))))
    cfg.idle_reset_ms = max(0, min(5000, int(raw.get("idle_reset_ms", cfg.idle_reset_ms))))
    cfg.gesture_release_ms = max(
        0, min(5000, int(raw.get("gesture_release_ms", cfg.gesture_release_ms))))

    layout = raw.get("axis_layout")
    if layout is not None and not isinstance(layout, dict):
        raise ValueError("input.axis_layout 必须是对象或 null")
    cfg.axis_layout = layout

    invert = raw.get("invert")
    if invert is not None and not isinstance(invert, dict):
        raise ValueError('input.invert 必须是对象或 null，例如 {"rs_y": true}')
    if invert:
        allowed = ("ls_x", "ls_y", "rs_x", "rs_y")
        for key, value in invert.items():
            if str(key).strip().lower() not in allowed:
                raise ValueError(
                    f"input.invert 的键只能是 {' / '.join(allowed)}，收到 {key!r}")
            if not isinstance(value, bool):
                raise ValueError(f"input.invert.{key} 必须是 true / false")
        cfg.invert = {str(k).strip().lower(): v for k, v in invert.items()}

    names = raw.get("button_names")
    if names is not None and not isinstance(names, dict):
        raise ValueError("input.button_names 必须是对象或 null")
    cfg.button_names = names
    return cfg


def _parse_rumble(raw: Any) -> RumbleConfig:
    raw = raw or {}
    if not isinstance(raw, dict):
        raise ValueError("rumble 字段必须是对象")
    cfg = RumbleConfig()
    cfg.enabled = bool(raw.get("enabled", cfg.enabled))
    backend = str(raw.get("backend", cfg.backend)).strip().lower()
    if backend not in ("auto", "pygame", "sdl2", "xinput", "none"):
        raise ValueError(
            f"rumble.backend 只能是 auto/pygame/sdl2/xinput/none，收到 {backend!r}")
    cfg.backend = backend
    cfg.startup_test = bool(raw.get("startup_test", cfg.startup_test))
    cfg.startup_test_strength = _clamp01(
        raw.get("startup_test_strength", cfg.startup_test_strength),
        "rumble.startup_test_strength")
    cfg.startup_test_ms = max(10, int(raw.get("startup_test_ms", cfg.startup_test_ms)))
    return cfg


def parse_config(data: Dict[str, Any], path: Optional[Path] = None) -> AppConfig:
    """把已解析的 JSON 字典变成 AppConfig（会做完整校验）。"""
    if not isinstance(data, dict):
        raise ValueError("配置文件根节点必须是 JSON 对象")

    skills_raw = data.get("skills")
    if not isinstance(skills_raw, list) or not skills_raw:
        raise ValueError("配置文件里 skills 必须是非空数组")

    skills = [_parse_skill(item, i) for i, item in enumerate(skills_raw)]

    seen: Dict[str, int] = {}
    for s in skills:
        seen[s.name] = seen.get(s.name, 0) + 1
    dupes = [n for n, c in seen.items() if c > 1]
    if dupes:
        raise ValueError(f"动作名称重复: {', '.join(dupes)}（名称会用于日志区分，请改成唯一的）")

    return AppConfig(
        input=_parse_input(data.get("input")),
        rumble=_parse_rumble(data.get("rumble")),
        skills=skills,
        global_cooldown_ms=max(0, int(data.get("global_cooldown_ms", 60))),
        path=path,
    )


def load_config(path: Optional[Path] = None) -> AppConfig:
    """从磁盘加载配置；文件不存在时使用内置默认配置。"""
    if path is None:
        path = Path(DEFAULT_CONFIG_FILENAME)
    path = Path(path)

    if not path.exists():
        return parse_config(json.loads(json.dumps(DEFAULT_CONFIG)), None)

    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        raise SystemExit(f"读取配置文件失败: {path}\n  {exc}") from None

    try:
        data = json.loads(text)
    except json.JSONDecodeError as exc:
        raise SystemExit(
            f"配置文件 JSON 语法错误: {path}\n"
            f"  第 {exc.lineno} 行 第 {exc.colno} 列: {exc.msg}\n"
            f"  提示：JSON 不支持 // 注释，也不允许最后一个元素后面多写逗号。"
        ) from None

    try:
        return parse_config(data, path)
    except ValueError as exc:
        raise SystemExit(f"配置文件内容有误: {path}\n  {exc}") from None


def dump_default_config(path: Path) -> Path:
    """把内置默认配置写到磁盘（skills_config.json 就是这么生成的）。"""
    path = Path(path)
    text = json.dumps(DEFAULT_CONFIG, ensure_ascii=False, indent=2)
    path.write_text(text + "\n", encoding="utf-8")
    return path
