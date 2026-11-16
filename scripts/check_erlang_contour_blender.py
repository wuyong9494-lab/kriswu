"""Check the actual fitted actor through Blender's evaluated animation poses.

Run with Blender, after -- pass the GLB and a new private JSON receipt path.
This checks geometry correspondence, not Metal or final character appearance.
"""
import hashlib
import json
import math
from pathlib import Path
import struct
import sys

import bpy
from mathutils import kdtree


def main():
    arguments = sys.argv[sys.argv.index('--') + 1:]
    if len(arguments) != 2:
        raise ValueError('Expected GLB and new private check receipt')
    model, destination = map(Path, arguments)
    if destination.exists():
        raise ValueError('Refuse to replace a private geometry check')
    raw = model.read_bytes()
    length, kind = struct.unpack_from('<II', raw, 12)
    if raw[:4] != b'glTF' or kind != 0x4E4F534A:
        raise ValueError('Expected the actual GLB JSON chunk')
    gltf = json.loads(raw[20:20 + length])
    receipt = json.loads((model.parent/'erlang-personal-neck-bridge-private.json').read_bytes())
    if hashlib.sha256(raw).hexdigest() != receipt['character']['sha256']:
        raise ValueError('Fitted actor bytes differ from their private receipt')
    proof = receipt['material']
    head_indices = proof['contour']['originalVertexIndices']
    body_indices = sorted({row['sourceVertex'] for row in proof['bodyBoundarySourceCopies']})
    if len(head_indices) != 182 or proof['collar']['sourceBoundaryVertices'] != 15:
        raise ValueError('Expected authentic complete head and exact body boundaries')
    bpy.ops.wm.read_factory_settings(use_empty=True)
    # BLENDER's cosmetic bone-length heuristic divides by actor scale .92,
    # while its rigid bone-child offset does not, causing a false 12.34 mm gap.
    # TEMPERANCE preserves the source correspondence without moving any object.
    bpy.ops.import_scene.gltf(filepath=str(model), bone_heuristic='TEMPERANCE')
    scene = bpy.context.scene
    armature = bpy.data.objects['SF3_Actor_Meters']
    head = bpy.data.objects['WuYong_Personal_Head']
    body = bpy.data.objects['arm__agl_44_m']
    bridge = bpy.data.objects['Personal_Neck_Bridge']
    if len(head.data.vertices) != 59878 or len(body.data.vertices) != 5560:
        raise ValueError('Importer changed original vertex indexing; do not infer correspondence')
    for obj in scene.objects:
        if obj.animation_data:
            for track in obj.animation_data.nla_tracks:
                track.mute = True
            obj.animation_data.use_nla = False
    used_bridge_vertices = sorted({index for polygon in bridge.data.polygons for index in polygon.vertices})
    if not used_bridge_vertices:
        raise ValueError('No actual rendered bridge triangles')
    results = []
    for animation in gltf['animations']:
        name = animation['name']
        action = bpy.data.actions.get(name + '_' + armature.name)
        if action is None:
            raise ValueError('No exact imported source animation: ' + name)
        armature.animation_data.action = action
        start, end = map(float, action.frame_range)
        samples = []
        for frame in (start, (start + end)/2, end):
            scene.frame_set(math.floor(frame), subframe=frame - math.floor(frame))
            bpy.context.view_layer.update()
            graph = bpy.context.evaluated_depsgraph_get()
            evaluated_bridge = bridge.evaluated_get(graph)
            mesh = evaluated_bridge.to_mesh()
            tree = kdtree.KDTree(len(used_bridge_vertices))
            for index in used_bridge_vertices:
                tree.insert(evaluated_bridge.matrix_world @ mesh.vertices[index].co, index)
            tree.balance()
            head_error = max(tree.find(head.matrix_world @ head.data.vertices[index].co)[2]
                             for index in head_indices)
            evaluated_body = body.evaluated_get(graph)
            source_mesh = evaluated_body.to_mesh()
            body_error = max(tree.find(evaluated_body.matrix_world @ source_mesh.vertices[index].co)[2]
                             for index in body_indices)
            evaluated_body.to_mesh_clear(); evaluated_bridge.to_mesh_clear()
            if max(head_error, body_error) > 2e-6:
                raise ValueError('Source boundary correspondence failed at ' + name + ': ' +
                                 str((frame, head_error, body_error)))
            samples.append(dict(frame=frame, maximumHeadDistanceMeters=head_error,
                                maximumBodyDistanceMeters=body_error))
        results.append(dict(sourceAnimation=name, samples=samples))
    if len(results) != 62:
        raise ValueError('The complete 62 source animations were not checked')
    output = dict(schema='erlang-contour-blender-source-boundaries-v1',
        characterSHA256=hashlib.sha256(raw).hexdigest(), blenderVersion=bpy.app.version_string,
        importerBoneHeuristic='TEMPERANCE', originalObjectTransformsManuallyChanged=False,
        originalHeadVertices=59878, originalBodyVertices=5560, sourceAnimations=62, evaluatedPoses=186,
        headBoundaryHalfEdges=182, bodyBoundaryVertices=15,
        maximumHeadDistanceMeters=max(row['maximumHeadDistanceMeters'] for result in results for row in result['samples']),
        maximumBodyDistanceMeters=max(row['maximumBodyDistanceMeters'] for result in results for row in result['samples']),
        toleranceMeters=2e-6, results=results, nativeMetalOrFinalAppearanceAcceptance=False)
    destination.write_text(json.dumps(output, ensure_ascii=False, separators=(',', ':')) + '\n')
    print(json.dumps({key: value for key, value in output.items() if key != 'results'}), flush=True)


if __name__ == '__main__':
    main()
