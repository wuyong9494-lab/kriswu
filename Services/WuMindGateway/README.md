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
wrangler secret put EPAY_API_URL            # 易支付/彩虹易支付网关地址（开启微信/支付宝一键跳转自动到账）
wrangler secret put EPAY_PID                # 易支付商户 ID
wrangler secret put EPAY_KEY                # 易支付商户密钥（自动验签 /v1/webhooks/epay 并入账）
wrangler secret put PAYMENT_CHECKOUT_URL    # 或自定义收银台模板（支持 {orderID}/{amount}/{userID}/{channel}）
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
5. 四种收款入账方式（均支持自动/秒到账）：
   - **微信/支付宝在线自动到账（推荐）**：配置 `EPAY_API_URL` + `EPAY_PID` + `EPAY_KEY` 后，用户在钱包点选金额直接拉起收银台付款，支付网关回调 `/v1/webhooks/epay` 自动验签并秒级入账，用户切回 App 后 3 秒内余额自动刷新无需找人工。
   - **自定义支付回调**：向 `POST /v1/webhooks/payment` 发送带 `X-WuMind-Signature`（HMAC-SHA256）的回调 JSON（支持仅传 `orderID` 自动匹配用户），按订单号严格幂等防重自动到账。
   - **Apple StoreKit 2 应用内购**：在 App Store Connect 创建消耗型内购 SKU（`com.kriswu.wumind.credit.6` / `.18` / `.68` / `.198`），App 付款后自动调用 `POST /v1/iap/verify` 校验 JWS 并实时到账。
   - **兑换码秒充 / 个人收款码备用**：批量生成 `WM-XXXX-XXXX-XXXX` 兑换码用户一键核销秒到账；个人静态收款码本身不会主动发服务器通知，需配合免签监控转发 `/v1/webhooks/payment` 或管理员按账号 ID 一键入账。
6. 网关同时原生支持：多模态视觉直传（GPT/Gemini/Claude/Grok）、Cloudflare Cron 云端定时任务、AES-256-GCM 零知识跨设备同步（`/v1/sync/*`）与 iPhone ↔ iPad 多设备独立令牌配对。
