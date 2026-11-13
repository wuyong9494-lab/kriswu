# 连续投锤、镜头后继与真实资源验收交接

本轮继续分支：`codex/fighter-visual-acceptance-20261113-1200`；当前游戏代码整合点为
`5462aad48b6d3add4b19125f507f7ffa0a476e38`。后续文档提交不另外计作代码测试。
不要从默认 `main` 或旧资源分支重新开始。

**已经完成连续投锤规则修复，33 项定向核心/回放回归通过；当前真实资源原生测试、截图与真机验收仍未执行。**
GitHub 在分配 runner 前拒绝该分支进入现有 `fighter-private-assets` 环境。不能把这次失败记为资源加载、模型或 native 测试失败，不能把未运行记成通过。

## 代码与证据承接

| 承接点 | 实际含义 |
| --- | --- |
| `a0657d3f42141d673e37e4afd3a41354d644ddfc` | 已核对的历史 dot 标记维护基线，保留 Build 702 相关记录。 |
| `4dd788e3b7b35943ea06f1714dd8ba02a572d636` | 上一轮 107 核心、22 合成原生与 16 网络规则检查的确切源码范围。 |
| `7d320d590b7772928b89b7d0f9e6ad4193ee29fb` | 上一轮文档交接，不能额外计作新的测试执行。 |
| `a452990f7f777b96ffdb323f744643542615daf8` → `b68977017c205f29f50bb3619dbd7695385edd52` | 三个镜头文件精确整合；b689 的两个父提交是 7d320d5 与 a452990f。无效蒙皮几何保留此前安全的较宽视角，并保留失败状态。 |
| `77ccd5f3cc2a1ccae18fd0fd98c4a435fd67da14` | 将工作目录从不支持 `runner` context 的 job env 移入 prepare 步骤；随后触及现有环境分支限制。 |
| `02d4e83e6bcd7e1018225c4fd66037c97f72b6cc` | 连续投锤与折叠扫掠修复。33 项实测的 214 文件源清单逐项匹配此提交，发布使用 `[skip ci]`。 |
| `201a203b75242bdcdd4536a92d7bf27ef3395d38` | 后续自动开发的相机空/不完整包围盒保护，直接父提交为 77ccd5f；只有两个 App/native test 文件，无远端执行通过证据。 |
| `5462aad48b6d3add4b19125f507f7ffa0a476e38` | 双父为 02d4e83 与 201a203；精确保留 201a 两文件，增加第十一项定向 native selector。214 文件核心闭包不变。 |

最新整合源码与上述受测源码的关系以 [来源绑定记录](validation/fighter-visual-20261113-source-binding.json) 为准。
201a 的空 check/status 集合不能解释成构建运行中。复用历史证据必须保留原 SHA、运行环境与测试范围；不重跑完整工作流，不把旧 107/22 迁移成当前全部通过。

## 本轮实际修复

### 双锤释放与接回

`DuelWeaponFight` 和 `DuelWeaponShadow` 现在共同使用源动作的武器 base/tip。技能 tick 24 的脱手点对，等于原有整数映射公式对应的 heavy 持锤姿态；tick 71 的接回点对等于施法者当前位置上的相应持锤姿态。这里的 24/71 是**应用技能 tick**，不是原始动画帧号，也不表示已经恢复原版技能事件表。

出击仍在 24–47 tick，48–71 为无伤回程，技能总长仍为 96 tick。能量 100、冷却 360、伤害 195、单次命中与打断规则保持。出击目标仍以旧的 `origin ± 5.25m` 绝对位置为限，受墙边约束，不从新的手位另加射程。每 tick 保留该相位的实际锤长；接近反向的轴向通过确定性中间方向衔接，避免归一化零向量。

起手受到身体推挤时，释放 origin 更新到实际 post-separation 位置；24 tick 后冻结，不改写已经飞出的轨迹。回程接向当前手位。零长、非有限或无法安全换算为毫米的端点关闭脱手表现与碰撞，不回退固定假轨迹。真实模型、trail、攻击框与接触使用同一端点路径。

这改变了实际空间接触，因此 `DuelReplayStateEncoding.rulesVersion` 升为 **3**；`schemaVersion` 仍为 **2**，没有新增序列化状态字段或改变线包布局。不能复用 Build 702 的网络身份来冒充当前规则。

### 折叠扫掠漏碰

独立代码复核找到了第一版四边形填充在旋转折叠时的确定漏碰反例，已在最终测试前替换。当前算法检查真实 shaft 与端点路径，并对 hurt box 的四个角解析求出移动 shaft 相交时间，最多检查八个二次方程候选根，再代回有限线段确认。

保留原 0.18m 接触半径、0.75m 双端连续性门限和深度条件。近线性、双根切触、镜像、仅支持线相交的假根，以及精确折叠反例均有定向回归。没有用宽 AABB/凸包填充或无界子步代替窄相判定。接触反馈点取实际 shaft 接触位置，而非固定高度。

### 镜头防护

