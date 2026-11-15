# 按实际条款原图就绪继续 Android 的修正

本批源码基线为 `adecac3876565403d217e8ea543bb2bc64c4f4ff`，树 `2953cea06d91487112ce80eda32d1f44be6273a7`。依据已认证的 [run 43694073878](https://github.com/wuyong9494-lab/kriswu/actions/runs/43694073878)，只修正两个确定问题：启动日志早于条款画面，以及焦点字段位于已取得的 activity dump 而非 window inventory。

## 代码变化

正常采样图的完整原 PNG SHA 必须命中两张已核对条款参考之一，才记录 `triggerSnapshot` 并进入一次新的前置截图与身份检查。marker 或 XML 条款文字单独出现时，继续原有 12 次采样、180 秒预算内的只读观察。未知画面不能触发点击。

前后焦点均固定取已有 activity dump 中唯一的 `mCurrentFocus`，与同一输出的唯一 `mResumedActivity` 核对；window inventory 保留为诊断资料，不作为另一条可替代的焦点来源。全部六份身份查询仍须完成。原有一次 launch、两次输入各至多一次、5 秒绝对新鲜度、37 × 37 复选框内部变化规则及普通缓存读取范围不变。

只执行 4 项受影响或新增的 mock 检查，全部通过，0.452 秒：启动画面 marker 必须等待已核原图、未知画面即使有 marker/XML 也不进入输入、唯一 activity 焦点正反例、完整两步输入回执。没有重跑此前 12 项全套。AST、YAML 与差异检查通过，另经独立只读审查。

## 消费者随新等待规则对齐

新私有消费者另存文件，不修改已消费的旧脚本或证据。新增 trigger 与正常原图、同 index PID 和截止时间的关联；多轮 marker 保留各自前后 PID，只接受最后一个有效样本的精确 claim。历史 marker 不再被错误要求等于后续输入 PID；实际输入仍独立受 trigger 和新鲜前置回执验证。

5 项新增合成检查通过，覆盖多个有效 marker、后续 PID 不同、旧 claim、篡改 proof 和 trigger 后出现额外 marker。下载、解封等 13 个函数的 AST 保持不变；未读取密钥、下载工件或执行新的客户端。新工件身份未取得前，消费者继续在读取源码、创建输出目录、下载或解封之前停止。

## 执行和交付边界

发布采用专用准备消息 `Prepare official Terms continuation after the reviewed screen 20261115`，新的 Android job 仍必须经过 `fighter-private-assets` 审批。此提交只生成具体待审对象，不代表已经批准或再次启动。先前收到的游戏协议授权记录保留，当前新 run 的环境审批另按其实际标识处理。

[Apple run 43691877506](https://github.com/wuyong9494-lab/kriswu/actions/runs/43691877506) 已取得两张正常原图且唯一 UI 方法通过；本批仅合并其实际结果报告，不再执行该成功方法。TestFlight 继续暂停；生产 App、角色资源、核心规则与 Sites 文件不在本批范围。
