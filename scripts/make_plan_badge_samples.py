#!/usr/bin/env python3
"""Create deterministic, entirely fictional OCR badge/overlap fixtures.

This script reads no user photographs. Supply a Chinese font, for example
NotoSansCJKsc-Regular.otf, with --font. Only generated JPEGs and JSON belong in
the repository; the font remains a local build dependency.
"""
import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


OUT = Path(__file__).resolve().parents[1] / "Tests" / "SiteTests" / "OCRSamples"
RULES = {"演示甲": ["样例甲"], "演示乙": ["样例乙"]}
COLUMNS = [("", 130), ("No.", 96), ("圈号", 120), ("卫星ID", 180),
           ("卫星名称", 170), ("地面站", 220), ("数传开始时间", 290),
           ("数传结束时间", 290), ("数传信息", 310), ("状态", 160)]


def plans():
    rows = []
    for n in range(1, 7):
        family = "甲" if n % 2 else "乙"
        rows.append({
            "number": n,
            "satellite": f"DEMO{chr(64 + n)}1",
            "name": f"模拟{n}号",
            "station": f"样例{family}-园区{n:02d}",
            "orbit": str(5100 + n),
            "start": f"2032-04-12 {n + 7:02d}:00:00",
            "end": f"2032-04-12 {n + 7:02d}:08:00",
            "info": "通道test说明：应急演练" if n == 6 else "通道1:800M",
            "emergency": n in (3, 4, 5),
            "status": "TeSt" if n == 4 else ("数传成功" if n == 5 else "等待数传"),
            "excluded": n == 4,
            # Red background alone is deliberately NOT an emergency signal.
            "red_background": n in (2, 3, 4, 5),
        })
    return rows


def page(rows, font_path, *, left, width, hidden_badges=()):
    title_font = ImageFont.truetype(font_path, 24)
    head_font = ImageFont.truetype(font_path, 24)
    cell_font = ImageFont.truetype(font_path, 22)
    tag_font = ImageFont.truetype(font_path, 23)
    top, header_height, row_height = 92, 68, 80
    height = top + header_height + len(rows) * row_height + 42
    image = Image.new("RGB", (width, height), "white")
    draw = ImageDraw.Draw(image)
    draw.text((left, 28), "合成演示用计划 · 不含实际任务信息", font=title_font, fill="#40566a")
    xs = [left]
    for _, column_width in COLUMNS:
        xs.append(xs[-1] + column_width)
    draw.line((left, top, xs[-1], top), fill="#e9b25b", width=3)
    for c, (label, _) in enumerate(COLUMNS):
        draw.text(((xs[c] + xs[c + 1]) / 2, top + header_height / 2), label,
                  font=head_font, fill="#202830", anchor="mm")
    for r, row in enumerate(rows):
        y = top + header_height + r * row_height
        if row["red_background"]:
            draw.rectangle((left, y, xs[-1], y + row_height), fill="#fae5e8")
        values = ["", str(row["number"]), row["orbit"], row["satellite"], row["name"],
                  row["station"], row["start"], row["end"], row["info"], row["status"]]
        for c, value in enumerate(values):
            x, cy = (xs[c] + xs[c + 1]) / 2, y + row_height / 2
            if c == len(COLUMNS) - 1:
                color = "#a02740" if row["excluded"] else "#22684f"
                tw = draw.textlength(value, font=tag_font)
                draw.rounded_rectangle((x - tw / 2 - 10, cy - 22, x + tw / 2 + 10, cy + 22),
                                       radius=3, outline=color, width=2)
                draw.text((x, cy), value, font=tag_font, fill=color, anchor="mm")
            elif value:
                draw.text((x, cy), value, font=cell_font, fill="#30343a", anchor="mm")
        if row["emergency"] and row["number"] not in hidden_badges:
            x, cy = (xs[0] + xs[1]) / 2, y + row_height / 2
            draw.rectangle((x - 35, cy - 23, x + 35, cy + 23), outline="#b6394e", width=2)
            draw.text((x, cy), "应急", font=tag_font, fill="#a7263d", anchor="mm")
        draw.line((left, y + row_height, xs[-1], y + row_height), fill="#d7dbe0", width=1)
    return image


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--font", type=Path, required=True)
    args = parser.parse_args()
    rows = plans()
    OUT.mkdir(parents=True, exist_ok=True)
    # Rows 3/4 overlap. Page 2 omits row 3's badge to exercise evidence retention.
    # A changed horizontal margin also requires reading the new page's header.
    names = ["badge_overlap_1", "badge_overlap_2"]
    page(rows[:4], args.font, left=48, width=2110).save(OUT / f"{names[0]}.jpg", quality=94, optimize=True)
    page(rows[2:], args.font, left=128, width=2290, hidden_badges=(3,)).save(
        OUT / f"{names[1]}.jpg", quality=94, optimize=True)
    truth = {"kind": "fictional_headerless_badges", "pages": names, "rules": RULES, "rows": rows}
    (OUT / "badge_overlap.json").write_text(json.dumps(truth, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    for name in names:
        print(f"{name}.jpg: {(OUT / (name + '.jpg')).stat().st_size} bytes")


if __name__ == "__main__":
    main()
