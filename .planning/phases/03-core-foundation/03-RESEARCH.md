# Phase 3: 纯核心地基 — 几何 / 配置校验 / 无头运行 / 架构 lint - Research

**Researched:** 2026-11-05
**Domain:** Godot 4.7.2-stable / GDScript 2.0 纯核心层（无场景树、无手柄）+ 无头测试运行器 + 跨语言（Python ↔ GDScript）对等性夹具 + 架构边界 lint
**Confidence:** **HIGH 对本机可机械证明的部分**（全部结论都在本机 4.7.2-stable 上实际跑过：`--headless --script`、退出码、`class_name` 与 `--import`、BOM、JSON、`fposmod`/`atan2`、`DirAccess.rename_absolute`、`.gdignore`、lint 原型）；**MEDIUM 对严格性取舍与 Android 侧文件系统行为**（`rename` 的原子覆盖在 macOS 实测通过，Android 只有 POSIX 语义与官方文档，无真机）；**LOW 对 CI 方案**（本阶段未实际搭建 Godot-on-Linux CI）。

---

## Summary

这一阶段的结论可以压成一句话：**「无头 runner 能做，但 Godot 的失败模式会假绿；BOM 会在你最信任的那条 API 上被静默吃掉；角度移植的真正陷阱不是 `atan2`，而是 `%` 和 `signed_delta` 的端点。」** 三件事都必须用机械闸门钉死，不能靠纪律。

本机在 4.7.2-stable 上实测出的、会直接改变计划写法的发现：

1. **`--script` 的失败不体现在退出码上。** 脚本解析失败、`class_name` 未解析、依赖脚本编译失败，Godot 都打印 `SCRIPT ERROR` 然后 **退出码 0**。只有 `SceneTree.quit(code)` 显式传值才可靠（`quit(7)` → 7）。所以"一条 headless 命令返回退出码"必须再加一条 **完成哨兵**（`TESTS_DONE failures=0`），只判 `$?` 会假绿。
2. **GDScript 的运行时错误只中止当前函数，调用者继续。** 一个 `-> int` 的套件函数崩掉时，调用者拿到的是 **0**，和"零失败"无法区分。runner 必须要求每个套件显式 `complete()`，用"完成标记缺失"识别崩掉的套件。
3. **入口函数里的运行时错误或 `assert()` 失败会让进程挂死。** 因为 `quit()` 永远执行不到；实测 15 秒超时（退出码 124）。外壳脚本必须有看门狗（macOS 默认没有 `timeout`，用 bash 后台看门狗或 Python `subprocess.run(timeout=...)`）。
4. **`FileAccess.get_file_as_string()` 会静默剥掉 UTF-8 BOM。** 同一个文件用 `get_file_as_bytes()` 读得到 `EF BB BF`，用 `get_file_as_string()` 读出来首字符是 `{`、长度少 1。若配置加载器用字符串 API，"BOM 注入 → 结构化错误"这条成功标准会 **永远测不出来**。加载器必须从 `PackedByteArray` 入口。
5. **`class_name` 在 `--import` 之前不可解析。** 干净 clone 直接 `--script` 会报 `Could not find type "X"`，随后级联成运行时错误并挂死。`preload` 单独用可以绕过，但只要核心代码在类型标注里引用另一个全局类名，就必须先 `--import`。Phase 2 的 `--import` 步骤因此是 Phase 3 的硬前置。
6. **GDScript 对两个 float 使用 `%` 是解析错误**（`Invalid operands to operator %, float and float`）。Python 的 `angle % 360.0` 不能直译；必须用 `fposmod`。`fmod(-90, 360) = -90`，`fposmod(-90, 360) = 270`，两者只差一个函数名，错了就是"左"变"右"。
7. **`signed_delta` 的 Python 文档字符串写错了区间。** 实际实现 `((a_to - a_from + 180) % 360) - 180` 在正好 ±180° 时返回 **-180**，即真实区间是 `[-180, 180)`，不是注释里的 `(-180, 180]`。移植时不要"顺手修正"端点，否则 180° 整的轨迹会与桌面版分叉（`angle_diff` 仍是 180，不受影响，但方向判定可能受影响）。
8. **Python 侧的四个坏配置行为已实测**：`"enabled": "false"` 被 `bool("false")` 静默当成 **True** 接受；`min_duration_ms: null` 抛 **TypeError**（不是 `ValueError`，`load_config` 抓不住）；`start_angle: [90, 180]` 在 `parse_config` 阶段 **被接受**，到 `ArcDetector.__init__` 才崩；BOM 被 `json.loads(str)` 拒绝（但 `json.loads(bytes)` 会按 `utf-8-sig` 接受，parity 脚本必须模拟前者）。这四条正是 Phase 3 成功标准 3 要修的东西。

**Primary recommendation:** 用 **`extends SceneTree` + `_initialize()` + `quit(code)`** 的手写 runner（零插件，符合本项目"无 pytest / 自建 check"的文化），外面套一层 **`bash mobile/tools/test-core.sh`**：先跑 Python 架构 lint（可进 CI、不需要 Godot）、再跑 `--import`、再跑 Godot 测试（看门狗 + `TESTS_DONE failures=0` 哨兵）、最后跑 Python 侧的几何黄金生成器 `--check` 与配置对等性脚本。核心层用 `class_name` + 纯 `RefCounted`，**只允许** `JSON` 这一个"引擎类"作为解析器例外（它无 I/O、无环境状态）；文件 I/O 与哈希全部落在 `mobile/src/app/config_store.gd`。

---

## 前置约束（本阶段没有 CONTEXT.md）

`.planning/phases/03-core-foundation/` 下没有 `CONTEXT.md`（Phase 3 未走 discuss）。以下约束来自 `PROJECT.md`、`ROADMAP.md`、`STATE.md`、Phase 1 的 `01-CONTEXT.md` 与仓库 `AGENTS.md`，效力等同锁定决策，研究不得与之冲突：

| 编号 | 约束 | 来源 |
|------|------|------|
| P-01 | **版本锁死 Godot `4.7.2-stable`**；不要用其它版本打开 `mobile/project.godot`（会静默改写工程格式）。测试与 lint 只能调用 `$HOME/Applications/Godot-4.7.2.app/Contents/MacOS/Godot` | `mobile/README.md:5`；Phase 2 P-01 |
| P-02 | `shared/skills_config.json` 是**唯一手写**配置；`mobile/assets/config/` 下是生成物 + `.sha256`，不许手改，也不许另造第二份真源 | Phase 1 D-04；`mobile/README.md:37-44` |
| P-03 | 标识符 / 配置键 / 代码 token 用**英文 ASCII**；docstring、注释、错误消息、用户可见文案用**中文** | `AGENTS.md` §Conventions |
| P-04 | 不引入测试框架（GUT / gdUnit4）。官方文档也明确 GDScript **没有内置单元测试框架**；本项目既有文化是手写 `check()` | `research/SUMMARY.md` D3；`[CITED: docs.godotengine.org/en/4.7/tutorials/ui/creating_applications.html]` |
| P-05 | **零 autoload**。组合根是 `Main._ready()`，依赖显式传入；core 不得通过全局单例拿任何东西 | `research/ARCHITECTURE.md` §Class vs Node vs Autoload |
| P-06 | **`src/core/` 里零 `Input` / `Time` / `Node` / `FileAccess` / `print`**，用 lint 强制；INFRA-03 是硬性需求，不是建议 | `REQUIREMENTS.md` INFRA-03；`research/ARCHITECTURE.md` §Testability |
| P-07 | 时间一律由参数 `t_ms` 传入；core 内不许读时钟。`delta` 与墙钟不得进判定路径 | `STATE.md` Decisions；`research/SUMMARY.md` |
| P-08 | 真机是 Phase 4/5 的退出条件；**Phase 3 不需要真机**，全部断言必须能在无设备机器上跑完 | `ROADMAP.md` 排序理由；Phase 2 P-06 |
| P-09 | 新增 `.gd` 文件会产生 `*.gd.uid` 边车，属于提交物；不要加进 `.gitignore`。提交前跑一次 `--import` 让边车生成 | `mobile/README.md:20`；`STATE.md` Phase 2 决策 |
| P-10 | 仓库级 Python 工具用系统 `python3`（本机 3.9.6）即可，不新增第三方依赖；`uv` 只属于 `desktop/` | `tools/sync_config.py` / `check_desktop.sh` 现状 |

---

<phase_requirements>
## Phase Requirements

| ID | Description（逐字取自 REQUIREMENTS.md） | Research Support |
|----|-------------|------------------|
| RESIL-02 | 配置校验失败显示错误屏并给出可操作信息，而非 `push_error` 或静默降级 | §Q4（`ConfigResult` + `Array[ConfigError]` + `json_path`/`code`/`message`/`fix_hint`）；§Code Examples 的 `ConfigError`/`ConfigResult`；§Pitfalls P4/P5；lint 规则禁止 core 内 `push_error`/`printerr`/`print` |
| RESIL-03 | 核心代码可在无场景树、无手柄的环境下无头运行，由回放源驱动 | §Q1（headless runner 的三种形态与退出码实测）；§Q2（零引擎依赖的可执行定义与 lint）；§Validation Architecture（`test-core.sh` 一条命令） |
| INFRA-03 | `mobile/src/core/` 架构 lint：禁止出现 `Input.` / `Time.` / `Node` / `FileAccess` / `print(` | §Q2（Python 文本扫描器 + 注释/字符串剥离；原型实测 clean=0 / dirty=6）；§Code Examples 的 lint 规则表；§Validation Architecture 的 canary 自测 |
| DATA-03 | 用户数据写入 `user://` 的稀疏覆盖层，绝不尝试修改 `res://` 内配置 | §Q5（`user://` 路径语义、bytes 读、temp+rename 原子写、首启无文件、base hash 变化丢弃）；§Code Examples 的 `OverlayMerge` / `ConfigStore` 契约；§Validation Architecture 的 overlay 测试矩阵 |

**映射到 ROADMAP Phase 3 成功标准（逐字）：**

| # | 成功标准 | 本研究中被证明/被钉死的部分 | 仍需实现 |
|---|----------|------------------------------|----------|
| 1 | 一条 headless 命令即可跑完几何与配置测试并返回退出码，不需要窗口、场景树或手柄 | `SceneTree` + `quit(n)` 退出码实测（0/1/7）；无场景树、无手柄可跑；`--path mobile` 下 `res://`/`user://` 正常 | `mobile/tools/test-core.sh` + `tests/run_tests.gd` |
| 2 | 八方向 + 中心的黄金表与 Python 版逐项一致（误差 < 1e-9），0° = 上、顺时针为正；`x == 0 and y == 0` 返回 0 而不是 π | 已在 GDScript 与 Python 双跑：9 个方向全部精确到打印的 17 位；中心/±0.0 守卫；`fposmod`/`atan2(x,-y)` 公式 | `tools/gen_geometry_golden.py` + `test_geometry.gd` |
| 3 | 注入坏配置（BOM / 字符串布尔 / `null` 数值 / `start_angle` 数组）后得到结构化错误列表（`json_path` + `code` + 修复建议），可原样渲染成错误屏；不存在 `push_error` 或静默降级 | Python 侧四种坏输入的实测行为已记录；BOM 必须走 bytes；`JSON.new().parse()` 静默、`parse_string()` 会打 ERROR；类型强转表已实测 | `ConfigLoader` + `ConfigValidator` + 错误码表 + fixture 语料 + （建议）最小错误屏 |
| 4 | `src/core/` 架构 lint 在出现 `Input.` / `Time.` / `Node` / `FileAccess` / `print(` 时非零退出，干净时零退出 | Python 原型：注释/docstring/字符串/三引号/raw string 全部剥离后 0 命中；dirty 样例 6 命中、rc=1 | `tools/lint_core.py` + `tools/test_lint_core.py` + `test-core.sh` 接线 |
| 5 | 用户修改写进 `user://` 稀疏覆盖层；base 配置 hash 变化时覆盖层被丢弃并提示，运行期绝不尝试写 `res://` | `user://` 路径、`DirAccess.rename_absolute` 覆盖已实测；docs 明确 `user://` 保证可写、`res://` 导出后只读 | `OverlayMerge`（纯语义）+ `ConfigStore`（I/O + hash） |

</phase_requirements>

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|--------------|----------------|-----------|
| 角度约定 / 最短弧 / 幅度 | **L2 Core（`src/core/geometry.gd`）** | — | 纯数学，零环境依赖；桌面与移动必须逐位一致 |
| 配置形状 / 校验 / 错误码 | **L2 Core（`src/core/config/**`, `src/core/domain/**`）** | — | 解析与语义校验必须能在无场景树、无文件系统的条件下测 |
| 字节解码（BOM / UTF-8 / JSON 语法） | **L2 Core（`ConfigLoader.parse_bytes`）** | — | BOM 是配置契约的一部分；放在 app 层会导致这条规则不可 headless 测 |
| 文件读取（res:// base） | **L1/App（`src/app/config_store.gd`）** | — | `FileAccess` 是引擎 I/O；core 只接收 bytes |
| 覆盖层写入 / 原子改名 / base hash | **L1/App（`src/app/config_store.gd`）** | L2 `OverlayMerge` 定义合并与丢弃语义 | I/O 在 app；"什么算过期、怎么合并"是纯语义，归 core |
| 错误屏渲染 | **L3 UI（`src/ui/error_screen.gd`）** | L2 `ConfigResult` 提供行数据 | UI 不解释错误，只渲染 `json_path`/`message`/`fix_hint` |
| 架构边界 lint | **仓库工具（`tools/lint_core.py`）** | CI / `test-core.sh` | 这是仓库政策，不是运行时行为；Python 可直接进现有 CI，不必下载 Godot |
| 几何黄金 / 配置对等性 | **仓库工具（`tools/*.py`）** | `mobile/tests/fixtures/` | Python 参考实现是生成器；夹具是跨语言契约 |
| 测试执行 / 退出码 | **L1 测试壳（`mobile/tests/run_tests.gd`）** | `mobile/tools/test-core.sh` | runner 用 `SceneTree` 只为拿 `quit(code)`；core 本身不碰树 |

---

## Q1. Godot 4.7.2 无 GUT 的无头测试：最小、零依赖、可失败

### 三种形态的实测对比

| 形态 | `quit(code)` 退出码 | 能否设非零退出码 | 实测结论 |
|------|---------------------|------------------|----------|
| `extends SceneTree` + `_init()` | ✅ `quit(7)` → 7 | ✅ | 可用。`_init` 里 `res://`、`user://`、`FileAccess`、`get_root()` 都已可用（实测 `get_root()` 非 null） |
| `extends SceneTree` + `_initialize()` | ✅ `quit(7)` → 7 | ✅ | **推荐**。同样可用；是 `MainLoop` 文档化的初始化钩子，涉及场景树时更稳妥 |
| `extends MainLoop` + `_process()` 返回 `true` | ❌ 没有 `quit()` | **不能** | `MainLoop` 没有 `quit()`；`OS.set_exit_code()` 在 4.7.2 **不存在**（实测解析错误：`Static function "set_exit_code()" not found`）。**排除** |
| 非 `SceneTree`/`MainLoop` 的普通脚本 | — | — | **挂死**：只打印引擎 banner，10 秒超时（124）。不是"报错退出"，是"永远等下去" |

> **口径说明（RESIL-03）：** runner 继承 `SceneTree` 只是为了满足 `--script` 的入口要求并拿到 `quit(code)`。它不在 `_process` 里跑循环、不加载主场景、不实例化任何 `Node`（除非错误屏测试显式 `add_child`），`_initialize` 里做完就 `quit()`。**core 本身零场景树、零窗口、零手柄**；"不需要场景树"指的是 core 的依赖，不是"runner 不能是 SceneTree"。如果要更严格，可以再加一个测试：在 `src/core/**` 的 lint 里已经禁止 `Node`/`SceneTree`/`get_tree(`，这就是机械证明。

**推荐 runner 骨架（实测可跑）：**

```gdscript
# mobile/tests/run_tests.gd
extends SceneTree

const Reporter := preload("res://tests/test_reporter.gd")
const SUITES := {
	"geometry": preload("res://tests/unit/test_geometry.gd"),
	"config_loader": preload("res://tests/unit/test_config_loader.gd"),
	"config_validator": preload("res://tests/unit/test_config_validator.gd"),
	"overlay_merge": preload("res://tests/unit/test_overlay_merge.gd"),
	"config_store": preload("res://tests/unit/test_config_store.gd"),
}

func _initialize() -> void:
	var r := Reporter.new()
	for suite_name in SUITES:
		r.begin(suite_name)
		SUITES[suite_name].new().run(r)
		if not r.completed.has(suite_name):
			# 运行时错误只中止套件函数，调用者会继续；这里把"没走完"变成失败
			r.check(false, "套件提前中止（运行时错误 / assert 失败），断言未全部执行")
	for f in r.failures:
		printerr("TESTS_FAIL " + f)
	print("TESTS_ASSERTIONS=%d" % r.assertions)
	print("TESTS_DONE failures=%d" % r.failures.size())
	quit(0 if r.failures.is_empty() else 1)
```

> `printerr`/`print` 在 `tests/` 里是允许的；lint 只扫 `src/core/`。

### `quit(code)` 是否传播为进程退出码

