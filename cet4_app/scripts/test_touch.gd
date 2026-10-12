extends SceneTree
## 模拟人类触控全界面摸查 v3：push_input 真实点击事件，逐屏截图 + 断言
const OUT := "C:/Users/s/Desktop/英语/_shots/touch/"

var main
var DB
var AI
var fails := 0

func _initialize() -> void:
	call_deferred("run")

func check(name: String, cond: bool) -> void:
	if not cond:
		fails += 1
	print(("PASS " if cond else "FAIL ") + name)

func snap(name: String) -> void:
	await process_frame
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	img.save_png(OUT + name + ".png")
	print("shot " + name)

func tap(c: Control, tag := "") -> void:
	if c == null or not is_instance_valid(c):
		print("FAIL tap 目标无效 " + tag)
		fails += 1
		return
	var center := c.get_global_transform_with_canvas() * (c.size / 2.0)
	for st in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.position = center
		ev.pressed = st
		root.push_input(ev, true)
		await process_frame
		await process_frame
	print("tap " + tag)

func find_btn(root_node: Node, key: String) -> Button:
	var stack := [root_node]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is Button and String(n.text).contains(key):
			return n
		for c in n.get_children():
			stack.append(c)
	return null

func dlg_count() -> int:
	var n := 0
	for d in get_nodes_in_group("ui_dialog"):
		if is_instance_valid(d) and d.visible:
			n += 1
	return n

func close_dialogs() -> void:
	for d in get_nodes_in_group("ui_dialog"):
		if is_instance_valid(d) and d.visible:
			d.hide()
			d.queue_free()

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	DB = root.get_node("DB")
	AI = root.get_node("AI")
	close_dialogs()   # 关掉"已更新"弹窗
	print("== 主界面就绪 ==")

	# ---------- 1. AI 页：会话下拉 ----------
	main.switch_tab(3)
	await process_frame
	await process_frame
	var ai = main.content.get_child(main.content.get_child_count() - 1)
	await tap(ai.session_btn, "会话按钮")
	check("会话下拉层打开", dlg_count() == 1)
	await snap("01_session_dropdown")
	# 点选第一个会话项
	var item := find_btn(root, String(DB.sessions[0].title))
	await tap(item, "会话项")
	check("下拉层已关闭", dlg_count() == 0)

	# ---------- 2. 快捷指令管理 → 编辑弹窗 ----------
	await tap(find_btn(ai, "管理"), "管理")
	await tap(find_btn(ai, "配近义词"), "快捷指令")
	check("快捷指令编辑弹窗打开", dlg_count() == 1)
	await snap("02_quick_edit")
	await tap(find_btn(root, "取消"), "取消编辑")
	check("编辑弹窗关闭", dlg_count() == 0)
	await tap(find_btn(ai, "管理"), "退出管理")

	# ---------- 3. 模拟 AI 回复（含记忆写入）----------
	var sid := String(ai.session.id)
	AI._commit(sid, "好的，记住了。\n```json\n{\"memory_add\":[\"触控测试：记忆链路\"]}\n```", "", {})
	await process_frame
	check("记忆已写入", DB.ai_memory.has("触控测试：记忆链路"))
	check("回复落库", String(ai.session.messages[-1].content).contains("好的"))
	ai._render_messages()
	await snap("03_ai_reply")

	# ---------- 4. 模拟词库修改 ops → 预览弹窗 ----------
	AI._commit(sid, "给你加了 1 个词", "", {"add_words": [{"w": "touchtest", "p": "", "m": "n. 触控测试", "day": "自定义", "syn": [], "sim": []}]})
	await process_frame
	ai._render_messages()
	await process_frame
	var ops_btn := find_btn(ai, "确认词库修改")
	check("ops 确认按钮出现", ops_btn != null)
	await tap(ops_btn, "确认词库修改按钮")
	check("词库预览弹窗打开", dlg_count() == 1)
	await snap("04_ops_preview")
	await tap(find_btn(root, "取消"), "取消预览")
	# 清掉 mock 消息
	ai.session.messages = ai.session.messages.slice(0, ai.session.messages.size() - 2)
	DB.save_sessions()

	# ---------- 5. 词表 → 添加词条弹窗 ----------
	main.switch_tab(0)
	await process_frame
	await process_frame
	var home = main.content.get_child(main.content.get_child_count() - 1)
	home._on_seg("table")
	await process_frame
	await process_frame
	await tap(find_btn(home, "＋ 添加"), "添加词条")
	check("词条编辑弹窗打开", dlg_count() == 1)
	await snap("05_word_edit")
	await tap(find_btn(root, "取消"), "取消词条编辑")

	# ---------- 6. 设置页：AI 记忆入口 ----------
	main.switch_tab(4)
	await process_frame
	await process_frame
	var st = main.content.get_child(main.content.get_child_count() - 1)
	# 展开 AI API 组
	await tap(find_btn(st, "AI API"), "展开AI API")
	await process_frame
	await process_frame
	var mem_btn := find_btn(st, "查看记忆")
	# 按钮可能在屏幕外（设置页很长）：滚动外层滚动区把它带进可视区再点
	var st_scroll: ScrollContainer = null
	for c in st.get_children():
		if c is ScrollContainer:
			st_scroll = c
	for i in range(30):
		var r := mem_btn.get_global_rect()
		if r.position.y > 200.0 and r.end.y < 1800.0:
			break
		st_scroll.scroll_vertical += int(r.position.y - 900.0)
		await process_frame
	print("查看记忆按钮 rect=", mem_btn.get_global_rect())
	await tap(mem_btn, "查看记忆")
	check("记忆弹窗打开", dlg_count() == 1)
	await snap("06_memory")
	await tap(find_btn(root, "关闭"), "关闭记忆")
	# 清理测试记忆
	DB.memory_remove(["触控测试：记忆链路"])

	# ---------- 7. 退出弹窗（返回键链路）----------
	main._handle_back()
	await process_frame
	check("退出确认弹窗", dlg_count() == 1)
	await snap("07_exit")
	await tap(find_btn(root, "取消"), "取消退出")

	print("== 触控摸查完成 fails=%d ==" % fails)
	quit()
