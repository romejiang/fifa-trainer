---
phase: 01-repo-split-config-single-source
plan: 05
subsystem: infra
tags: [clean-clone, regression-gate, tamper-counterexample, single-source-config, verification-script]

# Dependency graph
requires:
  - phase: 01-repo-split-config-single-source
    plan: 02
    provides: "tools/check_desktop.sh（230 项闸门）、tools/sync_config.py --check、desktop/ + mobile/ + shared/ 三子树、已提交的两份配置副本"
  - phase: 01-repo-split-config-single-source
    plan: 03
    provides: ".gitignore 三子树规则：.venv/ 与 __pycache__/ 在任意层级忽略，clone 跑完才可能零漂移"
  - phase: 01-repo-split-config-single-source
    plan: 04
    provides: "README.md 71 行仓库地图（本计划在小节四补一行入口，变成 73 行）+ CI 复用同一条闸门命令"
provides:
  - "tools/verify_clean_clone.sh：入口守卫（脏工作区 rc=2）→ git clone 到 mktemp → check_desktop.sh → sync_config.py --check → 零漂移断言；--tamper 追加篡改反例"
  - "README.md「四、跑回归检查」末尾一行入口（全文 73 行，仍 < 120）"
  - "ROADMAP 成功标准 4 的机械证明；01-VALIDATION 的 Manual-Only「干净 clone 复现」不再需要人工执行"
affects: [phase-2-mobile-skeleton]

# Actuals (#2632) — 与计划的 estimate 同尺度（chars/4 over realized diff）
actuals:
  tokens: 1277
  tasks: 2
  commits: 2
  plan_head_before: 29e279a6cbfad2450b409cb30f1e56a9bf06b6a0
  plan_head_after: 173124dcbdc0a04d36ad070d4441f42fb0613260

tech-stack:
  added: []
  patterns:
    - "干净 clone 复现四步：入口守卫 → git clone（不是 cp -R 工作区）→ 原样调用既有闸门 → 零漂移断言；不复制任何检查逻辑与数量"
    - "反例用 if 捕获期望失败的退出码并断言输出里出现被点名文件，禁止 || true 吞码后照样打印成功"
    - "mktemp -d + trap 'rm -rf' EXIT：成功与失败路径都不在磁盘上留残留"

key-files:
  created:
    - tools/verify_clean_clone.sh
  modified:
    - README.md

key-decisions:
  - "入口守卫用 rc=2（区别于检查失败的 rc=1）：脏工作区不是「验证失败」，而是「验证对象不接受」——clone 只复制提交，脏树下的绿指向旧代码"
  - "零漂移断言放在 clone 内而不是源仓库：它证明的是 .venv/ 与 __pycache__/ 的忽略规则在全新检出上也成立，而不是本机恰好干净"
  - "反例选 mobile/assets/config/skills_config.json 而不是桌面副本：两份副本对 --check 一视同仁，但移动端副本没有运行期消费者，篡改不会在 clone 里触发桌面测试的连带失败，反例只暴露配置闸门本身"
  - "反例的第 4 步不只看 --check 变绿，还追加 git status --porcelain 为空：证明 git checkout -- 把 clone 完整还原了，失败确实来自篡改"
  - "README 只加一行、放在「四、跑回归检查」末尾：根文档仍是地图，不复制脚本用法说明（细节在脚本头注释里）"
  - "不写死 230、不写死任何测试命令、不写死本机路径：脚本只调度 check_desktop.sh 与 sync_config.py，检查定义仍只有一份"

patterns-established:
  - "验证脚本的两种退出码语义：2 = 输入/前置条件不合法（脏工作区、未知参数），1 = 验证结论为红"
  - "反例三段式：篡改 → 两道关卡各自非零且点名文件 → 还原后重新变绿；缺一段就退出 1"

requirements-completed: [INFRA-01, INFRA-02]

