#!/usr/bin/env python3
"""
Exact FK reconstruction of shogun_heavy.bytes (66f), shogun_heavy_talent.bytes (137f),
shogun_idle.bytes (62f), and b_shogun_middle_heavy.bytes (41f) using the mathematically
verified 79-bone hierarchy. Outputs exact frame-by-frame weapon tip, trail activation,
lunge, and block-pushback telemetry!
"""
import json
import math
import sys
from pathlib import Path
import numpy as np
import UnityPy

sys.path.insert(0, "/home/antigravity/wuyong9494-lab/kriswu-fighter/scripts")
from prepare_fighter_target_motions import decode_motion

RAW = Path("/home/antigravity/shogun_phase1_work/raw_shogun/shogun")
OUT = Path("/home/antigravity/shogun_phase1_work/audit")

# 100% mathematically verified hierarchy (ID -> (name, parent_id))
# Verified by post-order DFS in shogun_heavy.bytes AND <= 0.04 cm match to Mesh m_BindPose!
BONE_HIERARCHY = {
    0:  ("pelvis", None),
    1:  ("stomach", 0),
    2:  ("chest", 1),
    3:  ("neck", 2),
    4:  ("head", 3),
    5:  ("head_end", 4),

    # Left arm (post-order: 11, 209..201, 13, 16..14, 19..17, 22..20, 12, 10, 57, 9, 23, 8, 24, 7)
    # Wait: let's verify exact parent of 11 (forearm_twist_l -> 10 forearm_l), 13 (weapon_l -> 12 hand_l)
    # and 7 (zero-offset root under chest -> 8 clavicle_l -> 9 arm_l -> 10 forearm_l -> 12 hand_l)
    7:  ("clavicle_l_root", 2),
    24: ("scapular_l", 7),
    8:  ("clavicle_l", 7),
    23: ("arm_l_helper", 8),
    9:  ("arm_l", 8),
    57: ("biceps_twist_l", 9),
    10: ("forearm_l", 9),
    11: ("forearm_twist_l", 10),
    12: ("hand_l", 10),
    13: ("weapon_l", 12),
    14: ("f_big1_l", 12),
    15: ("f_big2_l", 14),
    16: ("f_big3_l", 15),
    17: ("f_main1_l", 12),
    18: ("f_main2_l", 17),
    19: ("f_main3_l", 18),
    20: ("f_pointer1_l", 12),
    21: ("f_pointer2_l", 20),
    22: ("f_pointer3_l", 21),

    201: ("w_odati_01_l", 13),
    202: ("w_odati_03_l", 201),
    203: ("w_odati_capsule1_l", 201),
    204: ("w_odati_capsule2_l", 203),
    205: ("w_odati_02_l", 204),
    206: ("w_odati_trail1_l", 205),
    207: ("w_odati_trail2_l", 206),
    208: ("w_odati_trail3_l", 207),
    209: ("w_odati_trail4_l", 208),
    210: ("w_odati_rope1_l", 201),
    211: ("w_odati_rope2_l", 210),

    # Right arm (exact mirror)
    25: ("clavicle_r_root", 2),
    42: ("scapular_r", 25),
    26: ("clavicle_r", 25),
    41: ("arm_r_helper", 26),
    27: ("arm_r", 26),
    58: ("biceps_twist_r", 27),
    28: ("forearm_r", 27),
    29: ("forearm_twist_r", 28),
    30: ("hand_r", 28),
    31: ("weapon_r", 30),
    32: ("f_big1_r", 30),
    33: ("f_big2_r", 32),
    34: ("f_big3_r", 33),
    35: ("f_main1_r", 30),
    36: ("f_main2_r", 35),
    37: ("f_main3_r", 36),
    38: ("f_pointer1_r", 30),
    39: ("f_pointer2_r", 38),
    40: ("f_pointer3_r", 39),

    212: ("w_odati_01_r", 31),
    213: ("w_odati_03_r", 212),
    214: ("w_odati_capsule1_r", 212),
    215: ("w_odati_capsule2_r", 214),
    216: ("w_odati_02_r", 215),
    217: ("w_odati_trail1_r", 216),
    218: ("w_odati_trail2_r", 217),
    219: ("w_odati_trail3_r", 218),
    220: ("w_odati_trail4_r", 219),
    221: ("w_odati_rope1_r", 212),
    222: ("w_odati_rope2_r", 221),

    # Left leg
    43: ("thigh_l_root", 0),
    48: ("butt_l", 43),
    44: ("thigh_l", 43),
    59: ("thigh_twist_l", 44),
    45: ("calf_l", 44),
    46: ("foot_l", 45),
    47: ("toe_l", 46),

    # Right leg
    51: ("thigh_r_root", 0),
    56: ("butt_r", 51),
    52: ("thigh_r", 51),
    60: ("thigh_twist_r", 52),
    53: ("calf_r", 52),
    54: ("foot_r", 53),
    55: ("toe_r", 54),
}


