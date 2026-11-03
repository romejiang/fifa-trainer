# Phase 1: 仓库拆分 + 配置单一真源 + 桌面回归闸门 - Research

**Researched:** 2026-11-04
**Domain:** Python/uv 仓库重构 · 配置单一真源 · CI 回归闸门
**Confidence:** HIGH（关键结论均在本机实测：uv 项目根语义、lockfile 镜像污染、PyInstaller SPECPATH、git mv 历史、230 项检查名提取）

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** 只做**最小平移** —— 把 `app.py`、`main.py`、`padskills/`、`tests/`、`build/`、`pyproject.toml`、`uv.lock`、`FIFA-Skill-Trainer.spec` 整体移入 `desktop/`，`padskills/` 内部模块结构一字不动。**Reversibility:** reversible — 纯路径移动，回滚只需 `git revert`。
  - 理由：本阶段的验收是「行为零变化」，每多一层结构改动就多一倍需要证明的东西。`CONCERNS.md` 里记录的上帝模块（`gui.py` 1308 行等）属于独立的技术债，不能在搬迁阶段顺带处理，否则一旦回归失败将无法区分是路径问题还是重构问题。

- **D-02:** `pyproject.toml` 与 `uv.lock` 跟随代码进入 `desktop/`，仓库根**不再**保留 Python 项目元数据。所有桌面命令在 `desktop/` 目录内执行（`cd desktop && uv sync && uv run app.py`）。**Reversibility:** costly — 根目录若残留 `pyproject.toml` 会让 uv 产生两套环境与第二个锁文件。
  - 理由：uv 以 `pyproject.toml` 所在目录为项目根。保留一份根级副本会直接制造「两个 Python 项目」，与本阶段目标相反。

- **D-03:** 根 `README.md` 改写为**仓库地图**（三棵子树 + 常用命令入口 + 指向子目录文档），原 776 行桌面手册整体移入 `desktop/README.md`，内容不改。**Reversibility:** reversible。
  - 理由：现有 README 全部是桌面版使用说明，放在根目录会让 `mobile/` 的读者误以为那是全仓文档。拆分文档而不改写内容，既是结构清晰又零信息损失。

- **D-04:** `shared/skills_config.json` 是**唯一可手写**的动作配置。`tools/sync_config.py` 是它唯一的消费者与分发者，生成两份**只读副本**：
  - `desktop/skills_config.json`（开发态运行时读取路径不变）
  - `mobile/assets/config/skills_config.json`（未来 Godot `res://` 读取路径）
  
  每份副本旁生成 `.sha256`。`--check` 比对内容并按差异逐条报告，不一致即非零退出。**Reversibility:** one-way — 一旦桌面运行时改为直接读 `../shared/`，冻结打包后的路径语义会改变。
  - 理由：桌面版冻结后是单目录分发（PyInstaller），运行时不能依赖仓库相对路径。生成副本可以保持 `default_config_path()` 的运行时语义不变，从而保护行为闸门。两份副本都不是手写源，且都被 hash 钉住，不构成第二真源。

- **D-05:** `main.py --write-config` 在**开发态**改为写入 `shared/skills_config.json`，随后要求运行 `tools/sync_config.py`；**冻结态**行为不变（写入用户配置目录）。**Reversibility:** costly — 改变了一个开发期 CLI 的写入目标。
  - 理由：否则 `DEFAULT_CONFIG`（`padskills/config.py:250`）与 `shared/skills_config.json` 会同时成为可写入的源，本阶段刚要消灭的多真源问题会立刻复活。冻结态用户没有仓库，必须保持原行为。

- **D-06:** `padskills/config.py` 的 `DEFAULT_CONFIG` **保留**，角色降级为「内置默认值 + `--write-config` 的模板」，不再是运行时读取的配置。运行时可读配置只有一份：同步出来的副本。**Reversibility:** reversible。
  - 理由：`DEFAULT_CONFIG` 还承担 `_readme` 文档与配置生成职责，删除它会大幅扩大改动面；把它降级为模板即可，不必动。

- **D-07:** 建立单一入口脚本 `tools/check_desktop.sh`，它是「230 项检查」的**唯一定义**。脚本职责：
  1. 以 `SDL_VIDEODRIVER=dummy`、`SDL_AUDIODRIVER=dummy` 运行 `desktop/tests/test_detectors.py` 与 `desktop/tests/test_gui_smoke.py`
  2. 断言输出中的检查项**名称集合**与 `shared/expected_checks.txt` 逐项相等，且数量为 182 + 48
  3. 任一不符即非零退出并打印缺失/新增项
  
  **Reversibility:** reversible。

- **D-08:** `shared/expected_checks.txt` 必须在**搬迁之前**从当前代码生成一次并提交，作为基线；本阶段任何任务都不得重新生成它来「对齐」结果。**Reversibility:** one-way — 基线一旦被覆盖，就再也无法证明搬迁没有弱化断言。
  - 理由：这是整个阶段唯一的防作弊机制。允许重新生成基线，等于允许把「删掉一个失败断言」洗成「基线更新」。

- **D-09:** 新增 `.github/workflows/desktop-checks.yml`，在 push 与 PR 时调用同一个 `tools/check_desktop.sh`（`uv sync` 后执行）。**不**安装 pre-commit hook。**Reversibility:** reversible。
  - 理由：远程仓库已存在（`origin git@github.com:romejiang/fifa-trainer.git`），CI 是唯一无法用 `--no-verify` 绕过的闸门；同时它复用同一脚本，不会产生第二套检查定义。hook 会被下意识绕过，且会给日常提交增加摩擦，收益低于 CI。

- **D-10:** 本阶段 `mobile/` 只创建 `mobile/README.md` 与 `mobile/assets/config/`（同步目标），**不**创建 `project.godot`。Godot 项目初始化归 Phase 2。**Reversibility:** reversible。
  - 理由：Phase 1 不应依赖本机装好 Godot 4.7.2。由一个未知版本生成 `project.godot` 后，Phase 2 用正确版本打开时会被静默重写；把项目文件的创建权交给「锁定工具链」的那一阶段更干净。

- **D-11:** 根 `.gitignore` 重写为覆盖三棵子树的规则，至少包含：`desktop/build/*`（保留两条脚本白名单）、`desktop/dist/`、`mobile/.godot/`、`mobile/build/`、`mobile/export/`、`*.apk`。**Reversibility:** reversible。
  - 理由：现有 `build/*` 与 `!build/*` 白名单在搬迁后会指向不存在的路径，必须同步移动；顺带为 Phase 2 预留移动端产物忽略规则，避免第一次导出就把缓存提交进来。

### the agent's Discretion

以下区域用户明确表示「你来决定」（原话：*这些细节你来决定我也看不懂，你来决定*），规划与执行阶段可按实际发现调整实现手段，但不得改变上述决定的目标：

- 同步脚本的具体参数形态（除 `--check` 必须存在外）
- `.sha256` 文件的格式与存放位置
- `expected_checks.txt` 的具体文本格式（只要满足「名称集合逐项相等」）
- CI 的 Python 版本矩阵（单版本即可，建议与本地一致的 3.11+）
- 迁移过程中临时提交的拆分粒度

### Deferred Ideas (OUT OF SCOPE)

- **桌面版上帝模块拆分**（`gui.py` 1308 行、`detectors.py` 1046 行、`config.py` 790 行）—— 已在 `CONCERNS.md` 记录，属于独立重构，不在搬迁阶段混入。
- **pre-commit hook 形式的本地闸门** —— 本次不采用；CI + 脚本已覆盖同一需求，且 hook 易被 `--no-verify` 绕过。
- **移动端 GDScript 测试的 CI** —— 依赖 Godot headless，归 Phase 2 之后。
- **`shared/golden_vectors.json`** —— Phase 4/5 的对等性基线，本阶段只在 `shared/` 留出位置，不生成内容。
- **iOS 相关目录与构建配置** —— 明确延期，Phase 1 不为它预留空壳。
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| INFRA-01 | 仓库拆分为 `desktop/` + `mobile/` + `shared/`，桌面版 230 项检查全部通过 | §Pattern 1（基线先行搬迁）、§Pattern 2（检查名收集器）、§uv 调用矩阵、§git 历史保留；实测搬迁后 182 + 48 全绿、名称逐字节一致 |
| INFRA-02 | `shared/skills_config.json` 为唯一真源；同步脚本 + hash 校验；应用启动时校验 | §Pattern 3（同步 + hash + 反例检测）；"应用启动时校验"在本阶段只覆盖到 CLI/CI 的 `--check`，移动端启动校验见 Open Question 1 |
</phase_requirements>

