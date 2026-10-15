class_name UI
extends RefCounted
## 主题色板 + 控件工厂

static func full_rect(c: Control) -> void:
	## 可靠的全幅填充（set_anchors_preset 在 4.7 运行时会保留旧偏移，有坑）
	c.anchor_left = 0.0
	c.anchor_top = 0.0
	c.anchor_right = 1.0
	c.anchor_bottom = 1.0
	c.offset_left = 0.0
	c.offset_top = 0.0
	c.offset_right = 0.0
	c.offset_bottom = 0.0
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.grow_vertical = Control.GROW_DIRECTION_BOTH

static func palette() -> Dictionary:
	if DB.settings.get("theme_dark", true):
		return {
			"bg": Color("121417"), "panel": Color("1E2228"), "panel2": Color("262B33"),
			"text": Color("E8EAED"), "sub": Color("9AA0A6"),
			"accent": Color("60A5FA"), "star": Color("FBBF24"),
			"ok": Color("34D399"), "danger": Color("F87171"),
			"border": Color("333A45"),
		}
	# 米白色浅色主题
	return {
		"bg": Color("F6F1E7"), "panel": Color("FFFCF4"), "panel2": Color("EFE8D9"),
		"text": Color("2B2620"), "sub": Color("7C7466"),
		"accent": Color("3B82F6"), "star": Color("D97706"),
		"ok": Color("0E9F6E"), "danger": Color("E02424"),
		"border": Color("E2DAC7"),
	}

static func ui_scale() -> float:
	## 全局控件缩放系数（设置页可调，0.7~1.6）
	return clampf(float(DB.settings.get("ui_scale", 1.0)), 0.7, 1.6)

## 全局滑动状态（main.gd 在拖动超过死区时置 true）：按下即触发的交互（弹窗背板等）
## 必须等「抬起且未滑动」才执行——滑动永远优先，主动点击才算点击
static var touch_scrolled := false

static func font_scale() -> float:
	## 字体缩放系数（设置页可调）
	return clampf(float(DB.settings.get("font_scale", 1.0)), 0.7, 1.8)

static func low_end() -> bool:
	## 低配模式：关阴影/粒子保 60fps。未手动设置时按 CPU 核数自动判断（≤4 核视为低配）
	if not DB.settings.has("low_end_mode"):
		DB.settings["low_end_mode"] = OS.get_processor_count() <= 4
	return bool(DB.settings.get("low_end_mode", false))

static func style_box(color: Color, radius := 16, border_c := Color.TRANSPARENT, border_w := 0, shadow := true) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	if border_w > 0:
		sb.set_border_width_all(border_w)
		sb.border_color = border_c
	# 拟物化：不透明底色加柔和投影（透明按钮和列表卡片不投影，长列表投影太吃性能；低配模式全局关投影保帧率）
	if shadow and not low_end() and color.a > 0.05:
		sb.shadow_color = Color(0, 0, 0, 0.22 if DB.settings.get("theme_dark", true) else 0.10)
		sb.shadow_size = 6
		sb.shadow_offset = Vector2(0, 3)
	return sb

