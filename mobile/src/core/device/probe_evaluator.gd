class_name ProbeEvaluator
extends RefCounted

## 轴探针的纯计算部分：静止基线 → 四方向窗口 → (index, sign)。
##
## 为什么不在这里读手柄：探针屏负责采样与切窗口，本类只做「已经切好的 300 ms 窗口」
## 上的统计。没有时钟、没有 I/O、没有引擎单例 —— 同一份合成 raw 永远得到同一份结果。
##
## 三个阈值常量就是判定的全部依据，测试逐条引用：
##   MIN_DELTA   赢家轴的位移下限；低于它就是「没推够」
##   MIN_SAMPLES 窗口帧数下限；3 帧是硬底线，正常 60 Hz 的 300 ms 窗口有 18 帧
##   MIN_MARGIN  赢家与第二名的差距；两轴同时动时无法判定
##
## 判定顺序（先到先拒，原因必须具体）：
##   samples < MIN_SAMPLES   → not_enough_samples
##   |delta[w]| < MIN_DELTA  → not_enough_travel
##   margin < MIN_MARGIN     → ambiguous_axes

const MIN_DELTA := 0.5
const MIN_SAMPLES := 3
const MIN_MARGIN := 0.25
## 交叉校验用的信号干净度下限。它只是 warning：校准会覆盖量程，不阻塞继续。
const MIN_SEPARATION := 3.0


## 逐轴取中位数作为静止基线。
##
## 为什么是中位数而不是均值：蓝牙丢包重传会在静止段插入单帧尖峰，均值会被拉偏，
## 中位数不受影响。轴数取第一帧长度；短于第一帧的采样按缺失处理（该轴记 0.0）。
static func rest_from_samples(samples: Array[PackedFloat32Array]) -> PackedFloat32Array:
	var rest := PackedFloat32Array()
	if samples.is_empty():
		return rest
	var axis_count := samples[0].size()
	rest.resize(axis_count)
	for axis in axis_count:
		var values: Array[float] = []
		for sample in samples:
			if axis < sample.size():
				values.append(sample[axis])
		if values.is_empty():
			continue
		values.sort()
		var middle := values.size() >> 1
		if values.size() % 2 == 1:
			rest[axis] = values[middle]
		else:
			rest[axis] = (values[middle - 1] + values[middle]) * 0.5
	return rest


## 评估一个方向步：语义上输入是调用方已经切好的 300 ms 窗口，本函数不做滑窗。
##
## 返回的 `delta` 是**有符号**的 `delta[w]`（不是绝对值）：`sign` 由它导出，
## 质量指标与排障也读它，调用方不需要再从 raw 采样重算一遍。
##
## `margin = |delta[w]| - max(|delta[others]|)`；`separation = |delta[w]| / max(|delta[second]|, 1e-6)`。
static func evaluate_step(samples: Array[PackedFloat32Array],
		rest: PackedFloat32Array) -> Dictionary:
	var result := {
		"ok": false,
		"axis": -1,
		"sign": 0,
		"delta": 0.0,
		"samples": samples.size(),
		"margin": 0.0,
		"separation": 0.0,
		"code": &"",
		"message": "",
	}
	if samples.size() < MIN_SAMPLES:
		result["code"] = &"not_enough_samples"
		result["message"] = "采样太少：只有 %d 帧（至少要 %d 帧），请按住不动再试" % [
			samples.size(), MIN_SAMPLES]
		return result

	var axis_count := rest.size()
	if axis_count == 0:
		axis_count = samples[0].size()
	var delta := PackedFloat32Array()
	delta.resize(axis_count)
	for axis in axis_count:
		var total := 0.0
		var count := 0
		for sample in samples:
			if axis < sample.size():
				total += sample[axis]
				count += 1
		var mean := total / float(count) if count > 0 else 0.0
		var baseline := rest[axis] if axis < rest.size() else 0.0
		delta[axis] = mean - baseline

	var winner := -1
	var winner_magnitude := -1.0
	for axis in axis_count:
		var magnitude := absf(delta[axis])
		if magnitude > winner_magnitude:
			winner = axis
			winner_magnitude = magnitude
	if winner < 0:
		result["code"] = &"not_enough_travel"
		result["message"] = "位移不够：最大只有 0.000（至少要 %.1f），请把摇杆推到底" % MIN_DELTA
		return result

	var second_magnitude := 0.0
	for axis in axis_count:
		if axis != winner:
			second_magnitude = maxf(second_magnitude, absf(delta[axis]))
	var margin := winner_magnitude - second_magnitude
	var separation := winner_magnitude / maxf(second_magnitude, 1e-6)

	result["delta"] = delta[winner]
	result["margin"] = margin
	result["separation"] = separation
	if winner_magnitude < MIN_DELTA:
		result["code"] = &"not_enough_travel"
		result["message"] = "位移不够：最大只有 %.3f（至少要 %.1f），请把摇杆推到底再按住" % [
			winner_magnitude, MIN_DELTA]
		return result
	if margin < MIN_MARGIN:
		result["code"] = &"ambiguous_axes"
		result["message"] = "两轴同时动了：margin %.3f < %.2f，请只推一个方向" % [
			margin, MIN_MARGIN]
		return result

	result["ok"] = true
	result["axis"] = winner
	result["sign"] = 1 if delta[winner] > 0.0 else -1
	result["code"] = &""
	result["message"] = ""
	return result


