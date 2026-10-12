extends SceneTree
## 截图验收：依次渲染各页面保存 PNG 到 _shots/

const OUT := "C:/Users/s/Desktop/英语/_shots/"

func _initialize() -> void:
	call_deferred("run")

func snap(name: String) -> void:
	await process_frame
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	img.save_png(OUT + name + ".png")
	print("shot " + name)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	for i in range(5):
		main.switch_tab(i)
		await snap("tab%d_%s" % [i, main.tabs[i]])

	# 词表模式
	main.switch_tab(0)
	await process_frame
	await process_frame
	var home = main.content.get_child(main.content.get_child_count() - 1)
	home._on_seg("table")
	await snap("home_table")

	# 搜索：先抓拍「正在整理单词」转圈遮罩，再抓结果列表
	home._on_search("ab")
	await snap("search_loading")
	await create_timer(0.8).timeout
	await snap("search_results")
	home._on_search("")
	await create_timer(0.5).timeout

	# 学习卡片 正面/背面
	main.open_study("words", "手写一")
	await snap("study_card_front")
	main.overlay._flip()
	await create_timer(0.4).timeout   # 等翻面淡入淡出动画播完再截
	await snap("study_card_back")
	main.overlay._toggle_mode()
	await snap("study_list")
	main._on_overlay_back()

	# 词组卡片
	main.open_study("phrases", "P1")
	await snap("study_phrase")
	main._on_overlay_back()

	# 听写
	main.open_dictation("words", "Day 11")
	await snap("dictation")
	main._on_overlay_back()

	# AI 页：注入假消息看气泡排版（含思考链折叠块）
	main.switch_tab(3)
	await process_frame
	await process_frame
	var ai = main.content.get_child(main.content.get_child_count() - 1)
	ai.session["messages"] = [
		{"role": "user", "content": "给生词组配近义词"},
		{"role": "assistant", "content": "好的，以下是近义词：\n1. trivial → insignificant（不重要的）\n2. occurrence → incident（事件）",
			"reasoning": "用户要近义词。生词组里有 trivial 和 occurrence，先想词性，再给最常用的四级近义词……"},
	]
	ai._render_messages()
	await snap("ai_chat")

	# 浅色主题（米白）
	var db = root.get_node("DB")
	db.settings["theme_dark"] = false
	db.save_settings()
	main.queue_free()
	var main2 = load("res://scenes/main.tscn").instantiate()
	root.add_child(main2)
	await process_frame
	await process_frame
	main2.switch_tab(0)
	await snap("light_home")
	main2.switch_tab(4)
	await snap("light_settings")

	# 横屏适配：多列网格 + 学习卡片横排
	db.settings["theme_dark"] = true
	db.save_settings()
	root.size = Vector2i(1152, 540)
	await process_frame
	await process_frame
	main2.queue_free()
	var main3 = load("res://scenes/main.tscn").instantiate()
	root.add_child(main3)
	await process_frame
	await process_frame
	await process_frame
	main3.switch_tab(0)
	await snap("land_home")
	main3.open_study("words", "手写一")
	await snap("land_study")
	main3._on_overlay_back()
	main3.switch_tab(4)
	await snap("land_settings")

	# 主题切换过渡验收：截图滑开 + 粒子（中段应看到旧画面半滑开，无黑白闪帧）
	main3._on_theme_toggle()
	await snap("theme_transition")
	await create_timer(1.0).timeout
	await snap("theme_done")

	# iOS 风格退出确认弹窗
	var main4 = null
	for c in root.get_children():
		if c.has_method("_handle_back"):
			main4 = c
	if main4 != null:
		main4._handle_back()
		await snap("exit_dialog")

	print("== 截图完成 ==")
	quit()
