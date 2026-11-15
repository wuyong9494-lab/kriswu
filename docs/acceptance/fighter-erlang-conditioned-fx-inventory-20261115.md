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

## 仍有明确模块或事件缺口

现已绑定的 Earth 15 / 19 另留两个 Stretch、一个原 Shape6 的空 Mesh PPtr、一个 Shape.alignToDirection；Meditation 8 / 9 留一个 Stretch；Eye 15 / 19 留四个 Stretch。高质量 Sword 17 / 20 的三层 Noise2 也未替换为直线粒子。

本库存另保留人体 TweenScale、Floor_Offset 及未绑定技能事件等各自证据范围，不能从 prefab 数量推导它们已经处理。实际 App / native GPU 显示与端到端验收应单独报告，离线身份、采样和语法检查不等于原客户端运行或 TestFlight 交付。

## 恢复说明

此文档内容是在工作目录中断后依据本轮已读原件和已有收据身份重建的工作材料；它不是原私有收据的替代品。恢复原件后应再核对应收据存在与身份，才将新资源候选纳入正式组包。余震两层尚未激活：原 ground_locator 的 world-difference → localPosition 链已确认，但 FME +0xc8 父变换尚未证明，不能从可移植 GLB 根倒推其原生 rotation / scale 恒等。

### 余震导出器的恢复批次

`scripts/prepare_erlang_aftershock_start.py` 只准备独立的 `D15_AftershockStart_Source.json.gz`，不生成 App 使用的 `SF3_D15_SkillEffects.json.gz`。输出强制保留 `runtimeBound=false`、`groundParentTransformVerified=false`，没有修改 App 白名单、World、中央资源身份或工作流。

它要求恢复后的原 D15 bundle、原 1454 规则、两个精确材料和两张纹理输入，检查原事件字段后才采样。两个活跃普通层保留原 Local 朝向、一次 burst、0.5 simulationSpeed 和曲线，以 100 live-tick 定时销毁窗口为边界；原关闭的根发射器不会被算成第三层。源控制器的 5 秒 duration 和原 Looped 参数另保留，未将其解释为粒子重播或本地附着。

恢复批次实际只执行了三项合成合同检查：原字段保持为未授权 runtime 的候选；拒绝把 Looped 改作 AttachToLocal；拒绝定时长度、销毁淡出、定时器身份或重复触发器的变化。命令为 `PYTHONPATH=<restored-dependencies>:scripts python3 -m unittest test_erlang_aftershock_start_contract -v`，Python 3，3 项通过（0.001 秒）。这些 fixture 是重建字段合同，不是原始规则收据。

原件重新导出、原材质/粒子采样检查、App 接入和 Apple GPU 验证尚未在此恢复批次执行。尚未核实的 parent 变换不能通过这三项检查获得“已还原”状态。
