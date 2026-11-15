# D15 原始大脚实体特效接入（2026-11-15）

本批接入 `D15_fx_big_leg` 的三个原始网格发射器。它是独立模型
`D15_Avatara_Leg_Model` 的真实可见实体来源，不是人体骨骼或碰撞胶囊的替代模型。
本批没有修改技能伤害、碰撞、回放协议或发布开关。

## 原件与绑定

| 项目 | 核对结果 |
| --- | --- |
| 原 D15 FX bundle | `4f9476ea1326d7c102950a772ee44020.bin`，2,561,715 B，SHA-256 `971b3a1ea36eaaebaea4ae73a56ed65d8ffc4383625a06d64a209d8a70fbbd90` |
| 原 prefab | `assets/gamedata/resources/effects/prefabs/environmental/sets/d15/d15_fx_big_leg.prefab`，GameObject `-8069839089656887436` |
| 发射器 | `-929469514926225548`、`6055453625588746100`、`-1006497375095126156`，全部保留 |
| 原网格 | `-6222684053069387964`，685 个顶点；原三角形、法线、UV 与坐标反射保留 |
| 原材质 | `mtl_freshnel_premltpl`、`mtl_energy_scroll_09_adtv`、`mtl_aBlnd`；各自唯一精确 keyword variant |
| 共享材质原件 | 从已有归档精确成员 `bundles/743fc535f600cb6addb0c2d20c96a9ab.bin` 读取，986,541 B，整包 SHA-256 `863f1953d88d33beb0ec85229da17188376bb36e47d791146fc87a0f565706ec`；没有下载或扫描其他归档内容 |
| 原 shader bundle | 已缓存 `b77cd85962dab26b5e542811e8599be3.bin`，SHA-256 `c0b1fe09ba0684e474297ade8dcd7fee7b5d2e780236029c544c1986dea1e972` |
| 触发 | source lock 1434 / trigger 1，record 100 AnimationStart；Me `magic_joint_root`，Shift 与 Follow XYZ 均为零 |
| 角色模型 | `erlangSummon_stomp`，原 10 帧、19 个实时采样、AnimationEnd tick 18；物理与表现校验同一条源轨迹 |

原 Fresnel GLSL 的 `_Invert` 是 `int`。离线适配保留其整数标量读取，
没有把它作为 `float4` 传给原判断。三个程序的原始运算表达式、采样、颜色与
混合状态均保留，只转换 GPU API、向量类型和坐标接口。第一次材质转换因这个
新增类型缺口而中止；补齐显式转换后继续，原件没有改写。这不是战斗回归的红测。

## 实际接线

`DuelErlangStompEffectAssets` 验证独立文件摘要、角色身份、完整原模型轨迹、
五骨采样、三发射器及唯一源事件。`DuelTriadEffectAssets` 新增的 D15 大脚入口
仅接受这一种 effect；H17 原有模型身份和默认路径保持原约束。

`DuelWorld.consumeFeedback` 在每个固定战斗步调用新 renderer 的 `sampleStep`。
它只能记录 Core 中真实存在的 `erlangModels`，不创建碰撞、命中或技能输入。
每个 owner / model ID 只登记一次，出生位置来自原 `magic_joint_root`，FX 自身
按原 `takeInAccountCharacterDirection` 翻转一次。`Follow=[0,0,0]` 不跟随后续
角色位移，`reactToDissolveModel=0` 也没有被替换成碰撞模型的 18-tick 寿命。

原三个粒子的寿命都是 1.4 秒（84 个实时 tick），下落段在约 0.183 秒落定，
然后按原颜色曲线淡出。固定步记录保留这一寿命；显示跳帧不会漏掉已经观察到的
出生，重复绘制和暂停不会推进时钟。回合结束清理所有实例；未观察到的过期模型
不会由 renderer 倒推成一次新出生。原生引擎对完整 FX 对象销毁链的逐事件等价
尚未实测，本批不据此声称 Unity 逐像素或逐事件等价。

## 最终 62 动作身份绑定

本批只做一次最终 metadata rebind，角色原网格、特效采样与原资源没有重新转换。

| 文件 | Bytes | SHA-256 |
| --- | ---: | --- |
| 最终 `SF3_Erlang_Profile.json` | 18,898,503 | `e9001357a0bda99f2fcc8f833b5e5dbc1c48846551def88aa2057d4d1ee1ad23` |
| 最终 `WuYong_Erlang_D15.glb` | 18,590,120 | `debd14c7af756e52e14b920ce2db37fd77ddcfa26b5668fe552ac79e7a1303bd` |
| `SF3_D15_StompEffects.json.gz` | 198,464 | `42dc90b46ef7b9abb219f71ab2367cd8e68fcfbf5bf3aa37cc37d39d4d184d11` |
| `SF3_D15_Companions.json` | 53,047 | `ad71feddda95752b819993588c09bf20fa29320384aa2516046a9ac33cfc5fa7` |
| `SF3_D15_Effects.json.gz`（犬） | 99,987 | `26e4facfa38cc44613015e919f387ad750380f7791af55b7cfa0bb3b16e2ce67` |

大脚包包含 3 条粒子轨迹、3 个真实材质和 9 个摘要绑定的 GPU 程序/纹理文件。
私有派生资源和原件不进入公开 Git。组包器须同时纳入文件清单，并由集中身份文件
给 loader 提供上述摘要；单独存在转换产物不代表生产包已启用。

## 本批实际检查

新增定向检查只覆盖本批风险，没有重跑先前犬、原生截图或完整 Swift suite。

- `scripts/test_erlang_stomp_effect.py`：4 项实际原件检查通过，5.066 秒。验证原网格
  顶点与三角形、全部发射器与完整寿命、三个原 shader 的每条运算表达式、整数
  uniform、错误 keyword/篡改资源拒绝，以及最终 metadata rebind 仅改变角色身份。
- 随后只执行新增的完整材质准备方法检查，1 项通过，2.619 秒；从精确本地 ZIP
  成员和缓存 shader 重新走新增准备入口，三个最终程序与已核产物逐字一致。没有
  重跑上述 4 项。
- `scripts/check_erlang_stomp_effect_clock.swift`：Swift 6.0.3 编译并运行通过 6 项：
  一次出生、18/84 tick 不同寿命、冻结时钟、双 owner 与回合重置、无效出生拒绝、
  无显示帧的固定步补进。
- 修改的 4 个 App Swift 文件通过 Swift 6.0.3 `-frontend -parse`。
  这只证明语法成立，未声称 Apple SDK 类型检查、Metal GPU 编译或真机画面通过。
- 独立静态复核确认 fixed-step 接线、18/84 tick 分离、一次出生根变换、D15 窄
  scope 与 `_Invert` 整数接口没有发现阻塞；复核者没有再次执行检查。

检查入口参数分别为本批 candidate、精确材质源目录、已缓存 D15/shader bundle、
最终 profile；所有检查和转换均只访问本地原件。新 metadata binder 另核复制前后
资源 bytes / SHA-256，并拒绝不含完全相同原 stomp 轨迹的 profile。

## 尚未归入本批的可视部分

地面裂纹、眼部光束、其余模型特效和六把悬浮剑的可见实体不在这个单-effect
manifest 内。高档剑和部分终结技原 prefab 包含 Noise、Trail、子发射器或外部
力场，后续必须实现原模块；不能删除这些发射器、切换低档素材或用占位模型声称完成。
