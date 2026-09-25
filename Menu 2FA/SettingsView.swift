//
//  SettingsView.swift
//  Menu 2FA
//

import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case twofa
    case general
    case upgrade

    var id: String { rawValue }

    var title: String {
        switch self {
        case .twofa: return String(localized: "2FA")
        case .general: return String(localized: "General")
        case .upgrade: return String(localized: "Upgrade")
        }
    }

    var symbol: String {
        switch self {
        case .twofa: return "lock.fill"
        case .general: return "gearshape"
        case .upgrade: return "star"
        }
    }

    static func visible(isPro: Bool) -> [SettingsPane] {
        isPro ? [.twofa, .general] : [.twofa, .general, .upgrade]
    }

    var toolbarIdentifier: NSToolbarItem.Identifier {
        NSToolbarItem.Identifier(rawValue)
    }

    static func pane(for identifier: NSToolbarItem.Identifier) -> SettingsPane? {
        allCases.first { $0.toolbarIdentifier == identifier }
    }
}

@Observable
final class SettingsNavigation {
    static let shared = SettingsNavigation()
    var pane: SettingsPane = .twofa
}

struct SettingsView: View {
    var body: some View {
        SettingsShell(navigation: SettingsNavigation.shared)
    }
}

private struct SettingsShell: View {
    @Bindable var navigation: SettingsNavigation
    @Environment(ProStore.self) private var pro

    var body: some View {
        Group {
            switch navigation.pane {
            case .twofa:
                EditorView()
            case .general:
                GeneralPane()
            case .upgrade:
                UpgradeSettingsPane()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.windowBackground)
        .onChange(of: pro.isPro) { _, isPro in
            EditorWindowController.shared.refreshToolbar(isPro: isPro)
        }
    }
}

struct SettingsContent<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                content()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.windowBackground)
    }
}

struct SettingsRow<Accessory: View>: View {
    let title: String
    var description: String? = nil
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 12) {
                Text(title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                accessory()
            }
            if let description {
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SettingsGroup<Content: View>: View {
    let title: String
    var description: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            VStack(alignment: .leading, spacing: 14) {
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            if let description {
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct UpgradeSettingsPane: View {
    @Environment(ProStore.self) private var pro

    var body: some View {
        SettingsContent {
            VStack(alignment: .leading, spacing: 8) {
                Text("Pro")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .center)

                VStack(alignment: .leading, spacing: 14) {
                    upgradeFeature(
                        symbol: "macwindow",
                        title: String(localized: "Desktop Widgets"),
                        detail: String(localized: "Copy a code from a widget on the desktop.")
                    )
                    upgradeFeature(
                        symbol: "icloud",
                        title: String(localized: "iCloud Sync"),
                        detail: String(localized: "Optional. Keeps your accounts on your other Macs.")
                    )

                    VStack(spacing: 8) {
                        Button {
                            Task { await pro.purchase() }
                        } label: {
                            Text(pro.upgradeTitle)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(pro.isBusy)

                        Button("Restore Purchases") {
                            Task { await pro.restore() }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .disabled(pro.isBusy)
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.top, 4)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .task {
            await pro.loadProduct()
        }
    }

    private func upgradeFeature(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .center)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
