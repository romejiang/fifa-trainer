class_name AxisMapping
extends RefCounted

## 手柄轴 → 本项目语义的映射表：索引与符号分开存。
##
## 为什么不用「带符号索引」：`-1` 既是合法的符号，也是「未映射」的哨兵。合并成一个
## 整数后，`-1` 到底表示「索引 1、方向取反」还是「没有映射」无法区分。所以索引用
## `-1` 表示未映射，符号单独用 ±1 的字段。
##
## 索引完全由探针给出（ProbeEvaluator.mapping_from_steps），本类不假设任何厂商的轴
## 布局，也不读 Input / InputMap。
##
## 校准在**原始轴空间**测量：`raw_rs()` 返回未乘符号的原始值，符号只在
## `snapshot_rs()` 归一化的最后一步施加（见 Calibration.normalize 的顺序约束）。

var rs_x_index: int = -1
var rs_x_sign: int = 1
var rs_y_index: int = -1
var rs_y_sign: int = 1
var ls_x_index: int = -1
var ls_x_sign: int = 1
var ls_y_index: int = -1
var ls_y_sign: int = 1
var lt_index: int = -1
var rt_index: int = -1
var lt_rest: float = 0.0
var rt_rest: float = 0.0


func has_rs() -> bool:
	return rs_x_index >= 0 and rs_y_index >= 0


func has_ls() -> bool:
	return ls_x_index >= 0 and ls_y_index >= 0


## 取一根已映射轴的原始值并施加符号；未映射 / 越界返回 0.0，不抛错。
##
## 键只接受 rs_x / rs_y / ls_x / ls_y / lt / rt；未知键同样返回 0.0。
func mapped(raw: PackedFloat32Array, key: StringName) -> float:
	match key:
		&"rs_x":
			return _signed(raw, rs_x_index, rs_x_sign)
		&"rs_y":
			return _signed(raw, rs_y_index, rs_y_sign)
		&"ls_x":
			return _signed(raw, ls_x_index, ls_x_sign)
		&"ls_y":
			return _signed(raw, ls_y_index, ls_y_sign)
		&"lt":
			return _plain(raw, lt_index)
		&"rt":
			return _plain(raw, rt_index)
	return 0.0


## 右摇杆的**原始**二元组，不乘符号。
##
## 校准屏用它采 center / scale：中点和量程必须在设备上报的原始坐标里测量。
## 先乘符号会把中点也翻过去（中点 0.02 时引入 0.04 的系统偏差），所以符号只在
## snapshot_rs() 里施加一次。索引未映射或越界时返回 Vector2.ZERO。
func raw_rs(raw: PackedFloat32Array) -> Vector2:
	if not has_rs():
		return Vector2.ZERO
	if rs_x_index >= raw.size() or rs_y_index >= raw.size():
		return Vector2.ZERO
	return Vector2(raw[rs_x_index], raw[rs_y_index])


## raw → 归一化 → 死区，唯一的角度接缝入口。
##
## 顺序固定：两次 Calibration.normalize（先减中点、再除量程、最后乘符号），
## 再 Calibration.deadzone。输出直接喂 Geometry.angle_of / Geometry.magnitude；
## geometry.gd 不再做任何翻转或缩放。
static func snapshot_rs(raw: PackedFloat32Array, mapping: AxisMapping,
		calibration: Calibration, deadzone: float) -> Vector2:
	if mapping == null or calibration == null or not mapping.has_rs():
		return Vector2.ZERO
	return _snapshot(raw, mapping.rs_x_index, mapping.rs_y_index,
		calibration.center_x, calibration.center_y,
		calibration.scale_x, calibration.scale_y,
		mapping.rs_x_sign, mapping.rs_y_sign, deadzone)


## 左摇杆的归一化入口：与 `snapshot_rs()` **完全同构** —— 同一份 `_snapshot`，
## 只有索引、校准字段与符号不同（D-06）。
##
## 为什么要抽公共实现而不是复制一份：四个 `relative_to_ls` 技能的判定对等性
## 依赖「左右摇杆用同一套变换」。两份复制体会在某次修 bug 时只改一边，而那种
## 分叉不会让任何现有测试变红 —— 只会让左摇杆的手感悄悄偏离桌面版。
static func snapshot_ls(raw: PackedFloat32Array, mapping: AxisMapping,
		calibration: Calibration, deadzone: float) -> Vector2:
	if mapping == null or calibration == null or not mapping.has_ls():
		return Vector2.ZERO
	return _snapshot(raw, mapping.ls_x_index, mapping.ls_y_index,
		calibration.ls_center_x, calibration.ls_center_y,
		calibration.ls_scale_x, calibration.ls_scale_y,
		mapping.ls_x_sign, mapping.ls_y_sign, deadzone)


