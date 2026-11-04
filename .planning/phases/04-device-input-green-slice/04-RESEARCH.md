# Phase 4 Research: 设备输入层 + 绿色搓射竖切

**Researched:** 2026-11-05
**Domain:** Godot 4.7.2 Android 手柄输入 / 纯 GDScript 检测器移植 / 首次真机判定
**Confidence:** 检测器与引擎语义 **HIGH**；Godot 输入管线机制 **HIGH（源码级）**；真机时序与设备身份 **LOW（无设备，全部转为测量项）**

---

## Executive Summary

按「计划者最需要先知道什么」排序：

1. **INPUT-05 与 Phase 2 的「`_input` 收不到 `InputEventJoypadButton`」并不冲突，但那条记录目前没有仓库内的证据支撑。** `mobile/src/smoke/smoke_screen.gd` 全文没有重写 `_input()`（只重写了 `_process`/`_ready`），Phase 2 的 91 条 logcat 全部来自轮询循环 —— 它证明的是「轮询有效」，不是「事件无效」。而 Godot 4.7 源码里 `AndroidInputHandler::process_joy_event` 直接调用 `Input::joy_button`，`Input::_parse_input_event_impl` 末尾无条件调用 `event_dispatch_function`，安卓又在 `display_server_android.cpp:839` 安装了这个派发函数 —— 按源码推断按钮事件**应该**到得了 `_input`。因此本阶段把它当 **`[ASSUMED]` 反例**处理：适配器必须两条通道都实现，且天然幂等，不需要先知道真相就能正确工作；真机只负责**记录**哪条通道在供数。
2. **`Input.set_use_accumulated_input(false)` 是正确开关；`agile_event_flushing` 的方向是反的。** `input.cpp` 的 if/else 链是 `accumulated ? 累积 : (agile ? 塞缓冲 : 立即派发)`。也就是说：accumulation=false **且** agile=false 才是「事件到达即派发」；把 agile 打开反而把事件推进 `buffered_events`，等到帧边界才 flush。SUMMARY.md 遗留问题 1 里「或上 `agile_event_flushing`」这个备选方案必须**删除**，它会把时间戳重新量化到帧边界。
3. **TapDetector 的移植面可以比想象的小得多。** Python 的 `TapDetector` 只读 `frame.now` 与 `frame.buttons`（`detectors.py:917-918, 950-952, 959`），从不读 `frame.state`。Phase 4 的 `Frame` 只需要两个字段，不需要先把 `PadState` 全套搬过来。
4. **「两次独立判定」不是检测器的性质，是引擎的性质。** `cooldown_ms = 450`、`global_cooldown_ms = 60`、手势锁 150 ms、单槽 `_pending`、`GROUP_SIZE = 10` 全在 `engine.py` 里。只移植检测器无法解释成功标准 5，黄金向量必须同时覆盖 **detector 层**与 **runtime 层（引擎子集）**。
5. **黄金向量固定在 250 Hz 是刻意的工程选择，不是偷懒。** 250 Hz 下所有时间差都是 4 ms 的整数倍，Python 的 `:.0f` 与 GDScript 的 `%.0f` 不可能在 `.5` 上分叉 —— 于是 `message` 字符串可以**逐字比对**，而不是只比 `code`。这是「0 处差异」真正可机械判定的前提。
6. **轴探测 / 校准 / 设备档案全部可以是纯函数。** `AxisMapping`、`Calibration`、`DeviceProfile` 放 `src/core/`，用合成 raw 轴数组无头证明；只有 `PadSampler`（碰 `Input.`/`Time.`）与 `ProfileStore`（碰 `FileAccess`）在外层。这直接满足 INFRA-03 与 RESIL-03。
7. **字体闸门有一个闭世界缺口，且它正好会被本阶段踩中。** `tools/make_font_subset.py:38-44` 的 `CHAR_SOURCES` 是**硬编码元组**，只含 `skills_config.json`、两个桌面 py 文件、`src/smoke/*`。新增的引导屏 / 练习屏中文**不会**自动进子集 —— 字形闸门照旧 `GLYPH_OK`，真机却是豆腐。本阶段必须把新 UI 文件登记进去，并补一条「`src/ui/` 下每个 `.gd` 都必须在清单里」的机械断言。
8. **真机是退出条件，且现在没有设备。** `adb devices` 为空。5 条成功标准里 1 条可完全无头证明，其余 4 条必须人 + 手机 + 手柄。研究已把「可无头证明」与「必须人机同测」拆开（见 Validation Architecture），无设备时不得勾选任何一格。

---

## Project Constraints (from AGENTS.md)

从仓库根 `AGENTS.md` 与 `.planning/PROJECT.md` 提取的、本阶段**必须**遵守的硬约束：

| # | 约束 | 对本阶段的含义 |
|---|------|----------------|
| C1 | 安卓优先，iOS 延后 | 只做 Android；不写 iOS 分支 |
| C2 | 必须有外接手柄，不做虚拟摇杆 | 屏幕上不得出现任何触屏搓招控件 |
| C3 | 安卓上 Godot **没有**手柄震动实现；唯一通道是 `vibrate_handheld()`（震手机本体） | 本阶段不接震动；任何文案不得出现「手柄震动」 |
| C4 | 采样 60–125 Hz；阈值按毫秒保留；须 `Input.set_use_accumulated_input(false)` 并实测间隔分布 | 见 `## Input Capture`，本阶段就要落真机直方图 |
| C5 | 真机真手柄验证；模拟器不算 | 成功标准 2/3/4/5 只认真机 |
| C6 | 桌面 230 项检查是回归红线 | `bash tools/check_desktop.sh` 必须保持全绿（本次已跑：230/230） |
| C7 | `shared/skills_config.json` 是唯一真源 | 本阶段**不得**为「只练一个动作」去改配置；选择逻辑放组合根 |
| C8 | 标识符英文 ASCII、注释/文案中文、JSON 键 snake_case | 适用于所有新文件 |
| C9 | 时长一律 `_ms` 后缀、频率 `_hz`、时间戳 `Time.get_ticks_usec()/1000.0` | 检测器入参 `now_ms` |
| C10 | GDScript：一个文件一个 `class_name`、Tab 缩进、无第三方测试框架 | 新套件挂进 `core_runner.gd` 的 `SUITES` |
| C11 | `design/` 是用户未跟踪的工作，不许碰；禁止 `git add -A` | 只写本文件与计划内文件 |

---

## Evidence and Confidence

> 说明：`[VERIFIED: path:lines]` 表示本次已 `Read` 该文件并逐字引用；`[CITED: url]` 表示官方文档或引擎源码（外部一手来源）；`[ASSUMED]` 表示未经本次验证，必须转为测量项。

