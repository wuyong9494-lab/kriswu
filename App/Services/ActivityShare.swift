import LinkPresentation
import UIKit

/// 系统分享面板（发到微信等）：回报所选分享操作是否完成，不提供收件人送达回执。
enum ActivityShare {
    /// 只往微信这类聊天 App 发：面板里去掉用不上的（隔空投送、信息、邮件、打印……），微信就挪到 App 那一排前面
    @MainActor
    static var chatOnly: [UIActivity.ActivityType] {
        [.airDrop, .message, .mail, .print, .assignToContact, .addToReadingList, .openInIBooks, .markupAsPDF]
    }

    /// 这些操作只在本机保存或处理内容，完成后不能给运营商记「已发」。
    /// 不对白名单外的第三方分享 App 作限制，保留微信等扩展的兼容性。
    @MainActor
    private static var localActivities: [UIActivity.ActivityType] {
        [.copyToPasteboard, .saveToCameraRoll, .print, .assignToContact,
         .addToReadingList, .openInIBooks, .markupAsPDF]
    }

    @MainActor
    private final class Completion {
        private var gate = ShareCompletionGate()
        private let callback: @MainActor (Bool) -> Void

        init(_ callback: @escaping @MainActor (Bool) -> Void) { self.callback = callback }

        func finish(activity: ShareCompletionGate.Activity = .none,
                    completed: Bool = false, hasError: Bool = false) {
            guard let result = gate.finish(activity: activity, completed: completed, hasError: hasError) else { return }
            callback(result)
        }
    }

    /// 连着发的时候，上一个面板（和微信的发送窗口）可能还没收完：等它收完再弹，不然弹不出来。
    /// 等了几秒还收不完、或者弹不出来，就当没发（completion(false)），调用的地方好提示停在哪
    @MainActor
    static func present(_ items: [Any], excluding excluded: [UIActivity.ActivityType] = [],
                        completion: @escaping @MainActor (Bool) -> Void) {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.excludedActivityTypes = excluded
        let result = Completion(completion)
        let localIdentifiers = Set(localActivities.map(\.rawValue))
        controller.completionWithItemsHandler = { type, completed, _, error in
            let activity: ShareCompletionGate.Activity = type.map {
                localIdentifiers.contains($0.rawValue) ? .local : .externalOrUnknown
            } ?? .none
            let hasError = error != nil
            Task { @MainActor in result.finish(activity: activity, completed: completed, hasError: hasError) }
        }
        Task { @MainActor in
            var waited = 0
            while isBusy, waited < 50 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                waited += 1
            }
            guard !isBusy, let top = topController() else { result.finish(); return }
            // iPad 上从屏幕中间弹出
            if let popover = controller.popoverPresentationController {
                popover.sourceView = top.view
                popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
                popover.permittedArrowDirections = []
            }
            top.present(controller, animated: true)
            if controller.presentingViewController == nil { result.finish() }
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
