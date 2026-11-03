# Phase 1: 仓库拆分 + 配置单一真源 + 桌面回归闸门 - Context

**Gathered:** 2026-11-04
**Status:** Ready for planning

<domain>
## Phase Boundary

把现有扁平仓库拆成 `desktop/` + `mobile/` + `shared/` 三棵子树，并建立两道机械闸门：

1. **行为闸门** —— 搬迁后桌面版 230 项检查全绿，且检查项数量与名称与搬迁前逐项一致。
2. **配置闸门** —— `shared/skills_config.json` 是仓库里唯一手写的动作配置；其余副本由脚本生成并受 hash 校验保护。

本阶段不写任何移动端游戏代码、不初始化 Godot 项目、不新增用户可见功能、不重构桌面版内部结构。

</domain>

<decisions>
## Implementation Decisions

### 搬家深度

- **D-01:** 只做**最小平移** —— 把 `app.py`、`main.py`、`padskills/`、`tests/`、`build/`、`pyproject.toml`、`uv.lock`、`FIFA-Skill-Trainer.spec` 整体移入 `desktop/`，`padskills/` 内部模块结构一字不动。**Reversibility:** reversible — 纯路径移动，回滚只需 `git revert`。
  - 理由：本阶段的验收是「行为零变化」，每多一层结构改动就多一倍需要证明的东西。`CONCERNS.md` 里记录的上帝模块（`gui.py` 1308 行等）属于独立的技术债，不能在搬迁阶段顺带处理，否则一旦回归失败将无法区分是路径问题还是重构问题。

- **D-02:** `pyproject.toml` 与 `uv.lock` 跟随代码进入 `desktop/`，仓库根**不再**保留 Python 项目元数据。所有桌面命令在 `desktop/` 目录内执行（`cd desktop && uv sync && uv run app.py`）。**Reversibility:** costly — 根目录若残留 `pyproject.toml` 会让 uv 产生两套环境与第二个锁文件。
  - 理由：uv 以 `pyproject.toml` 所在目录为项目根。保留一份根级副本会直接制造「两个 Python 项目」，与本阶段目标相反。

- **D-03:** 根 `README.md` 改写为**仓库地图**（三棵子树 + 常用命令入口 + 指向子目录文档），原 776 行桌面手册整体移入 `desktop/README.md`，内容不改。**Reversibility:** reversible。
  - 理由：现有 README 全部是桌面版使用说明，放在根目录会让 `mobile/` 的读者误以为那是全仓文档。拆分文档而不改写内容，既是结构清晰又零信息损失。

### 配置单一真源

- **D-04:** `shared/skills_config.json` 是**唯一可手写**的动作配置。`tools/sync_config.py` 是它唯一的消费者与分发者，生成两份**只读副本**：
  - `desktop/skills_config.json`（开发态运行时读取路径不变）
  - `mobile/assets/config/skills_config.json`（未来 Godot `res://` 读取路径）
  
  每份副本旁生成 `.sha256`。`--check` 比对内容并按差异逐条报告，不一致即非零退出。**Reversibility:** one-way — 一旦桌面运行时改为直接读 `../shared/`，冻结打包后的路径语义会改变。
  - 理由：桌面版冻结后是单目录分发（PyInstaller），运行时不能依赖仓库相对路径。生成副本可以保持 `default_config_path()` 的运行时语义不变，从而保护行为闸门。两份副本都不是手写源，且都被 hash 钉住，不构成第二真源。

- **D-05:** `main.py --write-config` 在**开发态**改为写入 `shared/skills_config.json`，随后要求运行 `tools/sync_config.py`；**冻结态**行为不变（写入用户配置目录）。**Reversibility:** costly — 改变了一个开发期 CLI 的写入目标。
  - 理由：否则 `DEFAULT_CONFIG`（`padskills/config.py:250`）与 `shared/skills_config.json` 会同时成为可写入的源，本阶段刚要消灭的多真源问题会立刻复活。冻结态用户没有仓库，必须保持原行为。

- **D-06:** `padskills/config.py` 的 `DEFAULT_CONFIG` **保留**，角色降级为「内置默认值 + `--write-config` 的模板」，不再是运行时读取的配置。运行时可读配置只有一份：同步出来的副本。**Reversibility:** reversible。
  - 理由：`DEFAULT_CONFIG` 还承担 `_readme` 文档与配置生成职责，删除它会大幅扩大改动面；把它降级为模板即可，不必动。

