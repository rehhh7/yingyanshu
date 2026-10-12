extends VBoxContainer
## 设置页（分组）：外观 / 字体 / 发音 / AI API / 数据管理 / 回滚与重置 / 关于

# 备份列表状态：_rb_batch=批量管理模式，_rb_sel=勾选的备份文件名
var _rb_list: VBoxContainer = null
var _rb_batch := false
var _rb_sel := {}

func _ready() -> void:
	add_theme_constant_override("separation", 14)
	UI.full_rect(self)
	var p := UI.palette()
	var scroll := UI.make_scroll()
	add_child(scroll)
	var box := UI.scroll_box()
	scroll.add_child(box)

	# ================= 外观 =================
	var g_look := _group("外观", true)
	box.add_child(g_look)
	var look: VBoxContainer = g_look.get_meta("body")

	var theme_card := UI.panel()
	var th := HBoxContainer.new()
	theme_card.add_child(th)
	th.add_child(UI.label("深色模式", 30, p.text))
	var sp0 := Control.new()
	sp0.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(sp0)
	th.add_child(UI.make_switch(DB.settings.get("theme_dark", true), func(on: bool):
		DB.settings["theme_dark"] = on
		DB.save_settings()
		var main = get_meta("main")
		if main != null and main.has_method("_fade_theme_reload"):
			main._fade_theme_reload()
		else:
			get_tree().reload_current_scene()))
	look.add_child(theme_card)

	# 壁纸
	var wp_card := UI.panel()
	var wv := VBoxContainer.new()
	wv.add_theme_constant_override("separation", 10)
	wp_card.add_child(wv)
	wv.add_child(UI.label("背景壁纸", 30, p.text))
	var has_wp := String(DB.settings.get("wallpaper", "")) != ""
	wp_status_lbl = UI.label("当前：" + ("自定义壁纸" if has_wp else "默认纯色"), 26, p.sub)
	wv.add_child(wp_status_lbl)
	var wp_row := HBoxContainer.new()
	wp_row.add_theme_constant_override("separation", 10)
	wv.add_child(wp_row)
	var wp_pick := UI.button("更换壁纸……", p.accent, Color.WHITE, 28)
	wp_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wp_pick.pressed.connect(_pick_wallpaper)
	wp_row.add_child(wp_pick)
	var wp_clear := UI.button("恢复默认", p.panel2, p.text, 28)
	wp_clear.custom_minimum_size = Vector2(220, 84)
	wp_clear.pressed.connect(func():
		DB.settings.erase("wallpaper")
		DB.save_settings()
		var f := "user://wallpaper.png"
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
		_reload())
	wp_row.add_child(wp_clear)
	look.add_child(wp_card)

	# 按钮大小
	var scale_card := UI.panel()
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 10)
	scale_card.add_child(sv)
	sv.add_child(UI.label("按钮大小", 30, p.text))
	var slider := HSlider.new()
	slider.min_value = 0.8
	slider.max_value = 1.4
	slider.step = 0.05
	slider.value = clampf(float(DB.settings.get("ui_scale", 1.0)), 0.8, 1.4)
	slider.custom_minimum_size = Vector2(0, 96)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI.style_slider(slider)
	sv.add_child(slider)
	var preview := UI.button("预览按钮 %d%%" % int(slider.value * 100), p.accent, Color.WHITE, 30)
	sv.add_child(preview)
	sv.add_child(UI.label("拖动滑块实时预览，松手后生效到整个应用", 24, p.sub))
	slider.value_changed.connect(func(v: float):
		var sc := snappedf(v, 0.05)
		preview.text = "预览按钮 %d%%" % int(sc * 100)
		preview.custom_minimum_size = Vector2(0, 84 * sc)
		preview.add_theme_font_size_override("font_size", int(30 * sc)))
	slider.drag_ended.connect(func(_value_changed: bool):
		DB.settings["ui_scale"] = snappedf(slider.value, 0.05)
		DB.save_settings()
		_reload())
	look.add_child(scale_card)

	await get_tree().process_frame   # 分帧构建：设置页分多帧建，打开不再一帧建完卡顿
	if not is_inside_tree():
		return
	# ================= 字体 =================
	var g_font := _group("字体", true)
	box.add_child(g_font)
	var font_box: VBoxContainer = g_font.get_meta("body")
	var font_card := UI.panel()
	var fv := VBoxContainer.new()
	fv.add_theme_constant_override("separation", 10)
	font_card.add_child(fv)
	fv.add_child(UI.label("字体大小", 30, p.text))
	var fslider := HSlider.new()
	fslider.min_value = 0.8
	fslider.max_value = 1.6
	fslider.step = 0.05
	fslider.value = clampf(float(DB.settings.get("font_scale", 1.0)), 0.8, 1.6)
	fslider.custom_minimum_size = Vector2(0, 96)
	fslider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI.style_slider(fslider)
	fv.add_child(fslider)
	var fpreview := UI.label("预览：四级单词 Vocabulary（%d%%）" % int(fslider.value * 100), 30, p.text)
	fpreview.mouse_filter = Control.MOUSE_FILTER_STOP
	fv.add_child(fpreview)
	fslider.value_changed.connect(func(v: float):
		var sc := snappedf(v, 0.05)
		fpreview.text = "预览：四级单词 Vocabulary（%d%%）" % int(sc * 100)
		fpreview.add_theme_font_size_override("font_size", int(30 * sc)))
	fslider.drag_ended.connect(func(_value_changed: bool):
		DB.settings["font_scale"] = snappedf(fslider.value, 0.05)
		DB.save_settings()
		_reload())
	font_box.add_child(font_card)
	# 字体加粗开关
	var bold_card := UI.panel()
	var bh := HBoxContainer.new()
	bold_card.add_child(bh)
	bh.add_child(UI.label("字体加粗", 30, p.text))
	var spb := Control.new()
	spb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bh.add_child(spb)
	bh.add_child(UI.make_switch(bool(DB.settings.get("font_bold", false)), func(on: bool):
		DB.settings["font_bold"] = on
		DB.save_settings()
		_reload()))
	font_box.add_child(bold_card)
	# 低配模式开关：关阴影/粒子保帧率，默认按 CPU 核数自动判断
	var perf_card := UI.panel()
	var ph := HBoxContainer.new()
	perf_card.add_child(ph)
	ph.add_child(UI.label("低配模式（关阴影/粒子，更流畅）", 30, p.text))
	var spp := Control.new()
	spp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ph.add_child(spp)
	ph.add_child(UI.make_switch(UI.low_end(), func(on: bool):
		DB.settings["low_end_mode"] = on
		DB.save_settings()
		_reload()))
	font_box.add_child(perf_card)
	# 触感震动开关：按钮轻震、长按菜单震动，关掉即全局静默
	var hap_card := UI.panel()
	var hh := HBoxContainer.new()
	hap_card.add_child(hh)
	hh.add_child(UI.label("触感震动（按钮/长按菜单）", 30, p.text))
	var sph := Control.new()
	sph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hh.add_child(sph)
	hh.add_child(UI.make_switch(bool(DB.settings.get("haptics", true)), func(on: bool):
		DB.settings["haptics"] = on
		DB.save_settings()
		if on:
			UI.vibrate(30)))
	font_box.add_child(hap_card)

	await get_tree().process_frame
	if not is_inside_tree():
		return
	# ================= 发音 =================
	var g_tts := _group("发音", false)
	box.add_child(g_tts)
	var tts_box: VBoxContainer = g_tts.get_meta("body")
	var rate_card := UI.panel()
	var rh := HBoxContainer.new()
	rate_card.add_child(rh)
	rh.add_child(UI.label("默认发音语速", 30, p.text))
	var sp1 := Control.new()
	sp1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rh.add_child(sp1)
	var rate_btn := UI.button("%.1fx" % float(DB.settings.get("tts_rate", 1.0)), p.panel2, p.text, 28)
	rate_btn.custom_minimum_size = Vector2(180, 72)
	rate_btn.pressed.connect(func():
		var r := float(DB.settings.get("tts_rate", 1.0))
		r = 0.7 if r >= 1.0 else 1.0
		DB.settings["tts_rate"] = r
		DB.save_settings()
		rate_btn.text = "%.1fx" % r)
	rh.add_child(rate_btn)
	tts_box.add_child(rate_card)
	# 系统语音引擎状态：内置 605 词走录音不受影响，导入新词的兜底依赖系统英文语音
	var eng_card := UI.panel()
	var evb := VBoxContainer.new()
	eng_card.add_child(evb)
	var en_voices := TTS.english_voices()
	if en_voices.is_empty():
		evb.add_child(UI.label("系统语音引擎：未检测到英文语音", 28, p.danger))
		evb.add_child(UI.label("内置单词发音不受影响；但你导入的新词将无法朗读。可到系统「设置 → 无障碍 → 文字转语音（TTS）输出」安装英文语音数据。", 24, p.sub, true))
	else:
		evb.add_child(UI.label("系统语音引擎：已检测到 %d 个英文语音" % en_voices.size(), 28, p.ok))
		evb.add_child(UI.label("内置单词用真人录音；导入的新词由系统引擎朗读。", 24, p.sub, true))
	var test_btn := UI.button("🔊 试听系统发音", p.panel2, p.text, 28)
	test_btn.custom_minimum_size = Vector2(280, 72)
	test_btn.pressed.connect(func(): TTS.speak("apple"))
	evb.add_child(test_btn)
	tts_box.add_child(eng_card)
	# 无系统语音时的联网发音开关（默认开）：只有内置录音和系统 TTS 都不可用时才会联网
	var oa_card := UI.panel()
	var oah := HBoxContainer.new()
	oa_card.add_child(oah)
	oah.add_child(UI.label("无系统语音时联网发音", 30, p.text))
	var spo := Control.new()
	spo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	oah.add_child(spo)
	oah.add_child(UI.make_switch(bool(DB.settings.get("online_audio", true)), func(on: bool):
		DB.settings["online_audio"] = on
		DB.save_settings()))
	tts_box.add_child(oa_card)
	tts_box.add_child(UI.label("开启后：手机没有英文语音时，新词自动改用有道词典的真人发音（仅此时联网，听过一次就缓存离线可播）。", 24, p.sub, true))

	await get_tree().process_frame
	if not is_inside_tree():
		return
	# ================= AI API =================
	var g_ai := _group("AI API", false)
	box.add_child(g_ai)
	var ai_box: VBoxContainer = g_ai.get_meta("body")
	ai_box.add_child(_input_row("API Key", String(DB.settings.get("api_key", "")), true,
		func(t: String): DB.settings["api_key"] = t.strip_edges()))
	var base_card := _input_row("接口地址", String(DB.settings.get("api_base", "https://api.deepseek.com")), false,
		func(t: String): DB.settings["api_base"] = t.strip_edges().trim_suffix("/"))
	ai_box.add_child(base_card)
	var model_card := _input_row("模型", String(DB.settings.get("api_model", "deepseek-v4-flash")), false,
		func(t: String): DB.settings["api_model"] = t.strip_edges())
	# 常用 API 端口预设：点按直接填入输入框并保存（不刷新页面，不会跳到别的界面）
	ai_box.add_child(UI.label("常用接口（点按自动填入，Key 需自行填写）：", 24, p.sub))
	var pre_flow := HFlowContainer.new()
	pre_flow.add_theme_constant_override("h_separation", 10)
	pre_flow.add_theme_constant_override("v_separation", 10)
	ai_box.add_child(pre_flow)
	var presets := [
		["DeepSeek 官方", "https://api.deepseek.com", "deepseek-v4-flash"],
		["硅基流动", "https://api.siliconflow.cn/v1", "deepseek-ai/DeepSeek-V3.2"],
		["OpenRouter", "https://openrouter.ai/api/v1", "deepseek/deepseek-chat"],
		["Moonshot Kimi", "https://api.moonshot.cn/v1", "kimi-k2.6"],
	]
	for pre in presets:
		var b := UI.button(pre[0], p.panel2, p.text, 24)
		b.custom_minimum_size = Vector2(0, 76)
		pre_flow.add_child(b)
		b.pressed.connect(func():
			var pre2: Array = pre
			DB.settings["api_base"] = pre2[1]
			DB.settings["api_model"] = pre2[2]
			DB.save_settings()
			(base_card.get_meta("le") as LineEdit).text = pre2[1]
			(model_card.get_meta("le") as LineEdit).text = pre2[2]
			UI.toast(self, "已填入 " + String(pre2[0])))
	ai_box.add_child(model_card)
	var save_ai := UI.button("保存 AI 设置", p.accent, Color.WHITE, 30)
	save_ai.pressed.connect(func():
		DB.save_settings()
		UI.toast(self, "已保存"))
	ai_box.add_child(save_ai)
	ai_box.add_child(UI.label("Key 只保存在本机，不会上传。DeepSeek 官方模型填 deepseek-v4-flash（快、便宜）或 deepseek-v4-pro（更强，支持思考链）；旧型号 deepseek-chat 已于 2026-07 退役。", 24, p.sub, true))

	# ---- AI 长期记忆管理 ----
	ai_box.add_child(UI.label("AI 长期记忆：助手会记住你的偏好、薄弱点等，之后每次对话自动携带；也可以在 AI 页直接对它说「记住：……」或「忘掉……」：", 24, p.sub, true))
	var mem_row := HBoxContainer.new()
	mem_row.add_theme_constant_override("separation", 10)
	ai_box.add_child(mem_row)
	var mem_view := UI.button("🧠 查看记忆（%d 条）" % DB.ai_memory.size(), p.panel2, p.text, 28)
	mem_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mem_view.pressed.connect(func(): _show_memory(mem_view))
	mem_row.add_child(mem_view)
	var mem_clear := UI.button("清空", p.panel2, p.danger, 28)
	mem_clear.custom_minimum_size = Vector2(160, 0)
	mem_clear.pressed.connect(func():
		UI.double_press(mem_clear, "再按一次确认清空", func():
			DB.memory_clear()
			mem_view.text = "🧠 查看记忆（0 条）"
			UI.toast(self, "已清空 AI 记忆")))
	mem_row.add_child(mem_clear)

	await get_tree().process_frame
	if not is_inside_tree():
		return
	# ================= 数据管理 =================
	var g_data := _group("数据管理", false)
	box.add_child(g_data)
	var data_box: VBoxContainer = g_data.get_meta("body")
	var exp_docx := UI.button("导出备份（Word 文档，可另存/分享）", p.accent, Color.WHITE, 28)
	exp_docx.pressed.connect(func():
		UI.double_press(exp_docx, "再按一次确认导出", func():
			_export_and_maybe_share(DB.export_docx(), "英眼书备份.docx",
				"*.docx;Word 文档;application/vnd.openxmlformats-officedocument.wordprocessingml.document",
				"application/vnd.openxmlformats-officedocument.wordprocessingml.document")))
	data_box.add_child(exp_docx)
	var exp_json := UI.button("导出 JSON 数据（用于回导恢复）", p.panel2, p.text, 28)
	exp_json.pressed.connect(func():
		UI.double_press(exp_json, "再按一次确认导出", func():
			_export_and_maybe_share(DB.export_all(), "英眼书备份.json", "*.json;JSON;application/json", "application/json")))
	data_box.add_child(exp_json)

	data_box.add_child(UI.label("导入单词：粘贴文本或选择文件（docx / txt / md）。「本地整理」不联网，程序自动识别「单词/词组 + 释义」、检索词库查重、放入新的 Day 分组，逐条确认后入库；带「# 组名」标题的文件（含互传收到的文件）会按组名直接入库；格式太杂乱时可用「交给 AI 整理」。兼容旧版 JSON 备份。", 26, p.sub, true))
	# 可识别格式示例（折叠起来，需要时点开）
	var fmt_g := _group("📋 能识别的格式（点开看示例）", false)
	data_box.add_child(fmt_g)
	var fmt_b: VBoxContainer = fmt_g.get_meta("body")
	fmt_b.add_child(UI.label("abandon 放弃\nabandon v. 放弃\nabandon /əˈbændən/ n. 放弃\nabandon/əˈbændən/ 放弃\ntake off 起飞；脱下（词组自动识别）\n—— 表格/词典导出也能直接粘 ——\nabandon⇥/əˈbændən/⇥n. 放弃（Tab 分列）\nabandon,/əˈbændən/,\"n. 放弃\"（ECDICT 式 CSV）\n{\"word\":\"abandon\",\"translation\":\"n. 放弃\"}（JSONL）\n—— 分组格式（互传文件同款）——\n# 我的第一组\nabandon 放弃\n# 我的第二组\ntake off 起飞", 26, p.text, true))
	fmt_b.add_child(UI.label("规则：每行一条，先英文后中文，释义必须是中文；行首的 1. / - / • 等序号自动忽略；Day 5、Unit 2 这类标题行自动跳过；以「# 组名」开头的行是分组标题，其下词条按该组入库（可整段多组）；PDF/拍照常见的「两条挤一行」会自动拆开。内容不是单词表时（如录音稿、文章）会弹出格式提示，请改用「交给 AI 整理」。", 24, p.sub, true))
	var paste := TextEdit.new()
	paste.custom_minimum_size = Vector2(0, 240)
	paste.placeholder_text = "长按或双击后，粘贴单词文本（每行：单词 中文释义）……"
	paste.add_theme_font_size_override("font_size", 26)
	# 固定「纸张」样式：浅色底 + 黑色加粗文字，深浅主题下都清晰可读
	var paste_sb := UI.style_box(Color(0.96, 0.945, 0.90), 14)
	paste_sb.content_margin_right = 44   # 给纤细滚动条让位，文字不再被滑块遮挡
	paste.add_theme_stylebox_override("normal", paste_sb)
	paste.add_theme_color_override("font_color", Color(0.13, 0.11, 0.10))
	paste.add_theme_color_override("font_readonly_color", Color(0.13, 0.11, 0.10))
	paste.add_theme_color_override("font_placeholder_color", Color(0.45, 0.42, 0.38))
	var bf: Font = load("res://assets/NotoSansSC-subset.ttf")
	if bf:
		var bfv := FontVariation.new()
		bfv.base_font = bf
		bfv.variation_embolden = 0.55
		paste.add_theme_font_override("font", bfv)
	UI.style_textedit(paste)   # 自动换行（不再横向溢出）+ 平滑滚动 + 纤细滚动条
	UI.tap_lock(paste)
	data_box.add_child(paste)
	# 本地自动整理：输入即解析，实时显示识别统计（不联网、不等点按钮）
	var parse_lbl := UI.label("", 24, p.sub, true)
	data_box.add_child(parse_lbl)
	paste.text_changed.connect(_preview_parse.bind(paste, parse_lbl))
	var pick := UI.button("📂 选择文件导入（docx / txt / md / json）", p.panel2, p.text, 28)
	pick.pressed.connect(func(): _pick_import_file(paste))
	data_box.add_child(pick)
	var import_local := UI.button("本地整理导入（不联网）", p.accent, Color.WHITE, 30)
	import_local.pressed.connect(func():
		if paste.text.strip_edges() == "":
			UI.toast(self, "请先粘贴文本或选择文件")
			return
		UI.double_press(import_local, "再按一次确认导入", func(): _local_import(paste)))
	data_box.add_child(import_local)
	var import_ai := UI.button("交给 AI 整理（需联网 + API Key）", p.panel2, p.text, 28)
	import_ai.pressed.connect(func():
		if paste.text.strip_edges() == "":
			UI.toast(self, "请先粘贴文本或选择文件")
			return
		UI.double_press(import_ai, "再按一次确认", func(): _do_import(paste)))
	data_box.add_child(import_ai)
	var lan_btn := UI.button("📡 局域网 / 蓝牙互传（两台手机互发词库）", p.panel2, p.text, 28)
	lan_btn.pressed.connect(func():
		UI.double_press(lan_btn, "再按一次打开互传", func(): LanSyncDialog.open(self)))
	data_box.add_child(lan_btn)

	await get_tree().process_frame
	if not is_inside_tree():
		return
	# ================= 回滚与重置 =================
	var g_rb := _group("词库回滚与重置", false)
	box.add_child(g_rb)
	var rb_box: VBoxContainer = g_rb.get_meta("body")
	rb_box.add_child(UI.label("每次 AI / 导入修改前自动备份。点按＝回滚，长按＝重命名 / 删除", 24, p.sub, true))
	_rb_batch = false
	_rb_sel.clear()
	_rb_list = VBoxContainer.new()
	_rb_list.add_theme_constant_override("separation", 10)
	rb_box.add_child(_rb_list)
	_rebuild_backup_list()
	var wipe := UI.button("清除所有单词 / 词组（清空词库）", p.danger, Color.WHITE, 28)
	wipe.pressed.connect(func():
		UI.confirm_dialog(self, "清空词库",
			"将移除全部内置和自定义的单词、词组（学习记录保留），方便换成自己的单词表。操作前自动备份，可在上方回滚。",
			func():
				UI.toast(self, DB.wipe_library())
				_reload(), "清空", "取消", true))
	rb_box.add_child(wipe)
	var reset := UI.button("恢复出厂词库（清空自定义修改）", p.danger, Color.WHITE, 28)
	reset.pressed.connect(func():
		UI.confirm_dialog(self, "恢复出厂", "将删除全部自定义词条和删除标记（学习记录保留），确定？",
			func():
				DB.factory_reset_library()
				UI.toast(self, "已恢复出厂词库"), "恢复出厂", "取消", true))
	rb_box.add_child(reset)

	await get_tree().process_frame
	if not is_inside_tree():
		return
	# ================= 关于 =================
	var g_about := _group("关于", true)
	box.add_child(g_about)
	var about: VBoxContainer = g_about.get_meta("body")
	about.add_child(UI.label("英眼书  v" + DB.VERSION, 30, p.text))
	about.add_child(UI.label("单词 %d · 词组 %d · 本地存储，离线可用" % [DB.words.size(), DB.phrases.size()], 24, p.sub))
	about.add_child(UI.label("数据位置：" + OS.get_user_data_dir(), 22, p.sub, true))
	# 应用内更新日志：点开独立弹窗查看（折叠组内嵌滚动在部分机型上空白/无法滑动，改 sheet 一了百了）
	var g_log := _group("更新日志", false)
	box.add_child(g_log)
	var log_box: VBoxContainer = g_log.get_meta("body")
	var log_btn := UI.button("📜 查看更新日志（当前 v%s）" % DB.VERSION, p.panel2, p.text, 28)
	log_btn.pressed.connect(func():
		var sh := UI.sheet(self, "更新日志", "关闭", "")
		var lb := UI.label(DB.changelog_text(), 26, p.text, true)
		lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		(sh["body"] as VBoxContainer).add_child(lb))
	log_box.add_child(log_btn)

