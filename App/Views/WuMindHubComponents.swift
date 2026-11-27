import SwiftUI
import UIKit

// MARK: - Shared Flagship Secondary-Screen Visual System

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

    var body: some View {
        NavigationStack {
            List {
                Section("费用由谁结算") {
                    Text("内置通道使用 WuMind 钱包余额。自有通道使用你的 Key，费用由所选服务商结算。")
                }
                Section("充值") {
                    Text("在钱包中选择当前可用的充值方式。兑换码由管理员发放，兑换后可在账单查看。")
                    Text("TestFlight 的 Apple 沙盒交易仅增加测试余额。")
                }
                Section("核对用量") {
                    Text("模型价格按每百万 Token 展示。消息下方列出当次用量和费用，钱包账单可查看明细。联网搜索按次计费。")
                }
                Section("多设备") {
                    Text("在 WuMind 设置中打开跨设备同步，按提示配对此账号的其他设备。")
                }
            }
            .appList()
            .navigationTitle("充值与计费说明")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
        .accessibilityIdentifier("wumind.wallet.guideSheet")
    }
}

// MARK: - Admin-Only From-Zero Deployment & Monetization Tutorial Sheet

struct WuMindAdminSetupGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var cardBg: Color {
        colorScheme == .dark ? Color(red: 0.125, green: 0.14, blue: 0.175) : Color.white
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
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
                        title: "写入管理员密码与上游模型 Key（推荐 AIHubMix 统一供给）",
                        color: .teal,
                        summary: "真实 API Key 绝不打包进 App，全部存在 Cloudflare Secrets 中。用 AIHubMix 统一供给时请写入专用 AIHUBMIX_API_KEY，并在 wrangler.toml 填写 AIHUBMIX_ALLOWED_MODELS 白名单（切勿把 AIHubMix Key 塞进 OPENAI_API_KEY）：",
                        commands: [
                            "npx wrangler secret put ADMIN_SECRET",
                            "npx wrangler secret put AIHUBMIX_API_KEY",
                            "npx wrangler secret put DEEPSEEK_API_KEY",
                            "npx wrangler secret put OPENAI_API_KEY",
                            "npx wrangler secret put GEMINI_API_KEY",
                            "npx wrangler secret put CLAUDE_API_KEY"
                        ],
                        note: "安全隔离：AIHUBMIX_API_KEY 只发往 https://aihubmix.com/v1/chat/completions 并严格校验 AIHUBMIX_ALLOWED_MODELS 白名单；OPENAI_API_KEY 只发往 api.openai.com 官方。可选写入 APPLE_IAP_* 开启 Apple 官方复核。"
                    )

                    adminStepCard(
                        step: "3",
                        title: "在 App 管理员后台连接网关并验证",
                        color: .blue,
                        summary: "回到上一页「WUMIND 商业计费管理」第 1 区：",
                        commands: [],
                        note: "在构建配置中分别填写已核实的测试或正式服务地址。打开「网关与诊断」，核对当前版本的网关后保存管理凭据，再拉取云端配置。"
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
                .padding(DS.Space.m)
                .frame(maxWidth: DS.readableWidth)
                .frame(maxWidth: .infinity)
            }
            .appBackground()
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
                    .font(.caption.weight(.semibold))
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
                                .font(.footnote.monospaced())
                                .foregroundStyle(Color(red: 0.90, green: 0.94, blue: 1.0))
                                .fixedSize(horizontal: false, vertical: true)
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
