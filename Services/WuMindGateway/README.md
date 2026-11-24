# WUMIND 实时计费网关部署指南（Cloudflare Workers + D1）

本目录提供 WUMIND「内置付费 API 通道」的完整后端源码：**零服务器运维、全球 HTTPS、免费额度每天可承载数万次请求**。
所有厂商真实 API Key 仅存储在 Cloudflare Secrets 中，**永远不会打包进 iOS App**。

## 5 分钟快速上线步骤

### 1. 安装 Wrangler 并登录 Cloudflare
```bash
npm install -g wrangler
wrangler login
```

### 2. 创建 D1 数据库并初始化表结构
```bash
cd Services/WuMindGateway
wrangler d1 create wumind-billing-db
```
将终端输出的 `database_id` 填入 `wrangler.toml` 的 `database_id = "..."`，然后执行建表：
```bash
wrangler d1 execute wumind-billing-db --remote --file=./schema.sql
```

### 3. 配置云端机密（仅保存在 Cloudflare，不进代码库）
```bash
# 必填：你自己设定的管理员密钥（之后填进 App「设置 › WUMIND 商业与计费管理」）
wrangler secret put ADMIN_SECRET

# 至少配置一家你要开放的上游模型厂商 Key：
wrangler secret put DEEPSEEK_API_KEY
wrangler secret put OPENAI_API_KEY
wrangler secret put GEMINI_API_KEY
wrangler secret put CLAUDE_API_KEY
wrangler secret put GROK_API_KEY

# 可选增强（按需配置）：
wrangler secret put TAVILY_API_KEY          # 高质量联网深度搜索（未配时自动回落 DuckDuckGo）
wrangler secret put BRAVE_SEARCH_API_KEY    # Brave Search 备用
wrangler secret put PAYMENT_WEBHOOK_SECRET  # 微信/支付宝第三方自动回调 HMAC-SHA256 验签密钥
```

### 4. 一键部署
```bash
wrangler deploy
```
部署完成后会得到你的专属网关 HTTPS 地址，例如：
`https://wumind-billing-gateway.<你的子域>.workers.dev`（推荐绑定一个自己的自定义域名，国内直连更稳）。

### 5. 在 App 管理员模式中配置定价、合规收款模式与收款码
1. 打开 App →「设置」→「身份」→ 输入管理员密码登录为**管理员**。
2. 进入「**WUMIND 商业与计费管理（管理员）**」（页面顶部自带 6 步交互式配置教程与命令一键复制）。
3. 填入你的网关地址与 `ADMIN_SECRET`，点击「**拉取云端**」验证连通。
4. 选择收款合规模式（TestFlight 内外测可选「混合模式」或「仅扫码/兑换码」；提交 App Store 正式审核前切换为「仅 Apple 应用内购」），设置各模型售价与联网搜索单次计费，上传**微信/支付宝收款二维码**，点击「**保存并发布定价与二维码**」。
5. 四种收款入账方式：
   - **兑换码发卡**：批量生成 `WM-XXXX-XXXX-XXXX` 兑换码，用户在钱包一键核销秒到账。
   - **按账号 ID 秒充**：收到扫码转账备注的 `WM-XXXXXX` 后直接按 ID 一键入账。
   - **自动化支付回调**：向 `POST /v1/webhooks/payment` 发送带 `X-WuMind-Signature`（HMAC-SHA256）的回调 JSON，按 `externalOrderID` 严格幂等防重自动到账。
   - **Apple StoreKit 2 应用内购**：在 App Store Connect 创建消耗型内购 SKU（`com.kriswu.wumind.credit.6` / `.18` / `.68` / `.198`），App 付款后自动调用 `POST /v1/iap/verify` 校验 JWS 并幂等入账。
6. 网关同时原生支持：多模态视觉直传（GPT/Gemini/Claude/Grok）、Cloudflare Cron 云端定时任务、AES-256-GCM 零知识跨设备同步（`/v1/sync/*`）与 iPhone ↔ iPad 多设备独立令牌配对。