## 输入防抖 0.4s 后自动解析，实时预览识别结果（本地整理不联网，相当于内置自动化脚本）
var _parse_gen := 0
var wp_status_lbl: Label

func _preview_parse(paste: TextEdit, lbl: Label) -> void:
	_parse_gen += 1
	var gen := _parse_gen
	var text: String = paste.text
	await get_tree().create_timer(0.4).timeout
	if gen != _parse_gen or not is_instance_valid(lbl):
		return
	var n := text.strip_edges().length()
	if n == 0:
		lbl.text = ""
		return
	if n > 40000:
		lbl.text = "已输入 %d 字：内容较长，点「本地整理导入」开始解析" % n
		return
	if DB.is_groups_md(text):
		var groups := DB.parse_groups_md(text)
		var gw := 0
		var gp := 0
		for g in groups:
			gw += g["res"]["words"].size()
			gp += g["res"]["phrases"].size()
		lbl.text = "📑 分组/互传格式：%d 个分组（单词 %d · 词组 %d）→ 将按各自组名入库" % [groups.size(), gw, gp]
		return
	var res := DB.parse_import_text(text)
	var group := DB.next_day_name()
	if not res["words"].is_empty():
		group = String(res["words"][0].get("day", group))
	elif not res["phrases"].is_empty():
		group = String(res["phrases"][0].get("sec", group))
	if res["words"].is_empty() and res["phrases"].is_empty() and res["dup"].is_empty() and res["unknown"].is_empty():
		lbl.text = "已输入 %d 字，暂未识别到词条（格式：每行「单词 中文释义」或「词组 中文释义」）" % n
		return
	lbl.text = "⚙ 自动识别：单词 %d · 词组 %d · 重复跳过 %d · 待核对 %d 行 → 将放入新分组「%s」" % [
		res["words"].size(), res["phrases"].size(), res["dup"].size(), res["unknown"].size(), group]

