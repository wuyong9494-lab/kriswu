import PhotosUI
import SwiftUI
import UIKit

// MARK: - User-Facing WUMIND Wallet, Recharge QR & Live Pricing Sheet (Read-Only Config)

struct WuMindWalletSheet: View {
    @ObservedObject var store: WuMindStore
    @Environment(\.dismiss) private var dismiss

    @State private var voucherDraft = ""
    @State private var gatewayDraft = ""
    @State private var busy = false
    @State private var feedback: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                // Account & Live Balance Header Card
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("WUMIND 内置通道余额")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(formattedBalance)
                                    .font(.system(size: 32, weight: .black, design: .rounded))
                                    .foregroundStyle(.primary)
                            }
                            Spacer()
                            Button {
                                refreshAll()
                            } label: {
                                if busy {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Label("刷新", systemImage: "arrow.clockwise")
                                        .font(.caption.weight(.semibold))
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(busy || !store.hasGatewayURL)
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

                        if let status = store.managedAccountStatus {
                            HStack(spacing: 16) {
                                Text("累计充值 ¥\(String(format: "%.2f", status.totalRechargedYuan))")
                                Text("累计消耗 ¥\(String(format: "%.4f", status.totalSpentYuan))")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
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

                // Voucher Code Instant Redemption
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

                // Admin Payment QR Codes (Strictly Read-Only for Users)
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

                // Live Pricing Table (Read-Only for Users; 1-tap switches model!)
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
                } header: {
                    Text("WUMIND 内置模型实时计费价目表（点选即用）")
                } footer: {
                    Text("每次对话结束后，网关按厂商返回的真实输入 / 输出 / 思考 Token 数毫秒级自动扣费。")
                }

                // Recent Real-Time Billing Ledger
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

                // Gateway Endpoint (Only if not preconfigured yet)
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
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("WUMIND 钱包与计费")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
            .onAppear {
                gatewayDraft = store.gatewayBaseURL
                if store.hasGatewayURL {
                    refreshAll()
                }
            }
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
        case "chat": return entry.model.isEmpty ? "AI 对话" : entry.model
        case "redeem": return "兑换码充值"
        case "admin_topup": return "管理员扫码入账"
        case "welcome": return "新用户体验金"
        default: return entry.kind
        }
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
                }
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? "同步网关配置失败。"
            }
        }
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
        .onAppear {
            gatewayURLDraft = wumind.gatewayBaseURL
            hasAdminSecret = Keychain.wumindGatewayAdminSecret != nil
            configDraft = wumind.managedConfig
        }
    }

    private var adminForm: some View {
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
                        .foregroundStyle(DS.Palette.danger)
                }
            }

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
