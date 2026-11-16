"""Fit only a new personal neck mesh to authentic head/collar geometry.

The original portrait is immutable. Its exact-position half edges determine
the open contour, including the two distinct fans at its degree-four point.
The new bridge uses source UV colours and source endpoint normals; it is an
explicit fitting adaptation, not original SF3 geometry or a new portrait.
"""
from __future__ import annotations

import io
import numpy as np
from PIL import Image

from sun_triad_assets import accessor_read, require
from build_erlang_source_assets import sha


def unit(values):
    lengths = np.linalg.norm(values, axis=-1, keepdims=True)
    require(np.all(lengths > 1e-10), 'Degenerate source contour normal')
    return values / lengths


def boundary(g, binary, primitive):
    positions = accessor_read(g, binary, primitive['attributes']['POSITION'])
    original = accessor_read(g, binary, primitive['indices']).reshape(-1, 3)
    # Exact FLOAT positions only: never merge nearby facial vertices by radius.
    unique, inverse = np.unique(positions, axis=0, return_inverse=True)
    faces = inverse[original]
    edges = {}
    for face_index, face in enumerate(faces):
        require(len(set(map(int, face))) == 3, 'Degenerate original portrait triangle')
        for corner in range(3):
            pair = tuple(sorted((int(face[corner]), int(face[(corner + 1) % 3]))))
            edges.setdefault(pair, []).append((face_index, corner))
    require(all(len(items) <= 2 for items in edges.values()), 'Original portrait has a non-manifold edge')
    border = {item for items in edges.values() if len(items) == 1 for item in items}
    twins = {}
    for items in edges.values():
        if len(items) == 2:
            first, second = items
            require(faces[first[0], first[1]] == faces[second[0], (second[1] + 1) % 3] and
                    faces[first[0], (first[1] + 1) % 3] == faces[second[0], second[1]],
                    'Original portrait adjacent face winding differs')
            twins[first], twins[second] = second, first
    successor = {}
    for item in border:
        current = (item[0], (item[1] + 1) % 3)
        seen = set()
        # Walk the real incident face fan, not a nearest-angle pairing at a
        # shared vertex. This resolves the two fans at the degree-four point.
        while current not in border:
            require(current not in seen and current in twins, 'Original boundary face fan cannot be resolved')
            seen.add(current)
            twin = twins[current]
            current = (twin[0], (twin[1] + 1) % 3)
        successor[item] = current
    loops, visited = [], set()
    for item in sorted(border):
        if item in visited:
            continue
        loop, current = [], item
        while current not in visited:
            visited.add(current); loop.append(current); current = successor[current]
        require(current == item, 'Original boundary traversal merged distinct loops')
        loops.append(loop)
    require(len(loops) == 1 and len(loops[0]) == 182, 'Authenticated personal head contour scope differs')
    loop = loops[0]
    ids = np.asarray([original[face, corner] for face, corner in loop], dtype=np.int64)
    points = positions[ids].astype(float)
    area = .5 * np.sum(points[:, 0] * np.roll(points[:, 2], -1) - points[:, 2] * np.roll(points[:, 0], -1))
    require(area < -.01 and len(np.unique(points, axis=0)) == 181, 'Original neck opening orientation differs')
    return ids, dict(method='exact-position-half-edge-original-face-fans',
        boundaryHalfEdges=[[int(face), int(corner)] for face, corner in loop],
        originalVertexIndices=ids.tolist(), halfEdges=182, uniquePositions=181,
        degreeFourPointDisambiguatedByOriginalFaceFans=True, positionQuantizationUsed=False,
        signedXZArea=float(area))


