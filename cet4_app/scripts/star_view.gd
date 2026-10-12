extends VBoxContainer
## 生词页：单词/词组星标列表（字母序/乱序 + 收藏日期）+ 导出

var kind := "words"
var shuffle := false       # false=字母序 true=乱序
var seg_w: Button
var seg_p: Button
var order_btn: Button
var scroll: ScrollContainer
var box: VBoxContainer

func _ready() -> void:
	add_theme_constant_override("separation", 14)
	UI.full_rect(self)
	var p := UI.palette()
	var seg := HBoxContainer.new()
	seg.add_theme_constant_override("separation", 10)
	seg.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(seg)
	seg_w = UI.button("单词生词", Color.TRANSPARENT, p.text, 30)
	seg_p = UI.button("词组生词", Color.TRANSPARENT, p.text, 30)
	for b in [seg_w, seg_p]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		seg.add_child(b)
	seg_w.pressed.connect(_on_seg.bind("words"))
	seg_p.pressed.connect(_on_seg.bind("phrases"))

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 10)
	add_child(row2)
	order_btn = UI.button("字母序", p.panel2, p.text, 28)
	order_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	order_btn.pressed.connect(func():
		shuffle = not shuffle
		order_btn.text = "乱序" if shuffle else "字母序"
		_rebuild())
	row2.add_child(order_btn)
	var export_btn := UI.button("导出生词", p.accent, Color.WHITE, 28)
	export_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	export_btn.pressed.connect(func():
		UI.double_press(export_btn, "再按一次确认导出", _on_export))
	row2.add_child(export_btn)

	scroll = UI.make_scroll()
	add_child(scroll)
	box = UI.scroll_box()
	scroll.add_child(box)
	DB.progress_changed.connect(_rebuild)
	_refresh_seg()
	_rebuild()

func _on_seg(k: String) -> void:
	kind = k
	_refresh_seg()
	_rebuild()

func _refresh_seg() -> void:
	var p := UI.palette()
	seg_w.add_theme_stylebox_override("normal", UI.style_box(p.accent if kind == "words" else p.panel, 14))
	seg_p.add_theme_stylebox_override("normal", UI.style_box(p.accent if kind == "phrases" else p.panel, 14))
	seg_w.add_theme_color_override("font_color", Color.WHITE if kind == "words" else p.text)
	seg_p.add_theme_color_override("font_color", Color.WHITE if kind == "phrases" else p.text)

func _rebuild() -> void:
	if not is_inside_tree(): return
	for c in box.get_children():
		c.queue_free()
	var p := UI.palette()
	var items := DB.starred_items(kind)
	if items.is_empty():
		box.add_child(UI.label("还没有生词，学习时点 ⭐ 收藏", 30, p.sub))
		return
	if shuffle:
		items.shuffle()
	else:
		var key := "w" if kind == "words" else "en"
		items.sort_custom(func(a, b):
			return String(a.get(key, "")).nocasecmp_to(String(b.get(key, ""))) < 0)
	box.add_child(UI.label("共 %d 条 · %s" % [items.size(), "乱序" if shuffle else "字母序"], 28, p.sub))
	for it in items:
		box.add_child(_row(it, p))

func _row(it: Dictionary, p: Dictionary) -> Control:
	var id: String = DB.word_id(it) if kind == "words" else DB.phrase_id(it)
	var card := UI.panel(true)   # 长列表用轻量卡片
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	card.add_child(hb)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(vb)
	var title_text: String = it.w if kind == "words" else it.en
	vb.add_child(UI.label(title_text, 34, p.text, true))
	var meaning: String = String(it.get("m", "")) if kind == "words" else String(it.get("cn", ""))
	vb.add_child(UI.label(meaning, 28, p.sub, true))
	var group_name: String = it.get("day", "") if kind == "words" else it.get("sec", "")
	var date := DB.star_date(kind, id)
	var meta := group_name
	if date != "":
		meta += " · 收藏于 " + date
	vb.add_child(UI.label(meta, 22, p.sub))
	var star := UI.icon_btn("★", p.star, 40)
	star.pressed.connect(func(): DB.toggle_star(kind, id))
	hb.add_child(star)
	var spk := UI.icon_btn("🔊", p.accent, 36)
	spk.pressed.connect(func(): TTS.play_word(title_text))
	hb.add_child(spk)
	return card

func _on_export() -> void:
	var path := DB.export_starred()
	UI.toast(self, "已导出：" + path)
