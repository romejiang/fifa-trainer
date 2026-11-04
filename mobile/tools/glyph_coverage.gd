extends SceneTree

## 字形闸门：在关闭系统字体兜底的前提下，逐个断言清单里的字符都能渲染。
##
## 为什么必须关掉系统兜底：macOS 的系统字体能补上 Noto Sans SC 缺的 ✗，于是
## 闸门在开发机上永远是绿的，到了没有对应系统字体的安卓手机上照旧豆腐
## （02-RESEARCH §P6 / T-02-09）。这里对 base_font 与 fallbacks 里的每一个
## FontFile 逐层关掉 allow_system_fallback 再断言 —— 顶层资源是 FontVariation
## 而不是 FontFile，所以 research 片段里那句 `if font is FontFile` 永远不成立，
## 照着抄会得到一个什么都不关的闸门。
##
## 清单来自 res://assets/fonts/required_glyphs.txt，由 tools/make_font_subset.py
## 生成；本文件不内联第二份字符表，否则清单与断言会各自漂移。

const REQUIRED_PATH := "res://assets/fonts/required_glyphs.txt"
const APP_FONT_PATH := "res://assets/fonts/AppFont.tres"

func _initialize() -> void:
	var font := load(APP_FONT_PATH) as FontVariation
	if font == null:
		_fail("GLYPH_FAIL 无法加载 %s" % APP_FONT_PATH)
		return
	if font.base_font == null:
		_fail("GLYPH_FAIL 缺少 base_font：AppFont.tres 被简化成了空资源")
		return
	if font.fallbacks.is_empty():
		_fail("GLYPH_FAIL 缺少 fallback：✗ 只能由符号子集提供，单字体会豆腐")
		return

	# 逐层关闭：只关顶层（或只判断顶层是不是 FontFile）都会漏掉真正的字体文件。
	for file in _font_files(font):
		file.allow_system_fallback = false

	# 证明 project.godot 的 [gui] theme/custom_font 真的接上了，而不是只造了
	# 一个没人引用的 .tres —— 后者会让上面的断言全绿，屏幕上却仍是默认字体。
	var theme_font := ThemeDB.fallback_font
	if theme_font == null or theme_font.resource_path != APP_FONT_PATH:
		_fail("GLYPH_FAIL 项目字体没有指向 %s（检查 project.godot 的 [gui] 段）" % APP_FONT_PATH)
		return

	var text := FileAccess.get_file_as_string(REQUIRED_PATH)
	if text.is_empty():
		_fail("GLYPH_FAIL 读不到 %s" % REQUIRED_PATH)
		return

	var missing: Array[String] = []
	var checked := 0
	for i in text.length():
		var code := text.unicode_at(i)
		if code == 10 or code == 13 or code == 32:
			continue
		checked += 1
		if not font.has_char(code):
			var glyph := String.chr(code)
			if not missing.has(glyph):
				missing.append(glyph)

	# 信息行，不参与判定：主字体若自己有 ✗，双字体就不再是硬需求。
	print("GLYPH_BASE_HAS_X=%s" % str(font.base_font.has_char("✗".unicode_at(0))))

	if missing.is_empty():
		print("GLYPH_OK chars=%d" % checked)
		quit(0)
	else:
		printerr("GLYPH_MISSING %d: %s" % [missing.size(), "".join(missing)])
		quit(1)

## FontVariation 的 base_font 与每个 fallbacks 条目里真正的 FontFile。
func _font_files(font: FontVariation) -> Array[FontFile]:
	var out: Array[FontFile] = []
	if font.base_font is FontFile:
		out.append(font.base_font as FontFile)
	for entry in font.fallbacks:
		if entry is FontFile:
			out.append(entry as FontFile)
	return out

func _fail(message: String) -> void:
	printerr(message)
	quit(1)
