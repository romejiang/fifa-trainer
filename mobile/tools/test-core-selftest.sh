#!/usr/bin/env bash
# 闸门反例自测：证明 test-core.sh 的五种「假绿」路径都会变红，且正例仍然绿。
#
#   bash mobile/tools/test-core-selftest.sh
#
# 五条反例对应 RESEARCH §Q1 的失败表，缺一条就等于允许一种假绿：
#   stub_rc0_silent      —— 解析失败但退出码 0：没有 TESTS_DONE 哨兵
#   stub_hang            —— 入口运行时错误挂死：看门狗必须杀掉并判红
#   stub_fail            —— 真的失败：failures=1 且退出码非零
#   stub_zero_assertions —— 套件全被跳过：failures=0 但零断言
#   fixture_missing      —— tap 黄金夹具不见了：生成器自己的缺失提示必须让闸门变红
# 最后一条是正例：用真 Godot 跑一次完整闸门，必须成功。
#
# 每个 stub 都必须按参数分支：test-core.sh 的导入步骤**没有**看门狗（只有对信号
# 终止的有界重试）。挂死型 stub 如果对导入也 sleep，反例脚本会先把自己挂死，
# 而不是证明闸门的哨兵逻辑。

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
gate="$repo_root/mobile/tools/test-core.sh"

tmp="$(mktemp -d)"

# 第 5 条反例（fixture_missing）要临时把 tap 黄金夹具移走。还原必须挂在 EXIT 上：
# 反例 fail() 时也要把夹具放回去，否则一次失败的运行会把工作区留在「夹具不见了」的状态。
fixture="$repo_root/mobile/tests/fixtures/tap_golden.json"
fixture_backup="$tmp/tap_golden.json.bak"
restore_fixture() {
    if [ -f "$fixture_backup" ]; then
        mv "$fixture_backup" "$fixture"
    fi
}
trap 'rm -rf "$tmp"; restore_fixture' EXIT

fail() {  # $1=用例名 $2=原因
    echo "SELFTEST_FAIL $1: $2" >&2
    exit 1
}

make_stub() {  # $1=名字 $2=--script 分支的正文；返回可执行路径
    local name="$1" body="$2" path="$tmp/$1"
    {
        printf '#!/bin/sh\n'
        printf 'case "$*" in\n'
        printf '  *--script*)\n'
        printf '%s\n' "$body"
        printf '    ;;\n'
        printf '  *)\n'
        printf '    exit 0\n'
        printf '    ;;\n'
        printf 'esac\n'
    } >"$path"
    chmod +x "$path"
    printf '%s' "$path"
}

rc0_stub="$(make_stub stub_rc0_silent '    exit 0')"
hang_stub="$(make_stub stub_hang '    exec sleep 300')"
fail_stub="$(make_stub stub_fail '    echo "TESTS_DONE failures=1"
    exit 1')"
zero_stub="$(make_stub stub_zero_assertions '    echo "TESTS_ASSERTIONS=0"
    echo "TESTS_DONE failures=0"
    exit 0')"

check_red() {  # $1=用例名 $2=stub 路径 $3=日志里必须出现的失败原因
    local name="$1" stub="$2" reason="$3" log="$tmp/$1.log"
    if GODOT_BIN="$stub" CORE_TEST_TIMEOUT=2 bash "$gate" >"$log" 2>&1; then
        sed 's/^/    /' "$log" >&2
        fail "$name" "闸门返回 0，假绿没有被抓住"
    fi
    if ! grep -qF "$reason" "$log"; then
        sed 's/^/    /' "$log" >&2
        fail "$name" "闸门变红了，但不是因为预期原因（日志缺「${reason}」）"
    fi
    echo "✓ 反例 ${name} 已变红"
}

check_red stub_rc0_silent "$rc0_stub" "没有 TESTS_DONE failures=0"
check_red stub_fail "$fail_stub" "核心测试进程失败/超时"
check_red stub_zero_assertions "$zero_stub" "零断言"

# 挂死型还要证明「是看门狗杀的」：耗时必须远小于 stub 里的 300 秒。
hang_start=$SECONDS
if GODOT_BIN="$hang_stub" CORE_TEST_TIMEOUT=2 bash "$gate" >"$tmp/stub_hang.log" 2>&1; then
    sed 's/^/    /' "$tmp/stub_hang.log" >&2
    fail "stub_hang" "闸门返回 0，挂死型假绿没有被抓住"
fi
hang_elapsed=$((SECONDS - hang_start))
if ! grep -qF "核心测试进程失败/超时" "$tmp/stub_hang.log"; then
    sed 's/^/    /' "$tmp/stub_hang.log" >&2
    fail "stub_hang" "闸门变红了，但不是看门狗超时导致的"
fi
if [ "$hang_elapsed" -ge 30 ]; then
    fail "stub_hang" "耗时 ${hang_elapsed}s，看门狗没有生效（应小于 30s）"
fi
echo "✓ 反例 stub_hang 已变红（看门狗 ${hang_elapsed}s 内杀掉）"

# 第 5 条反例：tap 黄金夹具缺失。
#
# 夹具缺失时若闸门仍然绿，就是「测试对着不存在的期望报绿」—— 那种绿比红更危险。
# 断言日志里出现的是**生成器自己的**缺失提示（「缺少 tap 黄金夹具」），不是 Godot
# 的失败：原因指得准，才不会把「夹具丢了」误诊成「Godot 装坏了」。
#
# 还原后用 sha256 逐字节比对，而不是看 git status：这条反例必须能在夹具刚改过、
# 还没提交的工作区里正确判定「原样还原」，git 状态会把「已修改」误判成「没还原」。
fixture_sha_before="$(shasum -a 256 "$fixture" | awk '{print $1}')"
mv "$fixture" "$fixture_backup"
if GODOT_BIN="" bash "$gate" >"$tmp/fixture_missing.log" 2>&1; then
    restore_fixture
    sed 's/^/    /' "$tmp/fixture_missing.log" >&2
    fail "fixture_missing" "闸门返回 0，夹具缺失没有被抓住"
fi
if ! grep -qF "缺少 tap 黄金夹具" "$tmp/fixture_missing.log"; then
    restore_fixture
    sed 's/^/    /' "$tmp/fixture_missing.log" >&2
    fail "fixture_missing" "闸门变红了，但不是因为夹具缺失（日志缺「缺少 tap 黄金夹具」）"
fi
restore_fixture
fixture_sha_after="$(shasum -a 256 "$fixture" | awk '{print $1}')"
if [ "$fixture_sha_before" != "$fixture_sha_after" ]; then
    fail "fixture_missing" "夹具没有被原样还原（sha256 变了）"
fi
echo "✓ 反例 fixture_missing 已变红"

echo "▸ 正例：用真 Godot 跑一次完整闸门…"
if ! GODOT_BIN="" bash "$gate" >"$tmp/positive.log" 2>&1; then
    sed 's/^/    /' "$tmp/positive.log" >&2
    fail "positive" "正例没有变绿：真 Godot 跑不通闸门"
fi
if ! grep -qF "✓ 核心闸门通过" "$tmp/positive.log"; then
    fail "positive" "闸门退出 0 但没有打印通过行"
fi
echo "✓ 正例 真 Godot 闸门已变绿"

echo "SELFTEST_OK cases=6"