## AI 长期记忆查看 / 逐条删除弹窗
func _show_memory(count_btn: Button) -> void:
	UI.memory_dialog(self, count_btn)   # 共用组件（AI 页也有入口）

## 可折叠分组：返回外层容器，内容容器存在 meta["body"]
func _group(title: String, open := true) -> VBoxContainer:
	var p := UI.palette()
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	var head := UI.button(("▾  " if open else "▸  ") + title, Color.TRANSPARENT, p.text, 32)
	head.alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.custom_minimum_size = Vector2(0, 88)
	outer.add_child(head)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.visible = open
	outer.add_child(body)
	outer.set_meta("body", body)
	head.pressed.connect(func():
		body.visible = not body.visible
		head.text = ("▾  " if body.visible else "▸  ") + title)
	return outer

func _pick_wallpaper() -> void:
	UI.file_dialog(self, "选择壁纸图片（jpg / png）",
		DisplayServer.FILE_DIALOG_MODE_OPEN_FILE,
		["*.jpg,*.jpeg;图片;image/jpeg", "*.png;图片;image/png"],
		_on_wallpaper_picked)

## 导出文件后：安卓上优先弹系统分享面板（可直接发微信/QQ），否则走系统“另存为”
func _export_and_maybe_share(src_path: String, default_name: String, filter: String, mime: String) -> void:
	if src_path == "":
		UI.toast(self, "导出失败")
		return
	if Share.file(src_path, mime, "分享备份"):
		UI.toast(self, "已导出，可在分享面板里发给朋友")
		return
	_export_with_save_as(src_path, default_name, filter)

