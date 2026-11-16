# 蛇王剩余源机制核查 — 2026-11-16

本记录区分已经接入的命中规则、已经恢复但尚未接入的离散模型，以及仍需补齐的原生运行语义。它不代表 D13 完整验收，不改变生产角色选择、资源身份或发布权限。

## 核查来源

完整触发器来自 `serpent-trigger-source-v1`；每项均通过原始 bytes SHA、六字段 TriggerData 重建和 receipt 核验，未把说明文案作为运行规则。

Receipt SHA256：`d169d518d0133ee6180c81d11edd5b5c11816e91886b7aae2eed54806f775d37`。

| 原始文件 | SHA256 | 本次涉及内容 |
| --- | --- | --- |
| `lock_1379.bytes` | `315b57e6df0e1bad37c49804418ebdf07291a80ce6f67f38274515db665e6777` | 毒爆、毒增益选择、破防、降防 |
| `lock_1380.bytes` | `2aa474f906e1d2c8eeb9ac3c763abcc93b2717d91d3c82e0ec8d2759a8b0e16a` | 对手额外按钮反应、unarmed 毒增益摔倒 |
| `lock_1383.bytes` | `f53521ab0f51745c1cc2e00da4bfd54e0893849008ab143d8778b54a8c900e6c` | shadow 毒增益的 ModSC |
| `lock_1384.bytes` | `599e51a54b25ed92b3adaae205d266c9abe727d8151af8d69a6ee973d948ec05` | Bloom 能量、技能输入、特殊能量免疫 |
| `lock_1389.bytes` | `7af8a563d7738511bbc7eac9e3f325732ddb56c0a1b61dce36c9128b0bdb2e8f` | 最终伤害、被动、满 Bloom、随机瓶与 puddle |
| `lock_1396.bytes` | `941b17f2617d37d6bb0a252332d547c1aa740e61aa45f91b0705a646fbf4f354` | 等级 4 凋零与技能强化 |

下文 `1389/2` 等编号是 `sourceSetIndex=0` 内的零起始 `triggerIndex`。例外会明确给出 set 名称或 set index。

## 已接入：最终 Hit 伤害乘 0.66

`1389/2` 监听 `a16(enum65538, ...)`，即拥有 D13 的角色对对手产生的 Hit。源条件为：

- 当前事件是 `Hit` 时，`Me.HIT_FIRST == 1` 或 hit tag 为 `Hit_Invisible_Hit`；非 Hit 的原生替代事件沿原监听器分派规则接受。
- `f59 > 0`。
- 无伤害通道过滤，无格挡排除，无额外 Bloom 门槛。
- 所在源树要求 `D13_DEFAULT_ABILITY`，并保留正常 Fight / skeleton / set bonus 条件。

动作是 `a149(null, null, [f59, 0.66, op2], null)`。这是已经算完的 Hit damage replacement；不能在 WeaponPower 上先乘一次，再在 Hit 上重复乘一次，也不能附加到无 Hit 的 ModHP 毒伤上。

当前接入点为 `DuelWeaponFight.receiveTargetDamage(..., sourceHit:)` 和 `receiveTargetNormalizedDamage(..., sourceHit:)`。只有已接受的真实普通接触、模型接触入口以及投技伤害 marker 会显式传入 `sourceHit=true`。普通连续重叠由 `touchingStrikeIDs` / `landedStrikeIDs` 去重；源配对投技由 `damageApplied` 保证一次 marker。两个实际投技动画的原配置均为 Attack interval，tag 为 `Unblockable, Hit_Throw`，不是一个纯 ModHP 事件。

`DuelSerpentState.outgoingHitDamage` 是只读公式，没有新增保存状态。D13 的 ranged 毒防御因子和树皮护甲因子保留到最终乘法时组合；例如 `30 / 0.7 * 0.66` 不会先截断成 `42 * 0.66`。二郎神继续保存归一化 Float 血量，普通 30 点源伤害对应 19.8 点实际 HP；旧整数血量目标只在写入其血量域时向下取整。后续毒量和 Bloom 读取二郎神实际归一化血量变化，不从四舍五入后的 HUD 差反推。

毒雨、毒爆、持续毒伤和回血都没有被标记成这个 Hit。`check_serpent_passive_source.py` 的 v2 oracle 直接读取原 RPN，已核验 6 个最终伤害案例、6 个防御案例、4 个回血案例。新的 Swift 回归覆盖 first / invisible / 正伤害门控、实际双钩命中、实际投技与独立 ModHP；具体结果以集中回归日志为准。

