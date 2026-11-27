# WUMIND 实时计费网关部署与安全验收指南（Cloudflare Workers + D1）

本目录提供 WUMIND「内置付费 API 通道」的完整后端源码：**零服务器运维、全球 HTTPS、免费额度每天可承载数万次请求**。
所有厂商真实 API Key 仅存储在 Cloudflare Secrets 中，**永远不会打包进 iOS App**。

### iOS 构建地址与登录验收

| 构建配置 | 管理员提供的公开地址 |
| --- | --- |
| Release | `WUMIND_PRODUCTION_GATEWAY_URL` |
| Debug、WuMindTesting 方案的 Testing 归档 | `WUMIND_TEST_GATEWAY_URL` |

在对应 Worker 的「域和路由」核对已启用的 HTTPS 地址，并用该实例的 `/v1/health`、`/v1/public/config` 核对服务和搜索能力。将核实后的地址填入 `project.yml` 的对应构建设置，或作为同名 Xcode 构建参数传入。只有选中的地址进入 App 的 `WuMindGatewayURL`。未确认的地址留空，由 App 提示联系管理员。模型及搜索服务的凭据通过对应 Worker 的 Secret 配置。

全新安装后登录 WuMind，在普通对话开启「联网搜索」，查询一份公开文件并点开原文核对标题和内容。然后切到「自有通道」，选择服务商，只在设备上保存个人 Key，发送一条普通消息。验收时记录服务商、模型、结果和原文链接即可。

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

# 推荐方案 A（AIHubMix 统一供给多厂商对话/生图/参考图编辑/视频/实时语音模型）：
# 1) 推理密钥（sk-...）：必须写入 AIHUBMIX_API_KEY，切勿塞进 OPENAI_API_KEY！
wrangler secret put AIHUBMIX_API_KEY
# 2) 管理令牌（系统访问令牌 Manage Key，如 fd...）：仅用于云端查询 AIHubMix 共享池可用余额（GET /api/user/self），绝不写入 iOS App！
wrangler secret put AIHUBMIX_MANAGE_KEY

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

> **在线非破坏性升级（保留现有 D1 数据）**：新版 Worker 首次收到请求会自动幂等补齐新增列（`users.reserved_micros` / `billing_exempt` / `upstream_spent_micros` 等）及新表（`credit_reservations`、`admin_credit_audit`、`model_catalog`、`video_jobs`、`user_works`），无需删库或重建 D1。
> **管理员免充值权限**：在 `wrangler.toml` 设置 `ADMIN_EXEMPT_USER_IDS = "WM-XXXXXX"` 或在 App 管理员页开启「管理员免扣」开关，管理员钱包余额为 ¥0 亦可调用内置文字/生图/视频/实时语音/PPT，仍受限频（`ADMIN_EXEMPT_RPM`）与每日上游成本上限（`ADMIN_EXEMPT_DAILY_CAP_YUAN`）保护，并完整记入用量账本；上游 API 欠费时返回独立错误 `upstream_balance_insufficient`（不弹 App 充值）。

### 4. 运行本地全部 3 套自动化测试与线上实测脚本（上线前必跑）
```bash
node Services/WuMindGateway/test/iap-security.test.mjs
node Services/WuMindGateway/test/billing-catalog-media.test.mjs
node Services/WuMindGateway/test/admin-exempt-balance-works.test.mjs

# 部署到 Cloudflare 后，一键实测目录同步、模型探测、参考图生图与 Sora 2 视频：
WUMIND_GATEWAY_URL=https://你的网关域名 WUMIND_ADMIN_SECRET=你的管理员密钥 \
  node Services/WuMindGateway/scripts/live-verify-media-and-catalog.mjs
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
