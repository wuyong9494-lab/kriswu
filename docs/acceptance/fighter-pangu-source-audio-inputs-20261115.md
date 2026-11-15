# 盘古原始声音输入恢复（2026-11-15）

## 已完成的范围

`scripts/pangu_source_audio_inputs_20261115.json` 是离线输入计划 v2，不是运行时音频 release。它检查给定 `settings_sets_dynasty.bytes` 中全部 **29 个 D19 动画 alias**：14 个 alias 有声音，共 17 组 Common/Male 标记、38 个唯一原始标识。其中 **32 个已验证到本地 PCM，6 个未在完整已审目录中找到**。此范围是该配置的动画声音标记，不代表触发器音效、音乐或整个盘古角色的全部声音。

第一阶段只覆盖 **17 个已恢复 motion alias 中的 5 个有声 alias**，产生 25 个引用、24 个可得原音：21 个已有共享 WAV（10 个男性攻击声、11 个轻/重拳 whoosh）直接复用，pilum 发射声与 H20 两条 teleport disappear 各解码一次。第一阶段 4 个文件及全部 24 个原音身份已保留。

第二阶段继续只读另外 **12 个缺 motion BIN 的 alias** 的已解密原配置；其中 9 个有声音，增加 13 个唯一标识。8 个有准确目录条目：6 个男性重受击声直接复用现成 WAV，H20 两条 teleport appear 从第一阶段已取回的同一 bundle 中各解码一次，**没有新增下载或重解码原 24 个输入**。最终一共有 27 个原有共享 WAV 和 5 个本次新解码 WAV。v2 本次执行计数为复用 30 个（含 v1 已准备的 3 个）、新解码 2 个。

原 `SF3H17_*` 文件名保留，不改名为盘古专属素材。没有生成 `SF3_Pangu_Audio.json`，没有改变 App、战斗核心、角色选择或生产资源 release，也没有激活盘古。17 个 alias 的 motion bytes 已恢复；另外 12 个 alias 对应 11 个独立动作文件仍缺失。原配置中的声音标记可知，不等于对应动作已经恢复或可以绑定运行时。

## 原始标记与时间坐标

| 原动画 alias | 原路由 | 原 Frame / 保留的 sourceFrame | 候选声音数 | 本次输入状态 |
| --- | --- | --- | ---: | --- |
| `D19_Back_Blink_End` | `Sounds.Common` | 17 / 17 | 2 | H20 两条原音已恢复 |
| `D19_Missile` | `Sounds.Common` | 1 / 1 | 1 | `pangu_ranged_cast` 未在已审目录找到 |
| `D19_Missile` | `Sounds.Gender.Male` | 20 / 20 | 5 | 原男性轻攻击声已复用 |
| `D19_Missile_Model_Create` | `Sounds.Common` | 22 / 22 | 1 | 原 pilum 发射声已恢复 |
| `D19_Missile_Model_Create_No_Wall` | `Sounds.Common` | 22 / 22 | 1 | 复用同一个 pilum 输入 |
| `D19_Unthrow` | `Sounds.Common` | 25 / 25 | 6 | 原轻拳 whoosh 已复用 |
| `D19_Unthrow` | `Sounds.Common` | 44 / 44 | 5 | 原重拳 whoosh 已复用 |
| `D19_Unthrow` | `Sounds.Gender.Male` | 42 / 42 | 5 | 原男性重攻击声已复用 |

另外 12 个缺 motion BIN 的 alias 中，9 个有声 alias 的准确配置如下。其余 `D19_Forward_Rock_Model_Attack`、`D19_Forward_Big_Rock_Model_Attack`、`D19_Ultimate_Model_Pedestal` 的该字段为 `null`，不补造声音标记。

