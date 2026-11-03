---
last_mapped_commit: 5e489a15e4c8cbbfdedcb5239242264ab5394e66
last_mapped_at: 2026-11-04
---
# Testing Patterns

**Analysis Date:** 2026-11-04

## Test Framework

**Runner: none — the tests are standalone Python scripts with a hand-rolled harness.**

There is **no pytest, no unittest, no nose, no tox, no nox**:

- `pyproject.toml` has no `[dependency-groups]`, no `dev` extra, and no `[tool.pytest.ini_options]`.
- `uv.lock` contains only `pygame-ce`, `pyinstaller` (+ its transitive deps), and `xinput-python`. No test runner is installed anywhere in the lockfile.
- No `conftest.py`, `pytest.ini`, `setup.cfg`, `tox.ini`, or `noxfile.py` exists.
- `README.md:586-598` states this explicitly: *"两个都不依赖 pytest，也不用连手柄。"*
- `.gitignore` lists `.pytest_cache/` and `.mypy_cache/`, but those are aspirational — no such tooling is configured.

`tests/test_*.py` is a **naming convention only**, not a discovery contract. Each file is a program with `main()`.

**Assertion library: none.** A local `check(label, ok, extra="")` function increments module globals `PASS` / `FAIL` and prints a colored line.

**Run commands:**

```bash
uv run tests/test_detectors.py     # recognition algorithms + engine (182 checks, ~1.1s)
uv run tests/test_gui_smoke.py     # GUI drawing + demo trajectory (48 checks, ~0.3s)
```

Results verified on 2026-11-04: **182 passed / 0 failed** and **48 passed / 0 failed**. The README still advertises `127 项` for `test_detectors.py` (`README.md:588, 620`); the actual count grew to 182 — update both lines when you touch the suite.

There is **no watch mode, no coverage command, no test filter, and no CI**. There is no `.github/` directory and no Makefile/justfile.

**Exit codes:** each script returns `1 if FAIL else 0` and is launched with `raise SystemExit(main())`, so `uv run tests/... && ...` works in a shell pipeline.

## Test File Organization

**Location:** top-level `tests/` directory, separate from `padskills/`. No `__init__.py`; the tests are not a package.

**Naming:**
- `tests/test_detectors.py` — detectors, config validation, engine, rumble state machine.
- `tests/test_gui_smoke.py` — headless GUI rendering, demo source, logging, hotkeys.
- Test functions: `test_<subject>` (`test_arc`, `test_config_validation`, `test_history_scroll`).
- Helpers: no `test_` prefix (`make_frame`, `rotate`, `tick`, `variant`, `drive`).

**Bootstrap (required):** both files insert the repo root on `sys.path` before importing the package, because they are executed as scripts, not modules:

```python
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
```

(`tests/test_detectors.py:16`, `tests/test_gui_smoke.py:23`)

**Structure:**

```
tests/
├── test_detectors.py     # 1,480 lines; 17 test functions; 149 check() calls
└── test_gui_smoke.py     #   466 lines; 10 test functions;  54 check() calls
```

The two files are self-contained; there are no shared fixtures or helper modules. Duplication (`check`, `_Sink`) is accepted to keep each file runnable in isolation.

## Test Structure

**Suite skeleton (copy this when adding a file):**

```python
#!/usr/bin/env python3
"""GUI 冒烟测试（不需要真实显示器 / 手柄）。

    uv run tests/test_gui_smoke.py
"""

from __future__ import annotations

import os
import sys

os.environ.setdefault("SDL_VIDEODRIVER", "dummy")     # must precede `import pygame`
os.environ.setdefault("SDL_AUDIODRIVER", "dummy")
os.environ.setdefault("PYGAME_HIDE_SUPPORT_PROMPT", "1")

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import pygame
from padskills.gui import TrainerApp

PASS = 0
FAIL = 0

def check(label: str, ok: bool, extra: str = "") -> None:
    global PASS, FAIL
    if ok:
        PASS += 1
        print(f"  \033[32m✓\033[0m {label}" + (f"  ({extra})" if extra else ""))
    else:
        FAIL += 1
        print(f"  \033[31m✗\033[0m {label}" + (f"  ({extra})" if extra else ""))

def test_something() -> None:
    print("\n[7] 分节标题")
    check("描述期望行为的完整句子", actual == expected, f"实际 {actual}")

def main() -> int:
    ...
    test_something()
    print(f"\n  通过 {PASS} 项，失败 {FAIL} 项")
    return 1 if FAIL else 0

if __name__ == "__main__":
    raise SystemExit(main())
```

