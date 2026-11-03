---
last_mapped_commit: 5e489a15e4c8cbbfdedcb5239242264ab5394e66
last_mapped_at: 2026-11-04
---
# Codebase Structure

**Analysis Date:** 2026-11-04

## Directory Layout

```
fifa-trainer/
├── app.py                     # GUI + PyInstaller entry point (56 lines)
├── main.py                    # CLI entry: flags, startup flow, selftest (324 lines)
├── pyproject.toml             # uv project metadata; pygame-ce dep; optional xinput/build extras
├── uv.lock                    # uv lockfile (committed)
├── skills_config.json         # Runtime skill rules (generated from config.DEFAULT_CONFIG)
├── FIFA-Skill-Trainer.spec    # PyInstaller spec, entry = app.py
├── README.md                  # User manual + tuning guide + project notes (Chinese)
├── .gitattributes
├── .gitignore
├── padskills/                 # Application package (8 modules, ~4,700 lines)
│   ├── __init__.py            # Package docstring + __version__ = "1.0.0"
│   ├── geometry.py            # Angle convention and vector helpers (54)
│   ├── config.py              # Config parsing/validation/defaults + paths (790)
│   ├── input_source.py        # Gamepad polling + SDL-mapping layout inference (642)
│   ├── rumble.py              # Rumble backends + non-blocking state machine (344)
│   ├── detectors.py           # Arc / sequence / tap recognizers + failure codes (1,046)
│   ├── engine.py              # 250 Hz engine loop, arbitration, stats, debug output (508)
│   └── gui.py                 # pygame desktop app, demo source, diagnostic log (1,308)
├── tests/                     # Standalone test scripts (no pytest)
│   ├── test_detectors.py      # Synthetic trajectories, engine, rumble, config tests (1,480)
│   └── test_gui_smoke.py      # Dummy-video-driver GUI smoke tests (466)
├── build/                     # Packaging scripts only (other artifacts gitignored)
│   ├── build_macos.sh         # uv sync --extra build + pyinstaller → .app
│   └── build_windows.ps1      # Windows .exe build
└── .planning/codebase/        # GSD analysis documents (this file lives here)
```

## Directory Purposes

**Repository root:**
- Purpose: Entry scripts, configuration file users edit, packaging metadata, documentation.
- Contains: `app.py`, `main.py`, `skills_config.json`, `pyproject.toml`, `uv.lock`, PyInstaller spec, README.
- Key files: `skills_config.json` (all behavior tuning), `app.py` (packaged entry), `main.py` (CLI/diagnostics).

**`padskills/`:**
- Purpose: Entire application implementation; no other Python package exists.
- Contains: domain model/config, geometry, input adapters, rumble adapters, detectors, orchestration, GUI.
- Key files: `engine.py` (central loop), `detectors.py` (recognition algorithms), `gui.py` (desktop app), `config.py` (schema + defaults).

**`tests/`:**
- Purpose: Self-contained test executables runnable with `uv run tests/<file>.py`; also importable by pytest if desired.
- Contains: custom `check()` harness, synthetic frame builders, scripted sources/backends, end-to-end engine and GUI tests.
- Key files: `test_detectors.py`, `test_gui_smoke.py`.

**`build/`:**
- Purpose: Platform packaging invocations. Only scripts are committed (`.gitignore`: `build/*` with two negations).
- Contains: `build_macos.sh`, `build_windows.ps1`.
- Key files: `build/build_macos.sh` (also documents Gatekeeper workaround), `build/build_windows.ps1`.

**`.planning/codebase/`:**
- Purpose: GSD-generated codebase maps consumed by later planning/execution commands.
- Contains: this structure map and `ARCHITECTURE.md`.
- Generated: Yes, by GSD mapping. Committed: repository-dependent (not gitignored).

## Key File Locations

**Entry Points:**
- `app.py`: GUI-only launcher; PyInstaller target (`FIFA-Skill-Trainer.spec` `Analysis(['app.py'])`).
- `main.py`: CLI parser and dispatch; `--gui/--demo` forward to `padskills.gui.main_gui`.
- `padskills/gui.py:1279`: `main_gui()` — pygame subsystem init and window creation.
- `padskills/gui.py:386`: `TrainerApp.run()` — config/device/play state machine.
- `padskills/engine.py:154`: `Engine.run()` — the real-time loop.
- `padskills/config.py:785`: `dump_default_config()` — regenerates `skills_config.json`.

**Configuration:**
- `skills_config.json`: active ruleset (`_readme`, `input`, `rumble`, `global_cooldown_ms`, `skills`).
- `padskills/config.py:250`: `DEFAULT_CONFIG` — single source of truth for defaults and `--write-config`.
- `padskills/config.py:84`: `DIRECTION_ALIASES` — English/Chinese direction names → degrees.
- `padskills/config.py:46-64`: per-OS config directory resolution (`APPDATA`, Application Support, XDG).
- `padskills/input_source.py:296-304`: fallback XInput button/DPAD index tables.
- `pyproject.toml`: dependency + extras (`xinput`, `build`) and Python ≥3.11.

