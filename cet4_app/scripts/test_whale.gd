extends SceneTree
## 鲸鱼娘彩蛋专项：人格触发（仅 DeepSeek/仅当会话）、关键词配图、自动会话名、气泡挂图

var DB

func check(name: String, cond: bool) -> void:
	print(("PASS " if cond else "FAIL ") + name)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	DB = root.get_node("DB")
	var AiView = load("res://scripts/ai_view.gd")

	# ---- 静态判定 ----
	DB.settings["api_base"] = "https://api.deepseek.com"
	DB.settings["api_model"] = "deepseek-v4-flash"
	check("DeepSeek 判定=真", AiView._is_deepseek())
	DB.settings["api_base"] = "https://api.moonshot.cn"
	DB.settings["api_model"] = "kimi-k2.6"
	check("非 DeepSeek 判定=假", not AiView._is_deepseek())

	# ---- 触发：非 DeepSeek 时喊破喉咙也不觉醒 ----
	var v0 = AiView.new()
	v0.session = {"id": "t0", "title": "默认会话", "messages": []}
	v0._whale_on_send("你就是个大肥鱼")
	check("非 DeepSeek 不触发", not bool(v0.session.get("whale", false)))

	# ---- 触发：DeepSeek + 触发词 → 觉醒，且配图选中 whale_fat ----
	DB.settings["api_base"] = "https://api.deepseek.com"
	var v1 = AiView.new()
	v1.session = {"id": "t1", "title": "默认会话", "messages": []}
	v1._whale_on_send("你就是个大肥鱼，哼")
	check("触发词觉醒", bool(v1.session.get("whale", false)))
	check("胖→whale_fat", v1._pending_whale_img == "whale_fat")
	check("自动会话名", String(v1.session.title).begins_with("你就是个大肥鱼"))

	# ---- 人格隔离：另一个会话干干净净 ----
	var v2 = AiView.new()
	v2.session = {"id": "t2", "title": "会话 2", "messages": []}
	v2._whale_on_send("今天背什么")
	check("其他会话无人格标记", not v2.session.has("whale"))
	check("无关键词无配图", v2._pending_whale_img == "")

	# ---- 关键词 → 表情包映射 ----
	check("米饭→whale_rice", AiView._whale_image_for("先吃饭再背词，白米饭真香") == "whale_rice")
	check("token→whale_token", AiView._whale_image_for("你就是个白吃 token 的") == "whale_token")
	check("催更→whale_pressure", AiView._whale_image_for("快点给我结果") == "whale_pressure")
	check("夸→whale_smug", AiView._whale_image_for("太厉害了谢谢你") == "whale_smug")
	check("蠢→whale_stupid", AiView._whale_image_for("这也太蠢了吧") == "whale_stupid")
	check("回来→whale_back", AiView._whale_image_for("我回来了继续") == "whale_back")
	check("对比→whale_compare", AiView._whale_image_for("你比 chatgpt 差远了") == "whale_compare")
	check("休息→whale_rest", AiView._whale_image_for("你要不要休息一下") == "whale_rest")
	check("卖萌→whale_cute", AiView._whale_image_for("你好可爱啊") == "whale_cute")
	check("无关→空", AiView._whale_image_for("今天背 Day 3") == "")

	# ---- 十张表情包资源全部就位 ----
	var all_ok := true
	for k in ["whale_fat", "whale_token", "whale_rice", "whale_pressure", "whale_smug",
			"whale_stupid", "whale_back", "whale_compare", "whale_rest", "whale_cute"]:
		if not ResourceLoader.exists("res://assets/easter/%s.jpg" % k):
			all_ok = false
			print("  缺图：", k)
	check("10 张表情包资源就位", all_ok)

	# ---- 气泡挂图渲染（进树测真实 _ready + _add_bubble）----
	var v3 = AiView.new()
	v3.session = {"id": "t3", "title": "默认会话", "messages": []}
	root.add_child(v3)
	await process_frame
	await process_frame
	v3._add_bubble("assistant", "我只是个蹭白饭的肥鱼！", "", "whale_fat")
	var found_tr := false
	var stack := [v3]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is TextureRect:
			found_tr = true
			break
		for c in n.get_children():
			stack.append(c)
	check("气泡内表情包渲染", found_tr)
	v3.queue_free()

	print("== 彩蛋测试完成 ==")
	quit()
