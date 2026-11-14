# 盘古 D19 原始索引与资源恢复记录（2026-11-14）

## 本轮实际结果

本轮增加并实际执行了原始容器恢复工具：[`recover_pangu_source_index.py`](../scripts/recover_pangu_source_index.py)，配套 [`24 项 Python 回归`](../scripts/test_recover_pangu_source_index.py)全部通过。工具可以从已有 Unity 容器、按内容头识别的 ZIP 成员、TextAsset、ResourceManager 和已经解密的私有源归档中定位原始 `BConfigData`，精确关联 D19 目标资源及依赖，并把实际命中的原始容器保存到新的私有目录。

**本轮新增取得的 D19 专属动作文件为 0，专属装备资源条目为 0。** 实际检查范围内仍未取得有效 `BConfigData` 或成功 balancer 响应中的 metadata 地址。盘古独立模型、长柄斧绑定与 11 个专属动作文件继续标为缺少原始资源。已有普通斧动作、刘泉纬双锤、配置中的 D19 名称、17 个共享动作别名均不能替代这些资源。此记录不改变游戏运行时绑定或角色完成状态。

源身份继续使用已经核实的两份清单，避免新增猜测：

- [专属动作清单](../scripts/pangu_source_motion_inventory_20261114.json)：12 个未恢复别名对应 11 个不同文件；其中大小岩石攻击共用 `D19_forward_rock.bin`。
- [装备身份清单](../scripts/pangu_source_identity_20261114.json)：5 个专属装备条目，即两种长柄斧外观、铠甲、头盔和远程武器。它们仍没有已验证的原模型路径命中。

| 条目 | 原始 ID | 原模型路径 |
| --- | --- | --- |
| WPN_TWOHANDEDAXE_02 | 21094 | `Top100/wpn__twohanded_axe_01_02` |
| WPN_TWOHANDEDAXE_02a | 21095 | `Top100/wpn__twohanded_axe_01_02a` |
| ARM_AGL_48 | 22064 | `Top100/arm__agl_48` |
| HLM_AGL_48 | 23062 | `Top100/helm__agl_48` |
| RNG_PILUM_08 | 24046 | `Top100/rng__pilum_01_08` |

## 真正执行的取材范围

每行是一次不同覆盖范围的本地读取；存在重叠，不应相加后声称是唯一文件总量。没有重新下载客户端、重转 mesh、打包或上传资源版本。

| 检查 | 实际覆盖 | 结果与边界 |
| --- | --- | --- |
| 原始容器与 TextAsset 内容扫描 | 380,734,189 bytes；164 个可解析 Unity 容器；2,918 个按类型读取的 TextAsset；已有 132 个 bundle、目标资源缓存、RuStore 已缓存 `.assets` 和完整 IPA 的 `.assets` | 原始索引及 D19 容器、动作 TextAsset 候选均为 0。8 个旧范围缓存片段无法作为完整 Unity 容器解压，明确保留错误，未计为有效完整 bundle。 |
| ZIP 包装与已解密源归档扫描 | 174,623,964 bytes 输入；19 个 Unity 容器；618 个 TextAsset；展开 6,716 个 ZIP 成员，累计检查 111,576,748 bytes 的成员内容 | 覆盖两份已成功解密的源归档及其 battle triggers、quests、animation settings 三个 split；没有新解密。索引及 D19 候选仍为 0，解析错误为 0。 |
| 无扩展名成员与 ResourceManager 补查 | 完整 IPA 按成员内容头检查；复用 20 个已有容器 SHA；新增解析 7 个序列化容器，读取 1,127 条 ResourceManager 路径 | 修正只按 `.assets` 后缀检查会漏掉 `globalgamemanagers` 的问题。D19 路径及索引仍为 0，解析错误为 0。超出媒体扫描范围的原生可执行文件明确排除。 |

第一轮 8 个错误都来自 `*-subset-range-cache` 中的 256-byte 分段缓存。它们是部分下载片段，无法独立代替整个 Unity bundle。失败类型为 `LZ4BlockError`；本轮没有重新请求这些片段或将其标为通过。

本地发现的完整客户端为已提供的 IPA。没有完整 APK、APKS、XAPK 或 OBB 文件；Android 证据限于现存范围缓存、132 个保存的 bundle 以及旧 catalog 的检查结果。**不能据此声称所有 Android base/split 或运行后动态资源都已扫描。** 未提供的设备缓存和远端资源不属于本轮本地否定结论。

