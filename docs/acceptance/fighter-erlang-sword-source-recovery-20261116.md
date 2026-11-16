# D15 飞剑原特效 source-only 恢复

日期：2026-11-16。基线：`302e89031245d64c1a36b02a4fba1169f70d86b8`。

本次从现存原包恢复了飞剑高预设 20 个发射器中已支持的 17 个、全部十个材料依赖、
十四张原纹理及九种原模型姿态。输出为独立 source-only 候选；三个真正启用 Noise 的
发射器仍明确不支持，未声称完整 prefab、已接入角色或已通过原生/GPU 验收。

## 严格的新入口

默认 `historical` 入口继续使用原 model、held、material receipt、extra texture receipt、
Trail texture receipt 和真实 profile 合同。旧完整 SHA 未被替换，历史输出文件名和
清单/receipt 结构保持。`source_models` 和 `plane_geometry` 的 AST 保持完全相同。

新 `--input-format recovered-v1` 是另一条明确的 source-only 路径，拒绝夹带
`--profile`、`--cached-materials`、`--extra-textures`、`--trail-textures` 或
`--material-sources`，不通过空 profile、旧收据假名或 metadata 覆盖来绕过原入口。

| 输入 | 字节数 | 完整 SHA-256 |
|---|---:|---|
| recovered model | 666,196 | `25b7efc5cb38d2197ab49fcf58cc255feb8e3d6fa3309a9ab1ab31bb655496d0` |
| recovered held poses | 935,704 | `d84c455d5f2321980ed136cf15073663ba002f8ba76b8660ce7ce6638e5b8fb2` |
| recovered named D15 records | 175,384 | `259db85e76a7bb4175d3fc037012f0fa53e6c04eb8d9a08ba7b27ea66d6f4bb6` |

入口复用完整 `model_inputs` 验证原 decoded archive、animation/battle splits、45 条
D15 配置、18 个原 lock、211 条 trigger 的字节、CRC、全字段和类型，再把 model 与 held
的整份 `inputRecovery`、model SHA 和 `sourceCandidateReceipt` 精确联接。
原 lock 1447 高预设初始化、1440 的 HIDE/SHOW、1449 的删除条件继续逐项校验。

## 材料、纹理和原始字节

全部输入来自已存在的本地 D15、shared、FF108、shader、9d3e 和 e082 原包；零新增网络。
材料 helper 的新分支从完整固定 SHA 的 FF108 原包定点解两份外部 Material，并继续核
十个材料原 raw SHA、shader CAB、准确 keyword program 和原 invalid-keyword 声明。
每个非零纹理 PPtr 同时核 path ID 和 CAB，不只按名字或裸 ID 选择。

实际依赖是 **十四张原 Texture2D**：旧 extra 四张、Trail 六张、旧基础缓存三张，以及
D15 包内一张。原默认白纹理另列，不冒充额外原贴图。所有原对象、typed metadata、完整
压缩纹理流和 PNG 均保留。ETC2 格式 45/47 的 **108 层 mip** 逐层记录 offset、尺寸、
字节数和 SHA；没有丢弃小尺寸尾层或只保留顶层 PNG。

纹理 metadata 中的原 byte-array 使用已有显式 `__unity_bytes_hex__` 投影，读回恢复
原类型后逐字段比较；原 raw 与完整 stream 自身仍按完整 SHA 验证。

## 实际输出

成功目录为 `recovered-erlang-sword-source-only-v1`，共 **150 文件、12,063,266 B**，
包括原输入缓存、材料/程序证据、派生资源和收据。

| 输出 | 字节数 | SHA-256 |
|---|---:|---|
| `D15_Sword_SourceOnly.recovered-v1.json` | 2,322,239 | `81c190b69bcf7757b9d246a3cdf5f0c724044499d7aca7c75fbe835babd41e19` |
| `D15_Sword_SourceOnly.recovered-v1.json.gz` | 709,484 | `16f4003fc5130d80f65909a4e25daa026ad8ce130f9009736ae2aeb644aa0204` |
| `d15-sword-effect-receipt-private.json` | 113,605 | `245d64669edd31d5e7e5707ad60a4081d2e91424b235c6ddc67ed2a5a2e3af86` |

