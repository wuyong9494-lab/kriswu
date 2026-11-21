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

        # Limb segment lengths from rest pose
        self.len_thigh = vlen(vsub(self.wp("Shin.R"), self.wp("Thigh.R")))
        self.len_shin = vlen(vsub(self.wp("Foot.R"), self.wp("Shin.R")))
        self.len_uarm_l = vlen(vsub(self.wp("Forearm.L"), self.wp("UpperArm.L")))
        self.len_farm_l = vlen(vsub(self.wp("Hand.L"), self.wp("Forearm.L")))
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
            # Sagittal 2-bone IK: hanging leg starts pointing -Y (angle = -90 deg in (Z,Y))
            dist = math.hypot(dz, dy_leg)
            max_reach = (l1 + l2) * 0.992
            min_reach = abs(l1 - l2) + 0.08
            dist_c = max(min_reach, min(max_reach, dist))

            # Angle from -Y toward +Z: alpha = atan2(dz, -dy_leg)
            # Positive alpha means target is forward (+Z), which is NEGATIVE X rotation!
            alpha = math.atan2(dz, -dy_leg)
            cos_hip = max(-1.0, min(1.0, (l1 * l1 + dist_c * dist_c - l2 * l2) / (2.0 * l1 * dist_c)))
            beta = math.acos(cos_hip)
            # Knee bends forward (+Z) -> thigh tilts MORE forward (+alpha + beta), shin bends back!
            cos_knee = max(-1.0, min(1.0, (l1 * l1 + l2 * l2 - dist_c * dist_c) / (2.0 * l1 * l2)))
            knee_flex_deg = math.degrees(math.pi - math.acos(cos_knee))  # always >= 0!
            thigh_fwd_deg = math.degrees(alpha + beta)

            # In glTF: pitching a -Y limb forward (+Z) is NEGATIVE X rotation; bending shin back is POSITIVE X!
            th_pitch = -thigh_fwd_deg
            sh_pitch = knee_flex_deg
            # Keep planted foot flat; on kick point/flex foot forward
            if is_kicking:
                ft_pitch = -18.0 if kick_target[0] >= 0 else 15.0
            else:
                ft_pitch = -(th_pitch + sh_pitch)
                ft_pitch = max(-35.0, min(40.0, ft_pitch))

            # Small hip turnout on back foot for authentic martial stance
            foot_yaw = (14.0 if side == "L" else -14.0) if not is_kicking else 0.0
            if side == kick_leg and p.get("kick_yaw"):
                foot_yaw = p["kick_yaw"]

            # Apply thigh world-aligned orientation (canceling excessive pelvis yaw/pitch)
            th_world_delta = qmul(qeuler_xyz(th_pitch, foot_yaw, 0.0), inv_hips_q)
            lr[self.idx(th_name)] = self.delta_local(th_name, th_world_delta)
            lr[self.idx(sh_name)] = self.delta_local(sh_name, qeuler_xyz(sh_pitch, 0.0, 0.0))
            lr[self.idx(ft_name)] = self.delta_local(ft_name, qeuler_xyz(ft_pitch, 0.0, 0.0))

        # 6. Right Arm (Shoulder.R, UpperArm.R, Forearm.R, Hand.R) + Exact Weapon Blade Pitch
        r_sh = p.get("r_shoulder", (0.0, 0.0, 0.0))
        r_arm = p.get("r_arm", (-30.0, 0.0, 0.0))
        r_elb = p.get("r_elbow", (-25.0, 0.0, 0.0))
        # Liu Quanwei's heavy draped shamanic cloak covers Forearm.R/Hand.R (0 mesh verts
        # on Forearm.R). Extending UpperArm.R far forward pushes the axe socket 20 cm past
        # his visible cloak silhouette, so scale his right arm reach closer to his torso
        # while keeping full torso twist and blade-arc sweep!
        if self.hero_key == "liuQuanwei":
            r_arm = (r_arm[0] * 0.42 - 6.0, r_arm[1] * 0.45, r_arm[2] * 0.5)
            r_elb = (r_elb[0] * 0.45 - 8.0, r_elb[1] * 0.5, r_elb[2] * 0.5)
        lr[self.idx("Shoulder.R")] = self.delta_local("Shoulder.R", qeuler_xyz(*r_sh))
        lr[self.idx("UpperArm.R")] = self.delta_local("UpperArm.R", qeuler_xyz(*r_arm))
        lr[self.idx("Forearm.R")] = self.delta_local("Forearm.R", qeuler_xyz(*r_elb))

        wp, wr = self.fk(lr, lt)

        # Align weapon_socket_r (and Hand.R) to hit target side-view blade_angle smoothly!
        if "blade_angle" in p and "weapon_socket_r" in self.by_name:
            sock_idx = self.idx("weapon_socket_r")
            sock_parent = self.parent[sock_idx]
            cur_swr = wr[sock_idx]
            # Blade +Y axis in glTF world space (note: rw_euler is pure Y so +Y is invariant!)
            cur_dir = qrot(cur_swr, (0.0, 1.0, 0.0))
            cur_ang = math.degrees(math.atan2(cur_dir[1], cur_dir[2]))
            tgt_ang = p["blade_angle"]
            # Shortest angular delta in side plane (YZ):
            # In YZ, rotating around +X by +d turns (0,1,0) toward +Z, DECREASING atan2(y,z) by d!
            ang_diff = ((tgt_ang - cur_ang + 180.0) % 360.0) - 180.0
            max_w = p.get("blade_max_wrist", 115.0)
            clamped_diff = max(-max_w, min(max_w, ang_diff))
            # Rotate world orientation around +X by -clamped_diff, plus optional yaw
            byaw = p.get("blade_yaw", 0.0)
            wrist_world_q = qmul(qeuler_xyz(0.0, byaw, 0.0), qaxis((1.0, 0.0, 0.0), -clamped_diff))
            tgt_swr = qnorm(qmul(wrist_world_q, cur_swr))
            lr[sock_idx] = self.abs_local("weapon_socket_r", wr[sock_parent], tgt_swr)
            # Also pitch Hand.R similarly (65% blend) so visual glove bends naturally with weapon!
            h_idx = self.idx("Hand.R")
            hp_idx = self.parent[h_idx]
            hand_q = qslerp((0, 0, 0, 1), wrist_world_q, 0.65)
            lr[h_idx] = self.abs_local("Hand.R", wr[hp_idx], qnorm(qmul(hand_q, wr[h_idx])))

        wp, wr = self.fk(lr, lt)

        # 7. Left Arm: either 2-bone IK gripping two-handed weapon haft, OR manual pose (+ left blade for sunDeng)
        if p.get("two_handed", False) and "weapon_socket_r" in self.by_name:
            sock_idx = self.idx("weapon_socket_r")
            sock_wp = wp[sock_idx]
            sock_wr = wr[sock_idx]
            # Account for JSON rightWeapon.position (in socket local space)
            grip_w = vadd(sock_wp, qrot(sock_wr, self.rw_pos))
            bdir = vnorm(qrot(sock_wr, (0.0, 1.0, 0.0)))
            haft_off = p.get("haft_offset", -0.10)
            # Target for Hand.L palm (offset slightly toward left shoulder so wrist doesn't clip blade)
            tgt_l = vadd(grip_w, vscale(bdir, haft_off))
            self._solve_left_arm_ik(lr, lt, wp, wr, tgt_l)
        else:
            l_sh = p.get("l_shoulder", (0.0, 0.0, 0.0))
            l_arm = p.get("l_arm", (-20.0, 0.0, 0.0))
            l_elb = p.get("l_elbow", (-30.0, 0.0, 0.0))
            lr[self.idx("Shoulder.L")] = self.delta_local("Shoulder.L", qeuler_xyz(*l_sh))
            lr[self.idx("UpperArm.L")] = self.delta_local("UpperArm.L", qeuler_xyz(*l_arm))
            lr[self.idx("Forearm.L")] = self.delta_local("Forearm.L", qeuler_xyz(*l_elb))
            if "blade_l_angle" in p and "weapon_socket_l" in self.by_name:
                wp, wr = self.fk(lr, lt)
                sli = self.idx("weapon_socket_l")
                slp = self.parent[sli]
                cur_dir = qrot(wr[sli], (0.0, 1.0, 0.0))
                cur_ang = math.degrees(math.atan2(cur_dir[1], cur_dir[2]))
                diff = ((p["blade_l_angle"] - cur_ang + 180.0) % 360.0) - 180.0
                diff = max(-115.0, min(115.0, diff))
                lyaw = p.get("blade_l_yaw", 0.0)
                wq = qmul(qeuler_xyz(0.0, lyaw, 0.0), qaxis((1.0, 0.0, 0.0), -diff))
                lr[sli] = self.abs_local("weapon_socket_l", wr[slp], qnorm(qmul(wq, wr[sli])))

        return lr, lt

    def _solve_left_arm_ik(self, lr, lt, wp, wr, target_pos):
        """Analytical 2-bone 3D IK for Shoulder.L + UpperArm.L + Forearm.L to place Hand.L onto target_pos."""
        # Slight proactive shoulder reach across chest for comfortable 2H reach
        lr[self.idx("Shoulder.L")] = self.delta_local("Shoulder.L", qeuler_xyz(0.0, -18.0, 0.0))
        wp, wr = self.fk(lr, lt)

        ua_i = self.idx("UpperArm.L")
        fa_i = self.idx("Forearm.L")
        hd_i = self.idx("Hand.L")

        sh_pos = wp[ua_i]
        l1 = self.len_uarm_l
        l2 = self.len_farm_l + 0.07  # include palm center beyond wrist
        to_t = vsub(target_pos, sh_pos)
        d = vlen(to_t)
        if d < 1e-4:
            return
        d_c = max(abs(l1 - l2) + 0.05, min((l1 + l2) * 0.99, d))
        dir_t = vnorm(to_t)

        # Natural left-elbow pole: outward left (+X), down (-Y), slightly back (-Z)
        pole = vnorm((0.55, -0.75, -0.25))
        side = vcross(dir_t, pole)
        if vlen(side) < 1e-4:
            side = vcross(dir_t, (0.0, -1.0, 0.0))
        side = vnorm(side)
        bend_dir = vnorm(vcross(side, dir_t))  # points toward pole perpendicular to dir_t

        cos_a = max(-1.0, min(1.0, (l1 * l1 + d_c * d_c - l2 * l2) / (2.0 * l1 * d_c)))
        sin_a = math.sqrt(max(0.0, 1.0 - cos_a * cos_a))
        elbow_pos = vadd(sh_pos, vadd(vscale(dir_t, l1 * cos_a), vscale(bend_dir, l1 * sin_a)))

        # Aim UpperArm.L bone vector (from UpperArm.L -> Forearm.L in current FK) to (elbow_pos - sh_pos)
        cur_ua_vec = vnorm(vsub(wp[fa_i], wp[ua_i]))
        des_ua_vec = vnorm(vsub(elbow_pos, sh_pos))
        q_ua_delta = qfrom_to(cur_ua_vec, des_ua_vec)
        ua_parent = self.parent[ua_i]
        lr[ua_i] = self.abs_local("UpperArm.L", wr[ua_parent], qnorm(qmul(q_ua_delta, wr[ua_i])))

        # Re-evaluate FK to get updated Forearm.L world frame, then aim Forearm.L -> Hand.L to target_pos
        wp, wr = self.fk(lr, lt)
        cur_fa_vec = vnorm(vsub(wp[hd_i], wp[fa_i]))
        des_fa_vec = vnorm(vsub(target_pos, wp[fa_i]))
        q_fa_delta = qfrom_to(cur_fa_vec, des_fa_vec)
        lr[fa_i] = self.abs_local("Forearm.L", wr[ua_i], qnorm(qmul(q_fa_delta, wr[fa_i])))

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
        # Replace existing clip with same prefix if present
        base_prefix = clip_name.replace("_" + HERO_RIG_SUFFIX[self.hero_key], "")
        replaced = False
        for idx, an in enumerate(anims):
            nm = an["name"]
            if nm == clip_name or nm == base_prefix or nm.startswith(base_prefix + "_"):
                anims[idx] = new_anim
                replaced = True
                break
        if not replaced:
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
    """Distinct Shadow Fight 4 combat idle base pose for each hero."""
    if hk == "wuYong":  # Shogun: low wide chudan-no-kamae samurai stance
        return dict(hip_h=0.88, lean=7, twist=-14, stance=0.78, wf=0.50, front_leg="L",
                    r_arm=(-48, 12, -10), r_elbow=(-36, 0, 0), blade_angle=32, blade_yaw=4,
                    two_handed=True, haft_offset=-0.10, cape_pitch=10)
    if hk == "xuXiao":  # Grand Inquisitor: upright commanding knight guard
        return dict(hip_h=0.92, lean=4, twist=-10, stance=0.72, wf=0.48, front_leg="L",
                    r_arm=(-44, 10, -8), r_elbow=(-38, 0, 0), blade_angle=44, blade_yaw=6,
                    two_handed=True, haft_offset=-0.08, cape_pitch=8)
    if hk == "liuQuanwei":  # Nonna: wide heavy berserker great-axe stance
        return dict(hip_h=0.86, lean=9, twist=-18, stance=0.84, wf=0.50, front_leg="L",
                    r_arm=(-34, 8, -14), r_elbow=(-32, 0, 0), blade_angle=52, blade_yaw=6,
                    two_handed=True, haft_offset=-0.06, cape_pitch=12)
    # sunDeng: Midnight — deep crouched agile dual-ninjato assassin stance
    return dict(hip_h=0.79, lean=20, twist=-14, stance=0.90, wf=0.55, front_leg="L",
                r_arm=(-38, 12, -16), r_elbow=(-46, 0, 0), blade_angle=16, blade_yaw=10,
                two_handed=False,
                l_arm=(-50, -14, 14), l_elbow=(-48, 0, 0), blade_l_angle=42, blade_l_yaw=-14,
                cape_pitch=16)


