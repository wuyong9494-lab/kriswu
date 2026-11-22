#!/usr/bin/env python3
"""Author hero-specific, 60fps Shadow Fight 4 archetype combat animations and clean
GLB animation hygiene (LINEAR interpolation, zero quaternion flips, zero horizontal
knockdown drift, seamless idle convergence) across all 4 DuelChar_*.glb heroes.

Pure Python3 stdlib — edits ONLY animation channels/samplers in the GLB binaries;
all character meshes, heads, textures, skins, and rest-pose joint transforms stay
100% untouched.

Usage:
    python3 scripts/author_sf4_combat_anims.py [--heroes wuYong xuXiao liuQuanwei sunDeng]
"""
import argparse
import copy
import json
import math
import struct
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
CHAR_DIR = REPO / "App/Resources/DuelCharacters"
sys.path.insert(0, str(REPO / "scripts"))
import glb_audit as ga  # noqa: E402

HERO_ENUM = {"wuYong": "wuYong", "xuXiao": "gale", "liuQuanwei": "liu", "sunDeng": "ember"}
HERO_RIG_SUFFIX = {
    "wuYong": "WuYong_Rig",
    "xuXiao": "XuXiao_Rig",
    "liuQuanwei": "LiuQuanwei_Rig",
    "sunDeng": "SunDeng_Rig",
}


# ------------------------------------------------------------------ 3D math
def vadd(a, b): return (a[0] + b[0], a[1] + b[1], a[2] + b[2])
def vsub(a, b): return (a[0] - b[0], a[1] - b[1], a[2] - b[2])
def vscale(a, s): return (a[0] * s, a[1] * s, a[2] * s)
def vdot(a, b): return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
def vlen(a): return math.sqrt(vdot(a, a))


def vnorm(a):
    l = vlen(a)
    return (a[0] / l, a[1] / l, a[2] / l) if l > 1e-8 else (0.0, 1.0, 0.0)


def vcross(a, b):
    return (a[1] * b[2] - a[2] * b[1],
            a[2] * b[0] - a[0] * b[2],
            a[0] * b[1] - a[1] * b[0])


