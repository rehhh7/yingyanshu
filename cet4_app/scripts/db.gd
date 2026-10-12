extends Node
## 数据层：词库（内置+用户）、学习记录、统计、设置、聊天会话、备份

signal library_changed
signal progress_changed
signal settings_changed

const SETTINGS_PATH := "user://settings.json"
const PROGRESS_PATH := "user://progress.json"
const CUSTOM_WORDS_PATH := "user://custom_words.json"
const CUSTOM_PHRASES_PATH := "user://custom_phrases.json"
const REMOVED_PATH := "user://removed.json"
const SESSIONS_PATH := "user://chat_sessions.json"
const MEMORY_PATH := "user://ai_memory.json"
const BACKUP_DIR := "user://backups"
const EXPORT_DIR := "user://exports"

const VERSION := "0.9.27"   # 应用版本号（设置页/AI上下文/更新弹窗统一读这里）

## 读取内置更新日志；only_latest=true 时只取最新一个版本的段落
static func changelog_text(only_latest := false) -> String:
	if not FileAccess.file_exists("res://data/changelog.md"):
		return ""
	var text := FileAccess.get_file_as_string("res://data/changelog.md")
	if not only_latest:
		return text
	var first := text.find("## ")
	if first < 0:
		return ""
	var second := text.find("## ", first + 3)
	return text.substr(first, second - first).strip_edges() if second > 0 else text.substr(first).strip_edges()

var words: Array = []            # [{w,p,m,syn,sim,day,custom}]
var phrases: Array = []          # [{sec,en,cn,custom}]
var word_groups: PackedStringArray = []
var phrase_groups: PackedStringArray = []
var progress := {}
var settings := {}
var sessions: Array = []
var ai_memory: Array = []        # AI 长期记忆（String 列表，随每次对话自动携带）
var _sw_index: Array = []        # 搜索缓存：[[词条, 小写单词, 小写释义], ...]，避免每次搜索重复 to_lower 分配
var _sp_index: Array = []

const DEFAULT_SETTINGS := {
	"theme_dark": true,
	"font_bold": false,
	"group_renames": {"words": {}, "phrases": {}},
	"tts_rate": 1.0,
	"api_base": "https://api.deepseek.com",
	"api_key": "",
	"api_model": "deepseek-v4-flash",
	"study_lang": "英语",
	"quick_prompts": [
		{"name": "配近义词/形近词", "prompt": "请为我的生词组里的每个单词配上 1~2 个近义词和 1 个形近词，并各给一句中文辨析。用中文回答。"},
		{"name": "整理文本成词库", "prompt": "请把下面这段文本整理成词库 JSON。格式为 {\"add_words\":[{\"w\":\"单词\",\"p\":\"音标\",\"m\":\"词性+中文释义\",\"day\":\"自定义\",\"syn\":[],\"sim\":[]}],\"add_phrases\":[{\"sec\":\"自定义\",\"en\":\"英文词组\",\"cn\":\"中文释义\"}]}。只输出 JSON，不要输出其他内容。文本如下：\n"},
		{"name": "出10道听写题", "prompt": "请从我的生词组里挑 10 个词出听写题：给出中文释义让我默写英文。按 1. 中文释义 的格式列出题目，先不要给答案，等我回答后再批改。"},
		{"name": "分析学习数据", "prompt": "请分析我的学习统计数据，指出我的薄弱点并给出接下来一周的学习建议。用中文回答。"}
	]
}

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(BACKUP_DIR)
	DirAccess.make_dir_recursive_absolute(EXPORT_DIR)
	load_settings()
	load_builtin()
	load_custom()
	load_progress()
	load_sessions()
	load_memory()
	rebuild_library()

