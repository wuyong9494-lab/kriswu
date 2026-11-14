# 孙登黑色双刀与刘泉纬盘古：目标机制证据记录

记录日期：2026-11-14。本文用于本轮实现和复核，**不是完整还原已经通过的验收结论**。只整理已经取得的用户录像、原作者实机画面和官方公告；无法确认的数值保留 `null`。

## 1. 本轮目标身份

| 项目角色 | 本轮原版目标 | 确认依据 | 尚未锁定 |
|---|---|---|---|
| 孙登 | 《暗影格斗3》**死亡森林三魄 / Dead Forest Triad（DFT）**，先锋派系，**Ninjato / 忍者双刀** | 用户 11 月 14 日录像左侧的黑红盔甲、红色头饰、背后三个傀儡、双紫色直刀、紫雾和魂影，与 DFT 原作者录像对应；装备实机卡片显示 Branches of Pain 属于 Ninjato | 用户录像的客户端构建、套装等级、具体替代武器、附加特技、装备强度与模式规则均未锁定 |
| 刘泉纬 | 《暗影格斗3》**盘古 / Primordial Heavenly King**，王朝派系，**长柄单大斧** | 官方国服 App Store 明确公布盘古套装；国际服商店使用 Primordial Heavenly King 名称；三份原作者实机展示同一长柄单斧和四个原初招式 | 客户端构建、等级、武器内部资源 ID、正式版数值和玩家配置未锁定 |

**盘古不是双锤。** 本轮盘古目标不得继续沿用旧文档中的“双锤刘泉纬”作为武器、动作或机制身份。旧双锤角色资源可以保留其历史用途，但不能用来证明盘古已经还原。同样，孙登本轮目标为 Ninjato 双刀，不是旧单刀目标，也不是霓幻魅影的 Dual Katanas 套装。

本文对目标身份的更新优先于 `fighter-video-reference-20261113.md` 中更早的单刀／双锤描述；不改写那份历史录像的观察结果。

## 2. 来源、版本与证据等级

证据等级定义：

- **A：目标或官方直接证据。** 用户指定录像的直接观察，或开发商／发行方明确公告；只支持它实际展示或声明的事项。
- **B：原作者实机直接证据。** 已查看游戏画面、游戏内技能面板或操作演示；若为测试版，其事实只在该来源版本内成立。
- **C：查找线索。** 社区整理、作者口述但画面未独立证明的数值、或尚未查看的章节。不能直接成为已核实的正式版参数。

### 用户目标录像 R0

