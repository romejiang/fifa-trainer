---
phase: 01-repo-split-config-single-source
plan: 01
subsystem: infra
tags: [repo-tooling, baseline-snapshot, uv-lockfile, python-stdlib]

# Dependency graph
requires: []
provides:
  - "tools/collect_checks.py：注入 check() 记录器导出检查项名称（不解析 stdout）"
  - "shared/expected_checks.txt：搬迁前 230 行检查项基线，SHA-256 724b40a3904ddd37be432967f96ff99b8427e6b2e2e6369ef4b7b9f41a0a596a"
  - "根 pyproject.toml 的 [[tool.uv.index]] 固定段（pypi.org/simple, default = true）"
affects: [01-02, 01-04, 01-05]

# Actuals (#2632) — 与计划的 estimate 同尺度（chars/4 over realized diff）
actuals:
  tokens: 2947
  tasks: 3
  commits: 3
  plan_head_before: 131b445850202f8725837df51a2fe4bbfdd48df9
  plan_head_after: 07a11705e298df4eec78c7a27a1ca8521ba80a94

tech-stack:
  added: []
  patterns:
    - "importlib.util.spec_from_file_location 进程内加载非包测试脚本，替换模块级 check() 记录名称"
    - "基线快照在看板写入前生成并单独提交，之后视为只读历史事实"
    - "[[tool.uv.index]] default = true 抵消本机 ~/.config/uv/uv.toml 的镜像设置"

key-files:
  created:
    - tools/collect_checks.py
    - shared/expected_checks.txt
  modified:
    - pyproject.toml

key-decisions:
  - "基线 SHA-256 = 724b40a3904ddd37be432967f96ff99b8427e6b2e2e6369ef4b7b9f41a0a596a，供 01-02 的 tools/check_desktop.sh 钉成常量"
  - "名称按 LC_ALL=C sort 排序后落盘：UTF-8 码点序 == 字节序，本地 BSD sort 与 CI GNU sort 结果一致"
  - "INFRA-01 不在本计划标记为完成：本计划只交付「搬迁前基线」这一前置条件，真正的仓库拆分与 230 项闸门由 01-02 收口"

patterns-established:
  - "检查项名称采集：进程内注入记录器，绝不解析带 ANSI 码与运行时测量值的 stdout"
  - "锁文件防护：只跑 uv lock --check（只读），从不裸跑 uv sync"

requirements-completed: []

coverage:
  - id: D1
    description: "tools/collect_checks.py 能把任一自建 check() 测试脚本的检查项名称导出为 UTF-8 TSV"
    requirement: INFRA-01
    verification:
      - kind: unit
        ref: "uv run --no-sync python tools/collect_checks.py tests/test_detectors.py --out /tmp/cc_det.tsv（182 行）；tests/test_gui_smoke.py（48 行）"
        status: pass
    human_judgment: false
  - id: D2
    description: "shared/expected_checks.txt 为搬迁前 230 行检查项基线，可逐字节复现且此后不可重新生成"
    requirement: INFRA-01
    verification:
      - kind: other
        ref: "重提取 + LC_ALL=C sort 后 diff -u shared/expected_checks.txt（空输出）；230 行 / 去重 230 / git ls-files --error-unmatch 通过"
        status: pass
    human_judgment: false
  - id: D3
    description: "根 pyproject.toml 固定 PyPI 索引，使 uv.lock 不再被本机 aliyun 镜像改写"
    requirement: INFRA-01
    verification:
      - kind: other
        ref: "uv lock --check（退出 0）、git status --porcelain -- uv.lock（空）、uv.lock SHA-256 763caf7b… 未变"
        status: pass
    human_judgment: false

# Metrics
duration: 2min
completed: 2026-11-04
status: complete
---

# Phase 01 Plan 01: 搬迁前冻结 230 项检查基线 + 固定 PyPI 索引 Summary

**从搬迁前的扁平仓库提取出 182 + 48 = 230 条唯一检查项名称并单独提交为不可再生基线（SHA-256 `724b40a3…596a`），同时把 `[[tool.uv.index]]` 固定到 pypi.org，使 `uv lock --check` 由退出 1 变为退出 0 且 `uv.lock` 逐字节不变。**

## Performance

- **Duration:** ~2 min
- **Started:** 2026-11-03T20:19:53Z
- **Completed:** 2026-11-03T20:21:14Z
- **Tasks:** 3/3
- **Files modified:** 3（2 新建 + 1 修改）

## Accomplishments

- `tools/collect_checks.py`：标准库实现的采集器，`importlib` 按文件加载测试脚本、替换模块级 `check()` 记录 label，再调用原函数保留 PASS/FAIL 计数与彩色输出；两套件分进程运行，互不污染 pygame 全局状态。
- `shared/expected_checks.txt`：**搬迁前**生成的 230 行基线（`test_detectors.py` 182 行 + `test_gui_smoke.py` 48 行），`LC_ALL=C` 排序、UTF-8 无 BOM、LF、结尾换行、230 行全部唯一、每行恰好 2 个 TAB 分隔字段；`tests/` 零改动。
- 根 `pyproject.toml` 追加 `[[tool.uv.index]] url = "https://pypi.org/simple"`、`default = true`，抵消本机 `~/.config/uv/uv.toml` 的 aliyun 镜像；`uv.lock` 前后 SHA-256 均为 `763caf7b45feb218b3e353d8014e242fe3f6f88290c0ca1834bade28975fcb4f`。

