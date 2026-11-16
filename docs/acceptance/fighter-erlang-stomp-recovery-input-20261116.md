# D15 大脚原特效的独立恢复输入

日期：2026-11-16。

本次从已恢复的本地原包导出了 `D15_fx_big_leg` 的三个原网格发射器。
输出是独立的 **source-only 资源候选**，没有声称恢复旧运行时清单、完整吴庸角色
配置或 302-file 基底；也没有接入 App、修改资源身份白名单或触发原生运行。

## 输入与历史入口隔离

`prepare_erlang_stomp_effect.py` 的默认入口仍是 `historical`。原模型候选
`870b6c27c3a8117f2d4e7e45b60c0c7d0c74dd16ddd129b43ab01e4d5b428cfc`
及 653,960 B 长度检查保持；原 profile、compact rule、输出文件名、运行时字段
和 receipt 保持原合同。旧 profile 的真实明文字节仍未恢复，未填空值或替换其身份。

显式 `--input-format recovered-v1` 采用另一套严格输入，拒绝同时传入 `--profile`
或 `--material-sources`。新分支需要 `--settings`、`--decoded-splits` 和本地
`--texture-bundle`，复用 `model_inputs` 的完整校验：

- 原 decoded archive、animation/battle split、dynasty storage 的完整 SHA；
- 45 条 D15 原记录全部字段的逆投影与标量类型；
- 18 个原 lock 的 CRC、完整原始字节、211 条 trigger 及其完整字段；
- 新模型候选与上述整份 `inputRecovery` 的精确类型、值和身份联接。

| 新输入 | 字节数 | SHA-256 |
|---|---:|---|
| recovered D15 model candidate | 666,196 | `25b7efc5cb38d2197ab49fcf58cc255feb8e3d6fa3309a9ab1ab31bb655496d0` |
| recovered D15 named records | 175,384 | `259db85e76a7bb4175d3fc037012f0fa53e6c04eb8d9a08ba7b27ea66d6f4bb6` |
| decoded splits archive | 17,325,877 | `02bcd31d5b0f3ed992ca1972f2c6da5f59e6495fe3880fec45f8b073fbaa0e7a` |

仍检查原 record 100、`D15_Avatara_Leg_Model`、10 帧、AnimationEnd tick 18，
以及 lock 1434 trigger 1 的完整 event/action。没有推测或改写任何规则值。
新的派生 JSON 不被称为旧 compact JSON 或旧模型候选的字节恢复。

## 本地原资源闭合

只读取已存在的 D15、shared、shader 和 texture 原包，没有新增网络请求。
共享材料仍由旧 `erlang_effect_materials.prepare_materials` 从准确 ZIP 成员读取；
三个材料、原 shader keyword program 选择和粒子采样代码均未修改。

三个发射器为 `-929469514926225548`、`6055453625588746100`、
`-1006497375095126156`，共用原网格 `geo_big_leg_001`：

| 对象 | 身份 |
|---|---|
| mesh path ID | `-6222684053069387964` |
| mesh 原始字节 | 39,228 B |
| mesh 原始 SHA-256 | `953d2289a5d2ad7e5e6104a02cec6a3449ad8f3447abfb8cc2f3ff0f04d852f3` |
| 网格规模 | 685 vertices、984 triangles |
| 材料 | `mtl_freshnel_premltpl`、`mtl_energy_scroll_09_adtv`、`mtl_aBlnd` |

新分支定点恢复两份原 Texture2D，验证所属 CAB、对象 ID、名称、原始对象完整 SHA、
尺寸、格式、mip 标量类型和完整流 SHA，再保存完整流及逐 mip 收据。

| 原纹理 | path ID | 原流字节数 | 原流 SHA-256 |
|---|---|---:|---|
| `caustic_noise_007_grscl` | `-4727852512917511309` | 349,552 | `da1a9435f0c7c6e376abba56e4363426cc5a50f11629ee06051f4f8008ea250f` |
| `VFX_TileNoise_32_contrast` | `-8498525634246556637` | 349,552 | `60579717193f40549840d78c9850f36081f6ec295377b487714a05219a3becdb` |

两者均为 512 × 512、原格式 47、10 层 mip。全部 20 层的 offset、字节数和摘要
均被保留，未只保留顶层 PNG。源 shader 的空指针默认白纹理另列，未伪称第三张原贴图。
Unity typetree 中的 `bytes` 字段以显式 `__unity_bytes_hex__` 表示；原对象和流仍原字节保存，
读回时恢复其字节类型再逐字段比较。

新输出目录单独生成最小 SourceAssets 缓存，不改已有 cache。项目色彩空间、PhysicsManager
与 QualitySettings 继续使用已恢复的原数据和完整摘要，不重新假定重力或采样模式。

## 实际输出

