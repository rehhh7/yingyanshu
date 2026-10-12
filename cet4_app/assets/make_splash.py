# 重新生成启动封面（v0.9.19 起：用户要求封面不出现任何叠加文字——纯插画）
# AI 插画为底（裁掉底部含水印的一条，拉伸回 1080x2400）；无插画时回退：同色渐变底 + 羽化图标
from PIL import Image, ImageDraw, ImageFilter
import os

ROOT = os.path.dirname(os.path.abspath(__file__))
W, H = 1080, 2400
ART = os.path.join(ROOT, "splash_art.png")

if os.path.exists(ART):
    art = Image.open(ART).convert("RGB")
    art = art.crop((0, 0, art.width, int(art.height * 0.94))).resize((W, H), Image.LANCZOS)
    art.save(os.path.join(ROOT, "splash.png"))
    print("splash.png regenerated from AI art (no text)")
    raise SystemExit(0)

# ================= 旧版兜底（无 splash_art.png 时）：渐变底 + 羽化图标，无任何文字 =================
icon = Image.open(os.path.join(ROOT, "icon_source.jpg")).convert("RGB")
icon = icon.crop((70, 70, 1010, 1010))   # 裁掉 JPG 圆角外的白边

pts = [(450, 40), (130, 80), (800, 120), (850, 850)]
corners = [icon.getpixel(p) for p in pts]
base = tuple(sum(c[i] for c in corners) // 4 for i in range(3))

def shade(c, f):
    return tuple(max(0, min(255, int(v * f))) for v in c)

top_c = shade(base, 0.94)
bot_c = shade(base, 0.80)
canvas = Image.new("RGB", (W, H))
for y in range(H):
    t = y / (H - 1)
    canvas.paste(tuple(int(top_c[i] + (bot_c[i] - top_c[i]) * t) for i in range(3)), (0, y, W, y + 1))

# 图标后方柔光（奶油色）
glow = Image.new("L", (W, H), 0)
gd = ImageDraw.Draw(glow)
cx, cy, r = W // 2, int(H * 0.42), 560
gd.ellipse([cx - r, cy - r, cx + r, cy + r], fill=70)
glow = glow.filter(ImageFilter.GaussianBlur(180))
canvas = Image.composite(Image.new("RGB", (W, H), (246, 238, 216)), canvas, glow.point(lambda v: v * 0.55))

# 图标：圆角 + 大幅羽化边缘，融进底色
IS = 640
ic = icon.resize((IS, IS), Image.LANCZOS)
mask = Image.new("L", (IS, IS), 0)
md = ImageDraw.Draw(mask)
md.rounded_rectangle([0, 0, IS - 1, IS - 1], radius=150, fill=255)
mask = mask.filter(ImageFilter.GaussianBlur(26))
canvas.paste(ic, (cx - IS // 2, cy - IS // 2), mask)

canvas.save(os.path.join(ROOT, "splash.png"))
print("splash.png regenerated (fallback, no text), base color =", base)