### 回归闸门

- **D-07:** 建立单一入口脚本 `tools/check_desktop.sh`，它是「230 项检查」的**唯一定义**。脚本职责：
  1. 以 `SDL_VIDEODRIVER=dummy`、`SDL_AUDIODRIVER=dummy` 运行 `desktop/tests/test_detectors.py` 与 `desktop/tests/test_gui_smoke.py`
  2. 断言输出中的检查项**名称集合**与 `shared/expected_checks.txt` 逐项相等，且数量为 182 + 48
  3. 任一不符即非零退出并打印缺失/新增项
  
  **Reversibility:** reversible。

- **D-08:** `shared/expected_checks.txt` 必须在**搬迁之前**从当前代码生成一次并提交，作为基线；本阶段任何任务都不得重新生成它来「对齐」结果。**Reversibility:** one-way — 基线一旦被覆盖，就再也无法证明搬迁没有弱化断言。
  - 理由：这是整个阶段唯一的防作弊机制。允许重新生成基线，等于允许把「删掉一个失败断言」洗成「基线更新」。

- **D-09:** 新增 `.github/workflows/desktop-checks.yml`，在 push 与 PR 时调用同一个 `tools/check_desktop.sh`（`uv sync` 后执行）。**不**安装 pre-commit hook。**Reversibility:** reversible。
  - 理由：远程仓库已存在（`origin git@github.com:romejiang/fifa-trainer.git`），CI 是唯一无法用 `--no-verify` 绕过的闸门；同时它复用同一脚本，不会产生第二套检查定义。hook 会被下意识绕过，且会给日常提交增加摩擦，收益低于 CI。

### 移动端骨架

- **D-10:** 本阶段 `mobile/` 只创建 `mobile/README.md` 与 `mobile/assets/config/`（同步目标），**不**创建 `project.godot`。Godot 项目初始化归 Phase 2。**Reversibility:** reversible。
  - 理由：Phase 1 不应依赖本机装好 Godot 4.7.2。由一个未知版本生成 `project.godot` 后，Phase 2 用正确版本打开时会被静默重写；把项目文件的创建权交给「锁定工具链」的那一阶段更干净。

### 仓库设施

- **D-11:** 根 `.gitignore` 重写为覆盖三棵子树的规则，至少包含：`desktop/build/*`（保留两条脚本白名单）、`desktop/dist/`、`mobile/.godot/`、`mobile/build/`、`mobile/export/`、`*.apk`。**Reversibility:** reversible。
  - 理由：现有 `build/*` 与 `!build/*` 白名单在搬迁后会指向不存在的路径，必须同步移动；顺带为 Phase 2 预留移动端产物忽略规则，避免第一次导出就把缓存提交进来。

### the agent's Discretion

以下区域用户明确表示「你来决定」（原话：*这些细节你来决定我也看不懂，你来决定*），规划与执行阶段可按实际发现调整实现手段，但不得改变上述决定的目标：

- 同步脚本的具体参数形态（除 `--check` 必须存在外）
- `.sha256` 文件的格式与存放位置
- `expected_checks.txt` 的具体文本格式（只要满足「名称集合逐项相等」）
- CI 的 Python 版本矩阵（单版本即可，建议与本地一致的 3.11+）
- 迁移过程中临时提交的拆分粒度

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### 阶段定义
- `.planning/ROADMAP.md` §Phase 1 — 目标与 4 条成功标准（本阶段的验收定义）
- `.planning/REQUIREMENTS.md` — INFRA-01（仓库拆分 + 230 检查）、INFRA-02（配置单一真源 + 同步 + hash）
- `.planning/PROJECT.md` §Constraints — 「回归红线」与「配置真源」两条硬约束

### 现有代码事实
- `.planning/codebase/STRUCTURE.md` — 当前目录布局、模块依赖方向、`build/` 与 `.gitignore` 的现状
- `.planning/codebase/CONVENTIONS.md` — 中英分工、命名与格式约定（搬迁后必须保留）
- `.planning/codebase/TESTING.md` — 测试如何运行、182 + 48 的来源、无 pytest 的事实
- `.planning/codebase/CONCERNS.md` §Tech Debt — 明确**不在**本阶段处理的桌面版债务