**是。** 实测 `quit(0)→0`、`quit(1)→1`、`quit(7)→7`。官方文档：`SceneTree.quit(exit_code)` "Quits the application at the end of the current iteration, with the given `exit_code`… For portability reasons, it should be between `0` and `125`（inclusive）" `[CITED: docs.godotengine.org/en/4.7/classes/class_scenetree.html]`。所以失败码用 `1`，不要用 128+。

### `--headless --script` 是否仍然需要 `project.godot`

**不需要，但强烈建议永远带 `--path mobile`。** 实测在无 `project.godot` 的目录里 `--headless --script` 照样跑，`res://` 变成 **当前工作目录**，`user://` 变成 `.../app_userdata/[unnamed project]`（所有无工程脚本共享同一个用户目录）。`--path` 指向无 `project.godot` 的目录也一样。结论：runner/测试/lint 一律 `--path "$repo_root/mobile"`，否则 `user://` 测试会污染一个共享的 `[unnamed project]`。

### 能否在 `--import` 之前跑

**能跑，但只要碰到 `class_name` 就废。** 实测：

- 新工程（无 `.godot/`）里，`run_preload.gd` 只用 `preload("res://core/lab_foo.gd")` 调用静态方法 → **成功**。
- 同一个新工程里，`run_class_name.gd` 直接引用 `LabFoo` → `Parse Error: Identifier "LabFoo" not declared in the current scope`，**退出码 0**。
- 更隐蔽：`lab_user.gd` 用 `func make() -> LabFoo:`（preload 了脚本，但类型标注用全局类名）→ `Could not find type "LabFoo"` → runner 编译失败 → `UserScript.new()` 拿到编译失败的 GDScript → 运行时错误 → **进程挂死**（15 秒超时）。
- 跑一次 `--import` 后生成 `.godot/global_script_class_cache.cfg`，同一脚本立刻成功（`FOO=42`）。

**结论：** core 会用 `class_name`（类型标注需要），所以 `test-core.sh` 的固定第一步是 `--import`；干净 clone 上这是硬前置。`--import` 官方语义是 "Starts the editor, waits for any resources to be imported, and then quits. Implies `--editor` and `--quit`" `[CITED: docs.godotengine.org/en/4.7/tutorials/editor/command_line_tutorial.html]`。Phase 2 已知字体导入偶发 SIGSEGV（约 1/5），`gate-a.sh:43-69` 的有界重试逻辑必须复用（抽成共享函数或复制同一段，不要无重试）。

### 如何收集多个失败而不是 fail-fast

**用 reporter 累积，不要用 `assert()`。** 实测：`assert(false)` 在编辑器二进制里会打印 `Assertion failed` 并 **中止当前函数**；如果它在入口函数里，`quit()` 不会执行 → 进程挂死。更糟的是，GDScript 没有 try/catch，运行时错误也不可捕获。

Reporter 设计（`mobile/tests/test_reporter.gd`，无 `class_name`，用 `preload`）：

```gdscript
extends RefCounted

var assertions := 0
var failures: Array[String] = []
var completed: Array[String] = []
var _suite := ""

func begin(suite: String) -> void:
	_suite = suite

func check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok:
		failures.append("%s: %s" % [_suite, label])

func eq_float(actual: float, expected: float, tol: float, label: String) -> void:
	check(absf(actual - expected) <= tol,
		"%s（实际 %.17f，期望 %.17f，容差 %s）" % [label, actual, expected, str(tol)])

func complete() -> void:
	completed.append(_suite)
```

每个套件的 `run(r)` 末尾必须 `r.complete()`。原因：实测一个 `-> int` 的函数内部崩掉时，调用者收到的是 **0**；如果 runner 只数返回值，崩溃会被当成"零失败"。"完成标记缺失"是唯一可靠的崩溃信号。

### 外壳看门狗 + 哨兵（必须有）

因为三类失败都可能是"退出码 0"或"永远不退出"：

| 失败 | 实测表现 | 外壳对策 |
|------|----------|----------|
| 脚本解析错误 / 依赖编译失败 | `SCRIPT ERROR`，**rc=0** | 必须看到 `TESTS_DONE failures=0`；没有就失败 |
| 入口函数运行时错误 / `assert` | 打印错误后 **挂死** | 看门狗超时 + 杀进程 |
| 非 `SceneTree` 脚本 | 只打 banner，**挂死** | 同上 |
| 套件函数运行时错误 | 调用者继续，但该套件断言没跑 | reporter 的 `complete()` 标记 |

macOS **默认没有** `timeout`（本机恰好有，但干净机器不保证）。用 bash 3.2 兼容的后台看门狗：

```bash
run_with_timeout() {
	local secs="$1"; shift
	local out="$1"; shift
	"$@" >"$out" 2>&1 &
	local pid=$!
	( sleep "$secs"; kill -TERM "$pid" 2>/dev/null; sleep 2; kill -KILL "$pid" 2>/dev/null ) &
	local watcher=$!
	local rc=0
	wait "$pid" || rc=$?
	kill "$watcher" 2>/dev/null || true
	wait "$watcher" 2>/dev/null || true
	return "$rc"
}
```

然后：

```bash
out="$(mktemp)"
if ! run_with_timeout 180 "$out" "$godot" --headless --path "$repo_root/mobile" --script res://tests/run_tests.gd; then
	cat "$out"; echo "✗ 核心测试进程失败/超时" >&2; exit 1
fi
grep -q "TESTS_DONE failures=0" "$out" || { cat "$out"; echo "✗ 没有完成哨兵（解析/编译/运行时错误都可能 rc=0）" >&2; exit 1; }
```

---

## Q2. "零引擎依赖"的可执行定义 + 机械 lint

### 先纠正一个说法：不是"不能运行"，是"不能有环境状态"

`Input`、`Time`、`OS`、`FileAccess` 在 `--headless` 下**都能被调用**（实测 `Time.get_ticks_msec()` 在 `_init` 返回 74；`Input.get_connected_joypads()` 返回空数组，不崩）。`Node.new()` 也能在无树环境下构造。所以"零引擎依赖"不是运行时不可能，而是**设计约束**：core 不允许有环境状态、I/O、场景树或日志，否则它就无法被确定性回放、无法在无设备 CI 跑、也无法证明与桌面版一致。

**可执行定义（写进 `mobile/docs/CORE.md`，lint 按此实现）：**

> `src/core/**` 不得读取任何环境状态（时钟、输入、OS、配置单例）、不得做 I/O、不得持有或构造场景树类型、不得写日志/错误通道。所有输入以参数传入，所有输出以返回值传出。`JSON` 与 `RegEx` 是两个明确例外：它们是纯解析器，无 I/O、无环境状态、结果确定。

### 允许 / 禁止清单

| 类别 | 允许（无环境状态） | 禁止（在 core 内） |
|------|-------------------|--------------------|
| Variant 类型 | `String`, `StringName`, `Vector2`, `Vector2i`, `Dictionary`, `Array`, `PackedByteArray`, `PackedFloat64Array`, `PackedStringArray`, `int/float/bool` | — |
| 纯数学全局函数 | `abs`, `absf`, `min`, `max`, `clamp`, `clampf`, `fmod`, `fposmod`, `atan2`, `sqrt`, `deg_to_rad`, `rad_to_deg`, `wrapf`, `snappedf`, `is_equal_approx`, `PI`, `TAU` | `randi`, `randf`, 任何依赖全局种子的随机 |
| 纯类 | `RefCounted`, `Object`, `JSON`, `RegEx` | `Resource`（按路径缓存，`load()` 两次返回同一实例 → 可变状态跨测试泄漏） `[CITED: .planning/research/ARCHITECTURE.md §Class vs Node vs Autoload]` |
| 环境单例 | — | `Input.`, `Time.`, `OS.`, `Engine.`, `ProjectSettings.`, `DisplayServer.`, `ResourceLoader.`, `TranslationServer.` |
| 场景树 | — | `Node`, `Node2D`, `Control`, `SceneTree`, `Viewport`, `Window`, `get_tree(` |
| I/O | — | `FileAccess`, `DirAccess`, `FileDialog`, `HTTPRequest` |
| 日志 / 错误通道 | — | `print(`, `prints(`, `printt(`, `printerr(`, `print_rich(`, `print_debug(`, `push_error(`, `push_warning(` |
| 编辑器 | — | `@tool`（`--import` 隐含 `--editor`，`@tool` 脚本可能在导入期被执行；`[ASSUMED]` 具体取决于是否有节点/资源实例化它） |
| 依赖方向 | `preload("res://src/core/...")` | `preload/load("res://src/platform\|ui\|app/...")` |

**为什么 `JSON` 必须例外：** 配置校验的 BOM / UTF-8 / JSON 语法错误是 RESIL-02 的一部分，必须能在纯层里测。把 JSON 解析推到 app 层会让"BOM → 结构化错误"这条成功标准无法 headless 验证。`JSON` 没有 I/O、没有单例、没有环境状态，和 `RegEx` 同级。**不要**因此把 `FileAccess` 也放进来——它读的是真实文件系统。

### lint 实现：Python 文本扫描（不是 GDScript，不是 `--check-only`）

**为什么不用 `--check-only`：** 它只做解析，不检查 API 使用；而且实测它对解析错误也返回 **0**（Phase 2 已记录，本次复测确认）。它不能作为架构闸门。

**为什么不用 GDScript 写 lint：** 扫描 GDScript 需要先剥离注释/字符串，这是一个文本处理任务；用 GDScript 写等于在 Godot 里再造一个易错的小解析器，而且 CI 还得先装 Godot。Python 是仓库已有的工具语言（`sync_config.py`、`check_desktop.sh`），可以直接进现有 CI。

**算法（原型已在 lab 实测）：**

