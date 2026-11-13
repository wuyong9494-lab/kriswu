# 原版视频的五项还原目标与当前实现

以下原有实现表以游戏源码 `4dd788e3b7b35943ea06f1714dd8ba02a572d636` 为历史核对点。
后续镜头整合、连续投锤规则、定向核心验证及真实资源验收，见
`fighter-visual-acceptance-2026-11-13.md`；不得将下表的历史结果自动迁移到后继源码。
用户明确要求的五项目标是：**人物比例、人物质感、打击质感、技能质感、特效质感**。
五项都有已有实现基础，尚未通过本轮真实角色录屏与原版参考的逐项视觉/手感对照。
107 项核心与 22 项合成模拟器原生测试通过，不能替代这五项验收。

## 本轮普通拖尾修正，原生 / 画面尚待验证

`da689f81d6138cac8657f88193d185b97ad60a16` 已修正普通 endpoint ribbon 错用装备 atlas 的材质职责，
并将透明纹理跨度与真实消退年龄分离；shadow、碰撞、时序和生产人物灯光保持。
这是现有条带适配修正，没有恢复缺失的原 skinned trail mesh / 原 UV。
新的 [四方法 / 七图方案](fighter-trail-followup-2026-11-13.md) 已提交，run 43377027433 绑定 bf3e677，
当前等待受保护环境审核，实际 native 0 / 新图 0。三份 Swift 语法解析、源码审查与 12 项 helper 检查
不替代 Apple SDK 编译、Metal 输出和视觉签收。下面 26 张图继续是 2206 的修复前证据。

高光复核区分棚拍白 ambient650/omni1100 与生产偏蓝 ambient520/directional1250/fill180；
原棚拍还缺少显式 HDR / 曝光锁定，因此未把棚拍白脸直接归因于生产材质，也未整体调暗人物。

## 2206 的新增实际画面证据

环境已获准，`43369559706` 对源码 `2206a5fe26a8b0c9f6217d6f11eca8fcc31474fc`
执行了 11 个指定 native 方法：10 通过、1 失败、0 跳过，26 张图和 3 份数据完整。
全部原图已逐张查看；[本次报告](fighter-visual-review-43369559706.md) 区分真实模型棚拍、
生产战斗镜头、动作边界和合成接触 / 端点场景。

当前已观察到的品质缺口包括棚拍脸部 / 金属细节偏白、普通武器拖尾显示装备 atlas
纹样及硬边三角扇形、部分返回边界青蓝长条的遮挡仍需连续动作复核。
源纹理哈希和“有可见像素”的自动化通过没有证明这些画面已经还原。
失败方法是影技拖尾 retained 总数断言；当前发射者与淡出历史必须分别验收，
不能为了总数等于两把武器而删除正确历史。五项目标继续保持待视觉 / 连续音画验收。

## 参考已恢复，使用范围已纠正

已找回此前用户提供的原版《暗影格斗4》参考录屏，并以只读方式核对实际文件：
43.800 秒、1112×512、H.264、30/1 FPS，含 AAC 音轨。本轮查看的是指定时间点及
3.7–4.4 秒每 0.1 秒的取帧序列，未宣称完成逐帧全片标定、音频对齐或当前 App 对照。
视频内容只作参考，不进入公开仓库或游戏资源；参考原文来自 `2bef149d52fecb51c3de3c9e04cc84b11a578837`。
取帧复核和历史窗口的修正在 `fighter-video-reference-20261113.md`。

实际可观察的视觉关系包括：装备/衣料分层、明确的人物剪影；青蓝轨迹沿武器方向运动；
金色接触闪光短促出现，和青蓝轨迹分开；竹林、木板、火光与前中后景有层次。
这些观察不证明原 shader、命中事件表或源游戏帧率。

20 秒包含通知，22–33 秒包含加载/系统界面，37 秒出现直播 UI，38 秒为系统通知，
均不能作为干净战斗品质样本。17–19 秒还出现重复/停滞姿势，不能把它的持续时间当作
原游戏的 hit-stop 或技能时间。30 FPS 录屏也不能用于证明游戏稳定 60fps。

视频中的长兵器对战并不一一对应孙登武士刀与刘泉纬双锤。还原应保留目标各自已核实的
源骨架、武器和动作，用原片的比例、材质与效果层次作质量参照，不套用其他技能的时间线。

## 当前实现与未完成项

| 用户目标 | 已有代码基础 | 仍未通过的部分 |
| --- | --- | --- |
| 人物比例 | `DuelWeaponCharacterInstance.restorePersonalBindSpace()` 纠正已认证头颈网格的绑定外层变换；保留几何和源骨架。源 pelvis 高度、6 tick 回 idle 混合、真实蒙皮/武器边界驱动的镜头已有实现。 | 当前真实角色在同动作相位的头身关系、占屏身高、脚底接地、轮廓与武器尺度对照。镜头不裁切不能等同人物比例已还原。 |
| 人物质感 | `GLTFModel.material(...)` 有 base color、normal、metallic/roughness、emissive、透明模式、采样和 lightmap；武器角色使用 PBR，部分认证源材质恢复剔除、过滤及 wrap 状态。后侧 fill 为白色 180。 | 完整源 `Nekki/CharacterShader`、色彩管理、皮肤/布料/金属分离、头颈接缝与实际光照对照。战斗 ambient 仍偏蓝；当前纹理 1024 上限是否损失细节待画面证据，不能先认定为根因。 |
| 打击质感 | 确认接触驱动 hit/block、受击/倒地、击退、当前应用 hit-stop、方向性镜头 recoil、源贴图 burst 与命中/格挡声；重复 draw 不重复消费事件。本轮跳变过滤防止假命中与假挥击。 | 同相位画面/声音中的接触、停顿、受击姿态、击退和声音同步。当前格挡/普通/重击的 2/3/5 gameplay tick 是应用规则，并非原片恢复值。双锤专用挥动声未验证，当前 `playWhoosh(.dualHammers)` 为 `break`。 |
| 技能质感 | `DuelShadowRules` 已实现孙登有界冲刺、刘泉纬右锤投掷，包含能量、冷却、起手/有效/恢复、单次命中、无伤返回、打断与 replay。 | 原版技能编舞和事件表尚未恢复。当前身体复用各自 heavy clip 并按技能时长重采样；抛出/接回边界仍需真实模型逐帧审查。333 模型变身、完整适配和预制喊声也未完成。 |
| 特效质感 | 真实 base/tip 采样形成独立武器 trail；本轮 0.75m 连续性、缺失 tick 断段、模板预热/释放通过 4 项合成 SceneKit 方法；已有 dashGlow/dashNoise/hammerFire 纹理与曲线。 | 亮度、层次、宽度、长度、消退、遮挡和屏幕占比尚未与原片对齐。命中亮闪是 billboard burst，没有按命中创建动态 `SCNLight`；完整场景光照反馈、原 Unity FX 事件表均不能宣称已还原。 |

