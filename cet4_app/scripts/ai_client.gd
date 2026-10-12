extends Node
## AI 请求中枢（autoload AI）：请求生命周期独立于界面，切 Tab / 息屏不打断
## 完成后把回复（含词库修改 ops）写进会话记录，界面回来时从记录恢复

signal progress(cur: int, total: int)   # 分批模式进度
signal finished(session_id: String)     # 某会话的请求完成

var busy := false
var current_session := ""

func is_busy_for(sid: String) -> bool:
	return busy and current_session == sid

# ---------------- 入口 ----------------
func start_single(sid: String, sys: String, messages: Array, image_url := "") -> void:
	if busy:
		return
	busy = true
	current_session = sid
	_arm_watchdog(sid)
	_run_single(sid, sys, messages, image_url)

func start_batch(sid: String, sys_base: String, user_text: String, chunks: Array) -> void:
	if busy:
		return
	busy = true
	current_session = sid
	_arm_watchdog(sid)
	_run_batch(sid, sys_base, user_text, chunks)

## 看门狗：请求 150 秒还没结束（异常/断网极端情况）自动解锁并写入失败提示，
## 防止 busy 卡死导致之后所有发送被静默吞掉
func _arm_watchdog(sid: String) -> void:
	get_tree().create_timer(150.0).timeout.connect(func():
		if busy and current_session == sid:
			_commit(sid, "请求超时，请检查网络或 API 设置后重试"))

# ---------------- 流程 ----------------
func _run_single(sid: String, sys: String, messages: Array, image_url := "") -> void:
	var msgs := [{"role": "system", "content": sys}]
	if image_url != "" and not messages.is_empty():
		# 带图：最后一条用户消息升级为多模态（文本+图片），走视觉模型
		var last: Dictionary = (messages[-1] as Dictionary).duplicate()
		last["content"] = [
			{"type": "text", "text": String(last.get("content", ""))},
			{"type": "image_url", "image_url": {"url": image_url}}]
		messages = messages.duplicate()
		messages[messages.size() - 1] = last
	msgs.append_array(messages)
	var d := await _request(msgs, _vision_model() if image_url != "" else "")
	var content: String = d.get("content", "")
	if content == "" and d.has("error"):
		content = "请求失败：" + String(d["error"])
	# 单次请求也要提取词库修改 JSON，挂到消息上供气泡下的确认按钮使用
	_commit(sid, content, d.get("reasoning", ""), extract_ops(content))

func _vision_model() -> String:
	return String(DB.settings.get("api_vision_model", "deepseek-v4-flash-vision-exp"))

## 独立视觉请求（不占用会话 busy）：设置页「拍照识图导入」用；失败返回 ""，错误详情进 error_out
func request_vision(prompt: String, data_url: String, error_out: Array = []) -> String:
	var d := await _request([
		{"role": "user", "content": [
			{"type": "text", "text": prompt},
			{"type": "image_url", "image_url": {"url": data_url}}]}], _vision_model())
	if not error_out.is_empty():
		error_out[0] = String(d.get("error", ""))
	return String(d.get("content", ""))

func _run_batch(sid: String, sys_base: String, user_text: String, chunks: Array) -> void:
	var truncated := false
	if chunks.size() > 12:
		chunks = chunks.slice(0, 12)   # 防失控：最多 12 批（约 8 万字）
		truncated = true
	var merged := {"add_words": [], "add_phrases": [], "remove_words": [], "remove_phrases": []}
	var ok_batches := 0
	for i in chunks.size():
		progress.emit(i + 1, chunks.size())
		var um := "%s\n\n【附加文件内容 第 %d/%d 批】\n%s\n（只整理本批内容，输出本批的词库 JSON）" % [
			user_text, i + 1, chunks.size(), chunks[i]]
		var d := await _request([
			{"role": "system", "content": sys_base},
			{"role": "user", "content": um}])
		var reply: String = d.get("content", "")
		if reply == "":
			continue   # 某批失败不中断，最后汇总提示
		ok_batches += 1
		var ops := extract_ops(reply)
		for k in merged:
			merged[k].append_array(ops.get(k, []))
	var total: int = merged["add_words"].size() + merged["add_phrases"].size() \
		+ merged["remove_words"].size() + merged["remove_phrases"].size()
	var summary := "已分 %d 批整理（成功 %d 批）：待新增单词 %d 个、词组 %d 条%s。请点下方「确认词库修改」逐条核对。" % [
		chunks.size(), ok_batches, merged["add_words"].size(), merged["add_phrases"].size(),
		"；文件过长，超出 12 批的部分未发送，请分两次导入" if truncated else ""]
	_commit(sid, summary, "", merged if total > 0 else {})

