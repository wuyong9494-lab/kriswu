# 二郎神七个独立模型：原始轨迹与碰撞接入

本批把六个基础技能模型及斧击后震转换为可供 `DuelSummonMotionTrack` 使用的真实轨迹，同时导出独立小骨架的逐 tick 世界矩阵。它们使用源 `CreateModel` 指定的 common40、UrsusLight、dual swords 模型；不并入人体动作，不制造可见替代模型。这些模型的可见粒子、剑体和光束需由独立 D15 FX 接入消费同一时钟。

## 动作、裁剪与终止事件

全部动作 `FirstIndex=0`，缺省 `MidFrames=1`，普通播放每个源帧有两个 60 Hz 采样。完整采样、`AnimationEnd` 与另行派发的删除事件分别保存。

| 源记录 | runtime role | 原动作 | 原帧 → 导出帧 | 完整末 tick | AnimationEnd | 另行删除 |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| 100 | `erlangSummon_stomp` | `common_model_40_attack` | 31 → 10 | 18 | 18 | — |
| 103 | `erlangSummon_earth` | `s_agl_helm_bullet` | 68 → 16 | 30 | 22 | — |
| 105 | `erlangSummon_eye` | `d15_avatara_laser_model` | 71 → 66 | 130 | 122 | — |
| 106 | `erlangSummon_meditation` | `common_model_40_attack` | 31 → 31 | 60 | 52 | — |
| 118 | `erlangSummon_sword` | `d15_hovering_sword` | 51 → 51 | 100 | 92 | 70 |
| 128 | `erlangSummon_judgement` | `d15_avatara_ult_swords_model` | 92 → 33 | 64 | 64 | — |
| 132 | `erlangSummon_aftershock` | `s_agl_helm_bullet` | 68 → 68 | 134 | 126 | — |

100、128 的源 `SelfEndFrame=0`；其余缺省为 4。依据已核查 native 39182，`EndIndex − floor(position) <= SelfEndFrame` 派发动画结束。

飞剑源 lock 1449 trigger 12 在 `D15_Sword_Destroy` 的 `IntervalEnd` 执行 `DeleteModel`。该区间 End=35。native 39602 将正 End 转为 End−1，39191 要到 `floor(position) > EndIndex` 才派发 IntervalEnd，所以删除 tick 为 70。不能把 `sourceEndEventTick=92` 改成 70；轨迹另外提供 `sourceDeleteEventTick=70`。既有 arena 适配保留终止 tick 样本，下一 live tick 移除；本批不宣称这等同原引擎同 tick 的显示提交顺序。

攻击保留原始区间和有效存活区间。眼部光束源配置有 22 个 Attack 区间，末区间起于 tick 126，已晚于源 AnimationEnd 122，因此该区间保留原记录，`effective=null`，不擅自延长模型寿命。

## 原始碰撞及坐标

| 模型 | 原攻击 part | 原半径 |
| --- | --- | ---: |
| stomp | `Common_Model_40_Attacking_Edge_Big` | 1600 mm |
| earth / aftershock | `Ursus_attacking_edge_horizontal` | 100 mm |
| eye | `Magic_attacking_edge_4` | 50 mm |
| meditation | `Common_Model_40_Attacking_Edge_Huge` | 2250 mm |
| sword | `Shadow_attacking_edge_D15` | 30 mm |
| judgement | `Magic_attacking_edge_5` | 400 mm |

Ursus 的水平胶囊长 42 m，原 Align Shift.X 为 2000 cm，即 20 m；两项都原样导出。冥想半径 2250 mm 也不压缩到旧通用校验上限 2000 mm。接入方需对已审 role、part、精确半径做最小允许，其余校验保持严格。

转换先按真实 prefab 父子关系、声明的 BonesData ID 及源位置/四元数计算 FK，再做厘米到米、Unity Z 反射和源 RIGHT 的 Ry(π)。没有套用人体 0.92 缩放或 −90° 展示旋转。初始 Align 只移除声明的坐标轴，保留之后运动。胶囊 X 移除当前根位移，Core 使用当前和前一 tick 各自的 `offsetX` 加回一次，渲染消费同一源矩阵。

