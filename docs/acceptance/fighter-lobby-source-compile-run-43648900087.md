# 大厅角色身份绑定：Apple 源码编译回执 43648900087

**本次提交已通过一次真实、未签名的 Apple 应用编译。** 日志中的最终状态为 `compiled`，实际 `unsigned-source-build` 返回码为 `0`，用时 **364.924 秒**。本记录的验收范围是源码编译；测试方法执行、模拟器启动、真机验证与私有角色资源装载均为 **0**。

## 运行身份

| 字段 | 已核实际值 |
|---|---|
| 源提交 | [`5afd8195e2f611ab2e7c37f5096a4251a4616ee9`](https://github.com/wuyong9494-lab/kriswu/commit/5afd8195e2f611ab2e7c37f5096a4251a4616ee9) |
| 源树 | `f0bd64525ae7df38e0db8b2e14368593f4189f90` |
| 分支 | `codex/fighter-visual-acceptance-20261113-1200` |
| Actions | [43648900087](https://github.com/wuyong9494-lab/kriswu/actions/runs/43648900087) |
| Job / Attempt | [132612723233](https://github.com/wuyong9494-lab/kriswu/actions/runs/43648900087/job/132612723233) / `1` |
| 精确触发消息 | `Verify lobby identity source compile 20261115` |
| GitHub 结果 | `completed / success`；已进一步核对实际编译回执 |
| 运行开始 / 最终状态更新时间（北京时间） | `2026-11-15 06:35:31` / `2026-11-15 06:42:03`（Asia/Shanghai，UTC+08:00） |
| Runner | `macos-26-arm64`，image `20261102.0473.1`，macOS `26.7.2` |
| 编译工具 | Xcode `26.6`，build `17F113`；XcodeGen `2.46.0` |

## 本次修改与证据层级

[`DuelHomeView.swift`](https://github.com/wuyong9494-lab/kriswu/blob/5afd8195e2f611ab2e7c37f5096a4251a4616ee9/App/Views/DuelHomeView.swift) 的大厅身份与武器教学文字，改为读取现有预览已验证 catalog 的轻量身份快照。资料未就绪时显示中性提示，角色身份不按姓名猜测。刘泉纬的实际 `liu_hammers` 资料继续显示双锤，未被标为盘古完成。

[`DuelLobbyPreview.swift`](https://github.com/wuyong9494-lab/kriswu/blob/5afd8195e2f611ab2e7c37f5096a4251a4616ee9/App/Views/DuelLobbyPreview.swift) 只投影已加载 catalog 中的标题、武器标题与招式能力。快照不持有模型或完整动作轨；回调经主队列异步发布、去重，并在视图拆除时失效。独立只读审查核对了回调更新、旧实例失效、资源复用和未额外解析完整 catalog 的边界。

上述行为具有代码分析和本次 Apple 编译证据。大厅实际显示、角色资源加载、音画同步与 iPhone 17 Pro Max 操作效果仍需要各自的运行证据。本次没有读取原始 H17/D19 私有媒体，也没有重新验证材质专项测试；此前材质运行的提交与结果应保持独立记录。

## 实际构建阶段

| 阶段 | 次数 | 返回码 | 用时 |
|---|---:|---:|---:|
| 缺少 XcodeGen 时，通过现有 Homebrew 安装该构建依赖 | 1 | 0 | 7.246 秒 |
| 读取 XcodeGen 版本 | 1 | 0 | 0.021 秒 |
| `xcodegen generate` | 1 | 0 | 0.182 秒 |
| `xcodebuild build`，Debug，generic iOS Simulator 编译目标 | 1 | 0 | 364.924 秒 |

Helper 总耗时为 **373.801 秒**。使用现成 Xcode 26.6；未安装 Xcode、SDK 或媒体。构建采用 `CODE_SIGNING_ALLOWED=NO`、`CODE_SIGNING_REQUIRED=NO`、空签名身份、空 `FIGHTER_ASSET_RELEASE_SHA256` 与 `SWIFT_EMIT_LOC_STRINGS=NO`。未调用 `build-for-testing`、`test`、`test-without-building` 或 `simctl`。

完整应用与 Widget 依赖按原 `project.yml` 构建。正常的 `build_fighter_network_rules.py` 构建阶段保留并实际生成资源；输出摘要为 `f76c404d815a62428a7bb9d55572ffe17cfeecb6cd94702b70797fa7d35419be`，规则 fingerprint 为 `7d53146e6237bcc643dedb7f9b4462bcb57953f44170bf89926a854f3fb25c5a`。

## 源输入绑定

**823 个文件、58,614,601 字节**的清单逐项包含路径、Git 模式、文件大小与 SHA-256，按路径排序后进行固定 JSON 编码。聚合摘要为：

```text
faa18f44ca9d3ab54bd54323b7ca074f21995ff4330d6fe67da4cd38e745dee4
```

范围包含 `App`、`Sources`、`Shared`、`Widget`、`Tests`、`project.yml` 与实际构建脚本 `scripts/build_fighter_network_rules.py`。`Tests` 被纳入是因为 XcodeGen 发现这些工程路径；本次没有执行或产出测试包。无关取材脚本及验收文档不属于本次编译输入。

| 独立校验的文件 | SHA-256 |
|---|---|
| `App/Views/DuelHomeView.swift` | `2fbfb2b8d8ee41e3a7c7d02686c53b4c5d97e6edbdaab3ff9b238bdbe3989ee2` |
| `App/Views/DuelLobbyPreview.swift` | `cdb2d78a87c8a74d3e308cf901739f07944361c235df6b203291635db32f6263` |
| `App/Services/DuelTriadSourceMaterial.swift` | `efb78001996c8e66721cafbcdb99765b3af9d4ca17e827385ca6d3968ef75856` |
| `project.yml` | `21ad8ca03cafb81c7ad72821627227076da7602a855020f7bbf4b16cdb08c0d1` |
| `scripts/build_fighter_network_rules.py` | `50593000b48c128206cffbdde72f71c60daacddae9fe10cc8a76182c49f9ac45` |

工程生成后只允许项目声明的两份 entitlement 文件新增；全部受控源输入在工程生成后、编译后均重新核验。实际 report 的源提交、运行号、attempt、聚合摘要及上述独立摘要均已与本次固定入口核对一致。

- [工作流](https://github.com/wuyong9494-lab/kriswu/blob/5afd8195e2f611ab2e7c37f5096a4251a4616ee9/.github/workflows/fighter-lobby-source-compile.yml)：SHA-256 `73f82fcf8557b14dccfb9cd40bc6291d580692608039e00c362f795f2ce74c79`。
- [Helper](https://github.com/wuyong9494-lab/kriswu/blob/5afd8195e2f611ab2e7c37f5096a4251a4616ee9/.github/scripts/fighter_lobby_source_compile.py)：SHA-256 `1b03895207689692cd744c39f1356b53ee12b749f7726fdce0827401a74d3fab`。

## 验收边界

| 检查 | 本次结果 |
|---|---|
| 未签名应用编译 | 已通过 |
| 测试方法执行 | 0 |
| 测试包 / 测试运行计划产出 | 0 |
| 模拟器启动 / App 运行 | 0 |
| iPhone 17 Pro Max 真机验收 | 未执行 |
| 原始私有资源 staging / release 激活 | 0；`FighterPrivate` 为空 |
| 资源密钥注入 / TestFlight / 资源版本上传 | 0 |
| Artifacts | GitHub 查询实际返回空数组 |
| 重试或重跑成功测试 | 0 |

本次只下载一次公共 Job 日志。该文本副本的 SHA-256 为 `72af1afa1faa4c8be309437b621cfd8e8a3d783171b7cf20dc58c5933cfac218`；它是文本采集摘要，不是 GitHub artifact 摘要。各构建阶段的完整日志只留在临时 runner；report 记录了其大小和摘要，未上传完整日志或应用产物。

机器可读证据见 [对应 JSON](fighter-lobby-source-compile-run-43648900087.json)。
