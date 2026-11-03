---
phase: 01-repo-split-config-single-source
plan: 02
subsystem: infra
tags: [repo-split, single-source-config, sha256, regression-gate, git-rename, uv-lockfile]

# Dependency graph
requires:
  - phase: 01-repo-split-config-single-source
    plan: 01
    provides: "shared/expected_checks.txt（230 行基线，SHA-256 724b40a3…596a）+ pyproject.toml 的 [[tool.uv.index]] 固定段"
provides:
  - "desktop/ 子树：19 条 100% rename（内容零改动），app.py / main.py / padskills/ / tests/ / build/ / pyproject.toml / uv.lock / FIFA-Skill-Trainer.spec / README.md"
  - "shared/skills_config.json：唯一可手写的动作配置真源（字节未改，bccf123a…eee9）"
  - "tools/sync_config.py：sync() / check() / find_stray_copies() / sha256() / sidecar() / repo_root()；CLI --check 与 --root"
  - "tools/test_sync_config.py：23 条断言，覆盖手改副本、缺 .sha256、多余副本、缺真源、一次报全部问题"
  - "desktop/skills_config.json(+.sha256)、mobile/assets/config/skills_config.json(+.sha256)：生成副本，已被 git 跟踪"
  - "tools/check_desktop.sh：230 项检查的唯一定义，含 BASELINE_SHA256 常量与 uv sync --locked"
affects: [01-03, 01-04, 01-05]

# Actuals (#2632) — 与计划的 estimate 同尺度（chars/4 over realized diff）
actuals:
  tokens: 10581
  tasks: 3
  commits: 3
  plan_head_before: 9d6a2b862939232125664d0ddde28c59783f7d8c
  plan_head_after: 3f834755e3dba0693784ea1e7ff14eb5aaf7525a

tech-stack:
  added: []
  patterns:
    - "纯 git mv 单独提交：rename 100%、--numstat 全 0，git log --follow 仍能追到 Initial commit"
    - "生成式配置副本 + sha256sum 兼容 .sha256 旁文件，内容相同则不落盘（幂等）"
    - "闸门顺序即安全属性：先配置副本 → 再基线摘要 → 最后才装依赖跑测试"
    - "基线用常量钉死（BASELINE_SHA256 分行 + readonly），改基线不改常量必红"

key-files:
  created:
    - tools/sync_config.py
    - tools/test_sync_config.py
    - tools/check_desktop.sh
    - desktop/skills_config.json
    - desktop/skills_config.json.sha256
    - mobile/assets/config/skills_config.json
    - mobile/assets/config/skills_config.json.sha256
    - .planning/phases/01-repo-split-config-single-source/deferred-items.md
  modified:
    - "19 条路径的纯重命名（app.py → desktop/app.py 等）"

key-decisions:
  - "搬迁提交 02b03db 只含 git mv：19 条 --diff-filter=R，--numstat 全 0，0 删除，--follow 保留 Initial commit"
  - "闸门第一步就是 sync_config.py --check：副本缺失时 load_config() 会静默回退 DEFAULT_CONFIG，先跑测试就是假绿"
  - "BASELINE_SHA256 拆成「赋值行 + readonly 行」：校验按 ^BASELINE_SHA256= 行首锚定，合并写法会匹配不到"
  - "sync() 只在字节不同时落盘：重复运行不产生 diff，也不白改 mtime"
  - "check() 先收集全部问题再一次性报告，不在第一个错误处中断"
  - "find_stray_copies() 返回相对路径（不是绝对路径），报错信息才能与仓库布局对齐"
  - "mobile/ 本阶段只有 assets/config/ 两个生成副本，不创建 project.godot（D-10）"

patterns-established:
  - "配置唯一真源：shared/ 手写 → tools/sync_config.py 分发 → 两份只读副本 + .sha256 → 闸门首步校验"
  - "回归闸门只有一条命令、一个定义：bash tools/check_desktop.sh，无 --quick 之类的部分模式"
  - "uv 调用一律 cd desktop 后执行，uv sync 只带 --locked（裸 sync 会被本机镜像改写 uv.lock）"

requirements-completed: [INFRA-01, INFRA-02]

