#!/usr/bin/env python3
"""Prepare the original materials for D15 sword meshes, particles and trails.

The external materials are byte-pinned, already cached raw objects. Their
metadata is decoded again from those bytes, never trusted alone.
No archive discovery, network access or credential access occurs here.
"""
from __future__ import annotations
import json
import zipfile

from sun_triad_assets import private_output, require, write_private
from erlang_effect_materials import D15, SHARED, SHADER_SHA, selected_program, sha, save_json
from erlang_source_metal import translate

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


def prepare_materials(models, archive, shader_bundle, cached_inputs, output):
    import UnityPy
    from UnityPy.helpers import TypeTreeHelper
    from UnityPy.streams import EndianBinaryReader
    require(UnityPy.__version__ == '1.25.4', 'Use reviewed UnityPy 1.25.4')
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
    cached_receipt = (cached_inputs / 'receipt-private.json').read_bytes()
    require(sha(cached_receipt) == INPUT_RECEIPT_SHA, 'Reviewed cached material receipt differs')
    external_records = {int(r['pathID']): r for r in json.loads(cached_receipt)['records'] if r['type'] == 'Material'}
    template = next(o for o in environments[D15[0]].objects if o.type.name == 'Material')
    shaders, materials, additional = {}, [], []
    for path_id, (identity, digest) in MATERIALS.items():
        if identity == EXTERNAL:
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
            raw, material, cab = obj.get_raw_data(), obj.read_typetree(), obj.assets_file.name
            evidence = dict(sourceBundle=identity[0], sourceBundleBytes=identity[1],
                sourceBundleSHA256=identity[2], wholeBundleSHA256Verified=True)
        require(sha(raw) == digest, 'Original sword material digest differs')
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
    save_json(output / 'd15-sword-shader-bindings-private.json', document)
    save_json(output / 'd15-sword-metal-programs-private.json', translate(document, output))
    save_json(output / 'd15-sword-additional-materials-private.json', dict(records=additional))
