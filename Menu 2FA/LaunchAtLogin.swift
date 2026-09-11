//
//  LaunchAtLogin.swift
//  Menu 2FA
//

import AppKit
import ServiceManagement

enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func toggle() {
        do {
            if isEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Menu 2FA: Launch at Login failed: \(error.localizedDescription)")
        }
    }
}

enum ContextMenuRow: CaseIterable {
    case settings
    case requireAuthentication
    case launchAtLogin
    case support
    case moreApps
    case quit

    var title: String {
        switch self {
        case .settings: return String(localized: "Settings")
        case .requireAuthentication: return String(localized: "Require Authentication")
        case .launchAtLogin: return String(localized: "Launch at Login")
        case .support: return String(localized: "Support")
        case .moreApps: return String(localized: "More Apps")
        case .quit: return String(localized: "Quit")
        }
    }

    var accessory: String {
        switch self {
        case .settings: return "⌘,"
        case .requireAuthentication: return AppLock.isEnabled ? "✓" : ""
        case .launchAtLogin: return LaunchAtLogin.isEnabled ? "✓" : ""
        case .support, .moreApps: return ""
        case .quit: return "⌘Q"
        }
    }

    static let supportURL = URL(string: "https://sgroi.ga/Support/menu-2fa/")!
    static let moreAppsURL = URL(string: "https://apps.apple.com/developer/gabriel-sgroi/id6799928916")!

    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func menuItem() -> NSMenuItem {
        let titleWidth = (title as NSString).size(withAttributes: [.font: NSFont.menuFont(ofSize: 0)]).width
        let width = max(220, ceil(titleWidth) + 88)
        let item = NSMenuItem()
        let view = ContextMenuRowView(row: self, frame: NSRect(x: 0, y: 0, width: width, height: 22))
        view.autoresizingMask = [.width]
        item.view = view
        return item
    }
}

/// Shared row drawing so every label uses the same left edge.
private final class ContextMenuRowView: NSView {
    private let row: ContextMenuRow
    private var isHighlighted = false
    private var trackingArea: NSTrackingArea?

    private let titleLeading: CGFloat = 14
    private let accessoryTrailing: CGFloat = 14

    init(row: ContextMenuRow, frame: NSRect) {
        self.row = row
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHighlighted = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHighlighted = false
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        switch row {
        case .settings:
            enclosingMenuItem?.menu?.cancelTracking()
            EditorWindowController.shared.show()
        case .requireAuthentication:
            AppLock.toggle { [weak self] in
                self?.needsDisplay = true
            }
        case .launchAtLogin:
            LaunchAtLogin.toggle()
            needsDisplay = true
        case .support:
            enclosingMenuItem?.menu?.cancelTracking()
            ContextMenuRow.open(ContextMenuRow.supportURL)
        case .moreApps:
            enclosingMenuItem?.menu?.cancelTracking()
            ContextMenuRow.open(ContextMenuRow.moreAppsURL)
        case .quit:
            enclosingMenuItem?.menu?.cancelTracking()
            NSApp.terminate(nil)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHighlighted {
            NSColor.selectedContentBackgroundColor.setFill()
            bounds.fill()
        }

        let titleColor: NSColor = isHighlighted ? .selectedMenuItemTextColor : .labelColor
        let accessoryColor: NSColor = isHighlighted ? .selectedMenuItemTextColor : .secondaryLabelColor
        let font = NSFont.menuFont(ofSize: 0)

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: titleColor,
        ]
        let accessoryAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: accessoryColor,
        ]

        let isRTL = userInterfaceLayoutDirection == .rightToLeft
        let title = row.title as NSString
        let titleSize = title.size(withAttributes: titleAttributes)
        let titleY = (bounds.height - titleSize.height) / 2
        let titleX = isRTL
            ? bounds.width - titleSize.width - titleLeading
            : titleLeading
        title.draw(at: NSPoint(x: titleX, y: titleY), withAttributes: titleAttributes)

        let accessory = row.accessory as NSString
        if accessory.length > 0 {
            let accessorySize = accessory.size(withAttributes: accessoryAttributes)
            let accessoryX = isRTL
                ? accessoryTrailing
                : bounds.width - accessorySize.width - accessoryTrailing
            accessory.draw(at: NSPoint(x: accessoryX, y: titleY), withAttributes: accessoryAttributes)
        }
    }
}
