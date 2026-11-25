import Foundation
import StoreKit

/// Native Apple StoreKit 2 Consumable In-App Purchase manager for WUMIND credit packs.
/// Supports App Store Review compliant top-ups with cryptographic JWS verification against
/// the WUMIND Billing Gateway (`/v1/iap/verify`) and idempotent transaction deduplication.
@MainActor
final class WuMindIAPManager: ObservableObject {
    static let shared = WuMindIAPManager()

    @Published private(set) var productsByID: [String: Product] = [:]
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var purchasingProductID: String? = nil
    @Published var statusNote: String? = nil

    private var updatesTask: Task<Void, Never>?

    private init() {
        startTransactionObserver()
    }

    func loadProducts(for packs: [WuMindIAPPack]) async {
        let ids = packs.map(\.id).filter { !$0.isEmpty }
        guard !ids.isEmpty else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let fetched = try await Product.products(for: ids)
            var map: [String: Product] = [:]
            for p in fetched { map[p.id] = p }
            productsByID = map
            if fetched.isEmpty {
                statusNote = "App Store Connect 尚未上架这些消耗型内购 SKU（TestFlight 严禁向测试者收取真实费用，请先使用「自带 API」或免费测试兑换码）。"
            } else {
                statusNote = nil
            }
        } catch {
            statusNote = "暂无法读取 App Store 商品列表（\(error.localizedDescription)）。"
        }
    }

    func purchase(pack: WuMindIAPPack, store: WuMindStore) async {
        guard store.hasGatewayURL else {
            statusNote = "请先在管理员后台配置 WUMIND 计费网关地址，内购完成后才能安全验签入账。"
            return
        }
        guard !store.managedConfig.isAutoCreditPaused else {
            statusNote = "云端自动入账通道当前处于安全暂停状态（AUTO_CREDIT_PAUSED），暂不发起内购。"
            return
        }
        guard let product = productsByID[pack.id] else {
            await loadProducts(for: store.managedConfig.resolvedIAPPacks)
            if productsByID[pack.id] == nil {
                statusNote = "未在 App Store Connect 查到商品 \(pack.id)，请确认已在后台创建对应消耗型内购项目。"
                return
            }
            return
        }

        purchasingProductID = pack.id
        statusNote = nil
        defer { purchasingProductID = nil }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                try await handleVerification(verification, store: store)
            case .userCancelled:
                statusNote = "已取消 Apple 支付。"
            case .pending:
                statusNote = "订单等待家长同意或 App Store 确认，完成后将自动到账。"
            @unknown default:
                statusNote = "支付状态未知，请稍后刷新余额。"
            }
        } catch {
            statusNote = "Apple 内购失败：\((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
        }
    }

    private func startTransactionObserver() {
        updatesTask?.cancel()
        updatesTask = Task { @MainActor [weak self] in
            for await verification in Transaction.updates {
                guard let self else { break }
                try? await self.handleVerification(verification, store: WuMindStore.shared)
            }
        }
    }

    private func handleVerification(_ verification: VerificationResult<Transaction>, store: WuMindStore) async throws {
        switch verification {
        case .unverified(_, let error):
            statusNote = "Apple 交易签名校验未通过（\(error.localizedDescription)）。"
            return
        case .verified(let tx):
            let token = try await store.ensureManagedAccount()
            let verified = try await WuMindGatewayClient().verifyAppleIAP(
                gatewayURL: store.gatewayBaseURL,
                userToken: token,
                productID: tx.productID,
                transactionID: String(tx.id),
                originalTransactionID: String(tx.originalID),
                jwsRepresentation: verification.jwsRepresentation
            )
            store.managedBalanceYuan = verified.balanceYuan
            await tx.finish()
            try? await store.refreshManagedAccount()
            if verified.isSandboxTransaction {
                let sbBal = verified.sandboxBalanceYuan ?? 0
                if verified.alreadyCredited {
                    statusNote = String(format: "该 Apple 沙盒测试订单已核销，独立测试余额 ¥%.2f（正式余额 ¥%.2f 未变动）。", sbBal, verified.balanceYuan)
                } else {
                    statusNote = String(format: "Apple 沙盒验签通过！已计入独立测试余额 ¥%.2f（当前测试余额 ¥%.2f，正式余额未变动）。", verified.creditedYuan, sbBal)
                    ToastCenter.shared.show(String(format: "沙盒验签通过 · 测试余额 ¥%.2f", sbBal), style: .success)
                }
            } else if verified.alreadyCredited {
                statusNote = "该 Apple 内购订单已入账，当前余额 ¥\(String(format: "%.2f", verified.balanceYuan))。"
            } else {
                statusNote = String(format: "Apple 内购验签成功！已实时到账 ¥%.2f，当前余额 ¥%.2f。", verified.creditedYuan, verified.balanceYuan)
                ToastCenter.shared.show(String(format: "已到账 ¥%.2f", verified.creditedYuan), style: .success)
            }
        }
    }
}
