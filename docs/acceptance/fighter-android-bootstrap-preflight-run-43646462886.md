# Android 官方客户端取材前置检查：43646462886

本次是真实运行的只读环境诊断。结论为 **blocked / failure**，没有启动模拟器或 APK，没有取得 D19 新资源。

## 运行身份

| 字段 | 实际值 |
|---|---|
| 源提交 | `dba93a9e711fd510024de8cc7e53d1b7d7732100` |
| Actions | [43646462886](https://github.com/wuyong9494-lab/kriswu/actions/runs/43646462886) |
| Job / Attempt | `132605274205` / `1` |
| 时间 | 北京时间 2026-11-15 06:08:05—06:08:18 |
| 系统 | Ubuntu 24.04.5，runner image `20261111.127.1` |
| 工作流 | `.github/workflows/fighter-android-bootstrap-preflight.yml` |
| Helper | `.github/scripts/fighter-android-bootstrap-preflight.py` |

## 已执行结果

固定官方 [Google APIs 镜像目录](https://dl.google.com/android/repository/sys-img/google_apis/sys-img2-1.xml) 读取一次，200,144 B；SHA-256 `d48bd8404b8d5ab42d84cc0907dfb9e55c8a50194bb07c8a864c331375dd8b3a` 与审查目录一致。未下载系统镜像或 emulator。

选择包为 `system-images;android-30;google_apis;x86_64` revision 16，镜像 `x86_64-30_r16.zip` 为 1,438,186,618 B，SHA-1 `6ae21030eaadc041078444d3798e4b399f3e787d`，最低 emulator 30.8.0。该包的 `uses-license` 是 `android-sdk-license`，当前许可文本的 SHA-1 为 `efa68a6b3c661d18699d5c026771d5911cdc2f83`。未用另一版本的许可或历史摘要替代。

| 检查 | 真实观察 | 影响 |
|---|---|---|
| SDK manager | 可执行，元数据版本 12.0 | 可以识别已有工具，未调用安装 |
| Emulator | 未安装 | 无可启动的 emulator |
| API 30 r16 系统镜像 | 元数据及必需文件不存在 | 无可启动系统镜像 |
| 现有许可文件 | 文件存在，但不含当前精确许可摘要 | 未证明已接受该份许可 |
| `/dev/kvm` | 字符设备存在，当前用户无读写权限 | 加速能力未就绪 |

GitHub 的 `completed` 只表示诊断结束。此处 `conclusion=failure` 是明确的前置条件缺口，没有测试方法跳过后被计为通过。

## 边界与下一步

SDK 安装、许可接受、权限变更、emulator 启动、APK 启动、Apple 原生测试和 D19 新资源恢复数量均为 **0**。没有重新执行之前通过的测试，没有资源版本上传，也没有 TestFlight 操作。

官方客户端路线要继续，需要可使用的 emulator、符合该包要求的系统镜像、有效许可与实际可用的虚拟化环境。当前工作流仅报告现状，不会自动接受新的法律条款或修改 KVM 权限。补齐条件后才可进行一次受限的真实客户端启动，并从其实际返回的启动目录继续核验 D19；不猜资源 URL、不修改 APK、不绕过登录或资源保护。

真实客户端启动也不保证 D19 资源可用。独占模型、长斧、11 源文件、12 动作别名、5 类装备与技能音频仍须分别核对；`liu_hammers` 不能登记为盘古完成。

机器可读的运行结果见 [对应 JSON](fighter-android-bootstrap-preflight-run-43646462886.json)。
