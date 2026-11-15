# 二郎神哮天犬原始资源绑定

本批将已有原件变成可绑定的独立犬模型、动画和攻击胶囊轨迹，并新增独立的清单校验、SceneKit 载入器和显示接口。它不把犬动作塞进人物骨架，不把 141 帧原文件长度当成原技能的播放长度。

基线为本地 `31c21ec4d10958df3a3786315c16dafedd329def`，树 `96d695d1eb61d5e9e9c5116cb564a29408a1ecdf`。本批没有发布、启动客户端或执行原生 Apple 构建；吴庸的完整生产配置、最终 profile 清单和发布 pins 由集成批次统一绑定。

## 原件与派生结果

| 项目 | 精确身份与范围 |
| --- | --- |
| 犬模型 | `mgc__d15_dog`，bundle `9d5fd54b70a5568f2cdc1f204770f78d.bin`，260,603 字节，SHA-256 `2cbb991e2d8ece154c56d95e776d3be2ac72c6d09df5c09d5413cdaf1fe4dea8` |
| 犬骨骼声明 | 原 BonesData 4,753 字节，SHA-256 `72f0791d0bd777caa31d7616feee71e737ccc67aa40f4827c49b1203f639c82d`；50 个声明骨，52 个原 prefab 节点 |
| 原动作 | `unique_moves/sets_d15/d15_dog_attack.bin`，TextAsset path ID `7057222478336785206`，138,950 字节，SHA-256 `6443c760202bf084ae030d81b419f8494db1f4aa2e7c7904c40054bdf924b712`；两数组、141 帧、41 个动作骨 ID |
| 动作 bundle | `2a784bc550bc06541a38a4c1c53b69f3.bin`，SHA-256 `093b534cd7c509cf393b531e1dfc5f12f91e7a113c0153bf40bfe6bcdb5c5e6b` |
| 原配置 | `settings_sets_dynasty.bytes` record 93，`D15_Ability_Dog_Attack_Model`，SHA-256 `3d660f485ad5e238f23bf6dd19d16855635a9449fd213bf1dd468a9cc979f701` |
| 派生 GLB | `SF3WE_D15_Hound.glb`，438,144 字节，SHA-256 `22a9292b5fa62ae1a64d91cd7e840632119afd62a7c21d8485b5b9de011bc236` |
| 派生候选记录 | `d15-hound-candidate-private.json`，91,509 字节，SHA-256 `70e1ebe77b6ba26c01e077b04ca8ecd0abd2220568d69328cfe34788eaf47807` |

配置的 `FirstFrame` 使用原默认起点，`EndFrame=60`、`MidFrames` 使用原默认 1、`BlendingFrames=0`。因此导出前 60 帧，30 FPS 键帧对应 60 Hz 的 119 个采样点。原 `SelfEndFrame` 默认 4 对应 `AnimationEnd` tick 110；沿已有召唤物的应用呈现顺序保留该终止采样，下一 tick 清理。余下原始帧继续保存在原件记录中，没有被伪报为正在播放。

六个原胶囊全部从犬骨骼计算；配置实际选择头、躯干、左右前腿四个攻击部位。攻击源区间 12–34 转为 tick 22–67。没有给犬发明人物受击胶囊。头、躯干胶囊原本没有左右后缀，其 `right` 字段只是现有两槽格式中的稳定编码位置，不代表原件声明了右手武器。

原 `CreateModel` scale 1 被保留，厘米按 0.01 转成米。配置仅把犬的 `spine_root_joint` X 对齐到主人 pelvis X；没有复制主人 pelvis 高度，也没有猜额外位置偏移。水平根位移从骨骼里分离，只应用一次，原竖直动作留在骨架里。没有套用人形的 0.92 显示比例或推测地面抬升。

## 实际接线

