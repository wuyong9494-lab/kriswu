# 实际渲染器准备：首提交顺序候选与后续验收合同

## 依据与当前边界

`a7d5a447…` / [run 43676028522](https://github.com/wuyong9494-lab/kriswu/actions/runs/43676028522) 的新宿主诊断实际 1 PASS / 0 FAIL / 0 SKIP。拦截自动宿主场景准备后，原 Surface 第 0 帧已经能看到宫殿、孙登出生姿态和刘泉纬双锤；随后一次同步宿主 prepare 返回 true，前后原 PNG 字节相同。详见[实际报告](fighter-host-scene-ownership-run-43676028522.md)。这是暂停、离屏条件下的有限证据，尚未验证正常 drawable、生产 UI 或网络比赛。

`8b33cb0a6bb95e108003847f4d35e22143a40ca5` / [run 43678506116](https://github.com/wuyong9494-lab/kriswu/actions/runs/43678506116) 已实际验证原 Surface 的异步准备返回 true、身份匹配、音乐 ready 成立，但唯一原生方法仍为 **0 PASS / 1 FAIL / 0 SKIP**：956×440 原图的 420,640 个像素全部不透明黑。条件 UI 被原生失败阻断，实际 0 方法、计数 null。详见[实际失败报告](fighter-active-renderer-preparation-run-43678506116.md)。因此，只更换 prepare 所属 renderer 没有修复黑场。该候选仍存在于 `f52c293da885f24ebae7640055161380aba4a5f7`，不能沿用早先“已撤回”的描述。

本次从 f52 继续核对 `didMoveToWindow / layoutSubviews → 两个准备入口 → 原 Surface → command.commit 回调 → 原异步 prepare`。生产候选仅修改 `App/Views/DuelWorld.swift` 的准备先后顺序。其因果仍是待验证假设，不能由暂停离屏的早先可见图推定 SceneKit 内部根因已经确定。

## 最小代码范围

有 Triad Surface 时，两个入口先等待相同 scene、surface 和 renderer 的首次真实提交。门禁放在 `preparingScene` / `musicPreparingScene` 赋值之前，避免尚未发起 prepare 就锁住重入。原 Surface 的 `didSubmitFrame` 继续在每次真实提交时执行已有 MORPH 帧末处理；首次提交后只排一次主队列重入，再将原对象数组交给同一实际 `sceneRenderer`。存在 Surface 但身份不匹配时明确失败，无 Surface 的既有路径仍使用 SCNView。

这里的回调来自 `command.commit()` 之后，包含离屏 capture 的提交；它不代表 GPU 已完成，也不证明正常 drawable 已显示。生产代码不调用 capture、不等待 GPU、不新建 renderer、不重绑 scene。

暂停中的网络准备不能依赖开始游戏后才有的时钟。首次挂载时使用已有 FrameDriver 提交当前 tick、相机和采样数，最多 3 次真实绘制尝试，重试只排到后续主队列轮次，不推进仿真、不启动新时钟。只有真实提交能打开 prepare 门禁；缺少 drawable 或未调用 draw delegate 都不能当作提交成功。耗尽后通过现有失败路径终止准备；队列任务受身份、挂载、关闭状态与错误状态约束。

异步完成回到 MainActor 后重新核对 owner、scene、surface 与 renderer，再进入原来的音乐 UUID 或网络 owner 完成方法。原一次完成、失败不自动重试、卸载失去就绪、网络 effect variants 与真实资源校验保持。测试拦截入口不参与新的真实原生回归。

不使用同步主线程 prepare，不删除音乐就绪回调。受保护的 Surface、FrameDriver、GLTF、投影与武器资源实现均不修改。真实 UI 对正常 drawable 路径的验证与离屏两图方法分开登记。

## 仅执行必要范围

- 仅重选此前失败的方法：`SiteTests/DuelActiveRendererPreparationTests/testInstalledActiveRendererPreparationKeepsFirstFrameVisible`。暂停、原 Surface、同一 tick 下，A 在 prepare 前捕获；其真实提交通知生产代码，再等待一次真实异步准备与原 readiness；B 在准备后捕获。两张完整原图、报告及清理回执先保存，再分别断言。B 是第二次离屏捕获，不能称为“第一次完整帧”。两图均须不透明且包含非黑像素，身份、实际 completion 与 readiness 均须通过。
- 原生与证据门禁均通过后，只选择此前失败的 `ArenaFlowTests/DuelSharedRootVisualCaptureTests/testFinalSharedRootReleaseShowsBothFightersAndAcceptsSunBranchesThroughRealControls` 一次。未满足条件时记录 `blocked_by_native`、0 observed methods、null 方法计数，不能当作 0 项通过。
- 只做一次双 target 构建，复用同一 373 文件加密资源版本与原密钥环境；不重复上传资源或 TestFlight。
- 原 117、5、6 项及已成功的宿主诊断不重新选择。新增离线证据校验与实际 Apple 方法、UI 操作、人工图审分别计数。

唯一提交标题为 `Verify first-submit preparation and APK signer continuation 20261115`，限定原仓库、原分支、push 与 attempt 1。Apple 原生进程上限 720 秒，条件 UI 进程上限 360 秒。Android 签名解析继续项使用独立 job 和证据层，不计入 Apple 方法。

## 结果登记

结果以实际执行 SHA、run/job、方法计数、原图、运行时日志与清理回执为准。完整日志 producer 扫描与消费者尾段核验分开声明；普通 drawable 的可见性需要实际 UI 证据。声音、性能、双机网络一致性和物理 iPhone 17 Pro Max 仍按各自未完成范围登记。

刘泉纬当前资源身份仍为 `liu_hammers / isPangu=false`；孙刘与宫殿出现在诊断图中不能补齐盘古的 11 个文件、12 个 aliases 和 5 类装备，也不能登记角色开发或发布验收全部完成。

## 已有离线检查的归属

8b 单图 producer 的 20 项证据合同检查首次 20/20 通过（unittest 3.428 秒，进程 3.733010 秒）；日志 SHA-256 `bac132bb7b845660176614816a8dbd3db7cb3ce8bb4bbbceb6ace63d0664f767`。该历史成功范围不重新执行，也不自动迁移成两图候选的通过证据。本次只增加首提交顺序、两张原图与门禁的差异检查。Swift 解析与编译仍以实际 Xcode 构建为证，本地没有 Swift 工具可供核验。

本次新增 8 项差异检查于北京时间 2026-11-15 13:59:08–13:59:11 首次 **8 PASS / 0 FAIL / 0 ERROR**，unittest 2.121 秒、进程 2.412847 秒。范围是 4 项来源/入口闭包，以及 4 项两图、首次提交顺序、完整失败保留和条件 UI 门禁；Apple 方法执行数仍为 0。检查文件 SHA-256 `6b3288f0518e44115d07e3217231ca2094cb9b487f03e6a3a8ef57a2931522e2`，原日志 1,744 B / SHA-256 `3a3dfb29570cb2b788733d0311c48e47c9d10279ca881a8d98e4eb43132ce172`。后续真实方法与原图以新的提交和运行记录单独归属。
