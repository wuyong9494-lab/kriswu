import SwiftUI
import UIKit

struct DeepSeekPlanKeyView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var configured = false
    @State private var failure: String?

    private var trimmed: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField(configured ? "已保存，输入新的可替换" : "输入 DeepSeek API Key", text: $draft)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button("保存到本机") { save() }
                        .disabled(trimmed.isEmpty)
                    if configured {
                        Button("移除本机 Key", role: .destructive) {
                            if Keychain.setDeepSeekPlanAPIKey("") {
                                configured = false
                                draft = ""
                                failure = nil
                            } else {
                                failure = "未能移除 Key。请解锁设备后重试。"
                            }
                        }
                    }
                    if let failure {
                        Text(failure).foregroundStyle(DS.Palette.danger)
                    }
                } footer: {
                    Text("Key 保存在这台设备的系统钥匙串，不会同步或迁移到其他设备。保存不会联网，也不会扣费。")
                }
            }
            .navigationTitle("DeepSeek API Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear { configured = !(Keychain.get(.deepSeekPlanAPIKey) ?? "").isEmpty }
        }
    }

    private func save() {
        let value = trimmed
        guard !value.isEmpty, value.utf8.count <= 512, value.utf8.allSatisfy({ (33...126).contains($0) }) else {
            failure = "Key 格式不正确。请只粘贴 API Key，不要带换行或空格。"
            return
        }
        guard Keychain.setDeepSeekPlanAPIKey(value) else {
            failure = "未能保存 Key。请解锁设备后重试。"
            return
        }
        draft = ""
        dismiss()
    }
}

enum DeepSeekPlanPhoto {
    enum Failure: LocalizedError {
        case unreadable

        var errorDescription: String? {
            "无法载入这张图，请重新选择清晰的计划截图或照片"
        }
    }

    /// Draw into a new buffer to apply EXIF orientation and exclude source metadata,
    /// including GPS coordinates. Keep readable photo dimensions with a memory ceiling.
    @MainActor
    static func jpegWithoutMetadata(_ image: UIImage) -> Data? {
        let width = image.size.width * image.scale
        let height = image.size.height * image.scale
        guard width.isFinite, height.isFinite, width >= 1, height >= 1 else { return nil }
        let factor = min(1, 8_000 / max(width, height), sqrt(24_000_000 / (width * height)))
        let size = CGSize(width: max(1, (width * factor).rounded(.down)),
                          height: max(1, (height * factor).rounded(.down)))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        let rectangle = CGRect(origin: .zero, size: size)
        return UIGraphicsImageRenderer(size: size, format: format).jpegData(withCompressionQuality: 0.96) {
            $0.cgContext.setFillColor(UIColor.white.cgColor)
            $0.cgContext.fill(rectangle)
            image.draw(in: rectangle)
        }
    }
}
