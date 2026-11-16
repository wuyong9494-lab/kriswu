#!/usr/bin/env python3
"""Prepare the original materials for D15 sword meshes, particles and trails.

The external materials are byte-pinned, already cached raw objects. Their
metadata is decoded again from those bytes, never trusted alone.
No archive discovery, network access or credential access occurs here.
"""
from __future__ import annotations
import io
import json
import zipfile
from pathlib import Path

from sun_triad_assets import private_output, require, write_private
from erlang_effect_materials import D15, SHARED, SHADER_SHA, selected_program, sha, save_json
from erlang_source_metal import translate
from prepare_erlang_model_tracks import checked
from prepare_erlang_stomp_effect import PROJECT_INPUTS, texture_metadata_json

EXTERNAL = ('ff1080526339a7afed2acb60ee537859.bin', 1229196,
            '8db3cfd00de2a95055ed1c3483973652ec9aadaec273b743e21c902824d20ab6')
INPUT_RECEIPT_SHA = 'bd47334bb09f31a3d6fa9e944a03bb0a27859f0a4e92b4a546a50efa9ddfcd21'
MATERIALS = {
    -5141676562378979186: (D15, '740ad4d4abdf8ad6a2dea8142b4245b0afaf4b6448e504955112ef83c01ddcc2'),
    -2244836283075552378: (SHARED, 'e0c6b638dcec325e5c727854cf98eabec85b26e427e9c2cc4cc258f79a95223f'),
    2417979635781612236: (EXTERNAL, 'b34327caa6cf05fe905a8717ec0b4f1cd386e269bca777c1880a43f06923634f'),
    2227829583948946176: (D15, 'ba1105ac7a63c9eea512a7ab98a7d087146a135723f0a43b803d8d77d8c4fe37'),
    -1038151529775489848: (D15, 'b924c3b88fa388bf9468fdb245245fc380ced26b6a65a06be693a67db185a771'),
    -8308199006331653405: (D15, 'eee40a3b4594185011caf510681aaa4c0c7ec7e01653627bc7318bba604007db'),
    3656870033957952988: (D15, 'a539a8c4a357f7b80724c66da2f30252dacdad7673ddd694a45af4b633b050a3'),
    932919580993579723: (EXTERNAL, '34bbe3b1771650876ef1aa49d932d10094f24176ae16745f4e6219bda2429e01'),
    -4090667728569622105: (SHARED, 'fe25db9bf25544256cc08a81f2f3d613787d0b587a032de806210b606b882d4d'),
    -3196968270162323177: (SHARED, 'ffd371604953f2b9d6b147c634b9bb7c2909f03f67889cb61fc97b2a3fc8e932'),
}
INACTIVE_KEYWORDS = {3656870033957952988: ['_DISTORTION_VARIANT_SCROLL'],
                     932919580993579723: ['_EMISSION', '_INVERT_ON']}


# Exact original objects observed in the three complete, SHA-pinned local bundles.
RECOVERED_TEXTURE_BUNDLES = {'main': ('9d3e616ea68b083cc7b1b8b92e5f72a8.bin',
          68114260,
          'feffa7c512ceb35663bf7fdd80910ff0927c0f8b31deabdd8413777383392f2e'),
 'gradient': ('e0827787798b68df283fc2391b8d7f11.bin',
              21041786,
              '66b4fd415880e467fb328d4ba8c353c12387a89f5d2e3f7d5b06f1860454540a'),
 'local': ('4f9476ea1326d7c102950a772ee44020.bin',
           2561715,
           '971b3a1ea36eaaebaea4ae73a56ed65d8ffc4383625a06d64a209d8a70fbbd90')}
