# 刘共享根缚受害动作：独立资源核对

## 已确认的范围

只读审阅 `scripts/append_cached_root_victim_motions.py` 及已经生成的本地 candidate，**没有重新运行 append**。从新 GLB 独立调用已有 `bind_source_fighter_pelvis.pelvis_samples`，三个新动作共303个 pelvis 样本与 profile 逐值完全一致；再从写出的 GLB channel 重新计算刘自身 rig 的其他轨迹，所有输出取7位小数后差值为0。

结果仅证明追加资源的身份、结构和几何一致性；没有运行 Apple 原生测试、模拟器、渲染或 iPhone 17 Pro Max 验收。角色身份仍为 `liu_hammers`，没有将旧双锤资源升级为盘古独立装备。

## 输入与输出身份

| 内容 | SHA-256 |
| --- | --- |
| 原刘 profile | `30b7af76550112c523d11d8b967553bccd7a65503d24bb21cb71f92b060c8723` |
| 原刘 GLB | `f83d8cbbd7b2158604dad9eff28398bcf57c64fdcb4146e5c142608484a5a472` |
| 新刘 profile | `2dbe085bd288a4aff2bf9694d5e55699500879feb203985a342b76c1036b81ca` |
| 新刘 GLB | `a3aada76d336b9c4f9bda3904b5e947711d916f683a2dcbf7b8184377e01a517` |
| 刘 source capsule bindings | `fd16a6cb2eb863365b563aab9b162220335c6abdb0c700594499c08264151c57` |
| 刘 source mass bindings | `3bf3b9b92e118d4584019213c1d51f68b47d28dff11abb098ef42428a32dd1d2` |

## 逐项独立验证

- 原 GLB 的 **8,403,480-byte BIN 前缀逐字节保持**；原56个 animation、原 accessor/bufferView 前缀保持。
- 全部原节点、mesh、skin、material、texture、image、scene、extras及其余容器字段保持；buffer 只扩展长度。
- 原56个 profile clip完整保持，roles及除clips/bytes/sha256之外的全部profile字段保持。
- 新增恰3个动作，分别44/61/48帧，对应87/121/95个半帧采样；每个116个translation/rotation channel，绑定刘原rig的58个源骨骼。
- 每个新 clip 内保留的源motion bytes与已缓存的原文件逐字节一致，SHA与追加记录匹配；核对过程不输出这些字节或base64。
- 从新GLB独立重算 `root`、`handL/R`、`footL/R`、四条双锤端点、`groundLift`、按原顺序执行的Float质心及15个hurt capsule，全部与profile相同。
- 验证未读取孙profile。武器轨迹使用刘原mesh顶点、joint weights和inverse bind matrices；hurt capsule和质心使用固定身份的刘自身绑定文件。

| 新动作 | Frames / samples | 原motion SHA-256 |
| --- | --- | --- |
| `h17_root_spike_passive_start` | 44 / 87 | `69d01bc2d1cc6be69188be006582598bf3551c88db3f7446078fcda63583382c` |
| `h17_root_spike_passive_loop` | 61 / 121 | `a3f13059f3eeedd057e14d738894667a77b04279109d1544f0e2b34ad12502ce` |
| `h17_root_spike_passive_end` | 48 / 95 | `7d9b8572ae67cd8f344f16478cc50a56e17c0646191c7f2306ff2724453cf5e2` |

## 最小 importer gate

新增 `scripts/test_append_cached_root_victim_motions.py`，仅执行该文件的6个合成方法，全部通过，耗时0.021秒。覆盖自身node/sourceID唯一绑定、禁止借用其他角色质心身份、非法质量值、原Float累加顺序、实际bytes与digest/长度/symlink约束、已有输出在读取私有源前拒绝覆盖。

没有扫描原始资源档案、下载模型、重跑已成功重型集合、上传资源或TestFlight。详细脱敏记录见同目录 `liu-root-victim-independent-20261115.json`。其中 `pelvisSHA256` 与 `tracksSHA256` 使用追加receipt的“紧凑JSON加末尾换行”编码；`pelvisSemanticSHA256` 使用已有pelvis helper的无换行编码，二者命名分开，不能把序列化差异误判为轨迹差异。