def texture(g, binary, primitive):
    material = g['materials'][primitive['material']]
    pbr = material['pbrMetallicRoughness']
    index = pbr['baseColorTexture']['index']
    image = g['images'][g['textures'][index]['source']]
    view = g['bufferViews'][image['bufferView']]
    start = view.get('byteOffset', 0)
    raw = bytes(binary[start:start + view['byteLength']])
    srgb = np.asarray(Image.open(io.BytesIO(raw)).convert('RGB'), dtype=float) / 255
    linear = np.where(srgb <= .04045, srgb / 12.92, ((srgb + .055) / 1.055) ** 2.4)
    sampler = g['samplers'][g['textures'][index].get('sampler', 0)]
    factor = np.asarray(pbr.get('baseColorFactor', [1, 1, 1, 1])[:3])
    def sample(uv):
        uv = np.asarray(uv, dtype=float)
        x, y = uv[:, 0] * linear.shape[1] - .5, uv[:, 1] * linear.shape[0] - .5
        left, top = np.floor(x).astype(int), np.floor(y).astype(int)
        dx, dy = (x - left)[:, None], (y - top)[:, None]
        def coordinate(values, count, wrap):
            require(wrap in (10497, 33071), 'Unadapted original texture wrapping')
            return np.mod(values, count) if wrap == 10497 else np.clip(values, 0, count - 1)
        x0 = coordinate(left, linear.shape[1], sampler.get('wrapS', 10497))
        x1 = coordinate(left + 1, linear.shape[1], sampler.get('wrapS', 10497))
        y0 = coordinate(top, linear.shape[0], sampler.get('wrapT', 10497))
        y1 = coordinate(top + 1, linear.shape[0], sampler.get('wrapT', 10497))
        return ((linear[y0, x0] * (1 - dx) + linear[y0, x1] * dx) * (1 - dy) +
                (linear[y1, x0] * (1 - dx) + linear[y1, x1] * dx) * dy) * factor
    return sample, dict(material=material.get('name'), textureSHA256=sha(raw),
        filter='linear-light bilinear source texel sampling', imageSize=[linear.shape[1], linear.shape[0]])