coverage:
  - id: D1
    description: "干净 clone 上 230 项检查全绿 + 配置一致，一条命令可复现（成功标准 4）"
    requirement: INFRA-01
    verification:
      - kind: integration
        ref: "bash tools/verify_clean_clone.sh → rc=0；clone 内输出 182 项 + 48 项 + 「✓ 230 项检查全部通过，名称与基线逐项一致」+「✓ 干净 clone 复现成功：230 项检查全绿，配置一致，工作区无漂移」"
        status: pass
    human_judgment: false
  - id: D2
    description: "手改副本后被 sync_config.py --check 与回归闸门同时抓住，且输出指名文件（成功标准 2）"
    requirement: INFRA-02
    verification:
      - kind: integration
        ref: "bash tools/verify_clean_clone.sh --tamper → rc=0；日志第 313–317 行：反例 → 「✓ sync_config.py --check 抓住并指名 mobile/assets/config/skills_config.json」→ 原始报错行「✗ … 与真源不一致（副本只能由脚本生成，不能手改）」→「✓ 回归闸门同样被拦住」→「✓ 反例按预期失败」"
        status: pass
    human_judgment: false
  - id: D3
    description: "脏工作区时脚本以 rc=2 拒绝运行，不用陈旧提交冒充当前状态（成功标准 4 的反面）"
    requirement: INFRA-01
    verification:
      - kind: integration
        ref: "在真实仓库放置未跟踪探针 tools/.dirty-probe → bash tools/verify_clean_clone.sh → rc=2，stderr「✗ 工作区有未提交改动，干净 clone 只能验证已提交状态」+ 逐行 git status；删除探针后 git status 恢复为空"
        status: pass
    human_judgment: false
  - id: D4
    description: "验证脚本不污染仓库：两次运行后源仓库 git status --porcelain 为空，clone 由 trap 清理"
    requirement: INFRA-01
    verification:
      - kind: other
        ref: "正向与 --tamper 各跑一次后 `git status --porcelain` 均为空；脚本只在 mktemp -d 目录内作业并 trap 清理"
        status: pass
    human_judgment: false

# Metrics
duration: 2min
completed: 2026-11-04
status: complete
---

# Phase 01 Plan 05: 干净 clone 复现 + 篡改反例 Summary

**新增 `tools/verify_clean_clone.sh`：入口先拒绝脏工作区（rc=2），再用 `git clone` 把已提交状态拉到 `mktemp` 目录，原样调用 `bash tools/check_desktop.sh` 与 `python3 tools/sync_config.py --check`，最后断言 clone 跑完 `git status --porcelain` 为空；`--tamper` 追加反例，手改移动端副本会被配置校验与回归闸门同时抓住并指名文件，还原后重新变绿。**

## Performance

- **Duration:** ~2 min
- **Started:** 2026-11-03T20:39:56Z
- **Completed:** 2026-11-03T20:41:59Z
- **Tasks:** 2/2
- **Files modified:** 1 新建（`tools/verify_clean_clone.sh`，111 行）+ 1 修改（`README.md`，+2 行）

## Accomplishments

- **「不依赖本机残留状态」第一次有了机械证明**：脚本 `git clone` 到 `mktemp -d` 下的临时目录（禁止 `cp -R` 工作区），在全新检出上跑同一条闸门 —— 没有 `.venv`、没有 `__pycache__`、没有历史产物，`uv sync --locked` 在 clone 里从零建了 3.12 虚拟环境并装上 `pygame-ce==2.5.8`。
- **入口守卫不是形式主义**：`git status --porcelain` 非空即以 **rc=2** 结束并打印「✗ 工作区有未提交改动，干净 clone 只能验证已提交状态」+ 逐行状态。这把「用陈旧提交冒充当前状态」这条最容易自欺的路直接封掉；退出码 2 与检查失败的 1 区分开，语义是「不接受这次运行」而不是「跑出红」。
- **零漂移断言证明忽略规则在全新检出上成立**：闸门跑完立刻断言 `git status --porcelain` 为空。若 `.venv/` 只在根生效或 `__pycache__` 漏写，这一步会当场变红 —— 而不是等到某天有人抱怨「跑一次仓库就脏了」。
- **反例真的会咬人**：`--tamper` 在同一个 clone 里 `printf ' ' >> mobile/assets/config/skills_config.json`（字节不同、仍是合法 JSON），随后 `sync_config.py --check` 与 `check_desktop.sh` **各自**非零退出，输出点名该文件；`git checkout --` 还原后 `--check` 与 `git status --porcelain` 双双恢复，才打印成功行。
- **没有第二套检查定义**：脚本里不出现任何测试路径、检查项数量或阈值，只有 `bash tools/check_desktop.sh` 与 `python3 tools/sync_config.py --check` 两条调用 —— 检查定义仍只有一份，闸门改了脚本自动跟随。
- **根 README 保持地图形态**：只在「四、跑回归检查」末尾加一行入口，全文 71 → **73 行**（硬上限 120）。

