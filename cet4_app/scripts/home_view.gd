extends VBoxContainer
## 学习页：单词/词组分组 + 词表（两列网格，字母序/乱序，分帧加载防卡顿）+ 搜索（防抖+限量+转圈遮罩）

var kind := "words"        # words | phrases（分组模式）
var table_mode := false    # 词表模式
var wl_kind := "words"     # 词表模式下的类别
var wl_shuffle := false    # 词表乱序（否则按字母表排序）
var wl_items: Array = []
var wl_shown := 0
var wl_flow: HFlowContainer = null
const PAGE := 100          # 每页条数
const FRAME_US := 6000     # 每帧构建预算（微秒），超了就等下一帧，防止一帧建太多卡死
const SEARCH_MAX := 60

var seg_words: Button
var seg_phrases: Button
var seg_table: Button
var wl_bar: HBoxContainer
var wl_kind_btn: Button
var wl_order_btn: Button
var search_box: LineEdit
var list_scroll: ScrollContainer
var list_box: VBoxContainer
var more_btn: Button = null
var _last_cols := 0
var _build_gen := 0        # 构建代数：重建时作废进行中的异步构建
var _search_gen := 0       # 搜索防抖代数

func _ready() -> void:
	add_theme_constant_override("separation", 14)
	UI.full_rect(self)
	var p := UI.palette()

	# 分段控件：单词 | 词组 | 词表
	var seg := HBoxContainer.new()
	seg.add_theme_constant_override("separation", 10)
	seg.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(seg)
	seg_words = UI.button("单词", Color.TRANSPARENT, p.text, 32)
	seg_phrases = UI.button("词组", Color.TRANSPARENT, p.text, 32)
	seg_table = UI.button("词表", Color.TRANSPARENT, p.text, 32)
	for b in [seg_words, seg_phrases, seg_table]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		seg.add_child(b)
	seg_words.pressed.connect(_on_seg.bind("words"))
	seg_phrases.pressed.connect(_on_seg.bind("phrases"))
	seg_table.pressed.connect(_on_seg.bind("table"))

	# 词表工具条（搜索框上方，仅词表模式可见）
	wl_bar = HBoxContainer.new()
	wl_bar.add_theme_constant_override("separation", 10)
	wl_bar.visible = false
	add_child(wl_bar)
	wl_kind_btn = UI.button("单词", p.panel2, p.text, 28)
	wl_kind_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wl_kind_btn.pressed.connect(func():
		wl_kind = "phrases" if wl_kind == "words" else "words"
		wl_kind_btn.text = "词组" if wl_kind == "phrases" else "单词"
		_rebuild())
	wl_bar.add_child(wl_kind_btn)
	wl_order_btn = UI.button("字母序", p.panel2, p.text, 28)
	wl_order_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wl_order_btn.pressed.connect(func():
		wl_shuffle = not wl_shuffle
		wl_order_btn.text = "乱序" if wl_shuffle else "字母序"
		_rebuild())
	wl_bar.add_child(wl_order_btn)

	# 搜索框
	search_box = LineEdit.new()
	search_box.placeholder_text = "搜索单词 / 词组 / 中文释义"
	search_box.custom_minimum_size = Vector2(0, 84)
	search_box.add_theme_font_size_override("font_size", 32)
	search_box.add_theme_stylebox_override("normal", UI.style_box(p.panel, 14))
	search_box.add_theme_stylebox_override("focus", UI.style_box(p.panel2, 14))
	search_box.add_theme_color_override("font_color", p.text)
	search_box.add_theme_color_override("font_placeholder_color", p.sub)
	search_box.text_changed.connect(_on_search)
	UI.tap_lock(search_box)
	add_child(search_box)

	list_scroll = UI.make_scroll()
	add_child(list_scroll)
	list_box = UI.scroll_box()
	list_scroll.add_child(list_box)
	list_scroll.resized.connect(_relayout_cols)

	_refresh_seg()
	call_deferred("_rebuild")

func _main() -> Control:
	return get_meta("main")

func _on_seg(k: String) -> void:
	if k == "table":
		table_mode = true
	else:
		table_mode = false
		kind = k
	search_box.text = ""
	_refresh_seg()
	_rebuild()

func _refresh_seg() -> void:
	var p := UI.palette()
	var states := {seg_words: not table_mode and kind == "words",
		seg_phrases: not table_mode and kind == "phrases",
		seg_table: table_mode}
	for b in states:
		b.add_theme_stylebox_override("normal", UI.style_box(p.accent if states[b] else p.panel, 14))
		b.add_theme_color_override("font_color", Color.WHITE if states[b] else p.text)
	wl_bar.visible = table_mode

