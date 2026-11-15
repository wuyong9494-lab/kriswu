#!/usr/bin/env python3
"""Export only the reviewed original normal Avatar material, without binding it.

Inputs are three exact, local Android source bundles. The selected original
GLSL is kept private and digest-checked before its interface is adapted to MSL.
No actor, runtime event, release identity, texture LOD, or generic fade is added.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path

from erlang_effect_materials import selected_program
from erlang_source_metal import BUILTIN, convert_body, declarations, section, typ
from sun_triad_assets import private_output, require, write_private


BUNDLES = {
    'shader': ('b77cd85962dab26b5e542811e8599be3.bin', 1785198,
               'c0b1fe09ba0684e474297ade8dcd7fee7b5d2e780236029c544c1986dea1e972'),
    'material': ('ba154b0890fcb9346f0029c44aecc692.bin', 1806536,
                 'bc741a39383c9a02e718e7eea91fb71394b5c2414347b7ecafae640e1a1d0a93'),
    'textures': ('9d3e616ea68b083cc7b1b8b92e5f72a8.bin', 68114260,
                 'feffa7c512ceb35663bf7fdd80910ff0927c0f8b31deabdd8413777383392f2e'),
}
MATERIAL_ID = 6052238147740425361
MATERIAL_SHA = 'a0fa93408bb0cc520ec64cb8b77d460c8562837dc808198a9e7f072bf3729cbc'
SHADER_ID = 6408001018632598985
SHADER_SHA = '6137a33162d8c22bacba3c1a6714180f6137186385d4fad4545caac65e8d359c'
PROGRAM_SHA = '2a938668e0efa84f063a77636613ca24e639de7beb5191796770a1ca5598bdc5'
KEYWORDS = frozenset(('_USE_CAMERA_OFFSET_OFF', '_USE_SMOOTHSTEP_OFF',
                     '_USE_OFF', '_USE_CLAMP_OFF', '_MIN_BLENDING'))
TEXTURES = {
    '_BackgrTex': dict(id=-641309692710952876, label='wavyshocks', mips=1,
        objectSHA='05f921498ec62ae31fb8fad77305eba160639b72e6b4090c9b482518b86e2a82',
        dataBytes=262144, dataSHA='69975fddf73fdfb57ec55e1c1b2a009184cd8aa3ed429210f68942e69b7e8bea',
        displayedTopRGBA='4a0f9e11efb463723babe3138430bda0ebf8d93133bf3810d7da94b14a8287d0'),
    '_MainTex': dict(id=-4727852512917511309, label='caustic-noise', mips=10,
        objectSHA='a7b94d33b436e107be399a198a73b7dd493b206312d0065fc9d550a82e6b16cd',
        dataBytes=349552, dataSHA='da1a9435f0c7c6e376abba56e4363426cc5a50f11629ee06051f4f8008ea250f',
        displayedTopRGBA='be57fee962eb94f4fc6b313d9b7be1b51cf93ff551b8342d303a2403ff5b0b57'),
}


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def save_json(path, value):
    write_private(path, (json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + '\n').encode())


def resource(output, name, raw):
    write_private(output / name, raw)
    return dict(file=name, bytes=len(raw), sha256=sha(raw))


def exact_object(environment, path_id, kind, digest):
    matches = [o for o in environment.objects if o.path_id == path_id and o.type.name == kind]
    require(len(matches) == 1, 'Original Avatar object is missing or ambiguous')
    obj = matches[0]
    require(sha(obj.get_raw_data()) == digest, 'Original Avatar object bytes differ')
    return obj


def etc2_mip_ranges(width, height, count, total):
    """ETC2 RGBA8 has one 16-byte block per padded 4x4 area, even at 2x2/1x1."""
    require(all(type(v) is int for v in (width, height, count, total)), 'Mip dimensions must be integers')
    require(0 < width <= 4096 and 0 < height <= 4096 and
            0 < count <= max(width, height).bit_length(), 'Invalid original mip extent')
    offset, result = 0, []
    for level in range(count):
        w, h = max(1, width >> level), max(1, height >> level)
        size = ((w + 3) // 4) * ((h + 3) // 4) * 16
        result.append(dict(level=level, width=w, height=h, offset=offset, bytes=size))
        offset += size
    require(offset == total, 'Original mip chain is truncated or has extra bytes')
    return result


def source_metal(source):
    """Reuse reviewed expression substitutions; supply source-space actor inputs.

