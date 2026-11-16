# 蛇王毒云原始动作接入（2026-11-16）

已从原始远程动作包取得 `s_rng_agl_cloud_bullet`：151 帧、5 个骨骼节点、18,182 bytes，SHA256 `474b609e89df1a9756a6aa573bb6bc98590329fae763073e997cb2ae0a57da95`。旧 `motion_catalog.json` 未导出此文件，但 `android_bundle_catalog.jsonl` 已记录精确路径和对象 ID；此前“没有恢复到 cloud loop”的结论已被这次实际读取更新。

读取的是已有记录中的官方地址 `https://sf3assets.nekki.com/Bundles/unity_6_3_X_lzma/Android/archives/4120b508355a8d1e20ca308506cc1c37.bin`。包共 595,183 bytes，SHA256 `7946927e5656d327675fb7bd6b60a60032ad54c1b365d20c75fe000b20f82001`。精确 Unity 对象路径 `assets/gamedata/resources/content/animations/binaries/ranged/universal/s_rng_agl_cloud_bullet.bytes`，path ID `-7448206328050373201`。

原始 cloud ModelObject 没有 mesh，由虚拟骨骼承载特效。已绑定真实 prefab、bones 与配置第 69 条 `D13_Poison_Bomb_Cloud_Model_Attack`；保留 GrandParent pelvis 的 X 对齐、面向偏移 200、原始循环时钟和全部节点。全 151 帧的 array-zero 局部变换确实相同；静止是源数据的实测结果，不是缺资源的替代值。

生成的 GLB 为 26,108 bytes，SHA256 `b6c0f8996645390d68a262661eb2c29d1251fb81d847e682bf8b7b2190d52a35`。对 301 个半帧时刻 × 5 个骨骼完成 1,505 次导出回读矩阵比较，最大矩阵误差 `4.768371586472142e-08`。默认 SelfEndFrame=4 对应 End tick 292，下一步重置，循环周期 293 ticks。

`DuelSerpentCloudMotion` 校验源身份、采样数量、有限坐标、实测恒定姿态和循环时钟。`DuelSerpentRainRuntime` 可用已认证的动作自动生成 cloud frame；显式传入与源 FK 冲突的帧会原子拒绝，不消耗时间或随机结果。出生对齐只执行一次，人物随后移动或转身不会拖动既存毒云。源身份、出生朝向和空间锚点进入回放状态。

使用真实蛇王身体、瓶子、毒云绑定和独立源规则 oracle 执行 16 项 Swift 专项测试：全部通过、无失败、无跳过。覆盖瓶子释放→毒云创建→29 次雨滴脉冲→15 次毒地叠层→清理、双朝向、毒云创建的随机数边界、冲突／旧帧拒绝、回放一致性、免疫和区间边缘。

本次完成的是可验证的毒云动作和伤害组件连接。完整蛇王在 `DuelWeaponFight` 的角色注册、余下技能、正式粒子／音频呈现、原生资源验收与双机验收仍未完成；没有把这些组件测试当作角色已经完成或 TestFlight 已上传。原始模型／动作／配置与处理结果保存在私有检查点，不提交明文到公共仓库。
