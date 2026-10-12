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

const VERSION := "0.9.14"   # 应用版本号（设置页/AI上下文/更新弹窗统一读这里）

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

# ---------------- 词库 ----------------
func load_builtin() -> void:
	words.clear()
	phrases.clear()
	if FileAccess.file_exists("res://data/words.md"):
		_load_builtin_md()   # Markdown 源文件（可直接编辑更新词库）
	else:
		_load_builtin_json() # 兼容旧版 JSON
	_apply_group_renames()

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
## 读取文本类文件（txt/md/json/csv/docx），docx 自动解包提取纯文本
## 注意：安卓文件选择器返回 content:// URI（无扩展名、ZIPReader 打不开），
## 所以一律先读字节（FileAccess 支持 URI），再按 ZIP 魔数 "PK" 判断 docx
func extract_text_file(path: String) -> String:
	var data := FileAccess.get_file_as_bytes(path)
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
## 返回 {words:[{w,p,m,day,syn,sim}], phrases:[{en,cn,sec}], unknown:[String], dup:[String]}
func parse_import_text(text: String) -> Dictionary:
	var out := {"words": [], "phrases": [], "unknown": [], "dup": []}
	var day := next_day_name()
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
	var re_wph := RegEx.new()   # 单词和音标连写：abandon/əˈbændən/
	re_wph.compile("^([A-Za-z][A-Za-z\\-']*)(/[^/]+/)$")
	for raw in text.split("\n", false):
		var line := String(raw).replace("\t", " ").replace("　", " ").strip_edges()   # 制表符/全角空格当空格，避免整行误判
		if line == "" or line.begins_with("#") or line.begins_with("//"):
			continue
		line = re_num.sub(line, "", true)
		line = re_bullet.sub(line, "", true).strip_edges()
		if line == "" or re_head.search(line) != null:
			continue   # 跳过 "Day 5" 之类的标题行
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
		# 英文部分尾部的分隔标点清理掉（= ＝ — – ~ ～ 、 · 等手写常见分隔符）
		while en_part.length() > 0 and [":", "：", "-", "—", "–", ",", "，", "|", "；", ";", "=", "＝", "~", "～", "、", "·"].has(en_part.right(1)):
			en_part = en_part.left(en_part.length() - 1).strip_edges()
		if en_part == "":
			continue
		var tokens := en_part.split(" ", false)
		if tokens.is_empty() or (re_word.search(tokens[0]) == null and re_wph.search(tokens[0]) == null):
			out["unknown"].append(line)   # 首段不是英文单词开头（音标/词性孤立行等）
			continue
		var is_word := tokens.size() == 1
		var phon := ""
		var pos_prefix := ""
		var m0 := re_wph.search(tokens[0])
		if m0 != null:
			# 单词和音标连写："abandon/əˈbændən/ vt. 放弃"
			is_word = true
			phon = m0.get_string(2)
			tokens[0] = m0.get_string(1)
			if tokens.size() >= 2 and _is_pos_tag(tokens[1]):
				pos_prefix = tokens[1] + " "
		elif not is_word and tokens.size() >= 2 and (tokens[1].begins_with("/") or (tokens[1].begins_with("[") and tokens[1].ends_with("]"))):
			# 形如 "abandon /əˈbændən/ vt. 放弃" 或 "abandon [əˈbændən] vt. 放弃"：第二段是音标
			is_word = true
			phon = tokens[1]
			if tokens.size() >= 3 and _is_pos_tag(tokens[2]):
				pos_prefix = tokens[2] + " "
			elif tokens.size() >= 3:
				is_word = false   # 音标后面还有别的内容，不像词条
		elif not is_word and tokens.size() == 2 and _is_pos_tag(tokens[1]):
			# 形如 "abandon vt. 放弃"：第二段是词性
			is_word = true
			pos_prefix = tokens[1] + " "
		if is_word:
			var w := String(tokens[0])
			var id := w.to_lower()
			if existing_w.has(id):
				if not out["dup"].has(w):
					out["dup"].append(w)
				continue
			if cn_part == "":
				out["unknown"].append(w + "（无释义，请核对）")
				continue
			out["words"].append({"w": w, "p": phon, "m": pos_prefix + cn_part, "day": day, "syn": [], "sim": []})
			existing_w[id] = true
		else:
			var pid := en_part.to_lower()
			if existing_p.has(pid):
				if not out["dup"].has(en_part):
					out["dup"].append(en_part)
				continue
			if cn_part == "":
				out["unknown"].append(en_part + "（无释义，请核对）")
				continue
			out["phrases"].append({"en": en_part, "cn": cn_part, "sec": day})
			existing_p[pid] = true
	return out

func export_all() -> String:
	DirAccess.make_dir_recursive_absolute(EXPORT_DIR)
	var fname := "backup_%s.json" % Time.get_datetime_string_from_system().replace(":", "-")
	var payload := {
		"type": "cet4_backup", "version": 1, "exported_at": Time.get_datetime_string_from_system(),
		"progress": progress,
		"custom_words": _read_json(CUSTOM_WORDS_PATH, []),
		"custom_phrases": _read_json(CUSTOM_PHRASES_PATH, []),
		"removed": _read_json(REMOVED_PATH, {"words": [], "phrases": []}),
	}
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
