class_name TTS
extends RefCounted
## 文字转语音：离线语音包（APK 内置 605 词真人录音）优先，系统 TTS 兜底

static var _player: AudioStreamPlayer = null

## 单词发音三级兜底：① 内置语音包（605 词真人录音）② 系统 TTS（有英文语音时）
## ③ 无系统语音且开启「联网发音」时拉有道真人发音（拉取失败后退回系统 TTS）
## british 暂保留给系统 TTS 的口音偏好（语音包目前只有美式）
static func play_word(word: String, british := false) -> void:
	var id := word.to_lower().strip_edges()
	var path := "res://assets/audio/words/%s.ogg" % id
	if id != "" and not ResourceLoader.exists(path):
		path = "res://assets/audio/words/%s.wav" % id  # 兼容旧包
	if id != "" and ResourceLoader.exists(path):
		var tree := Engine.get_main_loop() as SceneTree
		if tree == null:
			return
		if _player == null or not is_instance_valid(_player):
			_player = AudioStreamPlayer.new()
			_player.name = "WordPlayer"
			tree.root.add_child(_player)
		_player.stream = load(path)
		_player.play()
		return
	if has_lang_voice():
		speak(word, british)
		return
	# 有道在线发音只覆盖英文词典：非英语没有可靠免费接口，直接回退系统 TTS
	if id != "" and _lang_prefix() == "en" and bool(DB.settings.get("online_audio", true)):
		OnlineAudio.play(id, func(): speak(word, british))
		return
	speak(word, british)

## 系统可用的英文语音列表（每项含 id / locale / name）
static func english_voices() -> Array:
	var out: Array = []
	for v in DisplayServer.tts_get_voices():
		var loc := String(v.get("locale", "")).to_lower().replace("-", "_")
		if loc.begins_with("en"):
			out.append(v)
	return out

## 系统 TTS 是否能读英文（导入新词的兜底依赖它；内置词走录音不受影响）
static func has_english_voice() -> bool:
	return not english_voices().is_empty()

## 当前学习语言 → TTS 语音地区前缀（自定义语言名兜底取前两位小写）
static func _lang_prefix() -> String:
	var lang := DB.study_lang()
	var map := {"英语": "en", "日语": "ja", "韩语": "ko", "法语": "fr", "德语": "de", "西班牙语": "es",
		"俄语": "ru", "意大利语": "it", "葡萄牙语": "pt"}
	if map.has(lang):
		return String(map[lang])
	var t := lang.to_lower().strip_edges()
	return t.left(2) if t.length() >= 2 else "en"

## 系统里有没有当前学习语言的语音
static func has_lang_voice() -> bool:
	var pre := _lang_prefix()
	for v in DisplayServer.tts_get_voices():
		if String(v.get("locale", "")).to_lower().replace("-", "_").begins_with(pre):
			return true
	return false

static func _pick_voice(british: bool) -> String:
	var pre := _lang_prefix()
	var want := "en_gb" if british else "en_us"
	var voices := DisplayServer.tts_get_voices()
	var fallback := ""
	for v in voices:
		var loc := String(v.get("locale", "")).to_lower().replace("-", "_")
		var id := String(v.get("id", ""))
		if not loc.begins_with(pre):
			continue
		if fallback == "":
			fallback = id
		if loc == want:
			return id
	# 精确匹配不到就模糊匹配（英语区分英美口音，其他语言同前缀即可）
	for v in voices:
		var loc := String(v.get("locale", "")).to_lower().replace("-", "_")
		var id := String(v.get("id", ""))
		if not loc.begins_with(pre):
			continue
		if british and ("gb" in loc or "uk" in loc):
			return id
		if not british and "us" in loc:
			return id
	return fallback

static func speak(text: String, british := false) -> void:
	var rate := float(DB.settings.get("tts_rate", 1.0))
	var voice := _pick_voice(british)
	if OS.has_feature("android"):
		DisplayServer.tts_stop()
	DisplayServer.tts_speak(text, voice, 50, 1.0, rate)

static func stop() -> void:
	DisplayServer.tts_stop()
