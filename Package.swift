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
        .target(name: "ShiftCore"),
        .testTarget(name: "ShiftCoreTests", dependencies: ["ShiftCore"]),
    ]
)
