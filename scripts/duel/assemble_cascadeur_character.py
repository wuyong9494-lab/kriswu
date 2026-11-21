#!/usr/bin/env python3
"""Blender 4.2 auto-assembler for Meshy + Cascadeur characters and weapons.

Supports two workflows:
  1) Character body (with head already swapped by user, or optional --head-glb)
     + folder of Cascadeur per-action FBX files -> merges all actions into clean
     NLA tracks, adds explicit `weapon_socket_r` / `weapon_socket_l` empties on
     the hand bones, compresses textures to <=1024 px, and exports a single
     mobile-ready `.glb` (<5 MB) for `DuelCascadeurCharacterAsset`.
  2) Standalone weapon FBX/GLB (`--weapon-only`) -> normalizes scale/origin
     and exports `DuelWeapon_<hero>.glb` ready to mount on `weapon_socket_r`.

Usage examples (run with Blender 4.2+):
  ~/blender/blender -b --python scripts/duel/assemble_cascadeur_character.py -- \\
      --base /path/to/wuyong_body.fbx \\
      --anims-dir /path/to/wuyong_cascadeur_fbx/ \\
      --output App/Resources/DuelCharacters/DuelChar_wuyong.glb

  ~/blender/blender -b --python scripts/duel/assemble_cascadeur_character.py -- \\
      --weapon-only /path/to/odachi.fbx \\
      --weapon-length 1.45 \\
      --output App/Resources/DuelCharacters/DuelWeapon_wuyong.glb
"""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

import bpy
from mathutils import Vector

RIGHT_HAND_CANDIDATES = (
    "weapon_socket_r", "weapon_r", "Weapon_R", "RightHand", "mixamorig:RightHand",
    "hand_r", "hand.R", "Hand_R", "R_Hand", "Bip001 R Hand", "J_Bip_R_Hand", "wrist_r",
)
LEFT_HAND_CANDIDATES = (
    "weapon_socket_l", "weapon_l", "Weapon_L", "LeftHand", "mixamorig:LeftHand",
    "hand_l", "hand.L", "Hand_L", "L_Hand", "Bip001 L Hand", "J_Bip_L_Hand", "wrist_l",
)
HEAD_CANDIDATES = (
    "Head", "head", "mixamorig:Head", "Bip001 Head", "J_Bip_C_Head",
)


def parse_args() -> argparse.Namespace:
    argv = sys.argv
    if "--" in argv:
        argv = argv[argv.index("--") + 1:]
    else:
        argv = []
    p = argparse.ArgumentParser(description="Assemble Meshy + Cascadeur FBX/GLB into mobile Duel GLB.")
    p.add_argument("--base", type=str, help="Base rigged character .fbx or .glb")
    p.add_argument("--anims-dir", type=str, default=None, help="Directory of Cascadeur per-action .fbx/.glb clips")
    p.add_argument("--weapon-only", type=str, default=None, help="Normalize a standalone weapon .fbx/.glb")
    p.add_argument("--weapon-length", type=float, default=1.35, help="Target blade length in meters for --weapon-only")
    p.add_argument("--target-height", type=float, default=1.82, help="Target standing character height in meters")
    p.add_argument("--max-texture", type=int, default=1024, help="Maximum texture edge in pixels")
    p.add_argument("--jpeg-quality", type=int, default=85, help="JPEG quality for glTF texture compression")
    p.add_argument("--output", type=str, required=True, help="Output .glb path")
    return p.parse_args(argv)


def clear_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_asset(path: Path) -> list[bpy.types.Object]:
    before = set(bpy.data.objects)
    ext = path.suffix.lower()
    if ext == ".fbx":
        bpy.ops.import_scene.fbx(
            filepath=str(path),
            use_anim=True,
            ignore_leaf_bones=False,
            automatic_bone_orientation=False,
        )
    elif ext in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(filepath=str(path))
    elif ext == ".obj":
        bpy.ops.wm.obj_import(filepath=str(path))
    else:
        raise ValueError(f"Unsupported format: {path}")
    return [obj for obj in bpy.data.objects if obj not in before]


