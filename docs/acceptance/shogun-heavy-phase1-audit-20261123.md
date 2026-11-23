# 《裂隙对决》第一阶段验收报告：吴庸换头幕府将军重斩（`shogun_heavy`）

- 核对日期：2026-11-23
- 基线分支：`codex/duel-original-minimal-20261120` @ `7b9e04f`（未修改 `main` @ `4bb2ff9`、未修改值班功能、未改动刘泉纬／徐骁／孙登）
- 独立执行分支：`codex/shogun-heavy-phase1-prototype`（未合并、未上传 TestFlight、公开仓库不含任何原始第三方媒体二进制）
- 输入归档：`gemini.zip` -> `shogun.rar`（`183,274,095 B`，SHA-256 `a66227c5b090ff8a9d53750022b14222073576821c114bcab1c1a17e128dc109`，含 38 个 Unity AssetBundle；`emperor.rar` / `monkey_king.rar` / `legion_king.rar` 第一阶段未解包、未改动）

## 总体结论：**未通过（原版实机录像缺失，实机数值与格挡后果待实测确认）**

| 验收维度 | 状态 | 说明 |
| --- | --- | --- |
| 1. 现状核查与隔离分支 | **通过** | 6 个工作树初始均为 `0 dirty`；本阶段仅在独立分支 `codex/shogun-heavy-phase1-prototype` 新增隔离模块与只读审计文档，零改动 `main`、值班功能及另外三名角色。 |
| 2. 原版数据核实与依赖清单 | **通过** | 已只读拆解 `shogun.rar` 全部 38 个 bundle；区分原版可读、密文未解与 20 项外部缺失依赖 `(CAB, PathID)`，详表见 `docs/acceptance/shogun-heavy-phase1-dependencies-20261123.json`。 |
| 3. 换头、双手握野太刀与原版重斩动作 | **通过** | 吴庸无损原头模（`CleanHead_wuYong.glb`）无偏斜、无露缝接入原版 `skin_hero_Shogun_base_body` + `wpn_Shogun_base_r`，原版 66 帧 `shogun_heavy.bytes` 实测播放通过。 |
| 4. 四种场景判定（Swift + 3D 固定侧视） | **判定逻辑通过；实机数值未确认** | `DuelShogunHeavyPhase1Tests` 6/6 通过（0 失败）：正常命中单次结算、空挥 0 扣血、格挡单次结算+原版 41 帧滑移、起手提前打断（含边界 tick 43）0 误扣血。 |
| 5. 同机位「原版实机录像」对照与格挡实测 | **未通过（缺输入）** | Dropbox `gemini.zip` 仅含 4 个资源 `.rar`，**不含原版幕府将军实机对战录像**，也无明文数值表。已输出同机位「原版 `shogun.rar` 渲染 vs 吴庸换头样板」短视频与 4 场景短视频，但实机格挡后果（是否破防/磨血比例）、实机停顿帧数、伤害与击退倍率标注为 **`未确认`**。 |

---

## 一、原版数据可用边界核实（来源与不可读边界）