早先“投技同 tick 扣一次新毒、寿命立即变成 899”的断言已撤回。它描述的是旧逐 tick 实现，不能作为原生规则。现在 100 点投技先经最终 Hit 乘数变成 66 点，原物理伤害和姿态顺序保留；其 D13 PostHit/Bloom 结果通过当前 step 内的临时 receipt，在状态更新结束后派发。命中这一 tick 的毒寿命仍为 900、累计时间为 0、没有额外毒伤；之后第 10 个有效状态更新才发出首次毒脉冲。普通双钩的 PostHit 也发生在状态更新之后。

## 已修正：ModHP / ModSC 共用原生脉冲语义

### 独立原生证据

本轮读取了现有 IPA 的精确原始输入，没有执行原游戏二进制：

- `UnityFramework` SHA256：`7c192647b0e035bd246c135a59c597ee3910d50fc4ed128abe402da39a62a55b`。
- `global-metadata.dat` SHA256：`12d52d278c904b210541e7c337025c68454e2b89a83eddab51f9c74fcc5a245c`，metadata version 39。
- 私有证据目录：`work-products/serpent-modsc-native-proof-v1`；`status-pulse-oracle-private.json` 保存 29 个方法地址和原始字节 SHA，以及 12 个明确创建阶段的 Float32 案例。`status_pulse_oracle.py` 是这些指令分支的有界翻译，不是全游戏解释器。

| 原生方法 | 已证明的行为 |
| --- | --- |
| 29153，`0x6f100c0` | `a10` 解析 ModHP / ModSC。ModHP 使用参数槽 3，ModSC 使用槽 4；不是同时使用两个值 |
| 39053，`0x7157750` | duration 从槽 5 取得；槽 6 缺省为 0，构造器将小于 10 的 interval 提升到 10 |
| 37012 / 37018，`0x70ee024` / `0x70ee39c` | 新建或同名刷新保存本次 rate、duration 和创建时钟，累计时间清零；创建本身不发出 HP/SC 事件 |
| 37019，`0x70edea4` | 累计 `sourceDelta`；达到 interval 时发出一次 `rate × accumulated`，再减一次 interval；到期且本次未发 interval pulse 时补发余量，随后停用 |
| 37020，`0x70eec58` | ModHP 发 `StatusHpTick`，ModSC 发 `StatusScTick`；没有自行触发 Hit / PostHit |
| 35975 / 35977，`0x70c4244` / `0x70c4518` | 正常 source delta 为 1，累计源时钟先于战斗阶段推进。状态使用该源时钟，不能解释成真实秒数或 Unity deltaTime |
| 24207 → 23786 → 23787 → 157745 / 157744 | HP 接收端向归一化 HP 直接加入 delta，再 clamp 到 0–1；没有额外的百分比换算 |
| 24205 → 24017 → 37572 / 37573 | SC 接收端向归一化 ShadowCharge 直接加入 delta，再 clamp 到 0–1；另有原生状态门控，不能替换为任意特殊能量槽 |

原 updater 的大 delta 分支只发一次、只减一次 interval；不能自行改为 `while accumulated >= interval`。有限 duration 在更新时间先累积，再判断到期；也不能提前把该次 delta 截成“剩余寿命”。暂停时战斗调度不调用状态更新。显式移除和同名刷新均丢弃尚未结算的累计量，不在移除时补发伤害或治疗。

`DuelSerpentStatusPulse` 按上述 Float32 分支实现。四毒、毒爆和吸血共用该内核；地面毒有独立实例。每个已发出的脉冲独立经过目标的血量边界，不先把多个 Double 相加后只做一次 Float 写入。

### 当前 D13 路径及准确结算点

