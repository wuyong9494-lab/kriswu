# 普通武器条带修正与四方法定向复验

继续分支为 `codex/fighter-visual-acceptance-20261113-1200`。
源码修正提交 **`da689f81d6138cac8657f88193d185b97ad60a16`**，直接父为
`121d738b9a41337b1019b39143e92c469192f657`；触发提交
**`bf3e677f461d2b868f0adc93278d298f2dc9987f`** 只增加新工作流的一行注释，游戏内容与 da689 相同。

本轮唯一新 [run 43377027433](https://github.com/wuyong9494-lab/kriswu/actions/runs/43377027433)
/ [job 131725794894](https://github.com/wuyong9494-lab/kriswu/actions/runs/43377027433/job/131725794894)
创建于 2026-11-13 06:11:57 UTC。记录时状态为 **waiting / required review**：
尚未获准、未分配 runner、步骤未执行，实际 native 方法 **0**、新图 **0**。
审核前等待时间不能算成构建耗时。这里的“Approve and deploy”是现有 GitHub environment 的按钮名，
本工作流只做无签名模拟器验证，不上传 TestFlight 或游戏 Release。

## 已修正的确定问题

修复前 2206 的普通刀 / 锤隔离图以及生产轻重击图中，出现装备 atlas 纹样与硬边扇形。
源码同时确认：历史 strip 只有年龄与武器长度的 UV，没有源装备网格 UV，却在普通 `weapon`
shader 中使用该 UV 采样装备 `sourceMain` / `sourceMask`。

本轮把两个职责分开：普通 endpoint ribbon 不再采样装备颜色 / mask atlas，继续使用已认证的
`sourceAlpha`、源颜色与透明度曲线、tint、强度和寿命。装备纹理仍用于实际武器模型，资源文件
和认证哈希没有修改。普通条带 UV.x 覆盖当前连续历史的 0…1 范围，透明纹理的 x/y 朝向保持。
真实年龄由每条材质独立的 `sourceTrailAges.xy` 提供；相邻 tick 的样本与过期前缀裁剪保证
首尾年龄插值对应各顶点实际年龄，展开纹理不再把首帧错误地当作经历了整个寿命。

这是对现有 endpoint ribbon 的有限适配。当前工作区没有原 skinned trail mesh / 原 UV 的完整证据，
**没有据此声称恢复原 shader、原轨迹网格或原版画面**。新画面的外观、边缘、宽度和遮挡仍待审图；
尚未生成的截图不能用修复前的 26 张图替代。

## 保持及验证边界

- 发射、断段、淡出、释放和材质复制路径保持；0.75m 连续性门限、几何宽度 / 顶点数 / 三角形数保持。
- Shadow 的 UV 与三类 shader 分支保持，既有孙登 0.48 呈现增益保持；没有用新增透明度或 bloom 隐藏问题。
- 命中、伤害、连招、投锤时序、网络规则、相机及生产灯光保持。
- 原 5835 的只读 DEBUG 诊断与严格生命周期验收保留，将合理淡出的旧条与每个武器 slot 的当前发射者分开。
- 214 个记录的 Core / Test / Package 文件与 `02d4e83` 的既有 33 项结果清单逐项一致；只复用相同闭包的证据，未重跑核心或完整工作流。

三份修改后的 Swift 文件已用 Linux Swift 6.0.3 执行 DEBUG 语法解析；diff 检查和独立源码审查通过。
这些结果**不是 Apple SDK 类型检查、Metal shader 编译、原生执行或视觉验收**。

## 最小文件级改动

| 文件 | 实际工作 |
| --- | --- |
| `App/Services/DuelWeaponEffects.swift` | 普通条带的材质职责、UV 与真实年龄分离；原 shadow、规则和生命周期保持。 |
| `Tests/SiteTests/DuelWeaponEffectsTests.swift` | 新增普通条带专项及无附件 GPU 年龄负控；保留原五图方法，并让冻结快照包含新年龄 uniform。 |
| `Tests/SiteTests/DuelWeaponGameplayTests.swift` | 新增孙 / 刘各轻击、重击的真实生产接触专项；原有成功方法逐字保持。 |
| `.github/scripts/fighter_visual_acceptance.py` | 增加闭集 `trail-followup`，绑定源码 / 方法 / 标签 / 设备；各阶段复核 prepared scope，防止漏环境变量后扩回 11 方法。 |
| `.github/scripts/test_fighter_visual_followup.py` | 12 项有界 helper 正反例，不属于游戏测试计数。 |
| `.github/workflows/fighter-visual-followup.yml` | 单次 unsigned build、单台已安装模拟器、四方法各一次、七图加密封装、清理；沿用 required review。 |

原 `fighter-visual-acceptance.yml` 文件未改。源码提交使用 `[skip ci]`，没有触发工作流；
随后只改新 followup 文件的注释，以精确前缀触发这一次新运行。

## 本次准确原生范围

| 精确 selector（均以 `SiteTests/` 开头） | 验证内容 | 新图片 |
| --- | --- | --- |
| `DuelShadowPresentationTests/testBothShadowFamiliesUseVerifiedSourceEffectsAndReleaseTheirTrails` | 原失败方法的 owner / 淡出 / lifetime 严格修正；真实认证资源 | 0 |
| `DuelWeaponTrailContinuityTests/testActiveTeleportStartsAnUnbridgedStripAndNextValidStepResumes` | 合成断段场景，不跨缺口，旧条与新条分别按寿命到期 | 0 |
| `DuelWeaponEffectsTests/testOrdinaryRibbonsUseSourceAlphaWithoutMeshAtlasAndPreserveAge` | 真实 alpha / 曲线与合成端点；atlas 替换不影响像素、alpha 置黑消失、年龄独立、双锤与模板隔离 | 3 |
| `DuelWeaponGameplayTests/testOrdinaryRibbonAdapterContributesToRealSourceContacts` | 真实角色 / 武器 / 舞台 / 输入 / 生产镜头；首次接触时只隐藏武器效果，检验条带自身像素贡献 | 4 |

准确标签是：

```text
ribbon-katana-first-active-step
ribbon-katana-source-alpha
ribbon-double-hammer-source-alpha
ribbon-equipped-ember-weapon1-source-contact
ribbon-equipped-ember-heavy-source-contact
ribbon-equipped-liu-weapon1-source-contact
ribbon-equipped-liu-heavy-source-contact
```

方法三中的 DEBUG GPU 负控使用明确的白 alpha 和 1→0 测试曲线，固定几何，仅改变年龄 uniform；
不假定未知真实曲线末值，也不替代三张真实资源附件。方法四仅导出有拖尾的四帧，隐藏拖尾的对照
只在测试内部计算。两者都不等于连续视频、实际可听音效、UI 流程或真机帧率验收。

## 有界工作流与资源安全

`trail-followup` 只允许源码列明的 4 方法 / 7 PNG / 0 data，未知 scope 拒绝。
附件根据 xcresult manifest 的确切 method → label → filename 与本次 simulator ID / name 核对，
缺失、重复、额外 payload、错误方法 / 设备、标签子串和不安全路径均拒绝。
导出失败仍可保存有界加密 partial evidence，不会把缺图写成通过。

12 项离线 helper 检查通过；另以旧认证产物的 29 条真实元数据格式和其中 7 个原始 payload
检查 parser 兼容性。后者只是旧文件的读取，**没有生成 7 张新图或执行新的原生方法**。
检查见 [helper 验证](validation/fighter-trail-followup-helper-validation-20261113.json)；
源码身份和本地检查见 [源码验证](validation/fighter-trail-followup-source-validation-20261113.json)。

继续验证既有 64 项资源记录和加密分块，不重复上传源对象。现有 recipient 公钥、密钥封装、
required reviewer、分支限制与清理机制保持；密钥、原模型、用户参考视频不进入公开仓库。
私有 Sites 仍只对现有 owner 可见。Build 702 的历史内部测试状态保留。

## 人物高光仍需独立诊断

已再次比较旧原图：棚拍 / 投锤边界台白脸明显，生产 heavy / kick 图仍能看见五官和阴影。
源码中棚拍是白 ambient 650 + omni 1100；生产是偏蓝 ambient 520 + directional 1250 + fill 180。
棚拍方法没有显式锁定 HDR / 自动曝光，而边界与生产截图锁定关闭。
因此这些图不是相同曝光的单变量 A/B，尚不足以认定生产材质或生产光照的确定根因。

本轮没有调整 GLTF PBR、曝光或全局人物亮度。下一最小诊断应固定同角色、姿态、相机、材质与
曝光，仅改变 ambient，分别检查脸 / 布料 / 金属；数据纹理色彩语义也需原生对照后才能归因。
“白像素减少”不能直接当作品质通过。人物比例、人物质感、打击质感、技能质感、特效质感，
以及 iPhone 17 Pro Max 持续 60fps、双机联机、音画和无障碍仍保持待验收。

旧 [43369559706 的结果](fighter-visual-review-43369559706.md) 仍是 **10 通过 / 1 失败 / 0 跳过**，
26 图 / 3 数据均属于 `2206a5f`。本次修正不能回写这次历史运行，也不能提前解除发布阻塞。
