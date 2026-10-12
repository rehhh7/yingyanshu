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
	print("== 传输格式测试完成 fails=%d ==" % fails)
	quit(1 if fails > 0 else 0)