RECOVERED_TEXTURES = {-3393026562314240441: {'bundle': 'main',
                        'cab': 'CAB-901eba28f4c9f491c9323f34153174a5',
                        'name': 'VFX_TileNoise_32',
                        'rawBytes': 216,
                        'rawSHA256': '633c9ef61d4c5bc95a34418720df6280aa25eda74701a8614454b88b59c388b6',
                        'width': 512,
                        'height': 512,
                        'format': 45,
                        'mips': 10,
                        'streamBytes': 174776,
                        'streamSHA256': 'be81d88fec5259e626146de059b9498ac7995783133287ac62c9e13ad5bd9687'},
 -8264271863913065384: {'bundle': 'main',
                        'cab': 'CAB-901eba28f4c9f491c9323f34153174a5',
                        'name': 'mask_quad_012_vert_clamp',
                        'rawBytes': 224,
                        'rawSHA256': '6db8967c67c918b0e6a5dd1cb83e7459405be50d0a518cecdb3b703ded2bf55d',
                        'width': 256,
                        'height': 256,
                        'format': 47,
                        'mips': 1,
                        'streamBytes': 65536,
                        'streamSHA256': 'be316190ca3799a25cb1a7d8d0e416522b6c5e9f9bbbf73ef2b677ca182be682'},
 -1338012494291763759: {'bundle': 'main',
                        'cab': 'CAB-901eba28f4c9f491c9323f34153174a5',
                        'name': 'dojo_legion_glow2_txr 1',
                        'rawBytes': 224,
                        'rawSHA256': '9b5686562ee5a9f6d0bdad4eea9c6d111c388d2597c51585820f06614dc755eb',
                        'width': 256,
                        'height': 256,
                        'format': 47,
                        'mips': 9,
                        'streamBytes': 87408,
                        'streamSHA256': '9b93c7b3e26b8d67e44895ff2de4447fef4f7805540e77ccb46f607d943f9b91'},
 13838286893223568: {'bundle': 'main',
                     'cab': 'CAB-901eba28f4c9f491c9323f34153174a5',
                     'name': 'caustic_noise_008',
                     'rawBytes': 220,
                     'rawSHA256': '21d98a5272b83f546a156a4be065fee1da216e1b04d56ac74a387664d0cd3fd9',
                     'width': 512,
                     'height': 512,
                     'format': 47,
                     'mips': 10,
                     'streamBytes': 349552,
                     'streamSHA256': 'a50cfdd7b85725a5262f64912270100a82ddb45606996960499d486b59a974bf'},
 -4782877046576669620: {'bundle': 'main',
                        'cab': 'CAB-901eba28f4c9f491c9323f34153174a5',
                        'name': 'mask_glow_001_low',
                        'rawBytes': 220,
                        'rawSHA256': 'ce80f5ef4d550a34b58c1e924ce72dc3064d48c1f85a4e51f076844a34770be6',
                        'width': 128,
                        'height': 32,
                        'format': 47,
                        'mips': 8,
                        'streamBytes': 5520,
                        'streamSHA256': '71e9e4cfb9ba19ab6bf55a9d0a5d0a729180e622661b34260f5907d6c31fb43e'},
 -6541556163830002439: {'bundle': 'main',
                        'cab': 'CAB-901eba28f4c9f491c9323f34153174a5',
                        'name': 'Caustic_03',
                        'rawBytes': 212,
                        'rawSHA256': 'decabeec6eb915fc7e27a56518a50ed8ed526aaf41c43929d55695e79dada34e',
                        'width': 512,
                        'height': 512,
                        'format': 47,
                        'mips': 10,
                        'streamBytes': 349552,
                        'streamSHA256': 'cfb887dc7875af7e85ef951fdd2e282b0898362e34db50b72a9e528d71e9fb70'},
 -5666020059328954682: {'bundle': 'main',
                        'cab': 'CAB-901eba28f4c9f491c9323f34153174a5',
                        'name': 'Glow_ray_03BW_horiz',
                        'rawBytes': 220,
                        'rawSHA256': 'ae33c6af4f83a3365dc7d073849a14b7ff94d318a161eb26a3bd40c22bd5697d',
                        'width': 256,
                        'height': 256,
                        'format': 45,
                        'mips': 9,
                        'streamBytes': 43704,
                        'streamSHA256': 'de11ec7d1a1a2c340448915bc27e733e0a69918e0a516ce834f019f0c0847296'},
 3244179952034596082: {'bundle': 'main',
                       'cab': 'CAB-901eba28f4c9f491c9323f34153174a5',
                       'name': 'CausticNoise',
                       'rawBytes': 212,
                       'rawSHA256': 'caf4b1e5c444c64ad01ba72bf87504454633b2430167920c8668e90f797548ee',
                       'width': 256,
                       'height': 256,
                       'format': 47,
                       'mips': 1,
                       'streamBytes': 65536,
                       'streamSHA256': 'bfbe98759de8f60d8f2caf318a0cc7a833ae7709bb146ca0b9d33548be501645'},
 -3772012025572410240: {'bundle': 'main',
                        'cab': 'CAB-901eba28f4c9f491c9323f34153174a5',
                        'name': 'VFX_noise_mrbl_001',
                        'rawBytes': 220,
                        'rawSHA256': '745fe4daa0a249d33d9cb94bce41401e47ac0d0028509145f832842f789cbddd',
                        'width': 512,
                        'height': 512,
                        'format': 45,
                        'mips': 10,
                        'streamBytes': 174776,
                        'streamSHA256': 'e4266da7ad89b0379a9e6d0664b86447a593be6539b00378e8bd7d10c0246a3a'},
 -3466120665697353164: {'bundle': 'main',
                        'cab': 'CAB-901eba28f4c9f491c9323f34153174a5',
                        'name': 'FireMask',
                        'rawBytes': 208,
                        'rawSHA256': 'f077191a0ccf12b704720c9a59aa1fe5858b858f09f075b9661be60aaf0595b4',
                        'width': 256,
                        'height': 256,
                        'format': 47,
                        'mips': 9,
                        'streamBytes': 87408,
                        'streamSHA256': '94165ff999f0037e575903e442be56b071a1e03fdf0c24ea3730e9c8e0e75526'},
 5890043092355976909: {'bundle': 'main',
                       'cab': 'CAB-901eba28f4c9f491c9323f34153174a5',
                       'name': 'noise_clouds_002',
                       'rawBytes': 216,
                       'rawSHA256': '8eecf040ff4721c28a31dc8b5e02829d427a1267d5ae2718856bc62507ad12de',
                       'width': 1024,
                       'height': 1024,
                       'format': 45,
                       'mips': 11,
                       'streamBytes': 699064,
                       'streamSHA256': '22a4af0dfe54457d1c26b96371e8b9198d3b976475072a1ae8e5bf5ae860151f'},
 9094581542779523862: {'bundle': 'main',
                       'cab': 'CAB-901eba28f4c9f491c9323f34153174a5',
                       'name': 'mask_quad_005_clamp',
                       'rawBytes': 220,
                       'rawSHA256': '0e86af9af8a0179841790b0d99c54b3254f9053817268b8418f3a272bb29c1ec',
                       'width': 256,
                       'height': 256,
                       'format': 45,
                       'mips': 1,
                       'streamBytes': 32768,
                       'streamSHA256': '5286cfbee1aaff029a5bee97c97d3a3cd34174fadcb3033525a0a0d7b74bb257'},
 6132750871359019208: {'bundle': 'gradient',
                       'cab': 'CAB-776814e1aecd39348ee7d1bd103cdaca',
                       'name': 'gradient_03',
                       'rawBytes': 212,
                       'rawSHA256': '2d992334028b97ff35e678ad7e3bcb819082f3ea88a3df0570482251d7a1b107',
                       'width': 128,
                       'height': 128,
                       'format': 45,
                       'mips': 8,
                       'streamBytes': 10936,
                       'streamSHA256': 'f71297626d2d22d1e0449a8699876d4238986b24e16ddcf13033b6253e56c4de'},
 1972434276286117894: {'bundle': 'local',
                       'cab': 'CAB-1f4b3e1848da14b8ff83ae70be7a8bc6',
                       'name': 'mask_grad_009',
                       'rawBytes': 216,
                       'rawSHA256': '9072cc4a6d22ca1aa23d6c5f7ddf1bc8cd17e6877872f1a20f6c82404dea0499',
                       'width': 1024,
                       'height': 256,
                       'format': 47,
                       'mips': 11,
                       'streamBytes': 349584,
                       'streamSHA256': 'f329b429cbe7ecc0ddaa3fc215a3746f13b155c001976ff72355d4f8e7bb60e4'}}


