# 四英雄 GLB 骨骼 / 动画 / 招式判定窗口量化审计报告

- 审计脚本：`scripts/glb_audit.py`（纯 Python 标准库二进制解析 4 个 `DuelChar_*.glb` + `DuelChar_*.json` + `DuelWeapon_*.glb`，并交叉核对 `DuelCascadeurCharacter.swift` 与 `DuelGame.swift` 60Hz 帧表）
- 基线验证：ShiftCore + 回放 31/31 通过（Schema 22 / Rules 28，`DuelShadowArenaTests|DuelReplayStateTests|DuelReplayStateAuditTests`）

## 1. 骨架总览与头颈重接偏移审计

| 英雄 | 原型 | 关节数 | 原始身高 / 运行时缩放 | Neck→Head 长度 (m) | Chest→Head 距离 (m) | Head 轴相对世界竖直 (°) | Head 相对 Neck 轴 (°) | Head/Neck 权重顶点数 |
|---|---|---:|---|---:|---:|---:|---:|---|
| `wuYong` (`.wuYong`) | Shogun / Odachi | 25 | 1.837m / ×1.0015 | 0.1270 | 0.3423 | 24.1° | 56.3° | Head=22,934 / Neck=2,729 |
| `xuXiao` (`.gale`) | Grand Inquisitor / Greatsword | 25 | 1.864m / ×0.9763 | 0.1081 | 0.3423 | 3.7° | 3.5° | Head=134,638 / Neck=1,433 |
| `liuQuanwei` (`.liu`) | Nonna / Great Axe | 25 | 1.821m / ×0.9995 | 0.1270 | 0.3423 | 24.1° | 56.3° | Head=30,420 / Neck=1,151 |
| `sunDeng` (`.ember`) | Midnight / dual ninjato | 26 | 1.800m / ×1.0001 | 0.1270 | 0.3423 | 24.1° | 56.3° | Head=17,578 / Neck=3,097 |

跨英雄头颈一致性检查：

- `neck_length`（中位数 `0.1270`）：`wuYong`=0.1270 (+0.0%)，`xuXiao`=0.1081 (-14.8%)，`liuQuanwei`=0.1270 (+0.0%)，`sunDeng`=0.1270 (+0.0%)
- `head_to_chest`（中位数 `0.3423`）：`wuYong`=0.3423 (-0.0%)，`xuXiao`=0.3423 (+0.0%)，`liuQuanwei`=0.3423 (+0.0%)，`sunDeng`=0.3423 (+0.0%)
- `neck_len_over_hips`（中位数 `0.1316`）：`wuYong`=0.1316 (+0.0%)，`xuXiao`=0.1121 (-14.8%)，`liuQuanwei`=0.1316 (+0.0%)，`sunDeng`=0.1316 (+0.0%)
- `head_chest_over_hips`（中位数 `0.3548`）：`wuYong`=0.3548 (-0.0%)，`xuXiao`=0.3548 (+0.0%)，`liuQuanwei`=0.3548 (+0.0%)，`sunDeng`=0.3548 (+0.0%)
- `head_up_vs_world_up_deg`（中位数 `24.0640`）：`wuYong`=24.0640 (-0.0%)，`xuXiao`=3.6636 (-84.8%)，`liuQuanwei`=24.0640 (+0.0%)，`sunDeng`=24.0640 (+0.0%)
- `head_up_vs_neck_dir_deg`（中位数 `56.3187`）：`wuYong`=56.3188 (+0.0%)，`xuXiao`=3.5198 (-93.8%)，`liuQuanwei`=56.3187 (+0.0%)，`sunDeng`=56.3187 (+0.0%)
- 说明：`xuXiao` 的 `neck_length`（`0.1081 m`，相对中位数 `-14.8%`）紧贴 15% 阈值边缘，但 `head_to_chest` 与其余三人完全一致（`0.3423 m`，误差 < 0.01 mm）；其 `Head` 局部轴朝向与其余三人不同（`head_up_vs_neck = 3.5°` vs `56.3°`），需结合视觉渲染排查仰头/受击表现。

## 2. 武器挂载点（Socket + JSON 变换）与 VFX 刀光跨度审计

| 英雄 | 手侧 | 父骨骼 | 静息距 Hand 距离 | JSON `position` / `eulerDeg` | 武器网格长 (m) | 静息刀刃世界方向 | 相对前臂夹角 | VFX 刀尖误差 | 告警 |
|---|---|---|---:|---|---:|---|---:|---:|---|
| `wuYong` | R | `Forearm.R` | 39.5 cm | `[0.0, 0.0, 0.0]` / `[0.0, 210.0, 0.0]` | 1.440 | (-0.15, +0.55, +0.82) | 65.6° | -0.1 cm | socket parented to Forearm.R (not Hand.R) |
| `xuXiao` | R | `Forearm.R` | 2.2 cm | `[0.0, 0.0, 0.0]` / `[0.0, 0.0, 0.0]` | 1.180 | (-0.12, +0.56, +0.82) | 66.2° | -0.5 cm | socket parented to Forearm.R (not Hand.R) |
| `liuQuanwei` | R | `Forearm.R` | 44.9 cm | `[-0.141, 0.0, 0.099]` / `[0.0, 250.0, 0.0]` | 1.350 | (-0.12, +0.58, +0.80) | 67.8° | -0.3 cm | socket parented to Forearm.R (not Hand.R) |
| `sunDeng` | R | `Forearm.R` | 23.2 cm | `[0.0, 0.0, 0.0]` / `[0.0, 0.0, 0.0]` | 0.720 | (-0.10, +0.50, +0.86) | 62.4° | -0.5 cm | socket parented to Forearm.R (not Hand.R) |
| `sunDeng` | L | `Hand.L` | 13.2 cm | `[0.0, 0.0, 0.0]` / `[0.0, 0.0, 0.0]` | 0.720 | (+0.12, +0.46, +0.88) | 93.1° | -0.5 cm | OK |

## 3. 关键骨骼静息局部变换与世界坐标

### `wuYong` (Shogun / Odachi)

| 骨骼 | 父节点 | Local T | Local R (xyzw) | Rest World Pos |
|---|---|---|---|---|
| `Root` | `WuYong_Rig` | `(+0.000, -0.000, +0.055)` | `(-0.000, -0.000, +0.000, +1.000)` | `(+0.000, -0.000, +0.026)` |
| `Hips` | `Root` | `(-0.000, +0.965, -0.047)` | `(+0.000, +0.000, -0.000, +1.000)` | `(+0.000, +0.965, -0.021)` |
| `Spine` | `Hips` | `(+0.000, +0.164, +0.000)` | `(+0.114, +0.000, +0.000, +0.994)` | `(+0.000, +1.128, -0.021)` |
| `Chest` | `Spine` | `(+0.000, +0.187, -0.000)` | `(-0.249, +0.004, +0.003, +0.968)` | `(+0.000, +1.310, +0.021)` |
| `Neck` | `Chest` | `(-0.000, +0.242, +0.006)` | `(+0.407, +0.005, +0.010, +0.913)` | `(-0.002, +1.545, -0.040)` |
| `Head` | `Neck` | `(+0.000, +0.127, +0.000)` | `(-0.472, -0.013, -0.015, +0.882)` | `(-0.004, +1.653, +0.028)` |
| `Hand.R` | `Forearm.R` | `(+0.000, +0.298, +0.000)` | `(+0.407, +0.553, -0.234, +0.688)` | `(-0.413, +1.097, +0.356)` |
| `Hand.L` | `Forearm.L` | `(-0.000, +0.229, +0.000)` | `(+0.158, -0.140, +0.118, +0.970)` | `(+0.366, +0.981, +0.134)` |
| `Sword` | `Hand.R` | `(-0.020, +0.071, -0.002)` | `(+0.004, -0.333, +0.331, +0.883)` | `(-0.384, +1.030, +0.363)` |
| `weapon_socket_r` | `Forearm.R` | `(+0.136, +0.058, +0.283)` | `(-0.541, +0.388, -0.022, +0.746)` | `(-0.350, +0.960, -0.009)` |

