# Arena 第一阶段验收基线

目标设备：iPhone 17 Pro Max。真机目标：持续 60 FPS；首战、集中技能、混战、连续 20–30 分钟均需测试。当前没有该设备测量，帧率、发热、GPU 和功耗均未验证。

## 样板范围

保留现有内容，不扩充角色和模式、不迁移引擎。先做游侠、骑士、法师和三对三占点的两张地图。

- 游侠：远程单发、直线压制；用掩体和侧翼突进反制。先校准瞄准方向、发射事件、弹道碰撞与命中反馈，不先加震屏或粒子。
- 骑士：近距离散射、冲锋突破；接近游侠有优势，空冲后可被拉开距离反制。
- 法师：越墙投掷、封锁争夺区域；迫使游侠换位，突进贴身时脆弱。以上是设计方向，平衡尚未实测。
- 地图 A：三路连接中央占点区，侧路设断续掩体，避免出生点直射中心；绕后路线必须可读。
- 地图 B：中央掩体与双侧突破口，草丛不贯通出生点至据点；保留投掷位并提供可到达的侧翼反制路线。
- 大厅：保持原创奇幻主题，统一暖色主光、冷色轮廓光、哑光卡通材质；角色主展示、开打主按钮、模式卡和次级菜单有明确层级。地图装饰不得遮挡弹道与碰撞边界。

## 批次一：诊断与生命周期

- 六项 CPU 阶段：模型文件首次解析、核心模拟、AI、骨骼动画、场景更新、场景创建。
- 每项记录次数、平均值、启动以来的单次峰值；内存固定。场景更新含骨骼动画，场景创建可能含首次模型加载，不能相加。
- 使用单调时钟和 Instruments signpost。模型计时不代表 GPU 首次上传；缓存命中不记录为首次加载。
- 面板回调 Hz/P95 来自 CADisplayLink，不是 GPU 帧率或屏幕呈现帧率。慢回调现有阈值约 34.3ms，不能据此断言满足 16.7ms 预算。
- 开启性能显示后重启 App，再进入大厅和首战，确保捕获冷启动。峰值跨对局累计；重新启动 App 开始新会话。
- 停止对局时清除本地按住的输入与待发攻击，防止恢复后自动移动/射击。停止后的回调不得推进场景。

## 回归矩阵

| 场景 | 自动化 | 真机 |
|---|---|---|
| 隐藏后重现，过期攻击不重播 | 已有骨骼姿态对比测试 | 未验证 |
| 连续攻击、移动攻击，结束回到行走 | 本批新增骨骼对比测试，待 CI | 未验证 |
| 死亡淡出、复活清除攻击层 | 本批新增骨骼对比测试，待 CI | 未验证 |
| 停止两次，不渲染、不保留输入 | 本批新增测试，待 CI | 未验证 |
| 角色切换、退出重进、后台恢复 | 尚需完整交互测试 | 未验证 |
| 首战、混战、集中技能、30 分钟 | 诊断已埋点，未测量 | 未验证 |

截图生成只证明流程执行。必须打开对应提交的大厅、战斗截图检查人物颜色、朝向、遮挡、菜单边界、战斗可读性；静态截图不能证明动画或流畅度。

## 当前构建与提交

Build 386: e29d39f54946cc9aaed2cc67a609390def5adc47。2026-10-29 最终结果：Linux/macOS 核心测试、iOS/模拟器编译、4 项动画回归通过。截图的 simctl launch 等待 150 秒后超时，无截图产物；视觉未验收，TestFlight 被正确跳过。下一批改用独立新模拟器截图并收集启动服务日志，不重跑相同提交。
Build 383: 签名、上传、测试说明任务均成功；无需重新接受 Apple 协议。

本地环境无 Swift/Xcode，新增代码不能在本机编译；必须通过云端核心测试、模拟器回归与 iOS 编译后才能作为已验证结果。不可用旧构建的成功结果为新提交背书。


## Build 387 closure and next sample

- Commit `8bad602ac8d9c3f9ce88e68b41dad0f551fc2a90`, run https://github.com/wuyong9494-lab/kriswu/actions/runs/40814402943.
- Core checks, device compilation, simulator compilation and 7 animation/lifecycle tests passed. Fresh capture simulator resolved Build 386's launch timeout. No duplicate 386 run was started.
- Actually opened all three engine captures (`arena`, `arenaPlay`, `arenaPerf`): knight is fully visible and colored in this sample; oversized competing lobby buttons, noisy floor and tree-like bushes remain. This is NOT whole-roster visual acceptance.
- Diagnostic branch deliberately skips TestFlight. Build 383's successful signing/upload/Chinese notes remain the last verified distribution evidence; Apple agreement is not a blocker. Build 386 capture failed and upload was skipped.
- Simulator overlay is callback timing, NOT device/GPU performance. No claim of stable real-device 60 FPS or thermal acceptance.

### Implemented sample (pending next cloud validation)

Lobby: compact icon menus, 56-point main battle button, bounded central hero framing and static layered backdrop. Hero clarity and menu hierarchy take priority over background complexity. The user's 500×281 Interface In Game blue lobby screenshot is a historical composition reference, not evidence of the current original game or a camera measurement: https://interfaceingame.com/wp-content/uploads/brawl-stars/brawl-stars-main-menu-500x281.png .

Canyon only: opt-in original procedural purple floor/walls/crates and short faceted leaves. Existing map tiles, routes, visibility and collisions unchanged. No new dynamic lights or transparent foliage layers. Other maps retained. Screenshots run the same ranger/knight/mage 3v3 seed 170017 to simulation time 6 seconds, then freeze; compare `arenaBaseline` and `arenaPurple`. Random particle poses and asynchronous render timing may still differ; do not infer a timing improvement from still images.

Readability: target-specific damage/heal merging over 120 ms, 12 reusable visible number nodes, bounded 256 image cache; health/damage calculation unchanged. Visibility is rechecked before queued text appears and while it remains displayed.

Diagnostics: individual toggles for numbers, particles, character outlines and alternate-frame bone sampling; change ONE variable and restart for each run. Animation time still advances when sampling is skipped. Copy report from battle with performance display enabled. Window is last 120 callbacks; slow threshold >34.333 ms. Lifetime callback duration/count/maximum excludes background gaps. Stage CPU counts/mean/peak retain cold load since app launch; nested stages cannot be added. GPU time and actual presented frame rate are explicitly unmeasured. UI/SceneKit internal submission remain uncovered; use Instruments on device. Fixed benchmark is reproducible stress input, not a representative 30-minute session.

### World/camera baseline (unchanged in this batch)

Perspective projection; offset (0,16,12.5), about 52° down from horizontal. Adaptive vertical FOV preserves horizontal half-span 12 in landscape or 6.6 in portrait. Follow look-ahead 4.2, movement lead 1.35. Tile=1 world unit; fighter collision radius=0.42; base model scale=0.95 plus character-specific factors. Canyon actual dimensions 15×25 tiles; this is not the visible screen extent. Accessories and animated model bounds must be measured per character. No reliable matched-aspect original gameplay frame has yet established precise original camera parameters. Camera A/B alternatives are deferred until this visual-only sample is inspected.

### Outstanding acceptance

New sample needs cloud compilation/tests and actual screenshot review. Full lobby character-switch/panel/foreground-background interaction coverage, all-character extremity framing, device first-load/mixed-combat/skill bursts and 20–30-minute thermal run remain UNVERIFIED. Ranger firing/audio/haptic timing polish is a subsequent batch, not claimed complete here. Diagnostics builds must not overwrite the stable latest Release artifact.
