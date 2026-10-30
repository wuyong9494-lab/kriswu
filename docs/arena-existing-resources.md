# 已导入资源核对（2026-10-30）

按 `7604b56cfd38ef688607488bd705c0120a0f0ea9` 的实际文件、调用代码和 Git 历史核对。之前仅依据候选复用评估、将历史资产说成尚未下载/接入的结论不正确。本文用于恢复已有成果；不重复下载，不替换引擎，不把已有文件当成本轮新成果。

|资源|实际文件与历史|当前接入情况|
|---|---|---|
|KayKit Adventurers，CC0|App/Arena3D 中 Knight、Rogue、Rogue_Hooded、Barbarian、Mage 共5个 GLB；24b77ea 首次3D接入|ArenaModels.swift / BrawlerLook 映射并加载动作；当前三英雄样板使用 Barbarian/Mage 和自制游侠，其余资源保留。不是只有两个外部模型。|
|KayKit Skeletons，CC0|4个 Skeleton_*.glb，5件独立武器 glTF/bin、skeleton_texture.png；050d76c|BrawlerLook 的四个骷髅角色及 Weapon 挂点映射；仍保留在现有工程，不代表它们都出现在三英雄试玩入口。|
|KayKit Medieval Hexagon，CC0|6种树、3种岩石、2面旗帜 glTF/bin，hexagons_medieval.png；见 KayKit-LICENSE.txt|ArenaModels.props 与 ArenaWorld.scenery 实际引用，用于场外装饰与队伍旗帜；场景分支可选择不同装饰。|
|Game-icons，CC BY 3.0|art/lobby/icons 的11个 SVG，App/Assets.xcassets 内33张1x/2x/3x PNG；696ef76|原始清单含上游提交82d9488、作者与来源，build_lobby_icons.py 可重建，设置页有署名。后续 ArenaLobbyIcon 对多个图标改成 Canvas 绘制，默认分支仍读取图片；不能把33张图片都说成当前大厅同时显示。|
|原创游侠|Ranger_Original.glb、Ranger_FaceSample.glb、scripts/assets/build_ranger.py，5b1230f起|现有模型、面部样板、动作与挂点代码均保留，不是待重新制作的空项。|
|月夜大厅背景|App/Assets.xcassets/ArenaLobbyMoonCity.imageset/moon-city.jpg；art/lobby/moon-city-provenance.md|ArenaLobbyArt.swift 实际读取。来源为已记录的图像生成，不归入第三方下载包。|
|原创程序化音乐/音效|App/ArenaSounds，包含4个 arena_theme_*.m4a，e03e554等|ArenaSound 与 ArenaEffectMixer 已接入；主题音乐受设置控制。不是已下载的第三方音乐，也不等于已完成听感/真机验收。|

具体文件大小和当前 SHA256 见 [资产盘点](evidence/existing-asset-inventory-2026-10-30.json)。哈希是当前工程文件身份，不宣称与上游原包逐字节一致；部分模型经过项目内调整。

[候选复用评估](arena-reuse-assessment.md)描述 SC Editor、SupercellSWF-Animate、glTF-Validator 等候选，不能据此否认上表已导入资产。后续沿用这些资源与现有加载器完成三英雄真实流程、动作和画面验证，再按缺口补资源。
