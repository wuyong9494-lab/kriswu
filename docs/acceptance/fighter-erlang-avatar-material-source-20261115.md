# Erlang normal Avatar material: source export

## Status and scope

The original normal Avatar material now has a private, reproducible source-only
export: its exact selected GLSL program, an interface conversion to Metal, the
original material values, both original ETC2 texture streams, and all 11 source
mip levels decoded individually. The additional 1×1 white input is explicitly
the original shader's default for its null `_MainTex2` slot.

This export does not activate a material in the application, add a release
identity, implement a source event, or claim a native/GPU pass. Its manifest has
`runtimeBound=false`. The separate recolored material branch has no source
binding in this export.

## Exact original inputs

The inputs come from the previously audited Android 1.45.3 source catalog. Only
three named local bundles are read, each with its complete byte count and
SHA-256 checked before object selection.

| Original object | Identity |
| --- | --- |
| Material | `6052238147740425361`, `mtl_Erlang_triplanar_Avatar`; 1,716 bytes; SHA-256 `a0fa93408bb0cc520ec64cb8b77d460c8562837dc808198a9e7f072bf3729cbc` |
| Shader | `6408001018632598985`, `VFX/TwoMapOffsetFres_inv_abs_twoplanar_2`; SHA-256 `6137a33162d8c22bacba3c1a6714180f6137186385d4fad4545caac65e8d359c` |
| Selected program | Subshader 0, pass 0, blob 3; 6,794 bytes; SHA-256 `2a938668e0efa84f063a77636613ca24e639de7beb5191796770a1ca5598bdc5` |
| Background texture | `-641309692710952876`, `wavyShocks 1`; 512×512 ETC2 RGBA8, one mip; original stream SHA-256 `69975fddf73fdfb57ec55e1c1b2a009184cd8aa3ed429210f68942e69b7e8bea` |
| Main texture | `-4727852512917511309`, `caustic_noise_007_grscl`; 512×512 ETC2 RGBA8, ten mips; original stream SHA-256 `da1a9435f0c7c6e376abba56e4363426cc5a50f11629ee06051f4f8008ea250f` |

The exact keyword set is `_USE_CAMERA_OFFSET_OFF`, `_USE_SMOOTHSTEP_OFF`,
`_USE_OFF`, `_USE_CLAMP_OFF`, and `_MIN_BLENDING`. Saved properties from unused
variants are not substituted into the selected program.

## Conversion contract

`scripts/prepare_erlang_avatar_material.py` reuses the existing source-expression
adapter's parsing, vector type and API substitutions. It supplies a separate
actor interface: already skinned source-space position, normal, vertex color,
tangent (including its original `w` sign), and source matrices. It does not call
the particle adapter's coordinate reflection, unit conversion, UV routing or
tint logic. `_Invert` remains an integer read and fractional values are refused.

Every assignment in both original shader bodies is compared with the generated
program after normalizing only those documented interface substitutions. This
does not establish GPU precision equivalence: the generated Metal interface
uses 32-bit floats, while original GLES precision qualifiers are retained in
the private source evidence.

The original program samples XY and ZY projections. Its weights include all
three absolute normal components in the denominator, but it does not add a
third texture projection. With the current nonnegative source texture values
and multiplier, its final alpha is `clamp(noise * C.a * C.a + 1)`, hence 1.
`_Transparent` scales the colored contribution; the exporter adds no general
opacity fade. Original raster values are SrcAlpha/OneMinusSrcAlpha, no culling,
no depth write, depth test 4, and transparent queue 3000.

Both compressed streams remain unchanged. Every mip is decoded separately with
`flip=False`; no mip is regenerated, resampled, or silently removed. The 2×2 and
1×1 ETC2 tail levels each still consume a complete 16-byte block. The manifest
records the original sampler and numeric texture color-space properties.
Binding these to an actual project color space, texture format and scene
projection remains runtime integration work.

## Local evidence

The first actual export completed with UnityPy 1.25.4. Its generated Metal file
is 6,937 bytes, SHA-256
`42922e9efb16ff890e4c84190303b5f0168a4d38674c0f44d278dbe5354b7edd`.
The private manifest is 15,616 bytes, SHA-256
`2dd43b60666d96d7c27ecba427aae8afcb37ea0068962862c8716526a47cf349`.

Six new focused checks passed in 0.028 seconds: all original arithmetic and
source vertex inputs; all eleven mip levels; the explicit white default,
raster and non-runtime status; rejection of a changed shader; rejection of
missing/extra/invalid mip data; and refusal to truncate a fractional integer
uniform. No old successful application, native, or UI tests were rerun.

```sh
python3 scripts/prepare_erlang_avatar_material.py \
  --source-bundles /private/source-bundles \
  --output /private/new-avatar-source-candidate
python3 scripts/test_erlang_avatar_material.py \
  --candidate /private/new-avatar-source-candidate
```

The export contains `SF3D15AvatarNormal.metal` and explicit compiler commands for
a Mac with an already installed Apple Metal compiler:

```sh
xcrun --sdk iphoneos metal -c SF3D15AvatarNormal.metal -o AvatarNormal.air
xcrun --sdk iphoneos metallib AvatarNormal.air -o AvatarNormal.metallib
```

The current Linux environment has no `xcrun`; these commands were not executed.
Their absence is unavailable, not a passing shader result. Actual Apple
compilation, additional-pass rendering on the real actor/head geometry, the
original accepted `a167` event lifecycle, and runtime resource binding remain
separate gates.
