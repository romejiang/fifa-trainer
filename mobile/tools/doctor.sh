#!/usr/bin/env bash
# 安卓工具链体检：一条命令说出这台机器缺哪一项工具链，并给出可直接照抄的修法。
#
#   bash mobile/tools/doctor.sh            # 五项构建断言：godot / template / jdk / sdk / keystore
#   bash mobile/tools/doctor.sh godot      # 只跑引擎版本断言
#   bash mobile/tools/doctor.sh device     # 只跑真机在线检查（构建闸门不依赖它）
#
# 这条命令同时证明三件事：每一项宿主事实都是「可读的版本或内容」而不是
# 「文件存在」、每一项断言都能按名字单独运行（闸门 A 不需要 1.9 GB 模板、
# JDK、真机）、缺项时非零退出并同时打印实际值、期望值与一条可执行的修法。
#
# 为什么版本字符串只能在这里定义一次：真实输出是
# 4.7.2.stable.official.ed1daf0bf，用等号比较永远红（RESEARCH P8）；
# 一旦其它脚本各写一份前缀，其中一份就会悄悄漂移到 4.8。后续闸门
# 一律调 doctor.sh <断言名>，不复制判定。
#
# 为什么 JAVA_HOME 的顺序不能反（RESEARCH P7）：Godot 首次 --import 会把
# 当时的 JAVA_HOME 写进 editor_settings-4.7.tres。顺序反了，这台机器之后
# 每一次导出都用错 JDK，而文件看起来全都「存在」。所以 jdk 断言不是查
# 路径存在，而是实跑 java -version 再比对设置文件里的 java_sdk_path。

set -euo pipefail

# 版本前缀必须带尾点：4.7.2.stable.official.ed1daf0bf 是前缀匹配，不是等号。
readonly GODOT_VERSION_PREFIX="4.7.2.stable."
readonly GODOT_DEFAULT="$HOME/Applications/Godot-4.7.2.app/Contents/MacOS/Godot"
GODOT_BIN="${GODOT_BIN:-$GODOT_DEFAULT}"
readonly GODOT_BIN

# 导出模板目录名取自 .tpz 内的 version.txt（精确一行，故这里用等号比较）。
readonly TEMPLATE_VERSION="4.7.2.stable"
readonly TEMPLATE_SHA512="ca4d71c4d7b81dfc15d1a98baa07534aa95b03fdda78a0075b06672e1648d2e5f40980c9adc28d23e1b92e732ee7bf3461997aa804af74ec2fcd7a93ccb84079"

# 系统默认 JDK 是 25；构建只认 17，但绝不改系统默认值，只在本脚本内解析。
readonly JDK_MAJOR="17"
readonly JDK_DEFAULT="$HOME/.sdkman/candidates/java/17.0.12-oracle"
readonly EDITOR_SETTINGS="$HOME/Library/Application Support/Godot/editor_settings-4.7.tres"

readonly BUILD_TOOLS="36.1.0"
readonly PLATFORM_DIR="android-36"
SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}"
readonly SDK_ROOT

# 密钥只走环境变量 / 固定默认路径，脚本里不出现任何口令字面值。
KEYSTORE_PATH="${FIFA_KEYSTORE:-$HOME/.fifa-trainer/release.keystore}"
readonly KEYSTORE_PATH
KEYSTORE_ALIAS="${FIFA_KEYSTORE_ALIAS:-fifa-trainer}"
readonly KEYSTORE_ALIAS

# mobile/tools/ 是两层深：tools/*.sh 的一层写法（/..）在这里一定指错目录。
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

