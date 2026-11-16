# 蛇王 D13：独立技能模型与原始碰撞恢复

日期：2026-11-16。此记录只确认真实原始输入、模型几何、动作与碰撞数据的恢复。五个模型状态尚未因此注册为完整可玩角色；完整技能条件、伤害、目标时钟、粒子与原着色器由后续适配分别验收。

## 本轮实际完成

新增 `scripts/prepare_serpent_ability_models.py`，从已有本地原始 archive、原始 Unity bundle、已恢复的 BonesData / ModelObject XML 以及 iOS 原始配置生成五个独立模型状态。脚本不下载、不解密、不执行原版游戏，也不修改人物目录或候选发布门禁。

命名配置逐字段、逐类型逆投影回原始压缩配置，核验全部 19 条 D13 记录。模型触发锁重新由原始已解码 split 解析，保留六个触发字段和祖先条件路径，未把带条件的 CreateModel 当成无条件创建。

| 状态 | 源记录 | 原始模型 | 原始帧数 / 使用帧数 | 最后样本与 AnimationEnd tick | 有效攻击 tick |
| --- | ---: | --- | --- | ---: | --- |
| `serpentSummon_helmet` | 57 | `mgc__common_model_40` | 22 / 22 | 42 | 0–42 |
| `serpentSummon_bloom` | 62 | `mgc__common_model_40` | 31 / 6 | 10 | 0–10 |
| `serpentSummon_push` | 64 | `mgc__islander_push` | 11 / 11 | 20 | 0–20 |
| `serpentSummon_vine1` | 65 | `mgc__islander_root` | 88 / 88 | 174 | 8–149 |
| `serpentSummon_vine2` | 66 | `mgc__islander_root` | 92 / 92 | 182 | 8–149 |

五条配置的 `SelfEndFrame` 均为原始值 0。Bloom 的 `EndFrame=6` 是源配置裁剪，不能使用公共动作的全部 31 帧，也不能应用默认提前 4 帧结束。藤蔓攻击源帧 5–75 对应 inclusive tick 8–149，`IntervalEnd` 在 tick 150；它与模型销毁时间分别保留。源 `AnimationEnd` 删除路径分别来自 lock 1387、1382、1385、1386，藤蔓共用 1386/0/3。

## 模型与胶囊的真实边界

common40 和 push 是原生无网格的独立碰撞骨架。没有给它们添加可见占位形体。D13 配置和原始 CreateModel 明确引用这些模型，它们不是用别的角色替代的素材。

藤蔓原包具有两个真实蒙皮网格：`m__tentacle` 为 974 顶点、728 三角形；`m__tentacle_crystal` 为 112 顶点、160 三角形。合计 1,086 顶点、888 三角形，沿 `tentacle_1` 至 `tentacle_21` 原始 21 骨链播放两套动作。GLB 保留原始 SkinData 顺序、四槽权重、每个网格自己的原始逆绑定矩阵、原始材质与纹理来源。

| 状态 | 原始胶囊 | 源半径 cm | 导出半径 mm |
| --- | --- | ---: | ---: |
| helmet | `Common_Model_40_Attacking_Edge_HorBig` | 150 | 1,500 |
| bloom | `Common_Model_40_Attacking_Edge` | 40 | 400 |
| push | `Magic_Islander_Model_Push_Attacking_Edge` | 75 | 750 |
| vine1 / vine2 | `Magic_Islander_Root_Attacking_Edge_Tentacle_18/19/20` | 每个 7 | 每个 70 |

藤蔓 BonesData 中其余 17 个胶囊未被这两个动作的 `AttackingParts` 选中，作为未选部分列入回执，没有扩充攻击范围。头盔源胶囊半径 150 cm 也没有人为缩小。

## 坐标、出生位置与采样

轨迹使用真实源单位：1 源厘米转换为 0.01 米，并转换 Unity 的 Z 方向。轨迹采用 canonical source RIGHT 的 `Ry(pi)` 朝向，不包含人物 0.92 比例，也不包含人体视觉用的额外轴旋转。骨架 FK 只移除出生时 Align 指定轴的初始根坐标。碰撞轨迹另移除当前根 X 位移，接入方必须且只能加回一次。

`magic_joint_root` 仅用于 common40 / push。藤蔓实际锚点是 `tentacle_1`，没有把另一套骨架的根名套用进去。

| 状态 | 对齐目标与轴 | 原始出生 Shift | 朝向 |
| --- | --- | --- | --- |
| helmet | owner pelvis，X | X +160 cm，随 facing | 原 SetDirection 解出的 facing |
| bloom | enemy pelvis，X / Y | 无 | 强制 DirectionLeft |
| push | enemy pelvis，X / Y | 无 | 原 SetDirection 解出的 facing |
| vine1 | owner pelvis，X | X −250 cm，随 facing | 原 SetDirection 解出的 facing |
| vine2 | owner pelvis，X | X −175 cm，随 facing | 原 SetDirection 解出的 facing |

没有向任何模型额外加 pelvis Z，也没有向 helmet / vine 加 owner pelvis Y。left 对 canonical 局部坐标同时翻转 X 和 Z，Y 保持原值。

