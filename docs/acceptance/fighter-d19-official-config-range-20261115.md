# D19 官方 APK 三个配置成员的精确取材（2026-11-15）

**三个此前未读的配置成员已取得并完成 ZIP 校验与解析，但没有得到新的 D19 资源地址或动态索引。** 本记录覆盖先读取的两个配置及随后追加的 InternalSettings，不代表整个 APK 没有 D19，也不能证明官方客户端启动一定能够取得缺失资源。机器可读记录见[同名 JSON](fighter-d19-official-config-range-20261115.json)。

## 来源与成员绑定

沿用[前次官方取材](../fighter-pangu-official-remote-index-20261115.md)保存的 [官方下载 resolver](https://shadowfight3.com/rest/build/download/index) POST 结果，固定其实际返回的 [19221.apk](https://sf3assets.nekki.com/builds/apk/7/19221.apk)：`com.nekki.shadowfight3`、版本 `1.46.0`、versionCode `19221`、总长 **263,891,547 B**。本次没有重新请求 resolver 或 HEAD。

已缓存的 3,119 项 ZIP 中央目录与该包 `assets/bin/Data/globalgamemanagers` 中的 ResourceManager 经 SHA-256 复核后，确认下列绑定。三个入口补充了前次关键词筛选结果；此前列出的相关路径不是 ResourceManager 全部配置路径。

| ResourceManager 路径 | fileID / pathID | APK 成员（位于 `assets/bin/Data/`） | 压缩 B / 展开 B | CRC32 |
| --- | --- | --- | ---: | --- |
| `configs/configsources` | `181 / 1` | `d03d6c4b3185d694db6bb7fd329584af` | 7,312 / 9,640 | `2be10aa0` |
| `configs/localserversettings` | `184 / 1` | `c687d59965f5f134dbf5bfd4f6ab0742` | 335 / 428 | `31334ee1` |
| `configs/internalsettings` | `182 / 1` | `bf71e3d497ac14d03addd9fc37ae7dc9` | 11,927 / 15,744 | `306a7956` |

## 实际读取与校验

首两个成员请求发生于 **2026-11-15 00:28:56–00:29:29 UTC（北京时间 08:28:56–08:29:29）**，为 **6 次 / 7,803 B**。追加 InternalSettings 的请求发生于 **00:40:25–00:40:43 UTC（北京时间 08:40:25–08:40:43）**，为 **3 次 / 12,005 B**。

每个成员只读取 30 B 局部头、48 B 文件名及完整压缩正文。三个成员合计 **9 个新 Range 请求、19,808 B**：压缩正文 **19,574 B**，局部头及文件名 **234 B**。

| 成员 | 局部头：起点 + B | 文件名：起点 + B | 压缩正文：起点 + B |
| --- | --- | --- | --- |
| ConfigSources | `109965561 + 30` | `109965591 + 48` | `109965639 + 7312` |
| LocalServerSettings | `109724643 + 30` | `109724673 + 48` | `109724721 + 335` |
| InternalSettings | `109598063 + 30` | `109598093 + 48` | `109598141 + 11927` |

九次响应均为 HTTP **206**，Content-Range、Content-Length、总包长度和既有 ETag 一致。新范围与原 17 次范围均不重叠，追加的第三成员也未重叠前两个成员；没有重定向、重试或整包读取。三个成员的局部头字段、名称、Deflate 结束边界、展开长度及 CRC32 均匹配中央目录。

APK Range 统计为旧 **17 次 / 648,667 B**，首两个成员完成后为 **23 次 / 656,470 B**，再追加 **3 次 / 12,005 B**，现累计 **26 次 / 668,475 B**。这是按请求累加的实收响应正文，不是 APK 唯一覆盖字节数，也不含其他历史页面、resolver 或 bootstrap 请求。未取得完整 APK SHA-256，未执行 APK 签名验证。

## 非敏感结果与边界

- **ConfigSources：39 条配置映射**，与已有 RuStore 解码结果逐项语义一致，无新增、删除或修改的映射。字段提供配置相对路径，没有直接远端资源索引地址。
- **LocalServerSettings：`defaultBalancer = prod`、`forceBalancer = prod`**，另有 5 项日志命令配置。`prod` 是环境选择器，不是主机名或 URL。
- **InternalSettings：`ServerSettings.Servers.prod`** 的主地址为 `https://sf3lb.nekki.com`（默认 443），备用地址为 `https://sfxlbalt.nekki.com:9043`。二者均无 path、query、fragment，且 host/port 组合均已在既有回执中出现。这个成员的 CRC/长度与旧 RuStore 不同；本次仅比较允许的生产地址投影，没有声称整个配置语义相同。
- 首两个成员没有直接 D19/Pangu 配置字段；追加第三成员确认了实际 `prod` 地址映射，但没有发现新端点或动态资源索引。本次未请求主、备地址，没有重试先前失败的 bootstrap。备用地址的历史 HTTP 400 属于旧 iOS 配置，不能算作当前官方 Android 参数组合的执行结果。

首版安全投影的 `sameHostAsPrevious=false` 来自双地址数组与单个旧地址的比较，**不能解释为主地址变化**。独立比较回执随后按主、备 host/port 分别核对，确认两者均为已知；首版与后续比较回执分别保留，没有覆盖初始记录。

因此，这三个小配置入口没有提供取得 D19 动态索引的捷径；真实启动响应或另一条有来源依据的索引仍待取得。结果仅属于**实际来源读取与静态解析证据**，原生测试、模拟器执行和真机验收均未在本步骤执行。

本次复用既有原资源解码器，密钥只用于内存解码；公共文件仅含成员元数据、校验摘要和非敏感结论，不包含完整配置正文、密钥或凭据。未下载完整 APK、安装或启动 Android 环境、接受 SDK 条款。

## 证据摘要

| 输入或回执 | SHA-256 |
| --- | --- |
| 官方 resolver 响应 | `572ea8def9fdb890f008cf722a0c4e7a1f433c41455ffa21f779f39289b01c0d` |
| ZIP 中央目录 | `abaebf457c31bd2bb5d2231225098afef0a9a3a41a45a0e28930dcb68539b583` |
| 官方包 globalgamemanagers | `ec4421cffcffc310025fcd0f96d9d54d83c38ad3c1c4b45d018944d2153f6574` |
| 两成员读取与解析回执 | `7df9f539074986ed323d92d8df843bc59e0c704571b34c6bfe7af25a84061c0a` |
| 非敏感语义比较回执 | `db80e0310932c48790d74a2a9d651a5e7aec980195a2b7c4ace7e1597b9cc7a7` |
| InternalSettings 完整容器 | `5012e509fb9a262049f86c96853a0b1abca94dbcd8af7b2faa096fc4dd6a68d1` |
| InternalSettings 读取与解析回执 | `e93a03bbcaad373e8865a571ee25c17b6b98ca092954ac791f9e58ea17907058` |
| InternalSettings 首版安全投影 | `70c56be13b2072ef5a9709111af19f46260c2b3639f6b8ac9970e554827ebc4c` |
| InternalSettings 独立比较回执 | `a1a5fbfe2130e71ffd16c141532fdb48e733a4a106305ddef7c1817375c21485` |
