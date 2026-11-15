# Android run 43694073878：授权后实际执行与提前停止修复

## 本次实际结果

[运行 43694073878](https://github.com/wuyong9494-lab/kriswu/actions/runs/43694073878) 使用提交 `adecac3876565403d217e8ea543bb2bc64c4f4ff`，attempt 1。本次已获得对这个运行、受保护环境和 I AGREE / CONTINUE 各一次的明确授权，环境审批实际完成。固定图像依赖、SDK、APK 校验、ARMv7 安装及一次启动均完成；观察步骤失败，证据封存、上传和清理成功。没有上传 TestFlight。

工件 `14154233145` 共 4,942,769 字节，SHA-256 为 `c0a52535fbf82cd6f3a420105c15b216e99f4705efe128bc0f8a55e92fcc55f7`。只下载一次并完成认证恢复，共 139 个 inventory 条目。恢复成功不表示客户端目标成功。

## 两个已经证实的判断问题

实际观察只有 **5.746 秒**，在第一次条款操作的前置检查中以 `terms_process_or_foreground_changed` 停止。两张原始 PNG 内容完全相同，均为 **Nekki 启动画面**，尚未显示条款控件。其尺寸为 1920 × 1080、每张 1,250,002 字节，SHA-256 为 `481105403b84f029489726b1924d50150241dbe8532257424e0f751d29efb49f`。

第一处问题是把同 PID 的未确认条款日志当成当前画面就绪信号。日志出现时仍处于 splash，不能据此开始点击流程。后续应等本轮普通 snapshot 的原始 PNG 精确命中已经核对的条款 reference，才启动新的现场截图和输入检查；其他画面只在原有预算内继续观察，不点未知控件。

第二处问题是焦点字段来源错误。前后唯一目标 PID 均为 5361，resumed activity 也匹配目标 App；`dumpsys window windows` 的输出没有 `mCurrentFocus`，而前后的 `dumpsys activity activities` 输出各有一个、且均指向同一目标 App。现有证据没有证明 App 切走；实际停止来自代码在不包含该字段的输出中查找焦点。

## 条款操作没有执行

第一项 action 的 `input` 为 null，两个 `inputReservations` 都为 0，认证 inventory 中没有任何 `consent-*-input` 日志或进程回执。对应源码在进入输入方法前退出。这些相互一致的证据支持本次没有发出条款输入，不能仅用 producer 的保守 false 字段代替该判断。

用户已授权这两项操作，与客户端是否实际收到点击是两件事。本次没有勾选、继续、进入大厅、战斗或完成初始化；也没有取得 D19 文件。

## 新增运行时事实与缓存边界

包管理记录确认 `primaryCpuAbi=armeabi-v7a`。本次目标 PID 5361 的 Unity 运行日志第 150 行也报告 CPU 为 `armeabi-v7a`；这是 App 自身运行日志的 ABI 声明，独立于安装选择，不能扩大为完整初始化或稳定性验收。保留日志中未见 SIGILL、Fatal signal 或 FATAL EXCEPTION，观察窗口仅覆盖上述短时启动过程。

普通缓存目录仍返回 exit 1 / Permission denied，取得文件数为 0。这既不能确定目录是否存在，也不能确定 App 自身访问该目录的权限；没有通过 root、run-as 或权限修改绕过它。

## 后续边界

只修正上述已有证据支持的画面就绪与焦点来源，保留原 12 次采样、180 秒观察截止时间、一次 launch、两次输入各至多一次以及 37 × 37 复选框内部像素变化规则。先完成受影响的轻量检查，再准备有明确源码和运行标识的待审对象，不重跑这个已消费的运行或重新下载其工件。刘泉纬继续为 `liu_hammers / isPangu=false`。