| # | 结论 | 证据 | 置信度 |
|---|------|------|--------|
| E1 | 绿色搓射 = `taps`、`required_button: "RB"`、`button: "X"`、`400/600/150/120`、`modifier_options: ["RB","RT"]`、`cooldown_ms: 450` | `[VERIFIED: shared/skills_config.json:208-231]`（逐字见下） | HIGH |
| E2 | 全局冷却 `global_cooldown_ms = 60` | `[VERIFIED: shared/skills_config.json:88]` `"global_cooldown_ms": 60,` | HIGH |
| E3 | `TapDetector` 状态字段与默认值：`min_ms=400`、`max_ms=600`、`grace_ms=max(0.0, timeout_grace_ms|150)`、`release_hold_ms=max(0.0, release_hold_ms|120)` | `[VERIFIED: desktop/padskills/detectors.py:867-889]` | HIGH |
| E4 | 第二下判定：`if self.min_ms <= interval_ms <= self.max_ms:` → Hit；`< min` → `too_fast`；`> max` → `too_slow` | `[VERIFIED: desktop/padskills/detectors.py:987-1013]` | HIGH |
| E5 | 没有第二下的超时：`if interval_ms > self.max_ms + self.grace_ms:` → `too_slow` | `[VERIFIED: desktop/padskills/detectors.py:1015-1024]` | HIGH |
| E6 | `reset()` 在 `_t0` 非空时产 `hold_short`，`elapsed = max(0.0, (self._now - self._t0) * 1000.0)` | `[VERIFIED: desktop/padskills/detectors.py:921-935]` | HIGH |
| E7 | `on_idle()` 是 no-op（右摇杆静止与按键动作无关） | `[VERIFIED: desktop/padskills/detectors.py:937-939]` | HIGH |
| E8 | `observe()` 只更新 `_now`/`_prev_pressed`/`_have_prev`，用于防止「一直按着 X」被当成第一下 | `[VERIFIED: desktop/padskills/detectors.py:913-919]` | HIGH |
| E9 | `abandon()` 静默丢弃，不产失败 | `[VERIFIED: desktop/padskills/detectors.py:941-946]` | HIGH |
| E10 | 引擎在修饰键不满足时 `observe(frame)` **然后** `reset()` | `[VERIFIED: desktop/padskills/engine.py:273-279]` | HIGH |
| E11 | 命中后先 `_discard_other_claims`，再依次判逐动作冷却与全局冷却；被冷却吞掉时**静默 `continue`**（不记 Outcome） | `[VERIFIED: desktop/padskills/engine.py:285-293]` | HIGH |
| E12 | 手势锁：命中后 `_gesture_locked = True`，右摇杆 `< RELEASE_STICK(0.35)` 持续 `gesture_release_ms(150)` 才解锁；锁定期间 `return`，**不调用任何 detector、不 drain failure** | `[VERIFIED: desktop/padskills/engine.py:217-233, 309-311]`（`RELEASE_STICK` 在 `:98`） | HIGH |
| E13 | 失败单槽：`_drain_failures` 只取**配置顺序第一个**有 pending 的 skill，其余 pending 被丢弃；失败使 `attempts += 1` | `[VERIFIED: desktop/padskills/engine.py:332-353]` | HIGH |
| E14 | `GROUP_SIZE = 10`；命中才 `group_hits += 1`，满 10 清 0 并 `groups_done += 1` | `[VERIFIED: desktop/padskills/engine.py:93, 296-301]` | HIGH |
| E15 | `_buttons_ok`：无要求键 → True；`button_mode == "any"` → any；否则 all | `[VERIFIED: desktop/padskills/engine.py:387-393]` | HIGH |
| E16 | 死区公式：`m = hypot(x,y)`；`m <= dz or m == 0` → `(0,0)`；否则 `scaled = min(1.0, (m-dz)/(1-dz))`，`x/m*scaled, y/m*scaled`（**不钳制 magnitude**） | `[VERIFIED: desktop/padskills/input_source.py:328-334]` | HIGH |
| E17 | 扳机归一：`rest < -0.05` 时 `(value - rest) / (1 - rest)` 再 clamp 到 0..1；否则直接 clamp | `[VERIFIED: desktop/padskills/input_source.py:539-547]` | HIGH |
| E18 | `AxisLayout.trigger_rest` 默认 `-1.0`（双极），探针判 `rest[lt_axis].mean < -0.4` 才留 `-1.0`，否则 `0.0` | `[VERIFIED: desktop/padskills/input_source.py:132, 288-291]` | HIGH |
| E19 | 角度约定：0°=上、90°=右、顺时针、`[0,360)`；`x==0 and y==0 → 0.0`；`norm_deg(rad_to_deg(atan2(x, -y)))` | `[VERIFIED: mobile/src/core/geometry.gd:38-45]` | HIGH |
| E20 | `Buttons.CANONICAL` 17 个规范名；`SQUARE→X`、`CROSS→A`、`L1→LB`、`R2→RT`（位置语义，不是品牌语义） | `[VERIFIED: mobile/src/core/domain/buttons.gd:17-44]` | HIGH |
| E21 | 配置校验**不检查** `timeout_grace_ms`（全仓无此键），但会拒绝负数 `release_hold_ms` / `min_interval_ms` / `max<=min` | `[VERIFIED: mobile/src/core/config/config_validator.gd:342-352, 410-422]` + `grep` 无 `timeout_grace` | HIGH |
| E22 | `Frame`/`Hit`/`Failure`/`Outcome`/`PadState` 在 `mobile/src/core/` **尚不存在**（只有 15 个 class_name：config 6 + domain 8 + Geometry 1） | `[VERIFIED: mobile/src/core/**（grep "^class_name"）]` | HIGH |
| E23 | 无头 runner 的判据是 `^TESTS_DONE failures=0$` + 拦截 `^TESTS_ASSERTIONS=0$` + 看门狗；当前 8 套件 / 576 断言全绿 | `[VERIFIED: mobile/tools/test-core.sh:134-143]`、`[VERIFIED: mobile/tests/core_runner.gd:69-75]`、本次运行输出 `TESTS_SUITES=8 / TESTS_ASSERTIONS=576 / TESTS_DONE failures=0` | HIGH |
| E24 | 字形来源是硬编码元组，只含 5 个路径 | `[VERIFIED: tools/make_font_subset.py:38-44]` | HIGH |
| E25 | Phase 2 真机：A/B/X/Y = 按钮 `0/1/2/3`；LB/RB = `9/10`；左摇杆轴 `0/1`；右摇杆轴 `2/3`；扳机轴 `4/5` 范围约 `-0.86 ~ +1.00`；右摇杆推右 = `axis 2 = -1.000` | `[VERIFIED: .planning/phases/02-apk/02-UAT.md:37-41]` | HIGH（单台设备） |
| E26 | 「`_input` 收不到 `InputEventJoypadButton`」这条记录**在本仓库没有对应探针**：`smoke_screen.gd` 无 `_input()` 重写 | `[VERIFIED: mobile/src/smoke/smoke_screen.gd:1-98]` + `grep -rn "_input" mobile/` 仅命中注释与 `_parse_input` | **LOW / `[ASSUMED]`** |
| E27 | Godot 安卓按键通路：`AndroidInputHandler::process_joy_event` → `Input::joy_button(...)`；`joy_axis` 同理 | `[CITED: github.com/godotengine/godot 4.7 platform/android/android_input_handler.cpp:39-45]` | HIGH |
| E28 | `Input::joy_button` 在无映射（`joy.mapping == -1`）时直接 `_button_event(...)`，后者 `parse_input_event(ievent)` | `[CITED: core/input/input.cpp:1652-1681, 1826-1834]` | HIGH |
| E29 | `parse_input_event`：`if (use_accumulated_input) { 累积 } else if (agile_input_event_flushing) { 入缓冲 } else { 立即 _parse_input_event_impl }` | `[CITED: core/input/input.cpp:1549-1556]` | HIGH |
| E30 | `_parse_input_event_impl` 末尾 `if (event_dispatch_function) { event_dispatch_function(p_event); }` | `[CITED: core/input/input.cpp:1045-1049]` | HIGH |
| E31 | 安卓安装派发函数：`Input::get_singleton()->set_event_dispatch_function(_dispatch_input_events);` | `[CITED: platform/android/display_server_android.cpp:839]` | HIGH |
| E32 | `agile_event_flushing` 默认 **false** | `[CITED: main/main.cpp:3659]` `GLOBAL_DEF("input_devices/buffering/agile_event_flushing", false);`、`[CITED: docs.godotengine.org/en/4.7/classes/class_projectsettings.html]` 默认值 `false` | HIGH |
| E33 | `use_accumulated_input` 官方语义：开启时「一帧内产生的所有输入事件被合并、在渲染结束时发出」；**默认开启** | `[CITED: docs.godotengine.org/en/4.7/classes/class_input.html#class-input-property-use-accumulated-input]` | HIGH |
| E34 | `get_connected_joypads()` 顺序在重启后**不保证一致** | `[CITED: docs.godotengine.org/en/4.7/classes/class_input.html#class-input-method-get-connected-joypads]` | HIGH |
| E35 | `get_joy_info()` 在 Android/Web **恒为空字典** | `[CITED: docs.godotengine.org/en/4.7/classes/class_input.html#class-input-method-get-joy-info]` | HIGH |
| E36 | `get_joy_guid()` 返回 SDL 兼容 GUID，「找不到时返回空串」；安卓不走 SDL 映射，实际返回值未知 | `[CITED: docs.godotengine.org/en/4.7/classes/class_input.html#class-input-method-get-joy-guid]` + `[ASSUMED]`（安卓实际值） | MEDIUM |
| E37 | 安卓仍用自研控制器实现（非 SDL 3） | `[CITED: docs.godotengine.org/en/4.7/tutorials/inputs/controllers_gamepads_joysticks.html]`「This custom code is still used to support controllers on Android and Web」 | HIGH |
| E38 | `display/window/handheld/orientation` 默认 `0` = `SCREEN_LANDSCAPE`；`display/window/energy_saving/keep_screen_on` 默认 `true` | `[CITED: class_projectsettings.html 属性表]` + `[CITED: class_displayserver.html enum ScreenOrientation]` | HIGH |
| E39 | 手柄名匹配只能靠 `get_joy_name()`；Phase 2 实际设备报告为 `Xbox Series X Controller` | `[VERIFIED: .planning/phases/02-apk/02-UAT.md:37]`、`[CITED: .planning/research/STACK.md:195]` | MEDIUM（DualSense 名未实测） |
| E40 | 生成器范式：`sys.path` 注入 `desktop/`、纯计算、`json.dumps(sort_keys=True, indent=2, ensure_ascii=False)` + 结尾换行、`--check` 逐字节比较且绝不写盘 | `[VERIFIED: tools/gen_geometry_golden.py:30-40, 116-133, 153-181]` | HIGH |
| E41 | 夹具放 `mobile/tests/fixtures/`（该目录有 `.gdignore`，不进 PCK、不参与导入） | `[VERIFIED: mobile/tests/fixtures/.gdignore 存在]`、`[VERIFIED: mobile/docs/CORE.md:123-129]` | HIGH |
| E42 | `config/use_custom_user_dir=true` + `custom_user_dir_name="FifaSkillTrainer"`，故 `user://` 落在该目录 | `[VERIFIED: mobile/project.godot:11-15]` | HIGH |
| E43 | 原子写：temp → `flush()` → `close()` → `DirAccess.rename_absolute`；失败清理 temp；只接受 `user://` | `[VERIFIED: mobile/src/app/config_store.gd:83-103]` | HIGH |

### E1 逐字引用（成功标准 5 的唯一配置输入）

```json
      "name": "绿色搓射 Green Finesse",
      "enabled": true,
      "type": "taps",
      "relative_to_ls": false,
      "required_button": "RB",
      "params": {
        "button": "X",
        "min_interval_ms": 400,
        "max_interval_ms": 600,
        "timeout_grace_ms": 150,
        "release_hold_ms": 120,
        "modifier_options": [
          "RB",
          "RT"
        ]
      },
```

`[VERIFIED: shared/skills_config.json:208-231]`，其后 `"cooldown_ms": 450`（`:230`）。

---

## Input Capture

### 1. 引擎侧的事实链（源码级）

一次安卓手柄按键/轴变化的完整通路：

```
Android UI thread / JNI
  GodotLib.joybutton / joyaxis          (java_godot_lib_jni.cpp:413-434)
    → AndroidInputHandler::process_joy_event          [CITED: platform/android/android_input_handler.cpp:39-45]
        case JOY_EVENT_BUTTON: Input::joy_button(...)
        case JOY_EVENT_AXIS:   Input::joy_axis(...)
    → Input::joy_button                                [CITED: core/input/input.cpp:1652-1681]
        joy.last_buttons[b] == p_pressed → return（同值去重）
        joy.mapping == -1 → _button_event(...)          （安卓：无映射库，走这条）
    → Input::_button_event / _axis_event                [CITED: core/input/input.cpp:1826-1843]
        构造 InputEventJoypadButton / InputEventJoypadMotion
    → Input::parse_input_event                          [CITED: core/input/input.cpp:1549-1556]
        if (use_accumulated_input)            → 累积
        else if (agile_input_event_flushing)  → 入 buffered_events（等帧边界）
        else                                  → _parse_input_event_impl（立即）
    → Input::_parse_input_event_impl                    [CITED: core/input/input.cpp:1045-1049]
        更新 joy_buttons_pressed / joy_axis 状态
        event_dispatch_function(p_event)
    → DisplayServerAndroid::_dispatch_input_events      [CITED: platform/android/display_server_android.cpp:479-480, 839]
    → Window → Viewport::push_input → Node::_input
```

三个直接结论：

- **轮询能工作 ⇒ 事件一定被创建过。** `Input.is_joy_button_pressed()` 读的 `joy_buttons_pressed` 集合只在 `_parse_input_event_impl` 里、由 `InputEventJoypadButton` 填充。Phase 2 的轮询有输出，说明事件对象确实被创建并解析了。
- **安卓确实安装了派发函数**（`display_server_android.cpp:839`），所以事件不是「到 Input 为止」。
- **`joy_axis` 只在「与上一次完全相同」时去重**（`input.cpp:1690`），右→左→右这类反转每一次都会产生独立事件。这正是 INPUT-05 要保的信息；而 `Input.get_joy_axis()` 只保留最后一个值，同帧内反转会丢 —— 轮询确实不够。

### 2. 对 Phase 2 记录的再评估（这一条很重要，别当成已证事实）

`.planning/phases/02-apk/02-VERIFICATION.md:280` 与 `02-UAT.md:41` 都写着：

> Godot 4.7.2 安卓上 `_input` 收不到 `InputEventJoypadButton`，只有轮询 `Input.is_joy_button_pressed` 有效。

**但本仓库里没有任何探针支持这句话。** `mobile/src/smoke/smoke_screen.gd` 的完整方法列表是 `_ready` / `_load_config` / `_log_changes` / `_on_joy_changed` / `_process` / `_refresh_axes` —— 没有 `_input()`。那 91 条 logcat 全部由 `_log_changes()` 里的轮询循环打印（`smoke_screen.gd:51-65`），所以它只能证明轮询有效。

按源码推断，按钮事件**应该**到得了 `_input`。剩下的可能原因只有三类，且都能在真机上一次探针里分辨：

| 可能原因 | 判别方法 |
|---|---|
| 记录来自一次未入库的临时脚本，或结论是「轮询有输出 ⇒ 事件没有」的误推 | 探针同时计数两条通道：`ev_button` 与 `poll_edges`。若 `ev_button > 0` 而 `poll_edges == 0`，旧结论被推翻 |
| 节点不在场景树里 / `set_process_input(false)` / 被上层 Control `set_input_as_handled()` 吃掉 | 探针节点放在根场景、`_input` 里先 `get_viewport().set_input_as_handled()` 都不要调；同时打印 `is_inside_tree()` |
| `_input` 在非主线程被调用，与主线程状态竞争，看起来像「没收到」 | 打印 `OS.get_thread_caller_id()`，与 `_process` 里的值比较 |

**因此本阶段的立场：** 按 `[ASSUMED]` 处理「按钮事件不可用」，但设计成两条通道**都实现**、写同一份状态、天然幂等 —— 这样无论真相是哪一边，代码都正确，真机只负责**记录**哪条通道在供数。

### 3. 推荐设计：事件优先 + 每帧对账（`PadSampler`）

关键洞察：**事件通道与轮询通道写的是同一份状态，所以对账是幂等的。** 事件先到，`_process` 里轮询读到的就是同一个值 → 不产生重复边沿；事件没到，轮询把边沿补上，只是时间戳晚到帧边界。不需要「启动时探测能力再二选一」，也不需要维护两套代码路径。

```gdscript
class_name PadSampler
extends Node

## 手柄采样的唯一入口。放在 src/input/（引擎绑定层），core 只收它产出的值。
##
## 两条通道写同一份状态，因此天然幂等：
##   _input  —— InputEventJoypadMotion / InputEventJoypadButton，到达即打戳
##   _process —— 每帧轮询一次按钮做「对账」，补上事件通道没送来的边沿
## 真机上哪条通道在供数由 events_* / poll_edges 三个计数器记录，不靠猜。

const MAX_BUTTON_INDEX := 21   # JOY_BUTTON_A(0) .. JOY_BUTTON_TOUCHPAD(20)
const MAX_AXIS_INDEX := 8

var _device := -1
var _down: Dictionary = {}          # int(button_index) -> bool
var _axes := PackedFloat32Array()
var _edges: Array = []              # [{t_ms: float, button: int, pressed: bool}]

var events_motion := 0
var events_button := 0
var poll_edges := 0                 # 只由轮询补出来的边沿数


func _input(event: InputEvent) -> void:
	if _device < 0:
		return
	if event is InputEventJoypadMotion:
		if event.device != _device:
			return
		events_motion += 1
		_axes[int(event.axis)] = event.axis_value
		# 轴的消费者是 MotionSample 队列，不由本函数做判定
		_append_motion(Time.get_ticks_usec() / 1000.0, int(event.axis), event.axis_value)
	elif event is InputEventJoypadButton:
		if event.device != _device:
			return
		events_button += 1
		_set_button(Time.get_ticks_usec() / 1000.0, int(event.button_index), event.pressed)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec() / 1000.0
	for index in MAX_BUTTON_INDEX:
		var down := Input.is_joy_button_pressed(_device, index as JoyButton)
		if down != bool(_down.get(index, false)):
			poll_edges += 1
			_set_button(now, index, down)
```

