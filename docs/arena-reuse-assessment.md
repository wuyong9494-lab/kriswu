# 复用核验与三英雄范围（2026-10-30）

接续 `codex/arena-quality-sample` 的 `04d6cc0`，保留 Swift / SwiftUI / SceneKit、既有模拟器和资产管线。用户最新指令将单游侠样板扩大到三个完整英雄与完整主流程；不扩地图，不发布、不合并、不购买。以下是读取真实目录、许可证和部分实现后的结论；未运行候选私服、APK、安装器或连接原版服务端。

## 先给结论

继续复用现有 KayKit CC0 角色/动作和自制游侠。没有找到可直接接管当前 iOS 项目的完整、许可明确的旧版原作客户端源码。不能把修改版 APK、网络协议客户端、服务端模拟器和有画面的客户端工程混称为“客户端源码”。不为凑复用而替换引擎或搬进旧协议。

## 候选与取舍

维护日期为本次 API 看到的最近 push；它不证明稳定性。具体快照及目录清单见 [核验清单](evidence/reuse-candidate-inventory.json)。

| 分类 / 仓库 | 维护、许可与要求 | 版本、平台及真实范围 | 对当前工程的价值、缺口和成本 |
|---|---|---|---|
| 可以复用：[KayKit Adventurers 1.0](https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0) | 2023-09-16；LICENSE.txt 明确 CC0 1.0，允许个人/商业使用，不强制署名；保留出处 | 通用 FBX/glTF 骨骼角色和动作，不依赖原作版本；资产包，非客户端 | 现有 Barbarian/Mage 已走现有导入器，复用成本低；仍需材质、比例、动作裁切和遮挡验收。仓内二进制与此 GitHub 快照哈希不同，精确导出版本/变更链未完全追溯，不宣称逐字节源文件匹配。 |
| 仅供参考：[SC Editor](https://github.com/danila-schelkov/sc-editor) | 2026-08-31；MIT，复制代码须保留版权及许可 | Java 17 / Maven / JOGL 桌面查看编辑器；读取 InspectCommand 确认导出名、形状、MovieClip 检查；没有明确原作客户端版本兼容矩阵 | 可研究合法持有的 SC 文件结构，不能生成我们的 SceneKit 完整角色。无获授权 SC 测试集；本轮没有编译/运行，额外 Java/OpenGL 依赖收益低。 |
| 仅供参考：[SupercellSWF-Animate](https://github.com/sc-workshop/SupercellSWF-Animate) | 2026-07-06；MIT，保留版权及许可 | package 1.4.0；Adobe Animate 插件，Windows 10/11 x64、macOS 15+；文档以 Animate 2022+ 为基准，1.4 降低安装门槛到 2019，但不保证功能。主要导出 2D SC；不支持声音、脚本/过滤器，部分文字和 3D 变换有限 | 适合自有 2D 内容的 SC 导出，不是 SwiftUI 菜单或 3D 客户端。当前不需要 SC 格式，缺 Animate 环境及合法 SC 验证资产；不安装，不采购。工具 MIT 不授权其示例中可能出现的游戏素材。 |
| 仅供参考，待离线验证：[glTF-Validator](https://github.com/KhronosGroup/glTF-Validator) | 2026-10-06；Apache-2.0；分发需保留许可证、适用声明，改动注明 | glTF 2.0 / GLBv2；Dart CLI 与 JS 包，通用离线资产检查工具 | 可补标准格式检查；当前没有已安装的可信包，尚未运行或接入。即使通过，也不能代替现有导入器特性门禁、画面验收或性能测量。无需改 iOS 引擎。 |
| 不适合采用：[GuitarBrawl](https://github.com/xmopser/GuitarBrawl) | 2025-01-26；GPL-3.0，分发受覆盖修改时须履行对应源码/许可义务；素材许可另核 | 旧版 v27.269 服务端，C# .NET 6 + MySQL；读取 csproj 验证。README 声称 3 模式 PvP、房间/好友/联盟，未实测；需要另取并修改 Android APK | 没有可移植的游戏客户端源码、美术渲染器或 iOS UI。旧协议/后端重构成本高；附带数据与改版 APK 来源许可不充分，完全不下载运行、不接正式服务。 |
| 不适合采用：[brawl-stars-copy](https://github.com/jinunpark/brawl-stars-copy) | 2026-08-29；递归目录与 API 未找到明确许可证，不按可复用处理 | Java 权威服务端 + Godot .NET 客户端原型；本地 2/4 人宝石玩法。仅 Linux x86-64 / WSL2；macOS/iOS 没有受支持完整流程 | 是实际客户端实现，但许可缺失，且替换现有 Swift 引擎成本高。只核结构，不复制代码、不 bootstrap。 |
| 不适合采用：[OrcaPlatforms/BrawlStar](https://github.com/OrcaPlatforms/BrawlStar) | 2026-02-21；MIT 文本存在，保留版权许可；不自动覆盖未核实第三方素材 | Unity WebGL 编译版；目录是 data/wasm/loader/framework、index、文档，没有 Unity C# 工程 | 能部署编译产物不等于能改造客户端源代码。无法逐项迁移角色/动画/UI，不把 WASM 当 iOS 源码。未运行。 |
| 不适合采用：[Minres/SCViewer](https://github.com/Minres/SCViewer) | 2026-08-17 push；EPL-1.0，受覆盖分发需遵守源码/声明条件 | Eclipse 插件、SystemC VCD/事务波形查看器 | 是真实同名项目，但与 Supercell 美术无关。截图提到的 Supercell “SCViewer”确切仓库仍未确认，不能冒认同一工具。 |

## 用户追问：直接拿旧版客户端代码更新

再次专项核验了以下带有 Client/Clone 名称的仓库。未找到完整可复用的旧版原作游戏客户端；这不是断言整个互联网不存在此类项目，只是本轮可核实的结果。若后续出现明确源码与许可，先隔离编译/功能验证再决定移植范围。

| 仓库 | 维护 / 许可 / 版本 | 实际检查与采用判断 |
|---|---|---|
| [PeterHackz/BrawlStars-Client](https://github.com/PeterHackz/BrawlStars-Client) | 2026-03-26 归档；MIT（保留版权许可）；README 提及 v58/v59 | 22 文件。Program.js 建立 TCP 连接，消息工厂只有握手/登录回应；没有场景、UI、角色渲染或战斗客户端。不适合本轮采用，不连接官方服务。 |
| [PeterHackz/BrawlStars-JavaClient](https://github.com/PeterHackz/BrawlStars-JavaClient) | 2026-03-26 归档；MIT；v46 | 13 文件，前者的 Java 协议实现；非完整游戏。没有需要移植的画面/动画流程，平台移植无收益。 |
| [superdudnikteam/BrawlStars-Client](https://github.com/superdudnikteam/BrawlStars-Client) | 2022-12-13 归档；MIT；README v47、描述 v46，版本说明冲突 | 18 文件 JS TCP/加密/消息，非渲染客户端。维护停止，协议版本未验证，不采用。 |
| [athemm/Classic-Client](https://github.com/athemm/Classic-Client) | 2021-02-13；MIT；游戏版本未明确 | 17 文件 Python 数据包命令工具；main.py 含改战绩/开箱等菜单，没有游戏渲染。无本轮价值；不运行、不使用这些服务端操作。 |
| [byTrident/brawl-stars-clone](https://github.com/byTrident/brawl-stars-clone) | 2024-01-29；MIT | 主分支只有 LICENSE 和 README 两个文件，没有客户端实现。不可复用。 |

## 隔离验证及现有工程接续

本轮未新增第三方运行时依赖。用当前只读 GLB 文件和既有 Python 解析/姿态采样器作最小验证：三套模型拥有不同文件/几何；各自待机、跑动、普攻、大招、受击、死亡、庆祝共 21 个动作均存在，采样姿态确实变化，未触发当前导入器的特性拒收。原始结果见 [资产审计](evidence/three-hero-asset-audit.json)。这证明可继续使用的技术基础，不证明动作美术完成，也不替代 iOS 实际加载。

修正旧素材说明的事实差异：Barbarian/Mage 文件仍各有 76 条动作，不是“文件只保留使用动作”；运行时只选需要的动作。精确上游二进制下载被当前连接器的文本限制拒绝，不能把失败说成哈希比对通过。

三英雄使用游侠（自制面部/持弩）、蛮王（CC0 不同模型、近战三斧与跃击）、法师（CC0 不同模型、越墙火球与陨石），不拿换色角色凑数。当前是沿用机制，不声称等同原作：远程压线可对照 Colt、近战越墙进场对照 El Primo、越墙爆发对照 Dynamike；普攻/大招具体规则保留现有效果，并在差异表中注明单发/连射、穿透/破墙等差异。官方历史说明只用于机制参考，不代表本轮取得对应版本连续录像或复用权。

仍缺：可确认版本的原作完整进入/大厅/三英雄详情/战斗/结算录像；三名对标英雄逐动作连续素材；三英雄统一美术质量验收；当前构建全流程录像与真机温度/GPU/帧时间。已恢复 IMG_3911、IMG_3912 两张带播放器覆盖的战斗参考静帧，不能用来证明动作时序。当前运行截图、媒体可解码、视觉达标与 iPhone 17 Pro Max 真机性能分开记录。


机制参考出处（阅读范围有限，不冒充原版连续录像）：[Apple 编辑的 Meet the Brawl Stars](https://apps.apple.com/us/story/id1446532399) 描述 Colt 连射/大招；[Supercell 历史 Summer Update](https://supercell.com/en/games/brawlstars/blog/game-updates/summer-update-2/) 涉及 Dynamike 大招与 El Primo；[2026 年 8 月官方更新](https://supercell.com/en/games/brawlstars/blog/release-notes/release-notes-august-2026/) 解释 El Primo 的近战坦克定位与跃击。只借鉴“远程压线、近身进场、隔墙爆发”的区分；我们现有三者不是逐招复刻，数值也不宣称等同这些不同版本。
