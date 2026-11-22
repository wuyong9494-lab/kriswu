#!/usr/bin/env python3
"""Generate production PBR map sets (Albedo, Normal, MetallicRoughness+AO, Alpha Vines)
and true Radiance RGBE (.hdr) Equirectangular IBL Environment Light Maps for SceneKit Metal.

Run with: /home/antigravity/blender/blender --background --python scripts/build_pbr_maps_and_ibl.py
"""
from __future__ import annotations

import glob
import math
import os
import struct
from pathlib import Path
import numpy as np
import bpy

ART_DIR = Path("/home/antigravity/.gemini/jetski/brain/v1/default/jetski_remote_agents_3p_devbox/f45c01f0-90cf-4537-a9d6-42bfc0dff771")
OUT_TMP = Path("/tmp/pbr_build")
OUT_RES = Path("App/Resources/DuelCharacters")


def find_art(prefix: str) -> Path:
    matches = sorted(ART_DIR.glob(f"{prefix}_*.jpg")) + sorted(ART_DIR.glob(f"{prefix}_*.png"))
    if not matches:
        raise FileNotFoundError(f"Missing generated source artwork: {prefix}")
    return matches[-1]


def load_rgb(path: Path, target_w: int | None = None, target_h: int | None = None) -> np.ndarray:
    """Load image via Blender into float32 (H, W, 3) top-to-bottom RGB in [0, 1]."""
    img = bpy.data.images.load(str(path), check_existing=False)
    if target_w and target_h and (img.size[0] != target_w or img.size[1] != target_h):
        img.scale(target_w, target_h)
    w, h = img.size[0], img.size[1]
    buf = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(buf)
    bpy.data.images.remove(img)
    arr = buf.reshape((h, w, 4))[::-1, :, :3].copy()  # flip Blender bottom-up -> top-down
    return np.clip(arr, 0.0, 1.0)


def save_image(arr: np.ndarray, path: Path, jpeg: bool = False, quality: int = 88) -> None:
    """Save top-to-bottom float32 (H, W, 3|4) in [0,1] via Blender."""
    h, w, c = arr.shape
    flipped = arr[::-1, :, :]
    if c == 3:
        rgba = np.ones((h, w, 4), dtype=np.float32)
        rgba[:, :, :3] = np.clip(flipped, 0.0, 1.0)
    else:
        rgba = np.clip(flipped, 0.0, 1.0).astype(np.float32)
    img = bpy.data.images.new(name=path.name, width=w, height=h, alpha=(c == 4), float_buffer=False)
    img.pixels.foreach_set(rgba.ravel())
    scene = bpy.context.scene
    scene.render.image_settings.file_format = "JPEG" if jpeg else "PNG"
    scene.render.image_settings.color_mode = "RGB" if (jpeg or c == 3) else "RGBA"
    if jpeg:
        scene.render.image_settings.quality = quality
    else:
        scene.render.image_settings.compression = 80
    img.save_render(filepath=str(path), scene=scene)
    bpy.data.images.remove(img)


def box_blur_wrap(x: np.ndarray, radius: int) -> np.ndarray:
    """Fast separable tileable box blur on 2D float32 array."""
    if radius <= 0:
        return x.copy()
    out = x.copy()
    for _ in range(2):
        # Horizontal
        acc = np.zeros_like(out)
        for d in range(-radius, radius + 1):
            acc += np.roll(out, d, axis=1)
        out = acc / (2 * radius + 1)
        # Vertical
        acc = np.zeros_like(out)
        for d in range(-radius, radius + 1):
            acc += np.roll(out, d, axis=0)
        out = acc / (2 * radius + 1)
    return out


