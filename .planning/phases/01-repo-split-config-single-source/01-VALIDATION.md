---
phase: "1"
slug: "repo-split-config-single-source"
status: draft
nyquist_compliant: false
wave_0_complete: false
created: "2026-11-04"
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | 自建 `check()` harness（无 pytest，本项目明确不引入测试框架） |
| **Config file** | none — 测试是可直接执行的脚本 |
| **Quick run command** | `uv --directory desktop run tests/test_detectors.py` |
| **Full suite command** | `tools/check_desktop.sh` |
| **Estimated runtime** | ~8 seconds（182 项检测器检查 + 48 项 GUI 冒烟） |

---

## Sampling Rate

- **After every task commit:** Run `tools/check_desktop.sh --quick`（仅检测器，跳过 SDL 冒烟）
- **After every plan wave:** Run `tools/check_desktop.sh`（完整 230 项 + 基线比对）
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 1-01-01 | 01 | 1 | INFRA-01 | T-1-01 | 基线文件在搬迁前生成，且由 git 追踪（防止事后重写） | script | `git ls-files --error-unmatch shared/expected_checks.txt` | ❌ W0 | ⬜ pending |
| 1-01-02 | 01 | 1 | INFRA-01 | T-1-02 | 基线名称集合与测试实际名称逐项相等 | script | `uv --directory desktop run tests/test_detectors.py` + 名称比对 | ❌ W0 | ⬜ pending |
| 1-01-03 | 01 | 1 | INFRA-01 | T-1-01 | 搬迁提交不包含内容修改（rename 100%） | script | `git show --stat --find-renames=100% HEAD` | ❌ W0 | ⬜ pending |
| 1-02-01 | 02 | 1 | INFRA-02 | T-1-03 | 手改副本后 `--check` 非零退出 | unit | `tools/sync_config.py --check` | ❌ W0 | ⬜ pending |
| 1-02-02 | 02 | 1 | INFRA-02 | T-1-03 | 重复同步幂等（无 diff） | unit | `tools/sync_config.py && git diff --exit-code` | ❌ W0 | ⬜ pending |
| 1-02-03 | 02 | 1 | INFRA-02 | T-1-04 | 生成副本随仓库提交，避免 `load_config()` 静默回退 `DEFAULT_CONFIG` | script | `git ls-files --error-unmatch desktop/skills_config.json mobile/assets/config/skills_config.json` | ❌ W0 | ⬜ pending |
| 1-03-01 | 03 | 2 | INFRA-01 | T-1-05 | CI 用 `--locked`，锁文件漂移即失败而非静默重写 | ci | `.github/workflows/desktop-checks.yml` 含 `uv sync --locked` | ❌ W0 | ⬜ pending |
| 1-03-02 | 03 | 2 | INFRA-01 | — | 干净 clone 可复现全部检查 | manual | 见 Manual-Only 表 | — | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `tools/check_desktop.sh` — 闸门脚本本体（Phase 1 要交付的核心产物，不是测试替身）
- [ ] `shared/expected_checks.txt` — 搬迁**之前**从现有代码生成的检查名基线
- [ ] `tools/sync_config.py` — 配置同步与 `--check` 模式

*说明：* 本项目不使用测试框架，因此没有「框架安装」类 Wave 0 项。Wave 0 的实质是**在搬迁动作发生前**先把基线与脚本落地，否则基线失去防作弊意义。

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| 干净 clone 复现 | INFRA-01 | 需要真正的新目录与干净环境，脚本内自测无法证明「不依赖本机残留」 | 1. `git clone <repo> /tmp/fifa-clean` 2. 按根 README 执行命令 3. 预期 230 项全绿 + `sync_config.py --check` 退出 0 |
| PyInstaller 打包仍可用 | INFRA-01（回归红线） | 打包耗时且依赖本机工具链，不适合放进每次采样 | `cd desktop && uv sync --extra build && pyinstaller FIFA-Skill-Trainer.spec`，预期生成 `dist/` 且可启动 |
| 根 README 可独立导航 | INFRA-01 | 「新人只读 README 就能定位三棵子树」无法自动断言 | 让未参与本项目的人仅凭根 README 说出 desktop/mobile/shared 各自位置与桌面测试命令 |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
