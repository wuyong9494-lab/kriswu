# iOS 页面与入口台账

基线提交 `b09b95f`。下列记录覆盖主 App 的 SwiftUI 页面、视图包装器、系统弹层与条件路由，以及 Widget 和分享扩展入口。路由来自源码，模拟器点击和真机截图另记。一个页面可有多个入口。复用卡片、舞台或工具栏单列，不能加到独立页面数里。

## 导航边界

- 冷启动进入双卡首页。内部用户的 On Duty 有今天、日历、统计、游戏、网站、设置六个标签。内部 WuMind 直达对话，外部 WuMind 有对话、游戏、我的三个标签；外部用户受角色保护，不能打开值班页和内部深链。
- 系统通知支持 `day:日期` 及工作留痕、录音、笔记、更新、公告、会议、排班记录、团队变化、数传计划。小组件及快捷指令支持拍照、录音、笔记及计划。URL 的 day 和 managed-calendar 打开指定日期。导入表格根据识别结果进入计划或会议，其他文件进入工作留痕；.arenapack 导入游戏资源。入口源见 [RootView](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/ShiftApp.swift)。
- 值班「全部功能」按普通、管理者、管理员权限生成链接。联网、登录、相册、相机、麦克风、蓝牙、StoreKit、局域网或 Game Center 的可用性取决于账号、权限和设备。
- 游戏首页公开入口包括勇者乱斗、星了个星、裂隙对决。徐骁练习仅在 L12_INTERNAL_PREVIEW 条件编译下出现。ScreenCatalog 的 `-screen` 参数只证明开发跳转。
- 路径以入口和构造器的可达链表达。某个父视图引用子视图不能证明入口控件在所有状态都可点；手势、闭包、运行时类型擦除及条件编译需实机或界面测试补证。源码链接固定到基线提交。

## 重点操作路径

| 从哪里进入 | 操作及条件 | 已定位的目的地 | 基线状态 |
|---|---|---|---|
| 首页 › WuMind › 工作台 › 全部工坊 | 从工坊列表选工具 | 实时语音、画室、视频、3D、智能体、PPT、音频、编程、办公、标书 | 已查 ToolboxDestination 分派 |
| 工作台 › 六个常用工坊快捷项 | 点快捷项后准备输入 | 原路径回到聊天预设。工作台内 PPT／3D 作品点击重新编辑，也走该回调 | 已定位路由差异，等待改后验证 |
| 聊天 › 上传文件 › 发送剪辑指令 | 已附本地 MP4／MOV／M4V | 在聊天交付剪辑作品，点击预览或分享 | 需要视频素材；非独立工作台 |
| 聊天 › 作品卡片 | 按作品类型进预览、详情或编辑 | 代码运行和编辑、图片、视频、PPT、3D、文档；原聊天结果与作品库的重新编辑回调不同 | 合法工件存在时显示 |
| 工作台 › 全部工坊 › 视频 | 切短剧模式，建分镜、选镜头与版本 | 短剧预览、重做、导出、分平台发布 | 依赖项目、镜头和导出文件 |
| 工作台 › 全部工坊 › PPT | 生成或恢复项目，选一页 | 页面编辑、单页重做、预览和导出 | 需有项目及幻灯片 |
| WuMind › 我的作品 | 按类型筛选，再选作品与版本 | 图片／视频／PPT／3D／文档／代码详情、同步状态与分享 | 空库、仅本地、上传中、失败、已同步分别需状态样例 |
| 聊天 › 模型及账号设置 | 选择内置或自有通道，按角色配置 | 服务商、Key、高级配置、联网来源、钱包；管理员另有用户、定价、充值、诊断 | 权限和已登录状态分别核验 |
| On Duty › 今天 › 值班工作台 › 发数传计划 | 导入、复核、结果，再进地面站与运营商 | 地面站列表、新建／编辑规则、校验、保存及回到列表 | 列表直达用例与从首页逐步遍历分开计算 |
| On Duty › 今天、日历、统计、网站、设置 | 进入具体日期、成员、班次、权限或功能搜索 | 值班明细、人员页、换班、统计、会议、留痕、设置子页见台账 | 部分入口仅管理者或管理员可用 |
| 游戏 › 勇者乱斗 | 大厅中的不同面板 | 角色与技能、玩法、奖杯、联机、好友、组队、商店、赛季、设置；独立进入诊断、资源或指南 | 对战、结算、组队房需要对应数据与设备 |
| 游戏 › 星了个星 | 选主线、航线、挑战、收藏或联机 | 经典棋盘、星轨、试炼、远征、星图、星际旅程、复盘与每日状态 | 进度解锁及战局内条件需另测 |
| 游戏 › 裂隙对决 | 主页选对局或联网 | 角色选择、房间及战斗；徐骁练习受内部编译开关控制 | 常规包不计内部练习达成 |
| 系统小组件或分享 | 选日期、拍照、录音、笔记、传入文件 | 日期详情、相机、录音、笔记、计划、会议及工作留痕 | 权限拒绝、文件类型、角色限制需另测 |

## 页面及预览