**Core Logic:**
- `padskills/geometry.py`: angle convention (0° up, clockwise), `signed_delta`, `angle_of`.
- `padskills/detectors.py:125` / `:453` / `:858`: arc, sequence, taps recognizers.
- `padskills/detectors.py:1039`: `build_detector()` kind → class factory.
- `padskills/engine.py:198`: `Engine._tick()` — facing, lock, modifier filter, detection, cooldowns, failure drain.
- `padskills/engine.py:320` / `:332`: `_discard_other_claims`, `_drain_failures` — single-verdict arbitration.
- `padskills/input_source.py:484`: `PygameJoystickSource.poll()`.
- `padskills/input_source.py:214` / `:258`: SDL-mapping layout vs rest-value fallback.
- `padskills/rumble.py:274` / `:298`: `RumbleEngine.play()` / `update()`.
- `padskills/rumble.py:175`: `build_backends()` ordered fallback list.

**Testing:**
- `tests/test_detectors.py`: recognizer/engine/rumble/config coverage; helpers at `:46-190` (`stick`, `make_frame`, `rotate`, `flick`, `held`, `variant`, `tap_frames`, `run_detector`).
- `tests/test_gui_smoke.py`: forces `SDL_VIDEODRIVER=dummy` and `SDL_AUDIODRIVER=dummy` (`:17-19`); demo end-to-end, drawing, hotkeys, history, modifier switching, diagnostic log.

## Naming Conventions

**Files:**
- Package modules: lowercase `snake_case.py`, one concern per module (`input_source.py`, `detectors.py`).
- Entry scripts: short lowercase (`app.py`, `main.py`).
- Tests: `test_<area>.py` under `tests/` (not co-located).
- Build scripts: `build_<platform>.<ext>` under `build/`.

**Directories:**
- Single application package `padskills/` (no `src/` layout); tests and build scripts at repo root level.

**Classes:**
- `PascalCase`; adapters end with their role (`PygameJoystickSource`, `DemoSource`, `PygameJoystickRumble`, `SDL2ControllerRumble`, `XInputRumble`).
- Recognizers end in `Detector` (`ArcDetector`, `SequenceDetector`, `TapDetector`).
- Dataclasses are noun-like (`PadState`, `AxisLayout`, `Frame`, `Hit`, `Failure`, `Outcome`, `ActiveSkill`, `Skill`, `Step`, `Pulse`, `AppConfig`, `InputConfig`, `RumbleConfig`).

**Functions/methods:**
- `snake_case`; private helpers prefixed `_` (`_tick`, `_drain_failures`, `_draw_skills`, `_parse_skill`, `_layout_from_mapping`).
- Constructor-time parsing helpers use `_parse_*`; inference helpers use `_*_from_*` (`_layout_from_mapping`, `_layout_from_rest`).
- Factories/entry verbs: `build_detector`, `build_backends`, `open_source`, `load_config`, `main_gui`.

**Variables/constants:**
- Module constants `UPPER_SNAKE_CASE` (`DEFAULT_CONFIG`, `CANONICAL_BUTTONS`, `BUTTON_ALIASES`, `GROUP_SIZE`, `IDLE_STICK`, `RELEASE_STICK`, `W`, `H`, `FPS`, color names).
- Runtime state `snake_case`; timing values carry unit suffixes (`_ms`, `_hz`, `_deg`, `_mag`).

**Configuration keys:**
- `snake_case` with unit suffixes in JSON: `poll_hz`, `deadzone`, `ls_facing_threshold`, `min_duration_ms`, `max_angle`, `start_tolerance`, `tolerance_deg`, `hold_ms`, `duration_ms`.
- Skill `type` values are lowercase: `"arc"`, `"sequence"`, `"taps"`.
- Buttons canonical form is uppercase Xbox naming (`A/B/X/Y`, `LB/RB/LT/RT`, `LS/RS`, `BACK/START/GUIDE`, `DPAD_*`); aliases normalized via `canonical_button()`.

**Language:**
- Code identifiers and all config keys are English; docstrings, comments, user-facing strings, and docs are Simplified Chinese. Preserve this split when adding code.

## Where to Add New Code

**New Skill (most common):**
- Primary: `skills_config.json` → append an object under `"skills"` (`name` unique, `type`, `relative_to_ls`, optional `required_button`/`button_mode`, `params`, `rumble`, `cooldown_ms`).
- To change built-in defaults: also edit `DEFAULT_CONFIG["skills"]` in `padskills/config.py:347-462`.
- Tests: add a case in `tests/test_detectors.py` (build frames with `rotate`/`flick`/`held` helpers, run via `run_detector` or `Engine`).

