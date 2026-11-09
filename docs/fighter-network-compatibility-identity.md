# Verified fighter compatibility identity prerequisite

This additive slice supplies real SHA-256 inputs for
`DuelNetworkStartBarrier.Compatibility`. It is not wired to the lobby or barrier,
never calls `confirmLoaded`, constructs no `DuelSession` or simulation, and starts
no display clock or network traffic. Selection Started still does not mean combat
is loaded. GPU readiness, an exact configuration loader, start coordination and
physical two-device validation remain separate work.

## Rules/build identity

`scripts/build_fighter_network_rules.py` reads the **current working tree**, not
Git HEAD. Its source closure is deliberately conservative:

- Every `.swift` file recursively under `App`, `Sources/ShiftCore`, and `Shared`.
- The exact `project.yml` bytes, including target compilation settings.
- No widget-only source, tests, generated files, asset bytes, credentials, Git
  metadata, timestamps, absolute paths or arbitrary environment variables.

All main-app source is covered, so an unrelated duty-source edit also changes
compatibility. This is an acceptable false mismatch for the initial same-build
network slice. New Swift files, removed files, renames and dirty local edits are
included automatically. Required baseline sources detect partial checkouts.
Symlinked source files/directories, empty/oversized sources, unsafe paths and
oversized output fail the build rather than producing a partial identity.

