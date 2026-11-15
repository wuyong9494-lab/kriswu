"""Bake the recovered body mirror rules on already sampled source poses.

This is deliberately limited to the 58-bone body schema used by the reviewed
Imperial Spear passive motion. Native methods 39217–39229, 39261/39262 and
39277 operate on rest-relative Euler angles, not a world-space reflection.
The source animation must be interpolated *before* applying these rules.

The Z-X-Y conversion follows Unity's documented default rotation order. The
current motion stays outside its singular branch; reject a new singular input
instead of claiming an unverified branch is equivalent to the native engine.
"""
from __future__ import annotations

import hashlib
import xml.etree.ElementTree as ET

import numpy as np

from sun_triad_assets import require


REVIEWED_BONES_SHA256 = {
    "0a5e4b58c5900ddf0bc9a019305b72f628919a4562050349e5f3ee3809e6e455",
    "5fbd5b097b318b58cddef0d63dd94e1addd931882124ad05a3dd9712f0d0ecd8",
}


def euler_zxy(q):
    """Quaternion XYZW -> XYZ degrees, with an explicit singularity guard."""
    q = np.asarray(q, dtype=np.float64)
    norm = np.linalg.norm(q, axis=-1)
    require(np.isfinite(q).all() and (norm > 1e-12).all(), "Invalid source quaternion")
    q = q / norm[..., None]
    x, y, z, w = np.moveaxis(q, -1, 0)
    sine_x = np.clip(2 * (w * x - y * z), -1, 1)
    require((1 - sine_x * sine_x > 4e-6).all(), "Unreviewed ZXY singular branch")
    return np.degrees(np.stack((
        np.arcsin(sine_x),
        np.arctan2(2 * (w * y + x * z), 1 - 2 * (x * x + y * y)),
        np.arctan2(2 * (w * z + x * y), 1 - 2 * (x * x + z * z)),
    ), axis=-1))


def quaternion_zxy(degrees):
    """XYZ degrees -> quaternion XYZW: Ry * Rx * Rz."""
    half = np.radians(np.asarray(degrees, dtype=np.float64)) / 2
    sx, sy, sz = np.moveaxis(np.sin(half), -1, 0)
    cx, cy, cz = np.moveaxis(np.cos(half), -1, 0)
    result = np.stack((sx * cy * cz + sy * sz * cx,
                       sy * cx * cz - sx * sz * cy,
                       sz * cx * cy - sx * sy * cz,
                       cx * cy * cz + sy * sz * sx), axis=-1)
    return result / np.linalg.norm(result, axis=-1)[..., None]


def body_rules(raw):
    require(hashlib.sha256(raw).hexdigest() in REVIEWED_BONES_SHA256,
            "Unreviewed original body mirror schema")
    root = ET.fromstring(raw)
    dual, own = [], []
    for group in root.findall("./Mirroring/DualMirrorers/Mirrorer"):
        axis = group.attrib["MirrorAxis"]
        require(axis in {"None", "YZ"}, "Unreviewed dual mirror axis")
        dual.extend((b.attrib["Name"], b.attrib["MirrorBone"], axis) for b in group)
    for group in root.findall("./Mirroring/SelfMirrorers/Mirrorer"):
        require(group.attrib["MirrorAxis"] == "YZ", "Unreviewed self mirror axis")
        own.extend(b.attrib["Name"] for b in group)
    names = [name for a, b, _ in dual for name in (a, b)] + own
    require(len(dual) == 26 and len(own) == 6 and len(names) == len(set(names)) == 58,
            "Original 58-bone mirror mapping differs")
    return dual, own


def sample_source_motion(motion, first, last):
    """Keep exact source crop, then local nlerp at every 60 Hz simulation tick."""
    p = np.asarray(motion["positions"][first:last + 1], dtype=np.float64)
    q = np.asarray(motion["rotations"][first:last + 1], dtype=np.float64)
    require(len(p) == last - first + 1 and p.shape[:-1] == q.shape[:-1], "Invalid source crop")
    q /= np.linalg.norm(q, axis=-1)[..., None]
    for i in range(1, len(q)):
        q[i] *= np.where(np.sum(q[i - 1] * q[i], axis=-1) < 0, -1, 1)[:, None]
    positions = np.empty((2 * len(p) - 1, p.shape[1], 3), dtype=np.float64)
    rotations = np.empty((2 * len(q) - 1, q.shape[1], 4), dtype=np.float64)
    positions[::2], rotations[::2] = p, q
    positions[1::2] = (p[:-1] + p[1:]) / 2
    halfway = q[:-1] + q[1:]
    rotations[1::2] = halfway / np.linalg.norm(halfway, axis=-1)[..., None]
    return positions, rotations


def mirror_source_samples(positions, rotations, columns, nodes, names, rules):
    """Source cm/Unity quaternions in; source cm/Unity quaternions out."""
    dual, own = rules
    require(set(columns) == {n for a, b, _ in dual for n in (a, b)} | set(own),
            "Mirror rule does not cover the exact source body")
    p, q = np.asarray(positions, dtype=np.float64), np.asarray(rotations, dtype=np.float64)
    require(p.shape[:-1] == q.shape[:-1] and p.shape[1] == 58, "Wrong sampled body shape")
    rest_p = {name: np.asarray(nodes[names[name]].get("translation", [0, 0, 0]))
              * [100, 100, -100] for name in columns}
    rest_q = {name: np.asarray(nodes[names[name]].get("rotation", [0, 0, 0, 1]))
              * [-1, -1, 1, 1] for name in columns}
    rest_e = {name: euler_zxy(value) for name, value in rest_q.items()}
    angles = euler_zxy(q)
    mirrored_p, mirrored_e = p.copy(), angles.copy()
    for a, b, axis in dual:
        rotation_sign = np.array([1, -1, -1]) if axis == "YZ" else np.ones(3)
        position_sign = np.array([1, -1, -1]) if axis == "YZ" else -np.ones(3)
        for target, source in ((a, b), (b, a)):
            ti, si = columns[target], columns[source]
            mirrored_p[:, ti] = rest_p[target] + (p[:, si] - rest_p[source]) * position_sign
            mirrored_e[:, ti] = rest_e[target] + (angles[:, si] - rest_e[source]) * rotation_sign
    for name in own:
        i = columns[name]
        mirrored_e[:, i] = rest_e[name] + (angles[:, i] - rest_e[name]) * [1, -1, -1]
        # Native self-YZ changes rotation only; it does not reflect translation.
    mirrored_q = quaternion_zxy(mirrored_e)
    for i in range(1, len(mirrored_q)):
        mirrored_q[i] *= np.where(np.sum(mirrored_q[i - 1] * mirrored_q[i], axis=-1) < 0, -1, 1)[:, None]
    return mirrored_p, mirrored_q
