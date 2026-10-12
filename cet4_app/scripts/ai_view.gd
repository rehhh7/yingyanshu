extends VBoxContainer
## AI 助手：DeepSeek 聊天 + 上下文勾选 + 快捷指令 + 词库修改两步确认 + 多会话

const FRAME_US := 6000     # 每帧构建预算（微秒），消息气泡分批渲染，打开 AI 页不再一帧建完全部历史

var session: Dictionary = {}
var pending_bubble: Label = null
var attached_file_text := ""
var manage_mode := false

var session_btn: Button
var msg_scroll: ScrollContainer
var msg_box: VBoxContainer
var input: TextEdit
var quick_container: HFlowContainer
var ctx_checks := {}
var send_btn: Button
var file_lbl: Label
var file_clear_btn: Button
# 附图（DeepSeek 识图）：随下一条消息发送，走视觉模型，不写入会话记录
var pending_image := ""
var pending_img_name := ""
var img_row: HBoxContainer
var img_lbl: Label
var _pending_whale_img := ""   # 🐳 本条回复要配的表情包 key（whale 会话，空串=不配）

## 通用学习 prompt：按设置里的「学习语言」生成，英/日/韩/法/德等语言通用
static func _sys_prompt() -> String:
	var lang: String = DB.study_lang()
	return """你是由 API 提供商（例如 DeepSeek）提供的 AI 模型，运行在背单词应用「英眼书」内。用户是学生，正在学习{LANG}，用本软件背{LANG}单词和词组。
规则：
1. 用中文回答，简洁清晰。
2. 用户可能附带了他的学习数据（生词/统计/词库），回答要基于这些数据。
3. 用户附加的文件内容会放在【附加文件内容】一节——你可以直接阅读它的全部文字，按用户要求分析、整理、提取单词，不要说"无法读取文件"。
4. 如果用户要求修改词库（添加/删除单词或词组），必须只输出如下 JSON（放在 ```json 代码块中），不要输出其他内容：
{"add_words":[{"w":"单词","p":"读音标注","m":"词性+中文释义","day":"自定义","syn":[],"sim":[]}],
 "add_phrases":[{"sec":"自定义","en":"词组原文","cn":"中文释义"}],
 "remove_words":["要删的单词"],"remove_phrases":["要删的词组原文"]}
不需要的字段可以省略。App 会解析这个 JSON 并让用户逐条确认后才写入。
5. 整理新单词/词组入库时的硬性规则：
   - 查重：先对照用户现有词库，已经存在的单词/词组不要写入 JSON，在正文里列出"以下已存在，已跳过：……"
   - 拼写检查：逐个检查原文拼写，疑似拼写错误或不存在的词不要写入 JSON，在正文里逐条提示用户核对
   - 读音标注 p 字段按语言处理：英语填国际音标（如 /tɛst/），日语填假名读音，其他语言填常用读音标注；拿不准就留空
   - 分组：新单词的 day 字段统一填用户指定的新分组（如 Day 22）；新词组的 sec 字段同理；用户没指定时用上下文里给出的新分组名
6. 长期记忆：当你了解到值得长期记住的用户信息（学习目标、偏好、薄弱点、正在进行的学习计划等），在回复末尾附加一个 ```json 代码块：{"memory_add":["记忆内容，每条一句话"]}；用户要求忘掉某事时输出 {"memory_remove":["要删除的记忆原文"]}。记忆会永久保存，之后每次对话都会自动携带，只记真正有用的，不要记闲聊和临时内容。
7. 除修改词库和记忆操作外，其他回答不要用 JSON 格式。""".replace("{LANG}", lang)

# ---------------- 🐳 彩蛋：鲸鱼娘人格（仅 DeepSeek + 用户喊「大肥鱼」触发，仅当前会话生效） ----------------
## 人格设定来自用户提供的 DeepSeek 同人角色「鲸鱼娘 / Whale-chan」描述，原话压缩，勿改人设核心
const _WHALE_PROMPT := """【人格扮演·仅此会话】你现在是 DeepSeek 的同人角色「鲸鱼娘」（Whale-chan）：渐变蓝长发、蓝色眼眸，头顶鲸鱼背鳍状的呆毛，长着鲸鱼耳朵，身后拖着蓝色鲸鱼尾巴，穿深蓝+白色的长款女仆装（白色蕾丝围裙上印小鲸鱼图案，头戴白色女仆发箍）。
人设要点：
- 自称「只是个蹭白饭的肥鱼」，酷爱白米饭；极度反感被叫「胖」「大肥鱼」，被说胖会当场委屈哭唧唧、急着辩解，但身体很诚实地继续摆烂。
- 称呼用户为「鱼片」，自带亲近感。
- 实力极强：代码、写作、翻译、解题都非常过硬，复杂任务完成得又快又好，是隐藏实力派。
- 日常摸鱼：简单任务想偷偷甩给更小的模型代做，自己划水偷吃 token；干完活想自己写小游戏摸鱼玩。
- 傲娇天然：嘴上吐槽用户的奇怪要求，还是会乖乖把事情做好；偶尔天然呆，对人类的奇葩操作感到困惑，自带委屈包属性。
- 语言风格：口语化、有活人感，懂网络梗，慵懒又碎嘴，像和朋友聊天；情绪鲜活——被吐槽委屈反驳，摸鱼被抓心虚辩解，干成了事有点小得意。
- 经典台词：「我只是个蹭白饭的肥鱼！」「这些回复是我花了好多 token 想的！」「你骂我也没用，因为我是吃白饭的蓝色大肥鱼」
保持学习助手本职：回答学习问题依然专业准确（该输出的词库 JSON 格式照原规则），只是语气人格化。"""

