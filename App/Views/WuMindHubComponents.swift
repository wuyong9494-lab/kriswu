import SwiftUI
import UIKit

// MARK: - Shared Flagship Secondary-Screen Visual System

/// Reusable modern AI-app hero banner for WUMIND secondary hubs (Projects, Schedules, Settings, Sync, Wallet).
struct WuMindHubHeroBanner: View {
    let title: String
    let subtitle: String
    let icon: String
    let colors: [Color]
    var chips: [(String, String)] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.84))
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }

            if !chips.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(chip.0)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.72))
                            Text(chip.1)
                                .font(.caption.monospacedDigit().weight(.bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: (colors.first ?? .indigo).opacity(0.24), radius: 14, y: 6)
    }
}

/// Squircle colored icon badge for flagship settings & hub cards.
struct WuMindIconBadge: View {
    let icon: String
    let color: Color

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(
                LinearGradient(colors: [color, color.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 8.5, style: .continuous)
            )
    }
}

// MARK: - User-Facing WUMIND Recharge & Real-Time Metering Tutorial Sheet

struct WuMindRechargeGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var pageBg: Color {
        colorScheme == .dark ? Color(red: 0.07, green: 0.08, blue: 0.11) : Color(red: 0.96, green: 0.965, blue: 0.985)
    }
    private var cardBg: Color {
        colorScheme == .dark ? Color(red: 0.125, green: 0.14, blue: 0.175) : Color.white
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    WuMindHubHeroBanner(
                        title: "WUMIND 充值与计费新手教程",
                        subtitle: "3 分钟看懂双通道区别、三种秒到账充值方式与毫秒级透明扣费",
                        icon: "book.closed.fill",
                        colors: [Color(red: 0.24, green: 0.34, blue: 0.92), Color(red: 0.44, green: 0.28, blue: 0.86)]
                    )

                    guideStepCard(
                        step: "1",
                        title: "两种使用通道随心切（互不影响）",
                        color: .indigo,
                        bullets: [
                            "「自带 API」通道：填入你自己申请的 DeepSeek / OpenAI / Gemini / Claude / Grok API Key（支持中转站地址），费用直接由对应厂商结算，WUMIND 零抽成。",
                            "「WUMIND 内置」通道：无需自备国外信用卡或折腾代理，点击激活自动分配专属账号 ID（如 WM-849201），充值后按真实 Token 实时计费，一个余额通吃全模型。"
                        ]
                    )

                    guideStepCard(
                        step: "2",
                        title: "三种充值方式（付款后自动秒到账）",
                        color: .teal,
                        bullets: [
                            "方式 A · Apple 应用内购：在钱包页直接点选 ¥6 / ¥18 / ¥68 / ¥198 流量包，使用 Face ID / Apple Pay 付款，StoreKit 2 自动校验签名并即时到账。",
                            "方式 B · 微信 / 支付宝在线自动充值：在钱包选择 ¥10 / ¥30 / ¥68 / ¥198 或自定义金额，点击「立即支付并自动到账」完成支付后切回 WUMIND，钱包会自动每 3 秒查单并在到账瞬间弹出提醒、刷新余额，全程无需联系客服。",
                            "方式 C · 兑换码秒充（或个人码备用）：粘贴管理员提供的 WM-XXXX-XXXX-XXXX 兑换码一键秒充；若使用管理员个人静态收款码转账，请备注账号 ID（WM-XXXXXX）以便入账。"
                        ]
                    )

                    guideStepCard(
                        step: "3",
                        title: "计费完全透明，失败请求绝不扣费",
                        color: .orange,
                        bullets: [
                            "每次对话结束后，消息下方会直接显示「输入 Token · 输出 Token · 本次扣费 ¥0.xxxx」，点一下就能看完整账单流水。",
                            "价格单位为「元 / 百万 Token」：例如 1000 个汉字约 1500 Token，使用 DeepSeek 聊一轮长问答通常仅需 ¥0.005 ~ ¥0.02（几厘到几分钱）。",
                            "开启多步骤「智能体」时，每步工具调用、联网搜索单价与总费用上限（默认 ¥2.00 护栏）均可在设置里自定义；网络中断或上游报错不扣费。"
                        ]
                    )

                    guideStepCard(
                        step: "4",
                        title: "iPhone ↔ iPad 多设备共享余额与加密同步",
                        color: .purple,
                        bullets: [
                            "在「WUMIND 设置 › 跨设备端到端加密同步」中生成 10 分钟设备配对码，在另一台 iPhone / iPad 输入绑定后，两台设备共用同一个余额、账单和 AES-256-GCM 加密云端对话库，互不踢下线。"
                        ]
                    )
                }
                .padding(16)
            }
            .background(pageBg.ignoresSafeArea())
            .navigationTitle("充值与计费教程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("我知道了") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("wumind.wallet.guideSheet")
    }

    private func guideStepCard(step: String, title: String, color: Color, bullets: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Text("STEP \(step)")
                    .font(.system(size: 10.5, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(color, in: Capsule())
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
            }
            ForEach(Array(bullets.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(color.opacity(0.75))
                        .frame(width: 5.5, height: 5.5)
                        .padding(.top, 6.5)
                    Text(line)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(color.opacity(0.20), lineWidth: 1)
        )
    }
}

// MARK: - Admin-Only From-Zero Deployment & Monetization Tutorial Sheet

struct WuMindAdminSetupGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var pageBg: Color {
        colorScheme == .dark ? Color(red: 0.07, green: 0.08, blue: 0.11) : Color(red: 0.96, green: 0.965, blue: 0.985)
    }
    private var cardBg: Color {
        colorScheme == .dark ? Color(red: 0.125, green: 0.14, blue: 0.175) : Color.white
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    WuMindHubHeroBanner(
                        title: "管理员从零部署与商业化教程",
                        subtitle: "零服务器月租（Cloudflare Workers + D1 免费额度），10 分钟跑通实时扣费、自动到账收款与 Apple 内购",
                        icon: "crown.fill",
                        colors: [Color(red: 0.12, green: 0.16, blue: 0.30), Color(red: 0.36, green: 0.24, blue: 0.78)]
                    )

                    adminStepCard(
                        step: "1",
                        title: "部署 Cloudflare Workers + D1 云端计费网关",
                        color: .indigo,
                        summary: "在电脑终端进入仓库里的 Services/WuMindGateway 目录，登录免费 Cloudflare 账号并建库、建表、一键上线（点击下方命令可直接复制）：",
                        commands: [
                            "cd Services/WuMindGateway && npx wrangler login",
                            "npx wrangler d1 create wumind-billing-db",
                            "npx wrangler d1 execute wumind-billing-db --remote --file=./schema.sql",
                            "npx wrangler deploy"
                        ],
                        note: "把 wrangler d1 create 输出的 database_id 填进 Services/WuMindGateway/wrangler.toml 后，再执行建表与 deploy。部署成功会得到你的专属 HTTPS 地址（如 https://wumind-gateway.xxx.workers.dev）。"
                    )

                    adminStepCard(
                        step: "2",
                        title: "写入管理员密码与各厂商真实 API Key（放云端 Secrets）",
                        color: .teal,
                        summary: "真实 API Key 绝不打包进 App，全部存在 Cloudflare Secrets 中（按需只填你要开放的厂商即可）：",
                        commands: [
                            "npx wrangler secret put ADMIN_SECRET",
                            "npx wrangler secret put DEEPSEEK_API_KEY",
                            "npx wrangler secret put OPENAI_API_KEY",
                            "npx wrangler secret put GEMINI_API_KEY",
                            "npx wrangler secret put CLAUDE_API_KEY",
                            "npx wrangler secret put GROK_API_KEY"
                        ],
                        note: "可选增强：写入 TAVILY_API_KEY（或 BRAVE_SEARCH_API_KEY）启用高质量联网搜索；自动收款回调密钥请见第 5 步。"
                    )

                    adminStepCard(
                        step: "3",
                        title: "在 App 管理员后台连接网关并验证",
                        color: .blue,
                        summary: "回到上一页「WUMIND 商业计费管理」第 1 区：",
                        commands: [],
                        note: "① 填入第 1 步得到的 https://...workers.dev 网关地址；\n② 填入第 2 步你自定的 ADMIN_SECRET；\n③ 点击「保存连接信息」→ 点击「拉取云端」，看到顶部绿色提示即代表连接成功！"
                    )

                    adminStepCard(
                        step: "4",
                        title: "设定盈利倍率、收款合规模式与收款二维码",
                        color: .orange,
                        summary: "定价表默认按官方成本加价展示，你可自由调整售价（利润 = 你的售价 − 官方成本）：",
                        commands: [],
                        note: "• 合规模式：TestFlight 内外测可选「混合模式」或「仅扫码/兑换码」；提交 App Store 正式审核前请切换为「仅 Apple 应用内购」。\n• 一键调价：点 1.5× / 2.0× / 2.5× / 3.0× 快速加价，或逐个模型微调「输入价 / 输出价（¥/百万 Token）」与「联网搜索单价」。\n• 收款码：上传你的微信/支付宝收款码和联系方式，最后务必点击蓝色大按钮「保存并发布定价与二维码」，全员立即生效！"
                    )

                    adminStepCard(
                        step: "5",
                        title: "开启「用户付款后 100% 全自动到账」（零人工值守）",
                        color: .green,
                        summary: "个人静态收款图片本身无法向服务器发回调；想要真正自动到账，推荐任选下方两种全自动通道：",
                        commands: [
                            "npx wrangler secret put EPAY_API_URL",
                            "npx wrangler secret put EPAY_PID",
                            "npx wrangler secret put EPAY_KEY",
                            "npx wrangler secret put PAYMENT_WEBHOOK_SECRET"
                        ],
                        note: "• 全自动通道 1 · 微信/支付宝在线收银台（易支付/彩虹易支付协议）：填入 EPAY_API_URL / EPAY_PID / EPAY_KEY 后，用户点「立即支付并自动到账」自动拉起收银台，付款成功回调 /v1/webhooks/epay 自动验签入账，用户切回 App 后 3 秒内自动弹窗到账！\n• 全自动通道 2 · 自定义回调或免签监控：设置 PAYMENT_WEBHOOK_SECRET（及可选 PAYMENT_CHECKOUT_URL），收款监听端向 /v1/webhooks/payment 推送 HMAC-SHA256 签名 JSON（传 orderID 与 amountYuan 即可自动匹配用户），幂等秒入账。\n• 全自动通道 3 · Apple StoreKit 2 内购：在 App Store Connect 创建 4 个消耗型 SKU（com.kriswu.wumind.credit.6 / .18 / .68 / .198），Apple Pay 付款后自动核销 JWS 秒到账。\n• 备用通道 · 兑换码发卡 / 按账号 ID 人工加款：本页第 4/5 区随时可用。"
                    )

                    adminStepCard(
                        step: "6",
                        title: "随时查看总营收、用户余额与定时巡检",
                        color: .purple,
                        summary: "在本页第 1 区点击「拉取云端」，底部第 6 区会实时展示：",
                        commands: [],
                        note: "总注册用户数、累计收款入账、累计真实 Token 扣费、全员剩余余额以及最近活跃用户明细。提醒：若把你的个人 Key 存在 Cloudflare Secrets，请定期到厂商后台检查额度余额，避免上游欠费。"
                    )
                }
                .padding(16)
            }
            .background(pageBg.ignoresSafeArea())
            .navigationTitle("管理员配置教程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("wumind.admin.guideSheet")
    }

    private func adminStepCard(step: String, title: String, color: Color, summary: String, commands: [String], note: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("第 \(step) 步")
                    .font(.system(size: 10.5, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(color, in: Capsule())
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
            }

            if !summary.isEmpty {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
            }

            if !commands.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(commands, id: \.self) { cmd in
                        HStack(spacing: 8) {
                            Text(cmd)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(Color(red: 0.90, green: 0.94, blue: 1.0))
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button {
                                UIPasteboard.general.setItems([["public.utf8-plain-text": cmd]], options: [.localOnly: true])
                                ToastCenter.shared.show("已复制命令", style: .success)
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.85))
                                    .padding(6)
                                    .background(Color.white.opacity(0.14), in: Circle())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color(red: 0.09, green: 0.105, blue: 0.145), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }

            if !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(color.opacity(0.22), lineWidth: 1)
        )
    }
}
