//
//  AppGroup.swift
//  Menu 2FA
//

import Foundation

enum AppGroup {
    /// macOS application group (`TEAMID.bundle`). Works without an iOS-style `group.` portal ID.
    static let identifier = "AUP84ZCD2B.ga.sgroi.menu-2fa"
    static let legacyIdentifier = "group.ga.sgroi.menu-2fa"
    static let authItemsKey = "authItems"
    static let requireAuthenticationKey = "requireAuthentication"
    static let proUnlockedKey = "proUnlocked"
    static let widgetCopiedAccountIDKey = "widgetCopiedAccountID"
    static let widgetCopiedAtKey = "widgetCopiedAt"

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: identifier)
    }

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    static var accountsFileURL: URL? {
        containerURL?
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent("authItems.json")
    }

    static func readAccounts() -> Data? {
        if let url = accountsFileURL, let data = try? Data(contentsOf: url), !data.isEmpty {
            return data
        }
        if let data = defaults?.data(forKey: authItemsKey), !data.isEmpty {
            return data
        }
        if let legacy = UserDefaults(suiteName: legacyIdentifier)?.data(forKey: authItemsKey), !legacy.isEmpty {
            return legacy
        }
        return UserDefaults.standard.data(forKey: authItemsKey)
    }

    static func writeAccounts(_ data: Data) {
        defaults?.set(data, forKey: authItemsKey)
        UserDefaults.standard.set(data, forKey: authItemsKey)
        defaults?.synchronize()
        guard let url = accountsFileURL else {
            NSLog("Menu 2FA: App Group container unavailable for \(identifier)")
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("Menu 2FA: failed to write shared accounts: \(error.localizedDescription)")
        }
    }

    static var hasAccountsFile: Bool {
        guard let url = accountsFileURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    static func bool(forKey key: String) -> Bool {
        if let defaults, defaults.object(forKey: key) != nil {
            return defaults.bool(forKey: key)
        }
        return UserDefaults.standard.bool(forKey: key)
    }

    static func set(_ value: Any?, forKey key: String) {
        defaults?.set(value, forKey: key)
        UserDefaults.standard.set(value, forKey: key)
        defaults?.synchronize()
    }
}
