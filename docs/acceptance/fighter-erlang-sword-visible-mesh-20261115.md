# 二郎神原始飞剑：可见剑体接入

本批把已接入的六剑模型状态连到真实剑体显示。它使用原始高画质预制体的六个剑网格发射器，覆盖出生三层和持续循环三层；原预制体共有二十个活动发射器，其余十四个仍在收据中明确列为未绑定。`completePrefab` 为 `false`，本记录不宣称整套飞剑特效或原生画面一致。

## 原件与绑定

| 项目 | 实际身份 |
| --- | --- |
| 原始预制体 | `D15_fx_sword_jian_glow(weapon_r)`；GameObject `-8276785478031651511` |
| 来源 bundle | `4f9476ea1326d7c102950a772ee44020.bin`；SHA-256 `971b3a1ea36eaaebaea4ae73a56ed65d8ffc4383625a06d64a209d8a70fbbd90` |
| 原始剑网格 | `geo_jian_sword_01`，pathID `5887294323812191014`，720 顶点；原对象 SHA-256 `0edd33e67555bbf4ac7734f01e76739f1024aba303533ae887662e9a3fe8b2d9` |
| 原始事件 | lock1447 / trigger1：模型初始化，high 分支，`magic_joint_root`，AttachToLocal=true、Follow=[1,1,1]、Shift=[0,0,0] |
| 原始控制器 | duration=9999 秒，overrideDuration=1；没有 delayedEffects；额外方向旋转开关为 0 |
| 原始模型动作 | records110–118：六种 Birth、单样本 Rotate、Idle、Attack；8 条已认证碰撞轨迹，Rotate 保持没有伪造轨迹 |
| 人物身份 | `wuyong_erlang`，62 动作 GLB SHA-256 `debd14c7af756e52e14b920ce2db37fd77ddcfa26b5668fe552ac79e7a1303bd` |

三个材质分别为原始 additive、black alpha 和 Fresnel。两个共享材质通过已存在的原 ZIP 成员和已存在的压缩区块缓存读取；新范围下载量为 0。外部 Fresnel 原对象是 1,376 字节，SHA-256 `b34327caa6cf05fe905a8717ec0b4f1cd386e269bca777c1880a43f06923634f`。准备器从这些原始字节重新解析材质，不以可编辑的元数据代替原件。该外部 bundle 仅有既有缓存子集，收据没有将它标为完整 bundle SHA 验证。

输出为 `SF3_D15_SwordEffects.json.gz`，482,805 字节，SHA-256 `02cf066eae8a636509c5c0ac5f87c252e1328e49d9b74e52fa9d9df79749162f`。它引用 7 个逐字节认证的私有资源文件，包含 3 个原材质和 9 条粒子轨迹。六个发射器中的三个循环发射器各保留两个交替轨道，从而不截断跨周期存活，也不重复叠加原本单个剑体。

源收据 `d15-sword-effect-receipt-private.json` 为 22,146 字节，SHA-256 `0f2d17faa38443603cc278fa45d1c5dfa1ac34fc12d3865450d36112116f41e2`。原始媒体、派生媒体、shader 程序和私有收据不提交到公开仓库。

## 显示行为

`DuelErlangSwordEffectAssets` 独立验证人物 GLB、八条对应的原始模型轨迹、九组源 root 姿态、六发射器范围和单帧 Rotate。既有 H17 入口的默认身份门槛保持原样。

`DuelErlangSwordEffects` 从 Core 当前模型的 owner、id、origin、direction、`motionTick(at:)` 和 `bornAt` 读取状态。角色变化只改变动作姿态；粒子出生时间继续使用同一个模型的真实出生时刻。Idle 回绕、Birth 转 Idle、射出和反复绘制不会重新播放初始化。原始 root 的约 0.28 米上下移动被保留，已归一化的 Align 原点不再扣第二次，原始方向只应用一次。Rotate 只允许 tick0，Attack 的 DeleteModel 边界保持 tick70。

显示遵守当前 `swordMotion.hidden`，但不会据此虚构源 `D15_SHOW_SWORDS` 事件或重新播放出生特效。完整的 SHOW 重启与 DestroyEffect 5/10 帧尾部仍需对应实际源事件；本批不从 cast phase 猜测。回合结束、资源失败和退出按现有 App 生命周期清理。渲染器不能创建战斗模型、造成命中或推进战斗时钟。

World 增加独立的准备、绘制、透明队列合并和清理入口；`DuelWeaponAssets.erlangSwordEffects` 与最终发布清单由整合分支统一接入。这里的结果属于候选资源和代码接入，尚不是 TestFlight 交付记录。

## 实际验证

只执行本批新增检查，未重跑既有全套或重型原生工作流。

- 5 个实际原件定向检查通过，4.923 秒：720 顶点及原拓扑；六发射器原始时长和循环交界；原 pose / 单样本 Rotate；篡改或缺失 profile 轨迹拒绝；材质原对象、精确 shader keywords 和所有运行资源哈希。
- 随后仅执行新增的 shader 算术检查，通过。逐行比较三个原 GLSL 程序与派生 Metal 的全部主体赋值，只归一化接口、向量类型和采样调用；未重跑前五项。
- 5 个纯 Swift 时钟场景通过：跨状态出生时钟、Idle 回绕与冻结帧、单样本 Rotate / 删除边界、隐藏不会伪造 SHOW、角色和原 duration 范围。
- Swift 6.0.3 对四个受影响 App 文件语法解析成功；`git diff --check` 通过。

检查入口为 `scripts/test_erlang_sword_effect.py` 和 `scripts/check_erlang_sword_visual_clock.swift`。准备入口为 `scripts/prepare_erlang_sword_effect.py`；输入均为既有原 bundle、已审模型候选、最终人物 profile 和已恢复材质缓存。

以上是离线原件、派生数据、时钟和语法验证。没有 Apple SDK typecheck、Metal 实机编译或新原生截图结果；Noise、Trail 及其他十四个发射器仍需后续接入与实际画面验收。
