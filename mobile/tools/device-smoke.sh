#!/usr/bin/env bash
# 真机冒烟里**自动化能做的部分**：装机、启动、进程存活、截图。
#
#   bash mobile/tools/device-smoke.sh             真跑（需要一台已授权的 Android 设备）
#   bash mobile/tools/device-smoke.sh --dry-run   只打印将执行的命令与期望 token，不需要设备
#
# 它**不对任何视觉内容下结论**：中文有没有豆腐块、五个符号在不在、轴数字有没有在动，
# 这些只能由人盯着屏幕判断，判据与记录字段在 `mobile/ACCEPTANCE.md`。这个脚本只负责
# 把「包能装上、能起来、起来之后没立刻死、屏幕上确实有东西」变成可重放的事实。
#
# 两个工具都按绝对路径解析，**一个都不依赖 PATH**：本机的 `aapt2` 只在
# `…/build-tools/36.1.0/` 里，写裸 `aapt2` 会让脚本跑到一半才 command not found。
# 工具缺失也走同一条 fail-closed 出口（`DEVICE_SMOKE_FAIL 找不到 …`）—— 不允许出现
# 「脚本自己崩了、但没打印 token」的形态。
#
# 一条自检规则贯穿全篇：`set -euo pipefail` 下，每一个可能失败的赋值都必须落在
# `if` / `&&` 里，或紧跟着显式的 token 分支。最典型的是取 pid —— 裸写
# `pid="$(adb shell pidof …)"` 时，进程已崩会让 pidof 返回非零，脚本**当场终止**，
# 而那正是最该打印 `DEVICE_SMOKE_FAIL` 的时刻。
#
# 退出码：0 = DEVICE_SMOKE_OK；1 = DEVICE_SMOKE_FAIL（含工具缺失、无设备、装不上、
# 起不来、立刻崩、截不到图）；2 = 调用方式错误。

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

sdk_root="${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}"
adb="$sdk_root/platform-tools/adb"
aapt2="$sdk_root/build-tools/36.1.0/aapt2"

apk="$repo_root/mobile/build/fifa-trainer.apk"
out_dir="$repo_root/mobile/build"
package_name="com.fifaskill.trainer"

dry_run=false
case "${1:-}" in
    "") ;;
    --dry-run) dry_run=true ;;
    *)
        echo "用法: bash mobile/tools/device-smoke.sh [--dry-run]" >&2
        exit 2
        ;;
esac

# 工具断言先于一切：缺失时打印 token 并退出，而不是让后面的命令以 127 收场。
if [[ ! -x "$adb" ]]; then
    echo "DEVICE_SMOKE_FAIL 找不到 adb: ${adb}" >&2
    echo "  修法: 装 Android platform-tools，或用 ANDROID_SDK_ROOT 指向正确的 SDK。" >&2
    exit 1
fi
if [[ ! -x "$aapt2" ]]; then
    echo "DEVICE_SMOKE_FAIL 找不到 aapt2: ${aapt2}" >&2
    echo "  修法: 装 build-tools 36.1.0（与 mobile/BUILD.md 第一节同一枚 pin）。" >&2
    exit 1
fi

if [[ ! -f "$apk" ]]; then
    echo "DEVICE_SMOKE_FAIL 找不到 APK: ${apk}" >&2
    echo "  修法: 先跑 bash mobile/tools/gate-b.sh 导出签名包。" >&2
    exit 1
fi

if [[ "$dry_run" == true ]]; then
    echo "DEVICE_SMOKE_PLAN（--dry-run：不装、不启动，只列出将执行的命令）"
    echo "  adb       = ${adb}"
    echo "  aapt2     = ${aapt2}"
    echo "  apk       = ${apk}"
    echo "  screenshot= ${out_dir}/device-smoke-<serial>.png"
    echo "命令："
    echo "  \"\$adb\" devices"
    echo "  \"\$adb\" -s <serial> install -r \"${apk}\""
    echo "  \"\$aapt2\" dump badging \"${apk}\"    # 取 launchable-activity: name='…'"
    echo "  \"\$adb\" -s <serial> shell am start -W -n \"${package_name}/<activity>\""
    echo "  \"\$adb\" -s <serial> shell pidof \"${package_name}\""
    echo "  \"\$adb\" -s <serial> exec-out screencap -p > \"${out_dir}/device-smoke-<serial>.png\""
    echo "  \"\$adb\" -s <serial> shell am force-stop \"${package_name}\""
    echo "期望 token：DEVICE_SMOKE_OK serial=<serial> package=${package_name} pid=<pid> screenshot=<path>"
    exit 0
fi

# --- 设备 ---
# 只认 state=device 的行；unauthorized / offline 会在这里被算成「0 台可用」，
# 因为它们装不了包 —— 报一个具体的修法比报一串设备名有用。
listing="$("$adb" devices 2>/dev/null | tail -n +2 | sed '/^$/d')" || listing=""
ready="$(printf '%s\n' "$listing" | awk 'NF >= 2 && $2 == "device" {print $1}')" || ready=""
count="$(printf '%s' "$ready" | grep -c . || true)"

