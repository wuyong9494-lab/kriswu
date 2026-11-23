#!/usr/bin/env python3
"""Trace exact heavy-slash VFX prefabs, materials, meshes, textures, and missing external CAB/PathIDs."""
import json
from collections import defaultdict
from pathlib import Path
import UnityPy

RAW = Path("/home/antigravity/shogun_phase1_work/raw_shogun/shogun")
OUT = Path("/home/antigravity/shogun_phase1_work/audit")

# Index all CABs across all 38 bundles
cab_map = {}
cab_objs = defaultdict(dict)
for bp in sorted(RAW.glob("*.bin")):
    env = UnityPy.load(str(bp))
    for sf_name, sf in env.files.items():
        subs = getattr(sf, "files", None)
        sfs = list(subs.items()) if subs else [(sf_name, sf)]
        for sub_name, sub in sfs:
            if not hasattr(sub, "objects"):
                continue
            key = sub_name.lower()
            cab_map[key] = bp.name
            for pid, o in sub.objects.items():
                cab_objs[key][int(pid)] = (bp.name, o.type.name, o.container or "")


def get_ext_map(assets_file):
    m = {}
    for idx, ext in enumerate(getattr(assets_file, "externals", []), start=1):
        ep = getattr(ext, "path", "") or getattr(ext, "name", "")
        m[idx] = {
            "path": ep,
            "cab": Path(ep).name.lower(),
            "guid": str(getattr(ext, "guid", "")),
        }
    return m


def walk_pptrs(node, path, out):
    if isinstance(node, dict):
        if set(node.keys()) >= {"m_FileID", "m_PathID"} and len(node) <= 3:
            fid = int(node.get("m_FileID", 0))
            pid = int(node.get("m_PathID", 0))
            if pid != 0:
                out.append((path, fid, pid))
            return
        for k, v in node.items():
            walk_pptrs(v, f"{path}.{k}" if path else k, out)
    elif isinstance(node, list):
        for i, v in enumerate(node):
            walk_pptrs(v, f"{path}[{i}]", out)