**Patterns:**
- **Setup is inside `main()`**, not a fixture: `test_detectors.main()` loads the real `skills_config.json` and passes `cfg` to each test (`tests/test_detectors.py:1454-1471`); `test_gui_smoke.main()` creates a temp config, initializes pygame, and stores `_cfg` / `_cfg_path` as module globals (`tests/test_gui_smoke.py:432-455`).
- **Explicit registration:** every new test function must be added to `main()`'s call list. There is no auto-discovery — a test you forget to call silently never runs.
- **Section headers** are printed as `"\n[7] 回归：按住不放不能反复触发"`, matching the GUI/CLI's `═` banner style.
- **No teardown** except explicit cleanup: `pygame.quit()` at the end of `test_gui_smoke.main()`, `rumble.close()` in `test_engine_end_to_end` (`tests/test_detectors.py:1011`). Temp dirs use `tempfile.mkdtemp(prefix="fifa-...")` and are never deleted (acceptable for short-lived smoke runs).
- **Table-driven loops** replace parametrization:
  ```python
  cases = [
      (180.0, 180.0, "从后往前转 180°", "马赛回旋"),
      (0.0, 90.0, "从前往侧转 90°", "踩单车"),
      (90.0, 90.0, "从侧往转 90°（不完整动作）", "都不触发"),
  ]
  for start, sweep, label, expect in cases:
      ...
      check(f"{label} -> {expect}", fired == expect, f"实际: {fired}")
  ```
  (`tests/test_detectors.py:308-320`)
- **Each `check()` verifies exactly one observable claim.** A scenario often produces 2–3 checks (fired / summary content / no spurious fire).
- **`assert` is used only for preconditions**, never for verdicts: `assert app.engine is not None` after `app._open_device()` (`tests/test_gui_smoke.py:137, 217, 283, 307, 369`). Verdicts must go through `check()` so a failure is counted and the suite continues.

**Assertion style:**

```python
check("从后(180°)顺时针转 200°/500ms -> 触发", hit is not None,
      f"耗时 {hit.elapsed_ms:.0f}ms" if hit else "未触发")
```

- Label: Chinese, states setup → expected outcome, often with the literal numbers.
- Condition: plain boolean expression; no custom matcher DSL.
- `extra`: the **actual** value or diagnostic, so a failure is self-explanatory without a debugger.

## Mocking

**Framework: none.** No `unittest.mock`, no `monkeypatch`, no `MagicMock`. All doubles are hand-written classes that subclass the production base class or wrap the real object.

**Patterns:**

```python
class RecordingBackend(RumbleBackend):
    label = "测试用记录后端"

    def __init__(self):
        self.pulses: List[Tuple[float, float, int]] = []

    def start(self, low, high, duration_ms):
        self.pulses.append((low, high, duration_ms))
        return True
```

(`tests/test_detectors.py:955-963`)

```python
class NullSource(GamepadSource):
    """只用于构造引擎；测试里直接手工喂 _tick。"""
    name = "空手柄"
    layout_source = "测试"

    def poll(self) -> PadState:
        return PadState()
```

(`tests/test_detectors.py:646-653`)

**Existing doubles:**

| Double | Base / role | Purpose | Location |
|--------|-------------|---------|----------|
| `NullSource` | `GamepadSource` | Engine construction only; frames are injected manually | `tests/test_detectors.py:646` |
| `ScriptedSource` | `GamepadSource` | Plays a scripted trajectory against real `perf_counter` time | `:966` |
| `RotatingSource` | `ScriptedSource` | Nested subclass generating one continuous arc | `:998` |
| `RecordingBackend` | `RumbleBackend` | Records `(low, high, duration_ms)` pulses | `:955` |
| `TimelineBackend` | `RumbleBackend` | Records ordered `("start", ...)` / `("stop",)` events for state-machine timing | `:1026` |
| `FailingBackend` | `RumbleBackend` | `start()` returns `False` | `:1112` (nested) |
| `ExplodingBackend` | `RumbleBackend` | `start()` raises `RuntimeError` | `:1128` (nested) |
| `SpyDetector` | duck-typed wrapper | Counts `on_idle()` calls without changing behavior | `:670` |
| `_Sink` | file-like | Swallows engine stdout in GUI tests | `tests/test_gui_smoke.py:48` |
| `_fake_outcome()` | factory | Builds a minimal `Outcome` for UI tests | `tests/test_gui_smoke.py:426` |