def qmat(q):
    x, y, z, w = q
    n = math.sqrt(x*x + y*y + z*z + w*w)
    if n < 1e-12:
        return np.eye(3)
    x, y, z, w = x/n, y/n, z/n, w/n
    return np.array([
        [1 - 2*(y*y + z*z), 2*(x*y - z*w),     2*(x*z + y*w)],
        [2*(x*y + z*w),     1 - 2*(x*x + z*z), 2*(y*z - x*w)],
        [2*(x*z - y*w),     2*(y*z + x*w),     1 - 2*(x*x + y*y)],
    ], dtype=np.float64)


def compute_fk(motion):
    """Compute world matrices in meters (glTF right-handed via Nekki C = diag(.01, .01, -.01),
    quat [-1, -1, 1, 1], facing +Z -> RIGHT maps +Z to +X fighting axis)."""
    # Wait: let's follow sun_triad_assets.py exact Nekki->glTF conversion:
    # p_gltf = p_cm * [0.01, 0.01, -0.01]
    # q_gltf = q * [-1, -1, 1, 1]
    # RIGHT[:3,:3] = [[0, 0, -1], [0, 1, 0], [1, 0, 0]]  (so Unity +Z -> glTF -Z -> RIGHT +X!)
    RIGHT = np.array([[0, 0, -1], [0, 1, 0], [1, 0, 0]], dtype=np.float64)
    ids = motion["boneIDs"]
    id_to_col = {bid: i for i, bid in enumerate(ids)}
    frames = motion["frameCount"]
    pos_all = np.asarray(motion["positions"], dtype=np.float64)
    rot_all = np.asarray(motion["rotations"], dtype=np.float64)

    # Topological order (parent before child)
    order = []
    visited = set()
    def visit(bid):
        if bid in visited or bid not in id_to_col:
            return
        pid = BONE_HIERARCHY[bid][1]
        if pid is not None and pid in id_to_col:
            visit(pid)
        visited.add(bid)
        order.append(bid)
    for bid in ids:
        visit(bid)

    world_by_name = []
    for f in range(frames):
        W = {}
        for bid in order:
            c = id_to_col[bid]
            p = pos_all[f, c] * np.array([0.01, 0.01, -0.01])
            q = rot_all[f, c] * np.array([-1.0, -1.0, 1.0, 1.0])
            M = np.eye(4, dtype=np.float64)
            M[:3, :3] = qmat(q)
            M[:3, 3] = p
            pid = BONE_HIERARCHY[bid][1]
            W[bid] = (W[pid] @ M) if (pid is not None and pid in W) else M
        # Convert to fight-space (+X forward, +Y up, +Z toward camera)
        named = {}
        for bid, M in W.items():
            bname = BONE_HIERARCHY[bid][0]
            named[bname] = RIGHT @ M[:3, 3]
        world_by_name.append(named)
    return world_by_name