def collar(g, binary, world, portrait, neck_local, fractions, first_top):
    nodes = [index for index, node in enumerate(g['nodes']) if node.get('name') == 'arm__agl_44_m']
    require(len(nodes) == 1, 'Original body collar mesh is ambiguous')
    node = nodes[0]; definition = g['nodes'][node]
    require(definition.get('skin') == 0, 'Original collar no longer shares the actor skin')
    primitives = g['meshes'][definition['mesh']]['primitives']
    require(len(primitives) == 1, 'Original collar primitive scope differs')
    primitive = primitives[0]; attributes = primitive['attributes']
    positions = accessor_read(g, binary, attributes['POSITION'])
    normals = accessor_read(g, binary, attributes['NORMAL'])
    uv = accessor_read(g, binary, attributes['TEXCOORD_0'])
    joints = accessor_read(g, binary, attributes['JOINTS_0']).astype(int)
    weights = accessor_read(g, binary, attributes['WEIGHTS_0'])
    matrix = np.linalg.inv(world[portrait]) @ world[node]
    positions = (np.c_[positions, np.ones(len(positions))] @ matrix.T)[:, :3]
    normals = unit(normals @ np.linalg.inv(matrix[:3, :3]))
    faces = accessor_read(g, binary, primitive['indices']).reshape(-1, 3)
    # Choose the existing face-patch boundary around the actual neck axis.
    # Its vertices and edges already exist in the source mesh. Interpolating
    # position and weights at an arbitrary triangle point is not dynamically
    # identical to interpolating the three already-skinned source vertices.
    unique, inverse = np.unique(positions, axis=0, return_inverse=True)
    welded = inverse[faces]
    plane = float(neck_local[1] + .04)
    selected = np.flatnonzero(positions[faces].mean(axis=1)[:, 1] > plane)
    edge_refs = {}
    for face in selected:
        for corner in range(3):
            a, b = welded[face, corner], welded[face, (corner + 1) % 3]
            edge_refs.setdefault(tuple(sorted((int(a), int(b)))), []).append((int(face), corner))
    require(all(len(items) <= 2 for items in edge_refs.values()), 'Collar source patch has a non-manifold edge')
    borders = {edge: items[0] for edge, items in edge_refs.items() if len(items) == 1}
    adjacency = {}
    for a, b in borders:
        adjacency.setdefault(a, []).append(b); adjacency.setdefault(b, []).append(a)
    require(all(len(items) == 2 for items in adjacency.values()), 'Collar source patch boundary is not a set of closed loops')
    visited, candidates = set(), []
    for start in sorted(adjacency):
        if start in visited: continue
        path, previous, current = [], None, start
        while current not in visited:
            visited.add(current); path.append(current)
            choices = adjacency[current]
            following = choices[0] if choices[0] != previous else choices[1]
            previous, current = current, following
        require(current == start, 'Collar source loop merged two components')
        points = unique[path]
        relative = points[:, [0, 2]] - neck_local[[0, 2]]
        other = np.roll(relative, -1, axis=0)
        winding = np.sum(np.arctan2(relative[:, 0]*other[:, 1] - relative[:, 1]*other[:, 0],
                                   np.sum(relative*other, axis=1))) / (2*np.pi)
        if abs(winding) > .5: candidates.append(path)
    require(len(candidates) == 1 and len(candidates[0]) == 15, 'The authenticated source collar vertex loop differs')
    loop = candidates[0]
    points = unique[loop]
    signed_area = .5*np.sum(points[:, 0]*np.roll(points[:, 2], -1) - points[:, 2]*np.roll(points[:, 0], -1))
    if signed_area > 0: loop = list(reversed(loop))
    target_angle = np.arctan2(first_top[2] - neck_local[2], first_top[0] - neck_local[0])
    points = unique[loop]
    angles = np.arctan2(points[:, 2] - neck_local[2], points[:, 0] - neck_local[0])
    start = int(np.argmin(abs(np.angle(np.exp(1j*(angles - target_angle))))))
    loop = loop[start:] + loop[:start]
    starts, ends, original_edges = [], [], []
    for a, b in zip(loop, loop[1:] + loop[:1]):
        face, corner = borders[tuple(sorted((a, b)))]
        pair = [int(faces[face, corner]), int(faces[face, (corner + 1) % 3])]
        if inverse[pair[0]] != a: pair.reverse()
        starts.append(pair[0]); ends.append(pair[1]); original_edges.append(dict(triangle=face, sourceVertexIndices=pair))
    starts, ends = np.asarray(starts), np.asarray(ends)
    dense = np.zeros((len(positions), len(g['skins'][0]['joints'])))
    for vertex in set(starts.tolist() + ends.tolist()):
        for joint, weight in zip(joints[vertex], weights[vertex]): dense[vertex, joint] += weight
    require(np.max(abs(dense[ends] - np.roll(dense[starts], -1, axis=0))) < 1e-7,
            'Coincident collar source seam vertices have different dynamic skinning')
    arc = np.linalg.norm(positions[ends] - positions[starts], axis=1)
    cumulative = np.r_[0., np.cumsum(arc)] / sum(arc)
    points, directions, uvs, bones = [], [], [], []
    for fraction in fractions:
        index = min(len(starts) - 1, int(np.searchsorted(cumulative, fraction, side='right') - 1))
        mix = (fraction - cumulative[index]) / (cumulative[index + 1] - cumulative[index])
        a, b = starts[index], ends[index]
        points.append(positions[a]*(1 - mix) + positions[b]*mix)
        directions.append(unit(normals[a]*(1 - mix) + normals[b]*mix))
        uvs.append(uv[a]*(1 - mix) + uv[b]*mix)
        values = dense[a]*(1 - mix) + dense[b]*mix
        bones.append({int(joint): float(values[joint]) for joint in np.flatnonzero(values > 1e-10)})
    sample, material = texture(g, binary, primitive)
    anchors = dict(starts=starts, ends=ends, positions=positions, normals=normals, uv=uv,
        joints=joints, weights=weights, fractions=cumulative, sourceMaterial=primitive['material'])
    return np.asarray(points), np.asarray(directions), sample(uvs), bones, dict(
        sourceNode=node, sourceMesh=definition['mesh'], sourceMaterial=primitive['material'],
        sourceMaterialProof=material, fittingPlaneOffsetFromNeckMeters=.04, fittingPlaneY=plane,
        method='existing-source-face-patch-edge-loop-around-neck-axis', sourcePatchFaces=len(selected),
        sourceBoundaryVertices=15, sourceEdges=original_edges,
        originalPositionsAndFourSkinAttributesAtBoundary=True, arbitraryBarycentricBoundary=False,
        fittingInteriorInterpolatesSourceEdges=True, sourceBoundaryFractions=cumulative.tolist()), anchors


