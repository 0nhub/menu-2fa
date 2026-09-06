//
//  EditorWindowController.swift
//  Menu 2FA
//

import AppKit
import SwiftUI

@MainActor
final class EditorWindowController: NSObject, NSWindowDelegate {
    static let shared = EditorWindowController()

    private var window: NSWindow?

    func show(skipAuthentication: Bool = false) {
        if skipAuthentication {
            showUnlocked()
            return
        }
        AppLock.authorizeIfNeeded(reason: String(localized: "Authenticate to open Settings")) { [weak self] allowed in
            DispatchQueue.main.async {
                guard allowed else { return }
                self?.showUnlocked()
            }
        }
    }

    private func showUnlocked() {
        if window == nil {
            window = makeWindow()
        }

        guard let window else { return }

        window.collectionBehavior.insert(.moveToActiveSpace)
        window.toolbar?.centeredItemIdentifiers = []
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func makeWindow() -> NSWindow {
        let root = EditorView()
            .environment(LaunchItemStore.shared)

        let hosting = NSHostingController(rootView: root)
        hosting.sizingOptions = [.preferredContentSize, .minSize]

        let window = NSWindow(contentViewController: hosting)
        window.title = ""
        window.titleVisibility = .visible
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 440, height: 540))
        window.minSize = NSSize(width: 360, height: 300)
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.toolbarStyle = .unified
        window.center()
        window.delegate = self
        return window
    }

    func windowDidBecomeKey(_ notification: Notification) {
        window?.toolbar?.centeredItemIdentifiers = []
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}
