# D19 矛模型生命周期与非反应性命中回归 — 2026-11-14

## 结论与证据范围

本次在观察到的 GitHub `54bfc94` 基础上修复三个核心行为：矛的 Create 阶段仍可被父角色受击取消；普通矛使用自己的完整 Create 长度，再保留 50 tick 自由飞行；`D19_Upper_Wind_Blade_Model_Attack` 的 `Hit_No_Reaction` 仍结算伤害，但不再中断目标技能或安排击退。

执行证据为 **Swift 6.0.3 / Linux 的 15 个定向核心测试通过，0 失败、0 跳过**。其中 6 个为新增方法、1 个纠正既有错误解释、8 个为直接受影响的既有回归。没有运行原始 iOS 播放器、模拟器、iPhone 17 Pro Max，也没有重跑重型原生验收、上传资源或 TestFlight。测试使用明确标注的合成碰撞几何，不能升级为原始模型或真机验收通过。

回放检查比较相同输入下的规范状态字节，包括取消、风刃命中、回合结束和下一回合；没有执行网络传输层测试。未增加存储状态字段，既有完整回放字段盘点测试通过。

## 源证据：创建与自由飞行是不同阶段

读取已恢复的私有源证据，没有重新解密、下载或公开密钥。以下摘要保留原字段；完整选定记录及执行摘要记录在本次 verification receipt 中。

| 原始来源 | 固定身份 |
| --- | --- |
| `settings_sets_dynasty.bytes` | SHA-256 `3d660f485ad5e238f23bf6dd19d16855635a9449fd213bf1dd468a9cc979f701` |
| `d19-lock-1546-compact-private.json` | SHA-256 `0adcbb2afc30e47db04f104d5f6aad290045efd7ee935ddd797ce0750a3633ae` |
| `d19-lock-1557-compact-private.json` | SHA-256 `157e76a9ce7e6d503092c53cd52046343bf82668911638a08c9f3cbdfd8fe411` |
| `h17-ninjato-d19-animation-named-private.json` | SHA-256 `ca4e897298b183818559a1a117f2ba24d529d8cb3f34cd0f10e9225cb49b7ae2` |
| `d19-motion-exact-join-private.json` | SHA-256 `3bcba93ebddf3c1218bf318b2c916cde5dd8b21220574be27f199825bb1cae49` |

### 触发器原字段

`lock1546 / SET_DYNASTY_19_MISSILE / setIndex 6 / triggerIndex 3` 使用 `a18["enum65537", "D19_Missile_Model_Pilum_Create"]` 事件，要求 `AnimationName == D19_Missile`，创建独立 `D19_MISSILE_PILUM_MODEL`。owner 动画 record240 的同名区间 `Start=5, End=5` 对应当前解释器 tick8。

`lock1557 / D19_MISSILE_PILUM_MODEL_CREATE` 的关键记录为：

| Trigger | 保留的原字段 | 实际约束 |
| --- | --- | --- |
| t5 | `priority=1000`; `events=[{"a26":["enum65539",null,null,null,null]}]`; 当前动画条件为 `D19_Missile_Model_Create` 或 `D19_Missile_Model_Create_No_Wall`；另有 `Not Hit_No_Reaction` | Parent Hit 在 Create 阶段仍可取消模型。记录同时保留 PostHit / HIT_FIRST / parent 条件，不能将事件简化成“创建后永久独立”。 |
| t5 actions | `a157[null,true]`; `a1[null]`; `a6["Physics",null,null]`; `a171["D19_MISSILE_PILUM_DESTROY","enum65537",1.0,300,null]`；另有停止 precast/trail | 创建阶段的父角色反应清理矛。当前核心无独立 Physics 特效模型，仅删除对应攻击队列/体。 |
| t8 | `a0["D19_Missile_Model_Create","enum65537"]` → `a6["D19_Missile_Model_Miss",null,null]`; `a171["Ranged_Free_Flight_Duration","enum65537",1.0,50,null]` | 强化矛在 Create 动画结束后进入 Miss。 |
| t9 | `a0["D19_Missile_Model_Create_No_Wall","enum65537"]` → `a6["D19_Missile_Model_Miss_No_Wall",null,null]`; 同一个 50 tick 变量 | 普通矛拥有自己的 Create 结束边界。 |
| t10 | `a44["enum65537","Ranged_Free_Flight_Duration"]`; `a0[null,"enum65537"]`; `a37["RoundFightEnd"]`; 删除动作为 `a50[null,null]` | Miss 到期、Active 动画结束或回合结束销毁；自由飞行不允许跨回合保留。 |

