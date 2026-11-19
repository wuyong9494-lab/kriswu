"""Metadata-only check of historical/candidate Sun endpoint tracks."""
import argparse
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
import replay_historical_sun as replay

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
    return capsule, delta, seal


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
                                         prefix="sun-track-proof-") as tmp:
            d = Path(tmp)
            repo = a.repo.resolve(strict=True)
            phase = "input-pins"
            capsule, delta, delta_sealed = inspect(repo, d, a.recipient_archive)
            if not a.protected:
                print(json.dumps({"pinsChecked":True,"decrypted":False})); return
            pins, source_sealed, artifact, receipt, base, _ = capsule
            phase = "source-capsule"
            key = recipient.unwrap(d, artifact["recipient-private.pkcs8.enc"],
                                   receipt["wrappedKeyHMACSHA256"], wrap, public.RECIPIENT_SPKI)
            cms = d/"sources.cms"; public.new_file(cms, source_sealed)
            source = public.command([public.openssl(),"cms","-decrypt","-binary","-inform","DER",
                                     "-in",str(cms),"-inkey",str(key),"-passin","pass:"], maximum=400_000)
            key.unlink()
            source_dir = d/"sources"
            sun.source_members(source, pins, source_dir)
            phase = "base-and-delta"
            sealed, base_zip, delta_zip, swift = (d/n for n in ("base.enc","base.zip","delta.zip","auth.swift"))
            base_loader.assemble_cipher(base, (repo/shared.BASE_PACK).parent, sealed)
            crypto.write_new(swift, shared.GCM_SWIFT.encode())
            crypto.run(["swift",str(swift),str(sealed),str(base_zip),str(delta_sealed),str(delta_zip)],
                       extra_env={recipient.KEY:wrap})
            wrap = ""
            phase = "endpoint-tracks"
            result = replay.replay(crypto.raw_file(base_zip,128*1024**2), crypto.raw_file(delta_zip,8*1024**2),
                                   base, delta, source_dir, d)
            summary = result["targetComparisons"]
            print(json.dumps({
                "historicalCatalogAuthenticated": True,
                "exact70MotionModel": True,
                "historicalClips": result["clips"],
                "uniqueEndpointCount": 8-len(result["rejectedEndpoints"]),
                "unresolvedEndpointCount": len(result["rejectedEndpoints"]),
                "fiveActionComparisons": sum(len(r["clips"]) == 5 for r in summary),
                "unresolvedAlternatives": sum(r["unresolvedAlternatives"] for r in summary),
                "divergentEndpointCount": sum(any(not x["sameTrack"] for x in r["clips"]) for r in summary),
                "targetTicksPerEndpoint": sum(x["ticks"] for x in summary[0]["clips"]) if summary else 0,
                "finalCatalogVerified": False, "appBuilt": False, "published": False
            }))
    except Exception as e:
        print(f"Stopped at {phase} ({type(e).__name__}). No resource bytes emitted.",file=sys.stderr)
        raise SystemExit(1) from None


if __name__ == "__main__":
    main()
