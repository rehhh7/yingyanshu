extends SceneTree
## 局域网互传回路测试：本机 127.0.0.1 发送→接收，验证大文件分包传输完整性

var fails := 0
func check(name: String, cond: bool) -> void:
	print(("PASS " if cond else "FAIL ") + name)
	if not cond:
		fails += 1

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	# 构造约 2MB 的备份 JSON（远超单包，验证长度前缀 + 分包拼接）
	var d := {"type": "cet4_backup", "version": 1, "custom_words": [], "custom_phrases": [], "removed": {"words": [], "phrases": []}}
	for i in range(20000):
		d["custom_words"].append({"w": "word%05d" % i, "p": "/wɜːd/", "m": "n. 测试词%d；含中文标点，" % i, "day": "Day 1", "syn": [], "sim": []})
	var json_text := JSON.stringify(d)
	print("payload bytes = ", json_text.to_utf8_buffer().size())
	check("载荷超1MB", json_text.to_utf8_buffer().size() > 1024 * 1024)

	var sender := LanSync.new()
	root.add_child(sender)
	var send_err := sender.start_sender(json_text)
	check("发送通道开启", send_err == "")
	var sent := [false]
	sender.send_done.connect(func(): sent[0] = true)

	var receiver := LanSync.new()
	root.add_child(receiver)
	var recv_err := receiver.start_receiver()
	check("接收通道开启", recv_err == "")
	var got := [""]
	receiver.receive_done.connect(func(t: String): got[0] = t)
	receiver.connect_and_receive("127.0.0.1")

	var t := 0.0
	while got[0] == "" and t < 8.0:
		await create_timer(0.1).timeout
		t += 0.1
	check("收到数据", got[0] != "")
	check("数据完整一致", got[0] == json_text)
	await create_timer(0.5).timeout
	check("发送完成回调", sent[0])

	sender.stop_all()
	receiver.stop_all()
	print("== LAN 测试完成 fails=%d ==" % fails)
	quit(1 if fails > 0 else 0)
