# Palace source color correction

The native palace captures were markedly darker than the character lighting.
The scene uses baked unlit materials, so changing the character's ambient or
key light cannot correct the environment. The previous rear-fill adjustment
addresses the cyan cast on the fighters separately.

## Source evidence

The locally retained source location shader (`Nekki/LocationShader`, source
object `4510184780266923675`) doubles normalized vertex RGB before multiplying
the main texture and the baked lightmap. The inspected static color path is:

`main texture RGB × (2 × normalized vertex RGB) × baked lightmap RGB`.

The lightmap property's label also mentions doubling, but the implementation
was checked independently: the multiplication occurs in the vertex-color
path. This is not evidence for RGBM decoding or a guessed exposure setting.

The existing palace export has 24 primitives. Only the `roof_back` primitive
has `COLOR_0` (1,985 vertices); all its exported FLOAT colors are
`[255, 255, 255, 255]`. The source mesh uses four UNorm8 components, while the
converter wrote the byte values as FLOAT without normalizing them. The other
23 primitives have no color attribute and use the source's default white.
The runtime previously ignored vertex colors and omitted the source gain.

## Bounded runtime change

The original encrypted GLB stays unchanged. `DuelStageAsset` verifies its
9,292,540-byte size and SHA-256 before explicitly enabling source location
color handling for the palace's ten verified material names. Other callers
of `GLTFModel` retain the existing default path.

For those materials, the loader divides the known byte-range FLOAT vertex RGB
by 255, uses white when the attribute is absent, and keeps vertex alpha at one.
The source gain is applied once while the material is constructed. The main
texture and material alpha continue to control coverage; cloning or entering
the scene again must not compound the gain. Non-finite, out-of-range or
malformed color arrays fail loading instead of producing invalid geometry.

This compatibility mode is specific to the verified scene export. General
glTF vertex colors are linear values in the zero-to-one range and must not be
reinterpreted as byte values. See the
[glTF material specification](https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html#materials)
and [SceneKit geometry sources](https://developer.apple.com/documentation/scenekit/scngeometry/init(sources:elements:)).

## Validation

Native checks use nonwhite vertex colors, midrange material/lightmap values
and nontrivial alpha to distinguish the intended result from missing gain,
double-applied color or changed coverage. The actual palace checks also
inspect the roof color and repeated scene instances. Full native results and
the before/after render review are pending.

This change does not establish complete source-renderer parity. Fog, MatCap,
animated effects, shadow-form lighting and original game color-space settings
still require separate evidence. The autumn lobby has no confirmed correction
in this change, and physical-device performance is not established by simulator
captures.
