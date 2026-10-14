extends SceneTree
## 诊断：词表模式列数与宽度

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in range(20):
		await process_frame
	var home = main.content.get_child(main.content.get_child_count() - 1)
	home._on_seg("table")
	for i in range(30):
		await process_frame
	print("scroll.size = ", home.list_scroll.size)
	print("flow.size = ", home.wl_flow.size if home.wl_flow else "null")
	print("cols = ", home._cols())
	if home.wl_flow and home.wl_flow.get_child_count() > 0:
		print("card0.min = ", home.wl_flow.get_child(0).custom_minimum_size)
		print("card0.size = ", home.wl_flow.get_child(0).size)
	var img := root.get_texture().get_image()
	var out := "user://_shots/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	img.save_png(out + "dbg_table.png")
	print("截图输出目录：" + ProjectSettings.globalize_path(out))
	print("== done ==")
	quit()