static func pop_in(c: Control) -> void:
	## 入场动画：淡入（切换界面/打开覆盖层时用）
	if not c.is_inside_tree():
		return
	c.modulate.a = 0.0
	var tw := c.create_tween()
	tw.tween_property(c, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

static func pop(c: Control, strength := 1.35) -> void:
	## 小动作反馈：中心弹跳（TRANS_BACK 过冲回弹），收藏/确认时用
	if not c.is_inside_tree():
		return
	c.pivot_offset = c.size / 2.0
	var tw := c.create_tween()
	tw.tween_property(c, "scale", Vector2.ONE * strength, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

static func fade_in(c: Control, delay := 0.0) -> void:
	## 列表项渐入：可带 stagger 延迟，批量入场有流水感
	if not c.is_inside_tree():
		return
	c.modulate.a = 0.0
	var tw := c.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(c, "modulate:a", 1.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

static func label(text: String, size := 32, color := Color.WHITE, wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", int(size * font_scale()))
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 不挡点击（卡片翻面等）
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

static func button(text: String, color: Color, text_color := Color.WHITE, size := 30) -> Button:
	var sc := ui_scale()
	var fs := font_scale()
	var b := Button.new()
	b.text = text
	b.clip_text = true   # 大字体/大按钮时文字钳在按钮内，不画出屏幕外
	# 注意：clip_text=true 后按钮最小宽度不再包含文字宽度，胶囊按钮会塌成空条（文字全被裁掉）。
	# 所以用全局字体实测文字宽，连左右留白一起写进最小宽度，把「按文字自动撑宽」的行为补回来
	var fpx := int(size * sc * fs)
	var min_w := 0.0
	var fnt: Font = ThemeDB.fallback_font
	if fnt != null:
		min_w = fnt.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fpx).x + 64.0 * sc
	b.custom_minimum_size = Vector2(min_w, 92 * sc * clampf(fs, 0.9, 1.3))
	if min_w > 0.0:
		# 大量调用方随后整体重写 custom_minimum_size = Vector2(0, H) 只为调高度，
		# 会把文字宽度冲掉（AI 页快捷指令胶囊文字全消失就是这么来的）——进树时再兜底一次
		b.ready.connect(func():
			if is_instance_valid(b) and b.custom_minimum_size.x < min_w:
				b.custom_minimum_size.x = min_w)
	b.add_theme_font_size_override("font_size", fpx)
	b.add_theme_color_override("font_color", text_color)
	b.add_theme_stylebox_override("normal", style_box(color, 14))
	b.add_theme_stylebox_override("hover", style_box(color.lightened(0.08), 14))
	# 拟物按压感：按下变暗且阴影收小（用更小的圆角模拟下沉）
	var ps := style_box(color.darkened(0.12), 14)
	ps.shadow_size = 2
	ps.shadow_offset = Vector2(0, 1)
	b.add_theme_stylebox_override("pressed", ps)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	# 按压过渡动画：按下微缩、松开回弹（只动 visual scale，不影响布局）
	b.resized.connect(func(): if is_instance_valid(b): b.pivot_offset = b.size / 2.0)
	b.button_down.connect(func():
		vibrate(10)   # 全 App 按钮按下轻震（设置里可关）
		if is_instance_valid(b):
			var tw := b.create_tween()
			tw.tween_property(b, "scale", Vector2(0.94, 0.94), 0.08).set_trans(Tween.TRANS_QUAD))
	b.button_up.connect(func():
		if is_instance_valid(b):
			var tw := b.create_tween()
			tw.tween_property(b, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT))
	return b

static func icon_btn(text: String, color: Color, size := 36) -> Button:
	## 长列表轻量图标按钮：flat 不画 stylebox，每行省 8 个 StyleBoxFlat 的创建开销
	var b := Button.new()
	b.text = text
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", int(size * ui_scale() * font_scale()))
	b.add_theme_color_override("font_color", color)
	b.add_theme_color_override("font_hover_color", color.lightened(0.15))
	b.add_theme_color_override("font_pressed_color", color.darkened(0.2))
	var s := 84.0 * ui_scale()   # 图标按钮默认加大（初始按钮过小的反馈）
	b.custom_minimum_size = Vector2(s, s)
	return b

static func row_label(text: String, size := 30, color := Color.WHITE) -> Label:
	## 长列表单行标签：超出省略号截断，不做整段排版（wrap 在长列表里极吃性能）
	var l := label(text, size, color, false)
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return l

static func panel(lite := false) -> PanelContainer:
	## lite=true 用于长列表行：描边代替投影，滚动时不吃 GPU
	var p := PanelContainer.new()
	var pal := palette()
	if lite:
		p.add_theme_stylebox_override("panel", style_box(pal["panel"], 18, pal["border"], 1, false))
	else:
		p.add_theme_stylebox_override("panel", style_box(pal["panel"], 18))
	return p

static func hsep() -> HSeparator:
	var s := HSeparator.new()
	s.add_theme_constant_override("separation", 8)
	return s

## iOS/安卓风格大开关（药丸 + 圆形滑钮动画）
static func make_switch(on: bool, on_toggled: Callable) -> Button:
	var p := palette()
	var b := Button.new()
	b.toggle_mode = true
	b.button_pressed = on
	b.custom_minimum_size = Vector2(180, 96)
	var pill_on := style_box(p.ok, 48)
	var pill_off := style_box(Color("565C66") if DB.settings.get("theme_dark", true) else Color("C9C2B2"), 48)
	b.add_theme_stylebox_override("normal", pill_on if on else pill_off)
	b.add_theme_stylebox_override("pressed", pill_on if on else pill_off)
	b.add_theme_stylebox_override("hover", pill_on if on else pill_off)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var knob := Panel.new()
	var ks := style_box(Color.WHITE, 40)
	ks.shadow_color = Color(0, 0, 0, 0.3)
	ks.shadow_size = 4
	ks.shadow_offset = Vector2(0, 2)
	knob.add_theme_stylebox_override("panel", ks)
	knob.custom_minimum_size = Vector2(76, 76)
	knob.position = Vector2(92.0 if on else 10.0, 10.0)
	knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(knob)
	b.toggled.connect(func(v: bool):
		b.add_theme_stylebox_override("normal", pill_on if v else pill_off)
		b.add_theme_stylebox_override("pressed", pill_on if v else pill_off)
		b.add_theme_stylebox_override("hover", pill_on if v else pill_off)
		var tw := b.create_tween()
		tw.tween_property(knob, "position:x", 92.0 if v else 10.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		on_toggled.call(v))
	return b

static var _grab_tex: Texture2D = null

## 圆形滑钮贴图（白色圆 + 深色描边）
static func grabber_texture() -> Texture2D:
	if _grab_tex != null:
		return _grab_tex
	var img := Image.create(56, 56, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(56):
		for x in range(56):
			var d := Vector2(x - 27.5, y - 27.5).length()
			if d <= 21.0:
				img.set_pixel(x, y, Color.WHITE)
			elif d <= 25.0:
				img.set_pixel(x, y, Color(0.55, 0.58, 0.64, 1.0))
	_grab_tex = ImageTexture.create_from_image(img)
	return _grab_tex

## 滑块加粗：轨道加高、圆形大滑钮
static func style_slider(s: HSlider) -> void:
	var p := palette()
	var track := StyleBoxFlat.new()
	track.bg_color = p.panel2
	track.set_corner_radius_all(12)
	track.content_margin_top = 12
	track.content_margin_bottom = 12
	s.add_theme_stylebox_override("slider", track)
	var gt := grabber_texture()
	s.add_theme_icon_override("grabber", gt)
	s.add_theme_icon_override("grabber_highlight", gt)
	s.add_theme_icon_override("grabber_disabled", gt)
	# 触控原生适配：HSlider 只认鼠标事件，部分触控链路（含无鼠标模拟的环境）拖不动；
	# 这里把屏幕触控直接翻译成取值——按下跳到触点、拖动跟手，松手发 drag_ended
	s.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventScreenTouch:
			if ev.pressed:
				s.value = s.min_value + (s.max_value - s.min_value) * clampf(ev.position.x / maxf(s.size.x, 1.0), 0.0, 1.0)
				s.set_meta("touch_grab", true)
			else:
				if s.has_meta("touch_grab"):
					s.remove_meta("touch_grab")
					s.drag_ended.emit(true)
			s.accept_event()
		elif ev is InputEventScreenDrag and s.has_meta("touch_grab"):
			s.value = s.min_value + (s.max_value - s.min_value) * clampf(ev.position.x / maxf(s.size.x, 1.0), 0.0, 1.0)
			s.accept_event())

static func spacer(h := 16) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c

static func scroll_box(separation := 14) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", separation)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return v

static func make_scroll() -> ScrollContainer:
	var s := ScrollContainer.new()
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# 侧边滚动条：默认纤细不抢视线，按住时才加粗方便拖动（与文本框共用样式）
	_style_vscroll(s.get_v_scroll_bar())
	return s

static func toast(parent: Node, text: String) -> void:
	var p := palette()
	var lbl := UI.label(text, 30, Color.WHITE)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", style_box(Color(0, 0, 0, 0.78), 16))
	pc.add_child(lbl)
	pc.anchor_left = 0.5
	pc.anchor_right = 0.5
	pc.anchor_top = 1.0
	pc.anchor_bottom = 1.0
	pc.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pc.grow_vertical = Control.GROW_DIRECTION_BEGIN
	pc.offset_top = -300.0
	pc.offset_bottom = -200.0
	# 必须挂到窗口根节点：挂到容器里会被容器排版挤走（之前在屏幕外/看不见就是这个原因）
	var host := parent.get_tree().root if parent.is_inside_tree() else null
	if host == null:
		host = (Engine.get_main_loop() as SceneTree).root
	host.add_child(pc)
	var tw := pc.create_tween()
	tw.tween_interval(1.6)
	tw.tween_property(pc, "modulate:a", 0.0, 0.4)
	tw.tween_callback(pc.queue_free)

## 统一调系统文件管理器（SAF）：显式检查返回错误码——之前直接忽略，打不开时静默无反应；
## 带类型过滤失败时自动退化为「全部文件」重试一次，仍失败则弹错误码便于反馈定位
static func file_dialog(host: Node, title: String, mode: int, filters: PackedStringArray,
		cb: Callable, filename := "", on_unavailable: Callable = Callable()) -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		if on_unavailable.is_valid():
			on_unavailable.call()
		else:
			toast(host, "当前环境不支持文件选择")
		return
	var err: Error = DisplayServer.file_dialog_show(title, "", filename, true, mode, filters, cb)
	if err != OK and not filters.is_empty():
		err = DisplayServer.file_dialog_show(title, "", filename, true, mode, PackedStringArray(), cb)
	if err != OK:
		toast(host, "无法打开文件管理器（错误码 %d），请截图反馈" % err)

static func confirm_dialog(parent: Node, title: String, text: String, on_ok: Callable,
		ok_text := "确认", cancel_text := "取消", danger := false, on_cancel := Callable()) -> Control:
	## iOS 风格弹窗：半透明遮罩 + 圆角卡片 + 大字标题 + 两个大按钮（细线分隔）
	## 点遮罩或「取消」关闭；返回键由 main 通过 ui_dialog 分组统一关闭
	var p := palette()
	var dark: bool = DB.settings.get("theme_dark", true)
	var overlay := Control.new()
	full_rect(overlay)
	overlay.add_to_group("ui_dialog")
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.42)
	full_rect(dim)
	overlay.add_child(dim)
	var center := CenterContainer.new()
	full_rect(center)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	var card := PanelContainer.new()
	var tree := Engine.get_main_loop() as SceneTree
	var vw := 720.0
	if tree != null:
		vw = tree.root.get_visible_rect().size.x
	card.custom_minimum_size = Vector2(minf(640.0, vw - 64.0), 0)
	var card_sb := style_box(Color("26292F") if dark else Color("FFFFFF"), 32)
	card_sb.content_margin_left = 0
	card_sb.content_margin_right = 0
	card_sb.content_margin_top = 0
	card_sb.content_margin_bottom = 0
	card.add_theme_stylebox_override("panel", card_sb)
	center.add_child(card)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 0)
	card.add_child(cv)
	var head_margin := MarginContainer.new()
	head_margin.add_theme_constant_override("margin_left", 36)
	head_margin.add_theme_constant_override("margin_right", 36)
	head_margin.add_theme_constant_override("margin_top", 30)
	head_margin.add_theme_constant_override("margin_bottom", 26)
	cv.add_child(head_margin)
	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head_margin.add_child(head)
	var t := label(title, 36, p.text)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(t)
	if text != "":
		var m := label(text, 28, p.sub, true)
		m.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		m.mouse_filter = Control.MOUSE_FILTER_STOP
		head.add_child(m)
	var sep := HSeparator.new()
	sep.add_theme_color_override("separator_color", Color(p.border, 0.8))
	cv.add_child(sep)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 0)
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	cv.add_child(btns)
	var cancel := Button.new()
	cancel.text = cancel_text
	cancel.flat = true
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.custom_minimum_size = Vector2(0, 116)
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.add_theme_font_size_override("font_size", int(32 * ui_scale() * font_scale()))
	cancel.add_theme_color_override("font_color", p.text)
	cancel.add_theme_color_override("font_hover_color", p.sub)
	cancel.add_theme_color_override("font_pressed_color", p.sub)
	btns.add_child(cancel)
	var vsep := VSeparator.new()
	vsep.add_theme_color_override("separator_color", Color(p.border, 0.8))
	btns.add_child(vsep)
	var ok := Button.new()
	ok.text = ok_text
	ok.flat = true
	ok.focus_mode = Control.FOCUS_NONE
	ok.custom_minimum_size = Vector2(0, 116)
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ok.add_theme_font_size_override("font_size", int(34 * ui_scale() * font_scale()))
	var okc: Color = p.danger if danger else p.accent
	ok.add_theme_color_override("font_color", okc)
	ok.add_theme_color_override("font_hover_color", okc.lightened(0.15))
	ok.add_theme_color_override("font_pressed_color", okc.darkened(0.15))
	btns.add_child(ok)
	cancel.pressed.connect(func():
		dismiss_dialog(overlay)
		if on_cancel.is_valid():
			on_cancel.call())
	ok.pressed.connect(func():
		dismiss_dialog(overlay)
		on_ok.call())
	dim.gui_input.connect(func(ev: InputEvent):
		# 抬起且未滑动才算「主动点背板关闭」：手指按下即拖的滑动手势不关弹窗
		if (ev is InputEventMouseButton and not ev.pressed) or (ev is InputEventScreenTouch and not ev.pressed):
			if not touch_scrolled:
				dismiss_dialog(overlay)
				if on_cancel.is_valid():
					on_cancel.call())
	# 必须挂到窗口根节点：挂到容器（设置页/AI页都是 VBoxContainer）里会被容器
	# 当成普通排版元素挤到屏幕外 —— 这就是"提示框在屏幕外面"的根因
	var host := parent.get_tree().root if parent.is_inside_tree() else null
	if host == null:
		host = (Engine.get_main_loop() as SceneTree).root
	host.add_child(overlay)
	# 淡入
	overlay.modulate.a = 0.0
	var tw := overlay.create_tween()
	tw.tween_property(overlay, "modulate:a", 1.0, 0.14)
	return overlay

static func dismiss_dialog(overlay: Control) -> void:
	## 关闭 iOS 风格弹窗（立即隐藏防重复触发，然后释放）
	if overlay == null or not is_instance_valid(overlay) or not overlay.visible:
		return
	overlay.hide()
	overlay.queue_free()

static func double_press(b: Button, armed_text: String, action: Callable) -> void:
	## 旁白式点选（类 TalkBack）：第一次点按 = 框选（琥珀色粗描边焦点框 + 提示文案），2.5s 内第二次点按才执行
	if b.get_meta("armed", false):
		_disarm(b)
		action.call()
		return
	b.set_meta("armed", true)
	b.set_meta("orig_text", b.text)
	b.set_meta("orig_color", b.get_theme_color("font_color"))
	b.set_meta("orig_sb", b.get_theme_stylebox("normal"))
	b.text = armed_text
	b.add_theme_color_override("font_color", Color("FBBF24"))
	var sb = b.get_theme_stylebox("normal").duplicate()
	if sb is StyleBoxFlat:
		sb.border_color = Color("FBBF24")
		sb.set_border_width_all(5)
		sb.set_corner_radius_all(maxi(sb.get_corner_radius(CORNER_TOP_LEFT), 14))
		b.add_theme_stylebox_override("normal", sb)
	var wr: WeakRef = weakref(b)
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		tree.create_timer(2.5).timeout.connect(func():
			var bb = wr.get_ref()
			if bb != null and bb.get_meta("armed", false):
				_disarm(bb))

static func _disarm(b: Button) -> void:
	b.set_meta("armed", false)
	b.text = String(b.get_meta("orig_text", b.text))
	b.add_theme_color_override("font_color", b.get_meta("orig_color", Color.WHITE))
	var orig = b.get_meta("orig_sb", null)
	if orig != null:
		b.add_theme_stylebox_override("normal", orig)

static func tap_lock(le: Control) -> void:
	## 文本框防误触：单击无效，长按 0.45s 或双击才进入编辑；失焦后重新锁定
	## 锁定状态下：拖动一律视为滚动（不误触发选词）；剪贴板有内容时长按先给「粘贴」选项
	if not (le is LineEdit or le is TextEdit):
		return
	le.editable = false
	le.context_menu_enabled = true   # 编辑态长按弹系统样式菜单（复制/粘贴/全选）
	var guard := Control.new()
	# PASS：罩层接收点击做长按/双击判定，拖动则自己转成滚动并吞掉（不让文本框选中文字）
	guard.mouse_filter = Control.MOUSE_FILTER_PASS
	full_rect(guard)
	le.add_child(guard)
	var state := {"pressed": false, "dragged": false}
	guard.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton or ev is InputEventScreenTouch:
			if ev.pressed:
				if ev is InputEventMouseButton and ev.double_click:
					state.pressed = false
					_unlock_edit(le, guard)
					return
				state.pressed = true
				state.dragged = false
				le.get_tree().create_timer(0.45).timeout.connect(func():
					if state.pressed and not state.dragged and is_instance_valid(le) and is_instance_valid(guard) and guard.visible:
						state.pressed = false
						_long_press_locked(le, guard))
			else:
				if state.pressed and not state.dragged:
					state.pressed = false
					UI.toast(le, "长按或双击文本框开始输入")
		elif (ev is InputEventScreenDrag
				or (ev is InputEventMouseMotion and (ev.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0)):
			# 锁定态拖动 = 滚动（手指上推内容下移），并吞掉事件防止文本框进入选词
			state.dragged = true
			if le is TextEdit:
				var vsb: VScrollBar = (le as TextEdit).get_v_scroll_bar()
				vsb.value -= ev.relative.y
			guard.accept_event())
	attach_edit_menu(le)

## 编辑态长按弹应用内菜单（复制/剪切/粘贴/全选）：Godot 原生右键菜单在部分安卓机上不弹，
## 统一走自家 dropdown，样式与全 App 一致，且带震动（设置页可关）
static func attach_edit_menu(le: Control) -> void:
	if not (le is LineEdit or le is TextEdit):
		return
	var estate := {"pressed": false, "dragged": false, "seq": 0}
	le.gui_input.connect(func(ev: InputEvent):
		if not bool(le.get("editable")):
			return   # 锁定态由 tap_lock 的 guard 负责
		if ev is InputEventScreenTouch or ev is InputEventMouseButton:
			if ev.pressed:
				estate.pressed = true
				estate.dragged = false
				estate.seq = int(estate.seq) + 1
				var my: int = estate.seq
				le.get_tree().create_timer(0.6).timeout.connect(func():
					if int(estate.seq) == my and estate.pressed and not estate.dragged \
							and is_instance_valid(le) and bool(le.get("editable")):
						_edit_menu(le))
			else:
				estate.pressed = false
		elif ev is InputEventScreenDrag or (ev is InputEventMouseMotion and (ev.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0):
			if estate.pressed and ev.relative.length() > 6.0:
				estate.dragged = true)

## 编辑态长按菜单：按选中状态和剪贴板动态出项（剪切/复制/粘贴/全选）
static func _edit_menu(le: Control) -> void:
	vibrate(24)
	var has_sel := false
	if le is LineEdit:
		has_sel = (le as LineEdit).has_selection()
	elif le is TextEdit:
		has_sel = (le as TextEdit).has_selection()
	var opts: Array = []
	var acts: Array = []
	if has_sel:
		opts.append("✂️ 剪切"); acts.append("cut")
		opts.append("📄 复制"); acts.append("copy")
	if DisplayServer.clipboard_get() != "":
		opts.append("📋 粘贴"); acts.append("paste")
	opts.append("🔠 全选"); acts.append("select_all")
	dropdown(le, opts, func(i: int):
		vibrate(14)
		var a: String = acts[i]
		if a == "cut":
			if le is LineEdit: (le as LineEdit).menu_option(LineEdit.MENU_CUT)
			else: (le as TextEdit).cut()
		elif a == "copy":
			if le is LineEdit: (le as LineEdit).menu_option(LineEdit.MENU_COPY)
			else: (le as TextEdit).copy()
		elif a == "paste":
			if le is LineEdit: (le as LineEdit).menu_option(LineEdit.MENU_PASTE)
			else: (le as TextEdit).paste()
		elif a == "select_all":
			if le is LineEdit: (le as LineEdit).select_all()
			else: (le as TextEdit).select_all())

static func _unlock_edit(le: Control, guard: Control) -> void:
	le.editable = true
	guard.hide()
	le.grab_focus()
	le.focus_exited.connect(_relock_edit.bind(le, guard), CONNECT_ONE_SHOT)

static func _relock_edit(le: Control, guard: Control) -> void:
	if is_instance_valid(le) and is_instance_valid(guard):
		le.editable = false
		guard.show()

## 触感震动：短 tick；设置页可关（settings["haptics"]）
static func vibrate(ms := 14) -> void:
	if not DB.settings.get("haptics", true):
		return
	if OS.has_feature("android"):
		Input.vibrate_handheld(ms)

## 锁定态长按：剪贴板有内容先给「粘贴」选项（导入场景的主要动作），否则直接进入编辑
static func _long_press_locked(le: Control, guard: Control) -> void:
	vibrate(24)
	var clip := DisplayServer.clipboard_get().strip_edges()
	if clip == "":
		_unlock_edit(le, guard)
		return
	dropdown(le, ["📋 粘贴剪贴板（%d 字）" % clip.length(), "✏️ 进入编辑"], func(i: int):
		if i == 0:
			if le is TextEdit:
				var te := le as TextEdit   # 追加到末尾并滚动可见，比插在光标处可预期
				te.text = te.text + ("" if te.text == "" or te.text.ends_with("\n") else "\n") + clip
				te.set_caret_line(te.get_line_count() - 1)
			elif le is LineEdit:
				(le as LineEdit).insert_text_at_caret(clip)
			vibrate(20)
			toast(le, "已粘贴 %d 字" % clip.length())
		else:
			_unlock_edit(le, guard))

# ---------------- 通用自定义弹窗（替代原生 ConfirmationDialog/AcceptDialog/OptionButton） ----------------
## 读图→缩放→JPEG base64 data URL（DeepSeek 视觉模型单图按 ≤384 token 计费，1024 边长足够清晰且省流量）
## 安卓系统文件选择器返回的是 content:// 路径：Image.load() 只认真实文件路径会失败，
## 必须先走 FileAccess（内部过 ContentResolver）拿字节，再按格式从内存解码
static func image_to_data_url(path: String, max_side := 1024) -> String:
	# FileAccess 读不动时自动走 YysKit 插件 ContentResolver 兜底（DB.read_uri_bytes）
	var bytes := DB.read_uri_bytes(path)
	if bytes.is_empty():
		return ""
	var img := Image.new()
	var err := FAILED
	var lower := path.to_lower()
	if lower.ends_with(".png"):
		err = img.load_png_from_buffer(bytes)
	elif lower.ends_with(".webp"):
		err = img.load_webp_from_buffer(bytes)
	elif lower.ends_with(".gif"):
		err = img.load_gif_from_buffer(bytes)
	elif lower.ends_with(".jpg") or lower.ends_with(".jpeg"):
		err = img.load_jpg_from_buffer(bytes)
	if err != OK:
		# content:// 无扩展名或猜错：三种常见格式轮试
		err = img.load_jpg_from_buffer(bytes)
		if err != OK:
			err = img.load_png_from_buffer(bytes)
		if err != OK:
			err = img.load_webp_from_buffer(bytes)
	if err != OK:
		return ""
	var w := img.get_width()
	var h := img.get_height()
	if w <= 0 or h <= 0:
		return ""
	var m: float = maxf(w, h)
	if m > max_side:
		var s := max_side / m
		img.resize(maxi(1, int(w * s)), maxi(1, int(h * s)), Image.INTERPOLATE_LANCZOS)
	return "data:image/jpeg;base64," + Marshalls.raw_to_base64(img.save_jpg_to_buffer(0.85))
## iOS 风格大弹窗：标题 + 可滚动内容区 + 底部大按钮，尺寸钳制在屏幕内
## 返回 {"overlay","body","scroll","ok","cancel"}；cancel_text 传 "" 时只显示主按钮
static func sheet(parent: Node, title: String, ok_text := "确定", cancel_text := "取消",
		on_ok := Callable(), danger := false) -> Dictionary:
	var p := palette()
	var dark: bool = DB.settings.get("theme_dark", true)
	var tree := Engine.get_main_loop() as SceneTree
	var vp := tree.root.get_visible_rect().size
	var overlay := Control.new()
	full_rect(overlay)
	overlay.add_to_group("ui_dialog")
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.42)
	full_rect(dim)
	overlay.add_child(dim)
	var center := CenterContainer.new()
	full_rect(center)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	var card := PanelContainer.new()
	var card_w := minf(880.0, vp.x - 48.0)
	card.custom_minimum_size = Vector2(card_w, 0)
	var card_sb := style_box(Color("26292F") if dark else Color("FFFFFF"), 28, Color.TRANSPARENT, 0, false)
	card_sb.content_margin_left = 0
	card_sb.content_margin_right = 0
	card_sb.content_margin_top = 0
	card_sb.content_margin_bottom = 0
	card.add_theme_stylebox_override("panel", card_sb)
	center.add_child(card)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 0)
	card.add_child(cv)
	var tm := MarginContainer.new()
	for m in ["margin_left", "margin_right"]:
		tm.add_theme_constant_override(m, 32)
	tm.add_theme_constant_override("margin_top", 26)
	tm.add_theme_constant_override("margin_bottom", 6)
	cv.add_child(tm)
	var t := label(title, 33, p.text, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tm.add_child(t)
	var bm := MarginContainer.new()
	for m in ["margin_left", "margin_right"]:
		bm.add_theme_constant_override(m, 26)
	bm.add_theme_constant_override("margin_top", 14)
	bm.add_theme_constant_override("margin_bottom", 18)
	cv.add_child(bm)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# ScrollContainer/VBox 默认 mouse_filter=PASS：弹窗里滑动会穿透带动背景页面一起滚，必须 STOP
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	# ScrollContainer 不会把内容高度向上传播，先给一个可靠默认高度，再由 _sheet_fit 精调
	scroll.custom_minimum_size = Vector2(card_w - 52.0, minf(440.0, vp.y * 0.5))
	bm.add_child(scroll)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	var sep := HSeparator.new()
	sep.add_theme_color_override("separator_color", Color(p.border, 0.8))
	cv.add_child(sep)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 0)
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	cv.add_child(btns)
	var cancel: Button = null
	if cancel_text != "":
		cancel = _flat_btn(cancel_text, p.text, 31)
		btns.add_child(cancel)
		var vsep := VSeparator.new()
		vsep.add_theme_color_override("separator_color", Color(p.border, 0.8))
		btns.add_child(vsep)
	var okc: Color = p.danger if danger else p.accent
	var ok := _flat_btn(ok_text, okc, 33)
	btns.add_child(ok)
	if cancel != null:
		cancel.pressed.connect(func(): dismiss_dialog(overlay))
	ok.pressed.connect(func():
		dismiss_dialog(overlay)
		if on_ok.is_valid():
			on_ok.call())
	dim.gui_input.connect(func(ev: InputEvent):
		if (ev is InputEventMouseButton and not ev.pressed) or (ev is InputEventScreenTouch and not ev.pressed):
			if not touch_scrolled:
				dismiss_dialog(overlay))
	var host := parent.get_tree().root if parent.is_inside_tree() else null
	if host == null:
		host = tree.root
	host.add_child(overlay)
	_sheet_fit(scroll, card, vp.y)
	overlay.modulate.a = 0.0
	var tw := overlay.create_tween()
	tw.tween_property(overlay, "modulate:a", 1.0, 0.14)
	return {"overlay": overlay, "body": body, "scroll": scroll, "ok": ok, "cancel": cancel, "card": card}