# ---------------- 列表重建 ----------------
func _clear_list() -> void:
	_build_gen += 1
	more_btn = null
	wl_flow = null
	for c in list_box.get_children():
		c.queue_free()

func _rebuild() -> void:
	if table_mode:
		_build_table()
	else:
		_build_groups()

func _cols() -> int:
	var w := list_scroll.size.x
	# 列数随控件/字体缩放自适应：放大后单列阈值变宽，避免内容把两列撑破版
	var s := maxf(1.0, maxf(UI.ui_scale(), UI.font_scale()))
	var min_cols := 2 if s <= 1.15 else 1
	return clampi(int(w / (620.0 * s)), min_cols, 4)

func _relayout_cols() -> void:
	var c := _cols()
	if c == _last_cols:
		return
	_last_cols = c
	if search_box.text.strip_edges() == "":
		_rebuild()

func _card_w(cols: int) -> float:
	if list_scroll.size.x <= 0:
		return 0.0
	# 预留加粗滚动条(34)和边距，保证 cols 列真的能放进同一行
	return (list_scroll.size.x - 52.0 - (cols - 1) * 14.0) / cols

func _build_groups() -> void:
	_clear_list()
	var gen := _build_gen
	await get_tree().process_frame   # 交还一帧，避免输入事件同帧卡住
	if gen != _build_gen or not is_inside_tree():
		return
	var p := UI.palette()
	var groups: PackedStringArray = DB.word_groups if kind == "words" else DB.phrase_groups
	var main := _main()
	# 宽屏多列网格，竖屏单列
	var cols := _cols()
	_last_cols = cols
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 14)
	flow.add_theme_constant_override("v_separation", 14)
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_child(flow)
	var cw := _card_w(cols)
	for g in groups:
		var prog := DB.group_progress(kind, g)
		var card := UI.panel()
		if cw > 0:
			card.custom_minimum_size = Vector2(cw, 0)
		# 长按卡片空白处 → 自定义分组名
		card.gui_input.connect(_on_card_gui_input.bind(kind, g))
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 14)
		card.add_child(hb)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(info)
		info.add_child(UI.label(g, 32, p.text, true))
		var sub := UI.label("共 %d · 已会 %d · 生词 %d" % [prog.total, prog.known, prog.starred], 26, p.sub, true)
		info.add_child(sub)
		var bar := ProgressBar.new()
		bar.min_value = 0
		bar.max_value = max(1, prog.total)
		bar.value = prog.known
		bar.custom_minimum_size = Vector2(0, 14)
		bar.show_percentage = false
		bar.add_theme_stylebox_override("background", UI.style_box(p.panel2, 7))
		bar.add_theme_stylebox_override("fill", UI.style_box(p.ok, 7))
		info.add_child(bar)
		var btn_box := VBoxContainer.new()
		btn_box.add_theme_constant_override("separation", 8)
		hb.add_child(btn_box)
		var study_btn := UI.button("学习", p.accent, Color.WHITE, 28)
		study_btn.custom_minimum_size = Vector2(150, 70)
		study_btn.pressed.connect(main.open_study.bind(kind, g))
		btn_box.add_child(study_btn)
		var dict_btn := UI.button("听写", p.panel2, p.text, 28)
		dict_btn.custom_minimum_size = Vector2(150, 70)
		dict_btn.pressed.connect(main.open_dictation.bind(kind, g))
		btn_box.add_child(dict_btn)
		flow.add_child(card)
		UI.fade_in(card, minf(flow.get_child_count() * 0.03, 0.2))   # 分组卡片流水渐入

# ---------------- 分组长按重命名 ----------------
var _lp_msec := 0
var _lp_pos := Vector2.ZERO

func _on_card_gui_input(ev: InputEvent, k: String, group: String) -> void:
	if ev is InputEventScreenTouch or ev is InputEventMouseButton:
		if ev.pressed:
			_lp_msec = Time.get_ticks_msec()
			_lp_pos = ev.position
		else:
			if _lp_msec > 0 and Time.get_ticks_msec() - _lp_msec >= 550:
				_group_menu(k, group)
			_lp_msec = 0
	elif ev is InputEventScreenDrag or ev is InputEventMouseMotion:
		if _lp_msec > 0 and ev.position.distance_to(_lp_pos) > 30.0:
			_lp_msec = 0   # 拖动滚动不算长按

