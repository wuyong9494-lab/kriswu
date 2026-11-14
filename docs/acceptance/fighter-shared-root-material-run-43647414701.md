# 共享根缚与材质专项：43647414701

**本次视觉验收失败，发布仍受阻。** 六个定向原生方法实际结果为 **6 PASS / 0 FAIL / 0 SKIP**，每个方法各执行一次；独立 UI 方法为 **0 PASS / 1 FAIL / 0 SKIP**。随后对原始截图的人工审查发现战斗画面明显异常，因此原生方法通过记录只能覆盖其加载、绑定与采样范围。

## 运行与提交

| 字段 | 已核实际值 |
|---|---|
| 源提交 | [`5788ebb1001a6e0f31c5208cb2b955b48b00741c`](https://github.com/wuyong9494-lab/kriswu/commit/5788ebb1001a6e0f31c5208cb2b955b48b00741c) |
| 固定基线 | `68f1e7de45351c3e4b2607c56ff8ab111d0c7130` |
| Actions | [43647414701](https://github.com/wuyong9494-lab/kriswu/actions/runs/43647414701) |
| Job / Attempt | [132608191547](https://github.com/wuyong9494-lab/kriswu/actions/runs/43647414701/job/132608191547) / `1` |
| 执行范围 | `material-followup-six`：四个此前失败的资源方法、两个新增 uniform 回归方法，以及一个 UI 方法 |
| GitHub 结果 | `completed / failure` |
| 运行开始 / 最终状态更新时间（北京时间） | `2026-11-15 06:18:45` / `2026-11-15 06:42:22`（Asia/Shanghai，UTC+08:00） |
| 模拟器 | iPhone 17 Pro Max，iOS `26.5`；原生结果与 UI 结果均核对为本次拥有的模拟器 |
| 最终清理 | Actions 清理步骤实际 `success` |

此记录读取了已经完成认证解封的本地证据与元数据，没有再次下载或解密 artifact，没有重新运行任何方法。归档中的 `visualReview=PENDING` 是封包时状态；其后主代理直接查看三份原始 PNG，视觉结论更新为 **FAILED**。归档摘要产生于最终清理之前，清理结果以最终 Actions 步骤为准。

## 六个原生方法实际通过的范围

| 方法 | 实际结果 | 证据边界 |
|---|---|---|
| `testInstalledReleaseBindsSevenOriginalVariantsAtThreeExactProfileIntervals` | PASS，一次 | 七份原始 floorfall 音频变体与三个明确 profile interval 的绑定 |
| `testInstalledIntervalsReachTheExistingConsumerOnceAcrossPauseAndReset` | PASS，一次 | 已安装资源事件进入现有消费路径，核对暂停与重置中的去重 |
| `testInstalledOriginalBodyFallWAVsDecodeWithoutStartingPlayback` | PASS，一次 | 原 WAV 解码；该方法明确不启动音频播放 |
| `testFinalSharedRootReleaseLoadsBothOriginalCharactersAndAllThreeLiuVictimMotions` | PASS，一次 | 原模型加载、蒙皮构建与三段刘泉纬共享受击动作的有限姿态采样 |
| `testInstalledSourceMaterialsResolveOnlyReviewedUnassignedCustomPosition` | PASS，一次 | 已复核材质中 `_CustomPos` 的受限初始化处理 |
| `testUnreviewedMissingUniformsRemainRejectedAndExplicitValuesKeepPriority` | PASS，一次 | 未复核缺失 uniform 继续被拒绝，显式值保留优先级 |

方法选择、xcresult 节点与进程回执一致，没有缺失、额外或重复方法。原生进程退出码为 `0`，迭代次数为 `1`。

资源认证与构建后 **373 项资源核验**已通过。模型附件记录孙登 `sun_triad` 加载 **65** 个 clip，刘泉纬 `liu_hammers` 加载 **59** 个 clip，其中包含三段新增共享受击动作。该附件明确声明 `renderedPixelsVerified=false`、`audiblePlaybackVerified=false`，两个已加载 profile 的 `isPangu` 均为 `false`。

相关固定源码：

- [floorfall 集成方法](https://github.com/wuyong9494-lab/kriswu/blob/5788ebb1001a6e0f31c5208cb2b955b48b00741c/Tests/SiteTests/DuelTriadFloorfallIntegrationTests.swift)
- [模型与共享动作加载方法](https://github.com/wuyong9494-lab/kriswu/blob/5788ebb1001a6e0f31c5208cb2b955b48b00741c/Tests/SiteTests/DuelSharedRootInstalledModelTests.swift)
- [uniform 回归方法](https://github.com/wuyong9494-lab/kriswu/blob/5788ebb1001a6e0f31c5208cb2b955b48b00741c/Tests/SiteTests/DuelTriadRuntimeUniformTests.swift)
- [材质实现](https://github.com/wuyong9494-lab/kriswu/blob/5788ebb1001a6e0f31c5208cb2b955b48b00741c/App/Services/DuelTriadSourceMaterial.swift)

此前 [43644209347](https://github.com/wuyong9494-lab/kriswu/actions/runs/43644209347) 的五个合成绑定/能力方法，属于提交 `68f1e7de45351c3e4b2607c56ff8ab111d0c7130` 的历史证据。它们本次没有再执行，也没有加到本次六项通过数中；旧 117 项套件同样没有重跑。

## UI 失败步骤与已确认的等待条件问题

唯一 UI 方法为：

```text
ArenaFlowTests/DuelSharedRootVisualCaptureTests/
testFinalSharedRootReleaseShowsBothFightersAndAcceptsSunBranchesThroughRealControls
```

该方法通过真实控件选择孙登并进入练习场，随后在 `sun-root-visible` 阶段的 **8 秒有界等待**中失败。实际错误为 `Did not observe sun-root-visible within its bounded UI budget`，UI 进程退出码为 `65`。方法执行一次，未完成双方练习场与完整根缚链；`flowCompleted=false`。

固定 [UI 源码](https://github.com/wuyong9494-lab/kriswu/blob/5788ebb1001a6e0f31c5208cb2b955b48b00741c/Tests/ArenaFlowTests/DuelSharedRootVisualCaptureTests.swift#L106-L122) 的准备条件使用 `.contains("可施放")`。实际 `sun-branches-ready` 观察记录中的控件值是 **“暂不可施放”**，该字符串同样包含“可施放”，因此等待条件错误地接受了未就绪状态。这是已由固定源码及运行观察共同确认的测试条件缺陷。

后续观察没有满足“根枝束缚”控件出现与对手血量下降的联合条件。上述等待条件缺陷尚未被证明能够解释全部渲染异常；画面的真正根因仍待定位，不能把单独修正等待文字比较视为像素问题已修复。

## 原始截图的真实观察

三张图片都来自本次 UI 方法的原始附件，像素尺寸均为 **1320 × 2868**。本报告只公开摘要和观察结果，不复制原始图片。截图与可访问性观察不是严格同一帧，不能据此声称观察到了某个精确动画 tick。

| 原附件标签 | 原始字节数 | 主代理直接查看原 PNG 的结果 | SHA-256 |
|---|---:|---|---|
| `shared-root-ui-sun-lobby` | 3,372,200 | 孙登完整人物与舞台可见；仍显示旧武士刀身份文字 | `448e4f2d463eea4d13d300149e4ae694565006498062032c457601f06831a73d` |
| `shared-root-ui-sun-practice` | 444,987 | 练习画面为黑场，并出现巨大的青白特效 | `02888c6f7fcd16abfe06cb8eae2468c0c16e74918d8ff43b2daddfd9849ed15d` |
| `shared-root-ui-failure` | 2,410,131 | 满屏紫色枝蔓特效，人物与舞台不可见 | `fc9f42b6509fc5e4855fc6001f642b1793c55b15b60dae6b4670dd95d76b0b04` |

要求的截图集合不完整：缺少刘泉纬大厅、刘泉纬练习场、孙登根缚观察、孙登根缚控制释放四项。失败截图保留了实际异常，不能代替缺失的成功阶段截图。附件导出的直接错误另为 `Expected bounded regular file`；现有代码在识别必需标签之前，会先把所有自动附件也按非空、24 MiB 单文件上限检查。现有密封内容不足以判定是哪一份自动附件触发该边界，不能将直接导出错误改写为仅仅缺图。两项问题都保留为失败，部分原始证据已经保全。

## 与后续大厅修复严格分开

本次截图属于 **`5788ebb…`**，包含旧“孙登、先锋 · 武士刀”文案。后续大厅快照绑定修复是在 **`5afd8195e2f611ab2e7c37f5096a4251a4616ee9`** 提交中发布，并由 [43648900087](https://github.com/wuyong9494-lab/kriswu/actions/runs/43648900087) 完成独立源码编译。

该后续运行执行测试数为 `0`，没有装载原始私有资源。它只能补充大厅新代码的编译证据，不能回写本次截图、改变本次 UI 失败结论或证明战斗画面已经修复。详见 [大厅编译回执](fighter-lobby-source-compile-run-43648900087.md)。刘泉纬的当前 profile 仍为 `liu_hammers`，盘古独立资源没有因此被登记为已完成。

## 资源与加密证据身份

| 项目 | 已核摘要 |
|---|---|
| 资源 release | `e5c0ccaeef85ce86c5b8fd4ee64524794d6556f5a561f4078362f6899bedf4e5` |
| 增量 manifest | `d50b7fc6f711a55849b259b0f78d348612782f5e3765f9629db50291e20fe2b9` |
| 材质源码 SHA-256 | `efb78001996c8e66721cafbcdb99765b3af9d4ca17e827385ca6d3968ef75856` |
| 原生工作流 helper SHA-256 | `016bb5a3a7065692dfc214036e7146b26c9e589ea7c58abf72c5a26ad1b8c978` |
| 本次工作流 SHA-256 | `458f83947c57a39035090e0ee2997194896cfe1d3c53e3fdc8375cab6821d6f3` |
| 加密 artifact | ID `14134893882`，224,223,739 B，SHA-256 `1f157104bba6e631461a994ef5291e2babf3326d91ed0f407eb1697ea99a1b6e` |
| UI recovery 密文 | 208,784,354 B，SHA-256 `a45f16a8b1b7dcc1dbccc18bb36062ab96af4c72d6f27949c86f746f7304f12f` |

已有回执确认 GitHub artifact digest、认证解封、canonical 身份、选择器与 67 个证据清单项；本报告重新计算了本地 artifact、三张 PNG、相关元数据及 recovery 密文摘要。**UI recovery 仍只有密文，本次未解密、未启动其中的产物。** 封包前的 `available=false / packagedAwaitingEncryption=true` 与最终密文存在属于不同时间点，不应混为恢复执行成功。

最终 Actions 的清理步骤成功，已处理本次模拟器、staging 媒体、构建产物及 runner 明文诊断。听感、原场景音画同步、精确动画 tick 的 UI 观察、真机视频及 iPhone 17 Pro Max 性能仍未验证；没有 TestFlight 上传，也没有为制作本报告触发任何工作流。

完整机器可读记录、六个选择器及文件摘要见 [对应 JSON](fighter-shared-root-material-run-43647414701.json)。