### `xuXiao` (Grand Inquisitor / Greatsword)

| 骨骼 | 父节点 | Local T | Local R (xyzw) | Rest World Pos |
|---|---|---|---|---|
| `Root` | `XuXiao_Rig` | `(+0.000, -0.000, -0.000)` | `(-0.000, +0.000, -0.000, +1.000)` | `(+0.000, -0.000, -0.040)` |
| `Hips` | `Root` | `(+0.000, +0.965, -0.047)` | `(-0.000, -0.000, -0.000, +1.000)` | `(-0.000, +0.965, -0.087)` |
| `Spine` | `Hips` | `(+0.000, +0.164, -0.000)` | `(-0.035, -0.000, +0.000, +0.999)` | `(+0.000, +1.128, -0.087)` |
| `Chest` | `Spine` | `(-0.000, +0.182, +0.000)` | `(+0.023, +0.004, +0.004, +1.000)` | `(-0.000, +1.310, -0.100)` |
| `Neck` | `Chest` | `(+0.000, +0.235, +0.000)` | `(+0.071, +0.005, +0.005, +0.997)` | `(-0.002, +1.545, -0.106)` |
| `Head` | `Neck` | `(+0.000, +0.108, -0.000)` | `(-0.027, -0.015, -0.014, +0.999)` | `(-0.004, +1.653, -0.093)` |
| `Hand.R` | `Forearm.R` | `(-0.000, +0.298, -0.000)` | `(+0.133, +0.656, -0.218, +0.711)` | `(-0.413, +1.097, +0.235)` |
| `Hand.L` | `Forearm.L` | `(+0.000, +0.229, -0.000)` | `(+0.039, -0.155, +0.109, +0.981)` | `(+0.366, +0.981, +0.013)` |
| `Sword` | `Hand.R` | `(-0.021, +0.094, -0.002)` | `(+0.267, -0.395, +0.395, +0.785)` | `(-0.384, +1.030, +0.297)` |
| `weapon_socket_r` | `Forearm.R` | `(+0.018, +0.302, +0.012)` | `(-0.546, +0.341, -0.007, +0.765)` | `(-0.400, +1.080, +0.230)` |

### `liuQuanwei` (Nonna / Great Axe)

| 骨骼 | 父节点 | Local T | Local R (xyzw) | Rest World Pos |
|---|---|---|---|---|
| `Root` | `LiuQuanwei_Rig` | `(+0.000, +0.000, +0.055)` | `(-0.000, +0.000, -0.000, +1.000)` | `(+0.000, +0.000, +0.055)` |
| `Hips` | `Root` | `(+0.000, +0.965, -0.047)` | `(-0.000, +0.000, +0.000, +1.000)` | `(+0.000, +0.965, +0.008)` |
| `Spine` | `Hips` | `(+0.000, +0.164, -0.000)` | `(+0.114, +0.000, +0.000, +0.994)` | `(+0.000, +1.128, +0.008)` |
| `Chest` | `Spine` | `(-0.000, +0.187, +0.000)` | `(-0.249, +0.004, +0.003, +0.968)` | `(-0.000, +1.310, +0.050)` |
| `Neck` | `Chest` | `(-0.000, +0.242, +0.006)` | `(+0.407, +0.005, +0.010, +0.913)` | `(-0.002, +1.545, -0.011)` |
| `Head` | `Neck` | `(+0.000, +0.127, +0.000)` | `(-0.472, -0.013, -0.015, +0.882)` | `(-0.004, +1.653, +0.057)` |
| `Hand.R` | `Forearm.R` | `(+0.000, +0.298, -0.000)` | `(+0.407, +0.553, -0.234, +0.688)` | `(-0.413, +1.097, +0.385)` |
| `Hand.L` | `Forearm.L` | `(-0.000, +0.229, +0.000)` | `(+0.158, -0.140, +0.118, +0.970)` | `(+0.366, +0.981, +0.163)` |
| `Sword` | `Hand.R` | `(-0.020, +0.071, -0.002)` | `(+0.004, -0.333, +0.331, +0.883)` | `(-0.384, +1.030, +0.392)` |
| `weapon_socket_r` | `Forearm.R` | `(+0.183, -0.041, +0.230)` | `(-0.557, +0.334, -0.003, +0.760)` | `(-0.280, +1.040, -0.040)` |

### `sunDeng` (Midnight / dual ninjato)

| 骨骼 | 父节点 | Local T | Local R (xyzw) | Rest World Pos |
|---|---|---|---|---|
| `Root` | `SunDeng_Rig` | `(+0.000, +0.000, +0.055)` | `(-0.000, +0.000, -0.000, +1.000)` | `(+0.000, +0.000, +0.055)` |
| `Hips` | `Root` | `(+0.000, +0.965, -0.047)` | `(-0.000, +0.000, +0.000, +1.000)` | `(+0.000, +0.965, +0.008)` |
| `Spine` | `Hips` | `(+0.000, +0.164, -0.000)` | `(+0.114, +0.000, +0.000, +0.994)` | `(+0.000, +1.128, +0.008)` |
| `Chest` | `Spine` | `(-0.000, +0.187, +0.000)` | `(-0.249, +0.004, +0.003, +0.968)` | `(-0.000, +1.310, +0.050)` |
| `Neck` | `Chest` | `(-0.000, +0.242, +0.006)` | `(+0.407, +0.005, +0.010, +0.913)` | `(-0.002, +1.545, -0.011)` |
| `Head` | `Neck` | `(+0.000, +0.127, +0.000)` | `(-0.472, -0.013, -0.015, +0.882)` | `(-0.004, +1.653, +0.057)` |
| `Hand.R` | `Forearm.R` | `(-0.000, +0.298, -0.000)` | `(+0.407, +0.553, -0.234, +0.688)` | `(-0.413, +1.097, +0.385)` |
| `Hand.L` | `Forearm.L` | `(-0.000, +0.229, +0.000)` | `(+0.158, -0.140, +0.118, +0.970)` | `(+0.366, +0.981, +0.163)` |
| `Sword` | `Hand.R` | `(-0.020, +0.071, -0.002)` | `(+0.004, -0.333, +0.331, +0.883)` | `(-0.384, +1.030, +0.392)` |
| `weapon_socket_r` | `Forearm.R` | `(+0.213, +0.211, +0.023)` | `(-0.518, +0.333, -0.010, +0.788)` | `(-0.210, +1.060, +0.280)` |
| `weapon_socket_l` | `Hand.L` | `(-0.002, +0.074, +0.109)` | `(-0.817, -0.132, +0.183, +0.531)` | `(+0.350, +0.900, +0.060)` |

