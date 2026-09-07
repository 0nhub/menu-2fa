//
//  StatusItemController.swift
//  Menu 2FA
//

import AppKit
import QuartzCore

final class StatusItemController: NSObject {
    private let store: LaunchItemStore
    private var statusItem: NSStatusItem?
    private var isPresentingMenu = false
    private var isShowingCopyFeedback = false
    private var lockImage: NSImage?
    private var checkImage: NSImage?
    private var countdownView: CountdownRingView?
    private var feedbackResetWorkItem: DispatchWorkItem?

    init(store: LaunchItemStore) {
        self.store = store
        super.init()
    }

    func install() {
        // Keep a strong reference first; some launch timing issues drop the item otherwise.
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item

        guard let button = item.button else {
            // Retry once on the next turn if the status bar button is not ready yet.
            DispatchQueue.main.async { [weak self] in
                self?.configureStatusButton()
            }
            return
        }
        configure(button: button)
    }

    private func configureStatusButton() {
        guard let button = statusItem?.button else { return }
        configure(button: button)
    }

    private func configure(button: NSStatusBarButton) {
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let lock = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: String(localized: "Menu 2FA"))?.withSymbolConfiguration(configuration)
        lock?.isTemplate = true
        lockImage = lock

        let check = NSImage(systemSymbolName: "checkmark", accessibilityDescription: String(localized: "Copied"))?.withSymbolConfiguration(configuration)
        check?.isTemplate = true
        checkImage = check

        button.image = lock
        button.title = ""
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = String(localized: "Menu 2FA")
        button.setAccessibilityTitle(String(localized: "Menu 2FA"))
        button.wantsLayer = true
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        button.action = #selector(handleClick(_:))
        button.target = self
    }

    func showSettings() {
        EditorWindowController.shared.show()
    }

    @objc
    private func handleClick(_ sender: NSStatusBarButton) {
        if isPresentingMenu { return }
        guard let event = NSApp.currentEvent else { return }

        cancelCopyFeedback(restoreKey: true)

        let isContextClick = event.type == .rightMouseDown || event.modifierFlags.contains(.control)
        let showCodes = !isContextClick && !store.items.isEmpty

        if showCodes && AppLock.isEnabled {
            isPresentingMenu = true
            AppLock.authenticate(reason: String(localized: "Authenticate to view your codes")) { [weak self] success in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isPresentingMenu = false
                    guard success else { return }
                    self.presentMenu(self.makeCodesMenu(), from: sender, showCountdown: true)
                }
            }
            return
        }

        let menu = showCodes ? makeCodesMenu() : makeContextMenu()
        presentMenu(menu, from: sender, showCountdown: showCodes)
    }

    private func presentMenu(_ menu: NSMenu, from sender: NSStatusBarButton, showCountdown: Bool) {
        isPresentingMenu = true
        if showCountdown {
            beginCountdown()
        }
        statusItem?.menu = menu
        sender.performClick(nil)
        statusItem?.menu = nil
        endCountdown()
        isPresentingMenu = false
    }

    @objc
    private func copyFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let id = UUID(uuidString: raw),
              let item = store.items.first(where: { $0.id == id })
        else { return }

        guard store.copyCode(item) else { return }

        // Show the checkmark immediately on click — don't wait for menu dismiss.
        showCopyFeedback()
        statusItem?.menu?.cancelTracking()
    }

    private func makeCodesMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        for item in store.items {
            let menuItem = NSMenuItem(
                title: item.name,
                action: #selector(copyFromMenu(_:)),
                keyEquivalent: ""
            )
            menuItem.target = self
            menuItem.representedObject = item.id.uuidString
            menuItem.isEnabled = store.currentCode(for: item) != nil
            menuItem.image = item.menuIcon(size: 16)
            menuItem.toolTip = String(localized: "Copy code")
            menuItem.keyEquivalentModifierMask = []
            menu.addItem(menuItem)
        }

        return menu
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(ContextMenuRow.settings.menuItem())
        menu.addItem(ContextMenuRow.requireAuthentication.menuItem())
        menu.addItem(ContextMenuRow.launchAtLogin.menuItem())
        menu.addItem(ContextMenuRow.quit.menuItem())
        return menu
    }

    private func beginCountdown() {
        guard let button = statusItem?.button else { return }
        button.image = nil
        button.title = ""
        let ring = CountdownRingView(frame: button.bounds)
        ring.autoresizingMask = [.width, .height]
        button.addSubview(ring)
        ring.start()
        countdownView = ring
    }

    private func endCountdown() {
        countdownView?.stop()
        countdownView?.removeFromSuperview()
        countdownView = nil
        if !isShowingCopyFeedback {
            restoreIdleAppearance()
        }
    }

    private func showCopyFeedback() {
        guard let button = statusItem?.button, let checkImage else {
            restoreIdleAppearance()
            return
        }

        countdownView?.stop()
        countdownView?.removeFromSuperview()
        countdownView = nil

        feedbackResetWorkItem?.cancel()
        isShowingCopyFeedback = true
        button.title = ""
        button.image = checkImage

        if let layer = button.layer {
            layer.removeAnimation(forKey: "copyFeedbackPop")
            let pop = CABasicAnimation(keyPath: "transform.scale")
            pop.fromValue = 0.72
            pop.toValue = 1
            pop.duration = 0.16
            pop.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(pop, forKey: "copyFeedbackPop")
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.isShowingCopyFeedback = false
            self.restoreIdleAppearance()
            self.feedbackResetWorkItem = nil
        }
        feedbackResetWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    private func cancelCopyFeedback(restoreKey: Bool) {
        feedbackResetWorkItem?.cancel()
        feedbackResetWorkItem = nil
        isShowingCopyFeedback = false
        statusItem?.button?.layer?.removeAnimation(forKey: "copyFeedbackPop")
        if restoreKey {
            restoreIdleAppearance()
        }
    }

    private func restoreIdleAppearance() {
        guard let button = statusItem?.button else { return }
        button.image = lockImage
        button.title = ""
        button.imagePosition = .imageOnly
    }
}

private final class CountdownRingView: NSView {
    private var displayLink: CADisplayLink?
    private var timer: Timer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { false }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    func start() {
        stop()
        needsDisplay = true

        let link = displayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .eventTracking)
        link.add(to: .main, forMode: .common)
        displayLink = link

        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .eventTracking)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        timer?.invalidate()
        timer = nil
    }

    @objc
    private func tick() {
        needsDisplay = true
        displayIfNeeded()
    }

    override func draw(_ dirtyRect: NSRect) {
        let elapsed = CGFloat(max(0, min(1, 1 - TOTP.progress())))
        let inset = bounds.insetBy(dx: 3, dy: 3)
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(inset.width, inset.height) / 2

        effectiveAppearance.performAsCurrentDrawingAppearance {
            let track = NSBezierPath()
            track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
            track.lineWidth = 1.8
            NSColor.labelColor.withAlphaComponent(0.22).setStroke()
            track.stroke()

            if elapsed > 0 {
                let sweep = NSBezierPath()
                sweep.appendArc(
                    withCenter: center,
                    radius: radius,
                    startAngle: 90,
                    endAngle: 90 - 360 * elapsed,
                    clockwise: true
                )
                sweep.lineWidth = 2
                sweep.lineCapStyle = .round
                NSColor.labelColor.setStroke()
                sweep.stroke()
            }
        }
    }
}
