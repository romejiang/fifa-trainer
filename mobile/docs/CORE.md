# 纯核心层（`mobile/src/core/`）—— 「零引擎依赖」的可执行定义

`mobile/src/core/` 是整个移动端的地基：配置解析、校验、覆盖层合并、角度与向量工具都在这里。
它必须能在**没有窗口、没有场景树、没有手柄、没有文件系统**的环境下运行并通过测试，
否则 Phase 4–6 的回放对等证明就无从谈起。

这份文档不是 lint 的复述，而是边界本身的说明。`tools/test_lint_core_purity.py` 会机械
断言本文列出的规则 id 与 `tools/lint_core_purity.py --list-rules` 的输出一致 —— 文档与
工具不允许各说各话。

## 1. 这一层是什么

`src/core/**` 的规则只有一句话：

> **不得读取任何环境状态，不得做 I/O，不得持有或构造场景树类型，不得写日志或错误通道。
> 所有输入以参数传入，所有输出以返回值传出。**

拆开看：

- **环境状态**：时钟、输入设备、OS 信息、编辑器状态、项目设置、显示服务器、翻译服务器 ——
  这些值每次都不同，读一次就让「同样的输入得到同样的输出」不再成立。
- **I/O**：真实文件系统的读写归 `src/app/`。core 只接受 `PackedByteArray`，返回结构化结果。
- **场景树**：core 的对象用 `RefCounted` 承载，没有生命周期回调，也不参与节点树。
- **日志 / 错误通道**：core 不允许 `print` / `printerr` / `push_error` / `push_warning`。
  错误必须作为返回值（`ConfigError` / `ConfigResult`）交给上层决定怎么显示。

这样做的收益是具体的：core 可以在无头 CI 里毫秒级跑完；同一个 `Dictionary` 输入永远得到
同一份输出；桌面版 Python 与 GDScript 的差异可以逐条写成测试，而不是靠真机调试发现。

## 2. 允许 / 禁止清单

### 允许

| 类别 | 允许使用 |
|------|----------|
| Variant 类型 | `String`、`StringName`、`Vector2`、`Vector2i`、`Dictionary`、`Array`、`PackedByteArray`、`PackedFloat64Array`、`PackedStringArray`、`int` / `float` / `bool` |
| 纯数学全局函数 | `abs`、`absf`、`min`、`max`、`clamp`、`clampf`、`fmod`、`fposmod`、`atan2`、`sqrt`、`deg_to_rad`、`rad_to_deg`、`wrapf`、`snappedf`、`is_equal_approx`、`PI`、`TAU` |
| 纯类 | `RefCounted`、`Object`、`JSON`、`RegEx`（见第 3 节的例外说明） |
| 依赖方向 | `preload("res://src/core/...")`，以及标准库的纯函数 |

### 禁止（由 lint 机械强制）

| 规则 id | 禁止的形状 | 为什么 |
|---------|------------|--------|
| `input_singleton` | `Input.` | 手柄状态是环境输入，必须由调用方采样后作为参数传入 |
| `time_singleton` | `Time.` | 时钟必须显式传入 `now`，否则回放测试不可能确定 |
| `node_type` | `Node` | 场景树类型；core 用 `RefCounted` 承载数据 |
| `fileaccess_io` | `FileAccess` | 读真实文件系统属于 `src/app/config_store.gd` |
| `logging` | `print(`、`prints(`、`printt(`、`printerr(`、`print_rich(`、`print_debug(`、`push_error(`、`push_warning(` | 日志是副作用；错误必须走返回值（RESIL-02） |
| `os_singleton` | `OS.` | 平台信息是环境状态 |
| `engine_singleton` | `Engine.` | 编辑器 / 引擎状态是环境状态 |
| `display_server` | `DisplayServer` | 平台层职责，属于 `src/platform/` |
| `tree_access` | `get_tree(` | 场景树入口 |
| `scene_tree_type` | `SceneTree` | 场景树类型 |
| `resource_loader` | `ResourceLoader` | 资源系统按路径缓存，等于隐式全局状态 |
| `resource_type` | `Resource` | `Resource` 按路径缓存，`load()` 两次返回同一实例，可变状态会跨测试泄漏；core 的数据对象一律用 `RefCounted` |
| `tool_annotation` | 行首 `@tool` | `--import` 隐含 `--editor`，`@tool` 脚本可能在导入期被执行，产生副作用 |
| `outer_layer_dep` | `preload` / `load` 指向 `res://src/platform|ui|app/` | 依赖方向：`core` 不得反向依赖外层 |