| 缺 motion BIN 的原 alias | 原路由 | 原 Frame / sourceFrame | 候选声音数 | 输入状态 |
| --- | --- | --- | ---: | --- |
| `D19_Upper` | `Sounds.Common` / `Battle@Movement` | 1 / 1 | 1 | `pangu_upper_whoosh` 目录缺失 |
| `D19_Upper_Passive` | `Sounds.Gender.Male` / `Battle@Voice` | 2 / 2 | 6 | 原男性重受击声已复用 |
| `D19_Upper_Passive_Atl` | `Sounds.Gender.Male` / `Battle@Voice` | 2 / 2 | 6 | 同一组 6 个原音，不重复解码 |
| `D19_Forward` | `Sounds.Common` / `Battle@Movement` | 1 / 1 | 1 | `pangu_forward_cast` 目录缺失 |
| `D19_Low` | `Sounds.Common` / `Battle@Movement` | 17 / 17 | 1 | `pangu_low_hit` 目录缺失 |
| `D19_Back` | `Sounds.Common` / `Battle@WeaponAndArmor` | 2 / 2 | 1 | `pangu_back_cast` 目录缺失 |
| `D19_Back_Blink_Start` | `Sounds.Common` / `Battle@Movement` | 2 / 2 | 2 | H20 两条 teleport appear 已恢复 |
| `D19_Ultimate` | `Sounds.Common` / `Battle@WeaponAndArmor` | 8 / 8 | 1 | `pangu_ult_cast` 目录缺失 |
| `D19_Ultimate_Alt` | `Sounds.Common` / `Battle@WeaponAndArmor` | 8 / 8 | 1 | 同一条 `pangu_ult_cast` 仍缺失 |

原生方法 `39579` 给声音采用 `max(0, Frame)`，不采用攻击区间的减一规则。输入计划不把 `FirstFrame=17` 的传送 alias 改成 frame 0，也不把带裁剪的 pilum frame 22 改成相对 runtime tick。`FirstFrame`、`EndFrame`、`MidFrames`、`SelfEndFrame` 与完整原声音数组保留；缺省 Frame 需要另外的原始证据，工具拒绝擅自当作 0。Female/Monkey/Floor 路由仍保存在原数据中，不混入本轮 Common/Male 输入。

候选列表顺序保持原配置顺序；没有自行选定某一个备选，也没有把声音转接到泛化的 `castPhase`。`Battle@WeaponAndArmor` 保留原值，不改成 `Movement`。所有 `runtimeClip`、`runtimeTick` 均为 `null`，等待与真实角色和原动作播放器的时间轴一起接入；也不把被动受击 alias 的声音擅自归给施术者。

## 来源与核验链

| 输入 | 字节数 | SHA-256 |
| --- | ---: | --- |
| `pangu_source_motion_inventory_20261114.json` | 52,747 | `baa0a83c58348c3842b4a442ea534f875168a93a411646ed6c7e07e5d2941d45` |
| 原交付 ZIP 中的 `research/android_bundle_catalog.jsonl` | 9,100,700 | `2c01276ca8c58ea32d79bfe481e37adc6696bc4c5a6140f6f6842ca262d07055` |
| 同 ZIP 的 `research/xiaomi_entries_with_offsets.json` | 649,576 | `74808fc799fcba68b86384b2dc3c42597049355e90e4f5d21589c41111d6e219` |
| 男性声音已审 PCM 清单 | 9,298 | `06a0b02587c55106b851f33aad1a7b10a480e5fad846d26c17a0510351974736` |
| 包含轻/重拳 whoosh 的已审 PCM provenance | 94,731 | `2eaf22eb311bbb9006a214199f52dc5e81179d01d97931a18d465a6b47a3b35e` |
| 含男性重受击声的 common-context PCM 清单 | 23,307 | `b1557aafc28213d6e2ed9aa975473c2649b94e48a10ced20da07bce6eab43bef` |
| `settings_sets_dynasty.bytes.values-private.json` | 1,111,299 | `a4b3023f669becc039c2b546e1c6f171fc89e84e1ecb82688b5db2dc66aea64b` |
| 对应 storage receipt | 790,977 | `44664e48acf70462c8285029bbf861a19cbc6df26804c28c7efc4d0d2c77b9b2` |
| storage 指向的原 settings entry | 334,225 | `3d660f485ad5e238f23bf6dd19d16855635a9449fd213bf1dd468a9cc979f701` |
| v1 已准备输入计划（只用于复用先前新解码的 3 个 PCM） | 61,400 | `7f4492df25afc1ce3825d1a6872f20cd268436dbd6c68c45669966c20fcf5729` |

