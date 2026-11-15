# D15 六个悬浮剑出生与持有原始姿势

本批只使用已缓存的原始动作、模型和解码配置，交付六个独立出生状态、悬停与转向的姿势及事件收据。没有网络下载、重复解密、人体动作转换或原生运行。剑的独立可见特效和玩法状态机由各自接入批次继续完成；本收据不把原始姿势当成已经完成的跟随行为。

## 实际产物与来源

私有产物 `d15-sword-held-candidate-private.json` 为 909,838 bytes，SHA256 `22cf4bd31691a19adeaf92b10e745ca452c4f5d31ac390893a742527caf6b55e`，schema `original-d15-sword-held-poses-v1`。它含 8 个状态的原始骨骼矩阵、7 条常规 summon track、原始配置及 lock 1440、1441—1447、1449 的身份和完整相关事件。

复用七模型候选 SHA256 `870b6c27c3a8117f2d4e7e45b60c0c7d0c74dd16ddd129b43ab01e4d5b428cfc` 中已核对的原始剑动作：`d15_hovering_sword`，51 帧、5 个原始动画骨 ID、2 个数组，6,182 bytes，SHA256 `0705dac47e95dee7d66f39c8a2ede4e4774762aa241f79c08e64129119f36632`。原始配置为 `settings_sets_dynasty.bytes`，SHA256 `3d660f485ad5e238f23bf6dd19d16855635a9449fd213bf1dd468a9cc979f701`。

## 六个出生身份

所有出生状态使用 Parent.Nodes.pelvis → magic_joint_root 的 X/Z 对齐，朝向取 Parent pelvis → Front。Y 不增加父角色 pelvis 高度。表中的 Shift 是原配置厘米值；模型 FK 已包含原始 RIGHT 旋转，不能再将 Shift 做一次 RIGHT 反号。

现成 native method 39421 的末段只在执行模型方向为 LEFT=2 时反转 Shift.X，Y/Z 均直接加入目标坐标。转换到 Arena 米坐标应取 `[sourceX/100, sourceY/100, -sourceZ/100]`，运行时只有 X 乘 direction，Z 不随换边再翻转。由此 slot1/3 的 Z 始终为 +0.5 m、slot2/4 为 −0.5 m、slot5/6 为 +0.15 m；这是源位移规则，与已带 RIGHT 的骨骼姿势旋转不同。

| Record | 角色内独立 model role | Source alias 后缀 | Shift cm |
|---|---|---|---|
| 110 | `erlangSummon_swordBirth1` | `Birth_1` | `[-75,170,-50]` |
| 111 | `erlangSummon_swordBirth2` | `Birth_2` | `[-75,170,50]` |
| 112 | `erlangSummon_swordBirth3` | `Birth_3` | `[-75,195,-50]` |
| 113 | `erlangSummon_swordBirth4` | `Birth_4` | `[-75,195,50]` |
| 114 | `erlangSummon_swordBirth5` | `Birth_5` | `[-75,205,-15]` |
| 115 | `erlangSummon_swordBirth6` | `Birth_6` | `[-75,225,-15]` |

完整 alias 前缀均为 `D15_Hovering_Sword_Model_`。原声音 `set_d15/d15_swords_appear@Battle@Movement` 的 Frame 1 对应独立出生时钟 tick 2；每个出生实例只绑定自己的声音，不能把六组声音合并到攻击模型。

## 保留的生命周期合同

出生窗口为 FirstIndex 0、51 source frames、101 个 60 Hz 样本、AnimationEnd threshold 92。lock 1449 trigger 9 将出生组结束转到 `Idle`，此处不是 DeleteModel。切换动作时应保留同一个模型身份。

Record 117 `Idle` 原配置为 Looped，XYZ 对齐 Me.Pivot。Record 116 `Rotate` 为原始 1 帧、MidFrames 0、SelfEndFrame 0；仅输出 tick 0 的真实静态姿势，未给通用 track 校验器伪造第二帧。lock 1449 trigger 7 恢复出生时记录的高度；trigger 8 priority 403 清除转向标记，trigger 9 priority 402 随后进入 Idle。原生循环回卷时点和同 tick 的显示提交顺序不从 End threshold 猜测。

`D15_Sword_Check` 的 source frames 5/10/15/18/21/25/30/35/40/45/50 按 IntervalStart `(frame−1)×2` 对应 ticks 8/18/28/34/40/48/58/68/78/88/98。98 保留为完整源记录，不声称在出生 End92 前发生。持有跟随采用 lock 1449 中的检查和速度规则，不能仅靠原姿势自动推断。

Parent 的 `SET_D15_SWORD_ATTACK_START` VariableDestruction 由 trigger 10 进入原 Attack118；攻击中的 DeleteModel 是另一个 IntervalEnd tick70。出生和 Idle 的 track 都没有攻击/受击部位或删除事件。

## 本次验证

只运行新增三个 Python 定向检查。实际原始数组的独立厘米 FK 与导出八个状态在 source frames 0/23/50 的矩阵一致；Rotate 仅检查其唯一 source frame0。检查拒绝骨骼点篡改、交换六个 slot、混淆声音与 IntervalStart 时钟、把出生合并为 attack、把静态一帧扩为两帧、伪造出生删除和出生攻击部位。三个检查通过；没有重跑先前七模型或原生工作流。

可复现入口为 `scripts/prepare_erlang_sword_holds.py`，参数为已缓存的 `--settings`、`--model-candidate`、`--additional`、`--rules` 和新私有 `--output`。定向检查为 `scripts/test_erlang_sword_holds.py --candidate <本次候选> --motion <原始剑动作 bytes>`，使用已验证的 UnityPy 1.25.4 / NumPy 环境。所有媒体及含源内容的产物保留在私有目录，公共提交只有代码和本说明。
