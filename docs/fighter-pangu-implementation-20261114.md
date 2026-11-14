# 刘泉纬盘古：机制接入与交付记录

记录日期：2026-11-14。本次开发基线：本地提交 `cabc2fc`；本文描述在该基线上完成的本地实现与验收边界，远程发布状态以本轮验收记录为准。

**记录范围：第 1—10 节保留上述早期基线的交付情况，不代表之后各批的当前发布状态。正式配置恢复后的专项更正见第 11—14 节；后续整批源码、资源和 Apple 验收状态见 [源恢复记录](DUEL_SOURCE_RESTORATION_20261114.md)。**

## 1. 本轮交付状态

盘古已具备独立的规则配置、1—6 级资源与技能状态机，并接入 `DuelWeaponFight` 的输入、碰撞、承伤、物理位移、回合生命周期与确定性回放。手机和外屏已接入盘古生命上限、光能与连击显示；网络选择和战斗校验已识别独立的 `liu_pangu` 身份。

**当前交付的是可由明确配置驱动、可进行真实 Fight 闭环验证的机制实现。原版完整参数、盘古模型、专属动作与石／风／柱特效尚未齐备，不能宣称“原版完全还原”或“当前发布版本已可完整游玩盘古”。** 测试目录中的盘古规则与动作是明确标识的合成夹具，用来验证实现边界，不是原版平衡配置或原版动作导出。

当前应用资源加载仍使用旧 `SF3_DistinctFighters.json` 的固定摘要与旧武器目录。新增盘古枚举不会把双锤改名为盘古，也不会自动开放未验证的盘古资源。主任务本轮读取的 Sites 状态仍为 `latest=11`、`updated=2026-11-13T13:24:46Z`；本轮没有写入 Sites。没有执行远程推送、iOS 构建或 TestFlight 发布；此前自动审批阻止了向公共分支推送，因此这些本地变更仍需按最终交付范围审阅。

代码依据：[盘古规则](../Sources/ShiftCore/DuelPanguRules.swift)、[盘古状态](../Sources/ShiftCore/DuelPanguState.swift)、[Fight 接入](../Sources/ShiftCore/DuelWeaponFight.swift)、[目录校验](../Sources/ShiftCore/DuelWeaponMotion.swift)、[原生资源加载](../App/Services/DuelWeaponAssets.swift)。原版证据边界见[机制参考](fighter-pangu-mechanics-reference-20261114.md)与[源审计](acceptance/fighter-pangu-source-audit-20261114.json)。

## 2. 配置与加载条件

`DuelPanguRules` 显式提供套装等级、最大生命、光能换算与回能量、连击门槛与增伤、每招起手／有效／收招时长、冷却、投射速度、范围、伤害类型、控制、击飞、风刃、天坠阶段和 Trance 参数。规则还记录来源类别、版本、证据和可选源摘要。来源类别包括项目适配、参考测量与源配置；填写来源标签本身不等于已经证明参数来自原版。

`liu_pangu` 目录必须同时提供 `combatRules` 和通过校验的 `panguRules`，只启用一侧武器轨，并绑定全部七个盘古动作角色：`panguShard`、`panguTyphoon`、`panguSplitter`、`panguBones`、`panguSpear`、`panguHeavenfall`、`panguStormGate`。缺少这些条件时目录被拒绝；旧武器档案也不能挂入盘古规则后继续以旧身份加载。

数值校验包含等级、生命和资源边界、时长与倍率范围、投射速度、接触体、可实现的攻速，以及天坠下落时长和高度／速度的一致性。配置错误在创建状态或加载目录时失败，不以零伤害、无限冷却或占位动作悄悄补齐。

尚未核实的原版判定使用独立策略字段表达，包括格挡是否计连击、原初被格挡是否授予 Rhythm、衍生命中是否回光／计数、风刃在起手还是命中时生成、多个风源是否叠加、门槛采用接触前还是接触后连击、Typhoon 固定冷却的优先级、Earth 窗口起点、天坠中断是否释放其石化，以及攻速叠加方式。**这些策略的可配置性解决工程接入问题；测试选定的策略仍需原版证据才能成为正式还原配置。**

## 3. 1—6 级能力与状态

等级按配置累加。下表记载当前代码能执行的关系；原版具体倍率、时长、门槛与尚未确定的判定不由本表补定。

