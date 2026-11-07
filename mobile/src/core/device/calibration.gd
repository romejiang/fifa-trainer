class_name Calibration
extends RefCounted

## 摇杆校准：中点、量程、归一化与死区。
##
## 校准屏采两次样本：手离开（中点）与四个方向推到最外圈（量程）。本类只做统计与
## 变换，采样由外层负责 —— 没有时钟、没有 I/O、没有引擎单例。
##
## 归一化顺序是硬约束：**先减中点 → 再除量程 → 最后乘符号**。
## 先乘符号会把中点也翻过去：中点 0.02、raw 0.02 时，正确结果精确为 0，
## 顺序写反会得到 ±0.04。测试 _check_normalize_order 把这一点钉死。
##
## `scale <= 0` 必须由上游（探针 / 档案校验）拒绝，本类**不写**除零兜底：
## 静默把坏档案变成「摇杆永远居中」比报错更难查。

## 中点与量程都要求至少 15 帧：60 Hz 下 400 ms 有 24 帧，15 是「确实按住了」的底线。
const MIN_SAMPLES := 15
## 中点阶段任一轴峰峰值超过它 → 用户没松手。
const MAX_PEAK_TO_PEAK := 0.15
## 中点偏移超过它 → 摇杆磨损；只警告，不拒绝启动。
const MAX_CENTER_DRIFT := 0.35
## 四方向最大位移低于它 → 推不到外圈。
const MIN_RANGE := 0.6
## 任一轴量程低于它 → 该轴不可用（推到头的距离太短）。
const MIN_SCALE := 0.5

## 每轴独立的中点与量程：摇杆是两个独立的模拟轴，磨损与偏移不会两轴同步。
var center_x: float = 0.0
var center_y: float = 0.0
var scale_x: float = 1.0
var scale_y: float = 1.0

## 左摇杆独立校准：左右两只摇杆的磨损、中点偏移与接线可以完全独立，共用一份
## 校准会让「右摇杆准、左摇杆偏」的手柄永远无法同时对齐。顺序与 RS 完全一致：
## 先减中点 → 再除量程 → 最后乘符号（见 `normalize`）。
var ls_center_x: float = 0.0
var ls_center_y: float = 0.0
var ls_scale_x: float = 1.0
var ls_scale_y: float = 1.0


## raw → 归一化。三步顺序写死：先减中点、再除量程、最后乘符号。
##
## NaN / Inf 一律回到 0.0（调用方另计一次坏样本）。不在这里替 `scale <= 0` 兜底：
## 那会把一份坏档案静默变成「摇杆永远居中」，用户只会看到「怎么推都没反应」。
static func normalize(raw: float, center: float, scale: float, sign: int) -> float:
	if not is_finite(raw) or not is_finite(center) or not is_finite(scale):
		return 0.0
	var centered := raw - center
	var normalized := clampf(centered / scale, -1.0, 1.0)
	return float(sign) * normalized


## 带重新缩放的死区：角度不变，可用行程被拉满。
##
## 逐字移植 desktop/padskills/input_source.py:328-334。两条性质必须保留：
##   1. 角度不变：乘的是标量 scaled，方向不动；
##   2. 输出长度 = scaled ≤ 1.0：x/m 与 y/m 是单位向量，乘上 scaled 后长度就是 scaled。
## 斜向推到底 (1.0, 1.0) 的 m ≈ 1.4142，scaled 被 minf(1.0, …) 封顶到 1.0，
## 所以返回 (0.7071, 0.7071)、长度恰好 1.0，不是 1.41。
##
## 禁止用 Input 的向量合成（那套圆形死区与 enter_threshold）或 InputMap 替代：
## 同一个物理位置会在不同点越过阈值，判定结果就不再与桌面版一致。
static func deadzone(x: float, y: float, dz: float) -> Vector2:
	# NaN / Inf 必须在这里挡住：调用方可能直接喂 raw 值，坏样本不能流进判定。
	if not is_finite(x) or not is_finite(y) or not is_finite(dz):
		return Vector2.ZERO
	var m := sqrt(x * x + y * y)
	if m <= dz or m == 0.0:
		return Vector2.ZERO
	var scaled := minf(1.0, (m - dz) / (1.0 - dz))
	return Vector2(x / m * scaled, y / m * scaled)


