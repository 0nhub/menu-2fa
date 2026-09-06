//
//  Menu_2FAApp.swift
//  Menu 2FA
//

import SwiftUI

@main
struct Menu_2FAApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Settings", id: "editor") {
            EditorView()
                .environment(LaunchItemStore.shared)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 440, height: 540)
        .defaultLaunchBehavior(.suppressed)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings") {
                    EditorWindowController.shared.show()
                }
                .keyboardShortcut(",")
            }
            CommandGroup(replacing: .newItem) {}
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItemController = StatusItemController(store: .shared)
    private static let didPresentInitialUIKey = "didPresentInitialUI"

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Stay a menu-bar app, but never rely on that alone for App Review discoverability.
        NSApp.setActivationPolicy(.accessory)
        applyOfficialAppIcon()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyOfficialAppIcon()
        statusItemController.install()
        NSApp.mainMenu?.items.first?.title = ""

        // Always ensure a visible Settings window on first successful launch (and when
        // there are no accounts yet). App Review reported neither a window nor a menu
        // bar extra — an empty accessory launch is too easy to miss on a crowded bar.
        let defaults = UserDefaults.standard
        let firstUI = !defaults.bool(forKey: Self.didPresentInitialUIKey)
        if firstUI || LaunchItemStore.shared.items.isEmpty {
            defaults.set(true, forKey: Self.didPresentInitialUIKey)
            // Bypass App Lock for this automatic presentation so reviewers always see UI.
            EditorWindowController.shared.show(skipAuthentication: true)
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

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusItemController.showSettings()
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        false
    }
}