| 等级 | 已接入的状态与行为 | 边界 |
|---|---|---|
| L1 | 光能与生命分别记账；实际命中可回光、累积并刷新连击，连击按规则增加指定伤害类型的输出；基础长矛使用充能；提供免投判定接口 | 光能换算、伤害乘区与最大生命均由配置给出。免投接口尚不等于完整的投技挣脱演出 |
| L2 | 四向原初招式、重击门槛风刃、Typhoon 持续状态、原初接触后 Rhythm、强化钉岩矛、分阶段天坠 | 风刃触发策略独立；挥空的原初招式不会因“已按下技能键”自动获得命中资源或 Rhythm |
| L3 | 普通回光增益；达到独立门槛后扩大可触发风刃的攻击范围 | L2 重击门槛和 L3 全攻击门槛是不同字段 |
| L4 | 前岩增伤与眩晕；风中 Light 消耗修正与限次背后瞬移；上挑增伤、追击风刃及 Dread；Earth 的跳跃落地震击和前岩徒手附伤分别计时；原初固定减冷却；连击门槛攻速 | Dread 属于目标状态。Earth 两个窗口、各风刃时序和 Typhoon 特例分别处理 |
| L5 | 原初命中的额外回光；实际被格挡接触可按等级与策略回光；连击门槛强化远程和充能恢复 | 格挡回光与格挡计连击相互独立；未命中不能冒充被格挡 |
| L6 | 受击保留连击并延长保持窗口；原初固定减冷却；达到门槛后原初零冷却与天坠冷却缩短；天坠增强回光／伤害／连击；限时 Trance 的攻速、防御、风刃和概率额外连击 | 已有冷却是否清除、Typhoon 优先级、Trance 获得阶段仍由策略明确给出；所有概率使用战斗随机源 |

L6 的“固定减少若干秒”已通过 `level6PrimordialCooldownReductionTicks` 与 L4 的固定减秒分别表示，转换为配置中的模拟 tick 后，在开始冷却时扣除。它与 `level6CooldownRecoveryBps` 表达的额外恢复速率是两个独立概念；后者保留为显式项目调节能力，不能代替原版固定减秒证据。Typhoon 是否接受各类缩减，以及达到零冷却门槛后的优先级，都需要策略选择。

免投方面，`DuelPanguState.throwImmune / canBeThrown` 与 `DuelWeaponFight.canBeThrown(_:)` 已提供资格判定。现有 equipped 控制没有投技命令及投掷接触链路，因此尚未完成原版“尝试投掷 → 自动挣脱／反制 → 对应演出”的闭环。后续仍需投技链路与原始投技、免投动作绑定。

代码依据：[状态机](../Sources/ShiftCore/DuelPanguState.swift)、[规则与策略](../Sources/ShiftCore/DuelPanguRules.swift)、[输入命令](../Sources/ShiftCore/DuelWeaponInput.swift)。原版逐级语义和证据等级见[机制参考第 3—5 节](fighter-pangu-mechanics-reference-20261114.md)。

## 4. 输入映射与可施放条件

盘古继续使用现有动作输入通道，通过相对朝向与方向组合选择招式。`shadow` 是输入命令名；盘古不会因此走旧武器的暗影攻击分支。方向以当前角色朝向解释，双方玩家席位使用同一套规则。

| 输入 | 盘古动作 | 绑定角色 | 最低等级 |
|---|---|---|---:|
| `shadow` ＋ 前 | 创世之石 / Shard of Creation | `panguShard` | 2 |
| `shadow` ＋ 后 | 原初风暴 / Primordial Typhoon | `panguTyphoon` | 2 |
| 风状态中再次 `shadow` ＋ 后，且符合次数限制 | 风暴之门 / Gates of the Storm | `panguStormGate` | 4 |
| `shadow` ＋ 上 | 劈开天际 / Horizon Splitter | `panguSplitter` | 2 |
| `shadow` ＋ 下 | 大地之骨 / Bones of the Earth | `panguBones` | 2 |
| `shadow` 且无方向 | 天坠 / Heavenfall | `panguHeavenfall` | 2 |
| `ranged` | 远古猎矛；按释放时资格选择普通／强化版本 | `panguSpear` | 1 |

输入采集保留按键边沿对应的方向，避免玩家松开方向后，已排队的四向技能被错误解释为无方向天坠。技能准入同时检查等级、冷却、光能、长矛充能、当前施放、瞬移周期次数、生命、正在执行的动作、硬控及离地／悬停状态。

受硬控、空中或不能施放时，不保留盘古技能键作为恢复后的隐式追发。旧目录继续使用原有输入与暗影技能路径。

代码依据：[输入采集](../Sources/ShiftCore/DuelWeaponInput.swift)、[技能映射与准入](../Sources/ShiftCore/DuelWeaponFight.swift)、[动作名称与角色](../Sources/ShiftCore/DuelPanguSpatialState.swift)。

## 5. 真实接触、资源与衍生伤害

`DuelPanguState` 负责资源与事件解释，`DuelWeaponFight` 负责实际命中。投石、长矛、风刃和地面伤害具有独立空间状态；绘制、按键或与目标持续重叠本身不会重复扣血。每次已确认接触进入单调递增的事件序列，状态层按接触 ID 去重，投射物在命中消费后不能再次结算同一次接触。

