---
phase: "5"
slug: "judge-parity-decimation"
status: draft
nyquist_compliant: false
wave_0_complete: false
created: "2026-11-06"
---

# Phase 5 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | 桌面：自建 `check()`（只读参考）；移动端：Godot 4.7.2 headless + 自建 Reporter |
| **Config file** | `mobile/tests/core_runner.gd` 的 `SUITES` 字典 |
| **Quick run command** | `bash mobile/tools/test-core.sh` |
| **Full suite command** | `bash tools/check_desktop.sh && bash mobile/tools/test-core.sh && bash mobile/tools/gate-a.sh` |
| **Estimated runtime** | quick ~50 s；full ~3–6 min |

**基线（Phase 5 开工前必须仍是这些数）：**

```text
bash tools/check_desktop.sh          → 302 项检查全部通过
bash mobile/tools/test-core.sh       → TESTS_SUITES=18 / TESTS_ASSERTIONS=1533 / TESTS_DONE failures=0
python3 tools/gen_tap_golden.py --check → detector 12 条、runtime 6 条
```

**判据（不可放宽）：** stdout 哨兵 `^TESTS_DONE failures=0$` + 拦截 `^TESTS_ASSERTIONS=0$` + 180 s 看门狗；退出码永不单独作判据。

## Sampling Rate

- **After every task commit:** `bash mobile/tools/test-core.sh`
- **After every plan wave:** quick + `bash tools/check_desktop.sh` + `bash mobile/tools/gate-a.sh`
- **After changing `test-core.sh`:** additionally `bash mobile/tools/test-core-selftest.sh`
- **Before `/gsd-verify-work`:** full suite green + D5-0…D5-8 recorded in `mobile/ACCEPTANCE.md`
- **Max feedback latency:** ~50 s (quick) / ~6 min (full)

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 05-01-T1 | 01 | 1 | JUDGE-03 | fixture parity + e2e | `bash mobile/tools/test-core.sh`（`GESTURE_GOLDEN cases=1`）+ `python3 tools/gen_gesture_golden.py --check` | ❌ W0 | ⬜ pending |
| 05-01-T2 | 01 | 1 | JUDGE-01 | fixture parity | `GESTURE_GOLDEN cases=5` | ❌ W0 | ⬜ pending |
| 05-01-T3 | 01 | 1 | JUDGE-04 | fixture parity | `GESTURE_GOLDEN cases=10` + `bash tools/check_desktop.sh` | ❌ W0 | ⬜ pending |
| 05-02-T1 | 02 | 2 | JUDGE-04 | fixture parity（边界 18 条） | `GESTURE_GOLDEN cases>=28` | ✅ 扩展 | ⬜ pending |
| 05-02-T2 | 02 | 2 | JUDGE-03 | fixture parity（变体 7 条） | `GESTURE_GOLDEN cases>=35` | ✅ 扩展 | ⬜ pending |
| 05-02-T3 | 02 | 2 | JUDGE-01 | fixture parity + mutation | `GESTURE_GOLDEN cases>=52` + 四段变异记录 | ✅ 扩展 | ⬜ pending |
| 05-03-T1 | 03 | 3 | JUDGE-03 | unit（Phase 4 兼容） | `bash mobile/tools/test-core.sh`（`TESTS_ASSERTIONS>=1533`） | ✅ 扩展 | ⬜ pending |
| 05-03-T2 | 03 | 3 | JUDGE-06 | engine fixture | `GESTURE_RUNTIME cases=29 mismatches=0` | ❌ W0 | ⬜ pending |
| 05-03-T3 | 03 | 3 | JUDGE-06 | mutation | 三段变异记录 + `git diff --exit-code` | ❌ W0 | ⬜ pending |
| 05-04-T1 | 04 | 4 | JUDGE-05 | unit | `bash mobile/tools/test-core.sh`（`GESTURE_*` 仍 0 差异） | ✅ 扩展 | ⬜ pending |
| 05-04-T2 | 04 | 4 | JUDGE-05 | unit（签名） | `_record` 定义数 1 / 参数 8 | ✅ 扩展 | ⬜ pending |
| 05-04-T3 | 04 | 4 | JUDGE-05 | unit + mutation | `MEASURED cases>=12 mismatches=0` + 三段变异记录 | ❌ W0 | ⬜ pending |
| 05-05-T1 | 05 | 5 | JUDGE-07 | fixture matrix | `python3 tools/decimate_trace.py --check`（`cases == 3 × 源用例数`、`>=240`） | ❌ W0 | ⬜ pending |
| 05-05-T2 | 05 | 5 | JUDGE-07 | fixture matrix | `DECIMATION rates=3 cases>=240 mismatches=0` | ❌ W0 | ⬜ pending |
| 05-05-T3 | 05 | 5 | JUDGE-07 | mutation | 三段变异记录 + `shared/skills_config.json` 未改 | ❌ W0 | ⬜ pending |
| 05-06-T1 | 06 | 6 | (LS mapping) | unit | `bash mobile/tools/test-core.sh` | ✅ 扩展 | ⬜ pending |
| 05-06-T2 | 06 | 6 | JUDGE-02 | unit（RS 冻结 / LS 门） | `_check_rs_pair_frozen_before_ls` 通过 + `test-core.sh` | ✅ 扩展 | ⬜ pending |
| 05-06-T3 | 06 | 6 | JUDGE-03 | unit + static + mutation | `bash mobile/tools/gate-a.sh`（`GLYPH_OK`）+ `SINGLE_PAGE nodes=16 added=Ls` + 三段变异记录 | ✅ 扩展 | ⬜ pending |
| 05-07-T1 | 07 | 7 | JUDGE-03 | unit（组合根） | `TESTS_SUITES=23` + `WIRING ok` 静态断言 | ✅ 扩展 | ⬜ pending |
| 05-07-T2 | 07 | 7 | JUDGE-06 | unit + tool + mutation | `DRAIN_SINGLE ok` + `INPUT_LOG_STATS windows=1` + 三段变异记录 | ❌ W0 | ⬜ pending |
| 05-07-T3 | 07 | 7 | JUDGE-02 / 04 / 06 / 07 | manual | D5-1 / D5-2 / D5-3 / D5-6 device checklist + `bash mobile/tools/gate-b.sh` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

