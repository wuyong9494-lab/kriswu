# 实际渲染器准备：最小生产修正与后续验收合同

## 依据与当前边界

`a7d5a447…` / [run 43676028522](https://github.com/wuyong9494-lab/kriswu/actions/runs/43676028522) 的新宿主诊断实际 1 PASS / 0 FAIL / 0 SKIP。拦截自动宿主场景准备后，原 Surface 第 0 帧已经能看到宫殿、孙登出生姿态和刘泉纬双锤；随后一次同步宿主 prepare 返回 true，前后原 PNG 字节相同。详见[实际报告](fighter-host-scene-ownership-run-43676028522.md)。这是暂停、离屏条件下的有限证据，尚未验证正常 drawable、生产 UI 或网络比赛。

本次修正针对已定位的调用链：`didMoveToWindow / layoutSubviews → prepareSourceMusicIfMounted 或 prepareNetworkSceneIfMounted → prepare`。旧代码从宿主 SCNView 准备整个场景，而装备路径实际通过 `triadRenderSurface.sceneRenderer` 绘制同一场景。新的候选仅在 `App/Views/DuelWorld.swift` 统一这两个准备入口的所属渲染器。

## 最小代码范围

有 Triad Surface 时，只允许将原准备对象数组交给当前实际 `sceneRenderer`；必须确认相同 scene、surface 和 renderer 身份。存在 Surface 但身份不匹配时明确失败，不能回退错误宿主。无 Triad Surface 的既有路径仍使用 SCNView。

异步完成回到 MainActor 后重新核对 owner、scene、surface 与 renderer，再进入原来的音乐 UUID 或网络 owner 完成方法。原一次完成、失败不自动重试、卸载失去就绪、网络 effect variants 与真实资源校验保持。测试拦截入口不参与新的真实原生回归。

不新增 renderer，不重绑场景，不用同步主线程 prepare，不删除音乐就绪回调或增设仿真时钟门槛。受保护的 Surface、FrameDriver、GLTF、投影与武器资源实现均不修改。本候选的 SceneKit 内部因果仍需实际后续结果支持，不能由先前隔离图推导成已修复。

## 仅执行必要范围

- 新原生方法：`SiteTests/DuelActiveRendererPreparationTests/testInstalledActiveRendererPreparationKeepsFirstFrameVisible`，一次真实自动异步准备，核原 completion、就绪与第 0 帧原图。原图与诊断报告必须先保存，再断言；黑图、未就绪或身份不符不能触发下一步。
- 原生与证据门禁均通过后，只选择此前失败的 `ArenaFlowTests/DuelSharedRootVisualCaptureTests/testFinalSharedRootReleaseShowsBothFightersAndAcceptsSunBranchesThroughRealControls` 一次。未满足条件时记录 `blocked_by_native`、0 observed methods、null 方法计数，不能当作 0 项通过。
- 只做一次双 target 构建，复用同一 373 文件加密资源版本与原密钥环境；不重复上传资源或 TestFlight。
- 原 117、5、6 项及已成功的宿主诊断不重新选择。新增离线证据校验与实际 Apple 方法、UI 操作、人工图审分别计数。

唯一提交标题为 `Verify active renderer preparation and approved Android continuation 20261115`，限定原仓库、原分支、push 与 attempt 1。Android 继续项使用独立 job 和证据层，不计入 Apple 方法。

## 结果登记

结果以实际执行 SHA、run/job、方法计数、原图、运行时日志与清理回执为准。完整日志 producer 扫描与消费者尾段核验分开声明；普通 drawable 的可见性需要实际 UI 证据。声音、性能、双机网络一致性和物理 iPhone 17 Pro Max 仍按各自未完成范围登记。

刘泉纬当前资源身份仍为 `liu_hammers / isPangu=false`；孙刘与宫殿出现在诊断图中不能补齐盘古的 11 个文件、12 个 aliases 和 5 类装备，也不能登记角色开发或发布验收全部完成。

## 首次离线检查

新 producer 的 20 项证据合同检查首次 20/20 通过（unittest 3.428 秒，进程 3.733010 秒）；日志 SHA-256 `bac132bb7b845660176614816a8dbd3db7cb3ce8bb4bbbceb6ace63d0664f767`。它们只验证固定来源、真实方法计数、原图、就绪及条件 UI 门禁，未运行 Apple 方法。Swift 解析与编译仍由实际 Xcode 构建给证据，本地没有 Swift 工具可供核验。
