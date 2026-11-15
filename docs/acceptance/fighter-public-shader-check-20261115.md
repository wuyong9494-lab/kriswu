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

SceneKit modifier 需要 SceneKit 生成完整程序，不能当作完整 MSL 独立编译。CLI 使用同一生产字符串创建一个有 UV 的三角形、一个无 UV 的三角形；两者分别绘制底色、绿色边缘、完全 discard 三种状态，共六张 32×32 离屏图。检查包含有界 `prepare`、Metal command 完成状态／错误、像素分类与像素 SHA。无 UV 分支不添加 UV，也不声明或绑定 mask sampler，而使用 compute 的真实采样值。

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
| `passed` | 0 | 两个 iPhoneOS MSL 编译／链接、Mac runtime library、compute 及两组 Morph 绘制全部完成 |
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

依据：[Apple 的离线 MSL 编译说明](https://developer.apple.com/documentation/metal/building-a-shader-library-by-precompiling-source-files)、[SceneKit shaderModifiers](https://developer.apple.com/documentation/scenekit/scnshadable/shadermodifiers)、[SceneKit prepare](https://developer.apple.com/documentation/scenekit/scnscenerenderer/prepare(_:shouldabortblock:))。prepare 完成与实际 command／像素检查是独立条件。
