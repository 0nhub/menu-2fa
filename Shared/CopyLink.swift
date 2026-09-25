import Foundation

enum CopyLink {
    static let scheme = "menu-2fa"

    static func url(accountID: String) -> URL? {
        guard !accountID.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = "copy"
        components.path = "/\(accountID)"
        return components.url
    }

    static func accountID(from url: URL) -> String? {
        guard url.scheme == scheme, url.host == "copy" else { return nil }
        let identifier = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return identifier.isEmpty ? nil : identifier
    }
}
