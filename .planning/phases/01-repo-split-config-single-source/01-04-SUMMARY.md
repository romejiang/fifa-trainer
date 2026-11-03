---
phase: 01-repo-split-config-single-source
plan: 04
subsystem: infra
tags: [readme, repo-map, github-actions, ci-gate, sha-pinning, mobile-docs]

# Dependency graph
requires:
  - phase: 01-repo-split-config-single-source
    plan: 02
    provides: "desktop/ 三子树布局、shared/skills_config.json 真源、tools/sync_config.py、tools/check_desktop.sh（230 项闸门）"
  - phase: 01-repo-split-config-single-source
    plan: 03
    provides: "三子树 .gitignore / .gitattributes（CI 文件不会被误忽略，YAML 未加 eol 规则）"
provides:
  - "README.md：71 行仓库地图（四类子树路径 + 跑桌面版 + 230 项闸门 + 配置真源 + 延伸阅读）"
  - "mobile/README.md：22 行移动端说明（Phase 2 才创建 project.godot，assets/config 副本只读）"
  - ".github/workflows/desktop-checks.yml：push(main) + PR 单 job CI，4 个 step，两个 action 按 40 位 commit SHA 固定"
affects: [01-05, phase-2-mobile-skeleton]

# Actuals (#2632) — 与计划的 estimate 同尺度（chars/4 over realized diff）
actuals:
  tokens: 1466
  tasks: 2
  commits: 2
  plan_head_before: 06349d44f41c138571d2dd82ba5c54524af50ccb
  plan_head_after: 76fec53e1e821f00e367aebf67561ddd76043b83

tech-stack:
  added: []
  patterns:
    - "根文档只做导航：仓库地图 71 行，桌面手册保持单一位置（desktop/README.md 776 行不改）"
    - "CI 复用同一脚本：workflow 只有「检出 → 装 uv → uv sync --locked → bash tools/check_desktop.sh」四步，不写第二套检查逻辑"
    - "第三方 action 按 40 位 commit SHA 固定并附 # vX.Y.Z 注释，run 步骤零 ${{ }} 插值"
    - "锁文件漂移单独变红：cd desktop && uv sync --locked 是独立 step，不会被后续闸门吞掉"

key-files:
  created:
    - README.md
    - mobile/README.md
    - .github/workflows/desktop-checks.yml
  modified:
    - .planning/phases/01-repo-split-config-single-source/deferred-items.md

key-decisions:
  - "根 README 只做地图（71 行）：桌面操作细节全部留在 desktop/README.md，避免两份手册互相漂移（D-03）"
  - "README 用「不要用 --project 指向 desktop 再传相对测试路径（如 tests/test_detectors.py）」描述失败形态，不复制可直接粘贴的坏命令 —— 否则文档里就躺着一条会 Failed to spawn 的示例"
  - "CI 只有 4 个 step：检出 → 安装 uv（0.9.5 / 3.12 / 缓存）→ cd desktop && uv sync --locked → bash tools/check_desktop.sh；不额外插一个 sync_config 步骤（闸门内部第一步已经做了，重复即第二套定义）"
  - "setup-uv 的 version 钉 0.9.5：与本机生成 uv.lock 的版本一致，避免新 uv 升级锁文件格式后 --locked 误红"
  - "mobile/README.md 明确 Phase 2 才创建 project.godot（D-10），本计划只加文档，不加任何 Godot 文件"

patterns-established:
  - "文档三层：根 README（地图）→ desktop/README.md / mobile/README.md（各自手册）→ .planning/codebase/（代码地图）"
  - "CI 与本地同一条命令：bash tools/check_desktop.sh 是 230 项检查的唯一入口，workflow 里不出现任何测试命令"

requirements-completed: [INFRA-01]

coverage:
  - id: D1
    description: "只读根 README 就能定位三棵子树、跑起桌面版、跑完 230 项检查，并知道改哪个文件才是改配置"
    requirement: INFRA-01
    verification:
      - kind: other
        ref: "README.md 71 行；plan 的 readme-map-ok 断言全过（10 个必需入口字符串、无 uv run --project desktop tests/ 形态）；desktop/README.md 仍 776 行且 git log --follow 2 条"
        status: pass
    human_judgment: false
  - id: D2
    description: "mobile/README.md 说明 Phase 2 才创建 project.godot，assets/config 下是生成副本不可手改"
    requirement: INFRA-01
    verification:
      - kind: other
        ref: "mobile/README.md 22 行（<30），含 assets/config 与 shared/；仓库内仍无 project.godot（find mobile -name project.godot 为空）"
        status: pass
    human_judgment: false
  - id: D3
    description: "CI 工作流可解析、4 个 step、两个 action 按 40 位 SHA 固定、run 步骤零插值"
    requirement: INFRA-01
    verification:
      - kind: other
        ref: "python3 + yaml.safe_load → ci-ok 4；uses 正则 @[0-9a-f]{40}$ 全部命中；无 ${{ / continue-on-error"
        status: pass
    human_judgment: false
  - id: D4
    description: "文档与 CI 落地后，230 项桌面检查仍全绿"
    requirement: INFRA-01
    verification:
      - kind: integration
        ref: "bash tools/check_desktop.sh → rc=0，182 + 48 = 230，末行「✓ 230 项检查全部通过，名称与基线逐项一致」"
        status: pass
    human_judgment: false