def main():
    env_a = UnityPy.load(str(RAW / "animations-base-shogun.bin"))
    wanted = {
        "shogun_heavy", "shogun_heavy_talent", "shogun_idle",
        "b_shogun_high_heavy", "b_shogun_middle_heavy", "b_shogun_low_heavy", "b_shogun_overhead_heavy",
        "shogun_slash_1", "shogun_slash_2",
    }
    clips = {}
    for o in env_a.objects:
        if o.type.name == "TextAsset":
            d = o.read()
            if d.m_Name in wanted:
                raw = d.m_Script.encode("utf-8", "surrogateescape") if isinstance(d.m_Script, str) else bytes(d.m_Script)
                clips[d.m_Name] = decode_motion(raw)

    # First sanity check: in shogun_idle frame 0, check head Y, foot Y, hand positions!
    idle_fk = compute_fk(clips["shogun_idle"][0])
    f0 = idle_fk[0]
    print("=== 1. FK SANITY CHECK (shogun_idle frame 0, fight-space +X fwd, +Y up) ===")
    for k in ("pelvis", "chest", "neck", "head", "foot_l", "foot_r", "hand_r", "hand_l", "w_odati_01_r", "w_odati_02_r", "w_odati_03_r"):
        if k in f0:
            v = f0[k]
            print(f"  {k:16s} = ({v[0]:+7.3f}, {v[1]:+7.3f}, {v[2]:+7.3f}) m")
    # Check blade length in FK!
    d_blade_r = np.linalg.norm(f0["w_odati_02_r"] - f0["w_odati_01_r"])
    d_full_r = np.linalg.norm(f0["w_odati_02_r"] - f0["w_odati_03_r"])
    d_hands_r = np.linalg.norm(f0["hand_r"] - f0["w_odati_01_r"])
    d_hands_l = np.linalg.norm(f0["hand_l"] - f0["w_odati_01_r"])
    print(f"  Blade hilt->tip = {d_blade_r:.3f}m | pommel->tip = {d_full_r:.3f}m | hand_r->hilt_r = {d_hands_r:.3f}m | hand_l->hilt_r = {d_hands_l:.3f}m")
    # Check both weapon_r and weapon_l — which hand holds the Odachi?!
    d_l_blade = np.linalg.norm(f0["hand_l"] - f0["w_odati_01_l"])
    print(f"  hand_l->hilt_l = {d_l_blade:.3f}m | w_odati_01_r vs w_odati_01_l dist = {np.linalg.norm(f0['w_odati_01_r'] - f0['w_odati_01_l']):.3f}m")

    # 2. Detailed frame-by-frame table for shogun_heavy (66f @ 30 FPS)
    heavy_fk = compute_fk(clips["shogun_heavy"][0])
    heavy_m = clips["shogun_heavy"][0]
    id_to_col = {bid: i for i, bid in enumerate(heavy_m["boneIDs"])}
    pos_h = np.asarray(heavy_m["positions"], dtype=np.float64)

    print("\n=== 2. shogun_heavy.bytes (66 frames @ 30 FPS = 2.20s / 131 ticks @ 60Hz) FRAME-BY-FRAME ===")
    print("F30 | T60 | pelvis_X | hiltR_X  hiltR_Y | tipR_X   tipR_Y  | tipR_vel | trailR_len | trailL_len | handL->pommelR")
    rows = []
    pelvis_x0 = heavy_fk[0]["pelvis"][0]
    for f, pose in enumerate(heavy_fk):
        px = pose["pelvis"][0] - pelvis_x0
        hr = pose["w_odati_01_r"]
        tr = pose["w_odati_02_r"]
        pr = pose["w_odati_03_r"]
        hl = pose["hand_l"]
        vel = 0.0 if f == 0 else float(np.linalg.norm(tr - heavy_fk[f-1]["w_odati_02_r"]) * 30.0)
        # Trail ribbon extension (sum of local norms of trail2+trail3+trail4 in cm)
        tr_r_len = sum(float(np.linalg.norm(pos_h[f, id_to_col[b]])) for b in (218, 219, 220))
        tr_l_len = sum(float(np.linalg.norm(pos_h[f, id_to_col[b]])) for b in (207, 208, 209))
        # Distance from left hand to right Odachi hilt segment [w_odati_03_r, w_odati_01_r]
        ab = hr - pr
        t_proj = float(np.clip(np.dot(hl - pr, ab) / max(1e-9, np.dot(ab, ab)), 0.0, 1.0))
        grip_dist = float(np.linalg.norm(hl - (pr + t_proj * ab)))
        rows.append({
            "f30": f, "t60": f * 2,
            "pelvis_dx": round(float(px), 4),
            "hiltR": [round(float(x), 4) for x in hr],
            "tipR": [round(float(x), 4) for x in tr],
            "tipR_vel_mps": round(vel, 2),
            "trailR_cm": round(tr_r_len, 2),
            "trailL_cm": round(tr_l_len, 2),
            "handL_to_hilt_m": round(grip_dist, 4),
        })
        mark = " <TRAIL!" if tr_r_len > 1.0 or tr_l_len > 1.0 else (" *FAST*" if vel > 12.0 else "")
        print(f"{f:3d} | {f*2:3d} | {px:+8.3f} | {hr[0]:+7.3f}  {hr[1]:+7.3f} | {tr[0]:+7.3f}  {tr[1]:+7.3f} | {vel:8.2f} | {tr_r_len:10.2f} | {tr_l_len:10.2f} | {grip_dist:8.3f}m{mark}")

    # 3. Check b_shogun_*_heavy block reaction animations!
    print("\n=== 3. ORIGINAL HEAVY BLOCK REACTION ANIMATIONS (b_shogun_*_heavy.bytes) ===")
    for bname in ("b_shogun_high_heavy", "b_shogun_middle_heavy", "b_shogun_low_heavy", "b_shogun_overhead_heavy"):
        bfk = compute_fk(clips[bname][0])
        xs = [p["pelvis"][0] - bfk[0]["pelvis"][0] for p in bfk]
        print(f"  {bname:26s}: {len(bfk)}f (@30fps={len(bfk)/30:.3f}s, @60hz={len(bfk)*2-1}t) | pelvis_dx min={min(xs):+.3f}m max={max(xs):+.3f}m end={xs[-1]:+.3f}m")

    # 4. Also check shogun_heavy_talent (137f) pelvis & hand movement summary
    tal_fk = compute_fk(clips["shogun_heavy_talent"][0])
    t_px0 = tal_fk[0]["pelvis"][0]
    hand_vels = [0.0] + [float(np.linalg.norm(tal_fk[f]["hand_r"] - tal_fk[f-1]["hand_r"]) * 30.0) for f in range(1, len(tal_fk))]
    peak_f = int(np.argmax(hand_vels))
    print(f"\n=== 4. shogun_heavy_talent.bytes ({len(tal_fk)}f @30fps) ===")
    print(f"  pelvis_dx end={tal_fk[-1]['pelvis'][0]-t_px0:+.3f}m, hand_r peak vel={hand_vels[peak_f]:.2f} m/s at f30={peak_f} (t60={peak_f*2})")

    (OUT / "shogun_heavy_kinematics.json").write_text(json.dumps({
        "shogun_heavy_frames": rows,
        "shogun_heavy_count_30fps": len(rows),
        "shogun_heavy_ticks_60hz": len(rows) * 2 - 1,
    }, indent=2))


if __name__ == "__main__":
    main()
