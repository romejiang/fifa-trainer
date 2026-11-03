#!/usr/bin/env python3
"""FIFA 花式动作练习 —— 双击启动 / 打包入口。

直接打开桌面窗口（等价于 ``uv run main.py --gui``）。
命令行用法::

    uv run app.py                 # 打开练习窗口
    uv run app.py --demo          # 不用手柄，循环演示成功和失败
    uv run app.py -c my.json      # 指定配置文件
"""

from __future__ import annotations

import os
import sys

os.environ.setdefault("PYGAME_HIDE_SUPPORT_PROMPT", "1")

# windowed 打包（--windowed）时 sys.stdout / sys.stderr 是 None，
# 必须赶在任何库尝试写它们之前兜住。这是打包后"双击没反应"的最常见原因。
if sys.stdout is None:
    sys.stdout = open(os.devnull, "w", encoding="utf-8")
if sys.stderr is None:
    sys.stderr = open(os.devnull, "w", encoding="utf-8")

# 直接 `python app.py` 时保证包能被导入（PyInstaller 会自动处理）
_HERE = os.path.dirname(os.path.abspath(__file__))
if _HERE not in sys.path:
    sys.path.insert(0, _HERE)


def _parse_args(argv):
    config = None
    demo = False
    args = list(argv)
    while args:
        arg = args.pop(0)
        if arg in ("--demo", "-d"):
            demo = True
        elif arg in ("--config", "-c") and args:
            config = args.pop(0)
        elif arg in ("--help", "-h"):
            print(__doc__)
            raise SystemExit(0)
    return config, demo


def main(argv=None) -> int:
    config, demo = _parse_args(sys.argv[1:] if argv is None else argv)
    from padskills.gui import main_gui

    return main_gui(config_path=config, demo=demo)


if __name__ == "__main__":
    raise SystemExit(main())
