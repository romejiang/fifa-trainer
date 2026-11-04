#!/usr/bin/env bash
# 安卓工具链体检：一条命令说出这台机器缺哪一项工具链，并给出可直接照抄的修法。
#
#   bash mobile/tools/doctor.sh            # 跑全部构建断言
#   bash mobile/tools/doctor.sh godot      # 只跑引擎版本断言
#
# 这条命令同时证明三件事：引擎是 4.7.2-stable 且来自仓库外的固定路径、
# 每一项断言都能按名字单独运行（闸门 A 不需要模板 / JDK / 真机）、
# 缺项时非零退出并同时打印实际值、期望值与一条可执行的修法 —— 而不是把
# 「文件存在」当成「工具链就绪」。
#
# 为什么版本字符串只能在这里定义一次：真实输出是
# 4.7.2.stable.official.ed1daf0bf，用等号比较永远红（RESEARCH P8）；
# 一旦其它脚本各写一份前缀，其中一份就会悄悄漂移到 4.8。后续闸门
# 一律调 doctor.sh <断言名>，不复制判定。
#
# 为什么 JAVA_HOME 的顺序不能反（RESEARCH P7）：Godot 首次 --import 会把
# 当时的 JAVA_HOME 写进 editor_settings-4.7.tres。顺序反了，这台机器之后
# 每一次导出都用错 JDK，而文件看起来全都「存在」。所以 jdk 断言将来必须
# 实跑 java -version 再比对设置文件里的 java_sdk_path，不能只查路径。

set -euo pipefail

# 版本前缀必须带尾点：4.7.2.stable.official.ed1daf0bf 是前缀匹配，不是等号。
readonly GODOT_VERSION_PREFIX="4.7.2.stable."
readonly GODOT_DEFAULT="$HOME/Applications/Godot-4.7.2.app/Contents/MacOS/Godot"
GODOT_BIN="${GODOT_BIN:-$GODOT_DEFAULT}"
readonly GODOT_BIN

# mobile/tools/ 是两层深：tools/*.sh 的一层写法（/..）在这里一定指错目录。
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

usage() {
    cat >&2 <<EOF
用法: bash mobile/tools/doctor.sh [断言名 ...]
  留空        依次跑全部构建断言（不包含 device）
  godot       引擎 --version 必须是 ${GODOT_VERSION_PREFIX}*（前缀匹配）
断言失败退出 1；调用方式错误（未知断言名）退出 2。
EOF
}

# godot：引擎存在、可执行、且 --version 落在 4.7.2.stable.* 前缀下。
assert_godot() {
    local version=""
    if ! version="$("$GODOT_BIN" --version 2>&1)"; then
        version=""
    fi
    # 失败时输出可能是多行错误；只取第一行参与匹配与展示。
    version="${version%%$'\n'*}"

    case "$version" in
        "$GODOT_VERSION_PREFIX"*)
            echo "✓ godot ${version}（${GODOT_BIN}）"
            return 0
            ;;
    esac

    echo "✗ godot 引擎不可用或版本不对：${GODOT_BIN}" >&2
    echo "  实际输出: ${version:-<无输出>}" >&2
    echo "  期望前缀: ${GODOT_VERSION_PREFIX}（完整输出形如 ${GODOT_VERSION_PREFIX}official.ed1daf0bf）" >&2
    echo "  修法: 把 4.7.2-stable 的 Godot.app 放到 \$HOME/Applications/Godot-4.7.2.app，" >&2
    echo "        或 export GODOT_BIN=<指向 4.7.2-stable 可执行文件的路径>。" >&2
    return 1
}

if [ "$#" -eq 0 ]; then
    set -- godot
fi

# 先整体校验断言名再执行：未知名字是「调用方式错」（退出 2），
# 不能混进「环境缺项」（退出 1）里。
selected=()
for name in "$@"; do
    case "$name" in
        godot) selected+=("$name") ;;
        *)
            echo "✗ 未知断言名：${name}（可用：godot）" >&2
            usage
            exit 2
            ;;
    esac
done

rc=0
for name in "${selected[@]}"; do
    if ! "assert_${name}"; then
        rc=1
    fi
done
exit "$rc"
