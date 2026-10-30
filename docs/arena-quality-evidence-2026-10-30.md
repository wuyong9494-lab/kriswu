# 品质研究证据台账：2026-10-30 第三轮

研究日期为北京时间 2026-10-30。本轮承接 09:03 的研究提交 `1bf10a68e0a43caf47abe99302875e5e4ba38504`，应用源码仍固定于 `5b298adf9e4a4adb3e2755daf2491f87b14ff93a`。两者的 Git 差异只有六份研究文档；本轮没有把 main 当作游戏最新版本。当前安装包 Build 未确认。

本轮新增内容是制作规格，不是成品、游戏测试报告或美术达标证明。所有数值分成：**现有数据**、**参考观察**、**建议起始值**、**验收目标**。后两者不冒充原版内部参数。

## 1. 证据等级与参考版本

| 标记 | 含义 | 可以支撑什么 | 不能支撑什么 |
|---|---|---|---|
| V | 本轮实际查看视频画面，记播放器时间 | 构图、形状、可见状态、局部遮挡 | 私有实现、触控延迟、完整菜单、真机 GPU 耗时 |
| F | 本轮读取源码、资产字节或现有渲染 | 本项目的结构、实现条件、文件统计 | 当前安装运行效果、主观审美通过 |
| T | 官方或制作方文字 | 公布规则、制作分工、适用许可说明 | 实际看过相应视频、全部版本都适用 |
| H | 继承前轮记录 | 找到线索、明确待验证对象 | 本轮已经重新观看或测量 |
| D | 本轮原创设计建议 | 指导制作和实验 | 已实现、平衡、好玩或性能达标 |

参考分轨：国服 EVA 历史大厅仅保留为用户目标线索；本轮可观看的国际服 2026 年 5 月玩家录像用于形状、层级和战斗可读性研究。它们**不是同一版本**。不把当前国际服的妙具规则、商店结构、活动变身应用到历史国服。录像发布日期也不是精确客户端版本。

## 2. 本轮实际查看的录像

### V01：Crow 玩家实录