| 页面 | 入口路径 | 改动 | 验证状态 |
|---|---|---|---|
| 工作区外壳 `RootView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/ShiftApp.swift#L159) | 冷启动 | 待分域核对 | 源码推定，未逐页点验 |
| 编程／办公 `AICodeWorkToolsView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/AICodeWorkToolsView.swift#L6) | 首页 › WuMind › AICodeWorkToolsView | 待分域核对 | 源码推定，未逐页点验 |
| WUMIND 画室 `AIImageToolView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/AIImageToolView.swift#L11) | 首页 › WuMind › AIImageToolView | 待分域核对 | 源码推定，未逐页点验 |
| 画室脱敏诊断 `ImageStudioDiagnosticsSheet` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/AIImageToolView.swift#L2972) | 首页 › WuMind › AIImageToolView › ImageStudioDiagnosticsSheet | 待分域核对 | 源码推定，未逐页点验 |
| 实时语音通话 `AILiveCallView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/AILiveCallView.swift#L44) | 首页 › WuMind › AILiveCallView | 待分域核对 | 源码推定，未逐页点验 |
| AI 工具箱 `AIProviderListView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/AIProviderListView.swift#L8) | 首页 › WuMind › AIProviderListView | 待分域核对 | 源码推定，未逐页点验 |
| `ProviderKeyView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/AIProviderListView.swift#L237) | 首页 › WuMind › ProviderKeyView | 待分域核对 | 源码推定，未逐页点验 |
| AIHubMix 连接 `AIHubMixConnectionSheet` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/AIProviderListView.swift#L595) | 待追踪 | 待分域核对 | 未证实普通用户入口 |
| 语音合成与转写 `AISpeechToolView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/AISpeechToolView.swift#L7) | 首页 › WuMind › AISpeechToolView | 待分域核对 | 源码推定，未逐页点验 |
| AI 生视频工坊 `AIVideoToolView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/AIVideoToolView.swift#L10) | 首页 › WuMind › AIVideoToolView | 待分域核对 | 源码推定，未逐页点验 |
| 接口字段查看 `APIFieldsView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/APIFieldsView.swift#L5) | 首页 › On Duty › 设置 › APIFieldsView | 待分域核对 | 源码推定，未逐页点验 |
| 全部功能 `AllFeaturesView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/AllFeaturesView.swift#L4) | 首页 › On Duty › 设置 › AllFeaturesView | 待分域核对 | 源码推定，未逐页点验 |
| `ArenaDiagnosticSuiteView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ArenaDiagnosticSuiteView.swift#L3) | 首页 › On Duty › 游戏；外部 WuMind › 游戏 › ArenaHomeView › ArenaDiagnosticSuiteView | 待分域核对 | 源码推定，未逐页点验 |
| `ArenaImportedHeroView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ArenaImportedHeroView.swift#L8) | 首页 › On Duty › 游戏；外部 WuMind › 游戏 › ArenaHomeView › ArenaImportedHeroView | 待分域核对 | 源码推定，未逐页点验 |
| `ArenaImportedLobbySceneView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ArenaImportedLobbySceneView.swift#L10) | 首页 › On Duty › 游戏；外部 WuMind › 游戏 › ArenaHomeView › ArenaSourceControlVisual › ArenaImportedLobbySceneView | 待分域核对 | 源码推定，未逐页点验 |
| `ArenaHomeView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ArenaLobby.swift#L11) | 首页 › On Duty › 游戏；外部 WuMind › 游戏 › ArenaHomeView | 待分域核对 | 源码推定，未逐页点验 |
| `ArenaGamePanel` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ArenaLobby.swift#L2007) | 首页 › On Duty › 游戏；外部 WuMind › 游戏 › ArenaHomeView › ArenaGamePanel | 待分域核对 | 源码推定，未逐页点验 |
| `ArenaMenuScreen` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ArenaMenuComponents.swift#L10) | 首页 › On Duty › 游戏；外部 WuMind › 游戏 › ArenaHomeView › ArenaMenuScreen | 待分域核对 | 源码推定，未逐页点验 |
| `ArenaAudioSettingsView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ArenaMenuComponents.swift#L126) | 首页 › On Duty › 游戏；外部 WuMind › 游戏 › ArenaHomeView › ArenaAudioSettingsView | 待分域核对 | 源码推定，未逐页点验 |
| `ArenaResourcePackView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ArenaResourcePackView.swift#L8) | 首页 › On Duty › 游戏；外部 WuMind › 游戏 › ArenaHomeView › ArenaResourcePackView | 待分域核对 | 源码推定，未逐页点验 |
| `ArenaResourceMapView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ArenaResourcePackView.swift#L292) | 首页 › On Duty › 游戏；外部 WuMind › 游戏 › ArenaHomeView › ArenaResourcePackView › ArenaResourceMapView | 待分域核对 | 源码推定，未逐页点验 |
| `ArenaSampleReview` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ArenaSampleReview.swift#L4) | 首页 › On Duty › 游戏；外部 WuMind › 游戏 › ArenaHomeView › ArenaSampleReview | 待分域核对 | 源码推定，未逐页点验 |
| `ArenaSampleMapPreview` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ArenaSampleReview.swift#L132) | 首页 › On Duty › 游戏；外部 WuMind › 游戏 › ArenaHomeView › ArenaSampleReview › ArenaSampleMapPreview | 待分域核对 | 源码推定，未逐页点验 |
| `ArenaSeasonSheet` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ArenaSeasonView.swift#L6) | 首页 › On Duty › 游戏；外部 WuMind › 游戏 › ArenaHomeView › ArenaSeasonSheet | 待分域核对 | 源码推定，未逐页点验 |
| `ArenaStoryView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ArenaStoryView.swift#L7) | 首页 › On Duty › 游戏；外部 WuMind › 游戏 › ArenaHomeView › ArenaStoryView | 待分域核对 | 源码推定，未逐页点验 |
| `ArenaPlayView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ArenaView.swift#L50) | 首页 › On Duty › 游戏；外部 WuMind › 游戏 › ArenaHomeView › ArenaPlayView | 待分域核对 | 源码推定，未逐页点验 |
| `ArenaRoomView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ArenaView.swift#L133) | 首页 › On Duty › 游戏；外部 WuMind › 游戏 › ArenaHomeView › ArenaRoomView | 待分域核对 | 源码推定，未逐页点验 |
| `ArenaMatchView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ArenaView.swift#L368) | 首页 › On Duty › 游戏；外部 WuMind › 游戏 › ArenaHomeView › ArenaDiagnosticSuiteView › ArenaMatchView | 待分域核对 | 源码推定，未逐页点验 |
| 备份与恢复 `BackupView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/BackupView.swift#L5) | 首页 › On Duty › 设置 › BackupView | 待分域核对 | 源码推定，未逐页点验 |
| 排班日历 `CalendarView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/CalendarView.swift#L5) | 首页 › On Duty › 日历 | 待分域核对 | 源码推定，未逐页点验 |
| `DayEditor` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/CalendarView.swift#L283) | 内部通知或日链接 › 指定日期 | 待分域核对 | 源码推定，未逐页点验 |
| 按日查看 `DayRosterView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DayRosterView.swift#L4) | 首页 › On Duty › 今天 › DayRosterView | 待分域核对 | 源码推定，未逐页点验 |
| `DeepSeekChatView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DeepSeekChatView.swift#L4) | 待追踪 | 待分域核对 | 未证实普通用户入口 |
| DeepSeek API Key `DeepSeekPlanKeyView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DeepSeekPlanKeyView.swift#L4) | 首页 › WuMind › DeepSeekPlanKeyView | 待分域核对 | 源码推定，未逐页点验 |
| 投标书草稿 `DeepSeekTenderView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DeepSeekTenderView.swift#L286) | 首页 › WuMind › DeepSeekTenderView | 待分域核对 | 源码推定，未逐页点验 |
| 电脑版网页 `DesktopNotesBrowser` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DesktopNotesBrowser.swift#L4) | 首页 › On Duty › 设置 › GroupNotesView › DesktopNotesBrowser | 待分域核对 | 源码推定，未逐页点验 |
| 自检与诊断 `DiagnosticsView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DiagnosticsView.swift#L5) | 首页 › On Duty › 今天 › DiagnosticsView | 待分域核对 | 源码推定，未逐页点验 |
| `DocumentScanner` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DocumentScanner.swift#L5) | 待追踪 | 待分域核对 | 未证实普通用户入口 |
| `DuelHomeView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DuelHomeView.swift#L6) | 首页 › On Duty › 游戏；外部 WuMind › 游戏 › DuelHomeView | 待分域核对 | 源码推定，未逐页点验 |
| `DuelLobbyPreview` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DuelLobbyPreview.swift#L75) | 首页 › On Duty › 游戏；外部 WuMind › 游戏 › DuelHomeView › DuelLobbyPreview | 待分域核对 | 源码推定，未逐页点验 |
| 双人格斗 · 联机测试 `DuelNetworkEntryView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DuelNetworkRoomView.swift#L4) | 首页 › On Duty › 游戏；外部 WuMind › 游戏 › DuelHomeView › DuelNetworkEntryView | 待分域核对 | 源码推定，未逐页点验 |
| `DuelNetworkRoomView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DuelNetworkRoomView.swift#L107) | 首页 › On Duty › 游戏；外部 WuMind › 游戏 › DuelHomeView › DuelNetworkEntryView › DuelNetworkRoomView | 待分域核对 | 源码推定，未逐页点验 |
| `DuelShadowArenaNetworkRoomView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DuelShadowArenaNetworkRoom.swift#L341) | 首页 › On Duty › 游戏；外部 WuMind › 游戏 › DuelHomeView › DuelNetworkEntryView › DuelShadowArenaNetworkRoomView | 待分域核对 | 源码推定，未逐页点验 |
| `DuelTelevisionViewController` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DuelTelevision.swift#L129) | 待追踪 | 待分域核对 | 未证实普通用户入口 |
| `DuelMatchView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DuelView.swift#L1284) | 首页 › On Duty › 游戏；外部 WuMind › 游戏 › DuelHomeView › DuelMatchView | 待分域核对 | 源码推定，未逐页点验 |
| 内部练习 `DuelXuXiaoPracticeView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DuelXuXiaoPracticeView.swift#L7) | 首页 › On Duty › 游戏；外部 WuMind › 游戏 › DuelXuXiaoPracticeView | 待分域核对 | 仅 L12_INTERNAL_PREVIEW，未逐页点验 |
| 排班复核 `DutyBurdenUpcomingView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DutyBurdenUpcomingView.swift#L3) | 首页 › On Duty › 统计 › DutyBurdenView › DutyBurdenUpcomingView | 待分域核对 | 源码推定，未逐页点验 |
| 近 30 天值班负担 `DutyBurdenView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DutyBurdenView.swift#L5) | 首页 › On Duty › 统计 › DutyBurdenView | 待分域核对 | 源码推定，未逐页点验 |
| `DutyBurdenDetailView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DutyBurdenView.swift#L126) | 首页 › On Duty › 统计 › DutyBurdenView › DutyBurdenDetailView | 待分域核对 | 源码推定，未逐页点验 |
| 组别任务清单 `DutyChecklistView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DutyWorkbenchView.swift#L188) | 首页 › On Duty › 今天 › DutyWorkbenchCard › DutyChecklistView | 待分域核对 | 源码推定，未逐页点验 |
| 交班卡 `DutyHandoffView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DutyWorkbenchView.swift#L199) | 首页 › On Duty › 今天 › DutyWorkbenchCard › DutyHandoffView | 待分域核对 | 源码推定，未逐页点验 |
| 外部用户登录 `ExternalAuthView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ExternalAuthView.swift#L7) | 首页 › On Duty › 设置 › ExternalAuthView | 待分域核对 | 源码推定，未逐页点验 |
| 我的 `ExternalAccountProfileView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ExternalAuthView.swift#L426) | 外部 WuMind › 我的 | 待分域核对 | 源码推定，未逐页点验 |
| 均衡分析 `FairnessView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/FairnessView.swift#L4) | 首页 › On Duty › 统计 › FairnessView | 待分域核对 | 源码推定，未逐页点验 |
| `RowView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/FairnessView.swift#L176) | 首页 › On Duty › 统计 › FairnessView › RowView | 待分域核对 | 源码推定，未逐页点验 |
| 小游戏 `GamesHomeView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/GamesHomeView.swift#L14) | 首页 › On Duty › 游戏；外部 WuMind › 游戏 | 待分域核对 | 源码推定，未逐页点验 |
| `GameRoomLobby` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/GamesHomeView.swift#L176) | 首页 › On Duty › 游戏；外部 WuMind › 游戏 › TileGameHomeView › TileRaceLobbyView › GameRoomLobby | 待分域核对 | 源码推定，未逐页点验 |
| 五子棋 `GomokuHomeView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/GomokuView.swift#L30) | 待追踪 | 待分域核对 | 未证实普通用户入口 |
| `GomokuLocalScreen` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/GomokuView.swift#L329) | GomokuHomeView | 待分域核对 | 未证实普通用户入口 |
| `GomokuRoomScreen` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/GomokuView.swift#L540) | GomokuHomeView | 待分域核对 | 未证实普通用户入口 |
| 轮流下 `GomokuTurnScreen` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/GomokuView.swift#L616) | GomokuHomeView | 待分域核对 | 未证实普通用户入口 |
| `GroupNoteView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/GroupNoteView.swift#L5) | 内部通知或日链接 › 指定日期 › GroupNoteView | 待分域核对 | 源码推定，未逐页点验 |
| 导入排班表 `ImportView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ImportView.swift#L5) | 首页 › On Duty › 设置 › ImportView | 待分域核对 | 源码推定，未逐页点验 |
| 数据核对 `DataCheckView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/InsightViews.swift#L7) | 首页 › On Duty › 统计 › DataCheckView | 待分域核对 | 源码推定，未逐页点验 |
| 工作量规则 `WorkloadRulesView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/InsightViews.swift#L84) | 首页 › On Duty › 统计 › WorkloadRulesView | 待分域核对 | 源码推定，未逐页点验 |
| 换班记录 `TeamChangesView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/InsightViews.swift#L195) | 首页 › On Duty › 统计 › TeamChangesView | 待分域核对 | 源码推定，未逐页点验 |
| 年度总结 `YearSummaryView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/InsightViews.swift#L293) | 首页 › On Duty › 统计 › YearStatsView › YearSummaryView | 待分域核对 | 源码推定，未逐页点验 |
| 周会各组趋势 `MeetingTrendView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/MeetingTrendView.swift#L5) | 首页 › On Duty › 设置 › AllFeaturesView › MeetingTrendView | 待分域核对 | 源码推定，未逐页点验 |
| 我负责的周会问题 `MeetingIssuesView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/MeetingViews.swift#L111) | 冷启动 › MeetingIssuesView | 待分域核对 | 源码推定，未逐页点验 |
| 写回金山文档 `MeetingWriteConfirmView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/MeetingViews.swift#L761) | 冷启动 › MeetingIssuesView › MeetingWriteConfirmView | 待分域核对 | 源码推定，未逐页点验 |
| 下载过程 `MeetingSourceView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/MeetingViews.swift#L846) | 冷启动 › MeetingIssuesView › MeetingSourceView | 待分域核对 | 源码推定，未逐页点验 |
| 周会文档 `MeetingDocBrowser` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/MeetingViews.swift#L1063) | 冷启动 › MeetingIssuesView › MeetingSourceView › MeetingDocBrowser | 待分域核对 | 源码推定，未逐页点验 |
| 搜索成员 `MemberSearchView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/MemberSearchView.swift#L4) | 首页 › On Duty › 今天 › MemberSearchView | 待分域核对 | 源码推定，未逐页点验 |
| `MemberScheduleView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/MemberSearchView.swift#L81) | 首页 › On Duty › 今天 › DayRosterView › MemberScheduleView | 待分域核对 | 源码推定，未逐页点验 |
| 本周全员 `WeekRosterView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/MoreViews.swift#L62) | 首页 › On Duty › 今天 › ManagerHomeView › WeekRosterView | 待分域核对 | 源码推定，未逐页点验 |
| 自动同步设置向导 `AutomationGuideView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/MoreViews.swift#L175) | 首页 › On Duty › 设置 › AutomationGuideView | 待分域核对 | 源码推定，未逐页点验 |
| 节假日值班 `HolidayDutyView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/MoreViews.swift#L249) | 首页 › On Duty › 统计 › HolidayDutyView | 待分域核对 | 源码推定，未逐页点验 |
| 请假规划 `LeavePlannerView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/MoreViews.swift#L287) | 首页 › On Duty › 今天 › QuickActions › LeavePlannerView | 待分域核对 | 源码推定，未逐页点验 |
| 历年统计 `MultiYearStatsView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/MultiYearStatsView.swift#L5) | 首页 › On Duty › 统计 › YearStatsView › MultiYearStatsView | 待分域核对 | 源码推定，未逐页点验 |
| `OnboardingView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/OnboardingView.swift#L4) | 首次进入 On Duty | 待分域核对 | 源码推定，未逐页点验 |
| `PassPlanBurstCameraView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/PassPlanBurstCameraView.swift#L10) | 待追踪 | 待分域核对 | 未证实普通用户入口 |
| 地面站与运营商 `PassPlanOperatorsView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/PassPlanOperatorsView.swift#L6) | 分享表格或内部通知 › passPlan › PassPlanOperatorsView | 待分域核对 | 源码推定，未逐页点验 |
| `GroundStationRuleEditorView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/PassPlanOperatorsView.swift#L251) | 分享表格或内部通知 › passPlan › PassPlanOperatorsView › GroundStationRuleEditorView | 待分域核对 | 源码推定，未逐页点验 |
| 发数传计划 `PassPlanView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/PassPlanView.swift#L46) | 分享表格或内部通知 › passPlan | 待分域核对 | 源码推定，未逐页点验 |
| `PassPlanSheet` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/PassPlanView.swift#L2082) | 分享表格或内部通知 › passPlan › PassPlanSheet | 待分域核对 | 源码推定，未逐页点验 |
| `PassPlanRowEditor` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/PassPlanView.swift#L2125) | 分享表格或内部通知 › passPlan › PassPlanRowEditor | 待分域核对 | 源码推定，未逐页点验 |
| 排班规律 `SchedulePatternsView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/PatternsView.swift#L4) | 首页 › On Duty › 统计 › SchedulePatternsView | 待分域核对 | 源码推定，未逐页点验 |
| 网站公告 `SiteNoticesView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/PatternsView.swift#L457) | 首页 › On Duty › 设置 › SiteNoticesView | 待分域核对 | 源码推定，未逐页点验 |
| 排班预览 `RosterPreviewView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/RosterPreviewView.swift#L4) | 首页 › On Duty › 统计 › RosterPreviewView | 待分域核对 | 源码推定，未逐页点验 |
| 规则说明 `RulesExplainView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/RulesExplainView.swift#L4) | 首页 › On Duty › 设置 › RulesExplainView | 待分域核对 | 源码推定，未逐页点验 |
| 设置 `SettingsView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/SettingsView.swift#L5) | 首页 › On Duty › 设置 | 待分域核对 | 源码推定，未逐页点验 |
| 班次类型 `ShiftTypesView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/SettingsView.swift#L752) | 首页 › On Duty › 设置 › ShiftTypesView | 待分域核对 | 源码推定，未逐页点验 |
| `ShiftTypeEditor` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/SettingsView.swift#L800) | 首页 › On Duty › 设置 › ShiftTypesView › ShiftTypeEditor | 待分域核对 | 源码推定，未逐页点验 |
| 各组工作内容 `GroupNotesView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/SettingsView.swift#L840) | 首页 › On Duty › 设置 › GroupNotesView | 待分域核对 | 源码推定，未逐页点验 |
| 播报声音 `VoicePickerView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/SettingsView.swift#L987) | 首页 › On Duty › 设置 › VoicePickerView | 待分域核对 | 源码推定，未逐页点验 |
| 我是谁 `WhoAmIView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/SettingsView.swift#L1083) | 首页 › On Duty › 今天 › WhoAmIView | 待分域核对 | 源码推定，未逐页点验 |
| 身份 `RoleView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/SettingsView.swift#L1147) | 首页 › On Duty › 设置 › RoleView | 待分域核对 | 源码推定，未逐页点验 |
| 查找网页排班代码 `SiteCodeFinderView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/SiteCodeFinderView.swift#L6) | 首页 › On Duty › 设置 › SiteCodeFinderView | 待分域核对 | 源码推定，未逐页点验 |
| 找到的代码 `SiteCodeResultsView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/SiteCodeFinderView.swift#L75) | 首页 › On Duty › 设置 › SiteCodeFinderView › SiteCodeResultsView | 待分域核对 | 源码推定，未逐页点验 |
| 值班网站 `SiteView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/SiteView.swift#L5) | 首页 › On Duty › 网站 | 待分域核对 | 源码推定，未逐页点验 |
| 星图修复 `StarCollectionView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/StarCollectionView.swift#L3) | 首页 › On Duty › 游戏；外部 WuMind › 游戏 › TileGameHomeView › StarCollectionView | 待分域核对 | 源码推定，未逐页点验 |
| 分岔远征 `StarExpeditionHomeView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/StarExpeditionView.swift#L34) | 首页 › On Duty › 游戏；外部 WuMind › 游戏 › TileGameHomeView › StarExpeditionHomeView | 待分域核对 | 源码推定，未逐页点验 |
| `StarJourneyRewardView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/StarJourneyRewardView.swift#L3) | 首页 › On Duty › 游戏；外部 WuMind › 游戏 › TileGameHomeView › StarJourneyHomeView › StarJourneyRewardView | 待分域核对 | 源码推定，未逐页点验 |
| 星际旅程 `StarJourneyHomeView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/StarJourneyView.swift#L3) | 首页 › On Duty › 游戏；外部 WuMind › 游戏 › TileGameHomeView › StarJourneyHomeView | 待分域核对 | 源码推定，未逐页点验 |
| 逐手复盘 `StarRailReplayView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/StarRailReplayView.swift#L3) | 首页 › On Duty › 游戏；外部 WuMind › 游戏 › TileGameHomeView › StarExpeditionHomeView › StarRailReplayView | 待分域核对 | 源码推定，未逐页点验 |
| 星轨移层 `StarRailHomeView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/StarRailView.swift#L9) | 首页 › On Duty › 游戏；外部 WuMind › 游戏 › TileGameHomeView › StarRailHomeView | 待分域核对 | 源码推定，未逐页点验 |
| 叠层与航线 `StarRailBoardView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/StarRailView.swift#L97) | 首页 › On Duty › 游戏；外部 WuMind › 游戏 › TileGameHomeView › StarRailBoardView | 待分域核对 | 源码推定，未逐页点验 |
| 星约试炼 `StarTrialHomeView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/StarTrialView.swift#L46) | 首页 › On Duty › 游戏；外部 WuMind › 游戏 › TileGameHomeView › StarTrialHomeView | 待分域核对 | 源码推定，未逐页点验 |
| 人员档案 `PeopleProfilesView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/SystemViews.swift#L7) | 首页 › On Duty › 统计 › PeopleProfilesView | 待分域核对 | 源码推定，未逐页点验 |
| `PersonProfileView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/SystemViews.swift#L71) | 首页 › On Duty › 统计 › PeopleProfilesView › PersonProfileView | 待分域核对 | 源码推定，未逐页点验 |
| 排班变动记录 `RosterLogView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/SystemViews.swift#L160) | 首页 › On Duty › 统计 › RosterLogView | 待分域核对 | 源码推定，未逐页点验 |
| 星了个星 `TileGameHomeView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TileGameHome.swift#L3) | 首页 › On Duty › 游戏；外部 WuMind › 游戏 › TileGameHomeView | 待分域核对 | 源码推定，未逐页点验 |
| `TileRaceLobbyView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TileGameView.swift#L209) | 首页 › On Duty › 游戏；外部 WuMind › 游戏 › TileGameHomeView › TileRaceLobbyView | 待分域核对 | 源码推定，未逐页点验 |
| `TileBoardView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TileGameView.swift#L322) | 首页 › On Duty › 游戏；外部 WuMind › 游戏 › TileGameHomeView › TileBoardView | 待分域核对 | 源码推定，未逐页点验 |
| `TileReplayView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TileReplayView.swift#L4) | 首页 › On Duty › 游戏；外部 WuMind › 游戏 › TileGameHomeView › TileBoardView › TileReplayView | 待分域核对 | 源码推定，未逐页点验 |
| 今天页的卡片 `TodayLayoutView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TodayLayoutView.swift#L50) | 首页 › On Duty › 今天 › TodayLayoutView | 待分域核对 | 源码推定，未逐页点验 |
| `TodayView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TodayView.swift#L3) | 首页 › On Duty › 今天 | 待分域核对 | 源码推定，未逐页点验 |
| 找人换班 `NextWorkSwapView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TodayView.swift#L763) | 首页 › On Duty › 今天 › QuickActions › NextWorkSwapView | 待分域核对 | 源码推定，未逐页点验 |
| `ManagerHomeView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TodayView.swift#L825) | 首页 › On Duty › 今天 › ManagerHomeView | 待分域核对 | 源码推定，未逐页点验 |
| 找人换班 `SwapHelperView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ToolsViews.swift#L7) | 内部通知或日链接 › 指定日期 › SwapHelperView | 待分域核对 | 源码推定，未逐页点验 |
| 换班账本 `SwapLedgerView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ToolsViews.swift#L97) | 首页 › On Duty › 统计 › SwapLedgerView | 待分域核对 | 源码推定，未逐页点验 |
| 手动记一笔 `AddSwapView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ToolsViews.swift#L161) | 首页 › On Duty › 统计 › SwapLedgerView › AddSwapView | 待分域核对 | 源码推定，未逐页点验 |
| 全年统计 `YearStatsView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ToolsViews.swift#L218) | 首页 › On Duty › 统计 › YearStatsView | 待分域核对 | 源码推定，未逐页点验 |
| 下次遥测 `DutyForecastView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ToolsViews.swift#L301) | 首页 › On Duty › 统计 › DutyForecastView | 待分域核对 | 源码推定，未逐页点验 |
| 待休变化 `RestTrendView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ToolsViews.swift#L373) | 首页 › On Duty › 统计 › RestTrendView | 待分域核对 | 源码推定，未逐页点验 |
| 法定节假日 `HolidaysView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ToolsViews.swift#L445) | 首页 › On Duty › 设置 › HolidaysView | 待分域核对 | 源码推定，未逐页点验 |
| 网页登录 `WebLoginView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WebLoginView.swift#L6) | 首页 › On Duty › 今天 › WebLoginView | 待分域核对 | 源码推定，未逐页点验 |
| `WebView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WebLoginView.swift#L197) | 首页 › On Duty › 网站 › WebView | 待分域核对 | 源码推定，未逐页点验 |
| 新功能 `WhatsNewView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WhatsNewView.swift#L28) | 更新后进入 On Duty | 待分域核对 | 源码推定，未逐页点验 |
| 工作留痕 `WorkLogView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WorkLogView.swift#L74) | 内部通知 › workLog | 待分域核对 | 源码推定，未逐页点验 |
| `WorkLogDetailView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WorkLogView.swift#L405) | 内部通知或日链接 › 指定日期 › WorkLogDetailView | 待分域核对 | 源码推定，未逐页点验 |
| 录音 `RecorderSheet` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WorkLogView.swift#L539) | 小组件或快捷指令 › record | 待分域核对 | 源码推定，未逐页点验 |
| 记一笔 `NoteSheet` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WorkLogView.swift#L632) | 小组件或快捷指令 › note | 待分域核对 | 源码推定，未逐页点验 |
| `CameraPicker` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WorkLogView.swift#L668) | 小组件 › 拍照 | 待分域核对 | 源码推定，未逐页点验 |
| `ActivityView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WorkLogView.swift#L706) | 内部通知 › workLog › ActivityView | 待分域核对 | 源码推定，未逐页点验 |
| 统计／工作量 `WorkloadView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WorkloadView.swift#L4) | 首页 › On Duty › 统计 | 待分域核对 | 源码推定，未逐页点验 |
| `WorkloadDetailView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WorkloadView.swift#L264) | 首页 › On Duty › 统计 › WorkloadDetailView | 待分域核对 | 源码推定，未逐页点验 |
| 没排班不算上班的人 `RotationMembersView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WorkloadView.swift#L357) | 首页 › On Duty › 统计 › RotationMembersView | 待分域核对 | 源码推定，未逐页点验 |
| `WorkspaceLauncherHomeView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WorkspaceLauncherHomeView.swift#L10) | 首页 | 待分域核对 | 源码推定，未逐页点验 |
| 用户与账单 `WuMindAdminUsersPage` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindAdminBillingSections.swift#L175) | 首页 › On Duty › 设置 › WuMindAdminBillingView › WuMindAdminUsersPage | 待分域核对 | 源码推定，未逐页点验 |
| 用户账单详情 `WuMindAdminUserDetailPage` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindAdminBillingSections.swift#L393) | 首页 › On Duty › 设置 › WuMindAdminBillingView › WuMindAdminUsersPage › WuMindAdminUserDetailPage | 待分域核对 | 源码推定，未逐页点验 |
| 模型定价 `WuMindAdminPricingPage` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindAdminBillingSections.swift#L840) | 首页 › On Duty › 设置 › WuMindAdminBillingView › WuMindAdminPricingPage | 待分域核对 | 源码推定，未逐页点验 |
| `WuMindAdminUserDirectorySheet` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindAdminBillingSections.swift#L1361) | 待追踪 | 待分域核对 | 未证实普通用户入口 |
| `WuMindAdminModelCatalogSheet` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindAdminBillingSections.swift#L1378) | 待追踪 | 待分域核对 | 未证实普通用户入口 |
| 确认给用户加余额 `WuMindAdminManualCreditConfirmSheet` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindAdminBillingSections.swift#L1400) | 待追踪 | 待分域核对 | 未证实普通用户入口 |
| 项目与智能体总控 `WuMindAgentWorkspaceView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindAgentWorkspaceView.swift#L8) | 首页 › WuMind › WuMindAgentWorkspaceView | 待分域核对 | 源码推定，未逐页点验 |
| `InteractiveMiniAppWebView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindAgentWorkspaceView.swift#L750) | 首页 › WuMind › WuMindAgentWorkspaceView › InteractiveMiniAppWebView | 待分域核对 | 源码推定，未逐页点验 |
| WUMIND 钱包与计费 `WuMindWalletSheet` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindBillingViews.swift#L7) | 首页 › WuMind › WuMindWalletSheet | 待分域核对 | 源码推定，未逐页点验 |
| 商业计费管理 `WuMindAdminBillingView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindBillingViews.swift#L1030) | 首页 › On Duty › 设置 › WuMindAdminBillingView | 待分域核对 | 源码推定，未逐页点验 |
| 充值与支付 `WuMindAdminPaymentsPage` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindBillingViews.swift#L1442) | 首页 › On Duty › 设置 › WuMindAdminBillingView › WuMindAdminPaymentsPage | 待分域核对 | 源码推定，未逐页点验 |
| 网关与诊断 `WuMindAdminGatewayDiagnosticsPage` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindBillingViews.swift#L1695) | 首页 › On Duty › 设置 › WuMindAdminBillingView › WuMindAdminGatewayDiagnosticsPage | 待分域核对 | 源码推定，未逐页点验 |
| `SpyViewController` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindDesignComponents.swift#L87) | TabRootNavigationDepthSpy | 待分域核对 | 未证实普通用户入口 |
| 定制中心 `WuMindCustomizationsSheet` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindFlagshipHubViews.swift#L28) | 首页 › WuMind › WuMindCustomizationsSheet | 待分域核对 | 源码推定，未逐页点验 |
| `WuMindQuickSkillEditorSheet` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindFlagshipHubViews.swift#L500) | 首页 › WuMind › WuMindCustomizationsSheet › WuMindQuickSkillEditorSheet | 待分域核对 | 源码推定，未逐页点验 |
| 项目空间 `WuMindProjectsSheet` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindFlagshipHubViews.swift#L582) | 首页 › WuMind › WuMindProjectsSheet | 待分域核对 | 源码推定，未逐页点验 |
| `WuMindProjectEditorSheet` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindFlagshipHubViews.swift#L733) | 首页 › WuMind › WuMindProjectsSheet › WuMindProjectEditorSheet | 待分域核对 | 源码推定，未逐页点验 |
| 定时任务中心 `WuMindSchedulesSheet` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindFlagshipHubViews.swift#L896) | 首页 › WuMind › WuMindSchedulesSheet | 待分域核对 | 源码推定，未逐页点验 |
| `WuMindScheduleEditorSheet` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindFlagshipHubViews.swift#L1271) | 首页 › WuMind › WuMindSchedulesSheet › WuMindScheduleEditorSheet | 待分域核对 | 源码推定，未逐页点验 |
| WUMIND 设置 `WuMindSettingsSheet` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindFlagshipHubViews.swift#L1505) | 首页 › WuMind › WuMindSettingsSheet | 待分域核对 | 源码推定，未逐页点验 |
| `WuMindGeminiVoiceView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindGeminiVoiceView.swift#L11) | 首页 › WuMind › WuMindGeminiVoiceView | 待分域核对 | 源码推定，未逐页点验 |
| 充值与计费教程 `WuMindRechargeGuideSheet` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindHubComponents.swift#L90) | 首页 › WuMind › WuMindWalletSheet › WuMindRechargeGuideSheet | 待分域核对 | 源码推定，未逐页点验 |
| 管理员配置教程 `WuMindAdminSetupGuideSheet` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindHubComponents.swift#L206) | 首页 › On Duty › 设置 › WuMindAdminBillingView › WuMindAdminGatewayDiagnosticsPage › WuMindAdminSetupGuideSheet | 待分域核对 | 源码推定，未逐页点验 |
| 聊天内连接与插件 `WuMindInChatConnectorsSheet` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindInChatConnectorsSheet.swift#L8) | 首页 › WuMind › WuMindInChatConnectorsSheet | 待分域核对 | 源码推定，未逐页点验 |
| `WuMindInlineBuildPreview` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindInlineBuildCard.swift#L31) | 首页 › WuMind › WuMindInlineBuildCard › WuMindInlineBuildPreview | 待分域核对 | 源码推定，未逐页点验 |
| `WuMindChatArtifactPreview` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindInlineBuildCard.swift#L134) | 首页 › WuMind › WuMindChatArtifactPreview | 待分域核对 | 源码推定，未逐页点验 |
| `WuMindOfflineHTMLPreview` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindInlineBuildCard.swift#L254) | 首页 › WuMind › WuMindChatArtifactPreview › WuMindOfflineHTMLPreview | 待分域核对 | 源码推定，未逐页点验 |
| 发布到多平台 `WuMindMultiPlatformPublishSheet` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindMultiPlatformPublishSheet.swift#L11) | 首页 › WuMind › AIVideoToolView › WuMindShortDramaView › WuMindMultiPlatformPublishSheet | 待分域核对 | 源码推定，未逐页点验 |
| 抖音官方接口授权 `WuMindDouyinAuthSheet` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindMultiPlatformPublishSheet.swift#L610) | 首页 › WuMind › AIVideoToolView › WuMindShortDramaView › WuMindMultiPlatformPublishSheet › WuMindDouyinAuthSheet | 待分域核对 | 源码推定，未逐页点验 |
| AI 写 PPT 工坊 `WuMindPPTStudioView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindPPTStudioView.swift#L522) | 首页 › WuMind › WuMindPPTStudioView | 待分域核对 | 源码推定，未逐页点验 |
| `WuMindPPTSlideEditorSheet` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindPPTStudioView.swift#L1725) | 首页 › WuMind › WuMindPPTStudioView › WuMindPPTSlideEditorSheet | 待分域核对 | 源码推定，未逐页点验 |
| `WuMindMathBlockView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindRichRenderers.swift#L5) | 首页 › WuMind › WuMindTurnView › WuMindMarkdownView › WuMindMathBlockView | 待分域核对 | 源码推定，未逐页点验 |
| `WuMindMermaidDiagramView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindRichRenderers.swift#L68) | 首页 › WuMind › WuMindTurnView › WuMindMarkdownView › WuMindMermaidDiagramView | 待分域核对 | 源码推定，未逐页点验 |
| `WuMindFlowchartView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindRichRenderers.swift#L182) | 首页 › WuMind › WuMindTurnView › WuMindMarkdownView › WuMindMermaidDiagramView › WuMindFlowchartView | 待分域核对 | 源码推定，未逐页点验 |
| `WuMindSequenceDiagramView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindRichRenderers.swift#L321) | 首页 › WuMind › WuMindTurnView › WuMindMarkdownView › WuMindMermaidDiagramView › WuMindSequenceDiagramView | 待分域核对 | 源码推定，未逐页点验 |
| `WuMindPieDiagramView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindRichRenderers.swift#L393) | 首页 › WuMind › WuMindTurnView › WuMindMarkdownView › WuMindMermaidDiagramView › WuMindPieDiagramView | 待分域核对 | 源码推定，未逐页点验 |
| `WuMindMarkdownTableView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindRichRenderers.swift#L440) | 首页 › WuMind › WuMindTurnView › WuMindMarkdownView › WuMindMarkdownTableView | 待分域核对 | 源码推定，未逐页点验 |
| `WuMindShortDramaView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindShortDramaView.swift#L11) | 首页 › WuMind › AIVideoToolView › WuMindShortDramaView | 待分域核对 | 源码推定，未逐页点验 |
| 单镜生成与重拍对比 `WuMindShotReshootSheet` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindShortDramaView.swift#L881) | 首页 › WuMind › AIVideoToolView › WuMindShortDramaView › WuMindShotReshootSheet | 待分域核对 | 源码推定，未逐页点验 |
| 短剧官方视频接口 `WuMindShortDramaAPISheet` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindShortDramaView.swift#L1238) | 首页 › WuMind › AIVideoToolView › WuMindShortDramaAPISheet | 待分域核对 | 源码推定，未逐页点验 |
| AI 3D 空间工坊 `WuMindSpatial3DStudioView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindSpatial3DStudioView.swift#L12) | 首页 › WuMind › WuMindSpatial3DStudioView | 待分域核对 | 源码推定，未逐页点验 |
| 3D 空间工程库 `WuMindSpatialProjectLibrarySheet` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindSpatial3DStudioView.swift#L1373) | 首页 › WuMind › WuMindSpatial3DStudioView › WuMindSpatialProjectLibrarySheet | 待分域核对 | 源码推定，未逐页点验 |
| Tripo 自由造型道具接口 `WuMindSpatialTripoSheet` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindSpatial3DStudioView.swift#L1436) | 首页 › WuMind › WuMindSpatial3DStudioView › WuMindSpatialTripoSheet | 待分域核对 | 源码推定，未逐页点验 |
| 3D 技术库 `WuMind3DTechRegistrySheet` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindSpatial3DStudioView.swift#L1513) | 首页 › WuMind › WuMindSpatial3DStudioView › WuMind3DTechRegistrySheet | 待分域核对 | 源码推定，未逐页点验 |
| `WuMindSpatial3DViewport` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindSpatial3DViewport.swift#L12) | 首页 › WuMind › WuMindChatArtifactPreview › WuMindSpatial3DViewport | 待分域核对 | 源码推定，未逐页点验 |
| 跨设备加密同步 `WuMindSyncSheet` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindSyncSheet.swift#L6) | 首页 › WuMind › WuMindSyncSheet | 待分域核对 | 源码推定，未逐页点验 |
| WuMind 对话 `WuMindWorkspaceView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindView.swift#L76) | 首页 › WuMind | 待分域核对 | 源码推定，未逐页点验 |
| `WuMindStreamingTurnView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindView.swift#L2787) | 首页 › WuMind › WuMindStreamingTurnView | 待分域核对 | 源码推定，未逐页点验 |
| `WuMindTurnView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindView.swift#L2849) | 首页 › WuMind › WuMindTurnView | 待分域核对 | 源码推定，未逐页点验 |
| `WuMindMarkdownView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindView.swift#L3541) | 首页 › WuMind › WuMindTurnView › WuMindMarkdownView | 待分域核对 | 源码推定，未逐页点验 |
| WUMIND 模型与能力中心 `WuMindModelHubSheet` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindView.swift#L3825) | 首页 › WuMind › WuMindModelHubSheet | 待分域核对 | 源码推定，未逐页点验 |
| 连接 GitHub `WuMindGitHubSheet` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindView.swift#L4755) | 首页 › WuMind › WuMindGitHubSheet | 待分域核对 | 源码推定，未逐页点验 |
| 同题对比与交叉复核 `WuMindCompareTurnSheet` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindView.swift#L5186) | 首页 › WuMind › WuMindCompareTurnSheet | 待分域核对 | 源码推定，未逐页点验 |
| 对话共享资料 `WuMindSharedMaterialsSheet` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindView.swift#L5321) | 首页 › WuMind › WuMindSharedMaterialsSheet | 待分域核对 | 源码推定，未逐页点验 |
| 已归档对话 `WuMindArchivedConversationsSheet` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindView.swift#L5381) | 首页 › WuMind › WuMindArchivedConversationsSheet | 待分域核对 | 源码推定，未逐页点验 |
| `WuMindWorkbenchView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindWorkbenchView.swift#L7) | 首页 › WuMind › WuMindWorkbenchView | 待分域核对 | 源码推定，未逐页点验 |
| `WuMindWorksView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindWorksView.swift#L9) | 首页 › WuMind › WuMindWorksView | 待分域核对 | 源码推定，未逐页点验 |
| `WuMindWorkDetailSheet` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindWorksView.swift#L474) | 首页 › WuMind › WuMindChatArtifactPreview › WuMindWorkDetailSheet | 待分域核对 | 源码推定，未逐页点验 |
| `ShareViewController` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/TenderShareExtension/ShareViewController.swift#L6) | iOS 系统分享 › 值班提醒 | 待分域核对 | 源码推定，未逐页点验 |
| `ShiftWidgetView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/Widget/ShiftWidget.swift#L57) | iOS 小组件 › ShiftWidgetView | 待分域核对 | 源码推定，未逐页点验 |
| `ShiftWidget` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/Widget/ShiftWidget.swift#L182) | iOS 小组件 | 待分域核对 | 源码推定，未逐页点验 |
| `NextDutyView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/Widget/ShiftWidget.swift#L409) | iOS 小组件库 › NextDutyWidget | 待分域核对 | 小组件宿主源已定位，未点验 |
| `CaptureWidgetView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/Widget/ShiftWidget.swift#L497) | iOS 小组件库 › CaptureWidget | 待分域核对 | 小组件宿主源已定位，未点验 |
| `TeamDutyView` [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/Widget/ShiftWidget.swift#L651) | iOS 小组件库 › TeamDutyWidget | 待分域核对 | 小组件宿主源已定位，未点验 |

## 弹层、导航声明和系统选择器

每行对应一处呈现声明或 NavigationLink。行内构造器以源码行显示。由绑定或枚举分派的目的页以该声明处的 switch 为准。

| 父页面或文件 | 控件或呈现声明 | 来源 |
|---|---|---|
| `RootView` | `.sheet(item: $openDay) { DayEditor(day: $0) }` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/ShiftApp.swift#L456) |
| `RootView` | `.sheet(item: $rootSheet) { sheet in` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/ShiftApp.swift#L457) |
| `RootView` | `.fullScreenCover(isPresented: Binding(get: { activeWorkspace == .duty && !AppStore.isDemo && !store.settings.onboardingDone },` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/ShiftApp.swift#L496) |
| `RootView` | `.fullScreenCover(isPresented: $camera) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/ShiftApp.swift#L500) |
| `AICodeWorkToolsView` | `NavigationLink { PassPlanView() } label: {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/AICodeWorkToolsView.swift#L110) |
| `AICodeWorkToolsView` | `NavigationLink { DeepSeekTenderView() } label: {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/AICodeWorkToolsView.swift#L129) |
| `AICodeWorkToolsView` | `.sheet(isPresented: $showingKey, onDismiss: syncKeyStatus) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/AICodeWorkToolsView.swift#L330) |
| `AIImageToolView` | `.photosPicker(isPresented: $showingRefPhotoPicker, selection: $pickedRefPhotoItem, matching: .images)` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/AIImageToolView.swift#L475) |
| `AIImageToolView` | `.fileImporter(` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/AIImageToolView.swift#L477) |
| `AIImageToolView` | `.sheet(isPresented: $showingHistory) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/AIImageToolView.swift#L488) |
| `AIImageToolView` | `.sheet(isPresented: $showingDiagnostics) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/AIImageToolView.swift#L493) |
| `AIImageToolView` | `.sheet(isPresented: $settingAIHubMix) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/AIImageToolView.swift#L500) |
| `AIImageToolView` | `.sheet(isPresented: $settingKey) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/AIImageToolView.swift#L509) |
| `AIImageToolView` | `.fullScreenCover(item: $lightboxItem) { item in` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/AIImageToolView.swift#L518) |
| `AILiveCallView` | `.sheet(isPresented: $showingKey) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/AILiveCallView.swift#L438) |
| `AIProviderListView` | `NavigationLink { WuMindAgentWorkspaceView() } label: {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/AIProviderListView.swift#L41) |
| `AIProviderListView` | `NavigationLink { WuMindSpatial3DStudioView() } label: {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/AIProviderListView.swift#L53) |
| `AIProviderListView` | `NavigationLink { AIImageToolView() } label: {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/AIProviderListView.swift#L65) |
| `AIProviderListView` | `NavigationLink { AIVideoToolView() } label: {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/AIProviderListView.swift#L77) |
| `AIProviderListView` | `NavigationLink { WuMindPPTStudioView() } label: {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/AIProviderListView.swift#L89) |
| `AIProviderListView` | `NavigationLink { AILiveCallView() } label: {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/AIProviderListView.swift#L101) |
| `AIProviderListView` | `NavigationLink { AISpeechToolView() } label: {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/AIProviderListView.swift#L113) |
| `AIProviderListView` | `NavigationLink { AICodeWorkToolsView(kind: .code) } label: {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/AIProviderListView.swift#L131) |
| `AIProviderListView` | `NavigationLink { AICodeWorkToolsView(kind: .work) } label: {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/AIProviderListView.swift#L143) |
| `AIProviderListView` | `NavigationLink { DeepSeekTenderView() } label: {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/AIProviderListView.swift#L155) |
| `AISpeechToolView` | `.fileImporter(isPresented: $importing, allowedContentTypes: importTypes) { result in` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/AISpeechToolView.swift#L158) |
| `AISpeechToolView` | `.fileExporter(isPresented: $exporting, document: synthesized.map { WaveDocument(data: $0) },` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/AISpeechToolView.swift#L161) |
| `AIVideoToolView` | `.fullScreenCover(isPresented: $showingGenerationStage, onDismiss: {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/AIVideoToolView.swift#L313) |
| `AIVideoToolView` | `.sheet(isPresented: $showingHistory) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/AIVideoToolView.swift#L333) |
| `AIVideoToolView` | `.sheet(isPresented: $showingDramaAPIConfig) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/AIVideoToolView.swift#L339) |
| `AIVideoToolView` | `.sheet(item: $configuringProvider) { provider in` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/AIVideoToolView.swift#L342) |
| `AllFeaturesView` | `NavigationLink {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/AllFeaturesView.swift#L132) |
| `ArenaHomeView` | `.fullScreenCover(item: $sheet, onDismiss: {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ArenaLobby.swift#L233) |
| `ArenaHomeView` | `.fullScreenCover(isPresented: $adventure, onDismiss: { ArenaSound.shared.enterLobby() }) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ArenaLobby.swift#L245) |
| `ArenaHomeView` | `.fullScreenCover(item: $playing, onDismiss: { ArenaSound.shared.enterLobby() }) { entry in` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ArenaLobby.swift#L248) |
| `ArenaHomeView` | `.fullScreenCover(item: $lobby, onDismiss: { ArenaSound.shared.enterLobby() }) { entry in` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ArenaLobby.swift#L251) |
| `ArenaResourcePackView` | `.fileImporter(isPresented: $picking, allowedContentTypes: [.arenaResourcePack, .data], allowsMultipleSelection: false) { result in` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ArenaResourcePackView.swift#L98) |
| `ArenaResourcePackView` | `.sheet(item: $selectedMap) { map in ArenaResourceMapView(map: map) }` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ArenaResourcePackView.swift#L111) |
| `ArenaStoryView` | `.fullScreenCover(item: $playing, onDismiss: finished) { entry in` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ArenaStoryView.swift#L75) |
| `ArenaRoomView` | `.fullScreenCover(item: $lobby.playing) { playing in` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ArenaView.swift#L192) |
| `BackupView` | `.fileImporter(isPresented: $showImporter, allowedContentTypes: pickFolder ? [.folder] : [.json, .data]) { result in` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/BackupView.swift#L81) |
| `CalendarView` | `NavigationLink {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/CalendarView.swift#L93) |
| `CalendarView` | `.sheet(item: $editing) { DayEditor(day: $0) }` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/CalendarView.swift#L100) |
| `CalendarView` | `.sheet(isPresented: $jumping) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/CalendarView.swift#L121) |
| `DayEditor` | `NavigationLink { WorkLogDetailView(entry: entry) } label: { WorkLogRow(entry: entry) }` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/CalendarView.swift#L344) |
| `DayEditor` | `NavigationLink {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/CalendarView.swift#L349) |
| `DayEditor` | `NavigationLink {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/CalendarView.swift#L355) |
| `DayEditor` | `NavigationLink {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/CalendarView.swift#L361) |
| `DayRosterView` | `NavigationLink {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DayRosterView.swift#L123) |
| `DayRosterView` | `NavigationLink {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DayRosterView.swift#L170) |
| `DeepSeekTenderView` | `.fileImporter(isPresented: $selecting, allowedContentTypes: allowedTypes, onCompletion: pick)` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DeepSeekTenderView.swift#L333) |
| `DeepSeekTenderView` | `.sheet(isPresented: $showingKey) { DeepSeekPlanKeyView() }` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DeepSeekTenderView.swift#L334) |
| `DeepSeekTenderView` | `.sheet(item: $sourcePreview, onDismiss: removeWordPreview) { preview in` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DeepSeekTenderView.swift#L335) |
| `DuelHomeView` | `.fullScreenCover(item: $match) { selected in` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DuelHomeView.swift#L199) |
| `DuelHomeView` | `.fullScreenCover(isPresented: $showingNetworkEntry) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DuelHomeView.swift#L202) |
| `DuelNetworkEntryView` | `.fullScreenCover(item: $roomEntry) { entry in` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DuelNetworkRoomView.swift#L47) |
| `DutyBurdenUpcomingView` | `.sheet(item: $focus) { item in` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DutyBurdenUpcomingView.swift#L80) |
| `DutyBurdenView` | `NavigationLink {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DutyBurdenView.swift#L23) |
| `DutyBurdenView` | `NavigationLink {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DutyBurdenView.swift#L40) |
| `DutyWorkbenchCard` | `NavigationLink {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DutyWorkbenchView.swift#L71) |
| `DutyWorkbenchCard` | `NavigationLink {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DutyWorkbenchView.swift#L84) |
| `DutyWorkbenchCard` | `NavigationLink {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DutyWorkbenchView.swift#L99) |
| `DutyWorkbenchCard` | `NavigationLink {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DutyWorkbenchView.swift#L112) |
| `DutyWorkbenchCard` | `NavigationLink(destination: destination) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DutyWorkbenchView.swift#L177) |
| `DutyHandoffView` | `NavigationLink("打开本班任务清单") { DutyChecklistView(day: window.day) }` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DutyWorkbenchView.swift#L246) |
| `DutyHandoffView` | `NavigationLink("查看原排班") { DayRosterView(day: endDay) }` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DutyWorkbenchView.swift#L269) |
| `DutyHandoffView` | `NavigationLink("查看数传计划") { PassPlanView() }` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DutyWorkbenchView.swift#L302) |
| `ExternalAccountProfileView` | `NavigationLink { AIProviderListView() } label: {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ExternalAuthView.swift#L502) |
| `ExternalAccountProfileView` | `.sheet(isPresented: $showingExternalAuth) { ExternalAuthView() }` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ExternalAuthView.swift#L564) |
| `ExternalAccountProfileView` | `.sheet(isPresented: $showingWallet) { WuMindWalletSheet(store: wumind) }` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ExternalAuthView.swift#L565) |
| `GamesHomeView` | `NavigationLink { TileGameHomeView() } label: {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/GamesHomeView.swift#L40) |
| `GamesHomeView` | `.fullScreenCover(isPresented: $showingDuel, onDismiss: {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/GamesHomeView.swift#L78) |
| `GamesHomeView` | `.fullScreenCover(isPresented: $showingXuPractice, onDismiss: {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/GamesHomeView.swift#L82) |
| `GamesHomeView` | `.fullScreenCover(isPresented: $showingArena) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/GamesHomeView.swift#L86) |
| `GomokuHomeView` | `.fullScreenCover(item: $local) { mode in` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/GomokuView.swift#L82) |
| `GomokuHomeView` | `.fullScreenCover(item: $room) { entry in` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/GomokuView.swift#L85) |
| `GomokuHomeView` | `.sheet(item: $opened) { entry in` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/GomokuView.swift#L88) |
| `ImportView` | `.fileImporter(isPresented: $showingFilePicker,` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ImportView.swift#L93) |
| `DataCheckView` | `NavigationLink("看这天全部组别") { DayRosterView(day: day) }.font(.caption)` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/InsightViews.swift#L68) |
| `WorkloadRulesView` | `NavigationLink {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/InsightViews.swift#L155) |
| `WorkloadRulesView` | `NavigationLink {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/InsightViews.swift#L160) |
| `MeetingCard` | `NavigationLink { MeetingIssuesView(mineOnly: !mine.isEmpty) } label: {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/MeetingViews.swift#L49) |
| `MeetingIssuesView` | `.sheet(item: $confirming) { pending in` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/MeetingViews.swift#L211) |
| `MeetingIssuesView` | `.sheet(isPresented: $showingSource) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/MeetingViews.swift#L235) |
| `MeetingIssuesView` | `.navigationDestination(isPresented: $showingTrend) { MeetingTrendView() }` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/MeetingViews.swift#L238) |
| `MeetingSourceView` | `NavigationLink("查看上次自动下载的过程") {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/MeetingViews.swift#L930) |
| `MeetingSourceView` | `NavigationLink("查看上次读到的内容") {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/MeetingViews.swift#L939) |
| `MeetingSourceView` | `.fullScreenCover(isPresented: $browsing) { MeetingDocBrowser() }` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/MeetingViews.swift#L957) |
| `MeetingSourceView` | `.fileImporter(isPresented: $pickingFile,` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/MeetingViews.swift#L958) |
| `MeetingSourceView` | `allowedContentTypes: [UTType("org.openxmlformats.spreadsheetml.sheet") ?? .data,` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/MeetingViews.swift#L959) |
| `MeetingSourceView` | `.sheet(isPresented: $pasting) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/MeetingViews.swift#L964) |
| `MeetingSourceView` | `NavigationLink("查看写回记录") {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/MeetingViews.swift#L1030) |
| `MemberSearchView` | `NavigationLink {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/MemberSearchView.swift#L34) |
| `MemberScheduleView` | `NavigationLink { DayRosterView(day: item.day) } label: { row(item.day, item.post, isToday: item.day == today) }` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/MemberSearchView.swift#L134) |
| `MemberScheduleView` | `NavigationLink { DayRosterView(day: item.day) } label: { row(item.day, item.post, isToday: false) }` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/MemberSearchView.swift#L153) |
| `LeavePlannerView` | `NavigationLink { SwapHelperView(day: d) } label: {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/MoreViews.swift#L317) |
| `OnboardingView` | `.fullScreenCover(isPresented: $showingWebLogin) { WebLoginView() }` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/OnboardingView.swift#L60) |
| `OnboardingView` | `.sheet(isPresented: $showingExternalAuth) { ExternalAuthView() }` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/OnboardingView.swift#L61) |
| `PassPlanBurstCameraView` | `.fullScreenCover(item: $previewingShot) { shot in` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/PassPlanBurstCameraView.swift#L65) |
| `PassPlanOperatorsView` | `.navigationDestination(isPresented: $isPresentingEditor) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/PassPlanOperatorsView.swift#L129) |
| `PassPlanView` | `NavigationLink {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/PassPlanView.swift#L394) |
| `PassPlanView` | `NavigationLink {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/PassPlanView.swift#L920) |
| `PassPlanView` | `NavigationLink {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/PassPlanView.swift#L1169) |
| `PassPlanView` | `.fullScreenCover(isPresented: $scanning, onDismiss: handleCapturedPhotoDismiss) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/PassPlanView.swift#L1303) |
| `PassPlanView` | `.fullScreenCover(isPresented: $showingCamera, onDismiss: handleCapturedPhotoDismiss) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/PassPlanView.swift#L1307) |
| `PassPlanView` | `.fileImporter(isPresented: $importing,` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/PassPlanView.swift#L1327) |
| `PassPlanView` | `.sheet(item: $editing) { target in editorView(target) }` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/PassPlanView.swift#L1332) |
| `PassPlanView` | `.sheet(item: $sharePreview, onDismiss: { pendingReceipt = nil }) { request in` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/PassPlanView.swift#L1333) |
| `PassPlanView` | `.sheet(isPresented: $showingCloudKey, onDismiss: loadCloudKeyStatus) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/PassPlanView.swift#L1336) |
| `SchedulePatternsView` | `.sheet(item: $sharing) { ActivityView(items: $0.urls) }` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/PatternsView.swift#L53) |
| `RulesExplainView` | `NavigationLink("改工作量规则") { WorkloadRulesView() }` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/RulesExplainView.swift#L45) |
| `SettingsView` | `NavigationLink { RoleView() } label: {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/SettingsView.swift#L32) |
| `SettingsView` | `NavigationLink {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/SettingsView.swift#L98) |
| `SettingsView` | `NavigationLink {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/SettingsView.swift#L110) |
| `SettingsView` | `NavigationLink {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/SettingsView.swift#L130) |
| `SettingsView` | `NavigationLink {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/SettingsView.swift#L150) |
| `SettingsView` | `NavigationLink {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/SettingsView.swift#L171) |
| `SettingsView` | `NavigationLink {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/SettingsView.swift#L176) |
| `SettingsView` | `.sheet(isPresented: $showWhatsNew) { WhatsNewView() }` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/SettingsView.swift#L190) |
| `SettingsView` | `NavigationLink {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/SettingsView.swift#L192) |
| `SettingsView` | `NavigationLink {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/SettingsView.swift#L197) |
| `SettingsView` | `NavigationLink {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/SettingsView.swift#L202) |
| `SettingsView` | `.fullScreenCover(isPresented: $showingWebLogin) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/SettingsView.swift#L221) |
| `SettingsView` | `.sheet(isPresented: $showingExternalAuth) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/SettingsView.swift#L224) |
| `SettingsView` | `.sheet(isPresented: $showingWuMindWallet) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/SettingsView.swift#L227) |
| `SettingsView` | `.sheet(isPresented: $showingWuMindSettings) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/SettingsView.swift#L230) |
| `SettingsView` | `NavigationLink {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/SettingsView.swift#L247) |
| `SettingsView` | `NavigationLink {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/SettingsView.swift#L265) |
| `SettingsView` | `NavigationLink {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/SettingsView.swift#L274) |
| `SettingsView` | `NavigationLink {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/SettingsView.swift#L279) |
| `SettingsView` | `NavigationLink {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/SettingsView.swift#L284) |
| `SettingsView` | `NavigationLink {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/SettingsView.swift#L293) |
| `SettingsView` | `NavigationLink {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/SettingsView.swift#L299) |
| `SettingsView` | `NavigationLink {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/SettingsView.swift#L304) |
| `SettingsView` | `NavigationLink {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/SettingsView.swift#L309) |
| `SettingsView` | `NavigationLink {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/SettingsView.swift#L377) |
| `SettingsView` | `NavigationLink {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/SettingsView.swift#L383) |
| `SettingsView` | `NavigationLink {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/SettingsView.swift#L493) |
| `SettingsView` | `NavigationLink {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/SettingsView.swift#L581) |
| `ShiftTypesView` | `NavigationLink {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/SettingsView.swift#L760) |
| `GroupNotesView` | `NavigationLink("查看 App 读到的页面内容") {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/SettingsView.swift#L893) |
| `GroupNotesView` | `.fullScreenCover(isPresented: $browsing) { DesktopNotesBrowser() }` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/SettingsView.swift#L955) |
| `GroupNotesView` | `.sheet(isPresented: $pasting) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/SettingsView.swift#L956) |
| `SiteCodeFinderView` | `.sheet(isPresented: $showResults) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/SiteCodeFinderView.swift#L44) |
| `StarExpeditionHomeView` | `.fullScreenCover(item: $play) { StarRailBoardView(game: $0.game) }` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/StarExpeditionView.swift#L68) |
| `StarExpeditionHomeView` | `.sheet(item: $replay) { StarRailReplayView(game: $0.game, back: store.cardBack, sky: store.sky) }` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/StarExpeditionView.swift#L69) |
| `StarJourneyHomeView` | `.fullScreenCover(item:$play) { StarRailBoardView(game:$0.game) }` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/StarJourneyView.swift#L31) |
| `StarRailHomeView` | `.fullScreenCover(item: $play) { StarRailBoardView(game: $0.game) }` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/StarRailView.swift#L56) |
| `StarRailBoardView` | `.sheet(isPresented: $inspection) { inspectionSheet }` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/StarRailView.swift#L169) |
| `StarRailBoardView` | `.sheet(item: $replay) { item in` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/StarRailView.swift#L170) |
| `StarRailBoardView` | `.fullScreenCover(isPresented: $trialHall) { StarTrialHomeView() }` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/StarRailView.swift#L178) |
| `StarTrialHomeView` | `.fullScreenCover(item: $play) { StarRailBoardView(game: $0.game) }` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/StarTrialView.swift#L91) |
| `PeopleProfilesView` | `NavigationLink {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/SystemViews.swift#L46) |
| `TileGameHomeView` | `.fullScreenCover(item: $play) { TileBoardView(play: $0, race: nil) }` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TileGameHome.swift#L65) |
| `TileGameHomeView` | `.fullScreenCover(isPresented: $starRails) { StarRailHomeView() }` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TileGameHome.swift#L66) |
| `TileGameHomeView` | `.fullScreenCover(item: $railPlay) { StarRailBoardView(game: $0.game) }` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TileGameHome.swift#L67) |
| `TileGameHomeView` | `.fullScreenCover(isPresented: $trialHall) { StarTrialHomeView() }` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TileGameHome.swift#L68) |
| `TileGameHomeView` | `.fullScreenCover(isPresented: $expeditionHall) { StarExpeditionHomeView() }` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TileGameHome.swift#L69) |
| `TileGameHomeView` | `.fullScreenCover(isPresented: $collection) { StarCollectionView() }` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TileGameHome.swift#L70) |
| `TileGameHomeView` | `.fullScreenCover(isPresented: $journeyHall) { StarJourneyHomeView() }` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TileGameHome.swift#L71) |
| `TileGameHomeView` | `.fullScreenCover(item: $trialPlay) { StarRailBoardView(game: $0.game) }` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TileGameHome.swift#L72) |
| `TileGameHomeView` | `.fullScreenCover(item: $lobby) { TileRaceLobbyView(room: $0.room) }` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TileGameHome.swift#L76) |
| `TileGameHomeView` | `.sheet(isPresented: $social) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TileGameHome.swift#L77) |
| `TileGameHomeView` | `.sheet(isPresented: $help) { helpSheet }` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TileGameHome.swift#L94) |
| `TileRaceLobbyView` | `.fullScreenCover(item: $race.presented) { round in` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TileGameView.swift#L261) |
| `TileBoardView` | `.fullScreenCover(isPresented: $showingReplay) { TileReplayView(replay: replay) }` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TileGameView.swift#L422) |
| `TodayView` | `NavigationLink("看诊断") { DiagnosticsView() }` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TodayView.swift#L43) |
| `TodayView` | `NavigationLink { WhoAmIView() } label: {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TodayView.swift#L52) |
| `TodayView` | `NavigationLink { TodayLayoutView() } label: {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TodayView.swift#L75) |
| `TodayView` | `NavigationLink {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TodayView.swift#L119) |
| `TodayView` | `NavigationLink {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TodayView.swift#L124) |
| `TodayView` | `.sheet(item: $editing) { DayEditor(day: $0) }` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TodayView.swift#L134) |
| `TodayView` | `.sheet(isPresented: $searching) { MemberSearchView() }` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TodayView.swift#L135) |
| `TodayView` | `.fullScreenCover(isPresented: $loggingIn) { WebLoginView() }` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TodayView.swift#L136) |
| `MonthStatCard` | `NavigationLink { WorkloadView() } label: {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TodayView.swift#L358) |
| `GamesCard` | `NavigationLink { TileGameHomeView() } label: { small("星了个星", "square.stack.3d.up.fill", 6) }` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TodayView.swift#L440) |
| `GamesCard` | `.fullScreenCover(isPresented: $showingArena) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TodayView.swift#L443) |
| `QuickActions` | `NavigationLink(destination: destination) { label(title, icon, color: color) }` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TodayView.swift#L493) |
| `StaleSyncBanner` | `NavigationLink { DiagnosticsView() } label: { Label("看原因", systemImage: "stethoscope") }` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TodayView.swift#L580) |
| `NoticeChangeCard` | `NavigationLink { SiteNoticesView() } label: {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TodayView.swift#L628) |
| `FavoritesCard` | `NavigationLink {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TodayView.swift#L689) |
| `DutyInsightCard` | `NavigationLink { SchedulePatternsView() } label: {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TodayView.swift#L785) |
| `ManagerHomeView` | `.sheet(isPresented: $searching) { MemberSearchView() }` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TodayView.swift#L896) |
| `ManagerHomeView` | `return NavigationLink { DayRosterView(day: day) } label: {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TodayView.swift#L902) |
| `ManagerHomeView` | `NavigationLink(destination: destination) { label(title, icon) }` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TodayView.swift#L933) |
| `SwapHelperView` | `NavigationLink("这些规则从哪来？看规则说明") { RulesExplainView() }` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ToolsViews.swift#L31) |
| `SwapLedgerView` | `.sheet(isPresented: $adding) { AddSwapView() }` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ToolsViews.swift#L151) |
| `YearStatsView` | `NavigationLink { YearSummaryView(year: year) } label: {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ToolsViews.swift#L233) |
| `YearStatsView` | `NavigationLink { MultiYearStatsView() } label: {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ToolsViews.swift#L236) |
| `DutyForecastView` | `NavigationLink("看完整顺序和规律") { SchedulePatternsView() }` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ToolsViews.swift#L316) |
| `WebLoginView` | `.sheet(item: $captured) { page in` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WebLoginView.swift#L78) |
| `WorkLogCard` | `NavigationLink { WorkLogView() } label: {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WorkLogView.swift#L17) |
| `WorkLogCard` | `.fullScreenCover(isPresented: $camera) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WorkLogView.swift#L46) |
| `WorkLogCard` | `.sheet(isPresented: $recording) { RecorderSheet() }` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WorkLogView.swift#L54) |
| `WorkLogCard` | `.sheet(isPresented: $writing) { NoteSheet() }` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WorkLogView.swift#L55) |
| `WorkLogView` | `NavigationLink { WorkLogDetailView(entry: entry) } label: { WorkLogRow(entry: entry) }` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WorkLogView.swift#L124) |
| `WorkLogView` | `.sheet(item: $sharing) { ActivityView(items: $0.urls) }` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WorkLogView.swift#L243) |
| `WorkLogView` | `.fullScreenCover(isPresented: $camera) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WorkLogView.swift#L267) |
| `WorkLogView` | `.sheet(isPresented: $recording) { RecorderSheet() }` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WorkLogView.swift#L273) |
| `WorkLogView` | `.sheet(isPresented: $writing) { NoteSheet() }` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WorkLogView.swift#L274) |
| `WorkLogView` | `.fileImporter(isPresented: $importing, allowedContentTypes: [.audio, .image, .pdf, .item],` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WorkLogView.swift#L275) |
| `WorkloadView` | `NavigationLink {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WorkloadView.swift#L91) |
| `WorkloadView` | `NavigationLink { SwapLedgerView() } label: {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WorkloadView.swift#L105) |
| `WorkloadView` | `NavigationLink {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WorkloadView.swift#L125) |
| `WorkloadView` | `NavigationLink {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WorkloadView.swift#L173) |
| `WorkloadView` | `.navigationDestination(isPresented: Binding(get: { toolIndex != nil }, set: { if !$0 { toolIndex = nil } })) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WorkloadView.swift#L202) |
| `WorkloadView` | `NavigationLink {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WorkloadView.swift#L209) |
| `WorkloadDetailView` | `NavigationLink {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WorkloadView.swift#L331) |
| `WuMindAdminUsersPage` | `NavigationLink {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindAdminBillingSections.swift#L217) |
| `WuMindAdminUserDetailPage` | `.sheet(isPresented: $showingDirectCredit) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindAdminBillingSections.swift#L539) |
| `WuMindAdminUserDetailPage` | `.sheet(isPresented: $showingExemptSheet) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindAdminBillingSections.swift#L542) |
| `WuMindAdminPricingPage` | `.sheet(item: $editingModel) { m in` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindAdminBillingSections.swift#L1030) |
| `WuMindAdminPricingPage` | `.sheet(isPresented: Binding(` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindAdminBillingSections.swift#L1033) |
| `WuMindWalletSheet` | `.sheet(isPresented: $showingGuide) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindBillingViews.swift#L85) |
| `WuMindAdminBillingView` | `NavigationLink {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindBillingViews.swift#L1120) |
| `WuMindAdminBillingView` | `NavigationLink {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindBillingViews.swift#L1137) |
| `WuMindAdminBillingView` | `NavigationLink {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindBillingViews.swift#L1159) |
| `WuMindAdminBillingView` | `NavigationLink {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindBillingViews.swift#L1173) |
| `WuMindAdminGatewayDiagnosticsPage` | `.sheet(isPresented: $showingSetupGuide) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindBillingViews.swift#L1785) |
| `WuMindCustomizationsSheet` | `.sheet(item: $configuringConnector) { spec in` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindFlagshipHubViews.swift#L97) |
| `WuMindCustomizationsSheet` | `.sheet(isPresented: $creatingSkill) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindFlagshipHubViews.swift#L100) |
| `WuMindCustomizationsSheet` | `.sheet(item: $editingSkill) { skill in` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindFlagshipHubViews.swift#L105) |
| `WuMindCustomizationsSheet` | `.accessibilityIdentifier("wumind.customizations.sheet")` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindFlagshipHubViews.swift#L113) |
| `WuMindProjectsSheet` | `.sheet(isPresented: $creatingProject) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindFlagshipHubViews.swift#L722) |
| `WuMindProjectsSheet` | `.sheet(item: $editingProject) { project in` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindFlagshipHubViews.swift#L725) |
| `WuMindProjectsSheet` | `.accessibilityIdentifier("wumind.projects.sheet")` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindFlagshipHubViews.swift#L729) |
| `WuMindProjectEditorSheet` | `.fileImporter(isPresented: $showingImporter, allowedContentTypes: Self.allowedDocTypes, allowsMultipleSelection: true) { result in` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindFlagshipHubViews.swift#L844) |
| `WuMindSchedulesSheet` | `.sheet(isPresented: $creating) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindFlagshipHubViews.swift#L1003) |
| `WuMindSchedulesSheet` | `.sheet(item: $editingTask) { task in` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindFlagshipHubViews.swift#L1006) |
| `WuMindSchedulesSheet` | `.accessibilityIdentifier("wumind.schedules.sheet")` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindFlagshipHubViews.swift#L1015) |
| `WuMindSettingsSheet` | `.sheet(item: $editingMemory) { item in` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindFlagshipHubViews.swift#L1549) |
| `WuMindSettingsSheet` | `.accessibilityIdentifier("wumind.settings.sheet")` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindFlagshipHubViews.swift#L1601) |
| `WuMindInlineBuildPreview` | `.quickLookPreview($filePreviewURL)` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindInlineBuildCard.swift#L50) |
| `WuMindMultiPlatformPublishSheet` | `.sheet(isPresented: $showingDouyinAuth) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindMultiPlatformPublishSheet.swift#L87) |
| `WuMindPPTStudioView` | `.sheet(isPresented: $showingHistory) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindPPTStudioView.swift#L662) |
| `WuMindPPTStudioView` | `.fileImporter(` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindPPTStudioView.swift#L667) |
| `WuMindPPTStudioView` | `.photosPicker(isPresented: $showingPhotoPicker, selection: $pickedPhotoItem, matching: .images)` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindPPTStudioView.swift#L676) |
| `WuMindPPTStudioView` | `.photosPicker(isPresented: $showingLogoPicker, selection: $pickedLogoItem, matching: .images)` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindPPTStudioView.swift#L680) |
| `WuMindPPTStudioView` | `.sheet(isPresented: $showingRegenSheet) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindPPTStudioView.swift#L690) |
| `WuMindPPTStudioView` | `.sheet(isPresented: Binding(` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindPPTStudioView.swift#L694) |
| `WuMindMermaidDiagramView` | `.sheet(isPresented: $expandedFullScreen) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindRichRenderers.swift#L144) |
| `WuMindShortDramaView` | `.sheet(isPresented: Binding(` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindShortDramaView.swift#L75) |
| `WuMindShortDramaView` | `.sheet(isPresented: $showingMultiPlatformPublish) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindShortDramaView.swift#L83) |
| `WuMindShortDramaAPISheet` | `.sheet(item: $configuringProvider) { provider in` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindShortDramaView.swift#L1359) |
| `WuMindSpatial3DStudioView` | `.sheet(isPresented: $showingWorksHistory) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindSpatial3DStudioView.swift#L140) |
| `WuMindSpatial3DStudioView` | `.sheet(isPresented: $showingProjectLibrary) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindSpatial3DStudioView.swift#L148) |
| `WuMindSpatial3DStudioView` | `.sheet(isPresented: $showingTechRegistry) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindSpatial3DStudioView.swift#L157) |
| `WuMindSpatial3DStudioView` | `.sheet(isPresented: $showingTripoSheet) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindSpatial3DStudioView.swift#L160) |
| `WuMindSpatial3DStudioView` | `.fileExporter(` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindSpatial3DStudioView.swift#L163) |
| `WuMindSpatial3DStudioView` | `.fileImporter(` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindSpatial3DStudioView.swift#L177) |
| `WuMindSpatial3DStudioView` | `.fileImporter(` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindSpatial3DStudioView.swift#L184) |
| `WuMindSyncSheet` | `.accessibilityIdentifier("wumind.sync.sheet")` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindSyncSheet.swift#L48) |
| `WuMindWorkspaceView` | `.navigationDestination(for: ToolboxDestination.self) { dest in` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindView.swift#L478) |
| `WuMindWorkspaceView` | `.photosPicker(isPresented: $showingPhotoPicker, selection: $pickedPhotoItem, matching: .images)` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindView.swift#L500) |
| `WuMindWorkspaceView` | `.fileImporter(` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindView.swift#L507) |
| `WuMindWorkspaceView` | `.sheet(isPresented: $showingInChatConnectors) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindView.swift#L518) |
| `WuMindWorkspaceView` | `.fullScreenCover(isPresented: $showingCamera) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindView.swift#L566) |
| `WuMindWorkspaceView` | `.fullScreenCover(isPresented: $showingGeminiVoice) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindView.swift#L572) |
| `WuMindWorkspaceView` | `.fullScreenCover(isPresented: $showingRealtimeCall) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindView.swift#L580) |
| `WuMindWorkspaceView` | `.sheet(item: $comparingTurn) { turn in` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindView.swift#L585) |
| `WuMindWorkspaceView` | `.sheet(isPresented: $showingSharedMaterialsSheet) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindView.swift#L603) |
| `WuMindWorkspaceView` | `.sheet(isPresented: $showingModelHub, onDismiss: {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindView.swift#L610) |
| `WuMindWorkspaceView` | `.sheet(isPresented: $showingSkills) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindView.swift#L639) |
| `WuMindWorkspaceView` | `.sheet(isPresented: $showingProjects) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindView.swift#L647) |
| `WuMindWorkspaceView` | `.sheet(isPresented: $showingSchedules) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindView.swift#L650) |
| `WuMindWorkspaceView` | `.sheet(isPresented: $showingSettings) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindView.swift#L653) |
| `WuMindWorkspaceView` | `.sheet(isPresented: $showingSync) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindView.swift#L694) |
| `WuMindWorkspaceView` | `.sheet(isPresented: $showingGitHub) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindView.swift#L697) |
| `WuMindWorkspaceView` | `.sheet(isPresented: $showingWallet) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindView.swift#L700) |
| `WuMindWorkspaceView` | `.sheet(item: $showingKeyFor, onDismiss: {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindView.swift#L703) |
| `WuMindWorkspaceView` | `.fullScreenCover(isPresented: Binding(` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindView.swift#L735) |
| `WuMindWorkspaceView` | `.sheet(item: $chatBuildPreview) { work in` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindView.swift#L748) |
| `WuMindWorkspaceView` | `.sheet(isPresented: $showingMyWorks) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindView.swift#L778) |
| `WuMindWorkspaceView` | `.sheet(isPresented: $showingArchivedSheet) {` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindView.swift#L781) |
| `WuMindArchivedConversationsSheet` | `.accessibilityIdentifier("wumind.archived.sheet")` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindView.swift#L5512) |
| `WuMindWorkbenchView` | `.sheet(item: $selectedDetailWork) { work in` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindWorkbenchView.swift#L90) |
| `WuMindWorksView` | `.sheet(item: $activeWork) { work in` | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindWorksView.swift#L74) |

## 开发启动筛选

这些入口可以独立启动界面样例，有些依赖样例数据或编译选项。公开入口仍以页面台账和呈现声明为准。

| 目的视图 | -screen 名称 |
|---|---|
| `FairnessView` | `fairness` |
| `RosterPreviewView` | `preview` |
| `WeekRosterView` | `week` |
| `SwapHelperView` | `swap` |
| `SwapLedgerView` | `ledger` |
| `YearStatsView` | `year` |
| `YearSummaryView` | `summary` |
| `DataCheckView` | `check` |
| `RestTrendView` | `rest` |
| `DutyForecastView` | `forecast` |
| `WorkLogView` | `worklog` |
| `ManagerHomeView` | `manager` |
| `OnboardingView` | `onboarding` |
| `PeopleProfilesView` | `profiles` |
| `RosterLogView` | `rosterlog` |
| `RoleView` | `role` |
| `SchedulePatternsView` | `patterns` |
| `HolidaysView` | `holidays` |
| `WorkloadRulesView` | `rules` |
| `TeamChangesView` | `team` |
| `LeavePlannerView` | `leave` |
| `AutomationGuideView` | `automation` |
| `BackupView` | `backup` |
| `DiagnosticsView` | `diagnostics` |
| `MemberSearchView` | `search` |
| `DayEditor` | `day` |
| `DayRosterView` | `roster` |
| `HolidayDutyView` | `holidayduty` |
| `MeetingIssuesView` | `meeting`, `meetingEdit` |
| `MeetingSourceView` | `meetingSource` |
| `MeetingTrendView` | `meetingTrend` |
| `TodayLayoutView` | `todayLayout` |
| `MultiYearStatsView` | `years` |
| `PassPlanView` | `passPlan` |
| `PassPlanOperatorsView` | `passPlanOperators` |
| `RulesExplainView` | `rulesExplain` |
| `AllFeaturesView` | `allFeatures` |
| `GamesHomeView` | `game` |
| `DuelHomeView` | `fighter` |
| `TileGameHomeView` | `tiles` |
| `TileBoardView` | `gameBoard` |
| `ArenaHomeView` | `arena`, `arenaRangerComparison` |
| `ArenaRoomView` | `arenaRoomReady`, `arenaRoomWaiting` |
| `ArenaSampleReview` | `arenaSampleReview`, `arenaSampleMapReview` |
| `ArenaDiagnosticSuiteView` | `arenaDiagnostics` |
| `ArenaPlayView` | `arenaBenchmark`, `arenaSampleBenchmark`, `arenaHarborBenchmark`, `arenaPlay`, `arenaShowdown`, `arenaZone`, `arenaBall`, `arenaHeist`, `arenaBoss`, `arenaVersus`, `arenaResult` |
| `ArenaStoryView` | `arenaStory`, `arenaTalk` |
| `ArenaSeasonSheet` | `arenaSeason` |
| `WuMindAdminBillingView` | `wumindAdminBilling` |

## 其余具名视图

这些类型包括嵌入式界面及自绘组件。缺乏明确独立入口的类型保留在此供复查。

| 类型 | 宿主或最近调用方 | 定义 |
|---|---|---|
| `AppBackground` | OnboardingView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/Theme.swift#L158) |
| `AppEmptyStateCard` | PassPlanOperatorsView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindDesignComponents.swift#L294) |
| `AppErrorBannerCard` | GroundStationRuleEditorView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindDesignComponents.swift#L332) |
| `AppPrimaryCTA` | 未定位具名宿主 | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindDesignComponents.swift#L214) |
| `AppSaveToolbarButton` | GroundStationRuleEditorView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindDesignComponents.swift#L254) |
| `AppSectionCard` | 未定位具名宿主 | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindDesignComponents.swift#L164) |
| `ArenaCountUp` | ArenaMatchView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ArenaView.swift#L1143) |
| `ArenaDialogue` | ArenaStoryView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ArenaStoryView.swift#L369) |
| `ArenaFighterBadge` | ArenaMatchView, ArenaVersus | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ArenaFighterBadge.swift#L6) |
| `ArenaGadgetButton` | ArenaMatchView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ArenaView.swift#L1418) |
| `ArenaHeroSelection` | ArenaHomeView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ArenaHeroSelection.swift#L4) |
| `ArenaImportedLobbyBackground` | ArenaLobbyBackground | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ArenaImportedLobbyAssets.swift#L7) |
| `ArenaImportedMapThumb` | ArenaHomeView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ArenaLobby.swift#L2553) |
| `ArenaImportedMenuIcon` | 未定位具名宿主 | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ArenaImportedMenuArtwork.swift#L70) |
| `ArenaInterfaceIcon` | ArenaAudioSettingsView, ArenaHomeView, ArenaMenuScreen | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ArenaInterfaceAssets.swift#L33) |
| `ArenaInterfaceTexture` | ArenaMenuCard, ArenaMenuSlider, ArenaMenuToggle | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ArenaInterfaceAssets.swift#L44) |
| `ArenaLoadoutSection` | ArenaHomeView, ArenaRoomView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ArenaView.swift#L1457) |
| `ArenaLobbyBackdrop` | ArenaLobbyBackground | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ArenaLobbyArt.swift#L152) |
| `ArenaLobbyBackground` | ArenaGamePanel, ArenaHomeView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ArenaLobby.swift#L2113) |
| `ArenaLobbyIcon` | ArenaHomeView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ArenaLobbyArt.swift#L4) |
| `ArenaLobbyQuestCountdown` | ArenaHomeView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ArenaLobbyArt.swift#L307) |
| `ArenaMapThumb` | ArenaHomeView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ArenaLobby.swift#L2518) |
| `ArenaMatchDialog` | ArenaMatchView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ArenaView.swift#L1022) |
| `ArenaMenuCard` | 未定位具名宿主 | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ArenaMenuComponents.swift#L42) |
| `ArenaMenuSlider` | ArenaAudioSettingsView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ArenaMenuComponents.swift#L94) |
| `ArenaMenuToggle` | ArenaAudioSettingsView, ArenaHomeView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ArenaMenuComponents.swift#L75) |
| `ArenaShowcase` | ArenaHeroSelection, ArenaHomeView, ArenaSampleReview | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ArenaLobby.swift#L2144) |
| `ArenaSkinSection` | ArenaHomeView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ArenaSeasonView.swift#L356) |
| `ArenaSourceControlVisual` | ArenaHomeView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ArenaSourceControlVisual.swift#L6) |
| `ArenaStick` | ArenaMatchView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ArenaView.swift#L1302) |
| `ArenaTrophyRoad` | ArenaHomeView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ArenaView.swift#L5) |
| `ArenaVendorButtonFace` | 未定位具名宿主 | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ArenaVendorAssets.swift#L90) |
| `ArenaVendorIcon` | ArenaHeroSelection, ArenaMenuScreen, BrawlerBadge | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ArenaVendorAssets.swift#L79) |
| `ArenaVersus` | ArenaMatchView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ArenaView.swift#L1163) |
| `ArenaWorld` | ArenaMatchView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ArenaWorld.swift#L44) |
| `Avatar` | DayRosterView, DutyBurdenView, DutyForecastView, FavoritesCard, HolidayDutyView, MemberScheduleView, MemberSearchView, OnboardingView, PeopleProfilesView, RowView, SwapHelperView, SwapLedgerView, WhoAmIView, WorkloadView, YearStatsView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/Theme.swift#L700) |
| `BrawlerBadge` | ArenaDialogue, ArenaFighterBadge, ArenaHeroSelection, ArenaHomeView, ArenaRoomView, ArenaSeasonSheet, ArenaStoryView, ArenaTrophyRoad | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ArenaModels.swift#L344) |
| `BurstCameraPreviewLayer` | PassPlanBurstCameraView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/PassPlanBurstCameraView.swift#L478) |
| `CaptureWidget` | ShiftWidgetBundle | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/Widget/ShiftWidget.swift#L562) |
| `CardTitle` | FavoritesCard, GamesCard, MonthSummary, RecentChanges, TaskChecklistCard, UpcomingList, WuMindAgentWorkspaceView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/Theme.swift#L269) |
| `CharacterPortraitPickerButton` | WuMindShortDramaView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindShortDramaView.swift#L806) |
| `Chip` | DayRosterView, MemberScheduleView, PeopleProfilesView, Summary, TaskChecklistCard, WorkloadView, WuMindAgentWorkspaceView, YearStatsView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/Theme.swift#L317) |
| `ConfirmButton` | HolidaysView, PersonProfileView, RecentChanges, RotationMembersView, ShiftTypesView, SwapLedgerView, TeamChangesView, WorkloadRulesView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/Theme.swift#L985) |
| `CountUpText` | MonthStatCard | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/Theme.swift#L744) |
| `DSButtonBody` | 未定位具名宿主 | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/Theme.swift#L416) |
| `DSSpinner` | GroupNotesView, OnboardingView, PassPlanView, RoleView, SettingsView, SyncNowButton, SyncStatus, WhoAmIView, WorkloadView, YearStatsView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/Theme.swift#L491) |
| `DateHeader` | ManagerHomeView, TodayView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TodayView.swift#L169) |
| `DayCell` | CalendarView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/CalendarView.swift#L190) |
| `DraftTextField` | GroupNotesView, MeetingSourceView, SettingsView, ShiftTypeEditor | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/Theme.swift#L1055) |
| `DuelControls` | 未定位具名宿主 | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DuelView.swift#L2849) |
| `DuelDrainHealthBar` | DuelMatchContent | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DuelDrainHealthBar.swift#L33) |
| `DuelMatchContent` | DuelMatchView, DuelNetworkMatchContent, DuelOfflineMatchContent, DuelPreparingLocalMatch | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DuelView.swift#L1501) |
| `DuelNetworkBackdrop` | DuelNetworkEntryView, DuelNetworkLobbyContent, DuelNetworkRoomView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DuelNetworkRoomView.swift#L371) |
| `DuelNetworkControls` | DuelMatchContent | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DuelView.swift#L2697) |
| `DuelNetworkLobbyContent` | DuelNetworkRoomView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DuelNetworkRoomView.swift#L169) |
| `DuelNetworkMatchContent` | DuelMatchView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DuelView.swift#L1492) |
| `DuelOfflineMatchContent` | DuelMatchView, DuelPreparingOriginalMatch | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DuelView.swift#L1484) |
| `DuelPanguControlHUD` | DuelMatchContent, DuelTelevisionHUD | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DuelPanguHUD.swift#L58) |
| `DuelPanguHUD` | DuelMatchContent, DuelTelevisionHUD | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DuelPanguHUD.swift#L5) |
| `DuelPreparingLocalMatch` | DuelMatchView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DuelView.swift#L1429) |
| `DuelPreparingOriginalMatch` | DuelMatchView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DuelView.swift#L1341) |
| `DuelSlantedMeterBar` | DuelMatchContent | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DuelDrainHealthBar.swift#L180) |
| `DuelTelevisionHUD` | DuelTelevisionViewController | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DuelTelevision.swift#L182) |
| `DuelTriadControlHUD` | DuelMatchContent | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DuelTriadHUD.swift#L35) |
| `DuelTriadHUD` | DuelMatchContent | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DuelTriadHUD.swift#L3) |
| `DuelWeaponControls` | DuelMatchContent | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DuelView.swift#L2373) |
| `DuelWorld` | DuelMatchContent | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DuelWorld.swift#L29) |
| `DutyInsightCard` | TodayView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TodayView.swift#L776) |
| `DutyLiveActivity` | ShiftWidgetBundle | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/Widget/ShiftWidget.swift#L211) |
| `DutySecondaryBanner` | AllFeaturesView, AutomationGuideView, BackupView, DiagnosticsView, DutyHandoffView, PeopleProfilesView, RulesExplainView, SettingsView, SwapHelperView, TodayLayoutView, WuMindAgentWorkspaceView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/Theme.swift#L231) |
| `DutyWorkbenchCard` | TodayView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DutyWorkbenchView.swift#L7) |
| `EmptyScheduleHint` | TodayView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TodayView.swift#L724) |
| `EmptyState` | APIFieldsView, AllFeaturesView, DayRosterView, MemberScheduleView, RosterLogView, RosterPreviewView, WorkLogView, WuMindAgentWorkspaceView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/Theme.swift#L359) |
| `ExpandableText` | FairnessView, WorkloadView, YearStatsView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/Theme.swift#L635) |
| `FavoritesCard` | TodayView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TodayView.swift#L679) |
| `FloatingTabBar` | RootView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/Theme.swift#L800) |
| `FlowChips` | WorkloadView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WorkloadView.swift#L239) |
| `GameRoomButtons` | GomokuHomeView, TileGameHomeView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/GamesHomeView.swift#L113) |
| `GamesCard` | 未定位具名宿主 | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TodayView.swift#L401) |
| `GomokuBoard` | GomokuLocalScreen, GomokuRoomScreen, GomokuTurnScreen | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/GomokuView.swift#L174) |
| `GomokuFrame` | GomokuLocalScreen, GomokuRoomScreen | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/GomokuView.swift#L298) |
| `GomokuHeader` | GomokuLocalScreen, GomokuRoomScreen, GomokuTurnScreen | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/GomokuView.swift#L255) |
| `GroupAttendanceSection` | WorkloadView, YearStatsView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WorkloadView.swift#L424) |
| `IconBadge` | AllFeaturesView, CardTitle, DayRosterView, DutyInsightCard, DutySecondaryBanner, EmptyState, GamesCard, GamesHomeView, ManagerHomeView, OnboardingView, QuickActions, SettingsView, TodayLayoutView, ToolGrid, WhatsNewView, WorkLogCard, WorkLogRow, WorkloadView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/Theme.swift#L293) |
| `ImageStudioLightbox` | AIImageToolView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/AIImageToolView.swift#L2781) |
| `JourneyChapterStrip` | StarJourneyHomeView, TileGameHomeView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/StarJourneyView.swift#L119) |
| `MeetingCard` | TodayView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/MeetingViews.swift#L37) |
| `MonthStatCard` | TodayView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TodayView.swift#L350) |
| `MonthSummary` | CalendarView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/CalendarView.swift#L244) |
| `NextDutyWidget` | ShiftWidgetBundle | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/Widget/ShiftWidget.swift#L398) |
| `NoticeChangeCard` | TodayView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TodayView.swift#L622) |
| `PeriodPager` | FairnessView, WeekRosterView, WorkloadView, YearStatsView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/Theme.swift#L1005) |
| `QuickActions` | TodayView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TodayView.swift#L462) |
| `RailBoardBackdrop` | StarRailCanvas | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/StarRailArtwork.swift#L59) |
| `RailBrandMark` | StarCollectionView, StarExpeditionDailyCard, StarExpeditionHomeView, StarJourneyHomeView, StarJourneyRewardView, StarRailBoardView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/StarRailCosmetics.swift#L37) |
| `RailCardBack` | RailTileFace, StarCollectionView, StarJourneyRewardView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/StarRailCosmetics.swift#L63) |
| `RailEnergyMeter` | StarRailBoardView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/StarRailArtwork.swift#L86) |
| `RailHomeArtwork` | StarRailHomeView, TileGameHomeView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/StarRailArtwork.swift#L105) |
| `RailSkyBackdrop` | StarCollectionView, StarExpeditionHomeView, StarJourneyHomeView, StarJourneyRewardView, StarRailBoardView, StarRailHomeView, StarRailReplayView, StarTrialHomeView, TileGameHomeView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/StarRailCosmetics.swift#L16) |
| `RailStarCoreFace` | StarRailBoardView, StarRailCanvas | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/StarRailCanvas.swift#L86) |
| `RailTileFace` | RailHomeArtwork, StarCollectionView, StarRailCanvas | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/StarRailArtwork.swift#L14) |
| `ReadOnlyNotice` | BackupView, PeopleProfilesView, PersonProfileView, WorkloadRulesView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/Theme.swift#L912) |
| `RecentChanges` | TodayView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TodayView.swift#L649) |
| `RestStepsSection` | RestTrendView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ToolsViews.swift#L516) |
| `SectionLabel` | 未定位具名宿主 | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/Theme.swift#L349) |
| `ShiftLabel` | ImportView, UpcomingList | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/ShiftStyle.swift#L52) |
| `ShiftWidgetBundle` | 未定位具名宿主 | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/Widget/ShiftWidget.swift#L195) |
| `SkeletonBlock` | SkeletonRows | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/Theme.swift#L759) |
| `SkeletonRows` | DataCheckView, RosterPreviewView, SchedulePatternsView, YearStatsView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/Theme.swift#L780) |
| `StaleSyncBanner` | 未定位具名宿主 | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TodayView.swift#L553) |
| `StarConstellationMap` | StarCollectionView, StarJourneyRewardView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/StarCollectionView.swift#L66) |
| `StarExpeditionDailyCard` | TileGameHomeView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/StarExpeditionView.swift#L3) |
| `StarRailCanvas` | StarRailBoardView, StarRailReplayView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/StarRailCanvas.swift#L5) |
| `StarRailTray` | StarRailBoardView, StarRailReplayView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/StarRailView.swift#L599) |
| `StarTrialDailyCard` | StarTrialHomeView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/StarTrialView.swift#L8) |
| `StatTile` | 未定位具名宿主 | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/Theme.swift#L335) |
| `StudioShimmerCard` | AIImageToolView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/AIImageToolView.swift#L2716) |
| `Summary` | FairnessView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/FairnessView.swift#L134) |
| `SyncNowButton` | EmptyScheduleHint, MemberSearchView, SchedulePatternsView, SiteNoticesView, SwapHelperView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/Theme.swift#L378) |
| `SyncStatus` | ManagerHomeView, TodayView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TodayView.swift#L739) |
| `SystemBroadcastButton` | WuMindAgentWorkspaceView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindAgentWorkspaceView.swift#L739) |
| `TabRootNavigationDepthSpy` | 未定位具名宿主 | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindDesignComponents.swift#L74) |
| `TaskChecklistCard` | DutyChecklistView, TodayView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/MoreViews.swift#L6) |
| `TaskRecordRow` | WorkLogView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WorkLogView.swift#L314) |
| `TeamDutyWidget` | ShiftWidgetBundle | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/Widget/ShiftWidget.swift#L689) |
| `TenderPDFSourceViewer` | DeepSeekTenderView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DeepSeekTenderView.swift#L738) |
| `TenderWordSourceViewer` | DeepSeekTenderView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DeepSeekTenderView.swift#L765) |
| `TileFace` | TileBoardView, TileReplayView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TileArtwork.swift#L167) |
| `TileGlyph` | RailTileFace, StarRailBoardView, StarRailTray, StarTrialDailyCard, TileFace, TileGameHomeView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TileArtwork.swift#L45) |
| `TileRaceStandings` | TileBoardView, TileRaceLobbyView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TileGameView.swift#L268) |
| `TileStarfield` | TileBoardView, TileReplayView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TileArtwork.swift#L22) |
| `TileStars` | StarExpeditionDailyCard, StarExpeditionHomeView, StarRailBoardView, StarRailHomeView, StarTrialHomeView, TileBoardView, TileGameHomeView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TileArtwork.swift#L193) |
| `ToastOverlay` | RootView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/Theme.swift#L538) |
| `TodayDutyLine` | 未定位具名宿主 | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TodayView.swift#L594) |
| `TodayHero` | TodayView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TodayView.swift#L196) |
| `ToolGrid` | WorkloadView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/Theme.swift#L658) |
| `UpcomingList` | TodayView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TodayView.swift#L507) |
| `WeekStrip` | TodayView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/TodayView.swift#L302) |
| `WeekTable` | WeekRosterView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/MoreViews.swift#L118) |
| `WeekWidget` | ShiftWidgetBundle | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/Widget/ShiftWidget.swift#L312) |
| `WorkLogCard` | TodayView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WorkLogView.swift#L7) |
| `WorkLogRow` | DayEditor, WorkLogView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WorkLogView.swift#L364) |
| `WorkPresentPair` | RowView, WorkloadView, YearStatsView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/Theme.swift#L887) |
| `WorkloadBarChart` | Summary, WorkloadView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/InsightViews.swift#L348) |
| `WorkspaceLauncherCard` | WorkspaceLauncherHomeView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WorkspaceLauncherHomeView.swift#L61) |
| `WorkspaceOrbitalOverlay` | WorkspaceLauncherCard | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WorkspaceLauncherHomeView.swift#L187) |
| `WuMindAdminUpstreamBalanceSection` | WuMindAdminGatewayDiagnosticsPage | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindAdminBillingSections.swift#L6) |
| `WuMindAgentTraceCard` | WuMindTurnView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindFlagshipHubViews.swift#L2012) |
| `WuMindChatVideoStage` | WuMindWorkspaceView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/AIVideoToolView.swift#L1470) |
| `WuMindComposerActionButtons` | WuMindIsolatedComposerBar | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindComposerSubviews.swift#L320) |
| `WuMindComposerAttachmentsStrip` | WuMindIsolatedComposerBar | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindComposerSubviews.swift#L8) |
| `WuMindComposerTextInput` | WuMindIsolatedComposerBar | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindComposerSubviews.swift#L296) |
| `WuMindHubHeroBanner` | AICodeWorkToolsView, AIHubMixConnectionSheet, AIProviderListView, AISpeechToolView, ExternalAuthView, WuMindAdminSetupGuideSheet, WuMindGitHubSheet, WuMindModelHubSheet, WuMindProjectsSheet, WuMindRechargeGuideSheet, WuMindSchedulesSheet, WuMindSettingsSheet, WuMindSyncSheet | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindHubComponents.swift#L7) |
| `WuMindIconBadge` | AICodeWorkToolsView, WuMindModelHubSheet, WuMindProjectsSheet, WuMindSchedulesSheet, WuMindSettingsSheet | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindHubComponents.swift#L72) |
| `WuMindInlineBuildCard` | WuMindWorkspaceView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindInlineBuildCard.swift#L6) |
| `WuMindInlineStatusRow` | WuMindTurnView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindComposerSubviews.swift#L693) |
| `WuMindIsolatedComposerBar` | WuMindWorkspaceView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindView.swift#L2649) |
| `WuMindScrollFollower` | WuMindWorkspaceView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindView.swift#L2773) |
| `WuMindStagePlayerSurface` | WuMindVideoGenerationStage | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/AIVideoToolView.swift#L1495) |
| `WuMindTurnCitationsSection` | WuMindTurnView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/WuMindComposerSubviews.swift#L752) |
| `WuMindVideoGenerationStage` | AIVideoToolView, WuMindChatVideoStage, WuMindWorkspaceView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/AIVideoToolView.swift#L1281) |
| `XuXiaoPracticeHold` | DuelXuXiaoPracticeView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/DuelXuXiaoPracticeView.swift#L182) |
| `YearSummaryCard` | YearSummaryView | [源码](https://github.com/wuyong9494-lab/kriswu/blob/b09b95f891878aef34cba913c07cece40ddb2846/App/Views/InsightViews.swift#L233) |