## 从中点样本里取每轴中位数。返回 `{ok, center, peak_to_peak, warnings, code, message}`。
##
## 为什么是中位数而不是均值：静止时的单帧尖峰（蓝牙丢包重传）会把均值拉偏，
## 中位数不受影响。峰峰值用来判断「用户是否在动」：缓慢漂移的标准差可能很小，
## 峰峰值一定大。
static func center_from_samples(samples: Array[Vector2]) -> Dictionary:
	var warnings: Array[String] = []
	if samples.size() < MIN_SAMPLES:
		return {
			"ok": false,
			"center": Vector2.ZERO,
			"peak_to_peak": 0.0,
			"warnings": warnings,
			"code": &"not_enough_samples",
			"message": "采样太少：只有 %d 帧（至少要 %d 帧），请松手保持 400 ms" % [
				samples.size(), MIN_SAMPLES],
		}
	var center := Vector2(_median(samples, true), _median(samples, false))
	var peak_to_peak := maxf(_peak_to_peak(samples, true), _peak_to_peak(samples, false))
	if peak_to_peak > MAX_PEAK_TO_PEAK:
		return {
			"ok": false,
			"center": center,
			"peak_to_peak": peak_to_peak,
			"warnings": warnings,
			"code": &"hand_on_stick",
			"message": "采样期间摇杆在动：峰峰值 %.3f > %.2f，请双手离开摇杆再试" % [
				peak_to_peak, MAX_PEAK_TO_PEAK],
		}
	if absf(center.x) > MAX_CENTER_DRIFT or absf(center.y) > MAX_CENTER_DRIFT:
		warnings.append("中点偏移较大：中心 (%.3f, %.3f)，可能是摇杆磨损；已记录，建议换手柄" % [
			center.x, center.y])
	return {
		"ok": true,
		"center": center,
		"peak_to_peak": peak_to_peak,
		"warnings": warnings,
		"code": &"",
		"message": "",
	}


## 从四方向样本里取每轴最大位移作为量程。返回 `{ok, scale, warnings, code, message}`。
##
## 调用方按「右 / 上 / 下 / 左」各推一次的协议采样；本函数只看所有样本相对中点的
## 最大位移。峰值 < MIN_RANGE 说明推不到外圈；某一轴 < MIN_SCALE 说明该轴不可用。
static func scale_from_samples(samples: Array[Vector2], center: Vector2) -> Dictionary:
	var warnings: Array[String] = []
	if samples.size() < MIN_SAMPLES:
		return {
			"ok": false,
			"scale": Vector2.ONE,
			"warnings": warnings,
			"code": &"not_enough_samples",
			"message": "采样太少：只有 %d 帧（至少要 %d 帧），请每个方向都按住 400 ms" % [
				samples.size(), MIN_SAMPLES],
		}
	var scale := Vector2.ZERO
	for sample in samples:
		scale.x = maxf(scale.x, absf(sample.x - center.x))
		scale.y = maxf(scale.y, absf(sample.y - center.y))
	var peak := maxf(scale.x, scale.y)
	if peak < MIN_RANGE:
		return {
			"ok": false,
			"scale": scale,
			"warnings": warnings,
			"code": &"range_short",
			"message": "四方向最大位移只有 %.3f（至少要 %.2f），请把摇杆推到最外圈再按住" % [
				peak, MIN_RANGE],
		}
	if minf(scale.x, scale.y) < MIN_SCALE:
		return {
			"ok": false,
			"scale": scale,
			"warnings": warnings,
			"code": &"scale_too_small",
			"message": "某一轴量程只有 %.3f（至少要 %.2f）：X %.3f / Y %.3f，请四个方向都推到最外圈" % [
				minf(scale.x, scale.y), MIN_SCALE, scale.x, scale.y],
		}
	var raw_scale := scale
	if scale.x > 1.0:
		scale.x = 1.0
		warnings.append("X 轴量程 %.3f 超过 1.0，已按 1.0 使用" % raw_scale.x)
	if scale.y > 1.0:
		scale.y = 1.0
		warnings.append("Y 轴量程 %.3f 超过 1.0，已按 1.0 使用" % raw_scale.y)
	return {
		"ok": true,
		"scale": scale,
		"warnings": warnings,
		"code": &"",
		"message": "",
	}