### 正向运行输出摘要（`bash tools/verify_clean_clone.sh`，rc=0）

```text
▸ 克隆已提交状态到临时目录…
▸ 在干净 clone 上跑回归闸门…
▸ 校验配置副本…
▸ 校验基线未被重新生成…
▸ 同步依赖（锁文件必须已是最新）…
Using CPython 3.12.12
Creating virtual environment at: .venv
Resolved 11 packages in 7ms
Installed 1 package in 11ms
 + pygame-ce==2.5.8
  …
  通过 182 项，失败 0 项                          ← 第 253 行
  …
  通过 48 项，失败 0 项                           ← 第 308 行
✓ 230 项检查全部通过，名称与基线逐项一致          ← 第 310 行
▸ 校验配置单一真源…
✓ 干净 clone 复现成功：230 项检查全绿，配置一致，工作区无漂移
```

`/tmp/clean_clone.log` 共 312 行，两套件输出完整（182 项检测器 + 48 项 GUI 冒烟），无一处 ✗。

### 反例运行输出摘要（`bash tools/verify_clean_clone.sh --tamper`，rc=0，日志第 312–317 行）

```text
✓ 干净 clone 复现成功：230 项检查全绿，配置一致，工作区无漂移
▸ 反例：手改移动端副本 mobile/assets/config/skills_config.json…
  ✓ sync_config.py --check 抓住并指名 mobile/assets/config/skills_config.json
    ✗ mobile/assets/config/skills_config.json 与真源不一致（副本只能由脚本生成，不能手改）
  ✓ 回归闸门同样被拦住
✓ 反例按预期失败：手改副本被 --check 与闸门同时抓住，还原后恢复绿
```

被抓住的路径 `mobile/assets/config/skills_config.json` 出现三次：脚本主动打印一次、`--check` 原始报错行一次、成功行一次。期望失败全部用 `if` 捕获退出码，全脚本 **零 `|| true`**。

### 守卫行为（另外两条 acceptance）

```text
$ : > tools/.dirty-probe && bash tools/verify_clean_clone.sh    → rc=2
✗ 工作区有未提交改动，干净 clone 只能验证已提交状态
?? tools/.dirty-probe
$ rm tools/.dirty-probe                                        → git status 恢复为空

$ bash tools/verify_clean_clone.sh --bogus                      → rc=2
✗ 未知参数：--bogus（只接受留空或 --tamper）
```

### 源仓库零污染（plan `<output>` 明确要求的事实）

| 时点 | `git status --porcelain` |
|------|--------------------------|
| 正向运行结束后 | 空 |
| `--tamper` 运行结束后 | 空 |
| 两次运行之间的提交前后 | 空 |

`git diff --stat 29e279a..HEAD` 只有 `README.md`（+2）与 `tools/verify_clean_clone.sh`（+111）；`desktop/`、`shared/`、`tools/check_desktop.sh` 零改动；`shared/expected_checks.txt` 的 SHA-256 仍是 `724b40a3904ddd37be432967f96ff99b8427e6b2e2e6369ef4b7b9f41a0a596a`。

## Task Commits

Each task was committed atomically:

1. **Task 1: 干净 clone 复现脚本（正向路径）** — `2bf002d` (feat) — tracer
2. **Task 2: `--tamper` 反例模式 + README 入口** — `173124d` (test)

**Plan metadata:** 见本次执行末尾的 `docs(01-05)` 提交

_注：Task 1 为 tracer 任务。auto_advance=false + human_verify_mode=end-of-phase + 仅自动化 verify，提交后重跑完整 `<verify>`（rc=0，日志含「干净 clone」与 230）通过，无 human checkpoint，随后才展开 Task 2。_

