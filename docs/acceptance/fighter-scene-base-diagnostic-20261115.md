# SceneKit 基础场景第 0 帧诊断（2026-11-15）

**执行前范围记录：本文件不代表新的 Apple 方法已经运行。** 前一项[完整入场诊断 43658526616](fighter-entrance-render-run-43658526616.md)实际为 1 PASS／0 FAIL／0 SKIP，但原始图片视觉 FAILED。它证明正常推进至第 394 帧可解锁；移除源特效及投影仍然全黑。三个全黑原图的 420,640 个像素均为不透明黑色，不能用图片透明度或前景森林单独解释。

## 为什么新增这一项

生产 `App/Views/DuelWorld.swift` 的方向光启用了 SceneKit 自带阴影。现有合成基础颜色／深度测试没有这盏灯；真实大厅的相应光源也没有启用这个分支。这是可核对的配置差异，**还不是已确认根因**。本项只比较它与原 surface、独立 `SCNRenderer.snapshot` 的输出，不预先关闭生产阴影或修改其他 Sites 正在处理的渲染文件。

唯一新方法位于 [`DuelSceneBasePassDiagnosticTests.swift`](../../Tests/SiteTests/DuelSceneBasePassDiagnosticTests.swift)：

```text
SiteTests/DuelSceneBasePassDiagnosticTests/testInstalledBaseSceneSeparatesSceneKitShadowAndSurfaceWithoutAdvancing
```

Swift 文件 SHA-256：`fddd9166fb0902a4e96e23f74b750b2e64ff4c0d9a116fa4b3a237201c5efc61`。

## 固定对照与证据边界

真实资源 release 沿用 `h17-shared-root-floorfall-20261115-v2`，摘要 `e5c0ccaeef85ce86c5b8fd4ee64524794d6556f5a561f4078362f6899bedf4e5`。App／Core 字节仍等于 `532fb03083da7053417b7ad7ba484a99e4c41c28`；新增源门禁以 `cdd0d496bf63fd186de6f8d9cf91646c1dc88917` 的全部既有 App、Tests、CI 为保留基线。

整个方法保持游戏第 0 帧，正常推进调用数 0、显示回调数 0，不注入状态。所有截图均临时移除独立 source projector，源特效绘制包数必须为 0。只切换一盏既有 SceneKit 方向光的 `castsShadow`；灯本身、光照参数、模型、资源、相机模型变换及 FOV 不变。

| 顺序／标签 | 渲染入口 | SceneKit 方向光阴影 | 采样记录 |
|---|---|---|---|
| `base-scene-original-4x` | 原 surface | 原值 true | 请求 2，模拟器实际映射 4 |
| `base-scene-no-scenekit-shadow-4x` | 原 surface | false | 4 |
| `base-scene-no-scenekit-shadow-1x` | 原 surface | false | 1 |
| `base-scene-snapshot-no-scenekit-shadow` | 新 SCNRenderer，同 device／scene／eye | false | snapshot 请求 multisampling4X |
| `base-scene-snapshot-original` | 同一新 SCNRenderer | 恢复 true | snapshot 请求 multisampling4X |
| `base-scene-restored-4x` | 原 surface | 恢复 true | 4 |

每次变更使用禁用隐式动画的零时长事务并 flush。原 source projector 强引用保留，在 World 清理之前恢复；新 renderer 随后释放 scene 与相机引用。最后一图与第一图是否相同是观测结果，不强制相等：snapshot 可能影响共享呈现状态，差异也必须被保留。模型状态不变、真实恢复与资源清理仍是严格断言。

每张原始 PNG 为 956×440；报告 `fighter-scene-base-pass-diagnostic-v1` 逐项关联标签、方法、模拟器、帧、字节数及 SHA-256。相机模型／呈现变换、投影、裁剪结果、节点可见性、角色包围盒中心和灯光状态均记录。模型包围盒中心不是蒙皮像素边界；frustum 或节点可见性不能自动变成画面通过。snapshot 的底层采样数没有被实测，不能用请求值虚构实际值。

## 单次执行约束

独立入口为 [`fighter_scene_base_diagnostic.py`](../../.github/scripts/fighter_scene_base_diagnostic.py) 与[工作流](../../.github/workflows/fighter-scene-base-diagnostic.yml)。它只选择上面的新方法一次，只构建 SiteTests host；UI 为 `not_selected`。历史 117、5、6 项及刚通过的 394 步诊断均不选择，也不合并计数。

沿用现有受保护环境及三个已授权资源 secret，仅 staging 可见；373 项安装资源使用原版本并逐字节校验。没有新资源版本或 TestFlight 上传。确切 6 PNG、JSON 报告和 manifest 在同一有界密文工件内封存，完整调用区间日志在封存前扫描两类已知 drawable 诊断；归档尾部与完整源日志分开标记。空结果、跳过、错误方法／设备、缺图或未恢复状态不能通过门禁。

本次执行前仅完成：新 Swift 的一次 Linux Swift 6.0.3 `-frontend -parse`，exit 0；新独立 CI 的 **18 项离线门禁检查首次执行，18 PASS／0 FAIL／0 SKIP，0.253 秒**。这些不是 Apple 类型检查、模拟器截图或真实设备证据。后续实际 run 必须另记精确 SHA、方法计数、原图结论和日志。

自动报告始终保留 `pixels=PENDING`，由后续原图审查独立更新视觉结论；实时 UI、可听音效、性能与 iPhone 17 Pro Max 真机仍需各自证据。刘当前仍为 `liu_hammers / isPangu=false`，本项不填补盘古独立资源缺口。
