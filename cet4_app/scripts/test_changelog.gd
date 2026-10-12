extends SceneTree
## 一次性排查：更新日志文本是否读到
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var db = root.get_node_or_null("DB")
	if db == null:
		print("FAIL autoload DB 未加载")
		quit()
		return
	var t: String = db.changelog_text()
	print("changelog length=", t.length())
	print("head:", t.left(80))
	quit()
