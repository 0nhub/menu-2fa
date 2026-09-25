//
//  AccountCodeWidget.swift
//  Menu 2FA Widget
//

import AppIntents
import AppKit
import ImageIO
import Intents
import SwiftUI
import WidgetKit

struct AccountCodeEntry: TimelineEntry {
    let date: Date
    let accountID: String
    let accountName: String
    let emoji: String
    let iconPNG: Data?
    let isLocked: Bool
    let isPro: Bool
    let showCopied: Bool
}

struct AccountCodeProvider: IntentTimelineProvider {
    func getSnapshot(for configuration: SelectAccountIntent, in context: Context, completion: @escaping (AccountCodeEntry) -> Void) {
        completion(makeEntry(from: configuration.account, at: .now))
    }

    func getTimeline(for configuration: SelectAccountIntent, in context: Context, completion: @escaping (Timeline<AccountCodeEntry>) -> Void) {
        let now = Date()
        let current = makeEntry(from: configuration.account, at: now)
        if current.showCopied {
            let hideAt = now.addingTimeInterval(2.5)
            let hidden = makeEntry(from: configuration.account, at: hideAt, showCopied: false)
            completion(Timeline(entries: [current, hidden], policy: .after(hideAt)))
        } else {
            completion(Timeline(entries: [current], policy: .never))
        }
    }

    func recommendations() -> [IntentRecommendation<SelectAccountIntent>] {
        SharedAccountStore.loadAccounts().map { account in
            let intent = SelectAccountIntent()
            intent.account = WidgetAccount(identifier: account.id.uuidString, display: account.name)
            return IntentRecommendation(intent: intent, description: account.name)
        }
    }

    func placeholder(in context: Context) -> AccountCodeEntry {
        makeEntry(from: nil, at: .now)
    }

    private func makeEntry(from selected: WidgetAccount?, at date: Date, showCopied forced: Bool? = nil) -> AccountCodeEntry {
        let accounts = SharedAccountStore.loadAccounts()
        let stored = accounts.first(where: { $0.id.uuidString == selected?.identifier })
            ?? accounts.first(where: { $0.name == selected?.displayString })
            ?? accounts.first
        let accountID = stored?.id.uuidString ?? ""
        let isPro = SharedAccountStore.isProUnlocked
        return AccountCodeEntry(
            date: date,
            accountID: accountID,
            accountName: stored?.name ?? "2FA",
            emoji: stored?.emoji ?? "",
            iconPNG: stored?.iconPNG ?? stored.flatMap { SharedAccountStore.iconFile(for: $0.id) },
            isLocked: SharedAccountStore.isAppLockEnabled,
            isPro: isPro,
            showCopied: isPro && (forced ?? SharedAccountStore.showsCopied(accountID: accountID, at: date))
        )
    }
}

struct AccountCodeWidget: Widget {
    static let kind = "ga.sgroi.menu-2fa.widget.code"

    var body: some WidgetConfiguration {
        IntentConfiguration(
            kind: Self.kind,
            intent: SelectAccountIntent.self,
            provider: AccountCodeProvider()
        ) { entry in
            AccountCodeWidgetView(entry: entry)
                .unredacted()
        }
        .configurationDisplayName("2FA")
        .description("Requires 2FA Pro. Choose which account this widget copies.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

struct AccountCodeWidgetView: View {
    var entry: AccountCodeEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Button(intent: CopyTOTPIntent(accountID: entry.accountID)) {
            face
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) {
            Color(nsColor: .windowBackgroundColor)
        }
        .unredacted()
    }

    private var face: some View {
        VStack(spacing: family == .systemMedium ? 8 : 6) {
            if entry.isPro {
                icon
            } else {
                Image(systemName: "lock.fill")
                    .font(.system(size: iconSize * 0.7, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            if !entry.isPro {
                Text("Pro")
                    .font(family == .systemMedium ? .title3.weight(.semibold) : .headline)
                    .foregroundStyle(.secondary)
            } else if entry.showCopied {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                    Text("Copied")
                }
                .font(family == .systemMedium ? .title3.weight(.semibold) : .headline)
                .foregroundStyle(.primary)
            } else {
                Text(entry.accountName)
                    .font(family == .systemMedium ? .title3.weight(.semibold) : .headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
            }
        }
        .unredacted()
    }

    private var icon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.accentColor.opacity(0.16))
            if let image = widgetImage(from: entry.iconPNG) {
                image
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: iconSize, height: iconSize)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else if !entry.emoji.isEmpty {
                Text(entry.emoji).font(.system(size: iconSize * 0.55))
            } else {
                Image(systemName: "lock.fill")
                    .font(.system(size: iconSize * 0.42, weight: .semibold))
            }
        }
        .frame(width: iconSize, height: iconSize)
        .clipped()
        .unredacted()
    }

    private func widgetImage(from data: Data?) -> Image? {
        guard let data, !data.isEmpty else { return nil }
        if let nsImage = NSImage(data: data) {
            var rect = NSRect(origin: .zero, size: nsImage.size)
            if let cgImage = nsImage.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
                return Image(decorative: cgImage, scale: 2, orientation: .up)
            }
        }
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            return Image(decorative: cgImage, scale: 2, orientation: .up)
        }
        return nil
    }

    private var iconSize: CGFloat {
        family == .systemMedium ? 44 : 36
    }
}
