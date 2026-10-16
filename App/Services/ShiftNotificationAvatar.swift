import Intents
import UIKit
import UserNotifications

/// 通知左边的大图显示这天的班（和 App 图标一个样子：渐变底、白色大字，组B 就是 B）。
/// iPhone 只许 App 在屏幕上时换图标：早上 App 还没打开过时，推送用的还是上次打开时的图标（比如前几天的 C）。
/// 按「通讯通知」的样子发，左边的大图就是这天的班，App 图标缩在角上。
/// 没有这项权限（侧载版）或系统不支持时，照常发普通通知。
@MainActor
enum ShiftNotificationAvatar {
    /// 这批通知在系统里登记的记录（每次重排提醒先删掉旧的，免得越积越多）
    static let groupID = "shift-avatar"

    /// 图标名 → 显示的字和上下两种颜色（和 scripts/make_icon.py 生成的 App 图标一致）
    static func glyph(for icon: String?) -> (text: String, top: UIColor, bottom: UIColor) {
        func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> UIColor { UIColor(red: r / 255, green: g / 255, blue: b / 255, alpha: 1) }
        let blue = (rgb(70, 150, 255), rgb(48, 44, 190))
        switch icon {
        case "IconDuty": return ("遥", rgb(118, 92, 230), rgb(34, 22, 110))
        case "IconDispatch": return ("调", rgb(255, 170, 60), rgb(226, 96, 30))
        case "IconTrip": return ("差", rgb(60, 200, 210), rgb(20, 110, 150))
        case "IconRest": return ("休", rgb(76, 217, 120), rgb(24, 140, 80))
        case let name? where name.hasPrefix("Icon") && name.count == 5: return (String(name.suffix(1)), blue.0, blue.1)
        default: return ("值", blue.0, blue.1)
        }
    }

    private static var cache: [String: Data] = [:]

    static func image(for icon: String?) -> Data? {
        let key = icon ?? "default"
        if let data = cache[key] { return data }
        let g = glyph(for: icon)
        let size = CGSize(width: 240, height: 240)
        let picture = UIGraphicsImageRenderer(size: size).image { ctx in
            let colors = [g.top.cgColor, g.bottom.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                ctx.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }
            let ascii = g.text.unicodeScalars.allSatisfy(\.isASCII)
            let text = NSAttributedString(string: g.text, attributes: [
                .font: UIFont.systemFont(ofSize: ascii ? 150 : 128, weight: .heavy),
                .foregroundColor: UIColor.white,
            ])
            let box = text.size()
            text.draw(at: CGPoint(x: (size.width - box.width) / 2, y: (size.height - box.height) / 2))
        }
        let data = picture.pngData()
        cache[key] = data
        return data
    }

    /// 重排提醒前清掉上一批登记的记录
    static func clearDonations() async {
        try? await INInteraction.delete(with: groupID)
    }

    /// 把通知改成「这天的班」发来的样子（左边大图是这天的班）；不行就原样返回。
    /// 通讯通知把发送人的名字当标题显示，所以名字就用原来的标题
    static func apply(to content: UNMutableNotificationContent, icon: String?) async -> UNNotificationContent {
        guard let data = image(for: icon) else { return content }
        let picture = INImage(imageData: data)
        let sender = INPerson(personHandle: INPersonHandle(value: "shift-\(icon ?? "default")", type: .unknown),
                              nameComponents: nil, displayName: content.title, image: picture,
                              contactIdentifier: nil, customIdentifier: nil)
        let intent = INSendMessageIntent(recipients: nil, outgoingMessageType: .outgoingMessageText, content: content.body,
                                         speakableGroupName: nil, conversationIdentifier: content.threadIdentifier,
                                         serviceName: nil, sender: sender, attachments: nil)
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .incoming
        interaction.groupIdentifier = groupID
        try? await interaction.donate()
        return (try? content.updating(from: intent)) ?? content
    }
}
