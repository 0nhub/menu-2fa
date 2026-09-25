//
//  WidgetExtensionProbe.swift
//  Menu 2FA Widget
//

import Foundation

enum WidgetExtensionProbe {
    static func install() {
        note("install count=\(SharedAccountStore.loadAccounts().count)")
    }

    static func note(_ line: String) {
        let accounts = SharedAccountStore.loadAccounts()
        let text = "\(ISO8601DateFormatter().string(from: Date())) \(line) names=\(accounts.map(\.name).joined(separator: ","))\n"
        guard let directory = SharedAccountStore.sharedDirectory else { return }
        let url = directory.appendingPathComponent("widget-ext-probe.txt")
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