| 路径 | 源配置与替换规则 | 已接入行为 |
| --- | --- | --- |
| 四毒 | `1389/17–23`，900 tick，rate 为 `-store / 900`；增加毒量后显式 `a35 + a10` | 每种毒独立累计，前 9 次有效更新没有脉冲，第 10 次结算；900 tick 正常实例发出 90 次脉冲 |
| 等级 4 / 5 毒爆清理 | `1398`：选中毒移除，其余量乘 0.25；随后明确逐种 `a35 + a10`，duration 读 `f230` | 保留每个变量的剩余寿命，但重建 status rate 并清零旧累计量。`f230` 不是保留旧脉冲余量的指令 |
| 等级 6 毒量重分配 | `1399`：分配选中量的三分之一，并对其余毒逐个 `a35 + a10` | 新 rate 按更新后的量捕获，duration 重置为 900，旧未结算量丢弃 |
| 地面毒 | `1403/13`，`SET_D13_GROUND_POISON`，1200 tick；`-0.02 × stacks / 1200 × RaidDamageAmplifier` | 与四毒分离；每 60 tick 的真实地面回调加层并重建 status。新的十 tick 间隔从该次重建后重新累计 |
| Lifedrain | `1389/12–13`，第一次变量计时 30 tick，然后创建 duration 30 的 `D13_LIFEDRAIN_HEAL` | 如果在 t=0 激活，t=30 创建状态，t=40 / 50 / 60 发出三次治疗；t=60 到期脉冲仍使用旧 rate，下一段捕获新的毒量 |
| 毒爆 | `1379/16`，四个独立 duration 1 的 ModHP | 原 release marker 只创建状态并保留展示事件；下一次有效更新按到期余量结算一次。Fight 不再从展示事件同步写 HP |

例：某毒累计了 7 tick 尚未发出脉冲，`1398` 在此时将它的量降为四分之一、余寿保留 893 tick。旧的 7 tick 被移除；新状态在相对重建第 10 tick 首次发出新 rate 的脉冲，最后到期补发 3 tick 余量。不能把旧 7 tick 合并到新 rate，也不能继续按旧 rate 扣血。

共同规则 `lock 923`、set 128 `CLEAR_STATUSES_ON_ROUND_CHANGE` 的 trigger 0（priority 99999），在 RoundFightEnd 或已经致死的 PostHit 中执行 `a35(null, Me, null)`。State / Rain 的 `endRound()` 因此清除所有本轮 status 实例，不结算残余时间。Owner 的 Bloom、冷却和独立变量计时是另外的生命周期；本次没有把这些变量与 ModHP 实例混为一类。该公共源 bytes SHA 为 `c2fe1f2fa5b4a0a8b457de20608334d9202b959b832b72317860adf0d8c9cba2`。

### 场景调度和适配边界

独立核查 `work-products/serpent-status-phase-private-v1` 证明：`InitLocationScene`（36309）注册 type 3749 `DMADMMPIMDL`；其 slot 5 是入队方法 23657、slot 6 是 drain 方法 23659。36315 的已证明路径为变量计时 → actor status 37019 → collision 36165 → 最终 drain → 匹配的 trigger 执行。因此，已经进入这个正常场景队列的 PostHit/Bloom 反应创建的 a10，应晚于本次状态更新。

该独立 `phase-proof-private.json` SHA256 为 `3af5747c1469d45fa9d6c7668900972c09ada42395c543eccbd1eed3ec827e0e`。同一 drain 产生的新事件可在这次 drain 内继续处理；推迟 status 创建的阶段不等于强行给所有事件增加一 tick 延迟。

另一个 type 3753 的实现确有同一 Unity `Time.frameCount` 内立即分派的 override，但它由 SF_GLOBAL 初始化路径注册，不是上述正常场景实例。没有把两个实例的分支混合为统一时序。

本地投技适配已明确将该命中分类为 PostHit，因此现在只延后 D13 的 poison/Bloom reaction；其他角色回调、投技物理伤害、两人姿态和出生锚点顺序不变。临时 receipt 在同一 step 内消耗，没有新增跨 tick 状态。**throw 专属原生 producer → 23809，以及 IntervalStart producer 的独立 native 边仍未逐函数闭合**；这里不宣称完整投技引擎已经逐指令复刻。

不同 status 在原生可复用容器内的完整先后顺序也未逐项映射。当前四毒仍采用已存在的 Channel 次序，毒爆四个新实例按 `1379/16` 的明确动作次序处理。单一实例的首次、刷新、到期及 Float32 脉冲已经核验；跨所有 status 的完整原生容器顺序仍是明确的 arena 适配边界，没有临时发明一种排序。

## 未接入：unarmed 毒增益的摔倒反应

### 已确认的完整触发链

