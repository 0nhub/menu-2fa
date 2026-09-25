//
//  CopyTOTPIntent.swift
//  Menu 2FA
//

import AppIntents

struct CopyTOTPIntent: AppIntent {
    static var title: LocalizedStringResource = "Copy 2FA Code"
    static var description = IntentDescription("Copy the current code for an account to the clipboard.")
    static var openAppWhenRun = false
    static var isDiscoverable = false

    static var parameterSummary: some ParameterSummary {
        Summary("Copy code for \(\.$accountID)")
    }

    @Parameter(title: "Account")
    var accountID: String

    init() {
        accountID = ""
    }

    init(accountID: String) {
        self.accountID = accountID
    }

    init(accountID: UUID) {
        self.accountID = accountID.uuidString
    }

    func perform() async throws -> some IntentResult {
        guard SharedAccountStore.isProUnlocked else { return .result() }
        guard let stored = resolveAccount(), TOTP.code(for: stored.secret) != nil else {
            return .result()
        }
        SharedAccountStore.markWidgetCopied(accountID: stored.id.uuidString)
        WidgetCopyBridge.requestCopy(accountID: stored.id.uuidString)
        WidgetCopyBridge.deliverPendingCopy()
        return .result()
    }

    private func resolveAccount() -> SharedAccount? {
        if let uuid = UUID(uuidString: accountID), let match = SharedAccountStore.account(id: uuid) {
            return match
        }
        return SharedAccountStore.account(named: accountID)
    }
}
