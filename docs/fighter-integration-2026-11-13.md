# 双角色开发整合：手动防御与挥砍连续性

## 基线与整合方式

本轮以 2026-11-13 03:00 UTC 远程核对到的有效开发提交
`54ff0d78fabf3bcd7247b38cb8e09e749dc9ced8` 为父提交，在独立分支
`codex/fighter-integrated-controls-20261113-1100` 继续开发。
该提交位于 `codex/fighter-camera-viewport-jitter-20261113-1030`，直接父提交为
`c7b9005cd678ec3e1870a1a49181d42cab42fd02`，继承交接资料中标记为 dot 整合基线的
`a0657d3f42141d673e37e4afd3a41354d644ddfc`。保留最新的 viewport 微小变化防抖，
不把所有历史提交的作者笼统认定为 dot。

另一个角色开发候选为
`3903fedf0323d0aaecde35df3288348111bcfd62`，位于
`codex/fighter-character-combat-20261111`。它与当前基线存在分歧，不能整树覆盖：
该候选关闭了当前已支持的 shadow 路径，也缺少当前的音频、预热及所有权实现。
本轮按行为和文件筛选移入其显式防御意图，原始相关提交为
`9c8b008790db8f1e8058c4f625a2c7b26aaec74c`；继续完成 UIKit 控件、会话与联机接线、
取消生命周期、无障碍状态和针对性回归。普通攻击的连续性修复在最新基线上实现，
保留当前影技自己的有界时间线。

## 完成的代码行为

### 显式防御

- `DuelWeaponInput` 只有接到玩家明确的 held 意图才请求防御。松开摇杆、攻击结束或站定
  不再自动举防；移动、空中、待跳跃、攻击与既有恢复期仍限制防御。
- 在原有四个动作按钮之外增加独立的“按住防御”控件，不替换源按钮图片与触摸区域。
  可用布局保留至少 44pt 的触摸范围，标识为 `duel.control.guard`。
- 最后一根手指松开、拖出、系统取消、暂停、重开、布局或窗口变化、控件失去所有权时释放
  意图。旧视图的回调不能清除新视图的输入。
- VoiceOver 双击明确切换同一 held 意图；无障碍值报告“已按住 / 未按住 / 操作已暂停”，
  不把输入意图表述为移动或空中时已成功格挡。
- 主客机继续使用既有本地座位与权威输入消费路径。网络准备必须同时具备可用防御控件和
  回调，已消费的防御位继续通过现有 wire 编码。

主要实现文件：`Sources/ShiftCore/DuelWeaponInput.swift`、
`App/Views/DuelSourceControls.swift`、`App/Views/DuelView.swift`、
`App/Services/DuelNetworkCompatibilityIdentity.swift`。

### 普通挥砍的碰撞、音效与刀光连续性

- `DuelWeaponSweepContinuity` 定义普通相邻采样 0.75m 的包含端点上限。
  这是本应用的防跳变规则，不是已恢复的原游戏事件表。
- 使用三维距离检查孙登刀和刘泉纬各锤的相邻采样。超限的端点不能凭空穿过身体命中，
  不能成为挥击音效的峰值，也不能让另一只合法挥动的锤失效。
- 碰撞同时检查上一帧和当前帧的战斗平面；用当前刀柄至刀尖线段命中之前，也验证刀柄
  自身没有跳变或来自平面之外。
- SceneKit trail 对刀柄和刀尖使用相同连续性规则，缺失动画 tick 或跳变时另起 strip，
  不跨空档连接。旧 strip 的消退、预热模板、暂停、reset 和 shutdown 所有权保持。
- Float 世界坐标仅在渲染判断中容许 10 微米舍入余量，核心 Double 碰撞上限保持严格
  0.75m；测试包含平移后恰好位于上限的样本。

主要实现文件：`Sources/ShiftCore/DuelWeaponSweepContinuity.swift`、
`Sources/ShiftCore/DuelWeaponFight.swift`、`App/Services/DuelWeaponEffects.swift`。

## 已执行的验证

### Linux 核心自动化

2026-11-13 03:15:41–03:19:58 UTC，使用官方 Swift 6.0.3、`--jobs 2` 执行 9 类筛选，
实际运行 **107 个 XCTest 方法，107 通过、0 失败、0 跳过，退出码 0**。

| 测试类 | 方法数 |
| --- | ---: |
| DuelWeaponInputTests | 18 |
| DuelManualGuardTests | 4 |
| DuelCameraFramingTests | 13 |
| DuelCombatCameraTests | 12 |
| DuelWeaponSweepContinuityTests | 8 |
| DuelWeaponFightTests | 19 |
| DuelWeaponComboTests | 7 |
| DuelWeaponShadowTests | 11 |
| DuelNetworkReplayTests | 15 |