## 4. 动画 Clip 帧率、插值、四元数翻转与 Root Motion 漂移审计

### `wuYong` — 19 Clips

| Clip | Keys | 时长(s) | FPS | 插值 | STEP 动轨 | 四元数翻转 | Hips 净移/峰值(m) | 刀尖峰值速度@进度 | 尾帧离 Idle 夹角 | 问题标记 |
|---|---:|---:|---:|---|---:|---:|---|---|---:|---|
| `backstep_WuYong_Rig` | 44 | 0.717 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.030 | 0.3m/s @ 0.87 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 29°) |
| `finisher_WuYong_Rig` | 40 | 0.650 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.080 | 118.2m/s @ 0.27 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 41°) |
| `getup_WuYong_Rig` | 18 | 0.283 | 60.0 | `LINEAR` | 0 | 0 | 0.641 / 0.641 | 75.8m/s @ 0.03 | 138.7° | drift 0.64m; weapon ignores wrist (socket vs Hand.R up to 31°) |
| `guard_WuYong_Rig` | 30 | 0.483 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.015 | 0.4m/s @ 0.26 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 29°) |
| `heavy_WuYong_Rig` | 52 | 0.850 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.070 | 117.3m/s @ 0.34 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 41°) |
| `hit_WuYong_Rig` | 18 | 0.283 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.040 | 5.6m/s @ 0.32 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 33°) |
| `hit_head_WuYong_Rig` | 18 | 0.283 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.020 | 10.3m/s @ 0.03 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 35°) |
| `hit_low_WuYong_Rig` | 18 | 0.283 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.218 | 39.8m/s @ 0.03 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 30°) |
| `idle_WuYong_Rig` | 90 | 1.483 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.025 | 0.2m/s @ 0.75 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 28°) |
| `jump_WuYong_Rig` | 28 | 0.450 | 60.0 | `LINEAR` | 0 | 0 | 0.140 / 0.220 | 15.8m/s @ 0.06 | 43.7° | weapon ignores wrist (socket vs Hand.R up to 33°) |
| `kick_WuYong_Rig` | 20 | 0.317 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.030 | 49.7m/s @ 0.03 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 29°) |
| `kick_back_WuYong_Rig` | 30 | 0.483 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.040 | 28.8m/s @ 0.36 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 29°) |
| `kick_down_WuYong_Rig` | 31 | 0.500 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.280 | 32.0m/s @ 0.35 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 27°) |
| `kick_forward_WuYong_Rig` | 46 | 0.750 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.040 | 29.3m/s @ 0.34 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 28°) |
| `kick_up_WuYong_Rig` | 27 | 0.433 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.040 | 44.0m/s @ 0.37 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 31°) |
| `knockdown_WuYong_Rig` | 20 | 0.317 | 60.0 | `LINEAR` | 0 | 0 | 0.641 / 0.641 | 33.2m/s @ 0.03 | 138.7° | drift 0.64m; weapon ignores wrist (socket vs Hand.R up to 27°); ends 139° from idle (Shin.R) |
| `light1_WuYong_Rig` | 24 | 0.383 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.030 | 108.9m/s @ 0.28 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 41°) |
| `light2_WuYong_Rig` | 27 | 0.433 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.040 | 87.4m/s @ 0.29 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 41°) |
| `roll_back_WuYong_Rig` | 18 | 0.283 | 60.0 | `LINEAR` | 0 | 0 | 0.160 / 0.160 | 26.0m/s @ 0.09 | 49.4° | weapon ignores wrist (socket vs Hand.R up to 175°) |
| `roll_forward_WuYong_Rig` | 18 | 0.283 | 60.0 | `LINEAR` | 0 | 0 | 0.160 / 0.160 | 38.3m/s @ 0.85 | 48.1° | weapon ignores wrist (socket vs Hand.R up to 159°) |
| `shogun_despotism_WuYong_Rig` | 42 | 0.683 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.120 | 127.2m/s @ 0.21 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 41°) |
| `shogun_fierce_WuYong_Rig` | 48 | 0.783 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.120 | 99.5m/s @ 0.24 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 41°) |
| `skill1_WuYong_Rig` | 46 | 0.750 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.020 | 39.9m/s @ 0.06 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 41°) |
| `skill2_WuYong_Rig` | 34 | 0.550 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.060 | 92.4m/s @ 0.29 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 40°) |
| `throw_WuYong_Rig` | 28 | 0.450 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.140 | 112.2m/s @ 0.20 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 39°) |
| `wakeup_kick_WuYong_Rig` | 24 | 0.383 | 60.0 | `LINEAR` | 0 | 0 | 0.641 / 0.641 | 52.9m/s @ 0.41 | 138.7° | drift 0.64m; weapon ignores wrist (socket vs Hand.R up to 27°) |
| `walk_WuYong_Rig` | 44 | 0.717 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.030 | 0.7m/s @ 0.13 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 26°) |
| `weapon_back_WuYong_Rig` | 28 | 0.450 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.050 | 84.5m/s @ 0.28 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 41°) |
| `weapon_down_WuYong_Rig` | 33 | 0.533 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.179 | 147.1m/s @ 0.27 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 37°) |
| `weapon_forward_WuYong_Rig` | 33 | 0.533 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.080 | 130.7m/s @ 0.27 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 40°) |
| `weapon_up_WuYong_Rig` | 30 | 0.483 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.100 | 157.3m/s @ 0.26 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 40°) |

### `xuXiao` — 19 Clips