## 分组长按菜单：重命名 / 分享（局域网+蓝牙）/ 删除
func _group_menu(k: String, group: String) -> void:
	UI.vibrate(40)
	var p := UI.palette()
	var sh: Dictionary = UI.sheet(self, "分组「%s」" % group, "", "关闭")
	var body: VBoxContainer = sh["body"]
	var rn := UI.button("✏️ 重命名分组", p.panel2, p.text, 29)
	rn.custom_minimum_size = Vector2(0, 80)
	rn.pressed.connect(func():
		UI.dismiss_dialog(sh["overlay"])
		_rename_dialog(k, group))
	body.add_child(rn)
	var share := UI.button("📡 分享本组（局域网 / 蓝牙）", p.panel2, p.text, 29)
	share.custom_minimum_size = Vector2(0, 80)
	share.pressed.connect(func():
		UI.dismiss_dialog(sh["overlay"])
		var md := DB.export_groups_md(k, group)
		LanSyncDialog.open(self, md, group))
	body.add_child(share)
	var del := UI.button("🗑 删除分组", p.panel2, p.danger, 29)
	del.custom_minimum_size = Vector2(0, 80)
	del.pressed.connect(func():
		UI.dismiss_dialog(sh["overlay"])
		UI.confirm_dialog(self, "删除分组",
			"「%s」里的词条将一并删除（删除前自动备份，可在 设置 → 词库回滚 还原），确定吗？" % group,
			func():
				DB.delete_group(k, group)
				UI.toast(self, "已删除「%s」" % group)
				_rebuild(),
			"删除", "取消", true))
	body.add_child(del)

func _rename_dialog(k: String, old_name: String) -> void:
	var p := UI.palette()
	var le := LineEdit.new()
	le.text = old_name
	le.custom_minimum_size = Vector2(0, 76)
	le.add_theme_font_size_override("font_size", 30)
	var sh := UI.sheet(self, "重命名分组", "保存", "取消", func():
		var err := DB.rename_group(k, old_name, le.text)
		if err != "":
			UI.toast(self, err)
		elif le.text.strip_edges() != old_name:
			UI.toast(self, "已重命名为「%s」" % le.text.strip_edges())
		_rebuild())
	sh["body"].add_child(UI.label("当前：%s" % old_name, 26, p.sub))
	sh["body"].add_child(le)

# ---------------- 本地词条编辑（添加/修改，走和 AI 相同的备份+合并通道） ----------------
static func _join_names(arr: Array) -> String:
	var out := []
	for e in arr:
		out.append(String(e.get("w", "")) if e is Dictionary else String(e))
	return "、".join(out)

static func _parse_names(text: String) -> Array:
	var out := []
	for t in text.replace("，", "、").replace(",", "、").replace(";", "、").replace("；", "、").split("、", false):
		var s := t.strip_edges()
		if s != "":
			out.append({"w": s, "n": ""})
	return out

