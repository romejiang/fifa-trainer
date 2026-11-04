extends RefCounted

## 覆盖层纯语义矩阵：七条整体丢弃 / 稀疏合并规则逐条钉死。
##
## 为什么 base 用最小字典而不是真实配置：这是纯函数测试，规则只有七条。
## 用真实配置会把「合并语义」和「校验语义」混在一起，失败时分不清是谁的错。
##
## 每条 check 的 label 都是场景描述，失败日志不需要回头读代码。

const HASH := "aaaa"


func run(r) -> void:
	_check_valid_sparse(r)
	_check_missing_schema(r)
	_check_schema_too_new(r)
	_check_base_changed(r)
	_check_hash_case_insensitive(r)
	_check_unknown_skill(r)
	_check_unknown_key(r)
	_check_base_unchanged(r)
	_check_whitelist_keys(r)
	r.complete()


## 1. 合法稀疏覆盖：只写 enabled，其余字段原样保留。
func _check_valid_sparse(r) -> void:
	var overlay := _overlay()
	overlay["skills"] = {"A": {"enabled": false}}
	var result := OverlayMerge.merge(_base(), overlay, HASH)
	r.check(result.applied, "合法稀疏覆盖必须被标记为已应用")
	r.check(result.data["skills"][0]["enabled"] == false,
		"稀疏覆盖的 enabled=false 必须写入")
	r.check(result.discarded_reason == &"",
		"合法覆盖不得带丢弃原因（实际 %s）" % result.discarded_reason)
	r.check(result.notice.is_empty(), "合法覆盖不得给 notice（实际 %s）" % result.notice)
	r.check(result.warnings.is_empty(), "合法覆盖不得产生 warning（实际 %d 条）" % result.warnings.size())


## 2. 缺 schema_version：整体丢弃，data 等于 base。
func _check_missing_schema(r) -> void:
	var base := _base()
	var before := JSON.stringify(base)
	var result := OverlayMerge.merge(base, {"base_sha256": HASH, "skills": {}}, HASH)
	r.check(result.discarded_reason == &"overlay_schema_invalid",
		"缺 schema_version 必须整体丢弃（实际 %s）" % result.discarded_reason)
	r.check(not result.applied, "缺 schema_version 时不得应用任何覆盖")
	r.check(JSON.stringify(result.data) == before, "丢弃时 data 必须逐字等于 base")
	r.check(not result.notice.is_empty(), "整体丢弃必须给用户一句 notice")


## 3. schema_version 过新：当前版本不猜未来版本的语义。
func _check_schema_too_new(r) -> void:
	var overlay := _overlay()
	overlay["schema_version"] = 2
	var result := OverlayMerge.merge(_base(), overlay, HASH)
	r.check(result.discarded_reason == &"overlay_schema_too_new",
		"schema_version=2 必须整体丢弃（实际 %s）" % result.discarded_reason)
	r.check(not result.applied, "schema 过新时不得应用任何覆盖")


## 4. base 摘要不匹配：整体丢弃，notice 逐字等于用户看到的那句话。
func _check_base_changed(r) -> void:
	var overlay := _overlay()
	overlay["skills"] = {"A": {"enabled": false}}
	var result := OverlayMerge.merge(_base(), overlay, "bbbb")
	r.check(result.discarded_reason == &"overlay_base_changed",
		"base 摘要不匹配必须整体丢弃（实际 %s）" % result.discarded_reason)
	r.check(result.notice == "配置已更新，已丢弃自定义按键设置。",
		"hash 不匹配的 notice 必须是约定原文（实际 %s）" % result.notice)
	r.check(not result.applied, "hash 不匹配时不得应用任何覆盖")
	r.check(result.data["skills"][0]["enabled"] == true,
		"hash 不匹配时 base 的 enabled 必须保持原值")


## 5. 摘要大小写不同但内容相同：必须视为匹配，不能误丢。
func _check_hash_case_insensitive(r) -> void:
	var overlay := _overlay()
	overlay["base_sha256"] = "AAAA"
	overlay["skills"] = {"A": {"enabled": false}}
	var result := OverlayMerge.merge(_base(), overlay, HASH)
	r.check(result.discarded_reason == &"",
		"摘要大小写不同不得触发丢弃（实际 %s）" % result.discarded_reason)
	r.check(result.applied, "摘要大小写不同仍然必须应用覆盖")
	r.check(result.data["skills"][0]["enabled"] == false,
		"摘要大小写不同时 enabled=false 仍必须生效")


