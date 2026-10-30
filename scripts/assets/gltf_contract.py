"""Fail authoring checks for features the current Arena importer cannot preserve.

This is a feature gate, not a renderer, visual approval, or a general glTF validator.
Metallic/roughness scalar factors remain an intentional Lambert/constant approximation.
"""


def unsupported_features(document):
    errors = []
    for extension in document.get('extensionsRequired', []):
        errors.append(f'required extension {extension} has no Arena import contract')
    for index, material in enumerate(document.get('materials', [])):
        prefix = f'material[{index}]'
        for key in ('normalTexture', 'occlusionTexture', 'emissiveTexture'):
            if key in material:
                errors.append(f'{prefix}.{key} is not imported')
        pbr = material.get('pbrMetallicRoughness', {})
        if 'metallicRoughnessTexture' in pbr:
            errors.append(f'{prefix}.metallicRoughnessTexture is not imported')
        texture = pbr.get('baseColorTexture')
        if texture is not None:
            if texture.get('texCoord', 0) != 0 or texture.get('extensions'):
                errors.append(f'{prefix}.baseColorTexture requires unsupported UV mapping')
            if pbr.get('baseColorFactor', [1, 1, 1, 1]) != [1, 1, 1, 1]:
                errors.append(f'{prefix} texture factor multiplication is not imported')
        if material.get('alphaMode', 'OPAQUE') != 'OPAQUE':
            errors.append(f'{prefix} alphaMode needs a separate tested render contract')
    for index, mesh in enumerate(document.get('meshes', [])):
        for primitive in mesh.get('primitives', []):
            if primitive.get('targets'):
                errors.append(f'mesh[{index}] morph targets are not imported; use facial bones')
            if primitive.get('mode', 4) != 4:
                errors.append(f'mesh[{index}] must export triangles')
    for animation in document.get('animations', []):
        name = animation.get('name', '<unnamed>')
        for sampler in animation.get('samplers', []):
            if sampler.get('interpolation', 'LINEAR') not in ('LINEAR', 'STEP'):
                errors.append(f'{name}: bake animation to LINEAR or STEP before export')
        for channel in animation.get('channels', []):
            if channel.get('target', {}).get('path') not in ('translation', 'rotation', 'scale'):
                errors.append(f'{name}: unsupported animation target path')
    return errors
