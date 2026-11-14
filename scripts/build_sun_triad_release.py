#!/usr/bin/env python3
"""Assemble a private, independently pinned H17 release from recovered inputs.

Original media stays outside the checkout. The legacy opponent retains its
original geometry and identity while source throw animations are appended.
The two-hammer model is never renamed D19.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import shutil
from sun_triad_assets import glb_read, private_output, require

LEGACY_CATALOG_SHA256 = "c4ee840d89cf1b2b8b82db0aebce878dbc5c2f2f60a52cf5b5a77b84f139ed5f"
LEGACY_TRAILS = dict(name="SF3_SourceTrails.json", bytes=20724,
                     sha256="6efadacf6a9e18a270a609132f622fb3ef569a505e46c81ff17c4b7ee386d0cc")


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def load(path):
    return json.loads(path.read_text())


def record(path):
    return dict(name=path.name, bytes=path.stat().st_size, sha256=digest(path))


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, separators=(",", ":")) + "\n")
    return record(path)


def verify_animation_append(original_path, appended_path, original, appended):
    require(record(original_path)["sha256"] == original["sha256"], "Baseline character mismatch")
    require(record(appended_path)["sha256"] == appended["sha256"], "Appended character mismatch")
    before, old_bytes = glb_read(original_path)
    after, new_bytes = glb_read(appended_path)
    require(new_bytes[:len(old_bytes)] == old_bytes, "Animation append modified original binary geometry")
    for key in ("nodes", "meshes", "materials", "skins", "textures", "images", "scenes", "scene", "extras"):
        require(before.get(key) == after.get(key), "Animation append modified original " + key)
    for key in ("animations", "accessors", "bufferViews"):
        require(after[key][:len(before[key])] == before[key], "Animation append changed old " + key)
    require(len(after["animations"]) == len(before["animations"]) + 6, "Expected six recovered source throws")
    for key in ("id", "hero", "faction", "bodyID", "weaponID", "resourceName", "activeWeaponSides"):
        require(original[key] == appended[key], "Animation append changed character identity")
    current = {c["name"]: c for c in appended["clips"]}
    for clip in original["clips"]:
        require(clip["name"] in current and all(current[clip["name"]][key] == clip[key]
            for key in ("frames", "sha256", "bundle")), "Original motion identity changed")


def build(args):
    out = private_output(args.output)
    out.mkdir(parents=True, exist_ok=True)
    require(digest(args.legacy_catalog) == LEGACY_CATALOG_SHA256, "Unknown baseline catalog")
    catalog = load(args.legacy_catalog)
    profile = load(args.candidate / "runtime/SF3_Triad_Profile.json")
    require(profile["id"] == "sun_triad", "Expected recovered H17 profile")
    baseline = next(p for p in catalog["profiles"] if p["id"] == "liu_hammers")
    legacy = load(args.candidate / "runtime/SF3_Liu_Profile.json")
    liu_model = args.candidate / "ordinary-throws/liu/Liu_Legion_Hammers.glb"
    verify_animation_append(args.candidate / "legacy-liu/Liu_Legion_Hammers.glb", liu_model, baseline, legacy)
    catalog["profiles"] = [profile, legacy]
    catalog["provenance"] = dict(
        selection="Recovered H17 source character and authenticated legacy opponent with six appended original source throw motions.",
        sourceCombat="H17 formal configuration and source bone capsules; normalized stats and impulses explicitly marked in profile.",
        d19="D19 runtime is validated separately. This resource release does not substitute the legacy opponent for a D19 character.")
    catalog_file = write(out / "SF3_DistinctFighters.json", catalog)
    copied = {}

    def copy(source, expected=None):
        item = record(source)
        if expected is not None:
            require(item == expected, "Source resource pin mismatch: " + source.name)
        if source.name in copied:
            require(copied[source.name] == item, "Conflicting private resource basename")
        else:
            if source.resolve() != (out / source.name).resolve(): shutil.copyfile(source, out / source.name)
            copied[source.name] = item
        return item

    copy(args.candidate / (profile["resourceName"] + ".glb"), dict(
        name=profile["resourceName"] + ".glb", bytes=profile["bytes"], sha256=profile["sha256"]))
    copy(liu_model, dict(name=liu_model.name, bytes=legacy["bytes"], sha256=legacy["sha256"]))
    summons_path = args.candidate / "spirits/SF3_H17_Summons.json"
    summons = load(summons_path)
    require(summons["characterSHA256"] == profile["sha256"], "Companion identity mismatch")
    for model in summons["models"]:
        copy(summons_path.parent / model["file"]["name"], model["file"])
    summons_file = copy(summons_path)

    audio_path = args.candidate / "audio-candidate/SF3_H17_Audio.json"
    audio = load(audio_path)
    require(audio["characterSHA256"] == profile["sha256"] and audio["markers"] and audio["cues"],
            "Audio source triggers must be bound before release")
    for file in audio["files"]: copy(audio_path.parent / file["name"], file)
    audio_file = copy(audio_path)

    import gzip
    effects_path = args.candidate / "fx-candidate/SF3_H17_Effects.json.gz"
    effects = json.loads(gzip.decompress(effects_path.read_bytes()))
    require(effects["characterSHA256"] == profile["sha256"] and effects["markers"] and effects["bindings"],
            "Effects source triggers must be bound before release")
    for file in effects["files"]: copy(effects_path.parent / file["name"], file)
    effects_file = copy(effects_path)

    trail_path = args.candidate / "trails/SF3WE_Ninjato_Trails.json"
    trails = load(trail_path)
    require(trails["profiles"][0]["characterSHA256"] == profile["sha256"], "Source trail identity mismatch")
    for target in trails["profiles"]:
        texture = target["alpha"]
        copy(trail_path.parent / texture["name"], {k: texture[k] for k in ("name", "bytes", "sha256")})
        for mesh in target["meshes"]:
            texture = mesh["material"].get("colorTexture")
            if texture: copy(trail_path.parent / texture["name"], {k: texture[k] for k in ("name", "bytes", "sha256")})
    trails["version"] = 3
    trails["legacy"] = dict(manifest=LEGACY_TRAILS, profileIDs=[legacy["id"]], rebindings=[dict(
        id=legacy["id"], mode="appendSourceAnimations", fromSHA256=baseline["sha256"], toSHA256=legacy["sha256"])])
    trails_file = write(out / "SF3WE_Target_Trails.json", trails)

    def binding(p, metadata, source_version, evidence, source_fps):
        return dict(id=p["id"], characterSHA256=p["sha256"], bodyID=p["bodyID"], weaponID=p["weaponID"],
            sourceVersion=source_version, evidence=evidence, motions=[dict(clip=c["name"], sourceSHA256=c["sha256"],
                sourceBundle=c["bundle"], frames=c["frames"], exportFramesPerSecond=30,
                sourceFramesPerSecond=source_fps) for c in p["clips"]],
            skinRoots=metadata["skinRoots"], restorePersonalBindSpace=metadata["restorePersonalBindSpace"],
            materials=metadata["materials"])

    metadata = load(args.candidate / "Sun_FighterRelease_Profile_Metadata.json")
    require(metadata["characterSHA256"] == profile["sha256"], "Main material metadata mismatch")
    release = dict(schemaVersion=2, id="h17-source-recovery-20261114", catalog=catalog_file,
        sourceTrails=trails_file, panguAudio=None, triadAudio=audio_file, triadSummons=summons_file,
        triadEffects=effects_file, profiles=[
            binding(profile, metadata, profile["triadRules"]["runtime"]["evidence"]["version"],
                metadata["evidence"] + ["Original actor/companion poses, 60 Hz simulation with source MidFrames=1, decoded H17 configuration."], 30),
            binding(legacy, dict(skinRoots=[dict(skin=0, declared=1, corrected=0)],
                restorePersonalBindSpace=True, materials=[]), "user-authenticated-legacy-integration+source-throws",
                ["Liu original geometry, materials, skins and original 50 motion channels are preserved; six recovered source throw channels are appended.",
                 "Native mass-weighted COM and paired source throws are validated independently; this is not a D19 character identity."], None)])
    release_file = write(out / "SF3_FighterRelease.json", release)
    inventory = sorted([record(out / name) for name in copied] + [catalog_file, trails_file, release_file], key=lambda x: x["name"])
    require(len(inventory) == len({f["name"] for f in inventory}), "Duplicate release file")
    return dict(release=release_file, files=inventory, baselineCatalogSHA256=LEGACY_CATALOG_SHA256,
        baselineTrails=LEGACY_TRAILS, replacements=["Liu_Legion_Hammers.glb", "SF3_DistinctFighters.json"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--legacy-catalog", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    receipt = build(args)
    write(args.output.parent / "h17-release-assembly-receipt-private.json", receipt)
    print(json.dumps(dict(release=receipt["release"], files=len(receipt["files"]),
        bytes=sum(f["bytes"] for f in receipt["files"]))))


if __name__ == "__main__": main()
