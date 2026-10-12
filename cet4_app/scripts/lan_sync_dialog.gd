class_name LanSyncDialog
extends Control
## 手机互传弹窗（局域网 + 蓝牙，同一套交互）：
## 两台手机都打开本页 → 点「搜索手机」→ 列表里点对方 → 选「扩展词汇 / 覆盖原词汇」并确认
## → 对方弹「XX 想要你的词库」确认 → 传输 → 按所选方式导入
## 用法：LanSyncDialog.open(父节点)

var _p: Dictionary
var _body: VBoxContainer
var _lan: LanSync
var _bt: Object = null              # YysKit 单例（无插件时为 null）
var _transport := "lan"             # lan / bt
var _mode_choice := "merge"         # merge（扩展词汇）/ overwrite（覆盖原词汇）
var _target_name := ""
var _target_addr := ""
var _payload_text := ""             # 实际发出的内容（Markdown 或 JSON）
var _preset_payload := ""           # 分组分享时由调用方传入
var _preset_label := ""
var _peers := {}                    # addr -> name（去重）

## 打开互传弹窗。payload 非空时发送该内容（分组分享的 Markdown），否则发送整库
static func open(parent: Node, payload := "", label := "") -> Control:
	var d: LanSyncDialog = LanSyncDialog.new()
	d._preset_payload = payload
	d._preset_label = label
	d._build()
	# 必须挂到窗口根节点：挂进 VBox 等容器会被当成普通子项排版，弹窗被挤到列表底部
	var host: Node = parent.get_tree().root if parent.is_inside_tree() else null
	if host == null:
		host = (Engine.get_main_loop() as SceneTree).root
	host.add_child(d)
	return d

func _build() -> void:
	_p = UI.palette()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_to_group("ui_dialog")   # 返回键由 main 统一关闭
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var tree := Engine.get_main_loop() as SceneTree
	var vw := 720.0
	if tree != null:
		vw = tree.root.get_visible_rect().size.x
	card.custom_minimum_size = Vector2(minf(660.0, vw - 56.0), 0)
	var dark: bool = DB.settings.get("theme_dark", true)
	var sb := UI.style_box(Color("26292F") if dark else Color("FFFFFF"), 30)
	sb.content_margin_left = 32
	sb.content_margin_right = 32
	sb.content_margin_top = 28
	sb.content_margin_bottom = 30
	card.add_theme_stylebox_override("panel", sb)
	center.add_child(card)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 16)
	card.add_child(cv)
	var title := UI.label("📡 手机互传", 34, _p.text)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(title)
	cv.add_child(UI.label("两台手机都打开本页面：一台搜到另一台后点它，对方同意即可传输。传的是自定义词库 + 学习记录。", 24, _p.sub, true))
	# 传输方式胶囊
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 14)
	cv.add_child(tabs)
	var lan_tab := UI.button("📶 局域网", _p.accent, Color.WHITE, 28)
	lan_tab.custom_minimum_size = Vector2(230, 76)
	var bt_tab := UI.button("🅱️ 蓝牙", _p.panel2, _p.text, 28)
	bt_tab.custom_minimum_size = Vector2(230, 76)
	tabs.add_child(lan_tab)
	tabs.add_child(bt_tab)
	lan_tab.pressed.connect(func(): _switch_transport("lan", lan_tab, bt_tab))
	bt_tab.pressed.connect(func(): _switch_transport("bt", lan_tab, bt_tab))
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 12)
	cv.add_child(_body)
	var close_btn := UI.button("关闭", _p.panel2, _p.text, 26)
	close_btn.custom_minimum_size = Vector2(0, 68)
	close_btn.pressed.connect(_close)
	cv.add_child(close_btn)
	# 引擎
	_lan = LanSync.new()
	add_child(_lan)
	_lan.peer_found.connect(func(nm: String, ip: String): _add_peer(nm, ip))
	_lan.incoming_request.connect(_on_incoming_request)
	_lan.receive_done.connect(_on_receive_done)
	_lan.rejected.connect(func(): _status("⚠️ 对方拒绝了互传"))
	_lan.failed.connect(func(msg: String): _status("⚠️ " + msg))
	_lan.send_done.connect(func(): _status("✅ 已发送完成，可以关闭了"))
	if Engine.has_singleton("YysKit"):
		_bt = Engine.get_singleton("YysKit")
		_bt.connect("bt_device_found", Callable(self, "_add_peer"))
		_bt.connect("bt_incoming_request", Callable(self, "_on_bt_incoming"))
		_bt.connect("bt_received", Callable(self, "_on_receive_done"))
		_bt.connect("bt_done", Callable(self, "_on_bt_done"))
	# 载荷：分组分享用调用方给的 Markdown；整库互传用自定义词库的固定 Markdown 格式
	if _preset_payload != "":
		_payload_text = _preset_payload
	else:
		_payload_text = DB.build_transfer_md()
	_show_idle()

