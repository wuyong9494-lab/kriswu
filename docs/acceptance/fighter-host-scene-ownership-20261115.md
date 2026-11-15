# 孙登首帧：原宿主 SCNView 准备归属诊断

## 状态与目的

本入口是新诊断，**不是已证实的生产修复**。准备阶段没有执行 Apple 方法、没有 UI 验收、没有新增媒体上传；实际执行 SHA、run、原图与结果须在新工作流结束后单独记录。当前固定的生产源码基线是恢复后的 `1efa361dbe454262e395221ba33b34d4779377d5`。App、Core、受保护的 Surface 与全部已有测试字节保持该基线。

本轮只选择一个新原生方法：

`SiteTests/DuelHostSceneOwnershipTests/testInstalledHostScenePreparationIsIsolatedAtFrameZero`

范围标识为 `installed-host-scene-ownership-one`，报告 schema 为 `fighter-host-scene-ownership-v1`。没有 UI 方法；`not_selected` 和零个选择不表示“零项通过”。

## 为什么需要这个区别

已有证据的范围不能混合：

| 历史源与运行 | 已观察结果 | 本轮没有重复选择 |
| --- | --- | --- |
| `4bd85374273b39f61724342b7e1d72631ab2042d` / [43664242283](https://github.com/wuyong9494-lab/kriswu/actions/runs/43664242283) | 实际 Surface 的 `SCNRenderer.prepare` 返回 true，原图仍黑 | 原准备方法 |
| `09f2f3c2ea1c8ad0283e920d442995a5faa1b254` / [43666784396](https://github.com/wuyong9494-lab/kriswu/actions/runs/43666784396) | 原 Surface 的前三图黑；仅额外关联 fresh renderer 后，仍由原 Surface 输出的第四图可见 | 原注册方法 |
| `e35c51d7b0fbe4e7659892d1fcc0caf839479a65` / [43670209830](https://github.com/wuyong9494-lab/kriswu/actions/runs/43670209830) | 延后唯一 Surface 初始化的候选实际 0 PASS / 1 FAIL / 0 SKIP，首图 420,640 像素全部不透明黑，UI 被原生门槛阻塞 | 失败候选方法及被阻塞 UI |

World 同时是一个 `SCNView`，自身也关联完整 scene。其 `prepareSourceMusicIfMounted` 名称描述的是音乐就绪用途，实际调用 `SCNView.prepare([scene], completionHandler:)`，会请求场景几何、材质和纹理的后台准备。它不等于音频文件解码，也不等于 Surface 内部 SCNRenderer 的 prepare。

Apple 文档说明，`rendersContinuously = false` 仍允许 scene graph 变化时重绘；`isPlaying = false` 只停止 scene time 递增。因而不能把这两行设置解释成“父 SCNView 已完全停止场景工作”。但共同持有 scene 本身也不是已证实的 API 错误，当前尚不能据此认定黑场根因。

官方依据：

- [SCNSceneRenderer.prepare(_:completionHandler:)](https://developer.apple.com/documentation/scenekit/scnscenerenderer/prepare(_:completionhandler:))
- [SCNSceneRenderer.prepare(_:shouldAbortBlock:)](https://developer.apple.com/documentation/scenekit/scnscenerenderer/prepare(_:shouldabortblock:))
- [SCNView.rendersContinuously](https://developer.apple.com/documentation/scenekit/scnview/renderscontinuously)
- [SCNSceneRenderer.isPlaying](https://developer.apple.com/documentation/scenekit/scnscenerenderer/isplaying)

## 两张原图及唯一变量

先创建离线练习 session，使用现有公共暂停 API 在 World 构造前暂停。利用既有 DEBUG `testingMusicPrepare` 接口截获挂载时的一次准备请求，核对传入对象是同一个完整 scene。不启动该后台调用，不转发其音乐就绪 completion。

setup 仅对原 Surface 调用一次 `setPaused(false)`，允许离屏编码；游戏 session 始终暂停，不启动 CADisplayLink。这个设置在 A/B 之间不变，报告明确区分暂停游戏与允许离屏采样。它不是正常 drawable 呈现或输入验证。

| 顺序 | 原图 attachment label | 操作与边界 |
| --- | --- | --- |
| A | `host-prepare-intercepted` | 自动准备请求已经截获；尚未执行显式 prepare；原 Surface、scene、camera、projector 完整保留 |
| B | `host-world-prepared` | 仅在原 World/SCNView 上同步执行一次 `prepare(scene, shouldAbortBlock: nil)` 后，仍由同一原 Surface 截图 |

报告 attachment 为 `host-scene-ownership-report`。不存在 C 解绑分支，不创建 fresh renderer，不重绑任何 scene，不对 Surface renderer 调用 prepare，不调用 snapshot API，也不显式调用 drawState 或推进游戏。所有采样固定 frame / animationTick / sourceLiveTick / displayLinkCallbacks 为 0，source packets 为 0。

两次 capture 均为 956 × 440 原始 PNG，使用原 Surface 的相同完整离屏渲染路径和原 projector。正常 drawable 提交数必须保持 0。截图本身会执行原 capture 路径的提交回调，但不是屏幕 present。

同时记录并核对同一 Surface、renderer、scene、camera、projector、Metal device、节点/geometry/material/skinner 对象身份、模型变换、灯光和角色初始状态。presentation 变换只作观测，不把变化伪装成模型变化，也不要求两个 PNG 相同。PNG 相等布尔必须与实际原图摘要一致。

## 结果如何解释

- A 已可见：应优先调查自动后台准备启动的影响；不能归功于尚未发生的同步 prepare。
- A 黑、B 可见：原宿主 SCNView 的准备与 Surface 输出之间出现可观察差异，仍须解释 renderer 归属与后续生命周期，不能直接宣称生产修复。
- A、B 均黑：这条特定宿主准备路径没有解决本次空帧，不能继续把“补一次 prepare”作为已验证修复。

`diagnosticCompleted` 只表示原图和观测形成。最终 XCTest 还检查同步 prepare 的真实返回值和清理结果。若 prepare 返回 false，仍先保存两张原图、完整报告与实际清理回执，然后方法失败。若两图都黑但操作和清理成立，诊断方法可以通过；**自动像素结论始终为 `PENDING`**，不得把方法 PASS 当成角色、舞台、原始效果或正常游戏画面验收。

报告清理在最终断言前显式完成并只附加一次；fallback defer 只处理尚未形成完整数据的早期失败。清理检查原 World/Surface/renderer 解绑、原 projector 和 callback 清除、测试 hook 清除以及显示时钟归还，不声称已证明 ARC 析构。

## 执行与证据门禁

工作流 `.github/workflows/fighter-host-scene-ownership.yml` 只接受指定仓库与验收分支上的 push，commit message 必须完整等于 `Verify approved Android client and host ownership 20261115`，且仅 attempt 1。没有 workflow_dispatch、自动重试或旧成功方法选择。

执行使用一个 SiteTests 构建、一个已安装的 iPhone 17 Pro Max 模拟器、一次精确 `-only-testing` 调用。原生进程保留 720 秒上限，失败后不重试。原始 xcresult summary/tests、真实退出码、唯一方法集合、0 skipped 和 owned simulator 归属独立核验。构建 target 存在不是方法已执行的证据。

资源保持 `e5c0ccaeef85ce86c5b8fd4ee64524794d6556f5a561f4078362f6899bedf4e5`，delta 为 `d50b7fc6f711a55849b259b0f78d348612782f5e3765f9629db50291e20fe2b9`。继续认证 73 个 baseline 文件、295 个 overlay 文件和 13-payload delta，最终 373 个资源；资源密钥只进入 stage。后续阶段拒绝资源密钥，封存只使用本次新证据密钥。没有 TestFlight 或资源版本上传。

所有既有 App/Core/build 输入、Tests、CI helper 和 workflow 按恢复基线固定。新增 Host Swift、helper、离线检查和 workflow 各自固定摘要。整体提交中的以下 Android 文件仅按精确名称允许并记录实际 SHA256，**不是 Host 的执行或构建输入**，不会被导入或调用：

- `.github/scripts/fighter_android_official_client.py`
- `.github/scripts/fighter_android_sdk_install.py`
- `.github/scripts/test_fighter_android_official_client.py`
- `.github/workflows/fighter-android-official-client.yml`

该处理避免两个独立新入口互相固定摘要造成循环，同时不放开整个 CI 目录。文档更新不属于编译输入。

完整本次原生调用区间的 simulator App 日志先做非空、结构、owned simulator 与已知 drawable 错误门禁，再封存最多 2 MiB 的文本尾部。超过限额时明确记录 `tailOnly`、原长度/摘要；尾部中没看到错误不能升级为完整日志独立复扫。

两个强制 PNG、JSON 报告与附件 manifest 优先进入同一密封工件。每个强制附件保留不超过 24 MiB、非空、方法/device/label/摘要门禁；系统自动附件另有总量限制，不计覆盖。部分失败附件仍保留，缺必需证据不能通过完整证据门槛。仅上传一次密文工件，随后清理本入口拥有的模拟器、构建产品、暂存资源与明文。

## 本地准备状态

本次提供新 Swift、独立 producer、18 项针对新 scope 的离线检查、workflow 和本文档。首次离线检查由根代理在源码复核后执行；本文件初版形成时尚未执行检查、Apple 编译或原生方法。不重跑历史 117、5、6 或各轮已执行的独立诊断，也不把历史结果计入本次。