已整合 a452 的安全 FOV 保留逻辑。201a 另为 `DuelDisplayedSkinBounds.verticalFOV` 加入空数组与非 16 倍数采样的拒绝条件，新增 native 方法检查 0/15/17 点拒绝、16 点保持与扩宽；两个文件已在 5462aad 精确整合，Git blobs 与 201a 相同。此方法尚未执行；源码解析成功不等于 SceneKit 编译或模拟器通过。

这项总点数保护不单独证明“双角色各自都贡献了完整几何”；当一方缺失而另一方仍提供完整块时，仍需在真实模型/生产镜头场景验证各自身份和边界。不能仅用总数通过替代该验收。

## 已执行验证：分开记录

| 证据 | 实际结果 | 适用范围 |
| --- | --- | --- |
| [最终连续投锤核心结果](validation/hammer-anchor-final-core-replay.json) | 33/33，失败 0、跳过 0、缺失/额外/重复方法 0 | Linux Swift 核心；16 shadow、2 replay golden、15 network replay。 |
| 同一轮 [日志](validation/hammer-anchor-final-core-replay.log) / [源清单](validation/hammer-anchor-final-core-replay.sha256) | 2026-11-13 04:36:00–04:36:48 UTC；北京时间 12:36；命令 48.004s，增量构建 0.32s，测试 45.98s | 214 文件在执行前后不变，且逐项匹配 02d4e83。不是 iOS 构建时长或 60fps 数据。 |
| [镜头安全 FOV 单方法结果](validation/camera-failed-skin-core-summary.json) | 1/1；命令 15.287s，构建 13.33s | a452 对应核心函数的独立检查，未并入上述 33 计数；真实失败注入/恢复方法仍待执行。 |
| [原验收辅助脚本检查](validation/fighter-visual-helper-validation.json) | 24 个本地合成检查 | 原十方法配置、标签、封装、双接收方与失败清理。不是模型/原生验收。 |
| [诊断封装检查](validation/fighter-visual-diagnostics-validation.json) | 7 个本地合成检查 | 严格导出门禁不放宽；异常附件排除后仍能密封允许的失败诊断；不上传异常 crash 内容。 |
| [十一方法选择器检查](validation/fighter-visual-eleven-selector-validation.json) | 13 个定向检查 | 支持命名 Swift extension；拒绝缺失/额外/重复/跳过与旧十项结果。加密与清理代码不变，未重跑加密检查或 native。 |
| [空采样后继核对](validation/camera-empty-envelope-review.json) | 两文件解析通过，blob 与 201a 一致 | 源码/解析证据；native 未执行。核心 214 文件闭包保持。 |

第一版投锤补丁的 18 项和临时单方法结果不计入最终 33；最终折叠修复后的结果是上表唯一计数依据。后继相机/App 文件不在该 SwiftPM 源清单中，证据可按未变的核心闭包复用，不能扩大为未执行的 native 通过。

## 两次未开始原生执行的真实记录

完整 API 摘录保存在 [失败阶段记录](validation/fighter-visual-attempts-20261113.json)。

