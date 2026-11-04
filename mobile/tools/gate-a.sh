#!/usr/bin/env bash
# 闸门 A：在无导出模板、无 JDK、无真机的机器上判定工程与配置是否就绪。
#
#   bash mobile/tools/gate-a.sh
#
# 这一条命令同时证明七件事：配置副本与唯一真源一致、引擎版本落在允许的前缀下、
# 工程能被 headless 导入、两个 GDScript 语法通过、导出的 PCK 里真的能读出
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
if ! "$godot" --headless --path "$repo_root/mobile" --import >"$tmp/import.log" 2>&1; then
    echo "✗ 工程导入失败（Godot --import），日志尾部：" >&2
    tail -n 20 "$tmp/import.log" >&2
    exit 1
fi

# 语法检查必须逐个指名文件失败：一个脚本里有错时，只说「语法检查失败」
# 等于把定位工作留给下一个人。
check_script() {
    local script="$1" out
    if ! out="$("$godot" --headless --path "$repo_root/mobile" \
            --check-only --script "$script" 2>&1)"; then
        echo "✗ 脚本语法检查失败：${script}" >&2
        printf '%s\n' "$out" >&2
        exit 1
    fi
    echo "  ✓ ${script}"
}

echo "▸ 检查两个 GDScript 的语法…"
check_script "res://src/smoke/smoke_screen.gd"
check_script "res://tools/check_pack.gd"

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
echo "▸ 校验字形清单与源文件一致…"
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
