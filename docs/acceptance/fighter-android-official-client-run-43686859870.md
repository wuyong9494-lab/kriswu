# Android 官方客户端 ARMv7 实跑验收 — run 43686859870

本次 **ARMv7 安装选择与正常启动已成立；客户端进入官方 `TERMS OF USE` 页，停在尚未勾选 `I AGREE` 的新游戏条款边界**。未进入大厅，未取得可读 bootstrap catalog，未回收 D19 资源。证据恢复成功与客户端目标未完成分别记录，不能用 Actions 的整体 `failure` 否定已完成的安装和启动，也不能将 Activity 启动成功写成游戏完整加载。

## 执行身份与证据归属

- 实际源码：[3e3ee0ead3a22b37d62ab58e81580029e7588c1f](https://github.com/wuyong9494-lab/kriswu/commit/3e3ee0ead3a22b37d62ab58e81580029e7588c1f)。基线为 `1efa361dbe454262e395221ba33b34d4779377d5`。
- [Actions run 43686859870](https://github.com/wuyong9494-lab/kriswu/actions/runs/43686859870)，attempt 1；[job 132729042525](https://github.com/wuyong9494-lab/kriswu/actions/runs/43686859870/job/132729042525)，conclusion 为 `failure`。
- Producer 原始状态：`launched_without_readable_catalog`；原始 `failureReason` 未给出具体错误；`observation.stopReason=bounded_observation_complete`。
- [唯一加密 artifact 14151245127](https://github.com/wuyong9494-lab/kriswu/actions/runs/43686859870/artifacts/14151245127)：11,440,499 B，SHA256 `c642deece56dcfb928a56a652873552da4171fc43c6c7a4cdbed648689ee25cd`。本地已认证解封、核对源码身份和 216 个 inventory entries；连同 inventory 文件共 217 个文件，consumer `issues=[]`。
- 本报告只读复核这份已经恢复的证据。未再下载、启动、派发工作流或执行测试，未修改原图；原始私有证据未重新发布。

## 实际完成层级

| 层级 | 本次实际证据 | 结论 |
|---|---|---|
| SDK、镜像与 APK 前提 | SDK、KVM、镜像启动、签名完整性 gates 均通过；同一固定 APK 下载、镜像启动、安装、Activity 启动各一次 | 已实际执行通过 |
| ARMv7 安装 | `adb install --abi armeabi-v7a` exit 0；随后单一目标 package dump 的 `primaryCpuAbi=armeabi-v7a`，`secondaryCpuAbi=null` | 已独立确认安装选择 |
| 原生运行架构 | 此次保留 logcat 没有显式 Unity CPU 或 crash ABI 字段 | `runtimeABIConfirmed=false`，不从安装元数据推定 |
| 正常启动 | `am start -W` 返回 `Status: ok`、`LaunchState: COLD`；12 次 PID 查询均为 5123 | Activity 被系统接受，12 个采样点进程均存在 |
| 启动进展 | 原图从 Nekki splash 进入使用条款；日志记录 Unity/IL2CPP、初始化入口、本地化完成及 TermsOfUse 画布 | 已走到官方启动 UI；不等于完整初始化 |
| 大厅、战斗 | 12 张原图均未出现大厅或战斗 | 未验收 |
| catalog、D19 | 普通 shell 指定目录查询失败；回收 catalog 0、D19 0 | 目标未完成 |
| 封存与恢复 | seal、upload、cleanup step 成功；密文和 inventory 认证通过 | 证据恢复成功，与游戏目标分开 |

APK 固定为 `https://sf3assets.nekki.com/builds/apk/7/19221.apk`，包名 `com.nekki.shadowfight3`，版本 `1.46.0` / code `19221`，263,891,547 B，SHA256 `3653dc2cd2a43aef50d93f66f26a0093a8c63911cb965b8482ee8fcf68ebe5f9`。签名完整性已由真实工具输出支持；该结论不额外声称已独立认证发行方身份。APK 原字节不在这份证据内，本次只读审查未再次取得或重哈希 APK。

## 原图核对：真正停止位置

所有截图为未修改的 1920×1080 原图。审查者直接查看 `screen-00.png`、`screen-01.png`、`screen-03.png`；root 另外直接查看 `screen-11.png`。其余截图按逐文件重算的完全相同字节归类。

| 截图 | 字节数与 SHA256 | 可见状态 |
|---|---|---|
| `screen-00.png` | 1,250,002 B；`481105403b84f029489726b1924d50150241dbe8532257424e0f751d29efb49f` | Nekki 启动标志 |
| `screen-01.png`、`screen-02.png` | 各 829,690 B；`a5eeeefabb52a01991def1f4f317b6ed05ca3114c9a39ad6890ab6defadffbf8` | 官方 `TERMS OF USE`，`I AGREE` 复选框为空，显示 `CONTINUE` |
| `screen-03.png` 至 `screen-11.png` | 各 831,381 B；`07ac94d2b38d97cf712759fe2c5717a2f9c40c2f81495d23bf3fa86bd150b86d` | 仍为相同未同意条款页；另有 `User id: -1` 和 `CONTACT SUPPORT`，这九张逐字节相同 |

人工像素结论为 **`unaccepted_official_game_terms`**。原图只展示滚动文本框的上部片段，不能声称已取得或读完完整游戏条款。没有勾选同意、点击继续、进入账号或接受新协议的操作证据。

## 为什么 producer 写成 bounded_observation_complete

这次配置的是 **180 秒观察上限**，实际 `elapsedSeconds=160.869373735`，共 12 次采样，不能写成完整三分钟观察。固定源码的 `observe_client` 同时受 180 秒 deadline 与 `range(12)` 约束，采样循环结束后会写入 `bounded_observation_complete`。

12 份 UIAutomator XML 全部只有 Unity 容器节点，所有 `text` 与 `content-desc` 均为空：首份 6 个节点，其余各 5 个节点。源码 `wall_reason` 只检索这两个属性，所以看不到已在 Unity 画布上绘出的 `TERMS OF USE`。这是本次确证的边界检测遗漏，原始 stopReason 不回写，另附人工结论。[固定源码 helper](https://github.com/wuyong9494-lab/kriswu/blob/3e3ee0ead3a22b37d62ab58e81580029e7588c1f/.github/scripts/fighter_android_official_client.py)

可实施的最小后续修复是识别同一客户端 PID 的明确“条款尚未确认”日志或可信条款状态，在相同预算内保守停止，并保留独立像素核对。此报告不改 producer、不重跑，也不以自动勾选条款来修补检测。

## 日志支持的进展与限制

保留的 PID 5123 logcat 为 16,393 B，SHA256 `109af6863b74c6205dc9d3d0ad187f3733ed50cb61cfe0447992a666bbda19ee`，内容时间从 2026-11-15 06:47:46.983 UTC 到 06:49:17.803 UTC。它是观察结束后的该 PID 日志快照，并非全部系统日志或进程全生命周期跟踪。

| UTC 时间 | 留存事件 | 支持的结论 |
|---|---|---|
| 06:47:49.796 | `EnterPoint.Init FL:True` | 已执行客户端初始化入口 |
| 06:47:50.045、06:47:54.188、06:48:24.960 | `Terms of use not confirm!` | 与未同意条款原图一致 |
| 06:47:51.491 | `Network check round end: Available` | 当次启动网络自检报可用；不能推广为 catalog 下载成功 |
| 06:47:53.918 | 本地化 English 初始化完成 | 已越过仅显示启动标志的阶段 |
| 06:47:54.575 | 内置 config `1.46.0.0.16728-prod` 指向更新目标 `1.46.0.65.16748-prod` | 客户端报告了目标版本；未证明目标已下载、解码或包含 D19 |
| 06:47:55.751 | `caller=[TermsOfUse]` | 官方条款画布已打开 |

本次留存日志没有 `SIGILL`、`Undefined instruction` 或 `Fatal signal`，12 个采样点 PID 均未变；实际启动进展与此前 ARM64 运行在约 17.1 秒后 SIGILL 退出的结果不同。但这不等于已经证明旧故障的根因修复，也不等于独立确认运行时 ARMv7 架构、持续帧率、音频或长期稳定性。Google Play Services 版本过旧及 telemetry 警告存在，尚无证据将其认定为当前条款页的原因。

## 缓存查询：只陈述命令真正证明的事实

实际命令为普通 shell 对固定路径 `/sdcard/Android/data/com.nekki.shadowfight3/files/gamedata/Resources/Configs` 执行 `ls -1`。命令 exit 1，原始输出明确为 `Permission denied`；这不是从“没拿到文件”推测权限问题。证据为 `ordinary-config-cache-list.log`，100 B，SHA256 `9b9ffb1704d6d42e830b47ac4ce4dfd20ae9b968cb57f7c00a98413c3c370b5d`。

该结果只说明这次普通 shell 查询被拒，**不证明目录存在或缺失、不证明客户端自身无权访问，也不能解释为权限或网络导致了当前条款边界**。没有获得文件，所以没有可读 catalog、目录解码或 D19 回收结论；本次没有进一步访问应用私有目录或改变权限。

## 资源状态与下一项边界

本次新增 D19 文件为 0；项目既有状态仍是刘泉纬 `liu_hammers`、`isPangu=false`，缺 11 个动作原文件、12 个动作别名、5 类装备。这里的缺项来自既有资源清单，本次执行只证明没有新增回收，不能把画面中的官方人物或启动图当作项目资源已接入。

继续客户端交互前，需要先取得可复核的完整游戏条款或准确官方链接，再由用户针对这一新协议明确授权。先前 SDK 授权针对已展示的精确 SDK 许可文本，不等于批准此次首次出现的游戏 `I AGREE`。当前未接受新游戏条款，未派发新 run。

运行结束时 emulator、adb 均已停止，KVM 已恢复，cleanup errors 为空。Actions cleanup step 成功与封存时 owned-runtime 清理已分别记录；后续明文删除没有额外独立核验。未执行 Apple 测试，未上传游戏资源或 TestFlight，未追加历史通过计数。

完整机器可读字段、逐文件原始证据哈希和 12 次 PID/XML/截图记录见同名 JSON。