func _edit_dialog(k: String, it: Dictionary) -> void:
	var p := UI.palette()
	var is_word := k == "words"
	var fields := {}
	var defs: Array
	if is_word:
		defs = [["w", "单词 *", it.get("w", "")],
			["p", "音标（如 /tɛst/，可留空）", it.get("p", "")],
			["m", "释义 *（含词性，如 vt. 放弃）", it.get("m", "")],
			["day", "分组", it.get("day", "自定义")],
			["syn", "近义词（顿号/逗号分隔）", _join_names(it.get("syn", []))],
			["sim", "形近词（顿号/逗号分隔）", _join_names(it.get("sim", []))]]
	else:
		defs = [["en", "英文词组 *", it.get("en", "")],
			["cn", "中文释义 *", it.get("cn", "")],
			["sec", "分组", it.get("sec", "自定义")]]
	for f in defs:
		var le := LineEdit.new()
		le.text = String(f[2])
		le.custom_minimum_size = Vector2(0, 68)
		le.add_theme_font_size_override("font_size", 28)
		fields[f[0]] = le
	var sh := UI.sheet(self, ("编辑" if not it.is_empty() else "添加") + ("单词" if is_word else "词组"), "保存", "取消", func():
		var ops := {"add_words": [], "add_phrases": [], "remove_words": [], "remove_phrases": []}
		if is_word:
			var w0: String = fields["w"].text.strip_edges()
			var m0: String = fields["m"].text.strip_edges()
			if w0 == "" or m0 == "":
				UI.toast(self, "单词和释义必填")
				return
			if not it.is_empty() and w0.to_lower() != String(it.get("w", "")).to_lower():
				ops["remove_words"].append(String(it.w))   # 改了拼写 = 删旧加新
			ops["add_words"].append({"w": w0, "p": fields["p"].text.strip_edges(), "m": m0,
				"day": fields["day"].text.strip_edges() if fields["day"].text.strip_edges() != "" else "自定义",
				"syn": _parse_names(fields["syn"].text), "sim": _parse_names(fields["sim"].text)})
		else:
			var e0: String = fields["en"].text.strip_edges()
			var c0: String = fields["cn"].text.strip_edges()
			if e0 == "" or c0 == "":
				UI.toast(self, "英文和中文必填")
				return
			if not it.is_empty() and e0 != String(it.get("en", "")):
				ops["remove_phrases"].append(String(it.en))
			ops["add_phrases"].append({"en": e0, "cn": c0,
				"sec": fields["sec"].text.strip_edges() if fields["sec"].text.strip_edges() != "" else "自定义"})
		UI.toast(self, DB.apply_ai_library_edit(ops))
		_rebuild())
	var vb: VBoxContainer = sh["body"]
	var group_key := "day" if is_word else "sec"
	for f in defs:
		vb.add_child(UI.label(String(f[1]), 24, p.sub))
		if f[0] == group_key:
			# 分组字段：可直接输入新分组名，也可从已有分组里挑一个填入
			var gle: LineEdit = fields[f[0]]
			gle.placeholder_text = "输入新分组名，或点右侧选择已有分组"
			gle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var grow := HBoxContainer.new()
			grow.add_theme_constant_override("separation", 8)
			grow.add_child(gle)
			var groups: Array = Array(DB.word_groups) if is_word else Array(DB.phrase_groups)
			var pick := UI.button("已有分组 ▾", p.panel2, p.text, 24)
			pick.custom_minimum_size = Vector2(240, 68)
			pick.pressed.connect(func():
				if groups.is_empty():
					UI.toast(self, "暂无已有分组，直接输入新分组名即可")
					return
				UI.dropdown(pick, groups, func(i: int): gle.text = String(groups[i])))
			grow.add_child(pick)
			vb.add_child(grow)
		else:
			vb.add_child(fields[f[0]])

# ---------------- 词表（字母序/乱序 + 两列网格 + 分帧分页加载） ----------------
func _build_table() -> void:
	_clear_list()
	var p := UI.palette()
	wl_items = (DB.words if wl_kind == "words" else DB.phrases).duplicate()
	if wl_shuffle:
		wl_items.shuffle()
	else:
		# 按字母表排序
		var key := "w" if wl_kind == "words" else "en"
		wl_items.sort_custom(func(a, b):
			return String(a.get(key, "")).nocasecmp_to(String(b.get(key, ""))) < 0)
	wl_shown = 0
	var cols := _cols()
	_last_cols = cols
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	list_box.add_child(head)
	var cnt := UI.label("共 %d 条 · %s · 两列网格分页加载" % [
		wl_items.size(), "乱序" if wl_shuffle else "字母序"], 26, p.sub)
	cnt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cnt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(cnt)
	var add_btn := UI.button("＋ 添加", p.accent, Color.WHITE, 26)
	add_btn.custom_minimum_size = Vector2(200, 72)
	add_btn.pressed.connect(func(): _edit_dialog(wl_kind, {}))
	head.add_child(add_btn)
	wl_flow = HFlowContainer.new()
	wl_flow.add_theme_constant_override("h_separation", 14)
	wl_flow.add_theme_constant_override("v_separation", 14)
	wl_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_child(wl_flow)
	_append_table_page()

func _append_table_page() -> void:
	var gen := _build_gen
	if more_btn != null and is_instance_valid(more_btn):
		more_btn.queue_free()
		more_btn = null
	if wl_flow == null or not is_instance_valid(wl_flow):
		return
	var p := UI.palette()
	var cw := _card_w(_cols())
	var end: int = mini(wl_shown + PAGE, wl_items.size())
	var i := wl_shown
	var t0 := Time.get_ticks_usec()
	while i < end:
		var it: Dictionary = wl_items[i]
		var row: Control = _word_row(it, p) if wl_kind == "words" else _phrase_row(it, p)
		if cw > 0:
			row.custom_minimum_size = Vector2(cw, 0)
		wl_flow.add_child(row)
		UI.fade_in(row, minf((i - wl_shown) * 0.025, 0.18))   # 流水式渐入
		i += 1
		if i < end and Time.get_ticks_usec() - t0 > FRAME_US:
			await get_tree().process_frame   # 时间预算用完就交还一帧，避免卡死
			if gen != _build_gen or not is_instance_valid(wl_flow):
				return   # 已被重建作废
			t0 = Time.get_ticks_usec()
	wl_shown = end
	if gen != _build_gen:
		return
	if wl_shown < wl_items.size():
		more_btn = UI.button("加载更多（已显示 %d / %d）" % [wl_shown, wl_items.size()], p.panel2, p.text, 28)
		more_btn.pressed.connect(_append_table_page)
		list_box.add_child(more_btn)

