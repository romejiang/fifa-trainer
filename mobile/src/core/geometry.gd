class_name Geometry
extends RefCounted

## 角度与向量工具：移动端唯一的角度约定出处。
##
## 本项目全局角度约定（单位：度，范围 [0, 360)）：
##   0°   = 上（朝对方球门，即球员的"正前方"）
##   90°  = 右
##   180° = 下（正后方）
##   270° = 左
## 角度增大 = 屏幕上的顺时针方向。
##
## 手柄原始坐标是 SDL / Godot 约定：x 向右为正，y 向下为正。
## 所有角度换算只在 angle_of() 里做一次，其余代码只跟上面的约定打交道。
## 五个函数全部 static：本类不持有任何状态，也不读取时钟 / 输入 / 文件。
## 行为以 desktop/padskills/geometry.py 为准；黄金夹具由
## tools/gen_geometry_golden.py 从 Python 参考重新推导，禁止手改。


static func norm_deg(angle: float) -> float:
	# 不能用 %：GDScript 对两个 float 使用 % 是解析错误；fmod 又会保留负号，
	# 让「左」（-90°）显示成负角度。fposmod 才是 Python % 的 floor-mod 语义。
	return fposmod(angle, 360.0)


static func signed_delta(a_from: float, a_to: float) -> float:
	# 与 Python 的实现逐字对应。真实区间是 [-180, 180)：
	# 正好 180° 时返回 -180（Python 的 % 是 floor-mod，不是 C 的 fmod）。
	# 不要为了迎合 Python 那边写错的文档字符串 (-180, 180] 把端点改成 +180：
	# 行为对等优先于注释对等，signed_delta(0, 180) == -180 已被黄金向量固化。
	return fposmod(a_to - a_from + 180.0, 360.0) - 180.0


static func angle_diff(a: float, b: float) -> float:
	return absf(signed_delta(a, b))


static func angle_of(x: float, y: float) -> float:
	# 居中守卫：x == 0.0 也覆盖 -0.0；没有它 atan2(0.0, -0.0) 会返回 180°，
	# 界面会把「摇杆居中」显示成「正后方」。
	if x == 0.0 and y == 0.0:
		return 0.0
	# 参数顺序仍是 atan2(y, x) 的 y 在前；公式文本恰好是 atan2(x, -y)。
	# 归一化交给 norm_deg（内部是 fposmod() 的 floor-mod 语义），不要在这里再写一次。
	return norm_deg(rad_to_deg(atan2(x, -y)))


static func magnitude(x: float, y: float) -> float:
	# 与 math.hypot 差 1 ulp 量级，比较必须带容差（1e-9 足够）。
	return sqrt(x * x + y * y)