### settings records241/242 与 31 帧 bullet

两记录的 `FileName` 均为 `ranged/str_pilum/s_rng_str_pilum_bullet.bin`：

```json
{
  "record241": {
    "Animation": "D19_Missile_Model_Create",
    "FirstFrame": 5,
    "EndFrame": 26,
    "SelfEndFrame": 0,
    "BlendingFrames": 0,
    "Attack": {"Start": 24, "End": null}
  },
  "record242": {
    "Animation": "D19_Missile_Model_Create_No_Wall",
    "FirstFrame": 5,
    "EndFrame": null,
    "SelfEndFrame": 0,
    "BlendingFrames": 0,
    "Attack": {"Start": 24, "End": null}
  }
}
```

exact-join 报告中的同一 bullet 身份：

| 字段 | 原值 |
| --- | --- |
| `name` / `frames` / `arrays` | `s_rng_str_pilum_bullet` / **31** / `2` |
| `path_id` / `bytes` / `bone_ids` | `-448972738872743105` / `790` / `[333]` |
| `sha256` | `2ba5f0540d80aa95666492f34a6ca8ade411886b49e3ae0fed44778fa4c94f39` |
| `bundle` | `4631e940cab6eb9ef36feb1f396e8b7e.bin` |
| bundle `sha256` / `bytes` | `fc4289eaa2747da7bc5abbff82c7db2d53b0417398268122a47af6fe7fa685af` / `422033` |

record242 的 `EndFrame=null` 不能被替换为 record241 的 `26`。按现有 60 Hz 核心与 30 fps 源帧约定，两个伤害入口都是 tick46；强化 Create 到 tick50，普通 Create 到 tick60。普通攻击体覆盖 14 tick Create 攻击期和 50 tick Miss，共 64 tick；强化分别使用 4 tick 初始攻击体和 50 tick 飞行体。

**tick60 是普通 Create clip 的结束边界，不是伤害开始时间；伤害入口仍为 tick46。** 原恢复报告的 `nativeFrameConversion.status` 仍为 `Raw configuration frames; player clock/stride conversion is still under native review.` 本次证明当前核心解释器按上述恢复字段执行，不宣称原始播放器时钟已获真机确认。

## 完整取消与命中路径

`DuelPanguState.startSource` 排队 → `stepSource` 按 live tick 释放 → `DuelWeaponFight.consumePanguEffects` → `DuelPanguSpatialState.spawn` → `contacts` → `applyPanguHit/applyHit`。

父角色的普通受击进入 `applyHit → state.interrupt → cancelMelee`；击倒另清理待派生攻击；孙根缚进入 `applyTriadControl → cancelPendingDerivedAttacks / interrupt / cancelMelee`。本次让这几个既有入口按同一 Create/Miss 边界清理空间攻击体。回合结束仍重建整个 `panguSpace` 并强制中断状态；下一回合重新初始化，不沿用自由飞行体。

格挡路径受 `!blocked` 约束，不触发上述 owner-cast 中断。有效测试在普通矛 owner 动作结束后持盾受击，确认仍存在的自由飞行体保持同一 ID 与到期 tick。没有制造“技能施放中仍可普通格挡”的不可达状态。

### Hit_No_Reaction 的精确范围

settings record224 的 `D19_Upper_Wind_Blade_Model_Attack` 原 `HitTags` 包含：

```text
Hit_Set_Ability, Break_Unbreakable, Unblockable, No_FX_SFX,
Hit_No_Critical_Reaction, Hit_No_Reaction, Hit_Shadow_Attack,
Hit_Ability_Move, Hit_D19_Wind_Blade
```

