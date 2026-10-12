class_name TTS
extends RefCounted
## 文字转语音：离线语音包（APK 内置 605 词真人录音）优先，系统 TTS 兜底

static var _player: AudioStreamPlayer = null

## 单词发音三级兜底：① 内置语音包（605 词真人录音）② 音素拼接（任意带音标的词）③ 系统 TTS
## british 暂保留给系统 TTS 的口音偏好（语音包目前只有美式）
static func play_word(word: String, phonetic := "", british := false) -> void:
	var id := word.to_lower().strip_edges()
	var path := "res://assets/audio/words/%s.wav" % id
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
	if phonetic.strip_edges() != "" and PhonemeTTS.speak(phonetic):
		return
	speak(word, british)

static func _pick_voice(british: bool) -> String:
	var want := "en_gb" if british else "en_us"
	var voices := DisplayServer.tts_get_voices()
	var fallback := ""
	for v in voices:
		var loc := String(v.get("locale", "")).to_lower().replace("-", "_")
		var id := String(v.get("id", ""))
		if not loc.begins_with("en"):
			continue
		if fallback == "":
			fallback = id
		if loc == want:
			return id
	# 精确匹配不到就模糊匹配
	for v in voices:
		var loc := String(v.get("locale", "")).to_lower().replace("-", "_")
		var id := String(v.get("id", ""))
		if not loc.begins_with("en"):
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