| 组件 | 来源文件（`shogun.rar` 内） | 可用程度与分类 | 说明 |
| --- | --- | --- | --- |
| 角色基础蒙皮网格 | `heroes-models-shogun-base-common.bin` (`skin_hero_Shogun_base_body` 11,988v、`_body_02` 265v、`_tie/_02/_03/_04` 3,419v、`skin_hero_Shogun_base_head` 3,205v) | **原版可读直接使用** | 仅移除 `skin_hero_Shogun_base_head`，替换为吴庸原头模 `CleanHead_wuYong.glb`（原 UV 无损）+ 领口内收颈桥。 |
| 角色 1K PBR 贴图 | `heroes-models-shogun-base-pbr.bin` + `heroes-models-shogun-base-pbr-textures.bin` (`_CM`/`_NM`/`_PBR`/`_SSS`, 1024×1024) | **贴图原版可读；PBR 着色器外部缺失（复现）** | 法线贴图为 Unity DXT5nm（`A->X, G->Y, 重建 Z`）正常解包；2 个外部角色/武器着色器 `CAB` 缺失，采用标准 glTF 2.0 Metallic-Roughness 复现。 |
| 野太刀网格与挂点 | `heroes-models-shogun-base-common.bin` (`wpn_Shogun_base_r` 1,611v, 3 骨骼；`w_odati_01_r.prefab`；`wpn_Shohun_base_{CM,NM,PBR}`) | **原版可读直接使用** | 挂点 `weapon_r -> w_odati_01_r (0, 0, -9.020 cm)`；刀柄尾 `w_odati_03_r` 至刀尖 `w_odati_02_r` 全长 `2.06 m`，刀身 `1.456 m`；原版胶囊节点 `w_odati_capsule1_r` / `w_odati_capsule2_r` 可直接读取。 |
| 重斩动作（`shogun_heavy`） | `animations-base-shogun.bin` :: `shogun_heavy.bytes` (`PathID=-1565575211346705244`, `125,494 B`) | **原版非加密二进制可读解析** | 非标准 Unity `AnimationClip`，但为明文二进制关键帧（float16 位置 + smallest-three 四元数）：**2 数组 × 66 帧 @ 30 FPS（2.20 s / 131 tick @ 60 Hz），79 骨骼**（含双手手指、野太刀及 4 根刀光带骨骼 `w_odati_trail1..4`）。另含蓄力/天赋版 `shogun_heavy_talent.bytes`（137 帧，58 骨骼）与重击格挡受击 `b_shogun_{high,middle,low,overhead}_heavy.bytes`（41 帧，58 骨骼）。 |
| 骨骼配置 `bones.xml` / `config.xml` | `heroes-models-shogun-base-common.bin` 内 7 处 `.xml` / `magica_init_data.txt` | **Base64 密文不可读（未破解）** | 按合规边界不解密；79 个骨骼 ID 由未加密 `Mesh.m_BindPose` 与 `w_odati_01_l/r` 局部坐标做几何距离比对唯一校核（46 根结构骨骼误差 `0.001–0.04 cm`）。 |
| 刀光与命中特效 | `heroes-models-shogun-base-common.bin` (`wpn_Shogun_base_trail_r` 20v, `trail_base.mat`)；`effects-prefabs-shogun.bin` (`shogun_pf_heavy/*` 5 个 prefab)；`effects-materials-heroes-add_mats-shogun.bin` (`shogun_mt_heavy/*` 6 材质 + 5 张本地贴图) | **网格与 5 张本地贴图原版可读；18 项外部特效依赖缺失 -> 独立复现** | 5 张本地原版贴图可读：`vfx_tex_trail_slash_01`、`VFX_ramp_01`、`vfx_tex_noise_01`、`VFX_TileNoise_darkCloud`、`vfx_smoke_TSA_opt`；原版 3 个特效网格可读：`vfx_mesh_shg_heavy_slash`、`fx_mesh_shg_sword`、`vfx_trail_plane`。其余 18 项外部缺失依赖见下表，渲染中统一标注为**复现**。 |
| 重斩音效 | `audio-sounds-heroes-shogun.bin`（158 个 `AudioClip`，**0 缺失外部引用**） | **原版可读直接使用** | 已提取 `sfx_Shogun_heavy_load.wav`、`sfx_Shogun_heavy_ready.wav`、`sfx_Shogun_shadow_whoosh_heavy_01.wav`、`sfx_Shogun_blade_hit.wav`、`sfx_wpn_ODT_scrape_01.wav`、`sfx_wpn_blood_01.wav`、`sfx_vo_Shogun_heavy_attack_01.wav`。 |

---

## 二、未解决依赖清单（第一阶段精确到外部 `CAB` 与 `PathID`，共 20 项）

完整机器可读清单见 `docs/acceptance/shogun-heavy-phase1-dependencies-20261123.json`（全包 38 个 bundle 累计缺失外部引用条目 154 处；下表列出**第一阶段幕府将军模型 + 重斩刀光/命中特效**全部 20 项精确缺失依赖）：

