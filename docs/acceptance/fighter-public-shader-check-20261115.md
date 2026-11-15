# 公有生产 shader 的独立编译与小图检查

`check_fighter_public_shaders.py` 为当前明确的运行时编译风险提供独立检查。它不启动 App 或模拟器，不读取资源包，不签名、不下载工具链，也不触发工作流。

## 精确输入与覆盖

检查器只读取以下两个生产 Swift 文件和自己的 CLI 源码，并记录字节数、SHA-256 及抽取片段身份。

| 生产文件 | 实际检查 |
| --- | --- |
| `App/Services/DuelTriadSourceMorph.swift` | 完整 `triad_morph_source_origin` MSL；UV／无 UV 两分支的 surface、fragment 字符串 |
| `App/Services/DuelSourceProjectedShadowRenderer.swift` | 完整 projected-shadow MSL 的六个入口 |

提取器原样复制 Swift literal 和三个纯 String 函数，由 Swift 自身处理多行字符串缩进和插值。它不重新实现 shader 方程。生产 App 文件没有为此改动。提取位置丢失、重复、超出既定结构或引入未经绑定的字符串插值时，检查会失败。

在具备现成 Xcode 的 Mac 上，先通过 `xcrun --sdk iphoneos metal` 分别编译、链接两个完整程序。随后在 macOS Metal 设备上重新编译这些字符串，检查 projected-shadow 的六个函数名，并执行一次 source-origin compute：读取合成的 1×1、RGBA8、`[128, 0, 0, 255]` 输入，要求结果接近 `128 / 255`。

SceneKit modifier 需要 SceneKit 生成完整程序，不能当作完整 MSL 独立编译。CLI 使用同一生产字符串创建一个有 UV 的三角形、一个无 UV 的三角形；每个分支先在同一几何、相机、renderer 和 `capture` 路径绘制一次没有 modifier 的红色基线，再安装原生产 modifier，分别绘制底色、绿色边缘、完全 discard 三种状态，保留这八张 32×32 离屏图。当前版本另外在有 UV 分支的同一场景与读回路径增加两张必需的深度遮挡图，总计十张；具体门槛见文末。检查包含有界 `prepare`、Metal command 完成状态／错误、像素分类与像素 SHA。无 UV 分支不添加 UV，也不声明或绑定 mask sampler，而使用 compute 的真实采样值。

基线的 `unmodifiedBaseline` 单独保存 `prepared`、`shaderModifierCount`、像素计数、中心 BGRA、像素 SHA 和 `passed`。红色基线要求 modifier 数为零且红色／非黑像素均大于 20；原三种 Morph 状态的颜色、discard 和不同像素 SHA 阈值保持原样。基线已经读回但像素失败时，仍收集该分支的三张 Morph 结果。两者必须各自通过；基线通过不能替代 Morph 通过，缺少基线也不能被 Python 外层接受为成功。

这是针对运行 `43728991997` / job `132857048310` 的下一项诊断：此前 authored-uv 的三张图全黑，虽然 prepare 和 command completion 均成功。现有证据不能确定黑屏在几何／SceneKit 目标通路还是 modifier。新增基线不更改生产 shader、采样值、渲染目标、相机、时间或判定阈值，也不声称已修复实际黑屏。它在安装 modifier 前先 prepare／capture，因此本检查不宣称首次冷绘制已通过。

这些检查不加载私有 Dog、stomp、sword 或 skill 的生成 MSL，因此不能证明这些程序已经编译。它也不验证原纹理压缩格式、完整角色材质叠加、原始媒体、阴影最终视觉效果或 iPhone GPU 输出。

## 运行方式与结果

输出必须是 checkout 外尚不存在的目录。默认使用已安装的 `/Applications/Xcode_26.6.app/Contents/Developer`；也可显式提供另一个已经安装的 `DEVELOPER_DIR`。

```sh
DEVELOPER_DIR=/Applications/Xcode_26.6.app/Contents/Developer \
  python3 scripts/check_fighter_public_shaders.py \
  --output /tmp/fighter-public-shader-check
```

