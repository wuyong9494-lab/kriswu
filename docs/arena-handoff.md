# Arena 接续记录

更新：2026-10-29。持续在 `codex/arena-diagnostics-2` 开发，不从 main 重建。

## 本阶段：恢复 401 碰撞回归

- 接续提交：`af00a8a3c89b75f72e34f6e986d7eda509bd9d26`。
- 401：https://github.com/wuyong9494-lab/kriswu/actions/runs/40835937976 。Linux/macOS 核心测试均在 `testBoxBesideWallPreservesAnUnblockedMovementAxis` 失败；接手时 arena-look 仍运行，未重复 dispatch。
- 原因经源码与失败坐标复核：无 `o` 的自定义地图有两个出生组；showdown 要求一个组，初始化替换为默认地图。碰撞计算使用默认图，原断言却使用局部夹具图。
- 修复：在远离碰撞坐标的空地添加 `o`，不改墙、坐标或预期结果；断言实际地图 ID、尺寸、tiles 和 spawns 与夹具一致；断言起点合法、移动进入箱体、径向推出进入墙体。最终碰撞断言改用实际 game.map。
- 本地没有 Swift/Xcode，仅完成 diff 检查；Swift/iOS 结果以本次提交触发的唯一 CI 为准。不得标记已通过或已上传。

## 分支关系

combat-sample-1 当前为 `c1d8008f1d0343fa9ec897b203bd7fab6e8dc6a3`，与接续提交分叉（diagnostics ahead 14 / behind 5），共同祖先 `8bad602ac8d9c3f9ce88e68b41dad0f551fc2a90`。diagnostics 已有部分地图样板代码，但不等于所有样板分支提交已整合；后续逐项比对，禁止盲目覆盖或直接合并。

## 发布与验收分别记录

- 399：仓库保存的 Apple 查询证据为 1.2（399），VALID / IN_BETA_TESTING，见 build-399-testflight-evidence.json。它是历史查询证据，不是当前重新访问 Apple 的结果。
- 400：用户交接确认检查通过、未上传 TestFlight。
- 401：核心检查失败，不可发布。
- 本阶段不请求 TestFlight 上传；当前分支 push 不触发上传，禁止为了跑检查使用可能上传的 workflow_dispatch。
- 真机：399 已有 iPhone18,2 基准 JSON；后续修复没有真机数据，不宣称性能改善或呈现 FPS 达标。
- 美术：原创游侠资产存在，技术导入通过不能算正式美术验收。大厅、地图、菜单、弹窗需统一游戏设计，保持值班功能不受影响。

## 下一步与画面对照

1. 验证修复后的完整核心检查和 iOS 构建，记录 run / SHA / 各 job 状态。
2. 保留 docs/brawl-video-reference-review.md 的三个既有视频及抽样时间：Crow/Fang 大厅、足球开场和交战。按同视口游戏内截图/录屏比较中央角色占比、姿态与轮廓、菜单密度、地形层次、血条/弹药/特效遮挡；不可用概念图代替成品。
3. 从 399 基准分项数据定位慢回调，必要时增加音频/特效分项计时；CPU、GPU/呈现、真机与模拟器结果分开。
4. 同版本真机复测贴墙、绕箱、进出草与持续交战；未取得数据保持未验证。

每阶段更新本文件，附实际证据与下一步，避免依赖旧聊天。

## 402 阶段证据（持续更新）
- 修复提交：`8e84fb782a14c641dcf9f1fa1dcba5ac36d2a44b`。
- 唯一自动检查：https://github.com/wuyong9494-lab/kriswu/actions/runs/40837268036 。没有手动重跑。
- Linux 核心 job 123324883604：292 tests / 1 platform skip / 0 failures；原碰撞回归通过。macOS 核心测试步骤通过。记录时设备编译、模拟器编译/回归/截图尚未完成，不算整个 402 通过。
- 400 run 40833969101 已重新查到 success；未将其当成发布版本。
- 本轮实际下载并打开 400 的 arena-look（artifact 12880357756）中的 rangerLobbyAfter.png、rangerCombatAfter.png。大厅角色小、展示台显眼、外围玻璃按钮仍明显；混战武器、盾罩与强亮色特效严重重叠，仍不合格。截图是模拟器，不能证明真机性能。
- 400 混战画面 sidecar：956×440、固定中心镜头、canyon、seed 170017、simulationTime 1.2、Ranger_Original.glb。大厅 sidecar 记录 viewWidth 260 / viewHeight 698，可能是方向切换期间首次布局；后续必须校验截图时最终 bounds，不能据此推算模型占屏比例。
- 399 真机已有数据：empty / soloWalk / crowdWalk 回调 P95 均约16.668ms、>34.333ms为0；combat P95 42.654ms、慢回调102次。combat sceneUpdate peak168.330ms、effects mean11.977/peak81.693ms、damageText mean2.001/peak5.980ms。阶段重叠不可相加；effects 包含音效，不可等同粒子绘制瓶颈。399 的 audio 只测准备，400 已补 play 路径计时，需要新真机报告才可比较。
- 固定路线 soloWalk 无慢回调不否认用户实际走路卡顿：该夹具不覆盖贴墙/绕箱/草丛切换，下一次增加对应场景或手动录制再对照。
- 样板分支的独有文件包括 ArenaSampleArt.swift、ArenaBenchmark.swift、ArenaSessionMetrics.swift；diagnostics 使用其他实现。整合前比较各自功能与回归，不能直接覆盖。
