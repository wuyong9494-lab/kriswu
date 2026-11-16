# 吴庸／二郎神：恢复媒体与颈桥 v2（2026-11-16）

## 当前冻结候选

当前交付是 `erlang-neck-v2-final` 与 `erlang-runtime-contour-v2`。本页后面的 v1 记录只表示恢复及回归输入，不是当前角色身份。

**已修复颈部连接与动态边界；源肖像白衣剪边仍可见。** 最终 front、side、threequarter 三视图已实际生成并查看，原肖像关闭新增桥后的对照图也已查看。三分之四角仍有白衣剪边和局部形体折线，未记为整角色最终视觉通过。原肖像和原衣领没有为抹去该边缘而改动。

最终角色保持全部 **62 个源动作、15 个独立模型轨迹、36 条能力攻击规则**。Blender 对每个动作的起点、中点、终点共 **186 个实际变形姿态**进行了边界对应检查：头部最大距离 `9.547868558001937e-7 m`，原衣领顶点最大距离 `0.0 m`。最终媒体有 **255 项文件引用、230 个去重后的实际媒体文件**：82 个原 WAV 与 148 个 FX 文件，总计 31,000,185 字节；GLB、profile 和各 manifest 另计。

`DuelErlangAssetIdentity` 的整包生产 pins 及音频旧 schema 1–4 不变。本批 D15 资源保持私有候选；原生私有 Metal、实际声音播放、完整对局包和真机显示验收仍未覆盖。

## 最终身份

下表全部是当前 `erlang-runtime-contour-v2` 中的实际文件。JSON 与 gzip 的身份分别记录，加载器应使用对应实际字节的 SHA。

| 当前文件 | 字节 | SHA-256 |
| --- | ---: | --- |
| `WuYong_Erlang_D15_Recovered_Combat.glb` | 18,956,368 | `2957d7861b2ee7656945259dd273f241591ce55f71d364dab007a9bc372d76f6` |
| `SF3_Erlang_Profile.json` | 18,924,587 | `05ebdc38393bb55b7053a4664f317f81d0c2532bd43c8c50bb313cc513b18d03` |
| `SF3_Erlang_Audio.json` | 232,542 | `c5992bbf314d3fd28f97a3c63be24a6b976cfd736711eb355e0def809ac52176` |
| `SF3_D15_Effects.json` | 481,357 | `ebb43d6fafa1640cbe3c0852213adbf5a3384c8c5aff61c2d57aea4ecb24b4c2` |
| `SF3_D15_StompEffects.json` | 511,940 | `435a0ab1dbefd81adaf7f6b92809b047fdef5b16d8566da91777d852f4ce0ba0` |
| `SF3_D15_SwordEffects.json` | 2,315,422 | `4140b6f2d8741863bfb749172dec1fa362eff4d3f106b56fc3ff1259ef5bf906` |
| `SF3_D15_SkillEffects.json` | 2,811,395 | `acfc53c1a6375b48a34522c6c99876a621bb213692bf851744f35d0f10749acb` |
| `SF3_D15_Effects.json.gz` | 99,986 | `9ebe58b943939620f0157e3a4c36e373fb7cf341c38de9ab5d4c6597cdb52cf7` |
| `SF3_D15_StompEffects.json.gz` | 198,507 | `a5e56224936aa308d2f2d87f8e8e8c804db19a13f1b17032b24ba38270d7b5e6` |
| `SF3_D15_SwordEffects.json.gz` | 706,932 | `2332b6a44a1d33affdfdb7574c1478f6671288e94f7479c734c026c778a5f1bb` |
| `SF3_D15_SkillEffects.json.gz` | 356,331 | `33da9b5606f79b5989747cdd1c140d669ba76c47ea3613addfa46d1cce1d4857` |

