"""Blender-side half of the pose-diff tool (run by scripts/render_pose_diff.py).

Usage (normally invoked by the driver):
    blender -b --python scripts/render_pose_diff_bpy.py -- job.json

The job file lists one hero (character GLB, weapon GLBs, socket config) and a list of
shots (clip name + normalized progress).  For each shot this script:
  * poses the rig exactly like the iOS runtime does
    (`DuelCascadeurCharacterInstance.sample`: time = clipStart + (clipEnd - clipStart) * progress),
  * mounts the weapon(s) under the socket node using the JSON position / eulerDeg / scale in
    the glTF node's *local* space (SceneKit `eulerAngles` order: R = Rx * Ry * Rz),
  * applies the runtime height normalization (heightMeters / raw bbox height), the facing yaw
    (+90 deg about the up axis -> fighter faces +X / screen-right) and the sole ground clamp,
  * renders an orthographic, pure side-on Workbench image and
  * writes world-space + pixel keypoints and silhouette metrics to JSON.

It also samples every clip densely (no rendering) so the driver can check whether the
weapon's maximum extension lines up with the gameplay active window.
"""
import bpy
import sys
import json
import math
import struct
import os

import numpy as np
from mathutils import Matrix, Vector, Quaternion
from mathutils.bvhtree import BVHTree

argv = sys.argv[sys.argv.index("--") + 1:]
job = json.load(open(argv[0]))
out_dir = job["out_dir"]
os.makedirs(out_dir, exist_ok=True)

# glTF (x, y, z) Y-up -> Blender (x, -z, y) Z-up.
CONV = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
CONV_INV = CONV.inverted()

RES_X, RES_Y = job.get("res", [504, 384])
ORTHO_W = job.get("ortho_w", 4.2)          # metres across the frame
PX_PER_M = RES_X / ORTHO_W
GROUND_PX_FROM_BOTTOM = job.get("ground_px", 30)
CAM_X_OFFSET = job.get("cam_x_offset", 0.3)  # frame centre = hips.x + offset


# --------------------------------------------------------------------------- glTF helpers
def glb_json(path):
    with open(path, "rb") as f:
        data = f.read()
    clen, = struct.unpack_from("<I", data, 12)
    return json.loads(data[20:20 + clen])


def node_local(n):
    if "matrix" in n:
        m = n["matrix"]
        return Matrix([m[0:4], m[4:8], m[8:12], m[12:16]]).transposed()
    t = Vector(n.get("translation", [0, 0, 0]))
    r = n.get("rotation", [0, 0, 0, 1])
    s = n.get("scale", [1, 1, 1])
    q = Quaternion((r[3], r[0], r[1], r[2]))
    return Matrix.Translation(t) @ q.to_matrix().to_4x4() @ Matrix.Diagonal((s[0], s[1], s[2], 1))


def gltf_rest_worlds(j):
    parent = {}
    for i, n in enumerate(j["nodes"]):
        for c in n.get("children", []):
            parent[c] = i
    cache = {}

    def world(i):
        if i in cache:
            return cache[i]
        m = node_local(j["nodes"][i])
        if i in parent:
            m = world(parent[i]) @ m
        cache[i] = m
        return m
    return {j["nodes"][i].get("name", f"node{i}"): world(i) for i in range(len(j["nodes"]))}


def socket_matrix(cfg):
    """SceneKit node transform from DuelChar_<hero>.json SocketTransform."""
    cfg = cfg or {}
    pos = cfg.get("position") or [0, 0, 0]
    deg = cfg.get("eulerDeg") or [0, 0, 0]
    s = cfg.get("scale") or 1.0
    k = math.pi / 180
    rx = Matrix.Rotation(deg[0] * k, 4, "X")
    ry = Matrix.Rotation(deg[1] * k, 4, "Y")
    rz = Matrix.Rotation(deg[2] * k, 4, "Z")
    # SceneKit applies roll (z) first, then yaw (y), then pitch (x).
    return Matrix.Translation(Vector(pos)) @ rx @ ry @ rz @ Matrix.Diagonal((s, s, s, 1))


# --------------------------------------------------------------------------- scene setup
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.fps = 24

before = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=job["char_glb"], guess_original_bind_pose=False)
char_objs = [o for o in bpy.data.objects if o not in before]
for o in list(char_objs):
    if o.type == "MESH" and o.name.startswith("Icosphere"):
        char_objs.remove(o)
        bpy.data.objects.remove(o, do_unlink=True)
