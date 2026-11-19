"""Materialize exact historical/rebuilt bytes inside one protected staging job.

All raw archives and source directories are already authenticated by the
runner. This module has no network, keys, artifact uploads, or signing.
"""
from pathlib import Path
import hashlib
import json
import tempfile

from assemble_active_assets import read,require,write_new
import fighter_h17_d19_native as legacy
import fighter_shared_root_native as shared
from verify_fighter_protected_base_reuse import historical_inventory
from assemble_from_archives import old_inputs,witness_input
from compile_catalog import compile_candidate,STUN_CATALOG,FINAL_CATALOG,identity
from rebuild_sun_glb_exact import rebuild as rebuild_sun,SUN
from rebuild_liu_motion import rebuild_motion
from com_rebuild import infer_mass_bindings
import rebuild_release_stamp as release

def rebuild_derived(repo,scratch,base_zip,delta_zip,base_pin,delta_pin,source_dir,
                    imperial_witness,liu_witness,serpent_payload,targets,*,manifest_rebuilder):
    scratch=Path(scratch)
    catalog,models=old_inputs(base_zip,delta_zip,base_pin,delta_pin)
    historic=scratch/"historical-private"
    legacy.overlay_zip(base_zip,base_pin,historic)
    manifest,payloads=shared.decode_delta(delta_zip,delta_pin)
    shared.reconstruct_delta(manifest,payloads,historic,base_pin)
    old=historical_inventory(repo)
    for row in old:read(row,historic/row["name"])
    rebuilt=scratch/"rebuilt-private";rebuilt.mkdir(mode=0o700)
    known={
        "SF3_H17_SerpentMorph.json":serpent_payload,
        "SF3_FighterRelease.json":release.encoded(release.descriptor(
            release.parse_json(read(dict(name=release.NAME,**release.OLD_RELEASE),historic/release.NAME)),targets)),
    }
    for n in manifest_rebuilder.BINDINGS:
        # Historical inventory may also include obsolete same-name rows. The
        # final byte pin, not resemblance or a timestamp, chooses the result.
        r=next(x for x in old if x["name"]==n)
        matches={raw for raw in manifest_rebuilder.rebuild(read(r,historic/n),n)
                 if identity(raw)==(targets[n]["bytes"],targets[n]["sha256"])}
        require(len(matches)==1,"Five-manifest replay did not reproduce original bytes")
        known[n]=next(iter(matches))
    with tempfile.TemporaryDirectory(prefix="catalog-active-",dir=scratch) as t:
        temp=Path(t)
        sun_in,liu_in,sun_out=(temp/n for n in ("sun-in.glb","liu-in.glb","sun-out.glb"))
        write_new(sun_in,models["sun"]);write_new(liu_in,models["liu"])
        rebuild_sun(sun_in,source_dir,sun_out)
        liu,_=rebuild_motion(liu_in,source_dir,temp)
        sun=sun_out.read_bytes()
        meta=witness_input(imperial_witness,(source_dir/"imperial_spear_heavy_slash_passive.bytes").read_bytes())
        stun,final=compile_candidate(catalog,models,{"sun":sun,"liu":liu},source_dir,meta,
                                     infer_mass_bindings,liu_witness=liu_witness)
        require(identity(stun)==STUN_CATALOG and identity(final)==FINAL_CATALOG,"Catalog replay did not reproduce both pins")
        known[SUN]=sun
        known["SF3_DistinctFighters.json"]=final
    require(len(known)==9,"Rebuilt resource selection differs")
    for n,raw in known.items():
        r=targets[n]
        require((len(raw),hashlib.sha256(raw).hexdigest())==(r["bytes"],r["sha256"]),"Rebuilt active asset hash differs")
        write_new(rebuilt/n,raw)
    return [(historic,old),(rebuilt,[targets[n] for n in sorted(known)])]
