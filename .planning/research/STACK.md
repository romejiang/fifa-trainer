# Stack Research — Godot 4 安卓手柄动作训练器

**Domain:** Godot 4 / Android 2D 实时手柄轨迹识别 + 视觉反馈
**Researched:** 2026-11-04
**Confidence:** HIGH（版本与 API 事实）/ MEDIUM（真机时序与震动降级路径）
**Brownfield 备注:** 本文只覆盖 `mobile/` 侧。现有 Python + pygame-ce 桌面栈见 `.planning/codebase/STACK.md`，不重复研究。

---

## TL;DR — 五条必须先知道的结论

1. **锁定 Godot `4.7.2-stable`**（2026-08-18）。不存在 Godot 4.x LTS：按官方发布策略，LTS 只在**新的 major 版本发布后**才落到上一个 major 分支（现在 LTS 是 3.6）。`4.8` 目前是 beta2，不可用于本项目。【HIGH】
2. **安卓上 `Input.start_joy_vibration()` 不会让手柄震动。** 这不是配置问题，是引擎实现缺失：Godot 4.5 起 Windows/macOS/Linux/iOS 用 SDL3 手柄驱动，**Android 仍走自研 `InputDevice` 路径**，从不注册 `JoypadFeatures`，因此 `Input.has_joy_vibration()` 在安卓恒为 `false`，`start_joy_vibration()` 只写内部状态、没有硬件出口。官方文档亦写明"controller features 目前仅支持 Windows / macOS / iOS / Linux"。【HIGH — 源码 + 官方文档双重确认】
3. **安卓上真正可用的震动只有 `Input.vibrate_handheld()`**（震手机/平板本体，需要导出预设勾选 `permissions/vibrate`）。这应当作为本项目震动的主路径，而不是降级路径。【HIGH】
4. **安卓上没有任何 SDL 手柄映射表。** `fallback_mapping == -1` → `Input` 直接把 Android 原始轴序号当 `JoyAxis` 用（X/Y/Z/RZ/LT/RT 排序后恰好对齐 0–5）。这对手柄摇杆够用，但没有 GUID 数据库兜底，属于"能用但脆"。【HIGH — 源码】
5. **默认输入是"每帧 flush 一次"**，同一帧内所有手柄事件拿到同一个时间戳 → 时间分辨率 = 帧间隔（60 Hz 屏约 16.7 ms，桌面版是 4 ms）。开 `Input.set_use_accumulated_input(false)` 可改为收到即派发；官方文档正是为"手绘线条"场景推荐这个开关。**必须在真机上量化抖动后再定判定容差。**【HIGH — 源码；抖动幅度必须实测】

---

## Recommended Stack

### Core Technologies

| 技术 | 版本 | 用途 | 为什么选它 |
|------|------|------|-----------|
| Godot Engine（标准版，非 .NET） | **4.7.2-stable**（tag `4.7.2-stable`） | 引擎 / 渲染 / 输入 / 场景 | 当前 stable 分支最新补丁；4.6 在 4.8 发布后即降级为 partial 支持；4.7 带来 GDScript 直接实现 Java 接口（`JavaClassWrapper`），让"不写插件也能碰 Android API"成为现实路径 |【HIGH】
| GDScript 2.0 | 随 4.7.2 | 全部业务代码 | 纯 2D + 5 个动作 + 无热路径性能压力；C# 在 Android 上官方标注为 experimental 且有额外限制，不值得为 3.7k 行逻辑引入第二个工具链 |【HIGH】
| 渲染后端：**Compatibility（OpenGL ES 3.0）** | `rendering/renderer/rendering_method = "gl_compatibility"` | 2D 渲染 | 把 minSdk 压回 **24**（Vulkan 路径默认 29）；2D UI 应用用不上 Mobile/Forward+；老平板与廉价机兼容性最好，启动更快、更省电 |【HIGH — 源码 `VULKAN_MIN_SDK_VERSION = 29`】

> 说明：Godot 的 Android 默认 `minSdk = 24`、`targetSdk = 36`、`compileSdk = 36`、`buildTools 36.1.0`、`NDK 29.0.14206865`、AGP 8.6.1、Kotlin 2.1.21、Java 17 —— 全部取自 `4.7.2-stable` 的 `platform/android/java/app/config.gradle`。【HIGH】

### Supporting Libraries

| 库 | 版本 | 用途 | 何时用 |
|----|------|------|--------|
| GUT（Godot Unit Test） | **9.7.1**（2026-07-10） | GDScript 单元测试 + 无头 CI | **默认选它。** 9.7.0 专门适配了 4.7 更严格的返回值类型检查；`extends GutTest` + `assert_*` 的写法最接近桌面版手写 `check()`；纯 GDScript，不引入 .NET |【HIGH】
| gdUnit4 | 6.2.3（2026-11-01） | 备选测试框架（含 mock / scene runner / C#） | 只在需要 mock、场景级输入回放、或将来上 C# 时换。它的 6.2.3 修的就是"全新 4.7 编辑器字体报错"，说明 4.7 支持到位 |【HIGH】
| `JavaClassWrapper` + `AndroidRuntime`（引擎内置，非第三方） | 随 4.7.2 | 从 GDScript 直接调 `android.os.*` / `android.view.*` | 补 `vibrate_handheld` 覆盖不到的场景（如申请 120 Hz 显示模式）；零插件、零 Gradle |【HIGH — 官方文档有完整示例】
| Godot Android Plugin v2（Kotlin/AAR） | 仅必要时 | 真正的手柄 rumble（`InputDevice.getVibrator()` / `VibratorManager`）、真实硬件时间戳 | **明确推迟**。只有真机验证证明"手机震动不够 + JavaClassWrapper 走不通"才做 |【MEDIUM】

### Development Tools

