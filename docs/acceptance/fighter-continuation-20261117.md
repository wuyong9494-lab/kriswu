# 四英雄开发续接：动作源、特效停止契约与原生预检

核对日期：2026-11-17（北京时间）。制作基线：`codex/fighter-completion-20261117` / `bf0343495121942462b1dd9ff2770a2ae4b2cd7f`。

## 本轮结论

本轮补充可复现开发工具和真实源输入证据。**仍未达到四英雄 100% 还原、完整战斗或发布验收。** 原有效分支 `codex/fighter-visual-acceptance-20261113-1200` 的 `fbe1f97b947df6936eb9a1721510e92a178fb543` 保持独立记录。

| 本轮项目 | 已完成 | 仍未完成 |
| --- | --- | --- |
| 刘泉纬 D13 过载动作 | 原调用触发器、别名、完整资源路径、PathID、字节、SHA 和骨架绑定闭合；独立单动作 GLB 与 profile 已生成并回读 | 未替换正式 66 动作模型；未激活自动 Bloom 过载、伤害或原生事件链 |
| 吴庸 D15 StopEffect | 原整数帧 job、逐步 Float32、`_Transparent` 写入及停用顺序恢复为独立源契约 | 未接入 App；provider、共享时钟、父级删除、Noise 和符号 Stretch 仍有缺口 |
| 原生 27 + 1 计划 | 只读预检工具核对源码、541 文件固定清单、项目映射、Apple 宿主和实际测试产物 | 本环境无 Apple SDK、Xcode/模拟器；未执行原生或 UI 测试 |
| 徐骁 D20 | 重新核对原目录映射、现有恢复目录及连接文件元数据 | 未发现新增真实输入；5 装备、37 动作仍缺媒体及后续依赖闭包 |

上一候选的 33 项 Linux 核心测试、37 项加密增量检查和原生计划保持原证据范围。本轮没有重复运行它们，也没有把新增 Python 检查累计成原生或真机通过数。

## 1. 刘泉纬：准确的共享源动作，不是英雄替换

`lock_1389.bytes / set0 / trigger14` 的原动作 `a6` 指向 `Set_Legion_3_Shadow_Form_In`。固定的 `settings_sets_legion.bytes` 第 12 行把该别名映射为 `unique_moves/sets/sets_moth_roar.bin`。这个来源关系允许 D13 使用原配置指定的共享动作，不允许改成另一个同为 54 帧的 `moth_shadow_form_in`。

| 对象 | 字节数 | SHA-256 |
| --- | ---: | --- |
| 原配置 `settings_sets_legion.bytes` | 335,308 | `0ce568c982adbba7b157cf5a5c72922e3f889b4cdaf1bac95c03f8ec38e979bf` |
| 原 bundle `9893dca6e10355eb9c3c79d1613f08b1.bin` | 14,681,877 | `d6f2efe8ce772b953f610583ab5fb8963fb27abcccfec4b3aeccce8be973dd42` |
| 原动作 `sets_moth_roar.bytes` | 75,442 | `95494d2fb96b2642a89b3c9c14e389eb922fc81377fcd6edca837255ea26f40c` |
| 新独立候选 `Liu_KingOfSerpents_D13_Overload_Source.glb` | 6,240,004 | `90794b73cc091f8f4b65c79716672765cf8c5b3830359eb7c7a88d819c7028f2` |
| 新独立候选 `D13_Overload_Source_Profile.json` | 304,421 | `40c85f3236903098eb0b20d70002dd0513e93afccad71b0be870f3a4bc8975af` |

实际 Unity 容器路径为 `assets/gamedata/resources/content/animations/binaries/unique_moves/sets/sets_moth_roar.bytes`，PathID 为 `3582625690775438110`。工具同时核对完整路径、PathID、名称、长度和哈希，不能只用文件名命中。

