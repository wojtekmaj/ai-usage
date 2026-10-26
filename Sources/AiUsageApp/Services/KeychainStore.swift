import Foundation
import LocalAuthentication
import Security

final class KeychainStore {
    let service: String
    private var cachedValues: [String: Data] = [:]
    private var loadedAccounts = Set<String>()

    init(service: String = "com.wojciechmaj.ai-usage") {
        self.service = service
    }

    func save(data: Data, account: String, allowInteraction: Bool = true) throws {
        var base = baseQuery(account: account)
        if allowInteraction == false {
            let context = LAContext()
            context.interactionNotAllowed = true
            base[kSecUseAuthenticationContext as String] = context
        }
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
        ]

        var status = SecItemUpdate(base as CFDictionary, updateAttributes as CFDictionary)
        if status == errSecItemNotFound {
            var newItem = base
            newItem[kSecValueData as String] = data
            newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(newItem as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }

        cachedValues[account] = data
        loadedAccounts.insert(account)
    }

    func save(string: String, account: String, allowInteraction: Bool = true) throws {
        guard let data = string.data(using: .utf8) else {
            throw KeychainError.invalidStringEncoding
        }

        try save(data: data, account: account, allowInteraction: allowInteraction)
    }

    func loadData(account: String, allowInteraction: Bool = true) throws -> Data? {
        if loadedAccounts.contains(account) {
            return cachedValues[account]
        }

        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        if allowInteraction == false {
            let context = LAContext()
            context.interactionNotAllowed = true
            query[kSecUseAuthenticationContext as String] = context
        }

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            let data = item as? Data
            if let data {
                cachedValues[account] = data
            }
            loadedAccounts.insert(account)
            return data
        case errSecItemNotFound:
            loadedAccounts.insert(account)
            cachedValues.removeValue(forKey: account)
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func loadString(account: String, allowInteraction: Bool = true) throws -> String? {
        guard let data = try loadData(account: account, allowInteraction: allowInteraction) else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }

        cachedValues.removeValue(forKey: account)
        loadedAccounts.insert(account)
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

enum KeychainError: Error {
    case invalidStringEncoding
    case unexpectedStatus(OSStatus)
}
