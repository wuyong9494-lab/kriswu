# Android 官方客户端执行结果：43678506106

**已实际接受用户批准的同一 SDK 条款；两个固定官方 SDK 归档各下载一次并完成校验和解压。运行仍为 failure / blocked，停在生成本地 package.xml 的 schema 解析阶段，SDK 安装未完成。APK 下载、模拟器开机、APK 安装和客户端启动均为 0。**

## 执行身份与时间

执行源 [`8b33cb0a6bb95e108003847f4d35e22143a40ca5`](https://github.com/wuyong9494-lab/kriswu/commit/8b33cb0a6bb95e108003847f4d35e22143a40ca5)，tree `21abc3952809a02206f9bd2237e15ee2f4ab6a6d`；[run 43678506106](https://github.com/wuyong9494-lab/kriswu/actions/runs/43678506106)、[job 132703814828](https://github.com/wuyong9494-lab/kriswu/actions/runs/43678506106/job/132703814828)、attempt 1。证据消费者记录的历史基线是 `1efa361dbe454262e395221ba33b34d4779377d5`，不能把基线当成本次执行源。

执行器记录的操作及清理窗口为 2026-11-15 **04:50:43.531—04:51:21.590 UTC**，即北京时间 **12:50:43.531—12:51:21.590**；该窗口不等于整个 GitHub job 的耗时。完整来源、逐项摘要和证据边界见[对应 JSON](fighter-android-official-client-run-43678506106.json)。

## 已完成的步骤

| 步骤 | 本次实际证据 | 结论边界 |
|---|---|---|
| 登记桥 Java 编译 | 1 次，退出 0，1.405713 秒 | 证明当前 CLI API 能编译，不等于安装完成 |
| 官方 JAXB 许可身份读取 | Emulator 和 image 各 1 次、均退出 0 | 两个固定 package 的官方解析后身份均与批准映射一致 |
| 官方 sdkmanager 许可对话 | `--licenses` 退出 0；review=1、接受=1、拒绝=7 | 只接受 `android-sdk-license`，没有接受全部许可 |
| Emulator 37.2.13 归档 | 固定官方地址下载 1 次；大小、批准 SHA-1、ZIP CRC、解压后源属性核对成功 | 已取得并校验文件，尚未成功登记或运行 |
| API 30 Google APIs x86_64 r16 归档 | 固定官方地址下载 1 次；同样完成校验及源属性核对 | 尚未登记该 image、启动或验证 ABI 运行能力 |

### 原批准文本与官方表示必须分别保留

| 身份 | UTF-8 字节 | SHA-1 | SHA-256 |
|---|---:|---|---|
| 用户批准、两个 catalog 引用的原文 | 16,962 | `efa68a6b3c661d18699d5c026771d5911cdc2f83` | `1f8729233617b193fd619213792ae16a41b95d2bbbf525dfe66998252ba68b16` |
| 官方 JAXB 解析及 sdkmanager 实际接受的显示版 | 16,960 | `24333f8a63b6825ea9c5514f83c2829b004d1fee` | `aaf80cd0aee7e569ffa8a4be1b61189c0fefccf23068e38dfafe336289b8c723` |

本次已验证六处固定空白变换，可以从批准原文逐字节重建官方显示版；所有文字和标点不变。SDKManager 实际写入接受记录 `24333f8a63b6825ea9c5514f83c2829b004d1fee`。这证明同一条款已通过官方工具接受，**不声称原 XML 的 16,962 字节被原样接受**；两种表示的 bytes 并不相同。`licenseAcceptedForExactText=true` 保留兼容字段语义，其依据明确为 `official_adapted_identity_not_original_XML_bytes`。

原批准身份、官方显示身份、六个位置及 hex 变换均收录在 JSON。没有任意空白归一化、手写 acceptance hash 或更换许可；Google TV、Google XR、ARM DBT、SDK preview、GDK、Micro XR、MIPS 七项许可回答 n。后续登记失败不抹掉本次实际接受事实。

### 已验证的两个官方归档

| 包 | 下载字节 | 官方批准 SHA-1 | 收到的完整归档 SHA-256 |
|---|---:|---|---|
| [Emulator 37.2.13](https://dl.google.com/android/repository/emulator-linux_x64-16740729.zip) | 349,658,551 | `f41f9e31eb5ca64926603c03265c50bbc0ff4172` | `cbc7c3cfb83220b8a0f9c513fdab557712e74d339ec19ddffa43f23350ae9bdd` |
| [system-images;android-30;google_apis;x86_64，r16](https://dl.google.com/android/repository/sys-img/google_apis/x86_64-30_r16.zip) | 1,438,186,618 | `6ae21030eaadc041078444d3798e4b399f3e787d` | `daae27654be74ae83a484daea4db2c0c77b4f4ad661a645bd5f36d96ce03e4d5` |

归档 SHA-256 来自本次实际收到的 bytes，并非预先伪造的官方摘要。Emulator 451 个成员展开 903,291,749 B；image 17 个成员展开 3,442,796,119 B；两者 CRC 均通过，源属性分别确认 revision 37.2.13 和 API 30 / Google APIs / x86_64 / revision 16。两个 catalog 和两个归档均由受控下载器各请求一次；SDKManager 自身可能读取目录元数据，不能把这四项当作全部网络请求总数。

## 失败点与未执行步骤

第一次 Emulator package 登记调用实际启动，**退出 1、耗时 1.143529 秒，未超时**。原日志 `sdk-official-register-emulator.log` 为 3,965 B，SHA-256 `f0affdeca83958e55b530cea6af729cfa929a727f326142eb4a3dbb5b1c3e4fe`。

调用链为 `RegisterPinnedPackage.main → InstallerUtil.writePackageXml → writeRepoXml → SchemaModuleUtil.marshal → getSchema`。底层抛出 `schema_reference.4`：导入的 `sdk-common-01.xsd` 未被已注册模块解析，落到工作目录查找并触发 `FileNotFoundException`；严格 warning 处理将其转成 `official_metadata_warning` 后停止。这是本次原日志直接证明的失败。

官方固定提交 `e0179e7b7c4768dd2ebab8d5c8e596180691fd09` 的只读源码解释了模块缺口：[InstallerUtil](https://android.googlesource.com/platform/tools/base/+/e0179e7b7c4768dd2ebab8d5c8e596180691fd09/repository/src/main/java/com/android/repository/util/InstallerUtil.java) 已向序列化传递 `manager.getResourceResolver(progress)`；[RepoManagerImpl](https://android.googlesource.com/platform/tools/base/+/e0179e7b7c4768dd2ebab8d5c8e596180691fd09/repository/src/main/java/com/android/repository/impl/manager/RepoManagerImpl.java) 从当前已注册模块构造该解析器。[AndroidSdkHandler](https://android.googlesource.com/platform/tools/base/+/e0179e7b7c4768dd2ebab8d5c8e596180691fd09/sdklib/src/main/java/com/android/sdklib/repository/AndroidSdkHandler.java) 的 `getAllModules()` 包含 repository common，却未包含负责 `/xsd/sdk-common-%02d.xsd` 的 SDK `COMMON_MODULE`；官方 `createRepoManager` 会额外注册后者。归档中的桥仅遍历 `getAllModules()`，缺少这项额外注册。

最小候选是在同一登记管理器中额外注册 `AndroidSdkHandler.getCommonModule()`，保留当前许可、摘要及严格 warning/error 门禁。该候选来自上述官方源码分析，**本运行没有验证新增注册语句的 CLI 兼容性或成功完成 package.xml marshal，也不能提前记作修复成功**。

回执中的 `packageCalls=1` 是已发起的登记尝试；`executed=false` 是尚未完成成功登记的标记，不能解读成 Java 从未运行。image 登记调用为 0，`installedExactPackagesVerified=false`、`sdkInstalled=false`、`runtimeValidated=false`。

APK 下载、签名验证、实际 image ABI 能力门禁、开机、APK 安装、客户端启动均未进入；没有截图、启动缓存或新 D19 文件。本次没有证明官方 19221 客户端能够完整加载，没有恢复盘古模型、动作或装备，也没有改变刘泉纬当前双锤参考身份的证据边界。

## 工件、独立消费检查与安全边界

[加密工件 14147567063](https://github.com/wuyong9494-lab/kriswu/actions/runs/43678506106/artifacts/14147567063)：**792,272 B**，SHA-256 `a6d1b15ca31d3c0abba60fcd7eb666fcdd19d22ebb1418353cba64e8dd3eec97`。root 单次认证消费，GitHub 摘要、密文封套与 canonical source 身份一致，25 个 inventory 条目，消费者 issues=[]。原 SDK 归档没有装入该证据包；消费者验证的是认证回执和日志，并未在本地再次取得或重哈希安装后的 SDK 文件。

另有 **12 项本轮新增消费者合成检查**由 root 单次执行通过，进程退出 0、耗时 0.768082 秒。它们只验证证据消费逻辑，未执行 SDK、下载工件、读取私钥或解封；不计入本次 SDK 成功步骤或 Apple 方法数。

封存时清理回执为 emulatorStopped / adbStopped / kvmRestored 均 true、errors=[]；在本次未开机的情形下，这些是清理状态，不能冒充已启动模拟器再成功关闭。后续明文删除不由本地消费者独立证明。报告仅公开来源、摘要、步骤和脱敏失败原因，不包含原始配置、资产、密钥、私钥位置或签名下载地址。Apple 测试、角色资源版本上传和 TestFlight 上传均为 0；物理 iPhone、音频、性能、iOS 渲染与盘古资源验收保持未验证。
