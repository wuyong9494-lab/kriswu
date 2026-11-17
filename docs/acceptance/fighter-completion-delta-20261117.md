# D13 victory Morph: isolated completion delta

This is one authenticated resource addition. It does not rebuild or replace the existing encrypted package, authorize a workflow, install a game build, or establish native/device acceptance.

## Fixed identities

| Item | Bytes | SHA-256 |
|---|---:|---|
| Existing `resource-manifest.json` | 147,492 | `5341f635b644b3bb498662ddbd554aa7d73b172af92f85fe7f2e248264b6dd43` |
| Existing `SF3_FighterRelease.json` | 35,645 | `527e0195b7911e5b532aec92c37057f36a633952768670518565bde65605cbd3` |
| Added `SF3_H17_SerpentMorph.json` | 12,479 | `f2b3ab352b6a433fa7910fdc4c04508f9d1498c1933e4315269d2b77d10063bd` |
| Private canonical clear ZIP | 12,627 | `06d8a5d6e176e9777f0932718dc484ccd12a88805c64746541e9016e7cff10b8` |
| `public/completion-delta.cms` | 13,253 | `8bd33a39113cb649aac05530c48c0a29bdf21a75d6e742e6196757fe36fdd630` |
| `public/completion-delta-manifest.json` | 1,361 | `aac614c1d1e2e4c2faf09bb6fa0a98f6577dc7355fc0d3d41ed870cd784657be` |
| `public/completion-compiled-inventory.json` | 75,826 | `4c8984617203134c7bf3328f3a6e41520bb823063f94d37013cae11839bc97a1` |

The original 47 CMS parts and original 540-file compiled inventory remain unchanged. The derived inventory is exactly those 540 records plus the one D13 Morph record, for 541 expected compiled files. The 470-entry original private input becomes a 471-entry logical union. The existing Morph mask is reused and is not included again.

The public recipient certificate remains externally pinned at 1,529 bytes, SHA-256 `9d8d67155afdd3068e8593b62ea674c1592350f2de6bde89e64450a7613dd656`, SPKI SHA-256 `3cde0f94a6ee92c436a6419e2a944db9b2e8065aa183955fd1482581d637ba91`.

## Scripts

The repository contains three new independent scripts:

- `scripts/prepare_fighter_completion_delta.py`: verifies the fixed base manifest, fixed D13 file, and recipient certificate. It seals only the canonical one-entry ZIP using AES-256-GCM with RSA-OAEP-SHA256/MGF1-SHA256. Certificate bytes are authenticated and copied into a private temporary snapshot before OpenSSL uses them. No private key is read.
- `scripts/stage_fighter_completion_delta.py`: authenticates fixed source-code pins for the public manifest, ciphertext, clear ZIP, compiled inventory, recipient certificate/SPKI, release and exact addition. Its CLI has no hash override. A caller supplies an already unwrapped protected recipient key and an already staged 540-file base. It verifies that base, authenticates/decrypts the one small delta, and produces a separate `overlay/SF3_H17_SerpentMorph.json`, merged inventory, and private stage receipt. It does not modify the base directory.
- `scripts/test_fighter_completion_delta.py`: reproduces all 37 local checks using explicit existing inputs and a newly generated temporary test key. Missing input is an error, never a skipped pass. It has no embedded private resource bytes, fixed scratch path or production key input.

The old native helper gate has not been changed. These scripts do not unwrap a recipient key or retrieve secrets. A caller without an already available authorized protected key cannot complete real staging through them.

### Prepare reproduction

Run from the repository with a **new, nonexistent output directory outside the checkout**:

```bash
python scripts/prepare_fighter_completion_delta.py \
  --base-manifest /path/to/existing/public/resource-manifest.json \
  --morph /path/to/reviewed/SF3_H17_SerpentMorph.json \
  --recipient-certificate /path/to/existing/public/recipient-public.crt \
  --output /private/new-completion-delta
```

