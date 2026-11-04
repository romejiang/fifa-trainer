#!/usr/bin/env bash
# 闸门 B：一条命令从「这台机器对不对」走到「这个 APK 能不能自证」。
#
#   bash mobile/tools/gate-b.sh
#
# 这一条命令同时证明六件事：五项工具链断言（引擎 / 模板 / JDK / SDK / 密钥库）、
# 闸门 A 的七项、口令只从环境来且这把密钥能签、签名是 v2 而不是「文件存在」、
# 包内 16 KB 对齐且只含 arm64、配置与 sidecar 真的躺在 assets/assets/config/ 下、
# 包名与 versionCode / versionName 是 Phase 9 覆盖安装依赖的那三个不可变事实。
#
# 为什么必须先 rm -f 再导出：Godot 的导出器是「先写包、后签名」。缺 keystore 或
# 口令错时它以退出码 1 收场，可磁盘上照样留下一个大小正常的未签名 APK —— 任何
# 「文件存在即成功」的判据都会被它骗过（RESEARCH P3 / T-02-11）。这一删让本轮的
# 失败无法被上一轮的产物冒充，也顺带证明幂等：连跑两次都从头来。
#
# 为什么验签结果不能交给管道去判：在管道里 `$?` 是后一个命令的退出码，验签失败
# 会被成功的那一半吞掉，闸门就永远绿。所以这里直接判定命令自身的退出码，输出
# 先落到临时文件，再单独比对内容。
#
# 为什么只有口令是必填输入：密钥库路径与别名在本仓库各只有一个正确答案，且
# doctor.sh 早就把它们定死（FIFA_KEYSTORE / FIFA_KEYSTORE_ALIAS 两个覆盖点，
# 默认值必须与 doctor.sh 逐字相同 —— 改一处就要改两处）。要求调用者再导出两个
# 恒定变量，只会制造一种「忘了 export」的红，那与包到底打成没打成无关；那种红
# 迟早会被注释掉。口令不同：它必须由人保管，所以它必须是唯一的必填项。

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
godot="${GODOT_BIN:-$HOME/Applications/Godot-4.7.2.app/Contents/MacOS/Godot}"
sdk_root="${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}"

# build-tools 的版本在这里与 doctor.sh 的 BUILD_TOOLS 各写一次，两边必须相同；
# 引擎与模板的版本断言只在 doctor.sh 里，本脚本不重复判定。
bt="$sdk_root/build-tools/36.1.0"
out="$repo_root/mobile/build/fifa-trainer.apk"

# 每个外部命令的输出都落在这个目录，失败时只回放尾部 —— 读日志的人看到的
# 是原始输出，不是一句转述的结论。
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# 密钥库路径与别名：默认值与 doctor.sh 的 KEYSTORE_PATH / KEYSTORE_ALIAS 逐字相同。
# 改这里就必须同步改 doctor.sh，否则「doctor 说密钥库好、闸门却用另一把签」。
keystore_path="${FIFA_KEYSTORE:-$HOME/.fifa-trainer/release.keystore}"
keystore_alias="${FIFA_KEYSTORE_ALIAS:-fifa-trainer}"

# 口令守卫必须早于 doctor：doctor 的 keystore 断言读的是同一个变量，
# 守卫放在后面时最先撞到的会是 doctor 的报错，读者会误以为是密钥库坏了。
# 消息里只写变量名与文档章节，绝不写值。
#
# 必须用显式 if + exit 1，不能用 `: "${VAR:?msg}"`：本脚本有 `trap ... EXIT`，
# 而 `:?` 展开失败是 bash 的特例 —— 它在 EXIT trap 里看到的 `$?` 仍是 0，
# 于是 trap 的 `rm -rf` 成功会把整个脚本的退出码洗成 0，缺口令反而「通过」闸门。
# 这个假绿在 2026-11-04 实测复现过（rc=0 且只打印守卫消息），不要再改回 `:?`。
if [ -z "${GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD:-}" ]; then
    echo "✗ 缺 release 口令：按 mobile/BUILD.md 第四节从密码管理器取出后 export 到当前 shell" >&2
    exit 1
fi
# 有人用 `VAR=... bash gate-b.sh` 这样传 —— 不 export 的话子进程收不到。
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD

