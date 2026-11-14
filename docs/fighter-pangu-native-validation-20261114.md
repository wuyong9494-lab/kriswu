# 盘古原生绑定验收 — 2026-11-14

本次已完成公开源码提交、真实 Mac 编译及 iOS 模拟器 XCTest：**49 通过、0 失败、0 跳过，每个预定方法恰好执行一次**。这关闭了上一批资源绑定改动的“尚未执行原生验证”缺口。盘古专属原版资源与真机验收仍未完成。

## 源码与运行

- [公开源码提交 `567bbbc`](https://github.com/wuyong9494-lab/kriswu/commit/567bbbcf1e07f33445d83114c6323cda50481634)：完整 tree 与已核查的本地 `ea383be` 相同，为 `5a7b67f0305cda2af6011c37f27ebe42db1d9160`。
- [实际验收提交 `4751a05`](https://github.com/wuyong9494-lab/kriswu/commit/4751a05bbc09f0f15783ede006d25319eabbaefa)：只增加/调整验收配置；七个应用、核心、测试与构建输入 tree/blob 固定值均与已审源码相同。
- [成功运行 #43568518933](https://github.com/wuyong9494-lab/kriswu/actions/runs/43568518933)：`attempt 1`，完成于 `2026-11-14 07:05:57 UTC`。
- 完整的逐方法结果、源码映射及证据摘要见 [验收 JSON](acceptance/fighter-pangu-native-validation-20261114.json)。本记录之后的文档提交不改变已验收的应用源码。

## 实际执行结果

| 范围 | 通过数 | 验证内容 |
| --- | ---: | --- |
| `DuelFighterAssetReleaseLoaderTests` | 12 | release pin、清单大小/哈希及显式资源绑定校验 |
| `DuelFighterCharacterContainerTests` | 10 | 自包含 GLB 容器及不受支持/外部资源的拒绝路径 |
| `DuelPanguSourceAudioBindingTests` | 13 | 阶段/接触/生成与强化标记的音频 Cue 匹配、去重及生命周期 |
| `DuelPanguSourceTrailBindingTests` | 11 | v2 武器轨迹、骨骼/材质绑定、相位窗口与重复姿态更新 |
| 指定既有资源回归 | 3 | 已安装内容的联网身份、原对象保持与释放、恢复动作的原始采样 |
| **合计** | **49** | **0 失败、0 跳过、0 缺失、0 重复方法** |

三个真实既有资源方法为：

- `DuelLifecycleTests/testNetworkIdentityVerifiesCompleteInstalledPrivateContentWithoutStartingClock`
- `DuelLifecycleTests/testVerifiedPreparationRetainsAllOriginalObjectsAndReleasesPayloadOnce`
- `DuelWeaponAssetTests/testEquippedRecoveryBlendsToIdleWithoutChangingSourceSample`

使用 **Xcode 26.6（17F113）/ Apple Swift 6.3.3 / iOS 26.5 SDK**，在 **iPhone 17 Pro Max、iOS 26.5 模拟器**运行。一次无签名 Debug `build-for-testing` 耗时 345.456 秒；一次 `test-without-building` 调用耗时 93.455 秒，其中 XCTest 结果时间跨度为 63.863 秒。既有 **73 个资源**分别在 staging 与编译后 App 中通过字节数和 SHA256 校验。

工作流只选择本次 49 个具体方法。summary 计数和 XCTest 方法树必须同时通过；成功退出但结果缺失、漏跑、重复或跳过均不能通过。其他旧工作流的任务被提交消息条件跳过，未重复执行旧的重型验收。

## 启动问题及处理

最初的新分支运行 [#43568110283](https://github.com/wuyong9494-lab/kriswu/actions/runs/43568110283) 被现有私有资源环境的分支规则拦截，未分配执行机、未执行任何 job step，也没有编译或测试。随后将同一批已核查源码 fast-forward 到环境原本允许的 `codex/fighter-visual-acceptance-20261113-1200`，保留分支限制与必需审核，并完成本次审核后启动上述成功运行。

源码审阅分支 `codex/fighter-pangu-native-20261114` 与验收分支同步。没有增加环境允许范围，也没有绕过环境审核。

## 证据核对

GitHub artifact `14104070475`（922,746 字节）的 ZIP SHA256 为 `985f149a7db8522e1f7f922cc293f2c9c3751b07dd0ba08ce5b743d658bd96a3`。下载后校验 ZIP 摘要、三份密文的校验文件和认证加密 MAC，并核对解密结果中的 49 个具体方法及 73 个编译资源回执；全部一致。公开记录保留结果和摘要，原版资源、解密密钥及私有日志均未提交。

运行结束后，模拟器、staged 明文资源、App 产物和 raw xcresult 均完成清理；证据封装、上传、清理和最终报告步骤全部通过。加密 CI artifact 的保留期限为 2026-11-17，逐方法摘要与源版本映射由本记录持久保留。

## 仍然不能据此声称的结果

- 46 项新测试使用合成 fixture；另 3 项使用已有旧资源包。它们没有提供或启用盘古专属原版模型、动作、特效、音频。
- 原版画面、动作编排、音频效果的逐项一致性尚未验收。
- 正式版数值的来源状态保持不变：38 项已核实参考事实，14 项仍缺充分证据；本次没有用测试结果替代原版来源。
- 这是真实执行的 iOS **模拟器**验收，物理 iPhone 验收与稳定 60 fps 尚未完成；本次没有签名或上传 TestFlight/App Store 包。
