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
```

### 4. 一键部署
```bash
wrangler deploy
```
部署完成后会得到你的专属网关 HTTPS 地址，例如：
`https://wumind-billing-gateway.<你的子域>.workers.dev`（推荐绑定一个自己的自定义域名，国内直连更稳）。

### 5. 在 App 管理员模式中配置定价与收款码
1. 打开 App →「设置」→「身份」→ 输入管理员密码登录为**管理员**。
2. 进入「**WUMIND 商业与计费管理（管理员）**」。
3. 填入你的网关地址与 `ADMIN_SECRET`。
4. 自定义各模型售价（高于官方成本自动盈利）、从相册上传**微信/支付宝收款二维码**与充值说明，点击「**发布配置到云端**」。
5. 当用户扫码付款并备注自己的账号 ID（如 `WM-849201`）后，直接在管理员页面：
   - 点击「**按用户 ID 一键入账**」，或
   - 点击「**生成充值兑换码**」发给用户，用户在 App 内一键核销秒到账！
6. 之后用户每次对话均按上游返回的真实 `prompt_tokens` + `completion_tokens` + `reasoning_tokens` 自动实时扣费。
