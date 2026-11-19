"""Append only the original GLB channels, independently of profile regeneration."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import tempfile
import xml.etree.ElementTree as ET

import numpy as np
from append_cached_stun_motions import BONES, MOTIONS, PROFILES, validate_stun_append
from append_cached_imperial_passives import SOURCE_RAW_SHA, VARIANTS, validate_append
from stage_cached_stun_release import NEW as STUN
from stage_cached_imperial_passives import NEW as IMPERIAL
from stage_h17_floorfall_release import fresh_output, regular, write_private
from stage_h17_shared_root_release import glb_chunks
from sun_triad_assets import Writer, decode
from source_body_mirroring import body_rules, mirror_source_samples, sample_source_motion

SUN="Sun_DeadForestTriad_Ninjato.glb"

def require(ok,label):
    if not ok: raise ValueError(label)

def sha(raw): return hashlib.sha256(raw).hexdigest()

def exact(raw,pin):
    return (len(raw),sha(raw))==(pin['bytes'],pin['sha256'])

def writer(raw):
    g,_,b=glb_chunks(raw)
    w=Writer(); w.g=g; w.b=bytearray(b)
    return w

def node_columns(raw,w,source_ids):
    entries=ET.fromstring(raw).findall("./Bones/Bone")
    selected={int(x.attrib["ID"]):x.attrib["Name"] for x in entries if int(x.attrib["ID"]) in source_ids}
    require(set(selected)==set(source_ids) and len(set(selected.values()))==len(source_ids),"Unbound source IDs")
    by_name={}
    for i,node in enumerate(w.g["nodes"]):
        name=node.get("name")
        if name in selected.values():
            require(name not in by_name,"Ambiguous bone name")
            by_name[name]=i
    require(set(by_name)==set(selected.values()),"Old GLB does not contain all original bone names")
    return by_name,{selected[k]:j for j,k in enumerate(source_ids)}

def add(w,animation,times,name,index,p,q):
    n=w.g["nodes"][index]
    require(n.get("name")==name,"Wrong target node")
    for kind,values,width in (("translation",p,"VEC3"),("rotation",q,"VEC4")):
        i=len(animation["samplers"])
        animation["samplers"].append(dict(input=times,output=w.acc(values,width),interpolation="LINEAR"))
        animation["channels"].append(dict(sampler=i,target=dict(node=index,path=kind)))

def add_stun(w,xml,raws):
    names,columns=node_columns(xml,w,BONES)
    for info,raw in zip(MOTIONS,raws,strict=True):
        name,frames=info['name'],info['frames']
        require(exact(raw,info),"Wrong Stun TextAsset")
        arr=decode(raw)
        require(len(arr)==2 and arr[0]["frame_count"]==frames and [int(x) for x in arr[0]["bone_ids"]]==BONES,"Unexpected Stun schema")
        motion=arr[0]
        a=dict(name=name,samplers=[],channels=[],extras=dict(sourceSHA256=info["sha256"],
            sourceFrames=frames,sourceFPS=30,simulationHz=60,defaultMidFrames=1,
            previewFPS=30,sourceBytesRetainedInProfile=True))
        t=w.acc(np.arange(frames)/30.,"SCALAR")
        for bone,c in columns.items():
            p=motion["positions"][:,c].astype(float)*[.01,.01,-.01]
            if bone=="pelvis": p[:,[0,2]]=0
            q=motion["rotations"][:,c].astype(float)*[-1,-1,1,1]
            require((np.linalg.norm(q,axis=1)>1e-12).all(),"Zero source quaternion")
            q/=np.linalg.norm(q,axis=1)[:,None]
            for i in range(1,len(q)):
                if q[i-1]@q[i]<0:q[i]*=-1
            add(w,a,t,bone,names[bone],p,q)
        w.g["animations"].append(a)

def add_imperial(w,xml,raw):
    rules=body_rules(xml)
    require(sha(raw)==SOURCE_RAW_SHA,"Wrong Imperial TextAsset")
    arr=decode(raw)
    require(len(arr)==2 and arr[0]["frame_count"]==120 and len(arr[0]["bone_ids"])==58,"Unexpected Imperial schema")
    names,columns=node_columns(xml,w,[int(x) for x in arr[0]["bone_ids"]])
    p0,q0=sample_source_motion(arr[0],0,70)
    for name,_,_,mirrored in VARIANTS:
        p,q=(mirror_source_samples(p0,q0,columns,w.g["nodes"],names,rules) if mirrored else (p0,q0))
        p=p*[.01,.01,-.01]
        q=q*[-1,-1,1,1]
        p[:,columns["pelvis"],[0,2]]=0
        p,q=p.astype(np.float32).astype(float),q.astype(np.float32).astype(float)
        a=dict(name=name,samplers=[],channels=[],extras=dict(sourceSHA256=SOURCE_RAW_SHA,
             sourceFrames=120,sourceFirstIndex=0,sourceLastIndex=70,sourceFPS=30,simulationHz=60,
             bakedSamples=141,sourceMirroringApplied=mirrored,
             sourceMirroringSchemaSHA256=sha(xml) if mirrored else None,sourceBytesRetainedInProfile=True))
        t=w.acc(np.arange(141)/60.,"SCALAR")
        for bone,c in columns.items(): add(w,a,t,bone,names[bone],p[:,c],q[:,c])
        w.g["animations"].append(a)

def rebuild(old,sources,output):
    target=fresh_output(output)
    base=regular(old,32_000_000)
    require(sha(base)==PROFILES["sun"]["characterSHA"],"Wrong pre-Stun Sun GLB")
    folder=sources.resolve(strict=True)
    xmls=[regular(folder/f"mirror-{r}.xml",128_000) for r in ("553","608")]
    for x in xmls: body_rules(x)
    stun=[regular(folder/(row["name"]+".bytes"),100_000) for row in MOTIONS]
    imperial=regular(folder/"imperial_spear_heavy_slash_passive.bytes",1_000_000)
    os.umask(0o077)
    with tempfile.TemporaryDirectory(dir=target.parent,prefix=".sun-channels-") as scratch:
        temp=Path(scratch)/SUN
        first=writer(base)
        add_stun(first,xmls[0],stun)
        first.save(temp)
        post=temp.read_bytes()
        validate_stun_append(base,post,65)
        require(exact(post,STUN["sun"]),"Post-Stun GLB does not match published hash")
        for xml in xmls:
            w=writer(post)
            add_imperial(w,xml,imperial)
            w.save(temp)
            raw=temp.read_bytes()
            validate_append(post,raw,68)
            if exact(raw,IMPERIAL["sun"]):
                g,_,_=glb_chunks(raw)
                require(max(len(s["joints"]) for s in g["skins"])==87,"Wrong skeleton")
                write_private(target,raw)
                return {"exact":True,"actions":70,"joints":87,"modelSHA256":sha(raw),"profileRebuilt":False}
        raise ValueError("Neither reviewed mirror schema reproduced the final digest")

if __name__=="__main__":
    import sys
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("old",type=Path);p.add_argument("sources",type=Path);p.add_argument("output",type=Path)
    a=p.parse_args()
    try: print(json.dumps(rebuild(a.old.absolute(),a.sources,a.output.absolute())))
    except (ValueError,OSError) as e: print(str(e),file=sys.stderr);raise SystemExit(1)
