---
last_mapped_commit: 5e489a15e4c8cbbfdedcb5239242264ab5394e66
last_mapped_at: 2026-11-04
---
# External Integrations

**Analysis Date:** 2026-11-04

## Summary

This is a fully offline, local-only desktop application. It has **no network APIs, no HTTP client, no databases, no authentication providers, no cloud services, no telemetry, and no webhooks**. A repository-wide search for `requests|urllib|http://|https://|socket|websocket|aiohttp|httpx|api_key|token` in Python sources found zero network code.

The only external boundaries are **local hardware and OS interfaces**:
1. Gamepad HID input via SDL2 (through pygame-ce)
2. Gamepad rumble via four interchangeable backends (pygame-ce, SDL2, XInput ctypes, XInput-Python)
3. Local filesystem for JSON config and a diagnostic log
4. Platform shell/font/console facilities

## APIs & External Services

**Network services:**
- None. No third-party REST/GraphQL/SOAP API, no OAuth flow, no remote config, no update checker, no analytics.
- The only network activity in the whole project happens at **development time**, when `uv sync` downloads packages from PyPI (`uv.lock` records `source = { registry = "https://pypi.org/simple" }`). That is package installation, not a runtime integration.

**Local hardware — gamepad input:**
- SDL2 HID layer accessed through pygame-ce:
  - Enumeration: `pygame.joystick.get_count()` / `Joystick(index)` in `padskills/input_source.py:367-384`
  - Raw polling: `Joystick.get_axis()`, `get_button()`, `get_hat()`, refreshed by `pygame.event.pump()` each frame (`padskills/input_source.py:484-537`)
  - Device metadata: `get_name()`, `get_guid()`, `get_instance_id()`, axis/button/hat counts (`padskills/input_source.py:378-384`, `:609-629`)
  - Protocol-agnostic layout: queries SDL's GameController mapping database via `pygame._sdl2.controller.Controller.get_mapping()` (`padskills/input_source.py:569-602`), then parses mapping strings like `a2`, `-a1`, `b4`, `h0.1` (`padskills/input_source.py:189-255`)
  - Fallbacks when no SDL mapping exists: rest-value classification (250 ms calibration sample) at `padskills/input_source.py:258-292`, then a hard-coded XInput button order at `:296-304`, then optional manual `input.axis_layout` override in config (`padskills/input_source.py:391-395`)
- SDK/Client: `pygame-ce 2.5.8` (bundled SDL2)
- Auth: none; OS-level device permissions only (macOS Input Monitoring, Linux `/dev/input` access)
- Cable/transport is transparent: USB, wireless receiver, and Bluetooth all arrive through the same SDL interface (README documents XInput/DInput/Bluetooth support)

**Local hardware — rumble/haptics:**
- Four backends selected by `rumble.backend` (`auto | pygame | sdl2 | xinput | none`) in `padskills/rumble.py:175-207`:
  1. `pygame.joystick.Joystick.rumble(low, high, duration_ms)` — primary, verified working on the target device (`padskills/rumble.py:48-65`)
  2. `pygame._sdl2.controller.Controller.rumble()` — same device reports unsupported, kept as fallback (`padskills/rumble.py:68-83`)
  3. Direct `ctypes.WinDLL` on `Xinput1_4.dll`, falling back to `Xinput1_3.dll` then `Xinput9_1_0.dll`; calls `XInputSetState` / `XInputGetState` with a 2×`c_ushort` vibration struct (`padskills/rumble.py:85-141`)
  4. Optional `XInput` Python package (`XInput-Python>=0.4.0`, Windows-only extra) calling `XInput.set_vibration()` (`padskills/rumble.py:144-168`)
- Startup self-test probes backends in order and keeps the first that really vibrates (`padskills/rumble.py:210-235`); all rumble calls are non-blocking and driven from the 250 Hz main loop (`padskills/rumble.py:242-344`)
- No external haptics SDK, no game-process hooking, no memory reading, and no FIFA/EA FC integration of any kind — the app is purely a passive controller observer.

## Data Storage

**Databases:**
- None. No SQLite, Postgres, Redis, ORM, or embedded DB.

**File Storage:**
- Local JSON config file only: `skills_config.json`
  - Development: repository root, resolved by `padskills/config.py:60-64`
  - Frozen Windows: `%APPDATA%\FifaSkillTrainer\skills_config.json` (`padskills/config.py:49-53`)
  - Frozen macOS: `~/Library/Application Support/FifaSkillTrainer/skills_config.json` (`padskills/config.py:54-55`)
  - Linux: `$XDG_CONFIG_HOME/FifaSkillTrainer/` or `~/.config/FifaSkillTrainer/` (`padskills/config.py:56-57`)
  - First run of a packaged build writes the built-in defaults if missing (`ensure_user_config`, `padskills/config.py:67-77`)
  - The GUI can rewrite a single `required_button` value in place using a regex, without reformatting the rest of the user's file (`padskills/gui.py:732-754`)
- Diagnostic log: `<user_config_dir>/trainer.log`
  - Append-mode UTF-8 with BOM, 2 MB truncation threshold (`TrainerApp.LOG_MAX_BYTES`, `padskills/gui.py:413-450`)
  - Records session start, config path/mtime, device layout, per-skill parameters, button transitions, right-stick pushes, and outcomes (`padskills/gui.py:452-538`)