### 规则只管「用」，不管「提」

扫描器先剥掉注释与字符串，再匹配规则。所以在中文文档字符串里解释「为什么不能用
`FileAccess`」、在错误消息里写「不要用 `Input.`」，都不会误报。`InputSource`、
`NodeState`、`NodePath` 这类标识符也不命中：`input_singleton` 要求 `Input` 后面跟点号，
`node_type` 用词边界，且规则大小写敏感（小写 JSON path `input.deadzone` 不命中）。

## 3. 两个例外与一个非例外

**例外一：`JSON`。** 配置的 BOM、UTF-8、JSON 语法错误都是 RESIL-02 的一部分，必须能在
纯层里测。`JSON` 是纯解析器：没有 I/O、没有单例、没有环境状态，同一个字符串永远得到
同一份结果。

**例外二：`RegEx`。** 与 `JSON` 同级：纯计算，结果确定。覆盖层合并与配置校验都需要它。

**非例外：`FileAccess`。** 它看起来也「只是读文件」，但它读的是真实文件系统 —— 路径、
权限、外部修改都会让结果不可复现。I/O 只允许出现在 `src/app/config_store.gd`，core 接收
`PackedByteArray` 并返回 `ConfigResult`。同样被拒绝的还有 `DirAccess`。

## 4. 怎么跑、退出码什么意思

唯一入口是核心闸门：

```bash
bash mobile/tools/test-core.sh
```

它按固定顺序跑：配置副本校验 → lint 反例自测 → 真 lint → 几何黄金校验 → 无头导入 →
几何套件。lint 两步都排在所有 Godot 调用之前 —— 纯文本、毫秒级、零依赖，没有理由等
引擎装好才跑。

也可以单独跑扫描器：

```bash
python3 tools/lint_core_purity.py                  # 扫描 mobile/src/core
python3 tools/lint_core_purity.py mobile/src/core   # 显式指定目标
python3 tools/lint_core_purity.py --list-rules      # 逐行打印规则 id
```

退出码是契约，三档不能混：

| 退出码 | 含义 | 输出 |
|--------|------|------|
| `0` | 没有命中 | `LINT_OK files=N`（正向哨兵，`N` 必须大于 0） |
| `1` | 有命中 | 每行 `相对路径:行号: 规则: 片段` |
| `2` | 目标不存在，或目录里没有任何 `.gd` | `LINT_INVALID ...` 到 stderr |

退出码 2 单独存在的原因：路径写错时扫到 0 个文件，如果返回 0 就等于自动通过 ——
「什么都没扫到」必须和「干净」分开。

已知漏报（记录，不追求完美）：用行继续符拆开 token、`ClassDB.instantiate("Node")`、
`call("print")`、`preload` 路径用变量拼接。lint 的目标是挡住无意识引入，不是对抗恶意代码。

## 5. 怎么加套件、怎么加夹具

**加测试套件：**

1. 新文件放 `mobile/tests/unit/test_<主题>.gd`，不加 `class_name`；
2. `run(r)` 的最后一句必须是 `r.complete()` —— runner 靠它识别「套件中途崩了」；
3. 断言用 `r.check(...)` / `r.eq_float(...)`，不要用 `assert`（运行时错误只中止当前函数，
   调用者会继续，assert 失败会让套件静默缺断言）；
4. 在 `mobile/tests/core_runner.gd` 的 `SUITES` 字典里显式 `preload` 注册。

**加夹具：**

- 放 `mobile/tests/fixtures/`（该目录有 `.gdignore`，坏 JSON 不会在 `--import` 时刷 ERROR，
  也不会被打进 PCK）；
- 能由 Python 推导的就写成生成器 + `--check`（参考 `tools/gen_geometry_golden.py`），
  手改即红；
- `tap_golden.json` 是**生成物**：先跑 `python3 tools/gen_tap_golden.py`，再跑
  `bash mobile/tools/test-core.sh`。`test_tap_detector` 与 `test_tap_runtime` 两个套件
  共读同一份夹具，按 `kind`（`detector` / `runtime`）分工 —— 分开只为失败定位，
  期望来源只有一处；
