import Foundation

/// One device-only Keychain entry holds both the bearer and its issuing gateway and account.
struct WuMindGatewayCredential: Codable {
    private let gateway: String
    private let accountID: String
    private let token: String

    init?(gateway: String, accountID: String, token: String) {
        guard let address = try? WuMindGatewayConfiguration.address(gateway),
              !accountID.isEmpty, !token.isEmpty else { return nil }
        self.gateway = address
        self.accountID = accountID
        self.token = token
    }

    func token(for address: String, accountID: String) -> String? {
        guard !token.isEmpty, !accountID.isEmpty, accountID == self.accountID,
              (try? WuMindGatewayConfiguration.address(address)) == gateway else { return nil }
        return token
    }
}
