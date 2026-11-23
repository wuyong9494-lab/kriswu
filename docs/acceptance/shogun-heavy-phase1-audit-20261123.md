# 《裂隙对决》第一阶段验收报告：吴庸换头幕府将军重斩（`shogun_heavy`）

- 核对日期：2026-11-23
- 基线分支：`codex/duel-original-minimal-20261120` @ `7b9e04f`（未修改 `main` @ `4bb2ff9`、未修改值班功能、未改动刘泉纬／徐骁／孙登）
- 独立执行分支：`codex/shogun-heavy-phase1-prototype`（未合并、未上传 TestFlight、公开仓库不含任何原始第三方媒体二进制）
- 输入归档：`gemini.zip` -> `shogun.rar`（`183,274,095 B`，SHA-256 `a66227c5b090ff8a9d53750022b14222073576821c114bcab1c1a17e128dc109`，含 38 个 Unity AssetBundle；`emperor.rar` / `monkey_king.rar` / `legion_king.rar` 第一阶段未解包、未改动）

## 总体结论：**未通过（原版实机核心机制已实测闭环；仅余 2 项未出现在本局录像的子场景与 20 项外部特效 CAB，待拍板放行前仍不合并、不发 TestFlight）**

| 验收维度 | 状态 | 说明 |
| --- | --- | --- |
| 1. 现状核查与隔离分支 | **通过** | 6 个工作树初始均为 `0 dirty`；本阶段仅在独立分支 `codex/shogun-heavy-phase1-prototype` 新增隔离模块与只读审计文档，零改动 `main`、值班功能及另外三名角色。 |
| 2. 原版数据核实与依赖清单 | **通过** | 已只读拆解 `shogun.rar` 全部 38 个 bundle；区分原版可读、7 处密文未解与 20 项外部缺失依赖 `(CAB, PathID)`，详表见 `docs/acceptance/shogun-heavy-phase1-dependencies-20261123.json`。 |
| 3. 换头、双手握野太刀与原版重斩动作 | **通过** | 吴庸无损原头模（`CleanHead_wuYong.glb`）无偏斜、无露缝接入原版 `skin_hero_Shogun_base_body` + `wpn_Shogun_base_r`，原版 66 帧 `shogun_heavy.bytes` 与实机前冲距（`+1.92 m` vs 实机 `+1.98 m`）吻合。 |
| 4. 原版 60 FPS 实机录像逐帧校对（`11-22-26-10-13-16.mov`） | **核心项通过；2 项子场景未出现** | 已逐帧实测全片 5 次重斩（`EV1–EV5`）：**格挡后果已实证（未蓄力与蓄力重斩正面格挡均不破防、蓝盾立姿滑移+高磨血）**，蓄力裸命中伤害/停顿/击退（`-921/7177`、`16–20t`、`~2.15 m` 倒地）及未蓄力格挡磨血/停顿/滑移（`-313/7177`、`3–4t`、`~1.14 m`）已回填。本局未出现「未蓄力重斩裸命中」与「重斩空挥／起手打断」，相关未测数值继续诚实标为 **`未确认`**。 |
| 5. 四种场景判定（Swift + 同机位对照短视频） | **判定与实机对齐通过（7/7 单测）** | `DuelShogunHeavyPhase1Tests` **7 / 7 通过**（含未蓄力格挡 EV3、蓄力格挡 EV2、蓄力命中 EV1、空挥、提前打断含 tick 43 边界、全距零重复结算）；已输出「实机 SF4 vs 吴庸样板帧同步对照短视频」与「四场景定机位短视频」。 |

---

## 一、原版数据可用边界核实（来源与不可读边界）

