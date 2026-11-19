"""Verify four additional asset packages in an approved runner; emit counts only."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

from reconcile_remaining import (CANDIDATE, INVENTORY, INVENTORY_SHA, PRIVATE,
                                 checked_packages, identity, must, pinned, read, rows_by_name, sha)

REPO = "wuyong9494-lab/kriswu"
BRANCH = "refs/heads/codex/fighter-visual-acceptance-20261113-1200"
PATH = ".github/scripts"
KEY = {"fighter-presentation":"FIGHTER_PRESENTATION_KEY",
       "fighter-source-trails":"FIGHTER_PRESENTATION_KEY",
       "sf3-distinct":"FIGHTER_LIU_MODEL_KEY", "sf3":"FIGHTER_LIU_MODEL_KEY"}
HELPER = {"fighter-presentation":"fighter_presentation_assets.py",
          "fighter-source-trails":"fighter_source_trails.py",
          "sf3-distinct":"fighter_sf3_distinct.py", "sf3":"fighter_sf3_assets.py"}
COUNT = {"fighter-presentation":8,"fighter-source-trails":1,"sf3-distinct":52,"sf3":3}
DRIVER = """
import importlib,sys
from pathlib import Path
repo,group,output,helper = sys.argv[1:]
repo,output = Path(repo),Path(output)
sys.path.insert(0,str(repo/'.github/scripts'))
module = importlib.import_module(helper.removesuffix('.py'))
if group in ('fighter-source-trails','fighter-presentation'):
    module.stage(output)
else:
    module.stage(repo / '.github/private' / group, output)
"""


def selected(repo, plan):
    metadata, sources = checked_packages(repo)
    target = rows_by_name(json.loads(read(repo / INVENTORY, 200_000, 75_826, INVENTORY_SHA))["compiledFiles"],"name")
    plan = json.loads(read(plan,200_000))
    must(plan["candidate"] == CANDIDATE and set(plan["cipherPackages"]) == set(KEY),
         "Wrong reconciliation")
    expected = {}
    for group in KEY:
        supplied = plan["cipherPackages"][group]
        must(supplied["manifestSHA256"] == sources[group]["manifestSHA256"], "Package not pinned")
        names = supplied["pendingClearVerification"]
        must(len(names) == len(set(names)) == COUNT[group],"Unexpected remaining count")
        must(all(n in target and n in metadata[group] and identity(target[n])==identity(metadata[group][n])
                 for n in names),"Unmatched target name")
        expected[group] = {n:target[n] for n in names}
        pinned(repo,Path(PATH)/HELPER[group])
    pinned(repo,Path(PATH)/"fighter_private_model.py")
    must(len(set().union(*(set(x) for x in expected.values()))) == 64,"Duplicate names across groups")
    return expected


def check_staged(output, rows):
    for n,row in rows.items():
        read(output/n,80_000_000,*identity(row))
    return len(rows)


def take_key(group):
    must(all(os.environ.get(k)==v for k,v in {"GITHUB_ACTIONS":"true","GITHUB_REPOSITORY":REPO,
             "GITHUB_REF":BRANCH,"GITHUB_EVENT_NAME":"push","GITHUB_RUN_ATTEMPT":"1"}.items()),
         "Approved runner required")
    k = KEY[group]
    value = os.environ.pop(k,"")
    must(re.fullmatch(r"[a-f0-9]{64}",value) is not None,"Approved package key unavailable")
    return value


def protected(group, repo, rows, value):
    k = KEY[group]
    env = {name:os.environ[name] for name in ("PATH","HOME","LANG","LC_ALL","TMPDIR") if name in os.environ}
    env[k] = value
    value = ""
    os.umask(0o077)
    with tempfile.TemporaryDirectory(prefix="fighter-followup-",dir=Path(os.environ["RUNNER_TEMP"]).resolve(strict=True)) as temp:
        output = Path(temp)/"files"
        output.mkdir(mode=0o700)
        result = subprocess.run([sys.executable,"-I","-B","-c",DRIVER,str(repo),group,str(output),HELPER[group]],
                                env=env,capture_output=True,timeout=180)
        del env[k]
        must(result.returncode==0,"Pinned package authenticator failed")
        return check_staged(output,rows)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("repo",type=Path)
    p.add_argument("plan",type=Path)
    p.add_argument("--protected-group",choices=sorted(KEY))
    a=p.parse_args()
    try:
        key = take_key(a.protected_group) if a.protected_group else None
        repo=a.repo.resolve(strict=True)
        names=selected(repo,a.plan)
        if a.protected_group:
            g=a.protected_group
            print(json.dumps({"group":g,"newExactFiles":protected(g,repo,names[g],key),"published":False}))
        else:
            print(json.dumps({"withoutKeys":True,"pinnedTargetCounts":{k:len(v) for k,v in names.items()}}))
    except (ValueError, OSError, subprocess.SubprocessError, KeyError):
        print("Follow-up did not verify; no decrypted data emitted.",file=sys.stderr)
        raise SystemExit(1) from None


if __name__=="__main__":
    main()
