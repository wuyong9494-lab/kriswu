import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Color Helper for Connectors & Projects

enum WuMindTintPalette {
    static func color(for key: String) -> Color {
        switch key {
        case "blue": return Color(red: 0.20, green: 0.50, blue: 0.98)
        case "green": return Color(red: 0.14, green: 0.72, blue: 0.42)
        case "yellow": return Color(red: 0.95, green: 0.70, blue: 0.12)
        case "orange": return Color(red: 0.96, green: 0.49, blue: 0.18)
        case "red": return Color(red: 0.92, green: 0.28, blue: 0.30)
        case "pink": return Color(red: 0.92, green: 0.32, blue: 0.56)
        case "purple": return Color(red: 0.60, green: 0.36, blue: 0.95)
        case "indigo": return Color(red: 0.34, green: 0.38, blue: 0.96)
        case "teal": return Color(red: 0.12, green: 0.68, blue: 0.68)
        case "cyan": return Color(red: 0.14, green: 0.66, blue: 0.88)
        case "mint": return Color(red: 0.16, green: 0.76, blue: 0.62)
        default: return Color.indigo
        }
    }
}

// MARK: - 1. Customizations Hub (Marketplace / Installed — Modeled on Flagship Customizations UI)

struct WuMindCustomizationsSheet: View {
    @ObservedObject var store: WuMindStore
    var onOpenGitHub: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    enum TabMode: String, CaseIterable {
        case marketplace = "市场"
        case installed = "已安装"
    }

    @State private var tab: TabMode = .marketplace
    @State private var query = ""
    @State private var configuringConnector: WuMindConnectorSpec? = nil
    @State private var endpointDraft = ""
    @State private var tokenDraft = ""
    @State private var editingSkill: WuMindSkill? = nil
    @State private var creatingSkill = false

    private var surfaceBg: Color {
        colorScheme == .dark ? Color(red: 0.09, green: 0.10, blue: 0.13) : Color(.systemGroupedBackground)
    }

    private var cardBg: Color {
        colorScheme == .dark ? Color(red: 0.14, green: 0.155, blue: 0.19) : Color.white
    }