usage() {
    cat >&2 <<EOF
用法: bash mobile/tools/doctor.sh [断言名 ...]
  留空        依次跑 godot template jdk sdk keystore 五项构建断言（不包含 device）
  godot       引擎 --version 必须是 ${GODOT_VERSION_PREFIX}*（前缀匹配）
  template    导出模板目录与 version.txt 必须是 ${TEMPLATE_VERSION}
  jdk         实跑 java -version 主版本 ${JDK_MAJOR}，且 editor_settings 指向同一个 ${JDK_MAJOR}
  sdk         build-tools ${BUILD_TOOLS} 的 apksigner/zipalign/aapt2 + platforms/${PLATFORM_DIR} + adb
  keystore    keystore 能被 keytool 打开；口令只从环境变量读，不落盘
  device      真机在线数；0 台 fail-closed，只在被点名时运行
断言失败退出 1；调用方式错误（未知断言名）退出 2。
· 仓库根: ${repo_root}
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

# template：android_release.apk 必须在，且同目录 version.txt 精确等于目录名。
# 只有「装错版本」在这里判；包体是否被掉包由下载期的 SHA-512 一次性建立
# （.tpz 解压后不保留，安装完成后无法再对 1.28 GB 包体做二次哈希）。
assert_template() {
    local dest="$HOME/Library/Application Support/Godot/export_templates/${TEMPLATE_VERSION}"
    local apk="$dest/android_release.apk"
    local version_file="$dest/version.txt"
    local actual_version=""
    local apk_state="缺失"

    if [ -f "$version_file" ]; then
        actual_version="$(tr -d '\r\n' < "$version_file")"
    fi
    if [ -f "$apk" ]; then
        apk_state="存在"
    fi

    if [ "$apk_state" = "存在" ] && [ "$actual_version" = "$TEMPLATE_VERSION" ]; then
        echo "✓ template ${TEMPLATE_VERSION}（${apk}）"
        return 0
    fi

    echo "✗ template 导出模板缺失或版本不对：$dest" >&2
    echo "  实际: android_release.apk ${apk_state}，version.txt=${actual_version:-<缺失>}" >&2
    echo "  期望: 目录名 ${TEMPLATE_VERSION}，且 version.txt 内容恰为 ${TEMPLATE_VERSION}" >&2
    echo "  修法（下载 + 校验 + 解压拷贝，三步都要）：" >&2
    echo "    curl -fL -o /tmp/templates.tpz https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz" >&2
    echo "    echo '${TEMPLATE_SHA512}  /tmp/templates.tpz' | shasum -a 512 -c -" >&2
    echo "    unzip -q -o /tmp/templates.tpz -d /tmp/tpl && mkdir -p \"$dest\" && cp -R /tmp/tpl/templates/. \"$dest/\"" >&2
    echo "  · 按这三行重装一次，模板来源就经过了一次 SHA-512 校验。" >&2
    return 1
}

# 解析出这台机器上可用的 JDK ${JDK_MAJOR}：先看 JAVA_HOME（若恰好是 17），
# 再退到固定默认路径。系统默认是 25，脚本绝不修改系统默认值，只在本进程内
# 显式选定一个 17 —— 这正是「JDK 17 不是系统默认」的机械化处置。
resolve_jdk17() {
    local candidate first
    for candidate in "${JAVA_HOME:-}" "$JDK_DEFAULT"; do
        [ -n "$candidate" ] || continue
        [ -x "$candidate/bin/java" ] || continue
        first="$("$candidate/bin/java" -version 2>&1 | head -n 1)" || first=""
        case "$first" in
            *"\"${JDK_MAJOR}."*)
                printf '%s\n' "$candidate"
                return 0
                ;;
        esac
    done
    return 1
}

