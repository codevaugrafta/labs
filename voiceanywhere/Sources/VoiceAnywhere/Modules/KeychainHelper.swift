import Foundation
import Security

/// Provides thread-safe read/write access to API keys stored in the macOS Keychain.
struct KeychainHelper {
    private static let service = "com.voiceanywhere"

    // MARK: - Public API

    static func setKey(_ key: String, for provider: TTSProviderType) {
        let account = accountName(for: provider)
        guard let data = key.data(using: .utf8) else { return }

        // Delete any existing item first to avoid errSecDuplicateItem.
        delete(account: account)

        let addQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data,
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            print("KeychainHelper: SecItemAdd failed with status \(status)")
        }
    }

    static func getKey(for provider: TTSProviderType) -> String? {
        let account = accountName(for: provider)

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    static func deleteKey(for provider: TTSProviderType) {
        delete(account: accountName(for: provider))
    }

    // MARK: - Private Helpers

    private static func accountName(for provider: TTSProviderType) -> String {
        "api-key-\(provider.rawValue)"
    }

    private static func delete(account: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
