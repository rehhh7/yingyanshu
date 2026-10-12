extends SceneTree
## 互传 Markdown 格式回归：切组导入（扩展/覆盖）、整库载荷、分组删除

var DB

var fails := 0
func check(name: String, cond: bool) -> void:
	print(("PASS " if cond else "FAIL ") + name)
	if not cond:
		fails += 1

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	DB = root.get_node_or_null("DB")
	if DB == null:
		print("FAIL autoload DB 未加载")
		quit(1)
		return
	var md := "# 英眼书互传\n\n# 互传测试组\nzztestapple /æ/ n. 测试苹果\nzztest banana 测试香蕉组\n\n"
	# 扩展模式导入
	var res: Dictionary = DB.import_groups_md(md, false)
	print("import: ", res)
	check("扩展导入成功", res["err"] == "")
	check("单词+1", res["added_w"] == 1)
	check("词组+1", res["added_p"] == 1)
	check("分组进词表", DB.word_groups.has("互传测试组"))
	# 重复扩展导入 → 全部判重
	var res2: Dictionary = DB.import_groups_md(md, false)
	check("重复导入单词+0", res2["added_w"] == 0)
	check("重复导入词组+0", res2["added_p"] == 0)
	# 覆盖模式：组内自定义先清空（词组被清掉），再写入新内容
	var md2 := "# 互传测试组\nzztestapple /æ/ n. 新释义\n"
	var res3: Dictionary = DB.import_groups_md(md2, true)
	check("覆盖导入成功", res3["err"] == "")
	check("覆盖后单词+1", res3["added_w"] == 1)
	check("覆盖后词组+0", res3["added_p"] == 0)
	var phrase_gone := true
	for p in DB.phrases:
		if String(p.get("sec", "")) == "互传测试组" and String(p.get("en", "")) == "zztest banana":
			phrase_gone = false
	check("覆盖清掉旧词组", phrase_gone)
	var new_meaning := false
	for w in DB.words:
		if String(w.get("w", "")) == "zztestapple" and String(w.get("m", "")) == "n. 新释义":
			new_meaning = true
	check("覆盖写入新释义", new_meaning)
	# 分组导出往返
	var exp: String = DB.export_groups_md("words", "互传测试组")
	check("导出有组头", exp.contains("# 互传测试组"))
	check("导出含词条", exp.contains("zztestapple"))
	# 整库载荷格式
	var t: String = DB.build_transfer_md()
	check("载荷有标记头", t.begins_with("# 英眼书互传"))
	# 删除分组
	DB.delete_group("words", "互传测试组")
	DB.delete_group("phrases", "互传测试组")
	check("删组后词表移除", not DB.word_groups.has("互传测试组"))
	var leftover := false
	for w in DB.words:
		if String(w.get("w", "")) == "zztestapple":
			leftover = true
	check("删组后词条清空", not leftover)
	# 分组格式检测
	check("is_groups_md 识别标记头", DB.is_groups_md("# 英眼书互传\n\n# 组A\napple 苹果\n"))
	check("is_groups_md 识别普通组头", DB.is_groups_md("前置说明\n# 组A\napple 苹果\n"))
	check("is_groups_md 不误判纯文本", not DB.is_groups_md("apple 苹果\nbanana 香蕉\n"))
	check("is_groups_md 不误判井号词", not DB.is_groups_md("#tag 标签词\n"))
	check("is_groups_md 不误判JSON", not DB.is_groups_md("{\"type\":\"cet4_backup\"}"))
	# 备份重命名 / 删除 / 批量删除（import_groups_md 每次都自动备份，此刻必有备份）
	var backups: PackedStringArray = DB.list_backups()
	check("有备份可管理", backups.size() >= 1)
	if backups.size() >= 2:
		var f1 := String(backups[0])
		var f2 := String(backups[1])
		check("默认显示名=时间名", DB.get_backup_label(f1) == f1.trim_suffix(".json"))
		check("重命名成功", DB.rename_backup(f1, "我的存档点") == "")
		check("显示名变标签", DB.get_backup_label(f1) == "我的存档点")
		check("清名恢复时间名", DB.rename_backup(f1, "") == "" and DB.get_backup_label(f1) == f1.trim_suffix(".json"))
		check("单个删除", DB.delete_backup(f2) == "" and not DB.list_backups().has(f2))
		var before: int = DB.list_backups().size()
		var picked := PackedStringArray([f1, "不存在的文件.json"])
		check("批量删除只删存在的", DB.delete_backups(picked) == 1)
		check("批量后总数-1", DB.list_backups().size() == before - 1)
	print("== 传输格式测试完成 fails=%d ==" % fails)
	quit(1 if fails > 0 else 0)