GLB 自身保留原模型空间，外层没有混入 RIGHT、Align 或人物缩放。它包含 `D13_Withering_Vine_1`、`D13_Withering_Vine_2` 两个动画，每个 42 个通道，分别 175 / 183 个 60 Hz 键。普通原始插值的半帧姿态直接作为键保存，避免把 30 Hz quaternion SLERP 当成已验证等价的源插值。验证覆盖每个 60 Hz 样本；样本之间的连续插值、原版慢动作第二数组调度和 native display-commit 顺序未据此宣称等价。

## 原始输入身份

| 输入 | SHA-256 |
| --- | --- |
| 原始动作与场景 archive，190,482,427 B | `f9a24c6f81c46b12facd670adff92d24f829a7811c298473ee51867262338959` |
| 原始 decoded splits，17,325,877 B | `02bcd31d5b0f3ed992ca1972f2c6da5f59e6495fe3880fec45f8b073fbaa0e7a` |
| D13 19 条命名动作配置 | `2ff1cca279a4db9bf772c27cd847102d6887e0363905b30616ad5ed54cd4357d` |
| `settings_sets_dynasty.bytes` | `3d660f485ad5e238f23bf6dd19d16855635a9449fd213bf1dd468a9cc979f701` |
| common40 bundle `3719ae2b78ab1968e0ffdb31081cb1c0.bin` | `85ee3665f55ea2d7517a9b17414e9806aa0a201782cf66eeb9bc6d725f916dc4` |
| push bundle `4658f30ed25625d417f2a7fd709d86f2.bin` | `4fda41f0830f715bead25647b673a2c2ad3d6b2740c19d9c7f456d834c3e1afc` |
| root bundle `50c9a6d2cebf72f31ac0bd048ab626e1.bin` | `88d06624994021869c9802237afda983168212b15169cf6df6a33499f8df5a53` |

各 XML、原始 TextAsset PathID、动作原始字节、bundle 以及配置的细分身份保存在私有 JSON / receipt。完整两份原始 motion arrays 都保留，当前轨迹明确使用普通播放的 array 0。配置来自用户提供的 iOS 1.46.1 所装载的 `1.46.0.16.16733-prod`，媒体来自已核验原始 archive；此处验证的是明确的源对象与配置绑定，没有声称两个原始客户端版本的完整 native 行为完全相同。

保留原始规则锁：1379、1382、1384、1385、1386、1387、1396。Bloom CreateModel 位于 1379/0/8；该触发的条件和后续清理顺序仍作为原始数据保存。

## 私有交付与检验

目录：`/workspace/scratch/31ccaa379696/work-products/serpent-abilities-models-v1`。

| 产物 | 字节 | SHA-256 |
| --- | ---: | --- |
| `d13-ability-models-private.json` | 2,018,820 | `61a1a5731b97ac6437161c07d6dc6a692c30a4f84e391ac78a2afc8ea1bb1f58` |
| `Serpent_D13_Withering_Vines.glb` | 567,544 | `2501b691696bdc22f358508ea298999acc3150436d83bc19c2dd42de29092121` |
| `readback-private.json` | 495 | `c7c2096e4f3af80b48d0f4428f39ee0a1f76d8682a2acfc8ff09c609ef3d4207` |
| `world-capsules-oracle-private.json` | 22,620 | `d7e2522b3223492e8d91a1a1e2af33b228a80b8031c1202bdf256540f00f13ea` |

独立读回先在源厘米空间重建 prefab FK，再转换坐标，校对全部 433 个模型 tick、7,893 个骨矩阵和 2,298 个胶囊端点。最大矩阵误差为 `8.76e-10`，最大端点误差为 `1.01e-9` 米。GLB 另外验证 7,518 个骨矩阵以及 388,788 个蒙皮顶点，最大位置误差 `1.12e-6` 米，低于 `2e-5` 米门槛。

给 Swift 的独立 oracle 有 38 个双向 / 时刻样例、78 个胶囊，覆盖各模型 tick 0、攻击开始、中点、攻击结束和最后样本（重合时去重）。owner pelvis 为 `(3.5, 1.1, 0.2)` 米，enemy pelvis 为 `(5.3, 1.2, -0.1)` 米。预期直接由原压缩数组、原 prefab 层级和 XML 端点计算，没有拿导出的 `collisionEdges` 自证。Bloom 的两种请求朝向都强制 DirectionLeft。

实际执行专属测试：

```sh
SERPENT_ABILITY_MODELS_DIR=/workspace/scratch/31ccaa379696/work-products/serpent-abilities-models-v1 \
PYTHONPATH=/workspace/scratch/612117c22e59/python_deps:scripts \
python -m unittest discover -s scripts -p test_serpent_ability_models.py -v
```

最终 7 项通过、0 失败、0 跳过，覆盖源数组 / FK / 骨架与胶囊、正确裁剪及 inclusive interval、实际双蒙皮读回、双向 world oracle、源摘要 / 半径 / 锚点 / 终止时刻 / 候选启用篡改拒绝。

## 后续适配尚需分别完成

这些模型数据可以供严格的 Swift binding 验证和技能碰撞适配使用。该脚本未改 `DuelWeaponFight`，未启用头盔 / 护甲动作，未处理目标独立 timescale，也未执行 native 或上传发布。

藤蔓源 `ForceGlow`、shadow-form / Morph / Alpha 外部纹理指针及材质属性保留在 GLB extras / 回执。便携材质预览不等于已恢复原版 Glow / shader；独立 `Chief_tentaclesStones_28` 等粒子效果也仍未绑定。本次产物始终标记 `sourceOnly=true`、`runtimeBound=false`、`customShaderParity=false`。
