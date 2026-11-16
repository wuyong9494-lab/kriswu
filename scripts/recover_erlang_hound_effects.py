#!/usr/bin/env python3
"""Recover the exact D15 hound source cache and run the existing sampler.

Only the pinned local source bundles are accepted. Original object and
PPtr identities, shader keyword selection and compressed texture bytes are
retained. No particle, clock, material formula or production pin is changed.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import struct
import warnings
from pathlib import Path
from types import SimpleNamespace

import numpy as np

from erlang_effect_materials import save_json, selected_program
from erlang_source_metal import translate
from prepare_erlang_hound_effects import BUNDLE, EFFECTS, HOUND_GLB_SHA, build, inventory
from sun_triad_assets import private_output, require, write_private


SOURCES = {
    '4f9476ea1326d7c102950a772ee44020.bin': (2561715, BUNDLE[1]),
    '743fc535f600cb6addb0c2d20c96a9ab.bin': (986541, '863f1953d88d33beb0ec85229da17188376bb36e47d791146fc87a0f565706ec'),
    'ff1080526339a7afed2acb60ee537859.bin': (1229196, '8db3cfd00de2a95055ed1c3483973652ec9aadaec273b743e21c902824d20ab6'),
    'b77cd85962dab26b5e542811e8599be3.bin': (1785198, 'c0b1fe09ba0684e474297ade8dcd7fee7b5d2e780236029c544c1986dea1e972'),
    '3f172fe58bba07b72356224fed03c89f.bin': (5043334, '4d3a9aeb848352f55914eabf9e44ccb13cb9e6b275b18bfb994ffdc7b6dc1fb4'),
    '9d3e616ea68b083cc7b1b8b92e5f72a8.bin': (68114260, 'feffa7c512ceb35663bf7fdd80910ff0927c0f8b31deabdd8413777383392f2e'),
    'e0827787798b68df283fc2391b8d7f11.bin': (21041786, '66b4fd415880e467fb328d4ba8c353c12387a89f5d2e3f7d5b06f1860454540a'),
    'globalgamemanagers': (673748, '1ddbe17aab3a2997a1913e122eb9099da5ed17b94aff84fecd288914fecb2e0f'),
}
MATERIALS = {
    -2884023811106616991: 'd8aac102cb17186dadad923f6f81a8eaf18fcbac70ef262280e7c85cc2da00eb',
    -1633406565193228711: '2910348b914657f92ee4dbe08a1812c6cebd2aa594e74538c599d004926ff8d6',
    6155268752203223441: '2ec71f972fd99cf8e078b402225a6b81ecc089c792bb74ce045d3845536f6355',
    1330429904785901429: '44b76454b6833386e11d4e87599abd948f18c432763f04d497c62ec951e23b17',
    -1725078091730863546: 'af60e5c5082dc3bb0ba2cbe97ef792af07b3219f5bb00f0d920d974671b7f477',
    2299989387330966054: '03727ea2fdbbf35871e028007a0177b452b218539cadff57dc5ca510b8aba673',
}
PROFILE_SHA = 'c5bbe34d04d4efb59c46a122b3e1e35b1d196e79b394783fafadea4043103fbd'
CHARACTER_SHA = 'af7106eea49691b3057772203907a5a350947e68403e0e0e8b69de9c8d082431'


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def checked(path, identity):
    size, digest = identity
    require(path.is_file() and not path.is_symlink() and path.stat().st_size == size,
            'Original source size or file type differs: ' + path.name)
    raw = path.read_bytes()
    require(sha(raw) == digest, 'Original source SHA256 differs: ' + path.name)
    return raw


class OriginalObjects:
    def __init__(self, source, mesh_bundle, *, additional_sources=None):
        import UnityPy
        require(UnityPy.__version__ == '1.25.4', 'Use reviewed UnityPy 1.25.4')
        UnityPy.config.FALLBACK_UNITY_VERSION = '6000.3.11f1'
        self.environments, self.by_cab, self.identities = {}, {}, {}
        inputs = {name: (mesh_bundle if name == '3f172fe58bba07b72356224fed03c89f.bin' else source / name, identity)
                  for name, identity in SOURCES.items()}
        for name, value in (additional_sources or {}).items():
            require(name not in inputs, 'Additional source attempts to replace a fixed original bundle')
            inputs[name] = value
        for name, (path, identity) in inputs.items():
            raw = checked(path, identity)
            environment = UnityPy.load(raw)
            self.environments[name] = environment
            files = {id(o.assets_file): o.assets_file for o in environment.objects}
            require(len(files) == 1, 'Original bundle has unexpected serialized file count')
            cab = next(iter(files.values()))
            require(cab.name not in self.by_cab, 'Original CAB identity is ambiguous')
            self.by_cab[cab.name] = {o.path_id: o for o in environment.objects}
            self.identities[cab.name] = dict(sourceBundle=name, sourceBundleBytes=len(raw),
                sourceBundleSHA256=identity[1], wholeBundleSHA256Verified=True)

    def resolve(self, owner, pointer, kind):
        cab = owner.assets_file
        file_id, path_id = pointer['m_FileID'], pointer['m_PathID']
        require(isinstance(file_id, int) and isinstance(path_id, int) and path_id != 0,
                'Original PPtr is null or invalid')
        if file_id:
            require(1 <= file_id <= len(cab.externals), 'Original external PPtr ordinal differs')
            name = cab.externals[file_id - 1].path.rsplit('/', 1)[-1]
        else:
            name = cab.name
        objects = self.by_cab.get(name)
        require(objects is not None and path_id in objects, 'Original PPtr source CAB or object is missing')
        result = objects[path_id]
        require(result.type.name == kind, 'Original PPtr object type differs')
        return result

    def record(self, obj, directory, *, metadata=None):
        raw = obj.get_raw_data()
        stem = str(obj.path_id)
        raw_path = directory / (stem + '.raw')
        write_private(raw_path, raw)
        result = dict(type=obj.type.name, externalCAB=obj.assets_file.name, pathID=stem,
            sourceObjectBytes=len(raw), sourceObjectSHA256=sha(raw), rawFile=str(raw_path),
            bundleEvidence=self.identities[obj.assets_file.name])
        if metadata is not None:
            path = directory / (stem + '.json')
            save_json(path, metadata)
            result['metadataFile'] = str(path)
        return result


def project_settings(objects, directory):
    source = objects.environments['globalgamemanagers']
    found = {kind: [o for o in source.objects if o.type.name == kind]
             for kind in ('PlayerSettings', 'PhysicsManager', 'QualitySettings')}
    require(all(len(value) == 1 for value in found.values()), 'Original project settings are ambiguous')
    player = found['PlayerSettings'][0].get_raw_data()
    require(sha(player) == '5fe9e533c9b17a8cafe0aa25387a6a6ff738641b27d5334ff117e276cc293cb9' and
            struct.unpack_from('<i', player, 256)[0] == 0, 'Original color-space prefix differs')
    save_json(directory / 'source-color-space-private.json', dict(
        memberSHA256=SOURCES['globalgamemanagers'][1], playerSettingsSHA256=sha(player),
        projectActiveColorSpace=0, completeTypeTreeRead=False,
        verifiedField=dict(field='m_ActiveColorSpace', type='int', offset=256, endOffset=260, value=0)))
    values = []
    for kind, expected in (
        ('PhysicsManager', '3180439a7fe54ae70297e236f16f23003b72b8dbae6bf179dc043c2e9a5be8ee'),
        ('QualitySettings', '7e1c4004b906f69308e973ecc7d3d09105e4f8933aea2e601931a0edc9e1cf8c')):
        obj = found[kind][0]
        require(sha(obj.get_raw_data()) == expected, 'Original physics or quality identity differs')
        values.append(dict(type=kind, completeTypeTreeRead=True, sha256=expected, values=obj.read_typetree()))
    save_json(directory / 'source-physics-quality-private.json', values)


def prepare_cache(objects, output, *, effects=EFFECTS, material_scope=MATERIALS,
                  expected_emitters=9, selected_systems=None, schema='recovered-d15-hound-source-inputs-v1'):
    from UnityPy.helpers.MeshHelper import MeshHandler
    external, shader_dir, programs = (output / n for n in ('external-objects', 'shader-source', 'metal-programs'))
    for directory in (external, shader_dir, programs):
        directory.mkdir(parents=True, mode=0o700)
    environment = objects.environments[BUNDLE[0]]
    materials, meshes, emitters = {}, {}, []
    for name, identity in effects.items():
        _, rows = inventory(environment, name, identity)
        for row in rows:
            if selected_systems is not None:
                systems = [c for c in row['components'] if c.type.name == 'ParticleSystem']
                if not systems or systems[0].path_id not in selected_systems[name]:
                    continue
            for renderer in (c for c in row['components'] if c.type.name == 'ParticleSystemRenderer'):
                values = renderer.read_typetree()
                if not values['m_Enabled']:
                    continue
                require(len(values['m_Materials']) == 1, 'Original hound material slots differ')
                material = objects.resolve(renderer, values['m_Materials'][0], 'Material')
                materials[material.path_id] = material
                if values['m_RenderMode'] == 4:
                    mesh = objects.resolve(renderer, values['m_Mesh'], 'Mesh')
                    meshes[mesh.path_id] = mesh
                emitters.append(dict(effect=name, sourceRendererPathID=str(renderer.path_id),
                    sourceRendererSHA256=sha(renderer.get_raw_data()), materialPathID=str(material.path_id)))
    require(len(emitters) == expected_emitters and set(materials) == set(material_scope), 'Original effect source scope differs')
    material_records, texture_objects, binding_materials, shaders = [], {}, [], {}
    for path_id, obj in materials.items():
        require(sha(obj.get_raw_data()) == material_scope[path_id], 'Original effect material raw identity differs')
        values = obj.read_typetree()
        record = objects.record(obj, external, metadata=values)
        record['sourceName'] = values['m_Name']
        material_records.append(record)
        for _, texture in values['m_SavedProperties']['m_TexEnvs']:
            pointer = texture['m_Texture']
            if pointer['m_PathID']:
                original = objects.resolve(obj, pointer, 'Texture2D')
                previous = texture_objects.get(original.path_id)
                require(previous is None or previous.assets_file.name == original.assets_file.name,
                        'Original texture pathID is ambiguous across CABs')
                texture_objects[original.path_id] = original
        shader = objects.resolve(obj, values['m_Shader'], 'Shader')
        keywords = shader.read_typetree()['m_ParsedForm']['m_KeywordNames']
        require(set(values['m_InvalidKeywords']).isdisjoint(keywords), 'Invalid material keyword is active in source shader')
        shader_record, selected = selected_program(shader, values['m_ValidKeywords'], shader_dir)
        shaders[str(shader.path_id)] = shader_record
        binding_materials.append(dict(sourceBundle=record['bundleEvidence']['sourceBundle'],
            sourceCAB=obj.assets_file.name, sourcePathID=str(path_id), sourceName=values['m_Name'],
            sourceObjectSHA256=record['sourceObjectSHA256'], metadataFile=record['metadataFile'],
            shaderPathID=str(shader.path_id), shaderName=shader_record['name'],
            validKeywords=values['m_ValidKeywords'], invalidKeywords=values['m_InvalidKeywords'],
            exactMatches=[selected], matchedExactly=True))
    textures = []
    for path_id, obj in texture_objects.items():
        texture, values = obj.read(), obj.read_typetree()
        # Complete original object and compressed mip bytes accompany this
        # explicit metadata projection; no partial tree is labelled complete.
        keys = ('m_Name', 'm_Width', 'm_Height', 'm_MipCount', 'm_ColorSpace', 'm_TextureFormat', 'm_TextureSettings')
        record = objects.record(obj, external, metadata={k: values[k] for k in keys})
        record['metadataProjection'] = list(keys)
        record['sourceName'] = texture.m_Name
        raw = bytes(texture.get_image_data())
        compressed_path = external / (str(path_id) + '.texture')
        write_private(compressed_path, raw)
        image = texture.image.convert('RGBA')
        png = io.BytesIO(); image.save(png, format='PNG'); pixels = png.getvalue()
        png_path = external / (str(path_id) + '.png'); write_private(png_path, pixels)
        record.update(textureFile=str(compressed_path), sourceTextureSHA256=sha(raw),
            sourceTextureBytes=len(raw), pngFile=str(png_path), pngSHA256=sha(pixels))
        textures.append(record)
    mesh_records = []
    for path_id, obj in meshes.items():
        mesh = obj.read(); handler = MeshHandler(mesh); handler.process()
        arrays = dict(positions=handler.m_Vertices, normals=handler.m_Normals, uv0=handler.m_UV0)
        for key, attr in (('uv1', 'm_UV1'), ('colors', 'm_Colors'), ('tangents', 'm_Tangents')):
            value = getattr(handler, attr, None)
            if value is not None and len(value): arrays[key] = value
        for index, triangles in enumerate(handler.get_triangles()):
            arrays['triangles' + str(index)] = triangles
        stream = io.BytesIO(); np.savez_compressed(stream, **arrays); raw = stream.getvalue()
        path = external / (str(path_id) + '.npz'); write_private(path, raw)
        record = objects.record(obj, external)
        record.update(name=mesh.m_Name, arraysFile=str(path), arraysSHA256=sha(raw))
        mesh_records.append(record)
    bindings = dict(sourceEffectsBundle=BUNDLE[0], sourceEffectsBundleSHA256=BUNDLE[1],
        sourceShaderBundle='b77cd85962dab26b5e542811e8599be3.bin',
        sourceShaderBundleSHA256=SOURCES['b77cd85962dab26b5e542811e8599be3.bin'][1],
        materials=binding_materials, shaders=list(shaders.values()))
    save_json(shader_dir / 'h17-shader-material-bindings-private.json', bindings)
    save_json(programs / 'h17-metal-material-patches-private.json', translate(bindings, programs))
    save_json(external / 'recovered-dependencies-private.json', dict(records=material_records))
    save_json(external / 'recovered-material-textures-private.json', dict(records=textures))
    save_json(external / 'mesh-arrays-private.json', dict(records=mesh_records))
    project_settings(objects, shader_dir)
    return dict(schema=schema,
        sourceFiles=[dict(name=v['sourceBundle'], bytes=v['sourceBundleBytes'], sha256=v['sourceBundleSHA256'])
                     for v in objects.identities.values()],
        sourceEmitters=emitters, materialRecords=material_records, textureRecords=textures, meshRecords=mesh_records,
        originalUnityEngineVersionVerified=False, originalAutomaticSeedRealizationOnly=True,
        nativeRenderingVerified=False, sourceFormulaReplacements=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('source-cache', 'mesh-bundle', 'profile', 'hound-glb', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    warnings.filterwarnings('ignore', category=Warning, module='UnityPy')
    profile_raw = checked(args.profile, (18924288, PROFILE_SHA))
    profile = json.loads(profile_raw)
    require(profile['id'] == 'wuyong_erlang' and profile['sha256'] == CHARACTER_SHA and
            len(profile['clips']) == 62, 'Recovered hound destination actor differs')
    checked(args.profile.parent / (profile['resourceName'] + '.glb'), (18594716, CHARACTER_SHA))
    checked(args.hound_glb, (438144, HOUND_GLB_SHA))
    objects = OriginalObjects(args.source_cache, args.mesh_bundle)
    output = private_output(args.output)
    require(not any(output.iterdir()), 'Recovered hound output must be empty')
    cache = output / 'source-inputs-private'; cache.mkdir(mode=0o700)
    receipt = prepare_cache(objects, cache)
    source_inventory = [dict(name=str(p.relative_to(cache)), bytes=p.stat().st_size, sha256=sha(p.read_bytes()))
                        for p in sorted(cache.rglob('*')) if p.is_file()]
    receipt['files'] = source_inventory
    save_json(cache / 'source-cache-recovery-receipt-private.json', receipt)
    destination = output / 'runtime'; destination.mkdir(mode=0o700)
    build(SimpleNamespace(models=args.source_cache, effects=cache, output=destination,
        shader_bundle=args.source_cache / 'b77cd85962dab26b5e542811e8599be3.bin',
        profile=args.profile, hound_glb=args.hound_glb))
    result = json.loads((destination / 'd15-hound-fx-receipt-private.json').read_bytes())
    require(result['profileSHA256'] == PROFILE_SHA and result['characterSHA256'] == CHARACTER_SHA,
            'Recovered hound candidate actor binding differs')
    save_json(output / 'hound-recovery-private.json', dict(schema='recovered-d15-hound-runtime-v1',
        sourceCacheReceiptSHA256=sha((cache / 'source-cache-recovery-receipt-private.json').read_bytes()),
        samplingReceiptSHA256=sha((destination / 'd15-hound-fx-receipt-private.json').read_bytes()),
        profileSHA256=PROFILE_SHA, characterSHA256=CHARACTER_SHA, effectsFile=result['effectsFile'],
        productionPinsChanged=False, nativeRenderingVerified=False))


if __name__ == '__main__':
    main()
