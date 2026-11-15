#!/usr/bin/env python3
"""Prepare the three original materials used by D15's visible sword mesh.

The one additional external material is a byte-pinned, already cached raw
object. Its metadata is decoded again from those bytes, never trusted alone.
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
}


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
    external_record = next(r for r in json.loads(cached_receipt)['records'] if r['pathID'] == '2417979635781612236')
    template = next(o for o in environments[D15[0]].objects if o.type.name == 'Material')
    shaders, materials, additional = {}, [], []
    for path_id, (identity, digest) in MATERIALS.items():
        if identity == EXTERNAL:
            raw = (cached_inputs / (str(path_id) + '.raw')).read_bytes()
            require(len(raw) == 1376 and sha(raw) == digest, 'Original cached sword material differs')
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
        require(sid in shader_objects and not material['m_InvalidKeywords'], 'Unresolved original sword shader')
        shader, match = selected_program(shader_objects[sid], material['m_ValidKeywords'], output)
        shaders[str(sid)] = shader
        materials.append(dict(sourceBundle=identity[0], sourceCAB=cab, sourcePathID=str(path_id),
            sourceName=material['m_Name'], sourceObjectSHA256=digest, metadataFile=str(metadata),
            shaderPathID=str(sid), shaderName=shader['name'], validKeywords=material['m_ValidKeywords'],
            invalidKeywords=[], exactMatches=[match], matchedExactly=True))
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
