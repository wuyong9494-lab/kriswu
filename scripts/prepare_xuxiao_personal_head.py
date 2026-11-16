#!/usr/bin/env python3
"""Prepare Xu Xiao's supplied static bust for later costume/rig attachment.

Run with Blender in background mode. The supplied .fbx is a ZIP container;
authenticate its real FBX and PBR maps before importing. Never exports the suit
as an emperor costume or claims a static head is an animated full fighter.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import zipfile

import bpy
import numpy as np

ARCHIVE_SHA256 = "661768850d4f64c8bc252200961c052f0643902da394c15c5cd189ad6841b560"
STEM = "Meshy_AI_man_portrait_bust_1113121636_image-to-3d-texture"
FILES = {
    ".fbx": (322287180, "202b7e2254139579dfbacf76537cd6b1c5b3cbf43367162d935d299089972392"),
    ".png": (14801285, "36a030213a07b380e21f65cf0025735d82a87242d80fde7f7d5a6a1dbeac02dd"),
    "_metallic.png": (18587, "39b8f0e2962ccdde7f662121aca41ff82482afc16127bb42d448bab22410f0f8"),
    "_normal.png": (11915614, "5c910299a300e2e3e859cb1a4c3257ee8abec63bc19b59f9d7a891fea5c0cf2a"),
    "_roughness.png": (1210856, "d0465e974879a6784de15b71825a1ee2e1a9dd920831ccc093a7dba5315f10cf"),
}


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def cropped_mesh(obj):
    old = obj.data
    assert len(old.vertices) == 3777559 and len(old.polygons) == 7562286
    xyz = np.empty(len(old.vertices) * 3, dtype=np.float32)
    old.vertices.foreach_get("co", xyz)
    xyz = xyz.reshape(-1, 3)
    loops = np.empty(len(old.loops), dtype=np.int32)
    old.loops.foreach_get("vertex_index", loops)
    assert len(loops) == 3 * len(old.polygons)
    triangles = loops.reshape(-1, 3)
    # Reviewed front/side anatomy: a sloping cut follows the exposed neck
    # above the supplied shirt collar. Coordinates are this exact source only.
    above = xyz[:, 2] >= -0.08 + 0.33 * xyz[:, 1]
    retained = np.all(above[triangles], axis=1)
    used, inverse = np.unique(triangles[retained], return_inverse=True)
    inverse = inverse.reshape(-1).astype(np.int32)
    uv = np.empty(len(old.loops) * 2, dtype=np.float32)
    old.uv_layers.active.data.foreach_get("uv", uv)
    uv = uv.reshape(-1, 3, 2)[retained]
    source_count = int(retained.sum())
    positions = xyz[used]
    # Bound the working mesh while preserving source triangle corner UVs.
    # A 0.006-source-unit cell is 1.5 mm at the exported attachment scale.
    # Keep corner UVs from a surviving source triangle; never project a new face.
    _, cells = np.unique(np.floor(positions / 0.006).astype(np.int32), axis=0, return_inverse=True)
    cells = cells.reshape(-1)
    weights = np.bincount(cells)
    positions = np.stack([np.bincount(cells, weights=positions[:,i]) / weights for i in range(3)], axis=1).astype(np.float32)
    mapped = cells[inverse].reshape(-1, 3)
    nondegenerate = (mapped[:,0] != mapped[:,1]) & (mapped[:,1] != mapped[:,2]) & (mapped[:,2] != mapped[:,0])
    indices = np.flatnonzero(nondegenerate)
    _, unique = np.unique(np.sort(mapped[indices], axis=1), axis=0, return_index=True)
    indices = indices[np.sort(unique)]
    inverse = mapped[indices].reshape(-1).astype(np.int32)
    uv = uv[indices].reshape(-1)
    mesh = bpy.data.meshes.new("XuXiao_SourceHead")
    mesh.vertices.add(len(positions)); mesh.vertices.foreach_set("co", positions.reshape(-1))
    mesh.loops.add(len(inverse)); mesh.loops.foreach_set("vertex_index", inverse)
    count = len(indices)
    mesh.polygons.add(count)
    mesh.polygons.foreach_set("loop_start", np.arange(count, dtype=np.int32) * 3)
    mesh.polygons.foreach_set("loop_total", np.full(count, 3, dtype=np.int32))
    mesh.polygons.foreach_set("use_smooth", np.ones(count, dtype=bool))
    mesh.uv_layers.new(name="UVMap").data.foreach_set("uv", uv)
    mesh.update()
    obj.data = mesh
    bpy.data.meshes.remove(old)
    return source_count


def source_material(directory):
    material = bpy.data.materials.new("XuXiao_Personal_Skin")
    material.use_nodes = True
    nodes, links = material.node_tree.nodes, material.node_tree.links
    bsdf = nodes.get("Principled BSDF")
    for suffix, socket in [(".png", "Base Color"), ("_metallic.png", "Metallic"),
                           ("_roughness.png", "Roughness"), ("_normal.png", "Normal")]:
        image = bpy.data.images.load(str(directory / (STEM + suffix)), check_existing=False)
        image.name = "XuXiao" + suffix
        if suffix != ".png":
            image.colorspace_settings.name = "Non-Color"
        # Keep the supplied texture content, downsample only for the mobile head.
        if max(image.size) > 2048:
            image.scale(2048, 2048)
        image.pack()
        texture = nodes.new("ShaderNodeTexImage"); texture.image = image
        if socket == "Normal":
            normal = nodes.new("ShaderNodeNormalMap")
            links.new(texture.outputs["Color"], normal.inputs["Color"])
            links.new(normal.outputs["Normal"], bsdf.inputs[socket])
        else:
            links.new(texture.outputs["Color"], bsdf.inputs[socket])
    return material


def coarsen_staged_head(source, output):
    receipt = json.loads((source / "geometry-receipt-private.json").read_text())
    original = source / "XuXiao_Head_Staging.blend"
    assert receipt["sourceSHA256"] == ARCHIVE_SHA256 and digest(original) == receipt["stagingSHA256"]
    output.mkdir(parents=True, exist_ok=False)
    bpy.ops.wm.open_mainfile(filepath=str(original))
    obj = bpy.data.objects["XuXiao_Personal_Head"]; old = obj.data
    assert len(old.polygons) == receipt["boundedTriangles"]
    vertices = np.empty(len(old.vertices) * 3, np.float32); old.vertices.foreach_get("co", vertices)
    vertices = vertices.reshape(-1, 3)
    faces = np.empty(len(old.loops), np.int32); old.loops.foreach_get("vertex_index", faces)
    faces = faces.reshape(-1, 3)
    uv = np.empty(len(old.loops) * 2, np.float32); old.uv_layers.active.data.foreach_get("uv", uv)
    uv = uv.reshape(-1, 3, 2)
    _, cells = np.unique(np.floor(vertices / .012).astype(np.int32), axis=0, return_inverse=True)
    cells = cells.reshape(-1); weights = np.bincount(cells)
    vertices = np.stack([np.bincount(cells, weights=vertices[:, i]) / weights for i in range(3)], axis=1).astype(np.float32)
    faces = cells[faces]
    valid = (faces[:, 0] != faces[:, 1]) & (faces[:, 1] != faces[:, 2]) & (faces[:, 2] != faces[:, 0])
    ids = np.flatnonzero(valid)
    _, unique = np.unique(np.sort(faces[ids], axis=1), axis=0, return_index=True)
    ids = ids[np.sort(unique)]; faces = faces[ids].astype(np.int32); uv = uv[ids]
    mesh = bpy.data.meshes.new("XuXiao_SurfaceCoarse")
    mesh.vertices.add(len(vertices)); mesh.vertices.foreach_set("co", vertices.reshape(-1))
    mesh.loops.add(faces.size); mesh.loops.foreach_set("vertex_index", faces.reshape(-1))
    mesh.polygons.add(len(faces)); mesh.polygons.foreach_set("loop_start", np.arange(len(faces), dtype=np.int32) * 3)
    mesh.polygons.foreach_set("loop_total", np.full(len(faces), 3, dtype=np.int32))
    mesh.uv_layers.new(name="UVMap").data.foreach_set("uv", uv.reshape(-1))
    mesh.materials.append(old.materials[0]); mesh.update(); obj.data = mesh
    bpy.data.meshes.remove(old); bpy.context.view_layer.update()
    staging = output / "XuXiao_Head_Staging.blend"
    bpy.ops.wm.save_as_mainfile(filepath=str(staging))
    receipt.update(intermediateStagingSHA256=receipt["stagingSHA256"],
                   stagingSHA256=digest(staging), boundedTriangles=len(faces))
    (output / "geometry-receipt-private.json").write_text(json.dumps(receipt, indent=2))
    print(json.dumps(receipt), flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--stage", choices=("prepare", "coarsen", "finish"), required=True)
    parser.add_argument("--source-stage", type=Path)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    assert args.archive.stat().st_size == 350235206 and digest(args.archive) == ARCHIVE_SHA256
    assert not args.output.resolve().is_relative_to(Path(__file__).resolve().parents[1]), "Keep raw personal assets private"
    if args.stage == "coarsen":
        assert args.source_stage is not None
        coarsen_staged_head(args.source_stage, args.output)
        return
    staging = args.output / "XuXiao_Head_Staging.blend"
    if args.stage == "prepare":
        args.output.mkdir(parents=True, exist_ok=False)
        inputs = args.output / "verified-inputs"; inputs.mkdir()
        with zipfile.ZipFile(args.archive) as archive:
            entries = archive.infolist()
            assert len(entries) == len(FILES)
            by_name = {Path(entry.filename).name: entry for entry in entries}
            assert set(by_name) == {STEM + suffix for suffix in FILES}
            for suffix, (size, sha) in FILES.items():
                entry = by_name[STEM + suffix]
                assert entry.file_size == size and not entry.flag_bits & 1
                raw = archive.read(entry)
                assert len(raw) == size and hashlib.sha256(raw).hexdigest() == sha
                (inputs / (STEM + suffix)).write_bytes(raw)
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.fbx(filepath=str(inputs / (STEM + ".fbx")), use_anim=False, use_image_search=False)
        meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
        assert len(meshes) == 1 and not any(obj.type == "ARMATURE" for obj in bpy.context.scene.objects)
        obj = meshes[0]; obj.name = "XuXiao_Personal_Head"
        before = cropped_mesh(obj)
        obj.data.materials.clear(); obj.data.materials.append(source_material(inputs))
        bpy.ops.outliner.orphans_purge(do_recursive=True)
        bpy.context.view_layer.update()
        bpy.ops.wm.save_as_mainfile(filepath=str(staging))
        receipt = {"sourceSHA256": ARCHIVE_SHA256, "croppedSourceTriangles": before,
            "boundedTriangles": len(obj.data.polygons), "stagingSHA256": digest(staging)}
        (args.output / "geometry-receipt-private.json").write_text(json.dumps(receipt, indent=2))
        print(json.dumps(receipt), flush=True)
        return
    receipt = json.loads((args.output / "geometry-receipt-private.json").read_text())
    assert receipt["sourceSHA256"] == ARCHIVE_SHA256 and digest(staging) == receipt["stagingSHA256"]
    bpy.ops.wm.open_mainfile(filepath=str(staging))
    obj = bpy.data.objects["XuXiao_Personal_Head"]
    assert 28000 < len(obj.data.polygons) == receipt["boundedTriangles"] <= 1000000
    before = receipt["croppedSourceTriangles"]
    bpy.context.view_layer.objects.active = obj; obj.select_set(True)
    # Preserve the clustered source surface and corner UVs. Uniform QEM
    # spends nearly its entire error budget on the sparsely tessellated face
    # while the non-manifold scanned hair stays dense. The 3 mm cluster stage
    # already removes about 98 percent of source triangles without that loss.
    assert len(obj.data.polygons) <= 160000, "Run the coarsen stage first"
    obj.data.validate(clean_customdata=False); obj.data.update()
    # Neutral attachment pivot at the source neck, 0.25 m per source unit.
    # Actual costume proportions/bind transform are reviewed at assembly time.
    for vertex in obj.data.vertices:
        vertex.co.z += 0.08
        vertex.co *= 0.25
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    bpy.ops.outliner.orphans_purge(do_recursive=True)
    obj.data.calc_loop_triangles()
    count = len(obj.data.loop_triangles)
    print(json.dumps({"outputPolygons": len(obj.data.polygons), "outputTriangles": count,
        "outputVertices": len(obj.data.vertices)}), flush=True)
    assert 100000 <= count <= 160000
    blend = args.output / "XuXiao_Personal_Head.blend"
    bpy.ops.wm.save_as_mainfile(filepath=str(blend))
    glb = args.output / "XuXiao_Personal_Head.glb"
    bpy.ops.export_scene.gltf(filepath=str(glb), export_format="GLB", use_selection=True,
        export_animations=False, export_materials="EXPORT", export_image_format="AUTO")
    report = {"character": "徐骁", "requestedCostume": "嬴政／王朝奠基者",
        "sourceArchiveSHA256": ARCHIVE_SHA256, "sourceTriangles": 7562286,
        "croppedSourceTriangles": before, "headTriangles": count, "vertices": len(obj.data.vertices),
        "maximumTextureDimension": 2048, "staticPersonalHeadOnly": True,
        "costumeBound": False, "sourceCostumeFamilyCandidate": "D20 / AGL49 (not yet authenticated)",
        "file": glb.name, "bytes": glb.stat().st_size, "sha256": digest(glb)}
    (args.output / "head-receipt-private.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(report, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