## 导出文件后弹系统“另存为”，用户自选保存位置/分享
func _export_with_save_as(src_path: String, default_name: String, filter: String) -> void:
	if src_path == "":
		UI.toast(self, "导出失败")
		return
	UI.file_dialog(self, "保存备份文件",
		DisplayServer.FILE_DIALOG_MODE_SAVE_FILE, [filter],
		func(ok: bool, paths: PackedStringArray, _i: int):
			if not ok or paths.is_empty():
				return
			var data := FileAccess.get_file_as_bytes(src_path)
			var f := FileAccess.open(paths[0], FileAccess.WRITE)
			if f == null:
				UI.toast(self, "保存失败，请重试")
				return
			f.store_buffer(data)
			f.close()
			UI.toast(self, "已保存"),
		default_name, func(): UI.toast(self, "已导出：" + src_path))

## 文件导入：docx/txt/md 读取到输入框（docx 自动解包为纯文本）
func _pick_import_file(paste: TextEdit) -> void:
	UI.file_dialog(self, "选择要导入的文件",
		DisplayServer.FILE_DIALOG_MODE_OPEN_FILE,
		["*.txt,*.md,*.csv;文本;text/plain", "*.json;JSON;application/json",
			"*.docx;Word 文档;application/vnd.openxmlformats-officedocument.wordprocessingml.document"],
		func(ok: bool, paths: PackedStringArray, _i: int):
			if ok and not paths.is_empty():
				var t := DB.extract_text_file(paths[0])
				if t.strip_edges() == "":
					UI.toast(self, "文件读取失败或内容为空")
				else:
					paste.text = t   # 内容显示在输入框，可先检查/修改再导入
					var stripped := t.strip_edges()
					if stripped.begins_with("{") or stripped.begins_with("["):
						UI.toast(self, "已读取 JSON 备份（显示在输入框），点「本地整理导入」恢复")
					elif DB.is_groups_md(stripped):
						var groups := DB.parse_groups_md(t)
						UI.toast(self, "已读取分组/互传文件：识别 %d 个分组，点「本地整理导入」按组入库" % groups.size())
					else:
						var res := DB.parse_import_text(t)
						UI.toast(self, "已显示在输入框：识别 %d 词 %d 词组，重复 %d 条" % [
							res["words"].size(), res["phrases"].size(), res["dup"].size()]))

