---
phase: 01-repo-split-config-single-source
verified: 2026-11-03T21:00:45Z
status: passed
score: 16/16 must-haves verified
behavior_unverified: 0
overrides_applied: 0
covered_files: [
  ".gitattributes",
  ".github/workflows/desktop-checks.yml",
  ".gitignore",
  ".planning/phases/01-repo-split-config-single-source/01-01-PLAN.md",
  ".planning/phases/01-repo-split-config-single-source/01-01-SUMMARY.md",
  ".planning/phases/01-repo-split-config-single-source/01-02-PLAN.md",
  ".planning/phases/01-repo-split-config-single-source/01-02-SUMMARY.md",
  ".planning/phases/01-repo-split-config-single-source/01-03-PLAN.md",
  ".planning/phases/01-repo-split-config-single-source/01-03-SUMMARY.md",
  ".planning/phases/01-repo-split-config-single-source/01-04-PLAN.md",
  ".planning/phases/01-repo-split-config-single-source/01-04-SUMMARY.md",
  ".planning/phases/01-repo-split-config-single-source/01-05-PLAN.md",
  ".planning/phases/01-repo-split-config-single-source/01-05-SUMMARY.md",
  "README.md",
  "desktop/FIFA-Skill-Trainer.spec",
  "desktop/README.md",
  "desktop/app.py",
  "desktop/build/build_macos.sh",
  "desktop/build/build_windows.ps1",
  "desktop/main.py",
  "desktop/padskills/__init__.py",
  "desktop/padskills/config.py",
  "desktop/padskills/detectors.py",
  "desktop/padskills/engine.py",
  "desktop/padskills/geometry.py",
  "desktop/padskills/gui.py",
  "desktop/padskills/input_source.py",
  "desktop/padskills/rumble.py",
  "desktop/pyproject.toml",
  "desktop/skills_config.json",
  "desktop/skills_config.json.sha256",
  "desktop/tests/test_detectors.py",
  "desktop/tests/test_gui_smoke.py",
  "desktop/uv.lock",
  "mobile/README.md",
  "mobile/assets/config/skills_config.json",
  "mobile/assets/config/skills_config.json.sha256",
  "shared/expected_checks.txt",
  "shared/skills_config.json",
  "tools/check_desktop.sh",
  "tools/collect_checks.py",
  "tools/sync_config.py",
  "tools/test_sync_config.py",
  "tools/verify_clean_clone.sh",
]
covered_digest: "v3:sha256:0778d61fb57b114c7f773d5dfaa0e813ae531d747fbc3f424f89463ca9a10cef"
deferred:
  - truth: "INFRA-02 的「应用启动时校验」子句（本阶段未交付运行期 hash 校验）"
    addressed_in: "Phase 3（RESIL-02 配置错误屏）"
    evidence: "01-03-PLAN.md 的 Scope 说明：D-01 要求开发态行为零变化，本阶段不做启动时/运行期校验；移动端启动校验归 Phase 3 RESIL-02，Phase 1 的机械校验由 tools/sync_config.py --check + CI 承担"
---

# Phase 1: 仓库拆分 + 配置单一真源 + 桌面回归闸门 — Verification Report

**Phase Goal:** 把仓库拆成 `desktop/` + `mobile/` + `shared/`，搬完桌面版行为零变化；`shared/skills_config.json` 成为唯一真源，并有一部可执行的同步 + hash 校验挡住第二份手写副本。
**Verified:** 2026-11-03T21:00:45Z
**Status:** passed
**Re-verification:** No — initial verification