`1379/12` 在毒爆 ANIM / KEY 事件中选中 unarmed 毒。条件是其毒量为正，并且满足“达到上限且最后毒种为 3”或“严格大于其余三个毒量”。它授予 `SET_DYNASTY_13_POISON_BUFF_UNARMED=1`，持续 900 源 tick；现有 State 已保存这一增益期限。

真正作用在对手身上的逻辑位于 `1380` 的 **set index 1，`SET_DYNASTY_13_FALL_REACTION`**。

| Trigger | 精确事件与条件 | 动作 |
| --- | --- | --- |
| 0 | 对手任意 `AnimationEnd`（`a0`）；Enemy 的 unarmed buff 活跃；`Random(1,100) <= 30`；本方无 `SET_DYNASTY_13_FALL_CD`；当前源动画名称不等于 `STANCE_IDLE` | 设置本方 `SET_DYNASTY_13_POISONED_FALL_ACTIVE=1` |
| 1，priority 402 | `Uninterrupt` 区间结束或 `STANCE_IDLE` 动画开始；RoundFightStart 阶段；buff 及 pending 标志仍活跃；双方无 Timeout_Postpone；对手不占有 THROW_BLOCKS_ANIMATION；自身当前不在 Uninterrupt 或 FOLLOWED_BY | 切换 `Physics`；`InPhysics=1` 持续 140 tick；CD 持续 180 tick；fall-damage timer 持续 30 tick；清除 pending 标志 |
| 2 | `SET_DYNASTY_13_FALL_DAMAGE` 的定时变量事件；RoundFightStart 阶段 | 给当前受害者一个持续 1 tick 的 ModHP：`-0.05 * RaidDamageAmplifier` |

这里的随机抽签发生在 **AnimationEnd**。`a0` 的含义也由原配对投技 `ANTI_THROW` 的 passive-end 事件独立确认，不能误接到 AnimationStart。摔倒不是“下一脚增伤”，也不是每次出拳直接丢一次 30% 抽签。

### 具体缺口

1. 当前 Fight 还没有忠实的通用 `Physics` / ragdoll 进入、骨骼接管、受击与恢复协议。不能把已有任意 knockdown clip 拉长成 140 tick 冒充该状态。
2. 需要在受害者一侧保存 pending、fall CD、Physics 生命周期、30 tick 延迟伤害，并接入回放和回合生命周期。过期 buff 本身不等价于源代码清除 pending；必须按原变量寿命语义处理。
3. 需要明确 AnimationEnd、UninterruptEnd、进入 STANCE_IDLE 同一 tick 的源分派顺序，以及“当前动画”在这些回调中的含义。仅有 UI pose 名不能补足这项证明。
4. RNG 必须只在满足源前置条件的 AnimationEnd 消费一次，使用权威对局 RNG；暂停、hit-stop 和重复渲染不消费抽签。
5. `1380` 的 set index 0 另有毒爆主动区间引起的 `Hit_Stun_Reaction` / `SET_D13_STUN_CD`，它与 unarmed 随机摔倒是独立机制，不能合并为一个通用 stun。

下一步先恢复并核验 `Physics` 原生调度与动画事件顺序，然后接受害者状态。实测应通过真实踢击或真实云回调取得 unarmed 毒，再正常毒爆取得增益；使用固定对局 seed 验证 30% 分支、CD、受保护时 pending 延后、30 tick 延迟伤害与 900 tick 增益截止。不得用强制 HP / 状态注入替代合法触发。

## 未接入：shadow 毒增益的能量影响

`1379/15` 的选择条件与上节同构，最后毒种编号为 5。它授予 900 tick 的 shadow buff，并发出立即的 `SET_D13_SHADOW_POISON_IMPACT` 变量事件。

`1383/0` 只在 RoundFightStart 阶段，且满足以下两个条件时创建状态：

- `Enemy.IS_INVULNERABLE != 1`。
- `Enemy.DISABLE_SHADOW_ENERGY_IMPACT != 1`。

原动作完整参数为：

```text
a10("SET_D13_SHADOW_BURN", enum65538, "ModSC",
    null, [0.0, 0.1, op1], 900.0, null, null, null)
```

**第四数值槽是 null，第五槽才是 -0.1。** 现在已有上述原生 factory / update / receiver 证据：ModSC 选择零起始槽 4，捕获 rate=-0.1，duration=900，缺省 interval=10。正常源时钟下每累计 10 tick 发出 `-0.1 × 10 = -1.0` 的归一化 ShadowCharge 变化，接收端 clamp 到 0–1；它不是“总共扣 10%”或“每秒扣 10%”。刷新会重新捕获 rate、重置寿命并丢弃旧累计时间。