## 源码恢复出的真实加载链

以下方法来自提供的原始客户端静态读取，没有执行原客户端。原生镜像 SHA-256：

`7c192647b0e035bd246c135a59c597ee3910d50fc4ed128abe402da39a62a55b`

### Balancer 请求与响应

方法 `1606` 构造 GET，请求参数为配置 `ConfigVersion.Full` 的 `fv`、`Random.Range(0, 100000)` 的十进制 `rand`，以及原平台映射的 `p`。提供包的配置完整版本仍是 `1.46.0.16.16733-prod`。可选 `w` 依赖客户端已经知道的 world，不能凭空填写。已核实标准 iOS 分支使用 `iOS`。本次没有发现足以改变旧失败请求的新参数、编码或必需应用请求头。

成功响应经 `1608 → 0x3d8d644 → BanzaiWebRequest.get_Text (170851) → JsonConvert.DeserializeObject (129428)` 解析为 `BalancerSettings`。这个阶段没有额外 base64、AES 或 ZIP 包装。旧失败响应缓存是 26-byte 的 HTTP 400 纯文本，并非误解包的成功 JSON；没有重复发送这些请求。

随后需要响应里的真实 `bundles.path` / `bundles.url`，再读取实际 metadata：`platforms` 的 Int64 版本映射与 `baseUrl`。方法 `39985` 才据此生成 `baseUrl/platform-version.zip`。静态 CDN 根地址与 `BundlesPath` 不能替代这一实际 metadata。

### 本地缓存、归档包装与实际索引成员

`39975 / 39976 / 39977` 枚举并解析 `bundles_<Int64>.bytes` 文件名；它们本身不解码索引。`39968 → 181725` 读取缓存文件的完整 bytes，再包装为数组片段。

实际资源 provider 的链为：

`174857 → 174852 → 174842 → 174860 → Banzai.Zip.183922 → 索引成员 → 161765 → MessageParser → Google.Protobuf.MessageExtensions.MergeFrom (138686)`

`174860` 包含原始归档变换及加密处理，之后 `183922` 从 ZIP 取成员。`40011 / 40010` 明确构造 `bundlesConfig_` + `180354` 给出的运行平台名 + `.bytes`。这是归档内部成员名称，不能直接拼接到 CDN 根目录当成已确认下载 URL。成员取得以后，调用链直接交给 protobuf 解析，没有再发现成员层 XOR 或 gzip 变换。

因此，单独对 raw TextAsset 做 protobuf 解析后返回空，不能推出客户端不存在索引。本轮已经补做已知 ZIP 包装、已解密结果及无扩展名容器检查。

### 已有加密结果如何复用

IPA 的 `archive` 外层归档只有两份 `.zip.enc` 与两个校验成员。两份加密成员的 SHA 均精确匹配此前成功解密 receipt，随后复用了现存明文 ZIP：

| 已有源归档 | 明文 bytes | 已复核明文 SHA-256 |
| --- | ---: | --- |
| `1.46.0.16.16733-prod-decoded-private.zip` | 2,751,235 | `165f5b1483909c461fabc86c591efd01ebb4915cc34ef7bf2579d52c94b35950` |
| `1.46.0.16.16733-prod_splits-decoded-private.zip` | 17,325,877 | `02bcd31d5b0f3ed992ca1972f2c6da5f59e6495fe3880fec45f8b073fbaa0e7a` |

这些已解密成员中未命中原始索引；本轮没有定位到另一份尚未处理的加密 index 容器。这个结论与“所有可能的加密缓存都已排除”不同，后者没有证据支持。密钥、原始媒体、明文源归档和原生指令记录均未提交到仓库。

## 原 protobuf schema 与恢复工具行为

使用原客户端恢复的 591-byte descriptor，SHA-256 为：

`f6498173aceffbf75ce671493fed3d6a97525ec73e60847fe34809da5d9d4be5`

