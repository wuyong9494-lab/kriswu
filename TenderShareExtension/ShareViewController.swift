import UIKit
import UniformTypeIdentifiers

/// A user-confirmed, on-device handoff. No network connection and no attempt
/// to launch the containing app from the extension.
final class ShareViewController: UIViewController {
    private enum Supply {
        case typed(identifier: String, ext: String)
        case fileURL
        case data(identifier: String)
    }

    private struct Candidate {
        let provider: NSItemProvider
        let supply: Supply
        let suggestedName: String?
    }

    private enum HandoffFailure: LocalizedError {
        case unsupported
        var errorDescription: String? { "未能读取 PDF / DOCX 文件，请在微信里先打开文件本身，再尝试分享。" }
    }

    private let heading = UILabel()
    private let information = UILabel()
    private let status = UILabel()
    private let saveButton = UIButton(type: .system)
    private let dismissButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var candidate: Candidate?
    private var saving = false
    private var saved = false

    override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = CGSize(width: 450, height: 330)
        view.backgroundColor = .systemBackground
        buildInterface()

        let allProviders = (extensionContext?.inputItems ?? []).compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] }
        let candidates = allProviders.compactMap(Self.admit)
        if candidates.count == 1, let found = candidates.first {
            candidate = found
            if let name = found.suggestedName {
                status.text = "待接收：\(String(name.prefix(160)))"
            }
        } else {
            status.text = candidates.isEmpty
                ? "没有可接收的文件。请分享一份 PDF 或 DOCX 招标文件，不要分享网页、聊天消息或旧版 .doc。"
                : "一次只能接收一份文件。请返回微信，只选一份 PDF 或 DOCX 再分享。"
            saveButton.isEnabled = false
        }
    }

    private func buildInterface() {
        heading.text = "值班提醒 · 招标收件箱"
        heading.font = UIFont.preferredFont(forTextStyle: .title2)
        heading.adjustsFontForContentSizeCategory = true
        heading.numberOfLines = 0
        information.text = "接收后只保存在本机，不会上传 DeepSeek。回到值班提醒，进「DeepSeek → 生成投标书草稿」选择即可。"
        information.font = UIFont.preferredFont(forTextStyle: .body)
        information.adjustsFontForContentSizeCategory = true
        information.numberOfLines = 0
        status.font = UIFont.preferredFont(forTextStyle: .footnote)
        status.textColor = .secondaryLabel
        status.adjustsFontForContentSizeCategory = true
        status.numberOfLines = 0
        spinner.hidesWhenStopped = true

        var saveConfiguration = UIButton.Configuration.filled()
        saveConfiguration.title = "接收到本机收件箱"
        saveButton.configuration = saveConfiguration
        saveButton.addTarget(self, action: #selector(save), for: .touchUpInside)
        dismissButton.setTitle("取消", for: .normal)
        dismissButton.addTarget(self, action: #selector(finish), for: .touchUpInside)

        let row = UIStackView(arrangedSubviews: [dismissButton, saveButton, spinner])
        row.axis = .horizontal
        row.alignment = .center
        row.distribution = .equalSpacing
        row.spacing = 12

        let stack = UIStackView(arrangedSubviews: [heading, information, status, row])
        stack.axis = .vertical
        stack.spacing = 16
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        view.addSubview(scroll)
        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: safe.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: safe.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -20),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -40),
        ])
    }

    private static func admit(_ provider: NSItemProvider) -> Candidate? {
        let name = provider.suggestedName
        let docx = UTType(filenameExtension: "docx")
            ?? UTType(importedAs: "org.openxmlformats.wordprocessingml.document", conformingTo: .data)
        for (type, ext) in [(UTType.pdf, "pdf"), (docx, "docx")] {
            if let declared = provider.registeredTypeIdentifiers.first(where: {
                UTType($0)?.conforms(to: type) == true || $0 == type.identifier
            }) {
                return Candidate(provider: provider, supply: .typed(identifier: declared, ext: ext), suggestedName: name)
            }
        }
        // WeChat can advertise a local file URL or bytes without its precise UTI.
        // Generic bytes are allowed only with a .pdf/.docx filename hint.
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            return Candidate(provider: provider, supply: .fileURL, suggestedName: name)
        }
        if let name, Self.supportedExtension(name) != nil,
           let binary = provider.registeredTypeIdentifiers.first(where: {
               UTType($0)?.conforms(to: .data) == true && UTType($0)?.conforms(to: .url) != true
           }) {
            return Candidate(provider: provider, supply: .data(identifier: binary), suggestedName: name)
        }
        return nil
    }

    @objc private func save() {
        guard let candidate, !saving, !saved else { return }
        saving = true
        dismissButton.isEnabled = false
        saveButton.isEnabled = false
        spinner.startAnimating()
        status.text = "正在读取并校验文件…"

        let provider = candidate.provider
        let suggested = candidate.suggestedName
        let finish: @Sendable (Result<String, Error>) -> Void = { [weak self] result in
            Task { @MainActor in self?.received(result) }
        }
        switch candidate.supply {
        case .typed(let identifier, let ext):
            Self.loadRepresentation(provider, identifier: identifier, suggested: suggested, expectedExtension: ext,
                                    completion: finish)
        case .fileURL:
            Self.loadItem(provider, identifier: UTType.fileURL.identifier, suggested: suggested,
                          expectedExtension: nil, completion: finish)
        case .data(let identifier):
            Self.loadRepresentation(provider, identifier: identifier, suggested: suggested, expectedExtension: nil,
                                    completion: finish)
        }
    }

    private func received(_ result: Result<String, Error>) {
        saving = false
        dismissButton.isEnabled = true
        spinner.stopAnimating()
        switch result {
        case .success(let name):
            saved = true
            saveButton.isHidden = true
            dismissButton.setTitle("完成", for: .normal)
            heading.text = "已接收到本机收件箱"
            status.text = "「\(name)」已保存。点完成后，打开值班提醒 → DeepSeek → 生成投标书草稿。"
        case .failure(let failure):
            saveButton.isEnabled = true
            let safeMessage = (failure as? TenderShareInbox.Failure)?.errorDescription
                ?? (failure as? HandoffFailure)?.errorDescription
                ?? "文件须是可读取的 PDF 或 DOCX，最大 16 MB。请在微信里打开文件后重试。"
            status.text = "没有保存：\(safeMessage)"
        }
    }

    @objc private func finish() {
        guard !saving else { return }
        if saved {
            extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        } else {
            extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
        }
    }

    private nonisolated static func supportedExtension(_ name: String) -> String? {
        let ext = (name as NSString).pathExtension.lowercased()
        return ["pdf", "docx"].contains(ext) ? ext : nil
    }

    private nonisolated static func preferredName(suggested: String?, file: URL?, expectedExtension: String?) throws -> String {
        if let suggested, let ext = supportedExtension(suggested), expectedExtension == nil || expectedExtension == ext {
            return suggested
        }
        if let suggested, let expectedExtension,
           !(suggested as NSString).lastPathComponent.isEmpty, (suggested as NSString).pathExtension.isEmpty {
            return suggested + "." + expectedExtension
        }
        if let filename = file?.lastPathComponent, let ext = supportedExtension(filename),
           expectedExtension == nil || expectedExtension == ext {
            return filename
        }
        if let expectedExtension { return "招标文件." + expectedExtension }
        throw HandoffFailure.unsupported
    }

    private nonisolated static func saveFile(_ file: URL, name: String) throws -> String {
        guard file.isFileURL else { throw HandoffFailure.unsupported }
        let scoped = file.startAccessingSecurityScopedResource()
        defer { if scoped { file.stopAccessingSecurityScopedResource() } }
        return try TenderShareInbox.appGroup().save(fileURL: file, filename: name).filename
    }

    private nonisolated static func loadRepresentation(_ provider: NSItemProvider, identifier: String,
                                                        suggested: String?, expectedExtension: String?,
                                                        completion: @escaping @Sendable (Result<String, Error>) -> Void) {
        provider.loadFileRepresentation(forTypeIdentifier: identifier) { file, _ in
            if let file {
                // NSItemProvider may remove this URL when this callback returns;
                // do the bounded read and the shared-container copy right here.
                completion(Result {
                    let name = try preferredName(suggested: suggested, file: file, expectedExtension: expectedExtension)
                    return try saveFile(file, name: name)
                })
            } else {
                loadItem(provider, identifier: identifier, suggested: suggested, expectedExtension: expectedExtension,
                         completion: completion)
            }
        }
    }

    private nonisolated static func loadItem(_ provider: NSItemProvider, identifier: String,
                                             suggested: String?, expectedExtension: String?,
                                             completion: @escaping @Sendable (Result<String, Error>) -> Void) {
        provider.loadItem(forTypeIdentifier: identifier, options: nil) { object, _ in
            completion(Result {
                if let file = object as? URL, file.isFileURL {
                    let name = try preferredName(suggested: suggested, file: file, expectedExtension: expectedExtension)
                    return try saveFile(file, name: name)
                }
                guard let bytes = object as? Data else { throw HandoffFailure.unsupported }
                if identifier == UTType.fileURL.identifier {
                    // Some hosts supply a URL's data representation instead of NSURL.
                    guard bytes.count <= 8_192, let file = URL(dataRepresentation: bytes, relativeTo: nil), file.isFileURL else {
                        throw HandoffFailure.unsupported
                    }
                    let name = try preferredName(suggested: suggested, file: file, expectedExtension: expectedExtension)
                    return try saveFile(file, name: name)
                }
                let name = try preferredName(suggested: suggested, file: nil, expectedExtension: expectedExtension)
                return try TenderShareInbox.appGroup().save(data: bytes, filename: name).filename
            })
        }
    }
}
