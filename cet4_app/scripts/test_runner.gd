extends SceneTree

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
	check("words=605", DB.words.size() == 605)
	check("phrases=3366", DB.phrases.size() == 3366)
	check("word_groups 首位=手写一", DB.word_groups[0] == "手写一")
	check("word_groups 数=12", DB.word_groups.size() == 12)
	check("phrase_groups 数=48", DB.phrase_groups.size() == 48)
	check("phrase_groups 首位=P1", DB.phrase_groups[0] == "P1")
	var g1 = DB.words_in_group("手写一")
	check("手写一=121", g1.size() == 121)
	var res = DB.search("trivial")
	check("搜索trivial", res["words"].size() >= 1)

	# 星标
	var id: String = DB.word_id(g1[0])
	var before: bool = DB.is_starred("words", id)
	DB.toggle_star("words", id)
	check("星标切换", DB.is_starred("words", id) == (not before))
	DB.toggle_star("words", id)
	check("星标还原", DB.is_starred("words", id) == before)

	# 进度
	DB.mark_known("words", id, true)
	var prog = DB.group_progress("words", "手写一")
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
	check("词库+2", DB.words.size() == 606 and DB.phrases.size() == 3367)
	var backups = DB.list_backups()
	check("自动备份生成", backups.size() >= 1)
	var rm = DB.apply_ai_library_edit({"remove_words": ["testword_zz"], "remove_phrases": ["test phrase zz"]})
	check("AI删除", DB.words.size() == 605 and DB.phrases.size() == 3366)
	check("回滚", DB.rollback_backup(backups[0]).begins_with("已回滚"))
	check("回滚后词数606", DB.words.size() == 606)
	# 清理测试数据
	DB.apply_ai_library_edit({"remove_words": ["testword_zz"], "remove_phrases": ["test phrase zz"]})
	DB.factory_reset_library()
	check("出厂还原", DB.words.size() == 605 and DB.phrases.size() == 3366)

	# 导入导出
	var path = DB.export_all()
	check("导出备份文件", FileAccess.file_exists(path))
	var err = DB.import_backup(FileAccess.get_file_as_string(path))
	check("导入备份", err == "")

	# 词库热更新
	var lib = {"words": [{"w": "hotupdate_zz", "m": "n. 热更新", "day": "自定义"}],
		"phrases": [{"sec": "自定义", "en": "hot phrase zz", "cn": "热更新词组"}]}
	var msg = DB.import_wordlib(JSON.stringify(lib))
	check("热更新导入", msg.begins_with("导入完成") and DB.words.size() == 606)
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
