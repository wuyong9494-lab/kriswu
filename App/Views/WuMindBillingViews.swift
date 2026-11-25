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

    /// Apple Developer Program License Agreement (§7.4): TestFlight builds MUST NOT charge beta testers
    /// real money for digital purchases, including external WeChat/Alipay checkout redirects or QR codes.
    private var isTestFlightComplianceRestricted: Bool {
        SigningInfo.isTestFlight
    }

    var body: some View {
        NavigationStack {
            List {
                balanceOverviewSection
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

    private var balanceOverviewSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                // Flagship Dark-Indigo Balance Card
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text("WUMIND 可用余额")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.white.opacity(0.78))
                                if store.isBillingExempt {
                                    Text("管理员免充值")
                                        .font(.caption2.weight(.bold))
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 2)
                                        .background(Color.green.opacity(0.32), in: Capsule())
                                        .foregroundStyle(.white)
                                }
                            }
                            Text(formattedBalance)
                                .font(.system(size: 32, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                                .accessibilityIdentifier("wumind.wallet.balance")
                            if let reserved = store.managedAccountStatus?.reservedYuan, reserved > 0 {
                                Text(String(format: "含进行中任务预留 ¥%.4f（失败自动全额释放）", reserved))
                                    .font(.caption2)
                                    .foregroundStyle(Color.white.opacity(0.82))
                            }
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

                if store.isBillingExempt {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundStyle(.purple)
                        Text(String(format: "已开通服务端校验的「管理员免充值」通道：余额为 ¥0 亦可调用文字/生图/视频/实时语音/PPT，不扣钱包余额但完整记录用量（日上限 ¥%.0f）。", store.managedAccountStatus?.dailyCostCapYuan ?? 200))
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
                            Text(String(format: "实购 ¥%.2f · 赠额 ¥%.2f", status.purchasedRechargedYuan ?? 0, status.adminGrantedYuan ?? 0))
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
                        sub: "共 \(store.managedAccountStatus?.totalRequests ?? 0) 次请求",
                        tint: .blue
                    )
                    walletStatTile(
                        title: "累计消费金额",
                        value: String(format: "¥%.4f", store.managedAccountStatus?.totalSpentYuan ?? 0),
                        sub: "输入 \(WuMindAccountStatus.formatTokens(store.managedAccountStatus?.totalPromptTokens ?? 0)) · 输出 \(WuMindAccountStatus.formatTokens((store.managedAccountStatus?.totalCompletionTokens ?? 0) + (store.managedAccountStatus?.totalReasoningTokens ?? 0)))",
                        tint: .orange
                    )
                    walletStatTile(
                        title: "真实购买 / 赠额",
                        value: String(format: "¥%.2f", store.managedAccountStatus?.purchasedRechargedYuan ?? store.managedAccountStatus?.totalRechargedYuan ?? 0),
                        sub: String(format: "管理员赠额 ¥%.2f", store.managedAccountStatus?.adminGrantedYuan ?? 0),
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

    private var testFlightComplianceSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.blue)
                    Text("TestFlight 测试版合规保护（0 元不收真实费用）")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                }
                Text("依据 Apple TestFlight 条款，测试版本严禁向测试者收取真实费用（包括 App 内外跳微信/支付宝或扫码转账）。当前已自动关闭全部真实付费通道。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("• 推荐测试：免费使用「自带 API」通道，或输入管理员发放的免费测试兑换码。\n• 内购验收：下方 Apple StoreKit 2 仅走 Apple 沙盒（0 元不扣费），经服务端 Apple Root CA - G3 证书链验签后计入独立沙盒测试余额，绝不混入正式余额。")
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
        if entry.kind.hasPrefix("admin_exempt_") {
            return "管理员免扣 · \(entry.model.isEmpty ? entry.kind : entry.model)"
        }
        switch entry.kind {
        case "chat":
            if entry.model == "web_search" { return "联网深度搜索" }
            return entry.model.isEmpty ? "AI 对话" : entry.model
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
    @State private var newModelProvider = "aihubmix"
    @State private var newModelName = ""
    @State private var newModelInputPrice = "10"
    @State private var newModelOutputPrice = "40"
    @State private var newModelThinking = true

    @State private var voucherAmount = "30"
    @State private var voucherCount = 1
    @State private var voucherNote = "测试兑换码"
    @State private var generatedVouchers: [WuMindVoucher] = []

    // Manual admin credit with WM- lookup + confirmation sheet + idempotency
    @State private var topUpUserID = ""
    @State private var topUpAmount = "20"
    @State private var topUpEnvironment = "production"
    @State private var topUpNote = "管理员人工赠额"
    @State private var lookedUpUser: WuMindAdminUserRecord? = nil
    @State private var lookupMatches: [WuMindAdminLookupMatch] = []
    @State private var pendingCreditIdempotencyKey: String = ""
    @State private var showingTopUpConfirm = false

    // AIHubMix pool balance + alert threshold
    @State private var upstreamBalance: WuMindAdminUpstreamBalance? = nil
    @State private var alertThresholdDraft = "10"
    @State private var loadingBalance = false
    @State private var savingThreshold = false

    // Dedicated sheets
    @State private var showingSetupGuide = false
    @State private var showingUserDirectory = false
    @State private var showingModelCatalog = false

    @State private var summary: WuMindAdminSummary?
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
                    Text("定价策略、收款二维码、AIHubMix 池余额、免扣权限与加余额仅限管理员登录后修改。请前往「设置 › 身份」输入管理员密码。")
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
        .toolbarBackground(.visible, for: .navigationBar)
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
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("收起键盘") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
        }
        .sheet(isPresented: $showingSetupGuide) {
            WuMindAdminSetupGuideSheet()
        }
        .sheet(isPresented: $showingUserDirectory) {
            if let secret = Keychain.wumindGatewayAdminSecret, wumind.hasGatewayURL {
                WuMindAdminUserDirectorySheet(gatewayURL: wumind.gatewayBaseURL, adminSecret: secret)
            }
        }
        .sheet(isPresented: $showingModelCatalog) {
            if let secret = Keychain.wumindGatewayAdminSecret, wumind.hasGatewayURL {
                WuMindAdminModelCatalogSheet(gatewayURL: wumind.gatewayBaseURL, adminSecret: secret) {
                    Task { try? await wumind.syncManagedGatewayConfig() }
                }
            }
        }
        .sheet(isPresented: $showingTopUpConfirm) {
            if let target = lookedUpUser, let amt = Double(topUpAmount), amt > 0 {
                WuMindAdminManualCreditConfirmSheet(
                    target: target,
                    amountYuan: amt,
                    environment: topUpEnvironment,
                    note: topUpNote,
                    isSubmitting: busy,
                    onConfirm: {
                        confirmDirectTopUp(target: target, amount: amt)
                    }
                )
            }
        }
        .onAppear {
            gatewayURLDraft = wumind.gatewayBaseURL
            hasAdminSecret = Keychain.wumindGatewayAdminSecret != nil
            configDraft = wumind.managedConfig
            if wumind.hasGatewayURL, Keychain.wumindGatewayAdminSecret != nil, upstreamBalance == nil {
                fetchUpstreamBalance(refresh: false)
            }
        }
    }

    private var adminHeaderSection: some View {
        Section {
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

            Button {
                Haptics.tap()
                showingSetupGuide = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "crown.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.indigo, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("管理员 6 步上线与计费配置教程")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                        Text("Cloudflare Workers + D1 · Manage Key · StoreKit 2 · 免扣管理员")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("wumind.admin.guide")

            Button {
                saveConnectionLocally()
                guard wumind.hasGatewayURL, Keychain.wumindGatewayAdminSecret != nil else {
                    errorBanner = "请先在下方填写网关地址和 ADMIN_SECRET。"
                    return
                }
                showingUserDirectory = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "person.3.sequence.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Color.purple, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("注册用户 · 充值 · 用量与管理员免扣")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("查看全部注册账号、实购/赠额/消耗明细及单号免充值开关")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 2)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("wumind.admin.userDirectory")

            Button {
                saveConnectionLocally()
                guard wumind.hasGatewayURL, Keychain.wumindGatewayAdminSecret != nil else {
                    errorBanner = "请先在下方填写网关地址和 ADMIN_SECRET。"
                    return
                }
                showingModelCatalog = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "cpu.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Color.teal, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("动态模型目录（同步 · 实测 · 定价 · 启用）")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("按对话 / 文生图 / 参考图编辑 / 视频分能力实测验证后上架")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 2)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("wumind.admin.modelCatalog")
        } header: {
            Text("运营总控入口")
        }
    }

    private var adminForm: some View {
        Form {
            // Topmost: AIHubMix Shared Pool Account Balance & Low-Balance Alert
            WuMindAdminUpstreamBalanceSection(
                balance: upstreamBalance,
                isLoading: loadingBalance,
                isSavingThreshold: savingThreshold,
                alertThresholdDraft: $alertThresholdDraft,
                onRefresh: { fetchUpstreamBalance(refresh: true) },
                onSaveThreshold: { saveUpstreamAlertThreshold() }
            )

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
                    .buttonStyle(.borderedProminent)
                    .disabled(busy)
                }
            } header: {
                Text("1. 云端计费网关（Cloudflare Workers + D1）")
            } footer: {
                Text("厂商推理 Key（AIHUBMIX_API_KEY）与管理令牌（AIHUBMIX_MANAGE_KEY）仅放在 Cloudflare Secrets 中，绝不打包进 App。管理员密钥仅存当前设备钥匙串。")
            }

            // 2. Manual Admin Credit ("给用户加余额") with WM- Lookup, Environment, Confirmation & Audit Trail
            Section {
                HStack(spacing: 8) {
                    TextField("输入 WM- 账号 ID 或姓名查找", text: $topUpUserID)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                        .accessibilityIdentifier("wumind.admin.topUpUserID")
                    Button("查找") {
                        lookupTargetUser()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(busy || topUpUserID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("wumind.admin.lookupUserButton")
                }

                if !lookupMatches.isEmpty && lookedUpUser == nil {
                    ForEach(lookupMatches) { m in
                        Button {
                            topUpUserID = m.userID
                            lookupTargetUser()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(m.displayName.isEmpty ? m.userID : "\(m.displayName) · \(m.userID)")
                                        .font(.caption.weight(.semibold))
                                    Text(String(format: "正式余 ¥%.2f · 沙盒余 ¥%.2f", m.balanceYuan, m.sandboxBalanceYuan ?? 0))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("选择").font(.caption2.weight(.bold)).foregroundStyle(.indigo)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let u = lookedUpUser {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Label("已核对账号：\(u.userID)", systemImage: "checkmark.seal.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.green)
                            Spacer()
                            if !u.displayName.isEmpty {
                                Text(u.displayName)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(String(format: "正式可用 ¥%.2f（实购 ¥%.2f · 赠额 ¥%.2f）· 沙盒 ¥%.2f",
                                    u.availableYuan ?? u.balanceYuan,
                                    u.purchasedRechargedYuan ?? 0,
                                    u.adminGrantedYuan ?? 0,
                                    u.sandboxBalanceYuan ?? 0))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }

                Picker("加款环境", selection: $topUpEnvironment) {
                    Text("正式余额 (Production)").tag("production")
                    Text("沙盒测试余额 (Sandbox)").tag("sandbox")
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("加款金额 ¥")
                    TextField("20", text: $topUpAmount)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("wumind.admin.topUpAmount")
                }

                TextField("审计备注（如：内部测试赠额 / 补偿）", text: $topUpNote)
                    .font(.footnote)

                Button {
                    prepareTopUpConfirmation()
                } label: {
                    HStack {
                        Spacer()
                        Label("核对并给用户加余额", systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.bold))
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy || topUpUserID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("wumind.admin.topUpSubmit")
            } header: {
                Text("2. 给用户加余额（先查人 · 二次确认 · 独立赠额账本）")
            } footer: {
                Text("人工加余额严格记为 admin_grant（写入 admin_credit_audit 审计表），与 Apple 内购真实收入完全分离；带单次与日限额及幂等防重。")
            }

            adminComplianceSection

            // 3. Payment QR Codes & Recharge Guidance
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
                Text("3. 收款二维码与充值说明（仅管理员可改）")
            }

            // 4. Per-Model Custom Pricing Table (Higher than Official Cost)
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
                            Text("AIHubMix 统一中转").tag("aihubmix")
                            Text("DeepSeek 官方").tag("deepSeek")
                            Text("OpenAI 官方").tag("openAI")
                            Text("Google Gemini 官方").tag("gemini")
                            Text("Anthropic Claude 官方").tag("claude")
                            Text("xAI Grok 官方").tag("grok")
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
                Text("4. 自定义对话模型售价表（单位：元 / 百万 Token）")
            } footer: {
                Text("推荐优先使用上方「动态模型目录」按能力实测后再上架；下方保留兼容定价表供快速维护。")
            }

            // 5. Voucher Generator (Instant Code Top-Up)
            Section {
                HStack(spacing: 8) {
                    Text("面额 ¥")
                    TextField("30", text: $voucherAmount)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 84)
                    Stepper("张数：\(voucherCount)", value: $voucherCount, in: 1...20)
                }
                TextField("备注（如：内测兑换码）", text: $voucherNote)
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
                Text("5. 发放免费测试 / 充值兑换码（用户核销秒到账）")
            }

            // 6. Live Revenue, Grant Separation & Audit Summary
            if let summary {
                Section("6. 云端账务与运营实况") {
                    LabeledContent("注册用户数", value: "\(summary.userCount) 人")
                    LabeledContent("真实内购/收款入账", value: String(format: "¥%.2f", summary.totalPurchasedYuan ?? summary.totalRechargedYuan))
                    LabeledContent("管理员人工赠额（独立核算）", value: String(format: "¥%.2f", summary.totalAdminGrantedYuan ?? 0))
                    LabeledContent("累计实时扣费", value: String(format: "¥%.4f", summary.totalSpentYuan))
                    LabeledContent("全员正式余额（含预留）", value: String(format: "¥%.2f", summary.totalBalanceYuan))
                    if let sb = summary.totalSandboxBalanceYuan, sb > 0 {
                        LabeledContent("全员沙盒测试余额", value: String(format: "¥%.2f", sb))
                    }

                    if let audits = summary.recentAdminCredits, !audits.isEmpty {
                        ForEach(audits.prefix(5)) { audit in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text("\(audit.targetUserID ?? "-") · +\(String(format: "¥%.2f", audit.amountYuan))")
                                        .font(.caption.monospaced().weight(.semibold))
                                    Spacer()
                                    Text(audit.environment == "sandbox" ? "沙盒" : "正式")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(audit.environment == "sandbox" ? .orange : .green)
                                }
                                Text("操作前 ¥\(String(format: "%.2f", audit.balanceBeforeYuan)) → 后 ¥\(String(format: "%.2f", audit.balanceAfterYuan)) · \(audit.note)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .modifier(AvoidTabBar())
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
                Text("• Apple StoreKit 2 验签：POST /v1/iap/verify（含 appAccountToken 归属核验）")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                Text("• Apple 退款/撤销回调：POST /v1/iap/apple-notifications")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        } header: {
            Text("合规收款模式、搜索单价与 StoreKit 2 验签（仅管理员可改）")
        } footer: {
            Text("App Store 正式版默认走 Apple 应用内购（StoreKit 2）；TestFlight 测试版严禁收取真实费用。")
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

    private func fetchUpstreamBalance(refresh: Bool) {
        saveConnectionLocally()
        guard wumind.hasGatewayURL, let secret = Keychain.wumindGatewayAdminSecret else {
            errorBanner = "请先填写网关地址和 ADMIN_SECRET 后再查询 AIHubMix 余额。"
            return
        }
        loadingBalance = true
        errorBanner = nil
        Task { @MainActor in
            defer { loadingBalance = false }
            do {
                let res = refresh
                    ? try await WuMindGatewayClient().adminRefreshUpstreamBalance(gatewayURL: wumind.gatewayBaseURL, adminSecret: secret)
                    : try await WuMindGatewayClient().adminFetchUpstreamBalance(gatewayURL: wumind.gatewayBaseURL, adminSecret: secret, refresh: false)
                upstreamBalance = res
                alertThresholdDraft = String(format: "%.2f", res.lowBalanceAlertUSD)
            } catch {
                errorBanner = (error as? LocalizedError)?.errorDescription ?? "查询 AIHubMix 余额失败。"
            }
        }
    }

    private func saveUpstreamAlertThreshold() {
        saveConnectionLocally()
        guard wumind.hasGatewayURL, let secret = Keychain.wumindGatewayAdminSecret else {
            errorBanner = "请先填写网关地址和 ADMIN_SECRET。"
            return
        }
        guard let val = Double(alertThresholdDraft.trimmingCharacters(in: .whitespacesAndNewlines)), val >= 0 else {
            errorBanner = "请输入有效的美元报警阈值（>= 0）。"
            return
        }
        savingThreshold = true
        errorBanner = nil
        Task { @MainActor in
            defer { savingThreshold = false }
            do {
                let res = try await WuMindGatewayClient().adminSetUpstreamAlertThreshold(
                    gatewayURL: wumind.gatewayBaseURL,
                    adminSecret: secret,
                    lowBalanceAlertUSD: val
                )
                upstreamBalance = res
                statusBanner = String(format: "低余额报警阈值已更新为 $%.2f。", res.lowBalanceAlertUSD)
            } catch {
                errorBanner = (error as? LocalizedError)?.errorDescription ?? "保存报警阈值失败。"
            }
        }
    }

    private func lookupTargetUser() {
        saveConnectionLocally()
        guard wumind.hasGatewayURL, let secret = Keychain.wumindGatewayAdminSecret else {
            errorBanner = "请先填写网关地址和 ADMIN_SECRET。"
            return
        }
        let query = topUpUserID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        busy = true
        errorBanner = nil
        lookedUpUser = nil
        lookupMatches = []
        Task { @MainActor in
            defer { busy = false }
            do {
                let res = try await WuMindGatewayClient().adminLookupUser(
                    gatewayURL: wumind.gatewayBaseURL,
                    adminSecret: secret,
                    query: query
                )
                if res.found, let user = res.user {
                    lookedUpUser = user
                    topUpUserID = user.userID
                    statusBanner = "已查到账号 \(user.userID)（当前正式余额 ¥\(String(format: "%.2f", user.balanceYuan))）。"
                } else if let matches = res.matches, !matches.isEmpty {
                    lookupMatches = matches
                    statusBanner = "查到 \(matches.count) 个候选用户，请在下方点选具体账号。"
                } else {
                    errorBanner = "未找到匹配的用户 \(query)。"
                }
            } catch {
                errorBanner = (error as? LocalizedError)?.errorDescription ?? "查找用户失败。"
            }
        }
    }

    private func prepareTopUpConfirmation() {
        errorBanner = nil
        guard let amount = Double(topUpAmount), amount > 0 else {
            errorBanner = "请输入大于 0 的入账金额。"
            return
        }
        guard amount <= 500 else {
            errorBanner = "单次人工赠额不能超过默认安全上限 ¥500（需提高上限请调整 Cloudflare 环境变量）。"
            return
        }
        if let u = lookedUpUser, u.userID.uppercased() == topUpUserID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
            pendingCreditIdempotencyKey = "adm-topup-\(UUID().uuidString.prefix(12))"
            showingTopUpConfirm = true
        } else {
            // Auto-lookup first so Admin ALWAYS confirms the real user identity & balance before crediting!
            saveConnectionLocally()
            guard wumind.hasGatewayURL, let secret = Keychain.wumindGatewayAdminSecret else {
                errorBanner = "请先填写网关地址和 ADMIN_SECRET。"
                return
            }
            busy = true
            Task { @MainActor in
                defer { busy = false }
                do {
                    let res = try await WuMindGatewayClient().adminLookupUser(
                        gatewayURL: wumind.gatewayBaseURL,
                        adminSecret: secret,
                        query: topUpUserID
                    )
                    if res.found, let user = res.user {
                        lookedUpUser = user
                        topUpUserID = user.userID
                        pendingCreditIdempotencyKey = "adm-topup-\(UUID().uuidString.prefix(12))"
                        showingTopUpConfirm = true
                    } else if let matches = res.matches, !matches.isEmpty {
                        lookupMatches = matches
                        errorBanner = "查到多个相似账号，请先在下方点选确认目标账号。"
                    } else {
                        errorBanner = "未找到目标用户，请先核对 WM- 账号 ID。"
                    }
                } catch {
                    errorBanner = (error as? LocalizedError)?.errorDescription ?? "查找目标用户失败。"
                }
            }
        }
    }

    private func confirmDirectTopUp(target: WuMindAdminUserRecord, amount: Double) {
        guard wumind.hasGatewayURL, let secret = Keychain.wumindGatewayAdminSecret else {
            errorBanner = "请先填写网关地址和 ADMIN_SECRET。"
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
                    userID: target.userID,
                    amountYuan: amount,
                    note: topUpNote,
                    environment: topUpEnvironment,
                    operatorID: wumind.managedAccountID.isEmpty ? "admin" : wumind.managedAccountID,
                    idempotencyKey: pendingCreditIdempotencyKey
                )
                showingTopUpConfirm = false
                lookedUpUser = nil
                topUpUserID = ""
                let envTitle = topUpEnvironment == "sandbox" ? "沙盒测试余额" : "正式余额"
                let latestBal = topUpEnvironment == "sandbox" ? (res.sandboxBalanceYuan ?? res.balanceYuan) : res.balanceYuan
                statusBanner = "已为 \(res.userID) 赠送\(envTitle) ¥\(String(format: "%.2f", amount))，最新余额 ¥\(String(format: "%.2f", latestBal))（审计单号 \(res.auditID ?? "-")）。"
                pullCloudConfigAndSummary()
            } catch {
                showingTopUpConfirm = false
                errorBanner = (error as? LocalizedError)?.errorDescription ?? "加余额失败。"
            }
        }
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
                if let bal = try? await WuMindGatewayClient().adminFetchUpstreamBalance(
                    gatewayURL: wumind.gatewayBaseURL,
                    adminSecret: secret,
                    refresh: false
                ) {
                    upstreamBalance = bal
                    alertThresholdDraft = String(format: "%.2f", bal.lowBalanceAlertUSD)
                }
                statusBanner = "已从云端同步最新定价、账务统计与 API 池余额。"
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
}