The particle adapter's position reflection, scaling, UV routing and tint are
intentionally not called. This interface receives already skinned source-space
vertices, original normal/color/tangent.w and caller-supplied source matrices.
"""
    require(len(source) == 6794 and sha(source) == PROGRAM_SHA, 'Unreviewed original Avatar program')
    vertex, fragment = (section(source.decode('utf8'), s) for s in ('VERTEX', 'FRAGMENT'))
    require(vertex['inputs'] == [('vec4', 'in_POSITION0'), ('vec4', 'in_TEXCOORD1'),
        ('vec4', 'in_COLOR0'), ('vec4', 'in_TANGENT0'), ('vec3', 'in_NORMAL0')],
        'Original Avatar vertex input interface differs')
    shared = {n: t for t, n in vertex['outputs']}
    require(shared == {'vs_TEXCOORD3': 'vec3', 'vs_COLOR0': 'vec4', 'vs_TEXCOORD4': 'vec3'} and
            all(shared.get(n) == t for t, n in fragment['inputs']), 'Original Avatar varyings differ')
    uniforms = {n: t for s in (vertex, fragment) for t, n, a in s['uniforms']
                if n not in BUILTIN and t != 'sampler2D'}
    names = sorted(uniforms)
    textures = sorted({n for s in (vertex, fragment) for t, n, a in s['uniforms'] if t == 'sampler2D'})
    require(len(names) <= 64 and textures == ['_BackgrTex', '_MainTex', '_MainTex2'] and
            uniforms['_Invert'] == 'int', 'Original Avatar uniform interface differs')
    code = ('#include <metal_stdlib>\nusing namespace metal;\n'
            'struct AvatarSourceVertex { float4 position, normal, tangent, color, uv1; };\n'
            'struct AvatarSourceUniforms { float4 data[96]; };\n'
            'struct AvatarSourceIO { float4 position [[position]];\n')
    code += ''.join(f'    {typ(t)} {n};\n' for n, t in shared.items()) + '};\n'
    code += ('vertex AvatarSourceIO avatar_normal_vertex(uint id [[vertex_id]], '
             'const device AvatarSourceVertex* vertices [[buffer(0)]], '
             'constant AvatarSourceUniforms& u [[buffer(2)]]) {\n'
             '    AvatarSourceIO o; AvatarSourceVertex a=vertices[id];\n')
    inputs = {'in_POSITION0': 'a.position', 'in_NORMAL0': 'a.normal.xyz',
              'in_TANGENT0': 'a.tangent', 'in_COLOR0': 'a.color', 'in_TEXCOORD1': 'a.uv1'}
    code += ''.join(f'    {typ(t)} {n} = {inputs[n]};\n' for t, n in vertex['inputs'])
    code += declarations(vertex, names) + '\n'
    code += '\n'.join('    ' + line for line in vertex['temps']) + '\n'
    code += convert_body(vertex['body'], shared, 'o') + '\n}\n'
    args = ', '.join(f'texture2d<float> {n} [[texture({i})]], sampler {n}Sampler [[sampler({i})]]'
                     for i, n in enumerate(textures))
    code += ('fragment float4 avatar_normal_fragment(AvatarSourceIO i [[stage_in]], '
             'constant AvatarSourceUniforms& u [[buffer(2)]], ' + args + ') {\n'
             '    float4 SV_Target0;\n')
    code += declarations(fragment, names) + '\n'
    code += '\n'.join('    ' + line for line in fragment['temps']) + '\n'
    code += convert_body(fragment['body'], [n for t, n in fragment['inputs']], 'i', True) + '\n}\n'
    return code.encode(), [dict(name=n, type=uniforms[n], float4Slot=32+i) for i, n in enumerate(names)], textures


def material_values(material, uniforms):
    saved = material['m_SavedProperties']
    floats, colors, textures = (dict(saved[k]) for k in ('m_Floats', 'm_Colors', 'm_TexEnvs'))
    result = []
    for spec in uniforms:
        name, kind = spec['name'], spec['type']
        if name.endswith('_ST'):
            texture = textures[name[:-3]]
            value = [texture['m_Scale']['x'], texture['m_Scale']['y'],
                     texture['m_Offset']['x'], texture['m_Offset']['y']]
        elif kind == 'vec4':
            value = [colors[name][k] for k in ('r', 'g', 'b', 'a')]
        else:
            require(kind in ('float', 'int') and name in floats, 'Unresolved original material uniform')
            require(kind != 'int' or floats[name] == int(floats[name]), 'Original integer uniform is fractional')
            value = [floats[name], 0., 0., 0.]
        require(all(math.isfinite(v) for v in value), 'Nonfinite original material uniform')
        result.append(dict(spec, value=value))
    return result


def export_texture(obj, expected, output):
    from UnityPy.export.Texture2DConverter import parse_image_data
    tree, texture = obj.read_typetree(), obj.read()
    require((tree['m_Width'], tree['m_Height'], tree['m_TextureFormat'], tree['m_MipCount']) ==
            (512, 512, 47, expected['mips']), 'Original Avatar texture metadata differs')
    data = texture.get_image_data()
    require(len(data) == expected['dataBytes'] and sha(data) == expected['dataSHA'],
            'Original Avatar texture stream differs')
    layout = etc2_mip_ranges(512, 512, expected['mips'], len(data))
    label = expected['label']
    stream = resource(output, label + '.source-etc2.bin', data)
    levels = []
    for mip in layout:
        part = data[mip['offset']:mip['offset'] + mip['bytes']]
        image = parse_image_data(part, mip['width'], mip['height'], 47,
            obj.version, obj.platform, getattr(texture, 'm_PlatformBlob', None), flip=False)
        require(image.mode == 'RGBA' and image.size == (mip['width'], mip['height']), 'Source mip decode differs')
        rgba = image.tobytes()
        if mip['level'] == 0:
            stride = mip['width'] * 4
            displayed = b''.join(rgba[y*stride:(y+1)*stride] for y in range(mip['height']-1, -1, -1))
            require(sha(displayed) == expected['displayedTopRGBA'], 'Recovered top-mip row/channel identity differs')
        levels.append(dict(mip, compressedSHA256=sha(part),
            rgba=resource(output, f'{label}.mip{mip["level"]}.rgba', rgba)))
    return dict(sourcePathID=str(obj.path_id), sourceObjectSHA256=sha(obj.get_raw_data()),
        sourceName=tree['m_Name'], sourceTextureFormat=47, sourceColorSpace=tree['m_ColorSpace'],
        sourceSampler=tree['m_TextureSettings'], originalStream=stream, mips=levels,
        rgbaRowOrder='original decoded texture rows; flip=False; no resample or generated mips')


def prepare(source_bundles, output):
    import UnityPy
    require(UnityPy.__version__ == '1.25.4', 'Use reviewed UnityPy1.25.4')
    UnityPy.config.FALLBACK_UNITY_VERSION = '6000.3.11f1'
    output = private_output(output)
    require(not any(output.iterdir()), 'Avatar source output must be a new empty private directory')
    environments, source_records = {}, []
    for label, (name, size, digest) in BUNDLES.items():
        raw = (source_bundles / name).read_bytes()
        require(len(raw) == size and sha(raw) == digest, 'Original Avatar source bundle differs')
        environments[label] = UnityPy.load(raw)
        source_records.append(dict(file=name, bytes=size, sha256=digest))
    obj = exact_object(environments['material'], MATERIAL_ID, 'Material', MATERIAL_SHA)
    material = obj.read_typetree()
    require(material['m_Name'] == 'mtl_Erlang_triplanar_Avatar' and
            set(material['m_ValidKeywords']) == KEYWORDS and not material['m_InvalidKeywords'],
            'Original normal Avatar material identity differs')
    require(material['m_Shader'] == dict(m_FileID=1, m_PathID=SHADER_ID), 'Original Avatar shader reference differs')
    raw_material = resource(output, 'normal-avatar.material.raw', obj.get_raw_data())
    save_json(output / 'normal-avatar.material.json', material)
    shader = exact_object(environments['shader'], SHADER_ID, 'Shader', SHADER_SHA)
    shader_record, match = selected_program(shader, material['m_ValidKeywords'], output)
    require((match['subshader'], match['passIndex'], match['blobIndex'], match['glslSHA256']) ==
            (0, 0, 3, PROGRAM_SHA), 'Original normal Avatar variant differs')
    source = Path(match['glslFile']).read_bytes()
    code, uniforms, texture_names = source_metal(source)
    program = resource(output, 'SF3D15AvatarNormal.metal', code)
    parsed = json.loads(Path(shader_record['parsedFile']).read_text())
    props = {p['m_Name']: p for p in parsed['m_PropInfo']['m_Props']}
    state = parsed['m_SubShaders'][0]['m_Passes'][0]['m_State']
    floats, tex_envs = (dict(material['m_SavedProperties'][k]) for k in ('m_Floats', 'm_TexEnvs'))
    require((floats['_Blend1'], floats['_Blend2'], floats['_Cull']) == (5, 10, 0) and
            state['zWrite']['val'] == 0 and state['zTest']['val'] == 4 and not state['lighting'] and
            state['rtBlend0']['srcBlend']['name'] == '_Blend1' and
            state['rtBlend0']['destBlend']['name'] == '_Blend2', 'Original normal Avatar raster differs')
    textures = {}
    for name, expected in TEXTURES.items():
        require(tex_envs[name]['m_Texture'] == dict(m_FileID=2, m_PathID=expected['id']),
                'Original Avatar texture reference differs')
        tex = exact_object(environments['textures'], expected['id'], 'Texture2D', expected['objectSHA'])
        textures[name] = export_texture(tex, expected, output)
    require(tex_envs['_MainTex2']['m_Texture'] == dict(m_FileID=0, m_PathID=0) and
            props['_MainTex2']['m_DefTexture']['m_DefaultName'] == 'white', 'Original null-texture default differs')
    textures['_MainTex2'] = dict(sourceKind='shader-declared-white-default', sourcePathID=None,
        width=1, height=1, mipCount=1, rgba=resource(output, 'shader-default-white.rgba', bytes([255])*4))
    manifest = dict(schemaVersion=1, kind='erlang-normal-avatar-source-only', runtimeBound=False,
        originalMaterialName=material['m_Name'], originalMaterialPathID=str(MATERIAL_ID),
        sourceBundles=source_records, originalMaterial=raw_material,
        originalShaderPathID=str(SHADER_ID), originalShaderSHA256=SHADER_SHA,
        originalGLSLSHA256=PROGRAM_SHA, keywords=sorted(KEYWORDS), exactVariant=match,
        program=dict(program, vertexFunction='avatar_normal_vertex', fragmentFunction='avatar_normal_fragment',
            vertexBuffer=0, uniformBuffer=2, uniformFloat4Count=96,
            vertexLayout=['float4 position', 'float4 normal', 'float4 tangent', 'float4 color', 'float4 uv1'],
            builtinSlots=dict(objectToWorld=[0,1,2,3], worldToObject=[4,5,6,7], matrixVP=[16,17,18,19],
                              worldCameraPosition=20, timeVector=21),
            materialUniforms=material_values(material, uniforms),
            textureBindings=[dict(name=n, textureIndex=i, samplerIndex=i) for i, n in enumerate(texture_names)]),
        raster=dict(queue=3000, sourceBlend=5, destinationBlend=10, cull=0, zWrite=False, zTest=4, lighting=False),
        textures=textures, genericFadeAdded=False, originalMipCount=sum(t['mips'] for t in TEXTURES.values()),
        validation=dict(exactSourceObjects=True, exactVariant=True, originalStreamsPreserved=True,
                        appleCompilation='not-run', runtimeGPU='not-run'),
        interfaceScope=dict(vertices='already skinned original source-space positions and normals; original color and tangent.w',
            coordinateConversion='none in this exporter; no particle reflection, unit scale, facing or tint',
            projection='caller provides projection appropriate to its target GPU clip convention; no guessed depth conversion',
            textureRows='source decoded rows, no vertical flip; all original mips retained',
            textureColorSpace='original numeric property retained; runtime texture-format/project-color-space binding not installed',
            timing='not installed; actual accepted original a167 source events and property scheduler are required',
            selection='normal material only; no retext branch or personal-head selector adaptation'),
        compilePreparation=dict(status='prepared-not-executed',
            commands=[['xcrun','--sdk','iphoneos','metal','-c',program['file'],'-o','AvatarNormal.air'],
                      ['xcrun','--sdk','iphoneos','metallib','AvatarNormal.air','-o','AvatarNormal.metallib']],
            workingDirectory='this private candidate directory',
            absence='Missing Apple compiler is unavailable, never a pass'))
    save_json(output / 'avatar-normal-source-only.json', manifest)
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-bundles', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    manifest = prepare(args.source_bundles, args.output)
    print(json.dumps(dict(output=str(args.output), sourceOnly=True, runtimeBound=False,
        material=manifest['originalMaterialName'], originalMips=manifest['originalMipCount'],
        program=manifest['program']['sha256'], appleCompilation='not-run')))


if __name__ == '__main__':
    main()
