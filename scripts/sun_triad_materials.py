#!/usr/bin/env python3
"""Preserve the source character material and its baseline player palette.

The character shader applies three sequential multiply/mix paints through
Mask.r, Mask.a and Mask2.r. Source ModelSkin initializes the live MaskColor
properties from the serialized MaskPlayerColor palette. The resulting diffuse
image is a portable preview of that paint operation; lighting, MatCap, rim,
shadow-form and timed replacement shaders remain separately recorded source
properties, not a claim that a generic PBR shader is the original renderer.
"""
from __future__ import annotations
import hashlib
import io
import numpy as np


def require(condition, message):
    if not condition:
        raise ValueError(message)


def paint_rgba(main, masks, palette):
    """Apply the source shader's ordered paints without altering source alpha."""
    image = np.asarray(main, dtype=float)
    colors = np.asarray(palette, dtype=float)
    require(image.ndim == 3 and image.shape[2] == 4 and np.isfinite(image).all()
            and (image >= 0).all() and (image <= 1).all(), 'Invalid source diffuse pixels')
    require(1 <= len(masks) <= 3 and colors.shape == (len(masks), 4)
            and np.isfinite(colors).all() and (colors >= 0).all()
            and (colors <= 1).all(), 'Invalid source player palette')
    result = image.copy()
    for mask, color in zip(masks, colors):
        mask = np.asarray(mask, dtype=float)
        require(mask.shape == image.shape[:2] and np.isfinite(mask).all()
                and (mask >= 0).all() and (mask <= 1).all(), 'Invalid source paint mask')
        result[:, :, :3] *= 1 + mask[:, :, None] * (color[:3] - 1)
    return result


def source_sampler(texture):
    settings = texture.m_TextureSettings
    require(settings.m_FilterMode in (0, 1, 2) and settings.m_WrapU in (0, 1)
            and settings.m_WrapV in (0, 1), 'Unsupported original texture sampling')
    mip_count = int(getattr(texture, 'm_MipCount', 1))
    filtering = settings.m_FilterMode
    minimum = (9728 if filtering == 0 else 9729) if mip_count <= 1 else (
        9984 if filtering == 0 else (9986 if filtering == 1 else 9987))
    return dict(wrapS=10497 if settings.m_WrapU == 0 else 33071,
                wrapT=10497 if settings.m_WrapV == 0 else 33071,
                minFilter=minimum, magFilter=9728 if filtering == 0 else 9729)


def embedded_texture(writer, image, name, sampler):
    stream = io.BytesIO(); image.save(stream, format='PNG')
    raw = stream.getvalue(); digest = hashlib.sha256(raw).hexdigest()
    cache = getattr(writer, '_source_textures', {})
    key = (digest, tuple(sorted(sampler.items())))
    if key in cache:
        return cache[key], dict(sha256=digest, bytes=len(raw))
    try:
        sampler_index = writer.g['samplers'].index(sampler)
    except ValueError:
        sampler_index = len(writer.g['samplers']); writer.g['samplers'].append(sampler)
    image_index = len(writer.g['images'])
    writer.g['images'].append(dict(name=name, bufferView=writer.block(raw), mimeType='image/png'))
    texture_index = len(writer.g['textures'])
    writer.g['textures'].append(dict(source=image_index, sampler=sampler_index))
    cache[key] = texture_index; writer._source_textures = cache
    return texture_index, dict(sha256=digest, bytes=len(raw))


def material_descriptor(material, document=None):
    """Derive the release's supported raster state from the embedded source."""
    source = material.get('extras', {}).get('sourceRaster', {})
    if not source and document is not None:
        # Supplied personal portrait textures keep the sampler embedded in
        # that user's GLB; equipment's independently proven source state wins.
        texture=material.get('pbrMetallicRoughness',{}).get('baseColorTexture')
        if texture is not None:
            definition=document['textures'][texture['index']]
            sampler=document.get('samplers',[])[definition['sampler']] if 'sampler' in definition else {}
            minimum=sampler.get('minFilter',9987);maximum=sampler.get('magFilter',9729)
            require(minimum in (9728,9729,9984,9985,9986,9987) and maximum in (9728,9729),
                    'Unsupported supplied portrait sampler')
            source=dict(filter='nearest' if minimum in (9728,9984,9986) else 'linear',
                magnification='nearest' if maximum==9728 else 'linear',
                mip='none' if minimum in (9728,9729) else 'nearest' if minimum in (9984,9985) else 'linear')
            for key in ('wrapS','wrapT'):
                value=sampler.get(key,10497);require(value in (10497,33071),'Unsupported supplied portrait wrap mode')
                source[key]='repeat' if value==10497 else 'clamp'
    return dict(name=material['name'], doubleSided=material.get('doubleSided', False),
        cull=source.get('cull', 'back'), minification=source.get('filter', 'linear'),
        magnification=source.get('magnification',source.get('filter', 'linear')), mip=source.get('mip', 'none'),
        wrapS=source.get('wrapS', 'repeat'), wrapT=source.get('wrapT', 'repeat'),
        maxAnisotropy=source.get('maxAnisotropy', 1))