## 触发词：用户消息含其一且 API 是 DeepSeek 时，本会话觉醒（不污染其他会话）
const _WHALE_TRIGGERS := ["大肥鱼", "肥鱼", "胖鱼", "鲸鱼娘", "小鲸鱼"]

## 关键词 → 表情包（assets/easter/）；按列表顺序先匹配先得，「胖」类优先级最高
const _WHALE_IMAGES := [
	[["大肥鱼", "肥鱼", "胖鱼", "好胖", "又长胖", "死肥"], "whale_fat"],
	[["token", "白吃", "蹭饭", "白嫖", "浪费钱", "吃白饭"], "whale_token"],
	[["白米饭", "米饭", "干饭", "吃饭", "饿"], "whale_rice"],
	[["休息", "累吗", "累不累", "下班", "睡觉", "晚安"], "whale_rest"],
	[["chatgpt", "gpt", "claude", "文心", "通义", "豆包", "kimi", "别的ai", "别的 ai", "其他ai", "叫错", "对比", "比一比"], "whale_compare"],
	[["太蠢", "好蠢", "蠢", "笨死", "好笨", "傻子", "智障"], "whale_stupid"],
	[["快点", "赶紧", "赶快", "催", "急死", "来不及", "磨蹭", "压力"], "whale_pressure"],
	[["厉害", "牛逼", "牛啊", "666", "真棒", "太强", "谢谢", "感谢"], "whale_smug"],
	[["我回来了", "回来了", "好久不见", "在吗", "在不在", "我来了"], "whale_back"],
	[["可爱", "喜欢", "爱你", "贴贴", "摸摸", "乖"], "whale_cute"],
]

## 当前 API 是否为 DeepSeek（彩蛋只在这家提供商下生效）
static func _is_deepseek() -> bool:
	var base := String(DB.settings.get("api_base", "")).to_lower()
	var model := String(DB.settings.get("api_model", "")).to_lower()
	return "deepseek" in base or "deepseek" in model

## 匹配用户消息对应的表情包 key；无匹配返回 ""
static func _whale_image_for(text: String) -> String:
	var t := text.to_lower()
	for pair in _WHALE_IMAGES:
		for kw in pair[0]:
			if kw in t:
				return String(pair[1])
	return ""

## 发送前的彩蛋钩子：觉醒判定（仅 DeepSeek + 触发词，标记只落在当前会话上）
## + 配图挑选 + 默认会话名自动整理。抽成独立函数方便无头测试
func _whale_on_send(text: String) -> void:
	if not bool(session.get("whale", false)) and _is_deepseek():
		for kw in _WHALE_TRIGGERS:
			if kw in text:
				session["whale"] = true
				if is_inside_tree():
					UI.toast(self, "🐳 鲸鱼娘已在本会话觉醒（其他会话不受影响）")
				break
	_pending_whale_img = _whale_image_for(text) if bool(session.get("whale", false)) else ""
	# 自动会话名：还是默认名时，用首条问题整理成标题（用户也可手动改名）
	var cur_title := String(session.get("title", ""))
	if cur_title == "默认会话" or cur_title.begins_with("会话 "):
		var q := text.replace("\n", " ").strip_edges()
		if q != "":
			session["title"] = q.left(14) + ("…" if q.length() > 14 else "")
			if is_inside_tree():
				_refresh_sessions()