命中回光、连击和 Rhythm 由真实接触驱动。长矛在施放时记录强化资格，实际飞行并碰到对手后才结算伤害与钉岩控制；Rhythm 到期或被消费不会反向修改已经飞出的矛。风刃可按明确策略在起手或命中时生成，起手发射后仍须实际碰撞才造成伤害；不能把“风刃已经生成”直接算成命中。

衍生攻击保留来源和伤害类型。它们可以依配置回光或计连击，但不会递归创建新的 Rhythm、风刃、Dread 或石块附伤。Earth 的徒手附伤绑定原石块已经确认的目标与接触位置，因此施法者投石后跳走，也不会把附伤错误地变成施法者身边的一次近战判定。

承伤先经过明确的状态修正，再按配置将适用伤害转换为光能消耗，剩余部分进入生命；整数吸收容量与扣光采用一致的取整规则。风中 Light 消耗减免、Trance 来伤修正和目标 Dread 分属不同步骤。当前“光能不足部分溢出到生命”的实现是显式项目模型，原版是否存在其他耗尽规则仍须补证，不能由合成测试反推原版行为。

最大生命来自盘古规则，创建对局、练习模式恢复与回合重置使用同一值。**超时胜负按各角色剩余生命比例比较是本项目比赛规则**；采用整数交叉相乘保留细小差异，不宣称这就是原游戏的超时规则。

代码依据：[接触、承伤和结算](../Sources/ShiftCore/DuelWeaponFight.swift)、[资源与去重](../Sources/ShiftCore/DuelPanguState.swift)、[空间攻击](../Sources/ShiftCore/DuelPanguSpatialState.swift)。

## 6. 物理高度、控制与时间边界

上挑通过显式冲量让目标升空，在配置规定的顶点停留后恢复下落，接触地面后进入落地／恢复过程。硬控会中断不再有效的攻击、清除对应缓冲，并保留进入控制时的真实高度，避免空中受控目标突然贴地。Dread 的输出与承伤修正独立于石化、钉岩和眩晕的动作锁定。

天坠依次执行石化、上升、蓄能、下落和落地阶段。石化有空间范围门槛，不能隔着场地无条件锁住目标；升柱和下落使用物理高度，蓄能在完成的计时间隔中回光。`phaseStartedTick` 防止进入下落的同一 tick 提前下降；实际高度归零、`landing` 阶段及配置为落地触发的 Trance 保持同 tick。冲击伤害和对应起手策略风刃使用真正的落地时点与地面原点，尚未落地时不提前扣血。

Earth 的震地资格来自施法者自己的跳跃并在落地时消费。遭敌方攻击挑飞后落地不会获得这次震地。前岩附伤和自己跳跃震地分别验证，不共用一个模糊的“发生了落地”条件。

风中瞬移根据敌人位置、身体间距和场地边界选点，并重新确定朝向。位移后重置上一帧的接触坐标，避免把整个跨场位移当成武器或投射物扫过路径。对无法到达的敌后空间采用项目边界处理，原版的精确回退位置仍待确认。

空间状态使用独立的 live tick。Hit-stop 时资源计时、冷却、控制期限、悬停、升降、投射物位置与存活时间一并冻结，恢复后继续原进度。攻速增加只推进相应攻击的额外逻辑采样；每个跨越的逻辑帧都进行有效窗口判定，连招共享锚点先处理该帧接触再衔接下一段，避免加速跳过单帧命中或提前换招。世界计时与投射物不会随攻击加速多推进。

硬控／倒地及相应中断路径会取消尚未发射的追击风刃，即使原招式的动作已经结束，也不能让未发出的追击继续“死后发射”。已释放的投射物保留独立空间生命周期。终局清理当前空间攻击、控制、升降和待发事件；回合重置恢复该局资源、生命、充能及随机状态。

代码依据：[Fight 主循环与物理接入](../Sources/ShiftCore/DuelWeaponFight.swift)、[空间时间和升降状态](../Sources/ShiftCore/DuelPanguSpatialState.swift)、[中断与待发事件](../Sources/ShiftCore/DuelPanguState.swift)。

## 7. 随机、回放与网络身份

Trance 的概率额外连击使用有显式内部状态的种子随机源；不会由渲染帧、系统随机值或 Swift 哈希种子决定。相同目录、规则、开局种子与输入流应产生逐 tick 相同的规范回放字节。

当前回放编码版本为 **schema 4、rules 8**。编码包含规则和目录、光能／连击／冷却／充能、施放阶段、随机状态、事件去重标记、尚未发射的风刃，以及空间 live tick、控制期限和来源、升降及阶段开始 tick、投射物位置与期限、待处理事件、攻速余数和跳跃震地资格。版本号描述回放格式与模拟规则，不代表原游戏版本。

