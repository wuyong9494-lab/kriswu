# D19 官方 bootstrap CI 诊断：625b3285

## 结论

**本次 GitHub CI 已实际执行一次源值固定的官方 bootstrap GET，但未取得 D19 的资源索引。** [运行 43644393775](https://github.com/wuyong9494-lab/kriswu/actions/runs/43644393775) 的结果是 `completed / failure`；失败发生在最终结果报告。请求采集、加密和上传步骤成功不代表资源恢复成功。

认证解封后的实际响应为 **HTTP 400、26 bytes**，与此前本地请求的正文逐字节相同，没有 JSON、`bundles.path`、`bundles.url`、平台版本 metadata 或可用下一跳。因此，本次新增 D19 专属动作文件 **0**、装备 **0**；仍缺 11 个专属源文件、12 个动作别名及 5 类装备。现有双锤、普通斧或共享动作不因此被改称为盘古专属实现。

本批文件名使用 `20261115` 开发批次；实际执行时间是 **北京时间 2026-11-15 05:44**（UTC 2026-11-14 21:44）。没有再次请求、重跑 CI、追随返回地址、下载完整 APK 或模型。

## 固定源与运行身份

| 项目 | 已核对值 |
| --- | --- |
| 仓库 / 分支 | `wuyong9494-lab/kriswu` / `codex/fighter-visual-acceptance-20261113-1200` |
| 提交 | [`625b32851f1909230a87b04675d64dfb7935068c`](https://github.com/wuyong9494-lab/kriswu/commit/625b32851f1909230a87b04675d64dfb7935068c) |
| Git tree | `13689f7e72d6862c0576401d6f78759fb6b1fa4b` |
| Workflow | [fighter-pangu-index-discovery.yml](https://github.com/wuyong9494-lab/kriswu/blob/625b32851f1909230a87b04675d64dfb7935068c/.github/workflows/fighter-pangu-index-discovery.yml) |
| Helper | [fighter_pangu_index_discovery.py](https://github.com/wuyong9494-lab/kriswu/blob/625b32851f1909230a87b04675d64dfb7935068c/.github/scripts/fighter_pangu_index_discovery.py) |
| Run / attempt / job | `43644393775` / `1` / `132598802063` |
| Runner | `ubuntu-24.04`，Python `3.12.3` |
| 请求开始 | 北京时间 `2026-11-15 05:44:29.646199`（原始回执为 UTC） |
| 请求耗时 | `0.574` 秒 |
| 唯一目标请求次数 | `1` |
| Redirect / retry / 后续 URL | `0 / 0 / 0` |

Admission 同时检查 GitHub source SHA、workflow SHA、run/attempt、指定分支、精确 push message，以及执行文件是否与该提交的 Git blob 一致。私有回执中的 source/run/attempt/request 与 GitHub API 记录及本地消费者核对一致。

| 发布文件 | SHA-256 |
| --- | --- |
| Workflow | `3bfde04ea84f8a1294b2661d567be34aa2104b30b623b424865b4e66ee687859` |
| Helper | `fc5c9a698319963077f10f33669dd47b5151adee5e55da1d739b060c9a8868c3` |
| 新增模拟测试源 | `8b4d3efce71b5645cd20e28a3e4314df6d4092897afc39652155c1ac6698fe14` |

## 请求来源与执行边界

固定请求是已观察到的源值组合：

```text
GET https://sf3lb.nekki.com?fv=1.46.0.0.16728-prod&rand=38491&p=Android
```

- Host 来自提供的原客户端 `internalSettings → ServerSettings.Servers.prod[0]`。
- `fv` 来自官网实际 resolver 指向的 `19221.apk` 启动归档成员 `1.46.0.0.16728-prod_splits.zip.enc`，不是推测版本号。前序取材见[官方远端索引报告](fighter-pangu-official-remote-index-20261115.md)。
- 原生 `1606 → 170836 → 170879` 使用 GET，form/body 为空，应用显式 headers 为空；没有已知 world 时不添加 `w`。
- CI 使用 runner 自带的代理与验证 TLS 设置，没有创建代理或隧道，没有覆盖网络策略、证书或 DNS。urllib 自动 User-Agent 实际为 `Python-urllib/3.12`，没有冒称 Unity 传输已完整复现。
- 进程总 deadline 为 20 秒；正文最多 1 MiB，响应头最多 64 KiB。重定向、重试及响应 URL 自动跟随均被拒绝。出现明确 policy denial 时只记录并停止。

这个任务是 GitHub CI 环境中的官方 bootstrap 集成诊断。新旧错误都没有明确的目的地策略拒绝标记；`400` 本身不足以确认某个网络层、认证条件或平台参数就是失败原因。

## 真实响应与前次比较

正文精确为非敏感错误文本 `Failure: 400 Bad Request\r\n`，SHA-256：

```text
ca71485324997c2c4cbf507b6e9cd20e1e8d1c7a644f87f5c993216cdafa56b0
```

| 项目 | 前次本地回执 | 本次 GitHub CI 回执 |
| --- | --- | --- |
| HTTP | `400` | `400` |
| 完整正文 | 26 bytes | 26 bytes，完整读取 |
| 正文 SHA | 上述 SHA | 完全相同 |
| Content-Type | `text/plain; charset=UTF-8` | 相同 |
| Server | `envoy` | 未提供该响应头 |
| Content-Length | 前次摘要未单独保留 | `26` |
| Date | `Sat, 14 Nov 2026 21:11:38 GMT` | `Sat, 14 Nov 2026 21:44:30 GMT` |
| Via / policy code | 未见 | 未见 |
| JSON / locator | 无 / 无 | 无 / 无 |
| transportFailure | 前次 HTTP 失败 | `null`，取得完整 HTTP 响应 |

CI 实际响应头只有 `Date`、`Content-Type`、`Content-Length`、`Connection`。没有 `Server`、`X-Envoy-Response-Flags`、`X-Envoy-Response-Code-Details` 或 policy-code 信息。因此可以确认 CI 环境也未解除当前请求的失败，**不能把两次正文相同解释为已确认同一 Envoy 或同一网络中间层**。

## 最后一级 `p` 值的静态补核

本次没有再发网络请求；只对现有原生镜像和 metadata 的三个已知位置作定点读取。

1. `native1606` 在 `0x6b070f0` 调用 `native180353`；`0x6b070f4` 将返回的 `x0` 直接移到 query value `x2`，在 `0x6b0710c` 加入 `NameValueCollection`。查询键的 usage slot `0xa594788` 对应 literal index `28279`，实际字符串为 `p`。这之后没有对该值调用 `ToString`。
2. `native180353` 对 `Application.get_platform` 的值 `11` 分支，直接跳到 `native180342`；`Enum.ToString` 位于未识别平台的 fallback 分支，不在这个路径上。
3. 提供的原生镜像中，`native180342` 返回 usage slot `0xa564050`。它映射为 string literal index `3457`，实际七字节值 **`Android`**。标准 iOS 返回 slot `0xa590d90` 则是 literal index `26423` 的 **`iOS`**。

这些定点字节证明了**当前已取得原生镜像中的实际映射和传入 query 的字符串形式**，排除了“这个 Android 分支其实先转整数或额外调用 Enum.ToString”的猜测。

边界仍然存在：这是一份提供的 iOS native 镜像，其中 Android 的可选 SKU 条件已被编译优化；尚未执行官方 Android 构建的实际平台选择分支。缓存 Android metadata 中存在 `AndroidChina`、`AndroidEGS`、`AndroidVietnam` 并不足以选择它们。没有新的确定证据支持改换 SKU，故没有扩大取材或追加请求。

源镜像 SHA：`7c192647b0e035bd246c135a59c597ee3910d50fc4ed128abe402da39a62a55b`；源 metadata SHA：`12d52d278c904b210541e7c337025c68454e2b89a83eddab51f9c74fcc5a245c`。

## 加密证据闭包

唯一 artifact 为 `pangu-bootstrap-private-43644393775-1`，ID **`14133218361`**，ZIP **6,179 bytes**，到期时间 `2026-11-17T21:44:30Z`。

GitHub artifact digest 已与下载字节核对：

```text
923012c8692a51692ac713d630bee0409dd3e80b10865f740cb1640f1c8c6402
```

| 加密产物中的固定文件 | Bytes | SHA-256 |
| --- | ---: | --- |
| `pangu-bootstrap-evidence.enc` | 4,450 | `f8edaadffd4c908a7ca4f64c54167d3d1c462483d219fdeb8e1c28babb8089d0` |
| `pangu-bootstrap-evidence.key.enc` | 384 | `ca3d959c8119177af06274517b607fbc743760e1c4f73573fcbb6e6ca115daa2` |
| `pangu-bootstrap-evidence.session-key.enc` | 384 | `b1382b8388ba7c7702b52daacc9e96ad4fb4dd8a7fd49de815522a383b36083c` |
| `pangu-bootstrap-evidence.SHA256SUMS` | 301 | `47f321bf56f46412690eecc8085da0d610d35f6fd056db08de8c8551cf6a0e01` |

消费者只下载本 artifact 一次，核对 GitHub ZIP digest、严格四文件集合、三份密文对应的 `SHA256SUMS`，并另记校验和文件本身的摘要。使用既有接收人验证 SPKI，再通过 OpenSSL 在进程内解包新的诊断 key；既有 `FIGHTER1/evidence` unseal 在解密之前核验完整 HMAC。没有输出或复制私钥，没有读取或上传资产密钥。

解封所得仅有 `identity.json`、`request-started.json`、`receipt.json`、`response.bin`。所有私有文件在仓库外，目录 `0700`、文件 `0600`。完整明文没有提交到本仓库。

私有审阅回执摘要：

- `verified-receipt.json`：`f24cb936d248b02bd45c3610e811abdac2839d799a11f82a69c74ecf998d50f3`。
- `platform-followup-private.json`：`ed177d354a239894e9d92ae623ed138d37174e5ddd6f080cc1e35f937bdd2a1e`。

## 测试与证据级别

| 范围 | 实际完成状态 |
| --- | --- |
| 新 Python 模拟门禁 | 本地最终 20 methods / 0 failures / 0.042 秒；覆盖身份、一次请求、大小/时间上限、拒绝跳转、密封及不泄漏正文 |
| 已成功测试的 CI 重跑 | **0**；发布前移除了 CI 再跑这 20 项的 step，保留测试源的提交 blob 门禁；该调整只作 YAML 解析/静态检查 |
| 官方 bootstrap CI | 真实单次 HTTP 400；资源恢复未通过 |
| 证据加密与本地消费 | GitHub digest、四文件集合、三密文校验和、RSA 接收方、认证 envelope、运行与请求身份均已核对 |
| 原生 / 模拟器 / 真机 | 本任务均未执行，不能由本回执推导通过 |
| D19 专属资源 | 未恢复；11 文件 / 12 别名 / 5 装备缺口保留 |

本次没有取得实际 metadata 结构或新 URL，故不存在可依据本回执执行的下一跳。下一步必须由新的真实客户端平台/启动响应证据支持；不会凭缓存文件名猜测 `metadata`、`bundlesConfig` 或 archive 地址，也不会把本次 HTTP 400 自动重试为通过。

## 后续客户端启动条件

[只读 Android 前置运行 43646462886](acceptance/fighter-android-bootstrap-preflight-run-43646462886.md)已核实真实 runner：SDK manager 可用；emulator、API30 r16 镜像不存在，现有许可文件不含当前许可的精确摘要，KVM 当前不可读写。尚未安装、接受许可、启动 APK 或恢复 D19。此后没有继续发送同类 bootstrap 请求。
