#!/usr/bin/env python3
"""Resolve only the three original D15 leg materials from cached bundles.

All I/O is local. The shared material is read from one exact ZIP member, not
found by an archive scan. The source shader keyword set must match one original
compiled program. Public code contains no shader, image or model payloads.
"""
from __future__ import annotations

import hashlib
import json
import struct
import zipfile
from pathlib import Path

from sun_triad_assets import private_output, require, write_private
from erlang_source_metal import translate

D15 = ('4f9476ea1326d7c102950a772ee44020.bin', 2561715,
       '971b3a1ea36eaaebaea4ae73a56ed65d8ffc4383625a06d64a209d8a70fbbd90')
SHARED = ('743fc535f600cb6addb0c2d20c96a9ab.bin', 986541,
          '863f1953d88d33beb0ec85229da17188376bb36e47d791146fc87a0f565706ec')
SHADER_SHA = 'c0b1fe09ba0684e474297ade8dcd7fee7b5d2e780236029c544c1986dea1e972'
MATERIALS = {
    -470710377040222942: (D15, '0709852707471efa623b5b73419ceec0975c7cd15ae5d6d5ee8a9036f5f11d51'),
    -8873318411363514674: (D15, '99e3379942d86218ba8bbf76a249c9b6a2c6831e4cd4c1fcf6a4aac674b09161'),
    -2244836283075552378: (SHARED, 'e0c6b638dcec325e5c727854cf98eabec85b26e427e9c2cc4cc258f79a95223f'),
}


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def save_json(path, value):
    write_private(path, json.dumps(value, separators=(',', ':'), allow_nan=False).encode())


def selected_program(shader, keywords, output):
    """Decode the one combined GLES program with this exact material keyword set."""
    from UnityPy.export.ShaderConverter import ShaderSubProgram
    from UnityPy.helpers import CompressionHelper
    from UnityPy.streams import EndianBinaryReader

    tree = shader.read_typetree()
    parsed = tree['m_ParsedForm']
    require(tree['platforms'] == [9] and len(tree['offsets']) == 1 and
            len(tree['offsets'][0]) == len(tree['compressedLengths'][0]) ==
            len(tree['decompressedLengths'][0]) == 1, 'Unsupported original shader platform layout')
    choices = {}
    for si, sub in enumerate(parsed['m_SubShaders']):
        for pi, source_pass in enumerate(sub['m_Passes']):
            for stage in ('progVertex', 'progFragment', 'progGeometry', 'progHull', 'progDomain'):
                for player, variants in enumerate(source_pass[stage]['m_PlayerSubPrograms']):
                    for variant in variants:
                        names = [parsed['m_KeywordNames'][i] for i in variant['m_KeywordIndices']]
                        if set(names) == set(keywords):
                            key = (si, pi, variant['m_BlobIndex'])
                            choices[key] = (stage, player, variant, names)
    require(len(choices) == 1, 'Original material has no unique exact keyword program')
    (si, pi, index), (stage, player, variant, names) = next(iter(choices.items()))
    offset, compressed, expanded = tree['offsets'][0][0], tree['compressedLengths'][0][0], tree['decompressedLengths'][0][0]
    require(0 <= offset < offset + compressed <= len(tree['compressedBlob']) and 0 < expanded <= 256_000_000,
            'Original shader block bounds differ')
    blob = CompressionHelper.decompress_lz4(bytes(tree['compressedBlob'][offset:offset + compressed]), expanded)
    require(len(blob) == expanded and len(blob) >= 4, 'Original shader expansion differs')
    count = struct.unpack_from('<I', blob)[0]
    require(0 < count < 20000 and 0 <= index < count and 4 + count * 12 <= len(blob),
            'Original shader program table is invalid')
    start, size, segment = struct.unpack_from('<III', blob, 4 + 12 * index)
    require(segment == 0 and 4 + count * 12 <= start < start + size <= len(blob),
            'Selected shader program is out of bounds')
    program = ShaderSubProgram(EndianBinaryReader(blob[start:start + size], endian='<'))
    require(set(program.m_Keywords) == set(names) and int(program.m_ProgramType) == variant['m_GpuProgramType']
            and int(program.m_ProgramType) in (3, 4, 5, 6), 'Selected shader program identity differs')
    raw = bytes(program.m_ProgramCode)
    source = raw.decode('utf8', errors='strict')
    require(len(raw) <= 256_000 and '#ifdef VERTEX\n' in source and '#ifdef FRAGMENT\n' in source
            and source.endswith('\n'), 'Original combined GLSL program is unsupported')
    glsl = output / (str(shader.path_id) + '-' + str(index) + '.glsl')
    write_private(glsl, raw)
    # Retain the exact relevant parsed properties and states. Large unrelated
    # keyword programs are not copied or decoded.
    projection = {k: parsed[k] for k in ('m_Name', 'm_PropInfo')}
    projection['m_SubShaders'] = [dict(m_Tags=s['m_Tags'], m_Passes=[
        dict(m_State=p['m_State']) for p in s['m_Passes']]) for s in parsed['m_SubShaders']]
    parsed_path = output / (str(shader.path_id) + '.selected-parsed.json')
    save_json(parsed_path, projection)
    match = dict(subshader=si, passIndex=pi, stage=stage, playerIndex=player, blobIndex=index,
        keywords=names, gpuProgramType=int(program.m_ProgramType), glslFile=str(glsl), glslSHA256=sha(raw),
        glslBytes=len(raw), tableOffset=start, tableBytes=size)
    record = dict(pathID=str(shader.path_id), name=parsed['m_Name'],
        sourceObjectSHA256=sha(shader.get_raw_data()), sourceCAB=shader.assets_file.name,
        parsedFile=str(parsed_path), parsedProjection='original properties, subshader tags and pass states',
        programBlobSHA256=sha(blob), variants=[match])
    return record, match


