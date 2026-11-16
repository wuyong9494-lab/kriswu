# 吴庸 D15 身体动画实际恢复 — 2026-11-16

本批已从现存原件生成一份新的动画模型及身体轨迹 profile：49 个原身体角色动作加 1 个原配置指定的镜像变体，共 50 段。输出使用实际新 SHA，没有复用散失的 62 段候选身份，也没有重建或绕过旧 302-file release 门槛。这是后续完整同场 profile 的实际输入；当前尚不是可直接发布的 full-match profile。

## 精确输入与转换范围

新入口为 `scripts/prepare_erlang_animated_body.py`。它复用现有 `append_motion`、源骨骼解析、裁剪/时钟和镜像函数，但不调用历史 builder 的 `build()`，也不修改其 `SETTINGS_SHA` 或 `REFERENCE_CATALOG_SHA`。

| 输入 | 本批核验 |
|---|---|
| 原 motions/scene ZIP | 沿既有 `ARCHIVE_SHA256`，内部 2,205 条完整 bundle 目录及 motion catalogue；9 个确切 motion bundle 全部已有，无下载 |
| 新恢复具名动画 | `erlang-imperial-animation-named-recovered-v1.json`，353,751 B，SHA `12704648d0fd60929d1bba47a0fe6cd1eb0f3aafd36b7504b8819f57f5bddb08`；82 条原配置，49 个身体角色逐一唯一解析 |
| 配置来源 | 6 份原 `*.bytes`、新具名恢复 receipt、82 条 round-trip audit 均按固定字节和 SHA 验证；不把新格式伪装为历史具名 JSON |
| 静态身体 | 10,379,416 B，SHA `fe02e7c96d99905e70af712cfd0b52bea1d6d3b732f07eb44bbe5fe6b8182f39`，配套 receipt SHA `ded6bbc5d5fb98a5a6ae8b245d6a4aa984283668921401de4a1145e0ddad326c` |
| 源骨骼 | 原 553/608 body XML 与 Imperial Spear XML 的现有固定 SHA；80 个绑定节点、58 个正质量骨骼、15 个人体胶囊和 2 条原长枪攻击胶囊 |
| 每个动作 | 目录中的 bundle/pathID/bytes/SHA 均验证，必须为唯一 TextAsset；禁止把独立模型或犬动画投到人体骨骼 |

静态身体的原 BIN 前缀、节点、8 个 mesh、蒙皮、材质、纹理、图片、已有 accessor/bufferView 逐项不变。个人头像仍是原 `head` 骨骼下的刚性子节点，59,878 顶点及原图像数据继承已核静态输入；本批没有生成或声称恢复颈部桥接。

## 实际产物

私有目录：`recovery-20261116/erlang-animated-body-v1/`。

| 产物 | 字节数 | SHA-256 |
|---|---:|---|
| `WuYong_Erlang_D15_Animated_Source.glb` | 17,094,876 | `1a8aa028b58db99dda4cc63c4008e6ab1e73f584cab80ac457fa70e1c9bcb84d` |
| `SF3_Erlang_Animation_Source_Profile.json` | 15,414,047 | `cf3f65c6eb12f2d7b4384e506ca15b3beedb1b0bbdb78148ba6d61dbc4e3493c` |
| `animated-body-receipt-private.json` | 60,254 | `8f648142f23466123cfbe29511ed325cddff52f8a751e887f47cc3c92b761387` |

profile 的 `resourceName` 对应这份新 GLB。它保留原 motion 字节、source configuration、原 source IDs、根位移、脚/脚趾/头/骨盆/质心、两条原武器胶囊及 15 个人体胶囊轨迹；普通 Imperial Spear/kick 接触区间来自相同的原配置。两侧攻击胶囊不表示新增第二柄可见枪：静态几何仍只有原 primary 左枪。

### 不能混用的时钟与动作