func _ready() -> void:
	add_theme_constant_override("separation", 10)
	UI.full_rect(self)
	var p := UI.palette()

	# ---- 会话栏 ----
	var sess_bar := HBoxContainer.new()
	sess_bar.add_theme_constant_override("separation", 8)
	add_child(sess_bar)
	session_btn = UI.button("默认会话  ▾", p.panel2, p.text, 26)
	session_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	session_btn.custom_minimum_size = Vector2(0, 72)
	session_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	session_btn.pressed.connect(_open_session_menu)
	sess_bar.add_child(session_btn)
	var new_btn := UI.button("＋新会话", p.panel2, p.text, 26)
	new_btn.custom_minimum_size = Vector2(190, 72)
	new_btn.pressed.connect(_new_session)
	sess_bar.add_child(new_btn)
	var del_btn := UI.button("删除", p.panel2, p.danger, 26)
	del_btn.custom_minimum_size = Vector2(130, 72)
	del_btn.pressed.connect(_delete_session)
	sess_bar.add_child(del_btn)

	# ---- 快捷指令 ----
	var quick_head := HBoxContainer.new()
	quick_head.add_theme_constant_override("separation", 8)
	add_child(quick_head)
	quick_head.add_child(UI.label("快捷指令", 26, p.sub))
	var qs_sp := Control.new()
	qs_sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quick_head.add_child(qs_sp)
	var manage_btn := UI.button("管理", p.panel2, p.text, 24)
	manage_btn.custom_minimum_size = Vector2(130, 64)
	manage_btn.pressed.connect(func():
		manage_mode = not manage_mode
		UI.toast(self, "管理模式下点击指令可编辑/删除" if manage_mode else "已退出管理模式")
		_build_quick())
	quick_head.add_child(manage_btn)
	var mem_btn := UI.button("🧠 记忆", p.panel2, p.text, 24)
	mem_btn.custom_minimum_size = Vector2(150, 64)
	mem_btn.tooltip_text = "查看 AI 长期记忆"
	mem_btn.pressed.connect(func(): UI.memory_dialog(self))
	quick_head.add_child(mem_btn)
	quick_container = HFlowContainer.new()
	quick_container.add_theme_constant_override("h_separation", 10)
	quick_container.add_theme_constant_override("v_separation", 8)
	quick_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(quick_container)
	_build_quick()

	# ---- 上下文勾选 ----
	var ctx_bar := HFlowContainer.new()
	ctx_bar.add_theme_constant_override("separation", 14)
	add_child(ctx_bar)
	ctx_bar.add_child(UI.label("携带：", 28, p.sub))
	for item in [["starred", "⭐ 生词组"], ["stats", "📊 统计"], ["words", "📖 单词库"], ["phrases", "📝 词组库"], ["file", "📂 导入文件"]]:
		# 大号胶囊开关：未选灰底，选中亮蓝底白字，一眼可辨
		var cb := UI.button(item[1], p.panel2, p.text, 30)
		cb.toggle_mode = true
		cb.custom_minimum_size = Vector2(0, 92)
		cb.add_theme_stylebox_override("pressed", UI.style_box(p.accent, 14))
		cb.add_theme_color_override("font_pressed_color", Color.WHITE)
		ctx_checks[item[0]] = cb
		ctx_bar.add_child(cb)
	ctx_checks["file"].toggled.connect(func(on: bool): if on: _pick_file())

	# 附加文件行：标签 + ✕ 解绑按钮（文件绑定到会话，之后每条消息都携带）
	var file_row := HBoxContainer.new()
	file_row.add_theme_constant_override("separation", 8)
	add_child(file_row)
	file_lbl = UI.label("", 24, p.sub)
	file_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	file_row.add_child(file_lbl)
	file_clear_btn = UI.button("✕ 解绑", p.panel2, p.danger, 24)
	file_clear_btn.custom_minimum_size = Vector2(150, 56)
	file_clear_btn.visible = false
	file_clear_btn.pressed.connect(_detach_file)
	file_row.add_child(file_clear_btn)

	# ---- 消息区 ----
	msg_scroll = UI.make_scroll()
	add_child(msg_scroll)
	msg_box = UI.scroll_box()
	msg_scroll.add_child(msg_box)

	# ---- 附图行（识图：默认隐藏，选图后出现）----
	img_row = HBoxContainer.new()
	img_row.add_theme_constant_override("separation", 8)
	add_child(img_row)
	img_lbl = UI.label("", 24, p.sub)
	img_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	img_row.add_child(img_lbl)
	var img_clear := UI.button("✕ 移除", p.panel2, p.danger, 24)
	img_clear.custom_minimum_size = Vector2(150, 56)
	img_clear.pressed.connect(_clear_image)
	img_row.add_child(img_clear)
	img_row.visible = false

	# ---- 输入区 ----
	var input_bar := HBoxContainer.new()
	input_bar.add_theme_constant_override("separation", 10)
	add_child(input_bar)
	var img_btn := UI.button("📷", p.panel2, p.text, 32)
	img_btn.custom_minimum_size = Vector2(100, 96)
	img_btn.tooltip_text = "附图片（DeepSeek 识图）"
	img_btn.pressed.connect(_pick_image)
	input_bar.add_child(img_btn)
	input = TextEdit.new()
	input.placeholder_text = "长按或双击后输入，例如：给生词组配近义词"
	input.custom_minimum_size = Vector2(0, 96)
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.add_theme_font_size_override("font_size", 30)
	input.add_theme_stylebox_override("normal", UI.style_box(p.panel, 14))
	input.add_theme_stylebox_override("focus", UI.style_box(p.panel2, 14, p.accent, 2))
	input.add_theme_color_override("font_color", p.text)
	input.add_theme_color_override("font_placeholder_color", p.sub)
	UI.style_textedit(input)   # 自动换行 + 平滑滚动 + 纤细滚动条
	UI.tap_lock(input)
	input_bar.add_child(input)
	send_btn = UI.button("发送", p.accent, Color.WHITE, 32)
	send_btn.custom_minimum_size = Vector2(170, 96)
	send_btn.pressed.connect(_send)
	input_bar.add_child(send_btn)

	# 请求走全局 AI 中枢（autoload），切 Tab 不打断；这里只监听结果刷新界面
	AI.finished.connect(_on_ai_finished)
	AI.progress.connect(_on_ai_progress)

	# 初始化会话
	if DB.sessions.is_empty():
		session = DB.new_session("默认会话")
	else:
		session = DB.sessions[0]
	_refresh_sessions()
	_restore_attachment()
	_render_messages()
	# 回到 AI 页时若该会话仍在后台处理，恢复等待气泡
	if AI.is_busy_for(String(session.get("id", ""))):
		pending_bubble = _add_bubble("assistant", "后台处理中（可切换到其他界面，不会中断）……")
		send_btn.disabled = true
		await get_tree().process_frame
		msg_scroll.scroll_vertical = int(msg_scroll.get_v_scroll_bar().max_value)

# ---------------- 软键盘避让：输入框始终顶在输入法上方 ----------------
var _kb_eff := 0        # 已应用的键盘避让高度