这次只将已证明的共用内核用于当前已有 ModHP 路径，尚未启用 shadow burn。仍需把原生 charge 接收端的抑制状态、普通 shadow-form 终止联动、目标角色能量身份和受害者 status 所有权完整接入，不能仅从一个通用 `energy` 数值槽直接减去 100。

`1383` 在 lock tree 中有两条保留的 sourceTreePaths：一条有 set / DisablePerks 条件，另一条过滤 FullSF、WithoutSF、Shadowless 和若干特殊 boss 模式。它们是原树中的两条路径，不能把路径条件任意合并成一个新条件。

### 已确认的特殊能量免疫

| 角色 | 原始源点 | 结论 |
| --- | --- | --- |
| 刘泉纬 / D13 | `1384/0`，`SET_DYNASTY_13_NO_FULL_SF` | `NO_SHADOW_ENERGY_GAIN=1`，`DISABLE_SHADOW_ENERGY_IMPACT=1`；Bloom 不能当成 ModSC 扣除目标 |
| 吴庸 / D15 | `1432/0`，`SET_DYNASTY_15_NO_FULL_SF` | `TAG_LIGHT_ENERGY=1`，`NO_SHADOW_ENERGY_GAIN=1`，`DISABLE_SHADOW_ENERGY_IMPACT=1`；Light 不能当成 ModSC 扣除目标 |

D15 `lock_1432.bytes` SHA256 为 `74917b81d2e8e0bae60123a7bb2a42f15d7ce4dc9f90f57a62c787c66dc4dde7`。本次没有把未核对的其他角色特殊能量一律推定为可扣或免疫。

下一步应从已定位的 37572 / 37573 继续核对 charge 写入所读的状态标志及 shadow-form 联动，再接独立 target burn 状态和普通 shadow-charge 适配，保存实际时钟与回放。源 `1383/0` 的两项免疫在创建 a10 前判断；receiver 自身的额外状态门控仍应保留。正向实测用具有普通 shadow 能量的真实角色，通过云回调取得 shadow 毒并毒爆；负向实测使用上述 D13/D15，断言 Bloom / Light 全程不被扣除。

## 与以上增益独立的完整 D13 缺口

| 机制 | 已有准确源输入 | 仍须接入的运行链 |
| --- | --- | --- |
| 自动满 Bloom | `1389/14`：Bloom >=1，合法 UninterruptEnd / STANCE_IDLE / BLOOM_CHECK 窗口，priority 402；动作 `Set_Legion_3_Shadow_Form_In` | 此人形动画不在当前 66 clip profile；需实际动作、原窗口、事件和独立模型接入。原动作共 54 源帧，end tick 98，Overload marker tick 54，不可复用毒爆动画 |
| 第五种 Bloom poison | `1389/16` 在 **RoundFightStart 或 Overload marker** 设置 `0.66`，持续 420 tick；无额外 FullBloom 条件。`1379/8` 通过单独模型释放；KEY 清除与 ANIM 路径不同 | 当前 State 只有四种累计毒。第五 store、初始 availability、来源 marker、碰撞命中与清除还未闭合。完成后应更新“开局没有任何可用毒”的现有部分实现测试，不能把该断言当完整源规则 |
| 头盔 / 护甲技能 | `1384` 的 Shadow+方向输入；实际人形动作已经存在；独立模型恢复文档已有 helmet、push、vine1、vine2、bloom FK/capsules | 输入门控、720 tick 自身 CD / 360 tick 配对锁、出生/销毁、碰撞、真实头盔受害者局部时钟冻结。胶囊恢复不等于完整技能已经可用 |
| 受击随机瓶 | `1389/28`：接受的 incoming PostHit / FIRST 或 Invisible，`Random(1,100)<=20`，创建 `D13_BOTTLE_MODEL` | 这是被动掉落瓶，不是已经完成的主动毒雨瓶。实际配置为 record 59 `D13_Bottle_Fall` / `rng_agl_bottle/throw_bottle_model_create.bin`，需要掉落模型 Physics 与落地出生链 |
| 独立 puddle | record 60 `D13_Puddle_Model_Loop`，record 61 `D13_Puddle_Enemy_Damage`；都有真实 `common_model_40_attack.bin` 配置，Align 和 lifetime 各不相同 | 需要独立场上实例、owner/target 进入退出、碰撞与销毁；不能复用毒雨云的体积、每 tick poison 或随机毒回调 |
| puddle 自身治疗 | `1389/29`：rate=`0.1*2.5/600`，duration 600，缺省 interval 10；BossEasy 分支另有 rate=`0.03/600` | 必须由真实 `SET_D13_PUDDLE_PLAYER_DEBUFF` 事件触发，处理原状态移除和刷新；现有 Lifedrain 不能替代它 |
| puddle 对手 DOT | `1389/31` priority -100，真实 `Hit_D13_Puddle` 且正 f59：保存 `-f59/900`、持续 900 tick，然后 SetHit damage=0 并关闭对应 hit 标志 | 需在完整 Hit 阶段顺序中读取已处理的 f59；最终伤害乘 0.66 与后续替换为 DOT 的次序不可调换 |
| 等级 4 凋零 / 强化 | `1396`：Bloom >=0.33 启用 aura，>=0.66 启用强化；COM 距离 <300 时按 60 tick 加层，外部按 20 tick 减层，最大 40 | 需要距离、层数、不同 timer、攻击通道减伤/critical 门控，以及强化技能的第二源 marker。它们不等价于 0.25/0.5/0.75 被动分段 |

