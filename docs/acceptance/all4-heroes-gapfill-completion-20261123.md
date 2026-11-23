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
| **1. 吴庸 / 幕府将军**<br>(`shogun.rar`, 38 `.bin`) | `DuelShogunHeavyPhase1.swift` | `DuelShogunHeavyPhase1Tests`<br>`DuelShogunTests` | 原版大铠+大太刀+1K PBR、`shogun_heavy`（66f/131t60, +1.919m 突进, t60 44…51 生效）、`b_shogun_middle_heavy`（41f/81t60, 1.279m 滑退）、原版重斩/格挡/空挥 WAV 音效 | `CleanHead_wuYong.glb` 换头与衣领颈桥、重斩刀光/受击火花/空挥砸地尘/蓝盾波纹 Shader（补 74 条外部 CAB 缺口）、无充能普通重斩 4 场景逻辑状态机 | **0** |
| **2. 刘泉纬 / 君主**<br>(`emperor.rar`, 86 `.bin`) | `DuelEmperorPhase2.swift` | `DuelEmperorPhase2Tests` | **人形态**体/披风/拳套 + **暗影兽形态** `emperor_creature_body`（7737v）+ `creature_hands` + 1K PBR；`emperor_transition`（86f/171t60, 118 骨, 爆发峰值 t60 100…103）；`p_agl_heavy_punch`（51f, +2.212m）；`claws_spinning_slash_1`（46f, +1.052m）；`b_claws_low_block_heavy`（39f, 1.181m 滑退）；原版变身/嘶吼/利爪 WAV | `CleanHead_liuQuanwei.glb` 人形态换头与颈桥；**独立合成** `rec_emperor_human_idle`（60f 呼吸武术待机）、`rec_emperor_mid_block_heavy`（39f 站立双臂架格挡，复用原版 1.181m 滑退曲线）、王朝步法；紫黑变身爆炸光环与暗影兽边缘发光 Shader（补 150 条 CAB 缺口）；双形态状态锁定 + 暗影兽命中吸血（空挥/打断严格 0 回复） | **0** |
| **3. 徐骁 / 军团之王**<br>(`legion_king.rar`, 72 `.bin`) | `DuelLegionKingPhase3.swift` | `DuelLegionKingPhase3Tests` | 11511v 重甲+3层披风+`wpn_King_C_Default_r` 1.26m 双手重剑（修复 Unity Z-up `Rx(-90°)` 精确锁手）+ 1K PBR；`twohanded_sword_heavy_slash`（64f/127t60, +0.972m）；`b_twohanded_sword_mid_block_heavy`（32f, 1.108m 滑退）；`shadow_ranged_chain`（69f）+ `shadow_ranged_chain_passive`（118f, 拉拽 `-1.066m`, 浮空 `Y=1.106m`）；`legion_king_ressurection`（121f）；原版锁链/重剑/二命 WAV | `CleanHead_xuXiao.glb` 换头与领口颈桥；**独立建模 Procedural 3D 暗影锁链（`Procedural_KOTL_ShadowChain`：28 节交替 90° 互锁锻铁环 + 幽冥镣铐项圈 + 青紫 Fresnel 鬼火边缘 Shader，补 `cab-4491db`/`cab-131b8f`/`cab-ddcfef` 3D 锁链缺失）**；军团通用踢技/跳跃过渡；暗影化身**每回合严格单次触发**复活逻辑（补 193 条 CAB 缺口） | **0** |
| **4. 孙登 / 孙悟空**<br>(`monkey_king.rar`, 82 `.bin`) | `DuelMonkeyKingPhase4.swift` | `DuelMonkeyKingPhase4Tests` | 8819v 盔甲+6骨伸缩金箍棒 `monkey_base_staff_r` + 5.01m 攀棍石柱 `monkey_base_pillar_r` + 4.32m 巨棒 `monkey_base_colomn_r` + 1K PBR；`staff_heavy_slash`（52f, +3.406m 跃击）；`monkey_king_climb_stance`（103f, **攀棍骨盆高度 `Y=2.123m`**）；`monkey_king_climb_forward_attack`（68f, 从 `Y=2.439m` 俯冲 `+2.729m`）；`monkey_king_climb_pillar_attack`（96f, `Y=3.482m`）；原版立柱/呼啸/地震 WAV | `CleanHead_sunDeng.glb` 换头与颈桥；**关键补全：独立合成双持长棍格挡 `rec_monkey_king_mid_block_heavy`（36f/71t60, 1.150m 阻尼滑退，彻底填补原包 `0 b_*` 无防御轨道缺口）**；王朝步法/扫腿；金箍棒金色光效与攀棍底座波纹 + 蓝盾波纹（补 57 条 CAB 缺口）；攀棍高空规避低中段地面攻击（`h <= 1.25m` 零伤）+ 防空打断坠棍（`h >= 1.75m` 取消俯冲） | **0** |

