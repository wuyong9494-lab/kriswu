"""Validate and join the three reviewed encrypted local fragments, without keys."""
import hashlib
import json
from pathlib import Path
from assemble_active_assets import read,key,require,index

PARTS=("rift-active-local-000.cms.part","rift-active-local-001.cms.part","rift-active-local-002.cms.part")

def pinned_plan(path,digest,bound):
    p=Path(path)
    require(p.is_file() and not p.is_symlink() and 0<p.stat().st_size<=bound,"Plan unavailable")
    data=p.read_bytes()
    require(hashlib.sha256(data).hexdigest()==digest,"Plan digest differs")
    return json.loads(data)

def check_plan(active,local_model):
    manifest=index(active)
    local=local_model["files"]
    require(local_model["active"]==len(active)==539 and local_model["localOnly"]==len(local)==157,"Wrong active/local count")
    require(len(index(local))==157 and all(manifest.get(r["name"])==r for r in local),"Local file inventory differs")
    require(sum(r["bytes"] for r in local)==103174495==local_model["localBytes"],"Wrong local exact byte total")
    return local

def concatenate(folder,plan,out=None):
    require(len(plan["parts"])==len(PARTS) and tuple(r["name"] for r in plan["parts"])==PARTS,"Wrong ciphertext object closure")
    h=hashlib.sha256();size=0
    for r in plan["parts"]:
        require(r["bytes"]<=20_000_000,"Ciphertext object exceeds bound")
        raw=read(r,Path(folder)/r["name"])
        if out is not None:out.write(raw)
        h.update(raw);size+=len(raw)
    require((size,h.hexdigest())==key(plan),"Ciphertext assembled identity differs")
    return size
