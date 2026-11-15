# Android 官方客户端后续：43676984599

**注册桥编译问题已经修复；当前运行仍为 failure / blocked，停在官方 SDK 许可显示文本校验。没有下载 SDK 大包或 APK，没有启动模拟器或客户端。**

## 精确来源与实际结果

执行源 [`3ac0d950948cede934ff52b45664b1225261a27d`](https://github.com/wuyong9494-lab/kriswu/commit/3ac0d950948cede934ff52b45664b1225261a27d)，tree `afb4529d790f5bc8a64f9b94fc81328178482f01`；[run 43676984599](https://github.com/wuyong9494-lab/kriswu/actions/runs/43676984599)、job `132699201034`、attempt 1。实际 Java 编译退出 0、耗时 0.903703 秒；它仅证明 CLI 12 API 编译兼容，登记桥尚未执行，packageCalls=0。

官方许可对话实际 review=1、接受=0、拒绝=4。Google TV、Google XR、ARM DBT 与显示出的 SDK 许可均回答 n；程序随后以 `displayed_approved_license_text_mismatch` 停止。没有接受额外协议、手写许可记录或继续取得归档。

## 已批准原文与实际显示版

| 版本 | 字节 | SHA-256 |
|---|---:|---|
| 用户已批准、两个固定 catalog 引用的原文 | 16,962 | `1f8729233617b193fd619213792ae16a41b95d2bbbf525dfe66998252ba68b16` |
| 本次 sdkmanager 实际显示版 | 16,960 | `aaf80cd0aee7e569ffa8a4be1b61189c0fefccf23068e38dfafe336289b8c723` |

root 对原 bytes 逐处比对，只有 6 处空白差异：原 offset 3182 删除一个空格；11059、11124、11167、11350 的换行替换为空格；16961 删除末尾换行。按这六个固定位置替换，可逐字节重建实际显示版，所有文字与标点一致。完整 SHA-1、变化的原位置和 hex 记录见[对应 JSON](fighter-android-official-client-run-43676984599.json)。这不是简单 strip，也不是条款文字变更。

用户对同一条款的授权继续存在；实际 SDK 接受仍为 false。本运行没有验证后续格式兼容修正。后续实现必须保存原文批准身份，并仅接受有完整摘要和精确映射证明的显示版；不得泛化成任意空白归一化、接受所有同名许可或手写 acceptance hash。

## 证据与未执行范围

[加密工件 14146698166](https://github.com/wuyong9494-lab/kriswu/actions/runs/43676984599/artifacts/14146698166)：697,985 B，SHA-256 `694279b088f00cfb0877eab250b1460c6f59dffc80c18ed2d79b268238f7c240`。root 唯一认证消费，22 个 inventory 条目，消费者 issues=[]，清理回执完整。公开 job 日志 21,818 B，SHA-256 `f5d717d1dbc0fca6e03da69077a9156cf8c191b60e58d060e724afa0901f1725`。

Emulator / image archive 下载为 0 / 0，APK 下载、安装、模拟器开机、客户端启动均为 0；没有截图或启动缓存，D19 新文件为 0。没有重复执行原 16/14 离线成功检查或旧 Apple 方法，没有上传角色资源版本或 TestFlight。刘泉纬仍为双锤参考身份，盘古资源缺口与物理 iPhone 验收没有因编译通过而完成。