> MVP 说明：ROADMAP 给本阶段标了 `Mode: mvp`，但 Goal 行不是用户故事格式（本阶段对最终用户零可见变化），五个 PLAN 也都在“MVP 说明”里明确说明未编造用户故事。本报告按用户指令做目标后向验证，以 ROADMAP 的四条 Success Criteria 为合同；User Flow Coverage 不适用。若后续需要正式 MVP 结构，应先运行 `/gsd-mvp-phase 1`。

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | 搬迁前提取到 182 + 48 = 230 条检查项名称，全部唯一 | ✓ VERIFIED | `wc -l shared/expected_checks.txt` = 230；`LC_ALL=C sort -u` = 230；闸门实跑分别通过 182 / 48 项 |
| 2 | 基线在任何 `git mv` 之前提交，且可由同一命令逐字节复现 | ✓ VERIFIED | `git log -- shared/expected_checks.txt` 仅 `e4d826c`；`git merge-base --is-ancestor e4d826c 02b03db` 通过；用 `uv run` 重提取 + `LC_ALL=C sort` 后 `cmp` 与基线一致，SHA-256 均为 `724b40a3…596a` |
| 3 | `uv lock --check` 退出 0，`uv.lock` 字节与搬迁前一致 | ✓ VERIFIED | `cd desktop && uv lock --check` rc=0；`git show 02b03db^:uv.lock` 与 `git show HEAD:desktop/uv.lock` 的 SHA-256 同为 `763caf7b…cb4f` |
| 4 | 仓库是 `desktop/` + `mobile/` + `shared/` + `tools/` 四子树；19 条 100% rename、0 行内容改动、历史可追溯 | ✓ VERIFIED | 根目录只剩 `AGENTS.md README.md desktop mobile shared tools`；`git show --numstat -M100% 02b03db` 19 行全部 `0 0`；`--diff-filter=R` = 19、`--diff-filter=D` = 0；`git log --follow -- desktop/padskills/config.py` = 3 条（含 `5e489a1 Initial commit`） |
| 5 | 仓库根一条命令跑完 230 项检查且全绿，数量与名称与拆分前逐项一致 | ✓ VERIFIED | `bash tools/check_desktop.sh` rc=0（2.18s），输出“通过 182 项”“通过 48 项”“✓ 230 项检查全部通过，名称与基线逐项一致”；脚本内部 `diff -u` 基线为空；从 `/tmp` 调用同样 rc=0 |
| 6 | 四份生成文件被 git 跟踪，干净 clone 不会退化成内置 `DEFAULT_CONFIG` | ✓ VERIFIED | `git ls-files --error-unmatch` 四路径通过；两份 `shasum -a 256 -c` 均为 `skills_config.json: OK`；闸门第一步就是 `sync_config.py --check`，缺副本会先红 |
| 7 | 同步一次即生成两份副本 + `.sha256`，重复运行不产生 diff；一致时 `--check` 退出 0 | ✓ VERIFIED | 临时 root 上 `sync` 生成两份副本且 `--check` rc=0；真实仓库连续 `sync` 前后四文件聚合 SHA-256 相同（`7c18ddb3…`），`git status` 无新增漂移 |
| 8 | 手改任一副本后 `--check` 非零退出并指名该文件 | ✓ VERIFIED | 临时副本追加一个空格后 rc=1，输出 `✗ mobile/assets/config/skills_config.json 与真源不一致…`；删 `.sha256` rc=1；多塞 `mobile/skills_config.json` rc=1 并报“多余的副本”；干净 clone 的 `--tamper` 再次复现 |
| 9 | `--write-config` 三级路由正确，开发态读取路径仍为 `desktop/skills_config.json` | ✓ VERIFIED | 路由探针：`default_config_path()` → `<repo>/desktop/skills_config.json`；`shared_config_path()` → `<repo>/shared/skills_config.json`；开发态 `write_config_target()` → `shared/`；显式 `-c /tmp/x.json` 原样返回；`sys.frozen=True` → `~/Library/Application Support/FifaSkillTrainer/skills_config.json`；`main.py --write-config -c` rc=0 且生成 5 个动作 |
| 10 | `.gitignore` 只忽略产物，三份配置与两条打包脚本保持 tracked；`.gitattributes` 钉住 LF | ✓ VERIFIED | 7 条应跟踪路径全部未被 `git check-ignore` 命中；6 条产物路径全部命中（`.gitignore:4/11/12/17/18/19`）；`.gitattributes:10-11` 为 `*.sha256 text eol=lf`、`*.txt text eol=lf` |
| 11 | 只读根 README 即可回答“桌面/手机/共享配置在哪、怎么跑检查”，且不含已知失败的 uv 形态 | ✓ VERIFIED | `README.md` 73 行（<120），10 个必需入口字符串全部存在；`grep 'uv run --project desktop tests/'` = 0；实际阅读确认六节结构与 `cd desktop` 命令正确 |
| 12 | `desktop/README.md` 仍是搬迁前那份 776 行手册，且 follow 历史完整 | ✓ VERIFIED | `wc -l` = 776；`git log 02b03db..HEAD -- desktop/README.md` = 0 条内容改动；`git log --follow` = 2 条（`02b03db` + `5e489a1`） |
| 13 | CI 在 push/PR 调用同一条闸门，action 按 40 位 SHA 固定，`run` 无 `${{ }}` 插值 | ✓ VERIFIED | `yaml.safe_load` 得 4 个 step；两个 `uses` 均匹配 `@[0-9a-f]{40}$`；含 `cd desktop && uv sync --locked` 与 `bash tools/check_desktop.sh`；无 `${{`、无 `continue-on-error`；触发为 `push(main)` + `pull_request` |
| 14 | 干净 clone 上仅用仓库内命令即可得到 230 全绿 + 配置一致，且运行后工作区零漂移 | ✓ VERIFIED | `bash tools/verify_clean_clone.sh` 连续 3 次 rc=0，日志含 182 / 48 / 230 与“✓ 干净 clone 复现成功…工作区无漂移”；脚本内 `git status --porcelain` 断言为空。首次运行曾命中已记录的时序偶发（见备注），随后 3/3 通过 |
| 15 | 干净 clone 里手改移动端副本后，`--check` 与闸门均非零且指名文件；还原后恢复绿 | ✓ VERIFIED | `bash tools/verify_clean_clone.sh --tamper` rc=0，日志含“✓ sync_config.py --check 抓住并指名 mobile/assets/config/skills_config.json”“✓ 回归闸门同样被拦住”“✓ 反例按预期失败”；还原后 `--check` 与零漂移断言均通过 |
| 16 | 源仓库有未提交改动时验证脚本拒绝运行（不用陈旧提交冒充当前状态） | ✓ VERIFIED | 工作区存在两个未跟踪评审文档时运行 `bash tools/verify_clean_clone.sh`，rc=2，stderr 为“✗ 工作区有未提交改动，干净 clone 只能验证已提交状态”并逐行列出状态 |