- 文件名：`ScreenRecording_11-14-2026 11-00-58_1.mp4`。
- 已解码媒体信息：时长 **12.966667 秒**，1112 × 512，30 FPS。
- SHA-256：`23143ed4552268ad7175d12806eba0a977c2770565a814731014de4069d774e9`。
- 用户关联来源：[抖音原链接](https://v.douyin.com/iA0pTSW58xQ/)，作者线索“三神 Daylight”。作者线索不是客户端版本证明。
- 本轮实际查看了 0.1 秒、2 秒、7 秒等帧。**7 秒**画面可同时看到左侧黑红双刀、紫雾／魂影和右侧赵云附近的紫色根枝形态。
- 此片段没有装备／套装等级页面，也没有干净的技能说明或完整回合起止。不能由血条长度、图标计数或短片段伤害量反推出固定 HP、倍率、冷却或完整招式表。
- 原录像、抽帧及个人存储定位信息不提交到仓库。

### 可公开复核的原始与官方来源

| ID | 来源与发布时间 | 实际可复核时间 | 版本与用途 |
|---|---|---|---|
| D1 | SF3 Warrior：[Lv.6 DFT vs Heir of Pangu (Hard Mode), No Perk Challenge](https://www.youtube.com/watch?v=Qiu0iqMLpL8)，2026-09-01 | [00:20](https://www.youtube.com/watch?v=Qiu0iqMLpL8&t=20s)说明使用 6 级 DFT、无特技及无氏族武器；[00:32](https://www.youtube.com/watch?v=Qiu0iqMLpL8&t=32s)开始第一回合 | **6 级对照角色**；用于核对外形与战斗形态。该等级与配置不能自动赋给 R0。右侧 Heir of Pangu 是 Boss，不能把 Boss 规则全部赋给玩家盘古 |
| D2 | Arifo：[New Set! DEAD FOREST TRIAD — In-depth Review](https://www.youtube.com/watch?v=bhS0h_YXHqo)，2024-09-18 | [00:40–00:45](https://www.youtube.com/watch?v=bhS0h_YXHqo&t=40s)明确说明创作者抢先测试版；[00:55–02:55](https://www.youtube.com/watch?v=bhS0h_YXHqo&t=55s)展示基础机制 | **早期测试版**；可核对雾能、诅咒、压制波等机制语义；不能作为 2026 年正式版全部参数 |
| D3 | Professor Rk Gaming：[Dead Forest Triad — Level By Level](https://www.youtube.com/watch?v=uzHLsGN_CCg)，2024-09-21 | [01:30–02:40](https://www.youtube.com/watch?v=uzHLsGN_CCg&t=90s)雾能和回合结束吸魂；[04:10–05:40](https://www.youtube.com/watch?v=uzHLsGN_CCg&t=250s)Mist Blade 与强化雾波 | **旧版原作者实机**；没有锁定构建号。画面和作者说明区分登记，数值不提升为当前正式版规则 |
| D4 | 官方 Shadow Fight Telegram：[三魄新增 7／8 级公告，帖子 997](https://t.me/shadowfightgames/997)；[可读频道上下文](https://t.me/s/shadowfightgames) | 无视频时间 | **官方发布事实**：截至本次核查，三魄已有 7、8 级。公告没有给出完整数值表，不能据此确认测试版参数未改变 |
| D5 | Arifo：[Dead Forest Triad Level 7 & 8](https://www.youtube.com/watch?v=Tyj_B8927Yw)，2026-11-04 | [00:05](https://www.youtube.com/watch?v=Tyj_B8927Yw&t=5s)明确 beta；[00:45–01:10](https://www.youtube.com/watch?v=Tyj_B8927Yw&t=45s)7 级；[01:15](https://www.youtube.com/watch?v=Tyj_B8927Yw&t=75s)起 8 级 | **NEKKI beta 测试版**，开场明确正式发布前仍可能改动 |
| D6 | Quarantine Gaming：[Dead Forest Triad Level 7 & 8 Gameplay](https://www.youtube.com/watch?v=bFIs0litmQA)，2026-11-04 | [00:15](https://www.youtube.com/watch?v=bFIs0litmQA&t=15s)说明 beta；[00:30](https://www.youtube.com/watch?v=bFIs0litmQA&t=30s)起展示 7／8 级；[02:05](https://www.youtube.com/watch?v=bFIs0litmQA&t=125s)双刀装备卡 | **beta**；有占位文本和作者指出的异常。可交叉核对新版语义与 Ninjato 装备身份 |
| P0-CN | [国服官方 App Store](https://apps.apple.com/cn/app/%E6%9A%97%E5%BD%B1%E6%A0%BC%E6%96%973/id6468901926?platform=ipad) | 无视频时间 | 发行方页面明确盘古套装；不是完整技能规范 |
| P0-EN | [国际服官方 App Store](https://apps.apple.com/nz/app/shadow-fight-3-rpg-fighting/id964827011) | 无视频时间 | 页面活动使用 Primordial Heavenly King 名称 |
| P1 | Shadow Gamer：[Primordial Heavenly King — detailed review](https://www.youtube.com/watch?v=othVs1yco3o)，2026-08-25 | [01:09](https://www.youtube.com/watch?v=othVs1yco3o&t=69s)1 级；[06:46](https://www.youtube.com/watch?v=othVs1yco3o&t=406s)2 级；[20:08](https://www.youtube.com/watch?v=othVs1yco3o&t=1208s)3 级；[22:00](https://www.youtube.com/watch?v=othVs1yco3o&t=1320s)4 级；[39:36](https://www.youtube.com/watch?v=othVs1yco3o&t=2376s)5 级；[44:11](https://www.youtube.com/watch?v=othVs1yco3o&t=2651s)6 级 | **存在未完成本地化的测试／预发布面板**：可直接读到机制，但数字显示 `{0}%` 等占位符。不能据此填写正式倍率 |
| P2 | HUY：[Primordial Heavenly King gameplay and bonus showcase](https://www.youtube.com/watch?v=GNw-4YUvN70)，2026-08-25 | [02:43](https://www.youtube.com/watch?v=GNw-4YUvN70&t=163s)1 级；[03:53](https://www.youtube.com/watch?v=GNw-4YUvN70&t=233s)2 级；[05:32](https://www.youtube.com/watch?v=GNw-4YUvN70&t=332s)3 级；[06:04](https://www.youtube.com/watch?v=GNw-4YUvN70&t=364s)4 级；[07:42](https://www.youtube.com/watch?v=GNw-4YUvN70&t=462s)5 级；[08:29](https://www.youtube.com/watch?v=GNw-4YUvN70&t=509s)6 级 | 同期原作者实机；界面仍有 `ERR_...`，解说把缺失参数写为 X。用于交叉确认动作与触发关系 |
| P3 | Quarantine Gaming：[Primordial Heavenly King — All Level & abilities](https://www.youtube.com/watch?v=ILQbJiTv52s)，2026-08-25 | [00:05–00:10](https://www.youtube.com/watch?v=ILQbJiTv52s&t=5s)装备；[01:07](https://www.youtube.com/watch?v=ILQbJiTv52s&t=67s)2 级；[03:24](https://www.youtube.com/watch?v=ILQbJiTv52s&t=204s)3 级；[03:50](https://www.youtube.com/watch?v=ILQbJiTv52s&t=230s)4 级；[05:18](https://www.youtube.com/watch?v=ILQbJiTv52s&t=318s)6 级 | 同期测试实机；头盔显示 `ERR_HELM_AGL_48`。这是检索资产的线索，**不是已确认的盘古武器资源 ID** |

上述时间是原视频的复核入口／已观察画面时间，不是恢复出来的逐帧命中时间。取得的是公开视频元数据、公开分镜以及用户原录像抽帧；没有通过这些资料恢复原游戏程序或正式服数值配置。

## 3. 孙登：已确认语义与实现边界

| 机制 | 触发与结果 | 证据 | 可用于实现的结论／缺口 |
|---|---|---|---|
| 双刀身份 | 黑红 DFT 装束；两把直刀在强化时呈紫色；背后三个傀儡 | A：R0 的 0.1／2／7 秒；B：D1 00:20–00:32；D6 [02:05](https://www.youtube.com/watch?v=bFIs0litmQA&t=125s)装备卡 | 应使用 Ninjato 双持姿态和左右独立刀轨。R0 具体是否为替代武器仍为 `null` |
| 雾能资源 | 使用 Mist energy；可通过诅咒、压制及回合胜利相关机制获得，演示中会保留到后续回合 | B：D2 [01:10–01:25](https://www.youtube.com/watch?v=bhS0h_YXHqo&t=70s) | 雾能不是普通暗影变身条。当前正式版初值、上限、跨回合保留比例和各次回能量为 `null` |
| 开场暴击准备 | 旧版演示开局带 Breakthrough 充能，在实际击中前保持 | B：D2 [00:55](https://www.youtube.com/watch?v=bhS0h_YXHqo&t=55s)、[01:30](https://www.youtube.com/watch?v=bhS0h_YXHqo&t=90s) | 需要区分准备态、挥空和命中消费。当前充能时间、暴击倍率及 R0 是否带额外特技为 `null` |
| Afterlife Forest | 开场召出雾林并诅咒对手；对手使用暗影招式可触发眩晕、输出削弱及三魄回雾能 | B：D2 [01:40–02:10](https://www.youtube.com/watch?v=bhS0h_YXHqo&t=100s)；D3 [01:30–01:40](https://www.youtube.com/watch?v=uzHLsGN_CCg&t=90s) | 应由“对手启动对应招式”事件检查，不能把进入雾区或每帧站立当成同一触发。概率、内置 CD、适用能量类别为 `null` |
| Mist Onslaught | 远程输入被替换为压制雾波；未强化时表现为穿过目标的压制作用。处于 Mist Blade 时，波变为有伤害与硬直的命中 | B：D2 [02:20–02:40](https://www.youtube.com/watch?v=bhS0h_YXHqo&t=140s)；D3 [05:20–05:40](https://www.youtube.com/watch?v=uzHLsGN_CCg&t=320s) | 压制应用与实体波伤害需分开；不能给未强化波套同一直接伤害。当前段数、范围、CD、伤害、穿透与防御细则为 `null` |
| 压制后的回能／持续效果 | 演示说明攻击被压制目标可恢复雾能；目标输出降低且承受持续伤害，效果可以叠加 | B：D2 [02:45–02:55](https://www.youtube.com/watch?v=bhS0h_YXHqo&t=165s) | 命中、挥空和持续伤害应分别计事件。叠层上限、持续时间、每跳数值、格挡算不算有效攻击均为 `null`；早期视频数字不能直接当现行值 |
| Mist Blade | 前方向能力输入后双刀转紫，强化近战并改变雾波效果；属于限时状态 | B：D3 [04:10–05:40](https://www.youtube.com/watch?v=uzHLsGN_CCg&t=250s) | 需要独立状态和动作入口。关于“必须先暴击才解锁”的完整条件，本轮没有取得足够连续画面证明，不能将社区概述提升为已核实正式条件；持续时间和转伤比例为 `null` |
| Feast | 击败对手后的回合结束演示吸取魂／雾能，随后下一回合带相应资源 | B：D3 [01:50–02:40](https://www.youtube.com/watch?v=uzHLsGN_CCg&t=110s) | 触发应依赖实际回合胜利结算，不是普通命中。获得量以及平局／特殊模式条件为 `null` |
| 根枝禁锢、魂影攻击 | 用户目标片段实际出现紫色根枝及独立魂影；须有目标控制与召唤表现 | A：R0 **07.00 秒**；B：D1 [00:32 起](https://www.youtube.com/watch?v=Qiu0iqMLpL8&t=32s)6 级对战 | 已确认其为目标视觉／战斗形态，但 13 秒录像不能证明完整技能顺序。根枝命中条件、禁锢时长、各魂种的伤害／资源消耗／CD／自动连发条件为 `null` |

### 尚不能写成“正式版完全核实”的三魄规则

旧版社区资料会列出 Branches Underneath、Consumed Legionary／Herald／Dynast、Crying Dance、Forest Rain、notches 层数以及替代武器 Whispers of the Consumed 的改动。它们是有效检索线索，但本次没有逐条取得与 R0 相同版本、同等级、同武器配置的连续技能面板证明。**不能仅凭三个召唤物名字或动作文件存在就宣称全部伤害、触发和资源规则已恢复。**

源资产审计发现的 `set_h17`、`h17_root_spike_*`、`h17_wave_ability_*`、`h17_buff_ability`、`h17_trans_*` 只能帮助建立原动作身份和动作阶段。具体数量、哈希与可用性以源资产审计的报告为准；动画文件名本身不证明冷却、伤害或控制规则。

### 7／8 级：官方发布与 beta 参数必须分开

官方 [D4 帖子 997](https://t.me/shadowfightgames/997)已经确认三魄获得 7、8 级。因此“原版最高只有 6 级”已经不成立；但 R0 是几级仍未知。

| 测试版观察 | 来源时间 | 可记录的版本事实 | 当前正式版参数 |
|---|---|---|---|
| 7 级开局带雾能 | D5 [00:45](https://www.youtube.com/watch?v=Tyj_B8927Yw&t=45s)；D6 [00:30](https://www.youtube.com/watch?v=bFIs0litmQA&t=30s) | beta 作者展示／说明 **30%** 初始资源；D5 文案称 shadow energy，不能据此把实际三魄资源改名 | `null`，需正式版面板核对 |
| 7 级增加对军团装备的减伤 | D5 [00:50–01:10](https://www.youtube.com/watch?v=Tyj_B8927Yw&t=50s) | beta 说明按军团护甲／武器检查；包含物理武器伤害和暗影伤害调整 | `null`，不能先合并成对所有目标统一减伤 |
| 8 级追加魂、延长禁锢 | D6 [01:00](https://www.youtube.com/watch?v=bFIs0litmQA&t=60s)、[01:30](https://www.youtube.com/watch?v=bFIs0litmQA&t=90s) | beta 作者展示／说明 **50%** 追加魂概率、每魂击延长根枝禁锢 **0.2 秒** | 概率、延长量、上限、是否要求有效伤害均为 `null` |
| 8 级扩展对王朝／先锋的防护 | D5 [01:15 起](https://www.youtube.com/watch?v=Tyj_B8927Yw&t=75s)；D6 [01:50](https://www.youtube.com/watch?v=bFIs0litmQA&t=110s) | 版本方向可确认，具体装备条件和乘算方式未完成正式核对 | `null` |

测试版数字只作为版本对照记录，不是建议默认值，也不是本项目已经通过的还原参数。

## 4. 刘泉纬盘古：可直接读到的触发链

以下主要依据 P1 的**游戏内技能面板**，再用 P2／P3 的实际动作交叉核对。面板含占位数字，所以“机制存在”和“正式版数值已知”是两件事。方向均以角色面对对手时的前／后为准；不能固定成屏幕左／右。

### 1／2 级基础

| 等级／机制 | 已读到的触发与结果（中文概述） | 原实机依据 | 数值／边界 |
|---|---|---|---|
| L1：光能与生命 | 使用 Light energy；成功命中回光能；受到伤害先扣光能，再影响生命 | P1 [01:30–02:50](https://www.youtube.com/watch?v=othVs1yco3o&t=90s)；P3 [00:20–00:40](https://www.youtube.com/watch?v=ILQbJiTv52s&t=20s) | 初值、上限、回能量、光能与伤害换算、溢出承伤及不可吸收伤害类别均 `null` |
| L1：连击增伤 | 每获得连击点增加输出，存在上限 | P1 [01:30–02:50](https://www.youtube.com/watch?v=othVs1yco3o&t=90s) | 每点增幅、上限、独立乘区和失效时刻均 `null` |
| L1：免投／脱离抓取 | 不能被投掷；对手尝试投掷时自动挣脱 | P1 [01:30–02:50](https://www.youtube.com/watch?v=othVs1yco3o&t=90s)；P2 [02:43 起](https://www.youtube.com/watch?v=GNw-4YUvN70&t=163s) | 抓取检查阶段、反击伤害和对 Boss 特殊抓取的适用性 `null`；不能把一次免投扩成全时无敌 |
| L2：原初招式准备 | 回合开始有四个 Primordial Moves 可用；它们成功命中会恢复光能 | P1 [06:50–10:20](https://www.youtube.com/watch?v=othVs1yco3o&t=410s) | 使用前资源要求、各自／共享 CD 和命中回能量 `null` |
| L2：Primal Onslaught | 达到连击门槛后，重击会附带风刃；风刃造成暗影伤害 | P1 [06:50–10:20](https://www.youtube.com/watch?v=othVs1yco3o&t=410s) | 门槛、风刃数量、伤害、追踪、同击多段计数 `null` |
| L2：Shard of Creation（前） | 向对手掷出岩石，造成暗影伤害 | P1 [06:50–10:20](https://www.youtube.com/watch?v=othVs1yco3o&t=410s)；P2 [03:53–05:31](https://www.youtube.com/watch?v=GNw-4YUvN70&t=233s) | 投射物速度、范围、阻挡／反射、伤害、CD `null` |
| L2：Primordial Typhoon（后） | 周身风流持续一段时间，提升输出；每次攻击附加暗影伤害风刃；面板强调其冷却有固定规则 | P1 [06:50–10:20](https://www.youtube.com/watch?v=othVs1yco3o&t=410s)；P2 [03:53–05:31](https://www.youtube.com/watch?v=GNw-4YUvN70&t=233s) | 持续时长、增伤、风刃倍率及固定 CD 值 `null`；与后续等级减 CD 的优先顺序未核 |
| L2：Horizon Splitter（上） | 斧头向上劈挑，造成**武器伤害**，把对手挑到空中保持一段时间 | P1 [12:00–13:20](https://www.youtube.com/watch?v=othVs1yco3o&t=720s)；P2 [03:53–05:31](https://www.youtube.com/watch?v=GNw-4YUvN70&t=233s) | 不能与石刺的暗影伤害混为一类；发射速度、滞空、落地、倍率、CD `null` |
| L2：Bones of the Earth（下） | 跺地召出尖锐石刺，命中造成暗影伤害 | P1 [12:00–13:20](https://www.youtube.com/watch?v=othVs1yco3o&t=720s)；P3 [01:07–03:23](https://www.youtube.com/watch?v=ILQbJiTv52s&t=67s) | 地面范围、空中目标可否中招、击退／击倒条件、倍率和 CD `null` |
| L2：Ancient Hunt → Rhythm of the Firmament | 原初招式命中后获得限时状态；期间远程投矛将对手钉在岩石上，造成眩晕及暗影伤害 | P1 [12:00–13:20](https://www.youtube.com/watch?v=othVs1yco3o&t=720s)；P2 [03:53–05:31](https://www.youtube.com/watch?v=GNw-4YUvN70&t=233s) | 这是“原初命中 → 远程强化 → 命中后钉岩”的链条，不能让普通远程无条件永久钉岩；状态、眩晕时长、次数和伤害 `null` |
| L2：Heavenfall（主动天坠） | 先石化对手，再攀上岩柱、积累光能，最后向下砸击造成暗影伤害 | P1 [12:00–13:20](https://www.youtube.com/watch?v=othVs1yco3o&t=720s)；P2 [03:53–05:31](https://www.youtube.com/watch?v=GNw-4YUvN70&t=233s) | 必须区分石化、上升、蓄能、坠落、落地命中；时长、是否可打断、无敌、回能和伤害全部 `null` |

### 3／4／5／6 级扩展

| 等级／机制 | 已确认的来源版本行为 | 原实机依据 | 数值／边界 |
|---|---|---|---|
| L3：Great Ancestor | 攻击获得更多光能；达到连击门槛后，风刃触发扩大到所有攻击 | P2 [05:32–06:03](https://www.youtube.com/watch?v=GNw-4YUvN70&t=332s)；P3 [03:24–03:49](https://www.youtube.com/watch?v=ILQbJiTv52s&t=204s) | 门槛、回能量和哪些命中事件计入 `null` |
| L4：Weight of Creation | 岩石增伤并追加眩晕 | P1 [22:30–24:50](https://www.youtube.com/watch?v=othVs1yco3o&t=1350s)；P3 [04:30](https://www.youtube.com/watch?v=ILQbJiTv52s&t=270s) | 增伤、眩晕时长及控制抗性 `null` |
| L4：Gates of the Storm | 风状态中可瞬移到对手身后，每个招式冷却周期有使用限制；该状态下降低光能承伤 | P1 [22:30–24:50](https://www.youtube.com/watch?v=othVs1yco3o&t=1350s)；P3 [05:05](https://www.youtube.com/watch?v=ILQbJiTv52s&t=305s) | 需限制瞬移次数并重新校准朝向／碰撞；减伤率、判定距离与 CD `null` |
| L4：Crushing Heavens | 上挑增伤，追加风刃攻击空中目标；施加 Primordial Dread，使目标受到更多伤害且输出降低 | P1 [22:30–24:50](https://www.youtube.com/watch?v=othVs1yco3o&t=1350s)；P3 [04:50](https://www.youtube.com/watch?v=ILQbJiTv52s&t=290s) | 风刃数、追击间隔、增伤与减伤、状态持续及叠加 `null` |
| L4：Lord of the Firmament | 跺地后一段时间内，自己的跳跃落地可击倒对手；另一个限时窗口内掷岩附加徒手物理伤害和眩晕 | P1 [27:10–28:20](https://www.youtube.com/watch?v=othVs1yco3o&t=1630s)；P3 [04:00](https://www.youtube.com/watch?v=ILQbJiTv52s&t=240s)落地击倒 | 应检查真实落地事件，不能跳起即击倒；两个窗口、范围、附伤及控制时长 `null` |
| L4：Meditation of Heaven and Earth／Elden Storm | 原初招式冷却缩短；达到连击门槛后提高攻击速度 | P1 [27:10–28:20](https://www.youtube.com/watch?v=othVs1yco3o&t=1630s) | CD 减量、连击阈值、攻速、动画与判定时间缩放方法 `null` |
| L5：Bastion of Harmony | 原初命中回能进一步提高；所有攻击，包括被格挡攻击，也可回能 | P1 [39:40–40:20](https://www.youtube.com/watch?v=othVs1yco3o&t=2380s)；P2 [07:42–08:28](https://www.youtube.com/watch?v=GNw-4YUvN70&t=462s) | 有效命中与被格挡命中应分别记录，挥空没有被证明也回能；具体回能量 `null` |
| L5：远程阈值强化 | 达到连击门槛后，远程充能补充更快，并持续使用钉岩版本 | P1 [39:40–40:20](https://www.youtube.com/watch?v=othVs1yco3o&t=2380s)；P2 [07:42–08:28](https://www.youtube.com/watch?v=GNw-4YUvN70&t=462s) | 阈值、补充倍率、充能数和阈值失去后的回退 `null` |
| L6：Unyielding | 受击不再重置连击，连击保持时间延长；达阈值后原初招式不再进入冷却，Heavenfall 冷却缩短 | P1 [45:00–46:20](https://www.youtube.com/watch?v=othVs1yco3o&t=2700s)；P3 [05:25–05:50](https://www.youtube.com/watch?v=ILQbJiTv52s&t=325s) | P3 作者在测试演示中说明门槛为 **100 连击**，P1 面板该项仍为占位符。因此当前正式阈值记 `null`，不能把测试数字当正式数据 |
| L6：Lord of Heaven and Earth | 原初招式充能／冷却恢复加快 | P1 [45:00–46:20](https://www.youtube.com/watch?v=othVs1yco3o&t=2700s) | 具体加速和对固定 CD 的覆盖关系 `null` |
| L6：Legend of the Great Sundering | Heavenfall 回能和伤害提高，并提供连击点；使用后进入限时 Primordial Trance | P1 [45:00–46:20](https://www.youtube.com/watch?v=othVs1yco3o&t=2700s)；P2 [09:00–10:20](https://www.youtube.com/watch?v=GNw-4YUvN70&t=540s) | 回能、伤害、连击点、状态开始阶段和时长 `null` |
| L6：Primordial Trance | 提高攻速、防御；成功攻击有概率多得连击点；每次攻击召出风刃 | P1 [48:00–49:20](https://www.youtube.com/watch?v=othVs1yco3o&t=2880s)；P2 [09:00–10:20](https://www.youtube.com/watch?v=GNw-4YUvN70&t=540s) | 各增幅、概率、风刃伤害、重复触发防护及叠加规则 `null` |

由这些原始面板可以确定：盘古应围绕**光能承伤 → 命中回能 → 连击门槛 → 四招控制与风刃 → 天坠强化状态**运行。把它做成“固定伤害的双锤大招”不能满足本轮目标。该结论不意味着上表任何缺失数值已经被恢复。

## 5. 必须保留未知值的参数表

| 参数族 | 三魄 | 盘古 | 缺少的直接证据 |
|---|---|---|---|
| 目标客户端／构建／区域 | `null` | `null` | 连续展示版本和装备的原录像或匹配发布配置 |
| R0／目标配置的套装等级 | `null` | `null` | 用户目标的实际装备与升级页面 |
| 装备力量、特技与替代武器 | `null` | `null` | 同配置清单；D1 的无特技配置不能替代用户配置 |
| 最大 HP 与护甲减伤 | `null` | `null` | 原版模式／装备计算；血条像素不能换算固定生命 |
| 每招基础伤害与伤害类型修正 | `null` | 数种类型已辨识，倍率 `null` | 当前正式技能配置与同条件可复现测试 |
| 起手、有效帧、收招、命中停顿 | `null` | `null` | 连续无变速、无剪辑的动作采样及接触帧标记 |
| 击退距离／速度与击飞轨迹 | `null` | `null` | 同镜头尺度、双方位置、输入和地面状态的连续对照 |
| 倒地／起身与控制免疫 | `null` | `null` | 普通、格挡、霸体、空中、倒地及特殊 Boss 分别测试 |
| 能量初值、上限、消耗、回能与溢出 | `null` | `null` | 当前正式配置及逐事件数值；测试面板占位不能填 0 |
| 冷却、持续时间、层数／连击阈值 | `null` | `null` | 当前正式版对应等级面板；beta 参数仅作版本记录 |
| 互相作用的优先级 | `null` | `null` | 例如根枝与盘古免投并不等同；控制、护盾、伤害和格挡先后顺序未完整验证 |

实现可先使用明确标记的项目调试参数完成可玩闭环，但这些值必须与“原版已核参数”分开。`null` 表示尚未确认，不等于 0、无效果、无限时长或自动采用旧版 wiki 默认值。

## 6. 用于实现和复核的状态要求

下列是由上述证据导出的工程要求，不是对原游戏源码结构的声明：

1. 记录两位角色各自的身份、套装等级、版本和武器变体；选择 6 级对照时不能暗中混入 7／8 级能力。
2. 攻击命中、被格挡、挥空、持续伤害、召唤物命中和回合结束采用不同事件，避免一段表现重复回能或重复计连击。
3. 伤害结算保留武器／徒手物理／暗影等类别；盘古光能承伤先于生命处理，但当前换算、溢出和例外必须另行核实。
4. 将硬直、眩晕、根枝禁锢、石化、击飞、倒地和免投区分。免投不自动免疫石化、根枝或普通命中；未核实的交互不能凭名称推断。
5. 对于瞬移和飞行，分别处理朝向、位置、碰撞、刀轨／斧轨断点；不能从旧位置跨屏生成一条假伤害轨迹。
6. 把 Heavenfall 的石化、攀升、回能、坠落和落地接触拆成可观察阶段；将附伤／召唤的判定绑定到对应事件，而不是仅播放特效。
7. 验收逐项比较同阶段的原录像与本项目录像，记录真实接触、资源变化、控制状态与动画。动作源接上、单测通过或技能名字一致，均不单独证明“游戏内机制完全还原”。

本文只提交事实概述、可复核链接和未知项；没有复制原版技能说明全文，也没有把第三方录像、音乐或图片作为项目分发资源。
