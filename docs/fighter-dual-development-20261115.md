# 孙登／刘泉纬开发接续：根缚动作、命中反应与资源增量

本批以 GitHub `54bfc94dfdaca4a9ea8325e661cf5304525601f8` 为源码基线，继续实现角色行为与原始资源接入。冻结审计基线 `0d83323a5463b9f3feb57cc00532da2ade5a5c48` 保留原样。此次开发使用独立工作目录，没有修改另一个 Sites 正在处理的渲染、GLTF、武器资源与原生工作流文件。

## 已实现的行为

### 孙登根缚：受击者拥有完整的动作阶段

原 `lock_1777` 的受击者并不是固定在普通 hit 姿态。现在 `DuelTriadRootVictimState` 与 `DuelWeaponFight` 接通原始 Start → Loop → End 三段动作。三段分别使用 44、61、48 个原始帧，通过源 SHA、帧数、两倍采样时钟及 pelvis 轨道共同授权；单独改动作名称不能激活这项能力。

根缚持续变量结束时，状态保留当前动作，等待原 `Loop_Check` 或 `AnimationEnd` 条件。已恢复的 interval end 比较是 `floor(position) > EndIndex`，所以源区间 1 / 25 / 45 对应当前解释器 tick **2 / 50 / 90**；Start 与 Loop 的动画结束事件为 tick **78 / 112**。倒地音效使用的是 interval start 20，对应 tick **38**。这两类事件使用不同的边界，不能统一减一后直接触发。

切换动作时保留受击者自身 pelvis 的世界 X，对齐新动作，并用自身根运动继续采样。命中停顿冻结状态时钟；期间的新命中保留伤害结算，但不覆盖根缚姿态。过期或其他 root 的释放事件不能清除当前来源。End 的完整末帧被保留后，进入现有起身流程；回合结束清理状态与控制缓存。

**起身派发是当前应用的恢复选择。** 原版全局 `FOLLOWED_BY` 派发仍未完整复原，本批不把当前 getUp 接续称为逐指令还原。

新增权威状态进入规范回放编码，`schemaVersion` 从 7 升为 8，`rulesVersion` 从 11 升为 12。网络规则摘要构建器原本覆盖所有 `Sources/ShiftCore/**/*.swift`，因此新状态与行为会进入现有内容身份校验。

最终真实 catalog 探针已通过一次公开输入释放 branches，完整观察 Start（wall/live 459/459）、Loop（549/537）、持续变量归零但保留 Loop（659/639）、等待 10 live ticks 后 End（669/649），再进入起身（772/744）。End 的 tick37→38 标记和 tick94 末样本各出现一次，28 个 hit-stop wall steps 没有推进状态。全程 8 次接触，刘 HP 最终为273，未注入内部状态或修改资源/血量。详细结果归属[根缚回执](acceptance/fighter-root-victim-20261115.json)。

### 刘泉纬参考骨架：追加共享受击动作，不改变盘古完成状态

三段原 motion 已在现有缓存中找到，不需要重新扫描或下载大归档。每段的 58 个 source bone ID 均能对应刘自身节点；孙、刘的静止 TRS 不同，因此没有把孙的 FK、碰撞或骨盆轨迹复制给刘。

新增装配器 `append_cached_root_victim_motions.py` 按刘原骨架重新计算半帧 FK、双锤蒙皮顶点、15 个 hurt capsule、ground lift、pelvis 及 58 骨骼的 Float 质量中心。旧 56 段动作、原二进制前缀、节点、蒙皮、网格、材质、纹理、场景和控制角色保持不变，追加后为 **59 段动作**。

| 模型对象 | SHA-256 |
| --- | --- |
| 原刘双锤参考 GLB | `f83d8cbbd7b2158604dad9eff28398bcf57c64fdcb4146e5c142608484a5a472` |
| 追加共享受击动作后的 GLB | `a3aada76d336b9c4f9bda3904b5e947711d916f683a2dcbf7b8184377e01a517` |

独立复核从新 GLB 的动画 channel 重新生成三段共 **303 个**采样；pelvis 与其他生成轨道在约定的七位精度下逐项一致。复核没有读取孙的 profile，也没有再次运行装配。原 **8,403,480 字节 BIN 前缀**逐字节相同。

这里的角色仍是 `liu_hammers`，`isPangu=false`。共享受击动作、盘古逻辑测试、恢复到的 D19 配置，都不能替代盘古独立装备及专属动作。

### 盘古矛与升风：按原始反应边界修复

