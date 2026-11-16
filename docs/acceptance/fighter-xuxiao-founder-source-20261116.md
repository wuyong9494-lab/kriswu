# 徐骁／嬴政套装：原版输入接续

基线 `73bff327c4ae45e4e66dd0a2c4c26e2035d28a99`。
角色名继续使用用户指定的 **徐骁**，沿用已完成的真实个人头部，不重复
下载 `徐.fbx` 或重新裁切、减面。新增
`scripts/prepare_xuxiao_founder_source.py` 已对现有原版配置实际运行。

## 本次完成的开发工作

将此前只有检索线索的 D20 资源身份，变成可供后续装配和规则绑定消费的
独立、可重现私有输入。准备器读取已解码且 SHA 固定的原始配置，完整保留：

- D20 的 6 档原始等级参数；不累计合并等级，也不把 `FakeValue` 展示字段
  直接当成已经证明的伤害公式。
- 4 个装备槽、5 个原始装备身份；两种御拳装备是同槽替代关系，不误算成
  五个同时穿戴的槽。
- 45 条 D20 动作记录、13 条御拳动作记录。全部 58 条用原生构造字段映射
  命名，并逐条逆向重建原数组，检查类型和浮点值均未丢失。
- 28 个 D20 专属规则分片、9 个御拳规则分片和 2 个相关共享分片。合计
  39 个分片、73 组规则、407 个触发器；保留全部六个触发器字段、顺序和
  107 条完整祖先门控路径，包含同一分片在不同路径中的重复引用。
- 按完整原始资源路径匹配的装备与动作清单；不因文件名相似、散列中含有
  `d20` 或另一角色使用同种武器就推断为已找到资源。

原版配置明确给出套装集合 `D_LEGENDARY_WPN_IMPERIAL_GLOVES_01`、集合 ID
`142` 和别名 `D20`。原版使用了两类动作复用：例如御拳暗影动作指向 D18
原始动作文件，D20 飞弹施法指向 H21 文件；准备器保留这些明确引用，不
把所有文件强行改名为 D20。

## 实际装备映射

| 槽位 | 原版装备 | 原版模型路径 |
| --- | --- | --- |
| 武器，选项 1 | `WPN_IMPERIAL_GLOVES_01` | `Top100/wpn__imperial_gloves_01_01` |
| 武器，选项 2 | `WPN_IMPERIAL_GLOVES_01a` | `Top100/wpn__imperial_gloves_01_01a` |
| 盔甲 | `ARM_AGL_49` | `Top100/arm__agl_49` |
| 头盔 | `HLM_AGL_49` | `Top100/helm__agl_49` |
| 远程 | `RNG_AGL_KNIVES_06` | `Top100/rng__agl_knives_01_06` |

