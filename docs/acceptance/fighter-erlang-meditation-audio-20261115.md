# 二郎神冥想原声事件与 62 段动作音频绑定

本批把已经恢复的 `d15_meditation` 原声接到真实源事件，并将既有 75 段 PCM、98 组配置声音标记绑定到完整 62 段人体动作候选。没有再次下载或解码原音，也没有运行 Apple 原生测试、远端工作流或上传 TestFlight。

## 原始起停条件

`lock_1432.bytes` 原件为 44,283 字节，SHA-256 为 `74917b81d2e8e0bae60123a7bb2a42f15d7ce4dc9f90f57a62c787c66dc4dde7`。独立公开来源清单为 `scripts/erlang_source_meditation_audio_20261115.json`，仅保留身份、条件和证据摘要，不含原始音频、私有路径或密钥。

| 源事件 | 条件 | 应用消费者 |
| --- | --- | --- |
| t13 / a111 | `D15_Meditation_Start` 的 AnimationStart | 实际 `meditationStarted`，为该 owner 播放一次原 PCM |
| t21 / a195 | Start 或 Loop 离开 Uninterrupt，且下一动画不是 Loop 或 End | 实际 `meditationStopped`，停止该 owner 的原声 |
| t21 / a195 | `D15_Meditation_End` 的 AnimationEnd | 实际 `meditationStopped`，停止该 owner 的原声 |

`a111` 的 Loop 参数为空，原 PlaySound 默认值为 `false`。10 秒的原音保持单次播放，不能改成循环。Start→Loop、Loop→End 本身都不满足条件停止分支。a195 已沿原生 dispatcher 16475、consumer 30806、接口实现 34648、命令 34136、executor 34129 追到 `Banzai.Audio.AudioManager.Stop`，没有用动作注册序号猜测其含义。

原 PCM `SF3Erlang_d15_meditation_c928faf2c6d7.wav` 为 882,044 字节、44,100 Hz、单声道、441,000 个 16 位样本，SHA-256 为 `c928faf2c6d7645465a94ac376269d1012a52237c11f43821f404b8a099e174e`。

## 实际消费边界

`DuelErlangMeditationAudioClock` 只接受权威 step 产生的有界事件列表，按 frame/sequence 去重并检查 owner。World 在每个固定模拟步传入事件；渲染帧、cast phase、按键释放和模型年龄均不能自行制造起停事件。两位 owner 使用独立播放器类别。

KO、回合重置、参与角色变化和 shutdown 负责应用播放器清理，明确与源 t21 StopSound 分开。暂停沿用既有媒体生命周期；被消费的事件不会因媒体服务恢复而重放。源随机变体仍沿用现有应用策略，不宣称完整复刻原 AudioManager 混音或随机序列。

`d15_swords_explosion` 原件继续收录。在已核的 D15 aliases、locks、FX 范围内没有发现活动引用，消费者不会给它编造触发条件。

## 最终候选身份

| 文件 | 字节数 | SHA-256 |
| --- | ---: | --- |
| `SF3_Erlang_Profile.json` | 18,898,503 | `e9001357a0bda99f2fcc8f833b5e5dbc1c48846551def88aa2057d4d1ee1ad23` |
| `WuYong_Erlang_D15.glb` | 18,590,120 | `debd14c7af756e52e14b920ce2db37fd77ddcfa26b5668fe552ac79e7a1303bd` |
| `SF3_Erlang_Audio.json` | 198,937 | `7b963997a9cf008f015bf00a631e437d09ba24cb57f75374a86337206bf36111` |

新 schema 3 包含 87 个人体、11 个模型声音标记，以及 1 个有原始条件的独立声音事件；没有待绑定模型声音。62 段人体中的新增 Stun／根刺受控动作在原配置中没有 Sounds，既有 98 组标记未变。

`bind_erlang_source_audio.py --meditation-trigger-source` 先认证源事件清单，再核对真实人体冥想角色、完整 profile、GLB 和每个原 PCM，输出新目录。所有旧候选保留；此次操作只重绑定元数据和复制已核字节。

## 新增验证

只运行本次受影响检查：

- `check_erlang_meditation_audio_clock.swift` 的 4 组新场景通过：真实事件去重、无事件时不推断停止；同 step 源事件顺序与双 owner 隔离；暂停／回退／错误 owner；KO 与新回合清理。
- `check_erlang_meditation_audio_loader.swift` 的 3 项新检查通过：实际 62 段动作与 75 段 PCM／98 标记／独立源事件闭合；把单次原声改成循环会在打开 PCM 前拒绝；错误 StopSound trigger 同样提前拒绝。
- 四个受影响 App 文件完成 Swift 语法解析。Linux 检查执行的是生产 loader／clock；SHA-256 用已审 system adapter，Core 使用既有构建模块，没有重跑旧测试。

这证明来源、元数据、状态时钟和消费者契约在离线检查中一致。设备音频解码、实际可听播放、整合后的原生构建及签名发布仍须由最终候选门禁证明。