**What to mock:**
- Hardware boundaries: gamepad source and rumble backend. Never open a real device in tests.
- Time only when the production API already accepts it: `DemoSource(clock=lambda: clock[0])` (`tests/test_gui_smoke.py:58`), and synthetic `Frame.now` values. Do **not** monkeypatch `time.perf_counter`; the engine intentionally takes `now` as a parameter.
- Output streams: pass `out=_Sink()` or `RumbleEngine(None, enabled=False)`.

**What NOT to mock:**
- Parsers, detectors, geometry, engine decision logic — these are the units under test and are cheap to run for real.
- `parse_config` / `load_config`: tests use the real `skills_config.json` and the real `DEFAULT_CONFIG`, which is what catches configuration regressions.
- Dataclasses: construct them directly (`PadState(...)`, `Outcome(...)`).

## Fixtures and Factories

**Synthetic-trajectory builders (detectors):**

| Helper | Purpose | Location |
|--------|---------|----------|
| `stick(angle, mag)` | angle + magnitude → raw `(x, y)`; inverse of `geometry.angle_of` | `tests/test_detectors.py:46` |
| `make_frame(t, rs_angle, rs_mag, ls_angle, ls_mag, facing, buttons)` | Build one `Frame` with derived magnitudes/angles | `:52` |
| `rotate(t0, start_angle, sweep, duration_ms, hz=250, mag=0.92, ...)` | Constant-speed arc | `:65` |
| `flick(t0, angle, mag=0.9, hold_ms=60.0, ...)` | One push → hold → recenter (60 ms default push, 80 ms release) | `:82` |
| `centered(t0, duration_ms, hz=250)` | Stick centered | `:98` |
| `held(t0, angle, duration_ms, mag=0.92)` | Push and hold without moving | `:105` |
| `tap_frames(t0, interval_ms, hold_ms=60.0, second=True, rb=True, rb_release_at=None, modifier="RB")` | Modifier held + two X presses with a controlled gap | `:123` |
| `tick(engine, t, rs_angle, rs_mag, buttons, ls_angle, ls_mag=0.9)` | Feed one frame directly to `Engine._tick` | `:656` |
| `drive(engine, seconds, t0=0.0, step=0.004)` | Advance `RumbleEngine.update()` at 4 ms steps | `:1042` |

**Skill lookup — by name fragment, never by index:**

```python
def skill_of(cfg, name_fragment: str) -> Skill:
    for s in cfg.skills:
        if name_fragment in s.name:
            return s
    raise AssertionError(f"配置里找不到动作 {name_fragment!r}")
```

(`tests/test_detectors.py:168-172`; `default_skill_raw` and `skill_index` follow the same rule — the docstring at `:176` explains that indexes shift when a new action is added.)

**Variants:** `variant(base_name, **params)` deep-copies the default skill and overrides params, so a single rule can be probed at different thresholds without touching `skills_config.json`:

```python
over = variant("马赛回旋", end_angle=90, end_tolerance=10)
```

(`tests/test_detectors.py:114-120`)

**Config data:**
- Detector suite: the real repo file — `load_config(Path(__file__).resolve().parent.parent / "skills_config.json")` (`:1454`).
- GUI suite: a fresh temp config — `dump_default_config(tmp / "skills_config.json")` into `tempfile.mkdtemp(prefix="fifa-gui-")` (`tests/test_gui_smoke.py:442-444`). This also exercises the config writer/reader round-trip.
- Corruption cases: write invalid JSON directly (`'{ "skills": [ }'`, `tests/test_gui_smoke.py:257-258`).

**Location:** all fixtures live inside the test files. There is no `conftest.py`, `fixtures/`, or `factories/` package.

## Coverage

**Requirements: none enforced.** No coverage tool, no threshold, no badge, no CI gate. `.gitignore` does not even list `.coverage`.

**View coverage:** not applicable — there is no command. If you add `coverage.py`, run:

```bash
uv run --with coverage coverage run tests/test_detectors.py
uv run --with coverage coverage report -m
```

but note that a script harness only measures top-level execution; branch coverage of the detector state machines is better assessed by reading `test_failure_diagnostics` (`tests/test_detectors.py:1283`), which drives every failure code.

## Test Types

**Unit tests (majority):**
- `geometry.py`: angle normalization, wraparound, centered-stick behavior (`test_geometry`, `:194`).
- `config.py`: every validation rule through 22 `expect_error(...)` cases (`test_config_validation`, `:1155`).
- Each detector in isolation with synthetic frames (`test_arc`, `test_stepover`, `test_sequence_*`, `test_button_taps`).
- Failure taxonomy: one case per `Failure.code` (`test_failure_diagnostics`, `:1283`). All ten codes are covered: `too_fast`, `too_slow`, `too_short`, `overshoot`, `wrong_start`, `wrong_end`, `wrong_direction`, `stalled`, `incomplete`, `hold_short`.