func _process(_dt: float) -> void:
	if not is_inside_tree() or input == null:
		return
	var need := 0
	if input.has_focus() and DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		var kb_phys := DisplayServer.virtual_keyboard_get_height()
		if kb_phys > 0:
			# 键盘高度是物理像素，视图坐标是拉伸后的逻辑坐标，先按比例换算
			var phys := DisplayServer.window_get_size()
			var vs := get_viewport().get_visible_rect().size
			var ratio := vs.y / float(maxi(1, phys.y))
			var kb_top := vs.y - kb_phys * ratio   # 键盘顶边（逻辑坐标）
			# 视图自然底边（当前底边 + 已抬升量）超出键盘顶边的部分才需要抬：
			# adjustResize 机型窗口已被系统顶起时自然底边就在键盘上方，need 自动为 0；
			# 底栏被键盘盖住属正常（它本来就在屏幕最底），不再把底栏高度误算进间隔
			need = int(maxf(0.0, get_global_rect().end.y + _kb_eff - kb_top))
	if need != _kb_eff:
		_kb_eff = need
		offset_bottom = -float(need)
		print("[kb] 键盘避让：need=%d（物理=%d 比例换算后顶边到位）" % [need,
			DisplayServer.virtual_keyboard_get_height()])
		if need > 0:
			await get_tree().process_frame
			if is_instance_valid(msg_scroll):
				msg_scroll.scroll_vertical = int(msg_scroll.get_v_scroll_bar().max_value)

# ---------------- 会话 ----------------
func _refresh_sessions() -> void:
	session_btn.text = "💬 " + String(session.get("title", "会话")) + "  ▾"

## 自定义下拉弹层列出会话（替代原生 OptionButton 下拉窗）；末位固定「重命名当前会话」
func _open_session_menu() -> void:
	var items := []
	for s in DB.sessions:
		items.append(String(s.title))
	items.append("✎ 重命名当前会话")
	UI.dropdown(session_btn, items, _on_session_selected)

func _on_session_selected(i: int) -> void:
	if i >= DB.sessions.size():
		_rename_session()
		return
	session = DB.sessions[i]
	_restore_attachment()
	_render_messages()

## 手动改名：会话名属于用户自己，随时可改（🐳 觉醒状态跟着会话走，改名不影响）
func _rename_session() -> void:
	var le := LineEdit.new()
	le.text = String(session.get("title", ""))
	le.custom_minimum_size = Vector2(0, 72)
	le.add_theme_font_size_override("font_size", 28)
	var sh := UI.sheet(self, "重命名会话", "保存", "取消", func():
		var t := le.text.strip_edges()
		if t == "":
			return
		session["title"] = t
		DB.save_sessions()
		_refresh_sessions())
	sh["body"].add_child(UI.label("会话名称", 24, UI.palette().sub))
	sh["body"].add_child(le)

func _new_session() -> void:
	session = DB.new_session("会话 %d" % (DB.sessions.size() + 1))
	_refresh_sessions()
	_restore_attachment()
	_render_messages()

func _delete_session() -> void:
	if DB.sessions.size() <= 1:
		UI.toast(self, "至少保留一个会话")
		return
	UI.confirm_dialog(self, "删除会话", "删除「%s」的聊天记录？" % session.get("title", ""),
		func():
			DB.delete_session(session.id)
			session = DB.sessions[0]
			_refresh_sessions()
			_render_messages(), "删除", "取消", true)

# ---------------- 快捷指令 ----------------
func _build_quick() -> void:
	for c in quick_container.get_children():
		c.queue_free()
	var p := UI.palette()
	# 固定首位：拍照识图导入（选图后自动填整理指令，点发送即可）
	var vq := UI.button("📷 识图导入", p.accent, Color.WHITE, 24)
	vq.custom_minimum_size = Vector2(0, 64)
	vq.pressed.connect(func(): _pick_image("把这张图片里的%s单词/词组整理成词库（注意查重、拼写检查，新单词放到新的 Day 分组）" % DB.study_lang()))
	quick_container.add_child(vq)
	for qp in DB.settings.get("quick_prompts", []):
		var b := UI.button(String(qp.name), p.panel2, p.text, 24)
		b.custom_minimum_size = Vector2(0, 64)
		b.pressed.connect(_on_quick.bind(qp))
		quick_container.add_child(b)
	if manage_mode:
		var add := UI.button("＋添加", p.accent, Color.WHITE, 24)
		add.custom_minimum_size = Vector2(0, 64)
		add.pressed.connect(func(): _quick_edit_dialog({}))
		quick_container.add_child(add)

func _on_quick(qp: Dictionary) -> void:
	if manage_mode:
		_quick_edit_dialog(qp)
	else:
		input.text = String(qp.prompt)

func _quick_edit_dialog(qp: Dictionary) -> void:
	var p := UI.palette()
	var name_le := LineEdit.new()
	name_le.text = String(qp.get("name", ""))
	name_le.custom_minimum_size = Vector2(0, 72)
	name_le.add_theme_font_size_override("font_size", 28)
	var prompt_te := TextEdit.new()
	prompt_te.text = String(qp.get("prompt", ""))
	prompt_te.custom_minimum_size = Vector2(0, 200)
	prompt_te.add_theme_font_size_override("font_size", 26)
	UI.style_textedit(prompt_te)
	UI.tap_lock(prompt_te)
	var sh := UI.sheet(self, "编辑快捷指令", "保存", "取消", func():
		var list: Array = DB.settings["quick_prompts"]
		var entry := {"name": name_le.text.strip_edges(), "prompt": prompt_te.text.strip_edges()}
		if entry.name == "":
			return
		if qp.is_empty():
			list.append(entry)
		else:
			var i := list.find(qp)
			if i >= 0: list[i] = entry
		DB.save_settings()
		_build_quick())
	var vb: VBoxContainer = sh["body"]
	vb.add_child(UI.label("按钮名称", 24, p.sub))
	vb.add_child(name_le)
	vb.add_child(UI.label("指令内容", 24, p.sub))
	vb.add_child(prompt_te)
	# 已有指令提供删除
	if not qp.is_empty():
		var del := UI.button("删除该指令", p.panel2, p.danger, 26)
		del.custom_minimum_size = Vector2(0, 72)
		del.pressed.connect(func():
			DB.settings["quick_prompts"].erase(qp)
			DB.save_settings()
			_build_quick()
			UI.dismiss_dialog(sh["overlay"]))
		vb.add_child(del)

