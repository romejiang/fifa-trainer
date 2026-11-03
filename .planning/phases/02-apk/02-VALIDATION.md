---
phase: "2"
slug: "apk"
status: draft
nyquist_compliant: false
wave_0_complete: false
created: "2026-11-04"
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | 无测试框架。三层 shell/python 闸门脚本（A/B/C），由 Godot CLI 与 Android SDK 工具驱动 |
| **Config file** | 无 —— 闸门脚本自带断言 |
| **Quick run command** | `bash mobile/tools/gate-a.sh`（无模板、无设备：PCK + 字体覆盖 + 项目导入） |
| **Full suite command** | `bash mobile/tools/gate-b.sh`（A + 完整 release 导出 + 签名/对齐/badging 静态校验） |
| **Estimated runtime** | A ≈ 10s；B ≈ 90s（首次含模板解压） |

---

## Sampling Rate

- **After every task commit:** `bash mobile/tools/gate-a.sh`
- **After every plan wave:** `bash mobile/tools/gate-b.sh`
- **Before `/gsd-verify-work`:** A 与 B 都必须绿；C 由人工在真机执行
- **Max feedback latency:** 120 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 2-01-01 | 01 | 1 | INFRA-04 | T-02-01 | 工具链缺失时 fail-closed 并指名缺失项，不静默跳过 | script | `bash mobile/tools/doctor.sh`（缺设备时以非零退出并列出缺项） | ❌ W0 | ⬜ pending |
| 2-01-02 | 01 | 1 | INFRA-04 | T-02-01 | `--version` 前缀匹配而非等号比较 | script | `bash mobile/tools/doctor.sh`（断言 `4.7.2.stable`） | ❌ W0 | ⬜ pending |
| 2-02-01 | 02 | 1 | INFRA-04 | T-02-02 | 配置真的在包里，不是从项目目录读到 | integration | `bash mobile/tools/gate-a.sh`（`--export-pack` + `--main-pack` 读出 `SKILL_COUNT=5`） | ❌ W0 | ⬜ pending |
| 2-02-02 | 02 | 1 | INFRA-04 | T-02-02 | 两类字体合起来覆盖全部必需字形 | script | `bash mobile/tools/gate-a.sh`（字形覆盖断言，含 `✗`） | ❌ W0 | ⬜ pending |
| 2-03-01 | 03 | 2 | INFRA-04 | T-02-03 | 导出失败时不得留下可被误认为成功的 APK | integration | `bash mobile/tools/gate-b.sh`（`apksigner verify` + `zipalign -c -P 16`） | ❌ W0 | ⬜ pending |
| 2-03-02 | 03 | 2 | INFRA-04 | T-02-03 | 签名与包名稳定，`versionCode` 单调递增 | script | `bash mobile/tools/gate-b.sh`（`aapt2 dump badging` 断言包名/versionCode/versionName） | ❌ W0 | ⬜ pending |
| 2-04-01 | 04 | 3 | INFRA-04 | — | 真机安装、启动、中文、轴值 | manual | 见 Manual-Only 表 | — | ⬜ pending |
| 2-04-02 | 04 | 3 | INFRA-04 | T-02-04 | 构建文档可在另一台干净机器复现 | manual | 见 Manual-Only 表 | — | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `mobile/tools/doctor.sh` —— 工具链体检（Godot 版本前缀、JDK 17、build-tools 36.1.0、keystore、adb 设备），缺失项 fail-closed
- [ ] `mobile/tools/gate-a.sh` —— 闸门 A：不需要导出模板、不需要设备
- [ ] `mobile/tools/gate-b.sh` —— 闸门 B：完整 release 导出 + 签名/对齐/badging
- [ ] `mobile/project.godot` + 最小场景 —— 被 A/B 驱动
- [ ] `mobile/assets/fonts/` —— CJK 主字体 + 符号 fallback（子集）

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| 真机安装并启动到首屏 | INFRA-04 | 需要真实 Android 手机；模拟器不能证明 OEM ROM 行为 | `adb install -r <apk>`，点图标启动，确认不停在启动屏 |
| 中文与 `° ± → ✓ ✗` 不豆腐 | INFRA-04 | 需要真实 OEM 字体回退行为；两台不同 OEM 才有效 | 在两台不同品牌手机上打开首屏，逐字确认无方框/缺字 |
| 蓝牙手柄原始轴实时变化 | INFRA-04 | 需要真实蓝牙手柄；模拟器无此通道 | 配对 Xbox 或 DualSense，推动右摇杆，观察屏上轴序号与数值 |
| 另一台干净机器可重导出 | INFRA-04 | 需要真正未配置过的环境 | 按 `mobile/BUILD.md` 从零执行，产出可用 APK |

**诚实说明：** 本阶段的核心价值是「真机上确实能跑」，而这一部分**无法自动化**。闸门 A/B 只能证明包结构、字体覆盖、签名与对齐正确；它们不能替代真机。任何声称「模拟器通过所以真机没问题」的结论都不成立。

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 120s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
