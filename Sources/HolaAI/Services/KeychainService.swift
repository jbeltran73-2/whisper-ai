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

    private init() {}

    // MARK: - API Key

    /// Save OpenAI API key to Keychain
    /// - Parameter apiKey: The API key to save
    /// - Returns: True if saved successfully
    @discardableResult
    func saveAPIKey(_ apiKey: String) -> Bool {
        // Delete existing key first
        deleteAPIKey()

        guard let data = apiKey.data(using: .utf8) else {
            logger.error("Failed to convert API key to data")
            return false
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: primaryService,
            kSecAttrAccount as String: openRouterKeyAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecSuccess {
            logger.info("API key saved to Keychain")
            return true
        } else {
            logger.error("Failed to save API key: \(status)")
            return false
        }
    }

    /// Retrieve OpenAI API key from Keychain
    /// - Returns: The API key if found, nil otherwise
    func getAPIKey() -> String? {
        if let key = getKey(for: openRouterKeyAccount) {
            return key
        }
        return getKey(for: legacyOpenAIKeyAccount)
    }

    private func getKey(for account: String) -> String? {
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

    /// Delete OpenAI API key from Keychain
    /// - Returns: True if deleted successfully
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

    private func deleteKey(for account: String, service: String) -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        return SecItemDelete(query as CFDictionary)
    }

    /// Check if an API key is stored
    var hasAPIKey: Bool {
        getAPIKey() != nil
    }
}
