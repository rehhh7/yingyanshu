extends Control
## 根界面：顶栏 + 内容区 + Tab 导航（竖屏底部横排 / 横屏左侧竖排，平板限宽居中）

const HomeView := preload("res://scripts/home_view.gd")
const StarView := preload("res://scripts/star_view.gd")
const StatsView := preload("res://scripts/stats_view.gd")
const AIView := preload("res://scripts/ai_view.gd")
const SettingsView := preload("res://scripts/settings_view.gd")
const StudyView := preload("res://scripts/study_view.gd")
const DictationView := preload("res://scripts/dictation_view.gd")

const MAX_CONTENT_W := 1750.0   # （已停用，保留注释）宽屏由多列网格自适应填充

var bg: ColorRect
var wallpaper: TextureRect
var scrim: ColorRect
var root_vbox: VBoxContainer
var body: HBoxContainer
var content: Control
var tab_bar: BoxContainer
var tab_panel: PanelContainer
var top_panel: PanelContainer
var title_label: Label
var tabs := ["学习", "生词", "统计", "AI", "设置"]
var current_tab := 0
var overlay: Control = null
var current_view: Control = null
static var _last_tab := 0     # 重载场景后回到原来的页面（设置里调滑块不再跳回首页）

func _ready() -> void:
	UI.full_rect(self)
	# 双保险：禁止系统返回键直接退出（我们自己处理逐级返回 + 双击退出）
	ProjectSettings.set_setting("application/config/quit_on_go_back", false)
	# 全局默认字体（中文字体子集；开启加粗时用 FontVariation 模拟粗体）
	var f: Font = load("res://assets/NotoSansSC-subset.ttf")
	if f:
		if bool(DB.settings.get("font_bold", false)):
			var fv := FontVariation.new()
			fv.base_font = f
			fv.variation_embolden = 0.55
			f = fv
		ThemeDB.fallback_font = f
		var th := Theme.new()
		th.default_font = f
		theme = th
	bg = ColorRect.new()
	UI.full_rect(bg)
	add_child(bg)
	# 自定义壁纸层（默认隐藏）
	wallpaper = TextureRect.new()
	UI.full_rect(wallpaper)
	wallpaper.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wallpaper.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	wallpaper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wallpaper)
	# 壁纸压暗层，保证可读性
	scrim = ColorRect.new()
	UI.full_rect(scrim)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)
	apply_wallpaper()

	root_vbox = VBoxContainer.new()
	UI.full_rect(root_vbox)
	root_vbox.add_theme_constant_override("separation", 0)
	add_child(root_vbox)

	# 顶栏
	top_panel = PanelContainer.new()
	root_vbox.add_child(top_panel)
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 16)
	top_panel.add_child(th)
	title_label = UI.label("英眼书", 40, Color.WHITE)
	th.add_child(title_label)
	var stretch := Control.new()
	stretch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(stretch)
	var theme_btn := UI.button("", Color.TRANSPARENT, Color.WHITE, 52)
	theme_btn.custom_minimum_size = Vector2(128, 128)
	theme_btn.name = "ThemeBtn"
	theme_btn.pressed.connect(_on_theme_toggle)
	th.add_child(theme_btn)

	# 主体区（横屏时左侧放导航栏）
	body = HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	root_vbox.add_child(body)

	# 内容区
	content = Control.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.clip_contents = true
	content.resized.connect(_fit_current_view)

	# Tab 导航
	tab_bar = BoxContainer.new()
	tab_bar.vertical = false
	tab_bar.add_theme_constant_override("separation", 8)
	tab_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	tab_panel = PanelContainer.new()
	tab_panel.add_child(tab_bar)
	for i in tabs.size():
		var b := UI.button(tabs[i], Color.TRANSPARENT, Color.WHITE, 30)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_vertical = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_tab.bind(i))
		tab_bar.add_child(b)

	get_viewport().size_changed.connect(_relayout)
	_relayout()
	switch_tab(_last_tab)
	call_deferred("_maybe_show_whats_new")
	# 主题切换幕布：新界面就绪后，幕布继续从左往右扫出，露出新主题（无黑/白闪帧）
	if _curtain != null and is_instance_valid(_curtain):
		var curtain := _curtain
		_curtain = null
		var w := maxf(size.x, get_viewport().get_visible_rect().size.x)
		var tw := curtain.create_tween()
		tw.tween_interval(0.08)   # 让新界面先渲染一两帧再揭开
		tw.tween_property(curtain, "position:x", w, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		tw.tween_callback(func():
			curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
			curtain.visible = false
			get_tree().create_timer(1.2).timeout.connect(curtain.queue_free))   # 让粒子飞完再释放

## 更新后首次打开：弹"本次更新内容"（只弹一次）
func _maybe_show_whats_new() -> void:
	if String(DB.settings.get("seen_version", "")) == DB.VERSION:
		return
	DB.settings["seen_version"] = DB.VERSION
	DB.save_settings()
	var latest := DB.changelog_text(true)
	if latest == "":
		return
	var p := UI.palette()
	var sh := UI.sheet(self, "已更新到 v" + DB.VERSION, "知道了", "")
	var lbl := UI.label(latest, 28, p.text, true)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sh["body"].add_child(lbl)

## 应用自定义壁纸（user://wallpaper.png），无则隐藏
## 压暗层按主题选色：深色主题罩黑纱、浅色主题罩米白纱——
## 浅色主题配深色壁纸时黑纱压不住，深字落在深图上会整体消失（ readability 优先，壁纸隐约可见即可）
func apply_wallpaper() -> void:
	var path := String(DB.settings.get("wallpaper", ""))
	if path != "" and FileAccess.file_exists(path):
		var img := Image.new()
		if img.load(path) == OK:
			wallpaper.texture = ImageTexture.create_from_image(img)
			wallpaper.visible = true
			scrim.visible = true
			var p := UI.palette()
			if DB.settings.get("theme_dark", true):
				scrim.color = Color(0, 0, 0, 0.45)
			else:
				scrim.color = Color(p.bg, 0.62)   # 米白纱：任何深色壁纸上深字都可读
			return
	wallpaper.visible = false
	scrim.visible = false

func _is_landscape() -> bool:
	var s := get_viewport().get_visible_rect().size
	return s.x > s.y

func _relayout() -> void:
	# 摘掉再按方向放回
	if tab_panel.get_parent():
		tab_panel.get_parent().remove_child(tab_panel)
	if content.get_parent():
		content.get_parent().remove_child(content)
	if _is_landscape():
		tab_bar.vertical = true
		tab_panel.custom_minimum_size = Vector2(170, 0)
		body.add_child(tab_panel)
		body.add_child(content)
	else:
		tab_bar.vertical = false
		tab_panel.custom_minimum_size = Vector2.ZERO
		body.add_child(content)
		root_vbox.add_child(tab_panel)
	call_deferred("_fit_current_view")
	call_deferred("apply_theme")

func _fit_current_view() -> void:
	if current_view == null or not is_instance_valid(current_view):
		return
	# 全幅填充（宽屏由多列网格负责利用空间），两侧留小边距
	UI.full_rect(current_view)
	current_view.offset_left = 12.0
	current_view.offset_right = -12.0
	current_view.grow_horizontal = Control.GROW_DIRECTION_BOTH

func apply_theme() -> void:
	var p := UI.palette()
	bg.color = p.bg
	top_panel.add_theme_stylebox_override("panel", UI.style_box(p.panel, 0))
	title_label.add_theme_color_override("font_color", p.text)
	var theme_btn := top_panel.find_child("ThemeBtn", true, false) as Button
	theme_btn.text = "☀" if DB.settings.get("theme_dark", true) else "🌙"
	theme_btn.add_theme_color_override("font_color", p.text)
	tab_panel.add_theme_stylebox_override("panel", UI.style_box(p.panel, 0))
	for i in tab_bar.get_child_count():
		var b := tab_bar.get_child(i) as Button
		var active := i == current_tab
		b.add_theme_color_override("font_color", p.accent if active else p.sub)
		b.add_theme_stylebox_override("normal", UI.style_box(p.panel2 if active else p.panel, 12))
		b.add_theme_stylebox_override("hover", UI.style_box(p.panel2, 12))
		b.add_theme_stylebox_override("pressed", UI.style_box(p.panel2, 12))

static var _curtain: ColorRect = null   # 主题切换幕布（挂在树根，跨场景重载存活）

func _on_theme_toggle() -> void:
	# 深浅主题切换：幕布扫过式过渡（无截图回读，不卡顿）
	DB.settings["theme_dark"] = not DB.settings.get("theme_dark", true)
	DB.save_settings()
	_fade_theme_reload()

## 主题切换：新主题色的幕布从左扫入→盖全屏时重载场景→新场景里幕布继续扫出
## 旧方案是整屏截图 GPU 回读，手机上必卡；幕布只是一个 ColorRect，零回读开销
func _fade_theme_reload() -> void:
	var vs := get_viewport().get_visible_rect().size
	var curtain := ColorRect.new()
	curtain.color = UI.palette().bg   # 设置已切换，palette 拿到的是新主题底色
	curtain.size = vs
	curtain.position = Vector2(-vs.x, 0)
	curtain.mouse_filter = Control.MOUSE_FILTER_STOP   # 过渡期间挡住触摸
	get_tree().root.add_child(curtain)
	_curtain = curtain
	_spawn_particles(curtain)
	var tw := curtain.create_tween()
	tw.tween_property(curtain, "position:x", 0.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		if get_tree().current_scene != null:
			get_tree().reload_current_scene()
		else:
			# 兜底：场景是手动实例化的（无 current_scene），就地替换
			var inst: Control = load("res://scenes/main.tscn").instantiate()
			var parent := get_parent()
			var idx := get_index()
			parent.add_child(inst)
			parent.move_child(inst, idx)
			queue_free())

## 主题切换粒子：前缘连续喷射的拖尾 + 全屏慢速漂浮光点（低配模式跳过，幕布扫过已足够反馈）
func _spawn_particles(host: Control) -> void:
	if UI.low_end():
		return
	var dark: bool = DB.settings.get("theme_dark", true)
	var col := Color(1, 1, 1, 0.9) if dark else Color(0.30, 0.26, 0.20, 0.8)
	var vs := get_viewport().get_visible_rect().size
	# 1) 揭示边高速拖尾：挂在滑动的截图左缘上，边移动边喷，拖出尾迹
	var fast := CPUParticles2D.new()
	fast.amount = 110
	fast.lifetime = 0.55
	fast.explosiveness = 0.0          # 连续发射，跟随移动的揭示边
	fast.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	fast.emission_rect_extents = Vector2(8, vs.y * 0.5)
	fast.position = Vector2(host.size.x, host.size.y * 0.5)   # 幕布右缘 = 揭示前缘
	fast.direction = Vector2(1, 0)
	fast.spread = 26.0
	fast.initial_velocity_min = 320.0
	fast.initial_velocity_max = 1000.0
	fast.gravity = Vector2.ZERO
	fast.damping_min = 60.0
	fast.damping_max = 160.0
	fast.scale_amount_min = 3.0
	fast.scale_amount_max = 9.0
	fast.color = col
	host.add_child(fast)
	fast.emitting = true
	get_tree().create_timer(0.42).timeout.connect(func():
		if is_instance_valid(fast):
			fast.emitting = false)   # 扫完即停喷，已有粒子继续飞完
	# 2) 全屏漂浮光点：缓慢上飘 + 阻尼，营造"散落"感
	var soft := CPUParticles2D.new()
	soft.amount = 70
	soft.lifetime = 1.6
	soft.one_shot = true
	soft.explosiveness = 0.3          # 在 lifetime 前 30% 内陆续喷出
	soft.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	soft.emission_rect_extents = Vector2(vs.x * 0.45, vs.y * 0.48)
	soft.position = Vector2(vs.x * 0.45, vs.y * 0.5)
	soft.direction = Vector2(0, -1)
	soft.spread = 180.0
	soft.initial_velocity_min = 30.0
	soft.initial_velocity_max = 150.0
	soft.gravity = Vector2(0, -36)
	soft.damping_min = 24.0
	soft.damping_max = 70.0
	soft.scale_amount_min = 2.0
	soft.scale_amount_max = 6.5
	soft.color = Color(col, 0.55)
	host.add_child(soft)
	soft.emitting = true

func _on_tab(i: int) -> void:
	switch_tab(i)

func switch_tab(i: int) -> void:
	current_tab = i
	_last_tab = i
	_clear_content()
	title_label.text = "英眼书"
	var view: Control
	match i:
		0: view = HomeView.new()
		1: view = StarView.new()
		2: view = StatsView.new()
		3: view = AIView.new()
		4: view = SettingsView.new()
	view.set_meta("main", self)
	current_view = view
	content.add_child(view)
	call_deferred("_fit_current_view")
	apply_theme()
	UI.pop_in(view)

func _clear_content() -> void:
	for c in content.get_children():
		c.queue_free()
	overlay = null
	current_view = null

## 打开学习界面（覆盖层）
func open_study(kind: String, group: String) -> void:
	var v := StudyView.new()
	v.kind = kind
	v.group = group
	_push_overlay(v, group)

## 打开听写界面
func open_dictation(kind: String, group: String) -> void:
	var v := DictationView.new()
	v.kind = kind
	v.group = group
	_push_overlay(v, "听写 · " + group)

func _push_overlay(v: Control, title: String) -> void:
	_clear_content()
	overlay = v
	title_label.text = title
	current_view = v
	content.add_child(v)
	call_deferred("_fit_current_view")
	v.back_requested.connect(_on_overlay_back)
	UI.pop_in(v)

func _on_overlay_back() -> void:
	switch_tab(current_tab)

# ---------------- 全局触控滑动（手指拖动 = 滚轮，松手带惯性缓停） ----------------
var _touch := {"active": false, "moved": false, "sx": 0.0, "sy": 0.0, "cancel": false, "guard": false}
const TOUCH_DEADZONE := 28.0   # 滚动死区：位移超阈值才接管滚动（否则页面乱飘）
const TAP_CANCEL_DIST := 10.0  # 点击取消线：位移超 10px 本次手势判定为滑动，抬起时取消这次点击（用户规则）
var _touch_sv: ScrollContainer = null   # 按下时缓存目标滚动区，拖动期间不重复全树扫描
var _fling_sv: ScrollContainer = null
var _fling_v := 0.0
var _samples: Array = []   # 最近触摸点 [毫秒, y]

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch.active = true
			_touch.moved = false
			_touch.cancel = false
			UI.touch_scrolled = false   # 新一次触摸开始，重置滑动标志（背板等抬起时判定用）
			_touch.sx = event.position.x
			_touch.sy = event.position.y
			_fling_v = 0.0
			_fling_sv = null
			_samples = [[Time.get_ticks_msec(), event.position.y]]
			# 手指落在文本框/滑块/输入行上时不接管滚动（划选文字、拖滑块由它们自己处理）；
			# 但 10px 取消规则对它们同样生效——屏幕上位移超 10px 的滑动手势，松手落在按钮上一律不触发
			_touch.guard = _textedit_at(event.position) or _slider_or_lineedit_at(event.position)
			_touch_sv = null if _touch.guard else _scroll_at(event.position)
		else:
			# 吞掉抬起的两种情形：① 发生过滚动（并启动惯性）② 10px 规则判定为滑动且松手落在按钮上
			# ——按钮收不到这次抬起，点击取消；滑动永远是第一层，主动点击才算点击
			if _touch.moved or (_touch.cancel and _buttonish_at(event.position)):
				get_viewport().set_input_as_handled()
				if _touch.moved:
					_start_fling()
			_touch.active = false
			_touch_sv = null
	elif event is InputEventScreenDrag and _touch.active:
		# 用户规则：以 touchstart 为基准，屏幕上位移超 10px = 滑动，取消本次点击（无豁免区）
		if not _touch.cancel \
				and Vector2(_touch.sx, _touch.sy).distance_to(event.position) > TAP_CANCEL_DIST:
			_touch.cancel = true
			UI.touch_scrolled = true
		var sv := _touch_sv
		if sv == null or not is_instance_valid(sv):
			return   # 起点在文本框/滑块/空白：不接管滚动，但上面的 10px 判定已生效
		if not _touch.moved and Vector2(_touch.sx, _touch.sy).distance_to(event.position) < TOUCH_DEADZONE:
			return   # 死区内不滚动：轻微抖动页面不飘
		_touch.moved = true
		UI.touch_scrolled = true
		sv.scroll_vertical -= int(event.relative.y)
		_fling_sv = sv
		_samples.append([Time.get_ticks_msec(), event.position.y])
		if _samples.size() > 8:
			_samples.pop_front()
		get_viewport().set_input_as_handled()

## 松手时根据最近滑动速度给滚动区一个惯性初速度
func _start_fling() -> void:
	if _fling_sv == null or _samples.size() < 2:
		return
	var first: Array = _samples.front()
	var last: Array = _samples.back()
	var dt: float = (last[0] - first[0]) / 1000.0
	if dt <= 0.01:
		return
	var vy: float = (last[1] - first[1]) / dt   # 手指速度（视口坐标/秒）
	_fling_v = clampf(-vy, -6000.0, 6000.0)  # 滚动方向与手指相反
	if absf(_fling_v) < 120.0:
		_fling_v = 0.0

func _process(dt: float) -> void:
	if _fling_sv != null and is_instance_valid(_fling_sv) and absf(_fling_v) > 30.0:
		var before := _fling_sv.scroll_vertical
		_fling_sv.scroll_vertical += int(_fling_v * dt)
		_fling_v *= exp(-4.5 * dt)   # 摩擦衰减，缓慢停下
		# 顶到上下边界就停
		if _fling_sv.scroll_vertical == before and absf(_fling_v) < 400.0:
			_fling_v = 0.0
	else:
		_fling_v = 0.0

func _scroll_at(pos: Vector2) -> ScrollContainer:
	var found: Array = []
	_collect_scrolls(self, pos, found)
	if found.is_empty():
		return null
	return found.back()   # 最上层（弹窗里的滚动区在最后）

## 手指位置是否有「内容比框长、可以滚」的文本框
func _textedit_at(pos: Vector2) -> bool:
	return _find_textedit(self, pos) != null

## 滑块/输入行命中：不接管它们的滚动（拖字号滑块、划选文字是它们自己的事）
func _slider_or_lineedit_at(pos: Vector2) -> bool:
	return _find_slider_or_lineedit(self, pos) != null

## 抬起位置是否落在按钮类控件上（Button/胶囊勾选行都是 BaseButton）：
## 10px 取消规则只拦截「按钮的点击」，滑块和文本框自己的抬起照常放行
func _buttonish_at(pos: Vector2) -> bool:
	return _find_buttonish(self, pos) != null

func _find_buttonish(n: Node, pos: Vector2) -> Control:
	if n is CanvasItem and not n.is_visible_in_tree():
		return null
	if n is BaseButton and (n as Control).get_global_rect().has_point(pos):
		return n
	for c in n.get_children():
		var r := _find_buttonish(c, pos)
		if r != null:
			return r
	return null

func _find_slider_or_lineedit(n: Node, pos: Vector2) -> Control:
	if n is CanvasItem and not n.is_visible_in_tree():
		return null
	if (n is Slider or n is LineEdit) and (n as Control).get_global_rect().has_point(pos):
		return n
	for c in n.get_children():
		var r := _find_slider_or_lineedit(c, pos)
		if r != null:
			return r
	return null

func _find_textedit(n: Node, pos: Vector2) -> TextEdit:
	if n is CanvasItem and not n.is_visible_in_tree():
		return null
	if n is TextEdit and n.get_global_rect().has_point(pos):
		var vsb := (n as TextEdit).get_v_scroll_bar()
		if vsb != null and vsb.max_value > vsb.page + 1:
			return n
	for c in n.get_children():
		var r := _find_textedit(c, pos)
		if r != null:
			return r
	return null

func _collect_scrolls(n: Node, pos: Vector2, out: Array) -> void:
	if n is CanvasItem and not n.is_visible_in_tree():
		return
	if n is ScrollContainer and n.get_global_rect().has_point(pos):
		out.append(n)
	for c in n.get_children():
		_collect_scrolls(c, pos, out)

# ---------------- 系统返回键 ----------------
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		get_viewport().set_input_as_handled()
		_handle_back()

func _unhandled_input(event: InputEvent) -> void:
	# 桌面调试用 Esc 模拟返回键（安卓上返回键会同时发按键事件，这里必须跳过，
	# 否则同一次按压被执行两遍 = 直接触发"双击退出"）
	if OS.has_feature("android"):
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_handle_back()

var _last_handle_ms := -1000   # 返回键去重
var _exit_dialog: Control = null

func _handle_back() -> void:
	# 去重：部分机型/系统版本一次按压会投递两次返回事件（按下+抬起，见引擎 issue #123454），
	# 400ms 内的重复触发直接忽略，避免"按一次就退出"
	var now0 := Time.get_ticks_msec()
	if now0 - _last_handle_ms < 400:
		return
	_last_handle_ms = now0
	# 1) 有系统窗口弹窗先关（AI 预览等 ConfirmationDialog）
	var wins: Array = []
	_collect_windows(self, wins)
	for i in range(wins.size() - 1, -1, -1):
		var w: Window = wins[i]
		if is_instance_valid(w) and w.visible:
			w.hide()
			return
	# 1.5) iOS 风格确认弹窗（ui_dialog 分组，含退出确认框本身）：返回键 = 取消
	var dlgs := get_tree().get_nodes_in_group("ui_dialog")
	for i in range(dlgs.size() - 1, -1, -1):
		var d: Control = dlgs[i]
		if is_instance_valid(d) and d.visible:
			UI.dismiss_dialog(d)
			return
	# 2) 覆盖层（学习/听写）返回上一级
	if overlay != null and is_instance_valid(overlay):
		_on_overlay_back()
		return
	# 3) 主界面：弹 iOS 风格确认框退出（不依赖双击计时，杜绝误退）
	_exit_dialog = UI.confirm_dialog(self, "退出应用", "确定要退出英眼书吗？",
		func(): get_tree().quit(), "退出", "取消", true)

func _collect_windows(n: Node, out: Array) -> void:
	if n is Window and n != get_window():
		out.append(n)
	for c in n.get_children():
		_collect_windows(c, out)
