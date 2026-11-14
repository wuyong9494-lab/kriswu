# Shared-root UI 就绪判断修复

## 真实执行结果

[运行 43647414701](https://github.com/wuyong9494-lab/kriswu/actions/runs/43647414701) 归属提交 `5788ebb1001a6e0f31c5208cb2b955b48b00741c`。经过实际结果与方法集合核对，6 个原生方法各执行一次，6 PASS、0 FAIL、0 SKIP；它们的成功证据保持归属该次运行，不再次选择执行。独立 UI 方法执行失败，最后阶段为 `sun-root-visible`。

本修复依据已认证解封的 `shared-root-ui-observations` 附件。它记录了 12 次可访问性树采样；不是根据工作流步骤失败推测所有方法失败。

## 已证实的测试错误

`DuelSharedRootVisualCaptureTests` 原先使用 `value.contains("可施放")` 判断就绪。字符串 `暂不可施放` 同样包含 `可施放`，导致否定状态被当作可以点击的状态。

| 采样 uptime（秒） | 阶段 | shadow 的真实 value | 其他观测 |
|---|---|---|---|
| 1208.1681927916668 | `sun-branches-ready` | `暂不可施放` | 按钮 enabled=true；旧谓词已经完成等待 |
| 1212.2810872083335 | `sun-root-visible` | `暂不可施放` | 刘血量 1000，累计命中 0 |
| 1213.3016353333335 | `sun-root-visible` | `暂不可施放` | 刘血量 1000，累计命中 0 |
| 1214.2575235833333 | `sun-root-visible` | `可施放` | 代码已进入只观察阶段，不会再次点击 |
| 1219.2396897083333 | `sun-root-visible` | `可施放` | 刘血量仍为 1000，无根枝控制标签 |

`enabled` 表示已解锁且可接收输入，不等同于技能当前可执行。App 的 triad 分支将 `fight.canUseTriad(...)` 写入 `ready`，并通过 value 区分 `可施放` 与 `暂不可施放`。测试必须尊重这个区别。

源码还显示，`canUseTriad` 拒绝源入场尚未结束的状态；`DuelSession.advance()` 在入场时将已消费的输入替换为中立输入，战斗层同时取消缓冲输入。上述位置与就绪变化符合仍处于源入场阶段的情况，但附件没有记录内部 intro 标志，故这一归因属于调用链支持的解释，不作为直接捕获的内部状态。

## 最小修改

测试文件 [DuelSharedRootVisualCaptureTests.swift](../../Tests/ArenaFlowTests/DuelSharedRootVisualCaptureTests.swift) 仅修改两处条件：武器就绪和枝蔓囚笼就绪都从子串匹配改为 `value == "可施放"`。方法 selector、超时、触摸操作、HP 下降、根枝控制出现/结束和角色身份断言不变。没有注入 HP、技能状态或战斗输入。

该文件修复后的 SHA-256 为 `d144949cad4b14eeef47ad7bf7d0134a5671016732d9690f77599aa54b911cee`。

Swift 6.0.3 `-frontend -parse` 与 `git diff --check` 通过。**修复后的 UI 方法尚未执行**；语法通过不代表 UI 通过。

## 普通武器提示与实际 ready 保持一致

独立代码审阅还确认了 [DuelView.swift](../../App/Views/DuelView.swift) 的普通武器控件描述问题：原 `ready` 使用 `fight.canUse(...) && fighter.attack == nil && fighter.stun == 0`，但文案最后无条件回落为“可施放”。源入场等资格门禁令 `canUse=false` 时，真实控件仍可能显示“可施放”，提前满足练习截图的观察条件。实际附件能证明文案被显示，不能独立读取当时内部的入场状态。

此次将原表达式抽为一个 `ready` 局部值，`setState` 继续使用完全相同的资格表达式；文案只有在 `ready=true` 时才显示“可施放”，其余显示“暂不可施放”。未装备、冷却、能量不足、受击和收招的具体文案保持原优先级。只修正展示与可访问性状态，不改变输入、伤害、能量或技能规则。

该生产文件的 SHA-256 为 `7576166011575d14e94a7d8fc880039afc3cd03cd1b8eab02928ec66beed3925`。Swift 6.0.3 前端语法解析通过；Apple 执行与原始截图仍由同一个失败 UI 方法的后续限定验证承担，不重复成功的六个原生方法。

## 距离与画面问题的证据边界

采样时孙的位置从 2462 经 2558、3032 变到 3044，刘保持 6500；摇杆一直为居中。当前 final v2 孙的 `runtime.modelTracks.roots` 存在，且有 `primary` 碰撞部件。`DuelTriadSpatialState.spawn` 对真实 source model 使用目标释放时的位置进行锚定，不能将 3456 mm 的双方间距直接认定为根枝技能无法命中的原因。本修复不添加走近、放大判定框或更改技能规则。

UI 截图中的渲染问题及 runtime Metal 诊断属于独立问题；本谓词修复不能证明它们已经解决，也不能将未观测到根枝控制一概归咎于渲染。画面仍须独立审阅。

现有 helper 会保留失败 UI 的部分 PNG/JSON；完整附件门禁要求 `flowCompleted=true`，因此失败报告不能获得完整 UI 通过状态。保留的 UI recovery 包包含当次已编译产物及旧 UI 测试二进制，不会自动带入此两行源码修改；未来复用需明确匹配来源和资源身份，并仅选择失败的 UI 方法。

## 本次限定验证：只重新执行失败 UI 方法

新增工作流 [fighter-shared-root-ui-remediation.yml](../../.github/workflows/fighter-shared-root-ui-remediation.yml) 使用 `ui-remediation-only` 范围。它只接受验收分支第一次 push、精确提交信息 `Verify shared root UI remediation 20261115`，保留 `fighter-private-assets` 环境保护，没有手动 dispatch 或自动重试入口。

源码基准固定为 `5afd8195e2f611ab2e7c37f5096a4251a4616ee9`。除三个精确 App 文件和这个 UI 测试文件外，App、Core、Shared、Widget、Tests、构建配置、现有脚本与工作流的保留集合必须匹配已审阅记录。新增 helper 范围与离线检查单独固定，新工作流只规范化唯一的 `EXPECTED_SHARED_ROOT_UI_HELPER_SHA256` 字段来消除互相引用的哈希环；字段真实值仍必须等于完整 helper SHA。新验收文档不进入构建输入集合。

| 本次允许变更的运行输入 | SHA-256 |
|---|---|
| `App/Views/DuelWorld.swift` | `e01058a8f5f57ce516621534f0e642397537a3532b7b3ffc88e80cf93bcf948e` |
| `App/Services/DuelTriadSurfaceFrameDriver.swift` | `1986d589d7ca309e426491f818f4f9e0f9d81a2a99f6a2c4c2e1b6274f347849` |
| `App/Views/DuelView.swift` | `7576166011575d14e94a7d8fc880039afc3cd03cd1b8eab02928ec66beed3925` |
| `Tests/ArenaFlowTests/DuelSharedRootVisualCaptureTests.swift` | `d144949cad4b14eeef47ad7bf7d0134a5671016732d9690f77599aa54b911cee` |

这次 App 调用方也有修复，因此使用原有 `ArenaFlow` scheme 重新进行一次 unsigned `build-for-testing`，要求产物中只有 `ArenaFlowTests` 测试目标，不临时修改 `project.yml`，不构建或选择 `SiteTests`。资源仍按相同 AAD、原始密文与最终 v2 清单认证，373 个编译内资源逐项匹配；只在 stage 注入现有资源密钥。

唯一执行的 selector 为：

```text
ArenaFlowTests/DuelSharedRootVisualCaptureTests/testFinalSharedRootReleaseShowsBothFightersAndAcceptsSunBranchesThroughRealControls
```

`expectedNativeMethods=0` 只表示 `nativeExecutionStatus=not_selected`。任何原生执行入口在调用工具前被拒绝；空方法集合不能验证为通过，产出任何当前原生结果文件也会阻断报告。历史 run `43647414701` 的六个原生通过和 run `43644209347` 的五个合约通过，分别保留原提交、artifact 和结果文件摘要，不进入当前计数。

### 附件和日志必须构成完整证据

UI 通过要求唯一方法执行一次、零 skipped，结果与附件均属于本次拥有的 iPhone 17 Pro Max 模拟器。六张指定 PNG 和观察 JSON 均必须存在、非空、单件不超过原来的 24 MiB，并严格验证方法归属、设备、内容与 SHA。附件 manifest 以及这七个必需文件优先进入密文封装；只有它们确实全部被封存，`uiSealedCaptureSetComplete` 才成立。

自动视频与系统记录使用独立边界：单件不超过 128 MiB，自动附件合计不超过 256 MiB，所有导出文件最多 512 个、总计不超过 384 MiB，任何符号链接或非普通文件均拒绝。允许空系统记录，但它们不计验收覆盖。密文媒体保持 PNG/JSON/TXT、单件 24 MiB、合计 160 MiB 的原边界；自动视频明确省略，并保留文件大小、摘要和省略原因。旧导出失败只能确认为通用文件边界校验触发，不能据现有信息断言究竟是空记录还是大视频造成。

本次 UI 调用起点到结果导出结束构成 runtime 日志窗口，向秒边界外取整。`log show --start/--end` 使用 Apple 官方 [TN3163 示例](https://developer.apple.com/documentation/technotes/tn3163-understanding-the-synchronization-of-nspersistentcloudkitcontainer) 的带时区日期格式。必须实际命令 exit 0、完整 JSON 可解析、模拟器归属一致且存在本次 App 进程条目；空日志、损坏结构或命令失败均不能当作没有渲染错误。

完整日志在封存前扫描两个已观测诊断：`Each CAMetalLayerDrawable can only be presented once!` 与 texture-after-present。任何一次出现均阻断完成状态。超过 2 MiB 的封存文本只保留末尾，回执记录完整原文 SHA/大小、扫描结果及 `tailOnly`；末尾未出现错误不能替代完整扫描。此门禁只针对已知诊断，不代表像素、听觉、性能或 iPhone 真机验收通过，所有截图仍需人工审阅。

### 本地检查范围

新增 [test_fighter_shared_root_ui_remediation.py](../../.github/scripts/test_fighter_shared_root_ui_remediation.py) 的 **17 个离线检查首次全部通过，耗时 0.212 秒**。它们覆盖精确选择与无原生执行、源码例外与 pin、现有 UI scheme、重复/跳过/错设备拒绝、必需附件的缺失/错误归属/空文件/超限/符号链接、自动附件预算、manifest 封存优先级、空/损坏/失败日志及两个已知 drawable 诊断、完整 gate 报告与 stage-only secrets。Apple 命令均为隔离 mock，不解密或加载真实资源；没有运行已通过的原生集合，也没有执行本次 UI 方法。

Python AST、工作流 YAML 和 `git diff --check` 通过。上述离线结果只能支持 helper 边界与编排逻辑；真实模拟器执行、画面复核和真机验收仍需各自证据。
