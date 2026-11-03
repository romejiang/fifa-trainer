---
last_mapped_commit: 5e489a15e4c8cbbfdedcb5239242264ab5394e66
last_mapped_at: 2026-11-04
---
# Coding Conventions

**Analysis Date:** 2026-11-04

## Language Split (the defining convention)

This codebase deliberately mixes two languages, and the boundary is strict:

| Layer | Language | Examples |
|-------|----------|----------|
| Identifiers (modules, classes, functions, variables, dataclass fields) | **English, ASCII only** | `build_detector`, `relative_to_ls`, `_pending_failure`, `ArcDetector` |
| JSON / config keys | **English snake_case** | `required_button`, `max_duration_ms`, `relative_to_ls` |
| Docstrings (module, class, function) | **Chinese** | `"""右摇杆画弧 / 转圈识别。"""` (`padskills/detectors.py:126`) |
| Inline comments | **Chinese** | `# 迟滞必须成立，否则会在阈值附近疯狂抖动` (`padskills/detectors.py:139`) |
| User-facing output, logs, UI labels | **Chinese** | `"转得不够：只转了 {n}°"`, `"做对了"`, `"待机"` |
| Exception / validation messages | **Chinese** | `f"动作 {name!r} 的 type 必须是 'arc'、'sequence' 或 'taps'，收到 {...!r}"` |
| Commit messages / README | Chinese | `README.md` is entirely Chinese |

**Verified:** an AST scan of every `.py` file finds **zero** identifiers containing CJK characters. Chinese appears only inside string literals and comments. Do not introduce Chinese identifiers, and do not write English docstrings — 103/103 docstrings in `app.py`, `main.py`, and `padskills/*.py` are Chinese.

Exception: Chinese is used as *data*, not as an identifier, in `DIRECTION_ALIASES` (`padskills/config.py:84-95`), e.g. `"前": 0.0, "右上": 45.0`. Config authors may write either `"forward"` or `"前"`; both must keep working.

## Naming Patterns

**Files:**
- Modules: one lowercase word, no underscores — `geometry.py`, `detectors.py`, `engine.py`, `rumble.py`, `gui.py`, `config.py`, `input_source.py`.
- Entry points: `app.py` (GUI/packaged), `main.py` (CLI).
- Tests: `tests/test_<subject>.py` — `test_detectors.py`, `test_gui_smoke.py`.

**Functions / methods:**
- `snake_case`, verb-first: `resolve_direction`, `parse_step`, `build_detector`, `pick_backend`, `open_source`, `ensure_user_config`.
- Private helpers carry a single leading underscore: `_parse_skill`, `_clamp01`, `_layout_from_mapping`, `_tick`, `_drain_failures`, `_render_debug`. 109 such definitions exist across `padskills/` and `main.py`.
- Predicate helpers read as questions: `is_frozen()`, `_buttons_ok()`, `_modifier_held()`, `_hat_matches()`.
- Pure helpers are `@staticmethod`: `Engine._buttons_ok` (`padskills/engine.py:387`), `Engine._angle_cell` (`:418`), `TrainerApp._stick_point` (`padskills/gui.py:881`), `TrainerApp._short_name` (`:875`).

**Classes:**
- `PascalCase`, domain nouns: `ArcDetector`, `SequenceDetector`, `TapDetector`, `AppConfig`, `PadState`, `RumbleEngine`, `TrainerApp`.
- Private/internal classes and test doubles get `_`: `_NullWriter` (`padskills/engine.py:19`), `_Sink` (`padskills/gui.py:268`), `_Segment`, `_Binding`.
- Base classes describe the role: `Detector`, `GamepadSource`, `RumbleBackend`.