| 组件 | 来源文件（`shogun.rar` 内） | 可用程度与分类 | 说明 |
| --- | --- | --- | --- |
| 角色基础蒙皮网格 | `heroes-models-shogun-base-common.bin` (`skin_hero_Shogun_base_body` 11,988v、`_body_02` 265v、`_tie/_02/_03/_04` 3,419v、`skin_hero_Shogun_base_head` 3,205v) | **原版可读直接使用** | 仅移除 `skin_hero_Shogun_base_head`，替换为吴庸原头模 `CleanHead_wuYong.glb`（原 UV 无损）+ 领口内收颈桥。 |
| 角色 1K PBR 贴图 | `heroes-models-shogun-base-pbr.bin` + `heroes-models-shogun-base-pbr-textures.bin` (`_CM`/`_NM`/`_PBR`/`_SSS`, 1024×1024) | **贴图原版可读；PBR 着色器外部缺失（复现）** | 法线贴图为 Unity DXT5nm（`A->X, G->Y, 重建 Z`）正常解包；2 个外部角色/武器着色器 `CAB` 缺失，采用标准 glTF 2.0 Metallic-Roughness 复现。 |
| 野太刀网格与挂点 | `heroes-models-shogun-base-common.bin` (`wpn_Shogun_base_r` 1,611v, 3 骨骼；`w_odati_01_r.prefab`；`wpn_Shohun_base_{CM,NM,PBR}`) | **原版可读直接使用** | 挂点 `weapon_r -> w_odati_01_r (0, 0, -9.020 cm)`；刀柄尾 `w_odati_03_r` 至刀尖 `w_odati_02_r` 全长 `2.06 m`，刀身 `1.456 m`；原版胶囊节点 `w_odati_capsule1_r` / `w_odati_capsule2_r` 可直接读取。 |
| 重斩动作（`shogun_heavy`） | `animations-base-shogun.bin` :: `shogun_heavy.bytes` (`PathID=-1565575211346705244`, `125,494 B`) | **原版非加密二进制可读解析** | 非标准 Unity `AnimationClip`，但为明文二进制关键帧（float16 位置 + smallest-three 四元数）：**2 数组 × 66 帧 @ 30 FPS（2.20 s / 131 tick @ 60 Hz），79 骨骼**（含双手手指、野太刀及 4 根刀光带骨骼 `w_odati_trail1..4`）。另含蓄力版 `shogun_heavy_talent.bytes`（137 帧，58 骨骼）与重击格挡受击 `b_shogun_{high,middle,low,overhead}_heavy.bytes`（41 帧，58 骨骼）。 |
| 骨骼配置 `bones.xml` / `config.xml` | `heroes-models-shogun-base-common.bin` 内 7 处 `.xml` / `magica_init_data.txt` | **Base64 密文不可读（未破解）** | 按合规边界不解密；79 个骨骼 ID 由未加密 `Mesh.m_BindPose` 与 `w_odati_01_l/r` 局部坐标做几何距离比对唯一校核（46 根结构骨骼误差 `0.001–0.04 cm`）。 |
| 刀光与命中特效 | `heroes-models-shogun-base-common.bin` (`wpn_Shogun_base_trail_r` 20v, `trail_base.mat`)；`effects-prefabs-shogun.bin` (`shogun_pf_heavy/*` 5 个 prefab)；`effects-materials-heroes-add_mats-shogun.bin` (`shogun_mt_heavy/*` 6 材质 + 5 张本地贴图) | **网格与 5 张本地贴图原版可读；18 项外部特效依赖缺失 -> 独立复现** | 5 张本地原版贴图可读：`vfx_tex_trail_slash_01`、`VFX_ramp_01`、`vfx_tex_noise_01`、`VFX_TileNoise_darkCloud`、`vfx_smoke_TSA_opt`；原版 3 个特效网格可读：`vfx_mesh_shg_heavy_slash`、`fx_mesh_shg_sword`、`vfx_trail_plane`。其余 18 项外部缺失依赖见下表，渲染中统一标注为**复现**并对齐实机金黄命中爆闪与蓝盾格挡视觉。 |
| 重斩音效 | `audio-sounds-heroes-shogun.bin`（158 个 `AudioClip`，**0 缺失外部引用**） | **原版可读直接使用** | 已提取并与实机音频互相关校核 `sfx_Shogun_heavy_load.wav`、`sfx_Shogun_heavy_ready.wav`、`sfx_Shogun_shadow_whoosh_heavy_01.wav`、`sfx_Shogun_blade_hit.wav`、`sfx_wpn_ODT_scrape_01.wav`、`sfx_wpn_blood_01.wav`、`sfx_vo_Shogun_heavy_attack_01.wav`。 |

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

**本局实机录像仍未覆盖的 2 项细项（继续标 `未确认`，不靠猜）**：
- **未蓄力重斩裸命中伤害与停顿**：`11-22-26-10-13-16.mov` 中全部 3 次重斩裸命中均带 `攻击已充能!`；未蓄力裸命中数值仍标 **`未确认`**。
- **重斩空挥与起手提前打断的实机录像**：本局未出现重斩空挥或起手被打断（实机起手是否带霸体帧标 **`未确认`**；样板在 Swift 单测与 3D 实拍中严格保证空挥与生效前打断 0 误扣血）。

