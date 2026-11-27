import Foundation

/// Canonical connection identity for persisted addresses and gateway-bound credentials.
public enum WuMindGatewayConfiguration {
    public static func address(_ input: String) throws -> String {
        let url = try WuMindGatewayClient.normalizedGatewayURL(input)
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = parts.host?.lowercased(),
              !["dash.cloudflare.com", "api.cloudflare.com"].contains(host),
              Set(parts.path.lowercased().split(separator: "/")).isDisjoint(with: ["admin", "dashboard", "edit", ".", ".."]),
              !host.hasPrefix("."),
              !host.contains(".."),
              !host.hasSuffix(".") else {
            throw WuMindGatewayClient.GatewayError.invalidGatewayURL
        }
        parts.scheme = "https"
        parts.host = host
        if parts.port == 443 { parts.port = nil }
        while parts.percentEncodedPath.hasSuffix("/") { parts.percentEncodedPath.removeLast() }
        guard let canonical = parts.string else { throw WuMindGatewayClient.GatewayError.invalidGatewayURL }
        return canonical
    }

    /// Only the public origin for this installation's build configuration is packaged.
    public static func bundledAddress(in bundle: Bundle = .main) -> String? {
        guard let raw = bundle.object(forInfoDictionaryKey: "WuMindGatewayURL") as? String else { return nil }
        return try? address(raw)
    }

    /// Legacy settings can describe another build, including a testing gateway.
    public static func resolvedAddress(saved: String?, bundled: String?) -> String? {
        guard let bundled, let pinned = try? address(bundled) else { return nil }
        if let saved, let previous = try? address(saved), previous == pinned {
            return previous
        }
        return pinned
    }

    /// Commit the normalized address only after a successful write.
    public static func persistAddress(_ input: String, write: (String) throws -> Void) throws -> String {
        let canonical = try address(input)
        try write(canonical)
        return canonical
    }

    /// Include the path as well as the origin: separate proxies on the same host need separate credentials.
    public static func administratorCredentialID(for address: String) throws -> String {
        let canonical = try self.address(address)
        return "gateway.admin.v2." + Data(canonical.utf8).base64EncodedString()
    }

    /// The migration marker is the new settings file. Only write it after the account data is durable.
    public static func finalizeLegacyMigration(
        writePrivateData: () throws -> Void,
        writeSettings: () throws -> Void,
        removeLegacy: () throws -> Void
    ) throws {
        try writePrivateData()
        try writeSettings()
        try removeLegacy()
    }
}