# Metrics
duration: 2min
completed: 2026-11-04
status: complete
---

# Phase 01 Plan 04: 根 README 仓库地图 + GitHub Actions 闸门 Summary

**根 `README.md` 从「776 行桌面手册」变成「71 行仓库地图」（桌面手册原样留在 `desktop/README.md`、内容零改动），新增 22 行 `mobile/README.md` 说明 Phase 2 才建 `project.godot`，并把同一条 `bash tools/check_desktop.sh` 接进 GitHub Actions —— 4 个 step、两个 action 按 40 位 commit SHA 固定、run 步骤零 `${{ }}` 插值。**

## Performance

- **Duration:** ~2 min
- **Started:** 2026-11-03T20:35:35Z
- **Completed:** 2026-11-03T20:37:14Z
- **Tasks:** 2/2
- **Files modified:** 3 新建 + 1 计划文档（`deferred-items.md` 追加结论）

## Accomplishments

- **根目录第一次有了「仓库地图」**：`README.md` 71 行（硬上限 120），六个中文编号章节 —— 这是什么 / 目录地图 / 跑桌面版 / 跑回归检查 / 改配置 / 进一步阅读。四类子树用 `名称 —— 职责` 对齐列表（照 `desktop/padskills/__init__.py` 的模块地图范式），命令一律 `cd desktop` 后执行，并明确写出 `uv --directory desktop run …` 等价写法。桌面安装、打包、排障细节一行都没搬过来。
- **`desktop/README.md` 一个字符都没动**：仍 776 行，`git log --follow` 2 条（`02b03db` + `5e489a1 Initial commit`），搬迁历史完整。
- **`mobile/README.md` 落地（D-10）**：22 行，明确「Phase 1 只有配置副本，没有 Godot 工程」「`project.godot` 由 Phase 2 创建」，并写明 `mobile/assets/config/skills_config.json` 及其 `.sha256` 是 `tools/sync_config.py` 生成的只读副本、真源在 `shared/skills_config.json`。仓库内仍未出现 `project.godot`。
- **CI 与本地共用一条闸门命令**：`.github/workflows/desktop-checks.yml` 在 `push`（main）与 `pull_request` 触发，单 job `desktop` / `ubuntu-latest`，4 个 step：检出 → 安装 uv（0.9.5 / 3.12 / enable-cache）→ `cd desktop && uv sync --locked` → `bash tools/check_desktop.sh`。锁文件漂移有独立的红色 step，不会被后面的闸门吞掉；CI 里没有任何测试命令或 `sync_config.py` 的第二份调用（闸门内部第一步已经做了）。
- **供应链固定**：`actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1  # v7.0.1`、`astral-sh/setup-uv@68559e99cc807c1eb7e9238fd43a15bba460eec2  # v10.3.3`，均为 40 位 commit SHA；无 secrets、无 `${{ }}` 插值、无 `continue-on-error`。
- **闸门仍全绿**：`bash tools/check_desktop.sh` → rc=0，182 + 48 = 230，名称与基线逐项一致；基线 SHA-256 `724b40a3…596a`、真源 `bccf123a…eee9`、两份副本哈希均未变。

## 关键事实（供 01-05 与后续阶段引用）

| 项目 | 值 |
|------|-----|
| 根 `README.md` 行数 | **71**（< 120） |
| `mobile/README.md` 行数 | **22**（≤ 30） |
| `desktop/README.md` 行数 | **776**（未改动） |
| `git log --follow -- desktop/README.md` | **2** 条：`02b03db`、`5e489a1 Initial commit` |
| workflow 解析出的 step 数 | **4** |
| `actions/checkout` | `3d3c42e5aac5ba805825da76410c181273ba90b1`（# v7.0.1） |
| `astral-sh/setup-uv` | `68559e99cc807c1eb7e9238fd43a15bba460eec2`（# v10.3.3） |
| 触发事件 | `push` (branches: [main]) + `pull_request` |
| `bash tools/check_desktop.sh` | rc=**0**，`182 + 48 = 230`，末行「✓ 230 项检查全部通过，名称与基线逐项一致」 |
| `shared/expected_checks.txt` SHA-256 | `724b40a3904ddd37be432967f96ff99b8427e6b2e2e6369ef4b7b9f41a0a596a`（未重生成） |
| `shared/skills_config.json` SHA-256 | `bccf123a06efc61c7f05bc430e488a0f596bdc1e5c7eade4c18a3660f9d0eee9`（未改） |