网络层为盘古使用独立 `liu_pangu`，保留旧 `liu_hammers`。可选项从通过校验的实际目录生成；开局校验还要求角色所选武器 ID 与该目录档案完全一致。载入双锤目录时不会因为协议已识别盘古 ID 就开放盘古，也不能用双锤资源满足盘古选择。网络合成测试沿真实主机输入／编码路径覆盖两个席位，并不更改发布资源摘要。

当前发布加载器仍固定旧目录摘要 `c4ee840d89cf1b2b8b82db0aebce878dbc5c2f2f60a52cf5b5a77b84f139ed5f`。新盘古规则、经过核验的模型／动作绑定与资源清单必须一并进入新的目录和兼容性身份后，才能成为真实发布选项。

代码依据：[回放编码](../Sources/ShiftCore/DuelReplayState.swift)、[状态编码与随机源](../Sources/ShiftCore/DuelPanguState.swift)、[空间状态编码](../Sources/ShiftCore/DuelPanguSpatialState.swift)、[武器选择](../Sources/ShiftCore/DuelMultiplayerSelection.swift)、[开局匹配校验](../Sources/ShiftCore/DuelNetworkCombatProtocol.swift)、[原生兼容性身份](../App/Services/DuelNetworkCompatibilityIdentity.swift)。

## 8. 手机、外屏与原生表现

手机与外屏 HUD 使用同一场 Fight 的当前生命、配置最大生命、光能及连击。手机动作就绪信息根据当前方向所对应的盘古招式，显示等级不足、冷却、光能不足、长矛充能、施放中或可施放，并提供对应动作的辅助功能标签。HUD 接入不绕过目录准入：只有实际载入盘古档案才出现相应盘古状态。

盘古石块、风刃、石柱等原始 FX 尚未取得可验证资产，因此目前没有宣称已完成这些招式的 native 特效绘制。现有双锤／武士刀的已认证武器轨迹不会用于盘古；`DuelWorld` 明确阻止盘古进入该旧轨迹绑定。声音分派也使用独立 `panguHit`、`panguBlock`、`panguWhoosh` 键，不回退到旧锤音。独立键和接口不表示相应原版音频已经补齐。

代码依据：[手机 HUD 与按钮就绪](../App/Views/DuelView.swift)、[外屏 HUD](../App/Views/DuelTelevision.swift)、[场景与轨迹边界](../App/Views/DuelWorld.swift)、[独立音频分派](../App/Services/DuelSourceEffects.swift)。

## 9. 验证范围与结果引用

测试使用 `DuelPanguTestFixture.rules(level:)` 和显式合成 `liu_pangu` 目录，动作轨、接触窗口、伤害、生命与各类时间均为测试条件。原目录未被这些夹具启用或覆盖；测试通过只说明代码在给定配置下满足断言。

| 验证层 | 覆盖的实际风险 | 测试文件 |
|---|---|---|
| 状态与规则 | 光能取整／溢出、连击与格挡策略、L4／L6 固定减秒、Typhoon 优先级、Rhythm 快照、阶段计时、衍生去重、RNG、非法配置 | [DuelPanguStateTests.swift](../Tests/ShiftCoreTests/DuelPanguStateTests.swift) |
| Fight 闭环 | 双朝向／双席位输入、挥空与真实命中差别、延时长矛一次伤害、范围拒绝、硬控清缓冲、实际升空／落地、瞬移无假接触、Earth 接触锚点与跳跃资格、hit-stop、逐 tick 回放、回合清理、最大生命、超时比例、攻速单帧窗口、旧目录兼容 | [DuelPanguFightTests.swift](../Tests/ShiftCoreTests/DuelPanguFightTests.swift) |
| 中断生命周期 | 招式结束后仍待发的风刃取消、天坠落地风使用地面原点、空中天坠受击后取消冲击并返回地面 | [DuelPanguLifecycleTests.swift](../Tests/ShiftCoreTests/DuelPanguLifecycleTests.swift) |
| 网络 | 独立身份与目录匹配、两个席位的真实主机输入和回放、最大生命投影边界 | [DuelPanguNetworkTests.swift](../Tests/ShiftCoreTests/DuelPanguNetworkTests.swift) |

**测试执行数量、通过情况、使用的工具链及最终命令：见本轮验收验证记录。** 最终汇总以[盘古验收验证记录](acceptance/fighter-pangu-validation-20261114.json)为准；此前目标武器补丁的验证记录仅属于其历史代码版本，不替代本轮结果。核心 Swift 测试不等同于 iOS 真机、原生特效或 TestFlight 验收。

## 10. 原版资源与参数的剩余交付条件

已核实目标为 Primordial Heavenly King；正式期原始录像面板可读到 Stormborn 双手长斧，以及 Pinnacle of Creation、Primordial Firmament 装备名。测试录像的 `ERR_HELM_AGL_48` 仅是头盔身份线索，尚不能直接绑定武器、套装配置或某个模型 bundle。派系及精确目标地区／构建也不能由该索引推断。

