# D19 官方 Android 客户端：已获许可的一次启动专项

## 本文状态与用途

这是本轮新增入口的执行合同，**不是启动成功或盘古还原完成的报告**。用户已在上一轮给出精确 Android SDK 许可全文及固定包版本后回复「允许」。许可原文 SHA-256 为 `1f8729233617b193fd619213792ae16a41b95d2bbbf525dfe66998252ba68b16`，SHA-1 为 `efa68a6b3c661d18699d5c026771d5911cdc2f83`，UTF-8 长度 16,962 bytes。

本轮从远端 `1efa361dbe454262e395221ba33b34d4779377d5` 继续。该提交恢复了失败的 World 装配候选；其 13 个 skipped 工作流没有产生新测试通过。本 Android 入口不改变 App/Core、角色资源或 Sites 受保护文件，不运行任何 Apple 方法。

首次工作流以精确提交标题 `Verify approved Android client and host ownership 20261115` 执行，实际结果归属 `a7d5a4471433b88b348c87a3dc381e142bded89a` / run `43676028509`。该次在许可和大包下载前的 Java 注册桥编译失败：`Repository` 的 import 包路径错误；许可接受、SDK archive 下载、APK 下载、模拟器启动、APK 安装和客户端启动均为 0。详见[实际失败证据](fighter-android-official-client-run-43676028509.md)。

`3ac0d950948cede934ff52b45664b1225261a27d` 的最小 import 修正已在 run `43676984599` 实际编译通过，但随后因 SDK 官方展示文本与原 XML 文本的表示差异而拒绝接受。实际 review=1、接受=0、拒绝=4，SDK/APK 大包与启动仍为 0；详见[第二次实际结果](fighter-android-official-client-run-43676984599.md)。用户已给出的同一精确 SDK 许可授权继续有效。

`8b33cb0a6bb95e108003847f4d35e22143a40ca5` / run `43678506106` 已完成同条款的官方接受（1 接受、7 拒绝）和两份固定 SDK 归档的实际完整性检查，随后在官方 package.xml marshal 阶段失败：现有模块集合遗漏 SDK Common 模块。APK/开机/安装/启动均为 0，见[第三次实际结果](fighter-android-official-client-run-43678506106.md)。该接受事实不因后续登记失败而被抹去。

