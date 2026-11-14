# 倒地音频：原始候选接入受摘要约束的资源版本

本批以 `54bfc94dfdaca4a9ea8325e661cf5304525601f8` 为源码基线。
新增装配器已实际把上批 95 WAV / 114 marker 私有候选接入新 H17 source release。
它复用现有音频调用链，不修改渲染、GLTF、WeaponAssets 或既有工作流。
这次接入没有重新提取、解码或编码原音频，也没有重新上传旧资源版本。

## 具体交付

`scripts/stage_h17_floorfall_release.py` 同时校验四个独立摘要：已审查加密包的
manifest、原 assembly receipt、原 release，以及上批候选 audio manifest。
它核对旧 295 文件与候选 95 WAV 的实际字节，只允许下面的变化：

- 替换 `SF3_H17_Audio.json`，其 88 个旧 PCM 绑定和 112 个旧 marker 均保持原样。
- 新增 7 个已经恢复的原始 PCM 文件，共 245,606 字节；不再次运行音频解码器。
- 替换 `SF3_FighterRelease.json` 的 release ID 与 `triadAudio` 文件记录。
  角色、模型、catalog、材质、动作、Morph 和其他 binding 均保留原值。

实际生成的 H17 overlay 包含 **302 文件 / 129,997,765 字节**。
与旧 295 文件 overlay 相比，293 个文件完全不变，只需传输 **9 个增量文件 /
329,548 字节**。输出目录使用 0700，文件使用 0600；既有目录和文件不能被覆盖。
增量清单同时记录 base package、base release 和 target release 摘要，不能靠包内自报
摘要取得激活权限。签名构建仍须独立采用新的 `FIGHTER_ASSET_RELEASE_SHA256`。

| 对象 | SHA-256 |
| --- | --- |
| 已审查 base release | `7bf9aa17a1e15273dbe7ae04eecd1ef092c2ad9a72360b99cd4f7ac08695704b` |
| 新 audio manifest，保持上批候选原字节 | `7451625a85eab8da8f296f4d412c94981e7d411706de7ea6e5b620c2f7d4d809` |
| 新 release / 签名构建 pin | `fc85891d75aef9b236270e801d9d6d43661ff0f86fde812d4d1aa7996bc9ebbf` |
| 9 文件增量清单 | `da980ab998acaa85fb828d320a9fc3aec4cff6457145644bd94287f0c84000fb` |

302 文件是完整的 **H17 source overlay**，不是独立的全部游戏资源。既有装配流程先安装
73 个基础资源，再应用 H17 overlay；两处已审查替换重叠，组合后为
`73 + 302 − 2 = 373` 个资源。旧 `SF3_SourceTrails.json` 等基础资源仍由该流程提供。

## 已核对的真实调用链

1. 签名构建 pin 授权 `DuelFighterAssetReleaseLoader` 读取新的 release。
2. 新 release 的 `triadAudio` 指向上述 candidate 原字节。`DuelWeaponAssets` 已通过
   该记录调用 `DuelTriadAudioBinding.load`，逐一校验 WAV 大小、摘要及引用闭包。
3. `DuelWeaponFight.setPose` 输出逐模拟步的 `sourceMotionSamples`；`DuelWorld`
   每个固定步将样本交给 `DuelSourceEffects.consumeTriad`。
4. 两个 marker 的 `clock=intervalStart` 把原始起点 20 转为零基采样 19。
   59 / 48 帧动作各自的完整时长为 116 / 94 ticks，因此均在动作 tick 38 跨越。
5. 现有 consumer 按已绑定角色、clip、frame、sequence 去重，再调用已有音效调度。

本轮没有通过把原音频写进源码、绕过签名 pin 或创建另一条秘密传输路径来接入。
受保护原生环境的密钥目的地授权仍须独立解决。

## 实际执行证据

