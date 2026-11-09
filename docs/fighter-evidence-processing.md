# Bounded private fighter evidence processing

Run 42661107172 (`01f87e9`) reported all four real-resource UI tests passing in
989 seconds, but the UI process/recorder step exceeded its 18-minute budget.
The later eight-minute protection step also timed out. No complete encrypted
media artifact was produced; only diagnostic files were uploaded. These logs do
not identify whether ZIP compression, encryption, memory pressure or another
host delay dominated that protection timeout.

The resource-only UI step now allows 24 minutes, still requiring the actual
process and recorder to succeed. The overall 75-minute job cap and all test
assertions remain. This is bounded completion headroom, not proof of a hang fix.

Evidence processing changes:

- Archive already-compressed screenshots/video with ZIP_STORED and fixed-size
  copies. Bound file count, path depth/length and aggregate bytes; reject links
  and nonregular files. Detect observed file mutation and publish atomically.
- Seal evidence through fixed-size OpenSSL output chunks and incremental HMAC,
  instead of holding multiple whole-archive copies in Python memory. Model
  staging and the byte-oriented envelope API remain unchanged.
- Preserve FIGHTER1/evidence framing, AES-256-CBC, PBKDF2-SHA256/200000, the
  existing environment-key route and authentication of the complete envelope.
  OpenSSL's omitted salt length remains eight bytes for compatibility; see
  https://docs.openssl.org/3.6/man1/openssl-enc/#options . No new format is accepted.
- Publish the final .enc only after successful encryption/MAC completion.
  Failed protection excludes it from artifact upload. Hidden partial ciphertext
  and temporary plaintext are never upload candidates. The shell cleans its
  private temporary archive directory on normal failure and tested interruption.
  Hard-kill cleanup remains best-effort; there is no plaintext fallback.
- Keep the protection cap at eight minutes. Log only aggregate phase, byte-count
  and duration progress; disable redundant artifact recompression.

Seventeen synthetic envelope/archive tests pass, as do the four asset and four
distinct-resource synthetic tests. A 64 MiB Linux synthetic probe measured
roughly 2 MiB peak Python allocation for each stage; this does not establish
macOS/real-media throughput. Compatibility tests use the existing unseal path,
and failure/interruption tests require no published final ciphertext. No real
key or private asset was needed for these local checks.

Actual macOS resource validation, evidence completion and successful encrypted
artifact upload remain required before accepting this change operationally.
