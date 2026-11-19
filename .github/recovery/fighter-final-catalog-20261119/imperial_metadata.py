"""Authenticate archived Imperial source metadata and replay own-rig clip assembly.

The source motion and both normalized configuration records are independently
cross-checked. This does not claim the missing intermediate wrapper's byte SHA.
"""
import base64
import copy
import hashlib
import json
import zipfile
from pathlib import Path

PROFILE = "continued-20261116/erlang-recovered-combat-body-v1/SF3_Erlang_Recovered_Combat_Profile.json"
NAMED = "recovered-erlang-named-animations-v1/erlang-imperial-animation-named-recovered-v1.json"
MEMBER_PINS = {
    PROFILE: "88e46fab47dbaa2ce5dd280ccf13b13cde406aa6813cfa42735dca98542b861a",
    NAMED: "12704648d0fd60929d1bba47a0fe6cd1eb0f3aafd36b7504b8819f57f5bddb08",
}
RAW_PIN = "75e0ec9ac3674098657aac66d6c3ee51b66f342234aae2a7b33fc3a666a6c411"
MISSING_WRAPPER_PIN = "8fc82d094d1c0b832cb13998b786d10e54bb63e983de6856bf7b2839bf977e29"
NAMES = ("imperial_spear_heavy_slash_passive", "imperial_spear_heavy_slash_passive_mirror")
KEYS = (
    "frames", "sourceUncroppedFrames", "sourceFirstIndex", "sourceLastIndex", "playbackTicks",
    "sourceWindowFrames", "sourceStaticPose", "sourceEndEventTick", "targetAbsentSourceWeaponTrackIDs",
    "sourceMirrorApplied", "sha256", "bundle", "sourcePathID", "sourceBytesBase64",
    "sourceArrayCount", "sourceBoneIDs",
)

def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def _require(ok, message):
    if not ok:
        raise ValueError(message)


def archived_inputs(checkpoint):
    with zipfile.ZipFile(checkpoint) as z:
        documents = {}
        for member, pin in MEMBER_PINS.items():
            data = z.read(member)
            _require(sha(data) == pin, f"Unreviewed input {member}")
            documents[member] = json.loads(data)

    names = (NAMES[0], NAMES[1] + "ed")
    rows = {
        row["name"]: row for row in documents[PROFILE]["clips"] if row["name"] in names
    }
    _require(set(rows) == set(names), "Missing source alias in Erlang witness")
    clip, held = [rows[n] for n in names]
    records = {}
    for row in documents[NAMED]["records"]:
        idx = row["sourceRecordIndex"]
        if idx in (9, 10) and row["sourceEntry"] == clip["sourceConfiguration"]["sourceEntry"]:
            _require(idx not in records, "Ambiguous Imperial style record")
            records[idx] = row
    _require(set(records) == {9, 10}, "Missing normalized records")
    for idx, row, mirrored in ((9, clip, False), (10, held, True)):
        _require(records[idx] == row["sourceConfiguration"], "Independent original configuration disagreement")
        _require(row["sourceMirrorApplied"] is mirrored, "Witness alias mismatch")
        _require(row["sourceEndEventTick"] == 132, "Source event mismatch")
    first, second = [records[i]["configuration"] for i in (9, 10)]
    _require(first["Mirrored"] is None and second["Mirrored"] == -1 and
             second["Animation"] == "Imperial_Spear_Heavy_Slash_Passive_Mirror" and
             {k: v for k, v in first.items() if k not in {"Animation", "Mirrored"}} ==
             {k: v for k, v in second.items() if k not in {"Animation", "Mirrored"}},
             "Imperial mirror differs beyond documented alias")
    for key, expected in dict(frames=71, sourceUncroppedFrames=120, sourceFirstIndex=0,
                              sourceLastIndex=70, playbackTicks=140, sourceWindowFrames=71,
                              sourceStaticPose=False, targetAbsentSourceWeaponTrackIDs=[],
                              sha256=RAW_PIN, bundle="baccadc1bc62c24fcf83246b63fd6c17.bin",
                              sourcePathID="6168038708356583987", sourceArrayCount=2).items():
        _require(clip[key] == held[key] == expected, f"Clip source timing/identity differs: {key}")
    raw = base64.b64decode(clip["sourceBytesBase64"], validate=True)
    _require(len(raw) == 167314 and sha(raw) == RAW_PIN and
             held["sourceBytesBase64"] == clip["sourceBytesBase64"] and
             len(clip["sourceBoneIDs"]) == 58 and clip["sourceBoneIDs"] == held["sourceBoneIDs"],
             "Unreviewed Imperial motion")
    _require(tuple(k for k in clip if k not in {"name", "sourceConfiguration", "tracks"}) == KEYS,
             "Archived witness metadata order differs")
    return clip, records, raw


def assemble_clip(clip, records, tracks, *, mirrored, source_keys=KEYS):
    """Replicate original copy/exclude/update ordering on a caller-chosen source wrapper.

    The default preserves every non-track field from the archived Erlang
    witness. Callers should distinguish it from the unrecovered wrapper and
    only assert historical exactness after the final catalog hash matches.
    """
    i = int(mirrored)
    _require(len(source_keys) == len(set(source_keys)) and set(source_keys) <= set(KEYS),
             "Unknown or duplicated source wrapper key")
    result = {k: copy.deepcopy(clip[k]) for k in source_keys}
    result.update(name=NAMES[i], tracks=tracks, sourceConfiguration=copy.deepcopy(records[9 + i]),
                  sourceEndEventTick=132, sourceMirroringApplied=bool(mirrored))
    return result


if __name__ == "__main__":
    import sys
    clip, records, raw = archived_inputs(Path(sys.argv[1]))
    for m in (False, True):
        result = assemble_clip(clip, records, {}, mirrored=m)
        print(json.dumps(dict(name=result["name"], keys=list(result),
                              archiveRecord=result["sourceConfiguration"]["sourceRecordIndex"],
                              rawSHA256=sha(raw), sourceEndEventTick=result["sourceEndEventTick"],
                              mirror=result["sourceMirroringApplied"], historicalWrapperVerified=False)))
