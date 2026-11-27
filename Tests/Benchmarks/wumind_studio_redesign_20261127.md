# WuMind 工作台与工坊改版验收

## 截图出处

用户指出的 iPad 画面为《季度经营汇报与下阶段决策建议》第 1 页上打开的系统 PDF 分享面板。系统显示 4:25 PM、PDF Document、229 KB。已从 Xcode 证据包提取完整原图，文件名为 `434F0716-5468-447D-806B-2F83EFBD9515.jpeg`。该附件与同一秒前后的其他三张附件内容相同。iPhone 原图来自同一测试方法、同一份本地报告，系统面板显示在底部。 [iPad 原图](studio-redesign-20261127/ipad-reference-pdf-share.jpg) · [iPhone 原图](studio-redesign-20261127/iphone-reference-pdf-share.jpg)

| 改前画面 | iPhone 17 Pro Max | iPad mini (A17 Pro) | 核对范围 |
|---|---|---|---|
| 工作台、10 个工坊及初次进入幻灯片的空白页 | [浅色](https://github.com/wuyong9494-lab/kriswu/actions/runs/45998573364/artifacts/15199159505) | [深色](https://github.com/wuyong9494-lab/kriswu/actions/runs/45998573364/artifacts/15201065719) | `f57f607`。工作台附件为 `WuMind-clean-workbench`，工坊按 `Workbench-<入口标识>` 命名。 |
| 同一工作台的另一种系统外观 | [深色](https://github.com/wuyong9494-lab/kriswu/actions/runs/46004048441/artifacts/15204465300) | [浅色](https://github.com/wuyong9494-lab/kriswu/actions/runs/46004048441/artifacts/15203923125) | `a28605b`。本轮只有工作台具备这一组改前反向外观截图。 |
| 3D 实际首帧 | [iPhone](https://github.com/wuyong9494-lab/kriswu/actions/runs/46013592826/artifacts/15207645902) | [iPad](https://github.com/wuyong9494-lab/kriswu/actions/runs/46005383057/artifacts/15203929699) | 使用初轮空白视口修复后、这次改版前的真实画面。 |
| 本地报告的第 1 页及编辑版本 | [iPhone](https://github.com/wuyong9494-lab/kriswu/actions/runs/46025311747/artifacts/15213432761) | [iPad](https://github.com/wuyong9494-lab/kriswu/actions/runs/46025311747/artifacts/15214795124) | `f620bc4`。原版封面附件 `Works-OriginalVersionPreview`，编辑版导出到「文件」的附件 `Works-EditedPowerPointExport`。 |
| 同一报告在幻灯片工坊的系统 PDF 分享面板 | [iPhone](https://github.com/wuyong9494-lab/kriswu/actions/runs/46029908204/artifacts/15215266540) | [iPad](https://github.com/wuyong9494-lab/kriswu/actions/runs/46029908204/artifacts/15215487371) | `a18dcdb`。在 `testShareLocalPDFToTenderInboxFromWorkbench` 的系统 JPEG 中保留完整画面。 |

## 操作范围

新截图从双工作区首页进入 WuMind，再点工作台，使用演示用户及本地数据。选择的输入是产品内置的经营报告模板，保持相同标题和封面。先打开文稿设置查看资料入口，再生成报告、编辑一页，分别核对 PDF 系统分享和保存编辑版 PowerPoint 到本机「文件」。宽屏用 iPad 横屏，最大辅助字号用系统 Accessibility XXXL。远程生成、真实模型计费和真机视觉需分开验证。