func _switch_transport(t: String, lan_tab: Button, bt_tab: Button) -> void:
	_transport = t
	lan_tab.add_theme_color_override("font_color", Color.WHITE if t == "lan" else _p.text)
	bt_tab.add_theme_color_override("font_color", Color.WHITE if t == "bt" else _p.text)
	# 背景色通过重新设置按钮样式代价高，用字色区分即可
	_show_idle()

func _clear_body() -> void:
	for c in _body.get_children():
		c.queue_free()
	_peers.clear()

func _status(text: String) -> void:
	var keep: Array = []
	for c in _body.get_children():
		if c.get_meta("keep", false):
			keep.append(c)
		else:
			c.queue_free()
	_body.add_child(UI.label(text, 26, _p.sub, true))

func _show_idle() -> void:
	_clear_body()
	if _transport == "bt" and _bt == null:
		_body.add_child(UI.label("⚠️ 本机没有蓝牙插件（非安卓构建），请改用局域网", 26, _p.danger, true))
		return
	if _transport == "bt" and _bt.call("bt_state") == 0:
		_body.add_child(UI.label("⚠️ 这台设备不支持蓝牙，请改用局域网", 26, _p.danger, true))
		return
	var hint := "局域网：两台手机连同一个 WiFi。" if _transport == "lan" else "蓝牙：两台手机都开着蓝牙；列表里可能出现耳机等其它设备，点对方手机的名字。"
	_body.add_child(UI.label(hint, 24, _p.sub, true))
	var go := UI.button("🔍 搜索手机", _p.accent, Color.WHITE, 30)
	go.custom_minimum_size = Vector2(0, 84)
	go.pressed.connect(_start_search)
	_body.add_child(go)

func _start_search() -> void:
	_clear_body()
	if _transport == "lan":
		var err := _lan.start_both(_payload_text)
		if err != "":
			_status("⚠️ " + err)
			return
	else:
		if not _bt.call("bt_ensure_perms"):
			_status("⚠️ 请先允许蓝牙权限，然后再点一次「搜索手机」")
			return
		if _bt.call("bt_state") == 1:
			_bt.call("bt_enable")
			_status("⚠️ 已在系统弹窗里打开蓝牙后，再点一次「搜索手机」")
			return
		_bt.call("bt_host_start", _payload_text)
		_bt.call("bt_discover")
	var what := "分组「%s」" % _preset_label if _preset_label != "" else "自定义词库"
	var lbl := UI.label("🔍 正在广播本机（%s）并搜索对方……\n（对方也要打开本页并点「搜索手机」）" % what, 26, _p.sub, true)
	lbl.set_meta("keep", true)
	_body.add_child(lbl)

func _add_peer(nm: String, addr: String) -> void:
	if _peers.has(addr):
		return
	_peers[addr] = nm
	var btn := UI.button("📱 %s → 点我选择互传方式" % nm, _p.panel2, _p.text, 27)
	btn.custom_minimum_size = Vector2(0, 78)
	btn.pressed.connect(func(): _show_mode_choose(nm, addr))
	_body.add_child(btn)