**New Detection Algorithm (new `type`):**
- Implementation: subclass `Detector` in `padskills/detectors.py`, implement `update()`, `reset()`, `on_idle()` (if the gesture is stick-based), `abandon()`, `status()`; emit failures via `self._emit(Failure(...))`.
- Registration: extend `build_detector()` at `padskills/detectors.py:1039` and the allowed-kind check in `_parse_skill` at `padskills/config.py:541`.
- Validation: add kind-specific checks in `_parse_skill` (`padskills/config.py:551-634`) and document params in `DEFAULT_CONFIG["_readme"]`.
- Tests: `tests/test_detectors.py` (unit via `run_detector`, integration via `Engine`).

**New Input Backend:**
- Implementation: subclass `GamepadSource` in `padskills/input_source.py` (implement `poll()`/`close()`); set `name` and `layout_source`.
- Wiring: `open_source()` at `padskills/input_source.py:632`.
- Test double precedent: `DemoSource` in `padskills/gui.py:232`, `NullSource`/`ScriptedSource` in `tests/test_detectors.py:646`, `:966`.

**New Rumble Backend:**
- Implementation: subclass `RumbleBackend` in `padskills/rumble.py` (`start()` must return immediately; `stop()` clears).
- Wiring: add to `build_backends()` at `padskills/rumble.py:175` and align with the `RumbleConfig.backend` allow-list in `padskills/config.py:717`.
- Tests: reuse `RecordingBackend`/`TimelineBackend` patterns in `tests/test_detectors.py:955`, `:1026`.

**New GUI Panel / Widget:**
- Implementation: add a `_draw_<panel>()` method on `TrainerApp` in `padskills/gui.py`, using `_panel`, `_text`, `_mark`, `_fit`, `_wrap` helpers.
- Wiring: call it from `TrainerApp._draw()` at `padskills/gui.py:781-800` (respect the `config_error` / `opening` / `engine is None` branches).
- Clickable areas: append `(rect, payload, value)` to `self._modifier_hits`-style lists and handle in `_on_click()` (`padskills/gui.py:704`).
- Dimensions: layout constants `W`, `H`, `FPS` and panel rects are hard-coded in `padskills/gui.py:37-51` and each `_draw_*`.

**New CLI Flag / Subcommand:**
- Implementation: add `parser.add_argument` in `main.py:198-234`, handle in `main()` before the GUI short-circuit or add a `cmd_*()` helper alongside `cmd_list`/`cmd_selftest` (`main.py:86-178`).

**New Config Field (global):**
- Implementation: add to the relevant dataclass (`InputConfig`/`RumbleConfig`/`AppConfig` in `padskills/config.py:207-243`), parse it in `_parse_input`/`_parse_rumble`/`parse_config` (`:667-753`), add to `DEFAULT_CONFIG`, and document in `_readme`.

**Utilities:**
- Angle/vector math: `padskills/geometry.py` (keep the 0°=up convention; convert raw SDL coordinates only here).
- Button name normalization: `canonical_button()` in `padskills/input_source.py:63`.
- Direction name/angle conversion: `resolve_direction` / `direction_name` in `padskills/config.py:104`, `:125`.

## Special Directories

**`build/`:**
- Purpose: Packaging scripts; the directory is otherwise excluded by `.gitignore` (`build/*` plus whitelist for the two scripts).
- Generated: Partially (PyInstaller intermediates land elsewhere: `dist/`, build cache).
- Committed: Only `build_macos.sh` and `build_windows.ps1`.

**`.planning/`:**
- Purpose: GSD workflow state and generated codebase documentation.
- Generated: Yes (by GSD commands).
- Committed: Not ignored by `.gitignore`; commit policy is up to the repository owner.

**`__pycache__/`, `.venv/`, `.pytest_cache/`:**
- Purpose: Tool caches.
- Generated: Yes.
- Committed: No (ignored).

**`dist/`:**
- Purpose: PyInstaller output (`.app` / `.exe`).
- Generated: Yes.
- Committed: No (ignored).

## Module Dependency Direction

```
geometry  ←  config  ←  input_source
    ↑           ↑            ↑
    └──── detectors ─────────┘
                 ↑
               engine  ←  rumble (← config)
                 ↑
                 gui
```

- `geometry` has no project imports (stdlib `math` only).
- `config` imports only `geometry`; it lazily imports `input_source.canonical_button` inside functions to avoid a cycle.
- `detectors` imports `config`, `geometry`, `input_source`.
- `engine` imports `config`, `detectors`, `input_source`, `rumble`.
- `gui` imports all of the above; `main.py`/`app.py` import `padskills` and lazily import `padskills.gui` only on GUI paths.
- Keep this direction: do not make `config`/`geometry` depend on `engine`/`gui`, and do not make detectors import `pygame`.

---

*Structure analysis: 2026-11-04*
