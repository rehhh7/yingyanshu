# 重新生成启动封面：AI 生成插画 + PIL 文字排版（无插画时回退旧版：同色渐变底 + 羽化图标）
from PIL import Image, ImageDraw, ImageFilter, ImageFont
import os

ROOT = os.path.dirname(os.path.abspath(__file__))
W, H = 1080, 2400
font_path = os.path.join(ROOT, "NotoSansSC-subset.ttf")
full_font = os.path.join(ROOT, "..", "..", "_tools", "downloads", "NotoSansSC.ttf")
if not os.path.exists(full_font):
    full_font = font_path
ink = (52, 58, 50)          # 深墨绿（从书本线条取色）
cream = (244, 236, 214)
ART = os.path.join(ROOT, "splash_art.png")

if os.path.exists(ART):
    # ---- 新版：AI 插画为底（裁掉底部含水印的一条，拉伸回 1080x2400）----
    art = Image.open(ART).convert("RGB")
    art = art.crop((0, 0, art.width, int(art.height * 0.94))).resize((W, H), Image.LANCZOS)
    canvas = art
    d = ImageDraw.Draw(canvas)
    cx = W // 2
    # 书名：放在书本下方的空区（书本约占 0.42~0.68 高度）
    ft = ImageFont.truetype(font_path, 132)
    title = "英眼书"
    tw = d.textlength(title, font=ft)
    ty = int(H * 0.74)
    d.text((cx - tw / 2, ty), title, font=ft, fill=ink, stroke_width=4, stroke_fill=ink)   # 同色描边加粗
    # 副标题
    fs = ImageFont.truetype(font_path, 46)
    sub = "四级单词 · 听力词组"
    sw = d.textlength(sub, font=fs)
    d.text((cx - sw / 2, ty + 185), sub, font=fs, fill=ink, stroke_width=2, stroke_fill=ink)
    # ---- 底部标语：戴墨镜的机器人 + 文字（底部居中）----
    fr = ImageFont.truetype(full_font, 48)
    credit = "英语学习，触手可及"
    cw = d.textlength(credit, font=fr)
    rw, rh = 220, 150
    gap = 36
    total = rw + gap + cw
    while total > W - 120 and fr.size > 30:
        fr = ImageFont.truetype(full_font, fr.size - 2)
        cw = d.textlength(credit, font=fr)
        total = rw + gap + cw
    rx = cx - total / 2
    ry = int(H * 0.875)
    d.line([(rx + rw / 2, ry), (rx + rw / 2, ry - 46)], fill=ink, width=8)
    d.ellipse([rx + rw / 2 - 14, ry - 74, rx + rw / 2 + 14, ry - 46], fill=ink)
    d.rounded_rectangle([rx, ry, rx + rw, ry + rh], radius=36, fill=cream, outline=ink, width=6)
    for ex in (rx + rw / 2 - 52, rx + rw / 2 + 52):
        d.ellipse([ex - 34, ry + 42, ex + 34, ry + 110], fill=(28, 30, 34))
    d.rectangle([rx + rw / 2 - 52, ry + 66, rx + rw / 2 + 52, ry + 82], fill=(28, 30, 34))
    d.text((rx + rw + gap, ry + rh / 2 - 34), credit, font=fr, fill=(40, 45, 38),
           stroke_width=3, stroke_fill=(40, 45, 38))
    canvas.save(os.path.join(ROOT, "splash.png"))
    print("splash.png regenerated from AI art")
    raise SystemExit(0)

# ================= 旧版兜底（无 splash_art.png 时）：渐变底 + 羽化图标 =================
icon = Image.open(os.path.join(ROOT, "icon_source.jpg")).convert("RGB")

# 图标 JPG 圆角外带白边：先裁掉 70px 外圈，只留灰绿圆角方块本体
icon = icon.crop((70, 70, 1010, 1010))

