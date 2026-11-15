# 已执行：原场景准备与投影器隔离诊断，Run 43664242283

公开元数据记录时间：北京时间 **2026-11-15 09:57:14（UTC+08:00）**；已在根代理唯一消费和逐图审查完成后补齐本报告。此文件与[机器可读结果](fighter-scene-preparation-run-43664242283.json)记录同一次执行。

**本次新方法实际为 1 PASS / 0 FAIL / 0 skipped，但四张原图的人工视觉验收均为 FAILED：每张都是 956 × 440 的不透明纯黑。UI 未选择。** 根代理已唯一认证消费工件并逐张审图；原自动化字段 `pixels=PENDING` 保持原样，人工失败另行记录。活动 renderer 的 prepare 返回 true、耗时约 53.877 毫秒，前后四图仍完全同字节，**没有“单独 prepare 可以治愈黑场”的证据，不能为生产 World 修复背书**。本次没有修改生产 App/Core，其基准仍是 `532fb030…`。

## 执行身份与证据入口

| 项目 | 本次实际值 |
|---|---|
| 仓库 / 分支 | `wuyong9494-lab/kriswu` / `codex/fighter-visual-acceptance-20261113-1200` |
| 执行提交 | [4bd85374273b39f61724342b7e1d72631ab2042d](https://github.com/wuyong9494-lab/kriswu/commit/4bd85374273b39f61724342b7e1d72631ab2042d) |
| 执行树 | `4c83c58cefc9f411760146b1d6327b7c96c3d4f8` |
| 本入口保留源码基准 | `00442b097747d95308ca69339fa999a46c216bc6` |
| 未改变的 App/Core 所属提交 | `532fb03083da7053417b7ad7ba484a99e4c41c28` |
| 工作流 | [fighter-scene-preparation-diagnostic.yml](https://github.com/wuyong9494-lab/kriswu/blob/4bd85374273b39f61724342b7e1d72631ab2042d/.github/workflows/fighter-scene-preparation-diagnostic.yml) |
| Actions run / job | [43664242283](https://github.com/wuyong9494-lab/kriswu/actions/runs/43664242283) / [132659987438](https://github.com/wuyong9494-lab/kriswu/actions/runs/43664242283/job/132659987438) |
| run number / attempt | `1 / 1`；不是旧 run 的 rerun |
| 最终状态 | run、job 均 `completed/success` |
| 唯一执行范围 | `installed-scene-preparation-diagnostic-one` |
| 环境与平台 | 既有 `fighter-private-assets` 正常审批；Xcode 26.6；新建本次拥有的 iPhone 17 Pro Max 模拟器 |
| 批准边界 | 沿用既有授权与保护规则；未改 reviewer、bypass 或分支保护 |

以上身份、时序、计数来自同一 run 的 GitHub API 和最终公开 job 日志；本报告不使用本地快照 commit 充当远端源 SHA。

## 实际方法与计数

唯一选择的方法：

```text
SiteTests/DuelScenePreparationDiagnosticTests/testInstalledScenePreparationAndProjectorAreIsolatedWithoutAdvancing
```

源文件为 [DuelScenePreparationDiagnosticTests.swift](https://github.com/wuyong9494-lab/kriswu/blob/4bd85374273b39f61724342b7e1d72631ab2042d/Tests/SiteTests/DuelScenePreparationDiagnosticTests.swift)，SHA-256 为 `bde3a67170b9dad7b602a5c9bb18f8a6f58c94b61c4f1974783c08e3736eb02f`。

最终公开结果明确记录：

| 证据字段 | 观察值 |
|---|---|
| `nativeObservedCounts.totalTestCount` | 1 |
| `passedTests / failedTests / skippedTests` | **1 / 0 / 0** |
| `nativeProcess.exitCode` | 0 |
| `nativeProcess.selectedCount / iterations` | 1 / 1 |
| `nativeExactMethodPassed` | true |
| `expectedUIMethods` | 0 |
| `uiExecutionStatus` | `not_selected` |
| `uiExactMethodPassed` | false，未把“0 项未执行”记成通过 |
| `uiArtifactsAbsent` | true |

方法选择、实际结果集合、次数和所属模拟器均由[本次独立 helper](https://github.com/wuyong9494-lab/kriswu/blob/4bd85374273b39f61724342b7e1d72631ab2042d/.github/scripts/fighter_scene_preparation_diagnostic.py)门禁核对。根代理唯一消费者已对原始 xcresult 导出、精确方法集合、次数、设备和原附件完成独立认证复核，缺失 / 意外 / 重复 selector 均为空、失败集合为空。通过计数来自实际方法结果，不由 workflow 的 `success` 单独推导。

本入口新增的 18 项离线门禁检查由根代理首次执行一次，结果为 **18 PASS / 0 FAIL / 0 skipped，0.251 秒**。这些是合成身份、参数、结果与证据关联的检查，不是 Apple 图像执行，也没有重跑既有成功集合。

## 本次诊断究竟改变什么

这是同一个已安装真实资源的 frame 0 离屏实验。保留同一场景、相机、角色和活动 surface renderer，仿真推进 **0 次**，display-link 回调 **0 次**，没有新建 renderer 或走 snapshot。只在第二、第三张图之间，调用一次活动 renderer 的同步 `SCNRenderer.prepare(_:shouldAbortBlock:)`。

| 原图标签 | 原 source projector | 活动 renderer 已显式 prepare 次数 | 比较用途 |
|---|---:|---:|---|
| `prep-original-before` | 安装并用于该次 capture | 0 | 准备前的原状态 |
| `prep-no-projector-before` | 暂时移除 | 0 | 准备前关闭 projector 的对照 |
| `prep-no-projector-after` | 继续移除 | 1 | 同一个活动 renderer prepare 后的对照 |
| `prep-original-after` | 恢复同一个原 projector | 1 | 准备后恢复原状态 |

固定画幅为 **956 × 440**，原 surface 样本请求值 2、解析后的 MSAA 值 4；源 FX packet 预期为 0。SceneKit 灯光不改变。样本记录模型身份、相机、场景、灯光、原 projector 的保留帧信息及 CPU 阶段时间；这些数据不能代替原 PNG 的人工审查。

最终公开摘要和受保护报告的实际值均为 `prepareCallCount=1`、`preparationSucceeded=true`，完整四图报告验证和密封闭包门禁均为 true。原报告的 `restoredPNGEqualsOriginal=true` 和 `basePNGEqualsBeforePreparation=true` 与四张 PNG 的实际摘要一致。两者是观察值，不是预设成功条件。如果 prepare 返回 false，入口仍会保留完整四图并使总体门禁失败；本次没有走该失败分支。

## 四张原图：人工审查 FAILED

根代理逐张查看原 PNG，并进行只读像素统计；未修改、压缩或重新编码原图。四图都为 **9,664 字节**，原始 SHA-256 完全相同：

```text
d057703632281c9f98c789fc1531a33b658d3301494a16a04a8fefcf69f89cd0
```

每张均为 **420,640 / 420,640 个 RGBA(0,0,0,255) 像素**，唯一 RGBA 数为 1，透明像素为 0。它们是原始不透明黑色输出，排除了“透明图被查看器显示为黑底”的解释；也与此前 `cdd0d496…` 入口诊断的黑图摘要相同。人工结果独立记为 `FAILED / OPAQUE_BLACK`，没有改写原自动报告中的 `pixels=PENDING`。

四个样本均保持 frame / animationTick / sourceLiveTick / displayLinkCallbacks / submittedPackets 为 0，源入场为 `firstBirth` tick 0。Sun 的 HP / x 为 1000 / 2580，Liu 为 1000 / 6500；weaponReady 与 branchesReady 均为 false。这里是冻结入场首帧，未执行战斗技能，不能扩展成游戏实时输入验收。四个样本中的 active surface、active renderer、scene、PoV 及模型身份相同，renderer / surface / source preparation failure 字段为空，但空错误字段同样不能证明像素正确。

场景元数据中宫殿有 24 个 geometry / 24 个 visible geometry；Sun 为 26 / 9，9 个 skinner；Liu 为 28 / 6，8 个 skinner。camera 的 model 与 presentation world transform 在四个样本中一致，FOV 为 24.689624786376953°、near / far 为 0.1 / 350。这些元数据与全黑输出同时存在，说明“节点可见 / 几何非空”不能代替渲染结果。保留的 projector lastFrame 显示 tick 0、13 个 caster、74,855 个 triangle；B/C 的 projectorEncodedForCapture 仍为 false，保留 metadata 不等于这两次实际编码了 projector。

prepare 实际耗时 **0.05387691666669525 秒**，返回 true，调用前后都是原活动 renderer / scene / PoV。准备前的关闭 projector 图 B 与准备后的图 C 仍同字节，原状态 A 与恢复后的 D 也同字节。因此本次没有单独 prepare 的治愈证据；不据此修改或背书生产 World。

| 内部阶段 | 实际墙钟秒数 |
|---|---:|
| construct-session | 19.535777542 |
| construct-world | 35.169066083 |
| mount-layout | 0.006015542 |
| frame 0 draw submission | 3.855245375 |
| A：原状态 capture | 0.966153792 |
| B：关闭 projector、prepare 前 capture | 0.013189208 |
| 活动 renderer 同步 prepare 一次 | 0.053876917 |
| C：关闭 projector、prepare 后 capture | 0.014067875 |
| D：恢复原 projector capture | 0.013440250 |

capture 的同步墙钟包含 GPU 回读等待，不能分解成 GPU-only 时间，也不是生产 live FPS。stateInvariant / restorationInvariant 均为 true；所有 render owner 已释放，原 projector 在 shutdown 前恢复，活动 clock 从 0 保持到 0。

原 JSON 报告为 **40,051 字节**，SHA-256 `f73ffaa9eb0bebbbc398eb0238556ca04e6a5baa8153807bec7f3b152fdecb62`；附件 manifest 为 **2,744 字节**，SHA-256 `b6a0635daa339e76272d5096a113aafa164e6f748ae9c2cf3fd5ed404c5883d5`。原图和完整私有报告保留在受保护证据中；公开仅列标识、摘要、数字和结论。

## 步骤时序

下表为 GitHub job API 的实际步骤时间；显示为北京时间，同日对应 UTC 减 8 小时。

| 步骤 | 开始 | 结束 | 结果 |
|---|---|---|---|
| job | 09:42:06 | 09:55:18 | success |
| 源码 / 方法 pin | 09:42:26 | 09:42:27 | success |
| Xcode 与工具 | 09:42:27 | 09:42:42 | success |
| 既有资源认证与装配 | 09:42:42 | 09:42:54 | success |
| SiteTests-only build 与 compiled 373 闭包 | 09:42:54 | 09:50:14 | success |
| 本次模拟器准备 | 09:50:14 | 09:51:54 | success |
| 唯一新方法与完整运行日志扫描 | 09:51:54 | 09:54:57 | success |
| 原附件导出 | 09:54:57 | 09:54:59 | success |
| 证据密封 | 09:54:59 | 09:55:01 | success |
| 仅加密诊断工件上传 | 09:55:01 | 09:55:03 | success |
| 本次设备与明文清理 | 09:55:03 | 09:55:15 | success |
| 最终独立门禁报告 | 09:55:15 | 09:55:15 | success |

run 创建于 **09:41:06**，最终 API 更新于 **09:55:20**。helper 的进程时间分别为 build **438.135 秒**、selected-native **133.490 秒**、xcresult summary 导出 **10.096 秒**、tests 导出 **0.297 秒**。selected-native 是 xcodebuild 测试调用时间；认证后的原 XCTest 日志另记单个方法 **60.447 秒**，suite 于 UTC 01:53:36.068 开始、01:54:36.521 完成。诊断报告内部 elapsed 为 **60.331235 秒**。这些时间口径不同，不声称实时 FPS、GPU 帧耗或性能验收通过。

## 完整日志扫描与密文内 tail 的区别

本次 helper 对完整选定测试调用和结果导出的日志区间进行了成功扫描：

| 项目 | 实际值 |
|---|---|
| 请求区间 UTC | 2026-11-15 01:52:22 至 01:54:52 |
| App 首条 / 末条 UTC | 01:53:32.137079 / 01:54:37.803889 |
| 完整原 JSON 大小 | **10,482,733 字节** |
| 完整 JSON 条目 / App 条目 | **7,938 / 7,938** |
| 完整原 JSON SHA-256 | `5dbf7b120903e5fec7d83fb1dcc8d36014ba17e73c07a3682efed8dc520b9499` |
| `doublePresent` / `textureAfterPresent` | **0 / 0** |
| 完整 JSON 解析、所属模拟器、runtime gate | 全部 true |
| `sealedTextTailOnly` | true |

零计数属于这两条已知 drawable 诊断的完整扫描结果，**不是“所有 GPU 问题为零”或像素正确的证明**。密文中仅保留有界文本 tail，不能将 tail 的字节数、摘要或可见日志等同于完整 10,482,733 字节源日志。唯一消费者已验证实际封存 tail 为 **2,097,152 字节**，SHA-256 `b9bda253e7a003225bb9f6ca875dac4b7f583bb48cd177f33051837511fd5fa9`。完整扫描是在已钉源码的 producer 中完成；消费者独立核对的是已认证的源扫描回执及完整封存 tail，**没有在本地重新扫描未封存的完整 10 MB 日志**。

## 资源与工件边界

资源版本保持 `h17-shared-root-floorfall-20261115-v2`，release SHA-256：

```text
e5c0ccaeef85ce86c5b8fd4ee64524794d6556f5a561f4078362f6899bedf4e5
```

13-payload delta manifest SHA-256：

```text
d50b7fc6f711a55849b259b0f78d348612782f5e3765f9629db50291e20fe2b9
```

认证链仍为 73 个基础文件、295 个旧 overlay 文件与既有 13-payload delta，先恢复 302 个 overlay，再按约定替换两项而合成 **373 个 App 文件**。认证与 compiled closure 均已通过；没有重复上传资源版本，没有激活 D19 盘古装备，没有上传 TestFlight。三个既有资源密钥仍仅用于 stage；公开报告不含密钥、媒体或私有持久存储标识。

| 加密工件字段 | 本次实际值 |
|---|---|
| artifact ID | `14141926549` |
| 名称 | `fighter-scene-preparation-diagnostic-43664242283-1-encrypted` |
| API 大小 | **3,578,138 字节** |
| API SHA-256 | `6094c29f2c213e35fc23bb4b5c8cfa8e7d22049539a022814a644b9cdb13075a` |
| 创建 UTC | 2026-11-15 01:55:03 |
| 保留到 UTC | 2026-11-18 01:55:02 |
| 唯一消费状态 | 根代理已完成一次认证下载 / 解封和四张原图审查；50 个解封文件、49 个 inventory entries、0 个失败 |

公开 seal policy 记录 selectedFileCount=6、selectedBytes=81,451、omittedFileCount=0；这里的 6 是四张 PNG、JSON 报告及附件 manifest 的封存关联，不是“六张图”或完整工件总文件数。完整 validated mandatory set 已被纳入密文；清理门禁 true。根代理唯一消费验证了 GitHub digest、密文 envelope、源码身份、精确方法 / 设备和完整附件集合；consumer 没有使用资源密钥、运行测试或触发 workflow。监控代理仅随后只读现有解封证据，没有下载或解密工件。

## 历史证据保持独立

| 历史 run | 原源提交 | 已有自动化结果 | 本次处理 |
|---|---|---|---|
| [43611931466](https://github.com/wuyong9494-lab/kriswu/actions/runs/43611931466) | `ef306408…` | 117 项通过 | 未重选，不归本 SHA |
| [43644209347](https://github.com/wuyong9494-lab/kriswu/actions/runs/43644209347) | `68f1e7de…` | 5 项通过 | 未重选 |
| [43647414701](https://github.com/wuyong9494-lab/kriswu/actions/runs/43647414701) | `5788ebb1…` | 6 项通过 | 未重选 |
| [43658526616](https://github.com/wuyong9494-lab/kriswu/actions/runs/43658526616) | `cdd0d496…` | 1 项诊断通过，人工像素 FAILED | 未重选，不覆盖像素失败 |
| [43661312798](https://github.com/wuyong9494-lab/kriswu/actions/runs/43661312798) | `00442b09…` | 1 项诊断通过，隔离 surface 可见；生产像素 NOT_VERIFIED | 未重选 |
| [43652056280](https://github.com/wuyong9494-lab/kriswu/actions/runs/43652056280) | `532fb030…` | 真实 UI 在 `ember-practice-ready` 失败 | 本次 UI 未选；旧失败没有被离屏诊断替代 |

本 SHA 注册 **12 个 workflow runs**：本诊断 1 个 completed/success，另 11 个 completed/skipped。skipped 只表示未执行，不计通过；逐 run 的 ID、名称、链接和状态保存在配套 JSON 中。

## 当前结论与下一步

**自动化证据链完整，人工像素验收失败，发布仍受阻。** 同一活动 renderer 的一次成功准备没有让四图中的任意一张显示角色或场景；本轮不支持把“补一次 prepare”作为 World 修复，也不能从 projector 关闭后仍黑这一观察推定其已是唯一根因。此前 `00442b09…` 的移除 projector 隔离实验曾显示角色与宫殿，本次不同控制序列下四图全黑，差异需要保留并继续基于真实执行定位，不能把两轮合并成生产已修复。

后续应围绕实际渲染路径差异确定最小因果修复；实时 UI、可听音频、性能和 iPhone 17 Pro Max 真机仍分别待验收。原始图像不公开，相同黑图不重复上传。本报告不授权重跑既有成功方法或重复资源版本上传。