## Wave 0 Requirements

- [ ] `tools/gen_gesture_golden.py` — reference harness, `--check`, source hashes, `configs` registry
- [ ] `mobile/tests/fixtures/gesture_golden.json` — generated, never hand-written, with `configs`
- [ ] `mobile/tests/unit/test_gesture_detector.gd` / `test_gesture_engine.gd` / `test_measured.gd`
- [ ] `tools/decimate_trace.py` + `mobile/tests/fixtures/golden_decimated.json` + `shared/decimation_allowlist.json`
- [ ] `tools/analyze_input_log.py` — active-window p50/p95/max
- [ ] `mobile/tools/test-core.sh` — four new sentinel greps（下限与套件同为 52 / 29 / 12 / 240）
- [ ] No new framework install — the hand-rolled runner is sufficient

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| LS mapping on a real pad | JUDGE-02 | Axes/signs only come from physically pushing a stick; no simulated pad proves it | D5-0 / D5-1: 设置页显示「左摇杆：轴 N/M」；**先**推 RS 四方向、**再**推 LS 上/右、再推 LS 四方向、按 A；`INPUT_SETUP` 行同时有 `rs=`、`ls=`、`ls_ready=1` |
| 5 actions each 3 times | JUDGE-02 | Real stick gestures + timing | D5-2: each attempt produces exactly one `OUTCOME` with matching `skill` |
| 5 failure codes | JUDGE-04 | Requires human mistakes | D5-3: too_fast / too_slow / wrong_start / wrong_end / hold_short each once; Chinese reason readable on screen |
| Arbitration: one gesture one verdict | JUDGE-06 | Real motion | D5-4: a 90° sweep yields exactly one `OUTCOME`, no companion `incomplete` |
| Release/cooldown window | JUDGE-06 | Real timing | D5-5: two shots with 200 ms gap → 2 verdicts; 100 ms → 1 |
| Active-window dt95 | JUDGE-07 | Real event timing | D5-6: `analyze_input_log.py` on the D5-2 window |
| Second controller re-probe | Phase 4 carry | Needs a second pad | D5-8: connect a DualSense/other pad; reuse gate must reject and re-probe |

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter after validate-phase

**Approval:** pending
