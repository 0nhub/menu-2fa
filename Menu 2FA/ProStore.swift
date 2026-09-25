//
//  ProStore.swift
//  Menu 2FA
//

import AppKit
import Foundation
import StoreKit
import WidgetKit
#if DEBUG
import Darwin
import ObjectiveC
#endif

@MainActor
@Observable
final class ProStore {
    static let shared = ProStore()
    static let productID = "ga.sgroi.menu2fa.pro"

    var isPro = false
    var product: Product?
    var isBusy = false

    @ObservationIgnored
    private var updatesTask: Task<Void, Never>?

    private init() {}

    func start() {
        guard updatesTask == nil else { return }
        #if DEBUG
        LocalStoreKit.install()
        #endif
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = result, transaction.productID == Self.productID {
                    await transaction.finish()
                    await self.refreshEntitlements()
                    EditorWindowController.shared.refreshToolbar(isPro: self.isPro)
                }
            }
        }
        Task {
            await loadProduct()
            await refreshEntitlements()
        }
    }

    func loadProduct() async {
        do {
            let products = try await Product.products(for: [Self.productID])
            product = products.first
            if product == nil {
                NSLog("Menu 2FA: Pro product not returned from StoreKit (id: \(Self.productID))")
            }
        } catch {
            NSLog("Menu 2FA: failed to load Pro product: \(error.localizedDescription)")
        }
    }

    func refreshEntitlements() async {
        if Self.debugSimulatePro {
            isPro = true
            publishProState()
            return
        }
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.productID == Self.productID {
                isPro = transaction.revocationDate == nil
                publishProState()
                return
            }
        }
        isPro = false
        publishProState()
    }

    private func publishProState() {
        LaunchItemStore.shared.applyProAccess()
        SharedAccountStore.setProUnlocked(isPro)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Set env `MENU_2FA_DEBUG_PRO=1` when launching to test iCloud sync without a purchase.
    private static var debugSimulatePro: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["MENU_2FA_DEBUG_PRO"] == "1"
        #else
        false
        #endif
    }

    func purchase() async {
        #if DEBUG
        if !LocalStoreKit.isActive {
            LocalStoreKit.install()
        }
        #endif
        if product == nil {
            await loadProduct()
        }
        guard let product else {
            Self.presentError(String(localized: "2FA Pro is not available right now."))
            return
        }

        #if DEBUG
        guard LocalStoreKit.isActive else {
            Self.presentError(String(localized: "2FA Pro is not available right now."))
            return
        }
        #endif

        isBusy = true
        defer { isBusy = false }

        let previousPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        let window = EditorWindowController.shared.windowForPurchase()
        defer {
            if previousPolicy != .regular {
                NSApp.setActivationPolicy(previousPolicy)
                window.makeKeyAndOrderFront(nil)
            }
        }

        do {
            let result: Product.PurchaseResult
            if #available(macOS 15.2, *) {
                result = try await product.purchase(confirmIn: window)
            } else {
                result = try await product.purchase()
            }
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    await refreshEntitlements()
                    EditorWindowController.shared.refreshToolbar(isPro: isPro)
                } else {
                    Self.presentError(String(localized: "Couldn't complete the purchase."))
                }
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            Self.presentError(error.localizedDescription)
        }
    }

    func restore() async {
        isBusy = true
        defer { isBusy = false }

        #if DEBUG
        await refreshEntitlements()
        EditorWindowController.shared.refreshToolbar(isPro: isPro)
        if !isPro {
            Self.presentError(String(localized: "No 2FA Pro purchase to restore."))
        }
        return
        #endif

        let previousPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        let window = EditorWindowController.shared.windowForPurchase()
        defer {
            if previousPolicy != .regular {
                NSApp.setActivationPolicy(previousPolicy)
                window.makeKeyAndOrderFront(nil)
            }
        }

        do {
            try await AppStore.sync()
            await refreshEntitlements()
            EditorWindowController.shared.refreshToolbar(isPro: isPro)
            if !isPro {
                Self.presentError(String(localized: "No 2FA Pro purchase to restore."))
            }
        } catch {
            Self.presentError(error.localizedDescription)
        }
    }

    var upgradeTitle: String {
        if let product {
            return String(format: String(localized: "Upgrade — %@"), product.displayPrice)
        }
        return String(localized: "Upgrade")
    }

    private static func presentError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "2FA Pro")
        alert.informativeText = message
        let window = EditorWindowController.shared.windowForPurchase()
        alert.beginSheetModal(for: window)
    }
}

#if DEBUG
enum LocalStoreKit {
    private static var session: NSObject?
    static var isActive: Bool { session != nil }

    /// Points StoreKit at Configuration.storekit so Buy stays in the local
    /// test store. The live App Store purchase sheet signs the Mac into an Apple Account.
    static func install() {
        guard session == nil else { return }
        let binary = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Frameworks/StoreKitTest.framework/Versions/A/StoreKitTest")
        guard FileManager.default.fileExists(atPath: binary.path) else { return }
        guard dlopen(binary.path, RTLD_NOW) != nil else { return }
        guard let storeURL = Bundle.main.url(forResource: "Configuration", withExtension: "storekit") else { return }
        guard let sessionClass = NSClassFromString("SKTestSession") else { return }
        guard let bundleIvar = class_getInstanceVariable(sessionClass, "_bundleID") else { return }

        let allocSelector = sel_registerName("alloc")
        guard let allocMethod = class_getClassMethod(sessionClass, allocSelector) else { return }
        typealias AllocFunction = @convention(c) (AnyClass, Selector) -> AnyObject
        let allocate = unsafeBitCast(method_getImplementation(allocMethod), to: AllocFunction.self)
        let allocated = allocate(sessionClass, allocSelector)
        let bundleID = (Bundle.main.bundleIdentifier ?? "ga.sgroi.menu-2fa") as NSString
        object_setIvar(allocated, bundleIvar, bundleID)

        let initSelector = sel_registerName("initWithContentsOfURL:error:")
        guard let initMethod = class_getInstanceMethod(sessionClass, initSelector) else { return }
        typealias InitFunction = @convention(c) (AnyObject, Selector, NSURL, UnsafeMutablePointer<NSError?>?) -> AnyObject?
        let initialize = unsafeBitCast(method_getImplementation(initMethod), to: InitFunction.self)
        var error: NSError?
        guard let created = initialize(allocated, initSelector, storeURL as NSURL, &error) as? NSObject else {
            return
        }
        created.setValue(false, forKey: "disableDialogs")
        created.setValue("DEU", forKey: "storefront")
        session = created
    }
}
#endif
