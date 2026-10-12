extends VBoxContainer
## 学习界面：卡片模式（翻面）+ 列表模式，星标 / 英美发音 / 语速 / 认识标记

signal back_requested

var kind := "words"     # words | phrases
var group := ""
var items: Array = []
var idx := 0
var flipped := false
var mode_card := true
var order_shuffle := false

var top_bar: HBoxContainer
var card_area: Control
var front_box: VBoxContainer
var back_box: VBoxContainer
var progress_lbl: Label
var star_btn: Button
var rate_btn: Button
var mode_btn: Button
var shuffle_btn: Button
var list_scroll: ScrollContainer
var card_panel: PanelContainer

func _ready() -> void:
	add_theme_constant_override("separation", 12)
	UI.full_rect(self)
	items = DB.words_in_group(group) if kind == "words" else DB.phrases_in_group(group)
	var p := UI.palette()

	# 顶部工具条
	top_bar = HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 10)
	add_child(top_bar)
	var back := UI.button("← 返回", p.panel2, p.text, 28)
	back.custom_minimum_size = Vector2(170, 76)
	back.pressed.connect(func(): back_requested.emit())
	top_bar.add_child(back)
	progress_lbl = UI.label("", 30, p.sub)
	progress_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top_bar.add_child(progress_lbl)
	mode_btn = UI.button("列表", p.panel2, p.text, 28)
	mode_btn.custom_minimum_size = Vector2(140, 76)
	mode_btn.pressed.connect(_toggle_mode)
	top_bar.add_child(mode_btn)
	shuffle_btn = UI.button("顺序", p.panel2, p.text, 28)
	shuffle_btn.custom_minimum_size = Vector2(140, 76)
	shuffle_btn.pressed.connect(_toggle_shuffle)
	top_bar.add_child(shuffle_btn)

	# 卡片区
	card_area = Control.new()
	card_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(card_area)
	_build_card_mode(p)

	# 列表区（默认隐藏）
	list_scroll = UI.make_scroll()
	list_scroll.visible = false
	add_child(list_scroll)

	_landscape = _is_landscape()
	get_viewport().size_changed.connect(_on_rotate)

	_refresh()

var _landscape := false

func _on_rotate() -> void:
	var l := _is_landscape()
	if l == _landscape:
		return
	_landscape = l
	if mode_card:
		for c in card_area.get_children():
			card_area.remove_child(c)
			c.queue_free()
		_build_card_mode(UI.palette())
		_refresh()

func _is_landscape() -> bool:
	var s := get_viewport().get_visible_rect().size
	return s.x > s.y

func _build_card_mode(p: Dictionary) -> void:
	var landscape := _is_landscape()
	# 竖屏：卡片在上、按钮在下；横屏：卡片在左、按钮在右一列
	var vb: BoxContainer = HBoxContainer.new() if landscape else VBoxContainer.new()
	UI.full_rect(vb)
	vb.add_theme_constant_override("separation", 14)
	card_area.add_child(vb)

	card_panel = PanelContainer.new()
	card_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_panel.add_theme_stylebox_override("panel", UI.style_box(p.panel, 24, p.border, 2))
	vb.add_child(card_panel)
	var tap := Button.new()
	UI.full_rect(tap)
	tap.flat = true
	tap.pressed.connect(_flip)
	card_panel.add_child(tap)

	front_box = VBoxContainer.new()
	UI.full_rect(front_box)
	front_box.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 不挡卡片翻面点击（子按钮仍可点）
	front_box.alignment = BoxContainer.ALIGNMENT_CENTER
	front_box.add_theme_constant_override("separation", 18)
	card_panel.add_child(front_box)

	back_box = VBoxContainer.new()
	UI.full_rect(back_box)
	back_box.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 同上
	back_box.alignment = BoxContainer.ALIGNMENT_CENTER
	back_box.add_theme_constant_override("separation", 14)
	back_box.visible = false
	card_panel.add_child(back_box)

	# 操作按钮区
	var btns: BoxContainer = VBoxContainer.new() if landscape else HBoxContainer.new()
	btns.add_theme_constant_override("separation", 10)
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	if landscape:
		btns.custom_minimum_size = Vector2(280, 0)
	vb.add_child(btns)
	var prev := UI.button("上一张", p.panel2, p.text, 28)
	prev.pressed.connect(func(): _step(-1))
	btns.add_child(prev)
	var unknown := UI.button("不认识 ⭐", p.danger, Color.WHITE, 28)
	unknown.pressed.connect(_mark_unknown)
	btns.add_child(unknown)
	var known := UI.button("认识 ✓", p.ok, Color.WHITE, 28)
	known.pressed.connect(_mark_known)
	btns.add_child(known)
	var next := UI.button("下一张", p.panel2, p.text, 28)
	next.pressed.connect(func(): _step(1))
	btns.add_child(next)
	for b in btns.get_children():
		if landscape:
			b.size_flags_vertical = Control.SIZE_EXPAND_FILL
		else:
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _id(it: Dictionary) -> String:
	return DB.word_id(it) if kind == "words" else DB.phrase_id(it)

