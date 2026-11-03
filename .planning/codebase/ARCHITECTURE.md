---
last_mapped_commit: 5e489a15e4c8cbbfdedcb5239242264ab5394e66
last_mapped_at: 2026-11-04
---
<!-- refreshed: 2026-11-04 -->

# Architecture

**Analysis Date:** 2026-11-04

## System Overview

```text
┌──────────────────────────────────────────────────────────────────────────┐
│                     Entry / Composition Layer                            │
│  `app.py` (GUI + PyInstaller entry)   `main.py` (CLI, flags, selftest)   │
│  `padskills/gui.py:main_gui()`        `FIFA-Skill-Trainer.spec`          │
└───────────────────────────────┬──────────────────────────────────────────┘
                                │ load_config() / open_source() / build_backends()
                                ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                 Orchestration — `padskills/engine.py`                    │
│  Engine.run(): fixed-rate loop (default 250 Hz), absolute timeline       │
│  Engine._tick(): facing → gesture lock → modifier filter → detect →      │
│                  cooldown → record Outcome → rumble.play() → drain fails │
│  Shared in-process state: ActiveSkill stats, last_outcome, outcome_seq   │
└───────┬─────────────────────┬──────────────────────┬─────────────────────┘
        │ Frame               │ Hit / Failure        │ Pulse + now
        ▼                     ▼                      ▼
┌───────────────────┐  ┌────────────────────┐  ┌─────────────────────────┐
│ Detection Layer   │  │ Result Vocabulary  │  │ Actuation Layer         │
│ `detectors.py`    │  │ Outcome / Hit /    │  │ `rumble.py`             │
│ ArcDetector       │  │ Failure / Frame    │  │ RumbleEngine (state     │
│ SequenceDetector  │  │ (engine + detectors│  │ machine, non-blocking)  │
│ TapDetector       │  │  dataclasses)      │  │ RumbleBackend adapters  │
└─────────┬─────────┘  └────────────────────┘  └────────────┬────────────┘
          │ Skill/Step/angle helpers                        │ low/high/ms
          ▼                                                 ▼
┌───────────────────────────────────┐  ┌──────────────────────────────────┐
│ Domain Model — `config.py`,        │  │ Input Adapters —                 │
│ `geometry.py`                      │  │ `input_source.py`                │
│ AppConfig / Skill / Step / Pulse   │  │ GamepadSource → PygameJoystick-  │
│ direction aliases, validation      │  │ Source / DemoSource; PadState    │
└───────────────────────────────────┘  └──────────────────────────────────┘
```

## Component Responsibilities

| Component | Responsibility | File |
|-----------|----------------|------|
| `main()` CLI | Parse flags, dispatch GUI vs CLI, run selftest/list/write-config, build engine | `main.py:198` |
| `main_gui()` | Initialize only `display`/`font`/`joystick` pygame subsystems, create window, run `TrainerApp` | `padskills/gui.py:1279` |
| `TrainerApp` | Window state machine (config error / connecting / no device / play), input events, 60 fps drawing, diagnostic log | `padskills/gui.py:313` |
| `Engine` | Fixed-rate polling loop, facing tracking, gesture arbitration, cooldowns, stats, `Outcome` emission, debug/trace rendering | `padskills/engine.py:92` |
| `Detector` + subclasses | Stateful per-skill gesture recognition and failure diagnosis | `padskills/detectors.py:61`, `:125`, `:453`, `:858` |
| `build_detector()` | Config `type` → concrete detector factory | `padskills/detectors.py:1039` |
| `load_config()` / `parse_config()` | JSON → validated `AppConfig`; default config generation | `padskills/config.py:756`, `:729`, `:535` |
| `resolve_direction()` / `parse_step()` | Direction-name/angle resolution and sequence-step normalization | `padskills/config.py:104`, `:147` |
| `geometry` | Single source of angle convention, shortest-arc math, magnitude | `padskills/geometry.py` |
| `PygameJoystickSource` | `pygame.event.pump()` + axis/button/hat reads → `PadState`; SDL mapping-table or rest-value layout inference | `padskills/input_source.py:357`, `poll` at `:484` |
| `DemoSource` | Scripted `PadState` generator for GUI demo/tests (implements `GamepadSource`) | `padskills/gui.py:232` |
| `RumbleEngine` | Single-pulse, non-blocking rumble state machine driven each tick | `padskills/rumble.py:242`, `play` `:274`, `update` `:298` |
| `build_backends()` / `pick_backend()` | Ordered backend candidates and startup probe | `padskills/rumble.py:175`, `:210` |
| `AxisLayout` / `PadState` | Input layout metadata and immutable per-frame snapshot | `padskills/input_source.py:116`, `:81` |