def height_to_normal(height: np.ndarray, strength_fine: float = 2.6, strength_broad: float = 1.8) -> np.ndarray:
    """Multi-scale tileable Sobel height -> tangent-space OpenGL normal map (R, G, B in [0,1])."""
    h_fine = height
    h_med = box_blur_wrap(height, 3)

    def sobel(h: np.ndarray):
        dx = (
            -np.roll(np.roll(h, 1, 0), 1, 1) + np.roll(np.roll(h, 1, 0), -1, 1)
            - 2.0 * np.roll(h, 1, 1) + 2.0 * np.roll(h, -1, 1)
            - np.roll(np.roll(h, -1, 0), 1, 1) + np.roll(np.roll(h, -1, 0), -1, 1)
        ) * 0.25
        dy = (
            -np.roll(np.roll(h, 1, 0), 1, 1) - 2.0 * np.roll(h, 1, 0) - np.roll(np.roll(h, 1, 0), -1, 1)
            + np.roll(np.roll(h, -1, 0), 1, 1) + 2.0 * np.roll(h, -1, 0) + np.roll(np.roll(h, -1, 0), -1, 1)
        ) * 0.25
        return dx, dy

    dx1, dy1 = sobel(h_fine)
    dx2, dy2 = sobel(h_med)
    # glTF/OpenGL tangent normal: +X right, +Y up (top-down array means -dy for +Y up)
    nx = -(dx1 * strength_fine + dx2 * strength_broad)
    ny = (dy1 * strength_fine + dy2 * strength_broad)
    nz = np.ones_like(nx)
    inv_len = 1.0 / np.sqrt(nx * nx + ny * ny + nz * nz + 1e-8)
    n = np.stack([nx * inv_len * 0.5 + 0.5, ny * inv_len * 0.5 + 0.5, nz * inv_len * 0.5 + 0.5], axis=-1)
    return np.clip(n, 0.0, 1.0)


