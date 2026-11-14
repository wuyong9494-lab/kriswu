# 根缚受击：接通原始 Start → Loop → End

本批源码基线为 `54bfc94dfdaca4a9ea8325e661cf5304525601f8`。新增
`DuelTriadRootVictimState` 并接入实际 `DuelWeaponFight`，替换满足原动作身份门禁时
“通用 hit 姿态冻结直到计时清零”的路径。实现文件的实际 SHA-256 及执行记录见
[机器可读验证记录](acceptance/fighter-root-victim-20261115.json)。本地工作树摘要用于
归属这次改动，不把独立目录的临时 Git 快照当成 GitHub 源提交。

## 原始条件与时钟

已核对 `lock_1777.bytes`，SHA-256 为
`d0732e8ca62baf42f6125d24d1c347f9054ae7d0dc9ce163fc0a458b096944c6`。
动作设置来自 `settings_sets_heralds.bytes` records 102、103、104，其摘要为
`64bd77afa0edacdc7b672047222fb4261771f08b835367bc3aeeb5b02e668f5a`。

| 源分支 | 已确认条件 | 本次接入 |
| --- | --- | --- |
| trigger 0 | 合格 PostHit / `Hit_Root_Spike_H17_Start` 选择 Passive_Start | 沿用既有命中/控制资格，确认 root contact 后进入 Start |
| trigger 5 | Start 或 Loop 的 AnimationEnd，且 Enemy 的 `SET_H17_ROOT_ATTACK_DUR == 1` | 进入或重新进入 Loop |
| trigger 6 | 上述 AnimationEnd 或 Loop_Check IntervalEnd，且该变量不为 1 | 进入 End |
| trigger 0、4 | 被动段关闭 repulsion；Uninterrupt 结束及转段条件恢复 | 状态持有期间停止普通 body separation，完成或回合清理后恢复 |

**持续时间清零只是条件，不能当成立即进入 End 的事件。** 原 Loop_Check 区间为
1、25、45。native 39602 把正的 End 转为 `End − 1`，39191 在
`floor(position) > EndIndex` 时才派发 IntervalEnd，因此在默认 MidFrames=1 时，
这三个结束事件是 live tick **2、50、90**。Floorfall 使用 IntervalStart，原起点 20
对应零基采样 19，故在 **tick 38** 跨越。两个事件不能共用同一转换规则。

| 动作 | 原帧数 | 完整采样末 tick | AnimationEnd tick | 原 motion SHA-256 |
| --- | ---: | ---: | ---: | --- |
| `h17_root_spike_passive_start` | 44 | 86 | 78 | `69d01bc2d1cc6be69188be006582598bf3551c88db3f7446078fcda63583382c` |
| `h17_root_spike_passive_loop` | 61 | 120 | 112 | `a3f13059f3eeedd057e14d738894667a77b04279109d1544f0e2b34ad12502ce` |
| `h17_root_spike_passive_end` | 48 | 94 | 86 | `7d9b8572ae67cd8f344f16478cc50a56e17c0646191c7f2306ff2724453cf5e2` |

AnimationEnd 按已核查 native 39182 的 `EndIndex − floor(position) <= SelfEndFrame`
派发；这三段的 SelfEndFrame 缺省为 4。它与完整采样时长分开保存。源 lock 没有
End → getUp 的 AnimationEnd 动作，本实现保留 End 的完整 tick 94，再进入游戏既有
getUp role。这一步是明确的应用恢复策略，尚未恢复原游戏的全局 FOLLOWED_BY 派发器。

## 战斗中的实际变化

`applyTriadControl` 在已确认的源 H17 root contact 后，仅当目标具备三段完整原动作时
创建 victim state。状态绑定 sourceID 和施法席位；旧 root 的延迟释放不能解锁新 root。
门禁要求三段名称、原 SHA、帧数、两倍源时钟以及目标自己的完整 pelvis 轨道全部匹配。
这属于已认证 catalog 的能力核对，不能用调用者自行声明的 SHA 证明其媒体为原资源；
release loader 仍须独立验证 catalog、模型和音频实际字节。

每个实际 live tick 推进受击状态；hit-stop、暂停和回合间隙不推进。持续时间到期后，
受击者仍保持动作所有权，等下一个原检查点进入 End。受控输入不会缓存成解除后的
突然攻击。转段当步先发布旧段的边界样本，再发布新段 tick 0，既有音频 consumer 因而
能够看见正确的事件顺序；End tick 38 只产生一次跨越。

方向仅在 Start 按对手位置选定；后续转段保留方向，依据目标自己的 FK pelvis 对齐。
这里采用现有竞技场坐标与缩放约定，不声称所有源引擎 Pivot、根模型位置偏移和反应
优先级都已复原。普通伤害仍经过既有伤害流程，被动动作持有时不会被普通受击姿态
悄悄替换。回合结束与下一回合初始化清除状态及控制，避免复用旧 sourceID 或动作缓存。

## 双角色资源边界

Sun 现有已 pin GLB 已包含三原受击动画。Liu 原双锤参考 GLB 原先没有它们。
已核对三 motion 的 58 个 source bone IDs：Sun/Liu 的 sourceID → name → targetNode
均 58/58 完整，名称、父节点身份一致；**58 个骨骼的 rest TRS 全部不同**，所以不能
复制 Sun 的 FK、碰撞或 pelvis 轨道到 Liu。

