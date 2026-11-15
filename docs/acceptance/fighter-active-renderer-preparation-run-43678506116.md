# Active renderer preparation 实际失败：43678506116

**原生实际 0 PASS / 1 FAIL / 0 SKIP；条件 UI 被阻塞，实际 0、计数 `null`。** 真实自动 prepare 和原 readiness 链成立，但首次完整离屏图仍是不透明纯黑；本次没有证明 World 候选有效。

## 身份与执行

[运行 43678506116](https://github.com/wuyong9494-lab/kriswu/actions/runs/43678506116) / [job 132703815527](https://github.com/wuyong9494-lab/kriswu/actions/runs/43678506116/job/132703815527)，attempt **1**，最终 `completed/failure`。执行源 [`8b33cb0a6bb95e108003847f4d35e22143a40ca5`](https://github.com/wuyong9494-lab/kriswu/commit/8b33cb0a6bb95e108003847f4d35e22143a40ca5)，tree `21abc3952809a02206f9bd2237e15ee2f4ab6a6d`，基线 `3ac0d950948cede934ff52b45664b1225261a27d`。Xcode **26.6 / 17F113**，设备为 **iOS 26.5 / 23F77 的 iPhone 17 Pro Max 模拟器**。

唯一方法：`SiteTests/DuelActiveRendererPreparationTests/testInstalledActiveRendererPreparationKeepsFirstFrameVisible`。

| 口径 | 实际值 |
|---|---:|
| XCTest 方法耗时 | **62.467 s**（原值 62.46705901622772） |
| `xcodebuild` 原生进程耗时 | **263.509 s**，exit **65** |
| 原生 CI 步骤区间 | UTC **05:05:54—05:11:14**，共 **320 s** |
| 原生进程上限 | **720 s**；本次未超时 |

上述时间均为 **2026-11-15 UTC**。构建 04:55:37—05:03:51 成功；job 05:11:39 结束。日志/结果导出和进程收尾不属于单个方法耗时。

## 唯一失败断言与原图

xcresult 只记录 **1 个失败断言**，位于[该执行源测试文件](https://github.com/wuyong9494-lab/kriswu/blob/8b33cb0a6bb95e108003847f4d35e22143a40ca5/Tests/SiteTests/DuelActiveRendererPreparationTests.swift)第 322 行：

> XCTAssertTrue failed - The first complete original Surface frame is empty, transparent or entirely black

stderr、方法日志和 phase receipt 的 **4 条失败记录都指向这个方法/断言**，不是 4 个失败方法。准备链断言之前的实际观测为：`target=surface.sceneRenderer`，request/completion/objectCount 各 **1**，prepare success、completion identity、World 和 session ready 均为 **true**；没有测试 hook，没有等待超时。等待真实 completion 的观测时长为 **2.42888025 s**。

原图 `active-preparation-first-full-frame` 为 **956×440、9,664 B**，全部 **420,640** 像素不透明且 RGB 全黑，透明与可见非黑像素均为 **0**。root 已逐图查看并确认 **FAILED_OPAQUE_BLACK**。PNG SHA-256：
`d057703632281c9f98c789fc1531a33b658d3301494a16a04a8fefcf69f89cd0`。

自动报告仍保留 `pixels=PENDING`，人工判断单列。游戏在 frame/tick 0 暂停；推进、display-link 回调、正常 drawable 提交均为 0；仅一次原 Surface 完整 capture，原 projector 始终保留，没有额外 renderer、scene 重绑或 snapshot。

## UI、日志与证据闭包

原生失败后，唯一旧失败 UI 的执行与导出步骤均 **skipped**，状态为 `blocked_by_native`，没有 UI 方法、进程、结果计数或附件；这不是 UI 通过。原生原图/report 导出、密封、上传及清理均成功。

producer 扫描 **05:06:38—05:11:10** 完整运行日志，**10,711,603 B / 8,103 条**；两项已知 drawable 诊断计数均为 **0**，完整源摘要 `56750bb111940408360e59e9cfc201c9a4a596fbbe91e59061af9b0df1684cdc`。消费者仅认证回执与封存尾段，**未独立重扫完整日志**；零已知诊断不能推翻已经观察到的黑图。

[工件 14147797568](https://github.com/wuyong9494-lab/kriswu/actions/runs/43678506116/artifacts/14147797568)：**3,620,623 B**，SHA-256 `8f0b74303cde4b0cdbc552447547149ed5d60e04262e5a104594f8584bb2ccbf`。root 唯一认证消费得到 **46 个 inventory 条目＋清单，共 47 文件**。原报告 **9,161 B**，SHA-256 `b9812b5b75453858f9ebb801091d5eeefc94d04cd325a0ab736dcf9ecde3adea`。

测试在像素断言前已真实清理 scene/surface/callback，活动时钟 **0→0**，关闭后 sourceMusicReady=false；不假定首个失败后的 XCTest 断言继续执行。最终 Actions `cleanupComplete=true / cleanupErrors=[]`；消费者没有事后重新检查 runner 文件系统。

## 验收边界与当前候选

**20 项 producer 离线检查和 12 项 consumer 合成检查均为各自首次通过，Apple 方法执行数均为 0**，不能加入本次 0/1/0 原生计数。旧成功 117、5、6 及历史诊断未重跑；373 文件 release `e5c0ccaeef85ce86c5b8fd4ee64524794d6556f5a561f4078362f6899bedf4e5` 未上传新版本，TestFlight 为 0。

截至 root 已核对的 `f52c293da885f24ebae7640055161380aba4a5f7`，World 仍包含此次候选，尚未恢复为其他实现。最小后续修复尚处只读分析，不能预填已修复。正常 drawable、实际 UI、音画、性能和真机均未验收；刘仍为双锤参考模型，非 D19 盘古。原媒体与密钥不公开。精确字段与来源摘要见[同名 JSON](fighter-active-renderer-preparation-run-43678506116.json)。