**Score:** 16/16 truths verified (0 present, behavior-unverified)

### Deferred Items

| # | Item | Addressed In | Evidence |
|---|------|-------------|----------|
| 1 | INFRA-02 的「应用启动时校验」子句 | Phase 3（RESIL-02） | `01-03-PLAN.md` Scope 说明：开发态行为零变化，启动时/运行期 hash 校验不在本阶段；移动端启动校验归 RESIL-02，Phase 1 由 `tools/sync_config.py --check` + CI 承担 |

## Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `desktop/`（19 条 rename） | 桌面版整棵子树，内容零改动 | ✓ VERIFIED | `--numstat -M100%` 全 0；tests/spec/build 脚本与搬迁前 blob 哈希一致 |
| `shared/skills_config.json` | 唯一可手写真源 | ✓ VERIFIED | SHA-256 `bccf123a…eee9`，与搬迁前根 `skills_config.json` 逐字节相同 |
| `desktop/skills_config.json` + `.sha256` | 开发态运行时读取的生成副本 | ✓ VERIFIED | tracked、未被忽略、`shasum -c` OK、与真源 `cmp` 相同 |
| `mobile/assets/config/skills_config.json` + `.sha256` | 未来 Godot 读取的生成副本 | ✓ VERIFIED | 同上；`mobile/` 下仅此两个文件 + README，无 `project.godot`（符合 D-10） |
| `tools/collect_checks.py` | 注入 `check()` 记录器导出名称 | ✓ VERIFIED | 182 / 48 行导出正确；被闸门实际调用 |
| `tools/sync_config.py` | 同步 + 校验 + 多余副本扫描 | ✓ VERIFIED | 8 条契约函数齐备；正例/反例均实跑 |
| `tools/test_sync_config.py` | 自测（幂等/篡改/缺 hash/多余副本/缺真源） | ✓ VERIFIED | `python3 tools/test_sync_config.py` rc=0，23 通过 / 0 失败。注：尚未接入闸门/CI（MED-03，已登记为 post-phase，非本阶段 must-have） |
| `tools/check_desktop.sh` | 230 项检查的唯一定义 | ✓ VERIFIED | `BASELINE_SHA256` 分行常量 + `readonly`；顺序为配置 → 基线 → `uv sync --locked` → 测试 diff |
| `shared/expected_checks.txt` | 230 行不可再生基线 | ✓ VERIFIED | 230 行 / 230 唯一；仅一次提交；SHA-256 `724b40a3…596a` |
| `desktop/padskills/config.py` | `shared_config_path()` / `write_config_target()` + `__all__` | ✓ VERIFIED | 两函数存在并导出；`default_config_path()` 函数体未改 |
| `desktop/main.py` | `-c` 默认 `None` + 三级写入路由 | ✓ VERIFIED | `explicit_config` / `config_path` 派生正确；运行期仍读桌面副本 |
| `.gitignore` / `.gitattributes` | 三子树忽略矩阵 + LF 规则 | ✓ VERIFIED | 13 条路径矩阵全部符合；两条新规则存在 |
| `README.md` / `mobile/README.md` | 仓库地图 + 移动端边界 | ✓ VERIFIED | 73 行 / 22 行；入口字符串齐全 |
| `.github/workflows/desktop-checks.yml` | CI 复用同一闸门，SHA 固定 | ✓ VERIFIED | 结构解析通过；远端首次执行无法本地观察（见备注） |
| `tools/verify_clean_clone.sh` | 干净 clone 正向 + `--tamper` 反例 | ✓ VERIFIED | 入口守卫 rc=2；正向 3/3 rc=0；`--tamper` rc=0 |

## Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `tools/check_desktop.sh` | `shared/expected_checks.txt` | 现场重提取 + `LC_ALL=C sort` + `diff` | ✓ WIRED | 脚本第 15-16 行钉哈希，第 81-88 行做名称 diff；实跑无差异 |
| `tools/collect_checks.py` | `desktop/tests/test_detectors.py` / `test_gui_smoke.py` | `importlib.util.spec_from_file_location` + 替换模块级 `check()` | ✓ WIRED | 闸门 `run_suite` 实际调用，导出 182 / 48 |
| `tools/sync_config.py` | `shared/skills_config.json` | 逐字节读取，写两份副本与 `.sha256` | ✓ WIRED | 生成物与真源 `cmp` 相同，sidecar 格式正确 |
| `desktop/tests/test_*.py` | `desktop/skills_config.json` | `Path(__file__).parent.parent / skills_config.json` | ✓ WIRED | `test_detectors.py:1454` 显式定位；闸门第一步保证副本存在且一致 |
| `tools/verify_clean_clone.sh` | `tools/check_desktop.sh` / `tools/sync_config.py` | clone 内原样调用同一条命令 | ✓ WIRED | 脚本第 50 / 53 行调用；未复制任何检查定义 |
| `README.md` | `desktop/README.md` / `mobile/README.md` | 链接 + 职责分离 | ✓ WIRED | 两处链接存在，桌面手册内容零改动 |
| `.github/workflows/desktop-checks.yml` | `tools/check_desktop.sh` | `run: bash tools/check_desktop.sh` | ✓ WIRED | 4 步工作流的最后一步；无第二套检查命令 |

## Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| `shared/skills_config.json` → 两份副本 | 配置字节 | 唯一真源 | 是（`cmp` 逐字节相同） | ✓ FLOWING |
| `desktop/skills_config.json` → 运行时 | `default_config_path()` | 同步生成副本 | 是（开发态返回该路径并被测试读取） | ✓ FLOWING |
| `shared/expected_checks.txt` → 闸门 | `BASELINE_SHA256` + 名称集合 | 搬迁前测试名称快照 | 是（现场提取与基线逐项一致） | ✓ FLOWING |

## Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| 230 项回归闸门 | `bash tools/check_desktop.sh` | rc=0，182 + 48 = 230，2.18s | ✓ PASS |
| 任意 cwd 解析仓库根 | `cd /tmp && bash …/tools/check_desktop.sh` | rc=0，230 项 | ✓ PASS |
| 配置一致性 | `python3 tools/sync_config.py --check` | rc=0 | ✓ PASS |
| 同步脚本自测 | `python3 tools/test_sync_config.py` | rc=0，23 通过 / 0 失败 | ✓ PASS |
| 手改副本反例 | 临时 root 追加空格后 `--check` | rc=1 且指名文件 | ✓ PASS（期望失败） |
| 缺 `.sha256` 反例 | 临时 root 删除 sidecar 后 `--check` | rc=1 且报“不存在” | ✓ PASS（期望失败） |
| 多余副本反例 | 临时 root 放 `mobile/skills_config.json` | rc=1 且报“多余的副本” | ✓ PASS（期望失败） |
| 幂等 | 真实仓库连续 `sync` 前后聚合 SHA-256 | 相同，`git status` 无漂移 | ✓ PASS |
| 三级路由 | 进程内探针（开发/显式/冻结） | `ROUTE-OK` | ✓ PASS |
| `--write-config` | `uv --directory desktop run … -c /tmp/v_wc2.json` | rc=0，5 个动作 | ✓ PASS |
| 干净 clone 正向 | `bash tools/verify_clean_clone.sh` | 3/3 rc=0，含 230 与“工作区无漂移” | ✓ PASS |
| 干净 clone 反例 | `bash tools/verify_clean_clone.sh --tamper` | rc=0，两道关卡均指认文件 | ✓ PASS |
| 脏工作区守卫 | 有未跟踪文件时运行验证脚本 | rc=2 + 中文原因 | ✓ PASS（期望拒绝） |
| 锁文件一致性 | `cd desktop && uv lock --check` | rc=0 | ✓ PASS |

## Probe Execution

| Probe | Command | Result | Status |
|-------|---------|--------|--------|
| 无 `scripts/*/tests/probe-*.sh` | `find scripts -path '*/tests/probe-*.sh'` | 无输出 | N/A |
| 本阶段机械探针：回归闸门 | `bash tools/check_desktop.sh` | rc=0，230 项 | PASS |
| 本阶段机械探针：干净 clone 全链路 | `bash tools/verify_clean_clone.sh --tamper` | rc=0 | PASS |

## Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| INFRA-01 | 01-01, 01-02, 01-03, 01-04, 01-05 | 仓库拆分为 `desktop/` + `mobile/` + `shared/`，桌面版 230 项检查全部通过 | ✓ SATISFIED | 19 条 100% rename；`check_desktop.sh` 230 项全绿且名称与基线一致；干净 clone 可复现 |
| INFRA-02 | 01-02, 01-03, 01-05 | `shared/skills_config.json` 唯一真源；同步脚本 + hash 校验；应用启动时校验 | ✓ SATISFIED（启动时校验子句已记录延期） | 真源唯一且字节未变；`--check` 正例 0 / 反例非零并指名；`.sha256` 与副本被跟踪；“应用启动时校验”按 01-03 Scope 说明延至 Phase 3 RESIL-02 |

