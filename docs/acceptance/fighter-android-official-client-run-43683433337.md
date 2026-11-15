# Android 官方客户端执行结果：43683433337

**本次实际完成了批准的 SDK 安装与登记、官方 19221 APK 的签名完整性验证和包信息核对，并通过 KVM 前置检查。运行仍为 failure / blocked：仅带 `-version` 的 Emulator 探针选择默认有窗口路径，并因缺少 `libpulse.so.0` 退出 127；计划中的无窗口、无音频启动尚未执行，也未安装 APK 或启动客户端。D19 新资源仍为 0。**

新版签名解析器已在真实输出上通过，不再停在上一运行的 `apk_signature_digest_missing`。这项进展不表示模拟器可运行、客户端初始化完成或盘古已恢复。完整字段、原始证据摘要及边界见[对应 JSON](fighter-android-official-client-run-43683433337.json)。

## 执行身份与时间

执行源为 [`903b5b61f399f7db7748c3912fcbb5afaa46553e`](https://github.com/wuyong9494-lab/kriswu/commit/903b5b61f399f7db7748c3912fcbb5afaa46553e)，tree `cab91537c63c05ca3031e4d762de457077e2a39c`；[run 43683433337](https://github.com/wuyong9494-lab/kriswu/actions/runs/43683433337)、[job 132718801919](https://github.com/wuyong9494-lab/kriswu/actions/runs/43683433337/job/132718801919)、attempt 1。run 和 job 均为 **completed / failure**。

操作与清理回执窗口为北京时间 **2026-11-15 14:00:12.561514—14:01:09.687799**（UTC 06:00:12.561514—06:01:09.687799）；整个 job 窗口为北京时间 **14:00:03—14:01:12**。两者不是同一个耗时口径。证据消费者保留的历史基线 `1efa361dbe454262e395221ba33b34d4779377d5` 不能替代本次执行源。

## 实际完成的步骤

| 步骤 | 本次实际证据 | 结论范围 |
|---|---|---|
| 官方 SDK Common 模块与 marshal 预检 | 两个固定包各调用一次，均退出 0；SDK Common 已注册，临时预检目录已清理 | 预检成功；单独看预检不等于接受许可或安装 |
| 官方许可对话 | review 1 次、接受 1 项、拒绝 7 项；无手写许可记录 | 已通过官方工具接受用户批准的同一条款 |
| Emulator 37.2.13 | 固定归档下载 1 次，大小、SHA-1、ZIP CRC、解压属性、正式 package 登记和已安装列表均通过 | SDK 文件及登记已完成，运行能力仍未通过 |
| API 30 Google APIs x86_64 r16 | 固定归档下载 1 次，执行同样的校验和正式登记 | 镜像已安装，尚未开机或验证 ABI 运行能力 |
| 官方 19221 APK | 下载 1 次；263,891,547 B，ZIP CRC、包名、版本和收到的字节 pin 均一致 | 固定来源与字节身份得到支持 |
| APK 签名 | `apksigner` 退出 0，0.701747 秒；v2 / v3 验证为 true，解析到 1 个 APK signer | 签名完整性验证成立；不等于独立认证发布者身份 |
| APK badging | 退出 0，0.100486 秒；`com.nekki.shadowfight3`、1.46.0、code 19221 | 包信息核对成立，不证明客户端能启动 |
| KVM | 当前 runner 的临时授权实际应用，`kvmReady=true` | 前置权限检查成立；未发生模拟器开机 |

SDK 回执状态为 `installed_exact_metadata_verified_not_booted`，正式包登记调用为 **2 次**，两次均退出 0，精确 package 元数据及官方已安装列表核验为 true。`runtimeValidated=false`；两个 catalog 和两个归档各请求一次，此计数不包含官方工具内部可能发起的全部目录请求。

### 许可的两个真实表示

| 身份 | UTF-8 字节 | SHA-1 | SHA-256 |
|---|---:|---|---|
| 用户批准的 catalog 原文 | 16,962 | `efa68a6b3c661d18699d5c026771d5911cdc2f83` | `1f8729233617b193fd619213792ae16a41b95d2bbbf525dfe66998252ba68b16` |
| 官方 JAXB 解析及实际接受的表示 | 16,960 | `24333f8a63b6825ea9c5514f83c2829b004d1fee` | `aaf80cd0aee7e569ffa8a4be1b61189c0fefccf23068e38dfafe336289b8c723` |

本次再次核实六处限定空白变换及许可记录变更策略。`licenseAcceptedForExactText=true` 的兼容字段依据是 `official_adapted_identity_not_original_XML_bytes`；**不声称 16,962 字节的 XML 原文被逐字节原样接受**。文字条款没有更换，也没有扩大到其他许可。两种表示及六处变换的详细说明保留在[此前报告](fighter-android-official-client-run-43678506106.md)。

## APK 签名修复的实际结果及信任边界

固定来源为 [19221.apk](https://sf3assets.nekki.com/builds/apk/7/19221.apk)。本次收到的完整 APK SHA-256 为：

`3653dc2cd2a43aef50d93f66f26a0093a8c63911cb965b8482ee8fcf68ebe5f9`

`receivedBytePin` 与[上一运行 43679952753](fighter-android-official-client-run-43679952753.md)在同一固定官方 URL 实际收到的字节一致。它提供跨运行字节一致性，**不是预先独立认证的发布者身份 pin**。证据包没有包含原 APK，消费者核对认证回执及签名、badging 日志，并未再次取得完整 APK 在本地重哈希。

当前解析器正确读取 `versioned_v3_0` 格式的一条 APK 签名证书摘要：

`fee5c7569efddc4ba055f78f9b43d7edd3a0f2923feba403809c6fd7dc3c0381`

APK 的 v2、v3 验证为 true；v1、v3.1、v3.2、v4 为 false。一个 source-stamp 证书行被排除，公钥摘要没有被当作证书摘要。原 `apk-signature.log` 为 **1,840 B**，SHA-256 `0ae25f3b2fa19764a46089007876a14808fb7e0fec251ce055e048a5f6429682`。producer 的真实签名门禁与消费者独立解析相符，消费者没有改写失败门禁。

## 当前失败点与未执行范围

`emulator-version` 本次只传入 `-version`，选择的是默认有窗口 `qemu-system-x86_64` 路径；子进程实际运行 **0.100896 秒**后退出 **127**，不是超时。脱敏错误内容为：

> error while loading shared libraries: libpulse.so.0: cannot open shared object file: No such file or directory

原日志 **218 B**，SHA-256 `b5a3f07ea1c7c67234af084694a7f9dab93310904c7faad86005ba9c7f093466`。该失败使 `prerequisitesReady=false`，不会因为前面的 SDK、APK 和 KVM 子步骤成功而把整个工作流记作通过。

本次模拟器开机、APK 安装和客户端启动均为 **0**；没有启动截图、运行时属性、可读启动目录或缓存，也没有新 D19 文件。APK 自身包含 arm64-v8a 和 armeabi-v7a 原生库各 24 项，x86 / x86_64 均为 0；选定镜像的实际 ABI 能力尚未探测，因此 `apkABICompatible=false` 表示门禁未到达，不能解读为已运行证明不兼容，也不能据 APK 目录推断该镜像必然可用。

上述缺库结论只适用于本次实际走到的有窗口探针，**不能证明计划中的 `-no-window -no-audio` 路径也缺少 `libpulse.so.0`**；该路径尚未执行。下一步最小候选是在 SDK 完成后、APK 下载前，将 `-version` 探针也统一为无窗口、无音频模式，再实际验证；只有该模式仍报告具体缺库，才针对该依赖处理。本次不预填 apt 安装、依赖闭包完成或模拟器启动成功。盘古模型、动作、装备仍未认证，刘泉纬现有双锤参考资源不因此变为盘古实现。

## 工件、独立检查与清理

[加密工件 14149546179](https://github.com/wuyong9494-lab/kriswu/actions/runs/43683433337/artifacts/14149546179)：**865,332 B**，SHA-256 `ee4b671bea19fcdf7f5728990e6d9c647a62503ae4faa8cffc86df4c7c419a34`。root 单次认证消费，GitHub 摘要、密文封套及 canonical source 身份一致；**53 个 inventory 条目，加 inventory 清单自身共 54 个认证文件**，消费者 issues=[]。认证消费成功不等于工作流通过。

两组新增离线检查单独计数：

| 范围 | 首次结果 | unittest / 进程耗时 | 不代表 |
|---|---|---|---|
| 新 producer 签名解析 7 项与 deadline 3 项 | 10 PASS、0 FAIL、0 SKIP | 0.005 / 0.207169 秒 | 未调用真实 SDK、APK 或模拟器 |
| 新 consumer 签名与 deadline 证据门禁 | 10 PASS、0 FAIL、0 SKIP | 0.005 / 0.174499 秒 | 未下载工件、读取密钥或解封 |

这些计数没有混入 Android 执行步骤、Apple 原生角色方法或历史成功集合。它们的源码和日志摘要独立收录在 JSON。

封存时的最终清理回执为 `emulatorStopped / adbStopped / kvmRestored=true`、errors=[]；后续工作流删除自身临时明文数据的步骤也为 success，但本地消费者没有独立探测远端删除结果。在开机数为 0 的本运行中，清理标记不表示曾经启动模拟器。报告不公开配置原文、原始资源、密钥、私钥位置或签名下载 URL；没有 Apple 测试、角色资源上传或 TestFlight 上传，音频、性能、iPhone 真机与 iOS 渲染验收仍未验证。