配套约束：

- **只在根场景的 `_input` 里做，不做 `_unhandled_input`。** GUI 的 `Control` 会先吃事件（`_unhandled_input` 在 GUI 之后），而判定输入不能被 UI 吃掉。`_input` 里也**不要**调用 `set_input_as_handled()` —— 那会挡掉别的节点。
- **节点必须在场景树里**（`Node._input` 官方说明：「This method is only called if the node is present in the scene tree」`[CITED: docs.godotengine.org/en/4.7/classes/class_node.html]`）。
- **线程**：`_input` 由 JNI 回调同步派发，是否在主线程未验证。设计上把 `_edges` 的写入/消费做成唯一生产者/唯一消费者；真机若测出跨线程，加一把 `Mutex`（`src/input/` 允许）是**一行**改动，不影响 core。
- **轴的消费**：`MotionSample` 队列按到达顺序逐条送进 core；`snapshot` 只给渲染用。

### 4. 时间戳与量化：如果最后只剩轮询，代价到底多大

设帧周期 `T`。轮询合成边沿时，时间戳比真实边沿**晚** `U(0, T)`；两个边沿相减，误差分布是两均匀分布之差，**均值 0、最坏 ±T**。

| 帧率 | T | 400 ms 下界的实测区间 | 600 ms 上界 | 60 ms 按压 |
|---|---|---|---|---|
| 125 Hz | 8.0 ms | 392.0 – 408.0 | 592.0 – 608.0 | 被至少 7 个采样点覆盖 |
| 90 Hz | 11.1 ms | 388.9 – 411.1 | 588.9 – 611.1 | ≥ 5 个采样点 |
| 60 Hz | 16.7 ms | 383.3 – 416.7 | 583.3 – 616.7 | ≥ 3 个采样点 |

**结论（直接回答 orchestrator 的提问）：**

- **60 ms 的按压在 60–125 Hz 的轮询下不会被漏掉。** 只要按压时长 ≥ 帧周期，就必然至少有一个采样点落在按压区间内；60 ms 是 60 Hz 帧周期的 3.6 倍。
- **`release_hold_ms = 120` 在 60 Hz 下是 7.2 帧**，解锁时刻被量化到 120–136.7 ms，无实质影响。
- **真正危险的是 400 / 600 这两个包含端点的边界**：真值恰好 400 ms 时，轮询的估计值有约 50% 概率落在 400 以下 → `too_fast`。这不是检测器的错，是采样通道的量化。
- 因此：**不得为了掩盖量化去放宽阈值**（那会破坏与桌面版的对等）。正确做法是 (a) 事件通道优先，(b) 在 UI 文案上把目标区间写成「400–600，练 450–500 最稳」，(c) 把真实分布作为测量结果记录，交给 Phase 5 的抽稀矩阵一起裁决。

### 5. 多设备、设备身份与「按任意键唤醒」

| 问题 | 事实 | 处理 |
|---|---|---|
| 有哪些设备 | `Input.get_connected_joypads() -> Array[int]` | 每帧读一次（廉价） |
| 顺序稳定吗 | **不保证**，官方明说重启后顺序可能变 | 永不持久化 device index；只在本进程内用 |
| 设备名 | `Input.get_joy_name(device)` | 唯一可用的品牌线索（`get_joy_info()` 在安卓恒空） |
| 设备 GUID | `get_joy_guid(device)`，官方说「找不到时返回空串」 | 当作**不透明字符串**；空则退回名字 |
| 多设备选谁 | —— | 选 `get_connected_joypads()[0]`；>1 时在引导屏显示设备名让用户选（Phase 4 可只写日志，选择 UI 留 Phase 8） |
| 事件属于谁 | `InputEventJoypadButton/Motion.device` | 一律先比 `event.device == _device`，否则丢弃 |
| 断连/重连 | `Input.joy_connection_changed(device, connected)` | 重连后 `_device` 重新选、状态清空、profile 重新过「复用门」 |
| 「按任意键唤醒」 | 蓝牙手柄在收到第一次输入前不出现（`smoke_screen.gd:78` 已标注为 `[ASSUMED]`） | 列表为空时每帧读 `get_connected_joypads()` + 连 `joy_connection_changed`；**不要**尝试「猜一个 device id 去轮询按钮」——设备还不在列表里时轮询必然全 false |
| 不知道按钮索引怎么判「任意键」 | —— | 设备出现后再判；`for i in MAX_BUTTON_INDEX (21)`：`JOY_BUTTON_TOUCHPAD = 20` 是枚举上界，覆盖 A/B/X/Y/肩键/摇杆按下/十字/背键/触摸板 |

### 6. 必须在真机上量出来的六件事（本阶段就要，不等 Phase 5）

| # | 测什么 | 怎么测 | 判据 |
|---|---|---|---|
| M1 | `_input` 是否收到 motion / button 事件 | 探针屏同时显示 `events_motion` / `events_button` / `poll_edges` | 三个数都要能解释：`events_button>0` 说明旧结论被推翻 |
| M2 | `set_use_accumulated_input(false)` 的真实时间戳粒度 | 记录相邻 `InputEventJoypadMotion` 的 `Δt_ms`，算 p50/p95/max | p95 ≤ 20 ms 视为可用；否则记录并按第 4 节处理 |
| M3 | `_input` 所在线程 | 在 `_input` 与 `_process` 各打印 `OS.get_thread_caller_id()` | 相同 → 无需加锁；不同 → 加 `Mutex` |
| M4 | 右摇杆轴序号与符号 | 轴探针屏（见下一节） | 得到 `(index, sign)` 四元组，且上/下、左/右互为反号 |
| M5 | 扳机静止值与行程 | 静止 5 s 记录，再全程扣到底 | 静止值 ∈ {-1.0, 0.0} 之一附近；行程覆盖 ≥ 0.8 |
| M6 | 设备名 / GUID 的真实返回值 | 引导屏显示 `get_joy_name` 与 `get_joy_guid` | 决定 profile key 的可用性 |

这些数字**全部**写进 `mobile/ACCEPTANCE.md` 的新一节（与 Phase 2 的验收表同构），不留口头结论。

---

## Axis Probe and Device Profile

### 1. 探针算法（一次四步，第二步与第四步互为校验）

**前置**：静止基线。用户松手 300 ms，记录每根轴的中位数 `rest[i]`。这一步同时给出扳机静止值。

**四步**：屏幕依次要求「把右摇杆推到最上 / 最右 / 最下 / 最左，按住不动」。

每一步的判定（纯函数，输入是 `Array[PackedFloat32Array]` 的原始采样序列）：

1. 等待位移：存在某轴 `i` 使 `|raw[i] - rest[i]| >= 0.5`，且连续 ≥ 3 个采样满足（去抖）。
2. 取该时刻起 300 ms 的窗口，对每根轴算 `delta[i] = mean(raw[i]) - rest[i]`。
3. 赢家 `w = argmax |delta[i]|`。
4. **歧义拒绝**：若 `|delta[w]| < 0.5` → 拒绝（没推够）；若第二名的 `|delta| > |delta[w]| - 0.25` → 拒绝（两轴同时动，无法判定）。
5. 记录 `(w, sign = delta[w] > 0 ? +1 : -1)`。

**交叉校验（这是「不硬编码、也不轻信」的关键）：**

| 检查 | 失败含义 |
|---|---|
| `up.axis != right.axis` | 上/右落在同一根轴 → 手柄或探针有问题 |
| `down.axis == up.axis` 且 `down.sign == -up.sign` | 上下的轴与符号必须互为反号 |
| `left.axis == right.axis` 且 `left.sign == -right.sign` | 左右的轴与符号必须互为反号 |
| 四步的 `|delta[w]|` 都 ≥ 0.5 | 有一根轴推不到满量程（磨损摇杆）→ 提示但允许继续（校准会覆盖） |

任一条失败：不清空已有结果，直接回到出错的那一步重来，并显示**具体**原因（「上/右落在同一根轴，请只推右摇杆」）。

**派生量：**

```
rs_x.index = right.axis      rs_x.sign = right.sign          # 右为正
rs_y.index = down.axis       rs_y.sign  = down.sign          # 下为正（SDL y-down，与 geometry.gd 一致）
```

注意 `rs_y.sign` 必须由**向下**那一步给出，不能由「向上取反」隐式推导 —— 显式用 down 那一步，才能让「上下反了」这类硬件问题在探针阶段暴露，而不是在检测器里表现成角度差 180°。

**可选（不阻塞本阶段）**：同法探一次左摇杆，供 Phase 5 的 `relative_to_ls` 使用。若用户跳过，profile 里 `ls` 为 `null`，`AxisMapping` 返回「无左摇杆映射」。

### 2. 置信度

每次探针给三个质量指标，写进 profile 并显示在确认页（用户能看出「这次测得准不准」）：

- `samples`：每一步落在窗口内的采样数（≥ 3 才算数，正常应有 10–40）。
- `margin`：`|delta[w]| - max(|delta[others]|)`，越大越干净（建议阈值 0.25）。
- `separation`：`|delta[w]| / |delta[second]|`，理想 ≥ 3。

任一步 `margin < 0.25` 或 `samples < 3` → 该步判「不确定」，要求重做。**不允许「大概齐就过」** —— 映射错了的后果是判定全错而用户毫不知情（PITFALLS C2 的原始症状）。

### 3. 设备身份：key 怎么取，什么时候必须重探

```
key = guid 非空 ? "guid:" + guid.to_lower() : "name:" + name.strip_edges().to_lower()
```

- **永远保存** `device_name` 与 `device_guid` 两个字段（便于诊断与人工核对），但 key 只用上面那一个。
- **永远不保存 device index。** 官方明说顺序不稳定（E34），存了就一定会错。
- **复用门前置校验**：即使 key 命中，也**必须**先跑一次「验证步」（只要求推右摇杆向右，约 2 秒）：
  - 观察到的 `(axis, sign)` 与 profile 完全一致 → 允许复用；
  - 不一致（哪怕只是符号）→ **整体丢弃该 profile，进入完整四步探针**。
- 这样即使两只同名手柄（`guid` 为空时 key 相同），也**绝不会**沿用错误的映射 —— 成功标准 3 的「绝不沿用上一次的映射」由这条门保证，而不是由 key 的唯一性保证。
- 判据写死成一句话，便于测试：**「只有当本次实测的轴/符号与档案逐项相等时，档案才被采用；否则一律重探。」**

### 4. 文件位置与 schema

**路径**：`user://profiles/controllers.json`（`user://` 已被 `config/use_custom_user_dir` 定名，见 E42；Phase 9 覆盖安装依赖它不变）。
**写入**：完全复用 `ConfigStore` 的原子写范式（temp → `flush()` → `close()` → `rename`，失败清理 temp，只接受 `user://`）。

```json
{
  "schema_version": 1,
  "profiles": {
    "guid:03000000…": {
      "key": "guid:03000000…",
      "device_name": "Xbox Series X Controller",
      "device_guid": "03000000…",
      "axes": {
        "rs_x": { "index": 2, "sign": -1 },
        "rs_y": { "index": 3, "sign": -1 },
        "ls_x": { "index": 0, "sign": 1 },
        "ls_y": { "index": 1, "sign": 1 },
        "lt":   { "index": 4, "rest": -1.0 },
        "rt":   { "index": 5, "rest": -1.0 }
      },
      "calibration": {
        "rs": { "center_x": 0.001, "center_y": -0.003, "scale_x": 0.98, "scale_y": 0.97 },
        "ls": { "center_x": -0.002, "center_y": 0.004, "scale_x": 0.99, "scale_y": 0.99 }
      },
      "quality": {
        "up":    { "samples": 31, "margin": 0.72, "separation": 6.1 },
        "right": { "samples": 28, "margin": 0.68, "separation": 5.4 },
        "down":  { "samples": 30, "margin": 0.70, "separation": 5.9 },
        "left":  { "samples": 29, "margin": 0.66, "separation": 5.2 }
      },
      "layout": "xbox",
      "layout_confirmed": true,
      "probed_at_iso": "2026-11-05T10:22:31"
    }
  }
}
```