| 工具 | 用途 | 备注 |
|------|------|------|
| Temurin JDK **17**（arm64） | Godot 导出 Android 的 Java 工具链 | 官方原文："Higher versions of the JDK are also supported, but we recommend using JDK 17"。在 Editor Settings → **Java SDK Path** 指向它，不要依赖 `JAVA_HOME`【HIGH】
| Android SDK（**不要用 Homebrew 装**） | `apksigner` / `zipalign` / `adb` / 可选 `android-36` 平台 | 官方警告：macOS 上 Homebrew 的 Android SDK 不在统一位置，Godot 找不到。路径形如 `/Users/$USER/Library/Android/sdk/`，且必须含 `platform-tools/adb`【HIGH】
| Godot Export Templates **4.7.2.stable** | 打包 APK | 目录 `~/Library/Application Support/Godot/export_templates/4.7.2.stable/`。版本必须与编辑器**完全一致**（含 `.stable` 后缀）【HIGH】
| Python 3.11+（复用仓库现有 uv 环境） | `shared/skills_config.json` → `mobile/` 同步与 hash 校验脚本 | 不新增依赖；与桌面版共用一套工具链【HIGH】
| `adb` | 真机部署 / logcat 取证 | 震动、配对、时序问题只能靠 `adb logcat` + 真机确认【HIGH】

---

## Installation（macOS 宿主机）

```bash
# 1) JDK 17（Apple Silicon 用 aarch64 包）
brew install --cask temurin@17
/usr/libexec/java_home -V            # 拿到路径，例如
# /Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home

# 2) Android SDK —— 用 Android Studio 或 cmdline-tools，不要 brew install android-sdk
sdkmanager --sdk_root="$HOME/Library/Android/sdk" \
  "platform-tools" \
  "build-tools;36.1.0" \
  "platforms;android-36" \
  "cmdline-tools;latest"

# 仅在需要 GDExtension / 原生代码时才装（本项目的 GDScript-only 方案不需要）
#   "cmake;3.10.2.4988404" "ndk;29.0.14206865"

# 3) 校验
adb version
ls "$HOME/Library/Android/sdk/build-tools"      # 应看到 36.1.0
```

然后在 Godot 编辑器里：

1. **Editor → Editor Settings → Android**
   - `Java SDK Path` → 上面 JDK 17 的 `Contents/Home`
   - `Android SDK Path` → `$HOME/Library/Android/sdk`
2. **Editor → Manage Export Templates → Download and Install**（4.7 支持按平台单独下载）
3. **Project → Install Android Build Template…** —— **只有**需要 Gradle build（AAB、Android 插件、改 manifest）时才装。装完会在 `res://android/build` 生成 Java 工程；`.so` 仍是预编译的，**不需要 C++ 工具链**。【HIGH — 官方文档】
4. 导出预设里勾选 `Options → Permissions → Vibrate`（映射 Android `VIBRATE` 权限）【HIGH】

**最小可行组合（侧载 APK）**：JDK 17 + platform-tools + build-tools 36.1.0 + 官方 APK 模板。**不需要** `platforms;android-36`、**不需要** NDK、**不需要** Gradle build。
**只有**要 AAB / 原生插件 / 自定义 manifest 时才升级到 Gradle build，那时才需要 `platforms;android-36`。

---

## 版本决策：为什么是 4.7.2，以及"LTS"这个问题的答案

| 时间线 | 事实 |
|--------|------|
| 2026-01-26 | Godot 4.6 stable |
| 2026-06-18 | Godot 4.7 stable |
| 2026-07-14 / 2026-08-18 | 4.7.1 / **4.7.2** stable（当前最新补丁） |
| 2026-10-29 | Godot 4.8 **beta2**（未发布 stable） |

**官方发布策略原文要点：**"Whenever a new **major** version is released, we make the previous stable branch a long-term supported release." 也就是说：

- 现在存在的是 **Godot 3.6 = 3.x LTS**；
- **Godot 4 没有、也不会有"4.x LTS"** —— 要等 Godot 5.0 出现，4.x 才会变成 LTS；
- 所以"4.x LTS vs latest"这个二选一在本项目里**不成立**，正确做法是：**跟随当前 stable 分支的最新补丁**，即 `4.7.2`。

**为什么不选 4.6.3**：4.8 一周内就会 stable，届时 4.6 会像 4.5 一样降为 partial（只收安全/平台修复）。4.7 是唯一能在整个 milestone 周期内保持 full support 的分支。

**为什么不选 4.8-beta2**：官方明确 "Pre-release Godot versions aren't intended to be used in production"。

**为什么 4.7 对本项目特别值**：Android 侧是本轮改动重点 —— GABE（Android 上直接 Gradle 导出）转正、**GDScript 可实现/重写 Java 接口**（`JavaClassWrapper` 能力扩展）、可自定义 Android 启动图、Perfetto 成为模板默认 profiling 工具、`Ignore Joypad on Unfocused Application` 项目设置。这些正好覆盖本项目要碰的几块。

**版本钉死做法（写进 roadmap）：**
- `mobile/project.godot` 的 `config/features` 会是 `PackedStringArray("4.7", "GL Compatibility")`；
- **禁止**用 4.8 打开工程（会静默升级 `project.godot` 格式）；
- CI / 本机脚本里加一条：`godot --headless --version` 输出必须等于 `4.7.2.stable`。

---

## 安卓手柄真相核查（源码级，Godot `4.7-stable` / `4.7.2-stable`）

这一节是本报告的核心。PROJECT.md 里写"外接手柄与震动是引擎级 API（`Input.start_joy_vibration()`），不需要自己写 platform channel"—— **前半句对，后半句在安卓上不成立**。以下是逐条验证结果。

### 3.1 安卓走的是"自研 InputDevice 路径"，不是 SDL

官方文档《Controllers, gamepads, and joysticks》原文：

> "Since Godot 4.5, the engine relies on **SDL 3** for controller support on Windows, macOS, and Linux… **This custom code is still used to support controllers on Android and Web**, so it may result in issues appearing only on those platforms."
>
> "#### Android — … controller support on mobile platforms relies on a custom implementation instead of using SDL for input. This means controller support may be less reliable than on desktop platforms. **Support for SDL-based controller input on mobile platforms is planned in a future release.**"

代码侧对应关系（全部在 `platform/android/`）：

| 环节 | 实现 | 后果 |
|------|------|------|
| 设备发现 | `GodotInputHandler.onInputDeviceAdded()`（Java，`InputManager.InputDeviceListener`） | 只认 `SOURCE_GAMEPAD` / `SOURCE_JOYSTICK`；名字来自 `device.getName()` |
| 轴/键 | `onGenericMotionEvent` / `onKeyEvent` → JNI → `AndroidInputHandler::process_joy_event()` → `Input::joy_axis/joy_button/joy_hat` | **只有** axis / button / hat 三种事件，**没有 rumble 出口** |
| 映射 | `Input::joy_connection_changed(device, connected, name)` —— **JNI 只传 3 个参数，不传 GUID** | `p_guid` 为空 → `uid` 退化为"设备名字符串的十六进制" |
| 特性注册 | `Input::set_joy_features()` 全仓库**只有** `drivers/sdl/joypad_sdl.cpp` 调用 | `joypad->features == nullptr` → `has_vibration = false` |
| 事件 flush | `DisplayServerAndroid::process_events()` 里 `Input::flush_buffered_events()` | 每渲染帧 flush 一次 |

