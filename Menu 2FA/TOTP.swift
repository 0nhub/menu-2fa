//
//  TOTP.swift
//  Menu 2FA
//

import CryptoKit
import Foundation

enum TOTP {
    static let period: TimeInterval = 30
    static let digits = 6

    static func normalizedSecret(_ raw: String) -> String {
        fields(from: raw).secret
    }

    static func fields(from raw: String) -> (secret: String, title: String?) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("otpauth://"),
           let components = URLComponents(string: trimmed) {
            let items = components.queryItems ?? []
            let secret = items.first(where: { $0.name.lowercased() == "secret" })?.value ?? ""
            let issuer = items.first(where: { $0.name.lowercased() == "issuer" })?.value
            let path = (components.path as NSString).pathComponents
                .filter { $0 != "/" }
                .joined(separator: "/")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let label = path.split(separator: ":").last.map(String.init)
            let title = [issuer, label].compactMap { $0?.nilIfEmpty }.first
            return (sanitize(secret), title)
        }
        return (sanitize(trimmed), nil)
    }

    static func isValidSecret(_ raw: String) -> Bool {
        let secret = fields(from: raw).secret
        guard secret.count >= 8, let data = decodeBase32(secret), !data.isEmpty else {
            return false
        }
        return true
    }

    static func remaining(at date: Date = .now, period: TimeInterval = period) -> TimeInterval {
        let elapsed = date.timeIntervalSince1970.truncatingRemainder(dividingBy: period)
        return period - elapsed
    }

    static func progress(at date: Date = .now, period: TimeInterval = period) -> Double {
        remaining(at: date, period: period) / period
    }

    static func code(for rawSecret: String, at date: Date = .now, period: TimeInterval = period, digits: Int = digits) -> String? {
        let secret = fields(from: rawSecret).secret
        guard let keyData = decodeBase32(secret), !keyData.isEmpty else { return nil }

        var counter = UInt64(floor(date.timeIntervalSince1970 / period)).bigEndian
        let counterData = Data(bytes: &counter, count: MemoryLayout<UInt64>.size)
        let mac = HMAC<Insecure.SHA1>.authenticationCode(for: counterData, using: SymmetricKey(data: keyData))
        let hash = Data(mac)
        let offset = Int(hash[hash.count - 1] & 0x0f)
        let binary =
            (UInt32(hash[offset] & 0x7f) << 24)
            | (UInt32(hash[offset + 1]) << 16)
            | (UInt32(hash[offset + 2]) << 8)
            | UInt32(hash[offset + 3])
        let otp = binary % UInt32(pow(10.0, Double(digits)))
        return String(format: "%0*u", digits, otp)
    }

    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
    private static let alphabetSet = Set(alphabet)

    private static func sanitize(_ raw: String) -> String {
        raw.uppercased().filter { alphabetSet.contains($0) }
    }

    private static func decodeBase32(_ string: String) -> Data? {
        let normalized = sanitize(string)
        guard !normalized.isEmpty else { return nil }

        var buffer = 0
        var bitsLeft = 0
        var output = [UInt8]()

        for character in normalized {
            guard let value = alphabet.firstIndex(of: character) else { return nil }
            buffer = (buffer << 5) | value
            bitsLeft += 5
            if bitsLeft >= 8 {
                bitsLeft -= 8
                output.append(UInt8((buffer >> bitsLeft) & 0xff))
            }
        }

        return output.isEmpty ? nil : Data(output)
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