arm = [o for o in char_objs if o.type == "ARMATURE"][0]
meshes = [o for o in char_objs if o.type == "MESH"]
head_keys = ("head", "portrait")
head_mesh = [o for o in meshes if any(k in o.name.lower() for k in head_keys)]
body_meshes = [o for o in meshes if o not in head_mesh]

gj = glb_json(job["char_glb"])
grest = gltf_rest_worlds(gj)
mw0 = arm.matrix_world.copy()
CORR = {}
for b in arm.data.bones:
    if b.name in grest:
        CORR[b.name] = (mw0 @ b.matrix_local).inverted() @ CONV @ grest[b.name]

# Runtime height normalisation (bind-pose bbox of the whole instance, glTF Y extent).
zs = []
for o in meshes:
    for c in o.bound_box:
        zs.append((o.matrix_world @ Vector(c)).z)
raw_h = max(zs) - min(zs)
cfg = json.load(open(job["config"])) if job.get("config") else {}
target_h = cfg.get("heightMeters") or 1.82
if raw_h > 0.01 and (raw_h < 0.7 or raw_h > 3.2 or cfg.get("heightMeters") is not None):
    base_scale = target_h / raw_h
else:
    base_scale = 1.0

root = bpy.data.objects.new("duel_root", None)
sc.collection.objects.link(root)
arm.parent = root
arm.matrix_parent_inverse = Matrix.Identity(4)
root.scale = (base_scale,) * 3
root.rotation_euler = (0, 0, math.radians(90))   # facing +X (screen right)

bpy.context.view_layer.update()


def bone_gltf_world(name):
    """World matrix (Blender space) of the glTF node `name`, in the node's own local axes."""
    pb = arm.pose.bones[name]
    return arm.matrix_world @ pb.matrix @ CORR[name]


# --------------------------------------------------------------------------- weapons
weapons = {}   # side -> dict
for side, key in (("r", "rightWeapon"), ("l", "leftWeapon")):
    path = job.get("weapon_" + side)
    sock_cfg = cfg.get(key)
    if not path or not os.path.exists(path):
        continue
    bone = (sock_cfg or {}).get("boneName") or f"weapon_socket_{side}"
    if bone not in arm.pose.bones:
        print("WARN socket bone missing", bone)
        continue
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    for o in list(new):
        if o.type == "MESH" and o.name.startswith("Icosphere"):
            new.remove(o)
            bpy.data.objects.remove(o, do_unlink=True)
    S = socket_matrix(sock_cfg)
    pb = arm.pose.bones[bone]
    local = Matrix.Translation((0, -pb.bone.length, 0)) @ CORR[bone] @ S @ CONV_INV
    # Weapon vertices expressed in the socket-bone glTF local space (for tip/base extraction).
    pts = []
    for o in new:
        if o.type != "MESH":
            continue
        w0 = o.matrix_world.copy()
        for v in o.data.vertices:
            p = S @ CONV_INV @ (w0 @ v.co)
            pts.append((p.x, p.y, p.z))
    rootobjs = [o for o in new if o.parent is None or o.parent not in new]
    for o in rootobjs:
        basis = o.matrix_world.copy()
        o.parent = arm
        o.parent_type = "BONE"
        o.parent_bone = bone
        o.matrix_parent_inverse = Matrix.Identity(4)
        o.matrix_basis = local @ basis
    P = np.array(pts)
    imax, imin = int(P[:, 1].argmax()), int(P[:, 1].argmin())
    weapons[side] = dict(bone=bone, S=S, tip=Vector(P[imax]), base=Vector(P[imin]),
                         ymin=float(P[:, 1].min()), ymax=float(P[:, 1].max()), objs=new)
bpy.context.view_layer.update()

# --------------------------------------------------------------------------- render setup
sc.render.engine = "BLENDER_WORKBENCH"
sh = sc.display.shading
sh.light = "STUDIO"
sh.color_type = "TEXTURE"
sh.show_object_outline = True
sh.object_outline_color = (0.08, 0.08, 0.08)
sh.show_cavity = False
sc.display.render_aa = "8"
sc.render.resolution_x = RES_X
sc.render.resolution_y = RES_Y
sc.render.resolution_percentage = 100
sc.render.film_transparent = False
sc.render.image_settings.file_format = "PNG"
sc.render.image_settings.color_mode = "RGB"
sc.view_settings.view_transform = "Standard"
w = bpy.data.worlds.new("w")
w.color = (0.62, 0.62, 0.60)
sc.world = w
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
sc.collection.objects.link(cam)
sc.camera = cam
cam.data.type = "ORTHO"
cam.data.ortho_scale = ORTHO_W
cam.data.clip_start = 0.1
cam.data.clip_end = 100
cam.rotation_euler = (math.radians(90), 0, 0)    # looks along +Y: SceneKit side camera at +Z
VIEW_H = RES_Y / PX_PER_M
CAM_Z = VIEW_H / 2 - GROUND_PX_FROM_BOTTOM / PX_PER_M

