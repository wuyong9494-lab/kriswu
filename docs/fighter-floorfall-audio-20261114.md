# 原版 common floorfall 音频：独立编译与绑定候选

本次完成的是**可复核的音频资源编译器、两项原事件绑定和新的私有候选目录**。候选未并入、激活或上传任何加密 release。本项音频工作没有修改现有游戏源码、H17 manifest、模型、网格、工作流或资源包。本文不表示用户当前安装版本已具备该音效，也不表示已经完成听感或真机音画同步验收。

基于 `ef3064085879c497d59533459c94b429a40f9cee` 的独立开发快照。实现仅新增以下文件：

- `scripts/source_floorfall_audio.py`：纯本地源字节解析、身份验证、七项 AudioClip 编译与 v2 候选绑定。
- `scripts/test_source_floorfall_audio.py`：轻量 Python 回归。
- `Tests/ShiftCoreTests/DuelFloorfallSourceMarkerTests.swift`：生产 `DuelSourceMotionSample.crosses` 的三个定向时序测试。
- 本文。

## 原始事件已确认的部分

从既有、已解码的 `1.46.0.16.16733-prod` splits 归档中直接读取并解析 `lock_923.bytes`。编译器先校验原字节长度与 SHA，再解析有界 typed storage；不执行原脚本，不读取密钥，不再次解密。

`lock923 / set97 / trigger0`，名称 `EFFECT__Dust_Down`：

| 项目 | 原始记录 | 本次处理 |
|---|---|---|
| 事件分支一 | `FloorHit(Me, Type=null)`；registry 默认 Type 为 `Physics` | 保留为未接入，不用渲染坐标或 y 过零推断 |
| 事件分支二 | `IntervalStart(Me, "Floorfall")` | 只编译两项已确认源动作 interval |
| 允许条件 | 当前动画匹配 `PHYSICS` 或 `FALL` | 源配置分组必须匹配 |
| 排除条件 | `THROW_FALL`、`PHYSICS_NO_SFX` | 严格保留；条件变化使编译失败 |
| PlaySound | action ordinal 111 | 已核对原 registry 的名称、参数顺序与默认值 |
| 声音数组 | body layer 的 V1、V3、V5、V8、V13、V15、V16 | 保留原顺序与候选数组，不用 Land/石地脚步音替代 |
| Loop | 源值 null，registry 默认 false | 单次声音 |
| Position | 源值 null，registry 默认 null | 保留 null；原生默认位置解析仍待恢复 |

同一触发器中的 `Dust_down_2` 特效使用 `centerOfMass`，它属于 **CustomEffect**，不能据此把音频 Position 改为 centerOfMass。另一个 `set98 / EFFECT__Dust_Down_From_Throw` 没有 PlaySound 动作，本次没有给它添加普通倒地声音。

七项声音来自既有原始缓存 `4d7f8b35e599fce4165da3b317824dc0.bin`，共 1,014,386 字节。编译器按目录中的精确资源路径和 pathID 查找 AudioClip，不依赖文件名相似度选择声音。

## 两项绑定与明确排除

| 源动画 | 源文件 / 记录 | 源 Floorfall interval | 结果 |
|---|---|---|---|
| `H_Head_Middle_Average_Critical_Fall` | `settings_hits.bytes` / 48 | Start=20、End=20 | 编译到 `h_hit_head_fall` |
| `H17_Root_Spike_Passive_End` | `settings_sets_heralds.bytes` / 104 | Start=20、End=20 | 编译到 `h17_root_spike_passive_end` |
| `Ninjato_Stance_Start_Round` | `settings_style_ninjato.bytes` / 11 | Start=13、End=13 | 排除：没有 PHYSICS/FALL 分组 |
| `Shadow_Ninjato_Slash_Passive` | `settings_style_ninjato.bytes` / 20 | Start=33、End=33 | 排除：带 THROW_FALL |

