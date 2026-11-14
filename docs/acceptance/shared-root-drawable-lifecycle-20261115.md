# Shared-root drawable 生命周期：真实诊断与最小调用层修复

记录日期：2026 年 11 月 15 日。本文时间均为北京时间（UTC+08:00）。

## 证据范围与当前结论

[运行 43647414701](https://github.com/wuyong9494-lab/kriswu/actions/runs/43647414701) 的源提交为 `5788ebb1001a6e0f31c5208cb2b955b48b00741c`。该次实际执行结果为 **6 个原生方法通过、0 失败、0 skipped；另 1 个 UI 方法失败、0 skipped**。实际模型加载报告附件也通过身份与归属门禁。工作流最终结论仍是 `completed / failure`，最后更新时间为 **2026-11-15 06:42:22**。

此次原始 UI 截图中，Sun 大厅的角色和舞台可见；练习场截图则出现黑背景、角色不可见、左侧巨大青白特效，而 HUD 仍可见。真实 Core Animation 日志、失败提交的调用链和 Apple 文档共同确认一个具体缺陷：**调用方在 MetalKit 绘制回调之外重复使用并呈现 `MTKView.currentDrawable`，没有经过 MetalKit 推进 drawable 的回调边界。**

下面的修复纠正这一已确认的生命周期缺陷。它尚未经过新的 Apple UI 执行；不能据此宣称全部黑场、角色可见性或特效尺寸问题已经解决。

下一次验证的基准提交为 `5afd8195e2f611ab2e7c37f5096a4251a4616ee9`，对应 tree `f0bd64525ae7df38e0db8b2e14368593f4189f90`。本次新增实现与本文由后续统一提交发布，以下使用仓库相对链接，不编造尚未发布的新提交 SHA。

## 两条实际 Metal 呈现诊断

诊断来自同一应用进程 `26043`，子系统 `com.apple.coreanimation`、category `API`，均为 `Error`：

| 北京时间 | 实际诊断 |
| --- | --- |
| 2026-11-15 06:38:37.874291 | `[CAMetalLayerDrawable texture] should not be called after already presenting this drawable. Get a nextDrawable instead.` |
| 2026-11-15 06:38:37.881896 | `Each CAMetalLayerDrawable can only be presented once!` |

归档条目为 `metadata/ui-runtime-log.log`。其 SHA256 为 `504abe606dd4498ca8292377e23c2427740341c7d89c702e95e35d9981ace140`。证据 inventory 明确记录原日志 **12,629,580 bytes**，归档的是 **2,097,152 bytes 尾段**，`tailOnly=true`；本文没有把保留尾段称为完整运行日志。

这些诊断来自已由根代理下载并认证解封的既有工件。本次定位、代码修改和本地验证未再次下载、解封或复制原始媒体。

## 原调用链与缺陷位置

失败提交中的真实源文件：

- [DuelWorld.swift，5788 源](https://github.com/wuyong9494-lab/kriswu/blob/5788ebb1001a6e0f31c5208cb2b955b48b00741c/App/Views/DuelWorld.swift)
- [DuelTriadRenderSurface.swift，5788 源](https://github.com/wuyong9494-lab/kriswu/blob/5788ebb1001a6e0f31c5208cb2b955b48b00741c/App/Services/DuelTriadRenderSurface.swift)

主显示路径是 `CADisplayLink → DuelDisplayTarget.tick → DuelWorldView.tick`。`tick` 先通过既有 `DuelClock` 计算固定步并调用 `session.advance()`，随后调用 `drawState()`。初始化和 `session.didReset` 也会调用 `drawState()`，本次没有给这些路径增加新的时钟。

`drawState()` 先应用角色姿势、相机、召唤物与源特效 packet，提交 SceneKit transaction，然后直接调用 `DuelTriadRenderSurface.drawFrame(tick:pointOfView:samples:)`。该方法取得 `currentDrawable`，调用 `encodeFrame`，登记 command completion，最后 `command.present(drawable)` 和 `command.commit()`。

`DuelTriadRenderSurface` 是 `MTKView` 子类，原配置为 `isPaused=true`、`enableSetNeedsDisplay=false`。它没有实现 UIKit 的 `draw(_:)`，也没有安装 `MTKViewDelegate` 的 `draw(in:)` 回调。原 World 直接调用自定义 `drawFrame`，因此每次提交没有经过 MetalKit 自身的 draw 回调返回边界。原生命周期与日志中的 after-present、double-present 诊断一致。

离屏 `captureFrame` 使用显式新 texture 和 command buffer，实际模型加载测试也不是 live drawable 连续呈现测试。因此已有原生测试成功不能排除本次在真实 UI 路径中观察到的缺陷。

## Apple 文档依据

本次实际查阅了以下 Apple 文档及其官方 Markdown 内容：

1. [MTKView.currentDrawable](https://developer.apple.com/documentation/metalkit/mtkview/currentdrawable)／[官方 Markdown](https://developer.apple.com/documentation/metalkit/mtkview/currentdrawable.md)：drawable 用于当前帧；只有在子类 `draw(_:)` 或 delegate `draw(in:)` 返回后，view 才更新该属性。没有可用 drawable 时应正常跳过绘制。
2. [MTKView.draw()](https://developer.apple.com/documentation/metalkit/mtkview/draw())／[官方 Markdown](https://developer.apple.com/documentation/metalkit/mtkview/draw().md)：手动要求 view 立即重绘会调用 delegate 或子类的绘制回调；不能在绘制回调内部再次调用 `draw()`。

因此采用调用层 adapter：由既有 World 进入 `surface.draw()`，在 delegate 回调里调用原 surface 的渲染方法，并在原 surface 返回后结束该回调。没有改为额外显示时钟，也没有在回调中递归调用 `draw()`。

## 两个非保护文件的最小修复

| 文件 | 作用 | SHA256 |
| --- | --- | --- |
| [DuelTriadSurfaceFrameDriver.swift](../../App/Services/DuelTriadSurfaceFrameDriver.swift) | 新增主线程同步 `MTKViewDelegate` adapter | `1986d589d7ca309e426491f818f4f9e0f9d81a2a99f6a2c4c2e1b6274f347849` |
| [DuelWorld.swift](../../App/Views/DuelWorld.swift) | 强持 adapter、创建时安装、drawState 转交、shutdown 先 detach | `e01058a8f5f57ce516621534f0e642397537a3532b7b3ffc88e80cf93bcf948e` |

World 改动为 6 行新增、2 行删除。新呈现链为：

`DuelWorldView.drawState → FrameDriver.drawFrame → MTKView.draw → FrameDriver.draw(in:) → 原 DuelTriadRenderSurface.drawFrame → currentDrawable → encodeFrame → present / commit → draw(in:) 返回 → MetalKit 更新 drawable`

adapter 由 World 强持，反向只弱持 surface。每次请求暂存同一 tick、相机引用和 sample count，在真正渲染前先消费 pending；重复回调、异 view 回调、无 pending 回调不会再次提交。正在绘制时的新请求被拒绝；原渲染器抛出的错误同步回传给 World 原有失败路径。

原 surface 对无 window、无 drawable、in-flight 容量不足和暂停状态的正常跳帧保持。若一次 `draw()` 没有产生 callback，请求在返回时被清除，不积压到以后重放。adapter 不推进 simulation、animation tick、音频或粒子；原时钟、pause 控制和源特效计算保持。

World shutdown 先停止、清 pending 并 detach adapter，再调用原 `surface.shutdown()`。detach 只清除自身持有的 delegate，不覆盖其他 owner。

保护文件 `DuelTriadRenderSurface.swift` 保持 SHA256 `f082f9c9d6d21473a501f16bd07d9ff9fb357ee777dc324a99cd7534b9da1538`。GLTF、源特效与其他受保护渲染文件未修改；没有切回旧画面路径掩盖异常。

## 首次新增的 8 项本地生命周期验证

新 adapter 的实际类体仅移除平台 imports 后，使用 Linux 上的最小 `MTKView`／surface callback-contract shim 编译执行；没有使用 Apple SDK、GPU、原模型、音频或资源密钥。这些检查验证 adapter 的控制流，不模拟真实画面结果。

| 检查 | 首次结果 |
| --- | --- |
| 连续两帧各经过一个同步 callback 周期；保留原 tick、camera、samples | 通过 |
| pending 消费一次；重复、异 view、无请求回调不重复提交 | 通过 |
| 无 window／drawable／容量或暂停时跳帧，无积压、无 tick 推进 | 通过 |
| draw 未调用 callback 时清除请求，后续不重放旧帧 | 通过 |
| 原错误同步回传，下一请求不携带上一次错误 | 通过 |
| 嵌套请求被拒绝，外层帧不被替换或重复提交 | 通过 |
| delegate 独占、所有权丢失拒绝、shutdown 幂等且不夺取其他 delegate | 通过 |
| adapter 不强持已释放的 surface，释放后请求被拒绝 | 通过 |

首次实际结果为 **8 passed / 0 failed**，执行约 **0.000445 秒**。另对两个 Swift 文件执行前端 syntax parse，exit 0；文件差异检查通过。没有重跑任何既有成功测试。

私有验证输入 `driver-lifecycle.swift` SHA256：`119bf2bc1018384b501b411381b85c67317af37c30cc3cfa363e434d4051a941`。结果 `result.json` SHA256：`b16a33bd4d5b4f1593cbf926168fd565c4992da721a9acb27eb81a5bd2c8e759`。结果明确记录 `appleNativeMethodsExecuted=0`、`pixelValidationPerformed=false`，不能作为 Apple 原生呈现或真机通过证据。

## 待执行的 Apple UI 单方法验证

下一次计划仅执行：

`ArenaFlowTests/DuelSharedRootVisualCaptureTests/testFinalSharedRootReleaseShowsBothFightersAndAcceptsSunBranchesThroughRealControls`

原 UI readiness 子串判断由另一份独立改动改成精确值比较；它与 drawable 呈现缺陷分别归因。本记录只负责呈现调用层。新的 App 字节发生变化，需要为新提交重新构建；5788 的旧 App 或恢复产物不能证明这次修复。

该新 UI 方法运行在本文记录时**尚未执行**。待检查真实原资源画面、角色与舞台、根缚实际控制路径和所需截图，同时核对新运行日志中是否仍出现重复 drawable 呈现诊断。即使 UI 方法计数通过，图片仍需人工审阅；仍不能把全部黑场或巨大特效问题提前标记为已解决。

原生 6 项、此前历史 5 PASS 及旧 117 项不列入此次重跑范围。资源 release 与密文版本保持，不重复上传。真机视频、性能指标和可听音频仍是独立待验收范围；没有 TestFlight 上传。