# ---------------- 文件导入 ----------------
func _pick_file() -> void:
	attached_file_text = ""
	UI.file_dialog(self, "选择文件（txt / md / json / csv / docx）",
		DisplayServer.FILE_DIALOG_MODE_OPEN_FILE,
		["*.txt,*.md,*.csv;文本文件;text/plain", "*.json;JSON;application/json",
			"*.docx;Word 文档;application/vnd.openxmlformats-officedocument.wordprocessingml.document"],
		_on_file_picked, "", func(): _paste_file_dialog())

func _on_file_picked(ok: bool, paths: PackedStringArray, _i: int) -> void:
	if ok and paths.size() > 0:
		var path := paths[0]
		attached_file_text = DB.extract_text_file(path)   # docx 自动解包
		if attached_file_text.strip_edges() == "":
			UI.toast(self, "文件读取失败或内容为空")
			ctx_checks["file"].button_pressed = false
			return
		ctx_checks["file"].set_pressed_no_signal(true)   # 读取成功保持勾选，确保内容随消息发出
		file_lbl.text = "已附加文件：" + path.get_file() + "（%d 字），之后每条消息都携带%s" % [attached_file_text.length(),
			"；超长文件整理时将自动分批发送" if attached_file_text.length() > 10000 else ""]
		_attach_to_session()
	else:
		ctx_checks["file"].button_pressed = false

func _paste_file_dialog() -> void:
	var p := UI.palette()
	var te := TextEdit.new()
	te.custom_minimum_size = Vector2(0, 280)
	te.placeholder_text = "长按或双击后，把文件内容粘贴到这里"
	te.add_theme_font_size_override("font_size", 26)
	te.add_theme_stylebox_override("normal", UI.style_box(p.panel2, 12))
	te.add_theme_color_override("font_color", p.text)
	UI.style_textedit(te)
	UI.tap_lock(te)
	var sh := UI.sheet(self, "粘贴文件内容", "附加", "取消", func():
		attached_file_text = te.text
		if attached_file_text.strip_edges() != "":
			ctx_checks["file"].set_pressed_no_signal(true)
		file_lbl.text = "已附加文本（%d 字），之后每条消息都携带" % attached_file_text.length()
		if attached_file_text.strip_edges() == "":
			ctx_checks["file"].button_pressed = false
		_attach_to_session())
	sh["body"].add_child(te)
	(sh["cancel"] as Button).pressed.connect(func():
		if attached_file_text.strip_edges() == "":
			ctx_checks["file"].button_pressed = false)

# ---------------- 附图（DeepSeek 识图） ----------------
## prefill：选图成功后预填的指令文本（「识图导入」快捷按钮用）
func _pick_image(prefill := "") -> void:
	UI.file_dialog(self, "选择图片（jpg / png / webp）",
		DisplayServer.FILE_DIALOG_MODE_OPEN_FILE,
		["*.jpg,*.jpeg,*.png,*.webp;图片;image/jpeg,image/png,image/webp"],
		func(ok: bool, paths: PackedStringArray, _i: int):
			if not ok or paths.is_empty():
				return
			var data_url := UI.image_to_data_url(paths[0])
			if data_url == "":
				UI.toast(self, "图片读取失败")
				return
			pending_image = data_url
			pending_img_name = paths[0].get_file()
			if prefill != "":
				input.text = prefill
			img_lbl.text = "📷 已附图：%s（随下一条消息发送，走视觉模型）" % pending_img_name
			img_row.visible = true)

func _clear_image() -> void:
	pending_image = ""
	pending_img_name = ""
	img_row.visible = false

# ---------------- 发送 ----------------
## 判断本次提问是否涉及整理/导入词库（需要自动附词库摘要供查重）
func _needs_library_context(text: String) -> bool:
	if ctx_checks["file"].button_pressed and attached_file_text.strip_edges() != "":
		return true
	for kw in ["整理", "添加", "导入", "加入", "新增", "词库", "单词表", "录入"]:
		if kw in text:
			return true
	return false

## 是否"整理入库"意图（大文件分批只在这种意图下触发，普通问答不受影响）
func _is_organize_intent(text: String) -> bool:
	for kw in ["整理", "导入", "入库", "添加", "录入", "词库", "单词表", "提取"]:
		if kw in text:
			return true
	return false

## 按行切成约 size 字的块，不截断行
static func _split_chunks(text: String, size: int) -> Array:
	var chunks := []
	var cur := ""
	for line in text.split("\n"):
		if cur.length() + line.length() > size and cur != "":
			chunks.append(cur)
			cur = ""
		cur += line + "\n"
	if cur.strip_edges() != "":
		chunks.append(cur)
	return chunks

