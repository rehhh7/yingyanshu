class_name PhonemeTTS
extends RefCounted
## 音素拼接引擎：按 IPA 音标现场拼接 44 个内置音素片段（PCM，22050Hz 单声道）
## 完全离线、不依赖系统 TTS；音质带合成感但清晰可辨
## 素材管线见开发记录「音素包」：SAPI SSML(IPA) → numpy 切片 → PCM 导入
## 文件名规则：音素逐字符码位十六进制下划线连接（如 iː → 0069_02D0.wav）

const SR := 22050
const XFADE := SR * 12 / 1000   ## 12ms 交叉淡化，消除拼接咔哒声

## 全部内置音素（与 assets/audio/phonemes 一一对应）
const SYMBOLS := [
	"iː", "ɪ", "e", "æ", "ɜː", "ə", "ʌ", "ɑː", "ɒ", "ɔː", "ʊ", "uː",
	"eɪ", "aɪ", "ɔɪ", "əʊ", "aʊ", "ɪə", "eə", "ʊə",
	"p", "b", "t", "d", "k", "g", "f", "v", "θ", "ð", "s", "z",
	"ʃ", "ʒ", "h", "tʃ", "dʒ", "m", "n", "ŋ", "l", "r", "w", "j",
]
const VOWELS := [
	"iː", "ɪ", "e", "æ", "ɜː", "ə", "ʌ", "ɑː", "ɒ", "ɔː", "ʊ", "uː",
	"eɪ", "aɪ", "ɔɪ", "əʊ", "aʊ", "ɪə", "eə", "ʊə",
]

static var _cache := {}                 ## 音素 → 解码后的采样（PackedInt32Array）
static var _player: AudioStreamPlayer = null

static func _clip_id(sym: String) -> String:
	var parts := PackedStringArray()
	for i in sym.length():
		parts.append("%04X" % sym.unicode_at(i))
	return "_".join(parts)

static func _load_samples(sym: String) -> PackedInt32Array:
	if _cache.has(sym):
		return _cache[sym]
	var out := PackedInt32Array()
	var path := "res://assets/audio/phonemes/%s.wav" % _clip_id(sym)
	if ResourceLoader.exists(path):
		var st: AudioStreamWAV = load(path)
		var raw := st.data
		out.resize(raw.size() / 2)
		for i in out.size():
			out[i] = raw.decode_s16(i * 2)
	_cache[sym] = out
	return out

## 分词：返回 [{s: 音素, stress: 0/1/2}]；stress 标在紧邻的下一个音素上（2=ˈ主重音 1=ˌ次重音）
## 识别不出任何音素时返回空数组
static func tokenize(ipa: String) -> Array:
	var t := ipa.strip_edges()
	if t.begins_with("/") or t.begins_with("["):
		t = t.substr(1)
	if t.ends_with("/") or t.ends_with("]"):
		t = t.left(t.length() - 1)
	# 别名：美式卷舌元音拆开；半长音符忽略；孤写 ɜ（漏标长音）归一为 ɜː
	# 弱读 i/u（happy-tensing，如 /ˈtrɪviəl/ /ˈɪnfluəns/）归一为 iː/uː；孤写 o 归一为 əʊ
	#（对已带 ː 的会叠出第二个 ː，分词时最长匹配后多余 ː 落入跳过表，无害）
	t = t.replace("ɝ", "ɜːr").replace("ɚ", "ər").replace("ˑ", "").replace("ɜ", "ɜː")
	t = t.replace("i", "iː").replace("u", "uː").replace("o", "əʊ")
	var out: Array = []
	var pending := 0
	var i := 0
	while i < t.length():
		var c := t[i]
		if c == "ˈ":
			pending = 2
			i += 1
			continue
		if c == "ˌ":
			pending = 1
			i += 1
			continue
		if [" ", "·", ".", "-", "‐", "‑", "'", "’", "ː", "(", ")", ",", ";", "ˈ", "ˌ"].has(c):
			i += 1   # 分隔符与孤立长音符
			continue
		var matched := ""
		for L in [3, 2, 1]:   # 最长匹配
			var cand := t.substr(i, L)
			if not SYMBOLS.has(cand):
				continue
			# 数据实证规则：iə 只在 r 前或词尾才是真双元音（/ˈtrɪviəl/ 是 i+ə 两个音节，
			# /hɪə/ 才是 ɪə）；eə/ʊə 无此冲突（ðeəˈbaɪ 的 eə 是真双元音）
			if cand == "iə":
				var nxt := t.substr(i + L, 1)
				if nxt != "r" and i + L < t.length():
					continue
			matched = cand
			break
		if matched == "":
			i += 1   # 未识别字符：跳过，不中断整词
			continue
		out.append({"s": matched, "stress": pending if VOWELS.has(matched) else 0})
		# 重音标在音节核（元音）上：辅音不消费 pending，顺延给后面的元音
		if VOWELS.has(matched):
			pending = 0
		i += matched.length()
	return out

## 拼成完整音频；无元音或总长不足 100ms 视为失败（交给下一级兜底）
static func build_stream(ipa: String) -> AudioStreamWAV:
	var tokens := tokenize(ipa)
	if tokens.is_empty():
		return null
	var pcm := PackedInt32Array()
	var vowel_seen := false
	for tk in tokens:
		var samples := _load_samples(String(tk.s))
		if samples.is_empty():
			continue
		var gain := 1.0
		if VOWELS.has(tk.s):
			vowel_seen = true
			if tk.stress == 2:
				gain = 1.25
			elif tk.stress == 1:
				gain = 1.12
		_append(pcm, samples, gain)
	if not vowel_seen or pcm.size() < SR / 10:
		return null
	var bytes := PackedByteArray()
	bytes.resize(pcm.size() * 2)
	for i in pcm.size():
		bytes.encode_s16(i * 2, clampi(pcm[i], -32768, 32767))
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = SR
	st.stereo = false
	st.data = bytes
	return st

## 把一段采样拼进 pcm：尾部 12ms 交叉淡化，gain 作用于新片段
static func _append(pcm: PackedInt32Array, samples: PackedInt32Array, gain: float) -> void:
	if pcm.is_empty():
		for v in samples:
			pcm.append(int(v * gain))
		return
	var xf: int = mini(XFADE, mini(pcm.size(), samples.size()))
	var base := pcm.size() - xf
	for k in xf:
		var a := float(pcm[base + k]) * (1.0 - float(k) / xf)
		var b := float(samples[k]) * gain * (float(k) / xf)
		pcm[base + k] = int(a + b)
	for k in range(xf, samples.size()):
		pcm.append(int(samples[k] * gain))

## 直接按音标发音；无法合成（无音素命中/无元音）返回 false 让调用方降级
static func speak(ipa: String) -> bool:
	var st := build_stream(ipa)
	if st == null:
		return false
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return false
	if _player == null or not is_instance_valid(_player):
		_player = AudioStreamPlayer.new()
		_player.name = "PhonemePlayer"
		tree.root.add_child(_player)
	_player.stream = st
	_player.play()
	return true
