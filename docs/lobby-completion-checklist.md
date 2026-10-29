# Lobby corrective batch after Build 424 review

Scope: lobby only, based on supplied moon-city tablet-screen reference. Source base: aee9c0b7df87a495ca902acf7077971f06e6d1a7.

Corrected in source:
- Header width is now 488pt on narrow layouts; all header buttons have 44pt height. Badge row starts below the header, with a reserved 240x44 region.
- Shared composition includes all interactive lobby controls, not only social/adventure/invite. Six phone/tablet sizes checked for bounds and pairwise intersections. Footer sizes are explicit; compact equipment clears the footer.
- Ranked selection moves into the mode sheet's existing 44pt segmented controls. The former 24pt header toggle is now a status label.
- Daily quest refresh label uses the same device-local calendar day as real quests, refreshed once a minute. No fake event timer or online count.
- Background asset corrected toward the reference's smooth moon, lower simpler skyline and thin deck. Source is an image-generation reconstruction, not the original game's extracted asset.
- Capture fixture accepts all 13 project heroes only under -demo. Readiness records window orientation separately from hero viewport orientation, including iPad.
- Added a lobby-only runtime review path: main phone all 13 heroes, small phone and iPad ranger, plus live 12s video. Missing devices or failed readiness are failures rather than skipped checks. Normal combat capture stays skipped. Latest user request explicitly asks full inspection without omissions.

Verification so far: local shared-coordinate reconstruction covers six sizes and reports no declared control intersections or out-of-bounds frames; YAML parses and Python capture script compiles. iOS whole-lobby bounds and real GPU shader tests are included but need the Mac runner. Bounds tests do not establish font/glyph appearance or actual touch behavior.

Still outstanding: exact original character/animation identity, exact original icon/font identity and actual visual/touch acceptance. Existing project models remain. No original animated reference-character asset has been obtained. No final-delivery marker; direct upload remains blocked for this partial batch. Do not label this batch fully identical or uploaded.