The clear ZIP and merged content identity reproduce byte for byte. CMS encryption intentionally uses randomness, so a new seal will have a different cipher SHA. It requires a separate external source-pin review before the production stage script can accept it. Rewriting an input manifest cannot authorize the new cipher. The four files in `.github/private/fighter-completion-20261117/` are the artifact authorized by the current stage constants; other cipher pins are rejected.

### Stage contract

No real-recipient stage command was executed in this preparation. Future authorized callers use:

```bash
python scripts/stage_fighter_completion_delta.py \
  --base-manifest /path/to/existing/public/resource-manifest.json \
  --base-directory /private/already-verified-540-file-base \
  --delta-directory .github/private/fighter-completion-20261117 \
  --recipient-certificate /path/to/existing/public/recipient-public.crt \
  --recipient-key /private/already-unwrapped-recipient.pem \
  --output /private/new-completion-overlay
```

The key must be a caller-owned regular file with no group/other permissions, and its public SPKI must match the independently fixed recipient. It is never copied into the output. The base directory must contain exactly the authenticated 540 flat resource files with matching bytes and SHA-256. No source file is removed or replaced. The output overlay contains one file; its installation into a caller's protected build staging area remains an explicit caller action. The 541-entry inventory is a build expectation, not proof of a successful compiled App.

## Validation actually performed

[`fighter-completion-delta-validation-20261117.json`](fighter-completion-delta-validation-20261117.json) records **37 passing local checks** from the portable repository script; `private/portable-local-regression.log` contains its successful execution summary. The initial scratch-script receipt is also preserved as `private/local-regression-report.json`. Checks include exact 540+1 metadata union, deterministic ZIP encoding, fixed outer pins, altered clear/cipher/inventory rejection, duplicate JSON and ZIP entries, extra files, traversal, absolute/nested/backslash paths, links, unsupported compression, file/total bounds, trailing bytes, output overwrite refusal, recipient-key ownership/permissions/SPKI checks, and base-file hash/stat/closure mutations.

Reproduce them from the repository. The report path must be new and outside the checkout; its parent directory must already exist:

```bash
python scripts/test_fighter_completion_delta.py \
  --base-manifest /path/to/existing/public/resource-manifest.json \
  --delta-directory .github/private/fighter-completion-20261117 \
  --morph /path/to/reviewed/SF3_H17_SerpentMorph.json \
  --report /private/new-local-regression-report.json
```

The equivalent path-only environment variables are `FIGHTER_COMPLETION_BASE_MANIFEST`, `FIGHTER_COMPLETION_DELTA_DIRECTORY`, `FIGHTER_COMPLETION_MORPH`, and `FIGHTER_COMPLETION_REPORT`. CLI flags take precedence. The existing private Morph input is required to reproduce the clear package and exercise a temporary recipient; the encrypted public directory cannot supply plaintext without an authorized real key. The test script does not request or use that real key. It never regenerates the production CMS object.

An isolated temporary test certificate/key exercised authenticated encryption and decryption, including GCM-tag failure and wrong clear-pin rejection. The test key was destroyed. Small synthetic 540-file fixtures checked base-closure helpers without rehashing or rebuilding the large production resource package. These fixtures were not passed off as the production base.

The real 13,253-byte delta has been checked for fixed ciphertext identity and public CMS algorithm/recipient structure. **The real protected recipient private key was not read; real-recipient decryption and production staging have not been verified.** No real `stage-receipt-private.json` has been produced. No workflow, upload, signing, native test, TestFlight operation, dual-device acceptance or iPhone 17 Pro Max performance claim is implied.

## Output boundary

Only `public/` contains the sealed delta and public integrity metadata. `private/` contains the clear ZIP, a public-certificate snapshot, preparation receipt and local regression report. Keep the private directory out of any publication or application bundle. The plaintext addition is already available in the separately reviewed D13 candidate directory; no original model, texture, audio, private key or unrelated resource was added to this delta.
