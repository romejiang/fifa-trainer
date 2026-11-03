---
phase: 01-repo-split-config-single-source
plan: 03
subsystem: infra
tags: [write-config-routing, single-source-config, gitignore, gitattributes, regression-gate, frozen-mode]

# Dependency graph
requires:
  - phase: 01-repo-split-config-single-source
    plan: 02
    provides: "desktop/ 三子树布局、shared/skills_config.json 真源、tools/sync_config.py、tools/check_desktop.sh（230 项闸门）"
provides:
  - "padskills.config.shared_config_path()：<repo>/shared/skills_config.json"
  - "padskills.config.write_config_target(explicit)：显式路径 > 冻结态用户目录 > 开发态真源"
  - "main.py --write-config 三级路由；-c/--config 默认值改为 None（运行期仍读 desktop/skills_config.json）"
  - ".gitignore 三子树规则 + desktop/build/ 两条白名单（打包脚本与三份配置永不误忽略）"
  - ".gitattributes 追加 *.sha256 / *.txt 的 eol=lf（hash 与基线跨平台字节不变）"
affects: [01-04, 01-05, phase-2-mobile-skeleton]

# Actuals (#2632) — 与计划的 estimate 同尺度（chars/4 over realized diff）
actuals:
  tokens: 1394
  tasks: 2
  commits: 2
  plan_head_before: 876d7cdcfb18f6422d6b2ca71edd17085f2176df
  plan_head_after: dc0e7746a2a0b007b08f737fbf3be863a221dfe8

tech-stack:
  added: []
  patterns:
    - "写入去向与读取路径分离：新增纯函数承载 --write-config 路由，default_config_path() 一字不动"
    - "路径纯函数可被 sys.frozen=True 在进程内断言，无需真的打包就能证明冻结态分支"
    - "忽略矩阵先写成 git check-ignore 断言再落地规则；不用 git add -f 掩盖白名单失效"

key-files:
  created: []
  modified:
    - desktop/padskills/config.py
    - desktop/main.py
    - .gitignore
    - .gitattributes

key-decisions:
  - "default_config_path() 函数体零改动：冻结态与开发态读取语义都是不可动的行为锚点，只新增写入侧函数"
  - "write_config_target() 独立成纯函数，三级路由可被单条 -c 断言覆盖，不需要真跑 --write-config 默认分支去污染真源"
  - "main.py 把显式路径收敛成一个 explicit_config 变量（plan 的验收要求「不再出现 Path(args.config)」与其 action 里给出的示例代码本身相冲突，按行为验收执行）"
  - ".gitignore 用 desktop/build/* 而非 desktop/build/：目录整体排除后 ! 白名单再也无法把打包脚本捞回来"
  - ".gitattributes 只加 *.sha256 与 *.txt，不加 *.yml/*.yaml：CI 只在 Linux 跑，给 YAML 加 eol 只会在 Windows 检出时增加 diff 噪音"
  - "开发态 --write-config 即使传了 -c 也打印 sync_config.py 提示：按 plan 字面「not is_frozen() 时打印」，不额外分支"

patterns-established:
  - "三级路由：显式 -c > 冻结态用户目录 > 开发态 shared/；读取路径独立于写入路径"
  - "忽略矩阵断言化：7 条 tracked + 6 条 ignored 全部用 git check-ignore -q 写成可执行检查"
  - "改完路径/CLI 立刻重跑 230 项闸门，避免「闸门假绿」与真实回归无法区分"

requirements-completed: [INFRA-01, INFRA-02]

coverage:
  - id: D1
    description: "开发态 --write-config（未传 -c）只写 shared/skills_config.json；显式 -c 原样使用；冻结态仍写用户配置目录；运行期读取仍是 desktop/skills_config.json"
    requirement: INFRA-02
    verification:
      - kind: unit
        ref: "uv --directory desktop run --no-sync python -c '...default_config_path/shared_config_path/write_config_target + sys.frozen=True...' → target-ok"
        status: pass
      - kind: integration
        ref: "uv --directory desktop run --no-sync python main.py --write-config -c /tmp/wc_probe.json（5 个动作，退出 0）"
        status: pass
    human_judgment: false
  - id: D2
    description: "三子树布局下 .gitignore 只忽略产物：两条打包脚本与三份 skills_config.json + 两份 .sha256 全部 tracked，六类产物路径 ignored"
    requirement: INFRA-01
    verification:
      - kind: other
        ref: "git check-ignore -q 矩阵：7 条应跟踪路径全部未命中；desktop/build/thing.txt、desktop/dist/x、desktop/.venv/py、mobile/.godot/y、mobile/build/z、mobile/export/a.apk 全部命中"
        status: pass
      - kind: other
        ref: "git ls-files | git check-ignore --stdin → 无输出（rc=1），66 个 tracked 文件无一被新规则命中"
        status: pass
    human_judgment: false
  - id: D3
    description: "改完 --write-config 路由与忽略规则后，230 项桌面检查仍全绿且名称与基线逐项一致"
    requirement: INFRA-01
    verification:
      - kind: integration
        ref: "bash tools/check_desktop.sh → rc=0，182 + 48 = 230 项，末行「✓ 230 项检查全部通过，名称与基线逐项一致」"
        status: pass
    human_judgment: false

