# 场景组装顺序候选与条件 UI 回归（2026-11-15）

**这是待实际 Apple 执行的候选与验收设计，尚不是修复通过报告。** 源基准是 `09f2f3c2ea1c8ad0283e920d442995a5faa1b254`。此前 [Run 43666784396](https://github.com/wuyong9494-lab/kriswu/actions/runs/43666784396) 的注册诊断方法实际 1 PASS：A 无原投影器、B 恢复原投影器、C 重绑原 renderer 的三图全黑；D 只关联第二个 renderer 后，原 surface 才可见。这证明实验内的关联操作能改变原 surface 输出，但没有证明应在生产中保留第二个 renderer，也没有完成完整生产或真机验收。

## 唯一生产候选

本轮只允许 `App/Views/DuelWorld.swift` 改变。原场景的模型、Morph、源特效节点与初始姿势先完成组装，随后才创建并首次绑定唯一的 `DuelTriadRenderSurface`。保持同一原投影器、packet renderer、frame driver、late geometry provider、提交回调与暂停状态；不增加 fresh renderer，不在生产中重绑 scene，不修改受保护 Surface 或其渲染 pass。

新入口以逐文件保留摘要固定除 World 以外的 App，另固定 Core、Shared、Widget、工程、资源工具、所有旧测试与既有 CI。World 的完整文件 SHA 单独绑定；不能借这个例外修改其他 App 文件。新 Swift、三个新 CI 文件也分别固定完整字节摘要。

## 新 native 方法：第一次完整离屏编码

```text
SiteTests/DuelSceneAssemblyFollowupTests/testInstalledColdSceneAssemblyRendersFirstFullFrameWithoutRegistrationWorkarounds
```

使用现有真实 release `h17-shared-root-floorfall-20261115-v2`。正常构造 World 后保持其已有初始姿势采样；测试不额外调用 `drawState`。构造与挂载后均要求原 surface 的正常 drawable 提交数为 0、提交 tick 为空、原投影器尚无 `lastFrame`，然后只调用一次原 surface 的 `captureFrame`。

唯一原 PNG 标签为 `assembly-cold-first-full-frame`，报告标签为 `scene-assembly-followup-report`，schema 为 `fighter-scene-assembly-followup-v1`。画幅固定 956×440，requested samples 2 对应平台 resolved samples 4。原投影器始终安装，唯一捕获必须真正产生其 tick 0 元数据；frame、animationTick、sourceLiveTick、displayLink 回调、source packets 与正常 drawable 提交数均保持 0。

该方法不创建辅助 renderer，不 prepare、不重绑、不移除原投影器、不切换样本数，也不注入游戏状态。`explicitDrawStateCalls=0`、`captureFrameCalls=1` 和 `normalDrawablePresentationValidated=false` 是不同口径：本项证明首次完整**离屏**编码的窄回归，不能声称正常 drawable 展示已经通过。

Swift 从保存的原 PNG 解码统计；producer 再独立解析该 PNG 的 CRC、尺寸、像素和摘要，与报告逐值核对。窄门槛是 420,640 个像素全部不透明，并至少有一个 `alpha > 0` 且任一 RGB 通道大于 0 的像素。全透明空图不能通过。这个条件只排除已知全黑／空图，不证明人物、舞台、构图、材质、动作或源准确性；自动 `pixels=PENDING` 始终保留。

Swift 在最后的时钟／像素断言之前实际执行 cleanup 并附加完整报告，且保证报告不重复。完整报告的 `lastPhase=captured-before-regression-assertions` 不能用来推断 PASS。黑图失败也保留 PNG、统计和清理记录；实际 XCTest 结果另外核对。清理只证明 owner、scene、camera、delegate、投影器和回调解绑，不冒充 ARC 析构证明。

## 一次构建，条件执行原失败 UI 方法

同一次 unsigned `build-for-testing` 通过临时工程 spec 构建现有 `SiteTests` 与 `ArenaFlowTests` 两目标。原 `project.yml` 保持原字节。生成的 xctestrun 必须恰含这两个目标，SiteTests 的 host 保留 `-demo`，不得包含跳过方法列表。**目标被构建不计为方法执行。**

先只执行上述 1 个新 native 方法。只有本次精确 1 PASS／0 FAIL／0 SKIP、同一设备、原 PNG 非黑窄门槛、完整附件归属与 native 完整运行日志门禁全部成功后，才允许执行一次：

```text
ArenaFlowTests/DuelSharedRootVisualCaptureTests/testFinalSharedRootReleaseShowsBothFightersAndAcceptsSunBranchesThroughRealControls
```

这是之前 `532fb03083da7053417b7ad7ba484a99e4c41c28`／[Run 43652056280](https://github.com/wuyong9494-lab/kriswu/actions/runs/43652056280) 已失败的方法，保持原 UI 源 SHA `d144949cad4b14eeef47ad7bf7d0134a5671016732d9690f77599aa54b911cee`、实际控件操作与等待边界。新入口没有修改其流程、注入 HP 或延长 xcodebuild 的 360 秒外部执行上限。

native 前置不满足时，UI 明确为 `blocked_by_native`，实际 UI 执行为 0，UI 方法结果计数为未知／无结果，不制造“0 PASS”的通过记录，也不将工作流 skipped 当通过。若 UI 实际失败，保留此前新 native 的真实结果，UI 独立记失败，不重新调用 native。native 与 UI 使用同一个本次新建的模拟器，分别保存 xcresult 方法结果、进程退出码、附件与完整日志区间。

UI 图像要求原有 6 张 PNG 与 `shared-root-ui-observations` 全部具备正确方法、UDID、设备名称、release、原字节摘要；完整真实控件流程仍须成功。失败时保留已有部分附件和失败记录，不能拿缺失集合或自动系统截图补足覆盖。正常 drawable 与输入属于这项独立 UI 范围；native 的非黑像素不能替代它。

## 证据、安全与成功条件

- 原资源 release SHA 为 `e5c0ccaeef85ce86c5b8fd4ee64524794d6556f5a561f4078362f6899bedf4e5`，复用原 373 个编译资源，不重传版本。
- 资源密钥只提供给受保护 environment 的 stage；其他阶段拒绝资源密钥环境变量。封存阶段使用独立新证据密钥并包装给既有收件人，只上传密文，不上传源码资源明文、密钥或编译 App。
- 两个 scope 的完整 start/end 日志先以完整 JSON、实际命令 exit 0、所属设备和非空 App entries 验真，并统计已知 drawable 重复 present／present 后访问 texture 错误。封存的文字超过 2 MiB 时只保留标注的尾部；尾部没有错误不能冒充独立扫描过完整日志。
- native 与 UI 的必需附件及两个 manifest 全局优先，分享最多 256 文件／160 MiB 附件预算。任何必需集合未实际进入密封 inventory，最终门禁必须失败。自动视频或其他系统附件仅有界保留元数据，不计覆盖。
- 一次 push、attempt 1、一次构建、最多 native 1＋UI 1、一个加密工件。没有 retry、workflow_dispatch、额外 UI、备用模拟器或 TestFlight 上传。失败后仍尽可能封存，随后清理本次模拟器、staged media、产品与明文。
- 历史 117、5、6 个成功方法与 cdd／00442／4bd／09f2 的四个成功诊断均不再选择。历史计数不累计到本次。

最终工作流成功仍只表示新 native 与指定 UI 方法及其证据门禁均达到。原始图像人工审查、完整生产表现、音画同步、FPS／内存／温升和 iPhone 17 Pro Max 真机验收继续单独记录。刘仍为 `liu_hammers / isPangu=false`；本候选不补齐 D19 独占资源、动作别名或装备。

## 当前验证状态

World 与新 Swift 已完成源码审阅。实际 Apple 编译、方法执行与原图尚待本入口运行。当前环境未启动本地 Swift 编译，不能把缺少命令解释成代码失败，也不记录为本地 parse 通过。

本入口新增 18 项离线检查，覆盖唯一生产文件例外、两目标单次构建、精确选法、条件 UI、实际 PNG 统计、完整失败保留、完整日志及两 scope 密封闭包。主代理已在北京时间 2026-11-15 10:56 首次运行该集合，结果 **18 PASS / 0 FAIL / 0 skipped，1.795 秒**（外层进程墙钟 2.041 秒）。这是纯离线检查，实际 Apple native/UI 调用均为 0；其中 mock UI 函数的成功输出不能计作真实 UI 执行。私有消费者的独立合成检查也不计为 Apple 方法、像素或真机通过。