两个新增 marker 均使用现有 `DuelTriadAudioBinding` v2 字段：`clock="intervalStart"`、`sourceFrame=20`、`context="Common"`。现有 intervalStart 播放样本为 `20-1=19`。本次核验的两个 motion 均保持当前 profile 的每原样本两 simulation ticks，因此 `19×2=38`。编译器校验原 motion SHA、样本数和播放 duration；裁剪起点、MidFrames、循环、interval 或 duration 变化均要求重新审阅，不能继续套用 tick 38。

这个结论表示**动作自身时间轴的第 38 tick**，不是整局全局 tick，也不依赖 renderer 当前帧是否跳过。动作采样边界、冻结重复样本以及加速跨越由独立 Swift 测试覆盖。未接入的 Physics FloorHit 分支不会被这一候选自动补齐。

## 新候选产物

候选采用现有 v2 manifest 格式，保留旧 document 中所有非 `files`、`markers` 字段。旧 88 项 file records 与旧 112 项 markers 保持原顺序及对象内容；只追加七项 PCM 与两个 markers。

| 项目 | 实际结果 |
|---|---:|
| 原 PCM 字节复用 | 88 文件 |
| 新恢复 PCM | 7 文件，245,606 字节 |
| 新 PCM 格式 | 22,050 Hz、单声道、PCM16 |
| 候选总音频 | 95 文件，10,143,046 字节 |
| 候选总 markers | 114 |
| 候选 manifest | 51,395 字节 |
| 输出目录权限 | 0700 |
| 媒体、manifest、私有来源记录权限 | 0600 |

七个 AudioClip 均校验源 bundle SHA、container 路径、pathID、对象类型、原始对象 SHA、编码音频 SHA，以及解码后的采样率、声道数和时长。没有重采样、增益调整、归一化或替换源音色。旧 PCM 直接按字节复制，没有重编码。

候选 manifest SHA256：

`7451625a85eab8da8f296f4d412c94981e7d411706de7ea6e5b620c2f7d4d809`

原 manifest SHA256 保持：

`f815d96b89cd59be9b42509a636919c64c43c6ada61b49ef40ae6489fcb9de47`

编译前后另行比对了 **91 个现有输入文件**：88 份旧 WAV、原 audio manifest、原 profiles 和原 release manifest，SHA 全部不变。输出是全新私有目录；工具在任何解码发生前拒绝已存在的输出目录，避免误重复成功编译。

最终审阅还把 base 的版本、H17 角色身份、固定配置 digest、context、file/marker 数量、累计字节、重名和引用闭包检查移到读取任何 WAV 之前。真实 base 的 `sourceConfigurationSHA256` 是 `71b164acc4f03d93e4af4aba864eb2e192531c07d1b4751f05b2520b94e7656e`；`release-final`、`release-morph`、`release-pelvis` 和 `audio-candidate` 四份既有 manifest 均一致。显式 `playbackTicks=0`、`false`、空串或非整数不再按缺省处理，只有缺失或 null 使用既有每样本两 ticks。前置门禁修正没有改变本次有效输入的转换逻辑；没有再次解码或重建已经成功的私有候选，以上候选 SHA 保持不变。

这项 digest 属于**现有音频绑定输入**，与整体 RuntimeProfile 的配置 pin 范围不同。已按 `bind_h17_audio_source_events_private.py` 的原规则独立重算：依次拼接 `h17-ninjato-d19-animation-named-private.json`、`h17-all-host-animation-named-private.json`、`h17-trigger-audio-events-private.json`、`ordinary-throws-animation-candidates-private.json` 四份原始 JSON 字节后取 SHA256，得到相同的 `71b164…`。四项各自的 SHA 也与当前 `h17-audio-source-event-bindings-private.json` 回执逐项一致。较早的 `h17-audio-binding-provenance-private.json` 对应首次单输入绑定，不能代替后续 v2 扩展回执。

## 验证结果与证据等级