## 两根摇杆共用的唯一变换：索引越界 / 未映射一律返回 ZERO，绝不部分归一化。
static func _snapshot(raw: PackedFloat32Array, x_index: int, y_index: int,
		center_x: float, center_y: float, scale_x: float, scale_y: float,
		sign_x: int, sign_y: int, deadzone: float) -> Vector2:
	if x_index < 0 or y_index < 0 or x_index >= raw.size() or y_index >= raw.size():
		return Vector2.ZERO
	var x := Calibration.normalize(raw[x_index], center_x, scale_x, sign_x)
	var y := Calibration.normalize(raw[y_index], center_y, scale_y, sign_y)
	return Calibration.deadzone(x, y, deadzone)


func to_dict() -> Dictionary:
	return {
		"rs_x": {"index": rs_x_index, "sign": rs_x_sign},
		"rs_y": {"index": rs_y_index, "sign": rs_y_sign},
		"ls_x": {"index": ls_x_index, "sign": ls_x_sign},
		"ls_y": {"index": ls_y_index, "sign": ls_y_sign},
		"lt": {"index": lt_index, "rest": lt_rest},
		"rt": {"index": rt_index, "rest": rt_rest},
	}


## 从 JSON 字典还原映射。任一非法项 → 记一条 ConfigError 并返回 null。
##
## rs_x / rs_y / ls_x / ls_y 四项必须存在；lt / rt 可省略（本阶段的绿色搓射不读扳机，
## 缺省是 -1 = 未映射）。ls 允许 -1，所以「缺左摇杆探针」的旧档案仍能被**解析**；
## 但它进不了练习 —— DeviceProfile 的 schema v2 门用 `has_ls()` 把整份档案拒绝
## （D-06）。解析层不替使用层做政策判断，两层各守一条边。
static func from_dict(data: Variant, out_errors: Array[ConfigError]) -> AxisMapping:
	var before := out_errors.size()
	if typeof(data) != TYPE_DICTIONARY:
		_error(out_errors, "$.axes", &"axes_not_object",
			"axes 必须是对象，收到 %s" % JSON.stringify(data),
			"写成 { \"rs_x\": { \"index\": 2, \"sign\": -1 }, ... } 这样的对象。")
		return null
	var root: Dictionary = data
	var mapping := AxisMapping.new()

	var rs_x := _axis(root, "rs_x", false, out_errors)
	mapping.rs_x_index = int(rs_x["index"])
	mapping.rs_x_sign = int(rs_x["sign"])

	var rs_y := _axis(root, "rs_y", false, out_errors)
	mapping.rs_y_index = int(rs_y["index"])
	mapping.rs_y_sign = int(rs_y["sign"])

	var ls_x := _axis(root, "ls_x", true, out_errors)
	mapping.ls_x_index = int(ls_x["index"])
	mapping.ls_x_sign = int(ls_x["sign"])

	var ls_y := _axis(root, "ls_y", true, out_errors)
	mapping.ls_y_index = int(ls_y["index"])
	mapping.ls_y_sign = int(ls_y["sign"])

	var lt := _axis(root, "lt", true, out_errors)
	mapping.lt_index = int(lt["index"])
	mapping.lt_rest = float(lt["rest"])

	var rt := _axis(root, "rt", true, out_errors)
	mapping.rt_index = int(rt["index"])
	mapping.rt_rest = float(rt["rest"])
	if out_errors.size() > before:
		return null
	return mapping


static func _signed(raw: PackedFloat32Array, index: int, sign: int) -> float:
	if index < 0 or index >= raw.size():
		return 0.0
	return raw[index] * float(sign)


static func _plain(raw: PackedFloat32Array, index: int) -> float:
	if index < 0 or index >= raw.size():
		return 0.0
	return raw[index]


