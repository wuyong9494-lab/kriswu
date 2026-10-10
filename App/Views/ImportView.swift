import SwiftUI
import UniformTypeIdentifiers

/// 粘贴或选择文件导入排班表，先预览识别结果，确认后再写入。
struct ImportView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var showingFilePicker = false
    @State private var fileError: String?
    var onImported: (() -> Void)?

    init(initialText: String = "", onImported: (() -> Void)? = nil) {
        _text = State(initialValue: initialText)
        self.onImported = onImported
    }

    private var preview: Result<ParseResult, Error>? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return Result { try store.parser.parse(text) }
    }

    var body: some View {
        Form {
            Section {
                TextEditor(text: $text)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(minHeight: 160)
                HStack {
                    Button {
                        if let s = UIPasteboard.general.string { text = s }
                    } label: { Label("粘贴", systemImage: "doc.on.clipboard") }
                    Spacer()
                    Button { showingFilePicker = true } label: { Label("选择文件", systemImage: "folder") }
                }
                .buttonStyle(.borderless)
                if let fileError {
                    Text(fileError).foregroundStyle(.red).font(.footnote)
                }
            } header: {
                Text("排班内容")
            } footer: {
                Text("""
                支持：从 Excel/WPS 复制的表格、CSV、日历 .ics、JSON，或者直接手打，例如：
                10/9 白班
                10/10 夜班
                多人排班表会自动找出「\(store.settings.aliases.joined(separator: " / "))」那一行或那一列。
                """)
            }

            if let preview {
                switch preview {
                case .success(let result):
                    Section {
                        ForEach(result.entries.sorted { $0.key < $1.key }.prefix(62), id: \.key) { entry in
                            HStack {
                                Text(entry.key.dateText).foregroundStyle(.secondary)
                                Spacer()
                                let display = ShiftDisplay(raw: entry.value, matcher: store.matcher)
                                Text("\(display?.emoji ?? "") \(display?.name ?? entry.value)")
                            }
                        }
                    } header: {
                        Text("识别为「\(result.format.rawValue)」，共 \(result.entries.count) 天")
                    } footer: {
                        if let range = result.range {
                            Text("导入后 \(range.lowerBound.dateText) 至 \(range.upperBound.dateText) 之间的旧排班会被替换。")
                        }
                    }
                    Section {
                        Button("导入") {
                            store.apply(result)
                            onImported?()
                            dismiss()
                        }
                        .bold()
                    }
                case .failure(let error):
                    Section("识别结果") {
                        Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .navigationTitle("导入排班")
        .fileImporter(isPresented: $showingFilePicker,
                      allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText, .json, .calendarEvent, .html, .data]) { result in
            fileError = nil
            switch result {
            case .success(let url):
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url), let s = SyncService.decode(data) else {
                    fileError = "无法读取这个文件。Excel 文件请先另存为 CSV，或直接复制表格粘贴。"
                    return
                }
                text = HTMLText.looksLikeHTML(s) ? HTMLText.toText(s) : s
            case .failure(let error):
                fileError = error.localizedDescription
            }
        }
    }
}