入口总预算为 240 秒；单条外部命令也有预算。每次 GPU 完成最多等待 10 秒，SceneKit prepare 的取消回调在 5 秒截止后返回 true，最终仍受外层进程预算约束。所有输入、编译日志、生成源码和 JSON 收据留在输出目录，失败时不删除。

| 状态 | 退出码 | 含义 |
| --- | ---: | --- |
| `passed` | 0 | 两个 iPhoneOS MSL 编译／链接、Mac runtime library、compute、两张无 modifier 基线、两组 Morph 绘制和两张固定顺序深度遮挡图全部完成并通过 |
| `prepared` | 0 | 仅 `--prepare-only` 抽取成功；没有 shader 编译或 GPU 通过声明 |
| `unavailable` | 3 | 非 macOS、所选 Xcode／Swift／Metal／SDK 缺失，或无 Metal 设备；不能计作通过 |
| `failed` | 1 | 编译、身份、绘制、像素或预算检查失败 |

离线 Metal 工具缺失时，入口仍尝试当前机器可执行的 macOS Swift／Metal
检查，并分别记录 `offlineMetalAvailable` 与 `runtime`。即使 runtime 通过，
缺少离线编译的整项结果仍为 `unavailable`。它不会下载组件，也不会把未运行
阶段计作通过。失败命令只输出末尾最多 60 行公有源码诊断；CI 的步骤摘要
保留完整结果元数据，便于定位首次 Apple 检查中真正发生的问题。

最终判定须读取 `public-shader-result.json` 的 `status`，不能只看退出码。`--prepare-only` 明确保留 `prepared`。检查器不运行 `xcodebuild -downloadComponent` 或其他安装操作。

## 本地已完成的检查

2026-11-15 在 Linux 完成以下新检查，没有执行 Apple 原生编译或 GPU 绘制。

1. `python3 scripts/test_fighter_public_shader_extraction.py`：三个专项通过，覆盖抽取结构漂移拒绝、prepared 不晋升为 pass，以及缺少平台时零 native 命令、明确 unavailable。
2. `--prepare-only`：实际抽取两个生产文件，结果为 `prepared`。
3. Swift 6.0.3 以 Foundation 单独编译并求值实际抽取后的两个完整程序、四个 modifier；独立读回比对完整 literal 内容与 UV／无 UV 分支。此步骤没有导入 Metal 或 SceneKit。
4. macOS CLI 源码的 Swift syntax parse 通过；Linux 无法对 Apple 框架做 typecheck。

实际求值的两段完整程序 SHA-256 为 `11d9161062298ec5b37a973edb3dc7f837f3c66c5b32b3db10657787c0ae92b5`（300 B）及 `505f3b1c51b99c4c59971eeb7c8db4024d2cfca37c2fdf9ced2e2c91e143d971`（3,459 B）。待主线 review 后，由主线选择现成 Mac 环境执行一次真实检查。本批没有改 workflow，也没有新的远程 run。

本次红色基线增量仅运行三个受影响的 mock 检查，`3 tests / 0.006s / OK`：基线成功而 Morph 失败仍保留失败、黑色基线与部分读回的有界诊断、两分支中任一基线缺失／失败或原 Morph 失败均拒绝整体通过。Swift 6.0.3 syntax parse 通过；另逐字核对原 `capture` 函数、生产 modifier 绑定块、原三相像素断言，以及两个生产 App 文件均未变化。没有执行新的 Apple 编译、GPU 绘制或工作流。