## Files Created/Modified

- `tools/verify_clean_clone.sh` — 新建，111 行：`#!/usr/bin/env bash` + 中文用途注释；`set -euo pipefail`；`repo_root` 由 `BASH_SOURCE` 锚定。结构：`case "$1"` 校验参数 → 入口守卫（rc=2）→ `mktemp -d` + `trap` → `git clone --quiet` → `bash tools/check_desktop.sh` → `python3 tools/sync_config.py --check` → 零漂移断言 → `--tamper` 三段式反例。
- `README.md` — 修改，+2 行（含空行）：在「四、跑回归检查」末尾加一行入口，说明脚本会 clone 已提交状态、重放闸门、断言零漂移，`--tamper` 额外验证手改副本必被抓住。全文 71 → 73 行。

## Decisions Made

- **rc=2 专用于「不接受这次运行」**：脏工作区与未知参数都返回 2，检查结论为红才返回 1。这样在 CI 或脚本调用侧能区分「环境不合法」与「代码有问题」。
- **反例选移动端副本**：两份副本对 `--check` 完全等价，但 `mobile/` 下的副本没有运行期消费者；篡改它不会在 clone 里连带触发桌面测试的异常，反例只暴露配置闸门本身这一件事。
- **反例第 4 步加 `git status --porcelain`**：plan 只要求 `--check` 恢复绿，实测再加一条零漂移断言，能同时证明「还原彻底」与「clone 没被之前的运行弄脏」。
- **把抓人的原始报错行打进日志**（`grep -F "$target" | sed 's/^/    /'`）：读日志的人不需要相信一句「✓ 抓住了」。为了避免 `set -o pipefail` 下 `grep` 空匹配导致静默退出 1，前面的断言改成**必须**出现 `$target`（不再接受「不一致」作为替代命中）。
- **README 只加一行**：脚本用法写在脚本头注释里，根文档保持地图形态，避免第三份用法说明漂移。

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `$var` 紧跟中文/省略号导致 unbound variable（两处）**
- **Found during:** Task 2 首次 `--tamper` 运行（`tools/verify_clean_clone.sh: line 71: target…: unbound variable`）
- **Issue:** 中文句子里的 `$target…` 与 `$mode（` 中，紧跟变量名的是多字节字符；在 `set -u` 下 bash 把 `…` / `（` 的首字节算进变量名，于是引用了一个不存在的变量，脚本在第 71 行直接退出，反例根本没开始跑。
- **Fix:** 两处都改成 `${target}` / `${mode}` 形式；并加了一条机械扫描（正则 `\$[A-Za-z_][A-Za-z0-9_]*` 匹配到后一个字符是 `ord > 127` 即报错，结果 `scan bad = 0`）防止再犯。
- **Files modified:** `tools/verify_clean_clone.sh`
- **Verification:** 重跑 `bash tools/verify_clean_clone.sh --tamper` → rc=0，反例三行证据齐全；`bash -n` 语法检查通过
- **Committed in:** `173124d`（Task 2 提交；发现时该提交尚未记录到任何 SUMMARY，用 `git commit --amend` 就地修正，避免留下一条「已知会崩」的历史）

### Scope Note（非缺陷，但值得记下）

**`--tamper` 模式的代码随 Task 1 的提交一起落地。** 两个任务共用同一个文件，我在 Task 1 写脚本时就把 `--tamper` 分支一并写完并提交（`2bf002d`），Task 2 因此只补了 README 入口与反例证据面的两处强化（把原始报错行进日志、还原后加零漂移断言）。功能与验收不受影响（两个任务的 acceptance 全部实测通过），但 Task 2 的 diff 比 plan 描述的更小。若要严格按任务切分，本应在 Task 1 里删掉 `--tamper` 分支、Task 2 再加回来 —— 那只是制造一次无意义的删改，故按现在的方式落地并在此记录。

---

**Total deviations:** 1 auto-fixed (1 bug) + 1 scope note
**Impact on plan:** 验证逻辑、退出码语义、输出文案与 plan 逐条对齐；反例比 plan 多一条「还原后零漂移」断言，属加强不是放宽。

