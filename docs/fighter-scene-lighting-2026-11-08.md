# Source scene color corrections

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

## Autumn lobby follow-up

The exact existing autumn export (11,164,484 bytes, SHA-256
`616d5cb125f49c6b378cf280c90cf10e927b5b71aa461ecb34d7cdaad08c62c1`)
has now been traced through its source hierarchy, mesh channels, material
references and matching compiled shader variants. All 96 exported renderers
and their main/baked texture associations were checked. Decoded source texture
pixels match the embedded PNG pixels; this establishes asset identity, not
equivalent GPU color management.

Five material names (`ALFA`, `BG`, `ALFA_BG`, `Base_mat`, `Leavs_mat`) cover
82 renderers and use the same static RGB formula described above. Their exact
empty-keyword and `USE_FOG` compiled variants have identical relevant program
bytes. `Base_mat` binds a MatCap texture but does not enable its MatCap keyword.
The independent autumn allowlist enables the existing compatibility path only
after the original size/hash gate succeeds.

The remaining 14 renderers use `Matcup_mat` with `USE_MATCAP_LOCAL`. That variant
adds a texture- and alpha-dependent MatCap term, so it is excluded from this
bounded correction. Shader object identity alone would not justify treating
all six materials alike. Fog, shadow-form transitions and omitted dynamic
effects are not restored by this change.

Only two autumn primitives contain source colors: `Leaves_01` (196 vertices)
and `Leaves_002` (214 vertices). Their source UNorm8 colors were exported as
FLOAT `[255,255,255,255]`; the verified path normalizes RGB and preserves
independent texture coverage. The other eligible meshes receive identity
white. The distant tree imagery belongs to the panorama atlas and is distinct
from these two explicit leaf meshes. Uniform grey lightmaps on `BG`, `ALFA_BG`
and `Leavs_mat` retain the loader's channel-zero optimization; the nonuniform
lightmap retains UV1.

The existing real-lobby test now checks every material count, retained baked
map and selected gain marker, plus the two actual leaf color arrays and two
background arrays. Its safe Float4 inspection also replaces the palace roof
test's unchecked buffer reads. It reuses existing scene instances and adds no
large asset loads. Lobby character fill changes from blue at intensity 240 to
neutral white at 180, consistent with the accepted battle fill.

The follow-up passed all five jobs at commit
`ed048cb3a58e6fa203e60a17fe2fa8f139084eb3` in
[run 42479153124](https://github.com/wuyong9494-lab/kriswu/actions/runs/42479153124).
The actual-asset group passed 43 unit tests and two UI tests, with no failures
or skips. The augmented autumn test passed in 26.030 seconds, the palace/roof
test in 30.667 seconds and the shared source-color pixel test in 0.900 seconds.
The standard native group passed 25 unit tests and two UI tests; its pixel
test took 2.995 seconds. No source asset or encrypted chunk changed.

Manual comparison of both original-rig lobby captures against run 42471549711
confirms reduced blue/cyan cast on hair, armor and boots, with warmer skin and
more legible rail panels, fallen leaves and distant background. The scene
retains its dark atmosphere. Warm shoulder/upper-arm highlights remain very
bright, and broad floor/column regions remain dark; final art quality is still
open. Counts of encoded channel values at 255 are not a linear-light clipping
measurement. The corresponding battle-idle captures are exactly equal across
all 946,440 decoded RGBA pixels, consistent with the lobby-only lighting change.

The authenticated private artifact is `13617546740`, 485,392,397 bytes,
SHA-256 `8fd1b03bf8f499b7f2ce98b9778e6619fc545e31ac6d4e86b6bab1ef94a925b9`.
Its 40 native PNGs, 14 text attachments and recorded UI evidence are retained
privately. This acceptance establishes the five-material static RGB correction
and inspected scene appearance; full source rendering and physical-device
performance remain separate open items.
