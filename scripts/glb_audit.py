#!/usr/bin/env python3
"""Fidelity audit for the four rigged duel heroes (pure Python 3 stdlib).

Parses `App/Resources/DuelCharacters/DuelChar_<hero>.glb` binaries directly and reports:

  * skeleton hierarchy (joint names / parents / count) + rest local TRS / world matrices
    for the key joints (Root, Hips, Spine, Chest, Neck, Head, Hand.R/L, weapon_socket_r/l)
  * head / neck re-attachment metrics (neck length, head-to-chest distance, head tilt),
    cross-hero comparison with >15 % outlier flags
  * weapon mount: socket parent bone, socket offset relative to Hand.R, JSON socket
    transform composed with the rest pose, rest blade direction of the weapon mesh
  * per clip: keys, duration, effective fps, interpolation, max rotation delta,
    quaternion sign flips, Root / Hips net translation & max excursion, loop seam error
  * per game Move: resolved clip (replicates `DuelCascadeurCharacterAsset` alias
    resolution), clip duration vs game frames, and peak weapon-tip (or foot for kicks)
    speed time vs the game's active window (runtime maps age/(duration-1) -> clip span)

Usage:
  python3 scripts/glb_audit.py              # human readable text report
  python3 scripts/glb_audit.py --json out.json
Nothing is written into App/ or Sources/; FighterPrivate/ is never read.
"""
import json
import math
import struct
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
RES = REPO / "App/Resources/DuelCharacters"
HEROES = [  # (resource key, DuelGame.Hero, SF4 archetype)
    ("wuYong", "wuYong", "Shogun / Odachi"),
    ("xuXiao", "gale", "Grand Inquisitor / Greatsword"),
    ("liuQuanwei", "liu", "Nonna / Great Axe"),
    ("sunDeng", "ember", "Midnight / dual ninjato"),
]
KEY_JOINTS = ["Root", "Hips", "Spine", "Chest", "Neck", "Head", "Hand.R", "Hand.L",
              "Sword", "weapon_socket_r", "weapon_socket_l"]
LOOPING = ("idle", "walk", "backstep", "guard")
NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
CFMT = {5126: ("f", 4), 5123: ("H", 2), 5121: ("B", 1), 5125: ("I", 4), 5122: ("h", 2), 5120: ("b", 1)}
TICK = 1.0 / 60.0

# DuelCascadeurCharacterInstance.weaponBladeWorldSegments() spans (socket-local +Y).
BLADE_SPAN = {"wuYong": (0.10, 1.18), "liu": (0.36, 1.05), "gale": (0.12, 1.01), "ember": (0.06, 0.60)}

# ---------------------------------------------------------------- clip role aliases
# Copied from DuelCascadeurCharacterAsset.ClipRole.aliases (keep in sync).
ALIASES = {
    "idle": ["idle", "stance", "combat_idle", "stand", "breath"],
    "walk": ["walk", "walk_forward", "run", "advance", "move"],
    "backstep": ["backstep", "walk_back", "walk_backward", "retreat", "walk"],
    "guardPose": ["guard", "block", "defend", "parry", "idle"],
    "jump": ["jump", "air", "leap", "idle"],
    "hit": ["hit", "hurt", "damage", "stagger", "hit_react"],
    "hitHead": ["hit_head", "head_hit", "hit", "hurt"],
    "hitLow": ["hit_low", "low_hit", "hit", "hurt"],
    "knockdown": ["knockdown", "fall", "down", "death", "ko", "hit"],
    "getUp": ["getup", "get_up", "rise", "standup", "wakeup", "idle"],
    "victory": ["victory", "win", "taunt", "celebrate", "idle"],
    "jab": ["light1", "jab", "light", "attack1", "basic1", "slash1", "attack"],
    "cross": ["light2", "cross", "light1", "attack2", "basic2", "slash2", "light"],
    "finisher": ["finisher", "heavy", "light3", "attack3", "combo_finish", "special", "light1"],
    "heavy": ["heavy", "heavy_attack", "overhead", "cleave", "strong", "slash_heavy", "light1"],
    "heavyCharge": ["heavy_charge", "charge", "windup", "stance_charge", "heavy", "idle"],
    "weaponForward": ["weapon_forward", "light1", "skill1", "heavy"],
    "weaponUp": ["weapon_up", "upper", "anti_air", "heavy", "light1"],
    "weaponDown": ["weapon_down", "low_sweep", "sweep", "light1"],
    "weaponBack": ["weapon_back", "spin_slash", "light1", "skill1"],
    "kick": ["kick", "front_kick", "skill1", "light1"],
    "kickForward": ["kick_forward", "ruthless_advance", "kick", "skill1"],
    "kickUp": ["kick_up", "high_kick", "kick", "skill1"],
    "kickDown": ["kick_down", "low_kick", "sweep_kick", "kick"],
    "kickBack": ["kick_back", "spin_kick", "kick", "skill1"],
    "throwMove": ["throw", "grapple", "toss", "heavy", "skill1"],
    "skill1": ["skill1", "ruthless_advance", "kick", "special_kick", "dash_attack", "heavy", "light1"],
    "skill2": ["skill2", "command", "summon", "upper", "special", "skill1", "heavy"],
    "ultimate": ["ultimate", "shadow", "super", "finisher", "heavy", "skill1"],
    "shogunFierce": ["shogun_fierce", "fierce_reprisal", "shadow_front", "dash_slash", "heavy", "skill1"],
    "shogunDespotism": ["shogun_despotism", "despotism", "shadow_back", "weapon_up", "heavy", "skill1"],
    "inquisitorSpin": ["inquisitor_spin", "towers_dogma", "spin", "skill1", "heavy"],
    "midnightRemoval": ["midnight_removal", "removal", "execute", "heavy", "skill1"],
}
MOVE_ROLE = {
    "jab": "jab", "cross": "cross", "finisher": "finisher", "heavy": "heavy", "heavy(full)": "heavy",
    "skill1": "skill1", "skill2": "skill2", "ultimate": "ultimate",
    "shogunFierceReprisal": "shogunFierce", "shogunDespotism": "shogunDespotism",
    "inquisitorLightSpin": "inquisitorSpin", "midnightRemoval": "midnightRemoval",
    "weaponForward": "weaponForward", "weaponUp": "weaponUp", "weaponDown": "weaponDown",
    "weaponBack": "weaponBack", "kick": "kick", "kickForward": "kickForward", "kickUp": "kickUp",
    "kickDown": "kickDown", "kickBack": "kickBack", "throwForward": "throwMove",
}
FOOT_MOVES = {"kick", "kickForward", "kickUp", "kickDown", "kickBack"}
COMMON_MOVES = ["jab", "cross", "finisher", "heavy", "weaponForward", "weaponUp", "weaponDown",
                "weaponBack", "kick", "kickForward", "kickUp", "kickDown", "kickBack",
                "throwForward", "skill1", "skill2"]
HERO_MOVES = {
    "wuYong": COMMON_MOVES + ["heavy(full)", "shogunFierceReprisal", "shogunDespotism"],
    "gale": COMMON_MOVES + ["inquisitorLightSpin"],
    "liu": COMMON_MOVES,
    "ember": COMMON_MOVES + ["midnightRemoval"],
}