字段语义：

| 字段 | 为什么存在 |
|---|---|
| `axes.rs_x.sign` | Phase 2 实测「推右得到 `axis 2 = -1.000`」，与桌面 SDL 相反。符号必须逐设备记录，不能全局取反 |
| `axes.lt/rt.rest` | 扳机静止值实测不稳定（首次 `-1.000`、交互后 `0.000`），归一公式依赖它（E17） |
| `calibration.*.scale_*` | 磨损摇杆推不到 1.0；没有满量程，弧线阈值会把硬件问题判成「你转得不够」 |
| `layout_confirmed` | 未确认为 `true` 时**不得**进入练习（成功标准 4） |
| `quality` | 让「测得不准」可见，而不是悄悄存下一份坏映射 |
| `probed_at_iso` | 排障用；不参与任何判定 |

`probed_at_iso` 需要墙钟时间（`Time.get_datetime_string_from_system()`），因此**只能**由 `src/app/profile_store.gd` 填，core 的 `DeviceProfile` 只承载字符串或留空。

---

## Calibration

### 1. 采样与统计

| 阶段 | 要求 | 采样 | 统计量 | 拒绝条件 |
|---|---|---|---|---|
| **中点** | 双手离开摇杆，屏幕显示 3-2-1 后保持 400 ms | ≥ 15 帧（60 Hz） | 每轴 **中位数** `center_x/center_y` | 任一轴峰峰值 > 0.15（用户在动）或 `abs(center) > 0.35`（漂移过大） |
| **满量程** | 依次推到最右 / 最上 / 最下 / 最左，每步按住 400 ms | 每步 ≥ 15 帧 | 每轴 `scale = max(|raw - center|)` 取四个方向的最大值 | 四步里最大位移 < 0.6（推不到）或 `scale < 0.5` |

用**中位数**而不是均值：摇杆在静止时偶发单帧尖峰（蓝牙丢包重传）会把均值拉偏，中位数不受影响。用**峰峰值**而不是标准差做「用户是否在动」的判据：一次缓慢漂移的标准差可能很小，峰峰值一定大。

### 2. 归一化公式（顺序不能换）

```gdscript
# Calibration.normalize(raw, center, scale, sign) -> float
var centered := raw - center
var normalized := clampf(centered / scale, -1.0, 1.0)
return sign * normalized
```

三个顺序上的硬约束：

1. **先减中点，再除量程，最后乘符号。** 先乘符号会把中点也翻过去（`-center`），中点为 0 时看不出问题，中点为 0.02 时会引入 0.04 的系统偏差。
2. **`scale <= 0` 必须被上游拒绝**（探针阶段已保证 ≥ 0.5），core 里不要写「除零兜底」—— 那会把一个坏档案静默变成「摇杆永远居中」。
3. **符号在最后**：`sign = +1` 表示「推右/推下得到正数」，与 `geometry.gd` 的 SDL 约定（x 右正、y 下正，`angle_of` 里 `atan2(x, -y)`）严格一致（E19）。**不要**在别处再翻一次符号。

### 3. 死区：逐字移植，不许换成 `Input.get_vector()`

`[VERIFIED: desktop/padskills/input_source.py:328-334]`：

```python
def _deadzone(x: float, y: float, dz: float) -> Tuple[float, float]:
    """带重新缩放的死区处理：角度不变，可用行程被拉满。"""
    m = math.hypot(x, y)
    if m <= dz or m == 0.0:
        return 0.0, 0.0
    scaled = min(1.0, (m - dz) / (1.0 - dz))
    return x / m * scaled, y / m * scaled
```

GDScript 对应：

```gdscript
static func deadzone(x: float, y: float, dz: float) -> Vector2:
	var m := sqrt(x * x + y * y)
	if m <= dz or m == 0.0:
		return Vector2.ZERO
	var scaled := minf(1.0, (m - dz) / (1.0 - dz))
	return Vector2(x / m * scaled, y / m * scaled)
```

两条必须保留的性质：

- **角度不变**：乘的是标量 `scaled`，方向不动。
- **magnitude 不钳制到 1.0**：斜向推到底时原始 `m` 可达 ~1.41，`scaled` 被钳到 1.0 后返回向量的长度仍是 ~1.41。`Input.get_vector()` 会把结果钳到 1.0 并用圆形死区 —— 同一个物理位置会在不同点越过 `enter_threshold: 0.72`，这是 PITFALLS C8 的原始缺陷。**禁止**用 `Input.get_vector()` / `InputMap` 替代。

### 4. 坏校准的检测（要在屏幕上说出来，不能只是「存了」）

| 现象 | 判据 | 用户看到的文案方向 |
|---|---|---|
| 没松手 | 中点阶段峰峰值 > 0.15 | 「手离开摇杆再试一次」 |
| 摇杆漂移 | `abs(center_x)` 或 `abs(center_y)` > 0.35 | 「摇杆中点偏移较大，可能是磨损；已记录，建议换手柄」 |
| 推不到底 | `scale < 0.5` | 「没推到最外圈，请推到底再保持」 |
| 推过头（不可能） | `scale > 1.0` | 夹到 1.0 并记一条 warning（与 Phase 3 的 clamp 语义一致） |
| 映射与探针矛盾 | 校准阶段位移最大的轴 ≠ 探针记录的轴 | 直接判失败并要求重探，不许静默覆盖 |

### 5. 与 `geometry.gd` 的接缝

调用顺序固定为：`raw → 符号/中点/量程 → deadzone → Geometry.angle_of / Geometry.magnitude`。

`geometry.gd` **一行都不改**（E19）；它签的是「已经归一化、已经带正确符号的 SDL 坐标」这份契约。任何在校准里翻转 y 轴的做法都会让 `angle_of` 的 0°/90° 整体旋转 180°，而首屏的八方向黄金表（`mobile/tests/fixtures/geometry_golden.json`）**抓不到**这种错误 —— 它测的是函数，不是数据流。因此本阶段必须**新增**一条端到端断言：给定一组合成 raw 轴（上/右/下/左各一条）与一份合成 profile，`snapshot_rs()` 产出的角度依次约为 `0 / 90 / 180 / 270`（±1e-6）。这条断言是「探针 + 校准 + 几何」三者的唯一接缝证明。

---

## Layout Suggestion and Confirmation

### 1. 名称匹配（只从 `get_joy_name()` 来）

| 匹配（小写、`contains`） | 建议布局 | 证据 |
|---|---|---|
| `xbox` | Xbox | `[VERIFIED: .planning/phases/02-apk/02-UAT.md:37]` 实测设备名 `Xbox Series X Controller`；`[CITED: .planning/research/STACK.md:195]` 另列出 `Xbox Wireless Controller` |
| `dualsense` / `dualshock` / `wireless controller` / `playstation` / `ps4` / `ps5` | PlayStation | `[CITED: .planning/research/STACK.md:195]`（`DualSense Wireless Controller` / `Wireless Controller`）—— **未在本项目真机实测**，`[ASSUMED]` |
| 其它 / 空串 | 无建议 | 官方明确 `get_joy_info()` 在安卓恒空（E35），拿不到 vendor/product id；**不做**猜测 |

匹配不到时的行为（硬规则）：**不预选任何一项**，确认页把 Xbox / PlayStation 两个选项并列显示，用户必须选一个才能继续。绝不静默落默认值 —— INPUT-04 的原话是「无法自动识别设备时由用户确认，绝不静默猜测」。

### 2. 这个选择在本阶段到底改了什么（先把它说小，再把它做对）

- **不改轴映射**（轴完全由探针决定）。
- **不改按键索引**：Godot 的 `JoyButton` 是**位置**语义（`A=0` 下、`B=1` 右、`X=2` 左、`Y=3` 上），Android 对 PlayStation 手柄同样按位置映射；`Buttons.canonical` 也已经是位置语义（`SQUARE→X`、`CROSS→A`，E20）。`[ASSUMED]`：DualSense 在安卓上的索引与 Xbox 一致 —— 由第 3 条的按键确认机制兜住。
- **改的是屏幕上的字**：绿色搓射要求「按住 RB 连按两下 X」。对 DualSense 用户，正确文案是「按住 R1 连按两下 □」。把 Xbox 的键名显示给 PS 用户，用户会去按错的键，然后得到一串「太快了 / 太慢了」——PITFALLS.md:998 记录的正是这个症状。

因此本阶段的布局选择**功能上低风险、体验上高价值**：它决定文案表，不决定判定。这一点要写进计划，避免有人把它做成一套映射引擎。

### 3. 按键确认页（把「确认」做成机械检查，而不是点一下「我同意」）

推荐流程（三步一屏）：

1. 标题：「检测到 Xbox 布局」/「没认出手柄，请选择布局」。
2. 让用户**按屏幕点名的那颗键**继续，例如 Xbox 显示「按 A 继续」、PlayStation 显示「按 ⨯ 继续」。
3. 收到的 `InputEventJoypadButton.button_index` 必须等于期望索引（A/⨯ = 0）。相等 → 记录 `layout_confirmed = true` 并进入练习；不等 → 显示「按到的是索引 N，说明这把手的键位与标准不同」，提供「仍然使用此布局」与「换一个布局」两个出口，并把实测索引写进 profile（`button_index_ok: false`）。

这一步把「按键确认页」从礼貌性点击变成一次真实的设备自检，成本是一个事件。

### 4. 字形代价（必须提前算进字体子集）

PlayStation 文案需要 `□ △ ○ ⨯`（U+25A1 / U+25B3 / U+25CB / U+00D7）与 `R1 R2 L1 L2`。这些字符**不在**当前 `CHAR_SOURCES` 的任何文件里（E24），必须显式加入 `EXTRA_SYMBOLS` 或写进某个被扫描的源文件，然后重跑 `python3 tools/make_font_subset.py` 并提交三份产物，否则闸门 A 会在 `make_font_subset.py --check` 这一步变红（这是**正确**行为）。

> 注意：`⨯` 若选 U+2A2F（vector cross product）会缺字形；用 U+00D7（multiplication sign）或直接用「叉」字。Phase 2 已经吃过一次「看起来一样但不在清单里」的亏（ASCII 连字符 vs U+2212），这里沿用同一条纪律：**先在清单里，再上屏幕**。

---

## Tap Detector Port and Golden Vectors

### 1. Python 契约（逐字段、逐方法）

**状态字段** `[VERIFIED: desktop/padskills/detectors.py:867-889]`：

| 字段 | Python 行 | 初值 | 语义 |
|---|---|---|---|
| `button` | `:869` | `canonical_button(p.get("button", "X"))` | 要连按的键（规范名） |
| `required` | `:870` | `tuple(skill.required_buttons)` | 全程必须按住的修饰键 |
| `min_ms` / `max_ms` | `:871-872` | `400.0` / `600.0` | **包含端点**的窗口 |
| `grace_ms` | `:880` | `max(0.0, 150.0)` | 没有第二下时的宽限 |
| `release_hold_ms` | `:881` | `max(0.0, 120.0)` | 重新武装所需的松开时长 |
| `_now` | `:883` | `0.0` | 最近一次 `update`/`observe` 的时间 |
| `_t0` | `:884` | `None` | 第一下按下的时刻 |
| `_armed` | `:885` | `True` | `False` = 等真正松开 |
| `_prev_pressed` | `:886` | `False` | 上一采样点的按键状态 |
| `_have_prev` | `:887` | `False` | 首帧守卫 |
| `_release_since` | `:888` | `None` | 开始观察到松开的时刻 |
| `_pending` | `:889` | `None` | 单槽失败 |

**方法契约**：

