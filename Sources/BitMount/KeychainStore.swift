import Foundation
import BitMountCore
import Security

struct KeychainItem: Identifiable, Hashable, Sendable {
    var account: String
    var label: String
    var kind: SecretKind

    var id: String { account }
}

enum KeychainStore {
    static let service = "io.github.alexander-gerontas.BitMount.bitlocker"

    static func save(account: String, label: String, secret: SavedSecret) throws {
        let data = try JSONEncoder().encode(secret)
        let query = baseQuery(account: account)
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrLabel as String] = label
        add[kSecAttrDescription as String] = secret.kind.rawValue
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        add[kSecAttrSynchronizable as String] = false
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError(status: status)
        }
    }

    static func load(account: String) -> SavedSecret? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return try? JSONDecoder().decode(SavedSecret.self, from: data)
    }

    static func delete(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }

    static func items() -> [KeychainItem] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let rows = result as? [[String: Any]]
        else { return [] }
        return rows.compactMap { row in
            guard let account = row[kSecAttrAccount as String] as? String else { return nil }
            let label = (row[kSecAttrLabel as String] as? String) ?? ""
            let kindRaw = (row[kSecAttrDescription as String] as? String) ?? SecretKind.password.rawValue
            return KeychainItem(
                account: account,
                label: label.isEmpty ? account : label,
                kind: SecretKind(rawValue: kindRaw) ?? .password
            )
        }
        .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

struct KeychainError: Error {
    var status: OSStatus
}
