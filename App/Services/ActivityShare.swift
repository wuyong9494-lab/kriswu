import UIKit

/// 系统分享面板（发到微信等）：和 ShareLink 不同，能知道是不是真的发出去了
enum ActivityShare {
    @MainActor
    static func present(_ items: [Any], completion: @escaping @MainActor (Bool) -> Void) {
        guard let root = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController }).first else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in
            Task { @MainActor in completion(completed) }
        }
        // iPad 上从屏幕中间弹出
        if let popover = controller.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        top.present(controller, animated: true)
    }
}