def fair_loft(bottom, top, rows, lengths):
    """Harmonic interior with both authentic contours fixed exactly.

    Only new bridge interior vertices move. Arc-length and vertical spacing
    weight the finite-difference operator, so tiny original cut edges are not
    mistaken for equal angular steps and extended as long pleats.
    """
    from scipy.sparse import lil_matrix
    from scipy.sparse.linalg import spsolve
    count = len(top); inner = (len(rows) - 2)*count
    matrix = lil_matrix((inner, inner)); rhs = np.zeros((inner, 3))
    height = float(np.mean(top[:, 1] - bottom[:, 1]))
    vertical = np.diff(rows)*height
    for row in range(1, len(rows) - 1):
        for col in range(count):
            index = (row - 1)*count + col
            before, after = lengths[(col - 1) % count], lengths[col]
            lower, upper = vertical[row - 1], vertical[row]
            terms = [(row, (col - 1) % count, 2/(before*(before + after))),
                     (row, (col + 1) % count, 2/(after*(before + after))),
                     (row - 1, col, 2/(lower*(lower + upper))),
                     (row + 1, col, 2/(upper*(lower + upper)))]
            matrix[index, index] = sum(weight for _, _, weight in terms)
            for neighbour, other, weight in terms:
                if neighbour == 0:
                    rhs[index] += weight*bottom[other]
                elif neighbour == len(rows) - 1:
                    rhs[index] += weight*top[other]
                else:
                    matrix[index, (neighbour - 1)*count + other] -= weight
    interior = spsolve(matrix.tocsr(), rhs).reshape(len(rows) - 2, count, 3)
    result = np.concatenate([bottom[None], interior, top[None]], axis=0)
    ruled = np.asarray([bottom*(1 - t) + top*t for t in rows])
    vertical_steps = np.diff(result[:, :, 1], axis=0)
    require(np.isfinite(result).all(), 'Non-finite contour fairing')
    return result, dict(method='metric-weighted-harmonic-interior-with-fixed-source-boundaries',
        originalTopAndBottomPositionsFixed=True, rows=len(rows),
        maximumDisplacementFromRuledMeters=float(np.max(np.linalg.norm(result - ruled, axis=2))),
        negativeVerticalSteps=int(np.sum(vertical_steps < -1e-8)),
        maximumVerticalBacktrackMeters=float(max(0., -np.min(vertical_steps))))


