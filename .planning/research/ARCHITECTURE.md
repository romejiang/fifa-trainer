# Architecture Research

**Domain:** Godot 4 (GDScript) Android real-time gesture trainer — faithful port of a single-threaded Python 250 Hz polling app
**Researched:** 2026-11-04
**Confidence:** HIGH for Godot engine semantics (official docs, quoted below); MEDIUM for device-specific behaviour (Android vibration reliability, trigger axis ranges, exported-PCK JSON handling) — those must be proven on real hardware, which the project already mandates.

---

## Verdict in One Page

The Python architecture ports cleanly **because its domain core is already pure**: `geometry` → `config` → `detectors` → `engine` has no pygame dependency except through `PadState`. Reproduce that DAG in GDScript, and 80% of the port is mechanical.

But **five things must change** — four forced by the engine, one forced by the original design's defects:

| # | Python design | Godot reality | Forced change |
|---|---|---|---|
| 1 | Fixed 250 Hz `sleep`-driven loop | Joypad state is refreshed **once per process frame**; there is no way to poll faster than the render loop | Sampling collapses to display refresh (60–120 Hz) with **variable Δt**. Death of the fixed-period loop. |
| 2 | Absolute-timeline catch-up + `overruns` counter | Sample times *are* frame times; there is nothing to catch up to | Replace re-alignment with a **frame-gap detector** that abandons in-flight gestures when Δt exceeds a reliability threshold |
| 3 | `time.perf_counter()` seconds, `* 1000.0` at every comparison | `_process(delta)` is **clamped and smoothed**; `_physics_process` runs 0..N times per rendered frame | Use **`Time.get_ticks_usec()/1000.0` milliseconds end-to-end**; never `delta` |
| 4 | GUI reads `engine.skills[i].detector` and mutates `Skill` in place | Godot's idiom is signals + `queue_redraw`; `res://` is read-only; `assert()` is stripped in release | **Signals + immutable snapshot + command methods + user:// override layer** |
| 5 | (the one to fix) Engine writes ANSI to a `TextIO`, GUI runs inside the sample callback | — | **`src/core/` contains zero `Input`, `Time`, `Node`, `print`, or `FileAccess`.** Enforced by a lint test. |

Everything else — the three detector state machines, the `update/reset/on_idle/abandon/observe/pop_failure/status` lifecycle, the gesture lock, the one-slot failure drain, the ms-based thresholds, the JSON schema — transfers essentially 1:1.

---

## Standard Architecture

### System Overview

```
┌──────────────────────────────────────────────────────────────────────────────┐
│  L0  Composition root            mobile/src/app/main.gd  (Node)              │
│      • loads config, constructs the object graph, wires signals              │
│      • the ONLY place that knows about both core and UI                      │
└───────────────┬─────────────────────────────────────┬────────────────────────┘
                │ inject (RefCounted)                 │ connect signals
                ▼                                     ▼
┌──────────────────────────────────────┐  ┌──────────────────────────────────┐
│  L1  Platform adapters (Nodes)       │  │  L3  Presentation (Nodes/Control)│
│  gesture_runtime.gd  ← the clock     │  │  sticks_plot.gd                  │
│  godot_input_source.gd ← Input       │  │  stats_panel.gd                  │
│  godot_rumble_sink.gd ← vibration    │  │  outcome_feed.gd                 │
│  replayer_source.gd  ← JSONL (dev)   │  │  error_screen.gd                 │
│  Only these may touch Input/Time/OS  │  │  reads SessionSnapshot only      │
└───────────────┬──────────────────────┘  └────────────▲─────────────────────┘
                │ PadSample{t_ms,axes,buttons}           │ snapshot()
                ▼                                        │
┌──────────────────────────────────────────────────────────────────────────────┐
│  L2  Core (pure GDScript, RefCounted, headless-testable)                     │
│                                                                              │
│  ┌────────────────────┐   ┌────────────────────────────────────────────┐     │
│  │ GestureEngine      │──▶│ Detector (arc | sequence | taps)           │     │
│  │ • facing tracking  │   │ • update(frame) -> Hit?                    │     │
│  │ • gesture lock     │◀──│ • reset/on_idle/abandon/observe            │     │
│  │ • modifiers filter │   │ • pop_failure() -> Failure?                │     │
│  │ • cooldowns/stats  │   └────────────────────────────────────────────┘     │
│  │ • failure drain    │   ┌────────────────────────────────────────────┐     │
│  │ • RumbleSequencer  │──▶│ AppConfig (Skill/Step/Pulse/InputCfg)      │     │
│  └────────────────────┘   └────────────────────────────────────────────┘     │
└──────────────────────────────────────────────────────────────────────────────┘
                ▲
                │ parse + validate
┌───────────────┴──────────────────────────────────────────────────────────────┐
│  L4  Data        res://assets/config/skills_config.json  (synced, hash-pinned)│
│                  user://config/overrides.json            (optional, sparse)  │
└──────────────────────────────────────────────────────────────────────────────┘
```

**Allowed dependencies (nothing else is permitted):**

| From | To | Mechanism |
|---|---|---|
| L0 `Main` | L1, L2, L4 | direct construction + `setup()` |
| L0 `Main` | L3 | `add_child()`, signal connect |
| L1 `GestureRuntime` | L2 `GestureEngine` | `tick(sample) → Array[Outcome]` |
| L1 `GodotInputSource` | L2 `PadSample`, `InputSource` | implements the port |
| L3 UI | L1 `GestureRuntime` | `snapshot()` + command methods |
| L3 UI | L2 DTO types only (`SessionSnapshot`, `Outcome`, `SkillSnapshot`) | type hints |
| L2 | nothing outside L2 | — |

`L2` must never `preload()` anything from `L1` or `L3`. `L3` must never hold a `Detector`, `Skill`, or `ActiveSkill` reference. Verify with the lint test in §Testability.

### Component Responsibilities

| Component | Layer | Base type | Owns | Must NOT |
|---|---|---|---|---|
| `Main` | L0 | `Node` | Object graph, signal wiring, scene switching | Contain detection logic or timing math |
| `GestureRuntime` | L1 | `Node` | The monotonic clock, one `PadSample` per `_process`, calling `engine.tick()`, re-emitting outcomes as signals | Know about UI widgets |
| `GodotInputSource` | L1 | `RefCounted` | `Input.get_joy_axis` / `is_joy_button_pressed` → `PadSample`; deadzone rescale; LT/RT synthesis; device id selection | Store detection state |
| `GodotRumbleSink` | L1 | `RefCounted` | `Input.start_joy_vibration` / `stop_joy_vibration` / `has_joy_vibration` | Decide *when* to vibrate |
| `ReplayerSource` | L1 | `RefCounted` | Emit `PadSample` from a JSONL trace at synthetic timestamps | Be used in production |
| `GestureEngine` | L2 | `RefCounted` | Facing, gesture lock, idle reset, modifier filtering, cooldowns, stats, failure drain, rumble sequencing | Touch `Input`, `Time`, `Node`, `FileAccess`, `print` |
| `Detector` + 3 subclasses | L2 | `RefCounted` | Per-skill FSM + failure diagnosis | Read wall-clock time; assume a fixed sample count |
| `RumbleSequencer` | L2 | `RefCounted` | Single-pulse state machine (drop while active, stop at deadline) | Call `Input` directly (takes a `RumbleSink`) |
| `AppConfig` / `Skill` / `Step` / `Pulse` | L2 | `RefCounted` | Immutable-after-load rule data | Be mutated at runtime |
| `ConfigLoader` / `ConfigValidator` | L2 | `RefCounted` (static) | JSON → `AppConfig` + `Array[ConfigError]` | `assert()` (stripped in release), `push_error()` only |
| `SessionSnapshot` | L2 | `RefCounted` | Read-only DTO of everything the UI may display | Expose detectors or `Skill` objects |
| `SticksPlot` | L3 | `Control` | `draw_polyline` ring buffer of LS/RS trails | Read `engine.skills` |
| `StatsPanel` / `OutcomeFeed` | L3 | `Control` | Render `SessionSnapshot` | Mutate config |

### Class vs Node vs Autoload — the prescriptive answer

