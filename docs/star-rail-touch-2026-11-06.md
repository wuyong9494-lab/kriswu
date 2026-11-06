# 星轨预览与移动确认回归

对应代码：`8eebee9f56096d7b875d21f0bb1b8465e7845c93`。基线为公开提交 `f23e2d16f4c461012917cdfdc2db60f73e8f8c12`。

## 行为

- 带锚标记的普通轨道牌可打开对应轨道的预览，仍不能在航线目标完成前被取入收集槽。星核继续遵循原护送规则。
- 轨道按钮有完整矩形点击范围，最小高度 44 点；重复选择同一轨道保留预览，点击取消关闭。
- 确认按钮明确显示移动动作、终点和实际费用；不满足条件时保留原因说明。
- 棋盘与教学标题不再覆盖子按钮的无障碍标识。
- 关卡规则和存档格式不变。

## 回归用例

`StarRailTests.testReportedFirstStageAnchorPositionCanMoveAndFinishWithoutRestart` 使用公开第一关牌序列 `[0,1,2,11,4,6,5,7,8,9]`，验证剩余锚牌、存档恢复、预览不提交动作、实际移层与最终通关。

`StarRailFlowTests` 补充锚牌预览、按钮中部及偏右触点、重复选择、明确确认、旋转和后台恢复。使用实际界面操作，不注入胜利状态。

## 检查结果

- Linux Swift 6.0.3：`swift test --jobs 2 --filter 'StarRailTests|StarRailExpansionTests'`，34 项通过，0 失败。
- Swift 语法解析和 `git diff --check` 通过。
- iPhone 17 Pro Max 模拟器检查仍在等待执行机：<https://github.com/wuyong9494-lab/kriswu/actions/runs/42249249731>。原生触控验收尚无结论。
- 本次未执行 TestFlight 发布。
