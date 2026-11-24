import PhotosUI
import SwiftUI
import UIKit

// MARK: - User-Facing WUMIND Wallet, Recharge QR & Live Pricing Sheet (Read-Only Config)

struct WuMindWalletSheet: View {
    @ObservedObject var store: WuMindStore
    @ObservedObject private var iap = WuMindIAPManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var voucherDraft = ""
    @State private var gatewayDraft = ""
    @State private var orderAmountDraft = "30"
    @State private var orderChannelDraft = "wechat"
    @State private var trackingOrderID: String?
    @State private var trackingAmountYuan: Double = 0
    @State private var checkingOrderNow = false
    @State private var orderPollTask: Task<Void, Never>?
    @State private var showingGuide = false
    @State private var busy = false
    @State private var feedback: String?
    @State private var errorMessage: String?

    private let quickAmounts = [10, 30, 68, 198]

    private var billingMode: WuMindBillingMode {
        store.managedConfig.resolvedBillingMode
    }

    var body: some View {
        NavigationStack {
            List {
                balanceOverviewSection
                if billingMode == .hybrid || billingMode == .appStoreIAP {
                    appleIAPSection
                }
                if billingMode == .hybrid || billingMode == .directQR {
                    automatedOrdersSection
                    voucherSection
                    qrRechargeSection
                }
                pricingTableSection
                ledgerSection
                gatewayEndpointSection
            }
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("WUMIND 钱包与计费")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        Haptics.tap()
                        showingGuide = true
                    } label: {
                        Label("充值教程", systemImage: "book.closed.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                    .accessibilityIdentifier("wumind.wallet.guideToolbar")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("收起键盘") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
            .sheet(isPresented: $showingGuide) {
                WuMindRechargeGuideSheet()
            }
            .onAppear {
                gatewayDraft = store.gatewayBaseURL
                if store.hasGatewayURL {
                    refreshAll()
                }
            }
            .onDisappear {
                stopOrderAutoPolling()
            }
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .active, let pendingID = trackingOrderID {
                    checkOrderOnce(pendingID, manual: false)
                }
            }
            .task {
                if billingMode == .hybrid || billingMode == .appStoreIAP {
                    await iap.loadProducts(for: store.managedConfig.resolvedIAPPacks)
                }
            }
        }
    }

