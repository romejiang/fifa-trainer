#!/usr/bin/env python3
"""FIFA / EA FC 花式动作搓招实时监测与震动反馈工具。

用法：
    uv run app.py                       # 打开桌面练习窗口（推荐）
    uv run main.py --gui                # 同上
    uv run main.py                      # 命令行模式，用同目录的 skills_config.json
    uv run main.py --debug              # 实时显示摇杆角度/幅度/按键，用于校准
    uv run main.py --list               # 列出检测到的手柄
    uv run main.py --selftest           # 只做震动自检然后退出
    uv run main.py --write-config       # 生成默认 skills_config.json

先跑 --debug 确认键位，再跑 --selftest 确认震动，最后正常启动挂后台。
"""

from __future__ import annotations

import os
import sys

# 必须在 import pygame 之前设置，否则每次启动都会打印 pygame 的社区横幅
os.environ.setdefault("PYGAME_HIDE_SUPPORT_PROMPT", "1")

# 打包成 windowed 应用时 stdout / stderr 可能是 None
if sys.stdout is None:
    sys.stdout = open(os.devnull, "w", encoding="utf-8")
if sys.stderr is None:
    sys.stderr = open(os.devnull, "w", encoding="utf-8")

# 输出重定向到文件时，默认编码可能是 ANSI 代码页，中文会乱码
if not sys.stdout.isatty():
    try:
        # errors="replace"：万一某个字符在目标编码里不存在，宁可显示成 ? 也不要崩
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

import argparse
import time
from pathlib import Path
from typing import List, Optional

from padskills import __version__
from padskills.config import (
    DEFAULT_CONFIG_FILENAME, AppConfig, Pulse, default_config_path,
    dump_default_config, ensure_user_config, is_frozen, load_config,
    write_config_target,
)
from padskills.engine import Engine
from padskills.input_source import list_devices, open_source
from padskills.rumble import RumbleEngine, build_backends, pick_backend


# ---------------------------------------------------------------------------
# 输出小工具
# ---------------------------------------------------------------------------

def banner(text: str) -> None:
    print()
    print("═" * 62)
    print(f"  {text}")
    print("═" * 62)


def step(text: str) -> None:
    print(f"\n▸ {text}")


def print_controller_hints() -> None:
    """连不上手柄/震动不工作时，按平台给建议。"""
    if sys.platform == "darwin":
        print("  · macOS：系统设置 → 隐私与安全性 → 输入监控，"
              "把终端（或打包后的 App）勾上")
        print("  · 有线连接通常比蓝牙更容易驱动震动")
        print("  · 手柄要先用系统自带的「游戏控制器」面板确认能被识别")
    elif sys.platform == "win32":
        print("  · 试试换一个 USB 口，或把手柄切到 XInput 模式")
        print("  · 有线连接通常比蓝牙更容易驱动震动")
    else:
        print("  · 确认手柄已连接，且有 /dev/input 访问权限")


# ---------------------------------------------------------------------------
# 子命令
# ---------------------------------------------------------------------------

def cmd_list() -> int:
    banner("手柄设备列表")
    devices = list_devices()
    if not devices:
        print("  没有检测到任何手柄。")
        print("  · 确认手柄已开机并连接（USB 线或接收器）")
        print_controller_hints()
        return 1
    for d in devices:
        backend = d.get("backend", "sdl")
        label = f"XInput {d['index']}" if backend == "xinput" else f"SDL {d['index']}"
        print(f"\n  [{label}] {d['name']}")
        print(f"      GUID      : {d['guid']}")
        print(f"      轴/键/帽  : {d['axes']} / {d['buttons']} / {d['hats']}")
        if backend == "xinput":
            print("      布局来源  : 内置 XInput 标准映射")
        else:
            print(f"      布局来源  : "
                  f"{'SDL 映射表（自动识别）' if d['sdl_mapping'] else '静止值分类（SDL 无此设备映射表）'}")
        print(f"      后端      : {'XInput（原生）' if backend == 'xinput' else 'SDL / pygame'}")
        print(f"      震动接口  : {'可用' if d['rumble'] else '不可用'}")
    print("\n  用 --index N 选择设备（Windows 上 XInput 优先），"
          "或改配置里的 input.joystick_index。")
    return 0


def _play_blocking(backend, pulses, label: str) -> None:
    """诊断用：阻塞式播一段震动（正式运行时不会这么干）。"""
    print(f"  ▸ {label}")
    for pulse in pulses:
        try:
            backend.start(pulse.low, pulse.high, pulse.duration_ms)
        except Exception as exc:
            print(f"      调用失败: {exc}")
            return
        time.sleep(pulse.duration_ms / 1000.0)
        try:
            backend.stop()
        except Exception:
            pass
        if pulse.gap_ms:
            time.sleep(pulse.gap_ms / 1000.0)
    time.sleep(0.6)


