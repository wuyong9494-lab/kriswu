"""Rebuild candidate Stun and Imperial track rows from authenticated GLB keys.
The final catalog byte pin is the acceptance authority, not this calculation.
"""
from __future__ import annotations
import base64
import hashlib
import numpy as np

from endpoint_consensus import animation_samples
from sun_triad_assets import RIGHT, capsule_point, decode, world_poses
from sun_triad_source_bones import capsule_binding, parse_bones_data
from source_body_mirroring import body_rules, mirror_source_samples, sample_source_motion
from append_cached_root_victim_motions import weighted_center
from append_cached_stun_motions import BONES, BUNDLE, MOTIONS, weapon_sampler
from append_cached_imperial_passives import VARIANTS, SOURCE_RAW_SHA
from stage_h17_floorfall_release import require

XYZ = [.01,.01,-.01]
HURT_XML_SHA = "5fbd5b097b318b58cddef0d63dd94e1addd931882124ad05a3dd9712f0d0ecd8"
BONES_XML_SHA = "0a5e4b58c5900ddf0bc9a019305b72f628919a4562050349e5f3ee3809e6e455"
LIMBS = (("handL","hand_l"),("handR","hand_r"),("footL","foot_l"),("footR","foot_r"))
WEAPON_FIELDS = ("weaponBaseL","weaponTipL","weaponBaseR","weaponTipR")
STUN_FIELDS = ("root", *[key for key,_ in LIMBS], *WEAPON_FIELDS, "groundLift", "pelvis", "centerOfMass")
IMPERIAL_FIELDS = ("root", *[key for key,_ in LIMBS], "toeL", "toeR", *WEAPON_FIELDS,
                   "groundLift", "pelvis", "centerOfMass")


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def original_roots(raw, info, g, names, xml):
    motion, _ = decode(raw)
    ids = [int(x) for x in motion["bone_ids"]]
    require(len(ids)==len(set(ids)) and ids.count(0) == 1, "Original pelvis source ID differs")
    columns = ids.index(0)
    if "mirrored" not in info:
        require(ids == BONES and motion["frame_count"] == info["frames"], "Stun source contract differs")
        source = motion["positions"][:,columns].astype(float) * XYZ
        return np.array([source[i//2]*(1-(i%2)*.5)+source[min(i//2+1,len(source)-1)]*((i%2)*.5)
                         for i in range(2*len(source)-1)]), source
    require(motion["frame_count"]==120 and len(ids)==58, "Imperial source contract differs")
    p,q = sample_source_motion(motion,0,70)
    if info["mirrored"]:
        names_xml = parse_bones_data(xml)["bones"]
        cols = {names_xml[i]: k for k, i in enumerate(ids)}
        require(cols.get("pelvis")==columns, "Mirror pelvis source ID differs")
        p,_ = mirror_source_samples(p,q,cols,g["nodes"],names,body_rules(xml))
    return p[:,columns]*XYZ, None


def original_hurt_shapes(profile, full_xml, names):
    require(sha(full_xml)==HURT_XML_SHA,"Unreviewed full-body XML")
    declarations = parse_bones_data(full_xml)["capsules"]
    target = [capsule_binding(c,"hurt") for c in declarations]
    require(len(target)==15 and all(c[end]["bone"] in names for c in declarations for end in ("base","tip")),
            "Unexpected original hurt capsule inventory")
    refs = [c["tracks"]["hurtCapsules"] for c in profile["clips"] if "hurtCapsules" in c["tracks"]]
    require(bool(refs), "Original catalog lacks hurt tracks")
    require(all([{k:r[k] for k in ("id","radiusMillimeters","defense")} for r in group] == target for group in refs),
            "Historical catalog hurt capsule order or definitions differ")
    return declarations


def generate_tracks(profile, g, b, info, raw, masses, full_xml, mirror_xml, consensus):
    name,frames = info["name"],info["frames"]
    is_imperial = "mirrored" in info
    names = {n["name"]:i for i,n in enumerate(g["nodes"])}
    rest_world,rest,parents = world_poses(g["nodes"])
    require(all(sum(n["name"]==k for n in g["nodes"])==1 for k in ("pelvis", "foot_l","foot_r","toe_l","toe_r")),
            "Duplicate joint identity")
    matching = [a for a in g["animations"] if a["name"]==name]
    require(len(matching)==1 and sha(raw)==info["sha256"]==matching[0]["extras"]["sourceSHA256"],
            "Source action digest differs")
    anim = matching[0]
    if info.get("mirrored"):
        require(sha(mirror_xml)==anim["extras"]["sourceMirroringSchemaSHA256"],"GLB and source mirror schema differ")
    basis = RIGHT[:3,:3] @ rest_world[parents[names["pelvis"]]][:3,:3]
    root_samples, keys30 = original_roots(raw,info,g,names,mirror_xml)
    count=2*frames-1
    require(root_samples.shape == (count,3),"Unexpected root sample count")
    if keys30 is not None:
        # The historical Stun writer applies the basis to 30 Hz root keys
        # before interpolation; interpolating in source space first can change bytes.
        key_delta=(keys30-keys30[0])@basis.T
        roots=[key_delta[i//2]*(1-(i%2)*.5)+key_delta[min(i//2+1,len(key_delta)-1)]*((i%2)*.5)
               for i in range(count)]
    else:
        roots=(root_samples-root_samples[0])@basis.T
    weapons=weapon_sampler(g,b,profile,names)
    shapes=original_hurt_shapes(profile,full_xml,names)
    hurt=[dict(**capsule_binding(c,"hurt"),base=[],tip=[]) for c in shapes]
    fields = IMPERIAL_FIELDS if is_imperial else STUN_FIELDS
    tracks={k:[] for k in fields}
    tracks["samplesPerSourceFrame"]=2
    markers=[]
    for side in ("l","r"):
        foot,toe=names["foot_"+side],names["toe_"+side]
        a,z=rest_world[foot][:3,3],rest_world[toe][:3,3]
        for x in (min(a[0],z[0])-.055,max(a[0],z[0])+.055):
            for zz in (min(a[2],z[2])-.055,max(a[2],z[2])+.055):
                markers.append((foot,np.linalg.inv(rest_world[foot])@[x,-.02,zz,1]))
    for i,world in enumerate(animation_samples(g,b,anim,frames,range(count),rest,parents,oriented=False)):
        tracks["root"].append(roots[i])
        limbs=LIMBS+(("pelvis","pelvis"),)+((("toeL","toe_l"),("toeR","toe_r")) if is_imperial else ())
        for field,bone in limbs:
            tracks[field].append((RIGHT@world[names[bone]][:,3])[:3])
        tracks["centerOfMass"].append(weighted_center(world,masses))
        for side,letter in (("left","L"),("right","R")):
            for end,label in (("base","Base"),("tip","Tip")):
                tracks["weapon"+label+letter].append(weapons(side,end,world))
        for source,shape in zip(shapes,hurt,strict=True):
            for end in ("base","tip"):
                shape[end].append(capsule_point(source[end],world,names))
        low=min((world[bone]@point)[1] for bone,point in markers)
        tracks["groundLift"].append(float(max(0.,-.035-low)))
    tracks={k:np.round(v,7).tolist() if isinstance(v,list) else v for k,v in tracks.items()}
    for row in hurt:
        for end in ("base","tip"):
            row[end]=np.round(row[end],7).tolist()
    if profile["id"]=="sun_triad":
        historic=next(c["tracks"]["collisionEdges"] for c in profile["clips"] if "collisionEdges" in c["tracks"])
        require(len(historic)==4,"Unexpected historical Sun weapon count")
        tracks["collisionEdges"]=[]
        for edge in historic:
            row={k:edge[k] for k in ("id","radiusMillimeters","side")}
            for end in ("base","tip"):
                values=consensus[name,edge["id"],end]
                require(len(values)==count,"Weapon endpoint sample count differs")
                row[end]=values
            tracks["collisionEdges"].append(row)
    tracks["hurtCapsules"]=hurt
    return tracks


def stun_clip(info, raw, tracks):
    require(len(raw)==info["bytes"] and sha(raw)==info["sha256"],"Wrong Stun source")
    return dict(name=info["name"],frames=info["frames"],sha256=info["sha256"],bundle=BUNDLE,
                sourcePathID=str(info["path_id"]),sourceBytesBase64=base64.b64encode(raw).decode(),
                sourceArrayCount=2,sourceBoneIDs=BONES,tracks=tracks)


def specs():
    return ({m["name"]:(m["sha256"],m["frames"]) for m in MOTIONS}
            | {name:(SOURCE_RAW_SHA,71) for name,*_ in VARIANTS})