# jdk：解析出的 JDK 实跑必须是 17；editor_settings 存在时，其 java_sdk_path 也必须能跑出 17。
assert_jdk() {
    local jdk_home=""
    local first=""

    if ! jdk_home="$(resolve_jdk17)"; then
        echo "✗ jdk 找不到可用的 JDK ${JDK_MAJOR}" >&2
        echo "  实际 JAVA_HOME: ${JAVA_HOME:-<未设置>}" >&2
        if [ -n "${JAVA_HOME:-}" ] && [ -x "${JAVA_HOME}/bin/java" ]; then
            echo "  实际 java -version: $("${JAVA_HOME}/bin/java" -version 2>&1 | head -n 1)" >&2
        fi
        echo "  期望: JDK ${JDK_MAJOR}（默认 ${JDK_DEFAULT}）" >&2
        echo "  修法: export JAVA_HOME=${JDK_DEFAULT}；不要改系统默认 JDK。" >&2
        return 1
    fi
    first="$("$jdk_home/bin/java" -version 2>&1 | head -n 1)" || first=""

    if [ -n "${JAVA_HOME:-}" ] && [ "$jdk_home" != "$JAVA_HOME" ]; then
        echo "· JAVA_HOME 指向的不是 JDK ${JDK_MAJOR}，已显式改用 ${jdk_home}（未修改系统默认值）"
    fi

    if [ ! -f "$EDITOR_SETTINGS" ]; then
        echo "· editor_settings 尚未生成（首次 --import 时按当时的 JAVA_HOME 写入）"
        echo "✓ jdk ${first}（${jdk_home}）"
        return 0
    fi

    local configured=""
    configured="$(grep -E '^export/android/java_sdk_path' "$EDITOR_SETTINGS" 2>/dev/null \
        | head -n 1 | sed -E 's/^[^=]*= *"(.*)" *$/\1/')" || configured=""

    if [ -z "$configured" ]; then
        echo "✗ jdk editor_settings 里没有 export/android/java_sdk_path：$EDITOR_SETTINGS" >&2
        echo "  期望: 指向 JDK ${JDK_MAJOR} 的目录" >&2
        echo "  修法: rm \"$EDITOR_SETTINGS\" 后，以 JAVA_HOME=$JDK_DEFAULT 重跑一次 --import。" >&2
        return 1
    fi

    local configured_first=""
    if [ -x "$configured/bin/java" ]; then
        configured_first="$("$configured/bin/java" -version 2>&1 | head -n 1)" || configured_first=""
    fi
    case "$configured_first" in
        *"\"${JDK_MAJOR}."*) ;;
        *)
            echo "✗ jdk editor_settings 指向的 JDK 不是 ${JDK_MAJOR}：$configured" >&2
            echo "  实际 java -version: ${configured_first:-<无法执行>}" >&2
            echo "  期望: 主版本 ${JDK_MAJOR}（RESEARCH P7：首次 --import 写死了当时的 JAVA_HOME）" >&2
            echo "  修法: rm \"$EDITOR_SETTINGS\" 后，以 JAVA_HOME=$JDK_DEFAULT 重跑 --import；顺序不能反。" >&2
            return 1
            ;;
    esac

    if [ "$configured" != "$jdk_home" ]; then
        echo "· editor_settings 的 java_sdk_path 与本次解析出的 JDK 不同：${configured}（同为 JDK ${JDK_MAJOR}，可用）"
    fi
    echo "✓ jdk ${first}（${jdk_home}，editor_settings → ${configured}）"
    return 0
}

# sdk：逐个点名缺失项，不在第一个缺失处中断（否则补一个又来一个）。
assert_sdk() {
    local build_tools_dir="$SDK_ROOT/build-tools/${BUILD_TOOLS}"
    local missing=0
    local tool

    for tool in apksigner zipalign aapt2; do
        if [ ! -x "$build_tools_dir/$tool" ]; then
            echo "✗ sdk 缺 ${tool}：$build_tools_dir/$tool 不存在或不可执行" >&2
            missing=1
        fi
    done
    if [ ! -d "$SDK_ROOT/platforms/${PLATFORM_DIR}" ]; then
        echo "✗ sdk 缺平台目录：$SDK_ROOT/platforms/${PLATFORM_DIR}" >&2
        missing=1
    fi
    if [ ! -x "$SDK_ROOT/platform-tools/adb" ]; then
        echo "✗ sdk 缺 adb：$SDK_ROOT/platform-tools/adb 不存在或不可执行" >&2
        missing=1
    fi

    if [ "$missing" -ne 0 ]; then
        echo "  实际 SDK 根目录: ${SDK_ROOT}（可用 ANDROID_SDK_ROOT 覆盖）" >&2
        echo "  期望: build-tools ${BUILD_TOOLS}（apksigner/zipalign/aapt2）、platforms/${PLATFORM_DIR}、platform-tools/adb" >&2
        echo "  修法: 在 Android Studio 的 SDK Manager 里勾选 Build-Tools ${BUILD_TOOLS}、" >&2
        echo "        Platform ${PLATFORM_DIR#android-}、Platform-Tools 后重试。" >&2
        return 1
    fi

    echo "✓ sdk build-tools ${BUILD_TOOLS} + platforms/${PLATFORM_DIR} + adb（${SDK_ROOT}）"
    return 0
}