### 3.2 `Input.has_joy_vibration()` 在安卓恒为 `false`

```cpp
// core/input/input.cpp
bool Input::has_joy_vibration(int p_device) const {
    const Joypad *joypad = joy_names.getptr(p_device);
    return joypad != nullptr && joypad->has_vibration;   // 安卓上没有地方把它置 true
}
```

`start_joy_vibration()` 只做一件事：

```cpp
vibration.timestamp = OS::get_singleton()->get_ticks_usec();
joy_vibration[p_device] = vibration;      // 写进 HashMap，然后……没有然后
```

硬件侧需要平台驱动去轮询 `get_joy_vibration_strength()`，而安卓平台层**不存在**这段代码（`platform/android/` 里全局搜 `vibrat` 只命中 `vibrate_handheld` 与设备震动的 `GodotNativeBridge.vibrate()`）。

**结论：`start_joy_vibration()` 在安卓上是静默空操作（silent no-op），不报错、不震动。** 这比"抛异常"更危险——测试会"通过"，用户没有反馈。【HIGH】

### 3.3 官方文档的旁证

《Controller features》（LED / 陀螺仪 / 加速度计）页首：

> **Warning:** These controller features are currently only supported on **Windows, macOS, iOS, and Linux**.

Android **不在列表里** —— 与上面的源码结论完全一致。同一页也确认 Xbox 手柄**没有**陀螺仪（本项目用不上，但排除了一条"用 gyro 辅助判定"的邪路）。

### 3.4 安卓上的轴序号是"排过序的 Android AXIS_*"，不是 SDL 映射

```java
// GodotInputHandler.onInputDeviceAdded()
Collections.sort(joystick.axes);                 // 按 Android AXIS_ 常量排序
for (int i = 0; i < joystick.axes.size(); i++)
    Log.i(TAG, " - Mapping Android axis " + joystick.axes.get(i) + " to Godot axis " + i);
```

因为 `fallback_mapping == -1`（非 XR 应用，见 `GodotNativeBridge.getInputFallbackMapping()` 返回 XR mode 的 fallback，普通模式为空 → 匹配不到），`Input::joy_axis()` 走这一支：

```cpp
if (joy.mapping == -1) { _axis_event(p_device, p_axis, p_value); return; }  // 原始序号直通
```

典型蓝牙手柄（Xbox / DualSense / DS4）的 motion ranges 为 `X(0) Y(1) Z(11) RZ(14) LTRIGGER(17) RTRIGGER(18)`，排序后下标正好 **0..5**，与 `JoyAxis{LEFT_X=0, LEFT_Y=1, RIGHT_X=2, RIGHT_Y=3, TRIGGER_LEFT=4, TRIGGER_RIGHT=5}` 一一对上。**左/右摇杆可用。** 但遇到同时上报 `RX/RY` 与 `Z/RZ` 的杂牌手柄就会错位。

按键侧反而是稳的：`getGodotButton()` 显式把 `KEYCODE_BUTTON_A/B/X/Y` 映射到 0/1/2/3，与 Godot 4.x 的 SDL 风格按钮顺序（`A=0, B=1, X=2, Y=3, BACK=4, GUIDE=5, START=6, LEFT_STICK=7, RIGHT_STICK=8, LEFT_SHOULDER=9, RIGHT_SHOULDER=10, DPAD_UP=11..14`）一一对上。`L1→9(LEFT_SHOULDER)`、`R1→10(RIGHT_SHOULDER)`、`START→6`、`SELECT/BACK→4`、`MODE→5(GUIDE)`、`THUMBL→7`、`THUMBR→8`、`DPAD_*→11..14` 也都对得上。

**另一处跨平台差异**：触发键在安卓上已经是 `0.0..1.0`，桌面是 `-1.0..1.0`（`input.cpp` 里有 `#ifndef ANDROID_ENABLED` 专门分支）。本项目判定只用摇杆，但配置校验/可视化若读扳机，必须分支处理。【HIGH】

### 3.5 设备识别：安卓能拿到什么、拿不到什么

| API | 安卓行为 | 用法建议 |
|-----|----------|----------|
| `Input.get_connected_joypads() -> Array[int]` | 正常 | 启动枚举的正确入口，以及热插拔信号不可靠时的低频兜底轮询【HIGH】|
| `Input.get_joy_name(device) -> String` | 返回 `InputDevice.getName()`，例如 `"Xbox Wireless Controller"`、`"DualSense Wireless Controller"`、`"Wireless Controller"`(DS4) | **主标识**。用它区分 Xbox / PlayStation 分支即可【HIGH】|
| `Input.get_joy_guid(device) -> String` | 返回 `joy_names[d].uid`，而安卓的 uid = **设备名的十六进制拼接**（因为 JNI 没传 GUID） | 可当"稳定 key"用于去重/记忆设备，**绝不能**拿去查 SDL/Godot 控制器数据库，也**不要**写成 `03000000...` 形式的硬编码【HIGH】|
| `Input.get_joy_info(device) -> Dictionary` | **官方：安卓与 Web 上恒为空字典** | 不要用；想要 `vendor_id`/`product_id` 只能靠原生插件【HIGH】|
| `Input.is_joy_known(device)` | 安卓恒 `false`（无映射表，`is_known` 从不置位） | 不要拿它判断"手柄被支持"【HIGH】|

### 3.6 采样率与时间戳 —— 本项目最大的技术风险

**默认路径（`Input.use_accumulated_input == true`，出厂默认）：**

```
Android UI 线程 MotionEvent
  → GodotInputHandler.handleJoystickAxisEvent  (每帧可能多次)
  → Input::joy_axis()  → parse_input_event()   → buffered_events.push_back()
  → ……… 等到本帧结束 ………
  → DisplayServerAndroid::process_events() → Input::flush_buffered_events()
  → _input() 被依次调用（同一帧内的所有事件拿到同一个 Time.get_ticks_usec()）
```

