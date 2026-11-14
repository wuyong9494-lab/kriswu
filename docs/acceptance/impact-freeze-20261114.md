# Frozen impact sampling candidate — 2026-11-14

Reference: fighter-video-reference-20261113.md separates short contact bursts from stalled recording frames. Do not extend hit-stop to match those stalls or invent SF3 timing from SF4 footage.

Prior lifecycle run 43441900352 completed successfully for 078972ac. This closes the previous test-only autorelease boundary correction, not physical-device performance acceptance.

This candidate skips interpolation/material writes when the visual tick is unchanged and no new contact arrived. New contacts invalidate the cache, including multiple contacts during hit-stop. Reset clears cache state. No source curves, texture, sound, contact, damage or hit-stop duration changes.

Added native regression checks 60 repeated frozen callbacks, a second same-tick contact, advancing time and round reset. Native execution remains pending. No FPS, visual parity or TestFlight publication claim.
