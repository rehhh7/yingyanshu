extends VBoxContainer
## 听写/拼写测试：出中文释义 → 默写英文（或播放发音听写）

signal back_requested

var kind := "words"
var group := ""
var items: Array = []
var idx := 0
var correct_cnt := 0
var wrong: Array = []

var prompt_lbl: Label
var input: LineEdit
var feedback_lbl: Label
var progress_lbl: Label
var submit_btn: Button
var answered := false

func _ready() -> void:
	add_theme_constant_override("separation", 16)
	UI.full_rect(self)
	var p := UI.palette()
	items = (DB.words_in_group(group) if kind == "words" else DB.phrases_in_group(group)).duplicate()
	items.shuffle()

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	add_child(top)
	var back := UI.button("← 返回", p.panel2, p.text, 28)
	back.custom_minimum_size = Vector2(170, 76)
	back.pressed.connect(func(): back_requested.emit())
	top.add_child(back)
	progress_lbl = UI.label("", 30, p.sub)
	progress_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(progress_lbl)

	var card := UI.panel()
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(card)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 20)
	card.add_child(vb)

	vb.add_child(UI.label("根据释义默写英文：", 30, p.sub))
	prompt_lbl = UI.label("", 44, p.text, true)
	prompt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(prompt_lbl)
	var spk := UI.button("🔊 播放发音（听音默写）", p.panel2, p.text, 28)
	spk.pressed.connect(func(): TTS.play_word(_answer(), _phonetic()))
	vb.add_child(spk)

	input = LineEdit.new()
	input.placeholder_text = "输入英文，回车提交"
	input.custom_minimum_size = Vector2(0, 96)
	input.add_theme_font_size_override("font_size", 36)
	input.add_theme_stylebox_override("normal", UI.style_box(p.panel2, 14))
	input.add_theme_stylebox_override("focus", UI.style_box(p.panel2, 14, p.accent, 2))
	input.add_theme_color_override("font_color", p.text)
	input.add_theme_color_override("font_placeholder_color", p.sub)
	input.text_submitted.connect(_on_submit_text)
	vb.add_child(input)

	feedback_lbl = UI.label("", 32, p.sub)
	feedback_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(feedback_lbl)

	submit_btn = UI.button("提交", p.accent, Color.WHITE, 32)
	submit_btn.pressed.connect(_on_submit)
	vb.add_child(submit_btn)

	_next()

func _answer() -> String:
	var it: Dictionary = items[idx]
	return String(it.w) if kind == "words" else String(it.en)

func _phonetic() -> String:
	var it: Dictionary = items[idx]
	return String(it.get("p", "")) if kind == "words" else ""

func _next() -> void:
	if idx >= items.size():
		_finish()
		return
	answered = false
	var it: Dictionary = items[idx]
	prompt_lbl.text = String(it.get("m", "")) if kind == "words" else String(it.get("cn", ""))
	progress_lbl.text = "%d / %d   ✓%d" % [idx + 1, items.size(), correct_cnt]
	input.text = ""
	feedback_lbl.text = ""
	submit_btn.text = "提交"
	input.grab_focus()

func _on_submit_text(_t := "") -> void:
	_on_submit()

func _on_submit() -> void:
	if items.is_empty(): return
	if answered:
		idx += 1
		_next()
		return
	answered = true
	var p := UI.palette()
	var ans := input.text.strip_edges().to_lower()
	var right := _answer().to_lower()
	var it: Dictionary = items[idx]
	var id: String = DB.word_id(it) if kind == "words" else DB.phrase_id(it)
	if ans == right:
		correct_cnt += 1
		DB.record_dictation(true)
		DB.mark_known(kind, id, true)
		feedback_lbl.text = "✓ 正确"
		feedback_lbl.add_theme_color_override("font_color", p.ok)
	else:
		DB.record_dictation(false)
		DB.mark_known(kind, id, false)
		if not DB.is_starred(kind, id):
			DB.toggle_star(kind, id)
		wrong.append(it)
		feedback_lbl.text = "✗ 正确答案：" + _answer()
		feedback_lbl.add_theme_color_override("font_color", p.danger)
	progress_lbl.text = "%d / %d   ✓%d" % [idx + 1, items.size(), correct_cnt]
	submit_btn.text = "下一题"

func _finish() -> void:
	var p := UI.palette()
	for c in get_children():
		if c is PanelContainer or c is HBoxContainer:
			c.queue_free()
	var card := UI.panel()
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(card)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 20)
	card.add_child(vb)
	var total := items.size()
	var pct := int(round(100.0 * correct_cnt / max(1, total)))
	vb.add_child(UI.label("听写完成！", 44, p.text))
	vb.add_child(UI.label("正确 %d / %d（%d%%）" % [correct_cnt, total, pct], 36, p.ok if pct >= 60 else p.danger))
	if not wrong.is_empty():
		vb.add_child(UI.label("以下 %d 个已自动加入生词：" % wrong.size(), 28, p.sub))
		for it in wrong.slice(0, 8):
			vb.add_child(UI.label("· " + (String(it.w) if kind == "words" else String(it.en)), 28, p.sub))
	var back := UI.button("返回", p.accent, Color.WHITE, 32)
	back.custom_minimum_size = Vector2(400, 96)
	back.pressed.connect(func(): back_requested.emit())
	vb.add_child(back)
