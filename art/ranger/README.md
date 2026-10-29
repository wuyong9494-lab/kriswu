# 游侠原创资产 v1

本目录和 `App/Arena3D/Ranger_Original.glb` 是本项目新制作的实际 3D 资产。几何、512 × 512 配色贴图、骨架、8 段动作均由 `scripts/assets/build_ranger.py` 制作，没有复制 Rogue / KayKit 网格或动画，也没有把原模型改名覆盖。

- `Ranger_Original.blend`：Blender 4.3.2 可编辑源文件，含原始拓扑、UV、权重、22 骨架节点和全部动作。
- `Ranger_Atlas_512.png`：不透明配色图集，1 个材质，无透明发丝、法线贴图和实时布料。
- `model-*.jpg` / `pose-*.jpg`：实际模型的离线渲染检查，**不是游戏截图**，也不是概念图。
- `../../App/Arena3D/Ranger_Original.glb`：游戏实际加载的 glTF 2.0 二进制。脚底 Y=0，正面 +Z，单位米。枪口节点 `muzzle`，右手挂点 `handslot.r`。

复现：

```sh
blender -b -t 4 --python scripts/assets/build_ranger.py -- --motions
python3 scripts/assets/validate_ranger.py
```

只生成资产可以改用 `--no-render`。CPU Cycles 预览用于查穿插和轮廓，游戏使用 SceneKit，最终仍以游戏内画面为准。

动作：`Ranger_Idle`（2.4 s）、`Ranger_Run`（约 0.667 s）、`Ranger_Shoot`（游戏 0.32 s）、`Ranger_Skill`（0.62 s）、`Hit_A`、`1H_Ranged_Reload`、`Death_A`、`Cheer`。30 Hz 烘焙 LINEAR 动作，静止通道 STEP；导出后删除与绑定姿态完全相同的通道。SceneKit 按游戏持续时间线性播放，不再应用旧角色的二次加速与姿态放大。

持弩待发是基础姿态；射击事件 0 ms 释放，随后后坐与复位。沿用现有即时发射、伤害和碰撞规则，没有为了动画改变游戏时序。跑步接触段按 2.4 m/s、0.667 s 周期制作，运行时使用现有速度倍率；移动攻击只覆盖上半身。

资产预算与验证结果见 `docs/ranger-asset-validation.json`。三角形数比旧 Rogue 文件高，骨架、材质、导入文件体积减少；这不构成真机性能改善的证据。正式美术验收仍需游戏内脸部、持弩、动作与真机可读性检查。没有面部表情骨骼，没有宣称达到概念设计图的全部雕刻和手绘细节。
