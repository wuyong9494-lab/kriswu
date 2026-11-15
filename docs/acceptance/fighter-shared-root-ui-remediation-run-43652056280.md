# 共享根缚 UI 修复复验：43652056280

**本次 UI 与模拟器视觉验收均失败，发布仍受阻。** 固定 UI 方法实际执行一次，结果为 **0 PASS / 1 FAIL / 0 SKIP**。当前原生方法为 **`not_selected`**，没有当前原生通过数。新 App 已编译并通过 373 项资源核验；完整 UI 日志中两类已知 drawable 错误均为零。这些证据没有改变练习场画面异常和 UI 未就绪的失败结论。

## 运行与候选提交

| 字段 | 已核实际值 |
|---|---|
| 被测候选提交 | [`532fb03083da7053417b7ad7ba484a99e4c41c28`](https://github.com/wuyong9494-lab/kriswu/commit/532fb03083da7053417b7ad7ba484a99e4c41c28) |
| 固定基线 | `5afd8195e2f611ab2e7c37f5096a4251a4616ee9` |
| Actions | [43652056280](https://github.com/wuyong9494-lab/kriswu/actions/runs/43652056280) |
| Job / Attempt | [132622477505](https://github.com/wuyong9494-lab/kriswu/actions/runs/43652056280/job/132622477505) / `1` |
| 范围 | `ui-remediation-only`：一个此前失败的 UI 方法；当前原生方法未选择 |
| GitHub 最终结果 | `completed / failure` |
| 创建 / 最终状态更新时间（北京时间） | `2026-11-15 07:12:23` / `2026-11-15 07:33:20`（Asia/Shanghai，UTC+08:00） |
| 模拟器 | 本次独占的 iPhone 17 Pro Max，iOS `26.5`（`23F77`），arm64；并非真机 |
| 工具 | Xcode `26.6`，build `17F113`；iOS Simulator SDK `26.5` |
| 最终清理 | 最终公开 Actions 摘要为 `cleanupComplete=true`，`cleanupErrors=[]` |

`532fb030…` 是**被测候选代码**，不是随后发布本报告的提交。候选以 `5afd819…` 为基线，固定三个 App 帧提交／就绪描述文件和一个 UI 精确比较文件。源码身份、资源身份、测试方法以及结果设备均已由唯一消费回执核对。本报告只读取现有已解封证据与最终公开摘要，没有再次下载或解密工件，没有触发工作流或重跑测试。

## 各证据层的实际结果

| 层级 | 结果 | 结论边界 |
|---|---|---|
| App 构建与资源闭包 | 已通过 | 构建进程 `342.053 s / exit 0`；373 项编译后资源核验通过，北京时间 `07:20:17` 完成这一门禁 |
| 当前原生方法 | `not_selected` | 选择数、观察数均为 0，结果摘要为 `null`；没有原生结果文件，不能记为“0 PASS”或新一轮通过 |
| 固定 UI 方法 | **FAILED** | 一次执行；`0 PASS / 1 FAIL / 0 SKIP`；设备归属一致 |
| 两类已知 drawable 日志错误 | 本区间门禁通过 | CI 封包前完整扫描；两类计数均为 0，消费者仅独立校验已封存尾部与回执 |
| 必需截图／观察集合 | **INCOMPLETE** | 未完成练习场与根缚链，五个必需截图标签缺失；观察附件 `flowCompleted=false` |
| 人工原图视觉审查 | **FAILED** | 孙登大厅人物可见，练习场出现遮满视野的巨大紫枝，人物与舞台不可见 |
| 真机、听感与性能 | 未验证 | 本次没有 iPhone 17 Pro Max 真机视频、音频实播验收或性能指标 |

构建日志沿用 `native-build` 阶段名称；该名称表示 App／UI runner 构建，不能据此认定本次执行了原生方法。[工作流](https://github.com/wuyong9494-lab/kriswu/blob/532fb03083da7053417b7ad7ba484a99e4c41c28/.github/workflows/fighter-shared-root-ui-remediation.yml)仅选择当前 UI 方法，历史 5 项、6 项及旧 117 项均未自动重跑。

## UI 实际停在练习场就绪阶段

唯一方法为：

```text
ArenaFlowTests/DuelSharedRootVisualCaptureTests/
testFinalSharedRootReleaseShowsBothFightersAndAcceptsSunBranchesThroughRealControls
```

实际错误：

```text
Did not observe ember-practice-ready within its bounded UI budget
```

该方法完成大厅横屏观察、孙登选择和孙登大厅截图，点击练习场后停在 `ember-practice-ready`。固定 [UI 源码](https://github.com/wuyong9494-lab/kriswu/blob/532fb03083da7053417b7ad7ba484a99e4c41c28/Tests/ArenaFlowTests/DuelSharedRootVisualCaptureTests.swift)为这一准备条件设定 **15 秒等待预算**；方法最终耗时 **188.505 秒**，调用该方法的 `xcodebuild` 进程耗时 **308.786 秒**、退出码 **65**。这是实际断言失败，**不是触发 360 秒进程上限的超时**。等待预算、单方法耗时与整个 xcodebuild 耗时属于不同计量范围。

当前精确准备条件要求武器控件值等于 `可施放`。五份完整练习场快照中，横屏、无资源错误、暂停按钮、双方状态、无恢复按钮以及居中摇杆等其他条件都已满足；武器与暗影控件始终为 **`暂不可施放`**。最后另有一次快照报告 `Interrupted by waiter`，未把该失败快照计入完整观察。

| 观察项 | 已记录值 |
|---|---|
| 孙登名称 / 武器按钮 | `孙登 · 黑色双刀` / `黑色双刀攻击` |
| 对手名称 | `刘泉纬 · 双锤` |
| 武器 / 暗影状态 | 五份完整快照均为 `暂不可施放` |
| 双方生命 / 累计命中 / 伤害 | `1,000 / 1,000`；`0`；`0` |
| 孙登可见位置 X | `2,580 → 2,580 → 2,460 → 2,467 → 2,469` |
| 刘泉纬可见位置 X | 均为 `6,500` |
| 摇杆 | 均为 `居中` |

位置变化说明 UI 观察到了部分状态变化，不能据此确定入场逻辑是否卡住、反复重启或有其他条件未解除。**本次尚未定位就绪失败与巨大紫色特效的根因。**

本次 UI **没有点击暗影按钮**，没有进入 `sun-branches-ready`、根缚命中、控制释放及刘泉纬练习场阶段。失败截图中的枝条不能登记为玩家成功施放根缚技能，也没有本次伤害、连招或控制释放通过证据。截图与可访问性快照并非严格同帧，不能推断精确动画 tick。

## 完整运行日志门禁与封存边界

固定 helper 在 CI 内对 **北京时间 2026-11-15 07:26:43—07:32:10** 的完整 UI 调用至结果导出区间收集并解析 JSON。原始 UTC 区间为 `2026-11-14T23:26:43+00:00` 至 `2026-11-14T23:32:10+00:00`。

| 项目 | 已核值 |
|---|---|
| CI 收集进程 | `exit 0`，完整 JSON 已解析，归属本次模拟器 |
| 原完整日志 | **12,012,780 B**；8,818 条，全部为本 App 条目 |
| 完整日志 SHA-256 | `055aa6650998977efd7aa9b7e14a9d19a5bd90b1696580dc5374a32ea1fecbef` |
| `Each CAMetalLayerDrawable can only be presented once!` | **0** |
| `[CAMetalLayerDrawable texture] should not be called after already presenting this drawable.` | **0** |
| 实际封存 | 最后 **2,097,152 B（2 MiB）**，`sealedTextTailOnly=true` |
| 尾部 SHA-256 | `66652c80cac2e7d0013a82846514f96607d741f74c35ea7d6e370bc0df6e517e` |
| 消费端独立核验 | 尾部字节、认证回执、精确标记、设备与 UI 时间窗；`fullLogIndependentlyRescanned=false` |

完整计数来自固定 [helper](https://github.com/wuyong9494-lab/kriswu/blob/532fb03083da7053417b7ad7ba484a99e4c41c28/.github/scripts/fighter_shared_root_native.py)在封包前扫描完整原文，消费者没有拿到完整原文，**不能声称消费端又独立重扫了 12 MB 日志**。两个已知诊断在这段调用中没有出现，不等于全部渲染、持续帧展示、特效比例、音画同步或性能已通过。封包摘要中的 `pixelReview=PENDING` 与后续人工 **FAILED** 结论分别保留。

## 原图审查与缺失覆盖

主代理直接查看了原始 PNG；本报告仅公开标签、摘要和观察，不公开原图。两份方法所属图片均为 **1320 × 2868**，字节保持不变。

| 标签 | 字节数 | 人工实际观察 | SHA-256 |
|---|---:|---|---|
| `shared-root-ui-sun-lobby` | 3,389,361 | 孙登原人物、舞台与双武器可见；大厅文案为“死亡森林三魄 · 忍刀双刃”，身份对应黑色双刀 | `b9aa28386c6fee93a139cb9471be6cc1536450a9ee8be7f677798de23d3ea576` |
| `shared-root-ui-failure` | 2,390,401 | 练习场被巨大紫枝遮满，两人物与舞台不可见；生命 1,000／1,000、命中 0、伤害 0 | `7a8536476de9def9ed5da13a0706a201ffe2626d375497be7d8565d6751f3b02` |

五个缺失必需截图标签为：`shared-root-ui-sun-practice`、`shared-root-ui-sun-root-observed`、`shared-root-ui-sun-root-control-released`、`shared-root-ui-liu-lobby`、`shared-root-ui-liu-practice`。观察附件虽然存在、方法与设备归属正确，但 `flowCompleted=false`，因此它的完整场景门禁同样失败。失败截图只能保留诊断，不能替代这些成功阶段截图。

密封策略实际保存 **4 个 UI 附件文件、5,796,326 B**（两份 PNG、观察 JSON 与 manifest）；另有 **18 项不支持格式的自动诊断记录**被省略，视频省略数为 0。这些省略记录不计覆盖率。附件导出阶段保留了“方法所属集合不完整”和“观察未完成真实控件场景”的实际失败；没有把部分封存成功当成验收通过。

失败后另行生成两份刘泉纬大厅备用诊断图片。两份原文件均为 **1,810,848 B**，SHA-256 同为 `f6054ed7358280685f4473812f6169bf1828732cada366c330c40e3afcaccea5`，字节完全相同；均不能证实刘泉纬人物、武器或完整大厅已显示。它们没有方法覆盖资格，也不能补足刘泉纬大厅／练习场截图。工具显示差异不作为原图不同的证据。

## 历史原生通过记录继续保持独立

| 原运行与源提交 | 已有结果 | 适用范围 |
|---|---|---|
| [43644209347](https://github.com/wuyong9494-lab/kriswu/actions/runs/43644209347)，`68f1e7de45351c3e4b2607c56ff8ab111d0c7130` | 历史 5 项通过 | 合成绑定与能力约束；不代表原媒体播放或本次执行 |
| [43647414701](https://github.com/wuyong9494-lab/kriswu/actions/runs/43647414701)，`5788ebb1001a6e0f31c5208cb2b955b48b00741c` | 历史 6 项通过 | 已安装音频绑定／解码、模型与共享动作加载、受限材质 uniform；该运行视觉仍失败 |

这两组方法的选择器、原工件及结果摘要固定在对应 JSON 中，本次 `selectedAgain=false`、`countsBelongToCurrentRun=false`。旧 117 项也未重跑。前次 [material 报告](fighter-shared-root-material-run-43647414701.md)与 [大厅源码编译报告](fighter-lobby-source-compile-run-43648900087.md)分别保留其原提交证据。

本次大厅新文案和孙登模型可见属于 `532fb030…` 的实测画面；不能反向改写 `5788ebb…` 的旧文案截图。刘泉纬当前仍是双锤 profile，备用截图没有验证其完整显示，更没有证明盘古 D19 独立模型、五类装备或技能资源完成。

## 固定源码与资源身份

| 文件或资源 | SHA-256 |
|---|---|
| [DuelTriadSurfaceFrameDriver.swift](https://github.com/wuyong9494-lab/kriswu/blob/532fb03083da7053417b7ad7ba484a99e4c41c28/App/Services/DuelTriadSurfaceFrameDriver.swift) | `1986d589d7ca309e426491f818f4f9e0f9d81a2a99f6a2c4c2e1b6274f347849` |
| [DuelWorld.swift](https://github.com/wuyong9494-lab/kriswu/blob/532fb03083da7053417b7ad7ba484a99e4c41c28/App/Views/DuelWorld.swift) | `e01058a8f5f57ce516621534f0e642397537a3532b7b3ffc88e80cf93bcf948e` |
| [DuelView.swift](https://github.com/wuyong9494-lab/kriswu/blob/532fb03083da7053417b7ad7ba484a99e4c41c28/App/Views/DuelView.swift) | `7576166011575d14e94a7d8fc880039afc3cd03cd1b8eab02928ec66beed3925` |
| [UI 方法](https://github.com/wuyong9494-lab/kriswu/blob/532fb03083da7053417b7ad7ba484a99e4c41c28/Tests/ArenaFlowTests/DuelSharedRootVisualCaptureTests.swift) | `d144949cad4b14eeef47ad7bf7d0134a5671016732d9690f77599aa54b911cee` |
| 材质源码 | `efb78001996c8e66721cafbcdb99765b3af9d4ca17e827385ca6d3968ef75856` |
| 工作流 helper | `945f612990abba097a5b53a45b25d9230f8bfde14628d4a78e6e631e26782036` |
| 工作流 | `5825c575999c1b15cbef2860a083fde618036cc8ba7ebd9a7fcaebd91ce42b42` |
| 资源 release | `e5c0ccaeef85ce86c5b8fd4ee64524794d6556f5a561f4078362f6899bedf4e5` |
| 增量 manifest | `d50b7fc6f711a55849b259b0f78d348612782f5e3765f9629db50291e20fe2b9` |

加密 [artifact 14136917363](https://github.com/wuyong9494-lab/kriswu/actions/runs/43652056280/artifacts/14136917363) 为 **14,859,820 B**，GitHub SHA-256 为 `8148983028f3cfdd4f5e445c0b91c700827ab0f45f339ccc934d67a3bccb4a42`。唯一消费已经验证 GitHub 摘要、四项密文外层、认证解封、canonical 身份及 **58 项**私有证据清单。本次没有 UI recovery 密文，也没有复用历史测试产物；私有证据已保留。

剩余工作包括定位练习场准备条件未解除和巨大紫枝遮挡的原因，完成真实暗影输入与根缚链，以及双方方法所属场景、刘泉纬独立盘古资源、音频实播和真机验收。此证据快照中根因仍待确认，不能据此宣称已修复。报告没有写入密钥、私有文件路径、原媒体或存储标识，没有上传 TestFlight，也没有修改游戏源码或工作流。

完整计数、源文件链接、历史选择器、截图与日志摘要见 [对应 JSON](fighter-shared-root-ui-remediation-run-43652056280.json)。
