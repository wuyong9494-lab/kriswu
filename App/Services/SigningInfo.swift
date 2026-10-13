import Foundation

/// 读取 App 自带的签名描述文件（SideStore / AltStore / Xcode 安装时会放进 App 里），得到签名到期时间。
/// 免费 Apple ID 签名 7 天到期，到期后 App 打不开，要在 SideStore 里点「Refresh All」续签。
enum SigningInfo {
    static let expirationDate: Date? = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex) else { return nil }
        let plist = try? PropertyListSerialization.propertyList(from: data.subdata(in: start.lowerBound..<end.upperBound),
                                                                 format: nil) as? [String: Any]
        return plist?["ExpirationDate"] as? Date
    }()

    /// 还剩几天（不足一天算 0）。
    static var daysLeft: Int? {
        expirationDate.map { max(0, Int($0.timeIntervalSinceNow / 86_400)) }
    }

    static var expiryText: String {
        guard let date = expirationDate else { return "未知（不是 SideStore 安装的）" }
        return date.formatted(date: .abbreviated, time: .shortened) + "（还剩 \(daysLeft ?? 0) 天）"
    }
}
