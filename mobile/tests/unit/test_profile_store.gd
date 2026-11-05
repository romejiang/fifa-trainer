extends RefCounted

## ProfileStore 的真实 I/O 矩阵：原子写、整份丢弃、`res://` 守卫，以及首次使用的安静态。
##
## 为什么用注入路径 `user://test_profiles/controllers.json`：默认路径是真实用户档案，
## 测试既不能读也不能写它。默认路径的 `user://` 前缀另有单独断言。
##
## 每个用例前后都清理测试文件：坏档案用例会留下文件，下一条用例若读到它，
## 失败会指向错误的场景（与 test_config_store.gd 同一纪律）。

const TEST_PROFILES := "user://test_profiles/controllers.json"
const FORBIDDEN_PATH := "res://nope/controllers.json"
const FORBIDDEN_DIR := "res://nope"


func run(r) -> void:
	_clean()
	_check_roundtrip(r)
	_check_atomic_write(r)
	_check_res_guard(r)
	_check_broken_json(r)
	_check_too_large(r)
	_check_one_bad_entry_discards_all(r)
	_check_upsert_stamps_time(r)
	_check_missing_file_is_quiet(r)
	_check_clear(r)
	_clean()
	r.complete()


## 写一份完整档案 → 读回 → 逐字段相等（含 axes / calibration / quality / profile_id）。
func _check_roundtrip(r) -> void:
	_clean()
	var store := _store()
	var profile := _profile()
	r.check(store.save_all({profile.key: profile}) == OK,
		"合法档案必须保存成功")

	var loaded := store.load_all()
	r.check(int(loaded["error"]) == OK,
		"合法档案读回不得有错误码（实际 %d）" % int(loaded["error"]))
	var profiles: Dictionary = loaded["profiles"]
	r.check(profiles.has(profile.key), "读回的档案必须仍以 key 为键")
	var back: DeviceProfile = profiles.get(profile.key)
	r.check(back != null, "读回的档案必须是 DeviceProfile")
	if back == null:
		return
	r.check(back.key == profile.key, "key 必须往返一致")
	r.check(back.profile_id == "primary", "profile_id 必须往返一致（INPUT-03 预留）")
	r.check(back.layout == DeviceProfile.LAYOUT_XBOX, "layout 必须往返一致")
	r.check(back.layout_confirmed, "layout_confirmed 必须往返一致")
	r.check(back.axes != null, "axes 必须往返存在")
	if back.axes != null:
		r.check(back.axes.rs_x_index == 2, "axes.rs_x_index 必须往返一致")
		r.check(back.axes.rs_x_sign == -1, "axes.rs_x_sign 必须往返一致")
	r.check(back.calibration != null, "calibration 必须往返存在")
	if back.calibration != null:
		r.eq_float(back.calibration.scale_x, 0.98, 1e-6, "calibration.scale_x 必须往返一致")
	r.check(back.quality.has("up"), "quality 必须往返存在")
	if back.quality.has("up"):
		r.check(int(back.quality["up"]["samples"]) == 30, "quality 里的数值必须往返一致")
	r.check(back.probed_at_iso == profile.probed_at_iso, "probed_at_iso 必须往返一致")


## 原子写：成功后不得残留 .tmp。
func _check_atomic_write(r) -> void:
	_clean()
	var store := _store()
	var profile := _profile()
	r.check(store.save_all({profile.key: profile}) == OK, "原子写必须成功")
	r.check(not FileAccess.file_exists(TEST_PROFILES + ProfileStore.TEMP_SUFFIX),
		"成功后不得残留 .tmp")


## 写偏：目标在 res:// 时必须拒绝，且目录与文件都不能被创建。
func _check_res_guard(r) -> void:
	var store := ProfileStore.new(FORBIDDEN_PATH)
	var err := store.save_all({})
	r.check(err == ERR_UNAUTHORIZED,
		"写入 res:// 必须返回 ERR_UNAUTHORIZED（实际 %d）" % err)
	r.check(not FileAccess.file_exists(FORBIDDEN_PATH),
		"写入 res:// 失败后不得留下文件")
	r.check(not DirAccess.dir_exists_absolute(FORBIDDEN_DIR),
		"写入 res:// 失败后不得创建目录")


## 坏 JSON：整份丢弃、删除文件、给 notice。
func _check_broken_json(r) -> void:
	_clean()
	_write_raw(TEST_PROFILES, "{not json")
	var loaded := _store().load_all()
	var profiles: Dictionary = loaded["profiles"]
	r.check(profiles.is_empty(), "坏 JSON 必须返回空档案")
	r.check(not String(loaded["notice"]).is_empty(), "坏 JSON 必须给出 notice")
	r.check(not FileAccess.file_exists(TEST_PROFILES),
		"坏 JSON 必须被删除，避免每次启动重复提示")


## 超大：超过 MAX_BYTES 的档案在解析前就被拒绝并删除（T-04-12）。
func _check_too_large(r) -> void:
	_clean()
	_write_raw(TEST_PROFILES, "x".repeat(ProfileStore.MAX_BYTES + 1))
	var loaded := _store().load_all()
	var profiles: Dictionary = loaded["profiles"]
	r.check(profiles.is_empty(), "超大档案必须返回空档案")
	r.check(not String(loaded["notice"]).is_empty(), "超大档案必须给出 notice")
	r.check(not FileAccess.file_exists(TEST_PROFILES), "超大档案必须被删除")