def cmd_selftest(cfg: AppConfig, joystick_index: int) -> int:
    import pygame

    banner("震动自检")
    # 只初始化需要的子系统：audio 在无声音设备/打包环境里经常初始化失败
    pygame.display.init()
    pygame.joystick.init()

    step("打开手柄")
    try:
        source = open_source(cfg.input, verbose=True)
    except Exception as exc:
        print(f"  失败: {exc}")
        return 1

    joy = getattr(source, "_joy", None)
    step("逐个尝试震动后端（每个后端会震一下，注意手感）")
    candidates = build_backends(
        "auto", joystick=joy,
        joystick_index=getattr(source, "xinput_slot", joystick_index),
        verbose=True)
    if not candidates:
        print("  没有可用的震动后端。")
        source.close()
        return 1
    backend = pick_backend(candidates, strength=0.7, duration_ms=250, verbose=True)

    print()
    if backend is None:
        print("  结论：所有后端都失败，震动不可用。")
        print_controller_hints()
        source.close()
        return 1

    print(f"  结论：推荐后端 = {backend.label}")

    # 震感实验室：同一个马达在不同强度/时长下差别很大，让你自己挑出感觉得到的组合
    step("震感对比（注意哪几下你真正感觉得到）")
    print("     低频=大马达（沉闷有力），高频=小马达（清脆但偏弱）")
    _play_blocking(backend, [Pulse(1.0, 0.0, 300)], "只有低频大马达 1.00 / 300ms")
    _play_blocking(backend, [Pulse(0.0, 1.0, 300)], "只有高频小马达 1.00 / 300ms")
    _play_blocking(backend, [Pulse(1.0, 1.0, 300)], "两个马达一起 1.00 / 300ms")

    step("时长对比（同一个强度，不同时长）")
    for ms in (60, 120, 200):
        _play_blocking(backend, [Pulse(0.5, 0.9, ms)], f"时长 {ms}ms")

    step("各动作当前配置的实际震感")
    for skill in cfg.enabled_skills():
        _play_blocking(backend, skill.pattern, f"{skill.name} —— {skill.rumble_summary()}")

    print()
    print("  提示：如果 60ms 那下几乎感觉不到、200ms 那下很明显，")
    print("        就把 skills_config.json 里对应动作的 duration_ms 调大一些；")
    print("        如果「只有高频」那下很弱、「两个一起」明显，就给 rumble 加上 low 值。")
    backend.close()
    source.close()
    return 0


# ---------------------------------------------------------------------------
# 启动流程
# ---------------------------------------------------------------------------

