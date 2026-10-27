#!/usr/bin/env python3
"""生成数传计划的文字识别测试图（虚构数据），放到 Tests/SiteTests/OCRSamples/。
模拟手机拍电脑屏幕：先按屏幕像素画出 Excel / 网页上的表，每个像素拆成红绿蓝三条子像素，
再按拍照的角度投到相机画面上（不做抗锯齿，子像素和相机像素对不齐，就出现拍屏幕时的彩色摩尔纹），
最后加一点模糊、噪点、明暗不均，存成 JPEG。另有一张很长的干净长图、一张文档扫描那样扶正过的。
每张图旁边一个 .json，写着表里每一行应该认出什么。

需要 Pillow、numpy，和中文字体（AR PL UMing 宋体风格、文泉驿正黑）：
  apt-get install fonts-arphic-uming fonts-wqy-zenhei
用法：python3 scripts/make_ocr_samples.py
"""
import json
import os
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = os.path.join(os.path.dirname(__file__), "..", "Tests", "SiteTests", "OCRSamples")
SONG = "/usr/share/fonts/truetype/arphic/uming.ttc"
HEI = "/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc"

rng = random.Random(20261027)

# 虚构的运营商和地面站（和真的对不上）
STATIONS = ["甲光北湖04", "甲光北湖03", "甲光东岭02", "甲光南湾01", "乙宇-东山05", "乙宇-东山01",
            "丙邑-西岭1101", "丙邑-青岗3101", "丁站02", "丁站01", "丁站", "戊星-南岭0751",
            "己桥-云岭01", "庚洲南部站", "辛站03", "辛站02"]
RULES = {"甲": ["甲光"], "乙": ["乙宇"], "丙": ["丙邑"], "丁": ["丁站"], "戊": ["戊星"],
         "己": ["己桥"], "庚": ["庚洲"], "辛": ["辛站"]}
SATS = ["XA101C", "XA102C", "XA1PT02A03", "XA1GF05B", "XBGF07C04", "XBGF07D02", "XBGF07D03",
        "XBGF07D04", "XBGF07E01", "XBGF07E02", "XBGF07E03", "XBGF07E04"]
NAMES = {"XA101C": "试验01星", "XA102C": "试验02星", "XA1PT02A03": "平台02A星", "XA1GF05B": "高分05B星",
         "XBGF07C04": "宽幅07C星", "XBGF07D02": "宽幅07D星", "XBGF07D03": "宽幅07D星", "XBGF07D04": "宽幅07D星",
         "XBGF07E01": "宽幅07E星", "XBGF07E02": "宽幅07E星", "XBGF07E03": "宽幅07E星", "XBGF07E04": "宽幅07E星"}


def plan(n):
    """n 条虚构计划，开始时间各不相同"""
    rows, used = [], set()
    sat_i = 0
    for i in range(n):
        if i and rng.random() < 0.35:
            sat_i = min(sat_i + 1, len(SATS) - 1)
        sat = SATS[sat_i]
        while True:
            day = rng.choice([27, 28])
            h, m, s = rng.randrange(24), rng.randrange(60), rng.randrange(60)
            start = f"2026-10-{day} {h:02d}:{m:02d}:{s:02d}"
            if start not in used:
                used.add(start)
                break
        dur = rng.randrange(300, 720)
        t = h * 3600 + m * 60 + s + dur
        eday = day + t // 86400
        t %= 86400
        end = f"2026-10-{eday} {t // 3600:02d}:{t % 3600 // 60:02d}:{t % 60:02d}"
        fast = rng.random() < 0.2
        rows.append({
            "satellite": sat, "name": NAMES[sat], "station": rng.choice(STATIONS),
            "orbit": str(rng.choice([rng.randrange(2016, 2034), rng.randrange(10840, 10890), rng.randrange(42930, 42970)])),
            "start": start, "end": end,
            "created": f"2026-10-26 {rng.choice([15, 16, 17])}:{rng.randrange(60):02d}:{rng.randrange(60):02d}",
            "info": "通道1:1200M，通道2:1200M" if fast else "通道1:900M，通道2:900M",
            "emergency": rng.random() < 0.18,
        })
    return rows


def font(path, size):
    return ImageFont.truetype(path, size)


