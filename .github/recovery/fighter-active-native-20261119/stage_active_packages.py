"""Reuse four independently reviewed package generators without exposing their keys."""
import os
from pathlib import Path
import re
import subprocess
import sys
from assemble_active_assets import require

KEYS={"fighter-presentation":"FIGHTER_PRESENTATION_KEY",
      "fighter-source-trails":"FIGHTER_PRESENTATION_KEY",
      "sf3-distinct":"FIGHTER_LIU_MODEL_KEY","sf3":"FIGHTER_LIU_MODEL_KEY"}
HELPERS={"fighter-presentation":"fighter_presentation_assets","fighter-source-trails":"fighter_source_trails",
         "sf3-distinct":"fighter_sf3_distinct","sf3":"fighter_sf3_assets"}
DRIVER="""import importlib,sys
from pathlib import Path
repo,group,output,helper=sys.argv[1:]
repo,output=Path(repo),Path(output)
sys.path.insert(0,str(repo/'.github/scripts'))
module=importlib.import_module(helper)
if group in ('fighter-source-trails','fighter-presentation'):
    module.stage(output)
else:
    module.stage(repo/ '.github/private'/group,output)
"""
def canonical_rows(rows):
    return [dict(name=n,bytes=r["bytes"],sha256=r["sha256"]) for n,r in sorted(rows.items())]

def collect(repo,scratch,validated_manifests,keys):
    require(set(validated_manifests)==set(KEYS),"Unexpected package source groups")
    allowed_environment={n:os.environ[n] for n in ("PATH","HOME","LANG","LC_ALL","TMPDIR") if n in os.environ}
    result=[]
    for name,key in KEYS.items():
        require(re.fullmatch(r"[0-9a-f]{64}",keys.get(key,"")) is not None,"Expected protected package key")
        dest=Path(scratch)/name;dest.mkdir(mode=0o700)
        proc=subprocess.run([sys.executable,"-I","-B","-c",DRIVER,str(repo),name,str(dest),HELPERS[name]],
                    env=allowed_environment|{key:keys[key]},capture_output=True,timeout=180)
        require(proc.returncode==0,"Pinned package helper failed: "+name)
        result.append((dest,canonical_rows(validated_manifests[name])))
    return result
