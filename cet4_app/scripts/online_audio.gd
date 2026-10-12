class_name OnlineAudio
extends RefCounted
## 在线发音兜底：本机没有系统英文语音时，从有道词典拉真人发音 mp3（磁盘缓存，第二次起离线可播）
## 只在「设置 → 发音 → 无系统语音时联网发音」开启且本地录音、系统 TTS 都不可用时触发

const CACHE_DIR := "user://audio_cache/"

static var _player: AudioStreamPlayer = null
static var _busy := false

static func _cache_path(word: String) -> String:
	return CACHE_DIR + word.uri_encode() + ".mp3"

## 异步拉取并播放；失败时回调 on_fail（调用方一般退回系统 TTS）
static func play(word: String, on_fail := Callable()) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or _busy:
		if on_fail.is_valid():
			on_fail.call()
		return
	var path := _cache_path(word)
	if FileAccess.file_exists(path):
		_play_bytes(FileAccess.get_file_as_bytes(path), tree)
		return
	_busy = true
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	var req := HTTPRequest.new()
	req.timeout = 8.0
	tree.root.add_child(req)
	req.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray):
		req.queue_free()
		_busy = false
		if result == HTTPRequest.RESULT_SUCCESS and code == 200 and body.size() > 500:
			var f := FileAccess.open(path, FileAccess.WRITE)
			if f != null:
				f.store_buffer(body)
				f.close()
			_play_bytes(body, tree)
		elif on_fail.is_valid():
			on_fail.call())
	var err := req.request("https://dict.youdao.com/dictvoice?audio=" + word.uri_encode() + "&type=1")
	if err != OK:
		req.queue_free()
		_busy = false
		if on_fail.is_valid():
			on_fail.call()

static func _play_bytes(bytes: PackedByteArray, tree: SceneTree) -> void:
	if bytes.is_empty():
		return
	var s := AudioStreamMP3.new()
	s.data = bytes
	if _player == null or not is_instance_valid(_player):
		_player = AudioStreamPlayer.new()
		_player.name = "OnlineAudioPlayer"
		tree.root.add_child(_player)
	_player.stream = s
	_player.play()