---

## 三、原版 60 FPS 实机录像逐帧实测与四种场景结果

### 3.1 原版实机录像实测总表（`11-22-26-10-13-16.mov`，60 FPS，`1568×720`，`149.70 s`，SHA-256 `eb58abda...`）

对局双方：幕府将军 `TAKI`（`4986/4986 HP`）vs 伊图 `CHƯA TÀY ĐÂU`（`7177/7177 HP`），全片共出现 **5 次重斩**，逐帧测得：

| 实机事件 | 时间段 | 类型 / 状态 | 守方 HP 变化（占 7177 比例） | 格挡后果 | 实测停顿 (`60 Hz`) | 实测位移（地平面标定） | 结算次数 |
| --- | --- | --- | --- | --- | --- | --- | ---: |
| **EV1** | `62.10–65.10 s` | **蓄力重斩裸命中**（`攻击已充能!` + 画面红字 **`暴击`**，蓄满 `48t / 0.80 s`） | `1743 -> 822`（**`-921`** / **`12.83%`**） | 裸命中 -> 金黄爆闪 + **强倒地** | **`~18–20t`**（核心定格 `~14t` + 慢放释放 `~6t`） | 击飞倒地 **`~2.15 m`**（`2.05–2.25 m`） | **1** |
| **EV2** | `65.20–69.00 s` | **蓄力重斩被格挡**（`攻击已充能!`，长按蓄力） | `822 -> 265`（**`-557`** / **`7.76%`**，为裸命中 `60.48%`） | **蓝盾格挡、不破防、不倒地** | **`4–5t`** 微停顿 | 贴右侧版边滑移被墙体截断 | **1** |
| **EV3** | `112.70–114.90 s` | **未蓄力重斩被格挡**（无 `攻击已充能!`） | `3940 -> 3627`（**`-313`** / **`4.36%`**，为同局普攻格挡 `68` 的 `4.60×`） | **蓝盾格挡、不破防、不倒地** | **`3–4t`** 微停顿 | 攻方前冲 **`+1.98 m`**（吻合二进制 `+1.92 m`）；守方立姿滑移 **`~1.14 m`**（接近 `b_shogun_middle_heavy` `+1.28 m`） | **1** |
| **EV4** | `127.10–129.60 s` | **蓄力重斩裸命中**（`攻击已充能!`，`x2 连击`） | `3290 -> 2392`（**`-898`** / **`12.51%`**） | 裸命中 -> 金黄爆闪 + **强倒地** | **`~15–17t`**（含 `f090..f094` 纯静止 5 帧） | 强倒地击退 | **1** |
| **EV5** | `139.00–141.40 s` | **蓄力重斩暗影终结**（`攻击已充能!` + `暴击`） | 终结击杀 | 黑剪影红斩定格（对应 `sfx_Shogun_Freeze_Frame_01.wav`） | 黑红定格 | 终结倒地 | **1** |

### 3.2 `shogun_heavy.bytes` 动作分段与实机互验

| 指标 | 数值 | 来源与状态 |
| --- | --- | --- |
| 总帧数 / 逻辑 tick | `66 f` @ 30 FPS (`2.20 s`) / `131 tick` @ 60 Hz (`MidFrames = 1`) | **原版二进制实测**（`shogun_heavy.bytes`） |
| 起手帧段（Startup） | `f30 = 0..21`（`t60 = 0..43`，44 tick）；`f30 = 6` 双手锁柄；实机 EV3 举刀+突进至接触合计 `~42–46t`（不含手动停顿） | **原版二进制 + 实机录像互验通过** |
| 有效命中窗口（Active） | `f30 = 22..25`（`t60 = 44..51`，8 tick）；刀尖速度 `18.37 -> 76.07 m/s`，最大触达 `+3.888 m`，刀光骨骼 `w_odati_trail2..4` 仅此 4 帧展开 `17.0..66.9 cm` | **原版二进制实测 + 实机 EV3 `f073..f076` 吻合** |
| 收招帧段（Recovery） | `f30 = 26..65`（`t60 = 52..130`，79 tick）；净前冲 `+1.919 m`（实机 EV3 `+1.98 m`）；实机 EV3 击中后约 `~60t` 可衔接下招 | **原版二进制 + 实机录像互验通过** |
| 格挡后果与滑移 | 正面格挡**均不破防**（EV3 未蓄力 `-313 / 4.36%` + `3–4t` 停顿；EV2 蓄力 `-557 / 7.76%` + `4–5t` 停顿）；`b_shogun_middle_heavy.bytes` 41f 净滑移 `+1.2791 m`（实机 EV3 `~1.14 m`） | **原版实机录像 + 原版二进制双实测** |
| 未蓄力裸命中 / 起手霸体 | 未蓄力裸命中伤害（推算占位 `209/2900`）与起手是否带霸体帧 | **未确认（本局录像未出现）** |