**Orphaned requirements:** 无。`REQUIREMENTS.md` 映射到 Phase 1 的只有 INFRA-01 / INFRA-02，且两者都被至少一个 PLAN 的 `requirements` 字段声明。

## Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| 本阶段触碰的实现文件 | — | `TBD` / `FIXME` / `XXX` / `PLACEHOLDER` | 无 | 全量扫描无命中 |
| `tools/` 新脚本 | — | `return null` / `return {}` / `return []` 之类空实现 | 无 | 未发现桩实现 |

**已登记、明确接受的评审发现（不构成本阶段 gap）：** `01-REVIEW-DISPOSITION.md` 把 MED-01…MED-04 与 LOW-01…LOW-05 全部标为 `open` 的 post-phase 精修项。其中与本阶段机械保证最相关的两条：

- MED-02：`.sha256` 校验只比较第一个字段，畸形 sidecar（仅摘要 / 错文件名 / 单空格 / 多条）可通过；不影响“手改副本必被抓”的主路径。
- LOW-01：`--tamper` 中闸门半段使用 `grep -e "$target" -e "配置"`，后者恒真；但 `--check` 半段仍具体指认了文件，且本次实跑闸门确实因篡改而非零退出。

这两条均不使任何 must-have truth 失效；按本次验证指令不记为 gap。

## Human Verification Required

**无必需人工项。** ROADMAP 的四条成功标准、五个 PLAN 的全部 must-have truths 均已由可执行命令或代码/提交证据覆盖。

### 备注（不阻塞判定）

1. **ROADMAP `Mode: mvp` 与 Goal 格式不一致**：Goal 不是用户故事格式，本阶段对最终用户零可见变化；按 PLAN 的 MVP 说明与本次验证指令按技术目标验证。若需要正式 MVP 结构，应运行 `/gsd-mvp-phase 1`。
2. **PyInstaller 打包未在本次验证中执行**：它不在本阶段 must-have 中。`desktop/FIFA-Skill-Trainer.spec` 与 `desktop/build/*` 相对搬迁前 blob 哈希完全一致；两个打包脚本都用 `BASH_SOURCE/..` 定位项目根，搬迁后该根正好是 `desktop/`，`Analysis(['app.py'])` 的相对路径语义保持不变。建议在 Phase 2 前手动跑一次打包作为额外保险。
3. **一次干净 clone 运行命中了已记录的时序偶发**：首次 `verify_clean_clone.sh` 在 `test_engine_end_to_end` 上出现 179/182（3 项失败，正是 `deferred-items.md` 记录的现象）；随后连续 3 次正向运行与 1 次 `--tamper` 运行均 182 + 48 = 230 全绿。判定为既有测试对 OS 调度停顿敏感，不是搬迁或闸门引入的缺陷；按既有约定不改 `desktop/tests/`。
4. **执行方式说明**：工作区当时有两个未跟踪的评审文档（`01-REVIEW.md`、`01-REVIEW-DISPOSITION.md`）。为满足 `verify_clean_clone.sh` 的脏工作区守卫（设计如此），复验时把它们临时移到批准使用的临时目录，运行后原样恢复；最终 `git status` 与复验前一致。
5. `REQUIREMENTS.md` 已把 INFRA-02 勾为 Complete，而其中“应用启动时校验”子句实际延至 Phase 3。这是需求文档的表述粒度问题，不是实现缺失；已在上方 Deferred Items 与 Requirements Coverage 中显式记录。

## Gaps Summary

无 gap。16/16 条 must-have truths 全部通过，ROADMAP 四条成功标准全部满足；无缺失/桩/未接线的关键产物，无 BLOCKER 级反模式，无未解决的 debt marker。

---

_Verified: 2026-11-03T21:00:45Z_
_Verifier: gsd-verifier_
