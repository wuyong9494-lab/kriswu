import ImageIO
import SwiftUI
import UIKit

/// Stand-alone image generation; does not read the chat, photos, or work files.
struct AIImageToolView: View {
    @State private var model: AIImageTool.Model? = nil
    @State private var prompt = ""
    @State private var requested: Pending? = nil
    @State private var confirming = false
    @State private var settingKey = false
    @State private var hasKey = false
    @State private var active: UUID? = nil
    @State private var task: Task<Void, Never>? = nil
    @State private var output: UIImage? = nil
    @State private var outputModel = ""
    @State private var failure: String? = nil

    private struct Pending {
        var model: AIImageTool.Model
        var prompt: String
    }

    private var cleaned: String { prompt.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var valid: Bool { !cleaned.isEmpty && cleaned.utf8.count <= AIImageTool.maxPromptBytes }

    var body: some View {
        Form {
            Section {
                Picker("出图模型", selection: $model) {
                    Text("请选择").tag(Optional<AIImageTool.Model>.none)
                    ForEach(AIImageTool.models) { item in
                        Text("\(item.provider.displayName) · \(item.displayName)").tag(Optional(item))
                    }
                }
                .disabled(active != nil)
                .accessibilityIdentifier("ai.image.model")
                TextField("描述你想生成的图片", text: $prompt, axis: .vertical)
                    .lineLimit(3...7)
                    .disabled(active != nil)
                if let model, !hasKey {
                    Button("填写\(model.provider.displayName) API Key") { settingKey = true }
                        .disabled(active != nil)
                }
                if active != nil {
                    ProgressView("生成中…")
                    Button("停止等待", role: .cancel, action: stop)
                } else {
                    Button("生成一张图片") { prepare() }
                        .disabled(!valid || model == nil)
                        .accessibilityIdentifier("ai.image.generate")
                }
                if let failure {
                    Text(failure).font(.footnote).foregroundStyle(DS.Palette.danger)
                }
            } footer: {
                Text("仅将本次提示词发给你选的服务商，按该 API 计费。不读取聊天、值班计划或相册。")
            }

            if let output {
                Section("结果 · \(outputModel)") {
                    let image = Image(uiImage: output)
                    image.resizable().scaledToFit()
                        .frame(maxWidth: 620)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("生成的图片")
                    ShareLink(item: image, preview: SharePreview("生成的图片", image: image))
                }
            }
        }
        .navigationTitle("文字生成图片")
        .navigationBarTitleDisplayMode(.inline)
        .alert("确认生成图片？", isPresented: $confirming) {
            Button("发送并生成") { start() }
            Button("取消", role: .cancel) { requested = nil }
        } message: {
            Text("将提示词发给\(requested?.model.provider.displayName ?? "所选服务商")，可能消耗 API 额度。请勿输入未经许可外发的内容。")
        }
        .sheet(isPresented: $settingKey) {
            if let model {
                ProviderKeyView(provider: model.provider) { configured in hasKey = configured; failure = nil }
            }
        }
        .onAppear(perform: syncKey)
        .onChange(of: model) { _ in syncKey(); failure = nil }
        .onDisappear(perform: stop)
    }

    private func syncKey() {
        hasKey = model.flatMap { Keychain.providerChatAPIKey($0.provider) } != nil
    }

    private func prepare() {
        guard active == nil, valid, let model else { return }
        guard Keychain.providerChatAPIKey(model.provider) != nil else { settingKey = true; return }
        requested = Pending(model: model, prompt: cleaned)
        confirming = true
    }

    private func start() {
        guard active == nil, let request = requested else { return }
        requested = nil
        guard let key = Keychain.providerChatAPIKey(request.model.provider) else {
            settingKey = true
            return
        }
        let id = UUID()
        active = id
        output = nil
        failure = nil
        task = Task { @MainActor in
            defer {
                if active == id { active = nil; task = nil }
            }
            do {
                let bytes = try await AIImageTool().generate(model: request.model, apiKey: key, prompt: request.prompt)
                guard active == id, !Task.isCancelled else { return }
                guard let image = Self.preview(bytes) else {
                    failure = "无法打开服务商返回的图片，或图片尺寸过大。"
                    return
                }
                outputModel = request.model.displayName
                output = image
            } catch {
                guard active == id, !Task.isCancelled else { return }
                failure = (error as? LocalizedError)?.errorDescription ?? "未能生成图片。"
            }
        }
    }

    private func stop() {
        if active != nil {
            active = nil
            failure = "已停止等待。已发出的请求可能仍产生 API 用量。"
        }
        task?.cancel()
        task = nil
        requested = nil
    }

    private static func preview(_ data: Data) -> UIImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              height > 0, width > 0, height <= 4_096, width <= 4_096,
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, options) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
