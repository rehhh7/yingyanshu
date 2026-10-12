class_name LanSync
extends Node
## 局域网互传引擎（纯离线，同 WiFi 下两台设备直连）
## 发现：宿主方每秒 UDP 广播一次「设备名」；搜索方监听广播列出设备
## 握手：请求方连上后发 "REQ|<设备名>\n"；宿主方确认后回 4 字节大端长度 + UTF-8 载荷，长度 0 = 拒绝
## 传输内容 = 固定 Markdown（DB.build_transfer_md，仅自定义词条；旧 JSON 备份载荷接收端兼容）；与蓝牙插件（YysKit）同一套交互

signal peer_found(dev_name: String, ip: String)
signal incoming_request(dev_name: String, ip: String)
signal receive_done(json_text: String)
signal send_done
signal rejected
signal failed(msg: String)

const BCAST_PORT := 47777
const TCP_PORT := 47778
const MAGIC := "YYSYNC1"
const MAX_BYTES := 64 * 1024 * 1024   # 防御：单次传输上限 64MB
const REQ_TIMEOUT := 8.0              # 等对方请求行的秒数

var _mode := 0   # 0 空闲 1 宿主 2 搜索
var _udp := UDPServer.new()
var _bcast := PacketPeerUDP.new()
var _tcp_srv := TCPServer.new()
var _payload := PackedByteArray()
var _pending: Array = []   # {conn: StreamPeerTCP, ip: String, wait: float} 已连接待读请求行
var _bcast_t := 0.0
var _client: StreamPeerTCP = null
var _expect := -1
var _buf := PackedByteArray()
var _peers := {}   # ip -> 设备名（去重）

func device_name() -> String:
	var m := OS.get_model_name()
	return m if m != "" else "未命名设备"

## 宿主方：开启 TCP 服务 + 开始广播。返回 "" 成功，否则错误文案
func start_host(json_text: String) -> String:
	stop_all()
	_payload = json_text.to_utf8_buffer()
	var err := _tcp_srv.listen(TCP_PORT)
	if err != OK:
		return "无法开启通道（端口被占用，请关掉重来）"
	_bcast = PacketPeerUDP.new()
	_bcast.set_broadcast_enabled(true)
	_mode = 1
	return ""

## 搜索方：监听广播发现设备（宿主/搜索可同时开，互不影响）
func start_discovery() -> String:
	_udp = UDPServer.new()
	var err := _udp.listen(BCAST_PORT)
	if err != OK:
		return "无法监听发现频道（端口被占用，请关掉重来）"
	_mode = 2 if _mode == 0 else _mode
	return ""

## 宿主/搜索同时开启（互传双方都是这个状态）
func start_both(json_text: String) -> String:
	var e1 := start_host(json_text)
	if e1 != "":
		return e1
	return start_discovery()

## 宿主方：回应待处理的请求；接受则随后发送备份数据
func respond(ip: String, accept: bool) -> void:
	for p in _pending:
		if p["ip"] == ip and p["req_done"]:
			var c: StreamPeerTCP = p["conn"]
			c.big_endian = true
			if accept:
				c.put_u32(_payload.size())
				c.put_data(_payload)
				p["sent"] = true
			else:
				c.put_u32(0)
				p["reject_sent"] = true
			return

## 请求方：连接指定设备并发出互传请求
func request_to(ip: String) -> void:
	_client = StreamPeerTCP.new()
	_expect = -1
	_buf.clear()
	var err := _client.connect_to_host(ip, TCP_PORT)
	if err != OK:
		failed.emit("连接对方失败")
		return
	_client.set_no_delay(true)
	_client.big_endian = true

func stop_all() -> void:
	_mode = 0
	_udp.stop()
	_tcp_srv.stop()
	_bcast.close()
	_client = null
	_pending.clear()
	_peers.clear()
	_expect = -1
	_buf.clear()