- `InputEventJoypadMotion` **不重写** `accumulate()`（只有 `InputEventMouseMotion` / `InputEventScreenDrag` 重写），所以事件**不会合并**，但**会攒到帧末**。
- 同一帧内所有样本的时间戳几乎相同。
- 有效时间分辨率 = **帧间隔**：60 Hz ≈ **16.7 ms**，120 Hz ≈ **8.3 ms**。桌面版是 **4 ms**（250 Hz）。

**改进路径（官方推荐，专为"手绘线条"场景）：**

```gdscript
func _ready() -> void:
    Input.set_use_accumulated_input(false)
```

文档原文：

> "Input accumulation can be disabled to get slightly more precise/reactive input at the cost of increased CPU usage. **In applications where drawing freehand lines is required, input accumulation should generally be disabled** while the user is drawing the line to get results that closely follow the actual input."

源码路径确认：`use_accumulated_input == false` 且 `agile_input_event_flushing == false`（默认）时，`parse_input_event()` 直接走 `_parse_input_event_impl()`，**收到即派发**，`_input()` 在事件到达时被调用，`Time.get_ticks_usec()` 才是真实到达时刻。

**但还有一关：屏幕刷新率。**
`platform/android/` 里**没有** `Surface.setFrameRate()` 或 `preferredDisplayModeId` 的任何调用（全局搜无命中）。也就是说 Godot 4.7 在安卓上**不会主动申请高刷模式**，多数设备会跑在系统默认的 60 Hz。想上 120 Hz 必须自己申请（`JavaClassWrapper` 改 `window.attributes.preferredDisplayModeId`，或原生插件）。

**因此：**

```
理论采样上限 ≈ min(手柄上报率, 屏幕刷新率)
现实预期   ≈ 60–120 Hz（且默认多半是 60 Hz）
时间戳精度 ≈ 关掉累积后 ≈ 手柄上报间隔；不关 ≈ 帧间隔
```

这**仍然满足**"60–125 Hz"的产品假设，但**必须实测**：`min_duration_ms` 这类边界阈值在 16.7 ms 量化下会抖。桌面版 250 Hz 的验收基线不能直接当移动端的验收基线用。【HIGH 事实 / 数值 MUST 真机实测】

---

## 输入 API 决策矩阵

| 需求 | 推荐 API | 不要用 | 理由 |
|------|----------|--------|------|
| 采样摇杆轨迹 | `_input()` 里收 `InputEventJoypadMotion`，**收到即** `Time.get_ticks_usec()` 打时间戳 | ❌ `_process` 里轮询 `Input.get_joy_axis()` | 轮询会**丢中间值**（手柄 120 Hz、屏幕 60 Hz 时丢掉一半样本），且轮询得到的是"上一帧最新值"，无法还原轨迹。事件驱动天然保序、不丢点【HIGH】|
| 需要"当前值快照"（UI 指针、死区显示） | 同一帧内 `Input.get_joy_axis(dev, JOY_AXIS_RIGHT_X)` | — | 这个函数读的是**原始值，不过死区**（死区只作用于 InputMap action / `get_vector`）【HIGH】|
| 死区 | **自己实现**，与桌面版同参数同算法；放在 `Sample` 归一化层，不放在采样层 | ❌ 依赖 Godot 内置死区（默认 0.5，且只对 action 生效） | 桌面版的死区阈值是判定逻辑的一部分，必须 1:1 平移；Godot 的 action 死区是"移动语义"，不是"手势语义"【HIGH】|
| 按键 | `InputEventJoypadButton` | `Input.is_action_pressed()` | 用原始 `JOY_BUTTON_*` 常量，避免 InputMap 把不同物理键折叠成同一个 action【HIGH】|
| 热插拔 | `Input.joy_connection_changed(device, connected)` 信号 + 启动时 `Input.get_connected_joypads()` | 轮询 `get_connected_joypads()` | 信号是官方入口；轮询会漏"拔了又插"同一 device id 的情况【HIGH】|
| 设备名 | `Input.get_joy_name(d)` + `OS.has_feature("mobile")` 分支 | `Input.get_joy_info()`（安卓恒空）、`Input.get_joy_guid()` 当 SDL GUID 用 | 见 §3.5【HIGH】|
| 时间源 | `Time.get_ticks_usec()`（µs，单调） | ❌ `OS.get_ticks_msec()`（ms 精度不够）、`Time.get_unix_time_from_system()`（会跳变） | 判定阈值是毫秒制，µs 存储再转 ms 才不掉精度【HIGH】|
| 帧率上限 | 保持 vsync 开启、`application/run/max_fps = 0` | ❌ 手动 `Engine.max_fps = 120` 但屏幕 60 Hz | vsync 优先于 max_fps；设了也没用，反而掩盖问题【HIGH】|
| 物理帧 | 保持 `physics/common/physics_ticks_per_second = 60`（默认） | ❌ 为了"更高采样"把它调到 240 | `_physics_process` 不会让手柄事件来得更快；只是空转 CPU。**判定逻辑不从物理帧取数据**【HIGH】|
| 防熄屏 | `display/window/energy_saving/keep_screen_on = true`（默认已开） | — | 手柄输入**不会**阻止系统息屏，Godot 默认开了这个保护；练习场景必须保留【HIGH】|

### 建议的输入服务结构（GDScript 侧）

```
PadInput (Node, autoload 或场景单例)
  _ready():  Input.set_use_accumulated_input(false)     # 单点决策，写注释说明原因
  _input(e): if e is InputEventJoypadMotion/Button:
                 emit(sample(e.device, e.axis, e.value, Time.get_ticks_usec()))
  _on_joy_connection_changed(d, c): emit(device_changed)
```

- 判定器是**纯函数**：`Detector.feed(Array[Sample]) -> Result`，不依赖 Node / 场景树 → 可以 headless 跑 182 条桌面用例。
- `Sample` 用 `RefCounted` + `class_name`，不要用 `Dictionary`（字典在热路径上是装箱的，且拼错 key 不报错）。

---

## 震动策略：三级降级（这是本报告最重要的架构建议）

Project 的约束是"震动尽力而为、可静默降级"。基于上面的源码结论，落地成一个显式接口：

