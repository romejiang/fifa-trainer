class_name PadSampler
extends Node

## 手柄采样的薄壳：**本文件是唯一允许出现 `Input.` / `Time.` 的采样代码**。
## 所有状态与判定逻辑都在 `PadStateBuffer`（纯 RefCounted，零引擎依赖）里，
## 无头测试只碰缓冲，不构造本节点。
##
## 两条通道写同一份状态，因此天然幂等：
##   * `_input` —— `InputEventJoypadMotion` / `InputEventJoypadButton`，到达即打戳；
##   * `_process` —— 每帧轮询一次按钮做「对账」，补上事件通道没送来的边沿。
## 事件先到，轮询读到同一个值 → 不产生重复边沿；事件没到，轮询把边沿补上，
## 只是时间戳晚到帧边界。真机上哪条通道在供数由 `events_motion` / `events_button`
## / `poll_edges` 三个计数器记录，不靠猜。
##
## 每条事件在写入缓冲之后**同时**交给 `InputLog`：按键边沿全记，轴按 16 ms / 0.02
## 节流。日志写入失败不会影响本函数 —— `InputLog` 自己吞掉全部 I/O 错误。
##
## **必须用 `_input`，不能用 GUI 之后才到达的那条输入回调**：Control 会先吃事件，
## 判定输入不能被 UI 吃掉。也**不要**在 `_input` 里把事件标记为已处理 —— 那会挡掉
## 别的节点。节点必须在场景树里（`_input` 只在树内被调用）。
##
## 线程：`_input` 由安卓 JNI 回调同步派发，**是否在主线程尚未验证**（M3 真机项）。
## `input_thread_id` / `process_thread_id` 就是给 M3 取证的；若实测跨线程，在本文件
## 加一把 Mutex 即可，core 完全不受影响。
##
## **轴值的唯一来源是 `InputEventJoypadMotion`，这是一条硬约束（INPUT-05）**：
## 轮询 `Input.get_joy_axis` 只保留帧内最后一个值，同帧「右 → 左 → 右」会把中间的
## 「左」永久吞掉。因此 `_process` 只对账**按钮**，不读、也不补轴值。
## 它的失败模式必须被当成显式停止条件：若某台设备根本不派发 motion 事件，
## `events_motion` 会恒为 0、`_axes` 恒为初值，探针与校准都无法进行。此时
## **不是**在设备层偷偷加一条轮询轴的回退路径（那直接违反 INPUT-05），而是：
## 04-05 的引导屏在探针/校准状态下经历 ≥ 60 帧仍未见到 `events_motion` 增长时，
## 必须显示「没有收到摇杆事件（events_motion = 0）…」并把验收判失败；
## 04-07 的 D0 把它写成停止条件 —— 不允许用「设备看起来正常」替代。
##
## `_ready()` 会在连好连接信号后主动 emit 一次当前设备列表。组合根必须在
## `add_child()` **之前** connect，否则错过这次初始 emit；之后再用
## `connected_devices()` 主动播种一次。两次都走 `bind()` 的幂等分支。

signal device_list_changed(devices: Array)

var buffer := PadStateBuffer.new()
## D6 的线程取证：`_input` 与 `_process` 各写一次，值不同就是跨线程。
var input_thread_id: int = 0
var process_thread_id: int = 0
## 轴日志节流状态：键是 "<device>:<axis>"，值是 {"v": float, "t": int}。
## 键里带设备号：换手柄后同号轴的值不能继承上一只手柄的基准。只记录**真的写进
## 日志**的样本，被跳过的样本不刷新基准（见 `InputLog.axis_should_log`）。
var _log_axes: Dictionary = {}


func _ready() -> void:
	Input.set_use_accumulated_input(false)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	device_list_changed.emit(Input.get_connected_joypads())


## 绑定设备。同一个设备重复绑定是 no-op（不清状态、不丢边沿），逻辑全部在缓冲里。
func bind(device_id: int) -> void:
	buffer.bind_device(device_id)


## 断开。同样只委托缓冲，薄壳不写第二份清状态逻辑。
func unbind() -> void:
	buffer.bind_device(-1)


func device_name() -> String:
	if buffer.device < 0:
		return ""
	return Input.get_joy_name(buffer.device)


## GUID 是不透明字符串（官方说找不到时返回空串）：调用方在空串时退回设备名。
func device_guid() -> String:
	if buffer.device < 0:
		return ""
	return Input.get_joy_guid(buffer.device)


## 组合根用它主动播种，不依赖信号时序（蓝牙手柄可能要先按一下键才出现）。
func connected_devices() -> Array:
	return Input.get_connected_joypads()


func _input(event: InputEvent) -> void:
	input_thread_id = OS.get_thread_caller_id()
	# 只做形状转换，不判定、不吞事件。缓冲自己负责设备过滤与越界拒绝。
	if event is InputEventJoypadMotion:
		var motion_ms := _now_ms()
		buffer.apply_event({
			"device": event.device,
			"t_ms": motion_ms,
			"kind": "motion",
			"axis": int(event.axis),
			"value": event.axis_value,
		})
		# 日志在状态写入之后：即使缓冲拒收（设备不匹配 / 越界），原始事件仍值得记录。
		_log_axis(int(motion_ms), event)
	elif event is InputEventJoypadButton:
		var button_ms := _now_ms()
		buffer.apply_event({
			"device": event.device,
			"t_ms": button_ms,
			"kind": "button",
			"index": int(event.button_index),
			"pressed": event.pressed,
		})
		# 按钮边沿永不节流：按下 / 松开各一条，测试者能逐条核对。
		var index := int(event.button_index)
		var canonical := JoyButtonMap.name_of(index)
		if canonical.is_empty():
			canonical = "-"
		InputLog.button(int(button_ms), event.device, index, canonical, event.pressed)


## 轴日志节流：同一设备同一根轴，|Δ| < 0.02 且距上次写入 < 16 ms 时跳过。
## 跳过的样本不写日志、也不更新基准 —— 下一次比较仍以最后一条真的写进日志的值为准。
func _log_axis(t_ms: int, event: InputEventJoypadMotion) -> void:
	var axis := int(event.axis)
	var key := "%d:%d" % [event.device, axis]
	var value := event.axis_value
	if _log_axes.has(key):
		var last: Dictionary = _log_axes[key]
		if not InputLog.axis_should_log(float(last["v"]), int(last["t"]), value, t_ms):
			return
	_log_axes[key] = {"v": value, "t": t_ms}
	InputLog.axis(t_ms, event.device, axis, value)


func _process(_delta: float) -> void:
	process_thread_id = OS.get_thread_caller_id()
	if buffer.device < 0:
		return
	var polled := {}
	for index in PadStateBuffer.MAX_BUTTON:
		polled[index] = Input.is_joy_button_pressed(buffer.device, index as JoyButton)
	buffer.reconcile(_now_ms(), polled)


func _now_ms() -> float:
	return Time.get_ticks_usec() / 1000.0


func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	device_list_changed.emit(Input.get_connected_joypads())
