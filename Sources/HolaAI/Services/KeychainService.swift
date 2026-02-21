import Foundation
import Security
import os.log

/// Service for securely storing sensitive data in the macOS Keychain
/// Thread-safe singleton for Keychain operations
final class KeychainService: Sendable {
    @MainActor static let shared = KeychainService()

    private let logger = Logger(subsystem: "com.holaai.app", category: "Keychain")

    private let primaryService = "com.holaai.app"
    private let legacyServices = ["com.whisperai.app"]
    private let openRouterKeyAccount = "openrouter-api-key"
    private let legacyOpenAIKeyAccount = "openai-api-key"
    private let groqKeyAccount = "groq-api-key"
    private let cerebrasKeyAccount = "cerebras-api-key"

    private init() {}

    // MARK: - Multi-Provider Key Management

    /// Save an API key for a specific provider account
    @discardableResult
    func saveKey(_ key: String, for account: String) -> Bool {
        // Delete existing first
        deleteKey(for: account, service: primaryService)

        guard let data = key.data(using: .utf8) else {
            logger.error("Failed to convert API key to data for \(account)")
            return false
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: primaryService,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecSuccess {
            logger.info("API key saved for \(account)")
            return true
        } else {
            logger.error("Failed to save API key for \(account): \(status)")
            return false
        }
    }

    /// Retrieve an API key for a specific provider account
    func getKey(for account: String) -> String? {
        if let key = getKey(for: account, service: primaryService) {
            return key
        }

        for service in legacyServices {
            if let key = getKey(for: account, service: service) {
                return key
            }
        }

        return nil
    }

    /// Delete an API key for a specific provider account
    @discardableResult
    func deleteKey(for account: String) -> Bool {
        var statuses: [OSStatus] = []
        let services = [primaryService] + legacyServices
        for service in services {
            statuses.append(deleteKey(for: account, service: service))
        }
        return statuses.allSatisfy { $0 == errSecSuccess || $0 == errSecItemNotFound }
    }

    /// Check if a key exists for a specific provider account
    func hasKey(for account: String) -> Bool {
        getKey(for: account) != nil
    }

    // MARK: - Legacy API (maps to OpenRouter)

    /// Save OpenRouter API key to Keychain (legacy compatibility)
    @discardableResult
    func saveAPIKey(_ apiKey: String) -> Bool {
        saveKey(apiKey, for: openRouterKeyAccount)
    }

    /// Retrieve OpenRouter API key from Keychain (legacy compatibility)
    func getAPIKey() -> String? {
        if let key = getKey(for: openRouterKeyAccount) {
            return key
        }
        return getKey(for: legacyOpenAIKeyAccount)
    }

    /// Delete OpenRouter API key from Keychain (legacy compatibility)
    @discardableResult
    func deleteAPIKey() -> Bool {
        var statuses: [OSStatus] = []
        let services = [primaryService] + legacyServices

        for service in services {
            statuses.append(deleteKey(for: openRouterKeyAccount, service: service))
            statuses.append(deleteKey(for: legacyOpenAIKeyAccount, service: service))
        }

        let allDeleted = statuses.allSatisfy { $0 == errSecSuccess || $0 == errSecItemNotFound }
        if !allDeleted {
            logger.error("Failed to delete API key")
        }
        return allDeleted
    }

    /// Check if an OpenRouter API key is stored (legacy compatibility)
    var hasAPIKey: Bool {
        getAPIKey() != nil
    }

    /// Check if any required API key exists (for the currently configured providers)
    var hasAnyAPIKey: Bool {
        hasAPIKey || hasKey(for: groqKeyAccount) || hasKey(for: cerebrasKeyAccount)
    }

    // MARK: - Private

    private func getKey(for account: String, service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess, let data = result as? Data {
            return String(data: data, encoding: .utf8)
        }

        if status != errSecItemNotFound {
            logger.error("Failed to retrieve API key: \(status)")
        }

        return nil
    }

    @discardableResult
    private func deleteKey(for account: String, service: String) -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        return SecItemDelete(query as CFDictionary)
    }
}