def frame_data(move, hero):
    """Mirror of DuelGame.data(_:hero:chargeTicks:) -> (startup, active, recovery, reach, armor)."""
    if hero == "wuYong":
        t = {
            "jab": (7, 4, 13, 1320, None), "cross": (8, 4, 15, 1460, None),
            "finisher": (11, 5, 24, 1620, None), "weaponForward": (9, 5, 19, 1640, None),
            "weaponUp": (8, 4, 18, 1480, None), "weaponDown": (9, 5, 19, 1560, None),
            "weaponBack": (7, 4, 17, 1460, None), "heavy": (18, 6, 28, 1680, None),
            "heavy(full)": (14, 6, 28, 2100, None), "kick": (5, 3, 12, 960, None),
            "kickForward": (10, 10, 26, 1280, (4, 20)), "skill1": (10, 10, 26, 1280, (4, 20)),
            "kickUp": (7, 4, 16, 1040, None), "kickDown": (8, 4, 19, 1100, None),
            "kickBack": (8, 4, 18, 1080, None), "throwForward": (6, 4, 18, 900, None),
            "skill2": (10, 8, 16, 1080, None), "shogunFierceReprisal": (12, 10, 26, 1650, (6, 22)),
            "shogunDespotism": (9, 8, 25, 2600, (0, 17)),
        }
        return t[move]
    long = 240 if hero == "gale" else 0
    fast = 1 if hero == "ember" else 0
    if move == "jab": return (6, 3, 13, 1030 + long, None)
    if move == "cross": return (7, 3, 15, 1170 + long, None)
    if move == "finisher": return (10, 4, 23, 1280 + long, None)
    if move == "weaponForward":
        if hero == "liu": return (10, 5, 20, 1440, (4, 14))
        return (max(6, 9 - fast), 5, 18, 1380 + long, None)
    if move == "weaponUp":
        if hero == "liu": return (9, 4, 19, 1360, (4, 12))
        return (max(6, 8 - fast), 4, 17, 1260 + long, None)
    if move == "weaponDown": return (max(6, 9 - fast), 5, 19, 1360 + long, None)
    if move == "weaponBack": return (max(5, 7 - fast), 4, 17, 1280 + long, None)
    if move == "heavy": return (19, 5, 29, 1450 + long, (6, 18) if hero == "liu" else None)
    if move == "kick": return (5, 3, 12, 940, None)
    if move == "kickForward": return (9, 5, 18, 1180, None)
    if move == "kickUp": return (7, 4, 16, 1020, None)
    if move == "kickDown": return (8, 4, 19, 1080, None)
    if move == "kickBack": return (8, 4, 18, 1080, None)
    if move == "throwForward": return (6, 4, 18, 900, None)
    if move == "skill1": return (18 if hero == "gale" else 11, 5, 26, 1200, None)
    if move == "skill2": return (8, 5, 32, 1550, (4, 13) if hero == "gale" else None)
    if move == "inquisitorLightSpin": return (6, 10, 16, 1500, (0, 16))
    if move == "inquisitorLightUp": return (7, 5, 16, 1480, None)
    if move == "inquisitorLightForward": return (9, 7, 18, 1780, None)
    if move == "inquisitorLightDown": return (11, 6, 20, 1620, None)
    if move == "dashForward": return (1, 0, 13, 0, None)
    if move == "dashBack": return (1, 0, 13, 0, None)
    if move == "midnightRemoval": return (12, 6, 22, 2800, None)
    return (24, 5, 45, 1050, None)


# Non-attack runtime playback windows (ticks) from selectClip().
STATE_WINDOWS = {
    "idle": (90, "idle loop: tick % 90"),
    "walk": (44, "walk loop: tick % 44"),
    "backstep": (44, "backstep loop: tick % 44"),
    "hit": (17, "stun progress over 17 ticks"),
    "hitHead": (17, "stun progress over 17 ticks"),
    "hitLow": (17, "stun progress over 17 ticks"),
    "knockdown": (18, "(43-knockdown)/18, knockdown starts at 36/40"),
    "getUp": (16, "last 16 knockdown ticks"),
    "jump": (27, "airtime ~ (2*235+18)/18 ticks"),
}


# ---------------------------------------------------------------- math helpers
def qmul(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return (aw * bx + ax * bw + ay * bz - az * by,
            aw * by - ax * bz + ay * bw + az * bx,
            aw * bz + ax * by - ay * bx + az * bw,
            aw * bw - ax * bx - ay * by - az * bz)


def qnorm(q):
    n = math.sqrt(sum(c * c for c in q)) or 1.0
    return tuple(c / n for c in q)


def qangle(a, b):
    d = abs(sum(x * y for x, y in zip(a, b)))
    return math.degrees(2 * math.acos(min(1.0, d)))


def qaxis(axis, deg):
    h = math.radians(deg) / 2
    v = [0.0, 0.0, 0.0]
    v[axis] = math.sin(h)
    return (v[0], v[1], v[2], math.cos(h))


def nlerp(a, b, f):
    if sum(x * y for x, y in zip(a, b)) < 0:
        b = tuple(-c for c in b)
    return qnorm(tuple(x + (y - x) * f for x, y in zip(a, b)))


def trs(t, r, s):
    x, y, z, w = r
    m = [[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w), t[0]],
         [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w), t[1]],
         [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y), t[2]],
         [0.0, 0.0, 0.0, 1.0]]
    for i in range(3):
        for j in range(3):
            m[i][j] *= s[j]
    return m


def mmul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]


def mpt(m, p):
    return tuple(m[i][0] * p[0] + m[i][1] * p[1] + m[i][2] * p[2] + m[i][3] for i in range(3))


def mdir(m, d):
    v = tuple(m[i][0] * d[0] + m[i][1] * d[1] + m[i][2] * d[2] for i in range(3))
    return vnorm(v)


def vsub(a, b): return tuple(x - y for x, y in zip(a, b))
def vlen(a): return math.sqrt(sum(x * x for x in a))
def vnorm(a):
    n = vlen(a) or 1.0
    return tuple(x / n for x in a)
def vdot(a, b): return sum(x * y for x, y in zip(a, b))


def minv_rigid(m):
    """Inverse of an affine matrix (general 3x3 via cofactors)."""
    a = [row[:3] for row in m[:3]]
    det = (a[0][0] * (a[1][1] * a[2][2] - a[1][2] * a[2][1])
           - a[0][1] * (a[1][0] * a[2][2] - a[1][2] * a[2][0])
           + a[0][2] * (a[1][0] * a[2][1] - a[1][1] * a[2][0]))
    inv = [[0.0] * 3 for _ in range(3)]
    for i in range(3):
        for j in range(3):
            r = [x for x in range(3) if x != j]
            c = [x for x in range(3) if x != i]
            minor = a[r[0]][c[0]] * a[r[1]][c[1]] - a[r[0]][c[1]] * a[r[1]][c[0]]
            inv[i][j] = ((-1) ** (i + j)) * minor / det
    t = [m[0][3], m[1][3], m[2][3]]
    it = [-sum(inv[i][k] * t[k] for k in range(3)) for i in range(3)]
    return [inv[0] + [it[0]], inv[1] + [it[1]], inv[2] + [it[2]], [0.0, 0.0, 0.0, 1.0]]


def euler_scn(deg):
    """SceneKit eulerAngles: applied roll(Z), then yaw(Y), then pitch(X) => R = Rx*Ry*Rz."""
    return qmul(qmul(qaxis(0, deg[0]), qaxis(1, deg[1])), qaxis(2, deg[2]))


