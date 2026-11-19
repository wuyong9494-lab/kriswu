"""Read one authenticated release descriptor and emit only a reconstruction receipt."""
import argparse
import base64
import io
import json
import os
from pathlib import Path
import stat
import sys
import tempfile
import zipfile

import fighter_base_recovery as crypto
import fighter_shared_root_native as shared
from completion_native_preflight import snapshot,metadata
import rebuild_release_stamp as release

KEY="FIGHTER_H17_D19_KEY"
REL=".github/private/fighter-h17-shared-root/manifest.json"
ENV={"GITHUB_ACTIONS":"true","GITHUB_REPOSITORY":"wuyong9494-lab/kriswu",
     "GITHUB_REF":"refs/heads/codex/fighter-visual-acceptance-20261113-1200",
     "GITHUB_EVENT_NAME":"push","GITHUB_RUN_ATTEMPT":"1"}

def check(ok):
    if not ok: raise ValueError("Pinned release input differs")

def inputs(repo):
    _, merged=metadata(repo)
    doc=json.loads(snapshot(repo/REL,maximum=2_100_000,sha256=crypto.MANIFESTS[REL],keep=True)["data"])
    found=[r for r in doc["payloadFiles"] if r["name"]==release.NAME]
    check(len(found)==1 and {k:found[0][k] for k in ("bytes","sha256")}==release.OLD_RELEASE)
    check(crypto.PAYLOADS[release.NAME]==(release.OLD_RELEASE["bytes"],release.OLD_RELEASE["sha256"]))
    item=doc["cipher"]; seal=(repo/REL).parent/item["name"]
    snapshot(seal,maximum=8_389_000,size=item["bytes"],sha256=item["sha256"])
    return doc,seal

def code():
    s=shared.GCM_SWIFT.replace("arguments.count == 5","arguments.count == 3").replace(
        '[(1, "fighter-h17-d19-v1", 134217728),\n                              (3, "fighter-h17-shared-root-delta-v1", 8388636)]',
        '[(1, "fighter-h17-shared-root-delta-v1", 8388636)]')
    check("fighter-h17-d19-v1" not in s and s.count("fighter-h17-shared-root-delta-v1")==1)
    return s.encode()

def verify(repo,source,seal,key):
    with tempfile.TemporaryDirectory(dir=Path(os.environ["RUNNER_TEMP"]).resolve(strict=True),prefix="release-proof-") as t:
        d=Path(t)
        clear,swift=(d/n for n in ("delta.zip","auth.swift"))
        crypto.write_new(swift,code())
        crypto.run(["swift",str(swift),str(seal),str(clear)],extra_env={KEY:key})
        key=""
        raw=crypto.raw_file(clear,8*1024**2)
        check(len(raw)==source["clearZIPBytes"] and release.hashlib.sha256(raw).hexdigest()==source["clearZIPSHA256"])
        with zipfile.ZipFile(io.BytesIO(raw)) as z:
            rows=[x for x in z.infolist() if x.filename==release.NAME]
            check(len(rows)==1 and rows[0].file_size==release.OLD_RELEASE["bytes"]
                  and stat.S_ISREG(rows[0].external_attr>>16) and not rows[0].flag_bits&1)
            with z.open(rows[0]) as f: old=f.read(release.OLD_RELEASE["bytes"]+1)
        p=d/release.NAME
        crypto.write_new(p,old)
        return release.verify(repo,p)

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("repo",type=Path);p.add_argument("--protected",action="store_true")
    a=p.parse_args();phase="scope"
    try:
        if a.protected:
            check(sys.platform=="darwin" and all(os.environ.get(k)==v for k,v in ENV.items()))
            k=os.environ.pop(KEY,"")
            check(len(k)==44 and len(base64.b64decode(k,validate=True))==32)
        else:
            check(KEY not in os.environ)
        phase="archive-pins"
        repo=a.repo.resolve(strict=True)
        source,seal=inputs(repo)
        code()
        if not a.protected:
            print(json.dumps({"pinned":True,"decrypted":False}));return
        phase="descriptor-replay"
        os.umask(0o077)
        result=verify(repo,source,seal,k)
        print(json.dumps(result))
    except Exception as e:
        print("Release receipt stopped at "+phase+" ("+type(e).__name__+"). No resource bytes emitted.",file=sys.stderr)
        raise SystemExit(1) from None

if __name__=="__main__":main()
