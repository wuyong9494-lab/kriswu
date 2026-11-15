# 正常窗口采集实跑复核 — run 43689256803

**本次已经观测到孙登选中并进入练习就绪状态，但没有通过正常帧采集或 UI 测试验收。** 控制台明确记录 `invalidPNG`；外层在 360 秒预算后返回 `124`，含终止回收的记录时长为 367.046 秒，没有最终结构化 XCTest 计数。已恢复的是 **2 张诊断原图，正常帧 0 张**。

## 执行与证据身份

- 源码：[c0da35df68e7bbe7d40fbc83ad122268af48cfc6](https://github.com/wuyong9494-lab/kriswu/commit/c0da35df68e7bbe7d40fbc83ad122268af48cfc6)，基线 `f47003c0c82b2ebe5d49f6940a7c3890bf8d8a04`。采集提交未更改生产 App。
- [Run 43689256803](https://github.com/wuyong9494-lab/kriswu/actions/runs/43689256803)，attempt 1；[job 132736193487](https://github.com/wuyong9494-lab/kriswu/actions/runs/43689256803/job/132736193487)。只选择 `DuelNormalFrameCaptureTests/testSunPracticeCapturesTwoNormalWindowFrames`；没有重跑历史成功方法。
- [Artifact 14151887691](https://github.com/wuyong9494-lab/kriswu/actions/runs/43689256803/artifacts/14151887691)，名称 `fighter-normal-frame-capture-43689256803-1-encrypted`，11,003,010 B，SHA256 `b16c9e21e80dcddc1e8922648eb9449593d6b0a5372a41692c0d45eac7b57330`。认证恢复 48 个 inventory entries。
- 已编译的 373 个资源及安装 bundle 身份核对通过。本报告只复核既有认证证据，不下载、不读取密钥、不重跑或重复上传图像。

## 本次实际进展与未完成项

| 层级 | 本次证据 | 结论 |
|---|---|---|
| 孙登选角 | 按实际观测到的文字中心执行一次坐标触控；原 observation 2 为孙登已选、刘泉纬未选 | 已观测成功，未重试 |
| 练习就绪 | 原 observation 9 满足固定源码 `isReadySunPractice` 的全部条件：横屏、双方姓名/状态、暂停、居中摇杆、武器可施放且无资源错误 | 原 UI readiness 为 true |
| 正常图保存 | `captures=[]`，日志出现 `invalidPNG`，失败阶段 `sun-practice-ready` | 正常帧 0，所需两张未完成 |
| XCTest 结果 | 外层 exit 124，`exports={}`、`uiObservedCounts=null`；日志已进入 Tear Down | 没有最终 PASS/FAIL/SKIP 计数，不能填成 1 PASS 或借用旧 run 计数 |
| 证据恢复 | sidecar 身份、两张原图及哈希已经认证恢复 | 恢复成功与采集目标失败分别成立 |

旧 producer summary 的 `uiVisibleReadinessObserved=false` 来自 `bool(captures)`，实际表示没有保存正常帧。它不能推翻最后一条原始观察已满足就绪条件。报告保留这个原字段，同时另列重算的 readiness；训练就绪仍不等于测试方法完成或 UI PASS。[固定 Swift 测试与就绪条件](https://github.com/wuyong9494-lab/kriswu/blob/c0da35df68e7bbe7d40fbc83ad122268af48cfc6/Tests/ArenaFlowTests/DuelNormalFrameCaptureTests.swift)

## 原图方向与 invalidPNG

两份同 API 诊断原图经只读 Pillow、EXIF 和内嵌 XMP 检查，均为 **IHDR 存储尺寸 1320×2868，EXIF Orientation=8、XMP tiff:Orientation=8，显示尺寸 2868×1320**。原字节没有旋转、缩放或重新编码。

固定源码 `capture` 直接读取 IHDR 并要求 `width > height`，没有按方向元数据解释显示宽高。这是可确认的源码判断错误：该条件会拒绝这两份按方向显示为横屏的诊断图。结合实际 `invalidPNG`，最有证据支持的失败解释是正常帧遭到同一方向判断误拒。

**上述失败机制仍是源代码与同 API 诊断共同支持的推断。** 真正被拒绝的首张正常 PNG 在 guard 之后才会保存，因此本次没有取得它的原字节；不能声称已经直接审阅该张正常图，也不能把故障后的诊断图改名计入正常帧。

## 两张诊断图的客观视觉复核

审查者逐张查看了两份原图。它们都是正常 `XCUIScreen.main.screenshot().pngRepresentation` 捕获的诊断图，不是离屏渲染替代图。

| 原图 | 原始字节与 SHA256 | 客观可见内容 |
|---|---|---|
| `lobby-before-sun-touch.png` | 3,335,705 B；`e06f8a385843455043f2063f455cfa9b1175c4dfa11abf1c501f9564ac005267` | 横屏武者大厅；刘泉纬被选中，中央人物持双锤，左侧选角与下方练习入口可见 |
| `normal-frame-failure.png` | 4,352,314 B；`4a41b3378ce7fbbd318bd231a658738c8ffa7ac61f6729d745e1a186968dff0d` | 已在孙登练习场；左侧双刀、三面具与紫色效果，右侧刘泉纬双锤，练习 HUD、生命/状态、摇杆和操作层均可见 |

两张图分别属于大厅和故障后练习场，不能作为“同一练习状态的两张正常帧”验收。它们证明当前场景及角色已经绘制，不证明持续正常出帧、内部 tick、帧率、音频或真机表现；刘泉纬的双锤画面也不证明盘古装备与资源还原。原观察和截图不是同一个精确帧。

## 后续修复范围

修正 PNG 方向解析，保留原始图像字节，并从原 observations 单独计算 UI readiness。正常图与诊断图继续分开，验收仍要求两张正常练习图及最终结构化 XCTest 成功。本次没有执行 Android 客户端、接受游戏条款或上传 TestFlight。

完整证据哈希和分层结论见同名 JSON；其中结构化计数保持 `null`，视觉验收保持未通过。
