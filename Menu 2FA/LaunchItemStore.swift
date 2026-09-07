//
//  LaunchItemStore.swift
//  Menu 2FA
//

import AppKit

@Observable
final class LaunchItemStore {
    static let shared = LaunchItemStore()

    private static let storageKey = "authItems"

    var items: [LaunchItem] = []

    private init() {
        load()
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

    func currentCode(for item: LaunchItem) -> String? {
        TOTP.code(for: item.secret)
    }

    @discardableResult
    func copyCode(_ item: LaunchItem) -> Bool {
        guard let code = TOTP.code(for: item.secret) else {
            Self.presentCodeError(name: item.name)
            return false
        }

        Self.writeToPasteboard(code)
        // Retry on the next turn — writes during menu tracking can fail to stick.
        DispatchQueue.main.async {
            Self.writeToPasteboard(code)
        }
        return true
    }

    private static func writeToPasteboard(_ code: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if !pasteboard.setString(code, forType: .string) {
            pasteboard.declareTypes([.string], owner: nil)
            pasteboard.setString(code, forType: .string)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey) else { return }
        do {
            items = try JSONDecoder().decode([LaunchItem].self, from: data)
        } catch {
            items = []
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(items)
            UserDefaults.standard.set(data, forKey: Self.storageKey)
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