coverage:
  - id: D1
    description: "仓库变成 desktop/ + mobile/ + shared/ + tools/ 四棵子树，桌面代码搬迁是 100% rename 且历史可追溯"
    requirement: INFRA-01
    verification:
      - kind: other
        ref: "git show --numstat -M100% 02b03db（19 文件 / +0 / -0）；--diff-filter=R 19 条；--diff-filter=D 0 条；git log --follow -- desktop/padskills/config.py 2 条"
        status: pass
    human_judgment: false
  - id: D2
    description: "tools/sync_config.py 能生成/校验两份只读副本，四种破坏（手改副本、缺 .sha256、多余副本、缺真源）都能被抓到并指名道姓"
    requirement: INFRA-02
    verification:
      - kind: unit
        ref: "python3 tools/test_sync_config.py（通过 23 项，失败 0 项，rc=0）"
        status: pass
    human_judgment: false
  - id: D3
    description: "四份生成文件被 git 跟踪且不被 .gitignore 命中，哈希与真源一致"
    requirement: INFRA-02
    verification:
      - kind: other
        ref: "git ls-files --error-unmatch 四个路径通过；shasum -a 256 -c 在两份副本目录各报 skills_config.json: OK；python3 tools/sync_config.py --check rc=0"
        status: pass
    human_judgment: false
  - id: D4
    description: "一条命令证明 230 项检查全绿且名称与搬迁前基线逐项一致"
    requirement: INFRA-01
    verification:
      - kind: integration
        ref: "bash tools/check_desktop.sh（rc=0，182 + 48 = 230，diff 无差异；从 /tmp 调用同样 rc=0）"
        status: pass
    human_judgment: false

# Metrics
duration: 4min
completed: 2026-11-04
status: complete
---

# Phase 01 Plan 02: 仓库三子树拆分 + 配置单一真源 + 230 项回归闸门 Summary

**19 条 `git mv` 把桌面代码整体搬进 `desktop/`（`--numstat` 全 0、`--follow` 保留 Initial commit），`shared/skills_config.json` 成为唯一手写真源并由 `tools/sync_config.py` 生成两份带 `.sha256` 的只读副本，`bash tools/check_desktop.sh` 一条命令跑出 182 + 48 = 230 项全绿且名称与搬迁前基线逐项一致。**

## Performance

- **Duration:** ~4 min
- **Started:** 2026-11-03T20:23:59Z
- **Completed:** 2026-11-03T20:27:51Z
- **Tasks:** 3/3
- **Files modified:** 26（19 条 rename + 7 个新建/生成）

## Accomplishments

- **纯重命名搬迁（零内容改动）**：`git show --numstat -M100% 02b03db` 19 个文件全部 `+0 -0`，`--diff-filter=R` 恰好 19 条、`--diff-filter=D` 0 条；`git log --follow -- desktop/padskills/config.py` 仍能追到 `5e489a1 Initial commit`。仓库根现在只剩 `desktop/`、`mobile/`、`shared/`、`tools/` 与 `.planning/`、`.gitattributes`、`.gitignore`、`AGENTS.md`。
- **配置单一真源落成**：`tools/sync_config.py` 把 `shared/skills_config.json` 逐字节写到 `desktop/skills_config.json` 与 `mobile/assets/config/skills_config.json`，并在旁边写 `sha256sum` 兼容的 `.sha256`（`<hex>  <basename>`）；内容相同就不落盘。`--check` 逐项校验存在性、逐字节相等、`.sha256` 摘要，并扫描第四份 `skills_config*.json`。
- **自测 23 条断言全绿**：`python3 tools/test_sync_config.py` → `通过 23 项，失败 0 项`（rc=0），四个反例（手改副本 / 删 `.sha256` / 多塞副本 / 删真源）都能让 `--check` 返回 1 并指出具体文件。
- **回归闸门可用**：`bash tools/check_desktop.sh` → rc=0，输出 `✓ 230 项检查全部通过，名称与基线逐项一致`；从 `/tmp` 调用同样 rc=0（仓库根以 `BASH_SOURCE` 为锚）。
- **防作弊落点生效**：篡改 `desktop/skills_config.json` 一个字节后闸门 rc=1，并打印 `✗ desktop/skills_config.json 与真源不一致（副本只能由脚本生成，不能手改）`；恢复后 `--check` 立即回到 0。

