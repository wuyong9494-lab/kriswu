import Foundation
import StoreKit

/// Native Apple StoreKit 2 Consumable In-App Purchase manager for WUMIND credit packs.
/// - Binds every purchase to the exact WUMIND `WM-` account via deterministic RFC 4122 `appAccountToken`.
/// - Persists unverified transactions in iOS Keychain so offline drops, app kills, or settings resets never lose paid orders.
/// - Automatically recovers `Transaction.unfinished` + Keychain pending transactions on launch, foreground, login, and wallet open.
/// - Calls `tx.finish()` ONLY after server-side cryptographic JWS verification succeeds (never finishes uncredited transactions!).
@MainActor
final class WuMindIAPManager: ObservableObject {
    static let shared = WuMindIAPManager()

    private struct PendingReceipt: Codable, Equatable {
        let productID: String
        let transactionID: String
        let originalTransactionID: String
        let jwsRepresentation: String
        let createdAt: Date
    }

    @Published private(set) var productsByID: [String: Product] = [:]
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var isRecovering = false
    @Published private(set) var purchasingProductID: String? = nil
    @Published private(set) var pendingTransactionCount: Int = 0
    @Published var statusNote: String? = nil

    private var updatesTask: Task<Void, Never>?
    private var inFlightTxIDs: Set<String> = []