def text(draw, xy, s, f, fill, clip=None, bold=False):
    """画一格的字；clip=(左, 右)：超出格子的部分不画（Excel 里旁边有字时就是这样）"""
    if clip is None:
        draw.text(xy, s, font=f, fill=fill)
        if bold:
            draw.text((xy[0] + 1, xy[1]), s, font=f, fill=fill)
        return
    w = int(draw.textlength(s, font=f)) + 4
    h = f.size + 8
    tile = Image.new("L", (w, h), 0)
    ImageDraw.Draw(tile).text((0, 0), s, font=f, fill=255)
    visible = max(0, min(w, clip[1] - int(xy[0])))
    if visible <= 0:
        return
    mask = tile.crop((0, 0, visible, h))
    draw._image.paste(fill, (int(xy[0]), int(xy[1]), int(xy[0]) + visible, int(xy[1]) + h), mask)


# MARK: - 屏幕上的 Excel

def excel_screen(rows, width=1920, height=1080):
    img = Image.new("RGB", (width, height), (255, 255, 255))
    d = ImageDraw.Draw(img)
    small = font(SONG, 15)
    head = font(SONG, 19)
    # 编辑栏
    d.rectangle((0, 0, width, 34), fill=(243, 243, 243))
    d.rectangle((6, 6, 120, 28), outline=(200, 200, 200), fill=(255, 255, 255))
    d.text((12, 8), "H21", font=small, fill=(60, 60, 60))
    d.text((150, 8), "fx", font=small, fill=(90, 90, 90))
    d.text((190, 8), "不是", font=small, fill=(30, 30, 30))
    widths = [44, 200, 210, 200, 220, 230, 230, 230, 230]
    xs = [0]
    for w in widths:
        xs.append(xs[-1] + w)
    top = 36
    letter_h = 24
    row_h = 19
    header_h = 26
    # 列字母
    d.rectangle((0, top, width, top + letter_h), fill=(238, 238, 238))
    for i, letter in enumerate("ABCDEFGH"):
        cx = (xs[i + 1] + xs[i + 2]) / 2
        d.text((cx - 5, top + 4), letter, font=small, fill=(90, 90, 90))
    y0 = top + letter_h
    # 表头（第 1 行）
    headers = ["卫星", "地面站", "圈次", "数传开始", "创建时间", "数传速率", "是否应急", "是否重点保障"]
    d.rectangle((xs[1], y0, xs[-1], y0 + header_h), fill=(217, 217, 217))
    d.rectangle((0, y0, xs[1], height), fill=(238, 238, 238))
    d.text((14, y0 + 5), "1", font=small, fill=(90, 90, 90))
    for i, h in enumerate(headers):
        cx = (xs[i + 1] + xs[i + 2]) / 2
        text(d, (cx - d.textlength(h, font=head) / 2, y0 + 3), h, head, (20, 20, 20), bold=True)
    y = y0 + header_h
    for r, row in enumerate(rows):
        d.text((10 if r + 2 < 10 else 6, y + 2), str(r + 2), font=small, fill=(90, 90, 90))
        cells = [row["satellite"], row["station"], row["orbit"], row["start"], row["created"], row["info"],
                 "是" if row["emergency"] else "不是", "不是"]
        for c, value in enumerate(cells):
            x = xs[c + 1] + 4
            # 数传速率比格子宽：后面的格子有字，超出的部分被挡住
            clip = (xs[c + 1], xs[c + 2] - 2) if c == 5 else None
            text(d, (x, y + 1), value, small, (25, 25, 25), clip=clip)
        y += row_h
    # 后面几行空着
    r = len(rows)
    while y < height - row_h:
        d.text((6, y + 2), str(r + 2), font=small, fill=(90, 90, 90))
        y += row_h
        r += 1
    # 格线
    for x in xs:
        d.line((x, y0, x, height), fill=(212, 212, 212))
    yy = y0
    d.line((0, yy, width, yy), fill=(190, 190, 190))
    yy += header_h
    while yy < height:
        d.line((0, yy, width, yy), fill=(222, 222, 222))
        yy += row_h
    # 选中的格子
    d.rectangle((xs[8], y0 + header_h + row_h * 19, xs[9], y0 + header_h + row_h * 20), outline=(33, 115, 70), width=2)
    return img


