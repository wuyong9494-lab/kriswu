# 孙学同胜利演出对吴庸的原始 Morph 绑定

本批补齐孙学同对吴庸的胜利 Morph 材料输入。它沿用已恢复的原胜利触发、遮罩、140 tick 过渡和宫殿投影阴影，独立绑定吴庸的实际身体和长枪，不借用刘晗的装备名称，也不修改任何人物 GLB 或贴图。

## 原始材料与参数

`prepare_erlang_source_morph.py` 核验完整已审目录中的精确男性路径，直接读取本地两个原件 bundle 的三个 Material 对象。目录和 bundle 全部核对 SHA-256；不按同名材质任选对象，因为同一衣甲 bundle 同时包含男性和女性材质。

| 实际材质 | 原对象 pathID | 原分类 | 胜利演出的参数来源 |
| --- | --- | --- | --- |
| `mat_arm__agl_44_base` | `-6011031156837743352` | `ARM_AGL_44` / Armor 2 | 原 lock1796 t12 的 Armor override |
| `mat_arm__agl_44_tie_base` | `-8673216404374002239` | 同一 Armor 2 的衣带 | 同一原 Armor override |
| `mat_wpn__agl_spear_01_01_base` | `4191842072599981697` | `WPN_IMPERIAL_SPEAR_01_01` / Weapon 3 | 该原长枪材质自己的默认值 |
| `Material.001` | 个人头部 | 明确的 actor-base 替换几何 | 源非 Weapon 的 base-model 分支适配 |
| `Personal_Neck_Bridge_Derived_Skin` | 新增个人颈桥 | 明确的 actor-base 适配几何 | 同一 base-model 分支适配 |

原 items 配置确认衣甲 ID 22045、长枪 ID 21056，分别使用 `Top100/arm__agl_44`、`Top100/wpn__agl_spear_01_01`。枚举来源同时确认 Helmet=1、Armor=2、Weapon=3。原 t12 只给 Helmet／Armor 设置参数；长枪不接受该覆盖。三个原材质序列化字段与实际 GLB 保存的原值逐项一致。

护甲和 actor-base 适配使用 Tile 0.2、EdgeSize 0.1、黑色起始边和 `[0,87,96]/255` 结束边。长枪保留原 Tile 约 0.1、EdgeSize 约 0.1，以及 `[0,26,146]/255` 到 `[0,237,244]/255` 的原边色。所有浮点保留原读取结果，不把其他目标的材质参数覆盖到长枪。

## 几何与运行边界

清单完整覆盖实际 5 个材质和 9 个 renderer。原个人头部仍是 59,878 个顶点，原 UV 不动；226 个顶点的 `Personal_Neck_Bridge` 仍保持无 UV。现有 Morph 的无 UV 特例只新增这枚已核颈桥材质名称，继续要求 actor-base 标识、无虚构 ItemType 和全部材质内容为常量。它复用原遮罩在 `(0,0)` 的真实 GPU 采样机制，不添加几何属性或替换贴图。

App loader 仅接受实际 62 段动作 GLB 身份，以及完整原根刺受控、Stun 三段契约。原刘晗分支保持其既有精确身份和材料检查。

运行集成使用独立 `erlangVictoryMorph`。World 根据实际参与角色的 ID 选择孙→刘或孙→吴清单，随后在原内部 guard 核验 SHA；同 ID 错误身份必须失败，不能靠跳过 Morph 变成成功。吴→刘没有孙学同参与，不安装这两种胜利绑定。最终 WeaponAssets／World 接线和发布身份由根整合批合入，本提交只修改两个 Morph 服务文件。

## 产物与验证

| 产物 | 字节数 | SHA-256 |
| --- | ---: | --- |
| `SF3_H17_WuMorph.json` | 8,232 | `f881e66bce80077ea017293d4dd990ba301f57c3165d9454e22636e507b3d9bb` |
| 原 `SF3_H17_MorphMask.texture` | 32,768 | `f5572cfbbe87bd2feb2e9aa93843815b0acdf1b71c0dd7ab584df24ce3ede514` |
| 吴庸实际人物 GLB | 18,590,120 | `debd14c7af756e52e14b920ce2db37fd77ddcfa26b5668fe552ac79e7a1303bd` |

Manifest 绑定的是 owner／target 的人物 GLB 身份，后续 profile 的战斗规则元数据变化不要求重读材料或重新生成贴图。公开来源与结果摘要见 `scripts/erlang_source_morph_receipt_20261115.json`；原始媒体和运行清单保留在私有候选目录。

只运行 3 项新增实际候选检查：原材料／五材质／九 renderer 与原遮罩闭合；篡改长枪原默认值被拒绝；删除原脸 UV 或将颈桥材质换成未知名字被拒绝。两处 App 源文件完成语法解析。此次没有原生运行或 GPU Morph 演出，因此不将离线核验表述为设备视觉通过。