成功目录名为 `recovered-erlang-stomp-source-only-v2`。完整目录 43 文件、3,515,476 B，
包含源对象、材料程序证据、纹理流、派生资源和收据；清单中的资源条目为 9 个。

| 文件 | 字节数 | SHA-256 |
|---|---:|---|
| `D15_Stomp_SourceOnly.recovered-v1.json` | 518,228 | `2c35c0972b9036e9948a496b7f9f43e31e42cc6199785003c639d6085589cd2a` |
| `D15_Stomp_SourceOnly.recovered-v1.json.gz` | 200,863 | `e25174fe3d41a530a3fce6e2a1386efb7d0b82e4bfa864ad315a9bd75237abbe` |
| `d15-stomp-effect-receipt-private.json` | 23,407 | `9954628860e88cc8a47cd28ee0c61cc084d9f9d6db4d822815c48a4774cdb019` |

三条 particle track 分别保留 19、21、20 个约简采样，原生命周期是
`1.399999976158142` 秒，输出记为 1.4 秒，原始 60 Hz 采样各 85 个。
这不被碰撞模型的 18 tick 生命周期截短。原自动 seed 使用旧采样器的可重复一次实现；
不能据此声称复现每次原客户端的随机粒子分布。

独立 schema 为 `original-d15-stomp-source-only-recovered-v1`，明确记录
`sourceOnly=true`、`runtimeBound=false`、`nativeParityVerified=false`、
`appleGPUVerified=false`。其中没有 `version`、`profileID`、`profileSHA256`、
`characterSHA256`、`erlangModelBindings`。原模型轨迹放在 `sourceModels`，原事件只作为
来源收据保存，不成为某个当前 fighter 的动作绑定。

当前 App 固定读取 `SF3_D15_StompEffects.json.gz`、核对完整 expected SHA，且解码必需
`version/profileID/characterSHA256/erlangModelBindings`。因此新文件名与缺失必需字段
共同阻止该 source-only 输出被当前 loader 消费；`runtimeBound=false` 只是准确声明，
本身不是 App 的安全门。即使误改文件名，现有身份和结构检查也不满足。

## 执行与检查

首个尝试在 Texture2D 元数据写入阶段因原 `bytes` 无法直接 JSON 编码而退出，耗时
4.394 秒；只留下输入缓存中的一个原 raw 对象，尚未转换发射器或产生清单。
该失败目录与日志保留，未覆盖。修复上述显式字节投影后，在新的 v2 目录完成一次完整
成功转换，耗时 5.378 秒。没有重复下载，也没有再次运行成功的整包转换。

新增 `test_erlang_stomp_recovered_input.py` 共 5 项检查通过，unittest 耗时 4.159 秒：

1. recovered 输入若夹带 profile、未审 material metadata、缺失 splits 或错误格式，在读取前拒绝；
2. 完整模型 SHA 与全部 typed source recovery 精确联接，改变 archive 身份、数字类型或模型字节均拒绝；
3. 错 CAB、改原对象、改 mip 类型、截短或改纹理流均拒绝；
4. 新输出的 schema、文件名及缺失运行时绑定字段符合 source-only 边界；
5. 一次独立原件读回核对原网格顶点/面、三个 emitter 原字节、完整生命周期、shader 原表达式、
   所有派生资源 SHA，以及两张原纹理全部 20 层 mip 字节。

读回复用旧测试中两个纯原件比较方法，没有执行旧 profile binder、没有重生成已经成功
生成的材料，也没有运行 Swift、Apple GPU 或原客户端。静态比较另外确认历史清单、receipt、
effect 和 event binding 的原 dict 表达式保持不变。原历史输入不全，因此未冒称重跑了旧入口。

## 未完成边界

本次未恢复完整 Wu 动画 profile、原运行时大脚 manifest、302-file 基底或 440-file 候选。
没有证明实际原生 a46 附着/缩放/生命周期全等、当前 App 的显示效果、帧率或 Apple GPU 通过。
生产 App、Identity、workflow、私有 gate 和 TestFlight 均未修改。

其他三个导出器本轮只列依赖，没有实施：

- Sword 尚需新模型/held 身份接线、旧两材料与两组纹理派生收据的独立严格恢复，以及真实 profile 绑定；3 个 Noise 层仍不支持。
- Skill 尚需真实 eye clip/head FK/release 所在完整 profile、材料与纹理/mesh 派生收据。期间另一工作分支已恢复准确 `08db602bdc0f7c37fd88caf15e23217e.bin`，因此原 bundle 缺失不再是当前阻塞。
- Hound 的 438,144 B 原 GLB 已按旧 SHA 完整恢复；该 FX exporter 不消费旧 hound candidate JSON。其余缺项为真实 profile 绑定及尚未完整恢复的 shared shader/material/external-object 输入。