def build_pbr_material_set(
    name: str,
    src_path: Path,
    size: int,
    rough_range: tuple[float, float],
    metal_range: tuple[float, float],
    normal_fine: float,
    normal_broad: float,
    ao_strength: float = 0.55,
    albedo_lift: float = 1.0,
    moss_rough_boost: bool = False,
) -> None:
    rgb = load_rgb(src_path, size, size)
    # Subtle contrast & tone control
    if albedo_lift != 1.0:
        rgb = np.clip(rgb * albedo_lift, 0.0, 1.0)
    lum = 0.299 * rgb[:, :, 0] + 0.587 * rgb[:, :, 1] + 0.114 * rgb[:, :, 2]

    # Height proxy from luminance + local contrast
    broad = box_blur_wrap(lum, 10)
    height = np.clip(0.65 * lum + 0.35 * np.clip(lum - broad + 0.5, 0.0, 1.0), 0.0, 1.0)
    normal = height_to_normal(height, strength_fine=normal_fine, strength_broad=normal_broad)

    # Cavity Ambient Occlusion (R channel of ORM texture)
    cavity = np.clip((lum - broad) * 2.4 + 0.82, 0.0, 1.0)
    ao = np.clip(1.0 - ao_strength * (1.0 - np.minimum(cavity, np.clip(lum * 1.45, 0.0, 1.0))), 0.28, 1.0)

    # Roughness (G channel): darker recesses rougher, worn highlights smoother
    r_lo, r_hi = rough_range
    rough = r_hi - (r_hi - r_lo) * np.clip((lum - 0.12) / 0.65, 0.0, 1.0)
    if moss_rough_boost:
        # Green moss/earth pockets stay matte while worn stone slabs catch wet/polished specular sheen
        green_excess = np.clip((rgb[:, :, 1] - np.maximum(rgb[:, :, 0], rgb[:, :, 2])) * 4.5, 0.0, 1.0)
        rough = np.clip(rough + green_excess * 0.24, 0.0, 0.98)

    # Metalness (B channel)
    m_lo, m_hi = metal_range
    metal = m_lo + (m_hi - m_lo) * np.clip((lum - 0.15) / 0.60, 0.0, 1.0)

    orm = np.stack([ao, np.clip(rough, 0.04, 0.99), np.clip(metal, 0.0, 1.0)], axis=-1)

    save_image(rgb, OUT_TMP / f"{name}_albedo.jpg", jpeg=True, quality=88)
    # 512px normal + ORM preserves razor-sharp PBR specular/bump while keeping mobile GLB under ~4.5 MB
    if size >= 1024:
        normal_out = normal.reshape(size // 2, 2, size // 2, 2, 3).mean(axis=(1, 3))
        # Re-normalize averaged normals
        nv = normal_out * 2.0 - 1.0
        nlen = np.sqrt(np.sum(nv * nv, axis=-1, keepdims=True) + 1e-8)
        normal_out = np.clip((nv / nlen) * 0.5 + 0.5, 0.0, 1.0)
        orm_out = orm.reshape(size // 2, 2, size // 2, 2, 3).mean(axis=(1, 3))
    else:
        normal_out = normal
        orm_out = orm
    save_image(normal_out, OUT_TMP / f"{name}_normal.png", jpeg=False)
    save_image(orm_out, OUT_TMP / f"{name}_orm.png", jpeg=False)
    print(f"[pbr] built {name} (albedo={size}, norm/orm={normal_out.shape[0]}) rough={rough_range} metal={metal_range}")


def build_crimson_vines_atlas(src_path: Path) -> None:
    """Convert white-background botanical sheet into crisp defringed RGBA alpha-cutout 1024x1024 + normal."""
    rgb = load_rgb(src_path, 1024, 1024)
    # Pure white background has high min(R,G,B) and low saturation
    cmin = np.min(rgb, axis=-1)
    cmax = np.max(rgb, axis=-1)
    sat = cmax - cmin
    # Pixels near white with very low saturation are background
    bg_score = np.clip((cmin - 0.80) / 0.16, 0.0, 1.0) * np.clip(1.0 - sat * 4.5, 0.0, 1.0)
    alpha = np.clip(1.0 - bg_score, 0.0, 1.0)
    # Crisp clean botanical silhouette cutoff with 1px soft anti-aliased fringe
    alpha = np.clip((alpha - 0.18) / 0.55, 0.0, 1.0)

    # Defringe: push interior leaf RGB outward into semi-transparent/empty border pixels so mipmaps never bleed white!
    solid = alpha > 0.72
    defringed = rgb.copy()
    mask = solid.copy()
    for _ in range(10):
        # Average of 4-neighbors that are already valid
        num = np.zeros_like(defringed)
        den = np.zeros((1024, 1024, 1), dtype=np.float32)
        for dy, dx in [(-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (1, 1), (-1, 1), (1, -1)]:
            m_s = np.roll(np.roll(mask, dy, axis=0), dx, axis=1)
            r_s = np.roll(np.roll(defringed, dy, axis=0), dx, axis=1)
            num += r_s * m_s[:, :, None]
            den += m_s[:, :, None]
        fill = (~mask) & (den[:, :, 0] > 0.5)
        if not np.any(fill):
            break
        defringed[fill] = num[fill] / den[fill]
        mask[fill] = True

    # Slightly deepen crimson/moss richness for dramatic sunlit foliage contrast
    defringed = np.clip(defringed * np.array([0.92, 0.88, 0.86], dtype=np.float32), 0.0, 1.0)

    # Extract 4 lush isolated hanging vine tendrils cleanly with zero bleed from neighboring rows
    crops = [
        (0, 488, 6, 200),       # quadrant 0: top-left lush crimson maple + dark ivy
        (0, 412, 345, 510),     # quadrant 1: top-mid crimson maple cluster
        (0, 365, 512, 686),     # quadrant 2: top-mid-right lush ivy + crimson
        (498, 1018, 6, 198),    # quadrant 3: bottom-left super lush crimson drape
    ]
    atlas_rgba = np.zeros((1024, 1024, 4), dtype=np.float32)
    # Fill empty atlas RGB with dark burgundy-bark so mipmaps stay dark
    atlas_rgba[:, :, :3] = np.array([0.16, 0.07, 0.06], dtype=np.float32)

    for idx, (y0, y1, x0, x1) in enumerate(crops):
        sub_rgb = defringed[y0:y1, x0:x1]
        sub_a = alpha[y0:y1, x0:x1]
        # Nearest/bilinear resize to 496x496 centered inside 512x512 quadrant with 8px margin
        sh, sw = sub_a.shape
        gy = np.linspace(0, sh - 1, 496)
        gx = np.linspace(0, sw - 1, 496)
        iy = np.clip(np.round(gy).astype(np.int32), 0, sh - 1)
        ix = np.clip(np.round(gx).astype(np.int32), 0, sw - 1)
        tile_rgb = sub_rgb[iy[:, None], ix[None, :]]
        tile_a = sub_a[iy[:, None], ix[None, :]]

        qr, qc = divmod(idx, 2)
        oy, ox = qr * 512 + 8, qc * 512 + 8
        atlas_rgba[oy:oy + 496, ox:ox + 496, :3] = tile_rgb
        atlas_rgba[oy:oy + 496, ox:ox + 496, 3] = tile_a

    # Synthesize leaf vein normal map
    lum = 0.299 * atlas_rgba[:, :, 0] + 0.587 * atlas_rgba[:, :, 1] + 0.114 * atlas_rgba[:, :, 2]
    leaf_norm = height_to_normal(lum * atlas_rgba[:, :, 3], strength_fine=2.0, strength_broad=1.0)

    save_image(atlas_rgba, OUT_TMP / "vines_atlas_rgba.png", jpeg=False)
    save_image(leaf_norm, OUT_TMP / "vines_atlas_normal.png", jpeg=False)
    print(f"[pbr] built vines_atlas_rgba.png (coverage={float(np.mean(atlas_rgba[:,:,3] > 0.5))*100:.1f}%)")


def write_radiance_hdr(rgb_linear: np.ndarray, path: Path) -> None:
    """Write standard uncompressed Radiance RGBE .hdr (universally decoded by SceneKit / Apple ImageIO)."""
    h, w, _ = rgb_linear.shape
    rgb = np.maximum(rgb_linear.astype(np.float32), 0.0)
    max_c = np.max(rgb, axis=-1)
    rgbe = np.zeros((h, w, 4), dtype=np.uint8)
    nz = max_c > 1e-32
    mant, exp = np.frexp(max_c[nz])
    scale = (mant * 256.0) / max_c[nz]
    rgbe[nz, 0] = np.clip(rgb[nz, 0] * scale, 0, 255).astype(np.uint8)
    rgbe[nz, 1] = np.clip(rgb[nz, 1] * scale, 0, 255).astype(np.uint8)
    rgbe[nz, 2] = np.clip(rgb[nz, 2] * scale, 0, 255).astype(np.uint8)
    rgbe[nz, 3] = np.clip(exp + 128, 0, 255).astype(np.uint8)

    header = f"#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y {h} +X {w}\n".encode("ascii")
    with open(path, "wb") as f:
        f.write(header)
        f.write(rgbe.tobytes())
    print(f"[ibl] wrote {path} ({w}x{h}, {path.stat().st_size // 1024} KB, maxRadiance={float(np.max(rgb)):.2f})")


def build_sky_and_hdr_ibls(sky_path: Path) -> None:
    """Export crisp sky cyclorama panorama + synthesize Sunlit & Shadow World Radiance .hdr IBLs."""
    sky_pano = load_rgb(sky_path, 1536, 864)
    # Save crisp sky panorama for our Blender 3D stage cyclorama dome
    save_image(sky_pano, OUT_TMP / "sanctuary_sky_pano.jpg", jpeg=True, quality=90)

    # Build 512x256 equirectangular HDR environment maps
    W, H = 512, 256
    sky_small = load_rgb(sky_path, W, H // 2)
    # sRGB -> linear
    sky_lin = np.power(np.clip(sky_small, 0.0, 1.0), 2.2)

    # --- 1. SUNLIT COURTYARD HDR IBL ---
    u = np.linspace(0.0, 1.0, W, endpoint=False)[None, :]      # azimuth [0, 1) -> [-pi, pi)
    v = np.linspace(0.0, 1.0, H, endpoint=False)[:, None]      # polar [0, 1] -> [0, pi]
    theta = v * math.pi
    phi = (u - 0.5) * 2.0 * math.pi
    # Direction vector (Y up, -Z forward, +X right)
    dx = np.sin(theta) * np.sin(phi)
    dy = np.cos(theta)
    dz = -np.sin(theta) * np.cos(phi)

    env_sun = np.zeros((H, W, 3), dtype=np.float32)
    # Upper hemisphere from painted sunlit sky (boosted gently for rich PBR sky bounce)
    env_sun[:H // 2, :, :] = sky_lin * 1.45
    # Lower hemisphere: warm earthy mossy courtyard bounce (prevents black underside reflections!)
    ground_t = np.clip((v[H // 2:, :] - 0.5) * 2.0, 0.0, 1.0)
    horizon_row = sky_lin[-1:, :, :] * 0.72
    earth_col = np.array([0.14, 0.13, 0.095], dtype=np.float32)[None, None, :]
    env_sun[H // 2:, :, :] = horizon_row * (1.0 - ground_t[:, :, None]) + earth_col * ground_t[:, :, None]

    # Add true HDR golden solar specular hotspot matching our SceneKit directional key light (upper-left-front)
    sun_dir = np.array([-0.48, 0.62, 0.62], dtype=np.float32)
    sun_dir /= np.linalg.norm(sun_dir)
    sun_dot = np.clip(dx * sun_dir[0] + dy * sun_dir[1] + dz * sun_dir[2], 0.0, 1.0)
    sun_disk = np.power(sun_dot, 90.0) * 14.0 + np.power(sun_dot, 12.0) * 2.2
    env_sun += sun_disk[:, :, None] * np.array([1.0, 0.88, 0.68], dtype=np.float32)[None, None, :]

    # Add cool misty-sky back-rim specular highlight lobe (upper-back) so blades gleam on BOTH sides!
    rim_dir = np.array([0.32, 0.55, -0.77], dtype=np.float32)
    rim_dir /= np.linalg.norm(rim_dir)
    rim_dot = np.clip(dx * rim_dir[0] + dy * rim_dir[1] + dz * rim_dir[2], 0.0, 1.0)
    rim_lobe = np.power(rim_dot, 22.0) * 4.5
    env_sun += rim_lobe[:, :, None] * np.array([0.74, 0.88, 1.0], dtype=np.float32)[None, None, :]

    write_radiance_hdr(env_sun, OUT_RES / "DuelEnv_Sunlit.hdr")

    # --- 2. SHADOW WORLD MONOCHROME INK + ICE-CYAN RIM HDR IBL ---
    env_shad = np.zeros((H, W, 3), dtype=np.float32)
    # Deep obsidian-ink sky dome with subtle cold silver zenith
    zenith = np.clip(dy, 0.0, 1.0)
    env_shad[:, :, 0] = 0.05 + 0.16 * np.power(zenith, 1.6)
    env_shad[:, :, 1] = 0.06 + 0.21 * np.power(zenith, 1.5)
    env_shad[:, :, 2] = 0.08 + 0.28 * np.power(zenith, 1.4)
    # Twin blazing electric ice-cyan studio rim arcs for obsidian-chrome SF4 Shadow Form!
    for rdir, power, gain, col in [
        (np.array([-0.55, 0.45, -0.70]), 28.0, 11.0, np.array([0.24, 0.86, 1.0])),
        (np.array([0.55, 0.52, -0.65]), 28.0, 9.5, np.array([0.38, 0.90, 1.0])),
        (np.array([0.0, 0.88, 0.46]), 16.0, 3.8, np.array([0.82, 0.92, 1.0])),
    ]:
        rdir = rdir / np.linalg.norm(rdir)
        rdot = np.clip(dx * rdir[0] + dy * rdir[1] + dz * rdir[2], 0.0, 1.0)
        env_shad += (np.power(rdot, power) * gain)[:, :, None] * col[None, None, :]

    write_radiance_hdr(env_shad, OUT_RES / "DuelEnv_Shadow.hdr")

    # Also save tone-mapped LDR preview of both HDRs to /tmp/pbr_build for quick inspection
    def tonemap(hdr: np.ndarray) -> np.ndarray:
        mapped = hdr / (1.0 + hdr)
        return np.power(np.clip(mapped, 0.0, 1.0), 1.0 / 2.2)

    save_image(tonemap(env_sun), OUT_TMP / "env_sunlit_preview.jpg", jpeg=True, quality=88)
    save_image(tonemap(env_shad), OUT_TMP / "env_shadow_preview.jpg", jpeg=True, quality=88)


def main() -> None:
    OUT_TMP.mkdir(parents=True, exist_ok=True)
    OUT_RES.mkdir(parents=True, exist_ok=True)

    build_pbr_material_set(
        "ground", find_art("pbr_courtyard_ground"), size=1024,
        rough_range=(0.50, 0.94), metal_range=(0.0, 0.02),
        normal_fine=3.2, normal_broad=2.4, ao_strength=0.65,
        albedo_lift=0.94, moss_rough_boost=True,
    )
    build_pbr_material_set(
        "earth_moss", find_art("pbr_packed_earth_moss"), size=1024,
        rough_range=(0.76, 0.97), metal_range=(0.0, 0.0),
        normal_fine=2.8, normal_broad=2.0, ao_strength=0.60,
        albedo_lift=0.90, moss_rough_boost=True,
    )
    build_pbr_material_set(
        "masonry", find_art("pbr_ruin_masonry"), size=1024,
        rough_range=(0.62, 0.94), metal_range=(0.0, 0.03),
        normal_fine=3.4, normal_broad=2.6, ao_strength=0.68,
        albedo_lift=0.96, moss_rough_boost=True,
    )
    build_pbr_material_set(
        "steel", find_art("pbr_weapon_forge"), size=512,
        rough_range=(0.16, 0.42), metal_range=(0.86, 0.98),
        normal_fine=2.0, normal_broad=1.1, ao_strength=0.45,
        albedo_lift=1.08,
    )
    build_pbr_material_set(
        "dark_wood", find_art("pbr_dark_wood_leather"), size=512,
        rough_range=(0.56, 0.88), metal_range=(0.02, 0.06),
        normal_fine=3.0, normal_broad=1.8, ao_strength=0.58,
        albedo_lift=1.05,
    )
    build_crimson_vines_atlas(find_art("pbr_crimson_vines"))
    build_sky_and_hdr_ibls(find_art("pbr_sanctuary_sky"))
    print("[pbr] ALL PBR MAPS + HDR IBLS COMPLETE!")


if __name__ == "__main__":
    main()
