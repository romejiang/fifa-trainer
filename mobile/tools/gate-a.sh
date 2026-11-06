#!/usr/bin/env bash
# 闸门 A：在无导出模板、无 JDK、无真机的机器上判定工程与配置是否就绪。
#
#   bash mobile/tools/gate-a.sh
#
# 这一条命令同时证明七件事：配置副本与唯一真源一致、引擎版本落在允许的前缀下、
# 工程能被 headless 导入、每个存在的 GDScript 语法通过（三个 UI 脚本存在即检查，
# 04-06 之后三个都必须存在）、导出的 PCK 里真的能读出
# 5 条动作与匹配的 sha256、字形清单与源文件一致、关闭系统兜底后全部必需字形
# 仍能渲染。
#
# 为什么这个顺序不能换：配置校验必须是第一步 —— 副本被手改时 load_config() 会
# 静默回退到内置默认配置，PCK 闸门照样能解析出 5 条动作并报绿，那是一个
# 「配置真的进包了」的假绿（T-02-04）。版本断言只调 doctor.sh godot：版本号
# 在整个仓库里只有一处定义，本脚本里只出现安装路径，不出现版本断言。最后读包
# 那一步刻意不带工程目录参数，否则 res:// 指回源码而不是导出物（T-02-06）。
# 字形两步的顺序同理不能倒：字形闸门只比对「清单 vs 子集」，它看不见「源文件
# 里新加了汉字、清单还没重生成」；那种情况下清单自洽、子集自洽，闸门照旧
# GLYPH_OK，屏幕上却是豆腐。--check 是补上「清单 vs 源文件」这条边的唯一一步。

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
godot="${GODOT_BIN:-$HOME/Applications/Godot-4.7.2.app/Contents/MacOS/Godot}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# 第一步必须是配置校验：副本缺失或被手改时 load_config() 会静默回退到内置
# DEFAULT_CONFIG，PCK 闸门照样能解析出 5 条动作 —— 那是「假绿」，正是本闸门
# 存在的意义所在。顺序挪到后面，闸门就变成对着手改过的副本报绿。
echo "▸ 校验配置副本与唯一真源一致…"
if ! python3 "$repo_root/tools/sync_config.py" --check; then
    echo "  运行 python3 tools/sync_config.py 重新生成副本后再试。" >&2
    exit 1
fi

echo "▸ 校验引擎版本（版本号只在 doctor.sh 里定义）…"
if ! bash "$repo_root/mobile/tools/doctor.sh" godot; then
    echo "✗ 引擎版本断言未通过：按上面打印的实际值与修法处理" >&2
    exit 1
fi

echo "▸ 导入工程（生成 .godot/ 缓存，干净 clone 的第一次必须跑）…"
# Godot 4.7.2 在 macOS arm64 上导入 NotoSansSC 子集时会偶发 SIGSEGV（约 1/5，
# 与字体内容无关，同一份文件重跑即可）。这里**只对导入这一步**做有界重试，
# 且**只在信号终止时重试**（退出码 >= 128）；导入成功但内容不对、或任何断言失败，
# 都不会被重试吞掉。重试次数会打印出来，不静默。
import_rc=1
for attempt in 1 2 3; do
    set +e
    "$godot" --headless --path "$repo_root/mobile" --import >"$tmp/import.log" 2>&1
    import_rc=$?
    set -e
    if [ "$import_rc" -eq 0 ]; then
        [ "$attempt" -gt 1 ] && echo "  · 导入第 ${attempt} 次成功（前一次被信号终止，Godot 已知偶发）"
        break
    fi
    if [ "$import_rc" -lt 128 ]; then
        echo "✗ 工程导入失败（Godot --import 退出码 ${import_rc}，不是信号终止，不重试），日志尾部：" >&2
        tail -n 20 "$tmp/import.log" >&2
        exit 1
    fi
    echo "  · 导入被信号终止（退出码 ${import_rc}），第 ${attempt}/3 次，重试…" >&2
done
if [ "$import_rc" -ne 0 ]; then
    echo "✗ 工程导入连续 3 次被信号终止（Godot 已知偶发，但三次都撞上说明不是偶发），日志尾部：" >&2
    tail -n 20 "$tmp/import.log" >&2
    exit 1
fi

# 语法检查必须逐个指名文件失败：一个脚本里有错时，只说「语法检查失败」
# 等于把定位工作留给下一个人。
#
# 注意：Godot 4.7.2 的 `--check-only --script` 对「解析失败」和「文件不存在」
# 都返回退出码 0（实测：坏脚本只打 SCRIPT ERROR，rc 仍是 0）。所以判据必须是
# **输出里没有错误行**，不能看退出码 —— 否则语法错会一路绿到 APK。
# 这是 2026-11-04 代码审查抓到的假绿，别改回 `if ! out=$(...)`。
check_script() {
    local script="$1" out
    if ! out="$("$godot" --headless --path "$repo_root/mobile" \
            --check-only --script "$script" 2>&1)"; then
        echo "✗ 脚本语法检查失败：${script}" >&2
        printf '%s\n' "$out" >&2
        exit 1
    fi
    if printf '%s\n' "$out" | grep -qE 'SCRIPT ERROR|Parse Error|Failed to load script|Can.t load script|File not found'; then
        echo "✗ 脚本语法检查失败：${script}（Godot 退出码为 0，但输出里有错误）" >&2
        printf '%s\n' "$out" | grep -E 'SCRIPT ERROR|Parse Error|Failed to load script|Can.t load script|File not found' | head -10 >&2
        exit 1
    fi
    echo "  ✓ ${script}"
}

