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

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        applyOfficialAppIcon()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyOfficialAppIcon()
        statusItemController.install()
        NSApp.mainMenu?.items.first?.title = ""
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
