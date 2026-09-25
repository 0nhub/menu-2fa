//
//  SharedAccountStore.swift
//  Menu 2FA
//

import Darwin
import Foundation

struct SharedAccount: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var secret: String
    var emoji: String?
    var iconPNG: Data?
}

struct SharedAccountChoice: Sendable {
    var id: String
    var name: String
}

enum SharedAccountStore {
    static let choicesKey = "widgetAccountChoices"
    private static let copiedVisibleFor: TimeInterval = 6

    static func markWidgetCopied(accountID: String) {
        let at = Date().timeIntervalSince1970
        AppGroup.set(accountID, forKey: AppGroup.widgetCopiedAccountIDKey)
        AppGroup.set(at, forKey: AppGroup.widgetCopiedAtKey)
        if let url = copiedMarkerURL {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let payload = ["id": accountID, "at": String(at)]
            if let data = try? JSONSerialization.data(withJSONObject: payload) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    static func showsCopied(accountID: String, at date: Date = .now) -> Bool {
        guard !accountID.isEmpty, let marker = copiedMarker(), marker.id == accountID else { return false }
        let age = date.timeIntervalSince1970 - marker.at
        return age >= -2 && age < copiedVisibleFor
    }

    private static var copiedMarkerURL: URL? {
        sharedDirectory?.appendingPathComponent("widget-copied.json")
    }

    private static func copiedMarker() -> (id: String, at: Double)? {
        guard let url = copiedMarkerURL,
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let id = object["id"],
              let at = object["at"].flatMap(Double.init)
        else { return nil }
        return (id, at)
    }

    static var isAppLockEnabled: Bool {
        AppGroup.bool(forKey: AppGroup.requireAuthenticationKey)
    }

    static var isProUnlocked: Bool {
        if let url = proMarkerURL,
           let text = try? String(contentsOf: url, encoding: .utf8) {
            return text.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
        }
        return AppGroup.bool(forKey: AppGroup.proUnlockedKey)
    }

    static func setProUnlocked(_ unlocked: Bool) {
        AppGroup.set(unlocked, forKey: AppGroup.proUnlockedKey)
        guard let url = proMarkerURL else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? (unlocked ? "1" : "0").write(to: url, atomically: true, encoding: .utf8)
    }

    private static var proMarkerURL: URL? {
        sharedDirectory?.appendingPathComponent("widget-pro.txt")
    }

    static func save(_ accounts: [SharedAccount]) {
        do {
            let data = try JSONEncoder().encode(accounts)
            SharedKeychain.write(data)
            writeSharedFile(data)
            writeIconFiles(accounts)
            writeChoices(accounts)
        } catch {
            NSLog("Menu 2FA: failed to encode shared accounts: \(error.localizedDescription)")
        }
    }

    static func accountChoices() -> [SharedAccountChoice] {
        if let rows = AppGroup.defaults?.stringArray(forKey: choicesKey) ?? UserDefaults.standard.stringArray(forKey: choicesKey),
           !rows.isEmpty {
            let parsed = rows.compactMap(choice(from:))
            if !parsed.isEmpty { return parsed }
        }
        return loadAccounts().map { account in
            let title = account.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return SharedAccountChoice(
                id: account.id.uuidString,
                name: title.isEmpty ? account.id.uuidString : title
            )
        }
    }

    static func writeIconFiles(_ accounts: [SharedAccount]) {
        var directories: [URL] = []
        if let shared = sharedDirectory?.appendingPathComponent("icons", isDirectory: true) {
            directories.append(shared)
        }
        if let group = AppGroup.containerURL?.appendingPathComponent("icons", isDirectory: true) {
            directories.append(group)
        }
        for directory in directories {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for account in accounts {
                guard let png = account.iconPNG else { continue }
                try? png.write(to: directory.appendingPathComponent("\(account.id.uuidString).png"), options: .atomic)
            }
        }
    }

    static func writeChoices(_ accounts: [SharedAccount]) {
        let rows = accounts.map { account in
            let title = account.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(account.id.uuidString)\t\(title.isEmpty ? account.id.uuidString : title)"
        }
        AppGroup.set(rows, forKey: choicesKey)
    }

    static func noteIntent(_ line: String) {
        guard let directory = sharedDirectory else { return }
        let text = "\(ISO8601DateFormatter().string(from: Date())) \(ProcessInfo.processInfo.processName) \(line)\n"
        let url = directory.appendingPathComponent("intent-handler-probe.txt")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(Data(text.utf8))
        } else {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private static func choice(from row: String) -> SharedAccountChoice? {
        let parts = row.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let name = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return SharedAccountChoice(id: String(parts[0]), name: name)
    }

    static func loadAccounts() -> [SharedAccount] {
        var order: [UUID] = []
        var byID: [UUID: SharedAccount] = [:]
        for data in [readSharedFile(), AppGroup.readAccounts(), SharedKeychain.read()].compactMap({ $0 }) {
            guard let accounts = decodeAccounts(data) else { continue }
            for account in accounts {
                if byID[account.id] == nil {
                    order.append(account.id)
                    byID[account.id] = account
                } else {
                    merge(account, into: &byID[account.id]!)
                }
            }
        }
        let loaded = order.compactMap { byID[$0] }
        if !loaded.isEmpty {
            writeChoices(loaded)
        }
        return loaded
    }

    private static func merge(_ incoming: SharedAccount, into current: inout SharedAccount) {
        if current.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            current.name = incoming.name
        }
        if (current.emoji ?? "").isEmpty {
            current.emoji = incoming.emoji
        }
        if (current.iconPNG?.count ?? 0) < (incoming.iconPNG?.count ?? 0) {
            current.iconPNG = incoming.iconPNG
        }
        if current.secret.isEmpty {
            current.secret = incoming.secret
        }
    }

    private static func decodeAccounts(_ data: Data) -> [SharedAccount]? {
        if let accounts = try? JSONDecoder().decode([SharedAccount].self, from: data), !accounts.isEmpty {
            return accounts.map { account in
                var copy = account
                if copy.iconPNG == nil {
                    copy.iconPNG = iconFile(for: copy.id)
                }
                return copy
            }
        }
        struct LooseAccount: Codable {
            var id: UUID
            var name: String
            var secret: String
            var emoji: String?
            var iconPNG: Data?
            var iconData: Data?
            var urlIconData: Data?
        }
        guard let rows = try? JSONDecoder().decode([LooseAccount].self, from: data), !rows.isEmpty else {
            return nil
        }
        return rows.map {
            SharedAccount(
                id: $0.id,
                name: $0.name,
                secret: $0.secret,
                emoji: $0.emoji,
                iconPNG: $0.iconPNG ?? $0.iconData ?? $0.urlIconData ?? iconFile(for: $0.id)
            )
        }
    }

    static func iconFile(for id: UUID) -> Data? {
        let names = ["\(id.uuidString).png"]
        var directories: [URL] = []
        if let shared = sharedDirectory?.appendingPathComponent("icons", isDirectory: true) {
            directories.append(shared)
        }
        if let group = AppGroup.containerURL?.appendingPathComponent("icons", isDirectory: true) {
            directories.append(group)
        }
        for directory in directories {
            for name in names {
                if let data = try? Data(contentsOf: directory.appendingPathComponent(name)), !data.isEmpty {
                    return data
                }
            }
        }
        return nil
    }

    static func account(id: UUID) -> SharedAccount? {
        loadAccounts().first { $0.id == id }
    }

    static func account(named name: String) -> SharedAccount? {
        loadAccounts().first { $0.name == name }
    }

    static var sharedDirectory: URL? {
        guard let home = realHomeDirectory() else { return nil }
        return home.appendingPathComponent("Library/Application Support/ga.sgroi.menu-2fa", isDirectory: true)
    }

    static var sharedFileURL: URL? {
        sharedDirectory?.appendingPathComponent("widget-accounts.json")
    }

    private static func writeSharedFile(_ data: Data) {
        guard let directory = sharedDirectory, let url = sharedFileURL else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("Menu 2FA: shared file write failed: \(error.localizedDescription)")
        }
    }

    private static func readSharedFile() -> Data? {
        guard let url = sharedFileURL else { return nil }
        return try? Data(contentsOf: url)
    }

    private static func realHomeDirectory() -> URL? {
        guard let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir else { return nil }
        return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
    }
}
