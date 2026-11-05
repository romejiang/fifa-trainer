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
| TBD | — | 1 | JUDGE-03 | fixture parity | `python3 tools/gen_gesture_golden.py --check` | ❌ W0 | ⬜ pending |
| TBD | — | 2 | JUDGE-01 | unit | `bash mobile/tools/test-core.sh` | ❌ W0 | ⬜ pending |
| TBD | — | 2 | JUDGE-04 | fixture parity | `GESTURE_GOLDEN cases>=50 mismatches=0` | ❌ W0 | ⬜ pending |
| TBD | — | 3 | JUDGE-06 | engine fixture | `GESTURE_RUNTIME cases>=26 mismatches=0` | ❌ W0 | ⬜ pending |
| TBD | — | 3 | JUDGE-05 | unit | `MEASURED cases=N mismatches=0` | ❌ W0 | ⬜ pending |
| TBD | — | 4 | JUDGE-07 | fixture matrix | `DECIMATION rates=3 cases>=240 mismatches=0` | ❌ W0 | ⬜ pending |
| TBD | — | 5 | (LS mapping) | unit | `bash mobile/tools/test-core.sh` | ✅ 扩展 | ⬜ pending |
| TBD | — | 6 | JUDGE-02 / JUDGE-04 | manual | D5-2 / D5-3 device checklist | — | ⬜ pending |
| TBD | — | 6 | JUDGE-07 | manual | D5-6 `analyze_input_log.py` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

## Wave 0 Requirements

- [ ] `tools/gen_gesture_golden.py` — reference harness, `--check`, source hashes
- [ ] `mobile/tests/fixtures/gesture_golden.json` — generated, never hand-written
- [ ] `mobile/tests/unit/test_gesture_detector.gd` / `test_gesture_engine.gd` / `test_measured.gd`
- [ ] `tools/decimate_trace.py` + `shared/golden_decimated.json` + `shared/decimation_allowlist.json`
- [ ] `tools/analyze_input_log.py` — active-window p50/p95/max
- [ ] `mobile/tools/test-core.sh` — four new sentinel greps
- [ ] No new framework install — the hand-rolled runner is sufficient

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
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
