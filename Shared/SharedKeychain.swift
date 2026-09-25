//
//  SharedKeychain.swift
//  Menu 2FA
//

import Foundation
import Security

enum SharedKeychain {
    private static let service = "ga.sgroi.menu-2fa"
    private static let account = "shared-auth-items"
    private static let accessGroup = "AUP84ZCD2B.ga.sgroi.menu-2fa"

    static func write(_ data: Data) {
        if !add(data, dataProtection: true) {
            _ = add(data, dataProtection: false)
        }
    }

    static func read() -> Data? {
        if let data = copy(dataProtection: true) { return data }
        return copy(dataProtection: false)
    }

    private static func add(_ data: Data, dataProtection: Bool) -> Bool {
        var query = baseQuery()
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        if dataProtection {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            NSLog("Menu 2FA: keychain write failed (\(status)) protection=\(dataProtection)")
            return false
        }
        return true
    }

    private static func copy(dataProtection: Bool) -> Data? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        if dataProtection {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup
        ]
    }
}
