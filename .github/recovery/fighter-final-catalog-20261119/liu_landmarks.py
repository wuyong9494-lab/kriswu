"""Authenticate legacy Liu weapon vertex identities and test archived tracks."""
import hashlib
import json
import math

import numpy as np

from append_cached_stun_motions import weapon_sampler
from endpoint_consensus import animation_samples
from sun_triad_assets import world_poses

WITNESS_SHA="074b5d7d762369389c30070daff8a4a673426136225de3d9f5858609d5096fd3"
WITNESS_SIZE=213
READBACK_LIMIT=2e-6
SIDES=(("left","L"),("right","R"))
ENDS=(("base","Base"),("tip","Tip"))

def need(ok,message):
    if not ok:
        raise ValueError(message)

def validate_rows(data):
    need(isinstance(data,dict) and set(data)=={"left","right"},"Liu landmark side closure differs")
    for row in data.values():
        need(isinstance(row,dict) and set(row)=={"mesh","baseVertex","tipVertex","bindLength"}
             and type(row["mesh"]) is str and len(row["mesh"]) in range(1,128)
             and all(type(row[k]) is int and row[k]>=0 for k in ("baseVertex","tipVertex"))
             and row["baseVertex"]!=row["tipVertex"]
             and type(row["bindLength"]) in (float,int) and math.isfinite(row["bindLength"])
             and row["bindLength"]>0,"Invalid Liu landmark record")
    return data

def decode_landmark_witness(raw_bytes):
    need(len(raw_bytes)==WITNESS_SIZE and hashlib.sha256(raw_bytes).hexdigest()==WITNESS_SHA,
         "Liu landmark witness pin differs")
    return validate_rows(json.loads(raw_bytes))

def core_rows(a):
    return {side:{k:row[k] for k in ("mesh","baseVertex","tipVertex")} for side,row in a.items()}

def validate_liu_landmarks(profile,historic_g,historic_b,fallback_landmarks):
    need(profile.get("id")=="liu_hammers","Wrong Liu source profile")
    expected=validate_rows(fallback_landmarks)
    declared=profile.get("weaponLandmarks")
    if declared is not None:
        need(core_rows(validate_rows(declared))==core_rows(expected),"Archived Liu landmark alias is not identical")
    landmarks=expected if declared is None else declared
    g,b=historic_g,historic_b
    names={x["name"]:i for i,x in enumerate(g["nodes"])}
    sample=weapon_sampler(g,b,dict(profile,weaponLandmarks=landmarks),names)
    _,rest,parents=world_poses(g["nodes"])
    animations={a["name"]:a for a in g["animations"]}
    clips=profile["clips"]
    need(len(animations)==len(g["animations"])==len(clips) and len(clips)>=50
         and set(animations)=={c["name"] for c in clips},"Liu motion inventory differs")
    for c in clips:
        anim=animations[c["name"]]
        need(anim.get("extras",{}).get("sourceSHA256")==c["sha256"],"Archived Liu motion digest differs")
        frames=c["frames"]; tracks=c["tracks"]; ticks=2*frames-1
        need(type(frames) is int and 0<frames<=2000 and tracks.get("samplesPerSourceFrame")==2,
             "Archived Liu motion clock differs")
        want={}
        for side,letter in SIDES:
            for end,label in ENDS:
                values=np.asarray(tracks["weapon"+label+letter])
                need(values.shape==(ticks,3) and np.isfinite(values).all(),"Invalid archived Liu track length")
                want[side,end]=values
        for tick,world in enumerate(animation_samples(g,b,anim,frames,range(ticks),rest,parents,oriented=False)):
            for key,values in want.items():
                error=float(abs(sample(*key,world)-values[tick]).max())
                need(math.isfinite(error) and error<READBACK_LIMIT,"Archived Liu weapon vertex readback differs")
    return landmarks