## Task Commits

Each task was committed atomically:

1. **Task 1: 纯 git mv —— 三子树布局一次成型（零内容改动）** - `02b03db` (refactor)
2. **Task 2: 同步脚本 + 自测 + 生成两份配置副本与 .sha256** - `e187f3d` (feat)
3. **Task 3: 回归闸门 —— 230 项检查的唯一定义** - `3f83475` (feat)

**Plan metadata:** 见本次执行末尾的 `docs(01-02)` 提交

_注：三个任务各自单一提交，没有 TDD 拆分。_

## 关键事实（供后续计划引用）

| 项目 | 值 |
|------|-----|
| 搬迁提交 | `02b03db` — 19 条 rename、`+0 / -0`、0 删除 |
| `git log --follow` 条数 | 2（`02b03db` + `5e489a1 Initial commit`） |
| `desktop/tests/` 是否被改过 | 否（`git log 02b03db..HEAD -- desktop/tests` 为空） |
| 真源 SHA-256 | `bccf123a06efc61c7f05bc430e488a0f596bdc1e5c7eade4c18a3660f9d0eee9`（与搬迁前 `skills_config.json` 逐字节一致） |
| `python3 tools/sync_config.py --check` | 退出 **0** |
| `python3 tools/test_sync_config.py` | 通过 **23** 项，失败 **0** 项，退出 0 |
| `bash tools/check_desktop.sh` | 退出 **0**：`test_detectors.py` 182 项、`test_gui_smoke.py` 48 项、`LC_ALL=C sort` 后与基线 `diff -u` 空输出、末行 `✓ 230 项检查全部通过，名称与基线逐项一致` |
| `shasum -a 256 -c` | `desktop/`：`skills_config.json: OK`；`mobile/assets/config/`：`skills_config.json: OK` |
| 基线未被重新生成 | `shared/expected_checks.txt` 仍 230 行，SHA-256 `724b40a3…596a` 未变 |
| 本计划提交数 | 3（`git rev-list --count 9d6a2b8..3f83475`） |

## Files Created/Modified

- `desktop/**`（19 条 rename）- 桌面版整棵子树，内容零改动
- `shared/skills_config.json` - 唯一可手写真源（由根 `skills_config.json` 重命名而来）
- `tools/sync_config.py` - 同步/校验 CLI：`sync()` `check()` `find_stray_copies()` `sha256()` `sidecar()` `repo_root()`，参数 `--check` `--root`
- `tools/test_sync_config.py` - 自测，`tempfile.mkdtemp()` + `io.StringIO()` 构造八个场景
- `tools/check_desktop.sh` - 230 项闸门：`BASELINE_SHA256` 常量、`run_suite()`、四个 SDL/编码环境变量
- `desktop/skills_config.json` / `.sha256` - 桌面开发态运行时读取的生成副本
- `mobile/assets/config/skills_config.json` / `.sha256` - 未来 Godot `res://` 读取的生成副本
- `.planning/phases/01-repo-split-config-single-source/deferred-items.md` - 记录本次发现的时序敏感用例

## Decisions Made

