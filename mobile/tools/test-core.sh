#!/usr/bin/env bash
# 纯核心闸门：一条命令判定移动端纯 GDScript 层是否与 Python 参考一致。
#
#   bash mobile/tools/test-core.sh
#
# 这一条命令同时证明四件事：配置副本与唯一真源一致、几何黄金夹具没有漂移、
# 工程能被 headless 导入、几何套件逐向量与 Python 参考一致且断言真的执行了。
#
# 为什么这个顺序不能换：配置校验必须第一步 —— 副本被手改时，测试会对着被改过的
# 副本自洽地绿（与闸门 A 同源的假绿）。黄金校验必须在 Godot 之前 —— 夹具被手改
# 时，测试只是「与手改后的自己一致」。导入必须在跑测试之前 —— class_name 的全局
# 缓存由导入生成，干净 clone 直接跑 --script 会 Could not find type，**而那种失败
# 的退出码是 0**。最后的判据是 stdout 里的完成哨兵，不是 $?：解析失败与依赖编译
# 失败都返回 0，只有脚本自己显式 quit(n) 才设置退出码。
#
# 不要把 --check-only 塞进来当语法判据：4.7.2 对解析错误同样返回 0，只能看输出。
# 本闸门的语法判据更强 —— runner 用 preload 拉起套件，preload / 编译失败会让
# runner 自己编译失败，于是根本没有 TESTS_DONE，哨兵判红。

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
godot="${GODOT_BIN:-$HOME/Applications/Godot-4.7.2.app/Contents/MacOS/Godot}"
# 看门狗秒数。默认 180 是生产值；反例自测把它压到 2 秒来证明「挂死会变红」，
# 否则那个用例要真的等上几分钟才能结束。
core_timeout="${CORE_TEST_TIMEOUT:-180}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# 第一步必须是配置校验：副本被手改时，测试会对着被改过的副本自洽地绿 —— 那正是
# 本闸门要防的假绿。顺序挪到后面，闸门就变成对着手改过的副本报绿。
echo "▸ 校验配置副本与唯一真源一致…"
if ! python3 "$repo_root/tools/sync_config.py" --check; then
    echo "  运行 python3 tools/sync_config.py 重新生成副本后再试。" >&2
    exit 1
fi

echo "▸ 校验几何黄金夹具未漂移…"
if ! python3 "$repo_root/tools/gen_geometry_golden.py" --check; then
    echo "  运行 python3 tools/gen_geometry_golden.py 重新生成黄金夹具后再试。" >&2
    exit 1
fi

echo "▸ 导入工程（生成 .godot/ 缓存与 class_name 全局注册表）…"
# Godot 4.7.2 在 macOS arm64 上导入 NotoSansSC 子集时偶发 SIGSEGV（约 1/5，
# 与字体内容无关，同一份文件重跑即可）。这里**只对导入这一步**做有界重试，
# 且**只在信号终止时重试**（退出码 >= 128）；导入成功但内容不对、或任何断言
# 失败，都不会被重试吞掉。重试次数会打印出来，不静默。
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
        echo "✗ 工程导入失败（Godot 退出码 ${import_rc}，不是信号终止，不重试），日志尾部：" >&2
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

# bash 3.2 兼容的看门狗：macOS 默认没有 GNU timeout，干净机器上调用它会直接
# command not found。这里后台起进程 + 后台看门狗，超时先 TERM 再 2 秒后 KILL。
# 挂死型失败必须变成「超时失败」，不能把闸门变成「永远等下去」。
run_with_timeout() {
    local secs="$1"; shift
    local out="$1"; shift
    "$@" >"$out" 2>&1 &
    local pid=$!
    ( sleep "$secs"; kill -TERM "$pid" 2>/dev/null; sleep 2; kill -KILL "$pid" 2>/dev/null ) &
    local watcher=$!
    local rc=0
    wait "$pid" || rc=$?
    kill "$watcher" 2>/dev/null || true
    wait "$watcher" 2>/dev/null || true
    return "$rc"
}

echo "▸ 运行核心测试（看门狗 ${core_timeout}s）…"
if ! run_with_timeout "$core_timeout" "$tmp/tests.log" \
        "$godot" --headless --path "$repo_root/mobile" --script res://tests/core_runner.gd; then
    cat "$tmp/tests.log" >&2
    echo "✗ 核心测试进程失败/超时（看门狗 ${core_timeout}s）：入口运行时错误会挂死，解析错误会假 rc=0" >&2
    exit 1
fi
cat "$tmp/tests.log"

# 判据是哨兵，不是 $?。没有这一行，解析失败 / class_name 未解析都会一路绿灯。
if ! grep -qE '^TESTS_DONE failures=0$' "$tmp/tests.log"; then
    echo "✗ 没有 TESTS_DONE failures=0（解析 / 编译 / 运行时错误都可能 rc=0）" >&2
    exit 1
fi

# 零断言是另一种假绿：套件全被跳过时同样打印 failures=0。
if grep -qE '^TESTS_ASSERTIONS=0$' "$tmp/tests.log"; then
    echo "✗ TESTS_ASSERTIONS=0：零断言是另一种假绿（套件全被跳过时也会打印 failures=0）" >&2
    exit 1
fi

echo "✓ 核心闸门通过：配置一致、黄金未漂移、几何套件全绿"