### `python3 -c` 校验输出（plan Task 2 的 `<automated>`）

```text
$ python3 -c "import re, yaml; t = open('.github/workflows/desktop-checks.yml', ...); ..."
ci-ok 4
```

同一次解析的结构快照：

```text
top-level keys: ['name', True, 'jobs']          # PyYAML 按 YAML 1.1 把 on 解析成 True，属正常
name: desktop-checks
triggers: {'push': {'branches': ['main']}, 'pull_request': None}
runs-on: ubuntu-latest
1 | 检出仓库              | actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1
2 | 安装 uv               | astral-sh/setup-uv@68559e99cc807c1eb7e9238fd43a15bba460eec2
    with: {'version': '0.9.5', 'python-version': '3.12', 'enable-cache': True}
3 | 锁文件必须与 pyproject 一致 | cd desktop && uv sync --locked
4 | 桌面回归闸门          | bash tools/check_desktop.sh
```

### Task 1 的 `readme-map-ok` 断言

```text
$ git log --follow --oneline -- desktop/README.md | wc -l   → 2
$ desktop/README.md 行数                                    → 776
$ README.md 行数                                            → 71 (< 120)
$ 10 个必需入口字符串                                        → 全部命中
  desktop/ · mobile/ · shared/ · tools/ · cd desktop ·
  tools/check_desktop.sh · tools/sync_config.py ·
  desktop/README.md · mobile/README.md · .planning/codebase/
$ 禁止形态 uv run --project desktop tests/                   → 不存在
readme-map-ok
```

## Task Commits

Each task was committed atomically:

1. **Task 1: 根 README 改写为仓库地图 + 新增移动端说明** — `cf46aad` (docs) — tracer
2. **Task 2: GitHub Actions 复用桌面回归闸门（action 按 SHA 固定）** — `76fec53` (chore)

**Plan metadata:** 见本次执行末尾的 `docs(01-04)` 提交

_注：Task 1 为 tracer 任务。auto_advance=false + human_verify_mode=end-of-phase + 仅自动化 verify，提交后已按 tracer feedback gate 重跑完整 `<verify>`（再次得到 `readme-map-ok`）并通过，无 human checkpoint，随后才展开 Task 2。_

## Files Created/Modified

- `README.md` — 新建，71 行仓库地图：这是什么 / 目录地图（四类子树）/ 跑桌面版 / 跑回归检查 / 改配置 / 进一步阅读
- `mobile/README.md` — 新建，22 行：移动端边界（Phase 2 才建 `project.godot`）、`assets/config` 副本只读、同步与校验命令
- `.github/workflows/desktop-checks.yml` — 新建，29 行：`name: desktop-checks`，push(main)+PR，单 job `desktop`，4 步，两个 action 按 40 位 SHA 固定
- `.planning/phases/01-repo-split-config-single-source/deferred-items.md` — 追加「01-04 的结论」：时序敏感用例不在本计划修复（`desktop/tests/` 禁止改动），CI 上线后会暴露抖动，处理归后续专项

## Decisions Made

- **根 README 只做地图**：D-03 要求原 776 行手册整体迁移、内容不改，因此根文档只保留导航与命令入口；任何桌面操作细节都指向 `desktop/README.md`，避免两份手册互相漂移。
- **坏命令只描述不复述**：plan 的 verify 明确断言 README 不含 `uv run --project desktop tests/`。初稿在警告句里原样引用了它，直接触发断言失败；改为「用 `--project` 指向 `desktop/` 再传相对测试路径（如 `tests/test_detectors.py`）」，既保留警告又不留下可粘贴的坏示例。
- **CI 不重复配置校验**：RESEARCH 的示例里有一个独立的 `sync_config.py --check` step，但 `tools/check_desktop.sh` 的第一步就是它。plan 的 prohibitions 明确「不得把 CI 写成第二套检查定义」，故只保留 4 步。
- **setup-uv 钉 0.9.5**：与本机生成 `uv.lock` 的版本一致；用最新 uv 可能因锁文件格式升级让 `--locked` 误红（RESEARCH A6）。
- **检出步骤补中文 name**：plan 只规定 `uses` 与行尾注释，未禁止命名；补 `检出仓库` 让 4 个 step 在 Actions UI 里都是可读中文，与项目「用户可见文本用中文」的约定一致。

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] 根 README 初稿在警告句里复述了被禁止的命令形态**
- **Found during:** Task 1（`README.md` 首次运行 `<automated>` 校验）
- **Issue:** 初稿写「**不要**用 `uv run --project desktop tests/test_detectors.py` 这种写法」，虽然语义是警告，但 plan 的 `<automated>` 断言 `! grep -qF 'uv run --project desktop tests/' README.md` 会因此变红 —— 文档里躺着的字符串本身就可能被读者复制执行。
- **Fix:** 改为「**不要**用 `--project` 指向 `desktop/` 再传相对测试路径（如 `tests/test_detectors.py`）—— 子进程的 cwd 仍是仓库根，会 `Failed to spawn`」。语义不变，坏命令不再可复制。
- **Files modified:** `README.md`
- **Verification:** 重跑完整 `<automated>` → `readme-map-ok`（提交后按 tracer gate 再跑一次，同样通过）
- **Committed in:** `cf46aad`（Task 1 提交）

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** 仅措辞调整；根 README 的六个章节、四类路径与两条命令入口全部按计划交付。

