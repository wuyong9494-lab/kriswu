# 四英雄开发接手与最小修复记录 · 2026-11-17

## 当前结论

本候选修复了可从现有源码、真实资源和明确失败路径确认的问题，并接续之前尚未提交的角色接入工作。**它不是「100% 还原」或发布验收通过记录。** 当前四英雄仍有原始资源、原生机制和设备验证阻塞；本次没有用别的英雄、猜测伤害常数或通用特效填补这些缺口。

源码基线为有效分支 `codex/fighter-visual-acceptance-20261113-1200` 的 `fbe1f97b947df6936eb9a1721510e92a178fb543`，候选分支为 `codex/fighter-completion-20261117`。提交前复核的最新 Actions 为 [44029477961](https://github.com/wuyong9494-lab/kriswu/actions/runs/44029477961)：成功准备受保护 recipient，仅证明该准备任务成功，未运行本候选 App 或四英雄原生验收。

采用独立工作目录接续已有未提交代码，原工作目录未改动。复用了已有资源验证结果和成功运行记录，没有重新运行重型恢复流程。此候选提交含 `[skip ci]`，不新增 workflow；环境审核、签名和 TestFlight 均未执行。

## 已落地的代码修复

| 问题与已确认影响 | 变更文件 | 修复后的边界 | 最小回归 |
|---|---|---|---|
| 可选 D13/D15/D20 profile、模型或媒体失败曾使整个角色资源初始化失败 | `App/Services/DuelLocalWeaponProfiles.swift`、`App/Services/DuelWeaponAssets.swift` | 按角色记录失败阶段并隔离；保留已验证的其他角色。签名基础包与共享资源的严格校验不放宽 | profile、GLB、媒体、延迟加载负例；坏 D13 不得恢复旧双锤刘泉纬 |
| 实际选择的两名角色可能未贯穿网络准备链路 | `App/Views/DuelNetworkRoomModel.swift`、`App/Views/DuelNetworkRoomView.swift`、`App/Views/DuelView.swift`、`App/Services/DuelNetworkCompatibilityIdentity.swift` | 使用确切的两名已验证角色、顺序及完整内容身份；缺失、重复或旧身份均拒绝准备 | 核心选择与握手负例；原生实际双角色准备 |
| D15 音频被计入网络内容身份，但创建网络 `DuelSourceEffects` 时没有传入 | `App/Services/DuelNetworkCompatibilityIdentity.swift`、`App/Services/DuelSourceEffects.swift` | 网络和本地路径传递同一已验证 D15 音频绑定 | 检查准备后的 effect 持有确切 actor/profile SHA 和音频文件集；声音播放仍需原生证据 |
| 新 D13 刘泉纬不能使用旧 `liu_hammers` 胜利 Morph；实际目标缺少绑定 | `App/Services/DuelTriadSourceMorphAssets.swift`、`App/Services/DuelSerpentAssetIdentity.swift`、`App/Services/DuelWeaponAssets.swift` | 增加严格 `liu_serpent` 目标，绑定实际 GLB SHA、全部六种材质和九个 primitive；沿用原 mask、触发和时序。变形依赖失败仅阻止对应角色对 | 完整材质、错误身份/头盔/ItemType/旧材质负例；真实 Metal 安装、140 tick 变形及取消恢复 |
| 重新开始时加载失败可能沿 `try?` 落入无原始武器的通用模拟 | `App/Views/DuelView.swift` | 原始武器模式未构造出真实战斗时保留旧局、暂停并报错，不安装替代战斗 | 损坏真实模型后释放缓存、重新加载、restart；旧局不被替换且不继续推进 |
| 大厅已经显示的身份可能掩盖稍后发生的模型失败，界面一直显示准备中 | `App/Views/DuelLobbyPreview.swift`、`App/Views/DuelHomeView.swift` | 失败优先于旧身份快照；展示受限的角色校验失败状态并禁用该角色，避免泄露内部路径 | 迟发模型失败、旧快照失效、没有回退角色 |
| 既有恢复模型、D13 原始瓶子和刚性头部边界尚未完成接入 | `DuelErlangAssetIdentity.swift`、`DuelSerpentBottleAssets.swift`、`DuelDisplayedSkinBounds.swift`、`DuelWorld.swift`、`Sources/ShiftCore/DuelSerpentBottlePresentation.swift`、`project.yml` | 接续已有真实资源绑定、来源瓶子动作展示和头部取景边界修复；展示读取不改变战斗/replay | 瓶子源动作 FK 与生命周期核心测试、SceneKit/材质/取景原生测试 |

上述表格记录代码行为与准备的回归，不表示 App 已成功编译或设备运行通过。生产加载器仍要求原始 profile 身份、外部固定 SHA、目录注册、文件白名单、完整性、骨架和动作验证；没有加入「显示姓名正确即可接受其他模型」的路径。

## 四名角色与当前资源身份

| 人物 | 枚举 / profile | 当前真实模型 | 字节数 | 静态资源事实 | 当前验收边界 |
|---|---|---|---:|---|---|
| 刘泉纬 | `.liu` / `liu_serpent` / D13 | `Liu_KingOfSerpents_D13_Recovered_Combat.glb` | 15,561,412 | glTF v2；80 关节；66 动画；真实 SHA 已核对 | 已接入候选代码；本候选原生成功加载尚未验证；Bloom/第五毒等机制未闭合 |
| 孙登 | `.ember` / `sun_triad` / H17 | `Sun_DeadForestTriad_Ninjato.glb` | 16,252,036 | 当前版 87 关节、70 动画；不能套用旧 65 动画模型的验收 | 当前模型的原生动作、胜利 Morph 和完整双机战斗仍需验证 |
| 吴庸（二郎神） | `.wuYong` / `wuyong_erlang` / D15 | `WuYong_Erlang_D15_Recovered_Combat.glb` | 18,956,368 | glTF v2；80 关节；62 动画；伙伴、FX、音频清单已核对 | 已接入候选代码；Noise/有符号 Stretch/HIDE 完整语义仍未证明 |
| 徐骁（嬴政风格） | `.gale` / `xuxiao_founder` / D20 | 未发现完整专属战斗模型 | — | 有个人头部及共享骨架/动作候选，不能视为完整 D20 | 完整装备与动作资源不足；继续阻止作为完整战斗角色进入网络目录 |

三个当前角色模型 SHA-256：

- 刘泉纬：`f25b35dec9bf335bbe01ceee557389f47165c3d0b45b54502017fda394a8bd70`
- 孙登：`7c9ebfe285f637cbd002f717d80b859a57d3ab11ef491f15930dc4f3eb50d96a`
- 吴庸：`2957d7861b2ee7656945259dd273f241591ce55f71d364dab007a9bc372d76f6`

原 `SF3_FighterRelease.json` 的 SHA 为 `527e0195b7911e5b532aec92c37057f36a633952768670518565bde65605cbd3`，其认证范围是原 H17/旧刘泉纬基础目录；D13 与 D15 使用独立固定身份，不能宣称该 release 已认证它们。旧资源保留不等于允许选角或运行时静默回退。

## 最小资源增量

本次只增加 `SF3_H17_SerpentMorph.json`，12,479 B，SHA-256 `f2b3ab352b6a433fa7910fdc4c04508f9d1498c1933e4315269d2b77d10063bd`。原 GLB、UV、权重、动画、mask 和音频未因本增量修改。固定的 47 个旧 CMS 分片不重封装、不重复上传；原编译资源期望清单保持 540 项，单文件 overlay 后为 **541 项期望值**，这不是 Xcode 打包成功计数。

仓库仅包含新增密文及完整性元数据，位于 `.github/private/fighter-completion-20261117/`。新密文为 13,253 B，SHA-256 `8bd33a39113cb649aac05530c48c0a29bdf21a75d6e742e6196757fe36fdd630`，采用 AES-256-GCM 与 RSA-OAEP-SHA256。真实 recipient 私钥未读取或公开，真实 recipient 解密/安装尚未执行。详见 [增量使用与安全边界](fighter-completion-delta-20261117.md)。

旧 52 项上传计划仅记录预期对象身份，未发现完整成功上传收据，不能视为旧基础包已全部可供远端取得。需要先按对象身份核对缺项，才能安排受保护的原生 staging；本次不盲目重复上传。

## 已完成验证与明确未完成项

| 验证 | 本次结果 | 能证明什么 | 不能证明什么 |
|---|---|---|---|
| Linux Swift 6.4.2 核心测试 | **33 通过 / 0 失败 / 0 跳过** | 身份、选角、握手；真实 D13 瓶子 FK/生命周期与只读展示投影 | Apple App 类型检查、SceneKit/Metal、网络实际媒体加载或双机运行 |
| 修改/新增 Swift 语法解析 | **25 文件通过** | Swift 语法可解析 | Apple SDK 语义编译 |
| 加密增量便携回归 | **37 通过 / 0 失败** | 固定身份、540+1 并集、ZIP 边界、破坏负例、临时测试 key 的 GCM/OAEP 往返 | 真实 recipient 解密、完整生产 base staging |
| D13 Morph 源材质复核与负例 | 六材质/九 primitive 覆盖，八种破坏输入拒绝 | 新绑定不偷换角色/装备或套用双锤材质 | 原生 shader、渲染效果与视觉一致性 |
| 原生与 UI 最小回归 | **27 原生 + 1 UI，已准备，未执行** | 仅说明用例和准确选择器已落实 | 没有模拟器截图/运行日志或新原生通过结论 |
| 双机与 iPhone 17 Pro Max 真机 | **未执行** | 无 | 网络实战、视频、帧时间、内存、温升等均未验收 |

核心测试首先因缓存模块记录旧绝对路径而在执行前失败；仅清理独立目录的模块缓存后重试成功。未修改原目录或为了通过而调整测试断言。后续核对相关源文件 SHA 未变，未重复运行已成功的测试。

详细记录：

- [33 项核心验证与源文件 SHA](fighter-completion-validation-20261117.json)
- [37 项加密增量回归](fighter-completion-delta-validation-20261117.json)
- [27 原生 + 1 UI 最小计划](fighter-completion-native-plan-20261117.json)
- [原始机制证据与未闭合条件](fighter-completion-mechanisms-20261117.json)

原生计划要求 **0 失败且 0 跳过**，目标为既有计划中的 Xcode 26.6 / iOS 26.5 / iPhone 17 Pro Max 模拟器。模拟器型号不能替代真机验收。旧的未提交原生 helper 草稿仍固定旧分支和 14 个用例，且缺少对应 workflow；本次未发布该草稿，也没有将其描述为执行本计划的工具。

## 距离完整还原仍需关闭的阻塞

1. **D20 原始输入缺失。** 尚缺五项真实装备目标与 37 项指定动作；需要实际资源目录响应或可认证的原始缓存/索引，随后完成完整身体、骨架、装备、动作、FX/音频绑定。个人头部加共享动作不能证明专属模型完成。
2. **D13 完整机制证据不足。** Bloom 第五存量的 `0.66` 与 420 tick 是创建可用条件，不能直接解释为 66% 生命伤害。必须补齐实际装备/等级/遭遇对应的 MagicPower、BodyDefense 与继承公式，模型触碰、KEY/ANIM 清理和终帧删除的原生事件顺序，以及满 Bloom 的实际身体切换链。现有源证据表明 D13/D15/H17 均有专属能量路径，不能直接扣通用 energy 代替影能效果。
3. **D15 完整特效语义不足。** 当前 67/79 个发射器已覆盖；其余包含三个 Noise 和九个有符号 Stretch/shape 相关项，还需要原始随机映射、组合次序、符号拉伸、父节点和 HIDE/淡出生命周期证据。不能改为绝对值拉伸或通用噪声后标记还原。
4. **原生资源安装与执行未完成。** 先核对基础对象是否已上传，再在受保护入口安装真实 540 项 base 与一项 delta，执行 27+1 用例。当前 Linux 环境没有 Apple SDK/Xcode；这一步没有发生。
5. **双机与真机证据缺失。** 需要实际两台设备的选角、握手、动作/技能/胜利/重开流程，以及 iPhone 17 Pro Max 视频和帧时间、内存、温升等采集。没有这些证据，不提升为发布通过。

这些是可定位的剩余条件；本记录没有给出缺少证据的百分比。只有对应文件、真实加载、动作运行和设备证据全部闭合后，才能重新评估完整还原与发布状态。
