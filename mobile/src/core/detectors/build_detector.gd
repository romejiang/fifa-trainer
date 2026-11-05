class_name DetectorFactory
extends RefCounted

## 按 `skill.kind` 选识别器：与 desktop/padskills/detectors.py:1039-1046 的
## `build_detector()` 同构，是**唯一**的构造入口。
##
## 调用方一律 `DetectorFactory.build(skill)`，绝不按技能名或位置决定用哪个检测器：
## 硬编码 `ArcDetector.new(skill)` 会让非弧线技能被弧线检测器回放，期望值与
## 回放结果一起跑偏，而这个错误在「5 个成功用例」里看不出来 —— 它只会让失败码
## 悄悄变成别的码。
##
## 未知 kind 返回 `null`，不在 core 里抛异常：`ConfigValidator` 已把 kind 限制在
## `arc` / `sequence` / `taps` 三值内，这里返回 null 是防御性兜底；调用方（回放套件）
## 拿到 null 必须直接 fail 该用例，而不是回落到某个默认检测器。
##
## 一个文件一个 `class_name`（skill.gd:6-7 的既定约束），所以工厂独占本文件。


static func build(skill: Skill) -> Detector:
	match skill.kind:
		Skill.KIND_ARC:
			return ArcDetector.new(skill)
		Skill.KIND_TAPS:
			return TapDetector.new(skill)
		Skill.KIND_SEQUENCE:
			return SequenceDetector.new(skill)
	return null