## Pattern Overview

**Overall:** Layered, data-driven, single-threaded polling pipeline ("ports & adapters lite").

**Key Characteristics:**
- **One thread owns everything.** No threads, locks, queues, or async anywhere in `padskills/` (verified: no `threading`/`asyncio` imports). SDL joystick calls, display, events, rumble, and detection all run inside `Engine.run()` on the main thread. Rationale is documented at `padskills/gui.py:3-9` and `padskills/rumble.py:242-257`.
- **Push samples, poll outcomes.** The engine pushes a `Frame` into every detector each tick; detectors publish at most one success (`Hit`, returned synchronously) and at most one failure (`Failure`, stored in a single `_pending` slot and drained by `_drain_failures`).
- **Adapters via narrow interfaces.** `GamepadSource` (`padskills/input_source.py:341`) and `RumbleBackend` (`padskills/rumble.py:30`) isolate platform/device concerns. `DemoSource` proves the input port is swappable.
- **Config is the extension point.** All skill rules live in `skills_config.json` / `config.DEFAULT_CONFIG`; adding a move does not require Python changes (`padskills/config.py:250-463`).
- **Arbitration beats competition.** A gesture lock plus `_discard_other_claims()` ensures one physical motion can only score one skill (`padskills/engine.py:217-233`, `:320-331`).

## Layers

**Entry / composition:**
- Purpose: Parse arguments, choose GUI or CLI, initialize pygame subsystems, load config, open device and rumble, hand a fully wired `Engine` to a runner.
- Location: `app.py`, `main.py`, `padskills/gui.py:main_gui`
- Contains: CLI subcommands (`--gui`, `--demo`, `--debug`, `--trace`, `--selftest`, `--list`, `--write-config`, `--duration`), window creation, packaging bootstrap.
- Depends on: all of `padskills`.
- Used by: OS / PyInstaller (`FIFA-Skill-Trainer.spec` targets `app.py`).

**Orchestration (`Engine`):**
- Purpose: Own the sample clock, build `Frame`s, enforce facing/modifier/idle/lock rules, invoke detectors, apply cooldowns, record results, drive rumble, emit debug output.
- Location: `padskills/engine.py`
- Contains: `Engine.run()` (`:154`), `Engine._tick()` (`:198`), arbitration helpers (`:320`, `:332`), `Outcome`/`ActiveSkill` dataclasses (`:63`, `:79`), `summary()` (`:477`).
- Depends on: `config`, `detectors`, `input_source`, `rumble`.
- Used by: `main.py` (CLI) and `TrainerApp._play()` (GUI).

**Detection:**
- Purpose: Per-skill state machines converting stick/button history into `Hit` or `Failure`.
- Location: `padskills/detectors.py`
- Contains: `Detector` base contract (`:61`), `ArcDetector` (`:125`), `SequenceDetector` (`:453`), `TapDetector` (`:858`), `Frame`/`Hit`/`Failure` (`:28`, `:41`, `:50`).
- Depends on: `config.Skill/Step/parse_step/resolve_direction`, `geometry`, `input_source.canonical_button`/`PadState`.
- Used by: `Engine` (one instance per enabled skill, created in `Engine.__init__` at `engine.py:113-116`).

**Domain model:**
- Purpose: Represent configuration, validated rules, vibration patterns, and the project-wide angle convention.
- Location: `padskills/config.py`, `padskills/geometry.py`
- Contains: `Pulse`, `Step`, `Skill`, `InputConfig`, `RumbleConfig`, `AppConfig`; `DEFAULT_CONFIG`; direction aliases; path resolution (`app_dir`, `user_config_dir`, `default_config_path`, `ensure_user_config`).
- Depends on: stdlib only (`json`, `pathlib`, `dataclasses`) plus `geometry`.
- Used by: every other module.

