import CryptoKit
import Foundation

/// Zero-knowledge end-to-end AES-256-GCM encryption for WUMIND Cross-Device Cloud Sync
/// and encrypted `.wumindsync` local backups.
/// The sync passphrase NEVER leaves the device; Cloudflare D1 only stores authenticated ciphertext.
enum WuMindSyncCrypto {
    enum CryptoError: LocalizedError {
        case emptyPassphrase
        case invalidFormat
        case decryptionFailed

        var errorDescription: String? {
            switch self {
            case .emptyPassphrase: return "请输入至少 4 位的端到端同步加密口令。"
            case .invalidFormat: return "云端同步密文格式不兼容或已损坏。"
            case .decryptionFailed: return "解密失败：请确认当前输入的同步加密口令与上传设备一致。"
            }
        }
    }

    private static let envelopePrefix = "WME1:"

    /// Derives a 256-bit AES-GCM key from the user's passphrase via iterated SHA-256 stretching.
    static func deriveKey(passphrase: String, salt: String = "wumind.e2ee.v1.salt") throws -> SymmetricKey {
        let clean = passphrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 4 else { throw CryptoError.emptyPassphrase }
        var state = Data((salt + ":" + clean).utf8)
        for _ in 0..<2048 {
            state = Data(SHA256.hash(data: state))
        }
        return SymmetricKey(data: state)
    }

    static func encrypt(_ plaintext: Data, passphrase: String) throws -> String {
        let key = try deriveKey(passphrase: passphrase)
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else { throw CryptoError.invalidFormat }
        return envelopePrefix + combined.base64EncodedString()
    }

    static func decrypt(_ envelope: String, passphrase: String) throws -> Data {
        let trimmed = envelope.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(envelopePrefix) else { throw CryptoError.invalidFormat }
        let b64 = String(trimmed.dropFirst(envelopePrefix.count))
        guard let combined = Data(base64Encoded: b64) else { throw CryptoError.invalidFormat }
        let key = try deriveKey(passphrase: passphrase)
        do {
            let box = try AES.GCM.SealedBox(combined: combined)
            return try AES.GCM.open(box, using: key)
        } catch {
            throw CryptoError.decryptionFailed
        }
    }
}