func _process(delta: float) -> void:
	if _mode == 1 or _tcp_srv.is_listening():
		_bcast_t += delta
		if _bcast_t >= 1.0:
			_bcast_t = 0.0
			_bcast.set_dest_address("255.255.255.255", BCAST_PORT)
			_bcast.put_packet((MAGIC + "|" + device_name()).to_utf8_buffer())
		while _tcp_srv.is_connection_available():
			var c: StreamPeerTCP = _tcp_srv.take_connection()
			c.set_no_delay(true)
			_pending.append({"conn": c, "ip": c.get_connected_host(), "wait": 0.0, "req_done": false, "sent": false, "reject_sent": false, "rbuf": PackedByteArray()})
		for i in range(_pending.size() - 1, -1, -1):
			var p: Dictionary = _pending[i]
			var c: StreamPeerTCP = p["conn"]
			c.poll()
			var st := c.get_status()
			if p["sent"] or p["reject_sent"]:
				# 发完等对方断开（立刻断可能截断内核缓冲）
				if st != StreamPeerTCP.STATUS_CONNECTED and st != StreamPeerTCP.STATUS_CONNECTING:
					_pending.remove_at(i)
					if p["sent"]:
						send_done.emit()
				continue
			if st != StreamPeerTCP.STATUS_CONNECTED:
				p["wait"] += delta
				if st == StreamPeerTCP.STATUS_ERROR or st == StreamPeerTCP.STATUS_NONE or p["wait"] > REQ_TIMEOUT:
					_pending.remove_at(i)
				continue
			# 读请求行 "REQ|<设备名>\n"
			var rb: PackedByteArray = p["rbuf"]
			var avail := c.get_available_bytes()
			if avail > 0:
				var res: Array = c.get_data(mini(avail, 4096 - rb.size()))
				if res[0] == OK:
					rb.append_array(res[1])
			var nl := -1
			for j in rb.size():
				if rb[j] == 10:
					nl = j
					break
			if nl >= 0:
				var req := rb.slice(0, nl).get_string_from_utf8()
				if req.begins_with("REQ|"):
					p["req_done"] = true
					incoming_request.emit(req.substr(4), p["ip"])
				else:
					_pending.remove_at(i)
			else:
				p["wait"] += delta
				if rb.size() >= 4096 or p["wait"] > REQ_TIMEOUT:
					_pending.remove_at(i)
	if _udp.is_listening():
		_udp.poll()
		while _udp.is_connection_available():
			var peer: PacketPeerUDP = _udp.take_connection()
			if peer == null:
				break
			while peer.get_available_packet_count() > 0:
				var pkt: PackedByteArray = peer.get_packet()
				var ip: String = peer.get_packet_ip()
				var msg: String = pkt.get_string_from_utf8()
				if msg.begins_with(MAGIC + "|"):
					var nm: String = msg.get_slice("|", 1)
					if not _peers.has(ip):
						_peers[ip] = nm
						peer_found.emit(nm, ip)
	_poll_client()

func _poll_client() -> void:
	if _client == null:
		return
	_client.poll()
	var st := _client.get_status()
	if st == StreamPeerTCP.STATUS_ERROR or st == StreamPeerTCP.STATUS_NONE:
		_client = null
		failed.emit("连接中断，请重试")
		return
	if st != StreamPeerTCP.STATUS_CONNECTED:
		return
	# 阶段一：连上先自报家门 "REQ|<设备名>\n"
	if _expect == -1:
		_client.put_data(("REQ|" + device_name() + "\n").to_utf8_buffer())
		_expect = -3   # 已发请求，等长度头
		return
	# 阶段二：读 4 字节长度（0 = 对方拒绝）
	if _expect == -3:
		if _client.get_available_bytes() < 4:
			return
		_expect = _client.get_u32()
		if _expect == 0:
			_client = null
			rejected.emit()
			return
		if _expect < 0 or _expect > MAX_BYTES:
			_client = null
			failed.emit("数据长度异常")
			return
	# 阶段三：读载荷
	if _expect > 0:
		var avail := _client.get_available_bytes()
		if avail > 0:
			var res: Array = _client.get_data(mini(avail, _expect - _buf.size()))
			if res[0] == OK:
				_buf.append_array(res[1])
		if _buf.size() >= _expect:
			var txt := _buf.get_string_from_utf8()
			_client.disconnect_from_host()
			_client = null
			receive_done.emit(txt)