**Variables and fields:**
- `snake_case`. Unit suffixes are mandatory and meaningful:
  - `_ms` for milliseconds: `hold_ms`, `cooldown_ms`, `idle_timeout_ms`, `release_hold_ms`, `duration_ms`.
  - `_deg` for degrees: `initial_facing_deg`, `tolerance_deg`, `claim_margin_deg`.
  - `_hz` for frequency: `poll_hz`.
  - `_threshold` for normalized 0..1 magnitudes: `enter_threshold`, `trigger_threshold`, `ls_facing_threshold`.
  - `_mag` / `_angle` for polar components: `rs_mag`, `rs_angle`, `ls_mag`.
  - `_at` / `_since` / `_t0` for timestamps: `started_at`, `_release_since`, `t0`.
- Temporary accumulation fields use short mathematical names: `acc`, `t0`, `lo`, `hi`, `avg`, `n`.
- Booleans read as state, not actions: `armed`, `active`, `neutral`, `_have_last`, `_gesture_locked`, `facing_valid`.

**Constants:**
- Module-level: `UPPER_SNAKE` — `DEFAULT_CONFIG`, `CANONICAL_BUTTONS`, `BUTTON_ALIASES`, `DIRECTION_ALIASES`, `FAILURE_LABELS`, `LOG_MAX_BYTES`, `APP_TITLE`.
- Class-level config knobs: `UPPER_SNAKE` inside the class — `Engine.GROUP_SIZE = 10`, `Engine.IDLE_STICK = 0.20`, `Engine.RELEASE_STICK = 0.35` (`padskills/engine.py:93-98`), `TrainerApp._HISTORY_ROWS = 5` (`padskills/gui.py:314`).
- Failure codes are lowercase snake_case English tokens (`too_fast`, `wrong_start`, `hold_short`) mapped to Chinese labels in `Detector.FAILURE_LABELS` (`padskills/detectors.py:65-76`). Add a new code only together with its label and a GUI advice line in `_ADVICE` (`padskills/gui.py:54-65`).

**Button / axis naming:**
- Canonical button names are UPPER (`"A"`, `"LB"`, `"RS"`, `"DPAD_UP"`) and normalized by `canonical_button()` (`padskills/input_source.py:63`). PlayStation aliases (`L1`→`LB`, `R2`→`RT`) are accepted at the boundary and must be converted immediately.
- Raw axis keys are lowercase (`"ls_x"`, `"rs_y"`), matching config keys in `input.invert`.

**Tests:** see `TESTING.md`. Test functions use `test_<behavior>`; helpers do not.

## Code Style

**Formatting:**
- **No formatter, no linter, no type checker is configured.** `pyproject.toml` contains only `[project]` and `[project.optional-dependencies]`; there is no `[tool.ruff]`, `[tool.black]`, `[tool.mypy]`, `.flake8`, `setup.cfg`, or `.editorconfig`.
- 4 spaces, no tabs, LF line endings (enforced for `*.py` by `.gitattributes`), UTF-8, final newline, no trailing whitespace (verified clean).
- **Soft line limit ~100 characters**, but not enforced. Measured distribution across source and tests: 6,636 lines ≤88 chars, 232 lines 89–100, 147 lines 101–120, 15 lines >120. Aim for ≤100; long Chinese docstrings and message strings routinely run to ~120. Wrap function calls with hanging indent rather than compressing arguments:
  ```python
  backend = pick_backend(
      candidates,
      strength=cfg.rumble.startup_test_strength,
      duration_ms=cfg.rumble.startup_test_ms,
      verbose=verbose,
  )
  ```
- **Double quotes** for essentially all code strings (~1,845 double-quoted literals vs ~100 single-quoted, most of which quote words inside Chinese prose). Use `'...'` only when nesting quotes inside a string.
- **f-strings only** (262 occurrences). No `%` formatting and no `.format()` anywhere.
- Two blank lines between top-level definitions; one blank line between methods. Dataclass fields may be grouped without blank lines, with aligned inline comments:
  ```python
  @dataclass
  class Skill:
      name: str
      kind: str                                  # "arc" | "sequence" | "taps"
      enabled: bool = True
      relative_to_ls: bool = False
  ```