本轮独立私有装配据 Liu 自己的 rig 重采样三段，保留其原 56 动作和旧 BIN、mesh、skin、
material、texture、accessor 等容器数据。装配回执记录 15 条原 hurt capsule、pelvis
及 58 骨骼 COM，新增 Liu GLB 摘要为
`a3aada76d336b9c4f9bda3904b5e947711d916f683a2dcbf7b8184377e01a517`。
它仍是 **`liu_hammers` 参考角色**；共享受击动作不建立独立盘古装备、专属技能或独占
动作已经完成的证据。资源组合、签名 pin 和受保护安装证据单独记录，不把候选装配
等同于模拟器或真机通过。

## 回放与最小回归

新增的每席 victim state 编入 canonical replay，含 sourceID、owner、motion、tick、
durationActive、originXMillimeters、direction。schema 7 → **8**、rules 11 → **12**。
即使可见 Loop pose 相同，持续变量状态不同也会产生不同的诊断字节。新 Swift 文件
自动进入现有源码 fingerprint glob；没有改动受占用的工作流或构建 helper。

执行分布如下，没有将失败或未运行的方法计为通过：

| 执行 | 结果 | 含义 |
| --- | --- | --- |
| 修复前定向 RED | 1 方法失败、2 个断言失败 | 确认 root contact 后错误地停在 `hammers_reaction`，时长 16 而非 Start 的 86 |
| 新 12 方法 + 4 个受 schema 变化影响的轻量 gate | 15 通过、1 失败、0 skipped | 唯一失败为镜像场景 310 wall-step 预算不足，End 当时已到 tick 88；真实 hit-stop 会暂停 live clock |
| 只复验该失败方法 | 1 通过、0 失败、0 skipped | 将预算改为 380，与已通过的完整链测试相同；生产代码未因该失败再改动 |
| 最终独立覆盖 | **16 方法已通过** | 12 个新 root 方法 + 4 个修改后的字段审计/字节 golden；不是声称单次 16/16 |

覆盖范围包括原始时钟、完整能力门禁、Start/Loop 循环、短 root 的等待、三个 IntervalEnd
及 AnimationEnd 释放点、陈旧 source/owner 拒绝、End 完整采样、暂停与输入清理、
两席镜像、转段 pelvis 连续性、回放一致、缺原动作时的明确兼容路径、KO/回合清理。
测试几何显式是人工 fixture，不把哈希标识误当作真实原动画数据。

## 最终组合资源的真实玩法执行

最终组合 release pin 为
`e5c0ccaeef85ce86c5b8fd4ee64524794d6556f5a561f4078362f6899bedf4e5`。
中间 audio-only / 首次组合候选均没有运行这次根缚 probe。最终版本 **只执行一次，
exit 0**：使用当前 release/audio loader，核对实际 catalog、两角色 GLB 的字节与自包含
容器、95 WAV、115 marker；同时核对 Morph owner/target 及 legacy trails 的目标摘要。
这些跨文件引用都指向当前实际 Liu GLB，不能留下旧模型摘要再宣称资源闭包成立。

probe 采用公开构造器默认位置 3500 / 6500。入场结束后，Sun 在第 395 wall step
通过中立方向的 shadow 输入释放一次 branches；当时源配置 mist 为 0、branches
mistCost 为 0，双方 HP 都是 1000。没有修改原 catalog、角色属性、HP 或内部状态。

| 实际观察 | wall step | live tick | 详细结果 |
| --- | ---: | ---: | --- |
| 确认 root contact，进入 Start | 459 | 459 | sourceID 2，持续 180 ticks，动作 tick 0 |
| Start → Loop | 549 | 537 | 78 个 live ticks，Loop tick 0 |
| 持续变量归零 | 659 | 639 | 仍是 Loop tick 102，不能立即恢复输入或跳到 End |
| Loop → End | 669 | 649 | 等待到 Loop AnimationEnd tick 112，额外 10 live ticks |
| Floorfall | 715 | 687 | End tick 37 → 38，显式 `liu_hammers` marker 恰好 1 次，绑定 7 原 PCM |
| End 完整末样本 | 771 | 743 | tick 93 → 94，恰好 1 次 |
| 进入现有 getUp | 772 | 744 | `m_str_stand_up_back_forward` tick 0，victim state 已清除 |

表中 live tick 来自 `triadPresentation.liveTick`，包含入场、排除 hit-stop，与
`sourcePresentationTick` 一致；不是声称私有 combat-only 时钟从入场前就运行。
全程 28 个 hit-stop wall steps，所有这些步都验证 state 不动且 source sample 队列
为空。结束时 HP 为 `[1000, 273]`，实际记录 8 个接触，未通过人工注入根缚或假动作
替代自然命中。结果摘要 SHA-256 为
`c967b4dab9a27153a23b8be4af3e6d2577e56e2291f0c10d5698de54e9ee22e9`。

Linux Foundation 适配仅替换 SHA 实现及 companion 元数据，不加载 SceneKit、不播放
声音。这个证据确认原资源字节与真实 Core 输入到已绑定音频 marker 的路径，尚不能
作为 GPU/骨骼视觉质量、音频可听输出或手机性能验收。新的 3 个 installed 测试已改为
最终 pin，检查 3 个角色归属明确的 Floorfall 区间、consumer 暂停/去重/重置及 WAV
解码；仅语法 parse 通过，Apple XCTest 执行数仍为 **0**。

模拟器画面/音频和 iPhone 17 Pro Max 视频/性能仍必须各自提供证据。历史
`ef306408…` 的 117 个原生方法没有重跑，亦不覆盖本批。