### 研究结论
- `.planning/research/SUMMARY.md` §Phase 1 — 「仓库拆分 + 配置单一真源 + 桌面回归闸门」是最先且阻塞一切的一步
- `.planning/research/STACK.md` §配置管线 — `*.json` 需显式导出过滤、`res://` 只读、`user://` 稀疏覆盖

### 项目状态
- `.planning/STATE.md` §Blockers/Concerns — 已知待验证项，本阶段不涉及但不得破坏

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- **`check()` 自建断言 harness**（`desktop/tests/test_detectors.py:35-48`、`test_gui_smoke.py:36-48`）—— 搬迁后原样保留，是行为闸门的载体。不要为了让 CI 好看而改成 pytest。
- **`DEFAULT_CONFIG`**（`padskills/config.py:250-463`）—— 保留为模板与内置默认值；`_readme` 段落仍是配置文档的唯一说明。
- **`default_config_path()`**（`padskills/config.py:60`）—— 路径推导必须跟着新布局调整，但**冻结态行为不得改变**（用户配置目录优先）。
- **现有 `build/build_macos.sh` / `build_windows.ps1`** —— 作为搬迁后验证 `uv sync` 与 PyInstaller spec 路径是否仍可用的快速探针。

### Established Patterns

- **无 pytest**：测试是可直接执行的脚本，用 `uv run tests/test_*.py` 调用。新增闸门脚本必须沿用这一事实，不要引入测试框架。
- **GUI 冒烟测试自带 SDL dummy 环境变量**（`test_gui_smoke.py:17-19`），闸门脚本无需重复设置，但显式设置更稳妥。
- **中英分工**：标识符与配置键用英文，文档、注释、错误信息用中文。新增脚本的注释与输出同样遵循。
- **`__all__` 导出约定**：每个公共模块顶部声明 `__all__`，`padskills/__init__.py` 不 re-export。

### Integration Points

- **`FIFA-Skill-Trainer.spec`** —— `Analysis(['app.py'])` 是相对路径，搬迁后必须改为相对 `desktop/` 解析。
- **`build/build_*.{sh,ps1}`** —— 目前在仓库根执行 `uv sync`，搬迁后需在 `desktop/` 内执行。
- **`.gitignore` 的 `build/*` 白名单** —— 路径失效，必须随目录移动。
- **`README.md` 中全部 `uv run app.py` / `uv run main.py` 命令** —— 搬迁后需加 `cd desktop` 前缀或改用 `uv run --project desktop`。
- **`tests/` 内的相对导入与路径假设** —— 需逐一核对。
- **`uv.lock` 与 `pyproject.toml` 的项目根语义** —— 二者必须与 `desktop/` 同层，否则 uv 会认为仓库根是项目根。

</code_context>

<specifics>
## Specific Ideas

- 用户的核心诉求原话：**「桌面版和手机版的代码要放到不同的目录里。代码结构要清晰一点，代码目录要清晰一些。」** 本阶段的一切形状决定都以这句为准。
- 用户对 230 项检查的定位是**不可协商的红线**：搬迁后必须全绿，且不允许通过改写、弱化或跳过断言来达成。
- 阶段结束时，一个从没看过这个仓库的人应当能只读根 `README.md` 就判断出「桌面代码在哪、手机代码在哪、共享配置在哪、怎么跑桌面测试」。

</specifics>

<deferred>
## Deferred Ideas

- **桌面版上帝模块拆分**（`gui.py` 1308 行、`detectors.py` 1046 行、`config.py` 790 行）—— 已在 `CONCERNS.md` 记录，属于独立重构，不在搬迁阶段混入。
- **pre-commit hook 形式的本地闸门** —— 本次不采用；CI + 脚本已覆盖同一需求，且 hook 易被 `--no-verify` 绕过。
- **移动端 GDScript 测试的 CI** —— 依赖 Godot headless，归 Phase 2 之后。
- **`shared/golden_vectors.json`** —— Phase 4/5 的对等性基线，本阶段只在 `shared/` 留出位置，不生成内容。
- **iOS 相关目录与构建配置** —— 明确延期，Phase 1 不为它预留空壳。

### Reviewed Todos (not folded)

无 —— 本阶段没有匹配的待办项（`todo.match-phase 1` 返回 0 条）。

</deferred>

---

*Phase: 1-仓库拆分 + 配置单一真源 + 桌面回归闸门*
*Context gathered: 2026-11-04*
