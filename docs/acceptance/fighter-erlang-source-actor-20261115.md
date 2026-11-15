# 吴庸（二郎神）原始角色资源候选

本批交付的是可复现的真实角色资源转换与离线读回证据。角色身份为 `wuyong_erlang`，展示名称为吴庸／二郎神。用户确认了该身份；未附在 dot v23 包中的完整人体 GLB 不作为已取得交付。实际人体和长枪来自已核完整目录中的原始 D15 对象，个人头来自 v23 的真实肖像 GLB。

## 实际内容

候选模型 `WuYong_Erlang_D15.glb` 为 17,971,472 字节，SHA-256 为 `c29f9a9189eb4aacae2a25b4433e88498deee4a0e434a90969c7ce3923fbce5e`。人形候选 profile 为 17,512,021 字节，SHA-256 为 `0aef2b94f4678de19bb5df00ce67fe33eb6e60e6c31e25da31f47a035eacf205`。后续绑定召唤模型、规则和发布清单会改变 profile 身份；此处的 hash 只标识本批人形资产候选。

模型保留原始 64 节点人体、16 个武器附属节点、六块男性 D15 衣甲和一柄原始主长枪。长枪所属动作组是 `IMPERIAL_SPEAR`。旧 `SPEAR` 组的动作没有混入。左右原碰撞边均保留，用于配置明确选择的碰撞；这不表示画面中显示两柄枪。

56 段人体动作包含普通 Imperial 攻击、来源明确的移动／防御／受击／腿法、D15 人体能力动作、D13 唤犬的人体动作、六个原始双侧投技角色、原始重击被投镜像，以及真实单帧退变身。犬和其他独立模型的动作不借用人体骨骼。逐角色的原 alias、bundle、对象 path ID、原字节 hash、裁剪与时钟列于 `scripts/erlang_source_asset_receipt_20261115.json`；公有文件不含原始模型、动作字节或音频。

所有人体片段均有按实际导出 GLB 计算的 `head`、脚趾、骨盆及质心轨迹。`head` 共 6,556 个样本。源 `FirstFrame`、`EndFrame` 的正值按原索引规则减一，源声音 `Frame` 的原点另行处理，不能套用动画裁剪规则。

## 两个容易混淆的源语义

`Imperial_Spear_Heavy_Slash_Passive_Mirror` 的 `Mirrored=-1` 是原模型镜像状态的切换。它不是倒播，也不是只改变角色朝向。导出先在原局部姿态上进行半帧 nlerp，再应用已核的 rest-relative Euler 镜像。该 71 源帧动作存储 141 个 60 Hz key，完整播放 tick 为 140，原 AnimationEnd tick 为 132。便携计算使用 float64 中间量、float32 GLB 存储；未声称与原生浮点结果逐 bit 相同。未核实的奇异输入会被拒绝。

`D15_Avatara_Transform_Out` 是配置记录 133，引用 `w_imperial_spear/staff_idle.bin`。原动作有 62 帧；本配置仅使用源帧 0。导出的 `erlangTransformOut` 只有 **1 源帧、1 个 GLB key、1 个 FK 样本、playbackTicks 0、sourceEndEventTick 0**，没有复制末帧。其原 motion hash 为 `72da7978875aa9b288933add7c045cdc417938a6f9887a55d0e0efddcf7123e1`。Core 对该唯一来源的静态姿态支持独立集成。

源配置中不存在于原胶囊列表的 `Tight_Left`／`Tight_right` 保留其名称并记录 skip。原生方法 38174 调用 36245 后对未找到的名称直接继续下一项；没有把名称改成 `Thigh_*`，同区间确实存在的 Leg／Foot 仍参与碰撞。

## 个人头与颈部适配

v23 原肖像包含 59,878 顶点，但下部已经是嘴／下巴，不能将其误当可拉伸的脖子。完整原顶点、法线、UV、索引和三个嵌入图像保持原字节。原脸未被重画、拉长或重新贴图。

新增网格明确命名 `Personal_Neck_Bridge`：226 顶点、448 三角形，复用原 actor 的同一 skin，仅使用原 `head`／`neck` 两个关节的归一化权重。它在原 bind space 中生成，是个人头适配几何，不冒称 D15 原件。材质使用原肖像下部侧后方皮肤纹理取样得到的单色 PBR；原图像本身不变。

真实候选已通过 Blender CPU Cycles 离线绘制并逐图检查正常姿态、原被投后仰和镜像被投后仰。检查对象是实际 GLB、原动作和原材质输入。画面中原先可见的头颈空隙得到连接，面部和头部位置没有由第二套 skin 重新解释。渲染不是原生 SceneKit 或设备验收；原纹理／调色板已恢复，PBR 光照仍属于适配。

## 可复现入口与本批验证

`build_erlang_source_assets.py` 从有准确 pin 的本地原件构建人体、材质和普通碰撞 profile。`augment_erlang_source_profile.py` 可只从既有 GLB 增补 head／toe FK，不重新解码原动作。`append_erlang_mirrored_passive.py` 使用共享的 `source_body_mirroring.py`，增量导出被投镜像；`bind_erlang_personal_neck.py` 追加独立 neck bridge；`append_erlang_transform_out.py` 增量追加源记录 133 的单帧姿态，并复用已经验证的 55 片段 head 列。

本批仅新增运行 `check_erlang_source_candidate.py` 的四组实际读回检查：完整原肖像属性和图像字节、原 55 动画和二进制前缀、bridge 的原 skin 与两骨权重，以及单帧 GLB key 和实际 head／pelvis／toe FK。四组全部通过，没有重复解码原 55 动画或执行原生测试。此前的正常源动作转换和原音恢复没有重复运行。

命令接受私有输入路径及其明确 SHA-256；输出须为新的私有目录，不覆盖成功候选。原动作数组与材料原件只进入私有候选。源码依赖已存在的 UnityPy 1.25.4、NumPy、Pillow；镜像增量还依赖已提交的共享源镜像 helper。

## 后续集成边界

完整运行期还需将该人形身份与真实模型轨迹、源战斗规则、犬／特效、音频、三角色资源包统一绑定。D15 原音输入的 28 个 PCM 和 29 组 Common／Male markers 属于 D15 配置范围，不等于普通 Imperial、地面材质或全部共享行为的声音已经全部播放。原始音频事件、真正普通对战、原生渲染和 TestFlight 状态由对应消费者与实际运行证据分别报告。

本批没有启动 Apple 或 Android 工作流，没有上传 TestFlight，也不把离线资源正确性写成原生验收通过。