- 手写的夹具必须在测试里有对应断言钉住，不能「放进目录就算数」。

## 6. 数据与判定契约（Phase 4 起）

这一节写的是**已经存在**的类型与字段，不是计划。UI、设备层、测试三方都按这一份读。

### `Frame`

| 字段 | 类型 | 口径 |
|------|------|------|
| `now` | `float` | **秒**。时间轴由调用方注入，core 不读时钟 |
| `buttons` | `Dictionary` | canonical 按钮名 → `true`，例如 `{"RB": true}` |

- **`Frame.buttons` 不要改成 `Array[String]`**：参考实现是 `frozenset`，逐帧
  `button in buttons` 必须是 O(1)；数组还会引入「有序、去重」两个没人验证的前提。
- **`now` 的单位是秒，不要加 `now_ms` 字段**：`elapsed_ms` 由 `(now - t0) * 1000.0`
  现场换算，与 `desktop/padskills/detectors.py` 逐字一致。两套时间单位并存时，
  总有一处会忘记换算。
- 摇杆字段（`rs_mag` / `rs_angle` / `ls_*` / `facing`）Phase 5 才加：`TapDetector`
  不读它们，提前造只会让「core 只承载判定真正需要的数据」这条边界先烂掉。

### 三个判定值对象

| 类型 | 字段 | 谁产生 |
|------|------|--------|
| `Hit` | `elapsed_ms` / `detail` / `summary` | 检测器在识别成功的那一刻构造 |
| `Failure` | `code` / `message` / `elapsed_ms` | 检测器在 `_emit()` 时构造 |
| `Outcome` | `skill_name` / `ok` / `code` / `message` / `elapsed_ms` / `at` / `detail` / `seq` | `TapRuntime` 在记录的瞬间构造 |

- `summary` / `detail` / `message` **由检测器现场产生**：UI 只显示，测试逐字比对，
  任何一方都不得重新拼装 —— 否则「与桌面版一致」会悄悄变成「与作者的理解一致」。
- `Outcome.at` 是引擎时间轴上的秒（与 `Frame.now` 同口径）；`Outcome.detail` 在成功时
  是 `Hit.summary`、失败时为空串（与 `engine.py:303-305` 相同）。
- `Outcome` 自身不读时钟、不校验、不提供 getter：纯数据对象，公开字段直接用。

### `TapRuntime` 的三条契约

1. **`pop_outcomes()` 是 UI 唯一的结果入口，每帧全量 drain。** Python 的引擎用
   `last_outcome` + `outcome_seq`，同一帧两条时第一条会被静默吞掉；移动端改成
   `Array[Outcome]` 队列，`Outcome.seq` 从 1 单调递增。「不丢结果」是结构，不是约定。
2. **`layout_confirmed == false` 时 `tick()` 不产任何 Outcome。** 这是运行时的第一早退，
   位于手势锁判断**之前**：界面另有状态机，但绕过界面时这里仍然零输出。
   `set_layout_confirmed(false)` 还会静默 `abandon()` —— 手柄中途断开不是一次尝试，
   不得产出 `too_slow` / `hold_short`。
3. **`select_taps_skill(config)` 按 `kind == "taps"` 选，绝不按名字或下标。**
   只练绿色搓射是「筛选」的结果；真实配置把绿色搓射排在 `skills` 最后，
   任何按下标取的做法都会读到马赛回旋。

### 本阶段的范围收缩（Phase 5 必须还原）

- **手势锁按「右摇杆恒回中」实现**：命中后固定锁满 `gesture_release_ms`（150 ms），
  锁满时调一次 `on_idle()`。Phase 5 的 `Frame` 有了 `rs_mag` 之后，要还原成
  「右摇杆真正回中才计时，推着就不解锁」。
- **`idle_reset_ms` 计时器未移植**：引擎的 idle 路径只调用 `on_idle()`，而
  `TapDetector.on_idle()` 是空实现，所以对 tap 场景零行为差异。Phase 5 移植
  arc / sequence 时必须补上。
- **`relative_to_ls` 技能被运行时拒绝**：本阶段没有左摇杆基准，构造时置
  `_enabled = false`，`tick()` 永远不判。Phase 5 有 `facing` 之后必须还原。

Phase 5 必须还原这三处，否则「范围收缩」会变成「功能缺失」。
