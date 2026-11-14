# 刘泉纬盘古：1—6 级机制、正式期证据与实现接口

核对日期：2026-11-14。本文服务于《裂隙对决》的盘古机制还原；它是证据与接口说明，不是原版全部参数已经恢复的声明。

## 1. 结论与证据等级

目标套装英文名为 **Primordial Heavenly King**，盘古的正式期武器面板显示 **STORMBORN / LEGENDARY TWO-HANDED AXE**，应表现为一把双手持握的长柄大斧，不能继续沿用双锤。该面板见 [A1，10:10](https://www.youtube.com/watch?v=1pblpwg6QJk&t=610s)。同一录像的头盔、护甲名称分别为 PINNACLE OF CREATION、PRIMORDIAL FIRMAMENT，见 [09:40—10:10](https://www.youtube.com/watch?v=1pblpwg6QJk&t=580s)。

**派系正式值仍为 `null`。** Q1 的视频说明称其为 Dynasty，但本轮没有读到清楚显示派系的正式游戏字段；不能由神话题材、动作观感、武器通常所属派系或 `AGL_48` 头盔索引推断。界面可用“盘古 · 双手长斧”。本结论修正前稿把“王朝”写成已确认身份的表述。

当前恢复了 Light 承伤、连击、四向原初招式、钉岩长矛、天坠、四级强化和六级 Trance 的机制结构；正式期原作者实机补出了部分 2／4 级数字。**Light 与 HP 的换算、六级正式阈值及全部伤害倍率仍未核实。** `null` 不表示 0、永久、无限次或无效果。

| 标记 | 含义 | 可以据此做什么 |
|---|---|---|
| `official` | 开发者官方发布、商店版本记录 | 确认发布存在及该记录的版本，不能替代技能配置 |
| `live_ui` | 正式推出后原作者录像中可读的游戏 UI | 核实画面中确实显示的项目 |
| `live_overlay` | 正式推出后原作者实机的自制字幕 | 保留为有来源的报告值，低于清晰的游戏数字面板 |
| `live_observation` | 正式期实机直接可见的动作／HUD 变化 | 确认该场景行为，不能从几张图推出精确帧数或所有边界 |
| `beta_ui` | 2026-08-25 测试版游戏面板 | 恢复语义；占位符不能变成正式参数 |
| `beta_overlay` | 测试版原作者字幕 | 单独记录候选值，不能默认为正式值 |
| `rule_unknown` | 不仅缺数字，还缺实际判定方式 | 需独立策略接口，不能用某个任意常数掩盖 |
| `parameter_unknown` | 触发关系已知，缺倍率／时长等 | 可先做状态链，项目调试值须另记来源 |

## 2. 来源、发布日期与版本边界

| ID | 原始来源 | 日期与可复核内容 | 使用限制 |
|---|---|---|---|
| O1 | [Shadow Fight 官方频道，post 937](https://t.me/shadowfightgames/937)，亦见 [频道分页](https://t.me/s/shadowfightgames?before=939) | 官方宣布新增该传奇套装，经 Battle Pass 获得 | 本轮网页只返回 16:26，未返回日历日期；正式发布精确日期仍 `null` |
| O2 | [国服 App Store](https://apps.apple.com/cn/app/%E6%9A%97%E5%BD%B1%E6%A0%BC%E6%96%973/id6468901926?platform=tv) | 开发者商店页以盘古为二周年内容；版本记录 1.45.4 为 8 月 25 日，下一条 1.45.3 为 7 月 22 日 | 这是国服商店记录，不是国际服录像构建号，也不能证明热更新配置相同 |
| A1 | [Aimpire Gamerz：逐级评测](https://www.youtube.com/watch?v=1pblpwg6QJk) | 公开播放器 `publishDate=2026-10-17T03:38:32-07:00`，19:51；0:50 升级面板、6:30 升 3 级、7:10—7:20 升 4 级，后半为 4 级实战 | 无 beta 标识，装备名已正常解析；具体客户端 build 未展示。数字字幕与游戏 UI 必须区分。此片没有继续升级 5／6 级 |
| R1 | [Professor Rk Gaming：盘古对盘古](https://www.youtube.com/watch?v=f0sL5YrGMjM) | 2026-08-28；0:25—0:40 连续展示升级 UI；[0:45—0:55](https://www.youtube.com/watch?v=f0sL5YrGMjM&t=45s) 自制字幕称本人为 5 级 | 说明文字称 6 级，但画面字幕称 5 级，不能拿标题／说明覆盖实际画面。缓存缩略图的数字太小，不录入猜测值 |
| T1 | [哈囉皮帝亞 Pedia 直播](https://www.youtube.com/watch?v=t9NO5ZS4330) | 播放器发布时间 `2026-10-16T19:55:19-07:00`；标题称 6 级盘古；[1:13:20—1:16:20](https://www.youtube.com/watch?v=t9NO5ZS4330&t=4400s) 有装备、战斗及训练 | 直播大部分是二郎神冒险；已检查片段未找到清晰的套装 5／6 级说明，标题不能单独证明全部参数 |
| V1 | [Venomous vex：盘古训练与突袭](https://www.youtube.com/watch?v=1D-xW-2zJqg) | 2026-08-31；[0:16—0:40](https://www.youtube.com/watch?v=1D-xW-2zJqg&t=16s) 展示配装，武器为 CHAOS SPLITTER；[0:46—2:44](https://www.youtube.com/watch?v=1D-xW-2zJqg&t=46s) 训练可见连击超过 100 和多次天坠 | 配有特技，且不是 A1 的 Stormborn 斧。只能作为形态与连击表现旁证，不能由血条变化反算裸装数值 |
| B1 | [Shadow Gamer：完整 1—6 级说明](https://www.youtube.com/watch?v=othVs1yco3o) | `2026-08-25T03:00:01-07:00`；章节：1:09／6:46／20:08／22:00／39:36／44:11 | 游戏面板仍有 `{0}` 等占位符；只采用能够读清的机制语义 |
| B2 | [HUY：技能及强敌演示](https://www.youtube.com/watch?v=GNw-4YUvN70) | 2026-08-25；2:43／3:53／5:32／6:04／7:42／8:29 对应六级说明 | `ERR_...` 本地化与 X 占位仍在，属于测试期证据 |
| Q1 | [Quarantine Gaming：全等级与能力](https://www.youtube.com/watch?v=ILQbJiTv52s) | `2026-08-25T03:00:03-07:00`；0:00／1:07／3:24／3:50／5:18；5:25—5:50 作者说明 100 连击门槛 | 测试素材，100 只能标为测试报告值，正式阈值仍 `null` |
| B3 | [Professor Rk Gaming：测试版逐级评测](https://www.youtube.com/watch?v=_NIJn-bJits) | 2026-08-25；说明明确说来自 Beta，并预告该周三推出；0:50／1:48／5:02／5:26／7:08／7:34 | 周三对应 2026-08-26，但这仅是作者预告，不是已核的官方实际上线时间 |

不能把上述“8 月 25 日测试录像上传日”“作者预告的周三”“国服 1.45.4 包更新时间”“官方正式推出帖”合并为同一日期或构建。也不能因取得某个 1.46.1 安装包，就断言其中内置本地化等于上述录像加载过的热更新配置。

## 3. 1—6 级触发与结果表

下表是累加升级：高等级继承低等级能力。`已核语义`指对应来源中读到的机制，不表示 2026-11-14 的所有正式数值已确认。

| 等级／机制 | 触发条件与结果 | 数据及规则缺口 | 原始依据 |
|---|---|---|---|
| L1 / Origin of Time：Light | 成功命中回光能；来伤先作用于光能，光能承担防护作用 | 回能量、初始量、容量、与 HP 的单位换算均未知；穿透、溢出、DOT、击倒仍否触发属于规则未知 | [B1 1:30—2:50](https://www.youtube.com/watch?v=othVs1yco3o&t=90s)；[A1 1:20—2:20](https://www.youtube.com/watch?v=1pblpwg6QJk&t=80s) |
| L1：连击增伤 | 连击点提高输出，存在上限 | 每点增幅、上限、乘区未知；何种命中计点、被格挡计点、基础超时与中断细则未核 | [B1 1:30—2:50](https://www.youtube.com/watch?v=othVs1yco3o&t=90s)；[Q1 0:20—0:40](https://www.youtube.com/watch?v=ILQbJiTv52s&t=20s) |
| L1：免投与挣脱 | 对手尝试普通投掷时能自动摆脱，不能按普通角色处理投技 | 不等于免疫根枝、石化或所有 Boss 抓取；是否附反击与特效时序未核 | [B2 2:43—3:52](https://www.youtube.com/watch?v=GNw-4YUvN70&t=163s) |
| L2：Primal Onslaught | 达连击门槛后，重击附带暗影伤害风刃 | 正式期作者报告门槛 15；“达到 15 的那一击”还是之后一击生效仍需临界测试 | [A1 5:40—6:10](https://www.youtube.com/watch?v=1pblpwg6QJk&t=340s)；[B1 6:50—10:20](https://www.youtube.com/watch?v=othVs1yco3o&t=410s) |
| L2：Origins of Earth and Heavens | 回合开始四个原初招式可用；原初有效命中回 Light | 不能以每帧重叠持续回能；是否另有资源准入／消耗、共享 CD、CD 开始点未核 | [B1 6:50—10:20](https://www.youtube.com/watch?v=othVs1yco3o&t=410s)；[A1 2:50—4:30](https://www.youtube.com/watch?v=1pblpwg6QJk&t=170s) |
| L2：Shard of Creation，向前 | 抛岩，造成暗影伤害 | 投射物速度、接触体、反射／防御、伤害系数未知；向前以角色朝向定义 | [B2 3:53—5:31](https://www.youtube.com/watch?v=GNw-4YUvN70&t=233s)；[A1 3:00—3:30](https://www.youtube.com/watch?v=1pblpwg6QJk&t=180s) |
| L2：Primordial Typhoon，向后 | 开风状态、增伤，攻击附带暗影风刃 | A1 报告持续 10 秒；增伤和风刃倍率未知。B1 特别说明固定冷却，不能未经验证就被高等级“所有 CD”覆盖 | [B1 6:50—10:20](https://www.youtube.com/watch?v=othVs1yco3o&t=410s)；[A1 3:40—4:20](https://www.youtube.com/watch?v=1pblpwg6QJk&t=220s) |
| L2：Horizon Splitter，向上 | 斧头上挑，武器伤害，挑飞并将对手留在空中一段时间 | 不是石刺暗影伤害；发射、悬停、落地参数及空中／倒地对手判定未知 | [B1 12:00—13:20](https://www.youtube.com/watch?v=othVs1yco3o&t=720s)；[Q1 1:07—3:23](https://www.youtube.com/watch?v=ILQbJiTv52s&t=67s) |
| L2：Bones of the Earth，向下 | 跺地唤石刺，造成暗影伤害 | 地面范围、空中目标和击倒规则未完整核实 | [B1 12:00—13:20](https://www.youtube.com/watch?v=othVs1yco3o&t=720s)；[A1 4:20—4:40](https://www.youtube.com/watch?v=1pblpwg6QJk&t=260s) |
| L2：Ancient Hunt | 原初命中得到限时 Rhythm of the Firmament；此时使用远程变成将敌人钉在岩石上的长矛，带眩晕与暗影伤害 | 状态时长、使用是否消耗状态、矛充能、眩晕、命中范围、免疫处理未知 | [B1 12:00—13:20](https://www.youtube.com/watch?v=othVs1yco3o&t=720s)；[A1 4:40—5:20](https://www.youtube.com/watch?v=1pblpwg6QJk&t=280s) |
| L2：Heavenfall | 主动技能：石化目标、攀上石柱、获得光能、向下冲击，暗影伤害 | 必须拆阶段；阶段精确帧、石化／回能时点、无敌／可打断、CD 与伤害未知 | [B1 12:00—13:20](https://www.youtube.com/watch?v=othVs1yco3o&t=720s)；[A1 5:20—5:30](https://www.youtube.com/watch?v=1pblpwg6QJk&t=320s) |
| L3：Great Ancestor | 提高攻击回 Light；达门槛后的风刃触发扩为所有攻击 | 回能、连击门槛及多段攻击对应次数未知；不能沿用“重击才触发”作为 L3 唯一规则 | [B2 5:32—6:03](https://www.youtube.com/watch?v=GNw-4YUvN70&t=332s)；[A1 6:30—7:00](https://www.youtube.com/watch?v=1pblpwg6QJk&t=390s) |
| L4：Weight of Creation | 前岩增伤并眩晕 | A1 报告眩晕 2 秒；增伤未知 | [A1 7:30](https://www.youtube.com/watch?v=1pblpwg6QJk&t=450s)；[B1 22:30—24:50](https://www.youtube.com/watch?v=othVs1yco3o&t=1350s) |
| L4：Gates of the Storm | 风中再次使用向后原初输入可瞬移到敌背后；一次冷却周期有次数限制；风中降低光能承伤 | A1 报告降低 35%；不等于永久生命减伤。瞬移次数重置点、边界空间、与零 CD 的关系未知 | [A1 7:40—8:00](https://www.youtube.com/watch?v=1pblpwg6QJk&t=460s)；[B1 22:30—24:50](https://www.youtube.com/watch?v=othVs1yco3o&t=1350s) |
| L4：Crushing Heavens | 上挑增伤、追加风刃打空中目标，并施加 Primordial Dread | A1 报告 5 风刃、Dread 10 秒；目标承伤 +50%、输出 −50%。风刃间隔、上挑额外倍率、刷新／叠加未知 | [A1 8:10—8:30](https://www.youtube.com/watch?v=1pblpwg6QJk&t=490s) |
| L4：Lord of the Firmament | 下招后，自己的跳跃落地可击倒；另有限时前岩徒手物理附伤及眩晕 | A1 报告 Earth 状态 9 秒，但未明确把它分别对齐到两项时间字段；两个窗口不能擅自合并 | [B1 27:10—28:20](https://www.youtube.com/watch?v=othVs1yco3o&t=1630s)；[A1 8:40—9:00](https://www.youtube.com/watch?v=1pblpwg6QJk&t=520s) |
| L4：Meditation of Heaven and Earth | 原初招式冷却减少 | A1 报告减少 1 秒；Typhoon 特例优先级未核 | [A1 9:10](https://www.youtube.com/watch?v=1pblpwg6QJk&t=550s) |
| L4：Elden Storm | 连击到门槛后加攻速 | 阈值、速度倍率、与 Trance 的合并方式未知 | [B1 27:10—28:20](https://www.youtube.com/watch?v=othVs1yco3o&t=1630s) |
| L5：Bastion of Harmony | 提高原初命中回 Light；所有攻击，包括被格挡攻击，也可回 Light | 未证明挥空回能；格挡回能不等于格挡计 combo。两类回能叠加／替换规则未知 | [B1 39:40—40:20](https://www.youtube.com/watch?v=othVs1yco3o&t=2380s)；[B2 7:42—8:28](https://www.youtube.com/watch?v=GNw-4YUvN70&t=462s) |
| L5：远程阈值强化 | 达连击门槛后，远程恢复更快，远程使用钉岩版本 | 门槛、充能数与恢复系数未知；不能把限时 Rhythm 改成永久全局标记 | [B1 39:40—40:20](https://www.youtube.com/watch?v=othVs1yco3o&t=2380s) |
| L6：Unyielding | 受击不再清空 combo；连击保持更久；达到阈值后原初招式不再进入 CD，天坠 CD 按倍数缩短 | 正式阈值、延长时间、倍数未知；已有 CD 是否立即清空、Typhoon 例外是否被覆盖属于规则未知 | [B1 45:00—46:20](https://www.youtube.com/watch?v=othVs1yco3o&t=2700s)；[Q1 5:25—5:50](https://www.youtube.com/watch?v=ILQbJiTv52s&t=325s) |
| L6：Lord of Heaven and Earth | 原初招式恢复再加快 | 减少秒数与前述零 CD／Typhoon 特例的优先级未知 | [B1 45:00—46:20](https://www.youtube.com/watch?v=othVs1yco3o&t=2700s) |
| L6：Legend of the Great Sundering | 天坠回能、伤害提高，并给 combo；激活后进入 Primordial Trance | 回能、额外 combo、持续时长、是否在激活／升柱／落地开始未知 | [B1 45:00—46:20](https://www.youtube.com/watch?v=othVs1yco3o&t=2700s)；[B2 9:00—10:20](https://www.youtube.com/watch?v=GNw-4YUvN70&t=540s) |
| L6：Primordial Trance | 增攻速与防御；成功攻击有概率多得 combo；攻击带风刃 | 额外 combo 概率、增幅、风刃、与 Typhoon／普通阈值的重叠计数都未知 | [B1 48:00—49:20](https://www.youtube.com/watch?v=othVs1yco3o&t=2880s)；[B2 9:00—10:20](https://www.youtube.com/watch?v=GNw-4YUvN70&t=540s) |

## 4. 正式期新增数字：严格保留出处类型

下面所有数字均来自 A1 的**作者叠加字幕**，不是清晰可读的游戏数字面板，也不是本项目已经完成的计时实验。A1 的 0:50、6:30、7:20 原始 UI 可核实正在逐级升级，因此这些报告值优于 8 月占位测试版，但依然应保留来源级别。

| 参数 | 报告值 | 原视频位置 | 可安全采用的范围与限制 |
|---|---:|---|---|
| 一般原初招式 CD | 10 秒 | [3:20](https://www.youtube.com/watch?v=1pblpwg6QJk&t=200s) | 用作“作者报告基础值”；尚未逐个完成四方向计时，不能因此断言共享 CD 或 Typhoon 例外 |
| Typhoon 持续 | 10 秒 | [4:00](https://www.youtube.com/watch?v=1pblpwg6QJk&t=240s) | 持续时间，不是同名技能 CD 的独立证明 |
| L2 重击风刃连击门槛 | 15 | [5:40](https://www.youtube.com/watch?v=1pblpwg6QJk&t=340s) | 不能同时填入 L3 全攻击、L4 攻速、L5 远程、L6 零 CD 门槛 |
| L4 前岩眩晕 | 2 秒 | [7:30](https://www.youtube.com/watch?v=1pblpwg6QJk&t=450s) | 上挑悬停、钉岩矛眩晕、天坠石化分别独立 |
| L4 风中 Light 承伤降低 | 35% | [8:00](https://www.youtube.com/watch?v=1pblpwg6QJk&t=480s) | 若承伤模型为线性，等价系数 0.65；该算术等价不证明基础 Light—HP 换算 |
| L4 上挑追击风刃数 | 5 | [8:10](https://www.youtube.com/watch?v=1pblpwg6QJk&t=490s) | 是该强化招式的追击数，不是每次普攻的风刃数 |
| Dread 持续 | 10 秒 | [8:10](https://www.youtube.com/watch?v=1pblpwg6QJk&t=490s) | 刷新、叠加与控制抗性仍未知 |
| Dread 目标承伤 | +50% | [8:20](https://www.youtube.com/watch?v=1pblpwg6QJk&t=500s) | 线性独立项可表示为 1.5；与别的伤害乘区关系未知 |
| Dread 目标输出 | −50% | [8:20](https://www.youtube.com/watch?v=1pblpwg6QJk&t=500s) | 线性独立项可表示为 0.5；不能同时替代自身 Trance 防御 |
| L4 Earth 状态 | 9 秒 | [8:40](https://www.youtube.com/watch?v=1pblpwg6QJk&t=520s) | 只保留报告的 Earth 总称，不自动令两个独立强化窗口都等于 9 |
| L4 原初 CD 缩减 | 1 秒 | [9:10](https://www.youtube.com/watch?v=1pblpwg6QJk&t=550s) | 通常 10−1=9 是推算值，不是四招每招均实测 9 秒 |

## 5. 可实现状态表与事件接口

本节是依据已知触发关系作出的工程设计，不声称是原版源代码结构。把数值未知作为配置缺口，把规则未知作为独立策略，才能补证后局部替换。

### 5.1 状态

| 状态 | 建议字段 | 清理／更新边界 |
|---|---|---|
| 配置来源 | `setLevel, region, build, profileID, evidenceTier` | 开局确定；同场不得混入 Boss 规则或其他装备变体 |
| 光能 | `lightCurrent, lightCapacity` | 与生命分开；承伤转换函数返回实际吸收和生命溢出 |
| 连击 | `comboCount, comboExpiryAt, comboRevision` | 成功事件更新；超时与受击是不同原因；L6 只明确排除了“受击清零” |
| 招式冷却 | `cooldownUntil[shard,typhoon,splitter,bones,heavenfall]` | 每种招式独立保存，是否共享由策略决定；不把天坠直接归入四招零 CD |
| 限时增益 | `typhoonUntil, rhythmUntil, tranceUntil` | 使用战斗模拟时间；不从屏幕动画播放次数判断 |
| 下招后两个窗口 | `bonesLandingUntil, bonesShardUntil` | 分开计时；落地事件与前岩命中分别消费或检查 |
| 瞬移 | `typhoonCycleID, teleportSpentInCycle` | 一次风周期的资格与普通 CD 分开，不因连续按键反复穿背 |
| 对手弱化 | `dreadUntil, dreadSourceID` | 目标侧持有；是否可刷新／叠加须配置 |
| 天坠过程 | `moveID, phase, phaseElapsed, sourceFacing, targetID` | `petrify → rise → charge → plunge → impact → recover`；中断／KO 统一退出 |
| 衍生命中去重 | `attackID, contactID, sourceKind, procDepth` | 区分斧身、多段、风刃、石刺、投矛；每个实际接触只结算一次 |

### 5.2 入口事件

```text
roundStart(config)
abilityRequest(relativeDirection, inputID)
rangedRequest(inputID)
confirmedContact(attackID, contactID, sourceKind, damageKind,
                 blocked, targetID, healthDamage, lightDamage)
damageIncoming(sourceKind, damageKind, amount, blocked)
throwAttempt(attackerID, throwKind)
landing(actorID, previousHeight, currentHeight, velocity)
phaseReached(moveID, phase)
timerTick(simulationDelta)
roundEnd(reason)
```

相对方向映射固定为 `forward→Shard`、`back→Typhoon / 合资格瞬移`、`up→Splitter`、`down→Bones`。天坠使用独立主动入口。把“后风”写成“上风”会改变输入机制。

### 5.3 Light 换算必须独立

```text
resolveLightAbsorption(incomingDamage, currentLight,
                       maxHealth, armorContext, sourceKind, modifiers)
    -> lightSpent, healthRemainder, absorptionEvents
```

目前只能确定先由 Light 承担防护，**不能写死 `lightSpent = incomingHPDamage`**。若原版按最大 HP 百分比、伤害前护甲、伤害后护甲或固定能量比例计账，这些实现会产生不同结果。尤其在 Light 剩余很少时，原版是把一次攻击的剩余部分溢出到生命，还是该次命中仍全部被挡，现有画面没有解决。该项是 `rule_unknown`，不只是缺一个比例。

L4 的 35% 是风中 Light 承伤修正，应放入该接口的对应阶段，不能直接减全部生命伤害。Trance 防御与 Dread 目标输出则应保持不同修正来源。

### 5.4 连击与风刃

连击计数与攻击动作数不同。必须保留“实际接触”“被格挡”“衍生风刃”“持续伤害”的来源；不能通过一次上挑生成 5 风刃，就在申请技能时预加 5 combo。风刃是否计 combo、是否回光及是否再触发风刃，须分别设策略。

对同一接触应去重；衍生攻击要有 `sourceKind=windBlade` 及 `procDepth`，防止普攻附风刃、风刃又被当作普攻无限递归。Typhoon、L3 门槛和 Trance 同时有效时，是合并一组风刃还是各自追加，仍是 `rule_unknown`，不能把三个条件简单写成三个无条件生成器。

L6 明确保留受击前 combo，但“持续时间更长”不等于跨回合、永久或永不衰减。未确认 L1—L5 的 Light 完全挡伤是否仍触发 combo 清零；这是测试重点。

### 5.5 四向冷却、长矛与瞬移

建议统一 `cooldownPolicy(moveID, level, combo, activeStates)`。需要区分：基础 CD、L4 减秒、L6 减秒、阈值后不进入 CD、天坠按倍数缩短，以及 Typhoon 的固定特例。尚未核实“达门槛瞬间是否清除已在进行的 CD”，因此应把 `clearExistingCooldownOnThreshold` 与 `nextCastCooldown` 分开。

长矛选择建议为 `rangedVariant = rhythm有效 || L5连击资格有效 ? pinToRock : normal`，但 Rhythm 是否被使用一次后消费仍需独立配置。先生成、飞行、命中，再执行钉岩与眩晕；挥空不能让目标无条件石化。按对手的受控状态取消移动，不可只画一块石头而不约束输入。

瞬移是风状态中第二次向后原初输入的强化行为。位移前后须重置前一帧碰撞轨迹、武器轨迹和朝向，否则跨屏线段会造成假命中。目标身后被边界挡住时的原版选点未核，项目应记录自身的回退策略。

### 5.6 Heavenfall 与 Trance

天坠至少要有石化、升柱、蓄能、下坠、着地伤害和收招阶段。将伤害绑定在实际的冲击阶段；Light 回补、L6 combo 和 Trance 的精确授予阶段目前均为 `null`，不能把“激活后”解释成已核的第 0 帧。

Trance 的完整事件链是：合资格天坠激活／执行 → 获得限时状态 → 攻速和防御修正 → 成功攻击进行额外 combo 概率判定 → 该攻击对应风刃 → 状态到期解除。这些回调要独立，不能靠一次大伤害近似整条链。概率应进入可重放的战斗随机源；不得每一渲染帧重新抽取概率。

倒地、KO、回合结束应取消未发射的派生招式、清理石化／悬空／瞬移资格和临时碰撞，避免下一回合残留。此项是本项目生命周期要求，并非声称已确认原游戏的内部清理实现。

## 6. 参数记录 JSON

下列是证据数据，不是可直接当作完整平衡配置加载的 JSON。`reportedLiveOverlay` 中是 2026-10-17 作者报告；`unverified` 中的 `null` 必须保持未知，若游戏运行需要临时值，应在另外的 project tuning profile 中提供。

```json
{
  "identity": {
    "setName": "Primordial Heavenly King",
    "weaponClass": "two_handed_axe",
    "weaponNameObserved": "Stormborn",
    "faction": null,
    "targetSetLevel": null,
    "upgradeLevelsCovered": [1, 2, 3, 4, 5, 6],
    "targetRegion": null,
    "targetBuild": null,
    "officialReleaseDate": null
  },
  "reportedLiveOverlay": {
    "source": "https://www.youtube.com/watch?v=1pblpwg6QJk",
    "uploadDate": "2026-10-17",
    "tier": "live_overlay",
    "genericPrimordialCooldownSeconds": 10,
    "typhoonDurationSeconds": 10,
    "l2HeavyWindComboThreshold": 15,
    "l4ShardStunSeconds": 2,
    "l4TyphoonLightDamageReductionFraction": 0.35,
    "l4SplitterWindBladeCount": 5,
    "l4DreadDurationSeconds": 10,
    "l4DreadDamageTakenIncreaseFraction": 0.50,
    "l4DreadDamageDealtReductionFraction": 0.50,
    "l4EarthNamedStateDurationSeconds": 9,
    "l4PrimordialCooldownReductionSeconds": 1
  },
  "betaOnly": {
    "source": "https://www.youtube.com/watch?v=ILQbJiTv52s&t=325s",
    "l6NoCooldownComboThreshold": 100,
    "eligibleForCurrentLiveParameters": false
  },
  "unverified": {
    "light": {
      "initial": null,
      "capacity": null,
      "gainOnSuccessfulAttackL1": null,
      "gainOnSuccessfulAttackL3": null,
      "gainOnPrimordialHitL2": null,
      "gainOnPrimordialHitL5": null,
      "gainOnBlockedAttackL5": null,
      "damageToLightConversion": null,
      "exhaustionSpilloverPolicy": null,
      "absorbedDamageKinds": null,
      "lightOnlyHitResetsComboBelowL6": null
    },
    "combo": {
      "damageIncreasePerPoint": null,
      "damageIncreaseCap": null,
      "expirySecondsBase": null,
      "expirySecondsL6": null,
      "blockedContactAddsCombo": null,
      "windBladeContactAddsCombo": null,
      "l3AllAttackWindThreshold": null,
      "l4AttackSpeedThreshold": null,
      "l4AttackSpeedIncrease": null,
      "l5RangedThreshold": null,
      "l6NoCooldownThreshold": null,
      "thresholdUsesPreHitOrPostHitCount": null
    },
    "cooldown": {
      "perMoveVerifiedSeconds": {
        "shard": null,
        "typhoon": null,
        "splitter": null,
        "bones": null,
        "heavenfall": null
      },
      "sharedOrIndependent": null,
      "startsAtPhase": null,
      "l6PrimordialReductionSeconds": null,
      "l6HeavenfallDivisorAtThreshold": null,
      "typhoonFixedCooldownPrecedence": null,
      "clearExistingCooldownOnThreshold": null
    },
    "moves": {
      "lightCostOrOtherAdmissionRule": null,
      "shardDamageCoefficient": null,
      "l4ShardDamageBonus": null,
      "typhoonDamageBonus": null,
      "windBladeDamageCoefficient": null,
      "splitterWeaponDamageCoefficient": null,
      "splitterSuspensionSeconds": null,
      "l4SplitterDamageBonus": null,
      "l4SplitterWindBladeIntervalSeconds": null,
      "bonesShadowDamageCoefficient": null,
      "l4BonesLandingWindowSeconds": null,
      "l4BonesShardWindowSeconds": null,
      "l4BonesShardUnarmedDamageCoefficient": null,
      "l4TeleportCooldownCycleResetRule": null,
      "dreadRefreshOrStackPolicy": null,
      "windProcOverlapPolicy": null
    },
    "ranged": {
      "rhythmDurationSeconds": null,
      "rhythmConsumedOnUse": null,
      "maxCharges": null,
      "rechargeSeconds": null,
      "l5RechargeMultiplier": null,
      "pinStunSeconds": null,
      "pinShadowDamageCoefficient": null
    },
    "heavenfall": {
      "petrifySeconds": null,
      "lightGainL2": null,
      "lightGainL6": null,
      "shadowDamageL2": null,
      "shadowDamageL6": null,
      "comboGainL6": null,
      "lightGainPhase": null,
      "comboGainPhase": null,
      "interruptAndInvulnerabilityPolicy": null
    },
    "trance": {
      "startPhase": null,
      "durationSeconds": null,
      "attackSpeedIncrease": null,
      "defenseIncrease": null,
      "extraComboChancePerSuccessfulAttack": null,
      "extraComboPoints": null,
      "windBladeCountPerTrigger": null,
      "refreshPolicy": null
    }
  }
}
```

## 7. 具体缺证与下一轮验证点

| 缺口 | 属于哪类未知 | 需要的有效证据 |
|---|---|---|
| Light 用多少能量吸收一击 | 规则与参数均未知 | 同版、同装备、同伤害来源，逐击记录生命／光能，包含光能恰好耗尽与溢出情形 |
| L1—L5 清 combo | 规则未知 | 分别检查直接扣 HP、仅扣 Light、格挡、DOT、被控制、静置超时 |
| L6 正式 100 门槛 | 数值未核，临界时点也未核 | 当前正式 6 级数字面板；99／100／101 的可复现 HUD 与 CD 对照 |
| Typhoon 固定 CD 优先级 | 规则未知 | 同一输入分别测 L2／4／6，门槛前后、风中瞬移前后及已在 CD 时跨阈值 |
| Ancient Hunt 消费／充能 | 规则与参数未知 | 原初命中／挥空／格挡后连续按远程，显示状态是否消失以及矛充能 |
| Heavenfall 各阶段授益 | 时点与参数未知 | 连续原速录像含能量、combo、Trance 图标；分别测试被打断、目标免控／已倒地 |
| L4 Earth 两个窗口 | 字段对应关系未知 | 下招后分别延时跳落和扔岩，不要只看到“9 秒”就给两个行为同一个计时器 |
| 风刃与 combo／能量递归 | 规则未知 | 隔离普通斧、Typhoon、L3 门槛、Trance 三种来源，记录每一个接触；不要由最终大伤害反推 |
| 原始动作与碰撞 | 动作源映射未核 | 匹配该正式斧变体的动作 ID、时间轴、武器轨迹及接触；旧双手斧动作不能仅凭类别被当作完全一致 |

可以用项目调试配置让全链路运行，但应把“机制入口均已接通”“测试通过”和“原版参数完全核实”分别陈述。后两者不能从第一项自动推出。

## 8. 本地证据索引与提取限制

本轮使用原作者公开 YouTube 页的播放器 JSON 与其公开 storyboard；未把第三方视频、配乐或截图纳入项目分发。下面路径仅是工作区核对缓存，不应提交到仓库。

| 本地文件（均位于工作区 `references/`） | 内容 |
|---|---|
| `1pblpwg6QJk-player.json` | A1 原始标题、发布时刻、时长和 storyboard 规格 |
| `1pblpwg6QJk-sb-0.jpg` 至 `-sb-13.jpg` | A1 10 秒采样，400×180 一格，3×3；第 i 张第 j 格对应约 `90*i + 10*j` 秒 |
| `pangu-live-stormborn-10m10s.png` | A1 武器 UI；从原始格裁切放大，未生成新细节 |
| `pangu-live-l4-rock-stun-07m30s.png` | A1 作者字幕：L4 前岩 2 秒眩晕 |
| `pangu-live-l4-teleport-07m40s.png` | A1 作者字幕：后招可立即再用；后续实机展示瞬移 |
| `pangu-live-l4-light-shield-08m00s.png` | A1 作者字幕：Light 承伤减少 35% |
| `pangu-live-l4-splitter-08m10s.png` | A1 作者字幕：5 风刃、10 秒 Dread |
| `pangu-live-l4-dread-08m20s.png` | A1 作者字幕：目标承伤与输出的 50% 修正 |
| `pangu-live-l4-earth-08m40s.png` | A1 作者字幕：Earth 9 秒，未解决两个窗口对应 |
| `pangu-live-l4-cooldown-09m10s.png` | A1 作者字幕：原初 CD 减 1 秒 |
| `f0sL5YrGMjM-player.json`、`-sb-0.jpg` 至 `-sb-7.jpg` | R1 5 秒采样，每格 320×180；升级片段的原始 UI 数字分辨率不足 |
| `pangu-rk-live-panel-00m25s.png`、`pangu-rk-live-panel-00m40s.png` | R1 原始升级 UI 裁切放大；不能依据模糊轮廓猜数值 |
| `t9NO5ZS4330-player.json` 与对应 `-sb-48.jpg`、`-sb-49.jpg`、`-sb-50.jpg` | T1 约 1:12—1:16 的装备及盘古实机 |
| `1D-xW-2zJqg-player.json` 与 `-sb-0.jpg`、`-sb-1.jpg`、`-sb-2.jpg` | V1 配装、超过 100 combo 的训练和天坠表现 |

以上时间是播放器 storyboard 的采样定位，不是逐帧识别出来的技能起手帧。裁切放大不能提高原始文字的信息量。

为读清 R1 数字而申请的 20—58 秒、720p 公共视频片段下载被自动审批拒绝，理由是下载体量风险与本任务“不下载大资源”的约束冲突。本轮已停止该下载路线，未用替代客户端、代理或绕过方式重试。正式 5／6 级清晰数字面板因此仍是待补证项；不会将模糊截图或 beta 占位符改写为正式数据。