Ursus 的源 motion 含 13、31，但其 BonesData 只声明 400…404；未声明的两个通道被记录并排除，不猜接人体骨。dual swords 的所需 D15 part 使用真实声明的 `weapon_r`，未被该 motion 动画化的骨保持原 prefab rest transform。该 XML 中无关的重复旧 part 和未解析装备顶点不参与所选 D15 part；选择过程拒绝所选 part 自身缺失或重名。

## 可核查输出

私有候选 `d15-model-tracks-candidate-private.json`：653,960 bytes，SHA-256：

`870b6c27c3a8117f2d4e7e45b60c0c7d0c74dd16ddd129b43ab01e4d5b428cfc`

该文件包含 `summonTracks`、每模型源骨矩阵、原 Attack 区间与有效窗、Align/SetDirection、Sounds，以及源 CreateModel 和删除 trigger 的摘要与完整相关记录。五个独立原始 motion bytes 同目录保留；没有原始媒体进入公开 git。

关键来源摘要：

- 具名配置 `erlang-animation-named-private.json`：`030ca65a96c38e1c335507c2d17c9570716e29510f85305a8e4d905fc179beaa`；原 `settings_sets_dynasty.bytes`：`3d660f485ad5e238f23bf6dd19d16855635a9449fd213bf1dd468a9cc979f701`。
- 完整 motion catalog：`09829af10b6691124853335a3b8a2821a53c771ffeb4ec0bac97ad8eb6c6fee8`；完整 Android bundle catalog：`2c01276ca8c58ea32d79bfe481e37adc6696bc4c5a6140f6f6842ca262d07055`。
- common40 BonesData：`27902c22151fa33d2bc45b163bb9d4ca106f4c934a36013eb31bb37a35dbfbd7`。
- UrsusLight BonesData：`f413e98e29154fc9e5d81d6affe595d510e9f6a0f7f483dfb6d4fb47c4470276`。
- dual swords BonesData：`1c95bf3e07766302cf8eccdf207cb4b7bb02d89bd39fd702540f62c9ce5be0e4`。

所有本批输入均复用已恢复文件和原始来源归档中的精确成员，无下载、客户端执行或密钥读取。

## 实际验证及接入边界

仅运行 5 个新增专项检查，0 失败，0.373 s。实际候选独立读回覆盖 7 模型、2917 个骨矩阵采样、1086 个胶囊端点；最大矩阵误差 `8.2770e−10 m`，最大端点误差 `1.6000e−8 m`。负例拒绝胶囊坐标篡改、把飞剑 AnimationEnd 错写为删除 tick、所选 part 重名、越界裁剪与未经支持的镜像/插帧设置。解析原 catalog 初次构建因将 `file` 键误写为 `bundle` 而在产物前失败；修正后实际构建成功，该失败不是行为回归红测。

命令为：

```sh
ERLANG_MODEL_CANDIDATE="$PRIVATE_CANDIDATE/d15-model-tracks-candidate-private.json" \
PYTHONPATH="$MOTION_PYTHON" \
python3 -m unittest discover -s scripts -p test_erlang_model_tracks.py -v
```

实际日志：`erlang-model-tracks-build-final-20261115.log`、`erlang-model-tracks-checks-20261115.log`。没有重跑旧全套、Swift/native build 或原已过的犬转换。

伤害归一化、106 的动态 BaseDamage、释放条件及源 actor origin 由战斗 adapter 根据本批源记录接入；这里不填假固定伤害。声音 Frame 也不套动画的一基帧规则：已审音频约定是 Frame1→tick2。六个 hovering sword 出生动作与射击动作保持不同事件，不在每次射击时误播六次出生音。最终人体 GLB 身份变更后，应统一重新绑定 companion、FX 和 audio manifest。