if [[ "$count" -eq 0 ]]; then
    echo "DEVICE_SMOKE_FAIL 未检测到设备（adb devices 为空）" >&2
    echo "  修法: 接上手机、开 USB 调试并在手机上点「允许」；" >&2
    echo "        用 \"${adb}\" devices 确认状态是 device 而不是 unauthorized / offline。" >&2
    exit 1
fi

if [[ -n "${ANDROID_SERIAL:-}" ]]; then
    serial="$ANDROID_SERIAL"
else
    serial="$(printf '%s\n' "$ready" | head -n 1)"
    if [[ "$count" -gt 1 ]]; then
        echo "· 检测到 ${count} 台设备，用第一台 ${serial}；可用 ANDROID_SERIAL=<serial> 指定" >&2
    fi
fi

# --- 从 APK 解析包名与启动 activity ---
# activity 名**不硬编码**：它由 export_presets.cfg 的 launcher_icons / package 决定，
# 硬编码一份就会与真实产物脱钩，而脱钩的表现是「装上了但起不来」，很难查。
if ! badging="$("$aapt2" dump badging "$apk" 2>&1)"; then
    echo "DEVICE_SMOKE_FAIL aapt2 读不出 badging: ${apk}" >&2
    printf '%s\n' "$badging" >&2
    exit 1
fi

package_name="$(printf '%s\n' "$badging" | sed -n "s/^package: name='\([^']*\)'.*/\1/p" | head -n 1)" || package_name=""
if [[ -z "$package_name" ]]; then
    echo "DEVICE_SMOKE_FAIL 从 badging 解析不出 package name" >&2
    exit 1
fi

activity="$(printf '%s\n' "$badging" | sed -n "s/^launchable-activity: name='\([^']*\)'.*/\1/p" | head -n 1)" || activity=""
if [[ -z "$activity" ]]; then
    echo "DEVICE_SMOKE_FAIL 从 badging 解析不出 launchable-activity" >&2
    echo "  badging 里缺少 launchable-activity: name='…'，说明这个包没有可启动的入口。" >&2
    exit 1
fi

echo "▸ 设备 ${serial}；包 ${package_name}；入口 ${activity}"

# --- 装机 ---
if ! "$adb" -s "$serial" install -r "$apk" > /tmp/device-smoke-install.log 2>&1; then
    echo "DEVICE_SMOKE_FAIL 安装失败: ${apk}" >&2
    tail -n 10 /tmp/device-smoke-install.log >&2
    exit 1
fi
echo "  ✓ 安装成功"

# --- 启动 ---
if ! "$adb" -s "$serial" shell am start -W -n "${package_name}/${activity}" > /tmp/device-smoke-start.log 2>&1; then
    echo "DEVICE_SMOKE_FAIL 启动失败: ${package_name}/${activity}" >&2
    tail -n 10 /tmp/device-smoke-start.log >&2
    exit 1
fi

# 等 5 秒再取 pid：立刻取会把「还没起完」误判成崩溃，而这一段的判据是
# 「起来之后没有立刻死」，不是「起得多快」。
sleep 5

# 必须用 if 包住：裸赋值在 pidof 返回非零时会直接终止脚本（见文件头自检规则）。
if ! pid="$("$adb" -s "$serial" shell pidof "$package_name" 2>/dev/null)"; then
    pid=""
fi
pid="$(printf '%s' "$pid" | tr -d '\r\n ')"
if [[ -z "$pid" ]]; then
    echo "DEVICE_SMOKE_FAIL 启动后进程不存在（${package_name} 在 5 秒内退出）" >&2
    tail -n 10 /tmp/device-smoke-start.log >&2
    exit 1
fi
echo "  ✓ 进程存活 pid=${pid}"

# --- 截图 ---
screenshot="$out_dir/device-smoke-${serial}.png"
mkdir -p "$out_dir"
if ! "$adb" -s "$serial" exec-out screencap -p > "$screenshot"; then
    echo "DEVICE_SMOKE_FAIL 截图失败: ${screenshot}" >&2
    exit 1
fi
if [[ ! -s "$screenshot" ]]; then
    echo "DEVICE_SMOKE_FAIL 截图是空文件: ${screenshot}" >&2
    exit 1
fi

# 收尾：不 force-stop 的话，下一次 install -r 可能撞上正在运行的实例。
"$adb" -s "$serial" shell am force-stop "$package_name" > /dev/null 2>&1 || true

echo "· 截图: ${screenshot}（视觉判据见 mobile/ACCEPTANCE.md 第 1 节，脚本不下结论）"
echo "DEVICE_SMOKE_OK serial=${serial} package=${package_name} pid=${pid} screenshot=${screenshot}"