# ---------------- 搜索（防抖 + 时间预算分帧 + 限量） ----------------
func _on_search(q: String) -> void:
	_search_gen += 1
	var gen := _search_gen
	if q.strip_edges() == "":
		_rebuild()
		return
	await get_tree().create_timer(0.25).timeout   # 防抖：停止输入 0.25s 后才真正搜
	if gen != _search_gen or not is_inside_tree():
		return
	_do_search(q, gen)

func _do_search(q: String, gen: int) -> void:
	_clear_list()
	var p := UI.palette()
	var res := DB.search(q)   # 走小写缓存索引，纯数据扫描很快
	var header := UI.label("单词 %d 条 · 词组 %d 条（各最多显示前 %d 条）" % [
		res.words.size(), res.phrases.size(), SEARCH_MAX], 28, p.sub)
	list_box.add_child(header)
	var todo: Array = []
	for w in res.words.slice(0, SEARCH_MAX):
		todo.append(["words", w])
	for ph in res.phrases.slice(0, SEARCH_MAX):
		todo.append(["phrases", ph])
	var i := 0
	var t0 := Time.get_ticks_usec()
	while i < todo.size():
		var k: String = todo[i][0]
		var it: Dictionary = todo[i][1]
		list_box.add_child(_word_row(it, p) if k == "words" else _phrase_row(it, p))
		i += 1
		if i < todo.size() and Time.get_ticks_usec() - t0 > FRAME_US:
			await get_tree().process_frame
			if gen != _search_gen or not is_inside_tree():
				return   # 已被新的搜索作废
			t0 = Time.get_ticks_usec()

func _word_row(w: Dictionary, p: Dictionary) -> Control:
	return _result_row(w.w, String(w.get("p", "")), String(w.get("m", "")),
		"words", DB.word_id(w), w.w, p, false, w)

func _phrase_row(ph: Dictionary, p: Dictionary) -> Control:
	# 词组英文较长：用可换行标签，卡片最小宽度才能收进半屏，保证两列排版
	return _result_row(ph.en, "", String(ph.get("cn", "")),
		"phrases", DB.phrase_id(ph), ph.en, p, true, ph)

func _result_row(title: String, phonetic: String, meaning: String,
		kind: String, id: String, speak_text: String, p: Dictionary, wrap := false,
		src: Dictionary = {}) -> Control:
	var card := UI.panel(true)   # 长列表用轻量卡片（无投影），防滚动卡顿
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	card.add_child(hb)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(vb)
	vb.add_child(UI.label(title, 32, p.text, true) if wrap else UI.row_label(title, 32, p.text))
	if phonetic != "":
		vb.add_child(UI.label(phonetic, 24, p.sub, true) if wrap else UI.row_label(phonetic, 24, p.sub))
	vb.add_child(UI.label(meaning, 26, p.sub, true) if wrap else UI.row_label(meaning, 26, p.sub))
	var btn_col := VBoxContainer.new()
	btn_col.add_theme_constant_override("separation", 4)
	hb.add_child(btn_col)
	var starred := DB.is_starred(kind, id)
	var star := UI.icon_btn("★" if starred else "☆", p.star if starred else p.sub, 40)
	star.pressed.connect(func():
		var on := DB.toggle_star(kind, id)
		star.text = "★" if on else "☆"
		star.add_theme_color_override("font_color", p.star if on else p.sub)
		UI.pop(star))
	btn_col.add_child(star)
	var spk := UI.icon_btn("🔊", p.accent, 34)
	spk.pressed.connect(func(): TTS.play_word(speak_text))
	btn_col.add_child(spk)
	if not src.is_empty():
		var edit := UI.icon_btn("✎", p.sub, 34)
		edit.pressed.connect(func(): _edit_dialog(kind, src))
		btn_col.add_child(edit)
	return card