def split_opening(positions, ids):
    """Separate the authentic small opposite-winding hole at the pinch.

    The source half-edge walk visits its degree-four position twice. These two
    visits bound a ten-edge local hole; extruding that hole all the way to the
    collar creates an artificial pleat. It is instead closed locally, using
    only its original positions, normals, UVs and original portrait material.
    """
    points = positions[ids]
    _, inverse, counts = np.unique(points, axis=0, return_inverse=True, return_counts=True)
    duplicated = np.flatnonzero(counts == 2)
    require(len(duplicated) == 1 and max(counts) == 2, 'Original contour pinch topology differs')
    first, second = np.flatnonzero(inverse == duplicated[0])
    inner = np.arange(first, second)
    outer = np.r_[np.arange(first), np.arange(second, len(ids))]
    def area(loop):
        return float(.5*np.sum(loop[:, 0]*np.roll(loop[:, 2], -1) - loop[:, 2]*np.roll(loop[:, 0], -1)))
    require(len(inner) == 10 and len(outer) == 172 and 1e-5 < area(points[inner]) < 2e-5
            and area(points[outer]) < -.016, 'Original local hole and main neck opening differ')
    polygon = points[inner][:, [0, 2]]
    def cross(a, b, c):
        return (b[0] - a[0])*(c[1] - a[1]) - (b[1] - a[1])*(c[0] - a[0])
    remaining = list(range(len(inner))); triangles = []
    while len(remaining) > 3:
        for offset in range(len(remaining)):
            a, b, c = remaining[offset - 1], remaining[offset], remaining[(offset + 1) % len(remaining)]
            if cross(polygon[a], polygon[b], polygon[c]) <= 1e-12:
                continue
            if any(min(cross(polygon[a], polygon[b], polygon[p]),
                       cross(polygon[b], polygon[c], polygon[p]),
                       cross(polygon[c], polygon[a], polygon[p])) >= -1e-12
                   for p in remaining if p not in (a, b, c)):
                continue
            # A cap reverses the existing source boundary edge orientation.
            triangles.append((c, b, a)); remaining.pop(offset); break
        else:
            raise ValueError('Original ten-edge local hole cannot be triangulated without crossing')
    triangles.append(tuple(reversed(remaining)))
    return outer, inner, np.asarray(triangles, dtype=np.uint32), dict(
        method='exact-shared-position-split-with-opposite-source-winding', mainOpeningHalfEdges=172,
        localHoleHalfEdges=10, localHoleTriangles=8, all182OriginalBoundaryEdgesCovered=True,
        originalSharedPosition=points[first].tolist(),
        localHoleSignedXZArea=area(points[inner]), mainOpeningSignedXZArea=area(points[outer]),
        localHoleBoundsExtentMeters=np.ptp(points[inner], axis=0).tolist(),
        localHoleOriginalVertexIndices=ids[inner].tolist(), mainOpeningOriginalVertexIndices=ids[outer].tolist(),
        localHoleUsesOriginalPortraitMaterialAndUV=True, localHoleDoesNotExtendToCollar=True)


def collar_zipper(anchors, fractions, grid_positions, grid_normals, grid_weights, grid_joints):
    """Join two different vertex counts without inventing boundary skinning."""
    count = len(fractions); body_count = len(anchors['starts'])
    top_parameters = np.r_[fractions, 1.]
    positions, normals, uv, joints, weights, source_copies = [], [], [], [], [], []
    def lower(edge, endpoint=0):
        source = int(anchors['ends'][body_count - 1] if edge == body_count else
                     anchors['ends'][edge] if endpoint else anchors['starts'][edge])
        return (anchors['positions'][source], anchors['normals'][source], anchors['uv'][source],
                anchors['joints'][source], anchors['weights'][source], source)
    def upper(column):
        fraction = top_parameters[column]
        edge = min(body_count - 1, int(np.searchsorted(anchors['fractions'], fraction, side='right') - 1))
        mix = (fraction - anchors['fractions'][edge]) / (anchors['fractions'][edge + 1] - anchors['fractions'][edge])
        a, b = anchors['starts'][edge], anchors['ends'][edge]
        texture_uv = anchors['uv'][a]*(1 - mix) + anchors['uv'][b]*mix
        index = count + 1 + column
        return (grid_positions[index], grid_normals[index], texture_uv,
                grid_joints[index], grid_weights[index], None)
    body, top = 0, 0
    while body < body_count or top < count:
        next_body = anchors['fractions'][body + 1] if body < body_count else np.inf
        next_top = top_parameters[top + 1] if top < count else np.inf
        if next_body <= next_top:
            triangle = (lower(body), lower(body, 1), upper(top)); body += 1
        else:
            triangle = (lower(body), upper(top + 1), upper(top)); top += 1
        for point, normal, texture_uv, joint, weight, source in triangle:
            if source is not None: source_copies.append(dict(vertex=len(positions), sourceVertex=source))
            positions.append(point); normals.append(normal); uv.append(texture_uv)
            joints.append(joint); weights.append(weight)
    require(len(positions) == 3*(body_count + count), 'Variable collar edge triangulation differs')
    return dict(positions=np.asarray(positions), normals=np.asarray(normals), uv=np.asarray(uv),
        joints=np.asarray(joints, dtype=np.uint16), weights=np.asarray(weights, dtype=np.float32),
        indices=np.arange(len(positions), dtype=np.uint32).reshape(-1, 3),
        sourceCopies=source_copies, sourceMaterial=anchors['sourceMaterial'])


