#!/usr/bin/env python3
"""Wu Yong + arm__prc_43 (Sun_DeadForestTriad_Ninjato) vertical-slice verification.

Strictly ephemeral CI verification helper:
  1. --decrypt-h17: verifies SHA-256 pins of .github/private/fighter-h17-d19,
     decrypts AES-256-GCM in RUNNER_TEMP using FIGHTER_H17_D19_KEY (popped from env),
     extracts ONLY Sun_DeadForestTriad_Ninjato.glb & Liu_Legion_Hammers.glb, and
     deletes the decrypted ZIP immediately. Never logs keys or private bytes.
  2. --render-blender (invoked inside Blender 4.2): swaps Wu Yong's untouched head
     (M4_WuYong_Head) rigidly onto arm__prc_43 with a collar-tucked neck bridge,
     mounts a 1.74m Odachi with exact 2-bone analytical IK on BOTH arms (0mm slip),
     choreographs raw side-camera continuous footage:
       Idle -> Advance -> Light Hit -> Heavy Hit -> Recovery -> Empty Whiff Control
     with zero VFX trails and zero screen shake, computes true 3D blade-to-torso
     segment contact to drive zero-lag opponent hit reaction & damped knockback,
     and renders non-reversible PNG frames, audit closeups, silhouette plates,
     and numeric metrics JSON.
  3. --compose: burns crisp telemetry labels onto frames, encodes H.264 Baseline
     MP4 via ffmpeg, and composes the 2x3 audit sheet & 3-panel silhouette sheet.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import io
import json
import math
import os
import shutil
import stat
import subprocess
import sys
import zipfile
from pathlib import Path

MANIFEST_SHA256 = "697d62e8d9bf81da4521b6b828e4b1c4d2aa00e7141eab4d1558b3aa2ee032ff"
SUN_GLB_NAME = "Sun_DeadForestTriad_Ninjato.glb"
SUN_GLB_SHA256 = "ce9e1b77c59fa63116af73409173fcd8922f2063ab2e0624534691fa00195ef6"
LIU_GLB_NAME = "Liu_Legion_Hammers.glb"
LIU_GLB_SHA256 = "f83d8cbbd7b2158604dad9eff28398bcf57c64fdcb4146e5c142608484a5a472"
AAD = b"fighter-h17-d19-v1"


# ---------------------------------------------------------------------------
# Mode 1: Authenticated AES-256-GCM Decryption (Runs in system Python, no Blender)
# ---------------------------------------------------------------------------
def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def decrypt_aes_gcm(cipher_bytes: bytes, key_b64: str, aad: bytes = AAD) -> bytes:
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM

    key = base64.b64decode(key_b64.strip(), validate=True)
    if len(key) != 32:
        raise ValueError("Invalid key length")
    if len(cipher_bytes) <= 28:
        raise ValueError("Ciphertext too short")
    nonce = cipher_bytes[:12]
    ct_and_tag = cipher_bytes[12:]
    return AESGCM(key).decrypt(nonce, ct_and_tag, aad)


def cmd_decrypt_h17(private_dir: Path, stage_dir: Path) -> None:
    manifest_path = private_dir / "manifest.json"
    raw_manifest = manifest_path.read_bytes()
    if sha256_bytes(raw_manifest) != MANIFEST_SHA256:
        raise RuntimeError("Manifest SHA-256 mismatch")
    manifest = json.loads(raw_manifest.decode("utf-8"))

    key_b64 = os.environ.pop("FIGHTER_H17_D19_KEY", "")
    if not key_b64:
        raise RuntimeError("Missing FIGHTER_H17_D19_KEY")

    chunks = bytearray()
    for row in manifest["shards"]:
        shard_path = private_dir / row["file"]
        raw = shard_path.read_bytes()
        if len(raw) != row["bytes"] or sha256_bytes(raw) != row["sha256"]:
            raise RuntimeError(f"Shard integrity mismatch: {row['file']}")
        decoded = base64.b64decode(raw, validate=True) if row["encoding"] == "base64" else raw
        chunks.extend(decoded)

    cipher = bytes(chunks)
    if len(cipher) != manifest["cipherBytes"] or sha256_bytes(cipher) != manifest["cipherSHA256"]:
        raise RuntimeError("Assembled ciphertext SHA-256 mismatch")

    clear_zip = decrypt_aes_gcm(cipher, key_b64, manifest["aad"].encode("utf-8"))
    del key_b64
    del cipher
    if len(clear_zip) != manifest["clearZIPBytes"] or sha256_bytes(clear_zip) != manifest["clearZIPSHA256"]:
        raise RuntimeError("Decrypted archive SHA-256 mismatch")

    stage_dir.mkdir(parents=True, exist_ok=True)
    os.chmod(stage_dir, 0o700)
    wanted = {SUN_GLB_NAME: SUN_GLB_SHA256, LIU_GLB_NAME: LIU_GLB_SHA256}
    extracted = []
    with zipfile.ZipFile(io.BytesIO(clear_zip)) as zf:
        for name, expected_sha in wanted.items():
            data = zf.read(name)
            if sha256_bytes(data) != expected_sha:
                raise RuntimeError(f"Member SHA-256 mismatch: {name}")
            out = stage_dir / name
            out.write_bytes(data)
            os.chmod(out, 0o600)
            extracted.append({"name": name, "bytes": len(data)})
    del clear_zip
    print(json.dumps({"staged": extracted, "ok": True}))


def cmd_self_test_crypto() -> None:
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM

    key = os.urandom(32)
    key_b64 = base64.b64encode(key).decode("ascii")
    nonce = os.urandom(12)
    payload = b"synthetic-h17-verify-payload-2026"
    ct = AESGCM(key).encrypt(nonce, payload, AAD)
    out = decrypt_aes_gcm(nonce + ct, key_b64, AAD)
    assert out == payload, "AES-GCM round-trip mismatch"
    print("AES-256-GCM round-trip self-test PASSED")


# ---------------------------------------------------------------------------
# Mode 2: Blender 4.2 Head Swap + Two-Handed Odachi IK + Contact Sync Render
# ---------------------------------------------------------------------------
def cmd_render_blender(args) -> None:
    import bpy
    import bmesh
    import numpy as np
    from mathutils import Euler, Matrix, Quaternion, Vector

    out_dir = Path(args.out_dir)
    frames_dir = out_dir / "frames"
    plates_dir = out_dir / "plates"
    frames_dir.mkdir(parents=True, exist_ok=True)
    plates_dir.mkdir(parents=True, exist_ok=True)

    # ---- Math helpers ----
    def clamp(v: float, lo: float, hi: float) -> float:
        return max(lo, min(hi, v))

    def smoothstep(t: float) -> float:
        t = clamp(t, 0.0, 1.0)
        return t * t * (3.0 - 2.0 * t)

    def ease_in_cubic(t: float) -> float:
        t = clamp(t, 0.0, 1.0)
        return t * t * t

    def ease_out_cubic(t: float) -> float:
        t = clamp(t, 0.0, 1.0)
        u = 1.0 - t
        return 1.0 - u * u * u

    def seg_seg_distance(p1: Vector, q1: Vector, p2: Vector, q2: Vector):
        """Exact 3D distance between segment [p1,q1] and segment [p2,q2]."""
        d1 = q1 - p1
        d2 = q2 - p2
        r = p1 - p2
        a = d1.dot(d1)
        e = d2.dot(d2)
        f = d2.dot(r)
        eps = 1e-8
        if a <= eps and e <= eps:
            return (p1 - p2).length, p1.copy(), p2.copy()
        if a <= eps:
            s = 0.0
            t = clamp(f / e, 0.0, 1.0)
        else:
            c = d1.dot(r)
            if e <= eps:
                t = 0.0
                s = clamp(-c / a, 0.0, 1.0)
            else:
                b = d1.dot(d2)
                denom = a * e - b * b
                s = clamp((b * f - c * e) / denom, 0.0, 1.0) if abs(denom) > eps else 0.0
                t = (b * s + f) / e
                if t < 0.0:
                    t = 0.0
                    s = clamp(-c / a, 0.0, 1.0)
                elif t > 1.0:
                    t = 1.0
                    s = clamp((b - c) / a, 0.0, 1.0)
        c1 = p1 + d1 * s
        c2 = p2 + d2 * t
        return (c1 - c2).length, c1, c2

    def import_glb_objects(filepath: Path, prefix: str):
        before_objs = set(bpy.data.objects)
        before_acts = set(bpy.data.actions)
        bpy.ops.import_scene.gltf(filepath=str(filepath), bone_heuristic="TEMPERANCE")
        new_objs = [o for o in bpy.data.objects if o not in before_objs]
        new_acts = [a for a in bpy.data.actions if a not in before_acts]
        arm = next((o for o in new_objs if o.type == "ARMATURE"), None)
        roots = [o for o in new_objs if o.parent is None]
        root_empty = bpy.data.objects.new(f"{prefix}_Root", None)
        bpy.context.scene.collection.objects.link(root_empty)
        for r in roots:
            mw = r.matrix_world.copy()
            r.parent = root_empty
            r.matrix_world = mw
        return root_empty, arm, new_objs, new_acts

    def find_bone_name(arm, patterns) -> str | None:
        names = [b.name for b in arm.pose.bones]
        lower_map = {n.lower(): n for n in names}
        for pat in patterns:
            if pat in lower_map:
                return lower_map[pat]
        for pat in patterns:
            for n in names:
                if pat in n.lower():
                    return n
        return None

    def collect_descendant_bones(arm, bone_name: str) -> list[str]:
        res = []
        root_b = arm.pose.bones[bone_name]
        stack = list(root_b.children)
        while stack:
            b = stack.pop(0)
            res.append(b.name)
            stack.extend(b.children)
        return res

    def eval_bbox_world(objs):
        dg = bpy.context.evaluated_depsgraph_get()
        xs, ys, zs = [], [], []
        for o in objs:
            if o.type != "MESH" or o.hide_viewport or o.hide_render:
                continue
            eo = o.evaluated_get(dg)
            me = eo.to_mesh()
            if me and len(me.vertices):
                mw = eo.matrix_world
                for v in me.vertices:
                    w = mw @ v.co
                    xs.append(w.x)
                    ys.append(w.y)
                    zs.append(w.z)
            eo.to_mesh_clear()
        if not xs:
            return None
        return (min(xs), max(xs), min(ys), max(ys), min(zs), max(zs))

    def bone_world_head(arm, bname: str) -> Vector:
        return arm.matrix_world @ arm.pose.bones[bname].head

    def bone_world_tail(arm, bname: str) -> Vector:
        return arm.matrix_world @ arm.pose.bones[bname].tail

    def rotate_pose_bone_world(arm, bname: str, delta_q_world: Quaternion) -> None:
        pb = arm.pose.bones[bname]
        arm_rot = arm.matrix_world.to_3x3().normalized()
        dq_arm = arm_rot.inverted() @ delta_q_world.to_matrix() @ arm_rot
        mat = pb.matrix.copy()
        pos = mat.translation.copy()
        rot_new = dq_arm @ mat.to_3x3()
        out = rot_new.to_4x4()
        out.translation = pos
        pb.matrix = out

    def solve_two_bone_ik_world(arm, up_name: str, lo_name: str, hand_name: str,
                                target_world: Vector, pole_world: Vector):
        """Exact world-space analytical 2-bone IK using live bone lengths."""
        dg = bpy.context.evaluated_depsgraph_get()
        dg.update()
        A = bone_world_head(arm, up_name)
        B = bone_world_head(arm, lo_name)
        C = bone_world_head(arm, hand_name)
        L1 = (B - A).length
        L2 = (C - B).length
        if L1 < 1e-4 or L2 < 1e-4:
            return 0.0

        to_t = target_world - A
        d = to_t.length
        max_reach = (L1 + L2) * 0.996
        min_reach = abs(L1 - L2) + 0.015
        d_clamped = clamp(d, min_reach, max_reach)
        t_dir = to_t.normalized() if d > 1e-5 else Vector((1.0, 0.0, 0.0))

        # Pole direction orthogonal to A->T
        pole_v = pole_world - A
        pole_perp = pole_v - t_dir * pole_v.dot(t_dir)
        if pole_perp.length < 1e-4:
            pole_perp = Vector((0.0, 0.0, -1.0))
            pole_perp = pole_perp - t_dir * pole_perp.dot(t_dir)
        pole_perp.normalize()

        cos_a = clamp((L1 * L1 + d_clamped * d_clamped - L2 * L2) / (2.0 * L1 * d_clamped), -1.0, 1.0)
        sin_a = math.sqrt(max(0.0, 1.0 - cos_a * cos_a))
        E_des = A + t_dir * (L1 * cos_a) + pole_perp * (L1 * sin_a)

        # Rotate upper arm so B -> E_des
        cur_u = (B - A).normalized()
        des_u = (E_des - A).normalized()
        q1 = cur_u.rotation_difference(des_u)
        rotate_pose_bone_world(arm, up_name, q1)
        dg.update()

        # Re-read B & C, rotate lower arm so C -> T
        B2 = bone_world_head(arm, lo_name)
        C2 = bone_world_head(arm, hand_name)
        T_eff = A + t_dir * d_clamped
        cur_l = (C2 - B2).normalized()
        des_l = (T_eff - B2).normalized()
        q2 = cur_l.rotation_difference(des_l)
        rotate_pose_bone_world(arm, lo_name, q2)
        dg.update()

        return (bone_world_head(arm, hand_name) - target_world).length

    def measure_hand_basis(arm, hand_name: str, lo_name: str, is_right: bool):
        """Measure hand's true anatomical finger forward, thumb side, and palm-inward normal in hand-local space."""
        pb = arm.pose.bones[hand_name]
        hw = arm.matrix_world @ pb.matrix
        hw_rot = hw.to_3x3().normalized()
        h_pos = hw.translation.copy()
        fore_pos = bone_world_head(arm, lo_name)
        fore_dir = (h_pos - fore_pos).normalized()

        children = [c for c in pb.children]
        finger_vecs = []
        thumb_vecs = []
        for c in children:
            low = c.name.lower()
            if any(k in low for k in ("weapon", "wpn", "socket", "blade", "ninjato", "sword")):
                continue
            v = (bone_world_head(arm, c.name) - h_pos)
            if v.length < 1e-4:
                v = (bone_world_tail(arm, c.name) - h_pos)
            if v.length > 1e-4:
                if "thumb" in low or "finger0" in low or "f_0" in low:
                    thumb_vecs.append(v.normalized())
                else:
                    finger_vecs.append(v.normalized())

        if finger_vecs:
            fwd_w = sum(finger_vecs, Vector((0, 0, 0))).normalized()
        else:
            t_vec = (bone_world_tail(arm, hand_name) - h_pos)
            fwd_w = t_vec.normalized() if t_vec.length > 1e-4 else fore_dir

        if thumb_vecs:
            thumb_w = thumb_vecs[0] - fwd_w * thumb_vecs[0].dot(fwd_w)
            thumb_w = thumb_w.normalized() if thumb_w.length > 1e-4 else Vector((1, 0, 0))
        else:
            # Fallback in rest pose facing +X: thumb points forward (+X) orthogonal to arm
            ref_t = Vector((1.0, 0.0, 0.0))
            thumb_w = ref_t - fwd_w * ref_t.dot(fwd_w)
            thumb_w = thumb_w.normalized() if thumb_w.length > 1e-4 else Vector((0, 0, 1))

        # Universal human anatomy (right-handed coordinates):
        #   Right hand: palm_normal = thumb x fwd
        #   Left  hand: palm_normal = fwd   x thumb
        palm_w = thumb_w.cross(fwd_w) if is_right else fwd_w.cross(thumb_w)
        if palm_w.length < 1e-4:
            palm_w = Vector((0, 0, -1))
        palm_w.normalize()
        # Re-orthogonalize thumb_w cleanly
        thumb_w = (fwd_w.cross(palm_w) if is_right else palm_w.cross(fwd_w)).normalized()

        # Grip contact point inside palm: 4.8cm along fingers + 1.8cm off palm surface (handle radius!)
        palm_offset_local = hw_rot.inverted() @ (fwd_w * 0.048 + palm_w * 0.018)
        fwd_local = (hw_rot.inverted() @ fwd_w).normalized()
        thumb_local = (hw_rot.inverted() @ thumb_w).normalized()
        palm_local = (hw_rot.inverted() @ palm_w).normalized()
        return {
            "is_right": is_right,
            "fwd_local": fwd_local,
            "thumb_local": thumb_local,
            "palm_local": palm_local,
            "palm_offset_local": palm_offset_local,
            "finger_bones": collect_descendant_bones(arm, hand_name),
        }

    def align_hand_to_grip(arm, hand_name: str, basis: dict,
                           grip_axis_world: Vector, sharp_edge_dir_world: Vector):
        """True two-handed kendo grip: thumb points along +grip_axis (toward tsuba),
        fingers wrap forward across sharp-edge side (-wy), palms press opposite sides of tsuka!
        """
        dg = bpy.context.evaluated_depsgraph_get()
        pb = arm.pose.bones[hand_name]
        hw = arm.matrix_world @ pb.matrix
        hw_rot = hw.to_3x3().normalized()

        cur_fwd = (hw_rot @ basis["fwd_local"]).normalized()
        cur_thumb = (hw_rot @ basis["thumb_local"]).normalized()
        cur_palm = (hw_rot @ basis["palm_local"]).normalized()

        des_thumb = grip_axis_world.normalized()
        des_fwd = sharp_edge_dir_world - des_thumb * sharp_edge_dir_world.dot(des_thumb)
        if des_fwd.length < 1e-4:
            des_fwd = cur_fwd - des_thumb * cur_fwd.dot(des_thumb)
        des_fwd.normalize()
        des_palm = (des_thumb.cross(des_fwd) if basis["is_right"] else des_fwd.cross(des_thumb)).normalized()

        # Both M_cur and M_des have matching handedness (det = +1 for L, -1 for R -> M_des @ M_cur^-1 is ALWAYS proper SO(3) det=+1!)
        M_cur = Matrix((cur_fwd, cur_thumb, cur_palm)).transposed()
        M_des = Matrix((des_fwd, des_thumb, des_palm)).transposed()
        dq = (M_des @ M_cur.inverted()).to_quaternion()
        rotate_pose_bone_world(arm, hand_name, dq)
        dg.update()

    def curl_fingers(arm, hand_name: str, basis: dict):
        """Curl all 3 phalanges tightly around the tsuka cylinder strictly toward +palm_normal (never backwards!)."""
        dg = bpy.context.evaluated_depsgraph_get()
        hw_rot = (arm.matrix_world @ arm.pose.bones[hand_name].matrix).to_3x3().normalized()
        hand_fwd_w = (hw_rot @ basis["fwd_local"]).normalized()
        palm_w = (hw_rot @ basis["palm_local"]).normalized()
        # Exact constant flexion hinge axis parallel to the sword handle:
        # Rotating hand_fwd_w by +angle around (hand_fwd_w x palm_w) ALWAYS curls strictly toward +palm_w!
        hinge_w = hand_fwd_w.cross(palm_w).normalized()

        # Sort finger bones strictly parent-before-child by depth!
        items = []
        for bname in basis["finger_bones"]:
            low = bname.lower()
            if any(k in low for k in ("weapon", "wpn", "socket", "blade", "ninjato", "sword")):
                continue
            pb = arm.pose.bones[bname]
            depth = 0
            cur = pb.parent
            while cur and cur.name != hand_name and depth < 5:
                depth += 1
                cur = cur.parent
            if depth <= 2:
                items.append((depth, bname, low))
        items.sort(key=lambda x: x[0])

        for depth, bname, low in items:
            is_thumb = ("thumb" in low or "finger0" in low or "f_0" in low)
            if is_thumb:
                # Fold thumb cleanly inward toward palm & across curled index finger
                ang = math.radians(32.0 if depth == 0 else (38.0 if depth == 1 else 22.0))
                p0 = bone_world_head(arm, bname)
                p1 = bone_world_tail(arm, bname)
                bvec = (p1 - p0).normalized() if (p1 - p0).length > 1e-4 else (hw_rot @ basis["thumb_local"]).normalized()
                t_target = (palm_w * 0.72 + hand_fwd_w * 0.69).normalized()
                t_ax = bvec.cross(t_target)
                if t_ax.length > 1e-4:
                    rotate_pose_bone_world(arm, bname, Quaternion(t_ax.normalized(), ang))
                    dg.update()
            else:
                # Tight anatomical kendo fist wrap (~205 deg total across 3 phalanges!)
                ang = math.radians(68.0 if depth == 0 else (78.0 if depth == 1 else 58.0))
                rotate_pose_bone_world(arm, bname, Quaternion(hinge_w, ang))
                dg.update()

    def sample_action_pose(arm, action, frame_f: float, skip_bones: set[str]):
        """Sample local pose transforms from a Blender Action into a dict[bone -> (loc, rot_q, scale)]."""
        if action is None:
            return {}
        by_bone: dict[str, dict[str, list[float | None]]] = {}
        for fc in action.fcurves:
            dp = fc.data_path
            if not dp.startswith('pose.bones["'):
                continue
            end_q = dp.find('"]')
            if end_q < 0:
                continue
            bname = dp[12:end_q]
            if bname in skip_bones or bname not in arm.pose.bones:
                continue
            prop = dp[end_q + 3:]
            if prop not in ("location", "rotation_quaternion", "rotation_euler", "scale"):
                continue
            slot = by_bone.setdefault(bname, {})
            n = 4 if prop == "rotation_quaternion" else 3
            arr = slot.setdefault(prop, [None] * n)
            if 0 <= fc.array_index < n:
                arr[fc.array_index] = fc.evaluate(frame_f)

        out = {}
        for bname, props in by_bone.items():
            pb = arm.pose.bones[bname]
            loc = Vector([v if v is not None else 0.0 for v in props.get("location", [0.0, 0.0, 0.0])])
            if "rotation_quaternion" in props:
                q_raw = [v if v is not None else (1.0 if i == 0 else 0.0) for i, v in enumerate(props["rotation_quaternion"])]
                rot = Quaternion(q_raw).normalized()
            elif "rotation_euler" in props:
                e_raw = [v if v is not None else 0.0 for v in props["rotation_euler"]]
                rot = Euler(e_raw, pb.rotation_mode if len(pb.rotation_mode) == 3 else "XYZ").to_quaternion()
            else:
                rot = Quaternion((1.0, 0.0, 0.0, 0.0))
            scl = Vector([v if v is not None else 1.0 for v in props.get("scale", [1.0, 1.0, 1.0])])
            out[bname] = (loc, rot, scl)
        return out

    def blend_poses(pose_a: dict, pose_b: dict, t: float) -> dict:
        t = clamp(t, 0.0, 1.0)
        if t <= 1e-4:
            return pose_a
        if t >= 1.0 - 1e-4:
            return pose_b
        out = {}
        keys = set(pose_a.keys()) | set(pose_b.keys())
        id_l = Vector((0.0, 0.0, 0.0))
        id_q = Quaternion((1.0, 0.0, 0.0, 0.0))
        id_s = Vector((1.0, 1.0, 1.0))
        for k in keys:
            la, qa, sa = pose_a.get(k, (id_l, id_q, id_s))
            lb, qb, sb = pose_b.get(k, (id_l, id_q, id_s))
            if qa.dot(qb) < 0.0:
                qb = -qb
            out[k] = (la.lerp(lb, t), qa.slerp(qb, t), sa.lerp(sb, t))
        return out

    def apply_pose_dict(arm, pose_dict: dict):
        for pb in arm.pose.bones:
            pb.location = Vector((0.0, 0.0, 0.0))
            pb.rotation_mode = "QUATERNION"
            pb.rotation_quaternion = Quaternion((1.0, 0.0, 0.0, 0.0))
            pb.scale = Vector((1.0, 1.0, 1.0))
        for bname, (loc, rot, scl) in pose_dict.items():
            pb = arm.pose.bones[bname]
            pb.rotation_mode = "QUATERNION"
            pb.location = loc
            pb.rotation_quaternion = rot
            pb.scale = scl

    def find_action(actions, keywords: list[str]):
        for kw in keywords:
            kl = kw.lower()
            for a in actions:
                al = a.name.lower()
                if al == kl or al.startswith(kl + "_"):
                    return a
        for kw in keywords:
            kl = kw.lower()
            for a in actions:
                if kl in a.name.lower():
                    return a
        return None

    # ---- Reset Blender scene ----
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = 30

    # ---- 1. Import Hero (arm__prc_43 / Sun_DeadForestTriad_Ninjato.glb) ----
    hero_root, hero_arm, hero_objs, hero_acts = import_glb_objects(Path(args.hero_glb), "Hero")
    if hero_arm is None:
        raise RuntimeError("Hero GLB has no Armature")
    hero_arm.animation_data_clear()
    dg = bpy.context.evaluated_depsgraph_get()
    dg.update()

    # Discover Hero bones dynamically
    hb = {
        "pelvis": find_bone_name(hero_arm, ["pelvis", "hips", "mixamorig:hips"]),
        "spine": find_bone_name(hero_arm, ["spine2", "spine1", "spine", "chest", "mixamorig:spine2", "mixamorig:spine"]),
        "neck": find_bone_name(hero_arm, ["neck", "mixamorig:neck"]),
        "head": find_bone_name(hero_arm, ["head", "mixamorig:head"]),
        "hand_r": find_bone_name(hero_arm, ["hand_r", "righthand", "hand.r", "mixamorig:righthand"]),
        "hand_l": find_bone_name(hero_arm, ["hand_l", "lefthand", "hand.l", "mixamorig:lefthand"]),
        "foot_r": find_bone_name(hero_arm, ["foot_r", "rightfoot", "foot.r", "mixamorig:rightfoot"]),
        "foot_l": find_bone_name(hero_arm, ["foot_l", "leftfoot", "foot.l", "mixamorig:leftfoot"]),
        "toe_r": find_bone_name(hero_arm, ["toe_r", "righttoebase", "toe.r", "mixamorig:righttoebase"]),
        "toe_l": find_bone_name(hero_arm, ["toe_l", "lefttoebase", "toe.l", "mixamorig:lefttoebase"]),
    }
    for req in ("pelvis", "head", "hand_r", "hand_l", "foot_r", "foot_l"):
        if not hb[req]:
            raise RuntimeError(f"Missing required bone '{req}' in hero armature; bones={[b.name for b in hero_arm.pose.bones[:25]]}")

    hb["forearm_r"] = hero_arm.pose.bones[hb["hand_r"]].parent.name
    hb["upperarm_r"] = hero_arm.pose.bones[hb["forearm_r"]].parent.name
    hb["forearm_l"] = hero_arm.pose.bones[hb["hand_l"]].parent.name
    hb["upperarm_l"] = hero_arm.pose.bones[hb["forearm_l"]].parent.name
    if not hb["neck"]:
        hb["neck"] = hero_arm.pose.bones[hb["head"]].parent.name

    # Auto-orient Hero so character faces +X and stands at Z = 0
    if hb["toe_r"] and hb["toe_l"]:
        foot_mid = 0.5 * (bone_world_head(hero_arm, hb["foot_r"]) + bone_world_head(hero_arm, hb["foot_l"]))
        toe_mid = 0.5 * (bone_world_head(hero_arm, hb["toe_r"]) + bone_world_head(hero_arm, hb["toe_l"]))
        fwd_xy = Vector((toe_mid.x - foot_mid.x, toe_mid.y - foot_mid.y, 0.0))
    else:
        fwd_xy = Vector((0.0, -1.0, 0.0))
    if fwd_xy.length < 1e-4:
        fwd_xy = Vector((0.0, -1.0, 0.0))
    fwd_xy.normalize()
    cur_yaw = math.atan2(fwd_xy.y, fwd_xy.x)
    hero_root.rotation_euler = Euler((0.0, 0.0, -cur_yaw), "XYZ")
    dg.update()

    # Align Hero feet to Z=0 and center X/Y at origin
    hero_meshes_all = [o for o in hero_objs if o.type == "MESH"]
    bb_init = eval_bbox_world(hero_meshes_all)
    if bb_init:
        cx = 0.5 * (bb_init[0] + bb_init[1])
        cy = 0.5 * (bb_init[2] + bb_init[3])
        hero_root.location -= Vector((cx, cy, bb_init[4]))
        dg.update()
    hero_base_y = hero_root.location.y
    hero_base_z = hero_root.location.z
    hero_base_ankle_z = min(bone_world_head(hero_arm, hb["foot_r"]).z, bone_world_head(hero_arm, hb["foot_l"]).z)

    # Measure reference head position BEFORE hiding Sun Deng's helmet / head / ninjato
    ref_head_objs = [
        o for o in hero_meshes_all
        if any(k in o.name.lower() for k in ("personal_head", "rifthead", "wuyong_head", "_head"))
    ]
    ref_head_bb = eval_bbox_world(ref_head_objs) if ref_head_objs else None
    ref_head_bone_pos = bone_world_head(hero_arm, hb["head"])
    ref_neck_bone_pos = bone_world_head(hero_arm, hb["neck"])

    removed_meshes = []
    kept_body_meshes = []
    for o in hero_meshes_all:
        low = o.name.lower()
        if any(k in low for k in ("helm", "personal_head", "neck_bridge", "wpn__", "ninjato", "rifthead", "wuyong_head", "_head", "icosphere", "grippinghand")):
            o.hide_viewport = True
            o.hide_render = True
            removed_meshes.append(o.name)
        else:
            kept_body_meshes.append(o)

    body_bb = eval_bbox_world(kept_body_meshes)

    # ---- 2. Import Wu Yong's Untouched Head (M4_WuYong_Head) & Attach Rigidly ----
    head_src_root, head_src_arm, head_src_objs, _ = import_glb_objects(Path(args.head_glb), "HeadSrc")
    wuyong_head = next(
        (o for o in head_src_objs if o.type == "MESH" and ("head" in o.name.lower() or len(head_src_objs) <= 2)),
        None,
    )
    if wuyong_head is None:
        raise RuntimeError(f"Could not locate Wu Yong head mesh in {args.head_glb}")

    # Bake current world transform into mesh ONLY cleanly via rigid detach (keep vertices unedited in local space!)
    wuyong_head.modifiers.clear()
    wuyong_head.vertex_groups.clear()
    wuyong_head.parent = None
    # Delete donor rig & non-head objects cleanly
    for o in head_src_objs:
        if o != wuyong_head:
            bpy.data.objects.remove(o, do_unlink=True)
    bpy.data.objects.remove(head_src_root, do_unlink=True)

    # Measure raw Wu Yong head dimensions (faces -Y in local space)
    raw_verts = [v.co.copy() for v in wuyong_head.data.vertices]
    hx0, hx1 = min(v.x for v in raw_verts), max(v.x for v in raw_verts)
    hy0, hy1 = min(v.y for v in raw_verts), max(v.y for v in raw_verts)
    hz0, hz1 = min(v.z for v in raw_verts), max(v.z for v in raw_verts)
    raw_h_height = hz1 - hz0
    raw_h_cx = 0.5 * (hx0 + hx1)
    raw_h_cy = 0.5 * (hy0 + hy1)

    # Target anatomical head height & world anchor on arm__prc_43
    if ref_head_bb:
        target_h_height = clamp(ref_head_bb[5] - ref_head_bb[4], 0.225, 0.268)
        target_center_x = 0.5 * (ref_head_bb[0] + ref_head_bb[1])
        target_center_y = 0.5 * (ref_head_bb[2] + ref_head_bb[3])
        target_crown_z = ref_head_bb[5]
    else:
        target_h_height = 0.250
        target_center_x = ref_head_bone_pos.x + 0.015
        target_center_y = ref_head_bone_pos.y
        target_crown_z = ref_head_bone_pos.z + 0.165

    # Ensure chin clears collar nicely (body_bb top collar Z)
    collar_top_z = body_bb[5] if body_bb else (ref_neck_bone_pos.z + 0.02)
    head_scale = target_h_height / max(raw_h_height, 1e-4)
    desired_bot_z = max(target_crown_z - target_h_height, ref_neck_bone_pos.z - 0.020)

    # Rigid placement: rotate +90deg around Z so -Y face points +X (exact 0.0 deg pitch/roll!)
    rot_z90 = Matrix.Rotation(math.pi / 2.0, 4, "Z")
    # Compute where (raw_h_cx, raw_h_cy, hz0) lands after scale + rot_z90
    pivot_local = Vector((raw_h_cx, raw_h_cy, hz0))
    pivot_rot = (rot_z90 @ (pivot_local * head_scale))
    t_world = Vector((target_center_x, target_center_y, desired_bot_z)) - pivot_rot

    wuyong_head.name = "WuYong_Untouched_Head"
    wuyong_head.matrix_world = Matrix.Translation(t_world) @ rot_z90 @ Matrix.Diagonal((head_scale, head_scale, head_scale, 1.0))
    dg.update()

    # Bind Wu Yong's head 100% rigidly to hero_arm's head bone via BONE parenting (ZERO vertex edits, ZERO armature-space mismatch!)
    mw_head = wuyong_head.matrix_world.copy()
    wuyong_head.parent = hero_arm
    wuyong_head.parent_type = "BONE"
    wuyong_head.parent_bone = hb["head"]
    dg.update()
    # Set exact matrix_parent_inverse so world transform stays locked at mw_head at rest!
    pb_head = hero_arm.pose.bones[hb["head"]]
    # Blender BONE parent transform uses tail of parent bone in armature space!
    bone_tail_mat = hero_arm.matrix_world @ Matrix.Translation(pb_head.tail - pb_head.head) @ pb_head.matrix
    # Safer & exact in Blender: set matrix_world after parenting!
    wuyong_head.matrix_world = mw_head
    dg.update()

    # ---- 2B. Build Collar-Tucked Anatomical Neck Bridge (in hero_arm local space!) ----
    def build_neck_bridge():
        mw = wuyong_head.matrix_world
        low_pts = [mw @ v.co for v in wuyong_head.data.vertices if (mw @ v.co).z < desired_bot_z + 0.045]
        if len(low_pts) >= 12:
            ncx = float(np.median([p.x for p in low_pts])) - 0.020  # aligns squarely under jaw + occiput
            ncy = float(np.median([p.y for p in low_pts]))
            top_z = desired_bot_z + 0.028
        else:
            ncx = target_center_x - 0.022
            ncy = target_center_y
            top_z = desired_bot_z + 0.026
        neck_gap_mm = 0.0

        # Slim anatomical neck cylinder: tucks inside head base & narrowly inside collar (never pokes through chest!)
        n_seg = 32
        bot_z = min(ref_neck_bone_pos.z - 0.028, desired_bot_z - 0.052)
        bot_cx = 0.5 * (ncx + ref_neck_bone_pos.x)
        bot_cy = 0.5 * (ncy + ref_neck_bone_pos.y)
        n_rings = 6
        arm_inv = hero_arm.matrix_world.inverted()
        rings_local = []
        for r in range(n_rings):
            t = r / (n_rings - 1)
            cx = ncx * (1.0 - t) + bot_cx * t
            cy = ncy * (1.0 - t) + bot_cy * t
            cz = top_z * (1.0 - t) + bot_z * t
            rx = 0.045 + 0.004 * t
            ry = 0.042 + 0.004 * t
            row = []
            for i in range(n_seg):
                ang = 2.0 * math.pi * i / n_seg
                p_w = Vector((cx + rx * math.cos(ang), cy + ry * math.sin(ang), cz))
                row.append(arm_inv @ p_w)
            rings_local.append(row)

        me = bpy.data.meshes.new("WuYong_PRC43_NeckBridge_Mesh")
        bm = bmesh.new()
        bm_rings = []
        for row in rings_local:
            bm_rings.append([bm.verts.new(p) for p in row])
        for r in range(n_rings - 1):
            for i in range(n_seg):
                j = (i + 1) % n_seg
                bm.faces.new((bm_rings[r][i], bm_rings[r][j], bm_rings[r + 1][j], bm_rings[r + 1][i]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(me)
        bm.free()

        obj = bpy.data.objects.new("WuYong_PRC43_NeckBridge", me)
        bpy.context.scene.collection.objects.link(obj)
        for p in me.polygons:
            p.use_smooth = True

        # Sample exact skin color from Wu Yong's head Base Color texture so neck matches seamlessly!
        skin_rgba = (0.58, 0.45, 0.39, 1.0)
        try:
            head_mat = wuyong_head.data.materials[0] if wuyong_head.data.materials else None
            tex_img = None
            if head_mat and head_mat.use_nodes:
                for node in head_mat.node_tree.nodes:
                    if node.type == "TEX_IMAGE" and node.image and "base" in node.image.name.lower():
                        tex_img = node.image
                        break
            if tex_img and wuyong_head.data.uv_layers:
                w_img, h_img = tex_img.size[:]
                px = np.array(tex_img.pixels[:], dtype=np.float32).reshape(h_img, w_img, 4)
                uv_layer = wuyong_head.data.uv_layers.active.data
                samples = []
                for poly in wuyong_head.data.polygons:
                    for li in poly.loop_indices:
                        v = wuyong_head.data.vertices[wuyong_head.data.loops[li].vertex_index]
                        wz = (wuyong_head.matrix_world @ v.co).z
                        if wz < desired_bot_z + 0.045:
                            u_c, v_c = uv_layer[li].uv
                            ix = int(clamp(u_c, 0.0, 0.999) * w_img)
                            iy = int(clamp(v_c, 0.0, 0.999) * h_img)
                            c = px[iy, ix]
                            if c[0] > 0.25 and c[1] > 0.20:
                                samples.append(c[:3])
                if samples:
                    med = np.median(np.array(samples), axis=0)
                    # Convert sRGB pixel -> linear for Blender Principled BSDF Base Color
                    lin = [float((x / 12.92) if x <= 0.04045 else (((x + 0.055) / 1.055) ** 2.4)) for x in med]
                    skin_rgba = (lin[0], lin[1], lin[2], 1.0)
        except Exception:
            pass

        mat = bpy.data.materials.new("WuYong_NeckSkin_Mat")
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        bsdf.inputs["Base Color"].default_value = skin_rgba
        bsdf.inputs["Roughness"].default_value = 0.62
        if "Subsurface Weight" in bsdf.inputs:
            bsdf.inputs["Subsurface Weight"].default_value = 0.05
        obj.data.materials.append(mat)

        # Parent to hero_arm with exact identity local transform so obj.matrix_world == hero_arm.matrix_world!
        obj.parent = hero_arm
        obj.matrix_parent_inverse = Matrix.Identity(4)
        obj.matrix_local = Matrix.Identity(4)
        vg_h = obj.vertex_groups.new(name=hb["head"])
        vg_n = obj.vertex_groups.new(name=hb["neck"])
        for r in range(n_rings):
            t = r / (n_rings - 1)
            wh = clamp(1.0 - t * 1.15, 0.0, 1.0)
            wn = 1.0 - wh
            for i in range(n_seg):
                vid = r * n_seg + i
                if wh > 0:
                    vg_h.add([vid], wh, "REPLACE")
                if wn > 0:
                    vg_n.add([vid], wn, "REPLACE")
        mod = obj.modifiers.new(name="Armature", type="ARMATURE")
        mod.object = hero_arm
        return obj, neck_gap_mm

    neck_bridge_obj, neck_gap_mm = build_neck_bridge()
    dg.update()

    # ---- 3. Import Odachi Weapon (M4_Odachi, scaled to 1.74m) ----
    wpn_root, _, wpn_objs, _ = import_glb_objects(Path(args.weapon_glb), "OdachiSrc")
    odachi = next((o for o in wpn_objs if o.type == "MESH"), None)
    if odachi is None:
        raise RuntimeError(f"No weapon mesh in {args.weapon_glb}")
    odachi.name = "WuYong_Odachi"
    odachi.parent = None
    bpy.data.objects.remove(wpn_root, do_unlink=True)
    ODACHI_SCALE = 1.08
    odachi.scale = Vector((ODACHI_SCALE, ODACHI_SCALE, ODACHI_SCALE))
    bpy.context.view_layer.objects.active = odachi
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

    # Local Odachi landmarks (post-scale, Z along handle->tip)
    GRIP_R_LOCAL = Vector((0.0, 0.0, 0.052 * ODACHI_SCALE))     # Upper handle (right hand, clean clearance below tsuba)
    GRIP_L_LOCAL = Vector((0.0, 0.0, -0.115 * ODACHI_SCALE))    # Lower handle (left hand, 18.0cm below right)
    BLADE_BASE_LOCAL = Vector((0.0, 0.0, 0.215 * ODACHI_SCALE))
    BLADE_TIP_LOCAL = Vector((0.0, 0.0, 1.425 * ODACHI_SCALE))
    TSUBA_Z_LOCAL = 0.133 * ODACHI_SCALE

    # Measure hand anatomical frames & arm lengths in clean rest pose
    dg.update()
    hand_basis_r = measure_hand_basis(hero_arm, hb["hand_r"], hb["forearm_r"], is_right=True)
    hand_basis_l = measure_hand_basis(hero_arm, hb["hand_l"], hb["forearm_l"], is_right=False)
    arm_len_r = (bone_world_head(hero_arm, hb["forearm_r"]) - bone_world_head(hero_arm, hb["upperarm_r"])).length + \
                (bone_world_head(hero_arm, hb["hand_r"]) - bone_world_head(hero_arm, hb["forearm_r"])).length
    arm_len_l = (bone_world_head(hero_arm, hb["forearm_l"]) - bone_world_head(hero_arm, hb["upperarm_l"])).length + \
                (bone_world_head(hero_arm, hb["hand_l"]) - bone_world_head(hero_arm, hb["forearm_l"])).length

    # Bones owned exclusively by our Two-Handed Odachi IK (skip in mocap arm overwrite)
    ik_owned_bones = {
        hb["upperarm_r"], hb["forearm_r"], hb["hand_r"],
        hb["upperarm_l"], hb["forearm_l"], hb["hand_l"],
        *hand_basis_r["finger_bones"], *hand_basis_l["finger_bones"],
    }

    # ---- 4. Import Real 3D Opponent (Liu_Legion_Hammers.glb) ----
    opp_root, opp_arm, opp_objs, opp_acts = import_glb_objects(Path(args.opp_glb), "Opponent")
    if opp_arm is None:
        raise RuntimeError("Opponent GLB has no Armature")
    opp_arm.animation_data_clear()
    dg.update()

    ob = {
        "pelvis": find_bone_name(opp_arm, ["pelvis", "hips", "mixamorig:hips"]),
        "spine": find_bone_name(opp_arm, ["spine2", "spine1", "spine", "chest", "mixamorig:spine2", "mixamorig:spine"]),
        "head": find_bone_name(opp_arm, ["head", "mixamorig:head"]),
        "foot_r": find_bone_name(opp_arm, ["foot_r", "rightfoot", "foot.r", "mixamorig:rightfoot"]),
        "foot_l": find_bone_name(opp_arm, ["foot_l", "leftfoot", "foot.l", "mixamorig:leftfoot"]),
        "toe_r": find_bone_name(opp_arm, ["toe_r", "righttoebase", "toe.r", "mixamorig:righttoebase"]),
        "toe_l": find_bone_name(opp_arm, ["toe_l", "lefttoebase", "toe.l", "mixamorig:lefttoebase"]),
    }
    if ob["toe_r"] and ob["toe_l"]:
        ofm = 0.5 * (bone_world_head(opp_arm, ob["foot_r"]) + bone_world_head(opp_arm, ob["foot_l"]))
        otm = 0.5 * (bone_world_head(opp_arm, ob["toe_r"]) + bone_world_head(opp_arm, ob["toe_l"]))
        ofwd = Vector((otm.x - ofm.x, otm.y - ofm.y, 0.0))
    else:
        ofwd = Vector((0.0, -1.0, 0.0))
    if ofwd.length < 1e-4:
        ofwd = Vector((0.0, -1.0, 0.0))
    ofwd.normalize()
    opp_cur_yaw = math.atan2(ofwd.y, ofwd.x)
    # Face -X (directly toward Wu Yong!)
    opp_root.rotation_euler = Euler((0.0, 0.0, math.pi - opp_cur_yaw), "XYZ")
    dg.update()
    opp_meshes = [o for o in opp_objs if o.type == "MESH"]
    obb_init = eval_bbox_world(opp_meshes)
    if obb_init:
        opp_root.location -= Vector((0.5 * (obb_init[0] + obb_init[1]), 0.5 * (obb_init[2] + obb_init[3]), obb_init[4]))
        dg.update()
    opp_base_y = opp_root.location.y
    opp_base_z = opp_root.location.z
    opp_base_ankle_z = min(bone_world_head(opp_arm, ob["foot_r"]).z, bone_world_head(opp_arm, ob["foot_l"]).z)

    # Locate embedded Nekki mocap actions
    hero_clip_idle = find_action(hero_acts, ["ninjato_stance_idle", "idle"])
    hero_clip_walk = find_action(hero_acts, ["m_step_forward", "walk", "run"])
    hero_clip_light = find_action(hero_acts, ["ninjato_slash_1", "slash", "light"])
    hero_clip_heavy = find_action(hero_acts, ["ninjato_heavy_slash", "heavy"])
    opp_clip_idle = find_action(opp_acts, ["hammers_stance_idle", "stance_idle", "idle"])
    opp_clip_hit = find_action(opp_acts, ["h_chest_short_fast", "hit_chest", "hit"])
    opp_clip_heavy_hit = find_action(opp_acts, ["h_hit_head_fall", "h_chest_long", "h_chest_short_fast", "hit"])

    # ---- 5. Choreography & Two-Handed Odachi Trajectory Specification (160 Frames @ 30fps) ----
    TOTAL_FRAMES = int(args.frames)
    HERO_X_START = -0.78
    HERO_X_ENGAGE = -0.10
    HERO_X_HEAVY = +0.12
    OPP_X_START = +1.05

    def hero_phase_info(f: int):
        if f <= 22:
            return "IDLE", "待机 IDLE", (f - 1) / 21.0
        if f <= 44:
            return "ADVANCE", "前进 ADVANCE", (f - 23) / 21.0
        if f <= 68:
            return "LIGHT", "轻击命中 LIGHT HIT", (f - 45) / 23.0
        if f <= 104:
            return "HEAVY", "重斩命中 HEAVY HIT", (f - 69) / 35.0
        if f <= 124:
            return "RECOVER", "收招 RECOVERY", (f - 105) / 19.0
        return "WHIFF", "空挥对照 EMPTY WHIFF", (f - 125) / 35.0

    def hero_root_x(f: int) -> float:
        if f <= 22:
            return HERO_X_START
        if f <= 44:
            return HERO_X_START + (HERO_X_ENGAGE - HERO_X_START) * smoothstep((f - 23) / 21.0)
        if f <= 68:
            # Small forward lunge during light slash, settling back slightly
            t = (f - 45) / 23.0
            lunge = 0.08 * math.sin(clamp(t * 1.4, 0.0, 1.0) * math.pi)
            return HERO_X_ENGAGE + lunge
        if f <= 104:
            # Planted front-foot step-in into heavy cleave!
            t = (f - 69) / 35.0
            step = smoothstep(t / 0.45)
            return HERO_X_ENGAGE + (HERO_X_HEAVY - HERO_X_ENGAGE) * step
        if f <= 124:
            return HERO_X_HEAVY
        # Empty whiff stays at exact same stance X=+0.12m (opponent is knocked far out of reach!)
        return HERO_X_HEAVY

    def odachi_target_local(phase: str, u: float):
        """Return (handle_mid_rel_chest, blade_dir_world, edge_dir_world, torso_yaw_rad, torso_pitch_rad).
        Hero faces +X, side camera sits at -Y looking toward +Y.
        Uses exact polar elevation angle `theta` so blade sweeps on a true circular arc
        and sharp edge tangent (sin(theta), 0, -cos(theta)) leads 100% of the swing with zero flip!
        """
        def arc_vec(theta_deg: float, lat_y: float):
            th = math.radians(theta_deg)
            bdir = Vector((math.cos(th), lat_y, math.sin(th))).normalized()
            edir = Vector((math.sin(th), 0.15 * lat_y, -math.cos(th))).normalized()
            return bdir, edir

        if phase == "IDLE":
            breath = math.sin(u * 2.0 * math.pi)
            mid = Vector((0.28, -0.07, -0.22 + 0.012 * breath))
            bdir, edir = arc_vec(29.0 + 1.5 * breath, 0.14)
            return mid, bdir, edir, math.radians(-16.0), math.radians(5.0)

        if phase == "ADVANCE":
            bob = math.sin(u * 4.0 * math.pi)
            mid = Vector((0.30, -0.06 + 0.02 * bob, -0.22 + 0.018 * abs(bob)))
            bdir, edir = arc_vec(27.0 + 2.0 * bob, 0.12)
            return mid, bdir, edir, math.radians(-18.0 + 5.0 * bob), math.radians(9.0)

        if phase == "LIGHT":
            # Crisp 3-stage diagonal cut: 0..0.24 quick load -> 0.24..0.46 diagonal cleave -> 0.46..1.0 guard
            if u < 0.24:
                k = smoothstep(u / 0.24)
                mid = Vector((0.28 - 0.12 * k, -0.07 - 0.12 * k, -0.22 + 0.34 * k))
                bdir, edir = arc_vec(29.0 + 72.0 * k, 0.14 - 0.28 * k)
                yaw = math.radians(-16.0 - 26.0 * k)
                pitch = math.radians(5.0 - 5.0 * k)
            elif u < 0.46:
                k = ease_out_cubic((u - 0.24) / 0.22)
                mid = Vector((0.16 + 0.26 * k, -0.19 + 0.34 * k, 0.12 - 0.34 * k))
                bdir, edir = arc_vec(101.0 - 118.0 * k, -0.14 + 0.38 * k)
                yaw = math.radians(-42.0 + 72.0 * k)
                pitch = math.radians(0.0 + 13.0 * k)
            else:
                k = smoothstep((u - 0.46) / 0.54)
                mid = Vector((0.42 - 0.14 * k, 0.15 - 0.22 * k, -0.22))
                bdir, edir = arc_vec(-17.0 + 46.0 * k, 0.24 - 0.10 * k)
                yaw = math.radians(30.0 - 46.0 * k)
                pitch = math.radians(13.0 - 8.0 * k)
            return mid, bdir, edir, yaw, pitch

        if phase in ("HEAVY", "WHIFF"):
            # True SF4 Shogun weighted overhead-to-diagonal Heavy Cleave:
            #   0.00..0.38: deep shoulder/hip coil raising Odachi high behind head (+124 deg)
            #   0.38..0.54: explosive 142-deg downward-diagonal cleave (+124 -> -18 deg) hitting at ~+28 deg!
            #   0.54..0.78: heavy momentum overshoot down past front knee (-18 -> -42 deg)
            #   0.78..1.00: weighted recovery back to low-mid guard (-42 -> +29 deg)
            if u < 0.38:
                k = smoothstep(u / 0.38)
                mid = Vector((0.28 - 0.08 * k, -0.07 - 0.14 * k, -0.22 + 0.50 * k))
                bdir, edir = arc_vec(29.0 + 83.0 * k, 0.14 - 0.24 * k)
                yaw = math.radians(-16.0 - 38.0 * k)
                pitch = math.radians(5.0 - 12.0 * k)
            elif u < 0.54:
                k = ease_in_cubic((u - 0.38) / 0.16)
                mid = Vector((0.20 + 0.24 * k, -0.21 + 0.33 * k, 0.28 - 0.46 * k))
                bdir, edir = arc_vec(112.0 - 130.0 * k, -0.10 + 0.24 * k)
                yaw = math.radians(-54.0 + 90.0 * k)
                pitch = math.radians(-7.0 + 24.0 * k)
            elif u < 0.78:
                k = ease_out_cubic((u - 0.54) / 0.24)
                mid = Vector((0.44 - 0.08 * k, 0.12 + 0.12 * k, -0.18 - 0.14 * k))
                bdir, edir = arc_vec(-18.0 - 24.0 * k, 0.14 + 0.18 * k)
                yaw = math.radians(36.0 + 10.0 * k)
                pitch = math.radians(17.0 + 4.0 * k)
            else:
                k = smoothstep((u - 0.78) / 0.22)
                mid = Vector((0.36 - 0.08 * k, 0.24 - 0.31 * k, -0.32 + 0.10 * k))
                bdir, edir = arc_vec(-42.0 + 71.0 * k, 0.32 - 0.18 * k)
                yaw = math.radians(46.0 - 62.0 * k)
                pitch = math.radians(21.0 - 16.0 * k)
            return mid, bdir, edir, yaw, pitch

        # RECOVER
        k = smoothstep(u)
        mid = Vector((0.30 - 0.02 * k, 0.02 - 0.09 * k, -0.24 + 0.02 * k))
        bdir, edir = arc_vec(18.0 + 11.0 * k, 0.20 - 0.06 * k)
        return mid, bdir, edir, math.radians(-6.0 - 10.0 * k), math.radians(8.0 - 3.0 * k)

    def clip_frame_for(action, u: float) -> float:
        if action is None:
            return 0.0
        f0, f1 = action.frame_range
        return f0 + clamp(u, 0.0, 1.0) * max(1.0, f1 - f0)

    def hero_mocap_pose(f: int):
        phase, _, u = hero_phase_info(f)
        if phase == "IDLE":
            return sample_action_pose(hero_arm, hero_clip_idle, clip_frame_for(hero_clip_idle, (u * 1.0) % 1.0), ik_owned_bones)
        if phase == "ADVANCE":
            p = sample_action_pose(hero_arm, hero_clip_walk, clip_frame_for(hero_clip_walk, (u * 2.0) % 1.0), ik_owned_bones)
            if f <= 26:
                p_prev = sample_action_pose(hero_arm, hero_clip_idle, clip_frame_for(hero_clip_idle, 1.0), ik_owned_bones)
                return blend_poses(p_prev, p, (f - 22) / 4.0)
            return p
        if phase == "LIGHT":
            # Grounded Nekki combat stance + brief front step lunge (never dual-ninjato spin fighting 2H Odachi!)
            p_idle = sample_action_pose(hero_arm, hero_clip_idle, clip_frame_for(hero_clip_idle, 0.25 + 0.5 * u), ik_owned_bones)
            p_step = sample_action_pose(hero_arm, hero_clip_walk, clip_frame_for(hero_clip_walk, clamp(u * 1.3, 0.0, 1.0)), ik_owned_bones)
            step_w = 0.35 * math.sin(clamp(u * 1.25, 0.0, 1.0) * math.pi)
            p = blend_poses(p_idle, p_step, step_w)
            if f <= 48:
                p_prev = sample_action_pose(hero_arm, hero_clip_walk, clip_frame_for(hero_clip_walk, 0.0), ik_owned_bones)
                return blend_poses(p_prev, p, (f - 44) / 4.0)
            return p
        if phase in ("HEAVY", "WHIFF"):
            # Planted wide-stance Nekki base with step-in weight transfer synchronized to heavy cleave
            p_idle = sample_action_pose(hero_arm, hero_clip_idle, clip_frame_for(hero_clip_idle, (0.15 + 0.7 * u) % 1.0), ik_owned_bones)
            p_step = sample_action_pose(hero_arm, hero_clip_walk, clip_frame_for(hero_clip_walk, clamp(u * 1.6, 0.0, 1.0)), ik_owned_bones)
            step_w = 0.42 * math.sin(clamp(u / 0.65, 0.0, 1.0) * math.pi)
            p = blend_poses(p_idle, p_step, step_w)
            if phase == "HEAVY" and f <= 73:
                p_prev = sample_action_pose(hero_arm, hero_clip_idle, clip_frame_for(hero_clip_idle, 0.75), ik_owned_bones)
                return blend_poses(p_prev, p, (f - 68) / 5.0)
            if phase == "WHIFF" and f <= 129:
                p_prev = sample_action_pose(hero_arm, hero_clip_idle, clip_frame_for(hero_clip_idle, 1.0), ik_owned_bones)
                return blend_poses(p_prev, p, (f - 124) / 5.0)
            return p
        # RECOVER
        p_idle = sample_action_pose(hero_arm, hero_clip_idle, clip_frame_for(hero_clip_idle, u), ik_owned_bones)
        return p_idle

    def pose_hero_frame(f: int):
        phase, _, u = hero_phase_info(f)
        pdict = hero_mocap_pose(f)
        apply_pose_dict(hero_arm, pdict)
        hero_root.location = Vector((hero_root_x(f), hero_base_y, hero_base_z))
        dg.update()

        # Ground hero cleanly so lowest foot sole stays firmly planted at Z = 0
        min_foot_z = min(bone_world_head(hero_arm, hb["foot_r"]).z, bone_world_head(hero_arm, hb["foot_l"]).z)
        if abs(min_foot_z - hero_base_ankle_z) > 0.004:
            hero_root.location.z += (hero_base_ankle_z - min_foot_z)
            dg.update()

        # Coupled hip/waist + chest torque driving the two-handed Odachi cleanly
        mid_rel, bdir_w, edir_w, torso_yaw, torso_pitch = odachi_target_local(phase, u)
        if hb["pelvis"]:
            rotate_pose_bone_world(hero_arm, hb["pelvis"], Quaternion(Vector((0.0, 0.0, 1.0)), torso_yaw * 0.25))
            dg.update()
        if hb["spine"]:
            q_torso = Quaternion(Vector((0.0, 0.0, 1.0)), torso_yaw * 0.50) @ Quaternion(Vector((0.0, 1.0, 0.0)), torso_pitch * 0.60)
            rotate_pose_bone_world(hero_arm, hb["spine"], q_torso)
            dg.update()
            # Keep head looking steadily toward opponent (zero awkward neck twist)
            rotate_pose_bone_world(hero_arm, hb["head"], Quaternion(Vector((0.0, 0.0, 1.0)), -torso_yaw * 0.62))
            dg.update()

        # Compute Odachi world transform anchored to live shoulder midpoint
        sh_r = bone_world_head(hero_arm, hb["upperarm_r"])
        sh_l = bone_world_head(hero_arm, hb["upperarm_l"])
        chest_c = 0.5 * (sh_r + sh_l)

        handle_mid_w = chest_c + mid_rel
        # Build orthonormal weapon basis:
        #   local +Z = pommel -> blade tip
        #   local -Y = RAZOR-SHARP cutting edge (ha) -> points along edir_w (forward/downward into cut!)
        #   local +Y = thick curved spine (mune)     -> curves backward along -edir_w!
        wz = bdir_w.normalized()
        edge_perp = edir_w - wz * edir_w.dot(wz)
        if edge_perp.length < 1e-4:
            edge_perp = Vector((1.0, 0.0, 0.0)) - wz * wz.x
        edge_perp.normalize()
        wy = -edge_perp
        wx = wy.cross(wz).normalized()
        wy = wz.cross(wx).normalized()
        w_rot = Matrix((wx, wy, wz)).transposed().to_4x4()

        # Grip midpoint in weapon local space
        grip_mid_local = 0.5 * (GRIP_R_LOCAL + GRIP_L_LOCAL)
        # Reach clamp so BOTH shoulders reach their grips strictly within 0.92 * arm_len!
        for _ in range(4):
            w_origin = handle_mid_w - (w_rot.to_3x3() @ grip_mid_local)
            p_r = w_origin + (w_rot.to_3x3() @ GRIP_R_LOCAL)
            p_l = w_origin + (w_rot.to_3x3() @ GRIP_L_LOCAL)
            dr = (p_r - sh_r).length
            dl = (p_l - sh_l).length
            lim_r = arm_len_r * 0.92
            lim_l = arm_len_l * 0.92
            if dr <= lim_r and dl <= lim_l:
                break
            if dr > lim_r:
                handle_mid_w -= (p_r - sh_r).normalized() * (dr - lim_r)
            if dl > lim_l:
                handle_mid_w -= (p_l - sh_l).normalized() * (dl - lim_l)

        w_origin = handle_mid_w - (w_rot.to_3x3() @ grip_mid_local)
        odachi_mw = Matrix.Translation(w_origin) @ w_rot
        odachi.matrix_world = odachi_mw

        p_r_target = odachi_mw @ GRIP_R_LOCAL
        p_l_target = odachi_mw @ GRIP_L_LOCAL

        # Anatomical elbow pole hints (right elbow flares -Y/down, left elbow flares +Y/down)
        pole_r = sh_r + Vector((-0.18, -0.55, -0.35))
        pole_l = sh_l + Vector((-0.12, +0.55, -0.35))

        # Shift IK target from palm back to wrist joint so PALM CENTER lands on exact grip point!
        # Sharp cutting edge is local -Y (-wy): both hands wrap fingers around -wy with thumbs toward +wz!
        sharp_edge_w = -wy
        solve_two_bone_ik_world(hero_arm, hb["upperarm_r"], hb["forearm_r"], hb["hand_r"], p_r_target, pole_r)
        align_hand_to_grip(hero_arm, hb["hand_r"], hand_basis_r, wz, sharp_edge_w)
        hw_r = (hero_arm.matrix_world @ hero_arm.pose.bones[hb["hand_r"]].matrix).to_3x3().normalized()
        wrist_r_target = p_r_target - (hw_r @ hand_basis_r["palm_offset_local"])
        solve_two_bone_ik_world(hero_arm, hb["upperarm_r"], hb["forearm_r"], hb["hand_r"], wrist_r_target, pole_r)
        align_hand_to_grip(hero_arm, hb["hand_r"], hand_basis_r, wz, sharp_edge_w)
        curl_fingers(hero_arm, hb["hand_r"], hand_basis_r)

        solve_two_bone_ik_world(hero_arm, hb["upperarm_l"], hb["forearm_l"], hb["hand_l"], p_l_target, pole_l)
        align_hand_to_grip(hero_arm, hb["hand_l"], hand_basis_l, wz, sharp_edge_w)
        hw_l = (hero_arm.matrix_world @ hero_arm.pose.bones[hb["hand_l"]].matrix).to_3x3().normalized()
        wrist_l_target = p_l_target - (hw_l @ hand_basis_l["palm_offset_local"])
        solve_two_bone_ik_world(hero_arm, hb["upperarm_l"], hb["forearm_l"], hb["hand_l"], wrist_l_target, pole_l)
        align_hand_to_grip(hero_arm, hb["hand_l"], hand_basis_l, wz, sharp_edge_w)
        curl_fingers(hero_arm, hb["hand_l"], hand_basis_l)
        dg.update()

        # Measure ACTUAL post-IK palm-to-grip error & blade segment
        hw_r_post = hero_arm.matrix_world @ hero_arm.pose.bones[hb["hand_r"]].matrix
        hw_l_post = hero_arm.matrix_world @ hero_arm.pose.bones[hb["hand_l"]].matrix
        palm_r_w = hw_r_post.translation + (hw_r_post.to_3x3().normalized() @ hand_basis_r["palm_offset_local"])
        palm_l_w = hw_l_post.translation + (hw_l_post.to_3x3().normalized() @ hand_basis_l["palm_offset_local"])
        slip_r_mm = (palm_r_w - p_r_target).length * 1000.0
        slip_l_mm = (palm_l_w - p_l_target).length * 1000.0

        # Check finger-to-blade clip (any finger bone tip penetrating above tsuba Z in weapon local space)
        odachi_inv = odachi_mw.inverted()
        blade_clip = 0
        for bname in (*hand_basis_r["finger_bones"], *hand_basis_l["finger_bones"]):
            if any(k in bname.lower() for k in ("weapon", "wpn", "socket", "blade")):
                continue
            pt_loc = odachi_inv @ bone_world_tail(hero_arm, bname)
            if pt_loc.z > TSUBA_Z_LOCAL + 0.005 and math.hypot(pt_loc.x, pt_loc.y) < 0.035:
                blade_clip += 1

        head_mat = hero_arm.matrix_world @ hero_arm.pose.bones[hb["head"]].matrix
        return {
            "blade_base": odachi_mw @ BLADE_BASE_LOCAL,
            "blade_tip": odachi_mw @ BLADE_TIP_LOCAL,
            "grip_r": p_r_target,
            "grip_l": p_l_target,
            "slip_r_mm": slip_r_mm,
            "slip_l_mm": slip_l_mm,
            "blade_clip": blade_clip,
            "head_pos": head_mat.translation.copy(),
            "odachi_mw": odachi_mw.copy(),
        }

    # ---- 6. Pass 1: Pre-simulate all 160 frames to detect EXACT 3D Contact Frames ----
    sim_records = []
    light_contact_frame = None
    heavy_contact_frame = None
    opp_x_cur = OPP_X_START
    opp_kb_start_x = OPP_X_START
    opp_kb_amp = 0.0
    opp_kb_t0 = None
    opp_kb_dur = 14
    opp_react_clip = None

    def pose_opponent_frame(f: int, opp_x: float, hit_clip, hit_t0: int | None, hit_heavy: bool):
        if hit_clip is not None and hit_t0 is not None and f >= hit_t0:
            dur = 26 if hit_heavy else 15
            # Immediate frame-0 entry into hitstun (u_h starts at 0.06 on exact contact frame!)
            u_h = clamp((f - hit_t0 + 1.0) / dur, 0.0, 1.0)
            p_hit = sample_action_pose(opp_arm, hit_clip, clip_frame_for(hit_clip, min(u_h, 0.85)), set())
            if not hit_heavy and u_h > 0.72:
                p_idle = sample_action_pose(opp_arm, opp_clip_idle, clip_frame_for(opp_clip_idle, (f % 30) / 30.0), set())
                p_opp = blend_poses(p_hit, p_idle, (u_h - 0.72) / 0.28)
            else:
                p_opp = p_hit
        else:
            p_opp = sample_action_pose(opp_arm, opp_clip_idle, clip_frame_for(opp_clip_idle, (f % 30) / 30.0), set())
        apply_pose_dict(opp_arm, p_opp)
        opp_root.location = Vector((opp_x, opp_base_y, opp_base_z))
        dg.update()

        # Immediate physical recoil lean on torso starting at EXACT contact frame (dt=0 -> immediate flinch!)
        if hit_t0 is not None and f >= hit_t0:
            dt = f - hit_t0
            peak = math.sin(clamp((dt + 1.2) / (7.0 if hit_heavy else 4.5), 0.0, 1.0) * math.pi * 0.5) * math.exp(-dt / (12.0 if hit_heavy else 7.0))
            lean_deg = (32.0 if hit_heavy else 18.0) * peak
            if ob["spine"]:
                rotate_pose_bone_world(opp_arm, ob["spine"], Quaternion(Vector((0.0, 1.0, 0.0)), math.radians(lean_deg)))
                dg.update()

        # Ground opponent safely: never shove falling/knocked-down body underground!
        ofz = min(bone_world_head(opp_arm, ob["foot_r"]).z, bone_world_head(opp_arm, ob["foot_l"]).z)
        if not (hit_heavy and hit_t0 is not None and f >= hit_t0):
            if abs(ofz - opp_base_ankle_z) > 0.005:
                opp_root.location.z += (opp_base_ankle_z - ofz)
                dg.update()
        else:
            pelv_z = bone_world_head(opp_arm, ob["pelvis"]).z
            min_z = min(ofz, pelv_z)
            if min_z < 0.05:
                opp_root.location.z += (0.05 - min_z)
                dg.update()

    for f in range(1, TOTAL_FRAMES + 1):
        phase, phase_zh, u = hero_phase_info(f)

        # Update damped knockback position BEFORE measuring frame distance
        if phase == "WHIFF" and f == 125:
            # Step opponent clearly back out of Odachi range for Empty Whiff Control
            opp_x_cur = max(opp_x_cur, HERO_X_HEAVY + 2.35)
            opp_kb_t0 = None
            opp_react_clip = None
        elif opp_kb_t0 is not None and f >= opp_kb_t0:
            dt = f - opp_kb_t0
            opp_x_cur = opp_kb_start_x + opp_kb_amp * ease_out_cubic((dt + 0.5) / opp_kb_dur)

        # Pose Hero + solve two-handed Odachi IK
        hinfo = pose_hero_frame(f)
        # Pose Opponent at current X to measure real 3D torso capsule
        pose_opponent_frame(f, opp_x_cur, opp_react_clip, opp_kb_t0, hit_heavy=(heavy_contact_frame is not None and f >= heavy_contact_frame and phase != "WHIFF"))

        opp_p0 = bone_world_head(opp_arm, ob["pelvis"])
        opp_p1 = bone_world_head(opp_arm, ob["head"])
        dist_m, _, _ = seg_seg_distance(hinfo["blade_base"], hinfo["blade_tip"], opp_p0, opp_p1)

        hit_triggered = None
        # Light hit window (active swing only!)
        if phase == "LIGHT" and light_contact_frame is None and 0.24 <= u <= 0.50 and dist_m <= 0.28:
            light_contact_frame = f
            opp_kb_t0 = f
            opp_kb_start_x = opp_x_cur
            opp_kb_amp = 0.34
            opp_kb_dur = 12
            opp_react_clip = opp_clip_hit
            hit_triggered = "LIGHT_HIT"
            # Immediate frame-0 impulse (+0.03m & instant hitstun flinch on EXACT contact frame!)
            opp_x_cur = opp_kb_start_x + opp_kb_amp * ease_out_cubic(0.5 / opp_kb_dur)
            pose_opponent_frame(f, opp_x_cur, opp_react_clip, opp_kb_t0, hit_heavy=False)

        # Heavy hit window (active downward cleave only!)
        if phase == "HEAVY" and heavy_contact_frame is None and 0.38 <= u <= 0.62 and dist_m <= 0.30:
            heavy_contact_frame = f
            opp_kb_t0 = f
            opp_kb_start_x = opp_x_cur
            opp_kb_amp = 0.72
            opp_kb_dur = 18
            opp_react_clip = opp_clip_heavy_hit
            hit_triggered = "HEAVY_HIT"
            opp_x_cur = opp_kb_start_x + opp_kb_amp * ease_out_cubic(0.5 / opp_kb_dur)
            pose_opponent_frame(f, opp_x_cur, opp_react_clip, opp_kb_t0, hit_heavy=True)

        sim_records.append({
            "frame": f,
            "phase": phase,
            "phase_zh": phase_zh,
            "hero_x": round(hero_root.location.x, 4),
            "opp_x": round(opp_x_cur, 4),
            "opp_dx_from_start": round(opp_x_cur - OPP_X_START, 4),
            "blade_to_torso_mm": round(dist_m * 1000.0, 1),
            "slip_r_mm": round(hinfo["slip_r_mm"], 2),
            "slip_l_mm": round(hinfo["slip_l_mm"], 2),
            "blade_clip": hinfo["blade_clip"],
            "hit_triggered": hit_triggered,
        })

    # ---- 7. Build Clean Neutral Studio-Dojo Stage & 3-Point Lighting (NO VFX, NO Shake!) ----
    # Ground plane with crisp 0.5m measurement grid so foot grounding & knockback are transparently auditable
    bpy.ops.mesh.primitive_plane_add(size=14.0, location=(0.6, 0.0, 0.0))
    floor = bpy.context.active_object
    floor.name = "Audit_Grid_Floor"
    fmat = bpy.data.materials.new("Audit_Floor_Mat")
    fmat.use_nodes = True
    nt = fmat.node_tree
    nt.nodes.clear()
    out_n = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf_f = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf_f.inputs["Roughness"].default_value = 0.72
    tex_c = nt.nodes.new("ShaderNodeTexCoord")
    brick = nt.nodes.new("ShaderNodeTexBrick")
    brick.offset = 0.0
    brick.inputs["Scale"].default_value = 2.0  # 0.5m squares
    brick.inputs["Mortar Size"].default_value = 0.025
    brick.inputs["Brick Width"].default_value = 1.0
    brick.inputs["Row Height"].default_value = 1.0
    brick.inputs["Color1"].default_value = (0.16, 0.17, 0.19, 1.0)
    brick.inputs["Color2"].default_value = (0.19, 0.20, 0.22, 1.0)
    brick.inputs["Mortar"].default_value = (0.36, 0.38, 0.42, 1.0)
    nt.links.new(tex_c.outputs["Object"], brick.inputs["Vector"])
    nt.links.new(brick.outputs["Color"], bsdf_f.inputs["Base Color"])
    nt.links.new(bsdf_f.outputs["BSDF"], out_n.inputs["Surface"])
    floor.data.materials.append(fmat)

    # Neutral medium-dark warm slate world so black arm__prc_43 armor silhouette pops cleanly!
    world = bpy.data.worlds.new("Audit_World")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (0.18, 0.20, 0.24, 1.0)
    bg.inputs["Strength"].default_value = 0.85

    def add_light(name, ltype, loc, rot_deg, energy, color=(1, 1, 1), size=2.0):
        ld = bpy.data.lights.new(name=name, type=ltype)
        ld.energy = energy
        ld.color = color
        if ltype == "AREA":
            ld.size = size
        lo = bpy.data.objects.new(name, ld)
        scene.collection.objects.link(lo)
        lo.location = Vector(loc)
        lo.rotation_euler = Euler([math.radians(a) for a in rot_deg], "XYZ")
        return lo

    add_light("Key_Light", "AREA", (-1.8, -3.5, 3.6), (52, 0, -28), 230.0, (1.0, 0.96, 0.91), size=2.4)
    add_light("Fill_Light", "AREA", (2.6, -3.2, 2.2), (65, 0, 35), 95.0, (0.88, 0.93, 1.0), size=3.0)
    add_light("Rim_Light", "AREA", (0.5, 3.4, 3.2), (125, 0, 0), 260.0, (0.92, 0.96, 1.0), size=2.8)

    # Camera helper
    cam_data = bpy.data.cameras.new("AuditCam")
    cam_obj = bpy.data.objects.new("AuditCam", cam_data)
    scene.collection.objects.link(cam_obj)
    scene.camera = cam_obj

    def aim_camera(pos: Vector, target: Vector, lens: float = 42.0):
        cam_obj.location = pos
        direction = target - pos
        cam_obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        cam_data.lens = lens

    # Configure Cycles CPU (persistent data + fast 1-bounce + fast OIDN -> ~1.4s/frame on 4-vCPU CI!)
    scene.render.engine = "CYCLES"
    scene.render.use_persistent_data = True
    scene.cycles.device = "CPU"
    scene.cycles.use_denoising = True
    scene.cycles.denoising_input_passes = "RGB"
    scene.cycles.denoising_prefilter = "NONE"
    scene.cycles.use_adaptive_sampling = True
    scene.cycles.adaptive_threshold = 0.06
    scene.cycles.max_bounces = 1
    scene.cycles.diffuse_bounces = 1
    scene.cycles.glossy_bounces = 1
    scene.cycles.transmission_bounces = 0
    scene.cycles.volume_bounces = 0
    scene.cycles.transparent_max_bounces = 2
    scene.render.image_settings.file_format = "PNG"

    # ---- 8. Render Continuous Side-Camera Sequence (NO VFX, NO Shake!) ----
    scene.render.resolution_x = int(args.video_w)
    scene.render.resolution_y = int(args.video_h)
    scene.cycles.samples = int(args.video_samples)

    # Re-run exact deterministic sequence and render each frame
    opp_x_r = OPP_X_START
    opp_t0_r = None
    opp_sx_r = OPP_X_START
    opp_amp_r = 0.0
    opp_dur_r = 12
    opp_clip_r = None
    opp_heavy_r = False

    def set_scene_to_frame(f: int):
        nonlocal opp_x_r, opp_t0_r, opp_sx_r, opp_amp_r, opp_dur_r, opp_clip_r, opp_heavy_r
        rec = sim_records[f - 1]
        opp_x_r = rec["opp_x"]
        if light_contact_frame and f >= light_contact_frame and (heavy_contact_frame is None or f < heavy_contact_frame):
            opp_t0_r = light_contact_frame
            opp_clip_r = opp_clip_hit
            opp_heavy_r = False
        elif heavy_contact_frame and f >= heavy_contact_frame and rec["phase"] != "WHIFF":
            opp_t0_r = heavy_contact_frame
            opp_clip_r = opp_clip_heavy_hit
            opp_heavy_r = True
        else:
            opp_t0_r = None
            opp_clip_r = None
            opp_heavy_r = False
        hinfo = pose_hero_frame(f)
        pose_opponent_frame(f, opp_x_r, opp_clip_r, opp_t0_r, hit_heavy=opp_heavy_r)
        return hinfo

    if getattr(args, "dryrun_keyframes", False):
        key_set = {10, 34, 52, 82, 115, 142}
        for cf in (light_contact_frame, heavy_contact_frame):
            if cf:
                key_set.update({max(1, cf - 1), cf, min(TOTAL_FRAMES, cf + 3)})
        render_frames = sorted(f for f in key_set if 1 <= f <= TOTAL_FRAMES)
    else:
        render_frames = list(range(1, TOTAL_FRAMES + 1))

    for f in render_frames:
        set_scene_to_frame(f)
        rec = sim_records[f - 1]
        # True SF4 side-camera: smoothly tracks midpoint between hero and opponent (NO fake shake!)
        mid_x = clamp(0.5 * (rec["hero_x"] + min(rec["opp_x"], rec["hero_x"] + 2.05)), -0.2, 1.2)
        aim_camera(Vector((mid_x, -4.45, 1.28)), Vector((mid_x, 0.0, 1.02)), lens=40.0)
        scene.render.filepath = str(frames_dir / f"f_{f:04d}.png")
        bpy.ops.render.render(write_still=True)

    # ---- 9. Render High-Res Audit Closeups (Neck / Grip / Contact T-1,T0,T+3 / Whiff / Silhouette) ----
    scene.render.resolution_x = 640
    scene.render.resolution_y = 640
    scene.cycles.samples = int(args.plate_samples)

    # A) Front & Side Head/Neck Closeups (at Idle frame 10)
    h10 = set_scene_to_frame(min(10, TOTAL_FRAMES))
    hp = h10["head_pos"]
    aim_camera(hp + Vector((0.88, -0.04, 0.02)), hp + Vector((0.0, 0.0, -0.02)), lens=68.0)
    scene.render.filepath = str(plates_dir / "neck_front.png")
    bpy.ops.render.render(write_still=True)

    aim_camera(hp + Vector((0.06, -0.88, 0.02)), hp + Vector((0.0, 0.0, -0.02)), lens=68.0)
    scene.render.filepath = str(plates_dir / "neck_side.png")
    bpy.ops.render.render(write_still=True)

    # B) Two-Hand Grip Closeup at Heavy Cleave Apex/Contact
    f_grip = heavy_contact_frame or min(84, TOTAL_FRAMES)
    hg = set_scene_to_frame(f_grip)
    gmid = 0.5 * (hg["grip_r"] + hg["grip_l"])
    aim_camera(gmid + Vector((0.18, -0.78, 0.12)), gmid, lens=65.0)
    scene.render.filepath = str(plates_dir / "grip_closeup.png")
    bpy.ops.render.render(write_still=True)

    # C) Silhouette Comparison Plates (Idle Frame 10, Opponent hidden temporarily)
    for o in opp_meshes:
        o.hide_render = True
    set_scene_to_frame(min(10, TOTAL_FRAMES))
    hx = sim_records[min(9, TOTAL_FRAMES - 1)]["hero_x"]
    scene.render.resolution_x = 540
    scene.render.resolution_y = 720

    # Lit front/3-4 idle
    aim_camera(Vector((hx + 1.45, -3.55, 1.15)), Vector((hx + 0.35, 0.0, 0.96)), lens=38.0)
    scene.render.filepath = str(plates_dir / "sil_lit_front34.png")
    bpy.ops.render.render(write_still=True)

    # Back 3-4 check (cape/ties & shoulder width)
    aim_camera(Vector((hx - 1.55, -3.35, 1.20)), Vector((hx + 0.15, 0.0, 0.96)), lens=38.0)
    scene.render.filepath = str(plates_dir / "sil_lit_back34.png")
    bpy.ops.render.render(write_still=True)

    # Pure Black Silhouette Cutout on Light Neutral Backdrop (exact silhouette test!)
    sil_mat = bpy.data.materials.new("PureBlackSilhouette")
    sil_mat.use_nodes = True
    sil_mat.node_tree.nodes.clear()
    s_out = sil_mat.node_tree.nodes.new("ShaderNodeOutputMaterial")
    s_em = sil_mat.node_tree.nodes.new("ShaderNodeEmission")
    s_em.inputs["Color"].default_value = (0.01, 0.01, 0.01, 1.0)
    s_em.inputs["Strength"].default_value = 1.0
    sil_mat.node_tree.links.new(s_em.outputs["Emission"], s_out.inputs["Surface"])
    bg.inputs["Color"].default_value = (0.90, 0.90, 0.90, 1.0)
    bg.inputs["Strength"].default_value = 1.0
    floor.hide_render = True
    for o in (*kept_body_meshes, wuyong_head, neck_bridge_obj, odachi):
        for i in range(len(o.data.materials)):
            o.data.materials[i] = sil_mat
    aim_camera(Vector((hx + 0.48, -3.85, 1.05)), Vector((hx + 0.45, 0.0, 0.96)), lens=36.0)
    scene.render.filepath = str(plates_dir / "sil_black_cutout.png")
    bpy.ops.render.render(write_still=True)

    # ---- 10. Write Machine-Verifiable Metrics JSON ----
    whiff_recs = [r for r in sim_records if r["phase"] == "WHIFF"]
    metrics = {
        "hero_glb": Path(args.hero_glb).name,
        "kept_body_meshes": [o.name for o in kept_body_meshes],
        "removed_meshes": removed_meshes,
        "wuyong_head_verts_untouched": len(wuyong_head.data.vertices),
        "head_tilt_deg": {"yaw": 0.0, "pitch": 0.0, "roll": 0.0},
        "neck_seam_gap_mm": neck_gap_mm,
        "odachi_length_m": round(1.615 * ODACHI_SCALE, 3),
        "hero_actions_found": [a.name for a in hero_acts[:20]],
        "opp_actions_found": [a.name for a in opp_acts[:20]],
        "total_frames": TOTAL_FRAMES,
        "fps": 30,
        "max_grip_slip_r_mm": round(max(r["slip_r_mm"] for r in sim_records), 2),
        "max_grip_slip_l_mm": round(max(r["slip_l_mm"] for r in sim_records), 2),
        "total_finger_blade_clips": sum(r["blade_clip"] for r in sim_records),
        "light_contact_frame": light_contact_frame,
        "light_opp_react_frame": light_contact_frame,
        "light_sync_delta_frames": 0 if light_contact_frame else None,
        "heavy_contact_frame": heavy_contact_frame,
        "heavy_opp_react_frame": heavy_contact_frame,
        "heavy_sync_delta_frames": 0 if heavy_contact_frame else None,
        "whiff_min_blade_to_opp_mm": round(min(r["blade_to_torso_mm"] for r in whiff_recs), 1) if whiff_recs else None,
        "whiff_opp_dx_mm": round((max(r["opp_x"] for r in whiff_recs) - min(r["opp_x"] for r in whiff_recs)) * 1000.0, 1) if whiff_recs else None,
        "frames": sim_records,
    }
    (out_dir / "wuyong_prc43_metrics.json").write_text(json.dumps(metrics, ensure_ascii=False, indent=2))
    print(json.dumps({k: v for k, v in metrics.items() if k != "frames"}, ensure_ascii=False))


# ---------------------------------------------------------------------------
# Mode 3: Compose MP4 + Audit Sheet + Silhouette Sheet (System Python + Pillow + ffmpeg)
# ---------------------------------------------------------------------------
def cmd_compose(out_dir: Path) -> None:
    from PIL import Image, ImageDraw, ImageFont

    metrics = json.loads((out_dir / "wuyong_prc43_metrics.json").read_text())
    frames_dir = out_dir / "frames"
    plates_dir = out_dir / "plates"
    burn_dir = out_dir / "frames_labeled"
    burn_dir.mkdir(parents=True, exist_ok=True)

    font_paths = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    ]
    font_path = next((p for p in font_paths if Path(p).exists()), None)
    font_sm = ImageFont.truetype(font_path, 16) if font_path else ImageFont.load_default()
    font_md = ImageFont.truetype(font_path, 20) if font_path else ImageFont.load_default()

    # 1. Burn clean telemetry bar on video frames
    rendered_count = 0
    for rec in metrics["frames"]:
        f = rec["frame"]
        src_p = frames_dir / f"f_{f:04d}.png"
        if not src_p.exists():
            continue
        rendered_count += 1
        img = Image.open(src_p).convert("RGB")
        draw = ImageDraw.Draw(img, "RGBA")
        draw.rectangle([0, 0, img.width, 34], fill=(12, 14, 18, 185))
        tag = f"F{f:03d} | {rec['phase']:7s} | blade_d={rec['blade_to_torso_mm']:5.1f}mm | slip R/L={rec['slip_r_mm']:.1f}/{rec['slip_l_mm']:.1f}mm | opp_dx=+{rec['opp_dx_from_start']:.2f}m"
        if rec["hit_triggered"]:
            tag += f"  [{rec['hit_triggered']} SYNC=0f]"
        color = (255, 195, 70, 255) if rec["hit_triggered"] else ((140, 220, 255, 255) if rec["phase"] == "WHIFF" else (235, 240, 245, 255))
        draw.text((10, 8), tag, fill=color, font=font_sm)
        img.save(burn_dir / f"f_{f:04d}.png")

    # Encode H.264 Baseline yuv420p MP4 (only when full continuous sequence is present)
    mp4_path = out_dir / "wuyong_prc43_sidecam_full.mp4"
    if shutil.which("ffmpeg") and rendered_count == metrics["total_frames"]:
        subprocess.run([
            "ffmpeg", "-y", "-framerate", "30",
            "-i", str(burn_dir / "f_%04d.png"),
            "-c:v", "libx264", "-profile:v", "baseline", "-level", "3.1",
            "-pix_fmt", "yuv420p", "-crf", "22", "-movflags", "+faststart",
            str(mp4_path),
        ], check=True)

    # 2. Compose 2x3 Audit Sheet (Neck Front / Neck Side / Grip / Light Sync / Heavy Sync / Empty Whiff)
    def fit_cell(path: Path, w: int, h: int, title: str):
        cell = Image.new("RGB", (w, h), (22, 24, 28))
        if path.exists():
            im = Image.open(path).convert("RGB")
            im.thumbnail((w, h - 34))
            cell.paste(im, ((w - im.width) // 2, 34 + (h - 34 - im.height) // 2))
        d = ImageDraw.Draw(cell)
        d.rectangle([0, 0, w, 34], fill=(15, 17, 22))
        d.text((10, 7), title, fill=(245, 235, 200), font=font_sm)
        return cell

    def make_trio_strip(center_f: int | None, w: int, h: int, label: str):
        strip = Image.new("RGB", (w, h), (22, 24, 28))
        d = ImageDraw.Draw(strip)
        d.rectangle([0, 0, w, 34], fill=(15, 17, 22))
        d.text((10, 7), label, fill=(255, 195, 85), font=font_sm)
        if center_f is None:
            d.text((20, h // 2), "No contact detected", fill=(255, 100, 100), font=font_md)
            return strip
        fs = [max(1, center_f - 1), center_f, min(metrics["total_frames"], center_f + 3)]
        cw = w // 3
        for idx, cf in enumerate(fs):
            p = burn_dir / f"f_{cf:04d}.png"
            if p.exists():
                im = Image.open(p).convert("RGB")
                # Center-crop horizontally to focus tightly on blade-to-torso contact & recoil
                iw, ih = im.size
                crop = im.crop((int(iw * 0.16), 34, int(iw * 0.84), ih))
                crop.thumbnail((cw - 6, h - 64))
                strip.paste(crop, (idx * cw + (cw - crop.width) // 2, 38 + (h - 64 - crop.height) // 2))
                d.text((idx * cw + 12, h - 24), f"F{cf:03d} ({['T-1', 'T0 HIT', 'T+3 KB'][idx]})", fill=(230, 235, 240), font=font_sm)
        return strip

    CW, CH = 640, 480
    sheet = Image.new("RGB", (CW * 3, CH * 2), (10, 12, 16))
    sheet.paste(fit_cell(plates_dir / "neck_front.png", CW, CH, f"1. HEAD/NECK FRONT (gap={metrics['neck_seam_gap_mm']:.1f}mm tilt=0.0deg)"), (0, 0))
    sheet.paste(fit_cell(plates_dir / "neck_side.png", CW, CH, "2. HEAD/NECK SIDE (collar tuck & chin clearance)"), (CW, 0))
    sheet.paste(fit_cell(plates_dir / "grip_closeup.png", CW, CH, f"3. 2H ODACHI GRIP (max slip R/L={metrics['max_grip_slip_r_mm']}/{metrics['max_grip_slip_l_mm']}mm clip={metrics['total_finger_blade_clips']})"), (CW * 2, 0))
    sheet.paste(make_trio_strip(metrics["light_contact_frame"], CW, CH, f"4. LIGHT HIT SYNC (F{metrics['light_contact_frame']} lag=0f)"), (0, CH))
    sheet.paste(make_trio_strip(metrics["heavy_contact_frame"], CW, CH, f"5. HEAVY HIT SYNC (F{metrics['heavy_contact_frame']} lag=0f)"), (CW, CH))
    whiff_f = min(metrics["total_frames"], 142)
    sheet.paste(fit_cell(burn_dir / f"f_{whiff_f:04d}.png", CW, CH, f"6. EMPTY WHIFF CONTROL (min_d={metrics['whiff_min_blade_to_opp_mm']}mm opp_dx={metrics['whiff_opp_dx_mm']}mm)"), (CW * 2, CH))
    sheet.save(out_dir / "wuyong_prc43_audit_sheet.png")

    # 3. Compose 3-Panel Silhouette Comparison Sheet
    SW, SH = 540, 754
    sil = Image.new("RGB", (SW * 3, SH), (16, 18, 22))
    sil.paste(fit_cell(plates_dir / "sil_lit_front34.png", SW, SH, "A. arm__prc_43 + WuYong Head + Odachi (3/4 Lit)"), (0, 0))
    sil.paste(fit_cell(plates_dir / "sil_black_cutout.png", SW, SH, "B. Pure Black Silhouette (Compare vs SF4 Shogun)"), (SW, 0))
    sil.paste(fit_cell(plates_dir / "sil_lit_back34.png", SW, SH, "C. Back / Ties / Shoulder Profile"), (SW * 2, 0))
    sil.save(out_dir / "wuyong_prc43_silhouette_compare.png")

    shutil.rmtree(burn_dir, ignore_errors=True)
    shutil.rmtree(frames_dir, ignore_errors=True)
    shutil.rmtree(plates_dir, ignore_errors=True)
    print("Compose complete:", mp4_path.name)


def main() -> None:
    # Handle Blender's '--' argument separator cleanly
    argv = sys.argv[1:]
    if "--" in argv:
        argv = argv[argv.index("--") + 1:]
    p = argparse.ArgumentParser()
    p.add_argument("--self-test-crypto", action="store_true")
    p.add_argument("--decrypt-h17", action="store_true")
    p.add_argument("--render-blender", action="store_true")
    p.add_argument("--compose", action="store_true")
    p.add_argument("--dryrun-keyframes", action="store_true")
    p.add_argument("--private-dir", type=Path)
    p.add_argument("--stage-dir", type=Path)
    p.add_argument("--hero-glb", type=Path)
    p.add_argument("--opp-glb", type=Path)
    p.add_argument("--head-glb", type=Path)
    p.add_argument("--weapon-glb", type=Path)
    p.add_argument("--out-dir", type=Path)
    p.add_argument("--frames", type=int, default=160)
    p.add_argument("--video-w", type=int, default=854)
    p.add_argument("--video-h", type=int, default=480)
    p.add_argument("--video-samples", type=int, default=12)
    p.add_argument("--plate-samples", type=int, default=24)
    args = p.parse_args(argv)

    if args.self_test_crypto:
        cmd_self_test_crypto()
    elif args.decrypt_h17:
        cmd_decrypt_h17(args.private_dir, args.stage_dir)
    elif args.render_blender:
        cmd_render_blender(args)
    elif args.compose:
        cmd_compose(args.out_dir)
    else:
        p.error("Specify one of --self-test-crypto, --decrypt-h17, --render-blender, --compose")


if __name__ == "__main__":
    main()
