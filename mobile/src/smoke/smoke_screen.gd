extends Control

## 验收面板。这一屏要一次性证明三件事：
##   1) 最长中文串与 ° ± → ✓ ✗ 都能显示（成功标准 2，不是豆腐块）
##   2) res://assets/config/ 的配置真的在包里，且 SKILL_COUNT = 5（成功标准 3）
##   3) 蓝牙手柄的原始轴读数在动（成功标准 4）
##
## Phase 3 之后这一屏会被真正的首屏替换。在此之前它是唯一的验收面板，
## 因此刻意不做样式、不接业务逻辑 —— 可以整体删除，不要把 UI 逻辑长在这里。

## 文案取自 desktop/padskills/gui.py 的 _ADVICE["wrong_start"]：用仓库里真实存在的
## 最长中文串，比编一句更长的假字符串有意义 —— 它同时验证真实字符集与排版长度。
const LONGEST := "起点错了：注意从左摇杆朝向的哪个方位起手。"

## 符号清单钉住成功标准 2 里写死的那五个符号。减号必须是键盘上的 ASCII 连字符
## （U+002D），不能是数学减号 U+2212：后者不在字体子集的字符清单里，会造成
## 「字体闸门绿、屏幕豆腐」的假绿（02-PATTERNS 设计冲突 3）。
const SYMBOLS := "° ± → ✓ ✗   0°  45°  -1.000"

@onready var _header: Label = %Header
@onready var _axes: Label = %Axes

var _skill_count := -1
var _device_ids: Array[int] = []

func _ready() -> void:
	# 默认每帧 flush 一次累积输入；关掉它只是为了在轴上「看得见」。
	# 真正的采样契约（事件时间戳、亚帧精度）归 Phase 4，这里不建立任何输入契约。
	Input.use_accumulated_input = false
	Input.joy_connection_changed.connect(_on_joy_changed)
	_load_config()
	_refresh_axes()

func _load_config() -> void:
	var path := "res://assets/config/skills_config.json"
	if not FileAccess.file_exists(path):
		_header.text = "配置缺失: " + path
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		_skill_count = (parsed.get("skills", []) as Array).size()
	_header.text = "SKILL_COUNT = %d\n%s\n%s" % [_skill_count, LONGEST, SYMBOLS]

func _on_joy_changed(_device: int, _connected: bool) -> void:
	_device_ids = Input.get_connected_joypads()
	_refresh_axes()

func _process(_delta: float) -> void:
	# 每帧重读是故意的：成功标准 4 只要求「看得见在动」，事件驱动的采样归 Phase 4。
	_refresh_axes()

func _refresh_axes() -> void:
	_device_ids = Input.get_connected_joypads()
	if _device_ids.is_empty():
		# 安卓蓝牙手柄可能要先按一下键才出现在设备列表里（RESEARCH P14，标 ASSUMED）。
		# 这句话无论真假都该有，成本为零。
		_axes.text = "没有检测到手柄：先按手柄上任意键唤醒"
		return
	var out: PackedStringArray = []
	for d in _device_ids:
		out.append("#%d  %s" % [d, Input.get_joy_name(d)])
		for axis in range(8):
			out.append("  axis %d = %+.3f" % [axis, Input.get_joy_axis(d, axis as JoyAxis)])
		# 按钮通道也要证明：Phase 4 的修饰键（A/B/X/Y、LB/RB）全部依赖它。
		# 只列「当前按下的索引」而不是全部 32 个，屏幕才不会被按钮刷屏。
		# 这里刻意用 ASCII 文案，避免给字体子集新增字形、把字形闸门弄红。
		var pressed: PackedStringArray = []
		for btn in range(21):
			if Input.is_joy_button_pressed(d, btn as JoyButton):
				pressed.append(str(btn))
		out.append("  buttons: " + (", ".join(pressed) if pressed.size() > 0 else "-"))
	out.append("")
	out.append("  stick/trigger -> axis; A/B/X/Y/LB/RB -> buttons")
	_axes.text = "\n".join(out)
