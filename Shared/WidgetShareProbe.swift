//
//  WidgetShareProbe.swift
//  Menu 2FA
//

import Foundation

enum WidgetShareProbe {
    static func run(accountCount: Int, names: [String]) {
        let keychainCount = SharedAccountStore.loadAccounts().count
        let container = AppGroup.containerURL?.path ?? "nil"
        let file = AppGroup.accountsFileURL?.path ?? "nil"
        let fileExists = AppGroup.hasAccountsFile
        let report = """
        time=\(ISO8601DateFormatter().string(from: Date()))
        appItems=\(accountCount)
        names=\(names.joined(separator: " | "))
        storeLoad=\(keychainCount)
        container=\(container)
        file=\(file)
        fileExists=\(fileExists)
        """
        NSLog("Menu 2FA probe: \(report.replacingOccurrences(of: "\n", with: "; "))")

        let urls = [
            AppGroup.containerURL?.appendingPathComponent("widget-probe.txt"),
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("widget-probe.txt")
        ].compactMap { $0 }

        for url in urls {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? report.write(to: url, atomically: true, encoding: .utf8)
        }
        if let directory = SharedAccountStore.sharedDirectory {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? report.write(
                to: directory.appendingPathComponent("widget-probe.txt"),
                atomically: true,
                encoding: .utf8
            )
        }
    }
}