**Caching:**
- None persistent. In-memory only: font object cache (`FontCache`/`FontBook`, `padskills/gui.py:119-139`) and the 5-row GUI history list (`padskills/gui.py:314`, `:600-607`).

## Authentication & Identity

**Auth Provider:**
- None. No accounts, login, tokens, API keys, or user identity. The app never transmits data.
- OS trust prompts are the only gate: macOS Input Monitoring permission for gamepad access; unsigned macOS builds require Gatekeeper bypass (right-click → Open, or `xattr -dr com.apple.quarantine`), documented in `build/build_macos.sh` and README.

## Monitoring & Observability

**Error Tracking:**
- None (no Sentry, Crashpad, or remote reporting).

**Logs:**
- Console output in CLI mode (`main.py`, `padskills/engine.py`), including `--debug` single-line refresh and `--trace` two-line ANSI refresh (`padskills/engine.py:426-462`)
- File log in GUI mode at `<user_config_dir>/trainer.log` (`padskills/gui.py:415-450`)
- Windows console ANSI support is enabled via `kernel32.SetConsoleMode` with `ENABLE_VIRTUAL_TERMINAL_PROCESSING` (`padskills/engine.py:29-52`)
- Windowed builds null-guard `sys.stdout`/`sys.stderr` because PyInstaller `--windowed` sets them to `None` (`app.py:19-24`, `main.py:24-28`)

## CI/CD & Deployment

**Hosting:**
- None. This is a client-side desktop app distributed as a standalone executable.

**CI Pipeline:**
- None. No `.github/`, no workflow files, no GitLab CI, no Jenkins.
- Build is manual and per-OS:
  - Windows: `powershell -ExecutionPolicy Bypass -File build\build_windows.ps1` → `dist\FIFA-Skill-Trainer.exe`
  - macOS: `bash build/build_macos.sh` → `dist/FIFA Skill Trainer.app`
- PyInstaller cannot cross-compile, so each artifact must be built on its target OS.

**Packaging integration details:**
- `FIFA-Skill-Trainer.spec`: entry `app.py`, `hiddenimports=['pygame._sdl2.controller']` (required because the SDL2 controller module is imported dynamically), `excludes=['XInput']` (keeps the optional Windows package out of the bundle), `console=False`, `upx=False`.
- Build scripts add `--onefile` on Windows and `--osx-bundle-identifier com.fifaskill.trainer` on macOS.
- `skills_config.json` is deliberately **not** bundled; it is created in the user config directory on first launch so upgrades never overwrite user rules.

## Environment Configuration

**Required env vars:**
- None required. All are optional behavior switches:
  - `PYGAME_HIDE_SUPPORT_PROMPT=1` — suppress the pygame banner
  - `SDL_VIDEO_CENTERED=1` — center the window
  - `APPDATA` — Windows user config root
  - `XDG_CONFIG_HOME` — Linux user config root
  - `SDL_VIDEODRIVER=dummy` / `SDL_AUDIODRIVER=dummy` — test-only, set by `tests/test_gui_smoke.py`

**Secrets location:**
- Not applicable. No secrets, credentials, certificates, or `.env` files exist in the repository (verified: no `.env*` files, `.gitignore` excludes logs only).

## Webhooks & Callbacks

**Incoming:**
- None. No HTTP listener, no socket server, no IPC endpoint.

**Outgoing:**
- None. No outbound HTTP, DNS, or telemetry calls.
- Internal callbacks are in-process only: `Engine.run(on_tick=...)` lets the GUI render from the 250 Hz loop (`padskills/engine.py:154-192`), and rumble backends expose `start()`/`stop()`/`close()` (`padskills/rumble.py:30-45`).

## OS-Level Integrations

**Windows:**
- XInput DLL loading via `ctypes.WinDLL` (`padskills/rumble.py:98-122`)
- `kernel32` console mode for ANSI escape support (`padskills/engine.py:29-52`)
- `os.startfile()` to open the config folder (`padskills/gui.py:765-767`)
- Fonts: `C:\Windows\Fonts\msyh.ttc`, `msyhbd.ttc`, `simhei.ttf`, `simsun.ttc` (`padskills/gui.py:73-79`)

**macOS:**
- Config/log under `~/Library/Application Support/FifaSkillTrainer/` (`padskills/config.py:54-55`)
- Fonts: `/System/Library/Fonts/PingFang.ttc`, `Hiragino Sans GB.ttc`, `STHeiti Medium.ttc`, `/Library/Fonts/Arial Unicode.ttf` (`padskills/gui.py:80-86`)
- Opens folders with `subprocess.Popen(["open", ...])` (`padskills/gui.py:768-770`)
- Unsigned `.app` distribution; requires manual Gatekeeper approval and Input Monitoring permission

**Linux:**
- Config/log under `$XDG_CONFIG_HOME` or `~/.config` (`padskills/config.py:56-57`)
- Fonts: Noto CJK, WenQuanYi Micro Hei, AR PL UMing (`padskills/gui.py:87-92`)
- Opens folders with `xdg-open` (`padskills/gui.py:771-773`)
- Requires `/dev/input` read permission

**Font fallback chain (all platforms):**
- Explicit file paths first, then `pygame.font.match_font()` over names such as `microsoftyahei`, `pingfangsc`, `notosanscjksc` (`padskills/gui.py:95-116`); if nothing is found, the UI still runs but warns about missing CJK glyphs (`padskills/gui.py:1202-1204`).

---

*Integration audit: 2026-11-04*