登记修正 `f52c293da885f24ebae7640055161380aba4a5f7` / [run 43679952753](https://github.com/wuyong9494-lab/kriswu/actions/runs/43679952753) 已实际完成两次隔离 marshal 预检、正式 package.xml 登记、固定包版本及官方安装清单验证，`completeSDKInstallValidated=true`。随后取得完整官方 APK，签名工具实际退出 0，输出 `Verifies`、v2/v3=true、签名者 1；旧解析器只识别 `Signer #1`，未识别该工具实际输出的 `V3.0 Signer:`，以 `apk_signature_digest_missing` 停止。该次 producer 的 `apkSignatureVerified=false` 保留，boot/install/launch 仍为 0，见[实际报告](fighter-android-official-client-run-43679952753.md)。

提交 `903b5b61f399f7db7748c3912fcbb5afaa46553e` / [run 43683433337](https://github.com/wuyong9494-lab/kriswu/actions/runs/43683433337) 已实际通过 APK 签名解析、badging 与 KVM 前置检查。随后，仅带 `-version` 的版本探针选中了带窗口的 `qemu-system-x86_64`，以 exit 127 停止，原始错误为缺少 `libpulse.so.0`。真正的 `-no-window -no-audio` 启动尚未执行；开机、安装与客户端启动均为 0。不能据此认定无窗口程序也缺少同一依赖，详见[实际报告](fighter-android-official-client-run-43683433337.md)。

本次最小候选是让版本探针与既定真实启动保持同一无窗口、无音频模式，并将它放在 SDK 安装成功后、APK 下载之前；不预先新增宿主包。唯一提交标题为 `Resolve official emulator headless version probe 20261115`，仍只允许指定仓库、指定分支、push 和首次 attempt。已实际通过的 SDK helper 字节不变；新的 runner 仍需满足原安装身份与许可门禁。原成功检查及新近 10 项签名/截止时间检查均保留，不自动重跑。同期 Apple 渲染回归属于独立工作流，不并入 Android 结果。

固定的 Emulator 37.2.13 归档本次仅作一次末尾中央目录读取：HTTP 206，范围 `349592994–349658550/349658551`，65,557 B，SHA-256 `b94bf5c0a44edaa64fc6765e7c36c29c997ec4542a451f7ad0abd735bfa0b5df`。中央目录 451 项，包含可执行常规成员 `emulator/qemu/linux-x86_64/qemu-system-x86_64-headless`，展开大小 24,433,280 B、CRC32 `5ccf29bf`。这次没有读取其二进制，也没有重新取得完整归档；完整包校验引用先前已认证的运行，不能冒称本次重新完成。

官方 [launcher](https://android.googlesource.com/platform/external/qemu/+/emu-master-dev/android/emulator/main-emulator.cpp) 将 `-no-window` 解析为 headless，并选择 `qemu-system-*-headless`；`-version` 不终止其参数解析。官方 [构建定义](https://android.googlesource.com/platform/external/qemu/+/af0d697842c6d71466b7d8e4c6e4d9935ed08426/CMakeLists.txt) 区分 headful 的 PulseAudio 链接与 headless 实现。这些源码支持候选方向，不代替固定版本真实二进制的执行验证。

新前置检查只核已认证包内 headless 常规可执行成员，记录实际大小和摘要，然后执行一次 `emulator -no-window -no-audio -version`。不直接调用 QEMU，不使用可能遗漏 launcher 包内库路径的裸 `ldd` 作为门禁，也不安装 apt 包。探针通过只证明该版本命令可执行，不将 boot、安装、ABI 或启动门禁标为通过；失败时在 APK 下载及 KVM ACL 变更之前停止。

签名解析只支持已核的 `V3.0 Signer:` 和官方编号格式；要求工具退出 0、唯一 `Verifies`、一个签名者及已验证的 APK 签名方案。应用证书、Source Stamp 证书与 public-key 摘要分别处理，后两者不能补足缺失的应用证书。重复、未知或冲突输出明确拒绝。新增小范围离线检查使用前次已认证原始日志和明确标注的合成变体，不重新调用验签工具或下载 APK。

新增 7 项签名解析与 3 项截止时间检查于北京时间 2026-11-15 13:52:58 首次执行，**10 PASS / 0 FAIL / 0 ERROR**；unittest 0.005 秒、进程 0.207169 秒。runtime SHA-256 `a1dbc6ebc5ca91fee2b12ba3406fcd06016a56c002a1142f63149aef94906e40`，新检查文件 SHA-256 `655fa250504c065396dfd91db3e7e974af2ef2d67a2d2cfe5aafe74aafc690c9`，原日志 1,957 B / SHA-256 `a650a9bf9796cb42dbbc9e6a5c8e629a0e2ab42069c4e7184446147c5504a4e3`。仅解析前次认证日志和模拟时间，不包含实际 SDK/APK/模拟器执行，不能替代下一次客户端结果。

## 本次无窗口版本探针的最小检查

北京时间 2026-11-15 14:15:06，四个新增合成边界方法首次执行：**4 PASS / 0 FAIL / 0 ERROR**，unittest 0.040 秒、进程 0.407009 秒。范围仅包含模式一致且只调用一次、非法成员不执行、真实 exit 127 与未证实启动的失败区分、以及编排失败阻断 APK/KVM/boot。没有真实 SDK、APK、模拟器或网络执行，也没有重新选择之前已通过的检查。

执行时 runtime SHA-256 `78ac6840ec4609fb80d4efdb5aaac604368efc6565da3d1e6c0c46084e4500e2`；新检查文件 `test_fighter_android_headless_probe.py` SHA-256 `89859b4a27a6bfe8ee96296feb2211998fcbfbcf1631a59ec645f3906e74918c`。原检查日志 832 B / SHA-256 `988f50f3b20210d921d70f9526ed48ad7b23fc5099454adbb3de2c16066bc644`。固定 ZIP 中央目录的[只读元数据回执](fighter-android-headless-archive-metadata-20261115.json)单列本次 range 观察与历史整包认证，不把它计为启动验证。

真实 runner 的 headless 探针、开机、ABI、安装、启动和缓存结果仍需分别核对新的执行回执；上述四项通过不提前解除这些门禁。

## 本次登记预检的离线检查

新增 10 个边界检查首次执行得到 5 方法通过、3 方法失败、2 方法错误。失败来自检查夹具仅按 package path 取目录首项，误选 Emulator 37.3.9，而生产 validator 正确要求固定 37.2.13。只修正夹具为 revision 与 stable channel 唯一匹配，没有放松生产校验。首次检查文件 SHA-256 `4aa1d5a39daa28112cef5aaec1e23d84a78fac2c69bc27114f7e7bb65a5e0db3`，原失败日志 SHA-256 `93d3e97c6cd8601f2569161e28fe1edbca5d6629eee43f806d0e381ca8545b47` 保留。

修正后检查文件 SHA-256 `548d2944058a9fc7fc95fbe877d41c2d4699649d4b994960268676dee143eeff`；只复验上述 5 个失败/错误方法，5/5 通过，unittest 0.054 秒，日志 SHA-256 `7fbeaf0098443dc0bebbf6def39d19351421c4ae81f09028d57608c3e4126ad8`。此前通过的 5 方法未重选，不冒称在修正后文件上全量重新通过。两次均未执行 Java、SDK、网络、许可接受或 Apple 方法；真实 Common 模块和 marshal 兼容性仍由新运行单独验证。

## 固定取材与许可

| 对象 | 这次允许的精确身份 |
|---|---|
| Emulator | Linux x64 / 37.2.13 / `emulator-linux_x64-16740729.zip`，349,658,551 bytes，SHA-1 `f41f9e31eb5ca64926603c03265c50bbc0ff4172` |
| 系统镜像 | `system-images;android-30;google_apis;x86_64` / r16 / `x86_64-30_r16.zip`，1,438,186,618 bytes，SHA-1 `6ae21030eaadc041078444d3798e4b399f3e787d` |
| APK | 官方 resolver 先前返回的 `https://sf3assets.nekki.com/builds/apk/7/19221.apk`；`com.nekki.shadowfight3` / 1.46.0 / 19221，263,891,547 bytes；f52 实际整包 SHA-256 `3653dc2cd2a43aef50d93f66f26a0093a8c63911cb965b8482ee8fcf68ebe5f9` |
| APK 已知成员 | Manifest SHA-256 `4b009c7cfa57dace3c4affec9b6d8757bdadc5d3d2d90a47d3dd97b1af705171`；中央目录 3,119 项 / 293,445 bytes / SHA-256 `abaebf457c31bd2bb5d2231225098afef0a9a3a41a45a0e28930dcb68539b583` |

两包与 APK 的压缩字节合计为 **2,051,736,716**。本次新增的整包 SHA-256 固定的是 f52 已实际取得的字节，不能说成独立可信发行者证书。原日志的应用证书 SHA-256 为 `fee5c7569efddc4ba055f78f9b43d7edd3a0f2923feba403809c6fd7dc3c0381`；该指纹尚未与另一可信发行者来源独立比对。官方来源链、包版本、成员身份、工具验签成功与 producer 解析门禁分别留证。

`sdkmanager` 的 `emulator` 包路径与 stable channel 不构成 revision pin。本轮调整旧草案的安装方法：由官方 `sdkmanager --licenses` 逐项显示许可，只有已批准精确正文才接受，其他正文明确拒绝。进入 review 的回答与法律接受回答分开计数。接受完成后只读验证许可文件增量；不手工追加 hash，不复制全局 license 文件，不使用 `yes` 或接受所有条款。

随后通过以上精确官方 archive URL 各取一次，验证 size/SHA-1、记录实际 SHA-256，再验证 ZIP 路径、类型、重复项、展开总量和原 `source.properties`。如 archive 没有登记文件，复用已有 CLI 的官方 repository API 从已认证 `RemotePackage` 生成 `package.xml`，再由官方工具发现并确认。这是从原 metadata 派生登记，不虚构包版本，不额外下载安装器候选。

## 原文、官方表示与实际接受分别记录

官方固定源提交 `e0179e7…` 的 [global.xjb](https://android.googlesource.com/platform/tools/base/+/e0179e7b7c4768dd2ebab8d5c8e596180691fd09/repository/src/main/resources/xsd/global.xjb) 将 `xsd:string` 绑定到 [TrimStringAdapter](https://android.googlesource.com/platform/tools/base/+/e0179e7b7c4768dd2ebab8d5c8e596180691fd09/repository/src/main/java/com/android/repository/impl/meta/TrimStringAdapter.java)。因此官方 JAXB 对象、显示对话及许可 hash 使用适配后的表示，不能将目录 XML 原 bytes 的 hash 直接用于这些层。

批准原文仍严格固定为 16,962 B / SHA-1 `efa68a6b3c661d18699d5c026771d5911cdc2f83` / SHA-256 `1f8729233617b193fd619213792ae16a41b95d2bbbf525dfe66998252ba68b16`。官方表示为 16,960 B / SHA-1 `24333f8a63b6825ea9c5514f83c2829b004d1fee` / SHA-256 `aaf80cd0aee7e569ffa8a4be1b61189c0fefccf23068e38dfafe336289b8c723`。仅允许已核六处固定空白编辑将前者精确映射到后者；不对其他文本作宽泛归一化，其他同名或不同名条款仍拒绝。

在实际许可交互及大包取得之前，已编译的官方 CLI Java 桥分别只读解析两个目录，必须各自返回精确官方表示摘要。`inspectionCalls/inspectionSuccesses/inspected` 与包登记 `packageCalls/executed` 分开；该检查不写 package.xml 或许可记录。之后由原 sdkmanager 对话接受精确官方表示，由官方工具写入唯一 `24333…` 记录。真正登记包之前再调用官方 `License.checkAccepted`，package.xml 的原 XML 身份与有效官方身份分开核验。

登记管理器按官方 `AndroidSdkHandler.createRepoManager` 的初始化补齐 SDK `getCommonModule()`；`getAllModules()` 中的 repository common 与 SDK common 是不同模块。继续使用 `InstallerUtil.writePackageXml` 及其内部官方 resolver，不手写 XSD 或 XML，也不忽略 warning/error。新增的两次隔离预检走同一实际 marshal 路径，核对产生的 package.xml 的 path、revision 与有效许可身份，随后移除临时目录；`registrationPreflight.calls/successes` 与 `packageCalls/executed` 分开。实际安装后的登记仍要求官方 `License.checkAccepted`。

前次临时 runner 的两份已验证归档已经清理，证据包不含 SDK 大包。新的 runner 优先复用现场已有的精确包；没有精确副本时，继续安装依赖仍需各取一次固定归档。这不是重选已成功的角色测试；前置 marshal 预检用于避免同类登记缺陷到归档取得之后才被发现。

回执主字段为 `approvedTermsAccepted`。兼容字段 `licenseAcceptedForExactText` 明确以 `official_adapted_identity_not_original_XML_bytes` 为 basis；`approvedOriginalBytesAcceptedVerbatim=false` 与 `originalBytesEqual=false` 保留，不能声称用户批准的 16,962 个 XML 字节被逐字写入。公开运行摘要也单列 `licenseAcceptance` 的两种身份、实际接受表示与记录 hash。安装后续失败不能抹去已经发生的合法接受，也不能将安装或启动自动标真。

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
- emulator 最多启动一次；开机等待 180 秒，整个设备运行窗口 600 秒。开机轮询及其等待按剩余预算裁剪，后续命令共享设备 deadline。
- 正常 App 启动最多一次，观察窗口最多 180 秒。网络、PID、截图及 hierarchy 命令分别扣除剩余观察预算，正常预算耗尽记录为 `bounded_observation_complete`，不掩盖其他错误。网络速率设为 1024:1024 kbps，并在实际可读的 guest interface 计数超过 256 MiB 时停止。该计数与限速配置不冒充逐请求完整网络审计。
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
