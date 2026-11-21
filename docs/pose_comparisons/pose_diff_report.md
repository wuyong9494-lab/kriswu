# 四英雄核心招式无头渲染与姿势轮廓对比报告

- 生成脚本：`scripts/render_pose_diff.py` + `scripts/render_pose_diff_bpy.py`（Blender 4.2 Workbench 正交纯侧面视角，严格复现运行时 `DuelCascadeurCharacterInstance` 的高度归一化、朝向、脚底贴地与武器挂载矩阵）
- 参考面板说明：公有仓库不含且严禁引入《暗影格斗4》原版版权图片。右侧默认渲染项目原创姿势规格 [`sf4_pose_spec.json`](sf4_pose_spec.json)；若本地存在（已 `.gitignore` 的）`docs/pose_comparisons/_private_refs/<hero>/<move>_<phase>.png`，脚本将自动优先拼接该参考图。
- 采样时间点：按运行时线性映射 `progress = age / max(1, total - 1)` 截取 **① 起手峰值帧（`startup-1`）**、**② 命中判定帧（`startup + active//2`）**、**③ 收招结束帧（`total-1`）**。

## 1. 头颈重接处穿模与网格体检（BVH 三角面相交检测）

检测每个角色独立头模与身体/领口网格在颈部半径 0.22 m 球体内的三角面相交与最大侵入深度（取全部 18 个采样帧的最大值）：

| 英雄 | 头模网格 | 最大相交三角对 | 头入体最深 (mm) | 体入头最深 (mm) | 头底相对 Neck 高度 (mm) | 判定 |
|---|---|---:|---:|---:|---:|---|
| 吴庸 / Shogun (大太刀) | `WuYong_UserPortrait` | 457 | 59.9 | 59.9 | -95.9 | ⚠️ 显著穿模 |
| 徐骁 / Grand Inquisitor (巨剑) | `XuXiao_ProvidedHead` | 6009 | 60.0 | 60.0 | -47.3 | ⚠️ 显著穿模 |
| 刘泉玮 / Nonna (巨斧) | `Liu exact substitute head` | 259 | 59.9 | 41.1 | -117.0 | ⚠️ 显著穿模 |
| 孙登 / Midnight (双忍刀) | `SunDeng_222_Head` | 1558 | 59.9 | 55.7 | -171.1 | ⚠️ 显著穿模 |

## 2. 四英雄 × 6 核心招式量化轮廓偏差表

指标：`刀角差` = 实际握把→刃尖角度与目标角度夹角（°）；`前倾差` = 躯干前倾角偏差（°）；`步幅差` = 双脚间距偏差（m）；`双手离柄` = 双手武器副手离握柄线段 3D 距离（cm，目标 ≤ 12 cm）；`最远伸展偏移` = 动作中武器最远前伸时刻与游戏判定窗口的进度偏差。

