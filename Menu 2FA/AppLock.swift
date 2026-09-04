//
//  AppLock.swift
//  Menu 2FA
//

import Foundation
import LocalAuthentication

enum AppLock {
    private static let storageKey = "requireAuthentication"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: storageKey) }
        set { UserDefaults.standard.set(newValue, forKey: storageKey) }
    }

    /// Touch ID when available, otherwise the Mac login password.
    static func authenticate(
        reason: String = String(localized: "Authenticate to access Menu 2FA"),
        completion: @escaping (Bool) -> Void
    ) {
        let context = LAContext()
        context.localizedCancelTitle = String(localized: "Cancel")

        var error: NSError?
        let policy = LAPolicy.deviceOwnerAuthentication
        guard context.canEvaluatePolicy(policy, error: &error) else {
            NSLog("Menu 2FA: LocalAuthentication unavailable: \(error?.localizedDescription ?? "unknown")")
            completion(false)
            return
        }

        context.evaluatePolicy(policy, localizedReason: reason) { success, evaluateError in
            if let evaluateError {
                NSLog("Menu 2FA: LocalAuthentication failed: \(evaluateError.localizedDescription)")
            }
            completion(success)
        }
    }

    /// Gates a privileged action. If locking is off, runs immediately.
    static func authorizeIfNeeded(
        reason: String = String(localized: "Authenticate to access Menu 2FA"),
        completion: @escaping (Bool) -> Void
    ) {
        guard isEnabled else {
            completion(true)
            return
        }
        authenticate(reason: reason, completion: completion)
    }

    /// Toggle preference. Enabling/disabling both require a successful system auth.
    static func toggle(completion: @escaping () -> Void) {
        let enabling = !isEnabled
        let reason = enabling
            ? String(localized: "Authenticate to enable app lock")
            : String(localized: "Authenticate to disable app lock")

        authenticate(reason: reason) { success in
            DispatchQueue.main.async {
                if success {
                    isEnabled = enabling
                }
                completion()
            }
        }
    }
}
