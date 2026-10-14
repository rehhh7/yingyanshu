extends SceneTree
## 一次性排查：展开设置页「更新日志」分组并截图
const OUT := "user://_shots/"   # 产物目录（符号路径，不写本机绝对路径）；实际位置见启动时打印

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	print("截图输出目录：" + ProjectSettings.globalize_path(OUT))
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.switch_tab(4)
	await process_frame
	await process_frame
	var sv = main.content.get_child(main.content.get_child_count() - 1)
	# 找「更新日志」分组头按钮并点开
	var found := false
	var stack := [sv]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is Button and String(n.text).contains("更新日志"):
			n.pressed.emit()
			found = true
			print("找到并展开更新日志分组")
			break
		for c in n.get_children():
			stack.append(c)
	if not found:
		print("FAIL 未找到更新日志分组")
	# 展开后滚到底部让日志进入视野
	await process_frame
	var sc: ScrollContainer = null
	for c in sv.get_children():
		if c is ScrollContainer:
			sc = c
	if sc:
		sc.scroll_vertical = 99999
	for i in range(4):
		await process_frame
	var img := root.get_texture().get_image()
	img.save_png(OUT + "changelog_open.png")
	print("shot changelog_open")
	quit()
