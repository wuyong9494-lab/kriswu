# 蓝月港样板：模拟器画面记录

本目录保存实际运行产生的原始 PNG 与场景身份 JSON；每张图的来源提交、工作流和 SHA256 见 [manifest.json](manifest.json)。图片保留模拟器原始像素方向，横屏界面在原始 PNG 中旋转显示，没有裁切、重绘或调色。

## 战斗样板

来源：`48024a552277afe4c9f280843360c7b9b7f46e48`，[成功采集运行](https://github.com/wuyong9494-lab/kriswu/actions/runs/41004031848)。随后应用修改集中在菜单布局；这些画面不冒充后续提交重新采集的战斗图。

| 场景 | 0.25 秒 | 1.2 秒 |
|---|---|---|
| 峡谷对照场，加载新游侠 | [画面](canyon-early.png) / [身份](canyon-early.json) | [画面](canyon-combat.png) / [身份](canyon-combat.json) |
| 双闸交汇，蓝月港环境 | [画面](harbor-early.png) / [身份](harbor-early.json) | [画面](harbor-combat.png) / [身份](harbor-combat.json) |

人工检查确认双闸墙体、降低高度的草丛、范围提示和新游侠显示；角色本体受击白光仍明显，不同职业的体量和美术风格尚不统一。场景模拟状态可比较，但动画/粒子阶段依赖显示帧与 SceneKit 动作时钟，不把固定模拟时间当作逐帧或像素一致性证明。

## 菜单实际画面

来源：`ebd6c173c83a2c34f32855da9ef28e9321ee9a61`，[采集运行](https://github.com/wuyong9494-lab/kriswu/actions/runs/41006620721)。角色页与地图页均成功通过身份门禁，随后人工查看原始 PNG。

- [角色页](sample-hero.png) / [身份](sample-hero.json)：全身、说明框、白字页签和固定试玩按钮完整显示，实际加载 Ranger_FaceSample.glb。
- [地图页](sample-map.png) / [身份](sample-map.json)：完整边界、六个出生点和中心区域可见，地图 ID 为 twin_gates_sample_v1。右侧长说明在卡片内独立滚动，首屏不代表全部说明已显示。

这确认了本次取景与首屏布局修复，不代表所有屏幕尺寸、辅助功能字号或连续交互均已验收。

## 验收边界

这是原创样板的模拟器截图记录，不是达到原版品质的证明。没有完成 iPhone 17 Pro Max 真机长时帧率、GPU、热状态、双机/三机网络对局或音乐音效试听。角色持弩姿态、手/弩/胸部负空间、连续动作衔接、地图美术细节和玩法公平性仍需后续制作与实测。
