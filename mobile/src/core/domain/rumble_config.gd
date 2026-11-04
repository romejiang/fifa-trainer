class_name RumbleConfig
extends RefCounted

## 震动参数：与 desktop/padskills/config.py:244-250 的 `RumbleConfig` 逐字段同默认值。
##
## backend 的合法值是 auto / pygame / sdl2 / xinput / none（桌面语义）。移动端没有 pygame
## 与 xinput 后端，但配置必须原样读进来 —— 同一份 skills_config.json 两端共用，
## 遇到不可用的后端要在运行时降级并给提示，而不是在校验期拒绝。
##
## 本类只承载已校验的数据：范围与枚举检查在 ConfigValidator。

var enabled: bool = true
var backend: StringName = &"auto"
var startup_test: bool = true
var startup_test_strength: float = 0.55
var startup_test_ms: int = 160
