//
//  IoTAIGlassesApp.swift
//  IoTAIGlasses
//
//  Created by joeyxyliu on 2026/10/10.
//

import SwiftUI

@main
struct IoTAIGlassesApp: App {
    @AppStorage(AppTheme.storageKey) private var theme: AppTheme = .soft

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(theme.colorScheme)
                .tint(Palette.accent)
        }
    }
}