**Input adapters:**
- Purpose: Produce immutable `PadState` snapshots and calibrate/derive device layout.
- Location: `padskills/input_source.py`
- Contains: `PadState` (`:81`), `AxisLayout` (`:116`), `PygameJoystickSource` (`:357`), `DemoSource` (`gui.py:232`), `canonical_button` (`:63`), `list_devices` (`:609`), `open_source` (`:632`).
- Depends on: `pygame`/`pygame._sdl2.controller` (lazy imports), `geometry`.
- Used by: `Engine`, `main.py` (`--list`, `--selftest`), `TrainerApp`.

**Actuation adapters:**
- Purpose: Deliver non-blocking rumble through the best available backend.
- Location: `padskills/rumble.py`
- Contains: `RumbleBackend`, `PygameJoystickRumble`, `SDL2ControllerRumble`, `XInputRumble`, `XInputPyRumble`, `RumbleEngine`, backend selection helpers.
- Depends on: `config.Pulse`, `pygame` indirectly (joystick object injected), `ctypes` on Windows.
- Used by: `Engine._tick`/`Engine.run` (`rumble.update`, `rumble.play`, `rumble.close`).

**Presentation (`TrainerApp`):**
- Purpose: Render state read from `Engine` and `PadState`, handle hotkeys/click, hot-plug retry, write diagnostic log.
- Location: `padskills/gui.py`
- Contains: `TrainerApp` (`:313`), font discovery (`:72`), demo script (`:190`), drawing helpers and panels (`:781-1272`), `main_gui` (`:1279`).
- Depends on: `engine`, `detectors`, `config`, `input_source`, `rumble`, `pygame`.
- Used by: `app.py`, `main.py --gui/--demo`.

## Data Flow

### Primary Request Path — Real-time input → detect → rumble (GUI)

1. **Bootstrap:** `app.py:main()` → `padskills.gui.main_gui()` (`gui.py:1279`) sets `SDL_VIDEO_CENTERED`, calls only `pygame.display.init()`, `pygame.font.init()`, `pygame.joystick.init()`, creates the 900×620 `SCALED | RESIZABLE` surface (`gui.py:1288-1301`).
2. **Config load:** `TrainerApp.__init__` → `_load_config()` → `load_config()` (`config.py:756`); frozen builds first `ensure_user_config()` into the per-OS user dir (`config.py:67-77`). Errors are stored in `self.config_error` and drawn (`gui.py:1256`).
3. **Device + rumble open:** `TrainerApp.run()` (`gui.py:386`) → `_open_device()` (`gui.py:540`) → `open_source()` (`input_source.py:632`) constructs `PygameJoystickSource`: 250 ms rest sampling (`_sample_rest`, `:408`), layout from SDL mapping table (`_layout_from_mapping`, `:214`) or rest-value classification (`_layout_from_rest`, `:258`), then config `input.invert` overrides (`apply_axis_inverts`, `:313`). `_build_rumble()` (`gui.py:278`) builds candidates and probe-fires one.
4. **Engine construction:** `Engine(cfg, source, rumble, feedback=True, out=_Sink())` (`gui.py:556`); `Engine.__init__` snapshots `cfg.enabled_skills()` into `ActiveSkill` objects and one detector each (`engine.py:113-116`).
5. **Sample loop:** `TrainerApp._play()` → `engine.run(on_tick=self._on_tick)` (`gui.py:584`). `Engine.run()` (`engine.py:154-192`) computes `period = 1 / cfg.input.poll_hz`, then per iteration:
   - `state = self.source.poll()` → `pygame.event.pump()`, raw axes, deadzone rescale, trigger normalization, buttons/hats mapped to canonical names (`input_source.py:484-537`).
   - `self._tick(now, state)`.
   - optional `_render_debug`, then `on_tick(now, state)`.
   - absolute deadline accounting: `next_tick += period`; if behind, count `overruns` and re-align instead of sleeping the deficit (`engine.py:179-186`).