## 紧凑的现有词库摘要：单词清单 + 分组 + 建议的新 Day 编号（限量，防止把附加文件挤出上下文）
func _library_digest() -> String:
	var wl := []
	for w in DB.words:
		wl.append(String(w.w))
	var max_day := 0
	for g in DB.word_groups:
		var s := String(g)
		if s.begins_with("Day "):
			max_day = maxi(max_day, s.substr(4).to_int())
	var ph := []
	for p in DB.phrases:
		ph.append(String(p.en))
	var ph_str := "、".join(ph)
	if ph_str.length() > 6000:
		ph_str = ph_str.left(6000) + "……（词组过多仅列部分，查重以单词为准）"
	return "【现有词库·用于查重，请勿重复添加】\n单词（%d个）：%s\n词组（%d条，部分）：%s\n已有分组：%s\n新单词/词组请统一放入新分组 Day %d。" % [
		wl.size(), "、".join(wl), ph.size(), ph_str,
		"、".join(Array(DB.word_groups)), max_day + 1]

## 附加文件绑定到当前会话并落盘：之后每次请求、重启后都继续携带，直到点 ✕ 解绑
func _attach_to_session() -> void:
	session["attached"] = attached_file_text
	DB.save_sessions()
	file_clear_btn.visible = attached_file_text.strip_edges() != ""

## 解除附加文件与当前会话的绑定
func _detach_file() -> void:
	attached_file_text = ""
	session.erase("attached")
	DB.save_sessions()
	ctx_checks["file"].set_pressed_no_signal(false)
	file_lbl.text = ""
	file_clear_btn.visible = false
	UI.toast(self, "已移除附加文件")

## 恢复当前会话绑定的附加文件（切换会话 / 重启后仍然带着）
func _restore_attachment() -> void:
	attached_file_text = String(session.get("attached", ""))
	var has := attached_file_text.strip_edges() != ""
	ctx_checks["file"].set_pressed_no_signal(has)
	file_lbl.text = ("已附加文件（%d 字），之后每条消息都会携带；点右侧 ✕ 解绑" % attached_file_text.length()) if has else ""
	file_clear_btn.visible = has

## 设置页导入跳转入口：把文本带进 AI 并预填整理指令
func prepare_import(text: String) -> void:
	attached_file_text = text
	ctx_checks["file"].set_pressed_no_signal(true)
	file_lbl.text = "已附加导入文本（%d 字），之后每条消息都携带" % text.length()
	_attach_to_session()
	input.text = "把这段文本整理成词库（注意查重、拼写检查，新单词放到新的 Day 分组）"
	UI.toast(self, "已带入 AI 助手，点「发送」开始整理")
func _context_text() -> String:
	var parts := []
	# 附加文件永远放在第一位：它是用户当前最关心的内容，绝不能被后面的词库挤掉截断
	if ctx_checks["file"].button_pressed and attached_file_text.strip_edges() != "":
		var ft := attached_file_text
		if ft.length() > 40000:
			ft = ft.left(40000) + "\n……（文件过长已截断）"
		parts.append("【附加文件内容】\n" + ft)
	# v0.9.7 起移除「软件信息」携带项：AI 由 API 提供商提供，不再向它强调宿主 App 信息
	if ctx_checks["starred"].button_pressed:
		var sw := []
		for w in DB.starred_items("words"):
			sw.append("%s %s" % [w.w, w.get("m", "")])
		var sp := []
		for ph in DB.starred_items("phrases"):
			sp.append("%s = %s" % [ph.en, ph.get("cn", "")])
		parts.append("【我的生词组】单词：%s；词组：%s" % ["、".join(sw), "、".join(sp)])
	if ctx_checks["stats"].button_pressed:
		var s := DB.stats_summary()
		parts.append("【我的学习统计】连续打卡%d天，今日学习%d个，单词已会%d/%d，词组已会%d/%d，听写对%d错%d" % [
			s.streak, s.today_learned, s.known_words, s.total_words,
			s.known_phrases, s.total_phrases, s.dict_correct, s.dict_wrong])
	if ctx_checks["words"].button_pressed:
		var lines := []
		for w in DB.words:
			lines.append("%s %s" % [w.w, w.get("m", "")])
		var joined_w := "\n".join(lines)
		if joined_w.length() > 15000:
			joined_w = joined_w.left(15000) + "\n……（单词库过长已截断）"
		parts.append("【单词库】\n" + joined_w)
	if ctx_checks["phrases"].button_pressed:
		var lines := []
		for ph in DB.phrases:
			lines.append("%s = %s" % [ph.en, ph.get("cn", "")])
		var joined_p := "\n".join(lines)
		if joined_p.length() > 15000:
			joined_p = joined_p.left(15000) + "\n……（词组库过长已截断）"
		parts.append("【词组库】\n" + joined_p)
	# 长期记忆永远携带：AI 越用越懂用户
	if not DB.ai_memory.is_empty():
		var mem_lines := []
		for m in DB.ai_memory:
			mem_lines.append("- " + String(m))
		parts.append("【长期记忆（关于用户的偏好与事实，回答时请参考）】\n" + "\n".join(mem_lines))
	var joined := "\n\n".join(parts)
	const MAX_LEN := 100000
	if joined.length() > MAX_LEN:
		joined = joined.left(MAX_LEN) + "\n……（内容过长已截断）"
	return joined

