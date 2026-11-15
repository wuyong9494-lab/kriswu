#!/usr/bin/env python3
"""Export six exact D15 materials and their original mips, without runtime binding.

Only fixed local bundles are read. The existing exact-keyword selector and
GLSL-to-MSL expression adapter are reused unchanged. Particle geometry, Noise,
birth history, runtime allowlists, GPU execution and release manifests are out
of scope. Private source programs, streams and decoded pixels stay outside Git.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import struct

from erlang_effect_materials import selected_program
from erlang_source_metal import BUILTIN, section, translate
from prepare_erlang_avatar_material import material_values
from sun_triad_assets import private_output, require, write_private

# Exact original object and selected-program identities, established by a
# local read of the matching complete source bundles on 2026-11-15.
BUNDLES = {'shared': ('743fc535f600cb6addb0c2d20c96a9ab.bin',
            986541,
            '863f1953d88d33beb0ec85229da17188376bb36e47d791146fc87a0f565706ec'),
 'external': ('ff1080526339a7afed2acb60ee537859.bin',
              1229196,
              '8db3cfd00de2a95055ed1c3483973652ec9aadaec273b743e21c902824d20ab6'),
 'shaders': ('b77cd85962dab26b5e542811e8599be3.bin',
             1785198,
             'c0b1fe09ba0684e474297ade8dcd7fee7b5d2e780236029c544c1986dea1e972'),
 'texturese0': ('e0827787798b68df283fc2391b8d7f11.bin',
                21041786,
                '66b4fd415880e467fb328d4ba8c353c12387a89f5d2e3f7d5b06f1860454540a'),
 'textures9d': ('9d3e616ea68b083cc7b1b8b92e5f72a8.bin',
                68114260,
                'feffa7c512ceb35663bf7fdd80910ff0927c0f8b31deabdd8413777383392f2e'),
 'project': ('globalgamemanagers',
             673748,
             '1ddbe17aab3a2997a1913e122eb9099da5ed17b94aff84fecd288914fecb2e0f')}

SHADERS = {4659798091178469451: '6cfb944a4278fb545246c2891f11dbf960de6c2601552d6e6b757a6a66dcf534',
 7099477430120726890: 'd58474f3edf409594f95808206392f4a1c01de058276fbbfadb43c9c30e52c30',
 4655989024510641494: '900248ef261d2fbda7879c9f4ed95d1595b9fb7004c303b8a4f148661aa2bf65'}

MATERIALS = {-2157749360310989314: {'bundle': 'shared',
                        'name': 'mtl_gradient_aBlnd',
                        'sha256': '644035983161bba5797e307aaf06384966257320a336a01368a26633f1525684',
                        'shaderID': 4659798091178469451,
                        'keywords': ['_USE_CAMERA_OFFSET_OFF',
                                     '_USE_CLAMP_OFF',
                                     '_USE_OFF',
                                     '_USE_SMOOTHSTEP_OFF'],
                        'variant': [0,
                                    0,
                                    31,
                                    2652,
                                    '64449a6385a7a19d851328309fc3cf15d362262b653599267ded206d937b82a6'],
                        'textures': {'_MainTex': '3786051072325781169'}},
 -1155837180958487824: {'bundle': 'shared',
                        'name': 'mtl_muzzle_noise',
                        'sha256': '01a25deaf5aa4cdcdf7f548a284f96449a2b559cc2e0733f63902f3d8719f940',
                        'shaderID': 7099477430120726890,
                        'keywords': ['_USE_BLENDADD',
                                     '_USE_CAMERA_OFFSET_OFF',
                                     '_USE_CLAMP_OFF',
                                     '_USE_LERP1',
                                     '_USE_SMOOTHSTEP_OFF'],
                        'variant': [0,
                                    0,
                                    54,
                                    3883,
                                    '2b86032a96348d73288e7e4a698d9b549362c26512d3e2e92378e7cac74a03c3'],
                        'textures': {'_MainTex': '2639016644056759067', '_Mask': '965847529922942018'}},
 8530189115646704333: {'bundle': 'shared',
                       'name': 'mtl_energy_flame 3',
                       'sha256': 'e67111de67b24dcc9fb111557105a1e50abe05f792fa7f18347044bfda90c88c',
                       'shaderID': 7099477430120726890,
                       'keywords': ['_USE_BLENDADD',
                                    '_USE_CAMERA_OFFSET_ON',
                                    '_USE_CLAMP_OFF',
                                    '_USE_LERP1',
                                    '_USE_SMOOTHSTEP_OFF'],
                       'variant': [0,
                                   0,
                                   53,
                                   4523,
                                   '1e0169db393b158e2a4b823d92f5d785864a5635b127ae4a1c25d7d5cc07eeda'],
                       'textures': {'_MainTex': '8106364428363554812', '_Mask': '-5605429874853356512'}},
 -4712904873042191220: {'bundle': 'external',
                        'name': 'Sparks_1',
                        'sha256': '78437ca75c4794fe24cc856f2af5414e309d04345037e0a273510eb7b95142b5',
                        'shaderID': 4659798091178469451,
                        'keywords': ['_USE_CAMERA_OFFSET_OFF',
                                     '_USE_CLAMP_OFF',
                                     '_USE_LERP1',
                                     '_USE_SMOOTHSTEP_OFF'],
                        'variant': [0,
                                    0,
                                    35,
                                    2922,
                                    '57146962e3276ac8219d6caef9b415bb4997fb772bdbcf78be67a98aff8d7412'],
                        'textures': {'_MainTex': '8622200343931352576'}},
 -3833188765227295071: {'bundle': 'external',
                        'name': 'mtl_energy_noise_gradient_1',
                        'sha256': 'f4001f260320b25bed75f36bbc9b24a529db3cf86446320237f3f560e676895b',
                        'shaderID': 4655989024510641494,
                        'keywords': ['_USE_CAMERA_OFFSET_ON',
                                     '_USE_CLAMP_OFF',
                                     '_USE_LERP1',
                                     '_USE_SMOOTHSTEP_OFF'],
                        'variant': [0,
                                    0,
                                    41,
                                    4820,
                                    '3763bdddfa00bd1327b271c7140648e48ffcadc24796635119462e2627a17eec'],
                        'textures': {'_MainTex': '5890043092355976909',
                                     '_MainTex2': '7062348484569995484',
                                     '_Mask': '3636411242617834560'}},
 -3539672900455825089: {'bundle': 'external',
                        'name': 'mtl_sparks_v4',
                        'sha256': 'c86e204a82399c85e6abc8684504b59a6d59a763a27ee6259b8db8cf6ba20c78',
                        'shaderID': 4659798091178469451,
                        'keywords': ['_USE_BLENDADD',
                                     '_USE_CAMERA_OFFSET_OFF',
                                     '_USE_CLAMP_OFF',
                                     '_USE_LERP1',
                                     '_USE_SMOOTHSTEP_OFF'],
                        'variant': [0,
                                    0,
                                    57,
                                    3169,
                                    '69aafee8863f6149965f260e6775216f24f861f196d48e978942d8aafd03d2e8'],
                        'textures': {'_MainTex': '-8666170619262010817'}}}

TEXTURES = {-5605429874853356512: {'bundle': 'texturese0',
                        'name': 'mask_quad_009_clamp',
                        'rawSHA256': '6c95888289be6871b4e6884ea90b71c9d48ea44e9196ea9f5c06a5ea0af49536',
                        'width': 256,
                        'height': 256,
                        'format': 47,
                        'mips': 9,
                        'streamBytes': 87408,
                        'streamSHA256': '82992337920a78020398c060f663ef4aee639af22ffe39ebbbb594411e48b317'},
 965847529922942018: {'bundle': 'texturese0',
                      'name': 'VFX_MuzzleFlash_2',
                      'rawSHA256': '27d3dd3b955365a6cf94416650c6eedc1b6c0dc03cfb49a720ddf50cf502cac7',
                      'width': 256,
                      'height': 128,
                      'format': 47,
                      'mips': 9,
                      'streamBytes': 43728,
                      'streamSHA256': '91b08d4af00a7a32efa04243ce20c6484b71e96f2f2809f3adda2bd83fbf7cae'},
 3786051072325781169: {'bundle': 'texturese0',
                       'name': 'mask_grad_019',
                       'rawSHA256': '20086d6536ca1d7475d54796fdd9aaffb00abe1773358448b71da176c08bc7d1',
                       'width': 256,
                       'height': 64,
                       'format': 47,
                       'mips': 9,
                       'streamBytes': 21904,
                       'streamSHA256': '6c8b15f0eba3452e4243e911b3a367a09ac25f61bba84636c7a1b1dbedf92b5b'},
 -8666170619262010817: {'bundle': 'textures9d',
                        'name': 'Big_Expl_rays_bw_01',
                        'rawSHA256': '067e1f49f787282e50ddca05a03540834a2fac11be1535205bdd2a033454f9f9',
                        'width': 256,
                        'height': 256,
                        'format': 47,
                        'mips': 1,
                        'streamBytes': 65536,
                        'streamSHA256': 'a6522acf62cd12e038a186e4367080b8d029e704bf2c4965b4ad72ce99334c9f'},
 2639016644056759067: {'bundle': 'textures9d',
                       'name': 'mana_noise_001_alpha',
                       'rawSHA256': 'f983d1c334899a54772add08ecebb7bebc8721cb0ff759003853cf09d2712a2b',
                       'width': 512,
                       'height': 512,
                       'format': 47,
                       'mips': 10,
                       'streamBytes': 349552,
                       'streamSHA256': '12e8d1bc626de0e3cc63f7bf49d17740e13aca3d33973cab0ad8497a84581da8'},
 3636411242617834560: {'bundle': 'textures9d',
                       'name': 'gradient_noise_003',
                       'rawSHA256': '10d1802186d4adec628a04f7583659ab6bae9acb23e5bb5178d7e30151ccb037',
                       'width': 1024,
                       'height': 512,
                       'format': 47,
                       'mips': 11,
                       'streamBytes': 699088,
                       'streamSHA256': 'ae1f582c95a72941c1e63b6c6de27c0cad5b47b26ee6502f51f3eba78617fe1d'},
 5890043092355976909: {'bundle': 'textures9d',
                       'name': 'noise_clouds_002',
                       'rawSHA256': '8eecf040ff4721c28a31dc8b5e02829d427a1267d5ae2718856bc62507ad12de',
                       'width': 1024,
                       'height': 1024,
                       'format': 45,
                       'mips': 11,
                       'streamBytes': 699064,
                       'streamSHA256': '22a4af0dfe54457d1c26b96371e8b9198d3b976475072a1ae8e5bf5ae860151f'},
 7062348484569995484: {'bundle': 'textures9d',
                       'name': 'fire_noise_a_03',
                       'rawSHA256': '6f7de39871233b10b650b73efc64dd71207a1e247f928f909b0aab98f797bfd6',
                       'width': 512,
                       'height': 512,
                       'format': 45,
                       'mips': 10,
                       'streamBytes': 174776,
                       'streamSHA256': '181e6896fe700d967192eaba592ed2f0cd5f4f9801c0bf791f7bf44d86565f5c'},
 8106364428363554812: {'bundle': 'textures9d',
                       'name': 'caustic_noise_010',
                       'rawSHA256': '0b9f4eec6338c768ff2a24e378de532b6d86bfd33bd03c63e831f52c2688718d',
                       'width': 512,
                       'height': 512,
                       'format': 47,
                       'mips': 10,
                       'streamBytes': 349552,
                       'streamSHA256': '13643c454b6b45efe739c359796082f3dc8900848b8737542d3db68e1a46e774'},
 8622200343931352576: {'bundle': 'textures9d',
                       'name': 'Big_Expl_rays_bw_02',
                       'rawSHA256': 'de7c6f93ce5411e03257a70aae6356a8ef7b0590482e9395956a4ddfa4dd486c',
                       'width': 256,
                       'height': 256,
                       'format': 47,
                       'mips': 1,
                       'streamBytes': 65536,
                       'streamSHA256': '2b32a4fd4985f62ba7a3546149d24f1de312e9d5f7c21d5288b6ae53c23874ea'}}


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def save_json(path, value):
    write_private(path, (json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + '\n').encode())


def resource(output, name, raw):
    write_private(output / name, raw)
    return dict(file=name, bytes=len(raw), sha256=sha(raw))


def exact_object(environment, path_id, kind, digest):
    matches = [o for o in environment.objects if o.path_id == path_id and o.type.name == kind]
    require(len(matches) == 1, 'Original object is missing or ambiguous')
    obj = matches[0]
    require(sha(obj.get_raw_data()) == digest, 'Original object bytes differ')
    return obj


def require_reference(owner, pointer, target):
    require(pointer['m_PathID'] == target.path_id, 'Original reference pathID differs')
    file_id = pointer['m_FileID']
    require(type(file_id) is int and 0 <= file_id <= len(owner.assets_file.externals),
            'Original reference fileID is out of bounds')
    cab = (owner.assets_file.externals[file_id - 1].path.rsplit('/', 1)[-1]
           if file_id else owner.assets_file.name)
    require(cab == target.assets_file.name, 'Original reference CAB differs')


def validate_material(material, expected):
    require(material['m_Name'] == expected['name'] and
            sorted(material['m_ValidKeywords']) == sorted(expected['keywords']) and
            not material['m_InvalidKeywords'], 'Original material name or keywords differ')
    slots = dict(material['m_SavedProperties']['m_TexEnvs'])
    require(len(slots) == len(material['m_SavedProperties']['m_TexEnvs']) and
            set(slots) == set(expected['textures']), 'Original material texture slots differ')
    for name, texture_id in expected['textures'].items():
        require(slots[name]['m_Texture']['m_PathID'] == int(texture_id),
                'Original material texture identity differs')


def validate_variant(match, expected):
    actual = tuple(match[k] for k in ('subshader', 'passIndex', 'blobIndex', 'glslBytes', 'glslSHA256'))
    require(actual == tuple(expected), 'Original exact keyword program differs')


def mip_ranges(width, height, count, texture_format, total):
    """Preserve all ETC2 RGB / RGBA source blocks, including 2x2 and 1x1 tails."""
    require(all(type(v) is int for v in (width, height, count, texture_format, total)),
            'Original mip dimensions must be integers')
    require(0 < width <= 4096 and 0 < height <= 4096 and
            0 < count <= max(width, height).bit_length() and texture_format in (45, 47),
            'Unsupported original texture format or mip extent')
    block_size = 8 if texture_format == 45 else 16
    offset, levels = 0, []
    for level in range(count):
        w, h = max(1, width >> level), max(1, height >> level)
        size = ((w + 3) // 4) * ((h + 3) // 4) * block_size
        levels.append(dict(level=level, width=w, height=h, offset=offset, bytes=size))
        offset += size
    require(offset == total, 'Original mip chain is truncated or has extra bytes')
    return levels


def export_texture(obj, expected, output):
    from UnityPy.export.Texture2DConverter import parse_image_data
    tree, texture = obj.read_typetree(), obj.read()
    require((tree['m_Name'], tree['m_Width'], tree['m_Height'], tree['m_TextureFormat'], tree['m_MipCount']) ==
            (expected['name'], expected['width'], expected['height'], expected['format'], expected['mips']),
            'Original texture metadata differs')
    data = texture.get_image_data()
    require(len(data) == expected['streamBytes'] and sha(data) == expected['streamSHA256'],
            'Original texture stream differs')
    layout = mip_ranges(expected['width'], expected['height'], expected['mips'], expected['format'], len(data))
    stream = resource(output, 'source-etc2.bin', data)
    raw_object = resource(output, 'source-texture.raw', obj.get_raw_data())
    # The complete object is preserved above. Project only serializable source
    # metadata here; a typetree can contain a binary image-data field.
    keys = ('m_Name', 'm_Width', 'm_Height', 'm_TextureFormat', 'm_MipCount',
            'm_TextureDimension', 'm_ImageCount', 'm_CompleteImageSize',
            'm_TextureSettings', 'm_ColorSpace', 'm_StreamData')
    save_json(output / 'source-texture.json', {key: tree[key] for key in keys if key in tree})
    levels = []
    for level in layout:
        part = data[level['offset']:level['offset'] + level['bytes']]
        image = parse_image_data(part, level['width'], level['height'], expected['format'],
            obj.version, obj.platform, getattr(texture, 'm_PlatformBlob', None), flip=False)
        require(image.mode in ('RGB', 'RGBA') and image.size == (level['width'], level['height']),
                'Original mip decode differs')
        rgba = image.convert('RGBA').tobytes()
        if expected['format'] == 45:
            require(all(a == 255 for a in rgba[3::4]), 'RGB source mip acquired non-opaque alpha')
        levels.append(dict(level, compressedSHA256=sha(part),
            rgba=resource(output, f'mip{level["level"]}.rgba', rgba)))
    return dict(sourcePathID=str(obj.path_id), sourceName=tree['m_Name'], sourceObject=raw_object,
        sourceCAB=obj.assets_file.name, sourceTextureFormat=expected['format'], sourceColorSpace=tree['m_ColorSpace'],
        sourceSampler=tree['m_TextureSettings'], sourceStream=stream, mips=levels,
        decodedRows='flip=False; no resampling, generated mip levels or color-space conversion',
        decodedRGBAAlpha='opaque 255 from source RGB format' if expected['format'] == 45 else 'original ETC2 alpha')


def source_project_context(environment, output):
    player = exact_object(environment, 1, 'PlayerSettings',
        '5fe9e533c9b17a8cafe0aa25387a6a6ff738641b27d5334ff117e276cc293cb9')
    raw = player.get_raw_data()
    require(len(raw) == 956 and struct.unpack_from('<i', raw, 256)[0] == 0,
            'Original verified color-space field differs')
    quality = exact_object(environment, 12, 'QualitySettings',
        '7e1c4004b906f69308e973ecc7d3d09105e4f8933aea2e601931a0edc9e1cf8c')
    tree = quality.read_typetree()
    index = tree['m_CurrentQuality']
    require(index == 0 and tree['m_QualitySettings'][index]['anisotropicTextures'] == 0,
            'Original serialized project default differs')
    return dict(directory='project', player=resource(output, 'PlayerSettings.raw', raw), playerCompleteTypeTreeRead=False,
        verifiedColorSpaceField=dict(name='m_ActiveColorSpace', offset=256, bytes=4, value=0),
        quality=resource(output, 'QualitySettings.raw', quality.get_raw_data()), qualityCompleteTypeTreeRead=True,
        serializedDefaultQuality=index, serializedDefaultAnisotropicFiltering=0,
        qualityLevels=[dict(name=q['name'], anisotropicTextures=q['anisotropicTextures'],
                            globalTextureMipmapLimit=q['globalTextureMipmapLimit']) for q in tree['m_QualitySettings']],
        runtimeQualitySelectionVerified=False)


def translate_material(binding, output, material):
    """A conversion failure stays a source-only unsupported record, never a pass."""
    try:
        result = translate(binding, output)
        require(len(result['materials']) == 1, 'Material conversion count differs')
        patch = result['materials'][0]
        source = Path(binding['materials'][0]['exactMatches'][0]['glslFile']).read_text()
        sections = [section(source, stage) for stage in ('VERTEX', 'FRAGMENT')]
        uniforms = {name: kind for part in sections for kind, name, array in part['uniforms']
                    if name not in BUILTIN and kind != 'sampler2D'}
        uniform_specs = [dict(name=name, type=uniforms[name], float4Slot=32+i)
                         for i, name in enumerate(sorted(uniforms))]
        values = material_values(material, uniform_specs)
        slots = dict(material['m_SavedProperties']['m_TexEnvs'])
        require(set(patch['program']['textures']) == set(slots), 'Program texture interface differs')
        require(patch['projectColorSpace'] == 0 and patch['projectAnisotropicFiltering'] == 0,
                'Existing converter context differs from verified serialized defaults')
        return dict(status='exported-source-only', program=patch['program'],
                    materialUniforms=values, raster=patch['raster'], runtimeBound=False)
    except (ValueError, KeyError, NotImplementedError) as error:
        return dict(status='unsupported', reason=f'{type(error).__name__}: {str(error)[:500]}',
                    runtimeBound=False)


def prepare(source_bundles, shared_bundle, output):
    import UnityPy
    require(UnityPy.__version__ == '1.25.4', 'Use reviewed UnityPy 1.25.4')
    UnityPy.config.FALLBACK_UNITY_VERSION = '6000.3.11f1'
    output = private_output(output)
    require(not any(output.iterdir()), 'Source-only output must be a new empty private directory')
    environments, sources = {}, []
    for key, (name, size, digest) in BUNDLES.items():
        path = shared_bundle if key == 'shared' else source_bundles / name
        raw = path.read_bytes()
        require(len(raw) == size and sha(raw) == digest, 'Original source bundle differs: ' + key)
        environments[key] = UnityPy.load(raw)
        sources.append(dict(file=name, bytes=size, sha256=digest, wholeFileSHA256Verified=True))
    context = source_project_context(environments['project'], private_output(output / 'project'))
    texture_objects, textures = {}, []
    for path_id, expected in TEXTURES.items():
        obj = exact_object(environments[expected['bundle']], path_id, 'Texture2D', expected['rawSHA256'])
        texture_objects[path_id] = obj
        target = private_output(output / 'textures' / str(path_id))
        record = export_texture(obj, expected, target)
        textures.append(dict(record, directory=str(target.relative_to(output)), sourceBundle=BUNDLES[expected['bundle']][0]))
    materials = []
    for path_id, expected in MATERIALS.items():
        obj = exact_object(environments[expected['bundle']], path_id, 'Material', expected['sha256'])
        material = obj.read_typetree()
        validate_material(material, expected)
        shader = exact_object(environments['shaders'], expected['shaderID'], 'Shader', SHADERS[expected['shaderID']])
        require_reference(obj, material['m_Shader'], shader)
        for slot, reference in material['m_SavedProperties']['m_TexEnvs']:
            require_reference(obj, reference['m_Texture'], texture_objects[int(expected['textures'][slot])])
        target = private_output(output / 'materials' / str(path_id))
        raw_material = resource(target, 'source-material.raw', obj.get_raw_data())
        metadata = target / 'source-material.json'
        save_json(metadata, material)
        shader_record, match = selected_program(shader, material['m_ValidKeywords'], target)
        validate_variant(match, expected['variant'])
        binding = dict(shaders=[shader_record], materials=[dict(sourcePathID=str(path_id),
            sourceName=material['m_Name'], sourceObjectSHA256=expected['sha256'], metadataFile=str(metadata),
            shaderPathID=str(expected['shaderID']), exactMatches=[match])])
        save_json(target / 'exact-source-binding.json', binding)
        conversion = translate_material(binding, target, material)
        materials.append(dict(sourcePathID=str(path_id), sourceName=material['m_Name'], sourceMaterial=raw_material,
            sourceBundle=BUNDLES[expected['bundle']][0], sourceCAB=obj.assets_file.name,
            directory=str(target.relative_to(output)), keywords=material['m_ValidKeywords'], invalidKeywords=[],
            sourceShaderPathID=str(expected['shaderID']), sourceShaderSHA256=SHADERS[expected['shaderID']],
            exactVariant=match, textures=expected['textures'], conversion=conversion))
    successful = sum(m['conversion']['status'] == 'exported-source-only' for m in materials)
    resources = [dict(file=str(p.relative_to(output)), bytes=p.stat().st_size, sha256=sha(p.read_bytes()))
                 for p in sorted(output.rglob('*')) if p.is_file()]
    manifest = dict(schemaVersion=1, kind='erlang-unbound-material-source-inputs',
        status='exported-source-only' if successful == len(MATERIALS) else 'partial-unsupported',
        runtimeBound=False, completeParticleEffects=False, sourceBundles=sources, sourceProjectContext=context,
        parser=dict(name='UnityPy', version='1.25.4', fallbackUnityVersion='6000.3.11f1',
                    originalUnityEngineVersionVerified=False),
        materials=materials, textures=textures, exportedMaterialCount=successful,
        unsupportedMaterialCount=len(materials)-successful, originalMipCount=sum(len(t['mips']) for t in textures),
        resources=resources,
        validation=dict(sourceIdentities='verified', exactKeywordPrograms='verified',
            allOriginalMips='retained', appleCompilation='not-run', runtimeGPU='not-run',
            particleSampling='not-run', nativeClient='not-run'),
        remainingGaps=['Signed Stretch vertex geometry', 'Noise algorithm and seed mapping',
            'Noise/Velocity/Clamp integration order', 'World-space particle birth history',
            'Runtime vertex-stream routing and material binding'],
        sourceOnlyBoundary='No runtime allowlist, particle adapter, application identity, workflow or release is changed.')
    save_json(output / 'erlang-unbound-materials-source-only.json', manifest)
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-bundles', type=Path, required=True)
    parser.add_argument('--shared-bundle', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = prepare(args.source_bundles, args.shared_bundle, args.output)
    print(json.dumps({key: result[key] for key in ('status', 'runtimeBound', 'exportedMaterialCount',
                                                'unsupportedMaterialCount', 'originalMipCount')}))
    return 0 if result['unsupportedMaterialCount'] == 0 else 2


if __name__ == '__main__':
    raise SystemExit(main())
