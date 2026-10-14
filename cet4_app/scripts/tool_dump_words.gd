extends SceneTree
## 构建工具：导出全词库 id + 原文列表（供 Windows SAPI 生成离线语音包）

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var DB = root.get_node_or_null("DB")
	if DB == null:
		print("FAIL autoload DB 未加载")
		quit(1)
		return
	var out := "user://_tools/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	print("TSV 输出目录：" + ProjectSettings.globalize_path(out))
	var f := FileAccess.open(out + "word_list.tsv", FileAccess.WRITE)
	if f == null:
		print("FAIL 无法写出 word_list.tsv")
		quit(1)
		return
	var seen := {}
	var n := 0
	for w in DB.words:
		var id: String = DB.word_id(w)
		if seen.has(id):
			continue
		seen[id] = true
		f.store_line(id + "\t" + String(w.get("w", "")))
		n += 1
	f.close()
	print("写出词条数 = ", n)
	quit(0)