| 方法 | Python 行 | 行为 |
|---|---|---|
| `update(frame)` | `:949-1026` | 唯一推进判定的入口；返回 `Hit` 或 `None`；失败进 `_pending` |
| `observe(frame)` | `:913-919` | 只更新 `_now` / `_prev_pressed` / `_have_prev`，**不推进判定** |
| `reset()` | `:921-935` | 若 `_t0` 非空 → 产 `hold_short`；清 `_t0`/`_release_since`；`_armed = not _prev_pressed` |
| `on_idle()` | `:937-939` | **no-op**（右摇杆静止与按键动作无关） |
| `abandon()` | `:941-946` | 静默丢弃：清 `_pending` 与进度，**不产失败** |
| `pop_failure()` | `:97-101`（基类） | 取出并清空单槽 |
| `set_modifier(button)` | `:892-903` | 换修饰键；清 `_t0`/`_release_since`/`_pending`；`_armed = not _prev_pressed` |
| `status()` | `:1029-1034` | `"待机"` 或 `"已按第一下 X，等第二下 {n}ms（目标 400~600）"` |

**`update()` 的判定顺序就是语义，顺序不能动** `[VERIFIED: desktop/padskills/detectors.py:949-1026]`：

1. `_now = now`；`pressed = button in buttons`
2. `if not _have_prev: _prev_pressed = pressed; _have_prev = True; return None` ← **首帧永不产 rising**
3. `rising = pressed and not _prev_pressed`
4. `if not mods_ok: _prev_pressed = pressed; return None` ← 防御分支，**不产失败、不清 `_t0`**
5. `if not _armed:` 松开计时 → 到 `release_hold_ms` 就 `_armed = True`；`return None`
6. `if _t0 is None:` 若 `rising` 则记 `_t0 = now`；**无论是否 rising 都** `_prev_pressed = pressed`；`return None`
7. `interval_ms = (now - _t0) * 1000`
8. `if rising:` → 命中 / `too_fast` / `too_slow`，三条路径都 `_clear(armed=False)`
9. `if interval_ms > max_ms + grace_ms:` → `too_slow`，`_clear(armed=False)`

### 2. 移植时最容易写错的 14 件事（每一条都要有对应夹具）

| # | 陷阱 | 正确的写法 |
|---|---|---|
| G1 | 第一帧就判 rising | `_have_prev` 守卫，首帧只记状态 |
| G2 | `observe()` 不更新 `_prev_pressed` | 必须更新，否则「先按住 X 再按 RB」会被当成一次新的按下（`test_detectors.py:802-814` 的用例） |
| G3 | 把 `reset()` 与 `abandon()` 合并 | 前者产 `hold_short`，后者静默；合并会让「换动作」也报失败 |
| G4 | `reset()` 里用「当前时间」算 elapsed | Python 用的是 `_now`（上一帧），core 不读时钟；必须照抄这个**略微过期**的时间 |
| G5 | 给 `on_idle()` 加上清进度 | 必须是 no-op；右摇杆静止时引擎会周期性调用它 |
| G6 | 认为一个 tick 只可能有一条失败 | `_emit` 是**覆盖写**，「最后写的赢」；同一个 tick 只能通过 `_drain` 取一条 |
| G7 | 漏掉某条终结路径的 `_clear(armed=False)` | 命中 / `too_fast` / `too_slow(第二下)` / `too_slow(超时)` 四条都要 |
| G8 | 超时判成 `>=` | Python 是 `> max + grace`（严格大于）：正好 750 ms 不报，754 ms 报 |
| G9 | 窗口判成开区间 | `min <= interval <= max`，两端都包含 |
| G10 | `mods_ok` 为假时顺手清 `_t0` | Python 不清；清 `_t0` 的是引擎调用的 `reset()`，两处不能混 |
| G11 | `set_modifier()` 只改 `required` | 还要清 `_t0`/`_release_since`/`_pending` 并按 `_prev_pressed` 重算 `_armed` |
| G12 | 直接拿 `%.0f` 当 Python `:.0f` | 250 Hz 下所有时间差都是 4 ms 的整数倍，不会出现 `.5`，可以逐字比对；但仍要在生成器里断言所有 `elapsed_ms` 都是整数 |
| G13 | 相信配置里的 `timeout_grace_ms` 已被校验 | 校验器**没有**这条规则（E21）；必须 `max(0.0, …)` |
| G14 | 在 `reset()` 里把 `_prev_pressed` 置 false | 它只读不写；`_armed = not _prev_pressed` 依赖真实值 |

### 3. `Frame` 最小化（有证据的范围收缩）

Python 的 `TapDetector` 只读 `frame.now` 与 `frame.buttons`（`detectors.py:917-918, 950-952, 959`），**从不读 `frame.state`**。因此 Phase 4 的 `Frame` 只需要两个字段：

```gdscript
class_name Frame
extends RefCounted

## 检测器输入的最小单位。Phase 4 只服务 tap 检测器，它只读 now 与 buttons；
## 左/右摇杆与 facing 在 Phase 5 移植 arc / sequence 时再加，不要提前造。
var now: float = 0.0            # 秒；时间轴由调用方注入（core 不读时钟）
var buttons: Dictionary = {}    # canonical_name -> true；用字典而不是数组，查询 O(1)
```

> 为什么不是 `Array[String]`：`update()` 每帧都要做一次 `button in buttons`，字典是 O(1)；而且 Python 侧是 `frozenset`，语义最接近。若坚持用数组，必须保证有序且去重，否则 `in` 变成 O(n)。两者都可以，但**全仓只能有一种**，并写进 `CORE.md`。

**这带来一个正面后果**：Phase 4 不需要 `PadState`，也就不会为了「顺手」把整个输入快照搬进 core —— 这正是「先做一条竖切」的本意。

### 4. 引擎子集 `TapRuntime`（必须一起移植，否则成功标准 5 无法解释）

| 规则 | Python 位置 | 移植要求 |
|---|---|---|
| `_buttons_ok`（all / any） | `engine.py:387-393` | 两种模式都要；绿色搓射是 `all` 且只有一个键 |
| 修饰键不满足 → `observe` **然后** `reset` | `engine.py:273-279` | 顺序不能反：先 observe 才能让 `reset` 用上本帧的按键状态 |
| `relative_to_ls` 且左摇杆回中 → observe+reset | `engine.py:267-271` | 绿色搓射是 `false`，但同一字段必须实现（Phase 5 要用） |
| 按住别的技能的修饰键 → observe+abandon | `engine.py:257-265` | 单技能场景 `held_required` 只可能含自己的键 |
| 命中 → `_discard_other_claims` → 逐动作冷却 → 全局冷却 | `engine.py:285-293` | **冷却吞掉时静默 `continue`**，不记 Outcome、不报错 |
| 命中后手势锁（RS < 0.35 持续 150 ms） | `engine.py:219-233, 309-311` | tap 场景 `rs_mag ≈ 0`，因此命中后固定锁 150 ms；锁定期间**不调用 detector、不 drain** |
| 失败单槽 drain（只取第一个 owner） | `engine.py:332-353` | 失败使 `attempts += 1` 并计入 `failures[code]` |
| 分组 | `engine.py:93, 296-301` | `GROUP_SIZE = 10`，命中才计数 |
| Outcome 记录 + 单调序号 | `engine.py:355-363` | 见下 |

**一处刻意的移动端改良（必须写进计划并说明理由）**：Python 的 GUI 靠 `outcome_seq` + `last_outcome` 读结果。若同一帧产生两条（当前不可能，但约束靠代码结构而非类型），`last_outcome` 会静默吞掉第一条。移动端改为 **`pop_outcomes() -> Array[Outcome]` 队列**：记录时 push，UI 每帧 drain。判定结果集合与 Python 完全一致，只是「不丢」这件事从约定变成结构。这不是分歧，是表示层更安全。

### 5. 黄金向量生成器（`tools/gen_tap_golden.py`）

**必须镜像 `gen_geometry_golden.py` 的形状**（E40）：

```
python3 tools/gen_tap_golden.py            # 生成 / 刷新
python3 tools/gen_tap_golden.py --check    # 只比对，不写盘；不一致返回 1
```

实现要点：

| 要点 | 做法 | 理由 |
|---|---|---|
| 路径锚定 | `_REPO_ROOT = Path(__file__).resolve().parent.parent`，`sys.path.insert(0, str(_REPO_ROOT / "desktop"))` | 不依赖 cwd（与几何生成器同） |
| 参考实现 | `from padskills.config import parse_config`、`from padskills.detectors import TapDetector`、`from padskills.engine import Engine` | `padskills.*` 不在模块层 import pygame |
| 配置来源 | `json.loads((root / "shared/skills_config.json").read_text(encoding="utf-8"))` → `parse_config(...)` | 用**真源**，不是手写副本；配置一改，夹具必须重生成 |
| 时间轴 | 250 Hz，步长 4 ms，`t_ms` 用 int | 4 ms 整数倍 ⇒ 所有 `elapsed_ms` 是整数 ⇒ `%.0f` 无歧义（E5/G12） |
| 期望值 | 直接跑参考实现，记录每一次 `Hit` 与每一次 `pop_failure()` | 「由 Python 生成」的字面含义 |
| runtime 期望 | 用 `Engine(cfg, NullSource(), RumbleEngine(None, enabled=False))`，包一层 `_record` 收集**全部** Outcome | 只看 `last_outcome` 会漏掉中间结果 |
| 序列化 | `json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n"` | 逐字节可比（E40） |
| `--check` | 重新推导后与磁盘逐字节比较；缺失或不同都返回 1 | 手改夹具必红 |

**夹具路径**：`mobile/tests/fixtures/tap_golden.json`（该目录有 `.gdignore`，E41）。

**夹具规模与压缩**：全部用例展开成逐帧数组后约 100–140 KB。不建议改成「只存变化点 + 让 GDScript 展开」——那会在被测端引入一段没人验证的展开逻辑，且 `0 处差异` 的可审计性下降。140 KB 的 JSON 无头读取是毫秒级，`config_corpus.json` 已有 17 KB 的先例。

### 6. 夹具 schema

```json
{
  "schema_version": 1,
  "source": {
    "detectors": "desktop/padskills/detectors.py",
    "engine": "desktop/padskills/engine.py",
    "sha256": { "detectors": "…", "engine": "…", "config": "…" }
  },
  "meta": { "hz": 250, "step_ms": 4, "skill": "绿色搓射 Green Finesse" },
  "cases": [
    {
      "id": "det_success_mid_450",
      "kind": "detector",
      "modifier": "RB",
      "button": "X",
      "frames": [[0, ""], [4, "RB"], [100, "RB+X"], [160, "RB"], [550, "RB+X"], [610, "RB"]],
      "expect": {
        "hits": [{ "elapsed_ms": 450.0, "summary": "两下 X 间隔 450ms" }],
        "failures": [],
        "status_after_first_press": "已按第一下 X，等第二下 0ms（目标 400~600）"
      }
    }
  ]
}
```

- `frames` 是**逐帧全量**：每 4 ms 一条，`[t_ms:int, "RB+X"]`，按键按字母序拼（`sorted()`），保证跨语言一致。
- `kind` 只有 `"detector"` 与 `"runtime"` 两种；runtime 的 `expect` 用 `outcomes` + `counters`：

```json
"expect": {
  "outcomes": [
    { "ok": true, "code": "ok", "elapsed_ms": 500.0, "message": "", "detail": "两下 X 间隔 500ms（RB 全程按住）" }
  ],
  "counters": { "hits": 1, "attempts": 1, "group_hits": 1, "groups_done": 0, "suppressed": 0 }
}
```

### 7. 用例清单（下限 14 条，覆盖 orchestrator 点名的全部场景）

