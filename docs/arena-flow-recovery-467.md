# Build 467 evidence and next recovery

Current remote branch head: `67ac1a5d82ab27c22655d13aed66c9ad311a4f0b`.

- iOS run [41038148581](https://github.com/wuyong9494-lab/kriswu/actions/runs/41038148581) passed device build, Linux/core checks, simulator regressions, and the restored original/legacy ranger comparisons. No TestFlight or release was performed.
- Sample run [41038148572](https://github.com/wuyong9494-lab/kriswu/actions/runs/41038148572): Ranger and Barbarian passed the control readiness/hittability checks and then failed the new unchanged `harbor-wall-cells` exclusion assertion. The final Ranger screenshot shows real battle, not VS. Its tree is still 113,842 characters. These tests never reached combat input and cannot be counted as complete flows.
- Menu capture failed before the first app launch: terminating a never-launched app timed out at 20 seconds, rebooted the new simulator, and launch then timed out at 150 seconds. This is the same fresh-device path already avoided by traversal recording; the menu caller still needed the fix.
- Mage remained queued without starting. After all actually running jobs finished and uploaded their evidence, the corrected successor replaces this unstarted obsolete job. It is not a Mage pass or a completed three-hero run; do not count it as either.
- The recording timing repair worked on Ranger: readiness was true before XCTest, actual test duration 66.262 seconds was separately recorded from 179.584 seconds of xcodebuild, and its original movie decoded. The collector correctly rejected its missing result JSON and failed UI test.

## Prepared next increment

- Set the SceneKit view's `accessibilityElements` and (iOS 17+) `automationElements` to empty arrays. UI automation has a separate list from assistive technology; flags alone did not suppress SceneKit's synthetic nodes. Keep the UI test assertion. The HUD, clock, sticks, entry/navigation, and result controls remain SwiftUI siblings. The existing mesh-exclusion assertion stays enabled.
- The original fixed 2-second east / 4-second north gesture ends at x=9.4–9.8 and crosses wall cell (9,18). Replace it with real joystick steps driven by read-only actual player position. Navigate through x=11, retry naturally after respawn, and retain the same 360-second result deadline. Save the actual movement trace and battle accessibility tree. Require the returned lobby to be hittable and the result screen to be dismissed. No movement, damage, charge, time or result is injected.
- Read-only feedback is gated to DEBUG + simulator + the existing explicit flow-capture mode. It is empty otherwise. The stable match clock carries it so a result hiding the control sticks does not race an in-flight query.
- Mark only the first menu launch on its explicitly fresh device. The second menu still terminates the running app normally. Preserve the failing command and bounded screenshot/device diagnostics if launch fails.

Local validation: 37 Python capture/evidence tests passed; workflow YAML, embedded Bash and whitespace checks passed. Swift/UI validation remains pending the next unique build. Existing art/audio assets and engine are unchanged.

Primary API rationale: [Apple WWDC23 — automation elements](https://developer.apple.com/videos/play/wwdc2023/10035/?time=779) and [automationElements](https://developer.apple.com/documentation/objectivec/nsobject-swift.class/automationelements).