# MARK: - 屏幕上的网页表格

def web_screen(rows, width=1920, height=1080, scale=1.0, tall=False):
    s = scale
    head_f = font(HEI, int(15 * s))
    cell_f = font(HEI, int(14 * s))
    tag_f = font(HEI, int(12 * s))
    columns = [("No.", 70), ("圈号", 110), ("卫星ID", 130), ("卫星名称", 150), ("地面站", 170),
               ("数传开始时间", 250), ("数传结束时间", 250), ("数传信息", 260), ("状态", 110)]
    total = sum(w for _, w in columns)
    xs = [int(30 * s)]
    for _, w in columns:
        xs.append(xs[-1] + int(w * s * (width / s - 60) / total))
    row_h = int(46 * s)
    head_h = int(52 * s)
    if tall:
        height = int(120 * s) + head_h + row_h * len(rows) + int(40 * s)
    img = Image.new("RGB", (width, height), (255, 255, 255))
    d = ImageDraw.Draw(img)
    # 工具栏
    d.rectangle((0, 0, width, int(56 * s)), fill=(248, 249, 251))
    for i, (label, x) in enumerate([("导出Excel", 30), ("100%", 160), ("125%", 240), ("150%", 320)]):
        bx = int(x * s)
        d.rectangle((bx, int(14 * s), bx + int(66 * s), int(42 * s)), fill=(64, 158, 255) if i == 3 else (236, 245, 255))
        d.text((bx + int(8 * s), int(20 * s)), label, font=tag_f, fill=(255, 255, 255) if i == 3 else (64, 158, 255))
    d.line((0, int(60 * s), width, int(60 * s)), fill=(255, 150, 40), width=max(1, int(2 * s)))
    y = int(70 * s)
    for i, (label, _) in enumerate(columns):
        cx = (xs[i] + xs[i + 1]) / 2
        d.text((cx - d.textlength(label, font=head_f) / 2, y + (head_h - head_f.size) / 2), label, font=head_f, fill=(48, 49, 51))
        d.text((cx - d.textlength(label, font=head_f) / 2 + 1, y + (head_h - head_f.size) / 2), label, font=head_f, fill=(48, 49, 51))
    y += head_h
    d.line((xs[0], y, xs[-1], y), fill=(235, 238, 245))
    grey = (96, 98, 102)
    for r, row in enumerate(rows):
        values = [str(r + 1), row["orbit"], row["satellite"], row["name"], row["station"], row["start"], row["end"],
                  row["info"].replace("，", " , ")]
        for c, value in enumerate(values):
            cx = (xs[c] + xs[c + 1]) / 2
            d.text((cx - d.textlength(value, font=cell_f) / 2, y + (row_h - cell_f.size) / 2), value, font=cell_f, fill=grey)
        # 状态：绿框的小标签
        cx = (xs[8] + xs[9]) / 2
        tw = d.textlength("等待数传", font=tag_f)
        d.rectangle((cx - tw / 2 - 8 * s, y + 10 * s, cx + tw / 2 + 8 * s, y + row_h - 10 * s), outline=(103, 194, 58),
                    fill=(240, 249, 235))
        d.text((cx - tw / 2, y + (row_h - tag_f.size) / 2), "等待数传", font=tag_f, fill=(103, 194, 58))
        y += row_h
        d.line((xs[0], y, xs[-1], y), fill=(235, 238, 245))
    return img


# MARK: - 拍屏幕

def perspective_coeffs(src, dst):
    """PIL 的 PERSPECTIVE 变换系数：相机画面上的点 dst → 屏幕上的点 src"""
    a = []
    b = []
    for (x, y), (u, v) in zip(dst, src):
        a.append([x, y, 1, 0, 0, 0, -u * x, -u * y])
        a.append([0, 0, 0, x, y, 1, -v * x, -v * y])
        b += [u, v]
    return np.linalg.solve(np.array(a, dtype=float), np.array(b, dtype=float)).tolist()


