# 《裂隙对决》四角色缺失项独立补全与验收总报告（2026-11-23）

- **开发分支**：`codex/all4-heroes-complete-20261123`（基于 Phase 1 `f124875` 独立拉出）
- **上游只读体检基线**：`codex/all4-heroes-readonly-asset-audit-20261123`（`01872f0`）
- **安全边界验证**：
  - 未改动 `main`（`4bb2ff9`）、`codex/duel-original-minimal-20261120`（`7b9e04f`）、`codex/shogun-heavy-phase1-prototype`（`f124875`）、值班功能、TestFlight。
  - 未向 Git 提交任何 `.rar` / `.bin` / `.glb` / `.mp4` / `.wav` / `.mov` 原始或渲染二进制素材（全部存放在仓外 `/home/antigravity/all4_heroes_work/`）。
  - 未破解任何加密 Base64 XML（`bones`/`config`）。

---

## 一、四角色来源诚实标注原则（Provenance Policy）

所有 3D 模型、骨骼轨迹、动画剪辑、特效着色器、音效与战斗参数均按四档严格标注来源，绝不将独立补全项冒充为原版导出品：

| 来源标签 | 含义 |
| --- | --- |
| `originalBinaryMeasured` | 直接从本地四个 `.rar` 未加密 Bundle 中提取并实测（模型网格、1K PBR 贴图、二进制骨骼动作帧、原版 WAV 音效）。 |
| `liveMobileReferenceObserved` | 来自用户实机手机录屏 `11-22-26-10-13-16.mov` 的 EV3 无充能普通重斩格挡实测观测（不破防、蓝盾、受击滑退）。 |
| `independentRecreation` | 针对外部缺失 CAB（共 `474` 条核心未解析 PPtr）、缺失通用/防御动作（如孙悟空 `0 b_*` 格挡）、以及无可控真机视频时的战斗平衡参数，由工程逻辑与 Blender 独立建模/合成/编写实现。 |
| `unconfirmed` | 尚待后续可选同版本基础武器实机录像复核的局部数值（如幕府将军普通重斩非暴击伤害与精确逻辑顿帧）。 |

---

## 二、四角色补全总览（原版保留 vs 独立补全）

