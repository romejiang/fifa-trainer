---
last_mapped_commit: 5e489a15e4c8cbbfdedcb5239242264ab5394e66
last_mapped_at: 2026-11-04
---
<!-- refreshed: 2026-11-04 -->

# Codebase Concerns

**Analysis Date:** 2026-11-04

**Scope:** full repository. Python 3.11+ desktop application `fifa-skill-rumble` (gamepad gesture detection + rumble feedback).
**Evidence collected:** static review of all source files; `182` detector/engine checks and `48` GUI smoke checks pass on this machine with `.venv/bin/python` (dummy SDL video); no real controller or rumble hardware was exercised during this audit. Reproductions below were run against the checked-in code.

## Highest-Risk Items

1. **A malformed but "validated" config can fail during device open, where the GUI misreports it as a gamepad failure and does not close the already-open device/rumble handles** (`start_angle` array case, see Known Bugs #1).
2. **GUI rendering and synchronous log flushes run inside the 250 Hz sampling loop**, so a slow frame or disk stall directly causes missed samples and delays rumble stop (`padskills/engine.py:154-186`, `padskills/gui.py:577-621`).
3. **The GUI play loop catches any exception escaping `Engine.run()` as "controller disconnected" and never writes a traceback to the diagnostic log**, hiding real software bugs in windowed builds (`padskills/gui.py:577-591`).
4. **Only one controller family is documented as validated, while layout parsing, multi-controller indexing, and fallback rumble backends have no automated coverage** (`README.md:10-11`, `padskills/input_source.py:189-255`, `padskills/rumble.py:85-207`).
5. **There is no CI, no pytest-compatible test suite, no coverage, and no build pipeline** (`.github/` absent; tests are custom scripts; builds are manual).

---

## Tech Debt

### God modules and mixed responsibilities

- `padskills/gui.py` — `1,308` lines. It combines CJK font discovery (`72-139`), a complete scripted demo input source (`149-265`), rumble backend selection (`278-303`), application state (`313-1308`), event handling, layout/drawing, diagnostic logging, and **in-place config rewriting** (`732-754`). Any layout or lifecycle change touches the state machine, and GUI logic cannot be tested without pygame.
- `padskills/detectors.py` — `1,046` lines. Three independent state machines (`ArcDetector` `125-446`, `SequenceDetector` `453-853`, `TapDetector` `858-1034`) plus shared `Detector`/`Failure`/`Hit` types. Each detector has its own undocumented magic constants and reset semantics.
- `padskills/config.py` — `790` lines, including a ~214-line embedded `DEFAULT_CONFIG` with a long `_readme` (`250-463`), parsing, validation, path resolution, migration helpers, and a user-config generator. Config schema and documentation are in the same module, which encourages drift.
- `tests/test_detectors.py` — `1,480` lines for one self-test script; `tests/test_gui_smoke.py` — `466` lines. Both are custom harnesses, not discoverable by standard tooling.

**Impact:** high review cost, difficult test isolation, and several behavioral inconsistencies noted below.
**Fix approach:** split the GUI into `app_state`, `render`, `diagnostics`, and `config_writer`; split detectors into separate modules with shared base types; move the default config to a generated JSON fixture or a dedicated resource file.

### Duplicated entry points and rumble orchestration

Rumble startup/fallback is implemented three times with slightly different behavior:

- CLI startup block: `main.py:276-302`
- GUI helper: `padskills/gui.py:278-303`
- Selftest: `main.py:123-178`

`app.py:32-45` also has a second, hand-written argument parser that is not argparse and silently ignores unknown flags. Consequences already visible:

- `main.py --gui --no-rumble` still rumbles because `--no-rumble` is applied at `main.py:255-256`, after the GUI branch at `main.py:244-246` returns.
- `app.py` cannot pass `--index`, `--no-rumble`, `--feedback`, or `--duration`; unknown flags are silently discarded.
- Rumble-selection details (`startup_test`, candidate ordering, labels) can drift between the three copies.

**Impact:** flag behavior depends on which entry point is used; fixes must be applied in multiple places.
**Fix approach:** extract one `bootstrap_runtime(config, args) -> (source, rumble_engine, labels)` used by CLI, GUI, and selftest; let `app.py` delegate to `main.py`'s argparse (or share one parser); reject unknown flags.

### Hard-coded thresholds and magic numbers

The following values are not configurable, are duplicated, or are embedded in control flow:

| Value(s) | Location | Consequence |
|---|---|---|
| `IDLE_STICK = 0.20`, `RELEASE_STICK = 0.35` | `padskills/engine.py:97-98` | Gesture lock/idle behavior cannot be tuned for a drifting stick without code changes. |
| `GROUP_SIZE = 10` | `padskills/engine.py:93` | UI "10 per group" is fixed; not in config. |
| `FPS = 60`, `W, H = 900, 620` | `padskills/gui.py:37-38` | Drawing budget and layout are fixed; no DPI/layout adaptation. |
| Diagnostic thresholds `0.5`, `0.3`, `0.045 s` | `padskills/gui.py:521-535` | Log sampling behavior is opaque and undocumented. |
| `report_min_angle = max(20, min_angle * 0.35)` | `padskills/detectors.py:187` | Which aborted arcs are reported as failures is a hidden heuristic. |
| `swept >= 5.0` (direction/stall), `abs(mag-last) >= 0.05`, `3.0°` display threshold | `padskills/detectors.py:310-311, 340, 364, 392, 553` | Detector behavior changes subtly with these constants; no docs/tests for tuning. |
| `abs(mag-last) >= 0.06`, motion/reference `2.0` | `padskills/detectors.py:481, 638` | Sequence motion detection magic thresholds. |
| Rest classification `0.25`, `0.4`, `-0.4`; calibration sleep `0.004` | `padskills/input_source.py:267-291, 428` | Auto-layout heuristic can silently misclassify a device. |
| XInput scaling `65535` / `255` | `padskills/rumble.py:132-134, 157-161` | Backend-specific, easy to get wrong; untested. |
| Duplicated defaults (`enter_threshold`, `max_duration_ms`, `idle_timeout_ms`, etc.) | `padskills/config.py:134-188, 353-461, 522-634`; detector constructors | Shipped config, schema defaults, and detector defaults diverge (see below). |

**Fix approach:** centralize defaults in one schema/constants module, expose user-tunable values in `InputConfig`, and add tests asserting docs/config/code parity.

### Multiple sources of truth for configuration

The same rules exist in at least five places:

1. `DEFAULT_CONFIG` in `padskills/config.py:250-463`
2. The checked-in `skills_config.json`
3. README tables and examples (`README.md:453-546`)
4. Detector constructor defaults (`padskills/detectors.py:134-208, 465-522, 867-889`)
5. The embedded `_readme` string in `DEFAULT_CONFIG`

Verified drift:

- `skills_config.json` lacks the top-level `input.invert` key present in `DEFAULT_CONFIG` (`config.py:330`), and its `_readme` omits the entire `input.invert` section.
- README says `max_duration_ms` defaults to `600` for arc/sequence (`README.md:508-510, 529-531`); `ArcDetector`/`SequenceDetector` constructors default to `700` (`detectors.py:145, 478`), and config validation also defaults to `700` (`config.py:564, 585`).
- README says `idle_timeout_ms` defaults to `180` for arc (`README.md:510`); the shipped arc rules use `250` (`padskills/config.py:365, 389`), and some docs describe "180~300" (`README.md:769`).
- README/test documentation says **127** checks (`README.md:588, 620`); the suites currently contain **182** detector checks and **48** GUI checks.
- `padskills/__init__.py:7` still says detectors are "arc / sequence 两类"; `taps` was added later.
- `tests/test_detectors.py:4` says "验证三个内置动作"; there are five default skills.

**Impact:** regenerating config with `--write-config` produces a different file from the checked-in one; documentation-based tuning can be wrong; test-count claims are stale.
**Fix approach:** generate `skills_config.json` from `DEFAULT_CONFIG` in a test or build step and fail if they differ; keep a single doc source for defaults; update docstrings/counts from test collection.

### Dead code, stale comments, and misleading API

- `InputConfig.button_names` is parsed (`config.py:219, 703-706`) but never read anywhere; users cannot actually override button names with it.
- `AxisLayout.to_dict()` (`input_source.py:134-145`) is never called; manual config cannot express `dpad`, and `from_dict()` ignores a `dpad` key entirely (`input_source.py:148-162`).
- `ArcDetector.path_detail()` (`detectors.py:426-428`) is never used; `_path` is still populated every frame (up to 64 points) for no consumer (`detectors.py:205, 317`).
- `XInputRumble.is_connected()` (`rumble.py:124-128`) is never called.
- `Engine._last_state` (`engine.py:120, 170`) and `Frame.state` (`detectors.py:27-37`) are written but never read by detectors.
- `RumbleEngine.start()` is a no-op kept only for callers (`rumble.py:271-272`); `Pulse.gap_ms` is parsed (`config.py:183, 504`) but the engine ignores it (`rumble.py:290-296`).
- `RumbleEngine.health()` still says "因排队丢弃" (`rumble.py:340-341`), although the queue was removed; "dropped" now means an overlapping pulse was rejected.
- `XInputRumble` docstring says zeroing is done by a "background thread" (`rumble.py:85-90`); there is no background thread (`rumble.py:242-257`).
- `padskills/engine.py` defines `__all__` twice (`16` and `59`); the second overwrites the first.
- `TrainerApp`'s docstring is placed after `_HISTORY_ROWS` (`gui.py:313-315`), so it is not a class docstring and `TrainerApp.__doc__` is `None`.

**Impact:** maintenance confusion, wasted per-frame work, and API promises that do not exist.
**Fix approach:** delete unused fields/helpers or wire them into the UI; correct stale comments; add a lint rule for unused private attributes.

### Error handling that swallows evidence

There are ~40 broad `except Exception` blocks. Many are legitimate cleanup guards, but several erase the only signal a user/support engineer needs:

- `gui._write_log()` swallows write failures (`gui.py:442-450`); the diagnostic channel cannot report its own failure.
- `gui._open_log()` swallows all setup failures and continues silently (`gui.py:415-432`).
- `input_source._query_sdl_mapping()` swallows every failure and returns `None` (`input_source.py:569-602`), so a broken layout query is indistinguishable from "SDL has no mapping".
- `main.py` swallows stdout reconfiguration failures (`main.py:31-36`), fine for output but hides encoding problems.
- `RumbleEngine._safe_stop()` swallows stop failures (`rumble.py:319-323`), leaving no dedicated "could not stop" health counter.
- `PygameJoystickSource.close()` swallows `stop_rumble()` failure (`input_source.py:549-553`).

**Impact:** silent degradation, especially in windowed builds where stdout is unavailable.
**Fix approach:** route failures to a single error sink/counter; log one line with operation, exception type, and context; keep `except Exception` only around cleanup, and never around diagnostics themselves.

### Tight GUI ↔ engine coupling

The GUI reaches directly into engine internals and mutates model objects:

- Reads `engine.skills`, `active.detector`, `active.skill`, `active.last_outcome`, `engine.last_outcome`, `engine.outcome_seq`, `engine.facing`, `engine.facing_valid`, `engine.started_at` (`gui.py:496-506, 573, 600-602, 919-970, 1025, 1144-1145`).
- Mutates `skill.required_buttons` and `skill.raw` in place (`gui.py:719-723`), then special-cases `TapDetector` with `isinstance` to update its modifier (`gui.py:721-723`).
- GUI smoke tests call private `Engine._tick()` directly (`tests/test_gui_smoke.py:147-149, 226-230`), so internal changes break tests.

**Impact:** the UI depends on data structures that should be internal; adding a detector type or changing outcome sequencing requires coordinated GUI changes.
**Fix approach:** expose a read-only snapshot/view model (`EngineSnapshot` with skill rows, latest outcome, timing health), and route user actions through engine commands (`set_modifier`, `reset`, `stop`) instead of mutating `Skill` directly.

### Threading model: sound today, unguarded against future threads

There are **no background threads** in the application (grep finds no `threading`/`Thread`/`Queue` usage). This is deliberate: SDL joystick/rumble calls must stay on the thread that initialized the subsystem (`rumble.py:242-257`, `gui.py:1-10`), and `Engine.run()` calls `source.poll()` and `rumble.update()` on the same thread that invokes the GUI callback. Current state is therefore race-free by construction: `stop()`/`reset_stats()` are called from event handlers inside `_on_tick`, which is itself inside the sampling loop; no lock is needed for CPython-level assignment of `_running` or `outcome_seq`.

The constraint is not enforced, however:

- `Engine.on_tick` is a general callback that runs in the hot loop (`engine.py:154-186`); the GUI uses it for rendering, event handling, and synchronous log flushes. Any future move of rendering/logging to a worker thread would race with `Engine._tick()` mutating detector state and `RumbleEngine._active/_deadline`.
- `RumbleEngine.play()`/`update()` mutate shared timing state with no synchronization (`rumble.py:274-317`); it is main-thread-only by convention, not by assertion.
- Public methods `stop()`/`reset_stats()` (`engine.py:370-385, 470-471`) have no thread guard; calling them from another thread would not corrupt Python objects, but the engine's loop would not be woken and a rumble stop could be delayed.
- `XInputRumble`'s docstring still claims a "background thread" zeroes motors (`rumble.py:85-90`), contradicting the real design.

**Fix approach:** document and assert the main-thread invariant (`threading.get_ident()` check when SDL calls are made); if rendering/logging must move, pass immutable snapshots/events through a queue and keep all `source`/`rumble` calls on the main thread; remove the stale background-thread comment.

### Packaging duplication

- `FIFA-Skill-Trainer.spec` and `build/build_windows.ps1` / `build/build_macos.sh` duplicate the PyInstaller configuration. The build scripts pass `app.py` to PyInstaller and do not use the checked-in spec, so the spec is an unused/stale copy.
- Build scripts do not run the test suites before packaging, and there is no CI build.
- No icon, Windows version resource, or macOS architecture target is configured; unsigned builds are documented (`README.md:581`), but Windows SmartScreen behavior is not.
- `uv.lock` is present and hash-pinned (`uv.lock:69-79`), but its package URLs point at the Aliyun mirror; see Dependencies at Risk.

**Fix approach:** make one PyInstaller spec the source of truth and have both scripts invoke it; add a `--test` gate; document architecture/signing/SmartScreen limitations.

---

## Known Bugs

### 1. `start_angle` as an array passes config validation, then crashes during engine construction

- **Symptoms:** `parse_config()` accepts `start_angle: [0, 90]` because validation loops over array values (`config.py:592-603`). `ArcDetector.__init__` passes the whole value to `resolve_direction()` (`detectors.py:167-170`), which raises `ValueError: 无法识别的方向 [0, 90]`. In the GUI, `Engine(...)` is constructed inside the broad `except Exception` in `_open_device()` (`gui.py:553-563`), so the app falls into its **"未检测到手柄"** screen and logs "打开手柄失败" even though the gamepad is fine.
- **Second-order effect:** `source` is opened at `gui.py:553`, rumble backends may be built at `554`, and neither is closed when `Engine()` raises. CLI construction at `main.py:316` is also outside a cleanup guard.
- **Trigger:** a user writes `start_angle: [0, 90]` (plausible because `end_angle` explicitly supports arrays and validation accepts it).
- **Files:** `padskills/config.py:592-603`, `padskills/detectors.py:167-170`, `padskills/gui.py:540-575`, `main.py:316`.
- **Fix approach:** reject arrays for `start_angle` during validation (or support them in the detector consistently); construct `Engine` under a context manager that closes the source/rumble on failure; distinguish config-detector errors from device-open errors in the GUI.

### 2. String booleans are silently truthy

- **Symptoms:** `bool("false")` is `True`. `enabled: "false"`, `relative_to_ls: "false"`, `startup_test: "false"` all enable the behavior. `AxisLayout.from_dict()` also uses `bool(raw[key])` for `invert_*` (`input_source.py:155-157`), so `"invert_rs_y": "false"` enables inversion.
- **Verified:** `enabled: "false"` parsed to `True`; `startup_test: "false"` and `relative_to_ls: "false"` also parsed to `True`.
- **Files:** `padskills/config.py:656-657, 715, 721`, `padskills/input_source.py:148-162`.
- **Fix approach:** add a strict `_as_bool()` that only accepts `True`/`False` (and perhaps the strings `"true"`/`"false"` deliberately), reject everything else with a field-specific error; use it for every boolean in config and axis layout.

### 3. `null` numeric fields raise a raw `TypeError` outside the friendly config-error path

- **Symptoms:** `load_config()` only converts `ValueError` into the user-facing `SystemExit` message (`config.py:756-782`). Values such as `skills[0].cooldown_ms: null`, `input.poll_hz: null`, `rumble.startup_test_ms: null`, or `rumble.duration_ms: null` reach `int(None)`/`float(None)` and raise `TypeError`. CLI prints a traceback; GUI shows a technical `TypeError: int() argument...` via its broad catch.
- **Verified:** all four examples reproduced as uncaught `TypeError`.
- **Files:** `padskills/config.py:503-505, 662, 672-683, 725`, `756-782`.
- **Fix approach:** make all numeric parsers raise field-scoped `ValueError` on `None`, booleans, strings, and out-of-range values; catch `(TypeError, ValueError)` at the `load_config` boundary and keep the existing friendly format.

### 4. UTF-8 BOM in `skills_config.json` breaks startup

- **Symptoms:** `load_config()` uses `path.read_text(encoding="utf-8")` (`config.py:765-768`) and `json.loads` rejects a leading BOM with `Unexpected UTF-8 BOM`. Windows editors that save UTF-8 with BOM produce a config the app cannot load.
- **Verified:** a BOM-prefixed copy of `DEFAULT_CONFIG` raises the JSON error and exits with code/status message.
- **Files:** `padskills/config.py:765-777`.
- **Fix approach:** read with `utf-8-sig` (and write without BOM, or preserve explicitly); add tests for BOM and CRLF on Windows.

### 5. `--no-rumble` is ignored in GUI mode and produces misleading CLI output

- **Symptoms A:** `main.py --gui --no-rumble` still rumbles because the GUI branch returns before `cfg.rumble.enabled = False` is applied (`main.py:244-256`). `--selftest --no-rumble` also still tests/displays rumble.
- **Symptoms B:** in default CLI output with rumble disabled, every successful detection prints `(识别到了但震动未发出)` because `_fire()` treats any `fired == False` as a send failure (`engine.py:395-412`), while `RumbleEngine.play()` returns `False` immediately when disabled (`rumble.py:282-283`). README promises `--no-rumble` simply prints trigger logs (`README.md:117`).
- **Files:** `main.py:244-256`, `padskills/engine.py:395-412`, `padskills/rumble.py:274-296`.
- **Fix approach:** apply global flags before branching to GUI/selftest; make `_fire()` distinguish `disabled`, `dropped`, `backend failed`, and `started`, or have `play()` return a status enum.

### 6. `SequenceDetector` hold timer accumulates across weak pushes

- **Symptoms:** the README says a hold step requires a **continuous** hold (`README.md:284, 546`), but when the stick drops below `enter_threshold` while staying above `release_threshold`, `update()` returns early without clearing `_hold_since` (`detectors.py:687-690`). The timer keeps running through the dip.
- **Verified:** for La Croqueta (350 ms hold), a `200 ms` push at 0.9, `200 ms` at 0.4 (below enter 0.6, above release 0.3), then a 0.9 push triggered at 400 ms with summary `保持 400ms`; only 200 ms was a real hold before the dip. This enables a false positive from two short pushes separated by a weak hold.
- **Files:** `padskills/detectors.py:626-736` (especially `657-660`, `687-690`, `729-735`).
- **Fix approach:** when `mag < enter` while `t0` is active, pause/reset `_hold_since` (or clear `_best_hold_ms`), and require the hold to be continuous; add a regression test with a below-enter dip. Document whether the timer is continuous or cumulative.

### 7. `ArcDetector.reset()` re-arms without requiring the stick to return to neutral

- **Symptoms:** `SequenceDetector.reset()` deliberately preserves `neutral` (`detectors.py:782-802`), but `ArcDetector.reset()` sets `active=False, armed=True` and leaves the current stick position untouched (`detectors.py:430-436`). If the engine calls `reset()` during a gesture — e.g., the left stick briefly centers for a `relative_to_ls` arc, or a modifier button blips (`engine.py:267-279`) — the next frame can start a fresh arc while the right stick is still pushed, and the remaining motion can trigger a hit.
- **Verified:** after a constructed reset at a valid start angle, continuing the same physical stick motion without releasing produced a hit.
- **Files:** `padskills/detectors.py:430-436`, `padskills/engine.py:219-233, 267-279`.
- **Fix approach:** make `reset()` behave like `_abort()` for arming purposes (require `mag < exit` and the release hold time before re-arming), or add an explicit `require_neutral` guard; add an engine test that resets mid-gesture and asserts no immediate retrigger.

### 8. Modifier persistence is regex-based and cannot handle arrays or legacy keys

- **Symptoms:** `_persist_required_button()` reads the config as text, finds `"name"` spans with a regex, and substitutes only `("required_button"\s*:\s*")([^"]*)(")` (`gui.py:732-754`). It fails for `required_button: ["RB", "RT"]` (supported by the parser), for the legacy `required_buttons` alias (`config.py:636-640`), and for `required_button: null`. A `"name"` key inside `params` also splits the spans incorrectly. Writes use `write_bytes()` directly, with no temp file, backup, fsync, or reload check.
- **Impact:** clicking a modifier chip can report "这个动作没有 required_button" for a valid config; a crash/disk-full during write can corrupt the user's only config; concurrent edits are lost.
- **Files:** `padskills/gui.py:710-754`, `padskills/config.py:636-640`.
- **Fix approach:** load with `json.loads`, update the parsed object, validate it, write to a temp file in the same directory, `os.replace()` it, and keep a `.bak`; support arrays/legacy keys explicitly; add failure-path tests.

### 9. Rumble summary advertises multiple pulses, but the engine only plays the first

- **Symptoms:** `Skill.rumble_summary()` returns `"{n} 连震"` when `len(pattern) > 1` (`config.py:200-204`), but `RumbleEngine.play()` always uses `pattern[0]` (`rumble.py:290-296`). `Pulse.gap_ms` is parsed (`config.py:183, 504`) and ignored. The README does document the single-pulse behavior (`README.md:434-437`), but `main.py --verbose`/`print_skill_table` will still show "N 连震".
- **Impact:** users configuring multi-pulse patterns believe the app will play them; main's skill table contradicts behavior.
- **Files:** `padskills/config.py:200-204, 480-506`, `padskills/rumble.py:274-296`, `main.py:185-195`.
- **Fix approach:** either implement a deliberate non-queued pattern policy (e.g., first pulse only, documented in the summary) or queue pulses with a bounded policy; remove `gap_ms` if unsupported; make the summary match reality.

### 10. `list_devices()` reports rumble availability from `hasattr()` only

- **Symptoms:** `input_source.py:626` sets `"rumble": hasattr(joy, "rumble")`; SDL/pygame may expose the method while the device/driver returns `False` for actual rumble (the README itself notes this for SDL2 Controller on the target device). `--list` can therefore print "震动接口: 可用" for a controller that cannot rumble via that backend.
- **Files:** `padskills/input_source.py:609-629`, `README.md:96-99, 714-725`.
- **Fix approach:** label it "接口存在" rather than "可用", or run a very short, opt-in test (not by default); point users to `--selftest`.

### 11. `--write-config` does not create missing parent directories

- **Symptoms:** `main.py --write-config -c some/new/dir/cfg.json` calls `dump_default_config()` (`main.py:236-239`), which writes directly with `Path.write_text()` (`config.py:785-790`) and raises `FileNotFoundError` if the parent directory does not exist. The packaged-app path through `ensure_user_config()` does create parents (`config.py:67-77`), so behavior differs between first-run app startup and the explicit CLI command.
- **Impact:** a documented maintenance command fails with a traceback in a clean directory; users cannot pre-generate a config where they want it.
- **Files:** `main.py:236-239`, `padskills/config.py:67-77, 785-790`.
- **Fix approach:** `path.parent.mkdir(parents=True, exist_ok=True)` before writing, use a temp file + replace, and report the resolved path.

### 12. CLI mode never drains pygame's joystick event queue

- **Symptoms:** pygame's bundled joystick documentation states that once a `Joystick` is opened, the event queue receives `JOYAXISMOTION`, `JOYBUTTONDOWN/UP`, and `JOYHATMOTION` events, and the queue must be drained with `event.get()`, `event.wait()`, or equivalent. `PygameJoystickSource.poll()` calls `pygame.event.pump()` on **every** sample (`input_source.py:486`), but `Engine.run()` has no `event.get()`/`event.clear()` (`engine.py:164-186`). GUI mode drains events in `_handle_events()` (`gui.py:657-674`); CLI mode (`main.py:316-319`) does not. The event queue therefore grows for the entire CLI session at input-event rate, and `JOYDEVICEADDED`/`JOYDEVICEREMOVED` events are never observed.
- **Impact:** long CLI runs can consume increasing memory and spend increasing time inside `event.pump()`, contributing to sampling overruns; hot-plug cannot be handled; the same omission affects `--debug`/`--feedback` sessions.
- **Verification:** confirmed against the installed pygame-ce joystick documentation (`joystick.rst`: "The event queue needs to be pumped frequently... To be able to get joystick events..."; "Once the device is initialized the pygame event queue will start receiving events about its input"). No physical controller was needed to establish the code path; runtime growth was not measured.
- **Files:** `padskills/input_source.py:484-537`, `padskills/engine.py:164-186`, `padskills/gui.py:657-674`, `main.py:316-319`.
- **Fix approach:** drain or discard events after the pump in CLI mode (e.g., `pygame.event.clear()` each tick or an `Engine` option that clears after the GUI callback has had a chance to process them); optionally watch device removal; add a long-run memory/queue test.

---

## README Claims vs Code

| README claim | Code reality | Evidence |
|---|---|---|
| Only Flydigi Vader 4 is validated (`README.md:10`) but XInput, DInput, and Bluetooth are supported (`README.md:11`). | Only one device family is documented as tested; no automated/multi-device hardware test exists. | No hardware fixtures/CI; `input_source.py:258-292` is heuristic fallback. |
| Users can override SDL's `~` inversion marker with `input.invert` (`README.md:489-491`). | The parser does not recognize `~` at all; a binding containing it is silently dropped. | `input_source.py:189-211` handles only `+`/`-` prefixes and numeric suffixes. |
| `--no-rumble` only prints trigger logs (`README.md:117`). | GUI ignores the flag; default CLI output appends "震动未发出" to every success when disabled. | `main.py:244-256`, `engine.py:395-412`, `rumble.py:282-283`. |
| Test suite has 127 checks (`README.md:588, 620`). | Current suites have 182 detector/engine checks + 48 GUI checks, all passing in this audit. | `grep -c 'check('` on both test files; local runs. |
| Windows diagnostic log is `%APPDATA%\FifaSkillTrainer\trainer.log` (`README.md:698`). | The README contains a literal tab between `FifaSkillTrainer` and `rainer.log`, so the displayed Windows path is wrong (`FifaSkillTrainer<TAB>rainer.log`). macOS path on the next line is correct. | `README.md:698` byte inspection. |
| `uv sync --extra xinput` can be used to work around rumble failures (`README.md:725-727`). | Both PyInstaller build paths exclude the `XInput` module, so packaged Windows builds cannot use XInput-Python; only the ctypes backend remains. | `FIFA-Skill-Trainer.spec:13`, `build/build_windows.ps1` `--exclude-module XInput`, `build/build_macos.sh` same. |
| Multi-pulse patterns are accepted, but only the first plays (`README.md:434`). | This is accurate for playback, but the skill summary still prints "N 连震". | `config.py:200-204`, `rumble.py:290-296`. |
| Opening screen says first connection takes 0.25 s to calibrate (`gui.py:1216`). | Calibration is 0.25 s by default, plus up to 160 ms per rumble backend probed (`pick_backend` sleeps), so startup can block for several times longer. `startup_test_ms` has no upper bound. | `input_source.py:408-433`, `rumble.py:210-235`, `gui.py:1216`. |
| Unsigned builds only (`README.md:581`) and Input Monitoring path binding (`README.md:574-576`). | Accurate and documented, but Windows SmartScreen and macOS architecture (arm64 vs x86_64) are not documented. | Build scripts/spec. |

Also stale docs: README uses old project paths (`fifa19-script`, a personal username at `README.md:20,25`); `padskills/__init__.py:7` says two detector types; `tests/test_detectors.py:4` says three built-in actions.

---

## Security Considerations

**Surface:** this is a local, single-user desktop app. No network calls, authentication, database, cloud storage, or secret files were found; there is no `.env` and no credential handling. Config is parsed as JSON data only (no `eval`/`exec`), and subprocess calls use argument lists rather than a shell (`gui.py:761-775`). The main security-relevant concerns are distribution and local integrity, not remote attack surface.

### Unsigned builds and OS trust

- **Risk:** macOS Gatekeeper blocks unsigned `.app` builds; Windows SmartScreen warns on unsigned `.exe` (not documented). Users are instructed to bypass Gatekeeper (`README.md:569-581`), which trains unsafe behavior and complicates support.
- **Files:** `build/build_macos.sh`, `build/build_windows.ps1`, `FIFA-Skill-Trainer.spec`.
- **Current mitigation:** documentation only; no signing, notarization, or checksums.
- **Recommendation:** sign/notarize releases where possible, publish SHA-256 checksums, and document SmartScreen; if unsigned is intentional, add a short "verify the download" section.

### Config integrity and availability

- **Risk:** GUI modifier changes overwrite the user's config in place with no temp file/backup (`gui.py:732-754`); a crash, disk-full, or concurrent editor can corrupt the only rule file. A malicious or accidental config can also cause a multi-second startup freeze via unbounded `startup_test_ms` (`config.py:725`) or a huge `skills` list (no upper bound in validation).
- **Current mitigation:** validation exists for some fields, and config errors are displayed in the GUI; but the write path bypasses structured validation and is non-atomic.
- **Recommendation:** atomic write + backup + reload/verify; cap or validate all time/interval fields; treat config as untrusted input.

### Logs and privacy

- **Risk:** `trainer.log` records controller name, loaded config path, button/axis mappings, all button changes, and 45 ms stick telemetry (`gui.py:452-538`). It is local and contains no secrets, but it reveals play patterns and local paths, which matters if shared publicly for support.
- **Current mitigation:** log is in the per-user config directory with normal user permissions.
- **Recommendation:** document the log contents in the privacy/support section, offer a "redact device names/paths" option, and rotate rather than overwrite logs (see below).

### DLL loading

- **Risk:** `XInputRumble` loads fixed Microsoft DLL names (`Xinput1_4.dll`, etc.) via `ctypes.WinDLL` (`rumble.py:98-111`); this is standard and uses OS search rules, not user-controlled paths. Residual risk is low.
- **Recommendation:** keep fixed names; do not add configurable DLL paths.

---

## Performance Bottlenecks

### 1. GUI rendering and logging run inside the 250 Hz sampling loop

`Engine.run()` invokes `on_tick` synchronously every frame (`engine.py:154-186`); the GUI callback handles events, parses outcomes, writes/flushes the diagnostic log, and redraws at 60 fps (`gui.py:593-621`). The 4 ms nominal budget is consumed by:

- `pygame` drawing and font rendering every 16.7 ms; measured **~2.73 ms per `_draw()`** on this machine with the dummy video driver (`_draw` at `gui.py:781-800`, `_text` re-renders every string at `gui.py:807-815`). Real display `flip()` can be slower.
- Synchronous log writes with `flush()` on every line (`gui.py:442-450`); `_diagnose()` can emit a line every 45 ms while the right stick is pushed (`gui.py:529-535`), plus outcome lines.
- `%APPDATA%` may be on a roaming/synced or antivirus-scanned profile on Windows, making those flushes much more expensive than local SSD writes.

When a frame exceeds the 4 ms period, the loop counts an overrun and re-aligns (`engine.py:179-186`). Because `RumbleEngine.update()` is only called from this loop (`engine.py:318`), a slow frame also delays the stop deadline; XInput's continuous vibration has no independent watchdog (see Fragile Areas).

**Fix approach:** keep rendering and file I/O out of the sampling callback. Publish a lightweight snapshot from the engine and draw/flush from a separate UI cadence (or at least batch log writes in a queue and flush outside the 4 ms budget); cache rendered text surfaces; draw only on state changes; move the display flip after scheduling the next poll if threading is ever reconsidered.

### 2. Startup blocks the event loop

`PygameJoystickSource._sample_rest()` sleeps in 4 ms increments for `calibration_ms` (default 250 ms), pumping SDL events but not dispatching them (`input_source.py:408-433`). `pick_backend()` then sleeps `duration_ms` for **every** candidate backend (`rumble.py:210-235`), and the GUI calls both synchronously before entering its event loop (`gui.py:540-575`). With the Windows `auto` order (pygame, SDL2, XInput-Python, XInput ctypes), this can be several hundred milliseconds to over a second; `startup_test_ms` is user-controlled and unbounded (`config.py:725`), so it can be much worse. The opening screen says 0.25 s (`gui.py:1216`), which understates the real freeze.

**Fix approach:** show a live progress state and pump events during probe/calibration, or run rumble probing after the window loop starts; cap `startup_test_ms`; try only one backend first and expand on failure.

### 3. Hot-loop allocations

`PygameJoystickSource.poll()` rebuilds `reverse = {v: k for k, v in lay.buttons.items()}` on every frame (`input_source.py:513`), allocates a list for all axes and a list/tuple for all raw buttons, then constructs a new `PadState` (`input_source.py:484-537`). `Engine._tick()` builds a new `Frame` and a `held_required` set every frame (`engine.py:206-215, 237-242`). This is small at five skills (the `_tick` benchmark was ~4 µs here), but it is avoidable GC pressure in the one loop that must hit 250 Hz.

**Fix approach:** precompute `index -> canonical button` and reusable buffers in `PygameJoystickSource`; avoid per-frame set comprehensions when no modifiers are held; keep `Frame`/`PadState` only if profiling shows it matters.

### 4. Sleep-based scheduling has no adaptive compensation and no user-visible health metric

The hot loop uses `time.sleep(slack)` with an absolute `next_tick` schedule (`engine.py:179-186`). This is **not** a busy-wait, but it is dependent on OS sleep granularity and scheduler load. There is no spin phase, no thread priority, and no `timeBeginPeriod`-style hint. `overruns` is incremented and printed only by the CLI summary (`engine.py:142, 503-504`); the GUI never shows it, so the user cannot distinguish a bad render frame from a missed gesture. `test_engine_end_to_end` asserts 250 Hz ±25 over 0.9 s (`tests/test_detectors.py:1010-1023`), which is a timing-sensitive test on loaded machines.

**Fix approach:** expose a small health indicator (actual Hz/overruns, rumble failures) in the GUI and diagnostic log; consider adaptive sleeps or a deadline-based scheduler with a short spin for the final sub-millisecond; document that 250 Hz is best-effort on a shared desktop.

### 5. Log growth and flush behavior

`_open_log()` rotates only at startup and only by truncating to a BOM if the file exceeds 2 MB (`gui.py:413-432`); runtime has no size cap. During continuous stick motion, `_diagnose()` writes and flushes a line every 45 ms (~22 lines/s), so an active session can grow the log quickly. The 2 MB cap destroys the previous evidence exactly when a user restarts after an incident; there is no rolling backup. Two app instances append to the same file without locking (`gui.py:427`).

**Fix approach:** use a bounded queue/background writer, rotate by size with numbered backups at startup and/or runtime, and record session boundaries/version headers so logs are easier to correlate.

---

## Fragile Areas

### Device-layout detection is heuristic and under-tested

- `_layout_from_rest()` assumes the first four axes whose rest values are centered are LS then RS, and the first two extreme axes are LT then RT (`input_source.py:258-292`). It reuses XInput button/hat indices (`296-304`) even for non-Xbox devices.
- `_parse_binding()` only understands `aN`/`bN`/`hN.M` with optional `+`/`-` prefixes; SDL's `~` inversion marker and multi-binding/comma forms are dropped (`input_source.py:189-211`). README explicitly claims `~` can be overridden (`README.md:489-491`).
- `_layout_from_mapping()` accepts button-bound sticks/hats only in limited forms and requires `rs_x` plus at least one button before trusting the mapping (`input_source.py:214-255, 435-444`).
- `AxisLayout.from_dict()` performs no range/type validation and ignores `dpad` (`input_source.py:148-162`); malformed values fail during device open, not config load.
- Only one controller family is documented as validated; a DInput/Bluetooth/PlayStation mapping may silently produce the wrong layout.

**Safe modification:** always run `--list`, `--debug`, and `--selftest` with the actual device; add a fixture-based mapping test set (real SDL mapping strings) and a manual `axis_layout` schema including `dpad`.

### Multi-controller index mapping is not guaranteed

`PygameJoystickRumble` uses the actual joystick object (safe), but the fallback backends use the numeric joystick index as an SDL controller index (`rumble.py:68-83`) or XInput user index (`rumble.py:98-101`). Pygame joystick enumeration, `pygame._sdl2.controller` enumeration, and XInput user slots are not guaranteed to have the same ordering, especially with virtual devices or multiple controllers. `build_backends()` passes `joystick_index` through (`rumble.py:175-207`). Layout lookup has a related weakness: `_query_sdl_mapping()` falls back to matching by device name when instance IDs do not match (`input_source.py:581-599`), so two identical controllers can receive the wrong mapping.

**Impact:** with more than one controller, a fallback backend can rumble the wrong device or fail silently, and the layout probe can read the wrong device's mapping; the config only offers a single index.
**Safe modification:** match by GUID/instance ID where possible, enumerate XInput slots explicitly, add a device picker, and test with two identical controllers.

### Rumble failover and shutdown are not watchdogged

- A backend is selected once at startup (`main.py:276-302`, `gui.py:278-303`); if it later returns failures, `RumbleEngine` counts them (`rumble.py:306-317`) but never retries another backend. A transient driver disconnect leaves the session without feedback until restart. If `startup_test` is disabled, the first candidate is chosen without any start check (`main.py:292-293`, `gui.py:290-291`), so an unsupported backend can be selected even though a working one exists later in the list.
- XInput is continuous-state: `start()` writes motor values and relies on `update()`/`close()` to zero them (`rumble.py:85-141`). Normal `Engine.run()` finally calls `rumble.close()` (`engine.py:189-192`), but a hard kill/crash or a failed `stop` (`rumble.py:319-323` swallows it) can leave the controller vibrating.
- `Engine.run()` calls `_clear_debug_line()` **before** `rumble.close()`/`source.close()` in its `finally` (`engine.py:189-192`). If the debug write/flush raises (broken pipe, closed stdout), cleanup is skipped and the device/rumble may remain open.
- `PygameJoystickSource.close()` calls only `stop_rumble()` and never `self._joy.quit()` (`input_source.py:549-553`); pygame's documentation says a `Joystick` is shut down when deallocated, so this is not a guaranteed permanent leak, but teardown is left to GC and the joystick can keep feeding the event queue until then. `SDL2ControllerRumble` has no `close()`/quit beyond the base stop (`rumble.py:68-83`); `_query_sdl_mapping()` creates `Controller` objects with no explicit teardown (`input_source.py:569-602`). Repeated reconnect cycles may retain SDL handles longer than necessary.

**Safe modification:** close resources first in `finally` (or wrap cleanup in a nested try); add a stop-watchdog and a failure/fallback policy; call `Joystick.quit()`/Controller teardown explicitly; add a test double that raises from debug output to verify cleanup.

### GUI error handling masks failures and can mislabel them

- `_play()` catches **all** exceptions and reports `手柄连接中断` (`gui.py:577-591`), but exceptions from `_on_tick`, `_draw`, font rendering, or logging also propagate through that path. `_draw()` only catches `display.flip()` errors (`gui.py:797-800`), not drawing errors. There is no `sys.excepthook`/traceback file, and the diagnostic log is not written from `_play`'s except (only `_open_device` logs its own failure at `gui.py:562`).
- `_wait_config()`/`_wait_device()` draw without a try/except; a draw bug there exits the app instead of showing an error screen.
- In a `--windowed` build there is no console, so a masked bug becomes an unexplained "controller disconnected" loop.

**Safe modification:** wrap `on_tick` render work in its own try/except that writes a full traceback to the log and shows a non-destructive error banner; classify exceptions (device vs render vs detector); add a top-level exception hook; never report a non-device error as a disconnect.

### Config validation is uneven

Beyond the known bugs above, these fields are accepted and can silently produce a permanently non-firing skill:

- `enter_threshold`, `exit_threshold`, `tolerance_deg`, `start_tolerance`, `end_tolerance`, and `claim_margin_deg` are not range-checked (`config.py:522-664`, `input_source.py:361`): thresholds outside `0..1` and negative tolerance values are accepted. `deadzone` is clamped to `0..1`, but `1.0` is accepted and disables all stick input (`config.py:673`).
- An unknown `direction` silently becomes `"any"` (`detectors.py:154-160`), despite README listing only `any/cw/ccw`.
- `exit_threshold >= enter_threshold` and `release_threshold >= enter_threshold` are silently clamped to `enter - 0.05`/`enter - 0.15` (`detectors.py:137-140, 475-477`) instead of reporting a config typo.
- `axis_layout` values are not validated until `open_source()` (`input_source.py:148-162`): non-integer values fail during device open, while out-of-range indices are accepted and simply never match a real button/axis.
- Disabled skills are still fully validated (`config.py:738`, `_parse_skill` for all items), so an experimental broken skill blocks startup even when `enabled: false`.
- `startup_test_ms`, `cooldown_ms`, `global_cooldown_ms`, and pulse `duration_ms` have no upper bounds; extreme values can freeze startup or disable detection.

**Safe modification:** define a schema with types/ranges/enums and validate every field at load time, including nested axis layout; reject unknown/invalid values with field paths; add a `--check-config` or GUI validation preview.

### Hot-plug and platform assumptions

- The GUI re-enumerates only when it receives `JOYDEVICEADDED` while in `device` mode (`gui.py:630-645, 664-666`). There is no `JOYDEVICEREMOVED` handler; removal is detected only if `poll()` raises. After a reconnect, `pygame.joystick.quit()/init()` is called, but the separate `pygame._sdl2.controller` subsystem is not reinitialized, so a newly attached device may not be discovered for mapping probes (`input_source.py:569-602`).
- The CLI has no reconnect loop; a disconnect propagates out of `Engine.run()` (only `KeyboardInterrupt` is caught) and the process exits with a traceback (`engine.py:187-192`, `main.py:316-319`).
- `main.py` always calls `pygame.display.init()` before CLI monitoring (`main.py:264-267`) and in selftest (`123-129`); `list_devices()` calls `pygame.init()` (`input_source.py:613`), initializing audio/font subsystems despite the GUI's documented rule to avoid `pygame.init()` (`gui.py:9`). Headless Linux/SSH use is therefore unsupported and likely fails before any device access.
- macOS Input Monitoring permission is documented; the app path binding after moving the `.app` is documented but still a common support burden (`README.md:574-576`).
- README targets Windows/macOS (`README.md:1`), while code contains Linux font paths and `/dev/input` hints (`gui.py:87-92, 1245-1246`); Linux is untested.

**Safe modification:** handle removal explicitly, reinitialize both SDL joystick and controller subsystems, add a CLI reconnect loop, and either support headless mode (dummy video/no display) or clearly reject it with a friendly message.

### In-game rumble conflict is unaddressed

The tool is meant to run while FIFA/EA FC is running. Both processes can write the same controller's rumble state; the trainer has no coordination with the game and the README does not tell users to disable in-game vibration. On some drivers the game's feedback will override the training pulse, making detection feedback inconsistent even when recognition is correct.

**Safe modification:** document "turn off in-game vibration for training" and/or add a backend/device isolation check; test with the game running.

### Demo mode is hard-coded to the default rules

`_demo_script()` hardcodes five successes and four failures at specific angles (`gui.py:190-229`), while `_open_device()` uses the user's loaded config in demo mode (`gui.py:548-551`). If the user disables/renames skills or changes thresholds, the demo may no longer show the advertised mix; the GUI smoke test uses a fresh default config, so it does not catch this (`tests/test_gui_smoke.py:432-463`).

**Safe modification:** generate demo trajectories from the active config, or label the demo as "default rules only"; add a test with a customized config.

---

## Scaling Limits

### Skill count breaks the fixed card layout at ~12 skills

The left panel is `300 × 428` with `top = panel.y + 38` and `avail = 376` (`gui.py:913-931`). Card height is `max(30, min(92, (avail - gap*(n-1))/n))` with `gap = 4` for `n > 4`. At `n = 12`, the computed height is `(376 - 44)/12 = 27.7`, clamped to the minimum `30`, giving `12*30 + 11*4 = 404 > 376`; cards overflow the panel and overlap the footer (`_draw_footer` starts at y=512). There is no scroll/paging for skills. The README encourages users to add their own skills.

**Fix approach:** make the skill list scrollable/paged, compute a layout that can shrink below 30 px with a separate detail view, or cap/warn at the safe count.

### Engine work scales linearly with skills

Every frame `_tick()` scans all enabled skills to build `held_required`, then updates each detector, and builds a `Frame`/sets (`engine.py:237-315`). At five skills this is negligible (~4 µs measured for `_tick` here), but user-added skills increase per-frame Python work and GUI card rendering; the layout limit above is reached first. There is no cap on `skills` in config, no profiling, and no test with a large skill set.

**Fix approach:** index skills by required modifier, short-circuit when idle, and add a stress test at 20–50 skills; clamp or warn on counts that cannot fit the UI.

### One controller, one config, one pulse at a time

- The GUI has no device picker; it uses `joystick_index` from config/`--index` (`padskills/gui.py:317-380`, `main.py:230`). Multi-controller users must edit config/relaunch.
- `RumbleEngine.play()` drops a new pulse if one is still active (`rumble.py:285-288`); `dropped` is only exposed in the CLI summary (`rumble.py:335-344`). Back-to-back gestures can silently lose feedback by design.
- Statistics/history are per-process and reset on restart; there is no session persistence or long-term progress history (README only promises "本次运行" stats).

**Fix approach:** add a device picker, expose dropped/overrun counts in the GUI, and persist optional session summaries if progress tracking is desired.

### Log and history size

- History is capped at 50 entries (`gui.py:314, 604-607`) and 5 visible rows; fine.
- The diagnostic log has no runtime cap and only startup truncation (`gui.py:413-432`); long sessions can grow it without bound.
- There is no log rotation/compression or retention policy.

---

## Dependencies at Risk

### `pygame-ce >=2.5.8` with no upper bound and private SDL API usage

- `pyproject.toml:6-8` allows any future pygame-ce version. The implementation depends on:
  - `pygame.joystick.Joystick.rumble()`/`stop_rumble()` (`rumble.py:48-65`)
  - **private** `pygame._sdl2.controller` APIs for mapping queries and SDL rumble (`input_source.py:569-602`, `rumble.py:68-83`)
  - version-specific behavior where SDL controller constants are not exposed (`input_source.py:165-168`)
- Only `2.5.8` is in `uv.lock:69`; no CI matrix tests a new version. A future pygame-ce release can rename/move private APIs or change rumble semantics without a runtime guard beyond `hasattr(joystick, "rumble")`.

**Recommendation:** add an upper bound or a tested version range, wrap private API access behind a compatibility adapter, and run the suite against the minimum and latest supported versions in CI.

### Hardware/driver variability is the dominant risk

- Rumble support depends on controller firmware, USB vs Bluetooth, OS driver, and SDL backend. The code has four backends and several fallbacks (`rumble.py:175-207`), but only the Flydigi device is documented as validated (`README.md:10`).
- `Joystick.rumble()` returning `True` does not guarantee a perceptible pulse; the README includes a manual "feel lab" (`main.py:157-176`) precisely because this is hardware-dependent.
- No automated or recorded hardware test exists; `--list`/`--debug`/`--selftest` are manual.

**Recommendation:** maintain a tested-device matrix; add a diagnostic bundle that records device GUID, SDL mapping, backend results, and raw samples; make `--selftest` results copyable.

### Optional `XInput-Python` is not usable in packaged builds

- `pyproject.toml:12-15` declares `XInput-Python>=0.4.0` for Windows only; `build_backends()` tries it before the ctypes fallback (`rumble.py:198-201`).
- Both PyInstaller paths explicitly exclude `XInput` (`FIFA-Skill-Trainer.spec:13`, `build/build_windows.ps1`, `build/build_macos.sh`), so users of the packaged `.exe` cannot use the documented workaround (`README.md:725-727`). It is also untested and has no upper version bound.

**Recommendation:** either bundle/import the optional package conditionally and test it, or remove the README recommendation for packaged builds and rely on the ctypes backend.

### Build tooling and reproducibility

- `pyinstaller>=6.0` is a build-only dependency with no upper bound (`pyproject.toml:17-20`); build scripts are manual and do not run tests.
- `uv.lock` pins exact versions/hashes but its wheel/sdist URLs point at an Aliyun mirror (`uv.lock:72-79`). A mirror outage/regional block can make `uv sync --locked` fail even though PyPI is reachable.
- Python `>=3.11` has no upper bound and there is no CI matrix; future Python/pygame wheel availability is unverified. The local `.venv` is Python 3.12, while `uv.lock` wheels shown are cp311.
- No `pytest`, `coverage`, `ruff`, or `mypy` dependency/config exists, despite `.gitignore` entries for `.pytest_cache`, `.mypy_cache`, and `.ruff_cache` (`.gitignore:5-7`).

**Recommendation:** pin PyInstaller to a tested major, run builds in CI, verify the lockfile against PyPI (or document/configure the mirror), and add a dev dependency group with quality tools.

### `pygame` vs `pygame-ce`

`import pygame` resolves to whichever distribution is installed. The project declares `pygame-ce`, but a user with classic `pygame` in the environment can get a build without `Joystick.rumble()`; the backend error explains this (`rumble.py:51-56`) but the CLI/GUI may simply show no rumble. The error message says `>=2.4`, while `pyproject.toml` requires `>=2.5.8`; align them.

---

## Missing Critical Features

- **CI/CD:** no `.github/workflows` or equivalent; tests/builds are manual and unverified on Windows/macOS.
- **Standard test runner and coverage:** no pytest/coverage configuration; no enforced pass/fail signal outside the custom scripts; no test count/coverage reporting.
- **Automated hardware/integration coverage:** no recorded controller traces, SDL mapping fixtures, or rumble backend emulator; all device-specific behavior is manually validated.
- **Crash reporting/traceback persistence:** no global exception hook; `_play()` exceptions are not written to `trainer.log`; windowed crashes can leave no evidence.
- **Device picker and guided calibration:** only config/`--index`; no UI to choose among multiple controllers, recalibrate, or preview mapping.
- **Config schema/migration/atomic save:** no schema version, no migration path, no backup/undo, no range validation for many fields; GUI writes are destructive.
- **Build signing/verification:** no code signing/notarization (documented as out of scope), no checksums, no Windows SmartScreen guidance.
- **Log rotation/health UI:** no runtime rotation; the GUI never shows actual Hz/overruns, rumble failures, or dropped pulses.
- **In-game rumble coordination:** no guidance/toggle for FIFA's own vibration.
- **License:** no `LICENSE` file; distribution terms are unstated.
- **Replayable diagnostics:** the log contains samples and detector state, but there is no parser/replay harness to turn a user's real capture into a regression test.

---

## Test Coverage Gaps

### Current state

The custom suites pass locally: **182** detector/engine checks and **48** GUI smoke checks (run via `.venv/bin/python` on 2026-11-04, GUI under `SDL_VIDEODRIVER=dummy`). They are useful, but they are not integrated with standard tooling and do not exercise hardware.

### Coverage table

| Area | What is not tested | Files | Risk | Priority |
|---|---|---|---|---|
| Real gamepad source/layout | `PygameJoystickSource.__init__`, `_sample_rest`, `_auto_layout`, SDL mapping parsing, `~`/comma bindings, trigger rest, deadzone rescaling, hat masks, `close()` | `padskills/input_source.py:189-255, 357-553` | Wrong layout/axis or stale handle on real hardware; the target device is the only known-good case | High |
| Rumble backends/selection | `PygameJoystickRumble`, `SDL2ControllerRumble`, `XInputRumble`, `XInputPyRumble`, `build_backends()` ordering/platform skip, `pick_backend()` failure paths | `padskills/rumble.py:48-235` | Silent no-rumble or wrong-controller feedback; XInput code untested on Windows | High |
| GUI lifecycle/cleanup | `_open_device` failure after source open, `_play` exception path, `_wait_device`/`_wait_config` draw failures, source/rumble cleanup, reconnect/hot-plug, log rotation/BOM, config persistence failure modes | `padskills/gui.py:386-645, 710-754` | Leaks, misreported errors, lost config, app exit without evidence | High |
| Config validation corner cases | `start_angle` arrays, string booleans, `null` numerics, BOM, out-of-range thresholds, invalid `direction`, `axis_layout` malformed values, disabled-invalid skills, upper bounds | `padskills/config.py:522-782`, `tests/test_detectors.py:1155-1280` | Runtime crash/misdiagnosis or silently non-firing skills; only ~26 validation cases exist | High |
| Engine loop behavior | `Engine.run()` stop/duration/KeyboardInterrupt, device disconnect mid-run, overrun accounting, cleanup after callback/log exception, multiple `run()` calls, **CLI event-queue growth (Known Bug #12)** | `padskills/engine.py:154-192`, `padskills/input_source.py:484-537` | CLI traceback on disconnect, cleanup skipped by debug I/O failure, unbounded event queue in long CLI runs | Medium |
| CLI/app argument behavior | `--list`, `--selftest`, `--write-config`, flag precedence (`--gui --no-rumble`, `--duration`), unknown flags in `app.py`, missing parent directories | `main.py:198-324`, `app.py:32-56` | Advertised flags silently ignored or crash with traceback | Medium |
| Multi-skill UI scaling | 12+ skills layout, all-disabled config, long names/messages, modifier options on non-tap detectors | `padskills/gui.py:913-1015` | Cards overlap footer; controls become unusable as users add skills | Medium |
| Detector edge cases | Sequence hold with a below-enter dip (Known Bug #6), Arc reset mid-gesture (Known Bug #7), release-before-min timing, modifier array/`button_mode=any` semantics, tap timeout boundaries | `padskills/detectors.py:240-446, 626-853, 949-1034` | False positives/negatives that synthetic happy-path tests miss | Medium |
| Hardware/platform matrix | Windows/macOS/Linux hot-plug, suspend/resume, Bluetooth, multiple controllers, non-Xbox layouts, high-DPI/resized windows, Input Monitoring | `padskills/input_source.py`, `padskills/gui.py`, build scripts | Only one device is documented as validated; no automated signal | High |
| Multi-pulse/rumble policy | `pattern` > 1, `gap_ms`, overlap/drop counting, backend failure after selection | `padskills/rumble.py:274-344` | Summary/behavior mismatch; feedback silently missing during fast combos | Low/Medium |

### Test infrastructure problems

1. **Not pytest-compatible.** `tests/test_detectors.py` defines `test_*` functions that require a `cfg` argument (e.g., `test_arc(cfg)`, `test_stepover(cfg)`) but there is no `pytest` fixture or `conftest.py`; running `pytest` would fail with `fixture 'cfg' not found`. `tests/test_gui_smoke.py` defines `test_*` functions that depend on module globals initialized only in `main()`, so pytest collection would hit `NameError`/uninitialized `_cfg_path`. There is no pytest dependency in `pyproject.toml`.
2. **Checks do not assert.** The custom `check()` records `PASS`/`FAIL` and prints, but does not raise; under pytest, a function that calls `check(..., False)` still returns normally and would be reported as passing. The only hard failure signal is the `return 1 if FAIL else 0` in each custom `main()`, which pytest does not call.
3. **Timing test is machine-sensitive.** `test_engine_end_to_end` runs a real 0.9 s loop and requires 250 Hz ±25 (`tests/test_detectors.py:1010-1023`); loaded CI runners or Windows timer behavior can make this flaky.
4. **Exact default values are baked into tests and docs.** Tests load the checked-in `skills_config.json` and assert Chinese skill names and parameter values; adding/renaming a skill or tuning a default can require broad test edits. The doc/test counts are already stale (127 vs 182).
5. **No coverage measurement.** There is no `coverage.py`/`pytest-cov` config, no CI artifact, and no report of which modules are exercised. The gaps above are inferred from inspection; there is no quantitative baseline.
6. **Builds do not gate on tests.** `build/build_windows.ps1` and `build/build_macos.sh` run `uv sync --extra build` and PyInstaller only; a broken test or config can be packaged.

**Recommended minimum:** add a pytest-compatible wrapper (or convert the custom checks to assertions), a `dev` dependency group (`pytest`, `pytest-cov`, `ruff`), a GitHub Actions matrix for Windows/macOS (Python 3.11–3.13), a test step in both build scripts, and a small hardware-independent fixture set for SDL mapping strings and rumble backends.

---

*Concerns audit: 2026-11-04*
