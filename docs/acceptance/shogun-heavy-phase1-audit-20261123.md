# 《裂隙对决》第一阶段验收报告：吴庸换头幕府将军重斩（`shogun_heavy`）

- 核对日期：2026-11-23
- 基线分支：`codex/duel-original-minimal-20261120` @ `7b9e04f`（未修改 `main` @ `4bb2ff9`、未修改值班功能、未改动刘泉纬／徐骁／孙登）
- 独立执行分支：`codex/shogun-heavy-phase1-prototype`（未合并、未上传 TestFlight、公开仓库不含任何原始第三方媒体二进制）
- 输入归档：`gemini.zip` -> `shogun.rar`（`183,274,095 B`，SHA-256 `a66227c5b090ff8a9d53750022b14222073576821c114bcab1c1a17e128dc109`，含 38 个 Unity AssetBundle；`emperor.rar` / `monkey_king.rar` / `legion_king.rar` 第一阶段未解包、未改动）

## 总体结论：**未通过（按 `_.md` 严口径仅验「普通重斩」，排除蓄力／暴击干扰后，尚缺同版本基础装备可控录屏覆盖普通重斩裸命中、空挥、格挡数值与生效前打断；不合并、不上传 TestFlight）**

| 验收维度 | 状态 | 说明 |
| --- | --- | --- |
| 1. 现状核查与隔离分支 | **通过** | 6 个工作树初始均为 `0 dirty`；本阶段仅在独立分支 `codex/shogun-heavy-phase1-prototype` 新增隔离模块与只读审计文档，零改动 `main`、值班功能及另外三名角色。 |
| 2. 原版数据核实与依赖清单 | **通过** | 已只读拆解 `shogun.rar` 全部 38 个 bundle；区分原版可读、`shogun_heavy.bytes` 非加密二进制（非直接可播 AnimationClip，亦不含原版判定/伤害算法）、7 处密文未解与 20 项外部缺失依赖 `(CAB, PathID)`，详表见 `docs/acceptance/shogun-heavy-phase1-dependencies-20261123.json`。 |
| 3. 换头、双手握野太刀与原版重斩动作 | **通过** | 吴庸无损原头模（`CleanHead_wuYong.glb`）无偏斜、无露缝接入原版 `skin_hero_Shogun_base_body` + `wpn_Shogun_base_r`，原版 66 帧 `shogun_heavy.bytes` 实测播放通过。 |
| 4. 普通重斩四项判定（Swift + 3D 定机位样板） | **样板逻辑通过（6/6 单测）；实机数值待可控录屏** | `DuelShogunHeavyPhase1Tests` **6 / 6 通过**（严格只按普通重斩：正常命中单次结算、空挥 0 扣血 0 受击特效、格挡单次结算不破防+原版 41f 滑移、生效前打断含边界 tick 43 无延迟命中/无重复结算）。 |
| 5. 同版本基础装备可控实机对照 | **未通过（缺可控原版录屏）** | 仅拿到移动端实战片 `11-22-26-10-13-16.mov`（仅 `EV3` 1 次为无蓄力/无暴击/无随从的**普通重斩格挡**，且无法核实平台/装备一致性；`EV1/EV2/EV4/EV5` 因带 `攻击已充能!`／`暴击` 已按 `_.md` 隔离排除）。`_.md` 内 4 条 YouTube 链接在云端 VM 因 `googlevideo.com` `HTTP 403`（JS 挑战）未绕过拉取。 |

---

## 一、原版数据可用边界核实（来源与不可读边界）

