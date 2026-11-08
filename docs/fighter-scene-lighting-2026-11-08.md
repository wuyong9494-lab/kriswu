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
inspect the roof color and repeated scene instances.

In [run 42471549711](https://github.com/wuyong9494-lab/kriswu/actions/runs/42471549711),
the standard native group passed 25 unit tests and two UI tests at commit
`c6b54e83236fa54d3070e07f2574a78b22d15697`. The new source-color pixel test
passed in 1.351 seconds. It checks the intended modulation against an independent
ordinary-material reference, repeated instances, explicit and missing white
colors, the unchanged default/nonmatching path, BLEND coverage and node opacity.
The actual-asset group also passed: 43 native tests and two UI tests, zero
failures and no skipped real-asset tests. This includes the 1,985 actual roof
colors and a second execution of the source-color pixel test (1.327 seconds).
The actual-asset unit tests took 448.283 seconds and the UI tests took 214.161
seconds, within the unchanged 15- and 10-minute test-step budgets. All five
workflow jobs completed successfully.

The private evidence artifact `13614017171` is 87,497,142 bytes, SHA-256
`249cc9e79f9a70b203053d7ac4355e2d0e2b0522da83dfed9355b285bc13d3ab`.
Its archive hash and evidence-envelope authentication passed. All 37 native
PNGs and 14 text attachments were retained with their originating test names.

Manual review compared the same idle camera with the accepted neutral-fill
baseline, run 42469636762, and inspected the final touch-driven Sun practice,
Liu hold, reverse-direction hold and both original-rig lobby captures. Palace
paving, walls and roof detail are more legible while the neutral character
lighting is retained. The darkest overhangs and vegetation remain dark. This
confirms the bounded RGB correction in the native scene; it does not approve
final art quality or complete source-renderer parity. The two lobby captures
remain visually consistent; only the Liu pair is exactly pixel-identical.

This change does not establish complete source-renderer parity. Fog, MatCap,
animated effects, shadow-form lighting and original game color-space settings
still require separate evidence. The autumn lobby has no confirmed correction
in this change, and physical-device performance is not established by simulator
captures.