def qmul(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return (aw * bx + ax * bw + ay * bz - az * by,
            aw * by - ax * bz + ay * bw + az * bx,
            aw * bz + ax * by - ay * bx + az * bw,
            aw * bw - ax * bx - ay * by - az * bz)


def qinv(q): return (-q[0], -q[1], -q[2], q[3])


def qnorm(q):
    n = math.sqrt(sum(c * c for c in q)) or 1.0
    return (q[0] / n, q[1] / n, q[2] / n, q[3] / n)


def qaxis(axis, deg):
    if abs(deg) < 1e-6:
        return (0.0, 0.0, 0.0, 1.0)
    u = vnorm(axis)
    h = math.radians(deg) * 0.5
    s = math.sin(h)
    return (u[0] * s, u[1] * s, u[2] * s, math.cos(h))


def qrot(q, v):
    qv = (v[0], v[1], v[2], 0.0)
    r = qmul(qmul(q, qv), qinv(q))
    return (r[0], r[1], r[2])


def qfrom_to(u, v):
    u, v = vnorm(u), vnorm(v)
    d = max(-1.0, min(1.0, vdot(u, v)))
    if d > 0.999999:
        return (0.0, 0.0, 0.0, 1.0)
    if d < -0.999999:
        ortho = vcross((1.0, 0.0, 0.0), u)
        if vlen(ortho) < 1e-4:
            ortho = vcross((0.0, 1.0, 0.0), u)
        return qaxis(ortho, 180.0)
    c = vcross(u, v)
    return qnorm((c[0], c[1], c[2], 1.0 + d))


def qeuler_xyz(rx, ry, rz):
    # Apply Z then Y then X in world frame: qx * qy * qz
    q = (0.0, 0.0, 0.0, 1.0)
    if rx: q = qmul(q, qaxis((1, 0, 0), rx))
    if ry: q = qmul(q, qaxis((0, 1, 0), ry))
    if rz: q = qmul(q, qaxis((0, 0, 1), rz))
    return q


def qslerp(a, b, t):
    if sum(x * y for x, y in zip(a, b)) < 0:
        b = (-b[0], -b[1], -b[2], -b[3])
    dot = max(-1.0, min(1.0, sum(x * y for x, y in zip(a, b))))
    if dot > 0.9995:
        return qnorm(tuple(a[i] + (b[i] - a[i]) * t for i in range(4)))
    th = math.acos(dot)
    s0 = math.sin((1.0 - t) * th) / math.sin(th)
    s1 = math.sin(t * th) / math.sin(th)
    return qnorm(tuple(a[i] * s0 + b[i] * s1 for i in range(4)))


def m3_to_q(m):
    # 4x4 row-major matrix -> unit quaternion (x,y,z,w)
    m00, m01, m02 = m[0][0], m[0][1], m[0][2]
    m10, m11, m12 = m[1][0], m[1][1], m[1][2]
    m20, m21, m22 = m[2][0], m[2][1], m[2][2]
    tr = m00 + m11 + m22
    if tr > 0:
        s = math.sqrt(tr + 1.0) * 2.0
        w = 0.25 * s
        x = (m21 - m12) / s
        y = (m02 - m20) / s
        z = (m10 - m01) / s
    elif m00 > m11 and m00 > m22:
        s = math.sqrt(1.0 + m00 - m11 - m22) * 2.0
        w = (m21 - m12) / s
        x = 0.25 * s
        y = (m01 + m10) / s
        z = (m02 + m20) / s
    elif m11 > m22:
        s = math.sqrt(1.0 + m11 - m00 - m22) * 2.0
        w = (m02 - m20) / s
        x = (m01 + m10) / s
        y = 0.25 * s
        z = (m12 + m21) / s
    else:
        s = math.sqrt(1.0 + m22 - m00 - m11) * 2.0
        w = (m10 - m01) / s
        x = (m02 + m20) / s
        y = (m12 + m21) / s
        z = 0.25 * s
    return qnorm((x, y, z, w))


def ease_cubic(t, mode="inout"):
    t = max(0.0, min(1.0, t))
    if mode == "out":
        u = 1.0 - t
        return 1.0 - u * u * u
    if mode == "in":
        return t * t * t
    if mode == "snap":
        # Explosive martial snap: slow gather then sharp whip into contact
        return t * t * (2.2 - 1.2 * t) if t < 0.5 else 1.0 - ((1.0 - t) ** 3) * 4.0
    if mode == "whip":
        # Ultra-crisp strike acceleration peaking near end of segment
        return 1.0 - (1.0 - t) ** 2.4
    return t * t * (3.0 - 2.0 * t)


# ------------------------------------------------------------------ Rig wrapper
class Rig:
    def __init__(self, path: Path, hero_key: str):
        self.path = path
        self.hero_key = hero_key
        data = path.read_bytes()
        jlen = struct.unpack("<I", data[12:16])[0]
        self.json = json.loads(data[20:20 + jlen])
        blen = struct.unpack("<I", data[20 + jlen:24 + jlen])[0]
        self.bin = bytearray(data[28 + jlen:28 + jlen + blen])
        self.nodes = self.json["nodes"]
        self.by_name = {n.get("name", ""): i for i, n in enumerate(self.nodes)}
        self.parent = {}
        for i, n in enumerate(self.nodes):
            for c in n.get("children", []):
                self.parent[c] = i
        self.joints = list(self.json["skins"][0]["joints"])
        self.joint_names = [self.nodes[j]["name"] for j in self.joints]
        # Rest local T, R, S & world pos / rot
        self.rest_t = {}
        self.rest_r = {}
        self.rest_s = {}
        for i, n in enumerate(self.nodes):
            self.rest_t[i] = tuple(n.get("translation", (0.0, 0.0, 0.0)))
            self.rest_r[i] = qnorm(tuple(n.get("rotation", (0.0, 0.0, 0.0, 1.0))))
            self.rest_s[i] = tuple(n.get("scale", (1.0, 1.0, 1.0)))

        # Compute rest world pos & rot for every node
        self.rest_wp = {}
        self.rest_wr = {}
        for i in range(len(self.nodes)):
            self._calc_rest_world(i)

        # Load weapon JSON transform (for blade grip/haft offset)
        cfg_path = CHAR_DIR / f"DuelChar_{hero_key}.json"
        self.cfg = json.loads(cfg_path.read_text()) if cfg_path.exists() else {}
        rw = self.cfg.get("rightWeapon") or {}
        self.rw_pos = tuple(rw.get("position") or (0.0, 0.0, 0.0))
        self.rw_euler = tuple(rw.get("eulerDeg") or (0.0, 0.0, 0.0))
        self.rw_scale = float(rw.get("scale") or 1.0)

        # Limb segment lengths & canonical anatomical rest arm vectors
        self.len_thigh = vlen(vsub(self.wp("Shin.R"), self.wp("Thigh.R")))
        self.len_shin = vlen(vsub(self.wp("Foot.R"), self.wp("Shin.R")))
        self.len_uarm_l = vlen(vsub(self.wp("Forearm.L"), self.wp("UpperArm.L")))
        self.len_farm_l = vlen(vsub(self.wp("Hand.L"), self.wp("Forearm.L")))
        self.rest_ua_r_dir = vnorm(vsub(self.wp("Forearm.R"), self.wp("UpperArm.R")))
        self.rest_fa_r_dir = vnorm(vsub(self.wp("Hand.R"), self.wp("Forearm.R")))
        self.rest_ua_l_dir = vnorm(vsub(self.wp("Forearm.L"), self.wp("UpperArm.L")))
        self.rest_fa_l_dir = vnorm(vsub(self.wp("Hand.L"), self.wp("Forearm.L")))
        self.q_ua_r_zero = qfrom_to(self.rest_ua_r_dir, (0.0, -1.0, 0.0))
        self.q_fa_r_zero = qfrom_to(self.rest_fa_r_dir, self.rest_ua_r_dir)
        self.q_ua_l_zero = qfrom_to(self.rest_ua_l_dir, (0.0, -1.0, 0.0))
        self.q_fa_l_zero = qfrom_to(self.rest_fa_l_dir, self.rest_ua_l_dir)
        self.rest_hips_y = self.wp("Hips")[1]
        self.rest_foot_y = min(self.wp("Foot.L")[1], self.wp("Foot.R")[1])

    def _calc_rest_world(self, i):
        if i in self.rest_wp:
            return
        if i in self.parent:
            p = self.parent[i]
            self._calc_rest_world(p)
            pr = self.rest_wr[p]
            pp = self.rest_wp[p]
            ps = self.rest_s[p]
            lt = self.rest_t[i]
            scaled_lt = (lt[0] * ps[0], lt[1] * ps[1], lt[2] * ps[2])
            self.rest_wp[i] = vadd(pp, qrot(pr, scaled_lt))
            self.rest_wr[i] = qnorm(qmul(pr, self.rest_r[i]))
        else:
            self.rest_wp[i] = self.rest_t[i]
            self.rest_wr[i] = self.rest_r[i]

    def idx(self, name): return self.by_name[name]
    def wp(self, name): return self.rest_wp[self.by_name[name]]
    def wr(self, name): return self.rest_wr[self.by_name[name]]

    def read_acc(self, acc_idx):
        a = self.json["accessors"][acc_idx]
        bv = self.json["bufferViews"][a["bufferView"]]
        n = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
        off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
        stride = bv.get("byteStride", 4 * n)
        return [struct.unpack_from("<%df" % n, self.bin, off + k * stride) for k in range(a["count"])]

    def append_acc(self, rows, typ, with_bounds=False):
        while len(self.bin) % 4:
            self.bin.append(0)
        off = len(self.bin)
        n = len(rows[0])
        for r in rows:
            self.bin += struct.pack("<%df" % n, *r)
        self.json["bufferViews"].append({
            "buffer": 0, "byteOffset": off, "byteLength": len(self.bin) - off
        })
        acc = {
            "bufferView": len(self.json["bufferViews"]) - 1,
            "componentType": 5126, "count": len(rows), "type": typ
        }
        if with_bounds:
            acc["min"] = [min(r[i] for r in rows) for i in range(n)]
            acc["max"] = [max(r[i] for r in rows) for i in range(n)]
        self.json["accessors"].append(acc)
        return len(self.json["accessors"]) - 1

    # ---- Forward kinematics given local T/R overrides for joints
    def fk(self, local_r, local_t=None):
        local_t = local_t or {}
        wp, wr = {}, {}
        def eval_n(i):
            if i in wp: return
            r = local_r.get(i, self.rest_r[i])
            t = local_t.get(i, self.rest_t[i])
            if i in self.parent:
                p = self.parent[i]
                eval_n(p)
                ps = self.rest_s[p]
                st = (t[0] * ps[0], t[1] * ps[1], t[2] * ps[2])
                wp[i] = vadd(wp[p], qrot(wr[p], st))
                wr[i] = qnorm(qmul(wr[p], r))
            else:
                wp[i] = t
                wr[i] = r
        for j in self.joints:
            eval_n(j)
        return wp, wr

    def delta_local(self, name, world_delta_q):
        """Local rotation for bone `name` applying incremental world-space rotation `world_delta_q`
        on top of parent's accumulated rotation: L_new = L_0 * (R_0^-1 * Q * R_0)."""
        i = self.idx(name)
        r0 = self.rest_wr[i]
        conj = qmul(qmul(qinv(r0), world_delta_q), r0)
        return qnorm(qmul(self.rest_r[i], conj))

    def abs_local(self, name, parent_wr, target_wr):
        """Local rotation so node's world rotation equals `target_wr` given parent's world rotation."""
        return qnorm(qmul(qinv(parent_wr), target_wr))

    # ---- High-level pose builder from martial-arts parameters
    def build_pose(self, p):
        """Build a complete anatomically valid joint pose (local_r, local_t) from semantic params:
          hip_h: target hip height (m)
          hips_yaw, hips_pitch, hips_roll: pelvis orientation (deg)
          lean: torso forward pitch (+Z, deg)
          twist: torso yaw (+Y = right shoulder forward, -Y = coiled back, deg)
          tilt: torso roll (+Z, deg)
          head_lock: True keeps head looking forward at opponent
          stance: foot-to-foot Z separation (m)
          wf: hips weight fraction from rear foot (0=back, 1=front)
          front_leg: 'L' or 'R' (which leg is forward in stance)
          kick_leg: None or 'R'/'L'
          kick_target: (z_rel, y_abs) for kick ankle if kick_leg set
          r_arm: (pitch, yaw, roll) for UpperArm.R in glTF world delta
          r_elbow: (pitch, yaw, roll) for Forearm.R in glTF world delta
          blade_angle: target side-view weapon angle in deg (0=fwd, +90=up, 180=back, -90=down)
          blade_yaw: optional sideways blade sweep yaw (deg, + = across left, - = out right)
          blade_max_wrist: clamp wrist adjustment (deg, default 105)
          two_handed: True runs 2-bone IK on left arm to grip weapon haft!
          haft_offset: distance along blade_dir from weapon_socket_r for left hand grip (m)
          l_arm, l_elbow: manual left arm deltas (used when not two_handed)
          blade_l_angle, blade_l_yaw: target angle for left ninjato (sunDeng)
          cape_pitch: dynamic trailing cape/coat pitch (deg)
        """
        lr = {j: self.rest_r[j] for j in self.joints}
        lt = {j: self.rest_t[j] for j in self.joints}

        # 1. Pelvis & Hips height
        hip_h = p.get("hip_h", 0.90)
        hips_idx = self.idx("Hips")
        base_hips_t = self.rest_t[hips_idx]
        dy = hip_h - self.rest_hips_y
        lt[hips_idx] = (base_hips_t[0], base_hips_t[1] + dy, base_hips_t[2])
        hips_q = qeuler_xyz(p.get("hips_pitch", 0.0), p.get("hips_yaw", 0.0), p.get("hips_roll", 0.0))
        lr[hips_idx] = self.delta_local("Hips", hips_q)

        # 2. Spine + Chest lean/twist/tilt (split 45% Spine / 55% Chest for smooth curve)
        lean = p.get("lean", 6.0)
        twist = p.get("twist", 0.0)
        tilt = p.get("tilt", 0.0)
        lr[self.idx("Spine")] = self.delta_local("Spine", qeuler_xyz(lean * 0.45, twist * 0.45, tilt * 0.45))
        lr[self.idx("Chest")] = self.delta_local("Chest", qeuler_xyz(lean * 0.55, twist * 0.55, tilt * 0.55))

        # 3. Head eye-lock toward opponent (+Z)
        wp, wr = self.fk(lr, lt)
        if p.get("head_lock", True):
            # Counter-rotate Neck + Head gently so fighter looks at opponent
            chest_delta = qmul(wr[self.idx("Chest")], qinv(self.wr("Chest")))
            # Extract approximate inverse yaw/pitch (70% counter-rotation looks natural)
            inv_c = qslerp((0, 0, 0, 1), qinv(chest_delta), 0.72)
            neck_q = qslerp((0, 0, 0, 1), inv_c, 0.45)
            head_q = qslerp((0, 0, 0, 1), inv_c, 0.55)
            # Optional extra head pitch/yaw
            hp, hy = p.get("head_pitch", 0.0), p.get("head_yaw", 0.0)
            if hp or hy:
                head_q = qmul(qeuler_xyz(hp, hy, 0.0), head_q)
            lr[self.idx("Neck")] = self.delta_local("Neck", neck_q)
            lr[self.idx("Head")] = self.delta_local("Head", head_q)

        # 4. Cape / Coat inertia trail
        cp = p.get("cape_pitch", 12.0)
        if "Cape" in self.by_name:
            lr[self.idx("Cape")] = self.delta_local("Cape", qeuler_xyz(cp, -twist * 0.25, 0.0))
        if "CapeTip" in self.by_name:
            lr[self.idx("CapeTip")] = self.delta_local("CapeTip", qeuler_xyz(cp * 0.6, -twist * 0.15, 0.0))
        if "Coat" in self.by_name:
            lr[self.idx("Coat")] = self.delta_local("Coat", qeuler_xyz(max(0.0, cp * 0.5), 0.0, 0.0))

        # 5. Legs (analytical 2-bone sagittal IK so stance width & kicks are EXACT!)
        stance = p.get("stance", 0.80)
        wf = p.get("wf", 0.50)
        front_leg = p.get("front_leg", "L")
        kick_leg = p.get("kick_leg", None)
        kick_target = p.get("kick_target", None)  # (z_rel_to_hips, y_abs)

        wp, wr = self.fk(lr, lt)
        hips_pos = wp[hips_idx]
        hips_delta_q = qmul(wr[hips_idx], qinv(self.wr("Hips")))
        # Unwind pelvis yaw slightly on thighs so feet stay pointed toward combat line
        inv_hips_q = qinv(hips_delta_q)

        l1, l2 = self.len_thigh, self.len_shin
        foot_ground_y = max(0.06, self.rest_foot_y)

        for side in ("L", "R"):
            th_name, sh_name, ft_name = f"Thigh.{side}", f"Shin.{side}", f"Foot.{side}"
            if p.get("airborne_legs", False):
                # Graceful soaring Form of Light hover pose: lead knee softly bent, rear leg swept back!
                is_front = (side == front_leg)
                th_pitch = -28.0 if is_front else 18.0
                sh_pitch = 48.0 if is_front else 32.0
                ft_pitch = 22.0
                th_world_delta = qmul(qeuler_xyz(th_pitch, 8.0 if side == "L" else -8.0, 0.0), inv_hips_q)
                lr[self.idx(th_name)] = self.delta_local(th_name, th_world_delta)
                lr[self.idx(sh_name)] = self.delta_local(sh_name, qeuler_xyz(sh_pitch, 0.0, 0.0))
                lr[self.idx(ft_name)] = self.delta_local(ft_name, qeuler_xyz(ft_pitch, 0.0, 0.0))
                continue
            th_pos = wp[self.idx(th_name)]
            if kick_leg == side and kick_target is not None:
                tz = hips_pos[2] + kick_target[0]
                ty = kick_target[1]
                is_kicking = True
            else:
                z_off = stance * (1.0 - wf) if side == front_leg else -stance * wf
                tz = hips_pos[2] + z_off
                ty = foot_ground_y
                is_kicking = False

            dz = tz - th_pos[2]
            dy_leg = ty - th_pos[1]
            dist = math.hypot(dz, dy_leg)
            max_reach = (l1 + l2) * 0.992
            min_reach = abs(l1 - l2) + 0.08
            dist_c = max(min_reach, min(max_reach, dist))

            alpha = math.atan2(dz, -dy_leg)
            cos_hip = max(-1.0, min(1.0, (l1 * l1 + dist_c * dist_c - l2 * l2) / (2.0 * l1 * dist_c)))
            beta = math.acos(cos_hip)
            cos_knee = max(-1.0, min(1.0, (l1 * l1 + l2 * l2 - dist_c * dist_c) / (2.0 * l1 * l2)))
            knee_flex_deg = math.degrees(math.pi - math.acos(cos_knee))
            thigh_fwd_deg = math.degrees(alpha + beta)

            th_pitch = -thigh_fwd_deg
            sh_pitch = knee_flex_deg
            if is_kicking:
                ft_pitch = -18.0 if kick_target[0] >= 0 else 15.0
            else:
                ft_pitch = -(th_pitch + sh_pitch)
                ft_pitch = max(-35.0, min(40.0, ft_pitch))

            foot_yaw = (14.0 if side == "L" else -14.0) if not is_kicking else 0.0
            if side == kick_leg and p.get("kick_yaw"):
                foot_yaw = p["kick_yaw"]

            th_world_delta = qmul(qeuler_xyz(th_pitch, foot_yaw, 0.0), inv_hips_q)
            lr[self.idx(th_name)] = self.delta_local(th_name, th_world_delta)
            lr[self.idx(sh_name)] = self.delta_local(sh_name, qeuler_xyz(sh_pitch, 0.0, 0.0))
            lr[self.idx(ft_name)] = self.delta_local(ft_name, qeuler_xyz(ft_pitch, 0.0, 0.0))

        # 6. Right Arm (canonical anatomical angles) + 100% Hand-Locked Weapon Aiming!
        r_sh = p.get("r_shoulder", (0.0, 0.0, 0.0))
        r_arm = p.get("r_arm", (-36.0, 0.0, 0.0))
        r_elb = p.get("r_elbow", (-36.0, 0.0, 0.0))
        lr[self.idx("Shoulder.R")] = self.delta_local("Shoulder.R", qeuler_xyz(*r_sh))
        lr[self.idx("UpperArm.R")] = self.delta_local("UpperArm.R", qmul(qeuler_xyz(*r_arm), self.q_ua_r_zero))
        lr[self.idx("Forearm.R")] = self.delta_local("Forearm.R", qmul(qeuler_xyz(*r_elb), self.q_fa_r_zero))

        wp, wr = self.fk(lr, lt)

        # Rotate Hand.R (keeping weapon_socket_r at pure rest identity inside Hand.R!)
        # so the sculpted gripping fingers stay 100.0% locked around the weapon hilt in every frame!
        if "blade_angle" in p and "weapon_socket_r" in self.by_name:
            sock_idx = self.idx("weapon_socket_r")
            h_idx = self.idx("Hand.R")
            hp_idx = self.parent[h_idx]
            cur_swr = wr[sock_idx]
            cur_dir = qrot(cur_swr, (0.0, 1.0, 0.0))
            cur_ang = math.degrees(math.atan2(cur_dir[1], cur_dir[2]))
            tgt_ang = p["blade_angle"]
            ang_diff = ((tgt_ang - cur_ang + 180.0) % 360.0) - 180.0
            max_w = p.get("blade_max_wrist", 88.0)
            clamped_diff = max(-max_w, min(max_w, ang_diff))
            byaw = p.get("blade_yaw", 0.0)
            broll = p.get("blade_roll", 0.0)
            wrist_world_q = qmul(qeuler_xyz(0.0, byaw, broll), qaxis((1.0, 0.0, 0.0), -clamped_diff))
            lr[h_idx] = self.abs_local("Hand.R", wr[hp_idx], qnorm(qmul(wrist_world_q, wr[h_idx])))
            lr[sock_idx] = self.rest_r[sock_idx]

        wp, wr = self.fk(lr, lt)

        # 7. Left Arm: either 2-bone IK gripping two-handed weapon haft, OR manual pose (+ left blade for sunDeng)
        if p.get("two_handed", False) and "weapon_socket_r" in self.by_name:
            sock_idx = self.idx("weapon_socket_r")
            sock_wp = wp[sock_idx]
            sock_wr = wr[sock_idx]
            grip_w = vadd(sock_wp, qrot(sock_wr, self.rw_pos))
            bdir = vnorm(qrot(sock_wr, (0.0, 1.0, 0.0)))
            haft_off = p.get("haft_offset", -0.14)
            tgt_l = vadd(grip_w, vscale(bdir, haft_off))
            self._solve_left_arm_ik(lr, lt, wp, wr, tgt_l, bdir)
        else:
            l_sh = p.get("l_shoulder", (0.0, 0.0, 0.0))
            l_arm = p.get("l_arm", (-28.0, 0.0, 0.0))
            l_elb = p.get("l_elbow", (-36.0, 0.0, 0.0))
            lr[self.idx("Shoulder.L")] = self.delta_local("Shoulder.L", qeuler_xyz(*l_sh))
            lr[self.idx("UpperArm.L")] = self.delta_local("UpperArm.L", qmul(qeuler_xyz(*l_arm), self.q_ua_l_zero))
            lr[self.idx("Forearm.L")] = self.delta_local("Forearm.L", qmul(qeuler_xyz(*l_elb), self.q_fa_l_zero))
            if "blade_l_angle" in p and "weapon_socket_l" in self.by_name:
                wp, wr = self.fk(lr, lt)
                sli = self.idx("weapon_socket_l")
                hl_i = self.idx("Hand.L")
                hl_p = self.parent[hl_i]
                cur_dir = qrot(wr[sli], (0.0, 1.0, 0.0))
                cur_ang = math.degrees(math.atan2(cur_dir[1], cur_dir[2]))
                diff = ((p["blade_l_angle"] - cur_ang + 180.0) % 360.0) - 180.0
                diff = max(-88.0, min(88.0, diff))
                lyaw = p.get("blade_l_yaw", 0.0)
                wq = qmul(qeuler_xyz(0.0, lyaw, 0.0), qaxis((1.0, 0.0, 0.0), -diff))
                lr[hl_i] = self.abs_local("Hand.L", wr[hl_p], qnorm(qmul(wq, wr[hl_i])))
                lr[sli] = self.rest_r[sli]

        return lr, lt

    def _solve_left_arm_ik(self, lr, lt, wp, wr, target_pos, blade_dir=None):
        """Analytical 2-bone 3D IK for Shoulder.L + UpperArm.L + Forearm.L + Hand.L to wrap weapon haft."""
        lr[self.idx("Shoulder.L")] = self.delta_local("Shoulder.L", qeuler_xyz(0.0, -20.0, 0.0))
        wp, wr = self.fk(lr, lt)

        ua_i = self.idx("UpperArm.L")
        fa_i = self.idx("Forearm.L")
        hd_i = self.idx("Hand.L")

        sh_pos = wp[ua_i]
        l1 = self.len_uarm_l
        l2 = self.len_farm_l + 0.045
        to_t = vsub(target_pos, sh_pos)
        d = vlen(to_t)
        if d < 1e-4:
            return
        d_c = max(abs(l1 - l2) + 0.05, min((l1 + l2) * 0.985, d))
        dir_t = vnorm(to_t)

        pole = vnorm((0.55, -0.78, -0.22))
        side = vcross(dir_t, pole)
        if vlen(side) < 1e-4:
            side = vcross(dir_t, (0.0, -1.0, 0.0))
        side = vnorm(side)
        bend_dir = vnorm(vcross(side, dir_t))

        cos_a = max(-1.0, min(1.0, (l1 * l1 + d_c * d_c - l2 * l2) / (2.0 * l1 * d_c)))
        sin_a = math.sqrt(max(0.0, 1.0 - cos_a * cos_a))
        elbow_pos = vadd(sh_pos, vadd(vscale(dir_t, l1 * cos_a), vscale(bend_dir, l1 * sin_a)))

        cur_ua_vec = vnorm(vsub(wp[fa_i], wp[ua_i]))
        des_ua_vec = vnorm(vsub(elbow_pos, sh_pos))
        q_ua_delta = qfrom_to(cur_ua_vec, des_ua_vec)
        ua_parent = self.parent[ua_i]
        lr[ua_i] = self.abs_local("UpperArm.L", wr[ua_parent], qnorm(qmul(q_ua_delta, wr[ua_i])))

        wp, wr = self.fk(lr, lt)
        cur_fa_vec = vnorm(vsub(wp[hd_i], wp[fa_i]))
        des_fa_vec = vnorm(vsub(target_pos, wp[fa_i]))
        q_fa_delta = qfrom_to(cur_fa_vec, des_fa_vec)
        lr[fa_i] = self.abs_local("Forearm.L", wr[ua_i], qnorm(qmul(q_fa_delta, wr[fa_i])))

        if blade_dir is not None:
            wp, wr = self.fk(lr, lt)
            # Gently align left gripping palm to wrap cleanly along the weapon shaft axis
            cur_h_axis = qrot(wr[hd_i], (0.0, 0.0, 1.0))
            q_h = qslerp((0, 0, 0, 1), qfrom_to(cur_h_axis, blade_dir), 0.72)
            lr[hd_i] = self.abs_local("Hand.L", wr[fa_i], qnorm(qmul(q_h, wr[hd_i])))

    # ---- Sample a sequence of keyframe poses at 60 fps and write/replace a GLB animation clip
    def write_clip(self, clip_name, num_frames, fps, keyframes):
        """keyframes: list of (frac_0_to_1, pose_dict, ease_in_mode_from_prev).
        Evaluates smooth slerp/lerp between built poses at every frame, canonicalizes
        quaternions (0 flips), and writes/replaces `clip_name` with LINEAR interpolation."""
        built = [(frac, self.build_pose(pd), ease) for frac, pd, ease in keyframes]
        dt = 1.0 / fps
        times = [(k * dt,) for k in range(num_frames)]
        rot_tracks = {j: [] for j in self.joints}
        pos_tracks = {j: [] for j in self.joints}

        for k in range(num_frames):
            u = k / max(1, num_frames - 1)
            # Find segment [i, i+1]
            seg = 0
            while seg < len(built) - 2 and u > built[seg + 1][0]:
                seg += 1
            f0, (r0, t0), _ = built[seg]
            f1, (r1, t1), mode = built[seg + 1]
            span = max(1e-6, f1 - f0)
            s = ease_cubic((u - f0) / span, mode)
            for j in self.joints:
                q = qslerp(r0[j], r1[j], s)
                if rot_tracks[j] and sum(a * b for a, b in zip(q, rot_tracks[j][-1])) < 0:
                    q = (-q[0], -q[1], -q[2], -q[3])
                rot_tracks[j].append(q)
                p0, p1 = t0[j], t1[j]
                pos_tracks[j].append((p0[0] + (p1[0] - p0[0]) * s,
                                      p0[1] + (p1[1] - p0[1]) * s,
                                      p0[2] + (p1[2] - p0[2]) * s))

        # Share ONE time accessor across all channels in this clip (compact!)
        t_acc = self.append_acc(times, "SCALAR", with_bounds=True)
        samplers = []
        channels = []
        for j in self.joints:
            # Rotation channel (every joint)
            r_acc = self.append_acc(rot_tracks[j], "VEC4", with_bounds=False)
            samplers.append({"input": t_acc, "interpolation": "LINEAR", "output": r_acc})
            channels.append({"sampler": len(samplers) - 1, "target": {"node": j, "path": "rotation"}})
            # Translation channel (only Hips/Root or joints whose translation changes)
            if j in (self.idx("Hips"), self.idx("Root")):
                p_acc = self.append_acc(pos_tracks[j], "VEC3", with_bounds=False)
                samplers.append({"input": t_acc, "interpolation": "LINEAR", "output": p_acc})
                channels.append({"sampler": len(samplers) - 1, "target": {"node": j, "path": "translation"}})

        new_anim = {"name": clip_name, "channels": channels, "samplers": samplers}
        anims = self.json.setdefault("animations", [])
        # Replace ALL existing clips matching exact clip_name (or Blender .001 duplicates), without touching e.g. hit_head when replacing hit!
        base_prefix = clip_name.replace("_" + HERO_RIG_SUFFIX[self.hero_key], "")
        matches = [
            idx for idx, an in enumerate(anims)
            if an["name"] == clip_name or an["name"] == base_prefix or an["name"].startswith(clip_name + ".")
        ]
        if matches:
            anims[matches[0]] = new_anim
            for dup_idx in reversed(matches[1:]):
                anims.pop(dup_idx)
        else:
            anims.append(new_anim)

    # ---- Hygiene pass on preserved clips (hit, hit_head, hit_low, knockdown, getup, jump, walk, backstep, guard)
    def clean_existing_clips(self, skip_prefixes, idle_pose_r):
        hips_idx = self.idx("Hips")
        root_idx = self.idx("Root")
        for an in self.json.get("animations", []):
            nm = an["name"]
            if any(nm == p or nm.startswith(p + "_") for p in skip_prefixes):
                continue
            is_kd_or_gu = nm.startswith("knockdown") or nm.startswith("getup")
            is_blend_to_idle = any(nm.startswith(p) for p in ("jump", "hit_head", "hit_low"))
            for ch in an["channels"]:
                s = an["samplers"][ch["sampler"]]
                node_i = ch["target"]["node"]
                path = ch["target"]["path"]
                # 1. Always LINEAR (eliminates all STEP snapping!)
                if s.get("interpolation") == "STEP":
                    s["interpolation"] = "LINEAR"
                if path == "rotation":
                    vals = [qnorm(v) for v in self.read_acc(s["output"])]
                    if len(vals) >= 2:
                        # Blend last 5 keys gently toward new idle pose on jump / hit_head / hit_low
                        if is_blend_to_idle and node_i in idle_pose_r and len(vals) >= 8:
                            tgt = idle_pose_r[node_i]
                            tail_n = min(5, len(vals) // 3)
                            for k in range(tail_n):
                                idx = len(vals) - tail_n + k
                                alpha = (k + 1) / float(tail_n)
                                vals[idx] = qslerp(vals[idx], tgt, alpha)
                        # Canonicalize quaternion sign continuity (zero flips!)
                        fixed = [vals[0]]
                        for v in vals[1:]:
                            if sum(a * b for a, b in zip(v, fixed[-1])) < 0:
                                v = (-v[0], -v[1], -v[2], -v[3])
                            fixed.append(v)
                        s["output"] = self.append_acc(fixed, "VEC4", with_bounds=False)
                elif path == "translation" and is_kd_or_gu and node_i in (hips_idx, root_idx):
                    # Strip horizontal (X, Z) drift from knockdown/getup while keeping vertical Y fall!
                    vals = self.read_acc(s["output"])
                    if len(vals) >= 2:
                        r0 = self.rest_t[node_i]
                        fixed = [(r0[0], v[1], r0[2]) for v in vals]
                        s["output"] = self.append_acc(fixed, "VEC3", with_bounds=False)

    def _compact(self):
        """Remove unreferenced accessors & bufferViews so GLB stays compact across re-runs."""
        used_acc = set()
        for m in self.json.get("meshes", []):
            for pr in m.get("primitives", []):
                used_acc.update(pr.get("attributes", {}).values())
                if "indices" in pr:
                    used_acc.add(pr["indices"])
                for tgt in pr.get("targets", []):
                    used_acc.update(tgt.values())
        for sk in self.json.get("skins", []):
            if "inverseBindMatrices" in sk:
                used_acc.add(sk["inverseBindMatrices"])
        for an in self.json.get("animations", []):
            for s in an.get("samplers", []):
                used_acc.add(s["input"])
                used_acc.add(s["output"])

        old_accs = self.json.get("accessors", [])
        acc_remap = {}
        new_accs = []
        for i in sorted(used_acc):
            acc_remap[i] = len(new_accs)
            new_accs.append(old_accs[i])
        for m in self.json.get("meshes", []):
            for pr in m.get("primitives", []):
                pr["attributes"] = {k: acc_remap[v] for k, v in pr.get("attributes", {}).items()}
                if "indices" in pr:
                    pr["indices"] = acc_remap[pr["indices"]]
                for tgt in pr.get("targets", []):
                    for k in list(tgt.keys()):
                        tgt[k] = acc_remap[tgt[k]]
        for sk in self.json.get("skins", []):
            if "inverseBindMatrices" in sk:
                sk["inverseBindMatrices"] = acc_remap[sk["inverseBindMatrices"]]
        for an in self.json.get("animations", []):
            for s in an.get("samplers", []):
                s["input"] = acc_remap[s["input"]]
                s["output"] = acc_remap[s["output"]]
        self.json["accessors"] = new_accs

        used_bv = set()
        for a in new_accs:
            if "bufferView" in a:
                used_bv.add(a["bufferView"])
        for im in self.json.get("images", []):
            if "bufferView" in im:
                used_bv.add(im["bufferView"])

        old_bvs = self.json.get("bufferViews", [])
        bv_remap = {}
        new_bvs = []
        new_bin = bytearray()
        for i in sorted(used_bv):
            bv = dict(old_bvs[i])
            src_off = bv.get("byteOffset", 0)
            src_len = bv["byteLength"]
            while len(new_bin) % 4:
                new_bin.append(0)
            bv["byteOffset"] = len(new_bin)
            new_bin += self.bin[src_off:src_off + src_len]
            bv_remap[i] = len(new_bvs)
            new_bvs.append(bv)
        for a in new_accs:
            if "bufferView" in a:
                a["bufferView"] = bv_remap[a["bufferView"]]
        for im in self.json.get("images", []):
            if "bufferView" in im:
                im["bufferView"] = bv_remap[im["bufferView"]]
        self.json["bufferViews"] = new_bvs
        self.bin = new_bin

    def save(self):
        self._compact()
        while len(self.bin) % 4:
            self.bin.append(0)
        self.json["buffers"][0]["byteLength"] = len(self.bin)
        js = json.dumps(self.json, separators=(",", ":")).encode()
        js += b" " * ((4 - len(js) % 4) % 4)
        total = 12 + 8 + len(js) + 8 + len(self.bin)
        out = struct.pack("<III", 0x46546C67, 2, total)
        out += struct.pack("<II", len(js), 0x4E4F534A) + js
        out += struct.pack("<II", len(self.bin), 0x004E4942) + bytes(self.bin)
        self.path.write_bytes(out)


# ------------------------------------------------------------------ Hero choreography specs
def hero_stance(hk):
    """Distinct, natural, athletic Shadow Fight 4 combat idle stances (hands centered in natural martial guard)."""
    if hk == "wuYong":  # Shogun: centered chudan-no-kamae samurai sword guard (odachi angled cleanly in front of chest)
        return dict(hip_h=0.89, lean=6, twist=-14, stance=0.78, wf=0.50, front_leg="L",
                    r_arm=(-48, 30, -10), r_elbow=(-54, 0, 0), blade_angle=34, blade_yaw=12,
                    two_handed=True, haft_offset=-0.13, cape_pitch=10)
    if hk == "xuXiao":  # Grand Inquisitor: poised commanding Templar greatsword guard centered across torso
        return dict(hip_h=0.92, lean=4, twist=-12, stance=0.74, wf=0.48, front_leg="L",
                    r_arm=(-46, 28, -10), r_elbow=(-52, 0, 0), blade_angle=44, blade_yaw=14,
                    two_handed=True, haft_offset=-0.12, cape_pitch=8)
    if hk == "liuQuanwei":  # Nonna: wide heavy Norse berserker great-axe stance (centered diagonal heavy grip)
        return dict(hip_h=0.87, lean=8, twist=-18, stance=0.84, wf=0.50, front_leg="L",
                    r_arm=(-40, 26, -12), r_elbow=(-48, 0, 0), blade_angle=48, blade_yaw=14,
                    two_handed=True, haft_offset=-0.13, cape_pitch=12)
    # sunDeng: Midnight — upright-agile dual-ninjato assassin stance (hip_h=0.86, poised twin blades!)
    return dict(hip_h=0.86, lean=12, twist=-16, stance=0.82, wf=0.52, front_leg="L",
                r_arm=(-44, 18, -14), r_elbow=(-56, 0, 0), blade_angle=16, blade_yaw=18,
                two_handed=False,
                l_arm=(-54, -18, 14), l_elbow=(-58, 0, 0), blade_l_angle=48, blade_l_yaw=-20,
                cape_pitch=14)


def merge(base, **kw):
    d = dict(base)
    d.update(kw)
    return d


def build_hero_clips(hk):
    """Author fluid, varied Shadow Fight 4 martial arts choreography — horizontal cuts, backhand rising
    slashes, lunging thrusts, continuous 2/3-hit combo strings, spinning hooks, soaring Form of Light
    aerial attacks, dashes, and violent frame-1 snap-back hit recoil."""
    st = hero_stance(hk)
    is_dual = (hk == "sunDeng")
    two_h = not is_dual
    h_off = -0.13 if hk != "xuXiao" else -0.12

    clips = {}

    # 1. Idle (90f = 1.5s loop): living martial breathing, shoulder micro-shift & blade poise
    clips["idle"] = (90, lambda *_: [
        (0.00, st, "inout"),
        (0.50, merge(st, hip_h=st["hip_h"] - 0.022, lean=st["lean"] + 2.5, twist=st["twist"] - 3,
                     blade_angle=st["blade_angle"] - 5.0, cape_pitch=st["cape_pitch"] + 5), "inout"),
        (1.00, st, "inout"),
    ])

    # 2. Guard (30f): crisp slanted cross-body blade parry (angled across torso & head)
    if is_dual:
        gd = merge(st, hip_h=0.84, lean=8, twist=-20, stance=0.84, wf=0.42,
                   r_arm=(-76, 28, -14), r_elbow=(-66, 0, 0), blade_angle=68, blade_yaw=34,
                   l_arm=(-80, -30, 14), l_elbow=(-64, 0, 0), blade_l_angle=98, blade_l_yaw=-34)
    else:
        gd = merge(st, hip_h=st["hip_h"] - 0.02, lean=2, twist=-24, stance=st["stance"] + 0.06, wf=0.40,
                   r_arm=(-72, 34, -14), r_elbow=(-64, 0, 0), blade_angle=74, blade_yaw=38,
                   two_handed=True, haft_offset=h_off)
    clips["guard"] = (30, lambda *_: [
        (0.00, gd, "inout"),
        (0.50, merge(gd, hip_h=gd["hip_h"] - 0.015, blade_angle=gd["blade_angle"] + 3), "inout"),
        (1.00, gd, "inout"),
    ])

    # 3. Walk & Backstep (44f seamless athletic martial stride)
    clips["walk"] = (44, lambda *_: [
        (0.00, merge(st, stance=st["stance"] + 0.08, wf=0.55, hip_h=st["hip_h"] - 0.01, lean=st["lean"] + 4), "inout"),
        (0.25, merge(st, stance=st["stance"] - 0.24, wf=0.48, hip_h=st["hip_h"] + 0.02, lean=st["lean"] + 5, twist=st["twist"] + 8), "inout"),
        (0.50, merge(st, stance=st["stance"] + 0.10, wf=0.45, front_leg="R", hip_h=st["hip_h"] - 0.01, lean=st["lean"] + 4, twist=st["twist"] + 12), "inout"),
        (0.75, merge(st, stance=st["stance"] - 0.24, wf=0.52, hip_h=st["hip_h"] + 0.02, lean=st["lean"] + 5, twist=st["twist"] + 4), "inout"),
        (1.00, merge(st, stance=st["stance"] + 0.08, wf=0.55, hip_h=st["hip_h"] - 0.01, lean=st["lean"] + 4), "inout"),
    ])
    clips["backstep"] = (44, lambda *_: [
        (0.00, merge(st, stance=st["stance"] + 0.06, wf=0.40, hip_h=st["hip_h"] - 0.01, lean=st["lean"] - 3), "inout"),
        (0.25, merge(st, stance=st["stance"] - 0.20, wf=0.46, hip_h=st["hip_h"] + 0.02, lean=st["lean"] - 4), "inout"),
        (0.50, merge(st, stance=st["stance"] + 0.08, wf=0.38, front_leg="R", hip_h=st["hip_h"] - 0.01, lean=st["lean"] - 3), "inout"),
        (0.75, merge(st, stance=st["stance"] - 0.20, wf=0.44, hip_h=st["hip_h"] + 0.02, lean=st["lean"] - 4), "inout"),
        (1.00, merge(st, stance=st["stance"] + 0.06, wf=0.40, hip_h=st["hip_h"] - 0.01, lean=st["lean"] - 3), "inout"),
    ])

    # 3b. NEW SF4 Double-Tap Dash Forward & Agile Back-Hop (14f = 0.23s)
    clips["dash_forward"] = (14, lambda *_: [
        (0.00, merge(st, hip_h=st["hip_h"] - 0.08, lean=22, stance=st["stance"] + 0.14, wf=0.68), "inout"),
        (0.35, merge(st, hip_h=st["hip_h"] - 0.12, lean=28, twist=-14, stance=1.08, wf=0.74,
                     r_arm=(-24, -22, -16), r_elbow=(-62, 0, 0), blade_angle=165, blade_yaw=-18,
                     two_handed=False, l_arm=(-64, 18, 14), l_elbow=(-68, 0, 0), cape_pitch=42), "whip"),
        (0.72, merge(st, hip_h=st["hip_h"] - 0.06, lean=16, stance=0.96, wf=0.62, cape_pitch=28), "out"),
        (1.00, st, "inout"),
    ])
    clips["dash_back"] = (14, lambda *_: [
        (0.00, merge(st, hip_h=st["hip_h"] - 0.06, lean=-6, stance=st["stance"] + 0.08, wf=0.32), "inout"),
        (0.35, merge(st, hip_h=st["hip_h"] + 0.04, lean=-14, twist=-22, stance=0.62, wf=0.28,
                     kick_leg="L", kick_target=(0.24, 0.34),
                     r_arm=(-64, 24, -12), r_elbow=(-62, 0, 0), blade_angle=74, blade_yaw=26,
                     two_handed=two_h, haft_offset=h_off, cape_pitch=-16), "whip"),
        (0.74, merge(st, hip_h=st["hip_h"] - 0.03, lean=-4, stance=0.88, wf=0.38, cape_pitch=6), "out"),
        (1.00, st, "inout"),
    ])

    # 4. JAB (`light1`): CRISP HORIZONTAL DRAW-SLASH / QUICK DIAGONAL CUT (NOT an overhead chop!)
    if hk == "wuYong":  # Shogun: lightning horizontal chest-level katana draw-cut right-to-left!
        clips["light1"] = ("jab", lambda su, ac: [
            (0.00, st, "inout"),
            (su, merge(st, hip_h=0.86, lean=4, twist=-48, stance=0.76, wf=0.38,
                       r_arm=(-68, -42, -24), r_elbow=(-56, 0, 0), blade_angle=18, blade_yaw=-52, blade_roll=18,
                       two_handed=True, haft_offset=h_off, cape_pitch=6), "out"),
            (ac, merge(st, hip_h=0.84, lean=12, twist=38, stance=0.92, wf=0.64,
                       r_arm=(-82, 42, -10), r_elbow=(-20, 0, 0), blade_angle=6, blade_yaw=50, blade_roll=-14,
                       two_handed=True, haft_offset=h_off, cape_pitch=28), "whip"),
            (min(0.84, ac + 0.24), merge(st, hip_h=0.86, lean=8, twist=42, stance=0.86, wf=0.58,
                       r_arm=(-68, 48, -10), r_elbow=(-32, 0, 0), blade_angle=-8, blade_yaw=56,
                       two_handed=True, haft_offset=h_off, cape_pitch=20), "out"),
            (1.00, st, "inout"),
        ])
    elif hk == "xuXiao":  # Grand Inquisitor: crisp horizontal diagonal temple sweep (shoulder-to-hip)
        clips["light1"] = ("jab", lambda su, ac: [
            (0.00, st, "inout"),
            (su, merge(st, hip_h=0.91, lean=2, twist=-44, stance=0.74, wf=0.40,
                       r_arm=(-82, -38, -20), r_elbow=(-48, 0, 0), blade_angle=44, blade_yaw=-44, blade_roll=22,
                       two_handed=True, haft_offset=h_off, cape_pitch=6), "out"),
            (ac, merge(st, hip_h=0.87, lean=11, twist=34, stance=0.88, wf=0.62,
                       r_arm=(-76, 36, -8), r_elbow=(-18, 0, 0), blade_angle=-6, blade_yaw=42, blade_roll=-18,
                       two_handed=True, haft_offset=h_off, cape_pitch=26), "whip"),
            (min(0.84, ac + 0.24), merge(st, hip_h=0.89, lean=8, twist=38, stance=0.82, wf=0.56,
                       r_arm=(-54, 40, -8), r_elbow=(-28, 0, 0), blade_angle=-24, blade_yaw=46,
                       two_handed=True, haft_offset=h_off, cape_pitch=18), "out"),
            (1.00, st, "inout"),
        ])
    elif hk == "liuQuanwei":  # Nonna: wide horizontal torso-twisting berserker side-hack
        clips["light1"] = ("jab", lambda su, ac: [
            (0.00, st, "inout"),
            (su, merge(st, hip_h=0.86, lean=4, twist=-56, stance=0.88, wf=0.35,
                       r_arm=(-74, -46, -26), r_elbow=(-44, 0, 0), blade_angle=16, blade_yaw=-58, blade_roll=20,
                       two_handed=True, haft_offset=h_off, cape_pitch=6), "out"),
            (ac, merge(st, hip_h=0.82, lean=14, twist=46, stance=0.98, wf=0.66,
                       r_arm=(-82, 46, -10), r_elbow=(-18, 0, 0), blade_angle=2, blade_yaw=54, blade_roll=-16,
                       two_handed=True, haft_offset=h_off, cape_pitch=30), "whip"),
            (min(0.84, ac + 0.24), merge(st, hip_h=0.84, lean=10, twist=48, stance=0.92, wf=0.58,
                       r_arm=(-60, 50, -8), r_elbow=(-26, 0, 0), blade_angle=-14, blade_yaw=58,
                       two_handed=True, haft_offset=h_off, cape_pitch=22), "out"),
            (1.00, st, "inout"),
        ])
    else:  # sunDeng: lightning horizontal twin-ninjato outward-to-inward scissor slash!
        clips["light1"] = ("jab", lambda su, ac: [
            (0.00, st, "inout"),
            (su, merge(st, hip_h=0.83, lean=14, twist=-38, stance=0.88, wf=0.44,
                       r_arm=(-76, -42, -24), r_elbow=(-50, 0, 0), blade_angle=24, blade_yaw=-48,
                       l_arm=(-66, 26, 22), l_elbow=(-54, 0, 0), blade_l_angle=64, blade_l_yaw=32,
                       cape_pitch=14), "out"),
            (ac, merge(st, hip_h=0.80, lean=20, twist=34, stance=1.00, wf=0.66,
                       r_arm=(-86, 40, -10), r_elbow=(-16, 0, 0), blade_angle=4, blade_yaw=46,
                       l_arm=(-74, -36, 12), l_elbow=(-22, 0, 0), blade_l_angle=-12, blade_l_yaw=-42,
                       cape_pitch=32), "whip"),
            (min(0.84, ac + 0.24), merge(st, hip_h=0.83, lean=16, twist=28, stance=0.92, wf=0.58,
                       r_arm=(-58, 44, -10), r_elbow=(-32, 0, 0), blade_angle=-22, blade_yaw=48,
                       l_arm=(-52, -34, 14), l_elbow=(-34, 0, 0), blade_l_angle=-42, blade_l_yaw=-38,
                       cape_pitch=24), "out"),
            (1.00, st, "inout"),
        ])

    # 5. CROSS (`light2`): REVERSE BACKHAND RISING RIPOSTE (sweeps smoothly low-left -> high-right!)
    if is_dual:
        clips["light2"] = ("cross", lambda su, ac: [
            (0.00, st, "inout"),
            (su, merge(st, hip_h=0.81, lean=18, twist=42, stance=0.92, wf=0.56,
                       r_arm=(-52, 46, -12), r_elbow=(-46, 0, 0), blade_angle=-28, blade_yaw=48,
                       l_arm=(-96, 32, 18), l_elbow=(-48, 0, 0), blade_l_angle=134, blade_l_yaw=34), "out"),
            (ac, merge(st, hip_h=0.84, lean=12, twist=-36, stance=1.02, wf=0.66,
                       r_arm=(-108, -34, -18), r_elbow=(-16, 0, 0), blade_angle=48, blade_yaw=-42,
                       l_arm=(-86, -34, 12), l_elbow=(-14, 0, 0), blade_l_angle=-6, blade_l_yaw=-38,
                       cape_pitch=34), "whip"),
            (min(0.84, ac + 0.24), merge(st, hip_h=0.86, lean=10, twist=-26, stance=0.92, wf=0.56,
                       r_arm=(-88, -32, -16), r_elbow=(-32, 0, 0), blade_angle=64, blade_yaw=-32,
                       l_arm=(-60, -24, 16), l_elbow=(-34, 0, 0), blade_l_angle=-36, blade_l_yaw=-26), "out"),
            (1.00, st, "inout"),
        ])
    else:
        clips["light2"] = ("cross", lambda su, ac: [
            (0.00, st, "inout"),
            (su, merge(st, hip_h=st["hip_h"] - 0.05, lean=12, twist=46, stance=st["stance"] + 0.06, wf=0.58,
                       r_arm=(-46, 48, -10), r_elbow=(-36, 0, 0), blade_angle=-28, blade_yaw=48, blade_roll=-20,
                       two_handed=True, haft_offset=h_off), "out"),
            (ac, merge(st, hip_h=st["hip_h"] + 0.01, lean=4, twist=-38, stance=st["stance"] + 0.14, wf=0.64,
                       r_arm=(-114, -36, -16), r_elbow=(-18, 0, 0), blade_angle=48, blade_yaw=-42, blade_roll=22,
                       two_handed=True, haft_offset=h_off, cape_pitch=28), "whip"),
            (min(0.84, ac + 0.24), merge(st, hip_h=st["hip_h"] + 0.02, lean=2, twist=-28, stance=st["stance"] + 0.08, wf=0.54,
                       r_arm=(-122, -28, -16), r_elbow=(-34, 0, 0), blade_angle=74, blade_yaw=-28,
                       two_handed=True, haft_offset=h_off), "out"),
            (1.00, st, "inout"),
        ])

    # 6. HEAVY (`heavy`): 4 COMPLETELY DIFFERENT HERO SIGNATURE EXECUTIONS!
    if hk == "wuYong":  # Shogun: DEEP IAIDO QUICK-DRAW HORIZONTAL LUNGE (hilt drawn low at hip -> blazing wide slash!)
        clips["heavy"] = ("heavy", lambda su, ac: [
            (0.00, st, "inout"),
            (su, merge(st, hip_h=0.75, lean=16, twist=-58, hips_yaw=-24, stance=0.96, wf=0.34,
                       r_arm=(-24, -48, -28), r_elbow=(-66, 0, 0), blade_angle=-26, blade_yaw=-66, blade_roll=24,
                       two_handed=True, haft_offset=h_off, cape_pitch=16), "out"),
            (ac, merge(st, hip_h=0.80, lean=18, twist=52, hips_yaw=28, stance=1.14, wf=0.74,
                       r_arm=(-88, 46, -8), r_elbow=(-12, 0, 0), blade_angle=4, blade_yaw=54, blade_roll=-18,
                       two_handed=True, haft_offset=h_off, cape_pitch=42), "whip"),
            (min(0.82, ac + 0.22), merge(st, hip_h=0.82, lean=14, twist=58, hips_yaw=24, stance=1.04, wf=0.64,
                       r_arm=(-64, 56, -8), r_elbow=(-24, 0, 0), blade_angle=-16, blade_yaw=64,
                       two_handed=True, haft_offset=h_off, cape_pitch=32), "out"),
            (1.00, st, "inout"),
        ])
    elif hk == "xuXiao":  # Grand Inquisitor: TOWERING CATHEDRAL TWO-HANDED OVERHEAD EXECUTION CLEAVE
        clips["heavy"] = ("heavy", lambda su, ac: [
            (0.00, st, "inout"),
            (su, merge(st, hip_h=0.94, lean=-10, twist=-22, stance=0.74, wf=0.30,
                       r_arm=(-158, -8, -8), r_elbow=(-28, 0, 0), blade_angle=152, blade_yaw=-8,
                       two_handed=True, haft_offset=h_off, cape_pitch=-8), "out"),
            (ac, merge(st, hip_h=0.82, lean=20, twist=22, stance=1.02, wf=0.72,
                       r_arm=(-74, 18, -6), r_elbow=(-12, 0, 0), blade_angle=-24, blade_yaw=10,
                       two_handed=True, haft_offset=h_off, cape_pitch=38), "whip"),
            (min(0.82, ac + 0.22), merge(st, hip_h=0.79, lean=22, twist=26, stance=0.98, wf=0.68,
                       r_arm=(-38, 22, -6), r_elbow=(-18, 0, 0), blade_angle=-52, blade_yaw=14,
                       two_handed=True, haft_offset=h_off, cape_pitch=30), "out"),
            (1.00, st, "inout"),
        ])
    elif hk == "liuQuanwei":  # Nonna: FULL-BODY NORSE BERSERKER OVERHEAD EARTH-BREAKER SMASH
        clips["heavy"] = ("heavy", lambda su, ac: [
            (0.00, st, "inout"),
            (su, merge(st, hip_h=0.90, lean=-14, twist=-62, hips_yaw=-26, stance=0.92, wf=0.25,
                       r_arm=(-148, -32, -20), r_elbow=(-32, 0, 0), blade_angle=146, blade_yaw=-28,
                       two_handed=True, haft_offset=h_off, cape_pitch=-6), "out"),
            (ac, merge(st, hip_h=0.78, lean=22, twist=46, hips_yaw=22, stance=1.10, wf=0.72,
                       r_arm=(-78, 34, -8), r_elbow=(-12, 0, 0), blade_angle=-12, blade_yaw=26,
                       two_handed=True, haft_offset=h_off, cape_pitch=40), "whip"),
            (min(0.82, ac + 0.22), merge(st, hip_h=0.76, lean=24, twist=50, hips_yaw=20, stance=1.04, wf=0.68,
                       r_arm=(-38, 38, -8), r_elbow=(-16, 0, 0), blade_angle=-48, blade_yaw=30,
                       two_handed=True, haft_offset=h_off, cape_pitch=32), "out"),
            (1.00, st, "inout"),
        ])
    else:  # sunDeng: CROSS-ARENA PREDATOR TWIN-BLADE PIERCING LUNGE THRUST!
        clips["heavy"] = ("heavy", lambda su, ac: [
            (0.00, st, "inout"),
            (su, merge(st, hip_h=0.76, lean=24, twist=-28, stance=0.98, wf=0.38,
                       r_arm=(22, -26, -24), r_elbow=(-56, 0, 0), blade_angle=176, blade_yaw=-16,
                       l_arm=(18, 26, 24), l_elbow=(-56, 0, 0), blade_l_angle=184, blade_l_yaw=16,
                       cape_pitch=24), "out"),
            (ac, merge(st, hip_h=0.72, lean=32, twist=18, stance=1.22, wf=0.76,
                       r_arm=(-92, 16, -8), r_elbow=(-10, 0, 0), blade_angle=0, blade_yaw=8,
                       l_arm=(-88, -16, 8), l_elbow=(-12, 0, 0), blade_l_angle=-4, blade_l_yaw=-8,
                       cape_pitch=46), "whip"),
            (min(0.82, ac + 0.22), merge(st, hip_h=0.76, lean=24, twist=16, stance=1.06, wf=0.64,
                       r_arm=(-74, 24, -10), r_elbow=(-28, 0, 0), blade_angle=-16, blade_yaw=22,
                       l_arm=(-68, -24, 10), l_elbow=(-28, 0, 0), blade_l_angle=-24, blade_l_yaw=-22,
                       cape_pitch=32), "out"),
            (1.00, st, "inout"),
        ])

    # 7. FINISHER (`finisher` — 3rd combo hit: DISTINCT per hero! Thrust / Spin-Cleave / Twin-X!)
    if hk == "xuXiao":  # Grand Inquisitor: FULL-BODY PIERCING CRUSADER GREATSWORD THRUST!
        clips["finisher"] = ("finisher", lambda su, ac: [
            (0.00, st, "inout"),
            (su, merge(st, hip_h=0.88, lean=4, twist=-48, hips_yaw=-18, stance=0.78, wf=0.32,
                       r_arm=(-44, -36, -16), r_elbow=(-72, 0, 0), blade_angle=8, blade_yaw=-10,
                       two_handed=True, haft_offset=h_off, cape_pitch=6), "out"),
            (ac, merge(st, hip_h=0.82, lean=20, twist=32, hips_yaw=16, stance=1.12, wf=0.76,
                       r_arm=(-92, 16, -4), r_elbow=(-8, 0, 0), blade_angle=0, blade_yaw=4,
                       two_handed=True, haft_offset=h_off, cape_pitch=40), "whip"),
            (min(0.82, ac + 0.22), merge(st, hip_h=0.86, lean=12, twist=20, stance=0.98, wf=0.64,
                       r_arm=(-72, 18, -8), r_elbow=(-28, 0, 0), blade_angle=-10, blade_yaw=10,
                       two_handed=True, haft_offset=h_off), "out"),
            (1.00, st, "inout"),
        ])
    elif hk == "liuQuanwei":  # Nonna: SPINNING WHIRLWIND HORIZONTAL GREAT-AXE CLEAVE!
        clips["finisher"] = ("finisher", lambda su, ac: [
            (0.00, st, "inout"),
            (su, merge(st, hip_h=0.82, lean=10, twist=-68, hips_yaw=-42, stance=0.94, wf=0.32,
                       r_arm=(-74, -52, -26), r_elbow=(-36, 0, 0), blade_angle=20, blade_yaw=-66, blade_roll=24,
                       two_handed=True, haft_offset=h_off, cape_pitch=10), "out"),
            (ac, merge(st, hip_h=0.80, lean=18, twist=60, hips_yaw=44, stance=1.08, wf=0.72,
                       r_arm=(-86, 54, -8), r_elbow=(-12, 0, 0), blade_angle=-4, blade_yaw=64, blade_roll=-20,
                       two_handed=True, haft_offset=h_off, cape_pitch=42), "whip"),
            (min(0.82, ac + 0.22), merge(st, hip_h=0.84, lean=12, twist=46, hips_yaw=28, stance=0.96, wf=0.60,
                       r_arm=(-52, 48, -10), r_elbow=(-28, 0, 0), blade_angle=-30, blade_yaw=54,
                       two_handed=True, haft_offset=h_off), "out"),
            (1.00, st, "inout"),
        ])
    else:  # Wu Yong spinning advancing diagonal execution / Sun Deng explosive X-cross slash
        clips["finisher"] = ("finisher", lambda su, ac: [
            (0.00, st, "inout"),
            (su, merge(st, hip_h=st["hip_h"] - 0.04, lean=-6, twist=-54, hips_yaw=-26, stance=st["stance"], wf=0.30,
                       r_arm=(-128, -34, -18), r_elbow=(-36, 0, 0), blade_angle=142, blade_yaw=-32,
                       two_handed=two_h, haft_offset=h_off,
                       l_arm=(-122, 30, 18), l_elbow=(-36, 0, 0), blade_l_angle=132, blade_l_yaw=28), "out"),
            (ac, merge(st, hip_h=st["hip_h"] - 0.08, lean=20, twist=50, hips_yaw=28, stance=st["stance"] + 0.24, wf=0.74,
                       r_arm=(-84, 42, -8), r_elbow=(-12, 0, 0), blade_angle=-12, blade_yaw=38,
                       two_handed=two_h, haft_offset=h_off,
                       l_arm=(-78, -38, 10), l_elbow=(-12, 0, 0), blade_l_angle=14, blade_l_yaw=-34,
                       cape_pitch=40), "whip"),
            (min(0.82, ac + 0.22), merge(st, hip_h=st["hip_h"] - 0.05, lean=16, twist=44, stance=st["stance"] + 0.16, wf=0.62,
                       r_arm=(-48, 44, -8), r_elbow=(-22, 0, 0), blade_angle=-38, blade_yaw=40,
                       two_handed=two_h, haft_offset=h_off,
                       l_arm=(-46, -38, 12), l_elbow=(-22, 0, 0), blade_l_angle=-58, blade_l_yaw=-34), "out"),
            (1.00, st, "inout"),
        ])

    # 8. WEAPON_FORWARD (`weaponForward`): TRUE MULTI-HIT 2-HIT / 3-HIT MARTIAL COMBO STRINGS!!
    if hk == "wuYong":  # Shogun 3-HIT ADVANCING ODACHI STRING: (1) Horizontal Slash -> (2) Backhand Rise -> (3) Straight Thrust!
        clips["weapon_forward"] = (42, lambda *_: [
            (0.00, st, "inout"),
            # Strike 1: fast horizontal right-to-left slash
            (0.14, merge(st, hip_h=0.86, lean=6, twist=-46, stance=0.80, wf=0.40,
                         r_arm=(-72, -38, -20), r_elbow=(-48, 0, 0), blade_angle=20, blade_yaw=-48,
                         two_handed=True, haft_offset=h_off), "out"),
            (0.24, merge(st, hip_h=0.84, lean=14, twist=40, stance=0.94, wf=0.64,
                         r_arm=(-82, 42, -8), r_elbow=(-16, 0, 0), blade_angle=6, blade_yaw=48,
                         two_handed=True, haft_offset=h_off, cape_pitch=28), "whip"),
            # Strike 2: snappy reverse backhand diagonal slash
            (0.40, merge(st, hip_h=0.85, lean=8, twist=-40, stance=1.00, wf=0.60,
                         r_arm=(-108, -32, -16), r_elbow=(-18, 0, 0), blade_angle=44, blade_yaw=-42,
                         two_handed=True, haft_offset=h_off, cape_pitch=34), "whip"),
            # Strike 3: deep lunging straight horizontal Odachi piercing thrust!
            (0.54, merge(st, hip_h=0.82, lean=10, twist=-26, stance=0.92, wf=0.44,
                         r_arm=(-46, -24, -14), r_elbow=(-68, 0, 0), blade_angle=2, blade_yaw=-6,
                         two_handed=True, haft_offset=h_off), "out"),
            (0.68, merge(st, hip_h=0.79, lean=22, twist=28, stance=1.16, wf=0.78,
                         r_arm=(-92, 14, -4), r_elbow=(-8, 0, 0), blade_angle=0, blade_yaw=4,
                         two_handed=True, haft_offset=h_off, cape_pitch=42), "whip"),
            (0.84, merge(st, hip_h=0.84, lean=12, twist=16, stance=0.98, wf=0.62), "out"),
            (1.00, st, "inout"),
        ])
    elif hk == "sunDeng":  # Midnight 3-HIT COLD-BLOODED ASSASSIN TWIN-BLADE X-FLURRY!
        clips["weapon_forward"] = (40, lambda *_: [
            (0.00, st, "inout"),
            # Hit 1: Right blade slash across
            (0.14, merge(st, hip_h=0.82, lean=16, twist=-42, stance=0.88, wf=0.45,
                         r_arm=(-76, -42, -22), r_elbow=(-46, 0, 0), blade_angle=24, blade_yaw=-46,
                         l_arm=(-46, 18, 18), l_elbow=(-60, 0, 0), blade_l_angle=68, blade_l_yaw=20), "out"),
            (0.24, merge(st, hip_h=0.80, lean=20, twist=38, stance=0.98, wf=0.64,
                         r_arm=(-86, 42, -8), r_elbow=(-14, 0, 0), blade_angle=4, blade_yaw=48,
                         l_arm=(-84, 34, 18), l_elbow=(-48, 0, 0), blade_l_angle=120, blade_l_yaw=34, cape_pitch=30), "whip"),
            # Hit 2: Left blade reverse slash across
            (0.44, merge(st, hip_h=0.78, lean=22, twist=-38, stance=1.06, wf=0.66,
                         r_arm=(-108, -30, -18), r_elbow=(-44, 0, 0), blade_angle=130, blade_yaw=-34,
                         l_arm=(-86, -42, 8), l_elbow=(-14, 0, 0), blade_l_angle=-8, blade_l_yaw=-48, cape_pitch=36), "whip"),
            # Hit 3: Twin-blade diving X-cross lunge!
            (0.68, merge(st, hip_h=0.74, lean=28, twist=20, stance=1.18, wf=0.76,
                         r_arm=(-84, 34, -8), r_elbow=(-12, 0, 0), blade_angle=-18, blade_yaw=34,
                         l_arm=(-84, -34, 8), l_elbow=(-12, 0, 0), blade_l_angle=16, blade_l_yaw=-34, cape_pitch=44), "whip"),
            (0.84, merge(st, hip_h=0.80, lean=18, twist=12, stance=0.98, wf=0.60), "out"),
            (1.00, st, "inout"),
        ])
    elif hk == "xuXiao":  # Grand Inquisitor 2-HIT HALBERD-STYLE THRUST + SWEEPING BACKHAND CLEAVE!
        clips["weapon_forward"] = (38, lambda *_: [
            (0.00, st, "inout"),
            (0.16, merge(st, hip_h=0.89, lean=6, twist=-40, stance=0.80, wf=0.38,
                         r_arm=(-44, -30, -14), r_elbow=(-66, 0, 0), blade_angle=4, blade_yaw=-10,
                         two_handed=True, haft_offset=h_off), "out"),
            # Hit 1: Straight piercing thrust
            (0.30, merge(st, hip_h=0.84, lean=18, twist=28, stance=1.08, wf=0.72,
                         r_arm=(-92, 16, -4), r_elbow=(-10, 0, 0), blade_angle=0, blade_yaw=4,
                         two_handed=True, haft_offset=h_off, cape_pitch=34), "whip"),
            # Hit 2: Wide sweeping diagonal backhand follow-through
            (0.60, merge(st, hip_h=0.85, lean=10, twist=-42, stance=1.02, wf=0.62,
                         r_arm=(-98, -38, -14), r_elbow=(-14, 0, 0), blade_angle=28, blade_yaw=-46,
                         two_handed=True, haft_offset=h_off, cape_pitch=38), "whip"),
            (0.82, merge(st, hip_h=0.90, lean=6, twist=-20, stance=0.86, wf=0.52), "out"),
            (1.00, st, "inout"),
        ])
    else:  # liuQuanwei: Nonna 2-HIT ARMORED AXE SWING + OVERHEAD CRUSH!
        clips["weapon_forward"] = (40, lambda *_: [
            (0.00, st, "inout"),
            (0.16, merge(st, hip_h=0.86, lean=4, twist=-56, stance=0.86, wf=0.34,
                         r_arm=(-74, -46, -24), r_elbow=(-44, 0, 0), blade_angle=16, blade_yaw=-54,
                         two_handed=True, haft_offset=h_off), "out"),
            # Hit 1: Armored horizontal waist cleave
            (0.30, merge(st, hip_h=0.82, lean=16, twist=46, stance=1.04, wf=0.68,
                         r_arm=(-82, 46, -8), r_elbow=(-14, 0, 0), blade_angle=2, blade_yaw=50,
                         two_handed=True, haft_offset=h_off, cape_pitch=34), "whip"),
            # Hit 2: Rising recoil -> crushing overhead axe slam!
            (0.48, merge(st, hip_h=0.89, lean=-6, twist=-24, stance=0.96, wf=0.46,
                         r_arm=(-150, -14, -12), r_elbow=(-30, 0, 0), blade_angle=146, blade_yaw=-12,
                         two_handed=True, haft_offset=h_off), "out"),
            (0.66, merge(st, hip_h=0.79, lean=20, twist=32, stance=1.10, wf=0.72,
                         r_arm=(-72, 24, -8), r_elbow=(-14, 0, 0), blade_angle=-24, blade_yaw=18,
                         two_handed=True, haft_offset=h_off, cape_pitch=40), "whip"),
            (0.86, merge(st, hip_h=0.84, lean=12, twist=18, stance=0.94, wf=0.58), "out"),
            (1.00, st, "inout"),
        ])

    # 9. SKILL1 (`skill1`): Hero-specific!
    if hk == "wuYong":  # Ruthless Advance — ARMORED ADVANCING FRONT KICK (odachi trailing low behind!)
        clips["skill1"] = ("skill1", lambda su, ac: [
            (0.00, st, "inout"),
            (su, merge(st, hip_h=0.88, lean=-8, twist=-18, stance=0.80, wf=0.50,
                       kick_leg="L", kick_target=(0.26, 0.62),
                       r_arm=(20, -24, -22), r_elbow=(-34, 0, 0), blade_angle=160, blade_yaw=-16,
                       two_handed=False, l_arm=(-52, 18, 14), l_elbow=(-62, 0, 0), cape_pitch=16), "out"),
            (ac, merge(st, hip_h=0.86, lean=-15, twist=-24, stance=0.82, wf=0.45,
                       kick_leg="L", kick_target=(0.80, 1.00),
                       r_arm=(32, -30, -24), r_elbow=(-22, 0, 0), blade_angle=186, blade_yaw=-20,
                       two_handed=False, l_arm=(-64, 24, 16), l_elbow=(-56, 0, 0), cape_pitch=34), "whip"),
            (min(0.82, ac + 0.24), merge(st, hip_h=0.86, lean=4, twist=-10, stance=0.84, wf=0.60,
                       r_arm=(-18, -14, -14), r_elbow=(-32, 0, 0), blade_angle=142, blade_yaw=-12,
                       two_handed=False, l_arm=(-42, 14, 12), l_elbow=(-46, 0, 0), cape_pitch=22), "out"),
            (1.00, st, "inout"),
        ])
    elif hk == "xuXiao":  # Salvation Sky Pillar Cast: raises Crusader sword high to heaven summoning sky lightning!
        clips["skill1"] = ("skill1", lambda su, ac: [
            (0.00, st, "inout"),
            (su, merge(st, hip_h=0.92, lean=-6, twist=-16, stance=0.74, wf=0.42,
                       r_arm=(-156, 6, -8), r_elbow=(-22, 0, 0), blade_angle=102, blade_yaw=4,
                       two_handed=True, haft_offset=h_off, cape_pitch=-6), "out"),
            (ac, merge(st, hip_h=0.94, lean=-10, twist=8, stance=0.80, wf=0.52,
                       r_arm=(-166, 12, -6), r_elbow=(-12, 0, 0), blade_angle=90, blade_yaw=6,
                       two_handed=True, haft_offset=h_off, cape_pitch=26), "whip"),
            (min(0.82, ac + 0.24), merge(st, hip_h=0.91, lean=4, twist=6, stance=0.78, wf=0.50,
                       r_arm=(-108, 12, -8), r_elbow=(-34, 0, 0), blade_angle=64, blade_yaw=8,
                       two_handed=True, haft_offset=h_off, cape_pitch=16), "out"),
            (1.00, st, "inout"),
        ])
    elif hk == "liuQuanwei":  # Nonna Spirit Owl Release: dramatic shamanic sweeping command outward!
        clips["skill1"] = ("skill1", lambda su, ac: [
            (0.00, st, "inout"),
            (su, merge(st, hip_h=0.86, lean=-4, twist=-48, stance=0.86, wf=0.38,
                       r_arm=(-42, -32, -20), r_elbow=(-46, 0, 0), blade_angle=132, blade_yaw=-24,
                       two_handed=False, l_arm=(-56, 36, 18), l_elbow=(-66, 0, 0), cape_pitch=8), "out"),
            (ac, merge(st, hip_h=0.85, lean=14, twist=38, stance=0.98, wf=0.66,
                       r_arm=(-32, -18, -18), r_elbow=(-36, 0, 0), blade_angle=142, blade_yaw=-14,
                       two_handed=False, l_arm=(-94, -18, 12), l_elbow=(-14, 0, 0), cape_pitch=34), "whip"),
            (min(0.82, ac + 0.24), merge(st, hip_h=0.86, lean=10, twist=24, stance=0.92, wf=0.58,
                       r_arm=(-36, -8, -14), r_elbow=(-42, 0, 0), blade_angle=82,
                       two_handed=False, l_arm=(-68, -14, 14), l_elbow=(-32, 0, 0), cape_pitch=20), "out"),
            (1.00, st, "inout"),
        ])
    else:  # sunDeng: Shadow Kunai throwing flick + smoke vanish crouch!
        clips["skill1"] = ("skill1", lambda su, ac: [
            (0.00, st, "inout"),
            (su, merge(st, hip_h=0.80, lean=14, twist=-46, stance=0.88, wf=0.40,
                       r_arm=(-88, -46, -24), r_elbow=(-72, 0, 0), blade_angle=142, blade_yaw=-36,
                       l_arm=(-66, 22, 18), l_elbow=(-56, 0, 0), blade_l_angle=68, blade_l_yaw=20,
                       cape_pitch=16), "out"),
            (ac, merge(st, hip_h=0.78, lean=22, twist=42, stance=1.04, wf=0.68,
                       r_arm=(-92, 24, -8), r_elbow=(-12, 0, 0), blade_angle=4, blade_yaw=16,
                       l_arm=(-24, -22, 24), l_elbow=(-42, 0, 0), blade_l_angle=166, blade_l_yaw=-20,
                       cape_pitch=36), "whip"),
            (min(0.82, ac + 0.24), merge(st, hip_h=0.82, lean=16, twist=24, stance=0.92, wf=0.56), "out"),
            (1.00, st, "inout"),
        ])

    # 10. WEAPON_UP (`weaponUp`): RISING ANTI-AIR UPPERCUT (2-hit double rising arc on Wu Yong!)
    if hk == "wuYong":
        clips["weapon_up"] = (34, lambda *_: [
            (0.00, st, "inout"),
            (0.16, merge(st, hip_h=0.76, lean=18, twist=-38, stance=0.88, wf=0.42,
                         r_arm=(14, -28, -16), r_elbow=(-28, 0, 0), blade_angle=-136, blade_yaw=-18,
                         two_handed=True, haft_offset=h_off), "out"),
            # Rising cut 1
            (0.32, merge(st, hip_h=0.94, lean=-6, twist=28, stance=0.82, wf=0.58,
                         r_arm=(-134, 18, -8), r_elbow=(-14, 0, 0), blade_angle=74, blade_yaw=16,
                         two_handed=True, haft_offset=h_off, cape_pitch=30), "whip"),
            # Rising cut 2 (follow-through downward cross-slash catching airborne foe!)
            (0.56, merge(st, hip_h=0.86, lean=12, twist=-32, stance=0.94, wf=0.64,
                         r_arm=(-92, -32, -14), r_elbow=(-16, 0, 0), blade_angle=22, blade_yaw=-38,
                         two_handed=True, haft_offset=h_off, cape_pitch=34), "whip"),
            (0.82, merge(st, hip_h=0.88, lean=6, twist=-14, stance=0.84, wf=0.54), "out"),
            (1.00, st, "inout"),
        ])
    else:
        clips["weapon_up"] = ("weaponUp", lambda su, ac: [
            (0.00, st, "inout"),
            (su, merge(st, hip_h=st["hip_h"] - 0.10, lean=16 if not is_dual else 22, twist=-36,
                       stance=st["stance"] + 0.08, wf=0.42,
                       r_arm=(14, -26, -16), r_elbow=(-24, 0, 0), blade_angle=-138, blade_yaw=-18,
                       two_handed=two_h, haft_offset=h_off,
                       l_arm=(10, 22, 16), l_elbow=(-28, 0, 0), blade_l_angle=-120, blade_l_yaw=16,
                       cape_pitch=10), "out"),
            (ac, merge(st, hip_h=st["hip_h"] + 0.05, lean=-6 if not is_dual else -2, twist=26,
                       stance=st["stance"] - 0.02, wf=0.58,
                       r_arm=(-134, 18, -8), r_elbow=(-14, 0, 0), blade_angle=74, blade_yaw=14,
                       two_handed=two_h, haft_offset=h_off,
                       l_arm=(-126, -18, 8), l_elbow=(-16, 0, 0), blade_l_angle=64, blade_l_yaw=-14,
                       cape_pitch=28), "whip"),
            (min(0.84, ac + 0.24), merge(st, hip_h=st["hip_h"] + 0.05, lean=-8 if not is_dual else -4, twist=20,
                       stance=st["stance"] - 0.04, wf=0.52,
                       r_arm=(-150, 12, -8), r_elbow=(-26, 0, 0), blade_angle=104, blade_yaw=10,
                       two_handed=two_h, haft_offset=h_off,
                       l_arm=(-142, -12, 8), l_elbow=(-28, 0, 0), blade_l_angle=86, blade_l_yaw=-10,
                       cape_pitch=20), "out"),
            (1.00, st, "inout"),
        ])

    # 11. WEAPON_DOWN (`weaponDown`): DEEP DUCKING HORIZONTAL LOW ANKLE SWEEP (ducks projectiles!)
    clips["weapon_down"] = ("weaponDown", lambda su, ac: [
        (0.00, st, "inout"),
        (su, merge(st, hip_h=0.68, lean=16, twist=-52, stance=st["stance"] + 0.16, wf=0.40,
                   r_arm=(-40, -44, -22), r_elbow=(-44, 0, 0), blade_angle=-24, blade_yaw=-56,
                   two_handed=two_h, haft_offset=h_off,
                   l_arm=(-38, 30, 18), l_elbow=(-44, 0, 0), blade_l_angle=-18, blade_l_yaw=32,
                   cape_pitch=14), "out"),
        (ac, merge(st, hip_h=0.64, lean=26, twist=46, stance=1.18, wf=0.68,
                   r_arm=(-48, 42, -10), r_elbow=(-14, 0, 0), blade_angle=-28, blade_yaw=54,
                   two_handed=two_h, haft_offset=h_off,
                   l_arm=(-46, -34, 12), l_elbow=(-16, 0, 0), blade_l_angle=-26, blade_l_yaw=-38,
                   cape_pitch=34), "whip"),
        (min(0.84, ac + 0.24), merge(st, hip_h=0.68, lean=20, twist=48, stance=1.10, wf=0.60,
                   r_arm=(-38, 46, -10), r_elbow=(-24, 0, 0), blade_angle=-36, blade_yaw=58,
                   two_handed=two_h, haft_offset=h_off,
                   l_arm=(-34, -36, 12), l_elbow=(-26, 0, 0), blade_l_angle=-36, blade_l_yaw=-40), "out"),
        (1.00, st, "inout"),
    ])

    # 12. WEAPON_BACK (`weaponBack`): COUNTER-STEP SPINNING REVERSE BACKHAND HOOK
    clips["weapon_back"] = ("weaponBack", lambda su, ac: [
        (0.00, st, "inout"),
        (su, merge(st, hip_h=st["hip_h"] - 0.04, lean=-6, twist=52, hips_yaw=20, stance=st["stance"] + 0.04, wf=0.35,
                   r_arm=(-64, 52, -14), r_elbow=(-42, 0, 0), blade_angle=22, blade_yaw=56,
                   two_handed=two_h, haft_offset=h_off,
                   l_arm=(-74, 38, 14), l_elbow=(-42, 0, 0), blade_l_angle=44, blade_l_yaw=42), "out"),
        (ac, merge(st, hip_h=st["hip_h"] - 0.05, lean=14, twist=-48, hips_yaw=-22, stance=st["stance"] + 0.16, wf=0.62,
                   r_arm=(-88, -42, -14), r_elbow=(-12, 0, 0), blade_angle=8, blade_yaw=-48,
                   two_handed=two_h, haft_offset=h_off,
                   l_arm=(-84, -38, 12), l_elbow=(-14, 0, 0), blade_l_angle=-8, blade_l_yaw=-42,
                   cape_pitch=34), "whip"),
        (min(0.84, ac + 0.22), merge(st, hip_h=st["hip_h"] - 0.02, lean=8, twist=-34, stance=st["stance"] + 0.08, wf=0.54,
                   r_arm=(-68, -40, -14), r_elbow=(-28, 0, 0), blade_angle=32, blade_yaw=-38,
                   two_handed=two_h, haft_offset=h_off,
                   l_arm=(-54, -28, 14), l_elbow=(-28, 0, 0), blade_l_angle=-34, blade_l_yaw=-32), "out"),
        (1.00, st, "inout"),
    ])

    # 13. KICKS (`kick`, `kick_forward`, `kick_up`, `kick_down`, `kick_back`)
    if is_dual:
        k_arm_su = dict(r_arm=(-52, 14, -24), r_elbow=(-56, 0, 0), blade_angle=112, blade_yaw=-14,
                        l_arm=(-58, -16, 22), l_elbow=(-54, 0, 0), blade_l_angle=60, blade_l_yaw=14)
        k_arm_ac = dict(r_arm=(14, -26, -28), r_elbow=(-42, 0, 0), blade_angle=156, blade_yaw=-22,
                        l_arm=(-56, -18, 22), l_elbow=(-52, 0, 0), blade_l_angle=32, blade_l_yaw=16)
    else:
        ang_k = 96 if hk == "xuXiao" else (88 if hk == "liuQuanwei" else 102)
        k_arm_su = dict(r_arm=(-46, 14, -10), r_elbow=(-48, 0, 0), blade_angle=ang_k - 8, blade_yaw=16,
                        two_handed=True, haft_offset=h_off)
        k_arm_ac = dict(r_arm=(-50, 12, -12), r_elbow=(-52, 0, 0), blade_angle=ang_k, blade_yaw=18,
                        two_handed=True, haft_offset=h_off)

    k_h = 0.96 if hk == "wuYong" else (0.90 if hk == "xuXiao" else (0.86 if hk == "liuQuanwei" else 1.04))
    clips["kick"] = ("kick", lambda su, ac: [
        (0.00, st, "inout"),
        (su, merge(st, hip_h=st["hip_h"] - 0.02, lean=-5, twist=-14,
                   kick_leg="L", kick_target=(0.22, 0.56), **k_arm_su), "out"),
        (ac, merge(st, hip_h=st["hip_h"] - 0.03, lean=-16, twist=-20,
                   kick_leg="L", kick_target=(0.74, k_h), cape_pitch=26, **k_arm_ac), "whip"),
        (min(0.84, ac + 0.24), merge(st, hip_h=st["hip_h"], lean=4, twist=-8, stance=st["stance"], wf=0.55), "out"),
        (1.00, st, "inout"),
    ])
    clips["kick_forward"] = ("kickForward", lambda su, ac: [
        (0.00, st, "inout"),
        (su, merge(st, hip_h=st["hip_h"] - 0.03, lean=-8, twist=-18,
                   kick_leg="L", kick_target=(0.28, 0.62), **k_arm_su), "out"),
        (ac, merge(st, hip_h=st["hip_h"] - 0.04, lean=-16, twist=-24,
                   kick_leg="L", kick_target=(0.82, 1.00), cape_pitch=34, **k_arm_ac), "whip"),
        (min(0.84, ac + 0.22), merge(st, hip_h=st["hip_h"] - 0.02, lean=6, twist=-10, stance=st["stance"] + 0.12, wf=0.62), "out"),
        (1.00, st, "inout"),
    ])
    clips["kick_up"] = ("kickUp", lambda su, ac: [
        (0.00, st, "inout"),
        (su, merge(st, hip_h=st["hip_h"] - 0.04, lean=-10, twist=-18,
                   kick_leg="L", kick_target=(0.24, 0.68), **k_arm_su), "out"),
        (ac, merge(st, hip_h=st["hip_h"] - 0.02, lean=-24, twist=-26,
                   kick_leg="L", kick_target=(0.68, 1.38), cape_pitch=34, **k_arm_ac), "whip"),
        (min(0.84, ac + 0.24), merge(st, hip_h=st["hip_h"], lean=-4, twist=-12, stance=st["stance"], wf=0.52), "out"),
        (1.00, st, "inout"),
    ])
    clips["kick_down"] = ("kickDown", lambda su, ac: [
        (0.00, st, "inout"),
        (su, merge(st, hip_h=0.68, lean=18, twist=-26, stance=0.88, wf=0.42,
                   kick_leg="L", kick_target=(0.14, 0.26), **k_arm_su), "out"),
        (ac, merge(st, hip_h=0.60, lean=24, twist=30, stance=1.02, wf=0.35,
                   kick_leg="L", kick_target=(0.82, 0.18), cape_pitch=32, **k_arm_ac), "whip"),
        (min(0.84, ac + 0.24), merge(st, hip_h=0.72, lean=16, twist=18, stance=0.94, wf=0.50), "out"),
        (1.00, st, "inout"),
    ])
    clips["kick_back"] = ("kickBack", lambda su, ac: [
        (0.00, st, "inout"),
        (su, merge(st, hip_h=st["hip_h"] - 0.03, lean=10, twist=44,
                   kick_leg="R", kick_target=(0.20, 0.56), **k_arm_su), "out"),
        (ac, merge(st, hip_h=st["hip_h"] - 0.04, lean=-18, twist=58,
                   kick_leg="R", kick_target=(0.78, 1.02), cape_pitch=36, **k_arm_ac), "whip"),
        (min(0.84, ac + 0.24), merge(st, hip_h=st["hip_h"], lean=4, twist=18, stance=st["stance"] + 0.08, wf=0.52), "out"),
        (1.00, st, "inout"),
    ])

    # 14. THROW (`throw` — close shoulder-throw)
    clips["throw"] = ("throwForward", lambda su, ac: [
        (0.00, st, "inout"),
        (su, merge(st, hip_h=0.74, lean=20, twist=-24, stance=0.90, wf=0.62,
                   r_arm=(-96, 18, -10), r_elbow=(-46, 0, 0), blade_angle=112,
                   two_handed=False, l_arm=(-92, -18, 10), l_elbow=(-48, 0, 0)), "out"),
        (ac, merge(st, hip_h=0.80, lean=28, twist=46, stance=1.02, wf=0.70,
                   r_arm=(-44, 38, -8), r_elbow=(-24, 0, 0), blade_angle=-28,
                   two_handed=False, l_arm=(-48, 32, 12), l_elbow=(-28, 0, 0), cape_pitch=36), "whip"),
        (min(0.84, ac + 0.24), merge(st, hip_h=0.84, lean=16, twist=28, stance=0.92, wf=0.58), "out"),
        (1.00, st, "inout"),
    ])

    # 15. SKILL2 (`skill2` — Deliverance Scar / Flame Roar / Blink Stance / Retainer Command)
    clips["skill2"] = ("skill2", lambda su, ac: [
        (0.00, st, "inout"),
        (su, merge(st, hip_h=st["hip_h"] + 0.02, lean=-10, twist=-32, stance=st["stance"], wf=0.38,
                   r_arm=(-142, -16, -12), r_elbow=(-32, 0, 0), blade_angle=142, blade_yaw=-14,
                   two_handed=two_h, haft_offset=h_off,
                   l_arm=(-120, -14, 14), l_elbow=(-32, 0, 0), blade_l_angle=128), "out"),
        (ac, merge(st, hip_h=st["hip_h"] - 0.06, lean=18, twist=38, stance=st["stance"] + 0.22, wf=0.68,
                   r_arm=(-86, 32, -6), r_elbow=(-12, 0, 0), blade_angle=-10, blade_yaw=24,
                   two_handed=two_h, haft_offset=h_off,
                   l_arm=(-84, -28, 8), l_elbow=(-12, 0, 0), blade_l_angle=-12, blade_l_yaw=-24,
                   cape_pitch=36), "whip"),
        (min(0.84, ac + 0.24), merge(st, hip_h=st["hip_h"] - 0.02, lean=12, twist=24, stance=st["stance"] + 0.12, wf=0.58), "out"),
        (1.00, st, "inout"),
    ])

    # 16. HERO SIGNATURE SHADOW / FORM OF LIGHT MOVES!
    if hk == "wuYong":
        # Fierce Reprisal: 2-HIT CATACLYSM DASH DOUBLE-SLASH (blazing horizontal slash 1 -> spinning reverse execution 2!)
        clips["shogun_fierce"] = (48, lambda *_: [
            (0.00, st, "inout"),
            (0.18, merge(st, hip_h=0.78, lean=14, twist=-56, hips_yaw=-24, stance=0.92, wf=0.36,
                         r_arm=(-48, -46, -24), r_elbow=(-56, 0, 0), blade_angle=-12, blade_yaw=-58,
                         two_handed=True, haft_offset=h_off, cape_pitch=14), "out"),
            # Hit 1: Blazing horizontal dash cleave
            (0.32, merge(st, hip_h=0.76, lean=22, twist=50, hips_yaw=26, stance=1.14, wf=0.76,
                         r_arm=(-86, 48, -8), r_elbow=(-10, 0, 0), blade_angle=4, blade_yaw=54,
                         two_handed=True, haft_offset=h_off, cape_pitch=44), "whip"),
            # Hit 2: Spinning reverse diagonal execution slash!
            (0.56, merge(st, hip_h=0.82, lean=14, twist=-52, hips_yaw=-28, stance=1.08, wf=0.70,
                         r_arm=(-108, -42, -16), r_elbow=(-12, 0, 0), blade_angle=34, blade_yaw=-52,
                         two_handed=True, haft_offset=h_off, cape_pitch=44), "whip"),
            (0.80, merge(st, hip_h=0.84, lean=10, twist=-28, stance=0.94, wf=0.58), "out"),
            (1.00, st, "inout"),
        ])
        # Despotism: planted blade frontal ward -> explosive telekinetic rising uppercut launch!
        clips["shogun_despotism"] = ("shogunDespotism", lambda su, ac: [
            (0.00, st, "inout"),
            (su, merge(st, hip_h=0.78, lean=14, twist=-48, stance=0.94, wf=0.38,
                       r_arm=(16, -32, -18), r_elbow=(-28, 0, 0), blade_angle=-142, blade_yaw=-24,
                       two_handed=True, haft_offset=h_off, cape_pitch=16), "out"),
            (ac, merge(st, hip_h=0.93, lean=-8, twist=36, stance=0.96, wf=0.66,
                       r_arm=(-128, 24, -8), r_elbow=(-12, 0, 0), blade_angle=58, blade_yaw=22,
                       two_handed=True, haft_offset=h_off, cape_pitch=40), "whip"),
            (min(0.82, ac + 0.24), merge(st, hip_h=0.90, lean=-4, twist=28, stance=0.90, wf=0.58,
                       r_arm=(-142, 18, -8), r_elbow=(-24, 0, 0), blade_angle=92, blade_yaw=16,
                       two_handed=True, haft_offset=h_off), "out"),
            (1.00, st, "inout"),
        ])
    elif hk == "xuXiao":
        # SOARING MID-AIR FORM OF LIGHT MOVESET (airborne_legs=True — floating angelic Crusader!)
        clips["inquisitor_spin"] = ("inquisitorLightSpin", lambda su, ac: [
            (0.00, merge(st, airborne_legs=True, hip_h=0.96, lean=6), "inout"),
            (su, merge(st, airborne_legs=True, hip_h=0.98, lean=4, twist=-64, hips_yaw=-36,
                       r_arm=(-92, -48, -20), r_elbow=(-22, 0, 0), blade_angle=22, blade_yaw=-54,
                       two_handed=True, haft_offset=h_off, cape_pitch=34), "out"),
            (ac, merge(st, airborne_legs=True, hip_h=0.98, lean=16, twist=62, hips_yaw=38,
                       r_arm=(-88, 48, -8), r_elbow=(-10, 0, 0), blade_angle=-6, blade_yaw=54,
                       two_handed=True, haft_offset=h_off, cape_pitch=52), "whip"),
            (min(0.82, ac + 0.24), merge(st, airborne_legs=True, hip_h=0.96, lean=10, twist=38,
                       r_arm=(-64, 42, -10), r_elbow=(-24, 0, 0), blade_angle=-28, blade_yaw=40,
                       two_handed=True, haft_offset=h_off, cape_pitch=38), "out"),
            (1.00, merge(st, airborne_legs=True, hip_h=0.96), "inout"),
        ])
        clips["inquisitor_light_up"] = ("inquisitorLightUp", lambda su, ac: [
            (0.00, merge(st, airborne_legs=True, hip_h=0.96), "inout"),
            (su, merge(st, airborne_legs=True, hip_h=0.94, lean=14, twist=-38,
                       r_arm=(12, -26, -16), r_elbow=(-30, 0, 0), blade_angle=-126, blade_yaw=-20,
                       two_handed=True, haft_offset=h_off, cape_pitch=24), "out"),
            (ac, merge(st, airborne_legs=True, hip_h=1.02, lean=-10, twist=30,
                       r_arm=(-142, 20, -8), r_elbow=(-12, 0, 0), blade_angle=82, blade_yaw=16,
                       two_handed=True, haft_offset=h_off, cape_pitch=46), "whip"),
            (1.00, merge(st, airborne_legs=True, hip_h=0.96), "inout"),
        ])
        clips["inquisitor_light_forward"] = ("inquisitorLightForward", lambda su, ac: [
            (0.00, merge(st, airborne_legs=True, hip_h=0.96), "inout"),
            (su, merge(st, airborne_legs=True, hip_h=0.96, lean=10, twist=-44,
                       r_arm=(-48, -32, -14), r_elbow=(-70, 0, 0), blade_angle=4, blade_yaw=-10,
                       two_handed=True, haft_offset=h_off, cape_pitch=28), "out"),
            (ac, merge(st, airborne_legs=True, hip_h=0.95, lean=26, twist=28,
                       r_arm=(-96, 14, -4), r_elbow=(-8, 0, 0), blade_angle=0, blade_yaw=4,
                       two_handed=True, haft_offset=h_off, cape_pitch=56), "whip"),
            (1.00, merge(st, airborne_legs=True, hip_h=0.96), "inout"),
        ])
        clips["inquisitor_light_down"] = ("inquisitorLightDown", lambda su, ac: [
            (0.00, merge(st, airborne_legs=True, hip_h=0.96), "inout"),
            (su, merge(st, airborne_legs=True, hip_h=1.04, lean=-12, twist=-20,
                       r_arm=(-164, -8, -8), r_elbow=(-24, 0, 0), blade_angle=142, blade_yaw=-8,
                       two_handed=True, haft_offset=h_off, cape_pitch=12), "out"),
            (ac, merge(st, airborne_legs=True, hip_h=0.88, lean=34, twist=24,
                       r_arm=(-54, 18, -6), r_elbow=(-10, 0, 0), blade_angle=-68, blade_yaw=10,
                       two_handed=True, haft_offset=h_off, cape_pitch=54), "whip"),
            (1.00, merge(st, airborne_legs=True, hip_h=0.96), "inout"),
        ])
    elif hk == "sunDeng":
        clips["midnight_removal"] = ("midnightRemoval", lambda su, ac: [
            (0.00, st, "inout"),
            (su, merge(st, hip_h=0.78, lean=18, twist=-38, stance=0.96, wf=0.38,
                       r_arm=(-136, -34, -20), r_elbow=(-30, 0, 0), blade_angle=148, blade_yaw=-28,
                       l_arm=(-132, 34, 20), l_elbow=(-30, 0, 0), blade_l_angle=138, blade_l_yaw=28,
                       cape_pitch=20), "out"),
            (ac, merge(st, hip_h=0.72, lean=28, twist=28, stance=1.20, wf=0.74,
                       r_arm=(-82, 40, -8), r_elbow=(-10, 0, 0), blade_angle=-24, blade_yaw=36,
                       l_arm=(-86, -40, 8), l_elbow=(-10, 0, 0), blade_l_angle=20, blade_l_yaw=-36,
                       cape_pitch=46), "whip"),
            (min(0.82, ac + 0.24), merge(st, hip_h=0.78, lean=22, twist=20, stance=1.04, wf=0.62,
                       r_arm=(-44, 44, -10), r_elbow=(-22, 0, 0), blade_angle=-58, blade_yaw=40,
                       l_arm=(-46, -44, 10), l_elbow=(-22, 0, 0), blade_l_angle=-72, blade_l_yaw=-40,
                       cape_pitch=34), "out"),
            (1.00, st, "inout"),
        ])

    # 17. VIOLENT FRAME-1 SNAP-BACK HIT RECOIL + KNOCKDOWN + GETUP + JUMP + WAKEUP + ROLLS!
    # Starting at peak recoil snap (0.06) makes every strike visibly whip the victim backward as they slide!
    hit_peak = merge(st, hip_h=st["hip_h"] - 0.06, lean=-28, twist=28, stance=st["stance"] + 0.14, wf=0.28,
                     r_arm=(-20, -24, -22), r_elbow=(-34, 0, 0), blade_angle=118,
                     two_handed=False, l_arm=(-30, 26, 28), l_elbow=(-32, 0, 0),
                     head_pitch=-24, head_yaw=18, cape_pitch=-22)
    clips["hit"] = (18, lambda *_: [
        (0.00, merge(hit_peak, lean=-18, twist=18), "inout"),
        (0.14, hit_peak, "whip"),
        (0.58, merge(st, hip_h=st["hip_h"] - 0.03, lean=-12, twist=12, stance=st["stance"] + 0.06, wf=0.40), "out"),
        (1.00, st, "inout"),
    ])
    hit_head_peak = merge(st, hip_h=st["hip_h"] - 0.03, lean=-36, twist=34, stance=st["stance"] + 0.10, wf=0.26,
                          r_arm=(-24, -22, -20), r_elbow=(-38, 0, 0), blade_angle=92,
                          two_handed=False, l_arm=(-54, 28, 28), l_elbow=(-58, 0, 0),
                          head_pitch=-50, head_yaw=30, cape_pitch=-28)
    clips["hit_head"] = (18, lambda *_: [
        (0.00, merge(hit_head_peak, lean=-24, head_pitch=-34), "inout"),
        (0.12, hit_head_peak, "whip"),
        (0.60, merge(st, hip_h=st["hip_h"] - 0.02, lean=-14, twist=14, head_pitch=-18), "out"),
        (1.00, st, "inout"),
    ])
    hit_low_peak = merge(st, hip_h=0.62, lean=34, twist=-22, stance=st["stance"] + 0.20, wf=0.64,
                         r_arm=(-22, 18, -22), r_elbow=(-38, 0, 0), blade_angle=-28,
                         two_handed=False, l_arm=(-34, -20, 20), l_elbow=(-42, 0, 0),
                         head_pitch=24, cape_pitch=30)
    clips["hit_low"] = (18, lambda *_: [
        (0.00, merge(hit_low_peak, hip_h=0.72, lean=22), "inout"),
        (0.14, hit_low_peak, "whip"),
        (0.64, merge(st, hip_h=0.78, lean=16, stance=st["stance"] + 0.08), "out"),
        (1.00, st, "inout"),
    ])

    kd_mid = merge(st, hip_h=0.56, hips_pitch=-44, lean=-24, twist=10, stance=0.62, wf=0.35,
                   r_arm=(-28, -20, -28), r_elbow=(-28, 0, 0), blade_angle=118,
                   two_handed=False, l_arm=(-32, 22, 26), l_elbow=(-32, 0, 0),
                   head_lock=False, head_pitch=-18, cape_pitch=-16)
    kd_flat = merge(st, hip_h=0.24, hips_pitch=-82, lean=-12, twist=6, stance=0.52, wf=0.40,
                    kick_leg="L", kick_target=(0.68, 0.24),
                    r_arm=(-12, -24, -34), r_elbow=(-20, 0, 0), blade_angle=165,
                    two_handed=False, l_arm=(-16, 26, 30), l_elbow=(-24, 0, 0),
                    head_lock=False, head_pitch=14, cape_pitch=-6)
    clips["knockdown"] = (20, lambda *_: [
        (0.00, st, "inout"),
        (0.42, kd_mid, "whip"),
        (0.82, kd_flat, "out"),
        (1.00, kd_flat, "inout"),
    ])
    clips["getup"] = (18, lambda *_: [
        (0.00, kd_flat, "inout"),
        (0.45, merge(st, hip_h=0.62, hips_pitch=-18, lean=24, stance=0.88, wf=0.58,
                     r_arm=(-44, 10, -14), r_elbow=(-42, 0, 0), blade_angle=18,
                     two_handed=False, l_arm=(-56, -12, 16), l_elbow=(-30, 0, 0)), "out"),
        (1.00, st, "inout"),
    ])
    clips["jump"] = (28, lambda *_: [
        (0.00, merge(st, hip_h=st["hip_h"] - 0.14, lean=14, stance=st["stance"] + 0.08), "inout"),
        (0.28, merge(st, hip_h=0.96, lean=8, stance=0.48, kick_leg="L", kick_target=(0.30, 0.56),
                     r_arm=(-68, 12, -16), r_elbow=(-52, 0, 0), blade_angle=64,
                     two_handed=two_h, haft_offset=h_off, cape_pitch=28), "out"),
        (0.55, merge(st, hip_h=0.94, lean=10, stance=0.52, kick_leg="L", kick_target=(0.36, 0.52),
                     r_arm=(-74, 14, -14), r_elbow=(-54, 0, 0), blade_angle=52,
                     two_handed=two_h, haft_offset=h_off, cape_pitch=34), "inout"),
        (0.84, merge(st, hip_h=st["hip_h"] - 0.10, lean=14, stance=st["stance"] + 0.10), "in"),
        (1.00, st, "inout"),
    ])
    clips["wakeup_kick"] = (24, lambda *_: [
        (0.00, kd_flat, "inout"),
        (0.26, merge(st, hip_h=0.44, hips_pitch=-34, lean=14, twist=-32, stance=0.84, wf=0.38,
                     kick_leg="L", kick_target=(0.14, 0.28),
                     r_arm=(-24, -18, -22), r_elbow=(-36, 0, 0), blade_angle=128,
                     two_handed=False, l_arm=(-48, 16, 20), l_elbow=(-32, 0, 0)), "out"),
        (0.39, merge(st, hip_h=0.52, hips_pitch=-16, lean=22, twist=36, stance=1.06, wf=0.35,
                     kick_leg="L", kick_target=(0.86, 0.20),
                     r_arm=(-32, -24, -20), r_elbow=(-30, 0, 0), blade_angle=142,
                     two_handed=False, l_arm=(-54, 18, 22), l_elbow=(-30, 0, 0), cape_pitch=34), "whip"),
        (0.72, merge(st, hip_h=0.76, lean=14, twist=12, stance=st["stance"] + 0.08, wf=0.54), "out"),
        (1.00, st, "inout"),
    ])
    clips["roll_forward"] = (18, lambda *_: [
        (0.00, merge(st, hip_h=0.72, lean=30, stance=0.86), "inout"),
        (0.24, merge(st, hip_h=0.62, hips_pitch=85, lean=24, stance=0.42,
                     r_arm=(-48, 20, -18), r_elbow=(-72, 0, 0),
                     two_handed=False, l_arm=(-52, -20, 18), l_elbow=(-72, 0, 0), head_lock=False, head_pitch=24), "whip"),
        (0.50, merge(st, hip_h=0.60, hips_pitch=175, lean=20, stance=0.38,
                     r_arm=(-48, 20, -18), r_elbow=(-74, 0, 0),
                     two_handed=False, l_arm=(-52, -20, 18), l_elbow=(-74, 0, 0), head_lock=False, head_pitch=26), "inout"),
        (0.76, merge(st, hip_h=0.66, hips_pitch=270, lean=22, stance=0.64,
                     r_arm=(-46, 16, -14), r_elbow=(-60, 0, 0),
                     two_handed=False, l_arm=(-48, -16, 14), l_elbow=(-60, 0, 0), head_lock=False, head_pitch=18), "inout"),
        (1.00, st, "inout"),
    ])
    clips["roll_back"] = (18, lambda *_: [
        (0.00, merge(st, hip_h=0.72, lean=-18, stance=0.84), "inout"),
        (0.24, merge(st, hip_h=0.62, hips_pitch=-85, lean=-18, stance=0.42,
                     r_arm=(-48, 16, -18), r_elbow=(-72, 0, 0),
                     two_handed=False, l_arm=(-52, -16, 18), l_elbow=(-72, 0, 0), head_lock=False, head_pitch=20), "whip"),
        (0.50, merge(st, hip_h=0.60, hips_pitch=-175, lean=-16, stance=0.38,
                     r_arm=(-48, 16, -18), r_elbow=(-74, 0, 0),
                     two_handed=False, l_arm=(-52, -16, 18), l_elbow=(-74, 0, 0), head_lock=False, head_pitch=22), "inout"),
        (0.76, merge(st, hip_h=0.66, hips_pitch=-270, lean=-14, stance=0.64,
                     r_arm=(-46, 14, -14), r_elbow=(-60, 0, 0),
                     two_handed=False, l_arm=(-48, -14, 14), l_elbow=(-60, 0, 0), head_lock=False, head_pitch=16), "inout"),
        (1.00, st, "inout"),
    ])

    return clips


def author_hero(hk):
    glb_path = CHAR_DIR / f"DuelChar_{hk}.glb"
    rig = Rig(glb_path, hk)
    suffix = HERO_RIG_SUFFIX[hk]
    hero_enum = HERO_ENUM[hk]
    clips = build_hero_clips(hk)

    idle_r, _ = rig.build_pose(hero_stance(hk))
    authored_prefixes = set()

    for base_name, (timing, builder) in clips.items():
        if isinstance(timing, int):
            num_frames = timing
            kfs = builder(0.3, 0.5)
        else:
            su, ac, rec, _reach, _armor = ga.frame_data(timing, hero_enum)
            total = su + ac + rec
            denom = max(1, total - 1)
            p_su = max(0.08, (su - 1) / denom)
            # Target exact active midpoint so peak velocity & forward extension sit squarely inside active!
            p_ac = min(0.70, (su + ac * 0.5) / denom)
            num_frames = total
            kfs = builder(p_su, p_ac)
        clip_name = f"{base_name}_{suffix}"
        rig.write_clip(clip_name, num_frames, 60.0, kfs)
        authored_prefixes.add(base_name)

    # Clean preserved clips (hit, hit_head, hit_low, knockdown, getup, jump)
    rig.clean_existing_clips(authored_prefixes, idle_r)
    rig.save()
    print(f"[authored] {hk}: {len(authored_prefixes)} 60fps hero-specific clips + hygiene pass -> {glb_path.name} ({glb_path.stat().st_size / 1e6:.2f} MB)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--heroes", nargs="*", default=["wuYong", "xuXiao", "liuQuanwei", "sunDeng"])
    args = ap.parse_args()
    for hk in args.heroes:
        author_hero(hk)


if __name__ == "__main__":
    main()