def print_skill_table(cfg: AppConfig) -> None:
    step(f"已加载 {len(cfg.skills)} 个动作规则（启用 {len(cfg.enabled_skills())} 个）")
    if not cfg.skills:
        return
    width = max(len(s.name) for s in cfg.skills)
    for s in cfg.skills:
        flag = "✓" if s.enabled else "✗"
        scope = "相对左摇杆" if s.relative_to_ls else "绝对方向"
        button = "+".join(s.required_buttons) if s.required_buttons else "无"
        print(f"  {flag} {s.name.ljust(width)}  [{s.kind:8s}] {scope} 修饰键:{button:6s} "
              f"震动:{s.rumble_summary()}")


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        prog="main.py",
        description="FIFA / EA FC 花式动作搓招实时监测与震动反馈",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "示例:\n"
            "  uv run main.py --gui              打开练习窗口\n"
            "  uv run main.py --debug            校准键位\n"
            "  uv run main.py --selftest         检查震动\n"
            "  uv run main.py --feedback         正式运行，并打印失败原因\n"
            "  uv run main.py                    正式运行（只在成功时打印）\n"
        ),
    )
    parser.add_argument("-c", "--config", default=None,
                        help="配置文件路径（默认：开发态 desktop/skills_config.json；"
                             "冻结态用户配置目录）")
    parser.add_argument("--gui", action="store_true", help="打开桌面练习窗口")
    parser.add_argument("--demo", action="store_true",
                        help="GUI 演示模式：不用手柄，循环播放成功和失败的轨迹")
    parser.add_argument("--debug", action="store_true",
                        help="单行实时刷新摇杆角度/幅度与按键编号，用于校准键位")
    parser.add_argument("--trace", action="store_true",
                        help="在 --debug 基础上多显示一行各动作识别器的实时进度")
    parser.add_argument("-v", "--verbose", action="store_true",
                        help="输出完整信息（键位映射、动作参数表、每次触发的轨迹详情）")
    parser.add_argument("--list", action="store_true", help="列出手柄设备后退出")
    parser.add_argument("--selftest", action="store_true", help="只做震动自检后退出")
    parser.add_argument("--write-config", action="store_true",
                        help=f"生成默认配置文件 {DEFAULT_CONFIG_FILENAME} 后退出")
    parser.add_argument("--feedback", action="store_true",
                        help="除了成功，也打印每次失败的原因")
    parser.add_argument("--no-rumble", action="store_true", help="本次运行不震动")
    parser.add_argument("--index", type=int, default=None, help="手柄序号，覆盖配置")
    parser.add_argument("--duration", type=float, default=None,
                        help="只运行指定秒数后自动退出（调试用）")
    parser.add_argument("--version", action="version", version=f"%(prog)s {__version__}")
    args = parser.parse_args(argv)

    # 未传 -c 时，运行期读的仍然是同步出来的桌面副本（desktop/skills_config.json），
    # 只有 --write-config 的写入去向被改成唯一真源 shared/skills_config.json。
    explicit_config = Path(args.config) if args.config else None
    config_path = explicit_config if explicit_config is not None else default_config_path()

    if args.write_config:
        path = dump_default_config(write_config_target(explicit_config))
        print(f"已生成默认配置: {path.resolve()}")
        if not is_frozen():
            print("提示：请运行 python3 tools/sync_config.py "
                  "把真源同步到桌面/移动端副本")
        return 0

    if args.list:
        return cmd_list()

    if args.gui or args.demo:
        from padskills.gui import main_gui
        return main_gui(config_path=str(config_path), index=args.index, demo=args.demo)

    # 打包运行：首次启动把默认配置写到用户目录，之后用户可以直接编辑
    if is_frozen():
        ensure_user_config(config_path)

    cfg = load_config(config_path)
    if args.index is not None:
        cfg.input.joystick_index = args.index
    if args.no_rumble:
        cfg.rumble.enabled = False

    verbose = args.verbose

    if args.selftest:
        banner(f"FIFA 花式动作搓招监测 v{__version__}")
        return cmd_selftest(cfg, cfg.input.joystick_index)

    import pygame
    # 只初始化真正需要的子系统：audio 在打包后的应用里经常是故障源
    pygame.display.init()
    pygame.joystick.init()

    try:
        source = open_source(cfg.input, verbose=verbose or args.debug)
    except Exception as exc:
        banner(f"FIFA 花式动作搓招监测 v{__version__}")
        print(f"连接手柄失败: {exc}")
        return 1

    rumble_engine = RumbleEngine(None, enabled=False)
    rumble_label = "已关闭"
    if cfg.rumble.enabled:
        joy = getattr(source, "_joy", None)
        candidates = build_backends(
            cfg.rumble.backend, joystick=joy,
            joystick_index=getattr(source, "xinput_slot", cfg.input.joystick_index),
            verbose=verbose)
        if candidates:
            if cfg.rumble.startup_test:
                # 自检会真震一下，这就是"连接成功"的提示
                backend = pick_backend(
                    candidates,
                    strength=cfg.rumble.startup_test_strength,
                    duration_ms=cfg.rumble.startup_test_ms,
                    verbose=verbose,
                )
            else:
                backend = candidates[0]
            if backend is not None:
                rumble_engine = RumbleEngine(backend, enabled=True)
                rumble_engine.start()
                # 后端标签里带的设备名跟上一行重复，去掉
                rumble_label = backend.label.split(" [")[0]
            else:
                rumble_label = "不可用（跑 --selftest 排查）"
        else:
            rumble_label = "不可用（跑 --selftest 排查）"

    # ---- 启动信息：默认只留 4 行，详细内容看 --verbose ----
    print(f"FIFA 花式动作搓招监测 v{__version__}")
    print(f"手柄 {source.name}  |  震动 {rumble_label}")
    names = [s.name.split(" (")[0] for s in cfg.enabled_skills()]
    print(f"动作 {len(names)} 个: {' / '.join(names)}")
    if verbose:
        print(f"配置文件 {cfg.path.resolve() if cfg.path else '（内置默认配置）'}"
              f"  |  {cfg.input.poll_hz}Hz")
        print_skill_table(cfg)
    print("Ctrl+C 退出。" + ("（调试模式：推摇杆看角度、按键看编号）" if args.debug else ""))
    print()

    engine = Engine(cfg, source, rumble_engine, debug=args.debug, trace=args.trace,
                    verbose=verbose, feedback=args.feedback)
    engine.run(duration=args.duration)
    print(engine.summary())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
