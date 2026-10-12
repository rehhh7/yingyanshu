class_name Share
extends RefCounted
## 系统分享面板（安卓 YysKit 插件封装）：可调起微信/QQ 等系统分享
## 插件不存在（非安卓构建）时返回 false，调用方自行降级

static func available() -> bool:
	return Engine.has_singleton("YysKit")

## 分享文件（备份 json / docx 等），返回是否成功调起
static func file(abs_path: String, mime: String, title := "分享给朋友") -> bool:
	if not available():
		return false
	Engine.get_singleton("YysKit").call("share_file", abs_path, mime, title)
	return true

## 分享纯文本
static func text(t: String, title := "分享") -> bool:
	if not available():
		return false
	Engine.get_singleton("YysKit").call("share_text", t, title)
	return true