| id | kind | 时间轴要点 | 期望 |
|---|---|---|---|
| `det_success_min_400` | detector | 第二下间隔 **正好 400** | 1 Hit，`elapsed 400.0` |
| `det_success_mid_450` | detector | 450 | 1 Hit，450.0 |
| `det_success_max_600` | detector | 正好 600 | 1 Hit，600.0 |
| `det_too_fast_300` | detector | 300 | `too_fast`，300.0 |
| `det_too_slow_second_700` | detector | 第二下在 700 | `too_slow`，700.0 |
| `det_too_slow_no_second` | detector | 只有第一下，尾巴 ≥ 900 | `too_slow`，**752.0**（第一帧满足 `interval > 750`） |
| `det_too_slow_boundary_750` | detector | 尾巴恰好覆盖到 interval = 750 就结束 | 750 时**无**失败（严格大于才报）；把尾巴延长到 752 才出 `too_slow` 且 `elapsed 752.0` |
| `det_hold_short_modifier_released` | detector | 第一下之后 200 ms 撤掉 RB | `hold_short`，`elapsed 200.0` |
| `det_modifier_switch_rb_to_rt` | detector | 第一下按 RB，随后换 RT 再按第二下 | 先 `hold_short`（RB 撤离触发 reset），不产 Hit |
| `det_set_modifier_rt_success` | detector | `set_modifier("RT")` 后全程按 RT，间隔 450 | 1 Hit |
| `det_first_frame_held_x` | detector | X 先按着，再按 RB | **不产**任何判定（`observe` 守卫） |
| `det_release_hold_gate` | detector | 命中后 40 ms 再按；再松开 120 ms 后重新起手 | 第一段只 1 Hit，第二段正常起手 |
| `rt_two_shots_500` | runtime | 两发间隔 500，两发之间留 700 ms 空档 | 2 Outcome（都 `ok`），`hits=2, attempts=2, group_hits=2` |
| `rt_cooldown_swallow` | runtime | 第二发的命中时刻落在上一发命中后 < 450 ms | **只有 1 条 Outcome**（第二发被静默丢弃，`suppressed` 不变）—— 这条用来防后人「顺手修好」它 |

补充断言（每条用例都查）：`cases.size() >= 14`、id 唯一、每个 `kind` 至少 5 条。规模下限的意义与 `test_config_corpus.gd:52-62` 相同：删掉大半语料不能让闸门变绿。

### 8. GDScript 无头回放

两个套件，各读同一份夹具的对应 `kind`（分开是为了失败定位）：

- `mobile/tests/unit/test_tap_detector.gd` → `TAP_GOLDEN_DETECTOR cases=N mismatches=0`
- `mobile/tests/unit/test_tap_runtime.gd` → `TAP_GOLDEN_RUNTIME cases=N mismatches=0`

回放逻辑（两者同构）：

1. `preload("res://tests/fixtures/tap_golden.json")` 不可行（JSON 不是资源），用 `FileAccess.get_file_as_bytes` + `JSON.new().parse()` —— 与 `test_geometry.gd:22-33` 完全一致（**不要**用 `JSON.parse_string`，它失败时向 stderr 打 ERROR 且不给行号）。
2. 对每条用例：按 `frames` 逐帧构造 `Frame{now = t_ms / 1000.0, buttons = parse("RB+X")}`。
3. detector 用例：`detector.update(frame)`；非 null 收进 `hits`；每帧后 `pop_failure()` 收进 `failures`。**注意** `hold_short` 可能来自 `reset()`，所以 `reset` 之后**也要** `pop_failure()`。
4. runtime 用例：`runtime.tick(frame)`，然后 `pop_outcomes()` 累积；最后比对 `counters`。
5. 比对：`elapsed_ms` 用 `eq_float(..., 1e-6, ...)`；`message`/`detail`/`summary` 用**精确字符串相等**（这正是 250 Hz 的价值）；`code` 精确；数组长度精确。
6. 最后 `r.complete()`（缺了会被 runner 记成崩溃）。

**哨兵行必须打印在 `r.complete()` 之前**，且 `mismatches` 只统计「本次实际比较过的差异数」，不统计通过数；`cases` 必须等于夹具条数（防止「零用例、零差异」的真空绿）。

### 9. 闸门接线（只加强，不削弱）

`mobile/tools/test-core.sh` 新增两步，位置有讲究：

| 步 | 位置 | 命令 | 为什么放这里 |
|---|---|---|---|
| 夹具未漂移 | 与 `gen_geometry_golden.py --check` **并列**，在导入之前 | `python3 tools/gen_tap_golden.py --check` | 纯 Python、毫秒级；夹具被手改时，GDScript 只是「与手改后的自己一致」 |
| 哨兵 | 现有 `TESTS_DONE` 判据**之后** | `grep -qE '^TAP_GOLDEN_DETECTOR cases=[1-9][0-9]* mismatches=0$'` 与 runtime 同名 | 与 `PACK_OK` / `GLYPH_OK` / `LINT_OK` 同文化：正向哨兵，不是「没看到失败就算过」 |

Risks of the wiring（计划里要写清）：

- `mobile/tools/test-core-selftest.sh` 的四条反例仍应全绿（新步骤在 Godot 之前，不改变 stub 行为）。建议**追加**第 5 条反例：把夹具挪走 → `gen_tap_golden.py --check` 必须非零 → 闸门必须红。这是「夹具缺失 = 假绿」的唯一机械证明。
- 新增 grep 是**加强**闸门；不得为了让某次运行通过而放宽 `TESTS_DONE` / `TESTS_ASSERTIONS` 的既有判据。

---

## Minimal UI Flow

### 1. 屏幕状态表（一屏一态，全部可由手柄推进，零触摸）

| # | 状态 | 屏幕内容（中文，需进字形清单） | 离开条件 |
|---|---|---|---|
| S0 | `BOOT` | 启动占位 | 配置 ok → S1；失败 → S99 |
| S1 | `NO_DEVICE` | 「打开手柄电源 → 长按配对键 → 在系统蓝牙里选择它 → 按手柄任意键唤醒」三步图文 | `get_connected_joypads()` 非空 → S2 |
| S2 | `DEVICE_READY` | 「已连接：<设备名>」+「按任意键继续」 | 任意按钮边沿 → S3 |
| S3 | `PROBE_INTRO` | 「接下来测四步，只推右摇杆；左摇杆不要动」 | 确认键 → S4 |
| S4 | `PROBE_UP` | 大字「把右摇杆推到最上，按住」+ 实时位移条 | 判定成功 → S5；失败 → S8 |
| S5 | `PROBE_RIGHT` | 同上，「最右」 | → S6 / S8 |
| S6 | `PROBE_DOWN` | 同上，「最下」 | → S7 / S8 |
| S7 | `PROBE_LEFT` | 同上，「最左」；结束时做交叉校验 | 通过 → S9；不通过 → S8 |
| S8 | `PROBE_FAILED` | 具体原因（「上/右落在同一根轴」「没推到 0.6 以上」） | 「重来这一步」→ 对应步 |
| S9 | `CALIBRATE_CENTER` | 「双手离开摇杆」+ 3-2-1 倒计时 | 采样完成 → S10；坏样本 → 重来 |
| S10 | `CALIBRATE_RANGE` | 四方向各一个进度环，「推到最外圈并保持」 | 完成 → S11 |
| S11 | `LAYOUT_CONFIRM` | 「检测到 Xbox 布局」+「按 A 继续」（PS：「按 ⨯ 继续」） | 索引匹配且确认 → S12 |
| S12 | `PRACTICE_IDLE` | 动作名 +「按住 RB，连按两下 X」+「等待第一下」 | 第一下 → S13 |
| S13 | `PRACTICE_ARMED` | 「已按第一下，等第二下：{n} ms / 目标 400–600」 | 判定 → S14 |
| S14 | `RESULT` | 成功/失败 + 原因一行 + 实测间隔 | 下一条 Outcome → S14（覆盖）；Phase 6 才做自动推进 |
| S15 | `DEVICE_LOST` | 「手柄断开，等待重连」 | 重连 → S2（重跑复用门） |
| S99 | `CONFIG_ERROR` | 复用 Phase 3 的 `ConfigResult.to_text()` 错误屏 | 修好重启 |

**S13 的实时读数必须节流**：`Label.text` 赋值会触发文本整形，60 Hz 下是整帧最贵的操作。实时毫秒数 10 Hz 更新足以读清（Phase 7 的 `StatsPanel` 是同一结论）。

### 2. 一次判定只显示一次，第二次独立显示

- `TapRuntime` 记录 Outcome 时 push 进队列并递增 `seq`（见 `## Tap Detector Port and Golden Vectors` §4）。
- 练习屏每帧 `pop_outcomes()` **全量 drain**，逐条进横幅队列；横幅自己维护 `_shown_seq`，只显示比它大的。
- 因为 engine 子集在**每个 tick 最多记一条**（命中路径 `break`、失败路径单槽 drain），且队列不会被覆盖，所以「一次尝试一条判定」由结构保证，而不是靠 UI 去重。
- 第二次快速搓射：`cooldown_ms = 450` / `release_hold_ms = 120` / 手势锁 150 ms 三道闸都远小于 `min_interval_ms = 400`，只要两发之间留出 ≥ 450 ms（发与发之间，不是按键之间），第二条 Outcome 必然独立产生。**这一条要在夹具 `rt_two_shots_500` 与真机清单里各证一次。**

### 3. Godot 4.7.2 的具体设置

| 设置 | 值 | 依据 |
|---|---|---|
| `display/window/handheld/orientation` | `0`（`SCREEN_LANDSCAPE`） | 默认已是 0，显式写出来防漂移（E38） |
| `display/window/energy_saving/keep_screen_on` | `true` | 默认已是 true；FEEDBACK-06 在 Phase 7 收口，这里不做承诺 |
| `display/window/stretch/mode` | `"canvas_items"` + 基准视口 `1280×720` | `[ASSUMED]` 推荐值：让「px」在不同 DPI 上语义稳定；未在本项目实测 |
| `input_devices/buffering/agile_event_flushing` | **保持 false（不要写进 project.godot）** | 打开会把事件推回帧边界（E29/E32） |
| `run/main_scene` | `res://src/ui/main.tscn` | 替换 Phase 2 的 smoke 屏；smoke 屏保留为「输入体检」调试入口，不要删 |

**字号（1 m 支架距离，`[ASSUMED]` 推荐值，需真机确认）**：判定大字 72–96 px、失败原因 40–48 px、正文/提示 28–32 px、实时数字 32 px。判据写死为一句可验收的话：**「坐在 1 m 外，不眯眼能读出失败原因那一行。」** 真机若读不清，调的是字号常量，不是布局结构。

### 4. 引导屏必须回答「为什么」，不只是「做什么」

S1 的三步图与 S3 的一句「左摇杆不要动」是 ONBOARD-01/02 的产品内容，不是装饰：

- 安卓蓝牙手柄**在收到第一次输入前不出现在列表里**（`smoke_screen.gd:78` 已标注 `[ASSUMED]`）—— 这是「连不上」的最大来源，必须在屏幕上说出来。
- S3 的「左摇杆不要动」防止探针把左摇杆的位移当成右摇杆（四步只认右摇杆，但用户不知道）。
- S9 的「双手离开」是校准有效性的前提，不能写成「点击继续」。

**验收判据（成功标准 2）**：一台**从未装过本应用**的手机，用户只看屏幕、不读任何文档，能走完 S1→S12。

---

## Architecture Placement

### 1. 文件表（一个文件一个 `class_name`，Tab 缩进）

| 文件 | 层 | `class_name` | 允许触碰 | 职责 |
|---|---|---|---|---|
| `mobile/src/core/frame.gd` | core | `Frame` | 纯 | `now` + `buttons` |
| `mobile/src/core/hit.gd` | core | `Hit` | 纯 | `elapsed_ms` / `detail` / `summary` |
| `mobile/src/core/failure.gd` | core | `Failure` | 纯 | `code` / `message` / `elapsed_ms` |
| `mobile/src/core/outcome.gd` | core | `Outcome` | 纯 | 一次判定 + `seq` |
| `mobile/src/core/detectors/detector.gd` | core | `Detector` | 纯 | 7 方法基类（`update`/`reset`/`on_idle`/`abandon`/`observe`/`pop_failure`/`status`） |
| `mobile/src/core/detectors/tap_detector.gd` | core | `TapDetector` | 纯 | tap 状态机（逐行移植） |
| `mobile/src/core/tap_runtime.gd` | core | `TapRuntime` | 纯 | 引擎子集（门控 / 冷却 / 手势锁 / 单槽 / 分组 / Outcome 队列） |
| `mobile/src/core/device/axis_mapping.gd` | core | `AxisMapping` | 纯 | 轴序号 + 符号 → `rs_x/rs_y/ls_x/ls_y` |
| `mobile/src/core/device/calibration.gd` | core | `Calibration` | 纯 | 中点/量程归一 + 死区逐字移植 |
| `mobile/src/core/device/device_profile.gd` | core | `DeviceProfile` | 纯 | 档案数据、`from_dict`/`to_dict`、复用门判定 |
| `mobile/src/core/device/probe_evaluator.gd` | core | `ProbeEvaluator` | 纯 | 四步采样 → 映射 + 质量 + 拒绝原因 |
| `mobile/src/input/pad_sampler.gd` | input | `PadSampler` | `Input.` / `Time.` / `OS.` | 事件优先 + 每帧对账 |
| `mobile/src/input/joy_button_map.gd` | input | `JoyButtonMap` | `JoyButton` 常量 | 索引 ↔ 规范名（17 个） |
| `mobile/src/app/profile_store.gd` | app | `ProfileStore` | `FileAccess` / `DirAccess` / `Time` | `user://profiles/controllers.json` 原子读写 |
| `mobile/src/ui/main.tscn` + `main.gd` | ui | （无） | 全部 | 组合根：加载配置、建对象图、切屏 |
| `mobile/src/ui/onboarding_screen.gd` | ui | （无） | —— | S1–S11 |
| `mobile/src/ui/practice_screen.gd` | ui | （无） | —— | S12–S15 |
| `mobile/src/ui/result_banner.gd` | ui | （无） | —— | 一次性展示 + 停留 |
| `mobile/tests/unit/test_tap_detector.gd` | tests | （无） | —— | detector 黄金回放 |
| `mobile/tests/unit/test_tap_runtime.gd` | tests | （无） | —— | runtime 黄金回放 |
| `mobile/tests/unit/test_device_profile.gd` | tests | （无） | —— | 探针/校准/复用门 |
| `mobile/tests/unit/test_pad_sampler.gd` | tests | （无） | —— | 合成事件 → 边沿序列 |
| `mobile/tests/fixtures/tap_golden.json` | fixtures | —— | —— | Python 生成的黄金向量 |
| `tools/gen_tap_golden.py` | tools | —— | —— | 生成器 + `--check` |