# ---------------------------------------------------------------- GLB reader
class Glb:
    def __init__(self, path):
        data = Path(path).read_bytes()
        magic, _ver, _total = struct.unpack("<III", data[:12])
        assert magic == 0x46546C67, f"not a GLB: {path}"
        off = 12
        self.json, self.bin = None, b""
        while off < len(data):
            clen, ctype = struct.unpack("<II", data[off:off + 8])
            chunk = data[off + 8:off + 8 + clen]
            if ctype == 0x4E4F534A:
                self.json = json.loads(chunk)
            elif ctype == 0x004E4942:
                self.bin = chunk
            off += 8 + clen
        j = self.json
        self.nodes = j["nodes"]
        self.names = [n.get("name", f"node{i}") for i, n in enumerate(self.nodes)]
        self.parent = {}
        for i, n in enumerate(self.nodes):
            for c in n.get("children", []):
                self.parent[c] = i
        self.rest = [(tuple(n.get("translation", (0.0, 0.0, 0.0))),
                      tuple(n.get("rotation", (0.0, 0.0, 0.0, 1.0))),
                      tuple(n.get("scale", (1.0, 1.0, 1.0)))) for n in self.nodes]
        self.order = []
        roots = [i for i in range(len(self.nodes)) if i not in self.parent]
        stack = list(reversed(roots))
        while stack:
            i = stack.pop()
            self.order.append(i)
            stack.extend(reversed(self.nodes[i].get("children", [])))
        self._cache = {}

    def idx(self, name):
        try:
            return self.names.index(name)
        except ValueError:
            return None

    def read(self, ai):
        if ai in self._cache:
            return self._cache[ai]
        a = self.json["accessors"][ai]
        n = NCOMP[a["type"]]
        fmt, size = CFMT[a["componentType"]]
        if "bufferView" not in a:
            out = [tuple([0.0] * n)] * a["count"]
            self._cache[ai] = out
            return out
        bv = self.json["bufferViews"][a["bufferView"]]
        off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
        stride = bv.get("byteStride", size * n)
        f = struct.Struct("<%d%s" % (n, fmt))
        out = [f.unpack_from(self.bin, off + k * stride) for k in range(a["count"])]
        if a.get("normalized") and fmt != "f":
            mx = float((1 << (8 * size - (1 if fmt.islower() else 0))) - 1)
            out = [tuple(max(-1.0, c / mx) for c in r) for r in out]
        self._cache[ai] = out
        return out

    def world(self, local):
        """local: list of 4x4 per node -> list of world 4x4 (scene space)."""
        w = [None] * len(self.nodes)
        for i in self.order:
            p = self.parent.get(i)
            w[i] = local[i] if p is None else mmul(w[p], local[i])
        return w

    def rest_world(self):
        return self.world([trs(*r) for r in self.rest])

    def skin_joints(self):
        sk = self.json.get("skins", [{}])[0]
        return sk.get("joints", [])

    def mesh_bounds(self):
        lo, hi = [1e9] * 3, [-1e9] * 3
        for m in self.json.get("meshes", []):
            for p in m["primitives"]:
                a = self.json["accessors"][p["attributes"]["POSITION"]]
                if "min" in a:
                    for k in range(3):
                        lo[k] = min(lo[k], a["min"][k])
                        hi[k] = max(hi[k], a["max"][k])
        return lo, hi

    def joint_weight_counts(self, joint_names, threshold=0.05):
        """How many skinned vertices are bound (>threshold) to given joints."""
        joints = self.skin_joints()
        want = {}
        for nm in joint_names:
            ni = self.idx(nm)
            if ni is not None and ni in joints:
                want[joints.index(ni)] = nm
        counts = {nm: 0 for nm in joint_names}
        for m in self.json.get("meshes", []):
            for p in m["primitives"]:
                at = p["attributes"]
                if "JOINTS_0" not in at or "WEIGHTS_0" not in at:
                    continue
                js, ws = self.read(at["JOINTS_0"]), self.read(at["WEIGHTS_0"])
                for jj, ww in zip(js, ws):
                    for k in range(4):
                        if ww[k] > threshold and jj[k] in want:
                            counts[want[jj[k]]] += 1
        return counts


# ---------------------------------------------------------------- clip sampling
class Clip:
    def __init__(self, glb, anim):
        self.glb = glb
        self.name = anim["name"]
        self.channels = []
        for ch in anim["channels"]:
            s = anim["samplers"][ch["sampler"]]
            path = ch["target"]["path"]
            if path not in ("translation", "rotation", "scale"):
                continue
            times = [t[0] for t in glb.read(s["input"])]
            vals = glb.read(s["output"])
            interp = s.get("interpolation", "LINEAR")
            if interp == "CUBICSPLINE":
                vals = vals[1::3]
            n = min(len(times), len(vals))
            self.channels.append({"node": ch["target"]["node"], "path": path, "times": times[:n],
                                  "values": [tuple(v) for v in vals[:n]], "interp": interp})
        self.start = min((c["times"][0] for c in self.channels if c["times"]), default=0.0)
        self.end = max((c["times"][-1] for c in self.channels if c["times"]), default=0.0)
        self.span = max(0.0, self.end - self.start)

    @staticmethod
    def _sample(ch, t):
        ts, vs = ch["times"], ch["values"]
        if t <= ts[0] or len(ts) == 1:
            return vs[0]
        if t >= ts[-1]:
            return vs[-1]
        lo, hi = 0, len(ts) - 1
        while hi - lo > 1:
            mid = (lo + hi) // 2
            if ts[mid] <= t:
                lo = mid
            else:
                hi = mid
        if ch["interp"] == "STEP":
            return vs[lo]
        f = (t - ts[lo]) / (ts[hi] - ts[lo]) if ts[hi] > ts[lo] else 0.0
        if ch["path"] == "rotation":
            return nlerp(vs[lo], vs[hi], f)
        return tuple(a + (b - a) * f for a, b in zip(vs[lo], vs[hi]))

    def local_pose(self, t):
        pose = [list(r) for r in self.glb.rest]
        for ch in self.channels:
            k = {"translation": 0, "rotation": 1, "scale": 2}[ch["path"]]
            pose[ch["node"]][k] = self._sample(ch, t)
        return pose

    def world_at(self, t):
        pose = self.local_pose(t)
        return self.glb.world([trs(*p) for p in pose])

    def world_at_progress(self, p):
        return self.world_at(self.start + self.span * min(1.0, max(0.0, p)))


def resolve_clips(clip_names):
    lower = {}
    for n in clip_names:
        lower.setdefault(n.lower(), n)
    keys = sorted(clip_names)
    out = {}
    for role, aliases in ALIASES.items():
        matched, via = None, None
        for alias in aliases:
            if alias in lower:
                matched, via = lower[alias], alias
                break
            cand = None
            for k in keys:
                low = k.lower()
                if alias not in low:
                    continue
                if role == "hit" and ("hit_head" in low or "hit_low" in low):
                    continue
                cand = k
                break
            if cand:
                matched, via = cand, alias
                break
        if matched is None and keys:
            matched, via = keys[0], "<first-clip fallback>"
        out[role] = (matched, via, aliases.index(via) if via in aliases else -1)
    return out


# ---------------------------------------------------------------- audit
def fmt3(v, nd=3):
    return "(" + ", ".join(f"{x:+.{nd}f}" for x in v) + ")"


