extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var main = scene
	print("PASS 主场景实例化")
	# 切 5 个 tab
	for i in range(5):
		main.switch_tab(i)
		await process_frame
		print("PASS tab %d" % i)
	# 打开学习界面（单词组 + 词组组）
	main.open_study("words", "手写一")
	await process_frame
	var study = main.overlay
	study._flip()
	study._step(1)
	study._mark_known()
	study._toggle_star()
	study._toggle_rate()
	study._toggle_mode()   # 列表
	await process_frame
	study._toggle_mode()   # 回卡片
	study._toggle_shuffle()
	print("PASS 学习界面单词")
	main.open_study("phrases", DBless("P1"))
	await process_frame
	print("PASS 学习界面词组")
	# 听写
	main.open_dictation("words", "Day 11")
	await process_frame
	var dv = main.overlay
	dv.input.text = "wronganswer"
	dv._on_submit()
	dv._on_submit()  # 下一题
	print("PASS 听写界面")
	main.switch_tab(0)
	await process_frame
	# 搜索
	main.switch_tab(0)
	await process_frame
	print("== UI 冒烟完成 ==")
	quit()

func DBless(sec: String) -> String:
	return sec