## 本地整理导入（不联网）：程序自动解析文本 → 查重 → 逐条确认 → 入库
func _local_import(paste: TextEdit) -> void:
	var t := paste.text.strip_edges()
	if t == "":
		UI.toast(self, "内容为空")
		return
	if t.begins_with("{") or t.begins_with("["):
		var err := DB.import_backup(paste.text)
		UI.toast(self, "导入完成" if err == "" else err)
		if err == "":
			paste.text = ""
		return
	# 「# 组名」分组格式（互传文件 / 手整分组词库）：按组名直接入库
	if DB.is_groups_md(t):
		_group_import_flow(paste)
		return
	var res := DB.parse_import_text(paste.text)
	var total: int = res["words"].size() + res["phrases"].size()
	if total == 0:
		if res["dup"].size() > 0 and res["unknown"].is_empty():
			UI.toast(self, "识别到 %d 条，但全部已在词库中" % res["dup"].size())
		else:
			UI.toast(self, "没有识别出词条，格式太乱可点「交给 AI 整理」")
		return
	# 待核对行占比过高：这段文字多半不是单词表（录音稿/文章段落），
	# 先讲清可识别格式，避免几百行待核对直接卡死预览（识别率 1/5 且 ≥20 行垃圾时拦截）
	if res["unknown"].size() >= 20 and total * 5 <= res["unknown"].size():
		_show_format_hint(res, paste)
		return
	_show_local_preview(res, paste)

