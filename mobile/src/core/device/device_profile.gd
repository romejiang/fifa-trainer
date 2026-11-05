class_name DeviceProfile
extends RefCounted

## 一台手柄的完整设备档案：轴映射 + 校准 + 探针质量 + 布局建议。
##
## **不存设备序号。** 官方文档明确 `get_connected_joypads()` 的顺序在重启后不保证
## 一致，存下来迟早会错位到另一台手柄。身份只用 `key`（guid 优先、否则规范化设备名）。
##
## 复用门是纯函数：`can_reuse()` 只比较本次实测的四个 index+sign。四个值逐项相等才
## 采用整份档案（含它的校准）；只要有一项不同 —— 哪怕只是符号 —— 就必须整份丢弃、
## 重跑四步探针。**绝不部分应用**：「同名手柄 + 错误映射」在这里必须返回 false。
##
## `profile_id` 是 INPUT-03 的预留字段：本阶段固定 "primary"（单档案），但字段与
## 序列化必须存在，将来多档案（例如一人一手柄）不需要改 schema。
##
## `probed_at_iso` 只承载字符串：墙钟由外层填（core 不读 Time.），排障用，不参与判定。

const SCHEMA_VERSION := 1
const LAYOUT_XBOX := &"xbox"
const LAYOUT_PLAYSTATION := &"playstation"

var schema_version: int = SCHEMA_VERSION
## `guid:...` 或 `name:...`；由 make_key() 生成，始终与下面两个字段并存便于人工核对。
var key: String = ""
## INPUT-03 预留：单档案阶段固定 "primary"。
var profile_id: String = "primary"
var device_name: String = ""
var device_guid: String = ""
var axes: AxisMapping = null
var calibration: Calibration = null
## 探针质量：四步各自的 samples / margin / separation。内容不做 schema 校验，
## 避免把「探针指标」写死成档案格式的一部分。
var quality: Dictionary = {}
## 空 StringName = 没有建议；调用方必须让用户二选一，绝不预选。
var layout: StringName = &""
var layout_confirmed: bool = false
var button_index_ok: bool = true
var probed_at_iso: String = ""


## guid 非空就用 guid（大小写不敏感），否则退回规范化设备名。
static func make_key(device_guid: String, device_name: String) -> String:
	var guid := device_guid.strip_edges().to_lower()
	if not guid.is_empty():
		return "guid:" + guid
	return "name:" + device_name.strip_edges().to_lower()


## 复用门：四个 index+sign 逐项相等才返回 true。
##
## **只比较这四项**：`calibration.center/scale` 与探针的静止基线 rest 都不参与 ——
## 复用时整份采用档案里的校准，rest 只是探针阶段的临时基线。
## `axes == null` 时返回 false（没有映射就没有可复用的东西）。
func can_reuse(observed_rs_x_index: int, observed_rs_x_sign: int,
		observed_rs_y_index: int, observed_rs_y_sign: int) -> bool:
	if axes == null:
		return false
	return (
		axes.rs_x_index == observed_rs_x_index
		and axes.rs_x_sign == observed_rs_x_sign
		and axes.rs_y_index == observed_rs_y_index
		and axes.rs_y_sign == observed_rs_y_sign
	)


## 只按小写设备名匹配；认不出就返回空（无建议，绝不静默落默认值）。
##
## 「Xbox Wireless Controller」同时含 xbox 与 wireless controller，xbox 先判。
static func suggest_layout(device_name: String) -> StringName:
	var lowered := device_name.strip_edges().to_lower()
	if lowered.contains("xbox"):
		return LAYOUT_XBOX
	for token in ["dualsense", "dualshock", "wireless controller", "playstation", "ps4", "ps5"]:
		if lowered.contains(token):
			return LAYOUT_PLAYSTATION
	return &""


func to_dict() -> Dictionary:
	return {
		"schema_version": schema_version,
		"key": key,
		"profile_id": profile_id,
		"device_name": device_name,
		"device_guid": device_guid,
		"axes": axes.to_dict() if axes != null else {},
		"calibration": calibration.to_dict() if calibration != null else {},
		"quality": quality,
		"layout": String(layout),
		"layout_confirmed": layout_confirmed,
		"button_index_ok": button_index_ok,
		"probed_at_iso": probed_at_iso,
	}