## Issues Encountered

- **clone 内的 `uv sync --locked` 依赖本机 uv 缓存或网络**：本机 uv 0.9.5 + 已有缓存，`Resolved 11 packages in 7ms / Installed 1 package in 11ms`，全程 < 2 秒。CI 上等价（`ubuntu-latest` 有网络）。没有把 `--locked` 降级为裸 `uv sync` —— 锁文件钉死是刻意属性。
- **`01-04` 记录的时序敏感用例 `test_engine_end_to_end` 未复现**：本次共跑了 **4 次**完整干净 clone 闸门（Task 1 verify、rehearsal、最终正向、最终 `--tamper` 的正向段），每次都 182 + 48 全绿，没有一次抖动。结论仍是「暂不处理」，`deferred-items.md` 的判定不变。
- **执行环境**：按 `<sequential_execution>` 在主工作树 `main` 直接提交（`.planning/config.json` 的 `branching_strategy` 为 `none`，与 01-01 ~ 01-04 一致）；未使用 `--no-verify`。

## Deferred Issues

| Item | Reason | Suggested handling |
|------|--------|--------------------|
| `desktop/tests/test_detectors.py` 的 `test_engine_end_to_end` 对 OS 调度停顿敏感 | 沿用 01-04 的结论：`desktop/` 不在本计划 `files_modified` 内 | 由后续专项决定：显式容差 / 单测重试 / 标记时序敏感；任何放宽必须先记录在案 |

## User Setup Required

None — 脚本只用 `git`、`python3` 与仓库已声明的 `uv`，无外部服务、无密钥。

## Known Stubs

None.

## Threat Flags

None — 未引入 `<threat_model>` 之外的新信任边界。T-01-13（入口守卫 rc=2、`git clone` 而非复制工作区、零漂移断言）、T-01-14（反例四条件齐备、零 `|| true`、还原后双重确认）、T-01-SC（clone 内只走 `check_desktop.sh` 的 `uv sync --locked`，不装新包、不改锁文件）三条缓解措施均已落地并被上面的运行证据验证。

## Next Phase Readiness

- **ROADMAP 成功标准 4 已机械可证**：`bash tools/verify_clean_clone.sh` 一条命令即可在陌生机器上重放「230 全绿 + 配置一致 + 零漂移」；`01-VALIDATION.md` 里 Manual-Only 的「干净 clone 复现」一条之后不再需要人工执行。
- **成功标准 2 有了可执行反例**：`--tamper` 把「手改副本 → 两道关卡同时抓住 → 还原恢复绿」变成可重复的脚本行为，Phase 2 之后任何配置漂移都可先用它定位。
- **CI 可选择性加跑**：`.github/workflows/desktop-checks.yml` 目前只跑 `check_desktop.sh`（与本地同一条命令）。若想让 CI 也证明「零漂移」，追加一个 `bash tools/verify_clean_clone.sh` 步骤即可 —— 但它会在 CI 里重复一遍 clone + uv sync，本阶段未加，留作 Phase 2 之后的取舍。
- **Phase 2**：移动端只需保证 `mobile/assets/config/` 下的副本由 `sync_config.py` 生成；本脚本的零漂移断言会自动覆盖新增的 Godot 生成物（`.godot/`、`build/`、`export/` 已在 `.gitignore` 里）。

---

## Self-Check: PASSED

- `tools/verify_clean_clone.sh`（111 行）与 `README.md`（73 行）存在且已提交
- 提交 `2bf002d`（Task 1）与 `173124d`（Task 2）均为 HEAD 祖先；`git rev-list --count 29e279a..HEAD` = 2
- 两次提交的 `--diff-filter=D` 均为空（无删除）
- `bash tools/verify_clean_clone.sh` rc=0（含 182 / 48 / 230 与「干净 clone」）；`--tamper` rc=0（含反例、被点名文件、「按预期失败」）
- 两次运行后源仓库 `git status --porcelain` 为空；`desktop/`、`shared/`、`tools/check_desktop.sh` 零改动；基线 SHA-256 未变

---

*Phase: 01-repo-split-config-single-source*
*Completed: 2026-11-04*