`lock1557` 区分矛的 Create 与 Miss 自由飞行阶段。模型在 tick8 创建，并不代表它立即脱离父角色取消规则。普通矛的 Create 到 tick60，强化矛到 tick50；创建期间发生有效反应会清除待发攻击及已形成的创建期攻击体，自由飞行后再独立存续。

普通矛伤害在 tick46 开始，故保留 14 tick 的创建攻击期和 50 tick 自由飞行，生命周期从 54 改为 **64 tick**。修复继续使用已有攻击体到期与 lifetime 字段，没有为这部分新增重复状态。

`D19_Upper_Wind_Blade_Model_Attack` 带 `Hit_No_Reaction`。现在它继续扣血与结算命中，但不会中断目标技能或安排击退。另一条普通源风刃没有该标签，仍保持反应逻辑。具体原字段、RED→GREEN 与最小文件改动见[盘古生命周期证据](acceptance/d19-released-model-lifecycle-20261114.md)。

### 音效：区间、角色归属与源数组变体

本批将既有七项原始身体倒地 WAV 接入资源版本。95 WAV 和原来 114 个标记继续复用；新增共享 root End 标记明确绑定刘的角色摘要和完整三段动作能力。加载器只允许该标记使用 `intervalStart=20`、`Common` 与七个独立变体，普通投技的共享音频仍沿用原 `soundFrame` 规则。

原生静态调用链进一步确认：`PlaySound.Position=null` 使用共享 AudioSource，`spatialBlend=0`；有显式位置才走另一条定位分支。现有二维播放器路径与这个 null 分支一致，特效的 COM 位置不能被当作音源位置。该结论来自方法 30175 → 30177 → 177256 → 177329 → 177330 的 ARM64 静态分析，不是 iPhone 听感验收。摘要见[原生音频语义证据](acceptance/fighter-floorfall-native-semantics-20261115.json)。

原动作使用 `UnityEngine.Random.Range(0, count)` 选择数组位置，重复元素保留权重。`DuelSourceEffects` 已把源角色音效从固定轮播改为 `DuelSourceAudioVariation`：根据类别和已接受事件序号取样，独立于战斗 RNG、渲染频率与墙钟；暂停、重置和媒体服务恢复不引入积压重播。它保持相同已接受事件流的选择可复现，**不声称复现 Unity 全局 RNG 状态或原随机序列**。

## 最终资源与加载闭包

最终版本为 `h17-shared-root-floorfall-20261115-v2`。在音频和动作接入后，完整引用核对还找到了暗影 Morph 与武器拖尾的旧刘摘要。这两份配置现在只更新目标模型摘要，材质、遮罩、投影、轨迹与继承来源不变；release 同步绑定两份配置的新摘要。

`DuelTriadSourceMorphAssets` 只接受原审核模型，或已独立证明仅追加三段动画的新模型；新模型还必须满足完整 victim capability。改名成盘古、更换装备、未知摘要或缺失原动作都会拒绝。当前 Foundation initializer 的 **11 个正负检查**已经执行通过，包括新 Morph 与原遮罩实际加载，以及把旧 Morph 绑定交给新模型时正确拒绝。该检查排除了 GPU prepare 与 SceneKit 节点绑定，不能当作 Morph 画面验收。两处材质颜色比例改为显式 `Float`，解决 Swift 6.0 的三元表达式推断编译问题，不改变源数值。

| 最终对象 | SHA-256 |
| --- | --- |
| Release / 独立构建 pin | `e5c0ccaeef85ce86c5b8fd4ee64524794d6556f5a561f4078362f6899bedf4e5` |
| Catalog | `fbd9ecbd9fb16de79c0240404e315af81d8cbbaa113b6042e6afc5ed7b1d0330` |
| Audio | `d13dbebea26a4759c3b5109ef12de957140b9056e6adc5fdf989b6a3321b3d90` |
| 加密增量公开 manifest | `d50b7fc6f711a55849b259b0f78d348612782f5e3765f9629db50291e20fe2b9` |
| AES-GCM 密文 | `fbf4e6b4e7f9777306a0bec62a39411a5deb5c2c4955975c397b015bf7ce7091` |

最终仅发布 **816,423 字节**的新密文增量和公开 manifest。13 项 payload 对应七个新增 WAV、六个替换资源；模型通过新 JSON chunk 与 BIN 后缀重建，catalog 通过三段动作追加补丁重建，旧 8.4 MB BIN 和旧 28.5 MB catalog 不重新传输。289 个原文件保持逐字节相同。