# ---------------- 设置 ----------------
func load_settings() -> void:
	settings = DEFAULT_SETTINGS.duplicate(true)
	if FileAccess.file_exists(SETTINGS_PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
		if d is Dictionary:
			for k in d:
				settings[k] = d[k]
	# 退役模型名迁移：deepseek-chat / deepseek-reasoner 已于 2026-07-24 停用
	if String(settings.get("api_base", "")).contains("deepseek.com") \
			and ["deepseek-chat", "deepseek-reasoner"].has(String(settings.get("api_model", ""))):
		settings["api_model"] = "deepseek-v4-flash"

func save_settings() -> void:
	_write_json(SETTINGS_PATH, settings)
	settings_changed.emit()

## 当前学习语言：AI 整理/识图的 prompt 按此切换（默认英语；清空时回退英语）
func study_lang() -> String:
	var l := String(settings.get("study_lang", "英语")).strip_edges()
	return l if l != "" else "英语"

# ---------------- 词库 ----------------
func load_builtin() -> void:
	words.clear()
	phrases.clear()
	if FileAccess.file_exists("res://data/words.md"):
		_load_builtin_md()   # Markdown 源文件（可直接编辑更新词库）
	else:
		_load_builtin_json() # 兼容旧版 JSON
	_apply_group_renames()
	_apply_group_deletes()

## 内置词库每次从源文件重载，分组删除也要在这里重放才能持久
func _apply_group_deletes() -> void:
	var dl: Dictionary = settings.get("group_deletes", {})
	var wd: Dictionary = dl.get("words", {})
	var pd: Dictionary = dl.get("phrases", {})
	if wd.is_empty() and pd.is_empty():
		return
	for i in range(words.size() - 1, -1, -1):
		if wd.has(String(words[i].get("day", ""))):
			words.remove_at(i)
	for i in range(phrases.size() - 1, -1, -1):
		if pd.has(String(phrases[i].get("sec", ""))):
			phrases.remove_at(i)

## 内置词库每次从源文件重载，分组改名要在这里重放才能持久
func _apply_group_renames() -> void:
	var rn: Dictionary = settings.get("group_renames", {})
	var wr: Dictionary = rn.get("words", {})
	var pr: Dictionary = rn.get("phrases", {})
	for w in words:
		if wr.has(w.get("day", "")):
			w["day"] = wr[w["day"]]
	for p in phrases:
		if pr.has(p.get("sec", "")):
			p["sec"] = pr[p["sec"]]

## 分组改名（长按分组卡片）：自定义词条直接改写，内置词条靠 rename 映射重放
func rename_group(kind: String, old_name: String, new_name: String) -> String:
	new_name = new_name.strip_edges()
	if new_name == "":
		return "名称不能为空"
	if new_name == old_name:
		return ""
	var groups := word_groups if kind == "words" else phrase_groups
	if groups.has(new_name):
		return "已存在同名分组"
	# 记录映射（内置词条每次重载时重放）
	var rn: Dictionary = settings.get("group_renames", {"words": {}, "phrases": {}})
	var map: Dictionary = rn.get(kind, {})
	# 若旧名本身是改过的，指回原始名，避免链式映射
	var origin := old_name
	for k in map:
		if map[k] == old_name:
			origin = k
			break
	map[origin] = new_name
	rn[kind] = map
	settings["group_renames"] = rn
	save_settings()
	# 内存中的词条立即改
	var items := words if kind == "words" else phrases
	var key := "day" if kind == "words" else "sec"
	for it in items:
		if it.get(key, "") == old_name:
			it[key] = new_name
	# 自定义词条落盘
	var path := CUSTOM_WORDS_PATH if kind == "words" else CUSTOM_PHRASES_PATH
	var custom_arr: Array = _read_json(path, [])
	var dirty := false
	for it in custom_arr:
		if it.get(key, "") == old_name or it.get(key, "") == origin:
			it[key] = new_name
			dirty = true
	if dirty:
		_write_json(path, custom_arr)
	rebuild_library()
	return ""

func _load_builtin_json() -> void:
	var wd = JSON.parse_string(FileAccess.get_file_as_string("res://data/words.json"))
	var pd = JSON.parse_string(FileAccess.get_file_as_string("res://data/phrases.json"))
	for w in wd.get("words", []):
		w["custom"] = false
		words.append(w)
	for p in pd.get("phrases", []):
		p["custom"] = false
		phrases.append(p)

## Markdown 词库格式：
##   ## 分组名
##   单词 /音标/ 词性. 释义 | 近: 近义词(辨析); ... | 似: 形近词(辨析); ...
##   词组行（phrases.md）：英文词组 中文释义
func _load_builtin_md() -> void:
	var group := ""
	for raw in FileAccess.get_file_as_string("res://data/words.md").split("\n", false):
		var line := String(raw).strip_edges()
		if line == "":
			continue
		if line.begins_with("##"):
			group = line.lstrip("#").strip_edges()
			continue
		if line.begins_with("#"):
			continue
		var w := _parse_md_word_line(line, group)
		if not w.is_empty():
			w["custom"] = false
			words.append(w)
	group = ""
	for raw in FileAccess.get_file_as_string("res://data/phrases.md").split("\n", false):
		var line := String(raw).strip_edges()
		if line == "":
			continue
		if line.begins_with("##"):
			group = line.lstrip("#").strip_edges()
			continue
		if line.begins_with("#"):
			continue
		var cut := _first_cjk(line)
		if cut <= 0:
			continue
		var en := line.substr(0, cut).strip_edges()
		var cn := line.substr(cut).strip_edges()
		if en == "" or cn == "":
			continue
		phrases.append({"sec": group, "en": en, "cn": cn, "custom": false})

## 找中文释义的起始位置：定位第一个汉字后，向前收纳紧邻的 ……（— 等中文常用前导符号（不越过空格）
static func _first_cjk(s: String) -> int:
	var i := -1
	for k in s.length():
		var c := s.unicode_at(k)
		if c >= 0x4E00 and c <= 0x9FFF:
			i = k
			break
	if i < 0:
		return -1
	while i > 0:
		var prev := s.unicode_at(i - 1)
		if prev == 0x2026 or prev == 0xFF08 or prev == 0x28 or prev == 0x2014 or prev == 0xFF09:
			i -= 1
		else:
			break
	return i

func _parse_md_word_line(line: String, group: String) -> Dictionary:
	var parts := line.split("|")
	var main := parts[0].strip_edges()
	var w := {"w": "", "p": "", "m": "", "day": group, "syn": [], "sim": []}
	var i1 := main.find("/")
	var i2 := main.find("/", i1 + 1) if i1 >= 0 else -1
	if i1 > 0 and i2 > i1:
		# 有音标：音标前全部是词条（兼容 snack bar 等多词条目），音标后原样是释义
		w["w"] = main.substr(0, i1).strip_edges()
		w["p"] = main.substr(i1, i2 - i1 + 1)
		w["m"] = main.substr(i2 + 1).strip_edges()
	else:
		# 无音标：从释义起点切分，词尾的词性缩写并入释义
		var cut := _first_cjk(main)
		if cut <= 0:
			return {}
		var en := main.substr(0, cut).strip_edges()
		var cn := main.substr(cut).strip_edges()
		var tokens := en.split(" ", false)
		var pos := []
		while tokens.size() > 1 and _is_pos_tag(tokens[tokens.size() - 1]):
			pos.push_front(tokens[tokens.size() - 1])
			tokens.remove_at(tokens.size() - 1)
		if tokens.is_empty():
			return {}
		w["w"] = " ".join(tokens)
		w["m"] = ((" ".join(pos) + " ") if not pos.is_empty() else "") + cn
	if w["w"] == "" or w["m"] == "":
		return {}
	# 近义词/形近词段：近: w(注); w2(注2)   —— 只按英文分号切，辨析里的中文分号不受影响
	for i in range(1, parts.size()):
		var seg := parts[i].strip_edges()
		var target := ""
		if seg.begins_with("近:") or seg.begins_with("近："):
			target = "syn"
			seg = seg.substr(2).strip_edges()
		elif seg.begins_with("似:") or seg.begins_with("似："):
			target = "sim"
			seg = seg.substr(2).strip_edges()
		else:
			continue
		for ent in seg.split(";"):
			var e := ent.strip_edges()
			if e == "":
				continue
			var bi := e.find("(")
			if bi > 0 and e.ends_with(")"):
				w[target].append({"w": e.left(bi).strip_edges(), "n": e.substr(bi + 1, e.length() - bi - 2)})
			else:
				w[target].append({"w": e, "n": ""})
	return w

func load_custom() -> void:
	# 用户词库（导入 / AI 写入），同 key 覆盖内置
	var cw = _read_json(CUSTOM_WORDS_PATH, [])
	var cp = _read_json(CUSTOM_PHRASES_PATH, [])
	var removed = _read_json(REMOVED_PATH, {"words": [], "phrases": []})
	var rw := {}
	for k in removed.get("words", []): rw[k] = true
	var rp := {}
	for k in removed.get("phrases", []): rp[k] = true
	words = words.filter(func(w): return not rw.has(word_id(w)))
	phrases = phrases.filter(func(p): return not rp.has(phrase_id(p)))
	var existing_w := {}
	for w in words: existing_w[word_id(w)] = true
	var existing_p := {}
	for p in phrases: existing_p[phrase_id(p)] = true
	for w in cw:
		w["custom"] = true
		if existing_w.has(word_id(w)):
			for i in words.size():
				if word_id(words[i]) == word_id(w):
					w["custom"] = true
					words[i] = w
					break
		else:
			words.append(w)
	for p in cp:
		p["custom"] = true
		if existing_p.has(phrase_id(p)):
			for i in phrases.size():
				if phrase_id(phrases[i]) == phrase_id(p):
					p["custom"] = true
					phrases[i] = p
					break
		else:
			phrases.append(p)

func rebuild_library() -> void:
	var wg := {}
	var pg := {}
	for w in words:
		if not wg.has(w.day): wg[w.day] = true
	for p in phrases:
		if not pg.has(p.sec): pg[p.sec] = true
	var wga := wg.keys()
	wga.sort_custom(func(a, b): return _group_sort_key(a) < _group_sort_key(b))
	word_groups = PackedStringArray(wga)
	var pga := pg.keys()
	pga.sort_custom(func(a, b): return _group_sort_key(a) < _group_sort_key(b))
	phrase_groups = PackedStringArray(pga)
	_rebuild_search_index()
	library_changed.emit()

func _rebuild_search_index() -> void:
	## 搜索小写缓存：词库变动时重建一次，搜索时零分配
	_sw_index.clear()
	for w in words:
		_sw_index.append([w, String(w.get("w", "")).to_lower(), String(w.get("m", "")).to_lower()])
	_sp_index.clear()
	for p in phrases:
		_sp_index.append([p, String(p.get("en", "")).to_lower(), String(p.get("cn", ""))])

static func _group_sort_key(s: String) -> String:
	# “手写一”最前，Day 数字其次，P 数字按数值
	if s.begins_with("手写"): return "0"
	var m := RegEx.new()
	m.compile("(\\d+)")
	var r := m.search(s)
	if r: return "1" + "%06d" % int(r.get_string(1))
	return "2" + s

static func word_id(w: Dictionary) -> String:
	return String(w.get("w", "")).to_lower().strip_edges()

static func phrase_id(p: Dictionary) -> String:
	return String(p.get("en", "")).to_lower().strip_edges() + "|" + String(p.get("sec", ""))

func words_in_group(day: String) -> Array:
	return words.filter(func(w): return w.day == day)

func phrases_in_group(sec: String) -> Array:
	return phrases.filter(func(p): return p.sec == sec)

func search(query: String) -> Dictionary:
	var q := query.to_lower().strip_edges()
	var rw := []
	var rp := []
	if q != "":
		if _sw_index.is_empty() and not words.is_empty():
			_rebuild_search_index()   # 兜底：缓存未建时现建
		for e in _sw_index:
			if q in e[1] or q in e[2]:
				rw.append(e[0])
		for e in _sp_index:
			if q in e[1] or q in e[2]:
				rp.append(e[0])
	return {"words": rw, "phrases": rp}

# ---------------- 进度 / 星标 ----------------
func load_progress() -> void:
	progress = _read_json(PROGRESS_PATH, {})
	if not progress.has("words"): progress["words"] = {}
	if not progress.has("phrases"): progress["phrases"] = {}
	if not progress.has("daily"): progress["daily"] = {}

func save_progress() -> void:
	_write_json(PROGRESS_PATH, progress)
	progress_changed.emit()

func _prog(kind: String, id: String) -> Dictionary:
	var pool: Dictionary = progress[kind]
	if not pool.has(id):
		pool[id] = {"star": false, "known": false, "seen": 0}
	return pool[id]

func is_starred(kind: String, id: String) -> bool:
	return _prog(kind, id).get("star", false)

func toggle_star(kind: String, id: String) -> bool:
	var rec := _prog(kind, id)
	rec["star"] = not rec.get("star", false)
	if rec["star"]:
		rec["star_at"] = Time.get_datetime_string_from_system()   # 记录收藏日期
	else:
		rec.erase("star_at")
	save_progress()
	return rec["star"]

## 收藏日期（YYYY-MM-DD，无记录返回空串）
func star_date(kind: String, id: String) -> String:
	var pool: Dictionary = progress[kind]
	var s := String(pool.get(id, {}).get("star_at", ""))
	return s.left(10)

func mark_known(kind: String, id: String, known: bool) -> void:
	var rec := _prog(kind, id)
	rec["known"] = known
	rec["seen"] = int(rec.get("seen", 0)) + 1
	_touch_today("learned", 1)
	save_progress()

func mark_seen(kind: String, id: String) -> void:
	var rec := _prog(kind, id)
	rec["seen"] = int(rec.get("seen", 0)) + 1
	# 不每次翻卡都写盘，统一由调用方合适时机 save
	save_progress()

func starred_items(kind: String) -> Array:
	var out := []
	var pool: Dictionary = progress[kind]
	if kind == "words":
		for w in words:
			if pool.get(word_id(w), {}).get("star", false):
				out.append(w)
	else:
		for p in phrases:
			if pool.get(phrase_id(p), {}).get("star", false):
				out.append(p)
	return out

func group_progress(kind: String, group: String) -> Dictionary:
	var items: Array = words_in_group(group) if kind == "words" else phrases_in_group(group)
	var known := 0
	var starred := 0
	for it in items:
		var id: String = word_id(it) if kind == "words" else phrase_id(it)
		var rec: Dictionary = progress[kind].get(id, {})
		if rec.get("known", false): known += 1
		if rec.get("star", false): starred += 1
	return {"total": items.size(), "known": known, "starred": starred}

# ---------------- 统计 ----------------
static func today_str() -> String:
	return Time.get_date_string_from_system()

func _touch_today(field: String, delta: int) -> void:
	var t := today_str()
	if not progress["daily"].has(t):
		progress["daily"][t] = {"learned": 0, "dict_correct": 0, "dict_wrong": 0}
	progress["daily"][t][field] = int(progress["daily"][t].get(field, 0)) + delta

func record_dictation(correct: bool) -> void:
	_touch_today("dict_correct" if correct else "dict_wrong", 1)
	save_progress()

func streak_days() -> int:
	var streak := 0
	var day := Time.get_datetime_dict_from_system()
	var t := Time.get_unix_time_from_datetime_dict(day)
	for i in range(0, 370):
		var d := Time.get_date_string_from_unix_time(t - i * 86400)
		var rec: Dictionary = progress["daily"].get(d, {})
		var active := int(rec.get("learned", 0)) + int(rec.get("dict_correct", 0)) + int(rec.get("dict_wrong", 0)) > 0
		if active:
			streak += 1
		elif i == 0:
			continue  # 今天还没学不打断连续
		else:
			break
	return streak

func stats_summary() -> Dictionary:
	# 只统计当前词库中实际存在的词条（已删除词条的进度残留不计入，避免"8/1"这类错位）
	var valid_w := {}
	for w in words:
		valid_w[word_id(w)] = true
	var valid_p := {}
	for p in phrases:
		valid_p[phrase_id(p)] = true
	var known_w := 0
	var star_w := 0
	for id in progress["words"]:
		if not valid_w.has(id):
			continue
		var rec: Dictionary = progress["words"][id]
		if rec.get("known", false): known_w += 1
		if rec.get("star", false): star_w += 1
	var known_p := 0
	var star_p := 0
	for id in progress["phrases"]:
		if not valid_p.has(id):
			continue
		var rec: Dictionary = progress["phrases"][id]
		if rec.get("known", false): known_p += 1
		if rec.get("star", false): star_p += 1
	var dc := 0
	var dw := 0
	for d in progress["daily"].values():
		dc += int(d.get("dict_correct", 0))
		dw += int(d.get("dict_wrong", 0))
	var t := today_str()
	var today: Dictionary = progress["daily"].get(t, {})
	return {
		"known_words": known_w, "star_words": star_w,
		"known_phrases": known_p, "star_phrases": star_p,
		"total_words": words.size(), "total_phrases": phrases.size(),
		"dict_correct": dc, "dict_wrong": dw,
		"today_learned": int(today.get("learned", 0)),
		"today_dict_correct": int(today.get("dict_correct", 0)),
		"today_dict_wrong": int(today.get("dict_wrong", 0)),
		"streak": streak_days(),
	}

# ---------------- 备份 / 导入导出 / 词库热更新 ----------------
## 统一的「用户选中的文件」读字节：先 FileAccess；读不到且是安卓则走 YysKit 插件的
## ContentResolver——部分机型上 FileAccess 读不动系统选择器返回的 content:// URI
## （GitHub godot#105328 / 提案#14263），而 ContentResolver 百分百可读（选择器已授权）
static func read_uri_bytes(path: String) -> PackedByteArray:
	var data := FileAccess.get_file_as_bytes(path)
	if data.is_empty() and OS.get_name() == "Android" and Engine.has_singleton("YysKit"):
		var r = Engine.get_singleton("YysKit").call("read_uri_bytes", path)
		if r is PackedByteArray:
			data = r
	return data

## 读取文本类文件（txt/md/json/csv/docx），docx 自动解包提取纯文本
## 注意：安卓文件选择器返回 content:// URI（无扩展名、ZIPReader 打不开），
## 所以一律先读字节（FileAccess 支持 URI），再按 ZIP 魔数 "PK" 判断 docx
func extract_text_file(path: String) -> String:
	var data := read_uri_bytes(path)
	if data.is_empty():
		return ""
	if data.size() >= 4 and data[0] == 0x50 and data[1] == 0x4B:
		# PK 头 = zip 容器（docx）；落到临时文件再解包
		var tmp := "user://_import_tmp.docx"
		var f := FileAccess.open(tmp, FileAccess.WRITE)
		if f == null:
			return ""
		f.store_buffer(data)
		f.close()
		var zr := ZIPReader.new()
		if zr.open(tmp) != OK:
			return ""
		if not zr.file_exists("word/document.xml"):
			zr.close()
			return ""
		var xml := zr.read_file("word/document.xml").get_string_from_utf8()
		zr.close()
		xml = xml.replace("</w:p>", "\n")
		var re := RegEx.new()
		re.compile("<[^>]+>")
		return re.sub(xml, "", true).xml_unescape()
	return data.get_string_from_utf8()

## 下一个可用的 Day 分组名：扫现有 "Day N" 取最大值 +1
func next_day_name() -> String:
	var max_n := 0
	var re := RegEx.new()
	re.compile("^Day\\s*(\\d+)$")
	for g in word_groups:
		var m := re.search(g)
		if m:
			max_n = maxi(max_n, int(m.get_string(1)))
	return "Day %d" % (max_n + 1)

static func _is_pos_tag(t: String) -> bool:
	## 判断是否为词性缩写（v / n. / adj 等）
	var s := t.to_lower().trim_suffix(".")
	return ["v", "n", "adj", "adv", "vt", "vi", "prep", "conj", "pron", "num", "art", "abbr", "int", "aux", "phr"].has(s)

## 本地整理导入文本（不联网）：逐行解析为单词/词组，自动查重、挑出无法识别的行
## 支持格式：自由文本（音标/词性/序号/项目符号）、TSV 分列、ECDICT 风格 CSV（GitHub 主流词库格式）、
## JSONL（每行一个 JSON）、PDF 双栏合并行自动拆分
## 返回 {words:[{w,p,m,day,syn,sim}], phrases:[{en,cn,sec}], unknown:[String], dup:[String]}
func parse_import_text(text: String) -> Dictionary:
	return _parse_word_lines(text, next_day_name())

## 逐行解析内核：词条归入指定分组（互传 Markdown 切组后逐组复用）
func _parse_word_lines(text: String, day: String) -> Dictionary:
	var out := {"words": [], "phrases": [], "unknown": [], "dup": []}
	var existing_w := {}
	for w in words:
		existing_w[word_id(w)] = true
	var existing_p := {}
	for p in phrases:
		existing_p[String(p.get("en", "")).to_lower().strip_edges()] = true
	# 正则全部在循环外预编译（PCRE2 不支持 (?i)，用大小写字符组代替）
	var re_num := RegEx.new()
	re_num.compile("^[\\(（]?\\d{1,4}[\\.、\\)）]\\s*")
	var re_bullet := RegEx.new()
	re_bullet.compile("^[\\-\\*•·◦▪‣●○▶➤»①-⑳]\\s*")
	var re_head := RegEx.new()
	re_head.compile("^([Dd][Aa][Yy]|[Uu][Nn][Ii][Tt]|[Ll][Ii][Ss][Tt]|[Ss][Ee][Cc][Tt][Ii][Oo][Nn]|[Pp][Aa][Rr][Tt])\\s*\\d+$")
	var re_word := RegEx.new()
	re_word.compile("^[A-Za-z][A-Za-z\\-']*$")
	var re_phon := RegEx.new()   # 音标块整体：/…/ 或 […] 或 【…】（允许内部空格）
	re_phon.compile("(/[^/\\s][^/]*/|\\[[^\\]]+\\]|【[^】]+】)")
	var re_cnpre := RegEx.new()  # 释义前的口音标记：美 / 英
	re_cnpre.compile("^(美|英)\\s+")
	# 收录单词/词组的小闭包（统一查重 + 释义必须含中文，否则进 unknown）
	var push_word := func(wtxt: String, phon: String, meaning: String) -> void:
		var id := wtxt.to_lower()
		if existing_w.has(id):
			if not out["dup"].has(wtxt):
				out["dup"].append(wtxt)
			return
		if meaning == "" or not _has_cjk(meaning):
			out["unknown"].append(wtxt + "（无释义，请核对）")
			return
		out["words"].append({"w": wtxt, "p": phon, "m": meaning, "day": day, "syn": [], "sim": []})
		existing_w[id] = true
	var push_phrase := func(en: String, cn: String) -> void:
		var pid := en.to_lower().strip_edges()
		if existing_p.has(pid):
			if not out["dup"].has(en):
				out["dup"].append(en)
			return
		if cn == "" or not _has_cjk(cn):
			out["unknown"].append(en + "（无释义，请核对）")
			return
		out["phrases"].append({"en": en, "cn": cn, "sec": day})
		existing_p[pid] = true
	for raw in text.split("\n", false):
		var raw_s := String(raw)
		var line := raw_s.replace("　", " ").strip_edges()   # 全角空格当空格
		if line == "" or line.begins_with("#") or line.begins_with("//"):
			continue
		# ---- JSONL：每行一个 JSON 对象（Anki/词典脚本导出常见）----
		if line.begins_with("{"):
			var d = JSON.parse_string(line)
			if d is Dictionary:
				var jw := String(d.get("word", d.get("w", ""))).strip_edges()
				var jen := String(d.get("en", d.get("phrase", ""))).strip_edges()
				var jp := String(d.get("phonetic", d.get("p", ""))).strip_edges()
				var jm := String(d.get("translation", d.get("m", d.get("cn", d.get("meaning", ""))))).strip_edges()
				if jw != "":
					push_word.call(jw, jp, jm)
				elif jen != "":
					push_phrase.call(jen, jm)
				else:
					out["unknown"].append(line.left(60))
				continue
			# 花括号开头但不是合法 JSON → 按普通文本继续
		# ---- TSV：制表符分列（Excel / Anki / 网页表格粘贴常见）----
		if raw_s.contains("\t"):
			var cols := raw_s.split("\t", false)
			var first := String(cols[0]).strip_edges()
			first = re_bullet.sub(re_num.sub(first, "", true), "", true).strip_edges()
			var phon_t := ""
			var cn_t := ""
			for i in range(1, cols.size()):
				var c := String(cols[i]).strip_edges().trim_prefix("\"").trim_suffix("\"")
				if c == "":
					continue
				if phon_t == "" and _is_phonetic_block(c):
					phon_t = c
					continue
				if cn_t == "" and _has_cjk(c):
					cn_t = c
			if first != "" and re_word.search(first) != null:
				push_word.call(first, phon_t, cn_t)
				continue
			if first.split(" ", false).size() >= 2 and re_word.search(first.split(" ", false)[0]) != null:
				push_phrase.call(first, cn_t)
				continue
			# 首列不像英文 → 按普通文本继续
		# ---- CSV：ECDICT 风格 word,phonetic,definition,translation,...（GitHub 主流词库格式）----
		if line.count(",") >= 2 or (line.count(",") >= 1 and line.contains("\"")):
			var cols2 := line.split(",", false)
			if cols2.size() >= 2:
				var c0 := String(cols2[0]).strip_edges().trim_prefix("\"").trim_suffix("\"")
				if re_word.search(c0) != null:
					var phon_c := ""
					var cn_c := ""
					for i in range(1, cols2.size()):
						var c := String(cols2[i]).strip_edges().trim_prefix("\"").trim_suffix("\"")
						if c == "":
							continue
						if phon_c == "" and _is_phonetic_block(c):
							phon_c = c
							continue
						if cn_c == "" and _has_cjk(c):
							cn_c = c
					if cn_c != "" or phon_c != "":
						push_word.call(c0, phon_c, cn_c)
						continue
		# ---- 自由文本 ----
		line = line.replace("\t", " ")
		line = re_num.sub(line, "", true)
		line = re_bullet.sub(line, "", true).strip_edges()
		if line == "" or re_head.search(line) != null:
			continue   # 跳过 "Day 5" 之类的标题行
		# 音标块整体提取（在切中文之前，允许音标内部带空格）
		var phon := ""
		var pm := re_phon.search(line)
		if pm != null:
			phon = pm.get_string(1)
			line = (line.substr(0, pm.get_start(1)) + " " + line.substr(pm.get_end(1))).strip_edges()
		# 找第一个中文字符，把行切成「英文部分 + 中文释义」
		var cut := -1
		for i in line.length():
			var c := line.unicode_at(i)
			if c >= 0x4E00 and c <= 0x9FFF:
				cut = i
				break
		if cut == 0:
			out["unknown"].append(line)   # 开头就是中文，无法对应英文
			continue
		var en_part := line
		var cn_part := ""
		if cut > 0:
			en_part = line.substr(0, cut).strip_edges()
			cn_part = line.substr(cut).strip_edges()
		# 释义开头的「美/英 + 音标」标记剥掉（如：tomato /x/ 美 /y/ 西红柿）
		while true:
			var before := cn_part
			cn_part = re_cnpre.sub(cn_part, "", true).strip_edges()
			var cm := re_phon.search(cn_part)
			if cm != null and cm.get_start(1) == 0:
				cn_part = cn_part.substr(cm.get_end(1)).strip_edges()
			if cn_part == before:
				break
		# 英文部分尾部的分隔标点清理掉（= ＝ — – ~ ～ 、 · 等手写常见分隔符）
		while en_part.length() > 0 and [":", "：", "-", "—", "–", ",", "，", "|", "；", ";", "=", "＝", "~", "～", "、", "·"].has(en_part.right(1)):
			en_part = en_part.left(en_part.length() - 1).strip_edges()
		if en_part == "":
			continue
		var tokens := en_part.split(" ", false)
		if tokens.is_empty() or re_word.search(tokens[0]) == null:
			out["unknown"].append(line)   # 首段不是英文单词开头（词性孤立行等）
			continue
		# 词性序列：词后连续的词性缩写（可多个、& 连接）并入释义前缀
		var pos_parts: Array = []
		var ti := 1
		while ti < tokens.size() and (_is_pos_tag(tokens[ti]) or tokens[ti] == "&"):
			if _is_pos_tag(tokens[ti]):
				pos_parts.append(tokens[ti])
			ti += 1
		if ti == tokens.size():
			# 单词词条
			var w0 := String(tokens[0])
			var prefix := (" ".join(pos_parts) + " ") if not pos_parts.is_empty() else ""
			# PDF/拍照双栏合并行：释义里藏着「英文词 + 中文」尾巴 → 自动拆成两条
			var sp := _split_merged_row(cn_part, re_word)
			if sp.is_empty():
				push_word.call(w0, phon, prefix + cn_part)
			else:
				push_word.call(w0, phon, prefix + String(sp[0]))
				push_word.call(String(sp[1]), "", String(sp[2]))
		else:
			# 词组
			push_phrase.call(en_part, cn_part)
	return out

static func _has_cjk(s: String) -> bool:
	for i in s.length():
		var c := s.unicode_at(i)
		if c >= 0x4E00 and c <= 0x9FFF:
			return true
	return false

static func _is_phonetic_block(c: String) -> bool:
	if c.length() < 2:
		return false
	var a := c.left(1)
	var b := c.right(1)
	return (a == "/" and b == "/") or (a == "[" and b == "]") or (a == "【" and b == "】")

## PDF 双栏合并行检测：释义形如「中文… 英文词 中文…」→ [释义1, 单词2, 释义2]，否则 []
static func _split_merged_row(cn: String, re_word: RegEx) -> Array:
	var toks := cn.split(" ", false)
	if toks.size() < 3:
		return []
	for i in range(1, toks.size() - 1):
		if re_word.search(String(toks[i])) == null:
			continue
		var left := " ".join(toks.slice(0, i))
		var right := " ".join(toks.slice(i + 1))
		if left == "" or right == "" or not _has_cjk(right):
			continue
		# 左侧最后一个字符必须是中文，避免把 "放弃 to give up sth" 这类英文注释拆错
		var last := left.unicode_at(left.length() - 1)
		if last >= 0x4E00 and last <= 0x9FFF:
			return [left, String(toks[i]), right]
	return []

# ================= 互传固定格式（Markdown）=================
## 格式约定：
##   # 组名            ← 父项目（分组）
##   word /音标/ 释义   ← 子项目（单词，释义内含词性前缀）
##   take off 起飞      ← 子项目（词组：英文部分含空格即自动识别）
## 接收端按 "# 组名" 切分，逐组走 _parse_word_lines 解析入库

## 导出 Markdown。kind: "words" / "phrases" / ""（两者）；group_filter 非空时只导该组；
## custom_only 为 true 时只导自定义词条（整库互传用，内置 605 词对方本来就有）
func export_groups_md(kind := "", group_filter := "", custom_only := false) -> String:
	var lines := PackedStringArray()
	if kind == "words" or kind == "":
		_append_md_section(lines, words, "day", group_filter, custom_only, true)
	if kind == "phrases" or kind == "":
		_append_md_section(lines, phrases, "sec", group_filter, custom_only, false)
	return "\n".join(lines).strip_edges() + "\n"

func _append_md_section(lines: PackedStringArray, items: Array, key: String,
		group_filter: String, custom_only: bool, is_word: bool) -> void:
	var by_group := {}
	var order := PackedStringArray()
	for it in items:
		if custom_only and not it.get("custom", false):
			continue
		var g := String(it.get(key, "自定义"))
		if group_filter != "" and g != group_filter:
			continue
		if not by_group.has(g):
			by_group[g] = []
			order.append(g)
		by_group[g].append(it)
	for g in order:
		lines.append("# " + g)
		for it in by_group[g]:
			if is_word:
				var l := String(it.get("w", ""))
				if String(it.get("p", "")) != "":
					l += " " + String(it["p"])
				l += " " + String(it.get("m", ""))
				lines.append(l)
			else:
				lines.append(String(it.get("en", "")) + " " + String(it.get("cn", "")))
		lines.append("")

## 互传整库载荷：自定义词条的 Markdown（学习记录不传，接收方保留自己的进度）
func build_transfer_md() -> String:
	return "# 英眼书互传\n\n" + export_groups_md("", "", true)

## 文本是否含「# 组名」分组标题（互传文件 / 手整分组词库 / 内置词库格式）
func is_groups_md(text: String) -> bool:
	for raw in text.split("\n", false):
		var line := String(raw).strip_edges()
		if line.begins_with("# ") and line.length() > 2:
			return true
	return false

## 按 "# 组名" 切分并逐组解析。返回 [{name, res}]；没有标题时全部进新 Day
func parse_groups_md(text: String) -> Array:
	var out: Array = []
	var cur_name := ""
	var cur := PackedStringArray()
	for raw in text.split("\n", false):
		var line := String(raw).strip_edges()
		if line.begins_with("# ") and line.length() > 2:
			if cur_name != "" or not cur.is_empty():
				var gname := cur_name if cur_name != "" else next_day_name()
				out.append({"name": gname, "res": _parse_word_lines("\n".join(cur), gname)})
			cur_name = line.substr(2).strip_edges()
			cur = PackedStringArray()
		else:
			cur.append(raw)
	if cur_name != "" or not cur.is_empty():
		var gname2 := cur_name if cur_name != "" else next_day_name()
		out.append({"name": gname2, "res": _parse_word_lines("\n".join(cur), gname2)})
	# 丢弃「英眼书互传」文件标记组（空组）
	var cleaned: Array = []
	for g in out:
		var r: Dictionary = g["res"]
		if g["name"] == "英眼书互传" and r["words"].is_empty() and r["phrases"].is_empty():
			continue
		cleaned.append(g)
	return cleaned

## 导入互传 Markdown。overwrite_groups=true：同名组的自定义词条先清空再写入（覆盖原词汇）；
## false：只并入自己没有的词条（扩展词汇）。返回 {err, added_w, added_p, groups}
func import_groups_md(text: String, overwrite_groups := false) -> Dictionary:
	backup_libraries("互传导入前自动备份")
	var custom_w: Array = _read_json(CUSTOM_WORDS_PATH, [])
	var custom_p: Array = _read_json(CUSTOM_PHRASES_PATH, [])
	if overwrite_groups:
		# 先扫出组名清单，把同名组从自定义库与内存里一并清掉，再解析（否则查重会把自己的旧词条挡住）
		var names := {}
		for raw in text.split("\n", false):
			var l := String(raw).strip_edges()
			if l.begins_with("# ") and l.length() > 2:
				names[l.substr(2).strip_edges()] = true
		custom_w = custom_w.filter(func(it): return not names.has(String(it.get("day", ""))))
		custom_p = custom_p.filter(func(it): return not names.has(String(it.get("sec", ""))))
		for i in range(words.size() - 1, -1, -1):
			if names.has(String(words[i].get("day", ""))) and words[i].get("custom", false):
				words.remove_at(i)
		for i in range(phrases.size() - 1, -1, -1):
			if names.has(String(phrases[i].get("sec", ""))) and phrases[i].get("custom", false):
				phrases.remove_at(i)
	var groups := parse_groups_md(text)
	if groups.is_empty():
		return {"err": "没有识别到任何词条", "added_w": 0, "added_p": 0, "groups": 0}
	var added_w := 0
	var added_p := 0
	for g in groups:
		var res: Dictionary = g["res"]
		for w in res["words"]:
			custom_w.append(w)
			added_w += 1
		for ph in res["phrases"]:
			custom_p.append(ph)
			added_p += 1
	_write_json(CUSTOM_WORDS_PATH, custom_w)
	_write_json(CUSTOM_PHRASES_PATH, custom_p)
	load_custom()
	rebuild_library()
	return {"err": "", "added_w": added_w, "added_p": added_p, "groups": groups.size()}

## 删除分组：自定义词条物理删除；内置词条靠 deletes 映射在重载时重放
func delete_group(kind: String, group: String) -> String:
	backup_libraries("删除分组前自动备份")
	var dl: Dictionary = settings.get("group_deletes", {"words": {}, "phrases": {}})
	var map: Dictionary = dl.get(kind, {})
	map[group] = true
	# 若组被改名过，把原始名也标上，双保险
	var rn: Dictionary = settings.get("group_renames", {"words": {}, "phrases": {}})
	for origin in rn.get(kind, {}):
		if rn[kind][origin] == group:
			map[origin] = true
	dl[kind] = map
	settings["group_deletes"] = dl
	save_settings()
	var items := words if kind == "words" else phrases
	var key := "day" if kind == "words" else "sec"
	for i in range(items.size() - 1, -1, -1):
		if String(items[i].get(key, "")) == group:
			items.remove_at(i)
	var path := CUSTOM_WORDS_PATH if kind == "words" else CUSTOM_PHRASES_PATH
	var custom_arr: Array = _read_json(path, [])
	var kept: Array = []
	for it in custom_arr:
		if String(it.get(key, "")) != group:
			kept.append(it)
	_write_json(path, kept)
	rebuild_library()
	return ""

## 备份内容（内存版，导出文件与局域网互传共用）
func build_backup_payload() -> Dictionary:
	return {
		"type": "cet4_backup", "version": 1, "exported_at": Time.get_datetime_string_from_system(),
		"progress": progress,
		"custom_words": _read_json(CUSTOM_WORDS_PATH, []),
		"custom_phrases": _read_json(CUSTOM_PHRASES_PATH, []),
		"removed": _read_json(REMOVED_PATH, {"words": [], "phrases": []}),
	}

func export_all() -> String:
	DirAccess.make_dir_recursive_absolute(EXPORT_DIR)
	var fname := "backup_%s.json" % Time.get_datetime_string_from_system().replace(":", "-")
	var payload := build_backup_payload()
	_write_json(EXPORT_DIR + "/" + fname, payload)
	return EXPORT_DIR + "/" + fname

## 导出可读 docx 备份（统计 + 单词库 + 词组库），返回路径；失败返回 ""
func export_docx() -> String:
	DirAccess.make_dir_recursive_absolute(EXPORT_DIR)
	var fname := "英眼书备份_%s.docx" % Time.get_datetime_string_from_system().replace(":", "-")
	var path := EXPORT_DIR + "/" + fname
	var s := stats_summary()
	var lines := PackedStringArray()
	lines.append("英眼书 · 学习备份")
	lines.append("导出时间：" + Time.get_datetime_string_from_system())
	lines.append("统计：单词已会 %d/%d · 词组已会 %d/%d · 连续打卡 %d 天 · 听写对 %d 错 %d" % [
		s.known_words, s.total_words, s.known_phrases, s.total_phrases, s.streak, s.dict_correct, s.dict_wrong])
	lines.append("")
	lines.append("【单词库】共 %d 个" % words.size())
	for w in words:
		lines.append(("%s  %s  %s" % [String(w.w), String(w.get("p", "")), String(w.get("m", ""))]).strip_edges())
	lines.append("")
	lines.append("【词组库】共 %d 条" % phrases.size())
	for ph in phrases:
		lines.append(("%s = %s" % [String(ph.en), String(ph.get("cn", ""))]).strip_edges())
	if _write_docx(path, lines):
		return path
	return ""

## 用 ZIPPacker 写最小 docx（zip 包）
func _write_docx(path: String, lines: PackedStringArray) -> bool:
	var body := ""
	for ln in lines:
		body += '<w:p><w:r><w:t xml:space="preserve">%s</w:t></w:r></w:p>\n' % ln.xml_escape()
	var document := '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
	document += '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>'
	document += body + "</w:body></w:document>"
	var content_types := '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
	content_types += '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
	content_types += '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
	content_types += '<Default Extension="xml" ContentType="application/xml"/>'
	content_types += '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
	content_types += "</Types>"
	var rels := '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
	rels += '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
	rels += '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
	rels += "</Relationships>"
	var zp := ZIPPacker.new()
	if zp.open(path) != OK:
		return false
	for part in [["[Content_Types].xml", content_types], ["_rels/.rels", rels], ["word/document.xml", document]]:
		zp.start_file(part[0])
		zp.write_file(String(part[1]).to_utf8_buffer())
		zp.close_file()
	zp.close()
	return true

func export_starred() -> String:
	DirAccess.make_dir_recursive_absolute(EXPORT_DIR)
	var fname := "starred_%s.json" % Time.get_datetime_string_from_system().replace(":", "-")
	var sw := []
	for w in starred_items("words"):
		sw.append({"w": w.w, "p": w.get("p", ""), "m": w.get("m", ""), "day": w.get("day", "")})
	var sp := []
	for p in starred_items("phrases"):
		sp.append({"sec": p.sec, "en": p.en, "cn": p.get("cn", "")})
	_write_json(EXPORT_DIR + "/" + fname, {"type": "cet4_starred", "words": sw, "phrases": sp})
	return EXPORT_DIR + "/" + fname

func import_backup(json_text: String) -> String:
	var d = JSON.parse_string(json_text)
	if not (d is Dictionary):
		return "JSON 解析失败"
	if d.get("type") == "cet4_backup":
		backup_libraries("导入前自动备份")
		if d.has("progress"): progress = d["progress"]
		if d.has("custom_words"): _write_json(CUSTOM_WORDS_PATH, d["custom_words"])
		if d.has("custom_phrases"): _write_json(CUSTOM_PHRASES_PATH, d["custom_phrases"])
		if d.has("removed"): _write_json(REMOVED_PATH, d["removed"])
		load_builtin()
		load_custom()
		load_progress()
		rebuild_library()
		save_progress()
		return ""
	if d.get("type") == "cet4_wordlib" or d.has("words") or d.has("phrases"):
		return import_wordlib(json_text)
	return "无法识别的备份格式"

## 合并模式导入（互传「扩展词汇」选项）：只把对方自定义词库里我没有的词条并进来，
## 学习进度与移除名单保持本机不动。返回 "" 成功，否则错误文案
func merge_backup(json_text: String) -> String:
	var d = JSON.parse_string(json_text)
	if not (d is Dictionary) or d.get("type") != "cet4_backup":
		return "无法识别的备份格式"
	backup_libraries("合并前自动备份")
	var cur_w: Array = _read_json(CUSTOM_WORDS_PATH, [])
	var seen_w := {}
	for w in cur_w:
		seen_w[word_id(w)] = true
	for w in d.get("custom_words", []):
		var id := word_id(w)
		if id != "" and not seen_w.has(id):
			cur_w.append(w)
			seen_w[id] = true
	var cur_p: Array = _read_json(CUSTOM_PHRASES_PATH, [])
	var seen_p := {}
	for p in cur_p:
		seen_p[String(p.get("en", "")).to_lower().strip_edges()] = true
	for p in d.get("custom_phrases", []):
		var pid: String = String(p.get("en", "")).to_lower().strip_edges()
		if pid != "" and not seen_p.has(pid):
			cur_p.append(p)
			seen_p[pid] = true
	_write_json(CUSTOM_WORDS_PATH, cur_w)
	_write_json(CUSTOM_PHRASES_PATH, cur_p)
	load_custom()
	rebuild_library()
	return ""

## 词库热更新：接受 {type:cet4_wordlib, words:[...], phrases:[...]} 或裸 {words/phrases}
func import_wordlib(json_text: String) -> String:
	var d = JSON.parse_string(json_text)
	if not (d is Dictionary):
		return "JSON 解析失败"
	var new_words: Array = d.get("words", [])
	var new_phrases: Array = d.get("phrases", [])
	if new_words.is_empty() and new_phrases.is_empty():
		return "文件里没有 words / phrases 数据"
	backup_libraries("词库导入前自动备份")
	var cw: Array = _read_json(CUSTOM_WORDS_PATH, [])
	var cp: Array = _read_json(CUSTOM_PHRASES_PATH, [])
	var added_w := 0
	var added_p := 0
	for w in new_words:
		if not w.has("w") or not w.has("m"): continue
		if not w.has("day"): w["day"] = "自定义"
		var id := word_id(w)
		var found := false
		for i in cw.size():
			if word_id(cw[i]) == id:
				cw[i] = w; found = true; break
		if not found:
			cw.append(w)
		added_w += 1
	for p in new_phrases:
		if not p.has("en"): continue
		if not p.has("cn"): p["cn"] = ""
		if not p.has("sec"): p["sec"] = "自定义"
		var id := phrase_id(p)
		var found := false
		for i in cp.size():
			if phrase_id(cp[i]) == id:
				cp[i] = p; found = true; break
		if not found:
			cp.append(p)
		added_p += 1
	_write_json(CUSTOM_WORDS_PATH, cw)
	_write_json(CUSTOM_PHRASES_PATH, cp)
	load_builtin()
	load_custom()
	rebuild_library()
	return "导入完成：单词 %d 条，词组 %d 条（同名单词已覆盖）" % [added_w, added_p]

## AI 改词库：ops = {"add_words":[], "add_phrases":[], "remove_words":[], "remove_phrases":[]}
func apply_ai_library_edit(ops: Dictionary) -> String:
	backup_libraries("AI 修改前自动备份")
	var cw: Array = _read_json(CUSTOM_WORDS_PATH, [])
	var cp: Array = _read_json(CUSTOM_PHRASES_PATH, [])
	var removed: Dictionary = _read_json(REMOVED_PATH, {"words": [], "phrases": []})
	var log := []
	for w in ops.get("add_words", []):
		if not w.has("w") or not w.has("m"): continue
		if not w.has("p"): w["p"] = ""
		if not w.has("syn"): w["syn"] = []
		if not w.has("sim"): w["sim"] = []
		if not w.has("day"): w["day"] = "自定义"
		var id := word_id(w)
		var found := false
		for i in cw.size():
			if word_id(cw[i]) == id:
				cw[i] = w; found = true; break
		if not found: cw.append(w)
		log.append("+单词 " + String(w.w))
	for p in ops.get("add_phrases", []):
		if not p.has("en"): continue
		if not p.has("cn"): p["cn"] = ""
		if not p.has("sec"): p["sec"] = "自定义"
		var id := phrase_id(p)
		var found := false
		for i in cp.size():
			if phrase_id(cp[i]) == id:
				cp[i] = p; found = true; break
		if not found: cp.append(p)
		log.append("+词组 " + String(p.en))
	for id in ops.get("remove_words", []):
		var sid := String(id).to_lower().strip_edges()
		if sid == "": continue
		var was_custom := false
		cw = cw.filter(func(w):
			if word_id(w) == sid:
				was_custom = true
				return false
			return true)
		if not was_custom and not removed["words"].has(sid):
			removed["words"].append(sid)
		log.append("-单词 " + sid)
	for key in ops.get("remove_phrases", []):
		var sid := String(key).strip_edges()
		if sid == "": continue
		var removed_any := false
		cp = cp.filter(func(p):
			if String(p.en).to_lower().strip_edges() == sid.to_lower():
				removed_any = true
				return false
			return true)
		if not removed_any:
			# 内置词组：按 en 记录删除（所有 sec 同名都删）
			for p in phrases:
				var pid := phrase_id(p)
				if String(p.en).to_lower().strip_edges() == sid.to_lower() and not removed["phrases"].has(pid):
					removed["phrases"].append(pid)
		log.append("-词组 " + sid)
	_write_json(CUSTOM_WORDS_PATH, cw)
	_write_json(CUSTOM_PHRASES_PATH, cp)
	_write_json(REMOVED_PATH, removed)
	load_builtin()
	load_custom()
	rebuild_library()
	return "已应用 %d 项修改：\n%s" % [log.size(), "\n".join(log)]

func backup_libraries(reason: String) -> String:
	DirAccess.make_dir_recursive_absolute(BACKUP_DIR)
	var fname := "%s/wordlib_%s.json" % [BACKUP_DIR, Time.get_datetime_string_from_system().replace(":", "-")]
	_write_json(fname, {
		"reason": reason,
		"time": Time.get_datetime_string_from_system(),
		"custom_words": _read_json(CUSTOM_WORDS_PATH, []),
		"custom_phrases": _read_json(CUSTOM_PHRASES_PATH, []),
		"removed": _read_json(REMOVED_PATH, {"words": [], "phrases": []}),
	})
	# 只保留最近 5 份
	var files := DirAccess.get_files_at(BACKUP_DIR)
	files.sort()
	while files.size() > 5:
		DirAccess.remove_absolute(BACKUP_DIR + "/" + files[0])
		files.remove_at(0)
	return fname

func list_backups() -> PackedStringArray:
	var files := Array(DirAccess.get_files_at(BACKUP_DIR))
	files.sort()
	files.reverse()
	return PackedStringArray(files)

func rollback_backup(fname: String) -> String:
	var d = _read_json(BACKUP_DIR + "/" + fname, {})
	if d.is_empty(): return "备份文件读取失败"
	_write_json(CUSTOM_WORDS_PATH, d.get("custom_words", []))
	_write_json(CUSTOM_PHRASES_PATH, d.get("custom_phrases", []))
	_write_json(REMOVED_PATH, d.get("removed", {"words": [], "phrases": []}))
	load_builtin()
	load_custom()
	rebuild_library()
	return "已回滚到 " + String(d.get("time", fname))

## 备份显示名：用户改过名用 label，否则用时间文件名
func get_backup_label(fname: String) -> String:
	var d = _read_json(BACKUP_DIR + "/" + fname, {})
	var lab := String(d.get("label", "")).strip_edges()
	if lab != "":
		return lab
	return fname.trim_suffix(".json")

## 重命名备份：只改 JSON 里的 label 字段，文件名不动（排序键保持时间序）
func rename_backup(fname: String, label: String) -> String:
	label = label.strip_edges()
	var d = _read_json(BACKUP_DIR + "/" + fname, {})
	if d.is_empty():
		return "备份文件读取失败"
	if label == "":
		d.erase("label")
	else:
		d["label"] = label.left(40)
	_write_json(BACKUP_DIR + "/" + fname, d)
	return ""

func delete_backup(fname: String) -> String:
	if not FileAccess.file_exists(BACKUP_DIR + "/" + fname):
		return "备份不存在"
	DirAccess.remove_absolute(BACKUP_DIR + "/" + fname)
	return ""

## 批量删除备份，返回删除份数
func delete_backups(fnames: PackedStringArray) -> int:
	var n := 0
	for f in fnames:
		if FileAccess.file_exists(BACKUP_DIR + "/" + f):
			DirAccess.remove_absolute(BACKUP_DIR + "/" + f)
			n += 1
	return n

func factory_reset_library() -> void:
	_write_json(CUSTOM_WORDS_PATH, [])
	_write_json(CUSTOM_PHRASES_PATH, [])
	_write_json(REMOVED_PATH, {"words": [], "phrases": []})
	load_builtin()
	load_custom()
	rebuild_library()

## 清空整个词库（内置+自定义全部移除，学习记录保留）：给想背自己单词表的用户
func wipe_library() -> String:
	backup_libraries("清空词库前自动备份")
	var removed := {"words": [], "phrases": []}
	for w in words:
		removed["words"].append(word_id(w))
	for p in phrases:
		removed["phrases"].append(phrase_id(p))
	_write_json(CUSTOM_WORDS_PATH, [])
	_write_json(CUSTOM_PHRASES_PATH, [])
	_write_json(REMOVED_PATH, removed)
	load_builtin()
	load_custom()
	rebuild_library()
	return "已清空词库（单词+词组）。可导入自己的单词表；学习记录保留，备份可回滚"

# ---------------- 聊天会话 ----------------
func load_sessions() -> void:
	sessions = _read_json(SESSIONS_PATH, [])

func save_sessions() -> void:
	_write_json(SESSIONS_PATH, sessions)

# ---------------- AI 长期记忆 ----------------
const MEMORY_MAX := 200   # 记忆上限，超出淘汰最旧

func load_memory() -> void:
	var m = _read_json(MEMORY_PATH, [])
	ai_memory = m if m is Array else []

func save_memory() -> void:
	_write_json(MEMORY_PATH, ai_memory)

## 新增记忆（去重、每条限 200 字），返回实际新增条数
func memory_add(items: Array) -> int:
	var n := 0
	for it in items:
		var s := String(it).strip_edges()
		if s == "" or ai_memory.has(s):
			continue
		ai_memory.append(s.left(200))
		n += 1
	while ai_memory.size() > MEMORY_MAX:
		ai_memory.pop_front()
	if n > 0:
		save_memory()
	return n

## 按原文移除记忆，返回移除条数
func memory_remove(items: Array) -> int:
	var n := 0
	for it in items:
		var s := String(it).strip_edges()
		if s != "" and ai_memory.has(s):
			ai_memory.erase(s)
			n += 1
	if n > 0:
		save_memory()
	return n

func memory_clear() -> void:
	ai_memory.clear()
	save_memory()

func new_session(title: String) -> Dictionary:
	var s := {"id": str(Time.get_unix_time_from_system()) + str(randi() % 1000),
		"title": title, "created": Time.get_datetime_string_from_system(), "messages": []}
	sessions.push_front(s)
	save_sessions()
	return s

func delete_session(id: String) -> void:
	sessions = sessions.filter(func(s): return s.id != id)
	save_sessions()

func get_session(id: String) -> Dictionary:
	for s in sessions:
		if s.id == id: return s
	return {}

# ---------------- 工具 ----------------
static func _read_json(path: String, fallback):
	if not FileAccess.file_exists(path):
		return fallback
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if d == null:
		return fallback
	return d

static func _write_json(path: String, data) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "  "))
		f.close()