# Metrics
duration: 2min
completed: 2026-11-04
status: complete
---

# Phase 01 Plan 03: --write-config 三级路由 + 三子树忽略/行尾规则 Summary

**开发态 `--write-config` 从「在桌面目录里再生成一份可写副本」改成「只写 `shared/skills_config.json` 真源并提示跑 `tools/sync_config.py`」，冻结态与运行期读取路径逐字节不变；`.gitignore` 跟着目录结构搬成三子树规则（`desktop/build/*` + 两条白名单，不碰三份配置与两份 `.sha256`），`.gitattributes` 补上 `*.sha256` / `*.txt` 的 `eol=lf`，230 项闸门仍全绿。**

## Performance

- **Duration:** ~2 min
- **Started:** 2026-11-03T20:30:26Z
- **Completed:** 2026-11-03T20:32:30Z
- **Tasks:** 2/2
- **Files modified:** 4（+49 / −11）

## Accomplishments

- **写入路径与读取路径彻底分离**：`padskills/config.py` 新增 `shared_config_path()` 与 `write_config_target(explicit)`（均加入 `__all__`），`default_config_path()` 函数体**一字未动**。开发态 `--write-config` 现在只落在唯一真源上，本阶段刚要消灭的「第二可写源」不会再从 CLI 长回来。
- **冻结态语义用 `sys.frozen=True` 在进程内证明**：无需真的打包，直接断言冻结态落点是 `~/Library/Application Support/FifaSkillTrainer/skills_config.json`，不含 `/shared/`。
- **运行期读取路径未变**：未传 `-c` 时 `config_path` 仍是 `desktop/skills_config.json`；`app.py` 未改动（仍传 `config=None`，GUI 内部本来回退 `default_config_path()`）。
- **忽略矩阵与搬迁前等价**：`desktop/build/*` + 两条 `!` 白名单让打包脚本保持 tracked；`mobile/.godot/`、`mobile/build/`、`mobile/export/`、`*.apk` 为 Phase 2 预留；没有任何规则命中三份 `skills_config.json` 或两份 `.sha256`。
- **闸门未被破坏**：改动后两次独立运行 `bash tools/check_desktop.sh` 均 rc=0，182 + 48 = 230 项，名称与基线逐项一致。

## 关键验证输出（plan 要求保留）

### 1. 三级路由行为断言（`target-ok`）

```text
$ uv --directory desktop run --no-sync python -c "..."
target-ok
  default_config_path() = /Users/stephen/Projects/202611/fifa-trainer/desktop/skills_config.json
  shared_config_path()  = /Users/stephen/Projects/202611/fifa-trainer/shared/skills_config.json
  frozen target         = /Users/stephen/Library/Application Support/FifaSkillTrainer/skills_config.json
```

- `write_config_target()` == `shared_config_path()`（开发态）
- `write_config_target(Path('/tmp/x.json'))` == `Path('/tmp/x.json')`（显式 `-c` 原样返回）
- `sys.frozen = True` 时不含 `/shared/`，落在用户配置目录
- `default_config_path()` 仍以 `/desktop/skills_config.json` 结尾（读取路径未漂移）

```text
$ uv --directory desktop run --no-sync python main.py --write-config -c /tmp/wc_probe.json
已生成默认配置: /private/tmp/wc_probe.json
提示：请运行 python3 tools/sync_config.py 把真源同步到桌面/移动端副本
write-config-ok: 5 skills
```

> 未传 `-c` 的分支没有真跑：它会覆盖 `shared/skills_config.json`，正是本计划要保护的真源。该分支由上面的纯函数断言覆盖，且 `shared/skills_config.json` 在执行全程 `git status` 无改动。

### 2. `git check-ignore` 矩阵（7 tracked / 6 ignored）

**应跟踪（不得被忽略）——全部通过：**