anim = arm.animation_data or arm.animation_data_create()
for t in anim.nla_tracks:
    t.mute = True
actions = {}
for a in bpy.data.actions:
    nm = a.name
    for suf in ("_" + arm.name + "_" + arm.name, "_" + arm.name):
        if nm.endswith(suf):
            nm = nm[: -len(suf)]
            break
    actions[nm] = a


def set_pose(clip, progress):
    act = actions[clip]
    anim.action = act
    f0, f1 = act.frame_range
    f = f0 + (f1 - f0) * min(1.0, max(0.0, progress))
    root.location = (0, 0, 0)
    sc.frame_set(int(math.floor(f)), subframe=f - math.floor(f))
    bpy.context.view_layer.update()
    # Runtime sole clamp: marker 0.04/baseScale below each foot node (foot-local -Y).
    lows = []
    for fb in ("Foot.L", "Foot.R"):
        m = bone_gltf_world(fb)
        lows.append((m @ Vector((0, -0.04 / base_scale, 0))).z)
    low = min(lows)
    root.location.z = max(-0.25, min(0.5, -0.03 - low))
    bpy.context.view_layer.update()
    return f


def P2(v):
    return [round(v.x, 4), round(v.z, 4)]


def keypoints():
    k = {}
    for nm, bone in (("neck", "Neck"), ("head_joint", "Head"), ("chest", "Chest"), ("hips", "Hips"),
                     ("shoulder_r", "UpperArm.R"), ("shoulder_l", "UpperArm.L"),
                     ("elbow_r", "Forearm.R"), ("elbow_l", "Forearm.L"),
                     ("wrist_r", "Hand.R"), ("wrist_l", "Hand.L"),
                     ("knee_l", "Shin.L"), ("knee_r", "Shin.R"),
                     ("foot_l", "Foot.L"), ("foot_r", "Foot.R")):
        k[nm] = bone_gltf_world(bone).translation.copy()
    for s in ("r", "l"):
        wv = k["wrist_" + s] - k["elbow_" + s]
        k["hand_" + s] = k["wrist_" + s] + (wv.normalized() * 0.08 if wv.length > 1e-6 else Vector())
    for side, wd in weapons.items():
        m = bone_gltf_world(wd["bone"]) @ wd["S"]
        k[f"weapon_{side}_grip"] = m.translation.copy()
        k[f"weapon_{side}_base"] = m @ wd["base"]
        k[f"weapon_{side}_tip"] = m @ wd["tip"]
        k[f"weapon_{side}_span_tip"] = m @ Vector((0, job["span"][1], 0))
    return k


def eval_world(obj, dg):
    eo = obj.evaluated_get(dg)
    me = eo.to_mesh()
    n = len(me.vertices)
    co = np.empty(n * 3, np.float32)
    me.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3).astype(np.float64)
    M = np.array(eo.matrix_world)
    co = co @ M[:3, :3].T + M[:3, 3]
    me.calc_loop_triangles()
    t = np.empty(len(me.loop_triangles) * 3, np.int32)
    me.loop_triangles.foreach_get("vertices", t)
    eo.to_mesh_clear()
    return co, t.reshape(-1, 3)


def local_bvh(co, tris, centre, radius):
    d = np.linalg.norm(co - centre, axis=1)
    keep = d[tris].min(axis=1) < radius
    tt = tris[keep]
    if len(tt) == 0:
        return None
    used = np.unique(tt)
    remap = -np.ones(len(co), np.int64)
    remap[used] = np.arange(len(used))
    return BVHTree.FromPolygons(co[used].tolist(), remap[tt].tolist())


