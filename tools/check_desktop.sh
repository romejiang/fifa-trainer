#!/usr/bin/env bash
# 桌面版回归闸门：302 项检查必须全绿，且检查项名称与基线逐项一致。
#
#   bash tools/check_desktop.sh
#
# 一条命令同时证明四件事：配置副本与唯一真源一致、检查项基线未被重新生成、
# 锁文件未漂移、桌面两套件 205 + 97 项全部通过。
#
# 基线 shared/expected_checks.txt 只允许随「合法新增检查」重新生成；每次都要
# 显式修改下面的常量，并在提交信息里说明理由。
# 这条常量是「基线不可重写」的机械化落点：改基线而不改常量，闸门必红。

set -euo pipefail

BASELINE_SHA256=414ccb727b85696b352164036a1f1d05f3216809e929cffa1c90d8ade920c3d4
readonly BASELINE_SHA256

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
baseline="$repo_root/shared/expected_checks.txt"
desktop="$repo_root/desktop"

export SDL_VIDEODRIVER=dummy
export SDL_AUDIODRIVER=dummy
export PYGAME_HIDE_SUPPORT_PROMPT=1
export PYTHONIOENCODING=utf-8

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# 第一步必须是配置校验：副本缺失时 load_config() 会静默回退到内置
# DEFAULT_CONFIG，测试照样全绿，但测的已经不是真源了（假绿）。
echo "▸ 校验配置副本…"
if ! python3 "$repo_root/tools/sync_config.py" --check; then
    echo "  运行 python3 tools/sync_config.py 重新生成副本后再试。" >&2
    exit 1
fi

# 第二步钉死基线本身：允许重生成基线，等于允许把「删掉一条断言」洗成
# 「基线更新」。摘要对不上就直接失败，不看测试结果。
echo "▸ 校验基线未被重新生成…"
baseline_digest="$(
    python3 - "$baseline" <<'PY'
import hashlib
import sys
from pathlib import Path

print(hashlib.sha256(Path(sys.argv[1]).read_bytes()).hexdigest())
PY
)"
if [ "$baseline_digest" != "$BASELINE_SHA256" ]; then
    echo "✗ 基线被修改：$baseline" >&2
    echo "  实际 SHA-256: $baseline_digest" >&2
    echo "  期望 SHA-256: $BASELINE_SHA256" >&2
    echo "  本阶段禁止重新生成基线；合法新增检查必须同步更新脚本里的 BASELINE_SHA256。" >&2
    exit 1
fi

# 第三步才碰依赖与测试。--locked：锁文件过期时报错，绝不静默改写
# （本机 uv 配置指向镜像，裸 uv sync 会把 uv.lock 改写成镜像地址）。
echo "▸ 同步依赖（锁文件必须已是最新）…"
cd "$desktop"
uv sync --locked

run_suite() {  # $1=相对 desktop 的测试脚本 $2=期望检查项数量
    local test_file="$1" expected="$2" out actual
    out="$tmp/$(basename "$test_file").tsv"
    # 测试自身的彩色输出全部转 stderr，stdout 只留给名称文件。
    if ! uv run --no-sync python "$repo_root/tools/collect_checks.py" \
            "$test_file" --out "$out" >&2; then
        echo "✗ $test_file 未通过（失败项见上面的 ✗ 行）" >&2
        exit 1
    fi
    actual="$(wc -l < "$out" | tr -d ' ')"
    if [ "$actual" -ne "$expected" ]; then
        echo "✗ $test_file：检查项 $actual 项，期望 $expected 项" >&2
        exit 1
    fi
    cat "$out"
}

{ run_suite tests/test_detectors.py 205
  run_suite tests/test_gui_smoke.py 97; } | LC_ALL=C sort > "$tmp/actual.txt"

# set -e 下裸 diff 一旦有差异会直接退出，来不及打印中文提示，所以包进 if。
if ! diff -u "$baseline" "$tmp/actual.txt"; then
    echo "✗ 检查项名称与 shared/expected_checks.txt 不一致" >&2
    exit 1
fi

echo "✓ 302 项检查全部通过，名称与基线逐项一致"
