//
//  SelectAccountIntentHandler.swift
//  Menu 2FA
//

import Foundation
import Intents

@objc(SelectAccountIntentHandler)
final class SelectAccountIntentHandler: INExtension, SelectAccountIntentHandling {
    override func handler(for intent: INIntent) -> Any {
        self
    }

    func provideAccountOptionsCollection(
        for intent: SelectAccountIntent,
        with completion: @escaping (INObjectCollection<WidgetAccount>?, Error?) -> Void
    ) {
        let items = makeAccounts()
        note("options count=\(items.count)")
        completion(INObjectCollection(items: items), nil)
    }

    func provideAccountOptions(
        for intent: SelectAccountIntent,
        with completion: @escaping ([WidgetAccount]?, Error?) -> Void
    ) {
        let items = makeAccounts()
        note("legacy options count=\(items.count)")
        completion(items, nil)
    }

    func resolveAccount(
        for intent: SelectAccountIntent,
        with completion: @escaping (WidgetAccountResolutionResult) -> Void
    ) {
        completion(resolveNow(intent.account))
    }

    func defaultAccount(for intent: SelectAccountIntent) -> WidgetAccount? {
        makeAccounts().first
    }

    private func resolveNow(_ current: WidgetAccount?) -> WidgetAccountResolutionResult {
        let items = makeAccounts()
        if let current, items.contains(where: { $0.identifier == current.identifier }) {
            return .success(with: current)
        }
        if let first = items.first {
            return .success(with: first)
        }
        return .needsValue()
    }

    private func makeAccounts() -> [WidgetAccount] {
        SharedAccountStore.loadAccounts().map { account in
            let title = account.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let display = title.isEmpty ? account.id.uuidString : title
            return WidgetAccount(identifier: account.id.uuidString, display: display)
        }
    }

    private func note(_ line: String) {
        guard let directory = SharedAccountStore.sharedDirectory else { return }
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
}
