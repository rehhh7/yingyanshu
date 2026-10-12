extends SceneTree
## 局域网互传回路测试：REQ 握手 → 对方确认 → 长度前缀分包传输；另测「拒绝」回执

var fails := 0
func check(name: String, cond: bool) -> void:
	print(("PASS " if cond else "FAIL ") + name)
	if not cond:
		fails += 1

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	# 约 2MB 的 Markdown 载荷（远超单包，验证长度前缀 + 分包拼接）
	var md := "# 英眼书互传\n\n# Day 99\n"
	for i in range(20000):
		md += "word%05d /wɜːd/ n. 测试词%d；含中文标点，\n" % [i, i]
	print("payload bytes = ", md.to_utf8_buffer().size())
	check("载荷超1MB", md.to_utf8_buffer().size() > 1024 * 1024)

	# ---- 接受路径 ----
	var host := LanSync.new()
	root.add_child(host)
	check("宿主通道开启", host.start_host(md) == "")
	var host_got_req := [""]
	host.incoming_request.connect(func(nm: String, ip: String):
		host_got_req[0] = nm
		host.respond(ip, true))
	var sent := [false]
	host.send_done.connect(func(): sent[0] = true)

	var cli := LanSync.new()
	root.add_child(cli)
	var got := [""]
	cli.receive_done.connect(func(t: String): got[0] = t)
	cli.request_to("127.0.0.1")
	var t := 0.0
	while got[0] == "" and t < 8.0:
		await create_timer(0.1).timeout
		t += 0.1
	check("宿主收到请求且自报家门", host_got_req[0] != "")
	check("收到数据", got[0] != "")
	check("数据完整一致", got[0] == md)
	await create_timer(0.5).timeout
	check("发送完成回调", sent[0])
	host.stop_all()
	cli.stop_all()
	host.queue_free()
	cli.queue_free()
	await create_timer(0.3).timeout

	# ---- 拒绝路径 ----
	var host2 := LanSync.new()
	root.add_child(host2)
	check("拒绝组宿主开启", host2.start_host("# 英眼书互传\n") == "")
	host2.incoming_request.connect(func(_nm: String, ip: String): host2.respond(ip, false))
	var cli2 := LanSync.new()
	root.add_child(cli2)
	var rejected := [false]
	cli2.rejected.connect(func(): rejected[0] = true)
	cli2.request_to("127.0.0.1")
	t = 0.0
	while not rejected[0] and t < 5.0:
		await create_timer(0.1).timeout
		t += 0.1
	check("拒绝回执送达", rejected[0])
	host2.stop_all()
	cli2.stop_all()

	print("== LAN 测试完成 fails=%d ==" % fails)
	quit(1 if fails > 0 else 0)
