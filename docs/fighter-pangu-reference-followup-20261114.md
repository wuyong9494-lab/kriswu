# 盘古正式期面板补证：2026-11-14

本轮从新的原作者公开视频中读清了 **38 个游戏 UI 事实字段，其中 33 个为数值**。六级的 100 连击门槛已由正式期游戏面板直接确认；天坠冷却减半、连击多保持 3 秒、天坠授予 20 连击、15 秒 Trance，以及 Trance 的攻速和额外连击概率也已读清。

归一化参数和每字段证据见 [fighter-pangu-verified-reference-values-20261114.json](acceptance/fighter-pangu-verified-reference-values-20261114.json)。本文件补充旧报告，不修改旧报告的历史结论。**五级正式数字、光能承伤换算和若干触发边界仍未核实。**

## 1. 新的原始来源与版本范围

主来源为 Funny Games TV 的[原始 YouTube 实机](https://www.youtube.com/watch?v=Jkf6cRuIIkw)，同一作者的[公开 Rutube 上传](https://rutube.ru/video/f2d148ab0ce9f8d089a620b7ae373d9d/)提供了可严格限量读取的公开未加密视频分段。

YouTube 公开播放器记录的发布时间为 `2026-08-31T06:15:07-07:00`，时长 2235 秒。画面右侧明确显示套装已达六级，左侧分别展开二、四、六级的升级说明。**这是 8 月 31 日发布的录像证据；录制时间、客户端构建号和配置版本没有显示，不能自动视作 11 月 1.46.2 的当前平衡。** 俄文界面也不能单独证明所属发行区域或派系。

| 证据帧 | 原视频位置 | 清晰可见的内容 |
|---|---|---|
| F0044 | [00:44](https://www.youtube.com/watch?v=Jkf6cRuIIkw&t=44s) | 四级 Dread 伤害修正，以及下招强化、冷却缩减、Elden Storm |
| F0048 | [00:48](https://www.youtube.com/watch?v=Jkf6cRuIIkw&t=48s) | 二级连击门槛、风刃、原初回复光能、前岩和风状态 |
| F0052 | [00:52](https://www.youtube.com/watch?v=Jkf6cRuIIkw&t=52s) | 二级上挑伤害及挑起时间、下招石刺伤害 |
| F0060 | [01:00](https://www.youtube.com/watch?v=Jkf6cRuIIkw&t=60s) | 四级两个独立的 9 秒窗口、前岩附伤与眩晕、攻速门槛 |
| F0064 | [01:04](https://www.youtube.com/watch?v=Jkf6cRuIIkw&t=64s) | 六级保留连击、100 门槛、冷却、天坠强化 |
| F0068 | [01:08](https://www.youtube.com/watch?v=Jkf6cRuIIkw&t=68s) | 六级天坠及完整 Trance 数字 |

上述静帧为原始 1280 × 720 解码结果，没有生成或修补文字。JSON 记录了每张图的 SHA-256、尺寸、字节数、视频时点及解码 PTS。编码 PTS 比清单时间原点约多 0.151 秒，因此同时保留两种时间。

## 2. 六级：由正式期 UI 直接确认的数值

| 机制 | 本轮确认的值与含义 | 证据 |
|---|---|---|
| 连击保留 | 受伤不清空计数；比基础规则多保持 **3 秒** | [01:04](https://www.youtube.com/watch?v=Jkf6cRuIIkw&t=64s) |
| 高连击冷却 | **100 连击**后原初招式不进入冷却；同一门槛让天坠冷却时间**除以 2** | [01:04](https://www.youtube.com/watch?v=Jkf6cRuIIkw&t=64s) |
| 六级固定减冷却 | 原初招式再减少 **1 秒**冷却 | [01:04](https://www.youtube.com/watch?v=Jkf6cRuIIkw&t=64s) |
| 天坠回能与伤害 | 比基础天坠多累积 **25% 光能**、多造成 **50% 伤害** | [01:04](https://www.youtube.com/watch?v=Jkf6cRuIIkw&t=64s) |
| 天坠给连击 | 使用天坠给予 **20 点连击** | [01:04](https://www.youtube.com/watch?v=Jkf6cRuIIkw&t=64s) |
| Trance 时长 | 天坠激活后获得 **15 秒**状态 | [01:08](https://www.youtube.com/watch?v=Jkf6cRuIIkw&t=68s) |
| Trance 攻速 | 攻击速度提高 **12.5%** | [01:08](https://www.youtube.com/watch?v=Jkf6cRuIIkw&t=68s) |
| Trance 连击概率 | 每次成功攻击有 **50%** 概率额外获得 **1 点连击** | [01:08](https://www.youtube.com/watch?v=Jkf6cRuIIkw&t=68s) |
| Trance 防御和风刃 | 防御提高 **50%**；每次攻击唤出风刃 | [01:08](https://www.youtube.com/watch?v=Jkf6cRuIIkw&t=68s) |

“三秒”是额外保持时间，不是连击总保持时间。“光能增加 25%”是相对基础天坠的增幅，不是直接增加 25 个光能百分点。天坠冷却减半与原初零冷却是两条不同结果。

面板把天坠连击和 Trance 关联到“使用／激活”事件；本轮没有做完整动画逐帧计时，因此授予发生在起跳、蓄能或落地的具体帧仍未确认。Trance 的 **防御 +50%** 也没有提供防御到最终承伤的公式，不能据此写死承伤乘 0.5。

## 3. 四级：补齐此前两个窗口和攻速的缺口

| 机制 | 本轮确认 | 证据 |
|---|---|---|
| 下招后自身跳跃落地击倒 | 窗口 **9 秒** | [01:00](https://www.youtube.com/watch?v=Jkf6cRuIIkw&t=60s) |
| 下招后前岩强化 | 独立窗口也为 **9 秒** | [01:00](https://www.youtube.com/watch?v=Jkf6cRuIIkw&t=60s) |
| 强化前岩附伤 | 额外 **25% 徒手物理伤害基数** | [01:00](https://www.youtube.com/watch?v=Jkf6cRuIIkw&t=60s) |
| 强化前岩眩晕 | **3 秒** | [01:00](https://www.youtube.com/watch?v=Jkf6cRuIIkw&t=60s) |
| 原初冷却 | 固定减少 **1 秒** | [01:00](https://www.youtube.com/watch?v=Jkf6cRuIIkw&t=60s) |
| Elden Storm | **55 连击**，攻速提高 **12.5%** | [01:00](https://www.youtube.com/watch?v=Jkf6cRuIIkw&t=60s) |
| Dread | 目标承伤提高 **50%**、输出降低 **50%** | [00:44](https://www.youtube.com/watch?v=Jkf6cRuIIkw&t=44s) |

旧报告只能确认作者把某个 Earth 状态称为 9 秒。本次画面把两个窗口分别写明为 9 秒，因而可以各自填入来源明确的值。这里的 3 秒眩晕带有“先用下招，再在窗口内命中前岩”的条件，不能替代普通四级前岩的眩晕参数。

两个攻速条款各自显示 +12.5%；本轮没有确认 Elden Storm 与 Trance 同时存在时相加还是相乘。

## 4. 二级：新增伤害基数和挑起时间

| 项目 | 清晰 UI 数值 | 证据 |
|---|---|---|
| 重击风门槛／风刃 | **15 连击**；风刃为 **25% 暗影伤害基数** | [00:48](https://www.youtube.com/watch?v=Jkf6cRuIIkw&t=48s) |
| 原初招式 | 回合开始可用 **4 招**；成功命中回复 **15% 光能** | [00:48](https://www.youtube.com/watch?v=Jkf6cRuIIkw&t=48s) |
| 前岩 | **55% 暗影伤害基数** | [00:48](https://www.youtube.com/watch?v=Jkf6cRuIIkw&t=48s) |
| 风状态 | 持续 **10 秒**，自身伤害 **+50%**；每次攻击附带 **25% 暗影伤害基数**风刃 | [00:48](https://www.youtube.com/watch?v=Jkf6cRuIIkw&t=48s) |
| 风招式冷却 | 单独声明固定 **10 秒** | [00:48](https://www.youtube.com/watch?v=Jkf6cRuIIkw&t=48s) |
| 上挑 | **55% 武器伤害基数**；将敌人挑起 **0.5 秒** | [00:52](https://www.youtube.com/watch?v=Jkf6cRuIIkw&t=52s) |
| 下招石刺 | **45% 暗影伤害基数** | [00:52](https://www.youtube.com/watch?v=Jkf6cRuIIkw&t=52s) |

上述暗影、武器和徒手物理伤害百分比都有各自的伤害基数。**它们不是目标最大生命百分比，也不能直接转成绝对伤害。** “挑起 0.5 秒”没有把升空、悬停和落地分别计时，工程实现应保留这个区别。

风招式的固定 10 秒与高级条款中的减秒／零冷却同时出现在面板中；本轮没有验证它们的优先级。达到门槛时是否立即清除正在运行的冷却，也仍是独立的未知规则。

## 5. 五级与其余未读部分

本轮曾检查 01:00 至约 01:03.2 的原始分段，五级条目在可读画面中保持折叠，随后 01:04 已展开六级。没有据此取得五级的正式数字。现有测试期材料已经提供五级的机制结构；本轮不会把二级的 15、四级的 55 或六级的 100 移用为五级门槛。

新增事实 JSON 将五级原初回光、格挡回光、远程门槛和恢复系数继续写成 `null`。光能承伤换算、基础连击保持时间、三档风刃来源重叠次数、临界一击计点顺序、天坠授予状态的精确帧，以及防御到最终承伤的关系也仍保留为未知。

这些缺口分别属于数值未读出和判定规则未验证；`null` 不代表 0、禁用、永久或无限次。

## 6. 作者讲解与其他新增来源的使用层级

在读取清晰面板之前，同一 Funny Games TV 视频的[03:00—03:18](https://www.youtube.com/watch?v=Jkf6cRuIIkw&t=180s)作者讲解及公开自动字幕已报告“100 连击”后的连续使用表现。公开缩略图中也可见 106、113、132 等连击值。它们原先只能构成作者报告和场景观察；现在 **100 这一阈值由 F0064/F0068 的 UI 单独确认**，无需依赖自动字幕猜词。

另有两个本轮筛选结果：

| 新来源 | 可确认内容 | 限制 |
|---|---|---|
| [Arifo：盘古对高等级突袭](https://www.youtube.com/watch?v=dzQBj_x1-vo) | 播放器发布时间为 2026-08-28；00:45—01:20 的原始公开缩略图可见逐级升级直至六级 | 320 × 180 的文字不足以核实五、六级数字，未把模糊像素转成参数 |
| [A4Gamestech：标题称完整升级](https://www.youtube.com/watch?v=443O9bZW4uw) | 实际时长 221 秒；已检查画面显示角色对战盘古继承者 | 说明里的章节延伸到 10 分钟之后，且已检查画面不支持所声称的六级面板；不作为参数证据 |

这些筛选不会改动旧报告中已经注明的测试期占位符或来源冲突。

## 7. 获取范围与复核位置

本轮新源的有限读取总响应体为 **3,057,608 字节**，小于 **3,145,728 字节（3 MiB）**上限。其中包含公开播放器 JSON 129,915 字节、两份清单 44,109 字节，以及视频范围响应 2,883,584 字节。仅使用了 00:40—01:20 区间内的少量分段前缀；每次范围响应都核对了 206 状态、Content-Range、Content-Length。下载已经停止。

原始静帧留在本地复核目录：

`/workspace/scratch/a8e45fa27863/references/pangu-followup/`

文件名为 `fgtv-public-frame-0044.png`、`0048.png`、`0052.png`、`0060.png`、`0064.png`、`0068.png`，后五个也使用相同的 `fgtv-public-frame-` 前缀。仓库仅新增本事实说明与参数审计 JSON，没有提交视频片段、字幕、第三方画面或播放器临时地址。
