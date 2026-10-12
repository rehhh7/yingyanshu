extends SceneTree
## 验证 docx 导出

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var db = root.get_node("DB")
	var path: String = db.export_docx()
	if path == "":
		print("FAIL docx 导出返回空")
	else:
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			print("FAIL docx 文件不存在")
		else:
			print("PASS docx 导出 size=%d path=%s" % [f.get_length(), path])
			f.close()
	# 再验证能作为 zip 读回
	var zr := ZIPReader.new()
	if path != "" and zr.open(path) == OK and zr.file_exists("word/document.xml"):
		print("PASS docx 结构有效")
		zr.close()
	else:
		print("FAIL docx 结构无效")
	quit()
