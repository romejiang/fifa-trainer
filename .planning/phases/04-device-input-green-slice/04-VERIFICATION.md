---
phase: 04-device-input-green-slice
verified: 2026-11-06T00:20:00Z
status: passed
score: 5/5 success criteria (SC3 partial — second controller unavailable, user-accepted)
---

# Phase 4 Verification — 设备输入层 + 绿色搓射竖切

**Verification basis:** automated gates re-run on the final tree; real-device evidence from three
device sessions recorded in `mobile/ACCEPTANCE.md` §6; input-event log pulled from the device at
`/sdcard/Android/data/com.fifaskill.trainer/files/input_log.txt`.

## Success Criteria

| # | Criterion | Verdict | Evidence |
|---|-----------|---------|----------|
| 1 | 绿色搓射 tap 检测器先于设备代码，黄金向量由 Python 生成，GDScript 回放 0 差异 | ✓ PASSED | `tools/gen_tap_golden.py --check` exit 0; `TAP_GOLDEN_DETECTOR cases=12 mismatches=0`; `TAP_GOLDEN_RUNTIME cases=6 mismatches=0` |
| 2 | 全新手机首次打开，按图文引导唤醒手柄并完成摇杆设置，不读文档 | ✓ PASSED | Attempt 3: clean uninstall + install, single-page setup, controller detected, four direction pushes → `ready=1 span=2.00/2.00`, A saved, practice entered |
| 3 | 引导记录右摇杆实际轴序号与符号并落盘 per-device profile；换手柄重新探测，绝不沿用 | ⚠ PARTIAL | Profile captured via diagnostics: `rs_x=(2,-1) rs_y=(3,1)`; `pair=2/3 sign=1/1`; controller-swap reject face **not tested** (only one controller). User accepted this gap; carried to Phase 5/9 |
| 4 | 布局建议自动给出，必须按键确认才进入练习 | ✓ PASSED | Single page shows `layout=xbox`, Start cycles, `confirmed=1` only after A; `InputSetup.build_profile` cannot set `layout_confirmed` without the A path |
| 5 | 真机做一次绿色搓射，屏幕产出且仅产出一次判定；快速两次得到两次独立判定 | ✓ PASSED | Input log: 7 attempts with intervals 458/501/560 ms → ok; 209/200 ms → too_fast; 928/718 ms → too_slow; screen `成功 3 / 8`, `group_hits=3`; user confirmed verdicts accurate |

## Requirements

| Requirement | Verdict | Evidence |
|-------------|---------|----------|
| INPUT-01 | ⚠ PARTIAL | Xbox Series X Controller verified over Bluetooth; PlayStation/DualSense not tested (no device) |
| INPUT-02 | ✓ | Axis pair detected from movement, LB/RB override; `grep -R JOY_AXIS_ mobile/src` empty |
| INPUT-03 | ✓ | `InputSetup` center/range from continuous min/max; `profile_id=input_setup`; atomic `ProfileStore` write |
| INPUT-04 | ✓ | Layout suggested on the same page, Start cycles, A confirms; never silently applied |
| INPUT-05 | ✓ | `PadSampler` event-first + per-frame reconciliation; `poll=0` with events present; same-frame reversal suite |
| ONBOARD-01 | ✓ | Pairing/wake screen; user pressed a button to wake |
| ONBOARD-02 | ✓ | Single-page calibration completed by the user; range `2.00/2.00` |

## Gates (final tree)

- `bash mobile/tools/test-core.sh` → `TESTS_SUITES=18` / `TESTS_ASSERTIONS=1533` / `TESTS_DONE failures=0`
- `bash mobile/tools/gate-a.sh` → `GLYPH_OK chars=1053` / `✓ 闸门 A 通过`
- `bash mobile/tools/gate-b.sh` → signed APK 27,079,510 B, cert `e1841a17…32e046`, v2, 16 KB aligned, arm64-only
- `bash tools/check_desktop.sh` → `302 项检查全部通过`
- `python3 tools/lint_core_purity.py mobile/src/core` → `LINT_OK files=28`
- `python3 tools/test_lint_core_purity.py` → 56/56
- `python3 tools/make_font_subset.py --check` → 1053 chars

## Accepted Risks

1. **SC3 / INPUT-01 partial:** only one physical controller. The per-device profile and reuse gate are
   proven; the "different controller → re-probe" reject face is not. Accepted by the user on
   2026-11-06 to unblock Phase 5. Phase 5/9 must re-run D2 with a second controller.
2. **Left stick not mapped yet:** `InputSetup` writes `ls_x/ls_y = -1`. The green finesse is button-only,
   so Phase 4 is unaffected; Phase 5's `relative_to_ls` skills require LS mapping and must add it.
3. **Active-window `dt95` not isolated:** the reported `dt95=234.7` includes idle gaps; Phase 5's
   decimation matrix must measure the active-window distribution.

## Deviations from the original plan

- The four-step probe + calibration + layout pages (04-05/04-08) were replaced by a single-page
  `InputSetupScreen` (04-09) after two failed device runs. The old screens remain in the tree but are
  not the first-run path.
- `OnboardingFlow`'s step machine is no longer used by `main.gd`; its tests remain green.
- The final acceptance run used the input event log (`04-10`) instead of real-time screenshots.
