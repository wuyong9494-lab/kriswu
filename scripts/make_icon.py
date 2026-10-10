"""生成 App 图标（1024×1024，不透明 PNG）：渐变背景上一个白色大字。

不做成日历的样子：图标只能在打开 App 时更换，做成日历容易被当成当天日期。
默认图标是「值」；每天切换的图标是组别字母 A–E（蓝色）和「休」（绿色）。

用法：python3 scripts/make_icon.py <字体文件> <输出 png> [文字] [配色 blue|green]
（汉字用中文字体如 wqy-zenhei.ttc，字母用粗体如 DejaVuSans-Bold.ttf）
"""
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

font_path, out = sys.argv[1], sys.argv[2]
text = sys.argv[3] if len(sys.argv) > 3 else "值"
scheme = sys.argv[4] if len(sys.argv) > 4 else "blue"
S = 2048  # 先画 2 倍大再缩小，边缘更平滑

top, bottom = {"blue": ((70, 150, 255), (48, 44, 190)), "green": ((76, 217, 120), (24, 140, 80))}[scheme]
img = Image.new("RGB", (S, S))
for y in range(S):
    t = y / (S - 1)
    img.paste(tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)), (0, y, S, y + 1))

font = ImageFont.truetype(font_path, 1250 if text.isascii() else 1050)
stroke = 0 if text.isascii() else 24  # 汉字字体偏细，描边加粗

def draw_text(draw, offset, fill):
    box = draw.textbbox((0, 0), text, font=font, stroke_width=stroke)
    w, h = box[2] - box[0], box[3] - box[1]
    pos = ((S - w) / 2 - box[0] + offset[0], (S - h) / 2 - box[1] + offset[1])
    draw.text(pos, text, font=font, fill=fill, stroke_width=stroke, stroke_fill=fill)

# 柔和的投影
shadow = Image.new("L", (S, S), 0)
draw_text(ImageDraw.Draw(shadow), (0, 36), 110)
shadow = shadow.filter(ImageFilter.GaussianBlur(40))
img.paste((10, 10, 60), (0, 0), shadow)

draw_text(ImageDraw.Draw(img), (0, 0), (255, 255, 255))
img.resize((1024, 1024), Image.LANCZOS).save(out, optimize=True)
