# 入场渲染诊断结果：43658526616

**一个新的 Apple 原生诊断方法实际执行并通过：1 PASS／0 FAIL／0 SKIP。六张认证原始 PNG 逐张复核后的画面结论为 FAILED；人物与基础场景仍不可见，发布阻塞未解除。** 本次没有选择 UI 方法，不能把 `UI=0 / not_selected` 记成 UI 通过，也不能把工作流 `completed / success` 当作画面验收通过。

同一冻结帧的隔离证据已缩小问题范围：frame 394 移除源特效包后仍全黑，再移除投影后也全黑，且两图都与 frame 0 的全黑图逐字节一致。因此，当前缺失画面不能仅用特效遮挡解释；**基础 SceneKit 输出缺失的具体原因仍待定位**。这些图片还不足以证明粒子比例本身错误。完整机器可读结果见[同名 JSON](fighter-entrance-render-run-43658526616.json)。

## 实际源提交、运行与计数

| 字段 | 已核实际值 |
|---|---|
| 被测源提交 | [`cdd0d496bf63fd186de6f8d9cf91646c1dc88917`](https://github.com/wuyong9494-lab/kriswu/commit/cdd0d496bf63fd186de6f8d9cf91646c1dc88917) |
| App／Core 固定基线 | `532fb03083da7053417b7ad7ba484a99e4c41c28`，本诊断没有修改生产代码 |
| Actions | [43658526616](https://github.com/wuyong9494-lab/kriswu/actions/runs/43658526616) |
| Job | [132642404573](https://github.com/wuyong9494-lab/kriswu/actions/runs/43658526616/job/132642404573) |
| Run number／attempt | `2 / 1`；这是修正诊断编译问题后的新提交运行，不是重跑前一次 run |
| 创建／最终更新时间（北京时间） | `2026-11-15 08:30:41 / 08:44:37`，UTC+08:00 |
| Job 起止（北京时间） | `2026-11-15 08:32:09—08:44:36`，UTC+08:00 |
| 工具链与设备 | Xcode `26.6`；单一受控 iPhone 17 Pro Max **模拟器**，iOS `26.5 (23F77)`，arm64 |
| 本次原生方法 | **1 total／1 passed／0 failed／0 skipped**，执行一次 |
| 本次 UI | `0 / not_selected`，无 UI 结果包；并非 `0/0` 通过 |
| XCTest 方法耗时 | **72.622 s**，来自实际方法日志 |
| `xcodebuild test` 进程耗时 | **145.792 s**，包含测试进程启动等开销，不是方法耗时 |
| 构建进程耗时 | **362.812 s**，退出码 `0` |

计数由确切方法、结果、设备和次数门禁共同核对，不是由 overall success 推导。唯一被选择的方法为：

```text
SiteTests/DuelEntranceRenderDiagnosticTests/
testInstalledEntranceCompletesAndCapturesSceneEffectShadowIsolationOnce
```

[实际 XCTest 源文件](https://github.com/wuyong9494-lab/kriswu/blob/cdd0d496bf63fd186de6f8d9cf91646c1dc88917/Tests/SiteTests/DuelEntranceRenderDiagnosticTests.swift)的 SHA-256 为 `9349383bd882fc281e5b28a73a05c0bd4c564ec81c45666b0bdaa41ec962cceb`。方法使用真实已安装 release、真实 `DuelSession` 和正常 `advance`，没有注入战斗状态、血量或就绪条件；在同一个主线程调用栈内完成 **394 次正常步进**，没有 live display-link 驱动。

## 本次门禁已完成的具体内容

| 门禁／阶段 | 实际结果 | 北京时间（2026-11-15） |
|---|---|---|
| 源码身份与唯一新方法 | success | 08:32:34—08:32:35 |
| 工具链选择 | success | 08:32:35—08:32:45 |
| 既有资源认证与 staging | success | 08:32:45—08:32:52 |
| SiteTests host 构建、373 项编译资源逐字节核验 | success | 08:32:52—08:38:57 |
| 单一受控模拟器准备 | success | 08:38:57—08:40:57 |
| 唯一新原生方法、完整运行日志门禁 | success | 08:40:58—08:44:09 |
| 确切方法／设备所属附件导出 | success | 08:44:09—08:44:11 |
| 加密封存 | success | 08:44:11—08:44:13 |
| 仅诊断密文上传 | success | 08:44:13—08:44:18 |
| 本次模拟器、暂存媒体、产物与明文清理 | success，错误数 0 | 08:44:18—08:44:31 |
| 最终公开计数报告 | success | 08:44:31 |

373 项资源来自既有 73 项基础文件与最终 302 项 overlay，合并时替换 2 项同名文件。最终 overlay 由既有 295 项加上 13 项增量 payload 形成，289 项原 overlay 保持原字节。资源 release 固定为 `h17-shared-root-floorfall-20261115-v2`，SHA-256 为 `e5c0ccaeef85ce86c5b8fd4ee64524794d6556f5a561f4078362f6899bedf4e5`；增量 manifest 为 `d50b7fc6f711a55849b259b0f78d348612782f5e3765f9629db50291e20fe2b9`。本次没有重转媒体、上传新资源版本或上传 TestFlight。

附件封存包含 **6 PNG＋1 诊断 JSON＋1 附件 manifest，共 8 文件、984,843 B，遗漏 0 文件**。字节摘要、956×440 图片尺寸、确切测试方法、所属模拟器，以及冻结帧状态的关联均通过。原始机器报告仍保存其生成时的 `pixels=PENDING`；本报告另行记录后续逐张原图复核的 `FAILED`，不改写自动执行回执。

## 六张原图的实际结果与隔离结论

以下均为认证工件内原始 PNG 的复核结果，未公开原媒体。四张 frame 394 图片之间，游戏状态、动画 tick、相机变换、FOV 和类别遮罩保持不变；临时隔离只作用于诊断的渲染拥有者，之后按正常路径恢复。

| 标签 | 实际状态／隔离 | 原图复核结果 | 字节数／摘要标识 |
|---|---|---|---|
| `entrance-frame-0-full` | 入场开始；0 个源特效绘制包 | 全黑，未见人物或场景 | 9,664 B；A |
| `entrance-frame-164-full` | `firstIntro` 的源 clip tick 163，森林 marker 之前 | 仅见紫雾与小刀，未见人物或场景 | 54,445 B；B |
| `entrance-frame-394-full` | 正常特效与投影；112 个绘制包 | 可见树雾，未见人物或场景 | 427,251 B；C |
| `entrance-frame-394-no-fx` | 移除源特效包，保留原投影 | 全黑 | 9,664 B；A |
| `entrance-frame-394-scene-only` | 再移除投影，仅保留基础场景渲染 | 全黑 | 9,664 B；A |
| `entrance-frame-394-restored` | 恢复正常特效与投影；112 个绘制包 | 与同帧 full 原图逐字节一致 | 427,251 B；C |

| 摘要标识 | 原 PNG SHA-256 |
|---|---|
| A | `d057703632281c9f98c789fc1531a33b658d3301494a16a04a8fefcf69f89cd0` |
| B | `df5dc545763fa7b8a3bf2486202b1209f36927d49e4cdfdb94c95fde2e2aed87` |
| C | `ceab33988cceb5a9587cb9fdf933dffcfa01d514bad2a07bb3ffd73e79bcec0e` |

独立只读像素统计进一步确认：A 组的 420,640 个像素全部为 `RGBA(0,0,0,255)`，并非透明图片被查看器衬成黑色。C 组有 6,811 种 RGBA，B 组有 2,975 种；六张图的 alpha 均为 255。统计不改变原 PNG 字节，也不代替角色与场景的视觉审查。

**已证实的边界：**单纯移除特效或投影没有恢复人物、场景；恢复后图像与原图完全一致，隔离没有意外推进战斗。这足以否定“仅由前景特效遮挡即可解释全部黑场”的归因，但还不能在 SceneKit 首 pass、阴影、渲染目标、材质或其他内部环节之间确定根因。也不能用一张移除特效后的诊断图替代生产画面验收。

## 八个状态样点：逻辑完成与像素输出分开

| 样点 | 入场状态／源 tick | 入场锁 | 武器／枝蔓就绪 | 孙 x／刘 x | 已提交特效包 |
|---|---|---|---|---|---:|
| frame 0 full | `firstBirth / 0` | 是 | 否／否 | 2580／6500 | 0 |
| frame 164 full | `firstIntro / 163` | 是 | 否／否 | 2494／6500 | 21 |
| frame 392 状态样点 | `firstIntro / 391` | 是 | 否／否 | 3044／6500 | 21* |
| frame 393 状态样点 | `startIdle / 0` | 是 | 否／否 | 3044／6500 | 21* |
| frame 394 full | 入场拥有者已释放 | 否 | 是／是 | 3044／6500 | 112 |
| frame 394 no-FX | 同一游戏状态 | 否 | 是／是 | 3044／6500 | 0 |
| frame 394 scene-only | 同一游戏状态 | 否 | 是／是 | 3044／6500 | 0 |
| frame 394 restored | 同一游戏状态 | 否 | 是／是 | 3044／6500 | 112 |

\* frame 392／393 只取状态，未执行新的 draw，因此包数保留自上一绘制样点，不能据此推断当帧完整特效数量。

八个样点双方 HP 始终为 **1000／1000**，display-link 回调始终为 **0**。frame 393 已转入 `startIdle`，入场拥有者要到第 394 次正常 advance 后才释放；这个真实边界不需要绕过就绪逻辑。**固定步进的 frame 394 可用状态不证明实时 UI 在其等待预算内就绪。** 既有真实 UI 在 `ember-practice-ready` 失败的证据仍保留。

场景图统计也没有等价为屏幕可见：宫殿节点有 24 个几何体、24 个满足节点可见性条件；孙节点有 26 个几何体、9 个 skinner（frame 394 满足可见性条件的几何体为 7）；刘节点有 28 个几何体、8 个 skinner、6 个满足可见性条件的几何体。三者类别均为 1，相机类别遮罩为 -1，近／远裁面为 0.1／350，两个 renderer 的 reverse-Z 均为 false。每次 capture 的 SceneKit scene 与 point-of-view 身份断言实际通过；late-source 几何体数始终为 0。这些是节点与调用链证据，**不是人物已渲染的像素证据**。

capture 为 956×440；视图为 956×440 points，实际 drawable 为 2868×1320、scale 为 3。请求采样数为 2，设备最终使用 4。报告保留这个实际差异，没有把请求参数写成设备最终参数。

## 分段耗时：首次构造与绘制是定位线索

| 分段 | 本次实测 |
|---|---:|
| 构造真实 session | 18.287485 s |
| 构造真实 world | 37.118183 s |
| 挂载与 layout | 0.002536 s |
| frame 0 首次 draw submission | 13.502432 s |
| frame 0 同步 capture／readback | 0.703927 s |
| 正常 advance 0→164 | 0.375144 s；164 次，单次 p95 0.003783 s，最大 0.086942 s |
| 正常 advance 164→392 | 0.330753 s；228 次，单次 p95 0.002168 s，最大 0.096755 s |
| advance 392→393／393→394 | 0.001773 s／0.005087 s |
| 394 次 advance 分段累计 | **0.712757 s** |
| frame 164 draw／同步 readback | 0.069670 s／0.387899 s |
| frame 394 full draw／同步 readback | 0.223827 s／0.617032 s |
| 同帧 no-FX／scene-only 同步 readback | 0.009727 s／0.008879 s |
| 同帧 restored draw／同步 readback | 0.015109 s／0.084366 s |
| 诊断内部总计／XCTest 方法 | 72.506421 s／72.622 s |

本次开销主要集中于 session／world 构造和首次 draw submission，可以据此继续定位，但**不能将一次测试的分段耗时认定为此前 UI 超时的完整因果解释**。394 次 advance 没有在每一步绘制，也没有依靠 live display-link；同步 capture 包含 GPU readback 等待。因此，这些数值既不是实时 FPS、稳定帧耗时，也不是 GPU 单独耗时或真机性能验收。

资源释放断言实际通过：scene、surface、renderer 均释放，活动时钟从 0 回到 0。这只覆盖本诊断生命周期，不替代用户要求的连续攻击、长时回放或真机资源压力验收。

## 完整日志门禁与封存尾部的区别

工作流在封存前解析并扫描完整请求区间 **北京时间 08:41:02—08:43:55** 的模拟器 App 日志。完整源为 **10,649,092 B、8,063 条 JSON 记录，8,063 条均属于本次 App**，源 SHA-256 为 `d29331714b18c56ae0b289d036b346306b3af5635d6fd3dd4968768e88c0f76f`。实际 App 记录起止为北京时间 **08:42:05.822811—08:43:24.921658**。完整 JSON、非空 App 记录与所属模拟器校验通过。

完整扫描中，两类已有关键诊断 `doublePresent` 与 `textureAfterPresent` 均为 **0**。这是所定义两类诊断的门禁结果，不是“所有 Metal 错误均为 0”，更不是黑场已解决的证明。

受保护归档只保留该日志最后 **2,097,152 B**，SHA-256 为 `004b7b25002f232139a78dbc7080ff1ebff6714b921e30e8c2342a72943fc4fb`，清单明确 `tailOnly=true`。对尾部的只读复核恢复出 1,622 个完整 JSON 对象：84 条 `Error` 全为 CoreAudio `LoudnessManager` 的 no-plist 信息；54 条 `Metal Compiling Shader` 为 activity-create 记录，发生于北京时间 08:43:06.332301—08:43:19.815020，另有一条 `failedConnection` 文本。尾部未出现 pipeline／command 文本匹配。**activity-create 时间差不是 shader 编译耗时，尾部检查也不能外推为完整日志的任意错误搜索结果。**

## 历史失败与成功范围继续独立归属

前次 [`7a8fc821… / run 43657437556`](fighter-entrance-render-build-run-43657437556.md) 因新增诊断统计函数的 actor 隔离编译错误失败，退出码 65：`effectiveVisibility` 在同步 nonisolated 局部计数函数中被调用。该次实际执行 **0 个原生方法，UI 0，截图 0**；后续步骤 skipped 不算通过，也不能把计划的 1 方法写成 1 个 XCTest FAIL。

本次只修正该诊断文件的主线程隔离遍历，并更新新入口的精确摘要与提交消息；App／Core 与 `532fb030…` 保持一致。新的真实 Apple 构建和一次方法执行已在本 run 完成。原有 20 个新增离线门禁检查的通过记录保持原时间与范围，未因纯摘要更新而重复运行。

| 历史运行 | 原源提交 | 已有通过范围 | 本次选择 |
|---|---|---:|---|
| [43611931466](https://github.com/wuyong9494-lab/kriswu/actions/runs/43611931466) | `ef3064085879c497d59533459c94b429a40f9cee` | 117 项 | 否 |
| [43644209347](https://github.com/wuyong9494-lab/kriswu/actions/runs/43644209347) | `68f1e7de45351c3e4b2607c56ff8ab111d0c7130` | 5 项 | 否 |
| [43647414701](https://github.com/wuyong9494-lab/kriswu/actions/runs/43647414701) | `5788ebb1001a6e0f31c5208cb2b955b48b00741c` | 6 项 | 否 |

上述计数不加入本次 1 项。[真实 UI 失败 run 43652056280](fighter-shared-root-ui-remediation-run-43652056280.md)仍为 0 PASS／1 FAIL／0 SKIP，失败步骤 `ember-practice-ready`；本次 offscreen 诊断没有重跑或覆盖它。刘泉纬当前 profile 仍是 `liu_hammers`，没有激活独立盘古生产资源；不能据此宣布盘古或黑色双刀的全部机制完成。

## 证据身份与后续边界

| 证据 | 已核身份 |
|---|---|
| [加密 artifact 14138764238](https://github.com/wuyong9494-lab/kriswu/actions/runs/43658526616/artifacts/14138764238) | `fighter-entrance-render-diagnostic-43658526616-1-encrypted`；4,482,564 B |
| artifact SHA-256 | `7dab5970617a53b49356c148edb9bcef053d4433320f441db18a651d175011e3` |
| 诊断 report | 43,253 B；`2d909fe29e485c2ae3a508e7b31480d94cd65d46256d6e2b0018d9f7d0e7bbba` |
| 附件 manifest | 3,651 B；`9c4a788ecd9d9fdd2d74d2d300ea85e1e1d163a44533e2dd288e9763f9930bcf` |
| 实际方法日志 | 137,216 B；`114e91a0e58ba73720cd2b38d244e6e8c6e0f8554df52304749e633b31a77902` |
| [实际 helper](https://github.com/wuyong9494-lab/kriswu/blob/cdd0d496bf63fd186de6f8d9cf91646c1dc88917/.github/scripts/fighter_entrance_render_diagnostic.py) | `6a9d546890f60ede92de66aae6dca81a4c8da2544e083b2bdd82883f569a5263` |
| [实际 workflow](https://github.com/wuyong9494-lab/kriswu/blob/cdd0d496bf63fd186de6f8d9cf91646c1dc88917/.github/workflows/fighter-entrance-render-diagnostic.yml) | `aee36b6360fbf43f7ae797a3f5a8cb7fdd0020fc7b127ac0f4163fddee06a8d6` |

工件已由唯一消费者认证、解封并检查，无身份／摘要失败；本报告复用已消费证据，没有第二次下载或执行。公开内容仅含标识、摘要和统计，保留原媒体及加密凭据的保护。

后续应先定位基础 SceneKit 输出缺失，再确定最小修复与新的对应证据范围。当前没有依据仅延长 UI 等待时间，也没有必要重跑已成功的历史方法。真实 iPhone 17 Pro Max、可听音效与音画同步、实时性能和完整玩法验收仍未通过；**本次原生诊断成功提供了失败画面的可归属证据，没有解除发布阻塞。**
