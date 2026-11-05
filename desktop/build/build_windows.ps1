# 在 Windows 上打包成可双击的 exe。
#
#   powershell -ExecutionPolicy Bypass -File build\build_windows.ps1
#
# 产物：dist\FIFA-Skill-Trainer.exe（单文件，双击即用）
# PyInstaller 不能交叉编译：macOS 的 .app 必须在 Mac 上打包。

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

Write-Host "▸ 安装打包依赖…"
uv sync --extra build

Write-Host "▸ 开始打包…"
uv run pyinstaller `
    --noconfirm --clean `
    --onefile --windowed --noupx `
    --name "FIFA-Skill-Trainer" `
    --hidden-import pygame._sdl2.controller `
    --hidden-import pygame._sdl2.video `
    --hidden-import padskills.xinput_source `
    --exclude-module XInput `
    --add-data "padskills\assets;padskills\assets" `
    app.py

if ($LASTEXITCODE -ne 0) {
    throw "PyInstaller 失败（退出码 $LASTEXITCODE）"
}

$exe = Join-Path $root "dist\FIFA-Skill-Trainer.exe"
if (-not (Test-Path $exe)) {
    throw "没有找到产物：$exe"
}

Write-Host ""
Write-Host "完成：$exe"
Write-Host "首次运行时，配置会写到 %APPDATA%\FifaSkillTrainer\skills_config.json"
Write-Host "之后想改动作规则，直接编辑那个文件即可。"
