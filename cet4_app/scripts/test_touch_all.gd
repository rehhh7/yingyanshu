extends SceneTree
## 全量触控遍历 v4：InputEventScreenTouch 模拟真实手指（经全局死区/惯性逻辑），
## 5 个 Tab + 学习/听写覆盖层的每个可见按钮逐一点击，弹窗自动收捡；
## 另测两件回归：① 按钮上起手的滑动不得触发点击（issue #16318 死区）② 滑动确实滚得动。
const OUT := "user://_shots/touch_all/"   # 产物目录（符号路径，不写本机绝对路径）

var main
var DB
var AI
var fails := 0
var taps := 0
var skipped: Array = []

# 单点可能破坏数据的按钮：跳过（它们的确认链路在 test_touch.gd 已覆盖）
const SKIP_KEYS := ["删除", "回滚到", "恢复出厂", "清空", "☀", "🌙", "写入选中", "确定写入"]
# 弹窗收捡时的优先按钮顺序
const CLOSE_KEYS := ["取消", "关闭", "知道了", "不了", "确定", "好"]

func _initialize() -> void:
	call_deferred("run")

func check(name: String, cond: bool) -> void:
	if not cond:
		fails += 1
	print(("PASS " if cond else "FAIL ") + name)

func frames(n: int) -> void:
	for i in range(n):
		await process_frame

func snap(name: String) -> void:
	await frames(3)
	if DisplayServer.get_name() == "headless":
		return   # 无渲染管线，跳过截图（截图走 test_shots.gd 窗口模式）
	var tex := root.get_texture()
	if tex == null:
		return
	var img := tex.get_image()
	if img == null:
		return
	img.save_png(OUT + name + ".png")
	print("shot " + name)