## 分组 Markdown 导入（互传文件 / 手整「# 组名」词库）：列出分组清单，二选一并直接入库
func _group_import_flow(paste: TextEdit) -> void:
	var p := UI.palette()
	var groups := DB.parse_groups_md(paste.text)
	if groups.is_empty():
		UI.toast(self, "没有识别到词条")
		return
	var w := 0
	var ph := 0
	var names := PackedStringArray()
	for g in groups:
		w += g["res"]["words"].size()
		ph += g["res"]["phrases"].size()
		names.append(String(g["name"]))
	if w + ph == 0:
		UI.toast(self, "识别到 %d 个分组，但里面没有词条" % groups.size())
		return
	var sh := UI.sheet(self, "识别到 %d 个分组（共 %d 词 · %d 词组）" % [groups.size(), w, ph], "", "取消")
	var body: VBoxContainer = sh["body"]
	var show := names.slice(0, 8)
	var list_txt := "、".join(show)
	if names.size() > 8:
		list_txt += " 等 %d 组" % names.size()
	body.add_child(UI.label("分组：" + list_txt, 26, p.sub, true))
	var merge_btn := UI.button("➕ 扩展词汇（保留我现有的，只加没有的）", p.accent, Color.WHITE, 28)
	merge_btn.custom_minimum_size = Vector2(0, 80)
	merge_btn.pressed.connect(func():
		UI.dismiss_dialog(sh["overlay"])
		_apply_group_import(paste, false))
	body.add_child(merge_btn)
	var over_btn := UI.button("🔁 覆盖原词汇（同名组的自定义词条先清空再写入）", p.panel2, p.danger, 28)
	over_btn.custom_minimum_size = Vector2(0, 80)
	over_btn.pressed.connect(func():
		UI.dismiss_dialog(sh["overlay"])
		UI.confirm_dialog(self, "覆盖原词汇",
			"同名分组里你自己加的词条会被替换，操作前有自动备份可回滚，确定吗？",
			func(): _apply_group_import(paste, true),
			"覆盖", "取消", true))
	body.add_child(over_btn)

func _apply_group_import(paste: TextEdit, overwrite: bool) -> void:
	var res: Dictionary = DB.import_groups_md(paste.text, overwrite)
	if res["err"] != "":
		UI.toast(self, "导入失败：" + res["err"])
		return
	UI.toast(self, "✅ 入库 %d 个分组：单词 +%d、词组 +%d（%s）" % [
		res["groups"], res["added_w"], res["added_p"],
		"覆盖原词汇" if overwrite else "扩展词汇"])
	paste.text = ""

## 识别率过低时的拦截提示：讲清可识别格式，留「仍要预览」出口
func _show_format_hint(res: Dictionary, paste: TextEdit) -> void:
	var p := UI.palette()
	var total: int = res["words"].size() + res["phrases"].size()
	var sh := UI.sheet(self, "这段文字看起来不像单词表", "仍要预览", "返回修改", func():
		_show_local_preview(res, paste))
	var body: VBoxContainer = sh["body"]
	body.add_child(UI.label("共 %d 行，只识别出 %d 条词条，其余 %d 行无法对应「英文 + 中文释义」。直接预览会列出几百行待核对，容易卡顿。" % [
		total + res["unknown"].size() + res["dup"].size(), total, res["unknown"].size()], 26, p.danger, true))
	body.add_child(UI.label("能识别的写法（每行一条，先英文后中文）：", 26, p.text, true))
	body.add_child(UI.label("abandon 放弃\nabandon v. 放弃\nabandon /əˈbændən/ n. 放弃\ntake off 起飞；脱下", 26, p.accent, true))
	body.add_child(UI.label("建议：把内容整理成上面的格式再点「本地整理导入」；课堂录音稿、文章段落这类内容请改用「交给 AI 整理」（联网）。" , 24, p.sub, true))