| 路径 | 结果 |
|------|------|
| `desktop/build/build_windows.ps1` | tracked |
| `desktop/build/build_macos.sh` | tracked |
| `shared/skills_config.json` | tracked |
| `desktop/skills_config.json` | tracked |
| `mobile/assets/config/skills_config.json` | tracked |
| `desktop/skills_config.json.sha256` | tracked |
| `mobile/assets/config/skills_config.json.sha256` | tracked |

**应忽略——全部命中：**

| 路径 | 命中的规则 |
|------|-----------|
| `desktop/build/thing.txt` | `.gitignore:12:desktop/build/*` |
| `desktop/dist/x` | `.gitignore:11:desktop/dist/` |
| `desktop/.venv/py` | `.gitignore:4:.venv/` |
| `mobile/.godot/y` | `.gitignore:17:mobile/.godot/` |
| `mobile/build/z` | `.gitignore:18:mobile/build/` |
| `mobile/export/a.apk` | `.gitignore:19:mobile/export/` |
| `.venv/py`（额外核对根目录旧 venv） | `.gitignore:4:.venv/` |

**附加防误伤检查**：`git ls-files | git check-ignore --stdin` 无输出（rc=1），即 66 个已跟踪文件没有一个被新规则命中。`.gitattributes` 含 `^*.sha256 text eol=lf` 与 `^*.txt text eol=lf` 两行。

### 3. 闸门最后一次运行（rc=0，230 行摘要）

```text
▸ 校验配置副本…
▸ 校验基线未被重新生成…
▸ 同步依赖（锁文件必须已是最新）…
  ...
  通过 182 项，失败 0 项
  ...
  通过 48 项，失败 0 项
══════════════════════════════════════════════════════════════
✓ 230 项检查全部通过，名称与基线逐项一致
```

`shared/expected_checks.txt` 未被重新生成（SHA-256 `724b40a3…596a`，闸门第二个 step 已就该常量校验通过）。

## Task Commits

Each task was committed atomically:

1. **Task 1: --write-config 三级路由（开发态写真源，冻结态不变）** - `8c71b48` (feat) — tracer
2. **Task 2: 重写 .gitignore / 追加 .gitattributes（三子树 + 白名单）** - `dc0e774` (chore)

**Plan metadata:** 见本次执行末尾的 `docs(01-03)` 提交

_注：Task 1 为 tracer 任务，提交后已按 tracer feedback gate 重跑完整 `<verify>` 链并通过（auto_advance=false + human_verify_mode=end-of-phase + 仅自动化 verify → 无 human checkpoint，直接进入扩展任务）。_

## Files Created/Modified

- `desktop/padskills/config.py` - 新增 `shared_config_path()` / `write_config_target(explicit)` 并加入 `__all__`；`default_config_path()` 与 `DEFAULT_CONFIG` 零改动
- `desktop/main.py` - `-c/--config` 默认值改 `None`、中文 help；新增 `explicit_config` / `config_path` 派生；`--write-config` 三级路由 + 开发态同步提示；GUI/冻结态/加载三处改用 `config_path`
- `.gitignore` - 三子树规则：Python 组沿用、`desktop/dist/` + `desktop/build/*` + 两条白名单、移动端四组预留、日志与编辑器组沿用
- `.gitattributes` - 末尾追加 `*.sha256 text eol=lf`、`*.txt text eol=lf`

## Decisions Made

- **`default_config_path()` 一字不动**：D-06 要求它的冻结态分支是用户配置目录，这是不可动的行为锚点；新增的函数只负责「写入去向」。
- **路由独立成纯函数**：三级判定在 `write_config_target()` 里一次写清，`main.py` 只调用一次，避免读取路径与写入路径各算一遍而悄悄分叉。
- **`explicit_config` 抽出为单变量**：plan 的 action 示例给的是 `Path(args.config) if args.config else None`，但同一条任务的 acceptance_criteria 又要求「`main.py` 中不再出现 `Path(args.config)`」。两者互斥，按**行为**验收：显式路径只做一次 `Path(...)` 转换，之后全部复用。
- **`desktop/build/*` 而非 `desktop/build/`**：目录整体排除后 `!` 无法再包含内部文件，这是 T-01-08 的核心落点。
- **不加 `*.yml` / `*.yaml` 的 eol 规则**：本阶段 CI 只在 Linux 跑，加了只会在未来 Windows 检出时制造 diff 噪音。
- **未传 `-c` 的写入分支不做真跑验证**：它会覆盖真源；改用纯函数断言覆盖同一判定，`shared/skills_config.json` 全程未被触碰。