| # | 类别 | 缺失外部 `CAB` | 缺失 `PathID` | 引用对象与属性 | 第一阶段处理方式 |
| ---: | --- | --- | ---: | --- | --- |
| 1 | VFX 网格 | `CAB-0ad1723334021877b14a24d2cb27f971` | `6095070311175572921` | `fx_shogun_heavy_trails(weapon_r_0).prefab` / `fx_shg_heavy_wave_in` (`m_Mesh`) | 缺失，第一阶段独立复现/省略波纹网格 |
| 2 | VFX 着色器 | `CAB-b362a4cedf7b92e649a345ad97da2456` | `7373163325283962925` | 全部 6 个 `fx_shg_heavy_*.mat` + `fx_shg_smoke.mat` + `fx_shg_splash.mat` (`m_Shader`) | 缺失，使用自发光 Alpha 着色器独立复现 |
| 3 | VFX 着色器 | `CAB-56d919bd5479d38f741da52a6beef92f` | `1830340831928533694` | `fx_shg_flash.mat` + `fx_shg_sparks.mat` (`m_Shader`) | 缺失，独立复现 |
| 4 | 刀光着色器 | `CAB-b362a4cedf7b92e649a345ad97da2456` | `-8050354664297809014` | `trail_base.mat` + `trail_shadow.mat` (`m_Shader`) | 缺失，原版 `wpn_Shogun_base_trail_r` 网格 + 原版 `vfx_tex_trail_slash_01` 贴图配复现着色器 |
| 5 | VFX 贴图 | `CAB-df8061062563c5389d94b6c1b6e9edae` | `-1120883871214229135` | `fx_shg_heavy_edge.mat` / `fx_shg_heavy_trails_in.mat` (`_DistortTex`) | 缺失，复现 |
| 6 | VFX 贴图 | `CAB-6c6df212ea0bf2e720d9a3c3f2b4867e` | `4697666133948377664` | `fx_shg_heavy_edge.mat` (`_MainTex`) | 缺失，复现 |
| 7 | VFX 贴图 | `CAB-7982c12d5d762482940c93b84344a615` | `-7532295210670410143` | `fx_shg_heavy_edge.mat` (`_MaskTex`) | 缺失，复现 |
| 8 | VFX 贴图 | `CAB-67ad41ff4235b1e301bc435fc9f64e58` | `-7248466878890212566` | `fx_shg_heavy_{edge,sword,trails_in,wave_in}.mat` / `fx_shg_smoke.mat` (`_Tex2`/`_MainTex`/`_DistortTex`) | 缺失，复现 |
| 9 | VFX 贴图 | `CAB-d25538ee442ac284a1f6034649153f87` | `758012997903668798` | `fx_shg_heavy_impact_spikes.mat` / `fx_shg_heavy_wave_in.mat` (`_DistortTex`) | 缺失，复现 |
| 10 | VFX 贴图 | `CAB-536f6dbec0ac132706adea1b53737ff2` | `-6479658091753498865` | `fx_shg_heavy_impact_spikes.mat` (`_MaskTex`) | 缺失，复现 |
| 11 | VFX 贴图 | `CAB-27f70f4aa75f5c2b15737bf89c6fbf94` | `1038372577286207603` | `fx_shg_heavy_slash.mat` (`_MaskTex`) | 缺失，复现（主/渐变/噪点贴图用原版） |
| 12 | VFX 贴图 | `CAB-18b6f024c02faab8545e8d00cae8c66f` | `-613962727008778602` | `fx_shg_heavy_sword.mat` / `fx_shg_heavy_trails_in.mat` (`_MaskTex`) | 缺失，复现 |
| 13 | VFX 贴图 | `CAB-008b65b925b880b8210510b942a86688` | `-8570749644217509411` | `fx_shg_heavy_trails_in.mat` (`_MainTex`) | 缺失，复现 |
| 14 | VFX 贴图 | `CAB-242fc4ab99d02415831250b98fc6cda3` | `2133459429896764726` | `fx_shg_heavy_wave_in.mat` (`_MainTex`) | 缺失，复现 |
| 15 | VFX 贴图 | `CAB-a41171d33bb22bbc18df9f7b0910ded0` | `673014424893667739` | `fx_shg_heavy_wave_in.mat` (`_MaskTex`) | 缺失，复现 |
| 16 | VFX 贴图 | `CAB-84a3e71eb7654b597837d22fda3dccd2` | `8303572611695458412` | `fx_shg_flash.mat` (`_MainTex`) | 缺失，复现 |
| 17 | VFX 贴图 | `CAB-c1d0b8033a6be0724e29bfd731df37a5` | `5672975400942849768` | `fx_shg_sparks.mat` (`_MainTex`) | 缺失，复现 |
| 18 | VFX 贴图 | `CAB-0a8e57b45cd75bd1512a7e0f78076ddb` | `5990154127222293458` | `fx_shg_splash.mat` (`_MainTex`) | 缺失，复现 |
| 19 | 角色 PBR 着色器 | `CAB-b362a4cedf7b92e649a345ad97da2456` | `1617579206180282452` | `pbr_arm_shogun_base` / `pbr_tie_shogun_base` / `pbr_helm_shogun_base` (`m_Shader`) | 缺失，采用标准 glTF 2.0 PBR 复现 |
| 20 | 武器 PBR 着色器 | `CAB-a6995602d3ac62371a30d90c9e5a83a6` | `2720044653844142656` | `pbr_wpn_shogun_base` (`m_Shader`) | 缺失，采用标准 glTF 2.0 PBR 复现 |

**非归档缺失项（直接导致本轮无法标通过）**：
- **原版幕府将军实机对战录像**：`gemini.zip` 未附带，导致实机格挡后果、停顿帧数、伤害/磨血比例、实机起手可打断边界无法与实机录像逐帧校对，均标为 **`未确认`**。

---

## 三、逐帧测量与四种场景验收数据（固定侧视机位、固定初始位置与 2900 HP）

### 3.1 `shogun_heavy.bytes` 帧段划分与数值来源