# JAVA_HOME 只用于让导出器与 apksigner 找到 java；是不是 17 由 doctor.sh 的
# jdk 一项断言（版本解析只在 doctor 里做一次）。这里只保证它指向一个真存在的 JDK。
if [ -z "${JAVA_HOME:-}" ] || [ ! -x "${JAVA_HOME}/bin/java" ]; then
    JAVA_HOME="$HOME/.sdkman/candidates/java/17.0.12-oracle"
    export JAVA_HOME
fi

echo "▸ 工具链五项断言（引擎 / 模板 / JDK / SDK / 密钥库）…"
if ! bash "$repo_root/mobile/tools/doctor.sh"; then
    echo "✗ 工具链断言未通过：按上面每一条打印的实际值与修法处理，闸门不往下走" >&2
    exit 1
fi

echo "▸ 闸门 A（配置真源 + 语法 + PCK + 字形）…"
if ! bash "$repo_root/mobile/tools/gate-a.sh"; then
    echo "✗ 闸门 A 未通过：先把它修绿再谈打 APK" >&2
    exit 1
fi

# 先删后建：这一行是本闸门与「文件存在即成功」的分界线。
echo "▸ 清掉上一轮的产物…"
mkdir -p "$repo_root/mobile/build"
rm -f "$out"

echo "▸ 用 release 密钥库导出签名 APK…"
if ! GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$keystore_path" \
        GODOT_ANDROID_KEYSTORE_RELEASE_USER="$keystore_alias" \
        "$godot" --headless --path "$repo_root/mobile" \
        --export-release "Android" "$out" > "$tmp/export.log" 2>&1; then
    echo "✗ 导出失败（Godot --export-release），日志尾部：" >&2
    tail -n 20 "$tmp/export.log" >&2
    if [ -f "$out" ]; then
        echo "  · 注意：磁盘上留下了一个 ${out}，但它没通过签名 —— 不要拿它去装。" >&2
    fi
    exit 1
fi
# 导出成功的日志里也有 ERROR（No project icon specified）和 adb 噪声，
# 判据只看退出码与后面的产物校验（RESEARCH P4 / P10）。

echo "▸ 验签（直接判命令退出码，不经管道）…"
if ! "$bt/apksigner" verify --verbose --print-certs "$out" > "$tmp/sign.txt" 2>&1; then
    echo "✗ 验签失败：$out 没有可验证的签名（文件存在不等于导出成功）" >&2
    tail -n 20 "$tmp/sign.txt" >&2
    exit 1
fi
if ! grep -qF 'Verified using v2 scheme (APK Signature Scheme v2): true' "$tmp/sign.txt"; then
    echo "✗ 签名不是 v2：安卓 7.0 起只认 v2 及以上的整包签名" >&2
    if ! grep -F 'Verified using' "$tmp/sign.txt" >&2; then
        echo "  （apksigner 输出里没有 Verified using 行）" >&2
    fi
    exit 1
fi
# 证书指纹必须与发布密钥逐位一致。
# 只验「有 v2 签名」是不够的：任何人都能用一把新密钥重签同一个包，apksigner 照样
# 说 v2 true —— 但同一包名换了签名密钥，安卓会拒绝覆盖安装，用户只能卸载重装、
# user:// 数据全丢。这正是本阶段定义为「不可逆事故」的那一类。
# 下面是 2026-11-04 生成发布密钥库时记录的公开发布证书指纹（小写、无冒号）。
readonly EXPECTED_CERT_SHA256="e1841a17bda43307cdfc8e9e757c672a6a91b7fd60ea86e715afd461ba32e046"
actual_cert="$(grep -F 'certificate SHA-256 digest' "$tmp/sign.txt" | head -1 | awk '{print $NF}' | tr -d ':' | tr 'A-F' 'a-f')"
if [ -z "$actual_cert" ]; then
    echo "✗ apksigner 输出里没有证书摘要行，无法确认这个包是发布密钥签的" >&2
    exit 1
fi
if [ "$actual_cert" != "$EXPECTED_CERT_SHA256" ]; then
    echo "✗ 签名证书不是发布密钥：期望 ${EXPECTED_CERT_SHA256:0:16}… 实际 ${actual_cert:0:16}…" >&2
    echo "  用别的密钥签出的包无法覆盖安装到已发布版本上。" >&2
    exit 1
fi
echo "  ✓ 证书指纹与发布密钥一致（${EXPECTED_CERT_SHA256:0:16}…）"