- Section separators are exactly `# ` + 75 dashes (77 chars), surrounded by blank lines:
  ```python
  # ---------------------------------------------------------------------------
  # 解析
  # ---------------------------------------------------------------------------
  ```
  Used 38 times. Keep the width identical.
- No trailing commas required, but multi-line literals do use them (`padskills/detectors.py:23-24`).

**Linting / typing:** none automated. Type hints are best-effort, not verified: 250 of 294 functions have return annotations, but parameters are sometimes untyped at boundaries (`buttons`, `cfg`, `rect`, `active`). Do not add a mypy gate without a project decision; do keep new public functions annotated.

## Type Hints and Data Modeling

- **Every module starts with `from __future__ import annotations`** (11/11 files). This is mandatory.
- **Use `typing` generics, not PEP 585 builtins**, even though `requires-python = ">=3.11"`:
  ```python
  from typing import Any, Dict, List, Optional, Tuple
  angles: Tuple[float, ...]
  skills: List[Skill]
  params: Dict[str, Any]
  ```
  There are **zero** occurrences of `list[...]`, `dict[...]`, `tuple[...]`, or `set[...]` in the codebase. Match the existing style; do not "modernize" one file at a time.
- `Optional[X]` (not `X | None`), `FrozenSet[str]` for button sets, `Sequence[Pulse]` for read-only inputs, `Callable[[float, PadState], None]` for callbacks, `TextIO` for output streams.
- `Any` is reserved for untyped JSON boundaries (`Skill.params`, `InputConfig.axis_layout`, `list_devices()` results) — 32 uses, almost all in `config.py` / `input_source.py`.
- **`dataclasses` are the data-structure idiom**: 14 `@dataclass` declarations.
  - `frozen=True` for immutable value objects: `Pulse`, `Step` (`padskills/config.py:133,177`), `PadState` (`padskills/input_source.py:81`), `_Binding` (`:181`).
  - Mutable dataclasses for objects that accumulate or are edited after parsing: `Skill`, `InputConfig`, `RumbleConfig`, `AppConfig`, `Frame`, `Hit`, `Failure`, `Outcome`, `ActiveSkill`, `AxisLayout`.
  - Use `field(default_factory=...)` for mutable defaults (`Dict`, `List`), never a bare `{}` / `[]`.
  - `__slots__` is used only for the tiny `_Segment` (`padskills/gui.py:149-150`).
- **No `Enum`, no `Protocol`, no `ABC`, no `TypedDict`, no `TypeAlias`.** State is encoded as strings (`kind`, `code`, `direction`, `backend`, `button_mode`) validated at parse time. Base classes raise `NotImplementedError` and document the contract in the docstring (`Detector.update`, `GamepadSource.poll`, `RumbleBackend.start`).
- Dataclass `__post_init__` is not used; validation lives in explicit `_parse_*` / `parse_step` / `resolve_direction` functions so errors carry the field path.

## Import Organization

**Order (follow this):**
1. Module docstring (Chinese, explains *why* the module exists).
2. `from __future__ import annotations`.
3. Standard library (`ctypes`, `json`, `math`, `os`, `sys`, `time`, `dataclasses`, `pathlib`, `typing`, `re`, `subprocess`).
4. Local package imports, relative inside `padskills/` (`from .config import ...`), absolute from `main.py` (`from padskills.config import ...`).
5. `__all__` immediately after imports.

```python
"""角度与向量工具。 ..."""

from __future__ import annotations

import math

__all__ = ["norm_deg", "signed_delta", "angle_diff", "angle_of", "magnitude"]
```

**Path aliases:** none. No `src/` layout, no `PYTHONPATH` tricks except the test bootstrap.