## 6. 未知 skill 名：只记 warning，其余合法条目照常生效。
func _check_unknown_skill(r) -> void:
	var overlay := _overlay()
	overlay["skills"] = {
		"不存在的动作": {"enabled": false},
		"A": {"enabled": false},
	}
	var result := OverlayMerge.merge(_base(), overlay, HASH)
	r.check(result.warnings.size() == 1,
		"未知动作必须产生一条 warning（实际 %d 条）" % result.warnings.size())
	if result.warnings.size() == 1:
		r.check(result.warnings[0].code == &"overlay_skill_unknown",
			"未知动作的 warning 码必须是 overlay_skill_unknown（实际 %s）" % result.warnings[0].code)
	r.check(result.applied, "未知动作不得影响同批次合法条目生效")
	r.check(result.data["skills"][0]["enabled"] == false,
		"同批次里合法 skill 的覆盖必须生效")


## 7. 未知键：只记 warning，白名单之外的字段（尤其 params）绝不写入。
func _check_unknown_key(r) -> void:
	var overlay := _overlay()
	overlay["skills"] = {"A": {"params": {"min_angle": 10}}}
	var result := OverlayMerge.merge(_base(), overlay, HASH)
	r.check(result.warnings.size() == 1,
		"未知键必须产生一条 warning（实际 %d 条）" % result.warnings.size())
	if result.warnings.size() == 1:
		r.check(result.warnings[0].code == &"overlay_key_unknown",
			"未知键的 warning 码必须是 overlay_key_unknown（实际 %s）" % result.warnings[0].code)
	r.check(result.data["skills"][0]["params"]["min_angle"] == 150.0,
		"params 里的阈值不得被覆盖层修改")
	r.check(result.data["skills"][0]["params"].size() == 1,
		"未知键 params 不得往原字典里塞任何字段")
	r.check(not result.applied, "只有未知键时不得标记为已应用")


## 8. 深拷贝：调用者的 base 在 merge 之后逐字不变。
func _check_base_unchanged(r) -> void:
	var base := _base()
	var before := JSON.stringify(base)
	var overlay := _overlay()
	overlay["skills"] = {"A": {"enabled": false, "required_button": "LB"}}
	var result := OverlayMerge.merge(base, overlay, HASH)
	r.check(result.applied, "前置条件：这份覆盖必须被应用")
	r.check(JSON.stringify(base) == before, "merge 不得修改调用者传入的 base")
	r.check(result.data["skills"][0]["required_button"] == "LB",
		"深拷贝出来的副本必须带上覆盖值")


## 9. 白名单三个键各自单独覆盖都能生效，且不碰其它字段。
func _check_whitelist_keys(r) -> void:
	var cases := [
		["enabled", false],
		["required_button", "LB"],
		["button_mode", "any"],
	]
	for item in cases:
		var overlay := _overlay()
		overlay["skills"] = {"A": {item[0]: item[1]}}
		var result := OverlayMerge.merge(_base(), overlay, HASH)
		r.check(result.applied, "白名单键 %s 必须能单独生效" % item[0])
		r.check(result.data["skills"][0][item[0]] == item[1],
			"白名单键 %s 的值必须被写入" % item[0])
		r.check(result.data["skills"][0]["params"]["min_angle"] == 150.0,
			"白名单键 %s 不得顺带修改 params" % item[0])


static func _base() -> Dictionary:
	return {
		"skills": [
			{
				"name": "A",
				"enabled": true,
				"required_button": "RB",
				"button_mode": "all",
				"params": {"min_angle": 150.0},
			},
			{
				"name": "B",
				"enabled": true,
				"required_button": null,
				"button_mode": "any",
				"params": {"min_angle": 10.0},
			},
		],
	}


static func _overlay() -> Dictionary:
	return {"schema_version": 1, "base_sha256": HASH, "skills": {}}
