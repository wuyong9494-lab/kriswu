// swift-tools-version:5.9
import PackageDescription

// ShiftCore 是与平台无关的核心逻辑（解析排班表、识别班次、计算提醒），
// 可以在 Linux / macOS 上直接 `swift test`。iOS App 直接编译这些源文件。
let package = Package(
    name: "ShiftCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "ShiftCore", targets: ["ShiftCore"]),
    ],
    targets: [
        // 完整的并发检查（Swift 5 模式下是警告）：多个线程同时读写同一份数据的地方会被指出来
        .target(name: "ShiftCore", swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]),
        .testTarget(name: "ShiftCoreTests", dependencies: ["ShiftCore"]),
    ]
)
