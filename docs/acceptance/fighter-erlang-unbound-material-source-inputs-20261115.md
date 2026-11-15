# 二郎神未绑定粒子层：六个原材料输入恢复

## 实际结果与范围

从现有、完整 SHA 匹配的原始 bundle 完成六个 Material 的 source-only 导出：六个原关键词集合分别唯一匹配一个原 GLES 程序，复用现有 `selected_program` 与 `erlang_source_metal.translate` 生成对应 MSL。没有修改这两个公共辅助函数，也没有放宽原材质状态、关键词或程序身份检查。

本批同时保存十条原 ETC2 压缩纹理链及全部 81 个 mip。八张纹理为原格式 47（ETC2 RGBA），两张为格式 45（ETC2 RGB）；后者解码表示明确补入不透明 alpha 255，原压缩字节不变。包括长方形纹理及 4×4 以下的完整块尾，没有生成 mip、重采样或执行色彩空间转换。

导出状态为 `exported-source-only`，六项成功、零项 unsupported；`runtimeBound=false`、`completeParticleEffects=false`。它不提升当前飞剑 17/20、Eye 15/19、Earth 15/19 或 Meditation 8/9 的运行时绑定数量。Stretch、Noise、模块组合顺序、世界空间出生历史和运行时顶点流仍属于独立未闭合范围。

## 原材料与选定程序

所有选定程序均为原 subshader 0 / pass 0。表内 blob 为原压缩 shader 程序表的索引，不是推测的新 variant。

| 原 Material | pathID | 原 Shader pathID | blob | 原 GLSL SHA-256 |
| --- | --- | --- | ---: | --- |
| mtl_gradient_aBlnd | -2157749360310989314 | 4659798091178469451 | 31 | `64449a6385a7a19d851328309fc3cf15d362262b653599267ded206d937b82a6` |
| mtl_muzzle_noise | -1155837180958487824 | 7099477430120726890 | 54 | `2b86032a96348d73288e7e4a698d9b549362c26512d3e2e92378e7cac74a03c3` |
| mtl_energy_flame 3 | 8530189115646704333 | 7099477430120726890 | 53 | `1e0169db393b158e2a4b823d92f5d785864a5635b127ae4a1c25d7d5cc07eeda` |
| Sparks_1 | -4712904873042191220 | 4659798091178469451 | 35 | `57146962e3276ac8219d6caef9b415bb4997fb772bdbcf78be67a98aff8d7412` |
| mtl_energy_noise_gradient_1 | -3833188765227295071 | 4655989024510641494 | 41 | `3763bdddfa00bd1327b271c7140648e48ffcadc24796635119462e2627a17eec` |
| mtl_sparks_v4 | -3539672900455825089 | 4659798091178469451 | 57 | `69aafee8863f6149965f260e6775216f24f861f196d48e978942d8aafd03d2e8` |

前三个 Material 来自 `743fc535f600cb6addb0c2d20c96a9ab.bin`，后三个来自 `ff1080526339a7afed2acb60ee537859.bin`；原 Shader 来自 `b77cd85962dab26b5e542811e8599be3.bin`。准备器固定完整包、对象 raw SHA、材料名称、完整关键词集合和具体程序元组，并同时核 PPtr 的 pathID 与外部 CAB，避免只按重名对象或可编辑元数据装配。

转换产物保留各材料真实混合因子、剔除与深度状态；原解析后的 pass 状态与 properties 另有独立文件。MSL 接口仍是既有粒子转换器的受限接口，没有据这些程序反推未闭合的 Stretch 顶点或 Noise 轨迹。

## 原纹理完整范围

| 原 Texture2D | pathID | 尺寸 | 原格式 | mip 数 |
| --- | --- | --- | ---: | ---: |
| mask_quad_009_clamp | -5605429874853356512 | 256×256 | 47 | 9 |
| VFX_MuzzleFlash_2 | 965847529922942018 | 256×128 | 47 | 9 |
| mask_grad_019 | 3786051072325781169 | 256×64 | 47 | 9 |
| Big_Expl_rays_bw_01 | -8666170619262010817 | 256×256 | 47 | 1 |
| mana_noise_001_alpha | 2639016644056759067 | 512×512 | 47 | 10 |
| gradient_noise_003 | 3636411242617834560 | 1024×512 | 47 | 11 |
| noise_clouds_002 | 5890043092355976909 | 1024×1024 | 45 | 11 |
| fire_noise_a_03 | 7062348484569995484 | 512×512 | 45 | 10 |
| caustic_noise_010 | 8106364428363554812 | 512×512 | 47 | 10 |
| Big_Expl_rays_bw_02 | 8622200343931352576 | 256×256 | 47 | 1 |

前三张来自 `e0827787798b68df283fc2391b8d7f11.bin`，其余七张来自 `9d3e616ea68b083cc7b1b8b92e5f72a8.bin`。原压缩链合计 2,556,144 B；解码 RGBA mip 合计 13,718,872 B。收据逐层保存原偏移、压缩长度 / SHA、解码尺寸 / SHA，同时保留原 sampler、色彩空间整数、完整 Texture2D raw 对象和选定的可序列化元数据。

## 项目上下文与限制

使用同批原 Android `globalgamemanagers`，完整 SHA 为 `1ddbe17aab3a2997a1913e122eb9099da5ed17b94aff84fecd288914fecb2e0f`。PlayerSettings 仅核既有 raw pin 及偏移 256 的 `m_ActiveColorSpace=0`，没有声称完整 typetree 已解析。QualitySettings 完整解析保留全部质量档；原序列化默认档为 0，其 anisotropicTextures 为 0。其他档的值也保留，没有将它们重写成 0，也没有声称已核实时运行所选档位。

UnityPy 固定为 1.25.4。原包读取出现 `6000.3.11f1` fallback 警告，回执明确 `originalUnityEngineVersionVerified=false`。这些 parser 参数、source-only 转换及下列检查不构成 Apple MSL 编译、GPU 或原客户端执行结果。

## 可复现入口与验证

准备器仅接受本地输入，新输出目录必须为空且位于仓库之外：

```sh
python3 scripts/prepare_erlang_unbound_materials.py \
  --source-bundles <restored-source-bundles> \
  --shared-bundle <source-inputs>/743fc535f600cb6addb0c2d20c96a9ab.bin \
  --output <private-new-output>

python3 scripts/test_erlang_unbound_materials.py --candidate <private-new-output>
```

实际完整导出 exit 0，耗时约 3.8 秒。只运行本批六项定向检查，全部通过（0.094 秒）：逐项保留六个原程序主体算式；十条原流 / 81 mip 完整性；关键词、程序身份与跨 CAB 拒绝；长方形及 RGB 小块尾、截断 / 追加拒绝；转换与后续 uniform 失败仍标 unsupported；完整文件 inventory 与非运行时声明。检查只读已导出像素，没有重复解码，也没有运行既有全套。独立代理完成准备器的窄静态审查，无确定阻塞，未重复执行导出或测试。

私有主收据 `erlang-unbound-materials-source-only.json` 为 108,696 B，SHA-256 `78bdc61679ae08437380d74ddfee00fda16a07d3db8ea28e44b0e3b0e663b1d8`。它核对 149 个依赖文件，合计 16,431,453 B；主收据自身不计入该 inventory。原 shader、派生 MSL、纹理和像素均留在私有目录，没有加入公开仓库。

本提交只增加准备器、定向检查和本文。没有修改运行时白名单、粒子算法、App、中央资源身份、工作流或发布清单；没有新网络下载、GPU / 原客户端运行或上传。