    private var balanceOverviewSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                // Flagship Dark-Indigo Balance Card
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("WUMIND 可用余额")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.white.opacity(0.78))
                            Text(formattedBalance)
                                .font(.system(size: 32, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                                .accessibilityIdentifier("wumind.wallet.balance")
                        }
                        Spacer()
                        Button {
                            refreshAll()
                        } label: {
                            HStack(spacing: 4) {
                                if busy {
                                    ProgressView().tint(.white).controlSize(.mini)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                }
                                Text("刷新")
                            }
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.18), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(busy || !store.hasGatewayURL)
                    }

                    Button {
                        Haptics.tap()
                        showingGuide = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "questionmark.circle.fill")
                                .font(.subheadline)
                                .foregroundStyle(.white)
                            Text("新手必看：如何充值、兑换码与按 Token 透明计费教程")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color.white.opacity(0.75))
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("wumind.wallet.guide")
                }
                .padding(14)
                .background(
                    LinearGradient(
                        colors: [Color(red: 0.16, green: 0.22, blue: 0.56), Color(red: 0.36, green: 0.24, blue: 0.80)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )

                if let status = store.managedAccountStatus, status.totalRechargedYuan > 0 {
                    let ratio = min(1.0, max(0.0, status.balanceYuan / status.totalRechargedYuan))
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: ratio)
                            .tint(ratio < 0.15 ? .orange : .indigo)
                        HStack {
                            Text("剩余额度占比 \(Int((ratio * 100).rounded()))%")
                            Spacer()
                            Text("累计充值 ¥\(String(format: "%.2f", status.totalRechargedYuan))")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    walletStatTile(
                        title: "今日已用",
                        value: String(format: "¥%.4f", store.managedAccountStatus?.todaySpentYuan ?? 0),
                        sub: "\(WuMindAccountStatus.formatTokens(store.managedAccountStatus?.todayTokens ?? 0)) Tokens",
                        tint: .indigo
                    )
                    walletStatTile(
                        title: "累计 Token 用量",
                        value: WuMindAccountStatus.formatTokens(store.managedAccountStatus?.totalTokens ?? 0),
                        sub: "共 \(store.managedAccountStatus?.totalRequests ?? 0) 次对话",
                        tint: .blue
                    )
                    walletStatTile(
                        title: "累计消费金额",
                        value: String(format: "¥%.4f", store.managedAccountStatus?.totalSpentYuan ?? 0),
                        sub: "输入 \(WuMindAccountStatus.formatTokens(store.managedAccountStatus?.totalPromptTokens ?? 0)) · 输出 \(WuMindAccountStatus.formatTokens((store.managedAccountStatus?.totalCompletionTokens ?? 0) + (store.managedAccountStatus?.totalReasoningTokens ?? 0)))",
                        tint: .orange
                    )
                    walletStatTile(
                        title: "累计充值金额",
                        value: String(format: "¥%.2f", store.managedAccountStatus?.totalRechargedYuan ?? 0),
                        sub: store.managedAccountID.isEmpty ? "激活后实时同步" : "实时按 Token 扣费",
                        tint: .green
                    )
                }
                .accessibilityIdentifier("wumind.wallet.usageGrid")

                if !store.managedAccountID.isEmpty {
                    HStack(spacing: 8) {
                        Label("账号 ID：\(store.managedAccountID)", systemImage: "person.crop.circle.badge.checkmark")
                            .font(.footnote.monospaced().weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("复制 ID") {
                            UIPasteboard.general.setItems([["public.utf8-plain-text": store.managedAccountID]], options: [.localOnly: true])
                            ToastCenter.shared.show("已复制账号 ID", style: .success)
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                } else if store.hasGatewayURL {
                    Button {
                        activateAccount()
                    } label: {
                        Label("一键激活 WUMIND 内置账号", systemImage: "sparkles")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy)
                }

                if !store.managedConfig.announcement.isEmpty {
                    Text(store.managedConfig.announcement)
                        .font(.caption)
                        .foregroundStyle(.indigo)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.indigo.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var appleIAPSection: some View {
        Section {
            let packs = store.managedConfig.resolvedIAPPacks
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(packs) { pack in
                    let product = iap.productsByID[pack.id]
                    let isPurchasing = iap.purchasingProductID == pack.id
                    Button {
                        Haptics.tap()
                        Task { @MainActor in
                            await iap.purchase(pack: pack, store: store)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 4) {
                                Text(pack.title)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Spacer()
                                if let badge = pack.badge, !badge.isEmpty {
                                    Text(badge)
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1.5)
                                        .background(Color.indigo, in: Capsule())
                                }
                            }
                            Text(String(format: "到账 ¥%.0f", pack.creditYuan))
                                .font(.headline.monospacedDigit().weight(.black))
                                .foregroundStyle(.indigo)
                            HStack {
                                if isPurchasing {
                                    ProgressView().controlSize(.mini)
                                    Text("支付中…")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text(product?.displayPrice ?? pack.fallbackPriceLabel)
                                        .font(.caption.monospacedDigit().weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Image(systemName: "apple.logo")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.indigo.opacity(0.24), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(iap.purchasingProductID != nil)
                }
            }
            .padding(.vertical, 4)
            .accessibilityIdentifier("wumind.wallet.iapGrid")

            if let note = iap.statusNote, !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Apple 应用内购流量包（StoreKit 2 实时到账）")
        } footer: {
            Text("采用 Apple StoreKit 2 消耗型内购与 JWS 加密凭证核销，同一交易 ID 严格幂等防重，付款完成后自动充值至你的 WUMIND 余额。")
        }
    }

    private var voucherSection: some View {
        Section {
            HStack(spacing: 8) {
                TextField("输入充值兑换码（如 WM-XXXX-XXXX-XXXX）", text: $voucherDraft)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .font(.subheadline.monospaced())
                    .accessibilityIdentifier("wumind.wallet.voucherInput")
                Button("兑换") {
                    redeemCode()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(busy || voucherDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.hasGatewayURL)
            }
            if let feedback {
                Text(feedback)
                    .font(.footnote)
                    .foregroundStyle(.green)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.danger)
            }
        } header: {
            Text("兑换码秒充")
        }
    }

    private var qrRechargeSection: some View {
        Section {
            let wechatImg = WuMindAttachmentHelper.decodeBase64Image(store.managedConfig.wechatQRBase64)
            let alipayImg = WuMindAttachmentHelper.decodeBase64Image(store.managedConfig.alipayQRBase64)

            if wechatImg == nil && alipayImg == nil {
                VStack(alignment: .leading, spacing: 6) {
                    Label("管理员尚未上传收款二维码", systemImage: "qrcode")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text("管理员可在「设置 › 身份（登录管理员）› WUMIND 商业与计费管理」上传微信 / 支付宝收款码与自定义定价。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                HStack(spacing: 14) {
                    if let wechatImg {
                        qrCard(title: "微信收款码", color: .green, image: wechatImg)
                    }
                    if let alipayImg {
                        qrCard(title: "支付宝收款码", color: .blue, image: alipayImg)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }

            if !store.managedConfig.rechargeNote.isEmpty {
                Text(store.managedConfig.rechargeNote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if !store.managedConfig.contactNote.isEmpty {
                HStack {
                    Label("联系管理员：\(store.managedConfig.contactNote)", systemImage: "message.fill")
                        .font(.footnote.weight(.medium))
                    Spacer()
                    Button("复制") {
                        UIPasteboard.general.setItems([["public.utf8-plain-text": store.managedConfig.contactNote]], options: [.localOnly: true])
                        ToastCenter.shared.show("已复制联系方式", style: .success)
                    }
                    .font(.caption.weight(.semibold))
                }
            }
        } header: {
            Text("扫码充值（付款请备注上方账号 ID）")
        }
    }

    private var automatedOrdersSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: store.managedConfig.isAutoCheckoutEnabled ? "bolt.badge.checkmark.fill" : "clock.arrow.circlepath")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(store.managedConfig.isAutoCheckoutEnabled ? .green : .teal)
                    Text(store.managedConfig.isAutoCheckoutEnabled
                         ? "已开启自动到账收银台 · 支付后 3 秒内自动入账"
                         : "在线充值单 · 回调验签或查单后自动到账")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(store.managedConfig.isAutoCheckoutEnabled ? .green : .secondary)
                    Spacer()
                }

                // 4-column zero-overflow quick amount picker
                HStack(spacing: 8) {
                    ForEach(quickAmounts, id: \.self) { amt in
                        let selected = orderAmountDraft.trimmingCharacters(in: .whitespacesAndNewlines) == "\(amt)"
                        Button {
                            Haptics.select()
                            orderAmountDraft = "\(amt)"
                        } label: {
                            Text("¥\(amt)")
                                .font(.subheadline.monospacedDigit().weight(.bold))
                                .foregroundStyle(selected ? .white : .primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    selected ? Color.teal : Color.secondary.opacity(0.11),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .accessibilityIdentifier("wumind.wallet.quickAmounts")

                HStack(spacing: 8) {
                    Picker("通道", selection: $orderChannelDraft) {
                        Text("微信").tag("wechat")
                        Text("支付宝").tag("alipay")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 130)

                    HStack(spacing: 4) {
                        Text("¥")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.secondary)
                        TextField("自定义金额", text: $orderAmountDraft)
                            .keyboardType(.decimalPad)
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }

                Button {
                    createTrackedOrder()
                } label: {
                    HStack(spacing: 6) {
                        if busy {
                            ProgressView().tint(.white).controlSize(.small)
                        } else {
                            Image(systemName: store.managedConfig.isAutoCheckoutEnabled ? "bolt.fill" : "checkmark.shield.fill")
                        }
                        Text(store.managedConfig.isAutoCheckoutEnabled
                             ? "立即支付 ¥\(orderAmountDraft.isEmpty ? "30" : orderAmountDraft)（自动到账）"
                             : "创建自动到账充值单（¥\(orderAmountDraft.isEmpty ? "30" : orderAmountDraft)）")
                            .font(.subheadline.weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)
                .disabled(busy || !store.hasGatewayURL)
                .accessibilityIdentifier("wumind.wallet.createAutoOrder")

                if let activeID = trackingOrderID {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small).tint(.teal)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("正在自动检测到账（每 3 秒自动刷新）")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.teal)
                                Text("订单 \(activeID) · ¥\(String(format: "%.2f", trackingAmountYuan))，支付完成后切回本页即自动入账")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        HStack(spacing: 8) {
                            Button {
                                checkOrderOnce(activeID, manual: true)
                            } label: {
                                Label(checkingOrderNow ? "查单中…" : "立即检测到账", systemImage: "arrow.clockwise")
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.teal)
                            .controlSize(.mini)
                            .disabled(checkingOrderNow)

                            Button("复制单号") {
                                UIPasteboard.general.setItems([["public.utf8-plain-text": activeID]], options: [.localOnly: true])
                                ToastCenter.shared.show("已复制订单号", style: .success)
                            }
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.bordered)
                            .controlSize(.mini)

                            Spacer()

                            Button("停止检测") {
                                stopOrderAutoPolling()
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(11)
                    .background(Color.teal.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.teal.opacity(0.28), lineWidth: 1)
                    )
                }
            }
            .padding(.vertical, 4)

            if !store.managedPaymentOrders.isEmpty {
                ForEach(store.managedPaymentOrders.prefix(5)) { order in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(order.id)
                                .font(.caption.monospaced().weight(.semibold))
                            Text("\(order.channel == "alipay" ? "支付宝" : "微信") · \(order.status == "paid" ? "已自动到账" : "待支付回调")")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(order.status == "paid" ? .green : .orange)
                        }
                        Spacer()
                        Text(String(format: "¥%.2f", order.amountYuan))
                            .font(.subheadline.monospacedDigit().weight(.bold))
                        if order.status != "paid" {
                            Button("查单") {
                                trackingOrderID = order.id
                                trackingAmountYuan = order.amountYuan
                                startOrderAutoPolling(orderID: order.id)
                                checkOrderOnce(order.id, manual: true)
                            }
                            .font(.caption2.weight(.semibold))
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }
            }
        } header: {
            Text("微信 / 支付宝在线充值（自动秒到账）")
        } footer: {
            Text(store.managedConfig.paymentWebhookNote ?? "发起充值单后，网关支持易支付 / 彩虹易支付（/v1/webhooks/epay）及 HMAC-SHA256 回调（/v1/webhooks/payment）自动验签入账；切回 App 后 3 秒内自动刷新余额。")
        }
    }

    private var pricingTableSection: some View {
        Section {
            ForEach(store.enabledManagedModels) { item in
                let isSelected = store.channel == .managed && store.activeManagedModel?.id == item.id
                Button {
                    Haptics.select()
                    store.selectManagedModel(item)
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.displayName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("输入 ¥\(formatPrice(item.inputPricePerMillion)) / 百万 · 输出 ¥\(formatPrice(item.outputPricePerMillion)) / 百万")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.indigo)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            HStack {
                Label("智能体联网深度搜索（web_search）", systemImage: "magnifyingglass.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.teal)
                Spacer()
                Text(String(format: "¥%.3f / 次", store.managedConfig.resolvedWebSearchCostYuan))
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(.teal)
            }
        } header: {
            Text("WUMIND 内置模型实时计费价目表（点选即用）")
        } footer: {
            Text("每次对话结束后，网关按厂商返回的真实输入 / 输出 / 思考 Token 数毫秒级自动扣费；联网搜索按实际调用次数单独透明计费。")
        }
    }

    @ViewBuilder
    private var ledgerSection: some View {
        if let ledger = store.managedAccountStatus?.ledger, !ledger.isEmpty {
            Section("最近实时计费与充值流水") {
                ForEach(ledger.prefix(15)) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ledgerTitle(entry))
                                .font(.subheadline.weight(.medium))
                            if entry.kind == "chat" {
                                Text("输入 \(entry.promptTokens) · 输出 \(entry.completionTokens + entry.reasoningTokens) Tokens")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            } else if !entry.note.isEmpty {
                                Text(entry.note)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            let isCredit = entry.costYuan < 0
                            Text(isCredit
                                 ? "+¥\(String(format: "%.2f", abs(entry.costYuan)))"
                                 : "-¥\(String(format: "%.4f", entry.costYuan))")
                                .font(.subheadline.monospacedDigit().weight(.semibold))
                                .foregroundStyle(isCredit ? .green : .primary)
                            Text("余 ¥\(String(format: "%.2f", entry.balanceAfterYuan))")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var gatewayEndpointSection: some View {
        Section {
            HStack(spacing: 8) {
                TextField("输入管理员提供的 WUMIND 网关地址 (https://...)", text: $gatewayDraft)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(.caption)
                Button("连接") {
                    store.updateGatewayURL(gatewayDraft)
                    refreshAll()
                }
                .font(.caption.weight(.semibold))
                .disabled(busy || gatewayDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } header: {
            Text("WUMIND 计费网关地址")
        } footer: {
            Text("普通用户可随时在首页切换「自带 API」通道使用自己的密钥，或在「WUMIND 内置」通道使用云端实时计费服务。")
        }
    }

    private var formattedBalance: String {
        if let bal = store.managedBalanceYuan {
            return String(format: "¥%.2f", bal)
        }
        return store.hasGatewayURL ? "未激活" : "未连接网关"
    }

    private func formatPrice(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", value) : String(format: "%.2f", value)
    }

    private func ledgerTitle(_ entry: WuMindLedgerEntry) -> String {
        switch entry.kind {
        case "chat":
            if entry.model == "web_search" { return "联网深度搜索" }
            return entry.model.isEmpty ? "AI 对话" : entry.model
        case "web_search": return "联网深度搜索"
        case "schedule": return "云端定时任务"
        case "apple_iap": return "Apple 应用内购"
        case "webhook_topup": return "支付回调自动入账"
        case "redeem": return "兑换码充值"
        case "admin_topup": return "管理员扫码入账"
        case "welcome": return "新用户体验金"
        default: return entry.kind
        }
    }

    private func walletStatTile(title: String, value: String, sub: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.monospacedDigit().weight(.bold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(sub)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func qrCard(title: String, color: Color, image: UIImage) -> some View {
        VStack(spacing: 6) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 145, maxHeight: 145)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(color.opacity(0.35), lineWidth: 1.2))
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }

    private func activateAccount() {
        guard !busy else { return }
        busy = true
        errorMessage = nil
        feedback = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                try await store.syncManagedGatewayConfig()
                try await store.refreshManagedAccount()
                try? await store.refreshManagedPaymentOrders()
                feedback = "已激活账户 \(store.managedAccountID)。"
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? "激活失败，请检查网关地址与网络。"
            }
        }
    }

    private func refreshAll() {
        guard !busy, store.hasGatewayURL else { return }
        busy = true
        errorMessage = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                try await store.syncManagedGatewayConfig()
                if Keychain.wumindGatewayUserToken != nil {
                    try await store.refreshManagedAccount()
                    try? await store.refreshManagedPaymentOrders()
                }
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? "同步网关配置失败。"
            }
        }
    }

    private func createTrackedOrder() {
        guard !busy else { return }
        guard let amount = Double(orderAmountDraft.trimmingCharacters(in: .whitespacesAndNewlines)), amount >= 1 else {
            errorMessage = "请输入大于等于 ¥1 的有效金额。"
            return
        }
        busy = true
        errorMessage = nil
        feedback = nil
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        Task { @MainActor in
            defer { busy = false }
            do {
                let order = try await store.createManagedPaymentOrder(amountYuan: amount, channel: orderChannelDraft)
                UIPasteboard.general.setItems([["public.utf8-plain-text": order.id]], options: [.localOnly: true])
                trackingOrderID = order.id
                trackingAmountYuan = order.amountYuan
                startOrderAutoPolling(orderID: order.id)
                if let urlStr = order.checkoutURL, let payURL = URL(string: urlStr),
                   payURL.scheme?.lowercased() == "https" {
                    feedback = "已为你拉起在线支付（订单 \(order.id)），付款后切回 WUMIND 将自动到账！"
                    openURL(payURL)
                } else {
                    feedback = "已创建订单 \(order.id)（¥\(String(format: "%.2f", order.amountYuan))），单号已复制；正在每 3 秒自动检测到账。"
                }
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? "创建充值单失败。"
            }
        }
    }

    private func startOrderAutoPolling(orderID: String) {
        orderPollTask?.cancel()
        orderPollTask = Task { @MainActor in
            for _ in 0..<100 {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if Task.isCancelled { return }
                guard trackingOrderID == orderID else { return }
                do {
                    let result = try await store.checkManagedPaymentOrderStatus(orderID)
                    if result.isPaid {
                        handleOrderCredited(result)
                        return
                    }
                } catch {
                    // Keep polling silently on transient network blips
                }
            }
            if trackingOrderID == orderID {
                trackingOrderID = nil
            }
        }
    }

    private func stopOrderAutoPolling() {
        orderPollTask?.cancel()
        orderPollTask = nil
        trackingOrderID = nil
    }

    private func checkOrderOnce(_ orderID: String, manual: Bool) {
        guard !checkingOrderNow else { return }
        checkingOrderNow = true
        Task { @MainActor in
            defer { checkingOrderNow = false }
            do {
                let result = try await store.checkManagedPaymentOrderStatus(orderID)
                if result.isPaid {
                    handleOrderCredited(result)
                } else if manual {
                    ToastCenter.shared.show("尚未收到支付回调，请确认已完成付款后稍候片刻", style: .info)
                }
            } catch {
                if manual {
                    errorMessage = (error as? LocalizedError)?.errorDescription ?? "查单失败，请检查网络。"
                }
            }
        }
    }

    private func handleOrderCredited(_ result: WuMindPaymentOrderStatus) {
        stopOrderAutoPolling()
        Haptics.success()
        let msg = "充值已自动到账 +¥\(String(format: "%.2f", result.amountYuan))！"
        ToastCenter.shared.show(msg, style: .success)
        feedback = "\(msg) 当前最新余额 ¥\(String(format: "%.2f", result.balanceYuan))。"
    }

    private func redeemCode() {
        guard !busy else { return }
        let code = voucherDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        busy = true
        errorMessage = nil
        feedback = nil
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        Task { @MainActor in
            defer { busy = false }
            do {
                let status = try await store.redeemManagedVoucher(code)
                voucherDraft = ""
                feedback = "兑换成功！当前最新余额 ¥\(String(format: "%.2f", status.balanceYuan))。"
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? "兑换失败，请核对兑换码。"
            }
        }
    }
}

// MARK: - Admin-Only Pricing, Payment QR Code, Voucher & Top-Up Management Console

struct WuMindAdminBillingView: View {
    @EnvironmentObject private var appStore: AppStore
    @ObservedObject private var wumind = WuMindStore.shared

    @State private var gatewayURLDraft = ""
    @State private var adminSecretDraft = ""
    @State private var hasAdminSecret = false
    @State private var configDraft = WuMindCommercialConfig()

    @State private var wechatPickerItem: PhotosPickerItem?
    @State private var alipayPickerItem: PhotosPickerItem?

    @State private var addingModel = false
    @State private var newModelID = ""
    @State private var newModelProvider = "deepSeek"
    @State private var newModelName = ""
    @State private var newModelInputPrice = "10"
    @State private var newModelOutputPrice = "40"
    @State private var newModelThinking = true

    @State private var voucherAmount = "30"
    @State private var voucherCount = 1
    @State private var voucherNote = "扫码充值"
    @State private var generatedVouchers: [WuMindVoucher] = []

    @State private var topUpUserID = ""
    @State private var topUpAmount = "20"
    @State private var topUpNote = "微信/支付宝扫码入账"

    @State private var summary: WuMindAdminSummary?
    @State private var showingSetupGuide = false
    @State private var busy = false
    @State private var statusBanner: String?
    @State private var errorBanner: String?

    var body: some View {
        Group {
            if !appStore.canEdit {
                VStack(spacing: 14) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.secondary)
                    Text("仅管理员模式可编辑")
                        .font(.headline)
                    Text("定价策略、收款二维码与充值发卡仅限管理员登录后修改。请前往「设置 › 身份」输入管理员密码。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                adminForm
            }
        }
        .navigationTitle("WUMIND 商业计费管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if appStore.canEdit {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Haptics.tap()
                        showingSetupGuide = true
                    } label: {
                        Label("配置教程", systemImage: "book.closed.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                    .accessibilityIdentifier("wumind.admin.guideToolbar")
                }
            }
        }
        .sheet(isPresented: $showingSetupGuide) {
            WuMindAdminSetupGuideSheet()
        }
        .onAppear {
            gatewayURLDraft = wumind.gatewayBaseURL
            hasAdminSecret = Keychain.wumindGatewayAdminSecret != nil
            configDraft = wumind.managedConfig
        }
    }

    private var adminHeaderSection: some View {
        Section {
            Button {
                Haptics.tap()
                showingSetupGuide = true
            } label: {
                WuMindHubHeroBanner(
                    title: "管理员从零配置教程（6 步上线）",
                    subtitle: "含 Cloudflare Workers + D1 一键复制命令、厂商 Key 写入、加价定价、收款码、Webhook 与 Apple 内购完整指引",
                    icon: "crown.fill",
                    colors: [Color(red: 0.14, green: 0.18, blue: 0.34), Color(red: 0.36, green: 0.24, blue: 0.78)]
                )
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
            .listRowBackground(Color.clear)
            .accessibilityIdentifier("wumind.admin.guide")

            if let statusBanner {
                Label(statusBanner, systemImage: "checkmark.circle.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.green)
            }
            if let errorBanner {
                Label(errorBanner, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(DS.Palette.danger)
            }
        }
    }

    private var adminForm: some View {
        Form {
            adminHeaderSection

            // 1. Gateway Connection & Admin Secret
            Section {
                TextField("Cloudflare 网关地址（https://...workers.dev）", text: $gatewayURLDraft)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("wumind.admin.gatewayURL")

                SecureField(hasAdminSecret ? "管理员密钥已保存在本机钥匙串（输入可替换）" : "输入 Cloudflare Worker 的 ADMIN_SECRET",
                            text: $adminSecretDraft)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("wumind.admin.secret")

                HStack(spacing: 12) {
                    Button("保存连接信息") {
                        saveConnectionLocally()
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("拉取云端") {
                        pullCloudConfigAndSummary()
                    }
                    .buttonStyle(.bordered)
                    .disabled(busy)
                }
            } header: {
                Text("1. 云端计费网关（Cloudflare Workers + D1）")
            } footer: {
                Text("厂商真实 API Key 仅放在 Cloudflare Secrets 中，绝不打包进 App。管理员密钥仅存你当前设备的钥匙串。")
            }

            adminComplianceSection

            // 2. Payment QR Codes & Recharge Guidance
            Section {
                let wechatButtonTitle = configDraft.wechatQRBase64 == nil ? "上传微信码" : "更换微信码"
                let alipayButtonTitle = configDraft.alipayQRBase64 == nil ? "上传支付宝码" : "更换支付宝码"
                HStack(spacing: 16) {
                    VStack(spacing: 8) {
                        if let img = WuMindAttachmentHelper.decodeBase64Image(configDraft.wechatQRBase64) {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 112, height: 112)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        } else {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.green.opacity(0.10))
                                .frame(width: 112, height: 112)
                                .overlay(Image(systemName: "qrcode").font(.title).foregroundStyle(.green))
                        }
                        PhotosPicker(selection: $wechatPickerItem, matching: .images) {
                            Text(wechatButtonTitle)
                                .font(.caption.weight(.semibold))
                        }
                        if configDraft.wechatQRBase64 != nil {
                            Button("移除", role: .destructive) { configDraft.wechatQRBase64 = nil }
                                .font(.caption2)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 8) {
                        if let img = WuMindAttachmentHelper.decodeBase64Image(configDraft.alipayQRBase64) {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 112, height: 112)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        } else {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.blue.opacity(0.10))
                                .frame(width: 112, height: 112)
                                .overlay(Image(systemName: "qrcode").font(.title).foregroundStyle(.blue))
                        }
                        PhotosPicker(selection: $alipayPickerItem, matching: .images) {
                            Text(alipayButtonTitle)
                                .font(.caption.weight(.semibold))
                        }
                        if configDraft.alipayQRBase64 != nil {
                            Button("移除", role: .destructive) { configDraft.alipayQRBase64 = nil }
                                .font(.caption2)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 4)

                TextField("充值指引说明（如扫码备注账号 ID）", text: $configDraft.rechargeNote, axis: .vertical)
                    .lineLimit(2...4)
                    .font(.footnote)
                TextField("管理员联系微信号 / 方式（选填）", text: $configDraft.contactNote)
                    .font(.footnote)
                TextField("钱包顶部公告（选填）", text: $configDraft.announcement)
                    .font(.footnote)
            } header: {
                Text("2. 收款二维码与充值说明（仅管理员可改）")
            }

            // 3. Per-Model Custom Pricing Table (Higher than Official Cost)
            Section {
                HStack(spacing: 8) {
                    Text("一键调价：")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach([1.5, 2.0, 2.5, 3.0], id: \.self) { mult in
                        Button("\(String(format: "%.1f", mult))×") {
                            applyMultiplierToDefaults(mult)
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }

                ForEach($configDraft.pricing) { $item in
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(isOn: $item.enabled) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.displayName)
                                    .font(.subheadline.weight(.semibold))
                                Text("\(item.id) · \(item.officialReferenceNote)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("输入价 (¥/百万)").font(.caption2).foregroundStyle(.secondary)
                                TextField("输入价", value: $item.inputPricePerMillion, format: .number)
                                    .keyboardType(.decimalPad)
                                    .textFieldStyle(.roundedBorder)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("输出价 (¥/百万)").font(.caption2).foregroundStyle(.secondary)
                                TextField("输出价", value: $item.outputPricePerMillion, format: .number)
                                    .keyboardType(.decimalPad)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { offsets in
                    configDraft.pricing.remove(atOffsets: offsets)
                }

                Button {
                    addingModel.toggle()
                } label: {
                    Label(addingModel ? "收起新增模型" : "添加自定义计费模型", systemImage: "plus.circle")
                }

                if addingModel {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("上游厂商", selection: $newModelProvider) {
                            Text("DeepSeek").tag("deepSeek")
                            Text("OpenAI").tag("openAI")
                            Text("Google Gemini").tag("gemini")
                            Text("Anthropic Claude").tag("claude")
                            Text("xAI Grok").tag("grok")
                        }
                        TextField("模型 ID（如 gpt-5 / claude-opus-4）", text: $newModelID)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        TextField("展示名称", text: $newModelName)
                        HStack {
                            TextField("输入 ¥/1M", text: $newModelInputPrice).keyboardType(.decimalPad)
                            TextField("输出 ¥/1M", text: $newModelOutputPrice).keyboardType(.decimalPad)
                        }
                        Toggle("支持深度思考", isOn: $newModelThinking)
                        Button("加入定价表") {
                            addCustomPricingModel()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(newModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                Button {
                    saveAndPublishConfig()
                } label: {
                    HStack {
                        Spacer()
                        if busy { ProgressView().controlSize(.small) }
                        Text("保存并发布定价与二维码")
                            .font(.subheadline.weight(.bold))
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy)
                .accessibilityIdentifier("wumind.admin.publish")
            } header: {
                Text("3. 自定义模型售价表（单位：元 / 百万 Token）")
            } footer: {
                Text("本地保存会立即更新本机预览；若已配置云端网关与管理员密钥，将同步发布到 Cloudflare D1 对全体用户实时生效。")
            }

            // 4. Voucher Generator (Instant Code Top-Up)
            Section {
                HStack(spacing: 8) {
                    Text("面额 ¥")
                    TextField("30", text: $voucherAmount)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 84)
                    Stepper("张数：\(voucherCount)", value: $voucherCount, in: 1...20)
                }
                TextField("备注（如：微信 30 元档）", text: $voucherNote)
                    .font(.footnote)
                Button("生成云端充值兑换码") {
                    createVouchers()
                }
                .disabled(busy)

                if !generatedVouchers.isEmpty {
                    ForEach(generatedVouchers) { v in
                        HStack {
                            Text(v.code)
                                .font(.caption.monospaced().weight(.semibold))
                            Spacer()
                            Text("¥\(String(format: "%.2f", v.amountYuan))")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.green)
                            Button("复制") {
                                UIPasteboard.general.setItems([["public.utf8-plain-text": v.code]], options: [.localOnly: true])
                                ToastCenter.shared.show("已复制兑换码", style: .success)
                            }
                            .font(.caption2.weight(.semibold))
                        }
                    }
                }
            } header: {
                Text("4. 发放充值兑换码（用户核销秒到账）")
            }

            // 5. Direct User Top-Up by WM-XXXXXX ID
            Section {
                TextField("用户账号 ID（如 WM-849201）", text: $topUpUserID)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                HStack {
                    Text("入账金额 ¥")
                    TextField("20", text: $topUpAmount)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                }
                TextField("入账备注", text: $topUpNote)
                    .font(.footnote)
                Button("立即给该用户实时加款") {
                    performDirectTopUp()
                }
                .disabled(busy || topUpUserID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: {
                Text("5. 收到扫码转账后按用户 ID 秒充")
            }

            // 6. Live Revenue & Users Summary
            if let summary {
                Section("6. 云端运营实况") {
                    LabeledContent("注册用户数", value: "\(summary.userCount) 人")
                    LabeledContent("累计收款入账", value: String(format: "¥%.2f", summary.totalRechargedYuan))
                    LabeledContent("累计实时扣费", value: String(format: "¥%.4f", summary.totalSpentYuan))
                    LabeledContent("全员剩余余额", value: String(format: "¥%.2f", summary.totalBalanceYuan))

                    ForEach(summary.recentUsers.prefix(10)) { u in
                        HStack {
                            Text(u.userID).font(.caption.monospaced().weight(.semibold))
                            Spacer()
                            Text("余 ¥\(String(format: "%.2f", u.balanceYuan)) / 耗 ¥\(String(format: "%.3f", u.totalSpentYuan))")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("收起键盘") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
        .onChange(of: wechatPickerItem) { item in
            guard let item else { return }
            Task { @MainActor in
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data),
                   let encoded = WuMindAttachmentHelper.encodeQRCodeImage(img) {
                    configDraft.wechatQRBase64 = encoded
                    statusBanner = "已载入微信收款码（记得点击下方「保存并发布」）。"
                }
                wechatPickerItem = nil
            }
        }
        .onChange(of: alipayPickerItem) { item in
            guard let item else { return }
            Task { @MainActor in
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data),
                   let encoded = WuMindAttachmentHelper.encodeQRCodeImage(img) {
                    configDraft.alipayQRBase64 = encoded
                    statusBanner = "已载入支付宝收款码（记得点击下方「保存并发布」）。"
                }
                alipayPickerItem = nil
            }
        }
    }

    private var adminComplianceSection: some View {
        Section {
            Picker("收款与上架合规模式", selection: Binding(
                get: { configDraft.resolvedBillingMode },
                set: { configDraft.billingMode = $0.rawValue }
            )) {
                ForEach(WuMindBillingMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .accessibilityIdentifier("wumind.admin.billingMode")

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("联网深度搜索单次计费（¥/次）")
                        .font(.subheadline.weight(.medium))
                    Text("内置通道调用 web_search 时实时扣费")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                TextField("0.03", value: Binding(
                    get: { configDraft.resolvedWebSearchCostYuan },
                    set: { configDraft.webSearchCostYuan = max(0, $0) }
                ), format: .number)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .frame(width: 82)
            }

            TextField("支付自动化回调说明（展示在用户钱包）", text: Binding(
                get: { configDraft.paymentWebhookNote ?? "" },
                set: { configDraft.paymentWebhookNote = $0 }
            ), axis: .vertical)
            .lineLimit(2...3)
            .font(.footnote)

            VStack(alignment: .leading, spacing: 5) {
                Text("自动化入账接口（Cloudflare Workers）")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("• 微信/支付宝回调：POST /v1/webhooks/payment（Header: X-WuMind-Signature = HMAC-SHA256，按 external_order_id 幂等防重）")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                Text("• Apple StoreKit 2 核销：POST /v1/iap/verify（SKU: \(configDraft.resolvedIAPPacks.map(\.id).joined(separator: ", "))）")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        } header: {
            Text("合规收款模式、搜索单价与自动化 Webhook（仅管理员可改）")
        } footer: {
            Text("提交 App Store 正式审核时建议切换为「仅 Apple 应用内购」，TestFlight 内外测阶段可使用「混合模式」或「仅扫码/兑换码/自动化回调」。更改后请点击下方「保存并发布」。")
        }
    }

    private func saveConnectionLocally() {
        errorBanner = nil
        statusBanner = nil
        wumind.updateGatewayURL(gatewayURLDraft)
        let cleanedSecret = MultiProviderAIClient.sanitizePastedKey(adminSecretDraft)
        if !cleanedSecret.isEmpty {
            _ = Keychain.setWuMindGatewayAdminSecret(cleanedSecret)
            adminSecretDraft = ""
            hasAdminSecret = true
        }
        statusBanner = "网关连接与管理员密钥已保存到本机。"
    }

    private func applyMultiplierToDefaults(_ mult: Double) {
        let basePrices: [String: (Double, Double)] = [
            "deepseek-reasoner": (2.0, 8.0),
            "deepseek-chat": (1.0, 4.0),
            "gpt-4o": (18.0, 72.0),
            "gemini-2.5-pro": (9.0, 72.0),
            "claude-sonnet-4-20250514": (22.0, 108.0),
            "grok-3": (22.0, 108.0),
        ]
        for idx in configDraft.pricing.indices {
            if let (baseIn, baseOut) = basePrices[configDraft.pricing[idx].id] {
                configDraft.pricing[idx].inputPricePerMillion = (baseIn * mult * 10).rounded() / 10
                configDraft.pricing[idx].outputPricePerMillion = (baseOut * mult * 10).rounded() / 10
            }
        }
        statusBanner = "已按官方参考成本的 \(String(format: "%.1f", mult))× 更新全部默认模型售价。"
    }

    private func addCustomPricingModel() {
        let cleanID = newModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanID.isEmpty else { return }
        let display = newModelName.trimmingCharacters(in: .whitespacesAndNewlines)
        let inPrice = Double(newModelInputPrice) ?? 10
        let outPrice = Double(newModelOutputPrice) ?? 40
        configDraft.pricing.append(WuMindPricingItem(
            id: cleanID,
            provider: newModelProvider,
            displayName: display.isEmpty ? cleanID : display,
            inputPricePerMillion: max(0, inPrice),
            outputPricePerMillion: max(0, outPrice),
            officialReferenceNote: "管理员自定义模型",
            supportsThinking: newModelThinking,
            enabled: true
        ))
        newModelID = ""
        newModelName = ""
        addingModel = false
    }

    private func saveAndPublishConfig() {
        saveConnectionLocally()
        wumind.updateManagedConfigLocally(configDraft)
        guard wumind.hasGatewayURL, let secret = Keychain.wumindGatewayAdminSecret else {
            statusBanner = "已保存为本机预览配置（填写云端网关地址与 ADMIN_SECRET 后即可一键同步全员）。"
            return
        }
        busy = true
        errorBanner = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                let published = try await WuMindGatewayClient().adminSaveConfig(
                    gatewayURL: wumind.gatewayBaseURL,
                    adminSecret: secret,
                    config: configDraft
                )
                wumind.updateManagedConfigLocally(published)
                statusBanner = "定价表与收款二维码已实时发布到云端，全员即时生效！"
            } catch {
                errorBanner = (error as? LocalizedError)?.errorDescription ?? "发布失败，请检查网关地址与 ADMIN_SECRET。"
            }
        }
    }

    private func pullCloudConfigAndSummary() {
        saveConnectionLocally()
        guard wumind.hasGatewayURL, let secret = Keychain.wumindGatewayAdminSecret else {
            errorBanner = "请先填写网关地址和 ADMIN_SECRET。"
            return
        }
        busy = true
        errorBanner = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                try await wumind.syncManagedGatewayConfig()
                configDraft = wumind.managedConfig
                summary = try await WuMindGatewayClient().adminFetchSummary(
                    gatewayURL: wumind.gatewayBaseURL,
                    adminSecret: secret
                )
                statusBanner = "已从云端同步最新定价与运营统计。"
            } catch {
                errorBanner = (error as? LocalizedError)?.errorDescription ?? "拉取云端数据失败。"
            }
        }
    }

    private func createVouchers() {
        saveConnectionLocally()
        guard wumind.hasGatewayURL, let secret = Keychain.wumindGatewayAdminSecret else {
            errorBanner = "请先填写网关地址和 ADMIN_SECRET。"
            return
        }
        guard let amount = Double(voucherAmount), amount >= 0.1 else {
            errorBanner = "请输入有效的面额（至少 ¥0.10）。"
            return
        }
        busy = true
        errorBanner = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                let created = try await WuMindGatewayClient().adminCreateVouchers(
                    gatewayURL: wumind.gatewayBaseURL,
                    adminSecret: secret,
                    amountYuan: amount,
                    count: voucherCount,
                    note: voucherNote
                )
                generatedVouchers = created + generatedVouchers
                statusBanner = "已生成 \(created.count) 张 ¥\(String(format: "%.2f", amount)) 充值兑换码。"
            } catch {
                errorBanner = (error as? LocalizedError)?.errorDescription ?? "生成兑换码失败。"
            }
        }
    }

    private func performDirectTopUp() {
        saveConnectionLocally()
        guard wumind.hasGatewayURL, let secret = Keychain.wumindGatewayAdminSecret else {
            errorBanner = "请先填写网关地址和 ADMIN_SECRET。"
            return
        }
        guard let amount = Double(topUpAmount), amount > 0 else {
            errorBanner = "请输入大于 0 的入账金额。"
            return
        }
        busy = true
        errorBanner = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                let res = try await WuMindGatewayClient().adminTopUpUser(
                    gatewayURL: wumind.gatewayBaseURL,
                    adminSecret: secret,
                    userID: topUpUserID,
                    amountYuan: amount,
                    note: topUpNote
                )
                topUpUserID = ""
                statusBanner = "已为 \(res.userID) 入账 ¥\(String(format: "%.2f", amount))，对方最新余额 ¥\(String(format: "%.2f", res.balanceYuan))。"
            } catch {
                errorBanner = (error as? LocalizedError)?.errorDescription ?? "入账失败，请检查用户 ID 是否正确。"
            }
        }
    }
}