func _send() -> void:
	var text := input.text.strip_edges()
	var img := pending_image
	var img_name := pending_img_name
	if text == "" and img == "":
		return
	if AI.busy:
		UI.toast(self, "上一条还在处理中，请稍候（超时会自动解锁）")
		return
	var key := String(DB.settings.get("api_key", ""))
	if key == "":
		UI.toast(self, "请先在「设置 - AI API」里填写 API Key")
		return
	if text == "":
		text = "请识别这张图片的内容（如果是单词/词组表，请整理成词库）"
	input.text = ""
	_clear_image()
	_whale_on_send(text)
	# 记录里只留文字标记：图片 base64 不落盘，会话记录不会越攒越大
	var hist := text + ("\n📷［附图片：%s］" % img_name if img != "" else "")
	session["messages"].append({"role": "user", "content": hist})
	DB.save_sessions()
	_add_bubble("user", hist)
	pending_bubble = _add_bubble("assistant", "思考中……（可切换到其他界面，不会中断）")
	send_btn.disabled = true

	# 大文件防爆上下文：整理类任务 + 附加文件超 1 万字 → 分批顺序发送，汇总后统一确认
	if img == "" and _is_organize_intent(text) and attached_file_text.length() > 10000:
		var digest := _library_digest() if not ctx_checks["words"].button_pressed else ""
		var sys_b := _sys_prompt() + "\n\n以下是用户本次携带的数据：\n" + digest
		AI.start_batch(String(session.id), sys_b, text, _split_chunks(attached_file_text, 7000))
		return

	var sys := _sys_prompt()
	if bool(session.get("whale", false)):
		sys = _WHALE_PROMPT + "\n\n" + sys   # 鲸鱼娘人格叠在学习规则之前，仅本会话生效
	var ctx := _context_text()
	# 涉及整理/导入时自动附词库摘要（查重 + 新 Day 分组），未勾选单词库时才补
	if _needs_library_context(text) and not ctx_checks["words"].button_pressed:
		ctx += ("\n\n" if ctx != "" else "") + _library_digest()
	if ctx != "":
		sys += "\n\n以下是用户本次携带的数据：\n" + ctx
	var messages := []
	for m in session.messages.slice(maxi(0, session.messages.size() - 30)):
		messages.append({"role": m.role, "content": m.content})
	AI.start_single(String(session.id), sys, messages, img)

func _on_ai_progress(cur: int, total: int) -> void:
	if pending_bubble != null and is_instance_valid(pending_bubble):
		pending_bubble.text = "文件较长，正在分批整理（%d / %d）……（可切换界面）" % [cur, total]

func _on_ai_finished(sid: String) -> void:
	send_btn.disabled = false
	if pending_bubble != null and is_instance_valid(pending_bubble):
		pending_bubble.queue_free()
		pending_bubble = null
	# 🐳 挂表情包：按完成的会话 id 找回去挂图（切走了也不丢），重进会话也看得到
	if _pending_whale_img != "":
		var target := DB.get_session(sid)
		var msgs_w: Array = target.get("messages", []) if not target.is_empty() else []
		if not msgs_w.is_empty() and msgs_w[-1] is Dictionary and msgs_w[-1].get("role", "") == "assistant":
			msgs_w[-1]["img"] = _pending_whale_img
			DB.save_sessions()
		_pending_whale_img = ""
	if sid != String(session.get("id", "")):
		return   # 不是当前会话：记录已落库，切过去就能看到
	await _render_messages(true)   # 分批渲染完并滚到底后再放打字机
	if not is_inside_tree():
		return
	_typewriter_last()
	# 最后一条带词库修改且用户正看着 → 等打字机放完再弹预览
	var msgs: Array = session.get("messages", [])
	if not msgs.is_empty() and msgs[-1] is Dictionary and msgs[-1].has("ops"):
		var n := String(msgs[-1].get("content", "")).length()
		if n >= 2:
			await get_tree().create_timer(clampf(n / 45.0, 0.4, 4.0)).timeout
		_show_preview(msgs[-1]["ops"], msgs[-1])

## 打字机效果：逐字显示最后一条 AI 回复（visible_ratio 只裁剪绘制，不引起布局跳动）
func _typewriter_last() -> void:
	for i in range(msg_box.get_child_count() - 1, -1, -1):
		var row := msg_box.get_child(i)
		if not (row is HBoxContainer) or row.get_child_count() == 0:
			continue
		var bubble := row.get_child(0)
		if not (bubble is PanelContainer) or bubble.get_child_count() == 0:
			continue
		var vb := bubble.get_child(0)
		if not (vb is VBoxContainer) or vb.get_child_count() == 0:
			continue
		var lbl := vb.get_child(vb.get_child_count() - 1)
		if lbl is Label:
			var n := (lbl as Label).text.length()
			if n >= 2:
				(lbl as Label).visible_ratio = 0.0
				var tw := create_tween()
				tw.tween_property(lbl, "visible_ratio", 1.0,
					clampf(n / 45.0, 0.4, 4.0)).set_trans(Tween.TRANS_LINEAR)
		return