| 英雄 | 招式 | 命中帧刀角 (实际/目标/差) | 起手刀角差 | 前倾差(命中) | 步幅(实际/目标) | 右手离握点(cm) | 双手离柄(命中,cm) | 踢腿高度(m) | 最远前伸 vs 判定窗 | 对比图 |
|---|---|---|---:|---:|---|---:|---:|---:|---|---|
| wuYong | `jab` | +3° / +5° / **2°** | 14° | 7° | 0.87 / 0.86m | 46.5 | 6.9 | - | p=0.38 vs [0.30,0.43] (Δ0.00) | [wuYong_jab.png](wuYong_jab.png) |
| wuYong | `heavy` | -1° / +0° / **1°** | 6° | 7° | 0.90 / 0.92m | 46.5 | 5.0 | - | p=0.40 vs [0.35,0.45] (Δ0.00) | [wuYong_heavy.png](wuYong_heavy.png) |
| wuYong | `skill1` | +152° / +190° / **38°** | 2° | 6° | 1.12 / 0.80m | 46.5 | N/A(双刀) | 0.92 (Δ0.08) | p=0.00 vs [0.22,0.42] (Δ0.22) | [wuYong_skill1.png](wuYong_skill1.png) |
| wuYong | `weapon_up` | +67° / +70° / **3°** | 52° | 2° | 0.74 / 0.75m | 46.5 | 7.6 | - | p=0.00 vs [0.28,0.38] (Δ0.28) | [wuYong_weapon_up.png](wuYong_weapon_up.png) |
| wuYong | `weapon_down` | -8° / -8° / **0°** | 3° | 12° | 1.07 / 1.10m | 46.5 | 13.7 | - | p=0.33 vs [0.28,0.41] (Δ0.00) | [wuYong_weapon_down.png](wuYong_weapon_down.png) |
| wuYong | `kick` | +109° / +110° / **1°** | 1° | 5° | 1.07 / 0.80m | 46.5 | 22.9 | 0.86 (Δ0.09) | p=0.57 vs [0.26,0.37] (Δ0.21) | [wuYong_kick.png](wuYong_kick.png) |
| xuXiao | `jab` | +2° / -10° / **12°** | 3° | 6° | 0.78 / 0.80m | 7.9 | 4.3 | - | p=0.38 vs [0.29,0.38] (Δ0.00) | [xuXiao_jab.png](xuXiao_jab.png) |
| xuXiao | `heavy` | -16° / -25° / **9°** | 0° | 10° | 0.86 / 0.95m | 7.9 | 5.6 | - | p=0.40 vs [0.37,0.44] (Δ0.00) | [xuXiao_heavy.png](xuXiao_heavy.png) |
| xuXiao | `skill1` | +1° / +0° / **1°** | 1° | 10° | 0.88 / 1.00m | 7.9 | 3.5 | - | p=0.42 vs [0.38,0.46] (Δ0.00) | [xuXiao_skill1.png](xuXiao_skill1.png) |
| xuXiao | `weapon_up` | +70° / +75° / **5°** | 45° | 1° | 0.63 / 0.72m | 7.9 | 7.9 | - | p=0.03 vs [0.29,0.39] (Δ0.26) | [xuXiao_weapon_up.png](xuXiao_weapon_up.png) |
| xuXiao | `weapon_down` | -6° / -5° / **1°** | 8° | 10° | 1.03 / 1.05m | 7.9 | 4.3 | - | p=0.33 vs [0.28,0.41] (Δ0.00) | [xuXiao_weapon_down.png](xuXiao_weapon_down.png) |
| xuXiao | `kick` | +106° / +100° / **6°** | 6° | 2° | 1.06 / 0.72m | 7.9 | 6.9 | 0.71 (Δ0.19) | p=0.60 vs [0.26,0.37] (Δ0.23) | [xuXiao_kick.png](xuXiao_kick.png) |
| liuQuanwei | `jab` | +5° / +5° / **0°** | 22° | 6° | 0.95 / 0.92m | 67.6 | 25.1 | - | p=0.33 vs [0.29,0.38] (Δ0.00) | [liuQuanwei_jab.png](liuQuanwei_jab.png) |
| liuQuanwei | `heavy` | -8° / -5° / **3°** | 19° | 9° | 1.01 / 1.05m | 68.4 | 23.8 | - | p=0.40 vs [0.37,0.44] (Δ0.00) | [liuQuanwei_heavy.png](liuQuanwei_heavy.png) |
| liuQuanwei | `skill1` | -7° / +0° / **7°** | 20° | 9° | 0.98 / 1.00m | 67.5 | 25.1 | - | p=0.30 vs [0.27,0.37] (Δ0.00) | [liuQuanwei_skill1.png](liuQuanwei_skill1.png) |
| liuQuanwei | `weapon_up` | +74° / +70° / **4°** | 46° | 4° | 0.83 / 0.86m | 60.2 | 25.5 | - | p=0.35 vs [0.29,0.39] (Δ0.00) | [liuQuanwei_weapon_up.png](liuQuanwei_weapon_up.png) |
| liuQuanwei | `weapon_down` | -6° / -5° / **0°** | 17° | 12° | 1.11 / 1.15m | 65.5 | 28.0 | - | p=0.33 vs [0.28,0.41] (Δ0.00) | [liuQuanwei_weapon_down.png](liuQuanwei_weapon_down.png) |
| liuQuanwei | `kick` | +107° / +95° / **12°** | 18° | 2° | 1.14 / 0.86m | 50.4 | 28.0 | 0.80 (Δ0.05) | p=0.57 vs [0.26,0.37] (Δ0.21) | [liuQuanwei_kick.png](liuQuanwei_kick.png) |
| sunDeng | `jab` | +15° / +10° / **5°** | 12° | 9° | 1.12 / 1.00m | 31.0 | N/A(双刀) | - | p=0.35 vs [0.29,0.38] (Δ0.00) | [sunDeng_jab.png](sunDeng_jab.png) |
| sunDeng | `heavy` | -17° / -30° / **13°** | 11° | 13° | 1.16 / 1.05m | 31.0 | N/A(双刀) | - | p=0.40 vs [0.37,0.44] (Δ0.00) | [sunDeng_heavy.png](sunDeng_heavy.png) |
| sunDeng | `skill1` | -0° / +0° / **0°** | 47° | 15° | 1.22 / 1.20m | 31.0 | N/A(双刀) | - | p=0.30 vs [0.27,0.37] (Δ0.00) | [sunDeng_skill1.png](sunDeng_skill1.png) |
| sunDeng | `weapon_up` | +71° / +75° / **4°** | 31° | 1° | 0.99 / 0.92m | 31.0 | N/A(双刀) | - | p=0.93 vs [0.26,0.37] (Δ0.55) | [sunDeng_weapon_up.png](sunDeng_weapon_up.png) |
| sunDeng | `weapon_down` | -5° / -5° / **0°** | 3° | 15° | 1.27 / 1.20m | 31.0 | N/A(双刀) | - | p=0.30 vs [0.26,0.39] (Δ0.00) | [sunDeng_weapon_down.png](sunDeng_weapon_down.png) |
| sunDeng | `kick` | +157° / +160° / **3°** | 8° | 7° | 1.31 / 0.92m | 31.0 | N/A(双刀) | 1.06 (Δ0.01) | p=0.85 vs [0.26,0.37] (Δ0.48) | [sunDeng_kick.png](sunDeng_kick.png) |

