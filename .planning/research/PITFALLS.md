# Pitfalls Research

**Domain:** Android-first Godot 4 gamepad gesture trainer, side-loaded APK (port of a validated Python/pygame desktop app)
**Researched:** 2026-11-04
**Confidence:** HIGH (repo/toolchain/API facts) / MEDIUM (device-specific controller behaviour; small-N community reports)

> Scope note: phase IDs below are **provisional** and follow the intended build order:
> **P1** repo split + desktop regression · **P2** shared config single source · **P3** Android build pipeline + on-device smoke · **P4** input adaptation layer · **P5** detector/engine port + parity · **P6** visual feedback + controller-first UI · **P7** haptics best-effort · **P8** lifecycle/disconnect resilience · **P9** sideload distribution.
> If the roadmap renames phases, keep the *ordering*: build pipeline before input, input before detectors, lifecycle before distribution.

---

## Android + Bluetooth gamepad reality (read this before planning)

This is the part most ports get wrong: the desktop assumptions do not survive contact with Android.

| Reality | Consequence for this project | Confidence |
|---|---|---|
| Godot 4.5+ uses SDL3 for controllers on Windows/macOS/Linux, but **Android still uses Godot's own non-SDL implementation**. Official docs: "controller support may be less reliable than on desktop platforms." | Desktop mapping results are not evidence for Android. Every axis/button must be re-verified on the phone. | HIGH |
| Xbox One S / Series / Elite 2 support Bluetooth. **Original Xbox One controllers (model 1537/1697) have no Bluetooth radio** and cannot pair with a phone at all. | "Xbox 手柄" is not a supported-device statement. Must publish a model list and a pairing guide. | HIGH |
| Xbox pairing = Xbox button + the Pair button on the top edge (the one next to USB). DualSense = PS + Create until the light bar double-flashes. DS4 = PS + Share. | Friends will try "just hold the Xbox button" and fail. In-app pairing instructions are a feature, not documentation. | HIGH |
| Controllers reconnect to the **last host**, not the nearest one. A controller still paired to a console/PC will wake that host instead of the phone. | "App sees no controller" is often "controller connected to the PS5 in the other room". Needs an explicit troubleshooting step. | MEDIUM |
| Xbox controller firmware updates require the Windows-only Xbox Accessories app. | A Mac-only developer cannot update a friend's controller. Old firmware is an unfixable variable; detect and document, don't chase. | HIGH |
| Xbox triggers have been **reported swapped (LT↔RT) on Android over Bluetooth**; a fix PR existed as of May 2025 (#106021). Verify on your exact controller/firmware before assuming it is fixed or broken. | The `RT` modifier option of "绿色搓射" is the single most likely thing to be broken on Android. | MEDIUM |
| DualSense on Android: reports of triggers registering as permanently pressed on some Samsung phones, and completely wrong button mapping on an older Nokia (Godot 4.4/4.5). | "DualSense supported" must mean "verified on at least two Android OEMs", not "paired once". | MEDIUM |
| `Input.get_joy_guid()` may be empty on Android; `get_joy_info()` fields (vendor_id/product_id) are documented for desktop/iOS, not Android. `Input.add_joy_mapping()` falls back to an internal mapping on Android. | Do **not** plan to fix Android mapping with SDL mapping strings or GUID lookups. Build a user-confirmed axis probe instead. | MEDIUM |
| A controller can enumerate as `SOURCE_GAMEPAD`, `SOURCE_JOYSTICK`, `SOURCE_DPAD`, or a generic HID/keyboard-ish device; cheap controllers may expose sticks as axes but buttons as keys, and some phones expose a virtual device at index 0. | "It's a gamepad" is not a reliable filter. Enumerate, inspect axis/button counts and names, and let the user confirm the device; don't assume the first entry is the controller. | MEDIUM |
| Bluetooth adds roughly 10–30 ms and Android coalesces motion events; sampling is bursty, not a clean 250 Hz stream. Latency shifts the start and end of a gesture **equally**, so measured duration stays valid. | Do not "compensate" by shrinking 400–600 ms windows. Latency affects feel, not the detector's millisecond math. | MEDIUM |
| Godot's Android layer implements **no joypad rumble**. `start_joy_vibration()` only records a request in the Input singleton; `get_joy_vibration_strength()` will happily report it while the controller is silent. Issue #73446 open since 2023, no implementation as of 4.6. | Vibration is not "best effort" on Android — it is **absent** unless you write an Android plugin. Design the product as visual-only and treat haptics as a bonus. | HIGH |
| Android itself *does* expose `InputDevice.getVibratorManager()` (API 31+), so controller haptics are technically possible via a custom Android plugin. | This is a spike, not a v1 requirement: it forces a Gradle build, plugin version pinning, and per-OEM testing. | HIGH |
| Cannot be done (reasonably): old Xbox One over BT, DualSense adaptive triggers / advanced haptics, controller battery level, guaranteed identical mapping across brands, reliable background operation. | Put these in "Out of Scope" explicitly so they don't become late surprises. | HIGH |

### Genuinely out of reach (put these in Out of Scope)

- **Controller rumble through Godot on Android.** The engine has no implementation; a custom Android plugin using `InputDevice.getVibratorManager()` could do it, but that is a separate project with its own toolchain risk.
- **A true 250 Hz timestamped sample stream.** Godot exposes no OS event timestamp; events are delivered in frame batches. You can recover every value in order, but not sub-frame timing. Millisecond windows are fine; microsecond analysis is not.
- **Raw HID features:** DualSense adaptive triggers, advanced haptics, controller battery level. Not exposed by Android's gamepad API or by Godot.
- **Guaranteed identical axis/button mapping across brands and OEMs.** The Android path is Godot's custom implementation with documented mis-mapping reports; calibration is mandatory, not optional.
- **Reliable operation while backgrounded or screen-off.** Android pauses the activity; the app cannot keep sampling a controller in the background without foreground-service machinery that is out of scope.
- **Injecting inputs into FC/FC Mobile.** Already out of scope, and not possible without root/accessibility privileges.

---

## Critical Pitfalls

### Pitfall C1: Treating `Input.start_joy_vibration()` as working controller rumble on Android

**What goes wrong:**
The call returns nothing, throws nothing, and `Input.get_joy_vibration_strength()` returns the values you set — but the controller never vibrates. If the UI logs "已震动" or shows a haptic indicator, it is lying. Worse, it passes every desktop test and fails only on the target device.

**Why it happens:**
Godot's desktop backends implement force feedback; the Android platform layer does not. The `Input` singleton stores the request in a `joy_vibration` map regardless of platform, so the API gives every appearance of success. The docs describe the method generically and only mention macOS limitations.

**How to avoid:**
- Model haptics as a capability with three states: `CONTROLLER`, `DEVICE` (phone vibrator), `NONE`. On Android, default to `DEVICE` or `NONE`, never `CONTROLLER`.
- Never use the return value, `has_joy_vibration()`, or `get_joy_vibration_strength()` as proof that the user felt anything. The only valid proof is a user-confirmed test ("你刚才感觉到震动了吗？").
- If `Input.vibrate_handheld()` is used, label it "手机震动" in the UI, require the VIBRATE permission in the export preset, and do not present it as controller feedback.
- If controller haptics become a real requirement, isolate it as a spike: custom Android plugin calling `InputDevice.getVibratorManager()`, Gradle build, plugin pinned to the Godot version. Do not let it block P7 or P9.

**Warning signs:**
- `start_joy_vibration` in code with no platform branch.
- A "震动已发送" log line, or a success animation whose only confirmation is an API call.
- QA only ever ran on desktop or an emulator.
- `has_joy_vibration()` used as a feature flag.

**Phase to address:**
P7 for implementation; **P6 must assume zero haptics** so the visual channel is complete on its own; P3 should include a 5-minute "does rumble exist at all?" hardware check so the team stops guessing early.

---

### Pitfall C2: Assuming Android controller mapping equals the desktop SDL mapping

**What goes wrong:**
The right stick's axes are in a different order or sign on Android; triggers are swapped; a DualSense reports a trigger as permanently held. The detectors still run and still produce outcomes — they are just wrong. "马赛回旋" fires on a forward push, "绿色搓射" can never see RT, and the failure messages confidently blame the user.

**Why it happens:**
Godot 4.5 moved desktop controller support to SDL3, but Android kept the older custom path. The `JoyAxis`/`JoyButton` enums look universal, so hardcoding `JOY_AXIS_RIGHT_X` seems safe. Testing with one controller on one phone produces a false sense of correctness.

**How to avoid:**
- Build a first-run **controller check** screen: "推右摇杆向上 / 向右 / 向下 / 向左", "按 L1", "扣右扳机". Record which axis changes, its sign, its rest value, and which button index fires. Persist a per-device profile keyed by `Input.get_joy_name()` plus a user-visible label.
- Never hardcode axis indices in detector or engine code. All access goes through the profile (`rs_x`, `rs_y`, `lt`, `rt`, `buttons`).
- Run the check on the minimum matrix: 2 phones (ideally different OEMs) × 2 controllers (Xbox + DualSense). Save the raw results as fixtures.
- Treat `Input.add_joy_mapping()` as a non-solution on Android (it maps to an internal fallback), and treat GUID/vendor-id detection as unreliable there.
- If a controller cannot be mapped correctly, fail loudly with a device-specific message rather than silently mis-detecting.

**Warning signs:**
- Only one physical device has ever been tested.
- `JOY_AXIS_*` or `JOY_BUTTON_*` constants appear outside the input layer.
- No screen shows raw axis values.
- A friend reports "方向反了" or "扳机一直按着".

**Phase to address:**
P4. P3's smoke APK should already display raw axes and buttons so mapping problems surface before detector work begins.

---

### Pitfall C3: Polling `Input.get_joy_axis()` in `_process` and losing intra-frame reversals

**What goes wrong:**
At 60 Hz you see only the last axis value per frame. A fast feint (right → left → right within ~30 ms) collapses into a single net movement. `ArcDetector` accumulates `signed_delta(last_angle, angle)` per sample, so dropping the reversal corrupts `acc`: the gesture either fails ("转得不够") or passes when it shouldn't. The Python reference at 250 Hz saw 6–8 samples of that same motion.

**Why it happens:**
`_process` polling is the default tutorial pattern. `Input.get_joy_axis()` reads like "the current stick position", and nothing warns that intermediate values were discarded. The Python engine's `source.poll()` also returns an instantaneous snapshot, which makes the mistake look like a faithful port.

**How to avoid:**
- Capture `InputEventJoypadMotion` in `_input(event)` and push every event, in arrival order, into the detector. Do not collapse to one sample per frame.
- Keep rendering on the latest snapshot; keep judgement on the event stream.
- Know the engine detail: with the default `use_accumulated_input = true`, joypad events are buffered and delivered at frame end, but **`InputEventJoypadMotion` does not implement `accumulate()`** (only mouse motion does), so no motion events are merged or lost. They all arrive, just with frame-end timestamps.
- Do not switch to `_physics_process` to "get more samples": it runs 0..N times per frame, duplicating or skipping the same axis value and double-counting rotation.
- Measure and display actual event rate during a gesture; do not trust the configured `poll_hz`.

**Warning signs:**
- `detector.samples` is far below the number of input events.
- Fast direction changes are never recognized, but slow ones are.
- Adjacent samples in the diagnostic log differ by 30°+ during a fast gesture.
- Behaviour changes when the device drops from 120 Hz to 60 Hz.

**Phase to address:**
P4 (capture) and P5 (consume). The detector API must accept one sample at a time with a timestamp, exactly like Python's `Frame`.

---

### Pitfall C4: Using `_process(delta)` or wall-clock time for millisecond judgement

**What goes wrong:**
After a stall or a resume, `delta` does not represent real elapsed time: Godot caps it at `Engine.time_scale * Engine.max_physics_steps_per_frame / Engine.physics_ticks_per_second`, and `OS.delta_smoothing` may post-process it. A 5-minute background trip can produce a delta of ~0.1 s, not 300 s. Conversely, using `Time.get_unix_time_from_system()` lets a user clock change or DST jump create negative or enormous gesture durations.

**Why it happens:**
Every Godot tutorial says "multiply delta by 1000 to get milliseconds". The Python code uses `time.perf_counter()` (monotonic), but that detail looks incidental rather than essential.

**How to avoid:**
- One function: `now_ms() -> int` backed by `Time.get_ticks_usec() / 1000` (monotonic, unaffected by `Engine.time_scale`). Ban `delta` and `get_unix_time_from_system()` from every judgement path.
- Keep `delta` for animation and interpolation only.
- Make golden-trace replay inject explicit timestamps, so parity tests never depend on the wall clock.
- Add a lint/grep check in review: `delta` must not appear under `mobile/scripts/detectors/` or `engine/`.

**Warning signs:**
- `delta * 1000.0` inside a detector.
- A "太慢了：用了 300000ms" message after returning from the background.
- `Time.get_unix_time` anywhere near gesture logic.
- Detector behaviour changes when `Engine.time_scale` is altered for a debug menu.

**Phase to address:**
P5, from the first line of ported detector code. P4 must supply the timestamp in the same units.

---

### Pitfall C5: No discontinuity handling for pause / resume / screen-off / reconnect

**What goes wrong:**
After the app is backgrounded, the screen locks, or the notification shade is pulled, the first frame back computes `now - t0` against a `t0` from minutes ago. The arc detector immediately reports "太慢了" or "中途停住"; the sequence detector abandons a step the user never released. Separately, a freshly connected controller can report all axes as `0.0` until its first real event arrives; the detector interprets that as "stick centred", re-arms, and then sees the real held position as a new gesture start.

**Why it happens:**
The desktop app has no application lifecycle — it owns the process until quit. A port deletes or ignores `NOTIFICATION_APPLICATION_PAUSED` because nothing in `engine.py` corresponds to it. Godot's `_process` simply resumes; detectors do not know time jumped.

**How to avoid:**
- Handle `NOTIFICATION_APPLICATION_PAUSED` (2015), `NOTIFICATION_APPLICATION_RESUMED` (2014), `NOTIFICATION_WM_WINDOW_FOCUS_OUT/IN`, and `Input.joy_connection_changed`.
- On pause: stop sampling, call `stop_joy_vibration` for every connected device, record the pause time.
- On resume: hard-reset every detector (`abandon` + `on_idle`), clear cached pressed states and `_prev_pressed`, set `ignore_until_ms = now + 150`, and require the right stick to stay below `RELEASE_STICK` for `gesture_release_ms` before re-arming.
- Track `has_axis_sample` per device; do not treat the initial `0.0` as a real centred reading. Wait for the first `InputEventJoypadMotion`/button event.
- `display/window/energy_saving/keep_screen_on` defaults to `true`, but still call `DisplayServer.screen_set_keep_on(true)` and verify it; an OEM battery saver or the power button can still pause you.

**Warning signs:**
- The first attempt after returning from the background always fails.
- A "太慢" outcome appears in stats with a huge `elapsed_ms`.
- After reconnecting a controller, the app needs a restart.
- The stick is held during reconnect but the app shows "待机" then fires immediately.

**Phase to address:**
P8 for the policy, but P5 must expose `reset_hard()` / `abandon()` on every detector so P8 can call it. Do not bolt this on after the UI is built.

---

### Pitfall C6: Porting `detectors.py` but not the arbitration in `engine.py`

**What goes wrong:**
The three detectors are ported correctly, but the surrounding rules are not: one physical gesture gets claimed by two skills; a success and a failure are reported for the same motion; failures are attributed to the wrong skill; cooldowns swallow back-to-back hits; the "10 个一组" counter is wrong. The detectors look right in isolation and the app still feels wrong.

**Why it happens:**
`detectors.py` is the biggest, most algorithm-looking file. `engine.py` looks like a thin loop, so it gets rewritten ad hoc in GDScript. But the engine owns: gesture lock until release, `held_required` modifier exclusivity, `_discard_other_claims`, one-failure-per-gesture draining, per-skill and global cooldowns, idle reset, facing validity, and group counting.

**How to avoid:**
- Port `engine.py` as a unit (`engine.gd`) with the same method boundaries: `_tick`, `_discard_other_claims`, `_drain_failures`, `_buttons_ok`, `_fire`.
- Keep the detector interface identical: `update(frame)`, `reset()`, `on_idle()`, `abandon()`, `pop_failure()`, `observe(frame)`.
- Use the existing 182 detector/engine checks as the acceptance spec, not just the detector subset. Add golden traces that exercise two skills competing for one motion.
- Do not "simplify" by letting each detector report directly to the UI. All outcomes go through one drain point.

**Warning signs:**
- Two outcome cards appear for one stick motion.
- Disabling one skill changes the failure reason of another.
- `attempts` does not equal successes + failures.
- A fast combo only registers the first hit.

**Phase to address:**
P5. Treat "engine parity" as a separate deliverable from "detector parity"; both must pass before P6.

---

### Pitfall C7: Getting the angle convention wrong (0° = up, clockwise positive)

**What goes wrong:**
Python's `geometry.angle_of(x, y)` is `atan2(x, -y)`: 0° = forward/up, 90° = right, increasing clockwise. Godot's `Vector2.angle()` measures from +X and, because screen Y is down, a naive `atan2(y, x)` gives 0° = right and 90° = down. Swap those in and every `start_angle` / `end_angle` is rotated 90° and mirrored. "马赛回旋" (`start_angle: 180`, i.e. backward) fires when the user pushes forward. The app runs, gives feedback, and is completely wrong.

**Why it happens:**
Both sides call it "angle" and both return degrees after conversion. There is no type error, no exception, and the visual trace still looks plausible because the drawing code uses the same wrong convention consistently.

**How to avoid:**
- Translate `geometry.py` line by line into `geometry.gd`, including the `if x == 0.0 and y == 0.0: return 0.0` guard (`atan2(0.0, -0.0)` is π, which would display "backward" at centre).
- Ban `Vector2.angle()`, `Vector2.rotated()`, and `atan2(y, x)` in gesture code. One helper, one convention.
- Unit-test eight directions plus centre: up=0, upright=45, right=90, downright=135, down=180, downleft=225, left=270, upleft=315.
- Put a "start at back, rotate 180°" trace in the golden set and assert that only Roulette hits; put "start at forward, rotate 90°" and assert Stepover.

**Warning signs:**
- Desktop passes, mobile fires the wrong skill.
- Pushing forward triggers the Roulette.
- Logged angles are consistently off by 90° or mirrored vertically.
- The on-screen trace is vertically flipped relative to the physical stick.

**Phase to address:**
P5, on day one. P4 must output angles through the same helper so there is only one implementation.

---

### Pitfall C8: Replacing the project's radial deadzone rescale with `Input.get_vector()` / action deadzone

**What goes wrong:**
Python's `_deadzone(x, y, dz)` rescales radially: `scaled = min(1.0, (m - dz) / (1 - dz))`, preserving angle, and `magnitude()` can exceed 1.0 on diagonals (up to ~1.41). Godot's `Input.get_vector()` applies a circular deadzone and clamps the result to 1.0; action deadzones are a third behaviour. The same physical stick position then crosses `enter_threshold: 0.72` at a different point, and diagonal pushes lose the >1.0 magnitude that the Python heuristics were tuned against.

**Why it happens:**
The engine helper looks more idiomatic and "more correct" than a hand-rolled deadzone. Nobody expects magnitude to be allowed above 1.0, so the difference is invisible until thresholds are compared.

**How to avoid:**
- Port `_deadzone` verbatim and feed it raw `get_joy_axis` values. Do not use `Input.get_vector`, `Input.get_axis`, or action deadzones for gesture input.
- Build a fixture: 8 directions × 5 magnitudes (0.1, 0.3, 0.5, 0.72, 1.0) → assert `(x, y, mag, angle)` matches Python within 1e-4.
- Keep `magnitude()` unclamped, exactly like `math.hypot`.
- Document in code why the helper is intentionally not the engine one; otherwise a future cleanup will "simplify" it back.

**Warning signs:**
- The same physical push triggers on desktop but not on mobile.
- Diagonals feel harder to trigger than cardinals.
- `rs_mag` never exceeds 1.0 in logs, while Python logs show 1.2.
- Someone "fixes" the deadzone by lowering thresholds.

**Phase to address:**
P4. This is input-layer behaviour and must be locked before detector tuning starts.

---

### Pitfall C9: Treating triggers as buttons, and not calibrating their rest value

**What goes wrong:**
The config says `required_button: "RB"` and `modifier_options: ["RB", "RT"]`. Python synthesises LT/RT booleans from trigger axes using `trigger_threshold = 0.35`, after auto-detecting whether the axis rests at `-1` or `0`. Godot has no `JOY_BUTTON_TRIGGER_RIGHT`; triggers are axes, and on Android their rest value and polarity vary by controller. Combined with the Xbox BT LT/RT swap, "绿色搓射" either never sees RT held, or sees it held forever.

**Why it happens:**
"RT" reads like a button name in the config, and on desktop SDL normalises it. The port maps the string to the nearest Godot button, or forgets the trigger path entirely because no detector mentions it.

**How to avoid:**
- In the input layer, explicitly read `JOY_AXIS_TRIGGER_LEFT/RIGHT`, calibrate rest (`-1` vs `0`) per device, normalise to `0..1`, and synthesise `LT`/`RT` booleans at `trigger_threshold`.
- Store the calibration in the same per-device profile as the stick axes. Re-calibrate on every connect; do not cache across controllers with the same name.
- The controller-check screen must include "扣一下右扳机" and show the raw axis value.
- If RT proves unreliable on Android, keep RB as the only exposed modifier for "绿色搓射" and record the decision. Do not silently ship an RT option that fails on half the devices.

**Warning signs:**
- Holding RT does nothing.
- The modifier appears held without touching the controller.
- RB works but RT does not (classic swap symptom).
- The config's `trigger_threshold` is never referenced in GDScript.

**Phase to address:**
P4 for synthesis/calibration; P6 for the modifier-options UI (hide unsupported options per device).

---

### Pitfall C10: Chinese UI depending on Android's system-font fallback

**What goes wrong:**
Godot's default project font is Open Sans SemiBold, which has no CJK glyphs. Godot does fall back to system fonts, and on Android that usually means Noto Sans CJK — but the official docs warn that loading system fonts on Android is unreliable because there is no official API and Godot parses vendor-modifiable config files. The result: perfect Chinese on the developer's Pixel, tofu boxes or blank labels on a friend's Xiaomi/Huawei. Because this project's entire UI is Chinese (action names, failure reasons), that is a total product failure, not a cosmetic bug.

**Why it happens:**
The editor and the first phone look fine. Nobody tests a second OEM. Font fallback is invisible in code review, and the desktop app already had a 70-line CJK font-discovery hack (`padskills/gui.py:72-139`) — evidence that this problem has bitten the project before.

**How to avoid:**
- Decide the font in P3, before layout: either bundle a subset CJK font (Noto Sans SC / 思源黑体) as the Theme default, or use a `SystemFont` with explicit fallbacks `["Noto Sans CJK SC", "Source Han Sans SC", "sans-serif"]` **plus** a bundled fallback.
- Put the longest Chinese string (action name + failure reason + degree text) on the first screen and screenshot it on two different OEM phones.
- Include digits, `°`, `±`, `→`, `✓`, `✗` in the glyph test; these appear in the existing messages and may not be in a subset font.
- If bundling, subset to the actual character set plus a margin, and add the font licence file.

**Warning signs:**
- Editor looks right, device shows squares.
- One phone is fine, another shows blank labels.
- Text width changes dramatically between devices (font fallback metrics differ).
- A `.ttf` is imported but its glyph list is empty.

**Phase to address:**
P6 for UI, but the font decision belongs in P3 because it affects layout, APK size, and theme setup.

---

### Pitfall C11: Installing an Android toolchain from a stale tutorial

**What goes wrong:**
Godot's Android requirements change every minor release. Godot 4.5 docs: JDK 17, build-tools 35.0.0, platform 35, NDK r28b (28.1.13356709), CMake 3.10.2.4988404. Godot 4.7 docs: build-tools 36.1.0, platform 36, NDK 29.0.14206865, CMake 3.22.1. Gradle pins `JavaVersion.VERSION_17`. Default `minSdk` is 24; `targetSdk` is 35 in 4.5 and 36 in 4.7. Following a 2024 blog on a 2026 editor produces "A valid Java SDK path is required", Gradle stack traces, or an export-template version mismatch. On macOS, using the Homebrew Android SDK is explicitly discouraged by the official docs because install locations are inconsistent.

**Why it happens:**
Search results are ranked by popularity, not by matching your editor version. `sdkmanager` "latest" installs the newest packages, not the ones this Godot release expects. macOS may have JDK 21 as the default `java` while Godot's Gradle needs 17.

**How to avoid:**
- Pin one Godot version for the milestone (4.7.x is the current stable line; 4.5 is the minimum for 16 KB page support — see C12). Record the exact versions in `mobile/BUILD.md`.
- Use Temurin/Adoptium **JDK 17**, and point Editor Settings → Export → Android → Java SDK Path at the JDK root (not `bin/java`). On macOS that is typically `/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home`.
- Install only the SDK packages the docs for *your* Godot version list; run `sdkmanager --licenses` first and accept all.
- Use the Android SDK from Android Studio or the official command-line tools, not Homebrew.
- Write `scripts/export_android.sh` plus a `doctor` check: `godot --version`, export-template directory, `java -version`, `sdkmanager --list_installed`, `adb devices`.
- Tag the first successful export and record the toolchain; upgrade Godot in its own PR, never in the middle of feature work.
- If you add an Android plugin, budget for a second toolchain: `gradle_build/use_gradle_build = true`, the plugin's `godot-lib` must match the editor minor version, its native libs must include `arm64-v8a`, and its manifest `minSdk` must be ≤ Godot's 24 (raise `gradle_build/min_sdk` if not, or the manifest merger fails). Every plugin is a new failure mode; v1 needs none.
- On Apple Silicon, use the arm64 Godot editor and matching arm64 templates. If tools were downloaded through a browser, macOS quarantine (`xattr -dr com.apple.quarantine`) can block `adb`/Gradle helpers. Keep `JAVA_HOME` pointed at the same JDK 17 configured in Editor Settings, or Gradle may silently use a different one.

**Warning signs:**
- Red error icon on the Android preset.
- `MISMATCHED_VERSIONS_MESSAGE` from Godot ("Template installed: X / Requested version: Y").
- Gradle fails before compiling any project code.
- Only one machine in the team can export.
- The docs you are following mention a different Godot minor version.

**Phase to address:**
P3, as the first thing after the repo split. Do not start detector work until a signed APK installs and launches on a real phone.

---

### Pitfall C12: Shipping an APK built with Godot < 4.5 to a modern phone

**What goes wrong:**
Android 15 introduced devices with 16 KB memory page sizes. Godot versions before 4.5 shipped `libgodot_android.so` aligned for 4 KB; on a 16 KB device the app may fail to install or crash at launch with a linker/RELRO error. There is no Play Console warning for a side-loaded APK, and the developer's older phone (4 KB) will never reproduce it.

**Why it happens:**
"Godot 4 is Godot 4" — the version looks irrelevant to a 2D input app. The failure appears only on a friend's newer device, after distribution.

**How to avoid:**
- Export with Godot ≥ 4.5 (prefer 4.7.x). The fix landed via NDK r28b (issue #106313, PR #106358).
- Verify the APK: `zipalign -c -P 16 -v 4 app.apk` and inspect `lib/arm64-v8a/libgodot_android.so` alignment; or use Android Studio's APK Analyzer.
- Install once on an Android 15+ device before calling the build "done".
- Record the minimum Godot version in `BUILD.md` with the reason, so nobody "downgrades for stability".

**Warning signs:**
- "App not installed" with no useful message.
- `logcat` shows a linker error or a crash before `Godot` prints anything.
- Old phone works, new phone doesn't.
- The APK was built with a 4.3/4.4 editor "because that's what was installed".

**Phase to address:**
P3 (choose the version) and P9 (verify the distributed artifact).

---

### Pitfall C13: Keystore / package / versionCode mistakes that turn every update into an uninstall

**What goes wrong:**
Changing the signing key (debug → release, new machine, lost keystore) makes Android refuse the update with `INSTALL_FAILED_UPDATE_INCOMPATIBLE`; friends must uninstall, which wipes `user://` (stats, calibration, settings). Changing `package/unique_name` creates a second app. Forgetting to bump `version/code` gets the update rejected. Exporting with "Export With Debug" checked ships a debuggable, larger, slower APK.

**Why it happens:**
Side-loading feels informal: "it installs, ship it". Godot auto-generates a debug keystore, so the first build works without a decision. `export_presets.cfg` is often gitignored, so the preset drifts per machine.

**How to avoid:**
- Generate one release keystore on day one, with a non-expiring validity (e.g. 10000 days), and back it up in a password manager plus an offline copy.
- Fix the application ID (lowercase reverse-DNS, no spaces/hyphens) and never change it. Bump `version/code` on every distributed build; put it in the release checklist.
- Inject signing secrets via `GODOT_ANDROID_KEYSTORE_RELEASE_PATH/USER/PASSWORD` environment variables. Do not commit passwords in `export_presets.cfg`.
- Commit a sanitised `export_presets.cfg` (no secrets) so the preset name, package, ABI list and version fields are reproducible.
- Acceptance test: install v1, record a stat, install v2 signed with the same key, confirm the stat survives.
- Uncheck "Export With Debug" for anything a friend receives.

**Warning signs:**
- "App not installed" on an update that installed fine the first time.
- Instructions include "先卸载旧版" — that is the smell.
- Friends' progress resets after every update.
- `export_presets.cfg` contains a plaintext password in `git status`.

**Phase to address:**
P3 (create the key and preset) and P9 (release checklist + upgrade test).

---

### Pitfall C14: Two copies of `skills_config.json` drifting, and trying to write config into `res://`

**What goes wrong:**
`shared/skills_config.json` is the source of truth, but Godot reads `res://`, so a copy lands in `mobile/`. Someone edits the mobile copy "just to test"; the sync script overwrites it one-way; CI only checks that a file exists. Meanwhile the UI lets the user switch the "绿色搓射" modifier from RB to RT, and the port writes that back to `res://` — which is read-only inside the APK — or writes a full `user://` copy that then shadows every future update to the shared rules.

**Why it happens:**
The desktop app already has a five-way configuration source-of-truth problem (`DEFAULT_CONFIG`, checked-in JSON, README tables, detector defaults, embedded `_readme`), and its GUI rewrites the config file in place with a regex (`padskills/gui.py:732-754`). Porting that pattern is the path of least resistance.

**How to avoid:**
- One source: `shared/skills_config.json`. The `mobile/` copy is generated by `scripts/sync_shared_config.py`, and both the export script and CI compare SHA-256; mismatch = hard fail, not a warning.
- At runtime, read only `res://shared/skills_config.json`. User changes go to `user://overrides.json`: sparse keys, a `schema_version`, and a deep-merge at startup where shared values win over stale defaults.
- Write `user://` atomically (temp file + rename) and keep a `.bak`.
- Validate with one shared fixture corpus (valid + invalid) in both Python and GDScript; compare normalised objects and error codes, not just "did it load".
- Never let the mobile app rewrite the bundled JSON. If a feature needs persistence, it is an override, not an edit.

**Warning signs:**
- Changing `shared/skills_config.json` does not change app behaviour.
- `git status` shows edits under `mobile/.../skills_config.json`.
- A user's customised rule survives an app update while a fixed rule does not.
- Config writes fail silently on Android (read-only `res://`).
- Python and GDScript disagree about the same file.

**Phase to address:**
P2 for the sync/hash mechanism and override schema; P4/P5 for consumption; P9 for the export-time check.

---

### Pitfall C15: Trying to validate this product on an Android emulator

**What goes wrong:**
A week disappears into emulator images, keyboard-to-joystick mapping, and "it works on the emulator". The emulator has no Bluetooth controller, no real rumble, different input dispatch, different frame pacing, and no OEM font stack. None of the project's actual risks — pairing, mapping, latency, disconnect, screen-off — are exercised.

**Why it happens:**
The emulator starts fast, supports screenshots, and looks like a phone. It is the cheapest thing to try when no device is at hand.

**How to avoid:**
- Make "real phone + real controller" a P3 exit criterion, not a P9 nice-to-have.
- Use the emulator only for layout screenshots and non-input regression.
- Establish the minimum matrix early: one phone, one tablet (optional), Xbox controller, DualSense. Borrow or buy before P4.
- Keep a paper log of which build was tested on which device/controller; "tested" without a device name is not a test.

**Warning signs:**
- "模拟器上没问题" in a status update.
- No one has physically held the controller during this milestone.
- Bluetooth/rumble/disconnect are still untested at P7.
- CI is being built around an emulator instead of a device farm or manual checklist.

**Phase to address:**
P3 onward, enforced at every phase gate.

---

## Keeping the Python reference and the GDScript port honest

The 230 existing checks are a behavioural spec, but they run in Python. They do not prove GDScript. Manual side-by-side runs are not repeatable, and "looks the same" is how a port silently changes semantics. The only durable answer is a **trace-replay parity harness** that runs in both runtimes.

### Harness design

1. **Record real traces from Python.** Add `--record-trace PATH` to `main.py`: JSONL, one line per frame, `{t_ms, ls_x, ls_y, rs_x, rs_y, lt, rt, buttons, facing}`, relative to session start, plus a header with app version, config SHA-256, and `trace_format_version`. Do not reuse the GUI's 45 ms diagnostic log — it is too coarse for parity.
2. **Build a corpus of ~40 traces**, not just happy paths:
   - one success per skill (5);
   - one trace per failure code (too_fast, too_slow, too_short, overshoot, wrong_start, wrong_end, wrong_direction, stalled, incomplete, hold_short);
   - boundary cases ±1 ms / ±1° around every threshold;
   - Known Bug #6 from `CONCERNS.md` (sequence hold accumulating across a below-enter dip);
   - Known Bug #7 from `CONCERNS.md` (arc reset mid-gesture re-arming while the stick is still pushed);
   - tap intervals at 399/400/600/601 ms;
   - two skills competing for one motion (engine arbitration);
   - modifier switch mid-session (RB→RT);
   - facing invalid (left stick centred) for `relative_to_ls` skills.
3. **Expected outputs come from Python, never by hand.** For each trace, store `.expected.json` generated by the Python reference: outcome code, owning skill, `elapsed_ms`, attempt/hit counts, ordered failure codes. Regenerating expected files is a deliberate act with a reviewable diff.
4. **Replay headlessly in GDScript.** Feed frames with injected `now_ms` (no real clock, no `delta`), run `engine.gd`, emit the same shape. Compare codes and counts exactly; compare `elapsed_ms` with ±5 ms; compare summary numbers with tolerance. Do **not** gate on exact Chinese message strings — report them separately as a readability diff.
5. **One command, red/green.** `make parity` (or `scripts/parity.sh`) runs Python expected-generation check + GDScript replay + diff. A divergence fails the build; it is not a warning. Wire it into the export script so a drifted port cannot be packaged.
6. **Fuzz beyond the hand-written corpus.** Seeded random walks (200 traces, 10–60 s, varying speed, reversals, noise, pauses) replayed through both implementations. Keep the seed in the filename so a failure reproduces exactly. This catches the cases nobody thought to record.
7. **Config parity in the same harness.** Both parsers load the same `shared/skills_config.json` and the same invalid fixtures; compare normalised objects and field-scoped error codes. A config change invalidates expected outputs — rerun and review, do not auto-accept.
8. **Pin the inputs.** Every expected file records `config_sha256` and `trace_format_version`; the runner refuses to compare across a mismatch. This prevents the classic "parity passed because it tested the old config".
9. **Python is the reference until a deliberate spec change.** If the two disagree, Python wins. To change behaviour, change Python + tests + expected traces first, then port. Never "fix" GDScript to match a hunch.
10. **Remove non-determinism from the replay.** No wall clock, no locale-dependent number formatting, no UI, no asynchronous input. The replay must be bit-for-bit reproducible on a laptop and in CI.

### Porting checklist — what must be identical

| Area | Must match | Where it lives in Python |
|---|---|---|
| Angle convention | 0°=up, 90°=right, clockwise, centre→0 | `padskills/geometry.py` |
| Rotation math | shortest signed delta, norm to [0,360) | `padskills/geometry.py` |
| Deadzone | radial rescale `(m-dz)/(1-dz)`, magnitude unclamped (>1 allowed) | `padskills/input_source.py::_deadzone` |
| Trigger synthesis | rest detection (-1 vs 0), threshold 0.35 → LT/RT booleans | `padskills/input_source.py::poll/_trigger_value` |
| Button aliases | L1→LB, Cross→A, Square→X, Share→BACK, etc. | `padskills/input_source.py::BUTTON_ALIASES` |
| Direction aliases | forward/up/前, back/down/后, 右/左, diagonals, numeric degrees | `padskills/config.py::DIRECTION_ALIASES` |
| Config defaults/ranges | same defaults and rejection rules | `padskills/config.py` |
| Engine arbitration | gesture lock, modifier exclusivity, claim discard, failure drain, cooldowns, groups | `padskills/engine.py` |
| Failure precedence | order of start/direction/overshoot/stall/slow/fast checks | `padskills/detectors.py` |
| Idle/release semantics | continuous vs cumulative hold, re-arm requirements | `padskills/detectors.py` |

---

## Moderate Pitfalls

### Pitfall M1: Hardcoding device 0 / caching a device ID across reconnects

**What goes wrong:**
The app starts, finds the controller at index 0, and stores it. The controller sleeps, reconnects, and Android assigns a new device index. The app keeps polling the old ID: `get_joy_axis` returns 0, buttons read released, and the UI says "已连接" while nothing works. On some phones a virtual device or the phone's own input sits at index 0, so even the first connection is wrong.

**Why it happens:**
`Input.get_connected_joypads()[0]` is the obvious first line. `Input.get_joy_name(0)` works in the editor because only one device exists there.

**How to avoid:**
- Never persist a numeric device ID. Resolve on every `joy_connection_changed` and on resume: enumerate, filter to devices with a plausible gamepad name/axis count, and prefer the device the user confirmed in the check screen.
- Store the *identity* (name + vendor/product if available + user label), not the index.
- Handle `connected == false` explicitly: clear the active device, reset detectors, show "手柄已断开", and keep listening.
- If multiple candidates exist, show a device picker instead of guessing.

**Warning signs:**
- Works until the controller sleeps; then a restart is required.
- `get_connected_joypads()` returns a different order after reconnect.
- The app reads all-zero axes but claims a device is connected.

**Phase to address:** P4 (discovery) and P8 (reconnect policy).

---

### Pitfall M2: Assuming exactly one controller and no virtual devices

**What goes wrong:**
Two controllers are paired (or a controller plus a Bluetooth remote), and both deliver events. `InputEventJoypadMotion.device` is ignored, so a second controller's stick drives the same detector, producing impossible traces. Conversely, filtering by device ID drops the intended controller.

**Why it happens:**
The desktop config has a single `joystick_index`, so the port inherits a one-device mindset.

**How to avoid:**
- Tag every captured event with `event.device`; feed only the selected device to the engine.
- Show the selected device name in the UI and allow switching via the controller (D-pad) without touching the phone.
- Ignore devices whose name suggests a remote/keyboard, and expose a "没有找到手柄" state with pairing instructions.
- Test with two controllers connected at once, including disconnect of the active one.

**Warning signs:**
- The trace jumps between two physical sticks.
- Outcomes fire while nobody is touching the selected controller.
- A second controller's button toggles UI focus.

**Phase to address:** P4, re-checked in P8.

---

### Pitfall M3: Idle FPS collapse / Android frame pacing making sampling worse when nothing moves

**What goes wrong:**
The app sits idle waiting for a gesture. Modern phones use variable-refresh displays, and Godot's Android frame pacing (Swappy, `display/window/frame_pacing/android/enable_frame_pacing`, default `true`) can change the swap interval; OEM power management can throttle further. The app may therefore run at a **lower cadence while static** than while the trace is animating. If that happens, the first fast gesture is sampled at a lower rate than the scenario that was tested, and the detector sees fewer, coarser angle steps exactly when resolution matters. Thermal throttling after 10 minutes on a bed makes it worse.

**Why it happens:**
Frame pacing and refresh adaptation are invisible until measured. Developers test with the trace animating (which keeps the frame rate up) and never measure the idle case.

**How to avoid:**
- Measure and display the actual input-event rate and frame rate while idle and during a gesture, on a real phone.
- Keep a lightweight always-on animation or set `Engine.max_fps` to a stable value (e.g. 60) rather than relying on "render only when needed".
- Consider disabling Swappy frame pacing for this app and A/B the latency; record the decision.
- Avoid `application/run/low_processor_mode` — it deliberately reduces redraws and makes sampling irregular.
- Show a subtle "采样 62 Hz" health indicator in a diagnostics panel; if it drops below ~45 Hz, warn.

**Warning signs:**
- Idle FPS is much lower than active FPS.
- The first gesture after a pause is mis-detected.
- The phone gets warm and hit rate degrades over a session.
- Frame rate differs between a 60 Hz and a 120 Hz phone in ways the detector notices.

**Phase to address:** P4 (measurement) and P8 (long-session behaviour).

---

### Pitfall M4: Feedback that is too fast, too subtle, or disappears before it is read

**What goes wrong:**
The result flashes for 300 ms, or exists only as a 120 ms vibration that Android cannot deliver. The user looks down and sees "待机". They cannot connect cause and effect, so they practise the wrong correction. If the result is only shown after the stick returns to neutral, the delay can exceed a second, and the association is lost.

**Why it happens:**
The desktop GUI has a persistent history panel, so the port assumes the same. On a phone at arm's length, a small line of text is not readable in 300 ms. Haptics are assumed to cover the gap.

**How to avoid:**
- Show the outcome on the **same frame** as the hit, not after release. Persist it until the next attempt starts, with a minimum on-screen time (e.g. 1.5 s) even if a new gesture begins.
- Make success/failure distinguishable by colour, icon, and one short word, not colour alone; readable at 1 m.
- Put the primary failure reason in large type ("太快了"), with the numeric detail smaller ("180ms，需要 ≥250ms").
- Treat haptics as an optional extra; test the UI with vibration disabled and ask "could you tell what happened?".
- Keep a short history (last 5 attempts) so a glance after the fact still works.

**Warning signs:**
- Testers say "刚才成功了吗？"
- Outcomes are only visible in a log.
- The result card is replaced by the idle state immediately.
- Success and failure differ only by a thin coloured border.

**Phase to address:** P6, with the timing contract defined in P5 (outcome available on the hit frame).

---

### Pitfall M5: Requiring touch to start, pause, or recover

**What goes wrong:**
The app opens with a touch-only "开始" button, or an Android dialog needs a tap, or a crash shows a touch-only "重试". The user is lying on a sofa with both hands on the controller and the phone on a stand; every touch means putting the controller down, which breaks the practice flow.

**Why it happens:**
Mobile UI defaults are touch-first, and Godot's Control focus system needs explicit setup. The desktop app uses keyboard/mouse, so there is no precedent for controller-only navigation.

**How to avoid:**
- Design for "controller in hand, phone untouched": A/Cross to start, Start/Menu to pause, D-pad to change selection, B/Circle to go back.
- Set explicit `focus_neighbor_*` / `focus_next` and call `grab_focus()` on the first control; test with the controller only, with touch input disabled if possible.
- Do not require runtime permissions (VIBRATE is install-time); avoid any modal that needs a tap.
- If a touch interaction is unavoidable (e.g. first-run pairing instructions), make it dismissible with A and state that on screen.
- Keep the phone in landscape if that is the stand orientation, but do not depend on orientation lock (see M9).

**Warning signs:**
- The start button only responds to touch.
- Focus outline is missing or jumps unpredictably.
- A dialog blocks the app until tapped.
- Testers reach for the phone after every attempt.

**Phase to address:** P6, verified in P9 with a friend who has never seen the app.

---

### Pitfall M6: Losing session progress when Android kills the app

**What goes wrong:**
The desktop app's stats are per-process and reset on restart; that is acceptable on a desktop you close deliberately. On a phone, the OS kills backgrounded apps routinely. The user checks a message, comes back, and the "10 个一组" progress and today's counts are gone. The product feels like a toy.

**Why it happens:**
"Stats persistence" is not in the desktop requirements, so it is not in the port's requirements either. `user://` is available but nobody thinks to use it until a tester complains.

**How to avoid:**
- Persist counters, per-skill attempts/failures, current group progress, and the last N outcomes to `user://progress.json` on every outcome (or debounced every few seconds), not only on quit.
- Write atomically (temp + rename) and tolerate a missing/corrupt file by starting fresh with a log line.
- Include `schema_version` and a migration path.
- Decide explicitly whether "本次运行" or "累计" is the product promise; if both, show both.
- Add a "重置统计" action reachable by controller, with confirmation.

**Warning signs:**
- Stats reset after switching apps.
- No `user://` writes in the codebase.
- Testers ask "为什么我的记录没了？"
- The app cold-starts after a long background period.

**Phase to address:** P6 (display) and P8 (persistence/lifecycle).

---

### Pitfall M7: Shipping every ABI and a debug build, then wondering why the APK is 120 MB

**What goes wrong:**
The default Android preset includes arm64-v8a, armeabi-v7a, and x86_64, and "Export With Debug" adds symbols and a debug runtime. The APK is huge, installs slowly, and starts slower. Friends on a chat app may refuse to download it; some file managers warn about size.

**Why it happens:**
Defaults are permissive so that exports run everywhere. Side-loading has no store to strip ABIs for you.

**How to avoid:**
- Export **arm64-v8a only** for phones/tablets from 2018 onward; add armeabi-v7a only if a specific friend's device needs it. Keep x86_64 for emulator-only builds, never for distribution.
- Uncheck "Export With Debug" for friend builds; keep a separate debug preset.
- Compare sizes after each release; an unexplained jump usually means an extra ABI or a stray asset.
- Put the APK on a normal file host with a SHA-256, not only in a chat that recompresses.

**Warning signs:**
- APK > 80 MB with no audio/video assets.
- `unzip -l` shows `lib/x86_64/` in a phone build.
- Install takes 30+ seconds.
- "Export With Debug" checked in the release preset.

**Phase to address:** P3 (preset defaults) and P9 (artifact check).

---

### Pitfall M8: Side-load friction and zero diagnostics on friends' phones

**What goes wrong:**
Android 14+ requires "install unknown apps" per source app; Play Protect warns about unknown developers; some OEMs require an extra "install via USB" switch. Friends give up or install an old build. If something does go wrong, there is no `adb logcat`, no crash reporter, and the only report is "用不了". Debugging by chat takes days.

**Why it happens:**
The developer's phone already has the switches enabled and the app already trusted. Side-loading is treated as "send the APK", not as a distribution channel with its own support burden.

**How to avoid:**
- Write a one-page install guide with screenshots for the two or three OEMs your friends actually use; include "允许安装未知应用" and "Play Protect → 仍要安装".
- Put the version name/code and build date on the app's about screen, and in the filename (`fifa-trainer-0.3.2-7.apk`).
- Build an in-app diagnostics screen: device model, Android version, controller name, raw axis snapshot, measured event rate, last 20 outcomes, export a log to `user://` and share via the Android share sheet.
- Log to `user://logs/session-*.log` with rotation; `print()` alone goes to logcat, which friends cannot access.
- Publish a SHA-256 next to the APK and tell friends how to verify it (or at least that it exists).
- Keep a "safe mode" build with verbose overlay enabled by a controller combo, so a friend can send a screenshot.

**Warning signs:**
- The only install instruction is "点这个 APK".
- No version number visible in the app.
- Bug reports are one sentence with no device name.
- Every fix requires a round trip.

**Phase to address:** P8 (logging/diagnostics) and P9 (install guide + artifact naming).

---

### Pitfall M9: Assuming landscape lock and a fixed layout on tablets

**What goes wrong:**
The desktop UI is a fixed 900×620 layout. The port sets landscape and anchors nothing. On a phone it is cramped; on a tablet running Android 16 with `targetSdk 36`, **orientation and resizability restrictions are ignored on screens with smallest width ≥ 600dp** — the app can be resized or rotated into a layout it never handled. Content also draws under the status bar/notch if edge-to-edge is enforced.

**Why it happens:**
`screenOrientation="landscape"` worked for a decade. Android 16 changed the rule for large screens, and the opt-out is temporary (removed for API 37). Godot's stretch mode hides the problem until a real tablet.

**How to avoid:**
- Design a layout that works in both orientations, or at least degrades gracefully: a two-column trace/result layout that becomes stacked in portrait.
- Use `Control` anchors and containers, not absolute positions; test at 1080×2400, 1440×3200, and 2560×1600.
- Respect `DisplayServer.get_display_safe_area()` and the cutout; keep critical text out of the top/bottom 48 dp.
- Do not rely on orientation lock for tablets. If a specific orientation is required, treat it as a preference and handle rotation.
- Test on a tablet (or a large-screen emulator) with Android 16.

**Warning signs:**
- Text overlaps the notch or status bar.
- Rotating the tablet breaks the layout.
- Cards overflow the screen at small heights (the desktop's 12-skill overflow bug is inherited).
- The UI is unreadable at 1 m on a phone.

**Phase to address:** P6 (layout), verified in P9 on at least one large screen.

---

### Pitfall M10: Carrying over per-sample magic constants that are frame-rate dependent

**What goes wrong:**
The Python code has per-sample heuristics: `motion_delta = 2.0°`, `abs(mag - last_mag) >= 0.05`, `swept >= 5.0`, `_last_path_t >= 0.008`. At 250 Hz they mean one thing; at 60–125 Hz with bursty event delivery they mean another. Example: `angle_diff(ref, angle) >= 2°` is true on almost every 60 Hz sample during any motion, so `_last_motion` is refreshed constantly and the "中途停住" failure effectively stops firing. Conversely, a noisy stick at 60 Hz can exceed 2° of jitter and keep a stalled gesture alive forever.

**Why it happens:**
The constants are not in `skills_config.json`, so a config-parity review will not catch them. They are buried in `detectors.py` and look like algorithm details rather than sampling assumptions.

**How to avoid:**
- Inventory every per-sample constant and classify it: "rate-independent" (thresholds in degrees/ms) vs "rate-dependent" (per-sample deltas). Put the rate-dependent ones behind named constants with a comment stating the assumed sample interval.
- Re-express rate-dependent checks in terms of **angular velocity** or **time since last change**, not per-sample deltas: e.g. "moved ≥2° since the last update" → "≥2° and ≥8 ms since last motion timestamp".
- Golden traces must include a 60 Hz, a 120 Hz, and a bursty/irregular trace of the same physical gesture; assert the same outcome codes.
- Log the per-sample delta distribution on device; if p95 is >10°, the constants need retuning.

**Warning signs:**
- The same gesture passes at 120 Hz and fails at 60 Hz (or vice versa).
- "中途停住" never appears on mobile but appears on desktop.
- A held stick with slight drift never times out.
- Detector tuning changes behaviour on desktop.

**Phase to address:** P5, with a dedicated "sampling assumptions" review before parity sign-off.

---

### Pitfall M11: macOS filesystem assumptions that break inside the APK

**What goes wrong:**
APFS is case-insensitive by default, and macOS normalises Unicode filenames (NFD). A `res://` path that works locally (`res://UI/Skills.json` vs `ui/skills.json`, or a Chinese filename typed with different normalisation) fails on Android, where the APK is case-sensitive and byte-exact. `.DS_Store` and other macOS droppings can also end up in the export if the filter is wrong.

**Why it happens:**
The editor resolves paths through the local filesystem, so it "just works". The failure appears only in the exported APK, often as a missing texture or a config that loads to `null`.

**How to avoid:**
- Enforce lowercase ASCII for all `res://` file and directory names; keep Chinese only in content, never in paths.
- Add a CI/export check that greps for mixed-case path references and non-ASCII filenames.
- Add `.DS_Store`, `._*`, and `.git*` to the export exclude filter; verify with `unzip -l`.
- On a case-sensitive volume (or Linux CI), open the project once to catch path mismatches early.

**Warning signs:**
- Editor runs, exported APK shows a missing resource.
- Errors mention a path with different capitalisation than the file.
- `.DS_Store` appears in `unzip -l`.
- Chinese-named assets load on one machine but not another.

**Phase to address:** P3 (project layout) and P9 (artifact inspection).

---

### Pitfall M12: Shipping `export_presets.cfg` with keystore secrets

**What goes wrong:**
Godot stores keystore path, alias, and password in `export_presets.cfg`. Committing it (or sharing the project folder) leaks the signing key password. If the repo is public, anyone can sign an APK that Android treats as an update to your app. Even in a private repo, the secret spreads to every clone and CI log.

**Why it happens:**
The file must be committed for reproducible presets, and it is not obvious that it contains secrets. `.gitignore` often misses it because "the preset is project config".

**How to avoid:**
- Keep `export_presets.cfg` in the repo **only** with secrets removed; inject `GODOT_ANDROID_KEYSTORE_RELEASE_PATH/USER/PASSWORD` at export time.
- If a secret was ever committed, rotate the keystore (and accept that friends must uninstall once) or treat the key as compromised.
- Add a pre-commit grep for `keystore/release_password`, `keystore/debug_password`, and `storepass`.
- Store the actual keystore outside the repo; back it up separately.

**Warning signs:**
- `git log -p -- export_presets.cfg` shows a password.
- The keystore file is inside the repo.
- CI logs print the export command with `--keystore-password`.
- A public fork contains your preset.

**Phase to address:** P3 (repo hygiene) and P9 (release audit).

---

### Pitfall M13: Changing `minSdk` / `targetSdk` without understanding which build path uses them

**What goes wrong:**
Godot 4.5–4.7 default to `minSdk 24` (Android 7.0) and `targetSdk 35` (4.5/4.6) or `36` (4.7). Someone lowers `minSdk` to 21 to support an old phone: if any Android plugin/AAR declares `minSdk 24`, the manifest merger fails with `uses-sdk:minSdkVersion 21 cannot be smaller than version 24 declared in library`. Or someone raises `minSdk` to 26 and silently drops friends' older devices. Separately, `gradle_build/min_sdk` and `gradle_build/target_sdk` only take effect when `use_gradle_build = true`; a template-based export ignores them, so the "fix" appears to do nothing. Lowering `targetSdk` below 23 makes Android 14+ refuse installation entirely; changing it to 36 on a tablet triggers the Android 16 orientation behaviour (M9).

**Why it happens:**
The export preset exposes min/target SDK next to the package name, so it looks like a normal setting. The template vs Gradle build distinction is buried in the preset, and most tutorials never mention it.

**How to avoid:**
- Keep the defaults (`minSdk 24`, `targetSdk 35` or `36`) unless a named device requires otherwise. Write the supported Android range in `BUILD.md` and the store/README text.
- Before adding any plugin, read its `AndroidManifest.xml` `minSdk`; adopt only if ≤ Godot's default, or raise `gradle_build/min_sdk` deliberately and re-test the oldest supported phone.
- Remember: custom min/target SDK requires `use_gradle_build = true`; otherwise the preset values are inert.
- Verify the built artifact's merged manifest (`aapt dump badging app.apk` or APK Analyzer), not the preset UI.
- Do not hand-edit the generated `AndroidManifest.xml`; it is regenerated on every export.

**Warning signs:**
- Manifest merger error mentioning `uses-sdk:minSdkVersion`.
- The preset says one thing; `aapt dump badging` says another.
- The app installs on the dev phone but not on an older friend's phone.
- A plugin works in the editor but the export fails during Gradle.
- Android 14 refuses to install with no clear reason.

**Phase to address:** P3 (preset defaults + supported range) and P9 (artifact verification).

---

## Minor Pitfalls

### Pitfall m1: Exact-string and exact-float parity assertions

**What goes wrong:**
Python formats with `f"{x:.0f}"` (round-half-even) and GDScript `"%d" % round(x)` or `"%.0f"` may round half away from zero; Python floats are doubles, GDScript `Vector2` components are 32-bit. A parity test that asserts exact strings or exact values fails on boundary cases and gets muted, hiding real regressions.

**Why it happens:**
The two runtimes format and store numbers differently, and exact equality looks like the strictest possible test — so it is the first thing written and the first thing disabled when it flakes.

**How to avoid:** Assert outcome **codes** and numeric values with tolerances (angle ±0.5°, time ±5 ms, magnitude ±0.005). Keep message snapshots as a separate, non-blocking report. Use plain `float` + `atan2`, not `Vector2`, in the math core.

**Warning signs:** Tests fail only on `.5` values; the team starts `round()`-ing to make tests pass; parity tests are skipped "because they're flaky".

**Phase to address:** P5.

---

### Pitfall m2: `JSON.parse_string()` returning `null` without a line number

**What goes wrong:**
A malformed config yields `null`, and the app either crashes later or shows a generic "配置加载失败". Python's error message names the line and column; the port loses that, making a friend's hand-edited config undebuggable.

**Why it happens:**
`JSON.parse_string()` is the convenient one-liner, and it returns `null` on failure while the error detail lives on a separate `JSON` instance that the caller never created.

**How to avoid:** Use `JSON.new().parse(text)` and report `get_error_line()` / `get_error_message()`; validate the parsed type (`Dictionary`) before use; reject BOM and non-UTF-8 explicitly.

**Warning signs:** "配置无效" with no path or line; a config error that only reproduces on one machine.

**Phase to address:** P2/P5.

---

### Pitfall m3: String booleans and `null` numerics behaving differently in GDScript

**What goes wrong:**
`bool("false")` is `true` in GDScript just like Python. `float(null)` errors. A config with `"enabled": "false"` or `"cooldown_ms": null` behaves differently in the two implementations — one silently enables the skill, the other crashes at a different point. The desktop already has both bugs (`CONCERNS.md` Known Bugs #2 and #3).

**Why it happens:**
Both languages are dynamically typed and coerce truthiness; the port copies the desktop's loose parsing because it looks like "the same code".

**How to avoid:** One strict accessor layer (`as_bool`, `as_int`, `as_float`) that accepts only the intended JSON types (plus deliberate `"true"`/`"false"` strings), rejects `null` with a field path, and is shared by both parsers via the same fixture corpus. Do not port the bugs; fix both sides in P2 and add regression fixtures.

**Warning signs:** A skill is enabled when the JSON says `false`; a `TypeError` traceback instead of a friendly message; Python and GDScript disagree on the same file.

**Phase to address:** P2 (fix both), P5 (consume).

---

### Pitfall m4: BOM / CRLF / encoding differences

**What goes wrong:**
A config saved by a Windows editor with a UTF-8 BOM fails `JSON.parse` in Python (`Unexpected UTF-8 BOM`, Known Bug #4) and may fail in Godot too. `FileAccess.get_as_text()` behaviour around BOM should not be assumed. CRLF is harmless for JSON but can break exact-match checks.

**Why it happens:**
The file is valid UTF-8 to a text editor and invalid to a JSON parser; every machine's editor, git config, and line-ending policy differs, so the failure is machine-specific.

**How to avoid:** Read bytes, strip a leading `EF BB BF` deliberately, decode UTF-8, then parse; write without BOM; add BOM and CRLF fixtures to the shared corpus; normalise line endings in generated files.

**Warning signs:** "Unexpected UTF-8 BOM"; config loads on one machine and not another; `git diff` shows whole-file changes.

**Phase to address:** P2.

---

### Pitfall m5: Export preset name / path drift breaking scripted builds

**What goes wrong:**
`godot --export-release "Android" build/app.apk` fails because the preset was renamed "Android Release" on someone's machine. Or the output path is relative to the project and the script runs from the repo root. The build works interactively and fails in a script.

**Why it happens:**
Presets live in `export_presets.cfg`, which is often gitignored (it can contain secrets) and edited per machine; the CLI addresses the preset by its human-readable name.

**How to avoid:** Commit a sanitised preset with a fixed name; have the export script assert the preset exists (`--export-release` fails loudly, but add a pre-check); use absolute paths derived from the script location; print the resolved preset, version code, and output path.

**Warning signs:** "Preset not found"; the APK lands in an unexpected directory; only the person who created the preset can build.

**Phase to address:** P3/P9.

---

### Pitfall m6: Assuming `Input.get_connected_joypads()` order is stable

**What goes wrong:**
The docs explicitly say the order of connected joypads is not guaranteed after a restart. Code that uses `[0]` or maps a saved index to a device will pick the wrong one after a reboot or a second controller connects.

**Why it happens:**
`get_connected_joypads()` returns an Array, and index 0 is the obvious choice; the ordering caveat is one sentence in the docs and easy to miss.

**How to avoid:** See M1 — resolve by identity, never by position; re-enumerate on every connection event.

**Warning signs:** The app controls the wrong controller after a reboot; the device picker shows the same name twice with different behaviour.

**Phase to address:** P4.

---

### Pitfall m7: `_process` doing per-frame allocations / string formatting in the input path

**What goes wrong:**
GDScript allocates on every `Dictionary`, `Array`, and formatted string. Building a debug line, a `Vector2`, or a `set` of held buttons on every input event at 125 Hz is usually fine, but doing it for 5 skills × several detectors and rendering a growing trace can push frame time over budget on a mid-range phone, causing dropped frames and worse sampling exactly during gestures.

**Why it happens:**
GDScript's ergonomics hide allocation, and the desktop had the same per-frame `Frame`/set construction (`CONCERNS.md` Performance #3) — the port inherits the shape without inheriting the warning.

**How to avoid:** Precompute canonical button maps; reuse arrays; draw the trace into a fixed-size ring buffer and redraw only the last N points; gate debug text behind a flag; profile on the lowest-end target phone, not the developer's flagship.

**Warning signs:** Frame time spikes during gestures; the trace grows unbounded; GC-like stutters; phone gets hot.

**Phase to address:** P6 (rendering) and P8 (long-session performance).

---

### Pitfall m8: Treating `poll_hz: 250` in the config as an instruction

**What goes wrong:**
The config says `input.poll_hz = 250`. The port either tries to run a 250 Hz loop (busy-wait, battery drain, thermal throttle) or silently ignores it, leaving a config field that lies. Detector tuning then assumes a sample rate that does not exist.

**Why it happens:**
The config was written for the desktop's dedicated 250 Hz loop and copied verbatim; on mobile nothing schedules that rate, but nobody removes or redefines the field.

**How to avoid:** On mobile, treat `poll_hz` as a **reported/expected** value, not a scheduling target. Add a startup diagnostic that prints the measured event rate and, if it differs from the config by more than ~2×, log a warning. Optionally derive a "minimum sample rate" health threshold. Document the field's meaning in both READMEs.

**Warning signs:** A `while` loop with `OS.delay_usec(4000)`; battery complaints; `poll_hz` never read; measured rate and config disagree with no warning.

**Phase to address:** P4/P5.

---

## Technical Debt Patterns

Shortcuts that look reasonable in a port, and what they cost later.

| Shortcut | Immediate benefit | Long-term cost | When acceptable |
|---|---|---|---|
| Poll `Input.get_joy_axis` in `_process` "for now" | One line, no event plumbing | Silent reversal loss; detector parity impossible; every later tuning is built on aliased data | Never — event capture is not much harder and is the foundation of parity |
| Hardcode axis/button indices after one device works | Saves a calibration screen | Every new controller/OEM is a bug report; no way to diagnose remotely | Never for a product distributed to friends |
| Port detectors only, rewrite the engine "simply" | Faster first demo | Double outcomes, wrong failure attribution, cooldown/group drift; parity claims are false | Never — the engine is part of the spec |
| Use `has_joy_vibration()` as the haptics capability check | No platform code | Backend-dependent: it can report true while nothing happens, and false while a workaround exists; a false "震动已发送" follows | Never — verify with a human, not a capability query |
| Keep the mobile `skills_config.json` as a hand-edited copy | No sync script | Drift, one-way overwrites, two truths; the exact debt the desktop already has | Only for a throwaway spike, deleted before P2 ends |
| Write user preferences into `res://` or a full `user://` copy of the config | Reuses the desktop mental model | Fails on Android (read-only), or shadows all future shared updates | Never — sparse overrides only |
| Ship a debug-signed / debug-flagged APK | No keystore decision | Can't update without uninstall; larger, slower, debuggable | Only for internal test builds, clearly labelled |
| Add an Android plugin early "to fix rumble/mapping" | Feels like progress on the hard problems | Gradle build, plugin/Godot version pinning, manifest/minSdk conflicts, more failure modes | Only as a time-boxed spike after P9, never on the critical path |
| Measure timing with `delta` because "it's the frame time" | Idiomatic Godot | Capped/smoothed delta; wrong after resume; parity tests can't reproduce | Never for judgement; fine for animation |
| Validate on the emulator only | Cheap, fast | None of the real risks are exercised; false confidence | Only for layout/regression, never for input/haptics/pairing |

---

## Integration Gotchas

| Integration | Common mistake | Correct approach |
|---|---|---|
| Godot ↔ Android controller | Assuming SDL mapping applies on Android | Build a per-device axis probe; store a profile; never hardcode indices |
| Godot ↔ Android lifecycle | Ignoring `NOTIFICATION_APPLICATION_PAUSED/RESUMED` | Hard-reset detectors, clear pressed state, ignore the first frames, require neutral re-arm |
| Godot ↔ Android haptics | Calling `start_joy_vibration` and trusting it | Treat controller rumble as unavailable; use `vibrate_handheld` only as a labelled phone buzz; user-confirmed test |
| Godot ↔ Python config | Two parsers, two validators, two truths | One shared fixture corpus; compare normalised objects and error codes; SHA-256 gate on the generated copy |
| Godot ↔ `res://` on Android | Writing config back into the APK | Read-only `res://`; sparse `user://overrides.json`; atomic writes |
| Godot ↔ Android export toolchain | Mixing JDK/SDK/NDK versions from different tutorials | Pin Godot + JDK 17 + exact SDK/NDK per version; script the export; record in `BUILD.md` |
| Android ↔ Bluetooth controller | Assuming "Xbox controller" means Bluetooth | Publish supported models (Xbox One S/Series/Elite 2; DualSense/DS4); include pairing steps; handle "connected to another host" |
| Mac host ↔ APK | Case-insensitive/Unicode paths that work locally | Lowercase ASCII `res://` paths; verify on a case-sensitive volume/CI; exclude `.DS_Store` |
| App ↔ friend's phone | No logs, no version, no install guide | In-app diagnostics + shareable log; visible version; per-OEM install instructions; SHA-256 |
| Android 16 ↔ layout | Relying on `screenOrientation` on tablets | Adaptive layout; safe-area handling; test on sw600dp with targetSdk 36 |

---

## Performance Traps

| Trap | Symptoms | Prevention | When it breaks |
|---|---|---|---|
| Rendering the full trace path every frame | Frame time grows with session length; stutter during gestures | Fixed-size ring buffer (e.g. 256 points); redraw only the visible window | After a few minutes of continuous motion |
| Per-event `Dictionary`/`Array`/string allocation | GC-like hitches; frame spikes at 125 Hz | Reuse buffers; precompute button maps; gate debug strings | Mid-range phones, long sessions |
| Debug overlay formatting every event | Fine on flagship, janky on target phone | Format at 10 Hz, not per event; disable in release | As soon as the log overlay is enabled |
| Synchronous file writes in the input path | Missed samples, delayed feedback (the desktop's known bottleneck) | Queue log lines; flush on a timer/worker; never write in `_input` | Any slow storage / antivirus / low-end eMMC |
| Idle cadence drop (variable refresh / Swappy / power saving) | First gesture after idle mis-detects; idle FPS differs from active FPS | Keep a stable frame cadence; measure idle and active rates; consider disabling frame pacing | When the user pauses to think |
| Thermal throttling after long play | Hit rate degrades over 10–20 min | Cap render FPS, keep visuals cheap, measure skin temperature/battery | Bed/sofa sessions, charging while playing |
| Unbounded history/log in memory | Memory growth, slower UI | Ring buffers, rotation, size caps | Long sessions |
| `get_connected_joypads()` every frame | Small but pointless allocation/lock | Cache, refresh on `joy_connection_changed` and resume | Never visible at 5 skills, but bad hygiene |

---

## Security Mistakes

This is a local, single-user app with no network or accounts; the realistic risks are distribution integrity and signing-key handling.

| Mistake | Risk | Prevention |
|---|---|---|
| Committing keystore passwords in `export_presets.cfg` | Anyone with the repo can sign an APK Android accepts as your update | Env vars only; sanitise the committed preset; pre-commit grep; rotate if leaked |
| Storing the keystore in the repo | Same, plus loss of the key if the repo is public/leaked | Keep it outside the repo, back it up offline |
| Shipping a debuggable build | Larger attack surface, `run-as` access to app data, Play Protect warnings | Uncheck "Export With Debug"; verify `android:debuggable` is absent |
| Requesting unnecessary permissions | Scary install screen; friends abandon the install | Only VIBRATE (if phone haptics), no INTERNET/storage/location |
| Distributing an unverifiable APK | Impersonation/malware in a friend's chat | Publish SHA-256; sign consistently; share from one canonical link |
| Trusting a hand-edited config as harmless | Extreme values freeze startup or disable detection (desktop has unbounded `startup_test_ms`, `skills` count) | Validate ranges, cap list sizes, fail with field paths, never `eval` |
| Logging device names/paths/samples indefinitely | Privacy (play patterns, local paths) if shared publicly | Rotate logs, document contents, offer redaction, cap size |

---

## UX Pitfalls

| Pitfall | User impact | Better approach |
|---|---|---|
| Xbox button names shown to DualSense users ("按 X", "按 RB") | The user presses Cross instead of Square; "绿色搓射" never triggers | Canonicalise internally, display brand-appropriate labels (□/△/○/×, R1/L1) based on the detected controller; show both if unknown |
| Result visible for <1 s, or only while the stick is moving | User looks down and sees nothing; no learning | Persist the last outcome until the next attempt starts, minimum 1.5 s; keep a 5-row history |
| Success conveyed only by vibration | Android has no controller rumble; phone buzz may be inaudible/imperceptible on a stand | Visual success banner + optional sound + labelled phone buzz; never haptic-only |
| Touch-only start/pause/recovery | User must put the controller down, breaking the practice loop | Controller-first focus navigation; A to start, Start to pause; no runtime permission dialogs |
| Failure message is a wall of degrees | User cannot tell what to change | One large cause ("太快了"), one small number ("180ms / ≥250ms"), one trace with the failing segment highlighted |
| No guidance when the controller is absent or paired elsewhere | "用不了" with no next step | Show device name/connection state, pairing steps for Xbox/DualSense, and a "重新扫描" action reachable by controller |
| Screen dims or sleeps mid-session | User loses the trace and the result | `keep_screen_on = true` + `screen_set_keep_on(true)`; verify after 5 min idle; high-contrast dark theme that survives adaptive brightness |
| Layout designed at 900×620 | Tiny or overflowing on phone/tablet; text under the notch | Container-based responsive layout; test phone portrait/landscape and tablet; safe-area insets |
| Stats reset on every app kill | Feels like a demo, not a trainer | Persist progress in `user://`; show "本次" and "累计" distinctly |
| No onboarding for the 5 actions | User does not know what to practise or how to hold the stick | A short "动作列表 + 演示轨迹" screen; let the user pick one action to focus; show the expected path |
| Trace is drawn in raw axis coordinates | The visual is mirrored/rotated versus the physical stick | Draw with the same `angle_of` convention as the detector; label 前/后/左/右 on the canvas |
| Feedback after release only | Up to 1 s delay between action and result; association lost | Emit the outcome on the hit frame; the release-hold logic governs re-arming, not display |

---

## "Looks Done But Isn't" Checklist

- [ ] **Rumble:** A human confirms they felt it on the target phone+controller — not `start_joy_vibration` returning, not `has_joy_vibration()`, not a log line. If no one felt it, the feature is "unavailable", not "done".
- [ ] **Axis mapping:** Right stick up/right/down/left produce 0/90/180/270 on **both** Xbox and DualSense, on **two** phones. "It works on my phone" is not a check.
- [ ] **Triggers:** LT and RT each register only when physically pressed, with the correct rest value, on both brands. The RT modifier option is either verified or hidden.
- [ ] **Detector parity:** A recorded trace from the Python app produces the same outcome code and elapsed_ms ±5 ms in GDScript.
- [ ] **Engine parity:** Two skills competing for one motion produce exactly one outcome; success + failure for the same gesture is impossible.
- [ ] **Timing source:** `delta` and `get_unix_time_from_system` are absent from all judgement code; `Time.get_ticks_usec` is the only clock.
- [ ] **Pause/resume:** Background the app for 2 minutes mid-gesture, return, and confirm no false failure and no spurious hit.
- [ ] **Screen-off:** Lock the phone mid-session, unlock, and confirm the app recovers without a restart and the screen stays on during normal use.
- [ ] **Disconnect:** Unplug/turn off the controller mid-gesture; confirm a clear message, no stuck vibration, and automatic recovery on reconnect (including a new device index).
- [ ] **Config sync:** Edit `shared/skills_config.json`, run the sync + export, and confirm the app's behaviour changes; then hand-edit the generated copy and confirm the export **fails**.
- [ ] **Config write:** Change a user preference, kill the app, relaunch, and confirm it persists without shadowing a shared-rule update.
- [ ] **Fonts:** The longest Chinese string and all symbols (`° ± → ✓ ✗`) render on a second OEM phone.
- [ ] **Update path:** Install v1, record progress, install v2 with the same key and a higher versionCode, confirm progress survives without uninstall.
- [ ] **Install path:** A friend who has never side-loaded follows the guide on their own phone without your help.
- [ ] **Artifact:** Release APK is arm64-only, not debuggable, version visible in-app, SHA-256 published, size acceptable.
- [ ] **Idle sampling:** Leave the app idle for 60 s, then perform a fast gesture; the measured event rate during the gesture is acceptable.
- [ ] **One-handed:** The whole session (start, practise, review, pause, quit) is possible without touching the phone.

---

## Recovery Strategies

| Pitfall | Recovery cost | Recovery steps |
|---|---|---|
| Controller rumble doesn't exist on Android | LOW (if designed visual-first) | Declare haptics unavailable on Android in the UI; keep the phone-buzz option; revisit with an Android plugin only if users ask |
| Axis mapping wrong on a friend's device | MEDIUM | Ship the guided axis probe + per-device profile; have the friend run it and send a screenshot; add the device to the matrix |
| Detector parity broken after port | HIGH | Freeze feature work; fix `geometry.gd` and `_deadzone` first; rerun the full golden corpus; do not "tune" thresholds to compensate |
| Export toolchain broken / machine-specific | MEDIUM | Revert to the tagged known-good Godot + SDK/NDK combination; rebuild on the recorded machine; do not upgrade mid-release |
| Signature mismatch on update | HIGH (data loss) | If the old key is gone, friends must uninstall; restore progress from a manual export if available; prevent by backing up the key |
| APK won't install on a new phone | MEDIUM | Check ABI (arm64), 16 KB alignment, minSdk, targetSdk, unknown-sources setting, Play Protect; collect `adb logcat` if possible |
| Font tofu on a friend's phone | LOW–MEDIUM | Ship a bundled CJK fallback in the next build; add a font self-test screen; do not rely on system fonts alone |
| Config drift discovered late | MEDIUM | Regenerate from `shared/`, diff behaviour, add the hash gate, re-run the 5-skill parity set; never hand-merge |
| Stats lost after process death | LOW–MEDIUM | Add `user://` persistence with atomic writes; accept the one-time loss; add a "session restored" log line |
| Haptics/feedback not noticed in testing | LOW | Extend result display time, add sound, increase contrast; re-test with vibration off |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention phase | Verification |
|---|---|---|
| C1 Android controller rumble is a no-op | P7 (design in P6) | A human confirms whether anything was felt; UI never claims controller rumble |
| C2 Android mapping ≠ desktop | P4 | Guided probe passes on 2 phones × 2 controllers; raw axis snapshot in diagnostics |
| C3 Polling loses intra-frame reversals | P4, P5 | Fast feint trace produces the same outcome as Python; `samples` ≈ event count |
| C4 `delta` / wall clock in judgement | P5 | Grep proves no `delta`/`get_unix_time` in detector/engine; resume test shows sane elapsed_ms |
| C5 No pause/resume discontinuity handling | P8 (hooks in P5) | 2-minute background mid-gesture → no false outcome; reconnect → no restart needed |
| C6 Engine arbitration not ported | P5 | Competing-skill trace yields one outcome; successes + failures = attempts |
| C7 Angle convention wrong | P5 (helper in P4) | 8-direction unit test; Roulette/Stepover golden traces |
| C8 Wrong deadzone model | P4 | 8×5 fixture matches Python within 1e-4; diagonal magnitude >1 preserved |
| C9 Triggers as buttons / no rest calibration | P4, P6 | LT/RT only register when pressed on both brands; RT option verified or hidden |
| C10 CJK font fallback | P3 decision, P6 UI | Longest Chinese string renders on a second OEM phone |
| C11 Stale Android toolchain | P3 | `doctor` script passes; signed APK installs; toolchain recorded in `BUILD.md` |
| C12 16 KB page incompatibility | P3, P9 | `zipalign -c -P 16` passes; installs on an Android 15+ device |
| C13 Keystore/package/versionCode | P3, P9 | v1→v2 update preserves data without uninstall |
| C14 Config dual copy / res:// writes | P2, P9 | Hash gate fails on drift; preference survives restart without shadowing shared rules |
| C15 Emulator-only validation | P3 onward | Every phase gate names the physical device/controller used |
| M1 Device ID instability | P4, P8 | Controller sleep/reconnect recovers automatically; order change handled |
| M2 Multiple/virtual controllers | P4, P8 | Only the selected device drives the engine; two-controller test passes |
| M3 Idle cadence drop / frame pacing | P4, P8 | Idle vs active event rate measured; fast gesture after 60 s idle still detected |
| M4 Feedback too fast/subtle | P6 | Tester can state the outcome 2 s later with vibration off |
| M5 Touch-only interaction | P6 | Full session possible with controller only |
| M6 Stats lost on process death | P6, P8 | Force-stop → relaunch → progress intact |
| M7 APK size/ABIs/debug | P3, P9 | `unzip -l` shows arm64 only; not debuggable; size recorded |
| M8 Side-load friction/no diagnostics | P8, P9 | A friend installs unaided; diagnostics screen exports a log |
| M9 Orientation/tablet/safe area | P6, P9 | Phone portrait/landscape + tablet Android 16 layouts usable |
| M10 Frame-rate-dependent constants | P5 | 60/120/bursty traces agree; stop-detection fires on mobile |
| M11 macOS path assumptions | P3, P9 | No mixed-case/non-ASCII `res://` paths; APK has no `.DS_Store` |
| M12 Keystore secrets in repo | P3, P9 | `git log -p` clean; env-var export; pre-commit grep |
| M13 minSdk/targetSdk conflicts | P3, P9 | Merged manifest (`aapt dump badging`) matches intent; oldest supported phone installs; plugin minSdk checked |
| m1 Exact float/string parity | P5 | Tolerance-based assertions; no flaky parity tests |
| m2 JSON errors without line numbers | P2, P5 | Malformed fixture reports file/line/message in both |
| m3 String booleans / null numbers | P2 | Shared invalid fixtures rejected identically by both parsers |
| m4 BOM/CRLF | P2 | BOM fixture loads or fails with a clear message on both |
| m5 Preset name/path drift | P3, P9 | Scripted export works from a clean clone |
| m6 Unstable joypad order | P4 | Reboot + two-controller test selects the right device |
| m7 Per-frame allocations | P6, P8 | Frame time stable on the lowest-end target during a gesture |
| m8 `poll_hz` treated as a command | P4, P5 | Measured rate logged; no busy-wait; config meaning documented |

---

## Sources

Primary sources were fetched directly; community reports are labelled.

| Source | Used for | Confidence |
|---|---|---|
| `padskills/engine.py`, `detectors.py`, `geometry.py`, `input_source.py`, `config.py`, `skills_config.json` (repo) | Angle convention, deadzone formula, trigger synthesis, engine arbitration, config aliases | HIGH |
| `.planning/codebase/CONCERNS.md` (repo) | Known config/validation/rumble/UI debts not to carry over | HIGH |
| Godot docs — *Exporting for Android* (4.5 and 4.7) | JDK 17, SDK/build-tools/NDK/CMake versions, Homebrew warning, template mismatch | HIGH |
| Godot docs — *Controllers, gamepads, and joysticks* (4.5–4.7) | Android uses custom (non-SDL) input; reliability warning; vibration section; mapping troubleshooting | HIGH |
| Godot docs — `Input` class reference | `start_joy_vibration`, `has_joy_vibration`, `vibrate_handheld`, `get_joy_info`, `get_joy_guid`, `use_accumulated_input` | HIGH |
| Godot docs — `Node._process` / `ProjectSettings` | Delta cap/smoothing; `keep_screen_on = true` default | HIGH |
| Godot docs — *Using Fonts* | Open Sans default; system-font fallback; Android system-font loading unreliable | HIGH |
| Godot source (`core/input/input.cpp`, `input_event.cpp`, `platform/android/*`) | Vibration is stored but never consumed on Android; only mouse motion implements `accumulate()`; no Android rumble code | HIGH |
| Godot issue #73446 | Controller vibration not working on Android; open since 2023; no implementation | MEDIUM |
| Godot issue #106313 / PR #106358 | 16 KB page alignment fixed in 4.5 via NDK r28b | HIGH |
| Godot forum — "Something is wrong with xbox remotes on mobile" (May 2025), PR #106021 | Xbox LT/RT swap on Android | MEDIUM |
| Godot forum — "Incorrect input behaviour when using PS5 Controller with Android phones" (Oct 2025) | DualSense trigger/mapping problems on specific Samsungs/Nokia | MEDIUM |
| Android Developers — *Support 16 KB page sizes*; *App orientation… Android 16* | 16 KB requirement; targetSdk 36 ignores orientation/resizability on sw600dp | HIGH |
| Android Developers — game controller input / `InputDevice.getVibrator()` | OS-level controller vibrator exists; Godot doesn't use it | HIGH |

---

*Pitfalls research for: Android-first Godot 4 gamepad gesture trainer*
*Researched: 2026-11-04*