### 2. 为什么新开 `src/input/` 而不是塞进 `src/app/`

| 理由 | 说明 |
|---|---|
| 边界语义不同 | `src/app/` 现在只有一件职责：**持久化 I/O**（`ConfigStore`）。输入设备是「读环境 + 有生命周期 + 可能有线程问题」，混在一起会让 `CORE.md` 的「I/O 只允许出现在 config_store.gd」这句话变成假话 |
| 可机械约束 | lint 只扫 `src/core`，所以 `src/input/` 天然可用 `Input.`/`Time.`；而 core 不得反向依赖它 —— 建议把 `outer_layer_dep` 正则从 `(?:platform|ui|app)` 扩成 `(?:platform|ui|app|input)`，并在 `tools/test_lint_core_purity.py` 加一条反例。**规则 id 不变**，`CORE.md` 与 `--list-rules` 的互锁仍然成立 |
| 可单独测 | `PadSampler` 可以在无头 `SceneTree` 脚本里用合成的 `InputEventJoypadMotion` 直接喂，不需要真机；放进 `src/app/` 会和 `FileAccess` 的测试搅在一起 |

### 3. 依赖方向（严格单向）

```
core (纯)  ←── input (引擎绑定)  ←── ui (场景/Control)
   ↑                                    ↑
   └────────── app (I/O) ───────────────┘
```

- **core 不 preload 任何外层**（现有 lint 管一半，扩展后全覆盖）。
- **input 可以 import core 的数据类型**（`Frame`、`DeviceProfile`），不 import `ui`。
- **ui 是唯一同时知道三者的地方**（组合根），与 ARCHITECTURE.md 的 L0 一致，**零 autoload**。

### 4. 两个必须当场验证的小风险

1. **`class_name` 冲突**：`Frame` / `Hit` / `Failure` / `Outcome` / `Detector` / `Calibration` / `AxisMapping` / `DeviceProfile` / `ProbeEvaluator` 在 Godot 4.7 的 `@GlobalScope` 里应当都不存在，但**必须在第一个 Wave 就跑一次 `--import` 验证**。撞名时改名为 `DetectFrame` 等，改动只在 core 内，成本一次性。
2. **`InputEventJoypadMotion.axis` 等属性的类型**：是 `JoyAxis` 枚举而非 `int`，GDScript 里 `int(event.axis)` 显式转换；`JoyButton` 同理。写错会在运行期才报，不在解析期。

---

## Validation Architecture

### 1. 测试基础设施

| 属性 | 值 |
|---|---|
| 框架 | 无第三方框架；手写 `SceneTree` runner（`mobile/tests/core_runner.gd`），`Reporter` 内嵌，套件显式 `preload` 注册 |
| 当前基线 | 8 套件 / 576 断言 / `TESTS_DONE failures=0`（本次已跑） |
| 判据 | stdout 哨兵 `^TESTS_DONE failures=0$` + 拦截 `^TESTS_ASSERTIONS=0$` + 180 s 看门狗；**退出码永不单独作判据** |
| 夹具目录 | `mobile/tests/fixtures/`（有 `.gdignore`，不进 PCK、不参与导入） |
| 配置 | 无独立 config 文件；入口就是 `mobile/tools/test-core.sh` |

### 2. 快速 / 完整命令

| 用途 | 命令 | 典型耗时 |
|---|---|---|
| **快速（每次任务提交）** | `bash mobile/tools/test-core.sh` | ~40 s（含一次 `--import`） |
| 纯文本子集（毫秒级，改完即可跑） | `python3 tools/lint_core_purity.py mobile/src/core`<br>`python3 tools/gen_tap_golden.py --check`<br>`python3 tools/gen_geometry_golden.py --check`<br>`python3 tools/sync_config.py --check` | < 1 s |
| **完整（每个 Wave 合并 / 阶段闸门）** | `bash mobile/tools/test-core.sh && bash mobile/tools/gate-a.sh && bash tools/check_desktop.sh` | 3–6 min |
| 闸门自测（改了 `test-core.sh` 之后必跑） | `bash mobile/tools/test-core-selftest.sh` | ~2 min |
| 单套件调试 | `"$HOME/Applications/Godot-4.7.2.app/Contents/MacOS/Godot" --headless --path mobile --script res://tests/core_runner.gd`（在 `SUITES` 里临时只留一个） | ~10 s |

### 3. 需求 → 测试方式矩阵

| Req | 行为 | 自动化 | 手工（真机） | 自动化命令 / 文件 |
|---|---|---|---|---|
| INPUT-01 | Xbox / PlayStation 蓝牙可用 | 部分：探针/映射对任意 `(index, sign)` 都能工作 | ✅ 两只手柄各配一次、各做一次绿色搓射 | `test_device_profile.gd` + 清单 D1/D2 |
| INPUT-02 | 不硬编码轴序号 | ✅ 机械：`mobile/src/` 内 `JOY_AXIS_` 出现次数必须为 0 | 间接（换手柄仍能探出） | `grep -R "JOY_AXIS_" mobile/src` 断言为空 + `test_device_profile.gd` |
| INPUT-03 | 中点 + 满量程校准；单档案；预留 `profile_id` | ✅ `Calibration` 数学 + 坏样本拒绝 + schema 必含 `profile_id` | ✅ 首次校准走完 | `test_device_profile.gd` |
| INPUT-04 | 布局建议 + 按键确认；不静默猜测 | ✅ 名称匹配表 + 「未确认不得进练习」状态断言 | ✅ DualSense 确认一次 | `test_device_profile.gd` + `test_onboarding_flow.gd` |
| INPUT-05 | 事件捕获，不轮询轴 | 部分：合成事件含**同帧反转**（右→左→右三帧内）必须全部保留；`PadSampler` 无头可测 | ✅ M1/M2/M3：`events_motion`、`Δt` 直方图、线程 id | `test_pad_sampler.gd` + 清单 M1–M3 |
| ONBOARD-01 | 配对图文 + 按任意键唤醒 | 部分：状态机 S1→S2 可在无头 `SceneTree` 里推 | ✅ 全新手机首次启动 | `test_onboarding_flow.gd` + 清单 D0 |
| ONBOARD-02 | 校准引导可完成 | 部分：同上学 | ✅ 不看文档走完 | 同上 |

### 4. 只有人 + 手机 + 手柄能证明的部分（照做即可，无需读代码）

> 前置：`bash mobile/tools/gate-b.sh` 需要 `GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD` 已 export；产物在 `mobile/build/fifa-trainer.apk`。
> 记录表沿用 `mobile/ACCEPTANCE.md`，新增「第 6 节 Phase 4 真机记录」。

**D0 全新手机首次启动（成功标准 2）**
1. 卸载旧包：`adb uninstall com.fifaskill.trainer`（确认「首次」是真的首次）。
2. `adb install -r mobile/build/fifa-trainer.apk`，启动。
3. **不读任何文档**，只看屏幕：按 S1 的三步配对；手柄开机后**先按一下任意键**。
4. 判据：设备名出现在 S2；按任意键进入 S3；四步探针各自给出进度与通过；中点 + 满量程校准走完；全程没有需要点击屏幕的地方。
5. 失败记录：卡在哪一屏、屏幕原文、截图。

**D1 轴探测落盘（成功标准 3）**
1. 走完 D0，进入 S11。
2. `adb shell run-as com.fifaskill.trainer cat files/profiles/controllers.json`（或应用内诊断页）确认写入。
3. 判据：`axes.rs_x` / `axes.rs_y` 的 `index` 与 `sign` 与手推方向一致；`ls_*` 若有则同；**没有**任何 device index 字段。

**D2 换手柄必须重探（成功标准 3 的后半）**
1. 断开手柄 A，连上手柄 B（最好是不同品牌）。
2. 判据：应用**不直接进入练习**，而是回到 S2/S3 并重新走探针；`controllers.json` 里出现第二个 key，且 A 的条目未被改写。
3. 反例：把 B 的 `device_name` 手工改成与 A 相同（模拟同型号）后重连 —— 复用门必须因为「实测轴/符号不符」而丢弃并重探。**这一条是「绝不沿用上一次映射」的真正证明。**

**D3 布局建议 + 按键确认（成功标准 4）**
1. Xbox：S11 应显示「检测到 Xbox 布局」；按 A 继续。
2. DualSense：S11 应显示「检测到 PlayStation 布局」；按 ⨯（索引 0）继续。
3. 判据：未按确认键之前，任何搓射都不产生判定（应用停在 S11）；确认后进入 S12。
4. 记录：`get_joy_name()` 的实际字符串（Xbox / DualSense 各一条），写进验收表。

**D4 一次绿色搓射（成功标准 5 前半）**
1. 在 S12 按住 RB，按两下 X，间隔约 450–500 ms。
2. 判据：屏幕**只出现一条**判定；成功时显示成功，失败时显示原因一行（「太快了 / 太慢了 / 保持不够」）与实测毫秒。
3. 反例：间隔 300 ms → `too_fast`；间隔 700 ms → `too_slow`；第一下之后松开 RB → `hold_short`。**三条都要各出一次，且每次只有一条判定。**

**D5 两发独立（成功标准 5 后半）**
1. 连续做两次成功的搓射，两发之间留 ≥ 1 s 空档。
2. 判据：屏幕出现**两条**判定；组进度点前进 2 格（`group_hits` 从 0 → 2）。
3. 附加观察（INPUT-05 的真正证据）：把右摇杆在 ~50 ms 内右→左→右快甩，调试页的 motion 事件计数必须**增加 ≥ 3**，且 `Δt` 直方图的 p95 ≤ 20 ms。这条不能被 tap 判定替代 —— tap 只用按钮，证明不了轴的事件流。

**D6 输入体检（M1–M6 六项测量）**
1. 进入调试屏（smoke 屏升级版），把 `events_motion` / `events_button` / `poll_edges` / `Δt` p50·p95·max / 线程 id / `get_joy_name` / `get_joy_guid` / 各轴 min·max 抄进验收表。
2. 判据：三项计数能解释清楚「谁在供数」；`Δt` p95 ≤ 20 ms；线程 id 相同或已加锁。

### 5. Wave 0 缺口（开工前要补的测试资产）

- [ ] `mobile/tests/fixtures/tap_golden.json` —— 由 `tools/gen_tap_golden.py` 生成（**不许手写**）
- [ ] `mobile/tests/unit/test_tap_detector.gd` / `test_tap_runtime.gd` —— 挂进 `SUITES`
- [ ] `mobile/tests/unit/test_device_profile.gd` / `test_pad_sampler.gd`
- [ ] `tools/gen_tap_golden.py`（含 `--check` 与 `--root`）
- [ ] `mobile/tools/test-core.sh` 的两步新增（夹具 `--check` + 两条 `TAP_GOLDEN_*` 哨兵）
- [ ] `mobile/tools/test-core-selftest.sh` 的第 5 条反例（夹具缺失必须红）
- [ ] 无新框架安装 —— 现有 runner 足够

