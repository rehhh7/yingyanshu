extends VBoxContainer
## 统计页：连续打卡 / 今日 / 累计 / 听写正确率 / 分组进度

func _ready() -> void:
	add_theme_constant_override("separation", 14)
	UI.full_rect(self)
	DB.progress_changed.connect(_rebuild)
	DB.library_changed.connect(_rebuild)
	var scroll := UI.make_scroll()
	add_child(scroll)
	var box := UI.scroll_box()
	box.name = "Box"
	scroll.add_child(box)
	_rebuild()

func _rebuild() -> void:
	if not is_inside_tree(): return
	var box := find_child("Box", true, false) as VBoxContainer
	if box == null: return
	for c in box.get_children():
		c.queue_free()
	var p := UI.palette()
	var s := DB.stats_summary()

	# 顶部大数字卡
	var top := UI.panel()
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 12)
	top.add_child(th)
	box.add_child(top)
	th.add_child(_stat_block("🔥 %d 天" % s.streak, "连续打卡", p))
	th.add_child(_stat_block(str(s.today_learned), "今日学习", p))
	var dict_total: int = s.dict_correct + s.dict_wrong
	var acc := int(round(100.0 * s.dict_correct / dict_total)) if dict_total > 0 else 0
	th.add_child(_stat_block("%d%%" % acc, "听写正确率", p))

	# 累计进度
	var card := UI.panel()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	card.add_child(vb)
	box.add_child(card)
	vb.add_child(UI.label("累计进度", 32, p.text))
	vb.add_child(_bar_row("单词", s.known_words, s.total_words, p))
	vb.add_child(_bar_row("词组", s.known_phrases, s.total_phrases, p))
	vb.add_child(UI.label("生词：单词 %d · 词组 %d" % [s.star_words, s.star_phrases], 28, p.sub))
	vb.add_child(UI.label("听写累计：对 %d · 错 %d" % [s.dict_correct, s.dict_wrong], 28, p.sub))

	# 分组进度
	box.add_child(UI.label("各组进度", 32, p.text))
	for g in DB.word_groups:
		var prog := DB.group_progress("words", g)
		box.add_child(_group_row(g, prog, p))
	for g in DB.phrase_groups:
		var prog := DB.group_progress("phrases", g)
		box.add_child(_group_row(g, prog, p))

func _stat_block(big: String, small: String, p: Dictionary) -> Control:
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	var a := UI.label(big, 44, p.accent)
	a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(a)
	var b := UI.label(small, 26, p.sub)
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(b)
	return vb

func _bar_row(name: String, done: int, total: int, p: Dictionary) -> Control:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	vb.add_child(UI.label("%s %d / %d" % [name, done, total], 28, p.text))
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = max(1, total)
	bar.value = done
	bar.custom_minimum_size = Vector2(0, 18)
	bar.show_percentage = false
	bar.add_theme_stylebox_override("background", UI.style_box(p.panel2, 9))
	bar.add_theme_stylebox_override("fill", UI.style_box(p.ok, 9))
	vb.add_child(bar)
	return vb

func _group_row(g: String, prog: Dictionary, p: Dictionary) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	var name_lbl := UI.label(g, 26, p.text)
	name_lbl.custom_minimum_size = Vector2(330, 0)
	hb.add_child(name_lbl)
	var bar := ProgressBar.new()
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.min_value = 0
	bar.max_value = max(1, prog.total)
	bar.value = prog.known
	bar.custom_minimum_size = Vector2(0, 16)
	bar.show_percentage = false
	bar.add_theme_stylebox_override("background", UI.style_box(p.panel2, 8))
	bar.add_theme_stylebox_override("fill", UI.style_box(p.accent, 8))
	hb.add_child(bar)
	hb.add_child(UI.label("%d/%d" % [prog.known, prog.total], 24, p.sub))
	return hb
