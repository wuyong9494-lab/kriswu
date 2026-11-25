import SwiftUI

// MARK: - 1. Top Card: AIHubMix Shared Pool Account Balance (Server-Side Manage Key Only)

struct WuMindAdminUpstreamBalanceSection: View {
    let balance: WuMindAdminUpstreamBalance?
    let isLoading: Bool
    let isSavingThreshold: Bool
    @Binding var alertThresholdDraft: String
    let onRefresh: () -> Void
    let onSaveThreshold: () -> Void

    @Environment(\.openURL) private var openURL

    private var formattedUSD: String {
        if let usd = balance?.availableUSD {
            return String(format: "$%.2f", usd)
        }
        return "--"
    }

    private var formattedSyncTime: String {
        guard let raw = balance?.syncedAt, !raw.isEmpty else { return "未同步" }
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: raw) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return String(raw.prefix(16))
    }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("AIHubMix 可用余额")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(formattedUSD)
                            .font(.system(size: 30, weight: .black, design: .rounded).monospacedDigit())
                            .foregroundStyle(balance?.alertTriggered == true ? .red : .primary)
                            .accessibilityIdentifier("wumind.admin.aihubmixBalanceValue")
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        Button {
                            onRefresh()
                        } label: {
                            HStack(spacing: 4) {
                                if isLoading {
                                    ProgressView().controlSize(.mini)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                }
                                Text("刷新")
                            }
                            .font(.caption.weight(.bold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isLoading)
                        .accessibilityIdentifier("wumind.admin.aihubmixRefresh")

                        Button {
                            let urlStr = balance?.topUpURL ?? "https://console.aihubmix.com/topup"
                            if let url = URL(string: urlStr) {
                                openURL(url)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up.right.square")
                                Text("去充值")
                            }
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.indigo)
                        .controlSize(.small)
                        .accessibilityIdentifier("wumind.admin.aihubmixTopUp")
                    }
                }

                // Status line: strictly preserves last cached balance on failure ("上次余额 · 同步失败"), NEVER resets to $0
                HStack(spacing: 6) {
                    if balance?.syncFailed == true {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                        Text("\(balance?.statusLabel ?? "上次余额 · 同步失败") · 上次同步 \(formattedSyncTime)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    } else if let b = balance, b.configured {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                        Text("账号共享余额 · 上次同步 \(formattedSyncTime)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "key.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Text(balance?.statusLabel ?? "请在 Cloudflare Secrets 配置 AIHUBMIX_MANAGE_KEY 后点击刷新")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let used = balance?.usedUSD {
                        Text(String(format: "已用 $%.2f", used))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                if let b = balance, b.alertTriggered {
                    HStack(spacing: 8) {
                        Image(systemName: "bell.badge.fill")
                            .foregroundStyle(.white)
                        Text(String(format: "低余额报警：当前可用余额 $%.2f 已低于报警阈值 $%.2f，请及时前往 AIHubMix 充值！", b.availableUSD ?? 0, b.lowBalanceAlertUSD))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityIdentifier("wumind.admin.aihubmixAlertBanner")
                }

                if let err = balance?.syncError, !err.isEmpty {
                    Text("同步异常详情：\(err)")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                HStack(spacing: 8) {
                    Image(systemName: "bell.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text("低余额报警阈值 ($)")
                        .font(.caption.weight(.medium))
                    Spacer()
                    TextField("10", text: $alertThresholdDraft)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 78)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("wumind.admin.alertThresholdField")
                    Button("保存") {
                        onSaveThreshold()
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isSavingThreshold)
                    .accessibilityIdentifier("wumind.admin.alertThresholdSave")
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("API 账户余额（云端 Manage Key 实时查询）")
        } footer: {
            Text("仅服务端使用独立 Manage Key（AIHUBMIX_MANAGE_KEY）查询 AIHubMix 账号共享池余额，绝不打包进 App；刷新失败时保留上次缓存值并标注「同步失败」，绝不误显示 $0。")
        }
    }
}

// MARK: - 2. Dedicated Registered Users, Recharge, Usage & Admin Fee-Waiver Sheet

struct WuMindAdminUserDirectorySheet: View {
    let gatewayURL: String
    let adminSecret: String

    @Environment(\.dismiss) private var dismiss
    @State private var users: [WuMindAdminUserRecord] = []
    @State private var totalUsers = 0
    @State private var rechargedUsersCount = 0
    @State private var searchQuery = ""
    @State private var isLoading = false
    @State private var errorMsg: String? = nil
    @State private var statusMsg: String? = nil
    @State private var editingExemptUser: WuMindAdminUserRecord? = nil
    @State private var exemptDailyCapDraft = "200"

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        statPill(title: "已注册用户", value: "\(totalUsers) 人", tint: .blue)
                        statPill(title: "已充值用户", value: "\(rechargedUsersCount) 人", tint: .green)
                        statPill(
                            title: "免扣管理员",
                            value: "\(users.filter(\.isBillingExempt).count) 人",
                            tint: .purple
                        )
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }

                if let statusMsg {
                    Section {
                        Label(statusMsg, systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                }

                if let errorMsg {
                    Section {
                        Label(errorMsg, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("全部注册用户 · 充值 · 余额 · 消费与免扣权限") {
                    if users.isEmpty && !isLoading {
                        Text("暂无匹配的已注册用户记录。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(users) { u in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(u.displayName.isEmpty ? "未命名用户" : u.displayName)
                                                .font(.subheadline.weight(.bold))
                                            Text(u.userID)
                                                .font(.caption.monospaced().weight(.semibold))
                                                .foregroundStyle(.secondary)
                                            if u.isBillingExempt {
                                                Text("免扣管理员")
                                                    .font(.caption2.weight(.bold))
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Color.purple.opacity(0.15), in: Capsule())
                                                    .foregroundStyle(.purple)
                                            }
                                        }
                                        Text("身份：\(roleLabel(u.registeredRole)) · 注册：\(String((u.createdAt ?? "").prefix(16)))")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button(u.isBillingExempt ? "调整免扣" : "设免充值") {
                                        exemptDailyCapDraft = String(format: "%.0f", u.dailyCostCapYuan ?? 200)
                                        editingExemptUser = u
                                    }
                                    .font(.caption2.weight(.semibold))
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                                    .tint(u.isBillingExempt ? .purple : .indigo)
                                }

                                HStack(spacing: 12) {
                                    Text(String(format: "余额 ¥%.2f", u.balanceYuan))
                                        .font(.caption.monospacedDigit().weight(.bold))
                                        .foregroundStyle(.indigo)
                                    Text(String(format: "实购 ¥%.2f", u.purchasedRechargedYuan ?? 0))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.green)
                                    Text(String(format: "赠额 ¥%.2f", u.adminGrantedYuan ?? 0))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.orange)
                                }

                                HStack(spacing: 12) {
                                    Text("调用 \(u.requestCount ?? 0) 次")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text("Token \(WuMindAccountStatus.formatTokens(u.totalTokens ?? 0))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(String(format: "消费 ¥%.4f", u.totalSpentYuan))
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                    if let up = u.upstreamSpentYuan, up > 0 {
                                        Text(String(format: "上游成本 ¥%.4f", up))
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(.purple)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("注册用户与免扣管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .searchable(text: $searchQuery, prompt: "按 WM- 账号或姓名搜索")
            .onSubmit(of: .search) {
                Task { await loadUsers() }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await loadUsers() }
                    } label: {
                        if isLoading {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            .sheet(item: $editingExemptUser) { target in
                adminExemptSheet(for: target)
            }
            .task {
                await loadUsers()
            }
        }
    }

    private func adminExemptSheet(for target: WuMindAdminUserRecord) -> some View {
        NavigationStack {
            Form {
                Section("目标账号") {
                    LabeledContent("账号 ID", value: target.userID)
                    LabeledContent("姓名", value: target.displayName.isEmpty ? "未命名" : target.displayName)
                    LabeledContent("当前免扣状态", value: target.isBillingExempt ? "已开启免充值调用" : "普通计费用户")
                    LabeledContent("钱包余额", value: String(format: "¥%.2f", target.balanceYuan))
                }

                Section {
                    HStack {
                        Text("每日上游成本上限 (¥)")
                        Spacer()
                        TextField("200", text: $exemptDailyCapDraft)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)
                            .multilineTextAlignment(.trailing)
                    }
                    Button {
                        Task { await updateExempt(userID: target.userID, exempt: true) }
                    } label: {
                        Label("开通「管理员免充值」权限（余额 ¥0 可调用，仍记账）", systemImage: "checkmark.shield.fill")
                    }
                    .tint(.purple)

                    if target.isBillingExempt {
                        Button(role: .destructive) {
                            Task { await updateExempt(userID: target.userID, exempt: false) }
                        } label: {
                            Label("撤销免充值（立即恢复正常扣费与 402 限制）", systemImage: "xmark.shield.fill")
                        }
                    }
                } footer: {
                    Text("仅服务端校验已授权管理员账号免扣 App 钱包余额；所有对话/生图/视频/实时语音/PPT 仍记录完整模型、Token 与上游成本，并受限频及每日上游成本上限保护。")
                }
            }
            .navigationTitle("管理员免充值权限")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { editingExemptUser = nil }
                }
            }
        }
    }

    private func statPill(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.subheadline.bold()).foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
    }

    private func roleLabel(_ raw: String?) -> String {
        switch raw {
        case "internal_duty": return "值班内部成员"
        case "external": return "外部用户"
        case "admin": return "管理员"
        default: return "注册用户"
        }
    }

    private func loadUsers() async {
        isLoading = true
        errorMsg = nil
        defer { isLoading = false }
        do {
            let res = try await WuMindGatewayClient().adminListUsers(
                gatewayURL: gatewayURL,
                adminSecret: adminSecret,
                query: searchQuery
            )
            users = res.users
            totalUsers = res.totalUsers
            rechargedUsersCount = res.rechargedUsersCount
        } catch {
            errorMsg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func updateExempt(userID: String, exempt: Bool) async {
        let cap = max(0, Double(exemptDailyCapDraft) ?? 200)
        do {
            let res = try await WuMindGatewayClient().adminSetUserBillingExempt(
                gatewayURL: gatewayURL,
                adminSecret: adminSecret,
                userID: userID,
                exempt: exempt,
                dailyCostCapYuan: cap
            )
            statusMsg = res.billingExempt
                ? "已为 \(res.userID) 开启管理员免充值（每日上游上限 ¥\(String(format: "%.0f", res.dailyCostCapYuan))）。"
                : "已撤销 \(res.userID) 的管理员免充值权限，恢复正常计费。"
            editingExemptUser = nil
            await loadUsers()
        } catch {
            errorMsg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            editingExemptUser = nil
        }
    }
}

// MARK: - 3. Manual Admin Credit Confirmation Sheet (Audited, Separated from Real IAP)

struct WuMindAdminManualCreditConfirmSheet: View {
    let target: WuMindAdminUserRecord
    let amountYuan: Double
    let environment: String
    let note: String
    let isSubmitting: Bool
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var currentBalanceForEnv: Double {
        environment == "sandbox" ? (target.sandboxBalanceYuan ?? 0) : target.balanceYuan
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("请二次核对加余额信息") {
                    LabeledContent("目标账号", value: target.userID)
                    if !target.displayName.isEmpty {
                        LabeledContent("用户姓名", value: target.displayName)
                    }
                    LabeledContent("入账环境", value: environment == "sandbox" ? "沙盒测试余额 (Sandbox)" : "正式余额 (Production)")
                    LabeledContent("本次赠送金额", value: String(format: "+¥%.2f", amountYuan))
                    LabeledContent("操作前余额", value: String(format: "¥%.2f", currentBalanceForEnv))
                    LabeledContent("操作后预计余额", value: String(format: "¥%.2f", currentBalanceForEnv + amountYuan))
                    LabeledContent("审计备注", value: note.isEmpty ? "管理员人工赠额" : note)
                }

                Section {
                    Button {
                        onConfirm()
                    } label: {
                        HStack {
                            Spacer()
                            if isSubmitting { ProgressView().controlSize(.small) }
                            Text("确认给 \(target.userID) 加款 ¥\(String(format: "%.2f", amountYuan))")
                                .font(.subheadline.weight(.bold))
                            Spacer()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSubmitting)
                    .accessibilityIdentifier("wumind.admin.confirmTopUpButton")
                } footer: {
                    Text("账务隔离说明：本操作记为「管理员人工赠额（admin_grant）」，写入独立审计表 admin_credit_audit，严格不计入 Apple 内购真实营收。")
                }
            }
            .navigationTitle("确认给用户加余额")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

// MARK: - 4. Dynamic Model Catalog Console (Discover · Filter · Probe · Price · Batch Enable)

struct WuMindAdminModelCatalogSheet: View {
    let gatewayURL: String
    let adminSecret: String
    let onCatalogUpdated: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var models: [WuMindCatalogModel] = []
    @State private var configuredUpstreams: [String] = []
    @State private var capabilityFilter: String = ""
    @State private var searchText: String = ""
    @State private var selectedIDs: Set<String> = []
    @State private var isBusy = false
    @State private var statusMsg: String? = nil
    @State private var errorMsg: String? = nil
    @State private var editingModel: WuMindCatalogModel? = nil
    @State private var priceInDraft = ""
    @State private var priceOutDraft = ""
    @State private var unitPriceDraft = ""
    @State private var enableDraft = false

    private var filteredModels: [WuMindCatalogModel] {
        models.filter { m in
            let capOK = capabilityFilter.isEmpty || m.capabilities.contains(capabilityFilter)
            let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let qOK = q.isEmpty || m.id.lowercased().contains(q) || m.displayName.lowercased().contains(q) || m.resolvedVendor.lowercased().contains(q)
            return capOK && qOK
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("已配置上游 Key：\(configuredUpstreams.isEmpty ? "尚未同步" : configuredUpstreams.joined(separator: " / "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Button {
                                Task { await discoverModels() }
                            } label: {
                                Label("拉取供应商目录", systemImage: "arrow.triangle.2.circlepath")
                                    .font(.caption.weight(.bold))
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(isBusy)
                            .accessibilityIdentifier("wumind.admin.catalog.discover")

                            Button {
                                Task { await probeSelected() }
                            } label: {
                                Label("实测所选 (\(selectedIDs.count))", systemImage: "waveform.path.ecg")
                                    .font(.caption.weight(.bold))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(isBusy || selectedIDs.isEmpty)
                            .accessibilityIdentifier("wumind.admin.catalog.probe")
                        }
                    }
                    .padding(.vertical, 4)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            capChip("全部", value: "")
                            capChip("对话", value: "chat")
                            capChip("纯文生图", value: "text_to_image")
                            capChip("参考图编辑", value: "image_edit")
                            capChip("视频", value: "video")
                        }
                    }
                } header: {
                    Text("动态发现 · 实测验证 · 定价上线")
                } footer: {
                    Text("新拉取的模型默认「未实测、未启用」；服务端硬护栏强制要求通过真实接口实测且定价 > 0 后才允许向用户开放。")
                }

                if let statusMsg {
                    Section {
                        Label(statusMsg, systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                }
                if let errorMsg {
                    Section {
                        Label(errorMsg, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("候选模型（共 \(filteredModels.count) 个）") {
                    ForEach(filteredModels) { model in
                        HStack(alignment: .top, spacing: 10) {
                            Button {
                                if selectedIDs.contains(model.id) { selectedIDs.remove(model.id) }
                                else if selectedIDs.count < 12 { selectedIDs.insert(model.id) }
                            } label: {
                                Image(systemName: selectedIDs.contains(model.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedIDs.contains(model.id) ? .indigo : .secondary)
                            }
                            .buttonStyle(.plain)

                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(model.displayName)
                                        .font(.subheadline.weight(.semibold))
                                    if model.isCallable {
                                        Text("已上架")
                                            .font(.caption2.weight(.bold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 1)
                                            .background(Color.green.opacity(0.16), in: Capsule())
                                            .foregroundStyle(.green)
                                    }
                                }
                                Text("\(model.id) · \(model.resolvedProvider) · \(model.capabilities.joined(separator: "/"))")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 8) {
                                    Text(model.probeStatusTitle)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(model.isVerified ? .green : (model.probeStatus == "unverified" ? .orange : .red))
                                    Text(model.pricingSummary)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                if let msg = model.probeMessage, !msg.isEmpty {
                                    Text(msg)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            Spacer()
                            Button("定价/启用") {
                                editingModel = model
                                priceInDraft = String(format: "%.2f", model.inputPricePerMillion)
                                priceOutDraft = String(format: "%.2f", model.outputPricePerMillion)
                                unitPriceDraft = String(format: "%.2f", model.unitPriceYuan)
                                enableDraft = model.enabled
                            }
                            .font(.caption2.weight(.semibold))
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("动态模型目录管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .searchable(text: $searchText, prompt: "筛选模型 ID 或厂商")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await loadCatalog() }
                    } label: {
                        if isBusy { ProgressView().controlSize(.small) }
                        else { Image(systemName: "arrow.clockwise") }
                    }
                }
            }
            .sheet(item: $editingModel) { m in
                editModelSheet(m)
            }
            .task {
                await loadCatalog()
            }
        }
    }

    private func capChip(_ title: String, value: String) -> some View {
        let active = capabilityFilter == value
        return Button {
            capabilityFilter = value
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(active ? Color.indigo : Color(.tertiarySystemFill), in: Capsule())
                .foregroundStyle(active ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private func editModelSheet(_ model: WuMindCatalogModel) -> some View {
        NavigationStack {
            Form {
                Section("模型能力与实测状态") {
                    LabeledContent("模型 ID", value: model.id)
                    LabeledContent("能力", value: model.capabilities.joined(separator: ", "))
                    LabeledContent("计费模式", value: model.pricingMode)
                    LabeledContent("实测状态", value: model.probeStatusTitle)
                }
                Section("定价与启用开关") {
                    if model.pricingMode == "token" {
                        HStack {
                            Text("输入价 (¥/百万)")
                            Spacer()
                            TextField("输入价", text: $priceInDraft).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        }
                        HStack {
                            Text("输出价 (¥/百万)")
                            Spacer()
                            TextField("输出价", text: $priceOutDraft).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        }
                    } else {
                        HStack {
                            Text(model.pricingMode == "per_second" ? "单价 (¥/秒)" : "单价 (¥/张)")
                            Spacer()
                            TextField("单价", text: $unitPriceDraft).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        }
                    }
                    Toggle("向用户端开放启用", isOn: $enableDraft)
                    Button("保存定价与状态") {
                        Task { await saveModelPatch(model) }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle("配置模型")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { editingModel = nil }
                }
            }
        }
    }

    private func loadCatalog() async {
        isBusy = true
        errorMsg = nil
        defer { isBusy = false }
        do {
            let res = try await WuMindGatewayClient().adminFetchCatalog(gatewayURL: gatewayURL, adminSecret: adminSecret)
            models = res.models
            configuredUpstreams = res.configuredUpstreams
        } catch {
            errorMsg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func discoverModels() async {
        isBusy = true
        errorMsg = nil
        statusMsg = nil
        defer { isBusy = false }
        do {
            let res = try await WuMindGatewayClient().adminDiscoverModels(gatewayURL: gatewayURL, adminSecret: adminSecret)
            models = res.models
            statusMsg = "已从供应商同步 \(res.totalDiscovered) 个候选模型（下线 \(res.totalDeprecated) 个），新模型默认未启用。"
        } catch {
            errorMsg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func probeSelected() async {
        guard !selectedIDs.isEmpty else { return }
        isBusy = true
        errorMsg = nil
        statusMsg = nil
        defer { isBusy = false }
        do {
            let res = try await WuMindGatewayClient().adminProbeModels(
                gatewayURL: gatewayURL,
                adminSecret: adminSecret,
                modelIDs: Array(selectedIDs)
            )
            let okCount = res.results.filter(\.isVerified).count
            statusMsg = "实测完成：\(okCount) / \(res.results.count) 个模型通过真实接口与权限校验。"
            selectedIDs.removeAll()
            await loadCatalog()
        } catch {
            errorMsg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func saveModelPatch(_ model: WuMindCatalogModel) async {
        isBusy = true
        errorMsg = nil
        statusMsg = nil
        defer { isBusy = false }
        let patch = WuMindCatalogUpdatePatch(
            id: model.id,
            inputPricePerMillion: model.pricingMode == "token" ? (Double(priceInDraft) ?? 0) : nil,
            outputPricePerMillion: model.pricingMode == "token" ? (Double(priceOutDraft) ?? 0) : nil,
            unitPriceYuan: model.pricingMode != "token" ? (Double(unitPriceDraft) ?? 0) : nil,
            enabled: enableDraft
        )
        do {
            let res = try await WuMindGatewayClient().adminBatchUpdateModels(
                gatewayURL: gatewayURL,
                adminSecret: adminSecret,
                updates: [patch]
            )
            if let rej = res.rejected.first {
                errorMsg = "已拒绝启用 \(rej.id)：\(rej.reason)"
            } else {
                statusMsg = "已更新 \(model.id) 的定价与状态。"
                onCatalogUpdated()
            }
            editingModel = nil
            await loadCatalog()
        } catch {
            errorMsg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            editingModel = nil
        }
    }
}