def prepare_materials(models, archive, shader_bundle, output):
    import UnityPy
    require(UnityPy.__version__ == '1.25.4', 'Use reviewed UnityPy 1.25.4')
    UnityPy.config.FALLBACK_UNITY_VERSION = '6000.3.11f1'
    output = private_output(output)
    require(not any(output.iterdir()), 'New D15 material output must be empty')
    raw = (models / D15[0]).read_bytes()
    require(len(raw) == D15[1] and sha(raw) == D15[2], 'Original D15 bundle differs')
    environments = {D15[0]: UnityPy.load(raw)}
    with zipfile.ZipFile(archive) as container:
        member = 'bundles/' + SHARED[0]
        info = container.getinfo(member)
        require(info.file_size == SHARED[1], 'Original shared material ZIP member size differs')
        raw = container.read(info)
    require(len(raw) == SHARED[1] and sha(raw) == SHARED[2], 'Original shared material bundle differs')
    environments[SHARED[0]] = UnityPy.load(raw)
    shader_raw = shader_bundle.read_bytes()
    require(sha(shader_raw) == SHADER_SHA, 'Original shared shader bundle differs')
    shader_objects = {o.path_id: o for o in UnityPy.load(shader_raw).objects if o.type.name == 'Shader'}
    shaders, materials, records = {}, [], []
    for path_id, (identity, digest) in MATERIALS.items():
        objects = [o for o in environments[identity[0]].objects if o.path_id == path_id and o.type.name == 'Material']
        require(len(objects) == 1, 'Original material object is ambiguous')
        obj = objects[0]
        raw = obj.get_raw_data()
        require(sha(raw) == digest, 'Original material bytes differ')
        material = obj.read_typetree()
        metadata = output / ('material-' + str(path_id) + '.json')
        raw_path = output / ('material-' + str(path_id) + '.raw')
        save_json(metadata, material)
        write_private(raw_path, raw)
        sid = int(material['m_Shader']['m_PathID'])
        require(sid in shader_objects and not material['m_InvalidKeywords'], 'Unresolved original material shader')
        shader, match = selected_program(shader_objects[sid], material['m_ValidKeywords'], output)
        shaders[str(sid)] = shader
        materials.append(dict(sourceBundle=identity[0], sourceCAB=obj.assets_file.name,
            sourcePathID=str(path_id), sourceName=material['m_Name'], sourceObjectSHA256=digest,
            metadataFile=str(metadata), shaderPathID=str(sid), shaderName=shader['name'],
            validKeywords=material['m_ValidKeywords'], invalidKeywords=[], exactMatches=[match], matchedExactly=True))
        if identity == SHARED:
            records.append(dict(type='Material', externalCAB=obj.assets_file.name, pathID=str(path_id),
                sourceName=material['m_Name'], sourceObjectBytes=len(raw), sourceObjectSHA256=digest,
                rawFile=str(raw_path), metadataFile=str(metadata),
                bundleEvidence=dict(sourceBundle=identity[0], sourceBundleBytes=identity[1],
                    sourceBundleSHA256=identity[2], exactMember='bundles/' + identity[0], wholeBundleSHA256Verified=True)))
    document = dict(sourceEffectsBundle=D15[0], sourceEffectsBundleSHA256=D15[2],
        sourceShaderBundle=shader_bundle.name, sourceShaderBundleSHA256=SHADER_SHA,
        shaders=list(shaders.values()), materials=materials)
    bindings = output / 'd15-shader-material-bindings-private.json'
    programs = output / 'd15-metal-material-patches-private.json'
    additional = output / 'd15-additional-material-records-private.json'
    save_json(bindings, document)
    save_json(programs, translate(document, output))
    save_json(additional, dict(records=records))
    return bindings, programs, additional
