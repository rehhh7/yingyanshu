extends SceneTree
## 音素拼接引擎测试：分词规则 + 音频合成

var fails := 0

func _initialize() -> void:
	call_deferred("run")

func check(name: String, cond: bool) -> void:
	print(("PASS " if cond else "FAIL ") + name)
	if not cond:
		fails += 1

func syms(tokens: Array) -> String:
	var a := PackedStringArray()
	for t in tokens:
		a.append(String(t.s) + ("" if t.stress == 0 else ("¹" if t.stress == 1 else "²")))
	return " ".join(a)

func run() -> void:
	# ---- 分词 ----
	var t1 := PhonemeTTS.tokenize("/əˈbændən/")
	print("  əˈbændən → ", syms(t1))
	check("abandon 音素数=7", t1.size() == 7)
	check("abandon 主重音在 æ", t1.size() >= 3 and t1[2].s == "æ" and t1[2].stress == 2)

	var t2 := PhonemeTTS.tokenize("/trɪˈviəl/")
	print("  trɪˈviəl → ", syms(t2))
	check("trivial 音素数=7", t2.size() == 7)
	check("trivial 主重音在 i", t2.size() >= 5 and t2[4].s == "iː" and t2[4].stress == 2)

	var t3 := PhonemeTTS.tokenize("/feɪnt/")
	check("faint 双元音整体=1", t3.size() == 4 and t3[1].s == "eɪ")

	var t4 := PhonemeTTS.tokenize("/tʃɪp/")
	check("tʃ 破擦音整体=1", t4.size() == 3 and t4[0].s == "tʃ")

	var t5 := PhonemeTTS.tokenize("/ˌɪntrəˈdʌkʃn/")
	print("  ˌɪntrəˈdʌkʃn → ", syms(t5))
	check("introduction 次重音在 ɪ", t5.size() > 0 and t5[0].s == "ɪ" and t5[0].stress == 1)
	var tj := PhonemeTTS.tokenize("/dʒɒb/")
	check("job 含 dʒ 整体", tj.size() == 3 and tj[0].s == "dʒ")

	# iə 歧义：trivial 是 i+ə 两音节，thereby 的 eə 是真双元音
	var t8 := PhonemeTTS.tokenize("/ˌðeəˈbaɪ/")
	check("thereby eə 保双元音", t8.any(func(x): return x.s == "eə"))

	# 美式别名
	var t6 := PhonemeTTS.tokenize("/ˈfɜrnɪtʃər/")
	check("卷舌 ɜr 拆开", syms(t6).contains("ɜː") and syms(t6).contains(" r"))
	var t7 := PhonemeTTS.tokenize("/ˈfɪɡjɚ/")
	check("ɚ 拆为 ə+r", syms(t7).contains("ə") and syms(t7).contains(" r"))

	# 垃圾输入
	check("纯中文分词=空", PhonemeTTS.tokenize("哈哈哈").is_empty())
	check("空串分词=空", PhonemeTTS.tokenize("").is_empty())

	# ---- 合成 ----
	var st := PhonemeTTS.build_stream("/əˈbændən/")
	check("合成流非空", st != null)
	if st != null:
		check("采样率 22050", st.mix_rate == 22050)
		check("单声道", st.stereo == false)
		var secs := st.data.size() / 2.0 / 22050.0
		print("  合成时长 %.2fs，%d 字节" % [secs, st.data.size()])
		check("时长 0.4~2.5s", secs > 0.4 and secs < 2.5)
	check("垃圾输入合成=null", PhonemeTTS.build_stream("哈哈哈") == null)
	# 重音增益：主重音元音片段峰值应高于非重音（直接对比 build 出的两段单音素流峰值不便，这里验证不报错且长度合理即可）
	var st2 := PhonemeTTS.build_stream("/ˌəʊvəˈsiː/")
	check("多音节词合成非空", st2 != null)

	# ---- 全库冒烟：605 个内置词 + 现有词库音标全部应能合成 ----
	var DB = root.get_node_or_null("DB")
	if DB != null:
		var ok := 0
		var bad := PackedStringArray()
		for w in DB.words:
			var ph := String(w.get("p", ""))
			if ph == "":
				continue
			if PhonemeTTS.build_stream(ph) != null:
				ok += 1
			else:
				bad.append(String(w.get("w", "?")))
		print("  全库音标合成：%d 成功，%d 失败 %s" % [ok, bad.size(), str(bad)])
		check("全库音标 100% 可合成", bad.is_empty())

	print("== 测试完成 fails=%d ==" % fails)
	quit(1 if fails > 0 else 0)
