extends SceneTree
## 主测试：v0.9.25 起内置词库为空，测试自行注入夹具数据，不再依赖任何出厂词条

var DB

func _initialize() -> void:
	call_deferred("run")

func check(name: String, cond: bool) -> void:
	print(("PASS " if cond else "FAIL ") + name)

func run() -> void:
	DB = root.get_node_or_null("DB")
	if DB == null:
		print("FAIL autoload DB 未加载")
		quit()
		return
	# 干净起点：出厂还原清空一切残留（v0.9.25 起出厂=空库）
	DB.factory_reset_library()
	check("内置词库为空", DB.words.size() == 0 and DB.phrases.size() == 0)
	check("分组为空", DB.word_groups.is_empty() and DB.phrase_groups.is_empty())

	# 注入夹具：12 词（测试组A）+ 3 词组（测试P组）
	var fx := {"add_words": [], "add_phrases": []}
	for i in range(1, 13):
		fx["add_words"].append({"w": "fxword%02d" % i, "m": "n. 夹具词%d" % i, "p": "/fx/", "syn": [], "sim": [], "day": "测试组A"})
	for i in range(1, 4):
		fx["add_phrases"].append({"sec": "测试P组", "en": "fx phrase %d" % i, "cn": "夹具词组%d" % i})
	DB.apply_ai_library_edit(fx)
	check("夹具注入", DB.words.size() == 12 and DB.phrases.size() == 3)
	check("word_groups 首位=测试组A", DB.word_groups.size() >= 1 and DB.word_groups[0] == "测试组A")
	check("phrase_groups 首位=测试P组", DB.phrase_groups.size() >= 1 and DB.phrase_groups[0] == "测试P组")
	var g1 = DB.words_in_group("测试组A")
	check("测试组A=12", g1.size() == 12)
	var res = DB.search("fxword01")
	check("搜索fxword01", res["words"].size() >= 1)

	# 星标
	var id: String = DB.word_id(g1[0])
	var before: bool = DB.is_starred("words", id)
	DB.toggle_star("words", id)
	check("星标切换", DB.is_starred("words", id) == (not before))
	DB.toggle_star("words", id)
	check("星标还原", DB.is_starred("words", id) == before)

	# 进度
	DB.mark_known("words", id, true)
	var prog = DB.group_progress("words", "测试组A")
	check("分组进度>0", prog.known >= 1)
	var s = DB.stats_summary()
	check("统计含streak", s.has("streak") and s.has("today_learned"))

	# AI 改词库 + 回滚
	var ops = {
		"add_words": [{"w": "testword_zz", "m": "n. 测试词", "p": "/test/", "syn": [], "sim": [], "day": "自定义"}],
		"add_phrases": [{"sec": "自定义", "en": "test phrase zz", "cn": "测试词组"}],
	}
	var log = DB.apply_ai_library_edit(ops)
	check("AI新增写入", log.find("testword_zz") >= 0)
	check("词库+2", DB.words.size() == 13 and DB.phrases.size() == 4)
	check("自动备份生成", DB.list_backups().size() >= 1)
	var rm = DB.apply_ai_library_edit({"remove_words": ["testword_zz"], "remove_phrases": ["test phrase zz"]})
	check("AI删除", DB.words.size() == 12 and DB.phrases.size() == 3)
	# 回滚到最新备份（= 删除操作前的快照），撤销删除恢复 13 词；
	# 注意备份只保留最近 5 份，捕获后不能再有其他写操作，否则目标会被挤掉
	var backups2 = DB.list_backups()
	check("回滚", DB.rollback_backup(backups2[0]).begins_with("已回滚"))
	check("回滚撤销删除", DB.words.size() == 13)
	# edit 接口：只合并给定字段，其余原样保留（v0.9.30 AI 修改词条/配例句）
	DB.apply_ai_library_edit({"add_words": [{"w": "editword_zz", "m": "n. 旧释义", "p": "/old/", "day": "测试组A"}],
		"add_phrases": [{"sec": "测试P组", "en": "edit phrase zz", "cn": "旧释义"}]})
	DB.apply_ai_library_edit({"edit_words": [{"w": "editword_zz", "ex": "This is editword_zz."}],
		"edit_phrases": [{"en": "edit phrase zz", "cn": "新释义"}]})
	var ew = DB.words.filter(func(w): return w.w == "editword_zz")[0]
	check("edit合并ex", String(ew.get("ex", "")) == "This is editword_zz.")
	check("edit保留旧字段", String(ew.get("m", "")) == "n. 旧释义" and String(ew.get("p", "")) == "/old/")
	var ep = DB.phrases.filter(func(p): return p.en == "edit phrase zz")[0]
	check("edit词组改释义", String(ep.get("cn", "")) == "新释义")
	var n0 = DB.words.size()
	DB.apply_ai_library_edit({"edit_words": [{"w": "ghostword_zz", "m": "n. 改转增", "ex": "Ghost."}]})
	check("edit未命中转新增", DB.words.size() == n0 + 1)
	# 清理测试数据
	DB.apply_ai_library_edit({"remove_words": ["testword_zz", "editword_zz", "ghostword_zz"], "remove_phrases": ["test phrase zz", "edit phrase zz"]})
	DB.factory_reset_library()
	check("出厂还原为空", DB.words.size() == 0 and DB.phrases.size() == 0)

	# 导入导出
	var path = DB.export_all()
	check("导出备份文件", FileAccess.file_exists(path))
	var err = DB.import_backup(FileAccess.get_file_as_string(path))
	check("导入备份", err == "")

	# 词库热更新
	var lib = {"words": [{"w": "hotupdate_zz", "m": "n. 热更新", "day": "自定义"}],
		"phrases": [{"sec": "自定义", "en": "hot phrase zz", "cn": "热更新词组"}]}
	var msg = DB.import_wordlib(JSON.stringify(lib))
	check("热更新导入", msg.begins_with("导入完成") and DB.words.size() == 1)
	DB.factory_reset_library()

	# 聊天会话
	var sess = DB.new_session("测试会话")
	sess["messages"].append({"role": "user", "content": "hi"})
	DB.save_sessions()
	var sess2 = DB.get_session(sess.id)
	check("会话保存", sess2.get("messages", []).size() == 1)
	DB.delete_session(sess.id)

	print("== 测试完成 ==")
	quit()