def trace_heavy_vfx():
    env_p = UnityPy.load(str(RAW / "effects-prefabs-shogun.bin"))
    by_pid = {int(o.path_id): o for o in env_p.objects}

    # Build GO hierarchy in effects-prefabs-shogun.bin
    go_tt = {}
    tr_children = defaultdict(list)
    tr_to_go = {}
    go_to_tr = {}
    for o in env_p.objects:
        if o.type.name == "GameObject":
            tt = o.read_typetree()
            go_tt[int(o.path_id)] = tt
        elif o.type.name == "Transform":
            tt = o.read_typetree()
            tpid = int(o.path_id)
            gpid = int(tt["m_GameObject"]["m_PathID"])
            fpid = int(tt["m_Father"]["m_PathID"])
            tr_to_go[tpid] = gpid
            go_to_tr[gpid] = tpid
            if fpid != 0:
                tr_children[fpid].append(tpid)

    heavy_prefabs = sorted(
        (c, int(o.path_id))
        for c, o in env_p.container.items()
        if "shogun_pf_heavy" in c.lower()
    )

    # Also load add_mats bundle to resolve material targets inside shogun.rar
    env_m = UnityPy.load(str(RAW / "effects-materials-heroes-add_mats-shogun.bin"))
    mat_by_pid = {int(o.path_id): o for o in env_m.objects}

    results = {}
    all_missing_deps = {}

    for cpath, root_gpid in heavy_prefabs:
        pname = Path(cpath).name
        # Traverse subtree
        queue = [root_gpid]
        visited = set()
        nodes = []
        missing_here = []
        resolved_here = []

        while queue:
            gpid = queue.pop(0)
            if gpid in visited or gpid not in go_tt:
                continue
            visited.add(gpid)
            tt = go_tt[gpid]
            gname = tt.get("m_Name", "")
            comp_list = []

            for c in tt.get("m_Component", []):
                cpid = int(c["component"]["m_PathID"])
                cobj = by_pid.get(cpid)
                if not cobj:
                    continue
                ctype = cobj.type.name
                comp_info = {"type": ctype, "path_id": cpid}
                if ctype in ("ParticleSystem", "ParticleSystemRenderer", "MeshRenderer", "MeshFilter", "SkinnedMeshRenderer"):
                    try:
                        ctt = cobj.read_typetree()
                        if ctype == "ParticleSystem":
                            comp_info["lengthInSec"] = ctt.get("lengthInSec")
                            comp_info["looping"] = ctt.get("looping")
                            comp_info["startDelay"] = ctt.get("startDelay")
                            im = ctt.get("InitialModule", {})
                            comp_info["startLifetime"] = im.get("startLifetime", {}).get("scalar")
                            comp_info["startSpeed"] = im.get("startSpeed", {}).get("scalar")
                            comp_info["startSize"] = im.get("startSize", {}).get("scalar")
                            em = ctt.get("EmissionModule", {})
                            comp_info["emissionEnabled"] = em.get("enabled")
                            comp_info["rateOverTime"] = em.get("rateOverTime", {}).get("scalar")
                            comp_info["bursts"] = em.get("m_Bursts", [])
                            tm = ctt.get("TrailModule", {})
                            if tm.get("enabled"):
                                comp_info["trailEnabled"] = True
                        pptrs = []
                        walk_pptrs(ctt, "", pptrs)
                        emap = get_ext_map(cobj.assets_file)
                        for prop, fid, pid in pptrs:
                            if fid == 0:
                                local_o = by_pid.get(pid)
                                if local_o and local_o.type.name in ("Mesh", "Material", "Texture2D", "Shader"):
                                    lname = local_o.read_typetree().get("m_Name", "")
                                    resolved_here.append({
                                        "go": gname, "comp": ctype, "prop": prop,
                                        "bundle": "effects-prefabs-shogun.bin",
                                        "type": local_o.type.name, "name": lname, "path_id": pid,
                                    })
                            else:
                                einfo = emap.get(fid, {})
                                cab = einfo.get("cab", "")
                                target = cab_objs.get(cab, {}).get(pid)
                                if target:
                                    rb, rt, rc = target
                                    # Also check material's own missing externals if it's in add_mats!
                                    resolved_here.append({
                                        "go": gname, "comp": ctype, "prop": prop,
                                        "bundle": rb, "type": rt, "container": rc, "path_id": pid,
                                    })
                                else:
                                    dep = {
                                        "go": gname, "comp": ctype, "prop": prop,
                                        "file_id": fid,
                                        "external_path": einfo.get("path", ""),
                                        "cab": cab,
                                        "target_path_id": pid,
                                        "cab_in_shogun_rar": cab in cab_map,
                                    }
                                    missing_here.append(dep)
                                    all_missing_deps[(einfo.get("path", ""), pid, prop)] = dep
                    except Exception as e:
                        comp_info["err"] = str(e)
                comp_list.append(comp_info)

            nodes.append({"gameObject": gname, "path_id": gpid, "components": comp_list})
            tpid = go_to_tr.get(gpid)
            if tpid is not None:
                for ch_t in tr_children.get(tpid, []):
                    ch_g = tr_to_go.get(ch_t)
                    if ch_g:
                        queue.append(ch_g)

        results[pname] = {
            "container": cpath,
            "root_path_id": root_gpid,
            "node_count": len(nodes),
            "nodes": nodes,
            "resolved_refs": resolved_here,
            "missing_refs": missing_here,
        }

    # Now audit ALL 6 heavy materials in effects-materials-heroes-add_mats-shogun.bin + trail_base/trail_shadow in model common!
    heavy_mats_audit = {}
    for cpath, obj in sorted(env_m.container.items()):
        if "shogun_mt_heavy" not in cpath.lower() and "shogun_mt_shared" not in cpath.lower():
            continue
        reader = mat_by_pid[int(obj.path_id)]
        tt = reader.read_typetree()
        emap = get_ext_map(reader.assets_file)
        pptrs = []
        walk_pptrs(tt, "", pptrs)
        resolved = []
        missing = []
        for prop, fid, pid in pptrs:
            if fid == 0:
                lo = mat_by_pid.get(pid)
                if lo:
                    resolved.append({"prop": prop, "bundle": "effects-materials-heroes-add_mats-shogun.bin", "type": lo.type.name, "name": lo.read_typetree().get("m_Name", ""), "path_id": pid})
            else:
                einfo = emap.get(fid, {})
                cab = einfo.get("cab", "")
                target = cab_objs.get(cab, {}).get(pid)
                if target:
                    resolved.append({"prop": prop, "bundle": target[0], "type": target[1], "container": target[2], "path_id": pid})
                else:
                    dep = {
                        "material": Path(cpath).name, "prop": prop,
                        "file_id": fid, "external_path": einfo.get("path", ""),
                        "cab": cab, "target_path_id": pid,
                    }
                    missing.append(dep)
                    all_missing_deps[(einfo.get("path", ""), pid, prop)] = dep
        heavy_mats_audit[Path(cpath).name] = {
            "container": cpath, "path_id": int(obj.path_id),
            "resolved": resolved, "missing": missing,
            "colors": tt.get("m_SavedProperties", {}).get("m_Colors", []),
            "floats": tt.get("m_SavedProperties", {}).get("m_Floats", []),
        }

    # Also check trail_base & trail_shadow & pbr_arm/wpn_shogun_base missing externals
    model_missing = []
    for bn in ("heroes-models-shogun-base-common.bin", "heroes-models-shogun-base-pbr.bin"):
        env_x = UnityPy.load(str(RAW / bn))
        for o in env_x.objects:
            if o.type.name != "Material":
                continue
            tt = o.read_typetree()
            mname = tt.get("m_Name", "")
            if "minion" in mname.lower() or "enemy" in mname.lower():
                continue
            emap = get_ext_map(o.assets_file)
            pptrs = []
            walk_pptrs(tt, "", pptrs)
            for prop, fid, pid in pptrs:
                if fid == 0:
                    continue
                einfo = emap.get(fid, {})
                cab = einfo.get("cab", "")
                if pid not in cab_objs.get(cab, {}):
                    model_missing.append({
                        "bundle": bn, "material": mname, "prop": prop,
                        "external_path": einfo.get("path", ""), "cab": cab,
                        "target_path_id": pid,
                    })

    summary = {
        "heavy_prefabs": results,
        "heavy_and_shared_materials": heavy_mats_audit,
        "model_material_missing_refs": model_missing,
    }
    (OUT / "shogun_heavy_vfx_dependency_audit.json").write_text(json.dumps(summary, indent=2, ensure_ascii=False))

    print("=== HEAVY PREFABS DEPENDENCY SUMMARY ===")
    for pname, info in results.items():
        print(f"\n[{pname}] nodes={info['node_count']} resolved={len(info['resolved_refs'])} missing={len(info['missing_refs'])}")
        for r in info["resolved_refs"]:
            print(f"  OK  {r['go']:28s} {r['prop']:24s} -> {r['bundle']} ({r['type']} {r.get('name') or r.get('container')})")
        for m in info["missing_refs"]:
            print(f"  MISS {m['go']:27s} {m['prop']:24s} -> {m['external_path']} PathID={m['target_path_id']}")

    print("\n=== HEAVY MATERIALS (shogun_mt_heavy) ===")
    for mname, info in heavy_mats_audit.items():
        if "heavy" not in mname.lower():
            continue
        print(f"\n[{mname}] resolved={len(info['resolved'])} missing={len(info['missing'])}")
        for r in info["resolved"]:
            print(f"  OK   {r['prop']:36s} -> {r['bundle']} ({r['type']} {r.get('name') or r.get('container')})")
        for m in info["missing"]:
            print(f"  MISS {m['prop']:36s} -> {m['external_path']} PathID={m['target_path_id']}")

    print("\n=== MODEL & TRAIL MATERIAL MISSING REFS ===")
    for m in model_missing:
        print(f"  MISS {m['bundle']} :: {m['material']:24s} {m['prop']:24s} -> {m['external_path']} PathID={m['target_path_id']}")


if __name__ == "__main__":
    trace_heavy_vfx()
