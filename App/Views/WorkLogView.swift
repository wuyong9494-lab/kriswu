import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// 首页的「工作留痕」：拍照、录音、记一笔，一点就开始
struct WorkLogCard: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var log = WorkLogStore.shared
    let day: DayKey
    @State private var camera = false
    @State private var recording = false
    @State private var writing = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            NavigationLink { WorkLogView() } label: {
                HStack {
                    Text("工作留痕").font(DS.Font.overline).kerning(0.6).foregroundStyle(.secondary)
                    Spacer()
                    let n = log.count(on: day)
                    Text(n == 0 ? "今天还没有记录" : "今天 \(n) 条").font(DS.Font.caption).foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            HStack(spacing: DS.Space.s) {
                action("拍照", "camera") { camera = true }
                action("录音", "mic") { recording = true }
                action("记一笔", "square.and.pencil") { writing = true }
            }
            // 交接班：把今天的清单、留痕整理成一段话，复制给接班的人
            Button {
                UIPasteboard.general.string = log.handoverSummary(for: day, store: store)
                Haptics.success()
                ToastCenter.shared.show("交接小结已复制，粘贴后补充几句就能发", style: .success)
            } label: {
                Label("生成交接小结", systemImage: "arrow.left.arrow.right.square")
                    .font(DS.Font.caption)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .card()
        .fullScreenCover(isPresented: $camera) {
            CameraPicker { image in
                if WorkLogStore.shared.addPhoto(image) != nil {
                    ToastCenter.shared.show("照片已存进工作留痕", style: .success)
                }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $recording) { RecorderSheet() }
        .sheet(isPresented: $writing) { NoteSheet() }
    }

    private func action(_ title: String, _ icon: String, run: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            run()
        } label: {
            VStack(spacing: DS.Space.xxs + 2) {
                IconBadge(icon: icon, size: 44)
                Text(title).font(DS.Font.caption).foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PressableStyle())
    }
}

/// 全部记录：按天分组，可以拍照、从相册选、录音、记文字、导入通话录音
struct WorkLogView: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var log = WorkLogStore.shared
    @State private var query = ""
    @State private var camera = false
    @State private var recording = false
    @State private var writing = false
    @State private var importing = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showGuide = false
    @State private var filter: WorkLogEntry.Kind?
    @State private var pendingDelete: [WorkLogEntry] = []

    var body: some View {
        if store.settings.workLogLock && !log.unlocked {
            VStack(spacing: DS.Space.m) {
                Image(systemName: "lock.fill").font(.system(size: 44)).foregroundStyle(.secondary)
                Text("工作留痕已上锁").font(DS.Font.headline)
                Button("用面容 ID 解锁") { Task { await log.unlock() } }
                    .buttonStyle(DSButtonStyle(kind: .primary))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .appBackground()
            .navigationTitle("工作留痕")
            .navigationBarTitleDisplayMode(.inline)
            .task { await log.unlock() }
        } else {
            content
        }
    }

    /// 一天的记录：左滑删除先确认；标题右边一次分享这天的全部照片、录音和一份文字汇总（交材料用）
    private func daySection(_ day: DayKey, entries: [WorkLogEntry]) -> some View {
        let title = day.dateText + (entries.compactMap(\.shift).first.map { " · \($0)" } ?? "")
        return Section {
            ForEach(entries) { entry in
                NavigationLink { WorkLogDetailView(entry: entry) } label: { WorkLogRow(entry: entry) }
            }
            .onDelete { offsets in
                // 左滑删除也先确认（照片、录音删了就没了）
                pendingDelete = offsets.map { entries[$0] }
            }
        } header: {
            HStack {
                Text(title)
                Spacer()
                ShareLink(items: exportItems(day: day, entries: entries)) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("分享这天的全部留痕")
            }
        }
    }

    /// 这天的文件 + 一份文字汇总
    private func exportItems(day: DayKey, entries: [WorkLogEntry]) -> [WorkLogShareFile] {
        let sorted = entries.sorted { $0.date < $1.date }
        var lines = ["\(day.dateText) 工作留痕"]
        for e in sorted {
            var line = e.date.formatted(date: .omitted, time: .shortened) + " " + e.kind.title
            if let shift = e.shift { line += "（\(shift)）" }
            if let file = e.file { line += " [\(file)]" }
            let text = [e.note, e.transcript ?? ""].filter { !$0.isEmpty }.joined(separator: "\n  ")
            if !text.isEmpty { line += "\n  " + text }
            lines.append(line)
        }
        var items = [WorkLogShareFile(name: "\(day) 工作留痕.txt", text: lines.joined(separator: "\n"))]
        for e in sorted {
            if let url = log.url(for: e) { items.append(WorkLogShareFile(name: url.lastPathComponent, url: url)) }
        }
        return items
    }

    private var content: some View {
        let shown = log.entries.filter { (filter == nil || $0.kind == filter) && $0.matches(query) }
        let groups = Dictionary(grouping: shown) { DayKey(date: $0.date, calendar: .app) }
        return List {
            Section {
                HStack(spacing: DS.Space.s) {
                    big("拍照", "camera.fill") { camera = true }
                    big("录音", "mic.fill") { recording = true }
                    big("记一笔", "square.and.pencil") { writing = true }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            Section {
                DisclosureGroup(isExpanded: $showGuide) {
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        Text("iPhone 不允许别的 App 录通话。用系统自带的通话录音（iOS 18.1 起）：")
                        Text("1. 打电话时点屏幕左上角的录音按钮，对方会听到提示。")
                        Text("2. 挂断后录音自动存进「备忘录」。")
                        Text("3. 在备忘录里打开那条录音，点 ⋯ › 分享 › 选「值班提醒」；或者「存储到文件」后在这里点右上角 ＋ › 导入通话录音。")
                        Text("导入后会记上日期和当天的班次。")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, DS.Space.xxs)
                } label: {
                    Label("通话录音怎么存进来", systemImage: "phone.badge.waveform")
                }
            }
            if shown.isEmpty {
                Section {
                    if query.isEmpty {
                        EmptyState(icon: "tray", title: "还没有记录", message: "拍照、录音、记一笔，都会按日期和当天的班次存好。")
                    } else {
                        EmptyState(icon: "magnifyingglass", title: "没找到「\(query)」", message: "说明、录音转出的文字、班次都会搜。")
                    }
                }
            }
            ForEach(groups.keys.sorted(by: >), id: \.self) { day in
                daySection(day, entries: groups[day] ?? [])
            }
            Section {
                Toggle("录音自动转成文字", isOn: $store.settings.workLogAutoTranscribe)
                Toggle("只在手机上识别（不联网）", isOn: $store.settings.speechOnDeviceOnly)
                Toggle("打开工作留痕要面容 ID", isOn: $store.settings.workLogLock)
                    .onChange(of: store.settings.workLogLock) { locked in
                        log.relocate(hidden: locked)
                        log.unlocked = true
                    }
            } header: {
                Text("设置")
            } footer: {
                Text(store.settings.workLogLock
                     ? "已上锁：文件挪到了 App 内部，「文件」App 里看不到，只能在这里看。所有文件都加密存储，手机锁屏时无法读取。"
                     : "文件只存在手机上并加密存储：「文件」App › 我的 iPhone › 值班提醒 › 工作留痕 也能看到，可以整个文件夹拷走备份。打开面容 ID 锁后会挪到 App 内部。")
            }
        }
        .confirmationDialog("删除这 \(pendingDelete.count) 条记录？照片、录音会一起删掉，不能恢复。",
                            isPresented: Binding(get: { !pendingDelete.isEmpty }, set: { if !$0 { pendingDelete = [] } }),
                            titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                pendingDelete.forEach(log.delete)
                pendingDelete = []
            }
            Button("取消", role: .cancel) { pendingDelete = [] }
        }
        .searchable(text: $query, prompt: "搜说明、录音文字、班次")
        .appList()
        .navigationTitle("工作留痕")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { camera = true } label: { Label("拍照", systemImage: "camera") }
                    PhotosPicker(selection: $photoItems, matching: .images) { Label("从相册选", systemImage: "photo.on.rectangle") }
                    Button { recording = true } label: { Label("录音", systemImage: "mic") }
                    Button { writing = true } label: { Label("记一笔", systemImage: "square.and.pencil") }
                    Button { importing = true } label: { Label("导入通话录音 / 文件", systemImage: "square.and.arrow.down") }
                    Divider()
                    Picker("只看", selection: $filter) {
                        Text("全部").tag(WorkLogEntry.Kind?.none)
                        ForEach([WorkLogEntry.Kind.photo, .audio, .call, .note, .file], id: \.self) { k in
                            Label(k.title, systemImage: k.symbol).tag(Optional(k))
                        }
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
            }
        }
        .fullScreenCover(isPresented: $camera) {
            CameraPicker { image in
                if log.addPhoto(image) != nil { ToastCenter.shared.show("照片已保存", style: .success) }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $recording) { RecorderSheet() }
        .sheet(isPresented: $writing) { NoteSheet() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio, .image, .pdf, .item],
                      allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            let n = urls.compactMap { log.importFile($0) }.count
            ToastCenter.shared.show(n > 0 ? "导入了 \(n) 个文件" : "没能导入", style: n > 0 ? .success : .error)
        }
        .onChange(of: photoItems) { items in
            guard !items.isEmpty else { return }
            Task { @MainActor in
                var n = 0
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data),
                       log.addPhoto(image) != nil { n += 1 }
                }
                photoItems = []
                ToastCenter.shared.show("存了 \(n) 张照片", style: .success)
            }
        }
    }

    private func big(_ title: String, _ icon: String, run: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            run()
        } label: {
            VStack(spacing: DS.Space.xs) {
                Image(systemName: icon).font(.system(size: 26, weight: .semibold))
                Text(title).font(DS.Font.caption.weight(.semibold))
            }
            .foregroundStyle(DS.Palette.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Space.m)
            .card(padding: 0)
        }
        .buttonStyle(PressableStyle())
    }
}