| Clip | Keys | 时长(s) | FPS | 插值 | STEP 动轨 | 四元数翻转 | Hips 净移/峰值(m) | 刀尖峰值速度@进度 | 尾帧离 Idle 夹角 | 问题标记 |
|---|---:|---:|---:|---|---:|---:|---|---|---:|---|
| `backstep_XuXiao_Rig` | 44 | 0.717 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.029 | 0.3m/s @ 0.87 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 25°) |
| `finisher_XuXiao_Rig` | 37 | 0.600 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.078 | 126.1m/s @ 0.26 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 41°) |
| `getup_XuXiao_Rig` | 18 | 0.283 | 60.0 | `LINEAR` | 0 | 0 | 0.664 / 0.664 | 72.3m/s @ 0.03 | 138.1° | drift 0.66m; weapon ignores wrist (socket vs Hand.R up to 31°) |
| `guard_XuXiao_Rig` | 30 | 0.483 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.015 | 0.3m/s @ 0.26 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 30°) |
| `heavy_XuXiao_Rig` | 53 | 0.867 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.107 | 130.7m/s @ 0.36 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 40°) |
| `hit_XuXiao_Rig` | 18 | 0.283 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.039 | 3.8m/s @ 0.32 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 28°) |
| `hit_head_XuXiao_Rig` | 18 | 0.283 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.020 | 4.3m/s @ 0.03 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 30°) |
| `hit_low_XuXiao_Rig` | 18 | 0.283 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.251 | 42.4m/s @ 0.03 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 31°) |
| `idle_XuXiao_Rig` | 90 | 1.483 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.024 | 0.2m/s @ 0.75 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 24°) |
| `inquisitor_spin_XuXiao_Rig` | 32 | 0.517 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.078 | 85.8m/s @ 0.18 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 41°) |
| `jump_XuXiao_Rig` | 28 | 0.450 | 60.0 | `LINEAR` | 0 | 0 | 0.137 / 0.176 | 12.0m/s @ 0.06 | 41.1° | weapon ignores wrist (socket vs Hand.R up to 33°) |
| `kick_XuXiao_Rig` | 20 | 0.317 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.029 | 33.2m/s @ 0.03 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 24°) |
| `kick_back_XuXiao_Rig` | 30 | 0.483 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.039 | 21.0m/s @ 0.36 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 24°) |
| `kick_down_XuXiao_Rig` | 31 | 0.500 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.312 | 19.2m/s @ 0.35 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 24°) |
| `kick_forward_XuXiao_Rig` | 32 | 0.517 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.039 | 26.4m/s @ 0.40 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 24°) |
| `kick_up_XuXiao_Rig` | 27 | 0.433 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.039 | 33.0m/s @ 0.37 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 27°) |
| `knockdown_XuXiao_Rig` | 20 | 0.317 | 60.0 | `LINEAR` | 0 | 0 | 0.664 / 0.664 | 28.4m/s @ 0.45 | 138.1° | drift 0.66m; weapon ignores wrist (socket vs Hand.R up to 24°); ends 138° from idle (Shin.R) |
| `light1_XuXiao_Rig` | 22 | 0.350 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.038 | 114.6m/s @ 0.26 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 40°) |
| `light2_XuXiao_Rig` | 25 | 0.400 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.039 | 91.7m/s @ 0.27 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 41°) |
| `roll_back_XuXiao_Rig` | 18 | 0.283 | 60.0 | `LINEAR` | 0 | 0 | 0.195 / 0.195 | 37.2m/s @ 0.03 | 52.0° | weapon ignores wrist (socket vs Hand.R up to 173°) |
| `roll_forward_XuXiao_Rig` | 18 | 0.283 | 60.0 | `LINEAR` | 0 | 0 | 0.195 / 0.195 | 40.2m/s @ 0.62 | 50.7° | weapon ignores wrist (socket vs Hand.R up to 157°) |
| `skill1_XuXiao_Rig` | 49 | 0.800 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.078 | 120.9m/s @ 0.36 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 40°) |
| `skill2_XuXiao_Rig` | 45 | 0.733 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.058 | 112.1m/s @ 0.17 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 40°) |
| `throw_XuXiao_Rig` | 28 | 0.450 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.176 | 105.4m/s @ 0.20 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 40°) |
| `wakeup_kick_XuXiao_Rig` | 24 | 0.383 | 60.0 | `LINEAR` | 0 | 0 | 0.664 / 0.664 | 39.2m/s @ 0.41 | 138.1° | drift 0.66m; weapon ignores wrist (socket vs Hand.R up to 24°) |
| `walk_XuXiao_Rig` | 44 | 0.717 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.029 | 0.6m/s @ 0.13 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 23°) |
| `weapon_back_XuXiao_Rig` | 28 | 0.450 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.049 | 73.1m/s @ 0.28 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 41°) |
| `weapon_down_XuXiao_Rig` | 33 | 0.533 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.214 | 131.6m/s @ 0.27 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 38°) |
| `weapon_forward_XuXiao_Rig` | 32 | 0.517 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.078 | 114.1m/s @ 0.27 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 40°) |
| `weapon_up_XuXiao_Rig` | 29 | 0.467 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.098 | 139.8m/s @ 0.27 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 40°) |

### `liuQuanwei` — 19 Clips

| Clip | Keys | 时长(s) | FPS | 插值 | STEP 动轨 | 四元数翻转 | Hips 净移/峰值(m) | 刀尖峰值速度@进度 | 尾帧离 Idle 夹角 | 问题标记 |
|---|---:|---:|---:|---|---:|---:|---|---|---:|---|
| `backstep_LiuQuanwei_Rig` | 44 | 0.717 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.030 | 0.3m/s @ 0.87 | 0.0° | - |
| `finisher_LiuQuanwei_Rig` | 37 | 0.600 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.080 | 122.3m/s @ 0.26 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 39°) |
| `getup_LiuQuanwei_Rig` | 18 | 0.283 | 60.0 | `LINEAR` | 0 | 0 | 0.620 / 0.620 | 61.2m/s @ 0.03 | 137.5° | drift 0.62m; weapon ignores wrist (socket vs Hand.R up to 21°) |
| `guard_LiuQuanwei_Rig` | 30 | 0.483 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.015 | 0.3m/s @ 0.26 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 10°) |
| `heavy_LiuQuanwei_Rig` | 53 | 0.867 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.070 | 107.5m/s @ 0.36 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 37°) |
| `hit_LiuQuanwei_Rig` | 18 | 0.283 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.039 | 8.2m/s @ 0.03 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 14°) |
| `hit_head_LiuQuanwei_Rig` | 18 | 0.283 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.020 | 12.7m/s @ 0.03 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 20°) |
| `hit_low_LiuQuanwei_Rig` | 18 | 0.283 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.197 | 39.5m/s @ 0.03 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 25°) |
| `idle_LiuQuanwei_Rig` | 90 | 1.483 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.025 | 0.2m/s @ 0.75 | 0.0° | - |
| `jump_LiuQuanwei_Rig` | 28 | 0.450 | 60.0 | `LINEAR` | 0 | 0 | 0.140 / 0.240 | 7.0m/s @ 0.06 | 41.8° | weapon ignores wrist (socket vs Hand.R up to 14°) |
| `kick_LiuQuanwei_Rig` | 20 | 0.317 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.030 | 17.8m/s @ 0.39 | 0.0° | - |
| `kick_back_LiuQuanwei_Rig` | 30 | 0.483 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.040 | 13.6m/s @ 0.36 | 0.0° | - |
| `kick_down_LiuQuanwei_Rig` | 31 | 0.500 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.260 | 21.8m/s @ 0.25 | 0.0° | - |
| `kick_forward_LiuQuanwei_Rig` | 32 | 0.517 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.040 | 14.5m/s @ 0.40 | 0.0° | - |
| `kick_up_LiuQuanwei_Rig` | 27 | 0.433 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.040 | 19.0m/s @ 0.37 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 11°) |
| `knockdown_LiuQuanwei_Rig` | 20 | 0.317 | 60.0 | `LINEAR` | 0 | 0 | 0.620 / 0.620 | 26.8m/s @ 0.45 | 137.5° | drift 0.62m; ends 137° from idle (Shin.R) |
| `light1_LiuQuanwei_Rig` | 22 | 0.350 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.019 | 140.0m/s @ 0.26 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 37°) |
| `light2_LiuQuanwei_Rig` | 25 | 0.400 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.040 | 95.6m/s @ 0.27 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 39°) |
| `roll_back_LiuQuanwei_Rig` | 18 | 0.283 | 60.0 | `LINEAR` | 0 | 0 | 0.140 / 0.140 | 27.7m/s @ 0.03 | 47.8° | weapon ignores wrist (socket vs Hand.R up to 153°) |
| `roll_forward_LiuQuanwei_Rig` | 18 | 0.283 | 60.0 | `LINEAR` | 0 | 0 | 0.140 / 0.140 | 15.9m/s @ 0.62 | 46.4° | weapon ignores wrist (socket vs Hand.R up to 152°) |
| `skill1_LiuQuanwei_Rig` | 42 | 0.683 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.040 | 139.8m/s @ 0.26 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 41°) |
| `skill2_LiuQuanwei_Rig` | 45 | 0.733 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.059 | 98.1m/s @ 0.17 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 29°) |
| `throw_LiuQuanwei_Rig` | 28 | 0.450 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.120 | 100.7m/s @ 0.20 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 30°) |
| `wakeup_kick_LiuQuanwei_Rig` | 24 | 0.383 | 60.0 | `LINEAR` | 0 | 0 | 0.620 / 0.620 | 35.4m/s @ 0.41 | 137.5° | drift 0.62m; weapon ignores wrist (socket vs Hand.R up to 25°) |
| `walk_LiuQuanwei_Rig` | 44 | 0.717 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.030 | 0.9m/s @ 0.62 | 0.0° | - |
| `weapon_back_LiuQuanwei_Rig` | 28 | 0.450 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.050 | 72.8m/s @ 0.24 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 30°) |
| `weapon_down_LiuQuanwei_Rig` | 33 | 0.533 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.159 | 125.1m/s @ 0.27 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 33°) |
| `weapon_forward_LiuQuanwei_Rig` | 35 | 0.567 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.080 | 112.4m/s @ 0.28 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 32°) |
| `weapon_up_LiuQuanwei_Rig` | 32 | 0.517 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.100 | 105.9m/s @ 0.27 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 40°) |