- [MGN Gaming / Crow: Prestige 2](https://odysee.com/@MGNbutGaming:3/brawl-stars-crow-prestige-2-(gameplay:9)，页面发布日期 2026-05-27，播放器总长 17:03。
- 使用公开浏览器播放器，静音，按暂停和跳转抽样；不是完整观看，也没有试听音轨。浏览器约 1348×926 的视口，视频呈现在约 890 像素宽的区域。网页顶部在部分截图遮住画面边缘，因此不从这些截图算精确屏占比。

| 视频时间 | 直接观察 | 设计推论（不是原版实现事实） |
|---|---|---|
| 00:00 | 橙黄鸟头、深色躯干、交叉手臂形成清楚主形；角色居中；装备位在人物上方；两侧短标签入口；模式卡与黄色 PLAY 相邻 | 角色辨识应由外轮廓、明暗块和姿态共同承担；主操作与模式选择应相邻 |
| 约 00:06 | 模式/活动页采用整页主题、中心模式卡、底部分组标签；观察到 Starr Nova 和 Trophy Rush 的活动内容 | 主题构图可与菜单共用美术语言，但不能将此活动页面当作全部常规菜单 |
| 01:19.94（暂停） | 浅色赛场、圆柱及三角形障碍；角色附近生命/弹药与脚下阵营环并存；右下技能按钮不占据中心交战区 | 地面降低纹理噪声，让角色与弹道优先；脚底和头顶信息承担不同语义 |
| 约 02:03（播放中抽样，时间误差约 ±2 秒） | 多个角色、伤害数字、紫色区域和轨迹重叠；左侧局部角色确实被效果与数字遮住 | 原版也不是零遮挡；应控制关键边界与角色身份可读性，不能承诺任何混战都毫无遮挡 |
| 02:18.78（暂停） | 球门前角色、接地环、网面、弹药条与技能冷却数字可同时出现 | 目标区装饰需要检查透视遮挡；冷却信息不能只靠颜色 |

该段包含活动内容，不能据此量普通角色数值、标准地图尺寸或当前常规模式规则。

### V02：Fang 玩家实录

- [MGN Gaming / Fang: Prestige 2 #1](https://odysee.com/@MGNbutGaming:3/brawl-stars-fang-prestige-2-1-(gameplay:5)，页面发布日期 2026-05-22，总长 15:25。
- 本轮实际看过两个暂停位置，静音；没有宣称完整分析连招。

| 视频时间 | 直接观察 | 制作应用 |
|---|---|---|
| 00:00 | 翅膀横向展开、白色头部/面部、橙红翼膜、深色边框，和 Crow 轮廓明显不同；脚下有柔和投影；背景为蓝色城市/月亮；底部 BRAWL BALL / Super Beach 与 PLAY 相邻 | 角色族群要有不同主轴和负空间；大厅要按动作最大包围盒取景，不能只按静止身高缩放 |
| 00:42.09；比赛钟 2:04 | 绿色地面、较亮的草、暖色木箱/木栅栏/桶，以及另一种灰蓝障碍；墙顶/侧面可分；人物脚下敌我标记、生命值和命中数字可辨 | 地形材质类型应稳定、装饰不能冒充碰撞；伤害大字只在短时出现；近战武器/翅膀在俯视下也需留出主体 |

### V03：制作方动画样例

- 来源：[Modma 的 Brawl Stars 制作案例](https://www.modmastudios.com/casestudybrawlstars)，该页公开嵌入的 [4.949 秒 MP4](https://framerusercontent.com/assets/dsMm7LmhcE4FyCXCeSqpMlVYYhs.mp4)。文件为 1920×1080、30 fps 视频轨；这些是编码参数，**不是游戏帧率**。
- 本轮下载公开片段并查看 00:00.0、00:00.5、00:01.0、00:01.5、00:02.0、00:02.5、00:03.0、00:03.5、00:04.0、00:04.5 的静帧序列。
- 00:00–00:01：悬空/舒展与落下后的身体压低；01.5–02.5：身体收拢、翻转及再次展开；03.0–04.5：进入稳定展示姿态。绿色头部大形、橙色手部、深色躯干和牙齿形状贯穿动作。上述描述仅针对采样帧，不声称精确接触帧、加速度或所有中间姿态。
- 这是制作方展示，具体皮肤和录制客户端未标定，不等于实战视口。可研究姿态对比、重心和形状保持，不能拿它推导游戏内骨数/面数。

### 未观看及访问边界

| 来源 | 本轮真实状态 | 后续 |
|---|---|---|
| 用户给的 09:03 ChatGPT 回复链接 | 网页检索不能读取；已用仓库 01:03:03Z 的对应提交核对 | 以仓库实际文档为续接依据 |
| [EVA 实录 BV1oPYszaEJo](https://www.bilibili.com/video/BV1oPYszaEJo/) | 页面可取标题/发布时间/227 秒元数据，没有完成播放 | 不提供虚构时间点；EVA 逐页与逐帧仍阻塞 |
| [Modma YouTube 展示](https://www.youtube.com/watch?v=XOZjfXJhZZs) | 找到制作方说明；页面抓取被限流，未观看此长片 | 已用其官网可访问短片完成独立的姿态研究 |
| 原始用户照片与历史项目截图 | 沿用前轮 H 记录；本轮 Library 读取仅返回图片指针/文本，没有再次取得可见像素 | 不将自动图片说明当视觉结论；不把旧图冒充当前 Build |

公开媒体只用于研究。本轮不把下载的视频或第三方角色图打包进应用，也不提交整段录像至仓库。精确客户端版本、设备条件和完整原版菜单依然未知。

## 3. 关键文字来源（均于 2026-10-30 查阅）

| ID | 来源与适用性 | 本轮使用的有限事实 |
|---|---|---|
| T01 | [Modma 制作案例](https://www.modmastudios.com/casestudybrawlstars)；合作方自述 | 工作包含角色美术、动画、技术美术、实现与游戏内 QA；据此安排制作岗位，不反推成本 |
| T02 | [HUUDA Kenji cinematic](https://huuda.studio/portfolio/kenji-cinematic/) | 明确是营销动画，含模型、绑定、灯光、后期；不作为实战资源预算 |
| T03 | [Apple 游戏图形性能](https://developer.apple.com/documentation/metal/improving-your-games-graphics-performance-and-settings) | CPU/GPU 时间线、资源加载与呈现节奏分别检查；60 fps 对应约 16.67 ms 的帧间隔 |
| T04 | [Apple Metal 性能分析](https://developer.apple.com/documentation/xcode/analyzing-the-performance-of-your-metal-app) | Instruments 的显示、GPU、热状态等轨道可用于定位；透明片元、分辨率、资源等待和几何都可能成为瓶颈 |
| T05 | [Apple 触摸区域](https://developer.apple.com/design/tips/) | 控件触摸区域至少 44×44 pt；不是说所有视觉图标必须画成 44pt |
| T06 | [官方 Map Maker 说明](https://support.supercell.com/brawl-stars/en/articles/about-map-maker.html)；正文来自官方搜索索引，直接页未返回可读正文 | 模式、主题、地形放置是分别选择的设计维度；不作为地图公平证明 |
| T07 | [2023 Mystery at the Hub 维护说明](https://supercell.com/en/games/brawlstars/blog/release-notes/mysteryatthehub-patch-notes/) | 历史地图调整强调布局差异与接敌节奏；同页历史 R-T 的标记/分体与 Willow 的控制用于机制结构案例，不当作 2026 数值 |
| T08 | [2026-04-01 商店调整公告](https://supercell.com/en/games/brawlstars/blog/news/changes-to-bling-shop-and-cosmetics/) | 该文宣布商店/目录方案会调整；提醒菜单必须锁定版本，不能拼接不同年代截图 |
| T09 | [官方皮肤说明](https://support.supercell.com/brawl-stars/en/articles/skins-7.html)；官方索引正文 | 皮肤可能含独立表现，但不应改变战斗能力；表现设计与机制数值分开 |
| T10 | [KayKit Adventurers 原作者页](https://kaylousberg.itch.io/kaykit-adventurers) / [Skeletons 原作者页](https://kaylousberg.itch.io/kaykit-skeletons) | 免费包声明 CC0；源文件及额外内容有单独分档。没有购买，也没有声称现有文件逐字节等同今日下载包 |
| T11 | [Game-icons 授权说明](https://game-icons.net/about.html) / [FAQ](https://game-icons.net/faq.html) | 按具体作者保留署名；项目已有逐图标来源表，仍要核对修改声明 |
| T12 | [Supercell Fan Content Policy](https://supercell.com/en/fan-content-policy/)；页面标注 2023-09-27 更新 | 该政策不是把其角色资产放入另一款游戏的通用许可；本项目采用原创或可核验授权路径 |
| T13 | [GitHub 跳过工作流](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/skip-workflow-runs) | 本次纯文档提交使用 `[skip ci]`，避免仓库 push 流程自动启动应用构建 |

## 4. 本轮增量源码发现

固定代码链接均可从 [应用基线](https://github.com/wuyong9494-lab/kriswu/tree/5b298adf9e4a4adb3e2755daf2491f87b14ff93a) 进入。

| ID | 位置 | 实际事实 | 制作影响 |
|---|---|---|---|
| F01 | `GLTFModel.swift:118–142` | 导入设置 Lambert，读取基础色贴图/颜色和 emissiveFactor；此路径未读取法线、金属粗糙贴图 | PBR 素材不能默认原样还原；首样板先用形体和基础色表达材质 |
| F02 | `GLTFModel.swift:254–278` | 动画路径只接 translation/rotation/scale；CUBICSPLINE 只取中间值，按线性处理 | 表情 morph 权重动画不是现成能力；烘焙 LINEAR，骨骼表情先做兼容验证 |
| F03 | `ArenaAvatar.swift:209–216` | authored 游侠的材质切为 constant，再应用 grade | 增加实时灯光不能直接保证原创游侠获得预期 Lambert 体积；须对实际 shader 输出评审 |
| F04 | `ArenaModels.swift:240–242` | 角色导入 maxTexture=1024，道具=512；游侠保留自身法线 | 不能误把 GLTFModel 默认参数 512 当所有角色最终上限；2K 贴图不会自动以 2K 使用 |
| F05 | `ArenaWorld.swift:1320–1432` | 大招金色/强化紫色可覆盖阵营弹色；光晕为加法混合、不写深度；默认弩箭/飞刀等用胶囊体及亮芯 | 存在敌我语义弱化和重叠过亮的设计风险；实际是否误读未做设备实验 |
| F06 | `ArenaModels.swift:83–177` | 骑士/剑圣、蛮王/酒桶、法师/书灵、刺客/飞镖手各共用模型 | 四组需要不同主轮廓与动作，而非再增加颜色倍率 |
| F07 | `ArenaLobby.swift:1514` 与 `ArenaMenuComponents.swift:4–53` | 同时存在大描边游戏框和另一套紫色平面卡片规范 | 统一设计 token 和层级，而不是判断“全是系统表单” |

现有 GLB 全部重新解析，原始网格总三角形数包含后来被隐藏的附件，不等于每帧提交量；primitive 数也不是总 draw call。结果见 [资产结构数据](arena-quality-asset-metrics.json)。源码已限制加载的动作集合，文件内动作数不代表每个角色会把所有动作都加载或播放。

## 5. 本轮研究的边界与续接

已补：本轮实际观看的两个玩家视频抽样、一个制作方短片采样；模型加载能力；全部现有 GLB 结构；角色/技能/地图/菜单制作合同；资源与验收路径。

仍须补：国服目标版连续菜单和动作实录、当前安装 Build 对应画面、原版输入/动画事件帧、原版内部资产规格、专业音频试听、iPhone 17 Pro Max 与双机实测。这些不能由进一步写文字替代。

不因某个视频打不开停止其它工作；也不为增加篇数反复搜索相同资料。继续点按 [总清单](arena-research-index.md) 的 Q01–Q08 与阻塞表执行。