本轮源审计已经覆盖现有备份、已授权 IPA、原始索引与当前 RuStore 1.46.2 的有界 ZIP／元数据读取。取得的新安装包版本不等于取得新的可读盘古运行配置：已读取的 English 与 configSources 仍与先前已验证内容一致，configSources 未提供可直接跟随的明文资源清单 URL，配置归档中的内层 `.zip.enc` 仍不可直接读取。现有通用双手斧动作虽有真实来源和摘要，尚未证明是盘古专属动作，不能据此宣布盘古动作已齐。

剩余缺口对应明确的文件类型：

1. 当前可读资源目录／manifest，将盘古装备内部 ID 绑定到具体 bundle 路径、摘要和依赖。
2. 已识别的盘古头盔、护甲、单把长柄大斧、专属动作、石／风／柱 FX 和相应音频资产；动作还需确认采样率、骨骼／武器绑定及事件时序。
3. 可读的当前技能事件与参数表，或具备出处的授权导出，用于确认伤害、生命、光能换算、各等级阈值、控制、冷却与规则优先级。正式期作者报告值和测试版占位文字不能替代整套运行配置。

详细文件版本、摘要、核验方式、排除的假命中和仍未知的内容以[源审计](acceptance/fighter-pangu-source-audit-20261114.json)为准；机制语义、视频时间点和证据级别以[机制参考](fighter-pangu-mechanics-reference-20261114.md)为准。这些结论限定于实际检查过的内容，不表示所有动态资源包已搜索完毕。后续工作应接回新增的、可验证的缺失文件，无需重复上传已经校验的 IPA、备份或录像资料。

## 11. 正式 D19 规则勘误：L2／L3 劈地不得生成 L4 落地伤害

2026-11-14 对用户已有 IPA 1.46.1 携带的 `1.46.0.16.16733-prod` 配置与当前运行路径进行复核，确认 `DuelPanguState.sourceContact` 曾在 L2／L3 劈地命中后错误预约一次 `upperFall`。该额外伤害使用 `0.5 × UnarmedDamage`，属于 L4 起才创建的独立落地模型，不能从低等级被动动画的地裂视觉标记推导出来。

来源定位如下；原始配置正文保留在私有证据中，未加入公共仓库。

| 原始条目 | 已核实的运行条件 |
|---|---|
| `lock_1546.bytes`，`SET_DYNASTY_19_SHADOW_UP`，trigger 4 | 敌方 `D19_Ground_Crack_VFX` 标记到达、处于战斗阶段且拥有 `D19_4_LEVEL` 时，才创建 `D19_UP_FALL_DAMAGE_MODEL_ATTACK`。 |
| 同集合 trigger 5 | 五次 `D19_Upper_Wind_Blade` 标记创建风刃同样要求 `D19_4_LEVEL`。 |
| `settings_sets_dynasty.bytes`，record 222 | 普通 `D19_Upper_Passive` 的地裂标记为源帧 27；该动画没有 Attack 区间。 |
| 同文件 records 223—225 | 强化被动的五次风刃标记为源帧 5、10、15、30、35，地裂为源帧 40；对应风刃伤害为 `0.15 × MagicPower`，落地模型为 `0.5 × UnarmedDamage`。 |

已从持有的配置 ZIP 成员重新核对摘要：`lock_1546.bytes` 为 `398e22eb17d605e6177a29d8dbf76ab704183b19cfcc784db100947e1909b7aa`；`settings_sets_dynasty.bytes` 为 `3d660f485ad5e238f23bf6dd19d16855635a9449fd213bf1dd468a9cc979f701`。原动画区间钟将源帧 F 映射为 `2 × (F − 1)` 个 60 Hz 核心 tick。

更正仅收紧正式源分支的等级条件：L2／L3 保留原劈地攻击、命中资源和 52 tick 的受击控制，不再预约 `upperFall` 或高等级风刃／Dread。L4—L6 仍保留 78 tick 的受击控制，并在确认命中后的第 8、18、28、58、68、78 tick 依次产生五次风刃和落地伤害。本次没有修改通用调试规则、其他技能、受击清队列策略、角色身份、模型或资源清单。

验证使用显式合成几何及 1,000 单位的应用生命／攻击归一化，测试规则由 `d19HeavenlyKing` 正式源工厂产生。[DuelPanguFormalMechanismTests](../Tests/ShiftCoreTests/DuelPanguFormalMechanismTests.swift) 的两个方法逐级覆盖 L2—L6；同时复跑既有 `DuelPanguRuntimeTests.testSplitterFollowUpsUsePassiveAnimationMarkersAndRequireActualReaction`，确认不能受该反应的目标不会预约追击。Swift 6.0.3 的本次独立回归为 **3 个方法、0 失败**，编译 23.66 秒、执行 0.139 秒。该结果与其他批次不累加宣称独立总数，也不构成盘古专属外观或 iOS 真机验收。

