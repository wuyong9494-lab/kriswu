# Apple run 43691877506：两张正常原图已取得，指定 UI 方法通过

## 实际验收结果

[运行 43691877506](https://github.com/wuyong9494-lab/kriswu/actions/runs/43691877506) 固定源为 `a915382716246b8cb42939e1724a962e21f518f2`，attempt 1。本次明确授权的环境审批已完成；源码、373 项资源、原生构建、安装身份和实际 UI 流程都有本次证据。

**本轮正常原图目标已完成：2 张正常练习场原 PNG。唯一指定 UI 方法实际通过。** 完整结构化 `ui-tests.json` 只含 `DuelNormalFrameCaptureTests/testSunPracticeCapturesTwoNormalWindowFrames()` 这个 Test Case，结果为 Passed；所有有结果字段的上层节点也为 Passed，设备与封存的 simulator/invocation 身份一致。从完整测试树独立计数为 **总数 1、通过 1、失败 0、跳过 0**。这些是测试树计数，不是缺失的 summary 计数。

| 本次证据层 | 实际结果 |
| --- | --- |
| 选定 UI 执行进程 | exit 0，259.205 秒 |
| 唯一指定 Test Case | Passed，133.993190 秒 |
| 完整 tests 树导出 | exit 0，15.768 秒 |
| 聚合 summary 导出 | exit 124，45.109 秒；未取得 summary JSON |
| 正常练习场原图 | 2 张，原字节、方向、readiness 关联均核对通过 |
| 诊断图 | 1 张大厅预触点图，不计入正常图 |
| Recover / Seal / Upload / Cleanup | 全部成功 |
| 原工作流 conclusion | failure，保留原样 |

## 为什么 Actions 仍显示失败

UI 已正常返回后，helper 再独立调用 `xcresult get test-results summary`，本次在单独的 45 秒预算后超时。后面的 tests 树导出成功，但原 gate 要求两份导出同时存在，因此写出 `Structured XCTest exports unavailable`。

原 producer 的 `uiExactMethodPassed=false`、`uiObservedCounts=null`、consumer 的双导出门槛 false，以及 `ui-failure.json` 都没有回写。新报告单独记录 `independentSelectedMethodPassed=true`，依据是完整测试树、同模拟器身份和正常退出的实际测试进程，不依据截图数量或 console 文本推断通过。

summary 更深层的超时原因尚无证据。侧车原图保存与认证流程不依赖这个汇总导出，因而该失败不使已经验证的两张 PNG 失效。**不为补汇总摘要再执行已经通过的 UI 方法。**

## 两张原图核对

| 文件 | 原始字节数 | SHA-256 |
| --- | ---: | --- |
| normal-sun-practice-ready.png | 4,308,633 | `840ede98ca3f860bfb4e97af52ddc9d001ed5a0a17b947bc5808eae656466063` |
| normal-sun-practice-later.png | 4,382,850 | `659bca6cf73ffdecb55aac52e5c1693af8cef7251d57460608026916bada70c4` |

两张原图存储尺寸均为 1320 × 2868，EXIF 与 XMP 方向均为 8；显示尺寸为 2868 × 1320，与 AX 956 × 440 恰为 3 倍。没有旋转、重编码或用诊断图替代正常图。

绑定的 observation 11、12 均满足实际练习场 readiness：孙登黑色双刀与刘泉纬双锤姓名正确，摇杆居中、武器可施放，唯一暂停控件可见，没有继续控件或资源错误。后次 observation 开始距首图结束约 1.435423 秒。根节点及独立审查者逐张查看原图，实际为横屏练习场，人物、姓名、血条、练习状态与控制区可见。

本次直接验证了上轮针对原 PNG 方向的修正。两张截图不能扩大为内部 tick/drawable、稳定帧率、声音、iPhone 真机或角色 1:1 完整还原验收。测试树仍保留一条 QoS 等待警告；本批没有测量或宣称解决帧率问题。

## 工件身份与范围

只下载一次的 artifact 为 `14154536845`，15,353,938 字节，SHA-256 `c7f3ae5463de2bb4b5c6680c3be35df7a9f749fa8ba481a80f3fe09e57fbea5a`；认证恢复共 50 个 inventory 条目。原 PNG、原测试树和原失败记录不提交到公共仓库，公共报告仅保留身份、摘要、计数和解释。

本轮未改变生产 App，未重新选择历史已通过的重型方法，未上传 TestFlight。刘泉纬仍是 `liu_hammers / isPangu=false`。