6. **Per-frame arbitration** (`engine.py:198-318`):
   - Facing: `ls_mag >= cfg.input.ls_facing_threshold` sets `facing_valid` and updates `facing = state.ls_angle`; centering invalidates facing rather than remembering the last direction (`:201-204`).
   - Build `Frame` with `now`, stick angles/mags, frozen facing, buttons (`:206-215`).
   - Gesture lock: while locked, wait for `rs_mag < RELEASE_STICK` sustained for `input.gesture_release_ms`, then `on_idle()` all detectors and unlock (`:219-233`).
   - `held_required` = union of required buttons currently held (`:237-242`).
   - Idle reset: right stick below `IDLE_STICK` for `input.idle_reset_ms` → `on_idle()` all detectors (`:245-255`).
   - For each `ActiveSkill`, in config order:
     - Holding another skill's modifier → `observe()` + `abandon()` (silent discard) (`:260-265`).
     - `relative_to_ls` without left-stick facing → `observe()` + `reset()` (`:268-271`).
     - Own modifier not satisfied → `observe()` + `reset()` (keeps UI hint) (`:273-279`).
     - Otherwise `hit = detector.update(frame)`.
   - On `Hit`: `_discard_other_claims()` (`:287`, `:320`), per-skill cooldown, global cooldown (increments `suppressed`), update stats/group counters, `_record()` an `Outcome`, `_fire()` → `rumble.play(skill.pattern, now)` + log, then set gesture lock and `break` (`:289-311`).
   - `_drain_failures(now)`: at most one failure per gesture (first in config order wins), recorded as an `Outcome`; then discard other detectors' progress (`:332-353`).
   - `rumble.update(now)`: stop motors when deadline reached (`:318`; `rumble.py:298-304`).
7. **Presentation tick (same thread):** `TrainerApp._on_tick()` (`gui.py:593`) processes pygame events, detects new `engine.outcome_seq` and appends `(timestamp, Outcome)` to a 50-entry history + diag log, writes RS diagnostics at ~22 Hz, stores `self.state`, and throttles drawing by timestamp to 60 fps (`:618-621`) before `_draw()`.
8. **Shutdown:** QUIT/Esc/Q sets `_running=False` and calls `engine.stop()` (`gui.py:657-681`). `Engine.run` exits its `while self._running`, then in `finally` clears debug line and calls `rumble.close()` + `source.close()` (`engine.py:189-192`).

### Secondary Flow — CLI run

1. `main.py:main()` parses args; GUI flags short-circuit to `main_gui` (`main.py:244-246`).
2. `load_config` + optional `--index`/`--no-rumble` overrides (`main.py:252-256`).
3. `--selftest` builds backends and plays blocking test pulses (`main.py:260-262`, `:104-178`) — the only intentional blocking rumble path.
4. Otherwise init `pygame.display` + `pygame.joystick`, open source, choose/pick backend (`main.py:264-302`), construct `Engine`, call `engine.run(duration=...)` (no `on_tick`), print `engine.summary()` (`main.py:316-319`).

### Secondary Flow — Demo mode (no gamepad)

`--demo` → `TrainerApp` with `demo=True` → `_open_device` uses `DemoSource` and disabled rumble (`gui.py:548-551`). `DemoSource.poll()` maps a looping script of `_Segment`s (5 successes + 4 typical failures) onto `PadState` by wall-clock time (`gui.py:190-265`). It exercises the full engine/detector/GUI chain in tests.

### Secondary Flow — Config reload / modifier switch

- GUI config errors: press `R` in `mode="config"` → `_load_config()` (`gui.py:691-692`).
- Modifier chip click: `_choose_modifier()` mutates `skill.required_buttons` + `skill.raw`, calls `TapDetector.set_modifier()` if applicable, and rewrites only that skill's `required_button` via regex segment patching (`gui.py:710-754`) — no full-file rewrite, preserving hand-edited comments from the user's perspective.