**Lazy imports are a rule, not an accident:**
- **Never import `pygame` at module scope.** It appears only inside functions: `main.py:124,264`, `padskills/gui.py:104,128,1282`, `padskills/input_source.py:364,611`. Reasons documented in code: `PYGAME_HIDE_SUPPORT_PROMPT` must be set before import (`main.py:21-22`), only needed subsystems are initialized, and CLI paths (`--list`, `--write-config`) must not pay for display init.
- Optional/hardware deps are imported inside the class/function that needs them: `import XInput` (`padskills/rumble.py:148`), `from pygame._sdl2 import controller` (`:72`, `padskills/input_source.py:572`), `import ctypes` in `enable_windows_ansi` (`padskills/engine.py:38`).
- **Function-local import to break a cycle** is acceptable and commented: `_parse_required_buttons` imports `canonical_button` from `.input_source` with `# 延迟导入避免循环依赖` (`padskills/config.py:510`).
- `app.py` and `main.py` do environment setup (stdout/stderr guards, `sys.path` insertion, `PYGAME_HIDE_SUPPORT_PROMPT`) **before** any heavy import (`app.py:17-29`, `main.py:21-29`).

**Known deviation — do not copy:** `padskills/engine.py` declares `__all__` at line 16, then defines `_NullWriter` and `enable_windows_ansi`, then imports its own package at lines 54–57, then declares a second `__all__` at line 59. New modules should keep all imports at the top.

## Error Handling

**Strategy: validate at the boundary, degrade at the UI/hardware boundary, never swallow in the logic core.**

1. **Config / data validation → `ValueError` with a Chinese, actionable message.** Include the offending value with `!r`, the field path, and the accepted range/values:
   ```python
   raise ValueError(
       f"动作 {name!r}: 各步骤 hold_ms 合计 {total_hold:.0f}ms 已经不小于 "
       f"max_duration_ms ({max_dur:.0f}ms)，这个动作永远无法触发，"
       f"请把 max_duration_ms 调大。"
   )                                            # padskills/config.py:571-576
   ```
   Use `raise ... from None` to suppress the chained traceback for expected user errors (10 occurrences, mostly in `config.py`).

2. **Environment / hardware failures → `RuntimeError`** with a Chinese remedy: no gamepad (`padskills/input_source.py:369-372`), index out of range (`:374-376`), pygame build lacks rumble (`padskills/rumble.py:55-56`), XInput on non-Windows (`:100`), DLL load failure (`:111`).

3. **Process-boundary errors → `SystemExit` with a formatted multi-line message.** `load_config()` converts `OSError`, `JSONDecodeError`, and `ValueError` into a single `SystemExit` that names the file, line, and column and gives a hint (`padskills/config.py:765-782`). `app.py:44` uses `SystemExit(0)` for `--help`. Nothing else may raise `SystemExit` — the GUI catches it explicitly and renders it as text (`padskills/gui.py:370-372`).

4. **No custom exception hierarchy.** Only `ValueError`, `RuntimeError`, `SystemExit`, and `KeyboardInterrupt` are used.

5. **Swallow only where a crash is worse than degradation.** There are 35 `except Exception` blocks (gui 14, rumble 9, input_source 6, main 5, engine 1) and **zero bare `except:`**. Accepted locations:
   - Optional backend probing: `build_backends` / `pick_backend` try each backend and skip failures (`padskills/rumble.py:184-189, 217-235`).
   - Rumble dispatch: `_safe_start` / `_safe_stop` catch, increment `failures`, store `_last_error`, and expose `health()` (`padskills/rumble.py:306-323`).
   - Windowed-app UI: display flip, log write, config-folder open, event pump, shutdown (`padskills/gui.py:430-432, 449-450, 537-538, 797-800, 1305-1308`). Packaged apps have no console, so failures are surfaced in the window (`self.error`, `self.config_error`, `self.notice`) and the diagnostic log.
   - Cleanup: `finally:` closes rumble/source/log (`padskills/engine.py:189-192`, `padskills/gui.py:406-407, 589-591`).
   **Rule:** do not add `except Exception: pass` in `geometry.py`, `config.py`, `detectors.py`, or `engine.py`'s decision paths. If you must catch there, count it and surface it like `RumbleEngine.health()`.