## 本地整理预览：逐条勾选确认后才写入（apply_ai_library_edit 自带备份，可回滚）
## 行分批渲染（每批 40 条）：几百条候选一次性建行会卡死低配机
func _show_local_preview(res: Dictionary, paste: TextEdit) -> void:
	var p := UI.palette()
	var checks: Array = []   # [勾选胶囊行, kind, payload]
	var sh := UI.sheet(self, "本地整理预览（勾选后确认写入，写入前自动备份）", "写入选中项", "取消", func():
		var ops := {"add_words": [], "add_phrases": [], "remove_words": [], "remove_phrases": []}
		for item in checks:
			if item[0].button_pressed and item[1] != "unknown":
				ops[item[1]].append(item[2])
		var total: int = ops["add_words"].size() + ops["add_phrases"].size()
		if total == 0:
			UI.toast(self, "未选择任何词条")
			return
		var log := DB.apply_ai_library_edit(ops)
		UI.toast(self, String(log).split("\n")[0] + "（可在下方回滚）")
		paste.text = ""
		_reload())
	var list: VBoxContainer = sh["body"]
	var tgt: String = res["words"][0].get("day", "") if not res["words"].is_empty() else (res["phrases"][0].get("sec", "") if not res["phrases"].is_empty() else "")
	var summary := "将新增：单词 %d 条 · 词组 %d 条 → 分组「%s」；重复跳过 %d 条；待核对 %d 行" % [
		res["words"].size(), res["phrases"].size(), tgt,
		res["dup"].size(), res["unknown"].size()]
	list.add_child(UI.label(summary, 26, p.sub, true))
	# 先提示词库现有各 Day 的单词数量，再进行逐条整理
	var dist: Array = []
	for g in DB.word_groups:
		dist.append("%s %d" % [g, DB.words_in_group(g).size()])
	list.add_child(UI.label("词库现有分组：" + " · ".join(dist) + "；本次新词将进入「%s」" % tgt, 24, p.accent, true))
	# 行规格统一收集：[文字, kind, payload, 颜色, 默认勾选]
	var specs: Array = []
	for w in res["words"]:
		specs.append(["＋单词  %s %s  %s" % [w.get("w", "?"), w.get("p", ""), w.get("m", "")], "add_words", w, p.text, true])
	for ph in res["phrases"]:
		specs.append(["＋词组  %s = %s" % [ph.get("en", "?"), ph.get("cn", "")], "add_phrases", ph, p.text, true])
	# 无法识别/无释义的行：默认不勾选，醒目提示；太多时只展示前 30 行（反正不导入）
	var unknown: Array = res["unknown"]
	var hidden := 0
	if unknown.size() > 30:
		hidden = unknown.size() - 30
		unknown = unknown.slice(0, 30)
	for u in unknown:
		specs.append(["？待核对（不导入）  %s" % u, "unknown", u, p.danger, false])
	if hidden > 0:
		list.add_child(UI.label("另有 %d 行待核对已从略（待核对行不会导入）" % hidden, 24, p.sub, true))
	var rows_box := VBoxContainer.new()
	rows_box.add_theme_constant_override("separation", 12)
	list.add_child(rows_box)
	var page := 40
	var shown := {"n": 0}
	var more := UI.button("", p.panel2, p.text, 26)
	var render_chunk: Callable
	render_chunk = func():
		var upto: int = mini(shown.n + page, specs.size())
		for i in range(shown.n, upto):
			var s: Array = specs[i]
			var cb := UI.check_row(s[0], s[4], s[3])
			rows_box.add_child(cb)
			checks.append([cb, s[1], s[2]])
		shown.n = upto
		more.visible = shown.n < specs.size()
		more.text = "显示更多（剩余 %d 条）" % (specs.size() - shown.n)
	render_chunk.call()
	if specs.size() > page:
		list.add_child(more)
		more.pressed.connect(render_chunk)
	if not res["dup"].is_empty():
		list.add_child(UI.label("已存在自动跳过：" + "、".join(res["dup"].slice(0, 30)) + (" ……" if res["dup"].size() > 30 else ""), 24, p.sub, true))

## 交给 AI 整理：JSON 直接导；普通文本跳到 AI 页并预填整理指令
func _do_import(paste: TextEdit) -> void:
	var t := paste.text.strip_edges()
	if t == "":
		UI.toast(self, "内容为空")
		return
	if t.begins_with("{") or t.begins_with("["):
		var err := DB.import_backup(paste.text)
		if err == "":
			UI.toast(self, "导入完成")
			paste.text = ""
		else:
			UI.toast(self, err)
		return
	if String(DB.settings.get("api_key", "")) == "":
		UI.toast(self, "请先在「AI API」里填写 API Key，AI 才能帮你整理文本")
		return
	var main = get_meta("main")
	if main != null:
		main.switch_tab(3)
		if main.current_view != null and main.current_view.has_method("prepare_import"):
			main.current_view.prepare_import(paste.text)
		paste.text = ""

func _on_wallpaper_picked(ok: bool, paths: PackedStringArray, _i: int) -> void:
	if not ok or paths.is_empty():
		return
	# 安卓返回的是 content:// 地址，先读字节再按格式解码，比 Image.load 直接读路径可靠
	var data := FileAccess.get_file_as_bytes(paths[0])
	if data.is_empty():
		UI.toast(self, "图片读取失败，请换一张试试")
		return
	var img := Image.new()
	var err := ERR_UNAVAILABLE
	if data.size() >= 8 and data[0] == 0x89 and data[1] == 0x50:   # PNG 魔数
		err = img.load_png_from_buffer(data)
	elif data.size() >= 3 and data[0] == 0xFF and data[1] == 0xD8:  # JPEG 魔数
		err = img.load_jpg_from_buffer(data)
	if err != OK:
		UI.toast(self, "只支持 jpg / png 格式的图片")
		return
	# 压缩到合理尺寸，避免大图占内存
	var max_side := 1920
	if img.get_width() > max_side or img.get_height() > max_side:
		var r := float(max_side) / float(maxi(img.get_width(), img.get_height()))
		img.resize(int(img.get_width() * r), int(img.get_height() * r), Image.INTERPOLATE_BILINEAR)
	if img.save_png("user://wallpaper.png") != OK:
		UI.toast(self, "壁纸保存失败")
		return
	DB.settings["wallpaper"] = "user://wallpaper.png"
	DB.save_settings()
	UI.toast(self, "壁纸已更新")
	_reload()

func _input_row(label_text: String, value: String, secret: bool, on_change: Callable) -> Control:
	var p := UI.palette()
	var card := UI.panel()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	card.add_child(vb)
	vb.add_child(UI.label(label_text, 26, p.sub))
	var le := LineEdit.new()
	le.text = value
	le.secret = secret
	le.custom_minimum_size = Vector2(0, 72)
	le.add_theme_font_size_override("font_size", 30)
	le.add_theme_stylebox_override("normal", UI.style_box(p.panel2, 12))
	le.add_theme_color_override("font_color", p.text)
	le.text_changed.connect(func(t: String): on_change.call(t))
	UI.tap_lock(le)
	vb.add_child(le)
	card.set_meta("le", le)   # 预设按钮直接改输入框用
	return card

