"""Assemble and check the exact historical catalog without resource publication."""
from __future__ import annotations
import copy
import json
from pathlib import Path

from append_cached_stun_motions import MOTIONS,PROFILES
from append_cached_imperial_passives import SOURCE_RAW_SHA,VARIANTS
from stage_cached_stun_release import append_catalog
from stage_cached_imperial_passives import NEW as IMPERIAL
from stage_h17_floorfall_release import encoded, fresh_output, write_private, require
from stage_h17_shared_root_release import glb_chunks
from endpoint_consensus import CATALOG, diagnose
from append_catalog_motion_tracks import sha,generate_tracks,stun_clip,specs,sun_blade_edges,HURT_XML_SHA,BONES_XML_SHA
from imperial_metadata import assemble_clip

STUN_CATALOG = (30_151_732, "41a63ef6a87f994be75560da10ae3adea881d472ae343eaaaaf7758593d279e8")
FINAL_CATALOG = (31_948_679, "77f7dd57c512aed3091fbedf8815ea5c6fc4b80725e9785cb2953bce2a47b6f4")
HISTORIC_SIZES = {"sun":15_458_776,"liu":10_792_864}


def identity(raw):
    return len(raw),sha(raw)


def append_imperial_rows(catalog, variants):
    result=copy.deepcopy(catalog)
    require({r["id"] for r in result["profiles"]} == {p["id"] for p in PROFILES.values()}, "Wrong historical roster")
    for key,pin in PROFILES.items():
        row=next(r for r in result["profiles"] if r["id"]==pin["id"])
        clips=variants[key]
        require(len(clips)==2 and len(row["clips"])==pin["count"]+3,"Wrong staged motion count")
        for c,(name,role,index,mirror) in zip(clips,VARIANTS,strict=True):
            require(c["name"]==name and c["sha256"]==SOURCE_RAW_SHA and c["frames"]==71 and
                    c["sourceConfiguration"]["sourceRecordIndex"]==index and c["sourceMirroringApplied"] is mirror and
                    role not in row["roles"] and all(old["name"]!=name for old in row["clips"]), "Wrong Imperial alias")
            row["roles"][role]=name
        row["clips"].extend(copy.deepcopy(clips))
        row["bytes"],row["sha256"]=IMPERIAL[key]["bytes"],IMPERIAL[key]["sha256"]
    return result


def compose(catalog,stun,imperial):
    staged=append_catalog(catalog,stun)
    return encoded(staged),encoded(append_imperial_rows(staged,imperial))


def compile_candidate(old_catalog, old_models, new_models, source_dir, metadata, mass_reader,
                      phase=lambda x:None, *, liu_witness=None):
    from liu_landmarks import validate_liu_landmarks
    require(identity(old_catalog)==CATALOG,"Historical catalog differs")
    catalog=json.loads(old_catalog)
    full_xml=(source_dir/"mirror-608.xml").read_bytes()
    base_xml=(source_dir/"mirror-553.xml").read_bytes()
    require(sha(full_xml)==HURT_XML_SHA and sha(base_xml)==BONES_XML_SHA,"BonesData identity differs")
    stuns={m["name"]:(source_dir/(m["name"]+".bytes")).read_bytes() for m in MOTIONS}
    raw_victim=(source_dir/"imperial_spear_heavy_slash_passive.bytes").read_bytes()
    clip,records=metadata
    require(sha(raw_victim)==SOURCE_RAW_SHA,"Victim source differs")
    stage_stun,stage_imperial = {},{}
    for key,pin in PROFILES.items():
        phase(key+"-model-pins")
        old,new=old_models[key],new_models[key]
        require(identity(old)==(HISTORIC_SIZES[key],pin["characterSHA"]),"Wrong historical GLB")
        require(identity(new)==(IMPERIAL[key]["bytes"],IMPERIAL[key]["sha256"]),"Wrong target GLB")
        og,_,ob=glb_chunks(old); ng,_,nb=glb_chunks(new)
        profile=next(r for r in catalog["profiles"] if r["id"]==pin["id"])
        require(len(og["animations"])==pin["count"] and len(ng["animations"])==pin["count"]+5
                and ng["animations"][:pin["count"]]==og["animations"] and ng["nodes"]==og["nodes"],
                "Target GLB changed the original rig or animations")
        phase(key+"-mass-bindings")
        masses=mass_reader(profile,og,ob,base_xml,full_xml)
        phase(key+"-weapon-tracks")
        consensus={}
        blades=None
        liu=None
        if key=="sun":
            proof=diagnose(catalog,og,ob,target_animation=(ng,nb,specs()),
                           diagnostic_only=True,keep_tracks=True)
            consensus=proof["candidateTracks"]
            blades=sun_blade_edges(profile)
            require(len(consensus)==40,"Not every Sun track is supported across five target actions")
        else:
            liu=validate_liu_landmarks(profile,og,ob,liu_witness)
        phase(key+"-stun-tracks")
        stun_clips=[]
        for m in MOTIONS:
            raw=stuns[m["name"]]
            tracks=generate_tracks(profile,ng,nb,m,raw,masses,full_xml,base_xml,consensus,sun_blades=blades,liu_landmarks=liu)
            stun_clips.append(stun_clip(m,raw,tracks))
        from stage_cached_stun_release import NEW as STUN
        stage_stun[key]=dict(sha256=STUN[key]["sha256"],clips=profile["clips"]+stun_clips)
        phase(key+"-imperial-tracks")
        new_clips=[]
        for name,_,_,mirror in VARIANTS:
            anim=next(a for a in ng["animations"] if a["name"]==name)
            xml=full_xml if anim["extras"]["sourceMirroringSchemaSHA256"]==HURT_XML_SHA else base_xml
            m=dict(name=name,frames=71,sha256=SOURCE_RAW_SHA,mirrored=mirror)
            tracks=generate_tracks(profile,ng,nb,m,raw_victim,masses,full_xml,xml,consensus,sun_blades=blades,liu_landmarks=liu)
            new_clips.append(assemble_clip(clip,records,tracks,mirrored=mirror))
        stage_imperial[key]=new_clips
    phase("catalog-pins")
    return compose(catalog,stage_stun,stage_imperial)


def verify_candidates(stun, final, output=None):
    a,b=identity(stun)==STUN_CATALOG,identity(final)==FINAL_CATALOG
    if output is not None and a and b:
        write_private(fresh_output(Path(output)),final)
    return dict(stunCatalogVerified=a,finalCatalogVerified=b,
                candidateStunBytes=len(stun),candidateFinalBytes=len(final),
                written=bool(output is not None and a and b),appBuilt=False,published=False)