| Kind | Use for | Not for |
|---|---|---|
| `RefCounted` + `class_name` | **Everything in `src/core/`** — model, geometry, config, all detectors, engine, sequencer, snapshot. This is the FP/pure layer. | Anything needing `_process`, tree access, or lifecycle |
| `Node` | **Only the 4 platform adapters + UI widgets + `Main`.** Nodes exist because Godot calls `_process` / `_draw` / notifications on them. | Detectors, config, model |
| `Resource` | **Nothing in this project, except optionally a generated `.tres` config cache.** Godot caches Resources *by path*: `load()` twice returns the **same instance**, so a Resource holding mutable state silently leaks between scenes/tests. | Config model, detector state |
| `Autoload` (singleton) | **Zero.** Optionally one stateless `Log` autoload writing to `user://logs/`. | Engine, config, input, "AppState" |

**Why zero autoloads, explicitly:** an autoload is a globally reachable mutable singleton. The Python version's defining defect is that the GUI can reach `engine.skills[i].detector` from anywhere in the same process. Recreating the engine as an autoload re-creates exactly that affordance, just with better syntax. Use `Main._ready()` as the composition root and pass dependencies explicitly (constructor arg or `setup()`).

One legitimate exception: **Android lifecycle notifications** (`NOTIFICATION_APPLICATION_PAUSED` / `RESUMED`) are delivered to nodes, so the receiving node must be alive for the whole app lifetime. `Main` is — it is never freed. No autoload needed.

---

## Recommended Project Structure

```
fifa-trainer/
├── desktop/                     # existing Python (restructured in the first phase)
├── shared/
│   └── skills_config.json       # SINGLE SOURCE OF TRUTH
├── tools/                       # repo-level, deliberately OUTSIDE mobile/
│   ├── sync_config.py           # shared/ -> mobile/assets/config/ + .sha256
│   ├── check_config_parity.py   # Python validator vs GDScript validator
│   ├── gen_trace_fixtures.py    # synthetic gestures -> tests/fixtures/traces/
│   └── decimate_trace.py        # 250 Hz -> 60/90/120 Hz fixtures
└── mobile/                      # === pure Godot project root (project.godot here) ===
    ├── project.godot
    ├── export_presets.cfg       # include_filter="*.json" (see §Config Boundaries)
    ├── .godot-version           # pin the engine, e.g. 4.7.2-stable
    ├── assets/
    │   ├── config/
    │   │   ├── skills_config.json     # SYNCED — never hand-edited
    │   │   ├── skills_config.sha256   # generated
    │   │   └── config_stamp.gd        # generated: const EXPECTED_SHA256 := "..."
    │   ├── fonts/
    │   └── icon.svg
    ├── src/
    │   ├── core/                      # ★ zero Godot-API dependencies
    │   │   ├── domain/
    │   │   │   ├── pad_sample.gd      # PadSample
    │   │   │   ├── frame.gd           # Frame (detector input)
    │   │   │   ├── hit.gd             # Hit
    │   │   │   ├── failure.gd         # Failure
    │   │   │   ├── outcome.gd         # Outcome
    │   │   │   ├── skill.gd           # Skill, Step, Pulse, InputConfig
    │   │   │   ├── app_config.gd      # AppConfig (+ to_dict for the immutability test)
    │   │   │   └── session_snapshot.gd
    │   │   ├── geometry.gd            # norm_deg / signed_delta / angle_diff / angle_of / magnitude
    │   │   ├── config/
    │   │   │   ├── config_loader.gd   # JSON text -> AppConfig + errors
    │   │   │   ├── config_validator.gd
    │   │   │   ├── config_error.gd    # {json_path, code, message, fix_hint}
    │   │   │   ├── direction_table.gd # 中/英方向名 -> degrees
    │   │   │   └── overrides.gd       # sparse merge of user://overrides.json
    │   │   ├── detectors/
    │   │   │   ├── detector.gd        # @abstract base + lifecycle
    │   │   │   ├── arc_detector.gd
    │   │   │   ├── sequence_detector.gd
    │   │   │   ├── tap_detector.gd
    │   │   │   └── detector_factory.gd
    │   │   ├── engine/
    │   │   │   ├── gesture_engine.gd
    │   │   │   ├── active_skill.gd
    │   │   │   └── rumble_sequencer.gd
    │   │   └── ports/
    │   │       ├── input_source.gd    # @abstract: poll(t_ms) -> PadSample
    │   │       └── rumble_sink.gd     # @abstract: start/stop/is_available
    │   ├── platform/
    │   │   ├── gesture_runtime.gd     # Node: clock + tick + signals
    │   │   ├── godot_input_source.gd
    │   │   ├── godot_rumble_sink.gd
    │   │   ├── joy_button_map.gd      # "LB" -> JOY_BUTTON_LEFT_SHOULDER
    │   │   └── replayer_source.gd     # dev/test
    │   ├── app/
    │   │   ├── main.tscn
    │   │   └── main.gd
    │   └── ui/
    │       ├── sticks_plot.gd
    │       ├── stats_panel.gd
    │       ├── outcome_feed.gd
    │       ├── status_bar.gd
    │       ├── error_screen.gd
    │       └── ui_theme.tres
    ├── tests/
    │   ├── run_tests.gd               # extends SceneTree; --headless entry
    │   ├── test_case.gd               # assert helpers + exit-code bookkeeping
    │   ├── unit/
    │   │   ├── test_geometry.gd
    │   │   ├── test_config_loader.gd
    │   │   ├── test_arc_detector.gd
    │   │   ├── test_sequence_detector.gd
    │   │   ├── test_tap_detector.gd
    │   │   ├── test_engine_arbitration.gd
    │   │   ├── test_rumble_sequencer.gd
    │   │   └── test_architecture_lint.gd   # no Input/Time/Node in src/core
    │   └── fixtures/
    │       ├── traces/*.jsonl             # committed, generated by tools/
    │       └── configs/{valid,invalid}/*.json
    └── docs/
        ├── ARCHITECTURE.md
        └── TIMING.md
```

### Structure Rationale

- **`tools/` outside `mobile/`:** Godot imports *every* file under the project root. Python scripts inside `mobile/` become non-resource blobs in the PCK and pollute the importer. Cross-language tooling belongs at repo level, next to `shared/`.
- **`src/core/` is a hard boundary, not a convention:** it is the only directory that may be unit-tested without a `SceneTree`, the only directory that can be replayed deterministically, and the only directory whose behaviour must match the Python desktop build. Make it enforceable (lint test), because "we'll keep it clean" decays.
- **`platform/` vs `core/ports/`:** the port interfaces live in core (so core can type-hint them); the implementations live in platform (so core never sees `Input`).
- **`assets/config/` holds a *generated* file.** Anything generated must be identifiable as generated — hence the `.sha256` sibling and the `config_stamp.gd` constant.
- **`tests/` inside the project root** so `res://tests/...` resolves under `--path mobile`; fixtures are plain files read with `FileAccess`, no import step.

---

## Timing Model (the part that must change)

### What Godot actually gives you

| Fact | Source | Consequence |
|---|---|---|
| `_process(delta)` runs once per idle frame, before rendering, after physics ticks | Node docs | One sample per frame = one coherent snapshot |
| `delta` **is clamped**: `Engine.time_scale * Engine.max_physics_steps_per_frame / Engine.physics_ticks_per_second` (default 8/60 ≈ **133 ms**) — "accumulated delta may not represent real world time" | Node docs, quoted verbatim | **Never integrate `delta` for detector timings** |
| `delta` may be post-processed by delta smoothing (`application/run/delta_smoothing`, on by default) | ProjectSettings docs | `delta` is a *rendering* hint, not a clock |
| `_physics_process(delta)` runs 0..N times per rendered frame; `delta` = `time_scale / physics_ticks_per_second`, always exactly 1/60 | Node docs | Duplicate/fabricated timestamps |
| `Input.use_accumulated_input` defaults **true**; "limits the number of input method calls per second to the rendering FPS" | Input docs | Input resolution == frame rate. Hard ceiling. |
| `input_devices/buffering/agile_event_flushing`: false ⇒ events flushed "only once per process frame"; **"Currently implemented only on Android"** | ProjectSettings docs | The only sanctioned escape hatch (see below) |
| `Time.get_ticks_usec()` "Always positive or 0, stored as a 64-bit value"; Time docs: "use `get_ticks_usec()` or `get_ticks_msec()` … they are guaranteed to be **monotonic**" | Time docs | The clock |
| `Engine.max_fps`: "If vsync is Enabled or Adaptive, the setting takes precedence and the max FPS number cannot exceed the monitor's refresh rate" | Engine docs | On a 60 Hz phone you get 60 Hz sampling, full stop |

