# D15 条件化特效库存（2026-11-15）

## 范围与证据

本表区分“原 prefab 文件存在”“在所选等级、质量和外观条件下被原规则直接请求”以及“已经接入当前 App 的具体事件路径”。它不是完成百分比；同一文件可以有一条已接入事件和另一条未接入事件。

本次库存基于已恢复的 D15 原始锁、29 个 prefab 及实际候选。条件化私有索引为 `erlang-d15-conditioned-visual-inventory-20261115-private.json`，205,361 B，SHA-256 `dadb3a4c92ae31d23983832e63b09d526cf40300f95e3571516fb89fece861d0`。原始文件库存为 57,381 B，SHA-256 `71d2d74ce945e6457b05f83b82e3b722e8c0cbaafd66d17cf451fd74f7c343bf`。这些收据保留原事件、条件、优先级、目标和完整动作字段。

实际当前配置为默认等级 8，基底外观、普通非镜像动作与高质量飞剑路径。候选 profile 为 `bafb288e94495d492a90523f67f963d85e75fb7f49adf7014bb64883bbf57c47`，62 个人体 clip、15 条模型轨迹。未绑定的 Wave 模型不能由已有普通 Earth 模型代替。

7 个文件已有某些绑定；16 个文件由所选主路径直接引用而仍未绑定；1 个为镜像天眼变体；1 个为低/中质量飞剑替代；4 个在本批已恢复锁中未找到直接 a46，间接用途仍未知。上述分类不能把全部“未绑定文件”相加后称为同一时刻必需的活跃特效，也不能将条件替代或未找到直接引用的文件称为无用。

## 原文件与事件路径

表中的名称保留可识别的 prefab stem；触发器写作“锁 / trigger”。已绑定数字是活跃发射器范围，不代表整个技能的所有视觉事件。

| Prefab stem | 当前绑定 | 原直接引用与条件 |
| --- | --- | --- |
| dog_smoke | 3 / 3 | 1433 / 1，犬模型 Hide |
| dog_smoke_startend | 6 / 6 | 1433 / 1、2，犬模型 Hide / End |
| big_leg | 3 / 3 | 1434 / 1，大脚模型 Initialize |
| floorattack | 15 / 19 | 1432 / 66，Spear_Ground_Shake_Model_Creation |
| laser(head) | 15 / 19 | 1432 / 53，普通天眼头部 |
| sword_jian_glow | 17 / 20 | 1447 / 1、3，高质量飞剑 |
| avatar_start_explos(chest) | 8 / 9，仅一条路径 | 1438 / 1 的冥想模型 Initialize 已接；1450 / 7 的 Level 4 角色 D15_Explosion_FX 未接 |
| axe_earthquake_explosion_start(ground_locator) | 0 / 2 | 1454 / 43，Level 6 Ground_FX 前段；正准备独立接入 |
| axe_earthquake_explosion(ground_locator) | 0 / 14 | 1454 / 45，AFTERSHOCK_FX_TIMER 结束后第二段 |
| avatar(chest) | 0 / 5 | 1432 / 2、5、30 |
| avatar_start_explos_small | 0 / 5 | 1432 / 28；1454 / 59、61 的回到形态 1 路径仍可引用 |
| axe_groundcracksexplos | 0 / 32 | 1432 / 59 |
| axe_light | 0 / 15 | 1432 / 57 |
| bigleg_groundcracksexplos | 0 / 28 | 1434 / 3 |
| bigleg_step_explos | 0 / 11 | 1432 / 47 |
| laser_ground | 0 / 19 | 1432 / 51、53，镜像与普通路径均有独立地面部分 |
| meditation | 0 / 18 | 1437 / 1、16 |
| spear_glow | 0 / 8 | 1432 / 64 |
| sword_model_down | 0 / 13 | 1464 / 0、1，独立左右 Wave 模型，各有 4 个平移实例 |
| ulta_1 | 0 / 26 | 1454 / 7 |
| ulta_2 | 0 / 16 | 1454 / 5 |
| ulta_gipnose_headglow | 0 / 5 | 1454 / 3，owner head |
| ulta_gipnose_headglow_passive | 0 / 4 | 1454 / 3，enemy head |
| laser(head)_mrr | 0 / 19，镜像替代 | 1432 / 51；当前普通天眼路径不伪装成此分支 |
| sword_model | 0 / 2，质量替代 | 1447 / 0、2，min / low / medium 条件；不能与高质量 glow 同时无条件叠加 |
| hovering | 0 / 4，间接用途未知 | 本批锁中无直接 a46 |
| spear_explosion | 0 / 16，间接用途未知 | 本批锁中无直接 a46 |
| ulta_1_groundcollision | 0 / 0，间接用途未知 | 本批锁中无直接 a46；没有活跃粒子不等于整个 prefab 无用 |
| white_screen | 0 / 1，间接用途未知 | 本批锁中无直接 a46 |