static func _flat_btn(txt: String, col: Color, sz: int) -> Button:
	var b := Button.new()
	b.text = txt
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 110)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", int(sz * ui_scale() * font_scale()))
	b.add_theme_color_override("font_color", col)
	b.button_down.connect(func(): vibrate(10))
	return b

## 弹窗高度精调：等两帧让内容排版完成，按内容真实高度贴合（上限屏高 58%）
static func _sheet_fit(scroll: ScrollContainer, card: PanelContainer, vh: float) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var fit := func():
		if not is_instance_valid(scroll):
			return
		var content_h := 300.0
		if scroll.get_child_count() > 0:
			content_h = (scroll.get_child(0) as Control).get_combined_minimum_size().y
		scroll.custom_minimum_size.y = clampf(content_h + 8.0, 140.0, vh * 0.58)
	tree.process_frame.connect(func():
		if not is_instance_valid(scroll):
			return
		tree.process_frame.connect(fit, CONNECT_ONE_SHOT), CONNECT_ONE_SHOT)

## 勾选项胶囊行（替代原生 CheckBox）：点整行切换，选中时 ✓ + 高亮描边，文字自动换行
static func check_row(text: String, on := true, text_color := Color(0, 0, 0, 0), size := 26) -> Button:
	var p := palette()
	if text_color.a == 0.0:
		text_color = p.text
	var b := Button.new()
	b.toggle_mode = true
	b.button_pressed = on
	b.focus_mode = Control.FOCUS_NONE
	b.text = ""
	# Button 不会把内部锚点子控件的高度向上传播：行高必须自己算，
	# 否则多行文字的行会塌成一条线、文字互相叠印（导入预览几百行时的重影根因）
	b.custom_minimum_size = Vector2(0, size * font_scale() * 1.35 + 26.0)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.anchor_left = 0.0
	hb.anchor_top = 0.0
	hb.anchor_right = 1.0
	hb.anchor_bottom = 1.0
	hb.offset_left = 22
	hb.offset_right = -22
	hb.offset_top = 12
	hb.offset_bottom = -12
	b.add_child(hb)
	var tick := label("✓" if on else "", size + 6, p.accent)
	tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tick.custom_minimum_size = Vector2(int(40 * ui_scale()), 0)
	hb.add_child(tick)
	var lb := label(text, size, text_color, true)
	lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(lb)
	_check_style(b, on)
	b.toggled.connect(func(o: bool):
		vibrate(12)
		tick.text = "✓" if o else ""
		_check_style(b, o))
	# 宽度定下来后按真实换行结果撑开行高（延迟应用，避免布局递归）
	var apply_h := func(h: float):
		if is_instance_valid(b) and absf(h - b.custom_minimum_size.y) > 4.0:
			b.custom_minimum_size.y = h
	lb.resized.connect(func():
		if not is_instance_valid(lb) or lb.size.x < 8.0:
			return
		var fnt: Font = lb.get_theme_font("font")
		var fsz: int = lb.get_theme_font_size("font_size")
		var need: float = fnt.get_multiline_string_size(
			lb.text, HORIZONTAL_ALIGNMENT_LEFT, lb.size.x, fsz).y + 26.0
		apply_h.call_deferred(need))
	return b