构建 174.27 秒，测试 80.309 秒，命令总耗时 256.471 秒。
测试是在父提交 54ff 加本轮工作区修复上运行，不能误写为原始 54ff 已通过这些新增测试。
为绑定精确内容，已保存 214 个 Package/Core/Test 文件的 SHA-256 清单，运行前后清单相同。

- 清单：`validation/fighter-integration-20261113-core-source.sha256`
- 清单 SHA-256：`b0c8f8595cc5de97f564147c945eda14c8fd723c2f40e624f69d729c7a0758d0`
- 机器摘要：`validation/fighter-integration-20261113-core.json`
- 完整执行日志：`validation/fighter-integration-20261113-core.log`
- 日志 SHA-256：`a96dfdf46594761a5afaf02d741e5dd686eee830700e1af971b9989f426a569b`

新增测试对 tick 7 的真实 contact/swing 事件断言，覆盖异常峰值、单锤跳变、刀柄伪命中、
越出平面与 0.74/0.75/0.76m 边界，不能仅凭“总命中次数相同”通过。

### 联机规则指纹

现有 `test_build_fighter_network_rules.py` 的 16 项确定性检查全部通过，测试耗时
0.160 秒。递归源码清单实际包含 300 个文件，覆盖新增连续性文件、输入、控件和网络
身份接线；不需要修改生成器或绕过兼容门禁。检查用 source-only 指纹为
`5c16d906d6d362b944a742bcdb60f56f1b5ed564fc0e61a046befa578945de92`，只证明源码
清单覆盖，不冒充含 Xcode 构建设置的出厂指纹或签名证明。结果与日志保存在
`validation/fighter-integration-20261113-network-rules.json` 和对应 `.log`。
新源码应生成新的规则身份，继续拒绝与旧 Build 702 不同规则的对局匹配，不复用旧 manifest。

### iOS 定向原生回归

`.github/workflows/fighter-integration-regression.yml` 仅适用于本轮独立分支，
固定 9 类核心测试及 22 个无私有资源依赖的原生方法。原生范围包括 SceneKit trail、
显式防御的多指/取消/VoiceOver 状态、输入所有权、网络准备与既有战斗镜头生命周期。
首次提交本文件时，该 iOS 工作流尚未运行；原生实际结果必须以精确源 SHA 的 Actions
记录为准，不能从 Linux 通过或 workflow 静态检查推定。

工作流构建一次 unsigned demo host，随后只运行指定方法；记录 Xcode、SDK、实际模拟器、
完整方法集合、失败与跳过数、源码 SHA 及各阶段耗时。失败保留原退出码和原生诊断。
它不解密资源，不签名、不制作 archive、不上传应用或 artifact、不创建 Release 或 TestFlight。

现有 `ios.yml` 只增加本轮分支的精确 push 排除项。**新远程分支必须直接指向已经包含此
排除项与定向工作流的新提交，不得先指向旧基线。** 不自动创建 PR，因为原有 PR 触发器会
进入更广的 iOS 工作流。后续文档记录更新不应重复触发已通过的定向测试。

## 保留的验收和安全边界

原 Build 702 内部测试状态保留。既有 Actions
`43249672064`（26分56秒）与实际资源验收 `43238606975`（51分21秒，应用源码
`93de03a4fcc1a56189a808a3e8960f057b63a33a`）是历史证据，不转记为本轮提交已通过。
本轮不重跑它们，也不修改其成功记录。

角色独立模型、武器、源骨骼/动作、源音频、连招每段命中预算、当前影技、资源校验与加密
措施保留。此补丁不包含解密密钥、私有明文资源、资源对象上传、重复上传或发布动作。

以下仍需分别验收，不能由本轮 107 项合成核心测试或 22 项合成原生测试代替：

1. 真实源角色与武器加载后，在近身、远离、跳跃、重击、连招及影技时逐帧检查比例、骨骼、
   刀光、音效、受击反馈、动作边界和屏幕裁切。
2. 实际资源 `testOriginalManualGuardReleasesAcrossPauseRestartAndControlReplacement`
   与 UI 流程 `testOriginalManualDefenseIsReachableAndReleasesAcrossPauseAndSelection`
   已加入源码，当前定向无资源工作流不执行这两个方法。
3. 真实双设备联机的角色选择、准备、输入延迟、断线与恢复，和真人 VoiceOver 操作。
4. iPhone 17 Pro Max 真机的冷/热加载、峰值内存、温升、长时间帧时与稳定 60fps。

后续继续开发时先读取本分支及远程最新有效 HEAD，查看有无正在运行的定向验收；以具体
失败方法和最小文件修复继续，不从旧候选整树覆盖，也不把未执行的真实资源/真机项目标绿。
