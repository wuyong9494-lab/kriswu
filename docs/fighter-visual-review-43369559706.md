# 真实资源模拟器验收：43369559706

本记录绑定源码 `2206a5fe26a8b0c9f6217d6f11eca8fcc31474fc`，分支
`codex/fighter-visual-acceptance-20261113-1200`。
游戏整合点仍为 `5462aad48b6d3add4b19125f507f7ffa0a476e38`；2206 只新增触发注释，
没有改动游戏实现。后续修复不得沿用本次截图作为修复后的画面。

[GitHub run](https://github.com/wuyong9494-lab/kriswu/actions/runs/43369559706) /
[实际 job](https://github.com/wuyong9494-lab/kriswu/actions/runs/43369559706/job/131701889529)。

## 审核及执行结果

用户保存了确切分支的 environment branch rule，随后明确要求代点本次审核。
`fighter-private-assets` 的 required reviewer 与禁止管理员绕过设置保持；本次 approval 成功。
旧两次未开始执行的失败记录继续保留，不改写为本次结果。

本次只有一次 unsigned build、一个已安装的 iPhone 17 Pro Max / iOS 26.5 **模拟器**、
一次 `test-without-building`。精确 11 个方法各执行一次：**10 通过、1 失败、0 跳过**。
失败方法是 `DuelShadowPresentationTests/testBothShadowFamiliesUseVerifiedSourceEffectsAndReleaseTheirTrails`。
该方法在源文件第 367 行产生六条 `3 != 2` 拖尾数量断言；这不是六次重跑。
`xcodebuild` 返回 65，不能把整个原生集合写成通过。

构建、26 图与 3 个数据附件的导出、证据加密、上传和 runner 明文清理均成功。
通过的十个方法保留各自范围，失败不会抹除这些证据，也不会被它们掩盖。

| 时间口径 | 实测 |
| --- | --- |
| runner 前审核 / 排队 / 派发合计 | 566 秒；未推断各子阶段比例，不算构建耗时 |
| unsigned build 步骤 | 337 秒；内部构建命令 336.366 秒 |
| 模拟器准备步骤 | 100 秒 |
| native 测试及结果处理步骤 | 294 秒；测试命令 252.312 秒 |
| job 总时间 | 775 秒，2026-11-13 05:13:41–05:26:36 UTC |

这些数字不是帧时间或 60fps 性能数据。本轮未重跑原先通过的 107 核心、22 合成原生、
33 投锤核心 / 回放或完整工作流。

完整可复核的安全记录为 [阶段与耗时](validation/fighter-visual-run-43369559706-phase-summary.json)
及 [认证结果汇总](validation/fighter-visual-run-43369559706-authenticated-summary.json)。
后者的 132 项检查核对证据身份与一致性，不是额外运行了 132 项游戏测试。

## 通过方法中的具体数值证据

14 个源文件哈希与 2206 Git 内容一致；64 项编译包记录与两个既有认证清单、加密分块引用一致。
这些是认证产物内 runner 测量记录与源码的交叉验证，本地没有再次读取 64 个源资源二进制。
26 张图片 / 3 个数据标签唯一完整，29 个 payload 连同 manifest 共 30 个附件文件；
八张边界 PNG 的实际哈希逐项吻合端点证据 JSON。

双朝向 tick 24 / 71 的右锤端点与**同 tick 源持锤参考**最大误差约
`0.001245 mm`；左锤及 tick 23 / 72 的右锤端点误差为零。
23→24 的 base / tip 位移约为 11.61 / 13.85 cm，71→72 约为 2.83 / 4.08 cm，
与源动作自身相邻 tick 运动吻合。数值支持额外释放 / 接回错位已消除，
不代表重采样动作已经自然，不能用相邻帧位移非零来误判绑定错误。

两角色的真实资源 / 生产镜头故障注入均为：横屏 29° → 竖屏 100° →
失败保持 100° → 恢复同一 skinner 后回到 29°，同一 simulation frame 为 0。
这两份是行为 / 数值文本，不是截图；新增空 / 部分包络方法则是合成数组验证。

## 拖尾失败的根因分层

`retainedTrailCount` 统计当前条与尚在源 lifetime 内淡出的旧条。
`emitting` 才按 fighter / slot 保存当前发射 owner。端点不连续时创建新条、保留旧条自然消退，
是现有设计；既有 `testActiveTeleportStartsAnUnbridgedStripAndNextValidStepResumes`
还明确要求一把武器断段前后两条共存。不能靠立即删除旧条、放宽 0.75m 门限、
将期待值改为 3 或跨缺口连接来“修绿”。

因此本次确认的是测试把 retained 总量等同两把武器的错误假设；
没有证据证明生命周期泄漏。日志没有记录内侧断段的具体 tick / slot，不能编造。
六条失败没有出现在同 tick 冻结、结束 tick 400 清零或 shutdown 断开断言中。
已在修正提交 `5835db9ec66bb48611987eec7500505e14f685dd` 中实现更严格的验收：
每锤唯一当前 owner、退役条不追加采样、按原 lifetime 到期消失，
并记录实际断段 tick / slot / 相邻位移，保留游戏呈现行为和已有连续性保护。
实体槽位由已认证 profile 与固定角色要求独立确定：刘泉纬 [0,1]，孙登 [1]；
发射窗口来自 authoritative fight 规则，不以被测 adapter 输出缩小期望。

修改只有三个文件：`DuelWeaponEffects.swift` 增加 DEBUG 只读快照与说明；
`DuelShadowPresentationTests.swift` 增加逐 tick 验收；
`DuelWeaponTrailContinuityTests.swift` 延长现有断段方法到准确淡出 / 清理边界。
去掉新增 DEBUG 块和注释后，效果实现与受测 2206 逐字相同。
三个文件的 DEBUG 语法解析、diff 格式检查及独立只读代码复核通过；
**没有 Apple SDK 类型检查或新 native 执行，不能将本次 10/1 结果改写为修正后通过。**
提交带 `[skip ci]`，没有重跑工作流。

[修正验证和文件哈希](validation/fighter-shadow-trail-lifecycle-checks-20261113.json)
绑定精确提交；后续最小原生范围只有下面两项：

```text
SiteTests/DuelShadowPresentationTests/testBothShadowFamiliesUseVerifiedSourceEffectsAndReleaseTheirTrails
SiteTests/DuelWeaponTrailContinuityTests/testActiveTeleportStartsAnUnbridgedStripAndNextValidStepResumes
```

这次没有改动导致 atlas 纹样 / 高光过白的材质或几何呈现，以下视觉缺口仍然存在。

## 证据来源和安全边界

只下载本次新产生的加密 artifact `14012354471`，大小 6,355,864 字节，SHA-256：
`2b7ed1d33b115793834fc4f9252d429f276092e4ab6b06ddbb38a77a45085ea8`。
本地通过外层校验和、RSA-OAEP 接收方和认证封装验证，核对 run / source identity 后再查看附件。
私钥、资源密钥、源模型、用户原版视频、原始世界坐标与原生日志不进入公开仓库。
原图仅保留在用户原有 owner-private Sites 验收面板；公开交接只记录标签、哈希和结论。

64 项资源的编译包 bytes/hash 核对和实际场景使用必须分开记录：
入包完整不等于每个文件已经显示、播放或被所有流程使用。100 条完整资源台账也不能因此全部升级。

## 26 张实际图片已逐张查看

本节是本次原图的画面观察，不能扩写成完整动画、原始 shader、声音或真机通过。

| 图片组 | 数量 / 场景 | 观察与结论 |
| --- | --- | --- |
| `distinct-source-render-{idle,weapon1,heavy,kick}` | 4；真实双角色，固定正交棚拍 | 两个独立身体、个人头部、武士刀与双锤均可见，四姿态有区别。脸部及金属区域高光偏白、细节受损，人物质感需要修复 / 复核。不能把棚拍灯光直接当成生产镜头根因。 |
| `equipped-{ember,liu}-{weapon1,heavy,kick}-source-contact` | 6；真实角色、宫殿、接触事件、生产 world/camera | 可见完整角色和场景，选取的六帧未见人物被画面边缘截断。孙登轻击 / 重击拖尾出现明显三角扇形及装备贴图纹样；未达到平滑、清楚的武器光带目标。六帧没有完整 HUD / 触摸 / 连续播放验收。 |
| `shadow-boundary-liu-facing-{positive,negative}-tick-{23,24,71,72}` | 8；真实模型，固定测试镜头 | 两朝向释放与接回均可见，未见残留第二个锤网格；71/72 的青蓝细长条在画面上跨过身体，需要整段动作与遮挡复核。面部 / 胸甲高光同样偏白。相邻帧身体本身运动，不能以非零位移判定接回错误。 |
| `source-hit-first-simulation-step`、`source-hit-original-six-layers`、`source-block-original-nine-layers` | 3；认证纹理，合成接触事件 | 白色爆点、烟点和层叠可见；此处是隔离测试，不能据此宣称已还原参考片的金色接触层次、生产光照或声音同步。 |
| `source-katana-first-active-step`、`source-katana-original-material`、`source-double-hammer-original-material` | 3；认证纹理，合成端点 | 普通武器轨迹中可辨认装备 atlas 纹样和硬边；“hash 正确”和“可见像素数量通过”没有证明纹理与轨迹 UV 的适配正确。 |
| `source-katana-dash-two-materials`、`source-hammer-smooth-trail-material` | 2；认证纹理，合成端点 | 青蓝 dash 环和双锤细条可见；只是隔离材质 / 生命周期证据，未证明生产动作、宽度、遮挡或原版技能质感。 |

### 已确认的代码事实与尚待验证的根因

`DuelWeaponEffects.rebuild` 给历史端点 strip 生成“年龄 × 武器全长”的 UV；
`fragment` 的 `weapon` 分支用它采样 `sourceMain` / `sourceMask` / `sourceAlpha`。
实现注释已明确没有复现源 skinned trail mesh。这些是源码事实。
本次图中同时出现装备 atlas 纹样，是已观察到的视觉缺陷。
“源武器 atlas 的 UV 被当成历史 strip UV 使用”是优先核查的根因候选；
在实际源映射核实前，不把猜测写成修复完成，不用统一透明度 / bloom 掩盖问题。

## 最小文件级继续方案

| 问题 | 最小责任文件 | 具体工作与针对性验收 |
| --- | --- | --- |
| 双锤影技 retained ribbon 3 / 2 | `App/Services/DuelWeaponEffects.swift`；`Tests/SiteTests/DuelShadowPresentationTests.swift`；必要时 `DuelWeaponTrailContinuityTests.swift` | 区分合理淡出的旧段与当前发射段，定位实际断段 tick。保护 0.75m、缺帧断段与左右锤独立历史；不能改成允许任意数量。只重验受影响方法及连续性边界，不重跑完整 11 方法捕获。 |
| 普攻拖尾出现装备纹样与扇形硬边 | `App/Services/DuelWeaponEffects.swift`；实际需要武器 UV 时才扩至 `DuelWeaponAssets.swift`；`Tests/SiteTests/DuelWeaponEffectsTests.swift` | 先核对源材质纹理角色及源 mesh UV，再实现与实际武器匹配的几何 / 映射。以当前三张隔离失败图和孙登两张生产接触图为基线；新截图需绑定修复 SHA。不可只检查“有像素”。 |
| 棚拍脸 / 金属细节偏白 | `Tests/SiteTests/DuelWeaponAssetTests.swift`、`DuelShadowPresentationTests.swift` 的固定灯光；若生产也复现再到 `GLTFModel.swift` / `DuelWeaponAssets.swift` / `DuelWorld.swift` | 锁定姿势、曝光、相机，分别检查皮肤、布料、金属。区分测试照明与材质 / 色彩管理；不要同时改所有参数或把整体提暗当作已还原。 |
| 人物比例和生产构图仍未对齐 | `DuelWorld.swift` / `DuelCameraFraming.swift`；确有绑定问题再到 `DuelWeaponAssets.swift` | 以同姿态头身比、武器尺度、脚底接地和占屏关系对照；不同场景 / 机位的两张图不能作为精确尺寸标定。无效 skin 保护通过不等于比例通过。 |
| 打击、技能、特效的连续质感 | `DuelSourceEffects.swift`、`App/Views/DuelWorld.swift` 内的 `DuelWorldView`、`DuelWeaponEffects.swift`、现有技能呈现测试 | 记录轻 / 重击、格挡、挥空、连段、影技出击 / 顶点 / 回程 / 接回 / 打断的连续音画及事件 tick。保留已通过规则，不把 30 FPS 参考录像或静态图当作 60fps 实测。 |

发布仍受人物 / 武器 / 特效视觉缺陷、完整音画与动作验收、无障碍、双真机联机、
iPhone 17 Pro Max 真机持续帧时间及热状态证据阻塞。Build 702 的历史内部测试记录保持，
本轮没有 TestFlight 上传、游戏 Release、重复资源对象上传或保护规则绕过。