def verify_recovered_material_pointers(material, source_cab):
    def target(pointer):
        fid, pid = pointer['m_FileID'], pointer['m_PathID']
        require(type(fid) is int and type(pid) is int and 0 <= fid <= len(source_cab.externals),
                'Original sword material PPtr type or index differs')
        cab = source_cab.name if fid == 0 else source_cab.externals[fid - 1].path.rsplit('/', 1)[-1]
        return cab, pid
    cab, _ = target(material['m_Shader'])
    require(cab == 'CAB-c8d89ff307ad393b5cf0982a245a196c', 'Original sword shader CAB differs')
    for _, value in material['m_SavedProperties']['m_TexEnvs']:
        cab, pid = target(value['m_Texture'])
        if pid:
            require(pid in RECOVERED_TEXTURES and cab == RECOVERED_TEXTURES[pid]['cab'],
                    'Original sword texture PPtr CAB or identity differs')


def verified_texture_mips(raw, metadata, stream, cab, pin):
    require(cab == pin['cab'] and metadata['m_Name'] == pin['name']
            and len(raw) == pin['rawBytes'] and sha(raw) == pin['rawSHA256'],
            'Original sword Texture2D identity differs')
    require(all(type(metadata[k]) is int and metadata[k] == pin[field] for k, field in (
        ('m_Width', 'width'), ('m_Height', 'height'), ('m_TextureFormat', 'format'), ('m_MipCount', 'mips'))),
        'Original sword texture dimensions, format or mip type differs')
    require(pin['format'] in (45, 47) and len(stream) == pin['streamBytes']
            and sha(stream) == pin['streamSHA256'], 'Original sword complete texture stream differs')
    offset, levels = 0, []
    for level in range(pin['mips']):
        width, height = max(1, pin['width'] >> level), max(1, pin['height'] >> level)
        size = ((width + 3) // 4) * ((height + 3) // 4) * (8 if pin['format'] == 45 else 16)
        payload = stream[offset:offset + size]
        require(len(payload) == size, 'Original sword mip chain is truncated')
        levels.append(dict(level=level, width=width, height=height, offset=offset, bytes=size, sha256=sha(payload)))
        offset += size
    require(offset == len(stream), 'Original sword mip chain has unaccounted bytes')
    return levels


def prepare_recovered_source_cache(models, effects, output):
    """Restore only the complete fourteen-texture dependency set, without network."""
    import UnityPy
    require(UnityPy.__version__ == '1.25.4', 'Use reviewed UnityPy 1.25.4')
    UnityPy.config.FALLBACK_UNITY_VERSION = '6000.3.11f1'
    cache = private_output(output / 'source-inputs-private')
    require(not any(cache.iterdir()), 'Recovered sword input cache must be new')
    records = []
    for key, identity in RECOVERED_TEXTURE_BUNDLES.items():
        raw = checked(models / identity[0], identity[2], identity[1])
        require(len(raw) == identity[1], 'Original sword texture bundle length differs')
        environment = UnityPy.load(raw)
        for pid, pin in RECOVERED_TEXTURES.items():
            if pin['bundle'] != key:
                continue
            found = [o for o in environment.objects if o.type.name == 'Texture2D'
                     and o.path_id == pid and o.assets_file.name == pin['cab']]
            require(len(found) == 1, 'Original sword Texture2D is missing or ambiguous')
            obj = found[0]
            object_raw, metadata, texture = obj.get_raw_data(), obj.read_typetree(), obj.read()
            stream = bytes(texture.get_image_data())
            levels = verified_texture_mips(object_raw, metadata, stream, obj.assets_file.name, pin)
            image = texture.image.convert('RGBA')
            require(image.size == (pin['width'], pin['height']), 'Decoded original sword texture size differs')
            buffer = io.BytesIO(); image.save(buffer, format='PNG'); png = buffer.getvalue()
            paths = {kind: cache / (str(pid) + suffix) for kind, suffix in (
                ('rawFile', '.raw'), ('metadataFile', '.json'), ('textureFile', '.texture'), ('pngFile', '.png'))}
            write_private(paths['rawFile'], object_raw); save_json(paths['metadataFile'], texture_metadata_json(metadata))
            write_private(paths['textureFile'], stream); write_private(paths['pngFile'], png)
            records.append(dict(type='Texture2D', externalCAB=pin['cab'], pathID=str(pid), sourceName=pin['name'],
                sourceObjectBytes=len(object_raw), sourceObjectSHA256=sha(object_raw),
                sourceTextureBytes=len(stream), sourceTextureSHA256=sha(stream),
                pngSHA256=sha(png), metadataSHA256=sha(paths['metadataFile'].read_bytes()),
                **{k: str(v) for k, v in paths.items()},
                bundleEvidence=dict(file=identity[0], bytes=identity[1], sha256=identity[2], wholeBundleSHA256Verified=True),
                fullMipChain=levels))
    require(len(records) == 14 and {int(r['pathID']) for r in records} == set(RECOVERED_TEXTURES),
            'Incomplete recovered sword texture dependency set')
    external = private_output(cache / 'external-objects')
    save_json(external / 'recovered-material-textures-private.json',
              dict(records=[r for r in records if RECOVERED_TEXTURES[int(r['pathID'])]['bundle'] != 'local']))
    save_json(external / 'recovered-dependencies-private.json', dict(records=[]))
    save_json(external / 'mesh-arrays-private.json', dict(records=[]))
    settings = private_output(cache / 'shader-source')
    project = []
    for name, (size, digest) in PROJECT_INPUTS.items():
        raw = checked(effects / 'shader-source' / name, digest, size)
        require(len(raw) == size, 'Recovered original project record length differs')
        write_private(settings / name, raw)
        project.append(dict(file=name, bytes=size, sha256=digest))
    receipt = dict(schema='original-d15-sword-source-cache-recovered-v1', sourceOnly=True,
        historicalTextureReceiptsRestored=False, networkRequests=0, textures=records, projectInputs=project)
    save_json(cache / 'receipt-private.json', receipt)
    return cache, receipt


def prepare_materials(models, archive, shader_bundle, cached_inputs, output, *, input_format='historical'):
    import UnityPy
    from UnityPy.helpers import TypeTreeHelper
    from UnityPy.streams import EndianBinaryReader
    require(UnityPy.__version__ == '1.25.4', 'Use reviewed UnityPy 1.25.4')
    require(input_format in ('historical', 'recovered-v1'), 'Unknown sword material input format')
    recovered = input_format == 'recovered-v1'
    require((cached_inputs is None) == recovered, 'Historical and recovered material inputs cannot be mixed')
    UnityPy.config.FALLBACK_UNITY_VERSION = '6000.3.11f1'
    output = private_output(output)
    require(not any(output.iterdir()), 'New sword material output must be empty')
    raw = (models / D15[0]).read_bytes()
    require(len(raw) == D15[1] and sha(raw) == D15[2], 'Original D15 bundle differs')
    environments = {D15[0]: UnityPy.load(raw)}
    with zipfile.ZipFile(archive) as container:
        info = container.getinfo('bundles/' + SHARED[0])
        require(info.file_size == SHARED[1], 'Original shared member size differs')
        raw = container.read(info)
    require(sha(raw) == SHARED[2], 'Original shared material bundle differs')
    environments[SHARED[0]] = UnityPy.load(raw)
    shader_raw = shader_bundle.read_bytes()
    require(sha(shader_raw) == SHADER_SHA, 'Original shared shader bundle differs')
    shader_objects = {o.path_id: o for o in UnityPy.load(shader_raw).objects if o.type.name == 'Shader'}
    if not recovered:
        cached_receipt = (cached_inputs / 'receipt-private.json').read_bytes()
        require(sha(cached_receipt) == INPUT_RECEIPT_SHA, 'Reviewed cached material receipt differs')
        external_records = {int(r['pathID']): r for r in json.loads(cached_receipt)['records'] if r['type'] == 'Material'}
    else:
        raw = checked(models / EXTERNAL[0], EXTERNAL[2], EXTERNAL[1])
        require(len(raw) == EXTERNAL[1], 'Original external sword material bundle length differs')
        environments[EXTERNAL[0]] = UnityPy.load(raw)
    template = next(o for o in environments[D15[0]].objects if o.type.name == 'Material')
    shaders, materials, additional = {}, [], []
    for path_id, (identity, digest) in MATERIALS.items():
        if identity == EXTERNAL and not recovered:
            external_record = external_records[path_id]
            raw = (cached_inputs / (str(path_id) + '.raw')).read_bytes()
            require(len(raw) == external_record['sourceObjectBytes'] and sha(raw) == digest ==
                    external_record['sourceObjectSHA256'], 'Original cached sword material differs')
            material = TypeTreeHelper.read_typetree(template.serialized_type.node,
                EndianBinaryReader(raw, endian=template.reader.endian), byte_size=len(raw), as_dict=True)
            cab = external_record['externalCAB']
            require(cab == 'CAB-f84b4be63f25036ecac28811c8604c97', 'Wrong cached sword material CAB')
            evidence = external_record['bundleEvidence']
        else:
            objects = [o for o in environments[identity[0]].objects if o.type.name == 'Material' and o.path_id == path_id]
            require(len(objects) == 1, 'Original sword material is ambiguous')
            obj = objects[0]
            raw, cab = obj.get_raw_data(), obj.assets_file.name
            if identity == EXTERNAL:
                require(cab == 'CAB-f84b4be63f25036ecac28811c8604c97', 'Wrong recovered sword material CAB')
                material = TypeTreeHelper.read_typetree(template.serialized_type.node,
                    EndianBinaryReader(raw, endian=template.reader.endian), byte_size=len(raw), as_dict=True)
            else:
                material = obj.read_typetree()
            evidence = dict(sourceBundle=identity[0], sourceBundleBytes=identity[1],
                sourceBundleSHA256=identity[2], wholeBundleSHA256Verified=True)
        require(sha(raw) == digest, 'Original sword material digest differs')
        if recovered:
            verify_recovered_material_pointers(material, obj.assets_file)
        metadata, raw_path = output / (str(path_id) + '.json'), output / (str(path_id) + '.raw')
        save_json(metadata, material); write_private(raw_path, raw)
        sid = int(material['m_Shader']['m_PathID'])
        inactive = INACTIVE_KEYWORDS.get(path_id, [])
        require(sid in shader_objects and material['m_InvalidKeywords'] == inactive,
                'Unresolved original sword shader')
        # These exact materials retain obsolete keywords in Unity's
        # invalid list. The source shader does not declare it; keep that fact
        # in the receipt while selecting the compiled active-keyword variant.
        declared = shader_objects[sid].read_typetree()['m_ParsedForm']['m_KeywordNames']
        require(not set(inactive).intersection(declared), 'Inactive source keyword belongs to this shader')
        shader, match = selected_program(shader_objects[sid], material['m_ValidKeywords'], output)
        shaders[str(sid)] = shader
        materials.append(dict(sourceBundle=identity[0], sourceCAB=cab, sourcePathID=str(path_id),
            sourceName=material['m_Name'], sourceObjectSHA256=digest, metadataFile=str(metadata),
            shaderPathID=str(sid), shaderName=shader['name'], validKeywords=material['m_ValidKeywords'],
            invalidKeywords=inactive, exactMatches=[match], matchedExactly=True))
        if identity != D15:
            additional.append(dict(type='Material', externalCAB=cab, pathID=str(path_id),
                sourceName=material['m_Name'], sourceObjectBytes=len(raw), sourceObjectSHA256=digest,
                rawFile=str(raw_path), metadataFile=str(metadata), bundleEvidence=evidence))
    document = dict(sourceEffectsBundle=D15[0], sourceEffectsBundleSHA256=D15[2],
        sourceShaderBundle=shader_bundle.name, sourceShaderBundleSHA256=SHADER_SHA,
        cachedInputReceiptSHA256=INPUT_RECEIPT_SHA, shaders=list(shaders.values()), materials=materials)
    if recovered:
        del document['cachedInputReceiptSHA256']
        document['inputRecovery'] = dict(format=input_format,
            sourceExternalBundle=dict(file=EXTERNAL[0], bytes=EXTERNAL[1], sha256=EXTERNAL[2]),
            historicalCachedReceiptSHA256=INPUT_RECEIPT_SHA, historicalCachedReceiptBytesRestored=False,
            sourceOnly=True)
    save_json(output / 'd15-sword-shader-bindings-private.json', document)
    save_json(output / 'd15-sword-metal-programs-private.json', translate(document, output))
    save_json(output / 'd15-sword-additional-materials-private.json', dict(records=additional))