## 把结果写进会话记录（ops 非空时挂在消息上，随时可打开预览确认）
func _commit(sid: String, content: String, reasoning := "", ops := {}) -> void:
	# AI 长期记忆：回复里的 ```json {"memory_add"/"memory_remove"} 块解析后应用，不展示给用户
	var mem := extract_memory_ops(content)
	if not mem.is_empty():
		content = content.replace(String(mem["raw"]), "").strip_edges()
		var added := DB.memory_add(mem["ops"].get("memory_add", []))
		var removed_n := DB.memory_remove(mem["ops"].get("memory_remove", []))
		if added > 0 or removed_n > 0:
			content += ("\n\n" if content != "" else "") + "🧠 记忆已更新（新增 %d 条 / 移除 %d 条）" % [added, removed_n]
	if content == "":
		content = "请求失败，请检查网络或 API 设置后重试"
	var msg := {"role": "assistant", "content": content}
	if reasoning != "":
		msg["reasoning"] = reasoning
	if not ops.is_empty():
		msg["ops"] = ops
	var sess := DB.get_session(sid)
	if not sess.is_empty():
		sess["messages"].append(msg)
		DB.save_sessions()
	busy = false
	current_session = ""
	finished.emit(sid)

# ---------------- 网络 ----------------
func _request(messages: Array, model := "") -> Dictionary:
	var key := String(DB.settings.get("api_key", ""))
	var url := String(DB.settings.get("api_base", "https://api.deepseek.com")).trim_suffix("/") + "/v1/chat/completions"
	var body := JSON.stringify({
		"model": model if model != "" else String(DB.settings.get("api_model", "deepseek-v4-flash")),
		"messages": messages,
		"stream": false})
	var rq := HTTPRequest.new()
	rq.timeout = 120.0
	add_child(rq)
	var err := rq.request(url, ["Content-Type: application/json", "Authorization: Bearer " + key],
		HTTPClient.METHOD_POST, body)
	if err != OK:
		rq.queue_free()
		return {"error": "请求发起失败（错误码 %d）" % err}
	var resp = await rq.request_completed
	rq.queue_free()
	var result: int = resp[0]
	var code: int = resp[1]
	if result != HTTPRequest.RESULT_SUCCESS:
		return {"error": "网络错误（%d），请检查网络连接" % result}
	var raw := (resp[3] as PackedByteArray).get_string_from_utf8()
	var d = JSON.parse_string(raw)
	if code == 200 and d is Dictionary and d.has("choices"):
		var msg_d: Dictionary = d["choices"][0]["message"]
		return {"content": String(msg_d.get("content", "")),
			"reasoning": String(msg_d.get("reasoning_content", ""))}
	# 把服务端错误原文带回去（模型名不对、Key 无效等，方便用户排查）
	var detail := raw.left(220)
	if d is Dictionary and d.has("error"):
		var e = d["error"]
		if e is Dictionary:
			detail = String(e.get("message", detail))
	return {"error": "HTTP %d：%s" % [code, detail]}

# ---------------- 记忆 JSON 提取 ----------------
## 提取回复末尾的记忆操作块 ```json {"memory_add":[], "memory_remove":[]} ```
## 返回 {"ops": Dictionary, "raw": 原始匹配文本（用于从展示内容中剔除）}；无则 {}
static func extract_memory_ops(content: String) -> Dictionary:
	var re := RegEx.new()
	re.compile("```(?:json)?\\s*(\\{.*?\\})\\s*```")
	for m in re.search_all(content):
		var d = JSON.parse_string(m.get_string(1))
		if d is Dictionary and (d.has("memory_add") or d.has("memory_remove")):
			return {"ops": d, "raw": m.get_string()}
	return {}
static func extract_ops(content: String) -> Dictionary:
	# 提取 ```json 代码块或裸 JSON
	var candidates := []
	var re := RegEx.new()
	re.compile("```(?:json)?\\s*(\\{.*?\\})\\s*```")
	for m in re.search_all(content):
		candidates.append(m.get_string(1))
	if candidates.is_empty():
		var s := content.find("{")
		var e := content.rfind("}")
		if s >= 0 and e > s:
			candidates.append(content.substr(s, e - s + 1))
	for c in candidates:
		var d = JSON.parse_string(c)
		if d is Dictionary and (d.has("add_words") or d.has("add_phrases")
				or d.has("remove_words") or d.has("remove_phrases")):
			return d
	return {}