一次真实 seal、一次真实 apply 后，302 个 H17 overlay 文件与目标目录逐 SHA 一致，共131,055,973字节。它仍需要既有73个基础资源；组合总量为 `73 + 302 − 2 = 373`。历史九项 audio-only 密文候选和中间缺少 Morph／trails 重绑定的版本均未发布。此次没有再次编译音频或重导出旧模型。

## 实际重击到倒地标记已经可达

早期近距离探针的“11 次挥击、0 接触”已被进一步定位。原始 3D 胶囊在该近距离存在轨迹空隙，重击自身又有明显前移；因此没有通过压平 Z、扩大碰撞或改伤害来让探针通过。

不修改真实 catalog、血量、技能等级或防护规则的两击对局，记录了以下路径：

| 固定步 | 实际事件 |
| --- | --- |
| 513 | 距离 2600 mm，刘施放一次重击。 |
| 559 | 动作 tick46、距离 1164 mm 时原 3D 胶囊接触，孙 HP 1000→871；首次非暗影命中触发孙原防护，所以没有倒地。 |
| 751 | 距离 2617 mm，再施放重击；仍处于原防护的 600 tick 冷却窗口。 |
| 797 | 第二次真实命中，HP 871→742，进入 `h_hit_head_fall`。 |
| 837 | `sourceMotionSamples` 从 tick37 到 tick38，只产生一次 source frame19 跨越。 |

这证明该真实 catalog 的碰撞、伤害、受击动作与标记路径在当前 Linux 核心可达。它没有执行 SceneKit、Apple 音频输出或物理设备。完整复现范围见[重击接触诊断](acceptance/h17-heavy-contact-diagnosis-20261114.md)。

## 验证归属与发布边界

本批使用定向测试；不同批次可能覆盖同一字段审计方法，不能把各批数字简单相加成不同方法总数。已通过方法的代码未变化时复用其执行记录，仅为真实失败的 fixture 修正重验对应方法。没有重新执行 ef306408 上已成功的 117 项重型 Apple 集合。

| 验证层 | 本批含义 |
| --- | --- |
| 代码分析 | 原始配置、动作身份、时钟、反应条件、音频调用链及当前运行时接线。 |
| Linux Swift 核心 | 盘古 15 项定向覆盖；根缚与新版回放 16 项覆盖；源音频变体 4 项覆盖。各批日志保留首次失败和修正后的结果。 |
| Python 与真实私有输入 | 资源输入身份、源骨架采样、增量装配和加密认证；恢复工具检查的未命中项单独记录。 |
| Apple XCTest | 新增／更新方法的源码与语法不等于执行；必须有对应提交、方法与零 skipped 的结果才可升级状态。 |
| 模拟器／真机 | 当前批次的原资源渲染、实际听感、帧时间、内存、温升和 iPhone 17 Pro Max 视频仍需独立验收。 |

上述 Swift 批次合计 **34 个不同方法**取得通过记录，其中一项字段审计在两个批次中重合。Python 为 **82 个不同方法**，包括中间音频工具21项、索引恢复24项、骨架输入6项以及最终增量31项；它们不计作 Apple 原生方法。新增原生范围为 installed3项与共享音频／Morph门禁5项，**8项均尚未在 Apple 执行**。完整源码摘要与执行归属见[本批机器回执](acceptance/fighter-dual-development-20261115.json)。

历史 Apple 成功记录仍只属于 [`ef306408… / run 43611931466`](https://github.com/wuyong9494-lab/kriswu/actions/runs/43611931466)：117 个 source-only 方法通过，5 个 installed-source 方法明确排除。新的代码与资源不能继承该运行的完成标签。

## 仍需解决的原始资源和执行入口

本轮实际复用了已有解密归档，并扩展检查原 Unity 容器、ZIP 成员、无扩展名序列化文件及 1,127 条 ResourceManager 路径。仍未取得新的 D19 专属动作或装备；缺口为 **11 个文件／12 个别名／5 个装备条目**。真实动态索引、成功 balancer metadata，或已下载盘古资源的设备缓存，才是下一项有效输入。完整边界见[盘古原始索引恢复记录](fighter-pangu-source-index-20261114.md)。

受保护原生环境的 `FIGHTER_H17_D19_KEY` 目的地写入，此前被自动审批拒绝，尚未取得针对 GitHub 仓库 `wuyong9494-lab/kriswu`、environment `fighter-private-assets` 的后续明确授权。本批只使用已有本地私有密钥处理新增量，没有更换目的地或绕过该限制。

没有上传 TestFlight，没有重传旧资源包，也没有把尚未执行的模拟器或真机项目记作通过。最终资源摘要、装配证明与源文件摘要以本批机器可读回执为准。
