# D19 官方 Android 客户端：已获许可的一次启动专项

## 本文状态与用途

这是本轮新增入口的执行合同，**不是启动成功或盘古还原完成的报告**。用户已在上一轮给出精确 Android SDK 许可全文及固定包版本后回复「允许」。许可原文 SHA-256 为 `1f8729233617b193fd619213792ae16a41b95d2bbbf525dfe66998252ba68b16`，SHA-1 为 `efa68a6b3c661d18699d5c026771d5911cdc2f83`，UTF-8 长度 16,962 bytes。

本轮从远端 `1efa361dbe454262e395221ba33b34d4779377d5` 继续。该提交恢复了失败的 World 装配候选；其 13 个 skipped 工作流没有产生新测试通过。本 Android 入口不改变 App/Core、角色资源或 Sites 受保护文件，不运行任何 Apple 方法。

新工作流仅在指定仓库、指定分支、首次 attempt，以及精确提交标题 `Verify approved Android client and host ownership 20261115` 同时匹配时运行。不设定时、不 dispatch、不重跑已有成功工作流。同期另一个新宿主 renderer 诊断是独立原生范围，其方法数不属于本 Android 结果。

## 固定取材与许可

| 对象 | 这次允许的精确身份 |
|---|---|
| Emulator | Linux x64 / 37.2.13 / `emulator-linux_x64-16740729.zip`，349,658,551 bytes，SHA-1 `f41f9e31eb5ca64926603c03265c50bbc0ff4172` |
| 系统镜像 | `system-images;android-30;google_apis;x86_64` / r16 / `x86_64-30_r16.zip`，1,438,186,618 bytes，SHA-1 `6ae21030eaadc041078444d3798e4b399f3e787d` |
| APK | 官方 resolver 先前返回的 `https://sf3assets.nekki.com/builds/apk/7/19221.apk`；`com.nekki.shadowfight3` / 1.46.0 / 19221，263,891,547 bytes |
| APK 已知成员 | Manifest SHA-256 `4b009c7cfa57dace3c4affec9b6d8757bdadc5d3d2d90a47d3dd97b1af705171`；中央目录 3,119 项 / 293,445 bytes / SHA-256 `abaebf457c31bd2bb5d2231225098afef0a9a3a41a45a0e28930dcb68539b583` |

两包与 APK 的压缩字节合计为 **2,051,736,716**。实际下载得到的 SHA-256、APK signer 指纹只在成功取得后记录，不能预填。APK 验签成功证明包的签名有效；首次取得的 signer 指纹不等于已经与另一份可信发行者指纹比对。官方来源链、包版本、成员身份与签名验证分别留证。

`sdkmanager` 的 `emulator` 包路径与 stable channel 不构成 revision pin。本轮调整旧草案的安装方法：由官方 `sdkmanager --licenses` 逐项显示许可，只有已批准精确正文才接受，其他正文明确拒绝。进入 review 的回答与法律接受回答分开计数。接受完成后只读验证许可文件增量；不手工追加 hash，不复制全局 license 文件，不使用 `yes` 或接受所有条款。

随后通过以上精确官方 archive URL 各取一次，验证 size/SHA-1、记录实际 SHA-256，再验证 ZIP 路径、类型、重复项、展开总量和原 `source.properties`。如 archive 没有登记文件，复用已有 CLI 的官方 repository API 从已认证 `RemotePackage` 生成 `package.xml`，再由官方工具发现并确认。这是从原 metadata 派生登记，不虚构包版本，不额外下载安装器候选。

## 执行环境与所有权

当前开发容器没有 `/dev/kvm` 和 Android SDK，故使用新的一次 `ubuntu-24.04` GitHub runner。已发布的 runner 清单不代替本次现场核验。现场记录 Java、CLI 12、ADB、apksigner、aapt、ACL 工具和实际 image 的版本、摘要及存在性；缺失则停止，不自动扩大安装集合。

任务私有 SDK 使用已有 CLI 的真实副本。AVD Manager 按其 canonical toolsdir 定位 SDK，仅改 `ANDROID_HOME` 或使用指向全局目录的 symlink 不足以隔离；因此检查实际 wrapper 的 canonical 位置和原工具摘要。ADB、签名和包信息工具复用 runner 既有项。

KVM 只允许为本次 runner UID 增加读写 ACL，保留原 mask 与其余主体的有效权限。先保存设备身份和 ACL、预演变更；如需要扩大 mask 或发现已有同 UID 特殊 ACL，则停止。结束时移除自己的增量并核对原 ACL，不能覆盖并发变更。

只创建一个新的 AVD，使用实际列出的 `pixel_2` profile、固定 console port 5556 / serial `emulator-5556`，另持有 5038 上的前台 ADB server。进程由独立 session、UID、启动时间和 process group 绑定；emulator launcher 正常 exec 为 QEMU 不会被误当成另一个进程。所有 ADB client 操作指定此 serial，并先检查所持有 server。

