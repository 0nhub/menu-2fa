//
//  EditorWindowController.swift
//  Menu 2FA
//

import AppKit
import SwiftUI

@MainActor
final class EditorWindowController: NSObject, NSWindowDelegate, NSToolbarDelegate {
    static let shared = EditorWindowController()

    private static let contentSize = NSSize(width: 480, height: 560)
    private static let toolbarIdentifier = NSToolbar.Identifier("Menu2FASettings")

    private var window: NSWindow?

    func orderOut() {
        window?.orderOut(nil)
    }

    func windowForPurchase() -> NSWindow {
        let created = window == nil
        if window == nil {
            window = makeWindow()
        }
        let window = window!
        applyFixedChrome(window)
        if created {
            refreshToolbar(isPro: ProStore.shared.isPro)
            select(.upgrade)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return window
    }

    func show(skipAuthentication: Bool = false, pane: SettingsPane = .twofa) {
        if skipAuthentication {
            showUnlocked(pane: pane)
            return
        }
        AppLock.authorizeIfNeeded(reason: String(localized: "Authenticate to open Settings")) { [weak self] allowed in
            DispatchQueue.main.async {
                guard allowed else { return }
                self?.showUnlocked(pane: pane)
            }
        }
    }

    private func showUnlocked(pane: SettingsPane = .twofa) {
        if window == nil {
            window = makeWindow()
        }

        guard let window else { return }

        applyFixedChrome(window)
        refreshToolbar(isPro: ProStore.shared.isPro)
        select(resolvedPane(pane))
        window.orderFrontRegardless()
        DispatchQueue.main.async { [weak window] in
            guard let window else { return }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(window.contentView)
        }
    }

    private func makeWindow() -> NSWindow {
        let root = SettingsView()
            .environment(LaunchItemStore.shared)
            .environment(ProStore.shared)

        let hosting = NSHostingController(rootView: root)
        hosting.sizingOptions = []

        let window = NSWindow(contentViewController: hosting)
        window.title = SettingsPane.twofa.title
        window.titleVisibility = .visible
        window.styleMask = [.titled, .closable]
        window.setContentSize(Self.contentSize)
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.toolbarStyle = .preference
        window.toolbar = makeToolbar()
        applyFixedChrome(window)
        window.center()
        window.delegate = self
        return window
    }

    private func applyFixedChrome(_ window: NSWindow) {
        window.styleMask = [.titled, .closable]
        window.setContentSize(Self.contentSize)
        window.collectionBehavior = [.moveToActiveSpace]
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
    }

    private func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: Self.toolbarIdentifier)
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.selectedItemIdentifier = SettingsPane.twofa.toolbarIdentifier
        return toolbar
    }

    func refreshToolbar(isPro: Bool) {
        guard let window else { return }
        if isPro, SettingsNavigation.shared.pane == .upgrade {
            SettingsNavigation.shared.pane = .twofa
        }
        window.toolbar = makeToolbar()
        window.title = SettingsNavigation.shared.pane.title
        window.toolbar?.selectedItemIdentifier = SettingsNavigation.shared.pane.toolbarIdentifier
    }

    private func resolvedPane(_ pane: SettingsPane) -> SettingsPane {
        if pane == .upgrade, ProStore.shared.isPro {
            return .twofa
        }
        return pane
    }

    private func select(_ pane: SettingsPane) {
        let pane = resolvedPane(pane)
        SettingsNavigation.shared.pane = pane
        window?.title = pane.title
        window?.toolbar?.selectedItemIdentifier = pane.toolbarIdentifier
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsPane.visible(isPro: ProStore.shared.isPro).map(\.toolbarIdentifier)
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsPane.visible(isPro: ProStore.shared.isPro).map(\.toolbarIdentifier)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let pane = SettingsPane.pane(for: itemIdentifier) else { return nil }
        return makePaneItem(pane)
    }

    private func makePaneItem(_ pane: SettingsPane) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: pane.toolbarIdentifier)
        item.label = pane.title
        item.paletteLabel = pane.title
        item.toolTip = pane.title
        item.image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: pane.title)
        item.target = self
        item.action = #selector(selectPane(_:))
        return item
    }

    @objc
    private func selectPane(_ sender: NSToolbarItem) {
        guard let pane = SettingsPane.pane(for: sender.itemIdentifier) else { return }
        select(pane)
    }
}
