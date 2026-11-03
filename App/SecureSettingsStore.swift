import Foundation
import Security

enum SecureSettingsStore {
    static func password(namespace: String) throws -> String {
        var query = base(namespace)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw BackupServiceError.message("Пароль копии недоступен. Разблокируй iPhone или настрой папку заново.")
        }
        return value
    }

    static func savePassword(_ password: String, namespace: String) throws {
        let query = base(namespace)
        let attributes: [String: Any] = [
            kSecValueData as String: Data(password.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            attributes.forEach { item[$0.key] = $0.value }
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
                throw BackupServiceError.message("Не удалось сохранить пароль в Связке ключей.")
            }
        } else if status != errSecSuccess {
            throw BackupServiceError.message("Связка ключей сейчас недоступна.")
        }
    }

    static func removePassword(namespace: String) {
        SecItemDelete(base(namespace) as CFDictionary)
    }

    private static func base(_ namespace: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "app.lumo.automatic-backup.\(namespace)",
         kSecAttrAccount as String: "recovery-password"]
    }
}
