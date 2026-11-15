# 二郎神：原始皇宫石地声音

本批将吴庸／二郎神的声音清单从 75 个 PCM、98 组标记扩充为 **82 个 PCM、119 组标记**。新增的 21 组来自当前 62 段人体动画的原始 `Sounds.Floor.Stone` 配置：普通动作 20 组、D15 开场站姿 1 组。独立模型的 11 组声音及冥想实际起停事件保持原样。

## 地面来源

`erlang_palace_floor_source_20261115.json` 记录可复核的来源链。

- 原 `02b589a405ebe8b7a25d13d1b51263ae.bin` 中，`palace_exterior_raid` 的 `Common.Location.SceneConfig` 对象为 pathID `-8058892632017654769`；对象 104 B，SHA-256 `655a58963cb540a7547143fa8ccbb6a3d58601c358a279f66c7e179b15263b76`。
- 原 `FloorSurfaceSettings` 为 `surfaceY = 0`，唯一范围 `[-2000, 2000]`，`surfaceType = 2`。
- 原 `global-metadata.dat`（27,877,556 B，SHA-256 `12d52d278c904b210541e7c337025c68454e2b89a83eddab51f9c74fcc5a245c`）中的地面枚举为 `None = 0 / Ground = 1 / Stone = 2 / Metal = 3 / Wood = 4`。五个字段的原默认值压缩字节依次为 `0 / 2 / 4 / 6 / 8`。
- App 实际加载的 `SF3_Palace_Exterior.glb` 为 9,292,540 B，SHA-256 `185aff02bbfb932e6cbf77daf9dba34d02adf6cec4ff78ee595414cef1f169d8`。本批从已经保存的整合 ZIP 中仅提取这一个文件，复核了同一身份。

Stone 的选择依据是原配置和原枚举。其他场景尚未取得同样的地面绑定，不能借用这一分支。

## 新增原音与时钟

7 个新增到吴庸清单的原音如下。其中 5 个直接复用既有、同源 AudioClip 已核验的 PCM；其余 2 个各解码一次，保持原声道、采样率、长度和音量。它们可能已被其他角色使用，不能称作新的二郎神专属录音。

| 原音 | 本批处理 |
| --- | --- |
| `9_Footsteps_Stone_Surface_V1 / V2` | 复用 2 个原 PCM |
| `11_Land_Stone_Surface_V4 / V5 / V9` | 复用 3 个原 PCM |
| `steel_weapon_hit_0` | 从已有完整 bundle 解码一次 |
| `4_Metallic_Weapon_Hit_V2` | 精确取回缺少的 377,421 B bundle，核目录、ZIP CRC 和 SHA 后解码一次 |

最后一项使用既有官方 APK 来源及已核 ZIP offsets，3 次严格 HTTP 206，共取 377,499 B。没有重新下载完整 APK。目录/object/encoded/PCM 的独立身份见 `erlang_palace_floor_audio_receipt_20261115.json`；公共文件不含原音、凭据或下载 URL。

原声音帧继续使用 `max(0, Frame)`，不减一。例如前后步的 `Frame = 10` 在当前原生步长 2 下对应 tick 20；落地 `Frame = 31` 对应 tick 62。原配置中 `[V1, V2, V2]` 的重复候选原样保留。六段配对投技、三段 Stun 和三段根刺被控动作的原 Floor 分支均为空。

## App 与资源绑定

`bind_erlang_source_audio.py --floor-input …` 产生 schema 4 清单。它验证独立 Floor 输入和地面来源收据，再与实际 profile／GLB 身份闭合。当前候选绑定：

| 项目 | 字节数 | SHA-256 |
| --- | ---: | --- |
| 62 段动作 profile | 18,899,069 | `bafb288e94495d492a90523f67f963d85e75fb7f49adf7014bb64883bbf57c47` |
| 原身体与个人头适配 GLB | 18,590,120 | `debd14c7af756e52e14b920ce2db37fd77ddcfa26b5668fe552ac79e7a1303bd` |
| 独立 Floor 输入 | 37,878 | `8e43cbe4b0f4d63cedb64f9b8f386dd992f12e3922daef4e9219bd9e1849a41d` |
| schema 4 音频清单 | 232,510 | `30334f61be20bed0ca7f49a0a8f6ca843e38f62cb964b3ee8ec01cc4f7892572` |

`DuelWorld` 只在已经成功加载 `.palace` 的情况下，向声音 consumer 传入实际 stage 的固定 digest。`DuelErlangSourceAudio.clocks(stageSHA256:)` 据此选择 Floor 标记；空值、Autumn 或其他 digest 只得到原有 98 组 Common／Male 标记。同一帧已消费的动作区间仍受原 sequence 门禁保护，即使之后才出现地面上下文，也不会补播旧脚步。

原 owner、暂停、回合、模型实例／动画状态时钟和冥想实际事件消费均不改变。`d15_swords_explosion` 继续保持“已收录、已审来源范围内未发现活动引用”。

## 本批验证边界

仅运行新增或受影响检查：

1. 两项源清单检查：21 个具体帧／tick 与重复候选，以及原 75 个 PCM 字节、98 个标记记录和冥想起停记录不变。
2. 四项实际 loader／clock 检查：读取完整 schema 4 的 82 个 PCM；只允许已验 Palace；错误 floor 先于 PCM 访问被拒；将声音帧减一被拒。
3. 三个受影响 App 文件语法解析。

Swift 检查使用已有 Core 模块和实际生产 loader／clock 源码。Linux 检查适配器只把 CryptoKit SHA-256 换成系统 SHA-256 工具；音频播放器和 iOS 原生运行未执行。首轮新检查的 harness 需以 `@testable import ShiftCore` 构造内部 sample initializer，修正后再执行；没有因此重跑旧的成功用例。

本收据不宣称 iOS 中已听到声音、不宣称完整特效已验收，也不构成 TestFlight 上传记录。主集成仍需将新的清单身份纳入最终资源包及原生验收。
