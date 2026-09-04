//
//  IconURLFetcher.swift
//  Menu 2FA
//

import AppKit
import Foundation

enum IconURLFetcher {
    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "ico", "icns", "bmp", "tif", "tiff", "svg"
    ]

    static func normalizedURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if LaunchItem.normalizedEmoji(trimmed) != nil, !trimmed.contains(".") {
            return nil
        }

        if let url = URL(string: trimmed), url.scheme != nil, isUsableHost(url.host) {
            return url
        }
        if let url = URL(string: "https://\(trimmed)"), isUsableHost(url.host) {
            return url
        }
        return nil
    }

    private static func isUsableHost(_ host: String?) -> Bool {
        guard let host, !host.isEmpty else { return false }
        return host.contains(".") || host == "localhost"
    }

    static func fetchIcon(from raw: String) async -> Data? {
        guard let pageURL = normalizedURL(from: raw) else { return nil }

        if looksLikeDirectImage(pageURL), let data = await downloadImageData(from: pageURL) {
            return pngData(from: data)
        }

        guard let host = pageURL.host, !host.isEmpty else { return nil }

        let candidates: [URL?] = [
            URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=128"),
            URL(string: "https://icons.duckduckgo.com/ip3/\(host).ico"),
            URL(string: "\(pageURL.scheme ?? "https")://\(host)/apple-touch-icon.png"),
            URL(string: "\(pageURL.scheme ?? "https")://\(host)/favicon.ico"),
        ]

        for candidate in candidates.compactMap({ $0 }) {
            if let data = await downloadImageData(from: candidate),
               let png = pngData(from: data) {
                return png
            }
        }
        return nil
    }

    private static func looksLikeDirectImage(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return imageExtensions.contains(ext)
    }

    private static func downloadImageData(from url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("Menu2FA/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            guard !data.isEmpty, NSImage(data: data) != nil else { return nil }
            return data
        } catch {
            return nil
        }
    }

    private static func pngData(from data: Data) -> Data? {
        guard let image = NSImage(data: data) else { return nil }
        let resized = resized(image, to: 256)
        guard let tiff = resized.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return rep.representation(using: .png, properties: [:])
    }

    private static func resized(_ image: NSImage, to maxEdge: CGFloat) -> NSImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxEdge, longest > 0 else { return image }

        let scale = maxEdge / longest
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let output = NSImage(size: size)
        output.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: size))
        output.unlockFocus()
        return output
    }
}
