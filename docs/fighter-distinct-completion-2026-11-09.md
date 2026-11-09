# 孙登武士刀、刘泉纬双锤：修复与原生测试结果

本次授权的资源发布、运行时修复和原生测试已完成。本文汇总已有公开提交及 GitHub Actions 结果；更完整的已公开执行历史见[原生验收说明](fighter-distinct-native-2026-11-09.md)。

## 已公开提交

目标仓库为 `wuyong9494-lab/kriswu`，分支为 `codex/fighter-lab-sf3-resources-20261108`。

| 内容 | 已公开提交 |
| --- | --- |
| 全部 32 个加密资源分片及清单；61 个文件的名称、大小和 SHA-256 已核对 | [b444d0f0](https://github.com/wuyong9494-lab/kriswu/commit/b444d0f0e513875ea2ae929b80d3c7b6c4624ca4) |
| 四个运行时源文件的修复及配套测试 | [4d7843e5](https://github.com/wuyong9494-lab/kriswu/commit/4d7843e5221944199dc3065a6e0c790deb9f525e) |
| 关闭对局时释放装备资源所有者，并阻止已关闭会话重新运行 | [ab68cc46](https://github.com/wuyong9494-lab/kriswu/commit/ab68cc4653304873378f483b9fa7e53b15a9292f) |
| 已有原生验收和媒体复核说明 | [3ab1777b](https://github.com/wuyong9494-lab/kriswu/commit/3ab1777b13b10cd42c5a514748efbd1db3effa4f) |

解密密钥没有提交到公开仓库或应用包。

## 四个运行时文件的修复

- `App/Services/GLTFModel.swift`：保留默认严格校验，为明确授权的已验证模型提供受限的内存中骨架根声明纠正。
- `App/Services/DuelWeaponAssets.swift`：仅对两份精确哈希匹配的源模型启用该纠正，保留模型字节、关节顺序、绑定矩阵和动画数据。
- `App/Services/DuelSourceEffects.swift`：保留原版格挡轨道的负 X 缩放，用绝对幅度检查合法范围；镜像效果可以正常渲染，零尺度仍按折叠处理。
- `App/Services/DuelWeaponEffects.swift`：使 `sourceTime` 的初始类型与后续 Double 更新一致。

配套测试继续保留实际几何、控件输入、命中伤害及资源释放断言。资源所有者的关闭后释放另由 `ab68cc46` 的后续修复和回归测试覆盖。

## 原生测试结果

[GitHub Actions 运行 42552805778](https://github.com/wuyong9494-lab/kriswu/actions/runs/42552805778) 在 `ab68cc4653304873378f483b9fa7e53b15a9292f` 上完成，状态为 **success**，五个任务全部成功。

| 任务 | 结果 |
| --- | --- |
| Core | 共 825 项：809 通过、16 项既有跳过、0 失败 |
| Envelope / staging | 10 项检查通过 |
| Device | 未签名 Release 构建及并发警告检查通过 |
| Ordinary native | 27 项原生测试及 2 项 UI 测试通过，0 失败、0 跳过 |
| Actual-resource character | 68 项原生测试及 3 项 UI 测试通过，0 失败、0 跳过 |

本次通过的回归包括装备资源所有者释放、已关闭会话拒绝继续运行、真实资源加载、源动作几何、原版控件及真实触摸命中流程。此后的说明提交没有更改已通过测试的运行时代码。

## 验收范围

已有公开验收说明仍列出刘泉纬恢复到待机的姿态切换、边缘控件遮挡及尾迹呈现等需要打磨的画面问题。功能测试通过并不表示最终视觉质量已全部验收。

暗影瞬移／投锤的原版时序与远程装备仍不可用。战斗时序、伤害和 AI 仍包含应用适配；本次没有建立完整原引擎等价性、可听音效质量或实机稳定 60 FPS 的结论。此次没有进行 TestFlight 分发。
