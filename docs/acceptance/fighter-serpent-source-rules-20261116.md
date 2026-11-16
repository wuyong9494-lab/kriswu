# 蛇王 D13：套装等级与原触发规则恢复

日期：2026-11-16。本批继 [原动作配置恢复](fighter-serpent-named-settings-20261116.md)，提供可供玩法实现使用的完整源输入。没有修改 App / WeaponFight / Identity / workflow，没有激活生产蛇王。

## 源身份与范围

原集合 `D_LEGENDARY_WPN_SHUANGOU_01_04` 的 ID 为 117、alias 为 D13，四件分别为 `WPN_SHUANGOU_01_04`、`ARM_AGL_41`、`HLM_AGL_41`、`RNG_BOTTLE_01_02`。helper 精确验证集合成员、四件原 tags 及两份脚本全文身份，并使用不执行 JavaScript 的受限 literal parser 读取等级对象。

原 decoded prod 为 2,751,235 bytes / `165f5b1483909c461fabc86c591efd01ebb4915cc34ef7bf2579d52c94b35950`；decoded splits 继续固定 `02bcd31d5b0f3ed992ca1972f2c6da5f59e6495fe3880fec45f8b073fbaa0e7a`。实际 battle split 为 16,429,699 bytes / `c3941a009cf87916ba076915b77bf308c33e7a00b9cdbd618bb353b5a6f7651b`，其准确 `lockTree.bytes` 为 885,808 bytes / `c8ab9d34b121365e5a8f1f58d1f2be49f7e57d0074ca819657dffd3f02675d11`。

| 原规则范围 | 数量 | 本批处理 |
| --- | ---: | --- |
| D13 专属锁 1374–1408 | 35 | 完整保留；其中 Boss / bot 分支也保存，不能据此说它们在玩家对战全部启用 |
| 双钩 style 子树直接引用 | 12 | 保留原 style 条件和全部祖先门槛 |
| D13 关联共享 / 模式锁 | 4 | 11、12、328、2674，单独标记 scope |
| 合计 | 51 锁 / 75 TriggerSet / 295 Trigger | 保存原二进制与新源 JSON |

相邻锁 1373 实际属于 D12，不属于本批 D13。这里的选择来自原 lock tree、准确 set 名和原 style 分支，没有用“相邻编号应该一样”替代身份核对。

## 为后续机制实现保留的关键信息

每个 Trigger 的原始六字段、优先级、events、conditions、actions 全部保存；同一锁在树中多次出现时，每条路径和每层原始条件分别保存。排队字段与触发顺序没有因便于阅读而删去。所有字段经过 JSON 写读后类型敏感的逆投影核对。

| 机制入口 | 原始证据位置 | 可证实的源含义 |
| --- | --- | --- |
| 特殊起势与 UI / 输入 | 1374–1381 | D13 起势、额外按钮、阴影按钮与敌方反应分支独立存在 |
| Bloom 与阴影能力 | 1384、1389 | 独立 Bloom slider、禁用常规阴影能量 / 阴影形态、四种能力 CD 与相互短 CD；完整命中、状态和反应条件保留 |
| 四种积毒 | 1389 | 武器、徒手、远程、阴影分别存量；源公式同时包含命中值、基础倍率、上限及其它 perk 值，不是统一固定伤害 |
| 主动毒性爆发 | 1379、1381、1398–1399 | 动作、source interval、积毒爆发与强化按钮分支分开，不把请求按钮等同实际命中 |
| Lv3 / Lv5 | 1395、1397 | 四通道系数乘 1.3；Lv5 改写能力 CD 与爆发系数。保留原操作和优先级 |
| Lv4 | 1396 | 强化能力与枯萎状态使用 Bloom 条件和独立触发，不由渲染猜测 |
| Lv6 | 1400–1403 | 毒瓶动作 / 模型、毒云与四种积毒 pulse；有单次使用状态及原先决条件 |
| Lv7 / Lv8 | 1404–1407 | 独立高级分支原样恢复，尚未宣称核心适配已实现 |

集合的 1–8 级字段是原始各级条目，**没有把它们私自累积成最终等级对象**。`FakeValue*` 也保留原名和值；它们不会在此被解释成伤害、冷却或状态常量。真正战斗参数应依据触发锁及其取值链。

## 原模型与外观分开

`CreateModel` 的实际显式路径包括 `mgc__common_model_40`、`mgc__islander_push`、`mgc__islander_root`、`shd__shadow_ranged_agile_cloud`。瓶子分支从当前 Ranged 装备创建，显式模型路径为空；不能据此填一个推测模型名。

普通蛇与腐化蛇外观是 `a46` 效果请求：1384 的 `D13_snake(pelvis)`、1407 的 `D13_Rot_snake(pelvis)`。它们与上述碰撞模型是不同入口。是否引用单独 `mgc__snake_liana` 资源还应核对对应原 prefab 的 PPtr，不能以名称相似替换碰撞 rig。

## 交付与实际验证

新增 helper 为 `scripts/prepare_serpent_source_rules.py`，专项检查为 `scripts/test_serpent_source_rules.py`。源输出使用 `original-d13-source-rules-v1`，固定 `sourceOnly=true`、`runtimeBound=false`、`conditionsEvaluated=false`。文件名称和字段不属于 App 的角色发布 manifest。

| 私有产物 | Bytes | SHA-256 |
| --- | ---: | --- |
| `serpent-original-levels-v1.json` | 6,325 | `b240f29568b7fed0886191a4c1500a983278839121489d954e838d6f220431d5` |
| 总 `receipt-private.json` | 26,954 | `d169d518d0133ee6180c81d11edd5b5c11816e91886b7aae2eed54806f775d37` |

四项新增专项一次通过（unittest，0.666 秒，无 skip）：51 份实际原文件及 295 个完整六字段 join；祖先条件和重复树路径保留；实际八级条目不被隐式合并；表达式 / 重复 key / 非有限数 / 非原件输入拒绝。日志为本批私有产物目录中的 `four-checks.log`。没有重跑旧全套、执行原脚本、客户端或 GPU，也没有网络或解密操作。

下一批新增独立 D13 核心状态与源事件接口，再由主分支接入实际碰撞、动作和资源。当前源数据完整性不能被当作玩法已完成或已经上传 TestFlight 的证据。