### 3.3 四种必测场景逐帧结果（固定侧视、攻守初始 `2900 / 2900 HP`，按实机比例标定）

固定侧视机位：同机位原版模型对照（Video 1）`eye=(1.65, -5.60, 1.48), lens=38mm`；四场景对战（Video 2）`eye=(2.15, -6.95, 1.48), lens=33mm`；实机 SF4 vs 吴庸帧同步对照视频同步对齐 `EV3` 格挡与 `EV1` 蓄力命中。

| 场景 | 初始位置 (`攻 / 守`) | 起手 / 有效 / 收招 (`60 Hz tick`) | 接触帧 | 结算次数 | 攻方 HP | 守方 HP（按 `2900` 同比实机 `7177`） | 停顿 / 击退 | 判定结果与来源 |
| --- | --- | --- | --- | ---: | ---: | ---: | --- | --- |
| **1. 正常命中（蓄力）** | `0.00 m / 2.85 m`（无防） | `44 / 8 / 79` | `t60 = 49` (`f30 = 24.5`) | **1**（单段锁定） | `2900 -> 2900` | `2900 -> 2528` (`-372`, **实机 EV1 `921/7177 = 12.83%`**) | **`18t`** [**实机 EV1/EV4**] / **`+2.15 m` 倒地** [**实机 EV1**] | **判定与实机对齐通过**（全距 `1.60..4.00 m` 0 重复结算） |
| **2. 空挥** | `0.00 m / 4.65 m`（超距） | `44 / 8 / 79` | 无接触 | **0** | `2900 -> 2900` | **`2900 -> 2900`** (`0`) | `0t` / `0.00 m` | **通过**（0 误扣血，触地烟尘复现 + 原版刮地音效） |
| **3A. 格挡（未蓄力）** | `0.00 m / 2.85 m`（正面格挡） | `44 / 8 / 79` | `t60 = 49` (`f30 = 24.5`) | **1**（单段锁定） | `2900 -> 2900` | `2900 -> 2774` (`-126`, **实机 EV3 `313/7177 = 4.36%`**) | **`4t`** [**实机 EV3**] / **`+1.28 m` 不破防立姿滑移**（**原版 41f + 实机 EV3 `~1.14 m`**） | **通过（实机实测确认不破防 + 蓝盾高磨血）** |
| **3B. 格挡（蓄力）** | `0.00 m / 2.85 m`（正面格挡） | `44 / 8 / 79` | `t60 = 49` (`f30 = 24.5`) | **1**（单段锁定） | `2900 -> 2900` | `2900 -> 2675` (`-225`, **实机 EV2 `557/7177 = 7.76%`**) | **`5t`** [**实机 EV2**] / **`+1.28 m` 仍不破防** | **通过（实机 EV2 确认蓄力格挡亦不破防，磨血为裸命中 60.5%）** |
| **4. 提前打断** | `0.00 m / 1.35 m`（反击） | `24 / 0 / 0`（边界 `43 / 0 / 0`） | 无有效命中 | **0** | `2900 -> 2815` (`-85`) | **`2900 -> 2900`** (`0`) | `0t` / `0.00 m` | **逻辑通过**（生效前即取消，含 tick 43 边界 0 误扣血；实机起手霸体与否 **未确认**） |

---

## 四、自动化测试验证

- `swift test --filter DuelShogunHeavyPhase1Tests`：**7 / 7 通过，0 失败**（`0.006s`，覆盖二进制/实机前冲互验、蓄力命中 EV1、空挥、未蓄力格挡 EV3、蓄力格挡 EV2、起手打断含边界 tick 43、全距 `1.60..4.00 m` 零重复结算）。
- 回归测试：`DuelShogunTests` **8 / 8 通过**、`DuelWeaponCapsuleTests` **8 / 8 通过**（未破坏既有功能、未触碰 `main`、值班功能及另外三名角色）。