候选使用原 D13 的 80 个蒙皮关节，58 条原身体轨道生成 116 个平移/旋转通道。原几何、材质、蒙皮、图片与个人头部数据未改。GLB 头为 `glTF` / version 2 / 长度 6,240,004。54 帧动作产生 107 个半帧回读采样点；5,796 项原动作、GLB 通道及 FK 比较通过，最大误差 `5.960464477539063e-08 m`。

时间域明确分开：源窗口 `0...53`、每源帧间隔 2 个逻辑 tick、最后姿势 tick 106；既有原生规则的 `SelfEndFrame` 默认 4，故 AnimationEnd 事件 tick 98。`D13_Bloom_Overload` 原第 28 帧对应 tick 54；特效标记原第 8 帧对应 tick 14。这些计算没有运行 App 的事件调度。

`trigger14` 的调用条件与 `trigger16` 的 `IntervalStart D13_Bloom_Overload` 是不同事件。满槽不能直接冒充后者，也不能把第五储存的 `0.66 / 420 tick` 当作扣除 66% HP。MagicPower、BodyDefense、模型接触与最终 Hit 路径仍需完成。

复现入口：`scripts/prepare_serpent_overload_source.py`。输入为已有、已解码恢复 checkpoint 和 motion source archive，使用已审 UnityPy 1.25.4；输出必须是仓库外的新私有目录。8 项负向检查拒绝其他英雄别名、同帧数错误动作、裁帧、镜像、错误时钟、错一帧的标记、坏字节和 ZIP 重名。真实候选回执见 `fighter-continuation-d13-overload-20261117.json`。

最小后续接入需同时更新真正的 actor/profile、所有依赖该模型哈希的媒体清单和白名单；保持其他 66 动作与几何数据，单独回归过载进入、中断、朝向、WeaponSwitch、动画尾帧及双方同步。**本轮没有执行这次正式资源替换**，不将单动作候选计作 67 动作正式角色。

## 2. 吴庸：停止特效使用独立整数帧时钟

详见 `fighter-erlang-effect-stop-source-contract-20261117.md` 及 `scripts/erlang_effect_stop_source_evidence_20261117.json`。原二进制仅作静态读取，没有执行。每个方法保留原文件 SHA、虚拟地址、文件偏移、长度、代码 SHA、metadata 记录及注册指针证据。

`StopEffect → 35910 → 35943/35944` 使用 Int32 frame job，与 Avatar 的浮点逻辑时间 job 不同。它先算逐步 Float32 的 progress，再算 `1 - progress` 写入精确的 `_Transparent` 属性。没有 clamp；到期后先写材料，再执行 `SetActive(false)`。帧数非正或 renderer 集合为空走立即停用分支。

新 `erlang_effect_stop_source_state.py` 只接收外部已观察的原 Int32 frame 和对象存活状态，不生成时钟、不推断 elapsed time、不把 `erlangLiveTick` 或命中停顿直接代入。原始对象与材质缺失不会借用另一英雄模型。

19 项检查在实际原二进制、metadata 和固定 Sword 源收据下通过，0 跳过；包含数值边界、原方法和属性回读、收据篡改拒绝。它们是源码契约检查，不是 SceneKit/Metal 或原生游戏执行。现有 emitter 覆盖仍为 67 / 79，不能随该契约增加完成数。

## 3. 原生验收预检：准备命令与执行结果分开

`scripts/completion_native_preflight.py` 是离线、只读工具；其子进程仅允许固定 Git / Apple 查询。它不解密、安装资源、生成项目、构建、启动模拟器、跑测试、联网、审核环境或上传。

预检固定 `fighter-completion-native-plan-20261117.json` 的 SHA 和 27 native + 1 UI selector，固定 540 + 1 编译输入清单（541 文件、311,221,653 B）。每个文件按文件名、大小、SHA 校验，拒绝符号链接、闭包缺项、多余项和读期间变化。放在仓库外的正确资源不能被误记为项目已安装。

构建后检查实际 App 与两个 `.xctestrun`：资源必须位于 loader 使用的同一目录；核对 release / D20 pin、源码 rules 指纹、测试 bundle 和 host；拒绝跳过、错误 selector、设备旧产物替代以及外部资源环境变量。`ShiftReminder` 与 `ArenaFlow` 方案共享一个 DerivedData。