`rebind_erlang_contour_media.py` 只改变已恢复清单中的当前角色 SHA，以及音频清单的当前 profile SHA；原 PCM、粒子采样、模型轨迹、着色器、纹理、时钟、条件、未播放音频与未绑定发射器记录全部保持一致。新的源恢复出处仍是原来的真实文件：音频输入 `07d582bf8eb888424bb64939c2f469f4dc0e9536e6b58acc5c51fbaed307928e`，62 动作恢复 profile `bb058e221c6402c3c1562e0c18c2f24970682d73b8052ef372e09c194c7604ff`。

## 颈桥 v2 的修复与保存边界

`bind_erlang_personal_neck.py --recovered-source --source-contour` 只接受固定的恢复源身份。新增 `erlang_personal_neck_contour.py` 处理原开口；不修改公共 GLTF 运行时。

原肖像的 59,878 个顶点、法线、UV、索引、原图像及节点保持不变。原 16,324,652 字节 BIN 前缀逐字节相同，原全部 accessor、mesh、material、image、texture、sampler、skin 和 62 个 animation 记录保留；人体、投技、技能和独立模型规则也未改。新增桥共有 **3,667 个顶点、2,947 个三角形**，复用原 skin；新增适配与源资源身份明确分开。

真实开口按精确 float32 位置及原三角面半边关系解析，共 182 条边、181 个不同位置；没有用半径或坐标舍入合并原顶点。唯一四度触点按原面扇区消歧后，包含 172 边主开口和 10 边反向局部微孔。微孔以其原位置、法线、连续 UV 和原肖像 material 加 8 个三角形局部封口；主开口才接向衣领，避免把微孔拉成长褶。

桥的内部采用固定真实上下边界的谐和光顺。源剪口的细碎凹凸没有继续被拉到整个颈部；首尾 UV 分裂处共享几何法线。顶部按每条原边各 32 个样点读取真实 UV，保留 15 处 UV 岛两侧的端点，未跨岛拉伸整张皮肤图。源色与源法线分别在桥顶端高度的 4% 和 2% 范围内过渡；这是毫米量级的**个人适配工程选择**，不是原游戏参数。原白衣剪边仍保留。

原先在衣领三角形内先插值位置和权重的方案，在真实 idle 下产生最大约 4.48 mm 的动态差。最终方案改为围绕真实 neck 轴的原 body 面片边界：**15 个原顶点及完整 POSITION／JOINTS／WEIGHTS 原样复制**，用变数量三角连接到新增内圈，并复用原衣料 material。最终 body 边界没有该动态差；只有新增内部拟合顶点存在记录在案、低于 1% 的四权重尾项裁剪，原 body 权重与实际边界副本未裁剪。

Blender 4.3.2 默认 BLENDER bone heuristic 对缩放为 0.92 的 armature 改了 bone length，却未同步刚性骨骼子物体的相应补偿，曾造成全顶圈共同偏移 12.3376 mm。源 glTF 数学对应没有该偏移。检查改用 TEMPERANCE 导入选项，未手动移动模型或原对象；在该导入下完成全部 186 个姿态检查。此导入诊断记录保留，旧带错误导入的图片不作最终证据。

## 原声音恢复

六份缺失的已知原 bundle 按固定官方 APK ZIP entry 恢复，核验原 CRC、文件名、长度和完整 SHA，没有重下完整 APK。`recover_erlang_source_audio.py` 对照固定历史记录，恢复了 **82 个 WAV，7,074,406 字节**；完整文件 SHA、PCM 样本 SHA、采样率、声道和帧数全部一致，无重采样、增益、裁切或替代声音。

最终有 **119 组事件**：98 组 Common／Male、21 组已核实 Palace Stone；其中 108 个人体事件、11 个独立模型事件。声音 Frame 保持 `max(0, Frame)`，重复备选保持源选择权重；Birth、Attack、Idle、Rotate 使用独立源状态时钟。冥想保留原单次播放起停 trigger。未发现活动来源引用的 `d15_swords_explosion` 文件保留但不擅自播放。

