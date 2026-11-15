# 官方 Android 客户端运行 43679952753：SDK 安装完成，签名摘要解析阻塞启动

[实际运行](https://github.com/wuyong9494-lab/kriswu/actions/runs/43679952753) · [作业 132708204612](https://github.com/wuyong9494-lab/kriswu/actions/runs/43679952753/job/132708204612) · attempt 1。执行提交 `f52c293da885f24ebae7640055161380aba4a5f7`，依据该提交的 [runtime](https://github.com/wuyong9494-lab/kriswu/blob/f52c293da885f24ebae7640055161380aba4a5f7/.github/scripts/fighter_android_official_client.py)、[SDK helper](https://github.com/wuyong9494-lab/kriswu/blob/f52c293da885f24ebae7640055161380aba4a5f7/.github/scripts/fighter_android_sdk_install.py) 与已认证工件。后续代码修正不改变本次失败归属。

## 真实结果

运行主体于 **2026-11-15 05:10:57.333875–05:11:45.491404 UTC** 执行，退出 1，原因 `apk_signature_digest_missing`。SDK helper 已完成官方许可接受、固定 Emulator **37.2.13** 与 Android 30 Google APIs x86_64 **r16** 的两份归档校验、官方 `package.xml` 登记和 `sdkmanager --list_installed` 核对；`installedExactPackagesVerified`、`officialInstalledListingVerified` 均为 true。许可接受依据经核对的官方 JAXB 展示文本，不声称其与批准的 XML 原始字节相同。

两归档本次各下载一次，分别 **349,658,551 B** 和 **1,438,186,618 B**。SDK 状态为 `installed_exact_metadata_verified_not_booted`，安装证据不代表模拟器或客户端已能运行。

APK 本次下载一次，**263,891,547 B**，SHA-256 `3653dc2cd2a43aef50d93f66f26a0093a8c63911cb965b8482ee8fcf68ebe5f9`。`apksigner` 真实退出 **0**，耗时 **1.102685 秒**，输出 `Verifies`，v2/v3 验证为 true；其证书行使用 `V3.0 Signer: certificate SHA-256 digest`，而本次 producer 的 regex 只接受 `Signer #<数字> certificate`。因此摘要解析失败，producer 的 `apkSignatureVerified=false`；这与工具实际验证成功必须分列，亦不等于已独立核实发布者身份。

|阶段|本次证据|
|---|---|
|官方许可与固定 SDK 安装/登记|真实完成|
|APK 下载 / apksigner|1 次 / exit 0，`Verifies`|
|aapt 包版本核对、KVM/AVD/ABI 检查|未执行|
|模拟器启动 / APK 安装 / activity 启动|**0 / 0 / 0**|
|截图 / D19 文件恢复|**0 / 0**|

## 证据与后续边界

[加密工件 14147143758](https://github.com/wuyong9494-lab/kriswu/actions/runs/43679952753/artifacts/14147143758)：**844,063 B**，SHA-256 `e719bd3262ad4144cd708782115a3064dffa756e37f89c09e17a873b75c3dfee`。唯一消费已验证传输摘要、认证封装、源身份及 **31 个 inventory 条目（含清单共 32 文件）**，`issues=[]`。这只证明失败证据被完整恢复。签名原日志 **1,840 B**，SHA-256 `0ae25f3b2fa19764a46089007876a14808fb7e0fec251ce055e048a5f6429682`；完整摘要、SDK/签名日志哈希见[配套 JSON](fighter-android-official-client-run-43679952753.json)。原日志、APK、媒体及密钥不随本报告公开。

失败后密封、密文上传及清理完成；清理回执三项为 true、errors 为空，本次没有创建模拟器或 ADB 服务。公开日志确认私有文件删除完成，消费者未另行检查远端删除后的目录。最小后续仅修正已观察到的 signer 输出格式解析，并保留原 exit-code 与证书归属门禁；启动能力仍须实际验证。本报告未修改 runtime、未重跑 SDK、旧成功测试或工作流。既有 16 producer / 14 consumer 离线检查不并入本次运行结果；Apple 方法、资源上传、TestFlight 均为 0。
