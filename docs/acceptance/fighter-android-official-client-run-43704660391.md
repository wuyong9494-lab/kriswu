# Android run 43704660391：两次条款操作完成，加载中 SIGILL 后返回桌面

## 实际结果

[运行 43704660391](https://github.com/wuyong9494-lab/kriswu/actions/runs/43704660391) 使用源码 `c522fed95e22c105a7e90caccd81ff9e0e4709a1`、tree `f1885954bda3fe725d443069ed5669832f5b60fe`，attempt 1，job `132783042164`。用户明确授权了这个运行的 `fighter-private-assets` 审核、I AGREE 与 CONTINUE 各一次以及初始化和普通缓存观察；本次环境审批实际完成一次。**两项输入各执行一次；原图显示复选框已勾选，CONTINUE 后条款弹窗消失。客户端随后在加载中发生一次 SIGILL，返回 Android 桌面，没有进入大厅。** 未上传 TestFlight。

客户端步骤在北京时间 2026-11-15 18:43:30 至 18:46:57 之间执行，一次 Activity 启动开始于 18:45:48。SDK 准备、固定 APK 校验、ARMv7 安装和一次启动成功。普通观察保存 `screen-00` 至 `screen-04` 共 5 张原图，实际持续 **62.094409 秒**，以 `app_process_unavailable` 停止；没有用完原有 180 秒、最多 12 次采样的上限。客户端步骤及整体 workflow 为 failure；证据封存、工件上传和清理均成功。

加密工件 `14158173429`，名称 `fighter-android-official-client-43704660391-1-encrypted`，为 **10,193,361 字节**，SHA-256 `6bfc51b6247905c58e558ed105413a19dbf4462373d6d42f6e627856b348f750`。它只下载和认证恢复各一次，**202 个 inventory 条目**通过校验。消费程序正常退出 0；没有重跑客户端、再次下载工件或修改原始恢复结果。完整结构化记录见[同名 JSON](fighter-android-official-client-run-43704660391.json)。

## 两次输入均有实际进程回执

| 项目 | I AGREE | CONTINUE |
| --- | --- | --- |
| 输入预留次数 | 1 | 1 |
| 实际输入进程回执 | 1 | 1 |
| called / returned / completed | 全部 true | 全部 true |
| 进程结果 | exit 0 | exit 0 |
| 固定坐标 | `(428,869)` | `(1444,874)` |
| 实际进程启动距新鲜截图开始 | 1.458403 秒 | 1.627544 秒 |
| 进程完成时距绝对截止期限 | 尚余 2.738244 秒 | 尚余 2.368018 秒 |

I AGREE 的实际进程开始于 monotonic `240.554435819`、结束于 `241.357788845`，绝对截止时间为 `244.096033308`。`consent-agree-input-process.json` 为 481 字节，SHA-256 `b222987e4388bc12f3d32bb616b2c07d059a21d845f485509f154694014e3a29`。

CONTINUE 的实际进程开始于 monotonic `243.31323633`、结束于 `244.317673925`，绝对截止时间为 `246.685692257`。`consent-continue-input-process.json` 为 480 字节，SHA-256 `0980a5449e7b70ab75001b4be189c62a16a48039a08fdf1b165e0665de13bcc6`。两份输入输出都为空且对应回执完整；没有缺少 process receipt 的 UNKNOWN 输入。

两项动作合计 12 份身份探测证据的原始日志与进程回执全部对应，exit 均为 0。四次前后 PID 探测都只有 **5299**；activity dump 中唯一的 resumed activity 与 current focus 均属于固定游戏 Activity。直到 `screen-02` 整张原 PNG 精确命中已审未勾选条款参考，才进入独立新鲜截图检查。第二项操作同时通过完整 51 × 50 控件的已审勾选 RGBA 精确匹配，以及控件外整帧像素不变检查。

原 producer/consumer 的 `checkedStateVerified=false`、`termsAccepted=false`、`userConsentConfirmed=false` 等保守字段保持原样；人工原图复核另行确认“复选框已勾选”与“CONTINUE 后条款弹窗消失”。本轮明确用户授权、实际输入执行、可见 UI 变化分别有证据；没有额外读取条款接受的持久化或服务端状态，更没有把这些结果合并为客户端初始化成功。

## 原图与实际界面顺序

以下均为原始 PNG 字节，未重编码或修改：

| 原件 | 字节数 | 尺寸 | SHA-256 |
| --- | ---: | --- | --- |
| `consent-before-agree.png` | 829,690 | 1920 × 1080 | `a5eeeefabb52a01991def1f4f317b6ed05ca3114c9a39ad6890ab6defadffbf8` |
| `consent-before-continue.png` | 830,643 | 1920 × 1080 | `0549a00a7d97023125f8d4a47dd018ab2646c0975b1aa43da3cdcb6152642c08` |
| `screen-03.png` | 1,433,764 | 1920 × 1080 | `497ec886e520bbce07c01aaeb5d1ed40eaf72b9d4f603a9c9394ca9c7c7354f8` |
| `screen-04.png` | 520,891 | 1080 × 1920 | `a80b16a4a67526897b82367cc62ad51fb23b4e377abdd33060163a3528d43587` |

`screen-00` 为 Nekki splash，`screen-01` 为 Shadow Fight 3 加载画面，`screen-02` 为未勾选条款页。两张 consent 原图依次显示空框和黄色实心勾选框。独立比较得到 **2,400 个变化像素**，全部位于半开矩形 `[403,844,454,894)`，即实际控件的 **51 × 50** 区域；控件外 **0 个像素变化**。

已勾选控件的 10,200 字节 RGBA 内容 SHA-256 为 `5c542af55905a181971f6b3b217be9acb7a0bc5821cecd1673a8ede70f7a8aa1`，精确匹配前一运行已经审阅的控件。将完整控件区域置零后，前后整帧 RGBA 都得到 `a6212969622abd0e18c5b7ff2d523b123c9a9d15bb1bf79b0fc472833bd43c8a`。上轮控件检查修复已在本轮实际执行中通过，第二项输入没有再被同一问题拦截。

CONTINUE 后，`screen-03` 显示条款弹窗已经消失，游戏仍为加载画面；该帧具有同一游戏 PID，进入 producer 的 `postInputObservation.samples`。随后保存的 `screen-04` 显示竖屏 Android Launcher 桌面；对应 `app-pid-4` 返回 exit 1、空输出，因此这张终止原图没有被算入“同一游戏进程”的后续样本。由此，后续原始截图是 2 张，而 producer 注册的同包后续观察样本是 1 个，两个计数不能混用。

## 新停点：加载中的一次 SIGILL

`official-app-logcat.log` 为 **12,089 字节**，SHA-256 `35dfd9e2eb3185afd63f9c6cdb0672ed1b07c507ca61f581ec72eb0ab2b71211`。同一个游戏 PID **5299**、TID **5383** 的日志先在 UTC `10:46:28.546` 记录 `TermsOfUse` 图层 Clear，随后出现 V8 initialized、Isolate initialized 与 JS Init params。UTC `10:46:43.052` 出现 crash header，接着记录 **signal 4 / SIGILL、code -6 / SI_TKILL**。

日志保留的 backtrace 只有一帧：`#00 pc 00028f44 <anonymous:37580000>`。CRASH 与 libc 的多行 SIGILL 是同一次崩溃的连续记录，**本报告计为一次观察到的崩溃**。这份匿名栈不足以定位具体库、指令或转换器根因。V8/JS 初始化日志只说明执行曾到达这些阶段，不能据此确认游戏、资源或大厅初始化完成。

崩溃后，下一次游戏 PID 探测为空，原图也已回到 Launcher；这些证据共同解释 `app_process_unavailable`。本轮不是又停在条款识别或第二次输入前，也没有发起第二次 launch。

消费报告保留的 `unclaimed_unconfirmed_terms_marker_requires_review` 只涉及**输入前**第 0、1 次采样的历史 marker；最新前置 claim 正确绑定第 2 次采样。它不是 CONTINUE 后协议被再次拒绝的证据。

## ABI、普通缓存与验收边界

包管理记录确认本次安装使用 `armeabi-v7a`。本次同 PID 的 crash header 还独立记录 Unity `6000.3.11f1`、`il2cpp`、CPU `armeabi-v7a` 和 ABI `arm`，因此这些运行时字段可以作为本轮独立观察列出。原 consumer 的 **`runtimeABIConfirmed=false` 保持不变**；部分代码已运行与完整运行时兼容通过是不同结果，且本轮确实随后崩溃。

普通 shell 仅对固定路径 `/sdcard/Android/data/com.nekki.shadowfight3/files/gamedata/Resources/Configs` 执行一次 `ls`，返回 exit 1 / **`Permission denied`**。没有取得文件，没有 stat/pull，未使用 root、run-as、权限修改或目录遍历绕过限制。该结果只证明本次普通 shell 读取被拒绝，不能确定目录是否存在、App 自身是否能访问，也不能据此归因网络故障。

本轮可读 catalog 文件 **0**，D19 文件 **0**；没有大厅、战斗、资源完整加载、模型/动作/装备身份、帧率、音频或真机验收结果。两次条款输入已完成且条款 UI 已移除，但客户端目标尚未完成。

## 唯一恢复、封存与清理

消费程序为 `recover-android-reviewed-checkbox-private.py`。原已审版本 158,105 字节，SHA-256 `a6be55edc78a808fb162a62b793279c744d7c99555de4386431847288cb618fd`；仅填入 4 项实际工件常量后为 158,211 字节，SHA-256 `03acb2a98d0b453c89e30faaac55ec876078412184e636cb0a4f917bdecc0c6e`。其余 AST 一致，唯一消费执行退出 0，认证解封与来源/库存校验成功；consumer 没有下载 SDK 或 APK，没有执行测试或启动客户端。

最终 GitHub job 的 seal、artifact upload 和 owned plaintext cleanup 三步均为 success。认证 producer 清理回执记录 `emulatorStopped=true`、`adbStopped=true`、`kvmRestored=true`，`errors=[]`。后续明文删除的依据是 GitHub 清理步骤成功，没有另行登录远端独立复查删除结果。

本报告只记录本轮实际结果；原 producer、consumer 输出和恢复证据均保持不变。未因整体 failure 准备或派发新运行，未上传 TestFlight。

## 对当前盘古角色状态的影响

本轮没有取得新的 D19 文件，也没有改变《裂隙对决》的角色配置。当前生产刘角色仍为 `liu_hammers / isPangu=false`；盘古机制代码已有实质实现，但专属资源、完整绑定和验收尚未完成。详见[盘古生产状态核查](liu-pangu-production-status-20261115.md)。