依据：[Apple 的离线 MSL 编译说明](https://developer.apple.com/documentation/metal/building-a-shader-library-by-precompiling-source-files)、[SceneKit shaderModifiers](https://developer.apple.com/documentation/scenekit/scnshadable/shadermodifiers)、[SceneKit prepare](https://developer.apple.com/documentation/scenekit/scnscenerenderer/prepare(_:shouldabortblock:))。prepare 完成与实际 command／像素检查是独立条件。

红色基线沿用 `.constant` 和红色 diffuse。Apple 的 [constant lighting model](https://developer.apple.com/documentation/scenekit/scnmaterial/lightingmodel-swift.struct/constant) 给出的公式为 `ambient * al + diffuse`，因此不通过额外加灯改变夹具。两者都使用原 [render(atTime:viewport:commandBuffer:passDescriptor:)](https://developer.apple.com/documentation/scenekit/scnrenderer/render(attime:viewport:commandbuffer:passdescriptor:)) 和同一 command 内的 blit 读回；下节记录基线的真实 Mac 运行结果及下一项诊断。

## 零 modifier 仍全黑后的夹具诊断

[运行 43730869760](https://github.com/wuyong9494-lab/kriswu/actions/runs/43730869760) 的 job `132862771610` 已实际完成。两个完整 MSL 的 iPhoneOS 编译／链接、两个 Mac runtime library 和 `128 / 255` compute 均成功；authored-uv 的零 modifier 基线与原 base／edge／discard 却都只返回黑色 clear color。四张图的中心 BGRA 都为 `[0, 0, 0, 255]`，像素 SHA 都为 `df894663e850afa3619ed3d3825d9d1c6520f15fcd76aac25c4407c405fa8cfe`。基线 `prepared=true`、`shaderModifierCount=0`、`commandCompleted=true`，红色及非黑像素数均为 0。这个结果不能把原因定位到生产 Morph modifier，也不能视为 discard 成功。

下一项增量保留原始失败结果与所有成功门槛，增加两份独立诊断：

- `fixtureDiagnostics`：在原基线读回后记录 SceneKit 实际几何源的 data SHA、类型、宽度、stride、offset 及最多三个解码向量；记录一个三角形 element 的原索引、几何包围盒、节点／相机的 model 与 presentation 变换、camera category、实际 diffuse、剔除与深度设置、renderer 的 color/depth/stencil pixel format，以及视锥测试。`projectedInputVertices` 投影的是原先明确传入的三个局部顶点，须与 `sources[].vectors` 的实际内部数据一起核对。非有限数记录为 null，格式不支持或越界分别保留状态，不猜读内存。
- `depthDisabledBaseline`：仅在原零 modifier 基线失败、且该分支原三相均已读回后，临时移除 modifier 并关闭材质的深度读取／写入，使用相同几何、剔除、相机、`atTime: 0`、渲染目标与原 `capture` 路径再画一次红三角形。它单独记录 `diagnosticOnly=true`、`redObserved`、prepare／command／像素结果或有界错误，并恢复原材质字段。它不替代任何原基线或 Morph gate；即使对照有红色，原失败仍是失败。

Apple 明确说明 [`init(vertices:)`](https://developer.apple.com/documentation/scenekit/scngeometrysource/init(vertices:)) 会把输入转换为内部优化格式；[`usesFloatComponents`](https://developer.apple.com/documentation/scenekit/scngeometrysource/usesfloatcomponents) 的实际宽度可以是 4-byte float 或 8-byte double。因此当前没有依据直接把 macOS `CGFloat` 宽度当作错误。新的解码按照返回的实际 metadata 读取。Apple 的 [`isNode(_:insideFrustumOf:)`](https://developer.apple.com/documentation/scenekit/scnscenerenderer/isnode(_:insidefrustumof:)) 只测试包围盒是否与视锥相交，不证明像素可见；[`projectPoint`](https://developer.apple.com/documentation/scenekit/scnscenerenderer/projectpoint(_:)) 的深度 0 与 1 分别代表近／远裁剪面。关闭 [`readsFromDepthBuffer`](https://developer.apple.com/documentation/scenekit/scnmaterial/readsfromdepthbuffer) 提供的是深度比较对照，不能凭它确认更上游的具体故障。

本增量不改生产 shader、MSL 程序数量、阈值或外层时间预算，也没有根据未观测结果更改几何和相机。新增采样仍受已有 prepare 5 秒、command 10 秒及 native 子进程 60 秒上限约束。只有距进程启动后第 55 秒仍至少剩 15 秒才尝试额外深度对照，否则保存 `skippedReason`；这为原读回结果写盘留出余量。尚未执行新的 Mac／GPU 运行。

本次仅运行两个新 mock：实际几何／深度失败证据保留，以及有红色的额外对照不能替代原基线或 Morph 通过。两项通过；预算 guard 之前的 CLI 已通过 Swift 6.0.3 syntax parse，随后工作区恢复按原 SHA 精确重建。恢复环境没有原 Swift binary，未重新安装；新增 guard 的 Apple 编译尚待实际执行。原 `capture`、生产 modifier 绑定、原像素断言、Python acceptance 函数和两个 App 生产文件已独立逐字／AST 核对无变化。Linux 检查不等于 Apple 框架 typecheck 或 GPU 通过。

## 深度对照已有红色后的修正与双遮挡门槛

[运行 43733277139](https://github.com/wuyong9494-lab/kriswu/actions/runs/43733277139) / job `132870243460` 的真实日志把范围缩小到了深度路径。实际内部顶点和索引正确，`insideFrustum=true`，三个投影点为 `[4, 4, 0.64646…]`、`[28, 4, 0.64646…]`、`[16, 28, 0.64646…]`。零 modifier 基线及原 base／edge／discard 仍全黑；同一 `capture` 路径关闭材质深度读写后，出现 **288 个红色／非黑像素**，中心 BGRA `[0, 0, 255, 255]`，像素 SHA `122503965c9567e5f68f1dfb49286c3f10832d4a51d33ce31b276b8663d452de`。command 完成且没有错误。运行仍失败，未把这张对照图计作通过。

当时实际记录为 `usesReverseZ=false`、depth32Float、`clearDepth=1`，材质深度读写均开启；`colorPixelFormat=0` 也保留为观测值。这证明深度开关改变了可见结果，尚不能说明 SceneKit 内部具体失败位置，也不能单凭此结果断言 conventional-Z 的 `false / 1` 组合本身在数学上错误。没有把生产 Morph shader 或 color format 标记为已证根因。

本次仅将公有检查器改成显式 `usesReverseZ=true` 与 `clearDepth=0`，仍开启深度读写，沿用 depth32Float、clear load action、相机、几何、时间、读回和全部原像素阈值。Apple 的 [`clearDepth`](https://developer.apple.com/documentation/metal/mtlrenderpassdepthattachmentdescriptor/cleardepth) 说明 clear load action 在 pass 开始填入所指定的值；其 [WWDC24 reverse-Z 示例](https://developer.apple.com/videos/play/wwdc2024/10092/) 使用零深度清除。后者属于 Compositor Services 示例，只支持所选 reverse-Z 清除约定，不能当作本次 SceneKit 故障原因的证明。生产 App 的 renderer 配置及 shader 字节均没有改动。

新增 `depthOcclusion` 是必需 gate，取代此前可选的 depth-disabled 诊断运行。它暂时移除 modifier，在相同场景中加入一个同几何的绿色三角形；两个材质都要求 depth read/write 为 true。两个 node 的 `renderingOrder` 固定为红色 0、绿色 1；Apple 明确说明较大的 [`renderingOrder`](https://developer.apple.com/documentation/scenekit/scnnode/renderingorder) 后绘制。两帧仅交换 Z 位置，不依赖 opaque 对象未指定的排序。

| 读回 | 红色 Z／order | 绿色 Z／order | 必需结果 |
| --- | --- | --- | --- |
| red-near | 0／0 | −0.5／1 | 红色像素 >20，绿色像素为 0 |
| green-near | −0.5／0 | 0／1 | 绿色像素 >20，红色像素为 0 |

相机仍位于 Z=3。第一帧要求先画的近红色挡住后画的远绿色，第二帧要求后画的近绿色覆盖远红色。只显示最后绘制对象会两帧均绿，只保留最先绘制对象会两帧均红，两种情况都不能通过。每张图保存实际 presentation 位置、绘制顺序、reverse-Z／clear 配置、command 状态、像素计数及 SHA；位置或顺序不符、图像相同、部分读回或任一结果失败均拒绝。Swift gate 和 Python 外层分别要求两张结果完整有效；旧 depth-disabled 成功记录不能替代它。

原 authored-uv 基线与三相结果先完成并保留，再尝试两张遮挡图。新增 prepare 仍限 5 秒，每条 command 仍限 10 秒；只有距 native 进程第 55 秒至少剩 25 秒才启动这个必需检查，否则记录跳过原因并失败。外层 native 60 秒／入口 240 秒预算不增加。临时 node、位置、绘制顺序和 modifier 在结束或异常时恢复。没有新增私有资源、签名、App 启动或工作流触发。

本批仅运行两个新 mock 和两个受影响的原 gate 检查，`4 tests / 0.001s / OK`，验证固定顺序两帧门槛、部分证据保留，以及原基线／Morph gate 仍必需。mock 只验证结果解释，不证明 SceneKit 实际遵守顺序或 GPU 已绘制。当前恢复环境没有 Swift binary，未安装工具链；这次新增 Swift 的 Apple 编译、reverse-Z 结果和实际双遮挡均待下一次公有 Mac 检查。


## 原生品红结果与有界编译诊断

实际运行 `43735247285`（source `243148fb925aacf38a68b2d0300e4f177e8cef3d`）已验证 reverse-Z fixture：无 modifier 基线 288 红像素；固定 red→green 绘制顺序、仅交换两个 z 的两帧遮挡分别为 288 红 / 288 绿，depth read/write 均开启。原 Morph 三相仍相同品红，因此整体失败。

随后 `43736380658`（source `ccf502978533aa192ebb8b1ce0aed8f368c80e40`）实际编译并执行完整 Metal modifier 参数写法，baseline 与双遮挡继续通过，Morph 仍全部品红。不能据此声称参数声明或局部名已经修复渲染，或将任何一个候选当作已证明的唯一原因。程序与 fixture 的通过条件保持原样。

两个运行的 stdout/stderr 只有入口自己的失败行，没有生成 shader 的编译器信息。下一次仅增加本次 synthetic process 的 `OSLogStore(scope: .currentProcessIdentifier)` 只读诊断，按进程身份与本次起始时间二次过滤，仅保留 shader / SceneKit / Metal / pipeline 条目。最多检查 2,000 条、保留 24 条、消息总量不超过 65,536 bytes；预算不足或日志不可用会明确记录，不影响失败结论。先落盘原始 runtime-result，再查询日志；不读取系统范围、其他进程或私有输入，也不更改生产 shader、KVC、渲染器或原像素门槛。

## 进程内日志确认的参数解析错误与最小修复

[运行 43736970650](https://github.com/wuyong9494-lab/kriswu/actions/runs/43736970650)（source `a8aa92ff5ae93cc907d383a36beed7f5403a1a9f`，job `132881605332`）实际编译并执行日志增量。baseline 与双深度遮挡均通过，Morph 三相仍为同一品红。日志检查了本进程 43 条记录、保留 24 条、消息共 3,816 bytes。生成 shader 明确出现不合法的 `constant return& mix`，并将 `triadMorphToLinear` 变成参数；同时报告 `texture2d<float>` 为未知类型。现有证据支持 SceneKit 将 `#pragma arguments` 后的函数定义继续作为参数解析，不能把品红当成可接受的实际视觉结果。

本次将颜色转换函数与 `uniform sampler2D` 放在参数段之前，参数段只保留单行 scalar/vector 声明，采样改为 SceneKit 的 `texture2D` 兼容接口。两个颜色函数、所有原比较边界、KVC 名称、阶段局部名称及 `SCNMaterialProperty` 的 repeat / linear / no-mip / anisotropy=1 均保留。无 UV 负断言同时排除 GLSL 与 Metal 纹理依赖。实际 actor 的原武器材质路径不经过 ArenaAvatar concealment；目前没有证据需要扩展修改通用 modifier 合并器。

两个受影响的提取／prepare 边界检查通过（2 tests / 0.005s），并静态比对了声明布局与颜色函数。该结果只证明可提取性；修复后的 Swift／Metal 编译、两种 UV 分支及原三相像素条件仍须下一次实际公有 GPU gate 验证。深度、颜色及 discard 的通过条件未降低。

API 依据：[OSLogStore](https://developer.apple.com/documentation/oslog/oslogstore)、[OSLogEntryFromProcess](https://developer.apple.com/documentation/oslog/oslogentryfromprocess)。日志只是诊断证据，不能代替 GPU 像素验收。
