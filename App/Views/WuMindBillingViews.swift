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

    /// Apple Developer Program License Agreement (§7.4): TestFlight builds MUST NOT charge beta testers
    /// real money for digital purchases, including external WeChat/Alipay checkout redirects or QR codes.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var isTestFlightComplianceRestricted: Bool {
        SigningInfo.isTestFlight || AppStore.isDemo
    }

    var body: some View {
        NavigationStack {
            List {
                balanceOverviewSection
                if let status = store.managedAccountStatus {
                    Section {
                        NavigationLink {
                            List {
                                if status.ledger.isEmpty {
                                    Text("暂无计费或充值流水").foregroundStyle(.secondary)
                                } else {
                                    ledgerSection
                                }
                            }
                            .appList()
                            .navigationTitle("最近账单")
                            .navigationBarTitleDisplayMode(.inline)
                        } label: {
                            Label("查看最近账单", systemImage: "list.bullet.rectangle")
                        }
                        .accessibilityIdentifier("wumind.wallet.ledger")
                    }
                }
                if isTestFlightComplianceRestricted {
                    testFlightComplianceSection
                    appleIAPSection
                    voucherSection
                } else {
                    if billingMode == .hybrid || billingMode == .appStoreIAP {
                        appleIAPSection
                    }
                    if billingMode == .hybrid || billingMode == .directQR {
                        automatedOrdersSection
                        voucherSection
                        qrRechargeSection
                    }
                }
                pricingTableSection
                gatewayEndpointSection
            }
            .appList()
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("WUMIND 钱包与计费")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if store.hasGatewayURL {
                    ToolbarItem(placement: .navigationBarLeading) { rechargeGuideButton }
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
                if store.hasGatewayURL {
                    refreshAll()
                    Task { @MainActor in
                        await iap.recoverUnfinishedTransactions(store: store, silent: true)
                    }
                }
            }
            .onDisappear {
                stopOrderAutoPolling()
            }
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .active {
                    if let pendingID = trackingOrderID {
                        checkOrderOnce(pendingID, manual: false)
                    }
                    if store.hasGatewayURL {
                        Task { @MainActor in
                            await iap.recoverUnfinishedTransactions(store: store, silent: true)
                        }
                    }
                }
            }
            .task {
                if billingMode == .hybrid || billingMode == .appStoreIAP {
                    await iap.loadProducts(for: store.managedConfig.resolvedIAPPacks)
                }
            }
        }
    }

    private var rechargeGuideButton: some View {
        Button {
            Haptics.tap()
            showingGuide = true
        } label: {
            Label("充值与计费说明", systemImage: "book.closed")
                .font(.subheadline.weight(.semibold))
        }
        .accessibilityIdentifier("wumind.wallet.guideToolbar")
    }

    private var balanceOverviewSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: DS.Space.m) {
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        Text("可用余额").font(DS.Font.caption).foregroundStyle(.secondary)
                        Text(formattedBalance)
                            .font(.largeTitle.weight(.semibold).monospacedDigit())
                            .accessibilityIdentifier("wumind.wallet.balance")
                        if let reserved = store.managedAccountStatus?.reservedYuan, reserved > 0 {
                            Text(String(format: "进行中任务已预留 ¥%.4f", reserved))
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if store.hasGatewayURL {
                        Button { refreshAll() } label: {
                            if busy { ProgressView() } else { Label("刷新", systemImage: "arrow.clockwise") }
                        }
                        .buttonStyle(.bordered)
                        .disabled(busy)
                    }
                }
                if store.isBillingExempt {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundStyle(.purple)
                        Text(store.managedAccountStatus?.dailyCostCapYuan.map { String(format: "管理员免充值，用量照常记录。每日上限 ¥%.0f。", $0) }
                             ?? "管理员免充值，用量照常记录。")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.purple)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.purple.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityIdentifier("wumind.wallet.adminExemptBanner")
                }

                if let status = store.managedAccountStatus, status.totalRechargedYuan > 0 {
                    let ratio = min(1.0, max(0.0, status.balanceYuan / status.totalRechargedYuan))
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: ratio)
                            .tint(ratio < 0.15 ? .orange : .indigo)
                        HStack {
                            Text("剩余额度占比 \(Int((ratio * 100).rounded()))%")
                            Spacer()
                            Text(String(format: "累计充值 ¥%.2f", status.totalRechargedYuan))
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }

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

                usageSummary
                if !store.hasGatewayURL {
                    rechargeGuideButton.frame(minHeight: 44)
                }
                if let sb = store.managedAccountStatus?.sandboxBalanceYuan, sb > 0 {
                    HStack(spacing: 8) {
                        Image(systemName: "flask.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.orange)
                        Text(String(format: "独立沙盒测试余额：¥%.2f（与正式余额完全隔离，仅用于验签验收）", sb))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityIdentifier("wumind.wallet.sandboxBalance")
                }

                if store.managedConfig.isAutoCreditPaused {
                    HStack(spacing: 8) {
                        Image(systemName: "pause.circle.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.red)
                        Text("云端自动入账通道当前处于安全暂停状态（AUTO_CREDIT_PAUSED），仅支持免费兑换码与自带 API。")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.09), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityIdentifier("wumind.wallet.autoCreditPausedBanner")
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

    @ViewBuilder
    private var usageSummary: some View {
        if let status = store.managedAccountStatus {
            let input = status.totalPromptTokens.map(WuMindAccountStatus.formatTokens)
            let output = status.totalCompletionTokens.map { WuMindAccountStatus.formatTokens($0 + (status.totalReasoningTokens ?? 0)) }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.xs), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), spacing: DS.Space.xs) {
                walletStatTile(
                    title: "今日已用",
                    value: status.todaySpentYuan.map { String(format: "¥%.4f", $0) } ?? "未获取",
                    sub: status.todayTokens.map { "\(WuMindAccountStatus.formatTokens($0)) Tokens" } ?? "今日用量未获取",
                    tint: .indigo
                )
                walletStatTile(
                    title: "累计 Token 用量",
                    value: input != nil && output != nil ? WuMindAccountStatus.formatTokens(status.totalTokens) : "未获取",
                    sub: status.totalRequests.map { "共 \($0) 次请求" } ?? "请求数未获取",
                    tint: .blue
                )
                walletStatTile(
                    title: "累计消费金额",
                    value: String(format: "¥%.4f", status.totalSpentYuan),
                    sub: "输入 \(input ?? "未获取") · 输出 \(output ?? "未获取")",
                    tint: .orange
                )
                walletStatTile(
                    title: "购买与赠额",
                    value: status.purchasedRechargedYuan.map { String(format: "实购 ¥%.2f", $0) } ?? String(format: "累计充值 ¥%.2f", status.totalRechargedYuan),
                    sub: status.adminGrantedYuan.map { String(format: "管理员赠额 ¥%.2f", $0) } ?? "赠额未获取",
                    tint: .green
                )
            }
            .accessibilityIdentifier("wumind.wallet.usageGrid")
        } else {
            Text(store.hasGatewayURL ? "尚未获取账户用量与账单。" : "尚未获取账户用量与账单。请联系管理员确认内置网关。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("wumind.wallet.usageGrid")
        }
    }

    private var testFlightComplianceSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.blue)
                    Text("测试版充值")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                }
                Text("当前仅支持测试兑换码和 Apple 沙盒内购。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("沙盒交易仅计入测试余额。使用个人 Key 时由服务商按其规则计费。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("wumind.wallet.testFlightComplianceBanner")
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
                            Text(isTestFlightComplianceRestricted
                                 ? String(format: "沙盒测试 ¥%.0f", pack.creditYuan)
                                 : String(format: "到账 ¥%.0f", pack.creditYuan))
                                .font(.headline.monospacedDigit().weight(.black))
                                .foregroundStyle(.indigo)
                            HStack {
                                if isPurchasing {
                                    ProgressView().controlSize(.mini)
                                    Text("验签中…")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text(isTestFlightComplianceRestricted ? "Sandbox 0 元" : (product?.displayPrice ?? pack.fallbackPriceLabel))
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
                    .disabled(iap.purchasingProductID != nil || store.managedConfig.isAutoCreditPaused)
                }
            }
            .padding(.vertical, 4)
            .accessibilityIdentifier("wumind.wallet.iapGrid")

            if let note = iap.statusNote, !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                Haptics.tap()
                Task { @MainActor in
                    await iap.syncAppStoreAndRecover(store: store)
                }
            } label: {
                HStack(spacing: 6) {
                    if iap.isRecovering {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath.circle")
                    }
                    Text(iap.pendingTransactionCount > 0
                         ? "恢复未完成内购（待核销 \(iap.pendingTransactionCount) 笔）"
                         : "恢复未完成内购 / 掉线补单")
                        .font(.caption.weight(.semibold))
                }
            }
            .disabled(iap.isRecovering || !store.hasGatewayURL)
            .accessibilityIdentifier("wumind.wallet.restoreIAP")
        } header: {
            Text(isTestFlightComplianceRestricted
                 ? "Apple 沙盒测试内购（TestFlight 0 元不扣费 · 独立测试余额）"
                 : "Apple 应用内购流量包（StoreKit 2 服务端验签）")
        } footer: {
            Text("采用 Apple StoreKit 2 消耗型内购，服务端独立校验证书链（Apple Root CA - G3）与 ES256 数字签名，同一交易 ID 严格防重与跨号隔离；沙盒交易仅计入独立测试余额。")
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
            Text("兑换码")
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
            Text("微信 / 支付宝充值")
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
            Text("内置模型价格")
        } footer: {
            Text("对话按输入、输出和思考 Token 计费。联网搜索按次计费。")
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
        Section("内置通道") {
            Text(store.hasGatewayURL ? "使用此版本配置的 WuMind 服务。" : "此版本尚未配置内置服务，请联系管理员。")
                .foregroundStyle(.secondary)
        }
    }

    private var formattedBalance: String {
        if let bal = store.managedBalanceYuan {
            return String(format: "¥%.2f", bal)
        }
        guard store.hasGatewayURL else { return "未连接网关" }
        return store.managedAccountID.isEmpty ? "未激活" : "未获取"
    }

    private func formatPrice(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", value) : String(format: "%.2f", value)
    }

    private func ledgerTitle(_ entry: WuMindLedgerEntry) -> String {
        if entry.kind.hasPrefix("admin_exempt_") {
            return "管理员免扣 · \(entry.model.isEmpty ? entry.kind : entry.model)"
        }
        switch entry.kind {
        case "chat":
            if entry.model == "web_search" { return "联网深度搜索" }
            return entry.model.isEmpty ? "对话" : entry.model
        case "image": return "文生图 · \(entry.model)"
        case "image_edit": return "参考图生图 · \(entry.model)"
        case "video": return "视频生成 · \(entry.model)"
        case "realtime_voice": return "实时语音 · \(entry.model)"
        case "web_search": return "联网深度搜索"
        case "schedule": return "云端定时任务"
        case "apple_iap": return "Apple 应用内购"
        case "sandbox_apple_iap": return "Apple 沙盒测试（独立测试余额）"
        case "iap_refund": return "Apple 退款/撤销扣回"
        case "webhook_topup": return "支付回调自动入账"
        case "redeem": return "兑换码充值"
        case "admin_grant", "admin_topup": return "管理员人工赠额"
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
                .fixedSize(horizontal: false, vertical: true)
            Text(sub)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
                errorMessage = (error as? LocalizedError)?.errorDescription ?? "激活失败，请检查网络或联系管理员。"
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
                if WuMindStore.shared.managedSessionToken != nil {
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
        guard !isTestFlightComplianceRestricted else {
            errorMessage = "依据 Apple TestFlight 条款，测试版本已禁止创建真实付费订单或跳转外部收款。"
            return
        }
        guard !store.managedConfig.isAutoCreditPaused else {
            errorMessage = "云端自动充值入账通道当前处于安全暂停状态（AUTO_CREDIT_PAUSED）。"
            return
        }
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

// MARK: - Admin-Only Commercial Billing Management (4 Status Cards + 4 Clean Sub-Pages)

struct WuMindAdminBillingView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var appStore: AppStore
    @ObservedObject private var wumind = WuMindStore.shared

    @State private var upstreamBalance: WuMindAdminUpstreamBalance? = nil
    @State private var summary: WuMindAdminSummary? = nil
    @State private var isLoading = false
    @State private var balanceError: String? = nil
    @State private var summaryError: String? = nil

    private var adminSecret: String {
        Keychain.wuMindGatewayAdminSecret(for: wumind.gatewayBaseURL) ?? ""
    }

    private var hasGatewayCredentials: Bool {
        wumind.hasGatewayURL && !adminSecret.isEmpty
    }

    var body: some View {
        Group {
            if !appStore.canEdit {
                AppEmptyStateCard(
                    icon: "lock.shield", title: "需要管理员权限",
                    message: "在「设置 › 身份」登录管理员账号后，可查看账单、定价和网关配置。"
                )
                .padding(DS.Space.m)
                .frame(maxWidth: DS.readableWidth)
            } else {
                dashboardList
            }
        }
        .hidesFloatingTabBar()
        .navigationTitle("商业计费管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            if appStore.canEdit {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await refreshDashboard(forceUpstreamRefresh: true) }
                    } label: {
                        if isLoading {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(isLoading)
                    .accessibilityIdentifier("wumind.admin.refreshAll")
                }
            }
        }
        .task {
            if appStore.canEdit && hasGatewayCredentials {
                await refreshDashboard(forceUpstreamRefresh: false)
            }
        }
    }

    private var dashboardList: some View {
        List {
            // Top: 4 Crisp Operational Status Cards (2×2 Grid)
            Section {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2),
                    spacing: 10
                ) {
                    upstreamBalanceCard
                    todayUsageCard
                    rechargeStatusCard
                    anomalyAlertCard
                }
                .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                .listRowBackground(Color.clear)
                if !hasGatewayCredentials {
                    NavigationLink {
                        gatewayDiagnostics
                    } label: {
                        Label("打开网关与诊断", systemImage: "network")
                    }
                    .accessibilityIdentifier("wumind.admin.gatewayFromStatus")
                }
            } header: {
                Text("运营状态总览")
            }

            // Bottom: 4 Dedicated Navigation Entries
            Section {
                NavigationLink {
                    if hasGatewayCredentials {
                        WuMindAdminUsersPage(gatewayURL: wumind.gatewayBaseURL, adminSecret: adminSecret)
                    } else {
                        missingGatewayPromptView
                    }
                } label: {
                    entryRow(
                        title: "用户与账单",
                        subtitle: summary.map { "共 \($0.userCount) 人 · 今日新增 +\($0.todayNewUsers ?? 0) · 详情内直接加余额" }
                            ?? "查看全部注册用户、消费明细与直接加余额",
                        icon: "person.3.sequence.fill",
                        color: .purple
                    )
                }
                .accessibilityIdentifier("wumind.admin.userDirectory")

                NavigationLink {
                    if hasGatewayCredentials {
                        WuMindAdminPricingPage(gatewayURL: wumind.gatewayBaseURL, adminSecret: adminSecret) {
                            Task {
                                try? await wumind.syncManagedGatewayConfig()
                                await refreshDashboard(forceUpstreamRefresh: false)
                            }
                        }
                    } else {
                        missingGatewayPromptView
                    }
                } label: {
                    let multText = String(format: "%.2f×", summary?.markupMultiplier ?? 1.50)
                    entryRow(
                        title: "模型定价",
                        subtitle: "统一倍率 \(multText) · v\(summary?.priceVersion ?? 1) · 聊天 / 生图 / 视频 / 语音",
                        icon: "cpu.fill",
                        color: .indigo
                    )
                }
                .accessibilityIdentifier("wumind.admin.modelCatalog")

                NavigationLink {
                    WuMindAdminPaymentsPage(initialConfig: wumind.managedConfig, summary: summary, canPublish: hasGatewayCredentials) {
                        Task { await refreshDashboard(forceUpstreamRefresh: false) }
                    }
                } label: {
                    entryRow(
                        title: "充值与支付",
                        subtitle: "收款码、兑换码、合规模式与搜索单价（不改现用收款开关）",
                        icon: "creditcard.fill",
                        color: .green
                    )
                }
                .accessibilityIdentifier("wumind.admin.payments")

                NavigationLink {
                    gatewayDiagnostics
                } label: {
                    entryRow(
                        title: "网关与诊断",
                        subtitle: hasGatewayCredentials ? "网关地址、密钥、低余额报警阈值与上线教程" : "确认构建地址并配置管理凭据",
                        icon: "wrench.and.screwdriver.fill",
                        color: .orange
                    )
                }
                .accessibilityIdentifier("wumind.admin.gateway")
            } header: {
                Text("管理")
            }
        }
        .appList()
    }

    private var gatewayDiagnostics: some View {
        WuMindAdminGatewayDiagnosticsPage(
            upstreamBalance: $upstreamBalance,
            summary: summary,
            onUpdated: {
                Task { await refreshDashboard(forceUpstreamRefresh: false) }
            }
        )
    }

    // MARK: - 4 First-Screen Status Cards

    private var upstreamBalanceCard: some View {
        let valueText: String
        let detailText: String
        let tint: Color

        if !hasGatewayCredentials {
            valueText = "未配置"
            detailText = "待连接计费网关"
            tint = .secondary
        } else if let err = balanceError {
            valueText = "获取失败"
            detailText = String(err.prefix(32))
            tint = .orange
        } else if let b = upstreamBalance {
            if b.syncFailed {
                valueText = b.availableUSD.map { String(format: "$%.2f", $0) } ?? "同步失败"
                detailText = b.syncError ?? "上次余额 · 同步失败"
                tint = .orange
            } else if let usd = b.availableUSD {
                valueText = String(format: "$%.2f", usd)
                detailText = b.alertTriggered ? "低于报警阈值 $\(String(format: "%.0f", b.lowBalanceAlertUSD))" : "AIHubMix 共享池"
                tint = b.alertTriggered ? .red : .indigo
            } else {
                valueText = "待配置"
                detailText = b.statusLabel
                tint = .orange
            }
        } else {
            valueText = isLoading ? "查询中…" : "未同步"
            detailText = "点击右上角刷新"
            tint = .secondary
        }

        return statusCard(
            title: "上游余额",
            value: valueText,
            detail: detailText,
            icon: "dollarsign.circle.fill",
            tint: tint,
            id: "wumind.admin.card.upstreamBalance"
        )
    }

    private var todayUsageCard: some View {
        let valueText: String
        let detailText: String
        if !hasGatewayCredentials {
            valueText = "--"
            detailText = "待连接计费网关"
        } else if let err = summaryError {
            valueText = "拉取失败"
            detailText = String(err.prefix(28))
        } else if let s = summary {
            valueText = String(format: "¥%.2f", s.todaySpentYuan ?? 0)
            detailText = "\(s.todayRequests ?? 0) 次调用 · 新用户 +\(s.todayNewUsers ?? 0)"
        } else {
            valueText = isLoading ? "查询中…" : "--"
            detailText = "网关今日统计"
        }
        return statusCard(
            title: "今日用量",
            value: valueText,
            detail: detailText,
            icon: "chart.bar.fill",
            tint: .blue,
            id: "wumind.admin.card.todayUsage"
        )
    }

    private var rechargeStatusCard: some View {
        let valueText: String
        let detailText: String
        let tint: Color
        if let s = summary {
            let paused = s.autoCreditPaused ?? true
            let iapLive = s.appleIAPProductionEnabled ?? false
            valueText = paused ? "自动入账暂停" : (iapLive ? "正式内购已开" : "仅沙盒/人工")
            detailText = String(format: "实付 ¥%.0f · 赠额 ¥%.0f", s.totalPurchasedYuan ?? 0, s.totalAdminGrantedYuan ?? 0)
            tint = paused ? .orange : .green
        } else {
            valueText = hasGatewayCredentials ? (isLoading ? "查询中…" : "待同步") : "未连接"
            detailText = "不改网关收款开关"
            tint = .secondary
        }
        return statusCard(
            title: "充值与入账状态",
            value: valueText,
            detail: detailText,
            icon: "checkmark.shield.fill",
            tint: tint,
            id: "wumind.admin.card.rechargeStatus"
        )
    }

    private var anomalyAlertCard: some View {
        var issues: [String] = []
        if !hasGatewayCredentials {
            issues.append("未配网关密钥")
        }
        if upstreamBalance?.alertTriggered == true {
            issues.append("上游低余额")
        }
        if upstreamBalance?.syncFailed == true || balanceError != nil {
            issues.append("余额同步失败")
        }
        if let pending = summary?.pendingOrdersCount, pending > 0 {
            issues.append("\(pending) 笔待入账订单")
        }
        if let failedVid = summary?.failedVideoJobs24h, failedVid > 0 {
            issues.append("24h 视频失败 \(failedVid)")
        }
        let hasIssue = !issues.isEmpty
        return statusCard(
            title: "异常提醒",
            value: hasIssue ? "\(issues.count) 项待处理" : "运行正常",
            detail: hasIssue ? issues.joined(separator: " · ") : "无低余额或失败告警",
            icon: hasIssue ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
            tint: hasIssue ? .red : .green,
            id: "wumind.admin.card.anomalies"
        )
    }

    private func statusCard(
        title: String,
        value: String,
        detail: String,
        icon: String,
        tint: Color,
        id: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(.title3.monospacedDigit().weight(.bold))
                .foregroundStyle(tint == .secondary ? .primary : tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
        .padding(11)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(tint.opacity(0.22), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }

    private func entryRow(title: String, subtitle: String, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(color, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
        }
        .padding(.vertical, 3)
    }

    private var missingGatewayPromptView: some View {
        VStack(spacing: 12) {
            Image(systemName: "network.slash")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("尚未配置计费网关连接")
                .font(.headline)
            Text("请先确认构建的内置网关地址，然后在「网关与诊断」保存管理凭据。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
        .navigationTitle("需要配置网关")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func refreshDashboard(forceUpstreamRefresh: Bool) async {
        guard hasGatewayCredentials else { return }
        let gatewayURL = wumind.gatewayBaseURL
        guard let secret = Keychain.wuMindGatewayAdminSecret(for: gatewayURL) else { return }
        isLoading = true
        balanceError = nil
        summaryError = nil
        defer { isLoading = false }

        async let sumTask: Void = {
            do {
                let s = try await WuMindGatewayClient().adminFetchSummary(
                    gatewayURL: gatewayURL,
                    adminSecret: secret
                )
                await MainActor.run { self.summary = s }
            } catch {
                await MainActor.run {
                    self.summaryError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        }()

        async let balTask: Void = {
            do {
                let b = forceUpstreamRefresh
                    ? try await WuMindGatewayClient().adminRefreshUpstreamBalance(gatewayURL: gatewayURL, adminSecret: secret)
                    : try await WuMindGatewayClient().adminFetchUpstreamBalance(gatewayURL: gatewayURL, adminSecret: secret, refresh: false)
                await MainActor.run { self.upstreamBalance = b }
            } catch {
                await MainActor.run {
                    self.balanceError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        }()

        _ = await (sumTask, balTask)
    }
}

// MARK: - Sub-Page 3: 充值与支付 (QR Codes, Vouchers, Compliance Mode, Search Price)

private struct WuMindAdminPaymentsPage: View {
    @ObservedObject private var wumind = WuMindStore.shared
    let summary: WuMindAdminSummary?
    let canPublish: Bool
    let onUpdated: () -> Void

    @State private var configDraft: WuMindCommercialConfig
    @State private var showingInactiveQR = false
    @State private var wechatPickerItem: PhotosPickerItem?
    @State private var alipayPickerItem: PhotosPickerItem?
    @State private var voucherAmount = "30"
    @State private var voucherCount = 1
    @State private var voucherNote = "内测兑换码"
    @State private var generatedVouchers: [WuMindVoucher] = []
    @State private var busy = false
    @State private var statusBanner: String?
    @State private var errorBanner: String?

    init(initialConfig: WuMindCommercialConfig, summary: WuMindAdminSummary?, canPublish: Bool, onUpdated: @escaping () -> Void) {
        _configDraft = State(initialValue: initialConfig)
        self.summary = summary
        self.canPublish = canPublish
        self.onUpdated = onUpdated
    }

    var body: some View {
        Form {
            if let statusBanner {
                Section {
                    Label(statusBanner, systemImage: "checkmark.circle.fill")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.green)
                }
            }
            if let errorBanner {
                Section {
                    Label(errorBanner, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.red)
                }
            }

            Section {
                LabeledContent("网关自动入账开关", value: summary?.autoCreditPaused.map { $0 ? "已暂停（安全保护）" : "已开启" } ?? "未获取")
                LabeledContent("Apple 正式内购开关", value: summary?.appleIAPProductionEnabled.map { $0 ? "已开启" : "未开启" } ?? "未获取")
                Picker("展示合规模式", selection: Binding(
                    get: { configDraft.resolvedBillingMode },
                    set: { configDraft.billingMode = $0.rawValue }
                )) {
                    ForEach(WuMindBillingMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .accessibilityIdentifier("wumind.admin.billingMode")

                HStack {
                    Text("联网搜索单次计费 (¥/次)")
                    Spacer()
                    TextField("0.03", value: Binding(
                        get: { configDraft.resolvedWebSearchCostYuan },
                        set: { configDraft.webSearchCostYuan = max(0, $0) }
                    ), format: .number)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 82)
                }
            } header: {
                Text("收款合规与搜索单价")
            } footer: {
                Text("网关环境变量 AUTO_CREDIT_PAUSED 与 ALLOW_APPLE_PRODUCTION_IAP 仅由 Cloudflare 运维控制，App 端不会擅自更改。")
            }

            Section("钱包公告") {
                TextField("钱包顶部公告（选填）", text: $configDraft.announcement)
            }

            Section("站外收款") {
                if configDraft.resolvedBillingMode == .appStoreIAP {
                    DisclosureGroup("查看或编辑未启用的收款码与指引", isExpanded: $showingInactiveQR) {
                        qrFields
                    }
                    .accessibilityIdentifier("wumind.admin.inactiveQR")
                } else {
                    qrFields
                }
            }

            Section("发放充值兑换码") {
                HStack(spacing: 8) {
                    Text("面额 ¥")
                    TextField("30", text: $voucherAmount)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    Stepper("张数：\(voucherCount)", value: $voucherCount, in: 1...20)
                }
                TextField("备注", text: $voucherNote).font(.footnote)
                Button("生成云端兑换码") { createVouchers() }
                    .disabled(busy)

                ForEach(generatedVouchers) { v in
                    HStack {
                        Text(v.code).font(.caption.monospaced().weight(.semibold))
                        Spacer()
                        Text("¥\(String(format: "%.2f", v.amountYuan))").font(.caption.weight(.bold)).foregroundStyle(.green)
                        Button("复制") {
                            UIPasteboard.general.setItems([["public.utf8-plain-text": v.code]], options: [.localOnly: true])
                            ToastCenter.shared.show("已复制兑换码", style: .success)
                        }
                        .font(.caption2.weight(.semibold))
                    }
                }
            }
        }
        .appList()
        .scrollDismissesKeyboard(.interactively)
        .hidesFloatingTabBar()
        .navigationTitle("充值与支付")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                AppSaveToolbarButton(title: canPublish ? "保存并发布" : "保存到本机", isSaving: busy, accessibilityID: "wumind.admin.publish") {
                    saveAndPublish()
                }
                .accessibilityHint("保存收款配置，管理网关已连接时同时发布。")
            }
        }
        .onChange(of: wechatPickerItem) { item in
            guard let item else { return }
            Task { @MainActor in
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data),
                   let encoded = WuMindAttachmentHelper.encodeQRCodeImage(img) {
                    configDraft.wechatQRBase64 = encoded
                    statusBanner = "微信收款码已更改，尚未保存。"
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
                    statusBanner = "支付宝收款码已更改，尚未保存。"
                }
                alipayPickerItem = nil
            }
        }
    }

    @ViewBuilder
    private var qrFields: some View {
        HStack(spacing: 16) {
            qrSlot(
                title: configDraft.wechatQRBase64 == nil ? "上传微信码" : "更换微信码",
                base64: configDraft.wechatQRBase64,
                tint: .green,
                picker: $wechatPickerItem,
                onClear: { configDraft.wechatQRBase64 = nil }
            )
            qrSlot(
                title: configDraft.alipayQRBase64 == nil ? "上传支付宝码" : "更换支付宝码",
                base64: configDraft.alipayQRBase64,
                tint: .blue,
                picker: $alipayPickerItem,
                onClear: { configDraft.alipayQRBase64 = nil }
            )
        }
        .padding(.vertical, 4)

        TextField("充值指引说明", text: $configDraft.rechargeNote, axis: .vertical)
            .accessibilityIdentifier("wumind.admin.rechargeNote")
            .lineLimit(2...4)
            .font(.footnote)
        TextField("管理员联系方式（选填）", text: $configDraft.contactNote)
            .font(.footnote)
    }

    private func qrSlot(
        title: String,
        base64: String?,
        tint: Color,
        picker: Binding<PhotosPickerItem?>,
        onClear: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 8) {
            if let img = WuMindAttachmentHelper.decodeBase64Image(base64) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 106, height: 106)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(0.10))
                    .frame(width: 106, height: 106)
                    .overlay(Image(systemName: "qrcode").font(.title).foregroundStyle(tint))
            }
            PhotosPicker(selection: picker, matching: .images) {
                Text(title).font(.caption.weight(.semibold))
            }
            if base64 != nil {
                Button("移除", role: .destructive, action: onClear).font(.caption2)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func saveAndPublish() {
        wumind.updateManagedConfigLocally(configDraft)
        let gatewayURL = wumind.gatewayBaseURL
        guard let secret = Keychain.wuMindGatewayAdminSecret(for: gatewayURL) else {
            statusBanner = "已保存为本机配置（配置网关密钥后即可同步全员）。"
            return
        }
        busy = true
        errorBanner = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                let published = try await WuMindGatewayClient().adminSaveConfig(
                    gatewayURL: gatewayURL,
                    adminSecret: secret,
                    config: configDraft
                )
                wumind.updateManagedConfigLocally(published)
                statusBanner = "收款码与合规配置已发布生效。"
                onUpdated()
            } catch {
                errorBanner = (error as? LocalizedError)?.errorDescription ?? "发布失败。"
            }
        }
    }

    private func createVouchers() {
        let gatewayURL = wumind.gatewayBaseURL
        guard let secret = Keychain.wuMindGatewayAdminSecret(for: gatewayURL) else {
            errorBanner = "请先在「网关与诊断」填写网关地址与 ADMIN_SECRET。"
            return
        }
        guard let amount = Double(voucherAmount), amount >= 0.1 else {
            errorBanner = "请输入有效面额（至少 ¥0.10）。"
            return
        }
        busy = true
        errorBanner = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                let created = try await WuMindGatewayClient().adminCreateVouchers(
                    gatewayURL: gatewayURL,
                    adminSecret: secret,
                    amountYuan: amount,
                    count: voucherCount,
                    note: voucherNote
                )
                generatedVouchers = created + generatedVouchers
                statusBanner = "已生成 \(created.count) 张 ¥\(String(format: "%.2f", amount)) 兑换码。"
            } catch {
                errorBanner = (error as? LocalizedError)?.errorDescription ?? "生成兑换码失败。"
            }
        }
    }
}

