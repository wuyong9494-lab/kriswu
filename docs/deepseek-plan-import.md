# DeepSeek plan-image import (isolated first pass)

## Device workflow

Open 发数传计划 → DeepSeek 联网识图（可选）. Save your own DeepSeek
API Key in the device Keychain, then select one approved, complete table image.
The confirmation names the recipient and the image that will be sent; choose
改用本机识别 or cancel if the image is not approved for external processing.
No existing camera, local OCR, spreadsheet, clipboard, or notification action
sends a request through this feature.

The selected photo is re-encoded without the original metadata and sent inline
to the fixed HTTPS DeepSeek endpoint, with no redirects and no automatic retry.
The result is a recognized-text table, not a cropped original. No messages are
sent automatically. Existing grouping, review gates, and manual sharing apply.
Failure and cancellation leave the prior plan intact. The reader requires the
image to show the complete header and rows; it rejects ambiguous or partial
responses instead of filling missing data. A self-consistent model response
can still contain silent omissions or misreads; this is not proof of accuracy.

## Verification

- Linux: `swift test --filter 'DeepSeekPlanReaderTests|PassPlan'`.
  DeepSeek tests use a stub transport with synthetic inputs; no key or live API
  request is needed. Swift compiler parsing of the changed UIKit/SwiftUI files
  does not substitute for an iOS build.
- On an iPhone/iPad development build, use an approved non-sensitive fixture for
  each of: clear photo, webpage screenshot, Excel screenshot. Compare every row,
  date/time including seconds, identifier, station and warning with a known
  answer, then check the rendered preview. Test cancel, local fallback, invalid
  key, timeout/offline, superseded plan, and actual Excel file import. Save the
  key only on the device; never place it in CI, a fixture, or the repository.
