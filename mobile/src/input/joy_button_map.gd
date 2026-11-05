class_name JoyButtonMap
extends RefCounted

## 手柄按钮索引 ↔ 本项目规范名。**只决定索引对应哪个规范名，不决定任何轴序号。**
##
## 轴映射完全由探针给出（`ProbeEvaluator.mapping_from_steps` → `AxisMapping`）：
## 从这里取轴号会让「不硬编码轴序号」直接失效，所以本表里没有任何轴相关字段。
##
## 覆盖引擎按钮枚举的 0..20。15 是 MISC1，16–19 是 PADDLE1–4，20 是 TOUCHPAD ——
## 本阶段的配置没有对应词汇，一律返回空串（与 `Buttons.canonical()` 同一失败值约定），
## 不打印、不报错：调用方把空串当成「这个索引没有规范名」即可。
##
## Phase 2 真机实测交叉验证过：A/B/X/Y = 0/1/2/3、LB/RB = 9/10，与本表一致。
##
## **本阶段的修饰键范围：只支持 `required_button = "RB"`。**
## `LT` / `RT` 在 Godot 里是轴，不是按钮；`PadStateBuffer.pressed_dict()` 只由按钮索引
## 产生，不会也不应该合成它们。`shared/skills_config.json` 的 `modifier_options` 虽然
## 列了 `["RB","RT"]`，但本阶段不做修饰键切换 UI，也不把扳机轴伪造成按钮：
## `AxisMapping` 已经预留 `lt_index` / `rt_index` / `lt_rest` / `rt_rest`，
## Phase 5 接入扳机轴归一之后再启用 RT 分支。这是范围声明，不是遗漏。

## 索引 → 规范名。15..20 显式给空串，让「覆盖 0..20」在表里一眼可见，
## 而不是靠查表失败才推断出「没有名字」。
const INDEX_TO_NAME := {
	0: "A",
	1: "B",
	2: "X",
	3: "Y",
	4: "BACK",
	5: "GUIDE",
	6: "START",
	7: "LS",
	8: "RS",
	9: "LB",
	10: "RB",
	11: "DPAD_UP",
	12: "DPAD_DOWN",
	13: "DPAD_LEFT",
	14: "DPAD_RIGHT",
	15: "",
	16: "",
	17: "",
	18: "",
	19: "",
	20: "",
}

## 规范名 → 索引。由 `INDEX_TO_NAME` 在类初始化时反向构建，**不写第二份字面量**：
## 两张表各写一份时，改了一张忘另一张的漂移只能靠测试发现。GDScript 的常量不能求值
## 循环，所以用 `_static_init()` —— 它在类首次加载时执行一次，语义上就是这张表的
## 一次性反向索引。
static var NAME_TO_INDEX: Dictionary = {}


static func _static_init() -> void:
	for index in INDEX_TO_NAME:
		var canonical: String = INDEX_TO_NAME[index]
		if canonical.is_empty():
			continue
		NAME_TO_INDEX[canonical] = index


## 查不到返回空串。与 `Buttons.canonical()` 的失败值约定一致：空串由调用方决定
## 是跳过、报错还是提示，本类不替调用方做决定。
static func name_of(index: int) -> String:
	return INDEX_TO_NAME.get(index, "")
