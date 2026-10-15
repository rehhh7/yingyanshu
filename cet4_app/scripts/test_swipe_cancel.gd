extends SceneTree
## 10px 取消规则专项（v0.9.32 用户规则：以 touchstart 为基准，屏幕上位移超 10px 即取消按钮点击，
## 不按起点区域豁免；但滑块/文本框自己的抬起不拦截）：
## A. 按钮上按下、滑 15px、松手仍在按钮上 → 不触发
## B. 文本框上按下、滑 40px、松手落在按钮上 → 不触发（旧版豁免区的漏网之鱼）
## C. 原地按下抬起（0 位移）→ 正常触发
## D. 滑块上拖 30px、松手在滑块上 → 滑块值正常改变（抬起不拦非按钮控件）

var fails := 0

func check(name: String, cond: bool) -> void:
	print(("PASS " if cond else "FAIL ") + name)
	if not cond:
		fails += 1

func _initialize() -> void:
	call_deferred("run")

func _finger(pos: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.position = pos
	ev.pressed = pressed
	root.push_input(ev, true)

func _drag_to(from: Vector2, to: Vector2, steps := 5) -> void:
	_finger(from, true)
	await process_frame
	await process_frame
	for i in range(steps):
		var ev := InputEventScreenDrag.new()
		ev.index = 0
		ev.position = from.lerp(to, float(i + 1) / steps)
		ev.relative = (to - from) / steps
		root.push_input(ev, true)
		await process_frame
	_finger(to, false)
	await process_frame
	await process_frame
	await process_frame

func _drag_continue(from: Vector2, to: Vector2, steps := 5) -> void:
	# 已按住的情况下继续拖动并松手（配合前面已 _finger(from, true) 使用）
	for i in range(steps):
		var ev := InputEventScreenDrag.new()
		ev.index = 0
		ev.position = from.lerp(to, float(i + 1) / steps)
		ev.relative = (to - from) / steps
		root.push_input(ev, true)
		await process_frame
	_finger(to, false)

func _tap(pos: Vector2) -> void:
	_finger(pos, true)
	await process_frame
	await process_frame
	_finger(pos, false)
	await process_frame
	await process_frame
	await process_frame

func _center(c: Control) -> Vector2:
	return c.get_global_transform_with_canvas() * (c.size / 2.0)

func run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in range(12):
		await process_frame
	var tabs: Array = main.tab_bar.get_children()
	var settings_tab: Control = tabs[4]
	var ai_tab: Control = tabs[3]

	# C 先做（基线）：原地 tap 设置 tab → 正常切换
	await _tap(_center(settings_tab))
	check("C 原地点击正常触发", main.current_tab == 4)
	for i in range(8):
		await process_frame

	# A：设置 tab 上按下、按钮内滑 15px、松手 → 不切换（从设置滑回别处再试）
	await _tap(_center(ai_tab))
	for i in range(8):
		await process_frame
	check("C2 切到AI页", main.current_tab == 3)
	await _drag_to(_center(settings_tab), _center(settings_tab) + Vector2(0, 15))
	check("A 按钮内滑15px不触发", main.current_tab == 3)

	# B：AI 输入框(TextEdit)上按下、滑 40px、松手落在设置 tab 上 → 不切换
	var ai_view = main.current_view
	var te: TextEdit = ai_view.input
	await _drag_to(_center(te), _center(settings_tab))
	check("B 文本框起手滑40px落按钮不触发", main.current_tab == 3)

	# D：设置页字号滑块拖动 30px → 值正常变化（抬起不拦滑块）
	await _tap(_center(settings_tab))
	var slider: Slider = null
	for i in range(120):   # 设置页分帧构建，轮询等滑块出现
		await process_frame
		var v = main.current_view
		if v != null:
			slider = _find_slider(v)
			if slider != null:
				break
	check("D 滑块就位", slider != null)
	if slider != null:
		var pos := _center(slider)
		_finger(pos, true)
		await process_frame
		await process_frame
		var v_press: float = slider.value   # 按下跳到触点位置（落点值随持久化设置浮动，以此为准）
		await _drag_continue(pos, pos + Vector2(200, 0))
		await process_frame
		await process_frame
		check("D 滑块拖动值变化", slider.value > v_press)

	print("== 手势取消专项完成 fails=%d ==" % fails)
	quit(1 if fails > 0 else 0)

func _find_slider(n: Node) -> Slider:
	if n is CanvasItem and not n.is_visible_in_tree():
		return null
	if n is Slider:
		return n
	for c in n.get_children():
		var r = _find_slider(c)
		if r != null:
			return r
	return null
