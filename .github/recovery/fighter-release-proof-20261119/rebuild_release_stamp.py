"""Reproduce the reviewed H17 release document from the old signed descriptor.

Resource identities come from the immutable compiled inventory. This does not
establish that the roster catalog itself has been recovered or loaded.
"""
import argparse
from copy import deepcopy
import hashlib
import json
from pathlib import Path

import completion_native_preflight as pre
BUNDLE='1b0a132a449bc2947a2a326ff30ff33d.bin'
MOTIONS=({'name': 'h_stun_start',
  'role': 'sourceStunIn',
  'frames': 31,
  'bytes': 43426,
  'path_id': 1063423564692364207,
  'sha256': 'ea3b5942fd8c7d8721f9b90bfab4c7c03c55a3dd570c4aa9cff12eefd4d9965b'},
 {'name': 'h_stun_loop',
  'role': 'sourceStunLoop',
  'frames': 35,
  'bytes': 48994,
  'path_id': 4075479027709813272,
  'sha256': 'bd1e3f455499a3caf6df7b67d5c5e40c0aff418fa88dd96aab6fd014de879eb3'},
 {'name': 'h_stun_end',
  'role': 'sourceStunOut',
  'frames': 31,
  'bytes': 43426,
  'path_id': 3764084586578974847,
  'sha256': '5d23977e9369fa15724fe5f0b9e3abdf7393d944182425f734258f14369c1eac'})
PROFILES={'sun': {'id': 'sun_triad',
         'resource': 'Sun_DeadForestTriad_Ninjato',
         'count': 65,
         'profileSHA': '303b0c010def983688b0fa38ee201bcbdb26a031f20ce03add47c091158b5cfe',
         'characterSHA': 'ce9e1b77c59fa63116af73409173fcd8922f2063ab2e0624534691fa00195ef6',
         'bindingsSHA': '3e292f26f59830d397cf1471ff4e5c3e62652c0c7f1752694213a48187da893a',
         'massesSHA': '89f89bdb912eb2b98cd1e8b5506fe308a38ad2ffb2114d569409d8b8e4c0ff6b',
         'massCharacterSHA': 'ce9e1b77c59fa63116af73409173fcd8922f2063ab2e0624534691fa00195ef6'},
 'liu': {'id': 'liu_hammers',
         'resource': 'Liu_Legion_Hammers',
         'count': 59,
         'profileSHA': '2dbe085bd288a4aff2bf9694d5e55699500879feb203985a342b76c1036b81ca',
         'characterSHA': 'a3aada76d336b9c4f9bda3904b5e947711d916f683a2dcbf7b8184377e01a517',
         'bindingsSHA': 'fd16a6cb2eb863365b563aab9b162220335c6abdb0c700594499c08264151c57',
         'massesSHA': '3bf3b9b92e118d4584019213c1d51f68b47d28dff11abb098ef42428a32dd1d2',
         'massCharacterSHA': 'f83d8cbbd7b2158604dad9eff28398bcf57c64fdcb4146e5c142608484a5a472'}}
SOURCE_RAW_SHA='75e0ec9ac3674098657aac66d6c3ee51b66f342234aae2a7b33fc3a666a6c411'
VARIANTS=(('imperial_spear_heavy_slash_passive', 'imperialHeavyPassive', 9, False),
 ('imperial_spear_heavy_slash_passive_mirror',
  'imperialHeavyPassiveMirrored',
  10,
  True))
MEDIA_BINDINGS={'sourceTrails': ('SF3WE_Target_Trails.json', ('sun', 'liu')),
 'triadAudio': ('SF3_H17_Audio.json', ('sun', 'liu')),
 'triadSummons': ('SF3_H17_Summons.json', ('sun',)),
 'triadEffects': ('SF3_H17_Effects.json.gz', ('sun',)),
 'triadMorph': ('SF3_H17_Morph.json', ('sun', 'liu'))}
NEW={'sun': {'bytes': 16252036,
         'sha256': '7c9ebfe285f637cbd002f717d80b859a57d3ab11ef491f15930dc4f3eb50d96a',
         'profileSHA': 'f46dd3c1e5df637fadc6f5a5f5a08468af2c6db50002a0ae8282b78f4daf6e6a'},
 'liu': {'bytes': 11585516,
         'sha256': 'd873864549fd7c7c3f2e9450aba12725c1d488f68ccf5c775ef5e889a4c4fe80',
         'profileSHA': 'a98e19b573509d6a08c998093b3937fefe8c9c4742d683e76621a8a10a22f266'}}
def encoded(value):
    return (json.dumps(value, ensure_ascii=False, separators=(",",":"), allow_nan=False) + "\n").encode()

def parse_json(value):
    return json.loads(value)

NAME="SF3_FighterRelease.json"
OLD_RELEASE={"bytes":33278,"sha256":"e5c0ccaeef85ce86c5b8fd4ee64524794d6556f5a561f4078362f6899bedf4e5"}
TARGET_ID="shared-imperial-victim-reconstructed-20261117-v1"
CATALOG="SF3_DistinctFighters.json"


def require(ok, reason):
    if not ok: raise ValueError(reason)


def descriptor(old, rows):
    target=deepcopy(old)
    require(target["schemaVersion"]==2 and target["panguAudio"] is None, "Wrong original release family")
    target["id"]=TARGET_ID
    require(target["catalog"]["name"]==CATALOG,"Unexpected original catalog")
    target["catalog"]=rows[CATALOG]
    for field,(name,_) in MEDIA_BINDINGS.items():
        require(target[field]["name"]==name,"Unexpected original media binding")
        target[field]=rows[name]
    by_id={p["id"]:p for p in target["profiles"]}
    require(len(by_id)==len(target["profiles"])==2 and set(by_id)=={p["id"] for p in PROFILES.values()},"Wrong original roster")
    for key,pin in PROFILES.items():
        row=by_id[pin["id"]]
        require(row["characterSHA256"]==pin["characterSHA"] and len(row["motions"])==pin["count"],"Wrong original profile")
        row["characterSHA256"]=NEW[key]["sha256"]
        new=[dict(clip=m["name"],sourceSHA256=m["sha256"],sourceBundle=BUNDLE,frames=m["frames"],
                  exportFramesPerSecond=30,sourceFramesPerSecond=30) for m in MOTIONS]
        new += [dict(clip=name,sourceSHA256=SOURCE_RAW_SHA,sourceBundle="baccadc1bc62c24fcf83246b63fd6c17.bin",
                     frames=71,exportFramesPerSecond=30,sourceFramesPerSecond=30) for name,_,_,_ in VARIANTS]
        require(len({m["clip"] for m in row["motions"]+new})==len(row["motions"])+5,"Repeated clip")
        row["motions"].extend(new)
    return target


def verify(repo, authorized_old):
    _, inv=pre.metadata(repo)
    rows={r["name"]:r for r in inv["compiledFiles"]}
    old=pre.snapshot(authorized_old,maximum=65_536,size=OLD_RELEASE["bytes"],sha256=OLD_RELEASE["sha256"],keep=True)["data"]
    candidate=encoded(descriptor(parse_json(old),rows))
    return {"compared":1,"exact":len(candidate)==rows[NAME]["bytes"]
                and hashlib.sha256(candidate).hexdigest()==rows[NAME]["sha256"],
            "catalogRebuilt":False,"built":False,"published":False}


if __name__=="__main__":
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("repo",type=Path);p.add_argument("authorized_old",type=Path)
    a=p.parse_args()
    print(json.dumps(verify(a.repo,a.authorized_old)))