echo "▸ 校验 16 KB 页对齐…"
if ! "$bt/zipalign" -c -P 16 -v 4 "$out" > "$tmp/align.txt" 2>&1; then
    echo "✗ APK 不是 16 KB 页对齐：16 KB 页设备会直接拒绝安装" >&2
    tail -n 5 "$tmp/align.txt" >&2
    exit 1
fi

echo "▸ 校验包内容（配置与 sidecar 在包内、没有 x86 库与签名旁文件）…"
if ! unzip -l "$out" > "$tmp/zip.txt" 2>&1; then
    echo "✗ 读不出 APK 的 zip 目录：$out" >&2
    exit 1
fi

# 双 assets 不是笔误：PCK 整体挂在 APK 的 assets/ 下，所以 res://assets/config/x
# 在 zip 里是 assets/assets/config/x（RESEARCH P2 注 (a)）。把这条断言「修」成
# 单 assets 会永远失败，而删掉它就等于放弃成功标准 3 的机械证明。
config_json="assets/assets/config/skills_config.json"
config_sidecar="assets/assets/config/skills_config.json.sha256"
for path in "$config_json" "$config_sidecar"; do
    if ! grep -qF "$path" "$tmp/zip.txt"; then
        echo "✗ 包里没有 $path" >&2
        echo "  期望: PCK 挂在 APK 的 assets/ 下，所以路径是双 assets 前缀" >&2
        echo "  修法: 检查 mobile/export_presets.cfg 的 include_filter 与 gate-a 的读包结果。" >&2
        exit 1
    fi
done

# 不该分发的东西：x86 / armeabi 库（成功标准 1 只要 arm64）、apksigner 的 v4
# 旁文件、以及任何密钥库文件（T-02-13）。
forbidden='lib/x86_64/|lib/x86/|lib/armeabi-v7a/|\.idsig|\.keystore|\.jks'
if grep -qE "$forbidden" "$tmp/zip.txt"; then
    echo "✗ 包里混入了不该分发的东西：" >&2
    grep -E "$forbidden" "$tmp/zip.txt" >&2
    exit 1
fi

echo "▸ 校验 badging（包名 / versionCode / versionName / 架构 / minSdk）…"
if ! "$bt/aapt2" dump badging "$out" > "$tmp/badge.txt" 2>&1; then
    echo "✗ aapt2 读不出 badging：$out" >&2
    exit 1
fi

# 三个不可变事实：包名、versionCode 起点、keystore 别名。别名由上面的导出与
# 下面的验签共同锁定；这里钉死前两个 —— 它们一旦发给朋友就不能再改，
# 改了就是另一个 app 且 user:// 数据全丢（Phase 9 的覆盖安装依赖它们）。
for expected in \
        "package: name='com.fifaskill.trainer'" \
        "versionCode='1'" \
        "versionName='0.1.0'" \
        "native-code: 'arm64-v8a'"; do
    if ! grep -qF "$expected" "$tmp/badge.txt"; then
        echo "✗ badging 里没有：${expected}" >&2
        echo "  实际 badging 前两行：" >&2
        head -n 2 "$tmp/badge.txt" >&2
        echo "  修法: 检查 mobile/export_presets.cfg 的 package/* 与 version/* 键。" >&2
        exit 1
    fi
done

# minSdk 不在这里钉死（它由模板与 gl_compatibility 共同决定），只要求存在并把
# 实际值打印出来，供 BUILD.md 记录 —— 钉死一个会随模板变化的数字只会制造噪音。
# 注意大小写：aapt2 打的是 minSdkVersion（大写的 Sdk），写成 sdkVersion 永远不匹配。
if ! grep -q "minSdkVersion:'" "$tmp/badge.txt"; then
    echo "✗ badging 里没有 minSdkVersion 行" >&2
    exit 1
fi

echo "· APK: ${out}（$(wc -c < "$out" | tr -d ' ') 字节）"
echo "· 最小 SDK: $(grep -m 1 "minSdkVersion:'" "$tmp/badge.txt" | tr -d ' ')"
echo "· 装到手机: $sdk_root/platform-tools/adb install -r \"$out\""
echo "· 下一步: mobile/ACCEPTANCE.md 的真机验收（闸门 C 只有人能过）"
echo "✓ 闸门 B 通过：签名有效、16 KB 对齐、仅 arm64、配置在包内、包名与版本正确"
