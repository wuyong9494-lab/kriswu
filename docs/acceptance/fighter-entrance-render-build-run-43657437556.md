# 入场渲染诊断构建失败：43657437556

**本次在 Swift 编译阶段失败，新原生诊断方法没有开始执行；实际原生执行数为 0，UI 执行数为 0，没有截图。** 计划选择一个方法不等于实际执行一个方法，不能将本次记为“1 个方法 FAIL”，也不能把后续步骤的 `completed / skipped` 当作通过。

资源认证与 staging 已成功，编译后 373 项资源核验没有完成。失败日志已加密封存，最终清理成功。既有练习场视觉问题、真实玩法与真机验收的发布阻塞没有因此解除。

## 运行与被测源提交

| 字段 | 实际值 |
|---|---|
| 被测候选 | [`7a8fc821b2a6ee911f843555f70c292ca1a82afc`](https://github.com/wuyong9494-lab/kriswu/commit/7a8fc821b2a6ee911f843555f70c292ca1a82afc) |
| 固定基线 | `532fb03083da7053417b7ad7ba484a99e4c41c28` |
| Actions | [43657437556](https://github.com/wuyong9494-lab/kriswu/actions/runs/43657437556) |
| Job / Attempt | [132638998961](https://github.com/wuyong9494-lab/kriswu/actions/runs/43657437556/job/132638998961) / `1` |
| 执行范围 | `installed-entrance-render-diagnostic-one`；计划一个新原生诊断，UI 未选择 |
| GitHub 最终状态 | `completed / failure` |
| 创建 / 最终状态更新时间（北京时间） | `2026-11-15 08:17:29` / `2026-11-15 08:23:07`（Asia/Shanghai，UTC+08:00） |
| Job 起止（北京时间） | `2026-11-15 08:18:27—08:23:06`（Asia/Shanghai，UTC+08:00） |
| Xcode | `26.6` |
| App／Core | 源码门禁确认与 `532fb030…` 基线一致 |

`7a8fc821…` 是本次实际编译失败的候选。后续诊断统计代码修正及本报告的发布提交应另行记录，不能回写本次源身份。

## 唯一实际 Swift 编译错误

构建日志包含一条 Swift `error:`，位置为固定 [DuelEntranceRenderDiagnosticTests.swift:141](https://github.com/wuyong9494-lab/kriswu/blob/7a8fc821b2a6ee911f843555f70c292ca1a82afc/Tests/SiteTests/DuelEntranceRenderDiagnosticTests.swift#L141)：

```text
call to main actor-isolated local function 'effectiveVisibility' in a synchronous nonisolated context
```

当时 `sceneInventory()` 内的局部 `count(_:)` 被视为同步 nonisolated 上下文，却调用了隔离在 MainActor 的 `effectiveVisibility(_:)`。编译器同时指向该辅助函数的定义位置，说明跨 actor 调用需要满足隔离约束。此处是**新增诊断统计代码的编译问题**，不是此次原生方法内的断言失败，也不是 App／Core 在本次发生了玩法修改。

`native-build` 进程耗时 **234.452 秒**，退出码 **65**。已有静态核对和轻量脚本验证不能替代 Apple 编译器；本次日志是该隔离错误的直接证据。

## 已完成与未到达的门禁

| 阶段 | 实际结果 | 证据边界 |
|---|---|---|
| 源码与新方法身份 | success | App／Core／工程输入仍为固定基线，新诊断源文件有独立摘要 |
| 资源认证与 staging | success | 73 项基础文件、295 项原始 overlay 与 13 项增量 payload 已按原资源身份处理 |
| 最终 staging 目标 | 已建立 | 302 项最终 overlay、289 项未变 overlay，编译资源目标为 373 项 |
| SiteTests host 构建 | **failure** | 新诊断文件的 actor 隔离错误；`234.452 s / exit 65` |
| 编译后 373 项资源核验 | **未完成** | `compiled373ResourcesVerified=false`，不能沿用 staging 成功替代 |
| 模拟器准备 | skipped | 构建失败，未建立本次诊断模拟器证据 |
| 新原生诊断执行 | skipped／未开始 | 计划 1 项，实际 0 项；没有进程回执、xcresult 或测试计数 |
| UI | `not_selected` | 实际 0 项，结果计数为 `null` |
| 附件导出 | failure | `Native result bundle unavailable`，属于没有执行结果包的下游失败 |
| 运行日志门禁 | UNAVAILABLE | 没有诊断运行日志，不能记为两类错误数均为 0 |
| 加密封存／上传／清理 | success | 保留失败元数据和日志；这些成功不是验收通过 |

资源回执明确 `redecodedMedia=false`、`downloadedAssets=false`，资源 release 与既有最终版本保持一致。运行没有形成编译完成的 App 资源核验，也没有执行任何已成功的历史方法。

## 计划方法与实际执行状态

计划的唯一新方法为：

```text
SiteTests/DuelEntranceRenderDiagnosticTests/
testInstalledEntranceCompletesAndCapturesSceneEffectShadowIsolationOnce
```

本次 identity 中的 `nativeExecutionStatus=selected` 记录的是**选择计划**。结合最终构建失败、执行步骤 skipped，以及归档中不存在 `native-process.json`、`native-summary.json`、`native-tests.json`，实际状态为 **`not_started_build_failed`**。

本次原生测试结果计数为 **`null`**，没有 PASS／FAIL／SKIP 的方法结果。Actions 的步骤 skipped 也不等于 XCTest 执行了一个 skipped 方法。UI 为 `not_selected`，同样不产生新的通过数。

原计划的 frame 0、164、394，以及 394 的 full／no-FX／scene-only／restored 对照均**未取得**。归档内没有任何 PNG，没有 `entrance-render-diagnostic-report`，没有完整或截断的运行日志。封包中的 `pixels=PENDING` 只是保留字段；本次有效像素证据状态为 **未运行、无图片**。

## 后续最小诊断源码修正

主代理已在同一个诊断测试文件中准备修正：为可见性与场景统计辅助函数显式保留 MainActor 隔离，并用 `for` 加显式节点栈遍历，替换原 nonisolated 局部计数／枚举调用边界。仅改变诊断统计实现；App／Core、方法选择器和六个截图标签保持不变。

| 项目 | SHA-256 |
|---|---|
| 本次实际失败的 Swift 文件 | `313ab545a90a6b94f197f9d759f94de60bd33a295d1e414dbce5ffb33fa1251a` |
| 后续本地修正后的 Swift 文件 | `9349383bd882fc281e5b28a73a05c0bd4c564ec81c45666b0bdaa41ec962cceb` |

**后续修正尚不能由本次运行证明编译通过。** 该修改也没有证明入场状态、巨大紫枝遮挡或真实 UI 已修复。后续 Apple 构建与尚未执行的新诊断，应使用新的源提交和运行身份取得结果；历史成功测试不需要因此重跑。

## 历史证据独立保留

| 原运行 | 原源提交 | 已有范围 |
|---|---|---|
| [43611931466](https://github.com/wuyong9494-lab/kriswu/actions/runs/43611931466) | `ef3064085879c497d59533459c94b429a40f9cee` | 历史 117 项原生方法通过，本次未选择 |
| [43644209347](https://github.com/wuyong9494-lab/kriswu/actions/runs/43644209347) | `68f1e7de45351c3e4b2607c56ff8ab111d0c7130` | 历史 5 项合成绑定／能力方法通过，本次未选择 |
| [43647414701](https://github.com/wuyong9494-lab/kriswu/actions/runs/43647414701) | `5788ebb1001a6e0f31c5208cb2b955b48b00741c` | 历史 6 项资源／材质方法通过，本次未选择；该运行视觉失败 |

这些历史记录均为 `selectedAgain=false`、`countsBelongToCurrentRun=false`，不加入本次计数。前一轮 [43652056280 UI 与视觉失败报告](fighter-shared-root-ui-remediation-run-43652056280.md)仍保留其 `532fb030…` 证据；当前构建失败没有新增图像来改变那个结论。刘泉纬盘古独立资源、原场景音画同步、真实 iPhone 17 Pro Max 与性能指标也没有获得新的通过证据。

## 证据身份与保全

| 项目 | 已核值 |
|---|---|
| 资源 release | `e5c0ccaeef85ce86c5b8fd4ee64524794d6556f5a561f4078362f6899bedf4e5` |
| 增量 manifest | `d50b7fc6f711a55849b259b0f78d348612782f5e3765f9629db50291e20fe2b9` |
| [本次独立 helper](https://github.com/wuyong9494-lab/kriswu/blob/7a8fc821b2a6ee911f843555f70c292ca1a82afc/.github/scripts/fighter_entrance_render_diagnostic.py) | `f32d00a4d9b88641916deaaa642c5a64f46a21ce3fbf5ad04044494d7ff146f7` |
| [本次工作流](https://github.com/wuyong9494-lab/kriswu/blob/7a8fc821b2a6ee911f843555f70c292ca1a82afc/.github/workflows/fighter-entrance-render-diagnostic.yml) | `56b656514e2e8da05e0b420a205512aa2a38c3b88b8082350bd9fe7180b31ab9` |
| 加密 [artifact 14138663420](https://github.com/wuyong9494-lab/kriswu/actions/runs/43657437556/artifacts/14138663420) | **1,121,700 B**；SHA-256 `c6db6f3b5e5f61592f52fa865359f98103fa539f453ca3ef084802013a66fb1a` |
| 完整构建 stdout | **969,747 B**；SHA-256 `1ab506316c512abccd7d1d0d231ed10e2bf8b68e7f528c0ac9542e4517a4db85` |
| 已认证证据清单 | **27 项**；均为元数据／日志，无尾部截断文件、无截图或测试结果 |
| 最终清理 | `cleanupComplete=true`，`cleanupErrors=[]` |

主代理已唯一下载并认证解封此工件，核对 GitHub 摘要、四项密文外层、canonical 身份与内部清单。本报告仅重新读取已存在的本地元数据、错误日志与公开最终状态，没有重复下载或解密，没有读取私钥，没有运行测试、触发工作流、修改 App／Core／CI 或已有报告，也没有上传 TestFlight。

完整阶段时间、计划与执行区分、摘要和后续修正边界见 [对应 JSON](fighter-entrance-render-build-run-43657437556.json)。