## 一次正常客户端路径

1. 验证 SDK、APK 整包、ZIP CRC、Manifest、中央目录、ARM ABI 清单、包版本和签名。
2. 临时 KVM ACL就绪后冷启动一次。开机后核 AVD name、API、fingerprint、实际 ABI 与 native bridge。该 APK 只有 ARM64/ARMv7，x86_64 镜像能开机不等于能够运行它。
3. 正常 `adb install`，不使用 `-g` 批量授权。Main activity 来自已安装包的真实 resolver，不写死推测入口。
4. 仅 `am start -W` 一次，采集本次 PID/时段日志、原始 PNG 和可见 UI hierarchy。遇新协议、登录、验证码、付费或额外权限即记录并停下，不代点击同意。
5. 仅检查普通 shell 可读的同包 external-files 缓存：`/sdcard/Android/data/com.nekki.shadowfight3/files/gamedata/Resources/Configs/bundles_<版本>.bytes`。该路径来自已核原版 Banzai.IO 的缓存拼接链；尚不能预称当前 APK 一定产生它。

不使用 root、run-as、重签、patch、TLS 中间人、关闭证书校验、应用私有 sandbox 提权读取，也不根据 D19 名称、构建号或历史 hash 拼资源 URL。缓存若存在，保留原 bytes/size/SHA，并先标记未解码；取得缓存不等于 D19 资源已经恢复。

## 资源与证据预算

- 安装前至少 18 GiB 可用空间；SDK archive 解包总量上限 12 GiB。
- emulator 最多启动一次；开机等待 180 秒，整个设备运行窗口 600 秒，后续命令共享剩余 deadline。
- 正常 App 启动最多一次，观察窗口最多 180 秒；网络速率设为 1024:1024 kbps，并在实际可读的 guest interface 计数超过 256 MiB 时停止。该计数与限速配置不冒充逐请求完整网络审计。
- 最多 12 张原 PNG；每张上限 16 MiB。最多 8 个严格匹配的原缓存，单个 32 MiB、合计 64 MiB。
- emulator 和 ADB 后台输出边读边计算摘要，仅保留最后 2 MiB；记录原始已读字节量、流是否读完和 tailOnly，不能声称完整日志已提供。
- 加密证据总明文上限 384 MiB，不包含 APK、SDK archive 或 AVD 磁盘。所有原日志和缓存保持加密，公开仅脱敏摘要。

复用既有 `fighter_private_model.py` 的 AES-256-CBC/PBKDF2 与独立 HMAC envelope。每次生成新的证据密钥，仅通过已核 RSA 公钥包装；资源解密 secrets 不进入本工作流。GitHub artifact 仅上传 `.enc`、包装后的 `.key.enc` 与校验表，保留 3 天。

先停止自有 emulator/ADB 并恢复 KVM，记录真实清理结果，再封存证据；确认封存后清除本次 SDK、APK、AVD 和明文。清理不完整不能打印完成。不会上传 TestFlight 或重复上传任何角色资源版本。

## 结果必须分层

报告单列 `prerequisitesReady`、`licenseAcceptedForExactText`、`sdkInstalled`、`apkSignatureVerified`、`kvmReady`、`imageBooted`、`apkABICompatible`、`apkInstalled`、`normalLaunchObserved` 和 `readableBootstrapCatalogObtained`。每层都需对应实际回执；接受许可后下一阶段失败，不能抹掉已接受事实，也不能把后续层自动标真。

当前已知 D19 缺口仍为 11 原动作文件、12 aliases 与 5 类装备。现有 `liu_hammers/isPangu=false` 不变。自动化启动、缓存完整性、原生 iOS 机制、模拟器视觉与 iPhone 17 Pro Max 真机验收是不同证据层。实际本轮结果将在独立运行报告中写入。

## 官方依据

- [SDK Manager 命令](https://developer.android.com/tools/sdkmanager)
- [官方 LicensesAction](https://android.googlesource.com/platform/tools/base/+/e0179e7b7c4768dd2ebab8d5c8e596180691fd09/sdklib/src/main/java/com/android/sdklib/tool/sdkmanager/LicensesAction.java)
- [官方 InstallerUtil](https://android.googlesource.com/platform/tools/base/+/e0179e7b7c4768dd2ebab8d5c8e596180691fd09/repository/src/main/java/com/android/repository/util/InstallerUtil.java)
- [官方 AvdManagerCli](https://android.googlesource.com/platform/tools/base/+/e0179e7b7c4768dd2ebab8d5c8e596180691fd09/sdklib/src/main/java/com/android/sdklib/tool/AvdManagerCli.java)
- [ADB 前台 server 参数](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/client/commandline.cpp)
