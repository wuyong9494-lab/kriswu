# 首次共享根缚验收：参数拒绝，0 方法执行

本记录保留首次运行的实际失败及最小修复，不覆盖原始验收计划。

- 运行：[43642548703](https://github.com/wuyong9494-lab/kriswu/actions/runs/43642548703)
- Job：[132593069280](https://github.com/wuyong9494-lab/kriswu/actions/runs/43642548703/job/132593069280)
- 真实 GitHub 提交：bf5cc1893b4cff80cd04dda08ffff0cdf1ec408a
- 结论：completed / failure，attempt 1；2026-11-14 21:36:06 UTC 更新。
- 工件：14132858423，fighter-shared-root-native-43642548703-1-encrypted；5,178,380 bytes。
- 工件 SHA256：54ba5f91862c35a1914111d9bcfc45ae888cbdaa18167817711437d1d3fbd79c。

根任务已下载并认证解封一次。后续分析读取该既有明文证据，没有重复下载、解密或获取资源 key。

## 实际达到的阶段

| 阶段 | 真实结果 | UTC 时间 |
| --- | --- | --- |
| 源码门禁与工具选择 | success | 21:24:58–21:25:08 |
| 73 基线 + 295 overlay + 13 payload 认证 | success | 21:25:08–21:25:17 |
| 双 target 的 unsigned build 与 373 编译资源校验 | success | 21:25:17–21:30:00 |
| iPhone 17 Pro Max 模拟器准备 | success | 21:30:00–21:32:47 |
| 9 项原生方法调用 | **exit 64，0 方法执行** | 21:32:47–21:34:09 |
| 1 项 UI 方法调用 | **exit 64，0 方法执行** | 21:34:09–21:34:21 |
| 备用刘泉纬大厅的 2 张截图与日志 | 捕获操作 success；根任务图审发现空白/黑背景，无可见角色或控件 | 21:34:21–21:35:34 |
| 精确测试附件导出 | failure；未执行方法没有所需附件 | 21:35:34–21:35:39 |
| 失败诊断加密与上传 | success | 21:35:39–21:35:49 |
| 自有 simulator / 明文 / 构建产物清理 | success | 21:35:49–21:35:58 |
| 最终通过门禁 | failure，如实拒绝验收 | 21:35:58 |

两个结果包各自的 totalTestCount、passedTests、failedTests、skippedTests 全为 0，result 为 unknown；两个 tests 导出都没有 Test Case 叶节点。因此没有失败的方法断言，更没有 9 项或 UI 已通过。仅凭 completed 或工件上传成功不能改写此结果。

备用两张 PNG 的 SHA256 相同。根任务已进行实际图审，只有空白/黑背景，未见角色或控件；因此不能称“实际大厅可见”。这一视觉观察单独保留，不能仅用已证实的命令行参数错误解释它；其加载/显示调用链仍在只读调查。

## 唯一已证实原因

两个 stderr 文件均为同一条 Xcode 错误：

~~~text
xcodebuild: error: Must specify -test-iterations with more than 1 iteration.
~~~

metadata/selected-native-stderr.log 与 metadata/selected-ui-stderr.log 均为 77 bytes，SHA256 相同：

~~~text
ce4e83dd5528a01a356303dff0386e1c1e54ed87cc496e24041a5a6cd6c3444f
~~~

helper 添加了不合法的 -test-iterations 1。Xcode 在方法执行前拒绝命令。这里的 1 是计划执行次数，不是已经完成的次数；必须结合 exit code、summary 与方法叶节点判断。

既有成功原生路径 .github/scripts/fighter_h17_source_native.py 的 test-without-building 调用没有传此参数，.github/scripts/fighter_h17_d19_native.py 同样没有。它们使用默认单次执行，并由精确结果集合及重复方法门禁核实执行范围。

## 最小修复

唯一生产代码变化位于 .github/scripts/fighter_shared_root_native.py 的 execute_tests：从命令列表移除 -test-iterations 和 1。以下约束不变：

- 原生 9 个 selector 与 UI 1 个 selector 分别执行和计数。
- 默认单次执行、关闭并行、同一次阶段调用防重入。
- 精确总数、每个方法只出现一次、全部 Passed、0 failed、0 skipped。
- App、Core、Swift 测试源码、所有资源、release pin、旧受保护 workflow/helper、超时预算均不变。
- 不重新打包或上传资源，不触发旧 117 项。

新增的唯一 Python 参数回归检查覆盖 native 和 UI 两种调用，确认没有重复执行参数，同时保留精确 selector 及 iterations=1 的计划元数据。

该检查使用模拟的 xcodebuild 与结果导出，**没有运行 Apple 或实际游戏方法**。修复前运行 1 个新检查、两个子场景均因非法参数失败；修复后仅重跑这一个新检查，1 / 1 通过，0.005 秒。此前成功的 15 项 Python 检查及所有旧集合未重复运行。

## 下一次执行边界

9 项原生与 1 项 UI 仍待首次真正方法执行。下一次应通过新的已评审提交启动，不重跑历史成功集合。首次失败时 native9 未通过，因此当时的条件式 UI 恢复包没有生成；原构建产物已清理，后续需要重新构建。这笔成本不应被伪称为已有可复用产物。

备用大厅截图不能证明 Sun 根缚流程、精确 tick 38、floorfall 可听播放、真机性能或 D19 盘古资源完成。原始参数失败记录与首次工件应持续保留。

机器可读摘要与相对证据路径 / SHA256 见同名 JSON。本记录创建时未提交、推送或触发修复运行；真实后续 run 结果另行记录。