static func _check_style(b: Button, on: bool) -> void:
	var p := palette()
	if on:
		b.add_theme_stylebox_override("normal", style_box(p.panel2, 14, p.accent, 3, false))
	else:
		b.add_theme_stylebox_override("normal", style_box(p.panel, 14, Color.TRANSPARENT, 0, false))
	b.add_theme_stylebox_override("hover", style_box(p.panel2, 14, p.accent if on else p.border, 3 if on else 2, false))
	b.add_theme_stylebox_override("pressed", style_box(p.panel2, 14, p.accent, 3, false))

## 自定义下拉弹层（替代原生 OptionButton 的下拉窗口）：锚定按钮下方展开
static func dropdown(anchor: Control, items: Array, on_pick: Callable) -> void:
	var p := palette()
	var dark: bool = DB.settings.get("theme_dark", true)
	var tree := Engine.get_main_loop() as SceneTree
	var vp := tree.root.get_visible_rect().size
	var overlay := Control.new()
	full_rect(overlay)
	overlay.add_to_group("ui_dialog")
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.25)
	full_rect(dim)
	overlay.add_child(dim)
	var arect := anchor.get_global_rect()
	var pw := clampf(arect.size.x, 340.0, vp.x - 48.0)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",
		style_box(Color("26292F") if dark else Color("FFFFFF"), 20, Color.TRANSPARENT, 0, false))
	panel.custom_minimum_size = Vector2(pw, 0)
	overlay.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# 高度按条目数直接算好（ScrollContainer 不会传播内容高度），超高出滚动条
	scroll.custom_minimum_size = Vector2(pw - 24.0, minf(items.size() * 96.0 + 12.0, vp.y * 0.5))
	panel.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vb)
	for i in items.size():
		var b := _flat_btn(String(items[i]), p.text, 29)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 92)
		vb.add_child(b)
		b.pressed.connect(func():
			dismiss_dialog(overlay)
			on_pick.call(i))
	panel.position = Vector2(
		clampf(arect.position.x, 24.0, maxf(24.0, vp.x - pw - 24.0)),
		minf(arect.end.y + 8.0, vp.y * 0.42))
	dim.gui_input.connect(func(ev: InputEvent):
		if (ev is InputEventMouseButton and not ev.pressed) or (ev is InputEventScreenTouch and not ev.pressed):
			if not touch_scrolled:
				dismiss_dialog(overlay))
	var host := anchor.get_tree().root if anchor.is_inside_tree() else null
	if host == null:
		host = tree.root
	host.add_child(overlay)
	# 底部越界时上移（高度已按条目数算好，mh 可靠）
	tree.process_frame.connect(func():
		if not is_instance_valid(panel):
			return
		var mh: float = panel.get_combined_minimum_size().y
		if panel.position.y + mh > vp.y - 24.0:
			panel.position.y = maxf(24.0, vp.y - 24.0 - mh), CONNECT_ONE_SHOT)
	overlay.modulate.a = 0.0
	var tw := overlay.create_tween()
	tw.tween_property(overlay, "modulate:a", 1.0, 0.12)

