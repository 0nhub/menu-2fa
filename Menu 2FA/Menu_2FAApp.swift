//
//  Menu_2FAApp.swift
//  Menu 2FA
//

import AppKit
import Intents
import SwiftUI
import WidgetKit

@main
enum Menu2FAMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItemController = StatusItemController(store: .shared)
    private static let didPresentInitialUIKey = "didPresentInitialUI"
    private static let storeAppPath = "/Applications/2FA.app"

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        applyOfficialAppIcon()
        terminateStoreBuildIfNeeded()
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        if let event = NSAppleEventManager.shared().currentAppleEvent {
            handleGetURLEvent(event, withReplyEvent: NSAppleEventDescriptor())
        }
        Self.hideAllWindows()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyOfficialAppIcon()
        terminateStoreBuildIfNeeded()
        AppLock.mirrorToAppGroup()
        LaunchItemStore.shared.republishForWidgets()
        WidgetShareProbe.run(
            accountCount: LaunchItemStore.shared.items.count,
            names: LaunchItemStore.shared.items.map(\.name)
        )
        WidgetCenter.shared.reloadAllTimelines()
        ProStore.shared.start()
        if ProStore.shared.isPro, LaunchItemStore.shared.syncsWithiCloud, iCloudListSync.hasAccount {
            NSUbiquitousKeyValueStore.default.synchronize()
        }
        statusItemController.install()
        installSettingsCommand()
        NSApp.mainMenu?.items.first?.title = ""
        WidgetCopyBridge.afterCopy = {
            AppDelegate.hideAllWindows()
        }
        WidgetCopyBridge.startListening {
            WidgetCopyBridge.deliverPendingCopy()
        }

        if WidgetCopyBridge.hasPendingRequest() || Self.currentEventIsWidgetCopy() {
            WidgetCopyBridge.deliverPendingCopy()
            Self.hideAllWindows()
            return
        }

        let defaults = UserDefaults.standard
        let firstUI = !defaults.bool(forKey: Self.didPresentInitialUIKey)
        if firstUI || LaunchItemStore.shared.items.isEmpty {
            defaults.set(true, forKey: Self.didPresentInitialUIKey)
            EditorWindowController.shared.show(skipAuthentication: true)
        } else {
            Self.hideAllWindows()
        }
    }

    private func applyOfficialAppIcon() {
        if let url = Bundle.main.url(forResource: "Menu2FALogo", withExtension: "png"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
            return
        }
        if let icon = NSImage(named: "AppIcon") ?? NSImage(named: "ApplicationIcon") {
            NSApp.applicationIconImage = icon
        }
    }

    private func installSettingsCommand() {
        guard let appMenu = NSApp.mainMenu?.items.first?.submenu else { return }
        if appMenu.items.contains(where: { $0.action == #selector(openSettings(_:)) }) {
            return
        }
        let item = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings(_:)),
            keyEquivalent: ","
        )
        item.target = self
        appMenu.insertItem(item, at: min(2, appMenu.items.count))
    }

    @objc
    private func openSettings(_ sender: Any?) {
        EditorWindowController.shared.show()
    }

    private func terminateStoreBuildIfNeeded() {
        guard Bundle.main.bundleURL.path != Self.storeAppPath else { return }
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: "ga.sgroi.menu-2fa") {
            guard app.bundleURL?.path == Self.storeAppPath else { continue }
            app.forceTerminate()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Self.hideAllWindows()
        return false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        false
    }

    nonisolated func application(_ application: NSApplication, handlerFor intent: INIntent) -> Any? {
        SelectAccountIntentHandler()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            Self.handleWidgetCopy(url)
        }
    }

    @objc
    func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard let raw = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: raw)
        else { return }
        Self.handleWidgetCopy(url)
    }

    static func handleWidgetCopy(_ url: URL) {
        guard let accountID = CopyLink.accountID(from: url) else { return }
        hideAllWindows()
        copyAccount(accountID)
        DispatchQueue.main.async {
            hideAllWindows()
        }
    }

    static func copyPendingWidgetCode() {
        WidgetCopyBridge.deliverPendingCopy()
    }

    private static func copyAccount(_ accountID: String) {
        let uuid = UUID(uuidString: accountID)
        let storeItem: LaunchItem? = {
            if let uuid {
                return LaunchItemStore.shared.items.first(where: { $0.id == uuid })
            }
            return LaunchItemStore.shared.items.first(where: { $0.name == accountID })
        }()
        let sharedItem: SharedAccount? = {
            let accounts = SharedAccountStore.loadAccounts()
            if let uuid {
                return accounts.first(where: { $0.id == uuid })
            }
            return accounts.first(where: { $0.name == accountID })
        }()
        let secret = storeItem?.secret ?? sharedItem?.secret
        let resolvedID = storeItem?.id.uuidString ?? sharedItem?.id.uuidString ?? accountID
        guard let secret, let code = TOTP.code(for: secret) else { return }
        Clipboard.copy(code)
        SharedAccountStore.markWidgetCopied(accountID: resolvedID)
        WidgetCenter.shared.reloadAllTimelines()
        hideAllWindows()
    }

    static func hideAllWindows() {
        EditorWindowController.shared.orderOut()
        for window in NSApp.windows {
            window.orderOut(nil)
        }
    }

    private static func currentEventIsWidgetCopy() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              let raw = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: raw)
        else { return false }
        return CopyLink.accountID(from: url) != nil
    }
}