echo "▸ 检查每个存在的 GDScript 的语法…"
# 三个 UI 脚本守卫式检查：本波次执行时 practice_screen.gd 还不存在（04-06 才创建），
# 无条件检查会让闸门在中间波次变红。守卫不是永久豁免：04-06 的验收要求三个文件
# 全部存在，且输出里出现各自的 ✓ 行 —— 那才证明它们真的被编译过，而不是被跳过。
# 判据一个字都不放宽（见 check_script 的注释：Godot 对解析错误也返回 0）。
for script in \
    "res://src/smoke/smoke_screen.gd" \
    "res://tools/check_pack.gd" \
    "res://src/ui/main.gd" \
    "res://src/ui/input_setup_screen.gd" \
    "res://src/ui/onboarding_screen.gd" \
    "res://src/ui/diagnostics_overlay.gd" \
    "res://src/ui/home_screen.gd" \
    "res://src/ui/practice_screen.gd"; do
    if [ -f "$repo_root/mobile/${script#res://}" ]; then
        check_script "$script"
    fi
done

# 产物路径必须是绝对路径：--path 之后，传给 Godot 的相对路径锚点是工程目录，
# 写成相对会落到 mobile/mobile/build/ 下（RESEARCH P2 / T-02-05）。
echo "▸ 导出 PCK（打包不需要 1.9 GB 导出模板）…"
mkdir -p "$repo_root/mobile/build"
if ! "$godot" --headless --path "$repo_root/mobile" --export-pack "Android" "$repo_root/mobile/build/verify.pck" >"$tmp/export.log" 2>&1; then
    echo "✗ PCK 导出失败（Godot 打包命令），日志尾部：" >&2
    tail -n 20 "$tmp/export.log" >&2
    exit 1
fi

# 读包刻意不带工程目录参数：带了之后 res:// 会指回工程目录，读到的是源码里
# 的配置而不是导出物 —— 那样这条断言就失去意义（T-02-06）。
echo "▸ 从 PCK 里读回配置与 sidecar…"
if ! pack_out="$("$godot" --headless --main-pack "$repo_root/mobile/build/verify.pck" --script res://tools/check_pack.gd 2>&1)"; then
    printf '%s\n' "$pack_out" >&2
    echo "✗ 包内校验失败：配置或 sidecar 不在包里 / SKILL_COUNT 不对" >&2
    exit 1
fi
printf '%s\n' "$pack_out"
case "$pack_out" in
    *PACK_OK*)
        ;;
    *)
        echo "✗ 包内校验没有给出 PACK_OK 标记：${pack_out}" >&2
        exit 1
        ;;
esac

# 字形必须走两步，且顺序不能反：
#   1) --check 比对「清单 vs 源文件」——源文件里新加了一个汉字而清单没重生成时，
#      清单与子集仍然彼此自洽，字形闸门照旧 GLYPH_OK，屏幕上却是豆腐。这一步
#      只读、不调用字体工具、毫秒级，是把这条边补上的唯一办法。
#   2) 字形闸门比对「清单 vs 子集」——在关闭系统兜底的前提下逐字符断言。
glyph_tool="tools/make_font_subset.py"
# 这一步同时覆盖闭世界的两条边：src/ui 下的新增文件（目录自动枚举）与会渲染的
# core 文案（RENDER_SOURCES 点名）。任一缺登记，--check 直接失败 —— 闸门在真机
# 豆腐时保持绿色是本仓库已经付过代价的假绿。
echo "▸ 校验字形源闭世界（src/ui 自动枚举 + RENDER_SOURCES 点名）与清单一致…"
if ! python3 "$repo_root/$glyph_tool" --check; then
    echo "✗ 字形清单与源文件不一致：运行 python3 $glyph_tool 重新生成" >&2
    exit 1
fi

echo "▸ 关闭系统兜底后逐字符断言字形…"
if ! glyph_out="$("$godot" --headless --path "$repo_root/mobile" --script res://tools/glyph_coverage.gd 2>&1)"; then
    printf '%s\n' "$glyph_out" >&2
    echo "✗ 字形闸门失败：清单里的字符在 AppFont（含 fallback）里渲染不出来" >&2
    exit 1
fi
printf '%s\n' "$glyph_out"
case "$glyph_out" in
    *GLYPH_OK*)
        ;;
    *)
        echo "✗ 字形闸门没有给出 GLYPH_OK 标记：${glyph_out}" >&2
        exit 1
        ;;
esac

echo "· PCK 留在 $repo_root/mobile/build/verify.pck 供人工检查（mobile/build/ 已被忽略）"
echo "✓ 闸门 A 通过：配置一致、脚本语法通过、PCK 内含 5 条动作、全部必需字形可渲染"
