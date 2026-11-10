# Actual-resource native completion budget

The lobby/camera candidate is `8d6fc923a105110e3e54925f201b82d8958794e3`.
[Run 42746304926](https://github.com/wuyong9494-lab/kriswu/actions/runs/42746304926)
does not have a passing overall result.

## Measured results

- Attempt 1 completed all 253 actual-resource native cases with zero failures in
  1,005.905 seconds. Xcode printed `TEST EXECUTE SUCCEEDED`, but the encompassing
  step reached its 20-minute limit before successful process completion was
  established. The five actual-resource UI cases passed separately.
- Attempt 2's actual-resource native step again reached 20 minutes. Logs record
  233 completed passing cases and no assertion failure before the cutoff. The
  remaining cases were not accepted as complete.
- Attempt 2 passed the ordinary native job: 207 cases, including 12 existing
  skips, and all four ordinary UI cases. Core, envelope and unsigned device
  compilation checks also passed.
- Attempt 2 passed four actual-resource UI cases, but the source-weapon flow
  failed during the stationary-observation check after Sun's background return
  and explicit resume. That failure is separate from the native time budget;
  this change does not repair or dismiss it.

## Narrow correction

Increase only the actual-resource native stage's bounded timeout from 20 to
25 minutes. Simulator launch, the full test list and Xcode result finalization
share this budget. The enclosing job remains capped at 75 minutes. No test,
assertion, resource, gameplay value, UI timeout or command argument is removed
or changed; `xcodebuild` must still exit successfully through `pipefail`.

A structural comparison of the workflow YAML before and after this edit
confirms that the timeout value is its only behavioral change. Fresh native
execution is required before this correction can be accepted. The separate
source-control UI failure also remains an acceptance blocker.
