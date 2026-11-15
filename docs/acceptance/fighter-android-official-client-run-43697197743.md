# Android run 43697197743：I AGREE 已勾选，CONTINUE 被像素检查拦下

## 实际结果

[运行 43697197743](https://github.com/wuyong9494-lab/kriswu/actions/runs/43697197743) 使用源码 `57655b2dd85310492e96cb2c6bda3e14316277c6`，attempt 1，job `132760265245`。用户明确授权了这个运行的 `fighter-private-assets` 审核、I AGREE 与 CONTINUE 各一次以及初始化和普通缓存观察；本次环境审批实际完成一次。**I AGREE 实际执行一次，原图显示已勾选；CONTINUE 没有执行，客户端仍停在条款页。** 未上传 TestFlight。

客户端步骤在北京时间 2026-11-15 18:18:54 至 18:22:02 之间执行。SDK 准备、固定 APK 校验、ARMv7 安装和一次启动成功；普通观察得到 3 次截图，实际持续 **38.721962 秒**，以 `terms_pixels_outside_checkbox_changed` 停止。客户端步骤及整体 workflow 仍为 failure；证据封存、工件上传和清理成功。

加密工件 `14157655500` 为 8,208,292 字节，SHA-256 `f37bf5b9297f02d5267fb2ef1926cd50077e6536bbb37f08b8ffacfac602a770`。它只下载和认证恢复各一次，184 个 inventory 条目全部通过。消费程序仅填入四项实际工件常量，其余 AST 保持原已审版本；没有重跑客户端或重新下载。

## 两次操作分别核对

| 项目 | I AGREE | CONTINUE |
| --- | --- | --- |
| 输入预留次数 | 1 | 0 |
| 实际输入进程回执 | 1 | 0 |
| 进程结果 | exit 0，returned/completed | 输入方法未进入 |
| 原图状态 | 空框变为黄色实心勾选框 | 条款页仍在，按钮尚未点击 |
| 最终停点 | 第一项输入已完成 | 新鲜截图的像素检查 |

I AGREE 的实际进程开始于 monotonic `232.667735343`、结束于 `233.672497954`，早于绝对截止时间 `235.70918898`。其原始进程回执为 479 字节，SHA-256 `5de56edab8e0a3036d28a458bc8a5377c83fb9235906db9b927360a0189c84bc`。该回执、空输出、动作记录与认证 inventory 一致；原图独立显示勾选状态。

CONTINUE 的前后 PID 与前台身份检查均成功，但 action 仍为 `checking_identity_and_image`，`visualRule=null`、`input=null`。认证工件没有任何 `consent-continue-input` 文件，源码在调用输入方法前退出。这些证据共同支持第二次输入未执行，不能仅根据保守的 false 字段得出这一结论。

原 producer/consumer 的 `checkedStateVerified=false`、`termsAccepted=false` 等保守字段保持原样；人工原图复核另行确认“复选框已勾选”。这没有把用户的授权、控件勾选、点击 CONTINUE 和客户端初始化合并为同一结果。

## 失败来自实际控件大于旧检查区域

两张 1920 × 1080 原始 PNG 均未重编码：

| 原件 | 字节数 | SHA-256 |
| --- | ---: | --- |
| `consent-before-agree.png` | 829,690 | `a5eeeefabb52a01991def1f4f317b6ed05ca3114c9a39ad6890ab6defadffbf8` |
| `consent-before-continue.png` | 830,643 | `0549a00a7d97023125f8d4a47dd018ab2646c0975b1aa43da3cdcb6152642c08` |

独立像素比较发现 **2,400 个变化像素**，全部位于半开矩形 `[403,844,454,894)`，即实际复选框的 **51 × 50** 区域。这个完整控件以外的页面、文字、CONTINUE、背景和进度条像素完全相同。旧规则只覆盖 `[410,851,447,888)` 的 37 × 37 内部，因而把其中 1,181 个正常的控件变化像素算成“框外变化”。本次错误有精确的原始证据支持。

已勾选控件的 10,200 字节 RGBA 内容 SHA-256 为 `5c542af55905a181971f6b3b217be9acb7a0bc5821cecd1673a8ede70f7a8aa1`。将完整控件区域置零后，前后整帧 RGBA 都得到 `a6212969622abd0e18c5b7ff2d523b123c9a9d15bb1bf79b0fc472833bd43c8a`。后续修复应精确匹配这份已核对的勾选控件，并保持控件外逐字节一致；不能只放宽矩形、接受其中任意变化。

## 上次两处修复已在真实运行中通过

`screen-00` 为 Nekki splash，`screen-01` 为 Shadow Fight 3 加载画面，直到 `screen-02` 精确命中已审条款原图才进入输入检查。实际 trigger PID 为 5385，两项 action 的前后唯一 PID 与 activity dump 中的 resumed activity/focus 均匹配。因此，“日志提前出现即误认条款画面”和“从错误 dump 查焦点”没有再次阻止本轮第一项输入。

消费报告保留的较早未认领条款 marker 提示，只涉及第 0、1 次采样里的历史日志；最新 claim 正确绑定第 2 次采样。旧日志仍存在，不代表额外点击或出现另一份条款。

## 缓存及资源结论

包管理记录确认本轮安装使用 `armeabi-v7a`。本轮保留的 App 日志没有 Unity CPU 字段，不能沿用上个运行的 ABI 日志声称本轮已取得同样的运行时声明。日志未见 SIGILL、Fatal signal 或 FATAL EXCEPTION，有限观察窗口也不构成稳定性验收。

普通 shell 对已知 Configs 缓存目录执行一次 `ls`，返回 exit 1 / `Permission denied`。没有取得文件，没有 stat/pull，未使用 root、run-as、权限修改或目录遍历绕过限制。该结果不能确定目录是否存在，也不能确定 App 自身能否访问它。

本轮未点击 CONTINUE，未进入初始化后观察、游戏大厅或战斗，未取得 D19 文件。刘泉纬仍为 `liu_hammers / isPangu=false`。后续只修正有实际证据的控件匹配问题，保留一次 launch、两次输入各至多一次、5 秒截图新鲜度、180 秒观察和 12 次采样上限；新的真实运行须有明确运行标识和环境审核。
