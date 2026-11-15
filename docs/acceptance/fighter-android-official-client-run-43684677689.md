# Android 官方客户端执行结果：43684677689

**无窗口版本探针已实际修复，官方客户端首次完成开机、安装和正常 Activity 启动；随后 ARM64 原生执行路径出现未定义指令并以 SIGILL 退出，尚未取得 D19 启动索引。** 工作流结论仍是 failure，不将 Logo、安装成功或正常启动接受当成初始化完成。

## 固定执行身份

- 源提交 [`8f74a82142526ec1a686052daf2a995274e88209`](https://github.com/wuyong9494-lab/kriswu/commit/8f74a82142526ec1a686052daf2a995274e88209)，tree `2ea0745c12eef85db2649656267816b1dc3b41d7`。
- [Run 43684677689](https://github.com/wuyong9494-lab/kriswu/actions/runs/43684677689)，job `132722539224`，attempt 1。
- 公共作业日志窗口：北京时间 **2026-11-15 14:16:24—14:19:20**（UTC 06:16:24—06:19:20）。
- 完整的分层字段及摘要见[对应 JSON](fighter-android-official-client-run-43684677689.json)。

## 实际推进到的阶段

| 阶段 | 本次实际证据 | 范围 |
|---|---|---|
| 无窗口版本探针 | 一次 `-no-window -no-audio -version`，exit 0，约 0.100617 秒 | headless 版本命令可运行；没有安装宿主包或修改库路径 |
| SDK / APK / KVM | 精确许可、两 SDK 包登记、同一官方 APK 字节与签名、KVM 均通过 | 沿用批准范围；未更换 APK 或镜像 |
| 模拟器 | boot 1；API 30；实际 native bridge 为 `libndk_translation.so` | 设备开机成立，声明支持 ABI 不保证所有指令能执行 |
| 正常安装 | install 1，成功 | 当前未指定 ABI override |
| 正常启动 | launch 1；resolver 返回 `com.nekki.unityplugins.NekkiNativeActivity`；`am start -W` 为 Status ok | 冷启动被接受，首次 PID 为 5407；不等于持续运行或初始化完成 |
| 后续观察 | 17.104710 秒后 `app_process_unavailable` | 进程已消失，不是观察窗口正常结束 |
| 目录缓存 / D19 | 缓存文件 0、D19 新文件 0 | 普通 shell 路径未取得有效索引 |

探针前后 APK 下载、boot、install、launch 计数均为 0；它不计为开机。后续执行计数分别为 APK 下载 1、开机 1、安装 1、启动 1。`normalLaunchObserved=true` 只对应真实启动接受及初始进程观察，`officialClientFullyLoaded=false` 保留。

## 原图与退出日志

root 分别查看两张未修改的原 PNG：`screen-00.png` 为 1920×1080 的 Nekki 启动 Logo，`screen-01.png` 为 1080×1920 的 Android 桌面。没有看到协议或登录界面，也没有点击同意或登录；这些截图不能证明大厅加载完成。

实际 `official-app-logcat.log` 为 **40,839 B**，SHA-256 `4b0a31b83f63acbca9a94462463a63160acb76de956bc8b2cbad3522e947c518`。日志顺序为：

1. 初始化 `NDK translation (aarch64), version 0.2.2`。
2. Unity 6000.3.11f1 / IL2CPP 明确记录 CPU `arm64-v8a`，随后崩溃头记录 ABI `arm64`。
3. 北京时间 **14:19:06.689**，`ndk_translation` 报告 `Undefined instruction 0x5ee1b901`。
4. UnityMain 紧接着收到 SIGILL；栈 #00–#03 均在 `lib/arm64/libunity.so`，首帧相对偏移 `0xa9b308`，Unity Build ID 为 `83c8828ffe8996adaf7ba658122aa8d7f487b8f6`。
5. 栈 #04 为 `libnative_bridge_vdso.so`；**14:19:07.256**，libc 报 Fatal signal 4。

这证明本次实际运行 ARM64 翻译路径，并出现上述指令错误及原生退出。尚不能据此认定完整根因，更不能擅自归因为反模拟器行为。APK ABI 声明、安装 ABI、实际加载 ABI与完整运行成功是四层不同证据。

## 最小后续候选

同一已核 APK 含 24 个 ARM64 和 24 个 `armeabi-v7a` 原生库；本次设备的实际 `abilist32` 包含 `armeabi-v7a`。Android 官方文档支持通过正常的 [`adb install --abi`](https://developer.android.com/games/optimize/64-bit) 选择 ABI。因此下一候选只选择该 APK 自带的 32 位路径，保持 APK、签名、镜像、许可、观察预算及安全边界不变。

安装后、唯一启动前必须只读核对目标包 `primaryCpuAbi=armeabi-v7a`。API 30 的 [NativeLibraryHelper](https://android.googlesource.com/platform/frameworks/base/+/android-11.0.0_r1/core/java/com/android/internal/content/NativeLibraryHelper.java) 明确存在 multiArch 忽略 override 的分支，所以安装 `Success` 和命令参数本身不足以证明选择生效。缺失、冲突或仍为 ARM64 时立即停止，保留已安装事实，不自动换更多参数或反复启动。

**该候选尚未执行，32 位仍可能发生兼容性问题。** 不修改或重签 APK，不改系统镜像，不提权读取，不猜测资源地址，也不绕过客户端条款。

## 证据、检查与清理

[加密工件 14149609718](https://github.com/wuyong9494-lab/kriswu/actions/runs/43684677689/artifacts/14149609718)：**2,759,705 B**，SHA-256 `445ea041e72f2acc692a6eaa5f6ed60b30b9e5d22863cb22a8085c9133d6512c`。仅一次下载与认证解封；127 个 inventory 条目加清单共 128 个认证文件。消费者记录 `client_observation_stopped_at_boundary`，没有把恢复证据成功当成客户端成功。

新增 producer 4 项、consumer 3 项轻量检查分别首次通过；没有重跑旧成功检查，也没有将这些检查计为角色原生方法。封存前自有模拟器、ADB 与 KVM 清理均确认成功；后续远端明文删除未由本地消费者独立复查。

刘泉纬仍是 `liu_hammers / isPangu=false`，盘古仍缺 11 个原动作文件、12 个 aliases 与 5 类装备。该 Android 运行没有执行 Apple 方法、上传游戏资源或 TestFlight；物理 iPhone、音画与性能仍未验收。