| 验证 | 当前证据 |
|---|---|
| 原始配置字节与 registry | 已执行：4 个源成员、原 action/event registry、源 catalog 与 bundle 身份校验 |
| 实际音频编译 | 已执行：只恢复新增 7 项，产物格式、时长、大小与 SHA 均通过 |
| Python 回归 | 最终源码的 18 项有界回归全部通过（0 失败，0.019 秒）；mock 确认拒绝路径不读取现有 WAV、不调用音频解码 |
| Swift 语法 | `swiftc -frontend -parse` 通过；该命令只检查语法 |
| Swift 核心定向执行 | Swift 6.0.3 / Linux：本文件 3 项全部通过，纳入本次最终 15 项定向组合，0 failures |
| iOS 音频加载与播放 | 未执行 |
| 模拟器、iPhone 17 Pro Max | 未执行 |

音频依赖在解码时输出两行 `socket(): Operation not permitted`，进程最终退出码为 0；本地 PCM 校验成功。没有下载新的源 bundle。此结果不能替代 Apple 音频 API 的实际播放验证。

Swift 新文件只依赖 `XCTest` 和 `@testable import ShiftCore`，自带 sample 构造 helper，不依赖其他测试文件中的 fixture。三个方法检查：两项 motion 在 tick 38 跨越；冻结样本不重复且加速跳帧仍跨越；重启动作可重新播放而倒退不跨越。这些属于纯核心时序验证，不是 iOS 音频或视觉验收。没有重跑现有 117 项呈现测试。

完整执行摘要与最终源码摘要见 [本批验证记录](acceptance/fighter-dual-continuation-20261114.json)。组合执行回执为 `dual-character-core-final.log`：增量编译 11.27 秒，15 项执行 3.109 秒。Floorfall 的三个方法均执行成功；这不证明原资源在 iOS 场景中的播放、混音或延迟。

## 精确复用入口

命令必须给出已有私有缓存，输出必须是仓库外的新目录：

```bash
python scripts/source_floorfall_audio.py \
  --splits /private/source-recovery/1.46.0.16.16733-prod_splits-decoded-private.zip \
  --actions /private/source-recovery/original-actions-registry-private.json \
  --events /private/source-recovery/original-events-registry-private.json \
  --catalog-archive /private/source-inventory/ShadowFight3_Motions_and_Scene_Sources.zip \
  --models /private/existing-model-cache \
  --profiles /private/existing-release/SF3_DistinctFighters.json \
  --audio-manifest /private/existing-release/SF3_H17_Audio.json \
  --audio-directory /private/existing-release \
  --output /private/new-floorfall-candidate
```

实际验证复用了既有 UnityPy 1.25.4 依赖缓存，没有重新安装工具。完整源数组、AudioClip pathID、编码与 PCM 摘要、允许与排除的配置记录，以及未完成事项，保存在候选的 `floorfall-audio-provenance-private.json`。源码仓库只保存工具、测试与此说明，不收录 PCM 或原始资源。

## 后续最小接入范围

若要进入实际用户版本，仍需独立安排：验证原生 `PlaySound.Position=null` 的解析与当前播放路径一致；为权威 Physics FloorHit 事件建立单独绑定并处理与 interval 的事件边界；核验 Apple 端新候选加载和 tick 38 播放；最后才审阅加密 release manifest 的整合。本次不触及这些已有共享文件，也没有自动创建资源包、上传版本或触发工作流。

原始字节 pin：

| 成员 | SHA256 |
|---|---|
| `lock_923.bytes` | `c2fe1f2fa5b4a0a8b457de20608334d9202b959b832b72317860adf0d8c9cba2` |
| `settings_hits.bytes` | `d6daca4777b04dcab96375ce6aa899ec75a6b0aa5784b0beddd53f843aa9226a` |
| `settings_sets_heralds.bytes` | `64bd77afa0edacdc7b672047222fb4261771f08b835367bc3aeeb5b02e668f5a` |
| `settings_style_ninjato.bytes` | `84fc1a78b7de5a3ad3bbdabf32f6526daf89bf7bd1fdbb9fd4d7a18cb12948bb` |
| 现有声音 bundle | `a66918864b0974a585e24b11799ce701f70d3848d27baa343cf8199e68f35f32` |