**State Management:**
- All runtime state is in-process mutable objects on the single main thread. There is no serialization, IPC, DB, or cache.
- `Engine` is the single writer of detection stats (`ActiveSkill.hits/attempts/failures/group_hits/groups_done`, `last_outcome`) and exposes `outcome_seq` as a monotonic change token for the GUI (`engine.py:146-148`, `:363`; GUI reads at `gui.py:600`).
- `PadState` is frozen; `Outcome`, `Hit`, `Failure` are per-event values. `Skill`/`AppConfig` are mutable but only the modifier-switch path mutates them at runtime.
- `RumbleEngine` owns `_active`/`_deadline`, advanced only by `play()` and `update()` with the engine's `perf_counter` timestamps (`rumble.py:274-304`).

## Key Abstractions

**`GamepadSource` (input port):**
- Purpose: Hide device acquisition/protocol; produce `PadState`.
- Examples: `PygameJoystickSource` (`input_source.py:357`), `DemoSource` (`gui.py:232`), test doubles `NullSource`/`ScriptedSource` (`tests/test_detectors.py:646`, `:966`).
- Pattern: Template/interface with `poll()` / `close()` / `describe()`; layout inference strategy inside the pygame implementation.

**`RumbleBackend` (actuation port):**
- Purpose: Normalize pygame / SDL2 / XInput / XInput-Python rumble APIs.
- Examples: `rumble.py:48`, `:68`, `:85`, `:144`; test double `RecordingBackend` (`tests/test_detectors.py:955`).
- Pattern: Adapter + ordered fallback list; `RumbleEngine` composes one backend and owns timing.

**`Detector` (strategy per skill kind):**
- Purpose: Encapsulate recognition FSM and failure classification.
- Examples: `ArcDetector`, `SequenceDetector`, `TapDetector`.
- Pattern: Strategy chosen by `build_detector(skill)`; shared lifecycle contract `update` / `reset` / `on_idle` / `abandon` / `observe` / `pop_failure` / `status` (`detectors.py:78-118`).

**`Frame` / `Hit` / `Failure` / `Outcome`:**
- Purpose: Stable boundary values between engine, detectors, and UI.
- Pattern: Frozen or plain dataclasses; `Failure` is buffered in a one-slot `_pending` so exactly one verdict per attempt reaches the engine.

**`Skill` / `Step` / `Pulse` / `AppConfig`:**
- Purpose: Immutable-ish declarative rules consumed by detectors/rumble.
- Examples: `config.py:133-243`; defaults `config.py:250-463`.
- Pattern: Parse-then-validate at load time; unknown/extra params remain in `Skill.params`/`Skill.raw` (open schema, no rigid dataclass per kind).

**`ActiveSkill`:**
- Purpose: Pair one `Skill` with one live detector and per-skill counters/cooldowns.
- Location: `engine.py:79-89`.

## Entry Points

**GUI / packaged app:**
- Location: `app.py:48` (`main`), used by `FIFA-Skill-Trainer.spec` and `build/build_macos.sh` / `build/build_windows.ps1`.
- Triggers: double-click, `uv run app.py`, `uv run main.py --gui`, `uv run main.py --demo`.
- Responsibilities: window init, config load, device retry loop, events, rendering.

**CLI:**
- Location: `main.py:198`.
- Triggers: `uv run main.py [flags]`.
- Responsibilities: diagnostics (`--list`, `--debug`, `--trace`, `--selftest`, `--verbose`, `--feedback`), headless monitoring, default config generation.

**Engine loop:**
- Location: `Engine.run()` — `padskills/engine.py:154`.
- Triggers: `TrainerApp._play()` or `main()`.
- Responsibilities: sampling cadence, detection, arbitration, rumble state advance, stats.

**Config generator:**
- Location: `dump_default_config()` — `padskills/config.py:785`; CLI `--write-config` (`main.py:236-239`).

## Architectural Constraints