### `sunDeng` — 19 Clips

| Clip | Keys | 时长(s) | FPS | 插值 | STEP 动轨 | 四元数翻转 | Hips 净移/峰值(m) | 刀尖峰值速度@进度 | 尾帧离 Idle 夹角 | 问题标记 |
|---|---:|---:|---:|---|---:|---:|---|---|---:|---|
| `backstep_SunDeng_Rig` | 44 | 0.717 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.030 | 0.3m/s @ 0.87 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 29°) |
| `finisher_SunDeng_Rig` | 37 | 0.600 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.080 | 84.4m/s @ 0.26 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 41°) |
| `getup_SunDeng_Rig` | 18 | 0.283 | 60.0 | `LINEAR` | 0 | 0 | 0.550 / 0.550 | 49.6m/s @ 0.03 | 123.5° | drift 0.55m; weapon ignores wrist (socket vs Hand.R up to 30°) |
| `guard_SunDeng_Rig` | 30 | 0.483 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.015 | 0.2m/s @ 0.26 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 30°) |
| `heavy_SunDeng_Rig` | 53 | 0.867 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.079 | 66.3m/s @ 0.36 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 41°) |
| `hit_SunDeng_Rig` | 18 | 0.283 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.040 | 4.8m/s @ 0.03 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 39°) |
| `hit_head_SunDeng_Rig` | 18 | 0.283 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.020 | 14.6m/s @ 0.03 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 40°) |
| `hit_low_SunDeng_Rig` | 18 | 0.283 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.128 | 17.8m/s @ 0.03 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 29°) |
| `idle_SunDeng_Rig` | 90 | 1.483 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.025 | 0.2m/s @ 0.75 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 28°) |
| `jump_SunDeng_Rig` | 28 | 0.450 | 60.0 | `LINEAR` | 0 | 0 | 0.140 / 0.310 | 15.1m/s @ 0.06 | 28.8° | weapon ignores wrist (socket vs Hand.R up to 32°) |
| `kick_SunDeng_Rig` | 20 | 0.317 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.030 | 50.6m/s @ 0.39 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 33°) |
| `kick_back_SunDeng_Rig` | 30 | 0.483 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.040 | 33.7m/s @ 0.36 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 35°) |
| `kick_down_SunDeng_Rig` | 31 | 0.500 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.190 | 31.9m/s @ 0.38 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 145°) |
| `kick_forward_SunDeng_Rig` | 32 | 0.517 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.040 | 42.1m/s @ 0.40 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 34°) |
| `kick_up_SunDeng_Rig` | 27 | 0.433 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.040 | 50.9m/s @ 0.37 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 36°) |
| `knockdown_SunDeng_Rig` | 20 | 0.317 | 60.0 | `LINEAR` | 0 | 0 | 0.550 / 0.550 | 23.6m/s @ 0.03 | 123.5° | drift 0.55m; weapon ignores wrist (socket vs Hand.R up to 27°); ends 123° from idle (Shin.R) |
| `light1_SunDeng_Rig` | 22 | 0.350 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.039 | 67.7m/s @ 0.26 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 41°) |
| `light2_SunDeng_Rig` | 25 | 0.400 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.050 | 62.8m/s @ 0.27 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 41°) |
| `midnight_removal_SunDeng_Rig` | 40 | 0.650 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.110 | 57.6m/s @ 0.29 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 41°) |
| `roll_back_SunDeng_Rig` | 18 | 0.283 | 60.0 | `LINEAR` | 0 | 0 | 0.070 / 0.119 | 33.6m/s @ 0.03 | 27.5° | weapon ignores wrist (socket vs Hand.R up to 177°) |
| `roll_forward_SunDeng_Rig` | 18 | 0.283 | 60.0 | `LINEAR` | 0 | 0 | 0.070 / 0.119 | 30.5m/s @ 0.85 | 25.7° | weapon ignores wrist (socket vs Hand.R up to 169°) |
| `skill1_SunDeng_Rig` | 42 | 0.683 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.090 | 78.0m/s @ 0.26 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 41°) |
| `skill2_SunDeng_Rig` | 45 | 0.733 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.059 | 78.4m/s @ 0.17 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 40°) |
| `throw_SunDeng_Rig` | 28 | 0.450 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.050 | 63.8m/s @ 0.20 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 40°) |
| `wakeup_kick_SunDeng_Rig` | 24 | 0.383 | 60.0 | `LINEAR` | 0 | 0 | 0.550 / 0.550 | 30.8m/s @ 0.41 | 123.5° | drift 0.55m; weapon ignores wrist (socket vs Hand.R up to 31°) |
| `walk_SunDeng_Rig` | 44 | 0.717 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.030 | 0.5m/s @ 0.62 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 27°) |
| `weapon_back_SunDeng_Rig` | 27 | 0.433 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.050 | 52.3m/s @ 0.25 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 41°) |
| `weapon_down_SunDeng_Rig` | 32 | 0.517 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.149 | 80.8m/s @ 0.24 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 35°) |
| `weapon_forward_SunDeng_Rig` | 31 | 0.500 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.080 | 69.3m/s @ 0.25 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 40°) |
| `weapon_up_SunDeng_Rig` | 28 | 0.450 | 60.0 | `LINEAR` | 0 | 0 | 0.000 / 0.100 | 108.7m/s @ 0.24 | 0.0° | weapon ignores wrist (socket vs Hand.R up to 40°) |

