//
//  iCloudListSync.swift
//  Menu 2FA
//

import Foundation

enum iCloudListSync {
    static let enabledKey = "syncsWithiCloud"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var hasAccount: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }
}

enum AuthItemCloudStore {
    private static let schemaKey = "authItemSchema"

    static func load() -> AuthItemCloudSchema? {
        let store = NSUbiquitousKeyValueStore.default
        store.synchronize()
        guard let data = store.data(forKey: schemaKey) else { return nil }
        return try? JSONDecoder().decode(AuthItemCloudSchema.self, from: data)
    }

    static func save(_ schema: AuthItemCloudSchema) {
        do {
            let data = try JSONEncoder().encode(schema)
            let store = NSUbiquitousKeyValueStore.default
            store.set(data, forKey: schemaKey)
            store.synchronize()
        } catch {
            NSLog("Menu 2FA: failed to save iCloud schema: \(error.localizedDescription)")
        }
    }
}
