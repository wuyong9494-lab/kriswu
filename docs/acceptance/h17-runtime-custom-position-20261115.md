# H17 原材质运行时 `_CustomPos` 装载修复

## 已确认问题与范围

基线提交 `68f1e7de45351c3e4b2607c56ff8ab111d0c7130` 的 [Apple 运行 43644209347](https://github.com/wuyong9494-lab/kriswu/actions/runs/43644209347) 实际执行了 9 个原生方法：`DuelTriadRootVictimAudioTests` 的 5 个方法通过；3 个 `DuelTriadFloorfallIntegrationTests` 和 1 个 `DuelSharedRootInstalledModelTests` 均在共同装载入口抛出 `descriptor("Missing original uniform: _CustomPos")`。独立 UI 方法在 `ember-practice-ready` 失败，辅助功能树包含 `duel.resourceError`。这不是 9 个方法全部失败，也不是工作流仅仅 completed 或 skipped。

这次修改只解决真实原材质描述被错误拒绝装载的问题。它没有修改原材质、原着色器、角色 GLB、加密资源、解密密钥或发布资源版本。Metal 编译、像素表现、实际音频与 iPhone 真机验收不能从描述验证通过推导。

## 完整入口与字段来源

调用链是 `DuelWeaponAssets.init` → `DuelTriadEffectAssets.init` → `DuelTriadSourceMaterial.Descriptor.validate()` → `materialUniforms()`。最后一步原先只接受纹理 `_ST`、已保存的 float/color 和导出器保留的 ShaderLab 默认值。失败发生在 `DuelTriadEffectAssets.prepare` 的 Metal 编译之前，也在惰性的 `assets.character(for:)` GLB 装载之前。

对 final v2 `SF3_H17_Effects.json.gz` 的全部 62 个材质，按上述真实优先级枚举后，唯一未绑定字段是 `_CustomPos`：17 个材质引用这一标量，涉及 7 个原着色器对象。其来源均经过以下核对：

- 17 个原材质 `m_SavedProperties` 中没有 `_CustomPos`；导出的 `floats` 和 `colors` 同样没有该项。
- 7 个原 ShaderLab `m_PropInfo.m_Props` 中没有 `_CustomPos`，所以不存在遗漏复制的 ShaderLab 默认值。
- 原编译 GLES3 程序声明了无初始化器的全局标量 `_CustomPos`，片元计算实际使用 `clamp((worldY - _CustomPos) / _Grad, 0, 1)`。该字段不是可以删除的无用声明。Metal 资源保留了相同计算。
- 原材质、着色器对象与既有绑定报告的 SHA-256 相符。7 个原对象的完整哈希及 17 个材质的元数据哈希见同名 JSON 记录。

final v2 资源清单 SHA-256 为 `e5c0ccaeef85ce86c5b8fd4ee64524794d6556f5a561f4078362f6899bedf4e5`；effects 清单 SHA-256 为 `ce7350283846c370e00df073d2c04146687301c095a1be4b6f19aece982f2435`。原 shader bundle SHA-256 为 `c0b1fe09ba0684e474297ade8dcd7fee7b5d2e780236029c544c1986dea1e972`，H17 effects bundle SHA-256 为 `f8623b6aeff0dbdee43818437043096ab5afb217e7564c3298f182e420e9f9d7`。

## 修复依据与尚未确认的运行时行为

[Unity 2021.3 官方说明](https://docs.unity3d.com/2021.3/Documentation/Manual/SL-PropertiesInPrograms.html)区分序列化材质属性与运行时属性：实例属性优先于材质属性，之后才读取全局属性；各层均未赋值时，浮点属性由引擎提供零初值。属性不出现在 ShaderLab `Properties` 中，并不代表着色器不能读取它。原 GLES3 声明的零初始规则也与 [GLSL ES 3.10 §4.3.5](https://registry.khronos.org/OpenGL/specs/es/3.1/GLSL_ES_Specification_3.10.pdf)一致。

本次改动仅将这一**未赋值时的引擎初态**显式写入当前 Metal ABI。必须同时满足字段名 `_CustomPos`、宽度 1、已审核 `shaderPathID`、对应完整 `sourceShaderSHA256`。原有显式 float、color 和原始默认值继续优先；任何其他缺失字段、错宽度、未知来源或变更过的原 shader 身份仍抛错。没有增加通配的“缺什么就填零”处理。

另一次只读原客户端审阅追踪了 10 处已映射的 `Shader.SetGlobalFloat` 调用、8 个实际方法，其字段为 `_MipMapBias`、`_Gamma`、`_RimPower`、`_DissolveBlendValue` 和 `_DissolveWeaponBlendValue`。整数 property ID 通过原静态构造函数还原，没有按名称猜测。`AppearAndDisappear` 的材质写入是 `_appear` 和 `_hitBlocked`。通用 `ShaderParamsRandomizer` 可以从序列化名称数组写入属性，但当前 36 个 H17 prefab 的 36 个 MonoBehaviour 均为同一个 effect 控制脚本，字段中不存在该数组或 `_CustomPos`。

这些排查没有定位到目标 `_CustomPos` 的动态 setter，**不能证明所有原场景、间接调用或动态生成名称都从未写入它**。本修复不宣称恢复了未知场景的动态全局控制，也不将加载成功升级为原游戏效果完全一致。该剩余边界保留待验证。

## 最小改动与验证

生产改动仅在 [DuelTriadSourceMaterial.swift](../../App/Services/DuelTriadSourceMaterial.swift) 的 `materialUniforms()` 与同一描述类型的 7 项审核表；没有改变纹理、shader 程序、光栅状态、几何、角色身份或任何原资源。

新文件 [DuelTriadRuntimeUniformTests.swift](../../Tests/SiteTests/DuelTriadRuntimeUniformTests.swift) 只有两个方法：

1. `testInstalledSourceMaterialsResolveOnlyReviewedUnassignedCustomPosition`：严格匹配 final v2 安装 pin 与 effects 清单哈希，实际解出 62 个材质，逐项执行真实描述校验；确认只有已知 17 项/7 原 shader 的未赋值标量采用引擎初态。
2. `testUnreviewedMissingUniformsRemainRejectedAndExplicitValuesKeepPriority`：基于实际 17 个描述，逐项验证错 SHA、错 source ID、错宽度、未知字段和被删去的真实保存标量仍拒绝，并验证显式 float、color、原始默认值的原有优先级。这些是两个 XCTest 方法，循环断言不另计为测试方法数。

Linux Swift 6.0.3 定向检查先使用旧生产描述逻辑，两个新方法中一个以相同 `_CustomPos` 异常失败，另一个严格拒绝边界方法通过。最小修复后为 **2 方法执行、2 通过、0 失败、0 跳过，0.233 秒**。该检查使用生产 `Descriptor`、其验证依赖和未改写的两个 XCTest 方法主体；仅将 Apple bundle 读取替换为已认证的现有私有元数据输入，并去掉与描述校验无关的 Metal 类型部分。两份完整 Swift 源文件另经语法解析。

因此上述结果属于 **Linux 描述逻辑回归与 Swift 语法验证**，不是 Apple native、SceneKit 或 Metal 运行结果。原生后续执行范围为先前失败的 4 个资源方法加本次新增 2 个方法，合计 6 个；独立 UI 方法另计 1 个。先前已经通过的 5 个合约方法和旧 117 方法不重复执行。新 Apple 结果应独立登记，不能以此处的 Linux 通过替代。

生产文件 SHA-256：`efb78001996c8e66721cafbcdb99765b3af9d4ca17e827385ca6d3968ef75856`。

新测试文件 SHA-256：`e982e1ab17702552571a2fc8b00445039cf9e217ad615bf122074e67ece7b3ac`。