### 必须保留的条件差别

- 原基底动作通常要求 `Not(And(f239 四装备槽 == 101741))`，对应重纹理外观另有替代触发器；当前转换只覆盖明确的基底原件，未实现通用 f239 外观选择器。
- `sword_model_down` 是 Wave 模型效果，不能作为低质量飞剑文件的别名。当前 15 条模型轨迹不包含原 Wave 左右 1–4 的释放路径。
- 大爆炸文件在 1438 / 1 已接入，并不证明 1450 / 7 也已接入；后者是不同的原事件与目标。
- 小爆炸的一个基础条件排除 Level 4，但 Level 6 的 1454 / 59、61 仍可请求它，不能据基础分支将整个文件从 Level 8 范围删去。
- 普通天眼 1432 / 53 同样请求独立地面 prefab；镜像分支未选择不能解释普通地面部分的缺失。
- 高质量飞剑 glow 与 min / low / medium 的 sword_model 原条件互补。未绑定替代分支不代表主路径没有视觉，也不代表替代永远不需要。

## 七个有符号 Stretch 层保持未绑定

原始 renderer 参数快照为 `erlang-skill-stretched-inventory-20261115-private.json`，282,642 B，SHA-256 `ae5d7d14d4548d5dc30079581a2f75ab0e80f19783c26e1867c88ea723d76ffa`。七层中六层存在负 lengthScale 或 velocityScale，不能取绝对值后宣称保持了原几何。

| 原 ParticleSystem pathID | lengthScale | velocityScale | 其他必须保留的差别 |
| --- | ---: | ---: | --- |
| 3678594313255446982 | -200 | -0.10000000149 | Eye，pivot / flip 为 0 |
| -1551466144542758458 | -200 | -0.10000000149 | Eye，pivot / flip 为 0 |
| 8242420645739293126 | -200 | -0.10000000149 | Eye，pivot / flip 为 0 |
| -6744143991670249018 | -200 | -0.10000000149 | Eye，pivot / flip 为 0 |
| 226975819404105122 | 2 | 0.01999999955 | Earth，pivotY 4.13000011444，世界空间 VelocityModule |
| 8193636258807174562 | -7 | 0.009999999776 | Earth，pivotY -0.1099999994，alignment 4、sort 1 |
| 2022811022957143107 | 1.5 | -0.009999999776 | Meditation，pivotY -0.07、flipX 1 |

七层均为 cameraVelocityScale 0、freeform false、rotateWithStretch true。官方文档给出各参数的用途，但没有给出这个原版本在负值、pivot、flip 和旋转组合下的完整顶点公式；公开 C# 绑定将几何处理交给 native。已有 managed getter 不能证明 native 几何结果。

当前独立 Skill 白名单仍拒绝这些层，不调用旧通用采样器的绝对值拉伸公式。未改旧 H17 行为。下一步须先获得足够的公式或目标版本结果证据，再实现受限适配；本批不把纹理存在当作几何已还原。

## 恢复原件重新读回：飞剑三层不只缺 Noise

随后从恢复的完整 `4f9476ea1326d7c102950a772ee44020.bin` 重新定点读取三个 ParticleSystem 和各自的 renderer。原包为 2,561,715 B，SHA-256 `971b3a1ea36eaaebaea4ae73a56ed65d8ffc4383625a06d64a209d8a70fbbd90`。新的[公开参数与身份回执](fighter-erlang-sword-noise-stretch-readback-20261115.json)只保存选定参数、对象 ID 和实际 raw SHA，不包含资源正文、shader 程序、纹理或私有下载地址；它不是已丢失旧收据的重建替身。