采用原生方法 16684 / reader 16478..16506 已恢复的 29 字段 schema，`Sounds` 位于索引 26，内部顺序为 Frame/Common/Gender/Floor，Gender 顺序为 Male/Female/Monkey。先逐项核对全部 17 个已有 alias 的配置 recordIndex、motion FileName、全部原标记与 Sounds，再读取 12 个缺 motion alias。storage 的 `allBytesConsumed=true`，没有因动作文件缺失跳过配置记录。

原动作配置版本是 `1.46.0.16.16733-prod`；此次共享音频目录与准确 APK 范围来源保留其历史 Android `1.45.3` 身份。两者通过原配置的完整资源标识连接，再核实际对象与字节，没有把目录版本改写成 D19 专属资源版本。

离线工具逐项验证以下链条：原配置 identifier → 完整目录中的唯一 path/pathID → 本地 bundle 长度与 SHA-256 → 实际 container 的 AudioClip 类型及 pathID → 原对象字节和编码音频字节的 SHA-256 → 已审 WAV 身份或新解码 WAV → PCM16、采样率、声道数、样本帧数及与源 AudioClip 的时长一致性。新输出另记录纯 PCM 样本 SHA-256。复用路径不调用 `AudioClip.samples`；原有共享 PCM 和前阶段已准备的 PCM 均核验身份后直接复用。

`h17-common-context-audio-inventory-private.json` 不含第一阶段的 11 条拳声，拳声来自 `h17-audio-binding-provenance-private.json`；第二阶段新增的 6 个男性重受击声则准确来自 common-context 清单。不同来源逐项保留，不混用同名文件或猜测家族。

## 本次新增的准确原件范围

| 原 bundle | 长度 | SHA-256 | 本轮目标 |
| --- | ---: | --- | --- |
| `1879bbcd352f4c26f314716c6c6d8bb0.bin` | 20,739 | `0ca1b6263761026c8125dc0b8329ebd7a1bf280d2bde3e7e96310050f81c7791` | `pilum_shoot` |
| `39c7049edc5921808079c604eabe8caf.bin` | 1,722,404 | `70fe31cc8194823ae43db83572937f96ebacf07ac71b9bb6611aaeaaa8b46a43` | H20 两条 teleport disappear、两条 appear |

仅使用现存官方来源 receipt 的地址和已审 ZIP 条目偏移，读取这两个条目的 local header 与原始未压缩数据，接收量共 1,743,301 字节（含 header）。各请求均验证 HTTP 206、准确 Content-Range、identity 编码、ZIP 成员名、CRC32 与目录 SHA-256。没有重下整个 2,683,387,431 字节 APK；本次也没有重新声称核过完整 APK 哈希。地址仅用于私有恢复，不写入仓库或本说明。

| 新 PCM | 字节数 | WAV SHA-256 | 格式 |
| --- | ---: | --- | --- |
| `pilum_shoot` | 99,268 | `6bef51ba152b0a1e052a482e154ec3a726720b6baa309ec038e2db63c460f8a9` | 44,100 Hz / mono / PCM16 / 49,612 frames |
| `h20_teleport_dissappear_1` | 95,012 | `0bcf5d5a909d7bf8ff380dd1d78a8dcde3fa7cd40ab80eff9e5bf64ceb4d6ce8` | 44,100 Hz / mono / PCM16 / 47,484 frames |
| `h20_teleport_dissappear_2` | 105,468 | `85862b03c4005478ca890eb1d0526c34dcc79ea0a2cd575d5bbc73beb4d689cf` | 44,100 Hz / mono / PCM16 / 52,712 frames |
| `h20_teleport_appear_1` | 117,844 | `d5cc7641b125e97abaef7b7683fd4013200fbca890643c5a942b1984d1ea25c2` | 44,100 Hz / mono / PCM16 / 58,900 frames |
| `h20_teleport_appear_2` | 118,416 | `243b4fe6da22d3e1b2d154ca9373d8051fc92358c6dd03dd773dd93004fb65a2` | 44,100 Hz / mono / PCM16 / 59,186 frames |

