# Android 官方客户端执行结果：43676028509

**结论：`blocked / failure`。SDK 登记桥的 Java 编译失败；许可证接受、SDK 大包下载、APK 下载、安装和启动均为 0。** 本报告只覆盖 Android job，不并计同一提交上的 host SceneKit 诊断。

## 身份与实际执行

| 字段 | 证据 |
|---|---|
| 执行源 | [`a7d5a4471433b88b348c87a3dc381e142bded89a`](https://github.com/wuyong9494-lab/kriswu/commit/a7d5a4471433b88b348c87a3dc381e142bded89a) |
| 源树 / 基线 | `bf82681cce5023e0da147ff2cd8f38e0ff46804f` / `1efa361dbe454262e395221ba33b34d4779377d5` |
| Actions / job / attempt | [43676028509](https://github.com/wuyong9494-lab/kriswu/actions/runs/43676028509) / [132696255103](https://github.com/wuyong9494-lab/kriswu/actions/runs/43676028509/job/132696255103) / `1` |
| Runner | `ubuntu-24.04`，image `20261111.370.1`，runner `2.338.2` |
| 主 helper 实际区间 | UTC `2026-11-15 04:16:25.510279—04:16:36.720688`；北京时间 `12:16:25.510279—12:16:36.720688` |
| SDK helper 区间 | UTC `04:16:30.802346—04:16:36.719420` |

两个官方目录各请求一次：Emulator 目录 **384,394 B**、Google APIs 镜像目录 **200,144 B**，分别匹配 Emulator `37.2.13` 与 Android 30 / Google APIs / x86_64 revision `16` 的固定 metadata。私有 CLI 副本真实版本命令退出 `0`，版本为 `12.0`。目录检查成功不等于安装成功。

公共日志依次记录：`04:16:35.360 UTC` 开始编译登记桥；`04:16:36.734` 主执行退出 `1`；`04:16:36.961` 密封完成；`04:16:38.539` 工件上传完成；`04:16:38.633` cleanup helper 报告删除本次临时 Android 数据。这些是**日志观察时间**，没有另行补查或编造 API step 时间。

## 唯一实际编译错误与最小修复

调用链：`fighter_android_official_client.py run → fighter_android_sdk_install.install → Installer.run → prepare_registration_bridge → javac`。

生成文件 `RegisterPinnedPackage.java` 第 7 行错误导入：

```java
import com.android.repository.impl.meta.Repository;
```

实际错误为 `cannot find symbol: class Repository`，位置 `com.android.repository.impl.meta`。唯一 `javac` 调用退出 **1**、耗时 **1.357893 s**、`timedOut=false`；没有运行登记桥。原始编译日志 **328 B**，SHA-256：

`fad581cfe467e063cc87bfd47df86b9511d37f82c7ae29aa0ff4d965f637f113`

最小修复是 SDK helper 内 `JAVA_REGISTRAR` 的这一行改成 `com.android.repository.api.Repository`；[官方 API 源码](https://android.googlesource.com/platform/tools/base/+/e0179e7b7c4768dd2ebab8d5c8e596180691fd09/repository/src/main/java/com/android/repository/api/Repository.java) 确认此包名。待验证 SDK helper SHA-256 为 `1e9f60ad1fd29b898d74cfd3c3af0e13fd892e7d78a3fb80ffe222b224e029db`。**本次失败运行没有验证修复。** 后续需新源码绑定的一次实际编译；成功才继续尚未执行的许可、固定包及一次客户端路线。

## 零执行范围与授权区别

| 项目 | 本次实际数量 |
|---|---:|
| 许可证 review / 接受 / 拒绝响应 | `0 / 0 / 0` |
| 手写许可证记录 | `0` |
| Emulator / 系统镜像大包下载 | `0 / 0` |
| SDK 包安装 / sdkmanager install / update | `0 / 0 / 0` |
| APK 下载 / 安装 / 启动 | `0 / 0 / 0` |
| Emulator 启动 / 截图 / 启动缓存文件 / D19 新资源 | `0 / 0 / 0 / 0` |
| 本 job 的 Apple 原生 / UI 方法 | `0 / 0` |
| 游戏资源版本上传 / TestFlight 上传 | `0 / 0` |

用户已经授权精确许可与一次官方客户端路线。目录中的 `android-sdk-license` 正文匹配已批准 SHA-256 `1f8729233617b193fd619213792ae16a41b95d2bbbf525dfe66998252ba68b16`，但执行未进入官方 `--licenses` 对话。`licenseAcceptedForExactText=false`、`installedExactPackagesVerified=false`，不得把授权或原文匹配当作实际接受。

新 producer/SDK 的 **16 项离线检查首次 16/16**（unittest `0.093 s`，进程 `0.355155 s`）；私有消费者 **14 项 synthetic 首次 14/14**（unittest `0.015 s`，进程 `0.351278 s`）。两组都不是 Apple 原生测试，也没有执行真实 SDK 编译。没有重跑这两组或历史已成功的 117、5、6 及独立诊断方法，不能把离线通过抵消本次实际编译失败。

## 工件、清理与验收边界

[加密工件 14145543761](https://github.com/wuyong9494-lab/kriswu/actions/runs/43676028509/artifacts/14145543761)：**614,218 B**，SHA-256 `c7320547536b819814a5b5e2e27cc5a10f0d86b4336db4867dfc52b5c2419bd9`。根代理唯一下载并认证解封，确认 **19 个 inventory 成员，含 inventory 共 20 个文件**；摘要、source 身份、成员与 SHA 校验通过，消费者 `issues=[]`。这是证据完整性结论，不是客户端或 D19 通过。

密封时 cleanup 三项标志均 `true`、错误列表为空；本次未启动 emulator/ADB，也未到 KVM 权限变更。不能把这些标志写成曾成功启动模拟器或调整权限。后续临时数据删除由公共 cleanup 日志记录，消费者没有重新检查远端文件系统。

公共 job 日志 **21,745 B**，SHA-256 `aee6a117173621968a1072ee427d0b5d689ab8c21e2c719d6ae4b5375a48344b`。执行时的 [运行 helper](https://github.com/wuyong9494-lab/kriswu/blob/a7d5a4471433b88b348c87a3dc381e142bded89a/.github/scripts/fighter_android_official_client.py)、[SDK helper](https://github.com/wuyong9494-lab/kriswu/blob/a7d5a4471433b88b348c87a3dc381e142bded89a/.github/scripts/fighter_android_sdk_install.py) 与 [工作流](https://github.com/wuyong9494-lab/kriswu/blob/a7d5a4471433b88b348c87a3dc381e142bded89a/.github/workflows/fighter-android-official-client.yml) 的精确 SHA-256 及其余证据摘要见 [对应 JSON](fighter-android-official-client-run-43676028509.json)。本公开记录不含 signed URL、密钥、原始 APK、SDK 大包或私人存储标识。

无截图可供审查，图像状态为 `NOT_AVAILABLE_NO_CAPTURE`；消费者自动 `PENDING` 字段不能升级为画面验收。Android 启动、D19 资源恢复、iOS 渲染、音画同步、性能和 iPhone 17 Pro Max 真机验收均未得到本 job 的通过证据。`liu_hammers` 仍是双锤参考身份，不能登记为盘古完成。