| 原 ParticleSystem pathID | 对应 renderer pathID | 原模拟空间 / 循环 | Clamp dampen |
| --- | --- | --- | ---: |
| 148819201852362057 | 8946964618604105033 | local（0），不循环，duration 约 0.3 秒 | 0.01999999955 |
| -7290008168018162359 | -3844928422825112247 | local（0），循环，duration 1 秒 | 0.009999999776 |
| 4799608978381983049 | 8981488520721911113 | world（1），循环，duration 1 秒 | 0.009999999776 |

三层同时具备以下原始配置：

- renderer `m_RenderMode=1`（Stretch）、`lengthScale=-1.5`、`velocityScale=-0.009999999776`、`pivotZ=0.85000002384`、`flipX=0.5`、alignment 2。cameraVelocityScale 为 0，freeform 为 false，rotateWithStretchDirection 为 true。加上前述七个 Skill 层，目前这组缺口实际涉及十个 Stretch renderer。
- `NoiseModule`、`VelocityModule`、`ClampVelocityModule` 均启用。Noise 的原 quality 整数为 1、frequency 约 0.03、damping 为 true、octaves 为 1、scroll 为 0、positionAmount 为 1，rotationAmount / sizeAmount 为 0；这些参数不等于已取得原 Noise 算法或随机种子映射。
- Velocity 的线性 XYZ 为 0，但 orbitalZ 的原范围为 -6 到 6；Clamp 的 magnitude 为 1、drag 为 0，dampen 如上表。因此不能将它们描述成“不需要速度处理”的粒子。现有通用采样器已有 Velocity / Clamp 分支，但尚未证明它与这三层 Noise 的原生组合顺序和结果一致。

第三层还必须保留世界空间粒子的实际出生历史，不能把已出生粒子逐帧重新附着到当前剑模型位置。三层共同引用的材料为 fileID 1 / pathID `-3539672900455825089`，不在当前 Sword `MATERIALS` 表中；本次只核到原引用，未把其 shader / 纹理闭合记为完成。

因此，单独补一个 Noise 函数不能把飞剑从 17 / 20 提升为完整。最小后续依赖是有符号 Stretch 顶点规则、原 Noise 与速度 / 限速的组合规则，以及世界空间出生历史和精确材料输入。现有 omission 标签 `unbound_original_noise_module` 只是当前拒绝入口，不是全部缺口清单。本批只修正文档和保存回执，没有改运行时、采样算法或验收门槛，也没有新增 GPU / 原客户端执行结果。

解析使用 UnityPy 1.25.4，实际出现 `6000.3.11f1` fallback 警告；这个读取器版本回退值不作为原 Unity 引擎版本的证明。

## 仍有明确模块或事件缺口

现已绑定的 Earth 15 / 19 另留两个 Stretch、一个原 Shape6 的空 Mesh PPtr、一个 Shape.alignToDirection；Meditation 8 / 9 留一个 Stretch；Eye 15 / 19 留四个 Stretch。高质量 Sword 17 / 20 的三层同时含 Noise、Stretch 与 Velocity / Clamp，仍保持未绑定，未替换为直线粒子。

本库存另保留人体 TweenScale、Floor_Offset 及未绑定技能事件等各自证据范围，不能从 prefab 数量推导它们已经处理。实际 App / native GPU 显示与端到端验收应单独报告，离线身份、采样和语法检查不等于原客户端运行或 TestFlight 交付。

## 恢复说明

此文档内容是在工作目录中断后依据本轮已读原件和已有收据身份重建的工作材料；它不是原私有收据的替代品。恢复原件后应再核对应收据存在与身份，才将新资源候选纳入正式组包。余震两层尚未激活：原 ground_locator 的 world-difference → localPosition 链已确认，但 FME +0xc8 父变换尚未证明，不能从可移植 GLB 根倒推其原生 rotation / scale 恒等。

### 余震导出器的恢复批次

`scripts/prepare_erlang_aftershock_start.py` 只准备独立的 `D15_AftershockStart_Source.json.gz`，不生成 App 使用的 `SF3_D15_SkillEffects.json.gz`。输出强制保留 `runtimeBound=false`、`groundParentTransformVerified=false`，没有修改 App 白名单、World、中央资源身份或工作流。