## 12. 正式 D19 风刃计数在普通受击后继续计时

同批复核确认，正式 D19 的普通风刃由模型变量 `SET_D19_WIND_BLADE_COUNTER` 与 `SET_D19_WIND_BLADE_SPAWN` 驱动，不依赖主人仍在某个施法动作中。此前四个普通受击／受控入口调用通用清队列方法时，同时抹掉了这两个状态，造成已获得但尚未发出的风刃丢失。

原始证据仍来自第 11 节同一份 `lock_1546.bytes`，集合为 `SET_DYNASTY_19_SHADOW_BACK`：

| 原始 trigger | 对风刃变量的作用 |
|---|---|
| 11 | 满足条件的 PostHit 将发射计时变量设为 1，并给它 10 tick 的到期时间。 |
| 12—14 | 分别根据台风武器命中、连击门槛和 Trance 命中条件，增加无到期时间的待发数量。 |
| 15 | 发射计时到期、仍处于战斗阶段且待发数量大于 0 时，重设 10 tick 计时、数量减 1，并创建风刃模型。没有主人受击动作或倒地状态的取消条件。 |

已离线扫描原 battle-trigger ZIP 的全部 5,187 个成员及持有的明文配置，以上两个精确变量名的配置读写都位于该集合；未发现普通受击／倒地触发的清零操作。`lock_1549.bytes`、`lock_1550.bytes` 中另一个 `SET_D19_HIT_WIND_BLADE_COUNTER` 是命中特效循环计数，不能拿来解释待发风刃队列。

原生静态执行链也与此一致：action 171 经 dispatcher 16475、handler 30639 写入独立模型变量；核心 update 36315 调用变量更新 23671／23670 推进到期时间。全局变量重置 23669 的已定位调用属于生命周期路径 23754／23755。该结论限定于持有 IPA 的原函数路径和已核对的配置，不宣称已经在真机观察。详细检索与反汇编回执保存在私有 `d19-wind-lifecycle-raw-references-private.json`、`d19-variable-reset-callers-private.json` 和 `d19-wind-disasm-*` 中；原始配置正文未加入公共仓库。

实现增加 `cancelPendingDerivedAttacks(preservingSourceWindCounter: Bool = false)`。仅带正式 `runtime` 的普通击倒、Pangu 控制、Triad 控制及既有普通投技受击入口传入 `true`，保留待发数量与**当前剩余 tick**，不会重启一个新的 10 tick 计时。其他派生队列仍按原逻辑清理；强制中断、显式默认清理、重置和回合切换仍清空风刃。调试／旧规则没有正式 `runtime`，因此即使传入 `true` 也不改变其原取消行为。本项没有新增存储字段或改变回放编码。

专项测试在 L2—L6 验证计时经过 3 tick 后受击仍准确保留剩余 7 tick；通过实际 `DuelWeaponFight` 普通互击倒地及 H17 根控路径，验证风刃按原第 10 tick 释放并命中目标；同时覆盖强制中断、默认清理、重置与真实回合切换，确认不会把旧风刃带入下一回合。两个 Fight 场景使用明确合成的骨盆点／碰撞几何及受击时长，仅测试机制交互，没有加载或声称盘古原始模型。

最终 Swift 6.0.3 定向回归为 **9 个方法、0 失败**：本类 7 个方法包含第 11 节原有 2 个；另复跑原 Splitter 反应门禁与旧调试规则的击倒取消各 1 个。编译 6.07 秒，执行 0.667 秒。前置新 fixture 的闭包类型、点数组编码和调试根控时长约束错误已修正；最终通过并未放宽正式参数或断言。本次 9 个方法与第 11 节的 3 个方法存在重叠，不能相加为独立测试总数。日志为私有 `d19-wind-lifecycle-tests-private.log`。

## 13. 正式 D19 六个本体技能的收招反投窗口

原配置的 `Throwable` 区间并不等于普通动作的 `Uninterrupt` 结束。D19 的六个本体技能在仍处于收招时，已经允许敌方发起投技尝试，再由 D19 免投反击接管双方动作。旧实现同时要求目标没有普通 action、没有 activeCast，因而把这些已存在的源窗口延迟到了整段施法结束。

来源为同一份 `settings_sets_dynasty.bytes`。下表的 tick 从当前源动画首帧开始；六条均未裁剪起始帧，`Throwable` 的 End 为 null，进入公式为 `2 × (源帧 − 1)`。其中投矛另有 EndFrame 55 的尾部裁剪。当前 cast 结束 tick 是既有运行适配边界，不能称为尚未恢复的全部原始动作总帧数。

