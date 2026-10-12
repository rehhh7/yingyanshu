# -*- coding: utf-8 -*-
"""操作指南截图批注：编号红圈 + 底部外接说明条（画布向下延长，不遮挡内容）"""
from PIL import Image, ImageDraw, ImageFont
import os

SRC = r"C:\Users\s\Desktop\英语\_shots"
DST = r"C:\Users\s\Desktop\英语\操作指南"
FONT = r"C:\Windows\Fonts\msyh.ttc"

def annotate(src, dst, points, caption):
    img = Image.open(src).convert("RGB")
    W, H = img.size
    s = W / 540.0
    f_num = ImageFont.truetype(FONT, int(34 * s))
    f_cap = ImageFont.truetype(FONT, int(25 * s))
    # 说明文字换行（先算行数定条高）
    max_chars = int((W - 40 * s) / (26 * s))
    lines, cur = [], ""
    for ch in caption:
        if ch == "\n":
            lines.append(cur); cur = ""; continue
        cur += ch
        if len(cur) >= max_chars:
            lines.append(cur); cur = ""
    if cur:
        lines.append(cur)
    line_h = int(38 * s)
    bar_h = int(20 * s) + line_h * len(lines) + int(16 * s)
    # 画布向下延长
    canvas = Image.new("RGB", (W, H + bar_h), (12, 14, 18))
    canvas.paste(img, (0, 0))
    d = ImageDraw.Draw(canvas)
    # 编号红圈
    r = int(26 * s)
    for i, (x, y) in enumerate(points, 1):
        cx, cy = int(x), int(y)
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(229, 57, 53), outline=(255, 255, 255), width=max(2, int(3 * s)))
        t = str(i)
        bb = d.textbbox((0, 0), t, font=f_num)
        d.text((cx - (bb[2] - bb[0]) / 2, cy - (bb[3] - bb[1]) / 2 - bb[1]), t, font=f_num, fill=(255, 255, 255))
    # 说明条
    d.line([0, H, W, H], fill=(60, 64, 72), width=max(2, int(2 * s)))
    ty = H + int(14 * s)
    for ln in lines:
        d.text((int(20 * s), ty), ln.strip(), font=f_cap, fill=(235, 235, 235))
        ty += line_h
    canvas.save(dst, quality=92)
    print("OK", os.path.basename(dst), "%dx%d" % (W, H + bar_h))

annotate(SRC + r"\guide_home_empty.png", DST + r"\第1步_首次打开.png",
    [(270, 328)],
    "第 1 步｜装好后词库是空的，这是正常的——所有单词都由你自己导入。\n点红圈里的「去导入」直达导入区（以后也可以点右下角「设置」→「数据管理」）。")

annotate(SRC + r"\guide_import_area.png", DST + r"\第2步_导入单词的五种方式.png",
    [(30, 680), (500, 833), (500, 881), (500, 931), (500, 1026)],
    "第 2 步｜把单词放进来的五种方式：\n① 把单词文本粘贴进输入框（每行一条：单词＋中文释义，词组也行）\n② 点「选择文件导入」直接读 txt / md / docx 文件\n③ 点「拍照识图导入」拍一张单词表照片（联网，自动识别填入）\n④ 点「本地整理导入」：不联网，自动识别格式、查重、逐条确认入库\n⑤ 两台手机互传词库（见第 4 步）。文本太乱时可点「交给 AI 整理」。")

annotate(SRC + r"\ai_chat.png", DST + r"\第3步_AI拍照识图.png",
    [(48, 171), (28, 1071)],
    "第 3 步｜AI 页拍照识图更方便（需先在「设置 → AI API」填 API Key）：\n① 点「识图导入」选一张单词表照片，整理指令自动填好，再点「发送」\n② 或点相机图标附任意图片后自己提问（拍题目、拍书页都能问）。")

annotate(SRC + r"\lansync_centered.png", DST + r"\第4步_两台手机互传.png",
    [(537, 259), (575, 301)],
    "第 4 步｜两台手机互传词库：两台手机都打开「设置 → 数据管理 → 局域网/蓝牙互传」\n① 选局域网（同一 WiFi）或蓝牙　② 一台点「搜索手机」，找到对方后点它，\n选「扩展词汇」或「覆盖原词汇」，另一台手机上确认后开始传。")