它要求恢复后的原 D15 bundle、原 1454 规则、两个精确材料和两张纹理输入，检查原事件字段后才采样。两个活跃普通层保留原 Local 朝向、一次 burst、0.5 simulationSpeed 和曲线，以 100 live-tick 定时销毁窗口为边界；原关闭的根发射器不会被算成第三层。源控制器的 5 秒 duration 和原 Looped 参数另保留，未将其解释为粒子重播或本地附着。

恢复批次实际只执行了三项合成合同检查：原字段保持为未授权 runtime 的候选；拒绝把 Looped 改作 AttachToLocal；拒绝定时长度、销毁淡出、定时器身份或重复触发器的变化。命令为 `PYTHONPATH=<restored-dependencies>:scripts python3 -m unittest test_erlang_aftershock_start_contract -v`，Python 3，3 项通过（0.001 秒）。这些 fixture 是重建字段合同，不是原始规则收据。

原件重新导出、原材质/粒子采样检查、App 接入和 Apple GPU 验证尚未在此恢复批次执行。尚未核实的 parent 变换不能通过这三项检查获得“已还原”状态。

### 随后的原件恢复与实际采样

在上述准备提交之后，已从原始 SHA / CRC 匹配的 D15、FF 材料、两个共享纹理 bundle 和 Android `globalgamemanagers` 完成一次新的离线读取。以下是重新取得的原始证据，不是重建 fixture：

| 项目 | 新的实际结果 |
| --- | --- |
| 粒子与材料 | 两个活跃 ParticleSystem、两个对应 renderer 和两个原 Material 的 raw SHA 均匹配既有 pin；根 ParticleSystem 的 emission 与 renderer 确实关闭。原材质的精确 shader variant 已提取并经现有转换器生成程序，未声称 GPU 验证。 |
| 外部纹理 | `glow_01_90` 原 Texture2D `5044707271281776510` 为 128 × 128、格式 47、1 mip；`Glow_Rec` 原 Texture2D `482803268541587901` 为 128 × 128、格式 45、8 mips。两个对象 raw SHA、原压缩 mip 字节长度、实际解码 PNG 均有新收据；没有替换为生成图片。 |
| 原项目参数 | Android 成员 SHA 保持 `1ddbe17aab3a2997a1913e122eb9099da5ed17b94aff84fecd288914fecb2e0f`。PhysicsManager 与 QualitySettings 完整 typetree 读取通过，分别保留原重力 `[0, -981, 0]` 和所选各向异性模式 0。 |
| 原色彩空间 | PlayerSettings raw SHA 保持 `5fe9e533c9b17a8cafe0aa25387a6a6ff738641b27d5334ff117e276cc293cb9`。只按原字段顺序读取前缀中的 `m_ActiveColorSpace`，其字节偏移 256–259 为整数 0；完整对象解析仍未通过，未伪报完整读取。 |
| 局部粒子采样 | 两个原 Local 层均实际产生候选。每层在 60 Hz、100 tick 的准备窗口内先采 101 点，经现有线性约简合计保留 4 个端点；保留原 3 秒 / 约 3.6 秒完整寿命作为曲线归一化分母，没有把裁切窗口重标成完整寿命。原位置、原旋转、原尺寸和两个原材质保持独立。 |

该实际候选的文件名是 `D15_AftershockParticles_PendingRules.json.gz`，4,585 bytes，SHA-256 `92b393ff45ec76b6869ed6572a3b41250ce970621aaeda67494d0bda2eea0e86`，解码 13,870 bytes，包含两个轨迹、两个材质和 10 个派生依赖文件。它明确保留 `sourceRulesReverified=false`、`runtimeBound=false`、`groundParentTransformVerified=false`，不会进入正式 Skill manifest。新的纹理 / 项目参数收据为 4,078 bytes，SHA-256 `109d9dac2c5e67d28039fdda90ac58f00cebd63d19c799c85961b667540e0fe1`。

恢复过程保留了两次真实失败：初次 JSON 写入未处理 Unity typetree 的二进制字段；随后 UnityPy 1.25.4 的 PlayerSettings 全部字段解析只消耗 952 / 956 bytes。前者改为保留二进制原件和独立摘要；后者只恢复现有适配器实际使用的、已由原对象 pin 约束的色彩空间字段，并明确 `completeTypeTreeRead=false`。Physics / Quality 的完整读取门槛与既有 H17 / D15 原件 pin 均未放宽。这两次失败不是通过的测试。

