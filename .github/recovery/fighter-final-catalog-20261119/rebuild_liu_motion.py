"""Reproduce the removed Liu GLB only in private memory for catalog motion recovery.

This is not a model-release path. Reuses the reviewed Sun channel append code,
requires all three historical Liu byte identities, and deletes temporary GLBs.
The caller may consume the verified animation/rig data to rebuild the catalog;
it must not stage or publish the removed double-hammer character.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import tempfile

import rebuild_sun_glb_exact as channels
from append_cached_stun_motions import MOTIONS, PROFILES, validate_stun_append
from append_cached_imperial_passives import SOURCE_RAW_SHA, VARIANTS, validate_append
from stage_cached_stun_release import NEW as STUN
from stage_cached_imperial_passives import NEW as IMPERIAL
from stage_h17_shared_root_release import NEW_CHARACTER_BYTES, glb_chunks
from stage_h17_floorfall_release import real_directory, regular, require
from sun_triad_assets import REPOSITORY

BASE_PIN = dict(bytes=NEW_CHARACTER_BYTES, sha256=PROFILES["liu"]["characterSHA"])
STUN_PIN = {k: STUN["liu"][k] for k in ("bytes", "sha256")}
FINAL_PIN = {k: IMPERIAL["liu"][k] for k in ("bytes", "sha256")}
COUNTS = (59, 62, 64)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def require_pin(raw, pin, label):
    require((len(raw), sha(raw)) == (pin["bytes"], pin["sha256"]), label)


def load_sources(sources):
    """Read only the same two reviewed schemas and four original motions as Sun."""
    folder = real_directory(sources)
    xmls = [regular(folder / f"mirror-{label}.xml", 128_000) for label in ("553", "608")]
    for xml in xmls:
        channels.body_rules(xml)  # Independently pinned by original mirroring module.
    stun = [regular(folder / (row["name"] + ".bytes"), 100_000) for row in MOTIONS]
    for raw, row in zip(stun, MOTIONS, strict=True):
        require_pin(raw, row, "Wrong original Stun source")
    imperial = regular(folder / "imperial_spear_heavy_slash_passive.bytes", 1_000_000)
    require(sha(imperial) == SOURCE_RAW_SHA, "Wrong original Imperial source")
    return xmls, stun, imperial


def rebuild_motion(old, sources, scratch_parent):
    """Return `(exact_final_glb_bytes, receipt)`; persist no character or profile.

    Inputs are the authenticated shared-root 59-clip Liu GLB and the six flat
    source files consumed by the existing exact Sun builder. `scratch_parent`
    must be an existing real directory outside the repository. Output is never
    admitted solely on numeric similarity: both intermediate and final exact
    byte counts and SHA-256 identities must match the historical release pins.
    """
    old = Path(old).absolute()
    require(old.resolve(strict=True) == old, "Base GLB must not use symbolic links")
    base = regular(old, BASE_PIN["bytes"])
    require_pin(base, BASE_PIN, "Wrong pre-Stun 59-clip Liu GLB")
    base_g, _, _ = glb_chunks(base)
    require(len(base_g["animations"]) == COUNTS[0], "Wrong base animation count")
    xmls, stun, imperial = load_sources(sources)
    scratch_parent = real_directory(scratch_parent)
    require(scratch_parent != REPOSITORY and REPOSITORY not in scratch_parent.parents,
            "Diagnostic scratch must remain outside the repository")

    with tempfile.TemporaryDirectory(prefix=".liu-motion-only-", dir=scratch_parent) as scratch:
        temp = Path(scratch) / "diagnostic-only.glb"
        # Writer.save truncates this already-private file, retaining its mode.
        descriptor = os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        os.close(descriptor)
        first = channels.writer(base)
        channels.add_stun(first, xmls[0], stun)
        first.save(temp)
        post = regular(temp, STUN_PIN["bytes"])
        validate_stun_append(base, post, COUNTS[0])
        require_pin(post, STUN_PIN, "Post-Stun Liu GLB differs from historical pin")

        attempts = []
        for xml in xmls:
            # Always restart from pinned 62-clip bytes, never from a failed attempt.
            writer = channels.writer(post)
            channels.add_imperial(writer, xml, imperial)
            writer.save(temp)
            raw = regular(temp, 32_000_000)
            validate_append(post, raw, COUNTS[1])
            attempts.append(dict(mirrorSchemaSHA256=sha(xml), bytes=len(raw), sha256=sha(raw)))
            if (len(raw), sha(raw)) != (FINAL_PIN["bytes"], FINAL_PIN["sha256"]):
                continue
            g, _, _ = glb_chunks(raw)
            require(len(g["animations"]) == COUNTS[2], "Wrong final animation count")
            receipt = dict(
                schema="liu-historical-motion-only-rebuild-v1",
                purpose="private-catalog-motion-recovery-only", input=dict(BASE_PIN),
                intermediate=dict(STUN_PIN), final=dict(FINAL_PIN), animationCounts=list(COUNTS),
                appended=[row["name"] for row in MOTIONS] + [row[0] for row in VARIANTS],
                selectedMirrorSchemaSHA256=sha(xml), mirrorAttempts=attempts,
                exactHistoricalIntermediate=True, exactHistoricalFinal=True,
                originalMediaPublished=False, removedCharacterStaged=False,
                persistentModelOutput=False, profileRebuilt=False, nativeRendered=False)
            return raw, receipt
        raise ValueError("Neither reviewed mirror schema reproduced final Liu D873 bytes")


# Same signature for callers using the Sun builder's function name.
rebuild = rebuild_motion


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("old", type=Path)
    parser.add_argument("sources", type=Path)
    parser.add_argument("scratch_parent", type=Path)
    args = parser.parse_args()
    _, receipt = rebuild_motion(args.old, args.sources, args.scratch_parent)
    print(json.dumps(receipt, sort_keys=True))


if __name__ == "__main__":
    main()
