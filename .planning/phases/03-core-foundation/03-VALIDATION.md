---
phase: "3"
slug: "core-foundation"
status: draft
nyquist_compliant: false
wave_0_complete: false
created: "2026-11-05"
---

# Phase 3 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | 自建无头 runner（`extends SceneTree` + 完成哨兵 + 看门狗），无 GUT、无 pytest |
| **Config file** | 无 —— runner 与 `test-core.sh` 自带断言 |
| **Quick run command** | `bash mobile/tools/test-core.sh`（几何 + 配置 + overlay + lint，无引擎依赖部分） |
| **Full suite command** | `bash mobile/tools/test-core.sh && bash mobile/tools/gate-a.sh` |
| **Estimated runtime** | ~15s（含 Godot 冷启动与导入检查） |

**为什么必须有看门狗和完成哨兵：** 实测 Godot 4.7.2 在三种情况下**返回 0 却不代表通过** —— 脚本解析失败、`class_name` 未解析、依赖编译失败；而入口运行时错误或 `assert` 失败会**挂死**而不是退出。所以：

- 退出码 0 **不足以**判定通过；
- 必须看到 `TESTS_DONE failures=0` 哨兵行；
- 每个套件必须有 `complete()` 完成标记；
- `test-core.sh` 必须带超时（挂死即失败）。

---

## Sampling Rate

- **After every task commit:** `bash mobile/tools/test-core.sh`
- **After every plan wave:** `bash mobile/tools/test-core.sh && bash mobile/tools/gate-a.sh`
- **Before `/gsd-verify-work`:** 全量绿 + 架构 lint 绿
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 3-01-01 | 01 | 1 | RESIL-03 | T-03-01 | runner 失败时非零退出，不产生假绿 | script | `bash mobile/tools/test-core.sh`（含故意失败的自检） | ❌ W0 | ⬜ pending |
| 3-01-02 | 01 | 1 | RESIL-03 | T-03-01 | 几何与 Python 参考逐向量一致 | unit | `bash mobile/tools/test-core.sh`（golden vectors） | ❌ W0 | ⬜ pending |
| 3-02-01 | 02 | 2 | RESIL-02 | T-03-02 | 坏配置返回结构化错误而非崩溃 | unit | `bash mobile/tools/test-core.sh`（坏配置语料） | ❌ W0 | ⬜ pending |
| 3-02-02 | 02 | 2 | RESIL-02 | T-03-02 | BOM 输入被识别（不经会剥 BOM 的字符串 API） | unit | `bash mobile/tools/test-core.sh` | ❌ W0 | ⬜ pending |
| 3-03-01 | 03 | 3 | DATA-03 | T-03-03 | 覆盖层写入 `user://`，绝不改 `res://` | unit | `bash mobile/tools/test-core.sh` | ❌ W0 | ⬜ pending |
| 3-03-02 | 03 | 3 | DATA-03 | T-03-03 | 原子写：临时文件 + rename，不产生半写文件 | unit | `bash mobile/tools/test-core.sh` | ❌ W0 | ⬜ pending |
| 3-04-01 | 04 | 1 | INFRA-03 | T-03-04 | core 内禁用 token 机械禁绝，且不误报注释/字符串 | script | `python3 tools/lint_core_purity.py` | ❌ W0 | ⬜ pending |
| 3-04-02 | 04 | 1 | INFRA-03 | T-03-04 | lint 有脏样例反例（必须变红） | script | `python3 tools/test_lint_core_purity.py` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `mobile/tools/test-core.sh` —— 带超时、完成哨兵、失败传播的 runner 驱动
- [ ] `mobile/tests/core_runner.gd` —— `extends SceneTree` 的断言收集器（不 fail-fast）
- [ ] `tools/lint_core_purity.py` —— `mobile/src/core/` 禁用 token 扫描器
- [ ] `shared/golden/geometry_vectors.json` —— Python 侧生成的几何黄金向量

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| 错误屏在真机可读 | RESIL-02 | 真机字体与布局；Phase 7 才有正式 UI | 真机装坏配置后启动，确认错误屏可读（若本阶段交付最小错误屏） |

*其余行为均有自动化验证。*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
