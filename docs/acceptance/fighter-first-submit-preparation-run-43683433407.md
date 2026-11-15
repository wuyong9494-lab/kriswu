# 首次提交准备回归 43683433407：原生通过，UI 方法通过但结果封存失败

执行源 `903b5b61f399f7db7748c3912fcbb5afaa46553e`（tree `cab91537c63c05ca3031e4d762de457077e2a39c`），基线 `f52c293da885f24ebae7640055161380aba4a5f7`。[运行](https://github.com/wuyong9494-lab/kriswu/actions/runs/43683433407) / [作业 132718802689](https://github.com/wuyong9494-lab/kriswu/actions/runs/43683433407/job/132718802689)，attempt 1，最终 **failure**。作业时间为 **2026-11-15 北京时间 14:00:48–14:17:35（UTC 06:00:48–06:17:35）**。本报告的发布提交不改变实际执行归属。

## 必须分开的三层结果

|证据层|实际结果|计时|
|---|---|---|
|原生结构化 XCTest|**1 PASS / 0 FAIL / 0 SKIP**，exact method once，process exit 0|XCTest 方法 **53.031616 秒**；报告内部 **52.637870 秒**；进程 **160.677 秒**|
|UI 已认证原始控制台|唯一 UI 方法明确 **passed (318.146 seconds)**，套件 **1 test / 0 failures**|北京时间 **14:11:37.721–14:16:55.871**（UTC **06:11:37.721–06:16:55.871**）|
|UI 进程、结构化结果及原图验收|**失败**：进程在 **360.402 秒**退出 **124**，xcresult 未完成，UI 附件未封存|UI 调用步骤 **374 秒**，含后续日志处理|

原生方法是 `SiteTests/DuelActiveRendererPreparationTests/testInstalledActiveRendererPreparationKeepsFirstFrameVisible`；UI 方法是 `ArenaFlowTests/DuelSharedRootVisualCaptureTests/testFinalSharedRootReleaseShowsBothFightersAndAcceptsSunBranchesThroughRealControls`。两者各选择一次，不能合写成“两个原生方法通过”。UI 的 `structuredCounts=null`；原消费者 `observedCount=0` 表示**未从缺失的结构化结果提取到方法记录**，绝不是没有执行 UI 方法。

原始 `selected-ui.log` **9,058 B**，SHA-256 `c1244cd13cae6e8787a60202e746ac803f6d528f12182d7403414c53b65ad7b9`。其中依次记录 6 张截图及 1 份 observations 的 `Added attachment`，随后记录唯一方法通过；这些“Added”不能证明附件已导出。当前工件中的 UI 原图和 observations 文件均为 **0**，不能补写正常画面验收通过。三条失败记录分别涉及 UI 进程与未完成结果包的导出，不是三个失败方法。

## 两张原生原图与有限人工审查

真实顺序为 A 捕获前 request/completion 均 0；A 原 Surface 的 command-buffer commit 触发生产异步准备；真实 request/completion 均为 1、ready 为 true 后再捕获 B。两图均处于 frame/liveTick/animationTick 0，仿真推进、display-link 回调与普通 drawable 提交均为 0。A 是第一次完整离屏编码，B 是第二次；commit 回调不代表 GPU 已完成或 drawable 已显示。

|原图|字节数|SHA-256|
|---|---:|---|
|A · first-submit-before-preparation|725,568|`1f51f284b68084dd97d5ded682a6e767e6aef53cfd6a2b53af514cb21a061c64`|
|B · first-submit-after-preparation|725,774|`60d48e87a95b985c0d4fc1f588211e113f2a4971482558f48f6ff4de779716c8`|

两图均为 **956×440**，420,640 个不透明像素，其中 418,283 个非黑、2,357 个黑、透明 0。统计相同，**原字节及 SHA 不同**。Root 已逐张查看两份原图，宫殿、孙登 H17 firstBirth 姿态与刘泉纬双锤均可见；独立人工审查登记为 **`partial_scope_visible`**。原消费者的 `visualReview=PENDING` 保留原样，不覆盖其原始结论。

这项证据确认有限离屏场景可见和准备顺序回归，不证明正常 drawable、完整 UI 画面、角色动作全集、可听音效、性能或物理 iPhone 验收。刘泉纬仍为 `liu_hammers / isPangu=false`，不能登记盘古资源已完成。

## 日志、封存与后续

Producer 扫描了完整调用范围的原生 **10,480,461 B / 7,937 条**与 UI **25,601,742 B / 18,567 条**日志，两类已知 drawable 诊断均为 0。消费者认证了扫描回执与各 **2 MiB 尾段**，`fullLogIndependentlyRescanned=false`；不能描述为消费者已重扫完整日志，也不是性能或全部 GPU 错误验收。

[加密工件 14149359853](https://github.com/wuyong9494-lab/kriswu/actions/runs/43683433407/artifacts/14149359853)：**7,179,646 B**，SHA-256 `b9af61328ffcbf28770970f39574646bfbef6f663dfb0f5fda905bc6b4c0351d`。Root 单次认证消费得到 **60 个 inventory 条目、含清单共 61 文件**；原生两图、报告及 manifest 共 4 文件完整封存，UI 原图 0。原生所有者/排队准备清理回执成立，最终 Actions 报告确认 CI cleanup 完成、errors 为空。资源仍为原 `e5c0…` 的 373 文件版本，无新增游戏资源上传或 TestFlight。

下一步限定为修复结果完成与证据导出的收尾，并补充最小正常画面证据。**不得自动重跑本次已经成功的原生或控制台已通过的 UI 方法，也不能单纯延长超时后宣告验收通过。** 本报告没有实施或预先确认后续修复。完整字段、源文件 pins 与证据摘要见[配套 JSON](fighter-first-submit-preparation-run-43683433407.json)；原媒体、私有路径与密钥不公开。
