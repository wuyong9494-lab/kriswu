# 刘泉纬盘古：机制接入与交付记录

记录日期：2026-11-14。本次开发基线：本地提交 `cabc2fc`；本文描述在该基线上完成的本地实现与验收边界，远程发布状态以本轮验收记录为准。

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