6. **Recognition failures are not exceptions.** They are data: `Failure(code, message, elapsed_ms)` (`padskills/detectors.py:49-58`), emitted once per attempt via `_emit()`, drained by `pop_failure()`, and turned into `Outcome` rows by `Engine._drain_failures()` (`padskills/engine.py:332-353`). This keeps the 250 Hz loop allocation-light and guarantees "one attempt → at most one failure message".

7. **`assert` is for internal invariants only**, and only in the GUI: `assert self.engine is not None` (`padskills/gui.py:494, 914, 1021`), `assert self.cfg is not None` (`:541`). Never use `assert` for input validation — it disappears under `python -O`.

## Logging

**Framework: none.** `logging` is never imported. Three deliberate channels:

1. **CLI user output — `print()`**, wrapped in presentation helpers:
   - `banner(text)` and `step(text)` draw the `═` / `▸` blocks (`main.py:57-65`).
   - Result lines use `[HH:MM:SS] ✓ <动作名>` / `[HH:MM:SS] ✗ <动作名> — <原因>` (`padskills/engine.py:365-368, 395-412`).
   - `--debug` is a single carriage-return-refreshed line; `--trace` writes two lines and moves the cursor with `\x1b[1A`, degrading gracefully when ANSI is unavailable (`padskills/engine.py:29-52, 426-462`).
2. **Injectable stream — `out: TextIO`.** `Engine.__init__(..., out=None)` defaults to `sys.stdout` or `_NullWriter` when stdout is `None` (`padskills/engine.py:100-111, 19-27`); `TrainerApp` passes `_Sink()` to keep the GUI console-silent (`padskills/gui.py:268-275, 556-557`). New library code that must emit text should accept an `out`/`logger` parameter rather than calling `print` — `pick_backend(..., logger=print)` (`padskills/rumble.py:210`) is the pattern.
3. **Diagnostic file log (GUI only).** `TrainerApp._open_log/_write_log/_diagnose` write to `user_config_dir()/trainer.log`: UTF-8 **with BOM** (Windows Notepad compatibility), `[HH:MM:SS.mmm]` prefix, truncated to `LOG_MAX_BYTES = 2_000_000` on startup, and every write wrapped in `try/except` (`padskills/gui.py:413-538`). It records the config path, controller mapping, resolved skill parameters, every button transition, and right-stick pushes sampled at ≥45 ms.

**Verbosity rule:** quiet by default. Success prints one line; failure detail requires `--feedback`; trajectory detail requires `--verbose`; per-frame telemetry requires `--debug`/`--trace`. Library functions take `verbose: bool = False` and print only when true (`build_backends`, `pick_backend`, `PygameJoystickSource`).

## Comments

**When to comment — always explain *why*, not *what*.** Comments are Chinese and frequently long (3–8 lines). The house style is to document the bug or physical constraint that forced the code:

```python

# 摇杆回落 -> 结束本次画弧；连续回中够久才重新武装。

# 不能一低于 exit 就立刻 armed=True，否则动作结尾轻轻一抖就会被当成下一次起手。

```

(`padskills/detectors.py:244-245`)

Other recurring comment subjects:
- Real-hardware measurements and device quirks (`padskills/rumble.py:1-12`, `padskills/input_source.py:165-168`).
- User-reported symptoms quoted directly: `"""用户报"往左扳着不动就一直震"。"""` (`tests/test_detectors.py:514`).
- Threshold/clock reasoning at 250 Hz (`padskills/detectors.py:308-309, 508-510`).
- "Why not the obvious approach" notes: no `pygame.init()`, no background thread, no queue (`padskills/gui.py:5-9`, `padskills/rumble.py:243-257`).

**Avoid:** commented-out code, `TODO`/`FIXME`/`HACK` markers (there are none), and English comments. Section banners use the 77-char dash rule described above.

