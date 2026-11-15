# 正常画面保存与 Android ABI 续接：2026-11-15

## 本次范围

从远端 `codex/fighter-visual-acceptance-20261113-1200` 的
[`8f74a82142526ec1a686052daf2a995274e88209`](https://github.com/wuyong9494-lab/kriswu/commit/8f74a82142526ec1a686052daf2a995274e88209)
续接，原树为 `2ea0745c12eef85db2649656267816b1dc3b41d7`。
本批补齐中断时未提交的截图保存与安装 ABI 改动，不修改游戏资源和 App 运行时代码。
本文件描述实现及执行范围；新的远端执行结果必须另记，不预先登记通过。

## 沿用已有结果

| 已有运行 | 可确认结果 | 不能据此确认 |
| --- | --- | --- |
| [Apple 43683433407](https://github.com/wuyong9494-lab/kriswu/actions/runs/43683433407) | 唯一原生首帧准备方法结构化 1 通过；两张有限离屏原图已有证据 | 正常窗口、完整视觉、性能或真机通过 |
| 同一运行的 UI | 控制台报告唯一方法通过，耗时 318.146 秒；总进程在 360.402 秒退出码 124，结果包未正常完成 | 结构化 UI 通过、六张预期 UI 原图已经封存 |
| [Android 43684677689](https://github.com/wuyong9494-lab/kriswu/actions/runs/43684677689) | 模拟器开机、原 APK 安装、Activity 启动被接受；实际 ARM64 Unity 路径随后 SIGILL | 客户端完整初始化、盘古索引或资源取得 |

详见本目录对应两次运行的 JSON 和 Markdown。成功方法不在本次重复选择；
`completed`、`skipped` 和证据解封成功均不作为玩法或视觉通过。

## iOS：正常窗口截图即时保存

新增独立 UI 方法
`ArenaFlowTests/DuelNormalFrameCaptureTests/testSunPracticeCapturesTwoNormalWindowFrames`。
通过真实入口选择孙登并进入练习，确认正常横屏、两名角色与攻击控件就绪，
取得两张相隔至少一秒的 `XCUIScreen` 原始 PNG。流程不复跑原先较长的技能与双角色切换方法。

截图与报告先写入该次 Test Runner 的独立目录，再作为 XCTest 附件保存。
采集身份包含源提交、run、attempt、模拟器 UDID 和随机 nonce；每张图保留原始字节数及 SHA-256。
后续按本次构建产生的 Runner 身份回收，不搜索或挪用旧运行的图片。
结果包收尾失败时仍尝试回收已写成的证据，但不会由此把 XCTest 失败改成通过。

两个截图是正常屏幕的证据，不等于画面已经验收。
报告不会虚构 UI 未暴露的帧号、动画 tick、音频播放或渲染准备计数。
正常像素、结构化 XCTest 结果、运行日志、人工视觉与物理设备分别记录。

本地新增采集专项 **12 项通过，0 失败**，覆盖结果包缺失时回收原图、
运行身份不符、残缺报告、损坏或额外图片、重复/跳过/错误方法、
两种 xctestrun 布局的 Runner 环境写回、日志时间范围及清理边界。
Swift 6.4.2 的语法解析通过；Linux 语法解析不代表 Apple 框架类型检查或模拟器执行通过。
安装身份核对同时包含 Debug 构建实际使用的 `.debug.dylib`。
封存失败会清理本次游戏资源与构建产物，保留有界诊断原件并报告失败。

## Android：核实原包自带的 32 位路径

保持原 APK、签名、API 30 镜像、SDK 许可与观察预算，使用普通
`adb install --abi armeabi-v7a` 选择原包自带的库。
安装后、唯一一次启动前，读取目标包的 `dumpsys package`，
仅当唯一且无歧义的目标包记录明确报告 `primaryCpuAbi=armeabi-v7a` 时继续。
这符合 Android 官方的 [安装 ABI 选择方式](https://developer.android.com/games/optimize/64-bit#install_and_test_your_app)。

安装参数本身不作为选择生效的证据。错误 ABI、缺失或重复字段、身份漂移、
不支持的设备以及安装失败均停止后续启动，并保留已经真实完成的阶段。
安装 ABI 与 Unity 实际加载 ABI 分开记录；客户端存活、初始化、目录缓存和 D19 文件取得继续独立验收。

新增 ABI 专项检查首次运行：**6 项通过，0 失败，0 跳过**。
这是本地契约检查，不能替代新的 Android 实际运行。

## 仍需完成的角色工作

当前已验证资源仍为原有 373 文件版本。刘泉纬仍报告
`liu_hammers / isPangu=false`；本批不能登记盘古专属装备、动作或完整音画机制已完成。
与本批分开的孙登空中眩晕运动问题正在独立复现，只有拿到复现与修复证据后才合并。

不上传 TestFlight，不公开解密密钥，不修改 Sites 正在处理的文件。