- **Threading:** Strictly single-threaded. Ban on background rumble/polling threads is deliberate: SDL's joystick subsystem is thread-affine, and concurrent `pygame.event.pump()` + `SDL_JoystickRumble` caused dropped vibrations (`README.md` §十, `padskills/rumble.py:242-257`). `RumbleEngine.start()` is now a no-op kept for API compatibility (`rumble.py:271-272`).
- **No blocking in the hot loop:** `on_tick` must return immediately (`engine.py:156-157`); `play()` never sleeps; only startup probes/`--selftest` block (`rumble.py:224`, `main.py:113`).
- **Global state:** No module-level mutable singletons except the constant `DEFAULT_CONFIG` dict (`config.py:250`) and lookup tables (`DIRECTION_ALIASES`, `BUTTON_ALIASES`, `_SDL_*` maps). All mutable state lives on `Engine`, `ActiveSkill`, detectors, `TrainerApp`, or `RumbleEngine` instances.
- **Circular imports:** Avoided by lazy imports — `config._parse_required_buttons`/`_parse_skill` import `input_source.canonical_button` inside functions (`config.py:510`, `:606`); `pygame` is imported lazily in most modules. Import DAG: `geometry` ← `config` ← `detectors` ← `engine` ← `gui`; `input_source` ← `config`/`detectors`/`engine`; `rumble` ← `config`/`engine`.
- **Sampling assumptions:** Detectors assume uniform ~250 Hz frames. Motion detection compares against a reference angle several frames back (`motion_min_delta_deg`) rather than adjacent frames (`detectors.py:308-314`, `:508-510`).
- **Angle convention:** 0° = up/forward, 90° = right, clockwise positive; SDL's y-down coordinates are converted once in `geometry.angle_of()` (`geometry.py:41-49`). All other code uses only the project convention.
- **Facing semantics:** `relative_to_ls` skills are invalid unless the left stick is currently beyond `ls_facing_threshold`; the base angle is frozen at gesture start (`detectors.py:286`, `:697`).
- **UI/engine coupling:** GUI reads engine internals directly (same thread) rather than receiving copies; the only explicit change signal is `outcome_seq`.
- **Packaging:** Windowed builds have `sys.stdout/stderr = None`; `app.py:21-24` and `main.py:25-28` patch these before importing pygame, and GUI passes `_Sink()` as `Engine.out` (`gui.py:268`, `:557`).

## Anti-Patterns

### Background thread for rumble/SDL calls

**What happens:** Offloading `Joystick.rumble()` or `event.pump()` to a worker thread to "avoid blocking".
**Why it's wrong:** SDL joystick calls must occur on the initializing thread; the prior implementation produced intermittent/no vibration (`README.md` §十; `rumble.py:242-257`).
**Do this instead:** Emit one pulse in `RumbleEngine.play(pattern, now)` and stop it in `RumbleEngine.update(now)` from `Engine._tick` (`engine.py:318`, `:396`).

### Queueing rumble pulses

**What happens:** Appending triggered patterns to a playback queue.
**Why it's wrong:** Nearby triggers concatenate into one long/continuous vibration (documented regression, `rumble.py:250-253`).
**Do this instead:** Single-pulse state machine; drop a new trigger while `_active` is true (`rumble.py:285-296`), and rely on gesture lock + cooldowns to space triggers (`engine.py:289-293`).

### Sleeping inside the sample loop or `on_tick`

**What happens:** `time.sleep()` or blocking I/O in the tick callback/render path.
**Why it's wrong:** It steals time from the 250 Hz detector loop and inflates `overruns` (`engine.py:179-186`).
**Do this instead:** Timestamp-based throttling, as in `TrainerApp._on_tick` (`gui.py:618-620`); let `Engine.run` own the only sleep (`engine.py:180-182`).

### Calling `pygame.init()`

**What happens:** One-shot full pygame initialization.
**Why it's wrong:** It also initializes audio, a frequent failure source in packaged builds (`gui.py:9`, `main.py:265-267`).
**Do this instead:** Initialize only `display`, `font`, `joystick` as needed (`gui.py:1288-1290`).

### Treating `reset()` and `abandon()` as interchangeable

**What happens:** Using `reset()` when a gesture belonged to another skill.
**Why it's wrong:** `reset()` re-arms immediately (modifier released case); `abandon()` keeps the detector disarmed until the stick centers, preventing half-progress from being re-claimed (`detectors.py:81-95`, `engine.py:260-265`, `:320-331`).
**Do this instead:** Use `abandon()` on arbitration loss/branch mismatch; use `reset()` only for locally invalid conditions (modifier/facing) where retry is legitimate.