## 从 JSON 还原档案。**任何一项不合法 → 整份丢弃**（返回 null + 至少一条 ConfigError）。
##
## 绝不部分恢复、绝不静默用默认值补：一份坏档案最坏的结果必须是「要求重探」，
## 而不是「带着错误轴映射进入练习」。所有取值先用 typeof() 判断再转换；JSON 的
## 整数会被解析成 float，所以数值字段同时接受 TYPE_INT 与 TYPE_FLOAT。
static func from_dict(data: Variant, out_errors: Array[ConfigError]) -> DeviceProfile:
	var before := out_errors.size()
	if typeof(data) != TYPE_DICTIONARY:
		_error(out_errors, "$", &"profile_not_object",
			"设备档案必须是 JSON 对象，收到 %s" % JSON.stringify(data),
			"检查文件是否被截断；顶层必须是 { ... }。")
		return null
	var root: Dictionary = data
	var profile := DeviceProfile.new()

	var version: Variant = root.get("schema_version")
	if not _is_number(version) or float(version) != float(SCHEMA_VERSION):
		_error(out_errors, "$.schema_version", &"unsupported_schema",
			"schema_version 必须是 %d，收到 %s" % [SCHEMA_VERSION, JSON.stringify(version)],
			"改成 %d；未知版本必须整份丢弃，不做猜测迁移。" % SCHEMA_VERSION)
	else:
		profile.schema_version = SCHEMA_VERSION

	profile.key = _read_text(root, "key", "$.key", false, out_errors)
	profile.profile_id = _read_text(root, "profile_id", "$.profile_id", false, out_errors)
	profile.device_name = _read_text(root, "device_name", "$.device_name", false, out_errors)
	profile.device_guid = _read_text(root, "device_guid", "$.device_guid", true, out_errors)

	profile.axes = AxisMapping.from_dict(root.get("axes"), out_errors)
	profile.calibration = Calibration.from_dict(root.get("calibration"), out_errors)

	var quality: Variant = root.get("quality")
	if typeof(quality) != TYPE_DICTIONARY:
		_error(out_errors, "$.quality", &"quality_not_object",
			"quality 必须是对象，收到 %s" % JSON.stringify(quality),
			"补上 {} 或探针质量对象；内容不做校验。")
	else:
		profile.quality = quality

	var layout: Variant = root.get("layout")
	if typeof(layout) != TYPE_STRING:
		_error(out_errors, "$.layout", &"layout_not_string",
			"layout 必须是字符串，收到 %s" % JSON.stringify(layout),
			"写成 \"xbox\"、\"playstation\" 或 \"\"（无建议）。")
	elif layout == "":
		profile.layout = &""
	elif layout == "xbox":
		profile.layout = LAYOUT_XBOX
	elif layout == "playstation":
		profile.layout = LAYOUT_PLAYSTATION
	else:
		_error(out_errors, "$.layout", &"layout_unknown",
			"layout 只能是 \"xbox\" / \"playstation\" / \"\"，收到 %s" % JSON.stringify(layout),
			"改成三个合法值之一；布局只影响屏幕上显示的键名。")

	profile.layout_confirmed = _read_bool(root, "layout_confirmed", out_errors)
	profile.button_index_ok = _read_bool(root, "button_index_ok", out_errors)
	profile.probed_at_iso = _read_text(root, "probed_at_iso", "$.probed_at_iso", true, out_errors)

	if out_errors.size() > before:
		return null
	return profile


## 非空文本字段。allow_empty = true 时允许空串（device_guid / probed_at_iso）。
static func _read_text(root: Dictionary, field: String, path: String, allow_empty: bool,
		out: Array[ConfigError]) -> String:
	if not root.has(field):
		_error(out, path, &"missing_field",
			"缺少 %s 字段" % field, "补上 %s。" % field)
		return ""
	var raw: Variant = root[field]
	if typeof(raw) != TYPE_STRING:
		_error(out, path, &"string_expected",
			"%s 必须是字符串，收到 %s" % [field, JSON.stringify(raw)],
			"写成不带引号以外的形式，例如 \"Xbox Series X Controller\"。")
		return ""
	var value: String = raw
	if not allow_empty and value.strip_edges().is_empty():
		_error(out, path, &"empty_field",
			"%s 不能为空" % field, "补上非空值；空值无法定位设备档案。")
		return ""
	return value


static func _read_bool(root: Dictionary, field: String, out: Array[ConfigError]) -> bool:
	var path := "$." + field
	if not root.has(field):
		_error(out, path, &"missing_field",
			"缺少 %s 字段" % field, "补上 true 或 false。")
		return false
	var raw: Variant = root[field]
	if typeof(raw) != TYPE_BOOL:
		_error(out, path, &"bool_expected",
			"%s 必须是布尔值，收到 %s" % [field, JSON.stringify(raw)],
			"写 true 或 false（不要加引号）；字符串 \"true\" 不是布尔值。")
		return false
	return raw


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


static func _error(out: Array[ConfigError], path: String, code: StringName,
		message: String, fix_hint: String) -> void:
	out.append(ConfigError.new(path, code, message, fix_hint))
