#!/usr/bin/env bash
# 闸门 B 的反例自测：两件事只有「故意做错」才能被证明。
#
#   bash mobile/tools/gate-b-selftest.sh
#
# 场景 A 证明「文件存在 ≠ 导出成功」：绕过闸门 B 的守卫直接调 Godot，口令故意
# 写错，让它把包写到探针路径。导出按预期失败，但磁盘上很可能留下一个大小正常
# 的未签名 APK —— 那个文件必须过不了验签，否则本闸门的全部判据都是假的。
# 场景 B 证明「口令不进日志」：造一个随机 canary 当口令（必然导出失败），把
# stdout + stderr 全部捕获，canary 一个字都不许出现。
#
# 本脚本不复制闸门 B 的任何检查逻辑：需要完整验证时它直接调 gate-b.sh，
# 这里只负责造反例、判期望失败、清理现场。期望失败必须用 if 包起来 ——
# 一个永远绿的反例比没有反例更危险。

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
godot="${GODOT_BIN:-$HOME/Applications/Godot-4.7.2.app/Contents/MacOS/Godot}"
sdk_root="${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}"
bt="$sdk_root/build-tools/36.1.0"

# 探针产物刻意与正式产物分开：自测失败时不能顺手毁掉 mobile/build/fifa-trainer.apk。
probe="$repo_root/mobile/build/unsigned-probe.apk"

# 与 doctor.sh / gate-b.sh 逐字相同的两个覆盖点（FIFA_KEYSTORE / FIFA_KEYSTORE_ALIAS）。
keystore_path="${FIFA_KEYSTORE:-$HOME/.fifa-trainer/release.keystore}"
keystore_alias="${FIFA_KEYSTORE_ALIAS:-fifa-trainer}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "▸ 场景 A：绕过闸门 B，直接导出到探针路径（口令故意写错）…"
mkdir -p "$repo_root/mobile/build"
rm -f "$probe"

# 直接调 Godot 而不是调 gate-b.sh：gate-b 会在导出前拦住缺口令/坏口令，
# 那样就永远看不到「导出失败却留下文件」这个现场。
if GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$keystore_path" \
        GODOT_ANDROID_KEYSTORE_RELEASE_USER="$keystore_alias" \
        GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="selftest-wrong-password" \
        "$godot" --headless --path "$repo_root/mobile" \
        --export-release "Android" "$probe" > "$tmp/unsigned.log" 2>&1; then
    echo "SELFTEST_FAIL 口令写错时导出居然成功了：签名链路与闸门假设不一致" >&2
    rm -f "$probe"
    exit 1
fi
echo "  · 导出按预期非零退出（判据是退出码，不是日志里有没有 ERROR）"

if [ -f "$probe" ]; then
    # 这就是现场证据：文件在、大小正常、但验签必须失败。
    if "$bt/apksigner" verify "$probe" > "$tmp/unsigned-verify.log" 2>&1; then
        echo "SELFTEST_FAIL 未签名的探针产物居然通过了验签：闸门 B 的判据是假的" >&2
        rm -f "$probe"
        exit 1
    fi
    echo "  ✓ 未签名产物被 apksigner 拒绝"
    echo "    · 残留大小: $(wc -c < "$probe" | tr -d ' ') 字节（大小正常，这正是「文件存在即成功」会踩的坑）"
else
    echo "  ✓ 导出在写包前失败"
fi
rm -f "$probe"
if [ -e "$probe" ]; then
    echo "SELFTEST_FAIL 探针产物清不掉：${probe}" >&2
    exit 1
fi

echo "▸ 恢复一个合格产物（重跑闸门 B）…"
if ! bash "$repo_root/mobile/tools/gate-b.sh"; then
    echo "SELFTEST_FAIL 探针清掉后闸门 B 仍不能产出合格 APK：问题不在反例" >&2
    exit 1
fi

echo "▸ 场景 B：用 canary 当口令，证明口令不进导出日志…"
# canary 的生成方式有讲究：如果上游无限产出、下游按固定字节数读够就关闭读端，
# 上游会收到 SIGPIPE 并以 141 退出；本脚本开头是 set -euo pipefail，于是脚本会
# 在「生成 canary」这一步直接死掉，场景 B 根本走不到断言 —— 反例脚本自己崩掉
# 比没有反例更危险。od 一次只产出 12 字节，tr 会把输入读到底才退出，
# 没有任何一端被提前关闭。仅仅换个参数不算修好：只要还是「字符集过滤 +
# 固定字节数读取」的组合，危险就在。
#
# canary 只存在于当前进程的环境变量与 $tmp 下的临时文件里，
# 绝不写进任何仓库文件。
canary="CANARY_$(od -An -N12 -tx1 /dev/urandom | tr -d ' \n')"
rm -f "$probe"

if GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$keystore_path" \
        GODOT_ANDROID_KEYSTORE_RELEASE_USER="$keystore_alias" \
        GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$canary" \
        "$godot" --headless --path "$repo_root/mobile" \
        --export-release "Android" "$probe" > "$tmp/canary.log" 2>&1; then
    echo "SELFTEST_FAIL canary 当口令时导出居然成功了" >&2
    rm -f "$probe"
    exit 1
fi
rm -f "$probe"

if grep -qF "$canary" "$tmp/canary.log"; then
    echo "SELFTEST_FAIL 导出日志里出现了口令 canary（共 $(grep -cF "$canary" "$tmp/canary.log") 行）" >&2
    exit 1
fi
echo "  ✓ 导出日志不含口令 canary"

# 口令是唯一硬要求；这里再补一条：签名命令行里的密钥库参数必须是脱敏的，
# 不能把真实路径原样打出来（路径本身不致命，但它会让日志被当成凭据线索）。
if grep -q 'apksigner sign' "$tmp/canary.log"; then
    if grep 'apksigner sign' "$tmp/canary.log" | grep -qF "$keystore_path"; then
        echo "SELFTEST_FAIL 导出日志把真实密钥库路径原样打了出来" >&2
        exit 1
    fi
    echo "  ✓ 签名命令行里的密钥库参数是脱敏的"
else
    echo "  · 日志里没有签名命令行（导出在签名前就失败了），口令仍然没有出现"
fi

echo "SELFTEST_OK"
