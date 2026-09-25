//
//  GeneralSettings.swift
//  Menu 2FA
//

import SwiftUI

struct GeneralPane: View {
    @Environment(LaunchItemStore.self) private var store
    @Environment(ProStore.self) private var pro
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var requireAuthentication = AppLock.isEnabled
    @State private var iCloudSync = iCloudListSync.isEnabled

    var body: some View {
        SettingsContent {
            SettingsGroup(title: String(localized: "Startup")) {
                SettingsRow(
                    title: String(localized: "Launch at Login"),
                    description: String(localized: "Open 2FA when you log in.")
                ) {
                    Toggle("", isOn: launchAtLoginBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }

            SettingsGroup(title: String(localized: "iCloud")) {
                SettingsRow(
                    title: String(localized: "Sync Accounts"),
                    description: String(localized: "Optional. Keeps your accounts on your other Macs.")
                ) {
                    Toggle("", isOn: iCloudSyncBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }

            SettingsGroup(title: String(localized: "Security")) {
                SettingsRow(
                    title: String(localized: "Require Authentication"),
                    description: String(localized: "Ask for Touch ID or your Mac password before opening codes or Settings.")
                ) {
                    Toggle("", isOn: requireAuthenticationBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
        }
        .onAppear {
            launchAtLogin = LaunchAtLogin.isEnabled
            requireAuthentication = AppLock.isEnabled
            iCloudSync = store.syncsWithiCloud
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { _ in
                LaunchAtLogin.toggle()
                launchAtLogin = LaunchAtLogin.isEnabled
            }
        )
    }

    private var requireAuthenticationBinding: Binding<Bool> {
        Binding(
            get: { requireAuthentication },
            set: { target in
                guard target != requireAuthentication else { return }
                AppLock.toggle {
                    requireAuthentication = AppLock.isEnabled
                }
            }
        )
    }

    private var iCloudSyncBinding: Binding<Bool> {
        Binding(
            get: { pro.isPro && iCloudSync },
            set: { value in
                guard pro.isPro else {
                    EditorWindowController.shared.show(pane: .upgrade)
                    return
                }
                iCloudSync = value
                store.setSyncsWithiCloud(value)
            }
        )
    }
}
