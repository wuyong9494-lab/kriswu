"""生成 App 图标（1024×1024，不透明 PNG）：蓝色渐变背景上的日历，中间一个字。

用法：python3 scripts/make_icon.py <字体文件> <输出 png> [文字] [文字颜色 #RRGGBB]
（汉字用中文字体如 wqy-zenhei.ttc，字母用粗体如 DejaVuSans-Bold.ttf）
默认图标是「值」；每天切换的图标是组别字母 A–E 和「休」。
"""
import sys
from PIL import Image, ImageDraw, ImageFont

font_path, out = sys.argv[1], sys.argv[2]
text = sys.argv[3] if len(sys.argv) > 3 else "值"
color = sys.argv[4] if len(sys.argv) > 4 else "#2D3CC8"
fill = tuple(int(color.lstrip("#")[i:i + 2], 16) for i in (0, 2, 4))
S = 2048  # 先画 2 倍大再缩小，边缘更平滑

img = Image.new("RGB", (S, S))
top, bottom = (64, 140, 255), (52, 52, 196)
for y in range(S):
    t = y / (S - 1)
    img.paste(tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)), (0, y, S, y + 1))

d = ImageDraw.Draw(img)
# 日历卡片（带阴影）
x0, y0, x1, y1 = 400, 470, 1648, 1690
d.rounded_rectangle((x0 + 24, y0 + 40, x1 + 24, y1 + 40), 150, fill=(30, 30, 120))
d.rounded_rectangle((x0, y0, x1, y1), 150, fill=(255, 255, 255))
# 顶部色条
header_h = 300
d.rounded_rectangle((x0, y0, x1, y0 + header_h), 150, fill=(255, 92, 72))
d.rectangle((x0, y0 + 150, x1, y0 + header_h), fill=(255, 92, 72))
# 两个日历挂环
for cx in (x0 + 330, x1 - 330):
    d.rounded_rectangle((cx - 55, y0 - 130, cx + 55, y0 + 110), 55, fill=(245, 245, 250))
# 中间的字（字母比汉字略大）
font = ImageFont.truetype(font_path, 780 if text.isascii() else 820)
box = d.textbbox((0, 0), text, font=font)
tw, th = box[2] - box[0], box[3] - box[1]
cy = (y0 + header_h + y1) / 2
d.text(((x0 + x1) / 2 - tw / 2 - box[0], cy - th / 2 - box[1] + 10), text, font=font, fill=fill,
       stroke_width=0 if text.isascii() else 18, stroke_fill=fill)  # 汉字字体偏细，描边加粗

img.resize((1024, 1024), Image.LANCZOS).save(out, optimize=True)
