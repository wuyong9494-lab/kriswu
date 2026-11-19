"""Final catalog recovery entry point for already authenticated private data.
No network, key handling, upload, or logging of asset bytes.
"""
import base64
import json
from pathlib import Path
import tempfile

import fighter_shared_root_native as shared
import stage_h17_shared_root_release as stage
from replay_historical_sun import selected_base_members, SUN_NAME
from rebuild_sun_glb_exact import rebuild as rebuild_sun
from compile_catalog import compile_candidate,verify_candidates,identity,CATALOG,HISTORIC_SIZES
from append_cached_stun_motions import PROFILES
from imperial_metadata import KEYS,RAW_PIN
from stage_h17_floorfall_release import require,write_private

WITNESS = (9618,"6ed3b66b251aaedc53e86cddcc1a223c058869f489e712ff58dcb823a54128a6")
EXPECTED_TRANSFORMS={stage.CATALOG_NAME:stage.CATALOG_PATCH_NAME,stage.CHARACTER_NAME:stage.GLB_PATCH_NAME}


def witness_input(path,source_raw):
    require(path.is_file() and not path.is_symlink() and path.stat().st_size==WITNESS[0],"Imperial witness missing or size differs")
    raw=path.read_bytes()
    require(identity(raw)==WITNESS and identity(source_raw)==(167314,RAW_PIN),"Imperial witness/source hash differs")
    rows=json.loads(raw)
    require(set(rows)=={"clip","records"} and tuple(rows["clip"])==tuple(k for k in KEYS if k!="sourceBytesBase64")
            and [r["sourceRecordIndex"] for r in rows["records"]]==[9,10],"Imperial witness format differs")
    clip=dict(rows["clip"])
    clip["sourceBytesBase64"]=base64.b64encode(source_raw).decode()
    return clip,{r["sourceRecordIndex"]:r for r in rows["records"]}


def old_inputs(base_zip,delta_zip,base_manifest,delta_manifest):
    selected=selected_base_members(base_zip,base_manifest,(stage.CATALOG_NAME,SUN_NAME,stage.CHARACTER_NAME))
    doc,payload=shared.decode_delta(delta_zip,delta_manifest)
    trans=doc["transforms"]
    inventory=stage.inventory_from_pack(base_manifest)
    require(len(trans)==2 and {x["target"]:x["payload"] for x in trans}==EXPECTED_TRANSFORMS
            and all(x["base"]==inventory[x["target"]] for x in trans),"Original archive transformation differs")
    catalog=stage.rebuild_catalog(selected[stage.CATALOG_NAME],payload[stage.CATALOG_PATCH_NAME])
    liu=stage.rebuild_glb(selected[stage.CHARACTER_NAME],payload[stage.GLB_PATCH_NAME])
    sun=selected[SUN_NAME]
    require(identity(catalog)==CATALOG and identity(liu)==(HISTORIC_SIZES["liu"],PROFILES["liu"]["characterSHA"])
            and identity(sun)==(HISTORIC_SIZES["sun"],PROFILES["sun"]["characterSHA"]),"Historical inputs differ")
    return catalog,{"sun":sun,"liu":liu}


def replay(base_zip,delta_zip,base_manifest,delta_manifest,source_dir,witness,scratch_root,phase=lambda x:None, *, liu_witness=None):
    from rebuild_liu_motion import rebuild_motion
    from com_rebuild import infer_mass_bindings
    phase("exact-historical-inputs")
    catalog,models=old_inputs(base_zip,delta_zip,base_manifest,delta_manifest)
    meta=witness_input(witness,(source_dir/"imperial_spear_heavy_slash_passive.bytes").read_bytes())
    with tempfile.TemporaryDirectory(prefix="exact-catalog-",dir=scratch_root) as raw:
        d=Path(raw)
        s,l=(d/n for n in ("old-sun.glb","old-liu.glb"))
        write_private(s,models["sun"])
        write_private(l,models["liu"])
        phase("exact-target-models")
        newest=d/"sun-70.glb"
        rebuild_sun(s,source_dir,newest)
        liu,_=rebuild_motion(l,source_dir,d)
        sun=newest.read_bytes()
        new_models={"sun":sun,"liu":liu}
        stun,final=compile_candidate(catalog,models,new_models,source_dir,meta,infer_mass_bindings,phase,liu_witness=liu_witness)
        return verify_candidates(stun,final)