| 组件 | 来源文件（`shogun.rar` 内） | 可用程度与分类 | 说明 |
| --- | --- | --- | --- |
| 角色基础蒙皮网格 | `heroes-models-shogun-base-common.bin` (`skin_hero_Shogun_base_body` 11,988v、`_body_02` 265v、`_tie/_02/_03/_04` 3,419v、`skin_hero_Shogun_base_head` 3,205v) | **原版可读直接使用** | 仅移除 `skin_hero_Shogun_base_head`，替换为吴庸原头模 `CleanHead_wuYong.glb`（原 UV 无损）+ 领口内收颈桥。 |
| 角色 1K PBR 贴图 | `heroes-models-shogun-base-pbr.bin` + `heroes-models-shogun-base-pbr-textures.bin` (`_CM`/`_NM`/`_PBR`/`_SSS`, 1024×1024) | **贴图原版可读；PBR 着色器外部缺失（复现）** | 法线贴图为 Unity DXT5nm（`A->X, G->Y, 重建 Z`）正常解包；2 个外部角色/武器着色器 `CAB` 缺失，采用标准 glTF 2.0 Metallic-Roughness 复现。 |
| 野太刀网格与挂点 | `heroes-models-shogun-base-common.bin` (`wpn_Shogun_base_r` 1,611v, 3 骨骼；`w_odati_01_r.prefab`；`wpn_Shohun_base_{CM,NM,PBR}`) | **原版可读直接使用** | 挂点 `weapon_r -> w_odati_01_r (0, 0, -9.020 cm)`；刀柄尾 `w_odati_03_r` 至刀尖 `w_odati_02_r` 全长 `2.06 m`，刀身 `1.456 m`；原版胶囊节点 `w_odati_capsule1_r` / `w_odati_capsule2_r` 可直接读取。 |
| 重斩动作（`shogun_heavy`） | `animations-base-shogun.bin` :: `shogun_heavy.bytes` (`PathID=-1565575211346705244`, `125,494 B`) | **原版非加密二进制可读解析（不含判定/伤害算法）** | 非标准 Unity `AnimationClip`，经二进制结构读取还原为 **66 帧 @ 30 FPS（`2.20 s`，79 骨骼含手指与 `w_odati_trail1..4`）**；仅提供骨骼轨迹，**不代表已拿到原版命中判定或伤害算法**。另含重击格挡受击 `b_shogun_{high,middle,low,overhead}_heavy.bytes`（41 帧）。 |
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

**未补齐的可控实机录像与外链阻塞说明**：
- `_.md` 提供的 4 条 YouTube 参考（`AfZPeriDCrA` Steam 排位、`2Zl55gtOq3Y` 3v3、`gPJx0UKCEQE` 13 英雄、`f2RrzxNKfFQ` 移动稀有武器）已完整登记章节，但云端 VM 拉取 `googlevideo.com` 音视频流返回 `HTTP 403 Forbidden`（JS 挑战），未做绕过。
- 仅 `11-22-26-10-13-16.mov` 在 VM 内可读，但它是移动端实战录屏，无法确认基础装备/天赋条件，且仅覆盖普通重斩「格挡」1 项。

---

## 三、原版实机观测（严格按 `_.md` 排除干扰项）与四种场景结果

### 3.1 录像帧率、丢帧与测量不确定度（`11-22-26-10-13-16.mov`）

- **文件校验**：`68,692,523 B`，SHA-256 `eb58abda145665b986118fc2418ebc00e9119bdf990e6d7a1e9267e63f1294e0`，分辨率 `1568×720`。
- **帧率与丢帧**：全片 `8,893` 帧 / `149.683 s`，平均 **`59.405 FPS`**（VFR）；帧间隔 `>22 ms` 共 **`89` 处（`1.00%`）**，最大间隔 `33.3 ms`。在普通重斩格挡窗口 `EV3`（`112.5–115.5 s`）内实测 `181` 帧、局部 **`60.000 FPS`、`0` 丢帧**。
- **测量不确定度**：所有时间与帧数均为**录像观测帧**（不确定度 `±1–2` 录像帧 = `±16.7–33.3 ms`，地平面位移标定 `±0.12 m`），**不把录像帧等同于引擎逻辑帧**。

### 3.2 唯一无干扰的普通重斩观测：`EV3`（`112.70–114.90 s`，移动端正面格挡参考）

无 `攻击已充能!`、无 `暴击`、无随从介入；移动端实战装备/天赋条件不可控，仅作行为参考、不定 Steam 基础数值：

