# D19 官方远端索引取材补查（2026-11-15 批次）

## 结果与边界

本轮找到并实际走通一条此前未检查的官方分发路径：**官方首页 → 原站 JavaScript → 匿名下载 resolver → 官方 APK → ZIP 中央目录 → 实际版本、启动归档前缀与三个新增读取成员**。新增工具为 [`recover_pangu_remote_index_20261115.py`](../scripts/recover_pangu_remote_index_20261115.py)。这条路径带来了新的可复核原始输入，不复用以前 HTTP 400 的相同版本参数，也没有下载整包。

**仍未取得 D19 的 11 个专属动作文件、12 个动作别名或 5 类装备。** 新获取的两个额外 Unity 成员实际属于性能测试配置；新构建的 ResourceManager 没有 D19 路径或实际 bundle 索引。依据这个包恢复出的真实配置版本执行的一次 balancer 请求也没有返回 metadata。现有双锤模型、普通斧动作及共享动作身份保持原样。

本批次的远端实际采样日期为 **北京时间 2026-11-15**（UTC 2026-11-14）；原始回执保留 UTC 时间，文件名使用北京时间开发批次。没有将这些读取结果标为原生测试、模拟器或真机验收。

## 新的官方入口与实际请求

[Shadow Fight 3 官方首页](https://shadowfight3.com/)的 APK 按钮调用 [`main.js`](https://shadowfight3.com/dist/index-page/js/main.js) 中的 `window.onDownloadLinkApkClick`。原站函数使用无请求体的 `POST /rest/build/download/index`，并从 `url`、`data.url` 或 `data.data.url` 取下载地址。因此这次请求路径来自真实发布代码，没有拼接猜测 APK 文件名或索引版本。

| 入口或证据 | 本轮实际读取结果 |
| --- | --- |
| 官方首页 | HTTP 200，8,206 bytes；SHA-256 `6644e47f1422a662b827c32c92f122963ab8c48ffbdc6f4d1cd0ef818fda76be` |
| 官方 `main.js` | HTTP 200，4,273 bytes；SHA-256 `4946e572ddff447fd191a5e10d23c25a8f78c22797ce5262225cdd02595d728b` |
| 原站 `ab-test.js` | HTTP 200，2,546 bytes；检查未发现另一资源索引入口 |
| [官方下载 resolver](https://shadowfight3.com/rest/build/download/index) | 按原站代码执行 POST，HTTP 200，83-byte JSON；SHA-256 `572ea8def9fdb890f008cf722a0c4e7a1f433c41455ffa21f779f39289b01c0d` |
| Resolver 返回的实际 APK | `https://sf3assets.nekki.com/builds/apk/7/19221.apk`；HEAD 200，声明 263,891,547 bytes，支持 byte ranges |
| APK Last-Modified | `2026-10-08 14:05:43 GMT`；官网本次仍指向此构建，不能把官网按钮称为已经取得最新动态游戏资源 |

先保存上述响应，再由新工具验证固定 resolver SHA、实际 APK URL 和 HEAD 长度。后续仅发送原包的精确 Range GET，要求 HTTP 206、完全匹配的 `Content-Range` 与 `Content-Length`，禁止自动重定向；若服务器返回整包 200，立即关闭响应而不读取整包正文。

## 得到的原包信息

| 项目 | 已验证值 |
| --- | --- |
| APK application ID | `com.nekki.shadowfight3` |
| AndroidManifest 版本 | `1.46.0`，versionCode `19221` |
| AndroidManifest | 完整成员读取、解压和 ZIP CRC 校验通过，76,692 bytes；SHA-256 `4b009c7cfa57dace3c4affec9b6d8757bdadc5d3d2d90a47d3dd97b1af705171` |
| ZIP 中央目录 | 3,119 项，293,445 bytes；SHA-256 `abaebf457c31bd2bb5d2231225098afef0a9a3a41a45a0e28930dcb68539b583` |
| 启动归档中的实际成员名 | `1.46.0.0.16728-prod_splits.zip.enc` |
| 启动归档读取范围 | 只读取/展开前缀，得到 16,384 bytes；没有下载完整加密归档，没有验证整个归档 CRC，没有访问密钥或解密 |

该构建与已有 RuStore `19226`、官方中国版 `907` 的目录分别进行了对比。837 个 `assets/bin/Data/` 成员中，563 个与 RuStore 的中央目录 CRC 和长度相同；此指标用于避免重复取材，**不是完整 SHA-256 相等证明**。没有因“名称或长度相同”就把内容当成已验证。

相对 RuStore，多出的两个 Unity 成员很小，因此只读取了它们及该构建的 `globalgamemanagers`。其他发生变化的成员没有整批下载，也没有重新扫描前轮 380 MB 的旧缓存。

| 新读取成员 | 原始 bytes | 实际内容与结论 |
| --- | ---: | --- |
| `830560d47780e32479e5090e928c0f1d` | 5,952 | 一个 TextAsset：`PerformanceTestRunInfo`；不是 D19 或 bundle 索引 |
| `d5fec129c21aa1947923a8f029f22e89` | 204 | 一个 TextAsset：`PerformanceTestRunSettings`；不是 D19 或 bundle 索引 |
| `globalgamemanagers` | 688,404 | 读取 ResourceManager 的 1,127 条路径；目标 D19 路径、实际 BConfigData、metadata 命中均为 0 |

三个成员都通过完整 ZIP CRC 校验。按原容器类型解析共 **694,560 bytes**，两个 TextAsset、一个 ResourceManager，解析错误 **0**。仅有的相关配置路径仍为 `configs/archive` 与 `configs/bundlesspecialsconfig`，不是可直接请求的远端 index URL。

本轮共读取 **648,667 bytes 的 APK ranges**，17 个互不重复的范围。包括官网页面、脚本、resolver 和下述一次 balancer 在内，直接取材 HTTP 共 23 次，正文累计 **663,801 bytes**；这一统计不包括搜索服务页面检索。没有下载 263 MB 整包、重新转换模型或重复获取旧媒体。

## 新版本 balancer 请求与原生回退结论

前轮已经分别试过真实 iOS 配置 `1.46.0.16.16733-prod` 和 RuStore Android 配置 `1.46.0.11.16732-prod`。本轮从上述官方构建第一次恢复出不同的 `1.46.0.0.16728-prod`，因此它提供了新的真实参数依据。

按照已恢复的 native1606 请求结构、现有镜像可见的标准 Android 平台分支及缓存 Android metadata，只执行了一次新的请求：`fv=1.46.0.0.16728-prod`、`p=Android`，合法范围内的随机字段。实际 Android SKU 的原生发送未执行，详见下表。结果仍为 HTTP **400**、**26 bytes**，正文 SHA-256 `ca71485324997c2c4cbf507b6e9cd20e1e8d1c7a644f87f5c993216cdafa56b0`；没有 JSON，更没有 `bundles.path`、`bundles.url` 或 metadata。响应 `Server` 为 `envoy`，现有证据不足以认定错误具体来自原站还是中间网络层，也不能据此断言是认证失败。

没有通过改变随机数或重复添加请求头继续重试；没有更改网络配置、代理或环境。

此外，复核原客户端已有反汇编可以明确排除“构造函数中另有固定默认 metadata 地址”的这条推测：

- `172863`：`bundles` 对象为空时直接返回 null。
- `172865`：使用实际 `bundles.url`；或将实际 `bundles.path` 与已提供的 override/host 组合。没有生成缺失的 path。
- `172867`：构造函数初始化空列表，没有设置固定 metadata URL。
- `15456 / 15460`：对传入 host 数组进行选择/轮换；不会制造另一个原生内置索引端点。

这些方法使用的原生镜像身份继续是 `7c192647b0e035bd246c135a59c597ee3910d50fc4ed128abe402da39a62a55b`。没有运行原客户端或读取密钥。

### 完整请求链补核

新旧请求的非敏感错误正文逐字节相同，具体是 `Failure: 400 Bad Request\r\n`，不是一个被误解包的成功响应。追加核对覆盖 14 份已有原生方法记录，没有增加网络请求。

| 请求部分 | 静态证据与当前覆盖 |
| --- | --- |
| HTTP method | `1606 → 170836 → 170879`：`wwwForm=null`，选择 `UnityWebRequest.Get`；已覆盖 GET |
| 请求体与 Content-Type | 没有表单或请求体；该调用没有设置应用层 Content-Type；未发现 JSON、protobuf、签名数据或加密 wrapper 需要加入请求体 |
| 必需 query | `fv=ConfigVersion.Full`、`rand=Random.Range(0,100000)` 的十进制值、`p=平台选择`；已按实际源值覆盖 |
| 条件 query | `w` 仅在已有 world option 非空时加入。没有已知 world 时，原生也允许省略；不猜 world 值 |
| Query 编码 | `170990 / 170993 / 170995` 构造 `?`、`key=value`、`&` 拼接；目前 ASCII 参数不需要另一层编码 |
| 空根路径 | 离线检查 urllib Request，实际 selector 为 `/?fv=...`。写作 `https://host?query` 不会在本工具中发出缺少 `/` 的请求行，排除此猜测，未进行重复请求 |
| 应用显式 headers | `170836` 的 settings headers 为 null；`170873` 保存，`170884` 只遍历已有 dictionary。未发现遗漏的 Authorization、签名头或其他固定应用请求头 |
| 最终发送与响应包装 | `170883 / 170891` 进入 `UnityWebRequest.SendWebRequest`；成功响应直接 `get_Text → Newtonsoft.Json.DeserializeObject<BalancerSettings>` |
| iOS SKU | 已有包 ID 为 `com.nekki.shadowfight3`；提供的原生镜像中标准分支为 `iOS` |
| Android SKU | 已有 Android metadata 真实字面量为 `Android`、`AndroidChina`、`AndroidEGS`、`AndroidVietnam`，未发现 `AndroidRuStore`。官网 APK 及 RuStore application ID 均为 `com.nekki.shadowfight3`，但没有本地 Android 原生镜像/实际启动来证明该 SKU 最终执行分支，不能宣称实测完全相同 |
| Unity 自动传输行为 | 原生自动 User-Agent、cookie 状态、实际 TLS/HTTP 协商没有在运行中的客户端观测；Python 请求不能据此称为与 Unity 每一个线上字节都完全一致 |

Android metadata SHA-256 为 `b6070729e09bf5a6bfe49eea9587847fa4756e12fa357b7d63f3a8d2f97416fc`，复用了先前已完整 CRC 校验的本地输入，没有再次下载。

**结论是“已复原应用定义的 method/query/body/显式 headers，未发现新的明确遗漏”，而不是“已经验证真实客户端全部 wire 行为”。** 没有新的确证参数，因此本轮追加核对之后没有再发 balancer 请求。

### 本地 Linux 开发容器的 Android 运行能力盘点

只读检查 PATH、常用 SDK/运行时目录、workspace 中相应可执行文件、Android SDK/AVD 环境变量与设备节点，结果如下：

- `adb`、`emulator`、`avdmanager`、`sdkmanager` 均未发现。
- `qemu-system-x86_64`、`qemu-system-aarch64`、Waydroid、Anbox、Docker、Podman 均未发现。
- `/opt/android-sdk`、`/opt/android`、`/usr/lib/android-sdk`、`/opt/google/android-emulator`、`/usr/share/waydroid` 均不存在；没有 Android SDK/AVD 变量。
- `/dev/kvm`、`/dev/binder`、`/dev/binderfs` 均不存在。

因此当前没有已就绪的 Android 环境可直接运行官方客户端并读取其自行获得的索引。本次没有安装软件、接受 SDK 许可、创建账号或修改环境。

## 新工具的实际验证

脚本最终 SHA-256：`a661b38c7d8f1444a9149f12bb18855fbff9b596a30a6097246a7bb2e073f8d3`。

该脚本已完成上述真实远端读取。随后对最终源码执行 **10 项离线定向检查，0 failures，0.012 秒**，没有再次发送网络请求：中央目录读取；重复/路径穿越/截断/条目计数拒绝；复用实际缓存 AXML 解析版本；HTTP 200 整包拒读并关闭连接；错误 Content-Range 拒读；准确范围只保存一次；总传输上限；已有输出在输入读取前拒绝；未经观察的 APK URL 拒绝。

脚本使用标准库，不安装依赖，不搜集凭据。完整请求/目录/成员/解析回执保存于私有取材目录。公共仓库中只有这份新脚本和本记录，原 APK 范围、TextAsset、归档前缀以及其他原始资源没有提交。

## 当前真实阻塞与自主推进方向

新的官方取材路径已经执行到实际原包内容，仍没有得到可继续下载 D19 的索引。不能从静态 CDN 根目录、构建号、模型名称或一个旧动作的 hash 推导出缺失 D19 文件的真实地址。

剩余技术瓶颈集中在**取得正确客户端平台与传输路径上的一次成功启动目录响应**。应用层请求没有发现新的明确遗漏，现有环境也无法直接执行官方 Android 客户端去观测自动请求和动态缓存。原始响应中真实 `bundles.path/url`、metadata 的 `platforms/baseUrl` 或客户端自行缓存的实际索引，仍未恢复。

下一步开发方向是建立可运行官方客户端并记录其自身启动结果的技术路径，或从另一条有发布方源证据的公开入口恢复同一索引；此处不要求用户另行提供他已经说明没有的盘古资源。当前任务授权仅限运行能力盘点，因此本轮没有把未安装运行时写成已经能够启动。

取得真实索引后，前轮 [`recover_pangu_source_index.py`](../scripts/recover_pangu_source_index.py) 已具备按原 protobuf `archives` 和 `paths: map<int64,string>` 精确匹配 11 个文件／5 类装备及依赖闭包的能力。本轮不宣称所有公开来源、所有 APK 成员或全部可能缓存均已排除，也不把静态资源获取能力写作盘古角色已完成。

本轮汇总私有 receipt SHA-256：`1d995794c56ea18450971424d6c91b34fe4ebf19d09be89a398c47d8540ddeed`。

请求链与运行能力补核 receipt SHA-256：`8c8843077daf75ba84e170d6de198fa87140861173cfc8c1b8ba091d1d144624`。

## 后续独立 CI 证据

同批次新增的 [官方 bootstrap CI 报告](fighter-pangu-bootstrap-ci-625b3285-20261115.md)记录了独立 runner 的真实 HTTP 400；[Android 前置检查](acceptance/fighter-android-bootstrap-preflight-run-43646462886.md)则已执行在另一个 Ubuntu runner。该 runner 有 SDK manager 12，但 emulator、目标镜像、该份许可接受证据及当前 KVM 读写均未就绪。两份报告属于新的实际证据，不将本节本地容器盘点冒充 CI 环境事实。