# ---------------- 备份列表：点按回滚 / 长按菜单 / 批量管理 ----------------
## 重建备份列表（普通模式=回滚行；批量模式=勾选行+删除按钮）
func _rebuild_backup_list() -> void:
	if _rb_list == null or not is_instance_valid(_rb_list):
		return
	for c in _rb_list.get_children():
		c.queue_free()
	var p := UI.palette()
	var backups := DB.list_backups()
	if backups.is_empty():
		_rb_batch = false
		_rb_sel.clear()
		_rb_list.add_child(UI.label("暂无备份", 26, p.sub))
		return
	var toggle := UI.button("✓ 完成" if _rb_batch else "☑ 批量管理备份", p.panel2, p.text, 26)
	toggle.pressed.connect(func():
		_rb_batch = not _rb_batch
		_rb_sel.clear()
		_rebuild_backup_list())
	_rb_list.add_child(toggle)
	for fname in backups:
		if _rb_batch:
			var row := UI.check_row(DB.get_backup_label(fname), _rb_sel.get(fname, false), p.text, 26)
			row.toggled.connect(func(o: bool): _rb_sel[fname] = o)
			_rb_list.add_child(row)
		else:
			_rb_list.add_child(_make_backup_row(fname))
	if _rb_batch:
		var del := UI.button("🗑 删除选中的备份", p.danger, Color.WHITE, 28)
		del.pressed.connect(func():
			var picked := PackedStringArray()
			for f in backups:
				if _rb_sel.get(f, false):
					picked.append(f)
			if picked.is_empty():
				UI.toast(self, "先勾选要删除的备份")
				return
			UI.confirm_dialog(self, "删除备份",
				"将删除 %d 份备份，删除后不能再回滚到它们，确定吗？" % picked.size(),
				func():
					var n := DB.delete_backups(picked)
					UI.toast(self, "已删除 %d 份备份" % n)
					_rb_sel.clear()
					_rebuild_backup_list(),
				"删除", "取消", true))
		_rb_list.add_child(del)

## 单条备份行：不连 pressed，全部走 gui_input——短按回滚（带确认），长按 550ms 出菜单，拖动 30px 取消（与主页卡片同一套触控逻辑）
func _make_backup_row(fname: String) -> Button:
	var p := UI.palette()
	var b := UI.button("回滚到 " + DB.get_backup_label(fname), p.panel2, p.text, 26)
	var st := {"msec": 0, "pos": Vector2.ZERO}   # 字典是引用类型，规避 lambda 按值快照
	b.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventScreenTouch or ev is InputEventMouseButton:
			if ev.pressed:
				st["msec"] = Time.get_ticks_msec()
				st["pos"] = ev.position
			elif st["msec"] > 0:
				var held: int = Time.get_ticks_msec() - st["msec"]
				st["msec"] = 0
				if held >= 550:
					_backup_menu(fname)
				else:
					UI.confirm_dialog(self, "回滚词库",
						"确定要回滚到「%s」吗？当前自定义词库会被覆盖。" % DB.get_backup_label(fname),
						func():
							UI.toast(self, DB.rollback_backup(fname))
							_reload(),
						"回滚", "取消", true)
		elif (ev is InputEventScreenDrag or ev is InputEventMouseMotion) and st["msec"] > 0:
			if ev.position.distance_to(st["pos"]) > 30.0:
				st["msec"] = 0)
	return b

## 备份长按菜单：重命名 / 回滚 / 删除
func _backup_menu(fname: String) -> void:
	UI.vibrate(40)
	var p := UI.palette()
	var lab := DB.get_backup_label(fname)
	var sh: Dictionary = UI.sheet(self, "备份「%s」" % lab, "", "关闭")
	var body: VBoxContainer = sh["body"]
	var rn := UI.button("✏️ 重命名备份", p.panel2, p.text, 29)
	rn.custom_minimum_size = Vector2(0, 80)
	rn.pressed.connect(func():
		UI.dismiss_dialog(sh["overlay"])
		_backup_rename_dialog(fname))
	body.add_child(rn)
	var rb := UI.button("⏪ 回滚到此备份", p.panel2, p.text, 29)
	rb.custom_minimum_size = Vector2(0, 80)
	rb.pressed.connect(func():
		UI.dismiss_dialog(sh["overlay"])
		UI.confirm_dialog(self, "回滚词库",
			"确定要回滚到「%s」吗？当前自定义词库会被覆盖。" % lab,
			func():
				UI.toast(self, DB.rollback_backup(fname))
				_reload(),
			"回滚", "取消", true))
	body.add_child(rb)
	var del := UI.button("🗑 删除备份", p.panel2, p.danger, 29)
	del.custom_minimum_size = Vector2(0, 80)
	del.pressed.connect(func():
		UI.dismiss_dialog(sh["overlay"])
		UI.confirm_dialog(self, "删除备份",
			"将删除备份「%s」，删除后不能再回滚到它，确定吗？" % lab,
			func():
				var err := DB.delete_backup(fname)
				UI.toast(self, err if err != "" else "已删除备份")
				_rebuild_backup_list(),
			"删除", "取消", true))
	body.add_child(del)

## 备份重命名弹窗（清空输入 = 恢复默认时间名）
func _backup_rename_dialog(fname: String) -> void:
	var p := UI.palette()
	var le := LineEdit.new()
	le.text = DB.get_backup_label(fname)
	le.custom_minimum_size = Vector2(0, 76)
	le.add_theme_font_size_override("font_size", 30)
	var sh := UI.sheet(self, "重命名备份", "保存", "取消", func():
		var err := DB.rename_backup(fname, le.text)
		if err != "":
			UI.toast(self, err)
		else:
			UI.toast(self, "已重命名为「%s」" % le.text.strip_edges())
		_rebuild_backup_list())
	sh["body"].add_child(UI.label("留空则恢复默认的时间名称", 24, p.sub))
	sh["body"].add_child(le)

func _reload() -> void:
	get_tree().reload_current_scene()
