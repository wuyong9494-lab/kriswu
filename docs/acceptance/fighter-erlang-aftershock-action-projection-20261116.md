# D15 余震：a46 参数投射与对象池父级

日期：2026-11-16。范围：原件的有界静态读取与文档更新。

本轮闭合了原 `a46` 到 `LAFOIKNPFAE` 参数对象的执行路径，以及命名特效池设置父级的直接调用。余震 start 的原始粒子产物仍为 `sourceOnly=true`、`runtimeBound=false`、`groundParentTransformVerified=false`；没有重新导出资源、修改 App / Identity、激活生产特效或运行原客户端。

本文续接 [条件化特效库存](fighter-erlang-conditioned-fx-inventory-20261115.md) 中“余震根矩阵的有界原生读取”一节。那一节保留当时尚未闭合的历史边界；以下为本轮新增证据。

## 原件与读取范围

原 Mach-O SHA-256 为 `7c192647b0e035bd246c135a59c597ee3910d50fc4ed128abe402da39a62a55b`，metadata SHA-256 为 `12d52d278c904b210541e7c337025c68454e2b89a83eddab51f9c74fcc5a245c`，与此前恢复原件一致。

本轮读取 29 个明确地址窗口，共 18,820 bytes 原生代码，涉及 **32 个不同方法体**。同一 dispatcher 的三个局部窗口只计一个方法；因编译布局相邻而实际读到的五个方法则分别计数，没有把它们藏在一个大区间里省略。达到约定上限后停止读取。方法身份依据原 metadata / module pointer 表核对，未进行全程序调用者扫描。

公开文档不包含原指令转储、完整动作参数数组、原媒体或解码参数。完整原件读取片段及逐字段证明保留在独立的本轮证据收据中。

## a46 的真实执行路径

原 dispatcher 直接使用动作记录的 raw case 选择跳转表项，没有把注册顺序当作 case。case 46 进入 `0x6ba2744`，构造 wrapper 29439（`0x6f20a7c`），再调用 consumer 29489（`0x6f235c4`）。consumer 构造参数对象 182174（`0x383aea4`），并把同一对象传给 `EffectsManager.PlayCustomEffect` 34369。

完整读取的 consumer 与同一 wrapper 的 16 个字段 getter 共同支持下列结论。

| 参数或行为 | 已直接核实的结果 |
| --- | --- |
| Camera、AttachToLocal | 原字段未提供时，各自的 bool getter 返回 false。两者是独立字段。 |
| Follow 未提供 | getter 返回无值的 nullable vector；参数构造器不启用 Follow。 |
| 本余震动作提供的零 Follow 向量 | 构造器检查 nullable 是否有值，并与 `Vector3.zero` 比较；零向量不会置位 FollowEnabled。不能把它解释为“已启用跟随，只是三个系数为零”。 |
| YMax / YMin 未提供 | 分别取正无穷与负无穷；不是隐含的地面高度或零。 |
| Position 未提供 | 取 `Vector3.zero`。该初始位置随后仍会被已审启动方法覆盖。 |
| 位置回调 | consumer 新建参数对象；构造器及随后直接播放路径未给它设置回调。 |
| Looped | 独立写入自己的参数字段，不代表 AttachToLocal 或 FollowEnabled。 |
| Additional / Params | 原动作没有请求条目；consumer 对列表数量和 nullable 值分别设有门槛，没有因此生成额外的位置回调。 |

结合此前已读的 34309 附着更新，本动作的 AttachToLocal 与 FollowEnabled 均为 false 时，会在 Y 限制、回调和根位置写入之前退出。因此，这一更新方法不会在后续 tick 主动用骨位置改写根位置。**这不等于证明特效的世界位置永远不变**：其父级之后是否变化仍是独立问题。

### ApplyTo 与 Pool 必须分开

参数对象 `LAFOIKNPFAE +0x68` 来自 **ApplyTo（字段 4）**，同时参与目标解析。它不是 Pool（字段 5）。播放方法根据该值选择是否使用目标 model id，并不能据此把它命名为 Pool。