### Reporting failure from multiple detectors for one motion

**What happens:** Letting every detector emit a failure for the same gesture.
**Why it's wrong:** The UI/summary would show several contradictory verdicts for one attempt.
**Do this instead:** One-slot `_pending` per detector plus `_drain_failures()` first-wins policy, followed by `_discard_other_claims(owner)` (`engine.py:332-353`).

### Hard-coding axis/button indices

**What happens:** Assuming XInput index order (e.g. triggers at axes 0/1).
**Why it's wrong:** The measured device's triggers sit at axes 4/5 with rest value −1.0 (`README.md` §十).
**Do this instead:** Derive from SDL `Controller.get_mapping()`; fall back to rest-value classification; allow `input.axis_layout` / `input.invert` overrides (`input_source.py:214`, `:258`, `:313`).

## Error Handling

**Strategy:** Validate early at config load, degrade gracefully at runtime, never crash the windowed app, and convert failures into user-readable one-liners.

**Patterns:**
- **Config:** `load_config` raises `SystemExit` with file path, JSON line/column, or semantic message (`config.py:765-782`). GUI catches `SystemExit`/`Exception` into `config_error` and renders a dedicated error screen with `R` to reload (`gui.py:364-380`, `:1256`).
- **Skill validation:** Kind-specific checks in `_parse_skill` (`config.py:535-664`): non-empty steps, `sum(hold_ms) < max_duration_ms`, `max > min` windows, valid direction names, valid canonical buttons, `modifier_options` consistency, duplicate skill names (`:740-745`).
- **Device:** `PygameJoystickSource` raises `RuntimeError` with actionable hints; `main.py` prints and exits 1 (`main.py:269-274`); GUI shows no-device screen, listens for `JOYDEVICEADDED`, supports `R` retry with `joystick.quit()/init()` re-enumeration (`gui.py:630-645`, `:664-666`).
- **Runtime loop exceptions (unplug, SDL error):** `TrainerApp._play` catches, stores `error`, clears engine, returns to the wait screen (`gui.py:577-591`).
- **Rumble:** exceptions/False returns counted in `RumbleEngine.failures` with `_last_error`; surfaced by `health()` in `Engine.summary()` (`rumble.py:306-343`, `engine.py:505-506`). Individual stop errors swallowed.
- **Detector verdicts:** `Failure` carries a machine `code` (for stats/i18n labels) and a Chinese `message` (for display); codes are mapped to advice in `_ADVICE` (`gui.py:54-65`) and labels in `Detector.FAILURE_LABELS` (`detectors.py:65-76`).
- **Diagnostics:** GUI writes a UTF-8-BOM `trainer.log` under `user_config_dir()`, rotates at 2 MB, logs session config/layout plus per-gesture RS traces and outcomes (`gui.py:413-538`).

## Cross-Cutting Concerns

**Logging:** CLI prints to stdout (`--verbose` for layout/skill table/trajectory, `--feedback` for failures; `engine.py:365-412`, `main.py:304-313`). GUI routes engine output to `_Sink` and instead writes structured diagnostics to `trainer.log` (`gui.py:268-275`, `:442-450`). `--debug`/`--trace` use carriage-return cursor control with Windows ANSI enablement (`engine.py:29-52`, `:426-462`).

**Validation:** Centralized in `config.py` at parse time (`_clamp01`, `_parse_pulses`, `_parse_required_buttons`, `_validate_common_timing`, `_parse_skill`, `_parse_input`, `_parse_rumble`). Detectors additionally guard invariants in their constructors (`detectors.py:148-152`, `:476-486`, `:873-879`). No runtime validation of `PadState` (assumed device-provided).

**Authentication:** Not applicable — local desktop app, no network, no accounts, no secrets.

**Internationalization:** UI, error messages, docs, and failure labels are Simplified Chinese; canonical internal identifiers (button names, kind strings) are English. Direction aliases accept both Chinese and English (`config.py:84-95`).

---

*Architecture analysis: 2026-11-04*