func to_dict() -> Dictionary:
	return {
		"center_x": center_x,
		"center_y": center_y,
		"scale_x": scale_x,
		"scale_y": scale_y,
		"ls_center_x": ls_center_x,
		"ls_center_y": ls_center_y,
		"ls_scale_x": ls_scale_x,
		"ls_scale_y": ls_scale_y,
	}


## 八项必须是有限数值，且四个量程都大于 0；任一非法 → 记一条 ConfigError 并返回 null。
##
## LS 四字段**不做「可选、缺失落默认」**：默认校准在数值上与真校准不可区分，
## 04-11 的真机缺陷就是它被当成「这台手柄已经校准过」。缺字段只能整份重探。
static func from_dict(data: Variant, out_errors: Array[ConfigError]) -> Calibration:
	var before := out_errors.size()
	if typeof(data) != TYPE_DICTIONARY:
		_error(out_errors, "$.calibration", &"calibration_not_object",
			"calibration 必须是对象，收到 %s" % JSON.stringify(data),
			"写成 { \"center_x\": 0.0, \"center_y\": 0.0, \"scale_x\": 1.0, \"scale_y\": 1.0 }。")
		return null
	var root: Dictionary = data
	var calibration := Calibration.new()
	calibration.center_x = _read_finite(root, "center_x", out_errors)
	calibration.center_y = _read_finite(root, "center_y", out_errors)
	calibration.scale_x = _read_positive(root, "scale_x", out_errors)
	calibration.scale_y = _read_positive(root, "scale_y", out_errors)
	calibration.ls_center_x = _read_finite(root, "ls_center_x", out_errors)
	calibration.ls_center_y = _read_finite(root, "ls_center_y", out_errors)
	calibration.ls_scale_x = _read_positive(root, "ls_scale_x", out_errors)
	calibration.ls_scale_y = _read_positive(root, "ls_scale_y", out_errors)
	if out_errors.size() > before:
		return null
	return calibration


static func _median(samples: Array[Vector2], use_x: bool) -> float:
	var values: Array[float] = []
	for sample in samples:
		values.append(sample.x if use_x else sample.y)
	values.sort()
	var middle := values.size() >> 1
	if values.size() % 2 == 1:
		return values[middle]
	return (values[middle - 1] + values[middle]) * 0.5


static func _peak_to_peak(samples: Array[Vector2], use_x: bool) -> float:
	var lowest := INF
	var highest := -INF
	for sample in samples:
		var value := sample.x if use_x else sample.y
		lowest = minf(lowest, value)
		highest = maxf(highest, value)
	return highest - lowest


static func _read_finite(root: Dictionary, key: String, out: Array[ConfigError]) -> float:
	var path := "$.calibration." + key
	if not root.has(key):
		_error(out, path, &"missing_calibration_field",
			"缺少 %s 字段" % key, "补上校准值；中点通常是接近 0 的小数。")
		return 0.0
	var raw: Variant = root[key]
	if not _is_number(raw):
		_error(out, path, &"calibration_not_number",
			"%s 必须是数字，收到 %s" % [key, JSON.stringify(raw)],
			"写成不带引号的数字。")
		return 0.0
	var value := float(raw)
	if not is_finite(value):
		_error(out, path, &"calibration_not_finite",
			"%s 必须是有限数，收到 %s" % [key, JSON.stringify(raw)],
			"重新跑一次校准；NaN / Inf 不能进档案。")
		return 0.0
	return value


static func _read_positive(root: Dictionary, key: String, out: Array[ConfigError]) -> float:
	var path := "$.calibration." + key
	if not root.has(key):
		_error(out, path, &"missing_calibration_field",
			"缺少 %s 字段" % key, "补上大于 0 的量程；通常接近 1.0。")
		return 1.0
	var raw: Variant = root[key]
	if not _is_number(raw):
		_error(out, path, &"calibration_not_number",
			"%s 必须是数字，收到 %s" % [key, JSON.stringify(raw)],
			"写成不带引号的数字。")
		return 1.0
	var value := float(raw)
	if not is_finite(value) or value <= 0.0:
		_error(out, path, &"invalid_scale",
			"%s 必须是大于 0 的有限数，收到 %s" % [key, JSON.stringify(raw)],
			"改成大于 0 的数；量程为 0 会让摇杆永远居中。")
		return 1.0
	return value


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


static func _error(out: Array[ConfigError], path: String, code: StringName,
		message: String, fix_hint: String) -> void:
	out.append(ConfigError.new(path, code, message, fix_hint))
