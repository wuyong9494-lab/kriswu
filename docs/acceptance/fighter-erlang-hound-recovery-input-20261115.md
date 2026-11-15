# D15 原犬模型：恢复后的严格配置输入

## 本次实际结果

使用已认证的原模型、动作和 XML，再由原转换器执行一次离线转换，重新生成了 **438,144 字节**的 `SF3WE_D15_Hound.glb`。完整 SHA-256 为：

`22a9292b5fa62ae1a64d91cd7e840632119afd62a7c21d8485b5b9de011bc236`

这与既有犬模型验收记录以及 `prepare_erlang_hound_effects.py` 的固定 GLB 身份完全相同。此次恢复没有执行游戏客户端、原生 App 或测试设备，也没有改动 App、角色目录或资源发布身份。

## 两个配置输入身份

`scripts/prepare_erlang_hound.py` 新增显式选项 `--settings-format`：

| 格式 | 完整配置文件 SHA-256 | 行为 |
| --- | --- | --- |
| `historical`，默认 | `030ca65a96c38e1c335507c2d17c9570716e29510f85305a8e4d905fc179beaa` | 保留原输入校验、原输出字段和原转换行为 |
| `recovered-d15-v1` | `259db85e76a7bb4175d3fc037012f0fa53e6c04eb8d9a08ba7b27ea66d6f4bb6` | 仅接受本次恢复的 45 条 D15 原记录，并在候选收据中追加 `settingsInputRecovery` |

新配置是 **175,384 字节**的 `erlang-animation-named-recovered-v1.json`，具有单独的严格身份；它不是旧 `030ca…` 文件的字节恢复。新入口进一步检查原客户端和配置版本、原解码档案、原 animation split、原生 schema 方法 16684，以及 `settings_sets_dynasty.bytes` 的完整记录范围 89…133。两种入口随后都执行原有 `source_configuration` 校验，包括 record 93、原配置 SHA、犬动作名、裁剪、插帧、攻击窗口、四个原攻击部位及 X 轴 Align。

配置来源保持固定：

| 来源 | SHA-256 |
| --- | --- |
| 已恢复的原 splits 解码档案 | `02bcd31d5b0f3ed992ca1972f2c6da5f59e6495fe3880fec45f8b073fbaa0e7a` |
| 原 animation split | `efe3e5d48819adc1106302dacb2b9e94352d5b6735e79a7018a546b19531ab29` |
| 原 `settings_sets_dynasty.bytes` | `3d660f485ad5e238f23bf6dd19d16855635a9449fd213bf1dd468a9cc979f701` |
| 新具名配置恢复收据 | `22541c12e95558c4e1a0a09e4b67ecb817ffde512ad41ea079a285fe0e9acd27` |

该收据绑定原生字段顺序以及具名 JSON 写入、重读后的逆投影；原值类型和浮点值完整保留。新增格式不读取资源密钥，也不执行解密或网络请求。

## 原媒体输入没有更换

| 输入 | SHA-256 |
| --- | --- |
| `9d5fd54b70a5568f2cdc1f204770f78d.bin`，原犬模型 | `2cbb991e2d8ece154c56d95e776d3be2ac72c6d09df5c09d5413cdaf1fe4dea8` |
| `2a784bc550bc06541a38a4c1c53b69f3.bin`，原 D15 动作包 | `093b534cd7c509cf393b531e1dfc5f12f91e7a113c0153bf40bfe6bcdb5c5e6b` |
| 原犬动作，138,950 字节 | `6443c760202bf084ae030d81b419f8494db1f4aa2e7c7904c40054bdf924b712` |
| 原犬 Bones XML | `72f0791d0bd777caa31d7616feee71e737ccc67aa40f4827c49b1203f639c82d` |
| 原犬 ModelObject XML | `067a8a8560b317c42d4c6e8cbbd5d619c66a7f619ac5f99db8f807e55c1030a0` |

模型转换、材质、骨架、动作、GLB 写入和碰撞采样代码均未改动。实际转换保留原 141 帧动作，按原 record 93 裁剪为 60 帧，产生 119 个样本、52 个 rig 节点、50 个皮肤骨绑定、41 条动作骨轨和 6 个原胶囊；原 AnimationEnd 仍为 tick 110。

## 验证和输出边界

4 项新入口检查通过，耗时 0.004 秒：明确的新格式可接受；默认历史格式拒绝新格式字节；改变一字节后完整摘要拒绝；未知格式在读取输入前拒绝。随后一次真实离线转换退出码为 0，并再次从磁盘核对生成 GLB 的长度及完整摘要。

新 `d15-hound-candidate-private.json` 为 **92,291 字节**，SHA-256：

`ff2cf317bd2a8adb0a3cd3534704d5688b1807ca7fb4a97a00b057c235e1231f`

它保留实际配置输入的格式、文件名、字节数、摘要和来源，并明确 `historicalNamedSettingsBytesRestored=false`。这份新候选不冒充旧 `70e1…` 候选收据；现有接受端的旧收据 pin 没有修改。犬 GLB 的精确恢复也不代表最终 Wu profile、302 文件基底或完整整合候选已恢复，更不构成原生画面、游戏行为或 TestFlight 验收。

本次变更只有转换器和本报告；独立静态复核未发现输入门或默认路径的阻塞问题。