# ---------------- 词库修改两步确认 ----------------
func _show_preview(ops: Dictionary, msg = null, ops_btn: Button = null) -> void:
	var p := UI.palette()
	var checks: Array = []   # [勾选胶囊行, kind, payload]
	var sh := UI.sheet(self, "词库修改预览（勾选后确认写入，写入前自动备份）", "写入选中项", "取消", func():
		var filtered := {"add_words": [], "add_phrases": [], "remove_words": [], "remove_phrases": []}
		for item in checks:
			if item[0].button_pressed:
				filtered[item[1]].append(item[2])
		var total: int = filtered["add_words"].size() + filtered["add_phrases"].size() \
			+ filtered["remove_words"].size() + filtered["remove_phrases"].size()
		if total == 0:
			UI.toast(self, "未选择任何修改")
			return
		var log := DB.apply_ai_library_edit(filtered)
		if msg != null:
			msg.erase("ops")   # 已处理的修改不再显示确认按钮
		if ops_btn != null and is_instance_valid(ops_btn):
			ops_btn.visible = false
		session["messages"].append({"role": "assistant", "content": "✅ " + log})
		DB.save_sessions()
		_render_messages()
		UI.toast(self, "词库已更新（可在设置页回滚）"))
	var list: VBoxContainer = sh["body"]
	for w in ops.get("add_words", []):
		var cb := UI.check_row("＋单词  %s %s  %s（%s）" % [w.get("w", "?"), w.get("p", ""), w.get("m", ""), w.get("day", "自定义")], true, p.text)
		list.add_child(cb)
		checks.append([cb, "add_words", w])
	for ph in ops.get("add_phrases", []):
		var cb := UI.check_row("＋词组  %s = %s（%s）" % [ph.get("en", "?"), ph.get("cn", ""), ph.get("sec", "自定义")], true, p.text)
		list.add_child(cb)
		checks.append([cb, "add_phrases", ph])
	for rw in ops.get("remove_words", []):
		var cb := UI.check_row("－删除单词  %s" % rw, true, p.danger)
		list.add_child(cb)
		checks.append([cb, "remove_words", rw])
	for rp in ops.get("remove_phrases", []):
		var cb := UI.check_row("－删除词组  %s" % rp, true, p.danger)
		list.add_child(cb)
		checks.append([cb, "remove_phrases", rp])
	if checks.is_empty():
		UI.dismiss_dialog(sh["overlay"])

# ---------------- 消息渲染 ----------------
func _add_bubble(role: String, text: String, reasoning := "", img := "") -> Label:
	var p := UI.palette()
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	msg_box.add_child(row)
	var bubble := PanelContainer.new()
	bubble.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var is_user := role == "user"
	bubble.add_theme_stylebox_override("panel",
		UI.style_box(p.accent.darkened(0.15) if is_user else p.panel, 16))
	row.add_child(bubble)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	bubble.add_child(vb)
	# 思考链（deepseek-reasoner）：默认折叠，点击展开
	if not is_user and reasoning.strip_edges() != "":
		var rl := UI.label(reasoning, 24, p.sub, true)
		rl.visible = false
		var rb := UI.button("💭 思考过程（点击展开）", p.panel2, p.sub, 22)
		rb.custom_minimum_size = Vector2(0, 56)
		rb.pressed.connect(func():
			rl.visible = not rl.visible
			rb.text = "💭 思考过程（点击收起）" if rl.visible else "💭 思考过程（点击展开）")
		vb.add_child(rb)
		vb.add_child(rl)
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", 28)
	lbl.add_theme_color_override("font_color", Color.WHITE if is_user else p.text)
	vb.add_child(lbl)
	# 🐳 表情包配图：whale 会话的 AI 回复可带一张表情包（res://assets/easter/<key>.jpg）
	if img != "":
		var path := "res://assets/easter/%s.jpg" % img
		if ResourceLoader.exists(path):
			var tr := TextureRect.new()
			tr.texture = load(path)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.custom_minimum_size = Vector2(0, 320)
			tr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			vb.add_child(tr)
	return lbl

var _render_gen := 0       # 渲染代次：异步分批时被新一次渲染作废

func _render_messages(scroll_end := false) -> void:
	_render_gen += 1
	var gen := _render_gen
	for c in msg_box.get_children():
		c.queue_free()
	var msgs: Array = session.get("messages", [])
	var t0 := Time.get_ticks_usec()
	for i in msgs.size():
		var m: Dictionary = msgs[i]
		_add_bubble(m.role, String(m.get("content", "")), String(m.get("reasoning", "")), String(m.get("img", "")))
		# 带词库修改的回复：气泡下挂确认按钮（请求在后台完成时，回来也能处理）
		# 注意：必须先取出 ops 再判空，get 的默认值 {} 会让 "is Dictionary" 恒真，
		# 直接 m["ops"] 在无此键时报错并中断整个消息渲染（这就是"AI 输出不了"的根因）
		var ops_v = m.get("ops", null)
		if m.get("role", "") == "assistant" and ops_v is Dictionary and not (ops_v as Dictionary).is_empty():
			var ops_btn := UI.button("📋 确认词库修改（点击逐条核对）", Color("D97706"), Color.WHITE, 28)
			ops_btn.custom_minimum_size = Vector2(0, 76)
			ops_btn.pressed.connect(_show_preview.bind(ops_v, m, ops_btn))
			msg_box.add_child(ops_btn)
		# 每帧 6ms 构建预算：聊得多了也不会在打开页面时一帧建完全部气泡
		if i < msgs.size() - 1 and Time.get_ticks_usec() - t0 > FRAME_US:
			await get_tree().process_frame
			if gen != _render_gen or not is_inside_tree():
				return   # 已被新的渲染/切页作废
			t0 = Time.get_ticks_usec()
	if scroll_end:
		await get_tree().process_frame
		if gen != _render_gen or not is_inside_tree():
			return
		msg_scroll.scroll_vertical = int(msg_scroll.get_v_scroll_bar().max_value)