- `BConfigData.archives` 是 `map<string, BArchiveData>`。
- **`BConfigData.paths` 是 `map<int64, string>`**，并非 path 字符串到 bundle 的字典。工具保留有符号 Int64，不猜测 path ID 对 archive 的归属。
- `BArchiveData` 的 `assets`、`name`、`dependencies` 用于精确匹配与依赖闭包；`realHash` 与 `crc` 保持原始不透明字段，不猜测哈希算法。
- 专属动作按精确路径、或明确标为尚待路径核验的专属 TextAsset 名称定位；旧双锤、普通斧和近似名称不能命中。
- 只处理有真实格式头的 raw protobuf、JSON、ZIP、gzip 或 Unity 序列化数据；ZIP 的压缩成员由标准 ZIP 读取并校验。gzip 是工具支持的输入形式，不代表已证实原客户端在这个索引阶段使用 gzip。
- 有输入尺寸、解压总量、嵌套层数、成员数、protobuf 字段数等边界；重复哈希复用、敏感名称、加密 ZIP 成员、符号链接与错误单独记录。
- 候选容器保存到全新的仓库外目录，目录权限 `0700`、文件 `0600`，不覆写既有资源。候选的 `modelComplete`、`motionDecoded`、`runtimeInstalled` 初始均为 false；命中候选不等于角色完成。

已有实际索引或已经解密的原归档可以直接进入同一恢复路径，例如：

```sh
python scripts/recover_pangu_source_index.py \
  --descriptor "$PRIVATE_SOURCE_DESCRIPTOR" \
  --index "$PRIVATE_DECODED_SOURCE_ARCHIVE" \
  --cache-root "$PRIVATE_ORIGINAL_BUNDLE_CACHE" \
  --output "$NEW_PRIVATE_RECOVERY_DIRECTORY"
```

工具不会请求网络、寻找凭据、自动解密、运行游戏、转换模型、安装 release 或触发 Actions。成功 balancer metadata 或实际设备缓存仍是取得动态 D19 原资源的下一项必要输入；已有成功测试和资源版本不需要重跑或重复上传。

## 本轮公开检索的排除记录

公开检索仍未提供能够核验 D19 的真实资源索引；保留以下新检索入口，避免重复下载无关包：

- [官方 App Store 产品页](https://apps.apple.com/cn/app/id6468901926)与 [TapTap 官方发行页](https://www.taptap.cn/app/430024)提供产品、版本说明，没有给出动态 bundle 的原始索引。
- [公开 1.46.2 APK 页面](https://www.apkmirror.com/apk/nekki/shadow-fight-3/shadow-fight-3-rpg-fighting-1-46-2-release/shadow-fight-3-rpg-fighting-1-46-2-android-apk-download/)只有客户端分发信息，不能证明 D19 动态资源包含其中，未重复下载。
- 新发现的 [shadowfight-restored 仓库](https://github.com/gitnurdun/shadowfight-restored)在 README 明确属于 Shadow Fight 2 还原，未下载其大 APK。
- [旧论坛 bundles 帖](https://4pda.to/forum/index.php?showtopic=835611&st=8800)的搜索索引指向 2024 年的归档；原页面返回 403。未绕过访问限制，也没有将旧归档当成盘古资源来源。

## 可复核结果与待完成项

最终脚本 SHA-256：`0f5a2abb3e5d48983855d7b3bf930359b3e69a006a0d5ddbc89b5fdc0e534040`。

测试文件 SHA-256：`14ec08903ca8a3c5dd5ff2d9a41394f80657f3653e71f2ae8e7f41e7e13f425d`。

对应最终源码的 `python -m unittest test_recover_pangu_source_index -q` 执行 24 项、0 failures、0 errors，约 0.008 秒。测试涵盖 schema、负 Int64、损坏/溢出输入、名称精确匹配、依赖闭包、metadata 参数、ZIP 包装、无扩展名内容头、ResourceManager、私有输出权限和错误保留。**这是本地 Python 恢复工具验证，不是 iOS 原生测试、模拟器或真机验收。**

汇总私有 receipt 的 SHA-256：`08dce64b3a9aae0852fa300201101c6af5886e0f4212e2e8b3721d6ccc2caca4`。它逐项保存输入、三个扫描结果的 SHA、原生方法取证记录、错误/排除项与公开检索结论；原始资产与密钥未进入公共文档。

尚待取得和执行：实际成功的动态索引或对应设备缓存；11 个 D19 专属动作及上述 5 个装备条目的原资源；解码后的骨架/武器/动作事件绑定；角色碰撞、伤害、连招、声画与资源生命周期回归；模拟器及 iPhone 17 Pro Max 真机证据。本轮没有伪造其中任何完成项。
