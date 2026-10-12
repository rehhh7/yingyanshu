class_name LanSyncDialog
extends Control
## 局域网互传弹窗：同一个 WiFi 下两台设备互发词库备份
## 用法：LanSyncDialog.open(父节点)

var _sync: LanSync
var _status_box: VBoxContainer
var _p: Dictionary

static func open(parent: Node) -> Control:
	var d: LanSyncDialog = LanSyncDialog.new()
	d._build()
	parent.add_child(d)
	return d

func _build() -> void:
	_p = UI.palette()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_to_group("ui_dialog")   # 返回键由 main 统一关闭
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed:
			_close())
	add_child(dim)
	var bottom := VBoxContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom)
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var dark: bool = DB.settings.get("theme_dark", true)
	var sb := UI.style_box(Color("26292F") if dark else Color("FFFFFF"), 28)
	sb.corner_radius_bottom_left = 0
	sb.corner_radius_bottom_right = 0
	sb.content_margin_left = 32
	sb.content_margin_right = 32
	sb.content_margin_top = 28
	sb.content_margin_bottom = 36
	card.add_theme_stylebox_override("panel", sb)
	bottom.add_child(card)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 18)
	card.add_child(cv)
	var title := UI.label("📡 局域网互传", 34, _p.text)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(title)
	cv.add_child(UI.label("两台手机连同一个 WiFi，都打开这个页面：一台「发送」，另一台「接收」。传的是自定义词库 + 学习记录，全程不联网。", 24, _p.sub, true))
	var send_btn := UI.button("📤 发送本机词库", _p.accent, Color.WHITE, 30)
	send_btn.custom_minimum_size = Vector2(0, 88)
	send_btn.pressed.connect(_on_send_pressed)
	cv.add_child(send_btn)
	var recv_btn := UI.button("📥 接收对方词库", _p.panel2, _p.text, 30)
	recv_btn.custom_minimum_size = Vector2(0, 88)
	recv_btn.pressed.connect(_on_recv_pressed)
	cv.add_child(recv_btn)
	_status_box = VBoxContainer.new()
	_status_box.add_theme_constant_override("separation", 12)
	cv.add_child(_status_box)
	_sync = LanSync.new()
	add_child(_sync)
	_sync.peer_found.connect(_on_peer_found)
	_sync.receive_done.connect(_on_receive_done)
	_sync.send_done.connect(func(): _set_status("✅ 已发送完成，可以关闭本页了"))
	_sync.failed.connect(func(msg: String): _set_status("⚠️ " + msg))

func _clear_status() -> void:
	for c in _status_box.get_children():
		c.queue_free()

func _set_status(text: String) -> void:
	_clear_status()
	_status_box.add_child(UI.label(text, 26, _p.sub, true))

func _on_send_pressed() -> void:
	var json_text := JSON.stringify(DB.build_backup_payload())
	var err := _sync.start_sender(json_text)
	if err != "":
		_set_status("⚠️ " + err)
		return
	var wc: int = DB.build_backup_payload()["custom_words"].size()
	var pc: int = DB.build_backup_payload()["custom_phrases"].size()
	_set_status("📤 正在广播：%s\n内容：自定义单词 %d 个、词组 %d 条、学习记录一份\n请保持本页打开，等对方点「接收」。" % [_sync.device_name(), wc, pc])

func _on_recv_pressed() -> void:
	var err := _sync.start_receiver()
	if err != "":
		_set_status("⚠️ " + err)
		return
	_set_status("🔍 正在搜索同一 WiFi 下的发送设备……\n（找不到？确认两台手机连的是同一个 WiFi，且对方已点「发送」）")

func _on_peer_found(dev_name: String, ip: String) -> void:
	var btn := UI.button("📱 %s（%s）→ 点我接收" % [dev_name, ip], _p.panel2, _p.text, 28)
	btn.custom_minimum_size = Vector2(0, 80)
	btn.pressed.connect(func():
		_set_status("🔗 正在连接 %s ……" % dev_name)
		_sync.connect_and_receive(ip))
	_status_box.add_child(btn)

func _on_receive_done(json_text: String) -> void:
	var d = JSON.parse_string(json_text)
	if not (d is Dictionary) or d.get("type") != "cet4_backup":
		_set_status("⚠️ 收到的数据不是英眼书备份")
		return
	var wc: int = (d.get("custom_words", []) as Array).size()
	var pc: int = (d.get("custom_phrases", []) as Array).size()
	_set_status("📥 收到一份备份")
	UI.confirm_dialog(self, "导入收到的词库？",
		"单词 %d 个、词组 %d 条、学习记录一份。\n导入会覆盖本机的对应数据（导入前自动备份，可在「设置 → 词库回滚」还原）。" % [wc, pc],
		func():
			var e := DB.import_backup(json_text)
			if e == "":
				UI.toast(self, "✅ 导入完成")
				_close()
			else:
				UI.toast(self, "导入失败：" + e),
		"导入", "取消")

func _close() -> void:
	_sync.stop_all()
	queue_free()