| 验证 | 结果与范围 |
| --- | --- |
| 新装配器轻量测试 | 10 方法通过，0 失败；覆盖原输入身份、追加范围、时钟/变体顺序、数据篡改、目录隔离和禁止覆盖 |
| 真实资源 stage | 一次成功，295 → 302 文件，9 文件 delta；没有重编码或上传 |
| 当前 Swift release/audio loader 源码 | Linux Swift 6.0.3 编译并执行；新 pin 加载成功，旧 pin 拒绝；catalog 验证、96 个音频记录和 114 个 marker 通过 |
| 两个 interval | 12 个跨越/冻结/跳帧/倒退检查通过 |
| 新 installed SiteTests | 3 个方法已新增，Swift 语法检查通过；没有执行 Apple XCTest |

Linux loader 检查采用当前两个 App loader 的源文件，仅补 `ShiftCore` import。
SHA 通过 `sha256sum` 适配；companion 仅用已 pin 的角色/帧元数据适配，没有加载
SceneKit 模型。因此这些结果不等同于 iOS 播放、GPU 场景或真机听感验收。
原 `ef306408…` 的 117 个原生方法没有重跑，也不覆盖本批新增内容。

新增 `Tests/SiteTests/DuelTriadFloorfallIntegrationTests.swift` 明确要求新 release pin。
缺失资源会失败，不会 skipped 后被记为通过。三个方法分别检查真实资源绑定、既有
consumer 的重复/暂停/重置边界，以及七个 WAV 的 Apple 解码；consumer 方法使用
播放器 spy，不能单独作为可听输出证据。

该文件随后更新为最终组合 pin `e5c0ccae…`、115 marker 和 3 个 Floorfall 绑定
（Sun 两个、Liu 共享根缚结束一个），其最新定义与 parse 证据见根缚后续记录。
上表的 114 marker loader 执行仍只代表当时的 fc858 audio-only 候选，不替代最终
组合版本的单独执行证据。

## 实际玩法路径的后续核查

**普通 knockdown：**当前 Sun profile 的 `knockdown` role 确实绑定
`h_hit_head_fall`。一个不修改源配置或角色属性的实际 catalog 探针，在入场结束后让
Liu 靠近并重击。1800 个固定步产生了 11 次 heavy swing，但没有接触，双方 HP 保持
1000，因而没有自然 knockdown marker 跨越。该版本 Fight 构造器仅接收 catalog，
碰撞直接采样其骨骼轨道，没有遗漏一个可注入的 GLB capsule provider。
该探针保留为最初未成功的场景记录。后续在原 catalog、不改伤害或轨道的合法距离
2600 / 2617 mm 各起手一次重击，实际接触发生时距离约 1164 / 1181 mm；两次命中将
Sun HP 从 1000 降至 871、742。首击触发既有 H17 防护，所以没有受击动作；第二击在
600 tick 冷却内进入 `h_hit_head_fall`，其 tick 37 → 38 **恰好跨越一次 Floorfall**。
结果在第 837 个 wall step 完成。最初 0 接触由探针起手距离与首击保护的组合解释，
不再列为碰撞实现待修复。证据见
[合法重击接触诊断](acceptance/h17-heavy-contact-diagnosis-20261114.md)。
这证明 Linux Core 中的自然玩法采样路径，没有执行 iOS 播放或真机验收。

**根缚结束：**`h17_root_spike_passive_end` 已在 Sun 原动作目录和新的音频绑定中，
但本次接入前的 `applyTriadControl` 只设置通用 hit 姿态和 root 计时；锁定时冻结该姿态，
`controlReleased` 清理计时/来源后没有进入原始 Start → Loop → End 动作链。
已复核原始 `lock_1777` 的 PostHit、AnimationEnd 和 Loop_Check interval 分支，确认
这是实际机制缺口。Liu 旧模型也没有这组三段动作，不能用 marker 的存在宣称该路径
已完成，不能把旧双锤当成盘古资源。本轮后续已核实三原动作与双方 58 骨骼身份映射，
并独立接入 `DuelTriadRootVictimState`，见
[根缚受击后续实现](fighter-root-victim-20261115.md)。本文件的 9 payload / fc858 候选
仍是当时的 audio-only 结果，不能冒充后续组合资源已安装或验收通过。

机器可读摘要见 [本批接入验证](acceptance/fighter-floorfall-integration-20261114.json)。
