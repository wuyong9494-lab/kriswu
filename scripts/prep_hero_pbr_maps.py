#!/usr/bin/env python3
"""Generate real tangent-space Normal + ORM (AO/Roughness/Metallic) PBR maps for:
1) Liu Quanwei's previously 0-normal-map body texture (extracted directly from DuelChar_liuQuanwei.glb)
2) Forged steel & worn leather maps for sculpted hero gauntlets, bracers, and Spirit Wolf/Owl GLBs.

Runs under system python3 (PIL + numpy) BEFORE Blender runs scripts/fix_hero_hands_grips_and_pbr.py.
"""
from __future__ import annotations

import io
import json
import math
import struct
from pathlib import Path
from PIL import Image, ImageFilter

REPO = Path(__file__).resolve().parents[1]
RES_DIR = REPO / "App/Resources/DuelCharacters"
ART_DIR = Path("/home/antigravity/.gemini/jetski/brain/v1/default/jetski_remote_agents_3p_devbox/f45c01f0-90cf-4537-a9d6-42bfc0dff771")
OUT_DIR = Path("/tmp/hero_pbr")
OUT_DIR.mkdir(parents=True, exist_ok=True)


def extract_liu_albedo() -> Image.Image:
    raw = (RES_DIR / "DuelChar_liuQuanwei.glb").read_bytes()
    jlen = struct.unpack_from("<I", raw, 12)[0]
    g = json.loads(raw[20:20 + jlen].decode("utf-8"))
    bin_off = 28 + jlen
    mat = next(m for m in g["materials"] if m.get("name") == "tripo_mat_2d054047")
    tex_idx = mat["pbrMetallicRoughness"]["baseColorTexture"]["index"]
    img_idx = g["textures"][tex_idx]["source"]
    img_def = g["images"][img_idx]
    bv = g["bufferViews"][img_def["bufferView"]]
    off = bin_off + bv.get("byteOffset", 0)
    data = raw[off:off + bv["byteLength"]]
    return Image.open(io.BytesIO(data)).convert("RGB")


