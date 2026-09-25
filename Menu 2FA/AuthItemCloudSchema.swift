//
//  AuthItemCloudSchema.swift
//  Menu 2FA
//

import Foundation

struct AuthItemRecord: Codable, Equatable {
    var id: UUID
    var name: String
    var secret: String
    var iconData: Data?
    var emoji: String?
    var url: String?
    var urlIconData: Data?

    init(_ item: LaunchItem) {
        id = item.id
        name = item.name
        secret = item.secret
        iconData = item.iconData
        emoji = item.emoji
        url = item.url
        urlIconData = item.urlIconData
    }

    func asLaunchItem() -> LaunchItem {
        LaunchItem(
            id: id,
            name: name,
            secret: secret,
            iconData: iconData,
            emoji: emoji,
            url: url,
            urlIconData: urlIconData
        )
    }
}

struct AuthItemCloudSchema: Codable, Equatable {
    static let currentVersion = 1

    var version: Int
    var updatedAt: Date
    var items: [AuthItemRecord]

    init(items: [LaunchItem], updatedAt: Date = Date()) {
        version = Self.currentVersion
        self.updatedAt = updatedAt
        self.items = items.map(AuthItemRecord.init)
    }

    static func materialize(
        _ records: [AuthItemRecord],
        onto local: [LaunchItem],
        keepUnmatched: Bool
    ) -> [LaunchItem] {
        var used = Set<UUID>()
        var result: [LaunchItem] = []

        for record in records {
            if let existing = local.first(where: { $0.id == record.id && !used.contains($0.id) }) {
                used.insert(existing.id)
                var merged = record.asLaunchItem()
                if merged.iconData == nil { merged.iconData = existing.iconData }
                if merged.urlIconData == nil { merged.urlIconData = existing.urlIconData }
                result.append(merged)
            } else {
                result.append(record.asLaunchItem())
                used.insert(record.id)
            }
        }

        guard keepUnmatched else { return result }

        for item in local where !used.contains(item.id) {
            result.append(item)
        }
        return result
    }
}
