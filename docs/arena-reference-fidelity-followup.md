# Reference fidelity follow-up

Based on 417 and fa5169e. User authorizes skipping capture and direct TestFlight after required checks.

Implemented: compact protruding lobby rail emblems, larger hero viewport, single readable map subtitle; bounded grass footprint with quarter-turn orientation; mirrored cover in expanded side lanes. Map IDs advance to expanded_v2 and peers negotiate revision 2, with historical-map fallback for older peers. Shared opaque blade geometry replaces spherical bushes.

Local verification: workflow YAML parses; independent reconstruction of seven expanded maps confirms traversable cells connected and terrain centrally symmetric. No local Swift/Xcode. Required device/core/simulator regressions remain in CI; this branch now runs arena-look tests but skips screenshot step, and auto-uploads only after all three required jobs succeed.

417 device and arena-look jobs were cancelled; its promotion was cancelled. No claim of 417 upload, exact original-game fidelity, or device performance acceptance. This batch is a further implementation step; character-model art, full lobby animation and actual phone visual comparison remain outstanding.
