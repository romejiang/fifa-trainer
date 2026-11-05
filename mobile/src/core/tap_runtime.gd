class_name TapRuntime
extends GestureEngine

## 单动作 tap 运行时：Phase 4 的兼容层，现在是 `GestureEngine` 的子类。
##
## 为什么保留这个类：`main.gd` 与 Phase 4 的全部套件都按
## `TapRuntime.new(skill, global_cooldown_ms, gesture_release_ms, layout_confirmed[, group_size])`
## 构造它。构造签名**一个字都不能变** —— 它把「一个技能 + 两个输入参数」翻译成
## 「一份只含该技能的 AppConfig」，再交给基类。
##
## 为什么不再自己实现 `tick()`：Phase 4 里这段是「单技能能用到的那部分引擎」；
## Phase 5 的 `GestureEngine` 是同一段分支顺序的完整形态。子类只做参数翻译，
## 任何逻辑分叉都会让「单技能」与「多技能」成为两套判定真相。
##
## ## 与 Phase 4 的差别（行为保持，机制改变）
##
## - `relative_to_ls` 从「构造期整个禁用」变成「运行期由 `!ls_ok` 决定」。
##   旧用例的帧不带 LS（`ls_mag` 默认 0），所以仍然是零判定。
## - idle 计时器与 `_discard_other_claims` 现在真的存在：前者对 `TapDetector`
##   （`on_idle()` 空实现）零行为差异，后者在单技能下没有对象。
## - `status()` / `_record()` 由基类提供，这里不再声明第二份 —— 布局硬门在
##   基类 `status()` 的最前面，Phase 4 的「未确认布局」断言原样成立。
##
## ## 合成配置的口径
##
## `idle_reset_ms` 与 `ls_facing_threshold` 用出厂默认（250 / 0.35）：Phase 4 的
## 构造签名没有这两个参数，而所有旧用例都按出厂值书写。`global_cooldown_ms` 与
## `gesture_release_ms` 由调用方注入，与 Phase 4 逐字一致。


## 「只练绿色搓射」的唯一实现点：按 `kind` 选，绝不按名字或下标。
##
## 真实配置里 `skills` 的顺序是 Roulette / Stepover / Heel-to-Heel / La Croqueta /
## Green Finesse —— 绿色搓射是**最后一个**。任何 `skills[0]` 的写法都会读到马赛回旋
## （arc），于是「命中次数」永远是 0。名字可以被翻译改掉，`kind` 不会。
## 零个或多个 taps 动作都返回 null：运行时的语义是「唯一一个」。
static func select_taps_skill(config: AppConfig) -> Skill:
	var found: Skill = null
	for skill in config.enabled_skills():
		if skill.kind != Skill.KIND_TAPS:
			continue
		if found != null:
			return null
		found = skill
	return found


## 把「一个技能 + 全局冷却 + 解锁时长」翻译成只含该技能的 AppConfig。
func _init(p_skill: Skill, p_global_cooldown_ms: int, p_gesture_release_ms: int,
		p_layout_confirmed := false, p_group_size: int = GROUP_SIZE) -> void:
	var synthetic := AppConfig.new()
	synthetic.skills.append(p_skill)
	synthetic.global_cooldown_ms = p_global_cooldown_ms
	synthetic.input.gesture_release_ms = p_gesture_release_ms
	super._init(synthetic, p_layout_confirmed, p_group_size)
