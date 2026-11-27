import SwiftUI
import UIKit

/// Flagship External User Registration & Login Sheet (Phone SMS OTP + WeChat OAuth + Local External Boundary Preview).
/// Clearly explains & enforces the strict viewing boundary between internal duty personnel and external users.
@MainActor
struct ExternalAuthView: View {
    enum AuthMethod: String, CaseIterable, Identifiable {
        case phone
        case wechat
        var id: String { rawValue }
        var title: String {
            switch self {
            case .phone: return "手机号验证码"
            case .wechat: return "微信登录"
            }
        }

    }

    @ObservedObject private var account = AppAccountManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var method: AuthMethod = .phone
    @State private var phone = ""
    @State private var smsCode = ""
    @State private var nickname = ""
    @State private var wechatCode = ""
    @State private var sendingCode = false
    @State private var submitting = false
    @State private var cooldown = 0
    @State private var statusBanner: String?
    @State private var errorBanner: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("登录方式", selection: $method) {
                        ForEach(AuthMethod.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: method) { _ in
                        errorBanner = nil
                        statusBanner = nil
                    }

                    if method == .phone {
                        TextField("中国大陆手机号", text: $phone)
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)
                            .accessibilityIdentifier("external.auth.phone")
                        TextField("6 位短信验证码", text: $smsCode)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .accessibilityIdentifier("external.auth.code")
                        Button(sendingCode ? "发送中…" : (cooldown > 0 ? "\(cooldown) 秒后重新获取" : "获取验证码")) {
                            Task { await requestSMSCode() }
                        }
                        .disabled(sendingCode || cooldown > 0 || AppAccessBoundary.normalizeMainlandPhone(phone) == nil)
                        .accessibilityIdentifier("external.auth.sendSMS")
                    } else {
                        TextField("微信授权码", text: $wechatCode)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .accessibilityIdentifier("external.auth.wechatCode")
                    }
                    TextField("昵称（选填）", text: $nickname)
                        .textContentType(.nickname)
                } footer: {
                    Text("外部账号可使用 WuMind、游戏和个人设置。")
                }

                if let statusBanner { Label(statusBanner, systemImage: "checkmark.circle").foregroundStyle(.secondary) }
                if let errorBanner { AppErrorBannerCard(message: errorBanner) }

                Section {
                    if method == .phone {
                        AppPrimaryCTA(title: "验证并登录", isLoading: submitting,
                                      isDisabled: AppAccessBoundary.normalizeMainlandPhone(phone) == nil || !AppAccessBoundary.isValidSMSCode(smsCode)) {
                            Task { await submitSMSLogin() }
                        }
                        .accessibilityIdentifier("external.auth.submitPhone")
                    } else {
                        AppPrimaryCTA(title: "微信登录", isLoading: submitting,
                                      isDisabled: wechatCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                            Task { await submitWeChatLogin() }
                        }
                        .accessibilityIdentifier("external.auth.submitWeChat")
                    }
                    Button("以本机访客身份进入") {
                        Haptics.tap()
                        account.enterLocalExternalMode(nickname: nickname.isEmpty ? "外部用户" : nickname)
                        dismiss()
                    }
                    .accessibilityIdentifier("external.auth.guest")
                }
            }
            .appList()
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("外部用户登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("收起键盘") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
        }
    }

    private func requestSMSCode() async {
        sendingCode = true
        errorBanner = nil
        statusBanner = nil
        defer { sendingCode = false }
        do {
            let res = try await account.sendSMSCode(phone: phone)
            statusBanner = "验证码已发送至 \(res.maskedPhone ?? AppAccessBoundary.maskedPhone(phone))，5 分钟内有效。"
            if let debugCode = res.debugCode, !debugCode.isEmpty {
                smsCode = debugCode
                statusBanner = "测试验证码已填入。"
            }
            startCooldown(res.cooldownSeconds ?? 60)
        } catch {
            errorBanner = error.localizedDescription
        }
    }

    private func submitSMSLogin() async {
        submitting = true
        errorBanner = nil
        defer { submitting = false }
        do {
            try await account.verifySMSCode(phone: phone, code: smsCode, nickname: nickname)
            Haptics.success()
            dismiss()
        } catch {
            errorBanner = error.localizedDescription
        }
    }

    private func submitWeChatLogin() async {
        submitting = true
        errorBanner = nil
        defer { submitting = false }
        do {
            try await account.loginWithWeChatCode(code: wechatCode, nickname: nickname)
            Haptics.success()
            dismiss()
        } catch {
            errorBanner = error.localizedDescription
        }
    }

    private func startCooldown(_ seconds: Int) {
        cooldown = max(1, seconds)
        Task {
            while cooldown > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if cooldown > 0 { cooldown -= 1 }
            }
        }
    }
}

/// Dedicated 3rd tab ("我的") for external registered users.
/// Strictly exposes ONLY personal settings, WUMIND wallet/keys, and role switching — zero internal duty surfaces.
@MainActor
struct ExternalAccountProfileView: View {
    @EnvironmentObject private var appStore: AppStore
    @ObservedObject private var account = AppAccountManager.shared
    @ObservedObject private var wumind = WuMindStore.shared

    @State private var showingExternalAuth = false
    @State private var showingWallet = false
    @State private var confirmReturnInternal = false

    var body: some View {
        NavigationStack {
            Form {
                Section("账号") {
                    Text(account.externalProfile?.nickname ?? "外部用户")
                        .font(DS.Font.title)
                    LabeledContent("登录方式", value: account.externalProfile?.methodDisplayTitle ?? "本机访客")
                    if let phone = account.externalProfile?.phoneMasked, !phone.isEmpty {
                        LabeledContent("手机号", value: phone)
                    }
                    Button("绑定或切换账号") { showingExternalAuth = true }
                }

                Section("WuMind") {
                    Button { showingWallet = true } label: { Label("钱包与用量", systemImage: "creditcard") }
                    NavigationLink { AIProviderListView() } label: {
                        Label("服务商与个人 Key", systemImage: "key")
                    }
                }
                Section("外观") {
                    Picker("显示模式", selection: $appStore.settings.appearance) {
                        ForEach(Appearance.allCases, id: \.self) { mode in Text(mode.title).tag(mode) }
                    }
                }
                Section {
                    Button("切换到内部人员入口") { confirmReturnInternal = true }
                        .accessibilityIdentifier("external.profile.switchInternal")
                } footer: {
                    Text("当前可访问 WuMind、游戏和个人设置。内部值班功能需要值班网站账号。")
                }
            }
            .appList()
            .navigationTitle("我的")
            .observeTabRootNavigationDepth(tabID: "ext.profile")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingExternalAuth) { ExternalAuthView() }
            .sheet(isPresented: $showingWallet) { WuMindWalletSheet(store: wumind) }
            .confirmationDialog("切换回值班表内部人员入口？", isPresented: $confirmReturnInternal, titleVisibility: .visible) {
                Button("切换并连接内部值班账号") {
                    account.signOutExternal(returnToRosterOnboarding: appStore.settings.lastSync == nil)
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("切换后将恢复内部排班标签栏；未连接过值班网站的设备需要重新登录值班网站验证身份。")
            }
        }
    }

}