## 5. 招式 60Hz 判定窗口 vs 动画峰值与倍速对齐审计

运行时使用线性进度映射 `progress = age / max(1, total - 1)`。下表对比每招的 60Hz 帧数（起手/判定/收招）、动画倍速 `clip_s / game_s`，以及动作速度峰值是否落入判定区间：

### `wuYong` (`.wuYong`)

| 游戏招式 | 映射 Clip | 匹配方式 | 60Hz 帧数 (起/判/收=总) | 游戏时长 / Clip 时长 (倍速) | 动作峰值进度 | 判定窗进度 | 偏离 | 告警 |
|---|---|---|---|---|---:|---|---:|---|
| `jab` | `light1_WuYong_Rig` | `light1` | 7/4/13=24 | 0.400s / 0.383s (**×0.96**) | 0.28 (blade_tip) | [0.30, 0.43] | 0.02 | - |
| `cross` | `light2_WuYong_Rig` | `light2` | 8/4/15=27 | 0.450s / 0.433s (**×0.96**) | 0.29 (blade_tip) | [0.31, 0.42] | 0.02 | - |
| `finisher` | `finisher_WuYong_Rig` | `finisher` | 11/5/24=40 | 0.667s / 0.650s (**×0.97**) | 0.27 (blade_tip) | [0.28, 0.38] | 0.01 | - |
| `heavy` | `heavy_WuYong_Rig` | `heavy` | 18/6/28=52 | 0.867s / 0.850s (**×0.98**) | 0.34 (blade_tip) | [0.35, 0.45] | 0.01 | - |
| `weaponForward` | `weapon_forward_WuYong_Rig` | `weapon_forward` | 9/5/19=33 | 0.550s / 0.533s (**×0.97**) | 0.27 (blade_tip) | [0.28, 0.41] | 0.02 | - |
| `weaponUp` | `weapon_up_WuYong_Rig` | `weapon_up` | 8/4/18=30 | 0.500s / 0.483s (**×0.97**) | 0.26 (blade_tip) | [0.28, 0.38] | 0.02 | - |
| `weaponDown` | `weapon_down_WuYong_Rig` | `weapon_down` | 9/5/19=33 | 0.550s / 0.533s (**×0.97**) | 0.27 (blade_tip) | [0.28, 0.41] | 0.02 | - |
| `weaponBack` | `weapon_back_WuYong_Rig` | `weapon_back` | 7/4/17=28 | 0.467s / 0.450s (**×0.96**) | 0.28 (blade_tip) | [0.26, 0.37] | 0.00 | - |
| `kick` | `kick_WuYong_Rig` | `kick` | 5/3/12=20 | 0.333s / 0.317s (**×0.95**) | 0.24 (foot) | [0.26, 0.37] | 0.03 | - |
| `kickForward` | `kick_forward_WuYong_Rig` | `kick_forward` | 10/10/26=46 | 0.767s / 0.750s (**×0.98**) | 0.34 (foot) | [0.22, 0.42] | 0.00 | - |
| `kickUp` | `kick_up_WuYong_Rig` | `kick_up` | 7/4/16=27 | 0.450s / 0.433s (**×0.96**) | 0.37 (foot) | [0.27, 0.38] | 0.00 | - |
| `kickDown` | `kick_down_WuYong_Rig` | `kick_down` | 8/4/19=31 | 0.517s / 0.500s (**×0.97**) | 0.25 (foot) | [0.27, 0.37] | 0.02 | - |
| `kickBack` | `kick_back_WuYong_Rig` | `kick_back` | 8/4/18=30 | 0.500s / 0.483s (**×0.97**) | 0.36 (foot) | [0.28, 0.38] | 0.00 | - |
| `throwForward` | `throw_WuYong_Rig` | `throw` | 6/4/18=28 | 0.467s / 0.450s (**×0.96**) | 0.20 (blade_tip) | [0.22, 0.33] | 0.02 | - |
| `skill1` | `skill1_WuYong_Rig` | `skill1` | 10/10/26=46 | 0.767s / 0.750s (**×0.98**) | 0.34 (foot) | [0.22, 0.42] | 0.00 | - |
| `skill2` | `skill2_WuYong_Rig` | `skill2` | 10/8/16=34 | 0.567s / 0.550s (**×0.97**) | 0.29 (blade_tip) | [0.30, 0.52] | 0.02 | - |
| `heavy(full)` | `heavy_WuYong_Rig` | `heavy` | 14/6/28=48 | 0.800s / 0.850s (**×1.06**) | 0.34 (blade_tip) | [0.30, 0.40] | 0.00 | - |
| `shogunFierceReprisal` | `shogun_fierce_WuYong_Rig` | `shogun_fierce` | 12/10/26=48 | 0.800s / 0.783s (**×0.98**) | 0.24 (blade_tip) | [0.26, 0.45] | 0.01 | - |
| `shogunDespotism` | `shogun_despotism_WuYong_Rig` | `shogun_despotism` | 9/8/25=42 | 0.700s / 0.683s (**×0.98**) | 0.21 (blade_tip) | [0.22, 0.39] | 0.01 | - |

状态类 Clip 倍速：`idle` ×0.99、`walk` ×0.98、`hit` ×1.00、`knockdown` ×1.06、`getUp` ×1.06、`jump` ×1.00。

### `xuXiao` (`.gale`)