| 技能／原动作 | record | 原 Throwable 首帧 | 反投允许首 tick | 原 Uninterrupt 释放 tick | 当前 cast 结束 tick |
|---|---:|---:|---:|---:|---:|
| 劈地／`D19_Upper` | 221 | 58 | 114 | 126 | 126 |
| 碎石／`D19_Forward` | 226 | 50 | 98 | 110 | 110 |
| 根骨／`D19_Low` | 229 | 42 | 82 | 94 | 94 |
| 台风／`D19_Back` | 232 | 35 | 68 | 80 | 80 |
| 投矛／`D19_Missile` | 240 | 42 | 82 | 94 | 100 |
| 天坠／`D19_Ultimate` | 236 | 155 | 308 | 320 | 320 |

`lock_1545.bytes` 的 `SET_DYNASTY_19_ENEMY_THROW` triggers 0／1 要求目标**当前动画**带有 `Throwable`、没有 `Unstable`，并检查发起者输入／控制、真实 COM 距离、墙侧分支等条件。接受后令发起者进入 `D19_Unthrow_Passive`。`lock_1544.bytes` 的 `SET_DYNASTY_19_1_LEVEL` trigger 1 随敌方 THROW 动画开始，让 D19 主人进入 `D19_Unthrow`；该接管不要求主人自己的 Uninterrupt 已结束。因此不能把上述 12 tick 的重叠区间作为通用不可反投期。

原生 `CurrentInterval` 查询也已闭环：dispatcher 16637 的 function 29 经 27860／38092 到控制器 39304，返回当前动画播放器持有的区间列表；没有播放器时返回空列表。39191 按源帧进入／移除区间，39347 安装新播放器并经 39176 交接，39185／39187 的显式结束／停止路径通过 39192 清理区间。因此本次采用由当前 cast 计算的只读窗口，不另存一个可能跨动作残留的布尔开关。

代码增加 `sourceCastAllowsThrowResponse` 与 `acceptSourceThrowResponse()`。Fight 只在当前 action 的角色、clip 名称、无普通 command、非 reaction 均与该 cast 匹配时，放行这一条源反投路径。普通 `throwImmune`／`canBeThrown` 的含义没有改变：盘古不会因此变成普通被投受害者。发起者状态、双方落地条件、COM 小数距离、墙条件、强控、生命、已有投技配对等门禁保持原样。

接管只取消被替换本体 cast 所拥有的尚未释放攻击，并发出一次中断通知；不用强制中断，也不抹掉独立风刃计数、剩余计时、已经释放的模型、资源或冷却。天坠在 308 tick 的合法窗口同样可进入反投，但其他普通冲击仍保留原有的天坠抗打断规则。反投配对从 tick 0 开始，伤害仍在配对 tick 98 按 `0.15 × UnarmedDamage` 进入正常 PreHit 计算，不再等待旧技能尾段。

本次不扩展两个不同的问题：风暴之门的 `Throwable` 在当前 cast 结束的 62 tick 才进入，没有这六条提前窗口；`D19_Unthrow` 自己在 record 248 的 134 tick 再开放 Throwable，涉及已释放的旧配对参与者与仍持有角色的接管，应单独审查配对生命周期，未混入本次初次反投修正。当前未选用的 `D19_Ultimate_Alt` 也不借用正常天坠的规则。

来源摘要：动画配置见第 11 节；`lock_1544.bytes` 为 `ec56d114b475aa7546fb056595edcb167156e458423dbb82967a02a49f9351ca`，`lock_1545.bytes` 为 `073e0dc18d278aa518fa0f2dbf502b2afc77cfd3ea65c56136a4216c25a4fb42`。完整私有证据 `d19-throw-window-audit-private.json` 的 SHA-256 为 `98f0f6397c404ddfc83802829e0db906f0fdade19fcfa33c104f93ddbc6c958c`；原配置及反汇编正文均未加入公共仓库。本项没有新增存储字段、修改回放编码或资源文件。

Swift 6.0.3 本次定向验证一次完成 **37 个方法、0 失败**，编译 23.54 秒、执行 12.726 秒：本类现有 14 个方法（其中本项新增 7 个），加既有 SourceThrow 14 个及 SourceThrowFight 9 个。新覆盖逐级验证 L2—L6 的六条前一 tick／首 tick；实际 Fight 在两个朝向／席位接受后立即给出反投 tick 0，直到 97 tick 仍无反投伤害，98 tick 才执行原 `0.15` 基础值与普通 PreHit 倍率。另覆盖独立风剩余 7 tick、资源不退款、新施法、正常结束、强制清理、重置、回合切换、旧规则／双锤身份、超距、发起者忙碌，以及真实 host 暂停／恢复。几何与角色媒体仍明确为合成测试数据。本次 37 个方法包含第 11—12 节的部分方法，不能与此前批次相加宣称独立总数。

私有日志为 `d19-throw-window-tests-private.log`，SHA-256 `ffeb25ac615a6d4a6247bc419bcf0b799bc69fba2092f23f713f36a44cfd7a4d`；没有执行 Apple 原生或真机验证。

