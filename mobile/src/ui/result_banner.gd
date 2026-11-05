extends Control

## 结果横幅：只显示运行时交给它的那一条判定，不重拼任何句子。
##
## 「一次尝试只展示一次」的**唯一实现**是静态函数 `accepts()`：序号单调递增，
## 只有更大的 `seq` 才会覆盖当前显示。`clear()` 刻意**不重置** `_shown_seq` ——
## 序号是整场会话的时间轴，重置会让刚结束的旧结果重播一遍。
##
## 文案来源纪律：成功时 `%Reason` 是 `Outcome.detail`（检测器给的 `Hit.summary`），
## 失败时是 `Outcome.message`（`Failure.message`）。本文件不把「太快 / 太慢 /
## 保持不够」重新组织成自己的句子 —— 那会让「与桌面版一致」悄悄变成「与作者的理解
## 一致」。颜色只是附加信号，`✓` / `✗` 与「做对了 / 没做对」才是可判读的主路径。
##
## 节点缓存必须落在 `practice_screen.tscn` 的 `%ResultBanner` 之下：`%Title` 与
## `%Reason` 都是 `unique_name_in_owner = true` 的真实子节点。缺失时 `@onready`
## 求值为 null，判定与原因都到不了屏幕 —— 这不是可降级的路径。

const HOLD_SECONDS := 1.5
const SUCCESS_COLOR := Color("#66BB6A")
const FAILURE_COLOR := Color("#EF5350")

@onready var _title: Label = %Title
@onready var _reason: Label = %Reason

## 已显示过的最大序号。只增不减，`clear()` 也不回退。
var _shown_seq: int = 0
## 剩余停留秒数；> 0 时 `_process` 递减，到 0 清空文本（不做自动推进）。
var _remaining: float = 0.0


func _ready() -> void:
	pass


## 单调去重谓词。测试可直接 `preload` 本脚本后调用静态函数，不需要实例化 Node。
static func accepts(shown_seq: int, seq: int) -> bool:
	return seq > shown_seq


## 显示一条判定。只做「序号去重 + 取字段」，不做任何业务判断或字符串拼接。
func show_outcome(outcome: Outcome) -> void:
	if not accepts(_shown_seq, outcome.seq):
		return
	_shown_seq = outcome.seq
	if outcome.ok:
		_title.text = "✓ 做对了"
		_reason.text = outcome.detail
		_title.add_theme_color_override("font_color", SUCCESS_COLOR)
	else:
		_title.text = "✗ 没做对"
		_reason.text = outcome.message
		_title.add_theme_color_override("font_color", FAILURE_COLOR)
	_remaining = HOLD_SECONDS


func _process(delta: float) -> void:
	if _remaining <= 0.0:
		return
	_remaining -= delta
	if _remaining > 0.0:
		return
	_remaining = 0.0
	_title.text = ""
	_reason.text = ""


## 进入练习 / 重新 setup 时清空显示。**不重置 `_shown_seq`**：序号单调，
## 重置会让上一场的旧结果在下一次进入时重播。
func clear() -> void:
	_title.text = ""
	_reason.text = ""
	_remaining = 0.0