---

## 三、关键技术突破与防错校准

1. **军团之王双手剑 Z-up 轴向精准校准**：
   - 解析 `wpn_King_C_Default_r` 的 `m_BindPose` 发现该武器预制体在 Unity 中自带 `+90° X` 轴偏移（`t=[79.135, -14.276, 149.334]`）。在 `extract_3heroes_assets.py` 中对网格顶点、法线及 BindPose 统一左乘 `Rx(-90°)` 后，精确对齐至 `[79.135, 149.334, 14.276]` 且旋转矩阵严格等于 `diag(1, -1, -1)`，与 `weapon_r` 手部抓握误差 `< 0.1 mm`。
2. **独立 3D 暗影锁链建模与着色器（填补军团之王最大视觉缺口）**：
   - 针对只读体检确认缺失的 3 个 3D 锁链外部 CAB（`cab-4491db...`、`cab-131b8f...`、`cab-ddcfef...`），使用 Blender 程序化构建 28 节椭圆锻铁环（相邻环 90° 交替穿扣、自然垂坠弧度）与末端幽冥镣铐环，结合 `Layer Weight -> ColorRamp -> Emission` 实现暗铁核心 + 青蓝幽冥边光。
3. **孙悟空 `0 b_*` 防御轨道合成与攀棍高低判定**：
   - `monkey_king.rar` 全部 82 个 Bundle 中无任何防御动作，本次在 GLB 与 Swift 状态机中同步合成 `rec_monkey_king_mid_block_heavy`（36f/71t60，双臂持棍立架防 + 1.15m 平滑阻尼滑退，不破防）。
   - `monkey_king_climb_stance` 实测骨盆攀升至 `2.123 m`，战斗状态机明确区分低中段地面攻击（`<= 1.25m` 自动规避）与高空防空截击（`>= 1.75m` 打断坠棍且取消俯冲伤害）。
4. **君主双形态无缝切换与单次吸血闭环**：
   - 完整保留人形态与暗影兽两套真实 1K PBR 模型，并在 `emperor_transition` 的真实爆发峰值 `t60 = 100`（`f50`）严格锁定形态切换；若在 `t60 <= 99` 被打断，保持人形态且对敌 0 伤害；暗影兽爪击吸血仅在命中/格挡结算时触发，空挥与打断严格 `0` 回复。

---

## 四、仓外资产与自动化测试验证清单

- **仓外导出成品 GLB（`/home/antigravity/all4_heroes_work/models/`）**：
  - `Hero1_WuYong_Shogun_Completed.glb`（`16 MB`）
  - `Hero2A_LiuQuanwei_EmperorHuman_Completed.glb`（`16 MB`）
  - `Hero2B_LiuQuanwei_ShadowBeast_Completed.glb`（`5.3 MB`）
  - `Hero3_XuXiao_LegionKing_Chain_Completed.glb`（`38 MB`，含 28 节独立建模 3D 暗影锁链 + 幽冥镣铐 + `Rx(-90°)` 校准重剑）
  - `Hero4_SunDeng_MonkeyKing_Completed.glb`（`12 MB`，含金箍棒 + 攀棍石柱 + 独立合成 `rec_monkey_king_mid_block_heavy`）
- **仓外视觉验收媒介（`/home/antigravity/all4_heroes_work/media/`）**：
  - `all4_heroes_headswap_closeups.png`（4 角色换头与衣领贴合特写核验）
  - `all4_heroes_completed_lineup_sheet.png`（4 角色完整武器、变身、3D 锁链、攀棍与合成格挡 2×2 全景图）
  - `all4_heroes_mechanics_storyboard.png`（4×3 关键帧分镜图）
  - `all4_heroes_mechanics_showcase.mp4`（含 4 角色真实原版 WAV 音效的 6.0s 1280×720 演示视频）
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