## 14. 反投自身收招的 134 tick 再接管窗口

本项单独处理第 13 节留下的 `D19_Unthrow` 收招问题，没有改变那六个本体技能的接管边界。原动画配置 record 248 明确包含 `Throwable` Start 68／End null，按同一 60 Hz 区间钟在 tick 134 进入；自己的 Uninterrupt 到源帧 73 结束，即 tick 146 才释放。原配对被动 record 249 在 tick 112 已触发 AnimationEnd，所以 134 tick 时可以出现“敌方已自由、盘古仍在旧反投主动动作”的有效状态。

已与当前持有的真实动作及私有运行目录交叉核对：

| 原动画 | 已绑定角色 | 源样本末 tick | AnimationEnd tick | Uninterrupt 结束 tick | 动作 SHA-256 |
|---|---|---:|---:|---:|---|
| `D19_Unthrow`／record 248 | `ordinaryPanguEscape` | 162 | 154 | 146 | `0887c31334fee81394ef7f2cf47fb1242b831d2151d37adcdd728334824b28f6` |
| `D19_Unthrow_Passive`／record 249 | `ordinaryPanguResisted` | 120 | 112 | 121，全片 Uninterrupt 的投影边界 | `93c471b781eef97f90edc6be5213b1224b6559fd0158c599611660fd99a82228` |

这仍通过第 13 节相同的 `lock1545` 当前 Throwable 检查和 `lock1544/t1` 反投响应链启动新配对。代码不从“旧配对已经存在”推导永远禁止新尝试，也不允许任意配对被覆盖：仅当旧 variant 是 `panguEscape`、旧主动目标仍被该状态持有、旧发起者已经释放，而且当前角色确为带正式 D19 runtime 的盘古时，才考虑这一窄窗口。普通投技、仍持有双方的配对、没有正式 D19 规则的旧双锤均不获得该例外。

`DuelSourceThrowState.permitsPanguRecoveryTakeover(_:sampleTick:)` 是只读投影，没有新持久标志。Fight 进一步核对当前 pose 的 clip、时长、对应 `panguActive` motion 和 SHA。时钟边界使用**已实际准备的样本**：当前流程先 `prepareSourceThrowSamples(nextSamples)`，再判输入，之后才 advance 配对状态。因此旧状态 tick 133、当前 pose tick 134 时必须可响应；额外要求 `pose.tick == oldPair.tick + 1`，避免凭未推进的旧时钟延迟一 tick，或凭其他动画／任意未来样本提前接管。

接受后只释放旧状态最后仍持有的盘古参与者，并确认旧状态已经 `isFinished`，再移除旧状态；不调用会产生 idle 样本的通用释放路径，也不清理盘古风刃、资源或冷却。新配对从 tick 0 开始。原 step 记录的旧 advancing tick 与新配对 tick 0 不同，故既有推进检查拒绝在同一 tick 再推进新配对；旧状态也不可能在其原 154 tick 结束点释放新参与者或重新执行旧 98 tick 伤害。新配对继续按自己的 98 tick 执行一次伤害。

新增 [DuelPanguSourceRetakeTests](../Tests/ShiftCoreTests/DuelPanguSourceRetakeTests.swift) 8 个方法，与第 13 节的 37 个方法一并进行定向验证。**45 个方法范围内，44 个首轮通过；唯一失败方法的跳跃 fixture 把方向输入误写成跳跃 edge，修正为实际 `taps: .jump` 并推进至确实离地后，该方法单独复测 1／1 通过。** 保留了前置离地断言和全部拒绝断言，没有修改生产逻辑、原参数或容差；不能把这两次运行写成“一次 45／45”。首轮编译 23.71 秒、执行 19.236 秒；复测编译 7.47 秒、执行 1.164 秒。

覆盖包括 133／134 边界、两朝向及两席位、仍持有双方时拒绝覆盖、当前／未来样本约束、普通配对排除、COM／地面／发起者状态、资源和冷却不退款、原配对结束不影响新配对、每个新配对的 97 tick 无额外伤害／98 tick 单次伤害、连续再接管的确定性 canonical bytes，以及实际回合重置不残留旧配对或伤害。测试几何、骨骼点和角色媒体均为显式合成夹具；真实公共动作的存在不会把当前 `liu_hammers` 角色身份改成盘古。本项没有修改资源包、App、CI、Site、存储字段或回放 schema。

私有日志为 `d19-source-counter-retake-tests-private.log`（SHA-256 `b4a112a88edd47f1e6a51719b2947328e25ac024cc7a445897076da6d8efac6c`）及 `d19-source-counter-retake-air-fixture-retest-private.log`（SHA-256 `a5a3e6f9e9f07fd04471c1885b26e0d11b13674fe36804cad6570a875b774fd5`）。该范围包含前述 37 个方法，不能相加为 82 个独立测试；本项尚未单独执行 Apple 原生或真机验收。
