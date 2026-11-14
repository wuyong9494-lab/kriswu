# 大厅身份与教学改为读取真实角色目录

## 已修复的展示问题

`DuelHomeView` 原先只按 hero 写死“孙登＝先锋·武士刀、刘泉纬＝军团·双锤”，武器教学也使用固定文字。实际战斗与预览始终按经过校验的 `DuelWeaponAssets.catalog.profile(for:)` 选择模型；这处错误影响卡片、底部身份栏与教学，没有把实际 `sun_triad` 切回 `sun_katana`。

当前 final v2 的真实目录为 29,221,179 B，SHA-256 `fbd9ecbd9fb16de79c0240404e315af81d8cbbaa113b6042e6afc5ed7b1d0330`。

| 角色 | 实际 profile ID | 大厅标题 | 武器教学身份 |
|---|---|---|---|
| 孙登 | `sun_triad` | 死亡森林三魄 · 忍刀双刃 | 黑色双刀 |
| 刘泉纬 | `liu_hammers` | 军团 · 双锤 | 双锤 |

刘的共享 root victim 动作不改变装备身份，盘古专属资源未取得，不能显示盘古已完成。

## 两个文件的改动

[DuelLobbyPreview.swift](../../App/Views/DuelLobbyPreview.swift) 在既有资源管理器完成真实选角后，从其已验证目录投影一个轻量快照。只复制 profile ID、标题、武器名和方向攻击/重击能力，不持有完整目录、模型或动画轨迹。快照仅在资源管理器实例改变时创建，没有为文字再次解析 29.2 MB 目录，也没有新增 GLB 读取。

Coordinator 在主队列异步交付快照，避免在 SwiftUI 的 `makeUIView` / `updateUIView` 更新期间同步修改状态。`pending` / `published` 去重，generation 取消过期通知；每次更新保存最新回调，预览拆除先失效 Coordinator，再释放场景。回调使用弱引用。

[DuelHomeView.swift](../../App/Views/DuelHomeView.swift) 缓存快照，用实际 profile 标题与武器能力显示卡片、底部身份栏和教学。未收到有效目录身份时显示中性待载入文字；旧控制模式继续使用它原有的说明。新增 `duel.lobby.weaponIdentity` 仅用于观察显示文本，不改变战斗输入或装备选择。

## 验证与执行边界

两个文件已通过 Swift 6 Linux 语法解析和独立的源码、生命周期审阅；没有新增镜像实现的测试，没有运行旧重型 UI 流程。语法解析与审阅不等于 Apple 类型检查或实际 UI 显示。

为新 UI 代码准备独立的 [source-only build 工作流](../../.github/workflows/fighter-lobby-source-compile.yml) 与 [受限 helper](../../.github/scripts/fighter_lobby_source_compile.py)。它只执行一次未签名 Apple `build`，不会执行 `test`、启动模拟器、装载私有角色资源、上传工件或 TestFlight。项目原本的网络规则构建阶段保留。823 个实际编译及工程发现输入逐文件固定，两个 UI 文件及材质修复另有精确摘要。

工作流成功最多证明 Apple 编译通过。目录身份实际显示、从对局返回后的状态和物理设备表现须单独登记，不把较早提交的截图归给本次文字改动。

| 文件 | SHA-256 |
|---|---|
| `App/Views/DuelHomeView.swift` | `2fbfb2b8d8ee41e3a7c7d02686c53b4c5d97e6edbdaab3ff9b238bdbe3989ee2` |
| `App/Views/DuelLobbyPreview.swift` | `cdb2d78a87c8a74d3e308cf901739f07944361c235df6b203291635db32f6263` |

材质修复的原生 6 项与 UI 1 项运行固定于 `5788ebb1001a6e0f31c5208cb2b955b48b00741c`；本次大厅改动在之后提交，其只编译证据与该原生运行分别归属。
