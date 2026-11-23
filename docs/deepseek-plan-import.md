# DeepSeek plan-image import (isolated first pass)

## Device workflow

Open 发数传计划 and save your own DeepSeek API Key in the device
Keychain. Shoot or select one approved image showing the complete table.
Only confirm if the selected image is approved for external processing.
DeepSeek is the only image reader offered on this page. If offline or unable
to share the image, directly import Excel or paste the structured table instead.
Spreadsheet, clipboard and notification actions do not send an image.

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
  answer, then check the rendered preview. Test cancel, missing key, multiple captured pages, invalid
  key, timeout/offline, superseded plan, and actual Excel file import. Save the
  key only on the device; never place it in CI, a fixture, or the repository.

## Local station rules

The 运营商对照表 supports complete station names in addition to
legacy prefixes. In pasted rules, for example, `甲：甲站、=乙光-北区01`
adds an exact station alias as well as the prefix. A unique complete name
wins over a prefix; conflicting owners stay unassigned. Near spellings are
only suggestions; the text, satellite identifiers, and time fields are not
rewritten. When manually assigning an unrecognized DeepSeek station, only its
complete name is learned. All matching uses local rules after recognition:
the rule table and recipient names are not sent in the DeepSeek request.