def original_material(writer, material, cache, *, double_sided_override=None):
    from PIL import Image
    key = material.m_Name
    if key in cache:
        old = writer.g['materials'][cache[key]]
        require(double_sided_override is None or old['doubleSided'] == double_sided_override,
                'Conflicting source cull overrides for one material')
        return cache[key]
    properties = material.m_SavedProperties
    colors = {k: [v.r, v.g, v.b, v.a] for k, v in properties.m_Colors}
    floats = dict(properties.m_Floats); environments = dict(properties.m_TexEnvs)
    keywords = list(material.m_ValidKeywords)
    count = floats['_NumPaints']
    require(count in (1, 2, 3), 'Unsupported source character palette count')
    count = int(count)
    require(count < 2 or 'USE_A_AS_SECOND_PAINT' in keywords, 'Unknown second source paint channel')
    require(count < 3 or 'USE_R_AS_THIRD_PAINT' in keywords, 'Unknown third source paint channel')
    textures, bindings, images = {}, {}, {}
    for slot, environment in environments.items():
        pointer = environment.m_Texture
        binding = dict(sourceFileID=pointer.m_FileID, sourcePathID=str(pointer.m_PathID),
            scale=[environment.m_Scale.x, environment.m_Scale.y],
            offset=[environment.m_Offset.x, environment.m_Offset.y])
        if pointer.m_FileID == 0 and pointer.m_PathID:
            texture = pointer.read(); image = texture.image.convert('RGBA')
            index, receipt = embedded_texture(writer, image, texture.m_Name, source_sampler(texture))
            binding.update(texture=index, sourceName=texture.m_Name, sourceColorSpace=texture.m_ColorSpace,
                           width=texture.m_Width, height=texture.m_Height, **receipt)
            textures[slot] = texture; images[slot] = image
        bindings[slot] = binding
    required = ['_MainTex', '_Mask'] + (['_Mask2'] if count == 3 else [])
    require(all(slot in images for slot in required), 'Source character paint texture is external or missing')
    require(all(bindings[slot]['scale'] == [1, 1] and bindings[slot]['offset'] == [0, 0]
                for slot in required), 'Source paint UV transformation needs an explicit adapter')
    size = images['_MainTex'].size
    require(all(images[slot].size == size for slot in required), 'Source paint texture dimensions differ')
    pixels = {slot: np.asarray(images[slot], dtype=float) / 255 for slot in required}
    masks = [pixels['_Mask'][:, :, 0]]
    if count >= 2: masks.append(pixels['_Mask'][:, :, 3])
    if count == 3: masks.append(pixels['_Mask2'][:, :, 0])
    palette = [colors['_MaskPlayerColor' + (str(i + 1) if i else '')] for i in range(count)]
    painted = paint_rgba(pixels['_MainTex'], masks, palette)
    # The source opaque character pass writes alpha from _Alpha, not MainTex.a.
    # Transparent model effects retain their external alpha pointer for their
    # separately authenticated shader binding; no guessed mask is substituted.
    alpha = floats.get('_Alpha', 1.)
    require(np.isfinite(alpha) and 0 <= alpha <= 1, 'Invalid original material alpha')
    painted[:, :, 3] = alpha
    baked = Image.fromarray(np.rint(np.clip(painted, 0, 1) * 255).astype('uint8'), 'RGBA')
    texture, baked_receipt = embedded_texture(writer, baked, key + '_source_player_paints',
                                              source_sampler(textures['_MainTex']))
    cull = floats['_Cull']; blend = (floats['_SrcBlend'], floats['_DstBlend'])
    require(cull in (0, 1, 2) and blend in ((1, 0), (5, 10)), 'Unsupported source character raster state')
    double_sided = cull == 0 if double_sided_override is None else double_sided_override
    settings = textures['_MainTex'].m_TextureSettings
    mip_count = int(getattr(textures['_MainTex'], 'm_MipCount', 1))
    raster = dict(cull='front' if cull == 1 else 'back', sourceCull=int(cull),
        sourceBlend=list(blend), writesDepth=bool(floats['_ZWrite']),
        filter='nearest' if settings.m_FilterMode == 0 else 'linear',
        mip='none' if mip_count <= 1 else ('linear' if settings.m_FilterMode == 2 else 'nearest'),
        wrapS='repeat' if settings.m_WrapU == 0 else 'clamp',
        wrapT='repeat' if settings.m_WrapV == 0 else 'clamp',
        maxAnisotropy=max(1, min(16, settings.m_Aniso)))
    index = len(writer.g['materials'])
    writer.g['materials'].append(dict(name=key, doubleSided=double_sided,
        alphaMode='BLEND' if blend == (5, 10) else 'OPAQUE',
        pbrMetallicRoughness=dict(baseColorTexture=dict(index=texture), metallicFactor=.12, roughnessFactor=.72),
        extras=dict(sourceMaterial=key, sourceColors=colors, sourceFloats=floats,
            sourceKeywords=keywords, sourceTextureBindings=bindings, sourceRaster=raster,
            appliedSourcePalette='MaskPlayerColor', sourcePalette=palette,
            paintPreview=baked_receipt, paintSampling='decoded source texel values',
            customShaderParity=False,
            sourceCullOverride=double_sided_override)))
    cache[key] = index
    return index