```gdscript
class_name Haptics
# 后端优先级：桌面手柄 rumble → 安卓手机震动 → 静默

func pulse(weak: float, strong: float, ms: int) -> void:
    if _try_pad_rumble(weak, strong, ms):   # 只在 has_joy_vibration() 为真时走
        return
    if _try_handheld(ms):                   # 安卓：震手机本体
        return
    pass                                    # 静默
```

| 层级 | API | 平台 | 状态 |
|------|-----|------|------|
| L1 手柄马达 | `Input.has_joy_vibration(d)` 门控 → `Input.start_joy_vibration(d, weak, strong, duration_s)` | Windows / macOS / Linux / iOS | ✅ 真实可用。**必须门控**，否则安卓静默失败还占着状态【HIGH】|
| L2 手机本体 | `Input.vibrate_handheld(duration_ms: int = 500, amplitude: float = -1.0)` | Android / iOS / Web | ✅ 安卓可用，需 `permissions/vibrate`。`amplitude` 在 API 26+ 会被真正使用（`VibrationEffect.createOneShot(duration, amplitude)`）【HIGH】|
| L3 静默 | `pass` | 任意 | ✅ 默认行为【HIGH】|

**关于 `duration` 的坑：** `start_joy_vibration(duration = 0)` 意思是"尽可能长（约 65 秒）"，不是"瞬时"。本项目要的是短促反馈，**永远传显式秒数**（如 `0.08`），并在需要时 `stop_joy_vibration()`。【HIGH】

**为什么 L2 是主力而不是兜底：** 手机/平板就架在手边、甚至放在腿上，本体震动的可感知度未必低于手柄；而且它是唯一 100% 可控的通道。产品上应把"手机震动"当作正式反馈通道设计（可调强度/可关），而不是"手柄不行的补救"。【MEDIUM — 产品判断】

**什么时候才升级到原生插件（推迟到独立 phase）：**
只有同时满足三条才做：① 真机验证 L2 手感不够；② `JavaClassWrapper` 调 `InputDevice.getVibrator()` 走不通（`int[]` 返回值、重载解析、API 31 的 `VibratorManager` 都可能在 `JavaClassWrapper` 上翻车）；③ 用户明确要求。届时用 v2 插件（Kotlin，`GodotPlugin` + `@UsedByGodot`，AAR + `EditorExportPlugin` 打包），必须开 Gradle build。【MEDIUM】

**明确写进 roadmap 的验收口径：** 震动**不是**"必须震手柄"，而是"在不支持时没有任何报错、不影响判定与视觉反馈"。这条能直接消掉 PROJECT.md 里那个错误的技术前提。

---

## 数据驱动配置：`JSON.parse_string` vs 自定义 `Resource`

结论：**用 JSON，但读进来之后立刻转成强类型 `RefCounted`，不要一路传 `Dictionary`。**

| 方案 | 适用 | 本项目结论 |
|------|------|-----------|
| `FileAccess.get_file_as_string("res://data/skills_config.json")` + `JSON.parse_string()` | 与 Python/C++/CI 共享同一份文件 | ✅ **选它**。`shared/skills_config.json` 是唯一真源，JSON 是唯一能同时喂给 Python 校验器和 Godot 的格式【HIGH】|
| 自定义 `Resource` + `@export` + `.tres` | 想在 Inspector 里可视化编辑、要让引擎做类型校验 | ❌ 不用于**源文件**。`.tres` 是 Godot 私有格式，桌面版读不了，等于制造第二真源 —— 正好踩中 PROJECT.md 明令禁止的"配置多真源"债务【HIGH】|
| `JSON.parse_string()` + 手写 `Validator` → `SkillDef`（`RefCounted`） | — | ✅ **推荐形态**。把 `desktop/padskills/config.py` 的 790 行校验规则 1:1 翻成 GDScript，输入输出都是强类型对象【HIGH】|

### 必须知道的 JSON 细节

1. **导出时必须加非资源文件过滤。** 官方 troubleshooting 原文：
   > "By default, Godot will only include actual *resources* into the PCK file. Some files commonly used, such as JSON files, are not considered resources… you need to specify `*.json` in the non-resource export filter."

   → 导出预设 `Resources → Filters to export non-resource files/folders` 填 `*.json`。**这是最容易在"编辑器能跑、APK 报错"阶段踩的坑。**【HIGH】
2. **数字类型会分裂。** `"min_duration_ms": 120` 解析成 `int`，`120.0` 解析成 `float`。GDScript 是强类型的，`float(v)` 统一收口，否则 `>=` 比较/字典键在极端情况下行为不一致。【HIGH — `JSON.parse_string` 语义】
3. **`JSON.parse_string()` 失败返回 `null`，不抛异常、不带错误位置。** 需要错误信息时用 `JSON.new().parse(text)` 再读 `get_error_line()` / `get_error_message()`。配置加载失败必须**硬失败并显示在屏幕上**，不能静默用默认值——否则用户会以为"判定不准"。【HIGH】
4. **`res://` 在运行时只读。** 首版配置固定，读 `res://` 是对的；**若将来要允许用户在手机上改配置**，必须改成"首次启动把 `res://` 默认值拷到 `user://skills_config.json`，之后只读 `user://`"，并保留"恢复默认"。现在就把这条写进设计，别等到改的时候重构。【MEDIUM】

### 单一真源的落地方式（推荐）

```
shared/skills_config.json                 # 唯一提交的真源
mobile/data/skills_config.json            # 由脚本生成、提交、但带 hash 守卫
tools/sync_config.py                      # uv run tools/sync_config.py
   ├─ 生成/覆盖 mobile/data/skills_config.json
   ├─ 写 mobile/data/skills_config.sha256
   └─ 校验模式 --check：hash 不一致就 exit 1
```

- **不要用符号链接**：Godot 导出对 symlink 的支持不稳，Windows 上更麻烦。
- 生成物也提交，是为了让"打开工程就能 F5"成立；靠 `--check` 保证它不会漂。
- 生成物不是"手工维护的第二份"，符合 PROJECT.md 的约束。
- CI 顺序：`python tools/sync_config.py --check` → `godot --headless --import` → 跑测试 → 导出。

---

## 测试策略：GUT vs gdUnit4 vs 裸 headless

