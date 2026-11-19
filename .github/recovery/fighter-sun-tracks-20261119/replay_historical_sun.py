"""Join already-authenticated historical inputs privately for the Sun diagnostic.
Does not obtain keys, decrypt, copy original assets out, or publish anything.
"""
import hashlib
import io
import json
from pathlib import Path
import stat
import tempfile
import zipfile

import fighter_shared_root_native as shared
import stage_h17_shared_root_release as stage
from recover_endpoints import CATALOG, MODEL, TARGET_MODEL, pinned, require
from rebuild_sun_glb_exact import rebuild

SUN_NAME = "Sun_DeadForestTriad_Ninjato.glb"


def identity(raw, size, digest):
    return len(raw) == size and hashlib.sha256(raw).hexdigest() == digest


def selected_base_members(raw, base, selected):
    require(identity(raw, base["clearZIPBytes"], base["clearZIPSHA256"]), "Historical envelope identity differs")
    rows = stage.inventory_from_pack(base)
    with zipfile.ZipFile(io.BytesIO(raw)) as z:
        entries = z.infolist()
        require(len(entries) == len(rows) == len({x.filename for x in entries})
                and {x.filename for x in entries} == set(rows), "Historical archive file closure differs")
        contents = {}
        for name in selected:
            member = z.getinfo(name)
            row = rows[name]
            require(member.file_size == row["bytes"] and not member.flag_bits & 1
                    and member.compress_type in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED)
                    and stat.S_IFMT(member.external_attr >> 16) in (0, stat.S_IFREG),
                    "Historical member size/type differs")
            with z.open(member) as stream:
                data = stream.read(row["bytes"] + 1)
            require(identity(data, row["bytes"], row["sha256"]), "Historical member identity differs")
            contents[name] = data
    return contents


def reconstruct_inputs(base_bytes, delta_bytes, base, delta):
    catalog = stage.CATALOG_NAME
    selected = selected_base_members(base_bytes, base, (catalog, SUN_NAME))
    require(identity(selected[SUN_NAME], *MODEL), "Historical Sun identity differs")
    doc, payloads = shared.decode_delta(delta_bytes, delta)
    entries = [r for r in doc["transforms"] if r["target"] == catalog]
    rows = stage.inventory_from_pack(base)
    require(len(doc["transforms"]) == 2 and len(entries) == 1
            and entries[0]["base"] == rows[catalog]
            and entries[0]["payload"] == stage.CATALOG_PATCH_NAME,
            "Unexpected historical catalog transform")
    old_catalog = stage.rebuild_catalog(selected[catalog], payloads[stage.CATALOG_PATCH_NAME])
    require(identity(old_catalog, *CATALOG), "Expected pre-Stun catalog identity differs")
    return old_catalog, selected[SUN_NAME]


def replay(base_bytes, delta_bytes, base, delta, source_dir, scratch_root):
    from recover_endpoints import diagnose
    from append_cached_stun_motions import MOTIONS
    from append_cached_imperial_passives import SOURCE_RAW_SHA, VARIANTS
    catalog, old_glb = reconstruct_inputs(base_bytes, delta_bytes, base, delta)
    with tempfile.TemporaryDirectory(prefix="sun-diagnostic-", dir=scratch_root) as raw:
        temp = Path(raw)
        old, new = temp/"old.glb", temp/"target.glb"
        stage.write_private(old, old_glb)
        rebuild(old, source_dir, new)
        g, _, b = stage.glb_chunks(old_glb)
        target_g, _, target_b = stage.glb_chunks(pinned(new, TARGET_MODEL).read_bytes())
        specs = {r["name"]: (r["sha256"], r["frames"]) for r in MOTIONS}
        specs.update((name, (SOURCE_RAW_SHA, 71)) for name, *_ in VARIANTS)
        result = diagnose(json.loads(catalog), g, b, diagnostic_only=True,
                          target_animation=(target_g, target_b, specs))
        result["uniquelyBoundCapsules"] = len(result.pop("collisionEdges"))
        return result