清单内有 39 个资源：9 个共享去重后的 Metal 程序、15 份完整 texture 流、15 份 PNG。
其中 14 份是原纹理，另有原 shader 白默认。十个材料来自五个源 shader。

| 源层 | 实际导出 |
|---|---|
| 原剑和 spiral 网格发射器 | 8 个 |
| 普通局部 plane 发射器 | 7 个；原 mode 0 不错误使用其 inactive mesh 指针 |
| Trail 发射器 | 2 个，四个实际 particle head/独立 history 定义 |
| particle tracks | 36 条 |
| 真 Noise 发射器 | 3 个明确 unbound，`completePrefab=false` |
| 原模型状态 | 六 Birth、Idle、单样本 Rotate、Attack，共 9 种 |

六 Birth 与 Idle 各保留原 51 帧、101 个根姿态样本；Rotate 恰好 1 帧/1 样本/tick 0，
不伪造第二帧。Attack 保留 101 个原样本但源删除边界仍为 tick 70，未把完整采样长度
误当模型有效存活时间。

两个 Trail 保持源 world-space history、`dieWithParticles=false`、0/1 秒双相位、
2 秒周期、原 `.330000013…` 尾部寿命及 33 cm 宽度。候选只提供实际粒子局部源样本和
history 参数，没有杜撰角色运动产生的 world-history 点。HIDE/SHOW 和 10/5 帧
DestroyEffect 只作为原规则证据保留，本次没有证明原生淡出行为。

## 检查与执行记录

一次完整转换 exit 0，7.917 秒。成功后没有再次转换或重生成本候选。

六项新增检查最终均通过：

1. 历史与 recovered 参数身份不得混用，不能夹带 profile 或旧 metadata bypass；
2. model/held/全部 typed source 证明联接，改变候选字节或数字类型会被拒绝；
3. 错 CAB、原对象/纹理流改动、截断、mip 类型变化及材质纹理 PPtr 错 CAB 均被拒绝；
4. source-only schema/文件名/缺少运行时字段与九种原姿态保持准确；
5. 独立读取原 mesh、emitter、renderer 和 Trail module，核网格、部分支持范围、粒子时钟和尾部语义；
6. 独立解十份原材料，核全部原程序表达式与资源 SHA，逐字节核十四份完整纹理流及 108 层 mip。

首轮五项通过，第六项在复用旧测试模块的 `ARGS` 注入处发生测试 harness 的
`AttributeError`，尚未执行最终纹理读回。仅修正 mock 的 `create=True` 后，单独重跑
该受影响方法，3.481 秒通过；没有重跑前五项，也没有修改 producer 或成功输出。
两份日志都保留，不把首轮称为六项全绿。

静态 AST 核对确认历史 manifest、receipt、effect、source binding 和材料 document
原表达式仍存在且相同；共享 sampler、shader translator、Trail exporter、App 和中央
Identity 未修改。历史明文输入不全，所以未声称执行了旧入口回归。

## 消费与验收边界

新 schema 是 `original-d15-sword-source-only-recovered-v1`，输出明确
`sourceOnly=true`、`runtimeBound=false`、`nativeParityVerified=false`、
`appleGPUVerified=false`。它没有 `version/profileID/profileSHA256/characterSHA256`，
也没有 `erlangSwordModels/erlangSwordBinding`；原姿态只在 `sourceModels` 中。

当前 App 仍固定读取 `SF3_D15_SwordEffects.json.gz` 并校验完整身份和必需运行时字段，
因此不能消费这个新文件；即使误改名，结构和 pin 也不满足。未来需要对最终真实角色
profile 做明确的新绑定与验收，不得直接把该候选标成旧生产清单。

没有执行原客户端、Apple GPU、CI、受保护 workflow 或 TestFlight；没有上传。
完整 prefab 的三个 Noise 层、最终角色绑定、原生粒子/淡出一致性及屏幕视觉验收仍是缺口。