| 方案 | 4.7 现状 | 适用 | 结论 |
|------|---------|------|------|
| **GUT 9.7.1** | 9.7.0 明确适配 4.7 的返回值类型检查（breaking 变更写在 release notes 里）；纯 GDScript | 单元测试、参数化用例、JUnit XML 输出 | ✅ **默认** |
| gdUnit4 6.2.3 | 支持 4.6/4.7，CI 已跑在 4.8.dev7；功能更全（mock、scene runner、C#） | 需要 mock 外部依赖、或做场景级输入回放 | ⏸ 备选，不默认引入 |
| 裸 `SceneTree` 脚本（`extends SceneTree` + `-s`） | 永远可用，零依赖 | 极简 smoke / 工具脚本 | ✅ 配合 GUT 一起用（`--check-only` 做语法闸门） |
| `godot --test` | ⚠️ **不是给项目用的**：需要把引擎源码用 `tests=yes` 编译 | Godot 引擎自身的单元测试 | ❌ 别被 CLI 文档误导 |

### 推荐的跑法（本地 + CI 同一套）

```bash
# 0) 语法闸门（快，几秒）
godot --headless --check-only --script res://src/detectors/arc_detector.gd

# 1) 预热导入缓存（首次 clone / CI 必须；否则 headless 跑会因 .godot/ 为空而炸）
godot --headless --path . --import

# 2) 单元测试
godot --headless --path . \
  -s addons/gut/gut_cmdln.gd \
  -gdir=res://test -ginclude_subdirs \
  -gexit -gjunit_xml_file=res://.test-results/gut.xml
# 全通过返回 0，有失败返回 1
```

### 真正决定"平移是否成功"的不是框架，是**金标准向量**

230 条桌面检查本质是一份行为规格书。落地方式：

1. 用 Python 侧（现有 `tests/test_detectors.py` 的合成轨迹生成器）导出 `shared/golden_vectors.json`：
   ```json
   [{"skill":"roulette","samples":[[t_us,x,y],...],"expect":{"ok":true,"reason":null}}]
   ```
2. `mobile/test/test_detectors.gd` 是一个**数据驱动的 table test**：遍历向量 → 喂给纯函数检测器 → 断言 `Result`。
3. 边界用例单独再跑一遍"量化扰动"版本（时间戳按 16.7 ms 对齐），用来**提前暴露**移动端时间分辨率导致的判定漂移。

这样 GUT 只是 runner，断言内容来自共享真源，桌面/移动两边永远对齐。【HIGH】

---

## Alternatives Considered

| 推荐 | 备选 | 什么时候才该选备选 |
|------|------|-------------------|
| Godot 4.7.2 | **Godot 4.6.3** | 只有当下游某个必需插件明确不支持 4.7 时。本项目不需要任何第三方运行时插件，所以不成立 |
| Godot 4.7.2 | **Godot 4.8-beta2** | 永远不用（官方：pre-release 不用于生产） |
| GDScript | **C#（.NET 版 Godot）** | 需要大量复用既有 C# 库、或团队只写 C# 时。本项目是从 Python 平移的 3.7k 行逻辑，GDScript 与 Python 语法距离最近，C# 只会增加翻译成本 + 官方标注 Android 导出 experimental + APK 体积翻倍 |
| Compatibility 渲染后端 | **Mobile（Vulkan）** | 需要 3D/高级 2D 特效时。本项目是纯 2D，用 Vulkan 只会把 minSdk 抬到 29 并引入驱动兼容风险 |
| JSON 配置 + 手写校验 | **`.tres` Resource** | 只有"配置要在编辑器里可视化编辑"时才考虑。本项目配置由桌面版共享，不成立 |
| `vibrate_handheld()` 做震动 | **Kotlin v2 插件 + `VibratorManager`** | 见 §震动策略的三条件。发布后仍可作为 v2 功能 |
| GUT | **gdUnit4** | 需要 mock/spy 或场景级输入回放时；或将来引入 C# |

---

## What NOT to Use

| 别用 | 为什么 | 用什么代替 |
|------|--------|-----------|
| **`Input.start_joy_vibration()` 作为安卓震动主路径** | 安卓上恒为静默 no-op（`has_joy_vibration()` 恒 false，平台层无 rumble 出口）。会做出"测试通过但用户没感觉"的假功能 | `Input.vibrate_handheld()`；桌面保留 `start_joy_vibration` |
| **不加 `has_joy_vibration()` 门控就调 rumble** | 在安卓上会写入假的"正在震动"状态，`is_joy_vibrating()` 返回 true，UI 若据此显示"已震动"就是骗人 | 先门控，再调用 |
| **`Input.get_joy_info()`** | 官方：安卓与 Web 上**恒为空字典** | `Input.get_joy_name()` |
| **把 `Input.get_joy_guid()` 当 SDL GUID** | 安卓返回的是"设备名的十六进制串"，不是 `03000000...` 形式的 SDL GUID；拿去查控制器库永远查不到 | 只当稳定 key 用；分支判断靠 `get_joy_name()` |
| **`_process` 里轮询 `Input.get_joy_axis()` 当采样** | 屏幕 60 Hz 会丢掉手柄 120 Hz 的一半样本，轨迹变形；且拿不到到达时刻 | `_input()` + `InputEventJoypadMotion` + `Time.get_ticks_usec()` |
| **依赖 Godot 内置死区做手势判定** | 内置死区（默认 0.5）只作用于 InputMap action / `get_vector`；`get_joy_axis()` 是裸值。两套死区混用会让"起点不对"这类诊断失真 | 在 `Sample` 归一化层自己实现，参数与桌面版一致 |
| **`godot --test`** | 那是引擎自身的单元测试，需要 `tests=yes` 编译的引擎 | GUT / `-s` 脚本 |
| **`Line2D` + `antialiased = true` 画长轨迹** | 官方注记：`Line2D` 抗锯齿时**不参与批处理**，长轨迹会掉帧 | `Control._draw()` 里一次 `draw_polyline(points, color, width, antialiased)`；或 `Line2D` 但关抗锯齿 |
| **`draw_line()` 循环画折线** | 几百次 draw call | `draw_polyline()`（一次）或 `draw_polyline_colors()`（要渐变时） |
| **`OS.get_ticks_msec()` 做时间戳** | 毫秒精度，判定阈值本身就在毫秒级，量化误差直接吃掉容差 | `Time.get_ticks_usec()` |
| **Godot 3.x** | 无 4.x 的 2D/渲染/输入改进；GDScript 2.0 与 4.x API 完全不同；官方仅为存量项目维护 | Godot 4.7.2 |
| **Homebrew 装的 Android SDK** | 官方警告：不在统一位置，Godot 找不到 | Android Studio 或 cmdline-tools 装到 `~/Library/Android/sdk` |
| **Asset Library 里来路不明的 "vibration / rumble" 插件** | 4.x 生态里这类插件多数是 3.x 时代或直接包装 `start_joy_vibration`，在安卓上一样不工作；维护状态不可查 | 自己写 60 行 Kotlin v2 插件（若真需要） |
| **`VirtualJoystick`（4.7 新节点）** | 触屏搓招的肌肉记忆无法迁移到真手柄，PROJECT.md 已明确排除 | 不做 |

