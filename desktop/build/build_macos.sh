#!/usr/bin/env bash
# 在 macOS 上打包成可双击的 .app。
#
#   bash build/build_macos.sh
#
# 产物：dist/FIFA Skill Trainer.app
# PyInstaller 不能交叉编译：Windows 的 exe 必须在 Windows 上打包。

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

echo "▸ 安装打包依赖…"
uv sync --extra build

echo "▸ 开始打包…"
uv run pyinstaller \
    --noconfirm --clean \
    --windowed --noupx \
    --name "FIFA Skill Trainer" \
    --osx-bundle-identifier com.fifaskill.trainer \
    --hidden-import pygame._sdl2.controller \
    --exclude-module XInput \
    --add-data "padskills/assets:padskills/assets" \
    app.py

app="dist/FIFA Skill Trainer.app"
if [[ ! -d "$app" ]]; then
    echo "没有找到产物：$app" >&2
    exit 1
fi

cat <<EOF

完成：$app

未签名的 App 第一次打开会被 Gatekeeper 拦下，任选一种方式放行：
  1. 右键点 App → 打开 → 再点"打开"
  2. xattr -dr com.apple.quarantine "$app"

首次运行时，配置会写到：
  ~/Library/Application Support/FifaSkillTrainer/skills_config.json

第一次使用手柄如果没反应，去
  系统设置 → 隐私与安全性 → 输入监控
把本 App 勾上，然后重启 App。
EOF