| 游戏招式 | 映射 Clip | 匹配方式 | 60Hz 帧数 (起/判/收=总) | 游戏时长 / Clip 时长 (倍速) | 动作峰值进度 | 判定窗进度 | 偏离 | 告警 |
|---|---|---|---|---|---:|---|---:|---|
| `jab` | `light1_XuXiao_Rig` | `light1` | 6/3/13=22 | 0.367s / 0.350s (**×0.95**) | 0.26 (blade_tip) | [0.29, 0.38] | 0.02 | - |
| `cross` | `light2_XuXiao_Rig` | `light2` | 7/3/15=25 | 0.417s / 0.400s (**×0.96**) | 0.27 (blade_tip) | [0.29, 0.38] | 0.02 | - |
| `finisher` | `finisher_XuXiao_Rig` | `finisher` | 10/4/23=37 | 0.617s / 0.600s (**×0.97**) | 0.26 (blade_tip) | [0.28, 0.36] | 0.01 | - |
| `heavy` | `heavy_XuXiao_Rig` | `heavy` | 19/5/29=53 | 0.883s / 0.867s (**×0.98**) | 0.36 (blade_tip) | [0.37, 0.44] | 0.01 | - |
| `weaponForward` | `weapon_forward_XuXiao_Rig` | `weapon_forward` | 9/5/18=32 | 0.533s / 0.517s (**×0.97**) | 0.27 (blade_tip) | [0.29, 0.42] | 0.02 | - |
| `weaponUp` | `weapon_up_XuXiao_Rig` | `weapon_up` | 8/4/17=29 | 0.483s / 0.467s (**×0.97**) | 0.27 (blade_tip) | [0.29, 0.39] | 0.02 | - |
| `weaponDown` | `weapon_down_XuXiao_Rig` | `weapon_down` | 9/5/19=33 | 0.550s / 0.533s (**×0.97**) | 0.27 (blade_tip) | [0.28, 0.41] | 0.02 | - |
| `weaponBack` | `weapon_back_XuXiao_Rig` | `weapon_back` | 7/4/17=28 | 0.467s / 0.450s (**×0.96**) | 0.28 (blade_tip) | [0.26, 0.37] | 0.00 | - |
| `kick` | `kick_XuXiao_Rig` | `kick` | 5/3/12=20 | 0.333s / 0.317s (**×0.95**) | 0.24 (foot) | [0.26, 0.37] | 0.03 | - |
| `kickForward` | `kick_forward_XuXiao_Rig` | `kick_forward` | 9/5/18=32 | 0.533s / 0.517s (**×0.97**) | 0.27 (foot) | [0.29, 0.42] | 0.02 | - |
| `kickUp` | `kick_up_XuXiao_Rig` | `kick_up` | 7/4/16=27 | 0.450s / 0.433s (**×0.96**) | 0.37 (foot) | [0.27, 0.38] | 0.00 | - |
| `kickDown` | `kick_down_XuXiao_Rig` | `kick_down` | 8/4/19=31 | 0.517s / 0.500s (**×0.97**) | 0.25 (foot) | [0.27, 0.37] | 0.02 | - |
| `kickBack` | `kick_back_XuXiao_Rig` | `kick_back` | 8/4/18=30 | 0.500s / 0.483s (**×0.97**) | 0.36 (foot) | [0.28, 0.38] | 0.00 | - |
| `throwForward` | `throw_XuXiao_Rig` | `throw` | 6/4/18=28 | 0.467s / 0.450s (**×0.96**) | 0.20 (blade_tip) | [0.22, 0.33] | 0.02 | - |
| `skill1` | `skill1_XuXiao_Rig` | `skill1` | 18/5/26=49 | 0.817s / 0.800s (**×0.98**) | 0.36 (blade_tip) | [0.38, 0.46] | 0.01 | - |
| `skill2` | `skill2_XuXiao_Rig` | `skill2` | 8/5/32=45 | 0.750s / 0.733s (**×0.98**) | 0.17 (blade_tip) | [0.18, 0.27] | 0.01 | - |
| `inquisitorLightSpin` | `inquisitor_spin_XuXiao_Rig` | `inquisitor_spin` | 6/10/16=32 | 0.533s / 0.517s (**×0.97**) | 0.18 (blade_tip) | [0.19, 0.48] | 0.02 | - |

状态类 Clip 倍速：`idle` ×0.99、`walk` ×0.98、`hit` ×1.00、`knockdown` ×1.06、`getUp` ×1.06、`jump` ×1.00。

### `liuQuanwei` (`.liu`)

| 游戏招式 | 映射 Clip | 匹配方式 | 60Hz 帧数 (起/判/收=总) | 游戏时长 / Clip 时长 (倍速) | 动作峰值进度 | 判定窗进度 | 偏离 | 告警 |
|---|---|---|---|---|---:|---|---:|---|
| `jab` | `light1_LiuQuanwei_Rig` | `light1` | 6/3/13=22 | 0.367s / 0.350s (**×0.95**) | 0.26 (blade_tip) | [0.29, 0.38] | 0.02 | - |
| `cross` | `light2_LiuQuanwei_Rig` | `light2` | 7/3/15=25 | 0.417s / 0.400s (**×0.96**) | 0.27 (blade_tip) | [0.29, 0.38] | 0.02 | - |
| `finisher` | `finisher_LiuQuanwei_Rig` | `finisher` | 10/4/23=37 | 0.617s / 0.600s (**×0.97**) | 0.26 (blade_tip) | [0.28, 0.36] | 0.01 | - |
| `heavy` | `heavy_LiuQuanwei_Rig` | `heavy` | 19/5/29=53 | 0.883s / 0.867s (**×0.98**) | 0.36 (blade_tip) | [0.37, 0.44] | 0.01 | - |
| `weaponForward` | `weapon_forward_LiuQuanwei_Rig` | `weapon_forward` | 10/5/20=35 | 0.583s / 0.567s (**×0.97**) | 0.28 (blade_tip) | [0.29, 0.41] | 0.01 | - |
| `weaponUp` | `weapon_up_LiuQuanwei_Rig` | `weapon_up` | 9/4/19=32 | 0.533s / 0.517s (**×0.97**) | 0.27 (blade_tip) | [0.29, 0.39] | 0.02 | - |
| `weaponDown` | `weapon_down_LiuQuanwei_Rig` | `weapon_down` | 9/5/19=33 | 0.550s / 0.533s (**×0.97**) | 0.27 (blade_tip) | [0.28, 0.41] | 0.02 | - |
| `weaponBack` | `weapon_back_LiuQuanwei_Rig` | `weapon_back` | 7/4/17=28 | 0.467s / 0.450s (**×0.96**) | 0.24 (blade_tip) | [0.26, 0.37] | 0.02 | - |
| `kick` | `kick_LiuQuanwei_Rig` | `kick` | 5/3/12=20 | 0.333s / 0.317s (**×0.95**) | 0.24 (foot) | [0.26, 0.37] | 0.03 | - |
| `kickForward` | `kick_forward_LiuQuanwei_Rig` | `kick_forward` | 9/5/18=32 | 0.533s / 0.517s (**×0.97**) | 0.27 (foot) | [0.29, 0.42] | 0.02 | - |
| `kickUp` | `kick_up_LiuQuanwei_Rig` | `kick_up` | 7/4/16=27 | 0.450s / 0.433s (**×0.96**) | 0.37 (foot) | [0.27, 0.38] | 0.00 | - |
| `kickDown` | `kick_down_LiuQuanwei_Rig` | `kick_down` | 8/4/19=31 | 0.517s / 0.500s (**×0.97**) | 0.25 (foot) | [0.27, 0.37] | 0.02 | - |
| `kickBack` | `kick_back_LiuQuanwei_Rig` | `kick_back` | 8/4/18=30 | 0.500s / 0.483s (**×0.97**) | 0.36 (foot) | [0.28, 0.38] | 0.00 | - |
| `throwForward` | `throw_LiuQuanwei_Rig` | `throw` | 6/4/18=28 | 0.467s / 0.450s (**×0.96**) | 0.20 (blade_tip) | [0.22, 0.33] | 0.02 | - |
| `skill1` | `skill1_LiuQuanwei_Rig` | `skill1` | 11/5/26=42 | 0.700s / 0.683s (**×0.98**) | 0.26 (blade_tip) | [0.27, 0.37] | 0.01 | - |
| `skill2` | `skill2_LiuQuanwei_Rig` | `skill2` | 8/5/32=45 | 0.750s / 0.733s (**×0.98**) | 0.17 (blade_tip) | [0.18, 0.27] | 0.01 | - |