static func _clabel(text: String, size: int, color: Color, wrap := false) -> Label:
	var l := UI.label(text, size, color, wrap)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

func _refresh() -> void:
	var p := UI.palette()
	if items.is_empty():
		progress_lbl.text = "本组为空"
		return
	idx = clampi(idx, 0, items.size() - 1)
	var it: Dictionary = items[idx]
	progress_lbl.text = "%d / %d" % [idx + 1, items.size()]
	flipped = false
	_flipping = false   # 卡片内容重建时解锁，防止翻页 tween 被打断后永久卡死
	if is_instance_valid(card_panel):
		card_panel.modulate.a = 1.0   # 淡入淡出被中断时恢复不透明
	back_box.visible = false
	front_box.visible = true

	for c in front_box.get_children(): c.queue_free()
	for c in back_box.get_children(): c.queue_free()

	var id := _id(it)
	# ---- 正面 ----
	var top_row := HBoxContainer.new()
	top_row.alignment = BoxContainer.ALIGNMENT_CENTER
	top_row.add_theme_constant_override("separation", 20)
	front_box.add_child(top_row)
	var title_text: String = it.w if kind == "words" else it.en
	var title_lbl := UI.label(title_text, 64, p.text, kind == "phrases")
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL  # 换行标签要占满可用宽度，否则会塌成单字竖排
	top_row.add_child(title_lbl)
	star_btn = UI.button("★" if DB.is_starred(kind, id) else "☆",
		Color.TRANSPARENT, p.star if DB.is_starred(kind, id) else p.sub, 52)
	star_btn.custom_minimum_size = Vector2(90, 90)
	star_btn.pressed.connect(_toggle_star)
	top_row.add_child(star_btn)

	if kind == "words" and String(it.get("p", "")) != "":
		front_box.add_child(_clabel(String(it.p), 34, p.sub))

	var tts_row := HBoxContainer.new()
	tts_row.alignment = BoxContainer.ALIGNMENT_CENTER
	tts_row.add_theme_constant_override("separation", 14)
	front_box.add_child(tts_row)
	var speak := UI.button("🔊 朗读", p.panel2, p.text, 30)
	speak.custom_minimum_size = Vector2(240, 84)
	speak.pressed.connect(func(): TTS.play_word(title_text, String(it.get("p", "")) if kind == "words" else ""))
	tts_row.add_child(speak)
	rate_btn = UI.button("语速 %.1fx" % float(DB.settings.get("tts_rate", 1.0)), p.panel2, p.text, 28)
	rate_btn.custom_minimum_size = Vector2(190, 84)
	rate_btn.pressed.connect(_toggle_rate)
	tts_row.add_child(rate_btn)

	var hint := UI.label("点击卡片查看释义", 26, p.sub)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	front_box.add_child(hint)

	# ---- 背面 ----
	if kind == "words":
		back_box.add_child(_clabel(String(it.w), 44, p.text))
		if String(it.get("p", "")) != "":
			back_box.add_child(_clabel(String(it.p), 30, p.sub))
		back_box.add_child(_clabel(String(it.get("m", "")), 38, p.accent, true))
		for syn in it.get("syn", []):
			back_box.add_child(_clabel("近义 " + String(syn.get("w", "")), 30, p.text))
			back_box.add_child(_clabel(String(syn.get("n", "")), 26, p.sub, true))
		for sim in it.get("sim", []):
			back_box.add_child(_clabel("形近 " + String(sim.get("w", "")), 30, p.text))
			back_box.add_child(_clabel(String(sim.get("n", "")), 26, p.sub, true))
	else:
		back_box.add_child(_clabel(String(it.en), 40, p.text, true))
		back_box.add_child(_clabel(String(it.get("cn", "")), 40, p.accent, true))
		back_box.add_child(_clabel("出自 " + String(it.sec), 24, p.sub))
	DB.mark_seen(kind, id)
	if mode_card and is_instance_valid(card_panel):
		UI.fade_in(card_panel)   # 换卡轻淡入，节奏更顺