## Task Commits

Each task was committed atomically:

1. **Task 1: 检查项名称采集器（不解析 stdout 的端到端路径）** - `07d034f` (feat)
2. **Task 2: 生成并提交 230 行基线（搬迁前，不可再生）** - `e4d826c` (chore)
3. **Task 3: 固定 PyPI 索引，让锁文件不再被本机镜像改写** - `07a1170` (build)

**Plan metadata:** 见本次执行末尾的 `docs(01-01)` 提交

## Files Created/Modified

- `tools/collect_checks.py` - 检查项名称采集器（`main(argv: Optional[List[str]] = None) -> int`，位置参数 `test_script`，必需 `--out`）
- `shared/expected_checks.txt` - 230 行基线（套件名 TAB 检查项名称，`LC_ALL=C` 排序）
- `pyproject.toml` - 追加 `[[tool.uv.index]]` 固定段（+5 行，含一行中文说明注释）

## 关键事实（供后续计划引用）

| 项目 | 值 |
|------|-----|
| 基线行数 | 182（test_detectors.py）+ 48（test_gui_smoke.py）= **230**，去重仍 230 |
| 基线 SHA-256 | `724b40a3904ddd37be432967f96ff99b8427e6b2e2e6369ef4b7b9f41a0a596a` |
| 基线提交 | `e4d826c`（`git log --oneline -- shared/expected_checks.txt` 仅此一条，且历史中不存在任何 `desktop/` 路径提交） |
| `uv lock --check` 退出码 | 改动前 **1**（本机镜像导致锁文件被判过期）→ 改动后 **0** |
| `uv.lock` SHA-256 | `763caf7b45feb218b3e353d8014e242fe3f6f88290c0ca1834bade28975fcb4f`（前后一致） |
| 本计划提交数 | 3（`git rev-list --count 131b445..07a1170`） |

## Decisions Made

- **基线排序用 `LC_ALL=C sort`**：UTF-8 码点序等于字节序，规避 BSD sort 与 GNU sort 的 locale collation 差异（Pitfall 6）。01-02 复现时须沿用同一条命令。
- **采集器保留原 `check()` 调用**：测试自身的 PASS/FAIL 统计和彩色输出不变，`tests/` 无需任何改动，采集与测试共用唯一实现。
- **`uv.lock` 只读校验**：全程只运行 `uv lock --check`，未裸跑 `uv sync`，锁文件字节未变。
- **不在本计划标记 INFRA-01 完成**：需求原文是「仓库拆分为 desktop/mobile/shared，230 项检查全部通过」；本计划只交付其前置条件（基线 + 索引固定），拆分与闸门由 01-02 收口。REQUIREMENTS.md 保持未勾选是正确的。

## Deviations from Plan

None - plan executed exactly as written.

（执行环境说明：按 `<sequential_execution>` 在主工作树 `main` 分支直接提交；`.planning/config.json` 的 `branching_strategy` 为 `none`，即项目本身不使用阶段分支。）

## Issues Encountered

- Task 2 的 `<verify>` 链首次执行时无输出退出 1；逐段复跑显示采集、拼接、`diff`、行数断言全部通过，重跑整条链即 `TASK2 VERIFY PASSED`（瞬态，未改动任何文件）。最终以复跑结果为准。
- 执行开始时工作区已存在编排器留下的 `.planning/STATE.md`、`.planning/state.json` 改动与未跟踪的 `.planning/milestone.lock`；这些不属于本计划 `files_modified`，未被本计划的提交包含。

## Known Stubs

None.

## Threat Flags

None - 未引入计划 `<threat_model>` 之外的新信任边界（无网络端点、无认证路径、无 schema 变更）。

## Next Phase Readiness

- 01-02 可直接开始纯 `git mv`：工作区对 `pyproject.toml` / `uv.lock` / `shared/` / `tools/` 均干净，起点无残留内容改动。
- 01-02 的 `tools/check_desktop.sh` 应把 `BASELINE_SHA256` 钉为 `724b40a3904ddd37be432967f96ff99b8427e6b2e2e6369ef4b7b9f41a0a596a`，并在比对时沿用 `LC_ALL=C sort`。
- 基线文件此后不得重新生成或编辑（D-08）。

## Self-Check: PASSED

- `tools/collect_checks.py` 存在且已提交于 `07d034f`
- `shared/expected_checks.txt` 存在、230 行、已跟踪，提交于 `e4d826c`
- `pyproject.toml` 索引段已提交于 `07a1170`
- `uv lock --check` 退出 0；`uv.lock` 字节未变

---

*Phase: 01-repo-split-config-single-source*
*Completed: 2026-11-04*
