"""Open approved encrypted Sun inputs, reassemble one base GLB, and emit only a receipt."""
import argparse
import base64
import hashlib
import io
import json
import os
from pathlib import Path
import stat
import sys
import tempfile
import zipfile

import fighter_base_recovery as base_crypto
import fighter_h17_d19_native as base_loader
import fighter_shared_root_native as shared
import prepare_fighter_completion_delta as public
import verify_serpent_receipt as recipient
from rebuild_sun_glb_exact import rebuild, SUN

META_SHA = "cf87bf472b7f60daa9f667624513925463a36953304fad17aefd809438b0deac"
ENV={"GITHUB_ACTIONS":"true","GITHUB_REPOSITORY":"wuyong9494-lab/kriswu",
     "GITHUB_REF":"refs/heads/codex/fighter-visual-acceptance-20261113-1200",
     "GITHUB_EVENT_NAME":"push","GITHUB_RUN_ATTEMPT":"1"}
NAMES=frozenset(("h_stun_start.bytes","h_stun_loop.bytes","h_stun_end.bytes",
                 "imperial_spear_heavy_slash_passive.bytes","mirror-553.xml","mirror-608.xml"))
BASE_SHA="ce9e1b77c59fa63116af73409173fcd8922f2063ab2e0624534691fa00195ef6"


def need(ok):
    if not ok: raise ValueError("verified scope or bytes differ")


def matches(raw,row):
    return len(raw)==row["bytes"] and hashlib.sha256(raw).hexdigest()==row["sha256"]


def inspect(repo,archive,scratch):
    here=Path(__file__).resolve().parent
    m=public.regular(here/"input-pins.json",8000).read_bytes()
    need(public.digest(m)==META_SHA)
    pins=public.decode(m)
    need(pins["files"].keys()==NAMES)
    encoded=public.regular(here/"inputs.cms.b64",400_000).read_bytes()
    cipher=base64.b64decode(b"".join(encoded.splitlines()),validate=True)
    need(matches(cipher,pins["sealed"]))
    raw=public.regular(archive,8192).read_bytes()
    need(len(raw)==4184)
    art=recipient.exact_zip(raw,recipient.RECORDS,recipient.ARCHIVE_SHA)
    receipt=public.decode(art["recipient-report.json"])
    need(receipt["runID"]=="44029477961" and receipt["recipientSPKISHA256"]==public.RECIPIENT_SPKI)
    cert=scratch/"recipient-public.crt"; public.new_file(cert,art[cert.name]);public.certificate_spki(cert)
    rel=".github/private/fighter-h17-d19/manifest.json"
    manifest=public.regular(repo/rel,2_100_000).read_bytes()
    need(public.digest(manifest)==base_crypto.MANIFESTS[rel])
    base=base_loader.validate_release_manifest(public.decode(manifest))
    row=next(x for x in base["files"] if x["file"]==SUN)
    need(row["sha256"]==BASE_SHA and row["bytes"]==15_458_776)
    return pins,cipher,art,receipt,base,row


def source_members(raw,pins,folder):
    need(matches(raw,pins["clearZip"]))
    folder.mkdir(mode=0o700)
    with zipfile.ZipFile(io.BytesIO(raw)) as z:
        items=z.infolist()
        need(len(items)==len(NAMES) and {i.filename for i in items}==NAMES)
        for info in items:
            r=pins["files"][info.filename]
            need(info.file_size==r["bytes"] and not info.is_dir() and
                 stat.S_ISREG(info.external_attr>>16) and not info.flag_bits&1 and info.compress_type==zipfile.ZIP_DEFLATED)
            with z.open(info) as f: payload=f.read(r["bytes"]+1)
            need(matches(payload,r));public.new_file(folder/info.filename,payload)


def base_model(repo,scratch,base,row,key):
    sealed=scratch/"base.enc"; clear=scratch/"base.zip"
    base_loader.assemble_cipher(base,repo/".github/private/fighter-h17-d19",sealed)
    old=shared.GCM_SWIFT
    code=old.replace("arguments.count == 5","arguments.count == 3").replace(
        '[(1, "fighter-h17-d19-v1", 134217728),\n                              (3, "fighter-h17-shared-root-delta-v1", 8388636)]',
        '[(1, "fighter-h17-d19-v1", 134217728)]')
    need(old!=code and "shared-root-delta" not in code)
    swift=scratch/"decrypt-base.swift";base_crypto.write_new(swift,code.encode())
    base_crypto.run(["swift",str(swift),str(sealed),str(clear)],extra_env={recipient.KEY:key})
    whole=base_crypto.raw_file(clear,128*1024**2)
    need(len(whole)==base["clearZIPBytes"] and public.digest(whole)==base["clearZIPSHA256"])
    with zipfile.ZipFile(io.BytesIO(whole)) as z:
        rows=[x for x in z.infolist() if x.filename==SUN]
        need(len(rows)==1 and rows[0].file_size==row["bytes"] and not rows[0].flag_bits&1
             and stat.S_IFMT(rows[0].external_attr>>16) in (0,stat.S_IFREG))
        with z.open(rows[0]) as f: raw=f.read(row["bytes"]+1)
    need(matches(raw,row))
    model=scratch/"old.glb";public.new_file(model,raw)
    clear.unlink(); sealed.unlink()
    return model


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("repo",type=Path);p.add_argument("recipient_archive",type=Path)
    p.add_argument("--protected",action="store_true")
    a=p.parse_args(); phase="scope"
    try:
        if a.protected:
            need(sys.platform=="darwin" and all(os.environ.get(k)==v for k,v in ENV.items()))
            wrap=os.environ.pop(recipient.KEY,"")
            recipient.recipient.resource_key(wrap)
        else:
            need(recipient.KEY not in os.environ)
        os.umask(0o077)
        with tempfile.TemporaryDirectory(dir=Path(os.environ.get("RUNNER_TEMP",tempfile.gettempdir())).resolve(strict=True),prefix="sun-protected-") as t:
            d=Path(t);repo=a.repo.resolve(strict=True)
            phase="source-pins"
            pins,sealed,art,receipt,base,row=inspect(repo,a.recipient_archive,d)
            if not a.protected:
                print(json.dumps({"encryptedInputsChecked":len(pins["files"]),"decrypted":False}));return
            phase="source-capsule"
            key=recipient.unwrap(d,art["recipient-private.pkcs8.enc"],receipt["wrappedKeyHMACSHA256"],wrap,public.RECIPIENT_SPKI)
            cms=d/"inputs.cms";public.new_file(cms,sealed)
            clear=public.command([public.openssl(),"cms","-decrypt","-binary","-inform","DER","-in",str(cms),"-inkey",str(key),"-passin","pass:"],maximum=400_000)
            key.unlink()
            source_members(clear,pins,d/"sources")
            phase="baseline-model"
            old=base_model(repo,d,base,row,wrap)
            wrap=""
            phase="exact-rebuild"
            rec=rebuild(old,d/"sources",d/"rebuilt.glb")
            print(json.dumps({**rec,"installed":False,"published":False}))
    except Exception as e:
        allowed={"Old GLB does not contain all original bone names","Post-Stun GLB does not match published hash","Neither reviewed mirror schema reproduced the final digest","Wrong skeleton"}
        detail=str(e) if str(e) in allowed else type(e).__name__
        print(f"Sun rebuild stopped during {phase}: {detail}. No resource bytes emitted.",file=sys.stderr)
        raise SystemExit(1) from None


if __name__=="__main__":
    main()