| 观测节点 | 录像时间点 / 局部录像帧 | 观测事实与状态 |
| --- | --- | --- |
| 输入（若可见） | — | **未确认**（右下虚拟按键被抖音水印遮挡） |
| 起手抬刀 | `112.750 s`（`f003`） | 进入双手举刀蓄势；短停顿后于 `113.600 s`（`f054`）进入前冲突进 |
| 首个视觉接触 | **`113.950 s`**（`f075`） | 野太刀触及伊图正面格挡 |
| 首次扣血 | **`113.950 s`**（`f075`） | **与首接触同录像帧**：HUD 由 `3940/7177` 降至 `3627/7177`（`-313`），`f076..f082` 零二次扣血（单段单次结算） |
| 特效起点 | `113.950 s`（`f075`） | 伊图胸前出现蓝色竖盾格挡波，**不破防、不倒地** |
| 音效起点 | `113.650 s` / `114.050 s` | 音频包络 `113.65 s` 起挥刀风声、`114.05 s` 撞击主峰（含录屏音画封装延迟不确定度） |
| 格挡停顿 | `f075..f078` | 约 **`3–4` 录像帧**（`~50–67 ms` 微停顿；**录像帧 ≠ 引擎逻辑帧**） |
| 击退滑移 | `f077..f096`（`~19` 录像帧） | 攻方前冲 `~1.98 ± 0.12 m`（吻合 `shogun_heavy.bytes` `+1.92 m`）；守方立姿滑移 `~1.14 ± 0.12 m`（接近 `b_shogun_middle_heavy` `+1.28 m`） |
| 收招后重新可操作 | 守方 `114.333 s`（`f098`） / 攻方 `114.900 s`（`f132`） | 守方接触后约 `23` 录像帧恢复立姿；攻方接触后约 `57` 录像帧（`0.95 s`）起手下一招普攻 |

> **已隔离排除的干扰片段（不用于普通重斩定值）**：同视频中 `EV1`（`62.10–65.10 s`，`-921`、`18–20` 录像帧停顿、`~2.15 m` 倒地）、`EV2`（`65.20–69.00 s`，格挡 `-557` 不破防）、`EV4`（`127.10–129.60 s`，`x2 连击 -898`）与 `EV5`（`139.00–141.40 s` 暗影终结）均触发了 **`攻击已充能!`**（及 `EV1/EV5` 红字 **`暴击`**），按 `_.md` 规范全部排除，不混入普通重斩基准。

### 3.3 四种必测场景结果（严格只验「普通重斩」，`2900 / 2900 HP` 固定侧视样板）

固定侧视机位：同机位模型对照（Video 1）`eye=(1.65, -5.60, 1.48), lens=38mm`；四场景样板（Video 2）`eye=(2.15, -6.95, 1.48), lens=33mm`。

| 场景（普通重斩） | 初始位置 (`攻 / 守`) | 样板起手 / 有效 / 收招 (`60 Hz` 样板帧) | 样板接触帧 | 结算 | 攻方 HP | 守方 HP | 停顿 / 击退 | 样板状态 & 原版可控录屏状态 |
| --- | --- | --- | --- | ---: | ---: | ---: | --- | --- |
| **1. 正常命中** | `0.00 m / 2.85 m` | `44 / 8 / 79`（`shogun_heavy.bytes` 推导） | `t60 = 49` (`f30 = 24.5`) | **1**（单段锁定） | `2900 -> 2900` | `2900 -> 2691`（`-209` **未确认占位**） | `10t` [**未确认**] / `+1.65 m` [**未确认**] | 样板单结算通过；**同条件原版普通重斩裸命中未确认** |
| **2. 空挥** | `0.00 m / 4.65 m` | `44 / 8 / 79` | 无接触 | **0** | `2900 -> 2900` | **`2900 -> 2900`** (`0`) | `0t` / `0.00 m` | 样板 0 扣血 0 受击特效通过；**原版空挥录屏未确认** |
| **3. 格挡** | `0.00 m / 2.85 m` | `44 / 8 / 79` | `t60 = 49` (`f30 = 24.5`) | **1**（单段锁定） | `2900 -> 2900` | `2900 -> 2774`（`-126` 参考移动 EV3，**基础装备比例未确认**） | `4t` [参考 EV3 录像帧] / `+1.28 m`（**原版 41f 滑移不破防**） | 样板与移动 EV3 不破防方向一致；**同平台基础装备数值未确认** |
| **4. 生效前打断** | `0.00 m / 1.35 m` | `24 / 0 / 0`（含边界 `43 / 0 / 0`） | 无有效命中 | **0** | `2900 -> 2815` (`-85`) | **`2900 -> 2900`** (`0`) | `0t` / `0.00 m` | 样板无延迟命中/无重复结算通过；**原版起手打断录屏未确认** |

---

## 四、自动化测试验证

- `swift test --filter DuelShogunHeavyPhase1Tests`：**6 / 6 通过，0 失败**（严格按普通重斩范围：单次结算、空挥 0 扣血 0 受击特效、格挡不破防+原版 41f 滑移、生效前打断含 tick 43 边界无延迟命中、全距 `1.60..4.00 m` 零重复结算）。
- 回归测试：`DuelShogunTests` **8 / 8 通过**（未破坏既有功能、未触碰 `main`、值班功能及另外三名角色）。


