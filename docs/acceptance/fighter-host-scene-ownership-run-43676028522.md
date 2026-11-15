# Host 场景所有权诊断：43676028522

**实际原生方法 1 PASS / 0 FAIL / 0 SKIP；UI 未选择、实际 0。** 两张原图在暂停的离屏隔离条件下可见，结论限于 `partial_diagnostic_only`，不构成生产渲染修复或发布验收。

## 执行与证据

- [运行 43676028522](https://github.com/wuyong9494-lab/kriswu/actions/runs/43676028522)，attempt 1；执行源 [`a7d5a4471433b88b348c87a3dc381e142bded89a`](https://github.com/wuyong9494-lab/kriswu/commit/a7d5a4471433b88b348c87a3dc381e142bded89a)，基线 `1efa361dbe454262e395221ba33b34d4779377d5`。后来分支移动不改变归属。
- 唯一方法：`SiteTests/DuelHostSceneOwnershipTests/testInstalledHostScenePreparationIsIsolatedAtFrameZero`，实际耗时 **61.307967 s**。Xcode **26.6 / 17F113**；**iOS 26.5 的 iPhone 17 Pro Max 模拟器**。xcresult 区间 UTC **2026-11-15 04:26:47.114—04:28:27.536**。
- 原生实际计数来自 xcresult。旧 117、5、6 及此前诊断均未复选；Android 的 16/14 项离线检查不并计。

## 两图的实际含义

测试在 World 构造前暂停游戏，截获一次自动 host prepare，未转发完成回调；仿真、时钟、正常 drawable 提交均为 0。原 Surface、模型、相机与 projector 保持，未创建 fresh renderer、重绑 scene 或调用 snapshot。

| 原图 | 唯一差别 | 人工观察 |
|---|---|---|
| `host-prepare-intercepted` | 尚未显式 prepare | 宫殿、孙出生姿态、刘双锤可见 |
| `host-world-prepared` | 同一 World SCNView 同步 prepare 一次 | 返回 true，耗时 **1.0257005 s**；图像完全相同 |

root 查看原 PNG，并逐文件独立核对摘要与像素统计；两图原始字节相同：每图 **956×440、725,797 B、42,580 种 RGBA、418,283 个非黑像素、2,357 个黑像素、透明像素 0**；共同 SHA-256：
`eef064aaa19c14e07ab5688f142b069675188922879d5dd0e0a2c8a74e146291`。

这说明 A 的隔离路径已可见，后续同步 host prepare 没有改变本次图像；尚不能据此确认唯一根因或直接背书生产改法。自动报告的 `pixels=PENDING` 原样保留，人工观察单列。未验证正常 drawable、实际 UI、声音、性能或真机；刘仍是双锤参考模型，非盘古。

## 日志与加密工件

producer 扫描 UTC **04:26:20—04:28:38** 的完整日志，**10,482,201 B / 7,938 条**；`doublePresent`、`textureAfterPresent` 均为 0。消费者仅验证认证回执与封存尾段，**未独立重扫完整日志**，不能扩大成“全部渲染错误不存在”。完整日志摘要为 `946f30e6afebdcd99a406e0e820c86055088412a03dabc162193f76de8cacbe1`。

[工件 14146209987](https://github.com/wuyong9494-lab/kriswu/actions/runs/43676028522/artifacts/14146209987)：**4,964,834 B**，SHA-256 `74fc13d930356e480b730dbceacd889f0077929881b74b1830f9ab609842a208`。root 唯一认证消费得到 **47 个 inventory 条目＋清单，共 48 文件**，无 failure 记录；身份、方法与附件闭包通过。报告附件 **15,375 B**，SHA-256 `16a78f0e42d43063aca46b22400c14b088505d9c7945f5b799c11bff34eaabe9`。

沿用 release `e5c0ccaeef85ce86c5b8fd4ee64524794d6556f5a561f4078362f6899bedf4e5` 的 373 文件；未上传资源新版本或 TestFlight。原图、媒体与密钥不公开。精确源文件、代码摘要和清理证据边界见[同名 JSON](fighter-host-scene-ownership-run-43676028522.json)。

已保留的一份[未修改原图](https://chatgpt.com/library?file_id=libfile_fde3_f-a00f9823b440819188c0ac7043c78432_34346a6e9f94819199b47bb8deaf05ae&account_id=personal)同时对应上述两个字节完全相同的捕获，来源仍分别按附件 manifest 绑定；未重复保存第二份相同图片。
