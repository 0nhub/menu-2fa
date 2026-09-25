import AppKit
import Darwin
import Foundation
import WidgetKit

/// The widget extension cannot keep a pasteboard write: the process exits and
/// macOS drops it. The menu-bar app performs the single clipboard write.
enum WidgetCopyBridge {
    static let notificationName = CFNotificationName("ga.sgroi.menu-2fa.widget-copy" as CFString)
    private static let distributedName = Notification.Name("ga.sgroi.menu-2fa.widget-copy")
    private static let lock = NSLock()
    private static var handledNonce: String?

    static func requestCopy(accountID: String) {
        guard !accountID.isEmpty else { return }
        writeRequest(accountID: accountID)
        DistributedNotificationCenter.default().postNotificationName(
            distributedName,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            notificationName,
            nil,
            nil,
            true
        )
        launchMenuBarAppIfNeeded()
    }

    static func hasPendingRequest() -> Bool {
        pendingRequest() != nil
    }

    @discardableResult
    static func deliverPendingCopy() -> Bool {
        guard Bundle.main.bundleIdentifier == "ga.sgroi.menu-2fa" else { return false }
        guard SharedAccountStore.isProUnlocked else {
            _ = consumePendingRequest()
            return false
        }
        guard let request = consumePendingRequest() else { return false }
        let accounts = SharedAccountStore.loadAccounts()
        let account = accounts.first(where: { $0.id.uuidString == request.id })
            ?? accounts.first(where: { $0.name == request.id })
        guard let account, let code = TOTP.code(for: account.secret) else { return false }
        let accountID = account.id.uuidString
        let apply = {
            Clipboard.copy(code)
            SharedAccountStore.markWidgetCopied(accountID: accountID)
            WidgetCenter.shared.reloadAllTimelines()
            afterCopy()
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
        return true
    }

    static var afterCopy: () -> Void = {}

    static func startListening(_ handler: @escaping () -> Void) {
        Listener.shared.handler = handler
        Listener.shared.start()
    }

    private static func writeRequest(accountID: String) {
        let payload = [
            "id": accountID,
            "nonce": UUID().uuidString,
            "at": String(Date().timeIntervalSince1970)
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        for url in requestURLs {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func pendingRequest() -> (id: String, nonce: String, at: Double)? {
        for url in requestURLs {
            guard let data = try? Data(contentsOf: url),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                  let id = object["id"], !id.isEmpty,
                  let nonce = object["nonce"],
                  let at = object["at"].flatMap(Double.init),
                  Date().timeIntervalSince1970 - at < 20
            else { continue }
            return (id, nonce, at)
        }
        return nil
    }

    private static func consumePendingRequest() -> (id: String, nonce: String, at: Double)? {
        lock.lock()
        defer { lock.unlock() }
        guard let request = pendingRequest(), request.nonce != handledNonce else { return nil }
        handledNonce = request.nonce
        for url in requestURLs {
            try? FileManager.default.removeItem(at: url)
        }
        return request
    }

    private static var requestURLs: [URL] {
        var urls: [URL] = []
        if let group = AppGroup.containerURL {
            urls.append(group.appendingPathComponent("widget-copy-request.json"))
        }
        if let home = SharedAccountStore.sharedDirectory {
            urls.append(home.appendingPathComponent("widget-copy-request.json"))
        }
        return urls
    }

    private static func launchMenuBarAppIfNeeded() {
        guard Bundle.main.bundleIdentifier != "ga.sgroi.menu-2fa" else { return }
        let running = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "ga.sgroi.menu-2fa"
        }
        guard !running else { return }
        let appURL = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
    }

    private final class Listener {
        static let shared = Listener()
        var handler: (() -> Void)?
        private var registered = false
        private var directorySource: DispatchSourceFileSystemObject?
        private var timer: Timer?

        func start() {
            guard !registered else { return }
            registered = true
            let observer = Unmanaged.passUnretained(self).toOpaque()
            CFNotificationCenterAddObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                observer,
                { _, observer, _, _, _ in
                    guard let observer else { return }
                    let listener = Unmanaged<Listener>.fromOpaque(observer).takeUnretainedValue()
                    listener.schedule()
                },
                notificationName.rawValue,
                nil,
                .deliverImmediately
            )
            DistributedNotificationCenter.default().addObserver(
                forName: distributedName,
                object: nil,
                queue: .main
            ) { _ in
                Listener.shared.handler?()
            }
            watchDirectory()
            let timer = Timer(timeInterval: 0.3, repeats: true) { _ in
                Listener.shared.handler?()
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
            schedule()
        }

        private func schedule() {
            DispatchQueue.main.async {
                self.handler?()
            }
        }

        private func watchDirectory() {
            guard directorySource == nil,
                  let directory = SharedAccountStore.sharedDirectory
            else { return }
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let fd = open(directory.path, O_EVTONLY)
            guard fd >= 0 else { return }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .rename, .extend],
                queue: .main
            )
            source.setEventHandler { [weak self] in
                self?.handler?()
            }
            source.setCancelHandler {
                close(fd)
            }
            source.resume()
            directorySource = source
        }
    }
}
