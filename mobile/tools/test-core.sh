#!/usr/bin/env bash
# 纯核心闸门：一条命令判定移动端纯 GDScript 层是否与 Python 参考一致。
#
#   bash mobile/tools/test-core.sh
#
# 这一条命令同时证明七件事：配置副本与唯一真源一致、lint 的反例仍会变红、
# src/core 没有越出零引擎依赖边界、几何黄金夹具没有漂移、配置判定在
# Python/GDScript 两侧一致且分歧已记录、工程能被 headless 导入、核心套件
# 逐条与 Python 参考一致且断言真的执行了。
#
# 为什么这个顺序不能换：配置校验必须第一步 —— 副本被手改时，测试会对着被改过的
# 副本自洽地绿（与闸门 A 同源的假绿）。lint 的反例自测必须排在真 lint 之前 ——
# 一条被写坏的规则会以「干净通过」的形式保护一切。架构边界必须排在所有 Godot
# 调用之前 —— 它是纯文本、毫秒级、零依赖的检查，没有理由等引擎装好；排在后面时，
# 一条越界会被误读成某个测试的怪错误。黄金校验必须在 Godot 之前 —— 夹具被手改时，
# 测试只是「与手改后的自己一致」。导入必须在跑测试之前 —— class_name 的全局缓存
# 由导入生成，干净 clone 直接跑 --script 会 Could not find type，**而那种失败的
# 退出码是 0**。最后的判据是 stdout 里的完成哨兵，不是 $?：解析失败与依赖编译失败
# 都返回 0，只有脚本自己显式 quit(n) 才设置退出码。
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

# 第二步：lint 的反例自测。必须先于真 lint —— 一条被写坏的规则会以「干净通过」的
# 形式保护一切，后面的真扫描再绿也没有意义。
echo "▸ 校验 lint 自身的反例（tools/test_lint_core_purity.py）…"
if ! python3 "$repo_root/tools/test_lint_core_purity.py"; then
    echo "  lint 的反例没变红：先修 lint 或它的自测，不要绕过。" >&2
    exit 1
fi

# 第三步：架构边界。纯文本、毫秒级、零依赖，不需要 Godot —— 没有任何理由等引擎
# 装好才跑。这是 INFRA-03 唯一被机械强制的边界，定义见 mobile/docs/CORE.md。
echo "▸ 校验 src/core 的架构边界（tools/lint_core_purity.py）…"
if ! python3 "$repo_root/tools/lint_core_purity.py" "$repo_root/mobile/src/core"; then
    echo "  core 不允许出现 Input. / Time. / Node / FileAccess / print(；把 I/O 与时钟推到 src/app/，把值作为参数传进来。见 mobile/docs/CORE.md" >&2
    exit 1
fi

echo "▸ 校验几何黄金夹具未漂移…"
if ! python3 "$repo_root/tools/gen_geometry_golden.py" --check; then
    echo "  运行 python3 tools/gen_geometry_golden.py 重新生成黄金夹具后再试。" >&2
    exit 1
fi

echo "▸ 校验 tap 黄金夹具未漂移…"
if ! python3 "$repo_root/tools/gen_tap_golden.py" --check; then
    echo "  运行 python3 tools/gen_tap_golden.py 重新生成黄金夹具后再试。" >&2
    exit 1
fi

# 手势夹具同样必须在 Godot 之前校验：夹具被手改时，回放只是「与手改后的自己一致」。
# 这条校验同时覆盖 detector 与 runtime 两类期望，且 `--check` 绝不写盘。
echo "▸ 校验手势黄金夹具未漂移…"
if ! python3 "$repo_root/tools/gen_gesture_golden.py" --check; then
    echo "  运行 python3 tools/gen_gesture_golden.py 重新生成黄金夹具后再试。" >&2
    exit 1
fi

# 轴枚举常量的零出现断言（INPUT-02）。纯文本、毫秒级、零 Godot 依赖 —— 放在导入
# 之前，反例自测才能在几秒内变红，而不必跑完整个 Godot 套件。
# 注意：这条断言**扫描注释**，所以源码里解释这条规则时必须用中文，不能把常量名写进
# 注释；下面这条 grep 本身不扫 tools/，只扫 mobile/src。
echo "▸ 校验 mobile/src 下没有手写 Godot 轴枚举常量（INPUT-02）…"
if grep -R --include='*.gd' -n "JOY_AXIS_" "$repo_root/mobile/src"; then
    echo "✗ mobile/src 下不允许出现 Godot 轴枚举常量前缀：轴序号必须由探针给出（INPUT-02）" >&2
    exit 1
