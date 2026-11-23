#!/usr/bin/env python3
"""Read-only deep audit of shogun.rar Unity AssetBundles for Phase 1 acceptance."""
import hashlib
import json
import os
import struct
from collections import Counter, defaultdict
from pathlib import Path
import UnityPy

RAW_DIR = Path("/home/antigravity/shogun_phase1_work/raw_shogun/shogun")
OUT_DIR = Path("/home/antigravity/shogun_phase1_work/audit")
OUT_DIR.mkdir(parents=True, exist_ok=True)


def sha256_bytes(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def sha256_file(p: Path) -> str:
    h = hashlib.sha256()
    with p.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def safe_name(obj) -> str:
    try:
        d = obj.read()
        for attr in ("m_Name", "name"):
            v = getattr(d, attr, None)
            if v:
                return str(v)
    except Exception:
        pass
    try:
        t = obj.read_typetree()
        if isinstance(t, dict) and t.get("m_Name"):
            return str(t["m_Name"])
    except Exception:
        pass
    return ""


def walk_pptrs(node, path, out):
    if isinstance(node, dict):
        if set(node.keys()) >= {"m_FileID", "m_PathID"} and len(node) <= 3:
            fid = node.get("m_FileID", 0)
            pid = node.get("m_PathID", 0)
            if fid != 0 and pid != 0:
                out.append((path, int(fid), int(pid)))
            return
        for k, v in node.items():
            walk_pptrs(v, f"{path}.{k}" if path else k, out)
    elif isinstance(node, list):
        for i, v in enumerate(node):
            walk_pptrs(v, f"{path}[{i}]", out)


def main():
    bundles = sorted(RAW_DIR.glob("*.bin"))
    print(f"Auditing {len(bundles)} bundle files in {RAW_DIR}")

    # First pass: index all CAB names & PathIDs provided by all 38 bundles
    cab_to_bundle = {}
    cab_pathids = defaultdict(set)
    bundle_summaries = {}

    for bpath in bundles:
        env = UnityPy.load(str(bpath))
        bname = bpath.name
        fhash = sha256_file(bpath)
        type_counts = Counter()
        cabs = []
        externals_all = []
        containers = []

        for sf_name, sf in env.files.items():
            # BundleFile contains SerializedFile children in sf.files
            subfiles = getattr(sf, "files", None)
            sfs = list(subfiles.items()) if subfiles else [(sf_name, sf)]
            for sub_name, sub in sfs:
                if not hasattr(sub, "objects"):
                    continue
                cabs.append(sub_name)
                cab_to_bundle[sub_name.lower()] = bname
                for pid in sub.objects.keys():
                    cab_pathids[sub_name.lower()].add(int(pid))
                exts = getattr(sub, "externals", [])
                for idx, ext in enumerate(exts, start=1):
                    externals_all.append({
                        "serialized_file": sub_name,
                        "file_id": idx,
                        "name": getattr(ext, "name", ""),
                        "path": getattr(ext, "path", ""),
                        "guid": str(getattr(ext, "guid", "")),
                        "type": getattr(ext, "type", None),
                    })

        for obj in env.objects:
            type_counts[obj.type.name] += 1

        for cpath, obj in env.container.items():
            containers.append({
                "container": cpath,
                "type": obj.type.name,
                "path_id": int(obj.path_id),
            })

        bundle_summaries[bname] = {
            "bytes": bpath.stat().st_size,
            "sha256": fhash,
            "cabs": cabs,
            "type_counts": dict(type_counts),
            "externals": externals_all,
            "container_count": len(containers),
            "containers": containers,
        }

    # Check which externals are resolved locally within shogun.rar vs MISSING
    missing_externals_summary = []
    for bname, info in bundle_summaries.items():
        for ext in info["externals"]:
            raw_path = ext["path"] or ext["name"]
            cab_base = Path(raw_path).name.lower()
            resolved_bundle = cab_to_bundle.get(cab_base)
            ext["resolved_in_shogun_rar"] = resolved_bundle is not None
            ext["resolved_bundle"] = resolved_bundle
            if not resolved_bundle:
                missing_externals_summary.append({
                    "source_bundle": bname,
                    "serialized_file": ext["serialized_file"],
                    "file_id": ext["file_id"],
                    "external_path": ext["path"],
                    "external_name": ext["name"],
                    "cab": cab_base,
                    "guid": ext["guid"],
                })

    # Deep audit of key bundles:
    key_bundles = [
        "animations-base-shogun.bin",
        "animations-stances-base-shogun.bin",
        "heroes-models-shogun-base-common.bin",
        "heroes-models-shogun-base-pbr.bin",
        "heroes-models-shogun-base-pbr-textures.bin",
        "weapons-models-shogun-r-base-rec-vassal-common.bin",
        "weapons-models-shogun-r-base-rec-vassal-pbr.bin",
        "effects-prefabs-shogun.bin",
        "effects-materials-heroes-add_mats-shogun.bin",
        "audio-sounds-heroes-shogun.bin",
        "shaders-temp-1_9_80-after_shogun_merge.bin",
        "shaders-temp-shogun.bin",
    ]

    deep = {}
    for bname in key_bundles:
        bpath = RAW_DIR / bname
        if not bpath.exists():
            continue
        env = UnityPy.load(str(bpath))
        items = []
        unresolved_pptrs = []

        # Build external map per serialized file
        sf_ext_map = {}
        for sf_name, sf in env.files.items():
            subfiles = getattr(sf, "files", None)
            sfs = list(subfiles.items()) if subfiles else [(sf_name, sf)]
            for sub_name, sub in sfs:
                if not hasattr(sub, "objects"):
                    continue
                emap = {}
                for idx, ext in enumerate(getattr(sub, "externals", []), start=1):
                    ep = getattr(ext, "path", "") or getattr(ext, "name", "")
                    emap[idx] = {
                        "path": ep,
                        "cab": Path(ep).name.lower(),
                        "guid": str(getattr(ext, "guid", "")),
                    }
                sf_ext_map[sub] = emap

        for obj in env.objects:
            tname = obj.type.name
            entry = {
                "type": tname,
                "path_id": int(obj.path_id),
                "name": "",
                "container": obj.container or "",
            }
            if tname == "TextAsset":
                d = obj.read()
                raw = d.m_Script.encode("utf-8", "surrogateescape") if isinstance(d.m_Script, str) else bytes(d.m_Script)
                entry["name"] = d.m_Name
                entry["bytes"] = len(raw)
                entry["sha256"] = sha256_bytes(raw)
                entry["magic_hex"] = raw[:32].hex()
                entry["magic_ascii"] = "".join(chr(c) if 32 <= c < 127 else "." for c in raw[:32])
                items.append(entry)
            elif tname in ("Mesh", "Texture2D", "Material", "Shader", "AudioClip", "AnimationClip", "GameObject", "SkinnedMeshRenderer", "MeshRenderer", "TrailRenderer", "ParticleSystem", "ParticleSystemRenderer"):
                try:
                    d = obj.read()
                    entry["name"] = getattr(d, "m_Name", "")
                    if tname == "Mesh":
                        entry["vertex_count"] = getattr(d.m_VertexData, "m_VertexCount", None) if hasattr(d, "m_VertexData") else None
                        entry["submesh_count"] = len(getattr(d, "m_SubMeshes", []) or [])
                        entry["bindpose_count"] = len(getattr(d, "m_BindPose", []) or [])
                    elif tname == "Texture2D":
                        entry["width"] = getattr(d, "m_Width", None)
                        entry["height"] = getattr(d, "m_Height", None)
                        entry["format"] = str(getattr(d, "m_TextureFormat", ""))
                    elif tname == "AudioClip":
                        entry["length"] = getattr(d, "m_Length", None)
                        entry["freq"] = getattr(d, "m_Frequency", None)
                        entry["channels"] = getattr(d, "m_Channels", None)
                        entry["compression"] = str(getattr(d, "m_CompressionFormat", ""))
                except Exception as e:
                    entry["read_error"] = str(e)
                items.append(entry)

            # For effects / shaders / models / weapons, inspect external PPtrs via typetree
            if bname.startswith("effects-") or bname.startswith("heroes-models-shogun-base-") or bname.startswith("weapons-models-shogun-"):
                try:
                    tt = obj.read_typetree()
                    pptrs = []
                    walk_pptrs(tt, "", pptrs)
                    emap = sf_ext_map.get(obj.assets_file, {})
                    obj_name = tt.get("m_Name", "") if isinstance(tt, dict) else ""
                    for prop_path, fid, pid in pptrs:
                        ext_info = emap.get(fid, {})
                        cab = ext_info.get("cab", "")
                        resolved_bundle = cab_to_bundle.get(cab)
                        pid_exists = (pid in cab_pathids.get(cab, set())) if resolved_bundle else False
                        if not resolved_bundle or not pid_exists:
                            unresolved_pptrs.append({
                                "owner_type": tname,
                                "owner_name": obj_name,
                                "owner_path_id": int(obj.path_id),
                                "property": prop_path,
                                "file_id": fid,
                                "target_path_id": pid,
                                "target_external_path": ext_info.get("path", ""),
                                "target_cab": cab,
                                "target_guid": ext_info.get("guid", ""),
                                "cab_present_in_shogun_rar": resolved_bundle is not None,
                                "path_id_present": pid_exists,
                            })
                except Exception:
                    pass

        deep[bname] = {
            "item_count": len(items),
            "items": items,
            "unresolved_pptr_count": len(unresolved_pptrs),
            "unresolved_pptrs": unresolved_pptrs,
        }

    report = {
        "bundle_count": len(bundles),
        "bundles": bundle_summaries,
        "missing_externals_summary": missing_externals_summary,
        "deep": deep,
    }
    out_json = OUT_DIR / "shogun_rar_full_audit.json"
    out_json.write_text(json.dumps(report, indent=2, ensure_ascii=False))
    print(f"Wrote {out_json}")

    # Concise stdout summary
    print("\n=== ALL 38 BUNDLES SUMMARY ===")
    for bname, info in bundle_summaries.items():
        missing_n = sum(1 for e in info["externals"] if not e["resolved_in_shogun_rar"])
        print(f"  {bname:58s} {info['bytes']:10d}B  objs={info['type_counts']}  ext={len(info['externals'])} (missing={missing_n})")

    print("\n=== ANIMATIONS IN animations-base-shogun.bin (heavy / shogun) ===")
    for it in deep.get("animations-base-shogun.bin", {}).get("items", []):
        if "heavy" in it["name"].lower() or "heavy" in it["container"].lower() or len(deep["animations-base-shogun.bin"]["items"]) <= 80:
            print(f"  [{it['type']}] {it['name']} | container={it['container']} | bytes={it.get('bytes')} | magic={it.get('magic_hex','')[:24]} ({it.get('magic_ascii','')[:16]})")

    print("\n=== MESHES & KEY OBJECTS IN BASE MODEL & WEAPON ===")
    for bn in ("heroes-models-shogun-base-common.bin", "heroes-models-shogun-base-pbr.bin", "weapons-models-shogun-r-base-rec-vassal-common.bin", "weapons-models-shogun-r-base-rec-vassal-pbr.bin"):
        print(f"-- {bn} --")
        for it in deep.get(bn, {}).get("items", []):
            if it["type"] in ("Mesh", "Material", "Texture2D", "SkinnedMeshRenderer", "MeshRenderer"):
                print(f"  [{it['type']}] {it['name']} v={it.get('vertex_count')} sub={it.get('submesh_count')} bp={it.get('bindpose_count')} {it.get('width','')}x{it.get('height','')}")

    print("\n=== EFFECTS UNRESOLVED EXTERNALS ===")
    for bn in ("effects-prefabs-shogun.bin", "effects-materials-heroes-add_mats-shogun.bin"):
        d = deep.get(bn, {})
        print(f"-- {bn}: {len(d.get('items', []))} items, {d.get('unresolved_pptr_count', 0)} unresolved PPtrs --")
        by_cab = Counter((u["target_external_path"], u["target_path_id"], u["property"]) for u in d.get("unresolved_pptrs", []))
        for (ep, pid, prop), cnt in by_cab.most_common(40):
            print(f"  MISSING {ep} PathID={pid} prop={prop} (x{cnt})")


if __name__ == "__main__":
    main()
