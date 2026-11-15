# SceneKit 基础场景诊断结果：43661312798

**本次唯一的新 Apple 原生诊断实际执行一次：1 PASS／0 FAIL／0 SKIP。UI 为 `0 / not_selected`。认证工件的六张原图已逐张复核：四个隔离 surface 分支可见孙角色、刘双锤与宫殿；两个 fresh snapshot 分支完全透明。生产画面仍为 NOT_VERIFIED，发布验收没有通过。** 自动报告生成时的 `pixels=PENDING` 保留原样，后续原图分支复核另行记录。

这是一个新的 frame 0 隔离实验：不推进战斗、不运行 display-link，在同一场景与相机下比较 SceneKit 灯光阴影、surface 多重采样和独立 `SCNRenderer.snapshot`。它没有重跑前一个已成功的 394 步入场诊断，也没有修正生产 App／Core。前一个诊断的画面失败与真实 UI 就绪失败继续独立保留。完整数值记录见[同名 JSON](fighter-scene-base-run-43661312798.json)。

## 实际源身份与执行范围

| 字段 | 已核值 |
|---|---|
| 实际执行源提交 | [`00442b097747d95308ca69339fa999a46c216bc6`](https://github.com/wuyong9494-lab/kriswu/commit/00442b097747d95308ca69339fa999a46c216bc6) |
| 实际源 tree | `3553abf8d12cfa3bc0ab071a62f438779518e07f` |
| 本入口 source gate 基线 | `cdd0d496bf63fd186de6f8d9cf91646c1dc88917`，原有测试、helper 与 workflow 保持原摘要 |
| App／Core 基线 | `532fb03083da7053417b7ad7ba484a99e4c41c28`，本次没有改动 |
| Actions | [43661312798](https://github.com/wuyong9494-lab/kriswu/actions/runs/43661312798) |
| Job | [132651036254](https://github.com/wuyong9494-lab/kriswu/actions/runs/43661312798/job/132651036254) |
| Run number／attempt | `1 / 1`，不是旧运行的 rerun |
| 创建／最终更新时间（北京时间） | `2026-11-15 09:04:28 / 09:20:46`，UTC+08:00 |
| Job 实际起止（北京时间） | `2026-11-15 09:10:01—09:20:45`，UTC+08:00 |
| 最终工作流／作业状态 | `completed / success` |
| 工具链与设备 | Xcode `26.6`；本次专用 iPhone 17 Pro Max **模拟器** |
| 当前新原生计数 | **1 total／1 passed／0 failed／0 skipped** |
| UI | `not_selected`，无 UI 产物；不能记为 UI 通过 |

唯一被选择且通过的方法为：

```text
SiteTests/DuelSceneBasePassDiagnosticTests/
testInstalledBaseSceneSeparatesSceneKitShadowAndSurfaceWithoutAdvancing
```

[该 Swift 文件](https://github.com/wuyong9494-lab/kriswu/blob/00442b097747d95308ca69339fa999a46c216bc6/Tests/SiteTests/DuelSceneBasePassDiagnosticTests.swift)的 SHA-256 为 `fddd9166fb0902a4e96e23f74b750b2e64ff4c0d9a116fa4b3a237201c5efc61`。原生调用回执记录 `exitCode=0`、`selectedCount=1`、`iterations=1`；确切方法、次数及所属模拟器经过结果门禁核对。**以上计数来自公共 job 日志中的实际 `nativeObservedCounts`，并非由 overall success 推导。**

同一源提交共登记 12 个 workflow runs：本入口实际执行，其余 11 个均为 `completed / skipped`，这些 skipped 不是新增通过证据。

## 构建、资源与证据门禁

| 阶段 | 实际结果 | 北京时间（2026-11-15） |
|---|---|---|
| 源码与唯一新方法身份 | success | 09:10:19—09:10:20 |
| 工具链选择 | success | 09:10:20—09:10:28 |
| 既有资源认证与 staging | success | 09:10:28—09:10:36 |
| SiteTests host 构建及 373 项编译资源核验 | success | 09:10:36—09:14:54 |
| 专用模拟器准备 | success | 09:14:54—09:16:31 |
| 唯一新方法及完整运行区间日志门禁 | success | 09:16:31—09:20:26 |
| 六张原图与报告导出 | success | 09:20:26—09:20:27 |
| 加密封存 | success | 09:20:27—09:20:28 |
| 诊断密文上传 | success | 09:20:28—09:20:30 |
| 本次模拟器、暂存媒体、构建产物和明文清理 | success，错误数 0 | 09:20:30—09:20:39 |
| 最终公开报告 | success | 09:20:39 |

资源继续固定于 `h17-shared-root-floorfall-20261115-v2`，release SHA-256 为 `e5c0ccaeef85ce86c5b8fd4ee64524794d6556f5a561f4078362f6899bedf4e5`，增量 manifest 为 `d50b7fc6f711a55849b259b0f78d348612782f5e3765f9629db50291e20fe2b9`。

既有 295 项 overlay 通过同一 13 项增量形成 302 项最终 overlay，其中 289 项保持原字节；与 73 项基础文件合并时替换两项，最终 **373 项编译资源均通过字节核验**。本次没有重转原媒体、上传新的资源版本或上传 TestFlight。

封存的 mandatory 证据为 **6 PNG＋1 report JSON＋1 manifest，共 8 文件、2,977,401 B，遗漏 0 文件**。方法／设备归属、956×440 尺寸、实际 PNG 摘要与报告元数据关联，以及封存闭包均由固定 helper 校验。自动附件不能补足 mandatory 覆盖。唯一独立消费者已完成工件认证，**52 个文件、0 个验证失败**，确切方法与设备、资源、日志和附件门禁全部核对通过；随后对六张原图分别复核。

## 六路实际原图：四路可见、两路完全透明

所有截图均固定在 frame 0、animation tick 0、source live tick 0。正常战斗 advance 调用数与 display-link callback 数均为 0；源特效包数为 0，源投影在六张截图期间均移除。**源投影与 SceneKit 灯光的 `castsShadow` 是两个独立变量**，报告逐项记录，不能混为一个“阴影已关闭”状态。

| 截图标签 | 渲染路径 | SceneKit 原 key light 阴影 | surface 请求→实际采样 | snapshot 请求 | 原图复核 |
|---|---|---|---|---|---|
| `base-scene-original-4x` | 原 surface `captureFrame` | 开 | 2→4 | 不适用 | 孙、刘双锤、宫殿可见；摘要 A |
| `base-scene-no-scenekit-shadow-4x` | 原 surface `captureFrame` | 关 | 2→4 | 不适用 | 可见，与首图逐字节一致；A |
| `base-scene-no-scenekit-shadow-1x` | 原 surface `captureFrame` | 关 | 1→1 | 不适用 | 孙、刘双锤、宫殿可见；B |
| `base-scene-snapshot-no-scenekit-shadow` | 新 `SCNRenderer.snapshot`，共用原 scene／camera | 关 | 不适用 | `multisampling4X` | `EMPTY_TRANSPARENT`；C |
| `base-scene-snapshot-original` | 同一新 renderer snapshot | 恢复开 | 不适用 | `multisampling4X` | `EMPTY_TRANSPARENT`，与前图一致；C |
| `base-scene-restored-4x` | 原 surface `captureFrame` | 恢复开 | 2→4 | 不适用 | 可见，与首图逐字节一致；A |

| 摘要标识 | 字节数 | 原 PNG SHA-256 | 原字节像素统计 |
|---|---:|---|---|
| A（三张） | 726,546 | `ea3ca6a4aa89543a04d111f1cdf8f3b764245c295a364833ff987d3f02f8f7b7` | 43,022 种 RGBA；alpha 全为 255；2,357 个不透明黑像素 |
| B（一张） | 714,726 | `6486f12d0992790f38ca2348e511d91246753969f61bb2119b827f21f71b1a5a` | 42,226 种 RGBA；alpha 全为 255；2,699 个不透明黑像素 |
| C（两张） | 7,671 | `78ec085230b4b223d2ba4ee6e7aeefe21a40995e007d67456f3f0a81fafaf60a` | **420,640／420,640 像素全部 RGBA(0,0,0,0)** |

像素统计只读取原 PNG，没有修改原字节。C 是完全透明输出，不能因查看器背景把它写成黑场；此前 `cdd0d496…` 的黑图为 **RGBA(0,0,0,255)**，两种结果明确不同。

snapshot 的 `multisampling4X` 仅是所请求的抗锯齿模式；其内部实际采样数没有被查询，相关 surface 采样字段必须明确为 `null`，不能把请求写成实际观测。

模型相机变换、FOV、类别遮罩与游戏状态保持不变；source projector、key light 和临时 fresh renderer 的恢复／释放断言实际通过，活动时钟从 0 回到 0。本次 `restoredPNGEqualsOriginal=true`，与首尾原图摘要一致；该字段是**观察值**，门禁并未强制它为 true。

六个样点均为 `firstBirth / 0`、入场拥有者仍在、0 个特效包、0 个 display-link 回调，`sameScene` 和 `samePointOfView` 均为 true。模型与 presentation 相机变换一致，FOV 均为 24.689624786376953。宫殿的可见且在视锥内几何体为 24；孙节点为 9，刘节点为 6。各路统计相同，却有两张完全透明图片，因此这些节点／视锥查询**不能代替渲染像素证据**。

**本实验内，SceneKit key light 阴影开关没有改变 4× surface 图像，1× surface 也可见，因而不支持用该阴影开关解释这组输出差异。具体生产故障仍未定位。** 所有六路都预先移除了 source projector，没有覆盖正常生产组合；隔离 frame 0 可见不等于生产已经修复，也不能据此直接认定删除 projector 就是修复。fresh snapshot 的全透明结果要按实际通路继续定位，不能冒充一个已成功的替代渲染入口。

另一个初始条件差异是：本次在第一张 surface 图之前，已经创建 fresh `SCNRenderer` 并关联原 scene／eye；旧 cdd 诊断没有该步骤。因此跨 run 同时改变了首次 projector 接入与额外 renderer 注册，不能只凭两批原图认定其中一个是根因。下一项最小对照将不创建 fresh renderer，保留同一原 surface，分别取正常 projector、移除 projector、同一 active renderer 实际 prepare 之后的基础图、恢复 projector 后的完整图。准备目标与实际显示 renderer 的静态差异已发现，但尚无其导致旧黑场的因果结论。

## 时间与运行日志的已知范围

公共进程计时记录 `native-build` 为 **257.118 s**，`selected-native` 为 **170.748 s**，均退出 0。认证的方法日志给出 XCTest 方法耗时 **101.725 s**，内部诊断总计 **101.569031 s**。170.748 秒属于整个 `xcodebuild test` 进程，不能与单方法或纯 GPU 时间混用。

| 内部分段 | 本次墙钟耗时 |
|---|---:|
| 构造真实 session | 16.779859 s |
| 构造真实 world | 77.917317 s |
| 挂载 layout／构造 fresh renderer | 0.002709 s／0.000342 s |
| frame 0 draw submission | 2.066015 s |
| 原 surface 4× capture | 0.574404 s |
| 关闭 SceneKit 灯光阴影后的 surface 4× | 0.927846 s |
| 同条件 surface 1× | 0.103203 s |
| fresh snapshot，灯光阴影关闭／恢复 | 0.774893 s／0.136243 s |
| 恢复原 surface 4× capture | 0.015045 s |

这次调用的主要耗时在构造阶段；它们是可继续定位的实际分段，不是此前 UI 超时的已证实完整原因。本次没有战斗步进或实时 display-link 驱动，capture 包含同步 readback／snapshot 完成等待，不能从这些数值推导实时 FPS、独立 GPU 时间或真机性能通过。

完整运行日志请求区间为北京时间 **09:17:10—09:20:06**；App 实际记录起止为 **09:18:08.700082—09:19:56.290646**。封存前完整解析并扫描的源日志为 **10,488,737 B、7,951 条 JSON，7,951 条属于本次 App**，SHA-256 为：

`fd31bc7fe9216a6bec6bba5b9a9cf7a32890dfff8392cf8d01117ba0439e5250`

完整、非空、所属模拟器及时间范围门禁通过。已定义的 `doublePresent` 和 `textureAfterPresent` 两类诊断均为 **0**，这只说明本次定义的两类问题未出现，不能扩展为所有 GPU 问题或像素正确性的证明。

受保护工件对每份文本日志只保留最后最多 **2,097,152 B**，公开 summary 明确 `sealedTextTailOnly=true`。实际运行日志尾部为 2,097,152 B，SHA-256 为 `c0955e0d2a610ce17934fc95a8e9dfc80e381616d672eb3faa471f82940c0383`，已与认证证据清单核对。完整源的扫描回执与归档尾部是不同证据，不能从尾部内容替代整段任意错误搜索。

## 历史证据不并入本次计数

| 历史运行 | 原源提交 | 原有结果 | 本次选择 |
|---|---|---|---|
| [43611931466](https://github.com/wuyong9494-lab/kriswu/actions/runs/43611931466) | `ef3064085879c497d59533459c94b429a40f9cee` | 历史 117 项通过 | 否 |
| [43644209347](https://github.com/wuyong9494-lab/kriswu/actions/runs/43644209347) | `68f1e7de45351c3e4b2607c56ff8ab111d0c7130` | 历史 5 项通过 | 否 |
| [43647414701](https://github.com/wuyong9494-lab/kriswu/actions/runs/43647414701) | `5788ebb1001a6e0f31c5208cb2b955b48b00741c` | 历史 6 项通过；该运行视觉失败 | 否 |
| [43658526616](fighter-entrance-render-run-43658526616.md) | `cdd0d496bf63fd186de6f8d9cf91646c1dc88917` | 历史入场诊断 1 项通过；六图视觉 FAILED | 否 |

此前 `cdd0d496…` 诊断在 frame 394 释放入场拥有者、武器和枝蔓逻辑可用，但 no-FX／scene-only 图仍全黑。它与当前零步进基础场景实验是不同范围，不能合写成当前通过两项。

[真实 UI 运行 43652056280](fighter-shared-root-ui-remediation-run-43652056280.md)仍为 **0 PASS／1 FAIL／0 SKIP**，失败在 `ember-practice-ready`。本次 UI 未选择；原生 offscreen 方法通过没有证明该实时流程已恢复。刘泉纬实际 profile 仍是 `liu_hammers`，不代表盘古独立资源已激活；实际可听音效、音画同步、完整角色机制、真实 iPhone 17 Pro Max 与性能验收仍待完成。

## 证据摘要与下一步

| 项目 | 已核身份 |
|---|---|
| [加密 artifact 14140921845](https://github.com/wuyong9494-lab/kriswu/actions/runs/43661312798/artifacts/14140921845) | `fighter-scene-base-diagnostic-43661312798-1-encrypted`；**6,449,261 B** |
| artifact SHA-256 | `55f1f432011e8e0d7f3d671335fce4c85125d3a0c50e77d43750fe569285a44d` |
| artifact 创建时间（北京时间） | `2026-11-15 09:20:30` |
| 诊断 report JSON | 64,005 B；`e6c1c865cbef3f72eb802e0c2f9713b96a801679ea800ac21efe85f4769b2aa3` |
| 附件 manifest | 3,690 B；`d52ede2f52639feeaaa184b137af75885d8a6702554b92f0004de1a7344294d5` |
| 实际方法日志 | 134,383 B；`7332ffca3b4254a36bd4cc7bc3e6be7e7d2abdc2184df31b8b5072ee82dd4936` |
| [新 helper](https://github.com/wuyong9494-lab/kriswu/blob/00442b097747d95308ca69339fa999a46c216bc6/.github/scripts/fighter_scene_base_diagnostic.py) | `b42aa509fe8459fd47e9d4c4191226cbb93b85c5e2452a8855adb87cb272db90` |
| [新 workflow](https://github.com/wuyong9494-lab/kriswu/blob/00442b097747d95308ca69339fa999a46c216bc6/.github/workflows/fighter-scene-base-diagnostic.yml) | `ab93d7b70e2c41e49d0c1c2f1c39e5bf204ef4b4695207d4f66c8372e1bc45bd` |

指定唯一消费者已完成认证和原图复核；本报告复用其已解封证据，没有再次下载或解密工件。公开记录只含标识、摘要、数值和观察结论，不含解密密钥、原媒体或私有绝对路径。本次没有自动重跑任何任务，也没有修改生产渲染代码。后续须比较正常生产组合与这次隔离实验，依据具体证据选择最小修复；**当前生产画面、实时 UI、可听音效和真机性能仍未完成验收。**