1. 逐字符扫描，状态机：`normal` / `line_comment` / `string(delim, triple)`。
2. `#` 到行尾 → 全部替换为空格（保留换行与列号）。
3. 单引号 / 双引号 / 三引号 / `r"..."` / `&"..."` / `^"..."`：识别起始引号，处理 `\` 转义，直到同种引号闭合；内容全部替换为空格（换行保留）。
4. 对"剥离后的代码"逐行跑规则正则。
5. 输出 `relative_path:line: rule: token`，任何命中 → rc=1；干净 → rc=0；`--root` 不存在或零个 `.gd` → rc=2（"这不是一次有效运行"，与 Phase 1 的 `rc=2` 约定一致）。

**规则表（前 5 条是 INFRA-03 的硬性集合，不可删；其余是"零引擎依赖"的扩展）：**

| rule | 正则（对剥离后的代码） | 为什么 |
|------|------------------------|--------|
| `input_singleton` | `\bInput\s*\.` | INFRA-03 |
| `time_singleton` | `\bTime\s*\.` | INFRA-03；时钟必须由参数传入 |
| `node_type` | `\bNode\b` | INFRA-03；场景树类型 |
| `fileaccess_io` | `\bFileAccess\b` | INFRA-03；I/O 归 app |
| `logging` | `\b(print\|prints\|printt\|printerr\|print_rich\|print_debug\|push_error\|push_warning)\s*\(` | INFRA-03 的 `print(` + RESIL-02 的"不许 push_error" |
| `os_singleton` | `\bOS\s*\.` | 环境状态 |
| `engine_singleton` | `\bEngine\s*\.` | 环境状态（`is_editor_hint` 等） |
| `display_server` | `\bDisplayServer\b` | 平台层 |
| `tree_access` | `\bget_tree\s*\(` | 场景树 |
| `scene_tree_type` | `\bSceneTree\b` | 场景树 |
| `resource_loader` | `\bResourceLoader\b` | 资源系统 / 路径缓存 |
| `resource_type` | `\bResource\b` | core 数据对象用 `RefCounted`；`Resource` 按路径缓存，`load()` 两次返回同一实例 |
| `tool_annotation` | `^\s*@tool\b` | 导入期副作用 |
| `outer_layer_dep` | `(?:preload\|load)\s*\(\s*"res://src/(?:platform\|ui\|app)/` | 依赖方向：core 不得反向依赖 |

**原型实测（lab，非仓库）：**

- `clean_sample.gd`：把 `Input.` / `Time.` / `Node` / `FileAccess` / `print(` 全部写进 `##` 注释、普通字符串、单引号字符串、三引号字符串、raw string，另有合法标识符 `InputSource` → **`LINT_HITS=0`，rc=0**。
- `dirty_sample.gd`：真实使用 `Input.get_joy_axis`、`Time.get_ticks_usec`、`Node.new`、`FileAccess.open`、`print`、`push_error` → **6 命中，rc=1**。

### 必须容忍的假阳性

| 场景 | 处理 |
|------|------|
| 中文 docstring 里提到 `Input` / `Time` / `Node` | 注释剥离后不命中 |
| 错误消息字符串里写 `"不要用 Input."` | 字符串剥离后不命中 |
| `InputSource`、`NodeState`、`NodePath` | `Input\.` 要求点；`\bNode\b` 的词边界不匹配 `NodeState`/`NodePath`。**注意：** `NodePath` 本身是纯类型，但 `\bNode\b` 不会误伤它 |
| 小写 `input.deadzone`（JSON path） | 规则大小写敏感，`Input\.` 不匹配 `input.` |
| `#region` / `#endregion` | 行注释 |
| 三引号里的 `"""` 转义 | 原型按 `delim*3` 查找闭合；极端嵌套转义可能误判，作为已知限制记录 |

### 已知漏报（记录，不追求完美）

- 用行继续符把 token 拆开（`Inp\` 换行 `ut.`）→ 不命中。
- 动态调用 `ClassDB.instantiate("Node")` / `call("print")` → 字符串被剥离，不命中。
- `preload` 路径用变量拼接 → 不命中。
这些都不是本阶段的现实写法；lint 的目标是"挡住无意识引入"，不是"对抗恶意代码"。

### 自测（反例优先，沿用 Phase 1 文化）

`tools/test_lint_core.py` 用 `tempfile.mkdtemp()` 搭临时 core 目录，写 canary `.gd`，直接调 `lint_core.scan_text()`：

- clean canary → 0 命中
- 五条硬规则各一个 canary → 对应 rule 命中
- 注释/字符串 canary → 0 命中
- `tests/*` 嵌套路径 + `outer_layer_dep` → 命中
- `--root` 不存在 → rc=2；空目录 → rc=2

---

## Q3. 逐字移植 `geometry.py`

### Python 源（规格书）

```python
# desktop/padskills/geometry.py:23-54（逐字）
def norm_deg(angle: float) -> float:
    """把任意角度归一化到 [0, 360)。"""
    return angle % 360.0


def signed_delta(a_from: float, a_to: float) -> float:
    """从 a_from 旋转到 a_to 的**最短带符号**旋转量，范围 (-180, 180]。

    正值 = 顺时针（对应角度增大的方向）。
    """
    return ((a_to - a_from + 180.0) % 360.0) - 180.0


def angle_diff(a: float, b: float) -> float:
    """两个角度之间的最小夹角，范围 [0, 180]。"""
    return abs(signed_delta(a, b))


def angle_of(x: float, y: float) -> float:
    """由摇杆原始坐标求角度。x 向右为正，y 向下为正。

    摇杆居中（或落在死区内）时返回 0.0 而不是让 atan2 给出无意义的值——
    注意 atan2(0.0, -0.0) 会得到 π（180°），居中时显示成"正后方"很误导人。
    """
    if x == 0.0 and y == 0.0:
        return 0.0
    return norm_deg(math.degrees(math.atan2(x, -y)))


def magnitude(x: float, y: float) -> float:
    """摇杆推杆幅度，范围 [0, ~1.41]（斜推角落时会略大于 1）。"""
    return math.hypot(x, y)
```

`[VERIFIED: desktop/padskills/geometry.py:23-54]`（本 session 用 Read 打开；上段为逐字引用）

### GDScript 等价实现（本机实测与 Python 逐项一致）

```gdscript
# mobile/src/core/geometry.gd
class_name Geometry
extends RefCounted

## 本项目全局角度约定：0° = 上，90° = 右，180° = 下，270° = 左；范围 [0, 360)。
## 手柄原始坐标是 SDL / Godot 约定：x 向右为正，y 向下为正；只在 angle_of() 里换算一次。


static func norm_deg(angle: float) -> float:
	# 不能用 %：GDScript 对两个 float 使用 % 是解析错误；fmod 会保留负号。
	return fposmod(angle, 360.0)


static func signed_delta(a_from: float, a_to: float) -> float:
	# 与 Python 的实现逐字对应。注意实际区间是 [-180, 180)：
	# 正好 180° 时返回 -180（Python 的 % 是 floor-mod，不是 C 的 fmod）。
	return fposmod(a_to - a_from + 180.0, 360.0) - 180.0


static func angle_diff(a: float, b: float) -> float:
	return absf(signed_delta(a, b))


static func angle_of(x: float, y: float) -> float:
	# 居中守卫：x == 0.0 也覆盖 -0.0；没有它 atan2(0.0, -0.0) 会返回 180°。
	if x == 0.0 and y == 0.0:
		return 0.0
	return norm_deg(rad_to_deg(atan2(x, -y)))


static func magnitude(x: float, y: float) -> float:
	return sqrt(x * x + y * y)
```

### GDScript 与 Python 的差异（逐条）

| 差异 | Python | GDScript | 后果 |
|------|--------|----------|------|
| 浮点取模 | `-90 % 360 = 270`（floor-mod） | `%` 对 float **解析错误**；`fmod(-90,360) = -90` | 必须用 `fposmod`；用 `fmod` 会让负角度保持负值，"左"变"右" |
| `atan2` 参数顺序 | `math.atan2(y, x)` | `atan2(y, x)`（同为 y 在前） | 公式文本恰好都是 `atan2(x, -y)`；**不要**因为"Godot 是 y 在前"就写成 `atan2(-y, x)` |
| `sin/cos` 的坐标系 | 数学系 | 数学系（`Vector2` 才是 y-down） | 用 `atan2(x,-y)` 一次换算，其余代码不再碰原始坐标 |
| `Vector2.angle()` | 无对应 | 从 +X 起、y-down；上 = `-π/2` | **禁止**在 core 用 `Vector2.angle()` / `Vector2.rotated()` 推角度 |
| `math.degrees` | `x * (180/π)` | `rad_to_deg(x)` = `x * (180/π)` | 实测 9 个方向全部精确一致（打印 17 位） |
| `math.hypot` | 带缩放，斜向返回精确 1.0 | `sqrt(x*x+y*y)` 斜向返回 `0.99999999999999989` | 幅度断言必须带容差（1e-9 足够）；不要做 `==` 断言 |
| `%` 的整数行为 | `5 % 2 = 1` | `5 % 2 = 1` | 只对 int 可用；时间/角度一律用 float |

### 为什么文档字符串的区间是错的（不要修）

Python 实测：

```text
signed_delta(0, 180)   = -180.0
signed_delta(-180, 0)  = -180.0
signed_delta(180, 0)   = -180.0
signed_delta(0, -180)  = -180.0
signed_delta(0, 181)   = -179.0
signed_delta(350, 10)  = 20.0
signed_delta(10, 350)  = -20.0
signed_delta(270, 0)   = 90.0
signed_delta(0, 270)   = -90.0
```

`[VERIFIED: desktop/padskills/geometry.py 在 Python 3 下实际运行]`

所以真实区间是 **`[-180, 180)`**，不是注释里的 `(-180, 180]`。`angle_diff` 用 `abs`，端点无影响；但 `ArcDetector` 的 `_turn_sign` / 方向判定可能依赖 180° 整的符号。**移植的目标是行为对等，不是注释对等**：保留公式，修正注释，并在测试里把 `signed_delta(0, 180) == -180` 固化成黄金向量，防止后人"修正"成 +180。

### 八方向 + 中心黄金表（Python 生成，GDScript 实测一致）

| case | x | y | angle_of |
|------|---|---|----------|
| center | 0.0 | 0.0 | 0.0 |
| up | 0.0 | -1.0 | 0.0 |
| upright | 0.7071067811865476 | -0.7071067811865476 | 45.0 |
| right | 1.0 | 0.0 | 90.0 |
| downright | 0.7071067811865476 | 0.7071067811865476 | 135.0 |
| down | 0.0 | 1.0 | 180.0 |
| downleft | -0.7071067811865476 | 0.7071067811865476 | 225.0 |
| left | -1.0 | 0.0 | 270.0 |
| upleft | -0.7071067811865476 | -0.7071067811865476 | 315.0 |

`[VERIFIED: Python 与 Godot 4.7.2 双侧实测，9/9 一致]`

**这些向量能抓住的静默失败：**

- 写成 `atan2(y, x)`（或 `Vector2.angle()`）→ `up` 得 270°、`right` 得 0°；整张表逆时针转了 90°。
- 用 `Vector2(x,y).angle()` → 与上一条同源（`atan2(y,x)`），`up` 得 -90°（再 norm 成 270°），`right` 得 0°。
- 忘了 `fposmod`，用 `fmod` → `left` 得 -90° 而不是 270°；`sd(0,270)` 得 -270° 而不是 -90°。
- 去掉居中守卫 → `angle_of(0,0)` 得 180°（`atan2(0.0,-0.0)`），UI 显示"正后方"。
- 把 `signed_delta` 的端点"修正"成 +180 → `sd(0,180)` 从 -180 变 +180，方向判定分叉。

**额外必须进黄金表的用例：** `norm_deg(-90)=270`、`norm_deg(360)=0`、`norm_deg(-1e-12)=359.999999999999`、`angle_of(-0.0,-0.0)=0`、`signed_delta(0,180)=-180`、`signed_delta(350,10)=20`、`signed_delta(10,350)=-20`、`magnitude(1,0)=1`、`magnitude(s,s)≈1`（容差 1e-9）。

---

## Q4. 配置校验：返回结构化错误，不 raise / assert / push_error

### Python 的现状（规格书 + 要修的 bug）

`load_config()` 用 `raise SystemExit(...)` 报错，一次只给第一条；`parse_config()` 内部用 `raise ValueError(...)`。具体规则（逐字摘自 `desktop/padskills/config.py`）：

- 根节点：`"配置文件根节点必须是 JSON 对象"`；`"配置文件里 skills 必须是非空数组"`；`"动作名称重复: ..."`（`config.py:748-764`）
- 动作：`"skills[{index}] 必须是对象"`；`"动作 {name!r} 的 type 必须是 'arc'、'sequence' 或 'taps'..."`；`"动作 {name!r} 的 params 必须是对象"`（`config.py:554-568`）
- sequence：`"动作 {name!r} 是 sequence 类型，params.steps 必须是非空数组"`；`"动作 {name!r} 的 steps[{i}]: {exc}"`；`"动作 {name!r}: max_duration_ms (...) 必须大于 min_duration_ms (...)"`；`"动作 {name!r}: 各步骤 hold_ms 合计 ... 已经不小于 max_duration_ms ...，这个动作永远无法触发..."`（`config.py:570-596`）
- arc：`"动作 {name!r} 的 max_angle (...) 必须大于 min_angle (...)"`；`max_duration_ms <= min_duration_ms`；`start_angle`/`end_angle`/`end_angles` 的空数组与方向解析（`config.py:598-622`）
- taps：`params.button` 规范化；`min_interval_ms` 负数；`max_interval_ms > min_interval_ms`；`modifier_options` 非空数组 / 规范名 / 不重复（`config.py:624-653`）
- 公共时间参数：`idle_timeout_ms`、`release_hold_ms` 不能为负；`idle_timeout_ms > 0`；`motion_min_delta_deg > 0`（`config.py:541-551`）
- 修饰键：`button_mode` 只能是 `'all'` / `'any'`；`modifier_options` 必须同时有 `required_button`；`required_button` 必须在 `modifier_options` 里（`config.py:528-538, 655-670`）
- rumble：`rumble` 无法解析 / `pattern` 非空 / item 必须是对象 / `low`/`high` 在 0..1（`config.py:499-525`）
- input：`input` 必须是对象；`deadzone`/`ls_facing_threshold`/`trigger_threshold` 在 0..1；`axis_layout` 对象或 null；`invert` 键只能是 `ls_x/ls_y/rs_x/rs_y`、值必须是 bool；`button_names` 对象或 null（`config.py:686-726`）
- rumble 配置：`backend` 只能是 `auto/pygame/sdl2/xinput/none`；`startup_test_strength` 0..1（`config.py:729-745`）

`[VERIFIED: desktop/padskills/config.py:489-801]`（本 session Read）

**按键规范化（必须逐字复制，不能只抄"常用键"）：**

```python
# desktop/padskills/input_source.py:35-60（逐字）
CANONICAL_BUTTONS: Tuple[str, ...] = (
    "A", "B", "X", "Y",
    "LB", "RB", "LT", "RT",
    "LS", "RS", "BACK", "START", "GUIDE",
    "DPAD_UP", "DPAD_DOWN", "DPAD_LEFT", "DPAD_RIGHT",
)

BUTTON_ALIASES: Dict[str, str] = {
    "L1": "LB", "L2": "LT", "L3": "LS",
    "R1": "RB", "R2": "RT", "R3": "RS",
    "CROSS": "A", "CIRCLE": "B", "SQUARE": "X", "TRIANGLE": "Y",
    "SHARE": "BACK", "OPTIONS": "START", "TOUCHPAD": "BACK",
    "LSTICK": "LS", "RSTICK": "RS", "LTHUMB": "LS", "RTHUMB": "RS",
    "VIEW": "BACK", "SELECT": "BACK", "CREATE": "BACK",
    "MENU": "START", "PAUSE": "START",
    "HOME": "GUIDE", "PS": "GUIDE", "XBOX": "GUIDE",
    "DUP": "DPAD_UP", "DDOWN": "DPAD_DOWN", "DLEFT": "DPAD_LEFT", "DRIGHT": "DPAD_RIGHT",
    "DPADUP": "DPAD_UP", "DPADDOWN": "DPAD_DOWN",
    "DPADLEFT": "DPAD_LEFT", "DPADRIGHT": "DPAD_RIGHT",
    "LEFTSHOULDER": "LB", "RIGHTSHOULDER": "RB",
    "LEFTTRIGGER": "LT", "RIGHTTRIGGER": "RT",
    "LEFTSHOULDERBUTTON": "LB", "RIGHTSHOULDERBUTTON": "RB",
}
```

`[VERIFIED: desktop/padskills/input_source.py:35-60]`（本 session Read；上段为逐字引用）

**Python 侧的"晚失败"证据（`start_angle` 数组为什么必须在校验期拒绝）：**

```python
# desktop/padskills/detectors.py:154-170（逐字）
        direction = str(p.get("direction", "any")).strip().lower()
        if direction in ("cw", "clockwise", "顺时针"):
            self.direction = 1
        elif direction in ("ccw", "counterclockwise", "逆时针"):
            self.direction = -1
        else:
            self.direction = 0
        ...
        raw_start = p.get("start_angle")
        self.start_target: Optional[float] = (
            None if raw_start is None else resolve_direction(raw_start)
        )
```

`[VERIFIED: desktop/padskills/detectors.py:154-170]`（本 session Read；上段为逐字引用）

两件事同时被这段证明：**(a)** 未知 `direction` 静默落到 `else: self.direction = 0`（= `any`），所以配置里的拼写错误不会报错，只会改变判定语义；**(b)** `start_angle` 数组在 `parse_config` 时能过，到 `ArcDetector.__init__` 才由 `resolve_direction(raw_start)` 抛错——这正是 Phase 3 要提前到校验期的 bug。

**五个已被实测的 Python 行为（前四条是 Phase 3 成功标准点名的）：**

| 注入 | Python 实测 | 问题 |
|------|-------------|------|
| `"enabled": "false"` | **ACCEPT**，`bool("false")` = True | 用户以为关掉了，实际开着——静默错误语义 |
| `"min_duration_ms": null` | **REJECT**，但抛 `TypeError: float() argument must be...`（不是 `ValueError`），`load_config` 只 catch `ValueError` → 未捕获异常 | 错误信息不可操作，且可能直接崩 |
| `"start_angle": [90, 180]` | **ACCEPT** at `parse_config`；到 `ArcDetector.__init__` 的 `resolve_direction(list)` 才 `ValueError` | 错误发现得太晚（引擎构造时），且在校验器的语义里是合法写法 |
| 文件带 UTF-8 BOM | **REJECT**（`json.loads(str)` → `Unexpected UTF-8 BOM`） | 消息是英文 JSON 错误，不是"另存为无 BOM" |
| `"min_duration_ms": "250"` | **ACCEPT**（`float("250")`） | 宽松强转；与布尔一样属于"类型混淆"家族，建议一并严格化 |

`[VERIFIED: 在 desktop/ 下用 Python 3 实际调用 parse_config]`

注意：`json.loads(bytes)` 会按 `utf-8-sig` **接受** BOM；`load_config` 是先 `path.read_text(encoding="utf-8")` 再 `json.loads(str)`，所以拒绝。写 parity 脚本时必须模拟后者，不能直接 `json.loads(open(...,'rb').read())`。

### GDScript 契约：返回 `ConfigResult`，不抛异常

GDScript 没有受检异常，也不该用 `assert`（release 被剥离）或 `push_error`（安卓没有 console，用户看不见）。**唯一正确的形状是返回值：**

```gdscript
class_name ConfigError
extends RefCounted

const SEVERITY_ERROR := &"error"
const SEVERITY_WARNING := &"warning"

var json_path: String      # "skills[3].params.max_duration_ms"；根用 "$"
var code: StringName       # &"number_expected" / &"bom_detected" / ...
var message: String        # 中文，人能看懂，含实际值
var fix_hint: String       # 中文，告诉用户改哪里、改成什么
var severity: StringName   # &"error" | &"warning"

func _init(p_path: String, p_code: StringName, p_message: String,
		p_fix_hint: String, p_severity: StringName = SEVERITY_ERROR) -> void:
	json_path = p_path
	code = p_code
	message = p_message
	fix_hint = p_fix_hint
	severity = p_severity

func format_line() -> String:
	return "[%s] %s: %s（%s）" % [code, json_path, message, fix_hint]
```

```gdscript
class_name ConfigResult
extends RefCounted

var config: AppConfig                 # 有 error 时为 null
var errors: Array[ConfigError] = []
var warnings: Array[ConfigError] = []
var source_path := ""                 # "res://assets/config/skills_config.json" / "user://config/overrides.json"
var notice := ""                      # 覆盖层被丢弃等一次性提示（中文）
var overrides_applied := false

func ok() -> bool:
	return errors.is_empty() and config != null

func to_text() -> String:
	var lines: PackedStringArray = []
	for e in errors:
		lines.append(e.format_line())
	for w in warnings:
		lines.append(w.format_line())
	return "\n".join(lines)
```

**最小形状判据：** 每条错误必须同时带 `json_path` + `code` + `message` + `fix_hint`。`severity` 不是成功标准要求的，但强烈建议从第一天就有——因为 Python 的 `poll_hz`/`calibration_ms`/`cooldown_ms` 等是**静默 clamp**，把它们降级成 `warning`（"已按 30..1000 截断为 250"）比伪造成错误更诚实，也符合"不静默降级"。

### 收集所有错误，而不是第一条

- 顶层按顺序检查：根节点 → `skills` → 每个 skill → 汇总重复名。
- 每个 skill 内部：先检查 `type` 与 `params` 的结构；结构不成立时，**只跳过依赖它的检查**（例如 `type` 非法就不做 arc/sequence/taps 的专项检查），但 `required_button`/`rumble`/`cooldown_ms`/`enabled` 这些不依赖 `type` 的字段仍然检查。
- 每个 `resolve_direction` / `canonical_button` 失败都变成一条 `ConfigError`，带上 `steps[i]` / `params.button` 的路径，而不是抛出去。
- 最后统计重复名：`skills[i].name` 重复时，给**每一处**都报一条（或至少给后出现的那条报，消息里点名第一次出现的位置）。
- 任何一个 error → `config = null`；只有 warnings → `config` 正常返回。

### 错误码表（建议，稳定后不要改名）

| area | codes |
|------|-------|
| 文件/JSON | `file_missing`, `file_read_error`, `file_too_large`, `bom_detected`, `invalid_utf8`, `file_empty`, `json_syntax_error`, `root_not_object` |
| skills | `skills_not_array`, `skills_empty`, `skill_not_object`, `skill_type_invalid`, `params_not_object`, `duplicate_skill_name` |
| 类型 | `number_expected`, `bool_expected`, `string_expected`, `array_expected`, `object_expected`, `null_not_allowed` |
| 方向/步骤 | `direction_unknown`, `direction_is_bool`, `step_direction_missing`, `step_hold_not_number`, `step_hold_negative`, `step_group_empty`, `steps_empty`, `start_angle_not_scalar` |
| 数值约束 | `out_of_range`, `max_not_greater_than_min`, `hold_sum_exceeds_max`, `negative_value`, `must_be_positive` |
| 按键 | `button_unknown`, `button_mode_invalid`, `modifier_options_invalid`, `modifier_duplicate`, `modifier_requires_required_button`, `required_button_not_in_options` |
| rumble | `rumble_invalid`, `rumble_pattern_empty`, `rumble_item_not_object`, `rumble_backend_invalid` |
| input | `input_not_object`, `axis_layout_not_object`, `invert_not_object`, `invert_key_invalid`, `invert_value_not_bool`, `button_names_not_object` |
| 覆盖层 | `overlay_schema_invalid`, `overlay_schema_too_new`, `overlay_base_changed`, `overlay_skill_unknown`, `overlay_key_unknown` |

### 错误屏契约（RESIL-02）

错误屏只需要消费 `ConfigResult`，不做任何解释：

- 顶部：配置来源（`source_path`）+ "发现 N 个问题"。
- 每条 `ConfigError` 一行/一块：`json_path`（等宽小字）、`message`（大字）、`fix_hint`（带 `→` 前缀）。
- 底部：「复制」（`DisplayServer.clipboard_set(result.to_text())`）、「恢复默认」（删除 `user://config/overrides.json` 并重载）。
- `notice`（覆盖层被丢弃）单独一条横幅，不是 error。

**范围建议：** Phase 3 必须交付 `ConfigResult` + `to_text()` + headless 测试证明四种坏输入的 `json_path`/`code` 都在输出里（这就满足"可原样渲染"）。**建议**同时交付一个最小的 `src/ui/error_screen.gd/.tscn`（`VBoxContainer` + 动态 Label），并用一个 headless 场景测试断言四条错误的路径与码出现在 Label 文本里；完整的视觉/交互留给 Phase 7。若计划阶段认为这会把 UI 提前拉进来，至少保留 `to_text()` 这个"可渲染"的机械证明，并在 Phase 4 的组合根里接上真正的屏。

### Python 与 GDScript 的"严格性"取舍（必须显式记录）

| 情形 | Python | 建议 GDScript | 理由 |
|------|--------|---------------|------|
| `"enabled": "false"` | 接受，静默为 True | **拒绝** `bool_expected` | 两个平台对同一份配置的语义会分叉，比拒绝更糟 |
| `min_duration_ms: null` | TypeError | **拒绝** `number_expected` | 可操作的中文错误 |
| `min_duration_ms: "250"` | 接受（强转） | **建议拒绝** `number_expected` | 同一"类型混淆"家族；拒绝一次，用户改一次，两端都接受 |
| `start_angle: [90,180]` | 接受，构造检测器时崩 | **拒绝** `start_angle_not_scalar` | 修复 Python bug #1；`end_angle` 仍允许数组 |
| `direction: "clockwisee"` | 静默当 `any` | **建议拒绝** `direction_unknown` | 静默改变判定语义；shared 配置里只有 `any` |
| `poll_hz: 5000` | 静默 clamp 到 1000 | **warning** `out_of_range` + 应用截断值 | 不阻塞启动，但必须让用户看见 |
| `cooldown_ms: -5` | 静默 clamp 到 0 | **warning** `negative_value` + 应用 0 | 同上 |

> 这些取舍会写入 `tools/check_config_parity.py` 的 `.expect.json`（`"python": "accept", "godot": "reject", "divergence": "..."`），把"故意不一致"变成显式契约，而不是隐藏的偏差。

---

## Q5. `user://` 稀疏覆盖层（DATA-03）

### 路径语义

- `res://` = 工程资源；导出后**只读**（在编辑器/`--path` 跑时是本机目录，能写——所以"绝不写 res://"不能靠本地测试证明，只能靠代码结构与守卫）。
- `user://` = 用户数据；官方原文："Unlike `res://`, the directory pointed at by `user://` is created automatically and *guaranteed* to be writable to, even in an exported project." `[CITED: docs.godotengine.org/en/4.7/tutorials/io/data_paths.html]`
- 桌面默认路径：macOS `~/Library/Application Support/Godot/app_userdata/[project_name]`；Windows `%APPDATA%\Godot\app_userdata\[project_name]`；Linux `~/.local/share/godot/app_userdata/[project_name]`。`[CITED: 同上]`
- 移动端："this path is unique to the project and is not accessible by other applications for security reasons." `[CITED: 同上]`（没有给出 Android 的绝对路径；不要依赖它）。
- **本机实测**：当前工程名是中文，`--path mobile --script` 打印 `USER_DIR=/Users/stephen/Library/Application Support/Godot/app_userdata/FIFA 花式动作练习器`。`[VERIFIED: 真实 mobile 工程 headless probe]`

**建议在 Phase 3 定下 `use_custom_user_dir`：**

```ini
[application]
config/use_custom_user_dir=true
config/custom_user_dir_name="FifaSkillTrainer"
```

这样桌面开发路径变成 `~/Library/Application Support/FifaSkillTrainer`（ASCII、无空格），`application/config/name`（应用显示名）仍然是中文。`[CITED: docs.godotengine.org/en/4.7/classes/class_os.html + data_paths.html]` **必须在任何用户数据产生之前决定**：Phase 9 的 v1→v2 覆盖安装依赖 `user://` 位置不变；发布后再改等于丢数据。Android 上该设置是否影响沙箱路径未验证，`[ASSUMED]` 不影响（Android 的 `user://` 是应用私有目录）。

### 首启：没有文件是正常状态

- `FileAccess.file_exists(overrides_path) == false` → 只用 base，**不要**创建空文件，不要报错，不要提示。
- 只有用户第一次改按键/开关时才写。

### 写：temp + rename，flush 在 close 之前

```gdscript
const OVERRIDES_DIR := "user://config"
const OVERRIDES_PATH := "user://config/overrides.json"

func save_overrides(data: Dictionary) -> Error:
	var target := _overrides_path
	var temp := target + ".tmp"
	if not target.begins_with("user://") or not temp.begins_with("user://"):
		return ERR_UNAUTHORIZED           # 生产路径必须是 user://；绝不尝试写 res://
	var dir_err := DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	if dir_err != OK:
		return dir_err
	var f := FileAccess.open(temp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(data, "\t", true))
	f.flush()
	f.close()
	var err := DirAccess.rename_absolute(temp, target)
	return err
```

实测（macOS，4.7.2）：

- `DirAccess.make_dir_recursive_absolute("user://lab")` → OK。
- 首次 `DirAccess.rename_absolute(tmp, final)` → `0`（OK）。
- **目标已存在时再 rename** → 仍然 `0`，内容被覆盖，tmp 消失。官方文档："If the destination file or directory exists and is not access-protected, it will be overwritten." `[CITED: docs.godotengine.org/en/4.7/classes/class_diraccess.html]` `[VERIFIED: 本机实测覆盖成功]`
- Android 是 POSIX 文件系统，`rename(2)` 同样原子覆盖；但**未真机验证**，`[ASSUMED]`。`FileAccess.flush()` 在 `close()` 之前调用，保证数据落到内核再 rename。

### 读：bytes，不是 string

**必须用 `FileAccess.get_file_as_bytes()`。** 实测：同一份带 BOM 的文件，`get_file_as_bytes()` 返回 `[239,187,191,...]`；`get_file_as_string()` 返回的字符串长度少 1、首字符是 `{`、`begins_with("\uFEFF") == false`。`[VERIFIED: 本机 4.7.2 实测]`

这直接决定 RESIL-02 的 BOM 用例：**如果加载器/测试用 `get_file_as_string()`，BOM 会在读文件时被剥掉，校验器永远看不到它，成功标准 3 会假绿。** 正确分工：

- `ConfigStore`（app）用 `get_file_as_bytes()` 读 base 与 overlay。
- `ConfigLoader.parse_bytes(bytes, source)`（core）检查 `EF BB BF` → `bom_detected`；然后 `bytes.get_string_from_utf8()`；空 bytes → `file_empty`；非空 bytes 解码为空串 → `invalid_utf8`。
- 测试也必须用 bytes 读 fixture（或在测试里直接用 `PackedByteArray([0xEF,0xBB,0xBF]) + clean_bytes` 合成）。

### 覆盖层 schema（稀疏）

```json
{
  "schema_version": 1,
  "base_sha256": "bccf123a06efc61c7f05bc430e488a0f596bdc1e5c7eade4c18a3660f9d0eee9",
  "skills": {
    "马赛回旋 Roulette": { "required_button": "LB" },
    "绿色搓射 Green Finesse": { "enabled": false }
  }
}
```

- 只允许**白名单键**：`enabled`、`required_button`、`button_mode`。`params` 里的阈值**不进覆盖层**——它们是 shared 配置的职责；允许用户改阈值会让历史数据不可比（PROJECT.md 的反目标）。
- 以 **skill name** 为键，不用索引（索引会随 base 重排漂移）；skill name 已被"唯一"校验。
- `schema_version` 用数字；JSON 解析后是 float（`1` → `1.0`），比较时 `int(v)`。
- `base_sha256` 用**当前 base 文件字节**的 SHA-256（`FileAccess.get_sha256(base_path)`，64 位小写 hex），不要用 `.sha256` sidecar（sidecar 可能是旧的或被手改）。
- 合并语义（纯函数 `OverlayMerge.merge`）：
  1. overlay 缺 `schema_version` 或不是数字 → 丢弃，`overlay_schema_invalid`。
  2. `int(schema_version) > SCHEMA_VERSION` → 丢弃，`overlay_schema_too_new`（未来版本写的文件，当前版本不猜）。
  3. `base_sha256` 不是字符串或与当前 hash 不相等（忽略大小写）→ **丢弃全部覆盖**，`overlay_base_changed`，`notice = "配置已更新，已丢弃自定义按键设置。"`
  4. `skills` 不是对象 → 丢弃；每个键必须是 base 里存在的 skill name，否则 warning `overlay_skill_unknown` 并忽略该条。
  5. 每个 skill 的值必须是对象；白名单键逐个应用；未知键 → warning `overlay_key_unknown` 并忽略。
  6. 深拷贝 base（`base.duplicate(true)`），在副本上应用；**不要修改调用者传入的 base**。
  7. 返回 `OverlayResult { data, warnings, applied, discarded_reason, notice }`。
- 丢弃后建议**删除** `user://config/overrides.json`（或用 `.bak` 改名）：否则每次启动都会重复丢弃与提示，用户会被同一条横幅反复打扰。
- 合并后的字典再交给 `ConfigValidator.validate()`；如果覆盖层把配置改成非法（例如 `required_button` 拼错），错误屏照样出现，并且「恢复默认」按钮删除覆盖层即可恢复。

### I/O 与纯语义的分界

| 职责 | 位置 | 允许的引擎 API |
|------|------|----------------|
| 字节读取、size 检查、`base_sha256`、临时文件/rename、删除 | `mobile/src/app/config_store.gd` | `FileAccess`, `DirAccess` |
| BOM/UTF-8/JSON 语法、schema 校验、方向/按键表、覆盖层合并语义、错误对象 | `mobile/src/core/**` | 仅 `JSON`（+ 纯类型） |
| 渲染错误屏 | `mobile/src/ui/error_screen.gd` | `Control`, `DisplayServer`（剪贴板） |

**"绝不写 res://"的机械守卫：**

- `ConfigStore` 的写入路径是常量 `user://config/overrides.json`；`save_overrides()` 开头检查 `begins_with("user://")`，否则返回 `ERR_UNAUTHORIZED`。
- 测试用注入路径时也传 `user://...`；另有一条测试断言默认 `overrides_path().begins_with("user://")`。
- 代码评审清单：`src/` 下任何 `FileAccess.open(..., WRITE)` 的目标必须是 `user://`；Phase 3 不引入任何 `res://` 写入。

### 大小上限

`overrides.json` 是用户可编辑的输入。加一个 `MAX_BYTES := 1_048_576`（1 MiB）：base 9 KB、overlay 正常 < 2 KB；超过 → `file_too_large`，不 JSON 解析。这是对畸形/恶意输入的廉价 DoS 防护（JSON 深层嵌套的递归解析不在本阶段深挖）。

---

## Q6. 动手写 800+ 行之前必须知道的 GDScript 事实

### 类型系统

| 事实 | 实测/文档 | 对本项目的影响 |
|------|-----------|----------------|
| 类型化数组 `Array[ConfigError]`、`Array[Skill]` | ✅ 可用 | 全部用；错误列表/技能列表都强类型 |
| 类型化字典 `Dictionary[String, int]` | ✅ 4.7.2 可用 | 覆盖层白名单、映射表可用 |
| **嵌套类型化集合不允许**（`Dictionary[String, Array[int]]`） | 官方文档明确 disallowed | 覆盖层只能是 `Dictionary[String, Variant]` 或普通 `Dictionary` |
| `String` 与 `StringName` 作为字典键**可互换** | ✅ 实测：`{"a":1}.get(&"a") == 1`，`{"b":1}.has("b") == true` | JSON 解析出的 String 键可以用 `&"arc"` 常量查；不必每个键都转换 |
| `StringName` 是 interned，比较极快 | 官方文档 | 错误码、`kind`、信号名、白名单键用 `StringName`；路径/消息/JSON 文本用 `String` |
| `JSON.stringify` 的 `StringName` 会序列化成普通字符串 | ✅ 实测 | 覆盖层里可以放心用 StringName |
| 整数除法截断：`5 / 2 == 2` | ✅ 实测 | 时间/角度/比例一律写 `float` 字面量（`1.0 / 3.0`） |
| `typeof(1) == TYPE_INT (2)`，`typeof(1.0) == TYPE_FLOAT (3)`，`typeof(true) == TYPE_BOOL (1)` | ✅ 实测 | 数值校验必须接受 INT **和** FLOAT；布尔必须单独拒绝 |
| `float(true) == 1.0`、`float("3.5") == 3.5`、`bool("false") == true` | ✅ 实测 | **所有**校验必须先 `typeof` 再转换；不能直接 `float(v)` |
| `float(null)` / `int(null)` | 运行时错误（"Nonexistent 'float' constructor"），**只中止当前函数**，调用者继续 | `null` 数值必须在转换前拦截，否则错误会被吞成"该函数提前返回" |
| `const` 容器只读 | ✅ `C["a"] = 2` → **解析错误** `Cannot assign a new value to a constant` | `DIRECTION_ALIASES` / `BUTTON_ALIASES` 用 `const` 字典，安全 |
| `JSON` 数字全部解析成 float（`1` → `1.0`） | ✅ 实测 | `schema_version` / `cooldown_ms` 等先确认是数字，再 `int()`；不要 `typeof == TYPE_INT` |
| `str(1.0/3.0)` 只有 14 位有效数字 | ✅ 实测（`0.33333333333333`） | 不要用 `str()` 比较浮点；黄金比较用数值 + 容差 |
| `JSON.stringify(..., "", true, true)` 的 full_precision 给 17 位 | ✅ 实测 | 若 GDScript 要写浮点（本阶段不需要），用 full_precision |
| `String.matchn("tests/*")` 的 `*` **跨 `/`** | ✅ 实测（`tests/unit/x.gd` 命中） | `export_presets.cfg` 的 `exclude_filter="tests/*"` 能递归排除 |
| `@abstract` | 4.7.2 官方 style guide 有示例（引入版本未在本 session 核实） | Phase 4 的 `Detector` / `InputSource` 端口用；Phase 3 用不上 |
| `enum` vs StringName 常量 | GDScript 的 `enum` 是整数常量；字符串枚举只用于 `@export_enum` | 配置词汇（`arc`/`sequence`/`taps`、错误码）用 `const KIND_ARC := &"arc"` 这类 StringName 常量，因为值来自 JSON、要出现在错误消息里；`enum` 只留给未来的内部整数状态。不要为配置字符串造 enum + `from_string()` 双向表——那是第二份会漂移的词汇表 |
| 静态类型 | 官方文档强调"更早发现错误 / 自动补全 / 文档化"；`[CITED: static_typing.html]` | 800+ 行全部标注参数/返回/容器类型；性能不是本阶段的理由（纯逻辑不跑热路径），正确性和可读性是 |

### `class_name` vs `preload`

- `class_name` 注册的是**全局类名**，解析依赖 `.godot/global_script_class_cache.cfg`，该文件由 `--import` 生成。**干净 clone 直接 `--script` 会 `Could not find type`**（实测）。
- `preload("res://...gd")` 在解析期按路径加载，不依赖全局缓存；但如果被 preload 的文件在**类型标注**里用了别的全局类名，仍然会失败（实测 `lab_user.gd` 的 `-> LabFoo`）。
- **结论：** core 用 `class_name`（类型标注需要），`test-core.sh` 固定先 `--import`；测试套件/ reporter 不用 `class_name`，用 `preload`，避免污染全局命名空间、也避免把测试类打进导出包。
- 已实测：`ClassDB.class_exists()` 对 `Geometry/Skill/Step/Pulse/Frame/Hit/Failure/Outcome/PadSample/AppConfig/InputConfig/RumbleConfig/ConfigError/ConfigLoader/ConfigValidator/OverlayMerge/SessionSnapshot/DirectionTable` 全部返回 `false`（4.7.2 无冲突）。`Geometry` 可用；若担心未来版本新增同名全局类，可改名 `CoreGeometry`（本阶段不必）。

### `assert()`：debug-only，且会挂死 runner

官方原文："The assert keyword can be used to check conditions in debug builds. These assertions are ignored in non-debug builds. This means that the expression passed as argument won't be evaluated in a project exported in release mode." `[CITED: docs.godotengine.org/en/4.7/tutorials/scripting/gdscript/gdscript_basics.html#assert-keyword]`

- 编辑器二进制永远是 debug build（`target=editor` 定义 `DEBUG_ENABLED`），所以**本地跑得通的 assert，在 release APK 里会消失**。`[CITED: docs.godotengine.org/en/4.7/engine_details/development/compiling/introduction_to_the_buildsystem.html]`
- 实测：`assert(false, "X")` 打印 `Assertion failed`，中止当前函数；在入口 `_init` 里 → 进程挂死（15s timeout）。
- **规则：** core 里 `assert()` 只能用于"不可能发生"的内部不变量（belt-and-braces），**绝不能**用于配置校验/用户输入/测试断言；测试用 reporter 的 `check()`。

### `@tool`

- `@tool` 只决定脚本能否在编辑器里执行；`--headless --script` 下普通脚本照常跑。
- 但 `--import` 隐含 `--editor`，所以 `@tool` 脚本在导入期有被执行的可能（是否执行取决于有没有节点/资源实例化它）。core 不需要 `@tool`，lint 直接禁止。
- 结论：Phase 3 的 core **零 `@tool`**。

### `--import` 与 `.uid` 边车

- `--import` 是干净 clone 的硬前置（`class_name` 缓存 + 资源导入）。
- 每个新 `.gd` 会生成 `.gd.uid`（Phase 2 决策：提交物，不进 `.gitignore`）。执行顺序：创建/修改 `.gd` → 跑 `--import` → `git add` 包含 `.uid`。
- `.json` 是 Godot 的注册资源扩展名（Phase 2 实测 `ResourceLoader.get_recognized_extensions_for_type("JSON") == ["tres","res","json"]`）；无效 JSON fixture 若放在普通目录会在 `--import` 时刷 ERROR。用 **`mobile/tests/fixtures/.gdignore`** 让导入器忽略整个夹具目录：实测 `--import` 零 ERROR、`FileAccess.get_file_as_bytes()` 仍能读、`DirAccess.get_files_at()` 仍能列。`[VERIFIED: 本机 4.7.2]`
- fixture 目录被 `.gdignore` 后不会被 `all_resources` 打进 PCK；测试脚本（`tests/*.gd`）仍会被扫描，需在 `export_presets.cfg` 的 `exclude_filter` 里加 `tests/*`。

### 其他会咬人的细节

- `JSON.parse_string(text)` 在失败时会 **向 stderr 打一条 ERROR**（`Parse JSON failed...`）；`JSON.new().parse(text)` **不打**，只返回 `Error` 码，配 `get_error_line()` / `get_error_message()`。core 的加载器用后者，避免"纯函数自己写日志"。
- `JSON.new().parse()` 的 `get_error_line()` 是 **0 基**（实测单行输入返回 0）；给人看的消息要 `+1`。
- `JSON.parse_string` 失败返回 `null`；成功解析 `null` 字面量也返回 `null`（`parse()` 返回 OK + `data == null`）。根节点必须检查 `typeof(data) == TYPE_DICTIONARY`。
- `String.split(" ", false)` 会丢弃空字段；Phase 1 的 `.sha256` 解析沿用 `split(" ", false)[0]`。
- `String.begins_with("\uFEFF")` 可用；但 `get_file_as_string` 已经把 BOM 剥了，所以 BOM 检测必须在 bytes 上做。
- `FileAccess.get_sha256(path)` 返回 64 位 hex，可直接用于 `base_sha256`；`FileAccess.get_file_as_bytes` 对不存在文件返回空 `PackedByteArray`（配合 `file_exists` 区分"空文件"与"不存在"）。
- `DirAccess.remove_absolute(path)` 删除文件；不存在时返回错误码（忽略即可）。
- `Error` 的 `OK == 0`；`FileAccess.get_open_error()` 在 `open()` 返回 null 后取具体原因。

---

## Validation Architecture

> 本节回答研究问题 Q7：纯逻辑阶段的验证架构。

### 一条命令

```bash
bash mobile/tools/test-core.sh
```

内部顺序（**顺序即安全属性**，与 `gate-a.sh` 同构）：

1. **`python3 tools/sync_config.py --check`** —— 先证明 `mobile/assets/config/` 副本与唯一真源一致。副本被手改时，测试仍能对着被改过的副本自洽地绿（Phase 1/2 的假绿模式），所以这一步必须是第一步。
2. **`python3 tools/test_lint_core.py`** —— lint 自测（canary 反例）。不需要 Godot。
3. **`python3 tools/lint_core.py mobile/src/core`** —— 真 lint；命中即非零退出。
4. **`python3 tools/gen_geometry_golden.py --check`** —— 黄金夹具是否与 Python 参考实现一致（防止有人改了 Python 的几何而没重新生成）。
5. **`python3 tools/check_config_parity.py`** —— Python 侧对 fixture 语料的 accept/reject 判定；与 Godot 侧共享同一份 `.expect.json`。
6. **`$GODOT --headless --path mobile --import`** —— 带 Phase 2 的有界重试（只对信号终止重试）。
7. **看门狗跑 `res://tests/run_tests.gd`** —— 必须看到 `TESTS_DONE failures=0`。

为什么 lint 在 Godot 之前：lint 是纯文本、毫秒级、零依赖，能在 CI 里独立跑；如果等到 Godot 装好才发现 `Input.`，反馈太慢。为什么黄金 `--check` 在测试之前：它证明夹具没漂移；否则测试可能对着旧夹具自洽地绿。

### Test Framework（测试框架）

| Property | Value |
|----------|-------|
| Framework | 手写 `SceneTree` runner + `RefCounted` reporter（零插件；官方明确 GDScript 无内置测试框架） |
| Config file | 无 |
| Quick run command | `bash mobile/tools/test-core.sh` |
| 直接跑 Godot 套件 | `"$GODOT" --headless --path mobile --script res://tests/run_tests.gd`（必须先 `--import`） |
| 失败判据 | 退出码非零 **或** 输出无 `TESTS_DONE failures=0` 即失败 |

### Phase Requirements → Test Map（需求 → 测试映射）

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|--------------|
| RESIL-03 | core 在无场景树/无手柄下跑完几何与配置测试，返回退出码 | unit + smoke | `bash mobile/tools/test-core.sh` | ❌ Wave 0 |
| RESIL-02 | BOM / 字符串布尔 / null 数值 / `start_angle` 数组 → 结构化错误（path+code+hint）；core 无 `push_error`/`print` | unit + lint | `godot ... res://tests/run_tests.gd` + `python3 tools/lint_core.py` | ❌ Wave 0 |
| INFRA-03 | `src/core/` 出现 `Input.`/`Time.`/`Node`/`FileAccess`/`print(` → 非零 | lint + canary | `python3 tools/lint_core.py mobile/src/core`；`python3 tools/test_lint_core.py` | ❌ Wave 0 |
| DATA-03 | overlay 写 `user://`；base hash 变 → 丢弃 + 提示；不写 `res://` | unit + integration（本地 `user://`） | `res://tests/unit/test_overlay_merge.gd` + `test_config_store.gd` | ❌ Wave 0 |
| （成功标准 2） | 八方向+中心与 Python 差 < 1e-9；`(0,0)→0` | golden vector | `python3 tools/gen_geometry_golden.py --check` + `test_geometry.gd` | ❌ Wave 0 |

### 黄金向量：放哪、谁生成

**几何黄金：** `mobile/tests/fixtures/geometry_golden.json`

- **生成器**：`tools/gen_geometry_golden.py`，`sys.path.insert(0, repo/"desktop")` 后 `from padskills.geometry import ...`（`geometry.py` 只 import `math`，不碰 pygame）。
- 文件内容存**输入与输出**：每个 case 的 `x`、`y`、`expected`，以及 `norm_deg`/`signed_delta`/`angle_diff`/`magnitude` 的用例；再加 `meta.python_geometry_sha256`（对 `geometry.py` 的字节哈希）。
- `--check` 重新生成并逐字节比较；不一致即失败，并打印差异。
- **为什么不放 `shared/`：** 这份夹具的唯一消费者是 GDScript 测试；Python 侧是生成器，不是运行时消费者。放进 `shared/` 会逼出一个"shared → mobile/tests"的同步步骤，等于给一份生成物再造第二份副本。Phase 5 的 `shared/golden_vectors.json`（轨迹回放）确实需要 `shared/` + 同步，因为 Python 生成器与 Godot 回放都要读；那是 Phase 5 的事，Phase 3 不要预建那套机制。
- **测试容差：** `1e-9`（roadmap 要求）；`angle_of` 的 9 个方向实测精确一致，但仍用容差比较，避免 Android libm 的 1 ulp 差异。中心 case 额外断言 `== 0.0`（守卫是精确分支）。

**配置语料：** `mobile/tests/fixtures/configs/{valid,invalid}/*.json` + 同名 `.expect.json`

`invalid/string_bool.json.expect.json` 示例：

```json
{
  "python": "accept",
  "python_note": "bool('false') 为 True，属已知缺陷；GDScript 故意拒绝",
  "godot": "reject",
  "codes": ["bool_expected"],
  "paths": ["skills[0].enabled"],
  "divergence": "string_bool_python_silently_true"
}
```

- GDScript 测试：列目录（`DirAccess.get_files_at`，`.gdignore` 下仍可列，实测）→ **过滤掉 `*.expect.json` 与 `.gdignore`、按文件名排序** → 读 bytes → `ConfigLoader.parse_bytes` → 断言 `ok()` 与 `codes`（顺序无关，按集合比较）与 `paths`。
- Python parity：读同一批 `.json` + `.expect.json`；`valid/*` 必须 `parse_config` 成功；`invalid/*` 必须按 `expect.python` 拒绝（`TypeError`/`ValueError`/`JSONDecodeError` 都算拒绝）；带 `divergence` 的条目单独断言"Python 接受但 GDScript 拒绝"是**已知且已记录**的。
- **额外一条**：对每个 `python: accept` 的 fixture，再跑 `build_detector()`（`detectors.py` 不 import pygame 到模块级，可安全导入），抓 `start_angle` 数组这种"parse 通过、构造检测器才崩"的晚失败。`start_angle_array` 这条应标记为 `"python": "accept_then_detector_reject"`，证明 GDScript 把它提前到校验期。
- **语料最少覆盖：** 四条成功标准指定的 BOM / 字符串布尔 / null 数值 / `start_angle` 数组；再加根节点、空 skills、未知 type、空 steps、缺 direction、未知 direction、max<=min、hold 之和超 max、未知按键、button_mode 非法、modifier 缺 required_button、modifier 不在 options、重复 name、空 rumble pattern、low 越界、input.invert 键/值、backend 非法、JSON 语法错误、多错误（两条独立错误一次收齐）。
- **真实配置必须直接测：** `test_config_loader.gd` 读 `res://assets/config/skills_config.json`（bytes）→ 断言 `ok()` 且 `skills.size() == 5`、名称顺序与 `shared/` 一致。文件缺失时**必须失败而不是 skip**——那说明 `sync_config.py` 没跑，后面所有"配置能加载"的绿灯都是对着空气。

### Wave 0 Gaps（Wave 0 缺口）

- [ ] `mobile/tests/run_tests.gd` + `test_reporter.gd` —— 无头 runner、完成哨兵、崩溃检测
- [ ] `mobile/tests/unit/test_geometry.gd` + `tools/gen_geometry_golden.py` + `fixtures/geometry_golden.json`
- [ ] `mobile/src/core/geometry.gd`
- [ ] `mobile/src/core/domain/*`（Skill/Step/Pulse/InputConfig/RumbleConfig/AppConfig/buttons/direction_table）
- [ ] `mobile/src/core/config/*`（ConfigError/ConfigResult/ConfigLoader/ConfigValidator/OverlayMerge）
- [ ] `mobile/src/app/config_store.gd`
- [ ] `mobile/tests/fixtures/.gdignore` + `configs/{valid,invalid}/*` + `.expect.json`
- [ ] `tools/lint_core.py` + `tools/test_lint_core.py`
- [ ] `tools/check_config_parity.py`
- [ ] `mobile/tools/test-core.sh`
- [ ] `mobile/export_presets.cfg` 的 `exclude_filter` 加 `tests/*`（可选但建议）
- [ ] （建议）`mobile/src/ui/error_screen.gd/.tscn` + headless 场景测试
- [ ] （可选）`.github/workflows/mobile-core.yml`

### Sampling Rate（采样率）

- **每个 task 提交：** `bash mobile/tools/test-core.sh`（预计 < 15 秒；`--import` 在已有 `.godot/` 时 1–2 秒）。
- **每个 wave 合并：** `test-core.sh` + `bash mobile/tools/gate-a.sh`（保证工程仍能导入、PCK 仍含配置与字形、语法仍过）。
- **阶段门：** `test-core.sh` + `gate-a.sh` + `gate-b.sh`（无设备可跑的三道）；Phase 3 不需要真机。

---

## Standard Stack

### Core

| Library / Tool | Version | Purpose | Why Standard |
|----------------|---------|---------|--------------|
| Godot Engine（标准版，非 .NET） | **4.7.2-stable**（`4.7.2.stable.official.ed1daf0bf`） | 运行时 / headless / `--import` | 工程已锁定；Phase 2 已用它导出过签名 APK；禁止用 4.8 打开工程 |
| GDScript 2.0 | 随 4.7.2 | 全部 core / app / tests | 纯 2D、无热路径性能压力；C# 在 Android 上是 experimental 且要第二套工具链 |
| `JSON`（引擎内置类） | 4.7.2 | core 的 JSON 解析 | 唯一允许的"引擎类"例外：纯解析、无 I/O、无环境状态；`JSON.new().parse()` 不写日志 |
| `RefCounted`（引擎内置） | 4.7.2 | core 全部数据/服务对象的基类 | 无场景树生命周期、引用计数、`class_name` 可用；不用 `Resource`（按路径缓存会泄漏可变状态） |
| Python 3（stdlib） | 系统 `python3`（本机 3.9.6；CI 3.12） | lint / 黄金生成器 / parity 脚本 | 仓库已有工具语言；零第三方依赖 |

### Supporting

| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| `bash` 3.2+ | 系统 | `test-core.sh` / 看门狗 | 所有闸门入口 |
| `git` | 系统 | 提交 `.gd.uid` / fixtures / 研究产物 | 每次 task 结束 |
| `uv` | 0.9.5 | **不需要**（Phase 3 无新 Python 依赖） | 只在需要 `desktop` 的 Python 环境时；几何/配置工具不依赖 `uv` |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| 手写 `SceneTree` runner | GUT 9.7.1 / gdUnit4 6.2.3 | 官方文档明确 GDScript 无内置框架，GUT/GdUnit4 都成熟；但它们引入 addon、配置文件、导出排除、与引擎版本的耦合（GUT 9.6→9.7 就是适配 4.7 的 breaking change）。本阶段 ~200 条纯 `RefCounted` 断言，手写 60 行更划算。**触发切换条件**：需要 mock、场景级输入回放、或 CI 需要 JUnit XML 时再切 GUT ≥ 9.7.0 |
| Python lint | GDScript lint / grep | GDScript 版要自己写注释/字符串剥离器且 CI 需先装 Godot；grep 会被中文 docstring 里的 `Input` 误伤。Python 原型已验证 0 假阳性/0 漏报（在 canary 范围内） |
| `FileAccess.get_file_as_bytes` | `get_file_as_string` | **不可用**：会静默剥 BOM，BOM 用例永远测不出来 |
| `JSON.new().parse` | `JSON.parse_string` | `parse_string` 失败时向 stderr 打 ERROR；纯层不该写日志，且拿不到错误行 |
| `DirAccess.rename_absolute` | 直接覆盖写目标文件 | 写到一半被杀会留下半损坏文件；temp+rename 是 DATA-03/Phase 8 的原子写基础 |
| `fposmod` | `fmod` / `%` | `%` 对 float 是解析错误；`fmod` 保留负号，与 Python 的 floor-mod 语义不同 |

**Installation:** 本阶段不安装任何新包。Godot 已在 `$HOME/Applications/Godot-4.7.2.app`；Python 工具只用 stdlib。

**Version verification（本机实测）:**

```bash
"$HOME/Applications/Godot-4.7.2.app/Contents/MacOS/Godot" --version
# 4.7.2.stable.official.ed1daf0bf
```

---

## Package Legitimacy Audit

**本阶段不通过 npm / PyPI / crates 安装任何运行时依赖，也不新增 Python 第三方包。** 唯一的外部可执行物是已存在的 Godot 4.7.2-stable（Phase 2 已用 SHA-512 钉死）。`tools/*.py` 只用 Python 标准库（`json`、`hashlib`、`pathlib`、`tempfile`、`argparse`、`re`、`sys`）。

| Package | Registry | Age | Downloads | Source Repo | Verdict | Disposition |
|---------|----------|-----|-----------|-------------|---------|-------------|
| （无新增包） | — | — | — | — | — | — |

**Packages removed due to [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

> 不要因为"测试更方便"而引入 `pytest`、`gdtoolkit`（GDScript 解析器）、`gdlint` 或任何 GDScript parser 包。本阶段的 lint 用自写状态机；引入第三方解析器会让"零依赖闸门"多一个供应链面。

---

## Architecture Patterns

### System Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ 仓库根                                                                        │
│                                                                              │
│  shared/skills_config.json ──(Phase 1 sync)──▶ mobile/assets/config/*.json    │
│                                                          │                   │
│  desktop/padskills/geometry.py ──▶ tools/gen_geometry_golden.py ──▶ fixtures  │
│  desktop/padskills/config.py   ──▶ tools/check_config_parity.py ──┐           │
│                                                                   │           │
│  mobile/tests/fixtures/configs/*.json + *.expect.json ◀───────────┘           │
│         ▲  (同一份语料，Python 与 GDScript 各判一次)                            │
└─────────┼────────────────────────────────────────────────────────────────────┘
          │
          │  bash mobile/tools/test-core.sh
          ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│ 闸门 0  python3 tools/test_lint_core.py        （canary 自测，无 Godot）       │
│ 闸门 1  python3 tools/lint_core.py src/core    （五条硬规则 + 扩展规则）        │
│ 闸门 2  python3 tools/gen_geometry_golden.py --check                          │
│ 闸门 3  python3 tools/check_config_parity.py                                  │
│ 闸门 4  godot --headless --path mobile --import   （有界重试）                  │
│ 闸门 5  看门狗 + godot --headless --path mobile --script res://tests/run_tests.gd
│         必须看到 TESTS_DONE failures=0；否则失败（rc=0 也可能是解析错误）        │
└──────────────────────────────────────────────────────────────────────────────┘
          │
          ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│ mobile/src/                                                                  │
│                                                                              │
│  core/  （零环境状态；lint 强制）                                              │
│   ├─ geometry.gd            fposmod / signed_delta / angle_of / magnitude     │
│   ├─ domain/                Skill Step Pulse InputConfig RumbleConfig         │
│   │                         AppConfig buttons direction_table                 │
│   └─ config/                ConfigError ConfigResult ConfigLoader             │
│                             ConfigValidator OverlayMerge                      │
│                                                                              │
│  app/config_store.gd        FileAccess / DirAccess / get_sha256 / rename      │
│  ui/error_screen.gd（建议） 只渲染 ConfigResult                                │
└──────────────────────────────────────────────────────────────────────────────┘
          │
          ▼
   user://config/overrides.json（稀疏；base_sha256 不匹配 → 丢弃 + 提示）
   res://assets/config/skills_config.json（只读；APK 内）
```

### Recommended Project Structure

```text
mobile/
├── project.godot
├── export_presets.cfg              # exclude_filter 追加 tests/*
├── assets/config/                  # 生成物，Phase 1 已就位
├── src/
│   ├── core/                       # ★ 零环境状态；lint 只扫这里
│   │   ├── geometry.gd
│   │   ├── domain/
│   │   │   ├── buttons.gd          # CANONICAL_BUTTONS / BUTTON_ALIASES / canonical()
│   │   │   ├── direction_table.gd  # DIRECTION_ALIASES / resolve()
│   │   │   ├── pulse.gd
│   │   │   ├── step.gd
│   │   │   ├── skill.gd
│   │   │   ├── input_config.gd
│   │   │   ├── rumble_config.gd
│   │   │   └── app_config.gd
│   │   └── config/
│   │       ├── config_error.gd
│   │       ├── config_result.gd
│   │       ├── config_loader.gd    # parse_bytes / parse_text
│   │       ├── config_validator.gd # validate(Variant) -> ConfigResult
│   │       └── overlay_merge.gd    # 纯合并/丢弃语义
│   ├── app/
│   │   └── config_store.gd         # 唯一允许 FileAccess/DirAccess 的 config 入口
│   ├── ui/                         # （建议）最小错误屏
│   │   └── error_screen.gd/.tscn
│   └── smoke/                      # Phase 2 的验收面板，Phase 3 不动
├── tests/
│   ├── run_tests.gd                # extends SceneTree; TESTS_DONE 哨兵
│   ├── test_reporter.gd            # check/eq_float/complete
│   ├── unit/
│   │   ├── test_geometry.gd
│   │   ├── test_config_loader.gd
│   │   ├── test_config_validator.gd
│   │   ├── test_overlay_merge.gd
│   │   └── test_config_store.gd
│   └── fixtures/                   # .gdignore：不被导入、不进 PCK
│       ├── geometry_golden.json
│       └── configs/{valid,invalid}/*.json + *.expect.json
└── docs/
    └── CORE.md                     # 边界规则 + 如何跑测试 + 如何加 fixture

tools/                              # 仓库级，不放进 mobile/（Godot 会扫描工程内所有文件）
├── lint_core.py
├── test_lint_core.py
├── gen_geometry_golden.py
└── check_config_parity.py
```

**Rationale：**

- `tools/` 在仓库根：Godot 会导入工程根下的每个文件；Python 脚本放进 `mobile/` 会变成 PCK 里的非资源 blob，还会污染导入器。这与 Phase 1 的 `sync_config.py` 位置一致。
- `tests/` 在工程内：`res://tests/...` 才能在 `--path mobile` 下被 `preload`/`FileAccess` 找到。
- `fixtures/` 加 `.gdignore`：无效 JSON 不会在 `--import` 时刷 ERROR，也不会进 PCK；`FileAccess` 仍可读。
- `src/app/config_store.gd` 是 Phase 3 唯一的 app 层文件：DATA-03 需要一个真实写入者；把它留在 `src/app/` 也把 `FileAccess` 挡在 core 之外。

### Pattern 1: 纯函数 + 数据类型，服务对象只用于有状态的东西

**What:** `Geometry`、`DirectionTable`、`Buttons`、`ConfigValidator` 全部 `static func`；`ConfigError`/`ConfigResult`/`Skill` 等是 `RefCounted` 数据对象。没有单例、没有 autoload。
**When to use:** 所有无状态逻辑。
**Why:** 静态函数可以被测试直接调用，不构造对象；`ConfigValidator.validate(data)` 的输入输出完全由参数决定，回放/并行都安全。

```gdscript
class_name ConfigValidator
extends RefCounted

static func validate(data: Variant, source_path := "") -> ConfigResult:
	var result := ConfigResult.new()
	result.source_path = source_path
	if typeof(data) != TYPE_DICTIONARY:
		result.errors.append(ConfigError.new(
			"$", &"root_not_object",
			"配置文件根节点必须是 JSON 对象，收到 %s" % type_string(typeof(data)),
			"把整个文件包在 { } 里；最外层不能是数组或 null。"))
		return result
	# ...
	return result
```

### Pattern 2: 校验器"收集"而不是"抛出"

**What:** 每个 `_validate_*` 接收同一个 `Array[ConfigError]`（GDScript 数组是引用类型），失败就 `append` 后继续；只有"依赖前提不成立"时才跳过子树。
**When to use:** 所有用户可编辑输入的校验。
**Why:** 一次给全所有错误，错误屏才有意义；`SystemExit` 一条一条给是 Python 的缺陷，不要复制。

```gdscript
static func _validate_skill(raw: Variant, index: int, out: Array[ConfigError]) -> Skill:
	var path := "skills[%d]" % index
	if typeof(raw) != TYPE_DICTIONARY:
		out.append(ConfigError.new(path, &"skill_not_object",
			"每个动作必须是 JSON 对象", "用 { } 包住一个动作"))
		return null
	var dict: Dictionary = raw
	var kind := str(dict.get("type", "")).strip_edges().to_lower()
	if kind not in ["arc", "sequence", "taps"]:
		out.append(ConfigError.new(path + ".type", &"skill_type_invalid",
			"type 必须是 'arc'、'sequence' 或 'taps'，收到 %s" % JSON.stringify(dict.get("type")),
			"改成三种之一；拼写和大小写都要对。"))
		return null                       # 只跳过依赖 type 的子树，外层继续下一个 skill
	# ...
	return null
```

### Pattern 3: 跨语言夹具 = 同一份语料，两侧各判一次

**What:** `mobile/tests/fixtures/configs/**` 同时被 GDScript 测试与 `tools/check_config_parity.py` 读取；`.expect.json` 是唯一契约。
**When to use:** 任何"Python 是参考实现、GDScript 是移植"的地方。
**Why:** 不需要 Godot 调 Python 或反过来；两边读同一批文件，各自断言，CI 里可以只跑 Python 半边。新增 fixture 时只写一次。

```text
invalid/string_bool.json         ← 输入
invalid/string_bool.json.expect.json
{
  "python": "accept",
  "python_note": "bool('false') 为 True，已知缺陷",
  "godot": "reject",
  "codes": ["bool_expected"],
  "paths": ["skills[0].enabled"],
  "divergence": "string_bool_python_silently_true"
}
```

### Anti-Patterns to Avoid

- **用 `assert()` 做校验或测试断言：** release 被剥离；headless 下失败会挂死进程。
- **只判 `$?`：** 解析错误/编译失败返回 0；必须看 `TESTS_DONE failures=0`。
- **用 `get_file_as_string()` 读配置：** 静默剥 BOM，BOM 用例假绿。
- **用 `JSON.parse_string()`：** 失败时打 ERROR，拿不到行号；纯层不该有日志。
- **用 `%` 处理浮点角度：** 解析错误；用 `fposmod`。
- **用 `Vector2.angle()`：** +X 起、y-down，与项目 0°=上 相反。
- **把 `params` 阈值放进 `user://` 覆盖层：** 历史数据不可比；覆盖层只放 `enabled`/`required_button`/`button_mode`。
- **把 config 的 `FileAccess` 留在 core：** lint 会红，且无法在纯回放里测。
- **把测试 fixture 放在会被 Godot 导入的目录：** 无效 JSON 会在 `--import` 刷 ERROR；用 `.gdignore`。
- **在 `tests/` 里给测试类加 `class_name`：** 污染全局命名空间，且可能被打进包；用 `preload`。

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON 解析 | 自己写 JSON parser / 用正则拆 | `JSON.new().parse()` | 已内置；错误码/行号/消息都有；自己写会引入一整个 bug 面 |
| SHA-256 | 自己实现哈希 | `FileAccess.get_sha256(path)` | 内置、返回 64 位 hex；只在 app 层用 |
| 原子写 | 直接覆盖目标文件 | temp 文件 + `flush` + `close` + `DirAccess.rename_absolute` | 半写文件是 Phase 8 的明确失败模式；rename 覆盖已实测 |
| 角度归一化 | `while` 循环加减 360 | `fposmod` | 对任意大/负值都正确，且与 Python `%` 语义一致 |
| 测试框架 | 自己写 mock/runner 生态 | 当前：60 行 reporter；未来需要 mock/JUnit 时切 GUT ≥ 9.7.0 | 本阶段断言是纯函数循环，不需要框架特性 |
| 注释/字符串剥离 | 用 grep 直接扫 token | 自写 20 行字符状态机（Python） | grep 会被中文 docstring 里的 `Input` 误伤；原型已验证 |
| GDScript 语法检查 | 自己写 parser | `--check-only` **只用于报告**，真正闸门靠 runner 的 preload/编译失败 + 哨兵 | `--check-only` 对解析错误返回 0，不能单独当判据 |
| 方向名 → 角度 | 重写一套别名表 | 逐字复制 `DIRECTION_ALIASES`（47 条） | 配置里已经用了中文/英文/斜向/数字混写；少一条就是"某个动作起手不认" |

---

## Common Pitfalls

### P1: 解析错误 / 编译失败返回退出码 0
**What goes wrong:** `--script` 指向一个有语法错误或 `class_name` 未解析的脚本，Godot 打印 `SCRIPT ERROR`，进程退出 **0**。CI 绿，测试没跑。
**Why:** `--script` 的加载失败路径不设置退出码；只有脚本自己 `quit(n)` 才设置。
**How to avoid:** 输出必须包含 `TESTS_DONE failures=0`；外壳 `grep -q` 判哨兵，不只看 `$?`。
**Warning signs:** 日志里有 `SCRIPT ERROR` / `Parse Error` / `Failed to load script`，但 `$?` 是 0。
`[VERIFIED: 本机多次复现]`

### P2: 运行时错误只中止当前函数，返回值看起来正常
**What goes wrong:** 一个 `-> int` 的套件函数内部 `null.foo()`，调用者收到 `0`；runner 报"0 failures"。
**Why:** GDScript 没有异常；运行时错误中止当前调用帧，调用者继续。
**How to avoid:** reporter 的 `complete()` 标记；套件没 complete 即失败。
`[VERIFIED: 本机实测 `abort_return.gd`]`

### P3: 入口函数错误 / assert 失败 → 挂死
**What goes wrong:** `_init` 里一个错误或 `assert(false)` 让 `quit()` 永远执行不到；本地卡住，CI 超时。
**How to avoid:** 看门狗（bash 后台或 Python `subprocess.run(timeout=...)`）；测试里不用 `assert`。
`[VERIFIED: 15s timeout, rc=124]`

### P4: `FileAccess.get_file_as_string()` 静默剥 BOM
**What goes wrong:** BOM fixture 用字符串 API 读 → BOM 消失 → 校验器看到合法 JSON → "BOM → 错误"的断言永远绿。
**Why:** 引擎的字符串读取按 UTF-8 解码并跳过 BOM；`get_file_as_bytes()` 保留原始字节（实测 `EF BB BF`）。
**How to avoid:** 加载器/测试一律走 bytes；BOM 在 bytes 上检测。
`[VERIFIED: 本机 4.7.2]`

### P5: `JSON.parse_string()` 会写 stderr
**What goes wrong:** 一个"纯"加载器在坏 JSON 上打 `ERROR: Parse JSON failed...`，污染日志，且拿不到行号/消息。
**How to avoid:** `JSON.new().parse(text)` + `get_error_line()` + `get_error_message()`。
`[VERIFIED: 本机对照]`

### P6: `class_name` 在 `--import` 前不可解析
**What goes wrong:** 干净 clone 直接 `--script`，报 `Could not find type`，随后级联成运行时错误 + 挂死。
**How to avoid:** `test-core.sh` 固定先 `--import`；复用 Phase 2 的有界重试（字体导入偶发 SIGSEGV）。
`[VERIFIED: 本机 fresh2 工程]`

### P7: 浮点 `%` 是解析错误；`fmod` 与 Python 的 `%` 不同
**What goes wrong:** 直译 `angle % 360.0` 直接编译失败；换成 `fmod` 后负角度保持负值，`left` 变 `-90`。
**How to avoid:** `fposmod`；黄金表覆盖 `-90 → 270`。
`[VERIFIED: 本机]`

### P8: `signed_delta` 的端点被"修正"
**What goes wrong:** 有人看到注释写 `(-180,180]`，把公式改成返回 +180；`sd(0,180)` 从 -180 变 +180。
**How to avoid:** 黄金表固化 `sd(0,180) == -180`；注释改成真实区间。
`[VERIFIED: Python 实测]`

### P9: `Vector2.angle()` 的坐标系
**What goes wrong:** `up` 得到 `-π/2`，再 norm 成 270°；所有"上"变"左"。
**How to avoid:** 只允许 `atan2(x, -y) + rad_to_deg + fposmod`；lint 可以加一条 `Vector2.*angle` 规则（可选）。
`[VERIFIED: 本机 `Vector2(0,-1).angle() = -1.570796...`]`

### P10: 类型强转的静默兜底
**What goes wrong:** `float(true)=1.0`、`float("3.5")=3.5`、`bool("false")=true`；`float(null)` 则抛错并中止当前函数。
**How to avoid:** 每个字段先 `typeof` 检查；数值接受 `TYPE_INT|TYPE_FLOAT`，布尔只接受 `TYPE_BOOL`，字符串只接受 `TYPE_STRING`。
`[VERIFIED: 本机 coercion 测试]`

### P11: JSON 整数变成 float
**What goes wrong:** `schema_version: 1` 解析后 `typeof == TYPE_FLOAT`；用 `typeof == TYPE_INT` 判断会永远失败。
**How to avoid:** 数值统一接受 INT/FLOAT；`int(v)` 前确认是数字且是整数值。
`[VERIFIED: 本机]`

### P12: 测试 fixture 被 Godot 导入
**What goes wrong:** 无效 JSON 在 `--import` 时刷 ERROR（甚至可能影响导入退出行为）；fixture 被打进 PCK。
**How to avoid:** `mobile/tests/fixtures/.gdignore`；实测 `--import` 零 ERROR、`FileAccess` 仍可读、`DirAccess` 仍可列。
`[VERIFIED: 本机 gdignore lab]`

### P13: `user://` 路径用了中文工程名
**What goes wrong:** 桌面开发路径是 `.../app_userdata/FIFA 花式动作练习器`（带空格/中文）；脚本和日志里难看，且未来改设置会搬数据。
**How to avoid:** Phase 3 决定 `use_custom_user_dir=true` + `custom_user_dir_name="FifaSkillTrainer"`；发布后不得再改。
`[VERIFIED: 本机真实工程 probe]`

### P14: 把 `res://` 当可写
**What goes wrong:** 编辑器里能写，APK 里失败；或者测试在 `--path` 下写成功，掩盖了发布态错误。
**How to avoid:** `ConfigStore` 的写路径常量必须是 `user://`，并在 `save_overrides()` 入口做前缀检查；测试断言默认路径。
`[CITED: docs.godotengine.org/en/4.7/tutorials/io/data_paths.html]`

### P15: `--headless --script` 不带 `--path`
**What goes wrong:** 在仓库根跑，`res://` 变成 cwd，`user://` 变成 `[unnamed project]`；测试读到错误的配置或污染共享目录。
**How to avoid:** 所有命令固定 `--path "$repo_root/mobile"`。
`[VERIFIED: 本机 bare lab]`

### P16: 用 `timeout` 命令做看门狗
**What goes wrong:** macOS 默认没有 GNU `timeout`；干净机器上脚本直接 `command not found`。
**How to avoid:** bash 后台看门狗（见 Q1）或 Python `subprocess.run(timeout=...)`。
`[ASSUMED: 本机有，但 macOS 不自带]`

---

## Code Examples

> 以下除标注"仅示意"外，关键行为都在本机 4.7.2-stable 上验证过。完整几何实现见 §Q3，`ConfigError`/`ConfigResult` 见 §Q4。

### 1. `ConfigLoader`：从 bytes 入口，BOM 在解码前拦截

```gdscript
# mobile/src/core/config/config_loader.gd
class_name ConfigLoader
extends RefCounted

## 配置加载的唯一入口。core 不读文件：调用者（ConfigStore / 测试）传 bytes。
## 使用 JSON.new().parse() 而不是 JSON.parse_string()：后者失败时会向 stderr 打 ERROR。

static func parse_bytes(bytes: PackedByteArray, source_path := "") -> ConfigResult:
	if bytes.size() >= 3 and bytes[0] == 0xEF and bytes[1] == 0xBB and bytes[2] == 0xBF:
		var r := ConfigResult.new()
		r.source_path = source_path
		r.errors.append(ConfigError.new(
			"$", &"bom_detected",
			"配置文件开头有 UTF-8 BOM（EF BB BF）",
			"用编辑器另存为「UTF-8（无 BOM）」；BOM 会让 JSON 解析失败。"))
		return r
	if bytes.is_empty():
		var r2 := ConfigResult.new()
		r2.source_path = source_path
		r2.errors.append(ConfigError.new(
			"$", &"file_empty", "配置文件是空的", "确认路径正确，并写入至少一个 skills 数组。"))
		return r2
	var text := bytes.get_string_from_utf8()
	if text.is_empty():
		var r3 := ConfigResult.new()
		r3.source_path = source_path
		r3.errors.append(ConfigError.new(
			"$", &"invalid_utf8", "配置文件不是合法的 UTF-8", "用编辑器另存为 UTF-8。"))
		return r3
	return parse_text(text, source_path)


static func parse_text(text: String, source_path := "") -> ConfigResult:
	if text.begins_with("\uFEFF"):          # 防御：parse_text 的直接调用者
		var r := ConfigResult.new()
		r.source_path = source_path
		r.errors.append(ConfigError.new(
			"$", &"bom_detected",
			"配置文件开头有 UTF-8 BOM（U+FEFF）",
			"用编辑器另存为「UTF-8（无 BOM）」。"))
		return r
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		var r := ConfigResult.new()
		r.source_path = source_path
		r.errors.append(ConfigError.new(
			"$", &"json_syntax_error",
			"JSON 语法错误（第 %d 行）：%s" % [json.get_error_line() + 1, json.get_error_message()],
			"JSON 不支持 // 注释，也不允许最后一个元素后面多写逗号。"))
		return r
	return ConfigValidator.validate(json.data, source_path)
```

配套的 `DecodeResult`（`decode_bytes` 的返回类型）与 `_fatal`：

```gdscript
class_name DecodeResult
extends RefCounted
var data: Variant = null      # 解析成功时的 Dictionary；失败时 null
var error: ConfigError = null # 失败时非 null


# ConfigStore 内部的小工具（不对外）
func _fatal(code: StringName, message: String) -> ConfigResult:
	var r := ConfigResult.new()
	r.source_path = _base_path
	r.errors.append(ConfigError.new("$", code, message, "检查文件是否存在、是否可读。"))
	return r
```

> `decode_bytes()` 就是 `parse_bytes()` 去掉最后一行 `return ConfigValidator.validate(...)`：BOM/空文件/UTF-8/JSON 语法失败时把 `ConfigError` 放进 `DecodeResult.error`；成功时 `data` 是原始 `Dictionary`。`ConfigStore` 需要原始字典做 overlay 合并，所以不能直接用 `parse_bytes` 的"已校验"结果。

### 2. `OverlayMerge`：纯合并 / 丢弃语义

```gdscript
# mobile/src/core/config/overlay_merge.gd
class_name OverlayMerge
extends RefCounted

const SCHEMA_VERSION := 1
const ALLOWED_KEYS := [&"enabled", &"required_button", &"button_mode"]


static func merge(base: Dictionary, overlay: Dictionary,
		current_base_sha256: String) -> OverlayResult:
	var result := OverlayResult.new()
	result.data = base.duplicate(true)       # 绝不修改调用者的 base

	var schema = overlay.get("schema_version")
	if typeof(schema) != TYPE_INT and typeof(schema) != TYPE_FLOAT:
		return result._discard(&"overlay_schema_invalid",
			"自定义设置缺少有效的 schema_version，已恢复默认。")
	if int(schema) > SCHEMA_VERSION:
		return result._discard(&"overlay_schema_too_new",
			"自定义设置来自更新的版本，已恢复默认。")

	var hash_value = overlay.get("base_sha256")
	if typeof(hash_value) != TYPE_STRING or \
			String(hash_value).to_lower() != current_base_sha256.to_lower():
		return result._discard(&"overlay_base_changed",
			"配置已更新，已丢弃自定义按键设置。")

	var skills = overlay.get("skills")
	if typeof(skills) != TYPE_DICTIONARY:
		return result._discard(&"overlay_schema_invalid",
			"自定义设置的 skills 必须是对象，已恢复默认。")

	var by_name := {}
	for skill in result.data.get("skills", []):
		if typeof(skill) == TYPE_DICTIONARY and skill.has("name"):
			by_name[str(skill["name"])] = skill

	for skill_name in skills:
		var target = by_name.get(String(skill_name))
		if target == null:
			result.warnings.append(ConfigError.new(
				"skills." + String(skill_name), &"overlay_skill_unknown",
				"自定义设置里的动作 %s 在当前配置中不存在，已忽略。" % skill_name,
				"删除这条自定义设置，或确认动作名没有被改过。",
				ConfigError.SEVERITY_WARNING))
			continue
		var patch = skills[skill_name]
		if typeof(patch) != TYPE_DICTIONARY:
			continue
		for key in patch:
			if StringName(key) not in ALLOWED_KEYS:
				result.warnings.append(ConfigError.new(
					"skills[%s].%s" % [skill_name, key], &"overlay_key_unknown",
					"自定义设置的字段 %s 不受支持，已忽略。" % key,
					"覆盖层只允许 enabled / required_button / button_mode。",
					ConfigError.SEVERITY_WARNING))
				continue
			target[String(key)] = patch[key]
			result.applied = true
	return result
```

（`OverlayResult._discard()` 是 12 行的小方法：设置 `discarded_reason`、`notice`、`applied=false`，返回 self。）

### 3. `ConfigStore`：唯一允许 I/O 的 config 入口

```gdscript
# mobile/src/app/config_store.gd
class_name ConfigStore
extends RefCounted

const BASE_PATH := "res://assets/config/skills_config.json"
const OVERRIDES_DIR := "user://config"
const OVERRIDES_PATH := "user://config/overrides.json"
const TEMP_PATH := "user://config/overrides.json.tmp"
const MAX_BYTES := 1_048_576

var _base_path: String
var _overrides_path: String

func _init(base_path := BASE_PATH, overrides_path := OVERRIDES_PATH) -> void:
	_base_path = base_path
	_overrides_path = overrides_path


func overrides_path() -> String:
	return _overrides_path


func load_config() -> ConfigResult:
	if not _base_path.begins_with("res://") and not _base_path.begins_with("user://"):
		return _fatal(&"file_read_error", "配置路径不合法：%s" % _base_path)
	if not FileAccess.file_exists(_base_path):
		return _fatal(&"file_missing", "找不到配置：%s" % _base_path)
	var base_bytes := FileAccess.get_file_as_bytes(_base_path)
	if base_bytes.size() > MAX_BYTES:
		return _fatal(&"file_too_large", "配置文件超过 1 MiB，拒绝加载。")
	var base_hash := FileAccess.get_sha256(_base_path)

	# 1) 先解码 base（只解码，不校验），拿到原始 Dictionary 供合并
	var base_decoded := ConfigLoader.decode_bytes(base_bytes, _base_path)
	if base_decoded.data == null:
		var r := ConfigResult.new()
		r.source_path = _base_path
		r.errors.append(base_decoded.error)
		return r
	var base_dict: Dictionary = base_decoded.data

	# 2) 覆盖层（可选）
	var overlay_bytes := PackedByteArray()
	var notice := ""
	if FileAccess.file_exists(_overrides_path):
		var raw := FileAccess.get_file_as_bytes(_overrides_path)
		if raw.size() <= MAX_BYTES:
			var parsed := ConfigLoader.decode_bytes(raw, _overrides_path)
			if parsed.data != null and typeof(parsed.data) == TYPE_DICTIONARY:
				var merged := OverlayMerge.merge(base_dict, parsed.data, base_hash)
				base_dict = merged.data
				notice = merged.notice
				if merged.discarded_reason != &"":
					DirAccess.remove_absolute(_overrides_path)   # 只提示一次
			else:
				notice = "自定义设置已损坏，已恢复默认。"
				DirAccess.remove_absolute(_overrides_path)
		else:
			notice = "自定义设置文件过大，已忽略。"
			DirAccess.remove_absolute(_overrides_path)

	# 3) 合并后的数据再做完整校验
	var result := ConfigValidator.validate(base_dict, _base_path)
	result.notice = notice
	return result
```

`decode_bytes()` 返回 `{data, error}`；`parse_bytes()` 是 `decode_bytes + validate` 的便捷包装。这样"合并前需要原始字典"与"直接加载需要校验"两种用法都不重复解析。

### 4. `test-core.sh` 骨架（顺序即安全属性）

```bash
#!/usr/bin/env bash
# 纯核心闸门：lint → 黄金 → Python parity → import → Godot 测试 → 哨兵
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
godot="${GODOT_BIN:-$HOME/Applications/Godot-4.7.2.app/Contents/MacOS/Godot}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# 第一步必须是配置同步校验：副本被手改时，测试会对着被改过的副本自洽地绿（假绿）。
python3 "$repo_root/tools/sync_config.py" --check
python3 "$repo_root/tools/test_lint_core.py"
python3 "$repo_root/tools/lint_core.py" "$repo_root/mobile/src/core"
python3 "$repo_root/tools/gen_geometry_golden.py" --check
python3 "$repo_root/tools/check_config_parity.py"

# --import：干净 clone 的硬前置；只对信号终止做有界重试（Phase 2 已知字体导入偶发 SIGSEGV）
import_rc=1
for attempt in 1 2 3; do
	set +e
	"$godot" --headless --path "$repo_root/mobile" --import >"$tmp/import.log" 2>&1
	import_rc=$?
	set -e
	if [ "$import_rc" -eq 0 ]; then
		break
	fi
	if [ "$import_rc" -lt 128 ]; then
		tail -n 20 "$tmp/import.log" >&2
		exit 1
	fi
	echo "  · 导入被信号终止（rc=$import_rc），第 ${attempt}/3 次" >&2
done
if [ "$import_rc" -ne 0 ]; then
	echo "✗ 连续 3 次导入被信号终止" >&2
	exit 1
fi

# 看门狗 + 哨兵
run_with_timeout() {
	local secs="$1" out="$2"; shift 2
	"$@" >"$out" 2>&1 &
	local pid=$!
	( sleep "$secs"; kill -TERM "$pid" 2>/dev/null; sleep 2; kill -KILL "$pid" 2>/dev/null ) &
	local watcher=$!
	local rc=0
	wait "$pid" || rc=$?
	kill "$watcher" 2>/dev/null || true
	wait "$watcher" 2>/dev/null || true
	return "$rc"
}

if ! run_with_timeout 180 "$tmp/tests.log" \
		"$godot" --headless --path "$repo_root/mobile" --script res://tests/run_tests.gd; then
	cat "$tmp/tests.log"; echo "✗ 核心测试进程失败/超时" >&2; exit 1
fi
cat "$tmp/tests.log"
grep -q "TESTS_DONE failures=0" "$tmp/tests.log" || {
	echo "✗ 没有 TESTS_DONE failures=0（解析/编译/运行时错误都可能 rc=0）" >&2
	exit 1
}
echo "✓ 核心闸门通过：lint / 黄金 / parity / 几何+配置测试"
```

### 5. `lint_core.py` 的剥离器核心（原型已验证）

```python
#!/usr/bin/env python3
"""扫描 GDScript：先剥离注释/字符串，再匹配禁用 token。"""
import re

FORBIDDEN = [
    ("input_singleton", re.compile(r"\bInput\s*\.")),
    ("time_singleton", re.compile(r"\bTime\s*\.")),
    ("node_type", re.compile(r"\bNode\b")),
    ("fileaccess_io", re.compile(r"\bFileAccess\b")),
    ("logging", re.compile(
        r"\b(?:print|prints|printt|printerr|print_rich|print_debug|push_error|push_warning)\s*\(")),
    ("os_singleton", re.compile(r"\bOS\s*\.")),
    ("engine_singleton", re.compile(r"\bEngine\s*\.")),
    ("display_server", re.compile(r"\bDisplayServer\b")),
    ("tree_access", re.compile(r"\bget_tree\s*\(")),
    ("scene_tree_type", re.compile(r"\bSceneTree\b")),
    ("resource_loader", re.compile(r"\bResourceLoader\b")),
    ("resource_type", re.compile(r"\bResource\b")),
    ("tool_annotation", re.compile(r"^\s*@tool\b")),
    ("outer_layer_dep", re.compile(
        r"(?:preload|load)\s*\(\s*\"res://src/(?:platform|ui|app)/")),
]


def strip_code(text: str) -> str:
    """把注释与字符串替换成空格，保留换行与列位置。"""
    out, i, n = [], 0, len(text)
    while i < n:
        ch = text[i]
        if ch == "#":                                  # 行注释
            while i < n and text[i] != "\n":
                out.append(" "); i += 1
            continue
        if ch in ('"', "'"):                           # 普通/三引号/raw/StringName/NodePath
            delim = ch
            triple = text.startswith(delim * 3, i)
            width = 3 if triple else 1
            out.extend(" " * width); i += width
            while i < n:
                if text.startswith(delim * width, i):
                    out.extend(" " * width); i += width; break
                if text[i] == "\\" and i + 1 < n:
                    out.extend("  "); i += 2; continue
                out.append("\n" if text[i] == "\n" else " "); i += 1
            continue
        out.append(ch); i += 1
    return "".join(out)
```

**原型实测：** clean 样例（禁用 token 全在注释/字符串/三引号/raw string 里）→ `LINT_HITS=0`、rc=0；dirty 样例（真实 `Input.`/`Time.`/`Node`/`FileAccess`/`print`/`push_error`）→ 6 命中、rc=1。`[VERIFIED: lab 原型]`

### 6. `gen_geometry_golden.py` 的生成核心

```python
#!/usr/bin/env python3
import hashlib, json, math, sys
from pathlib import Path

repo = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(repo / "desktop"))
from padskills.geometry import norm_deg, signed_delta, angle_diff, angle_of, magnitude  # noqa: E402

S = 1.0 / math.sqrt(2.0)
CASES = [
    ("center", 0.0, 0.0), ("up", 0.0, -1.0), ("upright", S, -S),
    ("right", 1.0, 0.0), ("downright", S, S), ("down", 0.0, 1.0),
    ("downleft", -S, S), ("left", -1.0, 0.0), ("upleft", -S, -S),
]
payload = {
    "schema_version": 1,
    "source": "desktop/padskills/geometry.py",
    "meta": {
        "python_geometry_sha256": hashlib.sha256(
            (repo / "desktop/padskills/geometry.py").read_bytes()).hexdigest(),
    },
    "angle_of": [
        {"name": name, "x": x, "y": y, "expected": angle_of(x, y)}
        for name, x, y in CASES
    ],
    "norm_deg": [{"input": v, "expected": norm_deg(v)} for v in (-90.0, 360.0, -0.0, -1e-12, 720.5)],
    "signed_delta": [
        {"from": a, "to": b, "expected": signed_delta(a, b)}
        for a, b in ((0, 180), (0, 181), (350, 10), (10, 350), (270, 0), (0, 270), (45, 45))
    ],
    "magnitude": [{"x": x, "y": y, "expected": magnitude(x, y)} for _, x, y in CASES],
}
text = json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
# --check: 与 mobile/tests/fixtures/geometry_golden.json 比较；默认写入。
```

### 7. `project.godot` 的 `user://` 定名（建议，Phase 3 决定）

```ini
; mobile/project.godot 追加到 [application]
; 必须在任何用户数据产生之前决定：Phase 9 的覆盖安装依赖 user:// 位置不变。
config/use_custom_user_dir=true
config/custom_user_dir_name="FifaSkillTrainer"
```

### 8. `export_presets.cfg` 排除测试

```ini
; 现有：exclude_filter="build/*,tools/*.png"
; 追加 tests/*（Godot 的过滤器按 String.matchn 语义，* 跨 /；matchn 已实测，
; 导出器是否同源未单独验证 —— 用 --export-pack 后断言 tests/run_tests.gd 不在包里兜底）
exclude_filter="build/*,tools/*.png,tests/*"
```

---

## Plan Decomposition Suggestion

依赖关系（建议 4 个 plan，按波次）：

| Wave | Plan | Deliverable | 依赖 |
|------|------|-------------|------|
| 1 | `03-01` 无头 runner + 几何 | `run_tests.gd` + `test_reporter.gd` + `geometry.gd` + `test_geometry.gd` + `gen_geometry_golden.py` + golden fixture | 无（但需要 `--import`） |
| 2 | `03-02` 配置域 + 校验 | `domain/*` + `ConfigError`/`ConfigResult`/`ConfigLoader`/`ConfigValidator` + fixture 语料 + `check_config_parity.py` | Wave 1 的 runner |
| 3 | `03-03` 覆盖层 + store | `OverlayMerge` + `ConfigStore` + `test_overlay_merge.gd` + `test_config_store.gd` | Wave 2 的 `ConfigResult`/`ConfigValidator` |
| 4 | `03-04` lint + 总闸 + 文档 | `lint_core.py` + `test_lint_core.py` + `test-core.sh` + `export_presets.cfg` 排除 + `mobile/docs/CORE.md` + `mobile/README.md` 入口 + （建议）错误屏 | Wave 1–3（lint 可以在 Wave 1 就先落，越早越好） |

**建议提前 lint：** 如果等到 Wave 4 才加 lint，Wave 1–3 写下的 core 代码可能已经带进 `print`/`Time`；把 `lint_core.py` + `test_lint_core.py` 放在 Wave 1 的第一个 task，之后每个 wave 结束都跑一次。这样 lint 是"从第一天就存在的边界"，不是"最后补的检查"。

**每个 plan 的验收：** 必须能独立跑 `bash mobile/tools/test-core.sh`（Wave 1 时脚本可以只有几何套件；Wave 2 加配置；Wave 3 加 overlay；Wave 4 加 lint）。不要让 `test-core.sh` 在中间波次变成"跑不了的半成品"。

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| GUT / GdUnit4 作为默认测试框架 | 手写 `SceneTree` runner + reporter | 本项目 D3 决策（2026-11-04） | 零 addon、零导出排除、与既有 `check()` 文化一致；代价是要自己处理退出码/崩溃/看门狗 |
| `JSON.parse_string()` 一把梭 | `JSON.new().parse()` + 错误行/消息 | 4.x 一直如此，只是文档不强调 | 纯层不写日志、能给出"第 N 行"的错误 |
| 直接用 `FileAccess.get_file_as_string()` 读配置 | `get_file_as_bytes()` + 自己处理 BOM | 本项目实测（4.7.2） | BOM 可被检测；代价是所有加载器入口改成 bytes |
| Python 的 `%` 直译 | `fposmod` | GDScript 对 float `%` 是解析错误 | 角度语义与 Python floor-mod 一致 |
| `assert()` 做校验 | 返回 `ConfigError` 列表 | `assert` 在 release 被剥离（官方明确） | 安卓用户能看到错误屏，而不是静默/崩溃 |
| 配置错误只给第一条（`SystemExit`） | 收集全部独立错误 | 本项目 RESIL-02 | 错误屏一次列全；校验器需要"依赖子树跳过"逻辑 |

**Deprecated / 不要用：**

- `OS.set_exit_code()`：4.7.2 不存在；用 `SceneTree.quit(code)`。
- `MainLoop` 做测试 runner：没有 `quit()`，无法设非零退出码。
- `--check-only` 作为唯一语法闸门：解析错误也返回 0。
- `Resource` 作为 core 数据对象：按路径缓存，`load()` 两次返回同一实例，可变状态跨测试泄漏。
- `Vector2.angle()` / `Vector2.rotated()` 推角度：坐标系与项目约定相反。
- `Timer` / `Time` 进 core：时钟必须由参数传入。

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `use_custom_user_dir=true` + `custom_user_dir_name="FifaSkillTrainer"` 不影响 Android 的 `user://` 沙箱路径 | §Q5 | 若影响，Android 上的用户数据位置与桌面不同；Phase 4 真机确认；发布后不可再改 |
| A2 | 对数值字符串（`"250"`）采取严格拒绝，而不是像 Python 一样强转 | §Q4 | 会让一份 Python 能跑的配置在移动端报错；但两端语义一致，且 shared 配置全是真数字 |
| A3 | 对未知 `direction` 采取拒绝，而不是像 Python 一样静默当 `any` | §Q4 | 可能拒绝一份"能跑但语义错"的旧配置；shared 配置只有 `any`，风险低 |
| A4 | `DirAccess.rename_absolute` 在 Android 上原子覆盖 | §Q5 | 若目标存在时 rename 失败，overlay 写入会失败；Phase 4 真机验证，失败则加"先删目标再 rename"的回退（牺牲原子性） |
| A5 | `@tool` 脚本在 `--import` 期间可能被执行 | §Q2 | 只影响 lint 的 `tool_annotation` 规则的必要性；core 不用 `@tool`，风险低 |
| A6 | `.gdignore` 目录里的 fixture 不会被 `all_resources` 打进 PCK；`exclude_filter="tests/*"` 能递归排除测试脚本 | §Q7 | 若仍被打进，APK 多几 KB；用 `--export-pack` + `FileAccess.file_exists("res://tests/run_tests.gd") == false` 的包内断言兜底 |
| A7 | `FileAccess.get_string_from_utf8()` 对非法 UTF-8 返回空串（可据此报 `invalid_utf8`） | §Q5 | 若返回替换字符而非空串，非法 UTF-8 会进入 JSON 解析并报语法错误；错误码不同但仍是结构化错误 |
| A8 | Phase 3 应包含一个最小错误屏，而不只是 `to_text()` | §Q4 | 若推迟到 Phase 7，RESIL-02 只能"部分闭合"；建议至少交付 `to_text()` 的机械证明 |
| A9 | CI 采用 Godot-on-Linux 全量跑，而不是只跑 Python 半边 | §Validation Architecture | 需要 Linux 版 Godot 的 SHA-512 与 170 MB 下载；若不做，GDScript 测试只在本地跑 |
| A10 | `geometry.gd` 的全局类名 `Geometry` 不会与未来 Godot 版本冲突 | §Q6 | 4.7.2 实测无冲突；锁定版本内无风险 |

**如果这张表为空：** 不是——本阶段有多处产品/平台判断，必须在计划阶段或真机上确认。

---

## Open Questions

1. **CI 策略：Godot-on-Linux 全量，还是 Python-only？**
   - What we know: Phase 1 D-09 把 CI 定为"唯一不可绕过的闸门"；Phase 1 deferred 明确说"移动端 GDScript 测试的 CI 归 Phase 2 之后"。
   - What's unclear: Linux 版 Godot 4.7.2 的 SHA-512 尚未记录（Phase 2 只记了 macOS 的）；CI 首次 `--import` 可能撞上字体导入的偶发 SIGSEGV（有界重试已能覆盖）。
   - Recommendation: **做全量**：新增 `.github/workflows/mobile-core.yml`，下载 Linux 版 Godot 4.7.2（SHA-512 从官方 `SHA512-SUMS.txt` 取并钉死），只调用 `bash mobile/tools/test-core.sh`（不在 CI 里重复任何检查逻辑）。若计划阶段要压缩范围，退而求其次：CI 只跑 `lint_core.py` + `gen_geometry_golden.py --check` + `check_config_parity.py`（纯 Python、零下载），GDScript 套件本地跑，并在 `mobile/README.md` 写明这个缺口。

2. **严格性策略（A2/A3）是否要用户确认？**
   - What we know: 成功标准只点名 BOM / 字符串布尔 / null 数值 / `start_angle` 数组。
   - What's unclear: 数值字符串、未知 `direction`、静默 clamp 字段是否一并严格化。
   - Recommendation: 严格化 + `.expect.json` 显式记录 divergence；如果用户更想"与 Python 完全一致的接受面"，则撤回 A2/A3，只保留四条点名修复。

3. **错误屏是否进 Phase 3？**
   - What we know: RESIL-02 映射到 Phase 3；成功标准 3 只要求"结构化错误列表，可原样渲染成错误屏"。
   - Recommendation: 交付 `ConfigResult.to_text()` + headless 测试（必须）；再加一个最小 `error_screen.gd/.tscn` + 场景实例化测试（建议）。完整视觉留 Phase 7。

4. **`user://` 定名（A1）现在改还是等 Phase 4？**
   - Recommendation: 现在改。Phase 3 还没有任何用户数据，改动零成本；发布后再改会丢数据。

5. **`direction_name()` 是否移植？**
   - What we know: Python 用它做调试/UI 的"前/前右/右…"标签；Phase 3 的校验错误只需要 `direction_unknown`，不需要反向名。
   - Recommendation: 不移植。等 Phase 5/7 真正需要时再加，附黄金用例。

6. **`params` 里的未知键是否警告？**
   - What we know: Python 把未知 params 留在 `Skill.params`（开放 schema）；架构研究建议保持开放。
   - Recommendation: 不警告（保持开放 schema，未来检测器参数不需要改加载器）；只对**已知键的类型**严格校验。

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| Godot 4.7.2-stable | `--import` / `--script` / 测试 | ✓ | `4.7.2.stable.official.ed1daf0bf`（`$HOME/Applications/Godot-4.7.2.app/Contents/MacOS/Godot`） | 无（版本锁死） |
| Python 3 | lint / 黄金 / parity | ✓ | 系统 `python3` 3.9.6 | `uv run --project desktop python`（3.12） |
| `bash` | `test-core.sh` / 看门狗 | ✓ | macOS 自带 3.2 | 无 |
| `git` | 提交 `.uid` / fixtures / 研究 | ✓ | 系统 | 无 |
| GNU `timeout` | 看门狗 | ✓（本机） | coreutils | **bash 后台看门狗**（推荐；macOS 不保证有） |
| `.godot/` 导入缓存 | `class_name` / 测试 | ✓（当前工程已有） | — | 干净 clone 先 `--import`（有界重试） |
| Android 设备 / 手柄 | **不需要** | — | — | Phase 3 全部断言无设备可跑 |
| `uv` | 不需要 | ✓（0.9.5） | — | — |

**Missing dependencies with no fallback:** none（Godot 已装；Python 已装）。

**Missing dependencies with fallback:**
- GNU `timeout` 不保证：用 bash 后台看门狗。
- 干净 clone 的 `.godot/` 不存在：`--import` 是硬前置，不是可选步骤。

---

## Security Domain

> 本项目是纯本地、离线、单用户工具；没有认证、会话、网络、数据库。`security_enforcement` 未在 `.planning/config.json` 中显式关闭，故本节保留。

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | 无账号、无登录 |
| V3 Session Management | no | 无会话 |
| V4 Access Control | no | 单用户本地应用；`user://` 由 Android 沙箱隔离 |
| V5 Input Validation | **yes** | 手写 `ConfigValidator`：严格 `typeof`、范围检查、枚举白名单、大小上限、BOM/UTF-8 检查；不使用 `eval`；不把用户字符串拼进文件路径 |
| V6 Cryptography | **no（但有一条哈希）** | 不手写加密；`base_sha256` 用 `FileAccess.get_sha256`（内置 SHA-256），仅作**完整性/漂移检测**，不是签名，不构成安全边界 |

### Known Threat Patterns for Godot + JSON config

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| 畸形 JSON / 深层嵌套 → 解析崩溃或栈溢出 | Denial of Service | 1 MiB 大小上限；结构化错误；不用 `assert`；`JSON.new().parse()` 返回错误码而非抛异常 |
| BOM / 编码混淆 → 静默接受错误配置 | Tampering | bytes 入口 + `EF BB BF` 显式检测 + `invalid_utf8` 错误 |
| 字符串布尔 / null 数值 / 数组冒充标量 → 静默错误语义或晚崩溃 | Tampering | 严格 `typeof` + 专门的 `start_angle_not_scalar`；错误带 `json_path` |
| 用户编辑 `user://config/overrides.json` 注入任意键 | Tampering | 白名单键（`enabled`/`required_button`/`button_mode`）+ 合并后重新完整校验 + `schema_version`/`base_sha256` |
| 覆盖层指向旧 base → 阈值/按键语义漂移 | Tampering | `base_sha256` 不匹配即整体丢弃 + 中文提示 + 删除文件（只提示一次） |
| 尝试写 `res://`（导出后只读） | Denial of Service / 数据丢失 | 写路径常量 `user://` + 前缀守卫 `ERR_UNAUTHORIZED`；lint/评审禁止 `res://` 写入 |
| 超长 skill name / 错误文本撑爆 UI | Denial of Service（视觉） | 错误屏对 `message`/`skill name` 做长度截断（Phase 7 的排版细节） |
| 本地用户同时改 base 与 overlay | Repudiation | 无安全边界；`base_sha256` 只保证"base 变了就丢 overlay"，不防本地篡改 |

**关键结论：** 本阶段的安全工作 = **输入校验的完整性**，不是加密/认证。`ConfigValidator` 是唯一的安全相关组件；它必须"永远不会因为输入而崩溃"，并且"永远给出可操作的中文错误"。

---

## Sources

### Primary (HIGH confidence)

- **本机 Godot 4.7.2-stable 实测**（`$HOME/Applications/Godot-4.7.2.app/Contents/MacOS/Godot`）：
  - `--headless --script` + `SceneTree._init/_initialize` + `quit(0/1/7)` 退出码
  - 非 `SceneTree` 脚本 / 入口运行时错误 / `assert` 失败 → 挂死（timeout 124）
  - 解析错误 / `class_name` 未解析 / 依赖编译失败 → **退出码 0**
  - 运行时错误只中止当前函数；`-> int` 崩溃返回 0
  - `class_name` 在 `--import` 前不可解析；`preload` 单独可用；`--import` 后成功
  - `FileAccess.get_file_as_string()` 剥 BOM；`get_file_as_bytes()` 保留 `EF BB BF`
  - `JSON.parse_string()` 打 ERROR；`JSON.new().parse()` 静默、有 `get_error_line()/get_error_message()`
  - JSON 数字 → float（`1` → `1.0`）；`JSON.stringify` 中文字符串不转义、StringName 序列化为字符串
  - `fposmod` vs `fmod` vs `%`（float `%` 是解析错误）；`atan2(x,-y)` 9 方向表
  - `Vector2.angle()` = `-π/2`（up）
  - `float(true)=1.0`、`float("3.5")=3.5`、`bool("false")=true`、`float(null)` 运行错误
  - `String`/`StringName` 字典键可互换；`const` 字典元素赋值是解析错误
  - `DirAccess.rename_absolute` 覆盖已存在目标（macOS）
  - `.gdignore` 目录：`--import` 零 ERROR，`FileAccess`/`DirAccess` 仍可读写
  - `String.matchn("tests/*")` 跨 `/`
  - 真实 mobile 工程的 `user://` 路径、`res://` 配置 9117 字节、sha256 `bccf123a…eee9`
- **`desktop/padskills/geometry.py:23-54`**（本 session Read）——角度约定与公式的规格书
- **`desktop/padskills/config.py:489-801`**（本 session Read）——校验规则与错误消息的规格书
- **`desktop/padskills/input_source.py:35-74`**（本 session Read）——`CANONICAL_BUTTONS` / `BUTTON_ALIASES` / `canonical_button`
- **Python 3 实测**：`parse_config` 对 `string_bool`（接受）、`null_number`（TypeError）、`start_angle_array`（接受）、`string_number`（接受）、BOM（`json.loads(str)` 拒绝）的行为；`signed_delta` 端点值

### Secondary (MEDIUM confidence)

- `[CITED: docs.godotengine.org/en/4.7/tutorials/editor/command_line_tutorial.html]` —— `--script` 必须继承 `SceneTree`/`MainLoop`；`--path`；`--check-only`；`--import` 隐含 `--editor --quit`
- `[CITED: docs.godotengine.org/en/4.7/classes/class_scenetree.html]` —— `quit(exit_code)`，0..125
- `[CITED: docs.godotengine.org/en/4.7/tutorials/scripting/gdscript/gdscript_basics.html#assert-keyword]` —— assert 在 non-debug 被忽略、表达式不求值
- `[CITED: docs.godotengine.org/en/4.7/engine_details/development/compiling/introduction_to_the_buildsystem.html]` —— `target=editor` 定义 `DEBUG_ENABLED`，`template_release` 不定义
- `[CITED: docs.godotengine.org/en/4.7/tutorials/io/data_paths.html]` + `[CITED: class_os.html]` —— `user://` 保证可写、桌面路径、移动端私有
- `[CITED: docs.godotengine.org/en/4.7/classes/class_diraccess.html]` —— `rename_absolute` 覆盖已存在目标
- `[CITED: docs.godotengine.org/en/4.7/classes/class_json.html]` —— `JSON.new().parse()` 错误行/消息；`parse_string()` 无错误详情
- `[CITED: docs.godotengine.org/en/4.7/tutorials/scripting/gdscript/static_typing.html]` —— 类型化数组/字典；嵌套类型化集合不允许
- `[CITED: docs.godotengine.org/en/4.7/classes/class_stringname.html]` —— interned / 比较快
- `[CITED: docs.godotengine.org/en/4.7/tutorials/ui/creating_applications.html]` —— GDScript 无内置单元测试框架，GUT/GdUnit4 是社区插件
- `[CITED: docs.godotengine.org/en/4.7/tutorials/scripting/gdscript/gdscript_styleguide.html]` —— `class_name`/`extends` 顺序、两空行、`@abstract`
- `[CITED: docs.godotengine.org/en/4.7/tutorials/export/exporting_projects.html]` —— `export_filter` / include / exclude 过滤器的语义

### Tertiary (LOW confidence)

- Android 上 `DirAccess.rename_absolute` 与 `user://` 的具体路径 —— 只有 POSIX 语义与官方"沙箱目录"描述，无真机验证（Phase 4 补）。
- `@tool` 在 `--import` 期间是否真的执行 —— 取决于是否有节点/资源实例化它；本阶段只用"禁止"来规避，不依赖具体行为。

---

## Metadata

**Confidence breakdown:**

- **Standard stack:** HIGH —— 版本与二进制路径已实测；无新增依赖。
- **Headless runner / exit codes / failure modes:** HIGH —— 所有关键失败模式都在本机复现（rc=0 假绿、挂死、崩溃被当成 0、assert 中止）。
- **Geometry parity:** HIGH —— 9 方向 + 边界在 Python/GDScript 双跑；`signed_delta` 端点已实测。
- **Config validation rules:** HIGH —— Python 源码逐条读过；四种坏输入的行为已实测。
- **Config strictness decisions:** MEDIUM —— A2/A3 是产品判断，需要确认。
- **Overlay / `user://`:** HIGH（macOS 本地机制）/ MEDIUM（Android 原子覆盖与沙箱路径）。
- **Architecture lint:** HIGH —— 原型在 clean/dirty canary 上分别 0/6 命中，rc 正确。
- **CI:** LOW —— 未实际搭建 Godot-on-Linux CI；Linux 资产 SHA-512 未取。

**Research date:** 2026-11-05
**Valid until:** 2026-12-05（30 天；Godot 版本锁死，API 事实不会漂移；Android 文件系统行为需 Phase 4 真机确认）

