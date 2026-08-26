//
//  SapphireAnalytics.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-10

import Firebase
import FirebaseAnalytics

enum SapphireAnalytics {
    private static let lock = NSLock()
    private static var isConfigured = false

    static var isEnabled: Bool {
        SettingsModel.shared.settings.googleAnalyticsEnabled
    }

    static func bootstrap() {
        lock.lock()
        defer { lock.unlock() }

        if !isConfigured {
            // Fork-only guard: GoogleService-Info.plist is gitignored upstream and absent from this
            // repo, and FirebaseApp.configure() traps without it. Unchanged when the plist is present.
            guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else { return }
            FirebaseApp.configure()
            isConfigured = true
        }
        applyCollectionPreference()
    }

    static func applyCollectionPreference() {
        guard isConfigured else { return }
        Analytics.setAnalyticsCollectionEnabled(isEnabled)
    }

    static func logEvent(_ name: String, parameters: [String: Any]? = nil) {
        guard isEnabled else { return }

        if !isConfigured {
            bootstrap()
        }
        guard isConfigured else { return }
        Analytics.logEvent(name, parameters: parameters)
    }
}