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
        var icon: String {
            switch self {
            case .phone: return "iphone.gen3"
            case .wechat: return "message.fill"
            }
        }
    }

    @ObservedObject private var account = AppAccountManager.shared
    @ObservedObject private var wumind = WuMindStore.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

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

    private var isDark: Bool { colorScheme == .dark }
    private var pageBg: Color {
        isDark ? Color(red: 0.035, green: 0.04, blue: 0.062) : Color(red: 0.955, green: 0.96, blue: 0.98)
    }
    private var cardBg: Color {
        isDark ? Color(red: 0.095, green: 0.105, blue: 0.142) : Color.white
    }
    private var cardBorder: Color {
        isDark ? Color.white.opacity(0.09) : Color.black.opacity(0.06)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    WuMindHubHeroBanner(
                        title: "外部人员注册与登录",
                        subtitle: "非值班表人员可使用手机号或微信进入 WUMIND AI 与游戏中心；内部排班数据全链路隔离不可见",
                        icon: "person.badge.shield.checkmark.fill",
                        colors: [Color(red: 0.15, green: 0.42, blue: 0.88), Color(red: 0.32, green: 0.24, blue: 0.80)],
                        chips: [
                            ("可用范围", "WUMIND · 游戏 · 我的"),
                            ("内部隔离", "排班 / 留痕 / 网站全隐藏")
                        ]
                    )

                    // 2-segment full-width method toggle (zero horizontal scroll)
                    HStack(spacing: 6) {
                        ForEach(AuthMethod.allCases) { item in
                            let selected = method == item
                            Button {
                                Haptics.tap()
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                                    method = item
                                    errorBanner = nil
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: item.icon)
                                        .font(.caption.weight(.bold))
                                    Text(item.title)
                                        .font(.caption.weight(.bold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    selected
                                        ? (item == .wechat ? Color.green.opacity(0.20) : Color.blue.opacity(0.20))
                                        : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                )
                                .foregroundStyle(selected ? (item == .wechat ? Color.green : Color.blue) : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(4)
                    .background(cardBg, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))

                    if method == .phone {
                        phoneAuthCard
                    } else {
                        wechatAuthCard
                    }

                    if let statusBanner {
                        bannerRow(icon: "checkmark.circle.fill", text: statusBanner, tint: .green)
                    }
                    if let errorBanner {
                        bannerRow(icon: "exclamationmark.triangle.fill", text: errorBanner, tint: .orange)
                    }

                    // Honest immediate local external-boundary preview
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "shield.lefthalf.filled")
                                .foregroundStyle(.teal)
                            Text("立即体验外部用户权限界限（免短信网关）")
                                .font(.subheadline.weight(.bold))
                        }
                        Text("若管理员尚未在 Cloudflare 绑定短信服务商或微信开放平台 AppID，可直接以外部访客身份进入 App，立即验证外部用户仅可见「WUMIND / 游戏 / 我的」、内部排班全隔离的权限边界。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            Haptics.tap()
                            account.enterLocalExternalMode(nickname: nickname.isEmpty ? "外部用户" : nickname)
                            dismiss()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.right.circle.fill")
                                Text("以外部访客身份进入 WUMIND")
                                    .font(.subheadline.weight(.bold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.teal.opacity(0.16), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                            .foregroundStyle(.teal)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("external.auth.guest")
                    }
                    .padding(14)
                    .background(cardBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))

                    boundaryMatrixCard
                }
                .padding(14)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .background(pageBg.ignoresSafeArea())
            .navigationTitle("外部用户登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("external.auth.sheet")
    }

    private var phoneAuthCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("手机号一键注册 / 登录")
                .font(.subheadline.weight(.bold))

            HStack(spacing: 8) {
                Text("+86")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .background(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                TextField("请输入 11 位中国大陆手机号", text: $phone)
                    .keyboardType(.numberPad)
                    .textContentType(.telephoneNumber)
                    .font(.subheadline.monospacedDigit())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.045), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .accessibilityIdentifier("external.auth.phone")
            }

            HStack(spacing: 8) {
                TextField("6 位短信验证码", text: $smsCode)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .font(.subheadline.monospacedDigit())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.045), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .accessibilityIdentifier("external.auth.code")

                Button {
                    Task { await requestSMSCode() }
                } label: {
                    Group {
                        if sendingCode {
                            ProgressView().controlSize(.small)
                        } else if cooldown > 0 {
                            Text("\(cooldown)s")
                                .font(.caption.weight(.bold).monospacedDigit())
                        } else {
                            Text("获取验证码")
                                .font(.caption.weight(.bold))
                        }
                    }
                    .frame(minWidth: 88)
                    .padding(.vertical, 11)
                    .padding(.horizontal, 10)
                    .background(Color.blue.opacity(0.16), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .disabled(sendingCode || cooldown > 0 || AppAccessBoundary.normalizeMainlandPhone(phone) == nil)
                .accessibilityIdentifier("external.auth.sendSMS")
            }

            TextField("昵称（选填，例如：张工）", text: $nickname)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.045), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            Button {
                Task { await submitSMSLogin() }
            } label: {
                HStack(spacing: 8) {
                    if submitting {
                        ProgressView().tint(.white).controlSize(.small)
                    } else {
                        Image(systemName: "checkmark.shield.fill")
                    }
                    Text(submitting ? "正在验证登录…" : "验证手机号并进入 WUMIND")
                        .font(.subheadline.weight(.bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    LinearGradient(colors: [.blue, .indigo], startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                )
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(submitting || AppAccessBoundary.normalizeMainlandPhone(phone) == nil || !AppAccessBoundary.isValidSMSCode(smsCode))
            .accessibilityIdentifier("external.auth.submitPhone")
        }
        .padding(14)
        .background(cardBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))
    }

    private var wechatAuthCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.green.opacity(0.18))
                        .frame(width: 42, height: 42)
                    Image(systemName: "message.fill")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.green)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("微信开放平台授权登录")
                        .font(.subheadline.weight(.bold))
                    Text("通过 WUMIND 网关安全换取微信 OpenID，不保存微信密码")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("接入前提：需在微信开放平台完成移动应用审核并配置 Universal Links，且管理员在 Cloudflare Workers 填入 `WECHAT_APP_ID` 与 `WECHAT_APP_SECRET`。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("微信 OAuth 授权码（code，由微信回调或测试口令获得）", text: $wechatCode)
                .font(.caption.monospaced())
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.045), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .accessibilityIdentifier("external.auth.wechatCode")

            Button {
                Task { await submitWeChatLogin() }
            } label: {
                HStack(spacing: 8) {
                    if submitting {
                        ProgressView().tint(.white).controlSize(.small)
                    } else {
                        Image(systemName: "message.badge.filled.fill")
                    }
                    Text(submitting ? "正在校验微信授权…" : "验证微信授权并进入 WUMIND")
                        .font(.subheadline.weight(.bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Color.green, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(submitting || wechatCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("external.auth.submitWeChat")
        }
        .padding(14)
        .background(cardBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))
    }

    private var boundaryMatrixCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("App 查看界限说明")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            boundaryRow(allowed: true, title: "WUMIND AI 全栈工作台", detail: "多模型对话、临时聊天、生图、生视频、写 PPT、写标书、插件与语音")
            boundaryRow(allowed: true, title: "游戏中心", detail: "《裂隙对决》等全部休闲对战游戏")
            boundaryRow(allowed: true, title: "个人账号与设置", detail: "自有 API Key 管理、WUMIND 钱包、主题与账号切换")
            Divider().opacity(0.5)
            boundaryRow(allowed: false, title: "内部值班排班 / 日历 / 统计", detail: "仅值班表内部人员可见，外部账号彻底隐藏并拦截深链")
            boundaryRow(allowed: false, title: "值班网站 / 周会纪要 / 工作留痕 / 数传计划", detail: "涉及内部业务与人员花名册，外部账号无权访问")
        }
        .padding(14)
        .background(cardBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))
    }

    private func boundaryRow(allowed: Bool, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: allowed ? "checkmark.circle.fill" : "lock.fill")
                .font(.subheadline)
                .foregroundStyle(allowed ? Color.green : Color.secondary)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(allowed ? .primary : .secondary)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func bannerRow(icon: String, text: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(text)
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
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
                statusBanner = "测试网关模式：已自动填入测试验证码 \(debugCode)。"
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
    @Environment(\.colorScheme) private var colorScheme

    @State private var showingExternalAuth = false
    @State private var showingWallet = false
    @State private var confirmReturnInternal = false

    private var isDark: Bool { colorScheme == .dark }
    private var pageBg: Color {
        isDark ? Color(red: 0.035, green: 0.04, blue: 0.062) : Color(red: 0.955, green: 0.96, blue: 0.98)
    }
    private var cardBg: Color {
        isDark ? Color(red: 0.095, green: 0.105, blue: 0.142) : Color.white
    }
    private var cardBorder: Color {
        isDark ? Color.white.opacity(0.09) : Color.black.opacity(0.06)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Profile Header Card
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: [.blue, .indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 58, height: 58)
                            Image(systemName: "person.fill")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(.white)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(account.externalProfile?.nickname ?? "外部用户")
                                    .font(.headline.weight(.bold))
                                Text(account.externalProfile?.methodDisplayTitle ?? "外部界限")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.teal)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Color.teal.opacity(0.14), in: Capsule())
                            }
                            if let phone = account.externalProfile?.phoneMasked, !phone.isEmpty {
                                Text("手机号：\(phone)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Text(account.accessRole.boundarySummary)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(cardBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))

                    // Quick Actions
                    VStack(spacing: 0) {
                        Button { showingExternalAuth = true } label: {
                            profileRow(icon: "iphone.and.arrow.forward", tint: .blue, title: "手机号 / 微信账号绑定与切换", detail: account.externalProfile?.methodDisplayTitle ?? "去登录")
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 54)

                        Button { showingWallet = true } label: {
                            profileRow(icon: "creditcard.fill", tint: .indigo, title: "WUMIND 钱包与余额", detail: wumind.hasGatewayURL ? "已连网关" : "自带 API / 托管")
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 54)

                        NavigationLink { AIProviderListView() } label: {
                            profileRow(icon: "square.grid.2x2.fill", tint: .purple, title: "WUMIND 能力工坊", detail: "生图 · 生视频 · PPT · 语音")
                        }
                        .buttonStyle(.plain)
                    }
                    .background(cardBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))

                    // Appearance picker
                    VStack(alignment: .leading, spacing: 10) {
                        Text("界面外观")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        Picker("外观", selection: $appStore.settings.appearance) {
                            ForEach(Appearance.allCases, id: \.self) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(14)
                    .background(cardBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))

                    // Boundary Verification Card + Switch back to internal staff
                    VStack(alignment: .leading, spacing: 10) {
                        Label("已开启外部用户查看界限", systemImage: "lock.shield.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.teal)
                        Text("当前账号仅可访问 WUMIND AI、游戏中心与个人账号设置。所有单位内部值班排班表、花名册、工作留痕、周会纪要与值班网站均已完全隔离隐藏。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Button {
                            confirmReturnInternal = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "person.badge.key.fill")
                                Text("我是值班表内部人员 · 切换回内部值班入口")
                                    .font(.caption.weight(.bold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .foregroundStyle(.orange)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("external.profile.switchInternal")
                    }
                    .padding(14)
                    .background(cardBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))
                }
                .padding(14)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .background(pageBg.ignoresSafeArea())
            .navigationTitle("我的")
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

    private func profileRow(icon: String, tint: Color, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(0.15))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
            }
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
            Spacer()
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
