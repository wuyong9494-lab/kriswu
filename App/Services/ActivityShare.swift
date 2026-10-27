import LinkPresentation
import UIKit

/// 系统分享面板（发到微信等）：和 ShareLink 不同，能知道是不是真的发出去了
enum ActivityShare {
    /// 只往微信这类聊天 App 发：面板里去掉用不上的（隔空投送、信息、邮件、打印……），微信就挪到 App 那一排前面
    @MainActor
    static var chatOnly: [UIActivity.ActivityType] {
        [.airDrop, .message, .mail, .print, .assignToContact, .addToReadingList, .openInIBooks, .markupAsPDF]
    }

    /// 连着发的时候，上一个面板（和微信的发送窗口）可能还没收完：等它收完再弹，不然弹不出来。
    /// 等了几秒还收不完、或者弹不出来，就当没发（completion(false)），调用的地方好提示停在哪
    @MainActor
    static func present(_ items: [Any], excluding excluded: [UIActivity.ActivityType] = [],
                        completion: @escaping @MainActor (Bool) -> Void) {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.excludedActivityTypes = excluded
        controller.completionWithItemsHandler = { _, completed, _, _ in
            Task { @MainActor in completion(completed) }
        }
        Task { @MainActor in
            var waited = 0
            while isBusy, waited < 50 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                waited += 1
            }
            guard !isBusy, let top = topController() else { completion(false); return }
            // iPad 上从屏幕中间弹出
            if let popover = controller.popoverPresentationController {
                popover.sourceView = top.view
                popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
                popover.permittedArrowDirections = []
            }
            top.present(controller, animated: true)
            if controller.presentingViewController == nil { completion(false) }
        }
    }

    @MainActor
    private static var rootController: UIViewController? {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }.first
    }

    /// 最上面那一层（分享面板从它上面弹出来）
    @MainActor
    private static func topController() -> UIViewController? {
        guard var top = rootController else { return nil }
        while let presented = top.presentedViewController { top = presented }
        return top
    }

    /// 还有分享面板开着，或者有一层正在弹出、收起
    @MainActor
    private static var isBusy: Bool {
        var current = rootController
        while let controller = current {
            if controller is UIActivityViewController || controller.isBeingPresented || controller.isBeingDismissed { return true }
            current = controller.presentedViewController
        }
        return false
    }
}

/// 分享面板最上面显示的标题（「甲站数传计划 → 发到 XX 群」），连着发几家时一眼看出这次发给谁。
/// 分享面板在主线程问这些（@preconcurrency：按主线程的代码对待）
@MainActor
final class SharePayload: NSObject, @preconcurrency UIActivityItemSource {
    let item: Any
    let title: String
    let preview: UIImage?

    init(_ item: Any, title: String, preview: UIImage? = nil) {
        self.item = item
        self.title = title
        self.preview = preview
    }

    func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any { item }

    func activityViewController(_ controller: UIActivityViewController, itemForActivityType type: UIActivity.ActivityType?) -> Any? { item }

    func activityViewControllerLinkMetadata(_ controller: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = title
        if let preview {
            metadata.iconProvider = NSItemProvider(object: preview)
            metadata.imageProvider = NSItemProvider(object: preview)
        }
        return metadata
    }
}
