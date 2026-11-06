// swift-tools-version:5.9
import PackageDescription

// ShiftCore 是与平台无关的核心逻辑（解析排班表、识别班次、计算提醒），
// 可以在 Linux / macOS 上直接 `swift test`。iOS App 直接编译这些源文件。
let package = Package(
    name: "ShiftCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "ShiftCore", targets: ["ShiftCore"]),
        .executable(name: "StarRailAudit", targets: ["StarRailAudit"]),
        .executable(name: "StarExpeditionAudit", targets: ["StarExpeditionAudit"]),
        .executable(name: "StarJourneyAudit", targets: ["StarJourneyAudit"]),
    ],
    targets: [
        // 完整的并发检查（Swift 5 模式下是警告）：多个线程同时读写同一份数据的地方会被指出来
        .target(name: "ShiftCore", swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]),
        .executableTarget(name: "StarRailAudit", dependencies: ["ShiftCore"], path: "Tools/StarRailAudit"),
        .executableTarget(name: "StarExpeditionAudit", dependencies: ["ShiftCore"], path: "Tools/StarExpeditionAudit"),
        .executableTarget(name: "StarJourneyAudit", dependencies: ["ShiftCore"], path: "Tools/StarJourneyAudit"),
        .testTarget(name: "ShiftCoreTests", dependencies: ["ShiftCore"]),
    ]
)
