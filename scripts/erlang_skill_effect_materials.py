#!/usr/bin/env python3
"""Resolve the exact original materials for a scoped D15 skill effect.

Only already supplied source bundles and authenticated object snapshots are
read. Textures remain independently checked by SourceAssets during sampling.
"""
from __future__ import annotations
import json
import zipfile
from pathlib import Path
from types import SimpleNamespace

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

IMPACT_MATERIALS = {
    -8870619190891733605: ('cached', '01490deb998b33faec99272a817bce44b5ae3886df7b60e5a57629a127021946'),
    -8038901980011519531: ('local', '8c7d1c9b5208dc773120f70a4f32138ecf669fdabe47d9f1c2058abf977c055d'),
    -5850577637598373218: ('shared', 'f8270e1621731f076d74667d6e8b4d4809aee81c3978da68df7dcd466a699573'),
    -5491752970965739280: ('cached', 'd99ec2f68380c74d3be84c921ea933138f4c4d0c754290c4b358528b32fb84d4'),
    -4240759839167470152: ('cached', 'e11965be144b4f848939f58e345425b6d76c8cb2bfd846c6b0bb1c3cd6804dcc'),
    -3701573546119953775: ('cached', '3adb74f15363f7ad71c328037761cf65ef260859f4e9780d8e316be94bd60f74'),
    -3164343070369702147: ('local', '4eb86f7f1fccfd316358764a6009f890e9a3024ad3d269e0dd4c72a9b3549031'),
    -3093058558531369391: ('local', 'a38be628d532209e2ca44d7a9aa7e8a6887698b0782de24a5c19bbffaaf5cf9e'),
    -1633406565193228711: LASER_MATERIALS[-1633406565193228711],
    -654479186809044038: ('local', '6519cec5d155d5fd780ce627097c8a60ffdce4d4a48d6e1bfcd538fccc434cfd'),
    2075884677916889184: ('cached', '0d6b3bff2fb774902bc87ab25a4142eec26c0931b2e1371d80e712d7b93a1836'),
    2581545832667885839: ('local', '081a90380cccbf5ed5925349c37acb3cd480c17c38636ff2d77b60d4654ccbb7'),
    3924256803729815475: ('shared', '3a06ee5117f55fd87d74f2a0dc125ee971de54ac3109cdff10e0d229a83a8a8d'),
    4051454576017455378: ('cached', '446646b0643f6366154e3d51557c9a5a813e0881842c8b9e4ac4e4fe2862d30b'),
    4060845742799347738: ('cached', '72836465a08598e82c09f2fa47ac3a3353ea375c758df30ba60597b9dfd413ee'),
    5479373683313282163: ('local', 'f901a160fe755ed491edcb899a5773498991347817ea418f825c8ac9e530007a'),
    5853404374668710453: ('local', 'e0b1ee073ba2454f3ede842b8cb054d3d1153cb1eccf7f7aaf3d238c2793cf9d'),
    6433155620363279066: ('local', 'df03f724be9662ddf97ae4674ddff46bb31f8b4bbd51803c56be9ee9a4ae7ffa'),
    7001994652851409494: ('cached', '843fc46b2a2798297905f11fbebd0c250dd9da1ee84533efb701926a2415ca1b'),
    8768725238195491215: ('local', 'c5755f920891ccdf8ed127807be730bc5d2f4aeab12175f3a94297a0f8573b62'),
    9144163597607286078: ('cached', '0a502e591c95261b0e1682a3bb5ce3cfd9e2f448e33f1e26445fa61077cd89c0'),
}

AFTERSHOCK_START_MATERIALS = {
    -2562211360462363860: ('cached', 'a6f16cea050f55e9c17f1f4816390fef1df3faf23491d888890f0e10432514de'),
    3709641280244361373: ('local', '2acb1be1a7816818fa0a7d81756e633f98a8ab3ad1849273a15b3d5ac7f3dc34'),
}


def prepare_materials(models, archive, shader_bundle, effects, output, scope=LASER_MATERIALS,
                      additional_records=None, additional_shaders=None):
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
    if additional_shaders is not None:
        receipt_raw = additional_shaders.read_bytes()
        require(sha(receipt_raw) == '9d18747b18036a0cc2c9cb696c99920064e725a58a446c36aad8c69a57ae5292',
                'Original additional shader receipt differs')
        extra = json.loads(receipt_raw)
        require(not extra['missing'] and len(extra['records']) == 1, 'Additional shader recovery is incomplete')
        record = extra['records'][0]; raw = Path(record['rawFile']).read_bytes()
        require(record['type'] == 'Shader' and record['pathID'] == '2855819893914472268' and
                sha(raw) == record['sourceObjectSHA256'] == 'f0229a7fbc7710912cb7e3e4059ce20869ae8c8dcafbd17d568ae5dad02d810c',
                'Original additional shader bytes differ')
        shader_template = next(iter(shaders_by_id.values()))
        tree = TypeTreeHelper.read_typetree(shader_template.serialized_type.node,
            EndianBinaryReader(raw, endian=shader_template.reader.endian), byte_size=len(raw), as_dict=True)
        shaders_by_id[2855819893914472268] = SimpleNamespace(path_id=2855819893914472268,
            read_typetree=lambda tree=tree: tree, get_raw_data=lambda raw=raw: raw,
            assets_file=SimpleNamespace(name=record['externalCAB']))
    cached = json.loads((effects / 'external-objects/recovered-dependencies-private.json').read_bytes())['records']
    if additional_records is not None:
        cached += json.loads(additional_records.read_bytes())['records']
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
