extends Node
## 截图验收：依次渲染各页面保存 PNG 到 _shots/
## 运行：godot --path . scenes/test_shots.tscn --resolution 540x1152（不能用 -s：全局类编译早于 autoload 注册，DB 标识符解析失败）

const OUT := "C:/Users/s/Desktop/英语/_shots/"

func _ready() -> void:
	call_deferred("run")

func snap(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_tree().root.get_texture().get_image()
	img.save_png(OUT + name + ".png")
	print("shot " + name)

## 关掉所有弹窗（更新提示等），避免遮挡截图
func _dismiss_dialogs() -> void:
	for c in get_tree().root.get_children():
		if c.is_in_group("ui_dialog"):
			UI.dismiss_dialog(c)
	await get_tree().process_frame
	await get_tree().process_frame

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	# v0.9.25 起内置词库为空：注入演示夹具供学习/听写/搜索页面截图
	var db0 = get_tree().root.get_node("DB")
	db0.factory_reset_library()
	var fx := {"add_words": [], "add_phrases": []}
	var demo_words := [["trivial", "/ˈtrɪviəl/", "adj. 琐碎的；不重要的"],
		["occurrence", "/əˈkɜːrəns/", "n. 发生；发生的事情"],
		["precaution", "/prɪˈkɔːʃn/", "n. 预防措施"],
		["abandon", "/əˈbændən/", "v. 放弃；抛弃"],
		["absorb", "/əbˈzɔːb/", "v. 吸收；理解"]]
	for w in demo_words:
		fx["add_words"].append({"w": w[0], "p": w[1], "m": w[2], "day": "示例一组", "syn": [], "sim": []})
	for i in range(1, 7):
		fx["add_words"].append({"w": "demoword%d" % i, "p": "/demo/", "m": "n. 演示词%d" % i, "day": "Day 11", "syn": [], "sim": []})
	for i in range(1, 5):
		fx["add_phrases"].append({"sec": "示例P组", "en": "demo phrase %d" % i, "cn": "演示词组%d" % i})
	db0.apply_ai_library_edit(fx)
	var main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	_dismiss_dialogs()

	for i in range(5):
		main.switch_tab(i)
		await snap("tab%d_%s" % [i, main.tabs[i]])

	# 词表模式
	main.switch_tab(0)
	await get_tree().process_frame
	await get_tree().process_frame
	var home = main.content.get_child(main.content.get_child_count() - 1)
	home._on_seg("table")
	await snap("home_table")

	# 搜索：先抓拍「正在整理单词」转圈遮罩，再抓结果列表
	home._on_search("ab")
	await snap("search_loading")
	await get_tree().create_timer(0.8).timeout
	await snap("search_results")
	home._on_search("")
	await get_tree().create_timer(0.5).timeout

	# 学习卡片 正面/背面
	main.open_study("words", "示例一组")
	await snap("study_card_front")
	main.overlay._flip()
	await get_tree().create_timer(0.4).timeout   # 等翻面淡入淡出动画播完再截
	await snap("study_card_back")
	main.overlay._toggle_mode()
	await snap("study_list")
	main._on_overlay_back()

	# 词组卡片
	main.open_study("phrases", "示例P组")
	await snap("study_phrase")
	main._on_overlay_back()

	# 听写
	main.open_dictation("words", "Day 11")
	await snap("dictation")
	main._on_overlay_back()

	# AI 页：注入假消息看气泡排版（含思考链折叠块）
	main.switch_tab(3)
	await get_tree().process_frame
	await get_tree().process_frame
	_dismiss_dialogs()
	var ai = main.content.get_child(main.content.get_child_count() - 1)
	ai.session["messages"] = [
		{"role": "user", "content": "给生词组配近义词"},
		{"role": "assistant", "content": "好的，以下是近义词：\n1. trivial → insignificant（不重要的）\n2. occurrence → incident（事件）",
			"reasoning": "用户要近义词。生词组里有 trivial 和 occurrence，先想词性，再给最常用的四级近义词……"},
	]
	ai._render_messages()
	await snap("ai_chat")

	# 浅色主题（米白）
	var db = get_tree().root.get_node("DB")
	db.settings["theme_dark"] = false
	db.save_settings()
	main.queue_free()
	var main2 = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main2)
	await get_tree().process_frame
	await get_tree().process_frame
	main2.switch_tab(0)
	await snap("light_home")
	main2.switch_tab(4)
	await snap("light_settings")

	# 横屏适配：多列网格 + 学习卡片横排
	db.settings["theme_dark"] = true
	db.save_settings()
	get_tree().root.size = Vector2i(1152, 540)
	await get_tree().process_frame
	await get_tree().process_frame
	main2.queue_free()
	var main3 = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main3)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	main3.switch_tab(0)
	await snap("land_home")
	main3.open_study("words", "示例一组")
	await snap("land_study")
	main3._on_overlay_back()
	main3.switch_tab(4)
	await snap("land_settings")

	# 主题切换过渡动画会 reload_current_scene（本测试场景也会被重载 → 脚本重跑），
	# 场景模式下无法验收过渡动画，跳过（过渡动画此前已人工验收）

	# iOS 风格退出确认弹窗
	var main4 = main3
	main4._handle_back()
	await snap("exit_dialog")

	# ============ v0.9.18 新增功能验收 ============
	# 关掉退出确认弹窗
	for c in get_tree().root.get_children():
		if c.is_in_group("ui_dialog"):
			UI.dismiss_dialog(c)
	await get_tree().process_frame
	# 互传弹窗：验证居中（修复挂进 VBox 被挤到底部的 bug）
	main4.switch_tab(4)
	await get_tree().process_frame
	await get_tree().process_frame
	LanSyncDialog.open(main4)
	await snap("lansync_centered")
	for c in get_tree().root.get_children():
		if c is LanSyncDialog:
			c._close()
	await get_tree().process_frame
	# 设置页：备份列表（点按回滚/长按菜单/批量管理）——滚到底部让回滚区可见
	var settings = main4.content.get_child(main4.content.get_child_count() - 1)
	var db2 = get_tree().root.get_node("DB")
	db2.backup_libraries("截图验收测试备份")
	settings._rebuild_backup_list()
	var sc: ScrollContainer = null
	for c in settings.get_children():
		if c is ScrollContainer:
			sc = c
	# 展开「词库回滚与重置」折叠组（截图用：直接把 body 设为可见）
	settings._rb_list.get_parent().visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	if sc != null:
		sc.scroll_vertical = 999999
	await get_tree().process_frame
	await snap("settings_backups")
	# 批量管理模式
	settings._rb_batch = true
	settings._rebuild_backup_list()
	await get_tree().process_frame
	if sc != null:
		sc.scroll_vertical = 999999
	await get_tree().process_frame
	await snap("settings_backups_batch")
	settings._rb_batch = false
	settings._rebuild_backup_list()
	# 备份长按菜单（sheet 弹窗）
	settings._backup_menu(db2.list_backups()[0])
	await snap("backup_menu")
	for c in get_tree().root.get_children():
		if c.is_in_group("ui_dialog"):
			UI.dismiss_dialog(c)
	await get_tree().process_frame
	# 本地导入：分组/互传 Markdown 的选择弹窗（扩展/覆盖二选一）
	var demo_md := "# 英眼书互传\n\n# 验收组A\nzzshotapple /æ/ n. 截图苹果\nzzshot banana 截图香蕉组\n\n# 验收组B\nzzshotcat /kæt/ n. 截图猫\n"
	var tmp := TextEdit.new()
	get_tree().root.add_child(tmp)
	tmp.text = demo_md
	settings._group_import_flow(tmp)
	await snap("group_import_sheet")
	for c in get_tree().root.get_children():
		if c.is_in_group("ui_dialog"):
			UI.dismiss_dialog(c)
	tmp.queue_free()
	await get_tree().process_frame

	# ============ 操作指南用图：新用户视角（竖屏） ============
	get_tree().root.size = Vector2i(540, 1152)
	await get_tree().process_frame
	await get_tree().process_frame
	# 空库主页指引（新用户首次看到的样子）
	db2.factory_reset_library()
	main4.switch_tab(0)
	await get_tree().process_frame
	await get_tree().process_frame
	await snap("guide_home_empty")
	# 设置 → 数据管理 导入区（展开分组并滚到导入按钮）
	main4.switch_tab(4)
	await get_tree().process_frame
	await get_tree().process_frame
	var settings2 = main4.content.get_child(main4.content.get_child_count() - 1)
	# 设置页分帧构建：轮询等「数据管理」分组头出现再点开
	var header: Button = null
	for i in range(40):
		for n in settings2.find_children("*", "Button", true, false):
			if String(n.text).contains("数据管理"):
				header = n
				break
		if header != null:
			break
		await get_tree().process_frame
	if header != null:
		header.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var sc2: ScrollContainer = null
	for c in settings2.get_children():
		if c is ScrollContainer:
			sc2 = c
	# 滚到「拍照识图导入」按钮进入视野
	var target: Control = null
	for n in settings2.find_children("*", "Button", true, false):
		if String(n.text).contains("拍照识图导入"):
			target = n
			break
	if sc2 != null and target != null:
		var want: float = target.global_position.y - sc2.global_position.y - 200.0
		sc2.scroll_vertical = int(clampf(sc2.scroll_vertical + want, 0.0, sc2.get_v_scroll_bar().max_value))
	await get_tree().process_frame
	await get_tree().process_frame
	await snap("guide_import_area")

	print("== 截图完成 ==")
	get_tree().quit()
