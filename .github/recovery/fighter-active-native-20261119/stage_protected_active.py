"""Stage the reviewed 539 files in one restricted job. No signing or publishing."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

from assemble_active_assets import active_inventory,extract_local_archive,require,stage_new
from active_pack_parts import pinned_plan,check_plan,concatenate
from reconcile_remaining import checked_packages
import verify_catalog_protected as catalog_proof
import verify_protected as sun_proof
import verify_serpent_receipt as recipient
import fighter_base_recovery as crypto
import fighter_h17_d19_native as legacy
import fighter_shared_root_native as shared
import prepare_fighter_completion_delta as prep
import stage_fighter_completion_delta as serpent_stage
from assemble_from_archives import WITNESS
from liu_landmarks import decode_landmark_witness
from replay_active_historical import rebuild_derived
import stage_active_packages

PLAN_NAMES=("local-only-plan.json","local-only-cipher-plan.json")
PLAN_HASHES=("aec349ebc07b1325e8118c4cab0de11316237aba439e7fcf329524bed8523692","513a929c0c754318b32e5c03e0bfa7cfd8893a229c86090475d8cdd85c9d5e5f")
SOURCE_NAME="fighter-completion-20261117"
ORACLE_CIPHER=(10178,"25630a203467e36a1043d0e3b52e22b0e7d20871e1f8887df579f00a240bfe2a")
ENVIRONMENT={"GITHUB_ACTIONS":"true","GITHUB_REPOSITORY":"wuyong9494-lab/kriswu",
             "GITHUB_REF":"refs/heads/codex/fighter-visual-acceptance-20261113-1200",
             "GITHUB_EVENT_NAME":"push","GITHUB_RUN_ATTEMPT":"1"}

def authenticated_scope(protected):
    if not protected:
        require(not any(k in os.environ for k in shared.KEY_NAMES),"Unexpected key during metadata check")
        return {}
    require(sys.platform=="darwin" and all(os.environ.get(k)==v for k,v in ENVIRONMENT.items()),
            "Expected approved one-shot macOS runner")
    keys={k:os.environ.pop(k,"") for k in shared.KEY_NAMES}
    require(all(keys.values()),"Protected resource inputs unavailable")
    recipient.recipient.resource_key(keys[recipient.KEY])
    return keys

def digest_file(p):
    with p.open("rb") as f:return hashlib.file_digest(f,"sha256").hexdigest()

def prepare(repo,parts,plans,recipient_archive,scratch):
    rows,digest=active_inventory(repo)
    plan,cipher_plan=[pinned_plan(plans/n,h,100_000) for n,h in zip(PLAN_NAMES,PLAN_HASHES,strict=True)]
    local=check_plan(rows,plan)
    require(digest==plan["activeContentSHA256"],"Wrong active inventory")
    concat=scratch/"active-local.cms"
    with concat.open("xb") as out:concatenate(parts,cipher_plan,out)
    packs,_=checked_packages(repo)
    s=scratch/"sun-pins";s.mkdir(mode=0o700)
    capsule,delta,delta_sealed,imperial,liu=catalog_proof.inspect(repo,s,recipient_archive)
    r=scratch/"serpent-pins";r.mkdir(mode=0o700)
    snake=recipient.metadata(recipient_archive,repo/".github/private"/SOURCE_NAME,r)
    oracle_path=plans/"d13-test-oracle.cms.b64"
    oracle=base64.b64decode(b"".join(prep.regular(oracle_path,20_000).read_bytes().splitlines()),validate=True)
    require((len(oracle),hashlib.sha256(oracle).hexdigest())==ORACLE_CIPHER,"Test-only oracle ciphertext pin differs")
    return rows,plan,local,concat,packs,capsule,delta,delta_sealed,imperial,liu,snake,oracle

def open_small(blob,key,directory,name,limit):
    f=directory/(name+".cms");prep.new_file(f,blob)
    return prep.command([prep.openssl(),"cms","-decrypt","-binary","-inform","DER",
                         "-in",str(f),"-inkey",str(key),"-passin","pass:"],maximum=limit)

def stage(repo,inputs,keys,dest,scratch,notes,phase):
    rows,plan,local,concat,packs,capsule,delta,delta_sealed,imperial,liu,snake,oracle=inputs
    pins,cipher,art,receipt,base,_=capsule
    key=recipient.unwrap(scratch,art["recipient-private.pkcs8.enc"],
                         receipt["wrappedKeyHMACSHA256"],keys[recipient.KEY],prep.RECIPIENT_SPKI)
    phase("small-reviewed-capsules")
    source_dir=scratch/"sources"
    sun_proof.source_members(open_small(cipher,key,scratch,"source",400_000),pins,source_dir)
    imperial_bytes=open_small(imperial,key,scratch,"imperial",20_000)
    require((len(imperial_bytes),hashlib.sha256(imperial_bytes).hexdigest())==WITNESS,"Imperial input pin differs")
    witness=scratch/"imperial.json";prep.new_file(witness,imperial_bytes)
    liu_witness=decode_landmark_witness(open_small(liu,key,scratch,"liu",5000))
    snake_receipt,wrapped,snake_sealed=snake
    require(wrapped==art["recipient-private.pkcs8.enc"] and snake_receipt==receipt,"Recipient reuse differs")
    serpent=serpent_stage.unseal(snake_sealed,key,serpent_stage.SEALED_DELTA,serpent_stage.CLEAR_ZIP)
    phase("local-157-archive")
    clear=scratch/"active-local.zip"
    with clear.open("xb") as f:
        proc=subprocess.run([prep.openssl(),"cms","-decrypt","-binary","-inform","DER",
                             "-in",str(concat),"-inkey",str(key),"-passin","pass:"],
                            stdout=f,stderr=subprocess.PIPE,timeout=150)
    phase("test-only-oracle")
    from stage_completion_bottle_oracle import stage as stage_bottle
    oracle_clear=scratch/"d13-oracle-test.json"
    prep.new_file(oracle_clear,open_small(oracle,key,scratch,"test-oracle",16_000))
    stage_bottle(oracle_clear,repo)
    key.unlink()
    require(proc.returncode==0 and clear.stat().st_size==plan["archive"]["bytes"]
            and digest_file(clear)==plan["archive"]["sha256"],"Archived local ciphertext did not authenticate")
    localclear=scratch/"active-local"
    require(extract_local_archive(clear,localclear,local)==157,"Wrong local archive count")
    clear.unlink()
    phase("historical-archive-authentication")
    sealed,basezip,deltazip,swift=(scratch/n for n in ("base.enc","base.zip","delta.zip","auth.swift"))
    legacy.assemble_cipher(base,(repo/shared.BASE_PACK).parent,sealed)
    prep.new_file(swift,shared.GCM_SWIFT.encode())
    crypto.run(["swift",str(swift),str(sealed),str(basezip),str(delta_sealed),str(deltazip)],
                extra_env={recipient.KEY:keys.pop(recipient.KEY)})
    phase("historical-and-derived-replay")
    sources=rebuild_derived(repo,scratch,crypto.raw_file(basezip,128*1024**2),crypto.raw_file(deltazip,8*1024**2),
                   base,delta,source_dir,witness,liu_witness,serpent,{r["name"]:r for r in rows},manifest_rebuilder=notes)
    phase("four-reviewed-packages")
    sources+=stage_active_packages.collect(repo,scratch,packs,keys)
    keys.clear()
    phase("full-active-stage-closure")
    result=stage_new(repo,dest,[localclear],sources)
    return dict(**result,testOnlyOracleStaged=True,shippingOracle=False)

def main():
    p=argparse.ArgumentParser(description=__doc__)
    for name in ("repo","parts","plans","recipient_archive","destination"):
        p.add_argument(name,type=Path)
    p.add_argument("--protected",action="store_true")
    a=p.parse_args();state="scope"
    def phase(value):
        nonlocal state
        state=value
    try:
        keys=authenticated_scope(a.protected)
        os.umask(0o077)
        with tempfile.TemporaryDirectory(prefix="active-pack-inputs-",dir=Path(os.environ.get("RUNNER_TEMP","/tmp")).resolve(strict=True)) as d:
            root=Path(d)
            phase("input-pins")
            result=prepare(a.repo.resolve(strict=True),a.parts,a.plans,a.recipient_archive,root)
            if not a.protected:
                print(json.dumps({"inputPinsChecked":True,"plannedFiles":len(result[0]),"decrypted":False}))
                return
            import importlib.util
            path=a.plans.parent/"fighter-five-manifests-20261119"/"verify.py"
            spec=importlib.util.spec_from_file_location("verified_five_manifest_recipe",path)
            require(spec is not None and spec.loader is not None,"Reviewed manifest recipe unavailable")
            notes=importlib.util.module_from_spec(spec)
            spec.loader.exec_module(notes)
            print(json.dumps(stage(a.repo.resolve(strict=True),result,keys,a.destination,root,notes,phase)))
    except Exception as exc:
        print(f"Active resource staging stopped at {state} ({type(exc).__name__}). No private bytes emitted.",file=sys.stderr)
        raise SystemExit(1) from None

if __name__=="__main__":main()