| 角色 | 源码模块 | 单元测试 | 原版已实测保留（`originalBinaryMeasured`） | 本次独立补全项（`independentRecreation`） | 阻断缺口 |
| --- | --- | --- | --- | --- | :---: |
| **1. 吴庸 / 幕府将军**<br>(`shogun.rar`, 38 `.bin`) | `DuelShogunHeavyPhase1.swift` | `DuelShogunHeavyPhase1Tests`<br>`DuelShogunTests` | 原版大铠+大太刀+1K PBR、`shogun_heavy`（66f/131t60, +1.919m 突进, t60 44…51 生效）、`b_shogun_middle_heavy`（41f/81t60, 1.279m 滑退）、原版 VFX 纹理（`vfx_tex_trail_slash_01`/`vfx_tex_noise_01`/`vfx_tex_ground_crack`）与重斩/格挡/空挥 WAV 音效 | **高精原头重建**：以 `WuYong_222_Revised.fbx` 的 `64,644` 顶点 `WuYong_UserPortrait`（等比 `0.94×` 零失真）+ 暖肤色 2K PBR 烘焙（消除惨白过曝）+ 领口内衬颈桥替换低模头；**AAA 烈焰居合特效**：三层烈焰镰月斩弧 + 紧贴刀刃火膜 + 76 道流光火星 + 熔岩裂地火口 + 光学辉光（补 74 条外部 CAB 缺口） | **0** |
| **2. 刘泉纬 / 君主**<br>(`emperor.rar`, 86 `.bin`) | `DuelEmperorPhase2.swift` | `DuelEmperorPhase2Tests` | **人形态**体/披风/拳套 + **暗影兽形态** `emperor_creature_body`（7737v）+ `creature_hands` + 1K PBR；`emperor_transition`（86f/171t60, 118 骨, 爆发峰值 t60 100…103）；`p_agl_heavy_punch`（51f, +2.212m）；`claws_spinning_slash_1`（46f, +1.052m）；`b_claws_low_block_heavy`（39f, 1.181m 滑退）；原版 VFX 噪波贴图与变身/嘶吼/利爪 WAV | `CleanHead_liuQuanwei.glb` 暖肤色校准与颈桥；**独立合成** `rec_emperor_human_idle`（60f 呼吸武术待机）、`rec_emperor_mid_block_heavy`（39f 站立双臂架格挡，复用原版 1.181m 滑退曲线）、王朝步法；**AAA 暗影裂变特效**：地面紫雷裂隙阵 + 双层暗影黑烟旋涡 + 8 道 3D 分叉紫电 + 52 枚虚空碎片 + 暗影兽三爪锋锐紫炎弧（补 150 条 CAB 缺口） | **0** |
| **3. 徐骁 / 军团之王**<br>(`legion_king.rar`, 72 `.bin`) | `DuelLegionKingPhase3.swift` | `DuelLegionKingPhase3Tests` | 11511v 重甲+3层披风+`wpn_King_C_Default_r` 1.26m 双手重剑（修复 Unity Z-up `Rx(-90°)` 精确锁手）+ 1K PBR；`twohanded_sword_heavy_slash`（64f/127t60, +0.972m）；`b_twohanded_sword_mid_block_heavy`（32f, 1.108m 滑退）；`shadow_ranged_chain`（69f）+ `shadow_ranged_chain_passive`（118f, 拉拽 `-1.066m`, 浮空 `Y=1.106m`）；`legion_king_ressurection`（121f）；原版幽冥噪波贴图与锁链/重剑/二命 WAV | `CleanHead_xuXiao.glb` 暖肤色校准与领口颈桥；**独立建模 28 节 3D 暗影锁链 + 4 刺幽冥镣铐**（补 `cab-4491db`/`cab-131b8f`/`cab-ddcfef` 缺失）；**AAA 幽冥符文链阵特效**：多层北欧/军团符文召唤法阵 + 双螺旋青蓝魂火丝带 + 4 道链身寒霜电弧 + 48 缕幽冥魂焰 + 重剑魂火斩波 + 脚底黑青亡灵雾（补 193 条 CAB 缺口） | **0** |
| **4. 孙登 / 孙悟空**<br>(`monkey_king.rar`, 82 `.bin`) | `DuelMonkeyKingPhase4.swift` | `DuelMonkeyKingPhase4Tests` | 8819v 盔甲+6骨伸缩金箍棒 `monkey_base_staff_r` + 5.01m 攀棍石柱 `monkey_base_pillar_r` + 4.32m 巨棒 `monkey_base_colomn_r` + 1K PBR；`staff_heavy_slash`（52f, +3.406m 跃击）；`monkey_king_climb_stance`（103f, **攀棍骨盆高度 `Y=2.123m`**）；`monkey_king_climb_forward_attack`（68f, 从 `Y=2.439m` 俯冲 `+2.729m`）；`monkey_king_climb_pillar_attack`（96f, `Y=3.482m`）；原版云雾/裂纹贴图与立柱/呼啸/地震 WAV | `CleanHead_sunDeng.glb` 换头与细领暖肤颈桥；**关键补全：独立合成双持长棍格挡 `rec_monkey_king_mid_block_heavy`**（36f/71t60, 1.150m 阻尼滑退，填补 `0 b_*` 缺口）；**AAA 筋斗祥云与六角灵盾特效**：双层暖金半透雕琢筋斗祥云 + 12 瓣金色莲花裂地法阵 + 绕棍双螺旋金光丝带 + 金焰俯冲波 + 弧面六角蜂窝透明能量灵盾与 32 道弹反火花（补 57 条 CAB 缺口） | **0** |

---

## 三、关键技术突破与视觉修复校准

1. **吴庸高精原头重建与四人自然肤色校准（彻底消除失真与惨白）**：
   - 排查确认旧版 `CleanHead_wuYong.glb` 源自移动端减面截头（人脸压扁失真、反照率泛灰白且在强棚灯下过曝）。现直接提取 `WuYong_222_Revised.fbx` 内 `64,644` 顶点、`4K` 贴图的无损独立头模 `WuYong_UserPortrait`，采用严格等比缩放（`0.94×`）与下颌以上 `100% head` 刚性蒙皮确保任意战斗姿态零变形；并将 2K 烘焙反照率中位肤色由过曝 `[227, 182, 160]` 校准为自然暖东亚 PBR 肤色，配合平衡棚灯与四人统一肤色标定，彻底消除脸部惨白。