fi

# 第四步：跨语言配置判定对等。纯 Python、不需要 Godot，越早失败越省时间；
# 而且必须排在任何 Godot 调用之前 ——「两端语义分叉」比「某一端自己红了」
# 更需要先知道。它只校验 Python 侧判定与语料一致、且每处分歧都有记录；
# GDScript 侧由 config_corpus 套件在最后一步判。
echo "▸ 校验配置判定在两端一致…"
if ! python3 "$repo_root/tools/check_config_parity.py"; then
    echo "  某条语料的 Python 判定与记录不符，或两侧判定不同却没有 divergence 记录；先看 stderr 里的 PARITY_FAIL。" >&2
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
    # 看门狗的 stdout/stderr 必须重定向掉：它继承了调用方的 fd，若调用方把
    # 本脚本的 stdout 接进管道（`test-core.sh | tail` / `$(...)`），看门狗里的
    # sleep 会一直握着管道写端 —— 脚本本身早已退出，管道却要等到睡满才 EOF。
    ( sleep "$secs"; kill -TERM "$pid" 2>/dev/null; sleep 2; kill -KILL "$pid" 2>/dev/null ) >/dev/null 2>&1 &
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

# tap 黄金回放的正向哨兵：套件自己打印实际回放条数与差异数。没有这一行，等于
# 「夹具没被读过」也能绿；mismatches 必须为 0，且 cases 至少 1（真空绿的反面）。
if ! grep -qE '^TAP_GOLDEN_DETECTOR cases=[1-9][0-9]* mismatches=0$' "$tmp/tests.log"; then
    echo "✗ 没有 TAP_GOLDEN_DETECTOR cases=N mismatches=0（夹具未回放或跨语言判定有差异）" >&2
    grep -E '^TAP_GOLDEN_DETECTOR ' "$tmp/tests.log" >&2 || true
    exit 1
fi
echo "✓ tap 黄金回放：$(grep -E '^TAP_GOLDEN_DETECTOR ' "$tmp/tests.log")"

# 运行时回放的正向哨兵：与 detector 分开，12 条检测器用例不能替 6 条运行时用例作证。
# cases 的阈值就是套件自己的断言条数（6），手删 runtime 用例会让套件先红，
# 这里再兜一层：哨兵缺失或 mismatches 非 0 都判红。
if ! grep -qE '^TAP_GOLDEN_RUNTIME cases=[1-9][0-9]* mismatches=0$' "$tmp/tests.log"; then
    echo "✗ 没有 TAP_GOLDEN_RUNTIME cases=N mismatches=0（运行时期望未回放或跨语言判定有差异）" >&2
    grep -E '^TAP_GOLDEN_RUNTIME ' "$tmp/tests.log" >&2 || true
    exit 1
fi
echo "✓ tap 运行时回放：$(grep -E '^TAP_GOLDEN_RUNTIME ' "$tmp/tests.log")"

# 手势回放的正向哨兵：与 tap 分开，tap 的 18 条用例不能替手势语料作证。
# 没有这一行，等于「夹具没被读过」也能绿；mismatches 必须为 0，且 cases 至少 28
# （真空绿的反面）。阈值与套件 _check_scale 的下限是同一个数字。
if ! grep -qE '^GESTURE_GOLDEN cases=(2[8-9]|[3-9][0-9]|[1-9][0-9]{2,}) mismatches=0$' "$tmp/tests.log"; then
    echo "✗ 没有 GESTURE_GOLDEN cases=N mismatches=0（夹具未回放或跨语言判定有差异）" >&2
    grep -E '^GESTURE_GOLDEN ' "$tmp/tests.log" >&2 || true
    exit 1
fi
echo "✓ 手势回放：$(grep -E '^GESTURE_GOLDEN ' "$tmp/tests.log")"

echo "✓ 核心闸门通过：配置一致、边界干净、黄金未漂移、tap 回放一致、运行时判定一致、核心套件全绿"
