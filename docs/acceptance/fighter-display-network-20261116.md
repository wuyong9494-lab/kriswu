# Display, lobby and nearby-input continuation

Base: `58b2639a065c6ee316da6bde1e87ce800dd28f37`, existing visual-acceptance branch.
The user's delivery scope now includes Xu Xiao from Dropbox `徐.fbx` in the
Ying Zheng costume, alongside the existing Sun, Liu/King of Serpents and
Wu Yong/Erlang work. Complete the whole batch before TestFlight delivery.

## Changes

- A single pixel budget controls both SceneKit and its separate Metal drawable.
  Mirror connect/disconnect notifications now update the child immediately even
  when the phone's bounds do not change. The explicit drawable size prevents
  native-pixel auto-resizing from undoing the 1920×1080 envelope. Camera bounds
  and touch coordinates stay in points. Leaving casting restores native scale
  and the existing antialiasing. The lobby uses the same display budget.
- Ordered input packets arriving within the existing two-tick late window can
  retain separate attacks on successive available ticks. Previously they all
  mapped to the current tick and later commands were rejected as conflicts.
  Original lateness, six-tick future bound, seven-message queue, sender/epoch
  checks, sequence deduplication, lease expiry and authoritative replay remain.
  No commands are merged or replayed twice. Pause clears retimed inputs too.
- The lobby authenticates the existing catalog, release and selected character
  but does not decode battle-only particles, summons, trails, morph textures or
  audio. A showroom store cannot provide a combat catalog or claim verified
  network preparation. Entering a match still constructs the full combat store
  with all of its existing resource checks. Idle sampling stops on background.

## Verification

- Linux Swift 6.0.3: 87 network, selection, replay, timing and display-budget
  tests passed, zero failures/skips. New burst checks cover distinct commands,
  release, duplicate/reordered packets, unchanged queue/window bounds and pause.
- 17 network source-identity generator tests passed.
- Changed native Swift files passed syntax parsing; this is not Apple SDK type
  checking. A dedicated workflow compiles App, widget and native tests once,
  then runs exactly 43 asset-free Metal, display lifecycle and network methods
  on the installed iPhone 17 Pro Max simulator. Its result is pending at commit.
- The added real-resource showroom test remains part of full private-asset
  acceptance; it is deliberately not counted in the asset-free native workflow.

Physical TV transport latency, on-device frame time, complete costume assembly
and all-character two-device matches are not certified by these tests. This
batch does not trigger TestFlight or replace any fighter with placeholder media.
