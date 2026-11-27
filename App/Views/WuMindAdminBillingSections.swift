import PhotosUI
import SwiftUI

// MARK: - 1. AIHubMix Shared Pool Account Balance Card (Server-Side Manage Key Only)

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
                            .font(.largeTitle.weight(.semibold).monospacedDigit())
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

                // Strictly preserves last cached balance on failure ("上次余额 · 同步失败"), NEVER resets to $0
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
            Text("仅服务端使用独立 Manage Key（AIHUBMIX_MANAGE_KEY）查询 AIHubMix 账号共享池余额，绝不打包进 App；刷新失败时保留上次缓存值并显示明确错误原因，绝不误显示 ¥0 / $0。")
        }
    }
}

// MARK: - 2. Dedicated User Management Page (用户与账单: All Users, Today New, Search, Pagination 201+, Detail & Direct Credit)

struct WuMindAdminUsersPage: View {
    let gatewayURL: String
    let adminSecret: String

    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var users: [WuMindAdminUserRecord] = []
    @State private var allUsersCount: Int?
    @State private var matchedCount = 0
    @State private var todayNewUsers: Int?
    @State private var rechargedUsersCount: Int?
    @State private var currentPage = 1
    @State private var hasMore = false
    @State private var searchQuery = ""
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorMsg: String? = nil

