#!/usr/bin/env python3
"""Restore frozen 2-keyframe base clips in DuelChar_*.glb by rest-relative retargeting.

wuYong / xuXiao shipped with idle/walk/backstep/guard/light1/heavy/skill1/hit/
knockdown/getup exported as 2-key rest poses (zero motion). All four heroes share
the same 25-joint rig (same names/hierarchy), so we retarget the animated clips
from a donor hero:

  rotation:    q_dst(t) = rest_dst * inv(rest_src) * q_src(t)   (bone-local delta)
  translation: t_dst(t) = rest_dst + (t_src(t) - rest_src) * k  (k = hip-height ratio)
  scale:       unchanged (target keeps its constant scale)

Optional per-hero "style" adds a small bone-local offset curve so each hero reads
differently (Shogun low wide stance, Inquisitor upright heavy guard).

Only animation samplers are rewritten; meshes, skins and materials are untouched.
Usage: retarget_duel_base_clips.py <donor> <target> [<target> ...]
"""
import json
import math
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "App/Resources/DuelCharacters"
BASE_CLIPS = ["idle", "walk", "backstep", "guard", "light1", "heavy", "skill1",
              "hit", "knockdown", "getup"]
NCOMP = {"SCALAR": 1, "VEC3": 3, "VEC4": 4}

# Hero styling: (clip prefix or "*", bone, axis-angle degrees about local X/Y/Z)
STYLE = {
    # Shogun: lower, more forward-weighted samurai stance; a touch more spine coil.
    "wuYong": [
        ("*", "Spine", (4.0, 0.0, 0.0)),
        ("idle", "Thigh.L", (-4.0, 0.0, 0.0)),
        ("idle", "Thigh.R", (-4.0, 0.0, 0.0)),
        ("guard", "Chest", (3.0, -4.0, 0.0)),
    ],
    # Inquisitor: upright knightly carriage, slower heavier chest drive.
    "xuXiao": [
        ("*", "Spine", (-2.0, 0.0, 0.0)),
        ("heavy", "Chest", (-3.0, 0.0, 0.0)),
    ],
}
TIME_SCALE = {"xuXiao": {"heavy": 1.05, "skill1": 1.05}}


