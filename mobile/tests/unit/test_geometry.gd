extends RefCounted

## 几何套件：逐向量比对 Python 生成的黄金夹具，并单独钉死四个精确边界。
##
## 判据全部走 reporter 的 check / eq_float，不用 assert —— assert 在编辑器二进制
## 里会中止当前函数，在入口里直接让进程挂死（P3）。
##
## 为什么用 FileAccess.get_file_as_bytes + JSON.new().parse()：夹具是 JSON 字节，
## 读字节不会做字符串层面的意外转换；parse_string() 失败时会向 stderr 打 ERROR，
## 而 JSON.new().parse() 只返回错误码与行号。夹具体积小，一次全读没问题。
##
## 读不到 / 解析失败也必须走到 r.complete()：不带完成标记的提前返回会被 runner
## 记成「崩溃」，掩盖真正的原因（夹具缺失）。

const GOLDEN_PATH := "res://tests/fixtures/geometry_golden.json"

## roadmap 要求的跨语言容差；magnitude 用 sqrt 而非 hypot，斜向差 1 ulp。
const TOL := 1e-9


func run(r) -> void:
	var bytes := FileAccess.get_file_as_bytes(GOLDEN_PATH)
	if bytes.is_empty():
		r.check(false, "读不到几何黄金夹具：%s（运行 python3 tools/gen_geometry_golden.py 生成）" % GOLDEN_PATH)
		r.complete()
		return

	var json := JSON.new()
	if json.parse(bytes.get_string_from_utf8()) != OK:
		r.check(false, "几何黄金夹具不是合法 JSON（第 %d 行：%s）"
			% [json.get_error_line() + 1, json.get_error_message()])
		r.complete()
		return

	var data = json.data
	if not (data is Dictionary):
		r.check(false, "几何黄金夹具的根节点必须是对象")
		r.complete()
		return

	if data.has("angle_of"):
		for case in data["angle_of"]:
			r.eq_float(Geometry.angle_of(float(case["x"]), float(case["y"])),
				float(case["expected"]), TOL, "angle_of:%s" % str(case["name"]))
	else:
		r.check(false, "夹具缺少 angle_of 组")

	if data.has("norm_deg"):
		for case in data["norm_deg"]:
			r.eq_float(Geometry.norm_deg(float(case["input"])),
				float(case["expected"]), TOL, "norm_deg:%s" % str(case["input"]))
	else:
		r.check(false, "夹具缺少 norm_deg 组")

	if data.has("signed_delta"):
		for case in data["signed_delta"]:
			r.eq_float(Geometry.signed_delta(float(case["from"]), float(case["to"])),
				float(case["expected"]), TOL,
				"signed_delta(%s -> %s)" % [str(case["from"]), str(case["to"])])
	else:
		r.check(false, "夹具缺少 signed_delta 组")

	if data.has("angle_diff"):
		for case in data["angle_diff"]:
			r.eq_float(Geometry.angle_diff(float(case["from"]), float(case["to"])),
				float(case["expected"]), TOL,
				"angle_diff(%s -> %s)" % [str(case["from"]), str(case["to"])])
	else:
		r.check(false, "夹具缺少 angle_diff 组")

	if data.has("magnitude"):
		var index := 0
		for case in data["magnitude"]:
			r.eq_float(Geometry.magnitude(float(case["x"]), float(case["y"])),
				float(case["expected"]), TOL, "magnitude[%d]" % index)
			index += 1
	else:
		r.check(false, "夹具缺少 magnitude 组")

	# 居中守卫是精确分支：不是「约等于 0」，必须精确 0.0（且 -0.0 走同一条守卫）。
	r.check(Geometry.angle_of(0.0, 0.0) == 0.0, "angle_of(0,0) 必须精确为 0.0")
	r.check(Geometry.angle_of(-0.0, -0.0) == 0.0, "angle_of(-0.0,-0.0) 必须精确为 0.0")
	# 180° 端点：signed_delta 是 [-180, 180)，返回 -180；angle_diff 取绝对值后是 180。
	# 这两条一起固化同一端点的两个面，防止后人把 signed_delta「修正」成 +180。
	r.check(Geometry.signed_delta(0.0, 180.0) == -180.0,
		"signed_delta(0,180) 必须精确为 -180.0（区间是 [-180, 180)）")
	r.check(Geometry.angle_diff(0.0, 180.0) == 180.0, "angle_diff(0,180) 必须精确为 180.0")

	r.complete()
