class_name LanSync
extends Node
## 局域网互传引擎（纯离线，同 WiFi 下两台设备直连）
## 发现：发送方每秒 UDP 广播一次「设备名」；接收方监听广播列出可用设备
## 传输：TCP 直连，协议 = 4 字节大端长度 + UTF-8 JSON（即 DB.build_backup_payload 的序列化）
## 说明：蓝牙未采用——Godot 安卓端无蓝牙 API（需自写 Java 插件），且文本量级下局域网速度快百倍以上

signal peer_found(dev_name: String, ip: String)
signal receive_done(json_text: String)
signal send_done
signal failed(msg: String)

const BCAST_PORT := 47777
const TCP_PORT := 47778
const MAGIC := "YYSYNC1"
const MAX_BYTES := 64 * 1024 * 1024   # 防御：单次传输上限 64MB

var _mode := 0   # 0 空闲 1 发送方 2 接收方
var _udp := UDPServer.new()
var _bcast := PacketPeerUDP.new()
var _tcp_srv := TCPServer.new()
var _payload := PackedByteArray()
var _conns: Array = []   # 发送方已接受的连接（发完等对方断开再清理）
var _bcast_t := 0.0
var _client: StreamPeerTCP = null
var _expect := -1
var _buf := PackedByteArray()
var _peers := {}   # ip -> 设备名（去重）

func device_name() -> String:
	var m := OS.get_model_name()
	return m if m != "" else "未命名设备"

## 发送方：开启 TCP 服务 + 开始广播。返回 "" 成功，否则错误文案
func start_sender(json_text: String) -> String:
	stop_all()
	_payload = json_text.to_utf8_buffer()
	var err := _tcp_srv.listen(TCP_PORT)
	if err != OK:
		return "无法开启发送通道（端口被占用，请关掉重来）"
	_bcast = PacketPeerUDP.new()
	_bcast.set_broadcast_enabled(true)
	_mode = 1
	return ""

## 接收方：监听广播发现设备。返回 "" 成功，否则错误文案
func start_receiver() -> String:
	stop_all()
	_udp = UDPServer.new()
	var err := _udp.listen(BCAST_PORT)
	if err != OK:
		return "无法监听发现频道（端口被占用，请关掉重来）"
	_mode = 2
	return ""

## 接收方：连接指定设备并接收数据（结果走 receive_done / failed 信号）
func connect_and_receive(ip: String) -> void:
	_client = StreamPeerTCP.new()
	_expect = -1
	_buf.clear()
	var err := _client.connect_to_host(ip, TCP_PORT)
	if err != OK:
		failed.emit("连接对方失败")

func stop_all() -> void:
	_mode = 0
	_udp.stop()
	_tcp_srv.stop()
	_bcast.close()
	_client = null
	_conns.clear()
	_peers.clear()
	_expect = -1
	_buf.clear()

func _process(delta: float) -> void:
	if _mode == 1:
		_bcast_t += delta
		if _bcast_t >= 1.0:
			_bcast_t = 0.0
			_bcast.set_dest_address("255.255.255.255", BCAST_PORT)
			_bcast.put_packet((MAGIC + "|" + device_name()).to_utf8_buffer())
		while _tcp_srv.is_connection_available():
			var c: StreamPeerTCP = _tcp_srv.take_connection()
			c.set_no_delay(true)
			c.big_endian = true
			c.put_u32(_payload.size())
			c.put_data(_payload)
			_conns.append(c)
		# 发完的连接保持到对方主动断开（立刻断可能截断内核缓冲里的数据）
		for i in range(_conns.size() - 1, -1, -1):
			var c: StreamPeerTCP = _conns[i]
			c.poll()
			var st := c.get_status()
			if st != StreamPeerTCP.STATUS_CONNECTED and st != StreamPeerTCP.STATUS_CONNECTING:
				_conns.remove_at(i)
				send_done.emit()
	elif _mode == 2:
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
	_client.big_endian = true
	if _expect < 0:
		if _client.get_available_bytes() >= 4:
			_expect = _client.get_u32()
			if _expect <= 0 or _expect > MAX_BYTES:
				_client = null
				failed.emit("数据长度异常")
				return
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