record235 的 `D19_Wind_Blade_Model_Attack` 没有 `Hit_No_Reaction`；它包含 `H_Chest_Middle_Average` 与 `Hit_No_Wall_Reaction`，原 `Impulse={X:8000.0,Y:5000.0,Z:null}`。因此仅 `sourceStrike == .upperWind` 排除普通反应，未把所有风刃设为无反应。

修复发生在 `applyHit` 的 `targetReactable` 判定，伤害准备、血量扣除、命中计数与资源结算继续执行。真实合法阵容只允许一个 `liu_pangu`，本次没有为测试放宽 catalog 或双方身份校验：以刘的 upperWind 命中孙，确认孙技能原 cast ID、独立魂体以及待释放技能仍有效；矛自身队列与空间体则由普通命中、击倒、孙根缚验证。

## 最小文件改动

| 文件 | 修改 |
| --- | --- |
| `Sources/ShiftCore/DuelPanguState.swift` | owner 取消依赖保留到强化 tick50 / 普通 tick60；普通矛 lifetime 54 → 64。 |
| `Sources/ShiftCore/DuelPanguSpatialState.swift` | 在既有取消入口删除尚处 Create 的矛体；用已有 `expiresAt`、`sourceLifetimeTicks`、空间 tick 推导年龄，不新增回放字段。 |
| `Sources/ShiftCore/DuelWeaponFight.swift` | upperWind 保留伤害但排除技能打断与击退。 |
| `Tests/ShiftCoreTests/DuelPanguRuntimeTests.swift` | 纠正“tick8 创建即独立”的既有断言，保留 t5/t8/t9 证据说明。 |
| `Tests/ShiftCoreTests/DuelPanguReleasedModelTests.swift` | 新增 6 个实际生命周期/接触回归方法。 |

## RED → GREEN 结果

首次 RED 在未改生产代码时复现：正常矛寿命少 10 tick；tick8/45 被普通命中后仍能释放；tick46/59 的 Create 攻击体仍存在。回合结束/下一回合清理原已正确。

初版测试另有两个 fixture 错误，已单独记录而未修改相关生产逻辑：把跨过自然充能 tick60 的 charge 增加误认为退款；Triad 合成攻击体 top11000 超出合法上限10000。前者改为相同时间的未受击对照，后者改用 bottom9000/top10000。修正后的接触 RED 在未改生产代码时实际显示：孙的 cast ID 3 被清空、位置从4300移动到5460、待释放波没有出现。

GREEN 中所有 15 个选定方法通过，耗时 21.201 秒。随后自审修正席位 fixture：固定第一席朝向，确保盘古在第一席向右、第二席向左；只重验这个新增方法，48 个组合全部通过，耗时 8.226 秒，生产代码未再变动。新增测试包括：

- 普通/强化矛 × 6 个时刻 × 普通受击/击倒 × 两席位与相应左右朝向的 48 个边界组合。
- 孙根缚的 8 个 Create/Miss 边界组合。
- 普通与强化的完整且不同飞行寿命。
- owner 动作结束后格挡仍保留普通矛的剩余飞行。
- tick7、8、46、60 发生回合结束，随后下一回合无旧攻击复活，并比较规范回放字节。
- upperWind 实际命中 5 次、合计仍扣 75 HP，孙原 cast ID、位置、独立魂体和后续技能释放保持正确。

直接相关既有方法包括初始强化命中是否取消飞行、Rhythm/普通矛 Light、源风计时在反应/击倒/根缚下保留、强制重置与回合结束清理、完整存储字段回放盘点。未运行其他重型集合。

本地执行凭据：`pangu-released-model-red.log`、`pangu-released-model-red-contact.log`、`pangu-released-model-green.log`、`pangu-released-model-facing-green.log`、`pangu-released-model-verification.json`。receipt 固定源证据 digest、选定原字段、测试方法和结果、生产与测试文件 digest；它不包含解密密钥或资源内容。