2. **四角色 AAA 多层技能特效全面重构（淘汰简单单环圆环）**：
   - 结合 4 英雄本地原包实抽的 `103` 张原始 VFX 贴图与自建 `1K` 几何符文/莲花/六角蜂窝/裂隙法阵贴图，构建真·游戏加色透明 Shader（`AddShader(TransparentBSDF, Emission)` + `visible_shadow=False` + `transparent_max_bounces=24`）+ Cycles `FOG_GLOW` 选择性光学辉光 + 动态属性点光源 + 湿石板地面倒影，实现刀光斩弧、黑烟紫雷、符文魂链、雕琢祥云与六角蜂窝弹反护盾。
3. **军团之王双手剑 Z-up 轴向精准校准与 28 节 3D 锁链**：
   - 对 `wpn_King_C_Default_r` 统一左乘 `Rx(-90°)` 使握持误差 `< 0.1 mm`；以 28 节 90° 互锁锻铁环 + 4 刺幽冥镣铐配合双螺旋魂火与寒霜电弧补齐缺失的 3 个 3D 锁链 CAB。
4. **孙悟空 `0 b_*` 防御轨道合成与君主双形态闭环**：
   - 在 GLB 与 Swift 60 Hz 状态机中同步合成 `rec_monkey_king_mid_block_heavy`（36f/71t60, 1.15m 滑退），完整区分攀棍低段规避（`<=1.25m`）与高空防空打断（`>=1.75m`）；君主在 `t60=100` 锁定变身且严格限制仅命中/格挡触发吸血。

---

## 四、仓外资产与自动化测试验证清单

- **仓外导出成品 GLB（`/home/antigravity/all4_heroes_work/models/`）**：
  - `Hero1_WuYong_Shogun_Completed.glb`（`15.6 MB`，SHA256 `562d25bf...`，含 `64,644` 顶点 `WuYong_222_Revised` 无损高精原头 + 暖肤色 2K PBR）
  - `Hero2A_LiuQuanwei_EmperorHuman_Completed.glb`（`16.3 MB`，SHA256 `5ab29382...`）
  - `Hero2B_LiuQuanwei_ShadowBeast_Completed.glb`（`5.4 MB`，SHA256 `68006aab...`）
  - `Hero3_XuXiao_LegionKing_Chain_Completed.glb`（`39.1 MB`，SHA256 `c316f9ac...`，含 28 节独立建模 3D 暗影锁链 + 4 刺幽冥镣铐 + `Rx(-90°)` 校准重剑）
  - `Hero4_SunDeng_MonkeyKing_Completed.glb`（`12.1 MB`，SHA256 `8163542a...`，含金箍棒 + 攀棍石柱 + 独立合成 `rec_monkey_king_mid_block_heavy`）
- **仓外视觉验收媒介（`/home/antigravity/all4_heroes_work/media/`）**：
  - `all4_heroes_headswap_closeups.png`（4 角色高精换头与自然暖肤色特写核验）
  - `all4_heroes_completed_lineup_sheet.png`（4 角色升级版 AAA 技能特效 2×2 全景图）
  - `all4_heroes_mechanics_storyboard.png`（4×3 关键帧分镜图）
  - `all4_heroes_mechanics_showcase.mp4`（含 4 角色真实原版 WAV 音效 + 升级版 AAA 技能特效的 6.0s 1280×720 演示视频）
- **Swift 确定性 60 Hz 战斗测试验证（31/31 通过，0 失败，耗时 0.498s）**：
  - `DuelAll4HeroesGapFillTests`：**2/2 passed**
  - `DuelEmperorPhase2Tests`：**5/5 passed**
  - `DuelLegionKingPhase3Tests`：**5/5 passed**
  - `DuelMonkeyKingPhase4Tests`：**5/5 passed**
  - `DuelShogunHeavyPhase1Tests`：**6/6 passed**
  - `DuelShogunTests`：**8/8 passed**
  ```bash
  /home/antigravity/swift/usr/bin/swift test \
    --package-path /home/antigravity/wuyong9494-lab/all4-heroes-complete \
    --filter "DuelShogunHeavyPhase1Tests|DuelShogunTests|DuelEmperorPhase2Tests|DuelLegionKingPhase3Tests|DuelMonkeyKingPhase4Tests|DuelAll4HeroesGapFillTests"
  ```
- **后续可选精调说明**：由于未能获取同版本可控基础武器实机对战录屏，四角色部分独立补全的伤害/顿帧/格挡削血标量均显式标注 `independentRecreation` 或 `unconfirmed`，后续若在真机/Steam 同版本测得基准数值，只需直接微调各模块 `CombatParameters` 常量即可，无需重构模型、骨架或判定管线。