| 源动作 | 本批结果 |
|---|---|
| `d15_avatara_laser` / `erlangEye` | 原 149 帧，record 104，playback 296、EndEvent 288、297 个头部 FK 样本；原 motion SHA `c05c657b4eafdbe0e8785ea5672050fece08d4620d52f76e0bd401f77957645f` |
| `d15_avatara_spear_earthshake` | 原 record 102 的 `MidFrames=0`，111 帧、playback 110、EndEvent 106；空间表仍保留每源帧两采样，共 221 点，不误把其实际时长改成 220 ticks |
| `D15_Avatara_Transform_Out` | 原 record 133，`staff_idle` 原 62 帧仅取 frame index 0；真实 1 源帧、1 GLB key、1 FK 样本、playback 0、EndEvent 0，没有复制帧 |
| `Imperial_Spear_Heavy_Slash_Passive_Mirror` | 原 Imperial record 10 的 `Mirrored=-1`；相同原 passive TextAsset 经已审 body mirror 规则得到独立变体，71 源帧、141 个 60 Hz 导出 key、playback 140、EndEvent 132 |

普通 GLB 的 30 Hz key 时间和镜像的 60 Hz key 时间是可读回的导出网格；源裁剪、`MidFrames`、`SelfEndFrame` 和 profile playback 单独保留。没有把原未声明 FPS 换成“原游戏 30 FPS”。镜像继续限于已核非奇异分支，portable Float64 计算后存 Float32，不声称原生逐 bit 一致。

## 实际验证

一次转换 exit 0。写出 GLB 后重新读取所有 channel/key，并用实际存储变换独立计算头、骨盆、脚趾、质心、胶囊端点及地面抬升；共 **5,762 个头部样本、276,576 个比较点**，最大差 **2.384185791015625e-7 m**。原静态几何/BIN 前缀核验同时通过。这证明离线源动画与写出轨迹一致，不证明 SceneKit/native/GPU 或实际对战通过。

随后只运行 `scripts/test_erlang_animated_body.py` 的 5 项新增检查：

- 修改具名源输入一个字节必须在对象加载前拒绝。
- 修改实际候选一个 head 轨迹点，独立 GLB FK 必须拒绝。
- 修改实际候选一个 hurt capsule 端点，独立 GLB FK 必须拒绝。
- 真单帧 TransformOut 与 stride-one Earth 的帧/时长合同。
- 镜像仍绑定相同原件且轨迹确实不同；不完整 profile 的边界和缺失字段保持明确。

五项均通过、无跳过。检查只有显式传入实际源目录和候选目录才运行；缺少路径会明确 skip。没有重跑 Avatar、旧材质导出、原生编译或客户端检查。

复现转换需要显式提供 `--source-archive`、`--source-bundles`、`--source-configs`、`--shared-bones`、`--settings`、`--geometry`、`--geometry-receipt`、`--output`。所有私有输入/output 都在仓库外；目标已存在即拒绝。环境沿用已核 UnityPy 1.25.4 与既有隔离 Python 依赖。

针对性检查命令：

```sh
PYTHONDONTWRITEBYTECODE=1 \
PYTHONPATH=scripts:/absolute/recovery-20261115/python \
ERLANG_RECOVERED_BODY_INPUTS=/absolute/recovery-20261115 \
ERLANG_RECOVERED_BODY_CANDIDATE=/absolute/recovery-20261116/erlang-animated-body-v1 \
python3 -m unittest -v test_erlang_animated_body
```

实际日志为私有 notes 中的 `erlang-animated-body-v1-conversion.log` 与 `erlang-animated-body-five-checks.log`。

## 完整同场接入剩余项

输出显式 `sourceOnly=true`、`runtimeBound=false`、`fullMatchProfile=false`。目前没有写入 `ordinaryThrows` 或 `erlangRules`。后续应使用原始配置和原 motion 重建新的 reviewed profile，不应制造历史目录 `41a63…` 或旧 body `debd14…` 的相同身份。

1. 六段源普通/配对投技及其可独立核实的 policy、Wu 自身配对几何。
2. 原 Stun 三段、H17 root-victim 三段及各自真实配置。
3. 明示生成部分的个人 neck bridge 与实际姿态/视觉验收。
4. D15 能力规则、独立召唤物与 FX/audio 对新 profile 的真实身份绑定。
5. 完整 release、App 身份、原生/视觉验收及发布；本批未改这些门槛。

现有 `append_motion` 内的碰撞采样明确针对 Imperial Spear。其他角色可复用源 motion decode、裁剪、Writer、骨骼 FK 与质量表流程，但必须使用自己的原武器 capsule 配置，不能将 D15 长枪 part 改名套用。