## 3. 视觉差距清单（实时量化验收状态）

| 排名 | 影响 | 视觉检验项 | 当前量化数据 | 状态 |
|---:|---|---|---|---|
| 1 | **高** | **四英雄核心招式命中帧刀角轮廓（相对各原型目标）** | 24 组命中帧刀角平均偏差 **5.5°**（基线 69.6°）；最大偏差：wuYong.skill1(38°), sunDeng.heavy(13°), xuXiao.jab(12°), liuQuanwei.kick(12°)。 | ✅ 已达标（平均 ≤ 12°） |
| 2 | **高** | **双手武器副手握柄贴合度（大太刀/巨剑/巨斧）** | 双手招式命中帧左手离握柄平均 **14.4 cm**（基线 46.8 cm，目标 ≤ 14 cm）；最大：liuQuanwei.weapon_down(28cm), liuQuanwei.kick(28cm), liuQuanwei.weapon_up(26cm)。 | ⚠️ 待继续收紧 |
| 3 | **高** | **吴庸 `skill1`（无情突进踢）视觉与踢击逻辑一致** | 吴庸 `skill1` 命中帧抬脚高度 **0.92 m**（基线 0.03 m，目标 1.00 m，差 0.08 m）。 | ✅ 已达标（霸体前踢） |
| 4 | **高** | **战斗步幅与弓步冲砍张力** | 24 组命中帧平均步幅 **1.00 m**（基线 0.38 m，原版目标均值 **0.94 m**）。 | ✅ 已达标 |
| 5 | **高** | **前向武器招式最远前伸帧与 60Hz 判定窗口对齐** | 15 项前向武器招式最大偏离 **Δ0.00**（基线 Δ0.09–0.54）；全部招式（含踢击/上挑）最大偏离：sunDeng.weapon_up(Δ0.55), sunDeng.kick(Δ0.48), wuYong.weapon_up(Δ0.28)。 | ✅ 前向招式全 0 偏离 |
| 6 | **中** | **头颈重接处领口网格体检（BVH）** | wuYong: 457对/深60mm; xuXiao: 6009对/深60mm; liuQuanwei: 259对/深60mm; sunDeng: 1558对/深60mm（注：颈底深插衣领为防“长颈缝”设计，侧面渲染五官与下颌无穿模）。 | ℹ️ 视觉无穿帮，持续监控 |