---

## Stack Patterns by Variant

**如果只需要侧载 APK 给朋友（本项目当前形态）：**
- 用**官方预编译 APK 模板**导出（不装 Gradle Build Template）
- 只需 JDK 17 + platform-tools + build-tools 36.1.0
- 导出预设：`Gradle Build → Use Gradle Build = false`，`Permissions → Vibrate = true`，`Filters = *.json`
- 好处：CI 快、无 Gradle 下载、无 AGP 版本冲突

**如果将来要上 Google Play（AAB）：**
- 必须开 Gradle build（`Project → Install Android Build Template`）
- 需要 `platforms;android-36`，以及 release keystore（`keytool -genkey`）
- 仍需 `permissions/vibrate` 与 `*.json` 过滤
- 注意 Gradle build 下**以下划线开头的目录不会被打进 APK**（`_foo/bar.png` 丢失，`_bar.png` 正常）

**如果震动必须真·手柄马达：**
- 写 v2 Android 插件（Kotlin）：`GodotPlugin` 子类 + `@UsedByGodot fun vibrateGamepad(deviceId: Int, ms: Int, amplitude: Int)`
- 内部用 `InputManager.getInputDevice(id).vibrator`（API 30+）或 `VibratorManager.getVibrator(vibratorId)`（API 31+）
- 必须开 Gradle build；用 `EditorExportPlugin` 打包 AAR 到 `addons/<name>/`
- **先验证 JavaClassWrapper 路线**（零插件）能否走通，再决定是否值得上插件

**如果时序精度不够（真机实测发现 16.7 ms 量化破坏判定）：**
- 优先级 1：`Input.set_use_accumulated_input(false)`（已默认采用）
- 优先级 2：申请高刷（`JavaClassWrapper` 改 `window.attributes.preferredDisplayModeId`）
- 优先级 3：原生插件读 `MotionEvent.getEventTime()`（纳秒级硬件时间戳），通过 signal 回传 —— 成本最高，最后才做

**如果将来要做 iOS：**
- 把 `PadInput` 的震动后端加一层 `OS.has_feature("ios")` 分支；iOS 走 SDL3，`has_joy_vibration()` 正常
- 其余 GDScript 逻辑零改动（这也是选 Godot 的红利）

---

## Version Compatibility

| A | 兼容于 | 备注 |
|---|--------|------|
| Godot `4.7.2-stable` | Export Templates `4.7.2.stable` | **必须完全一致**（含 `.stable`）。不匹配会在导出时报模板版本错误 |
| Godot `4.7.2` | GUT `9.7.1` | 9.7.0 起适配 4.7 严格的返回值类型检查；用 9.6.x 会在 4.7 上出 double/return 相关报错 |
| Godot `4.7.2` | gdUnit4 `6.2.3` | 6.2.3 修的就是"全新 4.7 编辑器字体报错"；6.1.x 只保证到 4.6 |
| Godot `4.7.2` | JDK `17`（Temurin） | 官方推荐 17；更高版本"支持但不推荐"。Gradle 侧 `JavaVersion.VERSION_17` |
| Godot `4.7.2` | AGP `8.6.1` / Kotlin `2.1.21` / Gradle wrapper（随模板） | 不要手动升级 AGP，模板与引擎版本是绑定的 |
| `compileSdk 36` / `buildTools 36.1.0` | `targetSdk 36` / `minSdk 24` | 全部取自 `4.7.2-stable` 源码。**注意官方文档页仍写 35.0.1 / android-35 / ndk 28.1，已过期** |
| `gl_compatibility` | `minSdk 24` | 换 `mobile`(Vulkan) 会被强制抬到 29 |
| `JSON.parse_string()` | Godot 4.x 全系列 | 4.7 无变化 |
| `Input.set_use_accumulated_input()` | Godot 4.x 全系列 | 4.7 无变化 |
| `Input.vibrate_handheld()` | 实现于 Android / iOS / Web | 其他平台 no-op |
| `JavaClassWrapper` / `AndroidRuntime` | Godot 4.2+（4.7 扩展了"实现 Java 接口"） | Android 编辑器/模板均内置，无需插件 |

---

## 未知与必须真机验证的清单

> 下面每一条都**不能**靠模拟器或单元测试证明。建议在 roadmap 里单独开一个 "device spike" phase，产出一张实测表格再冻结判定容差。

| # | 待验证 | 怎么验 | 不通过怎么办 |
|---|--------|--------|-------------|
| 1 | Xbox Series/One 蓝牙 + DualSense/DualShock 蓝牙在目标机型上被 `Input.get_connected_joypads()` 识别，`get_joy_name()` 返回什么 | 装一个只打印设备名/轴值的调试 APK，`adb logcat` 抓 | 若某些手柄不被识别 → 需要原生插件，或改用 USB/2.4G |
| 2 | **左右摇杆的轴序号是否真的是 2/3**（本项目命门） | 同上，打印 `JOY_AXIS_RIGHT_X/Y` 的原始值，逐个手柄确认 | 若错位 → 加一层"按设备名配置轴映射"的兼容表（这本身是个 feature） |
| 3 | 关掉累积后，`_input()` 的实际到达间隔分布（p50/p95/max） | GDScript 里记录 `Time.get_ticks_usec()` 差值直方图，导出到 `user://` 再拉回来 | 若 p95 > 20 ms → 判定容差整体放宽 ≥ 1 帧，或上原生时间戳 |
| 4 | Android 侧默认刷新率是多少，能否稳定到 90/120 Hz | `DisplayServer.screen_get_refresh_rate()` 打印 + `adb shell dumpsys display` | 60 Hz 就按 60 Hz 设计容差；想更高需申请 `preferredDisplayModeId` |
| 5 | `Input.vibrate_handheld()` 在目标机上的实际手感与最短可感知时长 | 手动 A/B，记录 30/50/80/120 ms 的主观阈值 | 太弱 → 提高到 120–150 ms 或叠加视觉脉冲 |
| 6 | `JavaClassWrapper` 能否调到 `InputDevice.getVibrator()` / `VibratorManager`（含 `int[]` 返回值、重载解析） | 写一个 30 行 GDScript 探针，`Engine.get_singleton("AndroidRuntime")` 起手 | 走不通 → 要么放弃手柄震动，要么写 v2 插件 |
| 7 | 手柄断连/重连后 device id 是否复用、`joy_connection_changed` 是否可靠 | 反复开关手柄电源 20 次，记录信号序列 | 若漏信号 → 加低频兜底轮询（如每 2 s 比一次 `get_connected_joypads()`） |
| 8 | 边充电边玩时的 CPU/发热与掉帧 | Perfetto（4.7 起 Android 模板默认支持） | 降帧率上限 / 减少轨迹重绘面积 |
| 9 | `res://data/skills_config.json` 真的进了 APK | `unzip -l app.apk \| grep skills_config` | 忘了加 `*.json` 过滤（见 §配置） |
| 10 | 侧载安装（未知来源）在朋友机型上的可用性 | 真机装一次 | 需要说明"允许安装未知应用"，或考虑 `adb install` |