## Summary

本阶段是纯基础设施搬迁，技术风险不在"写代码"，而在**四个会静默出错的边界**：

1. **uv 的项目根**。`pyproject.toml` + `uv.lock` 必须同层进 `desktop/`；根目录不保留 Python 元数据（D-02）。实测确认：仓库根没有 `pyproject.toml` 时 `uv run --project desktop ...` 仍然可用，但**子进程 cwd 仍是仓库根**，且 `desktop/` 不会被放进 `sys.path`（项目没有 build backend，不会被安装）。因此"从根目录跑测试"的正确写法是 `uv --directory desktop run tests/test_detectors.py`（子进程 cwd=desktop），而不是 `uv run --project desktop tests/...`（会 `No such file or directory`）。
2. **本机镜像会改写 `uv.lock`**。`~/.config/uv/uv.toml` 里 `index-url = "https://mirrors.aliyun.com/pypi/simple"` 会让 `uv lock --check` 退出 1、让裸 `uv sync` 把 lockfile 里 10 处 `pypi.org` 改写成 aliyun。实测解法：在 `desktop/pyproject.toml` 加 `[[tool.uv.index]] url = "https://pypi.org/simple" default = true`，之后 `uv lock --check` / `uv sync` / `uv sync --locked` 全部退出 0，lockfile 保持 pypi.org。这是保证 CI 不被本机环境破坏的最小改动。
3. **基线必须从 pre-move 代码生成**（D-08），并且提取手段不能依赖 stdout 文本。实测：给测试模块的 `check()` 套一层记录器，可以在不改测试文件的前提下拿到全部 230 个名称（182 + 48，全部唯一），搬迁后逐字节一致。
4. **`git mv` 必须在纯重命名提交里完成**。实测：`git mv a.py desktop/a.py` 单提交，rename 100%，`git log --follow` 能看到搬迁历史；**同一提交里既移动又改内容会让 `--follow` 直接丢失历史**（小文件加 40 行后相似度跌破阈值）。

**Primary recommendation:** 按"基线先行 → 纯 `git mv` 提交 → 内容适配提交 → 同步脚本与 CI"四段推进；检查项名称用 `tools/collect_checks.py` 注入记录器提取，禁止解析带 ANSI 颜色的 stdout；`desktop/pyproject.toml` 固定 PyPI 索引，闸门脚本一律 `uv sync --locked`。

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| 仓库目录布局（`desktop/` / `mobile/` / `shared/`） | Repo tooling（git + 文件系统） | — | 纯路径事实，不涉及任何运行时 |
| 桌面行为保持（230 项检查） | Desktop runtime（Python 测试脚本） | Repo tooling（`tools/check_desktop.sh`） | 断言由测试文件持有，闸门只负责运行与比对名称 |
| 动作配置唯一真源 | Shared data（`shared/skills_config.json`） | Repo tooling（`tools/sync_config.py`） | 真源是数据文件；分发与校验是工具职责 |
| 开发态配置读取 | Desktop runtime（`padskills/config.py:default_config_path`） | — | 运行时只读生成副本，不读 `shared/`（保护冻结语义） |
| 配置副本完整性 | Repo tooling（`.sha256` + `--check`） | CI | 运行时不做 hash 校验，避免改变桌面行为 |
| 回归闸门执行 | CI（GitHub Actions） | Local shell | 同一脚本两处调用，避免第二套定义 |
| PyInstaller 打包 | Desktop build（`desktop/build/*`） | — | 构建脚本已自带"以脚本所在目录为根"的解析，无需改内容 |

## Standard Stack

### Core

| Library / Tool | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| uv | 本机 0.9.5；CI 需显式钉版本 | 项目根发现、锁文件、虚拟环境 | 仓库唯一依赖管理方式（`uv.lock` 已存在，`revision = 3`）[VERIFIED: `uv --version` → `uv 0.9.5 (d5f39331a 2025-10-21)`] |
| Python | 3.12.12（本机 venv）；`requires-python = ">=3.11"` | 运行测试与工具 | 本机 venv 实测 3.12.12；锁文件含 cp311–cp315 wheel |
| pygame-ce | 2.5.8（锁文件） | 唯一运行时依赖 | 测试导入 `pygame`（dummy driver） |
| PyInstaller | 6.22.3 | 打包（可选 extra `build`） | 本阶段只验证 spec 解析语义，不实际打包 |
| `hashlib.sha256` | 标准库 | 配置副本 hash | 禁止手写摘要算法 |
| `git mv` | 系统 git | 保留历史的重命名 | rename detection 基于内容，纯移动可达 100% |

### Supporting

| Tool | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `astral-sh/setup-uv` | **v10.3.3**（SHA `68559e99cc807c1eb7e9238fd43a15bba460eec2`） | CI 安装 uv | 官方 README 当前版本；`docs.astral.sh` 示例页仍写 v9.0.0（滞后）[CITED: github.com/astral-sh/setup-uv README] |
| `actions/checkout` | v7.0.1（docs 示例 SHA `3d3c42e5...`） | CI 检出 | 必须在 `setup-uv` 之前 [CITED: docs.astral.sh/uv/guides/integration/github/] |
| `LC_ALL=C` / Python `sorted()` | — | 中文字符串排序稳定性 | 基线比对必须与平台 locale 无关 |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| 根目录无 `pyproject.toml`（D-02） | 根 `pyproject.toml` + `[tool.uv.workspace] members = ["desktop"]` | 能保留根级命令，但直接违反 D-02，且产生 workspace 语义（`uv sync` 行为、锁文件位置都会变）。**不采用** |
| `[[tool.uv.index]]` 固定 PyPI | 闸门脚本里 `UV_NO_CONFIG=1` | 实测两者都能让 `uv lock --check` 退出 0；`UV_NO_CONFIG` 不保护开发者手敲的 `uv sync`（仍会改写 lockfile），只保护脚本。建议固定索引为主，`UV_NO_CONFIG=1` 可作为脚本内的双保险 |
| 解析 stdout 提取检查名 | 注入 `check()` 记录器 | stdout 带 ANSI 颜色码，且 `extra` 后缀与标签之间只用两个空格分隔，存在歧义；记录器无解析、无编码问题（实测 230 项全唯一） |
| 符号链接到 `shared/` | 生成副本 | Godot `res://` 以 `project.godot` 所在目录为根，非资源文件默认不进 PCK；指向项目外的链接在 Android 导出与 Windows 检出（`core.symlinks=false`）都不可靠。D-04 已锁定副本 |

**Installation:**

```bash
# 本阶段不安装任何新依赖。桌面依赖维持 uv.lock 现状。
cd desktop && uv sync --locked
```

**Version verification:**

```bash
uv --version                     # uv 0.9.5 (d5f39331a 2025-10-21)
uvx pyinstaller --version        # 6.22.3  （实测，走本机镜像安装）
grep -n 'name = "pygame-ce"' -A1 uv.lock   # version = "2.5.8"
head -3 uv.lock                  # version = 1 / revision = 3 / requires-python = ">=3.11"
```

## Package Legitimacy Audit

**本阶段不新增任何外部包。** `pygame-ce`、`XInput-Python`、`pyinstaller` 均已在 `uv.lock` 中锁定，本阶段不改依赖声明（只增加 `[[tool.uv.index]]` 索引固定，不改变解析结果——实测 `uv lock --check` 在有/无该条目时对同一 lockfile 的包集合与版本完全一致）。