The main `ShiftReminder` target alone has an always-running XcodeGen
`postBuildScripts` phase, with `basedOnDependencyAnalysis: false`. It writes
`FighterNetworkRules.json` directly into
`TARGET_BUILD_DIR/UNLOCALIZED_RESOURCES_FOLDER_PATH`, after resource copying and
before code signing. The manifest is not committed. Atomic output replacement
prevents partially written resources; unchanged output with the correct mode
keeps its mtime. A failed
script fails the build, even if a previous build output remains on disk.
The phase declares five scoped inputs: the generator script, `project.yml`, and
recursive `App`, `Sources/ShiftCore`, and `Shared` roots. Its only declared outputs
are the final JSON and `.FighterNetworkRules.json.tmp` beside it. The fixed scratch
path permits atomic replacement without random undeclared writes; it is removed
on success/failure, and a regular leftover from an interrupted build is replaced
on the next run. Symlinked scratch files are rejected. Builds targeting the same
product directory must be serialized, as with other Xcode build products. The
scratch output's absence after a successful atomic rename is expected; this phase
always runs rather than relying on output existence for incremental scheduling.
The nonsecret manifest is set to POSIX mode `0644` on the owned scratch file before
replacement, independent of umask. An existing identical `0600` output is rebuilt
to normalize its mode; no directory permissions are changed.
No script-sandbox or security setting is disabled. These keys follow the official
[XcodeGen build-script schema](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md#build-script).
The generator has only Python standard-library runtime dependencies and imports
no repository modules or packages. The hook runs Python with `-I -B -S` to exclude
user/PYTHONPATH/site startup hooks and bytecode-cache writes, and sets
`showEnvVars: false` so this phase does not print its environment. It reads no files outside the declared source
inputs except the declared previous output/scratch and Python's standard runtime.
No signing settings, widget/notification targets or release steps
change. Existing directory-based target source discovery includes the new service
and test extension.

The `--xcode-build` mode binds only these bounded, path-free build settings:
`TARGET_NAME`, `CONFIGURATION`, `PLATFORM_NAME`, `SDK_VERSION`, `SWIFT_VERSION`,
`XCODE_VERSION_ACTUAL`, `IPHONEOS_DEPLOYMENT_TARGET`, `SWIFT_OPTIMIZATION_LEVEL`,
`SWIFT_COMPILATION_MODE`, `ENABLE_TESTABILITY`, and
`SWIFT_ACTIVE_COMPILATION_CONDITIONS`. The target must be `ShiftReminder`, and the
first seven settings must be present. The standalone default is explicitly marked
`source-only`; the native reader rejects that mode, so an exploratory manifest
cannot be mistaken for an installed Xcode build identity.

The JSON schema has exactly `schemaVersion: 1`, `recipe:
"fighter-network-rules-v1"`, `build`, `files`, and `fingerprint`. Files contain
exactly `path`, `bytes`, and lowercase `sha256`, sorted by relative ASCII path.
The root fingerprint uses this canonical byte recipe:

1. UTF-8 recipe name followed by one LF.
2. Length-framed decimal build-setting count, then each key and value in sorted
   key order, each separately length framed.
3. Length-framed decimal file count, then each path, decimal byte length and
   lowercase SHA-256 in sorted path order, each separately length framed.
4. SHA-256 of the resulting bytes, rendered as 64 lowercase hexadecimal digits.

A field is framed as its decimal UTF-8 byte length, a colon, then the exact UTF-8
bytes. No JSON serialization order or floating-point formatting enters the root
recipe. Full source bytes, including whitespace/comments, enter each file digest.
The native reader checks bounded shape, supported recipe/build context, required
source coverage, safe/sorted/unique paths, sizes, digest syntax and recomputed
root digest. Python and Swift tests share an independent one-record golden.

This is **trusted build metadata**, not remote attestation. Source files are not
shipped, so the runtime cannot prove that a self-consistent manifest matches its
machine code. Trust comes from the local build phase and, for signed installations, the installed
signed bundle. Unsigned CI metadata is only self-consistent; this reader does not
validate a code signature.
An attacker able to replace/resign the app can also replace this manifest. Exact
SDK/configuration differences conservatively mismatch; compiler determinism,
custom-toolchain/command-line-override equivalence and cross-platform simulation
are not proven. No claim of executable/binary identity is made. Do not edit sources concurrently
with compilation: a post-build source manifest cannot retrospectively prove which
bytes an earlier compiler invocation read.

## Installed combat content identity

`DuelNetworkCompatibilityIdentity.verify(bundle:)` validates build metadata first,
then verifies the installed equipped combat resources. It returns the exact
validated `DuelWeaponCatalog`, immutable file receipts and a `Compatibility`.
It has no public memberwise initializer and no override for the production asset
pins. The explicit-directory seam still enforces all the same pins and never
falls back to another directory, a legacy fighter or a procedural substitute.

The current verified resource set is 62 files:

- Full pinned `SF3_DistinctFighters.json` bytes. This binds every schema/clock
  field, profile, role, clip, sampled motion track and combo link, including any
  additional JSON fields. Both character GLBs must match catalog size/hash pins
  and pass the existing skin/node/clip checks in `DuelWeaponAssets.character`.
- All seven source controls, verified with the existing non-injected
  `DuelSourceControlsView` loader. The receipt uses logical prefixed names for
  both supported prefixed and short-filename installations. A changed required
  control set fails closed until this recipe is updated.
- Full pinned source-effects and weapon-effects manifests plus all 38 and 11
  referenced resources respectively. Existing loaders additionally validate
  image/audio decoding, tracks/curves and material references.
- The palace combat stage, verified with `DuelStageAsset`'s byte-size/digest and
  decoded stage-node checks. Autumn lobby scenery is intentionally excluded.

The content recipe is `fighter-network-content-v1`, with the same framing,
an empty context dictionary, and records sorted by logical resource path.
Receipts contain each actual byte length and SHA-256, not just advertised profile
names or a catalog's model hash. Raw catalog/manifest bytes are intentional:
formatting changes cause a safe false mismatch. Installation-directory layout
and absolute paths do not affect the digest.

Reads are size bounded, reject symlinked/non-regular files, and verify every
observed file again before returning to catch ordinary replacement during the
check. The supplied directory is an installed trusted resource root, not an
adversarial mutable filesystem. Total verified resource bytes are bounded to
256 MB; bytes are read transiently rather than retained in the result. Models
are released between characters. Effect loaders prepare decoders/audio players
and are shut down without emitting an effect or playing a sound.

Successful identity verification means these required bytes were available and
passed the current native CPU loaders at that time. It is **not** renderer/GPU
readiness, not proof of later asset availability, not loading of an agreed match
configuration, and not permission to acknowledge or start combat. A future
loader must keep the verified catalog/configuration consistent, load its own
renderer resources and only then call the existing barrier's `confirmLoaded`.
The current offline game's fallback behavior is unchanged.

## Verification and remaining limits

Executed in the Linux implementation workspace:

- Focused Python generator tests, including determinism, dirty edits, additions,
  removals, renames, full source coverage, Xcode context binding, excluded assets
  and secrets, missing/empty/oversized sources, symlinks, atomic regeneration, fixed scratch cleanup/recovery,
  scratch-symlink rejection, POSIX mode `0644` under restrictive umask/old output,
  and scoped hook declarations.
- Generator against the actual checkout, and the hook shell script with synthetic
  Xcode settings, including paths containing spaces.
- YAML parse showing the hook exists only on `ShiftReminder`, and a comparison
  confirming all prior project configuration is unchanged after removing it.
- `git diff --check`.

`Tests/SiteTests/DuelLifecycleTests+CompatibilityIdentity.swift` adds eight native
cases under the existing selected `DuelLifecycleTests` suite: manifest rejection,
source/build mutation, cross-language framing, full catalog/resource digest
sensitivity, explicit missing/corrupt/symlinked content, generated bundle resource
presence, and the complete installed private-resource path without starting a
clock. The last case skips only if the private catalog is absent; a present but
broken pack must fail. Synthetic records are not claimed to be real assets.

**Swift and Xcode are absent here. Native tests, generated Xcode build-phase
placement, user-script sandbox enforcement, code signing and the successful real
private-pack path have not run.**
The synthetic shell invocation is not an Xcode build and cannot establish that a
particular Xcode sandbox grants recursive directory reads or Python runtime
access. Required native follow-up (retain sandboxing):

```sh
xcodegen generate
xcodebuild test -scheme ShiftReminder -destination 'platform=iOS Simulator,name=<available simulator>' \
  -only-testing:SiteTests/DuelLifecycleTests
```

Run both a public-resource build (missing private resources must fail closed)
and an authorized staged-private-resource build (all 62 receipts must verify).
A successful CI run for an older commit says nothing about this local slice.
The fighter envelope job also runs the generator unit tests. No release or
signing change is part of this work.