    private func filteredConnectors(for category: WuMindCustomizationCategory) -> [WuMindConnectorSpec] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return WuMindConnectorSpec.marketplaceCatalog.filter { spec in
            guard spec.category == category else { return false }
            if tab == .installed && !store.isConnectorInstalled(spec.id) { return false }
            guard !q.isEmpty else { return true }
            return spec.name.localizedCaseInsensitiveContains(q)
                || spec.subtitle.localizedCaseInsensitiveContains(q)
                || (spec.toolName?.localizedCaseInsensitiveContains(q) == true)
        }
    }

    private var filteredSkills: [WuMindSkill] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = tab == .installed
            ? store.allSkills.filter { !$0.isBuiltIn || store.activeSkillID == $0.id }
            : store.allSkills
        guard !q.isEmpty else { return base }
        return base.filter {
            $0.name.localizedCaseInsensitiveContains(q)
                || $0.summary.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    headerBar
                    categoriesSection
                    skillsSection
                }
                .padding(16)
            }
            .background(surfaceBg.ignoresSafeArea())
            .navigationTitle("定制中心")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(item: $configuringConnector) { spec in
                connectorConfigSheet(spec)
            }
            .sheet(isPresented: $creatingSkill) {
                WuMindQuickSkillEditorSheet(existing: nil, onDelete: nil) { name, icon, summary, prompt in
                    store.saveCustomSkill(name: name, icon: icon, summary: summary, prompt: prompt)
                }
            }
            .sheet(item: $editingSkill) { skill in
                WuMindQuickSkillEditorSheet(existing: skill, onDelete: {
                    store.deleteCustomSkill(skill.id)
                }) { name, icon, summary, prompt in
                    store.saveCustomSkill(id: skill.id, name: name, icon: icon, summary: summary, prompt: prompt)
                }
            }
        }
        .accessibilityIdentifier("wumind.customizations.sheet")
    }

    private var headerBar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Customizations")
                        .font(.title3.weight(.bold))
                    Text("已安装 \(store.installedConnectorIDs.count) 个连接器 · \(store.allSkills.count) 个 Skills")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 3) {
                    ForEach(TabMode.allCases, id: \.self) { mode in
                        let active = tab == mode
                        Button {
                            Haptics.select()
                            withAnimation(.easeInOut(duration: 0.18)) { tab = mode }
                        } label: {
                            Text(mode.rawValue)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(active ? .primary : .secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    active ? Color.secondary.opacity(0.22) : Color.clear,
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("wumind.custom.tab.\(mode.rawValue)")
                    }
                }
                .padding(3)
                .background(cardBg, in: Capsule())
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("搜索连接器、办公套件、智能体工具或 Skills…", text: $query)
                    .font(.subheadline)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(cardBg, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1))
        }
    }

    private var categoriesSection: some View {
        ForEach(WuMindCustomizationCategory.allCases) { category in
            let items = filteredConnectors(for: category)
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.title)
                            .font(.headline.weight(.bold))
                        Text(category.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    LazyVStack(spacing: 10) {
                        ForEach(items) { spec in
                            connectorRow(spec)
                        }
                    }
                }
            }
        }
    }

    private var skillsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("专业 Skills 技能包")
                        .font(.headline.weight(.bold))
                    Text("点击即刻激活角色指令，或创建你自己的专属 Skill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Haptics.tap()
                    creatingSkill = true
                } label: {
                    Label("新建 Skill", systemImage: "plus")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.indigo.opacity(0.14), in: Capsule())
                        .foregroundStyle(.indigo)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("wumind.skills.create")
            }

            if store.activeSkill != nil {
                Button {
                    Haptics.tap()
                    store.selectSkill(nil)
                } label: {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.secondary)
                        Text("恢复默认通用模式（取消当前 Skill）")
                            .font(.caption.weight(.medium))
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(cardBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            LazyVStack(spacing: 9) {
                ForEach(filteredSkills) { skill in
                    skillRow(skill)
                }
            }
        }
    }

    private func connectorConfigSheet(_ spec: WuMindConnectorSpec) -> some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        connectorIcon(spec)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(spec.name).font(.headline)
                            Text(spec.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                if spec.requiresEndpoint {
                    Section {
                        TextField("https://your-mcp-bridge.example.com/invoke", text: $endpointDraft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                        SecureField("Bearer Token（可选，仅存本机 Keychain）", text: $tokenDraft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } header: {
                        Text("HTTPS / MCP 桥接端点配置")
                    } footer: {
                        Text("为保护安全，仅允许公开 HTTPS 端点。凭据只保存在当前设备的 iOS Keychain，绝不上传至非目标服务器。")
                    }
                } else if spec.id == "dev.websearch" {
                    Section {
                        SecureField("可选：Tavily (tvly-...) 或 Brave Search API Key", text: $tokenDraft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } header: {
                        Text("自带 API 通道联网搜索增强（可选）")
                    } footer: {
                        Text("联网搜索独立于聊天模型。自带 API 时优先使用个人 Tavily / Brave Key（仅存本机钥匙串）；没有个人搜索 Key 时，可用已登录的 WUMIND 网关（按网关显示的规则计费）。个人搜索失败不会自动切到网关扣费。")
                    }
                    Section("工具说明") {
                        Text(spec.agentPromptHint)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("工具说明") {
                        Text(spec.agentPromptHint)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        store.toggleConnector(spec.id)
                        configuringConnector = nil
                    } label: {
                        Label(store.isConnectorInstalled(spec.id) ? "卸载此连接器" : "安装此连接器",
                              systemImage: store.isConnectorInstalled(spec.id) ? "trash" : "plus.circle")
                    }
                }
            }
            .navigationTitle("配置连接器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { configuringConnector = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if spec.requiresEndpoint {
                            store.setConnectorEndpoint(endpointDraft, for: spec.id)
                            Keychain.setConnectorToken(tokenDraft, for: spec.id)
                        } else if spec.id == "dev.websearch" {
                            Keychain.setConnectorToken(tokenDraft, for: spec.id)
                        }
                        if !store.isConnectorInstalled(spec.id) {
                            store.toggleConnector(spec.id)
                        }
                        configuringConnector = nil
                        ToastCenter.shared.show("已保存 \(spec.name) 配置", style: .success)
                    }
                }
            }
        }
    }

    private func connectorIcon(_ spec: WuMindConnectorSpec) -> some View {
        let tint = WuMindTintPalette.color(for: spec.tintKey)
        return Image(systemName: spec.iconName)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 38, height: 38)
            .background(
                LinearGradient(colors: [tint, tint.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
    }

    private func connectorRow(_ spec: WuMindConnectorSpec) -> some View {
        let installed = store.isConnectorInstalled(spec.id)
        let hasEndpoint = !(store.connectorEndpoints[spec.id] ?? "").isEmpty
        return HStack(spacing: 12) {
            connectorIcon(spec)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(spec.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if spec.toolName != nil {
                        Text("智能体工具")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(.indigo)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.indigo.opacity(0.12), in: Capsule())
                    }
                    if installed && spec.requiresEndpoint && hasEndpoint {
                        Text("已配端点")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.12), in: Capsule())
                    } else if installed && spec.id == "dev.websearch" && Keychain.connectorToken(for: spec.id) != nil {
                        Text("已配 Key")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.12), in: Capsule())
                    }
                }
                Text(spec.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 6)
            if installed {
                Menu {
                    if spec.id == "dev.github" {
                        Button {
                            dismiss()
                            onOpenGitHub()
                        } label: {
                            Label("连接或切换 GitHub 仓库…", systemImage: "chevron.left.forwardslash.chevron.right")
                        }
                    }
                    Button {
                        endpointDraft = store.connectorEndpoints[spec.id] ?? ""
                        tokenDraft = Keychain.connectorToken(for: spec.id) ?? ""
                        configuringConnector = spec
                    } label: {
                        let labelText = spec.requiresEndpoint
                            ? "配置 HTTPS / MCP 端点…"
                            : (spec.id == "dev.websearch" ? "配置联网搜索 Key 与说明…" : "查看说明与管理…")
                        Label(labelText, systemImage: "slider.horizontal.3")
                    }
                    Divider()
                    Button(role: .destructive) {
                        Haptics.tap()
                        store.toggleConnector(spec.id)
                    } label: {
                        Label("停用 / 卸载", systemImage: "minus.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .background(Color.secondary.opacity(0.12), in: Circle())
                }
            } else {
                Button {
                    Haptics.select()
                    if spec.requiresEndpoint {
                        endpointDraft = store.connectorEndpoints[spec.id] ?? ""
                        tokenDraft = Keychain.connectorToken(for: spec.id) ?? ""
                        configuringConnector = spec
                    } else {
                        store.toggleConnector(spec.id)
                        ToastCenter.shared.show("已安装「\(spec.name)」", style: .success)
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.primary)
                        .frame(width: 32, height: 32)
                        .background(Color.secondary.opacity(0.13), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("安装 \(spec.name)")
            }
        }
        .padding(12)
        .background(cardBg, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(installed ? Color.indigo.opacity(0.24) : Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    private func skillRow(_ skill: WuMindSkill) -> some View {
        let active = store.activeSkillID == skill.id
        return Button {
            Haptics.select()
            store.selectSkill(active ? nil : skill)
            if !active { dismiss() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: skill.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(active ? .white : .indigo)
                    .frame(width: 34, height: 34)
                    .background(active ? Color.indigo : Color.indigo.opacity(0.13), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(skill.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(skill.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                if active {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.indigo)
                } else if !skill.isBuiltIn {
                    Button {
                        editingSkill = skill
                    } label: {
                        Image(systemName: "pencil")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(cardBg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(active ? Color.indigo.opacity(0.45) : Color.secondary.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct WuMindQuickSkillEditorSheet: View {
    let existing: WuMindSkill?
    let onDelete: (() -> Void)?
    let onSave: (String, String, String, String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var summary: String
    @State private var prompt: String
    @State private var icon: String

    private let icons = [
        "wand.and.stars", "terminal.fill", "doc.text.fill", "chart.bar.fill",
        "hammer.fill", "globe", "brain.head.profile", "checkmark.shield.fill"
    ]

    init(existing: WuMindSkill?, onDelete: (() -> Void)? = nil, onSave: @escaping (String, String, String, String) -> Void) {
        self.existing = existing
        self.onDelete = onDelete
        self.onSave = onSave
        _name = State(initialValue: existing?.name ?? "")
        _summary = State(initialValue: existing?.summary ?? "")
        _prompt = State(initialValue: existing?.prompt ?? "")
        _icon = State(initialValue: existing?.icon ?? "wand.and.stars")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("Skill 名称", text: $name)
                    TextField("一句话用途说明", text: $summary)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 8), spacing: 8) {
                        ForEach(icons, id: \.self) { ic in
                            Button {
                                icon = ic
                            } label: {
                                Image(systemName: ic)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(icon == ic ? .white : .primary)
                                    .frame(width: 34, height: 34)
                                    .background(icon == ic ? Color.indigo : Color.secondary.opacity(0.14), in: Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("系统指令（System Prompt）") {
                    TextEditor(text: $prompt)
                        .frame(minHeight: 140)
                }
                if let onDelete {
                    Section {
                        Button(role: .destructive) {
                            onDelete()
                            dismiss()
                        } label: {
                            Label("删除此自定义 Skill", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? "新建自定义 Skill" : "编辑 Skill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(name, icon, summary, prompt)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// MARK: - 2. Projects Workspace Hub (Persistent Instructions + Knowledge Docs + Repo)

struct WuMindProjectsSheet: View {
    @ObservedObject var store: WuMindStore
    @Environment(\.dismiss) private var dismiss

    @State private var editingProject: WuMindProject? = nil
    @State private var creatingProject = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    WuMindHubHeroBanner(
                        title: "项目工作空间",
                        subtitle: "为不同任务绑定专属系统指令、长期知识库文件与 GitHub 仓库，对话自动共享上下文",
                        icon: "folder.fill",
                        colors: [Color(red: 0.22, green: 0.30, blue: 0.88), Color(red: 0.14, green: 0.60, blue: 0.72)],
                        chips: [
                            ("已建项目", "\(store.projects.count) 个"),
                            ("知识文档", "\(store.projects.reduce(0) { $0 + $1.knowledgeDocs.count }) 份"),
                            ("当前激活", store.activeProject?.name ?? "通用空间")
                        ]
                    )
                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                    .listRowBackground(Color.clear)
                }

                Section {
                    Button {
                        Haptics.tap()
                        creatingProject = true
                    } label: {
                        HStack(spacing: 11) {
                            WuMindIconBadge(icon: "folder.badge.plus", color: .indigo)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("新建项目空间")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.primary)
                                Text("独立系统指令 + PDF/Word/源码持久知识库")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .accessibilityIdentifier("wumind.projects.create")

                    if store.activeProject != nil {
                        Button {
                            Haptics.tap()
                            store.selectProject(nil, startFreshChat: false)
                            dismiss()
                        } label: {
                            HStack(spacing: 11) {
                                WuMindIconBadge(icon: "arrow.uturn.backward", color: .gray)
                                Text("退出当前项目，回到全部通用对话")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("我的项目空间（\(store.projects.count)）") {
                    if store.projects.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("还没有创建项目空间")
                                .font(.subheadline.weight(.semibold))
                            Text("像 Claude / ChatGPT Projects 一样：为不同工作或研发项目绑定专属系统指令、长期知识库文件（PDF/Word/表格/源码）与 GitHub 仓库，所有项目内对话自动共享上下文。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    } else {
                        ForEach(store.projects) { project in
                            let active = store.activeProjectID == project.id
                            let tint = WuMindTintPalette.color(for: project.colorKey)
                            let convoCount = store.conversations.filter { $0.projectID == project.id }.count
                            HStack(spacing: 12) {
                                Image(systemName: project.icon)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 38, height: 38)
                                    .background(tint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(project.name)
                                            .font(.subheadline.weight(.semibold))
                                        if active {
                                            Text("使用中")
                                                .font(.caption2.weight(.bold))
                                                .foregroundStyle(tint)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(tint.opacity(0.14), in: Capsule())
                                        }
                                    }
                                    Text("知识库 \(project.knowledgeDocs.count) 份 · 对话 \(convoCount) 条" + (project.attachedRepoFullName.map { " · \($0)" } ?? ""))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Button {
                                    editingProject = project
                                } label: {
                                    Image(systemName: "slider.horizontal.3")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .padding(7)
                                        .background(Color.secondary.opacity(0.12), in: Circle())
                                }
                                .buttonStyle(.plain)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                Haptics.select()
                                store.selectProject(project.id, startFreshChat: true)
                                dismiss()
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    store.deleteProject(project.id)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("项目空间")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(isPresented: $creatingProject) {
                WuMindProjectEditorSheet(store: store, existing: nil)
            }
            .sheet(item: $editingProject) { project in
                WuMindProjectEditorSheet(store: store, existing: project)
            }
        }
        .accessibilityIdentifier("wumind.projects.sheet")
    }
}

private struct WuMindProjectEditorSheet: View {
    @ObservedObject var store: WuMindStore
    let existing: WuMindProject?
    @Environment(\.dismiss) private var dismiss

    @State private var draft: WuMindProject
    @State private var repoInput: String
    @State private var showingImporter = false
    @State private var importing = false

    private let colorKeys = ["indigo", "blue", "teal", "green", "orange", "purple", "pink", "red"]
    private let icons = ["folder.fill", "cpu.fill", "doc.text.fill", "hammer.fill", "globe", "chart.bar.fill", "sparkles", "briefcase.fill"]

    private static let allowedDocTypes: [UTType] = {
        var types: [UTType] = [.pdf, .plainText, .commaSeparatedText, .json, .xml, .sourceCode, .utf8PlainText, .data]
        if let docx = UTType(filenameExtension: "docx") { types.append(docx) }
        if let xlsx = UTType(filenameExtension: "xlsx") { types.append(xlsx) }
        return types
    }()

    init(store: WuMindStore, existing: WuMindProject?) {
        self.store = store
        self.existing = existing
        let initial = existing ?? WuMindProject(name: "")
        _draft = State(initialValue: initial)
        _repoInput = State(initialValue: initial.attachedRepoFullName ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("项目信息") {
                    TextField("项目名称（如：卫星测控系统研发 / 2026 标书库）", text: $draft.name)
                    TextField("简短说明（可选）", text: $draft.summary)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 8), spacing: 8) {
                        ForEach(colorKeys, id: \.self) { ck in
                            let c = WuMindTintPalette.color(for: ck)
                            Button { draft.colorKey = ck } label: {
                                Circle()
                                    .fill(c)
                                    .frame(width: 26, height: 26)
                                    .overlay(
                                        Circle().strokeBorder(.white, lineWidth: draft.colorKey == ck ? 2.5 : 0)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 3)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 8), spacing: 8) {
                        ForEach(icons, id: \.self) { ic in
                            Button { draft.icon = ic } label: {
                                Image(systemName: ic)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(draft.icon == ic ? .white : .primary)
                                    .frame(width: 32, height: 32)
                                    .background(
                                        draft.icon == ic ? WuMindTintPalette.color(for: draft.colorKey) : Color.secondary.opacity(0.14),
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 3)
                }

                Section {
                    TextEditor(text: $draft.customInstructions)
                        .frame(minHeight: 110)
                } header: {
                    Text("项目专属系统指令（Custom Instructions）")
                } footer: {
                    Text("项目内所有对话都会自动注入该指令与下方知识库文档，无需重复说明背景。")
                }

                Section("绑定 GitHub 仓库（可选）") {
                    TextField("owner/repo（如 wuyong9494-lab/kriswu）", text: $repoInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("项目持久知识库文件（\(draft.knowledgeDocs.count) 份）") {
                    Button {
                        showingImporter = true
                    } label: {
                        HStack {
                            if importing { ProgressView().controlSize(.small) }
                            Label("上传 PDF / Word / Excel / 代码到项目知识库", systemImage: "doc.badge.plus")
                        }
                    }
                    .disabled(importing)

                    ForEach(draft.knowledgeDocs) { doc in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(doc.filename).font(.subheadline.weight(.medium)).lineLimit(1)
                                Text(doc.summaryBadge).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                draft.knowledgeDocs.removeAll { $0.id == doc.id }
                            } label: {
                                Image(systemName: "trash").font(.caption)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: Self.allowedDocTypes, allowsMultipleSelection: true) { result in
                guard case .success(let urls) = result else { return }
                let picked = Array(urls.prefix(4))
                importing = true
                Task {
                    let parsed: [WuMindProjectDoc] = await Task.detached(priority: .userInitiated) {
                        var out: [WuMindProjectDoc] = []
                        for url in picked {
                            let granted = url.startAccessingSecurityScopedResource()
                            defer { if granted { url.stopAccessingSecurityScopedResource() } }
                            if let data = try? Data(contentsOf: url),
                               let extracted = try? WuMindAttachmentParser.extract(data: data, filename: url.lastPathComponent) {
                                out.append(WuMindProjectDoc(
                                    filename: extracted.filename,
                                    kindRaw: extracted.kind.rawValue,
                                    summaryBadge: extracted.summaryBadge,
                                    extractedText: extracted.extractedText
                                ))
                            }
                        }
                        return out
                    }.value
                    await MainActor.run {
                        draft.knowledgeDocs.append(contentsOf: parsed)
                        importing = false
                    }
                }
            }
            .navigationTitle(existing == nil ? "新建项目空间" : "编辑项目空间")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存并进入") {
                        let cleanName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !cleanName.isEmpty else { return }
                        draft.name = cleanName
                        let cleanRepo = repoInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        draft.attachedRepoFullName = cleanRepo.isEmpty ? nil : cleanRepo
                        let saved = store.saveProject(draft)
                        store.selectProject(saved.id, startFreshChat: existing == nil)
                        dismiss()
                    }
                    .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// MARK: - 3. Scheduled Tasks / Automations Hub

struct WuMindSchedulesSheet: View {
    @ObservedObject var store: WuMindStore
    @Environment(\.dismiss) private var dismiss

    @State private var creating = false
    @State private var editingTask: WuMindScheduledTask? = nil
    @State private var pullingCloud = false
    @State private var cloudPullNote: String? = nil

    var body: some View {
        NavigationStack {
            List {
                Section {
                    WuMindHubHeroBanner(
                        title: "自动化定时任务",
                        subtitle: "区分单次 / 每天 / 每周与仅到点提醒 / AI 自动执行；内置通道经服务端确认后按北京时间锁屏准点执行且防重",
                        icon: "clock.arrow.circlepath",
                        colors: [Color(red: 0.88, green: 0.40, blue: 0.14), Color(red: 0.62, green: 0.24, blue: 0.72)],
                        chips: [
                            ("已安排", "\(store.scheduledTasks.filter { $0.supportsLockScreenCloudExecution }.count) 项"),
                            ("暂停/结束", "\(store.scheduledTasks.filter { !$0.enabled || $0.serverStatus == "completed" || $0.serverStatus == "cancelled" }.count) 项"),
                            ("全部任务", "\(store.scheduledTasks.count) 项")
                        ]
                    )
                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                    .listRowBackground(Color.clear)
                }

                Section {
                    Button {
                        Haptics.tap()
                        creating = true
                    } label: {
                        HStack(spacing: 11) {
                            WuMindIconBadge(icon: "clock.badge.plus", color: .orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("新建定时任务")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.primary)
                                Text("明确选择「仅一次 / 每天 / 每周」与「AI 自动执行 / 仅到点提醒」")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .accessibilityIdentifier("wumind.schedules.create")

                    Button {
                        Haptics.tap()
                        pullCloudResults()
                    } label: {
                        HStack(spacing: 11) {
                            if pullingCloud {
                                ProgressView().controlSize(.small).frame(width: 30, height: 30)
                            } else {
                                WuMindIconBadge(icon: "icloud.and.arrow.down", color: .teal)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pullingCloud ? "正在同步云端定时执行记录…" : "刷新云端状态与执行记录")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text("拉取锁屏期间 Cloudflare Cron 的独立执行记录与结果")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(pullingCloud || !store.hasGatewayURL)
                    .accessibilityIdentifier("wumind.schedules.pullCloud")

                    if let note = cloudPullNote {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("只有服务端返回确认后才会显示「已安排」；单次任务最多执行 1 次并自动结束，绝不重复触发或重复扣费。自有 Key 模式不会悄悄切到内置付费通道，暂不支持云端锁屏执行。")
                }

                Section("已配置定时任务（\(store.scheduledTasks.count)）") {
                    if store.scheduledTasks.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("暂无定时任务")
                                .font(.subheadline.weight(.semibold))
                            Text("例如：明天早 08:30（仅一次）汇总重点事项、每天早 08:30（北京时间）值班提醒、或仅到点提醒不调模型。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    } else {
                        ForEach(store.scheduledTasks) { task in
                            scheduleRow(task)
                        }
                    }
                }
            }
            .navigationTitle("定时任务中心")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(isPresented: $creating) {
                WuMindScheduleEditorSheet(store: store, existing: nil)
            }
            .sheet(item: $editingTask) { task in
                WuMindScheduleEditorSheet(store: store, existing: task)
            }
            .task {
                if store.hasGatewayURL && Keychain.wumindGatewayUserToken != nil {
                    _ = try? await store.pullCloudCronResults()
                }
            }
        }
        .accessibilityIdentifier("wumind.schedules.sheet")
    }

    private func badgeColor(for task: WuMindScheduledTask) -> Color {
        if task.serverStatus == "completed" { return .green }
        if task.serverStatus == "cancelled" { return .secondary }
        if !task.enabled || task.serverStatus == "paused" { return .orange }
        if !task.isManagedCloudTask { return .orange }
        if task.serverConfirmed { return .teal }
        if task.syncError != nil || task.serverStatus == "sync_failed" { return .red }
        return .indigo
    }

    private func scheduleRow(_ task: WuMindScheduledTask) -> some View {
        let isRunning = store.runningScheduleID == task.id
        let bColor = badgeColor(for: task)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.subheadline.weight(.semibold))
                    HStack(spacing: 6) {
                        Text(task.statusBadgeTitle)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(bColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(bColor.opacity(0.14), in: Capsule())

                        Text(task.executionMode.displayTitle)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(Color.secondary.opacity(0.11), in: Capsule())
                    }
                    HStack(spacing: 6) {
                        Text(task.cadence.displayLabel)
                        Text("·")
                        Text(task.isManagedCloudTask ? "内置云端" : "自有 Key（仅本机）")
                        if task.executionMode == .aiRun && !task.modelID.isEmpty {
                            Text("·")
                            Text(task.modelID)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                Spacer()
            }

            // Explicit Beijing Time next run + lock-screen capability line
            HStack(spacing: 6) {
                Image(systemName: task.supportsLockScreenCloudExecution ? "lock.shield.fill" : "clock")
                    .font(.caption2)
                    .foregroundStyle(task.supportsLockScreenCloudExecution ? .teal : .secondary)
                Text("下次执行：\(task.displayNextRunBeijingText)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.primary)
            }

            if !task.isManagedCloudTask {
                Label("自有 Key 暂不支持云端锁屏执行（不会悄悄切到内置付费通道）", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            if let syncError = task.syncError {
                HStack(spacing: 8) {
                    Text(syncError)
                        .font(.caption2)
                        .foregroundStyle(.red)
                    Spacer()
                    Button("重试同步") {
                        store.retrySyncScheduledTask(task.id)
                    }
                    .font(.caption2.weight(.bold))
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }

            Text(task.prompt)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            // Action Controls: Pause / Resume, Cancel, Edit, Manual Test Run
            HStack(spacing: 8) {
                if task.serverStatus != "completed" && task.serverStatus != "cancelled" {
                    Button {
                        Haptics.tap()
                        if task.enabled {
                            store.pauseScheduledTask(task.id)
                        } else {
                            store.resumeScheduledTask(task.id)
                        }
                    } label: {
                        Label(task.enabled ? "暂停" : "恢复", systemImage: task.enabled ? "pause.circle" : "play.circle")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color.orange.opacity(0.13), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("wumind.schedules.pause")

                    Button {
                        Haptics.tap()
                        store.cancelScheduledTask(task.id)
                    } label: {
                        Label("取消", systemImage: "xmark.circle")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color.red.opacity(0.12), in: Capsule())
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("wumind.schedules.cancel")
                }

                Button {
                    Haptics.tap()
                    Task { @MainActor in
                        await store.runScheduledTaskNow(task, manualTrigger: true)
                    }
                } label: {
                    HStack(spacing: 4) {
                        if isRunning { ProgressView().controlSize(.mini) }
                        else { Image(systemName: "play.fill").font(.caption2) }
                        Text(isRunning ? "执行中…" : "手动试跑")
                            .font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.indigo.opacity(0.12), in: Capsule())
                    .foregroundStyle(.indigo)
                }
                .buttonStyle(.plain)
                .disabled(store.runningScheduleID != nil)

                Spacer()

                Button {
                    editingTask = task
                } label: {
                    Text("编辑")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Independent per-execution run history (with status, reason, cost, and View Result button)
            if !task.runs.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("执行记录（最近 \(min(task.runs.count, 5)) 次）")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    ForEach(task.runs.prefix(5)) { run in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(run.status.badgeLabel)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(run.status.isFailure ? Color.red : (run.status == .reminderSent ? Color.blue : Color.green))
                                Text(run.executedAtText)
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(String(format: "¥%.4f", run.costYuan))
                                    .font(.caption2.monospacedDigit().weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            if let reason = run.failureReason, !reason.isEmpty {
                                Text("原因：\(reason)")
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                            } else if let preview = run.answerPreview, !preview.isEmpty {
                                Text(preview)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            if let convoID = run.conversationID,
                               store.conversations.contains(where: { $0.id == convoID }) {
                                Button {
                                    Haptics.tap()
                                    store.openConversation(convoID)
                                    dismiss()
                                } label: {
                                    Label("查看本次结果", systemImage: "text.bubble")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.indigo)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(8)
                        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .padding(.top, 2)
            } else if let status = task.lastStatus {
                HStack(spacing: 8) {
                    Text("上次：\(status)")
                        .font(.caption2)
                        .foregroundStyle(status.contains("失败") || status.contains("不足") ? Color.red : Color.secondary)
                    if let cost = task.lastCostYuan {
                        Text(String(format: "· ¥%.4f", cost))
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.indigo)
                    }
                    if let convoID = task.lastConversationID,
                       store.conversations.contains(where: { $0.id == convoID }) {
                        Button("查看结果") {
                            store.openConversation(convoID)
                            dismiss()
                        }
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.indigo)
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                store.deleteScheduledTask(task.id)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private func pullCloudResults() {
        guard !pullingCloud else { return }
        pullingCloud = true
        cloudPullNote = nil
        Task { @MainActor in
            defer { pullingCloud = false }
            do {
                let count = try await store.pullCloudCronResults()
                cloudPullNote = count > 0
                    ? "已同步 \(count) 条云端定时执行记录至本机。"
                    : "已刷新云端状态，暂无新的待同步执行记录。"
            } catch {
                cloudPullNote = (error as? LocalizedError)?.errorDescription ?? "拉取云端定时记录失败。"
            }
        }
    }
}

private struct WuMindScheduleEditorSheet: View {
    @ObservedObject var store: WuMindStore
    let existing: WuMindScheduledTask?
    @Environment(\.dismiss) private var dismiss

    enum CadenceKind: String, CaseIterable {
        case once = "仅一次"
        case daily = "每天"
        case weekly = "每周"
        case interval = "间隔小时"
    }

    @State private var title: String
    @State private var prompt: String
    @State private var cadenceKind: CadenceKind
    @State private var executionMode: WuMindScheduleExecutionMode
    @State private var timeDate: Date
    @State private var weekday: Int
    @State private var intervalHours: Int
    @State private var channel: WuMindChannel
    @State private var modelID: String
    @State private var selectedProjectID: UUID?
    @State private var useAgent: Bool

    init(store: WuMindStore, existing: WuMindScheduledTask?) {
        self.store = store
        self.existing = existing
        _title = State(initialValue: existing?.title ?? "")
        _prompt = State(initialValue: existing?.prompt ?? "")
        _executionMode = State(initialValue: existing?.executionMode ?? .aiRun)
        _channel = State(initialValue: WuMindChannel(rawValue: existing?.channelRaw ?? store.channel.rawValue) ?? store.channel)
        _modelID = State(initialValue: existing?.modelID ?? (store.channel == .managed ? store.managedSelectedModelID : store.selectedModelID))
        _selectedProjectID = State(initialValue: existing?.projectID ?? store.activeProjectID)
        _useAgent = State(initialValue: existing?.useAgentMode ?? true)

        var initKind: CadenceKind = .once
        var initHour = 8
        var initMinute = 30
        var initWeekday = 2
        var initInterval = 6
        var initDate = Date().addingTimeInterval(3600)
        if let cad = existing?.cadence {
            switch cad {
            case .daily(let h, let m):
                initKind = .daily; initHour = h; initMinute = m
            case .weekly(let wd, let h, let m):
                initKind = .weekly; initWeekday = wd; initHour = h; initMinute = m
            case .intervalHours(let hrs):
                initKind = .interval; initInterval = hrs
            case .once(let d):
                initKind = .once; initDate = d
            }
        }
        if initKind != .once {
            let bjCal = WuMindScheduleCadence.beijingCalendar
            var comps = bjCal.dateComponents([.year, .month, .day], from: Date())
            comps.hour = initHour
            comps.minute = initMinute
            initDate = bjCal.date(from: comps) ?? Date()
        }
        _cadenceKind = State(initialValue: initKind)
        _timeDate = State(initialValue: initDate)
        _weekday = State(initialValue: initWeekday)
        _intervalHours = State(initialValue: initInterval)
    }

    private var previewNextBeijingText: String {
        let bjCal = WuMindScheduleCadence.beijingCalendar
        let comps = bjCal.dateComponents([.hour, .minute], from: timeDate)
        let h = comps.hour ?? 8
        let m = comps.minute ?? 30
        let cand: Date? = {
            switch cadenceKind {
            case .once: return timeDate
            case .daily: return WuMindScheduleCadence.daily(hour: h, minute: m).nextRunDate(after: Date())
            case .weekly: return WuMindScheduleCadence.weekly(weekday: weekday, hour: h, minute: m).nextRunDate(after: Date())
            case .interval: return WuMindScheduleCadence.intervalHours(intervalHours).nextRunDate(after: Date())
            }
        }()
        return cand.map { WuMindScheduleCadence.formatBeijingDate($0) } ?? "请选择未来时间"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("任务定义") {
                    TextField("任务名称（如：每日值班晨报）", text: $title)
                    TextEditor(text: $prompt)
                        .frame(minHeight: 110)
                    Picker("执行方式", selection: $executionMode) {
                        ForEach(WuMindScheduleExecutionMode.allCases, id: \.self) { m in
                            Text(m.displayTitle).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Picker("重复频率", selection: $cadenceKind) {
                        ForEach(CadenceKind.allCases, id: \.self) { k in
                            Text(k.rawValue).tag(k)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch cadenceKind {
                    case .once:
                        DatePicker("单次执行时间（北京时间）", selection: $timeDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    case .daily:
                        DatePicker("每日执行时间（北京时间）", selection: $timeDate, displayedComponents: .hourAndMinute)
                    case .weekly:
                        Picker("星期几", selection: $weekday) {
                            Text("周日").tag(1)
                            Text("周一").tag(2)
                            Text("周二").tag(3)
                            Text("周三").tag(4)
                            Text("周四").tag(5)
                            Text("周五").tag(6)
                            Text("周六").tag(7)
                        }
                        DatePicker("执行时间（北京时间）", selection: $timeDate, displayedComponents: .hourAndMinute)
                    case .interval:
                        Stepper("每 \(intervalHours) 小时执行一次", value: $intervalHours, in: 1...72)
                    }

                    HStack {
                        Text("下次执行时间")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(previewNextBeijingText)
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                } header: {
                    Text("触发周期（统一按北京时间 Asia/Shanghai 校验）")
                } footer: {
                    Text(cadenceKind == .once ? "「仅一次」任务到点最多执行 1 次并立即标记完成，绝不会重复触发或重复扣费。" : "周期任务每次到点后会自动推进到下一个北京时间周期。")
                }

                Section {
                    Picker("执行通道", selection: $channel) {
                        ForEach(WuMindChannel.allCases) { ch in
                            Text(ch.title).tag(ch)
                        }
                    }
                    if channel == .ownAPI {
                        Label("自有 Key 暂不支持云端锁屏执行；本任务仅保留在本机，绝不悄悄切到内置付费通道。", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Label("内置通道经服务端确认后支持锁屏云端执行；若余额不足会记录失败原因且 ¥0 扣费。", systemImage: "lock.shield.fill")
                            .font(.caption)
                            .foregroundStyle(.teal)
                    }
                    if executionMode == .aiRun {
                        TextField("模型 ID（如 deepseek-reasoner / deepseek-chat）", text: $modelID)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    if !store.projects.isEmpty {
                        Picker("关联项目空间", selection: $selectedProjectID) {
                            Text("不绑定项目").tag(UUID?.none)
                            ForEach(store.projects) { proj in
                                Text(proj.name).tag(UUID?.some(proj.id))
                            }
                        }
                    }
                    if executionMode == .aiRun {
                        Toggle("允许调用智能体工具", isOn: $useAgent)
                    }
                } header: {
                    Text("执行通道与锁屏能力说明")
                }
            }
            .navigationTitle(existing == nil ? "新建定时任务" : "编辑定时任务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !cleanTitle.isEmpty, !cleanPrompt.isEmpty else { return }
                        let bjCal = WuMindScheduleCadence.beijingCalendar
                        let comps = bjCal.dateComponents([.hour, .minute], from: timeDate)
                        let h = comps.hour ?? 8
                        let m = comps.minute ?? 30
                        let cadence: WuMindScheduleCadence = {
                            switch cadenceKind {
                            case .daily: return .daily(hour: h, minute: m)
                            case .weekly: return .weekly(weekday: weekday, hour: h, minute: m)
                            case .interval: return .intervalHours(intervalHours)
                            case .once: return .once(timeDate)
                            }
                        }()
                        let nextRun = cadence.nextRunDate(after: Date())
                        let task = WuMindScheduledTask(
                            id: existing?.id ?? UUID(),
                            title: cleanTitle,
                            prompt: cleanPrompt,
                            projectID: selectedProjectID,
                            modelID: executionMode == .reminderOnly ? "" : (modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "deepseek-reasoner" : modelID.trimmingCharacters(in: .whitespacesAndNewlines)),
                            channelRaw: channel.rawValue,
                            useAgentMode: executionMode == .aiRun && useAgent,
                            cadence: cadence,
                            executionMode: executionMode,
                            timezoneID: "Asia/Shanghai",
                            enabled: existing?.enabled ?? true,
                            nextRunAt: nextRun,
                            nextRunBeijingText: nextRun.map { WuMindScheduleCadence.formatBeijingDate($0) },
                            lastRunAt: existing?.lastRunAt,
                            lastStatus: existing?.lastStatus,
                            lastCostYuan: existing?.lastCostYuan,
                            lastTokens: existing?.lastTokens,
                            lastConversationID: existing?.lastConversationID,
                            cloudSynced: false,
                            serverConfirmed: false,
                            serverStatus: channel == .managed ? "pending_sync" : "local_only",
                            syncError: nil,
                            runs: existing?.runs ?? []
                        )
                        store.saveScheduledTask(task)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// MARK: - 4. WUMIND Independent Flagship Settings Center

struct WuMindSettingsSheet: View {
    @ObservedObject var store: WuMindStore
    var onOpenWallet: () -> Void
    var onOpenCustomizations: () -> Void
    var onOpenProjects: () -> Void
    var onOpenSchedules: () -> Void
    var onOpenModelHub: () -> Void
    var onOpenSync: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var newMemoryDraft = ""
    @State private var newMemoryCategory = "规则"
    @State private var newMemoryVersion = ""
    @State private var bindNewMemoryToActiveProject = false
    @State private var editingMemory: WuMindMemoryItem?
    @State private var editMemoryDraft = ""
    @State private var editMemoryCategory = "规则"
    @State private var editMemoryVersion = ""
    @State private var editMemoryProjectID: UUID?
    @State private var confirmingClearAll = false

    var body: some View {
        NavigationStack {
            Form {
                settingsHeroSection
                accountSection
                memorySection
                contextSection
                agentSection
                hubLinksSection
                performanceSection
            }
            .navigationTitle("WUMIND 设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .confirmationDialog("清空全部 WUMIND 本机对话历史？", isPresented: $confirmingClearAll, titleVisibility: .visible) {
                Button("清空全部历史", role: .destructive) {
                    store.deleteAllConversations()
                }
            }
            .sheet(item: $editingMemory) { item in
                NavigationStack {
                    Form {
                        Section("记忆 / 规则内容") {
                            Picker("分类", selection: $editMemoryCategory) {
                                ForEach(WuMindMemoryItem.standardCategories, id: \.self) { cat in
                                    Text(cat).tag(cat)
                                }
                            }
                            TextField("规则版本号（可选，如 v2026.11）", text: $editMemoryVersion)
                                .autocorrectionDisabled()
                            TextField("记忆或更正内容", text: $editMemoryDraft, axis: .vertical)
                                .lineLimit(3...6)
                        }
                        Section("生效范围（项目隔离）") {
                            Picker("作用范围", selection: $editMemoryProjectID) {
                                Text("全局（所有非无痕对话生效）").tag(UUID?.none)
                                ForEach(store.projects) { proj in
                                    Text("仅项目：\(proj.name)").tag(UUID?.some(proj.id))
                                }
                            }
                        }
                        Section {
                            Button("删除这条记忆", role: .destructive) {
                                store.deleteMemory(item.id)
                                editingMemory = nil
                            }
                        }
                    }
                    .navigationTitle("修改记忆与规则")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("取消") { editingMemory = nil }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("保存") {
                                store.updateMemory(
                                    item.id,
                                    content: editMemoryDraft,
                                    category: editMemoryCategory,
                                    ruleVersion: editMemoryVersion,
                                    projectID: editMemoryProjectID
                                )
                                editingMemory = nil
                            }
                            .disabled(editMemoryDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("wumind.settings.sheet")
    }

    private var settingsHeroSection: some View {
        Section {
            WuMindHubHeroBanner(
                title: store.preferences.userDisplayName.isEmpty ? "WUMIND 旗舰工作台" : "你好，\(store.preferences.userDisplayName)",
                subtitle: "多模型聚合 · 1M 上下文自动压缩 · 智能体护栏 · 端到端加密同步",
                icon: "sparkles",
                colors: [Color(red: 0.16, green: 0.24, blue: 0.56), Color(red: 0.44, green: 0.26, blue: 0.84)],
                chips: [
                    ("当前通道", store.channel.title),
                    ("上下文上限", store.maxContextLabel),
                    ("智能体护栏", String(format: "¥%.1f/次", store.preferences.agentMaxCostYuanPerRun))
                ]
            )
            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
            .listRowBackground(Color.clear)
        }
    }

    // 1. Account & Dual-Channel Metering
    private var accountSection: some View {
        Section("账户与双通道计费") {
            Picker("默认执行通道", selection: Binding(
                get: { store.channel },
                set: { store.setChannel($0) }
            )) {
                ForEach(WuMindChannel.allCases) { ch in
                    Text(ch.title).tag(ch)
                }
            }
            .pickerStyle(.segmented)

            Button {
                dismiss()
                onOpenWallet()
            } label: {
                HStack(spacing: 11) {
                    WuMindIconBadge(icon: "creditcard.fill", color: .indigo)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("WUMIND 钱包、用量统计与充值教程")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("Apple 内购 · 测试兑换码 · 余额与实时流水")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(store.managedBalanceYuan.map { String(format: "¥%.2f", $0) } ?? "查看")
                        .font(.caption.monospacedDigit().weight(.bold))
                        .foregroundStyle(.indigo)
                }
            }

            Button {
                dismiss()
                onOpenModelHub()
            } label: {
                HStack(spacing: 11) {
                    WuMindIconBadge(icon: "key.fill", color: .blue)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("自带 API Key 与中转站管理（5 家厂商）")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("支持联网真实验证与域名/错误码诊断")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // 2. Personalization & Versioned, Project-Isolated Long-Term Memory
    private var memorySection: some View {
        Section {
            TextField("你的称呼（可选，如 Kris）", text: Binding(
                get: { store.preferences.userDisplayName },
                set: { val in store.updatePreferences { $0.userDisplayName = val } }
            ))
            TextField("职业与背景（如：卫星测控工程师 / 架构师）", text: Binding(
                get: { store.preferences.userRoleBackground },
                set: { val in store.updatePreferences { $0.userRoleBackground = val } }
            ))
            TextField("默认回答风格偏好", text: Binding(
                get: { store.preferences.responseStyle },
                set: { val in store.updatePreferences { $0.responseStyle = val } }
            ))
            Toggle("启用跨对话长期记忆（Memory）", isOn: Binding(
                get: { store.preferences.memoryEnabled },
                set: { val in store.updatePreferences { $0.memoryEnabled = val } }
            ))

            if store.preferences.memoryEnabled {
                Picker("记忆/规则类型", selection: $newMemoryCategory) {
                    ForEach(WuMindMemoryItem.standardCategories, id: \.self) { cat in
                        Text(cat).tag(cat)
                    }
                }
                TextField("规则版本号（可选，如 v2026.11，冲突时说明采用哪版）", text: $newMemoryVersion)
                    .font(.caption)
                    .autocorrectionDisabled()
                if let activeProj = store.activeProject {
                    Toggle("仅限当前项目「\(activeProj.name)」生效（不跨项目串用）", isOn: $bindNewMemoryToActiveProject)
                        .font(.caption)
                }
                HStack(spacing: 8) {
                    TextField("添加站名表、规则、更正或偏好…", text: $newMemoryDraft)
                    Button("添加") {
                        let pid = bindNewMemoryToActiveProject ? store.activeProjectID : nil
                        store.addMemory(
                            content: newMemoryDraft,
                            category: newMemoryCategory,
                            ruleVersion: newMemoryVersion,
                            projectID: pid,
                            isTemporaryChat: false
                        )
                        newMemoryDraft = ""
                        newMemoryVersion = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                    .disabled(newMemoryDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ForEach(store.memories) { item in
                    let projName = item.projectID.flatMap { pid in store.projects.first(where: { $0.id == pid })?.name }
                    HStack(alignment: .top, spacing: 8) {
                        Button {
                            editMemoryDraft = item.content
                            editMemoryCategory = item.category
                            editMemoryVersion = item.ruleVersion ?? ""
                            editMemoryProjectID = item.projectID
                            editingMemory = item
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 5) {
                                    Text(item.category)
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.indigo)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1.5)
                                        .background(Color.indigo.opacity(0.12), in: Capsule())
                                    if let ver = item.ruleVersion, !ver.isEmpty {
                                        Text("版本 \(ver)")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(.teal)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 1.5)
                                            .background(Color.teal.opacity(0.12), in: Capsule())
                                    }
                                    Text(projName.map { "项目：\($0)" } ?? "全局")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }
                                Text(item.content)
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)

                        Button(role: .destructive) {
                            store.deleteMemory(item.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } header: {
            Text("个人画像、规则版本与长期记忆")
        } footer: {
            Text("点击任意一条记忆可直接修改内容、版本号或项目隔离范围；临时聊天绝不读取或写入长期记忆。")
        }
    }

    // 3. 1M Context Window & Claude Auto-Compaction
    private var contextSection: some View {
        Section("1M 超长上下文与 Claude 自动压缩") {
            Picker("上下文窗口上限", selection: Binding(
                get: { store.maxContextTokens },
                set: { store.setMaxContextTokens($0) }
            )) {
                Text("1M Tokens（旗舰）").tag(1_000_000)
                Text("512K Tokens").tag(512_000)
                Text("256K Tokens").tag(256_000)
                Text("128K Tokens").tag(128_000)
            }

            Toggle("自动压缩早期上下文（保留最近 6 轮原文）", isOn: Binding(
                get: { store.autoCompactContext },
                set: { store.setAutoCompactContext($0) }
            ))

            if store.autoCompactContext {
                Picker("自动压缩触发阈值", selection: Binding(
                    get: { store.preferences.autoCompactThresholdPercent },
                    set: { val in store.updatePreferences { $0.autoCompactThresholdPercent = val } }
                )) {
                    Text("70%（更省流量）").tag(70)
                    Text("80%（推荐 · Claude 默认）").tag(80)
                    Text("90%（极致保留原文）").tag(90)
                }
            }
        }
    }

    // 4. Multi-Step Agent & Cost/Traffic Guardrails
    private var agentSection: some View {
        Section {
            Toggle("新对话默认开启智能体模式", isOn: Binding(
                get: { store.preferences.agentEnabledByDefault },
                set: { val in
                    store.updatePreferences { $0.agentEnabledByDefault = val }
                    store.agentModeEnabled = val
                }
            ))

            Stepper("单次智能体最大步数：\(store.preferences.agentMaxSteps) 步", value: Binding(
                get: { store.preferences.agentMaxSteps },
                set: { val in store.updatePreferences { $0.agentMaxSteps = val } }
            ), in: 2...10)

            Picker("内置通道单次任务费用护栏", selection: Binding(
                get: { store.preferences.agentMaxCostYuanPerRun },
                set: { val in store.updatePreferences { $0.agentMaxCostYuanPerRun = val } }
            )) {
                Text("¥0.50 / 次（省钱）").tag(0.5)
                Text("¥2.00 / 次（推荐）").tag(2.0)
                Text("¥5.00 / 次（深度研发）").tag(5.0)
                Text("¥20.00 / 次（重度长任务）").tag(20.0)
            }
        } header: {
            Text("智能体能力与流量计费护栏")
        } footer: {
            Text("智能体每一步工具调用与推理均按真实 Token 累计计费并透明展示分步明细；达到费用或步数护栏后自动收敛总结，绝不失控扣费。")
        }
    }

    // 5. Flagship Modules Quick Links
    private var hubLinksSection: some View {
        Section("旗舰能力中心") {
            Button {
                dismiss()
                onOpenCustomizations()
            } label: {
                HStack(spacing: 11) {
                    WuMindIconBadge(icon: "puzzlepiece.extension.fill", color: .blue)
                    Text("定制中心（连接器市场与 Skills）")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("\(store.installedConnectorIDs.count) 已装")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Button {
                dismiss()
                onOpenProjects()
            } label: {
                HStack(spacing: 11) {
                    WuMindIconBadge(icon: "folder.fill", color: .indigo)
                    Text("项目空间（指令 + 持久知识库）")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("\(store.projects.count) 个项目")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Button {
                dismiss()
                onOpenSchedules()
            } label: {
                HStack(spacing: 11) {
                    WuMindIconBadge(icon: "clock.arrow.circlepath", color: .orange)
                    Text("定时任务中心（Automations）")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("\(store.scheduledTasks.filter(\.enabled).count) 运行中")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Button {
                dismiss()
                onOpenSync()
            } label: {
                HStack(spacing: 11) {
                    WuMindIconBadge(icon: "icloud.and.arrow.up.fill", color: .teal)
                    Text("跨设备端到端加密同步（iPhone ↔ iPad）")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(store.cloudSyncVersion > 0 ? "v\(store.cloudSyncVersion)" : "AES-256")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.teal)
                }
            }
            .accessibilityIdentifier("wumind.settings.sync")
        }
    }

    // 6. Performance, Background Running & Data Control
    private var performanceSection: some View {
        Section {
            Toggle("后台生成完成时推送本地通知", isOn: Binding(
                get: { store.preferences.backgroundNotificationsEnabled },
                set: { val in store.updatePreferences { $0.backgroundNotificationsEnabled = val } }
            ))
            Toggle("长文 60 FPS 流式流畅渲染引擎", isOn: Binding(
                get: { store.preferences.streamSmoothMode },
                set: { val in store.updatePreferences { $0.streamSmoothMode = val } }
            ))
            DisclosureGroup("本机性能拆解与调用轨迹（\(store.recentCallTraces.count) 条）") {
                if store.recentCallTraces.isEmpty {
                    Text("发送对话后会自动记录每轮的「端侧准备 / 附件 / 网关等待 / 收到首段 / 正文首次提交界面 / 停止响应」耗时与模型派发及上游回报。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    let s = store.latencySummaryForDiagnostics
                    VStack(alignment: .leading, spacing: 4) {
                        Text("阶段耗时 P50 / P95（最近 \(store.recentCallTraces.count) 次实测）")
                            .font(.caption.weight(.bold))
                        Text("端侧准备：P50 \(s.clientPrep.p50Ms)ms · P95 \(s.clientPrep.p95Ms)ms")
                            .font(.caption2.monospacedDigit())
                        if s.gatewayWait.count > 0 {
                            Text("网关等待：P50 \(s.gatewayWait.p50Ms)ms · P95 \(s.gatewayWait.p95Ms)ms")
                                .font(.caption2.monospacedDigit())
                        }
                        if s.upstreamTTFT.count > 0 {
                            Text("收到首段：P50 \(s.upstreamTTFT.p50Ms)ms · P95 \(s.upstreamTTFT.p95Ms)ms")
                                .font(.caption2.monospacedDigit())
                        }
                        if s.firstRender.count > 0 {
                            Text("正文首次提交界面：P50 \(s.firstRender.p50Ms)ms · P95 \(s.firstRender.p95Ms)ms")
                                .font(.caption2.monospacedDigit())
                        }
                        if s.stopLatency.count > 0 {
                            Text("停止响应：P50 \(s.stopLatency.p50Ms)ms · P95 \(s.stopLatency.p95Ms)ms")
                                .font(.caption2.monospacedDigit())
                        }
                    }
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)

                    ForEach(store.recentCallTraces.prefix(8)) { tr in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text("\(tr.selectedChannel) · \(tr.selectedModelID)")
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                Spacer()
                                Text(tr.isFidelityExact ? "证据一致" : (tr.providerModelStatus == "未核实" ? "未核实" : "需核对"))
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(tr.isFidelityExact ? .green : .orange)
                            }
                            Text("\(tr.modelDiagnosticSummary) · 通道：\(tr.upstreamRoute) · 思考参数：\(tr.thinkingParamSent) · 思考回传：\(tr.reasoningObserved == true ? "有证据" : "未核实") · 图片：\(tr.imagesSentCount)/\(tr.attachedImageCount)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(tr.timing.compactSummary)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }

                    Button {
                        if let data = try? JSONEncoder().encode(store.recentCallTraces),
                           let json = String(data: data, encoding: .utf8) {
                            UIPasteboard.general.setItems([["public.utf8-plain-text": json]], options: [.localOnly: true])
                            ToastCenter.shared.show("已复制最近 \(store.recentCallTraces.count) 条性能与调用轨迹 JSON", style: .success)
                        }
                    } label: {
                        Label("复制性能与调用轨迹（JSON）", systemImage: "doc.on.doc")
                            .font(.caption.weight(.semibold))
                    }
                }
            }
            .accessibilityIdentifier("wumind.settings.perfTraces")

            Button {
                let md = store.exportConversationsMarkdown()
                UIPasteboard.general.setItems([["public.utf8-plain-text": md]], options: [.localOnly: true])
                ToastCenter.shared.show("已复制全部对话（Markdown 格式）", style: .success)
            } label: {
                Label("导出全部对话记录（复制 Markdown）", systemImage: "square.and.arrow.up")
            }
            Button(role: .destructive) {
                confirmingClearAll = true
            } label: {
                Label("清空全部本机对话历史", systemImage: "trash")
            }
        } header: {
            Text("性能、后台运行与数据隐私")
        } footer: {
            Text("所有聊天记录、项目知识库与记忆仅保存在当前 iPhone/iPad 本地，API Key 与连接器凭据受系统 Keychain 保护；开启云端同步时会先在本机进行 AES-256-GCM 零知识加密。")
        }
    }
}

// MARK: - 5. Collapsible Multi-Step Agent Execution Trace Card (Zero-Jank Lightweight)

struct WuMindAgentTraceCard: View {
    let steps: [WuMindAgentStep]
    let activePhase: String?
    let isGenerating: Bool
    let elevatedSurface: Color
    let subtleBorder: Color

    @State private var expanded = false

    private var totals: WuMindAgentUsageTotals {
        WuMindAgentUsageTotals.aggregate(steps: steps)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                Haptics.tap()
                withAnimation(.easeInOut(duration: 0.2)) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    if isGenerating && activePhase != nil {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "cpu.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.purple)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(activePhase ?? "智能体已完成 \(steps.count) 步工具协同")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if !steps.isEmpty {
                            let tokText = WuMindAccountStatus.formatTokens(totals.totalTokens)
                            let costText = totals.costYuan > 0 ? String(format: " · 累计 ¥%.4f", totals.costYuan) : ""
                            Text("共 \(steps.count) 步 · \(tokText) Tok\(costText)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if !steps.isEmpty {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)

            if expanded && !steps.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(steps) { step in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: icon(for: step))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(step.succeeded ? Color.purple : Color.orange)
                                .frame(width: 18)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text("第 \(step.stepIndex) 步 · \(displayToolName(step.toolName))")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text(String(format: "%.1fs", max(0.1, step.durationSeconds)))
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.tertiary)
                                }
                                Text(step.toolSummary)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                let stepTok = step.promptTokens + step.completionTokens + step.reasoningTokens
                                if stepTok > 0 || step.costYuan > 0 {
                                    Text("本步 \(WuMindAccountStatus.formatTokens(stepTok)) Tok" + (step.costYuan > 0 ? String(format: " · ¥%.4f", step.costYuan) : ""))
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.indigo.opacity(0.85))
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(elevatedSurface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Color.purple.opacity(0.26), lineWidth: 1)
        )
        .accessibilityIdentifier("wumind.agent.trace")
    }

    private func icon(for step: WuMindAgentStep) -> String {
        switch step.phase {
        case .budgetStopped: return "shield.lefthalf.filled"
        case .synthesizing: return "sparkles"
        default:
            switch step.toolName {
            case "web_search": return "magnifyingglass.circle.fill"
            case "github_inspect": return "chevron.left.forwardslash.chevron.right"
            case "web_fetch": return "globe"
            case "calculator_verify": return "function"
            case "project_search": return "doc.text.magnifyingglass"
            case "duty_schedule_lookup": return "calendar"
            case "webhook_call": return "antenna.radiowaves.left.and.right"
            default: return "wrench.and.screwdriver"
            }
        }
    }

    private func displayToolName(_ raw: String) -> String {
        switch raw {
        case "web_search": return "联网深度搜索"
        case "github_inspect": return "GitHub 仓库检视"
        case "web_fetch": return "网页实时抓读"
        case "calculator_verify": return "精算验算"
        case "project_search": return "项目知识库检索"
        case "duty_schedule_lookup": return "值班排班查询"
        case "webhook_call": return "Webhook / MCP"
        case "final_synthesis": return "最终汇总"
        default: return raw
        }
    }
}