### 6. 「0 处差异」的机械可查性（三层，缺一层就能造假）

| 层 | 机制 | 造假方式 | 被谁抓住 |
|---|---|---|---|
| 夹具是生成物 | `python3 tools/gen_tap_golden.py --check` 逐字节比较 | 手改 JSON 让测试变绿 | `test-core.sh` 第一步就红 |
| 期望来自参考实现 | 生成器直接 `import padskills` 跑 `TapDetector` / `Engine` | 在生成器里写死期望 | 代码审查 + `source.sha256` 变即代表要重生成 |
| 两端逐条相等 | `TAP_GOLDEN_DETECTOR cases=N mismatches=0` + `TAP_GOLDEN_RUNTIME cases=N mismatches=0` | 删用例、跳过循环 | `cases` 下限断言 + 哨兵 grep（`cases=[1-9]` 不允许 0） |

### 7. 采样率（验证节奏）

| 时机 | 跑什么 |
|---|---|
| 每个任务提交 | `bash mobile/tools/test-core.sh` |
| 每个 Wave 合并 | 快速 + `bash mobile/tools/gate-a.sh` + `bash tools/check_desktop.sh` |
| 改了 `test-core.sh` 之后 | 追加 `bash mobile/tools/test-core-selftest.sh` |
| 阶段闸门 | 完整三件套 + D0–D6 真机清单 + 验收表填满 |

---

## Security Domain

`security_enforcement: true`（`.planning/config.json`），ASVS level 1。本项目无网络、无账号、无服务端，攻击面只有两个：**蓝牙 HID 输入**与**本地 JSON 文件**。

| ASVS 类别 | 适用 | 本阶段的做法 |
|---|---|---|
| V2 身份认证 | 否 | 无账号 |
| V3 会话管理 | 否 | 无会话 |
| V4 访问控制 | 否 | 单用户本地应用 |
| V5 输入校验 | **是** | 配置走 Phase 3 的结构化校验；**新增** profile 文件必须整体校验（schema_version / 键类型 / 数值范围 / 轴序号上限），任何一项不合法 → 整份丢弃并重探，**不做部分恢复**（与 Phase 3 覆盖层同一策略） |
| V6 密码学 | 否 | 无密钥、无签名验证需求；**不引入**任何自研加密 |
| V7 日志 | 是（弱） | 日志不写设备序列号；`probed_at_iso` 只到秒 |

| 威胁 | STRIDE | 缓解 |
|---|---|---|
| 畸形 / 超大 profile JSON 导致崩溃或内存膨胀 | DoS | 先取长度再分配（沿用 `ConfigStore.MAX_BYTES = 1_048_576` 的做法，E43）；解析失败 → 丢弃 + 重探 |
| 手改 profile 把轴映射指向错误轴（「档案投毒」） | Tampering | 复用门（实测轴/符号必须逐项相等）+ `quality` 下限；投毒的最坏结果是「要求重探」，不是「静默判错」 |
| 路径穿越写文件 | Tampering | `ProfileStore` 第一句守卫：目标与临时路径都必须以 `user://` 开头（照抄 `save_overrides()` 的 `ERR_UNAUTHORIZED` 分支） |
| 手柄上报异常轴值（NaN/Inf/超出 ±1） | Tampering | 归一化后 `clampf(-1, 1)`；NaN 用 `is_nan()` 显式拒绝并计一次坏样本，不进入判定 |

---

## Risks and Open Questions

| # | 风险 / 未知 | 影响 | 怎么解决 | 阻塞计划？ |
|---|---|---|---|---|
| R1 | **当前无设备**（`adb devices` 为空） | 成功标准 2/3/4/5 无法闭合；D0–D6 全部无法执行 | 计划把设备波次放在最后并标 `checkpoint:human-verify`；无设备时**不得**勾选任何成功标准 | **不阻塞计划**，阻塞完成 |
| R2 | `_input` 是否收到按钮事件仍是 `[ASSUMED]` | 若收不到，按钮边沿退化为帧边界 | 设计已同时实现两条通道（幂等对账）；M1 只负责记录谁在供数 | 否 |
| R3 | `_input` 可能在非主线程 | 数据竞争 → 随机丢边沿 | M3 打印线程 id；需要时在 `src/input/` 加 `Mutex`（一行） | 否 |
| R4 | 新增 UI 中文没进字体子集 → 真机豆腐而闸门全绿 | 产品级失败 | 把新文件登记进 `CHAR_SOURCES` + 加「`src/ui/**/*.gd` 全部在清单里」的机械断言；重跑 `make_font_subset.py` | 否（有确定解法） |
| R5 | 400/600 边界在 60 Hz 轮询下有 ±16.7 ms 量化 | 边界尝试偶发误判 | UI 文案引导到 450–500；真机记录分布；**不动阈值**（Phase 5 抽稀矩阵统一裁决） | 否 |
| R6 | DualSense 的按钮索引是否与 Xbox 一致 | 若不一致，`X`/`□` 文案与索引对不上 | S11 的按键确认页会实测索引；不符则记录 `button_index_ok: false` 并提示 | 否 |
| R7 | `Frame` 等 `class_name` 撞名 | 解析期报错，Wave 1 就暴露 | 第一个 Wave 先跑 `--import`；撞名改名（成本一次性） | 否 |
| R8 | 冷却静默丢弃命中（`cooldown_ms = 450`） | 用户做完动作却**没有任何判定**，看起来像漏判 | 这是桌面版既有行为，**不修**（修了就破坏对等）；用夹具 `rt_cooldown_swallow` 把它钉成已知行为；UX 层的「冷却可见」归 Phase 6（LOOP-03） | 否 |
| R9 | 手势锁在 tap 场景锁 150 ms（rs_mag≈0） | 命中后 150 ms 内所有 detector 不更新 | 与桌面一致；夹具 `rt_two_shots_500` 已覆盖；写进计划备注防「优化」 | 否 |
| R10 | 安卓上 `get_joy_guid()` 可能是空串或非 SDL 格式 | profile key 退化为名字；两只同名手柄共享 key | 复用门兜底（实测不符即重探）；key 里保留 `name:` 前缀显式区分来源 | 否 |
| R11 | `agile_event_flushing` 被误开 | 事件重新被帧边界量化，M2 指标退化 | 研究结论写进计划：**必须保持 false**；`project.godot` 不写该键 | 否 |
| R12 | `test-core.sh` 新增步骤后自测脚本漂移 | 「闸门自测」变红或漏测 | 每次改闸门都跑 `test-core-selftest.sh`；新增第 5 条反例 | 否 |

**Open question（留给 Phase 5，不阻塞本阶段）**：60 Hz 抽稀下 tap 的 400/600 边界是否需要在「产品阈值」层面做一次性说明（例如把 UI 目标带画成 420–580）。回答它需要 Phase 5 的抽稀矩阵，本阶段只负责把 250 Hz 的对等钉死。

---

## Recommendations for the Planner

### 1. 波次顺序（前四波完全不需要设备；第五波之后才碰真机）

| Wave | 内容 | 依赖 | 结束时必须为真 |
|---|---|---|---|
| **W1** 检测器骨架 | `Frame`/`Hit`/`Failure`/`Outcome`/`Detector` + `TapDetector` + `TapRuntime`，全部在 `src/core/`；跑一次 `--import` 验证 `class_name` 不撞名 | 无 | `bash mobile/tools/test-core.sh` 仍绿（新文件不破坏既有 576 断言） |
| **W2** 对等性证明 | `tools/gen_tap_golden.py` + `tap_golden.json` + `test_tap_detector.gd` / `test_tap_runtime.gd` + `test-core.sh` 两步 + 自测第 5 条反例 | W1 | `TAP_GOLDEN_DETECTOR … mismatches=0`、`TAP_GOLDEN_RUNTIME … mismatches=0`、`gen_tap_golden.py --check` 退出 0；**成功标准 1 在此闭合** |
| **W3** 设备纯逻辑 | `AxisMapping` / `Calibration` / `DeviceProfile` / `ProbeEvaluator` + `test_device_profile.gd` + 「raw → 角度 0/90/180/270」端到端断言 | W1（`Frame` 无关，但同属 core） | 合成 raw 轴能推出正确映射；坏样本/歧义/复用门全部有反例 |
| **W4** 适配器 | `PadSampler` / `JoyButtonMap` / `ProfileStore` + `test_pad_sampler.gd`（合成事件含同帧反转）+ `JOY_AXIS_` 出现次数为 0 的机械断言 + `outer_layer_dep` 扩展 | W3 | 无头可证「事件流保序不丢反转」；profile 原子写与损坏丢弃各一条 |
| **W5** 最小界面 | `main.tscn`/`main.gd` + `onboarding_screen` + `practice_screen` + `result_banner`；`run/main_scene` 切换；`CHAR_SOURCES` 登记 + 重生成字体子集 + 字形闸门 | W2 + W4 | `gate-a.sh` 绿（字形覆盖新文案）；无设备下用 `ReplayerSource` 式的合成源走通 S12→S14 |
| **W6** 真机竖切 | `gate-b.sh` 出 APK → D0–D6 清单 → 填 `mobile/ACCEPTANCE.md` 第 6 节 | W5 + 设备 | 成功标准 2/3/4/5 各有可核对记录 |

### 2. 每个 Wave 的计划边界（避免把「证明」和「实现」写进同一个任务）

- **W1 只写实现，不写生成器。** 检测器必须能在没有黄金向量的情况下被审阅 —— 逐行对照 `detectors.py` 的 diff 就是它的第一层证明。
- **W2 只写证明，不改检测器。** 若黄金向量暴露出 W1 的偏差，改的是 W1 的代码并在 W2 里记录**为什么**（这是「先移植再证明」的顺序价值）。
- **W3 的验收句**：「给定四组合成 raw 采样序列，探针输出 `(index, sign)` 与手推方向一致；给定一份 profile 与一组 raw，`snapshot_rs()` 的角度依次为 0/90/180/270（±1e-6）」。
- **W4 的验收句**：「同一帧内右→左→右三条 motion 事件全部保留且顺序不变；事件通道正常时 `poll_edges == 0`」。
- **W5 的验收句**：「不碰屏幕，仅靠手柄能从 S1 走到 S12；新 UI 的每个汉字都在 `required_glyphs.txt` 里」。
- **W6 是唯一允许出现 `checkpoint:human-verify` 的 Wave**，且它必须**先**产出 APK 再开始清单，不许边改边测。

### 3. 明确不做什么（防范围蔓延）

| 不做 | 理由 |
|---|---|
| 不移植 `ArcDetector` / `SequenceDetector` / `GamepadSource` 全套 | Phase 5 的事；本阶段只需要 tap 一条竖切 |
| 不做 `modifier_options` 的 RB↔RT 切换 UI | `set_modifier()` 会移植并有夹具，但默认 RB 已够用；切换 UI 归 Phase 6/UX |
| 不改 `shared/skills_config.json` | 单一真源；「只练绿色搓射」由组合根筛 `kind == "taps"` 实现 |
| 不做自动推进 / 组进度点 / 音效 / 轨迹绘制 | Phase 6 / 7 |
| 不做断连重连的完整 UX | Phase 8（INPUT-06）；本阶段只做「检测到断连 → 回 S15」的最小行为 |
| 不为了掩盖量化放宽 400/600 | 破坏对等；证据交给 Phase 5 抽稀矩阵 |
| 不接震动 | Phase 10；且安卓上手柄马达不存在 |

### 4. 计划里必须原样带上的三条硬判据

1. **成功标准 1**：`python3 tools/gen_tap_golden.py --check` 退出 0 **且** 两条 `TAP_GOLDEN_* mismatches=0` 哨兵存在 —— 三者缺一不算 0 差异。
2. **成功标准 4**：`layout_confirmed == false` 时，`TapRuntime` 不得产生任何 Outcome（用一条无头断言钉死，不靠 UI 自觉）。
3. **成功标准 2/3/5**：无设备时一律留空，`mobile/ACCEPTANCE.md` 第 6 节填满之前阶段不得宣布完成。

---

## RESEARCH COMPLETE