## 任一条目非法 → 丢弃整份，合法的条目也不保留。
func _check_one_bad_entry_discards_all(r) -> void:
	_clean()
	var first := _profile().to_dict()
	var second := _profile().to_dict()
	# 只破坏第二条的轴序号：99 越界。
	second["axes"]["rs_x"]["index"] = 99

	var errors: Array[ConfigError] = []
	r.check(DeviceProfile.from_dict(first, errors) != null and errors.is_empty(),
		"前置：第一条必须单独合法，否则反例是空的")

	_write_raw(TEST_PROFILES, JSON.stringify({
		"schema_version": 1,
		"profiles": {"guid:good": first, "guid:bad": second},
	}))
	var loaded := _store().load_all()
	var profiles: Dictionary = loaded["profiles"]
	r.check(profiles.is_empty(),
		"任一条目 schema 非法必须整份丢弃（合法条目也不得保留，实际 %d 条）" % profiles.size())
	r.check(not String(loaded["notice"]).is_empty(), "整份丢弃必须给出 notice")
	r.check(not FileAccess.file_exists(TEST_PROFILES), "损坏档案必须被删除")


## upsert 负责填墙钟时间（秒级）；core 不读时钟。
func _check_upsert_stamps_time(r) -> void:
	_clean()
	var store := _store()
	var profile := _profile()
	profile.probed_at_iso = ""
	r.check(store.upsert(profile) == OK, "upsert 必须成功")

	var loaded := store.load_all()
	var profiles: Dictionary = loaded["profiles"]
	r.check(profiles.has(profile.key), "upsert 之后必须能按 key 找到")
	var back: DeviceProfile = profiles.get(profile.key)
	r.check(back != null and not back.probed_at_iso.is_empty(),
		"upsert 必须填入 probed_at_iso")
	if back == null:
		return
	var regex := RegEx.new()
	r.check(regex.compile("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}$") == OK,
		"时间格式正则必须能编译")
	r.check(regex.search(back.probed_at_iso) != null,
		"probed_at_iso 必须是秒级时间（实际 %s）" % back.probed_at_iso)


## 首次使用：文件不存在是安静的正常态，不是错误。
func _check_missing_file_is_quiet(r) -> void:
	_clean()
	var default_store := ProfileStore.new()
	r.check(default_store.path() == "user://profiles/controllers.json",
		"默认档案路径必须是 user://profiles/controllers.json（实际 %s）" % default_store.path())
	var store := _store()
	r.check(not FileAccess.file_exists(TEST_PROFILES), "前置：测试文件必须不存在")
	var loaded := store.load_all()
	r.check(String(loaded["notice"]) == "",
		"文件不存在时 notice 必须为空（实际 %s）" % String(loaded["notice"]))
	r.check(int(loaded["error"]) == OK,
		"文件不存在时错误码必须是 OK（实际 %d）" % int(loaded["error"]))
	var profiles: Dictionary = loaded["profiles"]
	r.check(profiles.is_empty(), "文件不存在时必须返回空档案")


## 清除：只删目标文件、幂等；`res://` 路径必须先被守卫拦下（T-04-23）。
func _check_clear(r) -> void:
	_clean()
	var store := _store()
	r.check(store.save_all({_profile().key: _profile()}) == OK, "前置：先写一份档案")
	r.check(FileAccess.file_exists(TEST_PROFILES), "前置：档案文件存在")
	r.check(store.clear() == OK, "clear() 必须成功")
	r.check(not FileAccess.file_exists(TEST_PROFILES), "clear() 之后文件必须不存在")
	r.check(store.clear() == OK, "文件不存在时 clear() 仍然是 OK（幂等）")
	r.check(not FileAccess.file_exists(TEST_PROFILES + ProfileStore.TEMP_SUFFIX),
		"clear() 不得留下 .tmp")

	var guarded := ProfileStore.new(FORBIDDEN_PATH)
	r.check(guarded.clear() == ERR_UNAUTHORIZED,
		"res:// 路径的 clear() 必须返回 ERR_UNAUTHORIZED")
	r.check(not FileAccess.file_exists(FORBIDDEN_PATH),
		"守卫失败后不得创建或删除任何 res:// 文件")


func _store() -> ProfileStore:
	return ProfileStore.new(TEST_PROFILES)


## 一份完整、合法的档案。所有字段都填上，往返断言才有东西可比。
static func _profile() -> DeviceProfile:
	var profile := DeviceProfile.new()
	profile.key = "guid:test-controller"
	profile.device_name = "Xbox Test Controller"
	profile.device_guid = "03000000-test"
	profile.profile_id = "primary"
	profile.axes = AxisMapping.new()
	profile.axes.rs_x_index = 2
	profile.axes.rs_x_sign = -1
	profile.axes.rs_y_index = 3
	profile.axes.rs_y_sign = -1
	profile.calibration = Calibration.new()
	profile.calibration.center_x = 0.01
	profile.calibration.center_y = -0.02
	profile.calibration.scale_x = 0.98
	profile.calibration.scale_y = 0.97
	profile.quality = {
		"up": {"samples": 30, "margin": 0.7, "separation": 6.0},
		"right": {"samples": 28, "margin": 0.68, "separation": 5.4},
	}
	profile.layout = DeviceProfile.LAYOUT_XBOX
	profile.layout_confirmed = true
	profile.probed_at_iso = "2026-11-05T10:00:00"
	return profile


static func _write_raw(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(text)
	file.flush()
	file.close()


func _clean() -> void:
	DirAccess.remove_absolute(TEST_PROFILES)
	DirAccess.remove_absolute(TEST_PROFILES + ProfileStore.TEMP_SUFFIX)
