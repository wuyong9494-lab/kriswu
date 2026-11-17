#!/usr/bin/env python3
"""Join the reviewed D15 target to the reconstructed original Sun container.

Only the owner's authenticated container identity changes. The target actor,
material definitions, source shader mask, trigger and source shadow are retained.
"""
import argparse
import copy
import json
import os
from pathlib import Path

from stage_erlang_local_candidate import checked, document, digest, require, BASE_RECEIPT, BASE_RECEIPT_SHA256, BASE_RELEASE_SHA256

REVIEWED_MORPH_SHA = "1089d179e72f8c452c1067ff896b0b1982fde2d9ca4646c2ad30647f4dbdfded"
SOURCE_TEMPLATE_SHA = "fc6cad67889ead35ca683ede13b86d4c0423949609388c01ca04b36dc050416b"
OLD_OWNER_SHA = "ce9e1b77c59fa63116af73409173fcd8922f2063ab2e0624534691fa00195ef6"
OWNER_SHA = "7c9ebfe285f637cbd002f717d80b859a57d3ab11ef491f15930dc4f3eb50d96a"
TARGET_SHA = "2957d7861b2ee7656945259dd273f241591ce55f71d364dab007a9bc372d76f6"


def rebind(args):
    receipt = document(args.base / BASE_RECEIPT, BASE_RECEIPT_SHA256)
    require(receipt["release"]["sha256"] == BASE_RELEASE_SHA256
            and len(receipt["files"]) == 302 and receipt["productionPanguActivated"] is False,
            "Reconstructed source base differs")
    rows = {row["name"]: row for row in receipt["files"]}
    def base_document(name):
        row = rows[name]
        checked(args.base / "FighterPrivate" / name, row["sha256"], row["bytes"])
        return document(args.base / "FighterPrivate" / name, row["sha256"])
    source = document(args.source_template, SOURCE_TEMPLATE_SHA)
    target = document(args.reviewed_morph, REVIEWED_MORPH_SHA)
    revised = base_document("SF3_H17_Morph.json")
    catalog = base_document("SF3_DistinctFighters.json")
    owners = [p for p in catalog["profiles"] if p["id"] == "sun_triad"]
    require(len(owners) == 1, "Missing original Sun source profile")
    owner = owners[0]
    require(owner["sha256"] == OWNER_SHA and owner["bodyID"] == "arm__prc_43"
            and owner["weaponID"] == "wpn__ninjato_01_06" and len(owner["clips"]) == 70,
            "The source owner is not the reviewed reconstructed Sun")
    require({k for k in set(source) | set(revised) if source.get(k) != revised.get(k)}
            == {"ownerCharacterSHA256", "targetCharacterSHA256"}, "Base morph changed its source behavior")
    require(source["ownerCharacterSHA256"] == target["ownerCharacterSHA256"] == OLD_OWNER_SHA
            and revised["ownerCharacterSHA256"] == OWNER_SHA
            and target["targetProfileID"] == "wuyong_erlang"
            and target["targetCharacterSHA256"] == TARGET_SHA, "Reviewed pair differs")
    for name in ("version", "ownerProfileID", "sourceConfigurationSHA256", "trigger", "mask", "projectedShadow"):
        require(source[name] == target[name] == revised[name], "Source behavior differs: " + name)
    result = copy.deepcopy(target)
    result["ownerCharacterSHA256"] = OWNER_SHA
    result["evidence"].append("Owner container follows shared-imperial-victim-reconstructed-20261117-v1; original source mask, trigger, target geometry and material bindings are unchanged.")
    require(len(result["evidence"]) <= 32, "Too many source references")
    output = args.output.absolute()
    require(not output.exists() and output.parent.resolve(strict=True) == output.parent,
            "Output must be a new private directory")
    output.mkdir(mode=0o700)
    mask = result["mask"]
    mask_path = checked(args.mask, mask["sha256"], mask["bytes"])
    name = "SF3_H17_WuMorph.json"
    with (output / name).open("x") as f:
        json.dump(result, f, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        f.write("\n")
    (output / mask["file"]).write_bytes(mask_path.read_bytes())
    audit = dict(schema="reviewed-erlang-morph-owner-rebind-v1", baseReleaseSHA256=BASE_RELEASE_SHA256,
        baseReceiptSHA256=BASE_RECEIPT_SHA256, reviewedTargetManifestSHA256=REVIEWED_MORPH_SHA,
        originalSourceTemplateSHA256=SOURCE_TEMPLATE_SHA, ownerCharacterSHA256=OWNER_SHA,
        targetCharacterSHA256=TARGET_SHA, sourceBehaviorUnchanged=True, targetMaterialsUnchanged=True,
        files=[dict(name=n, bytes=(output/n).stat().st_size, sha256=digest(output/n)) for n in (name, mask["file"])],
        nativeRendered=False, productionReady=False)
    (output / "erlang-morph-owner-rebind-receipt-private.json").write_text(
        json.dumps(audit, sort_keys=True, separators=(",", ":")) + "\n")
    for path in output.iterdir(): os.chmod(path, 0o600)
    return audit


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("base", "source-template", "reviewed-morph", "mask", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    print(json.dumps(rebind(parser.parse_args()), sort_keys=True))
