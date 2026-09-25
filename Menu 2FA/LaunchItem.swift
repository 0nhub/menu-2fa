//
//  LaunchItem.swift
//  Menu 2FA
//

import AppKit

struct LaunchItem: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var name: String
    var secret: String
    var iconData: Data?
    /// Single emoji used when no custom image is set.
    var emoji: String?
    /// Optional site URL kept as a note; also used to fetch a fallback icon.
    var url: String?
    /// Favicon loaded from `url`, used only when no image or emoji is set.
    var urlIconData: Data?

    init(
        id: UUID = UUID(),
        name: String,
        secret: String,
        iconData: Data? = nil,
        emoji: String? = nil,
        url: String? = nil,
        urlIconData: Data? = nil
    ) {
        self.id = id
        self.name = name
        self.secret = secret
        self.iconData = iconData
        self.emoji = Self.normalizedEmoji(emoji)
        self.url = url?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.urlIconData = urlIconData
    }

    var hasCustomImage: Bool {
        iconData != nil
    }

    var hasCustomOverride: Bool {
        iconData != nil || displayEmoji != nil
    }

    var displayEmoji: String? {
        Self.normalizedEmoji(emoji)
    }

    /// Custom image → emoji → URL favicon → lock.
    var icon: NSImage {
        displayIcon(size: 64)
    }

    func widgetIconPNG(size: CGFloat = 72) -> Data? {
        let image = Self.rasterizedForMenu(displayIcon(size: size), logicalSize: size)
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff)
        else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    func displayIcon(size: CGFloat) -> NSImage {
        if let iconData, let image = NSImage(data: iconData) {
            return Self.squared(image, size: size)
        }
        if let emoji = displayEmoji {
            return Self.emojiImage(emoji, size: size)
        }
        if let urlIconData, let image = NSImage(data: urlIconData) {
            return Self.squared(image, size: size)
        }
        return Self.keyPlaceholder(size: size)
    }

    func menuIcon(size: CGFloat = 16) -> NSImage {
        Self.rasterizedForMenu(displayIcon(size: size), logicalSize: size)
    }

    static func normalizedEmoji(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // Keep the first extended grapheme cluster (one emoji / emoji sequence).
        guard let first = trimmed.first else { return nil }
        let value = String(first)
        return value.isEmpty ? nil : value
    }

    static func keyPlaceholder(size: CGFloat) -> NSImage {
        let output = NSImage(size: NSSize(width: size, height: size))
        output.lockFocus()

        let inset = size * 0.08
        let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: size * 0.2, yRadius: size * 0.2)
        NSColor.labelColor.withAlphaComponent(0.08).setFill()
        path.fill()

        let pointSize = max(9, size * 0.4)
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        if var symbol = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) {
            symbol = symbol.copy() as? NSImage ?? symbol
            symbol.isTemplate = true
            let symbolSize = symbol.size
            let drawRect = NSRect(
                x: (size - symbolSize.width) / 2,
                y: (size - symbolSize.height) / 2,
                width: symbolSize.width,
                height: symbolSize.height
            )
            symbol.draw(
                in: drawRect,
                from: .zero,
                operation: .sourceOver,
                fraction: 0.55,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high]
            )
        }

        output.unlockFocus()
        output.isTemplate = false
        return output
    }

    static func emojiImage(_ emoji: String, size: CGFloat) -> NSImage {
        let output = NSImage(size: NSSize(width: size, height: size))
        output.lockFocus()

        let fontSize = size * 0.62
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize)
        ]
        let string = NSAttributedString(string: emoji, attributes: attributes)
        let textSize = string.size()
        let origin = NSPoint(
            x: (size - textSize.width) / 2,
            y: (size - textSize.height) / 2
        )
        string.draw(at: origin)

        output.unlockFocus()
        output.isTemplate = false
        return output
    }

    private static func squared(_ image: NSImage, size: CGFloat) -> NSImage {
        let output = NSImage(size: NSSize(width: size, height: size))
        output.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(x: 0, y: 0, width: size, height: size),
            from: .zero,
            operation: .copy,
            fraction: 1.0
        )
        output.unlockFocus()
        return output
    }

    /// macOS 26+ hides many menu images (especially SF Symbols). Rasterize to a bitmap rep so icons stay visible.
    static func rasterizedForMenu(_ source: NSImage, logicalSize: CGFloat) -> NSImage {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let pixels = max(1, Int((logicalSize * scale).rounded(.up)))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels,
            pixelsHigh: pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return source
        }
        rep.size = NSSize(width: logicalSize, height: logicalSize)

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return source }
        NSGraphicsContext.current = context
        context.imageInterpolation = .high

        source.draw(
            in: NSRect(x: 0, y: 0, width: logicalSize, height: logicalSize),
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: false,
            hints: [.interpolation: NSImageInterpolation.high]
        )

        let menuImage = NSImage(size: NSSize(width: logicalSize, height: logicalSize))
        menuImage.addRepresentation(rep)
        menuImage.isTemplate = false
        return menuImage
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
