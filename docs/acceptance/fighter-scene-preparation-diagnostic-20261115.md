# 同一渲染器准备与原投影器四图诊断（2026-11-15）

**执行前设计，不代表方法已运行或生产黑场已经修复。** 本项承接 [00442 的六图结果](fighter-scene-base-run-43661312798.md)：原 surface 在移除 source projector 时可见，SceneKit 灯影开关三图相同；fresh snapshot 的两张输出全透明。该实验在首图前还创建了 fresh renderer，所以不能把跨运行差异只归因于 projector。

生产 App／Core 仍保留 `532fb03083da7053417b7ad7ba484a99e4c41c28` 的字节。本项 source gate 以 `00442b097747d95308ca69339fa999a46c216bc6` 为保留基线，新增一个测试及独立入口；不修改其他 Sites 保护的渲染文件。

## 唯一新方法与固定条件

```text
SiteTests/DuelScenePreparationDiagnosticTests/testInstalledScenePreparationAndProjectorAreIsolatedWithoutAdvancing
```

测试使用同一个真实 `DuelWorldView`、原 surface 及其原 `SCNRenderer`、scene、camera 和 source projector。没有 fresh renderer，没有 snapshot 调用，也没有战斗状态注入。固定 frame／animationTick／sourceLiveTick 为 0，正常推进调用数和显示时钟回调数均为 0，源 FX packets 为 0。方向光设置、模型与相机模型变换保持不变。

| 原 PNG 标签 | 原投影器 | 实际 renderer.prepare 已调用 |
|---|---|---|
| `prep-original-before` | 原对象安装，正常完整路径 | 否 |
| `prep-no-projector-before` | 测试内临时移除，原对象强保留 | 否 |
| `prep-no-projector-after` | 仍移除 | 是，恰好一次同步 prepare |
| `prep-original-after` | 恢复同一个原对象，正常完整路径 | 是 |

所有原图为 956×440，经同一 surface 的真实 capture 路径取得。测试记录 active renderer 准备的实际目标身份、返回值和耗时，不把请求发出记成准备成功。若准备失败，尽可能先保留四图，再按真实失败处理。截图摘要、字节数、方法及模拟器归属与诊断 JSON 逐项绑定。

投影器正常安装的首图与末图是真实完整组合；中间两图仅用于区分基础 SceneKit 与投影合成。恢复对象、scene／camera 身份、状态和时钟清理是严格门禁；图像内容仍须人工独立核对。

## 为什么检查准备目标

当前 `App/Views/DuelWorld.swift` 的音乐与网络准备入口调用继承自 `SCNView` 的 prepare；实际显示经 `triadRenderSurface.sceneRenderer`。这是静态可确认的目标差异。离线时钟启动与异步准备的先后也不保证首次完整绘制前准备完成。

Apple 的 [prepare(_:completionHandler:)](https://developer.apple.com/documentation/scenekit/scnscenerenderer/prepare%28_%3Acompletionhandler%3A%29) 与 [prepare(_:shouldAbortBlock:)](https://developer.apple.com/documentation/scenekit/scnscenerenderer/prepare%28_%3Ashouldabortblock%3A%29) 文档说明该操作预载给定场景的几何、材质和 GPU 资源。本次同步 prepare 只用于有界诊断，**不是将同步阻塞搬进生产帧循环的修复方案**。目标差异尚未被证明是旧黑场的原因。

若同一 renderer 的基础图在 prepare 后恢复，并且恢复 projector 的完整图也可见，才支持从 World 的准备目标和完成身份着手修复。若一恢复 projector 又黑，则必须继续区分投影或合成通路。如果首张完整图已经可见，不能把可见结果归功于后面尚未执行的 prepare。

## 执行与证据边界

既有认证资源、release `h17-shared-root-floorfall-20261115-v2`、373 项编译资源及加密措施保持相同；不重转或重复上传资源，不上传 TestFlight。新工作流只选择上述一个新方法一次，UI 为 `not_selected`。历史 117、5、6 项、cdd 的完整入场方法及 00442 的六图方法均保留原结果，不再选择或并入新计数。

唯一新报告为 `scene-preparation-diagnostic-report`，schema 为 `fighter-scene-preparation-diagnostic-v1`。四张原 PNG、报告和 manifest 在同一个有界密文工件内封存；完整调用区间日志与归档尾部分开标记。实际执行源 SHA、方法计数、运行链接和原图结论须由后续结果报告补充。

自动报告保持 `pixels=PENDING`。诊断方法通过、完整生产画面可见、实时 UI、可听音效、性能以及 iPhone 17 Pro Max 真机分别验收。刘仍是 `liu_hammers / isPangu=false`，本项没有补齐 D19 独立模型、长斧和专属动作资源。

## 提交前新检查

18 项本入口离线检查首次执行全部通过（0.251 秒，0 失败）；这是新入口的选法、归属、失败保留、资源隔离和四图证据合同验证，不属于 Apple 执行。日志 SHA-256 为 `08d1e4c57d36d286759a9377091716ef913d2f1c2bc01abe5b541425e3028f61`。新 Swift 静态独立审阅没有发现确定类型或 actor 隔离缺陷；真实 Apple 编译与方法结果仍待本次工作流取得。