`readyForBuild` / `readyForTests` 只说明相应输入与配置可供执行，不证明编译来源或运行结果。无独立机器码来源证明时 `binarySourceProvenanceVerified=false`。真实 `xcodebuild` 执行、`xcresult`、截图/日志及资源身份仍是验收必要证据。

截图测试保留原有真实 GitHub run ID / attempt / source SHA 合同，预检读取调用者已取得的 GET 回执，不创建新 run，也不伪造编号。当前候选尚无匹配的 Actions 运行；这一 UI 证据条件仍阻塞。没有因制作预检工具而解除用户对新工作流的限制。

最小执行入口（由实际 Apple 主机填写真实值）：

```text
python3 -I -B -S scripts/completion_native_preflight.py \
  --expected-source-sha <已审查的40位提交SHA> \
  --derived-data <独立DerivedData绝对路径> \
  --device-udid <已有iPhone-17-Pro-Max模拟器UDID>
```

预检仅在条件相符时输出待执行命令。完整真实资源缺失、Apple 主机缺失或测试身份不足时应返回非零，并保留 `nativePassed=null`、`uiPassed=null`、`physicalDeviceAccepted=false`，不能显示绿色通过。

本轮 32 项预检边界检查通过，0 失败 / 0 跳过；其中合成输入只验证拒绝边界，不作真实资源证明。对当前基线执行只读预检，512 个构建相关源输入、固定 plan/inventory/project 和 27 + 1 selector 均通过；资源安装、Apple 主机和 UI capture 身份缺失，正确返回 exit 2、空命令列表。完整检查回执见 `fighter-continuation-validation-20261117.json`，未把源码子集校验描述为整个仓库无修改。

## 4. 徐骁：缺的是新的原始资源入口

本轮核对 2 份相同 SHA 的 9,100,700 B 原 Android catalog、固定 13,042 B D20 requirements、13,480 个已有工作区路径和 30 个归档的元数据。没有重复解包旧大文件或重跑已失败的 Android 探测。连接资料补查到北京时间 22:32；既有恢复 checkpoint 均早于基准，未发现新的 D20 原始输入。

仍缺五个装备媒体：两种 Imperial Gloves 武器、`arm__agl_49`、`helm__agl_49`、`rng__agl_knives_01_06`。48 个独立原动作中 11 个共享文件已有映射，其余 37 个未取得（26 个 D20 专属、11 个 Imperial Gloves）。这些数目不是完整技能、召唤、FX 与音频依赖总数。

下一项有效输入应是实际成功的 balancer 响应（`bundles.url` 或 `bundles.path` 与真实 host）、带 `platforms` 和 `baseUrl` 的原 metadata，或具有来源证明的普通客户端 `bundles_<Int64>.bytes` / `bundlesConfig_<platform>.bytes` / BConfigData 导出。收到后才能按真实索引建立 D20 资源/依赖映射。不能用推测 URL、旧哈希或改变 D19 工具固定 pins 代替。

逐文件缺项、完整路径、来源记录哈希、搜索范围及其局限见 `fighter-continuation-d20-20261117.json`。未检查的远端 blob 和未提供的缓存仍为未知；没有宣称原始媒体在上游不存在。

## 发布与证据边界

本轮通过独立候选提交交付新工具与证据，提交使用 `[skip ci]`。不改正式 App / Swift 战斗源码、旧执行草稿、已发布加密增量或资源身份 pins；没有新 GitHub workflow、环境审核批准或 TestFlight。新 D13 动作候选以私有文件交付，GitHub 和 Sites 仅记录源证据、文件名、大小、哈希与未激活状态。

四英雄仍分别保留大厅、路径、真实模型加载、骨架动画、完整战斗和双机/真机六层状态。任何源码通过、静态 GLB 解析、离线候选和模拟器名称都不计为实体 iPhone 17 Pro Max 验收。
