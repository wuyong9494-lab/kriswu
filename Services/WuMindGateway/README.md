# WUMIND 实时计费网关部署与安全验收指南（Cloudflare Workers + D1）

本目录提供 WUMIND「内置付费 API 通道」的完整后端源码：**零服务器运维、全球 HTTPS、免费额度每天可承载数万次请求**。
所有厂商真实 API Key 仅存储在 Cloudflare Secrets 中，**永远不会打包进 iOS App**。

> **重要安全与 Apple TestFlight 合规声明**
> 1. **默认安全暂停（Fail-Closed）**：`wrangler.toml` 默认 `AUTO_CREDIT_PAUSED = "true"`、`ALLOW_APPLE_PRODUCTION_IAP = "false"`、`ALLOW_APPLE_SANDBOX_TEST = "false"`，在完成加密验签与沙盒验收前不会执行任何自动入账。
> 2. **服务端独立加密验签**：`/v1/iap/verify` 会完整验证 StoreKit 2 JWS 的 **Apple Root CA - G3 固定 SHA-256 指纹 + 三级 `x5c` ECDSA 证书链 + Apple WWDR/Leaf 扩展 OID + 有效期 + ES256 签名**，并支持叠加 Apple App Store Server API v1 实时复核；任何未签名/伪造/篡改/已退款/`Xcode` 本地凭据均被严格拒绝。
> 3. **沙盒与正式余额严格隔离**：Apple `Sandbox` 交易**永远只计入 `users.sandbox_balance_micros`**（带单人上限 `SANDBOX_BALANCE_CAP_YUAN`，且不可消耗真实上游付费 API 余额），绝不触碰正式 `balance_micros`。
> 4. **Apple TestFlight 合规**：依据 Apple Developer Program License Agreement，TestFlight 测试版严禁向测试者收取真实费用（包括 App 内外跳微信/支付宝或扫码收款）。iOS 客户端已在 TestFlight 环境下自动隐藏并禁止真实付费入口。

---

## 一、若此前已手工部署旧版 Worker：立即检查与止损步骤

```bash
cd Services/WuMindGateway
npx wrangler deployments list
```

如果 Cloudflare 线上存在已部署的旧版 `wumind-billing-gateway`：
1. **立即暂停自动入账并升级至本版本**：确认 `wrangler.toml` 中 `AUTO_CREDIT_PAUSED = "true"`，执行升级迁移与重新部署：
   ```bash
   npx wrangler d1 execute wumind-billing-db --remote --command "ALTER TABLE users ADD COLUMN sandbox_balance_micros INTEGER NOT NULL DEFAULT 0;"
   npx wrangler d1 execute wumind-billing-db --remote --command "ALTER TABLE users ADD COLUMN sandbox_recharged_micros INTEGER NOT NULL DEFAULT 0;"
   npx wrangler d1 execute wumind-billing-db --remote --command "ALTER TABLE payment_orders ADD COLUMN environment TEXT NOT NULL DEFAULT 'production';"
   npx wrangler d1 execute wumind-billing-db --remote --command "ALTER TABLE ledger ADD COLUMN external_order_id TEXT;"
   npx wrangler d1 execute wumind-billing-db --remote --command "CREATE UNIQUE INDEX IF NOT EXISTS idx_ledger_external_order ON ledger(external_order_id) WHERE external_order_id IS NOT NULL;"
   npx wrangler deploy
   ```
2. **核查 D1 是否有可疑 `apple_iap` 流水**：
   ```bash
   npx wrangler d1 execute wumind-billing-db --remote --command "SELECT id, user_id, external_order_id, amount_micros, channel, status, created_at FROM payment_orders ORDER BY created_at DESC LIMIT 30;"
   ```

---

## 二、首次部署步骤

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

# 推荐方案 A（AIHubMix 统一供给多厂商模型）：
# 注意：AIHubMix 专用 Key 必须写入 AIHUBMIX_API_KEY（自动走 https://aihubmix.com/v1/chat/completions），
# 切勿把 AIHubMix Key 塞进 OPENAI_API_KEY（OPENAI_API_KEY 只会发给 api.openai.com 官方）！
wrangler secret put AIHUBMIX_API_KEY
# 然后在 wrangler.toml 的 [vars] 中配置可售模型白名单（防透传任意昂贵模型，严禁填 *）：
# AIHUBMIX_ALLOWED_MODELS = "gpt-4o,claude-sonnet-4-20250514,gemini-2.5-pro,deepseek-reasoner,deepseek-chat"

# 可选方案 B（各厂商官方直连 Key，仅在需要直连官方时配置）：
wrangler secret put DEEPSEEK_API_KEY
wrangler secret put OPENAI_API_KEY
wrangler secret put GEMINI_API_KEY
wrangler secret put CLAUDE_API_KEY
wrangler secret put GROK_API_KEY

# 强烈推荐：配置 Apple App Store Connect In-App Purchase API 密钥，叠加 Apple 官方服务器实时复核
wrangler secret put APPLE_IAP_ISSUER_ID
wrangler secret put APPLE_IAP_KEY_ID
wrangler secret put APPLE_IAP_PRIVATE_KEY

# 可选增强：
wrangler secret put TAVILY_API_KEY
wrangler secret put BRAVE_SEARCH_API_KEY
```

### 4. 运行本地加密验签与隔离测试（上线前必跑）
```bash
node Services/WuMindGateway/test/iap-security.test.mjs
```

### 5. 沙盒验收流程（TestFlight / Apple Sandbox 0 元测试）
1. 在 `wrangler.toml` 中将：
   - `AUTO_CREDIT_PAUSED = "false"`
   - `ALLOW_APPLE_SANDBOX_TEST = "true"`
   - `ALLOW_APPLE_PRODUCTION_IAP = "false"`（保持关闭！）
2. 执行 `wrangler deploy`。
3. 使用 App Store Connect 创建的 **Sandbox 测试账号**在 TestFlight 发起 0 元内购，确认：
   - 伪造/篡改 JWS 被服务端拒绝（HTTP `401`）；
   - 真实 Apple Sandbox JWS 通过 Apple Root CA - G3 验签并计入「独立沙盒测试余额」（`sandboxBalanceYuan`）；
   - 正式余额 `balanceYuan` 仍为 `¥0.00`，且沙盒余额无法调用真实上游付费对话接口（HTTP `402`）。

### 6. App Store 正式版开放
仅在 App Store 正式版上架且完成上述沙盒验收后：
- 在 `wrangler.toml` 中设置 `ALLOW_APPLE_PRODUCTION_IAP = "true"`、`ALLOW_APPLE_SANDBOX_TEST = "false"`（建议同时设置 `REQUIRE_APPLE_SERVER_API = "true"`）；
- 在 App 管理员后台将收款模式固定为 **「仅 Apple 应用内购（App Store 审核合规）」**。