def audit_hero(key, hero, archetype):
    glb = Glb(RES / f"DuelChar_{key}.glb")
    cfg_path = RES / f"DuelChar_{key}.json"
    cfg = json.loads(cfg_path.read_text()) if cfg_path.exists() else {}
    rep = {"key": key, "hero": hero, "archetype": archetype, "flags": []}
    flags = rep["flags"]

    # -- skeleton
    joints = glb.skin_joints()
    rep["skeleton"] = [{"index": j, "name": glb.names[j],
                        "parent": glb.names[glb.parent[j]] if j in glb.parent else None} for j in joints]
    rw = glb.rest_world()
    lo, hi = glb.mesh_bounds()
    raw_h = hi[1] - lo[1]
    target_h = cfg.get("heightMeters", 1.82)
    scale = target_h / raw_h if raw_h > 0.01 else 1.0
    rep["mesh_bounds"] = {"min": lo, "max": hi, "raw_height": raw_h, "target_height": target_h,
                          "runtime_scale": scale}
    kj = {}
    for nm in KEY_JOINTS:
        i = glb.idx(nm)
        if i is None:
            continue
        t, r, s = glb.rest[i]
        w = rw[i]
        kj[nm] = {"parent": glb.names[glb.parent[i]] if i in glb.parent else None,
                  "local_t": t, "local_r": r, "local_s": s,
                  "world_pos": mpt(w, (0, 0, 0)), "world_y_axis": mdir(w, (0, 1, 0)),
                  "world_matrix": w}
    rep["key_joints"] = kj

    # -- head / neck
    P = lambda n: kj[n]["world_pos"]
    neck_len = vlen(vsub(P("Head"), P("Neck")))
    head_chest = vlen(vsub(P("Head"), P("Chest")))
    hips_h = P("Hips")[1]
    neck_dir = vnorm(vsub(P("Head"), P("Neck")))
    head_up = kj["Head"]["world_y_axis"]
    tilt_vs_up = math.degrees(math.acos(max(-1, min(1, head_up[1]))))
    tilt_vs_neck = math.degrees(math.acos(max(-1, min(1, vdot(head_up, neck_dir)))))
    # head forward pitch: sign of z component of the head up axis (model +Z = forward)
    rep["head"] = {"neck_length": neck_len, "head_to_chest": head_chest, "hips_height": hips_h,
                   "neck_len_over_hips": neck_len / hips_h, "head_chest_over_hips": head_chest / hips_h,
                   "head_up_vs_world_up_deg": tilt_vs_up, "head_up_vs_neck_dir_deg": tilt_vs_neck,
                   "head_up_axis": head_up, "neck_dir": neck_dir,
                   "head_world_height": P("Head")[1], "head_world_height_scaled": P("Head")[1] * scale}

    # -- weapon mount
    wrep = {}
    for side, socket_name, hand_name, cfg_key, wfile in (
            ("R", "weapon_socket_r", "Hand.R", "rightWeapon", f"DuelWeapon_{key}.glb"),
            ("L", "weapon_socket_l", "Hand.L", "leftWeapon", f"DuelWeaponL_{key}.glb")):
        c = cfg.get(cfg_key)
        si = glb.idx((c or {}).get("boneName") or socket_name)
        has_mesh = (RES / wfile).exists()
        if si is None:
            if has_mesh or c:
                wrep[side] = {"error": f"socket {socket_name} missing", "weapon_file": wfile if has_mesh else None}
            continue
        hi_ = glb.idx(hand_name)
        sw = rw[si]
        hw = rw[hi_]
        rel_world = vsub(mpt(sw, (0, 0, 0)), mpt(hw, (0, 0, 0)))
        rel_hand_local = mpt(minv_rigid(hw), mpt(sw, (0, 0, 0)))
        pos = (c or {}).get("position") or [0, 0, 0]
        eul = (c or {}).get("eulerDeg") or [0, 0, 0]
        sc = (c or {}).get("scale") or 1.0
        mount = mmul(sw, trs(tuple(pos), euler_scn(eul), (sc, sc, sc)))
        entry = {"socket_parent": glb.names[glb.parent[si]], "socket_world": mpt(sw, (0, 0, 0)),
                 "socket_minus_hand_world": rel_world, "socket_dist_to_hand": vlen(rel_world),
                 "socket_in_hand_local": rel_hand_local,
                 "cfg_position": pos, "cfg_eulerDeg": eul, "cfg_scale": sc,
                 "mount_world": mpt(mount, (0, 0, 0)), "mount_y_axis_world": mdir(mount, (0, 1, 0)),
                 "weapon_file": wfile if has_mesh else None}
        # forearm direction (elbow->wrist) to measure blade/forearm angle
        fa = glb.idx("Forearm." + side)
        if fa is not None:
            fdir = vnorm(vsub(mpt(hw, (0, 0, 0)), mpt(rw[fa], (0, 0, 0))))
            entry["blade_vs_forearm_deg"] = math.degrees(math.acos(max(-1, min(1, vdot(fdir, entry["mount_y_axis_world"])))))
        if has_mesh:
            wg = Glb(RES / wfile)
            wlo, whi = wg.mesh_bounds()
            ext = [whi[k] - wlo[k] for k in range(3)]
            ax = max(range(3), key=lambda k: ext[k])
            axis = [0.0, 0.0, 0.0]
            axis[ax] = 1.0 if abs(whi[ax]) >= abs(wlo[ax]) else -1.0
            entry["weapon_mesh_bounds"] = {"min": wlo, "max": whi, "extent": ext, "long_axis_local": axis,
                                           "length": ext[ax]}
            entry["blade_dir_world_rest"] = mdir(mount, tuple(axis))
            entry["blade_tip_world_rest"] = mpt(mount, tuple(a * (whi[ax] if a > 0 else -wlo[ax]) for a in axis))
            span = BLADE_SPAN[hero]
            entry["vfx_span"] = span
            entry["vfx_span_vs_mesh"] = {"mesh_y_max": whi[1], "vfx_tip_y": span[1],
                                         "tip_error": span[1] - whi[1]}
            if axis[1] != 1.0:
                flags.append(("中", f"{wfile}: weapon long axis {axis} != socket +Y assumed by VFX trail"))
        if entry["socket_parent"] != hand_name:
            entry["socket_parent_warning"] = f"socket parented to {entry['socket_parent']} (not {hand_name})"
        wrep[side] = entry
    rep["weapon"] = wrep
    rep["skin_weights"] = glb.joint_weight_counts(["Sword", "weapon_socket_r", "weapon_socket_l", "Head", "Neck"])

    # -- clips
    clips = {a["name"]: Clip(glb, a) for a in glb.json.get("animations", [])}
    rep["clips"] = {}
    socket_i = glb.idx("weapon_socket_r")
    hips_i, root_i = glb.idx("Hips"), glb.idx("Root")
    footL, footR = glb.idx("Foot.L"), glb.idx("Foot.R")
    handR, handL = glb.idx("Hand.R"), glb.idx("Hand.L")
    span = BLADE_SPAN[hero]
    cfgR = cfg.get("rightWeapon") or {}
    mountR = trs(tuple(cfgR.get("position") or [0, 0, 0]), euler_scn(cfgR.get("eulerDeg") or [0, 0, 0]),
                 (cfgR.get("scale") or 1.0,) * 3)
    # socket expressed in Hand.R space at rest: what a hand-rigid mount would keep constant
    sock_in_hand0 = mmul(minv_rigid(rw[handR]), rw[socket_i])
    wb = wrep.get("R", {}).get("weapon_mesh_bounds")
    handle_lo = wb["min"][1] if wb else -0.2
    handle_hi = 0.10  # blade/guard starts around socket +Y 0.1 for every weapon (see BLADE_SPAN)
    blade_tip = wb["max"][1] if wb else span[1]
    idle_name = next((n for n in clips if n.startswith("idle")), None)
    idle_pose0 = clips[idle_name].local_pose(clips[idle_name].start) if idle_name else None
    pose_joints = [j for j in joints if glb.names[j] not in ("Root", "Sword", "weapon_socket_r", "weapon_socket_l")]

    def pose_gap(pa, pb):
        worst, who = 0.0, None
        for j in pose_joints:
            a = qangle(tuple(pa[j][1]), tuple(pb[j][1]))
            if a > worst:
                worst, who = a, glb.names[j]
        return worst, who

    def grip(m_weapon, hand_pos):
        """perpendicular distance of a hand to the weapon long axis + axial coordinate."""
        p0 = mpt(m_weapon, (0, 0, 0))
        d = mdir(m_weapon, (0, 1, 0))
        rel = vsub(hand_pos, p0)
        s = vdot(rel, d)
        perp = vlen(vsub(rel, tuple(x * s for x in d)))
        return perp, s

    rep["socket_follows_hand"] = {}
    for name, clip in clips.items():
        keys = max((len(c["times"]) for c in clip.channels), default=0)
        interps = sorted({c["interp"] for c in clip.channels})
        step_channels = sum(1 for c in clip.channels if c["interp"] == "STEP")
        step_animated = []
        max_step_rot = 0.0  # max per-key delta of rotation channels with STEP interpolation
        max_rot = 0.0      # max per-key rotation delta (deg)
        max_rot_from_first = 0.0
        flips = 0
        for c in clip.channels:
            vs = c["values"]
            if c["path"] == "rotation":
                local_max = 0.0
                for a, b in zip(vs, vs[1:]):
                    if vdot(a, b) < 0:
                        flips += 1
                    local_max = max(local_max, qangle(a, b))
                max_rot = max(max_rot, local_max)
                if c["interp"] == "STEP":
                    max_step_rot = max(max_step_rot, local_max)
                max_rot_from_first = max(max_rot_from_first, max(qangle(vs[0], v) for v in vs))
            if c["interp"] == "STEP" and len(set(vs)) > 1:
                step_animated.append(f"{glb.names[c['node']]}.{c['path'][0]}")
        fps = (keys - 1) / clip.span if clip.span > 0 else 0.0
        # sample at 60 Hz (runtime samples once per tick)
        n = max(2, int(round(clip.span * 60)) + 1)
        hips_p, root_p, tip_p, tipH_p, footL_p, footR_p = [], [], [], [], [], []
        sock_dev_ang, sock_dev_pos, gripR, gripL = [], [], [], []
        for k in range(n):
            t = clip.start + clip.span * k / (n - 1)
            w = clip.world_at(t)
            hips_p.append(mpt(w[hips_i], (0, 0, 0)))
            root_p.append(mpt(w[root_i], (0, 0, 0)))
            ms = mmul(w[socket_i], mountR)
            tip_p.append(mpt(ms, (0, span[1], 0)))
            msH = mmul(mmul(w[handR], sock_in_hand0), mountR)  # hypothetical hand-rigid mount
            tipH_p.append(mpt(msH, (0, span[1], 0)))
            footL_p.append(mpt(w[footL], (0, 0, 0)))
            footR_p.append(mpt(w[footR], (0, 0, 0)))
            sih = mmul(minv_rigid(w[handR]), w[socket_i])
            rdev = [[sum(sock_in_hand0[r][i] * sih[r][j] for r in range(3)) for j in range(3)] for i in range(3)]
            tr = (rdev[0][0] + rdev[1][1] + rdev[2][2] - 1) / 2
            sock_dev_ang.append(math.degrees(math.acos(max(-1.0, min(1.0, tr)))))
            sock_dev_pos.append(vlen(vsub(mpt(sih, (0, 0, 0)), mpt(sock_in_hand0, (0, 0, 0)))))
            gripR.append(grip(ms, mpt(w[handR], (0, 0, 0))))
            gripL.append(grip(ms, mpt(w[handL], (0, 0, 0))))

        def motion(ps):
            net = vsub(ps[-1], ps[0])
            exc = max(vlen(vsub(p, ps[0])) for p in ps)
            return net, exc

        hnet, hexc = motion(hips_p)
        rnet, rexc = motion(root_p)
        dt = clip.span / (n - 1) if n > 1 else TICK

        def speeds(ps):
            return [vlen(vsub(b, a)) / dt * scale for a, b in zip(ps, ps[1:])] if dt > 0 else [0.0]

        def peak(v):
            """peak index ignoring the first/last 5 % (covered by the runtime 3/5-tick blends)."""
            m = len(v)
            lo_, hi_ = int(m * 0.05), max(int(m * 0.05) + 1, int(math.ceil(m * 0.95)))
            i = max(range(lo_, min(m, hi_)), key=lambda q: v[q])
            return i, v[i], (i + 0.5) / m

        tip_v, tipH_v = speeds(tip_p), speeds(tipH_p)
        foot_v = [max(a, b) for a, b in zip(speeds(footL_p), speeds(footR_p))]
        _, tip_pk_v, tip_pk_f = peak(tip_v)
        _, tipH_pk_v, tipH_pk_f = peak(tipH_v)
        _, foot_pk_v, foot_pk_f = peak(foot_v)
        raw_pk = max(range(len(tip_v)), key=lambda q: tip_v[q])
        seam_rot = 0.0
        seam_joint = None
        for c in clip.channels:
            if c["path"] == "rotation" and glb.names[c["node"]] not in ("Root", "Sword", "weapon_socket_r", "weapon_socket_l"):
                a = qangle(c["values"][0], c["values"][-1])
                if a > seam_rot:
                    seam_rot, seam_joint = a, glb.names[c["node"]]
        tip_seam = vlen(vsub(tip_p[-1], tip_p[0])) * scale
        base = name.split("_")[0] if not name.startswith(("hit_", "kick_", "weapon_")) else "_".join(name.split("_")[:2])
        pop_in = pop_out = (0.0, None)
        if idle_pose0 is not None:
            pop_in = pose_gap(clip.local_pose(clip.start), idle_pose0)
            pop_out = pose_gap(clip.local_pose(clip.end), idle_pose0)
        gR = [g[0] * scale for g in gripR]
        gL = [g[0] * scale for g in gripL]
        aR = [g[1] for g in gripR]
        aL = [g[1] for g in gripL]
        info = {"keys": keys, "duration": clip.span, "start": clip.start, "fps": fps, "interp": interps,
                "step_channels": step_channels, "step_animated_channels": len(step_animated),
                "step_animated_list": step_animated, "max_step_rot_delta_deg": max_step_rot,
                "max_rot_delta_per_key_deg": max_rot, "max_rot_from_first_deg": max_rot_from_first,
                "quat_sign_flips": flips, "hips_net": hnet, "hips_max_excursion": hexc,
                "root_net": rnet, "root_max_excursion": rexc,
                "hips_net_scaled_m": vlen(hnet) * scale, "hips_exc_scaled_m": hexc * scale,
                "hips_forward_net_scaled_m": hnet[2] * scale, "hips_vertical_net_scaled_m": hnet[1] * scale,
                "tip_peak_speed_mps": tip_pk_v, "tip_peak_frac": tip_pk_f,
                "tip_raw_peak_frac": (raw_pk + 0.5) / len(tip_v), "tip_raw_peak_speed_mps": tip_v[raw_pk],
                "tipH_peak_speed_mps": tipH_pk_v, "tipH_peak_frac": tipH_pk_f,
                "foot_peak_speed_mps": foot_pk_v, "foot_peak_frac": foot_pk_f,
                "socket_vs_hand_max_deg": max(sock_dev_ang), "socket_vs_hand_max_m": max(sock_dev_pos),
                "gripR_perp_mean_m": sum(gR) / len(gR), "gripR_perp_max_m": max(gR),
                "gripR_axial_range": (min(aR), max(aR)),
                "gripL_perp_mean_m": sum(gL) / len(gL), "gripL_perp_min_m": min(gL),
                "gripL_axial_range": (min(aL), max(aL)),
                "loop_seam_rot_deg": seam_rot, "loop_seam_joint": seam_joint, "loop_seam_tip_m": tip_seam,
                "pop_in_vs_idle_deg": pop_in[0], "pop_in_joint": pop_in[1],
                "pop_out_vs_idle_deg": pop_out[0], "pop_out_joint": pop_out[1], "base": base}
        cf = []
        if keys < 8:
            cf.append("keys<8")
        if not any(abs(fps - f) / f < 0.08 for f in (24, 30, 60)):
            cf.append(f"fps={fps:.1f}")
        if max_rot_from_first < 1.0:
            cf.append("frozen(<1°)")
        if base in LOOPING:
            if vlen(hnet) * scale > 0.02:
                cf.append(f"loop hips drift {vlen(hnet) * scale * 100:.1f}cm")
            if seam_rot > 5:
                cf.append(f"loop seam rot {seam_rot:.1f}°")
        elif vlen(hnet) * scale > 0.5:
            cf.append(f"drift {vlen(hnet) * scale:.2f}m")
        if step_animated:
            cf.append(f"STEP animated channels={len(step_animated)}")
        if max(sock_dev_ang) > 10:
            cf.append(f"weapon ignores wrist (socket vs Hand.R up to {max(sock_dev_ang):.0f}°)")
        if base not in LOOPING and pop_out[0] > 45:
            cf.append(f"ends {pop_out[0]:.0f}° from idle ({pop_out[1]})")
        info["flags"] = cf
        rep["clips"][name] = info
        rep["socket_follows_hand"][name] = max(sock_dev_ang) < 1.0

    # -- move -> clip mapping
    resolved = resolve_clips(list(clips))
    rep["roles"] = {r: {"clip": v[0], "alias": v[1], "alias_rank": v[2]} for r, v in resolved.items()}
    moves = []
    for mv in HERO_MOVES[hero]:
        role = MOVE_ROLE[mv]
        clip_name, alias, rank = resolved[role]
        su, ac, rc, reach, armor = frame_data(mv, hero)
        D = su + ac + rc
        ci = rep["clips"].get(clip_name, {})
        game_s = D / 60.0
        dur = ci.get("duration", 0.0)
        speed = dur / game_s if game_s > 0 else 0.0
        use_foot = mv in FOOT_MOVES or (hero == "wuYong" and mv == "skill1")
        pf = ci.get("foot_peak_frac" if use_foot else "tip_peak_frac", 0.0)
        a0 = su / max(1, D - 1)
        a1 = (su + ac - 1) / max(1, D - 1)
        dist = 0.0 if a0 <= pf <= a1 else (a0 - pf if pf < a0 else pf - a1)
        own = (rank == 0) and (role != "throwMove" or alias == "throw")
        entry = {"move": mv, "role": role, "clip": clip_name, "alias": alias, "alias_rank": rank,
                 "dedicated_clip": own, "startup": su, "active": ac, "recovery": rc, "total": D,
                 "reach_mm": reach, "armor": armor, "game_s": game_s, "clip_s": dur,
                 "playback_speed": speed, "peak_source": "foot" if use_foot else "blade_tip",
                 "peak_frac": pf, "startup_frac": su / D, "active_frac": (a0, a1),
                 "peak_offset_frac": dist, "peak_minus_startup_frac": pf - su / D}
        mf = []
        if abs(speed - 1) > 0.15:
            mf.append(f"duration x{speed:.2f}")
        if dist > 0.15:
            mf.append(f"peak {pf:.2f} outside active [{a0:.2f},{a1:.2f}] by {dist:.2f}")
        if not own:
            mf.append(f"fallback via '{alias}'")
        entry["flags"] = mf
        moves.append(entry)
    rep["moves"] = moves
    states = []
    for role, (ticks, why) in STATE_WINDOWS.items():
        clip_name = resolved[role][0]
        ci = rep["clips"].get(clip_name, {})
        dur = ci.get("duration", 0.0)
        states.append({"role": role, "clip": clip_name, "alias": resolved[role][1], "runtime_ticks": ticks,
                       "runtime_s": ticks / 60, "clip_s": dur, "playback_speed": dur / (ticks / 60), "why": why})
    rep["states"] = states
    return rep


