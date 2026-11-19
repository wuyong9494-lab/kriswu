"""Recompute exact catalog in restricted scratch; output only hash-match flags."""
import argparse
import base64
import json
import os
from pathlib import Path
import sys
import tempfile

import fighter_base_recovery as crypto
import fighter_h17_d19_native as base_loader
import fighter_shared_root_native as shared
import prepare_fighter_completion_delta as public
import verify_serpent_receipt as recipient
import verify_protected as sun
import assemble_from_archives as replay

LIU_CIPHER = (785,"1b6ac9cf0a7daa8fe25479ed8750a95a44a0bf6b5a4b566075eb9eeac16245d4")
WITNESS_CIPHER = (10194,"1fd79d3709c02fb11a6fd61d07757f1666473baa297f99a975d10155a8c7b0fa")

def inspect(repo, d, archive):
    capsule = sun.inspect(repo, archive, d)
    path = repo/shared.DELTA_PACK
    raw = public.regular(path, 2_100_000).read_bytes()
    sun.need(public.digest(raw) == shared.DELTA_PACK_SHA)
    delta = public.decode(raw)
    sun.need(delta["schema"] == "fighter-h17-shared-root-sealed-delta-v1" and
             delta["basePackManifestSHA256"] == shared.BASE_PACK_SHA and
             delta["deltaManifestSHA256"] == shared.DELTA_DOCUMENT_SHA and
             delta["targetReleaseSHA256"] == shared.RELEASE_SHA)
    cipher = delta["cipher"]
    sun.need(cipher["name"] == "shared-root.delta.enc")
    seal = path.parent/cipher["name"]
    sun.need(sun.matches(public.regular(seal, 8_389_000).read_bytes(), cipher))
    witness_path=Path(__file__).with_name("imperial-witness.cms.b64")
    archived=public.regular(witness_path,20_000).read_bytes()
    witness=base64.b64decode(b"".join(archived.splitlines()),validate=True)
    sun.need(replay.identity(witness)==WITNESS_CIPHER)
    liu_path=Path(__file__).with_name("liu-landmarks.cms.b64")
    liu_raw=public.regular(liu_path,5000).read_bytes()
    liu=base64.b64decode(b"".join(liu_raw.splitlines()),validate=True)
    sun.need(replay.identity(liu)==LIU_CIPHER)
    return capsule, delta, seal, witness, liu


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("repo", type=Path)
    p.add_argument("recipient_archive", type=Path)
    p.add_argument("--protected", action="store_true")
    a = p.parse_args()
    phase = "scope"
    try:
        if a.protected:
            sun.need(sys.platform == "darwin" and all(os.environ.get(k) == v for k, v in sun.ENV.items()))
            wrap = os.environ.pop(recipient.KEY, "")
            recipient.recipient.resource_key(wrap)
        else:
            sun.need(all(k not in os.environ for k in shared.KEY_NAMES))
        os.umask(0o077)
        with tempfile.TemporaryDirectory(dir=Path(os.environ["RUNNER_TEMP"]).resolve(strict=True),
                                         prefix="catalog-proof-") as tmp:
            d = Path(tmp)
            repo = a.repo.resolve(strict=True)
            phase = "input-pins"
            capsule, delta, delta_sealed, witness, liu = inspect(repo, d, a.recipient_archive)
            if not a.protected:
                print(json.dumps({"pinsChecked":True,"decrypted":False})); return
            pins, source_sealed, artifact, receipt, base, _ = capsule
            phase = "source-capsule"
            key = recipient.unwrap(d, artifact["recipient-private.pkcs8.enc"],
                                   receipt["wrappedKeyHMACSHA256"], wrap, public.RECIPIENT_SPKI)
            cms = d/"sources.cms"; public.new_file(cms, source_sealed)
            source = public.command([public.openssl(),"cms","-decrypt","-binary","-inform","DER",
                                     "-in",str(cms),"-inkey",str(key),"-passin","pass:"], maximum=400_000)
            witness_cms=d/"witness.cms"; public.new_file(witness_cms,witness)
            witness_clear=public.command([public.openssl(),"cms","-decrypt","-binary","-inform","DER",
                                    "-in",str(witness_cms),"-inkey",str(key),"-passin","pass:"], maximum=20_000)
            sun.need(replay.identity(witness_clear)==replay.WITNESS)
            phase = "liu-landmark-witness"
            liu_cms=d/"liu-witness.cms"; public.new_file(liu_cms,liu)
            liu_clear=public.command([public.openssl(),"cms","-decrypt","-binary","-inform","DER",
                        "-in",str(liu_cms),"-inkey",str(key),"-passin","pass:"],maximum=5000)
            from liu_landmarks import decode_landmark_witness
            liu_witness=decode_landmark_witness(liu_clear)
            key.unlink()
            witness_path=d/"witness.json"; public.new_file(witness_path,witness_clear)
            source_dir = d/"sources"
            sun.source_members(source, pins, source_dir)
            phase = "base-and-delta"
            sealed, base_zip, delta_zip, swift = (d/n for n in ("base.enc","base.zip","delta.zip","auth.swift"))
            base_loader.assemble_cipher(base, (repo/shared.BASE_PACK).parent, sealed)
            crypto.write_new(swift, shared.GCM_SWIFT.encode())
            crypto.run(["swift",str(swift),str(sealed),str(base_zip),str(delta_sealed),str(delta_zip)],
                       extra_env={recipient.KEY:wrap})
            wrap = ""
            def phase_update(value):
                nonlocal phase
                phase=value
            result = replay.replay(crypto.raw_file(base_zip,128*1024**2), crypto.raw_file(delta_zip,8*1024**2),
                                   base, delta, source_dir, witness_path, d, phase_update, liu_witness=liu_witness)
            print(json.dumps(result),flush=True)
            return 0 if result["stunCatalogVerified"] and result["finalCatalogVerified"] else 1
    except Exception as e:
        # Enumerate field labels, never interpolate arbitrary archive text or paths.
        safe_fields={"weaponLandmarks","tracks","collisionEdges","hurtCapsules","weaponBaseL","weaponTipL",
                     "weaponBaseR","weaponTipR","sourceSHA256","sourceMirroringSchemaSHA256"}
        field=e.args[0] if isinstance(e,KeyError) and len(e.args)==1 and isinstance(e.args[0],str) else None
        label=f"/{field}" if field in safe_fields else ""
        print(f"Stopped at {phase} ({type(e).__name__}{label}). No resource bytes emitted.",file=sys.stderr)
        raise SystemExit(1) from None


if __name__ == "__main__":
    raise SystemExit(main())
