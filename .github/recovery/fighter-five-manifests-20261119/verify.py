"""Authenticate two pinned containers and reconstruct only five manifests."""
import argparse
import base64
import gzip
import hashlib
import io
import json
import os
from pathlib import Path
import stat
import sys
import tempfile
import zipfile
import zlib

import fighter_base_recovery as crypto
import fighter_h17_d19_native as legacy
import fighter_shared_root_native as shared
from completion_native_preflight import snapshot

KEY="FIGHTER_H17_D19_KEY"
ENV={"GITHUB_ACTIONS":"true","GITHUB_REPOSITORY":"wuyong9494-lab/kriswu",
     "GITHUB_REF":"refs/heads/codex/fighter-visual-acceptance-20261113-1200",
     "GITHUB_EVENT_NAME":"push","GITHUB_RUN_ATTEMPT":"1"}
BINDINGS={"SF3WE_Target_Trails.json":("sun","liu"),"SF3_H17_Audio.json":("sun","liu"),
          "SF3_H17_Summons.json":("sun",),"SF3_H17_Effects.json.gz":("sun",),"SF3_H17_Morph.json":("sun","liu")}
DELTA=frozenset(("SF3WE_Target_Trails.json","SF3_H17_Audio.json","SF3_H17_Morph.json"))
CHAIN={
 "sun":("ce9e1b77c59fa63116af73409173fcd8922f2063ab2e0624534691fa00195ef6","9513c85028541fe514f552a5e0d11fd01df277b8cd9f8ddeb832508ff975c699","7c9ebfe285f637cbd002f717d80b859a57d3ab11ef491f15930dc4f3eb50d96a"),
 "liu":("a3aada76d336b9c4f9bda3904b5e947711d916f683a2dcbf7b8184377e01a517","66f8a748efb431bb28bdcd5e4cd91bc2d5d374fd456eb00e843f5d6590a26bfe","d873864549fd7c7c3f2e9450aba12725c1d488f68ccf5c775ef5e889a4c4fe80"),
}
MAX=200_000_000


def require(ok):
    if not ok:
        raise ValueError("fixed input contract differed")


def identity(raw,row):
    return len(raw)==row["bytes"] and hashlib.sha256(raw).hexdigest()==row["sha256"]


def zip_only(data, archive_pin, selected, expected_count=None):
    require(len(data)==archive_pin["clearZIPBytes"] and
            hashlib.sha256(data).hexdigest()==archive_pin["clearZIPSHA256"])
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        infos=z.infolist()
        require(len({m.filename for m in infos})==len(infos))
        require(expected_count is None or len(infos)==expected_count)
        seen={m.filename:m for m in infos}
        result={}
        for name,row in selected.items():
            item=seen[name]
            require(item.file_size==row["bytes"] and not item.is_dir()
                    and stat.S_IFMT(item.external_attr>>16) in (0,stat.S_IFREG) and not item.flag_bits&1
                    and item.compress_type in (zipfile.ZIP_STORED,zipfile.ZIP_DEFLATED))
            with z.open(item) as f:
                raw=f.read(row["bytes"]+1)
            require(identity(raw,row))
            result[name]=raw
        return result


def rebuild(raw,name):
    if name.endswith(".gz"):
        decoder=zlib.decompressobj(16+zlib.MAX_WBITS)
        raw=decoder.decompress(raw,MAX+1)
        require(len(raw)<=MAX and decoder.eof and not decoder.unused_data and not decoder.unconsumed_tail)
    for offset in (0,1):
        for model in BINDINGS[name]:
            old,new=(x.encode() for x in CHAIN[model][offset:offset+2])
            require(raw.count(old)==1 and new not in raw)
            raw=raw.replace(old,new)
    if not name.endswith(".gz"):
        return [raw]
    packed=gzip.compress(raw,compresslevel=9,mtime=0)
    require(packed[:3]==b"\x1f\x8b\x08" and len(packed)>18)
    # Python 3.11/3.12 can emit the platform OS byte for mtime=0; newer
    # versions emit 255. Both remain candidates, only a full pin can pass.
    return list({packed[:9]+bytes([osmark])+packed[10:] for osmark in (3,255)})


