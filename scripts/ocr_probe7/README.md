# Probe 7 离线核验工具

本目录只审计既有公开合成样图的诊断产物，不执行 OCR、不处理真实用户照片，也不修改产品识别设置。离线真值不属于 App 或原生测试资源，分析器在来源、请求和图片完整性通过后才读取它。

## 已完成的运行

[原生运行 41780537427](https://github.com/wuyong9494-lab/kriswu/actions/runs/41780537427) 的 attempt 为 1、job 为 `126410815851`，artifact 为 `13298903262` / `plan-primary-probe7-9-1`。

受测源码为 `59864b3da8a950f477f644aef93ac6faf4cb0f71`，tree 为 `1b0a204f1326df65407d6d1f340d6f5758f4cb4d`。它是 `fe75c946bc2847c273e07cc71980afe1f1059bb1` 的同树空提交，用于恢复卡住的队列；不能把旧 run `41665626833` 记为测试成功。旧作业最终取消，没有 runner、执行步骤或产物。

四个原生方法全部完成，32 次请求完整，16 张 PNG 与 Probe 6 B 原字节一致。四组各为 **0/8**：1×/3×分别比较 `Float(10/baseHeight)` 与 `0`。仅第 22 行 1×在两种阈值下各返回一条 `COM`，其余 30 次请求没有 observation。本方案未采纳到产品，完整结果保存在 `docs/ocr-evidence/probe7-41780537427.json`。

## 文件与依赖

- `analyze_probe7.py`：Python 3.10+ 标准库分析器，绑定精确源码、tree、run、attempt、job、原始日志及图片。
- `tools/extract_xcresult_png.py`：从 xcresult 原始或 Zstandard 数据对象提取完整 PNG 字节，逐 chunk 检查 CRC；需要 Python `zstandard` 模块，不解码或重编码图像。
- `probe6_b_baseline.json`：16 张历史 B 裁图的冻结基线，SHA256 为 `6607596938a46be6b8167d89c64c2ce053222ec01f6e5fedf00c8c0bc71f78d3`。其中旧绝对路径只作来源记录，分析器不会依赖这些路径读取图片。
- `offline_truth.json`：只供完整性检查后的离线评分，不进入识别请求或裁框选择。

## 重新核验同一份产物

在仓库根目录运行以下命令。GitHub CLI 需具有读取该运行产物的权限；也可以从上述运行页面下载同名 artifact 并保留原始内容。示例只下载与分析已完成结果，不启动 CI。

```bash
PROBE7_EVIDENCE=/tmp/plan-ocr-probe7
mkdir -p "$PROBE7_EVIDENCE"
gh run download 41780537427 --repo wuyong9494-lab/kriswu \
  --name plan-primary-probe7-9-1 --dir "$PROBE7_EVIDENCE/artifact"
gh api repos/wuyong9494-lab/kriswu/actions/runs/41780537427 \
  > "$PROBE7_EVIDENCE/run.json"
gh api 'repos/wuyong9494-lab/kriswu/actions/runs/41780537427/jobs?filter=latest' \
  > "$PROBE7_EVIDENCE/jobs.json"

python scripts/ocr_probe7/tools/extract_xcresult_png.py \
  --xcresult "$PROBE7_EVIDENCE/artifact/primary-probe7.xcresult" \
  --log "$PROBE7_EVIDENCE/artifact/probe.log" \
  --output "$PROBE7_EVIDENCE/png"

python scripts/ocr_probe7/analyze_probe7.py \
  --expected-commit 59864b3da8a950f477f644aef93ac6faf4cb0f71 \
  --expected-tree 1b0a204f1326df65407d6d1f340d6f5758f4cb4d \
  --workflow-commit 59864b3da8a950f477f644aef93ac6faf4cb0f71 \
  --run-id 41780537427 --job-id 126410815851 --attempt 1 \
  --log "$PROBE7_EVIDENCE/artifact/probe.log" \
  --source-manifest "$PROBE7_EVIDENCE/artifact/source-manifest.json" \
  --run-metadata "$PROBE7_EVIDENCE/run.json" \
  --job-metadata "$PROBE7_EVIDENCE/jobs.json" \
  --png-dir "$PROBE7_EVIDENCE/png" \
  --png-report "$PROBE7_EVIDENCE/png/extraction-report.json" \
  --extractor scripts/ocr_probe7/tools/extract_xcresult_png.py \
  --baseline scripts/ocr_probe7/probe6_b_baseline.json \
  --geometry Tests/SiteTests/OCRSamples/status_cell_probe_geometry.json \
  --truth scripts/ocr_probe7/offline_truth.json \
  --out "$PROBE7_EVIDENCE/analysis"
```

原 ZIP 的 SHA256 为 `39bffa9e78426c9a15f3e5021c9206163c9f9efa75daa8f4e8b658b56a000dfa`，canonical `probe.log` 的 SHA256 为 `582752e0ecfd9f00b94b3b2cefef6940101d9b6159aca3de2bb06dd3eacd3931`。分析必须使用 artifact 内原始日志，不能用工作流回显或截断后的日志替代。

## 通过条件与评分边界

分析器退出码为 0 且 `summary.json` 的 `integrity.finalConclusionEligible=true` 才接受结论。退出码 2 表示证据不完整或身份不匹配；不能只检查输出文件是否存在。预评分完整性失败时不打开真值，正确率保持 null。

每组分母固定为 8，包含无 observation 的请求。严格正确要求单个 rank 1 候选等于完整状态，每个请求最多计一次；仅去空白新增、完整词子串和 rank 2/3 单独统计。禁止跨候选拼接、字符替换、繁简转换、模糊匹配或词表补救。原始候选、置信度、原生字符框及 nil/shared/error 状态保留。

16 张 PNG 须逐项核对原字节 SHA、长度、IHDR、native prepared 记录、Probe 6 基线，以及提取报告的每图 CRC 证明。提取报告旧路径只是来源记录；迁移后仍按实际文件字节和文件名绑定。

本实验使用预先固定的生成器网格和透视几何，不是产品 OCR 的实际行框。`minimumTextHeight=0` 不保证关闭 Vision 的所有内部缩放；XCTest 通过不代表识别正确。此处 0/8 不证明像素信息不可恢复，也不能替代完整网页流程或真实用户照片验收。摘要不能替代重新验收所需的 canonical artifact、原始 PNG 与最终运行元数据。