离散模型的当前恢复与实际 FK/capsule 验证记录见 `fighter-serpent-ability-models-20261116.md`。应从已经恢复的真实模型继续完成其调用链，不因完整机制尚未交付而重复制造假模型或写永久关闭的入口。

## 回放与验证边界

本轮 A/B 和脉冲修正进入 canonical replay schema 15 / rules 21：Fight 保留 `serpentHealingRemainders`，State 保留 barkskin / lifeDrain activation 与变量计时；旧 `lifeDrainStatusRemaining` / `lifeDrainStatusPerTick` 被 `lifeDrainStatus` 内核替换，并新增 `sourceStatusTime`、`poisonStatuses[4]`、`explosionStatuses[4]`。Rain 新增独立 `groundStatus`。

每个内核编码 `rate`、`duration`、`interval`、`createdAt`、`accumulated` 五个 Float32 bit pattern 和 `active`。单个 D13 runtime 的编码净增 198 bytes：State 增 177，Rain 增 21。最终 Hit 乘数和 step 内的临时投技 receipt 都没有新增持久字段。State / kernel 反射审计与实际 Rain fixture 的字段清单同时覆盖这些字段。

本次脉冲修正的第一轮真实资源回归为 **63 项通过，0 失败，0 跳过**，日志 `work-products/validation/swift-serpent-native-status-v1.log`：State 12、StatusPulse 4、ActionRuntime 10、RainRuntime 17、FightIntegration 20。它覆盖四毒 / f230、Lifedrain、真实雨和独立地面毒、毒爆延迟、正常实战与 kernel 首末边界。

投技 phase 修正后的定向验证共 **21 个不同用例，最终均有通过结果，0 跳过**：ReplayState 14、ReplayAudit 3、最新 D15 候选的入口与真实投技 3、Rain 字段清单 1。初轮日志 `swift-serpent-status-phase-final.log` 为 20 通过、1 失败；唯一失败是标量 golden 的 raw header 仍为 schema 14 / rules 20。只将该常量同步到 15 / 21 后，`swift-serpent-status-phase-golden-retry.log` 单独复测这 1 项通过，未修改运行逻辑、未重跑其余 20 项。不能把该单项复测加成 22 个不同用例，也不能将重复的 3 个实战用例与第一批重复计数。

最终定向的 `ERLANG_MATCH_PROFILE` 使用冻结的 `erlang-runtime-contour-v2/SF3_Erlang_Profile.json`；D13 使用 `serpent-match-v2/SF3_Serpent_Match_Integration_Profile.json`。旧提交 `845316122d57b099e739f71c6b8d7759448e16cb` 的 105 项与原生运行属于历史结果，不作为本次 core 修正已通过的证明。

unarmed 摔倒、shadow burn、第五毒、puddle 等后续一旦接入，必须把实际 pending / timer / 实例所有权加入同一审计；不能仅因为动画或音频已经出现就省略权威状态。展示音频的消费游标不推进对局，不加入 gameplay replay。
