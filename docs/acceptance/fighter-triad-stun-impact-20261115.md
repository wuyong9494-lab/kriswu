# 孙登魂魄眩晕与空中冲击回归：2026-11-15

## 代码身份与范围

- 远端基线：[8f74a82142526ec1a686052daf2a995274e88209](https://github.com/wuyong9494-lab/kriswu/commit/8f74a82142526ec1a686052daf2a995274e88209)。
- 本地基线提交：`6164f9bf1635781cc61ea8f8507ec739bf689389`；与上述远端基线共享同一 Git tree：`2ea0745c12eef85db2649656267816b1dc3b41d7`。
- 本次六个代码、测试与协议文档文件构成的候选 Git tree：`6a3ab9ff866b3444894e08531b28ce0c78c11330`。该树以基线加下表六文件计算，**不含本验收报告**，避免报告自引用。
- 整合父提交为 [3e3ee0ead3a22b37d62ab58e81580029e7588c1f](https://github.com/wuyong9494-lab/kriswu/commit/3e3ee0ead3a22b37d62ab58e81580029e7588c1f)；该提交只增加截图/Android 续接及记录，受测核心代码与上述基线相同。最终实现以包含本文的远端提交为准，不能由提交成功推断 Apple 原生构建通过。

## 缺陷与修复

实际魂魄命中先由 `applyHit` 建立冲击运动并保留原动作跳跃的身体高度，再经 `resolveTriadContacts` 施加眩晕。原 `updateTriadControl` 在非 root 分支调用 `advanceImpact` 后，无条件清零竖直速度，因此重力每个眩晕 tick 都被丢弃。

修复把清零速度限制到 root 控制。普通眩晕保留每个有效模拟 tick 的速度、重力和击退积分；hit-stop 仍完整冻结身体与控制时钟。未改原版资源、伤害常量或技能时序。根据既有协议约定，simulation rules 从 12 改为 13，schema 仍为 8。

## 实际检查结果

| 执行 | 结果 |
|---|---|
| Swift 6.4.2 / Linux 首次编译 | 测试前失败：既有 `APIDiscovery.swift:315` 类型检查耗时。**不是本缺陷的红测，不计为测试失败复现。** |
| Swift 6.0.3 / Linux 红测 | 构建成功，运行 4 个新增方法：root、回合清理 2 方法通过，空中运动 2 方法失败，共 30 个断言失败；0 意外失败。 |
| Swift 6.0.3 / Linux 绿测 | 5 个新增方法全部通过，0 失败、0 跳过；构建 28.39 秒，XCTest 0.081 秒。 |
| 旧 header / golden 定向回归 | 仅运行受版本影响的 3 个现有方法，全部通过，0 失败、0 跳过；构建 8.43 秒，XCTest 0.837 秒。 |
| 差异检查 | `git diff --check` 通过。 |

红测中，显式击飞目标高度停在 90 mm、速度为 0，而应继续为 170/240 mm、速度 70/60。零初速度魂魄命中原动作跳跃后，目标高度停在 306 mm，而应继续落到 296/276 mm、速度 -20/-30。修复后同样断言通过。

新增方法覆盖双玩家槽位、旧双锤与测试用盘古 profile 的独立控制、命中停顿、空中受击、root 与 stun 重叠、致命命中回合清理及规则 header。旧 golden 只改规则版本字节 `0c`→`0d`，其余 payload 不变；`DuelTriadFightTests` 的陈旧 schema7/rules11 断言改为实际 schema8/rules13，回放循环及其他断言保留。

在仓库根目录执行，`swift` 分别指向上表工具链；`<build-dir>` 为独立临时构建目录：

```sh
swift test --jobs 4 --filter DuelTriadStunImpactTests
swift test --jobs 4 --scratch-path <build-dir> --filter DuelTriadStunImpactTests
swift test --jobs 4 --scratch-path <build-dir> --filter 'DuelReplayStateTests.testInitialGameGoldenPinsTheCompleteFieldOrder|DuelReplayStateTests.testCanonicalScalarsHaveFixedGoldenByteOrderAndLengths|DuelTriadFightTests.testRenderingSnapshotsDoNotMutateAndReplayIncludesTheNewState'
```

第一条对应未运行测试的 6.4.2 尝试；第二条在 6.0.3 上分别用于修复前 4 方法和修复后 5 方法。第三条只运行三个受规则版本影响的现有方法。未运行全部旧套件或旧重型工作流。

## 源文件与网络兼容

| 文件 | 字节数 | SHA-256 |
|---|---:|---|
| `Sources/ShiftCore/DuelWeaponFight.swift` | 167166 | `ac309cb357f61b0466b1b506aa3d9cf7a977e12c9b3e18d26645c5098735200f` |
| `Sources/ShiftCore/DuelReplayState.swift` | 14286 | `02b982e41a07f25b58e65278b6c82cf03693801005032c68bedb756e4a4a87ff` |
| `Tests/ShiftCoreTests/DuelTriadStunImpactTests.swift` | 8252 | `48446c1964c50a72089abc5fafc32fc91bbb17ca8e04c0111487afd599c3dc19` |
| `Tests/ShiftCoreTests/DuelReplayStateTests.swift` | 17229 | `37c52e7ee19b5d7c334031d1b431675103884a66bf662226dd8f081f4250fb63` |
| `Tests/ShiftCoreTests/DuelTriadFightTests.swift` | 18442 | `2443fecfb605b25ec86cd9a4711990209f51849d1a1d2649306d9e677103e1b8` |
| `docs/fighter-replay-state-encoding.md` | 36326 | `43798959198bb10e4e0e6c546f5bfd7155037e33b9fba3ccdd654f051414ea71` |

使用仓库现有 `scripts/build_fighter_network_rules.py` 的 `build_manifest` 对基线与修复源码生成 source-only 清单，共 346 文件。仅 `DuelWeaponFight.swift` 和 `DuelReplayState.swift` 两项源码哈希变化：

- 基线指纹：`a19db23714947ee5bf069211afe6c2b19305d34b97d58a67f81fddd6038ba482`。
- 修复指纹：`43c4b2caad6da290b9ff6944f48b1f52f6f12fc392af8675271dec1c395c2cb7`。

这是源清单和规则标签检查，未执行真实设备握手，不能据此声称跨设备确定性已验收。

## 本地执行日志摘要指纹

日志仅用于本次检查，名称与摘要列于此；未把完整本机路径或日志正文写入公开仓库。

| 日志名称 | 字节数 | SHA-256 |
|---|---:|---|
| `triad-stun-impact-red.log` | 11398 | `c7ade0a2e7debe042225fd2ab43343309d1096bef2fdd3f28a6b90a44c70147c` |
| `triad-stun-impact-red-swift603.log` | 292349 | `4363a33aaef5ce64a697f30ac6ae21796fa7aedc9af73509e553f7e758207027` |
| `triad-stun-impact-green.log` | 5353 | `102ca9b46b716506f009c78f7a74e7ca52dc0efecbeca82653cfabec64f6e2d7` |
| `triad-stun-impact-golden-green.log` | 2205 | `b19e296bd54a64a4bd16d270ba00142f66dada8ed78d86a23cdc6ddde9e42086` |

## 验收边界

上述为 Linux 核心解释器与协议定向回归，新增参数明确为合成测试值。它不代表盘古真实资源绑定完成、原版物理数值已还原、Apple 原生画面、可听音频、物理 iPhone 性能或双机联机通过。本批未上传 TestFlight、未更改或公开解密密钥。
