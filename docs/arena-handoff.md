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

## 下一阶段：大厅取景、战斗辨识与分项诊断

本批基于 ad573e3，仍在 diagnostics 分支。402 核心检查、设备编译、模拟器编译与动画回归已通过；本批准备时截图尚在运行，等其结束再推送，避免取消证据采集。

### 实施
- 大厅：保留原创游侠资产；相机统一按可见模型包围范围取景，取消截图专用的过大固定取景框。展台高度0.22降至0.07，半径0.95降至0.78；不改变战斗角色尺寸或碰撞。
- 横屏取景：尺寸变化重新生成截图布局证据；仅横屏宽高稳定到有效比例后写出标记。新增竖屏→横屏→竖屏相机回归；静态取景变化主动请求重绘。不是完整动作包围盒验收。
- 游戏控件：大厅侧栏与共享菜单按钮使用实色面板、描边、底部阴影及按压位移；共享卡片减少玻璃效果。尚未重构所有联机/冒险/次级页面，不宣称全菜单完成。
- 战斗：降低蓄力整身自发光、缩短并降低受击闪白；护盾降低罩体叠色并保留金色细边。保留护盾显隐、满充能脚下圈、受击动作、伤害数字与全部战斗规则。没有削减伤害或关闭关键事件。
- 性能定位：新增 particleDispatch / projectileUpdate 阶段，音频标签更正为准备及播放。新增仅关闭战斗音效的独立对照，音乐保留；增加与基准相同模拟结果的回归。所有CPU阶段有包含关系，不可相加，不是GPU时间。

### 验收与后续
- 本地 diff 检查与 workflow YAML 解析通过；无 Swift/Xcode，编译和测试交单次自动 CI。
- 必须查看本批游戏内大厅、早期交战、1.2s混战及动作视频，并与400/402相同场景对照。截图中的 Before/After 指旧/新游侠资产，并非本批优化前后；跨批对照应选相同 Original 资产文件和相同时刻。
- 用户视频仍按 brawl-video-reference-review.md 三个来源对照。当前只推进取景与可读性，不宣称达到同等美术或体验。
- 新的真机四场景基准及 noEffectAudio 对照未取得。碰撞与进出草真机复测、20–30分钟热稳定性、游侠造型与动作打磨、菜单逐层统一仍待完成。
- 不上传 TestFlight；不改值班功能。

### 403 实际检查及局部返修

- 402 已最终全部成功，未取消截图、未上传。
- 403：20c79f919ebfb89b4d25d2a0a0ff417c63c5cd4c，run https://github.com/wuyong9494-lab/kriswu/actions/runs/40838955031 。macOS核心292/0失败；Linux292/1平台跳过/0失败；iOS回归20/0失败（含两项新增）；设备/模拟器编译通过。7条已有并发警告仍在。TestFlight跳过。
- 已实际打开 Original 游侠的大厅、0.25s战斗、1.2s混战截图。相机证据为652×258，静态距离3.09635、动态3.09907；旧证据误记录竖屏尺寸的问题已修复。大厅角色明显放大，头脚和弩完整。
- **视觉返修**：403按钮出现文字投影重影；展台缩小后装饰环越出台面。将阴影限制在按钮背景形状上，避免文字和图标参与投影；将展台阴影/内台/装饰环半径一并收进六边形内切圆。不能将403整体视觉判为通过。
- 混战骑士身体颜色更可辨，但旧帽子/武器、透明重叠与技能光仍遮挡严重，未达到用户视频目标；未获得真机403数据。
- 403原始视觉制品：https://github.com/wuyong9494-lab/kriswu/actions/runs/40838955031/artifacts/12882765747 。Before/After仍指模型资产对照，跨批比较应保持Original资产相同。
- 返修仅针对上述截图中实际发现的问题，下一次检查必须重新查看大厅，不能拿403编译成功替代。