def qmul(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return (aw * bx + ax * bw + ay * bz - az * by,
            aw * by - ax * bz + ay * bw + az * bx,
            aw * bz + ax * by - ay * bx + az * bw,
            aw * bw - ax * bx - ay * by - az * bz)


def qinv(q):
    return (-q[0], -q[1], -q[2], q[3])


def qnorm(q):
    n = math.sqrt(sum(c * c for c in q)) or 1.0
    return tuple(c / n for c in q)


def qeuler(deg):
    q = (0.0, 0.0, 0.0, 1.0)
    for axis, d in enumerate(deg):
        if not d:
            continue
        h = math.radians(d) / 2
        v = [0.0, 0.0, 0.0]
        v[axis] = math.sin(h)
        q = qmul(q, (v[0], v[1], v[2], math.cos(h)))
    return q


class Glb:
    def __init__(self, path):
        self.path = path
        data = path.read_bytes()
        jlen = struct.unpack("<I", data[12:16])[0]
        self.json = json.loads(data[20:20 + jlen])
        blen = struct.unpack("<I", data[20 + jlen:24 + jlen])[0]
        self.bin = bytearray(data[28 + jlen:28 + jlen + blen])
        self.names = {i: n.get("name", "") for i, n in enumerate(self.json["nodes"])}

    def read(self, idx):
        a = self.json["accessors"][idx]
        bv = self.json["bufferViews"][a["bufferView"]]
        n = NCOMP[a["type"]]
        off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
        stride = bv.get("byteStride", 4 * n)
        return [struct.unpack_from("<%df" % n, self.bin, off + k * stride)
                for k in range(a["count"])]

    def append(self, rows, typ, with_bounds):
        while len(self.bin) % 4:
            self.bin.append(0)
        off = len(self.bin)
        for r in rows:
            self.bin += struct.pack("<%df" % len(r), *r)
        self.json["bufferViews"].append({"buffer": 0, "byteOffset": off,
                                         "byteLength": len(self.bin) - off})
        acc = {"bufferView": len(self.json["bufferViews"]) - 1, "componentType": 5126,
               "count": len(rows), "type": typ}
        if with_bounds:
            acc["min"] = [min(r[i] for r in rows) for i in range(len(rows[0]))]
            acc["max"] = [max(r[i] for r in rows) for i in range(len(rows[0]))]
        self.json["accessors"].append(acc)
        return len(self.json["accessors"]) - 1

    def rest(self, name):
        for i, n in enumerate(self.json["nodes"]):
            if n.get("name") == name:
                return (tuple(n.get("rotation", (0, 0, 0, 1))),
                        tuple(n.get("translation", (0, 0, 0))))
        return None

    def clip(self, prefix):
        for an in self.json.get("animations", []):
            if an["name"] == prefix or an["name"].startswith(prefix + "_"):
                return an
        return None

    def save(self):
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


def max_keys(glb, an):
    return max(glb.json["accessors"][s["input"]]["count"] for s in an["samplers"])


def retarget(donor, target, hero):
    k = target.rest("Hips")[1][1] / max(donor.rest("Hips")[1][1], 1e-4)
    styles = STYLE.get(hero, [])
    for prefix in BASE_CLIPS:
        dst = target.clip(prefix)
        src = donor.clip(prefix)
        if dst is None or src is None:
            print(f"  skip {prefix}: missing")
            continue
        if max_keys(target, dst) > 2:
            print(f"  keep {dst['name']}: already animated")
            continue
        src_ch = {(donor.names[c["target"]["node"]], c["target"]["path"]): src["samplers"][c["sampler"]]
                  for c in src["channels"]}
        tscale = TIME_SCALE.get(hero, {}).get(prefix, 1.0)
        rewritten = 0
        for ch in dst["channels"]:
            bone = target.names[ch["target"]["node"]]
            path = ch["target"]["path"]
            s_src = src_ch.get((bone, path))
            if s_src is None or path == "scale":
                continue
            times = [(t[0] * tscale,) for t in donor.read(s_src["input"])]
            vals = donor.read(s_src["output"])
            r_src, t_src = donor.rest(bone)
            r_dst, t_dst = target.rest(bone)
            if path == "rotation":
                off = r_dst
                for (clip, sb, deg) in styles:
                    if sb == bone and (clip == "*" or clip == prefix):
                        off = qmul(off, qeuler(deg))
                base = qmul(off, qinv(r_src))
                out, prev = [], None
                for v in vals:
                    q = qnorm(qmul(base, v))
                    if prev is not None and sum(a * b for a, b in zip(q, prev)) < 0:
                        q = tuple(-c for c in q)
                    out.append(q)
                    prev = q
                typ = "VEC4"
            elif path == "translation":
                out = [tuple(td + (v[i] - ts) * k for i, (td, ts) in enumerate(zip(t_dst, t_src)))
                       for v in vals]
                typ = "VEC3"
            else:
                continue
            sampler = dst["samplers"][ch["sampler"]]
            sampler["input"] = target.append(times, "SCALAR", True)
            sampler["output"] = target.append(out, typ, False)
            sampler["interpolation"] = s_src.get("interpolation", "LINEAR")
            rewritten += 1
        print(f"  restored {dst['name']}: {rewritten} channels, {len(times)} keys")


def main():
    donor_name, targets = sys.argv[1], sys.argv[2:]
    donor = Glb(ROOT / f"DuelChar_{donor_name}.glb")
    for hero in targets:
        print(f"== {hero} <- {donor_name}")
        tgt = Glb(ROOT / f"DuelChar_{hero}.glb")
        retarget(donor, tgt, hero)
        tgt.save()


if __name__ == "__main__":
    main()
