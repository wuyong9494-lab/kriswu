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
  on the installed iPhone 17 Pro Max simulator. All 43 passed in run 43806934587;
  see the exact commit and evidence below.
- The added real-resource showroom test remains part of full private-asset
  acceptance; it is deliberately not counted in the asset-free native workflow.

Physical TV transport latency, on-device frame time, complete costume assembly
and all-character two-device matches are not certified by these tests. This
batch does not trigger TestFlight or replace any fighter with placeholder media.


## iOS 原生验证结果

最终验证提交 `a950068fc7d1de119a50df6d9eaabaffa888f18f`，GitHub Actions [43806934587](https://github.com/wuyong9494-lab/kriswu/actions/runs/43806934587)，job `133099744351`。Xcode 26.6 编译 App、widget 与测试成功；新建 iPhone 17 Pro Max 模拟器，43 项投屏、生命周期、Metal drawable 和联机协调测试全部通过，失败 0、跳过 0。

前两次工作流分别在准备目录和测试命令参数阶段失败，未伪记为测试通过；修正 `mkdir(parents=True)` 和移除 Xcode 不接受的 `-test-iterations 1` 后获得上述完整结果。后续不重复已成功的这组重型工作流。

本次仍是模拟器上的无私有资产回归，不能代表电视无线链路延迟、真机稳定 60 fps、真实角色资源加载或双手机实测通过。大厅的真实资源专项测试待统一资源包完成后执行。没有上传 TestFlight。