`prepare_erlang_hound.py` 只读取已经恢复的、逐项固定 SHA 的本地原件，产生独立 GLB、`DuelSummonMotionTrack`、攻击与释放绑定事实。最终脚本重新生成的 GLB 和候选 JSON 与已核输出逐字一致。所有原图、原动作和派生媒体保留在私有目录，没有加入源码仓库。

`bind_erlang_hound.py` 必须同时验证候选 SHA、当前 profile SHA、人物 GLB 身份，以及 profile 中与显示清单完全相等的犬轨迹，才生成 `SF3_D15_Companions.json`。它不根据相同角色名接受不同碰撞数据。

`DuelErlangCompanionManifest` 限定原模型、骨根、原动作 SHA、原骨骼 SHA、播放窗口、六胶囊半径、四个攻击部位和当前人物 SHA。`DuelErlangCompanionAssets` 再验证文件字节及自包含 GLB，并检查 82 个位置/旋转通道和实际动画时长。显示代码只读取战斗中的模型 ID、主人、方向、出生 tick、原点和当前 live tick；跳帧、重绘和暂停不会自行推进攻击或寿命。

吴庸局部资源入口需把固定 `companionManifestSHA256` 传给该载入器。该入口和 `DuelSummonMotionTrack.sourceEndEventTick` 可选字段由同一轮 Erlang 核心集成提供，本批没有改 replay 版本或工作流。

## 验证记录

- 新增 Python 定向检查覆盖原 141 帧与配置 60 帧区分、中心胶囊编码、当前 profile 与显示轨迹精确绑定。三项通过，没有运行旧完整套件。
- Swift 6.0.3 仅执行新增 `DuelErlangCompanionManifestTests` 三个方法：真实私有候选 JSON 解码和绑定、错误原件/骨根/窗口/轨迹拒绝、可重复的可见性与终止 tick。3 项通过，0 失败，0.523 秒；构建 13.03 秒。
- 首轮构建期间修改了新测试文件，Swift 报 `input file was modified during the build`，没有进入测试执行。该编译中断不记作回归测试红色结果；源文件固定后重新执行上述三项通过。
- 对真实 GLB 独立读回：50 份原 inverse bind、41 个动画骨的前 60 帧，共 4,920 通道采样；119 个 tick 的 6 个胶囊，共 1,428 个端点采样。最大 inverse-bind 误差为 `2.8611e-8`，胶囊七位小数舍入误差不超过 `5e-8`。实际网格顶点和键帧均与原对象经过明确单位/坐标变换后的 float32 数组相符。
- 新 App 文件和场景 hook 通过 Swift 语法解析。Linux 上的这些检查不代表 SceneKit 原生类型检查、Metal 渲染或真机画面验收通过。

可复用命令：

```sh
python3 -m unittest discover -s scripts -p test_erlang_hound.py -v
ERLANG_HOUND_CANDIDATE=<private-candidate-json> swift test --jobs 4 --scratch-path <isolated-build> --filter DuelErlangCompanionManifestTests
python3 scripts/verify_erlang_hound.py --candidate <private-candidate-json> --models <source-bundles> --configs <source-configs> --receipt <new-private-receipt>
```

## 明确保留的应用适配

`MagicPower` 的原 `BaseDamage=0.15000000596046448` 绑定为 shadow/1500 bps，最终伤害依赖明确的 arena magic power，未偷换成对手生命比例。原 `Impulse X=22000/Y=8000` 保留为原事实；200 mm/10 tick、重力 18、hit-stop 2 是现有 heavy 响应的应用适配，未宣称与原力学单位等价。

原 `D15_Dog_Hide` 区间及 10/15 tick 隐藏/显示时序已经绑定。当前显示采用从模拟 tick 计算的不透明度；原版定制 morph、SetSkinColor、灯光和 shader 视觉等价性尚未在原生运行证明。原烟雾 prefab、材质和 shader 有独立来源链，继续由 FX 接入批次处理；本批没有用泛用粒子冒充它们。