### Decision: `_process` + `Time.get_ticks_usec()`, never `_physics_process`, never `delta`

```gdscript
# src/platform/gesture_runtime.gd
class_name GestureRuntime
extends Node

signal outcome_recorded(outcome: Outcome)
signal sample_gap(reason: StringName, dt_ms: float)

const GAP_WARN_MS := 50.0     # a hiccup: log it, keep going
const GAP_RESET_MS := 120.0   # ≥ min(release_hold_ms) — the verdict can no longer be trusted

var _engine: GestureEngine
var _source: InputSource
var _last_t_ms := 0.0
var _started := false
var _gap_count := 0

func setup(engine: GestureEngine, source: InputSource) -> void:
    _engine = engine
    _source = source
    _started = true
    _last_t_ms = Time.get_ticks_usec() / 1000.0   # float milliseconds

func _ready() -> void:
    process_priority = -100          # tick before any UI node reads the snapshot
    set_process(true)

func _process(_delta: float) -> void:
    if not _started:
        return
    var now_ms := Time.get_ticks_usec() / 1000.0
    var dt_ms := now_ms - _last_t_ms
    _last_t_ms = now_ms

    if dt_ms > GAP_RESET_MS:
        _gap_count += 1
        _engine.on_time_discontinuity()     # reset detectors + unlock gesture + reload rumble deadline
        sample_gap.emit(&"reset", dt_ms)
        return                              # do NOT feed the discontinuity as a sample
    if dt_ms > GAP_WARN_MS:
        _gap_count += 1
        sample_gap.emit(&"warn", dt_ms)

    var sample := _source.poll(now_ms)
    for outcome in _engine.tick(sample):
        outcome_recorded.emit(outcome)
```

**Why not `_physics_process`:** with physics at 60 Hz and a 33 ms render frame, physics fires **twice** with the *same* joypad snapshot (input is pumped once per process frame). The second call carries a timestamp 16.7 ms later with identical axes. The arc detector would see "no rotation for 16.7 ms" and refresh/expire its motion latch; `elapsed_ms` inflates; `idle_timeout_ms = 250` fires after only ~15 real ticks of stillness. Every threshold in the config silently changes meaning. This is the single most likely way to ship a detector that "works in the editor" and mis-scores on device.

**Why not `delta`:** it is clamped at ~133 ms and smoothed. A 300 ms Android hiccup would be reported as 133 ms, so a gesture that genuinely took 400 ms could be scored inside the 250–600 ms window. `Time.get_ticks_usec()` deltas report the truth.

**Why `Time.get_ticks_usec()` also buys you robustness:** it is unaffected by `Engine.time_scale`, `--fixed-fps`, Movie Maker mode, and delta smoothing. Detector verdicts stay stable across all engine-level time manipulation.

### What replaces the absolute-timeline re-alignment

Nothing — and that is correct. In Python, `next_tick += period` existed because sampling was *supposed* to happen at 250 Hz independent of rendering. In Godot the sample time **is** the frame time; a late frame is not "behind schedule", it is simply the next truthful observation of the stick. There is no catch-up to perform.

So `Engine.overruns` becomes a **diagnostic histogram**, not a control mechanism:

| Python metric | Godot replacement | Purpose |
|---|---|---|
| `overruns` (loop fell behind, re-aligned) | `gap_count` + `p95_dt_ms` + `sampled_hz` | Show the user "your phone is dropping frames, verdicts may be unreliable" |
| `frames / elapsed` printed at exit | Live `sampled_hz` on the status bar | Same |
| `period = 1/poll_hz` from config | Derived from the device; `input.poll_hz` is **ignored on mobile** (keep the key for desktop config compatibility; validate it, don't obey it) | Avoids a lie in the config file |

**Recommendation:** keep `input.poll_hz` in the JSON for schema compatibility, but have `ConfigValidator` emit a *warning* (not an error) when `poll_hz > 144`: `"移动端采样率由屏幕刷新率决定（约 60–120 Hz），poll_hz 仅桌面版生效"`.

### Sample-rate sensitivity — actual numbers from this config

All five skills: `min_duration_ms = 250`, `max_duration_ms = 600`, `idle_timeout_ms = 250–350`, `release_hold_ms = 120–150`, `global_cooldown_ms = 60`, tap `min_interval_ms = 400`.

| Threshold | Value | Samples @60 Hz | Samples @120 Hz | Quantisation risk |
|---|---|---|---|---|
| `min_duration_ms` | 250 ms | 15.0 | 30.0 | low — measured by timestamps, not counts |
| `max_duration_ms` | 600 ms | 36.0 | 72.0 | low |
| `idle_timeout_ms` | 250 ms | 15.0 | 30.0 | low |
| `release_hold_ms` | 120 ms | **7.2** | 14.4 | medium — worst case the release takes 120→137 ms (+14%) |
| `global_cooldown_ms` | **60 ms** | **3.6** | 7.2 | **high** — a frame of jitter is ±28% of the threshold |
| tap `min_interval_ms` | 400 ms | 24.0 | 48.0 | low |

**Conclusions:**

1. **No threshold needs to be pre-emptively changed.** Every window is ≥ 3.6 samples wide and all durations are computed from timestamps, so the *measured* value is exact; only the *decision instant* is quantised.
2. **`global_cooldown_ms = 60` is the tightest value in the system** and the only one where frame jitter can flip a decision. It is also the least harmful (it only affects double-fire suppression, which is already gated by the gesture lock and `release_hold_ms`). Do **not** widen it pre-emptively — prove the drift with fixtures first (§Testability), then widen with evidence.
3. **`release_hold_ms` behaviour will visibly change** (a 120 ms release becomes 120–137 ms). Users will not notice; the trace test will.
4. **Per-frame rotation must stay well under 180°** for the arc detector's shortest-arc accumulation to remain unambiguous. At 60 Hz a 900°/s flick (already very fast) moves 15°/frame — safe. At a 100 ms gap it moves 90°/frame — the `GAP_RESET_MS = 120` guard covers the pathological case but note that 90° is already ambiguous for `signed_delta`. **Do not raise `GAP_RESET_MS` above ~150 ms.**

### The escape hatch, if 60 Hz proves insufficient

`input_devices/buffering/agile_event_flushing = true` flushes joypad events **before every idle *and physics* frame**, so a phone running 2 physics steps per rendered frame can deliver two flushes per frame. Combined with `Input.use_accumulated_input = false` and an `_input(event)` handler that accumulates `InputEventJoypadMotion` per axis with `Time.get_ticks_usec()` stamps, you could exceed the frame rate.

**Do not build this up front.** It is Android-only, it produces *per-axis* events rather than a coherent snapshot (you would fabricate the other axes), and it doubles the state machine. Keep it documented as the mitigation if Phase H device testing shows 60 Hz is insufficient. Flag it as a research item, not a task.

### Refresh-rate / device matrix (replaces "scaling considerations")

| Device class | `_process` rate | Samples per 250 ms window | Notes |
|---|---|---|---|
| Mid-range Android, 60 Hz panel | 60 Hz | 15 | `release_hold` = 7 samples; usable but the floor |
| Modern Android, 90 Hz | 90 Hz | 22 | Good |
| Flagship, 120 Hz | 120 Hz | 30 | Best fidelity; also the highest battery cost |
| Any device under load | 30–45 Hz | 7–11 | **Must** surface a "device is struggling" indicator; verdicts degrade silently otherwise |
| Desktop dev (macOS) | 60–120 Hz | — | Use `Engine.max_fps = 120` + `vsync_mode = disabled` for detector iteration so tests run at a realistic rate |

**Runtime policy:** vsync **on**, `Engine.max_fps = 0` (let the display decide). Do **not** disable vsync to chase >120 Hz — tearing on a trainer UI is worse than 8 ms of extra sample resolution, and `Engine.max_fps` cannot exceed the refresh rate anyway when vsync is on.

---

## Input Pipeline

### Poll, do not consume events (for the detection path)

| Approach | Gives you | Verdict |
|---|---|---|
| `Input.get_joy_axis(id, axis)` + `Input.is_joy_button_pressed(id, btn)` once per `_process` | A **coherent snapshot** of all axes and buttons at one instant | ✅ **Use this.** It is the exact analogue of Python's `PygameJoystickSource.poll() → PadState`. |
| `_input(event)` on `InputEventJoypadMotion/Button` | Per-axis deltas, interleaved, coalesced per frame | ❌ For detection. Axis events arrive one axis at a time; building a `Frame` requires carrying forward the other axes, and multiple axis events in one frame would share one timestamp (a zero-Δ sample). |
| `InputMap` actions + `Input.get_vector()` | Deadzone-managed, remappable | ❌ For detection. The deadzone is applied *before* you see the value, and Godot's deadzone semantics differ from `input.deadzone`. Hidden state you don't control. |
| `_input(event)` for `joy_connection_changed` | Hotplug | ✅ Use it, but via the `Input.joy_connection_changed` **signal**. |

### `PadSample` — the Godot `Frame` equivalent

```gdscript
# src/core/domain/pad_sample.gd
class_name PadSample
extends RefCounted

var t_ms: float = 0.0          # monotonic milliseconds since engine start
var ls_x: float = 0.0
var ls_y: float = 0.0
var rs_x: float = 0.0
var rs_y: float = 0.0
var lt: float = 0.0            # 0..1
var rt: float = 0.0            # 0..1
var buttons: PackedStringArray = PackedStringArray()   # canonical: A,B,X,Y,LB,RB,LT,RT,LS,RS,...

func ls_mag() -> float: ...
func ls_angle() -> float: ...
func rs_mag() -> float: ...
func rs_angle() -> float: ...
func has_button(name: String) -> bool: ...
```

Then `Frame` (detector input) is built by the engine each tick, exactly as in Python:

```gdscript
class_name Frame
extends RefCounted
var t_ms: float
var ls_mag: float
var ls_angle: float
var rs_mag: float
var rs_angle: float
var facing: float
var facing_valid: bool
var buttons: PackedStringArray
var sample: PadSample
```

**Keep `PadSample` separate from `Frame`.** Python did, and the separation is what lets `ReplayerSource` produce samples without knowing detector semantics.

### Adaptations the adapter must perform (and nothing else)

| Concern | Python | Godot | Action |
|---|---|---|---|
| Axis identity | Runtime inference from SDL mapping table, fallback to rest-value classification, fallback to config `axis_layout` | Fixed logical `JOY_AXIS_LEFT_X=0, LEFT_Y=1, RIGHT_X=2, RIGHT_Y=3, TRIGGER_LEFT=4, TRIGGER_RIGHT=5` via SDL GameController DB | **Delete `AxisLayout` inference entirely.** ~250 lines of Python disappear. Keep a read-only "axis probe" debug screen. |
| Y direction | SDL y-down; `geometry.angle_of()` converts once | Same: `JOY_AXIS_LEFT_Y` is +1 = down | Port `angle_of()` verbatim: `deg(atan2(x, -y))`. Keep the exact-centre guard (`x==0 && y==0 → 0.0`). |
| Deadzone | Applied in `PygameJoystickSource.poll()` with `input.deadzone` + rescale | **`Input.get_joy_axis` returns the raw value; Godot's deadzone only applies to InputMap actions** (`get_action_raw_strength` exists precisely because action strength *does* apply it) | **You must implement the deadzone yourself**, identically to Python. Do not rely on Godot. |
| Triggers | Raw SDL axes, rest ≈ −1.0; normalized to 0..1 with `trigger_threshold` | `JOY_AXIS_TRIGGER_*` in practice reports 0..1 on SDL game-controller mappings | **Medium confidence.** Add a startup axis probe that prints each axis's rest and full-press value, and assert `lt/rt ∈ [0,1]` in `GodotInputSource`. If a device reports −1..1, normalize `(v+1)/2` behind a `device_profile` key. |
| LT/RT as buttons | `canonical_button("LT")` → a member of `CANONICAL_BUTTONS`; `input.trigger_threshold` promotes the axis to a button | Triggers are **axes**, not `JoyButton`s | Synthesize: `if lt >= trigger_threshold: buttons.append("LT")`. This keeps every detector and the config vocabulary untouched. |
| Button names | `BUTTON_ALIASES` dict → `CANONICAL_BUTTONS` | `JoyButton` enum is *itself* the SDL logical layout, so the canonical set maps 1:1 | Build one `joy_button_map.gd` table: `A→JOY_BUTTON_A`, `B→JOY_BUTTON_B`, `X→JOY_BUTTON_X`, `Y→JOY_BUTTON_Y`, `LB→JOY_BUTTON_LEFT_SHOULDER`, `RB→JOY_BUTTON_RIGHT_SHOULDER`, `LS→JOY_BUTTON_LEFT_STICK`, `RS→JOY_BUTTON_RIGHT_STICK`, `BACK→JOY_BUTTON_BACK`, `START→JOY_BUTTON_START`, `GUIDE→JOY_BUTTON_GUIDE`, `DPAD_*→JOY_BUTTON_DPAD_*`. LT/RT are axis-derived (above). |
| Device selection | `input.joystick_index` | `Input.get_connected_joypads()` — **order is not stable across app restarts** (documented) | Do not persist an index. Prefer the first connected device; expose a device picker when >1. Record `Input.get_joy_name()` + `get_joy_guid()` in the log so traces are attributable. |
| Hotplug | `JOYDEVICEADDED` event + `joystick.quit()/init()` re-enumeration | `Input.joy_connection_changed(device, connected)` signal | Connect once in `GestureRuntime`; on disconnect, `engine.on_device_lost()` (reset all, clear lock) and show the reconnect overlay. |

---

## Detector Porting Contract

### Non-negotiable rules for `src/core/detectors/**`

1. **No `Time.*`, no `Input.*`, no `Node`, no `FileAccess`, no `print`.** All time arrives as `frame.t_ms`. Enforced by lint test.
2. **Every threshold is compared in milliseconds.** Convert `frame.t_ms` and `self.t0_ms` directly; never write `* 1000.0` anywhere.
3. **No sample-count assumptions.** Grep the Python source before porting: `self.samples` exists only for `status()` display, and `_motion_ref_angle` is refreshed by *angle*, not by frame count — so it is already rate-tolerant. **Preserve the angle-based latch exactly**; do not "simplify" it to adjacent-frame comparison (the Python comment explains why: at high rate a slow arc moves <2°/frame).
4. **Preserve the lifecycle semantics verbatim**, because the engine's arbitration depends on the distinction:
   - `reset()` — locally invalid (modifier released, facing lost). Re-arms **immediately**; retry is legitimate.
   - `abandon()` — this trajectory belongs to another skill. Clears `_pending` **and** must not re-arm until the stick centres.
   - `on_idle()` — long stillness; defaults to `reset()`.
   - `observe(frame)` — record stick position for UI hints **without** advancing the FSM.
   - `pop_failure()` — returns and clears the single `_pending` slot.
5. **One verdict per tick, globally.** `_emit()` is only reached on abort paths that immediately `return null`; a `Hit` return and a `_pending` failure are mutually exclusive. Assert this in `GestureEngine.tick()` under `assert()` for debug builds only (see the release-strip pitfall) and in a unit test for real.

### Lifecycle in GDScript

```gdscript
# src/core/detectors/detector.gd
@abstract
class_name Detector
extends RefCounted

const FAILURE_LABELS := {
    &"too_fast": "太快", &"too_slow": "太慢", &"too_short": "转得不够",
    &"overshoot": "转多了", &"wrong_start": "起点不对", &"wrong_end": "终点不对",
    &"wrong_direction": "方向反了", &"stalled": "中途停住",
    &"incomplete": "没做完", &"hold_short": "保持不够",
}

var _pending: Failure = null

func update(_frame: Frame) -> Hit:            return null
func reset() -> void:                          pass
func on_idle() -> void:                        reset()
func abandon() -> void:
    _pending = null
    reset()
func observe(_frame: Frame) -> void:           pass
func pop_failure() -> Failure:
    var f := _pending
    _pending = null
    return f
func status() -> String:                       return ""
func _emit(f: Failure) -> void:                _pending = f
```

> `@abstract` requires Godot ≥ 4.5 (fine on the pinned 4.7.x). If the pinned version is older, drop the annotation and `push_error()` in `_init()`.

### Failure message table

`Failure` carries a machine `code` (for stats/i18n) and a Chinese `message` (for display). Keep both. Do **not** move the message into the UI layer: the messages embed the measured value (`"太快了：{elapsed:.0f}ms 就转到位了"`), which only the detector knows. The UI maps `code → advice` as Python's `_ADVICE` did.

---

## Data Flow

### Per-tick flow (the only hot path)

```
 1. Godot main loop                 Input.event pump (once per frame, ALL platforms by default)
        │
        ▼
 2. GestureRuntime._process(_delta)  [process_priority = -100]
        │  now_ms = Time.get_ticks_usec()/1000.0
        │  dt_ms  = now_ms - last_t_ms
        │  if dt_ms > 120 → engine.on_time_discontinuity(); return
        ▼
 3. GodotInputSource.poll(now_ms)
        │  raw axes → deadzone rescale → lt/rt normalize → synthesize LT/RT buttons
        ▼
 4. PadSample {t_ms, ls*, rs*, lt, rt, buttons}
        │
        ▼
 5. GestureEngine.tick(sample)  ───────────────────────────────────────────────
        │  a. facing update (ls_mag ≥ ls_facing_threshold ? angle : invalid)
        │  b. Frame = {t_ms, angles, mags, facing, buttons}
        │  c. gesture_locked? → wait rs_mag < 0.35 for gesture_release_ms → on_idle all → unlock
        │        still locked → rumble.update(now); EARLY RETURN
        │  d. held_required = union of required buttons currently held
        │  e. idle: rs_mag < 0.20 for idle_reset_ms → on_idle all (once)
        │  f. for each ActiveSkill in config order:
        │        other skill's modifier held      → observe() + abandon(); continue
        │        relative_to_ls && !facing_valid → observe() + reset();   continue
        │        own modifier not satisfied       → observe() + reset();   continue
        │        hit = detector.update(frame)
        │        if hit:
        │            discard_other_claims(self)        # abandon() on all others
        │            cooldown checks (per-skill, then global) → maybe suppress
        │            stats++, record Outcome(ok), rumble.try_play(pattern, now)
        │            gesture_locked = true; break
        │  g. drain_failures(): first detector with a pending failure wins;
        │        record Outcome(fail); discard_other_claims(winner)
        │  h. rumble.update(now)   → sink.stop() at deadline
        └── returns Array[Outcome]  (0 or 1 entries; the ≤1 invariant is a unit test,
                                     with a debug-only assert as belt-and-braces)
        │
        ├──────────────► 6a. GestureRuntime emits outcome_recorded(o)
        │                      └──► OutcomeFeed.append(o), StatusBar counter, Log
        │
        └──────────────► 6b. SticksPlot._process [priority = 100]
                               └── snapshot = engine.snapshot(); queue_redraw()
                                   _draw(): draw_polyline(ring buffer)
```

**Direction is strictly downward for data and upward for commands.** The UI never pulls from `engine` mid-tick; it reads `snapshot()` *after* the tick, in the same frame, because `process_priority` orders them.

### State ownership

```
        ┌───────────────────────── owned by ─────────────────────────┐
Config  │ AppConfig (immutable after load)                           │
        ├────────────────────────────────────────────────────────────┤
Session │ GestureEngine: facing, facing_valid, gesture_locked,       │
        │   lock_release_since, idle_since, last_any_fire,           │
        │   ActiveSkill{s stats, last_fire, last_outcome}, gap stats │
        ├────────────────────────────────────────────────────────────┤
Per-skill│ Detector internals (FSM, _pending, timers)                │
        ├────────────────────────────────────────────────────────────┤
Device  │ GestureRuntime: device id, last_t_ms, source, gap counter  │
        ├────────────────────────────────────────────────────────────┤
UI      │ Stick trail ring buffer, text caches, scroll position      │
        └────────────────────────────────────────────────────────────┘
```

Nothing is shared. Nothing is written by two owners. That is the whole point.

---

## Separation of Concerns — the Godot-idiomatic fix

### What the Python version got wrong (from `CONCERNS.md`)

| Defect | Evidence | Why it hurts |
|---|---|---|
| GUI reaches into `engine.skills[i].detector`, `engine.facing`, `engine.outcome_seq` | `gui.py:496-506, 600-602, 919-970` | Adding a detector type or changing outcome ordering breaks the UI |
| GUI **mutates** `skill.required_buttons` and `skill.raw` in place, then `isinstance(TapDetector)` | `gui.py:719-723` | Config is no longer immutable; the mutation path is regex-based and can corrupt the source file |
| Engine owns presentation: `self.out` is a `TextIO`, `_render_debug()` writes ANSI cursor control | `engine.py:426-462` | The engine has an opinion about terminals; on Android there is no terminal |
| Engine invokes `on_tick()` which runs rendering + synchronous log flush inside the sample budget | `gui.py:593-621` | Rendering cost lands inside the timing-critical loop; `%APPDATA%` flush latency can cause sampling overruns |
| `outcome_seq` as a change token | `engine.py:148` | Polling instead of notifying; forces the UI to hold a copy of the engine's integer |

### The replacement

**1. Signals out, snapshot in.** No polling, no internals.

```gdscript
# GestureRuntime (L1) exposes exactly this surface to the UI:
signal outcome_recorded(outcome: Outcome)
signal session_reset()
signal sample_gap(reason: StringName, dt_ms: float)
signal device_changed(name: String, connected: bool)

func snapshot() -> SessionSnapshot   # safe to call any time after setup()
```

```gdscript
class_name SessionSnapshot extends RefCounted
var revision: int                  # monotonic; UI can skip work when unchanged
var skills: Array[SkillSnapshot]   # name, kind, hits, attempts, group_hits, groups_done, failures, status_text
var last_outcome: Outcome          # nullable
var frames: int
var sampled_hz: float
var last_dt_ms: float
var p95_dt_ms: float
var gap_count: int
var rumble_available: bool
var rumble_failures: int
```

`SkillSnapshot.status_text` is the **only** place detector `status()` strings surface. The engine builds them; the UI renders them as opaque text. The UI never holds a `Detector`.

**2. Commands, not mutations.** Every UI-initiated change is a method on the engine/runtime:

```gdscript
runtime.set_modifier(skill_index: int, buttons: PackedStringArray) -> ConfigResult
runtime.reset_session() -> void
runtime.set_skill_enabled(skill_index: int, enabled: bool) -> void
runtime.select_device(device_id: int) -> void
```

`set_modifier` does **not** rewrite the base config. It writes a sparse `user://config/overrides.json` (§Config Boundaries) and returns a `ConfigResult` with any validation error — which the UI renders. Python's regex segment-patching of `skills_config.json` cannot exist on Android (`res://` is read-only) and should not exist anywhere.

**3. Rendering cadence is the UI's problem, never the engine's.**

| Widget | Update cadence | Why |
|---|---|---|
| `SticksPlot` | every frame (`queue_redraw()`), 120-point ring buffer | Motion must be smooth |
| `StatsPanel` text | **10 Hz** via `Time.get_ticks_msec()` throttle | `Label.text = ...` triggers text shaping; at 120 Hz that is the most expensive thing in the frame |
| `OutcomeFeed` | on `outcome_recorded` only; also skip updating when the feed is scrolled away | Zero cost when idle |
| Status bar (Hz, gaps) | 2 Hz | Diagnostics, not animation |

**4. The core never logs.** `Log` is an L1/L3 subscriber to `outcome_recorded` and `sample_gap`, writing to `user://logs/trainer.log` with a bounded buffer flushed once per second (never inside the tick). Python's per-line `flush()` inside the loop is a documented bottleneck (`CONCERNS.md` §Performance 1) — do not reproduce it.

**5. Config is immutable after load, and that is testable.**

```gdscript
# tests/unit/test_config_immutability.gd
var before := cfg.to_dict()
# ... run a synthetic session, fire every skill, call every UI command ...
assert_eq(cfg.to_dict(), before, "AppConfig mutated during a session")
```

This one test kills the entire class of Python bug #8 and the `isinstance(TapDetector)` special-case.

---

## Config Boundaries

### Pipeline

```
shared/skills_config.json                       ← the ONLY hand-edited copy
        │
        │ tools/sync_config.py  (run: `uv run tools/sync_config.py`)
        │   • copy → mobile/assets/config/skills_config.json
        │   • compute sha256 → skills_config.sha256
        │   • regenerate  mobile/assets/config/config_stamp.gd:
        │         const EXPECTED_SHA256 := "<hex>"
        │         const SKILL_COUNT := 5
        │   • fail if the destination differs and --check was passed (CI gate)
        ▼
mobile/assets/config/skills_config.json  (committed, marked generated)
        │
        │ export_presets.cfg:  include_filter="*.json"     ← REQUIRED
        ▼
res://assets/config/skills_config.json   (inside the PCK, read-only)
        │
        ├── optional sparse merge ◄── user://config/overrides.json
        │                              (only keys the user changed: modifiers, enabled)
        ▼
ConfigLoader.load_text() → ConfigValidator.validate() → AppConfig | Array[ConfigError]
```

### Five rules, all of them load-bearing

1. **`res://` is read-only in an export. Never write there.** Python could (and did) rewrite the config file. On Android that must become an `overrides.json` overlay in `user://`. Overrides carry `schema_version` and a `base_sha256`; if the base hash changes, **discard the overrides** and log `"配置已更新，已重置自定义按键"`. Silent stale overrides are worse than losing them.

2. **`.json` under `res://` is a non-resource file.** It is only packed if the export preset's **"Filters to export non-resource files"** includes `*.json`. There are shipping reports in both directions across Godot versions (a file being packed with an empty filter, and a file missing despite the filter — godotengine/godot#39380). **Therefore:**
   - set `include_filter="*.json"` in `export_presets.cfg`;
   - add an **export smoke test**: build the APK, launch it, and assert the boot screen shows the skill count (not the config-error screen). This is a release-gate item, not a nice-to-have.
   - keep the `config_stamp.gd` hash check as the tripwire: at boot, hash the loaded bytes and compare to `EXPECTED_SHA256`. Mismatch → loud error screen, not silent behaviour change.

3. **Load and validate in one place, at boot, before the first tick.** `GestureRuntime._ready()` must not tick before config is resolved (`if not _configured: return`). Godot calls child `_ready()` **before** parent `_ready()` — so do composition in `Main._ready()`, which runs *last*, and only then call `runtime.setup(...)`. Getting this backwards yields one or two ticks with a null engine.

4. **`assert()` is stripped from release builds — never use it for user-facing validation.** Return `ConfigError` objects. Android has no console, so `push_error()` alone is invisible to the user.

5. **Fail loudly = an error *screen*, not a stack trace.** Android users cannot read `stderr`.

### `ConfigError` and the error screen

```gdscript
class_name ConfigError extends RefCounted
var json_path: String     # e.g. "skills[3].params.max_duration_ms"
var code: StringName      # &"must_be_greater", &"unknown_direction", &"bad_button", ...
var message: String       # Chinese, actionable
var fix_hint: String      # "把 max_duration_ms 调到 700，或把 hold_ms 之和降到 600 以下"
```

The error screen must show:
- the config source (`res://…` vs `user://overrides.json`),
- **every** error, not just the first (Python's `SystemExit` gives one at a time — an explicit improvement),
- the offending `json_path`,
- a "复制" button (Android log access is painful otherwise),
- a "恢复默认" button that deletes `user://config/overrides.json` and reloads.

### Validation parity, mechanically proven

Port the *semantic* checks from `config.py` (they are the real specification): non-empty `steps`, `sum(hold_ms) < max_duration_ms`, `max_duration_ms > min_duration_ms`, `exit_threshold < enter_threshold`, valid direction names, valid canonical buttons, `modifier_options` consistency, duplicate skill names, `start_angle` **must be scalar or null** (Python bug #1 — an array crashes at engine construction; make it a validation error), string booleans rejected, `null` numerics rejected with a friendly message (Python bugs #2, #3).

Then prove parity with a corpus:

```bash
uv run tools/check_config_parity.py
# for each fixture in tests/fixtures/configs/{valid,invalid}/*.json:
#   python  → (accept, sorted error codes)
#   godot --headless --path mobile -s res://tests/config_parity.gd -- <fixture>
#   assert identical accept/reject
```

Accept/reject parity is the requirement. Error-code parity is aspirational; message-text parity is not required.

### Schema hygiene

- **UTF-8 without BOM.** Python bug #4: a BOM breaks startup. `JSON.parse_string()` on a BOM-prefixed string returns `null` with a parse error. Detect a `0xEF 0xBB 0xBF` prefix explicitly and emit `&"bom_detected"` with the fix hint, rather than showing "JSON 解析失败".
- **Open schema.** Python keeps unknown params in `Skill.params`; do the same (`Dictionary`), so future detector params do not require a loader change. Validate only the keys the active detector type knows.

---

## Testability

### Headless runner (no plugin dependency)

```gdscript
# tests/run_tests.gd
extends SceneTree

func _init() -> void:
    var failures := 0
    var suites := [
        preload("res://tests/unit/test_geometry.gd"),
        preload("res://tests/unit/test_config_loader.gd"),
        preload("res://tests/unit/test_arc_detector.gd"),
        preload("res://tests/unit/test_sequence_detector.gd"),
        preload("res://tests/unit/test_tap_detector.gd"),
        preload("res://tests/unit/test_engine_arbitration.gd"),
        preload("res://tests/unit/test_rumble_sequencer.gd"),
        preload("res://tests/unit/test_architecture_lint.gd"),
    ]
    for suite in suites:
        failures += suite.new().run()
    print("FAILURES: %d" % failures)
    quit(1 if failures > 0 else 0)
```

Run: `godot --headless --path mobile -s res://tests/run_tests.gd`

`--script` requires the script to extend `SceneTree` (or `MainLoop`); `quit(exit_code)` makes it CI-gateable. This matches the project's existing culture (hand-rolled `check()` scripts, no pytest) and adds zero dependency. **GUT 9.x or GdUnit4 are the alternatives** — both are mature and CI-friendly, but they add an addon, a config file, and a second way to assert. For ~200 assertions over pure `RefCounted` classes, the 40-line runner is the better trade.

### Why `src/core/` is testable headlessly at all

Because it takes a timestamp as an argument. `ReplayerSource` reconstructs the sample stream from a file:

```gdscript
var sample := PadSample.new()
sample.t_ms = rec["t_ms"]           # from JSONL, not from Time
sample.rs_x = rec["rx"]
...
```

No scene tree, no display, no `Input`, no wall clock. A 3-second trace replays in milliseconds.

### Fixture format (JSONL, one sample per line)

```json
{"v":1,"meta":{"source":"desktop-250hz","pad":"Xbox Series X|03000000...","skill":"踩单车 Stepover","expect":"ok"}}
{"t_ms":0.0,"lx":0.0,"ly":0.0,"rx":0.02,"ry":0.00,"lt":0.0,"rt":0.0,"btn":[]}
{"t_ms":44.0,"lx":0.0,"ly":0.0,"rx":0.18,"ry":-0.62,"lt":0.0,"rt":0.0,"btn":[]}
```

- `t_ms` is relative to trace start. Detectors only use deltas; the engine's cooldowns use the same relative clock, so intervals are preserved exactly.
- A `meta` line declares the expected verdict sequence (`"ok"`, or `"wrong_start"`, or `"none"`). Tests assert the **sequence of `Outcome.code`** equals it — that is the real regression contract.

### Two fixture sources, both needed

| Source | How | What it proves |
|---|---|---|
| **Synthetic, generated by Python** | `tools/gen_trace_fixtures.py` reuses the existing Python trajectory builders and writes JSONL | Behavioural equivalence with the 182 existing detector/engine checks. Commit the output; regenerate on demand. |
| **Decimated 250 Hz → 60/90/120 Hz** | `tools/decimate_trace.py` | **The critical experiment:** does the 60 Hz sample stream produce the same verdicts as 250 Hz? This directly answers the project's stated risk "需要实测确认时序抖动可接受". |
| **On-device capture** | `GodotRuntime` writes `user://traces/<timestamp>.jsonl` for every gesture (ring-buffered, 2 s pre-roll); pull with `adb pull` | Ground truth. Decimation is a proxy; only a real phone reproduces real latency. |

**Decimation rule (do not get this wrong):** pick the sample nearest each `1000/hz` boundary, **but never drop a button edge**. If a window contains a press or release, emit that sample at its actual timestamp too. Tap detection counts rising edges; dropping one turns a double-tap into a single tap.

### The architecture lint test (cheapest high-value test in the project)

```gdscript
# tests/unit/test_architecture_lint.gd
const FORBIDDEN := ["Input.", "Time.", "get_tree(", "OS.", "FileAccess", "DisplayServer", "print("]
# walk res://src/core/**/*.gd, read each file, assert no forbidden token appears
```

Rationale: determinism is a property you either enforce or lose. Without this test, someone will "just call `Time.get_ticks_msec()`" inside a detector in month two, and the replay harness silently becomes untrustworthy.

Companion lint: `src/core/**` must not `preload("res://src/platform` or `res://src/ui`.

### Mapping the 230 Python checks to GDScript

| Python suite | Count | GDScript home | Notes |
|---|---|---|---|
| Detector + engine (`tests/test_detectors.py`) | 182 | `test_arc/sequence/tap_detector.gd`, `test_engine_arbitration.gd` | Port each `check()` as an assertion on the same synthetic input. The synthetic trajectories become JSONL fixtures (generated once, committed). |
| GUI smoke (`tests/test_gui_smoke.py`) | 48 | `test_engine_arbitration.gd` + a small `test_snapshot.gd` | Python's GUI tests call `Engine._tick()` directly — that is a **bug**, not a pattern. In GDScript, test `GestureEngine` through its **public** `tick()` and `snapshot()`. Do not port the private-method coupling. |
| Timing (`250 Hz ±25 over 0.9 s`) | 1 | **Delete.** | Not meaningful on a variable-rate main loop. Replace with `assert(p95_dt_ms < 2 × nominal_dt)` on a recorded trace. |

---

## Anti-Patterns

### Anti-Pattern 1: Detection in `_physics_process`

**What people do:** "Physics runs at a fixed rate, so my ms-based detectors will see uniform Δt."
**Why it's wrong:** Physics ticks are decoupled from the render frame. A 33 ms frame produces **two** physics calls with an *identical* joypad snapshot (input is pumped once per process frame). The second call has a later timestamp and unchanged axes: motion latches expire, `elapsed_ms` inflates, `idle_timeout_ms` fires early. When the engine can't keep up, `max_physics_steps_per_frame` caps catch-up and physics time silently falls behind wall time.
**Do this instead:** `_process` + `Time.get_ticks_usec()` deltas, one sample per frame.

### Anti-Pattern 2: `_process(delta)` used as the clock

**What people do:** `elapsed += delta`, then compare against `max_duration_ms`.
**Why it's wrong:** `delta` is clamped at `max_physics_steps_per_frame / physics_ticks_per_second` (default ≈ 133 ms) and may be smoothed. A 300 ms Android stall is reported as 133 ms — a gesture that took 400 ms scores as 400 ms or as 267 ms depending on where the stall landed. Verdicts become non-reproducible.
**Do this instead:** timestamps only. `dt_ms = now_ms - last_ms`.

### Anti-Pattern 3: The engine as an autoload

**What people do:** register `GestureEngine` as a singleton so "anyone can access it".
**Why it's wrong:** that is the Python defect with better syntax — global reachability is exactly how the GUI ended up reading `engine.skills[i].detector`. It also makes tests order-dependent (state leaks between suites).
**Do this instead:** `Main._ready()` builds the graph, injects it into `GestureRuntime`, and connects signals. One composition root.

### Anti-Pattern 4: Config objects as `Resource`

**What people do:** make `Skill` a `Resource` "because Godot".
**Why it's wrong:** Resources are cached **by path** — two `load()` calls return the *same instance*. A UI that mutates `skill.required_buttons` mutates it for every consumer, in every scene, forever. This is precisely Python bug #8 with worse blast radius.
**Do this instead:** plain `RefCounted`, constructed by the loader, never mutated. Optionally generate a `.tres` *cache* at build time, but always `duplicate(true)` on read.

### Anti-Pattern 5: `assert()` for config validation

**What people do:** `assert(p.max_duration_ms > p.min_duration_ms, "bad config")`.
**Why it's wrong:** `assert()` is **removed from release exports**. Your shipped APK accepts the bad config and then divides by zero — or worse, silently mis-scores. And `assert` output goes to a console Android users cannot see.
**Do this instead:** accumulate `ConfigError` objects in the validator; render them on an error screen with `json_path` + `fix_hint`.

### Anti-Pattern 6: `InputMap` actions for the detection path

**What people do:** define actions `stick_right`, `trigger_left` in Project Settings and read `Input.get_vector()` / `get_action_strength()`.
**Why it's wrong:** the action deadzone is applied *before* you see the value. Godot has several distinct deadzones that are not the project's `input.deadzone = 0.08` + rescale: the `InputMap.add_action()` default deadzone (changed 0.5 → 0.2 in Godot 4.4), the per-event `InputEventJoypadMotion.deadzone`, and `Input.get_vector()`'s own argument. You lose the raw magnitude that `enter_threshold = 0.72` depends on, and which deadzone you actually got becomes version-dependent.
**Do this instead:** `Input.get_joy_axis()` raw + your own deadzone, exactly as `PygameJoystickSource` does. Reserve `InputMap` for UI navigation only.

### Anti-Pattern 7: `await get_tree().process_frame` in the sampling path

**What people do:** yield "to avoid blocking".
**Why it's wrong:** it inserts a frame of latency and destroys replay determinism (fixtures can no longer be driven synchronously).
**Do this instead:** never await inside `GestureEngine` or any detector. If something must be deferred (a file write, a scene switch), do it in an L1 subscriber after the tick returns.

### Anti-Pattern 8: Deep node paths from UI to engine

**What people do:** `get_node("../../GestureRuntime").engine.skills[0]`.
**Why it's wrong:** it is the Python coupling, expressed spatially. Renaming a node breaks detection tests.
**Do this instead:** `%UniqueName` for intra-scene lookups, signals for cross-component communication, `snapshot()` for reads.

### Anti-Pattern 9: Per-frame `Label.text` assignment

**What people do:** rebuild the stats text every `_process`.
**Why it's wrong:** text shaping dominates the frame on mobile GPUs/CPUs. Python's equivalent (`_text` re-rendering every string, ~2.73 ms per `_draw()`) is a documented bottleneck.
**Do this instead:** 10 Hz text throttle; compare against the previous string and skip the assignment when unchanged; `queue_redraw()` only the plot.

### Anti-Pattern 10: Logging with `print()` on Android

**What people do:** `print("outcome: ", o.code)`.
**Why it's wrong:** `print` goes to logcat, which a sideloaded user cannot read, and in a release export stdout may be unavailable. It also does synchronous I/O inside the hot path.
**Do this instead:** a bounded in-memory ring buffer flushed to `user://logs/trainer.log` once per second, plus an in-app "导出日志" button that copies the path.

---

## Integration Points

### External Services / Engine APIs

| API | Integration pattern | Gotchas |
|---|---|---|
| `Input.get_joy_axis` / `is_joy_button_pressed` | Polled once per `_process` by `GodotInputSource` | Raw values, no deadzone. Triggers 0..1 (verify per device). Order of `get_connected_joypads()` is not stable across restarts |
| `Input.joy_connection_changed` | Signal → `GestureRuntime` → `engine.on_device_lost()` / reconnect overlay | Fires during scene setup too; guard on `_configured` |
| `Input.start_joy_vibration(id, weak, strong, duration_s)` | `GodotRumbleSink.start(pulse)`; `Pulse{duration_ms, low→strong, high→weak}` | `duration = 0` means ~65 s, never "one frame". `has_joy_vibration()` gates the attempt. Android reliability is device-dependent → must degrade silently. Keep the belt-and-braces `stop_joy_vibration()` at the sequencer deadline because backends disagree on expiry |
| `Time.get_ticks_usec()` | `GestureRuntime` only | Monotonic, since engine start. Do **not** use `Time.get_unix_time_from_system()` (not monotonic, and jumps on NTP sync) |
| `NOTIFICATION_APPLICATION_PAUSED` / `_RESUMED` | `Main._notification()` → `runtime.set_suspended(true/false)` | Android can deliver PAUSED twice (`godotengine/godot#85265`). Make the handler idempotent. On resume, force `engine.on_time_discontinuity()` — `Time.get_ticks_usec()` keeps counting across the suspension |
| `FileAccess` + `JSON.parse_string` | `ConfigLoader` | `res://` read-only; `.json` needs `include_filter`; BOM must be rejected explicitly |
| `user://` | Overrides + logs + traces | Survives app updates; deleted on uninstall. Include it in "导出诊断" |

### Internal Boundaries (what may talk to what)

| Boundary | Communication | Rule |
|---|---|---|
| `Main` ↔ `GestureRuntime` | direct method calls (`setup`, `snapshot`) + signals | `Main` is the only node that calls `setup` |
| `GestureRuntime` → `GestureEngine` | `engine.tick(sample) → Array[Outcome]` | engine never calls back into the runtime |
| `GestureEngine` → `Detector` | `update/reset/on_idle/abandon/observe/pop_failure/status` | exactly the 7-method Python contract; no extra surface |
| `GestureEngine` → `RumbleSink` | via `RumbleSequencer.try_play(pulse, t_ms)` | engine never calls `Input` |
| UI → `GestureRuntime` | `snapshot()` read + command methods | UI never imports `Detector`, `Skill`, or `ActiveSkill` |
| UI ← `GestureRuntime` | signals (`outcome_recorded`, `sample_gap`, `device_changed`) | no polling integers (`outcome_seq` is dead) |
| `ConfigLoader` → everyone | returns `AppConfig` or `Array[ConfigError]` | never throws, never asserts, never partially populates |

---

## Build Order Implications for the Roadmap

Dependencies are strict; the order below is the only one that does not force rework.

```
Phase 1  Repo split + shared config sync + desktop 230 checks green          [BLOCKS ALL]
            └─ tools/sync_config.py, sha256 stamp, include_filter
Phase 2  src/core/domain + geometry.gd  (pure GDScript, headless)            [BLOCKS 3,4]
            └─ golden table: GDScript vs Python to 1e-9
Phase 3  ConfigLoader + ConfigValidator + parity corpus                      [needs 2]
            └─ accept/reject parity proven against Python
Phase 4  Detectors (arc, sequence, taps) + trace fixtures + decimation       [needs 2,3] ★ HIGHEST RISK
            └─ 182 behavioural checks replayed at 250/120/60 Hz
Phase 5  GestureEngine + arbitration + snapshot + RumbleSequencer            [needs 4]
            └─ headless, driven by ReplayerSource
Phase 6  Platform adapters + GestureRuntime + desktop-runnable demo          [needs 5]
            └─ runs on macOS with ReplayerSource and with a real pad
Phase 7  UI: sticks plot, stats, outcome feed, error screen                  [needs 5,6]
Phase 8  Android device layer: button map, axis probe, hotplug, lifecycle    [needs 6]
Phase 9  Rumble adapter: capability gate, silent degrade                     [needs 5,6]
Phase 10 Android export + on-device trace capture + regression vs decimated  [needs all]
```

**Ordering rationale:**

- **Phase 4 before any UI.** The detectors are the only part where "does it match the desktop?" is a real question. Building UI first makes every detector bug look like a UI bug, and the 182-check spec gets ported against a moving target.
- **Phase 5 before Phase 6.** `GestureEngine` must be provably correct on synthetic traces before a real controller can introduce nondeterminism. If the engine only ever runs against `Input`, you cannot tell a detector bug from an input-latency artefact.
- **Phase 6 before Phase 7.** A `ReplayerSource`-driven desktop run and a `DemoSource`-equivalent (Python's `DemoSource` mapped a scripted loop onto `PadState`) give you a UI you can develop against with zero controllers, exactly as `--demo` did. Do not build UI against real hardware.
- **Phase 8 after Phase 6, not in parallel with Phase 4.** Device work is the only part that cannot be unit-tested. It must land on a stable core so failures are unambiguous.
- **Phase 9 last among features.** Rumble is explicitly "尽力而为" and must never block a phase. If `has_joy_vibration()` is false or the call fails, the trainer is unchanged.

**Phase-specific research flags (deeper research needed before planning that phase):**

| Phase | Why it needs research |
|---|---|
| 4 | Whether 60 Hz decimation preserves verdicts for `release_hold_ms=120` and `global_cooldown_ms=60`. This is empirical; run the decimation matrix before committing thresholds. |
| 8 | Godot trigger axis range and `JoyButton` mapping per device (Xbox BT vs DualSense BT on Android). `Input.get_joy_info()` returns an **empty dict on Android**, so device identification is weaker than on desktop. Build the axis probe first. |
| 9 | Android rumble support matrix per pad/firmware. Python's multi-backend fallback does not exist in Godot — there is exactly one API. Design for "silently does nothing". |
| 10 | Whether `.json` lands in the PCK on the pinned Godot version. Needs one real export, not documentation reading. |

---

## Sources

| Claim | Source | Confidence |
|---|---|---|
| `_process` runs once per idle frame, before rendering, after physics ticks | Godot docs, `Node._process` | HIGH |
| `_process(delta)` is clamped to `time_scale * max_physics_steps_per_frame / physics_ticks_per_second`; "accumulated delta may not represent real world time" | Godot docs, `Node._process` (verbatim) | HIGH |
| `delta` may be post-processed by delta smoothing (`application/run/delta_smoothing`) | Godot docs, ProjectSettings | HIGH |
| `_physics_process(delta)` runs once per physics tick with `delta = time_scale / physics_ticks_per_second` | Godot docs, `Node._physics_process` | HIGH |
| `Time.get_ticks_usec()` is monotonic, int64, since engine start | Godot docs, `Time`; "guaranteed to be monotonic" | HIGH |
| `Input.get_joy_axis` returns the raw axis value; deadzone applies to *actions*, not raw reads (`get_action_raw_strength` exists "ignoring the action's deadzone") | Godot docs, `Input` | HIGH |
| `Input.use_accumulated_input` defaults true and "limits the number of input method calls per second to the rendering FPS" | Godot docs, `Input.use_accumulated_input` | HIGH |
| `input_devices/buffering/agile_event_flushing` flushes before every idle *and* physics frame; "Currently implemented only on Android" | Godot docs, ProjectSettings | HIGH |
| `Engine.max_fps` cannot exceed the display refresh rate when vsync is enabled | Godot docs, `Engine.max_fps` | HIGH |
| `Input.joy_connection_changed(device, connected)` signal | Godot docs, `Input` signals | HIGH |
| `Input.has_joy_vibration` / `start_joy_vibration(device, weak, strong, duration_s)`; duration 0 ≈ 65 s | Godot docs, `Input` | HIGH |
| `Input.get_joy_info()` returns an empty dictionary on Android | Godot docs, `Input.get_joy_info` | HIGH |
| `Input.get_connected_joypads()` order is not guaranteed across restarts | Godot docs, `Input` | HIGH |
| `JoyButton` is the SDL logical layout (A=0, B=1, X=2, Y=3, BACK=4, GUIDE=5, START=6, LS=7, RS=8, LB=9, RB=10, DPAD 11–14) | Godot docs, `@GlobalScope.JoyButton` | HIGH |
| `--script` requires a script extending `SceneTree`/`MainLoop`; `quit(exit_code)` sets the process code | Godot docs, command-line tutorial; `SceneTree.quit` | HIGH |
| `NOTIFICATION_APPLICATION_PAUSED`/`_RESUMED` are Android/iOS-only, delivered to nodes; PAUSED can fire twice | Godot docs, `Node` constants; godotengine/godot#85265 | HIGH / MEDIUM |
| `.json` under `res://` requires the export "non-resource files" filter; behaviour has varied by version | Godot docs, exporting projects; godotengine/godot#39380; community reports | MEDIUM |
| `assert()` is removed from release builds | Godot docs, GDScript `assert` | HIGH |
| Triggers report 0..1 through `JOY_AXIS_TRIGGER_*` on SDL game-controller mappings | Godot `InputEventJoypadMotion.axis_value` documents −1..1; SDL GameController returns 0..32767 | **MEDIUM — verify on device** |
| Android gamepad vibration reliability varies by pad and firmware | Project constraint in `PROJECT.md`; community reports | MEDIUM |
| Detector sample-rate sensitivity analysis (tables in §Timing) | Derived from `shared/skills_config.json` values and `padskills/detectors.py` | HIGH (arithmetic), MEDIUM (behavioural impact until fixtures confirm) |

---

*Architecture research for: Godot 4 gesture-detection trainer port*
*Researched: 2026-11-04*
