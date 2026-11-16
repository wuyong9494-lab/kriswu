# 吴庸原配对与受控动作恢复 — 2026-11-16

本批在已验证的 50 段吴庸身体动画上追加了 12 段真实源动作，得到新的 62 段候选。六段配对投技不再依赖已散失的历史派生 catalog `41a63…`：原 motion、三份完整配置及六个原 trigger lock 构成独立的 `recovered-common-combat-source-contract-v1`。旧 builder 的身份门、302-file release 门及 App 身份均未修改。

## 原件与可复用规则

入口 `scripts/recover_erlang_combat_profile.py` 提供 `contract`、`append` 两个命令，以及供其他角色使用的 `throw_policy(profile, contract)`。合同不含某一角色的骨骼位置；policy 使用调用方自己的 root、footL、pelvis 和 COM。蛇王仍须从自己的源骨架与武器生成 profile，本函数不会替换其 source IDs 或武器胶囊。

完整 decoded-splits ZIP 的 SHA 为 `02bcd31d5b0f3ed992ca1972f2c6da5f59e6495fe3880fec45f8b073fbaa0e7a`。animation split、battle-trigger split、16684 构造器恢复 schema、9 个完整成员均按固定原字节验证。12 条动画记录的全部 29 个字段和嵌套 interval/damage/sound/gender/floor 字段经过具名 JSON 后的类型敏感逆投影；原 null、布尔、整数和浮点值保持不变。

| 原配置 | 记录 | 角色/用途 |
|---|---|---|
| `moves_settings.bytes` | 81–84 | 普通后投主动/被动、前投主动/被动 |
| `settings_sets_dynasty.bytes` | 248–249 | 原 D19 配对脱离主动/被动，用于双方配对互操作 |
| `moves_settings.bytes` | 87–89 | 原 Stun In/Loop/Out |
| `settings_sets_heralds.bytes` | 102–104 | H17 root-victim Start/Loop/End |

`ordinaryPanguEscape` / `ordinaryPanguResisted` 是既有配对 API 的角色名。本批没有启用盘古，也不将吴庸或蛇王标记为 D19 角色。

六个原 lock 的十条选定 trigger 逐条保存在私有合同中，公开只记录身份和结果：

| 原 lock | 本批绑定的事实 |
|---|---|
| 923 | 同时投技标志、普通后投主动/被动、前投被动别名；原 COM 接触距离 102、前墙分支 150 |
| 2568 | 普通前投主动；同一接触范围与后墙分支 100 |
| 2567 | 原互补随机选择：一方 `[1,99]`，另一方 `99 - Me`，原优先级 2002 |
| 945 | 两种原被投动作 End 后，对另一方设置 105 单位禁投计时 |
| 1544、1545 | 原 D19 脱离双方动作的配对别名；只恢复互操作输入 |

`normalizedUnarmedPower=1000`、source cm→arena mm 的 `92/10`、全动作保护区间的 `lastSampleTick+1` 关闭，均明示为既有 arena 配对适配。它们不伪装为本次新增原生证明。显式 source End 则按真实配置与 stride 换算，保留各自 AnimationEnd，不把两演员时长拉齐。

| 配对 | 原 motion | last sample | AnimationEnd | 保护结束 |
|---|---|---:|---:|---:|
| back active | `throw_p` | 100 | 92 | 88 |
| back passive | `throw_e` | 82 | 74 | 83 |
| forward active | `throw_front_a` | 164 | 156 | 165 |
| forward passive | `throw_front_b` | 160 | 152 | 161 |
| D19 active | `sven_throw_break_active` | 162 | 154 | 146 |
| D19 passive | `sven_throw_break_passive` | 120 | 112 | 121 |

三个主动动作的原攻击 Start 分别为 28、47、50，转换为 54、92、98 ticks，均落在双方真实 AnimationEnd 之前。原伤害类型是 UnarmedDamage，普通投技原 BaseDamage 约 0.1、D19 脱离约 0.15；合同保留完整原浮点值和防御字段，不自行补 null。

## 实际新产物

合同目录为 `recovery-20261116/common-combat-source-contract-v1/`；追加候选目录为 `recovery-20261116/erlang-recovered-combat-body-v1/`。

| 文件 | 字节数 | SHA-256 |
|---|---:|---|
| `common-combat-source-contract.json` | 59,336 | `04ae077c5cfb225ff0e794614bec3c15e2142285e885e45257f1e4c93f0ab79c` |
| `WuYong_Erlang_D15_Recovered_Combat.glb` | 18,576,776 | `7abc2955e2779c23541d14d51823369ec11d1954c8b3212ca0301834646460b3` |
| `SF3_Erlang_Recovered_Combat_Profile.json` | 18,732,553 | `88e46fab47dbaa2ce5dd280ccf13b13cde406aa6813cfa42735dca98542b861a` |
| `combat-body-receipt-private.json` | 5,588 | `14527b3be9fdb0dd6137eb3464c908d0b669576bfee221de38de5c3f0c8b48ac` |

所有 motion bundle 已在原归档中，无新下载。合同建立阶段核对原 catalogue 身份，明确 `motionObjectsRead=false`；追加阶段才逐一核真实 bundle、TextAsset pathID、长度和 raw SHA，并使用吴庸自己的 80 节点源 rig 转换。

追加后保留原 50 段 profile/GLB animation、原 BIN 前缀、全部几何/蒙皮/材质/个人头像不变。新 12 段写出后重新读取 GLB 并独立计算头部、骨盆、脚、脚趾、COM 和人体/武器胶囊端点：新增 **1,288 个头部样本、61,824 个比较点**，最大误差 **5.960464477539063e-8 m**。总 profile 为 62 clips、59 个具名 role、7,050 个头部样本；root-victim 三段按现有 core 的精确 clip 名消费，不添加猜测 role。

## 本批验证

原合同恢复与一次追加均 exit 0。随后仅运行 `test_erlang_recovered_combat.py` 的 5 项新增检查，**5 PASS / 0 skip，0.541 s**：

- 实际新合同与六对 source clocks、原攻击 Start 的双方存活窗口一致。
- 修改合同适配值或互补随机原参数会拒绝。
- 缺失配对角色或改动原 AnimationEnd 会拒绝。
- 显式合成的另一组 FK 投影确实改变 policy 的 root/foot/pelvis，证明接口没有借用吴庸位置；该负载不当作第二个真实角色验收。
- 真实 Stun/root 六段保留对应原配置、raw SHA 和各自时钟；尚未完整绑定的 profile 继续标记 false。

```sh
PYTHONDONTWRITEBYTECODE=1 \
PYTHONPATH=scripts:/absolute/recovery-20261115/python \
ERLANG_RECOVERED_COMBAT_ROOT=/absolute/recovery-20261116 \
python3 -m unittest -v test_erlang_recovered_combat
```

实际私有日志为 `notes/common-combat-contract-recovery.log`、`notes/erlang-combat-body-append.log`、`notes/erlang-recovered-combat-five-checks.log`。未重跑此前已通过的 50 段转换、Avatar 或原生测试。

## 后续边界

本候选已含 `ordinaryThrows`、Stun、root-victim，仍明确 `runtimeBound=false`、`fullMatchProfile=false`。下一步应以恢复后的犬、七模型、六剑 birth/idle 的新身份绑定能力 rules 和 15 条召唤轨，再实际验证完整 profile。个人颈部适配、FX/audio/companion 对新身份的重绑定、完整 release、App 原生与视觉验收仍单列。本批不声称恢复旧 body SHA，不修改中央身份或触发发布。
