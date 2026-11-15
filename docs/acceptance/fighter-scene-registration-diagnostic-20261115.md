# 同场景注册与首次投影接入四图对照（2026-11-15）

**这是执行前设计，不是渲染修复或验收通过。** 上一项 [Run 43664242283](fighter-scene-preparation-run-43664242283.md) 的真实方法 1 PASS，但四图全部为不透明纯黑；原活动 renderer 的一次同步 prepare 返回 true（53.877 ms）也没有改变画面。此次不继续采用“单独 prepare 即可修复”的方案。

源基准为 `4bd85374273b39f61724342b7e1d72631ab2042d`，App/Core 仍保持 `532fb03083da7053417b7ad7ba484a99e4c41c28`。上一轮 00442 的原 surface 隔离图曾可见，但首图前同时存在“移除原 projector”和“新建并关联 fresh renderer”两项条件。两个实际报告的相机 model/presentation、投影、viewport、三灯共同字段、模型共同字段、usesReverseZ、default lighting 和 playing 值一致，不能凭猜测修改这些设置。

## 唯一新方法

```text
SiteTests/DuelSceneRegistrationDiagnosticTests/testInstalledSceneRegistrationChangesAreIsolatedAtFrameZero
```

使用同一真实 World、原 surface、原活动 renderer、scene、eye 和原 projector。World 构造、挂载和布局保持原行为；在测试的唯一显式 drawState 前移除 projector，并记录该时点原 surface 已提交 drawable 的数量。显式调用计数不能代替整个 World 生命周期的调用计数。全程 frame、animationTick、sourceLiveTick、displayLink callbacks 与 source packets 均为 0。

| 四张原图 | 原 projector | 原 renderer 重绑 scene 次数 | fresh renderer 状态 |
|---|---|---:|---|
| `registration-base-before` | 移除，原对象保留 | 0 | 尚未创建 |
| `registration-original-projector` | 恢复同一实例 | 0 | 尚未创建 |
| `registration-original-rebound` | 保持安装 | 1 | 尚未创建 |
| `registration-fresh-associated` | 保持安装 | 1 | 仅创建并关联同 scene/eye |

A → B 只恢复原 projector，由其真实 encodeMap 路径采样；B → C 仅把原活动 renderer.scene 暂时置空再绑定同一 scene/eye，并提交零动画事务；C → D 只创建第二个 renderer 并关联同 scene/eye，复用旧六图相同的 reverseZ/lighting/playing/delegate 配置。四次原图始终来自原 surface。没有 fresh render、snapshot、prepare、采样切换、模型材质改动或游戏推进。

第一张图保留的 projector lastFrame 可能尚不存在，它只作为观察；随后三张必须记录真正原 projector 的有效元数据。对象身份、模型相机、灯和游戏状态不变；每张图的原字节、尺寸、方法、设备和捕获阶段都须绑定。PNG 是否相同只作观察，不把“同图”当作成功条件。

D 之后再解除 fresh renderer 的 scene/eye/delegate 绑定并释放本测试强引用，恢复全部原对象后正常 shutdown。此处只证明测试所有权与绑定清理，不将其冒充 ARC 已析构证据；没有“fresh 释放后画面仍可见”的截图。

## 如何使用结果

- A 已可见：补齐了无 fresh 的基础图证据，不能再说 fresh 是基础显示的必要条件。B 判断首次接回原 projector 后的真实完整组合。
- B 黑、C 可见：支持以同一活动 renderer 的场景重新绑定为最小修复候选；还须验证生产接入和后续交互。
- C 黑、D 可见：只支持第二 renderer 关联产生副作用，不能把生产保留无用途 renderer 当作已验证修复。
- 四图都黑：这些注册操作不足以恢复本次 renderer，应保留失败，不能继续把相同操作重跑为新的成功证据。

任何图可见都不能单独替代实时 UI、完整入场/技能、音画同步、性能或 iPhone 17 Pro Max 真机验收。原始四图另行人工审查，自动报告继续 `pixels=PENDING`。

## 执行限制

只新增一个方法与独立 CI 入口。原有成功的 117、5、6 项及 cdd/00442/4bd 的三个诊断方法均不再选择。既有 release `h17-shared-root-floorfall-20261115-v2`、373 编译资源与三个受保护 stage 密钥保持；不重复上传资源、不上传 TestFlight。生产代码及其他 Sites 正在处理的文件保持原样。

报告标签 `scene-registration-diagnostic-report`，schema `fighter-scene-registration-diagnostic-v1`；实际执行 source SHA、run、计数、清理与四图结论由后续结果报告补充。刘仍为 `liu_hammers / isPangu=false`，本项没有补齐 D19 独占 11 文件、12 动作别名及 5 装备。

## 提交前首次检查

本入口的 18 项新离线检查首次执行均通过（0.359 秒，0 失败），覆盖选法、源树、失败保留、四图归属及注册操作合同。日志 SHA-256 为 `de9c9416f849173be986e82cb6214c346d829c399c9d1867748ff8a4b6e97e31`。这些检查不属于 Apple 方法或像素验收；真实类型检查与执行结果由新工作流另行取得。
