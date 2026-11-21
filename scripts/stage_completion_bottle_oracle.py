"""Stage the reviewed independent D13 comparator into SiteTests only."""
import argparse
import json
import math
import os
from pathlib import Path

from completion_native_preflight import snapshot, nonsymlink, require, CheckError

NAME="Validation_D13_Bottle_Source_Oracle.json"
DIGEST="798549c83ba5f18b04a4568320600506e34cd301a32ea23a27fa5edb58d937a4"
MODEL="5ccf41b00f10b3e504012a33e8f6212c7935a2ff4ac65b831eedfab2d91626cd"
PROFILE="ca44aec355d6c70487df550a818112172a897bc64a0bbaa143748045a8284e53"


def valid(raw):
    d=json.loads(raw)
    require(d["schema"]=="d13-bottle-presentation-source-oracle-v1" and d["modelSHA256"]==MODEL
            and d["profileSHA256"]==PROFILE,"oracle-identity","Wrong D13 oracle identity")
    rows=d["samples"]
    require(len(rows)==49 and all(type(r["tick"]) is int and r["tick"]==i
                and all(len(r[k])==3 and all(type(v) in (int,float) and math.isfinite(v) for v in r[k])
                        for k in ("root","left","right"))
                for i,r in enumerate(rows)),"oracle-samples","Wrong D13 time or pose sample shape")


def stage(source,repo):
    raw=snapshot(source,maximum=16_000,size=9607,sha256=DIGEST,keep=True)["data"]
    valid(raw)
    testdir=nonsymlink(repo/"Tests")
    dest=testdir/"PrivateResourceValidation"
    dest.mkdir(mode=0o700,exist_ok=True)
    nonsymlink(dest)
    target=dest/NAME
    if target.exists():
        snapshot(target,maximum=16_000,size=9607,sha256=DIGEST)
    else:
        with os.fdopen(os.open(target,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600),"wb") as f:
            f.write(raw)
        snapshot(target,maximum=16_000,size=9607,sha256=DIGEST)
    return {"testTarget":"SiteTests","verifiedSamples":49,"historicalFileRecovered":False,
            "nativeTestsRun":False,"includedInApp":False}


if __name__=="__main__":
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("source",type=Path)
    p.add_argument("--repo",type=Path,default=Path(__file__).resolve().parents[1])
    a=p.parse_args()
    try: print(json.dumps(stage(a.source,a.repo)))
    except (OSError,ValueError,CheckError,KeyError) as e: p.exit(1,f"Pinned test oracle rejected: {e}\n")