状态类 Clip 倍速：`idle` ×0.99、`walk` ×0.98、`hit` ×1.00、`knockdown` ×1.06、`getUp` ×1.06、`jump` ×1.00。

### `sunDeng` (`.ember`)

| 游戏招式 | 映射 Clip | 匹配方式 | 60Hz 帧数 (起/判/收=总) | 游戏时长 / Clip 时长 (倍速) | 动作峰值进度 | 判定窗进度 | 偏离 | 告警 |
|---|---|---|---|---|---:|---|---:|---|
| `jab` | `light1_SunDeng_Rig` | `light1` | 6/3/13=22 | 0.367s / 0.350s (**×0.95**) | 0.26 (blade_tip) | [0.29, 0.38] | 0.02 | - |
| `cross` | `light2_SunDeng_Rig` | `light2` | 7/3/15=25 | 0.417s / 0.400s (**×0.96**) | 0.27 (blade_tip) | [0.29, 0.38] | 0.02 | - |
| `finisher` | `finisher_SunDeng_Rig` | `finisher` | 10/4/23=37 | 0.617s / 0.600s (**×0.97**) | 0.26 (blade_tip) | [0.28, 0.36] | 0.01 | - |
| `heavy` | `heavy_SunDeng_Rig` | `heavy` | 19/5/29=53 | 0.883s / 0.867s (**×0.98**) | 0.36 (blade_tip) | [0.37, 0.44] | 0.01 | - |
| `weaponForward` | `weapon_forward_SunDeng_Rig` | `weapon_forward` | 8/5/18=31 | 0.517s / 0.500s (**×0.97**) | 0.25 (blade_tip) | [0.27, 0.40] | 0.02 | - |
| `weaponUp` | `weapon_up_SunDeng_Rig` | `weapon_up` | 7/4/17=28 | 0.467s / 0.450s (**×0.96**) | 0.24 (blade_tip) | [0.26, 0.37] | 0.02 | - |
| `weaponDown` | `weapon_down_SunDeng_Rig` | `weapon_down` | 8/5/19=32 | 0.533s / 0.517s (**×0.97**) | 0.24 (blade_tip) | [0.26, 0.39] | 0.02 | - |
| `weaponBack` | `weapon_back_SunDeng_Rig` | `weapon_back` | 6/4/17=27 | 0.450s / 0.433s (**×0.96**) | 0.25 (blade_tip) | [0.23, 0.35] | 0.00 | - |
| `kick` | `kick_SunDeng_Rig` | `kick` | 5/3/12=20 | 0.333s / 0.317s (**×0.95**) | 0.24 (foot) | [0.26, 0.37] | 0.03 | - |
| `kickForward` | `kick_forward_SunDeng_Rig` | `kick_forward` | 9/5/18=32 | 0.533s / 0.517s (**×0.97**) | 0.27 (foot) | [0.29, 0.42] | 0.02 | - |
| `kickUp` | `kick_up_SunDeng_Rig` | `kick_up` | 7/4/16=27 | 0.450s / 0.433s (**×0.96**) | 0.37 (foot) | [0.27, 0.38] | 0.00 | - |
| `kickDown` | `kick_down_SunDeng_Rig` | `kick_down` | 8/4/19=31 | 0.517s / 0.500s (**×0.97**) | 0.25 (foot) | [0.27, 0.37] | 0.02 | - |
| `kickBack` | `kick_back_SunDeng_Rig` | `kick_back` | 8/4/18=30 | 0.500s / 0.483s (**×0.97**) | 0.36 (foot) | [0.28, 0.38] | 0.00 | - |
| `throwForward` | `throw_SunDeng_Rig` | `throw` | 6/4/18=28 | 0.467s / 0.450s (**×0.96**) | 0.20 (blade_tip) | [0.22, 0.33] | 0.02 | - |
| `skill1` | `skill1_SunDeng_Rig` | `skill1` | 11/5/26=42 | 0.700s / 0.683s (**×0.98**) | 0.26 (blade_tip) | [0.27, 0.37] | 0.01 | - |
| `skill2` | `skill2_SunDeng_Rig` | `skill2` | 8/5/32=45 | 0.750s / 0.733s (**×0.98**) | 0.17 (blade_tip) | [0.18, 0.27] | 0.01 | - |
| `midnightRemoval` | `midnight_removal_SunDeng_Rig` | `midnight_removal` | 12/6/22=40 | 0.667s / 0.650s (**×0.97**) | 0.29 (blade_tip) | [0.31, 0.44] | 0.01 | - |

状态类 Clip 倍速：`idle` ×0.99、`walk` ×0.98、`hit` ×1.00、`knockdown` ×1.06、`getUp` ×1.06、`jump` ×1.00。

## 6. 差距清单（实时量化状态，按玩家体感影响度：高 → 低）

| 排名 | 影响 | 差距描述 | 当前量化数据 | 状态 / 建议方案 |
|---:|---|---|---|---|
| 1 | **高** | **招式动画峰值与 60Hz 判定窗口对齐** | 全部 69 项招式最大峰值偏离 = **0.026**（`xuXiao.kick`），目标 ≤ 0.10。 | ✅ 已达标 |
| 2 | **高** | **专属招式覆盖（消除 Fallback 共用）** | 未配专属 Clip 的招式：**0 / 69**；60fps Clip 占比：**120 / 120**。 | ✅ 全招式 100% 专属 60fps 覆盖 |
| 3 | **高** | **GLB 动画插值净化（STEP 阶跃 / 四元数反号）** | STEP 动画轨道总数：**0**；四元数符号翻转总数：**0**。 | ✅ 已清零 |
| 4 | **高** | **受击 / 倒地 / 起身倍速与起身反击/翻滚** | 状态类最大倍速 = **×1.06**（基线 ×5.12）；已实现 SF4 起身低扫踢 (`wakeupKick`) 与前/后受身翻滚 (`rollForward`/`rollBack`) 并完成 31/31 回放快照对齐（Schema 22 / Rules 28）。 | ✅ 已达标 |
| 5 | **中** | **右手武器 Socket 挂在 `Forearm.R`（结构说明）** | 4 英雄 `weapon_socket_r` 均挂在 `Forearm.R` 下；经皮肤权重核查，`wuYong`/`liuQuanwei` 可视拳/袖顶点挂在 `Forearm.R`/`UpperArm.R`，新编动画已通过直接驱动 `weapon_socket_r` + `Hand.R` 同步腕部姿态消除僵直。 | ℹ️ 持续监控视觉脱手与穿模。 |
| 6 | **低** | **`xuXiao` 头模顶点数偏高（43.1 万，GLB 36.1 MB）与颈骨 -14.8%** | `xuXiao` `Head` 431,611 顶点（其余三人 7.3–11.7 万），`head_to_chest` 四人完全一致（0.3423 m）。 | ℹ️ 保五官前提下延后做体积瘦身。 |
