# D15 哮天犬原始特效接入

本批将哮天犬的两个原始特效接入独立 D15 资源加载器与现有 Metal 透明绘制队列。源材质、贴图、网格和曲线均来自已核对的本地原件；没有新下载或生成替代素材。H17 的默认身份约束和采样路径保持原样，D15 必须明确选择独立且严格限定的加载分支。

## 来源、产物和时钟

原始 bundle `4f9476ea1326d7c102950a772ee44020.bin` 的 SHA256 为 `971b3a1ea36eaaebaea4ae73a56ed65d8ffc4383625a06d64a209d8a70fbbd90`。两个 prefab 为 `D15_dog_smoke(spine_root_joint)` 与 `D15_dog_smoke_startEnd(spine_root_joint)`，共 9 个原始 emitter。

实际 `SF3_D15_Effects.json.gz` 为 99,987 bytes，SHA256 `c268e9989be0c86161bb008c7d7ec93b58541f05b4cc40a2c58ac02ef7335ca4`；未压缩 JSON 481,380 bytes。它含 42 条在原模型寿命内可达的粒子 track、6 个原材质和 25 个逐文件核验的贴图/着色器资源。完整原始 emission schedule、自动随机种子的一次确定实现及原对象身份保留在私有采样收据中。较早仅按静态 prefab 采样的试作产物已被本候选取代，不作为验收结果。

收据 `d15-hound-fx-receipt-private.json` 为 129,959 bytes，SHA256 `c0415fae57240ea9c942cc51f732ac3d19a5b4d1b37840d99f4fc73dc1d1f614`。它绑定已有犬 GLB SHA256 `22a9292b5fa62ae1a64d91cd7e840632119afd62a7c21d8485b5b9de011bc236`、真实 60 帧裁剪、119 个样本和原 AnimationEnd tick110。本次人体身份为最终 v8 GLB SHA256 `c29f9a9189eb4aacae2a25b4433e88498deee4a0e434a90969c7ce3923fbce5e`。

lock1433 在 Hide IntervalStart tick0 启动循环烟雾及第一组过渡粒子，在 Hide IntervalEnd tick56 启动第二组过渡粒子；循环烟雾的源 Shift.Y 为 −120 cm。AnimationEnd110 销毁烟雾与犬模型。展示只读取 `erlangLiveTick`，暂停和命中停顿不独立推进粒子时钟；回合结束清除实例。

## 修复动态骨骼下的世界速度

三个烟雾 emitter 明确声明 world-space 速度，另外含 2 倍或 4 倍的 X 轴粒子缩放。原本的通用静态 prefab 采样不能将这股世界向上速度直接交给旋转中的犬骨骼，否则风向会随骨骼转向。

本批只在 D15 显式启用逐样本附着旋转，将世界速度投影到实际犬 GLB 的源骨骼/发射器/粒子缩放坐标。local-space 粒子使用当前骨骼姿势，world-space 粒子保留各自出生时的骨骼姿势。所有仍在寿命内的原始出生均保留，超出模型终止时刻的出生不生成运行时轨道。原循环周期大于模型可见寿命，未把后续循环复用到不同出生姿势。

精确方向检查在原 `50 cm/s` 世界向上速度、`simulationSpeed=0.5`、非均匀缩放和 90° 旋转下测得：0.4 秒后旧静态基底得到约 `[-10,0,0] cm`，新投影得到约 `[0,10,0] cm`。另按连续转向解析积分核对，并在真实犬 source ticks0/30/70/110 核对同一向上向量。

## 运行时接线

`DuelErlangHoundEffectAssets` 要求 Wu 的精确角色身份、相同 hound 物理 track、精确压缩文件散列和全部源文件散列。它只接受上述两个原始 prefab、9 个源 emitter、60 Hz、厘米到米 0.01 比例，不接受 H17 marker/model/companion 冒用。源材质/着色器/纹理沿用已恢复共享缓存的原字节，文件名中的历史缓存前缀不改变其原始身份。

实例键包含 owner、model ID、源 binding 和 track。D15 的透明绘制项在排序前加入既有 H17 队列并重新编号 emitter，保留原 render queue、sorting order、sort mode 和深度规则；总预算仍为 1536，超出时失败而不静默丢粒子。

整合时 `DuelWeaponAssets` 需在已验证的 Erlang companions 后加载 `erlangHoundEffects`，使用 `DuelErlangAssetIdentity.houndEffectsSHA256`，并将其 `verifiedFiles` 加入内容身份核验。World 的新 hook 读取该属性。最终 profile 合并其他模型后，可用 `scripts/bind_erlang_hound_effects.py` 仅重绑定精确 profile/character 元数据；它要求犬轨道逐值相同，保留所有粒子、材质和贴图字节，输出到新目录。

## 实际验证与边界

本次新增三个 Python 检查通过，耗时 1.662 秒，覆盖实际产物/全部文件散列、源模型寿命以及静态和动态世界速度。随后只运行新增元数据重绑定检查，耗时 3.286 秒，通过并拒绝被更改的犬物理样本；未重复先前三个检查。

五个独立 Swift 纯时钟检查已通过：tick0/56 触发、local 当前姿势与 world 出生姿势、周期间隙和原模型结束。修改后的五个 App 源文件通过 Swift 6.0.3 语法 parse；独立静态复核未发现阻塞。此环境没有执行 Apple SDK 类型检查、SceneKit/Metal 原生绘制或设备截图，不把离线检查记作原生视觉通过。

采用原自动随机种子的一次确定实现，未声称跨引擎逐像素一致。其他 D15 能力的可见模型/粒子由后续批次接入；Noise、ExternalForces、SubEmitter、Trail 等未适配模块会拒绝导出，不能静默删掉后声称完整。犬的原皮肤着色器与完整原生事件提交顺序仍不在本批等价性声明内。