实际 App `DuelErlangSourceAudio` 的 schema 5 严格检查恢复输入、当前 profile／角色身份、原配置、PCM、真实轨迹、事件与 Palace 上下文。schema 1–4 原 pins 不变，生产整包 pin 不变；丢失的旧私有 manifest 没有被声称逐字节恢复。

## 源特效恢复与当前绑定

| 范围 | 实际发射器 | 粒子轨迹 | 运行时文件引用 | 保留边界 |
| --- | ---: | ---: | ---: | --- |
| 哮天犬两份 prefab | 9／9 | 42 | 25 | 源 local／world 出生姿势、动态世界向上速度与原模型时钟保持 |
| 大脚踩地 | 3／3 | 3 | 9 | 原 1.4 秒粒子生命与碰撞模型时钟分离 |
| 飞剑 | 17／20 | 36，另四条历史 trail | 39 | 九种 Birth／Idle／单帧 Rotate／Attack 状态保持，三组 Noise 仍未绑定 |
| Eye | 15／19 | 247 | 三技能合计 100 | 原 head 目标、源 unmirrored 与基础套装条件保持 |
| Earth | 15／19 | 46 | 同上 | 原 captured pelvis 与碰撞 anchor 分离 |
| Meditation | 8／9 | 21 | 同上 | 原 model Parent chest、3 cm source shift、Initialize 时钟保持 |

本表范围合计 **67／79 发射器、395 条粒子轨迹和四条历史 trail**。它仅表示本批已明确枚举的范围；其它条件 prefab 和余震尚未据此闭合。

犬缓存按真实 PPtr、外部 CAB、对象类型与原 Material raw SHA 重新建立：70 文件、3,590,951 字节，六个材质、九个 Texture2D 和一个原网格。原 `prepare_erlang_hound_effects.build` 没有改写，实际生成 2,225 个样点。新恢复共享网格 entry 为 5,043,334 字节，原 CRC 和 SHA 均校验；犬 GLB 的 438,144 字节原身份保留。

Eye／Earth／Meditation 本批实际恢复并绑定了既有白名单的 **38 组发射器**，不是只列出待办。`recover_erlang_skill_effects.py` 复用既有三个采样器；Eye 只是机械抽出采样函数，源采样语句已与原函数作结构比较，算法未变。原对象、26 个实际引用的材质、10 个网格和原纹理／GLSL／对应 MSL 已恢复。原材料表中唯一未被这 38 个 renderer 引用的额外输入未被冒充为使用层。新恢复冰纹理 entry 为 869,815 字节，另两份所需原包在旧本地资料中找到。

模型候选、1432／1438 完整源 trigger 字段均用固定 SHA 验证。基础套装条件、Eye 释放 tick 122、Earth 释放 tick 39、独立模型结束 tick，以及 Parent／owner 目标没有用碰撞位置或人体动作替代。三技能全部 **9 个原未支持发射器**仍列在清单里，三份 scope 的 `completePrefab` 保持 false。

## 已执行检查

| 检查 | 结果与证据 |
| --- | --- |
| 早先真实恢复输入检查 | 10 项通过；覆盖 v1 原肖像／62 动作、82 PCM、119 事件、拒绝错误时钟及两份 source-only FX 不变性 |
| 犬恢复 | 3 项新源输入检查与 1 项既有定向运行时检查通过；`erlang-hound-input-checks.log`、`erlang-hound-runtime-checks.log` |
| 三技能恢复 | 5 项通过，3.460 秒；源对象／缓存／scope、真实网格及 winding、26 个 GLSL 算术与 opaque stone、真实源时钟及条件拒绝；`erlang-skill-input-checks.log` |
| 最终 v2 与等价重绑 | **7 项通过，9.108 秒，零失败、零跳过**；`erlang-contour-completion-checks.log` |
| 最终实际动画边界 | **62 动作、186 姿态通过**；`erlang-neck-v2-final/source-boundary-poses-private.json`、`erlang-neck-v2-final-poses.log` |
| 实际 App 音频 loader／clock | 最终新 profile、schema 5 manifest、82 个实际 WAV 上 **7／7 通过**；`erlang-loader-check/checks-contour-v2.log` |