| Package | Registry | Age | Downloads | Source Repo | Verdict | Disposition |
|---------|----------|-----|-----------|-------------|---------|-------------|
| pygame-ce | PyPI | 既有依赖，已在锁文件 | — | github.com/pygame-community/pygame-ce | OK（未变更） | 维持 |
| pyinstaller | PyPI | 既有可选依赖，已在锁文件 | — | github.com/pyinstaller/pyinstaller | OK（未变更） | 维持 |
| XInput-Python | PyPI | 既有可选依赖（win32 only） | — | — | OK（未变更） | 维持 |

**新增的第三方执行面是 GitHub Actions，不是 Python 包。** 供应链要求：
- `astral-sh/setup-uv` 与 `actions/checkout` 必须按 **commit SHA** 固定，并附 `# vX.Y.Z` 注释（官方文档即如此示例）[CITED: docs.astral.sh/uv/guides/integration/github/]。
- CI 中 `uv sync --locked`，锁文件自带每个 wheel 的 `sha256`，不得使用 `--no-verify-hashes` 之类的开关。

**Packages removed due to [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

## Architecture Patterns

### System Architecture Diagram

```text
                      ┌──────────────────────────────────────────┐
                      │ shared/skills_config.json                │
                      │ 唯一可手写真源（人工编辑只发生在这里）      │
                      └───────────────┬──────────────────────────┘
                                      │
                    tools/sync_config.py（唯一分发者）
                      │                               │
        ┌─────────────┴───────────┐       ┌───────────┴─────────────────┐
        ▼                         ▼       ▼                             ▼
desktop/skills_config.json   .sha256   mobile/assets/config/       .sha256
（开发态运行时读取）          （校验）    skills_config.json           （校验）
        │                                   │
        │ 默认路径推导                        │ Phase 2+ Godot res://
        ▼                                   ▼
padskills/config.py::default_config_path()   （本阶段不读，只落盘）

        ┌──────────────── 回归闸门 ────────────────┐
        │                                          │
desktop/tests/test_detectors.py ─┐        shared/expected_checks.txt
desktop/tests/test_gui_smoke.py ─┤        （搬迁前生成，永不重生成）
        │                        │                 │
        └─ tools/collect_checks.py ─► 名称集合 ──► diff ──► 非零退出
                                                          │
                                              tools/check_desktop.sh
                                                   ▲              ▲
                                             本地手动          GitHub Actions
```

### Target Repository Structure

```text
.
├── README.md                     # 仓库地图（新写）
├── .gitignore                    # 覆盖三棵子树（D-11）
├── .gitattributes                # 追加 *.sha256 / *.txt 规则
├── .github/workflows/
│   └── desktop-checks.yml        # 复用 tools/check_desktop.sh（D-09）
├── shared/
│   ├── skills_config.json        # 唯一真源
│   └── expected_checks.txt       # 230 项基线（搬迁前生成）
├── tools/
│   ├── sync_config.py            # 同步 + --check
│   ├── collect_checks.py         # 检查名提取（不解析 stdout）
│   ├── check_desktop.sh          # 230 项闸门
│   └── test_sync_config.py       # 同步脚本自测（自建 check()）
├── desktop/
│   ├── README.md                 # 原 776 行手册，内容不改
│   ├── app.py  main.py  padskills/  tests/  build/
│   ├── pyproject.toml  uv.lock  FIFA-Skill-Trainer.spec
│   └── skills_config.json        # 生成副本（提交）
└── mobile/
    ├── README.md
    └── assets/config/
        ├── skills_config.json    # 生成副本（提交）
        └── skills_config.json.sha256
```

### Pattern 1: 基线先行搬迁（Baseline-first move）

**What:** 把"生成基线"和"移动文件"拆成两个不可混淆的步骤，基线在移动前生成并单独提交。
**When to use:** 所有"行为必须零变化"的搬迁。

**提交序列（推荐）：**

1. `chore: 增加检查项基线` —— 新增 `tools/collect_checks.py`，用它从**当前位置**的 `tests/` 生成 `shared/expected_checks.txt`（230 行）。此提交不含任何移动。
2. `refactor: 桌面代码整体移入 desktop/` —— 纯 `git mv`，**零内容改动**（包括暂不改 `.gitignore`）。
3. `chore: 适配 desktop/ 布局` —— `.gitignore`、根 README、`desktop/README.md` 落位、`pyproject.toml` 索引固定、`--write-config` 目标、路径断言。
4. `feat: 配置单一真源 + 同步脚本` —— `tools/sync_config.py`、两份副本与 `.sha256`、自测。
5. `ci: 桌面回归闸门` —— `tools/check_desktop.sh` + workflow。

**为什么第 2 步必须纯移动（实测）：**

```text
# 纯 git mv 提交
$ git show --stat -M HEAD
 a.py => desktop/a.py | 0
 b.py => desktop/b.py | 0
$ git log --follow --oneline -- desktop/a.py
53552ef move into desktop
1ce5e56 initial

# 移动 + 同提交内改内容（小文件追加 40 行）
$ git log --follow --oneline -- desktop/b2.py
f0b0db0 move+edit b          ← 只剩这一个提交，历史丢失
```

**约束：** 第 2 步之后仓库短暂不可运行（根目录已无 `pyproject.toml`）。这是可接受的，因为 CI 在第 5 步才出现；但如果审阅者要求"每个提交都可运行"，则把 2–3 合并成一个提交（粒度属 Discretion）。

### Pattern 2: 检查名收集器（不解析 stdout）

**What:** 用一个独立进程导入测试模块，在调用 `main()` 前替换模块级 `check()`，把每次调用的 `label` 原样记录下来。
**When to use:** D-07/D-08 的"名称集合逐项相等"。

**为什么不能解析 stdout（实测）：**

- `check()` 无条件输出 ANSI 颜色码，即使 stdout 被重定向：
  `print(f"  \033[32m✓\033[0m {label}" + ...)`（`tests/test_detectors.py:32-39`，逐字）
- 标签与 `extra` 之间只有两个空格 + `(`；`extra` 可能包含运行时测量值，**不具确定性**（例如 `f"实际 {engine.frames / 0.9:.0f}Hz"`，`tests/test_detectors.py:1022-1023`）。用 `rsplit("  (", 1)` 目前可行（AST 检查：148 + 53 个 `check()` 调用点中，标签本身含 `  (` 的有 0 个），但这依赖"未来标签永不包含两个连续空格"，是隐性契约。
- 输出编码取决于 locale；重定向时测试文件本身**没有** `sys.stdout.reconfigure`（只有 `main.py` 有）。

**实测结果（本机）：**

```text
test_detectors.py: rc=0 checks=182 unique=182
test_gui_smoke.py: rc=0 checks=48  unique=48
total 230 unique 230
```

**实现要点：**

- `importlib.util.spec_from_file_location` 加载测试文件（`tests/` 不是包，不能 `import tests.xxx`）。
- 必须先 `exec_module` 再替换 `mod.check`，因为测试在模块级定义 `check`。
- 包装器签名为 `(label, ok, extra="", *args, **kwargs)`，并调用原函数以保留 `PASS`/`FAIL` 计数与彩色输出。
- 名称写入 `--out` 文件（`<测试文件名>\t<label>`），测试自身输出仍走 stdout 供人阅读。
- 各套件**分进程**运行（避免 `test_gui_smoke` 的 pygame 全局状态污染 `test_detectors`）。

**已知失败模式（规划时必须接受或处理）：**

| 模式 | 现状 | 处理方式 |
|------|------|----------|
| 顺序 | 测试是显式调用序列，顺序稳定 | 基线排序后比对，**顺序不参与判定**（符合 D-07"名称集合"） |
| 同名标签 | 当前 230 个全部唯一（实测） | 用排序后的多重集比对，重复次数也参与判定 |
| 标签内嵌数字 | 93 个标签含数字，但全部来自表驱动常量（如 `保持到 400ms 门槛整`） | 改动阈值会改标签 → 闸门失败。这是**期望行为**（阈值变更必须显式改基线，而本阶段禁止改基线） |
| 标签内嵌运行时值 | 无（动态部分都在 `extra`） | 若未来出现，记录器仍能拿到求值后的字符串，但基线会随运行变化——禁止这样写标签 |
| 输出编码 / ANSI | 记录器不读 stdout | 天然免疫 |
- 名称排序用 Python `sorted()`（UTF-8 下码点序 == 字节序），避免 `sort` 的 locale 差异。

### Pattern 3: 配置同步与 hash（单源 + 生成副本）

**What:** 一个只依赖标准库的 Python 脚本，把 `shared/skills_config.json` 逐字节复制到两处，并在旁边写 `sha256sum` 兼容的 `.sha256`。

**行为契约：**

| 命令 | 行为 | 退出码 |
|------|------|--------|
| `python tools/sync_config.py` | 写两份副本 + 两份 `.sha256`；内容相同则跳过写入（保持 mtime 不变） | 0 |
| `python tools/sync_config.py --check` | 逐份比对：存在性、与源逐字节相等、`.sha256` 与副本相符 | 0 / 1 |
| `python tools/sync_config.py --check`（发现多余副本） | 扫描仓库内 `skills_config*.json`，不在白名单即报错 | 1 |

**`.sha256` 格式（推荐，属 Discretion）：**

```text
bccf123a06efc61c7f05bc430e488a0f596bdc1e5c7eade4c18a3660f9d0eee9  skills_config.json
```

- 相对文件名（不是绝对路径、不含目录），可 `cd` 到该目录后直接 `shasum -a 256 -c skills_config.json.sha256` 验证（macOS 实测 `skills_config.json: OK`）。
- 脚本内部用 `hashlib.sha256`，不依赖 `shasum`（Windows 没有）。

**"唯一真源"的机械定义（建议在 `--check` 中实现）：**

允许出现的 `skills_config*.json` 恰好三个：`shared/skills_config.json`（源）、`desktop/skills_config.json`、`mobile/assets/config/skills_config.json`。任何第四份（例如某人新建 `mobile/skills_config.json`）都让 `--check` 失败。

**sparse-checkout 提示：** `shared/` 必须与两个子项目同时检出。若有人用 `git sparse-checkout` 只取 `desktop/`，`--check` 会报"缺少真源"——这是期望行为，不要为了让 sparse 工作而放宽检查。

**关于"提交副本"（重要推论，需规划确认）：** 如果没有提交副本，`load_config()` 在文件缺失时会**静默回退到 `DEFAULT_CONFIG`**：

```python
if not path.exists():
    return parse_config(json.loads(json.dumps(DEFAULT_CONFIG)), None)
```
（`padskills/config.py:762-763`，逐字）

这会让 `test_detectors` 在"配置副本不存在"时依然全绿，却测的是内置默认值——干净 clone 上的假绿。因此**两份副本 + `.sha256` 必须提交**，这也是成功标准 4（干净 clone 可复现）的前提。

### Pattern 4: uv 调用矩阵（实测）

| 场景 | 命令 | 子进程 cwd | 结果 |
|------|------|-----------|------|
| 文档标准形态 | `cd desktop && uv run app.py` | `desktop/` | ✅ |
| 从根目录跑测试（推荐） | `uv --directory desktop run tests/test_detectors.py` | `desktop/` | ✅ 182 项通过 |
| 从根目录跑测试（可行但绕） | `uv run --project desktop desktop/tests/test_detectors.py` | 仓库根 | ✅（测试自己 `sys.path.insert` 了父目录） |
| 从根目录给工具用项目环境 | `uv run --project desktop python tools/sync_config.py` | 仓库根 | ✅ |
| **陷阱** | `uv run --project desktop python -c "import padskills"` | 仓库根 | ❌ `ModuleNotFoundError`（项目无 build backend，不会被安装） |
| **陷阱** | `uv run --project desktop tests/test_detectors.py` | 仓库根 | ❌ `Failed to spawn: No such file or directory` |

官方语义（`--project` 的 rustdoc，逐字）：

> Discover a project in the given directory. … **Other command-line arguments (such as relative paths) will be resolved relative to the current working directory.**
> See `--directory` to change the working directory entirely.
> [CITED: github.com/astral-sh/uv crates/uv-cli/src/lib.rs]

**结论：** 闸门脚本与 README 一律用 `cd desktop`（或 `uv --directory desktop`），不要依赖 `--project` 的相对路径行为。

### Anti-Patterns to Avoid

- **用 `uv run --project desktop python -c "import padskills"` 验证搬迁** —— 必然失败，会误导为"搬迁坏了"。
- **在同一个提交里移动并修改文件** —— 断送 `git log --follow`（已实测）。
- **解析带 ANSI 的 stdout 生成基线** —— 编码/locale/`extra` 三重不确定性。
- **让闸门 `uv sync`（不带 `--locked`）** —— 在带镜像的机器上会静默改写 lockfile，并让"lockfile 漂移"永远不被发现。
- **把 `desktop/skills_config.json` 加进 `.gitignore`** —— `load_config` 会静默回退到 `DEFAULT_CONFIG`，回归闸门变成假绿。
- **用符号链接替代副本** —— Godot 导出只打包项目树内文件，Android 导出与 Windows 检出均不可靠。

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| 文件内容摘要 | 自己拼字符串/简单累加 | `hashlib.sha256` + `sha256sum` 兼容格式 | 可被系统工具独立验证；避免编码陷阱 |
| 重命名并保留历史 | 文件系统 `mv` + `git add -A` | `git mv`（仍是内容级 rename detection，但纯移动相似度 100%） | 历史可追溯；`--follow` 可用 |
| 锁文件一致性 | 自己比较 `pyproject` 与 `uv.lock` | `uv lock --check` / `uv sync --locked` / `--frozen` | 官方语义已覆盖三种严格度，见下表 |
| 中文文本排序 | `sort` 默认 locale | Python `sorted()` 或 `LC_ALL=C sort` | BSD sort 与 GNU sort 的中文排序规则不同，会导致 CI 与本地误报 |
| YAML/JSON 解析 | shell 正则 | Python `json` / PyYAML（CI 文件不需要程序解析） | 可读性与正确性 |
| 临时目录 | 手拼 `/tmp/xxx` | `mktemp -d` + `trap` 清理 | 并发与清理 |

**uv 锁文件严格度（官方文档，逐字要点）：**

| 选项 | 语义 | 何时用 |
|------|------|--------|
| （无） | 锁文件过期则**自动重新锁定** | 日常开发（但会被镜像污染） |
| `--locked` | 锁文件过期则**报错**，不写 | **CI 与闸门脚本**，用来抓漂移 |
| `--frozen` | 直接使用过期锁文件，不检查 | 离线/需要原样安装时 |

> "To disable automatic locking, use the `--locked` option: If the lockfile is not up-to-date, uv will raise an error instead of updating the lockfile."
> "To use the lockfile without checking if it is up-to-date, use the `--frozen` option."
> [CITED: docs.astral.sh/uv/concepts/projects/sync.md]

## Runtime State Inventory

> 本阶段是 rename/migration 类阶段，逐类回答。

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| **Stored data** | 无数据库、无缓存服务。唯一的"数据"是配置文件与 `trainer.log`；日志在 `user_config_dir()`，与仓库布局无关。 | 无迁移；只需保证 `desktop/skills_config.json` 生成副本存在 |
| **Live service config** | GitHub 仓库设置（Actions 是否启用、默认分支 `main`、远端 `origin git@github.com:romejiang/fifa-trainer.git`）不在 git 内。新增 workflow 后需确认 Actions 已启用；无 secrets 需要配置。 | 首次 push 后到 Actions 页面确认 workflow 被发现并运行 |
| **OS-registered state** | 无 launchd / systemd / 计划任务 / 注册表项。历史构建出的 `.app` / `.exe` 以自身路径推导 `app_dir()`（`sys.frozen` 分支），不受仓库搬迁影响。 | 无 |
| **Secrets / env vars** | 仓库内无 `.env`、无密钥、无 token。测试用 `SDL_VIDEODRIVER` / `SDL_AUDIODRIVER` 是进程级开关。CI 只用 `GITHUB_TOKEN`（actions 默认）。 | 无 |
| **Build artifacts / installed packages** | ① 仓库根现有 `.venv/`（本机，搬迁后成为孤儿）；② 各目录 `__pycache__/`（git 已忽略，会自动重建）；③ 未来产物在 `desktop/dist/`、`desktop/build/`；④ 若根目录存在历史 `dist/` 则被 `dist/` 规则忽略。 | 手动删除根 `.venv` 后重建（不产生仓库改动）；`.gitignore` 增加 `desktop/build/*` 白名单与 `mobile/*` 产物规则 |

**搬迁后仍然"记着旧路径"的东西（逐项核对）：** 无 —— 没有数据库、没有服务注册、没有外部系统引用仓库内路径；唯一会残留的是本机 `.venv` 与编辑器索引。

## Common Pitfalls

### Pitfall 1: 本机镜像把 `uv.lock` 改写成 aliyun

**What goes wrong:** 提交的 lockfile 指向 `pypi.org`，本机一跑 `uv sync` / `uv lock` 就被改写成镜像地址；提上去 CI 解析不到（或反之）。
**Why it happens:** `~/.config/uv/uv.toml` 里有 `index-url = "https://mirrors.aliyun.com/pypi/simple"`。uv 会拿"当前配置的索引"去校验 lockfile 里的 `source = { registry = ... }`，不匹配就判定锁文件过期并重新锁定。
**实测证据：**

```text
$ grep -c 'pypi.org' uv.lock                 # 10
$ uv lock --check --project desktop
The lockfile at `uv.lock` needs to be updated, but `--locked` was provided.   (exit 1)

$ uv sync --project desktop                  # 不带 --locked
$ grep -c 'aliyun' desktop/uv.lock           # 10  ← 全被改写
```

**How to avoid:** 在 `desktop/pyproject.toml` 末尾固定索引：

```toml
[[tool.uv.index]]
url = "https://pypi.org/simple"
default = true
```

实测加完后：`uv lock --check` exit 0、裸 `uv sync` exit 0 且 lockfile 仍是 `pypi.org`、`uv sync --locked` exit 0。
（备选：闸门脚本里 `export UV_NO_CONFIG=1`，实测同样有效；但它只保护脚本，不保护手敲的 `uv sync`。）

**Warning signs:** `git status` 显示 `uv.lock` 被修改；`grep aliyun uv.lock` 有输出。

### Pitfall 2: 移动 + 改内容同提交 → `git log --follow` 断链

**What goes wrong:** 搬迁后想追溯某文件历史，只剩"移动"那一个提交。
**Why it happens:** rename detection 基于相似度；小文件在移动同时改动较大时跌破阈值，git 视为"删除 + 新增"。
**How to avoid:** 纯 `git mv` 单独提交（第 2 步），所有内容改动放到后续提交。
**Warning signs:** `git log --follow --oneline -- desktop/padskills/config.py` 只有一条记录。

### Pitfall 3: `uv run --project` 的 cwd 不是项目目录

**What goes wrong:** 从根目录执行 `uv run --project desktop tests/test_detectors.py` 报 `Failed to spawn`；`python -c "import padskills"` 报 `ModuleNotFoundError`。
**Why it happens:** `--project` 只改变"项目发现"，不改变 cwd，也不把项目目录加入 `sys.path`；本项目没有 build backend，不会被安装成包。测试能跑通只是因为它们自己 `sys.path.insert(0, Path(__file__).parent.parent)`（`tests/test_detectors.py:16`、`tests/test_gui_smoke.py:23`）。
**How to avoid:** 统一用 `cd desktop` 或 `uv --directory desktop run ...`。
**Warning signs:** 从根目录跑测试出现 `No such file or directory` / `ModuleNotFoundError`。

### Pitfall 4: 副本缺失时 `load_config` 静默回退，闸门假绿

**What goes wrong:** 干净 clone 上 `desktop/skills_config.json` 不存在，`test_detectors` 仍然 182 项全绿——但测的是 `DEFAULT_CONFIG`，不是真源。
**Why it happens:**

```python
if not path.exists():
    return parse_config(json.loads(json.dumps(DEFAULT_CONFIG)), None)
```
（`padskills/config.py:762-763`，逐字）

**How to avoid:** 两份副本与 `.sha256` 一并提交；闸门跑之前先 `tools/sync_config.py --check`（或让闸门包含它）。
**Warning signs:** `git ls-files desktop/skills_config.json` 为空；`--check` 在干净 clone 上报"副本不存在"。

### Pitfall 5: 基线提取被 stdout 格式污染

**What goes wrong:** 用 `grep '✓'` 之类提取，迁移到 CI 后名称对不上、编码乱码、`extra` 把标签截断。
**Why it happens:** `check()` 无条件打印 ANSI 颜色码；`extra` 用两个空格 + `(` 附加；输出编码取决于 locale。
**How to avoid:** 用 `tools/collect_checks.py` 注入记录器（见 Pattern 2 / Code Examples）。
**Warning signs:** 本地 230 行、CI 少几行；名称里混入 `\x1b[32m`；出现 `(实际 ...)` 片段。

### Pitfall 6: 中文字符串排序受 locale 影响

**What goes wrong:** 本地（macOS/BSD sort）与 CI（GNU sort）对中文名称的排序不同，`diff` 满屏红。
**Why it happens:** `sort` 默认按 locale 的 collation，而不是字节序。
**How to avoid:** 基线用 Python `sorted()` 生成（UTF-8 字节序 == 码点序），闸门里用 `LC_ALL=C sort`。
**Warning signs:** 同一份基线在本地通过、CI 失败，且差异只是顺序。

### Pitfall 7: `.gitignore` 白名单随目录移动失效

**What goes wrong:** 搬迁后 `build/*` 规则匹配不到 `desktop/build/*`，打包脚本被忽略或产物被提交。
**实测（D-11 草案规则，`git check-ignore` 逐项验证）：**

```text
desktop/build/build_windows.ps1          tracked   ← 白名单生效
desktop/build/build_macos.sh             tracked
desktop/build/thing.txt                  IGNORED
desktop/dist/x                           IGNORED   ← dist/ 规则匹配任意层级
desktop/.venv/py                         IGNORED   ← .venv/ 规则匹配任意层级
mobile/.godot/y                          IGNORED
mobile/export/a.apk                      IGNORED
shared/skills_config.json                tracked
```
**How to avoid:** `desktop/build/*` + 两条 `!desktop/build/...`；不要写成 `desktop/build/`（目录整体排除后 `!` 无法再包含内部文件）。
**Warning signs:** `git status` 里出现 `desktop/build/*.txt`，或打包脚本从 `git ls-files` 消失。

### Pitfall 8: 误以为打包走的是 `FIFA-Skill-Trainer.spec`

**What goes wrong:** 花时间"修正 spec 里的相对路径"，而实际打包脚本根本没用它。
**Why it happens:** `build/build_macos.sh` / `build_windows.ps1` 直接给 `pyinstaller` 传 CLI 参数并以 `app.py` 结尾，**没有引用 spec**（全文已读，grep 无 `spec` 命中）。
**实测（PyInstaller 6.22.3）：** 位于 `sub/probe.spec` 的 `Analysis(['probe_entry.py'])`，从父目录执行 `pyinstaller sub/probe.spec` 时：

```text
PROBE cwd= .../specprobe
PROBE SPEC= .../specprobe/sub/probe.spec
PROBE SPECPATH= .../specprobe/sub
PROBE entry in cwd: False
PROBE entry in SPECPATH: True
→ 构建成功，产物运行输出 hello-from-sub
```

即：spec 内的相对脚本路径**按 SPECPATH（spec 所在目录）解析**，与 cwd 无关。
**How to avoid:** 只把 spec 随 `desktop/` 移动，内容不动；如需从根目录打包，`pyinstaller desktop/FIFA-Skill-Trainer.spec` 也能工作。
**Warning signs:** 有人"为了修路径"把 `Analysis(['app.py'])` 改成 `Analysis(['desktop/app.py'])`——那会在 `cd desktop` 时反而失败。

### Pitfall 9: `--write-config` 改动顺带改掉了运行时读取路径

**What goes wrong:** 为了满足 D-05 把 `default_config_path()` 改成指向 `shared/`，结果 GUI/CLI 开发态也直接读 `shared/`，破坏 D-04/D-06。
**Why it happens:** `-c/--config` 的默认值就是 `str(default_config_path())`（`main.py:212-213`，逐字），`--write-config` 复用它（`main.py:236-239`）。
**How to avoid:** 保持 `default_config_path()` 不变；新增 `shared_config_path()`，只在 `--write-config` 且"未显式传 `-c`"且"非冻结"时使用（见 Code Examples）。
**Warning signs:** 冻结态行为变化；GUI 日志里的配置路径变成 `shared/...`。

### Pitfall 10: 根目录 `.venv` 成为孤儿

**What goes wrong:** 搬迁后根 `.venv` 仍在，编辑器/IDE 仍指向它；`uv run` 在根目录不报错（实测只打印 `warning: --no-sync has no effect when used outside of a project`），可能用错解释器。
**How to avoid:** 手动删除根 `.venv`，`cd desktop && uv sync` 重建；README 写明"所有桌面命令在 `desktop/` 内"。
**Warning signs:** `which python` 指向根 `.venv`；import 到旧路径的 `padskills`。

### Pitfall 11: 检查输出编码不确定

**What goes wrong:** CI 上中文标签变 `?`，基线对不上。
**Why it happens:** 测试脚本没有 `sys.stdout.reconfigure`（只有 `main.py:31-36` 有）。
**How to avoid:** 闸门里 `export PYTHONIOENCODING=utf-8`；记录器本身写文件时显式 `encoding="utf-8"`。
**Warning signs:** 输出里出现 `\ufffd` 或 `?`。

## Code Examples

### 检查名收集器 `tools/collect_checks.py`（本机实测可用）

```python
#!/usr/bin/env python3
"""从自建 check() 测试脚本里收集检查项名称，不解析 stdout 文本。"""
from __future__ import annotations

import argparse
import importlib.util
import sys
from pathlib import Path


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("test_script")
    parser.add_argument("--out", required=True)
    args = parser.parse_args(argv[1:])

    path = Path(args.test_script).resolve()
    spec = importlib.util.spec_from_file_location(f"_collect_{path.stem}", path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = mod
    spec.loader.exec_module(mod)

    names: list[str] = []
    original = mod.check

    def recording_check(label, ok, extra="", *rest, **kwargs):
        names.append(label)
        return original(label, ok, extra, *rest, **kwargs)

    mod.check = recording_check
    try:
        rc = mod.main()
    finally:
        Path(args.out).write_text(
            "".join(f"{path.name}\t{n}\n" for n in names), encoding="utf-8"
        )
    return rc


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
```

用法（搬迁前生成基线）：

```bash
uv run --no-sync python tools/collect_checks.py tests/test_detectors.py --out /tmp/det.tsv
uv run --no-sync python tools/collect_checks.py tests/test_gui_smoke.py --out /tmp/gui.tsv
cat /tmp/det.tsv /tmp/gui.tsv | LC_ALL=C sort > shared/expected_checks.txt
wc -l shared/expected_checks.txt     # 230
```

### 闸门脚本 `tools/check_desktop.sh`

```bash
#!/usr/bin/env bash
# 桌面版回归闸门：230 项检查必须全绿，且检查项名称与基线逐项一致。
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
desktop="$repo_root/desktop"
baseline="$repo_root/shared/expected_checks.txt"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

export SDL_VIDEODRIVER=dummy
export SDL_AUDIODRIVER=dummy
export PYGAME_HIDE_SUPPORT_PROMPT=1
export PYTHONIOENCODING=utf-8

cd "$desktop"
uv sync --locked

run_suite() {  # $1=测试脚本（相对 desktop） $2=期望检查项数量
    local test_file="$1" expected="$2" out="$tmp/$(basename "$1").tsv" actual
    # 测试自身输出走 stderr，stdout 只留给名称文件
    uv run --no-sync python "$repo_root/tools/collect_checks.py" "$test_file" --out "$out" >&2
    actual="$(wc -l < "$out" | tr -d ' ')"
    if [ "$actual" -ne "$expected" ]; then
        echo "✗ $test_file：检查项 $actual 项，期望 $expected 项" >&2
        exit 1
    fi
    cat "$out"
}

{ run_suite tests/test_detectors.py 182
  run_suite tests/test_gui_smoke.py 48; } | LC_ALL=C sort > "$tmp/actual.txt"

if ! diff -u "$baseline" "$tmp/actual.txt"; then
    echo "✗ 检查项名称与 shared/expected_checks.txt 不一致" >&2
    exit 1
fi

echo "✓ 230 项检查全部通过，名称与基线逐项一致"
```

### 同步脚本 `tools/sync_config.py`（骨架）

```python
#!/usr/bin/env python3
"""把 shared/skills_config.json 同步到两份只读副本，并校验一致性。"""
from __future__ import annotations

import argparse
import hashlib
import sys
from pathlib import Path

SOURCE = Path("shared/skills_config.json")
TARGETS = (
    Path("desktop/skills_config.json"),
    Path("mobile/assets/config/skills_config.json"),
)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sidecar(path: Path) -> Path:
    return path.with_name(path.name + ".sha256")


def check(root: Path) -> int:
    src = root / SOURCE
    if not src.is_file():
        print(f"✗ 缺少真源 {SOURCE}", file=sys.stderr)
        return 1
    data = src.read_bytes()
    failed = False
    for rel in TARGETS:
        target = root / rel
        if not target.is_file():
            print(f"✗ {rel} 不存在（运行 tools/sync_config.py）", file=sys.stderr)
            failed = True
            continue
        if target.read_bytes() != data:
            print(f"✗ {rel} 与真源不一致", file=sys.stderr)
            failed = True
        digest = sha256(data)
        side = sidecar(target)
        if not side.is_file() or side.read_text(encoding="utf-8").split()[0] != digest:
            print(f"✗ {rel}.sha256 缺失或过期", file=sys.stderr)
            failed = True
    return 1 if failed else 0


def sync(root: Path) -> int:
    data = (root / SOURCE).read_bytes()
    digest = sha256(data)
    for rel in TARGETS:
        target = root / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        if not target.is_file() or target.read_bytes() != data:
            target.write_bytes(data)          # 逐字节复制，保证 hash 稳定
        line = f"{digest}  {target.name}\n"
        side = sidecar(target)
        if not side.is_file() or side.read_text(encoding="utf-8") != line:
            side.write_text(line, encoding="utf-8")
        print(f"✓ {rel}")
    return 0
```

> 骨架省略了 `--root`（供自测指向临时目录）与"多余副本扫描"，这两项建议在实现时补上；`--root` 让 `tools/test_sync_config.py` 可以在 `tempfile.mkdtemp()` 里构造完整场景而不污染仓库。

### `--write-config` 的路由（D-05）

```python
# padskills/config.py（新增，不动 default_config_path）
def shared_config_path() -> Path:
    """开发态唯一手写配置：<repo>/shared/skills_config.json。"""
    return app_dir().parent / "shared" / DEFAULT_CONFIG_FILENAME
```

```python
# main.py
parser.add_argument("-c", "--config", default=None,
                    help="配置文件路径（默认在项目根目录 / 用户配置目录）")
...
config_path = Path(args.config) if args.config else default_config_path()

if args.write_config:
    target = Path(args.config) if args.config else (
        default_config_path() if is_frozen() else shared_config_path()
    )
    path = dump_default_config(target)
    print(f"已生成默认配置: {path.resolve()}")
    if not is_frozen():
        print("提示：请运行 tools/sync_config.py 把配置同步到桌面/移动端副本")
    return 0
```

其余分支把 `Path(args.config)` 换成 `config_path`，`main_gui(config_path=str(config_path), ...)`，确保**未传 `-c` 时的读取路径仍是 `desktop/skills_config.json`**。

### `.github/workflows/desktop-checks.yml`

```yaml
name: desktop-checks

on:
  push:
    branches: [main]
  pull_request:

jobs:
  desktop:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1  # v7.0.1
      - name: 安装 uv
        uses: astral-sh/setup-uv@68559e99cc807c1eb7e9238fd43a15bba460eec2  # v10.3.3
        with:
          version: "0.9.5"        # 与本机生成 lockfile 的版本一致
          python-version: "3.12"
          enable-cache: true
      - name: 锁文件必须与 pyproject 一致
        run: cd desktop && uv sync --locked
      - name: 配置单一真源校验
        run: uv run --project desktop --frozen python tools/sync_config.py --check
      - name: 桌面回归闸门
        run: bash tools/check_desktop.sh
```

> `uv sync --locked` 在锁文件过期时**退出 1**（实测），因此这一步就是"锁文件漂移"的闸门；后面用 `--frozen` 避免再次解析。`enable-cache` 的默认缓存键已包含 `**/uv.lock`，嵌套目录无需额外配置 [CITED: github.com/astral-sh/setup-uv README]。

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `--index-url` / `--extra-index-url` | `--default-index` / `--index` / `[[tool.uv.index]]` | uv 0.4.23（2024-10） | 旧选项仍兼容但已弃用；项目内固定索引用 `[[tool.uv.index]]` + `default = true` |
| 手动管理 venv + pip | `uv sync` / `uv run` + `uv.lock` | — | `--locked`（CI）与 `--frozen`（离线）语义分离 |
| `setup-uv@v1`…`v9` | `setup-uv@v10.3.3` | 当前（2026-11） | 官方 README 为 v10.3.3；`docs.astral.sh` 示例页仍写 v9.0.0 |
| 解析测试输出统计通过数 | 注入 `check()` 记录器 / 机器可读输出 | — | 本项目无 pytest，记录器是零改测试文件的最小方案 |

**Deprecated/outdated:**
- `uv pip install` 工作流：本仓库不使用，别为 CI 引入。
- `FIFA-Skill-Trainer.spec`：**未被任何构建脚本引用**（已 grep 确认），属于历史遗留；本阶段只移动不删除，也不要在它上面做"路径修正"。

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `desktop/skills_config.json` 与 `mobile/assets/config/skills_config.json` 连同 `.sha256` 应提交进 git（而非 gitignore） | Pattern 3 / Pitfall 4 | 若不提交，干净 clone 上 `test_detectors` 会静默测 `DEFAULT_CONFIG`，成功标准 4 无法自证 |
| A2 | INFRA-02 的"应用启动时校验"本阶段只覆盖到 CLI/CI 的 `--check`；移动端启动校验归 Phase 3（RESIL-02） | Phase Requirements | 若必须在 Phase 1 给桌面加启动校验，会改变开发态行为，与 D-01"行为零变化"冲突 |
| A3 | `shared/expected_checks.txt` 采用 `<测试文件名>\t<label>`、按 `LC_ALL=C` 排序的纯文本 | Pattern 2 | 格式属 Discretion，改格式不影响目标；但必须保证排序稳定 |
| A4 | `.sha256` 采用 `sha256sum` 兼容格式（`<hex>  <basename>`） | Pattern 3 | 若改成只存 hex，会失去"系统工具可独立验证"的好处 |
| A5 | CI 单 runner（ubuntu-latest）+ 单 Python（3.12） | Validation Architecture | Windows 路径差异（反斜杠、CRLF）不会被 CI 捕获；可后续加 windows job |
| A6 | CI 的 uv 版本钉在 0.9.5（与本机一致） | Code Examples | 若用最新 uv（0.13.x），可能因锁文件格式升级导致 `--locked` 失败；升级需单独提交并重生 lockfile |
| A7 | 符号链接不适合作为 `shared/` 的消费方式 | Alternatives / Pattern 3 | Godot 导出只打包项目树内文件（官方文档已说明非资源文件默认不导出），链接到项目外不可靠；D-04 已锁定副本，风险低 |

## Open Questions

1. **INFRA-02 的"应用启动时校验"到底指谁？**
   - What we know: Phase 1 没有移动端应用；桌面版开发态读生成副本，加启动 hash 校验会改变行为（D-01 禁止）。
   - What's unclear: 需求文字是否要求桌面在 Phase 1 就校验副本 hash。
   - Recommendation: Phase 1 用 `tools/sync_config.py --check` + CI 作为机械校验；桌面运行时**不**加校验；移动端启动校验放到 Phase 3（RESIL-02 配置错误屏）一并实现。规划时在 PLAN 的 scope 里显式写明。

2. **要不要用 `--write-config` 刷新一次 `shared/skills_config.json`？**
   - What we know: 现有 `skills_config.json` 与 `DEFAULT_CONFIG` **不完全相同**：`input.invert` 缺失、`_readme` 少 4 行；5 个动作的规则字段完全一致（已逐字段比对）。
   - What's unclear: 是否要在搬迁期间顺手"对齐"。
   - Recommendation: **不要**。以现有文件原样作为 `shared/` 的种子，保持搬迁 diff 纯净；`--write-config` 的正确性由 Phase 3+ 的配置测试覆盖。（若对齐，会让基线/配置的 diff 混在一起，违反最小平移。）

3. **CI 要不要加 Windows job？**
   - What we know: `tools/sync_config.py` 用 `pathlib`，理论上跨平台；`.gitattributes` 已强制 `.json`/`.ps1` 行尾。
   - Recommendation: 先 ubuntu 单 job；Phase 2 引入 Godot 导出时再评估 Windows。

4. **`AGENTS.md` 里的路径引用会失效**（如 `padskills/config.py:60`），但它是由 `.planning/codebase/` 生成的快照。
   - Recommendation: 本阶段不改；在 Phase 1 的 README 任务里留一句"代码地图见 `.planning/codebase/`"，避免顺手重写 AGENTS.md 扩大 diff。

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| uv | 项目/锁文件/CI 本地复现 | ✓ | 0.9.5 | — |
| Python | 测试与工具 | ✓ | 3.12.12（desktop venv） | `uv python install 3.12` |
| git | 搬迁与历史 | ✓ | 系统 git（`git mv` / `--follow` 实测可用） | — |
| PyInstaller | 仅验证 spec 语义 | ✓（按需下载） | 6.22.3（`uvx pyinstaller --version`） | 不装也能完成本阶段（构建脚本未用 spec） |
| `shasum` | 人工验证 `.sha256` | ✓ | macOS 自带 | 脚本内部用 `hashlib`，不依赖 |
| Godot | — | ✗ | — | **本阶段不需要**（D-10） |
| GitHub Actions | CI 闸门 | ✓（远端存在） | — | 本地 `tools/check_desktop.sh` 可完全替代 |

**Missing dependencies with no fallback:** 无
**Missing dependencies with fallback:** Godot（本阶段不需要）；PyInstaller（可选）

## Validation Architecture

> `workflow.nyquist_validation = true`（`.planning/config.json`），本节必填。结论先说：**本阶段能产出真实、可自动化的验证层，但只有两层——闸门脚本本身，以及同步脚本的自测。** 不要为了"看起来完整"虚构 UI/E2E 层；本阶段没有任何用户可见界面。

### Test Framework

| Property | Value |
|----------|-------|
| Framework | **无** —— 自建 `check()` harness（`tests/test_detectors.py:32-39`、`tests/test_gui_smoke.py:38-45`），直接 `uv run` |
| Config file | 无（没有 pytest.ini / conftest.py；不要为本阶段引入 pytest） |
| Quick run command | `uv run --project desktop python tools/test_sync_config.py`（< 1 s） |
| Full suite command | `bash tools/check_desktop.sh`（约 2–4 s：182 项 ~1.1 s + 48 项 ~0.3 s + uv 解析） |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| INFRA-01 | 搬迁后桌面检查全绿 | integration（脚本） | `bash tools/check_desktop.sh` | ❌ Wave 0（脚本 + 基线） |
| INFRA-01 | 检查项名称与数量逐项一致（182 + 48） | 结构断言（名称集合 diff） | `bash tools/check_desktop.sh`（内部 `diff -u`） | ❌ Wave 0 |
| INFRA-01 | 搬迁不改写/弱化断言 | 基线不可重生成（流程约束）+ 名称 diff | 同上；基线提交早于移动提交 | ❌ Wave 0（基线） |
| INFRA-02 | 同步一次生成两份副本 + `.sha256` | unit | `uv run --project desktop python tools/test_sync_config.py` | ❌ Wave 0 |
| INFRA-02 | 重复运行不产生 diff（幂等） | unit | 同上（临时目录里跑两次并比较字节） | ❌ Wave 0 |
| INFRA-02 | 手改副本后 `--check` 非零并指出差异 | unit（负例） | 同上（篡改临时副本后断言 rc=1 且输出含文件名） | ❌ Wave 0 |
| INFRA-02 | 一致时 `--check` 零退出 | unit | 同上 | ❌ Wave 0 |
| INFRA-02 | 仓库内不存在第二份手写配置 | unit（扫描） | 同上（构造多余副本，断言 rc=1） | ❌ Wave 0 |
| 成功标准 4 | 干净 clone 复现 1–3 | smoke（手动或脚本） | `tools/verify_clean_clone.sh`（可选）：`git clone . "$tmp"` → `cd "$tmp/desktop" && uv sync --locked` → `bash "$tmp/tools/check_desktop.sh"` → `uv run --project desktop python tools/sync_config.py --check` | ❌ Wave 0（可选） |

### Sampling Rate

- **Per task commit:** `uv run --project desktop python tools/test_sync_config.py`（改了同步脚本/配置时必跑）；改了测试/路径时跑 `bash tools/check_desktop.sh`。
- **Per wave merge:** `bash tools/check_desktop.sh` + `uv run --project desktop python tools/sync_config.py --check`。
- **Phase gate:** 全绿 + 干净 clone 复现（成功标准 4）。若 `verify_clean_clone.sh` 未实现，必须在 VERIFICATION 里逐条粘贴命令与输出。

### Wave 0 Gaps

- [ ] `tools/collect_checks.py` —— 检查名记录器（Pattern 2 / Code Examples），**必须在移动前存在**
- [ ] `shared/expected_checks.txt` —— 230 行基线，**必须在移动前生成并提交**（D-08）
- [ ] `tools/check_desktop.sh` —— 闸门（D-07）
- [ ] `tools/sync_config.py` —— 同步 + `--check`（D-04）
- [ ] `tools/test_sync_config.py` —— 同步脚本自测（用自建 `check()`，不引入 pytest）
- [ ] `desktop/skills_config.json` + `mobile/assets/config/skills_config.json` + 两份 `.sha256` —— 生成并提交
- [ ] `.github/workflows/desktop-checks.yml` —— CI（D-09）
- [ ] 框架安装：**无**（不新增依赖）

## Security Domain

> `security_enforcement = true`、`security_asvs_level = 1`（`.planning/config.json`）。

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | 无账号、无登录 |
| V3 Session Management | no | 无会话 |
| V4 Access Control | no | 本地单用户工具，无权限模型 |
| V5 Input Validation | **yes** | 配置 JSON 已由 `parse_config` 全量校验（类型/范围/方向/按键/重复名）；同步脚本只接受固定白名单路径，不拼接用户输入；CI 不接受外部输入 |
| V6 Cryptography | **yes** | 只用 `hashlib.sha256`（标准库），禁止自实现摘要；`.sha256` 仅用于完整性，不作认证 |
| V14 Configuration | **yes**（轻） | 单一真源 + 生成副本 + hash；配置文件路径在冻结态仍走 `user_config_dir()`（`padskills/config.py:46-57`） |

### Known Threat Patterns for {git + uv + GitHub Actions + Godot res://}

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| CI action 被替换/投毒 | Tampering / Elevation | `setup-uv` 与 `checkout` 按 commit SHA 固定；`uv sync --locked` + 锁文件内建 hash |
| 依赖混淆/镜像投毒 | Tampering | `[[tool.uv.index]]` 固定 PyPI；`uv.lock` 记录 `sha256`；不使用 `--no-verify-hashes` |
| 手改生成副本绕过校验 | Tampering | `--check` 内容比对 + `.sha256`；CI 每次跑 |
| 同步脚本被指向仓库外（路径穿越） | Tampering | 目标路径硬编码为常量；`--root` 仅用于测试且需 resolve 后仍在 root 下 |
| 误提交 `.venv` / 日志 / 构建产物 | Information disclosure（本地路径/环境） | `.gitignore` 覆盖三棵子树（Pitfall 7 的实测矩阵） |
| 配置文件含 secrets | Information disclosure | 本阶段配置只有动作规则；无密钥；CI 不注入任何 secrets |
| 冻结态写入只读目录 | Denial of service | 保持现有 `ensure_user_config` 的 `OSError` 兜底（`padskills/config.py:67-77`），不改 |

**本阶段不引入新的运行时输入面**：同步脚本是开发者工具，不进入打包产物，也不被桌面运行时调用。

## Sources

### Primary (HIGH confidence)

- **实测（本机，2026-11-04）**：`uv --version` → 0.9.5；`uvx pyinstaller --version` → 6.22.3；`uv lock --check` / `uv sync` / `uv sync --locked` 在"有/无 `[[tool.uv.index]]`"下的退出码与 lockfile 变化；`uv --directory` vs `uv run --project` 的子进程 cwd；`git mv` 后的 `git log --follow`；PyInstaller 6.22.3 的 `SPECPATH` 探针；230 项检查名收集（搬迁前后逐字节一致）；`.gitignore` 规则矩阵（`git check-ignore`）。
- **Context7 `/astral-sh/uv`**：`crates/uv-cli/src/lib.rs` 的 `--project` / `--directory` 文档；`docs/concepts/projects/sync.md` 的 `--locked` / `--frozen`；`crates/uv/src/commands/project/lock.rs` 的索引校验逻辑；`docs/concepts/configuration-files.md` 的 `[[tool.uv.index]]`。
- **Context7 `/pyinstaller/pyinstaller`**：`doc/spec-files.rst` 的 `SPEC` / `SPECPATH` 定义；`doc/usage.rst` 的 spec 调用方式。
- **Context7 `/godotengine/godot-docs`**：`classes/class_fileaccess.rst`（非资源文件默认不导出）、`tutorials/scripting/filesystem.rst`（`res://` 指向 `project.godot` 所在目录）、`tutorials/export/exporting_projects.rst`（`*.json` 需加入非资源导出过滤器）。
- **`github.com/astral-sh/setup-uv` README**（2026-11-04 抓取）：当前版本 v10.3.3，SHA `68559e99cc807c1eb7e9238fd43a15bba460eec2`；`working-directory` / `enable-cache` / `python-version` 输入语义。

### Secondary (MEDIUM confidence)

- **`docs.astral.sh/uv/guides/integration/github/`**（页面日期 2026-11-03）：`uv sync --locked --all-extras --dev` 的 CI 推荐形态；action 示例仍为 v9.0.0（滞后于 README）。
- **`docs.astral.sh/uv/changelogs/0.4.x.md`**：`--index-url` → `--default-index` / `[[tool.uv.index]]` 的迁移说明。

### Tertiary (LOW confidence)

- 无。本阶段没有仅靠 WebSearch 得出的结论。

## Metadata

**Confidence breakdown:**

- **Standard Stack: HIGH** —— 所有版本都在本机或官方 README 中核对；没有新增依赖。
- **Architecture: HIGH** —— 搬迁后的 182 + 48 已在本机临时目录完整演练，名称与基线逐字节一致；uv / PyInstaller / git 的关键行为均有可复现实验输出。
- **Pitfalls: HIGH** —— 前 5 条陷阱都有本机复现；其余（locale 排序、编码、`.gitignore`、spec、`--write-config`）来自代码逐行阅读 + `git check-ignore` / AST 检查。
- **Validation / Security: MEDIUM** —— 验证层设计已用原型验证，但"应用启动时校验"的归属仍是 Open Question；安全面很小，结论稳定。

**Research date:** 2026-11-04
**Valid until:** 2026-12-04（uv / setup-uv 版本推进较快；lockfile 与 CI 部分 30 天内有效）

