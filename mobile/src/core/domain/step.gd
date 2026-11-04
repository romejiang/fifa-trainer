class_name Step
extends RefCounted

## 方向序列里的一步：与 desktop/padskills/config.py:152-163 的 `Step` 对齐。
##
## angles  允许的角度集合。长度 > 1 表示「任一方向都算」，例如 [90, 270] 是左右都行。
## hold_ms 需要把这个方向保持多久才算完成这一步；0 表示点拨一下即可。
##
## angles 在构造时复制一份：GDScript 的数组是引用类型，直接持有入参会把调用方后续的
## append / clear 穿透进对象内部。这条语义由 test_models.gd 断言，不要为了省一次复制
## 把它改回去。
##
## 本类只承载已校验的数据：方向名解析在 DirectionTable，步骤合法性在 ConfigValidator。

var angles: Array[float] = []
var hold_ms: float = 0.0


func _init(p_angles: Array[float] = [], p_hold_ms := 0.0) -> void:
	# 浅拷贝足够：Array[float] 的元素是值类型。
	angles = p_angles.duplicate()
	hold_ms = p_hold_ms
