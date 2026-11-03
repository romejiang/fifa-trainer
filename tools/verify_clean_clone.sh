#!/usr/bin/env bash
# 在真正的干净 clone 上重放整条验证链，证明结论不依赖本机残留状态。
#
#   bash tools/verify_clean_clone.sh            正向：clone → 闸门 → 配置校验 → 零漂移
#   bash tools/verify_clean_clone.sh --tamper   正向 + 篡改反例（证明闸门真的会咬人）
#
# 只验证「已提交状态」：`git clone` 复制的是提交，工作区脏的时候 clone 里跑的
# 就是一段旧代码，那样的绿没有意义。因此入口直接用退出码 2 拒绝。
#
# 正向路径的四步：
#   1. git clone 到 mktemp 目录 —— 不是 cp -R 工作区，副本必须来自 git；
#   2. bash tools/check_desktop.sh —— 230 项检查、基线摘要、配置副本，一条命令；
#   3. python3 tools/sync_config.py --check —— 配置单一真源；
#   4. git status --porcelain 必须为空 —— 跑一次不会把仓库弄脏。
#
# --tamper 追加：手改 clone 里的移动端副本，`--check` 与闸门必须同时非零退出
# 并指名该文件；还原后必须重新变绿（证明失败来自篡改，不是脚本自身坏了）。
#
# 本脚本不复制任何检查逻辑：命令、数量、阈值全在 check_desktop.sh 与
# sync_config.py 里，这里只负责调度与断言。

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

mode="${1:-}"
case "$mode" in
    "" | --tamper) ;;
    *)
        echo "✗ 未知参数：${mode}（只接受留空或 --tamper）" >&2
        exit 2
        ;;
esac

# 入口守卫：脏工作区下 clone 出来的不是当前代码，先拦住再说。
if [[ -n "$(git -C "$repo_root" status --porcelain)" ]]; then
    echo "✗ 工作区有未提交改动，干净 clone 只能验证已提交状态" >&2
    git -C "$repo_root" status --porcelain >&2
    exit 2
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "▸ 克隆已提交状态到临时目录…"
git clone --quiet "$repo_root" "$tmp/clone"
cd "$tmp/clone"

echo "▸ 在干净 clone 上跑回归闸门…"
bash tools/check_desktop.sh

echo "▸ 校验配置单一真源…"
python3 tools/sync_config.py --check

# 零漂移断言：闸门跑完 clone 仍然是干净的，说明 .venv/、__pycache__/ 等
# 生成物都被忽略规则覆盖了 —— 否则「跑一次就变脏」会在真实仓库里变成噪音。
if [[ -n "$(git status --porcelain)" ]]; then
    echo "✗ clone 工作区出现漂移:" >&2
    git status --porcelain >&2
    exit 1
fi

echo "✓ 干净 clone 复现成功：230 项检查全绿，配置一致，工作区无漂移"

if [[ "$mode" != "--tamper" ]]; then
    exit 0
fi

target="mobile/assets/config/skills_config.json"

echo "▸ 反例：手改移动端副本 ${target}…"
printf ' ' >> "$target"

# 期望失败必须用 if 包起来，绝不能用 || true 吞掉退出码后照样打印成功 ——
# 一个永远绿的反例比没有反例更危险。
if out="$(python3 tools/sync_config.py --check 2>&1)"; then
    echo "✗ 手改副本后 --check 仍然通过" >&2
    exit 1
fi
if ! printf '%s' "$out" | grep -qF "$target"; then
    echo "✗ --check 失败了，但输出没有指名 $target" >&2
    printf '%s\n' "$out" >&2
    exit 1
fi
echo "  ✓ sync_config.py --check 抓住并指名 $target"
# 把抓人的那几行原样留在日志里，读日志的人不需要相信一句结论。
printf '%s\n' "$out" | grep -F "$target" | sed 's/^/    /'

if out="$(bash tools/check_desktop.sh 2>&1)"; then
    echo "✗ 手改副本后回归闸门仍然通过" >&2
    exit 1
fi
if ! printf '%s' "$out" | grep -qF -e "$target" -e "配置"; then
    echo "✗ 闸门失败了，但输出里既没有 $target 也没有「配置」" >&2
    printf '%s\n' "$out" >&2
    exit 1
fi
echo "  ✓ 回归闸门同样被拦住"

git checkout -- "$target"
if ! python3 tools/sync_config.py --check; then
    echo "✗ 还原后 --check 仍然失败：问题在脚本或仓库，不在篡改" >&2
    exit 1
fi
if [[ -n "$(git status --porcelain)" ]]; then
    echo "✗ 还原后工作区仍有残留改动（git checkout -- 没盖住）:" >&2
    git status --porcelain >&2
    exit 1
fi

echo "✓ 反例按预期失败：手改副本被 --check 与闸门同时抓住，还原后恢复绿"