def find_armature(objects: list[bpy.types.Object]) -> bpy.types.Object | None:
    for obj in objects:
        if obj.type == "ARMATURE":
            return obj
    return None


def find_bone(armature: bpy.types.Object, candidates: tuple[str, ...]) -> bpy.types.Bone | None:
    bones = armature.data.bones
    for name in candidates:
        if name in bones:
            return bones[name]
    lower_map = {b.name.lower(): b for b in bones}
    for name in candidates:
        if name.lower() in lower_map:
            return lower_map[name.lower()]
    for name in candidates:
        low = name.lower()
        for bname, bone in lower_map.items():
            if bname.endswith(low) or low in bname:
                return bone
    return None


def compute_world_bounds(meshes: list[bpy.types.Object]) -> tuple[Vector, Vector]:
    xs, ys, zs = [], [], []
    for obj in meshes:
        for corner in obj.bound_box:
            w = obj.matrix_world @ Vector(corner)
            xs.append(w.x)
            ys.append(w.y)
            zs.append(w.z)
    if not xs:
        return Vector((0, 0, 0)), Vector((0, 0, 1.82))
    return Vector((min(xs), min(ys), min(zs))), Vector((max(xs), max(ys), max(zs)))


def resize_textures(max_size: int) -> None:
    for img in bpy.data.images:
        if img.size[0] == 0 or img.size[1] == 0:
            continue
        w, h = img.size[0], img.size[1]
        if max(w, h) > max_size:
            scale = max_size / float(max(w, h))
            nw = max(16, int(round(w * scale)))
            nh = max(16, int(round(h * scale)))
            print(f"[texture] resizing {img.name}: {w}x{h} -> {nw}x{nh}")
            img.scale(nw, nh)
            img.pack()


def attach_weapon_socket(armature: bpy.types.Object, socket_name: str, bone: bpy.types.Bone) -> None:
    empty = bpy.data.objects.new(socket_name, None)
    empty.empty_display_type = "ARROWS"
    empty.empty_display_size = 0.12
    bpy.context.scene.collection.objects.link(empty)
    empty.parent = armature
    empty.parent_type = "BONE"
    empty.parent_bone = bone.name
    empty.location = (0.0, 0.0, 0.0)
    print(f"[socket] attached {socket_name} -> bone '{bone.name}'")


def merge_animation_clips(base_arm: bpy.types.Object, anims_dir: Path) -> int:
    if not base_arm.animation_data:
        base_arm.animation_data_create()
    base_bones = {b.name for b in base_arm.data.bones}
    imported = 0

    for clip_path in sorted(anims_dir.iterdir()):
        if clip_path.suffix.lower() not in (".fbx", ".glb", ".gltf"):
            continue
        clip_name = clip_path.stem.strip()
        before_actions = set(bpy.data.actions)
        new_objs = import_asset(clip_path)
        new_actions = [a for a in bpy.data.actions if a not in before_actions]
        clip_arm = find_armature(new_objs)

        chosen_action = None
        if clip_arm and clip_arm.animation_data and clip_arm.animation_data.action:
            chosen_action = clip_arm.animation_data.action
        elif new_actions:
            chosen_action = max(new_actions, key=lambda a: len(a.fcurves))

        if chosen_action:
            chosen_action.name = clip_name
            chosen_action.use_fake_user = True
            # Remap bone paths if prefix (e.g. mixamorig:) differs slightly.
            for fc in chosen_action.fcurves:
                if fc.data_path.startswith('pose.bones["'):
                    bname = fc.data_path.split('"')[1]
                    if bname not in base_bones:
                        tail = bname.split(":")[-1].lower()
                        for target in base_bones:
                            if target.split(":")[-1].lower() == tail:
                                fc.data_path = fc.data_path.replace(f'"{bname}"', f'"{target}"', 1)
                                break
            track = base_arm.animation_data.nla_tracks.new()
            track.name = clip_name
            start_frame = int(round(chosen_action.frame_range[0]))
            strip = track.strips.new(clip_name, start_frame, chosen_action)
            strip.name = clip_name
            imported += 1
            print(f"[anim] merged '{clip_name}' ({int(chosen_action.frame_range[1] - chosen_action.frame_range[0])} frames)")

        # Remove imported temporary objects/meshes.
        for obj in new_objs:
            bpy.data.objects.remove(obj, do_unlink=True)
    base_arm.animation_data.action = None
    return imported


