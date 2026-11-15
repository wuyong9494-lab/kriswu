# 二郎神 D15 原声音与 App 消费

本批将已恢复的 D15 原声音接入实际源动作／模型时钟。范围是 D15 的 45 个配置 alias 中 29 组 Common／Male Sounds markers，以及已取得的 14 个专属 AudioClip。它不覆盖全部普通皇朝长枪、腿法、受击或 Floor 材质分支；这些范围分别补齐，不能用本批 28 个 PCM 数量宣称全角色音效完成。

普通／共享 Common、Male 的后续恢复与消费见 `fighter-erlang-ordinary-source-audio-20261115.md`，该后续合包已达到 75 个原 PCM、98 组源 marker。本页保留 D15 首批的原始范围与证据。

## 原件与输入

`prepare_erlang_source_audio.py` 以已审完整 Android catalog、明确 bundle hash、容器路径、AudioClip path ID、对象和 encoded 数据 hash 交叉核实来源。28 个 PCM 包含 14 个专属 D15 声音和 14 个共享声音；首次恢复复用 5 个已有同对象 PCM，其余 23 个只解码一次。没有调增益、重采样或裁切。PCM 格式、时长、字节和解码后的样本 hash 均被记录。

原输入 manifest SHA-256 为 `01649a542d8a20cbe66e9e1bee831201c3c70cdd4200c6f0b1b23c66e88aa9fd`，配置原件 SHA-256 为 `3d660f485ad5e238f23bf6dd19d16855635a9449fd213bf1dd468a9cc979f701`。原 PCM 和详细来源私有记录不进入源码仓库。

`bind_erlang_source_audio.py` 将原输入与真正人体 profile、character hash 和独立 model tracks 绑定。这个步骤只核对并复制既有 PCM，不再次解码。当前中间候选为 29 个活动 marker：18 个人体、11 个模型，pending model 为 0。profile 后续的 Stun、配对和规则变化仍需要重新固化清单身份，不能将中间 profile hash 写成最终发布身份。

## 实际时钟

声音 Frame 的规则是 `max(0, Frame)`，不减一；扣除原动画 first index 后乘原 `MidFrames + 1`。人体完整播放时长与 AnimationEnd 的提前事件边界保留区别。Earthshaker 的 MidFrames 为 0，因此仍使用真实每源帧一个 tick，没有统一强制成两倍。

人体消费 `sourceMotionSamples` 的 previous／current tick 跨越区间，按真实 owner、clip、frame、sequence 和完整时长匹配。它不从 castPhase 反推音效时刻。跳过显示帧不会丢掉逐模拟步传来的事件；相同模拟步不会重复消费。

犬的源 Sound Frame 1 对应模型 age tick 2。飞剑的六个 Birth alias 分别绑定 `erlangSummon_swordBirth1` 到 `erlangSummon_swordBirth6`，每个实例在自己的 tick 2 播放一次。它们与同一原 motion 的 `erlangSummon_sword` Attack 分离；Attack 只消费自己的飞刀射出 marker。模型保留 id／bornAt，音频使用真实 `motionTick(at:)` 与 `(owner, id, role, stateStartedAt)` 识别新的动画状态。Idle／Rotate 不凭空增加声音，重复进入相同 Attack role 也不会继承前一状态的消费进度。

暂停不消费事件；KO 后不开始新的模型声音，但已发生的结束步人体样本可以消费一次；round reset 和 shutdown 清除旧时钟。播放仍使用现有播放器池，没有新建第二套音频引擎。吴庸的未绑定 weapon fallback 不再播放双锤声音。

## 已取得但不播放的两个原件

`d15_meditation` 有独立源 trigger 的起停流程，等待完整事件绑定，不能伪装成某个普通动画 Frame marker。`d15_swords_explosion` 已取得原件，但在本轮核实的 D15 alias、locks 和 FX 范围中没有发现活动引用；其状态记录为 `no-active-reference-in-reviewed-source-scope`，并不暗示未来一定存在一个待猜出的播放事件。两者均不因资源文件存在而自动播放。

## App 验证边界

`DuelErlangSourceAudio` 校验同一个 decoded profile、profile 文件 pin、character pin、源配置 pin、marker 与实际人体／模型轨迹、每个 WAV 的大小／hash／PCM16 格式和样本 hash。模型 alias 到 role 有明确约束，因此不能把 Birth 指向原 motion hash 相同的 Attack 来通过验证。允许的源路径、文件数量和总字节有界。

`DuelErlangAudioClock` 是纯 presentation 时钟；`DuelSourceEffects` 与 `DuelWorld` 的最小 hook 传递真实样本和模型状态。音效不能推进战斗、生成模型、确认命中或延长实例生命。

已完成的定向检查：此前 5 项 production clock 检查和 3 项真实 PCM loader 检查；本次只新增 3 项 persistent-sword 状态时钟检查，以及 2 项实际 29-marker／Birth误绑Attack 拒绝检查。旧检查没有为了本次状态字段变化重复运行。Linux loader 检查用系统 SHA-256 adapter 代替不可用的 CryptoKit，只验证生产 loader 其余逻辑和真实输入；没有宣称 Apple 音频解码、AVAudioPlayer 可听播放或原生设备验收已经通过。

本批没有启动工作流或上传 TestFlight。最终 profile、companion、音频及完整 release 的身份由统一候选最后绑定。