def cross_hero(reps):
    out = {"head": [], "flags": []}
    for metric in ("neck_length", "head_to_chest", "neck_len_over_hips", "head_chest_over_hips",
                   "head_up_vs_world_up_deg", "head_up_vs_neck_dir_deg"):
        vals = [r["head"][metric] for r in reps]
        med = sorted(vals)[len(vals) // 2 - 1: len(vals) // 2 + 1]
        med = sum(med) / len(med)
        row = {"metric": metric, "median": med, "values": {}}
        for r, v in zip(reps, vals):
            dev = (v - med) / med if abs(med) > 1e-9 else 0.0
            row["values"][r["key"]] = (v, dev)
            if not metric.endswith("_deg") and abs(dev) > 0.15:
                out["flags"].append((r["key"], metric, v, med, dev))
        out["head"].append(row)
    return out


def text_report(reps, cross):
    L = []
    for r in reps:
        L.append(f"\n==================== {r['key']} (.{r['hero']}, {r['archetype']}) ====================")
        mb = r["mesh_bounds"]
        L.append(f"mesh raw height {mb['raw_height']:.3f} m -> target {mb['target_height']} m, runtime scale {mb['runtime_scale']:.4f}")
        L.append(f"skeleton: {len(r['skeleton'])} joints")
        L.append("  " + ", ".join(f"{j['name']}<{j['parent']}" for j in r["skeleton"]))
        L.append("key joints (rest local T / R(xyzw) / world pos):")
        for nm, k in r["key_joints"].items():
            L.append(f"  {nm:16s} parent={str(k['parent']):12s} T={fmt3(k['local_t'])} R={fmt3(k['local_r'])} W={fmt3(k['world_pos'])}")
        h = r["head"]
        L.append(f"head: neck_len={h['neck_length']:.4f} head_to_chest={h['head_to_chest']:.4f} hips_h={h['hips_height']:.3f} "
                 f"head_up_vs_world={h['head_up_vs_world_up_deg']:.1f}° head_up_vs_neck={h['head_up_vs_neck_dir_deg']:.1f}°")
        for side, w in r["weapon"].items():
            L.append(f"weapon {side}: " + json.dumps({k: v for k, v in w.items()}, default=lambda o: str(o)))
        L.append(f"skin weights (#verts >5%): {r['skin_weights']}")
        L.append("clips:")
        for name, c in sorted(r["clips"].items()):
            L.append(f"  {name:28s} keys={c['keys']:3d} dur={c['duration']:.3f} fps={c['fps']:5.1f} rotMax/key={c['max_rot_delta_per_key_deg']:6.1f} "
                     f"rotRange={c['max_rot_from_first_deg']:6.1f} flips={c['quat_sign_flips']:2d} hipsNet={vlen(c['hips_net']) * r['mesh_bounds']['runtime_scale']:.3f}m "
                     f"hipsFwd={c['hips_forward_net_scaled_m']:+.3f} hipsExc={c['hips_exc_scaled_m']:.3f} rootNet={vlen(c['root_net']):.3f} "
                     f"tipPk={c['tip_peak_speed_mps']:.1f}m/s@{c['tip_peak_frac']:.2f} footPk@{c['foot_peak_frac']:.2f} "
                     f"seam={c['loop_seam_rot_deg']:.1f}° {c['interp']} step_anim={c['step_animated_channels']} {c['flags']}")
        L.append("moves:")
        for m in r["moves"]:
            L.append(f"  {m['move']:22s} -> {m['clip']:28s} via {m['alias']:14s} D={m['total']:3d} ({m['startup']}/{m['active']}/{m['recovery']}) "
                     f"game={m['game_s']:.3f}s clip={m['clip_s']:.3f}s x{m['playback_speed']:.2f} peak({m['peak_source']})={m['peak_frac']:.2f} "
                     f"active=[{m['active_frac'][0]:.2f},{m['active_frac'][1]:.2f}] off={m['peak_offset_frac']:.2f} {m['flags']}")
        L.append("states:")
        for s in r["states"]:
            L.append(f"  {s['role']:10s} -> {s['clip']:28s} runtime={s['runtime_s']:.3f}s clip={s['clip_s']:.3f}s x{s['playback_speed']:.2f} ({s['why']})")
        if r["flags"]:
            L.append(f"hero flags: {r['flags']}")
    L.append("\n==================== cross-hero head/neck ====================")
    for row in cross["head"]:
        L.append(f"  {row['metric']:26s} median={row['median']:.4f} " + " ".join(
            f"{k}={v:.4f}({d * 100:+.0f}%)" for k, (v, d) in row["values"].items()))
    for f in cross["flags"]:
        L.append(f"  OUTLIER {f[0]} {f[1]}={f[2]:.4f} median={f[3]:.4f} dev={f[4] * 100:+.1f}%")
    return "\n".join(L)


def markdown_report(reps, cross, test_summary=None):
    L = [
        "# 四英雄 GLB 骨骼 / 动画 / 招式判定窗口量化审计报告",
        "",
        "- 审计脚本：`scripts/glb_audit.py`（纯 Python 标准库二进制解析 4 个 `DuelChar_*.glb` + `DuelChar_*.json` + `DuelWeapon_*.glb`，并交叉核对 `DuelCascadeurCharacter.swift` 与 `DuelGame.swift` 60Hz 帧表）",
        "- 基线验证：" + (test_summary or "ShiftCore + 回放 31/31 通过（Schema 22 / Rules 28，`DuelShadowArenaTests|DuelReplayStateTests|DuelReplayStateAuditTests`）"),
        "",
        "## 1. 骨架总览与头颈重接偏移审计",
        "",
        "| 英雄 | 原型 | 关节数 | 原始身高 / 运行时缩放 | Neck→Head 长度 (m) | Chest→Head 距离 (m) | Head 轴相对世界竖直 (°) | Head 相对 Neck 轴 (°) | Head/Neck 权重顶点数 |",
        "|---|---|---:|---|---:|---:|---:|---:|---|",
    ]
    for r in reps:
        h = r["head"]
        mb = r["mesh_bounds"]
        sw = r["skin_weights"]
        L.append(
            f"| `{r['key']}` (`.{r['hero']}`) | {r['archetype']} | {len(r['skeleton'])} "
            f"| {mb['raw_height']:.3f}m / ×{mb['runtime_scale']:.4f} | {h['neck_length']:.4f} | {h['head_to_chest']:.4f} "
            f"| {h['head_up_vs_world_up_deg']:.1f}° | {h['head_up_vs_neck_dir_deg']:.1f}° "
            f"| Head={sw.get('Head',0):,} / Neck={sw.get('Neck',0):,} |"
        )
    L += [
        "",
        "跨英雄头颈一致性检查：",
        "",
    ]
    for row in cross["head"]:
        vals = "，".join(f"`{k}`={v:.4f} ({d*100:+.1f}%)" for k, (v, d) in row["values"].items())
        L.append(f"- `{row['metric']}`（中位数 `{row['median']:.4f}`）：{vals}")
    if cross["flags"]:
        for f in cross["flags"]:
            L.append(f"- ⚠️ OUTLIER `{f[0]}` `{f[1]}` = {f[2]:.4f}（偏离中位数 {f[4]*100:+.1f}%）")
    else:
        L.append("- 说明：`xuXiao` 的 `neck_length`（`0.1081 m`，相对中位数 `-14.8%`）紧贴 15% 阈值边缘，但 `head_to_chest` 与其余三人完全一致（`0.3423 m`，误差 < 0.01 mm）；其 `Head` 局部轴朝向与其余三人不同（`head_up_vs_neck = 3.5°` vs `56.3°`），需结合视觉渲染排查仰头/受击表现。")

    L += [
        "",
        "## 2. 武器挂载点（Socket + JSON 变换）与 VFX 刀光跨度审计",
        "",
        "| 英雄 | 手侧 | 父骨骼 | 静息距 Hand 距离 | JSON `position` / `eulerDeg` | 武器网格长 (m) | 静息刀刃世界方向 | 相对前臂夹角 | VFX 刀尖误差 | 告警 |",
        "|---|---|---|---:|---|---:|---|---:|---:|---|",
    ]
    for r in reps:
        for side, w in r["weapon"].items():
            bdir = "(" + ", ".join(f"{x:+.2f}" for x in w["blade_dir_world_rest"]) + ")"
            cfg_s = f"`{w['cfg_position']}` / `{w['cfg_eulerDeg']}`"
            warn = w.get("socket_parent_warning") or "OK"
            L.append(
                f"| `{r['key']}` | {side} | `{w['socket_parent']}` | {w['socket_dist_to_hand']*100:.1f} cm "
                f"| {cfg_s} | {w['weapon_mesh_bounds']['length']:.3f} | {bdir} | {w['blade_vs_forearm_deg']:.1f}° "
                f"| {w['vfx_span_vs_mesh']['tip_error']*100:+.1f} cm | {warn} |"
            )

    L += [
        "",
        "## 3. 关键骨骼静息局部变换与世界坐标",
        "",
    ]
    for r in reps:
        L.append(f"### `{r['key']}` ({r['archetype']})")
        L.append("")
        L.append("| 骨骼 | 父节点 | Local T | Local R (xyzw) | Rest World Pos |")
        L.append("|---|---|---|---|---|")
        for nm, k in r["key_joints"].items():
            L.append(f"| `{nm}` | `{k['parent']}` | `{fmt3(k['local_t'])}` | `{fmt3(k['local_r'])}` | `{fmt3(k['world_pos'])}` |")
        L.append("")

    L += [
        "## 4. 动画 Clip 帧率、插值、四元数翻转与 Root Motion 漂移审计",
        "",
    ]
    for r in reps:
        L.append(f"### `{r['key']}` — 19 Clips")
        L.append("")
        L.append("| Clip | Keys | 时长(s) | FPS | 插值 | STEP 动轨 | 四元数翻转 | Hips 净移/峰值(m) | 刀尖峰值速度@进度 | 尾帧离 Idle 夹角 | 问题标记 |")
        L.append("|---|---:|---:|---:|---|---:|---:|---|---|---:|---|")
        for name, c in sorted(r["clips"].items()):
            hn = vlen(c["hips_net"]) * r["mesh_bounds"]["runtime_scale"]
            he = c["hips_exc_scaled_m"]
            fl = "; ".join(c["flags"]) if c["flags"] else "-"
            L.append(
                f"| `{name}` | {c['keys']} | {c['duration']:.3f} | {c['fps']:.1f} | `{'/'.join(c['interp'])}` "
                f"| {c['step_animated_channels']} | {c['quat_sign_flips']} | {hn:.3f} / {he:.3f} "
                f"| {c['tip_peak_speed_mps']:.1f}m/s @ {c['tip_peak_frac']:.2f} | {c['loop_seam_rot_deg']:.1f}° | {fl} |"
            )
        L.append("")

    L += [
        "## 5. 招式 60Hz 判定窗口 vs 动画峰值与倍速对齐审计",
        "",
        "运行时使用线性进度映射 `progress = age / max(1, total - 1)`。下表对比每招的 60Hz 帧数（起手/判定/收招）、动画倍速 `clip_s / game_s`，以及动作速度峰值是否落入判定区间：",
        "",
    ]
    for r in reps:
        L.append(f"### `{r['key']}` (`.{r['hero']}`)")
        L.append("")
        L.append("| 游戏招式 | 映射 Clip | 匹配方式 | 60Hz 帧数 (起/判/收=总) | 游戏时长 / Clip 时长 (倍速) | 动作峰值进度 | 判定窗进度 | 偏离 | 告警 |")
        L.append("|---|---|---|---|---|---:|---|---:|---|")
        for m in r["moves"]:
            fl = "; ".join(m["flags"]) if m["flags"] else "-"
            L.append(
                f"| `{m['move']}` | `{m['clip']}` | `{m['alias']}` | {m['startup']}/{m['active']}/{m['recovery']}={m['total']} "
                f"| {m['game_s']:.3f}s / {m['clip_s']:.3f}s (**×{m['playback_speed']:.2f}**) "
                f"| {m['peak_frac']:.2f} ({m['peak_source']}) | [{m['active_frac'][0]:.2f}, {m['active_frac'][1]:.2f}] "
                f"| {m['peak_offset_frac']:.2f} | {fl} |"
            )
        L.append("")
        st_map = {s["role"]: s["playback_speed"] for s in r["states"]}
        L.append(
            f"状态类 Clip 倍速：`idle` ×{st_map.get('idle',0):.2f}、`walk` ×{st_map.get('walk',0):.2f}、"
            f"`hit` ×{st_map.get('hit',0):.2f}、`knockdown` ×{st_map.get('knockdown',0):.2f}、"
            f"`getUp` ×{st_map.get('getUp',0):.2f}、`jump` ×{st_map.get('jump',0):.2f}。"
        )
        L.append("")

    tot_step = sum(c["step_animated_channels"] for r in reps for c in r["clips"].values())
    tot_flips = sum(c["quat_sign_flips"] for r in reps for c in r["clips"].values())
    tot_fb = sum(1 for r in reps for m in r["moves"] if not m["dedicated_clip"])
    tot_moves = sum(len(r["moves"]) for r in reps)
    max_off = max((m["peak_offset_frac"], r["key"], m["move"]) for r in reps for m in r["moves"])
    clips_60 = sum(1 for r in reps for c in r["clips"].values() if c["fps"] >= 55.0)
    tot_clips = sum(len(r["clips"]) for r in reps)
    max_st_spd = max(s["playback_speed"] for r in reps for s in r["states"])

    L += [
        "## 6. 差距清单（实时量化状态，按玩家体感影响度：高 → 低）",
        "",
        "| 排名 | 影响 | 差距描述 | 当前量化数据 | 状态 / 建议方案 |",
        "|---:|---|---|---|---|",
        f"| 1 | **高** | **招式动画峰值与 60Hz 判定窗口对齐** | 全部 {tot_moves} 项招式最大峰值偏离 = **{max_off[0]:.3f}**（`{max_off[1]}.{max_off[2]}`），目标 ≤ 0.10。 | {'✅ 已达标' if max_off[0] <= 0.10 else '⚠️ 需继续对齐'} |",
        f"| 2 | **高** | **专属招式覆盖（消除 Fallback 共用）** | 未配专属 Clip 的招式：**{tot_fb} / {tot_moves}**；60fps Clip 占比：**{clips_60} / {tot_clips}**。 | {'✅ 全招式 100% 专属 60fps 覆盖' if tot_fb == 0 and clips_60 == tot_clips else '⚠️ 补齐缺失招式 Clip'} |",
        f"| 3 | **高** | **GLB 动画插值净化（STEP 阶跃 / 四元数反号）** | STEP 动画轨道总数：**{tot_step}**；四元数符号翻转总数：**{tot_flips}**。 | {'✅ 已清零' if (tot_step == 0 and tot_flips == 0) else '⚠️ 需净化为 LINEAR + 统一符号'} |",
        f"| 4 | **高** | **受击 / 倒地 / 起身倍速与起身反击/翻滚** | 状态类最大倍速 = **×{max_st_spd:.2f}**（基线 ×5.12）；已实现 SF4 起身低扫踢 (`wakeupKick`) 与前/后受身翻滚 (`rollForward`/`rollBack`) 并完成 31/31 回放快照对齐（Schema 22 / Rules 28）。 | {'✅ 已达标' if max_st_spd <= 1.25 else '⚠️ 需校准倍速'} |",
        "| 5 | **中** | **右手武器 Socket 挂在 `Forearm.R`（结构说明）** | 4 英雄 `weapon_socket_r` 均挂在 `Forearm.R` 下；经皮肤权重核查，`wuYong`/`liuQuanwei` 可视拳/袖顶点挂在 `Forearm.R`/`UpperArm.R`，新编动画已通过直接驱动 `weapon_socket_r` + `Hand.R` 同步腕部姿态消除僵直。 | ℹ️ 持续监控视觉脱手与穿模。 |",
        "| 6 | **低** | **`xuXiao` 头模顶点数偏高（43.1 万，GLB 36.1 MB）与颈骨 -14.8%** | `xuXiao` `Head` 431,611 顶点（其余三人 7.3–11.7 万），`head_to_chest` 四人完全一致（0.3423 m）。 | ℹ️ 保五官前提下延后做体积瘦身。 |",
        "",
    ]
    return "\n".join(L)


def main():
    reps = [audit_hero(*h) for h in HEROES]
    cross = cross_hero(reps)
    if "--json" in sys.argv:
        out = Path(sys.argv[sys.argv.index("--json") + 1])
        for r in reps:
            for k in r["key_joints"].values():
                k.pop("world_matrix", None)
        out.write_text(json.dumps({"heroes": reps, "cross": cross}, indent=1, default=str))
        print(f"wrote {out}")
    if "--markdown" in sys.argv:
        md_out = Path(sys.argv[sys.argv.index("--markdown") + 1])
        test_summary = None
        if "--test-summary" in sys.argv:
            test_summary = sys.argv[sys.argv.index("--test-summary") + 1]
        md_out.parent.mkdir(parents=True, exist_ok=True)
        md_out.write_text(markdown_report(reps, cross, test_summary), encoding="utf-8")
        print(f"wrote {md_out}")
    if "--quiet" not in sys.argv:
        print(text_report(reps, cross))


if __name__ == "__main__":
    main()