def merge(base, **kw):
    d = dict(base)
    d.update(kw)
    return d


def build_hero_clips(hk):
    """Return dict of clip_base_name -> (game_move_for_timing_or_frames, keyframes_builder).
    Each keyframes_builder(p_su, p_act, p_end) returns [(frac, pose_dict, ease_mode), ...]
    with explosive weapon/kick strike peak nailed directly at p_act = (startup + active/2)/(total-1)!"""
    st = hero_stance(hk)
    is_dual = (hk == "sunDeng")
    two_h = not is_dual
    h_off = -0.06 if hk == "liuQuanwei" else (-0.08 if hk == "xuXiao" else -0.10)

    clips = {}

    # 1. Idle (60f, 1.5s loop): living martial breathing sway
    clips["idle"] = (90, lambda *_: [
        (0.00, st, "inout"),
        (0.50, merge(st, hip_h=st["hip_h"] - 0.025, lean=st["lean"] + 2.5,
                     blade_angle=st["blade_angle"] - 4.0, cape_pitch=st["cape_pitch"] + 4), "inout"),
        (1.00, st, "inout"),
    ])

    # 2. Guard (30f): crisp high diagonal parry posture
    if is_dual:
        gd = merge(st, hip_h=0.78, lean=12, twist=-18, stance=0.84, wf=0.42,
                   r_arm=(-78, 22, -12), r_elbow=(-60, 0, 0), blade_angle=75, blade_yaw=22,
                   l_arm=(-82, -24, 12), l_elbow=(-58, 0, 0), blade_l_angle=105, blade_l_yaw=-22)
    else:
        gd = merge(st, hip_h=st["hip_h"] - 0.02, lean=2, twist=-22, stance=st["stance"] + 0.06, wf=0.40,
                   r_arm=(-78, 28, -14), r_elbow=(-55, 0, 0), blade_angle=86, blade_yaw=24,
                   two_handed=True, haft_offset=h_off)
    clips["guard"] = (30, lambda *_: [
        (0.00, gd, "inout"),
        (0.50, merge(gd, hip_h=gd["hip_h"] - 0.015, blade_angle=gd["blade_angle"] + 3), "inout"),
        (1.00, gd, "inout"),
    ])

    # 3. Walk & Backstep (44f seamless athletic martial stride loops)
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

    # 4. JAB (`light1`): hero-authentic fast primary strike!
    if hk == "wuYong":
        clips["light1"] = ("jab", lambda su, ac: [
            (0.00, st, "inout"),
            (su, merge(st, hip_h=0.88, lean=-4, twist=-38, stance=0.72, wf=0.38,
                       r_arm=(-118, -18, -14), r_elbow=(-42, 0, 0), blade_angle=135, blade_yaw=-14,
                       two_handed=True, haft_offset=h_off, cape_pitch=4), "out"),
            (ac, merge(st, hip_h=0.85, lean=12, twist=28, stance=0.88, wf=0.63,
                       r_arm=(-82, 24, -8), r_elbow=(-10, 0, 0), blade_angle=5, blade_yaw=14,
                       two_handed=True, haft_offset=h_off, cape_pitch=26), "whip"),
            (min(0.84, ac + 0.24), merge(st, hip_h=0.86, lean=9, twist=32, stance=0.84, wf=0.58,
                       r_arm=(-52, 28, -6), r_elbow=(-18, 0, 0), blade_angle=-24, blade_yaw=20,
                       two_handed=True, haft_offset=h_off, cape_pitch=20), "out"),
            (1.00, st, "inout"),
        ])
    elif hk == "xuXiao":
        clips["light1"] = ("jab", lambda su, ac: [
            (0.00, st, "inout"),
            (su, merge(st, hip_h=0.92, lean=-3, twist=-30, stance=0.72, wf=0.42,
                       r_arm=(-128, -12, -10), r_elbow=(-36, 0, 0), blade_angle=122, blade_yaw=-10,
                       two_handed=True, haft_offset=h_off, cape_pitch=4), "out"),
            (ac, merge(st, hip_h=0.88, lean=10, twist=22, stance=0.82, wf=0.60,
                       r_arm=(-76, 18, -6), r_elbow=(-12, 0, 0), blade_angle=-10, blade_yaw=12,
                       two_handed=True, haft_offset=h_off, cape_pitch=24), "whip"),
            (min(0.84, ac + 0.24), merge(st, hip_h=0.89, lean=8, twist=24, stance=0.78, wf=0.55,
                       r_arm=(-48, 22, -6), r_elbow=(-18, 0, 0), blade_angle=-30, blade_yaw=16,
                       two_handed=True, haft_offset=h_off, cape_pitch=18), "out"),
            (1.00, st, "inout"),
        ])
    elif hk == "liuQuanwei":
        clips["light1"] = ("jab", lambda su, ac: [
            (0.00, st, "inout"),
            (su, merge(st, hip_h=0.87, lean=-5, twist=-50, stance=0.86, wf=0.35,
                       r_arm=(-88, -36, -24), r_elbow=(-32, 0, 0), blade_angle=168, blade_yaw=-28,
                       two_handed=True, haft_offset=h_off, cape_pitch=4), "out"),
            (ac, merge(st, hip_h=0.84, lean=13, twist=36, stance=0.94, wf=0.63,
                       r_arm=(-80, 32, -10), r_elbow=(-10, 0, 0), blade_angle=5, blade_yaw=22,
                       two_handed=True, haft_offset=h_off, cape_pitch=28), "whip"),
            (min(0.84, ac + 0.24), merge(st, hip_h=0.85, lean=10, twist=38, stance=0.90, wf=0.58,
                       r_arm=(-48, 36, -8), r_elbow=(-16, 0, 0), blade_angle=-28, blade_yaw=26,
                       two_handed=True, haft_offset=h_off, cape_pitch=22), "out"),
            (1.00, st, "inout"),
        ])
    else:  # sunDeng: fast crouched dual-blade cross scissor!
        clips["light1"] = ("jab", lambda su, ac: [
            (0.00, st, "inout"),
            (su, merge(st, hip_h=0.78, lean=16, twist=-32, stance=0.92, wf=0.45,
                       r_arm=(-108, -24, -18), r_elbow=(-44, 0, 0), blade_angle=158, blade_yaw=-20,
                       l_arm=(-64, 12, 18), l_elbow=(-46, 0, 0), blade_l_angle=195, blade_l_yaw=16,
                       cape_pitch=14), "out"),
            (ac, merge(st, hip_h=0.75, lean=22, twist=28, stance=1.02, wf=0.66,
                       r_arm=(-86, 26, -8), r_elbow=(-12, 0, 0), blade_angle=10, blade_yaw=18,
                       l_arm=(-74, -22, 12), l_elbow=(-16, 0, 0), blade_l_angle=-20, blade_l_yaw=-18,
                       cape_pitch=32), "whip"),
            (min(0.84, ac + 0.24), merge(st, hip_h=0.77, lean=20, twist=22, stance=0.96, wf=0.58,
                       r_arm=(-48, 32, -8), r_elbow=(-24, 0, 0), blade_angle=-38, blade_yaw=24,
                       l_arm=(-44, -28, 12), l_elbow=(-24, 0, 0), blade_l_angle=-65, blade_l_yaw=-22,
                       cape_pitch=24), "out"),
            (1.00, st, "inout"),
        ])

    # 5. CROSS (`light2` — NEW dedicated 2nd combo strike! Reverse rising/backhand slash)
    if is_dual:
        clips["light2"] = ("cross", lambda su, ac: [
            (0.00, st, "inout"),
            (su, merge(st, hip_h=0.76, lean=22, twist=32, stance=0.94, wf=0.56,
                       r_arm=(-45, 34, -10), r_elbow=(-36, 0, 0), blade_angle=-42, blade_yaw=28,
                       l_arm=(-114, 18, 18), l_elbow=(-42, 0, 0), blade_l_angle=152, blade_l_yaw=18), "out"),
            (ac, merge(st, hip_h=0.74, lean=24, twist=-24, stance=1.04, wf=0.68,
                       r_arm=(-88, -22, -16), r_elbow=(-12, 0, 0), blade_angle=22, blade_yaw=-22,
                       l_arm=(-86, -24, 10), l_elbow=(-10, 0, 0), blade_l_angle=-12, blade_l_yaw=-20,
                       cape_pitch=34), "whip"),
            (min(0.84, ac + 0.24), merge(st, hip_h=0.78, lean=18, twist=-18, stance=0.96, wf=0.56,
                       r_arm=(-64, -26, -14), r_elbow=(-26, 0, 0), blade_angle=52, blade_yaw=-20,
                       l_arm=(-52, -18, 14), l_elbow=(-24, 0, 0), blade_l_angle=-48, blade_l_yaw=-16), "out"),
            (1.00, st, "inout"),
        ])
    else:
        clips["light2"] = ("cross", lambda su, ac: [
            (0.00, st, "inout"),
            (su, merge(st, hip_h=st["hip_h"] - 0.04, lean=12, twist=38, stance=st["stance"] + 0.06, wf=0.58,
                       r_arm=(-42, 42, -8), r_elbow=(-24, 0, 0), blade_angle=-35, blade_yaw=34,
                       two_handed=True, haft_offset=h_off), "out"),
            (ac, merge(st, hip_h=st["hip_h"] - 0.02, lean=10, twist=-28, stance=st["stance"] + 0.14, wf=0.64,
                       r_arm=(-92, -26, -14), r_elbow=(-12, 0, 0), blade_angle=24, blade_yaw=-24,
                       two_handed=True, haft_offset=h_off, cape_pitch=28), "whip"),
            (min(0.84, ac + 0.24), merge(st, hip_h=st["hip_h"], lean=6, twist=-22, stance=st["stance"] + 0.08, wf=0.56,
                       r_arm=(-108, -22, -14), r_elbow=(-28, 0, 0), blade_angle=62, blade_yaw=-18,
                       two_handed=True, haft_offset=h_off), "out"),
            (1.00, st, "inout"),
        ])

    # 6. HEAVY (`heavy`): Hero signature high-impact overhead/full-body cleave!
    if hk == "wuYong":  # Shogun: towering overhead Odachi -> horizontal chest lunge cleave -> low follow-through
        clips["heavy"] = ("heavy", lambda su, ac: [
            (0.00, st, "inout"),
            (su, merge(st, hip_h=0.90, lean=-10, twist=-34, stance=0.72, wf=0.30,
                       r_arm=(-152, -12, -10), r_elbow=(-28, 0, 0), blade_angle=150, blade_yaw=-10,
                       two_handed=True, haft_offset=h_off, cape_pitch=-4), "out"),
            (ac, merge(st, hip_h=0.83, lean=16, twist=30, stance=0.94, wf=0.68,
                       r_arm=(-88, 22, -6), r_elbow=(-8, 0, 0), blade_angle=0, blade_yaw=14,
                       two_handed=True, haft_offset=h_off, cape_pitch=34), "whip"),
            (min(0.82, ac + 0.22), merge(st, hip_h=0.81, lean=16, twist=34, stance=0.92, wf=0.62,
                       r_arm=(-46, 26, -6), r_elbow=(-12, 0, 0), blade_angle=-35, blade_yaw=18,
                       two_handed=True, haft_offset=h_off, cape_pitch=28), "out"),
            (1.00, st, "inout"),
        ])
    elif hk == "xuXiao":  # Grand Inquisitor: towering cathedral two-handed overhead execution chop
        clips["heavy"] = ("heavy", lambda su, ac: [
            (0.00, st, "inout"),
            (su, merge(st, hip_h=0.93, lean=-9, twist=-18, stance=0.72, wf=0.30,
                       r_arm=(-162, -6, -6), r_elbow=(-22, 0, 0), blade_angle=160, blade_yaw=-6,
                       two_handed=True, haft_offset=h_off, cape_pitch=-6), "out"),
            (ac, merge(st, hip_h=0.84, lean=18, twist=18, stance=0.96, wf=0.70,
                       r_arm=(-72, 14, -4), r_elbow=(-8, 0, 0), blade_angle=-25, blade_yaw=8,
                       two_handed=True, haft_offset=h_off, cape_pitch=36), "whip"),
            (min(0.82, ac + 0.22), merge(st, hip_h=0.81, lean=20, twist=22, stance=0.95, wf=0.68,
                       r_arm=(-38, 16, -4), r_elbow=(-10, 0, 0), blade_angle=-50, blade_yaw=10,
                       two_handed=True, haft_offset=h_off, cape_pitch=30), "out"),
            (1.00, st, "inout"),
        ])
    elif hk == "liuQuanwei":  # Nonna: brutal full-body rotating overhead-to-floor Great Axe cleave
        clips["heavy"] = ("heavy", lambda su, ac: [
            (0.00, st, "inout"),
            (su, merge(st, hip_h=0.89, lean=-12, twist=-56, stance=0.90, wf=0.25,
                       r_arm=(-144, -26, -18), r_elbow=(-26, 0, 0), blade_angle=145, blade_yaw=-24,
                       two_handed=True, haft_offset=h_off, cape_pitch=-4), "out"),
            (ac, merge(st, hip_h=0.81, lean=18, twist=42, stance=1.06, wf=0.70,
                       r_arm=(-80, 32, -8), r_elbow=(-8, 0, 0), blade_angle=-5, blade_yaw=24,
                       two_handed=True, haft_offset=h_off, cape_pitch=38), "whip"),
            (min(0.82, ac + 0.22), merge(st, hip_h=0.79, lean=22, twist=46, stance=1.02, wf=0.68,
                       r_arm=(-38, 36, -6), r_elbow=(-10, 0, 0), blade_angle=-45, blade_yaw=28,
                       two_handed=True, haft_offset=h_off, cape_pitch=30), "out"),
            (1.00, st, "inout"),
        ])
    else:  # sunDeng: Midnight overhead dual-ninjato X-slash from deep crouch!
        clips["heavy"] = ("heavy", lambda su, ac: [
            (0.00, st, "inout"),
            (su, merge(st, hip_h=0.82, lean=5, twist=-26, stance=0.92, wf=0.36,
                       r_arm=(-136, -28, -22), r_elbow=(-34, 0, 0), blade_angle=150, blade_yaw=-24,
                       l_arm=(-136, 22, 18), l_elbow=(-30, 0, 0), blade_l_angle=130, blade_l_yaw=20,
                       cape_pitch=4), "out"),
            (ac, merge(st, hip_h=0.71, lean=25, twist=16, stance=1.06, wf=0.66,
                       r_arm=(-76, 26, -8), r_elbow=(-10, 0, 0), blade_angle=-30, blade_yaw=24,
                       l_arm=(-82, -26, 8), l_elbow=(-10, 0, 0), blade_l_angle=15, blade_l_yaw=-24,
                       cape_pitch=38), "whip"),
            (min(0.82, ac + 0.22), merge(st, hip_h=0.72, lean=25, twist=18, stance=0.98, wf=0.62,
                       r_arm=(-40, 34, -8), r_elbow=(-14, 0, 0), blade_angle=-60, blade_yaw=30,
                       l_arm=(-44, -34, 8), l_elbow=(-14, 0, 0), blade_l_angle=-78, blade_l_yaw=-30,
                       cape_pitch=32), "out"),
            (1.00, st, "inout"),
        ])

    # 7. FINISHER (`finisher` — NEW 3rd combo hit: explosive lunging knockdown cleave!)
    clips["finisher"] = ("finisher", lambda su, ac: [
        (0.00, st, "inout"),
        (su, merge(st, hip_h=st["hip_h"] - 0.03, lean=-10, twist=-48, stance=st["stance"], wf=0.30,
                   r_arm=(-138, -28, -16), r_elbow=(-32, 0, 0), blade_angle=155, blade_yaw=-22,
                   two_handed=two_h, haft_offset=h_off,
                   l_arm=(-125, 22, 16), l_elbow=(-32, 0, 0), blade_l_angle=140, blade_l_yaw=18), "out"),
        (ac, merge(st, hip_h=st["hip_h"] - 0.08, lean=20, twist=44, stance=st["stance"] + 0.24, wf=0.72,
                   r_arm=(-84, 34, -6), r_elbow=(-8, 0, 0), blade_angle=-12, blade_yaw=24,
                   two_handed=two_h, haft_offset=h_off,
                   l_arm=(-76, -32, 8), l_elbow=(-8, 0, 0), blade_l_angle=18, blade_l_yaw=-22,
                   cape_pitch=38), "whip"),
        (min(0.82, ac + 0.22), merge(st, hip_h=st["hip_h"] - 0.06, lean=18, twist=48, stance=st["stance"] + 0.18, wf=0.64,
                   r_arm=(-44, 38, -6), r_elbow=(-14, 0, 0), blade_angle=-42, blade_yaw=28,
                   two_handed=two_h, haft_offset=h_off,
                   l_arm=(-42, -36, 10), l_elbow=(-16, 0, 0), blade_l_angle=-68, blade_l_yaw=-26), "out"),
        (1.00, st, "inout"),
    ])

    # 8. SKILL1 (`skill1`): Hero-specific!
    if hk == "wuYong":  # Ruthless Advance — ARMORED ADVANCING FRONT KICK (odachi trailing behind!)
        clips["skill1"] = ("skill1", lambda su, ac: [
            (0.00, st, "inout"),
            (su, merge(st, hip_h=0.88, lean=-8, twist=-18, stance=0.80, wf=0.50,
                       kick_leg="L", kick_target=(0.26, 0.62),
                       r_arm=(22, -24, -22), r_elbow=(-28, 0, 0), blade_angle=160, blade_yaw=-16,
                       two_handed=False, l_arm=(-52, 18, 14), l_elbow=(-60, 0, 0), cape_pitch=16), "out"),
            (ac, merge(st, hip_h=0.86, lean=-15, twist=-24, stance=0.82, wf=0.45,
                       kick_leg="L", kick_target=(0.80, 1.00),
                       r_arm=(34, -30, -24), r_elbow=(-18, 0, 0), blade_angle=186, blade_yaw=-20,
                       two_handed=False, l_arm=(-64, 24, 16), l_elbow=(-52, 0, 0), cape_pitch=34), "whip"),
            (min(0.82, ac + 0.24), merge(st, hip_h=0.86, lean=4, twist=-10, stance=0.84, wf=0.60,
                       r_arm=(-18, -14, -14), r_elbow=(-24, 0, 0), blade_angle=142, blade_yaw=-12,
                       two_handed=False, l_arm=(-42, 14, 12), l_elbow=(-40, 0, 0), cape_pitch=22), "out"),
            (1.00, st, "inout"),
        ])
    elif hk == "xuXiao":  # Grand Inquisitor: lunging two-handed Crusader thrust
        clips["skill1"] = ("skill1", lambda su, ac: [
            (0.00, st, "inout"),
            (su, merge(st, hip_h=0.90, lean=-5, twist=-44, stance=0.76, wf=0.30,
                       r_arm=(-42, -32, -14), r_elbow=(-58, 0, 0), blade_angle=175, blade_yaw=-10,
                       two_handed=True, haft_offset=h_off, cape_pitch=4), "out"),
            (ac, merge(st, hip_h=0.84, lean=18, twist=28, stance=1.02, wf=0.74,
                       r_arm=(-92, 16, -4), r_elbow=(-6, 0, 0), blade_angle=0, blade_yaw=4,
                       two_handed=True, haft_offset=h_off, cape_pitch=36), "whip"),
            (min(0.82, ac + 0.22), merge(st, hip_h=0.86, lean=12, twist=22, stance=0.96, wf=0.65,
                       r_arm=(-74, 14, -6), r_elbow=(-16, 0, 0), blade_angle=-10, blade_yaw=6,
                       two_handed=True, haft_offset=h_off, cape_pitch=24), "out"),
            (1.00, st, "inout"),
        ])
    elif hk == "liuQuanwei":  # Nonna: rotating waist-height charging axe swing
        clips["skill1"] = ("skill1", lambda su, ac: [
            (0.00, st, "inout"),
            (su, merge(st, hip_h=0.85, lean=5, twist=-64, stance=0.88, wf=0.35,
                       r_arm=(-58, -42, -26), r_elbow=(-28, 0, 0), blade_angle=186, blade_yaw=-36,
                       two_handed=True, haft_offset=h_off, cape_pitch=6), "out"),
            (ac, merge(st, hip_h=0.82, lean=20, twist=48, stance=1.02, wf=0.70,
                       r_arm=(-82, 36, -10), r_elbow=(-8, 0, 0), blade_angle=0, blade_yaw=32,
                       two_handed=True, haft_offset=h_off, cape_pitch=38), "whip"),
            (min(0.82, ac + 0.22), merge(st, hip_h=0.84, lean=15, twist=52, stance=0.94, wf=0.62,
                       r_arm=(-44, 42, -8), r_elbow=(-14, 0, 0), blade_angle=-56, blade_yaw=34,
                       two_handed=True, haft_offset=h_off, cape_pitch=28), "out"),
            (1.00, st, "inout"),
        ])
    else:  # sunDeng: Midnight low assassin dash twin-blade forward lunge
        clips["skill1"] = ("skill1", lambda su, ac: [
            (0.00, st, "inout"),
            (su, merge(st, hip_h=0.72, lean=28, twist=-18, stance=0.96, wf=0.45,
                       r_arm=(26, -22, -20), r_elbow=(-20, 0, 0), blade_angle=190, blade_yaw=-14,
                       l_arm=(22, 22, 20), l_elbow=(-20, 0, 0), blade_l_angle=198, blade_l_yaw=14,
                       cape_pitch=28), "out"),
            (ac, merge(st, hip_h=0.70, lean=30, twist=14, stance=1.18, wf=0.70,
                       r_arm=(-94, 14, -8), r_elbow=(-8, 0, 0), blade_angle=0, blade_yaw=10,
                       l_arm=(-88, -14, 8), l_elbow=(-10, 0, 0), blade_l_angle=-10, blade_l_yaw=-10,
                       cape_pitch=44), "whip"),
            (min(0.82, ac + 0.22), merge(st, hip_h=0.74, lean=24, twist=16, stance=1.02, wf=0.60,
                       r_arm=(-54, 24, -8), r_elbow=(-22, 0, 0), blade_angle=-30, blade_yaw=18,
                       l_arm=(-48, -24, 8), l_elbow=(-22, 0, 0), blade_l_angle=-44, blade_l_yaw=-18,
                       cape_pitch=30), "out"),
            (1.00, st, "inout"),
        ])

    # 9. WEAPON_UP (`weaponUp` — low rear coil -> explosive rising anti-air cut!)
    clips["weapon_up"] = ("weaponUp", lambda su, ac: [
        (0.00, st, "inout"),
        (su, merge(st, hip_h=st["hip_h"] - 0.10, lean=16 if not is_dual else 24, twist=-32,
                   stance=st["stance"] + 0.08, wf=0.42,
                   r_arm=(16, -24, -14), r_elbow=(-18, 0, 0), blade_angle=-142, blade_yaw=-14,
                   two_handed=two_h, haft_offset=h_off,
                   l_arm=(10, 18, 14), l_elbow=(-22, 0, 0), blade_l_angle=-122, blade_l_yaw=14,
                   cape_pitch=10), "out"),
        (ac, merge(st, hip_h=st["hip_h"] + 0.05, lean=-4 if not is_dual else 0, twist=22,
                   stance=st["stance"] - 0.02, wf=0.58,
                   r_arm=(-132, 14, -8), r_elbow=(-10, 0, 0), blade_angle=72, blade_yaw=10,
                   two_handed=two_h, haft_offset=h_off,
                   l_arm=(-122, -14, 8), l_elbow=(-12, 0, 0), blade_l_angle=62, blade_l_yaw=-10,
                   cape_pitch=28), "whip"),
        (min(0.84, ac + 0.24), merge(st, hip_h=st["hip_h"] + 0.06, lean=-8 if not is_dual else -4, twist=18,
                   stance=st["stance"] - 0.04, wf=0.52,
                   r_arm=(-154, 10, -8), r_elbow=(-18, 0, 0), blade_angle=106, blade_yaw=8,
                   two_handed=two_h, haft_offset=h_off,
                   l_arm=(-146, -10, 8), l_elbow=(-20, 0, 0), blade_l_angle=88, blade_l_yaw=-8,
                   cape_pitch=20), "out"),
        (1.00, st, "inout"),
    ])

    # 10. WEAPON_DOWN (`weaponDown` — deep wide crouch low ankle sweep!)
    clips["weapon_down"] = ("weaponDown", lambda su, ac: [
        (0.00, st, "inout"),
        (su, merge(st, hip_h=st["hip_h"] - 0.08, lean=12 if not is_dual else 20, twist=-44,
                   stance=st["stance"] + 0.14, wf=0.40,
                   r_arm=(-44, -32, -20), r_elbow=(-36, 0, 0), blade_angle=170, blade_yaw=-24,
                   two_handed=two_h, haft_offset=h_off,
                   l_arm=(-38, 22, 16), l_elbow=(-38, 0, 0), blade_l_angle=186, blade_l_yaw=20,
                   cape_pitch=14), "out"),
        (ac, merge(st, hip_h=0.64 if is_dual else 0.70, lean=25 if not is_dual else 30, twist=34,
                   stance=1.18 if is_dual else 1.10, wf=0.66,
                   r_arm=(-54, 28, -10), r_elbow=(-10, 0, 0), blade_angle=-6, blade_yaw=22,
                   two_handed=two_h, haft_offset=h_off,
                   l_arm=(-48, -24, 10), l_elbow=(-12, 0, 0), blade_l_angle=-14, blade_l_yaw=-18,
                   cape_pitch=34), "whip"),
        (min(0.84, ac + 0.24), merge(st, hip_h=0.66 if is_dual else 0.72, lean=20 if not is_dual else 26, twist=36,
                   stance=1.12 if is_dual else 1.04, wf=0.60,
                   r_arm=(-38, 34, -8), r_elbow=(-16, 0, 0), blade_angle=-20, blade_yaw=26,
                   two_handed=two_h, haft_offset=h_off,
                   l_arm=(-34, -28, 10), l_elbow=(-18, 0, 0), blade_l_angle=-28, blade_l_yaw=-22), "out"),
        (1.00, st, "inout"),
    ])

    # 11. WEAPON_FORWARD (`weaponForward` — advancing lunge stab/cleave)
    clips["weapon_forward"] = ("weaponForward", lambda su, ac: [
        (0.00, st, "inout"),
        (su, merge(st, hip_h=st["hip_h"] - 0.04, lean=4, twist=-38, stance=st["stance"] + 0.04, wf=0.34,
                   r_arm=(-36, -26, -16), r_elbow=(-56, 0, 0), blade_angle=166, blade_yaw=-12,
                   two_handed=two_h, haft_offset=h_off,
                   l_arm=(-32, 20, 14), l_elbow=(-52, 0, 0), blade_l_angle=176, blade_l_yaw=12), "out"),
        (ac, merge(st, hip_h=st["hip_h"] - 0.08, lean=18, twist=28, stance=st["stance"] + 0.26, wf=0.72,
                   r_arm=(-92, 18, -6), r_elbow=(-6, 0, 0), blade_angle=2, blade_yaw=8,
                   two_handed=two_h, haft_offset=h_off,
                   l_arm=(-86, -16, 6), l_elbow=(-8, 0, 0), blade_l_angle=-6, blade_l_yaw=-8,
                   cape_pitch=36), "whip"),
        (min(0.84, ac + 0.22), merge(st, hip_h=st["hip_h"] - 0.04, lean=12, twist=20, stance=st["stance"] + 0.14, wf=0.62,
                   r_arm=(-64, 18, -8), r_elbow=(-20, 0, 0), blade_angle=-16, blade_yaw=12,
                   two_handed=two_h, haft_offset=h_off,
                   l_arm=(-56, -16, 8), l_elbow=(-22, 0, 0), blade_l_angle=-24, blade_l_yaw=-12), "out"),
        (1.00, st, "inout"),
    ])

    # 12. WEAPON_BACK (`weaponBack` — crisp counter-step spinning backhand slash)
    clips["weapon_back"] = ("weaponBack", lambda su, ac: [
        (0.00, st, "inout"),
        (su, merge(st, hip_h=st["hip_h"] - 0.04, lean=-6, twist=46, stance=st["stance"] + 0.04, wf=0.35,
                   r_arm=(-56, 46, -12), r_elbow=(-36, 0, 0), blade_angle=142, blade_yaw=40,
                   two_handed=two_h, haft_offset=h_off,
                   l_arm=(-72, 34, 14), l_elbow=(-36, 0, 0), blade_l_angle=155, blade_l_yaw=32), "out"),
        (ac, merge(st, hip_h=st["hip_h"] - 0.05, lean=14, twist=-40, stance=st["stance"] + 0.16, wf=0.62,
                   r_arm=(-86, -34, -14), r_elbow=(-8, 0, 0), blade_angle=6, blade_yaw=-32,
                   two_handed=two_h, haft_offset=h_off,
                   l_arm=(-82, -30, 12), l_elbow=(-10, 0, 0), blade_l_angle=-10, blade_l_yaw=-28,
                   cape_pitch=34), "whip"),
        (min(0.84, ac + 0.22), merge(st, hip_h=st["hip_h"] - 0.02, lean=8, twist=-30, stance=st["stance"] + 0.08, wf=0.54,
                   r_arm=(-64, -36, -14), r_elbow=(-24, 0, 0), blade_angle=34, blade_yaw=-28,
                   two_handed=two_h, haft_offset=h_off,
                   l_arm=(-52, -24, 14), l_elbow=(-24, 0, 0), blade_l_angle=-36, blade_l_yaw=-22), "out"),
        (1.00, st, "inout"),
    ])

    # 13. KICKS (`kick`, `kick_forward`, `kick_up`, `kick_down`, `kick_back`) — foot peaks AT Active Hit!
    if is_dual:
        k_arm_su = dict(r_arm=(-54, 10, -24), r_elbow=(-46, 0, 0), blade_angle=120, blade_yaw=-14,
                        l_arm=(-60, -14, 22), l_elbow=(-42, 0, 0), blade_l_angle=60, blade_l_yaw=14)
        k_arm_ac = dict(r_arm=(12, -24, -28), r_elbow=(-36, 0, 0), blade_angle=160, blade_yaw=-22,
                        l_arm=(-56, -18, 22), l_elbow=(-44, 0, 0), blade_l_angle=32, blade_l_yaw=16)
    else:
        ang_k = 100 if hk == "xuXiao" else (92 if hk == "liuQuanwei" else 108)
        k_arm_su = dict(r_arm=(-48, 12, -10), r_elbow=(-38, 0, 0), blade_angle=ang_k - 8, blade_yaw=12,
                        two_handed=True, haft_offset=h_off)
        k_arm_ac = dict(r_arm=(-52, 10, -12), r_elbow=(-42, 0, 0), blade_angle=ang_k, blade_yaw=14,
                        two_handed=True, haft_offset=h_off)

    k_h = 0.96 if hk == "wuYong" else (0.90 if hk == "xuXiao" else (0.86 if hk == "liuQuanwei" else 1.04))
    clips["kick"] = ("kick", lambda su, ac: [
        (0.00, st, "inout"),
        (su, merge(st, hip_h=st["hip_h"] - 0.02, lean=-5 if not is_dual else 0, twist=-14,
                   kick_leg="L", kick_target=(0.22, 0.56), **k_arm_su), "out"),
        (ac, merge(st, hip_h=st["hip_h"] - 0.03, lean=-15 if not is_dual else -18, twist=-20,
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

    # 14. THROW (`throw` — close judo shoulder-throw peaking inside active window!)
    clips["throw"] = ("throwForward", lambda su, ac: [
        (0.00, st, "inout"),
        (su, merge(st, hip_h=0.74, lean=20, twist=-24, stance=0.90, wf=0.62,
                   r_arm=(-96, 18, -10), r_elbow=(-36, 0, 0), blade_angle=112,
                   two_handed=False, l_arm=(-92, -18, 10), l_elbow=(-38, 0, 0)), "out"),
        (ac, merge(st, hip_h=0.80, lean=28, twist=46, stance=1.02, wf=0.70,
                   r_arm=(-44, 38, -8), r_elbow=(-14, 0, 0), blade_angle=-28,
                   two_handed=False, l_arm=(-48, 32, 12), l_elbow=(-18, 0, 0), cape_pitch=36), "whip"),
        (min(0.84, ac + 0.24), merge(st, hip_h=0.84, lean=16, twist=28, stance=0.92, wf=0.58), "out"),
        (1.00, st, "inout"),
    ])

    # 15. SKILL2 (`skill2` — dedicated command/summon/special strike clip)
    clips["skill2"] = ("skill2", lambda su, ac: [
        (0.00, st, "inout"),
        (su, merge(st, hip_h=st["hip_h"] + 0.02, lean=-8, twist=-26, stance=st["stance"], wf=0.40,
                   r_arm=(-136, -12, -12), r_elbow=(-28, 0, 0), blade_angle=138,
                   two_handed=two_h, haft_offset=h_off,
                   l_arm=(-118, -10, 14), l_elbow=(-26, 0, 0), blade_l_angle=125), "out"),
        (ac, merge(st, hip_h=st["hip_h"] - 0.06, lean=18, twist=32, stance=st["stance"] + 0.22, wf=0.68,
                   r_arm=(-86, 26, -6), r_elbow=(-8, 0, 0), blade_angle=-8, blade_yaw=16,
                   two_handed=two_h, haft_offset=h_off,
                   l_arm=(-84, -22, 8), l_elbow=(-8, 0, 0), blade_l_angle=-12, blade_l_yaw=-16,
                   cape_pitch=36), "whip"),
        (min(0.84, ac + 0.24), merge(st, hip_h=st["hip_h"] - 0.02, lean=12, twist=22, stance=st["stance"] + 0.12, wf=0.58), "out"),
        (1.00, st, "inout"),
    ])

    # 16. HERO SIGNATURE SHADOW MOVES (eliminates fallback to heavy/weapon_up!)
    if hk == "wuYong":
        clips["shogun_fierce"] = ("shogunFierceReprisal", lambda su, ac: [
            (0.00, st, "inout"),
            (su, merge(st, hip_h=0.94, lean=-14, twist=-38, stance=0.76, wf=0.28,
                       r_arm=(-162, -16, -10), r_elbow=(-20, 0, 0), blade_angle=158, blade_yaw=-12,
                       two_handed=True, haft_offset=h_off, cape_pitch=-8), "out"),
            (ac, merge(st, hip_h=0.76, lean=22, twist=38, stance=1.08, wf=0.74,
                       r_arm=(-76, 26, -6), r_elbow=(-6, 0, 0), blade_angle=-18, blade_yaw=18,
                       two_handed=True, haft_offset=h_off, cape_pitch=42), "whip"),
            (min(0.82, ac + 0.24), merge(st, hip_h=0.78, lean=20, twist=42, stance=1.02, wf=0.66,
                       r_arm=(-38, 32, -6), r_elbow=(-12, 0, 0), blade_angle=-48, blade_yaw=22,
                       two_handed=True, haft_offset=h_off, cape_pitch=34), "out"),
            (1.00, st, "inout"),
        ])
        clips["shogun_despotism"] = ("shogunDespotism", lambda su, ac: [
            (0.00, st, "inout"),
            (su, merge(st, hip_h=0.76, lean=16, twist=-48, stance=0.94, wf=0.36,
                       r_arm=(18, -32, -18), r_elbow=(-22, 0, 0), blade_angle=-148, blade_yaw=-24,
                       two_handed=True, haft_offset=h_off, cape_pitch=16), "out"),
            (ac, merge(st, hip_h=0.92, lean=-6, twist=34, stance=0.96, wf=0.66,
                       r_arm=(-126, 22, -8), r_elbow=(-8, 0, 0), blade_angle=52, blade_yaw=20,
                       two_handed=True, haft_offset=h_off, cape_pitch=40), "whip"),
            (min(0.82, ac + 0.24), merge(st, hip_h=0.90, lean=-4, twist=28, stance=0.90, wf=0.58,
                       r_arm=(-144, 18, -8), r_elbow=(-18, 0, 0), blade_angle=96, blade_yaw=16,
                       two_handed=True, haft_offset=h_off), "out"),
            (1.00, st, "inout"),
        ])
    elif hk == "xuXiao":
        clips["inquisitor_spin"] = ("inquisitorLightSpin", lambda su, ac: [
            (0.00, st, "inout"),
            (su, merge(st, hip_h=0.88, lean=4, twist=-62, stance=0.86, wf=0.34,
                       r_arm=(-94, -44, -20), r_elbow=(-16, 0, 0), blade_angle=165, blade_yaw=-36,
                       two_handed=True, haft_offset=h_off, cape_pitch=14), "out"),
            (ac, merge(st, hip_h=0.84, lean=18, twist=56, stance=1.04, wf=0.70,
                       r_arm=(-88, 38, -8), r_elbow=(-6, 0, 0), blade_angle=-6, blade_yaw=34,
                       two_handed=True, haft_offset=h_off, cape_pitch=44), "whip"),
            (min(0.82, ac + 0.24), merge(st, hip_h=0.86, lean=14, twist=42, stance=0.96, wf=0.62,
                       r_arm=(-54, 42, -8), r_elbow=(-14, 0, 0), blade_angle=-36, blade_yaw=32,
                       two_handed=True, haft_offset=h_off, cape_pitch=32), "out"),
            (1.00, st, "inout"),
        ])
    elif hk == "sunDeng":
        clips["midnight_removal"] = ("midnightRemoval", lambda su, ac: [
            (0.00, st, "inout"),
            (su, merge(st, hip_h=0.74, lean=18, twist=-32, stance=0.96, wf=0.38,
                       r_arm=(-140, -28, -18), r_elbow=(-24, 0, 0), blade_angle=155, blade_yaw=-24,
                       l_arm=(-136, 28, 18), l_elbow=(-24, 0, 0), blade_l_angle=142, blade_l_yaw=24,
                       cape_pitch=18), "out"),
            (ac, merge(st, hip_h=0.68, lean=28, twist=24, stance=1.18, wf=0.72,
                       r_arm=(-82, 34, -8), r_elbow=(-6, 0, 0), blade_angle=-28, blade_yaw=30,
                       l_arm=(-86, -34, 8), l_elbow=(-6, 0, 0), blade_l_angle=22, blade_l_yaw=-30,
                       cape_pitch=46), "whip"),
            (min(0.82, ac + 0.24), merge(st, hip_h=0.72, lean=24, twist=18, stance=1.04, wf=0.62,
                       r_arm=(-38, 42, -10), r_elbow=(-14, 0, 0), blade_angle=-64, blade_yaw=36,
                       l_arm=(-42, -42, 10), l_elbow=(-14, 0, 0), blade_l_angle=-76, blade_l_yaw=-36,
                       cape_pitch=34), "out"),
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