    private init() {
        pendingTransactionCount = loadPendingReceipts().count
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
            // Ensure registered WM- account exists BEFORE calling Apple StoreKit so appAccountToken binds strictly to this account!
            _ = try await store.ensureManagedAccount()
            if store.managedAccountID.isEmpty {
                try? await store.refreshManagedAccount()
            }
            var options: Set<Product.PurchaseOption> = []
            if !store.managedAccountID.isEmpty {
                let accountToken = WuMindGatewayClient.accountUUID(for: store.managedAccountID)
                options.insert(.appAccountToken(accountToken))
            }

            let result = try await product.purchase(options: options)
            switch result {
            case .success(let verification):
                try await handleVerification(verification, store: store)
            case .userCancelled:
                statusNote = "已取消 Apple 支付。"
            case .pending:
                statusNote = "订单等待家长同意或 App Store 确认，完成后将自动到账。"
            @unknown default:
                statusNote = "支付状态未知，请稍后点击「恢复未完成内购」同步入账。"
            }
        } catch {
            statusNote = "Apple 内购失败：\((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
        }
    }

    /// Sweeps ALL unfinished StoreKit 2 transactions AND Keychain-persisted pending receipts,
    /// re-submitting them idempotently to `/v1/iap/verify` and auto-refreshing balance.
    func recoverUnfinishedTransactions(store: WuMindStore, silent: Bool = true) async {
        guard store.hasGatewayURL else { return }
        guard !isRecovering else { return }
        isRecovering = true
        defer { isRecovering = false }

        var recoveredCount = 0

        // 1. Drain StoreKit 2 native unfinished transactions (survives offline, kill, and device switch)
        for await verification in Transaction.unfinished {
            do {
                let credited = try await handleVerification(verification, store: store, silent: silent)
                if credited { recoveredCount += 1 }
            } catch {
                if !silent {
                    statusNote = "部分未完成交易暂未入账：\((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
                }
            }
        }

        // 2. Drain Keychain backup queue (survives local settings reset even if StoreKit listener missed a wake)
        let queued = loadPendingReceipts()
        for item in queued {
            if inFlightTxIDs.contains(item.transactionID) { continue }
            inFlightTxIDs.insert(item.transactionID)
            defer { inFlightTxIDs.remove(item.transactionID) }
            do {
                let token = try await store.ensureManagedAccount()
                let verified = try await WuMindGatewayClient().verifyAppleIAP(
                    gatewayURL: store.gatewayBaseURL,
                    userToken: token,
                    productID: item.productID,
                    transactionID: item.transactionID,
                    originalTransactionID: item.originalTransactionID,
                    jwsRepresentation: item.jwsRepresentation
                )
                removePendingReceipt(transactionID: item.transactionID)
                store.managedBalanceYuan = verified.balanceYuan
                recoveredCount += 1
            } catch let gwErr as WuMindGatewayClient.GatewayError {
                // Only drop permanently rejected/revoked/ownership-mismatch receipts; keep network/server-down for retry!
                switch gwErr {
                case .network:
                    break
                default:
                    if !silent {
                        statusNote = gwErr.errorDescription
                    }
                }
            } catch {
                break
            }
        }

        if recoveredCount > 0 {
            try? await store.refreshManagedAccount()
            if !silent {
                statusNote = "已自动恢复并补入账 \(recoveredCount) 笔 Apple 内购交易。"
                ToastCenter.shared.show("已补入账 \(recoveredCount) 笔内购", style: .success)
            }
        } else if !silent && statusNote == nil {
            statusNote = "已完成检查，当前没有待补单的未完成内购交易。"
        }
    }

    /// Manual recovery button in Wallet UI: invokes Apple `StoreKit.AppStore.sync()` then sweeps all unfinished & Keychain transactions.
    func syncAppStoreAndRecover(store: WuMindStore) async {
        statusNote = "正在同步 Apple 交易记录并核验未入账订单…"
        do {
            try await StoreKit.AppStore.sync()
        } catch {
            // Even if StoreKit.AppStore.sync() is cancelled or unavailable in simulator, still sweep local unfinished + Keychain queue
        }
        await recoverUnfinishedTransactions(store: store, silent: false)
    }

    private func startTransactionObserver() {
        updatesTask?.cancel()
        updatesTask = Task { @MainActor [weak self] in
            for await verification in Transaction.updates {
                guard let self else { break }
                _ = try? await self.handleVerification(verification, store: WuMindStore.shared, silent: false)
            }
        }
    }

    @discardableResult
    private func handleVerification(
        _ verification: VerificationResult<Transaction>,
        store: WuMindStore,
        silent: Bool = false
    ) async throws -> Bool {
        switch verification {
        case .unverified(_, let error):
            if !silent {
                statusNote = "Apple 交易签名校验未通过（\(error.localizedDescription)）。"
            }
            return false
        case .verified(let tx):
            let txID = String(tx.id)
            if inFlightTxIDs.contains(txID) { return false }
            inFlightTxIDs.insert(txID)
            defer { inFlightTxIDs.remove(txID) }

            let receipt = PendingReceipt(
                productID: tx.productID,
                transactionID: txID,
                originalTransactionID: String(tx.originalID),
                jwsRepresentation: verification.jwsRepresentation,
                createdAt: Date()
            )
            // Persist in Keychain BEFORE network call so app kill / offline / settings reset NEVER loses the order!
            enqueuePendingReceipt(receipt)

            let token = try await store.ensureManagedAccount()
            let verified = try await WuMindGatewayClient().verifyAppleIAP(
                gatewayURL: store.gatewayBaseURL,
                userToken: token,
                productID: tx.productID,
                transactionID: txID,
                originalTransactionID: String(tx.originalID),
                jwsRepresentation: verification.jwsRepresentation
            )

            // Only finish the StoreKit transaction & dequeue AFTER server confirms atomic commit!
            await tx.finish()
            removePendingReceipt(transactionID: txID)
            store.managedBalanceYuan = verified.balanceYuan
            try? await store.refreshManagedAccount()

            if !silent {
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
            return true
        }
    }

    // MARK: - Keychain Pending Receipt Queue

    private func loadPendingReceipts() -> [PendingReceipt] {
        guard let raw = Keychain.wumindPendingIAPQueue,
              let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([PendingReceipt].self, from: data) else {
            return []
        }
        return decoded
    }

    private func savePendingReceipts(_ list: [PendingReceipt]) {
        pendingTransactionCount = list.count
        if list.isEmpty {
            _ = Keychain.setWuMindPendingIAPQueue("")
            return
        }
        if let data = try? JSONEncoder().encode(list),
           let str = String(data: data, encoding: .utf8) {
            _ = Keychain.setWuMindPendingIAPQueue(str)
        }
    }

    private func enqueuePendingReceipt(_ item: PendingReceipt) {
        var list = loadPendingReceipts()
        if !list.contains(where: { $0.transactionID == item.transactionID }) {
            list.append(item)
            savePendingReceipts(list)
        }
    }

    private func removePendingReceipt(transactionID: String) {
        var list = loadPendingReceipts()
        list.removeAll { $0.transactionID == transactionID }
        savePendingReceipts(list)
    }
}
