class_name DirectionTable
extends RefCounted

## 方向写法归一：把配置里能写的中文、英文、带分隔符形态与角度数字，全部变成 [0, 360) 的角度。
##
## 逐条照抄 desktop/padskills/config.py:103-113（`DIRECTION_ALIASES` 42 条：英文 22 条、
## 中文 20 条）。条目数由 mobile/tests/unit/test_vocabulary.gd 硬断言 —— 少一条就是
## 「某个动作的起手方向不认」，多一条就是自创词汇表，两端语义会漂移。
##
## 角度约定沿用 Geometry：0° = 上，90° = 右，180° = 下，270° = 左，范围 [0, 360)。
##
## 失败值是 null，不是异常（同 Buttons.canonical）：core 不抛、不打印、不 push_error。
## 调用方拿 null 生成 direction_unknown 的 ConfigError。
##
## 刻意不移植 direction_name()（角度 → 中文方向名）：Phase 3 的校验错误只需要
## direction_unknown，反向名等真正需要时再加，并附黄金用例。

const ALIASES := {
	"up": 0.0, "forward": 0.0, "fwd": 0.0, "front": 0.0, "north": 0.0,
	"前": 0.0, "上": 0.0, "正前": 0.0, "前方": 0.0,
	"upright": 45.0, "forwardright": 45.0, "前右": 45.0, "右上": 45.0,
	"right": 90.0, "east": 90.0, "右": 90.0, "正右": 90.0,
	"downright": 135.0, "backright": 135.0, "后右": 135.0, "右下": 135.0,
	"down": 180.0, "back": 180.0, "backward": 180.0, "south": 180.0,
	"rear": 180.0, "后": 180.0, "下": 180.0, "正后": 180.0, "后方": 180.0,
	"downleft": 225.0, "backleft": 225.0, "后左": 225.0, "左下": 225.0,
	"left": 270.0, "west": 270.0, "左": 270.0, "正左": 270.0,
	"upleft": 315.0, "forwardleft": 315.0, "前左": 315.0, "左上": 315.0,
}


## 成功返回 float 角度 [0, 360)，失败返回 null。
static func resolve(value: Variant) -> Variant:
	# 布尔先挡掉。GDScript 的 bool 不是 int 的子类，但 float(true) == 1.0 依然成立；
	# 靠类型强转兜底会让 `"direction": true` 静默变成「正前方」，所以这里显式拒绝。
	if typeof(value) == TYPE_BOOL:
		return null
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return fposmod(float(value), 360.0)
	if typeof(value) != TYPE_STRING:
		# null / 字典 / 数组 / 其它对象都不是方向；不要在这里猜默认值。
		return null

	var key := str(value).strip_edges().to_lower()
	for separator in ["_", "-", " ", "\t"]:
		key = key.replace(separator, "")
	if ALIASES.has(key):
		return ALIASES[key]
	# 数字写法（"90" / "-90" / "720.5"）：先剥分隔符再判，免得 "-90" 被当成方向名。
	if key.is_valid_float():
		return fposmod(key.to_float(), 360.0)
	return null