## 最小文件级继续路径

任何修改先绑定同一个源码、资源哈希、设备与构建，不因看到质量缺口就盲目改全部参数。

1. **人物比例**：先执行真实资源的
   `DuelWeaponAssetTests.testPersonalHeadFollowsBodyFacingAndSourceNeckAnimation` 与
   `testRenderBothDistinctSourceBodiesWeaponsAndPersonalHeads`，捕获站姿、近身、跳跃、倒地、
   武器极值。绑定问题定位 `App/Services/DuelWeaponAssets.swift`；镜头占屏问题定位
   `App/Views/DuelWorld.swift` / `Sources/ShiftCore/DuelCameraFraming.swift`；不要用肢体缩放
   掩盖镜头或绑定错误。
2. **人物质感**：固定姿势、镜头和曝光，分别对比皮肤、布料、金属、武器与头颈接缝。
   最小责任点为 `App/Services/GLTFModel.swift` 的材质构建、`DuelWeaponAssets.swift` 的
   已认证材质状态、`DuelWorld.swift` 的灯光。`GLTFMaterialTests` 保护计算正确性，
   不能替代真实角色画面。不要统一提亮整个场景或无依据增大全部纹理。
3. **打击质感**：分别采集轻击、重击、格挡、挥空的完整事件和画面/声音。
   对应 `DuelWeaponFight.applyHit`、`DuelCombatCamera.consume`、
   `App/Services/DuelSourceEffects.swift`。真实资源入口为
   `DuelSourceEffectsTests.testActualHitAndBlockRenderFreezePauseAndRelease`、
   `DuelWeaponGameplayTests.testActualSourceWeaponHeavyAndKickHitInBothDirectionsWithoutCrossingBodies`。
   双锤专用声只在取得已认证相应资源后接入，不能把武士刀声音冒充双锤原声。
4. **技能质感**：逐帧检查起手、释放、出击、返回、接回与被击中取消。
   责任点为 `Sources/ShiftCore/DuelWeaponShadow.swift`、`DuelWeaponFight.swift` 的
   `setShadowPose`，以及 `DuelWeaponAssets.swift` 的 `pose/restoreDetachedWeapon`。入口为
   `DuelShadowPresentationTests.testRealHammerTravelsBothWaysAndRestoresWithoutAccumulatingOrReplacingMesh`
   与 `testBothShadowFamiliesUseVerifiedSourceEffectsAndReleaseTheirTrails`。
   先修真实手/武器接回边界，再处理有证据支持的原动作编舞。
5. **特效质感**：同相位对照挥空、命中、格挡、连段和影技的整段生命周期。
   责任点为 `DuelWorldView.weaponEffectPoses`、`DuelWeaponEffects.consumeStep/canJoin/rebuild`
   和源曲线配置。入口为
   `DuelWeaponEffectsTests.testSourceWeaponTrailsRenderAtRealEndpointsAndFreezeAndRelease`。
   优先核对源纹理/曲线和骨骼端点，不以更大 bloom 或常驻亮弧替代正确时序与遮挡。

上述真实资源方法**不在历史 22 项合成原生回归内**；本次新增执行结果按 2206 独立登记。
若已有相同源码/配置/资源的成功证据，
先复用；需要新验证时只选当前修改相关范围，不重复整套重型 workflow。

## 场景材质与人物材质分开验收

`DuelStageAsset` 的历史宫殿/秋季修复在确切资源门禁后采用源位置颜色兼容路径：
主纹理 RGB ×（2 × 归一化顶点 RGB）× baked lightmap RGB，透明覆盖单独保留。
这不能证明人物 shader 已还原。秋季 `Matcup_mat` 涉及 `USE_MATCAP_LOCAL`，仍明确
排除在这次 RGB 修复外；fog、MatCap、动态效果、shadow lighting 与源 GPU 色彩行为
仍有独立缺口。`docs/fighter-scene-lighting-2026-11-08.md` 保留其历史原生证据与限制。

## 验收结果记录要求

每项同时记录：原版时间窗口、我方动作/事件 tick、源码 SHA、资源哈希/分块引用、
实际设备/系统/构建、同相位截图或视频、确认问题、最小修复提交、针对性回归结果。
本次新增了 26 张实际截图及其独立观察，但没有新增完整当前角色录屏、视觉通过结论、
双真机对局或稳定 60fps 数据。不能将“图片已取得”改写为“图片验收通过”。
Build 702 内测、加密资源安全措施及既有成功证据继续保留，不上传 TestFlight 或游戏版本。