def fit(g, binary, primitive, world, portrait, head, neck):
    ids, contour = boundary(g, binary, primitive)
    attrs = primitive['attributes']
    all_positions = accessor_read(g, binary, attrs['POSITION'])
    outer, inner, cap_faces, opening = split_opening(all_positions, ids)
    cap_ids = ids[inner]
    original_faces = accessor_read(g, binary, primitive['indices']).reshape(-1, 3)
    all_end_ids = np.asarray([original_faces[face, (corner + 1) % 3]
        for face, corner in contour['boundaryHalfEdges']])
    all_uv = accessor_read(g, binary, attrs['TEXCOORD_0'])
    require(np.array_equal(all_uv[all_end_ids[inner]], np.roll(all_uv[cap_ids], -1, axis=0)),
            'The original local hole crosses a UV island; direct source-UV cap is unavailable')
    end_ids = all_end_ids[outer]
    ids = ids[outer]
    top = all_positions[ids].astype(float)
    top_normals = unit(accessor_read(g, binary, attrs['NORMAL'])[ids].astype(float))
    top_uv = accessor_read(g, binary, attrs['TEXCOORD_0'])[ids].astype(float)
    neck_local = np.linalg.inv(world[portrait]) @ world[neck][:, 3]
    lengths = np.linalg.norm(np.roll(top, -1, axis=0) - top, axis=1)
    require((lengths > 1e-8).all(), 'Original contour contains a zero-length edge')
    fraction = np.r_[0, np.cumsum(lengths)[:-1]] / sum(lengths)
    bottom, bottom_normals, bottom_colors, bottom_bones, collar_proof, anchors = collar(
        g, binary, world, portrait, neck_local, fraction, top[0])
    require(np.min(top[:, 1] - bottom[:, 1]) > .035, 'Personal neck fitting has an inverted vertical span')
    sample_head, head_material = texture(g, binary, primitive)
    end_uv = accessor_read(g, binary, attrs['TEXCOORD_0'])[end_ids].astype(float)
    region = (all_positions[:, 1] >= .015) & (all_positions[:, 1] <= .095) & (all_positions[:, 2] >= .025)
    skin = sample_head(all_uv[region])
    srgb_skin = np.where(skin <= .0031308, skin * 12.92, 1.055 * skin ** (1 / 2.4) - .055)
    selected = ((srgb_skin[:, 0] > .6) & (srgb_skin[:, 0] - srgb_skin[:, 1] > .04) &
                (srgb_skin[:, 1] - srgb_skin[:, 2] > .015))
    require(selected.sum() > 200, 'No bounded authentic lower-front skin colour sample')
    skin_color = np.median(skin[selected], axis=0)
    rows = np.asarray([0., .035, .10, .20, .40, .60, .80, .93, .98, 1.])
    columns = len(top)
    fitted, fairing = fair_loft(bottom, top, rows, lengths)
    positions, texcoords, joint_values, weight_values = [], [], [], []
    source_skin = g['skins'][0]
    head_slot = source_skin['joints'].index(head)
    discarded = 0.
    for row, t in enumerate(rows):
        points = fitted[row]
        head_weight = t*t*(3 - 2*t)
        for col in range(columns + 1):
            source = col % columns
            positions.append(points[source]); texcoords.append([col / columns, 1 - t])
            influences = {joint: (1 - head_weight)*value for joint, value in bottom_bones[source].items()}
            influences[head_slot] = influences.get(head_slot, 0.) + head_weight
            ranked = sorted(influences.items(), key=lambda pair: (-pair[1], pair[0]))
            discarded = max(discarded, sum(value for _, value in ranked[4:]))
            ranked = ranked[:4]; total = sum(value for _, value in ranked)
            joint_values.append([joint for joint, _ in ranked] + [0]*(4 - len(ranked)))
            weight_values.append([value / total for _, value in ranked] + [0.]*(4 - len(ranked)))
    require(discarded < .01, 'Collar fitting exceeds the four-influence adaptation bound')
    positions = np.asarray(positions, dtype=np.float32)
    triangles = []
    for row in range(len(rows) - 1):
        for col in range(columns):
            a = row*(columns + 1) + col; b = a + 1; c = a + columns + 1; d = c + 1
            triangles.extend(((a, b, c), (b, d, c)))
    triangles = np.asarray(triangles, dtype=np.uint32)
    normals = np.zeros_like(positions)
    for face in triangles:
        a, b, c = positions[face]; normal = np.cross(b - a, c - a)
        require(np.linalg.norm(normal) > 1e-12, 'Generated contour bridge has a degenerate triangle')
        for index in face: normals[index] += normal
    # The closing UV seam has two coincident vertices. Accumulate both face
    # fans before normalizing, so UV isolation does not create a hard normal
    # seam through the new neck.
    for row in range(len(rows)):
        first, last = row*(columns + 1), row*(columns + 1) + columns
        shared = normals[first] + normals[last]
        normals[first] = shared; normals[last] = shared
    normals = unit(normals)
    for row, t in enumerate(rows):
        for col in range(columns + 1):
            index = row*(columns + 1) + col; source = col % columns
            if t >= .98:
                blend = (t - .98) / .02
                normals[index] = unit(normals[index]*(1 - blend) + top_normals[source]*blend)
            elif t <= .10:
                blend = 1 - t / .10
                normals[index] = unit(normals[index]*(1 - blend) + bottom_normals[source]*blend)
    # Each original boundary edge gets its own narrow image strip. Its two
    # actual face UV endpoints can belong to different islands from adjacent
    # edges. Never interpolate between those unrelated island coordinates.
    edge_samples, height = 32, 257
    stride = edge_samples + 2  # one duplicate texel gutter at either end
    width = columns*stride
    amount = np.linspace(0, 1, edge_samples)[None, :, None]
    edge_uv = top_uv[:, None, :]*(1 - amount) + end_uv[:, None, :]*amount
    top_row = sample_head(edge_uv.reshape(-1, 2)).reshape(columns, edge_samples, 3)
    bottom_row = bottom_colors[:, None, :]*(1 - amount) + np.roll(bottom_colors, -1, axis=0)[:, None, :]*amount
    top_row = np.concatenate([top_row[:, :1], top_row, top_row[:, -1:]], axis=1).reshape(width, 3)
    bottom_row = np.concatenate([bottom_row[:, :1], bottom_row, bottom_row[:, -1:]], axis=1).reshape(width, 3)
    pixels = []
    for v in np.linspace(0, 1, height):
        top_blend = min(1., v / .04); top_blend = top_blend**2*(3 - 2*top_blend)
        colour = top_row*(1 - top_blend) + skin_color*top_blend
        lower = np.clip((v - .65)/.35, 0, 1); lower = lower**2*(3 - 2*lower)
        colour = colour*(1 - lower) + bottom_row*lower
        srgb = np.where(colour <= .0031308, colour*12.92, 1.055*np.maximum(colour, 0)**(1/2.4) - .055)
        pixels.append(np.round(np.clip(srgb, 0, 1)*255).astype(np.uint8))
    stream = io.BytesIO(); Image.fromarray(np.asarray(pixels), 'RGB').save(stream, format='PNG')
    png = stream.getvalue()
    # Duplicate only bridge strip corners; source vertices remain immutable.
    # Geometry/normals on either side of an atlas seam are identical, while UV
    # endpoints can preserve both original face islands.
    skirt = collar_zipper(anchors, fraction, positions, normals, np.asarray(weight_values), np.asarray(joint_values))
    # The barycentric construction ring is used only to fit the interior. The
    # actual bottom boundary is the 15 original body vertices in the zipper.
    expansion = np.asarray([row*(columns + 1) + edge + endpoint
        for row in range(1, len(rows)) for edge in range(columns) for endpoint in (0, 1)])
    positions, normals = positions[expansion], normals[expansion]
    joint_values = np.asarray(joint_values, dtype=np.uint16)[expansion]
    weight_values = np.asarray(weight_values, dtype=np.float32)[expansion]
    texcoords = np.asarray([[(edge*stride + 1.5 + endpoint*(edge_samples - 1))/width,
                            (.5 + (1 - t)*(height - 1))/height]
        for t in rows[1:] for edge in range(columns) for endpoint in (0, 1)], dtype=np.float32)
    triangles = []
    for row in range(len(rows) - 2):
        for edge in range(columns):
            a = row*columns*2 + edge*2; b = a + 1; c = a + columns*2; d = c + 1
            triangles.extend(((a, b, c), (b, d, c)))
    triangles = np.asarray(triangles, dtype=np.uint32)
    skirt_offset = len(positions)
    auxiliary = [dict(indices=skirt['indices'] + skirt_offset, sourceMaterial=skirt['sourceMaterial'])]
    positions = np.concatenate([positions, skirt['positions']])
    normals = np.concatenate([normals, skirt['normals']])
    texcoords = np.concatenate([texcoords, skirt['uv']])
    joint_values = np.concatenate([joint_values, skirt['joints']])
    weight_values = np.concatenate([weight_values, skirt['weights']])
    auxiliary.append(dict(indices=cap_faces + len(positions), sourceMaterial=primitive['material']))
    positions = np.concatenate([positions, all_positions[cap_ids].astype(np.float32)])
    normals = np.concatenate([normals, unit(accessor_read(g, binary, attrs['NORMAL'])[cap_ids].astype(float))])
    texcoords = np.concatenate([texcoords, all_uv[cap_ids].astype(np.float32)])
    cap_joints = np.zeros((len(cap_ids), 4), dtype=np.uint16); cap_joints[:, 0] = head_slot
    cap_weights = np.zeros((len(cap_ids), 4), dtype=np.float32); cap_weights[:, 0] = 1
    joint_values = np.concatenate([joint_values, cap_joints])
    weight_values = np.concatenate([weight_values, cap_weights])
    proof = dict(contour=contour, opening=opening, collar=collar_proof, originalHeadMaterial=head_material,
        sourceHeadUV=top_uv.tolist(), sourceHeadEdgeEndUV=end_uv.tolist(), sourceHeadNormals=top_normals.tolist(),
        originalUVIslandJunctions=int(np.sum(np.linalg.norm(end_uv - np.roll(top_uv, -1, axis=0), axis=1) > 1e-6)),
        sourceUVIslandEndpointsPreserved=True, atlasSourceSamplesPerBoundaryEdge=edge_samples,
        sourceColourTransitionFraction=.04, sourceNormalTransitionFraction=.02,
        loft='fair-interior-original-contour-to-actual-collar', fairing=fairing,
        topRingOffset=(len(rows) - 2)*columns*2, ringVertexCount=columns*2,
        bodyBoundarySourceCopies=[dict(vertex=row['vertex'] + skirt_offset, sourceVertex=row['sourceVertex'])
            for row in skirt['sourceCopies']],
        bodyBoundaryUsesExactSourceVertexSkinning=True, collarZipperTriangles=len(skirt['indices']),
        sourceSkinColourVertices=int(selected.sum()), skinColourLinear=skin_color.tolist(),
        maximumDiscardedCollarWeight=discarded, generatedAtlasSHA256=sha(png), generatedAtlasBytes=len(png),
        generatedAtlasSize=[width, height], topRingUsesExactSourcePositionNormalAndUVSamples=True,
        originalPortraitModified=False, originalAnimationModified=False,
        fittingAdaptation=True, sourceShaderParity=False, nativeRenderingVerified=False)
    return positions, normals, triangles, weight_values, joint_values, texcoords, png, proof, auxiliary
