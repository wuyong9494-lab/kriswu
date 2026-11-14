# Shared-root 原生 run 43644209347：实际资源门禁失败与最小后续范围

## 已执行结果

本次已实际执行 **9 个原生方法：5 通过、4 失败、0 skipped；另 1 个 UI 方法失败、0 skipped**。工作流结论为 `completed / failure`，不能把构建成功、密文工件上传或流程完成当成验收通过。

- [运行记录](https://github.com/wuyong9494-lab/kriswu/actions/runs/43644209347)；[任务记录](https://github.com/wuyong9494-lab/kriswu/actions/runs/43644209347/job/132598234049)。
- GitHub 源提交：`68f1e7de45351c3e4b2607c56ff8ab111d0c7130`；有效应用基准：`6ebca235dfb579454c99528791f5c8e84bc9ff6f`。
- 运行 attempt 1；最后更新时间：北京时间 `2026-11-15 06:02:15`；Xcode 26.6、iPhone 17 Pro Max **模拟器**、iOS 26.5 arm64。
- 工件 `14133862654`，14,828,908 bytes，SHA256 `c0b586e5cea26be6e243d0156f1d4b1f57effbc52bfdbff3721b2c412af0c0a8`。根代理已下载并认证解封一次；本报告只使用既有明文证据，不重复下载或解密。

73 个基础文件、295 个旧 overlay 文件及 13 个增量 payload 均已认证；一次 unsigned build 成功，编译包内 373 个资源逐项 bytes/SHA 匹配。随后 XCTest 方法执行才揭示加载失败。

## 精确方法结果

| 原生方法 selector | 实际结果 |
| --- | --- |
| `SiteTests/DuelSharedRootInstalledModelTests/testFinalSharedRootReleaseLoadsBothOriginalCharactersAndAllThreeLiuVictimMotions` | Failed |
| `SiteTests/DuelTriadFloorfallIntegrationTests/testInstalledIntervalsReachTheExistingConsumerOnceAcrossPauseAndReset` | Failed |
| `SiteTests/DuelTriadFloorfallIntegrationTests/testInstalledOriginalBodyFallWAVsDecodeWithoutStartingPlayback` | Failed |
| `SiteTests/DuelTriadFloorfallIntegrationTests/testInstalledReleaseBindsSevenOriginalVariantsAtThreeExactProfileIntervals` | Failed |
| `SiteTests/DuelTriadRootVictimAudioTests/testEveryVictimClipMustMatchSourceSHAFramesTicksGridAndPelvisBeforeSharing` | Passed |
| `SiteTests/DuelTriadRootVictimAudioTests/testMorphTargetMetadataAcceptsOnlyReviewedHammersAndCompleteNewVictimCapability` | Passed |
| `SiteTests/DuelTriadRootVictimAudioTests/testOrdinarySharedThrowsKeepSoundFrameClockWithoutTheRootEndException` | Passed |
| `SiteTests/DuelTriadRootVictimAudioTests/testRootEndRejectsWrongClockFrameContextVariantCountAndSunImpersonation` | Passed |
| `SiteTests/DuelTriadRootVictimAudioTests/testVerifiedRootEndUsesLiuOwnershipAtTick38AndDeduplicatesTheSameFrame` | Passed |

单独 UI selector：`ArenaFlowTests/DuelSharedRootVisualCaptureTests/testFinalSharedRootReleaseShowsBothFightersAndAcceptsSunBranchesThroughRealControls`，实际 Failed。两个调用各自 exit 65，两个 xcresult 的方法叶子与汇总计数一致。

这 5 个通过项验证生产音频绑定/能力逻辑的合成输入边界。它们不证明原始 GLB、所有 WAV 或屏幕音画已经通过；后续入口不再次选择这些方法。

## 真实失败步骤与源文件

4 个原资源方法共享同一错误：`descriptor("Missing original uniform: _CustomPos")`。调用链为 `DuelWeaponAssets.init → DuelTriadEffectAssets.init → DuelTriadSourceMaterial.Descriptor.validate → DuelTriadSourceMaterial.Descriptor.materialUniforms`，真实源文件为 [DuelTriadSourceMaterial.swift（失败提交）](https://github.com/wuyong9494-lab/kriswu/blob/68f1e7de45351c3e4b2607c56ff8ab111d0c7130/App/Services/DuelTriadSourceMaterial.swift)。错误发生在描述符验证阶段，早于 Metal 编译以及这些方法所要求的 GLB/音频加载完成。

UI 真正进入选择与练习流程，但在 `ember-practice-ready` 阶段出现 `duel.resourceError`，文本为“人物资源无法载入，请返回后重试。”输入控件被暂停，方法在原有有界预算内失败；没有注入战斗状态。

根代理亲眼审阅同一 UI 方法的两张原 PNG：Sun 大厅可见菜单但角色为空，仍显示武士刀/双锤旧标签；失败图明确显示资源无法载入。图片不是成功角色展示证据，也没有根缚技能或可听音频证据。图片仍只留在受保护证据中，公开 JSON 记录所属 selector、文件名、bytes/SHA。

## 最小后续执行范围：6 原生 + 1 UI

新入口 `.github/workflows/fighter-shared-root-material-followup.yml` 绑定固定 scope `material-followup-six` 和确切提交消息 `Verify shared root material followup 20261115`。旧 9+1 入口和两次历史记录保留。

本轮唯一应用改动是 `App/Services/DuelTriadSourceMaterial.swift`，SHA256 `efb78001996c8e66721cafbcdb99765b3af9d4ca17e827385ca6d3968ef75856`。其余 436 个 App git 记录固定为摘要 `823f65ee5de955a7dd8ba2de3abd7290ed1e6c3b8fc58bd6bb3f7b193c6c162a`；其余应用、Core、构建输入及旧 Tests 保持基准。新独立 XCTest 文件 `Tests/SiteTests/DuelTriadRuntimeUniformTests.swift` 固定 SHA256 `e982e1ab17702552571a2fc8b00445039cf9e217ad615bf122074e67ece7b3ac`。

修复仅针对 7 个已核对 shader ID/SHA 的 `_CustomPos` scalar width 1 未赋值初态；显式材质值优先，其余缺字段、错误身份或类型仍拒绝。原始运行时 global setter/更新时序尚未恢复，不能把初态适配表述成完整动态语义已经还原。原生执行将核对真实 final v2 的 62 descriptors / 17 相关材质 / 7 shader，并验证负向变体。

| 本次计划执行 | selector |
| --- | --- |
| 此前失败的原资源方法 | `SiteTests/DuelTriadFloorfallIntegrationTests/testInstalledReleaseBindsSevenOriginalVariantsAtThreeExactProfileIntervals` |
| 此前失败的原资源方法 | `SiteTests/DuelTriadFloorfallIntegrationTests/testInstalledIntervalsReachTheExistingConsumerOnceAcrossPauseAndReset` |
| 此前失败的原资源方法 | `SiteTests/DuelTriadFloorfallIntegrationTests/testInstalledOriginalBodyFallWAVsDecodeWithoutStartingPlayback` |
| 此前失败的原资源方法 | `SiteTests/DuelSharedRootInstalledModelTests/testFinalSharedRootReleaseLoadsBothOriginalCharactersAndAllThreeLiuVictimMotions` |
| 新增材质回归 | `SiteTests/DuelTriadRuntimeUniformTests/testInstalledSourceMaterialsResolveOnlyReviewedUnassignedCustomPosition` |
| 新增材质回归 | `SiteTests/DuelTriadRuntimeUniformTests/testUnreviewedMissingUniformsRemainRejectedAndExplicitValuesKeepPriority` |
| 此前失败 UI | `ArenaFlowTests/DuelSharedRootVisualCaptureTests/testFinalSharedRootReleaseShowsBothFightersAndAcceptsSunBranchesThroughRealControls` |

新运行要求恰好 6 个原生方法和 1 个 UI 方法各执行一次、0 failed、0 skipped、无多余/缺失/重复方法。新运行计数不加上 run 43644209347 的 5 个历史 PASS。原生 720 秒、UI 360 秒预算不增加，不传无效的 `-test-iterations 1`，不启用失败自动重试。旧 117 个成功方法和本次 5 个成功方法均不执行。

final v2 release 仍固定 `e5c0ccaeef85ce86c5b8fd4ee64524794d6556f5a561f4078362f6899bedf4e5`；delta manifest 仍为 `d50b7fc6f711a55849b259b0f78d348612782f5e3765f9629db50291e20fe2b9`。95 WAV / 115 markers / Sun 65 clips / Liu 59 clips、373 资源闭包保持。Liu 身份仍为 `liu_hammers`，没有 D19 激活，没有重复转换、上传资源或 TestFlight 上传。

三个既有资源密钥只在 stage 注入；沿用已授权的 `fighter-private-assets` 环境保护和审批。失败仍保留原 xcresult 正文与部分附件，密封后只上传密文，随后清理所属明文和模拟器。模型报告仍按模型方法 selector 归属，而非新增材质方法。

## 本地验证与仍待完成

仅首次执行新增的 8 项 Python 范围检查：**8 passed / 0 failed / 0 skipped，0.041 秒**。检查真实文件 pin、其它源树不变、固定 6+1 的参数与结果集合、拒绝混入历史 5 项、来源范围绑定、原有预算与 stage-only secrets。xcodebuild 与结果导出使用 mock；未执行 Apple 原生方法，未重跑旧 16 项 helper 检查。

新 Apple 6+1 的实际结果仍待后续运行。模拟器图片仍需逐图审查；本轮未做 iPhone 17 Pro Max 真机、性能、可听播放或 TestFlight 验收。上一 run 43642548703 的 CLI 参数错误造成 0 方法执行，保存在独立报告，不能与本次真正的方法失败混淆。

本报告的完整计数、精确方法、证据摘要及后续 pins 见同名 JSON。
