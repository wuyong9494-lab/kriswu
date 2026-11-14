# H17 原始三维碰撞与重击落地事件诊断

## 结论

旧探针的零接触来自过近的重击出招位置；调整合法移动与出招距离后，保留全部原始三维几何，可以实际命中并扣血。孙的首击源防护免除该 tick 的受击反应；600 tick 冷却内第二次重击会正常击倒，并跨过 `h_hit_head_fall` 第 19 源帧的落地事件。

**本条不是碰撞修复缺口。** 没有压平 Z、扩大碰撞体、修改 profile、删掉防护或更改角色血量。达到完整两击结果后停止，未增加其他对局。

证据范围为现有 staged catalog 的 `sun_triad` 对 `liu_hammers` 在 Linux 核心中的实际执行。后者仍是旧双锤刘，不能表述为盘古独立模型完成。本次没有渲染画面或播放音频，不能升级为模拟器、真机、原始媒体画面或听感验收。

## 固定资源与规则身份

catalog `SF3_DistinctFighters.json`：28,518,122 bytes，SHA-256 `2fad3a3e958238b5a294ec7ecdc94d004eae515c252184c8385d7b8460ef4801`。探针只读取该文件。

| Profile / role | 源 clip / frames | 源内容 SHA-256 |
| --- | --- | --- |
| `sun_triad / idle` | `ninjato_stance_idle` / 59 | `018403d58e1fbc5e9613c3da765675f2dd838f6ead6719de0087f5ca7a7e0076` |
| `sun_triad / knockdown` | `h_hit_head_fall` / 59 | `9fda1b85f59b5ff7a6b6406ad3720347ab0b43f9330108d249892ec2ce08fef2` |
| `liu_hammers / heavy` | `dual_hammers_heavy_slash` / 63 | `7ddc51b6000c8750718434666ecb8f67151c3be94f7fd89355b445eb4e4c4de6` |

旧双锤没有显式 `combatRules` 或 `collisionEdges`，因此合法调用链为 `resolvedCombatRule → legacyStrike`，有效区间 tick15…96、双侧武器端点、`collisionEdgeIDs=nil`。端点不是空数组。当前兼容规则为 damage190、blockedDamage15、knocksDown=true、hitStop2、击退200mm/10ticks；这是既有应用兼容规则，不是恢复出的盘古平衡数据。

孙的 idle 与 knockdown 都有 15 个恢复出的 hurt capsule。`contact()` 因此走原始三维 capsule sweep 分支，没有回落到二维躯干矩形。代码路径位于 `Sources/ShiftCore/DuelWeaponFight.swift` 的 `resolveOrdinaryContacts`、`contact`、`sourceHurtCapsules`，规则回退在 `Sources/ShiftCore/DuelCombatRules.swift`。

## 三层原因与实际执行

### 1. 原控制器把重击带入近距离几何盲区

旧探针在根距离小于800mm时持续输入 heavy，1800 step 无接触。该重击的源 root 到 tick46 已向前推进约1434mm；角色分离规则会把过近的出招压到最小根距离，主锤向前下挥时越过近身目标。

只读离散几何诊断中，固定根距离645mm时，最接近的一组真实三维胶囊仍差59.772mm；用于分析的二维投影出现117组重叠，但不能据此修改真实碰撞。固定根距离1200mm时，tick46左锤已可与 Stomach 胶囊相交，说明需要在**攻击采样时**达到合适距离。

因此合法探针在入场结束后通过移动把出招距离置于2600…2700mm，使源 root 推进后 tick46 的真实根距离约1200mm。

### 2. 正确距离下首击真实命中，但源防护免反应

首个完整只读探针在 step513、根距离2600mm发出一次 heavy；step559 / clip tick46 / 根距离1164mm 实际命中，孙 HP 从1000降到871，接触点为 `(3.0052524, 0.8126994672, 0.0688653)`。

孙未立即进入击倒动作有对应核心机制：`DuelTriadState.defendAgainstIncomingAttack` 在当前 level6 源运行时、首次可防护的非 shadow 命中时设置 `sourceDefenderProtectionRemainingTicks=1`，并启动600 tick冷却。该 tick 的 `impactImmune` 排除击退和动作打断，同时伤害继续结算。这个结果不能被判为 `completed` 即通过，也不能被误判为碰撞或击倒代码断链。

### 3. 冷却内第二击正常击倒并触发落地源帧

随后执行一次两击探针，保留全部防护和原 catalog，仅使用合法移动与两次 heavy 输入：

| 事件 | 固定 step | 重击 clip tick | 根距离 | 实际结果 |
| --- | ---: | ---: | ---: | --- |
| 第一次出招 | 513 | 0 | 2600mm | `canUse=true` |
| 第一次命中 | 559 | 46 | 1164mm | HP1000→871；源防护保持 idle，无 knockdown |
| 第二次出招 | 751 | 0 | 2617mm | `canUse=true` |
| 第二次命中 | 797 | 46 | 1181mm | HP871→742；进入 `h_hit_head_fall`，knockdown116 |
| 落地事件采样 | 837 | 受击动作 tick37→38 | — | `crosses(sourceFrame:19,totalSourceFrames:59)=true`，累计恰1次 |

两次实际命中相隔238次固定 step 调用，处于600 live tick防护冷却以内。第二击的源 clip duration 为116 tick，落地事件不是靠动画名称推测，而是由实际 `sourceMotionSamples` 跨帧记录确认。

## 执行凭据与后续边界

本地目录 `heavy-contact-diagnosis-20261114` 保留只读 `Probe.swift` / `ProbeTwoHits.swift`、已链接执行文件、编译日志、`result.json` / `result-two-hits.json` 与 `verification.json`。receipt 固定 catalog、源 clip、规则、两个探针与输出 digest，不包含媒体内容或 `sourceBytesBase64`。

两击结果在837 step达到目标后立即停止。没有重新运行成功的重型集合，也没有修改或上传任何资源版本。核心已确认的碰撞、扣血、源防护、击倒和落地帧，应与后续原始画面、音频播放、模拟器和 iPhone 17 Pro Max 验收分别记录。
