# 已核验的第三方游戏素材库

2026-10-30：实际导入 11 个官方免费素材包，6,675 个原始文件、85,364,328 字节（81.4 MiB），另有 10 个 PCM WAV 适配候选（262,394 字节）。文件数包含重复格式、颜色版本、预览和许可证，不等于 6,675 件独立道具。这个清单不是全网穷尽清单。

GitHub 中保存 11 个原始 ZIP（`archives/`）、逐文件索引、独立许可证和 10 个已适配 WAV；当前工作目录也已展开全部 6,675 个源文件。源目录由 ZIP 可离线重建，不在 Git 中重复储存二进制。

其中 `kenney-particle-pack.zip` 为适应上传大小限制，按原始字节保存为 `.part001` / `.part002`。导入脚本自动拼接并校验原 ZIP 的 SHA-256；内容没有重新压缩或删减，缺片或损坏会中止导入。

所有素材来自作者官方 GitHub 或 Kenney 官方下载入口，包内许可证明确为 CC0-1.0。允许修改、个人及商业使用，不强制署名；仍保留作者和原始许可。作者品牌预览/标识仅作出处记录，不作为本项目品牌。没有下载付费 EXTRA/SOURCE、原版游戏提取素材或许可不明的转载包。

11 个包均已有实际游戏调用。`scripts/assets/integrate_vendor_assets.py` 从完整来源库生成 `App/ArenaVendor` 中的 28 个运行文件，覆盖蛮王武器、场景货物与自然装饰、按钮/图标、粒子、菜单/战斗/脚步声音及结算短音乐。运行选择约 0.88 MiB；源包、重复制作格式和完整索引保留在 `art/vendor`，不在每次战斗中加载。`prepared/audio` 保存早期转换候选；当前采用文件以 `App/ArenaVendor/arena-vendor-runtime.json` 为准。原项目已有 KayKit 衍生模型与 game-icons.net 图标的许可仍分别保留，后者不是 CC0。