最终七项 Python 检查包含：原 BIN／肖像／动作不可变、全部 182 个源开口边覆盖、15 点衣领完整源 skin attributes、源法线及 15 个 UV 岛端点色值、实际动画 receipt、媒体所有字节／时钟／缺口不变性，以及**重新生成旧 v1 后 GLB/profile SHA 仍完全相同**。准确执行命令和实际日志身份另存于私有测试 receipt，未为归档而重跑。

Swift checker 使用真实 App loader／clock 源码，仅补 `import ShiftCore`，复用现成 ShiftCore 构建对象。SHA-256 适配只有系统 hash/read 接口，没有重写 loader。最终运行前再次确认 loader 源码与冻结 App 文件一致，SHA 为 `a9760f91787c22665c7768f3e89096992bfacdad76e559991a591d11d1e84226`。七项覆盖真实 82 PCM／119 时钟、Palace-only 地面与迟到 context 不重播，并拒绝错误 Floor、减一声音 Frame、旧私有清单冒充、改写源 profile、Birth 借用 Attack。此结果是 Linux 加载／时钟逻辑检查，未包含 Apple 音频播放或 GPU 绘制。

原始不完整输入、缺少依赖路径和不支持的 denoiser 等早期失败不计通过。已通过结果保持原日志，不用新执行覆盖历史证据。

## 尚未绑定或验收的边界

已逐一核对实际通用离线粒子采样器和 App 绘制入口。Velocity／Clamp、犬的 world 出生姿势和剑的历史 trail 有真实可复用实现；未发现可直接关闭下列缺口的原实现：

- 飞剑三组原 Noise 发射器：缺原 ParticleSystem Noise 算法、随机映射及组合顺序；还同时含负 Stretch、pivot／flip，其中一组为 world 粒子。六份未绑定层材料和十条纹理链实际存在，缺口不应误写为所有材料缺失。
- 三技能九组遗漏：七组有符号 Stretch；Earth 另有 Shape6 空 Mesh PPtr 与 alignToDirection。旧通用 Stretch 取绝对值，不能据此宣称保持这些源参数。这里与剑合计十个 Stretch 层，不能重复加到十二个遗漏发射器的总数上。
- 飞剑原 HIDE 淡出、其它条件／镜像／地面 prefab、余震 start 的 EffectsManager／ground locator 完整父级生命周期、旋转／缩放／附着仍未闭合。
- 私有特效的 Metal 编译与 Apple 绘制、实际原音频播放、整包 match identity、完整对局和真机显示仍待验收；源白衣剪边与局部形体折线仍可见。

所有上述遗漏和未验收标志均保留。没有新增替代声效、伪造原特效、放松源身份 gate 或更新生产整包 pins。

## 历史 v1 与归档

历史 v1 为 226 顶点、448 三角形的椭圆桥，GLB SHA `af7106eea49691b3057772203907a5a350947e68403e0e0e8b69de9c8d082431`，profile SHA `c5bbe34d04d4efb59c46a122b3e1e35b1d196e79b394783fafadea4043103fbd`。它作为恢复媒体的固定输入与旧入口回归证据保留；当前交付身份使用本页开头最终 v2 表。

私有归档清单逐项列出最终 runtime、最终 neck receipts／图片、v1 固定重绑输入、源缓存、旧目录所需的小型原件、日志与测试 receipt，并给出每个文件的长度和 SHA。PCM、材质资源以及 GLB/profile 的重复目录通过内容哈希映射恢复，完整 APK／IPA 留在既有 checkpoint。checker executable、Blender 临时文件和 Python 缓存不进入新归档。