[发行方 App Store 活动页](https://apps.apple.com/us/app/shadow-fight-3-rpg-fighting/id964827011?eventid=6811931931)
将该套装命名为 **Eternal Founder of the Empire**，并明确描述青铜傀儡军团。
[官方网站 Emporium](https://shadowfight3.com/emporium)也使用同一套装名称。
这里的 D20 装备关系来自实际原版集合／装备配置，不依靠社区命名猜测。

## 已查明的媒体缺口

现有 Android 1.45.3 资源目录共匹配到 48 个不同动作源文件中的 11 个
共享文件定位；这只证明目录中有位置，不证明本批次已读取、转换或装配
了这些文件。

当前目录未包含上表 5 类装备模型，也未包含另外 37 个动作文件：26 个
D20 专属文件和 11 个御拳文件。技能召唤物、完整材质、声音及特效的
动态资源仍需继续取得和绑定；“5 + 37”是装备／动作目录缺口，不能当成
完整发布包全部缺失文件的总数。

另外直接读取已下载官方 Android `19221` 包内的 `globalgamemanagers`，
对 1,127 条 ResourceManager 路径核对上述 D20 装备和动作路径，命中 0。
该成员通过 ZIP CRC，SHA-256 为
`ec4421cffcffc310025fcd0f96d9d54d83c38ad3c1c4b45d018944d2153f6574`。
此结果仅限该官方包的 ResourceManager，不推断所有外部目录或运行时缓存
均不存在资源。本批次没有重复官方客户端初始化失败工作流，也没有重复
下载旧包。

对用户提供的 iOS `1.46.1` IPA 也做了独立实际读取，不只检查旧 Android
目录。其 ResourceManager 同样有 1,127 条路径，目标装备／动作路径命中
0；另解析 `resources.assets` 内 1,539 个 GameObject、53 个 Mesh、124
个 Material、190 个 Texture2D 与 148 个 TextAsset 的原始名称，D20／
御拳／AGL49 名称命中 0、解析错误 0。该 123,797,852-byte 成员 SHA-256
为 `defdb00d1f6367552bd8e9c519f64dcde98fed5e9bd5e5258fa3c31387f8f013`。
共享骨架仍可读取，但没有取得 D20 装备自己的配置和模型时，不把共享
骨架本身当成已找到嬴政身体。上述范围也不等同于排除客户端以后从网络
取得的资源。

[小米官方分发页](https://app.mi.com/details?id=com.hahd.aygd3.mi)本次检索仍
列 `1.45.3`，更新时间 `2026-07-22`；没有把它包装成含有更晚 D20 内容的
新来源。

## 官方动态入口补查与准确恢复点

2026-11-16 06:04 UTC 另做了一次有界的官方入口刷新。实际读取
[官方发布脚本](https://shadowfight3.com/dist/index-page/js/main.js)，再按该
脚本执行无请求体的
`POST https://shadowfight3.com/rest/build/download/index`。两次响应均为
HTTP 200，正文合计仅 4,356 bytes：

| 输入 | 字节 | SHA-256 |
| --- | ---: | --- |
| 官方 `main.js` | 4,273 | `4946e572ddff447fd191a5e10d23c25a8f78c22797ce5262225cdd02595d728b` |
| 原站匿名 resolver 响应 | 83 | `572ea8def9fdb890f008cf722a0c4e7a1f433c41455ffa21f779f39289b01c0d` |

两项身份与已有记录相同，resolver 仍指向
`https://sf3assets.nekki.com/builds/apk/7/19221.apk`。这没有提供新的
客户端构建或动态媒体目录。本次没有下载该 APK、重复 IPA、重试原有
失败 balancer 参数，或启动 Android。针对官方 CDN 的精确公开搜索也
没有得到新的 metadata URL。

当前可继续恢复的准确入口有三种：

1. 原 balancer 的一次成功响应，提供真实 `bundles.url`，或
   `bundles.path` 与原 host/override，随后读取实际 metadata。
2. 已有的实际 metadata，提供 `platforms` 的平台到 Int64 版本映射和
   `baseUrl`，由原加载链形成正确的 platform-version 索引地址。
3. 普通客户端缓存中的 `bundles_<Int64>.bytes`、包含
   `bundlesConfig_<actual platform>.bytes` 的原归档，或已解码的真实
   `BConfigData`。取得后按原 protobuf `archives`、
   `paths: map<int64,string>` 精确匹配 D20 资源并恢复依赖闭包。

缺少的是实际目录响应或缓存，并没有新证据证明必须另行取得账号凭据
或签名。源加载方法与索引结构已有记录，不能用套装名称、APK 构建号或
旧 bundle 的散列猜出 D20 的真实下载地址。上述结论仅覆盖本次查到的
入口，不代表远端 D20 动态资源不存在。

本次补查独立保存于 `xuxiao-dynamic-source-audit-v1`：

| 私有记录 | 字节 | SHA-256 |
| --- | ---: | --- |
| `receipt-private.json` | 1,542 | `7f275d25c096abdf3d16011a54afa29395203f0c912f72f817318e3fbfd30449` |
| `resume-points-private.json` | 11,741 | `df968197667a16a44f01f22ca4442a52adfe4ccde4a873f8774503b0fd95f3ab` |

第二份记录保存五个装备选择、37 个缺少目录映射的动作原名，以及上述
恢复入口。它是下一步输入清单，不是已取得媒体或实现完成的证明。
原 `xuxiao-founder-source-v2` 的文件、源身份与准备回执保持不变。

## 输入与输出身份

| 项目 | SHA-256 |
| --- | --- |
| 现有徐骁真实头部 GLB，20,354,880 bytes | `c2242893775f0ba0fb21e88d830419ff41afa117dd22f0aae2ea577e25d37ee4` |
| 原版已解码 prod 配置 | `165f5b1483909c461fabc86c591efd01ebb4915cc34ef7bf2579d52c94b35950` |
| 原版已解码 splits 配置 | `02bcd31d5b0f3ed992ca1972f2c6da5f59e6495fe3880fec45f8b073fbaa0e7a` |
| 原生动作字段映射 | `f8687443bcf2da87ff3c9f5d7c2059cb2dbe851a9a33c776655477e750b85111` |
| 原始 Android 资源目录 | `2c01276ca8c58ea32d79bfe481e37adc6696bc4c5a6140f6f6842ca262d07055` |
| 本次私有源准备回执 | `d5070f929aab65f5b9c67de1e5229a955f58d94b26493e05d5407d554787b9c1` |

私有输出目录为 `xuxiao-founder-source-v2`，包含装备／等级、动作、触发器、
资源缺口清单以及可逐字节复核的原始成员。原始模型、配置、资源数据不
加入公开仓库；本提交只包含准备代码、验证代码与交接身份。

## 验证与下一步

针对实际私有输入的 **6 项 Python 检查全部通过，0 失败，0 跳过**：
输出字节身份、装备替代关系与原始等级、58 条动作逐字段反向还原、407
个触发器及祖先门控、未取得媒体的状态、错误配置／缺失门控的拒绝。
复跑入口为 `test_prepare_xuxiao_founder_source.py`，使用
`FIGHTER_XUXIAO_SOURCE_ROOT` 指向上述私有输出目录。

下一步使用实际 D20 动态资源补齐身体、双武器形态、头盔、远程及专属
动作；然后进行徐骁头部的比例／颈部与骨骼装配、技能运行时、选角、
联机及原生资源验收。当前结果是开发输入准备，不是完整嬴政角色、
iOS 编译、模拟器画面、真机性能或 TestFlight 发布完成证据。
