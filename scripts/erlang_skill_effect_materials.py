#!/usr/bin/env python3
"""Resolve the exact original materials for a scoped D15 skill effect.

Only already supplied source bundles and authenticated object snapshots are
read. Textures remain independently checked by SourceAssets during sampling.
"""
from __future__ import annotations
import json
import zipfile
from pathlib import Path

from sun_triad_assets import private_output, require, write_private
from erlang_effect_materials import D15, SHARED, SHADER_SHA, selected_program, sha, save_json
from erlang_source_metal import translate

LASER_MATERIALS = {
    -5767049895884654831: ('local', 'bad10386a871f1ddea8ae8266b08fb0cc3a7c1592b3cdfd4b640d10279904777'),
    -5588040408642645108: ('local', '6143269f969f5142020f41abf0ef01181d8669cbadd6921076a6863e5025b776'),
    7698625736226087731: ('local', '5c2455b73e01cb1fb4d1d6e65935174cc68b6ac68171956b69b04d1b5b538aae'),
    8335876950497352917: ('local', '4fdc0a1744ac80d74ce80d15aabf4772a972b11f277195daa6df2925341e4fb8'),
    -1633406565193228711: ('cached', '2910348b914657f92ee4dbe08a1812c6cebd2aa594e74538c599d004926ff8d6'),
    1405335076776623755: ('cached', '1ca4fdf09d983e7220e973e3a43fc2df04aa9fdd681d4280172b210fa56f02d6'),
    -1637196477244744623: ('shared', '9beea70cca3357d26633b4c424ae859e04c40022f3c204c5c9024a4974df0f9c'),
}


def prepare_materials(models, archive, shader_bundle, effects, output, scope=LASER_MATERIALS):
    import UnityPy
    from UnityPy.helpers import TypeTreeHelper
    from UnityPy.streams import EndianBinaryReader
    require(UnityPy.__version__ == '1.25.4', 'Use reviewed UnityPy 1.25.4')
    UnityPy.config.FALLBACK_UNITY_VERSION = '6000.3.11f1'
    output = private_output(output)
    require(not any(output.iterdir()), 'New skill material output must be empty')
    raw = (models / D15[0]).read_bytes()
    require(len(raw) == D15[1] and sha(raw) == D15[2], 'Original D15 bundle differs')
    environments = {'local': UnityPy.load(raw)}
    with zipfile.ZipFile(archive) as container:
        info = container.getinfo('bundles/' + SHARED[0])
        require(info.file_size == SHARED[1], 'Original shared member size differs')
        raw = container.read(info)
    require(sha(raw) == SHARED[2], 'Original shared material bundle differs')
    environments['shared'] = UnityPy.load(raw)
    shader_raw = shader_bundle.read_bytes()
    require(sha(shader_raw) == SHADER_SHA, 'Original shared shader bundle differs')
    shaders_by_id = {o.path_id: o for o in UnityPy.load(shader_raw).objects if o.type.name == 'Shader'}
    cached = json.loads((effects / 'external-objects/recovered-dependencies-private.json').read_bytes())['records']
    template = next(o for o in environments['local'].objects if o.type.name == 'Material')
    shaders, materials, records = {}, [], []
    for pid, (kind, digest) in scope.items():
        if kind == 'cached':
            candidates = [r for r in cached if r['type'] == 'Material' and int(r['pathID']) == pid
                          and r['sourceObjectSHA256'] == digest]
            require(candidates and len({r['externalCAB'] for r in candidates}) == 1, 'Original cached material is ambiguous')
            record = candidates[0]
            raw = Path(record['rawFile']).read_bytes()
            require(sha(raw) == digest, 'Original cached material bytes differ')
            material = TypeTreeHelper.read_typetree(template.serialized_type.node,
                EndianBinaryReader(raw, endian=template.reader.endian), byte_size=len(raw), as_dict=True)
            cab, evidence = record['externalCAB'], record['bundleEvidence']
            bundle = evidence['sourceBundle']
        else:
            found = [o for o in environments[kind].objects if o.type.name == 'Material' and o.path_id == pid]
            require(len(found) == 1, 'Original skill material is ambiguous')
            obj = found[0]; raw, material, cab = obj.get_raw_data(), obj.read_typetree(), obj.assets_file.name
            identity = D15 if kind == 'local' else SHARED
            bundle = identity[0]
            evidence = dict(sourceBundle=bundle, sourceBundleBytes=identity[1], sourceBundleSHA256=identity[2],
                wholeBundleSHA256Verified=True)
        require(sha(raw) == digest, 'Original skill material digest differs')
        metadata, raw_file = output / (str(pid) + '.json'), output / (str(pid) + '.raw')
        save_json(metadata, material); write_private(raw_file, raw)
        sid = int(material['m_Shader']['m_PathID'])
        require(sid in shaders_by_id, 'Unresolved original skill shader')
        # These original materials retain stale serialized invalid keywords.
        # They may not become active shader switches: every such name must be
        # absent from this exact original shader's entire keyword table.
        shader_keywords = shaders_by_id[sid].read_typetree()['m_ParsedForm']['m_KeywordNames']
        require(set(material['m_InvalidKeywords']).isdisjoint(shader_keywords),
                'Serialized invalid keyword exists in the original shader table')
        shader, match = selected_program(shaders_by_id[sid], material['m_ValidKeywords'], output)
        shaders[str(sid)] = shader
        materials.append(dict(sourceBundle=bundle, sourceCAB=cab, sourcePathID=str(pid),
            sourceName=material['m_Name'], sourceObjectSHA256=digest, metadataFile=str(metadata),
            shaderPathID=str(sid), shaderName=shader['name'], validKeywords=material['m_ValidKeywords'],
            invalidKeywords=material['m_InvalidKeywords'], exactMatches=[match], matchedExactly=True))
        if kind != 'local':
            records.append(dict(type='Material', externalCAB=cab, pathID=str(pid), sourceName=material['m_Name'],
                sourceObjectBytes=len(raw), sourceObjectSHA256=digest, rawFile=str(raw_file),
                metadataFile=str(metadata), bundleEvidence=evidence))
    document = dict(sourceEffectsBundle=D15[0], sourceEffectsBundleSHA256=D15[2],
        sourceShaderBundle=shader_bundle.name, sourceShaderBundleSHA256=SHADER_SHA,
        shaders=list(shaders.values()), materials=materials)
    save_json(output / 'd15-skill-shader-bindings-private.json', document)
    save_json(output / 'd15-skill-metal-programs-private.json', translate(document, output))
    save_json(output / 'd15-skill-additional-materials-private.json', dict(records=records))
