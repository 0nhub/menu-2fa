//
//  LaunchItemStore.swift
//  Menu 2FA
//

import AppKit
import WidgetKit

@Observable
final class LaunchItemStore {
    static let shared = LaunchItemStore()

    private static let storageKey = "authItems"
    private static let cloudUpdatedAtKey = "authItemSchemaUpdatedAt"

    var items: [LaunchItem] = []
    private(set) var syncsWithiCloud = iCloudListSync.isEnabled

    private var cloudUpdatedAt: Date?
    private var suppressesCloudPush = false
    private var didStartCloud = false
    private var observers: [NSObjectProtocol] = []

    private init() {
        load()
        NotificationCenter.default.addObserver(
            forName: .NSUbiquityIdentityDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyProAccess()
        }
        applyProAccess()
    }

    func applyProAccess() {
        let allowed = ProStore.shared.isPro && iCloudListSync.isEnabled
        guard allowed else {
            syncsWithiCloud = false
            return
        }
        syncsWithiCloud = true
        guard iCloudListSync.hasAccount else { return }
        startMonitoringIfNeeded()
        guard !didStartCloud else { return }
        didStartCloud = true
        applyRemoteIfNeeded(keepUnmatchedLocal: false)
    }

    func setSyncsWithiCloud(_ enabled: Bool) {
        guard ProStore.shared.isPro else { return }
        iCloudListSync.isEnabled = enabled
        syncsWithiCloud = enabled
        guard enabled, iCloudListSync.hasAccount else { return }
        startMonitoringIfNeeded()
        NSUbiquitousKeyValueStore.default.synchronize()
        if let remote = AuthItemCloudStore.load() {
            applyRemote(remote, keepUnmatchedLocal: true)
        } else {
            pushToCloud()
        }
    }

    func add(_ item: LaunchItem) {
        items.append(item)
        persist()
    }

    func update(_ item: LaunchItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
        persist()
    }

    func remove(_ item: LaunchItem) {
        items.removeAll { $0.id == item.id }
        persist()
    }

    func move(id: LaunchItem.ID, onto targetID: LaunchItem.ID) {
        guard id != targetID,
              let from = items.firstIndex(where: { $0.id == id }),
              let to = items.firstIndex(where: { $0.id == targetID })
        else { return }
        let item = items.remove(at: from)
        items.insert(item, at: to)
        persist()
    }

    func republishForWidgets() {
        persistLocal()
    }

    func currentCode(for item: LaunchItem) -> String? {
        TOTP.code(for: item.secret)
    }

    @discardableResult
    func copyCode(_ item: LaunchItem) -> Bool {
        guard let code = TOTP.code(for: item.secret) else {
            Self.presentCodeError(name: item.name)
            return false
        }

        Clipboard.copy(code)
        return true
    }

    private func startMonitoringIfNeeded() {
        guard observers.isEmpty else { return }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default,
            queue: .main
        ) { [weak self] notification in
            self?.handleCloudChange(notification)
        })
    }

    private func handleCloudChange(_ notification: Notification) {
        guard syncsWithiCloud else { return }
        guard let reason = notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int else {
            applyRemoteIfNeeded(keepUnmatchedLocal: false)
            return
        }
        switch reason {
        case NSUbiquitousKeyValueStoreServerChange, NSUbiquitousKeyValueStoreInitialSyncChange:
            applyRemoteIfNeeded(keepUnmatchedLocal: false)
        case NSUbiquitousKeyValueStoreQuotaViolationChange:
            NSLog("Menu 2FA: iCloud key-value store quota exceeded")
        default:
            break
        }
    }

    private func applyRemoteIfNeeded(keepUnmatchedLocal: Bool) {
        guard let remote = AuthItemCloudStore.load() else { return }
        applyRemote(remote, keepUnmatchedLocal: keepUnmatchedLocal)
    }

    private func applyRemote(_ schema: AuthItemCloudSchema, keepUnmatchedLocal: Bool) {
        if let cloudUpdatedAt, schema.updatedAt <= cloudUpdatedAt, !keepUnmatchedLocal {
            return
        }

        suppressesCloudPush = true
        items = AuthItemCloudSchema.materialize(
            schema.items,
            onto: items,
            keepUnmatched: keepUnmatchedLocal
        )
        cloudUpdatedAt = schema.updatedAt
        persistLocal()
        suppressesCloudPush = false

        if keepUnmatchedLocal {
            pushToCloud()
        }
    }

    private func pushToCloud() {
        guard syncsWithiCloud, !suppressesCloudPush else { return }
        let schema = AuthItemCloudSchema(items: items)
        cloudUpdatedAt = schema.updatedAt
        AppGroup.set(schema.updatedAt.timeIntervalSince1970, forKey: Self.cloudUpdatedAtKey)
        AuthItemCloudStore.save(schema)
    }

    private func load() {
        if let timestamp = AppGroup.defaults?.object(forKey: Self.cloudUpdatedAtKey) as? TimeInterval
            ?? UserDefaults.standard.object(forKey: Self.cloudUpdatedAtKey) as? TimeInterval {
            cloudUpdatedAt = Date(timeIntervalSince1970: timestamp)
        }
        let candidates = [
            AppGroup.readAccounts(),
            UserDefaults.standard.data(forKey: Self.storageKey)
        ].compactMap { $0 }
        for data in candidates {
            if let decoded = try? JSONDecoder().decode([LaunchItem].self, from: data) {
                items = decoded
                break
            }
        }
        if !items.isEmpty {
            persistLocal()
        }
    }

    private func persist() {
        persistLocal()
        pushToCloud()
    }

    private func persistLocal() {
        do {
            let data = try JSONEncoder().encode(items)
            AppGroup.writeAccounts(data)
            SharedAccountStore.save(
                items.map {
                    SharedAccount(
                        id: $0.id,
                        name: $0.name,
                        secret: $0.secret,
                        emoji: $0.displayEmoji,
                        iconPNG: $0.widgetIconPNG()
                    )
                }
            )
            if let cloudUpdatedAt {
                AppGroup.set(cloudUpdatedAt.timeIntervalSince1970, forKey: Self.cloudUpdatedAtKey)
            }
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            NSLog("Menu 2FA: failed to save items: \(error.localizedDescription)")
        }
    }

    private static func presentCodeError(name: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = String(format: String(localized: "Can't Copy Code for “%@”"), name)
            alert.informativeText = String(localized: "The token is invalid. Edit the item and check the secret.")
            alert.runModal()
        }
    }
}
