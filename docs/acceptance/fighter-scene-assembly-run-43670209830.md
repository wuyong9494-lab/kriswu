# 已执行：场景装配顺序候选失败，Run 43670209830

公开元数据记录时间：北京时间 **2026-11-15 11:18:47（UTC+08:00）**。根代理已唯一认证消费工件并逐图审查，本文于北京时间 **11:22:37** 补齐本地认证回执、精确断言和独立像素统计。配套[机器可读结果](fighter-scene-assembly-run-43670209830.json)保留各层证据的来源。

**新原生方法实际 0 PASS / 1 FAIL / 0 skipped；条件 UI 没有执行，状态为 `blocked_by_native`。** 延后唯一真实 Surface 装配的生产候选已在本次执行，其首次完整离屏图像没有通过非黑回归。原 PNG 经 producer 独立解析、根代理原样查看及再次只读像素复算，均确认为全部 420,640 个像素不透明纯黑；人工结论为 **FAILED_OPAQUE_BLACK**。自动 `pixels=PENDING` 原样保留，不能将该字段解释为图片尚无机器证据，也不能由导出／封存成功反推方法通过。

## 执行身份与源码范围

| 项目 | 实际值 |
|---|---|
| 执行提交 | [e35c51d7b0fbe4e7659892d1fcc0caf839479a65](https://github.com/wuyong9494-lab/kriswu/commit/e35c51d7b0fbe4e7659892d1fcc0caf839479a65) |
| 仓库／分支 | `wuyong9494-lab/kriswu`／`codex/fighter-visual-acceptance-20261113-1200` |
| 本入口保留源码基准 | `09f2f3c2ea1c8ad0283e920d442995a5faa1b254` |
| 生产变化 | 仅 `App/Views/DuelWorld.swift`；其他 App 与 Core 保持此前 `532fb030…` 实现，由新入口保留树摘要限制 |
| Run／job | [43670209830](https://github.com/wuyong9494-lab/kriswu/actions/runs/43670209830)／[132678367902](https://github.com/wuyong9494-lab/kriswu/actions/runs/43670209830/job/132678367902) |
| run number／attempt | 1／1；不是旧 run 的 rerun |
| 最终 run／job 状态 | `completed/failure`／`completed/failure` |
| 执行范围 | `installed-scene-assembly-followup-one` |
| 环境与工具 | 既有 `fighter-private-assets` 正常审批；已安装 Xcode 26.6（17F113）；SDK／模拟器 iOS 26.5；本次独占 iPhone 17 Pro Max 模拟器 |
| UI 范围 | 原失败方法只在新原生全部门禁通过后才可选择；本次没有达到条件 |

同一 SHA 注册 **13 个 runs**：本入口失败，另外 **12 个 completed/skipped**。旧预热池 Run 43670209582 也为 skipped，没有执行成功的旧重型测试。环境审批、构建成功、资源认证、方法执行、图片审阅是独立层级；任一层级的 completed 都不替代其实际结论。

本次唯一生产候选将真实 Surface／FrameDriver 的创建及首次 scene 关联延后到 Morph、源特效节点与初始姿态组装之后。保持同一原 projector、packet renderer、late geometry provider、提交回调与暂停状态；没有修改保护 Surface，没有增加辅助 renderer、scene 重绑、额外 prepare、移除 projector 或预热帧。正常挂载保留既有 SCNView 音乐场景异步准备；测试显式 prepare=0 不能解释为整个生命周期从未调用 prepare。源码审查未发现生命周期阻断，但本次实际失败，不能继续将它登记为已修复。

| 真实文件 | 完整 SHA-256 |
|---|---|
| [App/Views/DuelWorld.swift](https://github.com/wuyong9494-lab/kriswu/blob/e35c51d7b0fbe4e7659892d1fcc0caf839479a65/App/Views/DuelWorld.swift) | `2909c56d0c1e6e44f603e1ed68292bffa3133ef3d8a1a54b33bcb57230058b4f` |
| [Tests/SiteTests/DuelSceneAssemblyFollowupTests.swift](https://github.com/wuyong9494-lab/kriswu/blob/e35c51d7b0fbe4e7659892d1fcc0caf839479a65/Tests/SiteTests/DuelSceneAssemblyFollowupTests.swift) | `d6873b4b3b20493de4b14f89585d3feb96dad96a30aa0bb75fac0b381c8045c6` |
| [.github/scripts/fighter_scene_assembly_followup.py](https://github.com/wuyong9494-lab/kriswu/blob/e35c51d7b0fbe4e7659892d1fcc0caf839479a65/.github/scripts/fighter_scene_assembly_followup.py) | `eb62428656ea69553d91df1db2ed01b1512b660f89518151aadc61e640a0030e` |
| [.github/scripts/test_fighter_scene_assembly_followup.py](https://github.com/wuyong9494-lab/kriswu/blob/e35c51d7b0fbe4e7659892d1fcc0caf839479a65/.github/scripts/test_fighter_scene_assembly_followup.py) | `31df8861fee6897e1ce8dd439b05773e030f6be94d8a267d1bb5f35f9a2e160b` |
| [.github/workflows/fighter-scene-assembly-followup.yml](https://github.com/wuyong9494-lab/kriswu/blob/e35c51d7b0fbe4e7659892d1fcc0caf839479a65/.github/workflows/fighter-scene-assembly-followup.yml) | `571eaedda0bbbc5dfcda471d7362e5fa997df6ce66266b0009691d4b2ace835e` |

## 实际方法、条件 UI 与失败步骤

唯一原生 selector：

```text
SiteTests/DuelSceneAssemblyFollowupTests/testInstalledColdSceneAssemblyRendersFirstFullFrameWithoutRegistrationWorkarounds
```

公开的 xcresult 摘要为 `totalTestCount=1`、`passedTests=0`、`failedTests=1`、`skippedTests=0`、`result=Failed`。进程 `exitCode=65`、`selectedCount=1`、`iterations=1`，本次 selected-native 进程耗时 **255.991 秒**，没有到 720 秒外部 deadline。该耗时包含 xcodebuild 调用，不是测试方法本体或 GPU 帧耗时。认证后的实际方法耗时 **74.546 秒**，suite 于北京时间 **11:14:28.072—11:15:42.628** 执行。唯一断言在 `DuelSceneAssemblyFollowupTests.swift:347`：`XCTAssertGreaterThan` 检查可见非黑像素数大于 0，实际值为 **0**。消费者核对精确方法只执行一次、所属设备一致，缺失、意外与重复 selector 均为空。

条件 UI selector 保持旧失败源文件 SHA `d144949cad4b14eeef47ad7bf7d0134a5671016732d9690f77599aa54b911cee`：

```text
ArenaFlowTests/DuelSharedRootVisualCaptureTests/testFinalSharedRootReleaseShowsBothFightersAndAcceptsSunBranchesThroughRealControls
```

实际 `uiExecutionStatus=blocked_by_native`、`observedMethods=0`，`uiObservedCounts=null`，没有意外 UI 文件。工作流 UI 与 UI export 两步骤均 skipped，表示本次未执行；没有构造“0 PASS”的通过记录，也没有把它算作 XCTest skipped 方法。之前 Run 43652056280 的真实 UI 失败仍保留，未被本次覆盖。

### 实际步骤时序

以下统一为 **北京时间 2026-11-15（UTC+08:00）**；JSON 同时保存 API 原始 UTC。

| 步骤 | 开始—结束 | 实际结论 |
|---|---|---|
| 源码与唯一候选绑定 | 11:03:59—11:04:00 | success |
| 选择已安装 Xcode | 11:04:00—11:04:11 | success |
| 认证既有 373 资源 | 11:04:11—11:04:19 | success |
| 唯一一次双目标构建 | 11:04:19—11:10:21 | success；两个 target 不等于方法执行 |
| 准备独占模拟器 | 11:10:21—11:12:56 | success |
| 新原生方法及完整日志 | 11:12:57—11:17:54 | failure；进程 65、实际一项失败 |
| 原生原 PNG／报告导出 | 11:17:54—11:17:56 | success；允许保存完整黑图失败 |
| 条件 UI／UI export | 11:17:56 | skipped／未执行 |
| 加密封存 | 11:17:56—11:17:57 | success |
| 密文工件上传 | 11:17:57—11:18:00 | success |
| 本次模拟器与明文清理 | 11:18:00—11:18:08 | success |
| 最终独立门禁报告 | 11:18:08 | failure |
| job 终态 | 11:18:13 | completed/failure |

最终 report 的失败符合真实原生失败与 UI 被阻断，未将成功构建／导出／清理错误地升格为验收成功。

## 首次完整离屏图像的已知证据

测试不额外调用 `drawState`，不推进仿真或显示时钟。World 构造中已有的初始采样仍存在；`explicitDrawStateCalls=0` 只描述测试显式调用。构造及挂载后要求正常提交数为 0、提交 tick 为空、原 projector 尚无已编码帧，再唯一调用原 surface 的 `captureFrame`。

终态 producer 已核对报告与原 PNG：

| 字段 | 真实结果 |
|---|---|
| 捕获标签 | `assembly-cold-first-full-frame` |
| 尺寸／像素数 | 956 × 440／420,640 |
| 全不透明像素 | 420,640 |
| 不透明纯黑像素 | 420,640 |
| 全透明像素 | 0 |
| 可见且非黑像素 | 0 |
| 非黑回归门槛 | false |
| 原 PNG bytes | 9,664 |
| 原 PNG SHA-256 | `d057703632281c9f98c789fc1531a33b658d3301494a16a04a8fefcf69f89cd0` |
| captureFrame／测试显式 draw | 1／0 |
| 正常 drawable 提交数 | 0 |
| 原 projector 编码 tick | 0 |
| 辅助 renderer／重绑／测试显式 prepare | 0／0／0 |

这与历史不透明全黑图的摘要一致。**根代理已原样查看并独立复算：只有一种 RGBA 值 `(0, 0, 0, 255)`，没有透明像素；原 PNG 未修改。** 方法结构与图片元数据导出成功不代表图片通过。正常 drawable 展示与真实控件输入没有在本项原生方法中验证，条件 UI 本次也未执行。

本项无法据此指定 SceneKit 内部的准确原因，也没有证明 FOV、灯光、反 Z、粒子比例或 Metal 状态泄漏。此前关联辅助 renderer 后可见仅是历史隔离实验；不能用本次失败批准常驻无用 renderer。

## 完整日志扫描与封存尾部的区别

native producer 在所属模拟器上按本次 start/end 收集完整日志，实际命令 exit 0，完整 JSON **10,476,497 bytes／7,933 条 App entries**，完整内容 SHA-256：

```text
6c6d5db5f998d9f9064851a96ee62590e4e3e44e08535d11017380768abbda10
```

请求区间为北京时间 **11:13:29—11:17:50**；第一条 App 记录为 **11:14:22.026896**，最后一条为 **11:16:03.213712**。已知重复 present 与 present 后访问 texture 两种诊断计数均为 0，完整扫描门禁为 true。这只说明本次已知两种日志模式没有出现，不能证明像素正确或不存在其他渲染问题。

封存策略对超过 2 MiB 的文字只保存有明确标记的尾部。消费者能够验证认证过的完整扫描回执与实际尾部摘要，不应声称只凭尾部独立重新扫描了完整 10 MiB 日志。消费者已验证认证回执与实际 2,097,152-byte 尾段；`fullLogIndependentlyRescanned=false`、`archivedTailVerifiedOnly=true`，并核对日志区间覆盖实际测试。UI 没有执行，其日志状态 `UNAVAILABLE`，不计通过。

## 工件、资源与安全边界

| 工件字段 | 实际值 |
|---|---|
| artifact ID | `14144945404` |
| 名称 | `fighter-scene-assembly-followup-43670209830-1-encrypted` |
| GitHub 工件大小 | 3,610,739 bytes |
| GitHub digest | `7c9d0515d19ba58ad35c7124580b78f50d6aa34d2f37a3e186e99c60ea650d30` |
| 创建／到期 | 北京时间 11 月 15 日 11:18:00／11 月 18 日 11:17:58 |
| 原生 mandatory 封存 | 原 PNG、报告、manifest，共 3 文件／20,290 bytes，遗漏 0 |
| UI 封存 | 0 文件；未执行，闭包门禁 false |
| cleanup | true |

资源仍是既有 release `h17-shared-root-floorfall-20261115-v2`，release SHA `e5c0ccaeef85ce86c5b8fd4ee64524794d6556f5a561f4078362f6899bedf4e5`。原 73 基础文件、295 overlay 与 13-payload 增量认证后形成同一 373 编译资源闭包；没有重新解码、上传资源版本或上传 TestFlight。三个既有资源密钥只进入受保护 stage；证据单独加密，仅密文上传。

刘仍为 `liu_hammers / isPangu=false`。本次没有新增 D19 独占素材、动作或装备，不能把双锤画面／配置登记为盘古完成。

## 认证消费与失败证据闭包

根代理只消费本次工件一次，GitHub digest、信封校验、认证解封、canonical 源与 selector、方法设备归属、原图／报告摘要、封存 inventory 均通过身份和结构核验。实际解出 **47 文件／46 inventory entries**；多出的文件是 inventory 本身。**这些是证据有效性检查，native 冷帧与条件 UI 自动化验收门槛仍均为 false。**

消费者找到 4 条失败记录，分别来自 xcodebuild stderr、同一 XCTest 的像素断言、该方法失败摘要及 phase 包装错误，均指向同一个原生失败；不能写成 4 个失败方法，也不能因解密成功宣称 0 failure。

| 已认证内容 | bytes | SHA-256 |
|---|---:|---|
| 原生报告 | 9,298 | `ede365964b940bb48195e8a2722ed7a135e16265b2f6d8044f0a270cf8c5d5a2` |
| 附件 manifest | 1,328 | `f43be7654f59cd7c38770a9aa65710483ff8fc46e91c75c7f1ee8556fc31520e` |
| 精确原生执行日志 | 135,510 | `152d3d155ea2278677c6bd5b3acc41bd5d8b307caa119a8a8481b203a7962c3e` |
| runtime 封存尾段 | 2,097,152 | `223500bb273edeea0b6a359def1811246d029f201982f86adf1abd1a4cd94aae` |
| 本次构建日志 | 1,100,954 | `c96eb4b46047c9f645aa2421dd424bd365b8edced6121638fd61269bbd1f6c82` |

原报告记录构造已完成、唯一 Surface 尝试／子视图各 1、同一 packet renderer／FrameDriver／原 projector 正确连接，初始 pose 已在 Surface 前采样；第一次 capture 前没有正常提交或原 projector 编码。capture 后原 projector 在 tick 0 编码了 **13 个 caster／74,855 个三角形**，但输出依旧全黑。场景目录中宫殿有 24 个 geometry，孙有 26 个 geometry／9 个 skinner，刘有 28 个 geometry／8 个 skinner；目录对象存在不能替代其像素可见性。

两角色 HP 均 1000；孙处于 `h17_fight_start_stance_birth` tick 0，刘处于 `dual_hammers_stance_idle` tick 0；simulation／animation／live／display clock 均没有推进，ready 均为 false，source effects 和 packets 均为空。保留的 camera FOV 为 24.689624786376953°、near 0.1／far 350；renderer／surface／source preparation 错误字段为空。以上事实不足以确定内部渲染故障原因。

原报告总墙钟 **72.99568754166671 秒**；构造 session 26.11047329166672 秒、构造 World 37.67125408333345 秒、mount/layout 0.0063354583332966286 秒、首次离屏捕获 8.711862458333371 秒、原 PNG 统计 0.011343916666646692 秒。离屏捕获包括同步 GPU 回读等待；这些不是 live FPS 或隔离 GPU 性能结论。

cleanup 已在失败断言前记录 scene、Surface、packet renderer、delegate、projector 与回调解绑，活动时钟为 0→0；没有证明 ARC 对象析构。最终 Actions cleanup 另确认本次模拟器与明文已删除。没有改写旧报告、重跑成功方法或再次下载工件。

## 历史证据与本次结论

此前 117、5、6 项成功原生方法，以及 cdd／00442／4bd／09f2 四个成功诊断均未再选择；历史方法和旧 SHA 不累计为本次成功。新入口的 18 项离线合同检查首次 **18 PASS／0 FAIL／0 skipped，1.795 秒**，只验证入口规则，不替代此次 Apple 失败。

当前结论为 **冷首帧原生回归失败，条件 UI 被阻断，不能发布验收通过**。失败原图与精确断言已保留；后续应依据实际证据继续定位场景关联问题；不能把源码审查通过、正常环境审批、成功构建或没有两种已知 Metal 日志当作修复完成。

完整生产画面、正常 drawable、真实操作、可听音效与音画同步、FPS／内存／温升，以及 iPhone 17 Pro Max 真机仍未通过本次验收。

## 候选处置：恢复原生命周期，保留失败事实

本结果记录随以下最小撤回一起提交：`App/Views/DuelWorld.swift` 精确恢复为执行基准 `09f2f3c2ea1c8ad0283e920d442995a5faa1b254` 的原字节，SHA-256 为 `e01058a8f5f57ce516621534f0e642397537a3532b7b3ffc88e80cf93bcf948e`；这也恢复此前 `532fb030…` 的 App/Core 行为。没有继续保留未通过验证的延后装配变化，也没有触碰另一个 Sites 正在处理的 Surface 等文件。此撤回没有重新执行旧成功测试，不构成黑场已修复或新原生通过。

本次 `DuelSceneAssemblyFollowupTests.swift` 从当前测试发现目录移除，完整源码仍由上文 e35c 固定链接和本次 xcresult 保存。它在第138行把 `initialPoseAppliedBeforeTriadSurface == true` 作为前置断言；恢复原生命周期后，该值应为 false，继续保留会在原图抓取之前因实现次序退出。不能伪造该值，也不能把已被证伪的实现假设固定为长期产品要求。后续行为回归应以原始像素、资源身份、时钟和输入边界为正确性条件；装配次序作为诊断观察。

本次 helper、离线检查和 workflow 保留原始身份 pins，作为 e35c 的历史执行入口；新提交消息不匹配本次唯一触发条件，还原后的源文件也不能通过该入口的固定源码门禁。失败记录仍为 `0 PASS / 1 FAIL / 0 skipped`、UI `blocked_by_native`，P16 继续标记需要修复与阻塞发布。

### 异步准备的剩余证据缺口

执行源码中的 `prepareSourceMusicIfMounted()` 实际调用继承自 SCNView 的 `prepare([scene], completionHandler:)`，参数是完整当前场景；它用于音乐就绪状态，但并非仅加载音频。挂载与布局会触发该异步场景准备，完成回调记录场景身份并刷新音乐就绪状态，没有重绑原 Surface，也不阻断本次 capture。同步 MainActor 测试未等待该 completion，报告没有记录其开始、完成或成功状态。`explicitPrepareCalls=0` 只说明测试没有额外 prepare，空 `triadPreparationFailure` 也不是这条异步准备成功的证明。

4bd 的 prepare 接收者是原 Surface 的 `sceneRenderer`，与这里的 SCNView 不是同一 renderer。现有证据不足以确认上述异步准备与黑场之间的因果关系；未据此提交新生产改动或追加重型运行。09f2 的额外关联后可见与 e35c 的延后装配仍黑分别保留，SceneKit 内部根因仍待查。