// MARK: - Sub-Page 4: 网关与诊断 (Gateway URL, Admin Secret, Manage Key Balance & Threshold, Setup Guide)

private struct WuMindAdminGatewayDiagnosticsPage: View {
    @ObservedObject private var wumind = WuMindStore.shared
    @Binding var upstreamBalance: WuMindAdminUpstreamBalance?
    let summary: WuMindAdminSummary?
    let onUpdated: () -> Void

    @State private var adminSecretDraft = ""
    @State private var alertThresholdDraft = "10"
    @State private var loadingBalance = false
    @State private var savingThreshold = false
    @State private var showingSetupGuide = false
    @State private var statusBanner: String?
    @State private var errorBanner: String?

    private var hasAdminSecret: Bool {
        Keychain.wuMindGatewayAdminSecret(for: wumind.gatewayBaseURL) != nil
    }

    var body: some View {
        Form {
            if let statusBanner {
                Section {
                    Label(statusBanner, systemImage: "checkmark.circle.fill")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.green)
                }
            }
            if let errorBanner {
                Section {
                    Label(errorBanner, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.red)
                }
            }

            WuMindAdminUpstreamBalanceSection(
                balance: upstreamBalance,
                isLoading: loadingBalance,
                isSavingThreshold: savingThreshold,
                alertThresholdDraft: $alertThresholdDraft,
                onRefresh: { refreshBalance() },
                onSaveThreshold: { saveThreshold() }
            )

            Section {
                LabeledContent("当前版本的网关", value: wumind.hasGatewayURL ? wumind.gatewayBaseURL : "待管理员配置构建地址")
                    .accessibilityIdentifier("wumind.admin.gatewayURL")

                SecureField(
                    hasAdminSecret ? "此网关的 ADMIN_SECRET 已保存（输入可替换）" : "输入对应网关的 ADMIN_SECRET",
                    text: $adminSecretDraft
                )
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("wumind.admin.secret")

                Button("保存管理凭据", action: saveConnection)
                    .disabled(!wumind.hasGatewayURL || adminSecretDraft.isEmpty)
                .buttonStyle(.borderedProminent)
            } header: {
                Text("云端计费网关凭据")
            } footer: {
                Text(Keychain.hasUnboundWuMindGatewayAdminSecret && !hasAdminSecret
                     ? "检测到旧版密钥，但无法确认它属于当前地址。请为这个网关重新保存一次管理员密钥，之后更新无需重复填写。"
                     : "管理员密钥仅保存在本机钥匙串，切换网关不会沿用其他地址的密钥。")
            }

            if let s = summary {
                Section("全站账务核对快照") {
                    LabeledContent("注册用户总数", value: "\(s.userCount) 人")
                    LabeledContent("全员正式余额（含预留）", value: String(format: "¥%.2f", s.totalBalanceYuan))
                    LabeledContent("累计实付入账", value: String(format: "¥%.2f", s.totalPurchasedYuan ?? s.totalRechargedYuan))
                    LabeledContent("累计管理员赠额", value: String(format: "¥%.2f", s.totalAdminGrantedYuan ?? 0))
                    LabeledContent("累计网关消费", value: String(format: "¥%.4f", s.totalSpentYuan))
                }
            }

            Section("部署与运维文档") {
                Button {
                    showingSetupGuide = true
                } label: {
                    Label("查看部署与计费配置指南", systemImage: "book.closed.fill")
                }
                .accessibilityIdentifier("wumind.admin.guide")
            }
        }
        .appList()
        .scrollDismissesKeyboard(.interactively)
        .hidesFloatingTabBar()
        .navigationTitle("网关与诊断")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .sheet(isPresented: $showingSetupGuide) {
            WuMindAdminSetupGuideSheet()
        }
        .onAppear {
            if let threshold = upstreamBalance?.lowBalanceAlertUSD {
                alertThresholdDraft = String(format: "%.2f", threshold)
            }
        }
    }

    private func saveConnection() {
        statusBanner = nil
        errorBanner = nil
        guard let address = try? WuMindGatewayConfiguration.address(wumind.gatewayBaseURL) else {
            errorBanner = "请输入有效的 HTTPS 网关地址。空白或无效地址不会覆盖原配置。"
            return
        }
        let cleaned = MultiProviderAIClient.sanitizePastedKey(adminSecretDraft)
        if !cleaned.isEmpty && !Keychain.setWuMindGatewayAdminSecret(cleaned, for: address) {
            errorBanner = "管理员密钥未能写入钥匙串，原网关地址未改动。"
            return
        }
        adminSecretDraft = ""
        statusBanner = "当前网关的管理凭据已保存。"
        onUpdated()
    }

    private func refreshBalance() {
        statusBanner = nil
        let gatewayURL = wumind.gatewayBaseURL
        guard let secret = Keychain.wuMindGatewayAdminSecret(for: gatewayURL) else {
            errorBanner = "请确认构建的网关地址并保存管理凭据。"
            return
        }
        loadingBalance = true
        errorBanner = nil
        Task { @MainActor in
            defer { loadingBalance = false }
            do {
                let res = try await WuMindGatewayClient().adminRefreshUpstreamBalance(
                    gatewayURL: gatewayURL,
                    adminSecret: secret
                )
                upstreamBalance = res
                alertThresholdDraft = String(format: "%.2f", res.lowBalanceAlertUSD)
                onUpdated()
            } catch {
                errorBanner = (error as? LocalizedError)?.errorDescription ?? "查询 AIHubMix 余额失败。"
            }
        }
    }

    private func saveThreshold() {
        statusBanner = nil
        let gatewayURL = wumind.gatewayBaseURL
        guard let secret = Keychain.wuMindGatewayAdminSecret(for: gatewayURL) else {
            errorBanner = "请确认构建的网关地址并保存管理凭据。"
            return
        }
        guard let val = Double(alertThresholdDraft.trimmingCharacters(in: .whitespacesAndNewlines)), val >= 0 else {
            errorBanner = "请输入有效的美元阈值（>= 0）。"
            return
        }
        savingThreshold = true
        errorBanner = nil
        Task { @MainActor in
            defer { savingThreshold = false }
            do {
                let res = try await WuMindGatewayClient().adminSetUpstreamAlertThreshold(
                    gatewayURL: gatewayURL,
                    adminSecret: secret,
                    lowBalanceAlertUSD: val
                )
                upstreamBalance = res
                statusBanner = String(format: "低余额报警阈值已更新为 $%.2f。", res.lowBalanceAlertUSD)
                onUpdated()
            } catch {
                errorBanner = (error as? LocalizedError)?.errorDescription ?? "保存报警阈值失败。"
            }
        }
    }
}