### 明确"靠训练数据、未在本次研究中验证"的部分

- **调试 keystore 自动生成**：Godot 首次导出会在 `~/.android/debug.keystore` 生成或复用调试密钥（未在 4.7 文档中明确写出，属训练数据）。**LOW** — 若导出报 keystore 相关错误，直接用 `keytool` 手生成一个并填进导出预设。
- **`JAVA_HOME` 与 Godot 的 JDK 选择关系**：Godot 用的是 Editor Settings 里的 `Java SDK Path`，但 `keytool`/`apksigner` 子进程可能仍受 `JAVA_HOME` 影响。装多个 JDK 的机器上出现过 "apksigner not found"。**MEDIUM** — 建议宿主机只留一个 JDK 17。
- **macOS 上 Apple Silicon 的导出路径**：官方文档未单列，但 SDK/JDK 都是架构无关或原生 arm64；导出模板按 ABI 分。**MEDIUM**。
- **`arm64-v8a` vs `armeabi-v7a`**：本项目侧载给现代手机/平板，建议只勾 `arm64-v8a`（APK 更小）。32 位设备已极少，但**未验证**朋友设备。**MEDIUM**。

---

## Sources

| 来源 | 用途 | 置信度 |
|------|------|--------|
| `/websites/godotengine_en/4.7`（Context7，Godot 官方文档 4.7） | `Input.*`、`FileAccess`、`JSON`、`Line2D`/`CanvasItem`、`Engine`、`DisplayServer`、`OS`、Android 导出、Gradle build、Android plugin v2、JavaClassWrapper、控制器文档 | HIGH |
| https://docs.godotengine.org/en/4.7/about/release_policy.html | 版本支持矩阵、"新 major 才产生 LTS" 的原文 | HIGH |
| https://docs.godotengine.org/en/4.7/tutorials/inputs/controllers_gamepads_joysticks.html | "Android 仍用 custom implementation，未用 SDL"、"SDL-based mobile support planned"、死区语义、省电/焦点设置 | HIGH |
| https://docs.godotengine.org/en/4.7/tutorials/inputs/controller_features.html | "controller features 仅支持 Windows/macOS/iOS/Linux"（排除 Android 的官方依据） | HIGH |
| https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_android.html | JDK 17、SDK 包清单、Editor Settings 两处路径、AAB 需 Gradle、keystore、图标 | HIGH |
| https://docs.godotengine.org/en/4.7/tutorials/export/android_gradle_build.html | Install Android Build Template、`.so` 预编译免 C++ 工具链、下划线目录不入包 | HIGH |
| https://docs.godotengine.org/en/4.7/tutorials/export/exporting_projects.html + `/troubleshooting.html` | `*.json` 非资源文件过滤（"编辑器能跑、导出报错"的根因） | HIGH |
| https://docs.godotengine.org/en/4.7/tutorials/platform/android/android_plugin.html | v2 插件架构、AAR + EditorExportPlugin、`@UsedByGodot`、Gradle 前提 | HIGH |
| https://docs.godotengine.org/en/4.7/tutorials/platform/android/javaclasswrapper_and_androidruntimeplugin.html | `AndroidRuntime.getActivity()/getApplicationContext()` + `JavaClassWrapper.wrap()` 的官方示例（含 vibrator 配方） | HIGH |
| https://docs.godotengine.org/en/4.7/tutorials/editor/command_line_tutorial.html | `--headless` / `--import` / `--check-only` / `--quit-after`；`--test` 是引擎自测 | HIGH |
| **Godot 源码 `4.7-stable` / `4.7.2-stable`**（GitHub tarball，本次实际下载阅读） | `android_input_handler.cpp`、`java_godot_lib_jni.cpp`、`GodotInputHandler.java`、`GodotNativeBridge.kt`、`display_server_android.cpp`、`core/input/input.cpp`、`input_enums.h`、`java/app/config.gradle` | **最高**（一手实现） |
| https://godotengine.org/download/archive/ + GitHub Releases API | 4.7.2-stable(2026-08-18)、4.7.1、4.7、4.6.3、4.8-beta2(2026-10-29) 的实际发布日期 | HIGH |
| https://github.com/bitwes/Gut/releases | GUT 9.7.1(2026-07-10)、9.7.0 明确适配 4.7 | HIGH |
| https://github.com/godot-gdunit-labs/gdUnit4/releases | gdUnit4 6.2.3(2026-11-01)、6.1.0 起支持 4.6、6.2.3 修 4.7 编辑器问题 | HIGH |
| https://gut.readthedocs.io/en/latest/Command-Line.html | `gut_cmdln.gd` 参数、`-gexit`、退出码 0/1 | MEDIUM（文档可能滞后于 9.7.1，命令形式自 GUT 7 至今未变） |
| 训练数据 | 调试 keystore 自动生成、多 JDK 导致 apksigner 找不到、只打 arm64 的取舍 | LOW / MEDIUM（已在上一节标注） |

---

*Stack research for: Godot 4 安卓手柄动作训练器*
*Researched: 2026-11-04*