## 读一个轴条目，返回 `{index, sign, rest}`。
##
## `required = false` 时条目缺失是合法的（lt / rt 本阶段不读），直接给出未映射默认值。
## 条目存在但字段缺失 / 类型不对，一律记错误 —— 空对象 `{}` 不能冒充「未映射」。
static func _axis(root: Dictionary, key: String, allow_unmapped: bool,
		out: Array[ConfigError]) -> Dictionary:
	var path := "$.axes." + key
	var result := {"index": -1, "sign": 1, "rest": 0.0}
	var required := not (key == "lt" or key == "rt")
	if not root.has(key):
		if required:
			_error(out, path, &"missing_axis",
				"缺少 %s 轴映射" % key,
				"补上 { \"index\": 0~7, \"sign\": 1 或 -1 }。")
		return result
	var raw: Variant = root[key]
	if typeof(raw) != TYPE_DICTIONARY:
		_error(out, path, &"axis_not_object",
			"%s 必须是对象，收到 %s" % [key, JSON.stringify(raw)],
			"写成 { \"index\": 2, \"sign\": -1 }。")
		return result
	var entry: Dictionary = raw
	result["index"] = _index(entry, path, allow_unmapped, out)
	# 扳机条目没有符号：符号只对摇杆轴有意义，缺 sign 不是错误。
	if key != "lt" and key != "rt":
		result["sign"] = _sign(entry, path, out)
	result["rest"] = _rest(entry, path, out)
	return result


## 轴序号：JSON 的 1 解析成 float，所以 TYPE_INT 与 TYPE_FLOAT 都接受，但必须是整数值。
## rs 轴必须落在 0..7；allow_unmapped 为真时额外接受 -1（= 未映射）。
static func _index(entry: Dictionary, path: String, allow_unmapped: bool,
		out: Array[ConfigError]) -> int:
	if not entry.has("index"):
		_error(out, path + ".index", &"missing_axis_index",
			"缺少 index 字段", "写成 0~7 的整数；未映射写 -1。")
		return -1
	var raw: Variant = entry["index"]
	if not _is_number(raw):
		_error(out, path + ".index", &"axis_index_not_number",
			"index 必须是数字，收到 %s" % JSON.stringify(raw),
			"写成 0~7 的整数。")
		return -1
	var value := float(raw)
	if value != floorf(value):
		_error(out, path + ".index", &"axis_index_not_integer",
			"index 必须是整数，收到 %s" % JSON.stringify(raw),
			"写成 0~7 的整数。")
		return -1
	var index := int(value)
	if index >= 0 and index <= 7:
		return index
	if index == -1 and allow_unmapped:
		return -1
	_error(out, path + ".index", &"axis_index_out_of_range",
		"index 必须在 0~7 之间（未映射写 -1），收到 %d" % index,
		"改成 0~7 的整数；轴序号由探针给出，不要手猜。")
	return -1


## 符号只能是 ±1。0 会让整根轴恒为 0，必须整份丢弃。
static func _sign(entry: Dictionary, path: String, out: Array[ConfigError]) -> int:
	if not entry.has("sign"):
		_error(out, path + ".sign", &"missing_axis_sign",
			"缺少 sign 字段", "写成 1 或 -1；推右/推下为正用 1。")
		return 1
	var raw: Variant = entry["sign"]
	if not _is_number(raw):
		_error(out, path + ".sign", &"axis_sign_not_number",
			"sign 必须是数字，收到 %s" % JSON.stringify(raw),
			"写成 1 或 -1。")
		return 1
	var value := int(float(raw))
	if value != 1 and value != -1:
		_error(out, path + ".sign", &"axis_sign_invalid",
			"sign 只能是 1 或 -1，收到 %s" % JSON.stringify(raw),
			"改成 1（推右/推下为正向）或 -1（反向）。")
		return 1
	return value


## 扳机静止值：只要求有限数值；扳机在 0.0 与 -1.0 两种静止值之间切换是已知现象。
static func _rest(entry: Dictionary, path: String, out: Array[ConfigError]) -> float:
	if not entry.has("rest"):
		return 0.0
	var raw: Variant = entry["rest"]
	if not _is_number(raw):
		_error(out, path + ".rest", &"axis_rest_not_number",
			"rest 必须是数字，收到 %s" % JSON.stringify(raw),
			"写成扳机的静止值，例如 -1.0 或 0.0。")
		return 0.0
	var value := float(raw)
	if not is_finite(value):
		_error(out, path + ".rest", &"axis_rest_not_finite",
			"rest 必须是有限数，收到 %s" % JSON.stringify(raw),
			"写成 -1.0 或 0.0。")
		return 0.0
	return value


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


static func _error(out: Array[ConfigError], path: String, code: StringName,
		message: String, fix_hint: String) -> void:
	out.append(ConfigError.new(path, code, message, fix_hint))
