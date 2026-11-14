# 共享根缚原资源：最小 Apple 验收入口

本入口只安排 **9 个原生方法 + 1 个独立 UI 方法**。历史成功的 117 项、旧的 5 个 installed-source 方法、旧 UI 方法均不在选择集合内。此说明创建时尚未触发本工作流；本地完成的是 15 个新 Python 门禁测试、源树与清单预检，以及两个新 Swift 文件的语法解析。它们不等于 Apple 编译、模拟器执行或真机通过。

## 源码与资源归属

应用、Core、Shared、Widget、Package.swift、project.yml、既有 scripts 和既有 Tests 内容钉在 GitHub 基准提交 **6ebca235dfb579454c99528791f5c8e84bc9ff6f**。新入口只允许新增两个分别按 SHA256 校验的 Swift 测试文件。运行时另记录实际 workflow commit SHA，因此不会把本地 snapshot commit 当作 GitHub 证据。

源树门禁会拒绝应用或既有测试变化。新增资源恢复脚本应另行提交，不能混入本次触发提交而改变已经固定的 scripts tree。

最终资源为 shared-root v2；刘泉纬仍是 **liu_hammers / 双锤参考模型**。新增共享受击动作不会授权 D19 盘古模型、武器、独占技能或音效。

| 校验对象 | 固定 SHA256 |
| --- | --- |
| 原 295 文件 overlay 的密文 manifest | 697d62e8d9bf81da4521b6b828e4b1c4d2aa00e7141eab4d1558b3aa2ee032ff |
| 本轮 13 payload 增量的密文 manifest | d50b7fc6f711a55849b259b0f78d348612782f5e3765f9629db50291e20fe2b9 |
| 最终 release / 编译设置 | e5c0ccaeef85ce86c5b8fd4ee64524794d6556f5a561f4078362f6899bedf4e5 |
| 最终 catalog | fbd9ecbd9fb16de79c0240404e315af81d8cbbaa113b6042e6afc5ed7b1d0330 |
| 最终 audio manifest | d13dbebea26a4759c3b5109ef12de957140b9056e6adc5fdf989b6a3321b3d90 |
| 刘泉纬 59 动作 GLB | a3aada76d336b9c4f9bda3904b5e947711d916f683a2dcbf7b8184377e01a517 |

完整重建顺序是：认证既有 73 个基线资源；另外认证原 295 文件 overlay；对独立的 295 文件目录应用 13 payload，得到 302 文件 overlay；按两个明确替换项与 73 合并，得到 **373 个最终资源**。不能把已经混入基线的 366 文件目录作为 delta 的原始输入。两个替换项只有 Liu_Legion_Hammers.glb 和 SF3_DistinctFighters.json。

同一次小型 CryptoKit 程序分别验证原包与增量的固定 AES-GCM AAD。模型只追加经过核验的 JSON/BIN 后缀，catalog 只追加 3 条动作；保留旧模型 BIN 和旧动作。没有下载、重解码、重转模型或重新上传旧资源版本。373 个资源的字节数与 SHA256 必须在编译前及 App Bundle 内分别一致，之后才允许测试。

## 必需 Secret 与保护规则

本轮用户已明确授权将既有 FIGHTER_H17_D19_KEY 写入指定仓库的 fighter-private-assets environment；根任务已在 GitHub 界面保存并确认。既有环境审核人、禁止管理员绕过及分支规则保持原样。

| Secret 名称 | 既有用途 | 已确认的入口 |
| --- | --- | --- |
| FIGHTER_LIU_MODEL_KEY | sf3 / distinct 基线 | 仓库 Secret |
| FIGHTER_PRESENTATION_KEY | presentation / source-trails 基线 | fighter-private-assets |
| FIGHTER_H17_D19_KEY | 295 overlay 与 13 payload 增量 | fighter-private-assets |

三项都只注入 stage 步骤；stage 在任何重型 build 前检查格式并认证资源。每个子进程只继承其需要的资源 key。资源 key 不写入临时文件、不进入 App、日志、测试或工件。FIGHTER_MUSIC_PACKAGE_KEY 不用于本链。

## 精确执行范围

### 原生集合：9 个方法，独立结果包 native.xcresult

| 类 | 精确方法 |
| --- | --- |
| DuelTriadFloorfallIntegrationTests | testInstalledReleaseBindsSevenOriginalVariantsAtThreeExactProfileIntervals |
| DuelTriadFloorfallIntegrationTests | testInstalledIntervalsReachTheExistingConsumerOnceAcrossPauseAndReset |
| DuelTriadFloorfallIntegrationTests | testInstalledOriginalBodyFallWAVsDecodeWithoutStartingPlayback |
| DuelTriadRootVictimAudioTests | testVerifiedRootEndUsesLiuOwnershipAtTick38AndDeduplicatesTheSameFrame |
| DuelTriadRootVictimAudioTests | testRootEndRejectsWrongClockFrameContextVariantCountAndSunImpersonation |
| DuelTriadRootVictimAudioTests | testEveryVictimClipMustMatchSourceSHAFramesTicksGridAndPelvisBeforeSharing |
| DuelTriadRootVictimAudioTests | testOrdinarySharedThrowsKeepSoundFrameClockWithoutTheRootEndException |
| DuelTriadRootVictimAudioTests | testMorphTargetMetadataAcceptsOnlyReviewedHammersAndCompleteNewVictimCapability |
| DuelSharedRootInstalledModelTests | testFinalSharedRootReleaseLoadsBothOriginalCharactersAndAllThreeLiuVictimMotions |