def export_glb(output: Path, jpeg_quality: int) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(output),
        export_format="GLB",
        export_texcoords=True,
        export_normals=True,
        export_materials="EXPORT",
        export_image_format="JPEG",
        export_jpeg_quality=jpeg_quality,
        export_animations=True,
        export_nla_strips=True,
        export_skins=True,
        export_def_bones=False,
        export_yup=True,
    )
    size_mb = output.stat().st_size / (1024 * 1024)
    print(f"[done] exported {output} ({size_mb:.2f} MB)")


def assemble_weapon(args: argparse.Namespace) -> None:
    clear_scene()
    objs = import_asset(Path(args.weapon_only))
    meshes = [o for o in objs if o.type == "MESH"]
    if not meshes:
        raise RuntimeError("No meshes found in weapon file")
    bpy.context.view_layer.update()
    mn, mx = compute_world_bounds(meshes)
    dims = mx - mn
    longest = max(dims.x, dims.y, dims.z)
    if longest > 1e-4:
        scale = args.weapon_length / longest
        for o in objs:
            if o.parent is None:
                o.scale = (o.scale.x * scale, o.scale.y * scale, o.scale.z * scale)
        bpy.context.view_layer.update()
        mn, mx = compute_world_bounds(meshes)
        # Put grip near 20% from the base of the weapon's longest axis.
        center = (mn + mx) * 0.5
        offset = Vector((-center.x, -center.y, -(mn.z + (mx.z - mn.z) * 0.20)))
        for o in objs:
            if o.parent is None:
                o.location += offset
    resize_textures(args.max_texture)
    export_glb(Path(args.output), args.jpeg_quality)


def assemble_character(args: argparse.Namespace) -> None:
    clear_scene()
    base_path = Path(args.base)
    base_objs = import_asset(base_path)
    arm = find_armature(base_objs)
    meshes = [o for o in base_objs if o.type == "MESH"]
    if not arm:
        raise RuntimeError(f"No Armature found in {base_path}")

    # Preserve any base action already inside the base FBX/GLB.
    if arm.animation_data and arm.animation_data.action:
        base_act = arm.animation_data.action
        base_act.name = "idle"
        track = arm.animation_data.nla_tracks.new()
        track.name = "idle"
        track.strips.new("idle", int(round(base_act.frame_range[0])), base_act)
        arm.animation_data.action = None

    if args.anims_dir:
        count = merge_animation_clips(arm, Path(args.anims_dir))
        print(f"[info] total merged animation clips: {count}")

    # Normalize character height to target_height (Z-up in Blender -> Y-up in glTF).
    bpy.context.view_layer.update()
    mn, mx = compute_world_bounds(meshes)
    height = mx.z - mn.z
    if height > 1e-3 and abs(height - args.target_height) > 0.05:
        s = args.target_height / height
        arm.scale = (arm.scale.x * s, arm.scale.y * s, arm.scale.z * s)
        bpy.context.view_layer.update()
        mn, mx = compute_world_bounds(meshes)
        arm.location.z -= mn.z
        print(f"[scale] normalized height {height:.3f}m -> {args.target_height:.3f}m")

    # Add explicit right/left-hand weapon sockets for DuelCascadeurCharacterAsset.
    if r_bone := find_bone(arm, RIGHT_HAND_CANDIDATES):
        attach_weapon_socket(arm, "weapon_socket_r", r_bone)
    if l_bone := find_bone(arm, LEFT_HAND_CANDIDATES):
        attach_weapon_socket(arm, "weapon_socket_l", l_bone)

    resize_textures(args.max_texture)
    export_glb(Path(args.output), args.jpeg_quality)


def main() -> None:
    args = parse_args()
    if args.weapon_only:
        assemble_weapon(args)
    elif args.base:
        assemble_character(args)
    else:
        raise SystemExit("Specify either --base <character.fbx> or --weapon-only <weapon.fbx>")


if __name__ == "__main__":
    main()
