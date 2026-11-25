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
                        title: "合规充值与 TestFlight 测试规则",
                        color: .teal,
                        bullets: [
                            "TestFlight 测试版合规保护：依据 Apple TestFlight 条款，测试期间严禁向测试者收取真实费用（包括 App 内外跳微信/支付宝或扫码付款），TestFlight 版本已自动关闭全部真实付费通道。",
                            "Apple 应用内购（StoreKit 2）：服务端独立验证 Apple Root CA - G3 三级证书链与 ES256 数字签名，绝不信任未验签凭据；TestFlight 沙盒交易 0 元不扣费，仅计入独立「沙盒测试余额」，不会混入正式余额。",
                            "免费兑换码与正式版通道：TestFlight 阶段可使用「自带 API」或管理员发放的免费测试兑换码；正式版上线后由管理员完成沙盒验签验收再开启正式入账。"
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
                        title: "管理员从零部署与安全验收教程",
                        subtitle: "默认 fail-closed 暂停自动入账；先用 Apple 沙盒与独立测试余额完成服务端验签验收，再开放正式环境",
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
                        note: "把 wrangler d1 create 输出的 database_id 填进 Services/WuMindGateway/wrangler.toml 后再执行建表与 deploy。默认 AUTO_CREDIT_PAUSED=\"true\"（安全暂停自动入账），防止未完成验签验收前误入账。"
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
                        note: "可选增强：写入 APPLE_IAP_ISSUER_ID / APPLE_IAP_KEY_ID / APPLE_IAP_PRIVATE_KEY 开启 Apple App Store Server API 实时复核；写入 TAVILY_API_KEY 启用联网搜索。"
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
                        title: "设定定价与合规收款模式（TestFlight 严禁真实收费）",
                        color: .orange,
                        summary: "定价表默认按官方成本加价展示，你可自由调整售价（利润 = 你的售价 − 官方成本）：",
                        commands: [],
                        note: "• Apple 合规红线：TestFlight 阶段 App 会自动屏蔽微信/支付宝真实付费与外跳；正式提交 App Store 审核时请选择「仅 Apple 应用内购」。\n• 一键调价：点 1.5× / 2.0× / 2.5× / 3.0× 快速加价，或逐个模型微调「输入价 / 输出价（¥/百万 Token）」与「联网搜索单价」。\n• 发布生效：修改后点击「保存并发布」同步云端。"
                    )

                    adminStepCard(
                        step: "5",
                        title: "服务端 Apple Root CA - G3 验签与独立沙盒验收流程",
                        color: .green,
                        summary: "新版本网关强制校验证书链（Apple Root CA - G3）与 ES256 签名，并严格隔离沙盒测试余额与正式余额：",
                        commands: [
                            "node Services/WuMindGateway/test/iap-security.test.mjs",
                            "npx wrangler secret put APPLE_IAP_ISSUER_ID",
                            "npx wrangler secret put APPLE_IAP_KEY_ID",
                            "npx wrangler secret put APPLE_IAP_PRIVATE_KEY"
                        ],
                        note: "• 第 1 阶段（沙盒验收）：在 wrangler.toml 设 AUTO_CREDIT_PAUSED=\"false\" 且 ALLOW_APPLE_SANDBOX_TEST=\"true\"、ALLOW_APPLE_PRODUCTION_IAP=\"false\"，用 TestFlight / Apple Sandbox 账号 0 元测试内购，确认验签成功且仅增加「独立沙盒测试余额」（正式余额始终为 ¥0）。\n• 第 2 阶段（正式开放）：待 App Store 正式版审核上架后，再将 ALLOW_APPLE_PRODUCTION_IAP=\"true\"、ALLOW_APPLE_SANDBOX_TEST=\"false\"（建议同时开启 REQUIRE_APPLE_SERVER_API=\"true\"）。\n• 紧急止损：任何异常时将 AUTO_CREDIT_PAUSED=\"true\" 并重新 deploy，立即全线熔断自动入账。"
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