| 运行 | 阶段与证据 | 原生方法 / 图片 |
| --- | --- | --- |
| [43364628039](https://github.com/wuyong9494-lab/kriswu/actions/runs/43364628039) | b689；没有 job。源码复核发现 job env 使用不支持的 runner context，77ccd5f 已修。未取得这一轮的服务器错误 annotation，不能伪称原文。 | 0 / 0 |
| [43364818020 / job 131686634923](https://github.com/wuyong9494-lab/kriswu/actions/runs/43364818020/job/131686634923) | 77ccd5f；没有 runner，steps 为空。GitHub 原始 annotation 明确拒绝此分支使用 fighter-private-assets。 | 0 / 0 |

第二轮原文：

> Branch "codex/fighter-visual-acceptance-20261113-1200" is not allowed to deploy to fighter-private-assets due to environment protection rules.

运行创建到结果记录共 4 秒、job 记录间隔 3 秒，是平台拒绝阶段的时间，**不是构建或原生运行耗时**。资源 staging、unsigned build、模拟器测试与截图导出均未开始。

需仓库环境管理员允许上述**确切分支**使用现有 `fighter-private-assets` 环境，保留其 reviewers、secret 与其他保护规则。未自动修改环境、移除 environment、借用旧获准分支或以重试绕过限制。放行后应以最新整合源码执行新一轮定向验证，不重跑已经过期的 77ccd5f。

## 下一轮：11 个指定方法、26 张图片、3 份数据附件

两个历史失败运行计划为 **10** 个方法。201a 新增一个无图几何检查，下一轮才是 **11** 个；图片与数据数量不变。精确选择器、类型及标签以 `.github/scripts/fighter_visual_acceptance.py` 的 `SELECTED`、`IMAGE_LABELS`、`DATA_LABELS` 为准。

| 指定方法 | 证据类型与局限 |
| --- | --- |
| `DuelWeaponAssetTests/testPersonalHeadFollowsBodyFacingAndSourceNeckAnimation` | 真实角色层级与头颈跟随断言。 |
| `DuelWeaponAssetTests/testRenderBothDistinctSourceBodiesWeaponsAndPersonalHeads` | 4 张真实模型、固定中性正交测试场景图；不是生产镜头。 |
| `DuelSourceEffectsTests/testActualHitAndBlockRenderFreezePauseAndRelease` | 3 张认证源纹理、合成接触事件图；不能冒充实际对局接触。 |
| `DuelWeaponEffectsTests/testSourceWeaponTrailsRenderAtRealEndpointsAndFreezeAndRelease` | 5 张认证纹理图，但 endpoint poses 为合成输入；方法名不能取代范围说明。 |
| `DuelWeaponGameplayTests/testActualSourceWeaponHeavyAndKickHitInBothDirectionsWithoutCrossingBodies` | 真实资源目录与权威核心接触断言。 |
| `DuelWeaponGameplayTests/testEquippedSessionsShowRealHitsPauseRestartAndReleaseTheirScenes` | 6 张真实角色、宫殿、真实接触与生产 world/camera 图。 |
| `DuelShadowPresentationTests/testRealHammerTravelsBothWaysAndRestoresWithoutAccumulatingOrReplacingMesh` | 真实蒙皮武器、当前应用影技规则的完整周期断言。 |
| `DuelShadowPresentationTests/testBothShadowFamiliesUseVerifiedSourceEffectsAndReleaseTheirTrails` | 认证源纹理和权威影技姿态的生命周期检查。 |
| `DuelWeaponGameplayTests/testRealOpticalFitRetainsLensOnInvalidSkinAndRecovers` | 真实资源/生产镜头，人工注入 skin 失败后恢复，2 份文本证据。 |
| `DuelShadowPresentationTests/testRealShadowReleaseAndCatchBoundariesRenderForBothFacings` | 双朝向技能 tick 23/24/71/72，共 8 张真实模型固定测试镜头图及 1 份 world 端点数据；不代表生产镜头已验收。 |
| `DuelWeaponAssetTests/testEmptyOrPartialSkinEnvelopeCannotClaimSuccessfulOpticalFit` | 合成相机包围盒几何，无图片；检查 201a 新保护条件。 |

只进行一次 unsigned test-host build，使用一个已安装的 iPhone 17 Pro Max **模拟器**，`test-without-building` 运行精确方法集合，无重复迭代。不会重复 SwiftPM 107、既有合成 22、完整资源回归或全 UI 流程，也不签名上传游戏。

64 个既有 sf3/sf3-distinct 文件分别记录 manifest、加密 parts、期望/实际大小与哈希、失败原因。staged/bundle 哈希通过仅证明文件完整；每个文件是否被显示、播放或使用，仍由具体场景断言界定。音乐、全部声音可听效果、无障碍实机操作和稳定 60fps 不在这 11 方法内。

只有新产生的证据会密封：保留原接收方并使用本次固定公钥接收方；随机输出密钥采用既有 FIGHTER1 加密封装并由 RSA-OAEP-SHA256 包裹。源资源加密措施和密钥不变。仅上传密文与校验和，保留期三天；不上传原始资源、App、原始 xcresult、用户参考视频、解密私钥或明文截图。资源密钥仅进入 staging 步骤，不进入后续构建/测试/封装。

## 五项目标仍然需要同源画面验收

[原版参考与五项差距](fighter-visual-fidelity-2026-11-13.md) 保留了已经核对的原视频内容、实现责任文件和最小继续路径。用户原录屏没有公开上传；其中通知、系统/加载和直播叠层片段不作为干净战斗参考。30fps 录屏不能证明原游戏或当前游戏稳定 60fps。

| 目标 | 本轮推进 | 下一项有效证据 |
| --- | --- | --- |
| 人物比例 | 已整合安全镜头与缺失采样保护；保留源模型/绑定 | 同姿态头身比、脚底接地、轮廓、武器尺度、真实生产镜头占屏关系。 |
| 人物质感 | 既有真实 PBR / 源材质路径保持 | 固定姿态、镜头、曝光比较皮肤/布料/金属与接缝；未依据猜测调亮或提高所有纹理上限。 |
| 打击质感 | 接触点跟随实际扫掠，防漏碰/假碰，回程无伤 | 真实轻/重击、格挡、挥空的画面与声音、停顿、受击/击退同步。 |
| 技能质感 | 源相位脱手/回手与确定性回放有核心证据 | 真实 tick 边界图与完整动作录屏；原版编舞、333 变身与预制喊声仍未验收。 |
| 特效质感 | mesh/trail/contact 共享端点，生命周期保护保留 | 同相位亮度、宽度、消退、遮挡、占屏比例；真实资源截图尚无新增。 |

每个问题继续记录源码 SHA、资源及分块引用、实际加载结果/失败原因、修复文件、独立修复提交、精确回归、模拟器画面、无障碍检查、真机结果、性能与构建时间。未得到的结果保留为空或待验证。

Build 702 的历史 `VALID / IN_BETA_TESTING` 记录与已有功能保持；本轮未重新查询 Apple 状态、未上传 TestFlight、未创建游戏 Release，也没有重复上传任何既有资源对象。