def neck_penetration(k):
    """Head-vs-collar interpenetration around the neck.

    Returns triangle overlap pairs between the separate head mesh and body/collar meshes
    (restricted to a 0.22 m sphere around the neck), the deepest head vertex found *inside*
    the body surface and the deepest body vertex inside the head surface (mm), plus the
    lowest head-mesh vertex relative to the Neck joint along the torso axis.
    """
    if not head_mesh:
        return {}
    dg = bpy.context.evaluated_depsgraph_get()
    centre = np.array((k["neck"] + k["head_joint"]) / 2)
    R = 0.22
    hc, ht = zip(*[eval_world(o, dg) for o in head_mesh])
    off = np.cumsum([0] + [len(c) for c in hc[:-1]])
    hco = np.vstack(hc)
    htr = np.vstack([t + o for t, o in zip(ht, off)])
    bc, bt = zip(*[eval_world(o, dg) for o in body_meshes])
    off = np.cumsum([0] + [len(c) for c in bc[:-1]])
    bco = np.vstack(bc)
    btr = np.vstack([t + o for t, o in zip(bt, off)])
    hb = local_bvh(hco, htr, centre, R)
    bb = local_bvh(bco, btr, centre, R)
    res = {"overlap_pairs": 0, "head_in_body_mm": 0.0, "body_in_head_mm": 0.0,
           "head_in_body_n": 0, "body_in_head_n": 0}
    if hb is None or bb is None:
        return res
    res["overlap_pairs"] = len(hb.overlap(bb))

    def depth(src, tree):
        d = np.linalg.norm(src - centre, axis=1)
        pts = src[d < R]
        if len(pts) > 4000:
            pts = pts[:: int(len(pts) / 4000) + 1]
        worst, n = 0.0, 0
        for p in pts:
            loc, nrm, _, dist = tree.find_nearest(Vector(p), 0.06)
            if loc is None:
                continue
            if (Vector(p) - loc).dot(nrm) < 0:
                n += 1
                worst = max(worst, dist)
        return worst * 1000, n
    res["head_in_body_mm"], res["head_in_body_n"] = depth(hco, bb)
    res["body_in_head_mm"], res["body_in_head_n"] = depth(bco, hb)
    # Lowest head vertex relative to the neck joint, measured along chest->neck axis.
    axis = np.array((k["neck"] - k["chest"]).normalized())
    rel = (hco - np.array(k["neck"])) @ axis
    res["head_lowest_vs_neck_mm"] = float(rel.min() * 1000)
    hv = hco[:: max(1, len(hco) // 3000)]
    c = hv.mean(axis=0)
    res["head_centre"] = [float(c[0]), float(c[2])]
    res["head_top_z"] = float(hco[:, 2].max())
    return res


def to_px(v, cam_x):
    px = (v[0] - cam_x) * PX_PER_M + RES_X / 2
    py = RES_Y - GROUND_PX_FROM_BOTTOM - v[1] * PX_PER_M
    return [round(px, 1), round(py, 1)]


results = {"hero": job["hero"], "base_scale": base_scale, "raw_height": raw_h,
           "px_per_m": PX_PER_M, "res": [RES_X, RES_Y], "ground_px": GROUND_PX_FROM_BOTTOM,
           "weapons": {s: {"ymin": w_["ymin"], "ymax": w_["ymax"],
                           "grip_to_tip": w_["tip"].length, "grip_to_base": w_["base"].length}
                       for s, w_ in weapons.items()},
           "head_meshes": [o.name for o in head_mesh], "body_meshes": [o.name for o in body_meshes],
           "clips": {n: list(a.frame_range) for n, a in actions.items()},
           "shots": [], "sweeps": {}}

for shot in job["shots"]:
    f = set_pose(shot["clip"], shot["progress"])
    k = keypoints()
    pen = neck_penetration(k) if shot.get("penetration", True) else {}
    cam_x = k["hips"].x + CAM_X_OFFSET
    cam.location = (cam_x, -20, CAM_Z)
    entry = dict(shot)
    entry["frame"] = f
    entry["cam_x"] = cam_x
    entry["kp"] = {n: P2(v) for n, v in k.items()}
    entry["kp3"] = {n: [round(c, 4) for c in v] for n, v in k.items()}
    entry["px"] = {n: to_px(P2(v), cam_x) for n, v in k.items()}
    entry["pen"] = pen
    if shot.get("render", True):
        sc.render.filepath = os.path.join(out_dir, shot["id"] + ".png")
        bpy.ops.render.render(write_still=True)
        entry["image"] = sc.render.filepath
    results["shots"].append(entry)
    print("SHOT", shot["id"], round(f, 2), flush=True)

# Dense sweep of each clip (no rendering): weapon tip forward reach + height per progress.
for clip in job.get("sweep_clips", []):
    rows = []
    for i in range(41):
        p = i / 40
        set_pose(clip, p)
        k = keypoints()
        row = {"p": p, "hips": P2(k["hips"]), "foot_l": P2(k["foot_l"]), "foot_r": P2(k["foot_r"])}
        for s in weapons:
            row["tip_" + s] = P2(k[f"weapon_{s}_tip"])
            row["grip_" + s] = P2(k[f"weapon_{s}_grip"])
        rows.append(row)
    results["sweeps"][clip] = rows

json.dump(results, open(os.path.join(out_dir, "result.json"), "w"), indent=1)
print("DONE", job["hero"])