## Issues Encountered

- **CI 无法在本地执行**：`bash tools/check_desktop.sh` 已在本地 rc=0（230 项），但 workflow 的第一次真实运行只能发生在 push 之后。本地等价验证由 01-05 的干净 clone 脚本承担（同一脚本、同一命令）。
- **时序敏感用例仍可能让 CI 偶发红**：`deferred-items.md` 记录的 `test_engine_end_to_end` 在机器负载高时会失败。本计划 `files_modified` 不含 `desktop/tests/`，且 orchestrator 明确禁止改动 `desktop/`，因此**不在本计划处理**；已在 `deferred-items.md` 追加结论，留给后续专项（显式容差 / 单独重试 / 标注时序敏感，任选其一，都必须先记录再改）。
- **执行环境**：按 `<sequential_execution>` 在主工作树 `main` 分支直接提交（`.planning/config.json` 的 `branching_strategy` 为 `none`，与 01-01 / 01-02 / 01-03 一致）；未使用 `--no-verify`，仓库未配置 hooks。

## Deferred Issues

| Item | Reason | Suggested handling |
|------|--------|--------------------|
| `desktop/tests/test_detectors.py` 的 `test_engine_end_to_end` 对 OS 调度停顿敏感 | 本计划禁止改动 `desktop/`（`files_modified` 只有 3 个新文档/CI 文件） | 由后续专项决定：显式容差 / 单测重试 / 标记时序敏感；任何放宽必须先记录在案 |

## User Setup Required

None — 无外部服务、无密钥、无新增依赖。CI 首次运行需要在 GitHub 上 push 后观察。

## Known Stubs

None.

## Threat Flags

None — 未引入 `<threat_model>` 之外的新信任边界。T-01-11（action 按 SHA 固定、零 `${{ }}` / secrets / `continue-on-error`、CI 只调用同一脚本）、T-01-12（README 不含已知失败的命令形态）、T-01-SC（CI 不装额外 Python 包、uv 钉 0.9.5、`--locked` 且不关闭 hash 校验）三条缓解措施均已落地并被上面的命令验证。

## Next Phase Readiness

- **01-05**：干净 clone 脚本可复用 `bash tools/check_desktop.sh`；README 里的两条命令入口（`cd desktop && uv run app.py`、`bash tools/check_desktop.sh`）可直接作为「按 README 能复现」的断言对象。`.github/workflows/desktop-checks.yml` 已存在，clone 后不会被 `.gitignore` 命中（`git check-ignore` 未命中）。
- **Phase 2**：`mobile/README.md` 已声明「Phase 2 才创建 `project.godot`」，`mobile/` 下仍只有 `assets/config/` 两个生成副本；Phase 2 建工程时不会与本阶段产物冲突。
- **文档维护**：`.gitattributes` 未给 `*.yml` 加 eol 规则（01-03 的决定），CI 只在 Linux 跑，暂不需要。

---

## Self-Check: PASSED

- `README.md`（71 行）、`mobile/README.md`（22 行）、`.github/workflows/desktop-checks.yml`（29 行）均存在且已提交
- 提交 `cf46aad`（Task 1）与 `76fec53`（Task 2）均为 HEAD 祖先；`git rev-list --count 06349d4..HEAD` = 2
- 两次提交的 `--diff-filter=D` 均为空（无删除）
- `desktop/README.md` 仍 776 行、`git status` 对其无改动；`desktop/` 整棵子树在本计划区间零改动
- 闸门 `bash tools/check_desktop.sh` rc=0（182 + 48 = 230）；基线 SHA-256 与真源哈希均未变

---

*Phase: 01-repo-split-config-single-source*
*Completed: 2026-11-04*
