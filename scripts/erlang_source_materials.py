"""D15's original paint masks, with portable lighting explicitly separated.

The original CharacterShader program 4082 applies six ordered paints. Program
4064 applies four: the serialized weapon _NumPaints=5 does not enable a fifth
paint, because USE_B_AS_WEAPON_COLOR reserves that path for a runtime effect.
Neither that effect nor MatCap/rim/skin-color state is invented by this bake.
"""
from __future__ import annotations

import numpy as np

from sun_triad_materials import embedded_texture, source_sampler, require

SHADER_PROOFS = {
    'armor6': dict(blobIndex=4082, sha256='5a4ce303c08a731fae2c2c7a8fc2a2f8d9be349d3115e53d456e9301c5541741'),
    'spear4': dict(blobIndex=4064, sha256='ea582a3ecc19443786c667c77510cc1f9725eb977284721221fdb8ff9419ae74'),
}
SHADER_BUNDLE_SHA = 'c0b1fe09ba0684e474297ade8dcd7fee7b5d2e780236029c544c1986dea1e972'


def paint_channels(serialized_count, keywords):
    common = {'USE_A_AS_SECOND_PAINT', 'USE_R_AS_THIRD_PAINT', 'USE_G_AS_FOURTH_PAINT'}
    if serialized_count == 6:
        expected = common | {'USE_B_AS_FIFTH_PAINT', 'USE_A_AS_SIXTH_PAINT', 'USE_SKIN_COLOR'}
        require(set(keywords) == expected, 'D15 armor shader keyword identity differs')
        return [('_Mask', 0), ('_Mask', 3)] + [('_Mask2', i) for i in range(4)], 'armor6'
    if serialized_count == 5:
        expected = common | {'USE_B_AS_WEAPON_COLOR', 'GLOWEFFECT_USE_MASK_B'}
        require(set(keywords) == expected, 'D15 spear shader keyword identity differs')
        return [('_Mask', 0), ('_Mask', 3), ('_Mask2', 0), ('_Mask2', 1)], 'spear4'
    raise ValueError('Unsupported exact D15 material variant')


def ordered_paints(main, masks, palette):
    result = np.array(main, dtype=float, copy=True)
    require(result.ndim == 3 and result.shape[2] == 4 and np.isfinite(result).all()
            and (result >= 0).all() and (result <= 1).all(), 'Invalid source diffuse')
    colors = np.asarray(palette, float)
    require(len(masks) in (4, 6) and colors.shape == (len(masks), 4)
            and np.isfinite(colors).all() and (colors >= 0).all() and (colors <= 1).all(),
            'Invalid D15 player palette')
    for mask, color in zip(masks, colors):
        mask = np.asarray(mask, float)
        require(mask.shape == result.shape[:2] and np.isfinite(mask).all()
                and (mask >= 0).all() and (mask <= 1).all(), 'Invalid source paint channel')
        result[:, :, :3] *= 1 + mask[:, :, None] * (color[:3] - 1)
    return result


def erlang_material(writer, material, cache):
    from PIL import Image
    key = material.m_Name
    if key in cache:
        return cache[key]
    properties = material.m_SavedProperties
    colors = {k: [v.r, v.g, v.b, v.a] for k, v in properties.m_Colors}
    floats = dict(properties.m_Floats)
    keywords = list(material.m_ValidKeywords)
    channels, variant = paint_channels(floats['_NumPaints'], keywords)
    require(material.m_Shader.m_PathID == 8133545925718130986,
            'Expected original CharacterShader identity')
    textures, bindings, images = {}, {}, {}
    for slot, env in properties.m_TexEnvs:
        pointer = env.m_Texture
        binding = dict(sourceFileID=pointer.m_FileID, sourcePathID=str(pointer.m_PathID),
                       scale=[env.m_Scale.x, env.m_Scale.y], offset=[env.m_Offset.x, env.m_Offset.y])
        if pointer.m_FileID == 0 and pointer.m_PathID:
            texture = pointer.read(); image = texture.image.convert('RGBA')
            index, receipt = embedded_texture(writer, image, texture.m_Name, source_sampler(texture))
            binding.update(texture=index, sourceName=texture.m_Name, sourceColorSpace=texture.m_ColorSpace,
                           width=texture.m_Width, height=texture.m_Height, **receipt)
            textures[slot], images[slot] = texture, image
        bindings[slot] = binding
    required = ['_MainTex', '_Mask', '_Mask2']
    require(all(slot in images for slot in required), 'Missing local D15 paint texture')
    require(all(bindings[s]['scale'] == [1, 1] and bindings[s]['offset'] == [0, 0] for s in required),
            'Source paint transform requires a separate adapter')
    require(all(images[s].size == images['_MainTex'].size for s in required), 'Paint sizes differ')
    pixels = {s: np.asarray(images[s], float) / 255 for s in required}
    palette = [colors['_MaskPlayerColor' + (str(i + 1) if i else '')] for i in range(len(channels))]
    painted = ordered_paints(pixels['_MainTex'], [pixels[s][:, :, c] for s, c in channels], palette)
    require(floats['_Alpha'] == 1 and floats['_Cull'] == 2 and floats['_SrcBlend'] == 1
            and floats['_DstBlend'] == 0 and floats['_ZWrite'] == 1, 'D15 opaque raster differs')
    painted[:, :, 3] = floats['_Alpha']
    baked = Image.fromarray(np.rint(np.clip(painted, 0, 1) * 255).astype('uint8'), 'RGBA')
    texture, receipt = embedded_texture(writer, baked, key+'_source_player_paints', source_sampler(textures['_MainTex']))
    settings = textures['_MainTex'].m_TextureSettings
    mip_count = int(getattr(textures['_MainTex'], 'm_MipCount', 1))
    raster = dict(cull='back', sourceCull=2, sourceBlend=[1, 0], writesDepth=True,
        filter='nearest' if settings.m_FilterMode == 0 else 'linear',
        mip='none' if mip_count <= 1 else ('linear' if settings.m_FilterMode == 2 else 'nearest'),
        wrapS='repeat' if settings.m_WrapU == 0 else 'clamp',
        wrapT='repeat' if settings.m_WrapV == 0 else 'clamp', maxAnisotropy=max(1, min(16, settings.m_Aniso)))
    index = len(writer.g['materials'])
    writer.g['materials'].append(dict(name=key, doubleSided=False, alphaMode='OPAQUE',
        pbrMetallicRoughness=dict(baseColorTexture=dict(index=texture), metallicFactor=.12, roughnessFactor=.72),
        extras=dict(sourceMaterial=key, sourceColors=colors, sourceFloats=floats, sourceKeywords=keywords,
            sourceTextureBindings=bindings, sourceRaster=raster, appliedSourcePalette='MaskPlayerColor',
            sourcePalette=palette, paintChannels=[[s, c] for s, c in channels], paintPreview=receipt,
            shaderProgramProof=dict(**SHADER_PROOFS[variant], sourceBundleSHA256=SHADER_BUNDLE_SHA),
            customShaderParity=False, dynamicWeaponColorApplied=False, skinColorDifferenceApplied=False)))
    cache[key] = index
    return index