def build_normal_and_orm(
    img: Image.Image,
    out_prefix: str,
    size: int = 1024,
    strength_fine: float = 2.6,
    strength_broad: float = 1.9,
    rough_min: float = 0.50,
    rough_max: float = 0.90,
    metal_base: float = 0.0,
    metal_gain: float = 0.14,
) -> None:
    if img.size != (size, size):
        img = img.resize((size, size), Image.Resampling.LANCZOS)
    img.save(OUT_DIR / f"{out_prefix}_albedo.jpg", quality=92)

    w, h = img.size
    rgb = img.tobytes()
    lum_img = img.convert("L")
    fine_bytes = lum_img.filter(ImageFilter.GaussianBlur(radius=0.8)).tobytes()
    broad_bytes = lum_img.filter(ImageFilter.GaussianBlur(radius=4.5)).tobytes()
    lum_bytes = lum_img.tobytes()

    norm_out = bytearray(w * h * 3)
    orm_out = bytearray(w * h * 3)
    inv255 = 1.0 / 255.0
    sf = strength_fine * inv255
    sb = strength_broad * inv255
    r_span = rough_max - rough_min

    for y in range(h):
        ym = (y - 1) * w if y > 0 else 0
        yc = y * w
        yp = (y + 1) * w if y + 1 < h else (h - 1) * w
        for x in range(w):
            xm = x - 1 if x > 0 else 0
            xp = x + 1 if x + 1 < w else w - 1
            # Fine Sobel
            gxf = (
                (fine_bytes[ym + xp] + 2 * fine_bytes[yc + xp] + fine_bytes[yp + xp])
                - (fine_bytes[ym + xm] + 2 * fine_bytes[yc + xm] + fine_bytes[yp + xm])
            )
            gyf = (
                (fine_bytes[yp + xm] + 2 * fine_bytes[yp + x] + fine_bytes[yp + xp])
                - (fine_bytes[ym + xm] + 2 * fine_bytes[ym + x] + fine_bytes[ym + xp])
            )
            # Broad Sobel
            gxb = (
                (broad_bytes[ym + xp] + 2 * broad_bytes[yc + xp] + broad_bytes[yp + xp])
                - (broad_bytes[ym + xm] + 2 * broad_bytes[yc + xm] + broad_bytes[yp + xm])
            )
            gyb = (
                (broad_bytes[yp + xm] + 2 * broad_bytes[yp + x] + broad_bytes[yp + xp])
                - (broad_bytes[ym + xm] + 2 * broad_bytes[ym + x] + broad_bytes[ym + xp])
            )
            dx = -(gxf * sf + gxb * sb)
            dy = -(gyf * sf + gyb * sb)
            inv_l = 1.0 / math.sqrt(dx * dx + dy * dy + 1.0)
            idx3 = (yc + x) * 3
            norm_out[idx3] = max(0, min(255, int((dx * inv_l * 0.5 + 0.5) * 255.0)))
            norm_out[idx3 + 1] = max(0, min(255, int((dy * inv_l * 0.5 + 0.5) * 255.0)))
            norm_out[idx3 + 2] = max(0, min(255, int((inv_l * 0.5 + 0.5) * 255.0)))

            # ORM
            li = lum_bytes[yc + x] * inv255
            fi = fine_bytes[yc + x] * inv255
            bi = broad_bytes[yc + x] * inv255
            r0, g0, b0 = rgb[idx3], rgb[idx3 + 1], rgb[idx3 + 2]
            mx = max(r0, g0, b0)
            mn = min(r0, g0, b0)
            sat = (mx - mn) / (mx + 1.0)
            cavity = max(0.36, min(1.0, 0.82 + (fi - bi) * 1.45 + (li - 0.35) * 0.38))
            rough = max(rough_min, min(rough_max, rough_max - (li * 0.30 + sat * 0.16) * r_span))
            metal = max(0.0, min(0.96, metal_base + max(0.0, li - 0.58) * metal_gain * 2.5))
            orm_out[idx3] = int(cavity * 255.0)
            orm_out[idx3 + 1] = int(rough * 255.0)
            orm_out[idx3 + 2] = int(metal * 255.0)

    Image.frombytes("RGB", (w, h), bytes(norm_out)).save(OUT_DIR / f"{out_prefix}_normal.jpg", quality=90)
    orm_im = Image.frombytes("RGB", (w, h), bytes(orm_out))
    if w > 512:
        orm_im = orm_im.resize((512, 512), Image.Resampling.LANCZOS)
    orm_im.save(OUT_DIR / f"{out_prefix}_orm.jpg", quality=88)
    print(f"[pbr] built {out_prefix}_normal.jpg ({w}x{h}) + {out_prefix}_orm.jpg ({orm_im.size[0]}x{orm_im.size[1]})")


def main() -> None:
    liu_alb = extract_liu_albedo()
    build_normal_and_orm(
        liu_alb,
        "liu_body",
        size=768,
        strength_fine=2.8,
        strength_broad=2.2,
        rough_min=0.52,
        rough_max=0.90,
        metal_base=0.0,
        metal_gain=0.12,
    )

    # Also build forged steel & leather PBR sets from our saved artifact textures
    steel_src = sorted(ART_DIR.glob("pbr_weapon_forge_*.jpg"))
    if steel_src:
        build_normal_and_orm(
            Image.open(steel_src[0]).convert("RGB"),
            "steel",
            size=512,
            strength_fine=2.0,
            strength_broad=1.2,
            rough_min=0.18,
            rough_max=0.46,
            metal_base=0.82,
            metal_gain=0.14,
        )
    leather_src = sorted(ART_DIR.glob("pbr_dark_wood_leather_*.jpg"))
    if leather_src:
        build_normal_and_orm(
            Image.open(leather_src[0]).convert("RGB"),
            "leather",
            size=512,
            strength_fine=2.5,
            strength_broad=1.6,
            rough_min=0.52,
            rough_max=0.82,
            metal_base=0.02,
            metal_gain=0.05,
        )


if __name__ == "__main__":
    main()