# keystore：先看口令是否在环境里（只报变量名），再验文件与别名能否打开。
assert_keystore() {
    if [ -z "${GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD:-}" ]; then
        echo "✗ keystore 口令未在环境变量 GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD 中" >&2
        echo "  只报告变量名，不读取、不打印任何口令值。" >&2
        echo "  修法: 从密码管理器取出发布口令，先 export 变量 GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD（口令只留在环境里，不要写进任何文件）。" >&2
        return 1
    fi

    if [ ! -f "$KEYSTORE_PATH" ]; then
        echo "✗ keystore 文件不存在：$KEYSTORE_PATH" >&2
        echo "  期望路径: ${KEYSTORE_PATH}（或 export FIFA_KEYSTORE=<路径>）" >&2
        echo "  期望别名: ${KEYSTORE_ALIAS}（或 export FIFA_KEYSTORE_ALIAS=<别名>）" >&2
        echo "  修法: 口令在密码管理器，不要写进任何文件；生成一次并离线备份：" >&2
        echo "    keytool -genkeypair -v -keystore \"$KEYSTORE_PATH\" -alias \"$KEYSTORE_ALIAS\" \\" >&2
        echo "      -keyalg RSA -keysize 2048 -validity 10000 -storepass:env GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD" >&2
        return 1
    fi

    local keytool_home=""
    keytool_home="$(resolve_jdk17)" || keytool_home="${JAVA_HOME:-$JDK_DEFAULT}"
    local keytool_bin="$keytool_home/bin/keytool"
    if ! "$keytool_bin" -list -keystore "$KEYSTORE_PATH" -alias "$KEYSTORE_ALIAS" \
            -storepass:env GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD >/dev/null 2>&1; then
        echo "✗ keystore 打不开或别名不存在：${KEYSTORE_PATH}（alias=${KEYSTORE_ALIAS}）" >&2
        echo "  期望: keytool -list 能用环境变量里的口令打开该文件，且别名存在" >&2
        echo "  修法: 确认 FIFA_KEYSTORE / FIFA_KEYSTORE_ALIAS 与生成时一致；口令只经 -storepass:env 传入。" >&2
        return 1
    fi

    echo "✓ keystore ${KEYSTORE_PATH}（alias=${KEYSTORE_ALIAS} 可读，口令未落盘）"
    return 0
}

# device：只统计 state=device 的行；unauthorized / offline 单独点名，且不算通过。
assert_device() {
    local adb="$SDK_ROOT/platform-tools/adb"
    if [ ! -x "$adb" ]; then
        echo "✗ device 无法枚举：$adb 不存在或不可执行" >&2
        echo "  修法: 先修 sdk 断言里的 platform-tools/adb。" >&2
        return 1
    fi

    local listing=""
    listing="$("$adb" devices 2>/dev/null | tail -n +2 | sed '/^$/d')" || listing=""
    local ready=""
    ready="$(printf '%s\n' "$listing" | awk 'NF >= 2 && $2 == "device" {print $1}')" || ready=""
    local count=0
    if [ -n "$ready" ]; then
        count="$(printf '%s\n' "$ready" | grep -c .)" || count=0
    fi

    if [ "$count" -eq 0 ]; then
        echo "✗ device 0 台" >&2
        if [ -n "$listing" ]; then
            printf '%s\n' "$listing" | sed 's/^/  · 未就绪: /' >&2
        fi
        echo "  修法: 接上手机、打开 USB 调试，adb devices 应出现设备；本项只在被点名时运行，构建闸门不依赖它。" >&2
        return 1
    fi

    echo "✓ device ${count} 台"
    printf '%s\n' "$ready" | sed 's/^/  · /'
    return 0
}

if [ "$#" -eq 0 ]; then
    # 五项构建断言；device 刻意不在这里：闸门 A / B 不该因为手边没插手机而红。
    set -- godot template jdk sdk keystore
fi

# 先整体校验断言名再执行：未知名字是「调用方式错」（退出 2），
# 不能混进「环境缺项」（退出 1）里。
selected=()
for name in "$@"; do
    case "$name" in
        godot | template | jdk | sdk | keystore | device) selected+=("$name") ;;
        *)
            echo "✗ 未知断言名：${name}（可用：godot template jdk sdk keystore device）" >&2
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
