# 孙登与刘泉纬：独立接续开发记录

本批以验收分支 `codex/fighter-visual-acceptance-20261113-1200` 的
`ef3064085879c497d59533459c94b429a40f9cee` 为源代码基线，在独立目录开发。
执行文件的 SHA-256、精确方法及已有原生运行归属见
[本批验证记录](acceptance/fighter-dual-continuation-20261114.json)。

## 已落地的运行时修复

### 孙登召唤队列：拒绝请求前不再消耗资源

`DuelTriadState.canUse()` 原来只计算已释放攻击 `flights` 与通用延迟队列
`scheduled`，漏掉源机制的 `sourceScheduled`。实际入队处却计算三个队列的总量。
因此合法配置下可以出现准入返回 true、先扣雾能和分配事件 ID，最终入队失败的情况。

修复只把 `sourceScheduled.count` 加入同一个准入预算。容量不足时，三类手动魂召唤
在消耗雾能、冷却、刻痕或事件 ID 之前被拒绝，规范回放字节保持不变；攻击释放并
消亡后，空间再次可用。

复现使用明确标注的合成压力配置：雾能初值/上限 1,000,000，共享和军团魂冷却为 0，
每次仍支付 3,300 雾能。通过公共 `start()` 发出 256 个请求后，第 257 次请求在旧实现
中没有生成召唤，却把雾能从 155,200 减到 151,900。这里证明的是受支持配置的容量一致性
问题，没有把它描述成默认原版平衡下已观察到的玩家故障。

### 源配置身份：在加载阶段拒绝混用

H17 `RuntimeProfile` 原来只检查配置摘要是否为 64 位小写十六进制，但同一角色的
原始入场状态要求一个精确的配置摘要。一个格式正确、内容错误的摘要可以通过规则
验证，然后静默失去原始入场流程。

现在复用 `DuelTriadStanceState.runtimeConfigurationSHA256` 做精确验证，和现有 D19
运行时的固定来源策略保持一致。新增回归覆盖两个角色的错误摘要、角色版本互换、
1–6 级工厂及 JSON 往返；`runtime == nil` 的明确应用适配规则继续有效。原有四种入场
能力测试保留，另增加 `catalog.validate()` 在错误摘要处拒绝的断言。

## 原始倒地音频：新的私有候选与编译能力

新增 `scripts/source_floorfall_audio.py`，从已保存的类型化原始配置解析
`lock923 / set97 / EFFECT__Dust_Down` 的事件和条件。它区分 `FloorHit(Me, Physics)`
与 `IntervalStart(Me, Floorfall)`，要求源动作属于 `PHYSICS` 或 `FALL`，并排除
`THROW_FALL` 和 `PHYSICS_NO_SFX`。

本批只恢复这条规则实际引用的 7 个原始身体倒地音频，新增 PCM 共 245,606 字节；
88 个已存在的 PCM 按原字节复制，没有重新编码。独立候选包含 95 个 WAV 和 114 个
动作标记，原 manifest、角色目录、release 与旧音频的 91 份输入摘要均保持不变。
候选目录使用 0700，文件使用 0600，没有把原音频写入公开仓库。

两处有原始条件与动作身份支持的标记是 `h_hit_head_fall` 和
`h17_root_spike_passive_end`。它们的 interval 起点 20 对应零基源采样 19，在当前
60 Hz / 每源帧两 tick 的时钟下于 tick 38 跨越。新增核心回归覆盖准确跨越、冻结 tick
不重复、变速跨越不丢失、倒退不触发与新动作重新触发。站姿以及排除条件命中的投技
没有被加入。

这份候选尚未安装或并入加密 release。普通物理 `FloorHit` 分支、
`PlaySound.Position=null` 的原生默认位置，以及实际播放听感仍待核对；特效的
`centerOfMass` 不能当作声音位置证据。详细来源、测试与产物摘要见
[倒地音频记录](fighter-floorfall-audio-20261114.md)。

## 盘古：可复用的严格资源输入准备器

新增 `scripts/prepare_liu_pangu_inputs.py`，把既有 D19 身份清单、动作语义清单及实际
缓存连接成可供后续解码和 GLB 装配的输入计划。两份来源清单有固定摘要，逐个对象
校验字节数和 SHA；多个动作别名共用的源对象只列一次，并保留每个别名自己的原始
帧参数、声音标识和 interval。未知源 FPS、速度和实际骨架绑定保持未知。

真实缓存预检执行一次：10 个既有共享原动作对象、585,528 字节全部匹配已审查摘要，
对应 17 个已恢复别名；连同 12 个未恢复别名，共生成 29 个装配任务。尚缺的 12 个
别名对应 11 份独占动作文件；5 个明确装备身份当前没有已验证原资源输入。
这些共享动作是前序已恢复的资产，本批增加的是可执行准备能力。

旧双锤、旧斧及调用者自行填写的正确路径/摘要不能被升级为盘古原始身份。有效但不
完整的输入计划使用退出码 2，明确 `inputCoverageComplete=false` 和
`releaseActivationAllowed=false`。脚本不生成 `SF3_FighterRelease.json`，也不改写
运行时 catalog、签名构建摘要或任何已有输入计划。

后续双目标激活还需处理独立的 H17 Morph 对手契约：现有实现固定旧 `liu_hammers`
的模型、装备和材质，资源打包替换清单也仍限制旧模型。不能简单复制 H17 构建器、
替换角色 ID 后宣称 D19 已接入。详见
[盘古输入准备验证](acceptance/liu-pangu-input-preparation-20261114.json)。

## 执行证据与归属

- 本批最终一次核心组合回归：Swift 6.0.3 / Linux，15 个精确方法，15 通过、0 失败。
  包含队列拒绝与恢复、两角色来源身份、倒地标记及直接相关的魂释放/入场规则。
- 新 Python 工具只运行各自有界回归；精确计数和执行文件摘要分别保存在对应验证记录。
- 已有 [GitHub Actions 43611931466](https://github.com/wuyong9494-lab/kriswu/actions/runs/43611931466)
  归属 **ef306408**。已复用现存结果核对：117 个唯一选择器与实际 Test Case 集合完全
  相同，117 通过、0 失败、0 跳过。此前失败的受控魂层 RGB 方法已通过。
- 该原生运行是 source-only synthetic 验证，5 个 installed-source 方法明确排除，
  `sourceOriginalMediaLoaded=false`，`productionPanguAssetsActivated=false`。
  它不覆盖本批后续源码，也不证明原资源整体、原版音画或物理 iPhone 验收。

本批没有重新触发已成功的 Apple 重型工作流，没有上传游戏资源版本或 TestFlight，
也没有修改现有魂层渲染修复链、其 CI helper、加密资源或解密密钥。
原开发 Sites 保持独立；新增的只读验收面板记录本批证据与仍待完成的项目。
