//
//  Menu2FAWidgetBundle.swift
//  Menu 2FA Widget
//

import SwiftUI
import WidgetKit

@main
struct Menu2FAWidgetBundle: WidgetBundle {
    init() {
        WidgetExtensionProbe.install()
    }

    var body: some Widget {
        AccountCodeWidget()
    }
}
