# 已观测选角触点与客户端条款边界续接

## 基线和执行范围

本批以 [f47003c0c82b2ebe5d49f6940a7c3890bf8d8a04](https://github.com/wuyong9494-lab/kriswu/commit/f47003c0c82b2ebe5d49f6940a7c3890bf8d8a04) 为源码基线，树为 `8c801a9033e2effa9920ef97a7ffd4515d767d47`，已包含通过核心定向测试的魂魄眩晕运动修复及 rules 13。此后没有修改 App、Sources 或资源。

这次仅为上次明确失败的 UI 方法安排一次修正后的执行。Android 改动一并提交，但保留其独立触发消息，本批提交不会启动另一次官方客户端。TestFlight 继续暂停，Sites 文件不在本批范围。

## iOS：修正有证据支持的自动化触点问题

[run 43686860033](https://github.com/wuyong9494-lab/kriswu/actions/runs/43686860033) 在 `sun-selected` 失败，1 方法、0 通过、1 失败、0 跳过；原图 0。其原生构建、安装身份和正常写成的结构化失败结果已分别记录在对应报告。

本批保留同一 UI 方法、12 秒选角确认、练习场就绪条件和 360 秒进程预算，改变的是触点产生和现场保存方式：

1. 保存大厅原图，再读取同一次 accessibility snapshot 内的唯一孙登按钮、所属窗口及 App root 实际位置；文字 frame 存在时使用其中心，否则使用已观察到的按钮中心。
2. 拒绝重叠、越界、无效或陈旧几何；只发出一次普通界面触控。孙登必须随后显示“已选择”，刘泉纬显示“未选择”，才允许进入练习场。
3. 写盘前只记录尚未调用的 intent。写盘完成后紧邻点击重新检查两秒新鲜度，中间没有同步 I/O 或额外 UI 查询。`intent / called / returned` 与真实调用次数、时间戳分别记录；未调用的意图不能算作已点击。
4. 大厅预触点图和失败图在 schema v2 中单列为 diagnostic，不能充作两张正常练习场图。失败 PNG 已写入后若仅报告写盘失败，不再同时将它登记为“截图不可用”。

这些是对失败交互和证据缺口的修正，不能提前认定 App 的选角算法或渲染存在某个已证实缺陷。两张正常窗口图仍必须在真实练习入口完成后取得、按各自原始字节验证，并另行查看像素。

离线检查首次运行 15 项通过；随后独立审查发现并修复写盘与新鲜度时序、失败图片记录两处问题，只执行 4 个受影响或新增专项，全部通过，没有重复运行 15 项全套。最终 Swift 语法解析通过，另由独立审查者静态核对。Linux 检查不能替代随后 Apple 原生执行。

## Android：补齐 Unity 画布条款识别

[run 43686859870](https://github.com/wuyong9494-lab/kriswu/actions/runs/43686859870) 已确认 ARMv7 安装和客户端启动，实际进入未同意的游戏条款页。12 份 XML 没有可读文字，所以旧界面树检测遗漏了该页；这不是目录是否存在或网络失败的证据。

新增 fallback 读取当前目标包唯一 PID 的有界日志，并再次核对该包唯一 PID。只有前后 PID 相同、日志行来自同一 PID、严格匹配已见的 W/Banzai 未确认条款消息时才停止。证据记录包含引用日志、摘要和进程回执；不进行勾选、点击继续、登录或权限变更，全部读操作共享原有观察截止时间。

新增 6 项专项全部通过，0 失败、0 跳过。解析器在已恢复的真实 logcat 上只读命中第 78 行；换成其他 PID 不命中。此处没有新的 Android 执行，也不声称盘古 catalog 或 D19 已取得。

将来读取新版本 Android 工件时，消费者还需独立验证新增 `terms-logcat-N`、`terms-pid-after-N` 的 deadline 回执、前后 PID 和 marker；仅更新 helper 哈希不足以接受新证据。

## 游戏条款的可复核来源

本次已从现存 English TextAsset 的完整字段中定位条款正文。其成员长度和 CRC 与官方 19221 索引相符，官方 ResourceManager 绑定和截图可见段也匹配；没有将 CRC 比对夸大为两份独立下载的 SHA-256 相等。提取正文和游戏本地化资源没有提交到公共仓库。

条目列出的准确官方链接已逐一打开：

- [License Agreement](https://nekki.com/en/legal/license_agreement/)
- [Privacy Policy](https://nekki.com/en/legal/privacy/)（当前跳转至官方 privacy_policy 页面）
- [Rules of User Support Service](https://nekki.com/en/legal/russ/)
- [Game Rules](https://nekki.com/en/legal/game_rules/)

新游戏条款没有被接受。先前针对精确 SDK 文本的授权不登记为此项协议的批准。本次仍为 `liu_hammers / isPangu=false`，没有新增 D19 文件。

## 结果记录原则

旧失败结果保持原样，不回写为通过。后续 UI 结果须绑定新的实际源提交、run、attempt、模拟器及原图摘要另记；不把历史原生通过、证据解封成功或工作流跳过计入本次成功方法数。
