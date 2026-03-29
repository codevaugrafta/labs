import Foundation
import Security
import os.log

enum LeoSecretKey: CaseIterable, Hashable {
    case openRouter
    case inWorld

    var defaultsKey: String {
        switch self {
        case .openRouter: "leo.openRouterApiKey"
        case .inWorld: "leo.inworldApiKey"
        }
    }

    var accountName: String {
        switch self {
        case .openRouter: "api-key-openrouter"
        case .inWorld: "api-key-inworld"
        }
    }
}

protocol LeoSecretStore {
    func setSecret(_ secret: String, for key: LeoSecretKey)
    func getSecret(for key: LeoSecretKey) -> String?
    func deleteSecret(for key: LeoSecretKey)
}

protocol LeoDefaultsStore {
    func string(forKey defaultName: String) -> String?
    func removeObject(forKey defaultName: String)
}

extension UserDefaults: LeoDefaultsStore {}

struct LeoKeychainHelper: LeoSecretStore {
    private static let service = "com.franciscodilussor.leo"
    private static let logger = Logger(subsystem: service, category: "Keychain")

    func setSecret(_ secret: String, for key: LeoSecretKey) {
        deleteSecret(for: key)
        guard let data = secret.data(using: .utf8) else { return }

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.service,
            kSecAttrAccount: key.accountName,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable: kCFBooleanFalse as Any,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            Self.logger.error("SecItemAdd failed with status \(status)")
        }
    }

    func getSecret(for key: LeoSecretKey) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.service,
            kSecAttrAccount: key.accountName,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecAttrSynchronizable: kCFBooleanFalse as Any,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func deleteSecret(for key: LeoSecretKey) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.service,
            kSecAttrAccount: key.accountName,
            kSecAttrSynchronizable: kCFBooleanFalse as Any,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum LeoSecretMigrator {
    static func migrateLegacyDefaults(
        defaults: LeoDefaultsStore = UserDefaults.standard,
        secretStore: LeoSecretStore = LeoKeychainHelper()
    ) {
        for key in LeoSecretKey.allCases {
            guard let legacyValue = defaults.string(forKey: key.defaultsKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !legacyValue.isEmpty else {
                continue
            }

            if secretStore.getSecret(for: key)?.isEmpty != false {
                secretStore.setSecret(legacyValue, for: key)
            }
            defaults.removeObject(forKey: key.defaultsKey)
        }
    }
}