    var body: some View {
        List {
            Section {
                LabeledContent("注册用户", value: allUsersCount.map { String($0) } ?? "—")
                LabeledContent("今日新增", value: todayNewUsers.map { String($0) } ?? "—")
                LabeledContent("已充值", value: rechargedUsersCount.map { String($0) } ?? "—")
            } header: {
                Text("用户概况")
            }

            if let errorMsg {
                Section {
                    Label(errorMsg, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                }
            }

            Section {
                if users.isEmpty && isLoading {
                    ProgressView("正在加载用户")
                } else if users.isEmpty && errorMsg == nil {
                    Text(searchQuery.isEmpty ? "还没有注册用户。" : "没有找到匹配的用户。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(users) { u in
                        NavigationLink {
                            WuMindAdminUserDetailPage(
                                gatewayURL: gatewayURL,
                                adminSecret: adminSecret,
                                initialUser: u,
                                onUpdated: {
                                    Task { await loadUsers(page: 1, reset: true) }
                                }
                            )
                        } label: {
                            userRow(u)
                        }
                        .accessibilityIdentifier("wumind.admin.userRow.\(u.userID)")
                    }
                }

                if hasMore {
                    Button {
                        Task { await loadUsers(page: currentPage + 1, reset: false) }
                    } label: {
                        HStack {
                            Spacer()
                            if isLoadingMore {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("加载更多（已显示 \(users.count) / \(matchedCount) 人）")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.indigo)
                            }
                            Spacer()
                        }
                    }
                    .disabled(isLoadingMore)
                    .accessibilityIdentifier("wumind.admin.users.loadMore")
                }
            } header: {
                Text("用户列表 · 最近注册优先")
            }
        }
        .appList()
        .scrollDismissesKeyboard(.interactively)
        .hidesFloatingTabBar()
        .navigationTitle("用户与账单")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .searchable(text: $searchQuery, prompt: "按昵称或 WM- 账号 ID 搜索")
        .onSubmit(of: .search) {
            Task { await loadUsers(page: 1, reset: true) }
        }
        .onChange(of: searchQuery) { newVal in
            if newVal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Task { await loadUsers(page: 1, reset: true) }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await loadUsers(page: 1, reset: true) }
                } label: {
                    if isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(isLoading)
                .accessibilityLabel("刷新用户列表")
            }
        }
        .task {
            await loadUsers(page: 1, reset: true)
        }
    }

    private func userRow(_ u: WuMindAdminUserRecord) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Space.xs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: DS.Space.s))
        return VStack(alignment: .leading, spacing: DS.Space.xs) {
            layout {
                Text(u.displayName.isEmpty ? "未命名用户" : u.displayName)
                    .font(DS.Font.title)
                Text(String(format: "可用 ¥%.2f", u.availableYuan ?? u.balanceYuan))
                    .font(DS.Font.body.monospacedDigit())
            }
            Text(u.userID).font(DS.Font.caption.monospaced())
            if u.isBillingExempt { Label("免扣费", systemImage: "checkmark.shield") }
            Text(String(format: "实付 ¥%.2f · 赠额 ¥%.2f · 消费 ¥%.4f",
                        u.purchasedRechargedYuan ?? 0, u.adminGrantedYuan ?? 0, u.totalSpentYuan))
            Text("\(roleLabel(u.registeredRole)) · 调用 \(u.requestCount ?? 0) 次 · 注册于 \(String((u.createdAt ?? "—").prefix(16)))")
        }
        .font(DS.Font.caption)
        .foregroundStyle(.primary)
        .padding(.vertical, DS.Space.xs)
    }

    private func roleLabel(_ raw: String?) -> String {
        switch raw {
        case "internal_duty", "rosterMember": return "值班成员"
        case "external", "externalUser": return "外部用户"
        case "admin": return "管理员"
        default: return "注册用户"
        }
    }

    private func loadUsers(page: Int, reset: Bool) async {
        if reset {
            isLoading = true
        } else {
            isLoadingMore = true
        }
        errorMsg = nil
        defer {
            isLoading = false
            isLoadingMore = false
        }
        do {
            let res = try await WuMindGatewayClient().adminListUsers(
                gatewayURL: gatewayURL,
                adminSecret: adminSecret,
                query: searchQuery,
                page: page,
                limit: 50
            )
            if reset {
                users = res.users
            } else {
                let existingIDs = Set(users.map(\.userID))
                let fresh = res.users.filter { !existingIDs.contains($0.userID) }
                users.append(contentsOf: fresh)
            }
            matchedCount = res.totalUsers
            allUsersCount = res.allUsersCount ?? (searchQuery.isEmpty ? res.totalUsers : nil)
            todayNewUsers = res.todayNewUsers
            rechargedUsersCount = res.rechargedUsersCount
            currentPage = res.page ?? page
            hasMore = res.hasMore ?? false
        } catch {
            errorMsg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - 2B. User Detail Page (Gateway-Only Usage Breakdown + Direct In-Detail Credit Without Re-Typing ID)

struct WuMindAdminUserDetailPage: View {
    let gatewayURL: String
    let adminSecret: String
    let initialUser: WuMindAdminUserRecord
    var onUpdated: () -> Void = {}

    @State private var detail: WuMindAdminUserDetailResponse?
    @State private var isLoading = false
    @State private var errorMsg: String?
    @State private var statusMsg: String?

    // Direct in-detail credit flow (no re-entering WM- ID!)
    @State private var showingDirectCredit = false
    @State private var creditAmountDraft = "20"
    @State private var creditEnvironment = "production"
    @State private var creditNoteDraft = "管理员人工赠额"
    @State private var creditIdempotencyKey = ""
    @State private var showingCreditConfirm = false
    @State private var submittingCredit = false

    // Fee-waiver settings
    @State private var showingExemptSheet = false
    @State private var exemptCapDraft = "200"

    private var user: WuMindAdminUserRecord {
        detail?.user ?? initialUser
    }

    var body: some View {
        List {
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
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                }
            }

            // 1. Account Overview & Direct Credit CTA
            Section("账号与余额概览") {
                LabeledContent("昵称", value: user.displayName.isEmpty ? "未命名用户" : user.displayName)
                LabeledContent("WUMIND 账号", value: user.userID)
                LabeledContent("正式可用余额", value: String(format: "¥%.2f", user.availableYuan ?? user.balanceYuan))
                if let reserved = user.reservedYuan, reserved > 0 {
                    LabeledContent("任务预留冻结", value: String(format: "¥%.2f", reserved))
                }
                if let sandbox = user.sandboxBalanceYuan, sandbox > 0 {
                    LabeledContent("沙盒测试余额", value: String(format: "¥%.2f", sandbox))
                }
                LabeledContent("实付充值累计", value: String(format: "¥%.2f", user.purchasedRechargedYuan ?? 0))
                LabeledContent("管理员赠额累计", value: String(format: "¥%.2f", user.adminGrantedYuan ?? 0))
                LabeledContent("累计消费扣费", value: String(format: "¥%.4f", user.totalSpentYuan))
                if let refunded = user.refundedYuan, refunded > 0 {
                    LabeledContent("退款冲正", value: String(format: "¥%.2f", refunded))
                }

                HStack(spacing: 10) {
                    Button {
                        creditAmountDraft = "20"
                        creditEnvironment = "production"
                        creditNoteDraft = "管理员人工赠额"
                        showingDirectCredit = true
                    } label: {
                        Label("给此用户加余额", systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                    .accessibilityIdentifier("wumind.admin.userDetail.addCredit")

                    Button {
                        exemptCapDraft = String(format: "%.0f", user.dailyCostCapYuan ?? 200)
                        showingExemptSheet = true
                    } label: {
                        Label(user.isBillingExempt ? "免扣已开" : "免扣权限", systemImage: "shield.lefthalf.filled")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(user.isBillingExempt ? .purple : .secondary)
                }
                .padding(.vertical, 4)
            }

            // 2. Gateway-Only Usage Summary (Today / 7D / All-Time)
            if let summary = detail?.usageSummary {
                Section {
                    usageBucketRow(title: "今日（网关）", bucket: summary.today)
                    usageBucketRow(title: "近 7 天（网关）", bucket: summary.last7Days)
                    usageBucketRow(title: "累计（网关）", bucket: summary.allTime)
                } header: {
                    Text("WUMIND 网关用量统计")
                } footer: {
                    Text(detail?.scopeNote ?? "仅统计通过 WUMIND 内置计费网关发起的请求；自有 API Key 直连厂商产生的费用由厂商计费，不在此显示为 0。")
                }
            }

            // 3. Breakdown by Model & Kind
            if let byModel = detail?.breakdownByModel, !byModel.isEmpty {
                Section("按模型与类型分布") {
                    ForEach(byModel) { row in
                        modelBreakdownRow(row)
                    }
                }
            }

            // 4. Recent Admin Credit Audit Trail
            if let audits = detail?.recentAdminCredits, !audits.isEmpty {
                Section("管理员加余额审计记录") {
                    ForEach(audits) { a in
                        adminAuditRow(a)
                    }
                }
            }

            // 5. Recent Ledger Entries
            if let ledger = detail?.recentLedger, !ledger.isEmpty {
                Section("最近账单流水（最新 50 条）") {
                    ForEach(ledger) { item in
                        recentLedgerRow(item)
                    }
                }
            }
        }
        .appList()
        .hidesFloatingTabBar()
        .navigationTitle(user.displayName.isEmpty ? user.userID : user.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await loadDetail() }
                } label: {
                    if isLoading { ProgressView().controlSize(.small) }
                    else { Image(systemName: "arrow.clockwise") }
                }
            }
        }
        .sheet(isPresented: $showingDirectCredit) {
            directCreditSheet
        }
        .sheet(isPresented: $showingExemptSheet) {
            exemptConfigSheet
        }
        .task {
            await loadDetail()
        }
    }

    @ViewBuilder
    private func modelBreakdownRow(_ row: WuMindAdminUserModelBreakdown) -> some View {
        let subtitle = "\(row.kind) · \(row.requests) 次 · \(WuMindAccountStatus.formatTokens(row.tokens)) tokens"
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.model)
                    .font(.caption.monospaced().weight(.semibold))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "¥%.4f", row.spentYuan))
                    .font(.caption.monospacedDigit().weight(.bold))
                if row.upstreamYuan > 0 {
                    Text(String(format: "上游 ¥%.4f", row.upstreamYuan))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.purple)
                }
            }
        }
    }

    @ViewBuilder
    private func adminAuditRow(_ a: WuMindAdminCreditAuditRow) -> some View {
        let envLabel = a.environment == "sandbox" ? "沙盒" : "正式"
        let envColor: Color = a.environment == "sandbox" ? .orange : .green
        let timeLabel = String(a.createdAt.prefix(16))
        let summaryLine = String(
            format: "操作前 ¥%.2f → 后 ¥%.2f · 操作人 %@ · 单号 %@",
            a.balanceBeforeYuan,
            a.balanceAfterYuan,
            a.operatorID,
            a.id
        )
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(String(format: "+¥%.2f", a.amountYuan))
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(.orange)
                Text(envLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(envColor)
                Spacer()
                Text(timeLabel)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(summaryLine)
                .font(.caption2)
                .foregroundStyle(.secondary)
            if !a.note.isEmpty {
                Text(a.note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func recentLedgerRow(_ item: WuMindAdminUserLedgerItem) -> some View {
        let titleText = item.model.isEmpty ? item.kind : "\(item.kind) · \(item.model)"
        let timePrefix = String(item.createdAt.prefix(16))
        let subtitleText = item.note.isEmpty ? timePrefix : "\(timePrefix) · \(item.note)"
        let amountText = (item.costYuan > 0 ? "-¥" : "+¥") + String(format: "%.4f", abs(item.costYuan))
        let amountColor: Color = item.costYuan > 0 ? .primary : .green
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(titleText)
                    .font(.caption.weight(.semibold))
                Text(subtitleText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(amountText)
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(amountColor)
                Text(String(format: "余 ¥%.2f", item.balanceAfterYuan))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func usageBucketRow(title: String, bucket: WuMindAdminUserUsageBucket) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text("\(bucket.requests) 次请求 · \(WuMindAccountStatus.formatTokens(bucket.tokens)) tokens")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "¥%.4f", bucket.spentYuan))
                    .font(.subheadline.monospacedDigit().weight(.bold))
                if bucket.upstreamYuan > 0 {
                    Text(String(format: "上游 ¥%.4f", bucket.upstreamYuan))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.purple)
                }
            }
        }
    }

    private var directCreditSheet: some View {
        let parsedAmt = Double(creditAmountDraft.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let currentEnvBal = creditEnvironment == "sandbox" ? (user.sandboxBalanceYuan ?? 0) : user.balanceYuan
        return NavigationStack {
            Form {
                Section("目标用户（自动锁定，无需手填 ID）") {
                    LabeledContent("昵称", value: user.displayName.isEmpty ? "未命名用户" : user.displayName)
                    LabeledContent("账号 ID", value: user.userID)
                    LabeledContent("当前余额", value: String(format: "¥%.2f", currentEnvBal))
                }

                Section("加余额参数") {
                    Picker("入账环境", selection: $creditEnvironment) {
                        Text("正式余额 (Production)").tag("production")
                        Text("沙盒测试 (Sandbox)").tag("sandbox")
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Text("加款金额 ¥")
                        TextField("20", text: $creditAmountDraft)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    TextField("审计备注（如：测试赠额 / 补偿）", text: $creditNoteDraft)
                }

                if parsedAmt > 0 {
                    Section("入账前核对卡片") {
                        LabeledContent("本次加款", value: String(format: "+¥%.2f", parsedAmt))
                        LabeledContent("入账后预计余额", value: String(format: "¥%.2f", currentEnvBal + parsedAmt))
                    }
                }

                Section {
                    Button {
                        creditIdempotencyKey = "adm-direct-\(user.userID)-\(UUID().uuidString.prefix(10))"
                        showingCreditConfirm = true
                    } label: {
                        HStack {
                            Spacer()
                            if submittingCredit { ProgressView().controlSize(.small) }
                            Text("核对并提交加余额")
                                .font(.subheadline.weight(.bold))
                            Spacer()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(submittingCredit || parsedAmt <= 0 || parsedAmt > 500)
                } footer: {
                    Text("单次默认安全上限 ¥500；记为管理员人工赠额（admin_grant），绝不混入实付充值；含幂等键防重复点击多加。")
                }
            }
            .appList()
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("直接加余额")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showingDirectCredit = false }
                }
            }
            .alert("确认给「\(user.displayName.isEmpty ? user.userID : user.displayName)」加款？", isPresented: $showingCreditConfirm) {
                Button("取消", role: .cancel) {}
                Button("确认加款 ¥\(String(format: "%.2f", parsedAmt))") {
                    Task { await executeDirectCredit(amount: parsedAmt) }
                }
            } message: {
                Text("账号：\(user.userID)\n当前余额：¥\(String(format: "%.2f", currentEnvBal))\n入账后预计：¥\(String(format: "%.2f", currentEnvBal + parsedAmt))\n环境：\(creditEnvironment == "sandbox" ? "沙盒测试" : "正式余额")")
            }
        }
    }

    private var exemptConfigSheet: some View {
        NavigationStack {
            Form {
                Section("目标账号") {
                    LabeledContent("账号 ID", value: user.userID)
                    LabeledContent("当前状态", value: user.isBillingExempt ? "已开启管理员免充值" : "普通计费用户")
                }
                Section {
                    HStack {
                        Text("每日上游成本上限 (¥)")
                        Spacer()
                        TextField("200", text: $exemptCapDraft)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)
                            .multilineTextAlignment(.trailing)
                    }
                    Button {
                        Task { await setExempt(true) }
                    } label: {
                        Label("开通「管理员免充值」（余额 ¥0 可调用，仍记账）", systemImage: "checkmark.shield.fill")
                    }
                    .tint(.purple)

                    if user.isBillingExempt {
                        Button(role: .destructive) {
                            Task { await setExempt(false) }
                        } label: {
                            Label("撤销免充值（恢复正常预扣与结算）", systemImage: "xmark.shield.fill")
                        }
                    }
                }
            }
            .appList()
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("管理员免充值权限")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showingExemptSheet = false }
                }
            }
        }
    }

    private func loadDetail() async {
        isLoading = true
        errorMsg = nil
        defer { isLoading = false }
        do {
            detail = try await WuMindGatewayClient().adminFetchUserDetail(
                gatewayURL: gatewayURL,
                adminSecret: adminSecret,
                userID: initialUser.userID
            )
        } catch {
            errorMsg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func executeDirectCredit(amount: Double) async {
        submittingCredit = true
        errorMsg = nil
        defer { submittingCredit = false }
        do {
            let opID = WuMindStore.shared.managedAccountID.isEmpty ? "admin" : WuMindStore.shared.managedAccountID
            let res = try await WuMindGatewayClient().adminTopUpUser(
                gatewayURL: gatewayURL,
                adminSecret: adminSecret,
                userID: user.userID,
                amountYuan: amount,
                note: creditNoteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "管理员人工赠额" : creditNoteDraft,
                environment: creditEnvironment,
                operatorID: opID,
                idempotencyKey: creditIdempotencyKey
            )
            showingDirectCredit = false
            let newBal = creditEnvironment == "sandbox" ? (res.sandboxBalanceYuan ?? res.balanceYuan) : res.balanceYuan
            statusMsg = "服务端已确认：已为 \(res.userID) 加款 ¥\(String(format: "%.2f", amount))，最新余额 ¥\(String(format: "%.2f", newBal))（单号 \(res.auditID ?? "-")）。"
            await loadDetail()
            onUpdated()
        } catch {
            showingDirectCredit = false
            errorMsg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func setExempt(_ exempt: Bool) async {
        let cap = max(0, Double(exemptCapDraft) ?? 200)
        do {
            let res = try await WuMindGatewayClient().adminSetUserBillingExempt(
                gatewayURL: gatewayURL,
                adminSecret: adminSecret,
                userID: user.userID,
                exempt: exempt,
                dailyCostCapYuan: cap
            )
            statusMsg = res.billingExempt
                ? "已为 \(res.userID) 开启管理员免充值（每日上游上限 ¥\(String(format: "%.0f", res.dailyCostCapYuan))）。"
                : "已撤销 \(res.userID) 的免充值权限。"
            showingExemptSheet = false
            await loadDetail()
            onUpdated()
        } catch {
            errorMsg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            showingExemptSheet = false
        }
    }
}

// MARK: - 3. Unified 1.50× Server Pricing & Dynamic Model Catalog Page (模型定价)

struct WuMindAdminPricingPage: View {
    let gatewayURL: String
    let adminSecret: String
    var onCatalogUpdated: () -> Void = {}

    @State private var models: [WuMindCatalogModel] = []
    @State private var pricingMeta: WuMindPricingMeta?
    @State private var configuredUpstreams: [String] = []
    @State private var capabilityFilter: String = ""
    @State private var searchText: String = ""
    @State private var currentPage = 1
    @State private var totalCount = 0
    @State private var hasMore = false
    @State private var selectedIDs: Set<String> = []
    @State private var isBusy = false
    @State private var isLoadingMore = false
    @State private var statusMsg: String? = nil
    @State private var errorMsg: String? = nil

    // Preview & Approve 1.50× sync sheet
    @State private var pricingPreview: WuMindPricingPreviewResponse? = nil
    @State private var fxDraft = "7.25"
    @State private var approvingSync = false

    // Single-model toggle / detail edit sheet
    @State private var editingModel: WuMindCatalogModel? = nil
    @State private var enableDraft = false

    var body: some View {
        List {
            Section("当前定价") {
                if let meta = pricingMeta {
                    LabeledContent("服务倍率", value: String(format: "%.2f×", meta.markupMultiplier))
                    LabeledContent("美元汇率", value: String(format: "¥%.2f", meta.fxUsdToCny))
                    LabeledContent("定价版本", value: "v\(meta.priceVersion)")
                    LabeledContent("上次同步", value: formatTime(meta.lastSyncedAt))
                    if let count = meta.pricedCount { LabeledContent("已定价", value: "\(count)") }
                    if let count = meta.pendingPricingCount { LabeledContent("待定价", value: "\(count)") }
                } else {
                    Text(isBusy ? "正在加载定价信息…" : "暂无定价信息")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                AppPrimaryCTA(title: "预览 1.50× 定价", icon: "percent", isDisabled: isBusy) {
                    Task { await previewUniformPricingSync() }
                }
                .accessibilityIdentifier("wumind.admin.pricing.previewSync")
                Button {
                    Task { await discoverModels() }
                } label: {
                    Label("同步模型目录", systemImage: "arrow.triangle.2.circlepath")
                }
                .accessibilityIdentifier("wumind.admin.catalog.discover")
                if !selectedIDs.isEmpty {
                    Button {
                        Task { await probeSelected() }
                    } label: {
                        Label("测试所选的 \(selectedIDs.count) 个模型", systemImage: "waveform.path.ecg")
                    }
                    .accessibilityIdentifier("wumind.admin.catalog.probe")
                }
            } footer: {
                Text("按官方美元价 × 汇率 × 1.50 计算。待定价模型须先定价才能启用。自有通道按服务商计费。")
            }
            .disabled(isBusy)

            Section {
                Picker("模型能力", selection: $capabilityFilter) {
                    Text("全部").tag("")
                    Text("聊天").tag("chat")
                    Text("生图").tag("image")
                    Text("视频").tag("video")
                    Text("语音").tag("voice")
                }
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
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                }
            }

            Section("模型定价目录（共 \(totalCount) 个）") {
                if models.isEmpty && isBusy {
                    ProgressView("正在加载目录")
                } else if models.isEmpty && errorMsg == nil {
                    Text(searchText.isEmpty && capabilityFilter.isEmpty ? "暂无模型。可点「同步模型目录」获取目录。" : "没有符合当前条件的模型。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(models) { model in
                        modelRow(model)
                    }
                }

                if hasMore {
                    Button {
                        Task { await loadCatalog(page: currentPage + 1, reset: false) }
                    } label: {
                        HStack {
                            Spacer()
                            if isLoadingMore {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("加载更多（已显示 \(models.count) / \(totalCount) 个模型）")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.indigo)
                            }
                            Spacer()
                        }
                    }
                    .disabled(isLoadingMore)
                }
            }
        }
        .appList()
        .scrollDismissesKeyboard(.interactively)
        .hidesFloatingTabBar()
        .navigationTitle("模型定价")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .searchable(text: $searchText, prompt: "搜索模型 ID、名称或厂商")
        .onSubmit(of: .search) {
            Task { await loadCatalog(page: 1, reset: true) }
        }
        .onChange(of: capabilityFilter) { _ in
            Task { await loadCatalog(page: 1, reset: true) }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await loadCatalog(page: 1, reset: true) }
                } label: {
                    if isBusy { ProgressView().controlSize(.small) }
                    else { Image(systemName: "arrow.clockwise") }
                }
                .disabled(isBusy)
                .accessibilityLabel("刷新模型目录")
            }
        }
        .sheet(item: $editingModel) { m in
            editModelSheet(m)
        }
        .sheet(isPresented: Binding(
            get: { pricingPreview != nil },
            set: { if !$0 { pricingPreview = nil } }
        )) {
            if let preview = pricingPreview {
                pricingDiffApprovalSheet(preview)
            }
        }
        .task {
            await loadCatalog(page: 1, reset: true)
        }
    }

    private func modelRow(_ model: WuMindCatalogModel) -> some View {
        let selected = selectedIDs.contains(model.id)
        return VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text(model.displayName)
                .font(DS.Font.headline)
            Text("\(model.id) · \(model.resolvedVendor) · \(model.probeStatusTitle)")
                .font(DS.Font.caption.monospaced())
                .foregroundStyle(.secondary)
            if model.isCallable {
                Label("已上架", systemImage: "checkmark.circle")
            } else if model.isPendingPricing {
                Label("待定价", systemImage: "clock")
            }
            LabeledContent("计费单位", value: model.billingUnitLabel)
            LabeledContent("官方基准", value: model.officialPriceSummary)
            LabeledContent("WuMind 售价", value: model.pricingSummary)

            Button {
                if selected { selectedIDs.remove(model.id) }
                else if selectedIDs.count < 12 { selectedIDs.insert(model.id) }
            } label: {
                Label(selected ? "已选入测试" : "选入测试", systemImage: selected ? "checkmark.circle.fill" : "circle")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderless)
            .disabled(!selected && selectedIDs.count >= 12)
            .accessibilityLabel("\(selected ? "取消选择" : "选择")测试 \(model.displayName)")
            Button {
                editingModel = model
                enableDraft = model.enabled
            } label: {
                Label("管理启用状态", systemImage: "switch.2")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("管理 \(model.displayName) 启用状态")
        }
        .font(DS.Font.caption)
        .padding(.vertical, DS.Space.xs)
    }

    private func pricingDiffApprovalSheet(_ preview: WuMindPricingPreviewResponse) -> some View {
        NavigationStack {
            List {
                Section("同步预览摘要（批准后生效为 v\(preview.nextVersion)）") {
                    LabeledContent("统一倍率", value: String(format: "%.2f×", preview.markupMultiplier))
                    LabeledContent("换算汇率", value: String(format: "1 USD = ¥%.2f", preview.fxUsdToCny))
                    LabeledContent("本次价格变动", value: "\(preview.summary.changed) 个模型")
                    LabeledContent("保持不变", value: "\(preview.summary.unchanged) 个模型")
                    LabeledContent("无官方价（待定价）", value: "\(preview.summary.pendingPricing) 个模型")
                }

                Section {
                    Button {
                        Task { await approvePricingSync(preview: preview) }
                    } label: {
                        HStack {
                            Spacer()
                            if approvingSync { ProgressView().controlSize(.small) }
                            Text("批准并生效 v\(preview.nextVersion)（在途任务保留原价）")
                                .font(.subheadline.weight(.bold))
                            Spacer()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                    .disabled(approvingSync)
                    .accessibilityIdentifier("wumind.admin.pricing.approveConfirm")
                } footer: {
                    Text("批准后将把已核验的官方美元价 × \(String(format: "%.2f", preview.fxUsdToCny)) × \(String(format: "%.2f×", preview.markupMultiplier)) 写入服务端定价表；不会自动开启未实测模型；待定价模型保持停用。")
                }

                let changedItems = preview.diffs.filter { $0.changed || $0.pricingStatus == "pending_pricing" }
                Section("变动明细（共 \(changedItems.count) 项）") {
                    ForEach(changedItems.prefix(80)) { d in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(d.id).font(.caption.monospaced().weight(.semibold))
                                Spacer()
                                Text(d.pricingStatus == "priced" ? "1.50× 已计算" : "待定价")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(d.pricingStatus == "priced" ? .green : .orange)
                            }
                            if d.pricingMode == "token" {
                                Text(String(format: "旧：¥%.2f / ¥%.2f  →  新：¥%.2f / ¥%.2f (百万Token)",
                                            d.oldInputPricePerMillion, d.oldOutputPricePerMillion,
                                            d.newInputPricePerMillion, d.newOutputPricePerMillion))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(String(format: "旧：¥%.3f  →  新：¥%.3f (%@)",
                                            d.oldUnitPriceYuan, d.newUnitPriceYuan, d.pricingMode))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .appList()
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("核对 1.50× 价格变动")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { pricingPreview = nil }
                }
            }
        }
    }

    private func editModelSheet(_ model: WuMindCatalogModel) -> some View {
        NavigationStack {
            Form {
                Section("模型信息与定价（服务端 1.50× 统一计价）") {
                    LabeledContent("模型 ID", value: model.id)
                    LabeledContent("能力", value: model.capabilities.joined(separator: ", "))
                    LabeledContent("计费单位", value: model.billingUnitLabel)
                    LabeledContent("实测状态", value: model.probeStatusTitle)
                    LabeledContent("官方基准", value: model.officialPriceSummary)
                    LabeledContent("WUMIND 售价", value: model.pricingSummary)
                }
                Section {
                    Toggle("向用户端开放启用", isOn: $enableDraft)
                        .disabled(model.isPendingPricing || !model.isVerified)
                    if model.isPendingPricing {
                        Text("该模型处于「待定价」状态，禁止启用或按 ¥0 计费。请先完成官方价同步。")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else if !model.isVerified {
                        Text("该模型尚未通过权限与接口实测，请先勾选并点击「实测」。")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Button("保存开关状态") {
                        Task { await saveEnableToggle(model) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isBusy)
                }
            }
            .appList()
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("启用管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { editingModel = nil }
                }
            }
        }
    }

    private func formatTime(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "未同步" }
        return String(raw.prefix(16)).replacingOccurrences(of: "T", with: " ")
    }

    private func loadCatalog(page: Int, reset: Bool) async {
        if reset { isBusy = true } else { isLoadingMore = true }
        errorMsg = nil
        defer { isBusy = false; isLoadingMore = false }
        do {
            let res = try await WuMindGatewayClient().adminFetchCatalog(
                gatewayURL: gatewayURL,
                adminSecret: adminSecret,
                capability: capabilityFilter.isEmpty ? nil : capabilityFilter,
                query: searchText.isEmpty ? nil : searchText,
                page: page,
                limit: 50
            )
            if reset {
                models = res.models
            } else {
                let ids = Set(models.map(\.id))
                models.append(contentsOf: res.models.filter { !ids.contains($0.id) })
            }
            pricingMeta = res.pricingMeta
            configuredUpstreams = res.configuredUpstreams
            totalCount = res.totalCount
            currentPage = res.page ?? page
            hasMore = res.hasMore ?? false
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
            statusMsg = "已拉取供应商目录：共发现 \(res.totalDiscovered) 个模型（下线 \(res.totalDeprecated) 个），新模型默认未启用。"
            await loadCatalog(page: 1, reset: true)
            onCatalogUpdated()
        } catch {
            errorMsg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func previewUniformPricingSync() async {
        isBusy = true
        errorMsg = nil
        defer { isBusy = false }
        do {
            let fx = Double(fxDraft) ?? pricingMeta?.fxUsdToCny ?? 7.25
            pricingPreview = try await WuMindGatewayClient().adminPreviewPricingSync(
                gatewayURL: gatewayURL,
                adminSecret: adminSecret,
                fxUsdToCny: fx,
                markupMultiplier: 1.5
            )
        } catch {
            errorMsg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func approvePricingSync(preview: WuMindPricingPreviewResponse) async {
        approvingSync = true
        errorMsg = nil
        defer { approvingSync = false }
        do {
            let opID = WuMindStore.shared.managedAccountID.isEmpty ? "admin" : WuMindStore.shared.managedAccountID
            let res = try await WuMindGatewayClient().adminApprovePricingSync(
                gatewayURL: gatewayURL,
                adminSecret: adminSecret,
                fxUsdToCny: preview.fxUsdToCny,
                markupMultiplier: preview.markupMultiplier,
                operatorID: opID
            )
            pricingPreview = nil
            statusMsg = "已批准发布统一 \(String(format: "%.2f×", res.markupMultiplier)) 定价 v\(res.priceVersion)（变动 \(res.summary.changed) 个，待定价 \(res.summary.pendingPricing) 个）。"
            await loadCatalog(page: 1, reset: true)
            onCatalogUpdated()
        } catch {
            errorMsg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func probeSelected() async {
        let targets = Array(selectedIDs)
        guard !targets.isEmpty else { return }
        isBusy = true
        errorMsg = nil
        statusMsg = nil
        defer { isBusy = false }
        do {
            let res = try await WuMindGatewayClient().adminProbeModels(gatewayURL: gatewayURL, adminSecret: adminSecret, modelIDs: targets)
            let okCount = res.results.filter(\.isVerified).count
            statusMsg = "已完成 \(res.results.count) 个模型权限实测：\(okCount) 个通过，\(res.results.count - okCount) 个未通过。"
            selectedIDs.removeAll()
            await loadCatalog(page: 1, reset: true)
        } catch {
            errorMsg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func saveEnableToggle(_ model: WuMindCatalogModel) async {
        isBusy = true
        errorMsg = nil
        defer { isBusy = false }
        do {
            let res = try await WuMindGatewayClient().adminBatchUpdateModels(
                gatewayURL: gatewayURL,
                adminSecret: adminSecret,
                updates: [WuMindCatalogUpdatePatch(id: model.id, enabled: enableDraft)]
            )
            if let rej = res.rejected.first {
                errorMsg = "保存被服务端拒绝：\(rej.reason)"
            } else {
                statusMsg = "已更新 \(model.id) 启用状态。"
                editingModel = nil
                await loadCatalog(page: 1, reset: true)
                onCatalogUpdated()
            }
        } catch {
            errorMsg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - 4. Backward-Compatible Sheet Wrappers

struct WuMindAdminUserDirectorySheet: View {
    let gatewayURL: String
    let adminSecret: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            WuMindAdminUsersPage(gatewayURL: gatewayURL, adminSecret: adminSecret)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") { dismiss() }
                    }
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

struct WuMindAdminModelCatalogSheet: View {
    let gatewayURL: String
    let adminSecret: String
    let onCatalogUpdated: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            WuMindAdminPricingPage(
                gatewayURL: gatewayURL,
                adminSecret: adminSecret,
                onCatalogUpdated: onCatalogUpdated
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

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
            .appList()
            .scrollDismissesKeyboard(.interactively)
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