**Integration tests:**
- Engine + detectors + rumble backend: `Engine(cfg, NullSource(), RumbleEngine(RecordingBackend(), enabled=True))` then `tick()` per frame (`test_failure_diagnostics` tail, `test_engine_gesture_lock`, `test_engine_facing_and_group`).
- Rumble state machine in isolation: `test_rumble_state_machine` (`:1052`) verifies start/stop timing, drop-on-busy, disabled mode, failing/exploding backends, and non-blocking behavior (`update()` under 10 ms).
- GUI + engine + demo source: `run_demo()` advances 9 simulated seconds at 250 Hz through `engine._tick` and asserts 5 skills succeed once each and 4 failure codes appear (`tests/test_gui_smoke.py:85-128`).

**End-to-end (real clock):**
- `test_engine_end_to_end` (`tests/test_detectors.py:989`) runs `engine.run(duration=0.9)` against a `ScriptedSource` driven by `time.perf_counter()`, then asserts one hit, one rumble pulse, and **250 ± 25 Hz**. This is the only genuinely wall-clock-dependent test; keep its tolerance loose.
- GUI smoke tests are end-to-end for the draw path: real `pygame` surfaces, real `TrainerApp._draw(now)`, real event queue (`pygame.event.post` + `app._handle_events`).

**Soak/regression tests:** none. Timing-sensitive regressions are encoded as targeted cases with user-reported symptoms in the docstring, e.g. `test_no_retrigger_while_held` (`:513`) and `test_idle_reset` (`:572`).

## Headless GUI Testing

Set these **before importing pygame** (`tests/test_gui_smoke.py:19-25`):

```python
os.environ.setdefault("SDL_VIDEODRIVER", "dummy")
os.environ.setdefault("SDL_AUDIODRIVER", "dummy")
os.environ.setdefault("PYGAME_HIDE_SUPPORT_PROMPT", "1")
```

Then:
- Initialize only what is needed: `pygame.display.init()`, `pygame.font.init()` (never `pygame.init()`).
- Create an offscreen surface: `screen = pygame.display.set_mode((W, H))`; assign `app.screen = screen`.
- Call `app._draw(now)` directly with explicit timestamps rather than running the app loop.
- Assert "did not crash" with `try/except Exception` around `_draw`, because rendering failures are the thing under test:
  ```python
  ok = True
  try:
      app._draw(1.0)
  except Exception as exc:
      ok = False
      print(f"    绘制异常: {type(exc).__name__}: {exc}")
  check("GUI：练习界面能完整绘制", ok)
  ```
  (`tests/test_gui_smoke.py:164-171`)
- Drive the engine with `app.engine._tick(t0 + i * 0.004, state)` — reaching into private members is expected in this suite.
- **No screenshot/golden-image comparison.** Visual correctness is validated geometrically (e.g. `_stick_point` up/down/left assertions, `:198-206`) or by inspecting generated text logs.

## Common Patterns

**Async / timing testing:** there is no `async`. Time is simulated by passing `now` in seconds:

```python
frames = rotate(0.0, 180.0, 200.0, 500.0)   # 500 ms of motion at 250 Hz
hit = run_detector(ArcDetector(skill), frames)
```

`run_detector(detector, frames)` returns the **first** hit only (`tests/test_detectors.py:159-165`); to assert "fires exactly once", collect all results:

```python
hits = [h for h in (det.update(f) for f in frames) if h is not None]
check("持续推着外圈连转两圈 -> 只触发一次", len(hits) == 1, f"实际 {len(hits)} 次")
```

**Error testing:** config validation uses a mutation helper rather than `pytest.raises`:

```python
def expect_error(label, mutate):
    data = copy.deepcopy(base)
    mutate(data)
    try:
        parse_config(data)
        check(label, False, "居然没报错")
    except ValueError as exc:
        check(label, True, str(exc)[:60])
```

(`tests/test_detectors.py:1160-1167`) — always deep-copy the base config; never mutate it in place.

**Failure-code testing:** drain via the public API, not by inspecting `_pending`:

```python
def verdict(det, frames):
    run_detector(det, frames)
    return det.pop_failure()

f = verdict(det, rotate(0.0, 180.0, 60.0, 150.0) + centered(0.15, 200))
check("转得不够 -> too_short", f is not None and f.code == "too_short",
      f.message if f else "没有裁定")
```

**Engine-result testing:** sequence detection is exposed through `engine.outcome_seq` / `engine.last_outcome`; the GUI uses the same mechanism, so tests mirror production:

```python
if engine.outcome_seq != seen:
    seen = engine.outcome_seq
    outcomes.append(engine.last_outcome)
```

(`tests/test_gui_smoke.py:98-101`)

## Adding a New Test

1. Pick the file: pure logic → `tests/test_detectors.py`; anything that draws or touches the event loop → `tests/test_gui_smoke.py`.
2. Write `def test_<subject>(cfg) -> None:` (omit `cfg` if unused) with a Chinese `print("\n[N] 标题")` section header.
3. Use `check()` for each claim; put the actual value in `extra`.
4. Build trajectories with `make_frame` / `rotate` / `flick` / `held` / `tap_frames`; look skills up with `skill_of(cfg, "片段")` or `variant(...)`.
5. **Register it in `main()`** — this is mandatory and easy to forget.
6. Run `uv run tests/test_detectors.py` and confirm `失败 0 项`.
7. Update the count in `README.md:588` and `:620` if the suite grew.

## Coverage Gaps and Hazards

**[P1] Real device path is untested.**
- What's not tested: `PygameJoystickSource.__init__`, `_sample_rest`, `_auto_layout`, `_parse_binding`, `_layout_from_mapping`, `_layout_from_rest`, `_hat_matches`, `_trigger_value` (`padskills/input_source.py:189-554`). The SDL mapping parser is the most logic-dense untested code in the repo.
- Risk: a mapping-table format change or axis-layout regression is only caught on hardware.
- Mitigation for new work: extract the pure parsing helpers and test them with literal SDL mapping dicts (`{"rightx": "a2", "righty": "-a3", ...}`) — no pygame needed.

**[P2] CLI surface is untested.**
- What's not tested: `main.py` argparse wiring, `--write-config`, `--list`, `--selftest`, `--duration`, `app.py` manual arg parsing (`app.py:32-45`).
- Risk: flag regressions ship silently; `--write-config` is the documented way to regenerate `skills_config.json`.
- Mitigation: `cmd_*` functions are already isolated (`main.py:86-178`); test `_parse_args` and `dump_default_config` directly, and snapshot the generated JSON structure.

**[P2] GUI entry point and packaged behavior are untested.**
- What's not tested: `main_gui` (`padskills/gui.py:1279`), `_wait_config` / `_wait_device` loops, `_open_log` BOM/truncation edge cases, `sys.frozen` branches (`is_frozen`, `user_config_dir` per-platform), PyInstaller build.
- Risk: "double-click does nothing" class of bugs, which the code comments say is the most common packaging failure.
- Mitigation: test `user_config_dir` by patching `sys.platform`; unit-test `_open_log` with an oversized file in a temp dir (it is already exercised indirectly at `tests/test_gui_smoke.py:209-253`).

**[P2] Timing tests can flake on a loaded machine.**
- `test_engine_end_to_end` asserts 250 ± 25 Hz over a real 0.9 s run (`tests/test_detectors.py:1022`); `test_rumble_state_machine` asserts `update()` < 10 ms (`:1151`). Both are wall-clock sensitive.
- Do not tighten these tolerances. If they flake, prefer injecting a clock over widening them silently.

**[P3] No isolation between tests.**
- Shared mutable `Skill` objects across `Engine` instances; `test_button_taps` mutates and restores `required_buttons` (`:799-800`); GUI tests depend on module globals `_cfg` / `_cfg_path` set in `main()`.
- Consequence: individual test functions cannot be run in isolation, and ordering matters.
- Future: build per-test configs with `parse_config(copy.deepcopy(DEFAULT_CONFIG))`.

**[P3] pytest would not work out of the box.**
- Test functions take a `cfg` argument with no fixture, so `pytest tests/` would error with "fixture 'cfg' not found"; `test_gui_smoke.test_draw` also depends on module globals initialized in `main()`.
- If pytest is ever adopted, add a `conftest.py` fixture for `cfg`, move the GUI bootstrap into a session fixture, and convert `check()` to assertions. Until then, run the scripts directly.

**[P3] Suite counts drift from documentation.**
- `README.md:588` and `:620` say 127 checks; the suite currently emits 182. Keep the numbers honest or drop them from the README.

---

*Testing analysis: 2026-11-04*
