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
| 3-01-01 | 01 | 1 | RESIL-03 | T-03-01 | 只在看到 `TESTS_DONE failures=0` 时判过，退出码不作判据 | script | `bash mobile/tools/test-core.sh`（含故意失败的自检） | ❌ W0 | ⬜ pending |
| 3-01-02 | 01 | 1 | RESIL-03 | T-03-03 | 几何与 Python 参考逐向量一致，夹具可被 `--check` 抓手改 | unit | `bash mobile/tools/test-core.sh`（golden vectors） | ❌ W0 | ⬜ pending |
| 3-02-01 | 02 | 2 | INFRA-03 | T-03-06 | core 内禁用 token 机械禁绝，且不误报注释/字符串 | script | `python3 tools/lint_core_purity.py mobile/src/core` | ❌ W0 | ⬜ pending |
| 3-02-02 | 02 | 2 | INFRA-03 | T-03-08 | lint 有脏 canary 反例；扫不到文件退出 2 | script | `python3 tools/test_lint_core_purity.py` | ❌ W0 | ⬜ pending |
| 3-03-01 | 03 | 2 | RESIL-02 | T-03-11 | 三张词汇表条目数与 Python 一致，布尔不当方向 | unit | `bash mobile/tools/test-core.sh`（vocabulary） | ❌ W0 | ⬜ pending |
| 3-03-02 | 03 | 2 | RESIL-02 | T-03-12 | Pulse / Step / Skill 默认值与 Python 逐字段一致（含 `pattern` 一条 Pulse） | unit | `bash mobile/tools/test-core.sh`（models） | ❌ W0 | ⬜ pending |
| 3-03-03 | 03 | 2 | RESIL-02 | T-03-12 | Input / Rumble / AppConfig 缺省对等，`enabled_skills()` 不泄漏 | unit | `bash mobile/tools/test-core.sh`（models） | ❌ W0 | ⬜ pending |
| 3-04-01 | 04 | 3 | RESIL-02 | T-03-14 | BOM 在字节层被发现，坏字节给结构化错误 + 非空 fix_hint | unit | `bash mobile/tools/test-core.sh`（config_loader） | ❌ W0 | ⬜ pending |
| 3-04-02 | 04 | 3 | RESIL-02 | T-03-15 | 类型严格化：字符串布尔 / null 数值 / 数组冒充标量 / 未知旋转方向早失败 | unit | `bash mobile/tools/test-core.sh`（config_validator） | ❌ W0 | ⬜ pending |
| 3-04-03 | 04 | 3 | RESIL-02 | T-03-17 | 一次给全部独立错误；静默 clamp 变可见 warning 且上界照抄 Python | unit | `bash mobile/tools/test-core.sh`（config_validator） | ❌ W0 | ⬜ pending |
| 3-05-01 | 05 | 4 | RESIL-02 | T-03-19 | 四个点名坏输入成为两端口径一致的契约 | unit | `bash mobile/tools/test-core.sh`（config_corpus） | ❌ W0 | ⬜ pending |
| 3-05-02 | 05 | 4 | RESIL-02 | T-03-21 | 语料覆盖全规则族，且有规模下限防真空绿 | unit | `bash mobile/tools/test-core.sh`（config_corpus） | ❌ W0 | ⬜ pending |
| 3-05-03 | 05 | 4 | RESIL-02 | T-03-20 | Python 侧走 `json.loads(str)`，分歧必须记录否则判红 | script | `python3 tools/check_config_parity.py` | ❌ W0 | ⬜ pending |
| 3-06-01 | 06 | 5 | DATA-03 | T-03-23 | 覆盖层写入 `user://` 并合并生效，绝不写 `res://` | unit | `bash mobile/tools/test-core.sh`（config_store） | ❌ W0 | ⬜ pending |
| 3-06-02 | 06 | 5 | DATA-03 | T-03-24 | 稀疏合并白名单与整体丢弃语义逐条钉死 | unit | `bash mobile/tools/test-core.sh`（overlay_merge） | ❌ W0 | ⬜ pending |
| 3-06-03 | 06 | 5 | DATA-03 | T-03-25 | 原子写无残留；坏/过期覆盖层可恢复；warning 经 `load_config()` 抵达调用方 | unit | `bash mobile/tools/test-core.sh`（config_store） | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `mobile/tools/test-core.sh` —— 带超时、完成哨兵、失败传播的 runner 驱动
- [ ] `mobile/tests/core_runner.gd` —— `extends SceneTree` 的断言收集器（不 fail-fast）
- [ ] `tools/lint_core_purity.py` —— `mobile/src/core/` 禁用 token 扫描器
- [ ] `mobile/tests/fixtures/geometry_golden.json` —— Python 侧生成的几何黄金向量（由 `tools/gen_geometry_golden.py` 产出）

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