Frames、Pool、SingleInstance 的 getter 均已读取，但完整 consumer 29489 没有调用这三个 getter。它们在准备阶段或其它生命周期路径的用途，本轮没有闭合；“当前执行 consumer 未读取”不能被写成“原引擎完全忽略这些字段”。

## 命名特效池的父级已定位

实际路径为播放方法 34225 调用 34219 取命名池内可用实例；需要补充实例时进入 34212、池构造器 34394 和分配方法 34395。

| 原方法 | 本轮读到的直接行为 |
| --- | --- |
| 34212 / 34394 | 从 `AnimationEffects` 保存的字段取得 parent Transform 与 provider，再保存在对应命名池中。 |
| 34395 | 调用已注入 provider，取得返回对象中的 effect 实例，调用其虚方法，随后对实际 GameObject 的 Transform 调用 `SetParent(poolParent, false)`。 |
| 34342 `EffectsManager.Initialize` | 取得自身 `Component.transform`，把它作为 parent 传给 34204。 |
| 34204 | 把收到的 Transform 保存为 `AnimationEffects._parentTransform`，另存 provider。 |

因此，已知这条池路径的 parent 身份来自 **EffectsManager 自身的 Transform**，并且原调用显式传入 `worldPositionStays=false`。它不是从 portable actor GLB 根或 ground_locator 名称反推出来的父级。

这里仍没有证明 provider 返回之前的 clone / Awake / effect 构造顺序，也没有证明该实例构造时缓存的 local rotation / scale 必然等于 prefab 的作者值。34395 调用返回对象中的 effect，并不等于本轮已经读到它的构造过程；虚方法调用也不能在未读取实现时当作无操作。

此前 34303 的原件证据继续成立：启动流程明确覆盖根 `position`，最终采用指定骨的世界位置与调整后的偏移。未来绑定时不能再次叠加 prefab 根的 authoring translation；这不授权删除子节点的原始局部变换。

## 仍需证明的边界与下一入口

尚未闭合的内容包括：provider 内部的实例创建和构造缓存顺序；池设置父级之前的 effect 虚方法行为；EffectsManager Transform 的完整生命周期；FME `+0xc8` 与 ground_locator 父级后续的 parent / rotation / scale 写入。已知父级身份与调用参数，不足以推出这些 Transform 在整个生命周期始终恒等。

下一次最窄直接入口为 **34341 `EffectsManager.SetDependencies`，地址 `0x705cd54`**，本轮没有读取其方法体。首先只确认一个事实：**实际注入 EffectsManager `+0x80` 的 provider 是哪一个具体实现**。已知该接口为 `MLGMIPEFMLK`（type 6709），其方法 37085 在 34395 中被调用；无需为此扫描全程序调用者。

在上述问题闭合之前，可把本轮已证 defaults 保存为新的 source-only 语义收据；不能据此更改现有采样矩阵或激活运行时绑定。

## 交付与实际验证

| 收据或产物 | Bytes | SHA-256 |
| --- | ---: | --- |
| 本轮方法窗口收据 | 15,643 | `efc8d5f315589e5919f9c56064dd10828e113d6189b1fedf03051d1f1bf20d28` |
| 本轮参数 / 池父级证明 | 9,894 | `5c571392d29d020da91c3f32bfaea3e6a484249b4e19fd34c8e0562143aa9d4d` |
| 保持不变的 `D15_AftershockStart_Source.json.gz` | 3,612 | `33930d1e1ed3721e0aadafb50773b96feb6e56e2b78e4a4d3216f2b80d65ed83` |
| 保持不变的源导出收据 | 9,028 | `7989f776bd35b1df53e90934f9c3afa2d0a42caa3c302213c49f0ed642e2e270` |

本轮完成的是原件静态读取和已记录文件的完整性核对。没有重跑先前已通过的测试，没有执行 App、原客户端、Apple GPU 或 TestFlight 流程。现有两层源轨迹、authoring hierarchy 与生产状态保持原样。