func _finger(pos: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.position = pos
	ev.pressed = pressed
	root.push_input(ev, true)

func tap(c: Control, tag := "") -> void:
	if c == null or not is_instance_valid(c):
		print("FAIL tap 目标无效 " + tag)
		fails += 1
		return
	var center := c.get_global_transform_with_canvas() * (c.size / 2.0)
	_finger(center, true)
	await frames(2)
	_finger(center, false)
	await frames(3)
	taps += 1
	print("tap " + tag)

func drag(from: Vector2, dy: float, steps := 6) -> void:
	_finger(from, true)
	await frames(2)
	for i in range(steps):
		var ev := InputEventScreenDrag.new()
		ev.index = 0
		ev.position = from + Vector2(0, dy * float(i + 1) / steps)
		ev.relative = Vector2(0, dy / steps)
		ev.velocity = Vector2(0, dy / steps * 60)
		root.push_input(ev, true)
		await process_frame
	_finger(from + Vector2(0, dy), false)
	await frames(3)

func find_btn(root_node: Node, key: String) -> Button:
	var stack := [root_node]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is CanvasItem and not n.is_visible_in_tree():
			continue
		if n is Button and String(n.text).contains(key):
			return n
		for c in n.get_children():
			stack.append(c)
	return null

func collect_buttons(n: Node, out: Array) -> void:
	if n is CanvasItem and not n.is_visible_in_tree():
		return
	if n is Button and not n.disabled:
		out.append(n)
	for c in n.get_children():
		collect_buttons(c, out)

func dlg_count() -> int:
	var n := 0
	for d in get_nodes_in_group("ui_dialog"):
		if is_instance_valid(d) and d.visible:
			n += 1
	return n

func force_close_dialogs() -> void:
	for d in get_nodes_in_group("ui_dialog"):
		if is_instance_valid(d) and d.visible:
			d.hide()
			d.queue_free()

func settle_dialogs() -> void:
	for i in range(6):
		await frames(2)
		if dlg_count() == 0:
			return
		var b: Button = null
		for k in CLOSE_KEYS:
			b = find_btn(root, k)
			if b != null:
				break
		if b == null:
			force_close_dialogs()
			return
		await tap(b, "收捡弹窗:" + b.text)
	if dlg_count() > 0:
		force_close_dialogs()

func scroll_into_view(b: Button, sv: ScrollContainer) -> void:
	if sv == null:
		return
	var vh := root.get_visible_rect().size.y
	for i in range(40):
		if not is_instance_valid(b):
			return
		var r := b.get_global_rect()
		if r.position.y > 80.0 and r.end.y < vh - 80.0:
			return
		sv.scroll_vertical += int(r.position.y - vh * 0.4)
		await process_frame

func page_scroll(view: Control) -> ScrollContainer:
	for c in view.get_children():
		if c is ScrollContainer:
			return c
	return null

func should_skip(text: String) -> bool:
	for k in SKIP_KEYS:
		if text.contains(k):
			return true
	return false

func walk_view(tag: String) -> void:
	# 点按钮可能触发界面重建（分段切换/管理态/换词表），view 每轮从 main.content 重新获取；点过的按文本去重
	var done := {}
	for round in range(12):
		if not is_instance_valid(main):
			return
		var view: Control = main.content.get_child(main.content.get_child_count() - 1)
		var sv := page_scroll(view)
		var btns: Array = []
		collect_buttons(view, btns)
		if round == 0:
			print("-- %s 共 %d 个按钮 --" % [tag, btns.size()])
		var pending: Array = []
		for b in btns:
			var t := String(b.text).strip_edges()
			if should_skip(t):
				if not done.has(t):
					done[t] = true
					skipped.append("%s:%s" % [tag, t])
				continue
			if not done.has(t):
				pending.append(b)
		if pending.is_empty():
			return
		for b in pending:
			if not is_instance_valid(b) or not b.is_visible_in_tree():
				continue
			var t := String(b.text).strip_edges()
			done[t] = true
			await scroll_into_view(b, sv)
			if not is_instance_valid(b):
				continue
			await tap(b, "%s:%s" % [tag, t.left(14)])
			await settle_dialogs()
			if not is_instance_valid(main):
				return

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	print("截图输出目录：" + ProjectSettings.globalize_path(OUT))
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await frames(3)
	DB = root.get_node("DB")
	AI = root.get_node("AI")
	# v0.9.25 起出厂空库：学习覆盖层遍历需要分组，空库时注入演示夹具
	if DB.word_groups.is_empty():
		DB.apply_ai_library_edit({"add_words": [
			{"w": "fxdemo", "m": "n. 演示词", "p": "/demo/", "syn": [], "sim": [], "day": "演示组"},
			{"w": "fxdemo2", "m": "v. 演示词二", "p": "/demo2/", "syn": [], "sim": [], "day": "演示组"}]})
	force_close_dialogs()   # 关掉"本次更新"弹窗
	print("== 主界面就绪，开始全量触控遍历 ==")

	# ---------- 回归①：按钮上起手的滑动不得触发按钮（死区防误触）----------
	main.switch_tab(4)
	await frames(12)   # 设置页分帧构建，等它建完
	var st: Control = main.content.get_child(main.content.get_child_count() - 1)
	var sv4 := page_scroll(st)
	var grp := find_btn(st, "数据管理")
	if grp != null:
		await scroll_into_view(grp, sv4)   # 屏幕外的按钮推送事件打不中，先滚进可视区
		await tap(grp, "展开数据管理组")   # 分组默认折叠，先展开
		await frames(3)
	var victim := find_btn(st, "导出备份")
	check("找到滑动受害者按钮", victim != null)
	if victim == null:
		print("== 遍历中止：受害者按钮不存在 ==")
		quit()
		return
	var fired := [false]
	victim.pressed.connect(func(): fired[0] = true)
	await scroll_into_view(victim, sv4)
	var y0: int = sv4.scroll_vertical if sv4 != null else 0
	var c: Vector2 = victim.get_global_transform_with_canvas() * (victim.size / 2.0)
	await drag(c, -400.0)
	check("滑动未误触按钮", fired[0] == false)
	check("滑动确实滚动了页面", sv4 == null or sv4.scroll_vertical != y0)

	# ---------- 五个 Tab 全按钮遍历 ----------
	for i in range(5):
		main.switch_tab(i)
		await frames(12)   # 等分帧构建完成
		walk_view("tab%d_%s" % [i, main.tabs[i]])
		await snap("walk_tab%d" % i)

	# ---------- 学习覆盖层 ----------
	print("main 有效=", is_instance_valid(main), " tab=", main.current_tab if is_instance_valid(main) else -1)
	main.switch_tab(0)
	await frames(3)
	main.open_study("words", DB.word_groups[0])
	print("open_study 后即刻 overlay=", main.overlay)
	await frames(3)
	print("3 帧后 overlay=", main.overlay)
	var study: Control = main.overlay if is_instance_valid(main) else null
	if study == null:
		main.open_study("words", DB.word_groups[0])   # 有延迟调用清掉了覆盖层：重开一次
		await frames(3)
		study = main.overlay
		print("重开后 overlay=", study)
	check("学习覆盖层打开", study != null)
	if study != null:
		var sbtns: Array = []
		collect_buttons(study, sbtns)
		for b in sbtns:
			if is_instance_valid(b) and not should_skip(String(b.text)):
				await tap(b, "学习:%s" % String(b.text).left(14))
				await settle_dialogs()
		await snap("walk_study")
		if is_instance_valid(main):
			main._on_overlay_back()
		await frames(3)

	# ---------- 听写覆盖层 ----------
	main.open_dictation("words", DB.word_groups[0])
	await frames(3)
	var dv: Control = main.overlay
	check("听写覆盖层打开", dv != null)
	var dbtns: Array = []
	collect_buttons(dv, dbtns)
	for b in dbtns:
		if is_instance_valid(b) and not should_skip(String(b.text)):
			await tap(b, "听写:%s" % String(b.text).left(14))
			await settle_dialogs()
	await snap("walk_dictation")
	main._on_overlay_back()
	await frames(3)

	# ---------- 回归②：主题切换（场景整建链路）----------
	main.switch_tab(4)
	await frames(12)
	var th_btn := find_btn(root, "☀")
	if th_btn == null:
		th_btn = find_btn(root, "🌙")
	check("找到主题按钮", th_btn != null)
	await tap(th_btn, "主题切换")
	await frames(40)   # 幕布动画 + 场景重建
	var new_main = null
	for ch in root.get_children():
		if ch.has_method("switch_tab"):
			new_main = ch
	check("主题切换后场景重建成功", new_main != null)
	main = new_main
	if main != null:
		var back_btn := find_btn(root, "☀")
		if back_btn == null:
			back_btn = find_btn(root, "🌙")
		await tap(back_btn, "主题切回")
		await frames(40)
		for ch in root.get_children():
			if ch.has_method("switch_tab"):
				main = ch

	# ---------- 退出弹窗链路 ----------
	if main != null:
		main._handle_back()
		await frames(2)
		check("退出确认弹窗", dlg_count() == 1)
		await tap(find_btn(root, "取消"), "取消退出")

	print("== 全量触控遍历完成：共点击 %d 次，跳过危险按钮 %d 个，fails=%d ==" % [taps, skipped.size(), fails])
	for s in skipped:
		print("skip " + s)
	quit()