前 3 项验证已安装清单、consumer 行为和 7 份原 WAV 的 AVAudioPlayer 解码，不启动可听播放。中间 5 项使用合成 fixture 验证生产门禁，不能称原资源执行。最后 1 项真正调用惰性的 character(for:)、装配 SceneKit skin、核验孙登 65 与刘泉纬 59 动作及刘的 3 条原共享动作，拒绝空模型或无效骨骼采样。它仍不证明渲染像素和真机表现。

最后一项区分原 GLB 身体/武器 skin 和运行时附加的 source-trail skin：原模型的 87 / 76 joints 严格固定；所有 skin 仍须有非空几何及有效骨骼、inverse-bind、权重与索引输入。避免把独立的 4 joints 拖尾 skin 误判成模型失败。

### 界面集合：1 个方法，独立结果包 ui.xcresult

唯一 selector：

~~~text
ArenaFlowTests/DuelSharedRootVisualCaptureTests/testFinalSharedRootReleaseShowsBothFightersAndAcceptsSunBranchesThroughRealControls
~~~

它从现有 -demo -screen fighter 入口启动，真实点击孙登选角与练习，等待可施放后释放中立方向的枝蔓囚笼，观察根枝束缚与对手生命下降，等待可见控制状态解除，再返回并选择刘泉纬进入练习。没有注入能量、生命、位置或内部战斗状态。没有新增生产调试参数。

成功集包含 6 张图：孙登大厅、孙登练习、可见根缚、可见控制解除、刘泉纬大厅、刘泉纬练习；另有 shared-root-ui-observations JSON。失败时保留已完成的部分与可选失败截图。AX 观察与截图不保证同一动画帧；“控制解除”不等于精确 End 动画或 tick 38。精确动作时钟仍需结合已有 Core / 原生证据。

如果 UI 方法失败，另以同一 App 执行普通刘泉纬大厅启动、两张截图和日志，作为诊断，不能替代 UI 成功。截图须人工图审；大厅的既有音乐不能当作本次 floorfall 可听声音通过。

## 工作流与通过门禁

工作流文件：.github/workflows/fighter-shared-root-native.yml。唯一新执行 helper：.github/scripts/fighter_shared_root_native.py。

允许指定分支的精确提交消息触发：

~~~text
Verify shared root native increment 20261115
~~~

也提供带精确 source_sha 的 workflow_dispatch。两者都要求运行 attempt 为 1；普通 push、PR、计划任务或 GitHub 的整次 rerun 不会自动执行该验证。首发工作流尚未进入默认分支时，应使用已经评审的精确 push 入口。

使用现有 macos-26 / 已安装 Xcode 26.6 / iPhone 17 Pro Max 模拟器。临时生成独立 project.shared-root-native.yml，把现有 SiteTests 与 ArenaFlowTests 放入同一次 build-for-testing；不修改受保护的 project.yml，不下载模拟器 runtime，不签名。

随后两个 test-without-building 分别选择 **9 个具体原生 selector** 与 **1 个具体 UI selector**，关闭并行，每方法一次。两个 xcresult 的 summary 数字与 Test Case 叶节点都必须一致：各自总数准确、全部 Passed、failed=0、skipped=0、无缺项/重复/额外方法。进程 completed、工件存在或工作流 skipped 都不能替代通过。

9 项通过后即独立保存其结果；UI 失败不会清除该事实，也不会自动重跑 9 项。日志与两个结果包的 summary/tests 导出在失败后继续保留，测试原始退出码不会被导出成功覆盖。

## 诊断与恢复

模型 report、UI 6 图与观测 JSON 必须归属于精确 selector、该次 simulator UUID/name 和固定附件标签。只在对应完整集合通过时标记附件齐全。失败时的部分截图与原生失败正文仍进入有界加密诊断，不提升为通过。

诊断沿用既有已评审的公钥接收体系。每次生成新的 32 bytes 证据 key，用 RSA-OAEP-SHA256 包给两个既有接收者；日志和截图使用既有认证证据封装。资源 key 不参与诊断加密。Actions 仅上传密文、加密后的证据 key 和 SHA256SUMS，保留 3 天。

若 9 项已通过而 UI 或其附件门禁失败，helper 尝试把此次 Products / xctestrun 与独立逐文件摘要保存为额外的加密 UI 恢复包。只允许同一源码 SHA 与资源 pin 的后续受控 UI 恢复；包本身不运行任何测试。预算为 768 MiB 明文、256 MiB 压缩后，超限或包含不可接受的链接时明确记录不能保留及成本，不能声称已经可复用。成功 UI 不重复打包构建产物。

完成封存与上传后清理该次自有 simulator、明文资源、构建产物、xcresult、临时 spec 和明文日志。最终报告独立列出 9 项、1 项、资源/附件门禁、截图待图审、真机未验证、可听输出未验证及 D19 未激活。无 TestFlight 操作。

## 本地已完成 / Apple 待执行

2026-11-14 21:20 UTC 前的新 helper 验证：

- 新 Python 门禁测试：15 / 15，0 失败，0.041 秒；只跑这一新文件。
- Python 语法、workflow YAML、6ebca 完整应用源树、旧 Tests 排除两新文件后的摘要、新测试文件 SHA、公开资源清单 373 项映射均通过。
- 两个新 Swift 文件仅前端 parse 通过；未进行 Apple 类型检查或执行。
- 未读取/输出资源 key，未重复解密或下载资源，未重跑历史 117 项，未上传版本。

机器可读交接见 docs/acceptance/fighter-shared-root-native-20261115.json。首次 Apple 运行的真实 SHA、run URL、方法结果、截图与失败步骤应从新工作流证据补入，不能把本地预检写成原生通过。