## 第一步：选「扩展词汇 / 覆盖原词汇」→ 确认后向对方发请求
func _show_mode_choose(nm: String, addr: String) -> void:
	_target_name = nm
	_target_addr = addr
	_clear_body()
	_body.add_child(UI.label("从「%s」接收词库，接收后怎么处理？" % nm, 27, _p.text, true))
	var merge_btn := UI.button("➕ 扩展词汇（保留我的，加上对方新增的）", _p.panel2, _p.text, 27)
	merge_btn.custom_minimum_size = Vector2(0, 78)
	var over_btn := UI.button("🔁 覆盖原词汇（我的自定义词库换成对方的）", _p.panel2, _p.text, 27)
	over_btn.custom_minimum_size = Vector2(0, 78)
	var confirm := UI.button("✅ 确认，请求互传", _p.accent, Color.WHITE, 29)
	confirm.custom_minimum_size = Vector2(0, 82)
	var sel := UI.label("当前：扩展词汇", 25, _p.accent)
	merge_btn.pressed.connect(func():
		_mode_choice = "merge"
		sel.text = "当前：扩展词汇（保留我的，加上对方新增的）")
	over_btn.pressed.connect(func():
		_mode_choice = "overwrite"
		sel.text = "当前：覆盖原词汇（我的自定义词库换成对方的）")
	confirm.pressed.connect(func():
		_clear_body()
		_body.add_child(UI.label("⏳ 正在请求「%s」，等对方确认……" % _target_name, 26, _p.sub, true))
		if _transport == "lan":
			_lan.request_to(_target_addr)
		else:
			_bt.call("bt_connect", _target_addr, _lan.device_name()))
	_body.add_child(merge_btn)
	_body.add_child(over_btn)
	_body.add_child(sel)
	_body.add_child(confirm)

## 第二步（对方）：收到互传请求 → 拒绝 / 发送（拒绝也要明确回执，对方才能收到结果）
func _on_incoming_request(nm: String, ip: String) -> void:
	UI.vibrate(60)
	UI.confirm_dialog(self, "互传请求", "「%s」想接收你的词库，要发送吗？" % nm,
		func(): _lan.respond(ip, true), "发送", "拒绝", false,
		func(): _lan.respond(ip, false))

## 蓝牙通道的对方请求
func _on_bt_incoming(nm: String) -> void:
	UI.vibrate(60)
	UI.confirm_dialog(self, "互传请求", "「%s」想接收你的词库，要发送吗？" % nm,
		func(): _bt.call("bt_respond", true), "发送", "拒绝", false,
		func(): _bt.call("bt_respond", false))

## 第三步：收到数据，按事先选好的方式导入（自动识别 Markdown / JSON 备份两种格式）
func _on_receive_done(text: String) -> void:
	var stripped := text.strip_edges()
	if stripped.begins_with("{"):
		# 旧版 JSON 备份：走备份导入路径
		var d = JSON.parse_string(stripped)
		if not (d is Dictionary) or d.get("type") != "cet4_backup":
			_status("⚠️ 收到的数据无法识别")
			return
		var e := DB.merge_backup(stripped) if _mode_choice == "merge" else DB.import_backup(stripped)
		if e == "":
			UI.toast(self, "✅ 互传完成（%s）" % ("扩展词汇" if _mode_choice == "merge" else "覆盖原词汇"))
			_close()
		else:
			_status("⚠️ 导入失败：" + e)
		return
	# 固定 Markdown 格式：脚本按 "# 组名" 切分入库
	var res: Dictionary = DB.import_groups_md(text, _mode_choice == "overwrite")
	if res["err"] != "":
		_status("⚠️ 导入失败：" + res["err"])
		return
	UI.toast(self, "✅ 收到 %d 个分组：单词 +%d、词组 +%d（%s）" % [
		res["groups"], res["added_w"], res["added_p"],
		"扩展词汇" if _mode_choice == "merge" else "覆盖原词汇"])
	_close()

func _on_bt_done(ok: bool, msg: String) -> void:
	_status(("✅ " if ok else "⚠️ ") + msg)

func _close() -> void:
	_lan.stop_all()
	if _bt != null:
		_bt.call("bt_stop")
	queue_free()