# 取样图标底色（灰绿），封面底色与它一致 → 图标羽化后彻底融进去，物理上不可能有缝合线
pts = [(450, 40), (130, 80), (800, 120), (850, 850)]
corners = [icon.getpixel(p) for p in pts]
base = tuple(sum(c[i] for c in corners) // 4 for i in range(3))

def shade(c, f):
    return tuple(max(0, min(255, int(v * f))) for v in c)

top_c = shade(base, 0.94)     # 顶部略深
bot_c = shade(base, 0.80)     # 底部更深，垂直单向渐变（横向均匀，拉伸无感）

canvas = Image.new("RGB", (W, H))
for y in range(H):
    t = y / (H - 1)
    canvas.paste(tuple(int(top_c[i] + (bot_c[i] - top_c[i]) * t) for i in range(3)), (0, y, W, y + 1))

# ---- 图标后方柔光（奶油色，营造书本发光感）----
glow = Image.new("L", (W, H), 0)
gd = ImageDraw.Draw(glow)
cx, cy, r = W // 2, int(H * 0.40), 560
gd.ellipse([cx - r, cy - r, cx + r, cy + r], fill=70)
glow = glow.filter(ImageFilter.GaussianBlur(180))
canvas = Image.composite(Image.new("RGB", (W, H), (246, 238, 216)), canvas, glow.point(lambda v: v * 0.55))

# ---- 图标：圆角 + 大幅羽化边缘，融进底色 ----
IS = 640
ic = icon.resize((IS, IS), Image.LANCZOS)
mask = Image.new("L", (IS, IS), 0)
md = ImageDraw.Draw(mask)
md.rounded_rectangle([0, 0, IS - 1, IS - 1], radius=150, fill=255)
mask = mask.filter(ImageFilter.GaussianBlur(26))   # 羽化 26px，边缘渐变透明
canvas.paste(ic, (cx - IS // 2, cy - IS // 2), mask)

# ---- 品牌字 ----
font_path = os.path.join(ROOT, "NotoSansSC-subset.ttf")
ink = (52, 58, 50)          # 深墨绿（从书本线条取色）
cream = (244, 236, 214)
d = ImageDraw.Draw(canvas)
ft = ImageFont.truetype(font_path, 132)
fs = ImageFont.truetype(font_path, 46)
title = "英眼书"
sub = "四级单词 · 听力词组"
tw = d.textlength(title, font=ft)
# 标题描一圈浅色光晕再写深色字，保证在灰绿底上清晰
ty = int(H * 0.595)
d.text((cx - tw / 2, ty), title, font=ft, fill=ink, stroke_width=3, stroke_fill=(238, 232, 208))
sw = d.textlength(sub, font=fs)
d.text((cx - sw / 2, ty + 190), sub, font=fs, fill=shade(ink, 1.25))

# ---- 底部标语：戴墨镜的机器人 + 文字（底部居中）----
# 标语用全量字体（子集字体可能缺「触手可及」等字形）
full_font = os.path.join(ROOT, "..", "..", "_tools", "downloads", "NotoSansSC.ttf")
if not os.path.exists(full_font):
    full_font = font_path
fr = ImageFont.truetype(full_font, 48)
credit = "英语学习，触手可及"
cw = d.textlength(credit, font=fr)
rw, rh = 220, 150          # 机器人头尺寸
gap = 36
total = rw + gap + cw
while total > W - 120 and fr.size > 30:   # 超宽自动缩字号
    fr = ImageFont.truetype(full_font, fr.size - 2)
    cw = d.textlength(credit, font=fr)
    total = rw + gap + cw
rx = cx - total / 2
ry = int(H * 0.86)
# 天线
d.line([(rx + rw / 2, ry), (rx + rw / 2, ry - 46)], fill=ink, width=8)
d.ellipse([rx + rw / 2 - 14, ry - 74, rx + rw / 2 + 14, ry - 46], fill=ink)
# 头
d.rounded_rectangle([rx, ry, rx + rw, ry + rh], radius=36, fill=cream, outline=ink, width=6)
# 墨镜：两个圆片 + 横梁
for ex in (rx + rw / 2 - 52, rx + rw / 2 + 52):
    d.ellipse([ex - 34, ry + 42, ex + 34, ry + 110], fill=(28, 30, 34))
d.rectangle([rx + rw / 2 - 52, ry + 66, rx + rw / 2 + 52, ry + 82], fill=(28, 30, 34))
# 文字（与机器人垂直居中对齐；同色描边加粗笔画——全量字体是细体，细线在底上发虚）
d.text((rx + rw + gap, ry + rh / 2 - 34), credit, font=fr, fill=(40, 45, 38),
       stroke_width=3, stroke_fill=(40, 45, 38))

canvas.save(os.path.join(ROOT, "splash.png"))
print("splash.png regenerated, base color =", base, "bottom =", bot_c)