|素材包 / 官方来源|固定版本|实际文件|体积 MiB|当前用途|
|---|---|---:|---:|---|
|[KayKit Adventurers](https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0)|1.0 / `672074b`|72|17.88|角色、武器、已有动作的源文件；不增加可玩英雄|
|[KayKit Dungeon Remastered](https://github.com/KayKit-Game-Assets/KayKit-Dungeon-Remastered-1.0)|1.0 / `b0ca9bd`|622|16.23|墙、地板、木箱、桶、旗帜的同风格候选|
|[Kenney UI Audio](https://kenney.nl/assets/ui-audio)|1.0|53|0.46|选择、返回、确认的音效候选|
|[Kenney Interface Sounds](https://kenney.nl/assets/interface-sounds)|1.0|101|0.92|菜单反馈音效候选|
|[Kenney Impact Sounds](https://kenney.nl/assets/impact-sounds)|1.0|131|0.99|命中、脚步、碰撞音效候选|
|[Kenney RPG Audio](https://kenney.nl/assets/rpg-audio)|1.0|53|1.00|武器、布料、道具声音候选|
|[Kenney Music Jingles](https://kenney.nl/assets/music-jingles)|1.0|87|1.37|结算短句候选；不是完整大厅/战斗循环配乐|
|[Kenney UI Pack](https://kenney.nl/assets/ui-pack)|2.0|1313|1.35|按钮、面板、滑杆、拉丁字体；不替换中文字体|
|[Kenney Game Icons](https://kenney.nl/assets/game-icons)|1.0|434|3.88|通用菜单/控制图标候选；与 game-icons.net 许可不同|
|[Kenney Particle Pack](https://kenney.nl/assets/particle-pack)|1.1|194|9.25|透明火焰、烟、光点与命中特效纹理|
|[Kenney Nature Kit](https://kenney.nl/assets/nature-kit)|2.1|3615|28.08|草、灌木、石块、树和围栏候选|

## 已完成的最小验证

- 6,675 个源文件与逐文件 SHA-256 清单一致；6,001 个不同内容哈希。原 ZIP 的 SHA-256、下载来源、版本及排除项也记录在清单。
- 3,142 张 PNG 已完整解码；436 个 SVG 已解析并检查无脚本或外部引用。
- 564 个 GLB/glTF 的缓冲区、访问器、索引、依赖文件和动作时间检查通过；没有命中现有 `gltf_contract` 不支持的特性。不是完整 Khronos 标准认证，也不是 SceneKit 实际画面验收。
- 426 个 OGG 全量软件解码通过。额外导出选择、返回、确认、点击、草地脚步、石地脚步、身体命中、木材命中、切割和斩击共 10 个单声道 44.1 kHz / 16-bit PCM WAV；记录转换参数、源/输出哈希和峰值，未替换原音轨。
- KayKit 角色源包包含 5 个模型文件（4 个基础角色，Rogue_Hooded 是 Rogue 的变体），每个 76 段动作；不能把变体当作新增独立英雄。当前玩法仍为游侠、蛮王、法师三人。
- FBX、DAE、OBJ/MTL、STL、AI、TTF、图集 XML 只完成内容哈希核验，没有安装或运行相应编辑器。TTF 为拉丁字体，不替换中文字体。
- 从展开目录排除 15 个网站快捷方式和 1 个 Unity 专用重复打包文件（原始 ZIP 不改写）；粒子 PNG 原文件已导入。未运行第三方脚本、插件、安装程序。

## 接入判定

|类别|判定|当前工程成本与未验证项|
|---|---|---|
|PNG 粒子、UI/图标|可以复用的源资产|低：按实际效果挑选、控制尺寸与透明叠层；不能把整套不同风格 UI 覆盖现有布局。仍须运行截图和遮挡验收。|
|Kenney 音效/短句|可以复用的源资产|低至中：OGG 转 PCM/AAC，沿用现有混音器、音量和暂停状态。早期 10 个 WAV 候选已保留，当前运行转换见 App 清单；已接入共享 PCM 混音器；试听、在机播放和混音验收仍待完成。短句不能冒充完整循环配乐。|
|KayKit / Kenney glTF 场景和角色|可以复用的源资产|中：既有导入器格式检查通过；仍需脚底原点、缩放、挂点、材质、实际 SceneKit 截图和碰撞核验。优先选墙/桶/草相关，不扩地图数量。|
|SVG、其他 3D 格式、源设计文件|可保留制作源文件|需要离线转换/编辑工具；未直接接入 iOS。许可明确不等于格式原生支持。|
|原作提取资产、无明确许可源码或付费版本|不采用|未下载导入。旧客户端/查看工具的调查见复用评估，不把工具许可证当素材授权。|

现有 Barbarian/Mage 模型与动作保留；蛮王使用源包的独立双手斧，沿用原手部挂点及变换，隐藏旧内置斧防止叠加。模型及原始上游文件的差异仍保留在审计记录中。

## 文件和复现

- `sources.json`：11 个来源、版本、原 ZIP 校验值、用途。
- `manifest.json`：每一个源文件的原相对路径、大小、SHA-256、许可证及排除原因。
- `archives/`：11 个官方原始 ZIP。没有把作者资源改名当原创。
- 各包目录：在当前工作区已展开的实际源文件；新检出运行导入脚本即可离线展开。
- `licenses/`：每个包未改写的作者许可证；ZIP 内也有原件。
- `prepared/audio/manifest.json`：10 个音频转换的可审计记录。
- `../../docs/evidence/vendor-asset-audit.json`：本次全量离线检查结果。

```sh
python3 scripts/assets/import_vendor_assets.py art/vendor/archives
python3 scripts/assets/audit_vendor_assets.py
python3 scripts/assets/prepare_vendor_audio.py
```

导入脚本不下载或执行任何包内代码；从官方入口重新下载时先比对 `sources.json` 的 ZIP 哈希。官网新版本可能改变字节，校验不符需要更新来源记录，不能静默接受。检查脚本依赖当前已有的 Python/Pillow 和 ffmpeg。

此批没有新增 iOS 运行时依赖。离线解码通过不等于视觉/听觉达标，模拟器通过也不等于 iPhone 17 Pro Max 真机稳定 60 帧。