## 四步交叉校验：上/右不同轴、上下反号、左右反号。
##
## 只消费 `axis` / `sign` / `separation` 三个键 —— 三个都由 evaluate_step 的返回字典
## 提供，本函数不重算 delta、也不从 raw 采样再推一遍，避免两边各写一份键名。
##
## warning 只有 low_separation 一条，且必须可达：赢家轴 1.0、第二名轴 0.4 时
## margin 0.6（能过 evaluate_step）而 separation 2.5 < 3.0。warning 不阻止继续
## （校准会覆盖量程），`ok` 仍为 true。
##
## 失败时不清空任何已测结果 —— 本函数是纯函数，不持有状态；是否保留进度由调用方决定。
static func validate_cross(up: Dictionary, right: Dictionary, down: Dictionary,
		left: Dictionary) -> Dictionary:
	if up["axis"] == right["axis"]:
		return _cross_fail(&"same_axis_up_right",
			"上与右落在同一根轴（%d / %d），请只推右摇杆" % [up["axis"], right["axis"]])
	if down["axis"] != up["axis"] or down["sign"] != -int(up["sign"]):
		return _cross_fail(&"vertical_not_opposed",
			"上下没有互为反号：上 (轴 %d, 符号 %d)、下 (轴 %d, 符号 %d)，请检查手柄接线" % [
				up["axis"], up["sign"], down["axis"], down["sign"]])
	if left["axis"] != right["axis"] or left["sign"] != -int(right["sign"]):
		return _cross_fail(&"horizontal_not_opposed",
			"左右没有互为反号：右 (轴 %d, 符号 %d)、左 (轴 %d, 符号 %d)，请检查手柄接线" % [
				right["axis"], right["sign"], left["axis"], left["sign"]])

	var warnings: Array[StringName] = []
	for step in [up, right, down, left]:
		if float(step["separation"]) < MIN_SEPARATION:
			warnings.append(&"low_separation")
			break
	return {"ok": true, "code": &"", "message": "", "warnings": warnings}


## 把四步结果收成 AxisMapping。
##
## rs_y 只能来自「向下」那一步：rs_x 来自 right，rs_y 来自 down。
## 禁止用 up 取反隐式推导 —— 上下接线反了必须在探针阶段被 validate_cross 抓住，
## 而不是在判定里表现成「角度差 180°」，让用户以为是自己推错了方向。
@warning_ignore("unused_parameter")
static func mapping_from_steps(up: Dictionary, right: Dictionary, down: Dictionary,
		left: Dictionary) -> AxisMapping:
	var mapping := AxisMapping.new()
	mapping.rs_x_index = int(right["axis"])
	mapping.rs_x_sign = int(right["sign"])
	mapping.rs_y_index = int(down["axis"])
	mapping.rs_y_sign = int(down["sign"])
	return mapping


static func _cross_fail(code: StringName, message: String) -> Dictionary:
	var warnings: Array[StringName] = []
	return {"ok": false, "code": code, "message": message, "warnings": warnings}