def photograph(screen, size, corners, blur=1.1, noise=5.0, gain=1.0):
    """把屏幕按 corners（屏幕四个角在相机画面上的位置：左上、右上、右下、左下）拍下来"""
    arr = np.asarray(screen, dtype=np.uint8)
    h, w, _ = arr.shape
    # 每个像素拆成红绿蓝三条竖的子像素（中间留一点黑缝）
    sub = np.zeros((h * 3, w * 3, 3), dtype=np.uint8)
    for k in range(3):
        sub[:, k::3, k] = np.repeat(arr[:, :, k], 3, axis=0)
    sub[2::3, :, :] = (sub[2::3, :, :] * 0.55).astype(np.uint8)
    lit = Image.fromarray(sub)
    W, H = size
    coeffs = perspective_coeffs([(0, 0), (w * 3, 0), (w * 3, h * 3), (0, h * 3)], corners)
    # 不抗锯齿：子像素和相机像素对不齐，出彩色摩尔纹
    shot = lit.transform((W, H), Image.PERSPECTIVE, coeffs, resample=Image.BILINEAR, fillcolor=(18, 18, 20))
    out = np.asarray(shot, dtype=np.float32)
    # 屏幕发的光：子像素拆开后亮度只剩三分之一左右，补回来
    mask = np.asarray(Image.new("L", (w * 3, h * 3), 255).transform((W, H), Image.PERSPECTIVE, coeffs,
                                                                      resample=Image.BILINEAR, fillcolor=0),
                      dtype=np.float32)[:, :, None] / 255
    out = out * (2.4 * gain) * mask + out * (1 - mask)
    # 明暗不均（中间亮、四周暗）
    yy, xx = np.mgrid[0:H, 0:W]
    vignette = 1 - 0.18 * (((xx - W * 0.55) / W) ** 2 + ((yy - H * 0.45) / H) ** 2) * 2
    out *= vignette[:, :, None]
    out = np.clip(out, 0, 255).astype(np.uint8)
    img = Image.fromarray(out).filter(ImageFilter.GaussianBlur(blur))
    noisy = np.asarray(img, dtype=np.float32) + np.random.default_rng(7).normal(0, noise, (H, W, 3))
    return Image.fromarray(np.clip(noisy, 0, 255).astype(np.uint8))


def save(name, img, rows, kind, quality=80, columns=None):
    os.makedirs(OUT, exist_ok=True)
    img.save(os.path.join(OUT, name + ".jpg"), quality=quality, optimize=True)
    truth = {"kind": kind, "rules": RULES, "rows": [
        {"satellite": r["satellite"], "station": r["station"], "orbit": r["orbit"], "start": r["start"],
         "end": r["end"] if kind != "excel" else "", "emergency": r["emergency"] if kind == "excel" else None}
        for r in rows]}
    with open(os.path.join(OUT, name + ".json"), "w") as f:
        json.dump(truth, f, ensure_ascii=False, indent=1)
    print(name, img.size, os.path.getsize(os.path.join(OUT, name + ".jpg")) // 1024, "KB")


def main():
    # 1. 拍电脑上打开的导出 Excel：50 行挤满一屏，梯形变形、摩尔纹（和真的照片一样密）
    rows = plan(50)
    screen = excel_screen(rows)
    shot = photograph(screen, (4032, 3024), [(140, 60), (3990, 20), (3890, 2830), (320, 2900)])
    save("excel_photo", shot, rows, "excel", quality=72)

    # 2. 文档扫描（系统扫描会框出屏幕、扶正）：没有梯形，摩尔纹还在
    rows = plan(48)
    screen = excel_screen(rows)
    scan = photograph(screen, (3400, 1912), [(0, 0), (3400, 0), (3400, 1912), (0, 1912)], blur=0.9, noise=3)
    save("excel_scan", scan, rows, "excel", quality=78)

    # 3. 拍网页上的表：22 行，灰字，上宽下窄
    rows = plan(22)
    screen = web_screen(rows)
    shot = photograph(screen, (4032, 3024), [(260, 180), (3800, 120), (3960, 2900), (90, 2840)], blur=1.3, noise=6)
    save("web_photo", shot, rows, "web", quality=72)

    # 4. 很长的图（长截图、拼起来的长图）：70 行，干净
    rows = plan(70)
    long = web_screen(rows, width=1170, scale=2.2, tall=True)
    save("long_table", long, rows, "web", quality=80)


if __name__ == "__main__":
    main()
