# 星了个星 566 发布交接

记录时间：2026-11-06 15:27 UTC。值班提醒 **1.2（566）已上传 TestFlight，Apple processing = VALID**。

## 已发布候选

- App 源码：`f23e2d16f4c461012917cdfdc2db60f73e8f8c12`。
- 源分支：`codex/plan-tiles-journey-20261106`、`codex/star-journey-native-20261106`。
- 设备与核心检查：[42226841093](https://github.com/wuyong9494-lab/kriswu/actions/runs/42226841093)，726 项、15 项平台跳过、0 失败；设备 Release 构建通过，并发警告 0。
- 成功发布：[42238801391](https://github.com/wuyong9494-lab/kriswu/actions/runs/42238801391)，发布控制提交 `dc48d7c191b6fa3f7d69847bd762cc8ed00826af`。
- 签名 job `127965210595`：归档、App/Widget 身份、版本、同源状态、完整资源校验均通过；15:21:54 UTC 返回 EXPORT SUCCEEDED。
- Apple job `127975647998`：15:27:19 UTC 返回 VALID、`READY_FOR_BETA_TESTING`、`READY_FOR_BETA_SUBMISSION`；测试说明已写入并核对。外部测试尚未送审，不将内部就绪称为外部可安装。
- Apple build ID：`9f0e871e-52d9-4943-998a-efef0f1ce088`。

## 这版内容与边界

星了个星首页、三关旅程（清盘→护送星核→限能返航）、三种贯穿能力、两种路线、逐步存档与复盘、六组最佳成绩及星图外观奖励已进入该候选。旧模式、挑战码和旧存档继续保留。

用户明确要求“直接上传吧”，随后明确授权刷新同一私有资源链接并重试。只有固定的 566/f23 候选使用直接内测策略；严格发布模式未放宽。完整资源包和 App 源码未因本次重试改变。ARM hosted runner 两次未获机器后，使用标准 `macos-26-intel` 与同版 Xcode 26.6 成功完成。

本版 **不代表原生体验验收通过**：8 项 UI 测试中 7 失败；竞技私有资源 Metal 渲染 2 项中 1 失败。两项结果已如实写入 TestFlight 说明，延期报告保持 `passed: false`。iPhone 17 Pro Max 真机体验、听感和性能未验收；真人难度校准仍按用户要求排除。

## 下一步

1. 修复 `rails.board` / `rails.lesson` 父控件无障碍标识覆盖子按钮标识的问题，重新验证完整三关、恢复与旧模式。
2. 用真实 UIKit 宿主截图替换只渲染背景或显示不支持视图占位符的 ImageRenderer 快照，验收奖励、大字及不同尺寸布局。
3. 独立定位 Metal 渲染失败，保留真实结果；不以延期冒充通过。
4. 在 iPhone 17 Pro Max 验收操作、音频与性能后再评价成品质量。

不要重新上传 566，不要重用已消费的单次私有链接，不要将本地其他竞技模块改动整体推送。后续开发从上面固定源提交续接。

## 可核验证据

- archive identity artifact：`13516901430`，SHA256 `746ad367068ebf59c402cd0f60655ed5800d3972015a67295d94735967b36d46`。
- Apple status artifact：`13516002712`，SHA256 `ce9f78c59ab3e05dfa3a68bae75631206ec8f40a6b81a7fd51e9291341201f78`。
- 资源精确性检查通过不等于其中每个角色、地图或模式已完成玩法验收。
