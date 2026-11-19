"""Offline diagnostic: infer bindings from an authenticated old catalog + rig.
No asset download, no production writes. Results are candidates, not original XML.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from sun_triad_assets import RIGHT, accessor_read, glb_read, matrix, pose_world, world_poses

CATALOG = (29_221_179, "fbd9ecbd9fb16de79c0240404e315af81d8cbbaa113b6042e6afc5ed7b1d0330")
TARGET_MODEL = (16_252_036, "7c9ebfe285f637cbd002f717d80b859a57d3ab11ef491f15930dc4f3eb50d96a")
MODEL = (15_458_776, "ce9e1b77c59fa63116af73409173fcd8922f2063ab2e0624534691fa00195ef6")
COORD_SCALE = np.array([.01, .01, -.01])
ROUNDING_MAX = 5.001e-8
MARGIN = 2e-7


def require(valid, detail):
    if not valid:
        raise ValueError(detail)


def pinned(path, pin):
    size, sha = pin
    require(len(sha) == 64 and path.stat().st_size == size, "Historical input pin differs")
    with path.open("rb") as f:
        require(hashlib.file_digest(f, "sha256").hexdigest() == sha, "Historical input hash differs")
    return path


def endpoint_prediction(world, index, local):
    # Use the same parenthesization and homogeneous coordinate as capsule_point.
    return (world[:, index] @ np.r_[np.asarray(local) * COORD_SCALE, 1.])[:, :3]


def endpoint_candidates(world, values, training):
    """Retain all near-tied joints; every candidate must reproduce archived samples."""
    require(world.ndim == 4 and world.shape[2:] == (4, 4) and len(world) == len(values)
            and values.shape == (len(world), 3) and training.shape == (len(world),)
            and training.dtype == np.bool_ and np.isfinite(world).all() and np.isfinite(values).all()
            and min(training.sum(), (~training).sum()) >= 8, "Insufficient or invalid poses")
    fits = []
    for index in range(world.shape[1]):
        r, t = world[:, index, :3, :3] * COORD_SCALE, world[:, index, :3, 3]
        fit, _, rank, _ = np.linalg.lstsq(r[training].reshape(-1, 3), (values-t)[training].reshape(-1), rcond=None)
        if rank < 3:
            continue
        error = float(abs(endpoint_prediction(world, index, fit) - values).max())
        fits.append((error, index, fit))
    fits.sort(key=lambda row: row[0])
    require(len(fits) >= 2 and fits[0][0] <= ROUNDING_MAX * 1.3, "No verified joint fit")
    accepted, unresolved = [], []
    for error, index, fit in fits:
        if error > fits[0][0] + MARGIN:
            break
        for decimals in range(12):
            candidate = np.round(fit, decimals)
            projected = endpoint_prediction(world, index, candidate)
            if np.array_equal(np.round(projected, 7), values):
                accepted.append((index, candidate.tolist(), float(abs(projected - values).max())))
                break
        else:
            unresolved.append(index)
    require(bool(accepted), "Candidate does not reproduce every recorded endpoint to source precision")
    return accepted, unresolved


def fitting_endpoint(world, values, training):
    fits, unresolved = endpoint_candidates(world, values, training)
    require(len(fits) == 1 and not unresolved, "Ambiguous joint fit")
    return fits[0]


def compare_target_tracks(fits, unresolved, target_poses):
    """Compare all candidates on every new tick. Never infer an original joint from consensus."""
    require(fits and target_poses and not unresolved, "Not all plausible joint bindings are resolved")
    reports = []
    for name, world in target_poses.items():
        require(world.ndim == 4 and world.shape[2:] == (4, 4)
                and len(world) > 0 and np.isfinite(world).all(), "Invalid target action poses")
        rounded = [np.round(endpoint_prediction(world, index, local), 7) for index, local, _ in fits]
        # Serialized track hashes distinguish -0.0 from 0.0.
        raw = [track.tolist() for track in rounded]
        baseline = json.dumps(raw[0], separators=(",", ":"))
        equal = all(json.dumps(item, separators=(",", ":")) == baseline for item in raw[1:])
        reports.append(dict(name=name, ticks=len(world), sameTrack=equal))
    return reports

def animation_samples(g, b, anim, frames, sample_ids, rest, parents):
    extras = anim.get("extras", {})
    baked = "bakedSamples" in extras
    keys = 2*frames-1 if baked else frames
    hz = 60 if baked else 30
    require(not baked or (extras["bakedSamples"] == keys and extras.get("simulationHz") == 60),
            "Unexpected baked target sample count")
    streams = {}
    for channel in anim["channels"]:
        node, kind = (channel["target"][key] for key in ("node", "path"))
        require(kind in ("rotation", "translation") and kind not in streams.get(node, {}),
                "Unsupported historical animation channel")
        sampler = anim["samplers"][channel["sampler"]]
        values = accessor_read(g, b, sampler["output"]).astype(float)
        times = accessor_read(g, b, sampler["input"]).reshape(-1)
        require(sampler.get("interpolation", "LINEAR") == "LINEAR"
                and values.shape == (keys, 3 if kind == "translation" else 4)
                and len(times) == keys and np.allclose(times, np.arange(keys)/hz, atol=1e-7, rtol=1e-7),
                "Unexpected historical clip interpolation")
        streams.setdefault(node, {})[kind] = values
    require(all(set(row) == {"rotation", "translation"} for row in streams.values()), "Incomplete channel")
    for tick in sample_ids:
        require(0 <= tick < 2*frames-1, "Tick outside action")
        if baked:
            start, end, frac = int(tick), int(tick), 0.
        else:
            start, half = divmod(int(tick), 2)
            end, frac = min(start+1, frames-1), half*.5
        local = list(rest)
        for index, stream in streams.items():
            p, q = [stream[k][start]*(1-frac) + stream[k][end]*frac for k in ("translation", "rotation")]
            local[index] = matrix(p, q, g["nodes"][index].get("scale", [1, 1, 1]))
        yield RIGHT @ pose_world(local, parents)


def diagnose(catalog, g, b, *, profile_id="sun_triad", model_pin=MODEL, clip_total=65, diagnostic_only=False, withheld_clips=(), target_animation=None):
    matches = [row for row in catalog["profiles"] if row["id"] == profile_id]
    require(len(matches) == 1, "Sun row missing or ambiguous")
    profile = matches[0]
    require((profile["bytes"], profile["sha256"]) == model_pin, "Archived catalog references a different GLB")
    anims = {anim["name"]: anim for anim in g["animations"]}
    require(len(anims) == len(g["animations"]) == clip_total, "Unexpected historical rig")
    names = [node["name"] for node in g["nodes"]]
    limb_names = ("hand_l", "hand_r", "foot_l", "foot_r")
    require(all(names.count(name) == 1 for name in limb_names), "Ambiguous rig limb names")
    _, rest, parents = world_poses(g["nodes"])
    serialized_bindings, worlds, observations, training = None, [], [], []
    clip_count = 0
    targets, references = {}, {}
    for clip in profile["clips"]:
        name, frames = clip["name"], clip["frames"]
        tracks = clip["tracks"]
        edges = tracks.get("collisionEdges", [])
        if not edges or name not in anims:
            continue
        require(anims[name]["extras"]["sourceSHA256"] == clip["sha256"], "Clip identity differs")
        bindings = [{key: row[key] for key in ("id", "side", "radiusMillimeters")} for row in edges]
        if serialized_bindings is None:
            serialized_bindings = bindings
        require(bindings == serialized_bindings and len({row["id"] for row in bindings}) == len(edges) == 4
                and all(row["side"] in ("left", "right") and type(row["radiusMillimeters"]) is int
                        and row["radiusMillimeters"] > 0 for row in bindings), "Edge bindings differ")
        ticks = 2 * frames - 1
        require(tracks["samplesPerSourceFrame"] == 2 and all(
                len(edge[end]) == ticks for edge in edges for end in ("base", "tip")), "Edge sample count differs")
        if name in withheld_clips:
            targets[name] = np.array(list(animation_samples(g, b, anims[name], frames, range(ticks), rest, parents)))
            references[name] = np.array([[edge[end] for end in ("base", "tip")] for edge in edges])
            continue
        # Sample across many distinct archived clips, with odd and even ticks.
        ids = np.unique(np.linspace(0, ticks-1, min(ticks, 23), dtype=int))
        indexes = [names.index(n) for n in limb_names]
        world = np.array(list(animation_samples(g, b, anims[name], frames, ids, rest, parents)))
        for key, node in zip(("handL", "handR", "footL", "footR"), indexes):
            require(np.array_equal(np.round(world[:, node, :3, 3], 7), np.asarray(tracks[key])[ids]),
                    "Historical pose control does not reproduce archived limb track")
        worlds.append(world)
        observations.append(np.array([[edge[end] for end in ("base", "tip")] for edge in edges])[:, :, ids, :])
        training.extend([clip_count % 3 != 1] * len(ids))
        clip_count += 1
    require(clip_count >= 9, "Insufficient independent archived clips")
    require(set(targets) == set(withheld_clips), "Missing requested withheld clips")
    if target_animation:
        target_g, target_b, pinned_specs = target_animation
        require(target_g["nodes"] == g["nodes"], "Target GLB rig changes historical bindings")
        target_by_name = {a["name"]: a for a in target_g["animations"]}
        require(len(target_by_name) == len(target_g["animations"]), "Target animation names are ambiguous")
        require(set(pinned_specs).isdisjoint(anims), "New clips must not be part of historical fit")
        for name, (source_sha, frames) in pinned_specs.items():
            anim = target_by_name[name]
            require(anim["extras"]["sourceSHA256"] == source_sha, "Target source clip identity differs")
            targets[name] = np.array(list(animation_samples(target_g, target_b, anim, frames, range(2*frames-1), rest, parents)))
    poses, points, assigned = np.concatenate(worlds), np.concatenate(observations, axis=2), np.asarray(training)
    results, rejected, comparisons = [], [], []
    for i, binding in enumerate(serialized_bindings):
        record = dict(id=binding["id"], radiusCentimeters=binding["radiusMillimeters"]/10)
        for j, end in enumerate(("base", "tip")):
            try:
                fits, unresolved = endpoint_candidates(poses, points[i, j], assigned)
                if targets:
                    checked = compare_target_tracks(fits, [], targets)
                    for row in checked:
                        target_name = row["name"]
                        if target_name in references:
                            expected = references[target_name][i, j]
                            row["matchesKnownTrack"] = all(np.array_equal(
                                np.round(endpoint_prediction(targets[target_name], index, local), 7), expected)
                                for index, local, _ in fits)
                    comparisons.append(dict(capsule=binding["id"], endpoint=end, candidates=len(fits),
                        unresolvedAlternatives=len(unresolved),
                        status="inconclusive" if unresolved else
                            ("same-target-tracks" if all(row["sameTrack"] for row in checked) else "target-tracks-diverge"),
                        clips=checked))
                require(len(fits) == 1 and not unresolved, "Ambiguous joint fit")
                index, local, _ = fits[0]
                require(names[index] and names.count(names[index]) == 1, "Endpoint joint has no unique name")
                record[end] = dict(bone=names[index], localPositionCentimeters=local)
            except ValueError as error:
                if not diagnostic_only:
                    raise
                rejected.append(dict(capsule=binding["id"], endpoint=end, reason=str(error)))
        if "base" in record and "tip" in record:
            results.append(record)
    return dict(status="historical-projection-candidate" if not rejected else "unresolved-diagnostic",
                originalXML=False, productionReady=False, clips=clip_count,
                fittingSamples=int(assigned.sum()), holdoutSamples=int((~assigned).sum()),
                collisionEdges=results, rejectedEndpoints=rejected, targetComparisons=comparisons)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("catalog", type=Path)
    p.add_argument("model", type=Path)
    p.add_argument("--target-model", type=Path, help="Exact reviewed 70-action Sun model")
    args = p.parse_args()
    catalog = json.loads(pinned(args.catalog, CATALOG).read_bytes())
    g, b = glb_read(pinned(args.model, MODEL))
    options = {}
    if args.target_model:
        from append_cached_stun_motions import MOTIONS
        from append_cached_imperial_passives import SOURCE_RAW_SHA, VARIANTS
        from stage_h17_shared_root_release import glb_chunks
        target_g, _, target_b = glb_chunks(pinned(args.target_model, TARGET_MODEL).read_bytes())
        specs = {row["name"]: (row["sha256"], row["frames"]) for row in MOTIONS}
        specs.update((name, (SOURCE_RAW_SHA, 71)) for name, *_ in VARIANTS)
        require(len(target_g["animations"]) == 70 and
                target_g["animations"][:65] == g["animations"], "Target does not preserve old GLB animations")
        options["target_animation"] = (target_g, target_b, specs)
    receipt = diagnose(catalog, g, b, diagnostic_only=True, **options)
    receipt["uniquelyBoundCapsules"] = len(receipt.pop("collisionEdges"))
    print(json.dumps(receipt))


if __name__ == "__main__":
    main()