两个 bundle、分两阶段产生的五个新 WAV 和最终 32 个输入的私有文件定位记录保留在私有工作目录，仓库只包含代码、测试、来源标识与哈希。没有重采样、增益修改、声音合成或专属素材替换。解码期间底层库打印过 socket 权限拒绝提示；本地 WAV 产出及上述格式、时长和身份检查成功，未修改权限。

## 工具与验证

新工具 `scripts/prepare_pangu_source_audio_inputs.py` 只处理显式提供的本地输入。需要原 motion inventory、原 settings values/storage、含完整 catalog 的原交付 ZIP、本地 bundle 目录、三个固定哈希的 PCM provenance 清单，以及仓库外的私有输出目录。另以固定哈希的 v1 计划和私有 locator 复用前阶段 3 个已经解码的 PCM；v1 原件保留，不用当前可编辑清单自我背书。`--decode-missing` 只准许解码没有已审 PCM 的、已准确索引并核验的本地 AudioClip；没有联网、运行客户端或发布功能。已存在的输出文件会拒绝覆盖，已准备的新 PCM 也不会再次解码。

第一阶段 7 项新增轻量检查通过；随后收紧缺省 Frame 的处理，仅重跑该受影响检查并通过。扩展阶段只执行 2 项新检查和 1 项受影响的原坐标检查，3 项均通过（0.002 秒），没有重跑原完整集合。新增覆盖缺 motion 时保留原声音与 WeaponAndArmor 路由、已有 alias 与原配置不一致时拒绝、复用前阶段 PCM 必须同时匹配两个快照 pin。原检查覆盖裁剪坐标、缺省/负数 Frame、目录歧义、禁止重解码、对象/编码错配、PCM 篡改/截断、格式变化、覆盖拒绝和 partial 语义。

```bash
python -m unittest discover -s scripts -p test_prepare_pangu_source_audio_inputs.py -v
PYTHONPATH=scripts python -m unittest test_prepare_pangu_source_audio_inputs.PanguSourceAudioInputsTests.test_negative_sound_frames_clamp_and_absent_frames_require_evidence -v
PYTHONPATH=scripts python -m unittest test_prepare_pangu_source_audio_inputs.PanguSourceAudioInputsTests.test_missing_motion_retains_original_sound_and_weapon_armor_route test_prepare_pangu_source_audio_inputs.PanguSourceAudioInputsTests.test_previous_preparation_reuse_requires_both_exact_snapshot_pins test_prepare_pangu_source_audio_inputs.PanguSourceAudioInputsTests.test_actual_source_crop_keeps_marker_origin_and_alternative_routes -v
```

第一阶段实际执行得到 24 个 verified PCM；第二阶段只增加 6 个复用输入和 2 个新解码输入，得到 32 个。原 24 个 WAV 身份全部保持一致，未再次下载或解码。所有 17 组原 Frame 都是显式整数；未把原帧投影成运行时 tick。没有运行原生测试、模拟器、官方客户端或工作流。

## 后续接入条件

此动画标记范围仍有 6 个已知原标识没有匹配目录：`pangu_upper_whoosh`、`pangu_forward_cast`、`pangu_low_hit`、`pangu_back_cast`、`pangu_ult_cast`、`pangu_ranged_cast`，均属于 `set_d19/`。这不是整个人物只有 6 个音频缺项的断言；触发器音效、其他设置、Female/Floor 等上下文都不在本次可得计数中。

12 个 alias 对应的 11 个原动作文件、真实盘古模型和运行时时间轴仍需完成。届时可依据本计划的 alias、原路由、原 Frame 与原始对象身份接入；本计划不提供替代模型、不将 Sun/Liu 更名为盘古、不把这些原音单独当成角色已完成或 TestFlight 可发布的证据。