原 1454 规则的准确恢复入口也已重新取得：IPA `resources.assets` 的 TextAsset `565`（`archive`）内部含两份原 `1.46.0.16.16733-prod*.zip.enc`，加密成员 SHA 与公开旧收据逐一相同。规则需要此前已核实的明文 splits ZIP，再从 `splits/split_battle_triggers.bytes` 中读取 `lock_1454.bytes`；动作标记来自同一 splits 的 `settings_sets_dynasty.bytes`、record 101 `D15_Avatara_Axe`。目前没有把重建的三条触发器替代这些原始规则。

原生 parent 的新定点证据已证明 FME `+0xc8` 来自新建独立 GameObject 所加组件的 Transform，而非原 Armature / pelvis Transform。其初始化链只见位置赋值；后续整个生命周期的 rotation / scale 是否仍恒等尚未闭合。因此这次恢复仍没有添加 ground_locator 的运行时附着，也没有新增 App、GPU 或 TestFlight 验收声明。

## 原规则恢复后的余震源导出

随后已从用户提供的原 IPA 定点恢复两个原配置归档。恢复的 splits 明文为 17,325,877 bytes，SHA-256 `02bcd31d5b0f3ed992ca1972f2c6da5f59e6495fe3880fec45f8b073fbaa0e7a`；prod 明文为 2,751,235 bytes，SHA-256 `165f5b1483909c461fabc86c591efd01ebb4915cc34ef7bf2579d52c94b35950`。二者均命中此前完整明文身份，4 和 1,617 个 ZIP 条目分别通过全部 CRC。解码参数仅在内存中使用，公开仓库不包含参数值或原配置媒体。

这次读取 `splits/split_battle_triggers.bytes` 内的 `lock_1454.bytes`（35,276 bytes，SHA-256 `0bf4ae016ff582b8dc8e4753cd94aca3cd98027c03151820b575dff2b83d605d`），以及 `splits/split_animation_settings.bytes` 内的 `settings_sets_dynasty.bytes`（334,225 bytes，SHA-256 `3d660f485ad5e238f23bf6dd19d16855635a9449fd213bf1dd468a9cc979f701`）。固定源版本的 typed-storage 读取器检查全部字节和引用，保留 1454 的 64 个完整触发器及动作配置记录 101。

原件确认 `D15_Ground_FX` 为 `D15_Avatara_Axe` 的 source frames 36…50。1454 t42 启动 100 tick 定时器；t43 的普通外观分支创建 start 效果；t45 在定时器结束且 `RoundFightStart` 条件成立时销毁它，并启动另一独立爆炸。四个装备槽全部满足原外观值 101741 时使用 t44/t46 的 retext 分支。完整条件保留在源导出中，未把两套外观或后续爆炸合成同一效果。

`prepare_erlang_aftershock_start.py` 现在精确锁定重新读取的完整 compact 规则 JSON（77,609 bytes，SHA-256 `dcc66cdc27d5bf448a41593f6fddd3b569d3248f52855b04c12ee5b9e2e71ccb`），覆盖原事件、动作、服装条件与回合条件。两个新的轻量检查实际通过：原规则与已导出 lifecycle 完全一致；保留相同事件和动作、仅删除服装条件的改写被拒绝。此前已通过的检查未重跑。

新的实际源导出 `D15_AftershockStart_Source.json.gz` 为 3,612 bytes，SHA-256 `33930d1e1ed3721e0aadafb50773b96feb6e56e2b78e4a4d3216f2b80d65ed83`，包含两条原始粒子轨迹、两份原材质和完整已核实 lifecycle。源收据 `aftershock-start-source-receipt-private.json` 为 9,028 bytes，SHA-256 `7989f776bd35b1df53e90934f9c3afa2d0a42caa3c302213c49f0ed642e2e270`。

该产物继续保留 `sourceOnly=true`、`runtimeBound=false`、`groundParentTransformVerified=false`。已证明 ground locator 的父级来自新建运行时 GameObject；其完整生命周期的旋转、缩放与附着语义尚未闭合，因此本次没有更改 App renderer、生产资源开关或正式 Skill manifest，也没有原生画面验证。