## 文本框统一样式：自动换行（内容不再横向溢出）+ 平滑滚动 + 纤细滚动条（按住加粗）
static func style_textedit(te: TextEdit) -> void:
	te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	te.scroll_smooth = true
	_style_vscroll(te.get_v_scroll_bar())
	# 纤细滚动条画在文字区右缘：右边距让位，文字不被滑块遮挡（复制样式再改，不动共享资源）
	var sb := te.get_theme_stylebox("normal")
	if sb is StyleBoxFlat and sb.content_margin_right < 40.0:
		var dup := sb.duplicate() as StyleBoxFlat
		dup.content_margin_right = 44.0
		te.add_theme_stylebox_override("normal", dup)

## 滚动条样式：默认纤细，按住加粗（供 ScrollContainer / TextEdit 共用）
static func _style_vscroll(vsb: VScrollBar) -> void:
	vsb.custom_minimum_size = Vector2(18 * ui_scale(), 0)
	var p := palette()
	var grab := StyleBoxFlat.new()
	grab.bg_color = Color(p.sub, 0.45)
	grab.set_corner_radius_all(8)
	grab.content_margin_left = 4
	grab.content_margin_right = 4
	grab.content_margin_top = 14
	grab.content_margin_bottom = 14
	var grab_hi := StyleBoxFlat.new()   # 悬停/移动：只变色不变粗，避免滚动时滚动条忽粗忽细
	grab_hi.bg_color = Color(p.accent, 0.7)
	grab_hi.set_corner_radius_all(8)
	grab_hi.content_margin_left = 4
	grab_hi.content_margin_right = 4
	grab_hi.content_margin_top = 14
	grab_hi.content_margin_bottom = 14
	var grab_pr := StyleBoxFlat.new()   # 只有按住（选中）时才加粗
	grab_pr.bg_color = Color(p.accent, 0.9)
	grab_pr.set_corner_radius_all(12)
	grab_pr.content_margin_left = 8
	grab_pr.content_margin_right = 8
	grab_pr.content_margin_top = 14
	grab_pr.content_margin_bottom = 14
	vsb.add_theme_stylebox_override("grabber", grab)
	vsb.add_theme_stylebox_override("grabber_highlight", grab_hi)
	vsb.add_theme_stylebox_override("grabber_pressed", grab_pr)
	var thin := 18.0
	var thick := 44.0
	vsb.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton or ev is InputEventScreenTouch:
			vsb.custom_minimum_size = Vector2((thick if ev.pressed else thin) * ui_scale(), 0))

