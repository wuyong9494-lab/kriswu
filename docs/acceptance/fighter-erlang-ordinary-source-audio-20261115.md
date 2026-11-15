# 二郎神普通动作与共享原音补全

本批补齐已准入人体动作实际引用的普通／共享 Common、Male 声音，与此前 D15 声音合并后共 **75 个原始 PCM、98 组源 marker**。其中 D15 为 29 组，普通 Imperial、移动、受击、腿法和配对投技为 69 组。播放仍由实际源动作或模型时钟驱动，没有用通用长枪或双锤声音替代。

## 范围如何确定

只按当前 profile 的实际 clip、role、原配置记录和原动作对象取声音。普通动作逐项核对配置的 FileName、原 bundle 容器路径／path ID、裁剪窗口和完整播放时长。源配置包括 `settings_style_imperial_spear.bytes`、`moves_settings.bytes`、`settings_hits.bytes`、`settings_style_kicks.bytes` 和原皇朝套装配置；原 block 配置也纳入范围核对，但没有凭空增加 marker。

六个 shared paired roles 使用原配对时钟。四个普通 throw 的声音来自 moves_settings 81–84；D19_Unthrow 来自原皇朝配置记录 248，共三个 Common／Male marker。记录 249 的 passive Sounds 为空。新增 Stun_In／Loop／Out 的 moves_settings 87–89 也均为空，不为这些动作猜声音。

69 组声音在原输入中引用 52 个独立声音路径，其中 5 个与已有 D15 输入相同。52 个输入的处理结果是 **45 个已有 PCM 精确复用，7 个首次解码**。这 7 个仅为两个人声 heavy attack 和五个原 medium weapon whoosh；两个精确原 bundle 已在本地，无新下载。已有 28 个 D15 PCM 没有重新解码。

新原输入 `SF3_Erlang_Ordinary_Audio.json` 为 182,302 字节，SHA-256 为 `7296d0f5152bf07b34c532f621b5ffc3b91e92e00ab69f898325c9a7b6a41ea3`。源频率、声道、PCM16 样本数及原声音字节保持不变；没有增益、裁切或重采样。所有复用 PCM 均同时核对原 AudioClip 对象、encoded resource、WAV 和 PCM 样本身份。

## 事件与消费

`prepare_erlang_ordinary_audio.py` 从受 pin 保护的本地原配置、catalog、H17／Pangu／D15 PCM receipts 生成新私有输入。它不运行游戏，不请求网络或密钥。`bind_erlang_source_audio.py --ordinary-input …` 将其与既有 D15 输入和当前完整 profile 合并为 schema 2 运行期清单。

声音 Frame 仍使用 `max(0, 原值)`，不减一。人体事件保持 actual role、实际导出 clip、原 motion hash、源配置 hash、source first index、stride 和完整时长。被投镜像与普通被投虽保留相同原 motion 字节，却有不同的导出 clip／role，因此镜像音效不能误绑到普通被投 clip。

App loader 将每一 marker 的配置来源与固定原配置 hash 表核对，同时校验 profile、角色、所有文件、PCM16 样本和真实轨迹时长。合包 75 个文件的总体积继续受 32 MB 上限约束。普通声音不会削弱此前六柄飞剑 Birth 与 Attack 独立状态时钟的检查。

吴庸的旧 generic swing／impact fallback 设为 silent，使真实源 marker 不与错误的徒手或双锤默认声音叠加。命中视觉和战斗结果不由声音决定。没有源映射的全局材质 contact cue 不在本批中推断。

## 实际验证

本批新运行三个生产 loader 检查：75 个实际 PCM 和 98 个 marker 能完整认证；篡改 Imperial marker 的源配置 hash 会在 PCM 访问前拒绝；将镜像 role 指向普通被投 clip，即使原 motion hash 相同也会拒绝。三个检查全部通过。此前 D15 的 5 项原时钟、3 项输入 loader、3 项新增模型状态时钟和 2 项 Birth 绑定检查没有重复运行。

验证复用了既有 Swift 6.0.3 Core 模块，没有重建或重跑战斗测试。Linux loader 使用系统 SHA-256 adapter 代替不可用的 CryptoKit；没有执行 AVAudioPlayer 或声称设备可听播放已验收。完整 private profile 的最终 Stun／模型／规则变化，只需要重新绑定运行期身份，不能重新解码这些已成功的原 PCM。

公有 `scripts/erlang_source_audio_receipt_20261115.json` 保存文件和 marker 的身份、时钟、数量及范围，不含原音字节、私钥或签名 URL。

## 明确保留的边界

本批选择 Common／Male，未猜测 Floor 材质、Female 或 Monkey 分支。D15_meditation 的原生起停 trigger 由单独事件消费者接入，不能作为普通 Frame marker；d15_swords_explosion 在核实的 D15 alias／locks／FX 范围内未发现活动引用，保留原文件而不擅自播放。完整角色包的最终 profile、GLB、companion、音频和发布身份统一固化；本批没有启动 native workflow 或上传 TestFlight。