**Docstrings:**
- Chinese, one-line summary ending in `。` when short; blank line then detail paragraphs for complex APIs.
- Use reStructuredText inline literals for identifiers: ``reset()``, ``abandon()``, ``"arc"`` (`padskills/detectors.py:88-93`).
- **No `Args:` / `Returns:` / `:param:` sections anywhere.** The docstring explains the contract, side effects, and failure semantics; the signature carries the types.

## Function Design

**Size:** small helpers dominate; the state machines are intentionally long (`ArcDetector.update` ~170 lines, `SequenceDetector.update` ~145 lines, `TrainerApp._skill_card` ~85 lines). Treat those as exceptions: if you touch a state machine, preserve the ordered early-return structure and the comment explaining branch order (`padskills/detectors.py:323-324`).

**Parameters:**
- Booleans as keyword flags with defaults: `debug=False, trace=False, verbose=False, feedback=False`.
- Configuration objects over long argument lists: `Engine(cfg, source, rumble, ...)`, `ArcDetector(skill)`.
- Optional dependencies default to `None` and are resolved inside (`out: TextIO = None`, `layout: Optional[Dict[str, Any]] = None`).
- Time is always injected as a float `now` (seconds from `time.perf_counter()`), never read inside a detector. This is what makes the tests deterministic — keep it.

**Return values:**
- `Optional[Hit]` / `None` for "did this frame complete an action".
- Explicit `bool` for success (`play()`, `start()`, `_open_device()`).
- `Tuple[bool, str]` when a caller needs an error message (`TrainerApp._persist_required_button`).
- `-> None` annotated on all void functions.
- Never return sentinel magic numbers; use `None` / `bool` / dataclasses.

**Local closures** are used for small context-bound helpers: `def axis(idx)` inside `poll()` (`padskills/input_source.py:492`), `def add(description, factory)` inside `build_backends` (`padskills/rumble.py:184`), `def hand(angle, color, on, width, ball)` inside `_draw_footer` (`padskills/gui.py:1154`), `def hold(...)` inside a test (`tests/test_detectors.py:524`).

## Module Design

**Exports:**
- Every public module declares `__all__` at the top (`config.py:18`, `detectors.py:23`, `geometry.py:20`, `input_source.py:30`, `rumble.py:23`, `gui.py:33`, `engine.py:16`).
- `padskills/__init__.py` intentionally re-exports **nothing** — only a module map docstring and `__version__ = "1.0.0"`. Import from submodules (`from padskills.config import load_config`), not from the package root.
- Underscore-prefixed names are private even when technically importable; tests do reach into them (`Engine._tick`, `app._draw`) by design, production code should not.

**Barrel files:** none. No `index`-style re-export modules.

**Dependency direction** (keep it acyclic):

```
geometry  ←  config  ←  detectors  ←  engine  ←  gui / main / app
                ↑            ↑            ↑
          input_source ──────┘       rumble ┘
```

`geometry` imports nothing local; `config` imports `geometry` plus a function-local `input_source`; `detectors` imports `config`, `geometry`, `input_source`; `engine` imports all of them; `gui`/`main` are top-level.

**Single source of truth:** default rules live in `DEFAULT_CONFIG` (`padskills/config.py:250-463`) and are written to `skills_config.json` by `dump_default_config` (`:785-790`). `skills_config.json` is generated data, not hand-maintained source — change `DEFAULT_CONFIG` and regenerate with `uv run main.py --write-config`, or edit both. The JSON itself carries a `_readme` string array (Chinese) documenting every field.

**Version:** `__version__` lives in `padskills/__init__.py`; `pyproject.toml` duplicates `version = "1.0.0"`. Keep them in sync manually.

## Domain Conventions (project-wide invariants)

**Angle convention — do not deviate** (`padskills/geometry.py:1-14`):

| Degrees | Direction |
|---------|-----------|
| 0° | up / forward |
| 90° | right |
| 180° | down / back |
| 270° | left |

