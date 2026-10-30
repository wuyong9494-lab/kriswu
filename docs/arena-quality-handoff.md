> 最新范围更新（2026-10-30）：用户已明确将一个游侠样板扩大为三个完整英雄与主流程。下方旧记录的“不扩角色”仅描述当时范围，不再作为本轮限制。仍保留现有项目，不切换引擎、不合并 main、不发布 TestFlight、不购买。先读 [复用评估](arena-reuse-assessment.md) 与 [Build463 检查及接续](arena-quality-review-463.md)。当前已核实的远程基线是 `04d6cc0`；本提交包含三英雄流程/验证增量，尚待自己的唯一 CI 结果。旧客户端专项查到的项目没有完整可复用游戏客户端源码，不要把协议客户端或 APK 当源码。

# Quality sample handoff — 2026-10-30

Branch: `codex/arena-quality-sample`. Verified remote base: `d0c041d2f912a0e67b4b0da8f320c0b3c1685435`. No rebuild from main, release, TestFlight upload, or new characters/maps. Old local worktree HEAD is `0ab9e94` with API-published changes left uncommitted; do not commit that entire dirty tree. This continuation fetched touched files from the exact remote base.

## Independently checked

- Build461 [application run](https://github.com/wuyong9494-lab/kriswu/actions/runs/41016656676): Linux/macOS core and device build passed; 44 simulator tests produced four assertion failures in two tests. Three were grass bounds (-0.5317465 / 0.5072382 / 0.52148885 against +/-0.5), one expected the deliberately removed normal-bolt floor projection. Release/TestFlight skipped.
- Build461 [sample run](https://github.com/wuyong9494-lab/kriswu/actions/runs/41016656745): simulator build passed; menu validator rejected white map screenshot. Artifact12960386178 downloaded and both PNGs actually viewed. Hero/body/buttons visible; map entirely blank, JSON408x683.6667 remains portrait. Combat screenshots and both recordings skipped. Do not claim d0c041d visual acceptance.
- Build460 artifact12959816135 traversal software-decodes604 frames, span24.94s. Actual packet PTS collisions at870/600=1.45s and7733/600=12.888333s. Zero-based decoded pairs20/21 and291/292. Different packet offsets and DTS prove the collisions exist in the original stream, not only ffprobe's best-effort timestamp/report. Original file unmodified. Encoder/source-clock cause unresolved; 1/600 timebase alone does not prove quantization caused it. [Detailed audit](evidence/build460-timing-audit.json) includes video SHA256 and nearby frames/packets. Viewed both frames of the later pair and the460 combat still; no full real-time playback/audio or device-FPS claim.

## Changes prepared in this continuation

- Move outer leaf centres0.32→0.285, retaining widened blade profile, heights, normals,792 triangles/tile and shared material. Independent coordinate calculation bounds X[-0.497282,0.474362], Z[-0.457403,0.487689], Y[0,0.64]. Existing Swift bound assertions unchanged; iOS validation pending.
- Normal bolts explicitly require no floor projection; super/hyper retain exact-radius and team-shape checks. Color, no-particle and no-additive-light checks remain for every strength.
- Menu readiness requires landscape bounds. In CI, capture checks the existing screenshot validator and retries up to three times, preserving every rejected PNG under rejected-frames; persistent failure still fails. Standalone callers without that validator retain external validation requirements. This is a recovery attempt, not proof the blank-screen cause is fixed.
- Video audit saves actual frame and packet timestamp collision context, stream timebase and file SHA256. Duplicate timing is explicitly needs-review, separate from successful software decoding. No timestamp repair/resampling.
-21 Python tests pass locally, including portrait rejection, blank recovery/persistent failure and packet-collision reporting. No local Swift/Xcode; cloud regression required.

## Reference availability and next work

Remote tree contains reference prose/URLs but no identifiable original battle screenshot or continuous source video. Local official-0/1 PNGs were viewed and show event/reward menus, not battle; they do not validate grass/combat design. Missing: the two user battle reference images as repository assets, locally saved original battle video with provenance and timecoded observations, same-build physical-device capture/performance data. Do not claim those were watched this turn.

First collect the next unique build's grass bounds/tests and landscape map screenshot; then inspect actual Twin Gates combat and opening/traversal video. Compare grass continuity, cool wall sides and removal of generic decorative projectile rings only using their actual producing SHA. If timestamps recur, keep packet evidence and investigate recorder/source clocks; do not retime the output. Preserve fixed movement route and combat rules. Character/skill visual acceptance, full motion/audio, box traversal and iPhone17 Pro Max long-run/60fps remain unverified.


## Build462 continuation (latest)

Application41017743379 passed;44 simulator tests/0 failures. Actual map screenshot recovered with landscape bounds720x243.6667. Full sample41017743617 failed only at traversal movie finalization (90s timeout, moov missing); opening fully decodes448 frames with zero duplicate PTS. Current stills viewed: generic decorative rings removed, grass remains clumpy, early white impact overlap unresolved. Original two user battle reference images were recovered and viewed this turn. Details, hashes and visual evidence: [Build462 review](arena-quality-review-462.md).

This commit changes wall-top surface detail and isolates the second recorder by restarting only its dedicated simulator; it also retains scene evidence/logs before finalization.25 Python tests pass locally. Next: inspect the unique automatic successor build and capture; confirm wall cap readability and traversal media. Do not claim recorder root cause solved, final visual acceptance, full real-time/audio review, or device60fps. No release/TestFlight.