## AI 长期记忆查看弹窗（设置页/AI 页共用）；count_btn 传入时删除后同步刷新其文案
static func memory_dialog(parent: Node, count_btn: Button = null) -> void:
	var p := palette()
	var sh := sheet(parent, "AI 长期记忆（%d 条）" % DB.ai_memory.size(), "关闭", "")
	var list: VBoxContainer = sh["body"]
	if DB.ai_memory.is_empty():
		list.add_child(label("暂无记忆。和 AI 聊天时可以说「记住：我……」，或让它自己总结你的薄弱点。", 26, p.sub, true))
		return
	for i in DB.ai_memory.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var item_text := String(DB.ai_memory[i])
		var lb := label(item_text, 26, p.text, true)
		lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lb)
		# 逐条编辑：记忆是用户自己的数据，写错了能改，不用先删再让 AI 重记
		var edit := button("✎", p.panel2, p.text, 24)
		edit.custom_minimum_size = Vector2(72, 56)
		edit.pressed.connect(func():
			var te := TextEdit.new()
			te.text = item_text
			te.custom_minimum_size = Vector2(0, 160)
			te.add_theme_font_size_override("font_size", 26)
			style_textedit(te)
			tap_lock(te)
			var on_save := func():
				var nt := te.text.strip_edges()
				if nt == "" or nt == item_text:
					return
				var idx := DB.ai_memory.find(item_text)
				if idx >= 0:
					DB.ai_memory[idx] = nt
					DB.save_memory()
					lb.text = nt
			var esh := sheet(parent, "编辑这条记忆", "保存", "取消", on_save)
			esh["body"].add_child(te))
		row.add_child(edit)
		var del := button("✕", p.panel2, p.danger, 24)
		del.custom_minimum_size = Vector2(72, 56)
		del.pressed.connect(func():
			DB.memory_remove([item_text])
			row.queue_free()
			if count_btn != null and is_instance_valid(count_btn):
				count_btn.text = "🧠 查看记忆（%d 条）" % DB.ai_memory.size())
		row.add_child(del)
		list.add_child(row)

static func set_bg_color_recursive(root: Control) -> void:
	pass  # 背景由 main 统一处理