- Range `[0, 360)`, increasing = clockwise on screen.
- SDL raw stick coordinates are `x` right-positive, `y` **down**-positive. All conversion happens in `angle_of(x, y)` (which returns `0.0` for a centered stick, not `atan2(0, -0)`'s 180°).
- Use `norm_deg`, `signed_delta` (shortest arc, `(-180, 180]`), `angle_diff` (`[0, 180]`) — never hand-roll modulo arithmetic.

**Units and clocks:**
- All durations in **milliseconds** with an `_ms` suffix; all rates in **Hz** with `_hz`.
- All timestamps are `time.perf_counter()` seconds passed explicitly as `now`; never mix `time.time()` into the recognition path. Wall-clock `time.strftime` is only for human log prefixes.
- Nominal loop rate is 250 Hz → 4 ms per frame; tests assume this step.

**Config semantics:**
- `relative_to_ls: true` means angles are measured from the left-stick facing direction; `false` means absolute screen direction.
- Left stick centered (`ls_mag < ls_facing_threshold`) means *no facing*, so all relative skills are ineligible (`padskills/engine.py:199-204, 267-271`).
- Buttons are normalized before comparison; never compare a raw config string to a `PadState.buttons` entry.

## Anti-Patterns (observed — do not repeat)

### Import after executable code

**What happens:** `padskills/engine.py` defines a class and a function before its package imports (`:19-57`) and declares `__all__` twice (`:16`, `:59`).
**Why it's wrong:** violates PEP 8, creates a false sense that lazy imports are needed, and the first `__all__` is stale.
**Do instead:** all imports at the top, single `__all__`, as in `padskills/geometry.py:8-20` and `padskills/rumble.py:14-23`.

### Class "docstring" after a class attribute

**What happens:** `padskills/gui.py:313-315` assigns `_HISTORY_ROWS = 5` and *then* places the class docstring string, so `TrainerApp.__doc__` is `None`.
**Why it's wrong:** the documentation is invisible to `help()`, IDEs, and doc tooling.
**Do instead:** docstring first, then attributes (see `Engine` at `padskills/engine.py:92-98`).

### Duplicated orchestration between CLI and GUI

**What happens:** rumble backend selection is implemented twice — `main.py:276-302` and `TrainerApp._build_rumble` (`padskills/gui.py:278-303`) — with slightly different verbosity.
**Why it's wrong:** a backend-priority change must be made in two places or the two entry points diverge.
**Do instead:** extract to `padskills/rumble.py` (e.g. `open_rumble(cfg, source, verbose)`) and call it from both.

### Direct `print()` inside reusable modules

**What happens:** `PygameJoystickSource._print_layout_report` (`padskills/input_source.py:453-480`) and `build_backends` (`padskills/rumble.py:189, 204, 206`) print directly.
**Why it's wrong:** the GUI cannot silence them except by redirecting `stdout`; it already needs `_Sink` for the engine.
**Do instead:** accept `out: TextIO` or `logger: Callable[[str], None]` as `pick_backend` does (`padskills/rumble.py:210`).

### Cross-cutting mutable shared state in tests

**What happens:** `test_button_taps` mutates the shared `Skill.required_buttons` and restores it manually (`tests/test_detectors.py:799-800`); GUI tests share module-level `_cfg`.
**Why it's wrong:** test order becomes load-bearing and a failed mid-test leaves global state dirty.
**Do instead:** build an isolated config per test with `parse_config(copy.deepcopy(DEFAULT_CONFIG))` as `test_config_validation` does (`tests/test_detectors.py:1156-1167`).

### Version duplicated across files

**What happens:** `padskills/__init__.py` and `pyproject.toml` both hard-code `1.0.0`.
**Why it's wrong:** packaged `--version` can disagree with the distribution metadata.
**Do instead:** read `importlib.metadata.version("fifa-skill-rumble")` with a fallback, or keep a documented manual sync step.

---

*Convention analysis: 2026-11-04*