- **搬迁提交只允许 `git mv`**：把内容适配（`.gitignore`、README、`--write-config` 路由）全部留给 01-03/01-04，保证 `--numstat` 全 0 与 `--follow` 不断链。
- **闸门顺序固定为「配置 → 基线 → 依赖 → 测试」**：顺序本身是安全属性。若先跑测试，副本缺失时 `load_config()` 静默回退 `DEFAULT_CONFIG`，182 项照样绿——那是假绿。
- **`BASELINE_SHA256` 分行写**：第一行 `BASELINE_SHA256=<64 hex>`，第二行 `readonly BASELINE_SHA256`。校验按 `^BASELINE_SHA256=` 行首锚定，合并成一行就会匹配不到。
- **`sync()` 幂等**：只在字节不同时写盘，重复运行 `git status --porcelain` 为空。
- **`check()` 一次报全部问题**：出问题时开发者想看"一共错了几处"，不是"第一处是什么"。
- **`find_stray_copies()` 返回相对路径**：报错行直接是 `mobile/skills_config.json`，与仓库布局对齐，也避免泄漏本机绝对路径。

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] 自测脚本导入名与 harness 函数重名**
- **Found during:** Task 2（`tools/test_sync_config.py`）
- **Issue:** 计划的契约要求 `from sync_config import SOURCE, TARGETS, check, find_stray_copies, sidecar, sync`，同时又要求 harness 逐字照抄 `desktop/tests/test_detectors.py` 的 `def check(label, ok, extra="")`。两者同名，后者会覆盖前者，`--check` 就再也调不到。
- **Fix:** 改为 `from sync_config import (SOURCE, TARGETS, check as check_config, find_stray_copies, sidecar, sync)`；harness `check()` 保持逐字不变，所有被测调用走 `check_config()`。
- **Files modified:** `tools/test_sync_config.py`
- **Verification:** `python3 tools/test_sync_config.py` → 通过 23 项，失败 0 项（rc=0）
- **Committed in:** `e187f3d`（Task 2 提交）

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** 纯命名冲突，语义与断言集合完全按计划；没有放宽任何检查。

## Issues Encountered

- **一次性时序抖动**：Task 3 首次连续验证时，`desktop/tests/test_detectors.py` 的 `[8] 引擎端到端` 偶发 3 项失败（`真实时间轴下画弧` / `旋转摘要` / `震动后端 1 次`），同一轮 `采样频率接近 250Hz` 仍为 250Hz。单独连跑 5 次与闸门连跑 5 次均全绿，仅在本机同时创建 `desktop/.venv` 的两轮出现。判定为既有的真实时间轴用例对 OS 调度停顿敏感，**与搬迁无关**；按 SCOPE BOUNDARY 不改 `desktop/tests/`，已记入 `deferred-items.md` 交 01-04 接 CI 时处理。
- **执行环境**：按 `<sequential_execution>` 在主工作树 `main` 分支直接提交；`.planning/config.json` 的 `branching_strategy` 为 `none`，项目本身不使用阶段分支（与 01-01 一致）。

## User Setup Required

None - 无外部服务、无密钥、无新增依赖。

## Known Stubs

None.

## Threat Flags

None - 未引入 `<threat_model>` 之外的新信任边界。T-01-03 / T-01-04 / T-01-05 / T-01-06 的缓解措施均已落地并被上面的命令逐一验证。

## Next Phase Readiness

- 01-03 可以直接改写 `.gitignore`（三子树规则 + 两条 `desktop/build/` 白名单）与 `.gitattributes`（`*.sha256` / `*.txt`）：`desktop/skills_config.json` 及其 `.sha256` 现已受 git 跟踪，写新规则时务必 `git check-ignore -v` 复验它们仍未被忽略。
- `desktop/padskills/config.py` 的 `default_config_path()` 保持原样（开发态 → `desktop/skills_config.json`）；`--write-config` 的三级路由（显式 `-c` > 冻结态用户目录 > 开发态 `shared/`）尚未实现，属 01-03。
- 01-04 接 CI 时：`bash tools/check_desktop.sh` 已是唯一定义，workflow 只需 `cd desktop && uv sync --locked` 后调用它；另请处理 `deferred-items.md` 里的时序敏感用例。
- 01-05 的干净 clone 校验可复用 `python3 tools/sync_config.py --check` 与 `bash tools/check_desktop.sh`，无需第二套实现。

---

## Self-Check: PASSED

- `desktop/app.py`、`desktop/main.py`、`desktop/padskills/config.py`、`desktop/tests/test_detectors.py`、`desktop/FIFA-Skill-Trainer.spec`、`desktop/README.md`、`shared/skills_config.json` 均存在
- `tools/sync_config.py`、`tools/test_sync_config.py`、`tools/check_desktop.sh` 存在且已提交
- 四份生成文件被 `git ls-files --error-unmatch` 确认已跟踪
- 提交 `02b03db` / `e187f3d` / `3f83475` 均为 HEAD 祖先

---

*Phase: 01-repo-split-config-single-source*
*Completed: 2026-11-04*
