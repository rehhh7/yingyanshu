extends SceneTree
## 本地导入解析功能测试

var DB

func _initialize() -> void:
	call_deferred("run")

var fails := 0
func check(name: String, cond: bool) -> void:
	print(("PASS " if cond else "FAIL ") + name)
	if not cond:
		fails += 1

func run() -> void:
	DB = root.get_node_or_null("DB")
	if DB == null:
		print("FAIL autoload DB 未加载")
		quit(1)
		return
	var day: String = DB.next_day_name()
	print("next_day = ", day)
	check("新Day递增", day == "Day 22")

	# 注意：accordance/accelerate/trivial/virtual buffet 已在内置词库，应判重
	var text := """# 注释行跳过
Day 22
1. abandon vt. 放弃；抛弃
2）accordance n. 一致；按照（in accordance with）
- testwordabc /tɛst/ n. 测试音标词
* in accordance with 按照；与……一致
trivial adj. 琐碎的；不重要的
make sense 有意义；讲得通
hello_world_test 测试下划线
barewordnoconn
随便一行中文
// 注释
• take advantage of 利用
virtual buffet 丰盛大餐
"""
	var res: Dictionary = DB.parse_import_text(text)
	print("words=", res["words"].size(), " phrases=", res["phrases"].size(),
		" dup=", res["dup"], " unknown=", res["unknown"])
	for w in res["words"]:
		print("  W: ", w["w"], " | p=", w["p"], " | m=", w["m"], " | day=", w["day"])
	for ph in res["phrases"]:
		print("  P: ", ph["en"], " = ", ph["cn"], " | sec=", ph["sec"])

	check("解析出2个新单词", res["words"].size() == 2)
	if res["words"].size() >= 2:
		check("abandon词性并入释义", res["words"][0]["m"] == "vt. 放弃；抛弃")
		check("音标识别", res["words"][1]["w"] == "testwordabc" and res["words"][1]["p"] == "/tɛst/" and res["words"][1]["m"] == "n. 测试音标词")
		check("新词进新Day", res["words"][0]["day"] == day)
	check("解析出3个词组", res["phrases"].size() == 3)
	if res["phrases"].size() >= 1:
		check("词组进新分组", res["phrases"][0]["sec"] == day)
	check("trivial判重", res["dup"].has("trivial"))
	check("accordance判重", res["dup"].has("accordance"))
	check("virtual buffet判重", res["dup"].has("virtual buffet"))
	check("下划线词进unknown", res["unknown"].has("hello_world_test 测试下划线"))
	check("无释义进unknown", res["unknown"].has("barewordnoconn（无释义，请核对）"))
	check("纯中文行进unknown", res["unknown"].has("随便一行中文"))

	print("== 测试完成 fails=%d ==" % fails)
	quit(1 if fails > 0 else 0)