struct WorkLogRow: View {
    let entry: WorkLogEntry

    var body: some View {
        HStack(spacing: DS.Space.s) {
            if entry.kind == .photo, let url = WorkLogStore.shared.url(for: entry), let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                IconBadge(icon: entry.kind.symbol, size: 44)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.note.isEmpty ? (entry.transcript ?? entry.kind.title) : entry.note)
                    .font(.subheadline)
                    .lineLimit(2)
                HStack(spacing: DS.Space.xs) {
                    Text(entry.date.formatted(date: .omitted, time: .shortened))
                    Text(entry.kind.title)
                    if let d = entry.duration { Text(Self.time(d)) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    static func time(_ t: TimeInterval) -> String {
        let s = Int(t.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// 一条记录：看照片、听录音、改说明、分享、删除
struct WorkLogDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var log = WorkLogStore.shared
    @StateObject private var player = AudioPlayerModel()
    @State var entry: WorkLogEntry
    @State private var confirmDelete = false
    @State private var transcribeError: String?
    /// 识别出的文字，可以手动改（关掉页面时保存）
    @State private var transcriptDraft: String?

    var body: some View {
        let url = WorkLogStore.shared.url(for: entry)
        List {
            if entry.kind == .photo, let url, let image = UIImage(contentsOfFile: url.path) {
                Section {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
                        .listRowInsets(EdgeInsets())
                }
            }
            if entry.kind == .audio || entry.kind == .call {
                Section {
                    HStack(spacing: DS.Space.m) {
                        Button { player.toggle() } label: {
                            Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(DS.Palette.accent)
                        }
                        .buttonStyle(.plain)
                        VStack(alignment: .leading, spacing: 4) {
                            Slider(value: Binding(get: { player.progress }, set: { player.seek($0) }),
                                   in: 0...max(player.duration, 0.1))
                            HStack {
                                Text(WorkLogRow.time(player.progress))
                                Spacer()
                                Text(WorkLogRow.time(player.duration))
                            }
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, DS.Space.xxs)
                }
            }
            if entry.isAudio {
                let current = log.entries.first { $0.id == entry.id } ?? entry
                Section {
                    if log.transcribing.contains(entry.id) {
                        HStack(spacing: DS.Space.s) { ProgressView(); Text("正在转文字…").foregroundStyle(.secondary) }
                    } else if current.transcript != nil {
                        // 识别错的字直接改
                        TextField("识别出的文字", text: Binding(get: { transcriptDraft ?? current.transcript ?? "" },
                                                          set: { transcriptDraft = $0 }), axis: .vertical)
                            .lineLimit(3...20)
                        Button {
                            UIPasteboard.general.string = transcriptDraft ?? current.transcript
                            ToastCenter.shared.show("已复制", style: .success)
                        } label: {
                            Label("复制文字", systemImage: "doc.on.doc")
                        }
                        recognizeButtons(current)
                    } else {
                        recognizeButtons(current)
                    }
                    if let transcribeError {
                        Text(transcribeError).font(.footnote).foregroundStyle(DS.Palette.warning)
                    }
                } header: {
                    Text("录音文字")
                } footer: {
                    Text("默认只在手机上识别，录音不出手机，但准确度一般。「联网识别」用苹果的服务器识别，准很多，但这条录音会发给苹果。识别时会参考同事名字、组别、星名等常用词；错字可以直接改。")
                }
            }
            Section {
                TextField(entry.kind == .note ? "内容" : "说明（可选）", text: $entry.note, axis: .vertical)
                    .lineLimit(3...12)
            } header: {
                Text(entry.kind == .note ? "内容" : "说明")
            }
            Section {
                LabeledContent("时间", value: entry.date.formatted(date: .abbreviated, time: .shortened))
                if let shift = entry.shift { LabeledContent("当天班次", value: shift) }
                LabeledContent("类型", value: entry.kind.title)
                if let url {
                    ShareLink(item: url) { Label("分享 / 存到别处", systemImage: "square.and.arrow.up") }
                } else {
                    ShareLink(item: entry.note) { Label("分享文字", systemImage: "square.and.arrow.up") }
                }
                Button("删除这条", role: .destructive) { confirmDelete = true }
            }
        }
        .appList()
        .navigationTitle(entry.kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if let url, entry.kind == .audio || entry.kind == .call { player.load(url) } }
        .onDisappear {
            player.stop()
            WorkLogStore.shared.updateNote(entry.id, entry.note)
            if let transcriptDraft { WorkLogStore.shared.updateTranscript(entry.id, transcriptDraft) }
        }
        .confirmationDialog("删除后找不回来", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                WorkLogStore.shared.delete(entry)
                dismiss()
            }
        }
    }
}

extension WorkLogDetailView {
    @ViewBuilder
    func recognizeButtons(_ current: WorkLogEntry) -> some View {
        Button {
            transcriptDraft = nil
            Task { transcribeError = await WorkLogStore.shared.transcribe(current) }
        } label: {
            Label(current.transcript == nil ? "转成文字" : "重新识别",
                  systemImage: current.transcript == nil ? "text.bubble" : "arrow.clockwise")
        }
        if AppStore.shared.settings.speechOnDeviceOnly {
            Button {
                transcriptDraft = nil
                Task { transcribeError = await WorkLogStore.shared.transcribe(current, online: true) }
            } label: {
                Label("联网识别（更准，录音发给苹果）", systemImage: "icloud.and.arrow.up")
            }
        }
    }
}

/// 录音：大按钮开始 / 停止，停下来就存好
struct RecorderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = VoiceRecorder()
    @State private var note = ""
    /// 从控制中心、操作按钮打开时直接开始录
    var autoStart = false

    var body: some View {
        NavigationStack {
            VStack(spacing: DS.Space.l) {
                Spacer()
                Text(WorkLogRow.time(recorder.elapsed))
                    .font(.system(size: 56, weight: .semibold, design: .rounded).monospacedDigit())
                // 跟着音量跳的波形
                HStack(spacing: 4) {
                    ForEach(0..<24, id: \.self) { i in
                        Capsule()
                            .fill(DS.Palette.accent.opacity(recorder.isRecording ? 0.9 : 0.25))
                            .frame(width: 5, height: 8 + CGFloat(recorder.level) * 60 * CGFloat(abs(sin(Double(i) * 0.7 + recorder.elapsed * 6))))
                    }
                }
                .frame(height: 70)
                .animation(.easeOut(duration: 0.1), value: recorder.level)
                TextField("说明（可选）", text: $note)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, DS.Space.l)
                if let error = recorder.error {
                    Text(error).font(.footnote).foregroundStyle(DS.Palette.warning).multilineTextAlignment(.center)
                        .padding(.horizontal, DS.Space.l)
                }
                Button {
                    Haptics.tap()
                    if recorder.isRecording {
                        if let r = recorder.stop() {
                            if WorkLogStore.shared.addRecording(from: r.url, duration: r.duration, note: note) != nil {
                                ToastCenter.shared.show("录音已保存", style: .success)
                            } else {
                                ToastCenter.shared.show("录音没存进去，解锁手机后再试一次", style: .error)
                            }
                            dismiss()
                        }
                    } else {
                        Task { await recorder.start() }
                    }
                } label: {
                    ZStack {
                        Circle().stroke(Color.secondary.opacity(0.4), lineWidth: 4).frame(width: 84, height: 84)
                        if recorder.isRecording {
                            RoundedRectangle(cornerRadius: 8).fill(Color.red).frame(width: 34, height: 34)
                        } else {
                            Circle().fill(Color.red).frame(width: 68, height: 68)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(recorder.isRecording ? "停止并保存" : "开始录音")
                Text(recorder.isRecording ? "点一下停止并保存" : "点一下开始录音")
                    .font(.footnote).foregroundStyle(.secondary)
                Spacer()
            }
            .navigationTitle("录音")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        recorder.cancel()
                        dismiss()
                    }
                }
            }
        }
        .interactiveDismissDisabled(recorder.isRecording)
        .presentationDetents([.medium, .large])
        // 录着的时候页面被关掉（锁屏上锁、又按了一次快捷录音）：把录到的存下来，不丢
        .onDisappear {
            if recorder.isRecording, let r = recorder.stop() {
                if WorkLogStore.shared.addRecording(from: r.url, duration: r.duration, note: note) != nil {
                    ToastCenter.shared.show("录音已保存", style: .success)
                }
            }
        }
        .task {
            recorder.onInterrupted = { url, duration in
                if WorkLogStore.shared.addRecording(from: url, duration: duration, note: note) != nil {
                    ToastCenter.shared.show("录音被打断，已保存前面的部分", style: .success)
                }
            }
            if autoStart && !recorder.isRecording { await recorder.start() }
        }
    }
}

/// 记一笔文字
struct NoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                TextField("比如：08:30 交班，二号星遥测帧计数跳变，已报值班长", text: $text, axis: .vertical)
                    .lineLimit(5...20)
                    .focused($focused)
            }
            .navigationTitle("记一笔")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        // 没存进去就留着这页和写好的字，不丢
                        if WorkLogStore.shared.addNote(text) {
                            ToastCenter.shared.show("已记下", style: .success)
                            dismiss()
                        } else {
                            ToastCenter.shared.show("没存进去，解锁手机后再试一次", style: .error)
                        }
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
    }
}

/// 打开相机拍照（没有相机的设备打开相册）
struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

/// 分享出去的一个文件：留痕里已有的文件，或者临时写出来的文字汇总
struct WorkLogShareFile: Transferable {
    var name: String
    var url: URL?
    var text: String?

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .data) { item in
            if let url = item.url { return SentTransferredFile(url) }
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent(item.name)
            try (item.text ?? "").data(using: .utf8)?.write(to: temp, options: .atomic)
            return SentTransferredFile(temp)
        }
    }
}
