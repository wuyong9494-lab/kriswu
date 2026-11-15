# D19 官方 Android 客户端路线准备：2026-11-15

**状态：官方候选与 SDK 声明依赖已核实；客户端路线尚未执行。** 用户已授权官方资源的查找与获取，本文不增加 APK 下载批准要求。仍需单独确认的是接受下述确切 Android SDK 法律条款；资源获取授权不能代替许可接受。

本轮只读取一次官方 SDK 主目录，并复用已有镜像目录、前置报告和 APK 中央目录。SDK/镜像/APK 整包下载、SDK 安装、许可接受、KVM 变更、emulator 启动、APK 安装与启动、CI 触发均为 **0**。元数据读取不是软件归档下载，也不是运行通过。

## 固定候选与来源

| 对象 | 精确选择 | 官方归档声明 bytes | 官方声明 SHA-1 |
|---|---|---:|---|
| Linux Emulator | `emulator` **37.2.13**，Stable / `channel-0`，Linux 64-bit，build **16740729** | 349,658,551 | `f41f9e31eb5ca64926603c03265c50bbc0ff4172` |
| 系统镜像 | `system-images;android-30;google_apis;x86_64`，**r16**，Stable / `channel-0` | 1,438,186,618 | `6ae21030eaadc041078444d3798e4b399f3e787d` |

归档的实际下载 SHA-256 尚不存在，不以官方 SHA-1 或目录摘要替代：

- Emulator：<https://dl.google.com/android/repository/emulator-linux_x64-16740729.zip>
- 镜像：<https://dl.google.com/android/repository/sys-img/google_apis/x86_64-30_r16.zip>

上述候选取自官方元数据：

- [SDK 主目录](https://dl.google.com/android/repository/repository2-1.xml)：2026-11-15 00:03:39 UTC（北京时间 08:03:39）发起一次 GET，HTTP 200；384,394 bytes；SHA-256 `77fe1efa0850bc46a87a14e66dab802041277f2014a139a5c9df44608fd12b92`；响应 Last-Modified 为 2026-11-10 22:06:56 GMT。
- [Google APIs 镜像目录](https://dl.google.com/android/repository/sys-img/google_apis/sys-img2-1.xml)：复用已核实的 200,144 bytes 快照；SHA-256 `d48bd8404b8d5ab42d84cc0907dfb9e55c8a50194bb07c8a864c331375dd8b3a`。本轮未重复请求。

镜像唯一声明的 SDK 包依赖为 `emulator >= 30.8.0`；37.2.13 满足此下限，emulator 条目没有进一步的 SDK 包依赖。**这只完成两包的官方声明依赖闭包**，不证明宿主共享库、Java、KVM、图形能力或 ARM native bridge 已可用。Beta/Dev 候选不选用，也不自动升级渠道。

镜像＋emulator 的声明压缩字节合计为 **1,787,845,169**；加上下面的官方 19221 APK，为 **2,051,736,716**。展开磁盘、AVD 数据、客户端运行时下载与日志空间尚未核实，不把该压缩合计当成总资源上限。

## 唯一待确认的 SDK 许可

两份官方目录中，选定包均引用 `android-sdk-license`。解析后的许可文本逐字节相同，16,962 UTF-8 bytes：

- SHA-1：`efa68a6b3c661d18699d5c026771d5911cdc2f83`
- SHA-256：`1f8729233617b193fd619213792ae16a41b95d2bbbf525dfe66998252ba68b16`

Emulator 候选没有增加另一份许可文本，但这份文本尚未被本任务代为接受。[前置运行 43646462886](https://github.com/wuyong9494-lab/kriswu/actions/runs/43646462886) 的源提交为 `dba93a9e711fd510024de8cc7e53d1b7d7732100`：实际 SDK manager 为 12.0，emulator 与目标镜像缺失，确切许可摘要未接受，当前 runner 对 KVM 无读写权限。其 `completed/failure` 是阻塞证据，不是安装或启动成功。

用户确认确切文本后，只能通过[官方 sdkmanager 交互流程](https://developer.android.com/tools/sdkmanager)处理对应提示；不得手写 `licenses/` 接受记录，不使用 `yes` 批量接受全部许可。出现其他条款、账号或验证码时停止并交用户处理。镜像与 emulator 包路径本身不固定 revision，执行前仍须将安装选择绑定到本文的精确版本、归档及校验值；漂移时停止，不静默替换。

## 官方 APK 与 ABI 边界

主路线为 [Shadow Fight 3 官方首页](https://shadowfight3.com/) 的 `main.js` → `POST /rest/build/download/index` 已实际返回的：

<https://sf3assets.nekki.com/builds/apk/7/19221.apk>

已核实身份为 `com.nekki.shadowfight3`，版本 **1.46.0 / code 19221**，HEAD 声明 **263,891,547 bytes**。既有取材是 17 个互不重复 ranges，共 648,667 APK bytes；没有完整 APK。本轮没有新增 APK 请求。证据详见[官方远端索引记录](../fighter-pangu-official-remote-index-20261115.md)。

- AndroidManifest 成员：76,692 bytes，SHA-256 `4b009c7cfa57dace3c4affec9b6d8757bdadc5d3d2d90a47d3dd97b1af705171`。
- ZIP 中央目录：3,119 项，293,445 bytes，SHA-256 `abaebf457c31bd2bb5d2231225098afef0a9a3a41a45a0e28930dcb68539b583`。
- 目录包含 24 个 `arm64-v8a` 与 24 个 `armeabi-v7a` 原生库；`x86` / `x86_64` 原生库均为 0。完整 APK SHA-256、签名证书和实际 ELF 尚未验证。

因此 **API 30 x86_64 r16 能否正常运行该 ARM APK 仍未知**，须以实际镜像 ABI/native bridge、正常安装及唯一一次正常启动判断。不能把 KVM 或 emulator 开机成功当成客户端兼容，不更改 APK、伪造 ABI、额外注入 bridge 或擅自换镜像。RuStore 19226 不是本路线的 APK 身份。

## 后续执行与验收边界

复用现有官方工具，先核实际版本与能力，不重装已存在项或重跑旧 CI。缺失工具与宿主依赖如需补充，必须有精确包身份；许可确认后拟进行一次有界安装、一次冷启动与一次正常客户端启动。KVM 如需临时权限，只授本次 runner UID 并恢复，不扩大到所有用户。

正常客户端得到真实可读取目录之前，不猜 D19 下载 URL，不绕过账号、沙盒或证书校验。取得目录也不等于盘古模型、装备、动作与音画机制完成。后续应分别记录许可接受、包身份、镜像开机、APK 验签/安装/启动、可读取目录是否取得；任何一层不能代替下一层，更不能标为 iPhone 真机或 TestFlight 验收通过。