| 指标 | 数值 | 来源与状态 |
| --- | --- | --- |
| 总帧数 / 逻辑 tick | `66 f` @ 30 FPS (`2.20 s`) / `131 tick` @ 60 Hz (`MidFrames = 1`) | **原版二进制实测**（`shogun_heavy.bytes`） |
| 起手帧段（Startup） | `f30 = 0..21`（`t60 = 0..43`，共 44 tick）；双手于 `f30 = 6` 锁柄，骨盆前冲 `+1.390 m` | **原版二进制实测**（`shogun_heavy.bytes` FK） |
| 有效命中窗口（Active） | `f30 = 22..25`（`t60 = 44..51`，共 8 tick）；刀尖线速度 `18.37 -> 35.81 -> 65.18 -> 76.07 m/s`，最大触达 `+3.888 m`，原版刀光骨骼 `w_odati_trail2..4` 仅在此 4 帧展开 `17.0..66.9 cm` | **原版二进制轨迹推导**（实机服务端命中帧表 **未确认**） |
| 收招帧段（Recovery） | `f30 = 26..65`（`t60 = 52..130`，共 79 tick）；`f30 = 26` 刀光归零且刀尖触地（`Y = 0.033 m`），最终骨盆前移 `+1.919 m` | **原版二进制实测** |
| 格挡滑移曲线 | `b_shogun_middle_heavy.bytes`：`41 f` @ 30 FPS（`81 tick` @ 60 Hz），峰值滑移 `1.5191 m`，净滑移 `1.2791 m` | **原版二进制实测** |
| 伤害 / 磨血 / 格挡破防 / 停顿 / 命中击退 | 样板默认 `dmg=320`、`chip=48 (15%)`、`hitstop=10t (block 6t)`、`knockback=1.65 m`、未蓄力格挡按 `recreatedBlockWithChip` 演示 | **未确认（独立复现占位，不宣称原版算法，待原版实机录像校对）** |

### 3.2 四种必测场景逐帧结果（`Sources/ShiftCore/DuelShogunHeavyPhase1.swift` + `Tests/ShiftCoreTests/DuelShogunHeavyPhase1Tests.swift`）

固定侧视机位：同机位对照短视频（Video 1）使用 `eye=(1.65, -5.60, 1.48)`、`target=(1.65, 0.0, 1.15)`、`lens=38mm`；四场景对战短视频（Video 2）使用 `eye=(2.15, -6.95, 1.48)`、`target=(2.15, 0.0, 1.12)`、`lens=33mm`；攻守初始血量均为 `2900 / 2900`。

| 场景 | 初始位置 (`攻 / 守`) | 起手 / 有效 / 收招 (`60 Hz tick`) | 命中接触帧 | 结算次数 | 攻方 HP 变化 | 守方 HP 变化 | 停顿 / 击退 | 判定结果 |
| --- | --- | --- | --- | ---: | ---: | ---: | --- | --- |
| **1. 正常命中** | `0.00 m / 2.85 m`（无防） | `44 / 8 / 79` | `t60 = 49` (`f30 = 24.5`) | **1**（单段锁定，0 重复） | `0` (`2900 -> 2900`) | `-320` (`2900 -> 2580`, **未确认数值**) | `10t [未确认]` / `+1.65 m [复现]` | **判定通过**（含刀光/受击/原版命中音效） |
| **2. 空挥** | `0.00 m / 4.65 m`（超距） | `44 / 8 / 79` | 无接触 | **0** | `0` (`2900 -> 2900`) | **`0`** (`2900 -> 2900`) | `0t` / `0.00 m` | **通过**（0 误扣血，触发触地烟尘复现与原版刮地音效） |
| **3. 格挡** | `0.00 m / 2.85 m`（正面格挡） | `44 / 8 / 79` | `t60 = 49` (`f30 = 24.5`) | **1**（单段锁定） | `0` (`2900 -> 2900`) | `-48` (`2900 -> 2852`, **格挡后果未确认:复现**) | `6t [未确认]` / `+1.28 m`（**原版 41f 滑移实测**） | **逻辑通过，实机后果未确认** |
| **4. 提前打断** | `0.00 m / 1.35 m`（反击） | `24 / 0 / 0`（边界 `43 / 0 / 0` 亦测） | 无有效命中 | **0** | `-85` (`2900 -> 2815`) | **`0`** (`2900 -> 2900`) | `0t` / `0.00 m` | **通过**（生效前即取消重斩，0 误扣血；边界 `t60 = 43` 亦验证 0 扣血） |

---

## 四、自动化测试验证

- `swift test --filter DuelShogunHeavyPhase1Tests`：**6 / 6 通过，0 失败**（含全距离 `1.60 m .. 4.00 m` 零重复结算扫描、边界 `t60 = 43` 提前打断验证、原版 66 帧刀光轨迹校核）。
- 回归测试：`DuelShogunTests` 全部通过（未破坏既有功能、未触碰另外三名角色）。
