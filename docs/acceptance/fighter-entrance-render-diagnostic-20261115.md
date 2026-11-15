# 真实入场固定步与渲染分层诊断

## 为什么需要这一次新诊断

[UI 运行 43652056280](https://github.com/wuyong9494-lab/kriswu/actions/runs/43652056280) 的被测代码为 `532fb03083da7053417b7ad7ba484a99e4c41c28`。唯一 UI 方法实际失败于 `ember-practice-ready`，没有点击暗影技能。完整运行区间的两类已知 drawable 错误均为零，但失败原图仍被巨大紫枝遮挡，人物与舞台不可见。详见[该次独立结果报告](fighter-shared-root-ui-remediation-run-43652056280.md)。

真实控件记录只说明武器与暗影一直为“暂不可施放”。XCTest 长时间未收到符合其标准的 idle 通知，不能据此认定主线程连续阻塞 60 秒，也不能归因于 GPU。当前证据没有直接记录源入场 tick、完整 App 固定步耗时或绘制提交耗时，不能据此修改入场门禁、补步上限或等待时限。

本次新增一个此前没有执行过的原生诊断方法，**生产 App、Core、资源包均保持 `532fb030…` 的字节不变**。不重跑历史 117、5、6 个成功方法，不重新执行这次已经明确失败但尚无新修复的 UI，不重复上传资源，不上传 TestFlight。

## 已确认的调用链与代码推算

`DuelWorldView.tick` 在主线程的显示回调中通过 `DuelClock.consume` 产生固定步，然后依次调用 `DuelSession.advance`。每步除 Core 逻辑外，还通过 `presentStep → didSimulateStep → consumeFeedback` 执行原始效果事件、骨骼采样、粒子历史与音效反馈。每次显示回调最后调用 `drawState`，准备角色、相机和效果 packets，再通过 MetalKit 的同步 draw 回调提交画面。

`DuelClock` 每回调最多接收 0.1 秒、产生 6 个固定步；多余墙钟时间记为丢弃补步。因此较慢的显示回调可以让 60 Hz 的源入场动画在墙钟上明显变长。这是一条可验证的机制解释，当前还没有足够计时证据将实际成本分配给某个函数或 GPU。

当前真实 catalog 摘要为 `fbd9ecbd9fb16de79c0240404e315af81d8cbbaa113b6042e6afc5ed7b1d0330`。按 `alignSourceStance`、`sampleSourceStance` 的原公式，孙从 3500 mm 经 birth 偏移 −920 mm，得到 firstIntro 原点 2580 mm。结合已观察位置序列的先后顺序，可得到以下范围；这不是直接采集的内部 tick：

| 观察位置 X | 符合顺序的 firstIntro tick 候选 |
|---|---|
| 2580 | 0…68 |
| 2460 | 97、98、107、108、109 |
| 2467 | 126…137 |
| 2469 | 146、147、148、176 |

最后有效 AX 样本与失败截图相差约 3.17 秒，二者并非同帧。入场 frame 82 的森林 marker 与失败截图相符，不能登记为玩家成功施放根枝技能。上述轨迹推算支持“入场仍在推进但尚未完成”，不提供精确单一 tick 或性能根因。

释放顺序由现有代码决定：

| 正常 `DuelSession.advance` 次数 | 实际状态与门禁 |
|---|---|
| 1 | birth 转 firstIntro，clip tick 0 |
| 392 | firstIntro tick 391，仍不可攻击 |
| 393 | 发布 firstIntro tick 392 的结束采样，进入 startIdle tick 0，仍有 intro owner |
| 394 | 步骤开头释放完成的 intro owner，普通武器和枝蔓囚笼可用 |

已有合成 `DuelTriadStanceTests` 覆盖这条顺序；没有重跑。新方法补的是本次真实 catalog、GLB、原效果和完整 App feedback 路径。

## 一个方法，六份冻结画面

新增文件为 [DuelEntranceRenderDiagnosticTests.swift](../../Tests/SiteTests/DuelEntranceRenderDiagnosticTests.swift)，选择器固定为：

```text
SiteTests/DuelEntranceRenderDiagnosticTests/testInstalledEntranceCompletesAndCapturesSceneEffectShadowIsolationOnce
```

文件 SHA-256：`313ab545a90a6b94f197f9d759f94de60bd33a295d1e414dbce5ffb33fa1251a`。

方法要求安装 release `h17-shared-root-floorfall-20261115-v2`，摘要 `e5c0ccaeef85ce86c5b8fd4ee64524794d6556f5a561f4078362f6899bedf4e5`。孙 profile 必须为 `sun_triad`，刘必须为 `liu_hammers`，两者都不能被误标为盘古；没有注入血量、能量、攻击、动画状态或 ready 标志。

通过正常 `DuelSession.advance` 恰好推进 394 次，逐项核验 392／393／394 的真实门禁。挂载仍遵守生产生命周期，但方法无 `await` 或异步步进；初末均要求实际 `clockCallbacks == 0`，最终要求 `simulationAdvanceCalls == 394`，避免框架意外推进的 tick 被补差隐藏。

| 原始附件标签 | 画面状态 |
|---|---|
| `entrance-frame-0-full` | 入场前的完整生产绘制 |
| `entrance-frame-164-full` | 源森林 marker 前一帧的完整绘制（game.frame 164 / clip tick 163） |
| `entrance-frame-394-full` | 入场解除后的完整绘制 |
| `entrance-frame-394-no-fx` | 同一冻结状态，只清空源效果 packets，保留原投影阴影 |
| `entrance-frame-394-scene-only` | 同一冻结状态，另暂时移除原投影阴影 owner |
| `entrance-frame-394-restored` | 恢复原投影阴影，再由正常 `drawState` 恢复全部效果 packets |

后面三份是明确标记的**测试内因果对照**，不改变生产质量档、资源、战斗逻辑或源采样，不作为删除原效果的修复。保留原 shadow 的强引用，后置 defer 先恢复绘制 owner，再执行世界和 session 清理。恢复前后必须保持同一游戏状态、动画 tick、相机变换、FOV 与 packet 数。

视口固定为 `956 × 440`。每次捕获核验 World 和 Surface bounds 均与离屏目标一致，防止 UIKit 的宿主窗口朝向产生不同投影比例。截图核验真实 PNG、尺寸、字节摘要；方法所属、设备所属与完整封存由独立工作流门禁验证。

## 计时与验收边界

JSON 附件 `entrance-render-diagnostic-report` 保留：真实 frame、源 clip/tick、入场门禁、双方位置和血量、活动效果、packet 数、场景几何/可见性、相机投影、drawable 尺寸、实际 MSAA、显示回调数、清理结果以及六图摘要。

计时分为构建 session/world、挂载、正常固定步（含 App feedback）、绘制准备与提交、同步截图读回。`captureFrame` 使用原渲染队列并等待读回，因此其时间不能记成正常每帧 CPU 或 GPU 时间。没有修改生产私有函数来拆分 Core 和 feedback 内部开销；固定步记录明确包含两者。

即使新原生方法实际通过，它只支持入场固定步、对照状态不变和捕获闭包。`pixels=PENDING`、`liveUIValidated=false`、`physicalDeviceValidated=false`、`performanceVerified=false` 必须保留。需要人工查看原图后再判断是哪一层遮挡；不能把无 FX 的对照图当成完整游戏画面通过，不能推算 iPhone 17 Pro Max 真机帧率。

Swift 6.0.3 前端语法解析通过，独立代码审阅已核调用顺序与上述门禁。新增工作流辅助脚本的 20 项离线检查首次执行为 20 通过、0 失败、0 跳过；独立证据读取器的 44 项新合成检查首次全部通过。这些检查未启动 Apple 构建、模拟器或游戏。**本文件是执行设计快照，尚无本次 Apple 执行结果。** 后续运行结果必须独立记录源提交、精确方法集合、结果计数、实际设备、原图与日志，不反向把本设计改写成已通过证据。