## Deviations from Plan

### Auto-fixed Issues

None（无 bug、无缺失功能、无阻塞）。

### 计划文本内部不一致（按行为验收执行）

**1. `Path(args.config)` 的验收口径与示例代码冲突**
- **Found during:** Task 1（`desktop/main.py`）
- **情况：** action 明确要求写 `target = write_config_target(Path(args.config) if args.config else None)` 与 `config_path = Path(args.config) if args.config else default_config_path()`，而同一任务的 acceptance_criteria 写「`main.py` 中不再出现 `Path(args.config)`」。按字面两者不可能同时满足。
- **处理：** 以行为为准 —— 把显式路径收敛成 `explicit_config = Path(args.config) if args.config else None`（全文件仅此一处 `Path(args.config)`），`config_path` 与 `write_config_target(explicit_config)` 都复用它。
- **语义影响：** 无。显式 `-c` / 未传 `-c` / 冻结态三条分支的落点都由断言逐条验证。
- **Committed in:** `8c71b48`（Task 1 提交）

---

**Total deviations:** 0 auto-fixed（1 处计划文本内部不一致，按行为验收执行）
**Impact on plan:** 无行为偏差；三级路由、读取路径、冻结态语义、忽略矩阵与闸门全部按计划达成。

## Issues Encountered

- **只读验证的取舍**：plan 的 acceptance 要求「`--write-config` 在开发态打印同步提示」，但真跑该分支会覆盖真源。以 `-c` 显式路径跑通「打印提示 + 5 个动作」的链路，未传 `-c` 的三级判定由纯函数断言覆盖，`shared/skills_config.json` 在整个执行期间 `git status` 无改动。
- **执行环境**：按 `<sequential_execution>` 在主工作树 `main` 分支直接提交（`.planning/config.json` 的 `branching_strategy` 为 `none`，与 01-01 / 01-02 一致）；未使用 `--no-verify`。
- **未使用 `git add -f`**：白名单是通过改规则本身生效的，`desktop/build/` 下两条脚本由 `git ls-files` 确认仍在索引中。

## User Setup Required

None - 无外部服务、无密钥、无新增依赖（本计划未触碰 `uv.lock` 与 `pyproject.toml`）。

## Known Stubs

None.

## Threat Flags

None - 未引入 `<threat_model>` 之外的新信任边界。T-01-08（忽略规则白名单）与 T-01-09（`--write-config` 落点）的缓解措施已落地并逐条验证；T-01-10（行尾规则）按 accept 处置，`*.sha256` / `*.txt` 已显式 `eol=lf`。

## Next Phase Readiness

- **01-04**：`.gitignore` / `.gitattributes` 已就位，CI 可直接 `cd desktop && uv sync --locked` 后调用 `bash tools/check_desktop.sh`；若 CI 要提交 `.yml`，注意现有 `.gitattributes` 只覆盖 `sh/py/json/md/toml/lock/ps1/spec/sha256/txt`。
- **01-05**：干净 clone 校验现可断言「`git clone` 后 `desktop/build/` 两条脚本存在」与「三份 `skills_config.json` + 两份 `.sha256` 都在」，无需再用 `git add -f` 补文件。
- **Phase 2**：`mobile/assets/config/` 两份生成副本已被跟踪且不会被忽略；`mobile/.godot/`、`mobile/build/`、`mobile/export/`、`*.apk` 的忽略规则已预留，第一次 Godot 导出不会污染仓库。仍未创建 `mobile/project.godot`（D-10）。
- **留给后续阶段的既有事项**：`desktop/.venv/` 与根 `.venv/` 都命中 `.venv/` 规则（根 venv 是 Pitfall 10 的孤儿，属手工清理项，不在本计划 `files_modified` 内）。

---

## Self-Check: PASSED

- `desktop/padskills/config.py`、`desktop/main.py`、`.gitignore`、`.gitattributes` 四个文件均存在且已提交
- 提交 `8c71b48`（Task 1）与 `dc0e774`（Task 2）均为 HEAD 祖先，`git rev-list --count 876d7cd..HEAD` = 2
- 三次闸门运行（Task 1 验证、tracer gate 复跑、Task 2 提交前）均 rc=0 且输出含 `230`
- `desktop/tests/` 在 `876d7cd..HEAD` 区间零改动；`shared/expected_checks.txt` SHA-256 仍为 `724b40a3…596a`
- 无文件删除（两次提交的 `--diff-filter=D` 均为空）

---

*Phase: 01-repo-split-config-single-source*
*Completed: 2026-11-04*
