#!/usr/bin/env bash
# 在真正的干净 clone 上重跑闸门 B，证明「换一台机器也能重导出」不是一句自我声明。
#
#   bash mobile/tools/verify_clean_export.sh
#
# 只验证「已提交状态」：`git clone` 复制的是提交，工作区脏的时候 clone 里跑的就是
# 一段旧代码，那样的绿没有意义。因此入口直接用退出码 2 拒绝。
#
# 入口守卫**只判已跟踪文件**（`--untracked-files=no`）。理由不是「漏了未跟踪文件」，
# 事实相反：
#   · `git clone` 只复制提交，未跟踪文件根本不会进 clone，所以它们只可能让 clone
#     里的闸门**失败**（文件不存在），不可能让它假绿；
#   · 真正会让绿失去意义的，是已跟踪文件与 HEAD 不一致 —— 那才叫「clone 里跑的是
#     旧代码」；
#   · 顺带一个实际收益：用户自己的未跟踪在制品（例如 `design/`）不该把一个与它
#     无关的重导出闸门挡在门外。
# 注意 clone 内部那句 `git status --porcelain` 保持**全量**（含未跟踪），两处范围
# 不同是有意的：clone 起始是干净的，闸门跑完冒出任何一条路径都说明 `.gitignore`
# 漏了东西，或者有 Godot 边车没提交 —— 那正是零漂移断言要抓的东西。
#
# 环境继承：本脚本**不导出任何签名变量**。`GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD`
# 必须在调用前就存在于 shell 里（它是闸门 B 唯一的必填输入，密钥库路径与别名由
# gate-b.sh 自己解析默认值）。否则 clone 里的闸门 B 会在第一步守卫处停下，而失败
# 原因看起来像「仓库状态不够」—— 那会把人引向错误的修法。
#
# 本脚本不复制任何检查逻辑：命令、阈值、断言全在 `mobile/tools/gate-b.sh` 里，这里
# 只负责调度与零漂移断言。想改判据，去改闸门。
#
# 诚实说明：Godot、导出模板、JDK、Android SDK 与 release 密钥库都是**机器状态**，
# 不随仓库走。本脚本证明的是**仓库状态**足够导出，不是一台全新机器足够。后一条
# 结论只能由按 `mobile/BUILD.md` 第八节操作的人给出。

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# 入口守卫：只看已跟踪文件。clone 复制的是提交，未跟踪文件进不了 clone。
if [[ -n "$(git -C "$repo_root" status --porcelain --untracked-files=no)" ]]; then
    echo "✗ 已跟踪文件与 HEAD 不一致，干净 clone 只能验证已提交状态" >&2
    echo "  先提交（或还原）下面这些路径再运行：" >&2
    git -C "$repo_root" status --porcelain --untracked-files=no | sed 's/^/    /' >&2
    exit 2
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "▸ 克隆已提交状态到临时目录…"
git clone --quiet "$repo_root" "$tmp/clone"
cd "$tmp/clone"

# Godot 导入边车必须逐个点名断言，不能笼统一句「边车都在」。
#   · `.import` 钉住导入参数与目标路径；
#   · `.uid` 钉住脚本 UID。
# 它们不是可有可无的缓存：漏提交的代价是每台机器重新抽签导入参数与资源 UID，
# 产物随之漂移。先断言的好处是失败信息直指「上游漏提交」—— 否则闸门 B 跑完后
# 只会以一条含糊的 `?? …/*.import` 报错，下一个人多半会去改 `.gitignore`，
# 而正确修法是补提交。
sidecars=(
    "mobile/src/smoke/smoke_screen.gd.uid"
    "mobile/tools/check_pack.gd.uid"
    "mobile/tools/glyph_coverage.gd.uid"
    "mobile/assets/fonts/NotoSansSC-Subset.ttf.import"
    "mobile/assets/fonts/NotoSansSymbols2-Subset.ttf.import"
)

echo "▸ 断言五个 Godot 导入边车在 clone 里是已跟踪文件…"
for sidecar in "${sidecars[@]}"; do
    if ! git -C "$tmp/clone" ls-files --error-unmatch "$sidecar" > /dev/null 2>&1; then
        echo "✗ clone 里没有已跟踪的 ${sidecar}" >&2
        echo "  这不是本脚本的失败，是上游漏提交：把该文件 git add 后重新提交。" >&2
        echo "  不要把它加进 .gitignore —— 忽略导入边车会让每台机器重新抽签导入参数。" >&2
        exit 1
    fi
done
echo "  ✓ 五个导入边车在 clone 里都是已跟踪文件"

echo "▸ 在干净 clone 上跑闸门 B（doctor 五项 → 闸门 A → 导出 → 四段静态校验）…"
bash mobile/tools/gate-b.sh

# 零漂移断言：全量（含未跟踪）。clone 起始是干净的，闸门跑完如果冒出任何一条
# 路径，说明 `.gitignore` 漏了某类生成物，或者有 Godot 边车没提交（`*.import` /
# `*.uid` 会以 `??` 出现）—— 与入口守卫的 `--untracked-files=no` 范围不同，有意为之。
if [[ -n "$(git status --porcelain)" ]]; then
    echo "✗ clone 工作区出现漂移（`.gitignore` 漏项或边车未提交）:" >&2
    git status --porcelain >&2
    exit 1
fi

echo "· APK: mobile/build/fifa-trainer.apk（$(wc -c < mobile/build/fifa-trainer.apk | tr -d ' ') 字节）"
echo "· 这份产物由 clone 内的闸门 B 重新导出，不是本机上一轮的残留"
echo "✓ 干净 clone 重导出成功：闸门 B 全绿，工作区无漂移"