var _flipping := false

func _flip() -> void:
	if _flipping:
		return
	_flipping = true
	flipped = not flipped
	# 淡入淡出换面：不做 scale 翻转，避免文字在动画中被横向拉伸变形
	var tw := create_tween()
	tw.tween_property(card_panel, "modulate:a", 0.0, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		if not is_instance_valid(card_panel):
			return
		front_box.visible = not flipped
		back_box.visible = flipped)
	tw.tween_property(card_panel, "modulate:a", 1.0, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func(): _flipping = false)

func _step(d: int) -> void:
	idx = clampi(idx + d, 0, items.size() - 1)
	_refresh()

func _toggle_star() -> void:
	var p := UI.palette()
	var id := _id(items[idx])
	var on := DB.toggle_star(kind, id)
	star_btn.text = "★" if on else "☆"
	star_btn.add_theme_color_override("font_color", p.star if on else p.sub)
	UI.pop(star_btn)

func _toggle_rate() -> void:
	var r := float(DB.settings.get("tts_rate", 1.0))
	r = 0.7 if r >= 1.0 else 1.0
	DB.settings["tts_rate"] = r
	DB.save_settings()
	rate_btn.text = "语速 %.1fx" % r

func _mark_known() -> void:
	DB.mark_known(kind, _id(items[idx]), true)
	_step(1)

func _mark_unknown() -> void:
	var id := _id(items[idx])
	DB.mark_known(kind, id, false)
	if not DB.is_starred(kind, id):
		DB.toggle_star(kind, id)
	_step(1)

func _toggle_mode() -> void:
	mode_card = not mode_card
	mode_btn.text = "卡片" if not mode_card else "列表"
	card_area.visible = mode_card
	list_scroll.visible = not mode_card
	if not mode_card:
		_build_list()

func _toggle_shuffle() -> void:
	order_shuffle = not order_shuffle
	shuffle_btn.text = "随机" if not order_shuffle else "顺序"
	if order_shuffle:
		items.shuffle()
	else:
		items = DB.words_in_group(group) if kind == "words" else DB.phrases_in_group(group)
	idx = 0
	if mode_card:
		_refresh()
	else:
		_build_list()

func _build_list() -> void:
	for c in list_scroll.get_children():
		c.queue_free()
	var p := UI.palette()
	var vb := UI.scroll_box()
	list_scroll.add_child(vb)
	if items.is_empty():
		var empty := UI.label("本组暂无词条\n可到「词表」页点「＋ 添加」，或在「设置 - 数据管理」里导入", 30, p.sub, true)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(empty)
		return
	for it in items:
		vb.add_child(_list_row(it, p))

func _list_row(it: Dictionary, p: Dictionary) -> Control:
	var id := _id(it)
	var card := UI.panel(true)   # 长列表用轻量卡片
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	card.add_child(vb)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	vb.add_child(hb)
	var title_text: String = it.w if kind == "words" else it.en
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(tv)
	tv.add_child(UI.label(title_text, 34, p.text, true))
	var meaning: String = String(it.get("m", "")) if kind == "words" else String(it.get("cn", ""))
	tv.add_child(UI.label(meaning, 28, p.sub, true))
	var star := UI.button("★" if DB.is_starred(kind, id) else "☆",
		Color.TRANSPARENT, p.star if DB.is_starred(kind, id) else p.sub, 38)
	star.custom_minimum_size = Vector2(76, 76)
	star.pressed.connect(func():
		var on := DB.toggle_star(kind, id)
		star.text = "★" if on else "☆"
		star.add_theme_color_override("font_color", p.star if on else p.sub))
	hb.add_child(star)
	var spk := UI.button("🔊", p.panel2, p.text, 30)
	spk.custom_minimum_size = Vector2(88, 88)
	spk.pressed.connect(func(): TTS.play_word(title_text, String(it.get("p", "")) if kind == "words" else ""))
	hb.add_child(spk)
	if kind == "words" and not it.get("syn", []).is_empty():
		var detail := UI.label("", 26, p.sub, true)
		var parts := []
		for s in it.get("syn", []):
			parts.append("近义 %s：%s" % [s.get("w", ""), s.get("n", "")])
		for s in it.get("sim", []):
			parts.append("形近 %s：%s" % [s.get("w", ""), s.get("n", "")])
		detail.text = "\n".join(parts)
		vb.add_child(detail)
	return card