def inputs(repo):
    pins=json.loads(Path(__file__).with_name("manifest-replay-pins.json").read_bytes())
    require(pins.keys()==BINDINGS.keys())
    path=repo/".github/private/fighter-completion-20261117/completion-compiled-inventory.json"
    inv=json.loads(snapshot(path,maximum=100_000,sha256="4c8984617203134c7bf3328f3a6e41520bb823063f94d37013cae11839bc97a1",keep=True)["data"])
    rows={r["name"]:r for r in inv["compiledFiles"]}
    for n,v in pins.items():
        require(v["target"]==rows[n] and v["historical"]["name"]==n and
                crypto.PAYLOADS[n]==(v["historical"]["bytes"],v["historical"]["sha256"]))
    a=repo/".github/private/fighter-h17-d19"
    b=repo/".github/private/fighter-h17-shared-root"
    m=[]
    for f in (a/"manifest.json",b/"manifest.json"):
        sha=crypto.MANIFESTS[f.relative_to(repo).as_posix()]
        m.append(json.loads(snapshot(f,maximum=2_100_000,sha256=sha,keep=True)["data"]))
    base,delta=legacy.validate_release_manifest(m[0]),m[1]
    for pack,names in (({r["file"]:r for r in base["files"]},set(pins)-DELTA),
                       ({r["name"]:r for r in delta["payloadFiles"]},DELTA)):
        for n in names:
            require(all(pack[n][k]==pins[n]["historical"][k] for k in ("bytes","sha256")))
    return pins,a,b,base,delta


def execute(repo,prepared,key):
    pins,a,b,base,delta=prepared
    root=Path(os.environ["RUNNER_TEMP"]).resolve(strict=True)
    with tempfile.TemporaryDirectory(prefix="fighter-five-replay-",dir=root) as t:
        d=Path(t)
        ci,cl,dl,sw=(d/n for n in ("base.enc","base.zip","delta.zip","auth.swift"))
        legacy.assemble_cipher(base,a,ci)
        row=delta["cipher"]
        dc=b/row["name"]
        snapshot(dc,maximum=8_389_000,size=row["bytes"],sha256=row["sha256"])
        crypto.write_new(sw,shared.GCM_SWIFT.encode())
        crypto.run(["swift",str(sw),str(ci),str(cl),str(dc),str(dl)],extra_env={KEY:key})
        key=""
        selected={n:p["historical"] for n,p in pins.items()}
        data=zip_only(crypto.raw_file(cl,128*1024**2),base,{n:selected[n] for n in selected.keys()-DELTA},295)
        data.update(zip_only(crypto.raw_file(dl,8*1024**2),delta,{n:selected[n] for n in DELTA},14))
        return {name:any(identity(x,pins[name]["target"]) for x in rebuild(raw,name)) for name,raw in data.items()}


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("repo",type=Path)
    p.add_argument("--protected",action="store_true")
    a=p.parse_args()
    phase="scope"
    try:
        if a.protected:
            require(sys.platform=="darwin" and all(os.environ.get(k)==v for k,v in ENV.items()))
            key=os.environ.pop(KEY,"")
            require(len(key)==44 and len(base64.b64decode(key,validate=True))==32)
        else:
            require(KEY not in os.environ)
        phase="source-pins"
        repo=a.repo.resolve(strict=True)
        prepared=inputs(repo)
        if a.protected:
            phase="authenticated-replay"
            os.umask(0o077)
            result=execute(repo,prepared,key)
            print(json.dumps({"compared":len(result),"exact":sum(result.values()),"results":result,"published":False}))
        else:
            print(json.dumps({"pinnedSourceInputs":len(prepared[0]),"decrypted":False}))
    except Exception:
        print("Five-manifest verification stopped at "+phase+"; no private bytes emitted.",file=sys.stderr)
        raise SystemExit(1) from None


if __name__=="__main__":
    main()
