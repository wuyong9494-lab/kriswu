# 已执行：frame 0 场景关联诊断，Run 43666784396

公开元数据记录时间：北京时间 **2026-11-15 10:32:44（UTC+08:00）**；已在根代理唯一认证消费及四图审查后补齐结果。配套[机器可读结果](fighter-scene-registration-run-43666784396.json)保存同次执行的完整安全元数据。

**唯一新 native 方法实际为 1 PASS / 0 FAIL / 0 skipped；原图 A/B/C 均为不透明纯黑，只有 D 在关联辅助 renderer 后由原 surface 输出可见。UI 未选择。** 根代理已唯一认证消费全部工件并逐张审图。原 renderer 重绑没有在本次状态恢复画面；D 仅确认辅助关联后的输出变化，不能作为常驻无用 fresh renderer 的生产修复依据。自动化 `pixels=PENDING` 原样保留，人工分支观察单独记录。生产 App/Core 仍为 `532fb030…`，本次没有改生产渲染代码。 本轮结论为 **`partial_scope_only`**，不证明任何后续生产候选已经修复或执行。

## 执行身份

| 项目 | 实际值 |
|---|---|
| 执行提交 | [09f2f3c2ea1c8ad0283e920d442995a5faa1b254](https://github.com/wuyong9494-lab/kriswu/commit/09f2f3c2ea1c8ad0283e920d442995a5faa1b254) |
| 远端树 | `f76e34004825d8749c03e11bbcd7ff9d59d895b7` |
| 仓库 / 分支 | `wuyong9494-lab/kriswu` / `codex/fighter-visual-acceptance-20261113-1200` |
| 本入口保留源码基准 | `4bd85374273b39f61724342b7e1d72631ab2042d` |
| 未修改的 App/Core 基准 | `532fb03083da7053417b7ad7ba484a99e4c41c28` |
| Actions run / job | [43666784396](https://github.com/wuyong9494-lab/kriswu/actions/runs/43666784396) / [132667820513](https://github.com/wuyong9494-lab/kriswu/actions/runs/43666784396/job/132667820513) |
| run number / attempt | 1 / 1；不是旧 run 的 rerun |
| workflow | [fighter-scene-registration-diagnostic.yml](https://github.com/wuyong9494-lab/kriswu/blob/09f2f3c2ea1c8ad0283e920d442995a5faa1b254/.github/workflows/fighter-scene-registration-diagnostic.yml) |
| 最终 run / job 状态 | `completed/success` / `completed/success` |
| 执行范围 | `installed-scene-registration-diagnostic-one` |
| 资源环境 | 既有 `fighter-private-assets` 正常审批，保护规则保持 |
| 工具 | 已安装的 Xcode 26.6；本次拥有的 iPhone 17 Pro Max 模拟器 |

同 SHA 共注册 **12 个 runs**：本入口 1 个 completed/success，其他 **11 个 completed/skipped**。skipped 表示没有执行，不能计作通过；逐 run 的 ID、名称、URL、状态及时间均在配套 JSON 中。

## 实际方法与计数

唯一选中的方法为：

```text
SiteTests/DuelSceneRegistrationDiagnosticTests/testInstalledSceneRegistrationChangesAreIsolatedAtFrameZero
```

[Swift 源文件](https://github.com/wuyong9494-lab/kriswu/blob/09f2f3c2ea1c8ad0283e920d442995a5faa1b254/Tests/SiteTests/DuelSceneRegistrationDiagnosticTests.swift)的固定 SHA-256 为：

```text
87c876e637fd4e6afd9656a848a302cf0813b4d46a0e6948793778622fe45e1b
```

最终公开 job 日志明确给出 `totalTestCount=1`、`passedTests=1`、`failedTests=0`、`skippedTests=0`；测试进程 exitCode=0、selectedCount=1、iterations=1。精确方法与所属设备门禁为 true。该计数来自实际结果字段，不是只看 workflow 的 success 状态。

UI 字段为 `expectedUIMethods=0`、`uiExecutionStatus=not_selected`、`uiExactMethodPassed=false`、`uiArtifactsAbsent=true`。没有把零项 UI 当成通过。根代理唯一消费者已认证复核原始 xcresult 导出、精确方法集合、一次执行、所属模拟器和完整附件；缺失 / 意外 / 重复 selectors 及失败集合均为空。

新入口的 **18 项独立离线门禁检查**由根代理首次执行一次，结果 **18 PASS / 0 FAIL / 0 skipped，0.359 秒**；它们只检查本入口身份、参数、四图合同及证据闭包，不能算作 Apple 执行或像素验收。

## 四图实验顺序与控制范围

四图均由同一个原 surface 调用 `captureFrame`，画幅 **956 × 440**，请求 samples=2、实际格式解析为 4。所有采集均冻结在 frame / animationTick / source live tick / clock callback / FX packet 为 0 的状态。

| 标签 | 原 projector | 原 renderer 重绑累计 | fresh 创建 / 关联累计 | 操作 |
|---|---:|---:|---:|---|
| `registration-base-before` | 关闭 | 0 | 0 / 0 | 显式 draw 前先移除 projector，随后原 surface 采图 |
| `registration-original-projector` | 开启 | 0 | 0 / 0 | 恢复同一原 projector，仅采图 |
| `registration-original-rebound` | 开启 | 1 | 0 / 0 | 原 renderer 的 scene 置 nil，再绑定同一 scene / camera 并 flush |
| `registration-fresh-associated` | 开启 | 1 | 1 / 1 | 创建一个 fresh renderer 并关联同一 scene / camera，仍由原 surface 采图 |

fresh renderer **不 render、不 prepare、不 snapshot，也不用于任何 capture**。结束时只验证解绑 scene / camera / delegate 及清除本测试的强引用；没有宣称已证明 ARC 析构，没有解绑后的第五张图。

源码要求实验改变前 `surfaceSubmittedFramesBeforeExperiment=0`，用于核实正常 drawable 提交边界。显式 draw 后的正常提交次数与 lastSubmittedTick 只记录实际值，**不强制提交一次**；四张图必须与该快照一致。 `explicitDrawStateCalls=1` 只统计这个测试的显式调用；World 构造末尾已有的 drawState 仍存在，不能将此字段扩展为“整个生命周期总共 draw 一次”。captureFrame 的回读不增加正常提交计数。

最终公开摘要已实际核定：

| 字段 | 观察值 |
|---|---:|
| `registrationSequenceVerified` | true |
| `originalRendererRebindCallCount` | 1 |
| `freshRendererCreateCount` | 1 |
| `freshRendererAssociationCallCount` | 1 |
| `freshRendererRenderCallCount` | 0 |
| `prepareCallCount` | 0 |
| `snapshotCallCount` | 0 |

相邻 PNG 的实际摘要关系为 **[true, true, false]**：A=B=C，C≠D。它们是原始字节的观察结果，不是预设通过条件。图像内容以根代理逐张查看的原 PNG 为依据，不由附件大小或 metadata success 推测。

## 原图与实际不变量：A/B/C 失败，D 仅诊断可见

根代理逐张查看了同一 run 的四张原始 PNG，未重编码或修改图片：

| 原图 | 原始字节 | SHA-256 | 人工观察 |
|---|---:|---|---|
| A：registration-base-before | 9,664 | `d057703632281c9f98c789fc1531a33b658d3301494a16a04a8fefcf69f89cd0` | 不透明纯黑，FAILED |
| B：registration-original-projector | 9,664 | 同 A | 不透明纯黑，FAILED |
| C：registration-original-rebound | 9,664 | 同 A | 不透明纯黑，FAILED |
| D：registration-fresh-associated | 725,786 | `9db122f86b55a45897bc5215bf32c19e3ded7498dec48d745b5ac66fcef05bb9` | 宫殿、Sun 首出生浮空姿态、Liu 既有双锤可见；只属于该隔离分支 |

A/B/C 的摘要和字节数与此前已逐像素测得的黑图完全一致：**420,640 / 420,640 像素为 RGBA(0,0,0,255)**，不是透明图被查看器显示成黑底。D 保持原 surface、原 scene / camera / projector 采集；fresh 的 render / prepare / snapshot 均为 0。D 中 Liu 的可见双锤没有被记作盘古资产完成。

实验前正常提交计数实际为 **0，lastSubmittedTick=null**。本测试显式 draw 后实际为 **1，tick=0**，四次 capture 均保持 1 / 0，未增加正常提交数。这证实的是提交发生过，不是基础画面正确；A 随后仍全黑。四个样本均为 frame / animationTick / source live tick / displayLinkCallbacks / packet count 为 0，source stance 为 `firstBirth` tick 0；HP 保持 1000 / 1000，Sun / Liu 的 x 为 2580 / 6500，weaponReady / branchesReady 为 false。

四份完整 camera、sceneInventory 和 lights JSON 均逐值与 A 相同；surface / renderer / scene / PoV / 模型身份及游戏状态不变量全部为 true，三个错误字段为空。camera FOV 24.689624786376953°、near / far 0.1 / 350；宫殿有 24 个 geometry / 24 个 visible geometry，Sun 为 26 / 9、9 个 skinner，Liu 为 28 / 6、8 个 skinner。这些已记录元数据保持不变而 D 的像素改变，不能拿“可见节点非空”或“错误字段为空”直接充当像素通过，也尚未定位具体框架机制。

A 的原 projector lastFrame 为 `available=false`；B/C/D 均为同一 tick 0 的元数据，13 个 caster、74,855 个 triangle。A 没有保留帧是允许的观察，未伪造或补造 projector 数据。fresh 只在 D 存在，独立于 active renderer，关联同一 device / scene / eye，delegate 为空，reverseZ / 自动默认照明 / isPlaying 均为 false。

| 内部阶段 | 实际墙钟秒数 |
|---|---:|
| construct-session | 14.620993125 |
| construct-world | 25.090911333 |
| mount-layout | 0.002019958 |
| frame 0 base draw submission | 0.901729458 |
| A capture | 0.492108417 |
| 恢复原 projector | 0.000023083 |
| B capture | 0.058657167 |
| 原 renderer 重绑一次 | 0.000400667 |
| C capture | 0.007273625 |
| fresh 创建并关联一次 | 0.000852333 |
| D capture | 0.006466667 |

capture 的同步时间含 GPU 回读等待，不是 GPU-only 或 live FPS。清理确认原 scene / eye / projector 恢复、fresh 绑定和测试强引用清除、render owner 引用置空、活动 clocks 0 → 0；原报告明确 `freshObjectDeallocationVerified=false`、`postFreshDetachmentCaptureTaken=false`，不做额外生命周期成功推断。

原 JSON 报告 **42,305 字节**，SHA-256 `c92703ed8b37cfcfcf16d2cfd939031a3d19216e80808ad035e7a4fc6bf63619`；附件 manifest **2,761 字节**，SHA-256 `fab37b2ee97d8cb0e7a450d61d277b412e87dc3d53d992dc02479756f4ec30b9`。公开仅保留摘要与观测，原媒体继续私有。

## 因果分析边界

[受保护的 RenderSurface 现有链](https://github.com/wuyong9494-lab/kriswu/blob/09f2f3c2ea1c8ad0283e920d442995a5faa1b254/App/Services/DuelTriadRenderSurface.swift)依次包含 source shadow map、SceneKit 及后置 receiver / Gamma。将 projector 设为 nil，会同时关闭前置 map 和后置 receiver / Gamma；A/B 比较无法单独把问题归因于 map。原 projected-shadow 代码中各独立 encoder 都结束编码，目前没有源码实证支持“Metal 状态泄漏”这一结论。

本次实际为 **B 黑、C 仍黑、D 可见**。因此，“在这个已观察状态对原 renderer 做一次 scene nil → 原 scene / eye 重绑即可恢复”没有成立；此结论不应扩展成所有装配时序均无效。D 仅说明关联辅助 renderer 后，原 surface 的输出发生变化，精确的 SceneKit 内部机制仍未得到证明，不能将常驻无用 fresh renderer 当作生产修复。

D 之后仅执行解绑和清除本测试强引用，没有后续截图，也没有 ARC 析构证明。正常原 projector 冷首帧、解绑后的持续可见、生产实时 UI 都没有在本次获证。候选修复应继续围绕真实装配 / 关联顺序审阅，并以实际正常路径验证，不能凭本轮补猜 FOV、反向 Z、灯光或资源缺失。

## 实际步骤时序

以下为 GitHub job API 的实际北京时间，同日 UTC 减 8 小时。

| 步骤 | 开始 | 结束 | 结果 |
|---|---|---|---|
| job | 10:19:08 | 10:31:22 | success |
| source / 方法 pin | 10:19:30 | 10:19:31 | success |
| Xcode 与工具 | 10:19:31 | 10:19:43 | success |
| 同版本资源认证装配 | 10:19:43 | 10:19:53 | success |
| SiteTests-only build / compiled 373 门禁 | 10:19:53 | 10:26:47 | success |
| 本次模拟器准备 | 10:26:47 | 10:29:13 | success |
| 唯一新 native 方法 / 完整日志扫描 | 10:29:13 | 10:31:10 | success |
| 原附件导出 | 10:31:10 | 10:31:10 | success |
| 加密密封 | 10:31:10 | 10:31:11 | success |
| 仅加密诊断工件上传 | 10:31:11 | 10:31:14 | success |
| 本次设备 / 明文清理 | 10:31:14 | 10:31:20 | success |
| 最终独立门禁报告 | 10:31:20 | 10:31:20 | success |

run 创建于 **10:13:52**，等待既有环境正常批准后启动；最终 API updated_at 为 **10:31:25**。helper 记录的进程时间为 build **412.037 秒**、selected-native **89.106 秒**、summary 导出 **3.199 秒**、tests 导出 **0.119 秒**。认证后的原 XCTest 日志另记方法自身 **44.386 秒**，suite 于 UTC 02:30:16.037 开始、02:31:00.426 完成。内部诊断 elapsed 为 **44.324638 秒**。这些是不同口径的进程 / 方法 / 阶段墙钟，不据此声称 live FPS、GPU-only 耗时或性能通过。

## 完整运行日志与封存 tail

| 项目 | 本次实际值 |
|---|---|
| producer 扫描区间 UTC | 2026-11-15 02:29:32 至 02:31:07 |
| App 首条 / 末条 UTC | 02:30:13.022814 / 02:31:01.590731 |
| 完整原 JSON 大小 | **10,478,550 字节** |
| 全部条目 / App 条目 | **7,935 / 7,935** |
| 完整源 SHA-256 | `22cddc579afeac4f19da7135443d4d542b824f6b38e362e0fb288c3ea857a26f` |
| 两条已知 drawable 诊断 | `doublePresent=0`、`textureAfterPresent=0` |
| 完整 JSON、所属模拟器、runtime gate | true |
| `sealedTextTailOnly` | true |

这只是两条既定 drawable 诊断的完整源扫描结果，不等于所有 GPU 问题均不存在或像素正确。密文中保留的是有界 tail，不能把 tail 的大小和摘要称为完整原日志；实际封存 tail 为 **2,097,152 字节**，SHA-256 `74e6cded420008d04dad8f023cb6de0a8e4d8829918f99595d2be90fac150f1b`。消费者验证的是 producer 已认证扫描回执和确切封存 tail，`fullLogIndependentlyRescanned=false`；没有在本地重新扫描未封存的完整 10 MB 日志。

## 同版本资源和加密工件

真实资源仍为 `h17-shared-root-floorfall-20261115-v2`：

- release SHA-256：`e5c0ccaeef85ce86c5b8fd4ee64524794d6556f5a561f4078362f6899bedf4e5`。
- delta manifest SHA-256：`d50b7fc6f711a55849b259b0f78d348612782f5e3765f9629db50291e20fe2b9`。
- 73 个基础文件、295 个旧 overlay 和既有 13-payload delta 恢复 302 个 overlay，再按两项替换合成为 **373 个 App 文件**。
- 资源认证与 compiled closure 均通过，没有新资源版本上传，没有启用 D19 盘古装备，没有上传 TestFlight。

| 工件字段 | 实际值 |
|---|---|
| artifact ID | `14143116611` |
| 名称 | `fighter-scene-registration-diagnostic-43666784396-1-encrypted` |
| API 大小 | **4,314,533 字节** |
| API SHA-256 | `72278e80030d42c89245a37af32ebadbf7d492e3418b3850c279f6a2d642a23b` |
| 创建 UTC | 2026-11-15 02:31:14 |
| 保留到 UTC | 2026-11-18 02:31:11 |
| 唯一消费状态 | 根代理已完成一次认证消费和四图审查：50 个解封文件、49 个 inventory entries、0 个失败 |

公开 seal policy 的 selectedFileCount=6、selectedBytes=799,844、omittedFileCount=0，表示四张 PNG、一个 JSON 报告和附件 manifest；不是六张图，也不是整个加密包的总文件数。完整 mandatory set 已密封，清理门禁 true。唯一消费者对 GitHub digest、密文 envelope、源码、方法、设备、registration、runtime 回执和附件闭包全部通过；没有调用资源密钥、运行测试或触发工作流。所有原始媒体保持私有，公开报告只包含安全标识、摘要及数字，资源密钥仅用于 stage。监控代理只读现有解封证据，没有下载或解密工件。

## 历史范围不合并

历史 **117 / 5 / 6** 项通过，及 entrance、scene-base、scene-preparation 各 **1 项诊断通过**，均继续归其原提交和原 run，不计入本次 09f2… 的 1 项结果。特别是：

- [43658526616](https://github.com/wuyong9494-lab/kriswu/actions/runs/43658526616)：`cdd0d496…` 的 1 项通过、人工像素 FAILED，仍保留。
- [43661312798](https://github.com/wuyong9494-lab/kriswu/actions/runs/43661312798)：`00442b09…` 的 1 项通过，部分隔离 surface 可见，但生产画面 NOT_VERIFIED。
- [43664242283](https://github.com/wuyong9494-lab/kriswu/actions/runs/43664242283)：`4bd85374…` 的 1 项通过，四图全部不透明纯黑、人工像素 FAILED；prepare(true) 没有治愈证据。
- [43652056280](https://github.com/wuyong9494-lab/kriswu/actions/runs/43652056280)：`532fb030…` 的真实 UI 在 `ember-practice-ready` 失败，本次没有重选 UI，也没有以离屏结果替代该失败。

本次已将“原 renderer 重绑仍黑、仅辅助关联后的原 surface 可见”保留为具体诊断证据。后续若提出最小装配 / 关联顺序修复，仍须实际验证正常原 projector 冷首帧；本次没有实施或证明生产修复。发布、实时 UI、可听音频、性能及 iPhone 17 Pro Max 真机仍分别受阻或待验收，不能被 D 的单张隔离可见图替代。
